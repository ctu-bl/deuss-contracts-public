// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {FuzzIntegrityBase} from "./FuzzIntegrityBase.sol";
import {HandlerMarketplace} from "./helper/handlers/HandlerMarketplace.sol";

/**
 * @title FuzzMarketplaceIntegrity
 * @notice Checks handler integrity for the Marketplace fuzz harness
 */
contract FuzzMarketplaceIntegrity is HandlerMarketplace, FuzzIntegrityBase {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         INTEGRITY                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Checks the integrity of `handler_registerMarketplaceOffer`
     * @param total Proposed total token amount for the offer
     * @param lot Proposed lot size for the offer
     * @param allowCounterOffers Whether counter offers should be enabled
     */
    function fuzz_registerMarketplaceOffer(uint256 total, uint256 lot, bool allowCounterOffers) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerMarketplace.handler_registerMarketplaceOffer.selector, total, lot, allowCounterOffers
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-REGISTER");
        }
    }

    /**
     * @notice Checks the integrity of `handler_registerRedemptionOffer`
     * @param total Proposed total token amount for the offer
     * @param lot Proposed lot size for the offer
     */
    function fuzz_registerRedemptionOffer(uint256 total, uint256 lot) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_registerRedemptionOffer.selector, total, lot);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-REGISTER-REDEMPTION");
        }
    }

    /**
     * @notice Checks the integrity of `handler_registerInterestOffer`
     * @param total Proposed total token amount for the offer
     * @param lot Proposed lot size for the offer
     * @param minSaleUnitsSeed Seed used to derive the minimum threshold
     */
    function fuzz_registerInterestOffer(uint256 total, uint256 lot, uint256 minSaleUnitsSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerMarketplace.handler_registerInterestOffer.selector, total, lot, minSaleUnitsSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-REGISTER-INTEREST");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setMaxCounterOffersPerUser`
     * @param maxCounterOffers Proposed per-user counter-offer cap
     */
    function fuzz_setMaxCounterOffersPerUser(uint256 maxCounterOffers) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_setMaxCounterOffersPerUser.selector, maxCounterOffers);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-SET-MAX-COUNTER-OFFERS");
        }
    }

    /**
     * @notice Checks the integrity of `handler_acceptOffer`
     * @param offer Seed used to select a tracked offer
     * @param amount Seed used to derive the accepted amount
     */
    function fuzz_acceptOffer(uint256 offer, uint256 amount) public {
        bytes memory callData = abi.encodeWithSelector(HandlerMarketplace.handler_acceptOffer.selector, offer, amount);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-ACCEPT");
        }
    }

    /**
     * @notice Checks the integrity of `handler_expressInterest`
     * @param offer Seed used to select a tracked interest-discovery offer
     * @param amount Seed used to derive the expressed amount
     */
    function fuzz_expressInterest(uint256 offer, uint256 amount) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_expressInterest.selector, offer, amount);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-INTEREST-EXPRESS");
        }
    }

    /**
     * @notice Checks the integrity of `handler_expressInterestBelowThreshold`
     * @param offer Seed used to select a tracked interest-discovery offer
     * @param amount Seed used to derive the expressed below-threshold amount
     */
    function fuzz_expressInterestBelowThreshold(uint256 offer, uint256 amount) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_expressInterestBelowThreshold.selector, offer, amount);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-INT-BELOW-THRESH");
        }
    }

    /**
     * @notice Checks the integrity of `handler_activateInterest`
     * @param interest Seed used to select a tracked expressed interest
     */
    function fuzz_activateInterest(uint256 interest) public {
        bytes memory callData = abi.encodeWithSelector(HandlerMarketplace.handler_activateInterest.selector, interest);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-INTEREST-ACTIVATE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_closeExpiredInterest`
     * @param interest Seed used to select a tracked expired expressed interest
     */
    function fuzz_closeExpiredInterest(uint256 interest) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_closeExpiredInterest.selector, interest);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-INTEREST-CLOSE");
        }
    }

    /**
     * @notice Checks the integrity of batched `handler_closeExpiredInterestsBatch`
     * @param interest Seed used to select a tracked expired expressed interest
     * @param countSeed Seed used to derive the batch size
     */
    function fuzz_closeExpiredInterestsBatch(uint256 interest, uint256 countSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_closeExpiredInterestsBatch.selector, interest, countSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-INTEREST-CLOSE-BATCH");
        }
    }

    /**
     * @notice Checks the integrity of `handler_withdrawAvailable`
     * @param offer Seed used to select a tracked cancelled offer owned by the current actor
     */
    function fuzz_withdrawAvailable(uint256 offer) public {
        bytes memory callData = abi.encodeWithSelector(HandlerMarketplace.handler_withdrawAvailable.selector, offer);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-WITHDRAW");
        }
    }

    /**
     * @notice Checks the integrity of `handler_withdrawCancelledDirectOffer`
     * @param total Proposed total token amount for the fresh direct-sale offer
     * @param lot Proposed lot size for the fresh direct-sale offer
     */
    function fuzz_withdrawCancelledDirectOffer(uint256 total, uint256 lot) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_withdrawCancelledDirectOffer.selector, total, lot);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-WITHDRAW-CANCELLED-DIRECT");
        }
    }

    /**
     * @notice Checks the integrity of `handler_withdrawInterestAvailable`
     * @param offer Seed used to select a tracked expired interest-discovery offer
     */
    function fuzz_withdrawInterestAvailable(uint256 offer) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_withdrawInterestAvailable.selector, offer);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-WITHDRAW-INTEREST");
        }
    }

    /**
     * @notice Checks failed-book withdrawal is rejected in favor of cancellation
     * @param offer Seed used to select a tracked expired interest-discovery offer
     */
    function fuzz_withdrawInterestAvailableBelowThreshold(uint256 offer) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_withdrawInterestAvailableBelowThreshold.selector, offer);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-WDRAW-BELOW-THRESH");
        }
    }

    /**
     * @notice Checks the integrity of `handler_createCounterOffer`
     * @param offer Seed used to select a tracked offer
     * @param amount Seed used to derive the counter-offered amount
     */
    function fuzz_createCounterOffer(uint256 offer, uint256 amount) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_createCounterOffer.selector, offer, amount);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-COUNTER-CREATE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_cancelOffer`
     * @param offer Seed used to select a tracked offer owned by the current actor
     */
    function fuzz_cancelOffer(uint256 offer) public {
        bytes memory callData = abi.encodeWithSelector(HandlerMarketplace.handler_cancelOffer.selector, offer);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-CANCEL");
        }
    }

    /**
     * @notice Checks the integrity of `handler_cancelFailedInterestOffer`
     * @param offer Seed used to select an expired failed interest-discovery offer
     */
    function fuzz_cancelFailedInterestOffer(uint256 offer) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_cancelFailedInterestOffer.selector, offer);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-CANCEL-FAILED-INTEREST");
        }
    }

    /**
     * @notice Checks the integrity of `handler_cancelFailedInterestOfferByOperator`
     * @param offer Seed used to select an expired failed interest-discovery offer
     */
    function fuzz_cancelFailedInterestOfferByOperator(uint256 offer) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_cancelFailedInterestOfferByOperator.selector, offer);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-CANCEL-FI-OP");
        }
    }

    /**
     * @notice Checks the integrity of `handler_cancelCounterOffer`
     * @param deal Seed used to select a tracked counter-offer deal owned by the current actor
     */
    function fuzz_cancelCounterOffer(uint256 deal) public {
        bytes memory callData = abi.encodeWithSelector(HandlerMarketplace.handler_cancelCounterOffer.selector, deal);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-COUNTER-CANCEL");
        }
    }

    /**
     * @notice Checks the integrity of `handler_resolveCounterOffer`
     * @param deal Seed used to select a tracked counter-offer deal
     * @param accepted Whether the current actor accepts or declines the counter offer
     */
    function fuzz_resolveCounterOffer(uint256 deal, bool accepted) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_resolveCounterOffer.selector, deal, accepted);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-COUNTER-RESOLVE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_resolvePayment`
     * @param deal Seed used to select a tracked deal
     * @param paid Whether the selected deal should be resolved as paid or unpaid
     */
    function fuzz_resolvePayment(uint256 deal, bool paid) public {
        bytes memory callData = abi.encodeWithSelector(HandlerMarketplace.handler_resolvePayment.selector, deal, paid);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-RESOLVE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_resolvePayments`
     * @param payableDeal Seed used to select a tracked deal for the paid batch item
     * @param expiredDeal Seed used to select a tracked expired pending deal for the unpaid batch item
     */
    function fuzz_resolvePayments(uint256 payableDeal, uint256 expiredDeal) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_resolvePayments.selector, payableDeal, expiredDeal);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-RESOLVE-BATCH");
        }
    }

    /**
     * @notice Checks unpaid-only duplicate batch resolution from an unprivileged caller
     * @param deal Seed used to select a tracked expired pending deal
     */
    function fuzz_resolvePaymentsDuplicateUnpaid(uint256 deal) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_resolvePaymentsDuplicateUnpaid.selector, deal);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-RESOLVE-BATCH-DUP");
        }
    }

    /**
     * @notice Checks that `resolvePayments` skips a paid item once its pending deal has expired
     * @param deal Seed used to select a tracked expired pending deal
     */
    function fuzz_resolvePaymentsExpiredPaid(uint256 deal) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_resolvePaymentsExpiredPaid.selector, deal);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-RESOLVE-BATCH-EXPIRED-PAID");
        }
    }

    /**
     * @notice Checks that `handler_resolvePaymentsUnauthorized` rejects paid batches without PAYMENT_HANDLER
     * @param expiredDeal Seed used to select a tracked expired pending deal
     * @param payableDeal Seed used to select a tracked payable deal
     */
    function fuzz_resolvePaymentsUnauthorized(uint256 expiredDeal, uint256 payableDeal) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerMarketplace.handler_resolvePaymentsUnauthorized.selector, expiredDeal, payableDeal
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-RESOLVE-BATCH-UNAUTH");
        }
    }

    /**
     * @notice Checks that `handler_resolvePaymentUnauthorized` rejects callers without PAYMENT_HANDLER
     * @param deal Seed used to select a tracked payable deal
     */
    function fuzz_resolvePaymentUnauthorized(uint256 deal) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_resolvePaymentUnauthorized.selector, deal);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-RESOLVE-UNAUTH");
        }
    }

    /**
     * @notice Checks the integrity of `handler_settleDeal`
     * @param deal Seed used to select a tracked deal
     */
    function fuzz_settleDeal(uint256 deal) public {
        bytes memory callData = abi.encodeWithSelector(HandlerMarketplace.handler_settleDeal.selector, deal);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-SETTLE");
        }
    }

    /**
     * @notice Checks the integrity of batched `handler_settleDealsBatch`
     * @param deal Seed used to select a tracked settleable deal
     * @param countSeed Seed used to derive the batch size
     */
    function fuzz_settleDealsBatch(uint256 deal, uint256 countSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_settleDealsBatch.selector, deal, countSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-SETTLE-BATCH");
        }
    }

    /**
     * @notice Checks the integrity of mixed valid/invalid batched `handler_settleDealsMixedBatch`
     * @param settleableDeal Seed used to select a tracked settleable deal
     * @param invalidDeal Seed used to select a tracked invalid deal
     */
    function fuzz_settleDealsMixedBatch(uint256 settleableDeal, uint256 invalidDeal) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerMarketplace.handler_settleDealsMixedBatch.selector, settleableDeal, invalidDeal
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-SETTLE-MIXED-BATCH");
        }
    }

    /**
     * @notice Checks the integrity of `handler_initiateDispute`
     * @param deal Seed used to select a tracked unpaid deal within its dispute window
     */
    function fuzz_initiateDispute(uint256 deal) public {
        bytes memory callData = abi.encodeWithSelector(HandlerMarketplace.handler_initiateDispute.selector, deal);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-DISPUTE-INIT");
        }
    }

    /**
     * @notice Checks the integrity of `handler_resolveDispute`
     * @param deal Seed used to select a tracked in-dispute deal
     * @param paid Whether the arbitrator resolves the deal as paid or unpaid
     */
    function fuzz_resolveDispute(uint256 deal, bool paid) public {
        bytes memory callData = abi.encodeWithSelector(HandlerMarketplace.handler_resolveDispute.selector, deal, paid);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-DISPUTE-RESOLVE");
        }
    }

    /**
     * @notice Checks the deterministic dispute lifecycle flow from PENDING to arbitrated status
     * @param deal Seed used to select a tracked pending payable deal
     * @param paid Whether the arbitrator resolves the dispute as paid or unpaid
     */
    function fuzz_disputeResolutionFlow(uint256 deal, bool paid) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_disputeResolutionFlow.selector, deal, paid);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-DISPUTE-FLOW");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setOfferFrozen`
     * @param offer Seed used to select a tracked offer
     * @param frozen Whether the offer should be frozen or unfrozen
     */
    function fuzz_setOfferFrozen(uint256 offer, bool frozen) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_setOfferFrozen.selector, offer, frozen);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-FREEZE-OFFER");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setDealFrozen`
     * @param deal Seed used to select a tracked deal
     * @param frozen Whether the deal should be frozen or unfrozen
     */
    function fuzz_setDealFrozen(uint256 deal, bool frozen) public {
        bytes memory callData = abi.encodeWithSelector(HandlerMarketplace.handler_setDealFrozen.selector, deal, frozen);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-FREEZE-DEAL");
        }
    }

    /**
     * @notice Checks the integrity of `handler_seizeOfferEscrow`
     * @param offer Seed used to select a frozen tracked offer with seizable escrow
     * @param beneficiarySeed Seed used to select a valid beneficiary
     */
    function fuzz_seizeOfferEscrow(uint256 offer, uint256 beneficiarySeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_seizeOfferEscrow.selector, offer, beneficiarySeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-SEIZE-OFFER");
        }
    }

    /**
     * @notice Checks seizure of an interest-discovery offer with non-zero reserved interest
     * @param total Proposed total token amount for the fresh interest-discovery offer
     * @param lot Proposed lot size for the fresh interest-discovery offer and expressed interest
     * @param beneficiarySeed Seed used to select a valid beneficiary
     */
    function fuzz_seizeOfferReservedInterest(uint256 total, uint256 lot, uint256 beneficiarySeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerMarketplace.handler_seizeOfferReservedInterest.selector, total, lot, beneficiarySeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-SEIZE-RESERVED");
        }
    }

    /**
     * @notice Checks the integrity of `handler_seizeDeal`
     * @param deal Seed used to select a frozen tracked deal with frozen parent offer
     * @param beneficiarySeed Seed used to select a valid beneficiary
     */
    function fuzz_seizeDeal(uint256 deal, uint256 beneficiarySeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerMarketplace.handler_seizeDeal.selector, deal, beneficiarySeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-SEIZE-DEAL");
        }
    }

    /**
     * @notice Checks seizure of a deal after it is marked PAID and both sides are frozen
     * @param total Proposed total token amount for the fresh marketplace offer
     * @param lot Proposed lot size for the fresh marketplace offer and accepted deal
     */
    function fuzz_seizePaidDeal(uint256 total, uint256 lot) public {
        bytes memory callData = abi.encodeWithSelector(HandlerMarketplace.handler_seizePaidDeal.selector, total, lot);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-SEIZE-PAID-DEAL");
        }
    }

    /**
     * @notice Checks Marketplace admin and view coverage surface
     */
    function fuzz_marketplaceAdminSurface() public {
        bytes memory callData = abi.encodeWithSelector(HandlerMarketplace.handler_marketplaceAdminSurface.selector);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-MARKETPLACE-ADMIN-SURFACE");
        }
    }
}
