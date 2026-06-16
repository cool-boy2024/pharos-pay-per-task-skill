// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PayPerTaskEscrow
 * @notice Pay-per-task escrow for AI Agents on Pharos.
 *         Buyer escrows PHRS for a task → Agent submits proof → Funds split
 *         between agent / platform / ecosystem.
 *
 *         Adapted from AgentMart (0G APAC Hackathon) with hardening:
 *         - dispute window with refund path
 *         - configurable split via constructor
 *         - per-order agent address (not single creatorRecipient)
 *         - explicit task input/output hashes for proof binding
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

    // ── State ──────────────────────────────────────────────────────────
    uint256 public nextOrderId;
    mapping(uint256 => Order) public orders;

    // ── Events ─────────────────────────────────────────────────────────
    event OrderCreated(uint256 indexed orderId, address indexed buyer, address indexed agent, uint256 amount, bytes32 inputHash);
    event OrderCompleted(uint256 indexed orderId, string resultHash, uint256 paidToAgent, uint256 paidToPlatform, uint256 paidToEcosystem);
    event OrderDisputed(uint256 indexed orderId, address indexed buyer, string reason);
    event OrderRefunded(uint256 indexed orderId, address indexed buyer, uint256 amount);

    // ── Errors ─────────────────────────────────────────────────────────
    error ZeroAmount();
    error InvalidStatus();
    error NotAuthorized();
    error DisputeWindowClosed();
    error InvalidSplit();
    error TransferFailed();

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
     * @dev    Disputed orders cannot be completed; admin must refund or resolve.
     */
    function completeOrder(uint256 orderId, string calldata resultHash) external {
        Order storage o = orders[orderId];
        if (o.status != OrderStatus.Created) revert InvalidStatus();
        if (msg.sender != o.agent && msg.sender != admin) revert NotAuthorized();

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

    function _send(address to, uint256 value) internal {
        if (value == 0) return;
        (bool ok, ) = payable(to).call{value: value}("");
        if (!ok) revert TransferFailed();
    }

    receive() external payable {}
}
