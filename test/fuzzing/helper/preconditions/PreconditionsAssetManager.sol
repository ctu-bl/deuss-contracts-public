// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, gas-struct-packing */

import {AssetType} from "src/marketplace/MarketStructs.sol";
import {PreconditionsBase} from "./PreconditionsBase.sol";

abstract contract PreconditionsAssetManager is PreconditionsBase {
    struct SetAssetParams {
        address token;
        AssetType assetType;
        bool enabled;
        bool enforceTokenId;
    }

    struct SetAssetTokenIdParams {
        address token;
        uint256 tokenId;
        bool enabled;
    }

    struct ValidateAssetParams {
        address token;
        uint256 tokenId;
        uint256 amount;
    }

    /// @dev Picks a token from the synthetic asset pool or address(0) using the provided seed.
    function _pickAssetToken(uint256 seed) internal view returns (address token) {
        uint256 len = knownAssetTokens.length;
        require(len != 0, ClampFail("asset pool empty"));
        uint256 pick = seed % (len + 1);
        token = pick == 0 ? address(0) : knownAssetTokens[pick - 1];
    }

    function _pickAssetTokenId(uint256 seed) internal view returns (uint256 tokenId) {
        uint256 len = knownAssetTokenIds.length;
        require(len != 0, ClampFail("asset tokenId pool empty"));
        tokenId = knownAssetTokenIds[seed % len];
    }

    function setAssetPreconditions(uint256 tokenSeed, uint256 assetTypeSeed, bool enabled, bool enforceTokenId)
        internal
        view
        returns (SetAssetParams memory params)
    {
        params.token = _pickAssetToken(tokenSeed);
        // Full AssetType range (including NONE) so the InvalidAssetType branch is reachable.
        params.assetType = AssetType(uint8(assetTypeSeed % ASSET_TYPE_COUNT));
        params.enabled = enabled;
        params.enforceTokenId = enforceTokenId;
    }

    function setAssetTokenIdPreconditions(uint256 tokenSeed, uint256 tokenIdSeed, bool enabled)
        internal
        view
        returns (SetAssetTokenIdParams memory params)
    {
        params.token = _pickAssetToken(tokenSeed);
        params.tokenId = _pickAssetTokenId(tokenIdSeed);
        params.enabled = enabled;
    }

    function validateAssetPreconditions(uint256 tokenSeed, uint256 tokenIdSeed, uint256 amount)
        internal
        view
        returns (ValidateAssetParams memory params)
    {
        params.token = _pickAssetToken(tokenSeed);
        params.tokenId = _pickAssetTokenId(tokenIdSeed);
        // Bias amount towards {0, 1, ..., 7} so the ERC721 `amount == 1` success branch is
        // exercised meaningfully. Raw seeds made that branch virtually unreachable.
        params.amount = amount % 8;
    }
}
