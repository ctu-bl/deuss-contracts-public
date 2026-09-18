// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {BondStatus} from "src/registry/BondStructs.sol";
import {PropertiesBase} from "./PropertiesBase.sol";

abstract contract Properties_PAUSE is PropertiesBase {
    function invariant_PAUS_01() internal {
        BondStatus status = states[AFTER].bondStatus;
        bool tokenIdPaused = states[AFTER].bondVersionStates[states[AFTER].activeBondVersion].tokenIdPaused;

        if (status == BondStatus.Suspended) {
            fl.eq(tokenIdPaused, true, PAUS_01);
            return;
        }

        if (status == BondStatus.Issued) {
            fl.eq(tokenIdPaused, false, PAUS_01);
            return;
        }

        if (status == BondStatus.Redeemed) {
            fl.eq(states[AFTER].bondVersionStates[states[AFTER].activeBondVersion].totalSupply, 0, PAUS_01);
        }
    }
}
