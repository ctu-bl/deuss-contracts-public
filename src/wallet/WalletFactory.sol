// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {Initializable} from "solady/src/utils/Initializable.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import {AddressExtensions} from "src/libs/AddressExtensions.sol";
import {Errors} from "src/libs/Errors.sol";
import {ProxyDeployer} from "src/deployer/ProxyDeployer.sol";
import {IEntityRegistry} from "src/registry/interfaces/IEntityRegistry.sol";
import {EntityStatus} from "src/registry/EntityStructs.sol";
import {IWalletFactory} from "src/wallet/IWalletFactory.sol";
import {WalletFactoryStorage} from "src/wallet/WalletFactoryStorage.sol";

/**
 * @title WalletFactory
 * @author DEUSS Team
 * @notice Standalone factory for deploying entity wallets via EBSI proxy templates.
 * @dev Proxy-initializable: implementation locks initializers in the constructor; `initialize` wires
 *      `EntityRegistry` and owner. `createWallet` is `nonReentrant` because deployment may invoke user-supplied init code.
 */
contract WalletFactory is IWalletFactory, WalletFactoryStorage, ProxyDeployer, ReentrancyGuard, Initializable {
    using AddressExtensions for address;
    using ERC165Checker for address;

    /**
     * @notice Locks the implementation contract.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes a new wallet factory proxy instance.
     * @param entityRegistry_ EntityRegistry address (must implement `IEntityRegistry`).
     * @param owner_ Owner allowed to configure templates and factory settings.
     */
    function initialize(address entityRegistry_, address owner_) external initializer {
        owner_.assertAddressNotZero();

        _initializeOwner(owner_);
        _setEntityRegistry(entityRegistry_);
    }

    /**
     * @inheritdoc IWalletFactory
     */
    function createWallet(CreateWalletParams calldata params) external nonReentrant returns (address wallet) {
        address entityRegistry_ = _walletFactoryStorage().entityRegistry;
        bool isManager = IEntityRegistry(entityRegistry_).isEntityManager(params.entityId, msg.sender);
        require(isManager, Errors.WalletFactory__NotEntityManager(msg.sender, params.entityId));

        EntityStatus entityStatus = IEntityRegistry(entityRegistry_).getEntityStatus(params.entityId);
        require(entityStatus == EntityStatus.ENABLED, Errors.WalletFactory__EntityNotEnabled(params.entityId));

        bytes32 templateId = _resolveWalletTemplateId(params.walletType);
        require(params.initData.length != 0, Errors.WalletFactory__InitDataEmpty());

        wallet = _deployProxy(templateId, params.initData);
        require(wallet != address(0), Errors.ER__CompanyWalletAddressZero());

        emit WalletCreated(params.entityId, wallet, params.walletType, msg.sender);
    }

    /**
     * @inheritdoc IWalletFactory
     */
    function setWalletTemplateForType(bytes32 walletType, string calldata name, string calldata version)
        external
        onlyOwner
    {
        require(walletType != bytes32(0), Errors.ER__CompanyWalletTypeIdZero());

        bytes32 templateId = keccak256(abi.encode(name, version));
        ProxyDeployerStorage storage $ = _proxyDeployerStorage();

        if (!$.templateConfigs[templateId].isActive) {
            templateId = addTemplateConfig(name, version);
        }
        _walletFactoryStorage().walletTemplateIdByType[walletType] = templateId;

        emit WalletTemplateForTypeSet(walletType, templateId, name, version);
    }

    /**
     * @inheritdoc IWalletFactory
     */
    function getWalletTemplateIdForType(bytes32 walletType) external view returns (bytes32) {
        return _walletFactoryStorage().walletTemplateIdByType[walletType];
    }

    /**
     * @inheritdoc IWalletFactory
     */
    function entityRegistry() external view returns (address) {
        return _walletFactoryStorage().entityRegistry;
    }

    /**
     * @notice Sets the EntityRegistry reference
     * @param entityRegistry_ EntityRegistry address (must implement `IEntityRegistry`)
     * @dev Reverts if `entityRegistry_` is zero or does not implement `IEntityRegistry`
     * @dev Emits EntityRegistrySet on success
     */
    function _setEntityRegistry(address entityRegistry_) internal {
        entityRegistry_.assertAddressNotZero();
        require(
            entityRegistry_.supportsInterface(type(IEntityRegistry).interfaceId),
            Errors.WalletFactory__InvalidEntityRegistry(entityRegistry_)
        );

        _walletFactoryStorage().entityRegistry = entityRegistry_;

        emit EntityRegistrySet(entityRegistry_);
    }

    /**
     * @notice Resolves template id for a typed wallet.
     * @param walletType Wallet type identifier.
     * @return templateId Resolved template identifier.
     */
    function _resolveWalletTemplateId(bytes32 walletType) internal view returns (bytes32 templateId) {
        require(walletType != bytes32(0), Errors.ER__CompanyWalletTypeIdZero());
        templateId = _walletFactoryStorage().walletTemplateIdByType[walletType];
        require(templateId != bytes32(0), Errors.ER__CompanyWalletTypeNotConfigured(walletType));
    }
}
