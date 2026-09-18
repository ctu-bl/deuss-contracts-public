// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Initializable} from "solady/src/utils/Initializable.sol";
import {OwnableRolesExtension} from "../utils/OwnableRolesExtension.sol";
import {Errors} from "../libs/Errors.sol";
import {AssetType} from "./MarketStructs.sol";
import {AssetManagerStorage} from "./AssetManagerStorage.sol";
import {IAssetManager} from "./interfaces/IAssetManager.sol";
import {IAssetValidator} from "./interfaces/IAssetValidator.sol";

/**
 * @title AssetManager
 * @author DEUSS Team
 * @notice Lightweight asset whitelist and transfer-shape validator for marketplace modules
 * @dev Upgradeable module: `constructor` disables initializers; `initialize` sets owner. `ADMIN` configures
 *      token allowlists; `validateAsset` is `view`-only and used by `EscrowManager` / trading modules for checks.
 */
contract AssetManager is IAssetManager, AssetManagerStorage, Initializable, OwnableRolesExtension {
    /// @notice Admin role for configuration updates
    uint256 public constant ADMIN = _ROLE_0;

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes contract owner
     * @param owner_ Owner address
     */
    function initialize(address owner_) external initializer {
        require(owner_ != address(0), Errors.ZeroAddress());
        _initializeOwner(owner_);
    }

    /**
     * @inheritdoc IAssetManager
     */
    function setAsset(address token, AssetType assetType, bool enabled, bool enforceTokenId) external onlyRoles(ADMIN) {
        require(token != address(0), Errors.ZeroAddress());
        require(!enabled || assetType != AssetType.NONE, Errors.AssetManager__InvalidAssetType());

        _assetManagerStorage().assetConfigs[token] =
            AssetConfig({assetType: assetType, enabled: enabled, enforceTokenId: enforceTokenId});

        emit AssetConfigured(token, assetType, enabled, enforceTokenId);
    }

    /**
     * @inheritdoc IAssetManager
     */
    function setAssetTokenId(address token, uint256 tokenId, bool enabled) external onlyRoles(ADMIN) {
        AssetManagerState storage $ = _assetManagerStorage();
        AssetConfig memory config = $.assetConfigs[token];
        require(config.enabled, Errors.AssetManager__AssetNotSupported(token, tokenId));
        require(config.enforceTokenId, Errors.AssetManager__TokenIdAllowlistDisabled(token));

        $.allowedTokenIds[token][tokenId] = enabled;

        emit AssetTokenIdConfigured(token, tokenId, enabled);
    }

    /**
     * @inheritdoc IAssetManager
     */
    function setAssetValidator(address token, address validator) external onlyRoles(ADMIN) {
        AssetManagerState storage $ = _assetManagerStorage();
        require($.assetConfigs[token].enabled, Errors.AssetManager__AssetNotSupported(token, 0));

        $.assetValidators[token] = validator;

        emit AssetValidatorConfigured(token, validator);
    }

    /**
     * @inheritdoc IAssetManager
     */
    function validateAsset(address token, uint256 tokenId, uint256 amount) external view returns (AssetType assetType) {
        AssetManagerState storage $ = _assetManagerStorage();
        AssetConfig memory config = $.assetConfigs[token];
        require(config.enabled, Errors.AssetManager__AssetNotSupported(token, tokenId));

        if (config.enforceTokenId) {
            require($.allowedTokenIds[token][tokenId], Errors.AssetManager__TokenIdNotSupported(token, tokenId));
        }

        assetType = config.assetType;
        require(assetType != AssetType.ERC20 || tokenId == 0, Errors.AssetManager__InvalidTokenId(tokenId));

        if (assetType == AssetType.ERC721) {
            require(amount == 1, Errors.AssetManager__InvalidAmountForERC721(amount));
        }

        address validator = $.assetValidators[token];
        if (validator != address(0)) {
            IAssetValidator(validator).validate(token, tokenId, amount);
        }
    }

    /**
     * @inheritdoc IAssetManager
     */
    function isAssetSupported(address token, uint256 tokenId) external view returns (bool supported) {
        AssetManagerState storage $ = _assetManagerStorage();
        AssetConfig memory config = $.assetConfigs[token];
        if (!config.enabled) return false;
        if (!config.enforceTokenId) return true;

        return $.allowedTokenIds[token][tokenId];
    }

    /**
     * @inheritdoc IAssetManager
     */
    function getAssetType(address token) external view returns (AssetType assetType) {
        AssetConfig memory config = _assetManagerStorage().assetConfigs[token];
        require(config.enabled, Errors.AssetManager__AssetNotSupported(token, 0));
        return config.assetType;
    }

    /**
     * @inheritdoc IAssetManager
     */
    function getAssetConfig(address token)
        external
        view
        returns (AssetType assetType, bool enabled, bool enforceTokenId)
    {
        AssetConfig memory config = _assetManagerStorage().assetConfigs[token];
        return (config.assetType, config.enabled, config.enforceTokenId);
    }

    /**
     * @inheritdoc IAssetManager
     */
    function isTokenIdAllowed(address token, uint256 tokenId) external view returns (bool allowed) {
        return _assetManagerStorage().allowedTokenIds[token][tokenId];
    }

    /**
     * @inheritdoc IAssetManager
     */
    function getAssetValidator(address token) external view returns (address validator) {
        return _assetManagerStorage().assetValidators[token];
    }
}
