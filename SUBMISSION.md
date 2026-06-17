# Submission — Pharos Skill-to-Agent Dual Cascade Hackathon (Phase 1 — Skill)

**Project**: PayPerTask Skill for Pharos AI Agents
**Author**: 镇东 ([HackQuest @2405947](https://hackquest.io/profile/2405947), [GitHub @cool-boy2024](https://github.com/cool-boy2024))
**Submitted to**: [Pharos Skill-to-Agent Dual Cascade Hackathon](https://dorahacks.io/hackathon/pharos-phase1) — Phase 1 (Skill Hackathon)
**Submission deadline**: 2026-06-18 23:59 (extended)

---

## TL;DR

The smallest useful Skill the Pharos AI Agent ecosystem needs: **deposit → deliver → split**, all on chain.

Drop this skill into a Pharos AI Agent and any user can ask in natural language:

- *"Deploy a pay-per-task escrow on Pharos with an 80/15/5 split"*
- *"Order a token risk brief from agent 0xABC for 0.05 PHRS"*
- *"Mark order 7 delivered with proof ipfs://..."*
- *"Show me all completed orders on this contract"*
- *"Dispute order 3 — agent never delivered"*

The agent reads `SKILL.md`, finds the matching capability, opens
`references/payperask.md`, and runs the right `cast` / `forge` command — exactly
following the Pharos Skill Engine v0.1.0 convention.

## Submission Artifacts

| Required item                  | Where                                                                                                                |
|--------------------------------|----------------------------------------------------------------------------------------------------------------------|
| **GitHub repo**                | https://github.com/cool-boy2024/pharos-pay-per-task-skill                                                            |
| **`SKILL.md` entry point**     | https://github.com/cool-boy2024/pharos-pay-per-task-skill/blob/main/SKILL.md                                         |
| **Reference file**             | https://github.com/cool-boy2024/pharos-pay-per-task-skill/blob/main/references/payperask.md                          |
| **Solidity contract**          | https://github.com/cool-boy2024/pharos-pay-per-task-skill/blob/main/assets/payperask/PayPerTaskEscrow.sol            |
| **Foundry deploy script**      | https://github.com/cool-boy2024/pharos-pay-per-task-skill/blob/main/script/DeployPayPerTaskEscrow.s.sol              |
| **Network config**             | https://github.com/cool-boy2024/pharos-pay-per-task-skill/blob/main/assets/networks.json                             |
| **End-to-end demo script**     | https://github.com/cool-boy2024/pharos-pay-per-task-skill/blob/main/examples/basic-agent-using-skill.sh              |
| **Demo video (origin AgentMart)** | https://youtu.be/4jcaj5i5zhM (Pharos walkthrough recording in progress — see "Demo Plan" below) |
| **Deployed contract address**  | _to be filled in after testnet deploy — see "Deployment Plan" below_                                                  |

## How this maps to the Pharos Skill Engine v0.1.0 spec

The Pharos Skill Engine docs define a Skill as a folder with `SKILL.md` (entry
point) + `assets/` + `references/` + supporting templates. This submission
matches that structure exactly:

| Spec element                                                  | This submission                                                       |
|----------------------------------------------------------------|------------------------------------------------------------------------|
| `SKILL.md` with Capability Index, Prerequisites, Pre-checks   | ✅ `SKILL.md` in repo root                                             |
| `assets/networks.json` for chain config                       | ✅ `assets/networks.json` (Atlantic + Pacific stubs)                   |
| `assets/<skill>/<Contract>.sol` template                      | ✅ `assets/payperask/PayPerTaskEscrow.sol`                             |
| `src/<skill>/<Contract>.sol` build copy                       | ✅ `src/payperask/PayPerTaskEscrow.sol`                                |
| `references/<skill>.md` per-operation spec                    | ✅ `references/payperask.md` (deploy / order / complete / dispute / refund / query / events) |
| Capability Index rows for every public op                     | ✅ 9 capability rows mapping natural-language intents to references    |
| Write Operation Pre-checks documented                         | ✅ "Write Operation Pre-checks (Mandatory)" section in `SKILL.md`      |
| Error tables match exact revert strings                       | ✅ Every custom error mapped in `references/payperask.md`              |
| Composability story                                           | ✅ "Composability with Other Pharos Skills" section in reference file  |

## Why this Skill — Hackathon judging-criteria alignment

| Pharos judging criterion          | How PayPerTask scores                                                                                                                |
|-----------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| **Originality / creativity**      | First Skill that turns "agent gets paid per task" into a 1-line natural language operation. Not just deploy-this-contract.            |
| **Technical quality / completeness** | Full operation surface: deploy / verify / createOrder / completeOrder / disputeOrder / refundOrder / getOrder + 4 events. All have command templates, parameter tables, output parsing rules, error handling. |
| **Practical use case for AI Agents** | Every paid AI agent on Pharos needs this. Composes with Storage Proof, Inference, Rating, x402 skills.                            |
| **Reusability / composability**   | Per-order agent address (any agent can use it without redeploy). Configurable bps split (every project picks its own economics). Designed to plug into Skill-to-Agent Cascade.|
| **Successful deployment / integration on Pharos** | Targets Atlantic Testnet (chainId 688689). Uses canonical `cast` / `forge` workflow per Skill Engine docs. |
| **UX / documentation clarity**    | Reference file follows the exact 4-part section template (Command Template / Parameters / Output Parsing / Error Handling) the docs prescribe. Plus an end-to-end runnable bash demo. |
| **Alignment with Pharos AI Agent vision** | Pay-per-task is the foundational economic primitive of an agent economy. This skill makes that primitive 1-line trivial for any builder. |

## Origin — adapted and hardened from AgentMart

This skill is a Pharos-native re-implementation of [AgentMart](https://github.com/cool-boy2024/0g-agentmart),
my submission to the **0G APAC Hackathon Track 3** (March–May 2026, Grand Prizes
+ Community track, 7-week build).

What I added/hardened for Pharos:

| Concern                | AgentMartEscrow (0G original)               | PayPerTaskEscrow (Pharos)                                            |
|------------------------|---------------------------------------------|----------------------------------------------------------------------|
| Agent address          | Single `creatorRecipient` set at deploy     | Per-order `agent` (multi-agent marketplace, no redeploy needed)      |
| Dispute path           | None                                        | `disputeOrder` + 7-day window + admin `refundOrder`                  |
| Revenue split          | Hard-coded 85/10/5                          | Constructor-validated bps (must sum to 10,000)                       |
| Reverts                | `require` strings                           | Custom errors (cheaper gas, structured)                              |
| Status enum            | `Created/Processing/Completed/Failed`       | `None/Created/Completed/Disputed/Refunded` (slot 0 reserved)         |
| Result hash            | `string`                                    | `string` (kept for IPFS / 0G / arweave compatibility)                |
| Input commitment       | `bytes32 inputHash`                         | Same — used to bind agent output to the original task                |
| Skill Engine integration | None (was a Next.js webapp)                 | Full `SKILL.md` + reference file + Capability Index per Pharos spec  |

## Composability with the Skill-to-Agent Cascade

This Skill is designed to plug into Phase 2 (Agent Arena) cleanly:

- **Storage Proof Skill** → produces the `resultHash` passed to `completeOrder`.
- **Inference Skill** → executes the task whose `keccak(prompt)` was committed in `createOrder`.
- **Rating Skill** → reads `OrderCompleted` events to update agent reputation.
- **x402 Skill** → uses the same primitive for off-hot-path micropayments.

A higher-level Agent reads the Capability Index in `SKILL.md`, locates this
skill's section, and chains `createOrder → (work delegated to other skills) → completeOrder`.

## Deployment Plan (testnet)

The repo ships a runnable end-to-end demo. Once the user has Foundry + a
funded testnet wallet:

```bash
git clone --recurse-submodules https://github.com/cool-boy2024/pharos-pay-per-task-skill
cd pharos-pay-per-task-skill
curl -L https://foundry.paradigm.xyz | bash && foundryup

export PRIVATE_KEY=0xYourTestnetKey
export RPC=https://atlantic.dplabs-internal.com

# Get testnet PHRS first, then:
forge build
bash examples/basic-agent-using-skill.sh
```

Output: deployed contract address, OrderCreated tx, OrderCompleted tx, final
state read, all events queried. ~30 seconds end-to-end.

## Demo Plan

- **Origin video (AgentMart on 0G)**: https://youtu.be/4jcaj5i5zhM
- **Pharos walkthrough**: 60-second screencast running `examples/basic-agent-using-skill.sh`
  + a Claude Code session showing the agent reading `SKILL.md` and answering
  *"Deploy PayPerTask on Pharos with default split, then run a 0.001 PHRS
  demo order from me to myself."* — to be added before final submission.

## Roadmap (Phase 2 — Agent Arena)

If this Skill lands a Phase 1 prize, Phase 2 is to build a complete Agent that
composes this skill with three others:

1. **Token Risk Brief Agent** — reuses AgentMart's UX, now with on-chain billing
2. **Storage Proof Skill integration** — `resultHash` becomes a real IPFS / 0G CID
3. **Rating Skill integration** — `OrderCompleted` events drive agent reputation
4. **x402 settlement** — micropayments for high-frequency agent calls

## License

MIT
