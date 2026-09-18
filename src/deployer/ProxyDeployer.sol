// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {AddressExtensions} from "src/libs/AddressExtensions.sol";
import {Errors} from "src/libs/Errors.sol";
import {IProxyDeployer} from "src/deployer/IProxyDeployer.sol";
import {OwnableRolesExtension} from "src/utils/OwnableRolesExtension.sol";

// EBSI interfaces
import {ProxyFactory} from "ebsi/contract-factory/ProxyFactory.sol";
import {IProxyFactory} from "ebsi/contract-factory/interfaces/IProxyFactory.sol";
import {IProxyTemplateRegistry} from "ebsi/contract-factory/interfaces/IProxyTemplateRegistry.sol";

/**
 * @title ProxyDeployer
 * @author DEUSS Team
 * @notice Abstract helper providing shared template configuration and proxy deployment
 * @dev Supports multiple template configurations with event-based discovery (no unbounded loops)
 */
abstract contract ProxyDeployer is IProxyDeployer, OwnableRolesExtension {
    using AddressExtensions for address;

    /**
     * @notice Shared proxy deployment configuration
     * @custom:storage-location erc7201:deuss.deployer.proxydeployer.storage
     */
    struct ProxyDeployerStorage {
        /// @notice Shared proxy factory for all deployments
        address templateFactory;
        /// @notice Shared template registry for all deployments
        address templateRegistry;
        /// @notice Shared issuer DID used for proxy deployments authorization/tracking
        string did;
        /// @notice Mapping of templateId => template configuration
        mapping(bytes32 templateId => TemplateConfig config) templateConfigs;
    }

    /**
     * @notice ERC-7201 storage location for shared proxy deployment configuration
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("deuss.deployer.proxydeployer.storage"))) - 1))
     *      & ~bytes32(uint256(0xff))
     */
    // slither-disable-next-line unused-state
    bytes32 internal constant _PROXY_DEPLOYER_STORAGE_LOCATION =
        0x1be1affc245663ccf83f54f59d85d277ef7c71c2f359e52ff58373abee3d2900;

    /**
     * @notice Returns shared proxy deployment configuration storage.
     * @return $ Namespaced proxy deployer storage pointer
     */
    // slither-disable-next-line uninitialized-storage,assembly
    function _proxyDeployerStorage() internal pure returns (ProxyDeployerStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _PROXY_DEPLOYER_STORAGE_LOCATION
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IProxyDeployer
     */
    function setDid(string calldata did) external onlyOwner {
        require(!(bytes(did).length == 0), Errors.EmptyString());
        _proxyDeployerStorage().did = did;
        emit DidSet(did);
    }

    /**
     * @inheritdoc IProxyDeployer
     */
    function setFactory(address factory) external onlyOwner {
        factory.assertAddressNotZero();

        ProxyDeployerStorage storage $ = _proxyDeployerStorage();

        $.templateFactory = factory;
        emit FactorySet(factory);

        // If registry is already set, verify factory is wired to it
        if ($.templateRegistry != address(0)) {
            _validateWiredRegistry(factory, $.templateRegistry);
        }
    }

    /**
     * @inheritdoc IProxyDeployer
     */
    function setRegistry(address registry) external onlyOwner {
        registry.assertAddressNotZero();

        ProxyDeployerStorage storage $ = _proxyDeployerStorage();

        $.templateRegistry = registry;
        emit RegistrySet(registry);

        // If factory is already set, verify it is wired to the provided registry
        if ($.templateFactory != address(0)) {
            _validateWiredRegistry($.templateFactory, registry);
        }
    }

    /**
     * @inheritdoc IProxyDeployer
     */
    function deactivateTemplateConfig(bytes32 templateId) external onlyOwner {
        TemplateConfig storage config = _proxyDeployerStorage().templateConfigs[templateId];
        require(config.isActive, Errors.ProxyDeployer__TemplateNotFound(templateId));

        config.isActive = false;

        emit TemplateConfigDeactivated(templateId, config.name, config.version);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IProxyDeployer
     */
    function getDeploymentInfo(address proxy) external view returns (IProxyFactory.DeploymentInfo memory) {
        address templateFactory = _proxyDeployerStorage().templateFactory;
        require(!(templateFactory == address(0)), Errors.ZeroAddress());
        return IProxyFactory(templateFactory).getDeploymentInfo(proxy);
    }

    /**
     * @inheritdoc IProxyDeployer
     */
    function getDid() external view returns (string memory) {
        return _proxyDeployerStorage().did;
    }

    /**
     * @inheritdoc IProxyDeployer
     */
    function getFactory() external view returns (address) {
        return _proxyDeployerStorage().templateFactory;
    }

    /**
     * @inheritdoc IProxyDeployer
     */
    function getRegistry() external view returns (address) {
        return _proxyDeployerStorage().templateRegistry;
    }

    /**
     * @inheritdoc IProxyDeployer
     */
    function getTemplateConfig(bytes32 templateId) external view returns (TemplateConfig memory) {
        TemplateConfig memory config = _proxyDeployerStorage().templateConfigs[templateId];
        require(config.isActive, Errors.ProxyDeployer__TemplateNotFound(templateId));
        return config;
    }

    /**
     * @inheritdoc IProxyDeployer
     */
    function isTemplateActive(bytes32 templateId) external view returns (bool) {
        return _proxyDeployerStorage().templateConfigs[templateId].isActive;
    }

    /**
     * @inheritdoc IProxyDeployer
     */
    function computeProxyAddress(bytes32 templateId, bytes calldata initData, bytes32 salt)
        external
        view
        returns (address)
    {
        ProxyDeployerStorage storage $ = _proxyDeployerStorage();
        TemplateConfig memory config = $.templateConfigs[templateId];
        require(config.isActive, Errors.ProxyDeployer__TemplateNotFound(templateId));

        return IProxyFactory($.templateFactory).computeAddress(config.name, config.version, initData, salt);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IProxyDeployer
     */
    function computeTemplateId(string calldata name, string calldata version)
        external
        pure
        returns (bytes32 templateId)
    {
        return keccak256(abi.encode(name, version));
    }

    /**
     * @inheritdoc IProxyDeployer
     */
    function addTemplateConfig(string calldata name, string calldata version)
        public
        onlyOwner
        returns (bytes32 templateId)
    {
        // Validate inputs
        require(!(bytes(name).length == 0 || bytes(version).length == 0), Errors.EmptyString());

        ProxyDeployerStorage storage $ = _proxyDeployerStorage();

        // Compute template ID (will revert if registry not set)
        templateId = IProxyTemplateRegistry($.templateRegistry).computeTemplateId(name, version);

        // Check if already exists and active
        require(!($.templateConfigs[templateId].isActive), Errors.ProxyDeployer__TemplateAlreadyExists(name, version));

        // Verify template exists and is active in the registry
        IProxyTemplateRegistry.ProxyTemplate memory template_ =
            IProxyTemplateRegistry($.templateRegistry).getTemplate(templateId);
        require(template_.isActive, Errors.ProxyDeployer__TemplateNotActive(name, version));

        // Store template config
        $.templateConfigs[templateId] = TemplateConfig({name: name, version: version, isActive: true});

        emit TemplateConfigAdded(templateId, name, version);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploys a new proxy via the configured factory using a specific template
     * @param templateId The template ID to use for deployment
     * @param initData ABI-encoded initialization selector and arguments
     * @return proxy The address of the deployed proxy
     */
    function _deployProxy(bytes32 templateId, bytes memory initData) internal returns (address proxy) {
        ProxyDeployerStorage storage $ = _proxyDeployerStorage();
        TemplateConfig memory config = $.templateConfigs[templateId];
        require(config.isActive, Errors.ProxyDeployer__TemplateNotFound(templateId));

        string memory did = $.did; // @dev it can be empty string if `msg.sender` has `TRUSTED_ISSUER_ROLE` in EBSI ProxyFactory
        // slither-disable-next-line reentrancy-events
        proxy = IProxyFactory($.templateFactory).deployProxy(config.name, config.version, initData, did);

        emit ProxyDeployedViaTemplate(proxy, templateId, config.name, config.version, did);
    }

    /**
     * @notice Deploys a new proxy via the configured factory using a specific template and salt
     * @param templateId The template ID to use for deployment
     * @param initData ABI-encoded initialization selector and arguments
     * @param salt Salt for deterministic CREATE2 deployment
     * @return proxy The address of the deployed proxy
     */
    function _deployProxyWithSalt(bytes32 templateId, bytes memory initData, bytes32 salt)
        internal
        returns (address proxy)
    {
        ProxyDeployerStorage storage $ = _proxyDeployerStorage();
        TemplateConfig memory config = $.templateConfigs[templateId];
        require(config.isActive, Errors.ProxyDeployer__TemplateNotFound(templateId));

        string memory did = $.did;
        // slither-disable-next-line reentrancy-events
        proxy = IProxyFactory($.templateFactory).deployProxyWithSalt(config.name, config.version, initData, did, salt);

        emit ProxyDeployedViaTemplate(proxy, templateId, config.name, config.version, did);
    }

    /**
     * @notice Validates if the registry is wired to the provided factory
     * @param factory Address of the factory
     * @param registry Address of the registry
     */
    function _validateWiredRegistry(address factory, address registry) internal view {
        address wiredRegistry = address(ProxyFactory(factory).templateRegistry());
        require(wiredRegistry == registry, Errors.ProxyDeployer__InvalidRegistry(registry, wiredRegistry));
    }
}
