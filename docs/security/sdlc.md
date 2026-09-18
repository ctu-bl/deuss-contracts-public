# Secure SDLC: CI/CD Security Gate Matrix

This document lists the security gates enforced by `.gitlab-ci.yml` for merges
into `master`. Each row maps a requirement to the CI job that implements it,
whether it currently blocks the merge, and what condition causes failure.

| # | Gate | CI job | Stage | Blocking | Failure condition |
|---|------|--------|-------|----------|-------------------|
| 1 | `forge test` passes | `test-solidity` | `test` | Yes | Any Foundry test failure or non-zero exit from `forge coverage`. |
| 2 | Coverage on changed Solidity files ≥ 90% | `test-solidity` (step `coverage_changed_files.py`) | `test` | Yes on MR pipelines | The job first runs `tools/ci/test_coverage_changed_files.py`; failures block the job. `tools/ci/coverage_changed_files.py` parses `lcov.info`, lists files under `src/` changed against `origin/$CI_MERGE_REQUEST_TARGET_BRANCH_NAME` (`A...HEAD` merge-base), and exits non-zero if any file has line coverage (LH/LF) below 90%. Files absent from `lcov.info` are treated as 0% and fail the gate unless they are declaration-only sources with no executable members (for example interfaces or error/type libraries); files with `LF=0` are treated as 100% and auto-pass. The gate is skipped on non-MR pipelines (branch, tag, web), where `CI_MERGE_REQUEST_TARGET_BRANCH_NAME` is unset. The Cobertura coverage report is still published for trending. |
| 3 | Slither — no High findings | `lint-slither` | `test` | Yes on High | `slither --fail-high` exits non-zero when any High-impact finding is detected on `src/` (paths `dependencies/`, `test/`, `script/` are filtered out). Medium soft-fails via exit code 250 (`allow_failure`). Slither has no "Critical" severity; High is the strictest level it reports. |
| 4 | Solhint — zero warnings on `src/` | `lint-solhint` | `test` | Yes for `src/` | `npx solhint --max-warnings 0 'src/**/*.sol'` exits non-zero on any warning or error. The `test/` and `script/` runs use their own configs and do not enforce `--max-warnings 0`. |
| 5 | Secret scan (Gitleaks) — no findings | `gitleaks` | `test` | Yes | `gitleaks detect --exit-code 1` returns non-zero when any leak is detected. Findings are redacted in the JSON report artifact. |
| 6 | SBOM generated for deployer container | `build-docker-image` | `export` | No (release-time generation, not an MR gate) | BuildKit generates an SBOM via `--sbom=true` and attaches it to the deployer image manifest as a registry attestation. After push, the SBOM is also exported as the job artifact `sbom.json` via `docker buildx imagetools inspect`. This job runs only on `master` pushes and release tags, so SBOM generation is a release-time control rather than a per-MR gate; failure to attach the SBOM fails the build job. |

## Notes

- Gates 1–5 run in the `test` stage on every merge-request pipeline. Failure of
  any blocking gate prevents the MR pipeline from succeeding and therefore
  blocks the merge.
- Gate 2 (changed-file coverage) is line-based (`LH/LF` per file from
  `lcov.info`), not patch-line-based. It catches new `.sol` files added without
  tests, regressions in modified files, and missing coverage instrumentation.
- Gate 6 (SBOM) is produced by BuildKit at deployer-image build time. Because
  `build-docker-image` runs only on master pushes and release tags, the SBOM is
  a release artifact rather than a merge-blocking control. The SBOM is
  retrievable from the image registry via
  `docker buildx imagetools inspect <image> --format '{{ json .SBOM }}'`, or
  from the GitLab job artifact `sbom.json`.
