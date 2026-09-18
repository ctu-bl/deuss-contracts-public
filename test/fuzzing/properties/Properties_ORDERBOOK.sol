// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {PropertiesBase} from "./PropertiesBase.sol";

abstract contract Properties_ORDERBOOK is PropertiesBase {
    /// @dev OB_11 is only called by orderbookAdminSurfacePostconditions in fixed field order.
    /// Payment expiry and dispute buffer share the same configured value, so value dispatch is ambiguous.
    uint8 private _ob11FieldCursor;

    function invariant_OB_10(address actual, address expected) internal {
        if (expected == address(assetManager)) {
            fl.eq(actual, expected, OB_10_ASSET_MANAGER);
        } else if (expected == address(entityRegistry)) {
            fl.eq(actual, expected, OB_10_ENTITY_REGISTRY);
        } else if (expected == address(escrowManager)) {
            fl.eq(actual, expected, OB_10_ESCROW_MANAGER);
        } else if (expected == address(bondMarketFilter)) {
            fl.eq(actual, expected, OB_10_MARKET_FILTER);
        } else {
            fl.eq(actual, expected, OB_10);
        }
    }

    function invariant_OB_11(uint256 actual, uint256 expected) internal {
        unchecked {
            _ob11FieldCursor = (_ob11FieldCursor % 4) + 1;
        }

        if (_ob11FieldCursor == 1) {
            fl.eq(actual, expected, OB_11_PAYMENT_EXPIRY_THRESHOLD);
        } else if (_ob11FieldCursor == 2) {
            fl.eq(actual, expected, OB_11_MIN_EXPIRY_THRESHOLD);
        } else if (_ob11FieldCursor == 3) {
            fl.eq(actual, expected, OB_11_DISPUTE_BUFFER_PERIOD);
        } else {
            fl.eq(actual, expected, OB_11_MAX_RECENT_OBSERVATIONS);
        }
    }

    function invariant_OB_12(bool success, bytes4 errorSelector) internal {
        fl.eq(success, true, OB_12);
        if (!success) {
            bytes4[] memory allowedErrors = new bytes4[](0);
            fl.errAllow(errorSelector, allowedErrors, OB_12);
        }
    }

    function invariant_OB_13(bool success, bytes4 errorSelector, bytes4 expectedSelector) internal {
        fl.eq(success, false, OB_13);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = expectedSelector;
        fl.errAllow(errorSelector, allowedErrors, OB_13);
    }

    function invariant_OB_14(bool success, bytes4 errorSelector) internal {
        fl.eq(success, true, OB_14);
        if (!success) {
            bytes4[] memory allowedErrors = new bytes4[](0);
            fl.errAllow(errorSelector, allowedErrors, OB_14);
        }
    }
}
