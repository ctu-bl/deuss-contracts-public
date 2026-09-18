// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {FuzzIntegrityBase} from "./FuzzIntegrityBase.sol";
import {HandlerWALLET} from "./helper/handlers/HandlerWALLET.sol";

/**
 * @title FuzzWALLETIntegrity
 * @notice Checks handler integrity for the CompanyWallet ownership-epoch (I-3) fuzz harness.
 *
 * Each public `fuzz_*` function encodes the matching `handler_*` selector, delegates into
 * address(this) via `_testSelf`, and allows only `ClampFail` on the failure path. Direct
 * `handler_*` calls by the fuzzer engine are blocked via the engine config blacklist.
 */
contract FuzzWALLETIntegrity is HandlerWALLET, FuzzIntegrityBase {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         INTEGRITY                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Checks the integrity of `handler_changeOwner` (the epoch-bumping operation).
     * @param walletSeed Seed selecting which policy wallet to mutate
     * @param newOwnerSeed Seed selecting the incoming owner from the candidate pool
     */
    function fuzz_changeOwner(uint256 walletSeed, uint256 newOwnerSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerWALLET.handler_changeOwner.selector, walletSeed, newOwnerSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "WALLET-CHANGE-OWNER");
        }
    }

    /**
     * @notice Checks the integrity of `handler_execute` (a non-bumping control operation).
     * @param walletSeed Seed selecting which policy wallet executes the call
     */
    function fuzz_execute(uint256 walletSeed) public {
        bytes memory callData = abi.encodeWithSelector(HandlerWALLET.handler_execute.selector, walletSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "WALLET-EXECUTE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_executeInvalidTarget` (G-8 target guard).
     * @param walletSeed Seed selecting which policy wallet executes the call
     * @param kind Selects which target-guard leg is violated (0 = zero, 1 = self, 2 = EOA)
     */
    function fuzz_executeInvalidTarget(uint256 walletSeed, uint8 kind) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerWALLET.handler_executeInvalidTarget.selector, walletSeed, kind);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "WALLET-EXECUTE-INVALID-TARGET");
        }
    }

    /**
     * @notice Checks the integrity of `handler_executeAsNonOwner` (G-9 / X-3 policy authorization).
     * @param walletSeed Seed selecting which policy wallet executes the call
     * @param callerSeed Seed selecting a non-owner caller
     * @param targetSeed Seed selecting the operation calldata payload
     * @param grantRole Whether to first authorize the caller for the chosen operation
     */
    function fuzz_executeAsNonOwner(uint256 walletSeed, uint256 callerSeed, uint256 targetSeed, bool grantRole) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerWALLET.handler_executeAsNonOwner.selector, walletSeed, callerSeed, targetSeed, grantRole
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "WALLET-EXECUTE-AS-NON-OWNER");
        }
    }
}
