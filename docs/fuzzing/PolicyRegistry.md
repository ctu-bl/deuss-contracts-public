# PolicyRegistry Fuzz Coverage

Vertical entrypoint: [`test/fuzzing/FuzzPolicyRegistryIntegrity.sol`](../../test/fuzzing/FuzzPolicyRegistryIntegrity.sol)
Invariants: [`test/fuzzing/properties/Properties_PR.sol`](../../test/fuzzing/properties/Properties_PR.sol)
Descriptions: [`test/fuzzing/properties/PropertiesDescriptions.sol`](../../test/fuzzing/properties/PropertiesDescriptions.sol)

## Scope

Direct exercise of [`PolicyRegistry`](../registry/PolicyRegistry.md) wallet-scoped policy configuration, delegated policy-admin permissioning, role bitmap updates, operation-module lookup, module allowlist behavior, `CompanyWallet` admin surfaces, `CompanyWallet.execute` enforcement, and manual `CompanyWallet.advancePolicyEpoch` invalidation.

The harness deploys a real `PolicyRegistry`, three real `CompanyWallet` beacon proxies (two for the role/module surface and one dedicated `policyEpochWallet` for the policy-version invariants), a fuzz target contract, and four policy modules:

- `policyAllowModule` returns `true`.
- `policyDenyModule` returns `false`.
- `policyRevertingModule` reverts from `canExecute`.
- `policyInvalidReturnModule` returns an invalid one-byte payload.

Two wallets are used for the role/module surface so every wallet-scoped mutation also checks that the sibling wallet remains unchanged. A third dedicated wallet, `policyEpochWallet`, is reserved for the policy-version (ownership-epoch) invariants: its ownership is rotated so the epoch can be advanced repeatedly without disturbing the epoch-scoped state of the other two wallets.

## Handlers

| Entrypoint | Caller model | Target | Purpose |
|---|---|---|---|
| `fuzz_grantWalletPolicyAdmin` | wallet owner / admin / user / outsider | `policyRegistry.grantWalletPolicyAdmin` | Owner-only admin grant path plus unauthorized and duplicate-grant boundaries |
| `fuzz_revokeWalletPolicyAdmin` | wallet owner / admin / user / outsider | `policyRegistry.revokeWalletPolicyAdmin` | Owner-only admin revoke path plus unauthorized and not-granted boundaries |
| `fuzz_advancePolicyEpoch` | wallet owner / seeded admin / outsider | `CompanyWallet.advancePolicyEpoch` | Uses a three-seed surface to seed current-epoch delegated policy, advance the epoch, and verify old policy state becomes unreachable; also covers unauthorized and zero-reason failures |
| `fuzz_grantUserRoles` | wallet owner, granted admin, or unauthorized caller | `policyRegistry.grantUserRoles` | OR new user-role bits into a wallet-local bitmap |
| `fuzz_revokeUserRoles` | wallet owner, granted admin, or unauthorized caller | `policyRegistry.revokeUserRoles` | Clear selected user-role bits |
| `fuzz_setUserRoles` | wallet owner, granted admin, or unauthorized caller | `policyRegistry.setUserRoles` | Overwrite exact user-role bitmap, including zero |
| `fuzz_grantOperationRoles` | wallet owner, granted admin, or unauthorized caller | `policyRegistry.grantOperationRoles` | OR new operation-role bits into a wallet-local operation bitmap |
| `fuzz_revokeOperationRoles` | wallet owner, granted admin, or unauthorized caller | `policyRegistry.revokeOperationRoles` | Clear selected operation-role bits |
| `fuzz_setOperationRoles` | wallet owner, granted admin, or unauthorized caller | `policyRegistry.setOperationRoles` | Overwrite exact operation-role bitmap, including zero |
| `fuzz_setOperationModule` | wallet owner, granted admin, or unauthorized caller | `policyRegistry.setOperationModule` | Configure or clear the optional operation policy module |
| `fuzz_grantUserRolesBatch` | wallet owner, granted admin, or unauthorized caller | `policyRegistry.grantUserRoles(address,address[],uint256[])` | Batch variant: single-element array exercises the overload's loop logic with the same invariants as the scalar form |
| `fuzz_revokeUserRolesBatch` | wallet owner, granted admin, or unauthorized caller | `policyRegistry.revokeUserRoles(address,address[],uint256[])` | Batch variant for revoke |
| `fuzz_setUserRolesBatch` | wallet owner, granted admin, or unauthorized caller | `policyRegistry.setUserRoles(address,address[],uint256[])` | Batch variant for set |
| `fuzz_grantOperationRolesBatch` | wallet owner, granted admin, or unauthorized caller | `policyRegistry.grantOperationRoles(address,OperationRoles[])` | Batch variant for operation-role grant |
| `fuzz_revokeOperationRolesBatch` | wallet owner, granted admin, or unauthorized caller | `policyRegistry.revokeOperationRoles(address,OperationRoles[])` | Batch variant for operation-role revoke |
| `fuzz_setOperationRolesBatch` | wallet owner, granted admin, or unauthorized caller | `policyRegistry.setOperationRoles(address,OperationRoles[])` | Batch variant for operation-role set |
| `fuzz_setOperationModuleBatch` | wallet owner, granted admin, or unauthorized caller | `policyRegistry.setOperationModule(address,OperationModule[])` | Batch variant for operation module configuration |
| `fuzz_setPolicyModuleAllowed` | registry owner (`address(this)`) | `policyRegistry.setPolicyModuleAllowed` | Toggle global allowlist status for fuzz policy modules |
| `fuzz_setRoleLabel` | registry owner (`address(this)`) | `policyRegistry.setRoleLabel` | Store compact role metadata |
| `fuzz_checkPolicyLookup` | view-only model | `policyRegistry.canExecute` / `checkOperationModule` / `computeOperationKey` | Compare lookup results against the harness model, including structurally invalid requests |
| `fuzz_checkPolicyLookupWithAllowModule` | view-only model seeded through wallet owner | `policyRegistry.canExecute` / `checkOperationModule` | Seed matching user roles, operation roles, and an allowlisted allow-module so the module-authorized success branch is reachable |
| `fuzz_companyWalletAdminSurface` | wallet owner / outsider | `CompanyWallet.receive`, `setPolicyRegistry`, `renounceOwnership` | Exercise receive, idempotent policy registry setter, and disabled ownership renounce |
| `fuzz_executePolicyCall` | wallet owner / admin / user / outsider | `CompanyWallet.execute` | Verify owner bypass plus `PolicyRegistry.canExecute` enforcement against real wallet execution |
| `fuzz_advancePolicyVersionResetsState` | `policyEpochWallet` owner (rotated) | `CompanyWallet.transferOwnership` | Seed wallet-scoped policy at the current epoch, then advance the ownership epoch and verify the policy version increments monotonically and prior-epoch policy is reset |

## Invariants

### Wallet policy admins - group 10

| ID | Condition | Checked |
|---|---|---|
| PR-10 | `grantWalletPolicyAdmin` marks the selected admin as granted for the selected wallet | on success |
| PR-11 | `revokeWalletPolicyAdmin` clears the selected admin for the selected wallet | on success |
| PR-12 | Admin grant/revoke does not mutate the sibling wallet's admin flag | on success |
| PR-13 | Admin grant/revoke reverts only for the expected permission or state reason | on revert |

### Policy epoch - group 70

| ID | Condition | Checked |
|---|---|---|
| PR-70 | `advancePolicyEpoch` increments the selected wallet epoch and preserves the wallet owner | on success |
| PR-71 | Successful epoch advance makes selected delegated admin, user role, operation role, and module state unreachable in the new epoch | on success |
| PR-72 | `advancePolicyEpoch` reverts only for unauthorized caller or zero reason | on revert |
| PR-73 | Failed epoch advance preserves the selected wallet epoch and seeded delegated policy state | on revert |
| PR-74 | Epoch advancement is scoped to the selected wallet; sibling wallet epoch, owner, admin, role, module, and execution state are unchanged | always |
| PR-75 | The snapshotted pre-state contains reachable delegated policy state before attempting the epoch advance | before action |

### User roles - group 20

| ID | Condition | Checked |
|---|---|---|
| PR-20 | `grantUserRoles` stores `beforeRoles | roles` | on success |
| PR-21 | `revokeUserRoles` stores `beforeRoles & ~roles` | on success |
| PR-22 | `setUserRoles` stores the exact requested bitmap | on success |
| PR-23 | User role mutations do not affect the sibling wallet | on success |
| PR-24 | User role mutations revert only for unauthorized caller, already-granted bits, or missing bits as applicable | on revert |

### Operation roles - group 30

| ID | Condition | Checked |
|---|---|---|
| PR-30 | `grantOperationRoles` stores `beforeRoles | roles` | on success |
| PR-31 | `revokeOperationRoles` stores `beforeRoles & ~roles` | on success |
| PR-32 | `setOperationRoles` stores the exact requested bitmap | on success |
| PR-33 | Operation role mutations do not affect the sibling wallet | on success |
| PR-34 | Operation role mutations revert only for unauthorized caller, already-granted bits, or missing bits as applicable | on revert |

### Operation modules and metadata - groups 40 and 50

| ID | Condition | Checked |
|---|---|---|
| PR-40 | `setOperationModule` stores the selected module, or zero when clearing | on success |
| PR-41 | Operation module mutations do not affect the sibling wallet | on success |
| PR-42 | Module updates revert only for unauthorized callers or non-allowlisted modules | on revert |
| PR-50 | `setPolicyModuleAllowed` stores the exact allowlist status | on success |
| PR-51 | `setRoleLabel` stores the exact role label | on success |
| PR-52 | `setPolicyModuleAllowed` does not unexpectedly revert when called by the owner | on revert |
| PR-53 | `setRoleLabel` does not unexpectedly revert when called by the owner | on revert |

### Lookup and enforcement - group 60

| ID | Condition | Checked |
|---|---|---|
| PR-60 | `canExecute` equals the harness model: structurally valid request, non-zero user roles, intersecting operation roles, and optional module authorization | on lookup |
| PR-61 | `checkOperationModule` diagnostics match configured module, allowlist state, staticcall success, and module authorization | on lookup |
| PR-62 | `CompanyWallet.execute` succeeds only for wallet owner bypass or `PolicyRegistry.canExecute == true`; rejected calls do not mutate the target | on execute |
| PR-63 | `computeOperationKey(target, selector)` equals `keccak256(abi.encode(target, selector))` | on lookup |
| PR-64 | CompanyWallet directed admin and view calls do not unexpectedly revert | on receive, policy-registry setter, ERC165 views |
| PR-65 | Disabled `renounceOwnership` reverts with the expected selector | on renounce attempt |

### Policy version (ownership epoch) - group 70

| ID | Condition | Checked |
|---|---|---|
| PR-70 | Each wallet ownership transfer advances the policy version (ownership epoch) by exactly one and never decreases it | on success |
| PR-71 | Advancing the policy version resets wallet-scoped policy (admin, user roles, operation roles, and operation module) for the new epoch; seeded state is verified present at the prior epoch first | on success |
| PR-72 | Advancing the policy version (`transferOwnership`) does not unexpectedly revert | on revert |
| PR-76 | Policy allow-module seed call succeeds | before allow-module lookup |
| PR-77 | Policy owner seed calls succeed | before policy-epoch reset |

Summary of the clamping and state-selection logic applied before each handler issues a protocol call. Full implementation in [`helper/preconditions/PreconditionsPolicyRegistry.sol`](../../test/fuzzing/helper/preconditions/PreconditionsPolicyRegistry.sol).

| Handler | Clamp rules |
|---|---|
| Admin grant/revoke | Wallet selected from the two policy wallets. Admin selected from `POLICY_ADMINS`. Caller selected from wallet owner, policy admins, regular users, or `POLICY_OUTSIDER`. |
| `advancePolicyEpoch` | Wallet selected from the two policy wallets. `pathSeed` selects owner success, owner zero-reason failure, seeded-admin unauthorized failure, or outsider unauthorized failure. `stateSeed` derives delegated admin, user, operation, roles, and non-zero reason material. The precondition builder seeds delegated admin, user-role, operation-role, and allow-module state for the current epoch, snapshots selected and sibling wallet state, then the handler calls the wallet. |
| User role handlers (scalar and batch) | User selected from tracked users. Role bitmap clamped to `[1, 255]` for grant/revoke and `[0, 255]` for set. Authorization is recorded before the call so postconditions distinguish expected success from expected `PolicyRegistry__Unauthorized`. Batch variants use single-element arrays. |
| Operation role handlers (scalar and batch) | Operation selected from `FuzzPolicyTarget.setFlag(bool)` or `FuzzPolicyTarget.setNumber(uint256)`. Role bitmap clamping matches user roles. Batch variants use single-element arrays. |
| `setOperationModule` (scalar and batch) | Module selected from zero address, allow, deny, reverting, or invalid-return module. The handler records whether the module is currently globally allowlisted. Batch variant uses a single-element array. |
| `setPolicyModuleAllowed` | Module selected from the four non-zero fuzz policy modules. |
| `setRoleLabel` | Role id clamped to `[0, 255]`; label is derived directly from the seed. |
| `checkPolicyLookup` | Selects either a structurally valid request or one invalid field: zero wallet, zero caller, zero target, or calldata shorter than four bytes. |
| `checkPolicyLookupWithAllowModule` | Uses a valid wallet/user/operation tuple, re-allowlists `policyAllowModule` if needed, seeds user roles, operation roles, and the operation module as the wallet owner, then expects the module-authorized lookup path to be executable. |
| `companyWalletAdminSurface` | Selects one policy wallet, calls empty calldata from an outsider to cover `receive`, calls `setPolicyRegistry` as the owner with the existing registry address, and asserts `renounceOwnership` reverts with the disabled-renounce selector. |
| `executePolicyCall` | Uses a valid target operation and computes expected authorization from wallet owner bypass or the same role/module model used for `canExecute`. |
| `advancePolicyVersionResetsState` | Operates on the dedicated `policyEpochWallet`. Reads the current owner and rotates ownership to the other epoch-wallet owner (never a self-transfer). User and admin are selected from the tracked pools, the operation from `FuzzPolicyTarget`, the module is the allowlisted allow-module, and roles are forced non-zero so the seeded state is guaranteed present before the version advance. |

All public fuzz entrypoints delegate to handlers through `FuzzIntegrityBase._testSelf`. Direct `handler_*` calls remain blocked in `echidna-config.yaml`, and Medusa allowlists only `fuzz_*` entrypoints.
