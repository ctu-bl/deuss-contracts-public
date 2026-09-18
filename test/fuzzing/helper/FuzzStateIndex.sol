// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, gas-strict-inequalities */

import {CommonHelpers} from "./CommonHelpers.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {
    Deal,
    DealStatus,
    DealType,
    Escrow,
    Interest,
    InterestDiscoveryState,
    InterestStatus,
    Offer,
    SaleMode
} from "src/marketplace/MarketStructs.sol";
import {EntityStatus} from "src/registry/EntityStructs.sol";

enum OfferBucket {
    Existing,
    MarketplaceOpen,
    MarketplaceCounterable,
    MarketplaceCancellable,
    MarketplaceCancelledWithAvailable,
    InterestDiscoveryExisting,
    InterestDiscoveryOpen,
    InterestDiscoveryExpiredWithdrawable,
    FrozenSeizable
}

enum DealBucket {
    Existing,
    ActiveCounterOffer,
    PendingPayable,
    Payable,
    PendingExpired,
    UnpaidDisputable,
    InDispute,
    Settleable,
    FrozenSeizable
}

enum InterestBucket {
    Expressed,
    Activatable,
    Closeable
}

enum EscrowBucket {
    FuzzTestFunded
}

enum EntityBucket {
    Existing,
    Enabled
}

enum FuzzEntityBucket {
    Existing
}

enum FuzzAccountBucket {
    Free,
    Registered
}

abstract contract FuzzStateIndex is CommonHelpers {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 internal constant OFFER_BUCKET_COUNT = 9;
    uint256 internal constant DEAL_BUCKET_COUNT = 9;
    uint256 internal constant INTEREST_BUCKET_COUNT = 3;
    uint256 internal constant ESCROW_BUCKET_COUNT = 1;
    uint256 internal constant ENTITY_BUCKET_COUNT = 2;
    uint256 internal constant FUZZ_ENTITY_BUCKET_COUNT = 1;
    uint256 internal constant FUZZ_STATE_INDEX_PICK_ATTEMPTS = MAX_TRACKED_ITEMS;

    /*//////////////////////////////////////////////////////////////
                            TRACKING HOOKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Adds a newly tracked offer to all lifecycle buckets it currently satisfies.
     */
    function _onOfferTracked(uint256 offerId) internal virtual override {
        _syncOffer(offerId);
    }

    /**
     * @dev Adds a newly tracked deal to all lifecycle buckets it currently satisfies.
     */
    function _onDealTracked(uint256 dealId) internal virtual override {
        _syncDeal(dealId);
    }

    /**
     * @dev Adds a newly tracked interest to all lifecycle buckets it currently satisfies.
     */
    function _onInterestTracked(uint256 interestId) internal virtual override {
        _syncInterest(interestId);
    }

    /**
     * @dev Adds a newly tracked escrow to all buckets it currently satisfies.
     */
    function _onEscrowTracked(uint256 escrowId) internal virtual override {
        _syncEscrow(escrowId);
    }

    /**
     * @dev Adds a newly tracked entity to all registry-state buckets it currently satisfies.
     */
    function _onEntityTracked(bytes32 entityId) internal virtual override {
        _syncEntity(entityId);
    }

    /**
     * @dev Adds a newly tracked fuzz-created entity to its dedicated bucket.
     */
    function _onFuzzEntityTracked(bytes32 entityId) internal virtual override {
        _syncFuzzEntity(entityId);
    }

    /**
     * @dev Removes an evicted offer from every offer bucket.
     */
    function _onOfferEvicted(uint256 offerId) internal virtual override {
        _removeOfferFromFuzzStateIndex(offerId);
    }

    /**
     * @dev Removes an evicted deal from every deal bucket.
     */
    function _onDealEvicted(uint256 dealId) internal virtual override {
        _removeDealFromFuzzStateIndex(dealId);
    }

    /**
     * @dev Removes an evicted interest from every interest bucket.
     */
    function _onInterestEvicted(uint256 interestId) internal virtual override {
        _removeInterestFromFuzzStateIndex(interestId);
    }

    /**
     * @dev Removes an evicted escrow from every escrow bucket.
     */
    function _onEscrowEvicted(uint256 escrowId) internal virtual override {
        _removeEscrowFromFuzzStateIndex(escrowId);
    }

    /**
     * @dev Removes an evicted entity from every entity bucket.
     */
    function _onEntityEvicted(bytes32 entityId) internal virtual override {
        _removeEntityFromFuzzStateIndex(entityId);
    }

    /**
     * @dev Removes an evicted fuzz-created entity from every fuzz-entity bucket.
     */
    function _onFuzzEntityEvicted(bytes32 entityId) internal virtual override {
        _removeFuzzEntityFromFuzzStateIndex(entityId);
    }

    /*//////////////////////////////////////////////////////////////
                          BUCKET MAINTENANCE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Adds or removes an offer ID from one offer lifecycle bucket.
     */
    function _setOfferBucket(uint256 offerId, OfferBucket bucket, bool inBucket) internal {
        EnumerableSet.UintSet storage s = offerBuckets[uint256(bucket)];
        if (inBucket) s.add(offerId);
        else s.remove(offerId);
    }

    /**
     * @dev Adds or removes a deal ID from one deal lifecycle bucket.
     */
    function _setDealBucket(uint256 dealId, DealBucket bucket, bool inBucket) internal {
        EnumerableSet.UintSet storage s = dealBuckets[uint256(bucket)];
        if (inBucket) s.add(dealId);
        else s.remove(dealId);
    }

    /**
     * @dev Adds or removes an interest ID from one interest lifecycle bucket.
     */
    function _setInterestBucket(uint256 interestId, InterestBucket bucket, bool inBucket) internal {
        EnumerableSet.UintSet storage s = interestBuckets[uint256(bucket)];
        if (inBucket) s.add(interestId);
        else s.remove(interestId);
    }

    /**
     * @dev Adds or removes an escrow ID from one escrow-state bucket.
     */
    function _setEscrowBucket(uint256 escrowId, EscrowBucket bucket, bool inBucket) internal {
        EnumerableSet.UintSet storage s = escrowBuckets[uint256(bucket)];
        if (inBucket) s.add(escrowId);
        else s.remove(escrowId);
    }

    /**
     * @dev Adds or removes an entity ID from one registry-state bucket.
     */
    function _setEntityBucket(bytes32 entityId, EntityBucket bucket, bool inBucket) internal {
        EnumerableSet.Bytes32Set storage s = entityBuckets[uint256(bucket)];
        if (inBucket) s.add(entityId);
        else s.remove(entityId);
    }

    /**
     * @dev Adds or removes a fuzz-created entity ID from one fuzz-entity bucket.
     */
    function _setFuzzEntityBucket(bytes32 entityId, FuzzEntityBucket bucket, bool inBucket) internal {
        EnumerableSet.Bytes32Set storage s = fuzzEntityBuckets[uint256(bucket)];
        if (inBucket) s.add(entityId);
        else s.remove(entityId);
    }

    /**
     * @dev Adds or removes a fuzz actor from one account-registration bucket.
     */
    function _setFuzzAccountBucket(address account, FuzzAccountBucket bucket, bool inBucket) internal {
        EnumerableSet.AddressSet storage s = fuzzAccountBuckets[uint256(bucket)];
        if (inBucket) s.add(account);
        else s.remove(account);
    }

    /**
     * @dev Clears an offer ID from all offer buckets after it leaves the bounded tracked set.
     */
    function _removeOfferFromFuzzStateIndex(uint256 offerId) internal {
        for (uint256 i; i < OFFER_BUCKET_COUNT; ++i) {
            offerBuckets[i].remove(offerId);
        }
    }

    /**
     * @dev Clears a deal ID from all deal buckets after it leaves the bounded tracked set.
     */
    function _removeDealFromFuzzStateIndex(uint256 dealId) internal {
        for (uint256 i; i < DEAL_BUCKET_COUNT; ++i) {
            dealBuckets[i].remove(dealId);
        }
    }

    /**
     * @dev Clears an interest ID from all interest buckets after it leaves the bounded tracked set.
     */
    function _removeInterestFromFuzzStateIndex(uint256 interestId) internal {
        for (uint256 i; i < INTEREST_BUCKET_COUNT; ++i) {
            interestBuckets[i].remove(interestId);
        }
    }

    /**
     * @dev Clears an escrow ID from all escrow buckets after it leaves the bounded tracked set.
     */
    function _removeEscrowFromFuzzStateIndex(uint256 escrowId) internal {
        for (uint256 i; i < ESCROW_BUCKET_COUNT; ++i) {
            escrowBuckets[i].remove(escrowId);
        }
    }

    /**
     * @dev Clears an entity ID from all registry-state buckets after it leaves the bounded tracked set.
     */
    function _removeEntityFromFuzzStateIndex(bytes32 entityId) internal {
        for (uint256 i; i < ENTITY_BUCKET_COUNT; ++i) {
            entityBuckets[i].remove(entityId);
        }
    }

    /**
     * @dev Clears a fuzz-created entity ID from all fuzz-entity buckets after eviction.
     */
    function _removeFuzzEntityFromFuzzStateIndex(bytes32 entityId) internal {
        for (uint256 i; i < FUZZ_ENTITY_BUCKET_COUNT; ++i) {
            fuzzEntityBuckets[i].remove(entityId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             SYNC HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Initializes free/registered account buckets for the fixed fuzz actor set.
     */
    function _initializeFuzzAccountBuckets() internal {
        for (uint256 i; i < fuzzWallets.length; ++i) {
            _syncFuzzAccount(fuzzWallets[i]);
        }
    }

    /**
     * @dev Records whether a fuzz account is registered, then refreshes its account bucket.
     */
    function _setFuzzAccountRegistered(address account, bool registered) internal {
        if (account == address(0)) return;

        trackedFuzzAccount[account] = registered;
        _syncFuzzAccount(account);
    }

    /**
     * @dev Classifies a fuzz actor as free or registered from current registry state.
     */
    function _syncFuzzAccount(address account) internal {
        if (account == address(0)) return;

        bool registered = _isAccountRegistered(account);
        trackedFuzzAccount[account] = registered;

        // Free accounts can be used by registerAccount; registered accounts can be updated or removed.
        _setFuzzAccountBucket(account, FuzzAccountBucket.Free, !registered);
        _setFuzzAccountBucket(account, FuzzAccountBucket.Registered, registered);
    }

    /**
     * @dev Refreshes registry-state buckets for a tracked entity ID.
     */
    function _syncEntity(bytes32 entityId) internal {
        if (entityId == bytes32(0) || !trackedEntity[entityId]) {
            _removeEntityFromFuzzStateIndex(entityId);
            return;
        }

        try entityRegistry.getEntityStatus(entityId) returns (EntityStatus status) {
            // Existing entities can be inspected; enabled entities can accept new account registrations.
            _setEntityBucket(entityId, EntityBucket.Existing, status != EntityStatus.NONE);
            _setEntityBucket(entityId, EntityBucket.Enabled, status == EntityStatus.ENABLED);
        } catch {
            _removeEntityFromFuzzStateIndex(entityId);
        }
    }

    /**
     * @dev Refreshes the dedicated bucket for an entity created by this fuzz campaign.
     */
    function _syncFuzzEntity(bytes32 entityId) internal {
        if (entityId == bytes32(0) || !trackedFuzzEntity[entityId]) {
            _removeFuzzEntityFromFuzzStateIndex(entityId);
            return;
        }

        try entityRegistry.getEntityStatus(entityId) returns (EntityStatus status) {
            // Fuzz-created entities can be reused by entity-management handlers after creation.
            _setFuzzEntityBucket(entityId, FuzzEntityBucket.Existing, status != EntityStatus.NONE);
        } catch {
            _removeFuzzEntityFromFuzzStateIndex(entityId);
        }
    }

    /**
     * @dev Refreshes escrow buckets from current EscrowManager state.
     */
    function _syncEscrow(uint256 escrowId) internal {
        if (escrowId == 0 || !trackedEscrow[escrowId]) {
            _removeEscrowFromFuzzStateIndex(escrowId);
            return;
        }

        Escrow memory escrow = escrowManager.getEscrow(escrowId);

        // Only fuzz-test escrows with funds are useful for withdraw/claim handlers.
        _setEscrowBucket(
            escrowId,
            EscrowBucket.FuzzTestFunded,
            escrow.moduleType == FUZZ_ESCROW_TEST_MODULE_TYPE && escrow.amount > 0
        );
    }

    /**
     * @dev Refreshes offer buckets from current offer, flag, interest-state, and escrow data.
     */
    function _syncOffer(uint256 offerId) internal {
        if (offerId == 0 || !trackedOffer[offerId]) {
            _removeOfferFromFuzzStateIndex(offerId);
            return;
        }

        (Offer memory offer, InterestDiscoveryState memory state,,, uint256 escrowId) =
            marketplace.getOfferData(offerId);
        (bool cancelled, bool frozen,) = marketplace.getOfferFlags(offerId);

        bool exists = escrowId != 0 && offer.owner != address(0);

        // Existing offers can participate in broad accounting invariants and follow-up lifecycle handlers.
        _setOfferBucket(offerId, OfferBucket.Existing, exists);
        _syncDirectOfferBuckets(offerId, offer, exists, cancelled, frozen);
        _syncInterestDiscoveryOfferBuckets(offerId, offer, state, exists, cancelled, frozen);
        // Frozen offers with non-deal escrow balance can be seized.
        _setOfferBucket(
            offerId,
            OfferBucket.FrozenSeizable,
            exists && frozen
                && (offer.amounts.available > 0
                    || (offer.saleMode == SaleMode.INTEREST_DISCOVERY && state.reservedInterestUnits > 0))
        );
    }

    /**
     * @dev Refreshes deal buckets from current deal, offer, freeze, and timestamp state.
     */
    function _syncDeal(uint256 dealId) internal {
        if (dealId == 0 || !trackedDeal[dealId]) {
            _removeDealFromFuzzStateIndex(dealId);
            return;
        }

        (Deal memory deal,) = marketplace.getDealData(dealId);

        bool exists = deal.status != DealStatus.NON_EXISTING;
        (bool offerFrozen, bool dealFrozen) = (_isOfferFrozen(deal.offerId), _isDealFrozen(dealId));

        // Existing deals can be snapshotted and inspected by general invariants.
        _setDealBucket(dealId, DealBucket.Existing, exists);
        // Active direct-sale counter offers can still be cancelled or resolved before their expiry.
        _setDealBucket(
            dealId,
            DealBucket.ActiveCounterOffer,
            exists && !dealFrozen && !offerFrozen && deal.status == DealStatus.PROPOSED
                && deal.dealType == DealType.COUNTER_OFFER && block.timestamp <= deal.counterOfferExpiry
                && _isDirectSaleMode(_getOffer(deal.offerId).saleMode)
        );
        // Pending payable deals can be deterministically advanced into payment, dispute, or paid-seizure flows.
        _setDealBucket(
            dealId,
            DealBucket.PendingPayable,
            exists && deal.status == DealStatus.PENDING && block.timestamp <= deal.paymentDeadline
        );
        // Payable deals are pending before deadline or unpaid while an arbitration/dispute buffer exists.
        _setDealBucket(
            dealId,
            DealBucket.Payable,
            exists
                && ((deal.status == DealStatus.PENDING && block.timestamp <= deal.paymentDeadline)
                    || (deal.status == DealStatus.UNPAID && deal.disputeBuffer != 0))
        );
        // Pending-expired deals can be marked unpaid once their payment deadline passes.
        _setDealBucket(
            dealId,
            DealBucket.PendingExpired,
            exists && deal.status == DealStatus.PENDING && block.timestamp > deal.paymentDeadline
        );
        // Unpaid disputable deals are still inside the buyer dispute window.
        _setDealBucket(
            dealId,
            DealBucket.UnpaidDisputable,
            exists && deal.status == DealStatus.UNPAID && block.timestamp <= deal.disputeBuffer
        );
        // In-dispute deals can be resolved through the dispute-resolution path.
        _setDealBucket(dealId, DealBucket.InDispute, exists && deal.status == DealStatus.IN_DISPUTE);
        // Paid settlements claim escrowed tokens and require an enabled buyer.
        // Unpaid settlements only move accounting after the dispute buffer elapsed.
        _setDealBucket(
            dealId,
            DealBucket.Settleable,
            exists && !dealFrozen && !offerFrozen
                && ((deal.status == DealStatus.PAID
                        && !_offerTokenPaused(deal.offerId)
                        && entityRegistry.isAccountEnabled(deal.buyer))
                    || (deal.status == DealStatus.UNPAID && block.timestamp > deal.disputeBuffer))
        );

        // Frozen seizable deals hold value that can be recovered once both offer and deal are frozen.
        _setDealBucket(
            dealId,
            DealBucket.FrozenSeizable,
            exists && dealFrozen && offerFrozen
                && (deal.status == DealStatus.PENDING
                    || deal.status == DealStatus.UNPAID
                    || deal.status == DealStatus.IN_DISPUTE
                    || deal.status == DealStatus.PAID)
        );
    }

    /**
     * @dev Refreshes interest buckets from current interest, offer, threshold, and timestamp state.
     */
    function _syncInterest(uint256 interestId) internal {
        if (interestId == 0 || !trackedInterest[interestId]) {
            _removeInterestFromFuzzStateIndex(interestId);
            return;
        }

        Interest memory interest = marketplace.getInterestData(interestId);

        bool exists = interest.status != InterestStatus.NON_EXISTING;
        bool expressed = exists && interest.status == InterestStatus.EXPRESSED;
        bool activatable;
        bool closeable;

        if (expressed) {
            (Offer memory offer, InterestDiscoveryState memory state,,,) = marketplace.getOfferData(interest.offerId);
            (bool cancelled, bool frozen,) = marketplace.getOfferFlags(interest.offerId);
            (activatable, closeable) = _interestBucketsForLifecycle(offer, state, cancelled, frozen);
        }

        // Expressed interests are still open and may later be activated or closed.
        _setInterestBucket(interestId, InterestBucket.Expressed, expressed);
        // Activatable interests are inside the activation deadline after threshold is reached.
        _setInterestBucket(interestId, InterestBucket.Activatable, expressed && activatable);
        // Closeable interests missed the activation deadline and can be closed back into inventory.
        _setInterestBucket(interestId, InterestBucket.Closeable, expressed && closeable);
    }

    /**
     * @dev Classifies direct-sale offers by active sale, counter-offer, cancellation, and withdrawal states.
     */
    function _syncDirectOfferBuckets(uint256 offerId, Offer memory offer, bool exists, bool cancelled, bool frozen)
        internal
    {
        bool direct = exists && _isDirectSaleMode(offer.saleMode);
        bool hasAvailable = offer.amounts.available > 0;
        bool hasActiveInventory = hasAvailable || offer.amounts.inDeals > 0;
        bool notExpired = block.timestamp <= offer.expiry;

        // Open direct offers can be accepted while not expired and still holding available inventory.
        _setOfferBucket(
            offerId, OfferBucket.MarketplaceOpen, direct && !cancelled && !frozen && notExpired && hasAvailable
        );
        // Counterable direct offers additionally allow buyers to create counter offers.
        _setOfferBucket(
            offerId,
            OfferBucket.MarketplaceCounterable,
            direct && !cancelled && !frozen && notExpired && hasAvailable && offer.allowCounterOffers
        );
        // Cancellable direct offers still have available inventory or pending deal inventory to release.
        _setOfferBucket(
            offerId, OfferBucket.MarketplaceCancellable, direct && !cancelled && !frozen && hasActiveInventory
        );
        // Cancelled direct offers are selectable for withdrawAvailable, including zero-available revert paths.
        _setOfferBucket(offerId, OfferBucket.MarketplaceCancelledWithAvailable, direct && cancelled && !frozen);
    }

    /**
     * @dev Classifies interest-discovery offers by open and expired-withdrawable lifecycle states.
     */
    function _syncInterestDiscoveryOfferBuckets(
        uint256 offerId,
        Offer memory offer,
        InterestDiscoveryState memory state,
        bool exists,
        bool cancelled,
        bool frozen
    ) internal {
        bool marketplace = exists && offer.saleMode == SaleMode.INTEREST_DISCOVERY;
        bool hasAvailable = offer.amounts.available > 0;
        bool expired = block.timestamp > offer.expiry;
        bool notExpired = !expired;

        // Existing interest-discovery offers can be used by interest-specific state checks.
        _setOfferBucket(offerId, OfferBucket.InterestDiscoveryExisting, marketplace);
        // Open interest-discovery offers can accept expressed interest before expiry.
        _setOfferBucket(
            offerId,
            OfferBucket.InterestDiscoveryOpen,
            marketplace && !cancelled && !frozen && notExpired && hasAvailable
        );
        // Expired interest-discovery offers can be withdrawn when any inventory is withdrawable.
        _setOfferBucket(
            offerId,
            OfferBucket.InterestDiscoveryExpiredWithdrawable,
            marketplace && !cancelled && !frozen && expired && _isInterestDiscoveryExpiredWithdrawable(offer, state)
        );
    }

    /**
     * @dev Returns whether expired interest-discovery inventory can be withdrawn by the seller.
     */
    function _isInterestDiscoveryExpiredWithdrawable(Offer memory offer, InterestDiscoveryState memory state)
        internal
        pure
        returns (bool)
    {
        bool thresholdReached = state.interestedUnits >= state.minSaleUnits;

        if (thresholdReached) {
            return offer.amounts.available > 0;
        }

        return offer.amounts.available > 0 || state.reservedInterestUnits > 0;
    }

    /**
     * @dev Splits expressed interests into activatable or closeable based on threshold and activation deadline.
     */
    function _interestBucketsForLifecycle(
        Offer memory offer,
        InterestDiscoveryState memory state,
        bool cancelled,
        bool frozen
    ) internal view returns (bool activatable, bool closeable) {
        bool thresholdReached = state.interestedUnits >= state.minSaleUnits;
        bool eligible = offer.saleMode == SaleMode.INTEREST_DISCOVERY && !cancelled && thresholdReached;

        if (!eligible) {
            return (false, false);
        }

        uint256 activationDeadline = _interestActivationDeadline(offer.expiry, state);
        activatable = !frozen && block.timestamp <= activationDeadline;
        closeable = block.timestamp > activationDeadline;
    }

    /**
     * @dev Refreshes all known interests belonging to one offer.
     */
    function _syncKnownInterestsForOffer(uint256 offerId) internal {
        uint256 len = knownInterestIds.length;

        for (uint256 i; i < len; ++i) {
            uint256 interestId = knownInterestIds[i];
            if (interestId == 0) continue;

            Interest memory interest = marketplace.getInterestData(interestId);
            if (interest.status == InterestStatus.NON_EXISTING) continue;
            if (interest.offerId != offerId) continue;

            _syncInterest(interestId);
        }
    }

    /**
     * @dev Refreshes every known deal belonging to one offer.
     */
    function _syncKnownDealsForOffer(uint256 offerId) internal {
        uint256 len = knownDealIds.length;

        for (uint256 i; i < len; ++i) {
            uint256 dealId = knownDealIds[i];
            if (dealId == 0) continue;

            Deal memory deal = _getDeal(dealId);
            if (deal.status == DealStatus.NON_EXISTING) continue;
            if (deal.offerId != offerId) continue;

            _syncDeal(dealId);
        }
    }

    /**
     * @dev Refreshes every known offer before selecting from a timestamp-sensitive offer bucket.
     */
    function _refreshOfferBucket(OfferBucket bucket) internal {
        if (!_offerBucketDependsOnTime(bucket)) return;

        uint256 len = knownOfferIds.length;

        for (uint256 i; i < len; ++i) {
            _syncOffer(knownOfferIds[i]);
        }
    }

    /**
     * @dev Refreshes every known deal before selecting from a timestamp-sensitive deal bucket.
     */
    function _refreshDealBucket(DealBucket bucket) internal {
        if (!_dealBucketDependsOnTime(bucket)) return;

        uint256 len = knownDealIds.length;

        for (uint256 i; i < len; ++i) {
            _syncDeal(knownDealIds[i]);
        }
    }

    /**
     * @dev Refreshes every known interest before selecting from a timestamp-sensitive interest bucket.
     */
    function _refreshInterestBucket(InterestBucket bucket) internal {
        if (!_interestBucketDependsOnTime(bucket)) return;

        uint256 len = knownInterestIds.length;

        for (uint256 i; i < len; ++i) {
            _syncInterest(knownInterestIds[i]);
        }
    }

    /**
     * @dev Returns whether offer bucket membership can change solely because block time advanced.
     */
    function _offerBucketDependsOnTime(OfferBucket bucket) internal pure returns (bool) {
        return bucket == OfferBucket.MarketplaceOpen || bucket == OfferBucket.MarketplaceCounterable
            || bucket == OfferBucket.InterestDiscoveryOpen || bucket == OfferBucket.InterestDiscoveryExpiredWithdrawable;
    }

    /**
     * @dev Returns whether deal bucket membership can change solely because block time advanced.
     */
    function _dealBucketDependsOnTime(DealBucket bucket) internal pure returns (bool) {
        return bucket == DealBucket.ActiveCounterOffer || bucket == DealBucket.PendingPayable
            || bucket == DealBucket.Payable || bucket == DealBucket.PendingExpired
            || bucket == DealBucket.UnpaidDisputable || bucket == DealBucket.Settleable;
    }

    /**
     * @dev Returns whether interest bucket membership can change solely because block time advanced.
     */
    function _interestBucketDependsOnTime(InterestBucket bucket) internal pure returns (bool) {
        return bucket == InterestBucket.Activatable || bucket == InterestBucket.Closeable;
    }

    /*//////////////////////////////////////////////////////////////
                              PICK HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Picks a live entity from a registry-state bucket, removing stale candidates as encountered.
     */
    function _pickEntityFromBucket(EntityBucket bucket, uint256 seed) internal returns (bool found, bytes32 entityId) {
        EnumerableSet.Bytes32Set storage s = entityBuckets[uint256(bucket)];

        for (uint256 i; i < FUZZ_STATE_INDEX_PICK_ATTEMPTS; ++i) {
            uint256 len = s.length();
            if (len == 0) return (false, bytes32(0));

            bytes32 candidate = s.at(uint256(keccak256(abi.encode(seed, i))) % len);

            _syncEntity(candidate);

            if (!s.contains(candidate)) continue;

            return (true, candidate);
        }

        return (false, bytes32(0));
    }

    /**
     * @dev Picks a live fuzz-created entity from a fuzz-entity bucket.
     */
    function _pickFuzzEntityFromBucket(FuzzEntityBucket bucket, uint256 seed)
        internal
        returns (bool found, bytes32 entityId)
    {
        EnumerableSet.Bytes32Set storage s = fuzzEntityBuckets[uint256(bucket)];

        for (uint256 i; i < FUZZ_STATE_INDEX_PICK_ATTEMPTS; ++i) {
            uint256 len = s.length();
            if (len == 0) return (false, bytes32(0));

            bytes32 candidate = s.at(uint256(keccak256(abi.encode(seed, i))) % len);

            _syncFuzzEntity(candidate);

            if (!s.contains(candidate)) continue;

            return (true, candidate);
        }

        return (false, bytes32(0));
    }

    /**
     * @dev Picks a fuzz actor from the free or registered account bucket.
     */
    function _pickFuzzAccountFromBucket(FuzzAccountBucket bucket, uint256 seed)
        internal
        returns (bool found, address account)
    {
        EnumerableSet.AddressSet storage s = fuzzAccountBuckets[uint256(bucket)];

        for (uint256 i; i < FUZZ_STATE_INDEX_PICK_ATTEMPTS; ++i) {
            uint256 len = s.length();
            if (len == 0) return (false, address(0));

            address candidate = s.at(uint256(keccak256(abi.encode(seed, i))) % len);

            _syncFuzzAccount(candidate);

            if (!s.contains(candidate)) continue;

            return (true, candidate);
        }

        return (false, address(0));
    }

    /**
     * @dev Picks a funded fuzz-test escrow and returns its current EscrowManager state.
     */
    function _pickEscrowFromBucket(EscrowBucket bucket, uint256 seed)
        internal
        returns (bool found, uint256 escrowId, Escrow memory escrow)
    {
        EnumerableSet.UintSet storage s = escrowBuckets[uint256(bucket)];

        for (uint256 i; i < FUZZ_STATE_INDEX_PICK_ATTEMPTS; ++i) {
            uint256 len = s.length();
            if (len == 0) return (false, 0, escrow);

            uint256 candidate = s.at(uint256(keccak256(abi.encode(seed, i))) % len);

            _syncEscrow(candidate);

            if (!s.contains(candidate)) continue;

            escrow = escrowManager.getEscrow(candidate);
            return (true, candidate, escrow);
        }

        return (false, 0, escrow);
    }

    /**
     * @dev Refreshes timestamp-sensitive offer buckets, then picks a live offer.
     */
    function _pickOfferFromBucket(OfferBucket bucket, uint256 seed)
        internal
        returns (bool found, uint256 offerId, Offer memory offer)
    {
        _refreshOfferBucket(bucket);

        return _pickOfferFromBucketRaw(bucket, seed);
    }

    /**
     * @dev Picks an offer from an already-refreshed bucket and skips stale candidates.
     */
    function _pickOfferFromBucketRaw(OfferBucket bucket, uint256 seed)
        internal
        returns (bool found, uint256 offerId, Offer memory offer)
    {
        EnumerableSet.UintSet storage s = offerBuckets[uint256(bucket)];

        for (uint256 i; i < FUZZ_STATE_INDEX_PICK_ATTEMPTS; ++i) {
            uint256 len = s.length();
            if (len == 0) return (false, 0, offer);

            uint256 candidate = s.at(uint256(keccak256(abi.encode(seed, i))) % len);

            _syncOffer(candidate);

            if (!s.contains(candidate)) continue;

            offer = _getOffer(candidate);
            return (true, candidate, offer);
        }

        return (false, 0, offer);
    }

    /**
     * @dev Refreshes timestamp-sensitive deal buckets, then picks a live deal.
     */
    function _pickDealFromBucket(DealBucket bucket, uint256 seed)
        internal
        returns (bool found, uint256 dealId, Deal memory deal)
    {
        _refreshDealBucket(bucket);

        return _pickDealFromBucketRaw(bucket, seed);
    }

    /**
     * @dev Picks a deal from an already-refreshed bucket and skips stale candidates.
     */
    function _pickDealFromBucketRaw(DealBucket bucket, uint256 seed)
        internal
        returns (bool found, uint256 dealId, Deal memory deal)
    {
        EnumerableSet.UintSet storage s = dealBuckets[uint256(bucket)];

        for (uint256 i; i < FUZZ_STATE_INDEX_PICK_ATTEMPTS; ++i) {
            uint256 len = s.length();
            if (len == 0) return (false, 0, deal);

            uint256 candidate = s.at(uint256(keccak256(abi.encode(seed, i))) % len);

            _syncDeal(candidate);

            if (!s.contains(candidate)) continue;

            deal = _getDeal(candidate);
            return (true, candidate, deal);
        }

        return (false, 0, deal);
    }

    /**
     * @dev Refreshes timestamp-sensitive interest buckets, then picks a live interest.
     */
    function _pickInterestFromBucket(InterestBucket bucket, uint256 seed)
        internal
        returns (bool found, uint256 interestId, Interest memory interest)
    {
        _refreshInterestBucket(bucket);

        return _pickInterestFromBucketRaw(bucket, seed);
    }

    /**
     * @dev Picks an interest from an already-refreshed bucket and skips stale candidates.
     */
    function _pickInterestFromBucketRaw(InterestBucket bucket, uint256 seed)
        internal
        returns (bool found, uint256 interestId, Interest memory interest)
    {
        EnumerableSet.UintSet storage s = interestBuckets[uint256(bucket)];

        for (uint256 i; i < FUZZ_STATE_INDEX_PICK_ATTEMPTS; ++i) {
            uint256 len = s.length();
            if (len == 0) return (false, 0, interest);

            uint256 candidate = s.at(uint256(keccak256(abi.encode(seed, i))) % len);

            _syncInterest(candidate);

            if (!s.contains(candidate)) continue;

            interest = _getInterest(candidate);
            return (true, candidate, interest);
        }

        return (false, 0, interest);
    }

    /**
     * @dev Picks an entity from a bucket while excluding one specific entity ID.
     */
    function _pickEntityFromBucketDifferentFrom(EntityBucket bucket, bytes32 exclude, uint256 seed)
        internal
        returns (bool found, bytes32 entityId)
    {
        for (uint256 i; i < FUZZ_STATE_INDEX_PICK_ATTEMPTS; ++i) {
            (bool ok, bytes32 candidate) =
                _pickEntityFromBucket(bucket, uint256(keccak256(abi.encode(seed, i, "different"))));

            if (!ok) return (false, bytes32(0));

            if (candidate != exclude) {
                return (true, candidate);
            }
        }

        return (false, bytes32(0));
    }

    /**
     * @dev Picks an offer from a bucket that is owned by the requested actor.
     */
    function _pickOfferFromBucketOwnedBy(OfferBucket bucket, address owner, uint256 seed)
        internal
        returns (bool found, uint256 offerId, Offer memory offer)
    {
        _refreshOfferBucket(bucket);

        for (uint256 i; i < FUZZ_STATE_INDEX_PICK_ATTEMPTS; ++i) {
            (bool ok, uint256 candidate, Offer memory candidateOffer) =
                _pickOfferFromBucketRaw(bucket, uint256(keccak256(abi.encode(seed, i, "owned"))));

            if (!ok) return (false, 0, offer);

            if (candidateOffer.owner == owner) {
                return (true, candidate, candidateOffer);
            }
        }

        return (false, 0, offer);
    }

    /**
     * @dev Picks an offer from a bucket that is not owned by the requested actor.
     */
    function _pickOfferFromBucketNotOwnedBy(OfferBucket bucket, address actor, uint256 seed)
        internal
        returns (bool found, uint256 offerId, Offer memory offer)
    {
        _refreshOfferBucket(bucket);

        for (uint256 i; i < FUZZ_STATE_INDEX_PICK_ATTEMPTS; ++i) {
            (bool ok, uint256 candidate, Offer memory candidateOffer) =
                _pickOfferFromBucketRaw(bucket, uint256(keccak256(abi.encode(seed, i, "not-owned"))));

            if (!ok) return (false, 0, offer);

            if (candidateOffer.owner != address(0) && candidateOffer.owner != actor) {
                return (true, candidate, candidateOffer);
            }
        }

        return (false, 0, offer);
    }

    /**
     * @dev Picks a deal from a bucket whose buyer is the requested actor.
     */
    function _pickDealFromBucketByBuyer(DealBucket bucket, address buyer, uint256 seed)
        internal
        returns (bool found, uint256 dealId, Deal memory deal)
    {
        _refreshDealBucket(bucket);

        for (uint256 i; i < FUZZ_STATE_INDEX_PICK_ATTEMPTS; ++i) {
            (bool ok, uint256 candidate, Deal memory candidateDeal) =
                _pickDealFromBucketRaw(bucket, uint256(keccak256(abi.encode(seed, i, "buyer"))));

            if (!ok) return (false, 0, deal);

            if (candidateDeal.buyer == buyer) {
                return (true, candidate, candidateDeal);
            }
        }

        return (false, 0, deal);
    }

    /**
     * @dev Picks a deal from a bucket whose parent offer is owned by the requested actor.
     */
    function _pickDealFromBucketByOfferOwner(DealBucket bucket, address owner, uint256 seed)
        internal
        returns (bool found, uint256 dealId, Deal memory deal)
    {
        _refreshDealBucket(bucket);

        for (uint256 i; i < FUZZ_STATE_INDEX_PICK_ATTEMPTS; ++i) {
            (bool ok, uint256 candidate, Deal memory candidateDeal) =
                _pickDealFromBucketRaw(bucket, uint256(keccak256(abi.encode(seed, i, "seller"))));

            if (!ok) return (false, 0, deal);

            Offer memory offer = _getOffer(candidateDeal.offerId);

            if (offer.owner == owner) {
                return (true, candidate, candidateDeal);
            }
        }

        return (false, 0, deal);
    }
}
