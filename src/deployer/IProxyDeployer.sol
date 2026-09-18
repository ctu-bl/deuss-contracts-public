// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IProxyFactory} from "ebsi/contract-factory/interfaces/IProxyFactory.sol";

/**
 * @title IProxyDeployer
 * @author DEUSS Team
 * @notice Interface for ProxyDeployer providing shared EBSI template configuration and proxy deployment
 */
interface IProxyDeployer {
    /**
     * @notice Template configuration data for EBSI deployments
     * @param name Template name
     * @param version Template version
     * @param isActive Whether this template config is active
     */
    struct TemplateConfig {
        string name;
        string version;
        bool isActive;
    }

    /**
     * @notice Emitted when factory address is set
     * @param factory Address of the proxy factory
     */
    event FactorySet(address indexed factory);

    /**
     * @notice Emitted when registry address is set
     * @param registry Address of the template registry
     */
    event RegistrySet(address indexed registry);

    /**
     * @notice Emitted when a template config is added
     * @param templateId The computed template ID
     * @param name Template name
     * @param version Template version
     */
    event TemplateConfigAdded(bytes32 indexed templateId, string name, string version);

    /**
     * @notice Emitted when a template config is deactivated
     * @param templateId The template ID
     * @param name Template name
     * @param version Template version
     */
    event TemplateConfigDeactivated(bytes32 indexed templateId, string name, string version);

    /**
     * @notice Emitted when a proxy is deployed
     * @param proxy Address of the deployed proxy
     * @param templateId The template ID used for deployment
     * @param name Template name
     * @param version Template version
     * @param issuerDID Issuer DID used for deployment
     */
    event ProxyDeployedViaTemplate(
        address indexed proxy, bytes32 indexed templateId, string name, string version, string issuerDID
    );

    /**
     * @notice Emitted when issuer DID is set
     * @param did The issuer DID string
     */
    event DidSet(string did);

    /**
     * @notice Sets the proxy factory address
     * @param factory Address of the proxy factory
     * @dev If both factory and registry are set, validates they are wired together
     */
    function setFactory(address factory) external;

    /**
     * @notice Sets the template registry address
     * @param registry Address of the template registry
     * @dev If factory is already set, validates it is wired to this registry
     */
    function setRegistry(address registry) external;

    /**
     * @notice Adds a new template configuration
     * @param name Template name
     * @param version Template version
     * @return templateId The computed template ID
     */
    function addTemplateConfig(string calldata name, string calldata version) external returns (bytes32 templateId);

    /**
     * @notice Deactivates a template configuration (soft delete)
     * @param templateId The template ID to deactivate
     */
    function deactivateTemplateConfig(bytes32 templateId) external;

    /**
     * @notice Sets the issuer DID used when deploying proxies
     * @param did The issuer DID string
     */
    function setDid(string calldata did) external;

    /**
     * @notice Returns the factory address
     * @return address of the proxy factory
     */
    function getFactory() external view returns (address);

    /**
     * @notice Returns the registry address
     * @return address of the template registry
     */
    function getRegistry() external view returns (address);

    /**
     * @notice Returns the configured issuer DID
     * @return string of the issuer DID
     */
    function getDid() external view returns (string memory);

    /**
     * @notice Returns a template configuration by ID
     * @param templateId The template ID
     * @return TemplateConfig structure for EBSI deployments
     */
    function getTemplateConfig(bytes32 templateId) external view returns (TemplateConfig memory);

    /**
     * @notice Checks if a template is active
     * @param templateId The template ID
     * @return bool indicating if the template is active
     */
    function isTemplateActive(bytes32 templateId) external view returns (bool);

    /**
     * @notice Queries the factory for deployment info
     * @param proxy The proxy address
     * @return DeploymentInfo structure containing deployment details
     */
    function getDeploymentInfo(address proxy) external view returns (IProxyFactory.DeploymentInfo memory);

    /**
     * @notice Computes the template ID for a given name and version
     * @param name Template name
     * @param version Template version
     * @return templateId The computed template ID (keccak256 hash)
     * @dev Uses the same algorithm as EBSI ProxyTemplateRegistry
     */
    function computeTemplateId(string calldata name, string calldata version) external pure returns (bytes32 templateId);

    /**
     * @notice Computes the deterministic address for a proxy deployment with a given salt
     * @param templateId The template ID to use for deployment
     * @param initData ABI-encoded initialization selector and arguments
     * @param salt Salt for deterministic CREATE2 deployment
     * @return The predicted proxy address
     */
    function computeProxyAddress(bytes32 templateId, bytes calldata initData, bytes32 salt)
        external
        view
        returns (address);
}
