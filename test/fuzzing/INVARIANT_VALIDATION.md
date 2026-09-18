# Invariant Validation Ledger

This file tracks whether fuzz invariants are merely green or actually validated.

Validation status meanings:

- `unproven`: invariant exists, but no positive proof has been recorded yet
- `partially proven`: clean run exists, but no mutant has been killed yet
- `proven`: relevant state is reachable, a targeted mutant was killed, and clean code still passes

Proof workflow for each invariant:

1. Confirm reachability through the current harness surface, corpus activity, and coverage.
2. Introduce one minimal realistic mutant in production logic or state transition logic.
3. Re-run a short Echidna campaign and confirm the target invariant fails.
4. Restore clean code and confirm the campaign passes again.
5. Record the evidence here.

## Catalog

- `SPLY`: `SPLY_01` .. `SPLY_05`
- `ESCR`: `ESCR_01`, `ESCR_02`, `ESCR_10` .. `ESCR_16`, `ESCR_20` .. `ESCR_26`, `ESCR_30` .. `ESCR_33`, `ESCR_40` .. `ESCR_43`, `ESCR_50` .. `ESCR_58`, `ESCR_60` .. `ESCR_64`, `ESCR_70` .. `ESCR_72`
- `MKT`: `MKT_80` .. `MKT_82`
- `BMF`: `BMF_10`, `BMF_20`, `BMF_30`
- `OB`: `OB_10` .. `OB_14`
- `OFER`: `OFER_01`, `OFER_10` .. `OFER_13`, `OFER_20` .. `OFER_22`, `OFER_30` .. `OFER_34`, `OFER_40`, `OFER_50` .. `OFER_52`, `OFER_60` .. `OFER_64`, `OFER_70` .. `OFER_72`
- `DEAL`: `DEAL_01` .. `DEAL_03`, `DEAL_10` .. `DEAL_18`, `DEAL_20` .. `DEAL_24`, `DEAL_30` .. `DEAL_32`, `DEAL_40` .. `DEAL_41`, `DEAL_50` .. `DEAL_52`, `DEAL_60` .. `DEAL_67`
- `INTR`: `INTR_01`, `INTR_10` .. `INTR_13`, `INTR_20` .. `INTR_24`, `INTR_30` .. `INTR_32`, `INTR_40` .. `INTR_43`
- `PAUS`: `PAUS_01`
- `ER`: `ER_01`, `ER_10` .. `ER_12`, `ER_20` .. `ER_21`, `ER_30` .. `ER_33`, `ER_40` .. `ER_41`, `ER_50` .. `ER_52`, `ER_60` .. `ER_63`, `ER_70` .. `ER_71`, `ER_80` .. `ER_107`, `ER_110` .. `ER_115`
- `ASET`: `ASET_01`, `ASET_02`, `ASET_10` .. `ASET_15`, `ASET_20` .. `ASET_24`, `ASET_30` .. `ASET_33`, `ASET_40` .. `ASET_42`
- `ESAU`: `ESAU_01`, `ESAU_02`, `ESAU_10` .. `ESAU_13`, `ESAU_20` .. `ESAU_23`, `ESAU_30` .. `ESAU_34`, `ESAU_40` .. `ESAU_42`, `ESAU_50` .. `ESAU_52`, `ESAU_60`, `ESAU_61`, `ESAU_70` .. `ESAU_72`
- `PR`: `PR_10` .. `PR_13`, `PR_20` .. `PR_24`, `PR_30` .. `PR_34`, `PR_40` .. `PR_42`, `PR_50` .. `PR_53`, `PR_60` .. `PR_65`, `PR_70` .. `PR_77`
- `BOND`: `BOND_01` .. `BOND_05`, `BOND_10` .. `BOND_16`, `BOND_20` .. `BOND_24`, `BOND_30` .. `BOND_42`, `BOND_50` .. `BOND_53`, `BOND_60` .. `BOND_66`, `BOND_70` .. `BOND_73`, `BOND_80` .. `BOND_118`
- `TKN`: `TKN_01`, `TKN_10` .. `TKN_13`, `TKN_20` .. `TKN_22`, `TKN_30`, `TKN_31`, `TKN_40`, `TKN_41`, `TKN_50` .. `TKN_52`, `TKN_60` .. `TKN_63`, `TKN_70`, `TKN_71`, `TKN_80`, `TKN_81`

## Baseline

- Clean campaign command: `npm run echidna-fast`
- Clean campaign result: pass, `10026` calls, `126437` unique instructions, `20` corpus sequences
- Coverage artifact: Not archived in this repository. The baseline records the local campaign result only.

Additional mutation-validation batches have not yet been recorded for newer invariant families and later marketplace surfaces, especially `ASET`, `ESAU`, `PR`, `BOND`, `TKN`, dispute/freeze/seizure IDs, and batch settlement IDs. Add rows only after a targeted mutant is killed and the restored code is rerun cleanly. The per-harness reachability and current status of these families is recorded in the `Per-harness reachability report (RQ_SEC_FUZZ)` section below; that section records reachability and status only and does not claim mutation evidence that has not been captured.

## Per-harness reachability report (RQ_SEC_FUZZ)

This section is the per-harness reachability report required by the `RQ_SEC_FUZZ` acceptance criterion ("Per-harness reachability report committed to `test/fuzzing/INVARIANT_VALIDATION.md`"). It satisfies that clause only. The other `RQ_SEC_FUZZ` acceptance clause — `npm run echidna` and `npm run medusa` smoke-passing in CI on a schedule — is a CI-configuration concern (`.gitlab-ci.yml`) and is not evidenced in this ledger.

The nine harnesses are the verticals composed into `Fuzz.sol`: `DEUSSToken`, `EntityRegistry`, `BondRegistry`, `PolicyRegistry`, `Marketplace`, `OrderbookMarketplace`, `EscrowManager`, `AssetManager`, and `EscrowAuth`. Their public `fuzz_*` entrypoints live in the matching `Fuzz*Integrity.sol` contracts; the directed `FuzzMarketplaceLifecycle` target is a sibling campaign for rare Marketplace states.

### How to read the status column

The status values keep the same meaning as the top of this file, applied per invariant family rather than per harness:

- `proven` — a targeted mutant was killed for the listed ID and clean code reran cleanly. See Batches 1–3 for the mutant detail. Reachability is demonstrated because the mutated production branch was caught.
- `partially proven` — the entrypoints are composed into `Fuzz.sol` and the recorded clean `npm run echidna-fast` baseline exercises the relevant common action, but no mutant has been killed and no per-harness coverage artifact is archived.
- `unproven` — the invariant requires a rare lifecycle state that is reached only through directed flows or the `FuzzMarketplaceLifecycle` campaign whose results are not recorded in this ledger, and no mutant has been killed.

### Evidence caveats (apply to every harness below)

- The only recorded real campaign is the `npm run echidna-fast` baseline above, run against the composite `Fuzz` target. Its `10026` calls / `126437` unique instructions / `20` corpus sequences are reported for the whole composite target, not broken down per harness.
- `npm run medusa-fast` runs with `--test-limit 1`; it is a compile/selector smoke check, not a reachability campaign, and no Medusa result is recorded here.
- The directed `npm run echidna-interest-lifecycle` / `npm run medusa-interest-lifecycle` campaigns are designed to densify rare Marketplace states, but no result or coverage from them is recorded in this ledger.
- No per-harness coverage report or corpus directory is archived in this repository. Per-family reachability without a killed mutant therefore rests on composition plus the single clean baseline, not on an independent coverage artifact.
- Escrow accounting (`ESCR`) is reached from two harnesses. `ESCR_10`/`ESCR_11`/`ESCR_12` are attributed to the Marketplace harness (offer register/cancel paths) and `ESCR_20`/`ESCR_21`/`ESCR_22`/`ESCR_24` to the EscrowManager harness (`fuzz_createEscrow`); each ID is counted once, under the entrypoint that killed its mutant.

### Summary

| Harness | Public `fuzz_*` entrypoints | Invariant families | Mutants killed (this ledger) | Headline status |
| --- | --- | --- | --- | --- |
| `DEUSSToken` | 25 | `SPLY`, `TKN`, `PAUS` (shared) | 0 | partially proven; no `proven` rows |
| `EntityRegistry` | 29 | `ER` | 10 (Batch 1) | partially proven; 10 IDs proven; expanded pending/admin account-registration surface pending fuzz campaign |
| `BondRegistry` | 50 | `BOND`, `SPLY`/`PAUS` (shared) | 0 | partially proven; no `proven` rows |
| `PolicyRegistry` | 23 | `PR` | 0 | partially proven; version-monotonicity invariant implemented and reached, clean re-run pending |
| `Marketplace` | 37 | `OFER`, `DEAL`, `INTR`, `ESCR` (shared), `MKT` | 14 (Batches 2–3) | partially proven; dispute/freeze/seizure/batch unproven |
| `OrderbookMarketplace` | 11 | `OB`, `BMF`, `MKT`/`ESCR` residual coverage | 0 | partially proven; directed checks are property-backed, full order/trade invariant model pending |
| `EscrowManager` | 9 | `ESCR` | 4 (Batch 3) | partially proven; 4 IDs proven |
| `AssetManager` | 6 | `ASET` | 0 | partially proven; no `proven` rows |
| `EscrowAuth` | 11 | `ESAU` | 0 | partially proven; no `proven` rows |

Entrypoint counts are the `fuzz_*` functions declared in each `Fuzz*Integrity.sol`. "Mutants killed" counts only the IDs recorded in Batches 1–3 of this ledger. The column sums to 28; the three remaining proven IDs are `ESCR_10`/`ESCR_11`/`ESCR_12`, reached through Marketplace register/cancel entrypoints but tallied with the shared escrow family, giving 31 proven rows total across Batches 1–3.

### DEUSSToken

- **Fuzz entrypoints reached:** `fuzz_approve`, `fuzz_approveNonZeroToNonZero`, `fuzz_grantRolesBatchInvalidRoles`, `fuzz_transfer`, `fuzz_transferFromAllowance`, `fuzz_setOperator`, `fuzz_setOperatorUnregistered`, `fuzz_transferFromOperator`, `fuzz_batchTransferFromSingleReceiver`, `fuzz_batchTransferFromMultipleReceivers`, `fuzz_freezePartialTokens`, `fuzz_batchFreezePartialTokens`, `fuzz_unfreezePartialTokens`, `fuzz_batchUnfreezePartialTokens`, `fuzz_forcedTransfer`, `fuzz_batchForcedTransfer`, `fuzz_burn`, `fuzz_burnBatch`, `fuzz_protectAddress`, `fuzz_protectedReceiverTransfer`, `fuzz_checkpointFutureReverts`, `fuzz_setContractPause`, `fuzz_setBondSuspended`, `fuzz_contractPauseBlocksAction`, `fuzz_tokenIdPauseBlocksTransfer`.
- **Invariant families / IDs exercised:** `TKN_01`, `TKN_10` .. `TKN_13`, `TKN_20` .. `TKN_22`, `TKN_30`, `TKN_31`, `TKN_40`, `TKN_41`, `TKN_50`, `TKN_51`, `TKN_60` .. `TKN_63`, `TKN_70`, `TKN_71`, `TKN_80`, `TKN_81`; supply invariants `SPLY_01` .. `SPLY_05`; pause-alignment `PAUS_01` (shared with `BondRegistry`).
- **Validation command:** `npm run echidna-fast` (composite, recorded clean); `npm run medusa-fast` for selector/compile parity (not recorded).
- **Corpus / coverage evidence:** composite baseline only; no per-harness coverage or corpus artifact archived.
- **Mutants killed:** none recorded.
- **Evidence status:**

| Family group | Status | Note |
| --- | --- | --- |
| `TKN_10` .. `TKN_63`, `TKN_80`, `TKN_81` (approve/transfer/operator/freeze/burn/pause/protected-receiver assertions) | partially proven | common token actions exercised by the baseline; no mutant |
| `TKN_01`, `TKN_70`, `TKN_71` (frozen-balance bound, checkpoints) | partially proven | no mutant; reachability not coverage-archived |
| `SPLY_01` .. `SPLY_05` (total-supply / face-value invariants) | partially proven | global invariants; no mutant |
| `PAUS_01` (bond status vs token-id pause alignment) | partially proven | cross-cutting with `BondRegistry`; no mutant |

### EntityRegistry

- **Fuzz entrypoints reached:** `fuzz_registerEntity`, `fuzz_setEntityStatus`, `fuzz_registerAccount`, `fuzz_requestAccountRegistration`, `fuzz_acceptAccountRegistration`, `fuzz_requestAccountRegistrationOverwrite`, `fuzz_requestAccountRegistrationMultipleEntities`, `fuzz_pendingAccountRegistrationInvalidInputs`, `fuzz_acceptAccountRegistrationAlreadyRegistered`, `fuzz_requesterRevocationBeforeAcceptance`, `fuzz_stalePendingRegistrationAfterRemoval`, `fuzz_adminRegisterAccount`, `fuzz_registerAccountUnauthorized`, `fuzz_registerAccountInvalidInputs`, `fuzz_setAccountStatus`, `fuzz_removeAccount`, `fuzz_transferAccountToEntity`, `fuzz_setEntityManager`, `fuzz_registerEntityWithAccess`, `fuzz_registerEntityBatch`, `fuzz_setEntityMetadata`, `fuzz_setEntityAuthority`, `fuzz_setAccountRoleFlags`, `fuzz_entityRegistryViewSurface`, `fuzz_entityTypeSurface`, `fuzz_entityRegistryAdminSurface`, `fuzz_entityRegistryInitializeAgain`, `fuzz_entityRegistryFreshDeployment`, `fuzz_entityAccountSwapAndPopSurface`.
- **Invariant families / IDs exercised:** `ER_01`, `ER_10` .. `ER_12`, `ER_20`, `ER_21`, `ER_30` .. `ER_33`, `ER_40`, `ER_41`, `ER_50` .. `ER_52`, `ER_60` .. `ER_63`, `ER_70`, `ER_71`, `ER_80` .. `ER_107`, `ER_110` .. `ER_115`.
- **Validation command:** `npm run echidna-fast` (composite, recorded clean).
- **Corpus / coverage evidence:** composite baseline only; no per-harness coverage or corpus artifact archived.
- **Mutants killed:** `ER_20`, `ER_30`, `ER_31`, `ER_40`, `ER_50`, `ER_51`, `ER_60`, `ER_61`, `ER_62`, `ER_70` (10 IDs, Batch 1).
- **Evidence status:**

| Family group | Status | Note |
| --- | --- | --- |
| `ER_20`, `ER_40` (status transitions), `ER_30`, `ER_31` (account-role/link consistency), `ER_50`, `ER_51`, `ER_60` .. `ER_62`, `ER_70` | proven | killed mutants in Batch 1; clean rerun via baseline |
| `ER_01`, `ER_10` .. `ER_12`, `ER_21`, `ER_32`, `ER_33`, `ER_41`, `ER_52`, `ER_63`, `ER_71` | partially proven | reached by the same entrypoints; no mutant |
| `ER_80` .. `ER_91` (access/metadata/authority/role-flags/views/admin/swap-pop surfaces) | partially proven | reached by the auxiliary surface entrypoints; no mutant |
| `ER_92` .. `ER_107` (separate pending-registration request/accept/overwrite/revocation/stale surfaces) | unproven — implemented | compiled into the harness; clean Echidna/Medusa campaign and mutant kill pending |
| `ER_110` .. `ER_115` (admin immediate `registerAccount` success/auth/input/account-state surfaces) | unproven — implemented | compiled into the harness; clean Echidna/Medusa campaign and mutant kill pending |

### BondRegistry

- **Fuzz entrypoints reached:** `fuzz_publishBond`, `fuzz_publishBondActiveVersionNotIssuable`, `fuzz_publishBondSuccessorAlreadyPublished`, `fuzz_updatePublishedBond`, `fuzz_updatePublishedBondInvalidStatus`, `fuzz_issueBond`, `fuzz_issueBondPublisher`, `fuzz_issueBondSuccessorSuspendedPrevious`, `fuzz_closeIssuance`, `fuzz_closeIssuanceIssuer`, `fuzz_cancelBond`, `fuzz_suspendBond`, `fuzz_unsuspendBond`, `fuzz_closeBond`, `fuzz_burnBondReclaim`, `fuzz_burnBondSettlement`, `fuzz_burnBondSettlementIssuer`, `fuzz_burnBondSettlementHolder`, plus negative/auth variants (`fuzz_issueBondInvalidStatus`, `fuzz_cancelBondInvalid`, `fuzz_suspendBondInvalidStatus`, `fuzz_unsuspendBondInvalidStatus`, `fuzz_closeBondInvalid`, `fuzz_burnBondReclaimUnauthorized`, `fuzz_burnBondSettlementUnauthorized`, `fuzz_burnBondSettlementBurnerNotEnabled`, `fuzz_issueBondUnauthorized`, `fuzz_issueBondClosed`, `fuzz_issueBondZeroAmount`, `fuzz_issueBondMaxSupplyExceeded`, `fuzz_issueBondMaturityExpired`, `fuzz_closeIssuanceInvalidStatus`, `fuzz_closeIssuanceUnauthorized`, `fuzz_closeIssuanceAlreadyClosed`, `fuzz_burnBondInvalidSource`, `fuzz_burnBondInvalidStatus`, `fuzz_burnBondBatchReclaim`, `fuzz_burnBondBatchSettlement`, `fuzz_burnBondBatchLengthMismatch`, `fuzz_burnBondBatchInvalidSource`, `fuzz_publishBondInvalidInput`), the scoring surface (`fuzz_appendScoring`, `fuzz_appendScoringInvalid`, `fuzz_scoringInvalidQueries`), and admin/view surfaces (`fuzz_bondRegistryViewSurface`, `fuzz_publishIndependentZeroCouponBond`, `fuzz_bondRegistryAdminSurface`, `fuzz_bondRegistryGrantInvalidRole`, `fuzz_bondRegistrySetMultiTokenLocked`, `fuzz_bondRegistryInitializeAgain`).
- **Invariant families / IDs exercised:** `BOND_01` .. `BOND_05`, `BOND_10` .. `BOND_16`, `BOND_20` .. `BOND_24`, `BOND_30` .. `BOND_42`, `BOND_50` .. `BOND_53`, `BOND_60` .. `BOND_66`, `BOND_70` .. `BOND_73`, `BOND_80` .. `BOND_103`, `BOND_110` .. `BOND_118`; shared `SPLY` (supply moves on issue/burn) and `PAUS_01` (suspend/unsuspend vs token-id pause).
- **Validation command:** `npm run echidna-fast` (composite, recorded clean); `npm run medusa-fast` for selector/compile parity (not recorded).
- **Corpus / coverage evidence:** composite baseline only; no per-harness coverage or corpus artifact archived.
- **Mutants killed:** none recorded. Listed in the Baseline note above as a family with no mutation-validation batch yet.
- **Evidence status:**

| Family group | Status | Note |
| --- | --- | --- |
| `BOND_10` .. `BOND_16` (publish), `BOND_30` .. `BOND_42` (issue / close issuance), `BOND_50` .. `BOND_53` (cancel), `BOND_60` .. `BOND_66` (suspend / unsuspend), `BOND_70` .. `BOND_73` (close) | partially proven | the publish → suspend → unsuspend → cancel/close lifecycle required by `RQ_SEC_FUZZ` is reachable via single-action entrypoints in the baseline; no mutant |
| `BOND_01` .. `BOND_05` (per-version supply / pause / tokenId consistency) | partially proven | global invariants; no mutant |
| `BOND_20` .. `BOND_24` (update), `BOND_80` .. `BOND_103` (burn + auth + negative), `BOND_110` .. `BOND_118` (scoring / admin / views) | partially proven | reached by the matching entrypoints; no mutant |

### PolicyRegistry

- **Fuzz entrypoints reached:** `fuzz_grantWalletPolicyAdmin`, `fuzz_revokeWalletPolicyAdmin`, `fuzz_grantUserRoles`, `fuzz_revokeUserRoles`, `fuzz_setUserRoles`, `fuzz_grantUserRolesBatch`, `fuzz_revokeUserRolesBatch`, `fuzz_setUserRolesBatch`, `fuzz_grantOperationRoles`, `fuzz_revokeOperationRoles`, `fuzz_setOperationRoles`, `fuzz_grantOperationRolesBatch`, `fuzz_revokeOperationRolesBatch`, `fuzz_setOperationRolesBatch`, `fuzz_setOperationModule`, `fuzz_setOperationModuleBatch`, `fuzz_setPolicyModuleAllowed`, `fuzz_setRoleLabel`, `fuzz_checkPolicyLookup`, `fuzz_checkPolicyLookupWithAllowModule`, `fuzz_companyWalletAdminSurface`, `fuzz_executePolicyCall`, `fuzz_advancePolicyVersionResetsState`.
- **Invariant families / IDs exercised:** `PR_10` .. `PR_13`, `PR_20` .. `PR_24`, `PR_30` .. `PR_34`, `PR_40` .. `PR_42`, `PR_50` .. `PR_53`, `PR_60` .. `PR_65`, `PR_70` .. `PR_77`.
- **Validation command:** `npm run echidna-fast` (composite; recorded clean for `PR_10` .. `PR_63`). A `2026-06-01` `echidna-fast` run reached the new `fuzz_advancePolicyVersionResetsState` entrypoint (reachability empirically confirmed) and falsified it — surfacing a harness false-positive, not a protocol defect: the handler seeded `setOperationModule` with `policyAllowModule` after `fuzz_setPolicyModuleAllowed` had globally disallowed it, so the seeding call reverted (`PolicyModuleNotAllowed`) and tripped the handler's own "seed must succeed" assertion. The handler/precondition now seed and check the operation-module dimension only when the allow-module is currently allowlisted. A clean re-run after this fix has not yet been recorded. `npm run medusa-fast` for selector/compile parity (not recorded).
- **Corpus / coverage evidence:** composite baseline only; no per-harness coverage or corpus artifact archived.
- **Mutants killed:** none recorded.
- **Evidence status:**

| Family group | Status | Note |
| --- | --- | --- |
| `PR_10` .. `PR_13` (wallet policy admin), `PR_20` .. `PR_34` (user / operation roles), `PR_40` .. `PR_42` (operation modules), `PR_50` .. `PR_53` (module allowlist / role labels) | partially proven | reached by the matching entrypoints; no mutant |
| `PR_60` .. `PR_65` (`canExecute` / module diagnostics / `CompanyWallet.execute` authorization / key derivation / CompanyWallet admin surface) | partially proven | reached via `fuzz_checkPolicyLookup`, `fuzz_checkPolicyLookupWithAllowModule`, `fuzz_companyWalletAdminSurface`, and `fuzz_executePolicyCall`; no mutant |
| `PR_70` .. `PR_72` — policy version monotonicity (`RQ_SEC_FUZZ` clause) | unproven — implemented and reached; clean re-run pending | `fuzz_advancePolicyVersionResetsState` seeds wallet-scoped policy on a dedicated `policyEpochWallet`, then transfers ownership to advance `ICompanyWallet.ownershipEpoch()`. `PR_70` asserts the version increments by exactly one and never decreases; `PR_71` asserts the seeded admin / user-roles / operation-roles (and operation-module when the allow-module is allowlisted) were present at the prior epoch and are reset at the new epoch; `PR_72` asserts the transfer does not unexpectedly revert. Reachability is **empirically confirmed**: a `2026-06-01` `echidna-fast` run reached and evaluated the entrypoint. That run falsified the test due to a now-fixed harness false-positive (module/allowlist coupling, see Validation command above), not a protocol defect. No mutant has been killed and no clean campaign has been recorded since the fix, so the clause stays `unproven`. **To reach `proven`:** re-run `npm run echidna-fast` for the clean pass (→ `partially proven`), then introduce a mutant (e.g. drop the `_ownershipEpoch = nextEpoch` increment in `CompanyWallet._setOwner` to fail `PR_70`, or make `_getWalletEpoch` return a constant to fail `PR_71`), confirm the kill, restore, rerun clean, and record a Batch 4 row. |

### Marketplace

- **Fuzz entrypoints reached (broad `FuzzMarketplaceIntegrity`):** `fuzz_registerMarketplaceOffer`, `fuzz_registerRedemptionOffer`, `fuzz_registerInterestOffer`, `fuzz_acceptOffer`, `fuzz_expressInterest`, `fuzz_expressInterestBelowThreshold`, `fuzz_activateInterest`, `fuzz_closeExpiredInterest`, `fuzz_closeExpiredInterestsBatch`, `fuzz_withdrawAvailable`, `fuzz_withdrawInterestAvailable`, `fuzz_withdrawInterestAvailableBelowThreshold`, `fuzz_createCounterOffer`, `fuzz_cancelOffer`, `fuzz_cancelFailedInterestOffer`, `fuzz_cancelFailedInterestOfferByOperator`, `fuzz_cancelCounterOffer`, `fuzz_resolveCounterOffer`, `fuzz_resolvePayment`, `fuzz_resolvePayments`, `fuzz_resolvePaymentsDuplicateUnpaid`, `fuzz_resolvePaymentsExpiredPaid`, `fuzz_resolvePaymentsUnauthorized`, `fuzz_resolvePaymentUnauthorized`, `fuzz_settleDeal`, `fuzz_settleDealsBatch`, `fuzz_settleDealsMixedBatch`, `fuzz_initiateDispute`, `fuzz_resolveDispute`, `fuzz_disputeResolutionFlow`, `fuzz_setOfferFrozen`, `fuzz_setDealFrozen`, `fuzz_seizeOfferEscrow`, `fuzz_seizeOfferReservedInterest`, `fuzz_seizeDeal`, `fuzz_seizePaidDeal`, `fuzz_marketplaceAdminSurface`.
- **Directed lifecycle entrypoints (`FuzzMarketplaceLifecycle`):** `fuzz_directSaleResolveUnpaid`, `fuzz_directSaleSettleUnpaid`, `fuzz_directSaleWithdrawAfterUnpaidSettlement`, `fuzz_interestDiscoveryCloseExpiredInterest`, `fuzz_interestDiscoveryCloseExpiredInterestsBatch`, `fuzz_interestDiscoveryWithdrawExpiredAvailable`, `fuzz_activatedInterestResolveUnpaid`, `fuzz_activatedInterestSettleUnpaid`, `fuzz_marketplaceNegativeValidationSurface`.
- **Invariant families / IDs exercised:** `OFER_01`, `OFER_10` .. `OFER_13`, `OFER_20` .. `OFER_22`, `OFER_30` .. `OFER_34`, `OFER_40`, `OFER_50` .. `OFER_52`, `OFER_60` .. `OFER_64`; `DEAL_01` .. `DEAL_03`, `DEAL_10` .. `DEAL_18`, `DEAL_20` .. `DEAL_24`, `DEAL_30` .. `DEAL_32`, `DEAL_40`, `DEAL_41`, `DEAL_50` .. `DEAL_52`, `DEAL_60` .. `DEAL_67`; `INTR_01`, `INTR_10` .. `INTR_13`, `INTR_20` .. `INTR_24`, `INTR_30` .. `INTR_32`, `INTR_40` .. `INTR_43`; offer-linked escrow `ESCR_10` .. `ESCR_16`; directed admin/negative coverage `MKT_80` .. `MKT_82`.
- **Validation command:** `npm run echidna-fast` (broad composite, recorded clean); directed branches via `npm run echidna-interest-lifecycle` / `npm run medusa-interest-lifecycle` (not recorded in this ledger).
- **Corpus / coverage evidence:** composite baseline only; the directed lifecycle campaigns write coverage under `*-directed-corpus/` when run, but no run output is archived here.
- **Mutants killed:** `OFER_10`, `OFER_11`, `OFER_12`, `OFER_20`, `OFER_21` (offers); `DEAL_01`, `DEAL_02`, `DEAL_10`, `DEAL_20`, `DEAL_21`, `DEAL_30`, `DEAL_40`, `DEAL_50`, `DEAL_51` (deals); `ESCR_10`, `ESCR_11`, `ESCR_12` (offer-linked escrow) — 17 IDs across Batches 2–3 reached through Marketplace entrypoints. (The summary table counts the 14 `OFER`/`DEAL` IDs under Marketplace and the 3 `ESCR` IDs under the shared escrow family.)
- **Evidence status:**

| Family group | Status | Note |
| --- | --- | --- |
| `OFER_10` .. `OFER_12`, `OFER_20`, `OFER_21`; `DEAL_01`, `DEAL_02`, `DEAL_10`, `DEAL_20`, `DEAL_21`, `DEAL_30`, `DEAL_40`, `DEAL_50`, `DEAL_51`; `ESCR_10` .. `ESCR_12` | proven | killed mutants in Batches 2–3; clean rerun via baseline (asset-conservation core: register / accept / cancel / settle / counter-offer / escrow funding) |
| `OFER_01`, `OFER_13`, `OFER_22`, `OFER_40`, `OFER_50` .. `OFER_52`; `DEAL_03`, `DEAL_11`, `DEAL_22`, `DEAL_32`, `DEAL_41`, `DEAL_52`; `INTR_01`, `INTR_10` .. `INTR_13` | partially proven | reached by common register/accept/cancel/withdraw/express entrypoints; no mutant |
| `MKT_80` .. `MKT_82` (admin/view and defensive-branch coverage) | partially proven | reached by Marketplace admin and directed lifecycle negative-validation surfaces; no mutant |
| `INTR_20` .. `INTR_24`, `INTR_30` .. `INTR_32`, `INTR_40` .. `INTR_43` (activate / close-expired / interest-discovery withdrawal) | unproven | rare multi-step / time-derived states; densified by the directed lifecycle campaign whose result is not recorded; no mutant |
| `DEAL_60` .. `DEAL_63` (dispute), `OFER_60`, `OFER_61`, `DEAL_64`, `DEAL_65` (freeze) | unproven | flagged in the Baseline note above; reached only via dispute/freeze flows; no mutant |
| `OFER_62` .. `OFER_64`, `DEAL_66`, `DEAL_67` (seizure) | unproven | flagged in the Baseline note above; reached only via seizure flows; no mutant |
| `OFER_30` .. `OFER_34`, `DEAL_14` .. `DEAL_18`, `DEAL_24`, `ESCR_13`, `ESCR_15`, `ESCR_16` (batch settlement) | unproven | flagged in the Baseline note above; batch/settlement paths; no mutant |

### EscrowManager

- **Fuzz entrypoints reached:** `fuzz_createEscrow`, `fuzz_createEscrowUnauthorized`, `fuzz_withdraw`, `fuzz_claim`, `fuzz_sweep`, `fuzz_directTransferToEscrow`, `fuzz_multiStandardEscrowSurface`, `fuzz_registerModule`, `fuzz_deactivateModule`.
- **Invariant families / IDs exercised:** `ESCR_01`, `ESCR_02` (global), `ESCR_20` .. `ESCR_26` (createEscrow), `ESCR_30` .. `ESCR_33` (withdraw), `ESCR_40` .. `ESCR_43` (claim), `ESCR_50` .. `ESCR_52` (sweep), `ESCR_53` .. `ESCR_58` (directTransferToEscrow), `ESCR_60` .. `ESCR_64` (balance bound / module accounting), `ESCR_70` .. `ESCR_72` (multi-standard and residual coverage).
- **Validation command:** `npm run echidna-fast` (composite, recorded clean).
- **Corpus / coverage evidence:** composite baseline only; no per-harness coverage or corpus artifact archived.
- **Mutants killed:** `ESCR_20`, `ESCR_21`, `ESCR_22`, `ESCR_24` (4 IDs, Batch 3, via `fuzz_createEscrow`).
- **Evidence status:**

| Family group | Status | Note |
| --- | --- | --- |
| `ESCR_20`, `ESCR_21`, `ESCR_22`, `ESCR_24` (createEscrow field/counter/balance/reserved accounting) | proven | killed mutants in Batch 3; clean rerun via baseline |
| `ESCR_23`, `ESCR_25`, `ESCR_26` (createEscrow depositor balance / no-revert / unauthorized) | partially proven | reached by `fuzz_createEscrow` / `fuzz_createEscrowUnauthorized`; no mutant |
| `ESCR_30` .. `ESCR_33` (withdraw), `ESCR_40` .. `ESCR_43` (claim), `ESCR_50` .. `ESCR_52` (sweep), `ESCR_53` .. `ESCR_58` (directTransferToEscrow) | partially proven | reached by the matching single-action entrypoints; no mutant |
| `ESCR_01`, `ESCR_02`, `ESCR_60` .. `ESCR_64` (global balance bound, module register/deactivate accounting), `ESCR_70` .. `ESCR_72` (multi-standard and residual coverage) | partially proven | global / module and coverage invariants; no mutant |

### AssetManager

- **Fuzz entrypoints reached:** `fuzz_setAsset`, `fuzz_setAssetUnauthorized`, `fuzz_setAssetTokenId`, `fuzz_setAssetTokenIdUnauthorized`, `fuzz_validateAsset`, `fuzz_validateAssetAsActor`.
- **Invariant families / IDs exercised:** `ASET_01`, `ASET_02` (views), `ASET_10` .. `ASET_15` (setAsset), `ASET_20` .. `ASET_24` (setAssetTokenId), `ASET_30` .. `ASET_33` (validateAsset), `ASET_40` .. `ASET_42` (authorization).
- **Validation command:** `npm run echidna-fast` (composite, recorded clean); `npm run medusa-fast` for selector/compile parity (not recorded).
- **Corpus / coverage evidence:** composite baseline only; no per-harness coverage or corpus artifact archived.
- **Mutants killed:** none recorded. Listed in the Baseline note above as a family with no mutation-validation batch yet.
- **Evidence status:**

| Family group | Status | Note |
| --- | --- | --- |
| `ASET_10` .. `ASET_15` (setAsset fields / allowlist preservation / revert predicates), `ASET_20` .. `ASET_24` (setAssetTokenId) | partially proven | reached by `fuzz_setAsset` / `fuzz_setAssetTokenId`; no mutant |
| `ASET_30` .. `ASET_33` (validateAsset success/revert/no-mutation/return type) | partially proven | reached by `fuzz_validateAsset` / `fuzz_validateAssetAsActor`; no mutant |
| `ASET_01`, `ASET_02` (view consistency), `ASET_40` .. `ASET_42` (non-admin rejection / no-mutation) | partially proven | global / authorization invariants; no mutant |

### EscrowAuth

- **Fuzz entrypoints reached:** `fuzz_registerModule`, `fuzz_registerModuleUnauthorized`, `fuzz_deactivateModule`, `fuzz_deactivateModuleUnauthorized`, `fuzz_setAssetManager`, `fuzz_setAssetManagerUnauthorized`, `fuzz_createEscrowAsActor`, `fuzz_withdrawAsActor`, `fuzz_claimAsActor`, `fuzz_sweep`, `fuzz_sweepUnauthorized`.
- **Invariant families / IDs exercised:** `ESAU_01`, `ESAU_02` (global), `ESAU_10` .. `ESAU_13` (registerModule), `ESAU_20` .. `ESAU_23` (deactivateModule), `ESAU_30` .. `ESAU_34` (setAssetManager and restore), `ESAU_40` .. `ESAU_42` (createEscrow from unregistered caller), `ESAU_50` .. `ESAU_52` (withdraw/claim unauthorized), `ESAU_60`, `ESAU_61` (sweep), `ESAU_70` .. `ESAU_72` (admin gate).
- **Validation command:** `npm run echidna-fast` (composite, recorded clean); `npm run medusa-fast` for selector/compile parity (not recorded).
- **Corpus / coverage evidence:** composite baseline only; no per-harness coverage or corpus artifact archived.
- **Mutants killed:** none recorded. Listed in the Baseline note above as a family with no mutation-validation batch yet.
- **Evidence status:**

| Family group | Status | Note |
| --- | --- | --- |
| `ESAU_10` .. `ESAU_13` (registerModule), `ESAU_20` .. `ESAU_23` (deactivateModule), `ESAU_30` .. `ESAU_34` (setAssetManager and restore) | partially proven | reached by the module/admin mutator entrypoints; no mutant |
| `ESAU_40` .. `ESAU_42` (unregistered createEscrow), `ESAU_50` .. `ESAU_52` (unauthorized withdraw/claim), `ESAU_60`, `ESAU_61` (sweep), `ESAU_70` .. `ESAU_72` (admin gate) | partially proven | reached by the authorization-check entrypoints; no mutant |
| `ESAU_01`, `ESAU_02` (authorization-matrix consistency) | partially proven | global invariants; no mutant |

### Requirement coverage map (RQ_SEC_FUZZ)

| `RQ_SEC_FUZZ` requirement clause | Harness(es) | Representative IDs | Status |
| --- | --- | --- | --- |
| Token: total-supply / per-id-supply invariants, pause behavior | `DEUSSToken` | `SPLY_01` .. `SPLY_05`, `TKN_60` .. `TKN_63`, `PAUS_01` | partially proven (no mutant) |
| EntityRegistry: account-role consistency, status transitions | `EntityRegistry` | `ER_30`, `ER_31` (link), `ER_20`, `ER_40` (status); new pending/admin registration IDs `ER_92` .. `ER_107`, `ER_110` .. `ER_115` | proven core (Batch 1); `ER_01` and legacy remainder partially proven; new pending/admin registration surface implemented but campaign/mutant proof pending |
| BondRegistry: lifecycle publish → suspend → unsuspend → cancel/close | `BondRegistry` | `BOND_10` .. `BOND_16`, `BOND_35`, `BOND_36`, `BOND_50` .. `BOND_53`, `BOND_60` .. `BOND_66`, `BOND_70` .. `BOND_73` | partially proven (no mutant) |
| PolicyRegistry: policy version monotonicity | `PolicyRegistry` | `PR_70` .. `PR_72` | unproven — invariant implemented (`fuzz_advancePolicyVersionResetsState`) and reached under `echidna-fast` (`2026-06-01`); a handler false-positive was fixed; clean re-run + mutant kill pending |
| Marketplace (InterestDiscovery + EscrowManager): asset conservation | `Marketplace`, `EscrowManager` | `OFER_01`, `ESCR_01`, `ESCR_02`, accounting `OFER_10` .. `OFER_21`, `DEAL_01` .. `DEAL_51`, `ESCR_10` .. `ESCR_24` | accounting proven (Batches 2–3); global bounds partially proven |
| Marketplace: freeze/seize correctness | `Marketplace` | `OFER_60` .. `OFER_64`, `DEAL_64` .. `DEAL_67` | unproven (no mutant; directed-only) |
| Marketplace: dispute resolution invariants | `Marketplace` | `DEAL_60` .. `DEAL_63` | unproven (no mutant; directed-only) |

## Batch 1: EntityRegistry invariants

This first batch focuses on EntityRegistry because the harness surface is already present and the mutants can be kept narrow. For these ten entries, the clean rerun column refers to the restored-source rerun captured by the baseline above.

| Invariant | Statement | Reachability path | Mutant | Mutant result | Test date | Clean rerun | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `ER_20` | `setEntityStatus` writes the requested entity status | `fuzz_setEntityStatus -> handler_setEntityStatus -> setEntityStatusPostconditions` | In `src/registry/EntityRegistry.sol`, forced `_setEntityStatus` to always write `EntityStatus.DISABLED` | Killed by `fuzz_setEntityStatus`; assertion `ER-20: setEntityStatus updates the entity status to the requested value` | 2026-04-23 | Clean rerun passed | `proven` |
| `ER_30` | `requestAccountRegistration` plus `acceptAccountRegistration` links the wallet to the selected entity and marks it enabled/registered | `fuzz_registerAccount -> handler_registerAccount -> registerAccountPostconditions` | In `test/fuzzing/helper/handlers/HandlerEntityRegistry.sol`, immediately called `removeAccount` after a successful account-registration lifecycle | Killed by `fuzz_registerAccount`; assertion `ER-30: Accepted account registration sets status to ENABLED and links it to the correct entity` | 2026-04-23 | Clean rerun passed | `proven` |
| `ER_31` | `requestAccountRegistration` plus `acceptAccountRegistration` increments entity account count by one | `fuzz_registerAccount -> handler_registerAccount -> registerAccountPostconditions` | In `test/fuzzing/helper/handlers/HandlerEntityRegistry.sol`, registered one extra wallet after the intended account-registration lifecycle | Killed by `fuzz_registerAccount`; assertion `ER-31: Accepted account registration appends it to the entity accounts array` | 2026-04-23 | Clean rerun passed | `proven` |
| `ER_40` | `setAccountStatus` writes the requested account status | `fuzz_setAccountStatus -> handler_setAccountStatus -> setAccountStatusPostconditions` | In `src/registry/EntityRegistry.sol`, forced `setAccountStatus` to always write `AccountStatus.DISABLED` | Killed by `fuzz_setAccountStatus`; assertion `ER-40: setAccountStatus updates the account status to the requested value` | 2026-04-23 | Clean rerun passed | `proven` |
| `ER_50` | `removeAccount` clears account registration | `fuzz_removeAccount -> handler_removeAccount -> removeAccountPostconditions` | In `src/registry/EntityRegistry.sol`, removed the final `delete _accounts[account]` effect from `_removeAccount` | Killed by `fuzz_removeAccount`; assertion `ER-50: removeAccount clears the account record (status becomes NONE)` | 2026-04-23 | Clean rerun passed | `proven` |
| `ER_51` | `removeAccount` decrements the source entity account count by one | `fuzz_removeAccount -> handler_removeAccount -> removeAccountPostconditions` | In `src/registry/EntityRegistry.sol`, skipped `_removeAccountFromEntity` inside `_removeAccount` | Killed by `fuzz_removeAccount`; assertion `ER-51: removeAccount decrements the entity accounts array length by one` | 2026-04-23 | Clean rerun passed | `proven` |
| `ER_60` | `transferAccountToEntity` relinks the wallet to the destination entity | `fuzz_transferAccountToEntity -> handler_transferAccountToEntity -> transferAccountPostconditions` | In `src/registry/EntityRegistry.sol`, removed `accountRecord.entityId = newEntityId` | Killed by `fuzz_transferAccountToEntity`; assertion `ER-60: transferAccountToEntity links the account to the new entity` | 2026-04-23 | Clean rerun passed | `proven` |
| `ER_61` | `transferAccountToEntity` decrements the old entity account count by one | `fuzz_transferAccountToEntity -> handler_transferAccountToEntity -> transferAccountPostconditions` | In `src/registry/EntityRegistry.sol`, skipped `_removeAccountFromEntity(oldEntityId, account)` | Killed by `fuzz_transferAccountToEntity`; assertion `ER-61: transferAccountToEntity removes the account from the old entity accounts array` | 2026-04-23 | Clean rerun passed | `proven` |
| `ER_62` | `transferAccountToEntity` increments the new entity account count by one | `fuzz_transferAccountToEntity -> handler_transferAccountToEntity -> transferAccountPostconditions` | In `src/registry/EntityRegistry.sol`, skipped `_addAccountToEntity(newEntityId, account)` | Killed by `fuzz_transferAccountToEntity`; assertion `ER-62: transferAccountToEntity appends the account to the new entity accounts array` | 2026-04-23 | Clean rerun passed | `proven` |
| `ER_70` | `setEntityManager` applies the requested manager flag | `fuzz_setEntityManager -> handler_setEntityManager -> setEntityManagerPostconditions` | In `src/registry/EntityRegistry.sol`, wrote `!enabled` instead of `enabled` | Killed by `fuzz_setEntityManager`; assertion `ER-70: setEntityManager sets the manager flag to the requested value` | 2026-04-23 | Clean rerun passed | `proven` |

## Batch 2: Marketplace and escrow invariants

This batch focuses on high-reach offer, deal, and escrow-accounting assertions. For these ten entries, the clean rerun column refers to the restored-source rerun captured by the baseline above.

| Invariant | Statement | Reachability path | Mutant | Mutant result | Test date | Clean rerun | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `OFER_20` | `acceptOffer` moves the accepted amount from available into inDeals | `fuzz_acceptOffer -> handler_acceptOffer -> acceptOfferPostconditions` | In `src/marketplace/Marketplace.sol`, changed `currentOffer.amounts.inDeals += amount` to `+= 0` | Killed by `fuzz_acceptOffer`; assertion `OFER-20: Accepting an offer moves amount from available into inDeals` | 2026-04-23 | Clean rerun passed | `proven` |
| `DEAL_01` | `acceptOffer` creates a pending deal with the expected offer, buyer, amount, and status | `fuzz_acceptOffer -> handler_acceptOffer -> acceptOfferPostconditions` | In `src/marketplace/Marketplace.sol`, changed `_createOfferDeal` status from `PENDING` to `PROPOSED` | Killed by `fuzz_acceptOffer`; assertion `DEAL-01: Accepting an offer creates a pending deal with expected fields` | 2026-04-23 | Clean rerun passed | `proven` |
| `DEAL_02` | `acceptOffer` increments the deal counter by one | `fuzz_acceptOffer -> handler_acceptOffer -> acceptOfferPostconditions` | In `src/marketplace/Marketplace.sol`, added an extra `counters.dealCounter` increment in `_createDeal` after loading `_countersStorage()` | Killed by `fuzz_acceptOffer`; assertion `DEAL-02: Accepting an offer increments the deal counter by one` | 2026-04-23 | Clean rerun passed | `proven` |
| `OFER_21` | `cancelOffer` marks the offer cancelled and zeroes available | `fuzz_cancelOffer -> handler_cancelOffer -> cancelOfferPostconditions`; failed-book seller/operator cancellation handlers reuse this invariant through `cancelFailedInterestOfferPostconditions` | In `src/marketplace/Marketplace.sol`, wrote `_offerCancelled[offerId] = false` during cancellation | Killed by `fuzz_cancelOffer`; assertion `OFER-21: Cancelling an offer marks it cancelled and zeroes available` | 2026-04-23 | Clean rerun passed | `proven` |
| `ESCR_12` | `cancelOffer` withdraws the previously available amount from escrow | `fuzz_cancelOffer -> handler_cancelOffer -> cancelOfferPostconditions`; failed-book seller/operator cancellation handlers cover escrow shrink via `ESCR_14` | In `src/marketplace/EscrowManager.sol`, changed `_transferFromEscrow` so it transfers out but does not decrement `escrow.amount` | Killed by `fuzz_cancelOffer`; assertion `ESCR-12: Cancelling an offer withdraws its previously available amount` | 2026-04-23 | Clean rerun passed | `proven` |
| `DEAL_50` | `resolveCounterOffer(true)` converts the proposal into a pending marketplace deal | `fuzz_resolveCounterOffer -> handler_resolveCounterOffer -> resolveCounterOfferPostconditions` | In `src/marketplace/Marketplace.sol`, changed the accepted counter-offer status from `PENDING` to `PROPOSED` | Killed by `fuzz_resolveCounterOffer`; assertion `DEAL-50: resolveCounterOffer(true) converts the proposal into a pending marketplace deal` | 2026-04-23 | Clean rerun passed | `proven` |
| `DEAL_51` | `resolveCounterOffer(false)` marks the proposal declined and clears the counter-offer expiry | `fuzz_resolveCounterOffer -> handler_resolveCounterOffer -> resolveCounterOfferPostconditions` | In `src/marketplace/Marketplace.sol`, changed the declined counter-offer status from `DECLINED` to `CANCELLED` | Killed by `fuzz_resolveCounterOffer`; assertion `DEAL-51: resolveCounterOffer(false) marks the proposal declined and clears the counter-offer expiry` | 2026-04-23 | Clean rerun passed | `proven` |
| `DEAL_10` | `resolvePayment(true)` marks the selected deal as paid | `fuzz_resolvePayment -> handler_resolvePayment -> resolvePaymentPostconditions` | In `src/marketplace/Marketplace.sol`, changed the paid branch to write `UNPAID` | Killed by `fuzz_resolvePayment`; assertion `DEAL-10: resolvePayment marks the selected deal as PAID` | 2026-04-23 | Clean rerun passed | `proven` |
| `DEAL_20` | `settleDeal` marks the selected deal with the terminal outcome (`SUCCESSFUL` for enabled-buyer `PAID`, `UNSUCCESSFUL` for `UNPAID`) | `fuzz_settleDeal -> handler_settleDeal -> settleDealPostconditions` | In `src/marketplace/Marketplace.sol`, left the deal in its original paid/unpaid status instead of setting a terminal outcome | Killed by `fuzz_settleDeal`; assertion `DEAL-20: settleDeal marks the selected deal with its terminal outcome` | 2026-04-23 | Clean rerun passed | `proven` |
| `DEAL_21` | enabled-buyer paid `settleDeal` increases buyer balance by the settled amount | `fuzz_settleDeal -> handler_settleDeal -> settleDealPostconditions` | In `src/marketplace/Marketplace.sol`, removed the escrow `claim` call from the paid settlement branch | Killed by `fuzz_settleDeal`; assertion `DEAL-21: settleDeal increases buyer balance by the settled amount` | 2026-04-23 | Clean rerun passed | `proven` |

## Batch 3: Registration, escrow creation, and counter-offer invariants

This batch covers offer registration initialization, escrow creation accounting, and counter-offer creation/cancellation. For these entries, the clean rerun column refers to the restored-source rerun captured by the baseline above.

| Invariant | Statement | Reachability path | Mutant | Mutant result | Test date | Clean rerun | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `OFER_10` | registering an offer stores the expected offer fields | `fuzz_registerMarketplaceOffer/fuzz_registerRedemptionOffer/fuzz_registerInterestOffer -> handler_register*Offer -> registerOfferPostconditions` | In `src/marketplace/Marketplace.sol`, set `_offers[offerId].amounts.available = 0` immediately after storing `validatedOffer` | Killed by register-offer entrypoints; assertion `OFER-10: Registering an offer stores the expected offer fields` | 2026-04-23 | Clean rerun passed | `proven` |
| `OFER_11` | registering an offer increments the offer counter by one | `fuzz_registerMarketplaceOffer/fuzz_registerRedemptionOffer/fuzz_registerInterestOffer -> handler_register*Offer -> registerOfferPostconditions` | In `src/marketplace/Marketplace.sol`, added an extra `counters.offerCounter` increment after allocating `offerId` through `_countersStorage()` | Killed by register-offer entrypoints; assertion `OFER-11: Registering an offer increments the offer counter by one` | 2026-04-23 | Clean rerun passed | `proven` |
| `OFER_12` | registering an offer decreases seller balance by the deposited amount | `fuzz_registerMarketplaceOffer/fuzz_registerRedemptionOffer/fuzz_registerInterestOffer -> handler_register*Offer -> registerOfferPostconditions` | In `src/marketplace/EscrowManager.sol`, transferred the escrowed amount back to the depositor after `_transferToEscrow` | Killed by register-offer entrypoints; assertion `OFER-12: Registering an offer decreases seller balance by the deposited amount` | 2026-04-23 | Clean rerun passed | `proven` |
| `ESCR_10` | registering an offer creates a linked escrow | `fuzz_registerMarketplaceOffer/fuzz_registerRedemptionOffer/fuzz_registerInterestOffer -> handler_register*Offer -> registerOfferPostconditions` | In `src/marketplace/Marketplace.sol`, set `_escrowIdByOfferId[offerId] = 0` after the escrow id consistency check | Killed by register-offer entrypoints; assertion `ESCR-10: Registering an offer creates a linked escrow` | 2026-04-23 | Clean rerun passed | `proven` |
| `ESCR_11` | registering an offer funds escrow with the deposited amount | `fuzz_registerMarketplaceOffer/fuzz_registerRedemptionOffer/fuzz_registerInterestOffer -> handler_register*Offer -> registerOfferPostconditions` | In `src/marketplace/EscrowManager.sol`, stored `amount - 1` in the escrow record | Killed by register-offer entrypoints; assertion `ESCR-11: Registering an offer funds escrow with the deposited amount` | 2026-04-23 | Clean rerun passed | `proven` |
| `ESCR_20` | `createEscrow` stores the expected escrow fields | `fuzz_createEscrow -> handler_createEscrow -> createEscrowPostconditions` | In `src/marketplace/EscrowManager.sol`, stored `amount - 1` in the escrow record | Killed by `fuzz_createEscrow`; assertion `ESCR-20: createEscrow stores the expected escrow fields` | 2026-04-23 | Clean rerun passed | `proven` |
| `ESCR_21` | `createEscrow` increments `nextEscrowId` by one | `fuzz_createEscrow -> handler_createEscrow -> createEscrowPostconditions` | In `src/marketplace/EscrowManager.sol`, added an extra `++nextEscrowId` after allocating the escrow id | Killed by `fuzz_createEscrow`; assertion `ESCR-21: createEscrow increments nextEscrowId by one` | 2026-04-23 | Clean rerun passed | `proven` |
| `ESCR_22` | `createEscrow` increases EscrowManager balance by the deposited amount | `fuzz_createEscrow -> handler_createEscrow -> createEscrowPostconditions` | In `src/marketplace/EscrowManager.sol`, transferred the escrowed amount back to the depositor after `_transferToEscrow` | Killed by `fuzz_createEscrow`; assertion `ESCR-22: createEscrow increases EscrowManager balance by the deposited amount` | 2026-04-23 | Clean rerun passed | `proven` |
| `ESCR_24` | `createEscrow` increases reserved balance by the deposited amount | `fuzz_createEscrow -> handler_createEscrow -> createEscrowPostconditions` | In `src/marketplace/EscrowManager.sol`, skipped the reserved balance increment by changing it to `+= 0` in `_transferToEscrow` | Killed by `fuzz_createEscrow`; assertion `ESCR-24: createEscrow increases reserved balance by the deposited amount` | 2026-04-23 | Clean rerun passed | `proven` |
| `DEAL_30` | `createCounterOffer` creates a proposed counter-offer deal with expected fields | `fuzz_createCounterOffer -> handler_createCounterOffer -> createCounterOfferPostconditions` | In `src/marketplace/Marketplace.sol`, changed the counter-offer deal status from `PROPOSED` to `PENDING` | Killed by `fuzz_createCounterOffer`; assertion `DEAL-30: createCounterOffer creates a proposed counter-offer deal with expected fields` | 2026-04-23 | Clean rerun passed | `proven` |
| `DEAL_40` | `cancelCounterOffer` marks the selected deal as `CANCELLED` | `fuzz_cancelCounterOffer -> handler_cancelCounterOffer -> cancelCounterOfferPostconditions` | In `src/marketplace/Marketplace.sol`, wrote `DECLINED` instead of `CANCELLED` during counter-offer cancellation | Killed by `fuzz_cancelCounterOffer`; assertion `DEAL-40: cancelCounterOffer marks the selected deal as CANCELLED` | 2026-04-23 | Clean rerun passed | `proven` |

## Notes

- Do not mark an invariant as proven if the failure came from an unrelated revert path.
- Do not mark an invariant as proven if the relevant production branch remains uncovered.
- For now, each proof records the minimal mutant inline in this ledger rather than keeping a permanent mutant branch.
