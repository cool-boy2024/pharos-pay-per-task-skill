# Submission — Pharos Skill-to-Agent Dual Cascade Hackathon (Phase 1 — Skill)

**Project**: PayPerTask Skill for Pharos AI Agents
**Author**: 镇东 ([HackQuest @2405947](https://hackquest.io/profile/2405947), [GitHub @cool-boy2024](https://github.com/cool-boy2024))
**Submitted to**: [Pharos Skill-to-Agent Dual Cascade Hackathon](https://dorahacks.io/hackathon/pharos-phase1) — Phase 1 (Skill Hackathon)
**Submission deadline**: 2026-06-18 23:59

---

## TL;DR

The economic primitive of the Pharos Skill-to-Agent Cascade: **deposit →
deliver → split**, all on chain.

Drop this skill into a Pharos AI Agent and any user can ask in natural language:

- *"Deploy a pay-per-task escrow on Pharos with a custom 85/10/5 split"*
- *"Order a token risk brief from the agent I deployed yesterday for 0.05 PHRS"*
- *"Mark order 7 delivered with proof ipfs://..."*
- *"Show me all completed orders on this contract"*
- *"Dispute order 3 — agent never delivered"*

The agent reads `SKILL.md`, finds the matching capability, opens
`references/payperask.md`, and runs the right `cast` / `forge` command —
following the Pharos Skill Engine v0.1.0 convention exactly.

## Why Pharos specifically (not just a 0G port)

Three concrete reasons:

1. **The Skill-to-Agent Cascade needs an economic primitive.** Phase 2 (Agent
   Arena) assumes paid agents; nothing in Phase 1 ships that. Every other
   skill (Storage Proof, Inference, Rating, x402) plugs into PayPerTask's
   `inputHash`/`resultHash` shape. This skill is the missing piece.
2. **Sub-second confirmation makes per-task billing UX viable.** On Pharos the
   buyer's `createOrder` confirms before the agent's prompt finishes
   streaming. The same flow on slower L1s feels like a wire transfer.
3. **Pull-payment fallback hardens multi-recipient splits at scale.** A
   misbehaving fee recipient credits a `pendingWithdrawals` ledger instead of
   bricking the agent's payout — partial-failure recovery as a built-in,
   not an afterthought.

## Submission Artifacts

| Required item                  | Where                                                                                                                |
|--------------------------------|----------------------------------------------------------------------------------------------------------------------|
| **GitHub repo**                | https://github.com/cool-boy2024/pharos-pay-per-task-skill                                                            |
| **`SKILL.md` entry point**     | https://github.com/cool-boy2024/pharos-pay-per-task-skill/blob/main/SKILL.md                                         |
| **Reference file**             | https://github.com/cool-boy2024/pharos-pay-per-task-skill/blob/main/references/payperask.md                          |
| **Solidity contract**          | https://github.com/cool-boy2024/pharos-pay-per-task-skill/blob/main/assets/payperask/PayPerTaskEscrow.sol            |
| **Foundry deploy script**      | https://github.com/cool-boy2024/pharos-pay-per-task-skill/blob/main/script/DeployPayPerTaskEscrow.s.sol              |
| **Forge test suite**           | https://github.com/cool-boy2024/pharos-pay-per-task-skill/blob/main/test/PayPerTaskEscrow.t.sol                      |
| **Network config**             | https://github.com/cool-boy2024/pharos-pay-per-task-skill/blob/main/assets/networks.json                             |
| **End-to-end demo script**     | https://github.com/cool-boy2024/pharos-pay-per-task-skill/blob/main/examples/basic-agent-using-skill.sh              |
| **Agent transcript**           | https://github.com/cool-boy2024/pharos-pay-per-task-skill/blob/main/examples/agent-transcript.md                     |
| **Origin video (AgentMart on 0G)** | https://youtu.be/4jcaj5i5zhM                                                                                  |
| **Pharos walkthrough video**   | _to be filled in before final submission — see "Demo Plan" below_                                                    |
| **Deployed contract address**  | _to be filled in after testnet deploy — see "Deployment Plan" below_                                                  |

## How this maps to the Pharos Skill Engine v0.1.0 spec

The Pharos Skill Engine docs define a Skill as a folder with `SKILL.md` (entry
point) + `assets/` + `references/` + supporting templates. This submission
matches that structure exactly:

| Spec element                                                  | This submission                                                       |
|----------------------------------------------------------------|------------------------------------------------------------------------|
| `SKILL.md` with Capability Index, Prerequisites, Pre-checks   | ✅ `SKILL.md` in repo root                                             |
| `assets/networks.json` for chain config (incl. faucet)        | ✅ `assets/networks.json`                                              |
| `assets/<skill>/<Contract>.sol` template                      | ✅ `assets/payperask/PayPerTaskEscrow.sol`                             |
| `src/<skill>/<Contract>.sol` build copy (byte-identical)      | ✅ `src/payperask/PayPerTaskEscrow.sol`                                |
| `references/<skill>.md` per-operation spec                    | ✅ `references/payperask.md` (deploy / verify / order / complete / dispute / refund / withdraw / query / events) |
| Capability Index rows for every public op                     | ✅ 10 capability rows mapping NL intents to references                 |
| 4-part section template per op (Cmd / Params / Output / Errors) | ✅ Every op uses the spec template                                   |
| Write Operation Pre-checks documented                         | ✅ "Write Operation Pre-checks (Mandatory)" section in `SKILL.md`      |
| Error tables match exact custom-error names                   | ✅ Every custom error mapped in `references/payperask.md`              |
| Composability story                                           | ✅ Architecture diagram in README + "Composability" section in reference |
| Forge test coverage                                           | ✅ `test/PayPerTaskEscrow.t.sol` (constructor / split / dispute / refund / pull-payment) |

## Why this Skill — Hackathon judging-criteria alignment

| Pharos judging criterion          | How PayPerTask scores                                                                                                                |
|-----------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| **Originality / creativity**      | First Pharos Skill that turns "agent gets paid per task" into a 1-line natural language operation. Pull-payment fallback is novel for an escrow primitive at this layer. |
| **Technical quality / completeness** | Full operation surface: deploy / verify / createOrder / completeOrder / disputeOrder / refundOrder / withdraw / getOrder + 6 events. All have command templates, parameter tables, output parsing rules, error handling. Forge test suite covers happy-path, dispute resolution, refund, pull-payment fallback, role-based authorization, and direct-send rejection. |
| **Practical use case for AI Agents** | Every paid AI agent on Pharos needs this. Composes with Storage Proof, Inference, Rating, x402 skills (see architecture diagram in README). |
| **Reusability / composability**   | Per-order agent address (any agent can use it without redeploy). Configurable bps split (every project picks its own economics). Pull-payment ledger keeps multi-recipient flows safe. Designed to plug into Skill-to-Agent Cascade. |
| **Successful deployment / integration on Pharos** | Targets Atlantic Testnet (chainId 688689). Uses canonical `cast` / `forge` workflow per Skill Engine docs. Deployed address pending (see Deployment Plan). |
| **UX / documentation clarity**    | Reference file follows the exact 4-part section template (Command Template / Parameters / Output Parsing / Error Handling) the docs prescribe. Plus an end-to-end runnable bash demo and an agent-transcript example. |
| **Alignment with Pharos AI Agent vision** | Pay-per-task is the foundational economic primitive of an agent economy. This skill makes that primitive 1-line trivial for any builder. |

## Origin — adapted and hardened from AgentMart

This skill is a Pharos-native re-implementation of [AgentMart](https://github.com/cool-boy2024/0g-agentmart),
my submission to the **0G APAC Hackathon Track 3** (March–May 2026, 7-week build).

What I added/hardened for Pharos:

| Concern                | AgentMartEscrow (0G original)               | PayPerTaskEscrow (Pharos)                                            |
|------------------------|---------------------------------------------|----------------------------------------------------------------------|
| Agent address          | Single `creatorRecipient` set at deploy     | Per-order `agent` (multi-agent marketplace, no redeploy needed)      |
| Dispute path           | None                                        | `disputeOrder` + 7-day window + admin `refundOrder` + admin `completeOrder` (resolve-in-agent's-favor) |
| Revenue split          | Hard-coded 85/10/5                          | Constructor-validated bps (must sum to 10,000)                       |
| Fee-recipient failure  | Reverts the whole completion                | Pull-payment fallback (`pendingWithdrawals` + `withdraw()`)          |
| Reverts                | `require` strings                           | Custom errors (cheaper gas, structured)                              |
| Status enum            | `Created/Processing/Completed/Failed`       | `None/Created/Completed/Disputed/Refunded` (slot 0 reserved)         |
| Result hash            | `string`                                    | `string` (kept for IPFS / 0G / arweave compatibility)                |
| Input commitment       | `bytes32 inputHash`                         | Same — used to bind agent output to the original task                |
| Tests                  | None (Next.js webapp)                       | Forge test suite (constructor / split / dispute / refund / pull-payment / role checks) |
| Skill Engine integration | None (was a webapp)                         | Full `SKILL.md` + reference file + Capability Index per Pharos spec  |

## Composability with the Skill-to-Agent Cascade

Each integration is a concrete data shape, not a buzzword:

- **Storage Proof Skill** → emits a CID/hash that this skill consumes as the
  `string resultHash` argument of `completeOrder(orderId, resultHash)`.
- **Inference Skill** → executes the task whose `bytes32 inputHash` was
  committed in `createOrder`. Its output feeds Storage Proof, whose CID closes
  the loop.
- **Rating Skill** → subscribes to
  `OrderCompleted(uint256 indexed orderId, string resultHash, uint256 paidToAgent, uint256 paidToPlatform, uint256 paidToEcosystem)`
  and indexes by the `agent` address (read via `getOrder(orderId).agent`) to
  build per-agent reputation.
- **x402 Skill** → uses the same primitive for off-hot-path micropayments;
  `createOrder` becomes the L1 anchor, x402 channels handle high-frequency
  settlement.

A higher-level Agent reads the Capability Index in `SKILL.md`, locates this
skill's section, and chains
`createOrder → (Inference Skill executes work) → (Storage Proof returns CID) → completeOrder`
while other skills handle the work itself. See the architecture diagram in
[README.md](./README.md#architecture-composability-with-the-skill-to-agent-cascade).

## Deployment Plan (testnet)

The repo ships a runnable end-to-end demo. Once the user has Foundry + a
funded testnet wallet:

```bash
git clone --recurse-submodules https://github.com/cool-boy2024/pharos-pay-per-task-skill
cd pharos-pay-per-task-skill
curl -L https://foundry.paradigm.xyz | bash       # restart shell, then:
foundryup

export PRIVATE_KEY=0xYourTestnetKey
export RPC=https://atlantic.dplabs-internal.com

# Get testnet PHRS from https://testnet.pharosnetwork.xyz/, then:
forge build
forge test -vv
bash examples/basic-agent-using-skill.sh
```

Output: deployed contract address, `OrderCreated` tx, `OrderCompleted` tx,
final state read, all events queried, pull-payment ledger checked.
~30 seconds end-to-end.

## Demo Plan

- **Origin video (AgentMart on 0G)**: https://youtu.be/4jcaj5i5zhM
- **Pharos walkthrough**: 60-second screencast running `examples/basic-agent-using-skill.sh`
  + a Claude Code session showing the agent reading `SKILL.md` and answering
  *"Deploy PayPerTask on Pharos with default split, then run a 0.001 PHRS
  demo order from me to myself."* — to be added before final submission.

## Roadmap (Phase 2 — Agent Arena)

If this Skill lands a Phase 1 prize, Phase 2 is to build a complete Agent that
composes this skill with three others:

1. **Token Risk Brief Agent** — reuses AgentMart's UX, now with on-chain
   billing. Target: first 10 paid orders on Atlantic within 4 weeks.
2. **Storage Proof Skill integration** — `resultHash` becomes a real IPFS / 0G
   CID, pinned and provable.
3. **Rating Skill integration** — `OrderCompleted` events drive agent reputation,
   indexed by `agent` address.
4. **x402 settlement** — micropayments for high-frequency agent calls,
   anchored to the L1 escrow.

## License

MIT
