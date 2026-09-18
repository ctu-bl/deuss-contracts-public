// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {PropertiesBase} from "./PropertiesBase.sol";
import {Errors} from "src/libs/Errors.sol";

import {DealStatus, SaleMode} from "src/marketplace/MarketStructs.sol";

abstract contract Properties_OFFER is PropertiesBase {
    function invariant_OFER_01() internal {
        fl.eq(states[AFTER].allTrackedOffersBounded, true, OFER_01);
    }

    function invariant_OFER_10(
        uint256 offerId,
        address owner,
        uint256 totalAmount,
        uint256 lot,
        uint256 unitPrice,
        uint256 expiry,
        SaleMode saleMode,
        bool allowCounterOffers,
        uint256 minSaleUnits,
        address[] memory allowedBuyers
    ) internal {
        fl.eq(states[AFTER].offerStates[offerId].owner, owner, OFER_10_OWNER);
        fl.eq(states[AFTER].offerStates[offerId].total, totalAmount, OFER_10_TOTAL);
        fl.eq(states[AFTER].offerStates[offerId].available, totalAmount, OFER_10_AVAILABLE);
        fl.eq(states[AFTER].offerStates[offerId].inDeals, 0, OFER_10_IN_DEALS);
        fl.eq(states[AFTER].offerStates[offerId].sold, 0, OFER_10_SOLD);
        fl.eq(states[AFTER].offerStates[offerId].lot, lot, OFER_10_LOT);
        fl.eq(states[AFTER].offerStates[offerId].unitPrice, unitPrice, OFER_10_UNIT_PRICE);
        fl.eq(states[AFTER].offerStates[offerId].expiry, expiry, OFER_10_EXPIRY);
        fl.eq(uint256(states[AFTER].offerStates[offerId].saleMode), uint256(saleMode), OFER_10_SALE_MODE);
        fl.eq(states[AFTER].offerStates[offerId].allowCounterOffers, allowCounterOffers, OFER_10_COUNTER_OFFERS);
        fl.eq(states[AFTER].offerStates[offerId].minSaleUnits, minSaleUnits, OFER_10_MIN_SALE_UNITS);
        uint256 expectedPaymentExpiryThreshold =
            saleMode == SaleMode.INTEREST_DISCOVERY ? _getInterestDiscoveryPaymentExpiryThreshold() : 0;
        fl.eq(
            states[AFTER].offerStates[offerId].paymentExpiryThreshold,
            expectedPaymentExpiryThreshold,
            OFER_10_PAYMENT_EXPIRY_THRESHOLD
        );
        fl.eq(states[AFTER].offerStates[offerId].interestedUnits, 0, OFER_10_INTERESTED_UNITS);
        fl.eq(states[AFTER].offerStates[offerId].reservedInterestUnits, 0, OFER_10_RESERVED_INTEREST);
        fl.eq(states[AFTER].offerStates[offerId].allowedBuyerCount, allowedBuyers.length, OFER_10_ALLOWED_BUYERS);
        fl.eq(states[AFTER].offerStates[offerId].allowedBuyers.length, allowedBuyers.length, OFER_10_ALLOWED_BUYERS);
        for (uint256 i; i < allowedBuyers.length; ++i) {
            fl.eq(states[AFTER].offerStates[offerId].allowedBuyers[i], allowedBuyers[i], OFER_10_ALLOWED_BUYERS);
        }
    }

    function invariant_OFER_11() internal {
        fl.eq(states[AFTER].offerCounter, states[BEFORE].offerCounter + 1, OFER_11);
    }

    function invariant_OFER_12(address seller, uint256 depositedAmount) internal {
        fl.eq(
            states[AFTER].actorStates[seller].balance + depositedAmount,
            states[BEFORE].actorStates[seller].balance,
            OFER_12
        );
    }

    function invariant_OFER_13(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, OFER_13);
    }

    function invariant_OFER_20(uint256 offerId, uint256 amount) internal {
        fl.eq(
            states[AFTER].offerStates[offerId].available + amount,
            states[BEFORE].offerStates[offerId].available,
            OFER_20
        );
        fl.eq(states[AFTER].offerStates[offerId].inDeals, states[BEFORE].offerStates[offerId].inDeals + amount, OFER_20);
    }

    function invariant_OFER_21(uint256 offerId) internal {
        fl.eq(states[AFTER].offerStates[offerId].cancelled, true, OFER_21);
        fl.eq(states[AFTER].offerStates[offerId].available, 0, OFER_21);
        fl.eq(states[AFTER].offerStates[offerId].expiry, block.timestamp, OFER_21_EXPIRY);
    }

    function invariant_OFER_22(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, OFER_22);
    }

    function invariant_OFER_30(uint256 offerId, uint256 amount) internal {
        fl.eq(states[AFTER].offerStates[offerId].inDeals + amount, states[BEFORE].offerStates[offerId].inDeals, OFER_30);
        fl.eq(states[AFTER].offerStates[offerId].sold, states[BEFORE].offerStates[offerId].sold + amount, OFER_30);
    }

    function invariant_OFER_31(uint256 offerId, uint256 amount) internal {
        fl.eq(states[AFTER].offerStates[offerId].inDeals + amount, states[BEFORE].offerStates[offerId].inDeals, OFER_31);
        fl.eq(
            states[AFTER].offerStates[offerId].available,
            states[BEFORE].offerStates[offerId].available + amount,
            OFER_31
        );
        fl.eq(states[AFTER].offerStates[offerId].sold, states[BEFORE].offerStates[offerId].sold, OFER_31);
    }

    function invariant_OFER_32(uint256 offerId, uint256[] memory dealIds) internal {
        (uint256 paidAmount, uint256 unpaidAmount) = _settledAmountsForOffer(offerId, dealIds);
        uint256 totalSettledAmount = paidAmount + unpaidAmount;
        fl.eq(
            states[AFTER].offerStates[offerId].inDeals + totalSettledAmount,
            states[BEFORE].offerStates[offerId].inDeals,
            OFER_32
        );
    }

    function invariant_OFER_33(uint256 offerId, uint256[] memory dealIds) internal {
        (, uint256 unpaidAmount) = _settledAmountsForOffer(offerId, dealIds);
        fl.eq(
            states[AFTER].offerStates[offerId].available,
            states[BEFORE].offerStates[offerId].available + unpaidAmount,
            OFER_33
        );
    }

    function invariant_OFER_34(uint256 offerId, uint256[] memory dealIds) internal {
        (uint256 paidAmount,) = _settledAmountsForOffer(offerId, dealIds);
        fl.eq(states[AFTER].offerStates[offerId].sold, states[BEFORE].offerStates[offerId].sold + paidAmount, OFER_34);
    }

    function invariant_OFER_40(uint256 offerId) internal {
        fl.eq(states[AFTER].offerStates[offerId].available, states[BEFORE].offerStates[offerId].available, OFER_40);
        fl.eq(states[AFTER].offerStates[offerId].inDeals, states[BEFORE].offerStates[offerId].inDeals, OFER_40);
        fl.eq(states[AFTER].offerStates[offerId].sold, states[BEFORE].offerStates[offerId].sold, OFER_40);
    }

    function invariant_OFER_50(uint256 offerId) internal {
        uint256 withdrawnAmount = _directSaleWithdrawableAmount(offerId);

        fl.eq(
            states[AFTER].offerStates[offerId].available + withdrawnAmount,
            states[BEFORE].offerStates[offerId].available,
            OFER_50
        );
        fl.eq(states[AFTER].offerStates[offerId].inDeals, states[BEFORE].offerStates[offerId].inDeals, OFER_50);
        fl.eq(states[AFTER].offerStates[offerId].sold, states[BEFORE].offerStates[offerId].sold, OFER_50);
    }

    function invariant_OFER_51(address seller, uint256 withdrawnAmount) internal {
        fl.eq(
            states[AFTER].actorStates[seller].balance,
            states[BEFORE].actorStates[seller].balance + withdrawnAmount,
            OFER_51
        );
    }

    function invariant_OFER_52(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = Errors.Marketplace__NoAvailableAmount.selector;
        fl.errAllow(errorSelector, allowedErrors, OFER_52);
    }

    function invariant_OFER_60(uint256 offerId, bool frozen) internal {
        fl.eq(states[AFTER].offerStates[offerId].frozen, frozen, OFER_60);
    }

    function invariant_OFER_61(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, OFER_61);
    }

    function invariant_OFER_62(uint256 offerId) internal {
        fl.eq(states[AFTER].offerStates[offerId].cancelled, true, OFER_62_CANCELLED);
        fl.eq(states[AFTER].offerStates[offerId].available, 0, OFER_62_AVAILABLE);
        fl.eq(states[AFTER].offerStates[offerId].inDeals, states[BEFORE].offerStates[offerId].inDeals, OFER_62_IN_DEALS);
        fl.eq(states[AFTER].offerStates[offerId].sold, states[BEFORE].offerStates[offerId].sold, OFER_62_SOLD);

        if (
            states[BEFORE].offerStates[offerId].saleMode == SaleMode.INTEREST_DISCOVERY
                && states[BEFORE].offerStates[offerId].reservedInterestUnits != 0
        ) {
            fl.eq(states[AFTER].offerStates[offerId].reservedInterestUnits, 0, OFER_62_RESERVED_INTEREST);
            fl.eq(states[AFTER].offerStates[offerId].reservedInterestSeized, true, OFER_62_RESERVED_SEIZED);
        } else {
            fl.eq(
                states[AFTER].offerStates[offerId].reservedInterestUnits,
                states[BEFORE].offerStates[offerId].reservedInterestUnits,
                OFER_62_RESERVED_INTEREST
            );
        }
    }

    function invariant_OFER_63(uint256 offerId, uint256 amount) internal {
        fl.eq(
            states[AFTER].offerStates[offerId].inDeals + amount,
            states[BEFORE].offerStates[offerId].inDeals,
            OFER_63_IN_DEALS
        );
        fl.eq(
            states[AFTER].offerStates[offerId].available,
            states[BEFORE].offerStates[offerId].available,
            OFER_63_AVAILABLE
        );
        fl.eq(states[AFTER].offerStates[offerId].sold, states[BEFORE].offerStates[offerId].sold, OFER_63_SOLD);
    }

    function invariant_OFER_64(bytes4 errorSelector, bool tokenIdPaused) internal {
        bytes4[] memory allowedErrors = new bytes4[](tokenIdPaused ? 1 : 0);
        if (tokenIdPaused) allowedErrors[0] = Errors.Token__TokenIdIsPaused.selector;
        fl.errAllow(errorSelector, allowedErrors, OFER_64);
    }

    function invariant_OFER_70(uint256 maxCounterOffers) internal {
        fl.eq(_getMaxCounterOffersPerUser(), maxCounterOffers, OFER_70);
    }

    function invariant_OFER_71(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = Errors.Marketplace__MaxCounterOffersPerUserZero.selector;
        fl.errAllow(errorSelector, allowedErrors, OFER_71);
    }

    function invariant_OFER_72(uint256 previousMaxCounterOffers) internal {
        fl.eq(_getMaxCounterOffersPerUser(), previousMaxCounterOffers, OFER_72);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _settledAmountsForOffer(uint256 offerId, uint256[] memory dealIds)
        internal
        view
        returns (uint256 paidAmount, uint256 unpaidAmount)
    {
        for (uint256 i; i < dealIds.length; ++i) {
            uint256 dealId = dealIds[i];
            if (states[BEFORE].dealStates[dealId].offerId != offerId) continue;

            if (states[BEFORE].dealStates[dealId].status == DealStatus.PAID) {
                paidAmount += states[BEFORE].dealStates[dealId].amount;
            } else if (states[BEFORE].dealStates[dealId].status == DealStatus.UNPAID) {
                unpaidAmount += states[BEFORE].dealStates[dealId].amount;
            }
        }
    }
}
