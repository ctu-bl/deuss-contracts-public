// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {Errors} from "src/libs/Errors.sol";
import {DealStatus, DealType, InterestStatus} from "src/marketplace/MarketStructs.sol";
import {PropertiesBase} from "./PropertiesBase.sol";

abstract contract Properties_INTEREST is PropertiesBase {
    function invariant_INTR_01(uint256 offerId) internal {
        fl.gte(
            states[AFTER].offerStates[offerId].interestedUnits,
            states[BEFORE].offerStates[offerId].interestedUnits,
            INTR_01
        );
    }

    function invariant_INTR_10(uint256 offerId, uint256 amount) internal {
        fl.eq(
            states[AFTER].offerStates[offerId].available + amount,
            states[BEFORE].offerStates[offerId].available,
            INTR_10
        );
        fl.eq(states[AFTER].offerStates[offerId].inDeals, states[BEFORE].offerStates[offerId].inDeals, INTR_10);
        fl.eq(
            states[AFTER].offerStates[offerId].interestedUnits,
            states[BEFORE].offerStates[offerId].interestedUnits + amount,
            INTR_10
        );
        fl.eq(
            states[AFTER].offerStates[offerId].reservedInterestUnits,
            states[BEFORE].offerStates[offerId].reservedInterestUnits + amount,
            INTR_10
        );
    }

    function invariant_INTR_11(uint256 interestId, uint256 offerId, uint256 amount, address investor) internal {
        fl.eq(states[AFTER].interestStates[interestId].offerId, offerId, INTR_11_OFFER_ID);
        fl.eq(states[AFTER].interestStates[interestId].amount, amount, INTR_11_AMOUNT);
        fl.eq(states[AFTER].interestStates[interestId].investor, investor, INTR_11_INVESTOR);
        fl.eq(
            states[AFTER].interestStates[interestId].price,
            states[AFTER].offerStates[offerId].unitPrice * amount,
            INTR_11_PRICE
        );
        fl.eq(
            uint256(states[AFTER].interestStates[interestId].status), uint256(InterestStatus.EXPRESSED), INTR_11_STATUS
        );
        uint256 lot = states[AFTER].offerStates[offerId].lot;
        fl.gt(lot, 0, INTR_11_LOT_NONZERO);
        if (lot != 0) {
            fl.eq(amount % lot, 0, INTR_11_AMOUNT_LOT_MULTIPLE);
        }
    }

    function invariant_INTR_12() internal {
        fl.eq(states[AFTER].interestCounter, states[BEFORE].interestCounter + 1, INTR_12);
    }

    function invariant_INTR_13(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, INTR_13);
    }

    function invariant_INTR_20(uint256 offerId, uint256 amount) internal {
        fl.eq(states[AFTER].offerStates[offerId].available, states[BEFORE].offerStates[offerId].available, INTR_20);
        fl.eq(states[AFTER].offerStates[offerId].inDeals, states[BEFORE].offerStates[offerId].inDeals + amount, INTR_20);
        fl.eq(
            states[AFTER].offerStates[offerId].reservedInterestUnits + amount,
            states[BEFORE].offerStates[offerId].reservedInterestUnits,
            INTR_20
        );
    }

    function invariant_INTR_21(uint256 interestId) internal {
        fl.eq(uint256(states[AFTER].interestStates[interestId].status), uint256(InterestStatus.ACTIVATED), INTR_21);
    }

    function invariant_INTR_22(uint256 dealId, uint256 interestId, uint256 offerId, address investor, uint256 amount)
        internal
    {
        fl.eq(states[AFTER].dealStates[dealId].offerId, offerId, INTR_22_OFFER_ID);
        fl.eq(states[AFTER].dealStates[dealId].buyer, investor, INTR_22_BUYER);
        fl.eq(states[AFTER].dealStates[dealId].amount, amount, INTR_22_AMOUNT);
        fl.eq(states[AFTER].dealStates[dealId].price, states[BEFORE].interestStates[interestId].price, INTR_22_PRICE);
        uint256 paymentExpiryThreshold = states[AFTER].offerStates[offerId].paymentExpiryThreshold;
        uint256 offerExpiry = states[AFTER].offerStates[offerId].expiry;
        uint256 expectedPaymentDeadline = offerExpiry + paymentExpiryThreshold;
        if (block.timestamp > offerExpiry) {
            expectedPaymentDeadline = block.timestamp + paymentExpiryThreshold;
        }
        fl.eq(states[AFTER].dealStates[dealId].paymentDeadline, expectedPaymentDeadline, INTR_22_PAYMENT_DEADLINE);
        fl.eq(
            states[AFTER].dealStates[dealId].disputeBuffer,
            expectedPaymentDeadline + _getDisputeBufferPeriod(),
            INTR_22_DISPUTE_BUFFER
        );
        fl.eq(uint256(states[AFTER].dealStates[dealId].status), uint256(DealStatus.PENDING), INTR_22_STATUS);
        fl.eq(uint256(states[AFTER].dealStates[dealId].dealType), uint256(DealType.OFFER), INTR_22_DEAL_TYPE);
    }

    function invariant_INTR_23() internal {
        fl.eq(states[AFTER].dealCounter, states[BEFORE].dealCounter + 1, INTR_23);
    }

    function invariant_INTR_24(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, INTR_24);
    }

    function invariant_INTR_30(uint256 interestId) internal {
        fl.eq(uint256(states[AFTER].interestStates[interestId].status), uint256(InterestStatus.CLOSED), INTR_30);
    }

    function invariant_INTR_31(uint256 offerId, uint256[] memory interestIds) internal {
        uint256 amount;
        for (uint256 i; i < interestIds.length; ++i) {
            amount += states[BEFORE].interestStates[interestIds[i]].amount;
        }

        fl.eq(
            states[AFTER].offerStates[offerId].available,
            states[BEFORE].offerStates[offerId].available + amount,
            INTR_31
        );
        fl.eq(
            states[AFTER].offerStates[offerId].reservedInterestUnits + amount,
            states[BEFORE].offerStates[offerId].reservedInterestUnits,
            INTR_31
        );
        fl.eq(
            states[AFTER].offerStates[offerId].interestedUnits,
            states[BEFORE].offerStates[offerId].interestedUnits,
            INTR_31
        );
    }

    function invariant_INTR_32(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, INTR_32);
    }

    function invariant_INTR_40(uint256 offerId) internal {
        fl.eq(states[AFTER].offerStates[offerId].available, 0, INTR_40);
    }

    function invariant_INTR_43(uint256 offerId) internal {
        fl.eq(states[AFTER].offerStates[offerId].reservedInterestUnits, 0, INTR_43);
    }

    function invariant_INTR_41(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, INTR_41);
    }

    function invariant_INTR_42(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, INTR_42);

        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = Errors.Marketplace__ThresholdNotReached.selector;
        fl.errAllow(errorSelector, allowedErrors, INTR_42);
    }
}
