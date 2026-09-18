// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {DealStatus, DealType, SaleMode} from "src/marketplace/MarketStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {PropertiesBase} from "./PropertiesBase.sol";

abstract contract Properties_DEAL is PropertiesBase {
    function invariant_DEAL_01(uint256 dealId, uint256 offerId, address buyer, uint256 amount) internal {
        uint256 lot = states[AFTER].offerStates[offerId].lot;
        uint256 expectedPaymentDeadline = block.timestamp + _directSalePaymentExpiryThreshold(offerId);

        fl.eq(states[AFTER].dealStates[dealId].offerId, offerId, DEAL_01_OFFER_ID);
        fl.eq(states[AFTER].dealStates[dealId].buyer, buyer, DEAL_01_BUYER);
        fl.eq(states[AFTER].dealStates[dealId].amount, amount, DEAL_01_AMOUNT);
        fl.eq(
            states[AFTER].dealStates[dealId].price, states[AFTER].offerStates[offerId].unitPrice * amount, DEAL_01_PRICE
        );
        fl.eq(states[AFTER].dealStates[dealId].paymentDeadline, expectedPaymentDeadline, DEAL_01_PAYMENT_DEADLINE);
        fl.eq(
            states[AFTER].dealStates[dealId].disputeBuffer,
            expectedPaymentDeadline + _getDisputeBufferPeriod(),
            DEAL_01_DISPUTE_BUFFER
        );
        fl.eq(uint256(states[AFTER].dealStates[dealId].status), uint256(DealStatus.PENDING), DEAL_01_STATUS);
        fl.eq(uint256(states[AFTER].dealStates[dealId].dealType), uint256(DealType.OFFER), DEAL_01_DEAL_TYPE);
        fl.eq(buyer != states[AFTER].offerStates[offerId].owner, true, DEAL_01_BUYER_NOT_OWNER);
        fl.gt(lot, 0, DEAL_01_LOT_NONZERO);
        if (lot != 0) {
            fl.eq(amount % lot, 0, DEAL_01_AMOUNT_LOT_MULTIPLE);
        }
    }

    function invariant_DEAL_02() internal {
        fl.eq(states[AFTER].dealCounter, states[BEFORE].dealCounter + 1, DEAL_02);
    }

    function invariant_DEAL_03(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, DEAL_03);
    }

    function invariant_DEAL_10(uint256 dealId) internal {
        fl.eq(uint256(states[AFTER].dealStates[dealId].status), uint256(DealStatus.PAID), DEAL_10);
    }

    function invariant_DEAL_12(uint256 dealId) internal {
        fl.eq(uint256(states[AFTER].dealStates[dealId].status), uint256(DealStatus.UNPAID), DEAL_12);
    }

    function invariant_DEAL_11(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, DEAL_11);
    }

    function invariant_DEAL_13(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, DEAL_13);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("Unauthorized()"));
        fl.errAllow(errorSelector, allowedErrors, DEAL_13);
    }

    function invariant_DEAL_14_PAID_STATUS(uint256 dealId) internal {
        fl.eq(uint256(states[AFTER].dealStates[dealId].status), uint256(DealStatus.PAID), DEAL_14_PAID_STATUS);
    }

    function invariant_DEAL_14_UNPAID_STATUS(uint256 dealId) internal {
        fl.eq(uint256(states[AFTER].dealStates[dealId].status), uint256(DealStatus.UNPAID), DEAL_14_UNPAID_STATUS);
    }

    function invariant_DEAL_15_RESOLVER_NOT_PAYMENT_HANDLER(address resolver) internal {
        fl.eq(
            marketplace.hasAllRoles(resolver, marketplace.PAYMENT_HANDLER()),
            false,
            DEAL_15_RESOLVER_NOT_PAYMENT_HANDLER
        );
    }

    function invariant_DEAL_15_STATUS(uint256 dealId) internal {
        fl.eq(uint256(states[AFTER].dealStates[dealId].status), uint256(DealStatus.UNPAID), DEAL_15_STATUS);
    }

    function invariant_DEAL_15_OFFER_ID(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].offerId, states[BEFORE].dealStates[dealId].offerId, DEAL_15_OFFER_ID);
    }

    function invariant_DEAL_15_AMOUNT(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].amount, states[BEFORE].dealStates[dealId].amount, DEAL_15_AMOUNT);
    }

    function invariant_DEAL_15_BUYER(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].buyer, states[BEFORE].dealStates[dealId].buyer, DEAL_15_BUYER);
    }

    function invariant_DEAL_15_PRICE(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].price, states[BEFORE].dealStates[dealId].price, DEAL_15_PRICE);
    }

    function invariant_DEAL_15_COUNTER_OFFER_EXPIRY(uint256 dealId) internal {
        fl.eq(
            states[AFTER].dealStates[dealId].counterOfferExpiry,
            states[BEFORE].dealStates[dealId].counterOfferExpiry,
            DEAL_15_COUNTER_OFFER_EXPIRY
        );
    }

    function invariant_DEAL_15_PAYMENT_DEADLINE(uint256 dealId) internal {
        fl.eq(
            states[AFTER].dealStates[dealId].paymentDeadline,
            states[BEFORE].dealStates[dealId].paymentDeadline,
            DEAL_15_PAYMENT_DEADLINE
        );
    }

    function invariant_DEAL_15_DISPUTE_BUFFER(uint256 dealId) internal {
        fl.eq(
            states[AFTER].dealStates[dealId].disputeBuffer,
            states[BEFORE].dealStates[dealId].disputeBuffer,
            DEAL_15_DISPUTE_BUFFER
        );
    }

    function invariant_DEAL_15_DEAL_TYPE(uint256 dealId) internal {
        fl.eq(
            uint256(states[AFTER].dealStates[dealId].dealType),
            uint256(states[BEFORE].dealStates[dealId].dealType),
            DEAL_15_DEAL_TYPE
        );
    }

    function invariant_DEAL_16_REVERTS(bool success) internal {
        fl.eq(success, false, DEAL_16_REVERTS);
    }

    function invariant_DEAL_16_ERROR(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("Unauthorized()"));
        fl.errAllow(errorSelector, allowedErrors, DEAL_16_ERROR);
    }

    function invariant_DEAL_16_OFFER_ID(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].offerId, states[BEFORE].dealStates[dealId].offerId, DEAL_16_OFFER_ID);
    }

    function invariant_DEAL_16_AMOUNT(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].amount, states[BEFORE].dealStates[dealId].amount, DEAL_16_AMOUNT);
    }

    function invariant_DEAL_16_BUYER(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].buyer, states[BEFORE].dealStates[dealId].buyer, DEAL_16_BUYER);
    }

    function invariant_DEAL_16_PRICE(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].price, states[BEFORE].dealStates[dealId].price, DEAL_16_PRICE);
    }

    function invariant_DEAL_16_COUNTER_OFFER_EXPIRY(uint256 dealId) internal {
        fl.eq(
            states[AFTER].dealStates[dealId].counterOfferExpiry,
            states[BEFORE].dealStates[dealId].counterOfferExpiry,
            DEAL_16_COUNTER_OFFER_EXPIRY
        );
    }

    function invariant_DEAL_16_PAYMENT_DEADLINE(uint256 dealId) internal {
        fl.eq(
            states[AFTER].dealStates[dealId].paymentDeadline,
            states[BEFORE].dealStates[dealId].paymentDeadline,
            DEAL_16_PAYMENT_DEADLINE
        );
    }

    function invariant_DEAL_16_DISPUTE_BUFFER(uint256 dealId) internal {
        fl.eq(
            states[AFTER].dealStates[dealId].disputeBuffer,
            states[BEFORE].dealStates[dealId].disputeBuffer,
            DEAL_16_DISPUTE_BUFFER
        );
    }

    function invariant_DEAL_16_STATUS(uint256 dealId) internal {
        fl.eq(
            uint256(states[AFTER].dealStates[dealId].status),
            uint256(states[BEFORE].dealStates[dealId].status),
            DEAL_16_STATUS
        );
    }

    function invariant_DEAL_16_DEAL_TYPE(uint256 dealId) internal {
        fl.eq(
            uint256(states[AFTER].dealStates[dealId].dealType),
            uint256(states[BEFORE].dealStates[dealId].dealType),
            DEAL_16_DEAL_TYPE
        );
    }

    function invariant_DEAL_17(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, DEAL_17);
    }

    function invariant_DEAL_18_BEFORE_PENDING(uint256 dealId) internal {
        fl.eq(uint256(states[BEFORE].dealStates[dealId].status), uint256(DealStatus.PENDING), DEAL_18_BEFORE_PENDING);
    }

    function invariant_DEAL_18_OFFER_ID(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].offerId, states[BEFORE].dealStates[dealId].offerId, DEAL_18_OFFER_ID);
    }

    function invariant_DEAL_18_AMOUNT(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].amount, states[BEFORE].dealStates[dealId].amount, DEAL_18_AMOUNT);
    }

    function invariant_DEAL_18_BUYER(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].buyer, states[BEFORE].dealStates[dealId].buyer, DEAL_18_BUYER);
    }

    function invariant_DEAL_18_PRICE(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].price, states[BEFORE].dealStates[dealId].price, DEAL_18_PRICE);
    }

    function invariant_DEAL_18_COUNTER_OFFER_EXPIRY(uint256 dealId) internal {
        fl.eq(
            states[AFTER].dealStates[dealId].counterOfferExpiry,
            states[BEFORE].dealStates[dealId].counterOfferExpiry,
            DEAL_18_COUNTER_OFFER_EXPIRY
        );
    }

    function invariant_DEAL_18_PAYMENT_DEADLINE(uint256 dealId) internal {
        fl.eq(
            states[AFTER].dealStates[dealId].paymentDeadline,
            states[BEFORE].dealStates[dealId].paymentDeadline,
            DEAL_18_PAYMENT_DEADLINE
        );
    }

    function invariant_DEAL_18_DISPUTE_BUFFER(uint256 dealId) internal {
        fl.eq(
            states[AFTER].dealStates[dealId].disputeBuffer,
            states[BEFORE].dealStates[dealId].disputeBuffer,
            DEAL_18_DISPUTE_BUFFER
        );
    }

    function invariant_DEAL_18_STATUS(uint256 dealId) internal {
        fl.eq(
            uint256(states[AFTER].dealStates[dealId].status),
            uint256(states[BEFORE].dealStates[dealId].status),
            DEAL_18_STATUS
        );
    }

    function invariant_DEAL_18_DEAL_TYPE(uint256 dealId) internal {
        fl.eq(
            uint256(states[AFTER].dealStates[dealId].dealType),
            uint256(states[BEFORE].dealStates[dealId].dealType),
            DEAL_18_DEAL_TYPE
        );
    }

    function invariant_DEAL_20(uint256 dealId) internal {
        DealStatus previousStatus = states[BEFORE].dealStates[dealId].status;
        DealStatus expectedStatus = previousStatus == DealStatus.PAID ? DealStatus.SUCCESSFUL : DealStatus.UNSUCCESSFUL;

        fl.eq(uint256(states[AFTER].dealStates[dealId].status), uint256(expectedStatus), DEAL_20);
    }

    function invariant_DEAL_21(address buyer, uint256 amount) internal {
        fl.eq(states[AFTER].actorStates[buyer].balance, states[BEFORE].actorStates[buyer].balance + amount, DEAL_21);
    }

    function invariant_DEAL_23(address buyer) internal {
        fl.eq(states[AFTER].actorStates[buyer].balance, states[BEFORE].actorStates[buyer].balance, DEAL_23);
    }

    function invariant_DEAL_24(uint256 dealId) internal {
        fl.eq(
            uint256(states[AFTER].dealStates[dealId].status), uint256(states[BEFORE].dealStates[dealId].status), DEAL_24
        );
    }

    function invariant_DEAL_batchBuyerBalance(address buyer, uint256[] memory dealIds) internal {
        uint256 paidAmount;
        for (uint256 i; i < dealIds.length; ++i) {
            uint256 dealId = dealIds[i];
            if (states[BEFORE].dealStates[dealId].buyer != buyer) continue;
            if (states[BEFORE].dealStates[dealId].status == DealStatus.PAID) {
                paidAmount += states[BEFORE].dealStates[dealId].amount;
            }
        }
        if (paidAmount == 0) {
            invariant_DEAL_23(buyer);
        } else {
            invariant_DEAL_21(buyer, paidAmount);
        }
    }

    function invariant_DEAL_22(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, DEAL_22);
    }

    function invariant_DEAL_30(
        uint256 dealId,
        uint256 offerId,
        address buyer,
        uint256 amount,
        uint256 unitPrice,
        uint256 counterOfferExpiry
    ) internal {
        fl.eq(states[AFTER].dealStates[dealId].offerId, offerId, DEAL_30_OFFER_ID);
        fl.eq(states[AFTER].dealStates[dealId].buyer, buyer, DEAL_30_BUYER);
        fl.eq(states[AFTER].dealStates[dealId].amount, amount, DEAL_30_AMOUNT);
        fl.eq(states[AFTER].dealStates[dealId].price, unitPrice * amount, DEAL_30_PRICE);
        fl.eq(states[AFTER].dealStates[dealId].counterOfferExpiry, counterOfferExpiry, DEAL_30_COUNTER_EXPIRY);
        fl.eq(states[AFTER].dealStates[dealId].paymentDeadline, 0, DEAL_30_PAYMENT_DEADLINE);
        fl.eq(states[AFTER].dealStates[dealId].disputeBuffer, 0, DEAL_30_DISPUTE_BUFFER);
        fl.eq(uint256(states[AFTER].dealStates[dealId].status), uint256(DealStatus.PROPOSED), DEAL_30_STATUS);
        fl.eq(uint256(states[AFTER].dealStates[dealId].dealType), uint256(DealType.COUNTER_OFFER), DEAL_30_TYPE);
    }

    function invariant_DEAL_31() internal {
        fl.eq(states[AFTER].dealCounter, states[BEFORE].dealCounter + 1, DEAL_31);
    }

    function invariant_DEAL_32(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, DEAL_32);
    }

    function invariant_DEAL_40(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].offerId, states[BEFORE].dealStates[dealId].offerId, DEAL_40_OFFER_ID);
        fl.eq(states[AFTER].dealStates[dealId].amount, states[BEFORE].dealStates[dealId].amount, DEAL_40_AMOUNT);
        fl.eq(states[AFTER].dealStates[dealId].buyer, states[BEFORE].dealStates[dealId].buyer, DEAL_40_BUYER);
        fl.eq(states[AFTER].dealStates[dealId].price, states[BEFORE].dealStates[dealId].price, DEAL_40_PRICE);
        fl.eq(
            states[AFTER].dealStates[dealId].counterOfferExpiry,
            states[BEFORE].dealStates[dealId].counterOfferExpiry,
            DEAL_40_COUNTER_EXPIRY
        );
        fl.eq(states[AFTER].dealStates[dealId].paymentDeadline, 0, DEAL_40_PAYMENT_DEADLINE);
        fl.eq(states[AFTER].dealStates[dealId].disputeBuffer, 0, DEAL_40_DISPUTE_BUFFER);
        fl.eq(uint256(states[AFTER].dealStates[dealId].status), uint256(DealStatus.CANCELLED), DEAL_40_STATUS);
        fl.eq(uint256(states[AFTER].dealStates[dealId].dealType), uint256(DealType.COUNTER_OFFER), DEAL_40_TYPE);
    }

    function invariant_DEAL_41(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, DEAL_41);
    }

    function invariant_DEAL_50(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].offerId, states[BEFORE].dealStates[dealId].offerId, DEAL_50_OFFER_ID);
        fl.eq(states[AFTER].dealStates[dealId].amount, states[BEFORE].dealStates[dealId].amount, DEAL_50_AMOUNT);
        fl.eq(states[AFTER].dealStates[dealId].buyer, states[BEFORE].dealStates[dealId].buyer, DEAL_50_BUYER);
        fl.eq(states[AFTER].dealStates[dealId].price, states[BEFORE].dealStates[dealId].price, DEAL_50_PRICE);
        fl.eq(uint256(states[AFTER].dealStates[dealId].status), uint256(DealStatus.PENDING), DEAL_50_STATUS);
        fl.eq(states[AFTER].dealStates[dealId].counterOfferExpiry, 0, DEAL_50_COUNTER_EXPIRY);
        fl.gt(states[AFTER].dealStates[dealId].paymentDeadline, 0, DEAL_50_PAYMENT_DEADLINE);
        fl.eq(
            states[AFTER].dealStates[dealId].disputeBuffer,
            states[AFTER].dealStates[dealId].paymentDeadline + _getDisputeBufferPeriod(),
            DEAL_50_DISPUTE_BUFFER
        );
        fl.eq(uint256(states[AFTER].dealStates[dealId].dealType), uint256(DealType.OFFER), DEAL_50_TYPE);
    }

    function invariant_DEAL_51_OFFER_ID(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].offerId, states[BEFORE].dealStates[dealId].offerId, DEAL_51_OFFER_ID);
    }

    function invariant_DEAL_51_AMOUNT(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].amount, states[BEFORE].dealStates[dealId].amount, DEAL_51_AMOUNT);
    }

    function invariant_DEAL_51_BUYER(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].buyer, states[BEFORE].dealStates[dealId].buyer, DEAL_51_BUYER);
    }

    function invariant_DEAL_51_PRICE(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].price, states[BEFORE].dealStates[dealId].price, DEAL_51_PRICE);
    }

    function invariant_DEAL_51_STATUS(uint256 dealId) internal {
        fl.eq(uint256(states[AFTER].dealStates[dealId].status), uint256(DealStatus.DECLINED), DEAL_51_STATUS);
    }

    function invariant_DEAL_51_COUNTER_OFFER_EXPIRY(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].counterOfferExpiry, 0, DEAL_51_COUNTER_OFFER_EXPIRY);
    }

    function invariant_DEAL_51_PAYMENT_DEADLINE(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].paymentDeadline, 0, DEAL_51_PAYMENT_DEADLINE);
    }

    function invariant_DEAL_51_DISPUTE_BUFFER(uint256 dealId) internal {
        fl.eq(states[AFTER].dealStates[dealId].disputeBuffer, 0, DEAL_51_DISPUTE_BUFFER);
    }

    function invariant_DEAL_51_DEAL_TYPE(uint256 dealId) internal {
        fl.eq(uint256(states[AFTER].dealStates[dealId].dealType), uint256(DealType.COUNTER_OFFER), DEAL_51_DEAL_TYPE);
    }

    function invariant_DEAL_52(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, DEAL_52);
    }

    function invariant_DEAL_60(uint256 dealId) internal {
        fl.eq(uint256(states[AFTER].dealStates[dealId].status), uint256(DealStatus.IN_DISPUTE), DEAL_60_STATUS);
        fl.eq(
            states[AFTER].dealStates[dealId].disputeBuffer,
            states[BEFORE].dealStates[dealId].disputeBuffer,
            DEAL_60_DISPUTE_BUFFER
        );
    }

    function invariant_DEAL_61(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, DEAL_61);
    }

    function invariant_DEAL_62(uint256 dealId, DealStatus status) internal {
        fl.eq(uint256(states[AFTER].dealStates[dealId].status), uint256(status), DEAL_62_STATUS);
        fl.eq(states[AFTER].dealStates[dealId].disputeBuffer, 0, DEAL_62_DISPUTE_BUFFER);
    }

    function invariant_DEAL_63(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, DEAL_63);
    }

    function invariant_DEAL_64(uint256 dealId, bool frozen) internal {
        fl.eq(states[AFTER].dealStates[dealId].frozen, frozen, DEAL_64_FROZEN);
        fl.eq(
            uint256(states[AFTER].dealStates[dealId].status),
            uint256(states[BEFORE].dealStates[dealId].status),
            DEAL_64_STATUS
        );
    }

    function invariant_DEAL_65(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, DEAL_65);
    }

    function invariant_DEAL_66(uint256 dealId) internal {
        fl.eq(uint256(states[AFTER].dealStates[dealId].status), uint256(DealStatus.SEIZED), DEAL_66_STATUS);
        fl.eq(states[AFTER].dealStates[dealId].offerId, states[BEFORE].dealStates[dealId].offerId, DEAL_66_OFFER_ID);
        fl.eq(states[AFTER].dealStates[dealId].amount, states[BEFORE].dealStates[dealId].amount, DEAL_66_AMOUNT);
        fl.eq(states[AFTER].dealStates[dealId].buyer, states[BEFORE].dealStates[dealId].buyer, DEAL_66_BUYER);
        fl.eq(states[AFTER].dealStates[dealId].price, states[BEFORE].dealStates[dealId].price, DEAL_66_PRICE);
    }

    function invariant_DEAL_67(bytes4 errorSelector, bool tokenIdPaused) internal {
        bytes4[] memory allowedErrors = new bytes4[](tokenIdPaused ? 1 : 0);
        if (tokenIdPaused) allowedErrors[0] = Errors.Token__TokenIdIsPaused.selector;
        fl.errAllow(errorSelector, allowedErrors, DEAL_67);
    }

    function _directSalePaymentExpiryThreshold(uint256 offerId) internal returns (uint256 threshold) {
        SaleMode saleMode = states[AFTER].offerStates[offerId].saleMode;

        fl.eq(saleMode == SaleMode.MARKETPLACE || saleMode == SaleMode.REDEMPTION, true, DEAL_01_DIRECT_SALE_MODE);

        if (saleMode == SaleMode.REDEMPTION) {
            return _getRedemptionPaymentThreshold();
        }

        return _getMarketplacePaymentExpiryThreshold();
    }
}
