// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {console2} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {DeployConfig} from "./DeployConfig.s.sol";
import {EBSIContracts, EBSIConfig} from "./DeployTypes.sol";
import {DeployConstants as Constants} from "./DeployConstants.sol";
import {Errors} from "src/libs/Errors.sol";

// EBSI Contracts
import {PolicyRegistry} from "ebsi/trusted-policies-registry/PolicyRegistry.sol";
import {DidRegistry} from "ebsi/did-registry/DidRegistry.sol";
import {Tir} from "ebsi/tir/Tir.sol";
import {ProxyTemplateRegistry} from "ebsi/contract-factory/ProxyTemplateRegistry.sol";
import {ProxyFactory} from "ebsi/contract-factory/ProxyFactory.sol";

/**
 * @title SetupEBSIInfrastructure
 * @author DEUSS Team
 * @notice Comprehensive EBSI infrastructure setup (deployment and integration)
 * @dev Handles setup (deployment, configuration, and integration) of EBSI contracts with BondRegistry
 */
contract SetupEBSIInfrastructure is DeployConfig {
    // solhint-disable private-vars-leading-underscore, ordering
    /*//////////////////////////////////////////////////////////////
                         EBSI CORE DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Main entry point for EBSI setup - handles conditional deployment
     * @return ebsi Struct containing all EBSI contract addresses
     */
    function setupEBSI() public returns (EBSIContracts memory ebsi) {
        EBSIConfig memory config = getEBSIConfig();

        console2.log("=== EBSI Setup ===");
        console2.log("Deploy EBSI Infrastructure:", config.deployEBSI);

        // Step 1: Deploy or load EBSI infrastructure
        if (config.deployEBSI) {
            ebsi = _deployEBSIInfrastructure();
        } else {
            ebsi = _loadExistingEBSIInfrastructure(config);
        }

        console2.log("=== Deploy EBSI Complete ===");
        return ebsi;
    }

    /**
     * @notice Deploy complete EBSI infrastructure (PolicyRegistry, DidRegistry, etc.)
     * @return ebsi Struct with deployed contract addresses
     */
    function _deployEBSIInfrastructure() internal returns (EBSIContracts memory ebsi) {
        console2.log("Deploying EBSI Infrastructure...");

        address policyRegistry = _deployPolicyRegistry();
        address didRegistry = _deployDidRegistry(policyRegistry);
        address proxyTemplateRegistry = _deployProxyTemplateRegistry();
        address proxyFactory = _deployProxyFactory(proxyTemplateRegistry, didRegistry);
        address tir = _deployTir(policyRegistry, didRegistry);

        ebsi = EBSIContracts({
            policyRegistry: policyRegistry,
            didRegistry: didRegistry,
            proxyTemplateRegistry: proxyTemplateRegistry,
            proxyTemplateRegistryImpl: address(0),
            proxyFactory: proxyFactory,
            proxyFactoryImpl: address(0),
            tir: tir
        });

        console2.log(" - PolicyRegistry:", policyRegistry);
        console2.log(" - DidRegistry:", didRegistry);
        console2.log(" - ProxyTemplateRegistry:", proxyTemplateRegistry);
        console2.log(" - ProxyFactory:", proxyFactory);
        console2.log(" - Tir:", tir);

        return ebsi;
    }

    /*//////////////////////////////////////////////////////////////
                      EBSI COMPONENT DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy PolicyRegistry contract
     * @return Address of deployed PolicyRegistry
     */
    function _deployPolicyRegistry() private returns (address) {
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        PolicyRegistry _policy = new PolicyRegistry();
        console2.log(" - PolicyRegistry:", address(_policy));
        // initialize version 1 with deployer as admin
        _policy.initialize(1);
        vm.stopBroadcast();
        return address(_policy);
    }

    /**
     * @notice Deploy DidRegistry contract
     * @param policyRegistry_ Address of PolicyRegistry
     * @return Address of deployed DidRegistry
     */
    function _deployDidRegistry(address policyRegistry_) private returns (address) {
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        DidRegistry _did = new DidRegistry(policyRegistry_);
        console2.log(" - DidRegistry:", address(_did));
        // initialize disabled in constructor; keep as-is (version defaults to 0)
        vm.stopBroadcast();
        return address(_did);
    }

    /**
     * @notice Deploy ProxyTemplateRegistry contract
     * @return Address of deployed ProxyTemplateRegistry
     */
    function _deployProxyTemplateRegistry() private returns (address) {
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        ProxyTemplateRegistry registry = new ProxyTemplateRegistry();
        registry.initialize();
        console2.log(" - Proxy Template Registry:", address(registry));
        vm.stopBroadcast();
        return address(registry);
    }

    /**
     * @notice Deploy ProxyFactory contract
     * @param templateRegistry Address of ProxyTemplateRegistry
     * @param didRegistry_ Address of DidRegistry
     * @return Address of deployed ProxyFactory
     */
    function _deployProxyFactory(address templateRegistry, address didRegistry_) private returns (address) {
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        ProxyFactory factory = new ProxyFactory();
        factory.initialize(templateRegistry, didRegistry_);
        console2.log(" - Proxy Factory:", address(factory));
        vm.stopBroadcast();
        return address(factory);
    }

    /**
     * @notice Deploy Tir (Trusted Issuer Registry) contract
     * @param policyRegistry_ Address of PolicyRegistry
     * @param didRegistry_ Address of DidRegistry
     * @return Address of deployed Tir
     */
    function _deployTir(address policyRegistry_, address didRegistry_) private returns (address) {
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        Tir _tirContract = new Tir(policyRegistry_, didRegistry_);
        console2.log(" - Tir:", address(_tirContract));
        // initialize disabled in constructor; keep as-is (version defaults to 0)
        vm.stopBroadcast();
        return address(_tirContract);
    }

    /**
     * @notice Get EBSI configuration from environment variables
     * @return EBSIConfig struct with deployment settings
     * @dev if deployEBSI is false, all addresses are required
     * @dev if deployEBSI is true, all addresses are set to zero as their deployment is handled afterwards
     */
    function getEBSIConfig() public view returns (EBSIConfig memory) {
        bool deployEBSI = vm.envOr("DEPLOY_EBSI", true);

        // initialize empty ebsi addresses
        address proxyFactory;
        address proxyTemplateRegistry;
        address didRegistry;

        if (!deployEBSI) {
            // Connect to existing EBSI - all addresses required
            proxyFactory = vm.envOr("EBSI_PROXY_FACTORY", address(0));
            if (proxyFactory == address(0)) revert Errors.DeployConfig__EBSIProxyFactoryNotSet();

            proxyTemplateRegistry = vm.envOr("EBSI_PROXY_REGISTRY", address(0));
            if (proxyTemplateRegistry == address(0)) revert Errors.DeployConfig__EBSIProxyRegistryNotSet();

            didRegistry = vm.envOr("EBSI_DID_BOND_REGISTRY", address(0));
            if (didRegistry == address(0)) revert Errors.DeployConfig__EBSIDidRegistryNotSet();
        }

        return EBSIConfig({
            deployEBSI: deployEBSI,
            proxyFactory: proxyFactory,
            proxyTemplateRegistry: proxyTemplateRegistry,
            didRegistry: didRegistry,
            entityRegistryDID: vm.envOr("EBSI_DID_ENTITY_REGISTRY", Constants.EBSI_DID_ENTITY_REGISTRY)
        });
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Load addresses of existing EBSI infrastructure
     * @param config EBSI configuration with addresses
     * @return ebsi Struct with existing contract addresses
     */
    function _loadExistingEBSIInfrastructure(EBSIConfig memory config)
        internal
        pure
        returns (EBSIContracts memory ebsi)
    {
        console2.log("Loading EBSI infra...");

        ebsi = EBSIContracts({
            policyRegistry: address(0), // Not needed for BondRegistry integration
            didRegistry: config.didRegistry,
            proxyTemplateRegistry: config.proxyTemplateRegistry,
            proxyTemplateRegistryImpl: address(0), // Deployed as implementation, not proxy
            proxyFactory: config.proxyFactory,
            proxyFactoryImpl: address(0), // Deployed as implementation, not proxy
            tir: address(0) // Not needed for BondRegistry integration
        });

        console2.log(" - DidRegistry:", config.didRegistry);
        console2.log(" - ProxyTemplateRegistry:", config.proxyTemplateRegistry);
        console2.log(" - ProxyFactory:", config.proxyFactory);

        return ebsi;
    }

    /*//////////////////////////////////////////////////////////////
                    JSON SERIALIZATION (for standalone use)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Serialize EBSI contracts to JSON string
     * @param ebsi EBSI contracts struct
     * @return JSON string representation of EBSI contracts
     */
    function serializeEBSI(EBSIContracts memory ebsi) public returns (string memory) {
        string memory didRegistryJson = vm.serializeAddress("DidRegistry", "contractAddress", ebsi.didRegistry);

        string memory proxyTemplateRegistryJson =
            vm.serializeAddress("ProxyTemplateRegistry", "contractAddress", ebsi.proxyTemplateRegistry);

        string memory proxyFactoryJson = vm.serializeAddress("ProxyFactory", "contractAddress", ebsi.proxyFactory);

        string memory policyRegistryJson = vm.serializeAddress("PolicyRegistry", "contractAddress", ebsi.policyRegistry);
        string memory tirJson = vm.serializeAddress("Tir", "contractAddress", ebsi.tir);

        string memory ebsiJson = vm.serializeString("ebsi", "DidRegistry", didRegistryJson);
        ebsiJson = vm.serializeString("ebsi", "ProxyTemplateRegistry", proxyTemplateRegistryJson);
        ebsiJson = vm.serializeString("ebsi", "ProxyFactory", proxyFactoryJson);
        ebsiJson = vm.serializeString("ebsi", "PolicyRegistry", policyRegistryJson);
        ebsiJson = vm.serializeString("ebsi", "Tir", tirJson);

        return ebsiJson;
    }

    /**
     * @notice Save EBSI deployment to JSON file (for standalone EBSI deployment)
     * @param ebsi EBSI contracts struct
     */
    function saveEBSIDeploymentToJson(EBSIContracts memory ebsi) internal {
        if (!_shouldPersistDeploymentArtifacts()) {
            return;
        }

        console2.log(" - Saving EBSI JSON");

        string memory ebsiJson = serializeEBSI(ebsi);
        string memory finalJson = vm.serializeString("deployment", "ebsi", ebsiJson);

        string memory dir = _deploymentDirPath();
        vm.createDir(dir, true);

        string memory pathLatest = string.concat(
            dir,
            vm.toString(block.chainid),
            "_",
            vm.envOr("BESU_DEPLOY_ENV", string("local")),
            "_",
            vm.toString(block.number),
            "_ebsi.json"
        );
        vm.writeJson(finalJson, pathLatest);
    }

    /**
     * @notice Returns true only for broadcasted or resumed script execution.
     * @dev Forge may execute scripts in additional non-broadcast contexts while preparing or simulating a run.
     *      Persisting deployment JSON in those contexts can overwrite the real broadcast artifacts with addresses
     *      that were never deployed on-chain. Restricting writes to broadcast/resume contexts ensures `latest`
     *      deployment files are generated for local Anvil runs and other real deployments, while simulation-only
     *      passes cannot corrupt them.
     * @return shouldPersist Whether deployment files should be written for the current Forge context.
     */
    function _shouldPersistDeploymentArtifacts() internal view returns (bool shouldPersist) {
        return vm.isContext(VmSafe.ForgeContext.ScriptBroadcast) || vm.isContext(VmSafe.ForgeContext.ScriptResume);
    }
}
