// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {FuzzIntegrityBase} from "./FuzzIntegrityBase.sol";
import {HandlerEscrowAuth} from "./helper/handlers/HandlerEscrowAuth.sol";

/**
 * @title FuzzEscrowAuthIntegrity
 * @notice Checks handler integrity for the EscrowManager authorization fuzz harness
 */
contract FuzzEscrowAuthIntegrity is HandlerEscrowAuth, FuzzIntegrityBase {
    function fuzz_registerModule(uint256 moduleTypeSeed, uint256 moduleAddrSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEscrowAuth.handler_registerModule.selector, moduleTypeSeed, moduleAddrSeed);
        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) _allowClampFail(errorSelector, "SELF-REGISTER-MODULE");
    }

    function fuzz_registerModuleUnauthorized(uint256 moduleTypeSeed, uint256 moduleAddrSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEscrowAuth.handler_registerModuleUnauthorized.selector, moduleTypeSeed, moduleAddrSeed
        );
        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) _allowClampFail(errorSelector, "SELF-REGISTER-MODULE-UNAUTH");
    }

    function fuzz_deactivateModule(uint256 moduleTypeSeed, uint256 moduleAddrSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEscrowAuth.handler_deactivateModule.selector, moduleTypeSeed, moduleAddrSeed);
        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) _allowClampFail(errorSelector, "SELF-DEACTIVATE-MODULE");
    }

    function fuzz_deactivateModuleUnauthorized(uint256 moduleTypeSeed, uint256 moduleAddrSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEscrowAuth.handler_deactivateModuleUnauthorized.selector, moduleTypeSeed, moduleAddrSeed
        );
        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) _allowClampFail(errorSelector, "SELF-DEACTIVATE-MODULE-UNAUTH");
    }

    function fuzz_setAssetManager(uint256 candidateSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEscrowAuth.handler_setAssetManager.selector, candidateSeed);
        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) _allowClampFail(errorSelector, "SELF-SET-ASSET-MANAGER");
    }

    function fuzz_setAssetManagerUnauthorized(uint256 candidateSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEscrowAuth.handler_setAssetManagerUnauthorized.selector, candidateSeed);
        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) _allowClampFail(errorSelector, "SELF-SET-ASSET-MANAGER-UNAUTH");
    }

    function fuzz_createEscrowAsActor(uint256 amountSeed, uint256 depositorSeed, uint256 tokenIdSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEscrowAuth.handler_createEscrowAsActor.selector, amountSeed, depositorSeed, tokenIdSeed
        );
        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) _allowClampFail(errorSelector, "SELF-CREATE-ESCROW-ACTOR");
    }

    function fuzz_withdrawAsActor(uint256 escrowIdSeed, uint256 amountSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEscrowAuth.handler_withdrawAsActor.selector, escrowIdSeed, amountSeed);
        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) _allowClampFail(errorSelector, "SELF-WITHDRAW-ACTOR");
    }

    function fuzz_claimAsActor(uint256 escrowIdSeed, uint256 amountSeed, uint256 beneficiarySeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEscrowAuth.handler_claimAsActor.selector, escrowIdSeed, amountSeed, beneficiarySeed
        );
        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) _allowClampFail(errorSelector, "SELF-CLAIM-ACTOR");
    }

    function fuzz_sweep(uint256 assetTypeSeed, uint256 tokenIdSeed, uint256 amountSeed, uint256 beneficiarySeed)
        public
    {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEscrowAuth.handler_sweep.selector, assetTypeSeed, tokenIdSeed, amountSeed, beneficiarySeed
        );
        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) _allowClampFail(errorSelector, "SELF-SWEEP");
    }

    function fuzz_sweepUnauthorized(
        uint256 assetTypeSeed,
        uint256 tokenIdSeed,
        uint256 amountSeed,
        uint256 beneficiarySeed
    ) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEscrowAuth.handler_sweepUnauthorized.selector,
            assetTypeSeed,
            tokenIdSeed,
            amountSeed,
            beneficiarySeed
        );
        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) _allowClampFail(errorSelector, "SELF-SWEEP-UNAUTH");
    }
}
