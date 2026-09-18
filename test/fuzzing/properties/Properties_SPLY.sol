// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {PropertiesBase} from "./PropertiesBase.sol";

abstract contract Properties_SPLY is PropertiesBase {
    function invariant_SPLY_01() internal {
        fl.eq(states[AFTER].totalSupply, states[AFTER].trackedBalanceSum, SPLY_01);
    }

    function invariant_SPLY_02() internal {
        fl.lte(states[AFTER].totalSupply, initialIssuedSupply, SPLY_02);
    }

    function invariant_SPLY_03() internal {
        fl.eq(states[AFTER].bondNominalValue, BOND_NOMINAL_VALUE, SPLY_03);
    }

    function invariant_SPLY_04() internal {
        fl.eq(states[AFTER].totalSupply * states[AFTER].bondNominalValue, states[AFTER].trackedFaceValueSum, SPLY_04);
    }

    function invariant_SPLY_05() internal {
        fl.eq(states[AFTER].totalSupplyAtCurrentBlock, states[AFTER].totalSupply, SPLY_05);
    }
}
