// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title PayPerTaskEscrow
 * @notice Pay-per-task escrow for AI Agents on Pharos.
 *         Buyer escrows PHRS for a task → Agent submits proof → Funds split
 *         between agent / platform / ecosystem.
 *
 *         Adapted from AgentMart (0G APAC Hackathon Track 3, March–May 2026)
 *         with hardening for Pharos:
 *         - dispute window with admin refund + admin resolve-in-favor
 *         - configurable split via constructor (validated to sum to 10_000)
 *         - per-order agent address (multi-agent marketplace, not single creator)
 *         - explicit task input/output hashes for proof binding
 *         - pull-payment fallback so a misbehaving fee recipient can never brick
 *           the agent's payout
 *
 * @dev    Designed as a Pharos Skill. See SKILL.md + references/payperask.md
 *         for the agent-facing operation guide (deposit / complete / dispute /
 *         refund / query history).
 */
contract PayPerTaskEscrow {
    enum OrderStatus {
        None,        // 0 — uninitialized slot
        Created,     // 1 — buyer escrowed funds, agent has not delivered
        Completed,   // 2 — agent submitted proof, funds released
        Disputed,    // 3 — buyer opened dispute within window
        Refunded     // 4 — admin refunded after dispute (or unclaimed escrow)
    }

    struct Order {
        address buyer;
        address agent;        // recipient of the creator share
        uint256 amount;
        OrderStatus status;
        bytes32 inputHash;    // task input fingerprint (set on createOrder)
        string  resultHash;   // delivery proof (set on completeOrder)
        uint64  createdAt;
    }

    // ── Config ──────────────────────────────────────────────────────────
    address public immutable admin;             // dispute resolver / refunder
    address public immutable platformRecipient; // platform fee
    address public immutable ecosystemRecipient;// ecosystem fee

    /// @dev Splits in basis points (out of 10_000). Must sum to 10_000.
    uint16 public immutable creatorBps;   // e.g. 8500 = 85%
    uint16 public immutable platformBps;  // e.g. 1000 = 10%
    uint16 public immutable ecosystemBps; // e.g.  500 =  5%

    /// @dev Time window during which the buyer can open a dispute.
    uint64 public constant DISPUTE_WINDOW = 7 days;

    /// @dev Bounded gas forwarded to recipient `call` on payouts. Enough for an
    ///      EOA or a simple receive() hook; not enough for a recipient to do
    ///      meaningful storage writes that could grief other orders.
    uint256 private constant SEND_GAS_LIMIT = 50_000;

    // ── State ──────────────────────────────────────────────────────────
    uint256 public nextOrderId;
    mapping(uint256 => Order) public orders;

    /// @notice Pull-payment ledger. If a `_send` fails (recipient is a
    ///         contract that reverts on receive, runs out of gas, etc.) the
    ///         credit lands here and the recipient can withdraw later. This
    ///         guarantees `completeOrder` cannot be permanently bricked by a
    ///         misbehaving platform/ecosystem recipient.
    mapping(address => uint256) public pendingWithdrawals;

    // ── Events ─────────────────────────────────────────────────────────
    event OrderCreated(uint256 indexed orderId, address indexed buyer, address indexed agent, uint256 amount, bytes32 inputHash);
    event OrderCompleted(uint256 indexed orderId, string resultHash, uint256 paidToAgent, uint256 paidToPlatform, uint256 paidToEcosystem);
    event OrderDisputed(uint256 indexed orderId, address indexed buyer, string reason);
    event OrderRefunded(uint256 indexed orderId, address indexed buyer, uint256 amount);
    event PaymentDeferred(address indexed recipient, uint256 amount);
    event PaymentWithdrawn(address indexed recipient, uint256 amount);

    // ── Errors ─────────────────────────────────────────────────────────
    error ZeroAmount();
    error ZeroAddress();
    error BadAgent();
    error InvalidStatus();
    error NotAuthorized();
    error DisputeWindowClosed();
    error InvalidSplit();
    error TransferFailed();
    error NothingToWithdraw();

    // ── Modifiers ──────────────────────────────────────────────────────
    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAuthorized();
        _;
    }

    constructor(
        address admin_,
        address platform_,
        address ecosystem_,
        uint16 creatorBps_,
        uint16 platformBps_,
        uint16 ecosystemBps_
    ) {
        if (admin_ == address(0) || platform_ == address(0) || ecosystem_ == address(0)) revert ZeroAddress();
        if (uint256(creatorBps_) + platformBps_ + ecosystemBps_ != 10_000) revert InvalidSplit();
        admin = admin_;
        platformRecipient = platform_;
        ecosystemRecipient = ecosystem_;
        creatorBps = creatorBps_;
        platformBps = platformBps_;
        ecosystemBps = ecosystemBps_;
    }

    /**
     * @notice Buyer escrows PHRS for a task delivered by `agent`.
     * @param  agent     Address that will receive the creator share on completion.
     * @param  inputHash Hash of the task inputs (e.g. keccak256 of the prompt).
     * @return orderId   Auto-incrementing order id.
     */
    function createOrder(address agent, bytes32 inputHash) external payable returns (uint256 orderId) {
        if (msg.value == 0) revert ZeroAmount();
        if (agent == address(0)) revert ZeroAddress();
        if (agent == address(this)) revert BadAgent();

        orderId = nextOrderId++;
        orders[orderId] = Order({
            buyer:      msg.sender,
            agent:      agent,
            amount:     msg.value,
            status:     OrderStatus.Created,
            inputHash:  inputHash,
            resultHash: "",
            createdAt:  uint64(block.timestamp)
        });

        emit OrderCreated(orderId, msg.sender, agent, msg.value, inputHash);
    }

    /**
     * @notice Agent (or admin) submits delivery proof → funds released by split.
     * @dev    Admin can also call `completeOrder` on a Disputed order to resolve
     *         in the agent's favor; otherwise admin uses `refundOrder`.
     */
    function completeOrder(uint256 orderId, string calldata resultHash) external {
        Order storage o = orders[orderId];

        bool isAdmin = msg.sender == admin;
        // Created → agent or admin may complete. Disputed → only admin (resolves in agent's favor).
        if (o.status == OrderStatus.Created) {
            if (msg.sender != o.agent && !isAdmin) revert NotAuthorized();
        } else if (o.status == OrderStatus.Disputed) {
            if (!isAdmin) revert NotAuthorized();
        } else {
            revert InvalidStatus();
        }

        // Effects (CEI): flip status before any external call.
        o.status = OrderStatus.Completed;
        o.resultHash = resultHash;

        uint256 toAgent     = (o.amount * creatorBps)   / 10_000;
        uint256 toPlatform  = (o.amount * platformBps)  / 10_000;
        uint256 toEcosystem = o.amount - toAgent - toPlatform; // remainder absorbs rounding

        _send(o.agent,             toAgent);
        _send(platformRecipient,   toPlatform);
        _send(ecosystemRecipient,  toEcosystem);

        emit OrderCompleted(orderId, resultHash, toAgent, toPlatform, toEcosystem);
    }

    /**
     * @notice Buyer opens a dispute within the dispute window. Blocks completion
     *         until admin resolves. Free-text reason is emitted for off-chain review.
     */
    function disputeOrder(uint256 orderId, string calldata reason) external {
        Order storage o = orders[orderId];
        if (o.status != OrderStatus.Created) revert InvalidStatus();
        if (msg.sender != o.buyer) revert NotAuthorized();
        if (block.timestamp > o.createdAt + DISPUTE_WINDOW) revert DisputeWindowClosed();
        o.status = OrderStatus.Disputed;
        emit OrderDisputed(orderId, o.buyer, reason);
    }

    /**
     * @notice Admin refunds buyer (after dispute, or for stuck orders).
     * @dev    v0 uses centralized arbitration. Replace with on-chain juror system in v1.
     */
    function refundOrder(uint256 orderId) external onlyAdmin {
        Order storage o = orders[orderId];
        if (o.status != OrderStatus.Created && o.status != OrderStatus.Disputed) revert InvalidStatus();
        o.status = OrderStatus.Refunded;
        _send(o.buyer, o.amount);
        emit OrderRefunded(orderId, o.buyer, o.amount);
    }

    /**
     * @notice Pull-payment escape hatch. If a recipient was a contract that
     *         rejected its `call` during `completeOrder`/`refundOrder`, its
     *         share was credited to `pendingWithdrawals` and emitted via
     *         `PaymentDeferred`. The recipient (or anyone on its behalf, since
     *         funds always go to `recipient`) calls this to claim.
     */
    function withdraw(address recipient) external {
        uint256 amount = pendingWithdrawals[recipient];
        if (amount == 0) revert NothingToWithdraw();
        pendingWithdrawals[recipient] = 0;
        (bool ok, ) = payable(recipient).call{value: amount, gas: SEND_GAS_LIMIT}("");
        if (!ok) {
            // Re-credit so the recipient can retry from a different code path
            // (e.g. once they've upgraded their wallet contract).
            pendingWithdrawals[recipient] = amount;
            revert TransferFailed();
        }
        emit PaymentWithdrawn(recipient, amount);
    }

    /**
     * @notice Public order accessor (auto-generated from `mapping orders` is fine,
     *         this getter just gives a consistent named-return interface).
     */
    function getOrder(uint256 orderId) external view returns (
        address buyer,
        address agent,
        uint256 amount,
        OrderStatus status,
        bytes32 inputHash,
        string memory resultHash,
        uint64 createdAt
    ) {
        Order storage o = orders[orderId];
        return (o.buyer, o.agent, o.amount, o.status, o.inputHash, o.resultHash, o.createdAt);
    }

    /**
     * @dev Bounded-gas low-level send. On failure, credits the pull-payment
     *      ledger instead of reverting, so a misbehaving recipient cannot
     *      permanently brick `completeOrder` for the agent.
     */
    function _send(address to, uint256 value) internal {
        if (value == 0) return;
        (bool ok, ) = payable(to).call{value: value, gas: SEND_GAS_LIMIT}("");
        if (!ok) {
            pendingWithdrawals[to] += value;
            emit PaymentDeferred(to, value);
        }
    }

    // No receive() / fallback() — funding must go through createOrder().
}
