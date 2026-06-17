# PayPerTask Skill for Pharos

> **Pay-per-task escrow primitive for AI Agents on Pharos.** Buyers escrow PHRS,
> agents submit delivery proofs, funds split on-chain between agent / platform / ecosystem.
> Includes a 7-day dispute window with admin refund.

🏆 **Submitted to**: [Pharos Skill-to-Agent Dual Cascade Hackathon](https://dorahacks.io/hackathon/pharos-phase1) — Phase 1 (Skill), June 2026
🌊 **Network**: Pharos Atlantic Testnet (chainId `688689`)
📦 **Forked from**: [AgentMart](https://github.com/cool-boy2024/0g-agentmart) (0G APAC Hackathon Track 3, March–May 2026)
📺 **Demo (origin)**: https://youtu.be/4jcaj5i5zhM

---

## Why this Skill

The Pharos AI Agent ecosystem needs paid agents. This skill is the smallest
useful primitive that makes that work: **deposit → deliver → split**, all on chain.

Drop this skill into a Pharos AI Agent and any user can ask:

- *"Deploy a pay-per-task escrow on Pharos with an 80/15/5 split"*
- *"Order a token risk brief from agent 0xABC for 0.05 PHRS"*
- *"Mark order 7 delivered with proof ipfs://..."*
- *"Show me all completed orders on this contract"*
- *"Dispute order 3 — agent never delivered"*

The agent reads `SKILL.md`, finds the matching capability, opens
`references/payperask.md`, and runs the right `cast` / `forge` command.

## File Structure

```
pharos-pay-per-task-skill/
├── SKILL.md                          ← AI agent entry point
├── README.md                         ← this file
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
├── references/
│   └── payperask.md                  ← detailed operation instructions
└── examples/
    └── basic-agent-using-skill.sh    ← end-to-end demo (deploy → order → settle)
```

## Quick start (for humans)

```bash
# 1. Clone with submodules (forge-std lives in lib/)
git clone --recurse-submodules https://github.com/cool-boy2024/pharos-pay-per-task-skill
cd pharos-pay-per-task-skill
# (already cloned without submodules? run: git submodule update --init --recursive)

# 2. Install Foundry
curl -L https://foundry.paradigm.xyz | bash && source ~/.zshenv && foundryup

# 3. Configure
export PRIVATE_KEY=0xYourTestnetKey
export RPC=https://atlantic.dplabs-internal.com

# 4. Get testnet PHRS (see Pharos faucet)

# 5. Build + run the end-to-end demo
forge build
bash examples/basic-agent-using-skill.sh
```

You'll see the script:

1. Deploy `PayPerTaskEscrow` with default 85/10/5 split
2. Create order escrowing 0.001 PHRS against `keccak("demo prompt")`
3. Mark the order completed with `ipfs://...` as the delivery proof
4. Print the final on-chain state and `OrderCompleted` event

## Quick start (for AI agents)

```bash
# Inside the skill folder
claude  # or any AI agent that follows the Pharos Skill convention
```

Then ask, in natural language: *"Deploy PayPerTask on Pharos and run a demo
order from me to myself for 0.001 PHRS."*

The agent reads `SKILL.md`, follows the Capability Index to
`references/payperask.md`, and runs each step with the correct `cast` / `forge`
commands.

## Contract — `PayPerTaskEscrow.sol`

| Function                             | Caller    | Effect                                                              |
|--------------------------------------|-----------|---------------------------------------------------------------------|
| `createOrder(agent, inputHash)`      | Buyer     | Escrows `msg.value` PHRS for a task delivered by `agent`            |
| `completeOrder(orderId, resultHash)` | Agent/Admin | Releases escrow split between agent / platform / ecosystem        |
| `disputeOrder(orderId, reason)`      | Buyer     | Opens dispute within 7 days; blocks completion                      |
| `refundOrder(orderId)`               | Admin     | Returns full escrow to buyer (resolves dispute)                     |
| `getOrder(orderId)`                  | anyone    | Reads buyer / agent / amount / status / hashes / createdAt          |

Events: `OrderCreated`, `OrderCompleted`, `OrderDisputed`, `OrderRefunded`.

## What changed vs. AgentMartEscrow (0G version)

| Concern                | AgentMartEscrow (0G)                               | PayPerTaskEscrow (Pharos)                                          |
|------------------------|----------------------------------------------------|--------------------------------------------------------------------|
| Agent address          | Single `creatorRecipient` set at deploy            | Per-order `agent` (multi-agent marketplace)                        |
| Dispute path           | None                                               | `disputeOrder` + 7-day window + admin `refundOrder`                |
| Split                  | Hard-coded 85/10/5 in `completeOrder`              | Constructor-validated bps (must sum to 10,000)                     |
| Reverts                | `require` strings                                  | Custom errors (cheaper gas, structured)                            |
| Status                 | `Created/Processing/Completed/Failed`              | `None/Created/Completed/Disputed/Refunded` (None reserves slot 0)  |
| Result hash            | `string`                                           | `string` (kept for IPFS / 0G / arweave compatibility)              |
| Input commitment       | `bytes32 inputHash`                                | Same — used to bind agent output to the original task              |

## Composability

Designed to plug into the Pharos Skill-to-Agent Cascade:

- **Storage Proof Skill** → produces the `resultHash` passed to `completeOrder`
- **Inference Skill** → executes the task whose `keccak(prompt)` was committed in `createOrder`
- **Rating Skill** → reads `OrderCompleted` events to update agent reputation
- **x402 Skill** → can use the same primitive for off-hot-path settlement

A higher-level Agent reads the Capability Index in `SKILL.md`, locates this
skill's section, and chains `createOrder → (work delegated to other skills) → completeOrder`.

## Hackathon submission (Phase 1 — Skill)

| Requirement                                  | Where                                                                    |
|----------------------------------------------|--------------------------------------------------------------------------|
| GitHub repo                                  | `https://github.com/cool-boy2024/pharos-pay-per-task-skill`              |
| `SKILL.md` follows Pharos Skill Engine spec  | [SKILL.md](./SKILL.md)                                                   |
| Reference file with cast/forge commands      | [references/payperask.md](./references/payperask.md)                     |
| Solidity contract template                   | [assets/payperask/PayPerTaskEscrow.sol](./assets/payperask/PayPerTaskEscrow.sol) |
| Foundry deploy script                        | [script/DeployPayPerTaskEscrow.s.sol](./script/DeployPayPerTaskEscrow.s.sol) |
| Network config                               | [assets/networks.json](./assets/networks.json)                           |
| End-to-end demo                              | [examples/basic-agent-using-skill.sh](./examples/basic-agent-using-skill.sh) |
| Composability story                          | See "Composability" above + bottom of `references/payperask.md`          |

## Roadmap (Phase 2 — Agent Arena)

If this skill lands a Phase 1 prize, Phase 2 is to build a complete Agent that
composes this skill with three others:

1. **Token Risk Brief Agent** — reuses AgentMart's UX, now with on-chain billing
2. **Storage Proof Skill integration** — `resultHash` becomes a real IPFS / 0G CID
3. **Rating Skill integration** — `OrderCompleted` events drive agent reputation
4. **x402 settlement** — micropayments for high-frequency agent calls

## Author

**镇东** — HackQuest builder [`@2405947`](https://hackquest.io/profile/2405947) · GitHub [`@cool-boy2024`](https://github.com/cool-boy2024)

Originally built [AgentMart](https://github.com/cool-boy2024/0g-agentmart) for the 0G APAC Hackathon Track 3 (March–May 2026, Grand Prizes + Community track).

## License

MIT
