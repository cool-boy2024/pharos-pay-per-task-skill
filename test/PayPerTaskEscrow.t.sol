// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {PayPerTaskEscrow} from "../src/payperask/PayPerTaskEscrow.sol";

/// @notice Reverts on receive — used to assert pull-payment fallback.
contract Reverter {
    receive() external payable {
        revert("nope");
    }
}

contract PayPerTaskEscrowTest is Test {
    PayPerTaskEscrow internal escrow;

    address internal admin     = address(0xA11CE);
    address internal platform  = address(0xB0B);
    address internal ecosystem = address(0xEC0);
    address internal buyer     = address(0xB0A);
    address internal agent     = address(0xA9E);

    bytes32 internal constant INPUT_HASH = keccak256("demo prompt");

    event OrderCreated(uint256 indexed orderId, address indexed buyer, address indexed agent, uint256 amount, bytes32 inputHash);
    event OrderCompleted(uint256 indexed orderId, string resultHash, uint256 paidToAgent, uint256 paidToPlatform, uint256 paidToEcosystem);
    event OrderDisputed(uint256 indexed orderId, address indexed buyer, string reason);
    event OrderRefunded(uint256 indexed orderId, address indexed buyer, uint256 amount);
    event PaymentDeferred(address indexed recipient, uint256 amount);

    function setUp() public {
        escrow = new PayPerTaskEscrow(admin, platform, ecosystem, 8500, 1000, 500);
        vm.deal(buyer, 10 ether);
    }

    // ── Constructor validation ──────────────────────────────────────────

    function test_constructor_revertsOnBadSplit() public {
        vm.expectRevert(PayPerTaskEscrow.InvalidSplit.selector);
        new PayPerTaskEscrow(admin, platform, ecosystem, 8000, 1000, 500); // sums to 9500
    }

    function test_constructor_revertsOnZeroAdmin() public {
        vm.expectRevert(PayPerTaskEscrow.ZeroAddress.selector);
        new PayPerTaskEscrow(address(0), platform, ecosystem, 8500, 1000, 500);
    }

    function test_constructor_revertsOnZeroPlatform() public {
        vm.expectRevert(PayPerTaskEscrow.ZeroAddress.selector);
        new PayPerTaskEscrow(admin, address(0), ecosystem, 8500, 1000, 500);
    }

    function test_constructor_revertsOnZeroEcosystem() public {
        vm.expectRevert(PayPerTaskEscrow.ZeroAddress.selector);
        new PayPerTaskEscrow(admin, platform, address(0), 8500, 1000, 500);
    }

    function test_constructor_storesParams() public view {
        assertEq(escrow.admin(),              admin);
        assertEq(escrow.platformRecipient(),  platform);
        assertEq(escrow.ecosystemRecipient(), ecosystem);
        assertEq(uint256(escrow.creatorBps()),   8500);
        assertEq(uint256(escrow.platformBps()),  1000);
        assertEq(uint256(escrow.ecosystemBps()),  500);
        assertEq(escrow.DISPUTE_WINDOW(),  7 days);
    }

    // ── createOrder ─────────────────────────────────────────────────────

    function test_createOrder_escrowsAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit OrderCreated(0, buyer, agent, 1 ether, INPUT_HASH);

        vm.prank(buyer);
        uint256 id = escrow.createOrder{value: 1 ether}(agent, INPUT_HASH);

        assertEq(id, 0);
        assertEq(escrow.nextOrderId(), 1);
        assertEq(address(escrow).balance, 1 ether);

        (address buyer_, address agent_, uint256 amount, PayPerTaskEscrow.OrderStatus status, bytes32 ih, string memory rh, uint64 ca)
            = escrow.getOrder(0);
        assertEq(buyer_, buyer);
        assertEq(agent_, agent);
        assertEq(amount, 1 ether);
        assertEq(uint8(status), uint8(PayPerTaskEscrow.OrderStatus.Created));
        assertEq(ih, INPUT_HASH);
        assertEq(bytes(rh).length, 0);
        assertEq(uint256(ca), block.timestamp);
    }

    function test_createOrder_revertsOnZeroValue() public {
        vm.prank(buyer);
        vm.expectRevert(PayPerTaskEscrow.ZeroAmount.selector);
        escrow.createOrder{value: 0}(agent, INPUT_HASH);
    }

    function test_createOrder_revertsOnZeroAgent() public {
        vm.prank(buyer);
        vm.expectRevert(PayPerTaskEscrow.ZeroAddress.selector);
        escrow.createOrder{value: 1 ether}(address(0), INPUT_HASH);
    }

    function test_createOrder_revertsOnSelfAgent() public {
        vm.prank(buyer);
        vm.expectRevert(PayPerTaskEscrow.BadAgent.selector);
        escrow.createOrder{value: 1 ether}(address(escrow), INPUT_HASH);
    }

    function test_createOrder_increments() public {
        vm.startPrank(buyer);
        uint256 a = escrow.createOrder{value: 1 ether}(agent, INPUT_HASH);
        uint256 b = escrow.createOrder{value: 1 ether}(agent, INPUT_HASH);
        vm.stopPrank();
        assertEq(a, 0);
        assertEq(b, 1);
    }

    // ── completeOrder ───────────────────────────────────────────────────

    function _seedOrder(uint256 amount) internal returns (uint256 id) {
        vm.prank(buyer);
        id = escrow.createOrder{value: amount}(agent, INPUT_HASH);
    }

    function test_completeOrder_splits85_10_5() public {
        uint256 id = _seedOrder(1 ether);

        vm.expectEmit(true, false, false, true);
        emit OrderCompleted(id, "ipfs://result", 0.85 ether, 0.10 ether, 0.05 ether);

        vm.prank(agent);
        escrow.completeOrder(id, "ipfs://result");

        assertEq(agent.balance,     0.85 ether);
        assertEq(platform.balance,  0.10 ether);
        assertEq(ecosystem.balance, 0.05 ether);
        assertEq(address(escrow).balance, 0);

        (, , , PayPerTaskEscrow.OrderStatus s, , string memory rh, ) = escrow.getOrder(id);
        assertEq(uint8(s), uint8(PayPerTaskEscrow.OrderStatus.Completed));
        assertEq(rh, "ipfs://result");
    }

    function test_completeOrder_adminCanComplete() public {
        uint256 id = _seedOrder(1 ether);
        vm.prank(admin);
        escrow.completeOrder(id, "ipfs://by-admin");
        assertEq(agent.balance, 0.85 ether);
    }

    function test_completeOrder_revertsForStranger() public {
        uint256 id = _seedOrder(1 ether);
        vm.prank(address(0xDEAD));
        vm.expectRevert(PayPerTaskEscrow.NotAuthorized.selector);
        escrow.completeOrder(id, "x");
    }

    function test_completeOrder_revertsOnAlreadyCompleted() public {
        uint256 id = _seedOrder(1 ether);
        vm.prank(agent);
        escrow.completeOrder(id, "first");
        vm.prank(agent);
        vm.expectRevert(PayPerTaskEscrow.InvalidStatus.selector);
        escrow.completeOrder(id, "second");
    }

    function test_completeOrder_dustGoesToEcosystem() public {
        // 7 wei split 8500/1000/500 → toAgent=5, toPlatform=0, toEcosystem=2.
        // Confirms remainder absorbs the rounding leftover.
        uint256 id = _seedOrder(7);
        vm.prank(agent);
        escrow.completeOrder(id, "dust");
        assertEq(agent.balance,     5);
        assertEq(platform.balance,  0);
        assertEq(ecosystem.balance, 2);
    }

    // ── disputeOrder ────────────────────────────────────────────────────

    function test_disputeOrder_buyerWithinWindow() public {
        uint256 id = _seedOrder(1 ether);

        vm.expectEmit(true, true, false, true);
        emit OrderDisputed(id, buyer, "agent never delivered");

        vm.prank(buyer);
        escrow.disputeOrder(id, "agent never delivered");

        (, , , PayPerTaskEscrow.OrderStatus s, , , ) = escrow.getOrder(id);
        assertEq(uint8(s), uint8(PayPerTaskEscrow.OrderStatus.Disputed));
    }

    function test_disputeOrder_blocksAgentCompletion() public {
        uint256 id = _seedOrder(1 ether);
        vm.prank(buyer);
        escrow.disputeOrder(id, "stuck");
        // Agent can no longer complete — only admin can resolve.
        vm.prank(agent);
        vm.expectRevert(PayPerTaskEscrow.NotAuthorized.selector);
        escrow.completeOrder(id, "too late");
    }

    function test_disputeOrder_revertsAfterWindow() public {
        uint256 id = _seedOrder(1 ether);
        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(buyer);
        vm.expectRevert(PayPerTaskEscrow.DisputeWindowClosed.selector);
        escrow.disputeOrder(id, "too late");
    }

    function test_disputeOrder_revertsForNonBuyer() public {
        uint256 id = _seedOrder(1 ether);
        vm.prank(agent);
        vm.expectRevert(PayPerTaskEscrow.NotAuthorized.selector);
        escrow.disputeOrder(id, "not me");
    }

    function test_adminResolvesDisputeInAgentFavor() public {
        uint256 id = _seedOrder(1 ether);
        vm.prank(buyer);
        escrow.disputeOrder(id, "stuck");
        // Admin completes despite Disputed status — pays agent.
        vm.prank(admin);
        escrow.completeOrder(id, "ipfs://verified");
        assertEq(agent.balance, 0.85 ether);
    }

    // ── refundOrder ─────────────────────────────────────────────────────

    function test_refundOrder_adminRefundsBuyer() public {
        uint256 id = _seedOrder(1 ether);
        uint256 buyerBalBefore = buyer.balance;

        vm.expectEmit(true, true, false, true);
        emit OrderRefunded(id, buyer, 1 ether);

        vm.prank(admin);
        escrow.refundOrder(id);

        assertEq(buyer.balance, buyerBalBefore + 1 ether);
        (, , , PayPerTaskEscrow.OrderStatus s, , , ) = escrow.getOrder(id);
        assertEq(uint8(s), uint8(PayPerTaskEscrow.OrderStatus.Refunded));
    }

    function test_refundOrder_onlyAdmin() public {
        uint256 id = _seedOrder(1 ether);
        vm.prank(buyer);
        vm.expectRevert(PayPerTaskEscrow.NotAuthorized.selector);
        escrow.refundOrder(id);
    }

    function test_refundOrder_revertsOnCompleted() public {
        uint256 id = _seedOrder(1 ether);
        vm.prank(agent);
        escrow.completeOrder(id, "done");
        vm.prank(admin);
        vm.expectRevert(PayPerTaskEscrow.InvalidStatus.selector);
        escrow.refundOrder(id);
    }

    // ── pull-payment fallback ───────────────────────────────────────────

    function test_completeOrder_revertingPlatformDoesNotBrickAgent() public {
        // Deploy fresh escrow whose platformRecipient is a contract that
        // reverts on receive. Agent should still receive their share via
        // direct call; platform's share lands in pendingWithdrawals.
        Reverter rev = new Reverter();
        PayPerTaskEscrow e = new PayPerTaskEscrow(admin, address(rev), ecosystem, 8500, 1000, 500);

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 id = e.createOrder{value: 1 ether}(agent, INPUT_HASH);

        vm.expectEmit(true, false, false, true);
        emit PaymentDeferred(address(rev), 0.10 ether);

        vm.prank(agent);
        e.completeOrder(id, "ipfs://x");

        assertEq(agent.balance,     0.85 ether);
        assertEq(ecosystem.balance, 0.05 ether);
        assertEq(e.pendingWithdrawals(address(rev)), 0.10 ether);
        assertEq(address(e).balance,                  0.10 ether);
    }

    function test_withdraw_revertsOnZeroLedger() public {
        vm.expectRevert(PayPerTaskEscrow.NothingToWithdraw.selector);
        escrow.withdraw(platform);
    }

    // ── No silent-receive ───────────────────────────────────────────────

    function test_directSendIsRejected() public {
        // No receive()/fallback() — direct PHRS sends must fail.
        vm.deal(address(this), 1 ether);
        (bool ok, ) = address(escrow).call{value: 1 ether}("");
        assertFalse(ok, "escrow must reject direct sends");
    }
}
