// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {console2} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {SetupEBSIInfrastructure} from "../SetupEBSIInfrastructure.s.sol";
import {DeployConstants as Constants} from "../DeployConstants.sol";
import {
    EBSIContracts,
    Registries,
    Governance,
    CoreContracts,
    CompanyWallet,
    MultiToken,
    UtilsContracts,
    Suite
} from "../DeployTypes.sol";
import {BRDeployer} from "src/deployer/registries/BRDeployer.sol";
import {ERDeployer} from "src/deployer/registries/ERDeployer.sol";
import {PolicyRegistryDeployer} from "src/deployer/registries/PolicyRegistryDeployer.sol";
import {WalletFactoryDeployer} from "src/deployer/registries/WalletFactoryDeployer.sol";
import {TimelockControllerDeployer} from "src/deployer/governance/TimelockControllerDeployer.sol";
import {EscrowManagerDeployer} from "src/deployer/marketplace/EscrowManagerDeployer.sol";
import {AssetManagerDeployer} from "src/deployer/marketplace/AssetManagerDeployer.sol";
import {MarketplaceLensDeployer} from "src/deployer/marketplace/MarketplaceLensDeployer.sol";
import {MarketplaceDeployer} from "src/deployer/marketplace/MarketplaceDeployer.sol";
import {OrderbookMarketplaceDeployer} from "src/deployer/marketplace/OrderbookMarketplaceDeployer.sol";
import {BondMarketFilterDeployer} from "src/deployer/marketplace/BondMarketFilterDeployer.sol";
import {TokenDeployer} from "src/deployer/token/TokenDeployer.sol";
import {Multicall3} from "src/utils/Multicall3.sol";
import {Errors} from "src/libs/Errors.sol";
import {CompanyWallet as CompanyWalletContract} from "src/wallet/CompanyWallet.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ProtocolAddresses} from "../ProtocolAddresses.s.sol";
import {DeployConfig} from "../DeployConfig.s.sol";

/**
 * @title DeployProtocol
 * @author DEUSS Team
 * @notice Pure deployment stage: deploys all protocol contracts and writes a manifest.
 *         Performs no role grants and no post-deploy wiring; token initialization
 *         protects the deployed EscrowManager custody address atomically.
 */
contract DeployProtocol is DeployConfig, ProtocolAddresses {
    /// @notice EBSI infrastructure deployer, set during deployment and reused by bootstrap.
    SetupEBSIInfrastructure public ebsiInfrastructure;

    /*//////////////////////////////////////////////////////////////
                               ENTRY POINT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy all contracts and persist the manifest. No post-deploy wiring applied.
     * @return suite Struct with unlinked deployed contract addresses
     */
    function run() public virtual returns (Suite memory suite) {
        _initAddresses();
        suite = _deploySuiteContracts();

        if (_shouldPersistDeploymentArtifacts()) {
            _saveDeploymentToJson(suite);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            BEACON HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Read the beacon address backing a deployed proxy.
     * @param proxy BeaconProxy contract address
     * @return beacon UpgradeableBeacon contract address
     */
    function getBeacon(address proxy) public view returns (address beacon) {
        return _getBeacon(proxy);
    }

    /**
     * @notice Read the implementation address backing a deployed proxy.
     * @param proxy BeaconProxy contract address
     * @return implementation Current implementation contract address
     */
    function getImplementation(address proxy) public view returns (address implementation) {
        return _getBeaconImplementation(proxy);
    }

    /*//////////////////////////////////////////////////////////////
                          DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialise all actor addresses from the active network config.
     *         Skips any address that has already been set (idempotent).
     */
    function _initAddresses() internal {
        if (deployer == address(0)) deployer = vm.createWallet(_activeNetworkConfig.deployerKey).addr;
        if (admin == address(0)) admin = vm.createWallet(_activeNetworkConfig.adminKey).addr;
        if (timelockControllerAdmin == address(0)) {
            timelockControllerAdmin = vm.createWallet(_activeNetworkConfig.timelockControllerAdminKey).addr;
        }
        if (timelockControllerActor == address(0)) {
            timelockControllerActor = vm.createWallet(_activeNetworkConfig.timelockControllerActorKey).addr;
        }
    }

    /**
     * @notice Deploy all contracts. Marketplace receives EntityRegistry during initialization;
     *         remaining cross-dependencies are wired by BootstrapProtocol. DEUSSToken is initialized
     *         after EscrowManager deployment so protected custody is configured atomically.
     * @return suite Struct with all deployed addresses
     */
    function _deploySuiteContracts() internal returns (Suite memory suite) {
        ebsiInfrastructure = new SetupEBSIInfrastructure();
        EBSIContracts memory ebsi = ebsiInfrastructure.setupEBSI();

        console2.log("=== Start DEUSS deploy ===");
        suite.governance = _deployGovernance();
        suite.registries = _deployRegistries();
        suite.core = _deployCoreContracts(suite.registries);
        suite.multiToken = _deployToken(suite.registries, suite.core.escrowManager);
        suite.utils = _deployUtils(suite.core.marketplace);
        suite.wallet = _deployCompanyWalletBeacon();
        suite.ebsi = ebsi;
        console2.log("=== DEUSS deploy done ===");
    }

    /**
     * @notice Deploy all governance contracts.
     * @return governance Struct with deployed governance addresses
     */
    function _deployGovernance() internal returns (Governance memory governance) {
        console2.log("--- Governance ---");

        console2.log("Deploying Timelock Controller");
        console2.log("Deployer", deployer);
        uint256 minDelay = vm.envOr("TIMELOCK_MIN_DELAY", Constants.TIMELOCK_CONTROLLER_MIN_DELAY);
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        TimelockControllerDeployer timelockControllerDeployer = new TimelockControllerDeployer(
            minDelay, new address[](0), new address[](0), timelockControllerAdmin, Constants.TIMELOCK_CONTROLLER_SALT
        );
        governance.timelockController = address(timelockControllerDeployer.timelockController());
        governance.timelockControllerBeacon = getBeacon(governance.timelockController);
        governance.timelockControllerImpl = getImplementation(governance.timelockController);
        // set global address
        timelockController = payable(governance.timelockController);
        vm.stopBroadcast();
    }

    /**
     * @notice Deploy all registry contracts.
     * @return registries Struct with deployed registry addresses
     */
    function _deployRegistries() internal returns (Registries memory registries) {
        console2.log("--- Deploying Registries ---");

        console2.log("Deploying Bond Registry");
        registries.bondRegistry = _deployBondRegistry();
        registries.bondRegistryBeacon = getBeacon(registries.bondRegistry);
        registries.bondRegistryImpl = getImplementation(registries.bondRegistry);

        console2.log("Deploying Entity Registry");
        registries.entityRegistry = _deployEntityRegistry();
        registries.entityRegistryBeacon = getBeacon(registries.entityRegistry);
        registries.entityRegistryImpl = getImplementation(registries.entityRegistry);

        console2.log("Deploying Wallet Policy Registry");
        registries.walletPolicyRegistry = _deployWalletPolicyRegistry();
        registries.walletPolicyRegistryBeacon = getBeacon(registries.walletPolicyRegistry);
        registries.walletPolicyRegistryImpl = getImplementation(registries.walletPolicyRegistry);

        console2.log("Deploying WalletFactory");
        registries.walletFactory = _deployWalletFactory(registries.entityRegistry);
        registries.walletFactoryBeacon = getBeacon(registries.walletFactory);
    }

    /**
     * @notice Deploy token contract.
     * @param registries Deployed registry addresses
     * @param escrowManager Deployed EscrowManager address to protect during token initialization
     * @return multiToken Struct with deployed token contract address
     */
    function _deployToken(Registries memory registries, address escrowManager)
        internal
        returns (MultiToken memory multiToken)
    {
        console2.log("--- Deploying Token ---");
        console2.log("Deploying DEUSSToken");

        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        TokenDeployer tokenDeployer = new TokenDeployer(
            deployer, registries.bondRegistry, registries.entityRegistry, escrowManager, Constants.TOKEN_SALT
        );
        multiToken.deussToken = address(tokenDeployer.token());
        multiToken.deussTokenBeacon = getBeacon(multiToken.deussToken);
        multiToken.deussTokenImpl = getImplementation(multiToken.deussToken);
        vm.stopBroadcast();

        console2.log(" - Multi Token:", multiToken.deussToken);
    }

    /**
     * @notice Deploy CompanyWallet implementation and UpgradeableBeacon.
     * @return wallet Struct with impl and beacon addresses
     */
    function _deployCompanyWalletBeacon() internal returns (CompanyWallet memory wallet) {
        console2.log("--- Deploying CompanyWallet ---");

        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        wallet.companyWalletImpl = address(new CompanyWalletContract());
        wallet.companyWalletBeacon = address(new UpgradeableBeacon(wallet.companyWalletImpl, deployer));
        vm.stopBroadcast();

        console2.log(" - CompanyWallet impl:", wallet.companyWalletImpl);
        console2.log(" - CompanyWallet beacon:", wallet.companyWalletBeacon);
    }

    /**
     * @notice Deploy all core contracts.
     * @dev Marketplace requires EntityRegistry at initialization; other cross-dependencies use address(0) placeholders.
     * @param registries Deployed registry addresses
     * @return core Struct with deployed core contract addresses
     */
    function _deployCoreContracts(Registries memory registries) internal returns (CoreContracts memory core) {
        console2.log("--- Deploying Core Contracts ---");

        console2.log("Deploying Asset Manager");
        core.assetManager = _deployAssetManager();
        core.assetManagerBeacon = getBeacon(core.assetManager);
        core.assetManagerImpl = getImplementation(core.assetManager);

        console2.log("Deploying Marketplace");
        core.marketplace = _deployMarketplace(core.assetManager, address(0), registries.entityRegistry);
        core.marketplaceBeacon = getBeacon(core.marketplace);
        core.marketplaceImpl = getImplementation(core.marketplace);

        console2.log("Deploying Bond Market Filter");
        core.bondMarketFilter = _deployBondMarketFilter();
        core.bondMarketFilterBeacon = getBeacon(core.bondMarketFilter);
        core.bondMarketFilterImpl = getImplementation(core.bondMarketFilter);

        console2.log("Deploying Orderbook Marketplace");
        core.orderbookMarketplace =
            _deployOrderbookMarketplace(address(0), address(0), address(0), core.bondMarketFilter);
        core.orderbookMarketplaceBeacon = getBeacon(core.orderbookMarketplace);
        core.orderbookMarketplaceImpl = getImplementation(core.orderbookMarketplace);

        console2.log("Deploying Escrow Manager");
        core.escrowManager = _deployEscrowManager(address(0), address(0));
        core.escrowManagerBeacon = getBeacon(core.escrowManager);
        core.escrowManagerImpl = getImplementation(core.escrowManager);
    }

    /**
     * @notice Deploy utility contracts
     * @param marketplace Deployed Marketplace proxy address
     * @return utils Struct with deployed utility contract addresses
     */
    function _deployUtils(address marketplace) internal returns (UtilsContracts memory utils) {
        console2.log("--- Deploying Utils ---");

        console2.log("Deploying Multicall");
        if (!vm.isContext(VmSafe.ForgeContext.Coverage)) {
            utils.multicall = _deployMulticall();
        }

        console2.log("Deploying Marketplace Lens");
        utils.marketplaceLens = _deployMarketplaceLens(marketplace);
        utils.marketplaceLensBeacon = getBeacon(utils.marketplaceLens);
        utils.marketplaceLensImpl = getImplementation(utils.marketplaceLens);
    }

    /*//////////////////////////////////////////////////////////////
                     INDIVIDUAL CONTRACT DEPLOYERS
    //////////////////////////////////////////////////////////////*/

    function _deployBondRegistry() internal returns (address bondRegistry) {
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        BRDeployer brDeployer = new BRDeployer(deployer, Constants.BOND_REGISTRY_SALT);
        bondRegistry = address(brDeployer.bondRegistry());
        vm.stopBroadcast();
        console2.log(" - BondRegistry:", bondRegistry);
    }

    function _deployBondMarketFilter() internal returns (address bondMarketFilter) {
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        BondMarketFilterDeployer bondMarketFilterDeployer =
            new BondMarketFilterDeployer(deployer, Constants.BOND_MARKET_FILTER_SALT);
        bondMarketFilter = address(bondMarketFilterDeployer.bondMarketFilter());
        vm.stopBroadcast();
        console2.log(" - BondMarketFilter:", bondMarketFilter);
    }

    function _deployEntityRegistry() internal returns (address entityRegistry) {
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        ERDeployer erDeployer = new ERDeployer(deployer, Constants.ENTITY_REGISTRY_SALT);
        entityRegistry = address(erDeployer.entityRegistry());
        vm.stopBroadcast();
        console2.log(" - EntityRegistry:", entityRegistry);
    }

    function _deployWalletFactory(address entityRegistry) internal returns (address factory) {
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        WalletFactoryDeployer wfDeployer =
            new WalletFactoryDeployer(entityRegistry, deployer, Constants.WALLET_FACTORY_SALT);
        factory = address(wfDeployer.walletFactory());
        vm.stopBroadcast();
        console2.log(" - WalletFactory:", factory);
    }

    function _deployWalletPolicyRegistry() internal returns (address policyRegistry) {
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        PolicyRegistryDeployer prDeployer = new PolicyRegistryDeployer(deployer, Constants.POLICY_REGISTRY_SALT);
        policyRegistry = address(prDeployer.policyRegistry());
        vm.stopBroadcast();
        console2.log(" - PolicyRegistry:", policyRegistry);
    }

    function _deployAssetManager() internal returns (address assetManager) {
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        AssetManagerDeployer amDeployer = new AssetManagerDeployer(deployer, Constants.ASSET_MANAGER_SALT);
        assetManager = address(amDeployer.assetManager());
        vm.stopBroadcast();
        console2.log(" - AssetManager:", assetManager);
    }

    function _deployMarketplace(address assetManager, address escrowManager, address entityRegistry)
        internal
        returns (address marketplace)
    {
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        MarketplaceDeployer.MarketplaceDeployParams memory params = MarketplaceDeployer.MarketplaceDeployParams({
            owner: deployer,
            offerExpiryThreshold: Constants.MARKETPLACE_OFFER_EXPIRY_THRESHOLD,
            maxOfferLifetime: Constants.MARKETPLACE_MAX_OFFER_LIFETIME,
            marketplacePaymentExpiryThreshold: Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_MARKETPLACE_MODE,
            redemptionPaymentExpiryThreshold: Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_REDEMPTION_MODE,
            interestDiscoveryPaymentExpiryThreshold: Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_INTEREST_DISCOVERY_MODE,
            disputeBufferPeriod: Constants.MARKETPLACE_DISPUTE_BUFFER_PERIOD,
            assetManager: assetManager,
            escrowManager: escrowManager,
            entityRegistry: entityRegistry,
            maxCounterOffers: Constants.MAX_COUNTER_OFFERS_PER_USER,
            marketplaceSalt: Constants.MARKETPLACE_SALT
        });
        MarketplaceDeployer marketplaceDeployer = new MarketplaceDeployer(params);
        marketplace = address(marketplaceDeployer.marketplace());
        vm.stopBroadcast();
        console2.log(" - Marketplace:", marketplace);
    }

    function _deployOrderbookMarketplace(
        address assetManager,
        address entityRegistry,
        address escrowManager,
        address marketFilter
    ) internal returns (address orderbookMarketplace) {
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        OrderbookMarketplaceDeployer obDeployer = new OrderbookMarketplaceDeployer(
            deployer,
            assetManager,
            entityRegistry,
            escrowManager,
            Constants.ORDERBOOK_PAYMENT_EXPIRY_THRESHOLD,
            Constants.ORDERBOOK_MIN_EXPIRY_THRESHOLD,
            Constants.ORDERBOOK_DISPUTE_BUFFER_PERIOD,
            marketFilter,
            Constants.ORDERBOOK_MARKETPLACE_SALT
        );
        orderbookMarketplace = address(obDeployer.orderbookMarketplace());
        vm.stopBroadcast();
        console2.log(" - Orderbook Marketplace:", orderbookMarketplace);
    }

    function _deployEscrowManager(address marketplace, address orderbookMarketplace)
        internal
        returns (address escrowManager)
    {
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        EscrowManagerDeployer emDeployer =
            new EscrowManagerDeployer(deployer, marketplace, orderbookMarketplace, Constants.ESCROW_MANAGER_SALT);
        escrowManager = address(emDeployer.escrowManager());
        vm.stopBroadcast();
        console2.log(" - Escrow Manager:", escrowManager);
    }

    function _deployMulticall() internal returns (address multicall) {
        bytes memory multicallInitCode = abi.encodePacked(type(Multicall3).creationCode, abi.encode());
        multicall = block.chainid == Constants.DEFAULT_ANVIL_NETWORK_ID
            ? _computeCreate2Address(Constants.MULTICALL_SALT, multicallInitCode)
            : Constants.MULTICALL;

        if (multicall.code.length == 0) {
            bytes memory multicallCode = abi.encodePacked(Constants.MULTICALL_SALT, multicallInitCode);
            vm.startBroadcast(_activeNetworkConfig.deployerKey);
            // solhint-disable-next-line avoid-low-level-calls
            (bool success,) = Constants.CREATE2_PROXY.call(multicallCode);
            vm.stopBroadcast();
            if (!success || multicall.code.length == 0) revert Errors.Create2DeploymentFailed(multicall);
            console2.log("Deployed Multicall.");
        }
        console2.log("Multicall:", multicall);
    }

    function _deployMarketplaceLens(address marketplace) internal returns (address marketplaceLens) {
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        MarketplaceLensDeployer lensDeployer =
            new MarketplaceLensDeployer(deployer, marketplace, Constants.MARKETPLACE_LENS_SALT);
        marketplaceLens = address(lensDeployer.marketplaceLens());
        vm.stopBroadcast();
        console2.log(" - Marketplace Lens:", marketplaceLens);
    }

    /*//////////////////////////////////////////////////////////////
                         MANIFEST PERSISTENCE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Persist deployment addresses to deployment JSON files.
     *
     *         Flat layout:
     *           deployments/<chainId>_<env>_latest.json
     *           deployments/<chainId>_<env>_<block>.json
     *
     * @param suite Deployed suite addresses
     */
    function _saveDeploymentToJson(Suite memory suite) internal {
        string memory coreJson = _serializeCoreContracts(suite.core);
        string memory registriesJson = _serializeRegistries(suite.registries);
        string memory governanceJson = _serializeGovernance(suite.governance);
        string memory walletJson = _serializeWallet(suite.wallet);
        string memory multiTokenJson = _serializeToken(suite.multiToken);
        string memory utilsJson = _serializeUtils(suite.utils);
        string memory ebsiJson = ebsiInfrastructure.serializeEBSI(suite.ebsi);

        string memory chainStr = vm.toString(block.chainid);
        string memory env = _activeNetworkConfig.env;
        string memory blockStr = vm.toString(block.number);

        string memory finalJson = vm.serializeString("deployment", "core", coreJson);
        finalJson = vm.serializeString("deployment", "registries", registriesJson);
        finalJson = vm.serializeString("deployment", "governance", governanceJson);
        finalJson = vm.serializeString("deployment", "wallet", walletJson);
        finalJson = vm.serializeString("deployment", "multiToken", multiTokenJson);
        finalJson = vm.serializeString("deployment", "utils", utilsJson);
        finalJson = vm.serializeString("deployment", "ebsi", ebsiJson);

        string memory dir = _deploymentDirPath();
        vm.createDir(dir, true);
        vm.writeJson(finalJson, string.concat(dir, chainStr, "_", env, "_latest.json"));
        vm.writeJson(finalJson, string.concat(dir, chainStr, "_", env, "_", blockStr, ".json"));
    }

    /*//////////////////////////////////////////////////////////////
                         JSON SERIALIZERS
    //////////////////////////////////////////////////////////////*/

    function _serializeCoreContracts(CoreContracts memory core) internal returns (string memory) {
        string memory assetManagerJson = vm.serializeAddress("AssetManager", "contractAddress", core.assetManager);
        assetManagerJson = vm.serializeAddress("AssetManager", "beaconAddress", core.assetManagerBeacon);
        assetManagerJson = vm.serializeAddress("AssetManager", "implementationAddress", core.assetManagerImpl);

        string memory escrowManagerJson = vm.serializeAddress("EscrowManager", "contractAddress", core.escrowManager);
        escrowManagerJson = vm.serializeAddress("EscrowManager", "beaconAddress", core.escrowManagerBeacon);
        escrowManagerJson = vm.serializeAddress("EscrowManager", "implementationAddress", core.escrowManagerImpl);

        string memory marketplaceJson = vm.serializeAddress("Marketplace", "contractAddress", core.marketplace);
        marketplaceJson = vm.serializeAddress("Marketplace", "beaconAddress", core.marketplaceBeacon);
        marketplaceJson = vm.serializeAddress("Marketplace", "implementationAddress", core.marketplaceImpl);

        string memory orderbookMarketplaceJson =
            vm.serializeAddress("OrderbookMarketplace", "contractAddress", core.orderbookMarketplace);
        orderbookMarketplaceJson =
            vm.serializeAddress("OrderbookMarketplace", "beaconAddress", core.orderbookMarketplaceBeacon);
        orderbookMarketplaceJson =
            vm.serializeAddress("OrderbookMarketplace", "implementationAddress", core.orderbookMarketplaceImpl);

        string memory bondMarketFilterJson =
            vm.serializeAddress("BondMarketFilter", "contractAddress", core.bondMarketFilter);
        bondMarketFilterJson = vm.serializeAddress("BondMarketFilter", "beaconAddress", core.bondMarketFilterBeacon);
        bondMarketFilterJson =
            vm.serializeAddress("BondMarketFilter", "implementationAddress", core.bondMarketFilterImpl);

        string memory coreJson = vm.serializeString("core", "AssetManager", assetManagerJson);
        coreJson = vm.serializeString("core", "EscrowManager", escrowManagerJson);
        coreJson = vm.serializeString("core", "Marketplace", marketplaceJson);
        coreJson = vm.serializeString("core", "OrderbookMarketplace", orderbookMarketplaceJson);
        coreJson = vm.serializeString("core", "BondMarketFilter", bondMarketFilterJson);
        return coreJson;
    }

    function _serializeRegistries(Registries memory registries) internal returns (string memory) {
        string memory bondRegistryJson = vm.serializeAddress("BondRegistry", "contractAddress", registries.bondRegistry);
        bondRegistryJson = vm.serializeAddress("BondRegistry", "beaconAddress", registries.bondRegistryBeacon);
        bondRegistryJson = vm.serializeAddress("BondRegistry", "implementationAddress", registries.bondRegistryImpl);

        string memory entityRegistryJson =
            vm.serializeAddress("EntityRegistry", "contractAddress", registries.entityRegistry);
        entityRegistryJson = vm.serializeAddress("EntityRegistry", "beaconAddress", registries.entityRegistryBeacon);
        entityRegistryJson =
            vm.serializeAddress("EntityRegistry", "implementationAddress", registries.entityRegistryImpl);

        string memory policyRegistryJson =
            vm.serializeAddress("PolicyRegistry", "contractAddress", registries.walletPolicyRegistry);
        policyRegistryJson =
            vm.serializeAddress("PolicyRegistry", "beaconAddress", registries.walletPolicyRegistryBeacon);
        policyRegistryJson =
            vm.serializeAddress("PolicyRegistry", "implementationAddress", registries.walletPolicyRegistryImpl);

        string memory walletFactoryJson =
            vm.serializeAddress("WalletFactory", "contractAddress", registries.walletFactory);
        walletFactoryJson = vm.serializeAddress("WalletFactory", "beaconAddress", registries.walletFactoryBeacon);

        string memory registriesJson = vm.serializeString("registries", "BondRegistry", bondRegistryJson);
        registriesJson = vm.serializeString("registries", "EntityRegistry", entityRegistryJson);
        registriesJson = vm.serializeString("registries", "PolicyRegistry", policyRegistryJson);
        registriesJson = vm.serializeString("registries", "WalletFactory", walletFactoryJson);
        return registriesJson;
    }

    /**
     * @notice Serialize governance contracts to JSON
     * @param governance Governance addresses
     * @return JSON string for governance contracts
     */
    function _serializeGovernance(Governance memory governance) internal returns (string memory) {
        string memory timelockControllerJson =
            vm.serializeAddress("TimelockController", "contractAddress", governance.timelockController);
        timelockControllerJson =
            vm.serializeAddress("TimelockController", "beaconAddress", governance.timelockControllerBeacon);
        timelockControllerJson =
            vm.serializeAddress("TimelockController", "implementationAddress", governance.timelockControllerImpl);

        return vm.serializeString("governance", "TimelockController", timelockControllerJson);
    }

    function _serializeWallet(CompanyWallet memory wallet) internal returns (string memory) {
        string memory cwJson = vm.serializeAddress("CompanyWallet", "beaconAddress", wallet.companyWalletBeacon);
        cwJson = vm.serializeAddress("CompanyWallet", "implementationAddress", wallet.companyWalletImpl);
        return vm.serializeString("wallet", "CompanyWallet", cwJson);
    }

    /**
     * @notice Serialize token contract to JSON
     * @param token Token addresses
     * @return JSON string for token contracts
     */
    function _serializeToken(MultiToken memory token) internal returns (string memory) {
        string memory multiTokenJson = vm.serializeAddress("deussToken", "contractAddress", token.deussToken);
        multiTokenJson = vm.serializeAddress("deussToken", "beaconAddress", token.deussTokenBeacon);
        multiTokenJson = vm.serializeAddress("deussToken", "implementationAddress", token.deussTokenImpl);
        return vm.serializeString("token", "deussToken", multiTokenJson);
    }

    function _serializeUtils(UtilsContracts memory utils) internal returns (string memory) {
        string memory multicallJson = vm.serializeAddress("Multicall3", "contractAddress", utils.multicall);
        string memory lensJson = vm.serializeAddress("MarketplaceLens", "contractAddress", utils.marketplaceLens);
        lensJson = vm.serializeAddress("MarketplaceLens", "beaconAddress", utils.marketplaceLensBeacon);
        lensJson = vm.serializeAddress("MarketplaceLens", "implementationAddress", utils.marketplaceLensImpl);
        vm.serializeString("utils", "Multicall3", multicallJson);
        return vm.serializeString("utils", "MarketplaceLens", lensJson);
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

    /*//////////////////////////////////////////////////////////////
                          CREATE2 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _prepareByteCode(bytes32 saltBytes, bytes memory creationCode, bytes memory initData)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(saltBytes, creationCode, initData);
    }

    function _computeCreate2Address(bytes32 saltBytes, bytes memory initCode) internal pure returns (address) {
        return address(
            uint160(
                uint256(keccak256(abi.encodePacked(hex"ff", Constants.CREATE2_PROXY, saltBytes, keccak256(initCode))))
            )
        );
    }
}
