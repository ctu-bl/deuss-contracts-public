# BondRegistry Fuzz Coverage

Vertical entrypoint: [`test/fuzzing/FuzzBondRegistryIntegrity.sol`](../../test/fuzzing/FuzzBondRegistryIntegrity.sol)
Invariants: [`test/fuzzing/properties/Properties_BOND.sol`](../../test/fuzzing/properties/Properties_BOND.sol)
Descriptions: [`test/fuzzing/properties/PropertiesDescriptions.sol`](../../test/fuzzing/properties/PropertiesDescriptions.sol)

## Scope

End-to-end exercise of the [`BondRegistry`](../registry/BondRegistry.md) lifecycle and issuance accounting: publishing successor versions, amending published bonds, issuing tranches, closing issuance, suspending/unsuspending, cancelling, terminally redeeming, issuer recovery, and both burn kinds (`ISSUER_RECLAIM` / `FINAL_SETTLEMENT`). The harness tracks every published version of the single `BOND_ISIN` series so multi-version flows (successor cutover, `Replaced` cascade) are reachable.

Registry-to-token consistency is the central cross-cutting property: `token.totalSupply(tokenId)` must equal `mintedSupply − totalBurned` for every tracked version at all times. Tranche consistency is checked independently by summing all tracked tranche `issueCount` values and comparing the result with `mintedSupply`.

## Handlers

| Entrypoint | Caller | Target | Purpose |
|---|---|---|---|
| `fuzz_publishBond` | harness admin (PUBLISHER) | `bondRegistry.publishBond` | Publish a successor version |
| `fuzz_publishBondActiveVersionNotIssuable` | harness admin (PUBLISHER) | `bondRegistry.publishBond` | Negative path: successor publish from non-Issued active version must revert |
| `fuzz_publishBondSuccessorAlreadyPublished` | harness admin (PUBLISHER) | `bondRegistry.publishBond` | Negative path: second Published successor must revert |
| `fuzz_updatePublishedBond` | harness admin (PUBLISHER) | `bondRegistry.updatePublishedBond` | Amend a Published version in place |
| `fuzz_updatePublishedBondInvalidStatus` | harness admin (PUBLISHER) | `bondRegistry.updatePublishedBond` | Negative path: update on non-Published status must revert |
| `fuzz_issueBond` | bond issuer (`USER1`) | `bondRegistry.issueBond` | Mint a tranche and record it |
| `fuzz_issueBondPublisher` | harness admin (PUBLISHER) | `bondRegistry.issueBond` | Mint a tranche through the role-authorized publisher path |
| `fuzz_issueBondUnauthorized` | non-issuer broker | `bondRegistry.issueBond` | Negative path: unauthorized issuance caller must revert |
| `fuzz_issueBondClosed` | bond issuer | `bondRegistry.issueBond` | Negative path: issuance after `closeIssuance` must revert |
| `fuzz_issueBondZeroAmount` | bond issuer | `bondRegistry.issueBond` | Negative path: zero issuance amount must revert |
| `fuzz_issueBondMaxSupplyExceeded` | bond issuer | `bondRegistry.issueBond` | Negative path: issuance above remaining supply must revert |
| `fuzz_issueBondMaturityExpired` | bond issuer | `bondRegistry.issueBond` | Negative path: issuance after maturity must revert |
| `fuzz_issueBondSuccessorSuspendedPrevious` | bond issuer | `bondRegistry.issueBond` | Negative path: first issuance of a published successor while the previous active version is suspended must revert |
| `fuzz_closeIssuance` | harness admin (PUBLISHER) | `bondRegistry.closeIssuance` | Permanently block future issuance |
| `fuzz_closeIssuanceIssuer` | bond issuer | `bondRegistry.closeIssuance` | Permanently block future issuance through the issuer-authorized path |
| `fuzz_closeIssuanceInvalidStatus` | harness admin | `bondRegistry.closeIssuance` | Negative path: invalid lifecycle status must revert |
| `fuzz_closeIssuanceUnauthorized` | non-issuer broker | `bondRegistry.closeIssuance` | Negative path: unauthorized close caller must revert |
| `fuzz_closeIssuanceAlreadyClosed` | bond issuer | `bondRegistry.closeIssuance` | Negative path: closing issuance twice must revert |
| `fuzz_cancelBond` | harness admin (CANCEL) | `bondRegistry.cancelBond` | Cancel the latest Published version when it has no tranches |
| `fuzz_suspendBond` | harness admin (SUSPEND) | `bondRegistry.suspendBond` | Transition Issued to Suspended, pause token id |
| `fuzz_unsuspendBond` | harness admin (UNSUSPEND) | `bondRegistry.unsuspendBond` | Transition Suspended back to Issued, unpause |
| `fuzz_closeBond` | harness admin (CLOSE) | `bondRegistry.closeBond` | Terminally redeem a version once supply is zero and no pending `Published` successor blocks active-version closure |
| `fuzz_rotateIssuer` | harness admin (ISSUER_RECOVERY) | `bondRegistry.rotateIssuer` | Rotate the issuer for a recoverable version; prefers `Replaced` when reachable |
| `fuzz_rotateIssuerInvalidStatus` | harness admin (ISSUER_RECOVERY) | `bondRegistry.rotateIssuer` | Negative path: issuer recovery from `Cancelled` / `Redeemed` must revert |
| `fuzz_burnBondReclaim` | bond issuer | `bondRegistry.burnBond` (`ISSUER_RECLAIM`) | Burn unfrozen issuer-held tokens and reopen capacity |
| `fuzz_burnBondSettlement` | enabled harness admin (BURNER) | `bondRegistry.burnBond` (`FINAL_SETTLEMENT`) | Burn tokens without returning capacity |
| `fuzz_burnBondSettlementIssuer` | bond issuer | `bondRegistry.burnBond` (`FINAL_SETTLEMENT`) | Burn issuer-held tokens through the issuer-authorized settlement path |
| `fuzz_burnBondSettlementHolder` | enabled harness admin (BURNER) | `bondRegistry.burnBond` (`FINAL_SETTLEMENT`) | Burn non-issuer holder/source tokens without returning capacity |
| `fuzz_burnBondBatchReclaim` | bond issuer | `bondRegistry.burnBondBatch` (`ISSUER_RECLAIM`) | Batch burn unfrozen issuer-held tokens and reopen capacity |
| `fuzz_burnBondReclaimFrozenIssuer` | bond issuer | `bondRegistry.burnBond` (`ISSUER_RECLAIM`) | Negative path: reclaim that includes frozen issuer inventory must revert |
| `fuzz_burnBondBatchSettlement` | enabled harness admin (BURNER) | `bondRegistry.burnBondBatch` (`FINAL_SETTLEMENT`) | Batch burn tokens without returning capacity |
| `fuzz_issueBondInvalidStatus` | bond issuer | `bondRegistry.issueBond` | Negative path: issuance against non-issuable status must revert |
| `fuzz_cancelBondInvalid` | harness admin | `bondRegistry.cancelBond` | Negative path: cancel on non-Published or already-issued bond must revert |
| `fuzz_suspendBondInvalidStatus` | harness admin | `bondRegistry.suspendBond` | Negative path: suspend on non-Issued status must revert |
| `fuzz_unsuspendBondInvalidStatus` | harness admin | `bondRegistry.unsuspendBond` | Negative path: unsuspend on non-Suspended status must revert |
| `fuzz_closeBondInvalid` | harness admin | `bondRegistry.closeBond` | Negative path: close on non-closeable status, non-zero supply, or active version with pending `Published` successor must revert |
| `fuzz_burnBondReclaimUnauthorized` | non-issuer broker | `bondRegistry.burnBond` (`ISSUER_RECLAIM`) | Negative path: reclaim from non-issuer caller must revert |
| `fuzz_burnBondSettlementUnauthorized` | non-issuer non-BURNER broker | `bondRegistry.burnBond` (`FINAL_SETTLEMENT`) | Negative path: settlement burn from caller without BURNER role must revert |
| `fuzz_burnBondSettlementBurnerNotEnabled` | unregistered BURNER caller | `bondRegistry.burnBond` (`FINAL_SETTLEMENT`) | Negative path: settlement burn from BURNER caller not enabled in EntityRegistry must revert |
| `fuzz_burnBondInvalidSource` | bond issuer | `bondRegistry.burnBond` | Negative path: invalid source for the burn kind must revert |
| `fuzz_burnBondInvalidStatus` | issuer or enabled BURNER | `bondRegistry.burnBond` | Negative path: invalid burn lifecycle status must revert |
| `fuzz_burnBondBatchLengthMismatch` | bond issuer | `bondRegistry.burnBondBatch` | Negative path: mismatched batch arrays must revert |
| `fuzz_burnBondBatchInvalidSource` | bond issuer | `bondRegistry.burnBondBatch` | Negative path: invalid batch source must revert |
| `fuzz_bondRegistryViewSurface` | harness | BondRegistry getters | Exercise tranche, coupon, version, token, and interface getters |
| `fuzz_publishIndependentZeroCouponBond` | harness admin (PUBLISHER) | `bondRegistry.publishBond` + coupon getters | Publish an independent zero-coupon ISIN and cover zero-coupon getter paths |
| `fuzz_appendScoring` | harness admin (SCORING) | `bondRegistry.appendScoring` | Append a valid scoring record and verify scoring getters |
| `fuzz_appendScoringInvalid` | harness admin (SCORING) | `bondRegistry.appendScoring` | Negative path: invalid scoring input must revert |
| `fuzz_scoringInvalidQueries` | harness | scoring getters | Negative path: invalid scoring reads must revert |
| `fuzz_bondRegistryAdminSurface` | harness owner | `grantRoles(address[],uint256)` | Cover valid array-role grants, including the issuer-recovery role |
| `fuzz_bondRegistryGrantInvalidRole` | harness owner | `grantRoles(address,uint256)` | Negative path: out-of-range role bit must revert |
| `fuzz_bondRegistrySetMultiTokenLocked` | harness owner | `bondRegistry.setMultiToken` | Negative path: locked token address must revert |
| `fuzz_bondRegistryInitializeAgain` | harness owner | `bondRegistry.initialize` | Negative path: repeated initializer must revert |
| `fuzz_publishBondInvalidInput` | harness admin (PUBLISHER) | `bondRegistry.publishBond` | Negative path: invalid bond input validation must revert |

`USER1` is bound as the bond issuer during setup and is granted the issuer-authorized path for `issueBond` and `burnBond(ISSUER_RECLAIM)`. All admin-gated calls are issued from `address(this)`, which is granted `ALL_BR_ROLES` in `_grantRoles` and registered as an enabled `DEUSS_PROTOCOL` account in `EntityRegistry`. The harness keeps a local ledger of burned amounts per `(version, kind)` (`burnedReclaimed`, `burnedSettled`) so the cross-cutting supply invariant can be expressed as an equality despite `_reservedByAsset` and burn accounting being private to the registry.

## Invariants

### Global — group 00

Re-evaluated after every successful action in any vertical through `onSuccessInvariantsGeneral`.

| ID | Condition |
|---|---|
| BOND-01 | For every tracked bond version, `token.totalSupply(tokenId) == mintedSupply − (burnedReclaimed + burnedSettled)` |
| BOND-02 | For every tracked bond version, `remainingIssuableSupply + mintedSupply == maxSupply + burnedReclaimed` |
| BOND-03 | For every tracked bond version in an active status (`Published` / `Issued` / `Suspended`), `token.isTokenPaused(tokenId)` matches `status == Suspended`. Terminal statuses (`Cancelled`, `Replaced`, `Redeemed`) are excluded because the token id pause state is not constrained after the lifecycle ends. `closeBond` unpauses a `Suspended` bond's token id on close, except when the token contract is globally paused (`unpauseTokenId` is `whenNotPaused`-guarded), in which case the token id may remain paused in the terminal `Redeemed` state. |
| BOND-04 | For every tracked bond version, reverse tokenId mapping, stored token address, and computed tokenId are consistent |
| BOND-05 | For every tracked bond version, the sum of all tranche `issueCount` values equals `mintedSupply` |

BOND-01 through BOND-03 are evaluated via separate supply, capacity, and pause aggregates in the `BeforeAfterBondRegistry` snapshot module; BOND-04 uses the `allTrackedBondReverseMappingsConsistent` aggregate; BOND-05 uses the `allTrackedBondTranchesConsistent` aggregate.

### `publishBond` — group 10

Checked in `publishSuccessorPostconditions` for `fuzz_publishBond`.

| ID | Condition | Checked |
|---|---|---|
| BOND-10 | New version equals previous latest plus one | on success |
| BOND-11 | New version has status `Published` | on success |
| BOND-12 | New version starts with `mintedSupply = 0` and `remainingIssuableSupply = maxSupply` | on success |
| BOND-13 | Previous active version's status is not mutated by publish | on success |
| BOND-14 | No unexpected reverts | on revert |
| BOND-15 | `publishBond` successor does not change `activeVersion` | on success |
| BOND-16 | Successor bond fields, including `isGuaranteed`, match the supplied `BondInput` | on success |

### `updatePublishedBond` — group 20

Checked in `updatePublishedPostconditions` for `fuzz_updatePublishedBond`.

| ID | Condition | Checked |
|---|---|---|
| BOND-20 | `tokenId` and `trancheCount` are preserved across the amendment | on success |
| BOND-21 | `remainingIssuableSupply` is reset to the new `maxSupply` | on success |
| BOND-22 | Bond status stays `Published` | on success |
| BOND-23 | No unexpected reverts | on revert |
| BOND-24 | Mutable bond fields are written from the amended input while immutable `isGuaranteed` is preserved | on success |

### `issueBond` — group 30

Checked in `issueBondPostconditions` for `fuzz_issueBond` and `fuzz_issueBondPublisher`.

| ID | Condition | Checked |
|---|---|---|
| BOND-30 | `mintedSupply` grows by the issued amount | on success |
| BOND-31 | `remainingIssuableSupply` shrinks by the issued amount | on success |
| BOND-32 | `trancheCount` grows by 1 and the latest tranche has `issueCount == amount` | on success |
| BOND-33 | Issuer bond balance grows by the issued amount | on success |
| BOND-34 | Token `totalSupply(tokenId)` grows by the issued amount | on success |
| BOND-35 | Status transitions `Published → Issued` on first issuance | on success + first issuance |
| BOND-36 | First issuance of a successor transitions previous active version to `Replaced` | on success + first issuance of a successor |
| BOND-37 | No unexpected reverts | on revert |
| BOND-39 | First issuance of a successor updates `activeVersion` to the issued successor version | on success + first issuance of a successor |
| BOND-102 | The issued version is in `Issued` status after every successful `issueBond`, including repeat issuances | on success |

### `closeIssuance` — group 40

Checked in `closeIssuancePostconditions` for `fuzz_closeIssuance` and `fuzz_closeIssuanceIssuer`.

| ID | Condition | Checked |
|---|---|---|
| BOND-40 | `issuanceClosed` flag flips to `true` | on success |
| BOND-41 | Bond status is not mutated | on success |
| BOND-42 | No unexpected reverts | on revert |

### `cancelBond` — group 50

Checked in `cancelBondPostconditions` for `fuzz_cancelBond`.

| ID | Condition | Checked |
|---|---|---|
| BOND-50 | Status transitions `Published → Cancelled` | on success |
| BOND-51 | No unexpected reverts | on revert |
| BOND-53 | `cancelBond` preserves monotonic `latestVersion` and only clears `activeVersion` when cancelling the active unissued draft | on success |

### `suspendBond` / `unsuspendBond` — group 60

Checked in `suspendBondPostconditions` / `unsuspendBondPostconditions` for `fuzz_suspendBond` and `fuzz_unsuspendBond`.

| ID | Condition | Checked |
|---|---|---|
| BOND-60 | `suspendBond` transitions status `Issued → Suspended` | on success of `fuzz_suspendBond` |
| BOND-61 | `suspendBond` pauses the bond token id | on success of `fuzz_suspendBond` |
| BOND-62 | `unsuspendBond` transitions status `Suspended → Issued` | on success of `fuzz_unsuspendBond` |
| BOND-63 | `unsuspendBond` unpauses the bond token id | on success of `fuzz_unsuspendBond` |
| BOND-64 | No unexpected reverts for either handler | on revert |

### `closeBond` — group 70

Checked in `closeBondPostconditions` for `fuzz_closeBond`.

| ID | Condition | Checked |
|---|---|---|
| BOND-70 | Token `totalSupply(tokenId)` is zero at the moment `closeBond` succeeds (verified against the pre-state snapshot) | on success |
| BOND-71 | Status transitions `Issued` or `Suspended` → `Redeemed` | on success |
| BOND-72 | No unexpected reverts | on revert |

### `burnBond` — group 80

Checked in `burnReclaimPostconditions` / `burnSettlementPostconditions` and the batch equivalents for all burn success handlers.

| ID | Condition | Checked |
|---|---|---|
| BOND-80 | Burn source balance for the burned version's tokenId shrinks by the burned amount | on success |
| BOND-81 | Token `totalSupply(tokenId)` shrinks by the burned amount | on success |
| BOND-82 | `mintedSupply` is not changed by a burn | on success |
| BOND-83 | `ISSUER_RECLAIM` burn grows `remainingIssuableSupply` by the burned amount | on success of reclaim single/batch burns |
| BOND-84 | `FINAL_SETTLEMENT` burn leaves `remainingIssuableSupply` unchanged | on success of settlement single/batch burns |
| BOND-85 | No unexpected reverts for `burnBond` or `burnBondBatch` | on revert |

### `rotateIssuer` — group 105

Checked in `rotateIssuerPostconditions` for `fuzz_rotateIssuer`.

| ID | Condition | Checked |
|---|---|---|
| BOND-105 | `issuer` is updated to the requested enabled replacement issuer | on success |
| BOND-106.status | Lifecycle status is preserved | on success |
| BOND-106.issuanceClosed | Issuance-closed flag is preserved | on success |
| BOND-106.isGuaranteed | Guarantee flag is preserved | on success |
| BOND-106.tokenIdPaused | Token pause state is preserved | on success |
| BOND-106.trancheCount | Tranche count is preserved | on success |
| BOND-106.tokenId | Token id is preserved | on success |
| BOND-106.tokenAddress | Token address is preserved | on success |
| BOND-106.mintedSupply | Minted supply is preserved | on success |
| BOND-106.remainingIssuableSupply | Remaining issuable supply is preserved | on success |
| BOND-106.maxSupply | Max supply is preserved | on success |
| BOND-106.totalSupply | Token total supply is preserved | on success |
| BOND-106.currency | Currency is preserved | on success |
| BOND-106.bondNominalValue | Nominal value is preserved | on success |
| BOND-106.couponRateType | Coupon rate type is preserved | on success |
| BOND-106.couponFrequency | Coupon frequency is preserved | on success |
| BOND-106.issuanceCountry | Issuance country is preserved | on success |
| BOND-106.maturityDate | Maturity date is preserved | on success |
| BOND-106.couponRatesHash | Coupon rates are preserved | on success |
| BOND-106.latestVersion | Latest version is preserved | on success |
| BOND-106.activeVersion | Active version is preserved | on success |
| BOND-107 | Old and new issuer token balances are unchanged | on success |
| BOND-108 | No unexpected reverts | on revert |

### Getter / auxiliary positive surfaces

These handlers exercise valid read/admin/scoring surfaces and keep the same positive-path convention as the lifecycle handlers: preconditions should select valid inputs, and any protocol revert is unexpected unless a later trace proves a specific selector is legitimate. The view surface also covers current-coupon branches for active, zero-coupon, unissued, missing-issue-date, and matured bond structs.

| ID | Condition | Checked |
|---|---|---|
| BOND-110 | `appendScoring` stores the expected scoring record and exposes it through `getScoringAt` / `getLatestScoring` | on success of `fuzz_appendScoring` |
| BOND-111 | `appendScoring` does not unexpectedly revert | on revert |
| BOND-114 | Valid BondRegistry admin helpers do not unexpectedly revert | on revert |
| BOND-117 | Independent zero-coupon bond publication does not unexpectedly revert | on revert |
| BOND-118 | BondRegistry getter surface does not unexpectedly revert for valid tracked series/version/token/tranche/coupon inputs | on getter revert |

### Negative paths — invalid statuses and unauthorized callers

Each invariant in this group checks that the call **must revert** and that the revert reason is one of a small allowlist for that operation. Anything else is a bug.

| ID | Condition | Checked |
|---|---|---|
| BOND-38 | `issueBond` against a version whose status is not `Published` or `Issued` reverts with `BondRegistry__InvalidBondStatus` | always (per `fuzz_issueBondInvalidStatus`) |
| BOND-52 | `cancelBond` against a version that is not `Published`, or that already has tranches, reverts with `BondRegistry__InvalidBondStatus` or `BondRegistry__BondAlreadyIssued` | always (per `fuzz_cancelBondInvalid`) |
| BOND-65 | `suspendBond` against a version whose status is not `Issued` reverts with `BondRegistry__InvalidBondStatus` | always (per `fuzz_suspendBondInvalidStatus`) |
| BOND-66 | `unsuspendBond` against a version whose status is not `Suspended` reverts with `BondRegistry__InvalidBondStatus` | always (per `fuzz_unsuspendBondInvalidStatus`) |
| BOND-73 | `closeBond` against a version that is not in `Issued`/`Suspended`, whose token total supply is non-zero, or whose active version has a pending `Published` successor, reverts with the expected close guard error | always (per `fuzz_closeBondInvalid`) |
| BOND-86 | `burnBond` from a caller that is neither the bond issuer nor an enabled BURNER reverts with `BondRegistry__UnauthorizedBurnCaller` | always (per `fuzz_burnBondReclaimUnauthorized`, `fuzz_burnBondSettlementUnauthorized`, and `fuzz_burnBondSettlementBurnerNotEnabled`) |
| BOND-87 | `issueBond` from a caller that is neither publisher nor issuer reverts with `BondRegistry__UnauthorizedIssuer` | always (per `fuzz_issueBondUnauthorized`) |
| BOND-88 | `issueBond` after `closeIssuance` reverts with `BondRegistry__IssuanceClosed` | always (per `fuzz_issueBondClosed`) |
| BOND-89 | `issueBond` with amount zero reverts with `BondRegistry__IssuanceAmountIsZero` | always (per `fuzz_issueBondZeroAmount`) |
| BOND-90 | `issueBond` above remaining issuable supply reverts with `BondRegistry__MaxSupplyExceeded` | always (per `fuzz_issueBondMaxSupplyExceeded`) |
| BOND-91 | `issueBond` after maturity reverts with `BondRegistry__MaturityDateExpired` | always (per `fuzz_issueBondMaturityExpired`) |
| BOND-92 | `closeIssuance` from an invalid lifecycle status reverts with `BondRegistry__InvalidBondStatus` | always (per `fuzz_closeIssuanceInvalidStatus`) |
| BOND-93 | `closeIssuance` from a caller that is neither publisher nor issuer reverts with `BondRegistry__UnauthorizedIssuanceCloser` | always (per `fuzz_closeIssuanceUnauthorized`) |
| BOND-94 | `closeIssuance` on an already closed version reverts with `BondRegistry__IssuanceClosed` | always (per `fuzz_closeIssuanceAlreadyClosed`) |
| BOND-95 | `burnBond` with a source disallowed for the burn kind reverts with `BondRegistry__InvalidBurnSource` | always (per `fuzz_burnBondInvalidSource`) |
| BOND-96 | `burnBond` from an invalid lifecycle status reverts with `BondRegistry__InvalidBondStatus` | always (per `fuzz_burnBondInvalidStatus`) |
| BOND-97 | `burnBondBatch` with mismatched `froms` / `amounts` lengths reverts with `LengthMismatch` | always (per `fuzz_burnBondBatchLengthMismatch`) |
| BOND-98 | `burnBondBatch` validates each source and reverts with `BondRegistry__InvalidBurnSource` | always (per `fuzz_burnBondBatchInvalidSource`) |
| BOND-99 | `publishBond` while the active version is not `Issued` reverts with `BondRegistry__ActiveVersionNotIssuable` | always (per `fuzz_publishBondActiveVersionNotIssuable`) |
| BOND-100 | `publishBond` while a successor version is already `Published` reverts with `BondRegistry__SuccessorAlreadyPublished` | always (per `fuzz_publishBondSuccessorAlreadyPublished`) |
| BOND-101 | `updatePublishedBond` against a version whose status is not `Published` reverts with `BondRegistry__InvalidBondStatus` | always (per `fuzz_updatePublishedBondInvalidStatus`) |
| BOND-103 | `issueBond` for a published successor while the current active version is `Suspended` reverts with `BondRegistry__InvalidBondStatus` | always (per `fuzz_issueBondSuccessorSuspendedPrevious`) |
| BOND-104 | `ISSUER_RECLAIM` above the issuer's unfrozen/free balance reverts with `BondRegistry__FrozenIssuerReclaimDenied` | always (per `fuzz_burnBondReclaimFrozenIssuer`) |
| BOND-109 | `rotateIssuer` against a version whose status is `Cancelled` or `Redeemed` reverts with `BondRegistry__InvalidBondStatus` | always (per `fuzz_rotateIssuerInvalidStatus`) |
| BOND-112 | Invalid `appendScoring` inputs revert with the expected scoring validation selector | always (per `fuzz_appendScoringInvalid`) |
| BOND-113 | Invalid scoring reads revert with `ScoringNotFound` / `InvalidScoringId` | always (per `fuzz_scoringInvalidQueries`) |
| BOND-115 | Protected admin calls revert with `InvalidRoles`, `MultiTokenLocked`, or `InvalidInitialization` as appropriate | always (per admin negative handlers) |
| BOND-116 | Invalid `publishBond` inputs revert with the expected bond input validation selector | always (per `fuzz_publishBondInvalidInput`) |

### Cross-cutting invariants (pre-existing)

Also enforced after every successful BondRegistry action through `onSuccessInvariantsGeneral`:

- **SPLY-01**, **SPLY-02** — total supply of the fuzzed bond token id stays consistent with tracked balances.
- **ESCR-01**, **ESCR-02**, **ESCR-60** — escrow invariants hold across burns that drop registry supply.
- **OFER-01** — offer balance bounds stay respected even as the token id is suspended.
- **PAUS-01** — active bond status and active version token pause state remain aligned; BOND-03 is the per-version generalisation.

## Preconditions

Summary of the clamping and state-selection logic applied before each handler issues a protocol call. Full implementation in [`helper/preconditions/PreconditionsBondRegistry.sol`](../../test/fuzzing/helper/preconditions/PreconditionsBondRegistry.sol).

| Handler | Clamp rules |
|---|---|
| `publishBond` | Requires a free successor slot (`latestVersion > 0` and `< uint8.max`), active version in `Issued`, and no existing Published successor. Cancelled successors remain in history, so the next successful publish advances to a fresh version/tokenId. New input reuses `BOND_ISIN`, the current issuer, and clamps `maxSupply` to `[1, BOND_ISSUE_COUNT]`. |
| `publishBondActiveVersionNotIssuable` | Requires an existing ISIN, a nonzero active version whose status is not `Issued`, and no Published successor; valid bond input is supplied so the active-status guard is isolated. |
| `publishBondSuccessorAlreadyPublished` | Requires active version in `Issued` and the latest tracked version in `Published`, then attempts to publish another successor. |
| `updatePublishedBond` | Picks a tracked version in `Published` status via `_pickKnownBondVersionByStatus`. Picks a registered user as the amended issuer, clamps `maxSupply` the same way as publish, and preserves the tracked version's `isGuaranteed` value. |
| `updatePublishedBondInvalidStatus` | Picks a tracked version whose status is not `Published` via `_pickKnownBondVersionNotPublished`. |
| `issueBond` | Picks a tracked version that is `Published` or `Issued`, has `issuanceClosed == false`, non-zero `remainingIssuableSupply`, and unexpired maturity (via `_pickKnownBondVersionIssuable`). For first issuance of a successor, the current active predecessor must still be `Issued`; the suspended-predecessor case is covered by the dedicated negative handler. Amount clamped to `[1, min(remainingIssuableSupply, BOND_ISSUE_COUNT)]`. Prank uses the bond issuer. |
| `issueBondPublisher` | Uses the same positive issuance selector as `issueBond`, but calls from the harness admin so the `PUBLISHER` role path is exercised. |
| `issueBondUnauthorized` | Reuses the positive issuance selector but picks a caller that is neither the issuer nor a holder of `PUBLISHER`. |
| `issueBondClosed` | Picks a tracked `Issued` version where `issuanceClosed == true` and calls from the bond issuer. |
| `issueBondZeroAmount` | Picks a positive issuable version and calls with amount `0`. |
| `issueBondMaxSupplyExceeded` | Picks a positive issuable version and calls with `remainingIssuableSupply + 1`. |
| `issueBondMaturityExpired` | Picks a tracked `Published` / `Issued` version that is unclosed but has `maturityDate <= block.timestamp`. |
| `closeIssuance` | Picks a tracked version with `issuanceClosed == false` in `Issued` / `Suspended` status (via `_pickKnownBondVersionIssuanceUnclosed`). |
| `closeIssuanceIssuer` | Uses the same positive close-issuance selector as `closeIssuance`, but calls from the bond issuer instead of the harness admin. |
| `closeIssuanceInvalidStatus` | Picks a tracked version outside `Issued` / `Suspended`, including unissued `Published` versions. |
| `closeIssuanceUnauthorized` | Reuses the positive close-issuance selector but picks a caller that is neither the issuer nor a holder of `PUBLISHER`. |
| `closeIssuanceAlreadyClosed` | Picks a tracked `Issued` / `Suspended` version where `issuanceClosed == true`. |
| `cancelBond` | Picks the latest tracked version only when it is `Published` with `trancheCount == 0` (via `_pickKnownBondVersionCancellable`). |
| `suspendBond` | Picks a tracked `Issued` version. May run while the token contract is globally paused. |
| `unsuspendBond` | Picks a tracked `Suspended` version. Requires the token contract to be unpaused because `unpauseTokenId` remains blocked by global pause. |
| `closeBond` | Picks a tracked version in `Issued` or `Suspended` with `token.totalSupply(tokenId) == 0`, excluding the active version when a later successor is pending (via `_pickKnownBondVersionCloseable`). |
| `rotateIssuer` | Picks a tracked version in `Published`, `Issued`, `Suspended`, or `Replaced`; `Replaced` is preferred when present so superseded-version recovery is exercised densely. Replacement issuer is picked from enabled registered users and must differ from the stored issuer. |
| `rotateIssuerInvalidStatus` | Picks a tracked version in `Cancelled` or `Redeemed`, then supplies an otherwise valid enabled replacement issuer so the status guard is isolated. |
| `burnBondReclaim` | Picks a tracked `Issued` version whose issuer holds non-zero unfrozen/free bond balance (via `_pickKnownBondVersionReclaimable`). Amount clamped to `[1, issuerFreeBalance]`. Prank uses the issuer. |
| `burnBondSettlement` | Picks a tracked version in `Issued` or `Replaced` whose issuer holds a non-zero bond balance (via `_pickKnownBondVersionSettlementBurnable`). Amount clamped the same way; prank uses the enabled harness admin (BURNER role). |
| `burnBondSettlementIssuer` | Uses the same positive settlement selector as `burnBondSettlement`, but calls from the issuer so the issuer-authorized `FINAL_SETTLEMENT` branch is exercised. |
| `burnBondSettlementHolder` | Picks a tracked version in `Issued` or `Replaced` with a non-issuer source balance among tracked users, `escrowManager`, or the harness address, then burns from that source via the enabled harness admin (BURNER role). |
| `burnBondBatchReclaim` | Uses the same selector as reclaim, but splits the free-balance-clamped burn amount across one or two batch entries. |
| `burnBondReclaimFrozenIssuer` | Picks a reclaimable `Issued` version, freezes part of the issuer's free balance as setup, then attempts to reclaim more than the issuer's remaining free balance. |
| `burnBondBatchSettlement` | Uses the same selector as settlement, but splits the clamped burn amount across one or two batch entries. |
| `issueBondInvalidStatus` | Picks a tracked version whose status is not `Published`/`Issued` (via `_pickKnownBondVersionNotIssuable`). Calls `issueBond` with amount 1 from the bond issuer so only the status check can fire. |
| `issueBondSuccessorSuspendedPrevious` | Requires the active version to be `Suspended`, then picks a tracked `Published` successor with open issuance, remaining supply, and unexpired maturity. Calls `issueBond` from the successor issuer and expects the predecessor-status cutover guard to revert. |
| `cancelBondInvalid` | Picks a tracked version that is either not `Published` or has at least one tranche (via `_pickKnownBondVersionNotCancellable`). |
| `suspendBondInvalidStatus` | Picks a tracked version whose status is not `Issued` (via `_pickKnownBondVersionNotIssued`). |
| `unsuspendBondInvalidStatus` | Picks a tracked version whose status is not `Suspended` (via `_pickKnownBondVersionNotSuspended`). |
| `closeBondInvalid` | Picks a tracked version where status is not in `{Issued, Suspended}`, where `totalSupply(tokenId) > 0`, or where the active version has a pending `Published` successor (via `_pickKnownBondVersionNotCloseable`). |
| `burnBondReclaimUnauthorized` | Picks a tracked `Issued` version with a non-zero issuer balance and a caller from tracked users that is neither the issuer nor a holder of the BURNER role. Amount is clamped to issuer balance because authorization fires before reclaim free-balance validation. |
| `burnBondSettlementUnauthorized` | Picks a tracked settlement-burnable version (`Issued` / `Replaced` with non-zero issuer balance) and the same kind of unauthorized caller. |
| `burnBondSettlementBurnerNotEnabled` | Picks a tracked settlement-burnable version, grants `BURNER` to a fixed unregistered caller, and expects the EntityRegistry enabled-account gate to reject it. |
| `burnBondInvalidSource` | Picks a burn-compatible status for the selected kind and calls from the issuer with `from != issuer`, so the source check is isolated. |
| `burnBondInvalidStatus` | Picks a status disallowed for the selected kind and uses an otherwise authorized caller/source. |
| `burnBondBatchLengthMismatch` | Picks an existing version and supplies `froms.length != amounts.length`. |
| `burnBondBatchInvalidSource` | Picks an `Issued` version and includes a non-issuer source in an `ISSUER_RECLAIM` batch. |
| `bondRegistryViewSurface` | Picks a tracked version with at least one tranche and calls every BondRegistry getter variant against valid active/version/token ids, including current-coupon helper branches. |
| `publishIndependentZeroCouponBond` | Publishes `BOND_ZERO_COUPON_ISIN` once with empty coupon arrays, then calls zero-coupon getter paths. |
| `appendScoring` | Picks a user wallet, records its previous scoring count, and builds a valid append-only scoring record. |
| `appendScoringInvalid` | Selects zero wallet, zero issue date, invalid expiration, zero distributor id, or probability over 10_000. |
| `scoringInvalidQueries` | Uses an unscored fuzz wallet and a non-zero id to isolate scoring getter reverts. |
| `bondRegistryAdminSurface` | Grants one valid role through the array overload, then revokes through the scalar and batch revoke surfaces. |
| `bondRegistryGrantInvalidRole` | Calls `grantRoles(address,uint256)` with an out-of-range role bit. |
| `bondRegistrySetMultiTokenLocked` | Calls `setMultiToken` after the token address has already been locked by setup. |
| `bondRegistryInitializeAgain` | Calls `initialize` after setup has already initialized the proxy. |
| `publishBondInvalidInput` | Selects invalid issuer, currency, bondNominalValue, max supply, maturity, coupon length, coupon order, or duplicate coupon cases. |

All clamp failures raise `ClampFail(string)`, which the integrity layer accepts as a skip rather than a bug.
