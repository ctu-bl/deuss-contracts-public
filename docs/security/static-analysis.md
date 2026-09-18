# Static Analysis (Slither & Mythril)

> Requirement `RQ_SEC_STATIC`: static analysis runs on every MR and the build
> fails on any High/Critical finding. Medium findings are reviewed and either
> fixed or recorded in `slither.db.json` with a rationale. Mythril runs on a
> scheduled (weekly) pipeline.

## Overview

Two complementary tools run in CI:

| Tool        | When                              | Gate                                  | CI job          |
| ----------- | --------------------------------- | ------------------------------------- | --------------- |
| **Slither** | every merge request (`test` stage)| **fails** on High; Medium soft-fails  | `lint-slither`  |
| **Mythril** | weekly schedule + manual web run  | scheduled run **fails** on High       | `sec-mythril`   |

Slither's impact taxonomy is `High > Medium > Low > Informational` — there is no
separate "Critical" tier, so **"High/Critical" maps to Slither `High`**. The same
applies to Mythril severities (`High > Medium > Low`).

## Slither (per-MR gate)

The `lint-slither` job runs:

```sh
slither . --filter-paths 'dependencies/|test/|script/' --json slither-output.json --fail-none --skip-assembly
```

Slither auto-loads `slither.config.json` (detector excludes) and `slither.db.json`
(triage suppressions) from the repo root. The highest *remaining* impact is read by
[`tools/ci/slither-json-highest-impact`](../../tools/ci/slither-json-highest-impact),
which drives the gate:

- **High** → exit `10` → job **fails** (hard gate).
- **Medium** → exit `250` → `allow_failure` soft-fail (warning); review and either
  fix it or record it in `slither.db.json` (below).
- **Low / Informational / none** → exit `0` → pass.

Findings are also published to the GitLab MR code-quality widget via
[`tools/ci/slither-json-to-gitlab`](../../tools/ci/slither-json-to-gitlab).

### Triaging Medium findings — `slither.db.json`

`slither.db.json` is Slither's triage database: it is a JSON **array** of finding
objects, and Slither suppresses any finding whose `id` (a content hash) appears in
it. Slither only reads the `id` field, so **extra fields are ignored** — we use that
to attach the required rationale to every suppression.

This file is **hand-maintained**, not generated output. The triage state must stay
honest: every entry suppresses a real, reviewed finding and carries a rationale.
It currently holds `[]` (no accepted suppressions); the previous `locked-ether`
entry was removed during review because that detector is already disabled in
`slither.config.json` and the finding lived in a filtered `dependencies/` path, so
it suppressed nothing and had no rationale.

**To accept (suppress) a Medium finding:**

1. Run Slither and find the finding object in `slither-output.json` (it has an `id`).
2. Append it to the `slither.db.json` array, keeping at least its `id`, and add a
   `rationale` (and, where one exists, an `issue` link). Every suppression **must**
   carry a non-empty `rationale` or `issue`.
3. Commit the change in the same MR that introduced/reviewed the finding.

Example entry:

```json
[
  {
    "id": "<slither finding hash from slither-output.json>",
    "check": "reentrancy-no-eth",
    "impact": "Medium",
    "rationale": "Guarded by nonReentrant on the public entrypoint; the flagged path is internal-only.",
    "issue": "https://gitlab.nesad.fit.vutbr.cz/.../-/issues/123",
    "reviewed_by": "<name>",
    "reviewed_at": "2026-06-09"
  }
]
```

High/Critical findings are **never** suppressed via the triage DB — they must be
fixed.

## Mythril (weekly scheduled deep scan)

Mythril performs symbolic execution and is far slower than Slither, so it runs on a
schedule rather than per-MR (`RQ_SEC_STATIC` explicitly allows this). The
`sec-mythril` job runs [`tools/ci/mythril-analyze.sh`](../../tools/ci/mythril-analyze.sh),
which:

- Builds the solc `--solc-json` settings from `remappings.txt` and the
  `[profile.default]` flags in `foundry.toml` (optimizer, `evmVersion`, `viaIR`).
- Analyzes the curated core deployable contracts in **source mode** (`myth analyze
  <file> --solc-json … --solv 0.8.34 -o json`), each with a per-contract execution
  timeout, tolerating per-contract compile/timeout failures (recorded as coverage
  gaps, not gate failures).
- Aggregates everything into `mythril-report.json` (CI artifact, kept 30 days) and
  gates on severity via
  [`tools/ci/mythril-json-highest-severity`](../../tools/ci/mythril-json-highest-severity):
  **High** → exit `10` (fail); Medium/Low/none → exit `0` (report only).

On the weekly **scheduled** pipeline the job gates (a High finding fails it). A
**manual** run from a *web* pipeline is advisory (`allow_failure: true`).

Tunable via CI variables: `MYTHRIL_EXEC_TIMEOUT` (seconds/contract, default `120`),
`MYTHRIL_SOLC_VERSION` (default `0.8.34`), `MYTHRIL_SOLC_BINARY` (exact compiler
path override), `MYTHRIL_SUPPRESSIONS` (default `./mythril.db.json`), and
`MYTHRIL_TARGETS` (override the file list).

### Run Mythril locally

```sh
python3 -m venv .venv && . .venv/bin/activate
pip install "setuptools<81" mythril   # setuptools<81 keeps pkg_resources available
solc --version             # must report 0.8.34
npm run mythril            # full scan over the default target set
npm run mythril-fast       # same, with a short per-contract timeout (MYTHRIL_EXEC_TIMEOUT=30)
# Analyze a single contract quickly:
MYTHRIL_TARGETS="src/token/fungible/DEUSSToken.sol" MYTHRIL_EXEC_TIMEOUT=60 npm run mythril
```

The wrapper sets a temporary `MYTHRIL_DIR` and `SOLCX_BINARY_PATH` so Mythril
does not reuse stale `~/.mythril` or `~/.solcx` compiler state. If the active
`solc` is not `0.8.34`, select it with `solc-select use 0.8.34` or pass
`MYTHRIL_SOLC_BINARY=/path/to/solc-0.8.34`. Known Mythril false positives are
tracked in [`mythril.db.json`](../../mythril.db.json) with a rationale and are
removed from the gated issue set after report aggregation.

## Handoff: configure the weekly schedule

A `rules: schedule` job does **not** create the schedule itself. To run Mythril
weekly, add a pipeline schedule in GitLab once:

1. **Project → Build → Pipeline schedules → New schedule.**
2. Cron e.g. `0 3 * * 1` (Mondays 03:00), target branch `master`.
3. Save. The scheduled pipeline runs `build` then `sec-mythril`; a High finding
   fails it and the team reviews `mythril-report.json`.
