// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {vm} from "@perimetersec/fuzzlib/src/IHevm.sol";
import {CounterOfferInput, Deal, DealStatus, Interest, OfferInput, SaleMode} from "src/marketplace/MarketStructs.sol";
import {PreconditionsMarketplace} from "../preconditions/PreconditionsMarketplace.sol";
import {PostconditionsMarketplace} from "../postconditions/PostconditionsMarketplace.sol";

/// @title HandlerMarketplace
/// @notice Stateful fuzz handlers for the Marketplace vertical slice.
abstract contract HandlerMarketplace is PreconditionsMarketplace, PostconditionsMarketplace {
    /// @notice Attempts to register a new marketplace offer for the current actor.
    function handler_registerMarketplaceOffer(uint256 total, uint256 lot, bool allowCounterOffers)
        public
        setCurrentActor
    {
        RegisterOfferParams memory params = registerMarketplaceOfferPreconditions(total, lot);
        _flowRegisterMarketplaceOffer(params, allowCounterOffers);
    }

    /// @notice Attempts to register a new redemption offer for the current actor.
    function handler_registerRedemptionOffer(uint256 total, uint256 lot) public setCurrentActor {
        RegisterRedemptionOfferParams memory params = registerRedemptionOfferPreconditions(total, lot);

        address[] memory actorsToUpdate = _singleActorArray(currentActor);
        uint256[] memory offerIdsToUpdate = _emptyUintArray();
        _before(actorsToUpdate, offerIdsToUpdate, _emptyUintArray());

        OfferInput memory input = OfferInput({
            tokenAddress: address(token),
            tokenId: bondTokenId,
            totalAmount: params.totalAmount,
            lot: params.lot,
            unitPrice: params.unitPrice,
            currency: bytes3(bytes(BOND_CURRENCY)),
            expiry: params.expiry,
            allowCounterOffers: false,
            allowedBuyers: params.allowedBuyers,
            saleMode: SaleMode.REDEMPTION,
            minSaleUnits: 0
        });

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.registerOffer.selector, input), currentActor
        );

        if (success) {
            uint256 offerId = _decodeUint256(returnData);
            _trackOfferId(offerId);
            offerIdsToUpdate = _singleUintArray(offerId);
        }

        registerOfferPostconditions(success, returnData, actorsToUpdate, offerIdsToUpdate, input);

        if (success) {
            _syncOffer(offerIdsToUpdate[0]);
        }
    }

    /// @notice Attempts to register a new interest-discovery offer for the current actor.
    function handler_registerInterestOffer(uint256 total, uint256 lot, uint256 minSaleUnitsSeed)
        public
        setCurrentActor
    {
        RegisterInterestOfferParams memory params = registerInterestOfferPreconditions(total, lot, minSaleUnitsSeed);
        _flowRegisterInterestOffer(params);
    }

    /// @notice Attempts to update the per-user counter-offer cap as the harness admin.
    function handler_setMaxCounterOffersPerUser(uint256 maxCounterOffers) public {
        uint256 previousMaxCounterOffers = _getMaxCounterOffersPerUser();

        _before(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace),
            abi.encodeWithSelector(marketplace.setMaxCounterOffersPerUser.selector, maxCounterOffers),
            address(this)
        );

        setMaxCounterOffersPerUserPostconditions(success, returnData, previousMaxCounterOffers, maxCounterOffers);
    }

    /// @notice Attempts to accept a tracked direct-sale offer as the current actor.
    function handler_acceptOffer(uint256 offer, uint256 amount) public setCurrentActor {
        AcceptOfferParams memory params = acceptOfferPreconditions(offer, amount);
        _flowAcceptOffer(params.offerId, params.amount);
    }

    /// @notice Attempts to express interest on a tracked interest-discovery offer.
    function handler_expressInterest(uint256 offer, uint256 amount) public setCurrentActor {
        ExpressInterestParams memory params = expressInterestPreconditions(offer, amount);
        _flowExpressInterest(params.offerId, params.amount);
    }

    /// @notice Expresses interest while keeping the offer below its minimum sale threshold.
    function handler_expressInterestBelowThreshold(uint256 offer, uint256 amount) public setCurrentActor {
        ExpressInterestParams memory params = expressInterestBelowThresholdPreconditions(offer, amount);
        _flowExpressInterest(params.offerId, params.amount);
    }

    /// @notice Attempts to activate a tracked expressed interest into a deal.
    function handler_activateInterest(uint256 interest) public setCurrentActor {
        uint256 interestId = activateInterestPreconditions(interest);
        _flowActivateInterest(interestId);
    }

    /// @notice Attempts to close one tracked expired expressed interest.
    function handler_closeExpiredInterest(uint256 interest) public {
        CloseInterestParams memory params = closeExpiredInterestPreconditions(interest);
        _flowCloseExpiredInterests(params.offerId, _singleUintArray(params.interestId));
    }

    /// @notice Attempts to close two or three tracked expired expressed interests in one call.
    function handler_closeExpiredInterestsBatch(uint256 interest, uint256 countSeed) public {
        CloseInterestBatchParams memory params = closeExpiredInterestsBatchPreconditions(interest, countSeed);
        _flowCloseExpiredInterests(params.offerId, params.interestIds);
    }

    /// @notice Attempts to withdraw available inventory from a cancelled tracked direct offer.
    function handler_withdrawAvailable(uint256 offer) public {
        OfferOwnerParams memory params = withdrawAvailablePreconditions(offer);
        _flowWithdrawAvailable(params.offerId);
    }

    /// @notice Attempts to withdraw inventory from an expired interest-discovery offer.
    function handler_withdrawInterestAvailable(uint256 offer) public {
        OfferOwnerParams memory params = withdrawInterestAvailablePreconditions(offer);
        address seller = _getOffer(params.offerId).owner;

        address[] memory actorsToUpdate = _singleActorArray(seller);
        uint256[] memory offerIdsToUpdate = _singleUintArray(params.offerId);
        _before(actorsToUpdate, offerIdsToUpdate, _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.withdrawAvailable.selector, params.offerId), seller
        );

        withdrawInterestAvailablePostconditions(success, returnData, actorsToUpdate, offerIdsToUpdate);

        _syncOffer(params.offerId);
        _syncKnownInterestsForOffer(params.offerId);
    }

    /// @notice Attempts failed-book withdrawal and expects the canonical cancellation path to be required.
    function handler_withdrawInterestAvailableBelowThreshold(uint256 offer) public {
        OfferOwnerParams memory params = withdrawInterestAvailableBelowThresholdPreconditions(offer);
        address seller = _getOffer(params.offerId).owner;

        _before(_singleActorArray(seller), _singleUintArray(params.offerId), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.withdrawAvailable.selector, params.offerId), seller
        );

        withdrawInterestAvailableBelowThresholdPostconditions(success, returnData);

        _syncOffer(params.offerId);
        _syncKnownInterestsForOffer(params.offerId);
    }

    /// @notice Attempts to create a counter offer against a tracked direct-sale offer.
    function handler_createCounterOffer(uint256 offer, uint256 amount) public setCurrentActor {
        CounterOfferParams memory params = createCounterOfferPreconditions(offer, amount);

        uint256[] memory offerIdsToUpdate = _singleUintArray(params.offerId);
        _before(_emptyAddressArray(), offerIdsToUpdate, _emptyUintArray());

        CounterOfferInput memory input = CounterOfferInput({
            offerId: params.offerId, expiry: params.expiry, amount: params.amount, unitPrice: params.unitPrice
        });

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.createCounterOffer.selector, input), currentActor
        );

        uint256[] memory dealIdsToUpdate = _dealIdsFromSuccessfulReturn(success, returnData);

        createCounterOfferPostconditions(success, returnData, offerIdsToUpdate, dealIdsToUpdate, params);

        _syncOffer(params.offerId);
        if (success) {
            _syncDeal(dealIdsToUpdate[0]);
        }
    }

    /// @notice Attempts to cancel a tracked direct-sale offer owned by the current actor.
    function handler_cancelOffer(uint256 offer) public setCurrentActor {
        OfferOwnerParams memory params = cancelOfferPreconditions(offer);
        _flowCancelOffer(params.offerId);
    }

    /// @notice Attempts to cancel an expired failed interest-discovery offer as its recorded seller.
    function handler_cancelFailedInterestOffer(uint256 offer) public {
        OfferOwnerParams memory params = cancelFailedInterestOfferPreconditions(offer);
        address seller = _getOffer(params.offerId).owner;

        address[] memory actorsToUpdate = _singleActorArray(seller);
        uint256[] memory offerIdsToUpdate = _singleUintArray(params.offerId);
        _before(actorsToUpdate, offerIdsToUpdate, _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.cancelOffer.selector, params.offerId), seller
        );

        cancelFailedInterestOfferPostconditions(success, returnData, actorsToUpdate, offerIdsToUpdate);

        _syncOffer(params.offerId);
        _syncKnownInterestsForOffer(params.offerId);
    }

    /// @notice Attempts to cancel an expired failed interest-discovery offer via INTEREST_DISCOVERY_OPERATOR.
    function handler_cancelFailedInterestOfferByOperator(uint256 offer) public {
        OfferOwnerParams memory params = cancelFailedInterestOfferByOperatorPreconditions(offer);
        address seller = _getOffer(params.offerId).owner;

        address[] memory actorsToUpdate = _singleActorArray(seller);
        uint256[] memory offerIdsToUpdate = _singleUintArray(params.offerId);
        _before(actorsToUpdate, offerIdsToUpdate, _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace),
            abi.encodeWithSelector(marketplace.cancelOffer.selector, params.offerId),
            address(this)
        );

        cancelFailedInterestOfferPostconditions(success, returnData, actorsToUpdate, offerIdsToUpdate);

        _syncOffer(params.offerId);
        _syncKnownInterestsForOffer(params.offerId);
    }

    /// @notice Attempts to cancel a tracked counter offer as its recorded buyer.
    function handler_cancelCounterOffer(uint256 deal) public {
        uint256 dealId = cancelCounterOfferPreconditions(deal);

        Deal memory dealState = _getDeal(dealId);
        uint256[] memory offerIdsToUpdate = _singleUintArray(dealState.offerId);
        uint256[] memory dealIdsToUpdate = _singleUintArray(dealId);
        _before(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace),
            abi.encodeWithSelector(marketplace.cancelCounterOffer.selector, dealId),
            dealState.buyer
        );

        cancelCounterOfferPostconditions(success, returnData, offerIdsToUpdate, dealIdsToUpdate);

        Deal memory updatedDeal = _getDeal(dealId);
        _syncDeal(dealId);
        _syncOffer(updatedDeal.offerId);
    }

    /// @notice Attempts to resolve a tracked counter offer as the original seller.
    function handler_resolveCounterOffer(uint256 deal, bool accepted) public {
        uint256 dealId = resolveCounterOfferPreconditions(deal, accepted);

        Deal memory dealState = _getDeal(dealId);
        address seller = _getOffer(dealState.offerId).owner;
        uint256[] memory offerIdsToUpdate = _singleUintArray(dealState.offerId);
        uint256[] memory dealIdsToUpdate = _singleUintArray(dealId);
        _before(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace),
            abi.encodeWithSelector(marketplace.resolveCounterOffer.selector, dealId, accepted),
            seller
        );

        resolveCounterOfferPostconditions(
            success, returnData, offerIdsToUpdate, dealIdsToUpdate, dealState.amount, accepted
        );

        Deal memory updatedDeal = _getDeal(dealId);
        _syncDeal(dealId);
        _syncOffer(updatedDeal.offerId);
    }

    /// @notice Attempts to resolve payment for a tracked payable deal.
    function handler_resolvePayment(uint256 deal, bool paid) public {
        uint256 dealId = resolvePaymentPreconditions(deal, paid);
        Deal memory dealState = _getDeal(dealId);
        _flowResolvePayment(dealState.offerId, dealId, paid);
    }

    /// @notice Resolves one paid deal and one expired unpaid deal through the batch surface.
    function handler_resolvePayments(uint256 payableDeal, uint256 expiredDeal) public {
        ResolvePaymentsBatchParams memory params = resolvePaymentsPreconditions(payableDeal, expiredDeal);

        _before(_emptyAddressArray(), params.offerIds, params.dealIds);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.resolvePayments.selector, params.resolutions)
        );

        resolvePaymentsPostconditions(success, returnData, params.offerIds, params.dealIds);

        for (uint256 i; i < params.dealIds.length; ++i) {
            _syncDeal(params.dealIds[i]);
        }
    }

    /// @notice Resolves the same expired deal twice through `resolvePayments` from an unprivileged caller.
    function handler_resolvePaymentsDuplicateUnpaid(uint256 deal) public setCurrentActor {
        ResolvePaymentsDuplicateParams memory params = resolvePaymentsDuplicateUnpaidPreconditions(deal);

        uint256[] memory offerIdsToUpdate = _singleUintArray(params.offerId);
        uint256[] memory dealIdsToUpdate = _singleUintArray(params.dealId);
        _before(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace),
            abi.encodeWithSelector(marketplace.resolvePayments.selector, params.resolutions),
            params.resolver
        );

        resolvePaymentsDuplicateUnpaidPostconditions(
            success, returnData, offerIdsToUpdate, dealIdsToUpdate, params.resolver
        );

        _syncDeal(params.dealId);
    }

    /// @notice Attempts to resolve an expired pending deal as paid through `resolvePayments`, expecting a clean skip.
    function handler_resolvePaymentsExpiredPaid(uint256 deal) public {
        ResolvePaymentsSingleParams memory params = resolvePaymentsExpiredPaidPreconditions(deal);

        uint256[] memory offerIdsToUpdate = _singleUintArray(params.offerId);
        uint256[] memory dealIdsToUpdate = _singleUintArray(params.dealId);
        _before(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.resolvePayments.selector, params.resolutions)
        );

        resolvePaymentsExpiredPaidPostconditions(success, returnData, offerIdsToUpdate, dealIdsToUpdate);

        _syncDeal(params.dealId);
    }

    /// @notice Attempts to batch-resolve a paid item from a caller without PAYMENT_HANDLER.
    function handler_resolvePaymentsUnauthorized(uint256 expiredDeal, uint256 payableDeal) public {
        ResolvePaymentsBatchParams memory params = resolvePaymentsUnauthorizedPreconditions(expiredDeal, payableDeal);

        _before(_emptyAddressArray(), params.offerIds, params.dealIds);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace),
            abi.encodeWithSelector(marketplace.resolvePayments.selector, params.resolutions),
            FUZZ_PAYMENT_UNAUTH_CALLER
        );

        resolvePaymentsUnauthorizedPostconditions(success, returnData, params.offerIds, params.dealIds);

        for (uint256 i; i < params.dealIds.length; ++i) {
            _syncDeal(params.dealIds[i]);
        }
    }

    /// @notice Attempts to mark a payable deal as paid from a caller without PAYMENT_HANDLER.
    function handler_resolvePaymentUnauthorized(uint256 deal) public {
        uint256 dealId = resolvePaymentUnauthorizedPreconditions(deal);

        Deal memory dealState = _getDeal(dealId);
        uint256[] memory offerIdsToUpdate = _singleUintArray(dealState.offerId);
        uint256[] memory dealIdsToUpdate = _singleUintArray(dealId);
        _before(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace),
            abi.encodeWithSelector(marketplace.resolvePayment.selector, dealId, true),
            FUZZ_PAYMENT_UNAUTH_CALLER
        );

        resolvePaymentUnauthorizedPostconditions(success, returnData);

        _syncDeal(dealId);
    }

    /// @notice Attempts to settle a tracked paid or timed-out unpaid deal.
    function handler_settleDeal(uint256 deal) public {
        uint256 dealId = settleDealPreconditions(deal);
        _flowSettleDeal(dealId);
    }

    /// @notice Attempts to settle multiple tracked paid or timed-out unpaid deals in one call.
    function handler_settleDealsBatch(uint256 deal, uint256 countSeed) public {
        uint256[] memory dealIds = settleDealsBatchPreconditions(deal, countSeed);

        address[] memory actorsToUpdate = new address[](dealIds.length);
        uint256[] memory offerIdsToUpdate = new uint256[](dealIds.length);
        for (uint256 i; i < dealIds.length; ++i) {
            Deal memory dealState = _getDeal(dealIds[i]);
            actorsToUpdate[i] = dealState.buyer;
            offerIdsToUpdate[i] = dealState.offerId;
        }
        _before(actorsToUpdate, offerIdsToUpdate, dealIds);

        (bool success, bytes memory returnData) =
            fl.doFunctionCall(address(marketplace), abi.encodeWithSelector(marketplace.settleDeals.selector, dealIds));

        settleDealsBatchPostconditions(success, returnData, actorsToUpdate, offerIdsToUpdate, dealIds);

        for (uint256 i; i < dealIds.length; ++i) {
            Deal memory updatedDeal = _getDeal(dealIds[i]);
            _syncDeal(dealIds[i]);
            _syncOffer(updatedDeal.offerId);
        }
    }

    /// @notice Attempts to settle one valid deal and skip one invalid deal in a batch.
    function handler_settleDealsMixedBatch(uint256 settleableDeal, uint256 invalidDeal) public {
        uint256[] memory dealIds = settleDealsMixedBatchPreconditions(settleableDeal, invalidDeal);

        address[] memory actorsToUpdate = new address[](dealIds.length);
        uint256[] memory offerIdsToUpdate = new uint256[](dealIds.length);
        for (uint256 i; i < dealIds.length; ++i) {
            Deal memory dealState = _getDeal(dealIds[i]);
            actorsToUpdate[i] = dealState.buyer;
            offerIdsToUpdate[i] = dealState.offerId;
        }
        _before(actorsToUpdate, offerIdsToUpdate, dealIds);

        (bool success, bytes memory returnData) =
            fl.doFunctionCall(address(marketplace), abi.encodeWithSelector(marketplace.settleDeals.selector, dealIds));

        settleDealsMixedBatchPostconditions(success, returnData, actorsToUpdate, offerIdsToUpdate, dealIds);

        for (uint256 i; i < dealIds.length; ++i) {
            Deal memory updatedDeal = _getDeal(dealIds[i]);
            _syncDeal(dealIds[i]);
            _syncOffer(updatedDeal.offerId);
        }
    }

    /// @notice Attempts to initiate a dispute for a tracked unpaid deal as its recorded buyer.
    function handler_initiateDispute(uint256 deal) public {
        uint256 dealId = initiateDisputePreconditions(deal);
        Deal memory dealState = _getDeal(dealId);
        _flowInitiateDispute(dealState.offerId, dealId);
    }

    /// @notice Attempts to resolve a tracked in-dispute deal as the harness arbitrator.
    function handler_resolveDispute(uint256 deal, bool paid) public {
        ResolveDisputeParams memory params = resolveDisputePreconditions(deal, paid);
        Deal memory dealState = _getDeal(params.dealId);
        _flowResolveDispute(dealState.offerId, params.dealId, params.status);
    }

    /// @notice Attempts to set the frozen flag on a tracked offer as the harness freezer.
    function handler_setOfferFrozen(uint256 offer, bool frozen) public {
        OfferOwnerParams memory params = setOfferFrozenPreconditions(offer);
        _flowSetOfferFrozen(params.offerId, frozen);
    }

    /// @notice Attempts to set the frozen flag on a tracked deal as the harness freezer.
    function handler_setDealFrozen(uint256 deal, bool frozen) public {
        uint256 dealId = setDealFrozenPreconditions(deal);
        Deal memory dealState = _getDeal(dealId);
        _flowSetDealFrozen(dealState.offerId, dealId, frozen);
    }

    /// @notice Attempts to seize non-deal escrow balance from a tracked frozen offer.
    function handler_seizeOfferEscrow(uint256 offer, uint256 beneficiarySeed) public {
        SeizeOfferParams memory params = seizeOfferEscrowPreconditions(offer, beneficiarySeed);
        _flowSeizeOfferEscrow(params.offerId, params.beneficiary, params.reason);
    }

    /// @notice Attempts to seize escrowed deal inventory from a tracked frozen deal and parent offer.
    function handler_seizeDeal(uint256 deal, uint256 beneficiarySeed) public {
        SeizeDealParams memory params = seizeDealPreconditions(deal, beneficiarySeed);
        _flowSeizeDeal(params.offerId, params.dealId, params.beneficiary, params.reason);
    }

    /// @notice Deterministically advances a pending deal through UNPAID, IN_DISPUTE, then arbitration.
    function handler_disputeResolutionFlow(uint256 deal, bool paid) public {
        DisputeResolutionFlowParams memory params = disputeResolutionFlowPreconditions(deal, paid);

        vm.warp(params.paymentDeadline + 1);

        if (!_flowResolvePayment(params.offerId, params.dealId, false)) return;
        if (!_flowInitiateDispute(params.offerId, params.dealId)) return;
        _flowResolveDispute(params.offerId, params.dealId, params.status);
    }

    /// @notice Creates an interest-discovery offer, reserves interest, freezes it, then seizes the reserved bucket.
    function handler_seizeOfferReservedInterest(uint256 total, uint256 lot, uint256 beneficiarySeed)
        public
        setCurrentActor
    {
        RegisterInterestOfferParams memory params = registerInterestOfferPreconditions(total, lot, 0);
        address seller = currentActor;

        uint256 offerId = _flowRegisterInterestOffer(params);
        if (offerId == 0) return;

        currentActor = _nonOwnerEnabledUserFromSeed(seller, beneficiarySeed);
        bool expressed = _flowExpressInterest(offerId, params.lot);
        currentActor = seller;
        if (!expressed) return;

        address beneficiary = _enabledUserFromSeed(beneficiarySeed);
        if (!_flowSetOfferFrozen(offerId, true)) return;
        _flowSeizeOfferEscrow(offerId, beneficiary, keccak256(abi.encodePacked("FUZZ_SEIZE_RESERVED", offerId)));
    }

    /// @notice Creates a pending deal, marks it PAID, freezes both sides, then seizes that paid deal.
    function handler_seizePaidDeal(uint256 total, uint256 lot) public setCurrentActor {
        RegisterOfferParams memory params = registerMarketplaceOfferPreconditions(total, lot);
        address seller = currentActor;

        uint256 offerId = _flowRegisterMarketplaceOffer(params, false);
        if (offerId == 0) return;

        currentActor = _nonOwnerEnabledUserFromSeed(seller, lot);
        uint256 dealId = _flowAcceptOffer(offerId, params.lot);
        currentActor = seller;
        if (dealId == 0) return;

        address beneficiary = _enabledUserFromSeed(lot);
        if (!_flowResolvePayment(offerId, dealId, true)) return;
        if (!_flowSetOfferFrozen(offerId, true)) return;
        if (!_flowSetDealFrozen(offerId, dealId, true)) return;
        _flowSeizeDeal(offerId, dealId, beneficiary, keccak256(abi.encodePacked("FUZZ_SEIZE_PAID", dealId)));
    }

    /// @notice Registers a direct-sale offer, cancels it with leftover inventory, then withdraws the surplus.
    /// @dev Deterministically drives the direct-sale branch of `withdrawAvailable` (cancelled offer with available
    ///      amount), which the random walk reaches only rarely because it requires the combined register/cancel state.
    function handler_withdrawCancelledDirectOffer(uint256 total, uint256 lot) public setCurrentActor {
        RegisterOfferParams memory params = registerMarketplaceOfferPreconditions(total, lot);

        uint256 offerId = _flowRegisterMarketplaceOffer(params, false);
        if (offerId == 0) return;

        if (!_flowCancelOffer(offerId)) return;
        _flowWithdrawAvailable(offerId);
    }

    /// @notice Exercises Marketplace admin and view surfaces without changing core fuzz parameters.
    function handler_marketplaceAdminSurface() public {
        _expectMarketplaceAdminCall(abi.encodeWithSelector(marketplace.getBondRegistry.selector));
        _expectMarketplaceAdminCall(abi.encodeWithSelector(marketplace.getEscrowManager.selector));
        _expectMarketplaceAdminCall(abi.encodeWithSelector(marketplace.getEntityRegistry.selector));
        _expectMarketplaceAdminCall(abi.encodeWithSelector(marketplace.getConfigAndCounters.selector));
        _expectMarketplaceAdminCall(
            abi.encodeWithSelector(marketplace.isCurrencyAllowed.selector, bytes3(bytes(BOND_CURRENCY)))
        );

        uint256[] memory typeIds = new uint256[](2);
        typeIds[0] = NATURAL_PERSON_ENTITY;
        typeIds[1] = DEUSS_PROTOCOL_ENTITY;
        _expectMarketplaceAdminCall(abi.encodeWithSelector(marketplace.setAllowedEntityTypes.selector, typeIds, false));
        _expectMarketplaceAdminCall(
            abi.encodeWithSelector(marketplace.setAllowedEntityType.selector, BROKER_ENTITY, true)
        );

        _exerciseMarketplaceConfigSetters();

        bytes3 tempCurrency = bytes3("FUZ");
        if (marketplace.isCurrencyAllowed(tempCurrency)) {
            _expectMarketplaceAdminCall(abi.encodeWithSelector(marketplace.removeCurrency.selector, tempCurrency));
        }
        _expectMarketplaceAdminCall(abi.encodeWithSelector(marketplace.addCurrency.selector, tempCurrency));
        _expectMarketplaceAdminCall(abi.encodeWithSelector(marketplace.removeCurrency.selector, tempCurrency));

        (bool setBondRegistrySuccess, bytes memory setBondRegistryReturnData) = fl.doFunctionCall(
            address(marketplace),
            abi.encodeWithSelector(marketplace.setBondRegistry.selector, address(bondRegistry)),
            address(this)
        );
        marketplaceSetBondRegistryPostconditions(setBondRegistrySuccess, setBondRegistryReturnData);
    }

    /// @notice Re-applies every Marketplace configuration setter at its canonical value as the harness admin.
    /// @dev Split out of `handler_marketplaceAdminSurface` to keep that handler within the function-length budget.
    ///      `setMaxOfferLifetime` is re-applied with `MAX_OFFER_LIFETIME`, matching the setup value so the
    ///      offer-expiry cross-check never reverts.
    function _exerciseMarketplaceConfigSetters() private {
        _expectMarketplaceAdminCall(abi.encodeWithSelector(marketplace.setAssetManager.selector, address(assetManager)));
        _expectMarketplaceAdminCall(
            abi.encodeWithSelector(marketplace.setOfferExpiryThreshold.selector, OFFER_EXPIRY_THRESHOLD)
        );
        _expectMarketplaceAdminCall(
            abi.encodeWithSelector(marketplace.setMaxOfferLifetime.selector, MAX_OFFER_LIFETIME)
        );
        _expectMarketplaceAdminCall(
            abi.encodeWithSelector(marketplace.setMarketplacePaymentExpiryThreshold.selector, PAYMENT_EXPIRY_THRESHOLD)
        );
        _expectMarketplaceAdminCall(
            abi.encodeWithSelector(
                marketplace.setInterestDiscoveryPaymentExpiryThreshold.selector, PAYMENT_EXPIRY_THRESHOLD
            )
        );
        _expectMarketplaceAdminCall(
            abi.encodeWithSelector(marketplace.setRedemptionPaymentExpiryThreshold.selector, PAYMENT_EXPIRY_THRESHOLD)
        );
        _expectMarketplaceAdminCall(
            abi.encodeWithSelector(marketplace.setDisputeBufferPeriod.selector, DISPUTE_BUFFER_PERIOD)
        );
        _expectMarketplaceAdminCall(
            abi.encodeWithSelector(marketplace.setMaxCounterOffersPerUser.selector, MAX_COUNTER_OFFERS_PER_USER)
        );
    }

    function _flowRegisterMarketplaceOffer(RegisterOfferParams memory params, bool allowCounterOffers)
        internal
        returns (uint256 offerId)
    {
        OfferInput memory input = OfferInput({
            tokenAddress: address(token),
            tokenId: bondTokenId,
            totalAmount: params.totalAmount,
            lot: params.lot,
            unitPrice: params.unitPrice,
            // forge-lint: disable-next-line(unsafe-typecast)
            currency: bytes3(bytes(BOND_CURRENCY)),
            expiry: params.expiry,
            allowCounterOffers: allowCounterOffers,
            allowedBuyers: _emptyAddressArray(),
            saleMode: SaleMode.MARKETPLACE,
            minSaleUnits: 0
        });

        return _flowRegisterOffer(input);
    }

    function _flowRegisterInterestOffer(RegisterInterestOfferParams memory params) internal returns (uint256 offerId) {
        OfferInput memory input = OfferInput({
            tokenAddress: address(token),
            tokenId: bondTokenId,
            totalAmount: params.totalAmount,
            lot: params.lot,
            unitPrice: params.unitPrice,
            // forge-lint: disable-next-line(unsafe-typecast)
            currency: bytes3(bytes(BOND_CURRENCY)),
            expiry: params.expiry,
            allowCounterOffers: false,
            allowedBuyers: _emptyAddressArray(),
            saleMode: SaleMode.INTEREST_DISCOVERY,
            minSaleUnits: params.minSaleUnits
        });

        return _flowRegisterOffer(input);
    }

    function _flowRegisterOffer(OfferInput memory input) internal returns (uint256 offerId) {
        address[] memory actorsToUpdate = _singleActorArray(currentActor);
        uint256[] memory offerIdsToUpdate = _emptyUintArray();
        _before(actorsToUpdate, offerIdsToUpdate, _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.registerOffer.selector, input), currentActor
        );

        if (success) {
            offerId = _decodeUint256(returnData);
            _trackOfferId(offerId);
            offerIdsToUpdate = _singleUintArray(offerId);
        }

        registerOfferPostconditions(success, returnData, actorsToUpdate, offerIdsToUpdate, input);

        if (success) {
            _syncOffer(offerId);
        }
    }

    function _flowAcceptOffer(uint256 offerId, uint256 amount) internal returns (uint256 dealId) {
        address seller = _getOffer(offerId).owner;
        address[] memory actorsToUpdate = _twoActorArray(currentActor, seller);
        uint256[] memory offerIdsToUpdate = _singleUintArray(offerId);
        _before(actorsToUpdate, offerIdsToUpdate, _emptyUintArray());

        bytes memory returnData;
        bool success;
        (success, returnData) = fl.doFunctionCall(
            address(marketplace),
            abi.encodeWithSelector(marketplace.acceptOffer.selector, offerId, amount),
            currentActor
        );

        uint256[] memory dealIdsToUpdate = _emptyUintArray();
        if (success) {
            dealId = _decodeUint256(returnData);
            _trackDealId(dealId);
            dealIdsToUpdate = _singleUintArray(dealId);
        }

        acceptOfferPostconditions(success, returnData, actorsToUpdate, offerIdsToUpdate, dealIdsToUpdate, amount);

        _syncOffer(offerId);
        if (success) {
            _syncDeal(dealId);
        }
    }

    function _flowExpressInterest(uint256 offerId, uint256 amount) internal returns (bool success) {
        address seller = _getOffer(offerId).owner;
        address[] memory actorsToUpdate = _twoActorArray(currentActor, seller);
        uint256[] memory offerIdsToUpdate = _singleUintArray(offerId);
        _before(actorsToUpdate, offerIdsToUpdate, _emptyUintArray(), _emptyUintArray());

        bytes memory returnData;
        (success, returnData) = fl.doFunctionCall(
            address(marketplace),
            abi.encodeWithSelector(marketplace.expressInterest.selector, offerId, amount),
            currentActor
        );

        uint256[] memory interestIdsToUpdate = _emptyUintArray();
        if (success) {
            uint256 interestId = _decodeUint256(returnData);
            _trackInterestId(interestId);
            interestIdsToUpdate = _singleUintArray(interestId);
        }

        expressInterestPostconditions(
            success, returnData, actorsToUpdate, offerIdsToUpdate, interestIdsToUpdate, amount
        );

        _syncOffer(offerId);
        if (success) {
            _syncInterest(interestIdsToUpdate[0]);
        }
        _syncKnownInterestsForOffer(offerId);
    }

    function _flowActivateInterest(uint256 interestId) internal returns (uint256 dealId) {
        Interest memory interestState = _getInterest(interestId);
        address seller = _getOffer(interestState.offerId).owner;
        address[] memory actorsToUpdate = _twoActorArray(interestState.investor, seller);
        uint256[] memory offerIdsToUpdate = _singleUintArray(interestState.offerId);
        uint256[] memory interestIdsToUpdate = _singleUintArray(interestId);
        _before(actorsToUpdate, offerIdsToUpdate, _emptyUintArray(), interestIdsToUpdate);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(marketplace),
            abi.encodeWithSelector(marketplace.activateInterest.selector, interestId),
            currentActor
        );

        uint256[] memory dealIdsToUpdate = _dealIdsFromSuccessfulReturn(success, returnData);

        activateInterestPostconditions(
            success,
            returnData,
            actorsToUpdate,
            offerIdsToUpdate,
            dealIdsToUpdate,
            interestIdsToUpdate,
            interestState.amount
        );

        Interest memory updatedInterest = _getInterest(interestId);
        _syncInterest(interestId);
        _syncOffer(updatedInterest.offerId);
        if (success) {
            dealId = dealIdsToUpdate[0];
            _syncDeal(dealId);
        }
        _syncKnownInterestsForOffer(updatedInterest.offerId);
    }

    function _flowCloseExpiredInterests(uint256 offerId, uint256[] memory interestIds) internal returns (bool success) {
        address seller = _getOffer(offerId).owner;
        uint256[] memory offerIdsToUpdate = _singleUintArray(offerId);
        _before(_singleActorArray(seller), offerIdsToUpdate, _emptyUintArray(), interestIds);

        bytes memory returnData;
        (success, returnData) = fl.doFunctionCall(
            address(marketplace),
            abi.encodeWithSelector(marketplace.closeExpiredInterests.selector, offerId, interestIds),
            seller
        );

        closeExpiredInterestsPostconditions(success, returnData, offerIdsToUpdate, interestIds);

        _syncOffer(offerId);
        for (uint256 i; i < interestIds.length; ++i) {
            _syncInterest(interestIds[i]);
        }
        _syncKnownInterestsForOffer(offerId);
    }

    function _flowWithdrawAvailable(uint256 offerId) internal returns (bool success) {
        address seller = _getOffer(offerId).owner;
        address[] memory actorsToUpdate = _singleActorArray(seller);
        uint256[] memory offerIdsToUpdate = _singleUintArray(offerId);
        _before(actorsToUpdate, offerIdsToUpdate, _emptyUintArray());

        bytes memory returnData;
        (success, returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.withdrawAvailable.selector, offerId), seller
        );

        withdrawAvailablePostconditions(success, returnData, actorsToUpdate, offerIdsToUpdate);

        _syncOffer(offerId);
    }

    function _flowCancelOffer(uint256 offerId) internal returns (bool success) {
        address[] memory actorsToUpdate = _singleActorArray(currentActor);
        uint256[] memory offerIdsToUpdate = _singleUintArray(offerId);
        _before(actorsToUpdate, offerIdsToUpdate, _emptyUintArray());

        bytes memory returnData;
        (success, returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.cancelOffer.selector, offerId), currentActor
        );

        cancelOfferPostconditions(success, returnData, actorsToUpdate, offerIdsToUpdate);

        _syncOffer(offerId);
    }

    function _flowResolvePayment(uint256 offerId, uint256 dealId, bool paid) internal returns (bool success) {
        uint256[] memory offerIdsToUpdate = _singleUintArray(offerId);
        uint256[] memory dealIdsToUpdate = _singleUintArray(dealId);
        _before(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);

        bytes memory returnData;
        (success, returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.resolvePayment.selector, dealId, paid)
        );

        resolvePaymentPostconditions(success, returnData, offerIdsToUpdate, dealIdsToUpdate, paid);

        _syncDeal(dealId);
    }

    function _flowSettleDeal(uint256 dealId) internal returns (bool success) {
        Deal memory dealState = _getDeal(dealId);
        address[] memory actorsToUpdate = _singleActorArray(dealState.buyer);
        uint256[] memory offerIdsToUpdate = _singleUintArray(dealState.offerId);
        uint256[] memory dealIdsToUpdate = _singleUintArray(dealId);
        _before(actorsToUpdate, offerIdsToUpdate, dealIdsToUpdate);

        bytes memory returnData;
        (success, returnData) =
            fl.doFunctionCall(address(marketplace), abi.encodeWithSelector(marketplace.settleDeal.selector, dealId));

        settleDealPostconditions(
            success,
            returnData,
            actorsToUpdate,
            offerIdsToUpdate,
            dealIdsToUpdate,
            dealState.amount,
            dealState.status == DealStatus.PAID
        );

        Deal memory updatedDeal = _getDeal(dealId);
        _syncDeal(dealId);
        _syncOffer(updatedDeal.offerId);
    }

    function _flowInitiateDispute(uint256 offerId, uint256 dealId) internal returns (bool success) {
        Deal memory dealState = _getDeal(dealId);
        uint256[] memory offerIdsToUpdate = _singleUintArray(offerId);
        uint256[] memory dealIdsToUpdate = _singleUintArray(dealId);
        _before(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);

        bytes memory returnData;
        (success, returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.initiateDispute.selector, dealId), dealState.buyer
        );

        initiateDisputePostconditions(success, returnData, offerIdsToUpdate, dealIdsToUpdate);

        _syncDeal(dealId);
    }

    function _flowResolveDispute(uint256 offerId, uint256 dealId, DealStatus status) internal returns (bool success) {
        uint256[] memory offerIdsToUpdate = _singleUintArray(offerId);
        uint256[] memory dealIdsToUpdate = _singleUintArray(dealId);
        _before(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);

        bytes memory returnData;
        (success, returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.resolveDispute.selector, dealId, status)
        );

        resolveDisputePostconditions(success, returnData, offerIdsToUpdate, dealIdsToUpdate, status);

        _syncDeal(dealId);
    }

    function _flowSetOfferFrozen(uint256 offerId, bool frozen) internal returns (bool success) {
        uint256[] memory offerIdsToUpdate = _singleUintArray(offerId);
        _before(_emptyAddressArray(), offerIdsToUpdate, _emptyUintArray());

        bytes memory returnData;
        (success, returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.setOfferFrozen.selector, offerId, frozen)
        );

        setOfferFrozenPostconditions(success, returnData, offerIdsToUpdate, frozen);

        _syncOffer(offerId);
        _syncKnownDealsForOffer(offerId);
        _syncKnownInterestsForOffer(offerId);
    }

    function _flowSetDealFrozen(uint256 offerId, uint256 dealId, bool frozen) internal returns (bool success) {
        uint256[] memory offerIdsToUpdate = _singleUintArray(offerId);
        uint256[] memory dealIdsToUpdate = _singleUintArray(dealId);
        _before(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);

        bytes memory returnData;
        (success, returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.setDealFrozen.selector, dealId, frozen)
        );

        setDealFrozenPostconditions(success, returnData, offerIdsToUpdate, dealIdsToUpdate, frozen);

        _syncDeal(dealId);
    }

    function _flowSeizeOfferEscrow(uint256 offerId, address beneficiary, bytes32 reason)
        internal
        returns (bool success)
    {
        address[] memory actorsToUpdate = _singleActorArray(beneficiary);
        uint256[] memory offerIdsToUpdate = _singleUintArray(offerId);
        _before(actorsToUpdate, offerIdsToUpdate, _emptyUintArray());

        bytes memory returnData;
        (success, returnData) = fl.doFunctionCall(
            address(marketplace),
            abi.encodeWithSelector(marketplace.seizeOfferEscrow.selector, offerId, beneficiary, reason)
        );

        seizeOfferEscrowPostconditions(success, returnData, actorsToUpdate, offerIdsToUpdate);

        _syncOffer(offerId);
        _syncKnownDealsForOffer(offerId);
        _syncKnownInterestsForOffer(offerId);
    }

    function _flowSeizeDeal(uint256 offerId, uint256 dealId, address beneficiary, bytes32 reason)
        internal
        returns (bool success)
    {
        address[] memory actorsToUpdate = _singleActorArray(beneficiary);
        uint256[] memory offerIdsToUpdate = _singleUintArray(offerId);
        uint256[] memory dealIdsToUpdate = _singleUintArray(dealId);
        _before(actorsToUpdate, offerIdsToUpdate, dealIdsToUpdate);

        bytes memory returnData;
        (success, returnData) = fl.doFunctionCall(
            address(marketplace), abi.encodeWithSelector(marketplace.seizeDeal.selector, dealId, beneficiary, reason)
        );

        seizeDealPostconditions(success, returnData, actorsToUpdate, offerIdsToUpdate, dealIdsToUpdate);

        _syncDeal(dealId);
        _syncOffer(offerId);
    }

    function _dealIdsFromSuccessfulReturn(bool success, bytes memory returnData)
        internal
        returns (uint256[] memory dealIds)
    {
        if (!success) return _emptyUintArray();

        uint256 dealId = _decodeUint256(returnData);
        _trackDealId(dealId);
        return _singleUintArray(dealId);
    }

    function _expectMarketplaceAdminCall(bytes memory callData) private {
        (bool success, bytes memory returnData) = fl.doFunctionCall(address(marketplace), callData, address(this));
        marketplaceAdminSuccessPostconditions(success, returnData);
    }
}
