// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable gas-strict-inequalities */

import {vm} from "@perimetersec/fuzzlib/src/IHevm.sol";
import {BondStatus} from "src/registry/BondStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {Deal, DealStatus, Interest, InterestDiscoveryState, Offer} from "src/marketplace/MarketStructs.sol";
import {HandlerMarketplace} from "./HandlerMarketplace.sol";

/// @title HandlerMarketplaceLifecycle
/// @notice Directed Marketplace lifecycle handlers for rare deadline-gated branches.
abstract contract HandlerMarketplaceLifecycle is HandlerMarketplace {
    /// @notice Creates a direct-sale pending deal, expires it locally, then resolves it as unpaid.
    function handler_directSaleResolveUnpaid(uint256 offerSeed, uint256 amountSeed) public {
        currentActor = issuer;
        PendingDealSeed memory seed = _seedDirectPendingDeal(offerSeed, amountSeed, false);

        _resolvePendingDealAsUnpaid(seed.dealId);
    }

    /// @notice Creates a direct-sale pending deal, resolves it as unpaid, then settles after the dispute buffer.
    function handler_directSaleSettleUnpaid(uint256 offerSeed, uint256 amountSeed) public {
        currentActor = issuer;
        PendingDealSeed memory seed = _seedDirectPendingDeal(offerSeed, amountSeed, false);

        _resolvePendingDealAsUnpaid(seed.dealId);
        _settleUnpaidDeal(seed.dealId);
    }

    /// @notice Cancels a direct-sale offer with a pending deal, settles it unpaid, then withdraws returned inventory.
    function handler_directSaleWithdrawAfterUnpaidSettlement(uint256 offerSeed, uint256 amountSeed) public {
        currentActor = issuer;
        PendingDealSeed memory seed = _seedCancelledDirectOfferWithPendingDeal(offerSeed, amountSeed);

        _resolvePendingDealAsUnpaid(seed.dealId);
        _settleUnpaidDeal(seed.dealId);

        _syncOffer(seed.offerId);
        require(_flowWithdrawAvailable(seed.offerId), ClampFail("direct withdraw failed"));
    }

    /// @notice Builds one threshold-reached expressed interest, expires it locally, then closes it.
    function handler_interestDiscoveryCloseExpiredInterest(uint256 offerSeed, uint256 interestSeed) public {
        currentActor = issuer;
        (uint256 offerId, uint256[] memory interestIds) =
            _seedThresholdReachedExpressedInterests(offerSeed, interestSeed, 1);

        _warpPastInterestActivationDeadline(offerId);
        _flowCloseExpiredInterests(offerId, interestIds);
    }

    /// @notice Builds multiple threshold-reached expressed interests and closes at least two in one call.
    function handler_interestDiscoveryCloseExpiredInterestsBatch(uint256 offerSeed, uint256 countSeed) public {
        currentActor = issuer;
        uint256 targetCount =
            fl.clamp(countSeed, MIN_CLOSE_EXPIRED_INTERESTS_BATCH_SIZE, MAX_CLOSE_EXPIRED_INTERESTS_BATCH_SIZE);
        (uint256 offerId, uint256[] memory interestIds) =
            _seedThresholdReachedExpressedInterests(offerSeed, countSeed, targetCount);

        _warpPastInterestActivationDeadline(offerId);
        _flowCloseExpiredInterests(offerId, interestIds);
    }

    /// @notice Builds a threshold-reached interest-discovery offer with leftover inventory and withdraws it.
    function handler_interestDiscoveryWithdrawExpiredAvailable(uint256 offerSeed, uint256 interestSeed) public {
        currentActor = issuer;
        uint256 offerId = _seedThresholdReachedInterestWithAvailable(offerSeed, interestSeed);

        _warpIntoInterestActivationWindow(offerId);
        _flowWithdrawInterestAvailable(offerId);
    }

    /// @notice Activates expressed interest after sale end, expires the deal locally, then resolves it as unpaid.
    function handler_activatedInterestResolveUnpaid(uint256 offerSeed, uint256 interestSeed) public {
        currentActor = issuer;
        uint256 dealId = _seedActivatedInterestPendingDeal(offerSeed, interestSeed);

        _resolvePendingDealAsUnpaid(dealId);
    }

    /// @notice Activates expressed interest after sale end, resolves it unpaid, then settles after dispute buffer.
    function handler_activatedInterestSettleUnpaid(uint256 offerSeed, uint256 interestSeed) public {
        currentActor = issuer;
        uint256 dealId = _seedActivatedInterestPendingDeal(offerSeed, interestSeed);

        _resolvePendingDealAsUnpaid(dealId);
        _settleUnpaidDeal(dealId);
    }

    /// @notice Exercises rare Marketplace validation reverts for missing interest and wrong sale-mode calls.
    function handler_marketplaceNegativeValidationSurface(uint256 offerSeed, uint256 amountSeed) public {
        currentActor = issuer;

        _expectMarketplaceRevert(
            abi.encodeWithSelector(marketplace.activateInterest.selector, 0),
            issuer,
            Errors.Marketplace__InterestNotFound.selector
        );

        RegisterInterestOfferParams memory interestParams =
            _directedRegisterInterestOfferWithAvailablePreconditions(offerSeed, amountSeed);
        uint256 interestOfferId = _flowRegisterInterestOffer(interestParams);
        require(interestOfferId != 0, ClampFail("neg interest reg failed"));

        address buyer = _nonOwnerUserFromSeed(issuer, amountSeed);
        _expectMarketplaceRevert(
            abi.encodeWithSelector(marketplace.acceptOffer.selector, interestOfferId, interestParams.lot),
            buyer,
            Errors.Marketplace__NotMarketplaceOffer.selector
        );

        RegisterOfferParams memory directParams =
            _directedRegisterOfferPreconditions(offerSeed, amountSeed, 1, FIXED_FUZZ_EXPIRY_DELTA);
        uint256 directOfferId = _flowRegisterMarketplaceOffer(directParams, false);
        require(directOfferId != 0, ClampFail("neg direct reg failed"));

        _expectMarketplaceRevert(
            abi.encodeWithSelector(marketplace.expressInterest.selector, directOfferId, directParams.lot),
            buyer,
            Errors.Marketplace__NotInterestDiscoveryOffer.selector
        );
    }

    function _seedDirectPendingDeal(uint256 offerSeed, uint256 amountSeed, bool leaveAvailable)
        internal
        returns (PendingDealSeed memory seed)
    {
        address seller = currentActor;
        uint256 minUnits = leaveAvailable ? 2 : 1;
        RegisterOfferParams memory params =
            _directedRegisterOfferPreconditions(offerSeed, amountSeed, minUnits, FIXED_FUZZ_EXPIRY_DELTA);

        seed.offerId = _flowRegisterMarketplaceOffer(params, false);
        require(seed.offerId != 0, ClampFail("direct offer registration failed"));

        currentActor = _nonOwnerUserFromSeed(seller, amountSeed);
        seed.dealId = _flowAcceptOffer(seed.offerId, _directedAcceptAmount(seed.offerId, amountSeed, leaveAvailable));
        currentActor = seller;

        require(seed.dealId != 0, ClampFail("direct deal creation failed"));
    }

    function _seedCancelledDirectOfferWithPendingDeal(uint256 offerSeed, uint256 amountSeed)
        internal
        returns (PendingDealSeed memory seed)
    {
        seed = _seedDirectPendingDeal(offerSeed, amountSeed, true);

        Offer memory offer = _getOffer(seed.offerId);
        require(offer.amounts.inDeals != 0, ClampFail("direct offer no deal stock"));
        require(_flowCancelOffer(seed.offerId), ClampFail("direct offer cancellation failed"));
        require(_isOfferCancelled(seed.offerId), ClampFail("direct offer not cancelled"));
    }

    function _seedThresholdReachedExpressedInterests(uint256 offerSeed, uint256 interestSeed, uint256 targetCount)
        internal
        returns (uint256 offerId, uint256[] memory interestIds)
    {
        address seller = currentActor;
        RegisterInterestOfferParams memory params =
            _directedRegisterInterestOfferPreconditions(offerSeed, interestSeed, targetCount);

        offerId = _flowRegisterInterestOffer(params);
        require(offerId != 0, ClampFail("interest registration failed"));

        interestIds = new uint256[](targetCount);
        for (uint256 i; i < targetCount; ++i) {
            uint256 actorSeed;
            unchecked {
                actorSeed = interestSeed + i;
            }
            currentActor = _nonOwnerUserFromSeed(seller, actorSeed);
            uint256 previousInterestCounter = _getInterestCounter();
            require(_flowExpressInterest(offerId, params.lot), ClampFail("interest expression failed"));

            uint256 interestId = _getInterestCounter();
            require(interestId == previousInterestCounter + 1, ClampFail("interest id not created"));
            interestIds[i] = interestId;
        }

        currentActor = seller;
    }

    function _seedActivatedInterestPendingDeal(uint256 offerSeed, uint256 interestSeed)
        internal
        returns (uint256 dealId)
    {
        (uint256 offerId, uint256[] memory interestIds) =
            _seedThresholdReachedExpressedInterests(offerSeed, interestSeed, 1);

        _warpIntoInterestActivationWindow(offerId);

        Interest memory interest = _getInterest(interestIds[0]);
        address seller = _getOffer(offerId).owner;
        currentActor = interest.investor;
        dealId = _flowActivateInterest(interestIds[0]);
        currentActor = seller;

        require(dealId != 0, ClampFail("interest activation failed"));
        require(_getDeal(dealId).status == DealStatus.PENDING, ClampFail("activated deal not pending"));
    }

    function _seedThresholdReachedInterestWithAvailable(uint256 offerSeed, uint256 interestSeed)
        internal
        returns (uint256 offerId)
    {
        address seller = currentActor;
        RegisterInterestOfferParams memory params =
            _directedRegisterInterestOfferWithAvailablePreconditions(offerSeed, interestSeed);

        offerId = _flowRegisterInterestOffer(params);
        require(offerId != 0, ClampFail("interest avail reg failed"));

        currentActor = _nonOwnerUserFromSeed(seller, interestSeed);
        require(_flowExpressInterest(offerId, params.minSaleUnits), ClampFail("interest avail express failed"));
        currentActor = seller;

        Offer memory offer = _getOffer(offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        require(state.interestedUnits >= state.minSaleUnits, ClampFail("interest threshold not reached"));
        require(offer.amounts.available != 0, ClampFail("interest no available inventory"));
    }

    function _resolvePendingDealAsUnpaid(uint256 dealId) internal {
        Deal memory deal = _getDeal(dealId);
        require(deal.status == DealStatus.PENDING, ClampFail("deal not pending"));
        require(deal.paymentDeadline != 0, ClampFail("deal payment deadline missing"));

        _warpJustPast(deal.paymentDeadline);
        _syncDeal(dealId);

        require(_flowResolvePayment(deal.offerId, dealId, false), ClampFail("resolve unpaid failed"));
    }

    function _settleUnpaidDeal(uint256 dealId) internal {
        Deal memory deal = _getDeal(dealId);
        require(deal.status == DealStatus.UNPAID, ClampFail("deal not unpaid"));
        require(deal.disputeBuffer != 0, ClampFail("deal dispute buffer missing"));

        _warpJustPast(deal.disputeBuffer);
        _syncDeal(dealId);
        _syncOffer(deal.offerId);

        require(_flowSettleDeal(dealId), ClampFail("settle unpaid failed"));
    }

    function _flowWithdrawInterestAvailable(uint256 offerId) internal {
        address seller = _getOffer(offerId).owner;
        address[] memory actorsToUpdate = _singleActorArray(seller);
        uint256[] memory offerIdsToUpdate = _singleUintArray(offerId);
        _before(actorsToUpdate, offerIdsToUpdate, _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.withdrawAvailable.selector, offerId), seller
        );

        withdrawInterestAvailablePostconditions(success, returnData, actorsToUpdate, offerIdsToUpdate);

        _syncOffer(offerId);
        _syncKnownInterestsForOffer(offerId);
        require(success, ClampFail("interest withdraw failed"));
    }

    function _expectMarketplaceRevert(bytes memory callData, address actor, bytes4 expectedSelector) internal {
        (bool success, bytes memory returnData) = fl.doFunctionCall(address(marketplace), callData, actor);
        marketplaceExpectedRevertPostconditions(success, returnData, expectedSelector);
    }

    function _warpIntoInterestActivationWindow(uint256 offerId) internal {
        Offer memory offer = _getOffer(offerId);

        _warpJustPast(offer.expiry);
        _syncOffer(offerId);
        _syncKnownInterestsForOffer(offerId);
    }

    function _warpPastInterestActivationDeadline(uint256 offerId) internal {
        Offer memory offer = _getOffer(offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        uint256 closeDeadline = _interestActivationDeadline(offer.expiry, state);

        _warpJustPast(closeDeadline);
        _syncOffer(offerId);
        _syncKnownInterestsForOffer(offerId);
    }

    function _warpJustPast(uint256 deadline) internal {
        require(deadline != type(uint256).max, ClampFail("deadline overflow"));

        if (block.timestamp <= deadline) {
            vm.warp(deadline + 1);
        }
    }

    function _directedRegisterInterestOfferPreconditions(uint256 totalSeed, uint256 lotSeed, uint256 targetCount)
        internal
        returns (RegisterInterestOfferParams memory params)
    {
        RegisterOfferParams memory base =
            _directedRegisterOfferPreconditions(totalSeed, lotSeed, targetCount, OFFER_EXPIRY_THRESHOLD);

        params.totalAmount = base.totalAmount;
        params.lot = base.lot;
        params.unitPrice = base.unitPrice;
        params.expiry = base.expiry;
        params.minSaleUnits = targetCount * base.lot;
    }

    function _directedRegisterInterestOfferWithAvailablePreconditions(uint256 totalSeed, uint256 lotSeed)
        internal
        returns (RegisterInterestOfferParams memory params)
    {
        RegisterOfferParams memory base =
            _directedRegisterOfferPreconditions(totalSeed, lotSeed, 2, OFFER_EXPIRY_THRESHOLD);

        params.totalAmount = base.totalAmount;
        params.lot = base.lot;
        params.unitPrice = base.unitPrice;
        params.expiry = base.expiry;
        params.minSaleUnits = base.lot;
    }

    function _directedRegisterOfferPreconditions(
        uint256 totalSeed,
        uint256 lotSeed,
        uint256 minUnits,
        uint256 expiryDelta
    ) internal returns (RegisterOfferParams memory params) {
        require(minUnits != 0, ClampFail("zero min units"));
        require(!_tokenPaused(), ClampFail("token paused"));
        require(bondRegistry.bondStatus(BOND_ISIN) == BondStatus.Issued, ClampFail("bond not issued"));
        require(token.isOperator(currentActor, address(escrowManager)), ClampFail("escrow operator not approved"));

        uint256 balance = token.balanceOf(currentActor, bondTokenId);
        uint256 frozenBalance = token.frozenBalanceOf(currentActor, bondTokenId);
        require(balance > frozenBalance, ClampFail("no free balance"));

        uint256 freeBalance = balance - frozenBalance;
        require(freeBalance >= minUnits, ClampFail("insufficient free balance"));

        uint256 maxLot = fl.min(freeBalance / minUnits, MAX_INTEREST_DISCOVERY_MIN_SALE_UNITS);
        params.lot = fl.clamp(lotSeed, 1, maxLot);

        uint256 maxUnits = fl.min(freeBalance / params.lot, MAX_INTEREST_DISCOVERY_MIN_SALE_UNITS);
        uint256 units = fl.clamp(totalSeed, minUnits, maxUnits);

        params.totalAmount = units * params.lot;
        params.unitPrice = DEFAULT_UNIT_PRICE;
        params.expiry = block.timestamp + expiryDelta;
    }

    function _directedAcceptAmount(uint256 offerId, uint256 amountSeed, bool leaveAvailable)
        internal
        returns (uint256 amount)
    {
        Offer memory offer = _getOffer(offerId);
        uint256 maxUnits = offer.amounts.available / offer.lot;
        require(maxUnits != 0, ClampFail("offer has no purchasable units"));

        uint256 maxAcceptedUnits = leaveAvailable && maxUnits > 1 ? maxUnits - 1 : maxUnits;
        uint256 units = fl.clamp(amountSeed, 1, maxAcceptedUnits);
        amount = units * offer.lot;
    }
}
