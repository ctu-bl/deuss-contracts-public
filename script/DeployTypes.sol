// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title EBSIConfig
 * @author DEUSS Team
 * @notice Configuration struct for EBSI deployment
 */
struct EBSIConfig {
    bool deployEBSI; // Deploy new EBSI or connect to existing
    address proxyFactory; // Required if deployEBSI=false
    address proxyTemplateRegistry; // Required if deployEBSI=false
    address didRegistry; // Required if deployEBSI=false
    string entityRegistryDID; // DID for EntityRegistry
}

/**
 * @title NetworkConfig
 * @author DEUSS Team
 * @notice Configuration struct for network deployment
 */
struct NetworkConfig {
    uint256 deployerKey;
    uint256 timelockControllerAdminKey;
    uint256 timelockControllerActorKey;
    uint256 adminKey;
    string env;
}

/**
 * @title Registries
 * @author DEUSS Team
 * @notice Configuration struct for registries deployment
 */
struct Registries {
    address entityRegistry;
    address entityRegistryBeacon;
    address entityRegistryImpl;
    address walletPolicyRegistry;
    address walletPolicyRegistryBeacon;
    address walletPolicyRegistryImpl;
    address walletFactory;
    address walletFactoryBeacon;
    address bondRegistry;
    address bondRegistryBeacon;
    address bondRegistryImpl;
}

/**
 * @title CoreContracts
 * @author DEUSS Team
 * @notice Configuration struct for core contracts deployment
 */
struct CoreContracts {
    address assetManager;
    address assetManagerBeacon;
    address assetManagerImpl;
    address marketplace;
    address marketplaceBeacon;
    address marketplaceImpl;
    address escrowManager;
    address escrowManagerBeacon;
    address escrowManagerImpl;
    address orderbookMarketplace;
    address orderbookMarketplaceBeacon;
    address orderbookMarketplaceImpl;
    address bondMarketFilter;
    address bondMarketFilterBeacon;
    address bondMarketFilterImpl;
}

/**
 * @title Governance
 * @author DEUSS Team
 * @notice Governance contract deployment
 */
struct Governance {
    address timelockController;
    address timelockControllerBeacon;
    address timelockControllerImpl;
}

/**
 * @title Multi Token contract
 * @author DEUSS Team
 * @notice Configuration struct for token contract deployment
 */
struct MultiToken {
    address deussToken;
    address deussTokenBeacon;
    address deussTokenImpl;
}

/**
 * @title CompanyWallet
 * @author DEUSS Team
 * @notice Configuration struct for company wallet deployment
 */
struct CompanyWallet {
    address companyWalletBeacon;
    address companyWalletImpl;
}

/**
 * @title UtilsContracts
 * @author DEUSS Team
 * @notice Configuration struct for utils contracts deployment
 */
struct UtilsContracts {
    address multicall;
    address marketplaceLens;
    address marketplaceLensBeacon;
    address marketplaceLensImpl;
}

/**
 * @title EBSIContracts
 * @author DEUSS Team
 * @notice Configuration struct for EBSI contracts deployment
 */
struct EBSIContracts {
    address policyRegistry;
    address didRegistry;
    address proxyTemplateRegistry;
    address proxyTemplateRegistryImpl;
    address proxyFactory;
    address proxyFactoryImpl;
    address tir;
}

/**
 * @title Suite
 * @author DEUSS Team
 * @notice Configuration struct for suite deployment
 */
struct Suite {
    CoreContracts core;
    Governance governance;
    Registries registries;
    UtilsContracts utils;
    MultiToken multiToken;
    CompanyWallet wallet;
    EBSIContracts ebsi;
}

/**
 * @title BootstrapConfig
 * @author DEUSS Team
 * @notice Script-side configuration for the bootstrap stage, loaded from env vars.
 *         Controls which optional bootstrap steps are applied and with what parameters.
 */
struct BootstrapConfig {
    bytes32 companyEntityName;
    uint256 companyEntityCaps;
    bool unpauseToken;
    bool registerEscrowEntity;
    string[] allowedCurrencies;
}
