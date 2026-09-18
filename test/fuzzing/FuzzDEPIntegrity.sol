// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {FuzzIntegrityBase} from "./FuzzIntegrityBase.sol";
import {HandlerDEP} from "./helper/handlers/HandlerDEP.sol";

/**
 * @title FuzzDEPIntegrity
 * @notice Checks handler integrity for the DependenciesBase write-once wiring harness (G-7 / I-4).
 *
 * Each public `fuzz_*` function encodes the matching `handler_*` selector, delegates into
 * address(this) via `_testSelf`, and allows only `ClampFail` on the failure path. Direct
 * `handler_*` calls by the fuzzer engine are blocked via the engine config blacklist.
 */
contract FuzzDEPIntegrity is HandlerDEP, FuzzIntegrityBase {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         INTEGRITY                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Checks the integrity of `handler_setDependency`
     * @param slotSeed Seed selecting which dependency slot to target
     * @param valueSeed Seed deriving the non-zero candidate address
     */
    function fuzz_setDependency(uint256 slotSeed, uint256 valueSeed) public {
        bytes memory callData = abi.encodeWithSelector(HandlerDEP.handler_setDependency.selector, slotSeed, valueSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "DEP-SET-DEPENDENCY");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setDependencyUnauthorized`
     * @param slotSeed Seed selecting which dependency slot to target
     * @param valueSeed Seed deriving the non-zero candidate address
     * @param callerSeed Seed selecting a non-admin caller
     */
    function fuzz_setDependencyUnauthorized(uint256 slotSeed, uint256 valueSeed, uint256 callerSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerDEP.handler_setDependencyUnauthorized.selector, slotSeed, valueSeed, callerSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "DEP-SET-DEPENDENCY-UNAUTH");
        }
    }
}
