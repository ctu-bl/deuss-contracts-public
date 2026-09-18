// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {AssetType} from "src/marketplace/MarketStructs.sol";
import {SnapshotTypes} from "./SnapshotTypes.sol";

/// @notice Before/after snapshot helpers for AssetManager fuzz actions.
abstract contract BeforeAfterAssetManager is SnapshotTypes {
    /*//////////////////////////////////////////////////////////////
                          ASSET SNAPSHOTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Snapshots the full AssetManager fuzz pool (all known tokens x tokenIds). Running
    /// a full sweep (instead of per-token) lets postconditions assert cross-token isolation
    /// without extra storage gymnastics. The pool is bounded (4 x 4) so this is cheap.
    function _beforeAsset() internal {
        for (uint256 i; i < knownAssetTokens.length; ++i) {
            _setAssetState(BEFORE, knownAssetTokens[i]);
        }
    }

    function _afterAsset() internal {
        for (uint256 i; i < knownAssetTokens.length; ++i) {
            _setAssetState(AFTER, knownAssetTokens[i]);
        }
    }

    function _setAssetState(uint8 callNum, address token) internal {
        if (token == address(0)) return;

        (AssetType assetType, bool enabled, bool enforceTokenId) = assetManager.getAssetConfig(token);
        states[callNum].assetConfigStates[token] =
            AssetManagerConfigState({assetType: assetType, enabled: enabled, enforceTokenId: enforceTokenId});

        for (uint256 i; i < knownAssetTokenIds.length; ++i) {
            uint256 tokenId = knownAssetTokenIds[i];
            states[callNum].assetAllowedStates[token][tokenId] = assetManager.isTokenIdAllowed(token, tokenId);
        }
    }
}
