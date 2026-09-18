#!/usr/bin/env bash
set -eo pipefail

echidna_image="${ECHIDNA_IMAGE:-ghcr.io/crytic/echidna/echidna:v2.3.2}"
config_path="${ECHIDNA_CONFIG:-echidna-config.yaml}"
target_file="${ECHIDNA_TARGET_FILE:-test/fuzzing/Fuzz.sol}"
target_contract="${ECHIDNA_TARGET_CONTRACT:-Fuzz}"
format="${ECHIDNA_FORMAT:-text}"
container_name="${ECHIDNA_CONTAINER_NAME:-deuss-echidna-$(date +%Y%m%d-%H%M%S)}"
log_dir="${ECHIDNA_LOG_DIR:-logs/fuzzing}"
log_path="${log_dir}/${container_name}.log"
coverage_dir="${ECHIDNA_COVERAGE_DIR:-echidna-coverage}"
# GHCRTS passes options to Echidna's Haskell runtime without +RTS/-RTS wrappers.
# Echidna release builds enabled RTS options starting in 2.3.0, and GHC's
# -M<size> caps the Haskell heap so the runtime errors before the kernel kills
# the whole container. -s prints runtime memory stats.
ghc_rts_opts="${ECHIDNA_RTS_OPTS:--M16G -Mgrace=512M -c -s}"

cpus="${ECHIDNA_CPUS:-3}"
memory="${ECHIDNA_MEMORY:-14g}"

platform_args=()

case "$(uname -m)" in
  arm64|aarch64)
    platform_args=(--platform linux/amd64)
    ;;
esac

mkdir -p "${log_dir}"

# Run detached so Docker keeps the container after completion for inspection.
# Docker/Rosetta can emit a benign Echidna ticker warning before compilation
# starts; filter that exact line so it is not mistaken for the campaign result.
# Stream docker logs back to stdout and tee the same output into a timestamped
# local log file under logs/fuzzing/.
container_id="$(
  docker run \
  -d \
  --name "${container_name}" \
  "${platform_args[@]}" \
  --cpus "${cpus}" \
  --memory "${memory}" \
  -u "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -e FOUNDRY_PROFILE=echidna \
  -e GHCRTS="${ghc_rts_opts}" \
  -v "${PWD}:/src" \
  -w /src \
  "${echidna_image}" \
  echidna "${target_file}" \
    --contract "${target_contract}" \
    --config "${config_path}" \
    --format "${format}" \
    --coverage-dir "${coverage_dir}" \
    "$@"
)"

printf 'Echidna container: %s (%s)\n' "${container_name}" "${container_id}" | tee "${log_path}"
printf 'Echidna log: %s\n' "${log_path}" | tee -a "${log_path}"
printf 'Streaming Echidna logs; the initial compile can be silent for several minutes.\n' | tee -a "${log_path}"

set +e
docker logs -f "${container_id}" 2>&1 \
  | awk '$0 != "echidna: Ticker: poll failed: Interrupted system call: Interrupted system call" { print; fflush(); }' \
  | tee -a "${log_path}"
log_status=("${PIPESTATUS[@]}")
status="$(docker wait "${container_id}")"
wait_status="$?"
set -e

if [ "${log_status[0]}" -ne 0 ] || [ "${log_status[1]}" -ne 0 ] || [ "${log_status[2]}" -ne 0 ]; then
  printf 'Warning: log streaming exited non-zero; using docker wait status for campaign result.\n' | tee -a "${log_path}"
fi

if [ "${wait_status}" -ne 0 ]; then
  exit "${wait_status}"
fi

exit "${status}"
