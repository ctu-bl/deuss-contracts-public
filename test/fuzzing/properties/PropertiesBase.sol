// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable no-empty-blocks */

import {FuzzBase} from "@perimetersec/fuzzlib/src/FuzzBase.sol";
import {SaleMode} from "src/marketplace/MarketStructs.sol";

import {PropertiesDescriptions} from "./PropertiesDescriptions.sol";
import {BeforeAfter} from "../helper/BeforeAfter.sol";

abstract contract PropertiesBase is FuzzBase, BeforeAfter, PropertiesDescriptions {
    function _directSaleWithdrawableAmount(uint256 offerId) internal view returns (uint256 amount) {
        return states[BEFORE].offerStates[offerId].available;
    }

    function _interestDiscoveryWithdrawableAmount(uint256 offerId) internal view returns (uint256 amount) {
        return states[BEFORE].offerStates[offerId].available;
    }

    function _failedInterestDiscoveryCancellationAmount(uint256 offerId) internal view returns (uint256 amount) {
        return states[BEFORE].offerStates[offerId].available + states[BEFORE].offerStates[offerId].reservedInterestUnits;
    }

    function _offerSeizableAmount(uint256 offerId) internal view returns (uint256 amount) {
        amount = states[BEFORE].offerStates[offerId].available;
        if (states[BEFORE].offerStates[offerId].saleMode == SaleMode.INTEREST_DISCOVERY) {
            amount += states[BEFORE].offerStates[offerId].reservedInterestUnits;
        }
    }

    function _dealSeizableAmount(uint256 dealId) internal view returns (uint256 amount) {
        return states[BEFORE].dealStates[dealId].amount;
    }
}
