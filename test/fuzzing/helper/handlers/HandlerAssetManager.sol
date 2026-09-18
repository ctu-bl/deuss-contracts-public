// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {PreconditionsAssetManager} from "../preconditions/PreconditionsAssetManager.sol";
import {PostconditionsAssetManager} from "../postconditions/PostconditionsAssetManager.sol";

/// @title HandlerAssetManager
/// @notice Stateful fuzz handlers for the AssetManager vertical slice.
/// @dev The harness (`address(this)`) holds ADMIN on AssetManager, so admin-guarded calls go
/// through `address(this)`. Dedicated `_unauthorized` handlers exercise the same mutators as
/// fuzz actors to assert that the solady `onlyRoles` gate rejects non-admins.
abstract contract HandlerAssetManager is PreconditionsAssetManager, PostconditionsAssetManager {
    /*//////////////////////////////////////////////////////////////
                              setAsset
    //////////////////////////////////////////////////////////////*/

    /// @notice Configures token-level asset support as the admin harness.
    function handler_setAsset(uint256 tokenSeed, uint256 assetTypeSeed, bool enabled, bool enforceTokenId) public {
        SetAssetParams memory params = setAssetPreconditions(tokenSeed, assetTypeSeed, enabled, enforceTokenId);
        _beforeAsset();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(assetManager),
            abi.encodeWithSelector(
                assetManager.setAsset.selector, params.token, params.assetType, params.enabled, params.enforceTokenId
            ),
            address(this)
        );

        setAssetPostconditions(success, returnData, params);
    }

    /// @notice Attempts to configure token-level asset support as a non-admin caller.
    function handler_setAssetUnauthorized(uint256 tokenSeed, uint256 assetTypeSeed, bool enabled, bool enforceTokenId)
        public
        setCurrentActor
    {
        SetAssetParams memory params = setAssetPreconditions(tokenSeed, assetTypeSeed, enabled, enforceTokenId);
        _beforeAsset();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(assetManager),
            abi.encodeWithSelector(
                assetManager.setAsset.selector, params.token, params.assetType, params.enabled, params.enforceTokenId
            ),
            currentActor
        );

        setAssetUnauthorizedPostconditions(success, returnData);
    }

    /*//////////////////////////////////////////////////////////////
                           setAssetTokenId
    //////////////////////////////////////////////////////////////*/

    /// @notice Toggles tokenId-level allowlist entry as the admin harness.
    function handler_setAssetTokenId(uint256 tokenSeed, uint256 tokenIdSeed, bool enabled) public {
        SetAssetTokenIdParams memory params = setAssetTokenIdPreconditions(tokenSeed, tokenIdSeed, enabled);
        _beforeAsset();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(assetManager),
            abi.encodeWithSelector(assetManager.setAssetTokenId.selector, params.token, params.tokenId, params.enabled),
            address(this)
        );

        setAssetTokenIdPostconditions(success, returnData, params);
    }

    /// @notice Attempts to toggle a tokenId-level allowlist entry as a non-admin caller.
    function handler_setAssetTokenIdUnauthorized(uint256 tokenSeed, uint256 tokenIdSeed, bool enabled)
        public
        setCurrentActor
    {
        SetAssetTokenIdParams memory params = setAssetTokenIdPreconditions(tokenSeed, tokenIdSeed, enabled);
        _beforeAsset();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(assetManager),
            abi.encodeWithSelector(assetManager.setAssetTokenId.selector, params.token, params.tokenId, params.enabled),
            currentActor
        );

        setAssetTokenIdUnauthorizedPostconditions(success, returnData);
    }

    /*//////////////////////////////////////////////////////////////
                            validateAsset
    //////////////////////////////////////////////////////////////*/

    /// @notice Exercises validateAsset(token, tokenId, amount) against the recorded snapshot and
    /// asserts the success/revert outcome matches the state-derived expectation.
    function handler_validateAsset(uint256 tokenSeed, uint256 tokenIdSeed, uint256 amount) public {
        ValidateAssetParams memory params = validateAssetPreconditions(tokenSeed, tokenIdSeed, amount);
        _beforeAsset();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(assetManager),
            abi.encodeWithSelector(assetManager.validateAsset.selector, params.token, params.tokenId, params.amount),
            address(this)
        );

        validateAssetPostconditions(success, returnData, params);
    }

    /// @notice Calls validateAsset as a non-admin actor. Marketplace modules (EscrowManager,
    /// Marketplace, OrderbookMarketplace) all call validateAsset from their own addresses
    /// rather than the admin, so this handler asserts that no authorization gate exists on the
    /// view function — a regression there would silently break every marketplace flow.
    function handler_validateAssetAsActor(uint256 tokenSeed, uint256 tokenIdSeed, uint256 amount)
        public
        setCurrentActor
    {
        ValidateAssetParams memory params = validateAssetPreconditions(tokenSeed, tokenIdSeed, amount);
        _beforeAsset();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(assetManager),
            abi.encodeWithSelector(assetManager.validateAsset.selector, params.token, params.tokenId, params.amount),
            currentActor
        );

        validateAssetPostconditions(success, returnData, params);
    }
}
