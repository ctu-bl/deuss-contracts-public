// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title DeployConstants
 * @author DEUSS Team
 * @notice Centralized constants for all deployment scripts
 * @dev All deployment-related constants are defined here to maintain consistency
 *      and make it easier to update configuration values
 */
library DeployConstants {
    /*//////////////////////////////////////////////////////////////
                         ANVIL TEST NETWORK
    //////////////////////////////////////////////////////////////*/

    /// @notice Default Anvil local network chain ID
    uint256 internal constant DEFAULT_ANVIL_NETWORK_ID = 31337;

    /// @notice Default Anvil deployer private key (account 0)
    uint256 internal constant DEFAULT_ANVIL_DEPLOYER_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /// @notice Default Anvil governance private key (account 1)
    uint256 internal constant DEFAULT_ANVIL_GOVERNANCE_PRIVATE_KEY =
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    /// @notice Default Anvil admin private key (account 2)
    uint256 internal constant DEFAULT_ANVIL_ADMIN_PRIVATE_KEY =
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;

    /// @notice Default Anvil admin private key (account 3)
    uint256 internal constant DEFAULT_ANVIL_TIMELOCK_CONTROLLER_ADMIN_PRIVATE_KEY =
        0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    /// @notice Default Anvil admin private key (account 4)
    uint256 internal constant DEFAULT_ANVIL_TIMELOCK_CONTROLLER_ACTOR_PRIVATE_KEY =
        0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a;

    /// @notice Pre-deployed Multicall3 contract address on Anvil local network
    address internal constant ANVIL_MULTICALL = 0x281F6BE55cc3fa2Ff62D61d9Ec2DEe5168Aa82Da;

    /*//////////////////////////////////////////////////////////////
                      EBSI TOKEN TEMPLATES
    //////////////////////////////////////////////////////////////*/

    /// @notice EBSI DID Bond registry name
    string internal constant EBSI_DID_BOND_REGISTRY = "did:ebsi:bond-registry";

    /// @notice EBSI DID Company wallet registry name
    string internal constant EBSI_DID_ENTITY_REGISTRY = "did:ebsi:entity-registry";

    /// @notice Bond DEUSSToken template name
    string internal constant BOND_FT_TEMPLATE_NAME = "BondFT";

    /// @notice Bond DEUSSToken template version
    string internal constant BOND_FT_TEMPLATE_VERSION = "1.0.0";

    /// @notice Company Wallet Registry template name
    string internal constant COMPANY_WALLET_TEMPLATE_NAME = "CompanyWallet";

    /// @notice Company Wallet Registry template version
    string internal constant COMPANY_WALLET_TEMPLATE_VERSION = "1.0.0";

    /// @notice Wallet type used for company wallet deployments
    bytes32 internal constant COMPANY_WALLET_TYPE = keccak256("COMPANY_WALLET");

    /*//////////////////////////////////////////////////////////////
                      REPOSITORY & AUDIT URIs
    //////////////////////////////////////////////////////////////*/

    /// @notice Main repository URI
    // solhint-disable-next-line gas-small-strings
    string internal constant REPO_URI = "https://gitlab.nesad.fit.vutbr.cz/bebi/onchain-core/bond-contract";

    /// @notice Audit report URI for DEUSSToken
    // solhint-disable-next-line gas-small-strings
    string internal constant AUDIT_URI_FT = "https://audit.deuss.com/fungible-token";

    /// @notice Audit report URI for Company Wallet
    // solhint-disable-next-line gas-small-strings
    string internal constant AUDIT_URI_CW = "https://audit.deuss.com/company-wallet";

    /*//////////////////////////////////////////////////////////////
                      CREATE2 DEPLOYMENT SALTS
    //////////////////////////////////////////////////////////////*/

    // Governance Salts
    // @notice Salt for TimelockController CREATE2 deployment
    string internal constant TIMELOCK_CONTROLLER_SALT = "governanceTimelockSalt";

    // Factory Salts
    /// @notice Salt for ClaimIssuerFactory CREATE2 deployment
    string internal constant CLAIM_ISSUER_FACTORY_SALT = "claimIssuerFactorySalt";

    /// @notice Salt for IdentityFactory CREATE2 deployment
    string internal constant IDENTITY_FACTORY_SALT = "identityFactorySalt";

    /// @notice Generic factory salt (unused - consider removing)
    string internal constant FACTORY_SALT = "factorySalt";

    // Registry Salts
    /// @notice Salt for BondRegistry CREATE2 deployment
    string internal constant BOND_REGISTRY_SALT = "bondRegistrySalt";

    /// @notice Salt for EntityRegistry CREATE2 deployment
    string internal constant ENTITY_REGISTRY_SALT = "entityRegistrySalt";

    /// @notice Salt for WalletFactory CREATE2 deployment
    string internal constant WALLET_FACTORY_SALT = "walletFactorySalt";

    /// @notice Salt for wallet PolicyRegistry CREATE2 deployment
    string internal constant POLICY_REGISTRY_SALT = "policyRegistrySalt";

    /// @notice Salt for ClaimTopicsIssuersRegistry CREATE2 deployment
    string internal constant CTIR_SALT = "ctirSalt";

    /// @notice Salt for IdentityRegistry CREATE2 deployment
    string internal constant IR_SALT = "irSalt";

    // Core Contract Salts
    /// @notice Salt for ClaimManager CREATE2 deployment
    string internal constant CLAIM_MANAGER_SALT = "claimManagerSalt";

    /// @notice Salt for Verifier CREATE2 deployment
    string internal constant VERIFIER_SALT = "verifierSalt";

    /// @notice Salt for Marketplace CREATE2 deployment
    string internal constant MARKETPLACE_SALT = "marketplaceSalt";

    /// @notice Salt for MarketplaceLens CREATE2 deployment
    string internal constant MARKETPLACE_LENS_SALT = "marketplaceLensSalt";

    /// @notice Salt for AssetManager CREATE2 deployment
    string internal constant ASSET_MANAGER_SALT = "assetManagerSalt";

    /// @notice Salt for EscrowManager CREATE2 deployment
    string internal constant ESCROW_MANAGER_SALT = "escrowManagerSalt";

    /// @notice Salt for OrderbookMarketplace CREATE2 deployment
    string internal constant ORDERBOOK_MARKETPLACE_SALT = "orderbookMarketplaceSalt";

    /// @notice Salt for BondMarketFilter CREATE2 deployment
    string internal constant BOND_MARKET_FILTER_SALT = "bondMarketFilterSalt";

    // Token Salts
    /// @notice Salt for ERC-6909 Minimal Multi-Token CREATE2 deployment
    string internal constant TOKEN_SALT = "tokenSalt";

    // EBSI Contract Salts
    /// @notice Salt for ProxyTemplateRegistry CREATE2 deployment
    string internal constant PROXY_TEMPLATE_REGISTRY_SALT = "proxyTemplateRegistrySalt";

    /// @notice Salt for ProxyFactory CREATE2 deployment
    string internal constant PROXY_FACTORY_SALT = "proxyFactorySalt";

    /// @notice Salt for Multicall deployment
    bytes32 internal constant MULTICALL_SALT = bytes32(uint256(0));

    /*//////////////////////////////////////////////////////////////
            Create2 Deterministic Deployment Proxy Address
    //////////////////////////////////////////////////////////////*/

    /// @notice Canonical CREATE2 deployer proxy address (deployed on most EVM chains)
    /// @dev See https://github.com/Arachnid/deterministic-deployment-proxy
    address public constant CREATE2_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /*//////////////////////////////////////////////////////////////
                      PROXY IMPLEMENTATION SLOT
    //////////////////////////////////////////////////////////////*/

    /// @notice EIP-1967 implementation slot for proxy contracts
    /// @dev keccak256("eip1967.proxy.implementation") - 1
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice EIP-1967 beacon slot for beacon proxy contracts
    /// @dev keccak256("eip1967.proxy.beacon") - 1
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /*//////////////////////////////////////////////////////////////
                            OTHER CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice
    uint256 internal constant TIMELOCK_CONTROLLER_MIN_DELAY = 1 days;

    bytes32 internal constant TIMELOCK_CONTROLLER_OP_SALT = bytes32("timelockControllerOpSalt");

    /// @notice Payment expiry threshold (4 days / 96 hours) for direct marketplace deals handled by Marketplace
    uint256 internal constant MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_MARKETPLACE_MODE = 4 days;

    /// @notice Payment expiry threshold (5 days / 120 hours) for accepted redemption deals handled by Marketplace
    uint256 internal constant MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_REDEMPTION_MODE = 5 days;

    /// @notice Payment expiry threshold (4 days / 96 hours) for deals created from activated interests
    uint256 internal constant MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_INTEREST_DISCOVERY_MODE = 4 days;

    /// @notice Minimum lifetime (1 day) for Marketplace offers and counter offers
    uint256 internal constant MARKETPLACE_OFFER_EXPIRY_THRESHOLD = 1 days;

    /// @notice Maximum lifetime (365 days) for Marketplace offers and counter offers
    uint256 internal constant MARKETPLACE_MAX_OFFER_LIFETIME = 365 days;

    /// @notice Dispute buffer period (3 days / 72 hours) for Marketplace
    uint256 internal constant MARKETPLACE_DISPUTE_BUFFER_PERIOD = 3 days;

    /// @notice Maximum number of counter offers per user per offer
    uint256 internal constant MAX_COUNTER_OFFERS_PER_USER = 5;

    /// @notice Payment expiry threshold (1 day / 24 hours) for OrderbookMarketplace
    uint256 internal constant ORDERBOOK_PAYMENT_EXPIRY_THRESHOLD = 1 days;

    /// @notice Minimum order expiry threshold (1 day / 24 hours) for OrderbookMarketplace
    uint256 internal constant ORDERBOOK_MIN_EXPIRY_THRESHOLD = 1 days;

    /// @notice Dispute buffer period (1 day / 24 hours) for OrderbookMarketplace
    uint256 internal constant ORDERBOOK_DISPUTE_BUFFER_PERIOD = 1 days;
    /// @notice Default entity type identifiers
    uint256 internal constant COMPANY_ENTITY = 1;
    uint256 internal constant NATURAL_PERSON_ENTITY = 2;
    uint256 internal constant AGENT_ENTITY = 3;
    uint256 internal constant DEUSS_PROTOCOL_ENTITY = 4;

    /// @notice Pre-deployed Multicall3 contract address
    address internal constant MULTICALL = 0xd54eF8e857B538e4f580BD3e95066755958f78e1;
}
