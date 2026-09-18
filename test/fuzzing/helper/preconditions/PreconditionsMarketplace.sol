// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, gas-strict-inequalities */

import {
    Deal,
    DealStatus,
    DealType,
    Interest,
    InterestDiscoveryState,
    InterestStatus,
    PaymentResolutionInput,
    Offer,
    SaleMode
} from "src/marketplace/MarketStructs.sol";
import {BondStatus} from "src/registry/BondStructs.sol";
import {DealBucket, InterestBucket, OfferBucket} from "../FuzzStateIndex.sol";
import {PreconditionsBase} from "./PreconditionsBase.sol";

abstract contract PreconditionsMarketplace is PreconditionsBase {
    struct RegisterOfferParams {
        uint256 totalAmount;
        uint256 lot;
        uint256 unitPrice;
        uint256 expiry;
    }

    struct RegisterRedemptionOfferParams {
        uint256 totalAmount;
        uint256 lot;
        uint256 unitPrice;
        uint256 expiry;
        address[] allowedBuyers;
    }

    struct RegisterInterestOfferParams {
        uint256 totalAmount;
        uint256 lot;
        uint256 unitPrice;
        uint256 expiry;
        uint256 minSaleUnits;
    }

    struct AcceptOfferParams {
        uint256 offerId;
        uint256 amount;
    }

    struct ExpressInterestParams {
        uint256 offerId;
        uint256 amount;
    }

    struct CounterOfferParams {
        uint256 offerId;
        uint256 amount;
        uint256 unitPrice;
        uint256 expiry;
    }

    struct OfferOwnerParams {
        uint256 offerId;
    }

    struct CloseInterestParams {
        uint256 offerId;
        uint256 interestId;
    }

    struct CloseInterestBatchParams {
        uint256 offerId;
        uint256[] interestIds;
    }

    struct ResolveDisputeParams {
        uint256 dealId;
        DealStatus status;
    }

    struct SeizeOfferParams {
        uint256 offerId;
        address beneficiary;
        bytes32 reason;
    }

    struct SeizeDealParams {
        uint256 offerId;
        uint256 dealId;
        address beneficiary;
        bytes32 reason;
    }

    struct DisputeResolutionFlowParams {
        uint256 offerId;
        uint256 dealId;
        uint256 paymentDeadline;
        DealStatus status;
    }

    struct ResolvePaymentsBatchParams {
        uint256[] offerIds;
        uint256[] dealIds;
        PaymentResolutionInput[] resolutions;
    }

    struct ResolvePaymentsDuplicateParams {
        uint256 offerId;
        uint256 dealId;
        address resolver;
        PaymentResolutionInput[] resolutions;
    }

    struct ResolvePaymentsSingleParams {
        uint256 offerId;
        uint256 dealId;
        PaymentResolutionInput[] resolutions;
    }

    struct PendingDealSeed {
        uint256 offerId;
        uint256 dealId;
    }

    function registerMarketplaceOfferPreconditions(uint256 total, uint256 lot)
        internal
        returns (RegisterOfferParams memory params)
    {
        return _registerOfferPreconditions(total, lot, FIXED_FUZZ_EXPIRY_DELTA);
    }

    function registerRedemptionOfferPreconditions(uint256 total, uint256 lot)
        internal
        returns (RegisterRedemptionOfferParams memory params)
    {
        RegisterOfferParams memory base = _registerOfferPreconditions(total, lot, FIXED_FUZZ_EXPIRY_DELTA);
        params.totalAmount = base.totalAmount;
        params.lot = base.lot;
        params.unitPrice = base.unitPrice;
        params.expiry = base.expiry;
        params.allowedBuyers = _nonOwnerUsers(currentActor);
        require(params.allowedBuyers.length != 0, ClampFail("no allowed buyers"));
    }

    function registerInterestOfferPreconditions(uint256 total, uint256 lot, uint256 minSaleUnitsSeed)
        internal
        returns (RegisterInterestOfferParams memory params)
    {
        RegisterOfferParams memory base = _registerOfferPreconditions(total, lot, OFFER_EXPIRY_THRESHOLD);
        uint256 offerUnits = base.totalAmount / base.lot;
        uint256 maxMinUnits = fl.min(offerUnits, MAX_INTEREST_DISCOVERY_MIN_SALE_UNITS);
        uint256 minUnits = fl.clamp(minSaleUnitsSeed, 1, maxMinUnits);

        params.totalAmount = base.totalAmount;
        params.lot = base.lot;
        params.unitPrice = base.unitPrice;
        params.expiry = base.expiry;
        params.minSaleUnits = minUnits * base.lot;
    }

    function acceptOfferPreconditions(uint256 offer, uint256 amount)
        internal
        returns (AcceptOfferParams memory params)
    {
        (bool found, uint256 offerId, Offer memory offerState) = _pickOfferFromBucketNotOwnedBy(
            OfferBucket.MarketplaceOpen, currentActor, offer
        );
        require(found, ClampFail("no acceptable tracked offer"));

        require(offerState.owner != address(0), ClampFail("offer missing"));
        require(_isDirectSaleMode(offerState.saleMode), ClampFail("offer not direct"));
        require(!_isOfferCancelled(offerId), ClampFail("offer cancelled"));
        require(!_isOfferFrozen(offerId), ClampFail("offer frozen"));
        require(offerState.amounts.available != 0, ClampFail("offer unavailable"));
        require(offerState.lot != 0, ClampFail("offer lot is zero"));
        require(block.timestamp <= offerState.expiry, ClampFail("offer expired"));
        require(_isBuyerAllowed(offerId, offerState, currentActor), ClampFail("buyer not allowed"));

        uint256 maxUnits = offerState.amounts.available / offerState.lot;
        require(maxUnits != 0, ClampFail("offer has no purchasable units"));
        uint256 units = fl.clamp(amount, 1, maxUnits);

        params.offerId = offerId;
        params.amount = units * offerState.lot;
    }

    function expressInterestBelowThresholdPreconditions(uint256 offer, uint256 amount)
        internal
        returns (ExpressInterestParams memory params)
    {
        (bool found, uint256 offerId, Offer memory offerState) =
            _pickOfferFromBucketNotOwnedBy(OfferBucket.InterestDiscoveryOpen, currentActor, offer);
        require(found, ClampFail("no tracked interest offer"));

        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        require(offerState.owner != address(0), ClampFail("offer missing"));
        require(offerState.saleMode == SaleMode.INTEREST_DISCOVERY, ClampFail("offer not interest discovery"));
        require(!_isOfferCancelled(offerId), ClampFail("offer cancelled"));
        require(!_isOfferFrozen(offerId), ClampFail("offer frozen"));
        require(offerState.amounts.available != 0, ClampFail("offer unavailable"));
        require(offerState.lot != 0, ClampFail("offer lot is zero"));
        require(block.timestamp <= offerState.expiry, ClampFail("offer expired"));
        require(state.interestedUnits < state.minSaleUnits, ClampFail("threshold already reached"));

        uint256 remainingBeforeThreshold = state.minSaleUnits - state.interestedUnits;
        require(remainingBeforeThreshold > offerState.lot, ClampFail("no below-threshold room"));

        uint256 maxBelowThresholdUnits = (remainingBeforeThreshold - 1) / offerState.lot;
        uint256 maxAvailableUnits = offerState.amounts.available / offerState.lot;
        uint256 maxUnits = fl.min(maxBelowThresholdUnits, maxAvailableUnits);
        require(maxUnits != 0, ClampFail("no below-threshold units"));
        uint256 units = fl.clamp(amount, 1, maxUnits);

        params.offerId = offerId;
        params.amount = units * offerState.lot;
    }

    function expressInterestPreconditions(uint256 offer, uint256 amount)
        internal
        returns (ExpressInterestParams memory params)
    {
        (bool found, uint256 offerId, Offer memory offerState) =
            _pickOfferFromBucketNotOwnedBy(OfferBucket.InterestDiscoveryOpen, currentActor, offer);
        require(found, ClampFail("no tracked interest offer"));

        require(offerState.owner != address(0), ClampFail("offer missing"));
        require(offerState.saleMode == SaleMode.INTEREST_DISCOVERY, ClampFail("offer not interest discovery"));
        require(!_isOfferCancelled(offerId), ClampFail("offer cancelled"));
        require(!_isOfferFrozen(offerId), ClampFail("offer frozen"));
        require(offerState.amounts.available != 0, ClampFail("offer unavailable"));
        require(offerState.lot != 0, ClampFail("offer lot is zero"));
        require(block.timestamp <= offerState.expiry, ClampFail("offer expired"));

        uint256 maxUnits = offerState.amounts.available / offerState.lot;
        require(maxUnits != 0, ClampFail("offer has no expressible units"));
        uint256 units = fl.clamp(amount, 1, maxUnits);

        params.offerId = offerId;
        params.amount = units * offerState.lot;
    }

    function activateInterestPreconditions(uint256 interest) internal returns (uint256 interestId) {
        (bool found, uint256 pickedInterestId, Interest memory interestState) =
            _pickInterestFromBucket(InterestBucket.Activatable, interest);
        require(found, ClampFail("no activatable interest"));

        require(interestState.status == InterestStatus.EXPRESSED, ClampFail("interest not expressed"));

        Offer memory offerState = _getOffer(interestState.offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(interestState.offerId);
        require(offerState.saleMode == SaleMode.INTEREST_DISCOVERY, ClampFail("offer not interest discovery"));
        require(!_isOfferCancelled(interestState.offerId), ClampFail("offer cancelled"));
        require(!_isOfferFrozen(interestState.offerId), ClampFail("offer frozen"));
        require(state.interestedUnits >= state.minSaleUnits, ClampFail("threshold not reached"));
        require(
            block.timestamp <= _interestActivationDeadline(offerState.expiry, state),
            ClampFail("activation window closed")
        );

        return pickedInterestId;
    }

    function closeExpiredInterestPreconditions(uint256 interest) internal returns (CloseInterestParams memory params) {
        (bool found, uint256 pickedInterestId, Interest memory interestState) =
            _pickInterestFromBucket(InterestBucket.Closeable, interest);
        require(found, ClampFail("no closeable interest"));

        require(interestState.status == InterestStatus.EXPRESSED, ClampFail("interest not expressed"));

        Offer memory offerState = _getOffer(interestState.offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(interestState.offerId);
        require(offerState.owner != address(0), ClampFail("offer missing"));
        require(offerState.saleMode == SaleMode.INTEREST_DISCOVERY, ClampFail("offer not interest discovery"));
        require(!_isOfferCancelled(interestState.offerId), ClampFail("offer cancelled"));
        require(state.interestedUnits >= state.minSaleUnits, ClampFail("threshold not reached"));
        require(
            block.timestamp > _interestActivationDeadline(offerState.expiry, state), ClampFail("activation window open")
        );

        params.offerId = interestState.offerId;
        params.interestId = pickedInterestId;
    }

    function closeExpiredInterestsBatchPreconditions(uint256 interest, uint256 countSeed)
        internal
        returns (CloseInterestBatchParams memory params)
    {
        (bool found, uint256 pickedInterestId, Interest memory interestState) =
            _pickInterestFromBucket(InterestBucket.Closeable, interest);
        require(found, ClampFail("no closeable interest"));

        uint256 targetCount =
            fl.clamp(countSeed, MIN_CLOSE_EXPIRED_INTERESTS_BATCH_SIZE, MAX_CLOSE_EXPIRED_INTERESTS_BATCH_SIZE);
        uint256[] memory picked = new uint256[](targetCount);
        picked[0] = pickedInterestId;

        params.offerId = interestState.offerId;

        uint256 pickedCount = 1;
        uint256 len = knownInterestIds.length;
        require(len > 1, ClampFail("not enough tracked interests"));

        uint256 start = countSeed % len;
        for (uint256 offset; offset < len && pickedCount < targetCount; ++offset) {
            uint256 candidate = knownInterestIds[(start + offset) % len];
            if (candidate == pickedInterestId) continue;
            if (!_isCloseableInterestForOffer(candidate, params.offerId)) continue;

            picked[pickedCount] = candidate;
            ++pickedCount;
        }

        require(pickedCount > 1, ClampFail("not enough closeable interests"));

        params.interestIds = new uint256[](pickedCount);
        for (uint256 i; i < pickedCount; ++i) {
            params.interestIds[i] = picked[i];
        }
    }

    function withdrawAvailablePreconditions(uint256 offer) internal returns (OfferOwnerParams memory params) {
        require(!_tokenPaused(), ClampFail("token paused"));

        (bool found, uint256 offerId, Offer memory offerState) =
            _pickOfferFromBucket(OfferBucket.MarketplaceCancelledWithAvailable, offer);
        require(found, ClampFail("no withdrawable tracked offer"));

        require(offerState.owner != address(0), ClampFail("offer missing"));
        require(entityRegistry.isAccountEnabled(offerState.owner), ClampFail("offer owner disabled"));
        require(!_isOfferFrozen(offerId), ClampFail("offer frozen"));
        require(offerState.amounts.available != 0, ClampFail("offer has no withdrawable amount"));

        params.offerId = offerId;
    }

    function withdrawInterestAvailablePreconditions(uint256 offer) internal returns (OfferOwnerParams memory params) {
        require(!_tokenPaused(), ClampFail("token paused"));

        (bool found, uint256 offerId, Offer memory offerState) =
            _pickOfferFromBucket(OfferBucket.InterestDiscoveryExpiredWithdrawable, offer);
        require(found, ClampFail("no withdrawable interest offer"));

        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        require(offerState.owner != address(0), ClampFail("offer missing"));
        require(entityRegistry.isAccountEnabled(offerState.owner), ClampFail("offer owner disabled"));
        require(offerState.saleMode == SaleMode.INTEREST_DISCOVERY, ClampFail("offer not interest discovery"));
        require(!_isOfferCancelled(offerId), ClampFail("offer cancelled"));
        require(!_isOfferFrozen(offerId), ClampFail("offer frozen"));
        require(block.timestamp > offerState.expiry, ClampFail("offer not expired"));
        require(state.interestedUnits >= state.minSaleUnits, ClampFail("threshold not reached"));
        require(offerState.amounts.available != 0, ClampFail("offer has no withdrawable amount"));

        params.offerId = offerId;
    }

    function withdrawInterestAvailableBelowThresholdPreconditions(uint256 offer)
        internal
        returns (OfferOwnerParams memory params)
    {
        require(!_tokenPaused(), ClampFail("token paused"));

        (bool found, uint256 offerId, Offer memory offerState) =
            _pickOfferFromBucket(OfferBucket.InterestDiscoveryExpiredWithdrawable, offer);
        require(found, ClampFail("no withdrawable interest offer"));

        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        require(offerState.owner != address(0), ClampFail("offer missing"));
        require(entityRegistry.isAccountEnabled(offerState.owner), ClampFail("offer owner disabled"));
        require(offerState.saleMode == SaleMode.INTEREST_DISCOVERY, ClampFail("offer not interest discovery"));
        require(!_isOfferCancelled(offerId), ClampFail("offer cancelled"));
        require(!_isOfferFrozen(offerId), ClampFail("offer frozen"));
        require(block.timestamp > offerState.expiry, ClampFail("offer not expired"));
        require(state.interestedUnits < state.minSaleUnits, ClampFail("threshold reached"));
        require(state.reservedInterestUnits != 0, ClampFail("no reserved interest"));

        params.offerId = offerId;
    }

    function cancelFailedInterestOfferPreconditions(uint256 offer) internal returns (OfferOwnerParams memory params) {
        require(!_tokenPaused(), ClampFail("token paused"));

        (bool found, uint256 offerId, Offer memory offerState) =
            _pickOfferFromBucket(OfferBucket.InterestDiscoveryExpiredWithdrawable, offer);
        require(found, ClampFail("no failed interest offer"));

        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        require(offerState.owner != address(0), ClampFail("offer missing"));
        require(entityRegistry.isAccountEnabled(offerState.owner), ClampFail("offer owner disabled"));
        require(offerState.saleMode == SaleMode.INTEREST_DISCOVERY, ClampFail("offer not interest discovery"));
        require(!_isOfferCancelled(offerId), ClampFail("offer cancelled"));
        require(block.timestamp > offerState.expiry, ClampFail("offer not expired"));
        require(state.interestedUnits < state.minSaleUnits, ClampFail("threshold reached"));

        params.offerId = offerId;
    }

    function cancelFailedInterestOfferByOperatorPreconditions(uint256 offer)
        internal
        returns (OfferOwnerParams memory params)
    {
        params = cancelFailedInterestOfferPreconditions(offer);

        require(
            marketplace.hasAllRoles(address(this), marketplace.INTEREST_DISCOVERY_OPERATOR()),
            ClampFail("operator role missing")
        );
    }

    function createCounterOfferPreconditions(uint256 offer, uint256 amount)
        internal
        returns (CounterOfferParams memory params)
    {
        (bool found, uint256 offerId, Offer memory offerState) =
            _pickOfferFromBucketNotOwnedBy(OfferBucket.MarketplaceCounterable, currentActor, offer);
        require(found, ClampFail("no counterable tracked offer"));

        require(offerState.owner != address(0), ClampFail("offer missing"));
        require(offerState.saleMode == SaleMode.MARKETPLACE, ClampFail("offer not marketplace"));
        require(offerState.allowCounterOffers, ClampFail("counter offers disabled"));
        require(!_isOfferFrozen(offerId), ClampFail("offer frozen"));
        require(offerState.amounts.available != 0, ClampFail("offer unavailable"));
        require(offerState.lot != 0, ClampFail("offer lot is zero"));
        require(block.timestamp <= offerState.expiry, ClampFail("offer expired"));
        require(_isBuyerAllowed(offerId, offerState, currentActor), ClampFail("buyer not allowed"));
        require(
            _getCounterOfferCount(currentActor, offerId) < _getMaxCounterOffersPerUser(),
            ClampFail("counter offer limit reached")
        );

        uint256 maxUnits = offerState.amounts.available / offerState.lot;
        require(maxUnits != 0, ClampFail("offer has no counterable units"));
        uint256 units = fl.clamp(amount, 1, maxUnits);

        params.offerId = offerId;
        params.amount = units * offerState.lot;
        params.unitPrice = DEFAULT_UNIT_PRICE;
        params.expiry = block.timestamp + FIXED_FUZZ_EXPIRY_DELTA;
    }

    function cancelOfferPreconditions(uint256 offer) internal returns (OfferOwnerParams memory params) {
        require(!_tokenPaused(), ClampFail("token paused"));

        (bool found, uint256 offerId, Offer memory offerState) =
            _pickOfferFromBucketOwnedBy(OfferBucket.MarketplaceCancellable, currentActor, offer);
        require(found, ClampFail("no cancellable tracked offer"));

        require(offerState.owner != address(0), ClampFail("offer missing"));
        require(_isDirectSaleMode(offerState.saleMode), ClampFail("offer not direct"));
        require(!_isOfferCancelled(offerId), ClampFail("offer cancelled"));
        require(!_isOfferFrozen(offerId), ClampFail("offer frozen"));
        require(
            offerState.amounts.available != 0 || offerState.amounts.inDeals != 0,
            ClampFail("offer has no tracked balance")
        );

        params.offerId = offerId;
    }

    function cancelCounterOfferPreconditions(uint256 deal) internal returns (uint256 dealId) {
        (bool found, uint256 pickedDealId, Deal memory dealState) =
            _pickDealFromBucket(DealBucket.ActiveCounterOffer, deal);
        require(found, ClampFail("no cancellable counter offer"));

        require(dealState.status == DealStatus.PROPOSED, ClampFail("deal not proposed"));
        require(block.timestamp <= dealState.counterOfferExpiry, ClampFail("counter offer expired"));
        require(!_isDealFrozen(pickedDealId), ClampFail("deal frozen"));
        require(!_isOfferFrozen(dealState.offerId), ClampFail("offer frozen"));

        Offer memory offerState = _getOffer(dealState.offerId);
        require(offerState.saleMode == SaleMode.MARKETPLACE, ClampFail("offer not marketplace"));
        require(dealState.dealType == DealType.COUNTER_OFFER, ClampFail("deal not counter offer"));
        return pickedDealId;
    }

    function resolveCounterOfferPreconditions(uint256 deal, bool accepted) internal returns (uint256 dealId) {
        (bool found, uint256 pickedDealId, Deal memory dealState) =
            _pickDealFromBucket(DealBucket.ActiveCounterOffer, deal);
        require(found, ClampFail("no resolvable counter offer"));

        require(dealState.status == DealStatus.PROPOSED, ClampFail("deal not proposed"));
        require(block.timestamp <= dealState.counterOfferExpiry, ClampFail("counter offer expired"));
        require(!_isDealFrozen(pickedDealId), ClampFail("deal frozen"));
        require(!_isOfferFrozen(dealState.offerId), ClampFail("offer frozen"));

        Offer memory offerState = _getOffer(dealState.offerId);
        require(offerState.owner != address(0), ClampFail("offer missing"));
        require(!_isOfferCancelled(dealState.offerId), ClampFail("offer cancelled"));
        require(offerState.saleMode == SaleMode.MARKETPLACE, ClampFail("offer not marketplace"));
        require(dealState.dealType == DealType.COUNTER_OFFER, ClampFail("deal not counter offer"));
        if (accepted) {
            require(block.timestamp <= offerState.expiry, ClampFail("offer expired"));
            require(offerState.amounts.available >= dealState.amount, ClampFail("offer amount no longer available"));
        }
        return pickedDealId;
    }

    function resolvePaymentPreconditions(uint256 deal, bool paid) internal returns (uint256 dealId) {
        (bool found, uint256 pickedDealId, Deal memory dealState) =
            paid ? _pickDealFromBucket(DealBucket.Payable, deal) : _pickDealFromBucket(DealBucket.PendingExpired, deal);
        require(found, ClampFail("no payable tracked deal"));

        if (paid) {
            require(
                dealState.status == DealStatus.PENDING || dealState.status == DealStatus.UNPAID,
                ClampFail("deal not payable")
            );
            if (dealState.status == DealStatus.PENDING) {
                require(block.timestamp <= dealState.paymentDeadline, ClampFail("payment deadline passed"));
            } else {
                require(dealState.disputeBuffer != 0, ClampFail("deal already arbitrated"));
            }
        } else {
            require(dealState.status == DealStatus.PENDING, ClampFail("deal not pending"));
            require(block.timestamp > dealState.paymentDeadline, ClampFail("payment deadline not passed"));
        }

        return pickedDealId;
    }

    function settleDealsBatchPreconditions(uint256 deal, uint256 countSeed)
        internal
        returns (uint256[] memory dealIds)
    {
        uint256 firstDealId = settleDealPreconditions(deal);
        uint256 targetCount =
            fl.clamp(countSeed, MIN_CLOSE_EXPIRED_INTERESTS_BATCH_SIZE, MAX_CLOSE_EXPIRED_INTERESTS_BATCH_SIZE);
        uint256[] memory picked = new uint256[](targetCount);
        picked[0] = firstDealId;

        uint256 pickedCount = 1;
        uint256 len = knownDealIds.length;
        require(len > 1, ClampFail("not enough tracked deals"));

        uint256 start = countSeed % len;
        for (uint256 offset; offset < len && pickedCount < targetCount; ++offset) {
            uint256 candidate = knownDealIds[(start + offset) % len];
            if (candidate == firstDealId) continue;
            if (!_isSettleableDeal(candidate)) continue;

            picked[pickedCount] = candidate;
            ++pickedCount;
        }

        require(pickedCount > 1, ClampFail("not enough settleable deals"));

        dealIds = new uint256[](pickedCount);
        for (uint256 i; i < pickedCount; ++i) {
            dealIds[i] = picked[i];
        }
    }

    function settleDealsMixedBatchPreconditions(uint256 settleableDeal, uint256 invalidDeal)
        internal
        returns (uint256[] memory dealIds)
    {
        uint256 settleableDealId = settleDealPreconditions(settleableDeal);
        uint256 len = knownDealIds.length;
        require(len > 1, ClampFail("not enough tracked deals"));

        uint256 start = invalidDeal % len;
        uint256 invalidDealId;
        for (uint256 offset; offset < len; ++offset) {
            uint256 candidate = knownDealIds[(start + offset) % len];
            if (candidate == settleableDealId) continue;
            if (_isSettleableDeal(candidate)) continue;

            Deal memory candidateState = _getDeal(candidate);
            if (candidateState.status == DealStatus.NON_EXISTING) continue;

            invalidDealId = candidate;
            break;
        }

        require(invalidDealId != 0, ClampFail("no invalid tracked deal"));

        dealIds = new uint256[](2);
        dealIds[0] = invalidDealId;
        dealIds[1] = settleableDealId;
    }

    function resolvePaymentUnauthorizedPreconditions(uint256 deal) internal returns (uint256 dealId) {
        (bool found, uint256 pickedDealId, Deal memory dealState) = _pickDealFromBucket(DealBucket.Payable, deal);
        require(found, ClampFail("no payable tracked deal"));
        require(
            dealState.status == DealStatus.PENDING || dealState.status == DealStatus.UNPAID,
            ClampFail("deal not payable")
        );
        if (dealState.status == DealStatus.PENDING) {
            require(block.timestamp <= dealState.paymentDeadline, ClampFail("payment deadline passed"));
        } else {
            require(dealState.disputeBuffer != 0, ClampFail("deal already arbitrated"));
        }

        return pickedDealId;
    }

    function settleDealPreconditions(uint256 deal) internal returns (uint256 dealId) {
        (bool found, uint256 pickedDealId, Deal memory dealState) = _pickDealFromBucket(DealBucket.Settleable, deal);
        require(found, ClampFail("no settleable tracked deal"));

        require(
            dealState.status == DealStatus.PAID || dealState.status == DealStatus.UNPAID,
            ClampFail("deal not settleable")
        );
        require(!_isDealFrozen(pickedDealId), ClampFail("deal frozen"));
        require(!_isOfferFrozen(dealState.offerId), ClampFail("offer frozen"));
        if (dealState.status == DealStatus.PAID) {
            require(!_offerTokenPaused(dealState.offerId), ClampFail("token paused"));
            require(entityRegistry.isAccountEnabled(dealState.buyer), ClampFail("buyer disabled"));
        }
        if (dealState.status == DealStatus.UNPAID) {
            require(block.timestamp > dealState.disputeBuffer, ClampFail("dispute period not expired"));
        }

        return pickedDealId;
    }

    function resolvePaymentsPreconditions(uint256 payableDeal, uint256 expiredDeal)
        internal
        returns (ResolvePaymentsBatchParams memory params)
    {
        uint256 paidDealId = resolvePaymentPreconditions(payableDeal, true);
        uint256 unpaidDealId = resolvePaymentPreconditions(expiredDeal, false);

        params.offerIds = new uint256[](2);
        params.dealIds = new uint256[](2);
        params.resolutions = new PaymentResolutionInput[](2);

        params.dealIds[0] = paidDealId;
        params.dealIds[1] = unpaidDealId;
        params.offerIds[0] = _getDeal(paidDealId).offerId;
        params.offerIds[1] = _getDeal(unpaidDealId).offerId;
        params.resolutions[0] = PaymentResolutionInput({dealId: paidDealId, paid: true});
        params.resolutions[1] = PaymentResolutionInput({dealId: unpaidDealId, paid: false});
    }

    function resolvePaymentsDuplicateUnpaidPreconditions(uint256 deal)
        internal
        returns (ResolvePaymentsDuplicateParams memory params)
    {
        require(
            !marketplace.hasAllRoles(currentActor, marketplace.PAYMENT_HANDLER()),
            ClampFail("actor has payment handler role")
        );

        uint256 dealId = resolvePaymentPreconditions(deal, false);
        Deal memory dealState = _getDeal(dealId);

        params.offerId = dealState.offerId;
        params.dealId = dealId;
        params.resolver = currentActor;
        params.resolutions = new PaymentResolutionInput[](2);
        params.resolutions[0] = PaymentResolutionInput({dealId: dealId, paid: false});
        params.resolutions[1] = PaymentResolutionInput({dealId: dealId, paid: false});
    }

    function resolvePaymentsExpiredPaidPreconditions(uint256 deal)
        internal
        returns (ResolvePaymentsSingleParams memory params)
    {
        require(!_tokenPaused(), ClampFail("token paused"));

        (bool found, uint256 pickedDealId, Deal memory dealState) = _pickDealFromBucket(DealBucket.PendingExpired, deal);
        require(found, ClampFail("no expired pending tracked deal"));
        require(dealState.status == DealStatus.PENDING, ClampFail("deal not pending"));
        require(block.timestamp > dealState.paymentDeadline, ClampFail("payment deadline not passed"));

        params.offerId = dealState.offerId;
        params.dealId = pickedDealId;
        params.resolutions = new PaymentResolutionInput[](1);
        params.resolutions[0] = PaymentResolutionInput({dealId: pickedDealId, paid: true});
    }

    function resolvePaymentsUnauthorizedPreconditions(uint256 expiredDeal, uint256 payableDeal)
        internal
        returns (ResolvePaymentsBatchParams memory params)
    {
        require(
            !marketplace.hasAllRoles(FUZZ_PAYMENT_UNAUTH_CALLER, marketplace.PAYMENT_HANDLER()),
            ClampFail("unauth caller has handler role")
        );

        uint256 unpaidDealId = resolvePaymentPreconditions(expiredDeal, false);
        uint256 paidDealId = resolvePaymentPreconditions(payableDeal, true);

        params.offerIds = new uint256[](2);
        params.dealIds = new uint256[](2);
        params.resolutions = new PaymentResolutionInput[](2);

        params.dealIds[0] = unpaidDealId;
        params.dealIds[1] = paidDealId;
        params.offerIds[0] = _getDeal(unpaidDealId).offerId;
        params.offerIds[1] = _getDeal(paidDealId).offerId;
        params.resolutions[0] = PaymentResolutionInput({dealId: unpaidDealId, paid: false});
        params.resolutions[1] = PaymentResolutionInput({dealId: paidDealId, paid: true});
    }

    function initiateDisputePreconditions(uint256 deal) internal returns (uint256 dealId) {
        (bool found, uint256 pickedDealId, Deal memory dealState) =
            _pickDealFromBucket(DealBucket.UnpaidDisputable, deal);
        require(found, ClampFail("no disputable tracked deal"));

        require(dealState.status == DealStatus.UNPAID, ClampFail("deal not unpaid"));
        require(block.timestamp <= dealState.disputeBuffer, ClampFail("dispute period expired"));

        return pickedDealId;
    }

    function resolveDisputePreconditions(uint256 deal, bool paid)
        internal
        returns (ResolveDisputeParams memory params)
    {
        (bool found, uint256 pickedDealId, Deal memory dealState) = _pickDealFromBucket(DealBucket.InDispute, deal);
        require(found, ClampFail("no in-dispute tracked deal"));

        require(dealState.status == DealStatus.IN_DISPUTE, ClampFail("deal not in dispute"));

        params.dealId = pickedDealId;
        params.status = paid ? DealStatus.PAID : DealStatus.UNPAID;
    }

    function setOfferFrozenPreconditions(uint256 offer) internal returns (OfferOwnerParams memory params) {
        (bool found, uint256 offerId, Offer memory offerState) = _pickOfferFromBucket(OfferBucket.Existing, offer);
        require(found, ClampFail("no tracked offer"));

        require(offerState.owner != address(0), ClampFail("offer missing"));

        params.offerId = offerId;
    }

    function setDealFrozenPreconditions(uint256 deal) internal returns (uint256 dealId) {
        (bool found, uint256 pickedDealId, Deal memory dealState) = _pickDealFromBucket(DealBucket.Existing, deal);
        require(found, ClampFail("no tracked deal"));

        require(dealState.status != DealStatus.NON_EXISTING, ClampFail("deal missing"));

        return pickedDealId;
    }

    function seizeOfferEscrowPreconditions(uint256 offer, uint256 beneficiarySeed)
        internal
        returns (SeizeOfferParams memory params)
    {
        require(!_tokenPaused(), ClampFail("token paused"));

        (bool found, uint256 offerId, Offer memory offerState) = _pickOfferFromBucket(OfferBucket.FrozenSeizable, offer);
        require(found, ClampFail("no seizable frozen offer"));

        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        require(_isOfferFrozen(offerId), ClampFail("offer not frozen"));
        require(
            offerState.amounts.available != 0
                || (offerState.saleMode == SaleMode.INTEREST_DISCOVERY && state.reservedInterestUnits != 0),
            ClampFail("offer has no seizable escrow")
        );

        params.offerId = offerId;
        params.beneficiary = _enabledUserFromSeed(beneficiarySeed);
        params.reason = keccak256(abi.encodePacked("FUZZ_SEIZE_OFFER", offerId));
    }

    function seizeDealPreconditions(uint256 deal, uint256 beneficiarySeed)
        internal
        returns (SeizeDealParams memory params)
    {
        require(!_tokenPaused(), ClampFail("token paused"));

        (bool found, uint256 pickedDealId, Deal memory dealState) = _pickDealFromBucket(DealBucket.FrozenSeizable, deal);
        require(found, ClampFail("no seizable frozen deal"));

        DealStatus status = dealState.status;
        require(_isDealFrozen(pickedDealId), ClampFail("deal not frozen"));
        require(_isOfferFrozen(dealState.offerId), ClampFail("offer not frozen"));
        require(
            status == DealStatus.PENDING || status == DealStatus.UNPAID || status == DealStatus.IN_DISPUTE
                || status == DealStatus.PAID,
            ClampFail("deal status not seizable")
        );

        params.offerId = dealState.offerId;
        params.dealId = pickedDealId;
        params.beneficiary = _enabledUserFromSeed(beneficiarySeed);
        params.reason = keccak256(abi.encodePacked("FUZZ_SEIZE_DEAL", pickedDealId));
    }

    function disputeResolutionFlowPreconditions(uint256 deal, bool paid)
        internal
        returns (DisputeResolutionFlowParams memory params)
    {
        (bool found, uint256 pickedDealId, Deal memory dealState) = _pickDealFromBucket(DealBucket.PendingPayable, deal);
        require(found, ClampFail("no pending payable tracked deal"));

        require(dealState.status == DealStatus.PENDING, ClampFail("deal not pending"));
        require(dealState.paymentDeadline != 0, ClampFail("deal payment deadline missing"));
        require(dealState.disputeBuffer > dealState.paymentDeadline, ClampFail("deal dispute buffer missing"));

        Offer memory offerState = _getOffer(dealState.offerId);
        require(offerState.owner != address(0), ClampFail("offer missing"));

        params.offerId = dealState.offerId;
        params.dealId = pickedDealId;
        params.paymentDeadline = dealState.paymentDeadline;
        params.status = paid ? DealStatus.PAID : DealStatus.UNPAID;
    }

    function _registerOfferPreconditions(uint256 total, uint256 lot, uint256 expiryDelta)
        internal
        returns (RegisterOfferParams memory params)
    {
        require(!_tokenPaused(), ClampFail("token paused"));
        require(bondRegistry.bondStatus(BOND_ISIN) == BondStatus.Issued, ClampFail("bond not issued"));
        require(entityRegistry.isAccountEnabled(currentActor), ClampFail("current actor disabled"));
        require(token.isOperator(currentActor, address(escrowManager)), ClampFail("escrow operator not approved"));

        uint256 balance = token.balanceOf(currentActor, bondTokenId);
        uint256 frozenBalance = token.frozenBalanceOf(currentActor, bondTokenId);
        require(balance > frozenBalance, ClampFail("no free balance"));

        uint256 freeBalance = balance - frozenBalance;

        params.lot = fl.clamp(lot, 1, freeBalance);
        params.totalAmount = fl.clamp(total, params.lot, freeBalance);
        params.totalAmount = params.totalAmount - (params.totalAmount % params.lot);
        require(params.totalAmount != 0, ClampFail("total amount rounds to zero"));

        params.unitPrice = DEFAULT_UNIT_PRICE;
        params.expiry = block.timestamp + expiryDelta;
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _nonOwnerUsers(address owner) internal view returns (address[] memory actors) {
        uint256 count;
        for (uint256 i; i < users.length; ++i) {
            if (users[i] != owner) {
                ++count;
            }
        }

        actors = new address[](count);
        uint256 idx;
        for (uint256 i; i < users.length; ++i) {
            if (users[i] == owner) continue;
            actors[idx] = users[i];
            ++idx;
        }
    }

    function _nonOwnerUserFromSeed(address owner, uint256 seed) internal view returns (address actor) {
        uint256 start = seed % users.length;
        for (uint256 offset; offset < users.length; ++offset) {
            address candidate = users[(start + offset) % users.length];
            if (candidate != owner) return candidate;
        }

        revert ClampFail("no non-owner user");
    }

    function _enabledUserFromSeed(uint256 seed) internal view returns (address actor) {
        uint256 start = seed % users.length;
        for (uint256 offset; offset < users.length; ++offset) {
            address candidate = users[(start + offset) % users.length];
            if (entityRegistry.isAccountEnabled(candidate)) return candidate;
        }

        revert ClampFail("no enabled user");
    }

    function _nonOwnerEnabledUserFromSeed(address owner, uint256 seed) internal view returns (address actor) {
        uint256 start = seed % users.length;
        for (uint256 offset; offset < users.length; ++offset) {
            address candidate = users[(start + offset) % users.length];
            if (candidate != owner && entityRegistry.isAccountEnabled(candidate)) return candidate;
        }

        revert ClampFail("no enabled non-owner user");
    }

    function _isCloseableInterestForOffer(uint256 interestId, uint256 offerId) internal returns (bool) {
        if (interestId == 0) return false;

        _syncInterest(interestId);

        Interest memory interestState = _getInterest(interestId);
        if (interestState.offerId != offerId || interestState.status != InterestStatus.EXPRESSED) return false;

        Offer memory offerState = _getOffer(offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        if (offerState.owner == address(0)) return false;
        if (offerState.saleMode != SaleMode.INTEREST_DISCOVERY) return false;
        if (_isOfferCancelled(offerId)) return false;
        if (state.interestedUnits < state.minSaleUnits) return false;

        return block.timestamp > _interestActivationDeadline(offerState.expiry, state);
    }

    function _isSettleableDeal(uint256 dealId) internal returns (bool) {
        if (dealId == 0) return false;

        _syncDeal(dealId);

        Deal memory dealState = _getDeal(dealId);
        if (dealState.status == DealStatus.PAID) {
            return !_isDealFrozen(dealId) && !_isOfferFrozen(dealState.offerId) && !_offerTokenPaused(dealState.offerId)
                && entityRegistry.isAccountEnabled(dealState.buyer);
        }
        if (dealState.status != DealStatus.UNPAID) return false;
        if (_isDealFrozen(dealId) || _isOfferFrozen(dealState.offerId)) return false;

        return block.timestamp > dealState.disputeBuffer;
    }
}
