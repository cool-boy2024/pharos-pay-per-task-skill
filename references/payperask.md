# PayPerTask Skill — Operation Instructions

This file contains detailed instructions for deploying and interacting with the
**PayPerTaskEscrow** contract on Pharos. It teaches three composable concepts:
escrowed pay-per-task billing, on-chain delivery proofs, and configurable
revenue splits between agent / platform / ecosystem.

> **RPC**: All commands assume `$RPC` is set to a valid Pharos RPC. Defaults
> to Atlantic Testnet — `export RPC=https://atlantic.dplabs-internal.com`.
> The canonical value lives in `assets/networks.json` under the
> `atlantic-testnet.rpcUrl` field. Foundry users can also use the
> `pharos_atlantic` alias defined in `foundry.toml`
> (`forge script ... --rpc-url pharos_atlantic`).
>
> **Private key**: Every write operation passes `--private-key $PRIVATE_KEY`
> explicitly — Foundry does not pick it up from the env automatically.
>
> **Custom-error decoding**: PayPerTaskEscrow uses Solidity custom errors. If
> `cast` shows `execution reverted: 0xabcd1234` instead of a name, run
> `cast 4byte 0xabcd1234` to resolve the selector to one of the names listed
> in the Error Handling tables below. Or pass `--json` and decode the `data`
> field.

---

## Deploy PayPerTaskEscrow

### Overview

PayPerTaskEscrow is an on-chain pay-per-task marketplace primitive. The
deployer (admin) configures three recipients (creator/agent, platform,
ecosystem) and a basis-point split that must sum to 10,000. Buyers escrow PHRS
when creating an order; agents claim it by submitting a delivery proof; or
buyers can dispute within 7 days and be refunded by admin. If a fee recipient
rejects a payout, that share is credited to a pull-payment ledger
(`pendingWithdrawals`) — so a misbehaving recipient cannot brick the agent's
share.

The deployment script (`script/DeployPayPerTaskEscrow.s.sol`) is shipped in
this skill. The agent does NOT need to regenerate it.

#### Command Template

```bash
forge script script/DeployPayPerTaskEscrow.s.sol:DeployPayPerTaskEscrow \
  --rpc-url $RPC \
  --private-key $PRIVATE_KEY \
  --broadcast
```

#### Parameters

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

> **Note:** `creatorBps + platformBps + ecosystemBps` MUST equal `10_000` and
> all three recipient addresses MUST be non-zero. The constructor reverts with
> `InvalidSplit()` or `ZeroAddress()` otherwise.

#### Output Parsing

| Field                | Description                                                          |
|----------------------|----------------------------------------------------------------------|
| `Contract Address`   | Address printed after `PayPerTaskEscrow deployed at:` — record this. The authoritative source is `broadcast/DeployPayPerTaskEscrow.s.sol/688689/run-latest.json` (`.transactions[] | select(.transactionType=="CREATE") | .contractAddress`). |
| `Transaction Hash`   | Use to look up the deployment on `https://atlantic.pharosscan.xyz/`  |

#### Error Handling

| Error                              | Cause                                                  | Fix                                                              |
|------------------------------------|--------------------------------------------------------|------------------------------------------------------------------|
| `InvalidSplit()`                   | Sum of bps != 10,000                                   | Adjust `CREATOR_BPS`/`PLATFORM_BPS`/`ECOSYSTEM_BPS`              |
| `ZeroAddress()`                    | One of admin/platform/ecosystem is `0x000…0`           | Pass real addresses (or unset env vars to default to deployer)   |
| `insufficient funds`               | Deployer wallet balance too low for gas                | Get testnet PHRS from `https://testnet.pharosnetwork.xyz/`       |
| `connection refused`               | `--rpc-url` missing                                    | Always pass `--rpc-url $RPC` explicitly                          |

> **Agent Guidelines**:
> 1. Complete Write Operation Pre-checks (see `SKILL.md`).
> 2. Confirm `creatorBps + platformBps + ecosystemBps = 10_000` before broadcasting.
> 3. After success, record the deployed address and show
>    `https://atlantic.pharosscan.xyz/address/<addr>`.
> 4. Wait `sleep 10` before any verification step to let the indexer catch up.

---

## Verify PayPerTaskEscrow

### Overview

Submit the contract source to Pharos Scan (Blockscout-compatible verifier) so
the explorer renders the ABI/source for buyers and agents. Run this after the
deployer's tx has been indexed.

#### Command Template

```bash
sleep 10
forge verify-contract <escrow_address> src/payperask/PayPerTaskEscrow.sol:PayPerTaskEscrow \
  --chain-id 688689 \
  --verifier-url https://api.socialscan.io/pharos-atlantic-testnet/v1/explorer/command_api/contract \
  --verifier blockscout \
  --constructor-args $(cast abi-encode \
      "constructor(address,address,address,uint16,uint16,uint16)" \
      $ADMIN_ADDRESS $PLATFORM_ADDRESS $ECOSYSTEM_ADDRESS \
      $CREATOR_BPS $PLATFORM_BPS $ECOSYSTEM_BPS)
```

> The constructor-args MUST match the values used at deploy. If the env vars
> defaulted to `$DEPLOYER` / `8500` / `1000` / `500`, set them to the same
> here before running.

#### Parameters

| Parameter            | Type   | Required | Description                                  |
|----------------------|--------|----------|----------------------------------------------|
| `<escrow_address>`   | string | Yes      | Contract address from deployment             |
| `--constructor-args` | bytes  | Yes      | ABI-encoded constructor args                 |
| `--chain-id`         | int    | Yes      | `688689` for Atlantic testnet                |
| `--verifier-url`     | string | Yes      | Blockscout-compatible endpoint               |

#### Output Parsing

| Field                | Description                                                          |
|----------------------|----------------------------------------------------------------------|
| `Submitted contract verification` | Verification request accepted; record the GUID if printed |
| `Contract verified`  | Success — explorer renders source at `https://atlantic.pharosscan.xyz/address/<addr>#code` |

#### Error Handling

| Error                                     | Cause                                            | Fix                                                              |
|-------------------------------------------|--------------------------------------------------|------------------------------------------------------------------|
| `Already verified`                        | Source previously submitted                      | No action — explorer already shows the source                    |
| `Compilation failed: ...`                 | Local solc version does not match foundry.toml   | Reinstall: `foundryup` and confirm `forge --version`             |
| `Verification failed: ... constructor`    | `--constructor-args` does not match deploy state | Re-encode using the SAME `ADMIN_ADDRESS`/`PLATFORM_ADDRESS`/etc. values that were active at deploy time |

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

#### Command Template

```bash
cast send <escrow_address> \
  "createOrder(address,bytes32)" <agent_address> <input_hash> \
  --value <amount>ether \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC
```

> `<amount>ether` uses Foundry's `1e18` multiplier — PHRS has 18 decimals so
> `0.05ether` resolves to 5×10¹⁶ wei of PHRS, not literal Ether.

#### Parameters

| Parameter         | Type    | Required | Description                                                     |
|-------------------|---------|----------|-----------------------------------------------------------------|
| `<escrow_address>`| address | Yes      | Deployed PayPerTaskEscrow address                               |
| `<agent_address>` | address | Yes      | EVM address of the agent fulfilling this order (must be non-zero and not the escrow itself) |
| `<input_hash>`    | bytes32 | Yes      | `cast keccak "<prompt>"` — fingerprint of the task input        |
| `--value`         | string  | Yes      | Amount of PHRS to escrow, e.g. `0.05ether`                      |

#### Output Parsing

| Field             | Description                                                              |
|-------------------|--------------------------------------------------------------------------|
| `transactionHash` | Use to look up the `OrderCreated` event on the explorer                  |
| `orderId`         | Decode `topics[1]` of the `OrderCreated` event in the receipt logs (preferred), or query `nextOrderId() - 1` immediately after the tx confirms |

#### Error Handling

| Error                                | Cause                                          | Fix                                              |
|--------------------------------------|------------------------------------------------|--------------------------------------------------|
| `execution reverted: ZeroAmount()`   | `--value` is `0` or missing                    | Add `--value <n>ether`                           |
| `execution reverted: ZeroAddress()`  | `<agent_address>` is `0x000…0`                 | Pass a real agent address                        |
| `execution reverted: BadAgent()`     | `<agent_address>` equals the escrow contract   | Use an EOA or a different contract               |
| `insufficient funds`                 | Buyer wallet balance too low                   | `cast balance <addr> --rpc-url $RPC --ether`     |
| `invalid address`                    | `<agent_address>` malformed                    | Confirm `0x` + 40 hex chars                      |

> **Agent Guidelines**:
> 1. Hash the task prompt with `cast keccak "<prompt>"` before calling — never
>    pass plain text as `bytes32`.
> 2. After success, show `https://atlantic.pharosscan.xyz/tx/<txHash>` and the
>    new `orderId`.
> 3. Remind the user the buyer can `disputeOrder` within 7 days if undelivered.

---

## Complete Order (Agent Submits Delivery Proof)

### Overview

The agent (or admin) marks the order as completed and submits a `resultHash`
(typically a CID, IPFS hash, or 0G storage proof). On success the contract
splits the escrowed PHRS by the configured basis points and emits an
`OrderCompleted` event with the per-recipient amounts.

If the order has been disputed, only the admin can call `completeOrder` (this
is the admin's "resolve in agent's favor" path). Otherwise admin uses
`refundOrder`.

#### Command Template

```bash
cast send <escrow_address> \
  "completeOrder(uint256,string)" <order_id> "<result_hash>" \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC
```

#### Parameters

| Parameter          | Type    | Required | Description                                                       |
|--------------------|---------|----------|-------------------------------------------------------------------|
| `<escrow_address>` | address | Yes      | Deployed PayPerTaskEscrow address                                 |
| `<order_id>`       | uint256 | Yes      | Order id from `OrderCreated` event                                |
| `<result_hash>`    | string  | Yes      | Delivery proof, e.g. IPFS CID or 0G storage hash                  |
| `--private-key`    | string  | Yes      | Must be the agent's key (or admin's)                              |

#### Output Parsing

| Field              | Description                                                   |
|--------------------|---------------------------------------------------------------|
| `status`           | `1` = success                                                 |
| `transactionHash`  | Use `cast receipt $TX --rpc-url $RPC --json` and decode `OrderCompleted` from `.logs[]`. Fields: `paidToAgent`, `paidToPlatform`, `paidToEcosystem` (uint256, wei). |
| `PaymentDeferred`  | Optional companion event. If a recipient rejected its share, that share is now claimable via `withdraw(<recipient>)`. |

#### Error Handling

| Error                                  | Cause                                              | Fix                                                |
|----------------------------------------|----------------------------------------------------|----------------------------------------------------|
| `execution reverted: InvalidStatus()`  | Order is not in `Created` or `Disputed` status     | Already completed/refunded — query state           |
| `execution reverted: NotAuthorized()`  | Caller is neither agent nor admin (or order is Disputed and caller is not admin) | Use the agent's `$PRIVATE_KEY` (or admin's for a Disputed order) |

> **Agent Guidelines**:
> 1. Run `cast call <escrow> "getOrder(uint256)" <orderId>` first to confirm
>    `status == Created` (`1`).
> 2. After success, decode the `OrderCompleted` event payload (paid amounts) by
>    calling `cast receipt $TX --rpc-url $RPC --json | jq '.logs'` on the tx.
> 3. If a `PaymentDeferred(recipient, amount)` event was also emitted, surface
>    it to the user — that recipient must call `withdraw(<recipient>)` to claim.

---

## Dispute Order (Buyer Opens Dispute Within 7 Days)

### Overview

The buyer can dispute an unfulfilled order within `DISPUTE_WINDOW = 7 days` of
order creation. This blocks completion until the admin resolves it (typically
by refunding via `refundOrder`, or by completing in the agent's favor).

#### Command Template

```bash
cast send <escrow_address> \
  "disputeOrder(uint256,string)" <order_id> "<reason>" \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC
```

#### Parameters

| Parameter          | Type    | Required | Description                                          |
|--------------------|---------|----------|------------------------------------------------------|
| `<escrow_address>` | address | Yes      | Deployed PayPerTaskEscrow address                    |
| `<order_id>`       | uint256 | Yes      | Order id                                             |
| `<reason>`         | string  | Yes      | Free-text reason emitted in `OrderDisputed` event    |
| `--private-key`    | string  | Yes      | Must be the buyer's key                              |

#### Output Parsing

| Field             | Description                                                     |
|-------------------|-----------------------------------------------------------------|
| `transactionHash` | Receipt should contain one `OrderDisputed(orderId, buyer, reason)` log |
| `OrderDisputed`   | `topics[1]` = `orderId`, `topics[2]` = `buyer`, `data` = ABI-encoded `reason` string |

#### Error Handling

| Error                                       | Cause                                        | Fix                                          |
|---------------------------------------------|----------------------------------------------|----------------------------------------------|
| `execution reverted: InvalidStatus()`       | Order not in `Created` status                | Cannot dispute completed/refunded orders     |
| `execution reverted: NotAuthorized()`       | Caller is not the buyer                      | Use buyer's `$PRIVATE_KEY`                   |
| `execution reverted: DisputeWindowClosed()` | More than 7 days since `createdAt`           | Window expired — buyer can no longer dispute; only the agent or admin can settle (`completeOrder`) or admin can `refundOrder` |

> **Agent Guidelines**:
> 1. Read `getOrder(orderId).createdAt` and confirm `block.timestamp - createdAt < 7 days`.
> 2. After success, notify user that admin will review the `<reason>`.

---

## Refund Order (Admin Refunds After Dispute)

### Overview

The admin returns the full escrowed amount to the buyer. Used to resolve
disputes or to handle stuck orders. Only callable by the admin set at deploy.

#### Command Template

```bash
cast send <escrow_address> \
  "refundOrder(uint256)" <order_id> \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC
```

#### Parameters

| Parameter          | Type    | Required | Description                                |
|--------------------|---------|----------|--------------------------------------------|
| `<escrow_address>` | address | Yes      | Deployed PayPerTaskEscrow address          |
| `<order_id>`       | uint256 | Yes      | Order id                                   |
| `--private-key`    | string  | Yes      | Must be the admin's key (set at deploy)    |

#### Output Parsing

| Field             | Description                                                      |
|-------------------|------------------------------------------------------------------|
| `transactionHash` | Receipt contains an `OrderRefunded(orderId, buyer, amount)` log  |
| `OrderRefunded`   | `topics[1]` = `orderId`, `topics[2]` = `buyer`, `data[0]` = `amount` (uint256, wei) |

#### Error Handling

| Error                                  | Cause                                          | Fix                                  |
|----------------------------------------|------------------------------------------------|--------------------------------------|
| `execution reverted: NotAuthorized()`  | Caller is not admin                            | Use the admin's `$PRIVATE_KEY`       |
| `execution reverted: InvalidStatus()`  | Order is `Completed` or already `Refunded`     | Cannot refund — query state          |

> **Agent Guidelines**:
> 1. Confirm the order is `Created` or `Disputed` before refunding.
> 2. After success, show `OrderRefunded` event from `cast receipt $TX --json`.

---

## Withdraw Deferred Payment (Pull-Payment Fallback)

### Overview

If a fee recipient (platform or ecosystem) is a contract that reverted on
receive during `completeOrder`/`refundOrder`, that share was credited to
`pendingWithdrawals[recipient]` and a `PaymentDeferred` event was emitted.
Anyone can call `withdraw(recipient)` to push the deferred amount; funds always
go to `recipient` (the call argument), never to `msg.sender`.

#### Command Template

```bash
cast send <escrow_address> \
  "withdraw(address)" <recipient_address> \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC
```

#### Parameters

| Parameter            | Type    | Required | Description                                   |
|----------------------|---------|----------|-----------------------------------------------|
| `<escrow_address>`   | address | Yes      | Deployed PayPerTaskEscrow address             |
| `<recipient_address>`| address | Yes      | Whose pending balance is being withdrawn      |
| `--private-key`      | string  | Yes      | Any funded wallet — `recipient` receives funds, not the caller |

#### Output Parsing

| Field             | Description                                                  |
|-------------------|--------------------------------------------------------------|
| `transactionHash` | Receipt contains `PaymentWithdrawn(recipient, amount)` log   |
| `pendingWithdrawals` | Read with `cast call <escrow> "pendingWithdrawals(address)(uint256)" <recipient> --rpc-url $RPC` to confirm the ledger is now zero |

#### Error Handling

| Error                                    | Cause                                         | Fix                                          |
|------------------------------------------|-----------------------------------------------|----------------------------------------------|
| `execution reverted: NothingToWithdraw()`| `pendingWithdrawals[recipient] == 0`          | Confirm a `PaymentDeferred` event was emitted for this recipient |
| `execution reverted: TransferFailed()`   | Recipient still rejects receive               | Recipient must fix their fallback before retrying — funds remain credited |

> **Agent Guidelines**: This is the safety valve for the pull-payment design.
> Surface to the user that funds are NOT lost; they are sitting in
> `pendingWithdrawals` and any caller can push them to the recipient.

---

## Query Order State

### Overview

Read all fields of an order in one call. Returns a 7-tuple matching the
`Order` struct.

#### Command Template

```bash
cast call <escrow_address> \
  "getOrder(uint256)(address,address,uint256,uint8,bytes32,string,uint64)" \
  <order_id> \
  --rpc-url $RPC
```

#### Parameters

| Parameter         | Type    | Required | Description                                |
|-------------------|---------|----------|--------------------------------------------|
| `<escrow_address>`| address | Yes      | Deployed PayPerTaskEscrow address          |
| `<order_id>`      | uint256 | Yes      | Order id from `OrderCreated`               |
| `--rpc-url`       | string  | Yes      | Pharos RPC                                 |

#### Output Parsing

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
> when reporting state to users. To enumerate orders, read `nextOrderId()` and
> iterate from `0` to `nextOrderId-1`.

---

## Query Events (Order History)

### Overview

`cast logs` decodes events from on-chain history. Pharos public RPCs reject
queries with very large block ranges; pass `--from-block <deploy_block>` (or a
recent block number) instead of `0`.

### Query All Created Orders

#### Command Template

```bash
cast logs \
  --rpc-url $RPC \
  --address <escrow_address> \
  --from-block <deploy_block> \
  "OrderCreated(uint256,address,address,uint256,bytes32)"
```

#### Output Parsing

| Field              | Description                                                  |
|--------------------|--------------------------------------------------------------|
| `topics[1]`        | `orderId` (indexed) — hex, convert with `cast --to-dec`      |
| `topics[2]`        | `buyer` (indexed)                                            |
| `topics[3]`        | `agent` (indexed)                                            |
| `data[0..32]`      | `amount` in wei                                              |
| `data[32..64]`     | `inputHash` (bytes32)                                        |

### Query Completed Orders

#### Command Template

```bash
cast logs \
  --rpc-url $RPC \
  --address <escrow_address> \
  --from-block <deploy_block> \
  "OrderCompleted(uint256,string,uint256,uint256,uint256)"
```

#### Output Parsing

| Field              | Description                                                  |
|--------------------|--------------------------------------------------------------|
| `topics[1]`        | `orderId` (indexed)                                          |
| `data`             | ABI-encoded `(string resultHash, uint256 paidToAgent, uint256 paidToPlatform, uint256 paidToEcosystem)` — decode with `cast abi-decode "f(string,uint256,uint256,uint256)" <data>` |

### Query Disputes

#### Command Template

```bash
cast logs \
  --rpc-url $RPC \
  --address <escrow_address> \
  --from-block <deploy_block> \
  "OrderDisputed(uint256,address,string)"
```

#### Output Parsing

| Field              | Description                                                  |
|--------------------|--------------------------------------------------------------|
| `topics[1]`        | `orderId` (indexed)                                          |
| `topics[2]`        | `buyer`   (indexed)                                          |
| `data`             | ABI-encoded `(string reason)` — decode with `cast abi-decode "f(string)" <data>` |

### Query Refunds

#### Command Template

```bash
cast logs \
  --rpc-url $RPC \
  --address <escrow_address> \
  --from-block <deploy_block> \
  "OrderRefunded(uint256,address,uint256)"
```

#### Output Parsing

| Field              | Description                                                  |
|--------------------|--------------------------------------------------------------|
| `topics[1]`        | `orderId` (indexed)                                          |
| `topics[2]`        | `buyer`   (indexed)                                          |
| `data[0..32]`      | `amount` in wei                                              |

> **Agent Guidelines**: Convert wei amounts to PHRS by dividing by 10^18.
> Convert `topics[1]` (orderId) from hex to decimal with `cast --to-dec`.
> Include `https://atlantic.pharosscan.xyz/tx/<txHash>` for each event.
> If no logs returned, clearly state no activity has occurred yet on this contract.
> The deploy block can be read from `broadcast/.../run-latest.json`
> (`.receipts[0].blockNumber`, hex — convert with `cast --to-dec`).

---

## Composability with Other Pharos Skills

PayPerTask is designed to compose with other Pharos Skills in the
Skill-to-Agent Cascade. Each integration is a concrete data shape, not a
buzzword:

- **Storage Proof Skill** → emits a CID/hash that this skill consumes as the
  `string resultHash` argument of `completeOrder(orderId, resultHash)`.
- **Inference Skill** → executes the task whose `bytes32 inputHash` was
  committed in `createOrder`. The output of inference is fed to Storage Proof,
  whose CID then closes the loop.
- **Rating Skill** → subscribes to `OrderCompleted(uint256 indexed orderId, string resultHash, uint256 paidToAgent, uint256 paidToPlatform, uint256 paidToEcosystem)`
  and indexes by the `agent` address (read via `getOrder(orderId).agent`) to
  build per-agent reputation.
- **x402 Skill** → can use the same escrow primitive for off-hot-path
  micropayments; `createOrder` becomes the L1 anchor, x402 channels handle the
  high-frequency settlement.

A higher-level Agent reads the **Capability Index** in `SKILL.md`, locates this
skill's section, and chains
`createOrder → (Inference Skill executes work) → (Storage Proof returns CID) → completeOrder`
while other skills handle the work itself.
