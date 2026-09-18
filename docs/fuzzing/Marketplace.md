# Marketplace Fuzz Coverage

Vertical entrypoint: [`test/fuzzing/FuzzMarketplaceIntegrity.sol`](../../test/fuzzing/FuzzMarketplaceIntegrity.sol)

Directed lifecycle entrypoint: [`test/fuzzing/FuzzMarketplaceLifecycle.sol`](../../test/fuzzing/FuzzMarketplaceLifecycle.sol)

Invariants:
- Marketplace directed coverage: [`test/fuzzing/properties/Properties_MKT.sol`](../../test/fuzzing/properties/Properties_MKT.sol)
- Offer-side: [`test/fuzzing/properties/Properties_OFFER.sol`](../../test/fuzzing/properties/Properties_OFFER.sol)
- Deal-side: [`test/fuzzing/properties/Properties_DEAL.sol`](../../test/fuzzing/properties/Properties_DEAL.sol)
- Interest-side: [`test/fuzzing/properties/Properties_INTEREST.sol`](../../test/fuzzing/properties/Properties_INTEREST.sol)
- Offer-linked escrow: [`test/fuzzing/properties/Properties_ESCROW.sol`](../../test/fuzzing/properties/Properties_ESCROW.sol) (ESCR-10..16, ESCR-40..42)

Descriptions: [`test/fuzzing/properties/PropertiesDescriptions.sol`](../../test/fuzzing/properties/PropertiesDescriptions.sol)

## Scope

End-to-end exercise of the [`Marketplace`](../marketplace/Marketplace.md) marketplace flow: marketplace offers, redemption offers, interest-discovery offers, interest expression, activation, expired-interest closeout, failed-book cancellation, counter-offer negotiation, counter-offer cap configuration, single-item and batched payment resolution, dispute arbitration, freeze/unfreeze controls, single and batched settlement, seizure, and owner-side inventory withdrawal. Each action that moves bond tokens is routed through the linked `EscrowManager` escrow, so the offer-linked half of the escrow invariants is exercised from this vertical.

The harness uses `FuzzStateIndex` buckets to select tracked offers, deals, and interests by lifecycle state. Time-derived bucket pickers refresh the bounded tracked ID set before selection so timestamp-only transitions such as expired offers, closeable interests, pending-expired deals, and settleable deals become reachable after the fuzzer advances time.

The sibling `FuzzMarketplaceLifecycle` campaign keeps the broad `Fuzz` campaign unchanged and focuses on sparse Marketplace branches. Its handlers build realistic short prefixes with public protocol calls, warp only to deadlines read from the touched offer or deal, sync the touched objects, and then call the same transition flows used by the main harness.

## Handlers

| Entrypoint | Caller | Target | Purpose |
|---|---|---|---|
| `fuzz_registerMarketplaceOffer` | `currentActor` | `marketplace.registerOffer` | Create an unrestricted marketplace offer and fund escrow |
| `fuzz_registerRedemptionOffer` | `currentActor` | `marketplace.registerOffer` | Create a redemption offer with an allowlisted buyer set |
| `fuzz_registerInterestOffer` | `currentActor` | `marketplace.registerOffer` | Create an interest-discovery offer |
| `fuzz_setMaxCounterOffersPerUser` | harness admin | `marketplace.setMaxCounterOffersPerUser` | Update or reject the per-user counter-offer cap |
| `fuzz_acceptOffer` | `currentActor` | `marketplace.acceptOffer` | Accept a tracked marketplace or redemption offer and open a pending deal |
| `fuzz_expressInterest` | `currentActor` | `marketplace.expressInterest` | Reserve inventory on a tracked interest-discovery offer |
| `fuzz_expressInterestBelowThreshold` | `currentActor` | `marketplace.expressInterest` | Reserve inventory while keeping an interest-discovery offer below threshold |
| `fuzz_activateInterest` | recorded seller | `marketplace.activateInterest` | Convert an expressed interest into a pending deal |
| `fuzz_closeExpiredInterest` | recorded seller | `marketplace.closeExpiredInterests` | Close one expired expressed interest |
| `fuzz_closeExpiredInterestsBatch` | recorded seller | `marketplace.closeExpiredInterests` | Close two or three expired expressed interests for the same offer |
| `fuzz_withdrawAvailable` | recorded seller | `marketplace.withdrawAvailable` | Reclaim available inventory from a cancelled direct-sale offer |
| `fuzz_withdrawInterestAvailable` | recorded seller | `marketplace.withdrawAvailable` | Reclaim available inventory from an expired successful interest-discovery offer |
| `fuzz_withdrawInterestAvailableBelowThreshold` | recorded seller | `marketplace.withdrawAvailable` | Prove failed-book withdrawal is rejected in favor of cancellation |
| `fuzz_cancelFailedInterestOffer` | recorded seller | `marketplace.cancelOffer` | Cancel an expired interest-discovery offer whose threshold was not reached |
| `fuzz_cancelFailedInterestOfferByOperator` | harness interest-discovery operator | `marketplace.cancelOffer` | Cancel an expired failed interest-discovery offer through the operator role |
| `fuzz_createCounterOffer` | `currentActor` | `marketplace.createCounterOffer` | Propose a counter-offer deal against a marketplace offer |
| `fuzz_cancelOffer` | `currentActor` | `marketplace.cancelOffer` | Cancel a direct-sale offer owned by the current actor |
| `fuzz_cancelCounterOffer` | recorded buyer | `marketplace.cancelCounterOffer` | Cancel a proposed counter-offer as its buyer |
| `fuzz_resolveCounterOffer` | recorded seller | `marketplace.resolveCounterOffer` | Accept or decline a counter-offer as the original seller |
| `fuzz_resolvePayment` | harness payment handler | `marketplace.resolvePayment` | Mark a deal PAID or UNPAID |
| `fuzz_resolvePayments` | harness payment handler | `marketplace.resolvePayments` | Resolve one paid item and one expired unpaid item through the batch surface |
| `fuzz_resolvePaymentsDuplicateUnpaid` | `currentActor` without `PAYMENT_HANDLER` | `marketplace.resolvePayments` | Prove unpaid-only batches are permissionless and tolerate a skipped duplicate item |
| `fuzz_resolvePaymentsExpiredPaid` | harness payment handler | `marketplace.resolvePayments` | Prove a paid batch item is skipped cleanly once its pending deal has expired |
| `fuzz_resolvePaymentsUnauthorized` | unauthorized fixed caller | `marketplace.resolvePayments` | Prove any batch containing a paid item rejects callers without `PAYMENT_HANDLER` before mutating deals |
| `fuzz_resolvePaymentUnauthorized` | unauthorized fixed caller | `marketplace.resolvePayment` | Prove `resolvePayment(true)` rejects callers without `PAYMENT_HANDLER` |
| `fuzz_initiateDispute` | recorded buyer | `marketplace.initiateDispute` | Move an unpaid deal inside its dispute window into dispute |
| `fuzz_resolveDispute` | harness arbitrator | `marketplace.resolveDispute` | Resolve an in-dispute deal as PAID or UNPAID |
| `fuzz_disputeResolutionFlow` | harness, then recorded buyer, then harness arbitrator | `resolvePayment(false)`, `initiateDispute`, `resolveDispute` | Deterministically cover the full unpaid dispute lifecycle from a pending deal |
| `fuzz_setOfferFrozen` | harness freezer | `marketplace.setOfferFrozen` | Freeze or unfreeze a tracked offer |
| `fuzz_setDealFrozen` | harness freezer | `marketplace.setDealFrozen` | Freeze or unfreeze a tracked deal |
| `fuzz_settleDeal` | harness | `marketplace.settleDeal` | Finalise an enabled-buyer PAID deal or timed-out UNPAID deal |
| `fuzz_settleDealsBatch` | harness | `marketplace.settleDeals` | Finalise two or three settleable deals in one batch |
| `fuzz_settleDealsMixedBatch` | harness | `marketplace.settleDeals` | Finalise one settleable deal while skipping one invalid deal in a mixed batch |
| `fuzz_seizeOfferEscrow` | harness seizure role | `marketplace.seizeOfferEscrow` | Seize non-deal escrow balance from a frozen offer |
| `fuzz_seizeOfferReservedInterest` | current actor, non-owner buyer, then harness freezer/seizure role | `registerOffer`, `expressInterest`, `setOfferFrozen`, `seizeOfferEscrow` | Create an interest-discovery offer, reserve interest, and cover the reserved-interest seizure branch |
| `fuzz_seizeDeal` | harness seizure role | `marketplace.seizeDeal` | Seize escrowed deal inventory from a frozen deal and frozen parent offer |
| `fuzz_seizePaidDeal` | current actor, non-owner buyer, then harness payment/freezer/seizure roles | `registerOffer`, `acceptOffer`, `resolvePayment(true)`, `setOfferFrozen`, `setDealFrozen`, `seizeDeal` | Create a direct-sale deal, mark it PAID, and cover the paid-deal seizure branch |
| `fuzz_marketplaceAdminSurface` | harness admin | Marketplace getters and admin setters | Exercise view helpers, configuration setters, currency allowlist updates, allowed entity-type updates, and idempotent dependency setters |

`currentActor` is set from `msg.sender`, so the fuzzer's sender choice drives buyer/seller roles. Handlers that must act as a recorded counterparty use that address explicitly.

## Directed Lifecycle Campaign

Config files:
- Echidna: [`echidna-interest-lifecycle.yaml`](../../echidna-interest-lifecycle.yaml)
- Medusa: [`medusa-interest-lifecycle.json`](../../medusa-interest-lifecycle.json)

Package scripts:
- `npm run echidna-interest-lifecycle-fast`
- `npm run echidna-interest-lifecycle`
- `npm run medusa-interest-lifecycle-fast`
- `npm run medusa-interest-lifecycle`

| Entrypoint | Target branch | Directed flow |
|---|---|---|
| `fuzz_directSaleResolveUnpaid` | `resolvePayment(false)` | Register a marketplace offer, accept a real deal, warp to `deal.paymentDeadline + 1`, sync the deal, then resolve unpaid |
| `fuzz_directSaleSettleUnpaid` | unpaid `settleDeal` | Build a direct pending deal, resolve unpaid, warp to `deal.disputeBuffer + 1`, sync deal and offer, then settle |
| `fuzz_directSaleWithdrawAfterUnpaidSettlement` | cancelled direct-sale `withdrawAvailable` after inventory returns | Build a direct pending deal, cancel the parent offer while `inDeals != 0`, resolve unpaid, settle after dispute buffer, then withdraw returned available inventory |
| `fuzz_interestDiscoveryCloseExpiredInterest` | single `closeExpiredInterests` with `releasedAmount != 0` | Register an interest-discovery offer, express enough interest to reach threshold, warp to `offer.expiry + paymentExpiryThreshold + 1` using the offer's snapshotted threshold, sync offer and known interests, then close one interest |
| `fuzz_interestDiscoveryCloseExpiredInterestsBatch` | batched `closeExpiredInterests` | Build at least two expressed interests for one threshold-reached offer, cross the activation deadline, sync touched objects, then close them in one call |
| `fuzz_interestDiscoveryWithdrawExpiredAvailable` | expired successful-book `withdrawAvailable` with leftover inventory | Register an interest-discovery offer with at least two lots, express the minimum threshold, enter the activation window, then withdraw the remaining available inventory |
| `fuzz_activatedInterestResolveUnpaid` | activated-interest `resolvePayment(false)` | Register an interest-discovery offer, express threshold-reaching interest, warp to `offer.expiry + 1`, activate it into a pending deal, then expire and resolve unpaid |
| `fuzz_activatedInterestSettleUnpaid` | activated-interest unpaid `settleDeal` | Build an activated-interest pending deal inside the post-sale activation window, resolve unpaid after payment deadline, then settle after dispute buffer |
| `fuzz_marketplaceNegativeValidationSurface` | wrong sale-mode and missing-interest reverts | Check `activateInterest(0)`, `acceptOffer` on an interest-discovery offer, and `expressInterest` on a direct marketplace offer against their expected selectors |

The equivalent Medusa directed command is `npm run medusa-interest-lifecycle-fast`; it uses `medusa-interest-lifecycle.json` and writes coverage under `medusa-interest-lifecycle-directed-corpus/coverage/`.

The lifecycle campaign does not expose standalone time-advance handlers. Every warp is local to the public lifecycle action that needs it and uses a live deadline from the exact offer or deal being transitioned.

## Invariants

### `registerOffer` - offer group 10

Checked in `registerOfferPostconditions`.

| ID | Condition | Checked |
|---|---|---|
| OFER-10 | Offer fields, sale mode, interest-discovery state, and redemption allowlist entries match input | on success |
| OFER-11 | Offer counter increments by exactly 1 | on success |
| OFER-12 | Seller bond balance shrinks by the deposited total | on success |
| OFER-13 | No unexpected reverts | on revert |
| ESCR-10 | A linked escrow is created for the new offer | on success |
| ESCR-11 | The linked escrow is funded with exactly the deposited total | on success |

### `expressInterest` - interest group 10

Checked in `expressInterestPostconditions`.

| ID | Condition | Checked |
|---|---|---|
| INTR-01 | `interestedUnits` never decreases across interest-discovery transitions | on success |
| INTR-10 | Expressed amount moves from `available` into `interestedUnits` and `reservedInterestUnits` | on success |
| INTR-11 | Interest record stores offer, amount, investor, price, and EXPRESSED status | on success |
| INTR-12 | Interest counter increments by exactly 1 | on success |
| INTR-13 | No unexpected reverts | on revert |

### `activateInterest` - interest group 20

Checked in `activateInterestPostconditions`.

| ID | Condition | Checked |
|---|---|---|
| INTR-01 | `interestedUnits` never decreases across activation | on success |
| INTR-20 | Reserved interest inventory moves into `inDeals` | on success |
| INTR-21 | Interest is marked ACTIVATED | on success |
| INTR-22 | A pending deal is created with expected buyer, amount, price, payment deadline, dispute buffer, status, and type | on success |
| INTR-23 | Deal counter increments by exactly 1 | on success |
| INTR-24 | No unexpected reverts | on revert |

### `closeExpiredInterests` - interest group 30

Checked in `closeExpiredInterestPostconditions` and `closeExpiredInterestsPostconditions`.

| ID | Condition | Checked |
|---|---|---|
| INTR-01 | `interestedUnits` never decreases across closeout | on success |
| INTR-30 | Each selected interest is marked CLOSED | on success |
| INTR-31 | Released amount leaves `reservedInterestUnits` and returns to `available` | on success |
| INTR-32 | No unexpected reverts | on revert |

### `withdrawAvailable` for expired interest-discovery offers - interest group 40

Checked in `withdrawInterestAvailablePostconditions`.

| ID | Condition | Checked |
|---|---|---|
| INTR-01 | `interestedUnits` never decreases across interest-discovery withdrawal or failed-book cancellation | on success |
| INTR-40 | Expired successful-book available inventory is cleared | on success |
| INTR-41 | No unexpected reverts | on revert |
| INTR-42 | Failed-book `withdrawAvailable` reverts with `ThresholdNotReached` | on revert |
| INTR-43 | Failed interest-discovery cancellation clears `reservedInterestUnits` | on success of seller or operator failed-book cancellation |
| OFER-51 | Seller bond balance grows by the withdrawn amount | on success |
| ESCR-14 | Linked escrow shrinks by the withdrawn amount | on success |

### Direct sale, counter-offer, payment, and settlement groups

The direct-sale and deal lifecycle assertions remain in the existing offer/deal groups:

| Area | IDs |
|---|---|
| `acceptOffer` | OFER-20, DEAL-01..03; `DEAL-01` checks buyer, amount, price, lot multiple, no self-dealing, sale-mode payment deadline, dispute buffer, status, and type |
| `withdrawAvailable` for cancelled direct-sale offers | OFER-50..52, ESCR-14 |
| `createCounterOffer` | OFER-40, DEAL-30..32 |
| `setMaxCounterOffersPerUser` | OFER-70..72 |
| `cancelOffer` | OFER-21..22, ESCR-12; `OFER-21` checks the cancelled flag, zero available inventory, and expiry latched to the cancellation timestamp |
| `cancelOffer` for failed interest-discovery offers | OFER-21..22, INTR-01, INTR-43, ESCR-12 |
| `cancelCounterOffer` | OFER-40, DEAL-40..41 |
| `resolveCounterOffer` | OFER-20, OFER-40, DEAL-50..52 |
| `resolvePayment` | DEAL-10..13 |
| `resolvePayments` | DEAL-14..18 |
| `settleDeal` | DEAL-20..23, OFER-30..31, ESCR-13, ESCR-15 |
| `settleDeals` | DEAL-20..24, OFER-30..34, ESCR-13, ESCR-15..16 |

### Dispute, freeze, and seizure groups

The newly reachable dispute/freeze/seizure surface is checked by the following groups. The single-action handlers keep the public production functions individually reachable; the flow handlers compact narrow state chains so the dispute success path, reserved-interest seizure branch, and paid-deal seizure branch are not dependent on random transaction ordering.

| Area | IDs |
|---|---|
| `initiateDispute` | DEAL-60..61, OFER-40 |
| `resolveDispute` | DEAL-62..63, OFER-40 |
| `setOfferFrozen` | OFER-60..61, OFER-40 |
| `setDealFrozen` | DEAL-64..65, OFER-40 |
| `seizeOfferEscrow` | OFER-62, OFER-64, INTR-01, ESCR-40..42 |
| `seizeDeal` | DEAL-66..67, OFER-63, ESCR-40..42 |

The dispute/freeze/seizure groups use field-specific assertion labels in `PropertiesDescriptions.sol` so counterexamples identify the exact mismatched field. For example, `OFER-62.available` distinguishes failed escrow-clear accounting from `OFER-62.reservedInterestSeized`, and `DEAL-66.status` distinguishes a missing `SEIZED` transition from preserved-field mismatches such as `DEAL-66.offerId` or `DEAL-66.price`.

Freeze-sensitive lifecycle buckets exclude frozen offers/deals from normal progression handlers that production blocks (`acceptOffer`, `cancelOffer`, counter-offer actions, `activateInterest`, `withdrawAvailable`, and `settleDeal`). Dispute and payment buckets intentionally remain reachable while frozen, matching production behavior where freeze does not pause deadlines or arbitration.

For the batched payment surface:

- `DEAL-14` checks that a mixed batch applies the expected PAID and UNPAID statuses to the selected deals.
- `DEAL-15` checks that unpaid-only batches remain permissionless and that a duplicated deal id is skipped cleanly after the first item succeeds.
- `DEAL-16` checks that any batch containing a paid item reverts for callers without `PAYMENT_HANDLER` before mutating the targeted deals.
- `DEAL-17` checks that `resolvePayments` does not unexpectedly revert when preconditions supply a valid batch shape.
- `DEAL-18` checks that a paid batch item whose pending deal has already expired is skipped cleanly without mutating the deal.

### Cross-cutting invariants

These are re-evaluated after every successful Marketplace action through `onSuccessInvariantsGeneral`.

| ID | Condition |
|---|---|
| OFER-01 | For every tracked offer, `available + inDeals + sold <= total` |
| ESCR-01 | `EscrowManager` bond balance equals tracked escrow amounts plus sweepable surplus |
| ESCR-02 | Each tracked offer-linked escrow equals the expected holdings for its sale mode |
| ESCR-60 | `escrowBalance >= escrowReserved` |
| SPLY-01 | Total supply of the bond token equals the sum of tracked balances |
| SPLY-02 | Total supply never exceeds the initial issued supply |
| PAUS-01 | Bond status and token pause state stay aligned for the fuzzed bond token id |

### Directed Marketplace coverage

| ID | Condition |
|---|---|
| MKT-80 | Marketplace admin and view coverage calls do not unexpectedly revert |
| MKT-81 | `setBondRegistry` only reverts when the registry is already set |
| MKT-82 | Directed Marketplace defensive-branch coverage reverts with the expected selector |

## Preconditions

The harness initializes Marketplace timing from `DeployConstants.sol`: direct payment expiry is 4 days, redemption payment expiry is 5 days, interest-discovery payment expiry is 4 days, offer expiry threshold is 1 day, and dispute buffer is 3 days. Orderbook is deployed with its production timing defaults for setup compatibility, but orderbook actions are outside this Marketplace vertical.

| Handler | Selection and clamp rules |
|---|---|
| `registerMarketplaceOffer` | Token not paused; bond status is `Issued`; current actor approved `EscrowManager`; free balance exists. `lot` and `total` are clamped to free balance and total is rounded to a lot multiple. Expiry uses a fixed delta within `[offerExpiryThreshold, maxOfferLifetime]`. |
| `registerRedemptionOffer` | Same deposit and expiry rules as marketplace registration; allowlist is all non-owner harness users and `allowCounterOffers` is always `false`. |
| `registerInterestOffer` | Same deposit and expiry rules as marketplace registration. `minSaleUnits` is clamped to `[1, min(5, totalAmount / lot)]` lots so campaigns can cover both one-interest threshold reachability and higher-threshold failed-book states. |
| `acceptOffer` | Picks `OfferBucket.MarketplaceOpen` not owned by `currentActor`; requires direct-sale mode, buyer allowlist eligibility, available inventory, non-zero lot, and unexpired offer. |
| `expressInterest` | Picks `OfferBucket.InterestDiscoveryOpen` not owned by `currentActor`; requires open interest-discovery offer with available inventory. |
| `expressInterestBelowThreshold` | Picks `OfferBucket.InterestDiscoveryOpen` not owned by `currentActor`; clamps the expressed amount so `interestedUnits + amount < minSaleUnits`. |
| `activateInterest` | Picks `InterestBucket.Activatable`; requires EXPRESSED interest, uncancelled interest-discovery offer, threshold reached, enabled investor/seller accounts, and the offer's snapshotted activation window still open. |
| `closeExpiredInterest` | Picks `InterestBucket.Closeable`; requires EXPRESSED interest, uncancelled interest-discovery offer, threshold reached, and the offer's snapshotted activation window closed. |
| `closeExpiredInterestsBatch` | Starts from `InterestBucket.Closeable`, then gathers one or two more closeable interests for the same offer. |
| `withdrawAvailable` | Token not paused; picks `OfferBucket.MarketplaceCancelledWithAvailable`; requires the recorded seller account to still be enabled, then pranks as that seller. |
| `withdrawInterestAvailable` | Token not paused; picks `OfferBucket.InterestDiscoveryExpiredWithdrawable`; requires an expired uncancelled interest-discovery offer with available or reserved withdrawable inventory and an enabled recorded seller account. |
| `withdrawInterestAvailableBelowThreshold` | Token not paused; picks `OfferBucket.InterestDiscoveryExpiredWithdrawable`; requires an expired uncancelled failed book with `interestedUnits < minSaleUnits`, non-zero `reservedInterestUnits`, and an enabled recorded seller account. |
| `cancelFailedInterestOffer` | Picks an expired uncancelled interest-discovery offer owned by an enabled recorded seller, requires `interestedUnits < minSaleUnits`, then calls `cancelOffer`. |
| `cancelFailedInterestOfferByOperator` | Same failed-book selection and enabled-recipient requirement, then calls `cancelOffer` from the harness `INTEREST_DISCOVERY_OPERATOR`. |
| `createCounterOffer` | Picks `OfferBucket.MarketplaceCounterable` not owned by `currentActor`; checks buyer eligibility and per-user counter-offer limit; uses a counter-offer expiry delta within `[offerExpiryThreshold, maxOfferLifetime]`. |
| `setMaxCounterOffersPerUser` | Harness admin calls the public setter directly. Non-zero caps must be stored; zero must revert with `Marketplace__MaxCounterOffersPerUserZero` and leave the existing cap unchanged. |
| `cancelOffer` | Picks `OfferBucket.MarketplaceCancellable` owned by `currentActor`; requires active tracked direct-sale balance. |
| `cancelCounterOffer` | Picks `DealBucket.ActiveCounterOffer`; prank uses the recorded buyer. |
| `resolveCounterOffer` | Picks `DealBucket.ActiveCounterOffer`; linked marketplace offer must exist and remain uncancelled; accepted resolutions require the parent offer to remain unexpired; prank uses the recorded seller. |
| `resolvePayment` | For `paid`, picks `DealBucket.Payable`; for `!paid`, picks `DealBucket.PendingExpired`. |
| `resolvePayments` | Picks one `DealBucket.Payable` deal and one `DealBucket.PendingExpired` deal, then resolves them in a single batch from the harness payment handler. |
| `resolvePaymentsDuplicateUnpaid` | Picks one `DealBucket.PendingExpired` deal, calls `resolvePayments` twice against the same deal from `currentActor`, and relies on the second item being skipped after the first turns the deal UNPAID. |
| `resolvePaymentsExpiredPaid` | Picks one `DealBucket.PendingExpired` deal, then calls `resolvePayments` with `paid = true` so the inner batch item hits `PaymentDeadlineExpired()` and is skipped by the outer try/catch loop. |
| `resolvePaymentsUnauthorized` | Picks one `DealBucket.PendingExpired` deal and one `DealBucket.Payable` deal, then calls `resolvePayments` from `FUZZ_PAYMENT_UNAUTH_CALLER` so the paid item triggers the top-level role gate before any item is processed. |
| `resolvePaymentUnauthorized` | Picks `DealBucket.Payable`, then calls `resolvePayment(true)` from a caller without `PAYMENT_HANDLER`. |
| `settleDeal` | Picks `DealBucket.Settleable`; PAID deals require an unpaused offer token and enabled buyer, and UNPAID deals require an expired dispute buffer. |
| `settleDealsBatch` | Starts from `DealBucket.Settleable`, then gathers one or two more settleable deals and verifies each selected deal reaches its terminal outcome (`SUCCESSFUL` for enabled-buyer `PAID`, `UNSUCCESSFUL` for `UNPAID`). |
| `settleDealsMixedBatch` | Starts from one invalid deal and one settleable deal, then verifies the invalid deal is skipped and the settleable deal reaches its terminal outcome (`SUCCESSFUL` for `PAID`, `UNSUCCESSFUL` for `UNPAID`). |
| `initiateDispute` | Picks `DealBucket.UnpaidDisputable`; prank uses the recorded buyer. |
| `resolveDispute` | Picks `DealBucket.InDispute`; the boolean seed maps to PAID or UNPAID. |
| `disputeResolutionFlow` | Picks `DealBucket.PendingPayable`, warps just past its payment deadline but still inside `disputeBuffer`, then runs `resolvePayment(false)`, `initiateDispute`, and `resolveDispute`. |
| `setOfferFrozen` | Picks `OfferBucket.Existing`; harness caller holds `FREEZE_ROLE`. |
| `setDealFrozen` | Picks `DealBucket.Existing`; harness caller holds `FREEZE_ROLE`. |
| `seizeOfferEscrow` | Token not paused; picks `OfferBucket.FrozenSeizable`; requires a frozen seizable offer, an enabled beneficiary, and non-zero reason. |
| `seizeDeal` | Token not paused; picks `DealBucket.FrozenSeizable`; requires a frozen seizable deal with a frozen parent offer, an enabled beneficiary, and non-zero reason. |
| `seizeOfferReservedInterest` | Creates a fresh interest-discovery offer with an enabled seller, switches to an enabled non-owner buyer to express one lot of interest, restores the seller actor, freezes the offer, then seizes the reserved-interest escrow bucket to an enabled beneficiary. |
| `seizePaidDeal` | Creates a fresh marketplace offer with an enabled seller, switches to an enabled non-owner buyer to accept one lot, restores the seller actor, resolves the deal PAID, freezes the parent offer and deal, then seizes that paid deal to an enabled beneficiary. |
| `marketplaceAdminSurface` | Calls read-only getters and admin setters with harness-owned roles, including allowed entity-type updates, expiry threshold setters, temporary currency add/remove, and the `setBondRegistry` already-set boundary. |

All clamp failures raise `ClampFail(string)`, which the integrity layer accepts as a skip rather than a bug.
