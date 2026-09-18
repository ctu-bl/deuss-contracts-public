// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {AssetType, DealStatus, Escrow} from "src/marketplace/MarketStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {PropertiesBase} from "./PropertiesBase.sol";

abstract contract Properties_ESCROW is PropertiesBase {
    function invariant_ESCR_01() internal {
        fl.eq(
            states[AFTER].escrowBalance, states[AFTER].trackedEscrowAmountSum + states[AFTER].escrowSweepable, ESCR_01
        );
    }

    function invariant_ESCR_02() internal {
        fl.eq(states[AFTER].allTrackedEscrowsMatchOfferHoldings, true, ESCR_02);
    }

    function invariant_ESCR_10(uint256 offerId) internal {
        fl.gt(states[AFTER].offerStates[offerId].escrowId, 0, ESCR_10);
    }

    function invariant_ESCR_11(uint256 offerId, uint256 depositedAmount) internal {
        uint256 escrowId = states[AFTER].offerStates[offerId].escrowId;
        fl.eq(states[AFTER].escrowStates[escrowId].amount, depositedAmount, ESCR_11);
    }

    function invariant_ESCR_12(uint256 offerId) internal {
        uint256 escrowId = states[BEFORE].offerStates[offerId].escrowId;
        uint256 availableBefore = states[BEFORE].offerStates[offerId].available;

        fl.eq(
            states[AFTER].escrowStates[escrowId].amount + availableBefore,
            states[BEFORE].escrowStates[escrowId].amount,
            ESCR_12
        );
    }

    function invariant_ESCR_13(uint256 offerId, uint256 amount) internal {
        uint256 escrowId = states[BEFORE].offerStates[offerId].escrowId;
        fl.eq(
            states[AFTER].escrowStates[escrowId].amount + amount, states[BEFORE].escrowStates[escrowId].amount, ESCR_13
        );
    }

    function invariant_ESCR_14(uint256 offerId, uint256 amount) internal {
        uint256 escrowId = states[BEFORE].offerStates[offerId].escrowId;
        fl.eq(
            states[AFTER].escrowStates[escrowId].amount + amount, states[BEFORE].escrowStates[escrowId].amount, ESCR_14
        );
    }

    function invariant_ESCR_15(uint256 offerId) internal {
        uint256 escrowId = states[BEFORE].offerStates[offerId].escrowId;
        fl.eq(states[AFTER].escrowStates[escrowId].amount, states[BEFORE].escrowStates[escrowId].amount, ESCR_15);
    }

    function invariant_ESCR_16(uint256 offerId, uint256[] memory dealIds) internal {
        uint256 paidAmount;
        for (uint256 i; i < dealIds.length; ++i) {
            uint256 dealId = dealIds[i];
            if (states[BEFORE].dealStates[dealId].offerId != offerId) continue;
            if (states[BEFORE].dealStates[dealId].status == DealStatus.PAID) {
                paidAmount += states[BEFORE].dealStates[dealId].amount;
            }
        }

        uint256 escrowId = states[BEFORE].offerStates[offerId].escrowId;
        fl.eq(
            states[AFTER].escrowStates[escrowId].amount + paidAmount,
            states[BEFORE].escrowStates[escrowId].amount,
            ESCR_16
        );
    }

    function invariant_ESCR_20(
        uint256 escrowId,
        address depositor,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount
    ) internal {
        Escrow memory escrow = escrowManager.getEscrow(escrowId);
        fl.eq(escrow.depositor, depositor, ESCR_20_DEPOSITOR);
        fl.eq(escrow.tokenAddress, tokenAddress, ESCR_20_TOKEN);
        fl.eq(escrow.tokenId, tokenId, ESCR_20_TOKEN_ID);
        fl.eq(escrow.amount, amount, ESCR_20_AMOUNT);
        fl.eq(uint256(escrow.assetType), uint256(AssetType.ERC6909), ESCR_20_ASSET_TYPE);
        fl.eq(uint256(escrow.moduleType), uint256(FUZZ_ESCROW_TEST_MODULE_TYPE), ESCR_20_MODULE_TYPE);
    }

    function invariant_ESCR_21() internal {
        fl.eq(states[AFTER].nextEscrowId, states[BEFORE].nextEscrowId + 1, ESCR_21);
    }

    function invariant_ESCR_22(uint256 amount) internal {
        fl.eq(states[AFTER].escrowBalance, states[BEFORE].escrowBalance + amount, ESCR_22);
    }

    function invariant_ESCR_23(address depositor, uint256 amount) internal {
        fl.eq(
            states[AFTER].actorStates[depositor].balance + amount,
            states[BEFORE].actorStates[depositor].balance,
            ESCR_23
        );
    }

    function invariant_ESCR_24(uint256 amount) internal {
        fl.eq(states[AFTER].escrowReserved, states[BEFORE].escrowReserved + amount, ESCR_24);
    }

    function invariant_ESCR_25(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, ESCR_25);
    }

    function invariant_ESCR_26(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, ESCR_26);
        bytes4[] memory allowedErrors = new bytes4[](2);
        allowedErrors[0] = Errors.EscrowManager__ModuleNotRegistered.selector;
        allowedErrors[1] = Errors.EscrowManager__ModuleNotAuthorized.selector;
        fl.errAllow(errorSelector, allowedErrors, ESCR_26);
    }

    function invariant_ESCR_30(uint256 escrowId, uint256 amount) internal {
        fl.eq(
            states[AFTER].escrowStates[escrowId].amount + amount, states[BEFORE].escrowStates[escrowId].amount, ESCR_30
        );
    }

    function invariant_ESCR_31(address depositor, uint256 amount) internal {
        fl.eq(
            states[AFTER].actorStates[depositor].balance,
            states[BEFORE].actorStates[depositor].balance + amount,
            ESCR_31
        );
    }

    function invariant_ESCR_32(uint256 amount) internal {
        fl.eq(states[AFTER].escrowBalance + amount, states[BEFORE].escrowBalance, ESCR_32);
    }

    function invariant_ESCR_33(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, ESCR_33);
    }

    function invariant_ESCR_40(uint256 escrowId, uint256 amount) internal {
        fl.eq(
            states[AFTER].escrowStates[escrowId].amount + amount, states[BEFORE].escrowStates[escrowId].amount, ESCR_40
        );
    }

    function invariant_ESCR_41(address beneficiary, uint256 amount) internal {
        fl.eq(
            states[AFTER].actorStates[beneficiary].balance,
            states[BEFORE].actorStates[beneficiary].balance + amount,
            ESCR_41
        );
    }

    function invariant_ESCR_42(uint256 amount) internal {
        fl.eq(states[AFTER].escrowBalance + amount, states[BEFORE].escrowBalance, ESCR_42);
    }

    function invariant_ESCR_43(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, ESCR_43);
    }

    function invariant_ESCR_50() internal {
        fl.eq(states[AFTER].trackedEscrowAmountSum, states[BEFORE].trackedEscrowAmountSum, ESCR_50);
    }

    function invariant_ESCR_51() internal {
        fl.gte(states[AFTER].escrowBalance, states[AFTER].escrowReserved, ESCR_51);
    }

    function invariant_ESCR_52(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, ESCR_52);
    }

    function invariant_ESCR_53(address sender, uint256 amount) internal {
        fl.eq(states[AFTER].actorStates[sender].balance + amount, states[BEFORE].actorStates[sender].balance, ESCR_53);
    }

    function invariant_ESCR_54(uint256 amount) internal {
        fl.eq(states[AFTER].escrowBalance, states[BEFORE].escrowBalance + amount, ESCR_54);
    }

    function invariant_ESCR_55() internal {
        fl.eq(states[AFTER].trackedEscrowAmountSum, states[BEFORE].trackedEscrowAmountSum, ESCR_55);
    }

    function invariant_ESCR_56() internal {
        fl.eq(states[AFTER].escrowReserved, states[BEFORE].escrowReserved, ESCR_56);
    }

    function invariant_ESCR_57(uint256 amount) internal {
        fl.eq(states[AFTER].escrowSweepable, states[BEFORE].escrowSweepable + amount, ESCR_57);
    }

    function invariant_ESCR_58(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = Errors.Token__ProtectedReceiverTransferNotAllowed.selector;
        fl.errAllow(errorSelector, allowedErrors, ESCR_58);
    }

    function invariant_ESCR_60() internal {
        fl.gte(states[AFTER].escrowBalance, states[AFTER].escrowReserved, ESCR_60);
    }

    function invariant_ESCR_61() internal {
        fl.eq(states[AFTER].trackedEscrowAmountSum, states[BEFORE].trackedEscrowAmountSum, ESCR_61_TRACKED_SUM);
        fl.eq(states[AFTER].escrowBalance, states[BEFORE].escrowBalance, ESCR_61_BALANCE);
        fl.eq(states[AFTER].escrowReserved, states[BEFORE].escrowReserved, ESCR_61_RESERVED);
    }

    function invariant_ESCR_62(address moduleAddress) internal {
        fl.eq(escrowManager.isAuthorizedModule(FUZZ_ESCROW_TEST_MODULE_TYPE, moduleAddress), false, ESCR_62_AUTHORIZED);
        fl.eq(escrowManager.moduleTypeOf(moduleAddress) == bytes32(0), true, ESCR_62_MODULE_TYPE);
    }

    function invariant_ESCR_63(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, ESCR_63);
    }

    function invariant_ESCR_64(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = Errors.EscrowManager__ModuleHasActiveEscrows.selector;
        fl.errAllow(errorSelector, allowedErrors, ESCR_64);
    }

    function invariant_ESCR_70(bool success, bytes4 errorSelector) internal {
        fl.eq(success, true, ESCR_70);
        if (!success) {
            bytes4[] memory allowedErrors = new bytes4[](0);
            fl.errAllow(errorSelector, allowedErrors, ESCR_70);
        }
    }

    function invariant_ESCR_71(uint256 actualBalance) internal {
        fl.eq(actualBalance, 1, ESCR_71);
    }

    function invariant_ESCR_72(bool success, bytes4 errorSelector, bytes4 expectedSelector) internal {
        fl.eq(success, false, ESCR_72);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = expectedSelector;
        fl.errAllow(errorSelector, allowedErrors, ESCR_72);
    }
}
