#!/usr/bin/env bash
# End-to-end demo of the PayPerTask Skill via raw cast commands.
#
# Prerequisites:
#   curl -L https://foundry.paradigm.xyz | bash && foundryup
#   export PRIVATE_KEY=0x...                # buyer = agent = admin (testnet)
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
#   4. Read the resulting state and balances
#
set -euo pipefail

: "${PRIVATE_KEY:?Set PRIVATE_KEY first: export PRIVATE_KEY=0x...}"
: "${RPC:=https://atlantic.dplabs-internal.com}"
: "${DEPLOYER:=$(cast wallet address --private-key "$PRIVATE_KEY")}"

echo "▸ Deployer: $DEPLOYER"
echo "▸ RPC:      $RPC"
echo

# ── 1. Deploy ──────────────────────────────────────────────────────────
echo "▸ Deploying PayPerTaskEscrow…"
forge script script/DeployPayPerTaskEscrow.s.sol:DeployPayPerTaskEscrow \
  --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast

# Authoritative source: Foundry's broadcast manifest. Pharos Atlantic = chainId 688689.
CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
RUN_LATEST="broadcast/DeployPayPerTaskEscrow.s.sol/${CHAIN_ID}/run-latest.json"
ESCROW=$(jq -r '.transactions[] | select(.transactionType=="CREATE") | .contractAddress' "$RUN_LATEST" | head -1)
if [ -z "$ESCROW" ] || [ "$ESCROW" = "null" ]; then
  echo "✗ Deploy failed. See $RUN_LATEST"
  exit 1
fi
echo "✓ Deployed at: $ESCROW"
echo "  Explorer:    https://atlantic.pharosscan.xyz/address/$ESCROW"
echo

# ── 2. Create order (buyer escrows 0.001 PHRS) ─────────────────────────
INPUT_HASH=$(cast keccak "demo prompt: token risk brief for 0G")
echo "▸ Creating order: agent=$DEPLOYER, value=0.001 PHRS, inputHash=$INPUT_HASH"
CREATE_TX=$(cast send "$ESCROW" "createOrder(address,bytes32)" "$DEPLOYER" "$INPUT_HASH" \
  --value 0.001ether --private-key "$PRIVATE_KEY" --rpc-url "$RPC" --json | jq -r '.transactionHash')
echo "✓ OrderCreated tx: https://atlantic.pharosscan.xyz/tx/$CREATE_TX"

ORDER_ID=$(cast call "$ESCROW" "nextOrderId()(uint256)" --rpc-url "$RPC")
ORDER_ID=$((ORDER_ID - 1))
echo "  orderId = $ORDER_ID"
echo

# ── 3. Agent completes order ───────────────────────────────────────────
RESULT_HASH="ipfs://QmDemoDeliveryProof123"
echo "▸ Completing order $ORDER_ID with resultHash=$RESULT_HASH"
COMPLETE_TX=$(cast send "$ESCROW" "completeOrder(uint256,string)" "$ORDER_ID" "$RESULT_HASH" \
  --private-key "$PRIVATE_KEY" --rpc-url "$RPC" --json | jq -r '.transactionHash')
echo "✓ OrderCompleted tx: https://atlantic.pharosscan.xyz/tx/$COMPLETE_TX"
echo

# ── 4. Read final state ────────────────────────────────────────────────
echo "▸ Final order state:"
cast call "$ESCROW" "getOrder(uint256)(address,address,uint256,uint8,bytes32,string,uint64)" \
  "$ORDER_ID" --rpc-url "$RPC"
echo
echo "▸ OrderCompleted events on this contract:"
cast logs --rpc-url "$RPC" --address "$ESCROW" \
  "OrderCompleted(uint256,string,uint256,uint256,uint256)" --from-block 0 || true
echo
echo "✓ Done. Skill flow: deploy → createOrder → completeOrder → split."
