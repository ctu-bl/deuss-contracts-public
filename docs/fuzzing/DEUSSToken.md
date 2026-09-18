# DEUSSToken Fuzz Coverage

Vertical entrypoint: [`test/fuzzing/FuzzDEUSSTokenIntegrity.sol`](../../test/fuzzing/FuzzDEUSSTokenIntegrity.sol)
Invariants:
- Token-side: [`test/fuzzing/properties/Properties_TKN.sol`](../../test/fuzzing/properties/Properties_TKN.sol)
- Supply/accounting: [`test/fuzzing/properties/Properties_SPLY.sol`](../../test/fuzzing/properties/Properties_SPLY.sol)

Descriptions: [`test/fuzzing/properties/PropertiesDescriptions.sol`](../../test/fuzzing/properties/PropertiesDescriptions.sol)

## Scope

Direct exercise of the issued [`DEUSSToken`](../token/DEUSSToken.md) bond token created during `FuzzSetup`. The vertical targets only the setup `bondTokenId` and uses the tracked `users` pool (`USER1..3`) as token holders, spenders, operators, and receivers so total-supply accounting remains bounded and enumerable.

Covered behavior:
- approvals, including zero revocation and nonzero-to-nonzero allowance overwrite
- BaseToken batch role-grant validation for invalid role bitmaps
- normal transfers, both `batchTransferFrom` overloads, and `transferFrom` through allowance
- operator grant/revoke and `transferFrom` through operator approval
- freeze/unfreeze, batch freeze/unfreeze, forced transfer, and batch forced transfer, including forced release of frozen balance
- owner-driven address protection checks
- protected receiver rejection for ordinary third-party transfers
- BondRegistry-only `burn` and `burnBatch`, including forced release of frozen balance
- contract pause and BondRegistry-driven token-id suspension
- supply, bondNominalValue, face-value, current-block checkpoint accounting, and future-block checkpoint rejection

## Handlers

| Entrypoint | Caller | Target | Purpose |
|---|---|---|---|
| `fuzz_approve` | `currentActor` | `token.approve` | Set or reset allowance for the issued token |
| `fuzz_approveOverwriteExisting` | `currentActor` | `token.approve` | Assert nonzero-to-nonzero approval overwrites the allowance |
| `fuzz_grantRolesBatchInvalidRoles` | harness owner | `token.grantRoles(address[],uint256)` | Assert batch role grants reject role bitmaps outside `BaseToken.ALL_ROLES` |
| `fuzz_transfer` | `currentActor` | `token.transfer` | Move free balance between tracked users |
| `fuzz_transferFromAllowance` | allowance spender | `token.transferFrom` | Move balance and spend allowance |
| `fuzz_setOperator` | `currentActor` | `token.setOperator` | Grant or revoke operator approval |
| `fuzz_setOperatorUnregistered` | `currentActor` | `token.setOperator` | Assert unregistered operator enablement is rejected |
| `fuzz_transferFromOperator` | approved operator | `token.transferFrom` | Move balance without spending allowance |
| `fuzz_batchTransferFromSingleReceiver` | `currentActor` | `token.batchTransferFrom(address,address,uint256[],uint256[])` | Cover the multi-token-id batch transfer overload for the issued token |
| `fuzz_batchTransferFromMultipleReceivers` | `currentActor` | `token.batchTransferFrom(address,address[],uint256,uint256[])` | Cover the multi-recipient batch transfer overload for the issued token |
| `fuzz_freezePartialTokens` | harness role holder | `token.freezePartialTokens` | Freeze free balance on a tracked user |
| `fuzz_batchFreezePartialTokens` | harness role holder | `token.batchFreezePartialTokens` | Freeze free balance through the batch entrypoint |
| `fuzz_unfreezePartialTokens` | harness role holder | `token.unfreezePartialTokens` | Release frozen balance on a tracked user |
| `fuzz_batchUnfreezePartialTokens` | harness role holder | `token.batchUnfreezePartialTokens` | Release frozen balance through the batch entrypoint |
| `fuzz_forcedTransfer` | harness role holder | `token.forcedTransfer` | Privileged transfer that can release frozen balance |
| `fuzz_batchForcedTransfer` | harness role holder | `token.batchForcedTransfer` | Privileged batch transfer that can release frozen balance |
| `fuzz_forcedTransferToProtectedReceiver` | harness role holder | `token.forcedTransfer` | Assert protected custody cannot be the receiver of a forced transfer |
| `fuzz_batchForcedTransferToProtectedReceiver` | harness role holder | `token.batchForcedTransfer` | Assert protected custody cannot be the receiver of a batch forced transfer |
| `fuzz_burn` | `BondRegistry` prank | `token.burn` | Burn a tracked user's balance through the registry-only token entrypoint |
| `fuzz_burnBatch` | `BondRegistry` prank | `token.burnBatch` | Burn a tracked user's balance through the batch registry-only token entrypoint |
| `fuzz_protectAddress` | harness owner | `token.protectAddress` / `token.isAddressProtected` | Mark a non-token-flow fuzz wallet as protected custody |
| `fuzz_protectedReceiverTransfer` | selected tracked user | `token.transfer` | Assert ordinary transfers into a protected receiver are rejected |
| `fuzz_checkpointFutureReverts` | harness | `token.balanceOfAt` | Assert future-block checkpoint queries revert |
| `fuzz_setContractPause` | harness owner | `token.pause` / `token.unpause` | Toggle contract-level pause |
| `fuzz_setBondSuspended` | harness BondRegistry role holder | `bondRegistry.suspendBond` / `unsuspendBond` | Toggle token-id pause through the registry |
| `fuzz_contractPauseBlocksAction` | `currentActor` | `token.approve` | Assert contract pause blocks token actions |
| `fuzz_tokenIdPauseBlocksTransfer` | selected tracked user | `token.transfer` | Assert token-id pause blocks normal transfers |

`fuzz_setBondSuspended` deliberately routes through `BondRegistry` instead of calling `pauseTokenId` directly, so `BondStatus.Suspended` and `token.isTokenPaused(bondTokenId)` stay aligned.

## Invariants

### Approvals and operators

| ID | Condition | Checked |
|---|---|---|
| TKN-10 | `approve` writes the expected allowance | on success |
| TKN-11 | Approval/operator actions do not mutate owner or spender balances | on success |
| TKN-12 | Nonzero-to-nonzero approval overwrites the allowance | on success |
| TKN-13 | Batch `grantRoles` rejects invalid BaseToken role bits with `InvalidRoles` and leaves roles unchanged | expected revert |
| TKN-30 | `setOperator` stores the requested operator approval | on success |
| TKN-31 | Enabling an unregistered operator reverts with `Token__OperatorNotEnabled` | expected revert |

### Transfers and freezes

| ID | Condition | Checked |
|---|---|---|
| TKN-20 | Transfer-like actions decrease sender balance and increase receiver balance by `amount` | on success |
| TKN-21 | Allowance transfer spends exactly `amount` of allowance | on success |
| TKN-22 | Operator transfer leaves allowance unchanged | on success |
| TKN-40 | Freeze increases frozen balance without changing total balance or supply | on success |
| TKN-41 | Unfreeze decreases frozen balance without changing total balance or supply | on success |
| TKN-50 | Forced transfer moves balance and reduces frozen balance only when free balance is insufficient | on success |
| TKN-51 | Burn decreases holder balance, releases frozen balance when needed, and decreases total supply | on success |
| TKN-52 | Forced transfer into protected custody reverts with `Token__ProtectedReceiverTransferNotAllowed` and leaves source, receiver, and supply unchanged | expected revert |

### Pause and suspension

| ID | Condition | Checked |
|---|---|---|
| TKN-60 | Contract pause state matches the requested state | on success |
| TKN-61 | Bond status and token-id pause match the requested suspension state | on success |
| TKN-62 | Contract pause blocks the selected token action with `PausableUpgradeable.EnforcedPause` | expected revert |
| TKN-63 | Token-id pause blocks normal transfer with `Token__TokenIdIsPaused` | expected revert |

### Cross-cutting token accounting

These run after successful token actions through `onSuccessInvariantsGeneral` or targeted token postconditions.

| ID | Condition |
|---|---|
| TKN-01 | Every tracked frozen balance is bounded by its token balance |
| TKN-70 | Current-block `balanceOfAt`, `frozenBalanceOfAt`, and `availableBalanceOfAt` match current account state for touched actors |
| TKN-71 | Future-block checkpoint queries revert with `Token__BlockInFuture` |
| TKN-80 | `protectAddress` marks the selected account as protected |
| TKN-81 | Ordinary third-party transfers into a protected receiver revert with `Token__ProtectedReceiverTransferNotAllowed` and preserve balances |
| SPLY-01 | Total supply equals the sum of tracked balances |
| SPLY-02 | Total supply never exceeds the initial issued supply |
| SPLY-03 | Bond nominal value remains `BOND_NOMINAL_VALUE` |
| SPLY-04 | `totalSupply * bondNominalValue` equals tracked balance face value |
| SPLY-05 | Current-block `totalSupplyAt` matches current `totalSupply` |

Touched actor balances, frozen balances, checkpoints, total supply, and pause state are snapshotted through the shared marketplace snapshot module because those accounting invariants are also used by offer, deal, and escrow flows. DEUSSToken-specific pair state, namely `allowance(owner, spender, bondTokenId)` and `isOperator(owner, spender)`, is snapshotted in `BeforeAfterDEUSSToken`.

## Preconditions

Summary of the clamping and state-selection logic applied before each handler issues a protocol call. Full implementation in [`helper/preconditions/PreconditionsDEUSSToken.sol`](../../test/fuzzing/helper/preconditions/PreconditionsDEUSSToken.sol).

| Handler | Clamp rules |
|---|---|
| `approve` | Contract must not be paused. Owner is `currentActor`; spender is selected from the tracked `users` pool. Amount is clamped to `[0, initialIssuedSupply]` and overwrites the existing allowance. |
| `approveOverwriteExisting` | Contract must not be paused. Selects a spender from the tracked `users` pool with existing nonzero allowance from `currentActor`; new amount is clamped to `[1, initialIssuedSupply]`. |
| `grantRolesBatchInvalidRoles` | Selects two adjacent tracked users, snapshots their token role bitmaps, and ORs `BaseToken.ALL_ROLES` with one invalid role bit selected from `[3, 255]`. |
| `transfer` | Contract and token ID must not be paused. `currentActor` must have free balance; receiver is a different tracked user; amount is clamped to `[1, freeBalance]`. |
| `transferFromAllowance` | Contract and token ID must not be paused. Selects an owner different from `currentActor` with nonzero allowance, no operator approval to `currentActor`, and free balance. Amount is clamped to the lower of allowance and free balance. |
| `setOperator` | Contract must not be paused. Owner is `currentActor`; operator is a different enabled tracked user; requested boolean passes through. |
| `setOperatorUnregistered` | Contract must not be paused. Operator is fixed to `FUZZ_TOKEN_UNREGISTERED_OPERATOR` and must not be enabled in EntityRegistry. |
| `transferFromOperator` | Contract and token ID must not be paused. Selects an owner that approved `currentActor` as operator and has free balance. |
| `batchTransferFromSingleReceiver` | Same as `transfer`, then wraps the issued `bondTokenId` and amount in singleton arrays for the multi-token-id overload. |
| `batchTransferFromMultipleReceivers` | Same as `transfer`, then wraps the receiver and amount in singleton arrays for the multi-recipient overload. |
| `freezePartialTokens` | Contract must not be paused. Selects a tracked user with free balance; amount is clamped to `[1, freeBalance]`. Token-id suspension is allowed. |
| `batchFreezePartialTokens` | Same as `freezePartialTokens`, then wraps the selected account and amount in singleton arrays for the batch entrypoint. |
| `unfreezePartialTokens` | Contract must not be paused. Selects a tracked user with frozen balance; amount is clamped to `[1, frozenBalance]`. Token-id suspension is allowed. |
| `batchUnfreezePartialTokens` | Same as `unfreezePartialTokens`, then wraps the selected account and amount in singleton arrays for the batch entrypoint. |
| `forcedTransfer` | Contract must not be paused. Selects a tracked user with balance; amount is clamped to `[1, balance]`. Token-id suspension is allowed. |
| `batchForcedTransfer` | Same as `forcedTransfer`, then wraps the source, receiver, and amount in singleton arrays for the batch entrypoint. |
| `forcedTransferToProtectedReceiver` | Selects a tracked user with balance, ensures `EscrowManager` is protected custody and EntityRegistry-enabled, then attempts to force-transfer `[1, balance]` tokens into it. |
| `batchForcedTransferToProtectedReceiver` | Same as `forcedTransferToProtectedReceiver`, then wraps the source, protected receiver, and amount in singleton arrays for the batch entrypoint. |
| `burn` | Ensures the contract is unpaused. Selects an enabled, unprotected tracked user with balance; amount is clamped to a capped range so burn coverage does not starve later token actions. The token call is pranked as `BondRegistry`. |
| `burnBatch` | Same as `burn`, then wraps the source and amount in singleton arrays for the batch entrypoint. |
| `protectAddress` | Selects an unprotected address from `FUZZ_WALLETS`, which is disjoint from the main token-flow `users` pool. |
| `protectedReceiverTransfer` | Ensures `FUZZ_WALLET_7` is enabled and protected, selects a tracked sender with free balance, clamps amount to `[1, freeBalance]`, then attempts a normal transfer into the protected receiver. |
| `checkpointFutureReverts` | Selects a tracked user and queries `balanceOfAt` at `block.number + 1`. |
| `setContractPause` | Requested pause state must differ from current contract pause state. |
| `setBondSuspended` | Suspension requires `BondStatus.Issued` and is allowed while the contract is globally paused; unsuspension requires `BondStatus.Suspended` and the contract must not be paused. |
| `contractPauseBlocksAction` | Ensures contract pause is active, snapshots allowance state, then attempts `approve`. |
| `tokenIdPauseBlocksTransfer` | Ensures token-id pause is active through `BondRegistry.suspendBond`, selects a user with free balance, then attempts `transfer`. |

All clamp failures raise `ClampFail(string)`, which the integrity layer accepts as a legitimate skip rather than a bug.
