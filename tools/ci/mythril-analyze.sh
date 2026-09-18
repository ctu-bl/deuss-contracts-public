#!/usr/bin/env bash
# Run Mythril symbolic analysis over the core deployable contracts and write an
# aggregated JSON report. Used by the scheduled `sec-mythril` GitLab CI job
# (RQ_SEC_STATIC). Mythril is heavy, so this is meant for the weekly scheduled
# pipeline rather than every merge request.
#
# Exit codes (mirrors the High gate of tools/ci/slither-json-highest-impact):
#   0   no High-severity finding (Medium/Low/none are report-only here)
#   10  at least one High-severity finding -> fail the pipeline
#
# Per-contract compile/timeout/crash failures are recorded in the report as
# coverage gaps and do NOT fail the run on their own (Mythril is flaky on large
# via-ir contracts); only real High findings gate.
#
# Environment overrides:
#   MYTHRIL_SOLC_VERSION   solc version Mythril installs/uses (default: 0.8.34)
#   MYTHRIL_SOLC_BINARY    exact solc binary to use (default: solc on PATH)
#   MYTHRIL_EXEC_TIMEOUT   per-contract symbolic-execution timeout, seconds (default: 120)
#   MYTHRIL_REPORT         output report path (default: ./mythril-report.json)
#   MYTHRIL_SUPPRESSIONS   suppression DB path (default: ./mythril.db.json)
#   MYTHRIL_TARGETS        newline/space separated target files (default: list below)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

SOLC_VERSION="${MYTHRIL_SOLC_VERSION:-0.8.34}"
EXEC_TIMEOUT="${MYTHRIL_EXEC_TIMEOUT:-120}"
REPORT="${MYTHRIL_REPORT:-$REPO_ROOT/mythril-report.json}"
SUPPRESSIONS="${MYTHRIL_SUPPRESSIONS:-$REPO_ROOT/mythril.db.json}"

# Core deployable contracts (entrypoints with real logic). Interfaces, *Storage,
# *Structs, libraries and base/ abstracts are intentionally excluded.
DEFAULT_TARGETS="
src/marketplace/Marketplace.sol
src/marketplace/OrderbookMarketplace.sol
src/marketplace/EscrowManager.sol
src/marketplace/AssetManager.sol
src/marketplace/filters/BondMarketFilter.sol
src/marketplace/validators/DeussBondValidator.sol
src/marketplace/lens/MarketplaceLens.sol
src/registry/BondRegistry.sol
src/registry/EntityRegistry.sol
src/registry/PolicyRegistry.sol
src/token/fungible/DEUSSToken.sol
src/wallet/CompanyWallet.sol
src/wallet/WalletFactory.sol
src/governance/TimelockController.sol
"
TARGETS="${MYTHRIL_TARGETS:-$DEFAULT_TARGETS}"

if ! command -v myth >/dev/null 2>&1; then
  echo "ERROR: 'myth' (Mythril) not found on PATH." >&2
  echo "Install it with:  pip install 'setuptools<81' mythril" >&2
  exit 127
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Mythril 0.24.x resolves compiler versions through py-solc-x. On macOS this can
# pick stale ~/.solcx wrapper scripts even when `solc --version` is correct.
# Expose a temporary py-solc-x install folder and PATH wrapper that both point
# to the exact compiler binary verified below. If PATH still points at another
# solc version, fall back to the binary installed by `solc-select install`.
SOLC_BINARY="${MYTHRIL_SOLC_BINARY:-$(command -v solc || true)}"
if [ -z "$SOLC_BINARY" ]; then
  echo "ERROR: 'solc' not found on PATH." >&2
  echo "Install/select solc ${SOLC_VERSION}, or set MYTHRIL_SOLC_BINARY to the exact compiler path." >&2
  exit 127
fi
if [ ! -x "$SOLC_BINARY" ]; then
  echo "ERROR: solc binary is not executable: $SOLC_BINARY" >&2
  exit 127
fi

SOLC_VERSION_OUTPUT="$("$SOLC_BINARY" --version 2>&1 || true)"
if ! printf '%s\n' "$SOLC_VERSION_OUTPUT" | grep -q "Version: ${SOLC_VERSION}"; then
  SOLC_SELECT_BINARY="${HOME:-}/.solc-select/artifacts/solc-${SOLC_VERSION}/solc-${SOLC_VERSION}"
  if [ -z "${MYTHRIL_SOLC_BINARY:-}" ] && [ -x "$SOLC_SELECT_BINARY" ]; then
    SOLC_SELECT_VERSION_OUTPUT="$("$SOLC_SELECT_BINARY" --version 2>&1 || true)"
    if printf '%s\n' "$SOLC_SELECT_VERSION_OUTPUT" | grep -q "Version: ${SOLC_VERSION}"; then
      SOLC_BINARY="$SOLC_SELECT_BINARY"
      SOLC_VERSION_OUTPUT="$SOLC_SELECT_VERSION_OUTPUT"
    fi
  fi
fi

if ! printf '%s\n' "$SOLC_VERSION_OUTPUT" | grep -q "Version: ${SOLC_VERSION}"; then
  echo "ERROR: expected solc ${SOLC_VERSION}, but '$SOLC_BINARY --version' returned:" >&2
  printf '%s\n' "$SOLC_VERSION_OUTPUT" >&2
  echo "Run 'solc-select install ${SOLC_VERSION} && solc-select use ${SOLC_VERSION}'," >&2
  echo "or set MYTHRIL_SOLC_BINARY to the exact ${SOLC_VERSION} compiler binary." >&2
  exit 2
fi

export MYTHRIL_REAL_SOLC_BINARY="$SOLC_BINARY"
SOLC_BIN_DIR="$WORKDIR/bin"
SOLCX_DIR="$WORKDIR/solcx"
mkdir -p "$SOLC_BIN_DIR" "$SOLCX_DIR"
SOLC_PATH_WRAPPER="$SOLC_BIN_DIR/solc"
cat > "$SOLC_PATH_WRAPPER" <<'EOF'
#!/usr/bin/env bash
exec "${MYTHRIL_REAL_SOLC_BINARY:?}" "$@"
EOF
chmod +x "$SOLC_PATH_WRAPPER"
cp "$SOLC_PATH_WRAPPER" "$SOLCX_DIR/solc-v$SOLC_VERSION"

export PATH="$SOLC_BIN_DIR:$PATH"
export SOLC="$SOLC_PATH_WRAPPER"
export SOLCX_BINARY_PATH="$SOLCX_DIR"
export MYTHRIL_DIR="${MYTHRIL_DIR:-$WORKDIR/mythril}"
export MPLCONFIGDIR="${MPLCONFIGDIR:-$WORKDIR/matplotlib}"
mkdir -p "$MYTHRIL_DIR" "$MPLCONFIGDIR"

# Build the solc standard-json "settings" Mythril needs to resolve imports and
# match the production build. Remappings come from remappings.txt; the optimizer
# / EVM / via-ir flags mirror [profile.default] in foundry.toml.
SETTINGS="$WORKDIR/solc-settings.json"
jq -n --argjson rem "$(grep -v '^[[:space:]]*$' remappings.txt \
        | sed 's/[[:space:]]*$//' | jq -R . | jq -s .)" '{
  remappings: $rem,
  optimizer: { enabled: true, runs: 200 },
  evmVersion: "cancun",
  viaIR: true
}' > "$SETTINGS"

# Pick a hard wall-clock guard so a hung compile/solver cannot stall the job.
# `timeout` exists on the Linux CI image; fall back to no wrapper locally.
HARD_TIMEOUT=$((EXEC_TIMEOUT + 120))
if command -v timeout >/dev/null 2>&1; then
  GUARD=(timeout --kill-after=30 "$HARD_TIMEOUT")
else
  GUARD=()
fi

metas=()
echo "Using $(myth version 2>/dev/null | tail -1) with solc ${SOLC_VERSION} - analyzing $(echo $TARGETS | wc -w | tr -d ' ') target(s), ${EXEC_TIMEOUT}s each"
echo

for file in $TARGETS; do
  [ -n "$file" ] || continue
  meta="$WORKDIR/$(echo "$file" | tr '/' '_').meta.json"
  out="$WORKDIR/$(echo "$file" | tr '/' '_').out.json"

  if [ ! -f "$file" ]; then
    printf '  %-55s MISSING\n' "$file"
    jq -n --arg f "$file" '{file:$f,status:"error",error:"file not found",issues:[]}' > "$meta"
    metas+=("$meta")
    continue
  fi

  rc=0
  "${GUARD[@]+"${GUARD[@]}"}" myth analyze "$file" \
      --solc-json "$SETTINGS" \
      --solv "$SOLC_VERSION" \
      --execution-timeout "$EXEC_TIMEOUT" \
      -o json > "$out" 2> "$out.err" || rc=$?

  # Mythril exits 0 (no issues) or 1 (issues found); both emit valid JSON.
  # Anything else (compile error, timeout, crash) is a coverage gap, not a gate.
  if jq -e 'has("issues")' "$out" >/dev/null 2>&1; then
    err="$(jq -r '.error // empty' "$out")"
    if [ -n "$err" ]; then
      status="error"
    else
      status="ok"
    fi
    jq --arg f "$file" --arg s "$status" --arg e "$err" \
       '{file:$f, status:$s, error:$e, issues:(.issues // [])}' "$out" > "$meta"
  else
    status="error"
    err="$(tail -3 "$out.err" 2>/dev/null | tr '\n' ' ' | tr -d '"')"
    [ "$rc" -eq 124 ] && status="timeout" && err="hard wall-clock timeout (${HARD_TIMEOUT}s)"
    jq -n --arg f "$file" --arg s "$status" --arg e "$err" \
       '{file:$f, status:$s, error:$e, issues:[]}' > "$meta"
  fi

  count="$(jq '.issues | length' "$meta")"
  printf '  %-55s %-8s %s issue(s)\n' "$file" "$status" "$count"
  metas+=("$meta")
done

if [ ${#metas[@]} -eq 0 ]; then
  echo "No targets to analyze (MYTHRIL_TARGETS is empty)." >&2
  echo '{"generated_at":"","targets":[],"issues":[]}' > "$REPORT"
  exit 0
fi

# Aggregate every contract's issues (tagged with their source file) into one report.
jq -s '{
  generated_at: (now | todateiso8601),
  targets: [ .[] | {file, status, error, issue_count: (.issues | length)} ],
  issues: [ .[] | (.issues[]? + {file: .file}) ]
}' "${metas[@]}" > "$REPORT"

if [ -f "$SUPPRESSIONS" ]; then
  filtered="$WORKDIR/report.filtered.json"
  jq --slurpfile db "$SUPPRESSIONS" '
    def matches($issue; $s):
      (($s.file == null or $s.file == $issue.file)
       and ($s.contract == null or $s.contract == $issue.contract)
       and ($s.function == null or $s.function == $issue.function)
       and ($s.title == null or $s.title == $issue.title)
       and ($s.severity == null or $s.severity == $issue.severity)
       and ($s.sourceMap == null or $s.sourceMap == $issue.sourceMap)
       and ($s["swc-id"] == null or $s["swc-id"] == $issue["swc-id"]));
    ($db[0].suppressions // []) as $sup
    | .issues as $all
    | ([ $all[] as $issue | $issue | select(any($sup[] as $s | matches($issue; $s))) ]) as $suppressed
    | ([ $all[] as $issue | $issue | select((any($sup[] as $s | matches($issue; $s)) | not)) ]) as $active
    | .issues = $active
    | .suppressed_issues = $suppressed
    | .targets = [
        .targets[] as $target
        | $target + {issue_count: ([ $active[] | select(.file == $target.file)] | length)}
      ]
  ' "$REPORT" > "$filtered"
  mv "$filtered" "$REPORT"
fi

echo
echo "=== Mythril summary ==="
jq -r '
  "targets analyzed : \(.targets | length)",
  "  ok / error / timeout : \([.targets[]|select(.status=="ok")]|length) / \([.targets[]|select(.status=="error")]|length) / \([.targets[]|select(.status=="timeout")]|length)",
  "suppressed issues : \(.suppressed_issues // [] | length)",
  "total issues     : \(.issues | length)",
  "  High / Medium / Low  : \([.issues[]|select(.severity=="High")]|length) / \([.issues[]|select(.severity=="Medium")]|length) / \([.issues[]|select(.severity=="Low")]|length)"
' "$REPORT"
echo "report written to: $REPORT"

highest="$("$REPO_ROOT/tools/ci/mythril-json-highest-severity" "$REPORT")"
echo "highest severity : $highest"

if [ "$highest" = "High" ]; then
  echo "FAIL: Mythril reported High-severity finding(s)." >&2
  exit 10
fi
exit 0
