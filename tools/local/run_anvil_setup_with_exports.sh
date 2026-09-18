#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RPC_URL="${ANVIL_RPC_URL:-http://127.0.0.1:8545}"
START_ANVIL=0
KEEP_ANVIL=0
STOP_ANVIL=0
ANVIL_HOST="127.0.0.1"
ANVIL_PORT="8545"
ANVIL_PID_FILE="${ROOT_DIR}/.tmp/anvil-events.pid"
ANVIL_LOG_FILE="${ROOT_DIR}/.tmp/anvil-events.log"

usage() {
  cat <<EOF
Run the full local Anvil flow and export decoded logs after each stage.

Usage:
  $(basename "$0") [--start-anvil] [--keep-anvil] [--rpc-url URL]
  $(basename "$0") --stop-anvil

Options:
  --start-anvil     Start a local Anvil instance in the background if needed.
  --keep-anvil      Keep Anvil running after the flow if this script started it.
  --stop-anvil      Stop the Anvil process previously kept alive by this script.
  --rpc-url URL     RPC URL to use. Default: ${RPC_URL}
  -h, --help        Show this help.

Outputs:
  deployments/31337_anvil_DeployProtocol_events.json
  deployments/31337_anvil_BootstrapProtocol_events.json
  deployments/31337_anvil_SeedDemoData_events.json
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start-anvil)
      START_ANVIL=1
      shift
      ;;
    --keep-anvil)
      KEEP_ANVIL=1
      shift
      ;;
    --stop-anvil)
      STOP_ANVIL=1
      shift
      ;;
    --rpc-url)
      RPC_URL="${2:?missing value for --rpc-url}"
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

stop_kept_anvil() {
  if [[ ! -f "${ANVIL_PID_FILE}" ]]; then
    echo "No kept Anvil PID file found at ${ANVIL_PID_FILE}" >&2
    exit 1
  fi

  local pid
  pid="$(cat "${ANVIL_PID_FILE}")"
  if [[ -z "${pid}" ]]; then
    echo "Kept Anvil PID file is empty: ${ANVIL_PID_FILE}" >&2
    exit 1
  fi

  if kill -0 "${pid}" >/dev/null 2>&1; then
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
    echo "Stopped kept Anvil process ${pid}"
  else
    echo "Kept Anvil process ${pid} is not running"
  fi
  rm -f "${ANVIL_PID_FILE}"
}

if [[ ${STOP_ANVIL} -eq 1 ]]; then
  stop_kept_anvil
  exit 0
fi

if [[ "${RPC_URL}" =~ ^http://([^:/]+):([0-9]+)$ ]]; then
  ANVIL_HOST="${BASH_REMATCH[1]}"
  ANVIL_PORT="${BASH_REMATCH[2]}"
fi

cleanup() {
  if [[ -n "${ANVIL_PID:-}" ]]; then
    kill "${ANVIL_PID}" >/dev/null 2>&1 || true
    wait "${ANVIL_PID}" >/dev/null 2>&1 || true
    rm -f "${ANVIL_PID_FILE}"
  fi
}

wait_for_rpc() {
  local attempts=0
  until cast block-number --rpc-url "${RPC_URL}" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [[ ${attempts} -ge 30 ]]; then
      echo "RPC endpoint did not become ready: ${RPC_URL}" >&2
      exit 1
    fi
    sleep 1
  done
}

start_anvil_if_needed() {
  if cast block-number --rpc-url "${RPC_URL}" >/dev/null 2>&1; then
    return
  fi

  if [[ ${START_ANVIL} -ne 1 ]]; then
    echo "Anvil is not reachable at ${RPC_URL}" >&2
    echo "Start it first, or rerun with --start-anvil." >&2
    exit 1
  fi

  echo "Starting Anvil at ${RPC_URL}"
  mkdir -p "${ROOT_DIR}/.tmp"
  nohup anvil --host "${ANVIL_HOST}" --port "${ANVIL_PORT}" --chain-id 31337 --disable-code-size-limit \
    >"${ANVIL_LOG_FILE}" 2>&1 &
  ANVIL_PID=$!
  if [[ ${KEEP_ANVIL} -eq 1 ]]; then
    echo "${ANVIL_PID}" >"${ANVIL_PID_FILE}"
  else
    trap cleanup EXIT
  fi
  wait_for_rpc
}

run_stage() {
  local name="$1"
  local make_target="$2"
  local broadcast_path="$3"
  local output_path="$4"

  echo "== ${name} =="
  (cd "${ROOT_DIR}" && make ANVIL_RPC_URL="${RPC_URL}" "${make_target}")
  (cd "${ROOT_DIR}" && make export_logs \
    BROADCAST="${broadcast_path}" \
    DEPLOYMENT="deployments/31337_anvil_latest.json" \
    OUT="${output_path}" \
    RPC_URL="${RPC_URL}")
}

start_anvil_if_needed

echo "== Install dependencies =="
(cd "${ROOT_DIR}" && forge soldeer install)

run_stage \
  "Deploy" \
  "deploy" \
  "broadcast/DeployProtocol.s.sol/31337/run-latest.json" \
  "deployments/31337_anvil_DeployProtocol_events.json"

run_stage \
  "Bootstrap" \
  "bootstrap" \
  "broadcast/BootstrapProtocol.s.sol/31337/run-latest.json" \
  "deployments/31337_anvil_BootstrapProtocol_events.json"

run_stage \
  "Mock Data" \
  "mock_data" \
  "broadcast/SeedDemoData.s.sol/31337/run-latest.json" \
  "deployments/31337_anvil_SeedDemoData_events.json"

echo "Completed local setup and exported decoded logs."
if [[ -n "${ANVIL_PID:-}" && ${KEEP_ANVIL} -eq 1 ]]; then
  echo "Anvil is still running at ${RPC_URL} with PID ${ANVIL_PID}."
  echo "Stop it with: npm run events:stop-anvil"
fi
