// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {AssetType} from "../MarketStructs.sol";

/**
 * @title IAssetManager
 * @author DEUSS Team
 * @notice Interface for managing supported assets and validating transfer constraints
 */
interface IAssetManager {
    /**
     * @notice Emitted when a token-level asset configuration is updated
     * @param token Token contract address
     * @param assetType Asset standard
     * @param enabled Whether the token is enabled
     * @param enforceTokenId Whether tokenId-level allowlisting is enforced
     */
    event AssetConfigured(
        address indexed token, AssetType indexed assetType, bool indexed enabled, bool enforceTokenId
    );

    /**
     * @notice Emitted when tokenId allowlist status is updated
     * @param token Token contract address
     * @param tokenId Token identifier
     * @param enabled Whether the tokenId is enabled
     */
    event AssetTokenIdConfigured(address indexed token, uint256 indexed tokenId, bool indexed enabled);

    /**
     * @notice Emitted when a token's optional validator hook is updated
     * @param token Token contract address
     * @param validator Validator contract address (address(0) clears the hook)
     */
    event AssetValidatorConfigured(address indexed token, address indexed validator);

    /**
     * @notice Configures token-level support for an asset contract
     * @param token Token contract address
     * @param assetType Asset standard
     * @param enabled Whether the token is enabled
     * @param enforceTokenId Whether tokenId-level allowlisting is enforced
     */
    function setAsset(address token, AssetType assetType, bool enabled, bool enforceTokenId) external;

    /**
     * @notice Configures tokenId-level support for a token contract
     * @param token Token contract address
     * @param tokenId Token identifier
     * @param enabled Whether this tokenId is enabled
     */
    function setAssetTokenId(address token, uint256 tokenId, bool enabled) external;

    /**
     * @notice Configures an optional validator hook for a token
     * @dev When set, `validateAsset` invokes `IAssetValidator.validate` after the static allowlist check.
     *      Pass `address(0)` to clear the hook. The token must be enabled.
     * @param token Token contract address
     * @param validator Validator contract address (or `address(0)` to clear)
     */
    function setAssetValidator(address token, address validator) external;

    /**
     * @notice Validates an asset transfer shape and returns the resolved asset type
     * @param token Token contract address
     * @param tokenId Token identifier
     * @param amount Transfer amount
     * @return assetType Resolved asset standard
     */
    function validateAsset(address token, uint256 tokenId, uint256 amount) external view returns (AssetType assetType);

    /**
     * @notice Returns whether a token/tokenId pair is currently supported
     * @param token Token contract address
     * @param tokenId Token identifier
     * @return supported True if supported
     */
    function isAssetSupported(address token, uint256 tokenId) external view returns (bool supported);

    /**
     * @notice Returns the configured asset standard for a token
     * @param token Token contract address
     * @return assetType Asset standard
     */
    function getAssetType(address token) external view returns (AssetType assetType);

    /**
     * @notice Returns token-level asset configuration
     * @param token Token contract address
     * @return assetType Asset standard
     * @return enabled Token-level status
     * @return enforceTokenId TokenId allowlist mode
     */
    function getAssetConfig(address token)
        external
        view
        returns (AssetType assetType, bool enabled, bool enforceTokenId);

    /**
     * @notice Returns whether a tokenId is explicitly enabled for a token
     * @param token Token contract address
     * @param tokenId Token identifier
     * @return allowed True if tokenId is enabled
     */
    function isTokenIdAllowed(address token, uint256 tokenId) external view returns (bool allowed);

    /**
     * @notice Returns the configured validator hook for a token (or `address(0)` if none)
     * @param token Token contract address
     * @return validator Validator contract address, or `address(0)` when no hook is configured
     */
    function getAssetValidator(address token) external view returns (address validator);
}
