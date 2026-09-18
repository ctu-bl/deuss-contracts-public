# PolicyRegistry Policy-Version Fuzz Coverage

Vertical entrypoint: [`test/fuzzing/FuzzPolicyRegistryIntegrity.sol`](../../test/fuzzing/FuzzPolicyRegistryIntegrity.sol) (`fuzz_advancePolicyVersionResetsState`)
Handler: [`test/fuzzing/helper/handlers/HandlerPolicyRegistry.sol`](../../test/fuzzing/helper/handlers/HandlerPolicyRegistry.sol)
Invariants: [`test/fuzzing/properties/Properties_PR.sol`](../../test/fuzzing/properties/Properties_PR.sol) (`PR_70` .. `PR_72`)
Descriptions: [`test/fuzzing/properties/PropertiesDescriptions.sol`](../../test/fuzzing/properties/PropertiesDescriptions.sol)

## Scope

Direct exercise of the `PolicyRegistry` policy-version reset property over a real `PolicyRegistry` and a dedicated real `CompanyWallet` instance, `policyEpochWallet`. `PolicyRegistry` keys wallet-scoped permissions by `(wallet, ownershipEpoch)` and consults the wallet's current epoch when reading user roles, wallet policy admins, operation roles, operation modules, and `canExecute`. `CompanyWallet.ownershipEpoch` increments when ownership changes through `_setOwner`. Together these mean state seeded under epoch N must be unreachable after ownership advances the wallet to epoch N+1.

The handler uses `policyEpochWallet`, not the shared role/module wallets `policyWalletA` and `policyWalletB`. This isolates the policy-version test from the broader PolicyRegistry RBAC handlers, which intentionally mutate `policyWalletA/B` state. The dedicated wallet is initialized with two known owners (`POLICY_EPOCH_WALLET_OWNER_A` and `POLICY_EPOCH_WALLET_OWNER_B`) so ownership can rotate repeatedly without self-transfers or unprankable owners.

The handler seeds wallet-scoped policy at the current epoch as the live wallet owner: user roles, wallet policy-admin status, operation roles, and, when the allow-module is currently allowlisted, an operation module. It snapshots that seeded state, transfers wallet ownership to the alternate epoch owner, then checks that the epoch advanced by exactly one and the seeded policy state is no longer reachable in the new epoch.

Campaign evidence and proof status are tracked in [`test/fuzzing/INVARIANT_VALIDATION.md`](../../test/fuzzing/INVARIANT_VALIDATION.md). That ledger currently records the handler as implemented and reached, with a clean rerun still pending after the harness false-positive fix.

## Handlers

| Entrypoint | Caller | Target | Purpose |
|---|---|---|---|
| `fuzz_advancePolicyVersionResetsState` | `policyEpochWallet` live current owner | `PolicyRegistry` grants / module setup, then `CompanyWallet.transferOwnership(address)` | Seed current-epoch wallet-scoped policy, advance the ownership epoch, and verify monotonicity plus policy reset |

The seeded user and admin are selected from the tracked policy pools, the operation comes from `FuzzPolicyTarget`, and roles are normalized to a non-zero bitmap. The operation module dimension is only seeded when `policyAllowModule` is currently allowlisted; if another fuzz step has disabled that module, the handler skips only the module dimension while still proving reset for admin, user-role, and operation-role state.

## Invariants

### `advancePolicyVersionResetsState` - policy-version monotonicity and reset

Checked in `advancePolicyVersionPostconditions` for `fuzz_advancePolicyVersionResetsState`.

| ID | Condition | Checked |
|---|---|---|
| PR-70 | Ownership transfer advances the policy version / ownership epoch by exactly one and never decreases it | on success |
| PR-71 | Seeded wallet policy-admin, user-role, operation-role, and seeded module state existed before the transfer and is reset in the new epoch | on success |
| PR-72 | The directed owner-authorized ownership transfer must not unexpectedly revert | always |
