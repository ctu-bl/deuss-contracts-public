// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, gas-strict-inequalities */

import {DealStatus, OfferInput} from "src/marketplace/MarketStructs.sol";
import {PreconditionsMarketplace} from "../preconditions/PreconditionsMarketplace.sol";
import {PostconditionsBase} from "./PostconditionsBase.sol";

abstract contract PostconditionsMarketplace is PostconditionsBase {
    function marketplaceAdminSuccessPostconditions(bool success, bytes memory returnData) internal {
        invariant_MKT_80(success, _returnSelector(returnData));
    }

    function marketplaceExpectedRevertPostconditions(bool success, bytes memory returnData, bytes4 expectedSelector)
        internal
    {
        invariant_MKT_82(success, _returnSelector(returnData), expectedSelector);
    }

    function marketplaceSetBondRegistryPostconditions(bool success, bytes memory returnData) internal {
        if (success) return;

        invariant_MKT_81(_returnSelector(returnData));
    }

    function registerOfferPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256[] memory offerIdsToUpdate,
        OfferInput memory input
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            _after(actorsToUpdate, offerIdsToUpdate, _emptyUintArray());
            invariant_OFER_10(
                offerId,
                currentActor,
                input.totalAmount,
                input.lot,
                input.unitPrice,
                input.expiry,
                input.saleMode,
                input.allowCounterOffers,
                input.minSaleUnits,
                input.allowedBuyers
            );
            invariant_OFER_11();
            invariant_OFER_12(currentActor, input.totalAmount);
            invariant_ESCR_10(offerId);
            invariant_ESCR_11(offerId, input.totalAmount);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_OFER_13(_returnSelector(returnData));
        }
    }

    function setMaxCounterOffersPerUserPostconditions(
        bool success,
        bytes memory returnData,
        uint256 previousMaxCounterOffers,
        uint256 maxCounterOffers
    ) internal {
        if (success) {
            _after(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());
            invariant_OFER_70(maxCounterOffers);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_OFER_71(_returnSelector(returnData));
            invariant_OFER_72(previousMaxCounterOffers);
        }
    }

    function acceptOfferPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate,
        uint256 amount
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            uint256 dealId = dealIdsToUpdate[0];
            _after(actorsToUpdate, offerIdsToUpdate, dealIdsToUpdate);
            invariant_OFER_20(offerId, amount);
            invariant_DEAL_01(dealId, offerId, currentActor, amount);
            invariant_DEAL_02();
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_DEAL_03(_returnSelector(returnData));
        }
    }

    function expressInterestPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory interestIdsToUpdate,
        uint256 amount
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            uint256 interestId = interestIdsToUpdate[0];
            address investor = actorsToUpdate[0];

            _after(actorsToUpdate, offerIdsToUpdate, _emptyUintArray(), interestIdsToUpdate);
            invariant_INTR_01(offerId);
            invariant_INTR_10(offerId, amount);
            invariant_INTR_11(interestId, offerId, amount, investor);
            invariant_INTR_12();
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_INTR_13(_returnSelector(returnData));
        }
    }

    function activateInterestPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate,
        uint256[] memory interestIdsToUpdate,
        uint256 amount
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            uint256 dealId = dealIdsToUpdate[0];
            uint256 interestId = interestIdsToUpdate[0];
            address investor = actorsToUpdate[0];

            _after(actorsToUpdate, offerIdsToUpdate, dealIdsToUpdate, interestIdsToUpdate);
            invariant_INTR_01(offerId);
            invariant_INTR_20(offerId, amount);
            invariant_INTR_21(interestId);
            invariant_INTR_22(dealId, interestId, offerId, investor, amount);
            invariant_INTR_23();
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_INTR_24(_returnSelector(returnData));
        }
    }

    function closeExpiredInterestsPostconditions(
        bool success,
        bytes memory returnData,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory interestIdsToUpdate
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];

            _after(_emptyAddressArray(), offerIdsToUpdate, _emptyUintArray(), interestIdsToUpdate);
            for (uint256 i; i < interestIdsToUpdate.length; ++i) {
                invariant_INTR_30(interestIdsToUpdate[i]);
            }
            invariant_INTR_01(offerId);
            invariant_INTR_31(offerId, interestIdsToUpdate);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_INTR_32(_returnSelector(returnData));
        }
    }

    function withdrawAvailablePostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256[] memory offerIdsToUpdate
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            address seller = actorsToUpdate[0];
            _after(actorsToUpdate, offerIdsToUpdate, _emptyUintArray());
            invariant_OFER_50(offerId);
            invariant_OFER_51(seller, _directSaleWithdrawableAmount(offerId));
            invariant_ESCR_14(offerId, _directSaleWithdrawableAmount(offerId));
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_OFER_52(_returnSelector(returnData));
        }
    }

    function withdrawInterestAvailablePostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256[] memory offerIdsToUpdate
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            address seller = actorsToUpdate[0];

            _after(actorsToUpdate, offerIdsToUpdate, _emptyUintArray());
            invariant_INTR_01(offerId);
            invariant_INTR_40(offerId);
            invariant_OFER_51(seller, _interestDiscoveryWithdrawableAmount(offerId));
            invariant_ESCR_14(offerId, _interestDiscoveryWithdrawableAmount(offerId));
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_INTR_41(_returnSelector(returnData));
        }
    }

    function withdrawInterestAvailableBelowThresholdPostconditions(bool success, bytes memory returnData) internal {
        invariant_INTR_42(success, _returnSelector(returnData));
    }

    function createCounterOfferPostconditions(
        bool success,
        bytes memory returnData,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate,
        PreconditionsMarketplace.CounterOfferParams memory params
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            uint256 dealId = dealIdsToUpdate[0];
            _after(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);
            invariant_OFER_40(offerId);
            invariant_DEAL_30(dealId, offerId, currentActor, params.amount, params.unitPrice, params.expiry);
            invariant_DEAL_31();
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_DEAL_32(_returnSelector(returnData));
        }
    }

    function cancelOfferPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256[] memory offerIdsToUpdate
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            _after(actorsToUpdate, offerIdsToUpdate, _emptyUintArray());
            invariant_OFER_21(offerId);
            invariant_ESCR_12(offerId);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_OFER_22(_returnSelector(returnData));
        }
    }

    function cancelFailedInterestOfferPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256[] memory offerIdsToUpdate
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            address seller = actorsToUpdate[0];
            _after(actorsToUpdate, offerIdsToUpdate, _emptyUintArray());
            invariant_OFER_21(offerId);
            invariant_INTR_01(offerId);
            invariant_INTR_40(offerId);
            invariant_INTR_43(offerId);
            invariant_OFER_51(seller, _failedInterestDiscoveryCancellationAmount(offerId));
            invariant_ESCR_14(offerId, _failedInterestDiscoveryCancellationAmount(offerId));
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_OFER_22(_returnSelector(returnData));
        }
    }

    function cancelCounterOfferPostconditions(
        bool success,
        bytes memory returnData,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            uint256 dealId = dealIdsToUpdate[0];
            _after(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);
            invariant_OFER_40(offerId);
            invariant_DEAL_40(dealId);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_DEAL_41(_returnSelector(returnData));
        }
    }

    function resolveCounterOfferPostconditions(
        bool success,
        bytes memory returnData,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate,
        uint256 amount,
        bool accepted
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            uint256 dealId = dealIdsToUpdate[0];
            _after(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);
            if (accepted) {
                invariant_OFER_20(offerId, amount);
                invariant_DEAL_50(dealId);
            } else {
                invariant_OFER_40(offerId);
                invariant_DEAL_51_OFFER_ID(dealId);
                invariant_DEAL_51_AMOUNT(dealId);
                invariant_DEAL_51_BUYER(dealId);
                invariant_DEAL_51_PRICE(dealId);
                invariant_DEAL_51_STATUS(dealId);
                invariant_DEAL_51_COUNTER_OFFER_EXPIRY(dealId);
                invariant_DEAL_51_PAYMENT_DEADLINE(dealId);
                invariant_DEAL_51_DISPUTE_BUFFER(dealId);
                invariant_DEAL_51_DEAL_TYPE(dealId);
            }
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_DEAL_52(_returnSelector(returnData));
        }
    }

    function resolvePaymentPostconditions(
        bool success,
        bytes memory returnData,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate,
        bool paid
    ) internal {
        if (success) {
            uint256 dealId = dealIdsToUpdate[0];
            _after(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);
            if (paid) {
                invariant_DEAL_10(dealId);
            } else {
                invariant_DEAL_12(dealId);
            }
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_DEAL_11(_returnSelector(returnData));
        }
    }

    function resolvePaymentsPostconditions(
        bool success,
        bytes memory returnData,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate
    ) internal {
        if (success) {
            _after(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);
            invariant_DEAL_14_PAID_STATUS(dealIdsToUpdate[0]);
            invariant_DEAL_14_UNPAID_STATUS(dealIdsToUpdate[1]);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_DEAL_17(_returnSelector(returnData));
        }
    }

    function resolvePaymentsDuplicateUnpaidPostconditions(
        bool success,
        bytes memory returnData,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate,
        address resolver
    ) internal {
        if (success) {
            uint256 dealId = dealIdsToUpdate[0];
            _after(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);

            invariant_DEAL_15_RESOLVER_NOT_PAYMENT_HANDLER(resolver);
            invariant_DEAL_15_STATUS(dealId);
            invariant_DEAL_15_OFFER_ID(dealId);
            invariant_DEAL_15_AMOUNT(dealId);
            invariant_DEAL_15_BUYER(dealId);
            invariant_DEAL_15_PRICE(dealId);
            invariant_DEAL_15_COUNTER_OFFER_EXPIRY(dealId);
            invariant_DEAL_15_PAYMENT_DEADLINE(dealId);
            invariant_DEAL_15_DISPUTE_BUFFER(dealId);
            invariant_DEAL_15_DEAL_TYPE(dealId);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_DEAL_17(_returnSelector(returnData));
        }
    }

    function resolvePaymentsExpiredPaidPostconditions(
        bool success,
        bytes memory returnData,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate
    ) internal {
        if (!success) {
            invariant_DEAL_17(_returnSelector(returnData));
            return;
        }

        uint256 dealId = dealIdsToUpdate[0];
        _after(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);

        invariant_DEAL_18_BEFORE_PENDING(dealId);
        invariant_DEAL_18_OFFER_ID(dealId);
        invariant_DEAL_18_AMOUNT(dealId);
        invariant_DEAL_18_BUYER(dealId);
        invariant_DEAL_18_PRICE(dealId);
        invariant_DEAL_18_COUNTER_OFFER_EXPIRY(dealId);
        invariant_DEAL_18_PAYMENT_DEADLINE(dealId);
        invariant_DEAL_18_DISPUTE_BUFFER(dealId);
        invariant_DEAL_18_STATUS(dealId);
        invariant_DEAL_18_DEAL_TYPE(dealId);
        onSuccessInvariantsGeneral(returnData);
    }

    function resolvePaymentsUnauthorizedPostconditions(
        bool success,
        bytes memory returnData,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate
    ) internal {
        _after(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);

        invariant_DEAL_16_REVERTS(success);
        invariant_DEAL_16_ERROR(_returnSelector(returnData));

        for (uint256 i; i < dealIdsToUpdate.length; ++i) {
            uint256 dealId = dealIdsToUpdate[i];
            invariant_DEAL_16_OFFER_ID(dealId);
            invariant_DEAL_16_AMOUNT(dealId);
            invariant_DEAL_16_BUYER(dealId);
            invariant_DEAL_16_PRICE(dealId);
            invariant_DEAL_16_COUNTER_OFFER_EXPIRY(dealId);
            invariant_DEAL_16_PAYMENT_DEADLINE(dealId);
            invariant_DEAL_16_DISPUTE_BUFFER(dealId);
            invariant_DEAL_16_STATUS(dealId);
            invariant_DEAL_16_DEAL_TYPE(dealId);
        }
    }

    function resolvePaymentUnauthorizedPostconditions(bool success, bytes memory returnData) internal {
        invariant_DEAL_13(success, _returnSelector(returnData));
    }

    function settleDealPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate,
        uint256 amount,
        bool wasPaid
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            uint256 dealId = dealIdsToUpdate[0];
            address buyer = actorsToUpdate[0];
            _after(actorsToUpdate, offerIdsToUpdate, dealIdsToUpdate);
            invariant_DEAL_20(dealId);
            if (wasPaid) {
                invariant_DEAL_21(buyer, amount);
                invariant_OFER_30(offerId, amount);
                invariant_ESCR_13(offerId, amount);
            } else {
                invariant_DEAL_23(buyer);
                invariant_OFER_31(offerId, amount);
                invariant_ESCR_15(offerId);
            }
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_DEAL_22(_returnSelector(returnData));
        }
    }

    function settleDealsBatchPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate
    ) internal {
        if (success) {
            _after(actorsToUpdate, offerIdsToUpdate, dealIdsToUpdate);
            for (uint256 i; i < dealIdsToUpdate.length; ++i) {
                invariant_DEAL_20(dealIdsToUpdate[i]);
                invariant_DEAL_batchBuyerBalance(actorsToUpdate[i], dealIdsToUpdate);
                invariant_OFER_32(offerIdsToUpdate[i], dealIdsToUpdate);
                invariant_OFER_33(offerIdsToUpdate[i], dealIdsToUpdate);
                invariant_OFER_34(offerIdsToUpdate[i], dealIdsToUpdate);
                invariant_ESCR_16(offerIdsToUpdate[i], dealIdsToUpdate);
            }
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_DEAL_22(_returnSelector(returnData));
        }
    }

    function settleDealsMixedBatchPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate
    ) internal {
        if (success) {
            _after(actorsToUpdate, offerIdsToUpdate, dealIdsToUpdate);
            invariant_DEAL_24(dealIdsToUpdate[0]);
            invariant_DEAL_20(dealIdsToUpdate[1]);
            uint256[] memory settledDealIdsToUpdate = _singleUintArray(dealIdsToUpdate[1]);
            invariant_DEAL_batchBuyerBalance(actorsToUpdate[1], settledDealIdsToUpdate);
            invariant_OFER_32(offerIdsToUpdate[1], settledDealIdsToUpdate);
            invariant_OFER_33(offerIdsToUpdate[1], settledDealIdsToUpdate);
            invariant_OFER_34(offerIdsToUpdate[1], settledDealIdsToUpdate);
            invariant_ESCR_16(offerIdsToUpdate[1], settledDealIdsToUpdate);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_DEAL_22(_returnSelector(returnData));
        }
    }

    function initiateDisputePostconditions(
        bool success,
        bytes memory returnData,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            uint256 dealId = dealIdsToUpdate[0];
            _after(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);
            invariant_DEAL_60(dealId);
            invariant_OFER_40(offerId);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_DEAL_61(_returnSelector(returnData));
        }
    }

    function resolveDisputePostconditions(
        bool success,
        bytes memory returnData,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate,
        DealStatus status
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            uint256 dealId = dealIdsToUpdate[0];
            _after(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);
            invariant_DEAL_62(dealId, status);
            invariant_OFER_40(offerId);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_DEAL_63(_returnSelector(returnData));
        }
    }

    function setOfferFrozenPostconditions(
        bool success,
        bytes memory returnData,
        uint256[] memory offerIdsToUpdate,
        bool frozen
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            _after(_emptyAddressArray(), offerIdsToUpdate, _emptyUintArray());
            invariant_OFER_60(offerId, frozen);
            invariant_OFER_40(offerId);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_OFER_61(_returnSelector(returnData));
        }
    }

    function setDealFrozenPostconditions(
        bool success,
        bytes memory returnData,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate,
        bool frozen
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            uint256 dealId = dealIdsToUpdate[0];
            _after(_emptyAddressArray(), offerIdsToUpdate, dealIdsToUpdate);
            invariant_DEAL_64(dealId, frozen);
            invariant_OFER_40(offerId);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_DEAL_65(_returnSelector(returnData));
        }
    }

    function seizeOfferEscrowPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256[] memory offerIdsToUpdate
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            _after(actorsToUpdate, offerIdsToUpdate, _emptyUintArray());
            invariant_OFER_62(offerId);
            invariant_INTR_01(offerId);
            invariant_ESCR_40(states[BEFORE].offerStates[offerId].escrowId, _offerSeizableAmount(offerId));
            invariant_ESCR_41(actorsToUpdate[0], _offerSeizableAmount(offerId));
            invariant_ESCR_42(_offerSeizableAmount(offerId));
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_OFER_64(_returnSelector(returnData), states[BEFORE].tokenIdPaused);
        }
    }

    function seizeDealPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256[] memory offerIdsToUpdate,
        uint256[] memory dealIdsToUpdate
    ) internal {
        if (success) {
            uint256 offerId = offerIdsToUpdate[0];
            uint256 dealId = dealIdsToUpdate[0];
            _after(actorsToUpdate, offerIdsToUpdate, dealIdsToUpdate);
            invariant_DEAL_66(dealId);
            invariant_OFER_63(offerId, _dealSeizableAmount(dealId));
            invariant_ESCR_40(states[BEFORE].offerStates[offerId].escrowId, _dealSeizableAmount(dealId));
            invariant_ESCR_41(actorsToUpdate[0], _dealSeizableAmount(dealId));
            invariant_ESCR_42(_dealSeizableAmount(dealId));
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_DEAL_67(_returnSelector(returnData), states[BEFORE].tokenIdPaused);
        }
    }
}
