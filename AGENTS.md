# Repository Guidelines

## Project Structure
- `src/`: Solidity contracts grouped by domain: `base/`, `deployer/` (`base`, `governance`, `marketplace`, `registries`, `token`), `governance/`, `marketplace/` (`filters/`, `interfaces/`, `lens/`), `registry/` (`interfaces/`), `token/{base,fungible}`, `wallet/`, `utils/`, and `libs/`. EBSI contracts are consumed through remapped dependencies.
- `test/`: Foundry suites plus shared setup in `fixtures/`, mocks in `mocks/`, shared constants in `Constants.t.sol`, deployment/bootstrap integration tests in `deploy/integration/`, deployer coverage in `deployer/`, governance tests in `governance/`, fuzz harnesses in `fuzzing/` with fuzz-only mocks in `fuzzing/mocks/`, and contract-domain suites in `marketplace/`, `registry/`, `token/`, `wallet/`, and `utils/`. Some domains already use `unit/` and `integration/` splits; keep following the existing local pattern in the area you touch. The composite fuzz harness currently covers Marketplace, EscrowManager, EntityRegistry, DEUSSToken, AssetManager, EscrowManager authorization, PolicyRegistry, and BondRegistry; keep `test/fuzzing/README.md`, `test/fuzzing/INVARIANT_VALIDATION.md`, and `docs/fuzzing/` aligned with that surface.
- `script/`: staged deployment and ops scripts. Main entrypoints are `deploy/DeployProtocol.s.sol`, `bootstrap/BootstrapProtocol.s.sol`, `DeployEBSI.s.sol`, and `SetupEBSIInfrastructure.s.sol`; shared helpers live in `lib/`; demo/test-data seeders live in `test_data/`; ad hoc local/event operations live in `ops/`; token recovery ops live in `unpause/` and should read current deployment manifest keys from `DeploymentArtifacts`; CI/report converters live under `tools/ci/`, `tools/export/`, and `tools/local/`.
- `docs/`: hand-written repo docs in `deployment.md` and `roles.md`, plus contract/domain docs under `docs/deployer/`, `docs/fuzzing/`, `docs/governance/`, `docs/marketplace/`, `docs/registry/`, `docs/security/`, `docs/token/`, `docs/utils/`, and `docs/wallet/`. Images used by docs live in `docs/images/`.
- Tooling and infra: `.devcontainer/`, `dockerfiles/`, `echidna-config.yaml`, `echidna-interest-lifecycle.yaml`, `medusa.json`, `medusa-interest-lifecycle.json`, `slither.config.json`, `tools/ci/generate_selector_docs.py`, `tools/ci/mythril-analyze.sh`, and `tools/export/export-abis.sh`.
- Static-analysis triage and policy: `slither.db.json` is a hand-maintained Slither triage database and `mythril.db.json` is a hand-maintained Mythril triage database (suppressions, each with a rationale), not generated output; the gate policy for Slither and the weekly Mythril scan is documented in `docs/security/static-analysis.md`.
- `dependencies/`: Soldeer-managed vendored packages and remapped libraries. Do not edit.
- Generated or derived outputs: `out/`, `broadcast/`, `cache/`, `deployments/`, `coverage/`, `coverage.json`, `coverage.xml`, `lcov.info`, `crytic-export/`, `echidna-corpus/`, `echidna-interest-lifecycle-directed-corpus/`, `medusa-corpus/`, `medusa-interest-lifecycle-directed-corpus/`, `public/`, `signatures/`, `.tmp/`, `slither-output.json`, and `mythril-report.json`. Do not hand-edit generated files.
- If the structure changes, update this file.

## Commands
- Ensure Foundry is on PATH if needed: `export PATH="$HOME/.foundry/bin:$PATH"`.
- Use Foundry `v1.7.0`; verify with `forge --version` before running build, lint, coverage, or fuzzing commands.
- Install Solidity deps: `forge soldeer install`
- Install JS tooling: `npm install`
- Build: `forge build` (must complete without warnings)
- Test: `forge test` (add `-vvv` for traces)
- Coverage: `npm run coverage` (uses `forge coverage --report summary --report lcov`)
- Lint: `npm run lint-all` or `npm run lint-src`
- Static analysis: `npm run slither-debug` (Slither); Mythril deep scan via `npm run mythril` (or `npm run mythril-fast` for a quick pass; needs `pip install "setuptools<81" mythril`)
- Fuzzing smoke checks: `npm run echidna-fast`, `npm run echidna-interest-lifecycle-fast`, `npm run medusa-fast`, and `npm run medusa-interest-lifecycle-fast`
- Full fuzzing campaigns: `npm run echidna`, `npm run echidna-interest-lifecycle`, `npm run medusa`, and `npm run medusa-interest-lifecycle`
- Local staged deployment flow: run `anvil`, then `make setup` or `make setup_test_data`
- Full local deployment including EBSI infrastructure: `make setup_full` or `make setup_full_test_data`
- Existing-EBSI deployment flow: `make setup_ebsi_existing` or `make setup_ebsi_existing_test_data`
- Verify from broadcast artifacts: `make verify_contracts`
- Local event/log export flow: `npm run events`, `npm run gen-transfer`, and `npm run events:stop-anvil`; see `tools/log-export.md`
- Deployment and bootstrap command behavior is documented in `docs/deployment.md`; update it when Makefile targets, manifest shape, environment variables, or script entrypoints change.

## Style
- Use 4-space indentation and keep project contracts on Solidity `0.8.34` unless an existing file intentionally differs.
- Follow `.solhint.json`, `.solhint.t.json`, and `.solhint.s.json`.
- Prefer `/** */` NatSpec over `///`, and keep docs current when behavior changes.
- Order namespaced state structs consistently: fixed-size dependencies/config first, counters/allocators next, primary entity mappings next, authorization/registry mappings next, and derived indexes, aggregates, caches, and accounting helpers last.
- Inside Solidity structs, document fields with `///` NatSpec. Use block NatSpec for contracts, functions, events, constants, and top-level struct descriptions.
- Interfaces start with `I`; non-constant state variables should use leading `_` and default to `internal` unless visibility needs to be broader.
- Reuse shared errors from `src/libs/Errors.sol` instead of introducing ad hoc revert strings.
- Run `forge fmt` on modified Solidity files.

## Docs
- Keep contract docs in `docs/**` aligned with the existing repo structure instead of writing ad hoc summaries.
- For contract docs, follow the established section order when relevant: `Overview`, `Prerequisites`, `Contract Architecture`, domain-specific sections such as `Data Model` / `Authorization Model` / `Deployment Flow`, then `Core Functions`, and finally trust or security notes when useful.
- Document behavior from the current code, not from stale intent or earlier iterations.
- For core function sections, include concise prerequisites, key parameters/returns, emitted events, main errors, and important notes when they materially affect integration or operations.
- Add Mermaid `Sequence Diagram` blocks for core state-changing or integration-heavy workflows, following the style already used in existing docs under `docs/`.
- Preserve local terminology and naming used by existing docs and contracts.
- Update cross-links when files or paths move.
- Use `docs/deployment.md` for deployment/bootstrap/operator flow details and `docs/roles.md` for role surfaces and role-change guidance.
- Use `docs/security/operational-model.md` for production governance, ownership, role-assignment, launch-gate, monitoring, and incident-response guidance.
- Use `docs/security/threat-model.md` for the current-state trust-boundary and actor-risk baseline, and keep it aligned with operational controls when threat assumptions or privileged surfaces change.
- Use `docs/security/wallet-operational-modes.md` for `CompanyWallet` ownership patterns such as Direct-Owned Company Wallet and Root-Controlled Subwallet Mode.
- Use `docs/security/static-analysis.md` for Slither/Mythril policy and `docs/security/sdlc.md` for security-development-lifecycle process guidance.
- Use `tools/log-export.md` for local Anvil event export and transfer-event generation workflows.
- Keep domain docs under the matching folder: deployer docs in `docs/deployer/`, governance in `docs/governance/`, marketplace in `docs/marketplace/`, registry in `docs/registry/`, token in `docs/token/`, wallet in `docs/wallet/`, and utilities in `docs/utils/`.
- For fuzzing documentation, keep the harness overview in `test/fuzzing/README.md`, invariant proof status in `test/fuzzing/INVARIANT_VALIDATION.md`, and per-vertical coverage notes in `docs/fuzzing/`.

## Testing
- Add or update Foundry tests alongside each contract change under `test/**` using `*.t.sol`.
- Keep test placement consistent with the current layout: deployment/bootstrap flows in `test/deploy/`, deployer coverage in `test/deployer/`, fuzz harness changes in `test/fuzzing/`, governance changes in `test/governance/`, and contract-domain tests in the matching domain folder.
- Where a domain already uses `unit/` and `integration/` folders, preserve that split. Where the current folder keeps top-level `*.t.sol` files, continue that pattern unless there is a clear reason to reorganize the whole area.
- Name tests after the exercised contract function using `test_<function>_success_<case>` and `test_<function>_reverts_<case>`. For non-reverting negative-result paths, use `test_<function>_success_<negativeCase>` instead of a generic umbrella test name.
- Group tests with section headers by exercised contract function so the test file structure mirrors the contract surface.
- Give each success path, revert path, and meaningful branch its own dedicated test. Shared setup helpers are fine, but do not rely on one umbrella test to cover multiple branches implicitly.
- Cover modified functions across happy paths, failure paths, permission checks, deployment/bootstrap wiring, and proxy flows when relevant.
- Before touching fuzz harness code under `test/fuzzing/`, read `test/fuzzing/README.md` and follow its Layering Rules, including invariant-label granularity, as the source of truth. Do not restate or reinterpret those rules in handlers or reviews; update the README first when the harness architecture changes.
- If you touch fuzz harness code or invariant IDs, keep `test/fuzzing/README.md`, `test/fuzzing/INVARIANT_VALIDATION.md`, `docs/fuzzing/`, `echidna-config.yaml`, and `medusa.json` aligned with the harness behavior.
- When adding or renaming invariant IDs, update `test/fuzzing/INVARIANT_VALIDATION.md` and the relevant `docs/fuzzing/*.md` entry in the same change.

## Completion Gates
- Relevant modified contracts should have full branch and permission-path coverage (reached 100%).
- Run `forge build`, `forge test`, `npm run lint-all`, and `npm run slither-debug` before finishing. All checks must pass. `forge build` must produce no warnings, no linter warnings are acceptable, and for Slither, fix critical, high, and medium findings introduced by the change.
- Run the relevant deployment flow against Anvil when deployment, bootstrap, role wiring, manifests, or seeded demo-data behavior changes. Use `make setup_full_test_data` for the full local stack.
- Update relevant docs in `docs/` when workflows, roles, deployment behavior, or contract interfaces change.
- For deployment or role changes, specifically check `docs/deployment.md`, `docs/roles.md`, and the affected contract/domain doc before finishing.
- Do not push any commits to remote.

### Running local deployment targets against Anvil
Use this workflow when another user or agent may already be using the default Anvil port.

1. Check whether the intended port is already taken.
```bash
ss -ltnp 2>/dev/null | rg ':8545\\b|:8546\\b|:9545\\b' || true
```

2. Pick a free port.
- If `127.0.0.1:8545` is free, use `8545`.
- If `8545` is already occupied, start a separate Anvil on another free port such as `8546`.

3. Start Anvil on the chosen port.
Default port:
```bash
anvil --host 127.0.0.1 --chain-id 31337 --port 8545 --silent --disable-code-size-limit
```
Alternate port:
```bash
anvil --host 127.0.0.1 --chain-id 31337 --port 8546 --silent --disable-code-size-limit
```

4. Verify the RPC is reachable before running setup.
Default port:
```bash
cast chain-id --rpc-url http://127.0.0.1:8545
```
Alternate port:
```bash
cast chain-id --rpc-url http://127.0.0.1:8546
```
Expected result:
```text
31337
```

5. Run the target against the same port.
Default port:
```bash
make setup_full_test_data
```
Alternate port:
```bash
make setup_full_test_data ANVIL_RPC_URL=http://127.0.0.1:8546
```

### Important
- For non-default ports, pass `ANVIL_RPC_URL` as a `make` variable:
```bash
make setup_full_test_data ANVIL_RPC_URL=http://127.0.0.1:8546
```
- Do not rely on this form:
```bash
ANVIL_RPC_URL=http://127.0.0.1:8546 make setup_full_test_data
```
That form may still use the default `8545` value from the `Makefile`.

## Security
- Copy `.env.example` to `.env` for local setup and never commit secrets.
- Static analysis gates per `docs/security/static-analysis.md`: Slither runs on every MR and **fails the build on High** findings; Medium findings must be fixed or recorded in `slither.db.json` with a rationale. Mythril runs on a weekly **scheduled** pipeline (`sec-mythril`) and must be enabled via a GitLab pipeline schedule (see that doc).
