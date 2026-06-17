---
name: paypertask-skill
version: 0.1.0
network: pharos
description: |
  Deploy and operate a pay-per-task escrow on Pharos so AI agents can charge
  users per task with on-chain settlement. Buyers escrow PHRS, agents submit
  delivery proofs, and funds split between agent / platform / ecosystem.
  Includes a 7-day dispute window with admin refund, plus a pull-payment
  fallback that prevents a misbehaving fee recipient from bricking the agent's
  payout. Built for the Skill-to-Agent Cascade Hackathon, June 2026. Adapted
  from the AgentMart marketplace prototype (0G APAC Hackathon Track 3).
author: 镇东 (HackQuest @2405947, GitHub @cool-boy2024)
license: MIT
---

# PayPerTask Skill

> v0.1.0 · Pharos Atlantic Testnet · Pharos Skill-to-Agent Cascade Hackathon submission (Phase 1)

This skill turns any Pharos AI Agent into a paid agent: buyers escrow PHRS,
the agent delivers, funds split on-chain. Composes with Storage Proof,
Inference, and Rating skills.

The skill is read by an AI agent at runtime (e.g. Claude Code). The agent
matches user intents to capabilities below, then opens
`references/payperask.md` for the exact `cast` / `forge` commands.

## Prerequisites

The agent must satisfy these before running any operation:

1. **Foundry installed** (`which cast` returns a path; if not, run
   `curl -L https://foundry.paradigm.xyz | bash`, restart your shell, then
   `foundryup`).
2. **`$PRIVATE_KEY` set** in the current shell (`export PRIVATE_KEY=0x...`).
3. **Pharos RPC reachable** (default: `https://atlantic.dplabs-internal.com`).
4. **Wallet has PHRS** for gas + escrow value (faucet:
   `https://testnet.pharosnetwork.xyz/`).

> **Foundry does NOT read `$PRIVATE_KEY` automatically.** Always pass it explicitly
> as `--private-key $PRIVATE_KEY` in every command. This is the single most common
> source of confusion.

## Network Configuration

Read `assets/networks.json` for the active network. Defaults shipped:

| Network          | Chain ID | RPC                                          | Explorer                              |
|------------------|----------|----------------------------------------------|---------------------------------------|
| Atlantic Testnet | `688689` | `https://atlantic.dplabs-internal.com`       | `https://atlantic.pharosscan.xyz`     |

Pacific Mainnet support is on the v0.2 roadmap; this skill targets Atlantic
Testnet for Phase 1.

## Capability Index

| User Need (how a user might phrase it)                                                                 | Capability                                              | Detailed Instructions                                                          |
|---------------------------------------------------------------------------------------------------------|---------------------------------------------------------|--------------------------------------------------------------------------------|
| Deploy PayPerTask escrow / set up agent marketplace / charge users per request                          | `forge script` + built-in PayPerTaskEscrow template     | → `references/payperask.md#deploy-paypertaskescrow`                            |
| Verify my contract on Pharos Scan / publish source                                                       | `forge verify-contract` against Pharos Scan             | → `references/payperask.md#verify-paypertaskescrow`                            |
| Buy / order from an agent / escrow PHRS for a task / pay an agent on Pharos                             | `cast send createOrder` payable                         | → `references/payperask.md#create-order-buyer-escrows-phrs`                    |
| Mark order delivered / claim payment / submit delivery proof / agent settles task                       | `cast send completeOrder`                               | → `references/payperask.md#complete-order-agent-submits-delivery-proof`        |
| Dispute order / open refund request / report agent failed                                               | `cast send disputeOrder`                                | → `references/payperask.md#dispute-order-buyer-opens-dispute-within-7-days`    |
| Refund buyer / resolve dispute (admin) / return funds                                                    | `cast send refundOrder`                                 | → `references/payperask.md#refund-order-admin-refunds-after-dispute`           |
| Withdraw a deferred payment / claim a stuck fee / pull-payment escape hatch                             | `cast send withdraw`                                    | → `references/payperask.md#withdraw-deferred-payment-pull-payment-fallback`    |
| Show order status / read order / look up order id / get buyer/agent/amount                              | `cast call getOrder` / `nextOrderId`                    | → `references/payperask.md#query-order-state`                                  |
| Show order history / list past orders / completed orders / disputes / refunds on this contract         | `cast logs` for `OrderCreated` / `OrderCompleted` / `OrderDisputed` / `OrderRefunded` | → `references/payperask.md#query-events-order-history`             |
| How does this compose with storage / inference / rating skills?                                         | Composability guide                                     | → `references/payperask.md#composability-with-other-pharos-skills`             |

## General Error Handling

| CLI Signature                       | Cause                                          | Fix                                                              |
|-------------------------------------|------------------------------------------------|------------------------------------------------------------------|
| `forge: command not found`          | Foundry not installed                          | `curl -L https://foundry.paradigm.xyz \| bash`, then restart shell and `foundryup` |
| `connection refused`                | `--rpc-url` missing                            | Always pass `--rpc-url $RPC` explicitly                          |
| `PRIVATE_KEY` not set               | env var missing in current shell               | `export PRIVATE_KEY=0x...`                                       |
| `nonce too low`                     | Previous tx still pending                      | Wait or set `--nonce` manually                                   |
| `insufficient funds`                | Wallet balance < amount + gas                  | Get testnet PHRS from `https://testnet.pharosnetwork.xyz/`       |
| `execution reverted: 0x...`         | Custom error (4-byte selector)                 | `cast 4byte 0x...` to resolve, then see per-op tables in `references/payperask.md` |
| `execution reverted: <reason>`      | Contract revert with named selector            | See per-operation Error Handling tables in `references/payperask.md` |

## Security Reminders

- **Use a dedicated testnet wallet** — never reuse a key that has held mainnet funds.
- **Never hardcode `$PRIVATE_KEY`** in scripts or commit to git. The repo's
  `.gitignore` excludes every `.env*` shape (only `.env.example` is checked in).
- **Prefer `cast wallet import` + `--account <name>`** over `--private-key`
  for interactive use to avoid keys landing in shell history.
- **Always confirm the network and recipient addresses** before broadcasting any
  `cast send` or `forge script --broadcast` command.
- **Admin authority is centralized in v0.** The admin can `refundOrder` and
  resolve disputes via `completeOrder`. Treat the admin key as a single point of
  trust until v1 introduces an on-chain juror system. Before running any admin
  operation, the agent MUST confirm `cast call <escrow> 'admin()(address)'`
  matches the caller's derived address.
- **Pull-payment fallback** — if a fee recipient is a contract that reverts
  on receive, the deferred amount is credited to `pendingWithdrawals` and the
  recipient (or anyone on their behalf) can call `withdraw(<recipient>)` later.
  Funds always go to `<recipient>`; this cannot be used to redirect payouts.

## Write Operation Pre-checks (Mandatory)

Every operation that sends a transaction MUST pass these four checks before
the agent runs the command. This is enforced and cannot be skipped.

1. **Private key set** — `[ -n "$PRIVATE_KEY" ]`.
2. **Address derives** — `cast wallet address --private-key $PRIVATE_KEY`
   matches the expected role (buyer/agent/admin). When `BUYER_ADDRESS`,
   `AGENT_ADDRESS`, or `ADMIN_ADDRESS` env hints are set, the derived address
   should equal the role being invoked.
3. **Network reachable** — `cast chain-id --rpc-url $RPC` returns exactly `688689`.
4. **Balance covers amount + gas** — `cast balance <addr> --rpc-url $RPC --ether`
   compared against `<value> + ~0.001`.

## How the Agent Resolves a Request — Step by Step

1. User makes a natural-language request.
2. Agent reads this `SKILL.md` → scans the Capability Index for matching intent.
3. Agent reads the linked anchor in `references/payperask.md`.
4. Agent reads `assets/networks.json` to resolve `rpcUrl` and `chainId`.
5. For write operations: agent runs all four pre-checks above.
6. Agent executes the `cast` or `forge` command with `--private-key $PRIVATE_KEY`.
7. Agent parses output per the Output Parsing rules in the reference.
8. Agent shows the result + a Pharos Scan link
   (`https://atlantic.pharosscan.xyz/tx/<hash>` or `/address/<addr>`).

## File Structure

```
pharos-pay-per-task-skill/
├── SKILL.md                          ← this file (AI agent entry point)
├── README.md                         ← human-facing project README
├── SUBMISSION.md                     ← hackathon submission map
├── .env.example                      ← copy to .env, fill in PRIVATE_KEY
├── .gitmodules                       ← registers lib/forge-std as a submodule
├── foundry.toml
├── assets/
│   ├── networks.json                 ← RPC, chain id, explorer, faucet
│   └── payperask/
│       └── PayPerTaskEscrow.sol      ← contract template (built-in)
├── src/
│   └── payperask/
│       └── PayPerTaskEscrow.sol      ← copy used by foundry build path
├── script/
│   └── DeployPayPerTaskEscrow.s.sol  ← Foundry deploy script
├── test/
│   └── PayPerTaskEscrow.t.sol        ← forge test suite
├── references/
│   └── payperask.md                  ← detailed operation instructions
├── examples/
│   ├── basic-agent-using-skill.sh    ← end-to-end demo as cast commands
│   └── agent-transcript.md           ← what an AI agent actually does at runtime
└── lib/forge-std                     ← submodule, pulled via --recurse-submodules
```

## Origin / Acknowledgements

This skill is a Pharos-native re-implementation of the **AgentMart** marketplace
prototype (0G APAC Hackathon Track 3, March–May 2026). The original
`AgentMartEscrow.sol` had a 3-recipient split with no dispute path; this skill
adds, for Pharos:

- Per-order agent address (multi-agent marketplace, not single creator)
- 7-day dispute window with admin refund + admin resolve-in-favor
- Configurable basis-point split (validated to sum to 10,000)
- Custom errors for cheaper reverts
- Pull-payment fallback so a misbehaving recipient never bricks the agent's payout
- Composability with the broader Pharos Skill ecosystem

Origin repo: https://github.com/cool-boy2024/0g-agentmart
