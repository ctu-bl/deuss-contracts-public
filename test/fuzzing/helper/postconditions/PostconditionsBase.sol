// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore */

import {Properties} from "../../properties/Properties.sol";

abstract contract PostconditionsBase is Properties {
    function onSuccessInvariantsGeneral(bytes memory) internal {
        invariant_SPLY_01();
        invariant_SPLY_02();
        invariant_SPLY_03();
        invariant_SPLY_04();
        invariant_SPLY_05();
        invariant_ESCR_01();
        invariant_ESCR_02();
        invariant_ESCR_60();
        invariant_OFER_01();
        invariant_PAUS_01();
        invariant_TKN_01();
        invariant_BOND_01();
        invariant_BOND_02();
        invariant_BOND_03();
        invariant_BOND_04();
        invariant_BOND_05();
    }

    function _returnSelector(bytes memory returnData) internal pure returns (bytes4 errorSelector) {
        if (returnData.length > 3) {
            errorSelector = bytes4(returnData);
        }
    }
}
