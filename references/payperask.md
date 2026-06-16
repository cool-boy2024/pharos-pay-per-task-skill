# PayPerTask Skill — Operation Instructions

This file contains detailed instructions for deploying and interacting with the
**PayPerTaskEscrow** contract on Pharos. It teaches three composable concepts:
escrowed pay-per-task billing, on-chain delivery proofs, and configurable
revenue splits between agent / platform / ecosystem.

> **Network Configuration**: The `<rpc>` parameter in all commands is read from
> the corresponding network's `rpcUrl` field in `assets/networks.json`.
> Defaults to the Atlantic testnet (`https://atlantic.dplabs-internal.com`).
>
> **Private Key Configuration**: All write operations must explicitly pass the
> private key via the `--private-key` parameter.
> Recommended: `--private-key $PRIVATE_KEY`.

---

## Deploy PayPerTaskEscrow

### Overview

PayPerTaskEscrow is an on-chain pay-per-task marketplace primitive. The
deployer (admin) configures three recipients (creator/agent, platform,
ecosystem) and a basis-point split that must sum to 10,000. Buyers escrow PHRS
when creating an order; agents claim it by submitting a delivery proof; or
buyers can dispute within 7 days and be refunded by admin.

### Step 1: Generate Deployment Script

The Agent generates `script/DeployPayPerTaskEscrow.s.sol` in the user's project
(already shipped in this skill at `script/DeployPayPerTaskEscrow.s.sol`):

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {PayPerTaskEscrow} from "../src/payperask/PayPerTaskEscrow.sol";

contract DeployPayPerTaskEscrow is Script {
    function run() external returns (PayPerTaskEscrow escrow) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        address admin     = vm.envOr("ADMIN_ADDRESS",     deployer);
        address platform  = vm.envOr("PLATFORM_ADDRESS",  deployer);
        address ecosystem = vm.envOr("ECOSYSTEM_ADDRESS", deployer);
        uint16 creatorBps   = uint16(vm.envOr("CREATOR_BPS",   uint256(8500)));
        uint16 platformBps  = uint16(vm.envOr("PLATFORM_BPS",  uint256(1000)));
        uint16 ecosystemBps = uint16(vm.envOr("ECOSYSTEM_BPS", uint256(500)));
        vm.startBroadcast();
        escrow = new PayPerTaskEscrow(admin, platform, ecosystem, creatorBps, platformBps, ecosystemBps);
        vm.stopBroadcast();
    }
}
```

### Step 2: Deploy

### Command Template

```bash
forge script script/DeployPayPerTaskEscrow.s.sol:DeployPayPerTaskEscrow \
  --rpc-url <rpc> \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### Parameters

| Parameter             | Type    | Required | Description                                                  |
|-----------------------|---------|----------|--------------------------------------------------------------|
| `--rpc-url`           | string  | Yes      | RPC endpoint, e.g. `https://atlantic.dplabs-internal.com`    |
| `--private-key`       | string  | Yes      | Deployer key. Defaults to admin/platform/ecosystem if env not set |
| `ADMIN_ADDRESS`       | env     | No       | Dispute resolver. Defaults to deployer                       |
| `PLATFORM_ADDRESS`    | env     | No       | Receives platformBps. Defaults to deployer                   |
| `ECOSYSTEM_ADDRESS`   | env     | No       | Receives ecosystemBps. Defaults to deployer                  |
| `CREATOR_BPS`         | env     | No       | Creator share in basis points. Default `8500` (85%)          |
| `PLATFORM_BPS`        | env     | No       | Platform share. Default `1000` (10%)                         |
| `ECOSYSTEM_BPS`       | env     | No       | Ecosystem share. Default `500` (5%)                          |

> **Note:** `creatorBps + platformBps + ecosystemBps` MUST equal `10_000`. The
> constructor reverts with `InvalidSplit()` otherwise.

### Output Parsing

| Field                | Description                                                          |
|----------------------|----------------------------------------------------------------------|
| `Contract Address`   | Address printed after `PayPerTaskEscrow deployed at:` — record this  |
| `Transaction Hash`   | Use to look up deployment on `https://atlantic.pharosscan.xyz/`      |

### Error Handling

| Error                              | Cause                                                  | Fix                                                              |
|------------------------------------|--------------------------------------------------------|------------------------------------------------------------------|
| `InvalidSplit()`                   | Sum of bps != 10,000                                   | Adjust `CREATOR_BPS`/`PLATFORM_BPS`/`ECOSYSTEM_BPS`              |
| `insufficient funds`               | Deployer wallet balance too low for gas                | Get testnet PHRS from Pharos faucet                              |
| `connection refused`               | `--rpc-url` missing                                    | Always pass `--rpc-url <rpc>` explicitly                         |

> **Agent Guidelines**:
> 1. Complete Write Operation Pre-checks (see `SKILL.md`).
> 2. Confirm `creatorBps + platformBps + ecosystemBps = 10_000` before broadcasting.
> 3. After success, record the deployed address and show
>    `https://atlantic.pharosscan.xyz/address/<addr>`.
> 4. Wait `sleep 10` before any verification step to let the indexer catch up.

---

## Verify PayPerTaskEscrow

### Command Template

```bash
sleep 10
forge verify-contract <escrow_address> src/payperask/PayPerTaskEscrow.sol:PayPerTaskEscrow \
  --chain-id 688689 \
  --verifier-url https://api.socialscan.io/pharos-atlantic-testnet/v1/explorer/command_api/contract \
  --verifier blockscout \
  --constructor-args $(cast abi-encode "constructor(address,address,address,uint16,uint16,uint16)" \
      $ADMIN $PLATFORM $ECOSYSTEM 8500 1000 500)
```

### Parameters

| Parameter            | Type   | Required | Description                                  |
|----------------------|--------|----------|----------------------------------------------|
| `<escrow_address>`   | string | Yes      | Contract address from deployment             |
| `--constructor-args` | bytes  | Yes      | ABI-encoded constructor args                 |
| `--chain-id`         | int    | Yes      | `688689` for Atlantic testnet                |

> **Agent Guidelines**:
> 1. Always run `sleep 10` before verification — the indexer needs time.
> 2. After success, show
>    `https://atlantic.pharosscan.xyz/address/<addr>#code`.

---

## Create Order (Buyer Escrows PHRS)

### Overview

The buyer locks PHRS into the escrow against an `inputHash` (typically
`keccak256(prompt)`) and an `agent` address that will receive the creator share
on completion. Returns an auto-incrementing `orderId`.

### Command Template

```bash
cast send <escrow_address> \
  "createOrder(address,bytes32)" <agent_address> <input_hash> \
  --value <amount>ether \
  --private-key $PRIVATE_KEY \
  --rpc-url <rpc>
```

### Parameters

| Parameter         | Type    | Required | Description                                                     |
|-------------------|---------|----------|-----------------------------------------------------------------|
| `<escrow_address>`| address | Yes      | Deployed PayPerTaskEscrow address                               |
| `<agent_address>` | address | Yes      | EVM address of the agent fulfilling this order                  |
| `<input_hash>`    | bytes32 | Yes      | `cast keccak "<prompt>"` — fingerprint of the task input        |
| `--value`         | string  | Yes      | Amount of PHRS to escrow, e.g. `0.05ether`                      |

### Output Parsing

| Field             | Description                                                              |
|-------------------|--------------------------------------------------------------------------|
| `transactionHash` | Use to look up the `OrderCreated` event on the explorer                  |
| `orderId`         | Read via `cast logs` on `OrderCreated` event, or call `nextOrderId() - 1`|

### Error Handling

| Error                              | Cause                                          | Fix                                              |
|------------------------------------|------------------------------------------------|--------------------------------------------------|
| `execution reverted: ZeroAmount`   | `--value` is `0` or missing                    | Add `--value <n>ether`                           |
| `insufficient funds`               | Buyer wallet balance too low                   | `cast balance <addr> --rpc-url <rpc> --ether`    |
| `invalid address`                  | `<agent_address>` malformed                    | Confirm `0x` + 40 hex chars                      |

> **Agent Guidelines**:
> 1. Hash the task prompt with `cast keccak "<prompt>"` before calling — never
>    pass plain text as `bytes32`.
> 2. After success, show `https://atlantic.pharosscan.xyz/tx/<txHash>` and the
>    new `orderId` (read via `nextOrderId() - 1`).
> 3. Remind the user the buyer can `disputeOrder` within 7 days if undelivered.

---

## Complete Order (Agent Submits Delivery Proof)

### Overview

The agent (or admin) marks the order as completed and submits a `resultHash`
(typically a CID, IPFS hash, or 0G storage proof). On success the contract
splits the escrowed PHRS by the configured basis points and emits an
`OrderCompleted` event with the per-recipient amounts.

### Command Template

```bash
cast send <escrow_address> \
  "completeOrder(uint256,string)" <order_id> "<result_hash>" \
  --private-key $PRIVATE_KEY \
  --rpc-url <rpc>
```

### Parameters

| Parameter          | Type    | Required | Description                                                       |
|--------------------|---------|----------|-------------------------------------------------------------------|
| `<escrow_address>` | address | Yes      | Deployed PayPerTaskEscrow address                                 |
| `<order_id>`       | uint256 | Yes      | Order id from `OrderCreated` event                                |
| `<result_hash>`    | string  | Yes      | Delivery proof, e.g. IPFS CID or 0G storage hash                  |
| `--private-key`    | string  | Yes      | Must be the agent's key (or admin's)                              |

### Output Parsing

| Field              | Description                                                   |
|--------------------|---------------------------------------------------------------|
| `status`           | `1` = success                                                 |
| `transactionHash`  | Use `cast logs` to inspect `OrderCompleted` event             |

### Error Handling

| Error                                | Cause                                              | Fix                                                |
|--------------------------------------|----------------------------------------------------|----------------------------------------------------|
| `execution reverted: InvalidStatus`  | Order is not in `Created` status                   | Already completed/disputed/refunded — query state  |
| `execution reverted: NotAuthorized`  | Caller is neither agent nor admin                  | Use the agent's `$PRIVATE_KEY`                     |
| `execution reverted: TransferFailed` | One of the recipients reverted on receive          | Check that recipients are EOAs or accept transfers |

> **Agent Guidelines**:
> 1. Run `cast call <escrow> "getOrder(uint256)" <orderId>` first to confirm
>    `status == Created` (`1`).
> 2. After success, show the `OrderCompleted` event payload (paid amounts) by
>    calling `cast logs` on the tx.

---

## Dispute Order (Buyer Opens Dispute Within 7 Days)

### Overview

The buyer can dispute an unfulfilled order within `DISPUTE_WINDOW = 7 days` of
order creation. This blocks completion until the admin resolves it (typically
by refunding).

### Command Template

```bash
cast send <escrow_address> \
  "disputeOrder(uint256,string)" <order_id> "<reason>" \
  --private-key $PRIVATE_KEY \
  --rpc-url <rpc>
```

### Parameters

| Parameter          | Type    | Required | Description                                          |
|--------------------|---------|----------|------------------------------------------------------|
| `<order_id>`       | uint256 | Yes      | Order id                                             |
| `<reason>`         | string  | Yes      | Free-text reason emitted in `OrderDisputed` event    |
| `--private-key`    | string  | Yes      | Must be the buyer's key                              |

### Error Handling

| Error                                       | Cause                                        | Fix                                          |
|---------------------------------------------|----------------------------------------------|----------------------------------------------|
| `execution reverted: InvalidStatus`         | Order not in `Created` status                | Cannot dispute completed/refunded orders     |
| `execution reverted: NotAuthorized`         | Caller is not the buyer                      | Use buyer's `$PRIVATE_KEY`                   |
| `execution reverted: DisputeWindowClosed`   | More than 7 days since `createdAt`           | Window expired — order will auto-complete    |

> **Agent Guidelines**:
> 1. Read `getOrder(orderId).createdAt` and confirm `block.timestamp - createdAt < 7 days`.
> 2. After success, notify user that admin will review the `<reason>`.

---

## Refund Order (Admin Refunds After Dispute)

### Overview

The admin returns the full escrowed amount to the buyer. Used to resolve
disputes or to handle stuck orders. Only callable by the admin set at deploy.

### Command Template

```bash
cast send <escrow_address> \
  "refundOrder(uint256)" <order_id> \
  --private-key $PRIVATE_KEY \
  --rpc-url <rpc>
```

### Parameters

| Parameter        | Type    | Required | Description                                |
|------------------|---------|----------|--------------------------------------------|
| `<order_id>`     | uint256 | Yes      | Order id                                   |
| `--private-key`  | string  | Yes      | Must be the admin's key (set at deploy)    |

### Error Handling

| Error                                | Cause                                          | Fix                                  |
|--------------------------------------|------------------------------------------------|--------------------------------------|
| `execution reverted: NotAuthorized`  | Caller is not admin                            | Use the admin's `$PRIVATE_KEY`       |
| `execution reverted: InvalidStatus`  | Order is `Completed` or already `Refunded`     | Cannot refund — query state          |

> **Agent Guidelines**:
> 1. Confirm the order is `Created` or `Disputed` before refunding.
> 2. After success, show `OrderRefunded` event from `cast logs`.

---

## Query Order State

### Command Template

```bash
cast call <escrow_address> \
  "getOrder(uint256)(address,address,uint256,uint8,bytes32,string,uint64)" \
  <order_id> \
  --rpc-url <rpc>
```

### Output Parsing

Returns a tuple in this order:

| Field         | Type     | Meaning                                            |
|---------------|----------|----------------------------------------------------|
| `buyer`       | address  | Buyer who escrowed the funds                       |
| `agent`       | address  | Recipient of the creator share                     |
| `amount`      | uint256  | Escrowed amount in wei (divide by 10^18 for PHRS)  |
| `status`      | uint8    | `0`=None `1`=Created `2`=Completed `3`=Disputed `4`=Refunded |
| `inputHash`   | bytes32  | Hash of task input committed by buyer              |
| `resultHash`  | string   | Empty until `completeOrder`, then the proof hash   |
| `createdAt`   | uint64   | Unix timestamp of order creation                   |

> **Agent Guidelines**: Map `status` to the human-readable enum names above
> when reporting state to users.

---

## Query Events (Order History)

### Query All Created Orders

### Command Template

```bash
cast logs \
  --rpc-url <rpc> \
  --address <escrow_address> \
  "OrderCreated(uint256,address,address,uint256,bytes32)"
```

### Output Parsing

| Field              | Description                                                  |
|--------------------|--------------------------------------------------------------|
| `topics[1]`        | `orderId` (indexed) — hex, convert with `cast --to-dec`      |
| `topics[2]`        | `buyer` (indexed)                                            |
| `topics[3]`        | `agent` (indexed)                                            |
| `data[0]`          | `amount` in wei                                              |
| `data[1]`          | `inputHash`                                                  |

### Query Completed Orders

```bash
cast logs \
  --rpc-url <rpc> \
  --address <escrow_address> \
  "OrderCompleted(uint256,string,uint256,uint256,uint256)"
```

### Query Disputes

```bash
cast logs \
  --rpc-url <rpc> \
  --address <escrow_address> \
  "OrderDisputed(uint256,address,string)"
```

### Query Refunds

```bash
cast logs \
  --rpc-url <rpc> \
  --address <escrow_address> \
  "OrderRefunded(uint256,address,uint256)"
```

> **Agent Guidelines**: Convert wei amounts to PHRS by dividing by 10^18.
> Convert `topics[1]` (orderId) from hex to decimal with `cast --to-dec`.
> Include `https://atlantic.pharosscan.xyz/tx/<txHash>` for each event.
> If no logs returned, clearly state no activity has occurred yet on this contract.

---

## Composability with Other Pharos Skills

PayPerTask is designed to compose with other Pharos Skills in the
Skill-to-Agent Cascade:

- **Storage Proof Skill** → produces a CID/hash that is passed as `resultHash` to `completeOrder`.
- **Inference Skill** → executes the task whose `inputHash` was committed in `createOrder`.
- **Rating Skill** → reads `OrderCompleted` events to update agent reputation.
- **x402 Skill** → can settle agent payments using the same escrow primitive off the L1 hot path.

A higher-level Agent reads the **Capability Index** in `SKILL.md`, locates this
skill's section, and chains `createOrder → (work) → completeOrder` while other
skills handle the work itself.
