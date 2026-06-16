// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {PayPerTaskEscrow} from "../src/payperask/PayPerTaskEscrow.sol";

/**
 * @title DeployPayPerTaskEscrow
 * @notice Foundry deployment script for Pharos Atlantic testnet.
 *
 * Usage:
 *   export PRIVATE_KEY=0x...
 *   export RPC=https://atlantic.dplabs-internal.com
 *   forge script script/DeployPayPerTaskEscrow.s.sol:DeployPayPerTaskEscrow \
 *     --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast
 */
contract DeployPayPerTaskEscrow is Script {
    function run() external returns (PayPerTaskEscrow escrow) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        // Read split recipients from env, fallback to deployer for all three on testnet.
        address admin     = vm.envOr("ADMIN_ADDRESS",     deployer);
        address platform  = vm.envOr("PLATFORM_ADDRESS",  deployer);
        address ecosystem = vm.envOr("ECOSYSTEM_ADDRESS", deployer);

        // 85 / 10 / 5 — same split as AgentMart MVP. Override via env if desired.
        uint16 creatorBps   = uint16(vm.envOr("CREATOR_BPS",   uint256(8500)));
        uint16 platformBps  = uint16(vm.envOr("PLATFORM_BPS",  uint256(1000)));
        uint16 ecosystemBps = uint16(vm.envOr("ECOSYSTEM_BPS", uint256(500)));

        console2.log("Deployer:           ", deployer);
        console2.log("Admin:              ", admin);
        console2.log("Platform recipient: ", platform);
        console2.log("Ecosystem recipient:", ecosystem);
        console2.log("Split (bps):        ", creatorBps, platformBps, ecosystemBps);

        vm.startBroadcast();
        escrow = new PayPerTaskEscrow(
            admin,
            platform,
            ecosystem,
            creatorBps,
            platformBps,
            ecosystemBps
        );
        vm.stopBroadcast();

        console2.log("PayPerTaskEscrow deployed at:", address(escrow));
    }
}
