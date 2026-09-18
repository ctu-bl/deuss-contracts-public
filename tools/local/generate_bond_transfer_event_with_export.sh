#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${ANVIL_RPC_URL:-http://127.0.0.1:8545}"
OUT="deployments/31337_anvil_GenerateBondTransferEvent_events.json"
HISTORY_OUT="deployments/31337_anvil_GenerateBondTransferEvent_history.json"

usage() {
  cat <<'USAGE'
Usage: tools/local/generate_bond_transfer_event_with_export.sh [--rpc-url URL] [--out FILE] [--history-out FILE]

Runs the idempotent GenerateBondTransferEvent Foundry script against a running Anvil
node, then exports decoded events from the generated broadcast receipts.
The entropy seed is always derived from the latest block number and timestamp.
The latest export is overwritten on each run; the history export is appended.

Environment overrides supported by the Solidity script include:
  BOND_TRANSFER_EVENT_ISIN
  BOND_TRANSFER_EVENT_CURRENCY
  BOND_TRANSFER_EVENT_ISSUE_AMOUNT
  BOND_TRANSFER_EVENT_MAX_SUPPLY
  BOND_TRANSFER_EVENT_OWNER_A_KEY
  BOND_TRANSFER_EVENT_OWNER_B_KEY
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rpc-url)
      RPC_URL="$2"
      shift 2
      ;;
    --out)
      OUT="$2"
      shift 2
      ;;
    --history-out)
      HISTORY_OUT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL")"
if [[ "$CHAIN_ID" != "31337" ]]; then
  echo "Expected Anvil chain id 31337, got $CHAIN_ID from $RPC_URL" >&2
  exit 1
fi

LATEST_BLOCK_JSON="$(cast rpc --rpc-url "$RPC_URL" eth_getBlockByNumber latest false)"
BLOCK_NUMBER_HEX="$(jq -r '.number' <<<"$LATEST_BLOCK_JSON")"
BLOCK_TIMESTAMP_HEX="$(jq -r '.timestamp' <<<"$LATEST_BLOCK_JSON")"
BLOCK_NUMBER="$((16#${BLOCK_NUMBER_HEX#0x}))"
BLOCK_TIMESTAMP="$((16#${BLOCK_TIMESTAMP_HEX#0x}))"
ENTROPY_SEED="$((BLOCK_NUMBER ^ BLOCK_TIMESTAMP))"
echo "Using entropy seed $ENTROPY_SEED from latest block number $BLOCK_NUMBER and timestamp $BLOCK_TIMESTAMP"

export BOND_TRANSFER_EVENT_ENTROPY_BLOCK="$ENTROPY_SEED"

make generate_bond_transfer_event ANVIL_RPC_URL="$RPC_URL"

make export_logs \
  BROADCAST=broadcast/GenerateBondTransferEvent.s.sol/31337/run-latest.json \
  DEPLOYMENT=deployments/31337_anvil_latest.json \
  OUT="$OUT" \
  RPC_URL="$RPC_URL"

python3 tools/local/append_transfer_event_history.py \
  --latest "$OUT" \
  --history "$HISTORY_OUT" \
  --entropy-seed "$ENTROPY_SEED"

echo "Decoded events written to $OUT"
echo "Decoded event history appended to $HISTORY_OUT"
