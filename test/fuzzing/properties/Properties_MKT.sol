// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {Errors} from "src/libs/Errors.sol";
import {PropertiesBase} from "./PropertiesBase.sol";

abstract contract Properties_MKT is PropertiesBase {
    function invariant_MKT_80(bool success, bytes4 errorSelector) internal {
        fl.eq(success, true, MKT_80);
        if (!success) {
            bytes4[] memory allowedErrors = new bytes4[](0);
            fl.errAllow(errorSelector, allowedErrors, MKT_80);
        }
    }

    function invariant_MKT_81(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = Errors.DependenciesBase__BondRegistryAlreadySet.selector;
        fl.errAllow(errorSelector, allowedErrors, MKT_81);
    }

    function invariant_MKT_82(bool success, bytes4 errorSelector, bytes4 expectedSelector) internal {
        fl.eq(success, false, MKT_82);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = expectedSelector;
        fl.errAllow(errorSelector, allowedErrors, MKT_82);
    }
}
