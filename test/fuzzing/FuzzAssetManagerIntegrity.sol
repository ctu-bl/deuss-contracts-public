// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {FuzzIntegrityBase} from "./FuzzIntegrityBase.sol";
import {HandlerAssetManager} from "./helper/handlers/HandlerAssetManager.sol";

/**
 * @title FuzzAssetManagerIntegrity
 * @notice Checks handler integrity for the AssetManager fuzz harness
 */
contract FuzzAssetManagerIntegrity is HandlerAssetManager, FuzzIntegrityBase {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         INTEGRITY                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Checks the integrity of `handler_setAsset`
     */
    function fuzz_setAsset(uint256 tokenSeed, uint256 assetTypeSeed, bool enabled, bool enforceTokenId) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerAssetManager.handler_setAsset.selector, tokenSeed, assetTypeSeed, enabled, enforceTokenId
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-SET-ASSET");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setAssetUnauthorized`
     */
    function fuzz_setAssetUnauthorized(uint256 tokenSeed, uint256 assetTypeSeed, bool enabled, bool enforceTokenId)
        public
    {
        bytes memory callData = abi.encodeWithSelector(
            HandlerAssetManager.handler_setAssetUnauthorized.selector, tokenSeed, assetTypeSeed, enabled, enforceTokenId
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-SET-ASSET-UNAUTH");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setAssetTokenId`
     */
    function fuzz_setAssetTokenId(uint256 tokenSeed, uint256 tokenIdSeed, bool enabled) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerAssetManager.handler_setAssetTokenId.selector, tokenSeed, tokenIdSeed, enabled
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-SET-ASSET-TOKEN-ID");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setAssetTokenIdUnauthorized`
     */
    function fuzz_setAssetTokenIdUnauthorized(uint256 tokenSeed, uint256 tokenIdSeed, bool enabled) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerAssetManager.handler_setAssetTokenIdUnauthorized.selector, tokenSeed, tokenIdSeed, enabled
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-SET-ASSET-TOKEN-ID-UNAUTH");
        }
    }

    /**
     * @notice Checks the integrity of `handler_validateAsset`
     */
    function fuzz_validateAsset(uint256 tokenSeed, uint256 tokenIdSeed, uint256 amount) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerAssetManager.handler_validateAsset.selector, tokenSeed, tokenIdSeed, amount);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-VALIDATE-ASSET");
        }
    }

    /**
     * @notice Checks the integrity of `handler_validateAssetAsActor`
     */
    function fuzz_validateAssetAsActor(uint256 tokenSeed, uint256 tokenIdSeed, uint256 amount) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerAssetManager.handler_validateAssetAsActor.selector, tokenSeed, tokenIdSeed, amount
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-VALIDATE-ASSET-ACTOR");
        }
    }
}
