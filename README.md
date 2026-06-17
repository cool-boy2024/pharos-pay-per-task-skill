# PayPerTask Skill for Pharos

> **The economic primitive of the Pharos Skill-to-Agent Cascade.** One
> natural-language sentence → on-chain escrow → split payout to agent /
> platform / ecosystem. The smallest piece every paid Pharos AI agent needs.

🏆 **Submitted to**: [Pharos Skill-to-Agent Dual Cascade Hackathon](https://dorahacks.io/hackathon/pharos-phase1) — Phase 1 (Skill), June 2026
🌊 **Network**: Pharos Atlantic Testnet (chainId `688689`)
📦 **Adapted from**: [AgentMart](https://github.com/cool-boy2024/0g-agentmart) (0G APAC Hackathon Track 3, March–May 2026)
📺 **Origin video** (AgentMart on 0G — Pharos walkthrough TBD): https://youtu.be/4jcaj5i5zhM

---

## Why this Skill

The Pharos AI Agent ecosystem needs paid agents. This skill is the smallest
useful primitive that makes that work: **deposit → deliver → split**, all on chain.

Drop this skill into a Pharos AI Agent and any user can ask:

- *"Deploy a pay-per-task escrow on Pharos with a custom 85/10/5 split"*
- *"Order a token risk brief from the agent I deployed yesterday for 0.05 PHRS"*
- *"Mark order 7 delivered with proof ipfs://..."*
- *"Show me all completed orders on this contract"*
- *"Dispute order 3 — agent never delivered"*
- *"Withdraw the deferred fee for the platform recipient"*

The agent reads `SKILL.md`, finds the matching capability, opens
`references/payperask.md`, and runs the right `cast` / `forge` command.

## Why Pharos specifically

This isn't a 0G port. Three Pharos-specific reasons this skill belongs here:

1. **The Skill-to-Agent Cascade needs an economic primitive.** The Phase 2
   Agent Arena assumes agents that can be paid; nothing in Phase 1 ships that.
   PayPerTask is the missing piece — every other skill (Storage Proof,
   Inference, Rating, x402) plugs into `createOrder`/`completeOrder`'s
   `inputHash`/`resultHash` shape.
2. **Sub-second confirmation makes per-task billing UX viable.** On Pharos,
   the buyer's `createOrder` confirms before the agent's prompt finishes
   streaming. The same UX on slower L1s makes pay-per-task feel like a wire
   transfer; on Pharos it feels like a tap.
3. **Pull-payment fallback hardens the multi-recipient split.** A misbehaving
   platform/ecosystem recipient credits a `pendingWithdrawals` ledger instead
   of bricking the agent's payout. This matters more on a high-throughput
   chain where partial-failure recovery is expected, not exceptional.

## Architecture (composability with the Skill-to-Agent Cascade)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ User: "Order a token risk brief from agent 0xABC for 0.05 PHRS"         │
└─────────────────────────────────────────────────────────────────────────┘
                                  │
              ┌───────────────────▼─────────────────────┐
              │   Pharos AI Agent (reads SKILL.md)      │
              └───┬───────────────┬───────────────┬─────┘
                  │               │               │
        ┌─────────▼──────┐ ┌──────▼───────┐ ┌─────▼──────────────┐
        │ PayPerTask     │ │ Inference    │ │ Storage Proof      │
        │ createOrder    │ │ Skill        │ │ Skill              │
        │ (inputHash)    │ │ runs prompt  │ │ pins result → CID  │
        └────────┬───────┘ └──────┬───────┘ └─────┬──────────────┘
                 │                │               │
                 │                └───────┬───────┘
                 │                        │
                 │                ┌───────▼─────────────────┐
                 │                │ resultHash (CID)        │
                 │                └───────┬─────────────────┘
                 │                        │
        ┌────────▼────────────────────────▼─────────┐
        │ PayPerTask completeOrder(orderId, result) │
        │  → 85% agent  / 10% platform / 5% ecosys  │
        │  → emits OrderCompleted (read by Rating)  │
        └────────────────────┬──────────────────────┘
                             │
                  ┌──────────▼───────────┐
                  │ Rating Skill         │
                  │ updates agent rep    │
                  └──────────────────────┘
```

## File Structure

```
pharos-pay-per-task-skill/
├── SKILL.md                          ← AI agent entry point
├── README.md                         ← this file
├── SUBMISSION.md                     ← hackathon submission map
├── .env.example                      ← copy to .env, fill in PRIVATE_KEY
├── foundry.toml
├── assets/
│   ├── networks.json                 ← Pharos Atlantic testnet config
│   └── payperask/
│       └── PayPerTaskEscrow.sol      ← contract template (built-in)
├── src/
│   └── payperask/
│       └── PayPerTaskEscrow.sol      ← src/ copy used by forge build
├── script/
│   └── DeployPayPerTaskEscrow.s.sol  ← Foundry deploy script
├── test/
│   └── PayPerTaskEscrow.t.sol        ← forge test suite (constructor, split, dispute, refund, pull-payment)
├── references/
│   └── payperask.md                  ← detailed operation instructions
├── examples/
│   ├── basic-agent-using-skill.sh    ← end-to-end demo (deploy → order → settle)
│   └── agent-transcript.md           ← what an AI agent actually does at runtime
└── lib/forge-std                     ← submodule, pulled via --recurse-submodules
```

## Quick start (for humans)

```bash
# 1. Clone with submodules (forge-std lives in lib/)
git clone --recurse-submodules https://github.com/cool-boy2024/pharos-pay-per-task-skill
cd pharos-pay-per-task-skill
# (already cloned without submodules? run: git submodule update --init --recursive)

# 2. Install Foundry
curl -L https://foundry.paradigm.xyz | bash
# Restart your shell, then:
foundryup

# 3. Configure
export PRIVATE_KEY=0xYourTestnetKey
export RPC=https://atlantic.dplabs-internal.com

# 4. Get testnet PHRS from the Pharos faucet:
#    https://testnet.pharosnetwork.xyz/

# 5. Build, test, then run the end-to-end demo
forge build
forge test -vv
bash examples/basic-agent-using-skill.sh
```

You'll see the script:

1. Deploy `PayPerTaskEscrow` with default 85/10/5 split
2. Create order escrowing 0.001 PHRS against `keccak("demo prompt …")`
3. Mark the order completed with `ipfs://...` as the delivery proof
4. Print the final on-chain state and `OrderCompleted` event

You can also use the `pharos_atlantic` rpc alias from `foundry.toml` if you
prefer (`forge script ... --rpc-url pharos_atlantic`).

## Quick start (for AI agents)

```bash
# Inside the skill folder
claude  # or any AI agent that follows the Pharos Skill convention
```

Then ask, in natural language: *"Deploy PayPerTask on Pharos and run a demo
order from me to myself for 0.001 PHRS."*

The agent reads `SKILL.md`, follows the Capability Index to
`references/payperask.md`, and runs each step with the correct `cast` / `forge`
commands. See `examples/agent-transcript.md` for what this looks like end to
end.

## Contract — `PayPerTaskEscrow.sol`

| Function                             | Caller       | Effect                                                              |
|--------------------------------------|--------------|---------------------------------------------------------------------|
| `createOrder(agent, inputHash)`      | Buyer        | Escrows `msg.value` PHRS for a task delivered by `agent`            |
| `completeOrder(orderId, resultHash)` | Agent / Admin| Releases escrow split between agent / platform / ecosystem (admin can resolve a Disputed order in agent's favor) |
| `disputeOrder(orderId, reason)`      | Buyer        | Opens dispute within 7 days; blocks completion                      |
| `refundOrder(orderId)`               | Admin        | Returns full escrow to buyer (resolves dispute)                     |
| `withdraw(recipient)`                | anyone       | Pull-payment escape: pushes `pendingWithdrawals[recipient]` to the recipient |
| `getOrder(orderId)`                  | anyone       | Reads buyer / agent / amount / status / hashes / createdAt          |
| `nextOrderId()`                      | anyone       | Auto-incrementing counter (`getOrder(nextOrderId-1)` = latest)      |

Events: `OrderCreated`, `OrderCompleted`, `OrderDisputed`, `OrderRefunded`,
`PaymentDeferred`, `PaymentWithdrawn`.

Custom errors: `ZeroAmount`, `ZeroAddress`, `BadAgent`, `InvalidStatus`,
`NotAuthorized`, `DisputeWindowClosed`, `InvalidSplit`, `TransferFailed`,
`NothingToWithdraw`.

## What changed vs. AgentMartEscrow (0G version)

| Concern                | AgentMartEscrow (0G)                               | PayPerTaskEscrow (Pharos)                                          |
|------------------------|----------------------------------------------------|--------------------------------------------------------------------|
| Agent address          | Single `creatorRecipient` set at deploy            | Per-order `agent` (multi-agent marketplace, no redeploy needed)    |
| Dispute path           | None                                               | `disputeOrder` + 7-day window + admin `refundOrder` + admin `completeOrder` (resolve in agent's favor) |
| Split                  | Hard-coded 85/10/5 in `completeOrder`              | Constructor-validated bps (must sum to 10,000)                     |
| Fee-recipient failure  | Reverts the whole completion                       | Pull-payment fallback (`pendingWithdrawals` + `withdraw()`)        |
| Reverts                | `require` strings                                  | Custom errors (cheaper gas, structured)                            |
| Status                 | `Created/Processing/Completed/Failed`              | `None/Created/Completed/Disputed/Refunded` (None reserves slot 0)  |
| Result hash            | `string`                                           | `string` (kept for IPFS / 0G / arweave compatibility)              |
| Input commitment       | `bytes32 inputHash`                                | Same — used to bind agent output to the original task              |
| Tests                  | None (Next.js webapp)                              | Forge test suite covering split / dispute / refund / pull-payment / role checks |

## Hackathon submission (Phase 1 — Skill)

| Requirement                                  | Where                                                                    |
|----------------------------------------------|--------------------------------------------------------------------------|
| GitHub repo                                  | `https://github.com/cool-boy2024/pharos-pay-per-task-skill`              |
| `SKILL.md` follows Pharos Skill Engine spec  | [SKILL.md](./SKILL.md)                                                   |
| Reference file with cast/forge commands      | [references/payperask.md](./references/payperask.md)                     |
| Solidity contract template                   | [assets/payperask/PayPerTaskEscrow.sol](./assets/payperask/PayPerTaskEscrow.sol) |
| Foundry deploy script                        | [script/DeployPayPerTaskEscrow.s.sol](./script/DeployPayPerTaskEscrow.s.sol) |
| Forge test suite                             | [test/PayPerTaskEscrow.t.sol](./test/PayPerTaskEscrow.t.sol)             |
| Network config                               | [assets/networks.json](./assets/networks.json)                           |
| End-to-end demo                              | [examples/basic-agent-using-skill.sh](./examples/basic-agent-using-skill.sh) |
| Agent transcript                             | [examples/agent-transcript.md](./examples/agent-transcript.md)           |
| Composability story                          | See "Architecture" diagram above + bottom of `references/payperask.md`   |

See [SUBMISSION.md](./SUBMISSION.md) for the full judging-criteria mapping.

## Roadmap (Phase 2 — Agent Arena)

If this skill lands a Phase 1 prize, Phase 2 is to build a complete Agent that
composes this skill with three others:

1. **Token Risk Brief Agent** — reuses AgentMart's UX with on-chain billing.
   Target: first 10 paid orders on Atlantic within 4 weeks of Phase 2 kickoff.
2. **Storage Proof Skill integration** — `resultHash` becomes a real IPFS / 0G
   CID, pinned and provable.
3. **Rating Skill integration** — `OrderCompleted` events drive agent reputation,
   indexed by `agent` address.
4. **x402 settlement** — micropayments for high-frequency agent calls,
   anchored to the L1 escrow.

## Author

**镇东** — HackQuest builder [`@2405947`](https://hackquest.io/profile/2405947) · GitHub [`@cool-boy2024`](https://github.com/cool-boy2024)

Originally built [AgentMart](https://github.com/cool-boy2024/0g-agentmart) for the 0G APAC Hackathon Track 3 (March–May 2026).

## License

MIT
