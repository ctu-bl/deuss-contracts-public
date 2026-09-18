// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BeforeAfter} from "../BeforeAfter.sol";

abstract contract PreconditionsBase is BeforeAfter {
    error ClampFail(string reason);

    modifier setCurrentActor() {
        if (_setActor) {
            currentActor = msg.sender;
        }
        _;
    }
}
