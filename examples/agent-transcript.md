# Example: AI Agent using PayPerTask Skill

What an AI agent (Claude Code, in this transcript) actually does at runtime
after a user drops the `pharos-pay-per-task-skill/` folder into its working
directory and asks a natural-language question. The agent reads `SKILL.md`,
follows the Capability Index, opens the right `references/payperask.md` anchor,
and runs the underlying `cast`/`forge` commands.

This file is the **show-don't-tell** complement to
`examples/basic-agent-using-skill.sh` (which is the same flow as raw bash
without the agent layer).

---

## Session

**User**: Deploy PayPerTask on Pharos Atlantic with the default 85/10/5 split,
then run a 0.001 PHRS demo order from me to myself.

**Agent** (internal):
1. Open `SKILL.md`. Match user intent → Capability Index row 1 (`Deploy PayPerTask escrow / set up agent marketplace …`). Open
   `references/payperask.md#deploy-paypertaskescrow`.
2. Run pre-checks:
   - `[ -n "$PRIVATE_KEY" ]` → ok
   - `cast wallet address --private-key $PRIVATE_KEY` → `0x21e3…576a`
   - `cast chain-id --rpc-url $RPC` → `688689` ✓
   - `cast balance 0x21e3…576a --rpc-url $RPC --ether` → `0.412` (covers gas + 0.001)
3. Confirm with user: deploying with admin=platform=ecosystem=`0x21e3…576a`, split 85/10/5 — proceed? (assumed yes)

**Agent → terminal**:

```bash
forge script script/DeployPayPerTaskEscrow.s.sol:DeployPayPerTaskEscrow \
  --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast
```

**Terminal**:
```
PayPerTaskEscrow deployed at: 0xABCD…1234
```

**Agent**: Deployed at `0xABCD…1234`. Pharos Scan: https://atlantic.pharosscan.xyz/address/0xABCD…1234

---

**Agent** (internal): User wants the demo order next. Capability Index row 3
(`Buy / order from an agent …`) → `references/payperask.md#create-order-buyer-escrows-phrs`.

**Agent → terminal**:

```bash
INPUT_HASH=$(cast keccak "demo prompt: token risk brief for Pharos")
cast send 0xABCD…1234 "createOrder(address,bytes32)" 0x21e3…576a $INPUT_HASH \
  --value 0.001ether --private-key $PRIVATE_KEY --rpc-url $RPC
```

**Terminal**:
```
transactionHash: 0xfeed…dead
```

**Agent**: Order created. Decoding `OrderCreated.topics[1]` from the receipt → orderId=`0`. Tx: https://atlantic.pharosscan.xyz/tx/0xfeed…dead

---

**User**: Mark it delivered.

**Agent** (internal): Capability Index row 4 → `references/payperask.md#complete-order-agent-submits-delivery-proof`.
Pre-check: `getOrder(0).status == 1` (Created) ✓. Caller is the agent address ✓.

**Agent → terminal**:

```bash
cast send 0xABCD…1234 "completeOrder(uint256,string)" 0 "ipfs://QmDemo…" \
  --private-key $PRIVATE_KEY --rpc-url $RPC
```

**Agent**: Completed. `OrderCompleted` event:
- `paidToAgent` = 850000000000000 wei (0.00085 PHRS)
- `paidToPlatform` = 100000000000000 wei (0.0001 PHRS)
- `paidToEcosystem` = 50000000000000 wei (0.00005 PHRS)
- No `PaymentDeferred` emitted → all three legs settled.

Tx: https://atlantic.pharosscan.xyz/tx/0xcafe…babe

---

## Why this is the agent-driven path

The user said three sentences. The agent ran six on-chain operations
(`forge script`, `cast wallet address`, `cast chain-id`, `cast balance`,
`cast send`, `cast send`) and decoded a receipt — all by reading exactly two
markdown files (`SKILL.md` + the right anchor of `references/payperask.md`)
and following the 4-part templates (Command Template / Parameters / Output
Parsing / Error Handling) the Pharos Skill Engine spec defines.

That is the entire point of the Skill Engine: a markdown bundle a user can
drop into any agent and get a precise, audited, reproducible on-chain flow
without the agent making anything up.
