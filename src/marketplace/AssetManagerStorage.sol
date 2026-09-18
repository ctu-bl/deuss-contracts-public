// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {AssetType} from "./MarketStructs.sol";

/**
 * @title AssetManagerStorage
 * @author DEUSS Team
 * @notice Storage layout for AssetManager.
 */
abstract contract AssetManagerStorage {
    /**
     * @notice Token-level marketplace asset configuration.
     * @dev `enforceTokenId` enables the tokenId allowlist for multi-token assets.
     */
    struct AssetConfig {
        /// @notice Marketplace asset classification returned by validation.
        AssetType assetType;
        /// @notice Whether the token is accepted by the marketplace.
        bool enabled;
        /// @notice Whether validation must also check the per-tokenId allowlist.
        bool enforceTokenId;
    }

    /**
     * @notice Asset whitelist and tokenId allowlist storage.
     * @custom:storage-location erc7201:deuss.assetManager.storage
     */
    struct AssetManagerState {
        /// @notice Token-level asset configuration
        mapping(address token => AssetConfig config) assetConfigs;
        /// @notice Optional tokenId-level allowlist when `enforceTokenId` is enabled
        mapping(address token => mapping(uint256 tokenId => bool enabled)) allowedTokenIds;
        /// @notice Optional per-token validator hook invoked by `validateAsset`
        mapping(address token => address validator) assetValidators;
    }

    /**
     * @notice ERC-7201 storage location for AssetManager state.
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("deuss.assetManager.storage"))) - 1))
     *      & ~bytes32(uint256(0xff))
     */
    // slither-disable-next-line unused-state
    bytes32 internal constant _ASSET_MANAGER_STORAGE_LOCATION =
        0x3c0e9b751c0d9d98159324a4b7460f9e12d438fd842007cc0592435d7c8dac00;

    /**
     * @notice Returns AssetManager namespaced storage.
     * @return $ Namespaced storage pointer.
     */
    // slither-disable-next-line uninitialized-storage,assembly
    function _assetManagerStorage() internal pure returns (AssetManagerState storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _ASSET_MANAGER_STORAGE_LOCATION
        }
    }
}
