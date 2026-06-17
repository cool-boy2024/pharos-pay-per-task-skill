#!/usr/bin/env bash
# End-to-end demo of the PayPerTask Skill via raw cast commands.
#
# Prerequisites:
#   curl -L https://foundry.paradigm.xyz | bash         # restart shell, then:
#   foundryup
#   export PRIVATE_KEY=0x...                            # buyer = agent = admin (testnet)
#   export RPC=https://atlantic.dplabs-internal.com
#   export DEPLOYER=$(cast wallet address --private-key $PRIVATE_KEY)
#
# Run from repo root:
#   bash examples/basic-agent-using-skill.sh
#
# What this script demonstrates:
#   1. Deploy escrow with default 85/10/5 split
#   2. Create an order escrowing 0.001 PHRS
#   3. Complete the order with a fake delivery proof
#   4. Read the resulting state, the OrderCompleted event, and confirm no
#      payment was deferred
#
set -euo pipefail

# ── Preconditions ─────────────────────────────────────────────────────
command -v cast >/dev/null 2>&1 || { echo "✗ cast not found. Install Foundry: curl -L https://foundry.paradigm.xyz | bash && foundryup"; exit 1; }
command -v forge >/dev/null 2>&1 || { echo "✗ forge not found. Install Foundry: curl -L https://foundry.paradigm.xyz | bash && foundryup"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "✗ jq required. brew install jq (or apt-get install jq)"; exit 1; }

: "${PRIVATE_KEY:?Set PRIVATE_KEY first: export PRIVATE_KEY=0x...}"
: "${RPC:=https://atlantic.dplabs-internal.com}"
: "${DEPLOYER:=$(cast wallet address --private-key "$PRIVATE_KEY")}"

# Confirm the RPC is alive and on the right chain (688689 = Atlantic).
CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
[ "$CHAIN_ID" = "688689" ] || { echo "✗ Wrong chain: $CHAIN_ID (expected 688689 — Pharos Atlantic)"; exit 1; }

echo "▸ Deployer: $DEPLOYER"
echo "▸ RPC:      $RPC"
echo "▸ Chain id: $CHAIN_ID"
echo

# ── 1. Deploy ──────────────────────────────────────────────────────────
echo "▸ Deploying PayPerTaskEscrow…"
forge script script/DeployPayPerTaskEscrow.s.sol:DeployPayPerTaskEscrow \
  --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast

# Authoritative source: Foundry's broadcast manifest. Pharos Atlantic = chainId 688689.
RUN_LATEST="broadcast/DeployPayPerTaskEscrow.s.sol/${CHAIN_ID}/run-latest.json"
[ -f "$RUN_LATEST" ] || { echo "✗ Missing $RUN_LATEST — deploy script never broadcast."; exit 1; }

ESCROW=$(jq -r '.transactions[] | select(.transactionType=="CREATE") | .contractAddress' "$RUN_LATEST" | head -1)
DEPLOY_TX=$(jq -r '.transactions[] | select(.transactionType=="CREATE") | .hash' "$RUN_LATEST" | head -1)
DEPLOY_BLOCK_HEX=$(jq -r '.receipts[] | select(.transactionHash=="'"$DEPLOY_TX"'") | .blockNumber' "$RUN_LATEST" | head -1)
DEPLOY_BLOCK=$(cast --to-dec "$DEPLOY_BLOCK_HEX")

if [ -z "$ESCROW" ] || [ "$ESCROW" = "null" ]; then
  echo "✗ Deploy failed. See $RUN_LATEST"
  exit 1
fi

echo "✓ Deployed at:  $ESCROW"
echo "  Deploy tx:    https://atlantic.pharosscan.xyz/tx/$DEPLOY_TX"
echo "  Address:      https://atlantic.pharosscan.xyz/address/$ESCROW"
echo "  From block:   $DEPLOY_BLOCK"
echo

# ── 2. Create order (buyer escrows 0.001 PHRS) ─────────────────────────
INPUT_HASH=$(cast keccak "demo prompt: token risk brief for Pharos")
echo "▸ Creating order: agent=$DEPLOYER, value=0.001 PHRS, inputHash=$INPUT_HASH"

CREATE_TX=$(cast send "$ESCROW" "createOrder(address,bytes32)" "$DEPLOYER" "$INPUT_HASH" \
  --value 0.001ether --private-key "$PRIVATE_KEY" --rpc-url "$RPC" --json | jq -r '.transactionHash')
[ -n "$CREATE_TX" ] && [ "$CREATE_TX" != "null" ] || { echo "✗ createOrder failed"; exit 1; }
echo "✓ OrderCreated tx: https://atlantic.pharosscan.xyz/tx/$CREATE_TX"

# Decode orderId from the receipt's OrderCreated log (topics[1] = orderId).
ORDER_ID_HEX=$(cast receipt "$CREATE_TX" --rpc-url "$RPC" --json | jq -r '.logs[0].topics[1]')
ORDER_ID=$(cast --to-dec "$ORDER_ID_HEX")
echo "  orderId = $ORDER_ID"
echo

# ── 3. Agent completes order ───────────────────────────────────────────
RESULT_HASH="ipfs://QmDemoDeliveryProofForPharosHackathon"
echo "▸ Completing order $ORDER_ID with resultHash=$RESULT_HASH"

COMPLETE_TX=$(cast send "$ESCROW" "completeOrder(uint256,string)" "$ORDER_ID" "$RESULT_HASH" \
  --private-key "$PRIVATE_KEY" --rpc-url "$RPC" --json | jq -r '.transactionHash')
[ -n "$COMPLETE_TX" ] && [ "$COMPLETE_TX" != "null" ] || { echo "✗ completeOrder failed"; exit 1; }
echo "✓ OrderCompleted tx: https://atlantic.pharosscan.xyz/tx/$COMPLETE_TX"
echo

# ── 4. Read final state ────────────────────────────────────────────────
echo "▸ Final order state:"
cast call "$ESCROW" "getOrder(uint256)(address,address,uint256,uint8,bytes32,string,uint64)" \
  "$ORDER_ID" --rpc-url "$RPC"
echo

echo "▸ OrderCompleted events on this contract (since deploy block):"
cast logs --rpc-url "$RPC" --address "$ESCROW" --from-block "$DEPLOY_BLOCK" \
  "OrderCompleted(uint256,string,uint256,uint256,uint256)" || true
echo

# Pull-payment ledger (should be 0 when buyer = agent = admin = single EOA).
PENDING=$(cast call "$ESCROW" "pendingWithdrawals(address)(uint256)" "$DEPLOYER" --rpc-url "$RPC")
echo "▸ pendingWithdrawals[$DEPLOYER] = $PENDING wei"
echo

echo "✓ Done. Skill flow: deploy → createOrder → completeOrder → split."
