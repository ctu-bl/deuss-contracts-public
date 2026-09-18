// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {PropertiesBase} from "./PropertiesBase.sol";

abstract contract Properties_BMF is PropertiesBase {
    function invariant_BMF_10(address actualAdapter, address expectedAdapter) internal {
        fl.eq(actualAdapter, expectedAdapter, BMF_10);
    }

    function invariant_BMF_20(bool actualMatch, bool expectedMatch) internal {
        fl.eq(actualMatch, expectedMatch, BMF_20);
    }

    function invariant_BMF_30(bool success, bytes4 errorSelector, bytes4 expectedSelector) internal {
        fl.eq(success, false, BMF_30);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = expectedSelector;
        fl.errAllow(errorSelector, allowedErrors, BMF_30);
    }
}
