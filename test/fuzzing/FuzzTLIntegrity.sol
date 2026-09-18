// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {FuzzIntegrityBase} from "./FuzzIntegrityBase.sol";
import {HandlerTL} from "./helper/handlers/HandlerTL.sol";

/**
 * @title FuzzTLIntegrity
 * @notice Checks handler integrity for the governance TimelockController fuzz harness.
 *
 * Each public `fuzz_*` function encodes the matching `handler_*` selector, delegates
 * into address(this) via `_testSelf`, and allows only `ClampFail` on the failure path.
 * Direct `handler_*` calls by the fuzzer engine are blocked via the engine config blacklist.
 */
contract FuzzTLIntegrity is HandlerTL, FuzzIntegrityBase {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         INTEGRITY                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Checks the integrity of `handler_scheduleTL`.
    function fuzz_scheduleTL(uint256 targetSeed, uint256 dataSeed, uint256 delaySeed, bool usePredecessor) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerTL.handler_scheduleTL.selector, targetSeed, dataSeed, delaySeed, usePredecessor
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "TL-SCHEDULE");
        }
    }

    /// @notice Checks the integrity of `handler_executeTL`.
    function fuzz_executeTL(uint256 opSeed, bool useTracked) public {
        bytes memory callData = abi.encodeWithSelector(HandlerTL.handler_executeTL.selector, opSeed, useTracked);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "TL-EXECUTE");
        }
    }

    /// @notice Checks the integrity of `handler_cancelTL`.
    function fuzz_cancelTL(uint256 opSeed, bool useTracked) public {
        bytes memory callData = abi.encodeWithSelector(HandlerTL.handler_cancelTL.selector, opSeed, useTracked);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "TL-CANCEL");
        }
    }

    /// @notice Checks the integrity of `handler_updateDelayTL`.
    function fuzz_updateDelayTL(uint256 delaySeed) public {
        bytes memory callData = abi.encodeWithSelector(HandlerTL.handler_updateDelayTL.selector, delaySeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "TL-UPDATE-DELAY");
        }
    }
}
