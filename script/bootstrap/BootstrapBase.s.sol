// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {console2} from "forge-std/Script.sol";
import {DeployProtocol} from "script/deploy/DeployProtocol.s.sol";
import {DeployConstants as Constants} from "../DeployConstants.sol";
import {Suite, CoreContracts, BootstrapConfig, EBSIContracts, EBSIConfig} from "../DeployTypes.sol";
import {EntityRegistry} from "src/registry/EntityRegistry.sol";
import {BondRegistry} from "src/registry/BondRegistry.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {OrderbookMarketplace} from "src/marketplace/OrderbookMarketplace.sol";
import {EscrowManager} from "src/marketplace/EscrowManager.sol";
import {AssetManager} from "src/marketplace/AssetManager.sol";
import {AssetType} from "src/marketplace/MarketStructs.sol";
import {BondMarketFilter} from "src/marketplace/filters/BondMarketFilter.sol";
import {DeussBondMetadataAdapter} from "src/marketplace/filters/DeussBondMetadataAdapter.sol";
import {DeussBondValidator} from "src/marketplace/validators/DeussBondValidator.sol";
import {IBaseToken} from "src/token/base/IBaseToken.sol";
import {DEUSSToken} from "src/token/fungible/DEUSSToken.sol";
import {AccountStatus, EntityStatus, EntityTypeMeta} from "src/registry/EntityStructs.sol";
import {TimelockController} from "src/governance/TimelockController.sol";
import {IProxyDeployer} from "src/deployer/IProxyDeployer.sol";
import {IWalletFactory} from "src/wallet/IWalletFactory.sol";
import {CompanyWallet} from "src/wallet/CompanyWallet.sol";

// EBSI contracts
import {ProxyFactory} from "ebsi/contract-factory/ProxyFactory.sol";
import {IProxyTemplateRegistry} from "ebsi/contract-factory/interfaces/IProxyTemplateRegistry.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title ITransferOwnable
 * @author DEUSS Team
 * @notice Minimal interface for contracts that support ownership transfer.
 */
interface ITransferOwnable {
    /// @notice Transfers ownership of the contract to `newOwner`.
    /// @param newOwner Address of the new owner
    function transferOwnership(address newOwner) external;
    /// @notice Returns the current owner of the contract.
    /// @return Current owner address
    function owner() external view returns (address);
}

/**
 * @title BootstrapBase
 * @author DEUSS Team
 * @notice Abstract contract containing all idempotent bootstrap logic.
 *         Both BootstrapProtocol and DeployBootstrapHarness inherit from here so the
 *         wiring code lives in exactly one place.
 */
abstract contract BootstrapBase is DeployProtocol {
    /*//////////////////////////////////////////////////////////////
                         BOOTSTRAP ENTRY POINT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Apply all bootstrap steps to the given suite. Safe to rerun.
     *         Loads BootstrapConfig from environment variables.
     * @param suite Deployed contract addresses
     */
    function applyBootstrap(Suite memory suite) public {
        _applyBootstrapWithConfig(suite, _loadBootstrapConfig());
    }

    /**
     * @notice Transfer ownership of all protocol beacons and proxies to the TimelockController.
     * @param suite Deployed suite with all contract addresses
     */
    function transferOwnershipToTimelock(Suite memory suite) public {
        _transferOwnershipToTimelock(suite);
    }

    /**
     * @notice Apply all bootstrap steps using the provided config. Safe to rerun.
     * @param suite Deployed contract addresses
     * @param config Bootstrap configuration (roles, currencies, flags)
     */
    // solhint-disable-next-line function-max-lines
    function _applyBootstrapWithConfig(Suite memory suite, BootstrapConfig memory config) internal {
        console2.log("=== Bootstrap ===");

        _setupTimelockController(payable(suite.governance.timelockController));
        _setupEntityRegistry(
            suite.registries.entityRegistry,
            suite.core.escrowManager,
            suite.governance.timelockController,
            admin,
            config
        );
        _setupBondRegistry(
            suite.registries.bondRegistry,
            suite.multiToken.deussToken,
            admin,
            suite.governance.timelockController,
            config
        );
        _setupAssetManager(suite.core.assetManager, suite.multiToken.deussToken, suite.registries.bondRegistry, admin);
        _setupEscrowManager(suite.core, admin);
        _setupMarketplace(
            suite.registries.entityRegistry,
            suite.core,
            admin,
            suite.governance.timelockController,
            config.allowedCurrencies
        );
        _setupBondMarketFilter(
            suite.core.bondMarketFilter, suite.multiToken.deussToken, suite.registries.bondRegistry, admin
        );
        _setupOrderbookMarketplace(
            suite.registries.entityRegistry, suite.core, admin, suite.governance.timelockController
        );
        _wireWalletFactoryToEBSI(suite.ebsi, suite.registries.walletFactory, suite.wallet.companyWalletBeacon);
        _setupToken(suite.multiToken.deussToken, suite.governance.timelockController, config.unpauseToken);
        console2.log("=== Bootstrap complete ===");
    }

    /**
     * @notice Grant PROPOSER and EXECUTOR roles to timelockControllerActor.
     * @param timelockController Address of the TimelockController proxy
     */
    function _setupTimelockController(address payable timelockController) internal {
        vm.startBroadcast(_activeNetworkConfig.timelockControllerAdminKey);
        TimelockController(timelockController)
            .grantRole(TimelockController(timelockController).PROPOSER_ROLE(), timelockControllerActor);
        TimelockController(timelockController)
            .grantRole(TimelockController(timelockController).EXECUTOR_ROLE(), timelockControllerActor);
        TimelockController(timelockController)
            .grantRole(TimelockController(timelockController).CANCELLER_ROLE(), timelockControllerActor);
        vm.stopBroadcast();
    }

    /**
     * @notice Grant all EntityRegistry roles to admin and define required entity types.
     * @param entityRegistry Address of the EntityRegistry proxy
     * @param escrowManager Address of the EscrowManager (used for escrow entity registration)
     * @param timelockController Address of the TimelockController (used for governance entity registration)
     * @param admin Address that receives all EntityRegistry roles
     * @param config Bootstrap configuration (entity type names, caps, escrow entity flag)
     */
    function _setupEntityRegistry(
        address entityRegistry,
        address escrowManager,
        address timelockController,
        address admin,
        BootstrapConfig memory config
    ) internal {
        EntityRegistry er = EntityRegistry(entityRegistry);
        uint256 allRoles =
            er.ADMIN_ROLE() | er.ENTITY_TYPE_MANAGER() | er.ONBOARDING() | er.GUARD() | er.WALLET_TRANSFER();

        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        er.grantRoles(admin, allRoles);
        vm.stopBroadcast();
        vm.startBroadcast(_activeNetworkConfig.adminKey);
        _defineEntityTypeIfMissing(er, Constants.COMPANY_ENTITY, config.companyEntityName, config.companyEntityCaps);
        _defineEntityTypeIfMissing(er, Constants.DEUSS_PROTOCOL_ENTITY, bytes32("DEUSS_PROTOCOL"), 0);
        vm.stopBroadcast();

        if (config.registerEscrowEntity) {
            _ensureProtocolEntityAccount(entityRegistry, escrowManager, "escrow-entity");
        }
        _ensureProtocolEntityAccount(entityRegistry, timelockController, "timelock-entity");
    }

    /**
     * @notice Grant BondRegistry roles, set the multi-token, and allowlist currencies.
     * @param bondRegistry Address of the BondRegistry proxy
     * @param token Address of the fungible token
     * @param actor Address that receives all operational BondRegistry roles
     * @param timelockController Address that receives the critical issuer recovery role
     * @param config Bootstrap configuration (allowed currencies)
     */
    function _setupBondRegistry(
        address bondRegistry,
        address token,
        address actor,
        address timelockController,
        BootstrapConfig memory config
    ) internal {
        BondRegistry br = BondRegistry(bondRegistry);

        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        br.grantRoles(
            actor,
            br.PUBLISHER() | br.CANCEL() | br.CLOSE() | br.CURRENCY() | br.SUSPEND() | br.UNSUSPEND() | br.SCORING()
        );
        br.grantRoles(timelockController, br.ISSUER_RECOVERY());

        if (br.getToken() == address(0)) {
            br.setMultiToken(token);
        }
        vm.stopBroadcast();

        vm.startBroadcast(_activeNetworkConfig.adminKey);
        for (uint256 i; i < config.allowedCurrencies.length; ++i) {
            br.setAllowedCurrency(config.allowedCurrencies[i], true);
        }
        vm.stopBroadcast();
    }

    /**
     * @notice Wire WalletFactory to EBSI infrastructure (template registry, proxy factory, DID).
     *         Idempotent — skips steps that are already configured.
     * @param ebsi EBSI contract addresses
     * @param walletFactory Address of the WalletFactory proxy
     * @param beaconCW Address of the CompanyWallet UpgradeableBeacon
     */
    function _wireWalletFactoryToEBSI(EBSIContracts memory ebsi, address walletFactory, address beaconCW) internal {
        EBSIConfig memory config = ebsiInfrastructure.getEBSIConfig();
        bool proxyDeployerConfigured = _isWalletFactoryProxyDeployerConfigured(walletFactory, ebsi, config);
        bool walletTemplateConfigured = _isCompanyWalletTemplateConfigured(walletFactory);

        if (proxyDeployerConfigured && walletTemplateConfigured) {
            console2.log(" - WalletFactory ready");
            console2.log("=== WalletFactory wired ===");
            return;
        }

        vm.startBroadcast(_activeNetworkConfig.deployerKey);

        // Step 1: Register CompanyWallet template in ProxyTemplateRegistry
        bytes32 cwTemplateId = IProxyTemplateRegistry(ebsi.proxyTemplateRegistry)
            .computeTemplateId(Constants.COMPANY_WALLET_TEMPLATE_NAME, Constants.COMPANY_WALLET_TEMPLATE_VERSION);
        bytes32 ebsiAdminRole = keccak256("EBSI_ADMIN_ROLE");
        address deployer = vm.addr(_activeNetworkConfig.deployerKey);
        if (
            !IProxyTemplateRegistry(ebsi.proxyTemplateRegistry).getTemplate(cwTemplateId).isActive
                && IAccessControl(ebsi.proxyTemplateRegistry).hasRole(ebsiAdminRole, deployer)
        ) {
            IProxyTemplateRegistry.ProxyTemplate memory cwTemplate = _createTemplate(
                Constants.COMPANY_WALLET_TEMPLATE_NAME,
                Constants.COMPANY_WALLET_TEMPLATE_VERSION,
                beaconCW,
                CompanyWallet.initialize.selector,
                Constants.REPO_URI,
                Constants.AUDIT_URI_CW,
                type(CompanyWallet).creationCode
            );
            IProxyTemplateRegistry(ebsi.proxyTemplateRegistry).addTemplate(cwTemplate);
        }

        // Step 2: Grant TRUSTED_ISSUER_ROLE to WalletFactory
        bytes32 trustedIssuerRole = ProxyFactory(ebsi.proxyFactory).TRUSTED_ISSUER_ROLE();
        ProxyFactory(ebsi.proxyFactory).grantRole(trustedIssuerRole, walletFactory);

        // Step 3: Configure WalletFactory's ProxyDeployer
        if (IProxyDeployer(walletFactory).getFactory() != ebsi.proxyFactory) {
            IProxyDeployer(walletFactory).setFactory(ebsi.proxyFactory);
        }

        if (IProxyDeployer(walletFactory).getRegistry() != ebsi.proxyTemplateRegistry) {
            IProxyDeployer(walletFactory).setRegistry(ebsi.proxyTemplateRegistry);
        }

        if (keccak256(bytes(IProxyDeployer(walletFactory).getDid())) != keccak256(bytes(config.entityRegistryDID))) {
            IProxyDeployer(walletFactory).setDid(config.entityRegistryDID);
        }

        // Step 4: Register company wallet template in WalletFactory
        IWalletFactory(walletFactory)
            .setWalletTemplateForType(
                Constants.COMPANY_WALLET_TYPE,
                Constants.COMPANY_WALLET_TEMPLATE_NAME,
                Constants.COMPANY_WALLET_TEMPLATE_VERSION
            );

        vm.stopBroadcast();
    }

    /**
     * @notice Grant ADMIN role to actor and register the fungible token as an ERC-6909 asset.
     * @param assetManager Address of the AssetManager proxy
     * @param token Address of the fungible token
     * @param bondRegistry Address of the BondRegistry proxy (read by the validator)
     * @param actor Address that receives the ADMIN role
     */
    function _setupAssetManager(address assetManager, address token, address bondRegistry, address actor) internal {
        AssetManager am = AssetManager(assetManager);

        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        am.grantRoles(actor, am.ADMIN());
        vm.stopBroadcast();

        vm.startBroadcast(_activeNetworkConfig.adminKey);
        am.setAsset(token, AssetType.ERC6909, true, false);
        if (am.getAssetValidator(token) == address(0)) {
            DeussBondValidator validator = new DeussBondValidator(bondRegistry);
            am.setAssetValidator(token, address(validator));
        }
        vm.stopBroadcast();
    }

    /**
     * @notice Grant ADMIN role to actor and register Marketplace and OrderbookMarketplace modules.
     * @param core Core contract addresses
     * @param actor Address that receives the ADMIN role
     */
    function _setupEscrowManager(CoreContracts memory core, address actor) internal {
        EscrowManager em = EscrowManager(core.escrowManager);

        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        em.grantRoles(actor, em.ADMIN());
        vm.stopBroadcast();

        vm.startBroadcast(_activeNetworkConfig.adminKey);
        if (!em.isAuthorizedModule(em.MARKETPLACE_MODULE(), core.marketplace)) {
            em.registerModule(em.MARKETPLACE_MODULE(), core.marketplace);
        }
        if (!em.isAuthorizedModule(em.ORDERBOOK_MARKETPLACE_MODULE(), core.orderbookMarketplace)) {
            em.registerModule(em.ORDERBOOK_MARKETPLACE_MODULE(), core.orderbookMarketplace);
        }
        if (em.assetManager() == address(0)) {
            em.setAssetManager(core.assetManager);
        }
        vm.stopBroadcast();
    }

    /**
     * @notice Grant roles to actor, wire dependencies, and allowlist currencies in Marketplace.
     * @param entityRegistry Address of the EntityRegistry proxy
     * @param core Core contract addresses
     * @param actor Address that receives ADMIN | PAYMENT_HANDLER | ARBITRATOR | FREEZE_ROLE | INTEREST_DISCOVERY_OPERATOR
     * @param seizureActor Address that receives SEIZURE_ROLE
     * @param currencies Currency codes to allowlist (e.g. ["EUR"])
     */
    function _setupMarketplace(
        address entityRegistry,
        CoreContracts memory core,
        address actor,
        address seizureActor,
        string[] memory currencies
    ) internal {
        Marketplace marketplace = Marketplace(core.marketplace);

        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        marketplace.grantRoles(
            actor,
            marketplace.ADMIN() | marketplace.PAYMENT_HANDLER() | marketplace.ARBITRATOR() | marketplace.FREEZE_ROLE()
                | marketplace.INTEREST_DISCOVERY_OPERATOR()
        );
        marketplace.grantRoles(seizureActor, marketplace.SEIZURE_ROLE());
        vm.stopBroadcast();

        vm.startBroadcast(_activeNetworkConfig.adminKey);
        marketplace.setAssetManager(core.assetManager);
        if (marketplace.getEscrowManager() == address(0)) {
            marketplace.setEscrowManager(core.escrowManager);
        }
        if (marketplace.getEntityRegistry() == address(0)) {
            marketplace.setEntityRegistry(entityRegistry);
        }
        for (uint256 i; i < currencies.length; ++i) {
            bytes3 currency3 = _toBytes3(currencies[i]);
            if (!marketplace.isCurrencyAllowed(currency3)) {
                marketplace.addCurrency(currency3);
            }
        }
        marketplace.setAllowedEntityType(Constants.COMPANY_ENTITY, true);
        vm.stopBroadcast();
    }

    /**
     * @notice Grant ADMIN role to actor and register the DEUSS metadata adapter for the fungible token.
     * @param bondMarketFilter Address of the BondMarketFilter proxy
     * @param token Address of the fungible token
     * @param bondRegistry Address of the BondRegistry proxy (forwarded to the DEUSS metadata adapter)
     * @param actor Address that receives the ADMIN role
     */
    function _setupBondMarketFilter(address bondMarketFilter, address token, address bondRegistry, address actor)
        internal
    {
        BondMarketFilter bmf = BondMarketFilter(bondMarketFilter);

        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        bmf.grantRoles(actor, bmf.ADMIN());
        vm.stopBroadcast();

        vm.startBroadcast(_activeNetworkConfig.adminKey);
        if (bmf.adapter(token) == address(0)) {
            DeussBondMetadataAdapter deussAdapter = new DeussBondMetadataAdapter(bondRegistry);
            bmf.setAdapter(token, address(deussAdapter));
        }
        vm.stopBroadcast();
    }

    /**
     * @notice Grant roles to actor and wire AssetManager, EntityRegistry, and EscrowManager dependencies.
     * @param entityRegistry Address of the EntityRegistry proxy
     * @param core Core contract addresses
     * @param actor Address that receives ADMIN | PAYMENT_HANDLER | ARBITRATOR | FREEZE_ROLE
     * @param seizureActor Address that receives SEIZURE_ROLE
     */
    function _setupOrderbookMarketplace(
        address entityRegistry,
        CoreContracts memory core,
        address actor,
        address seizureActor
    ) internal {
        OrderbookMarketplace ob = OrderbookMarketplace(core.orderbookMarketplace);

        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        ob.grantRoles(actor, ob.ADMIN() | ob.PAYMENT_HANDLER() | ob.ARBITRATOR() | ob.FREEZE_ROLE());
        ob.grantRoles(seizureActor, ob.SEIZURE_ROLE());
        vm.stopBroadcast();

        vm.startBroadcast(_activeNetworkConfig.adminKey);
        if (ob.assetManager() == address(0)) {
            ob.setAssetManager(core.assetManager);
        }
        if (ob.entityRegistry() == address(0)) {
            ob.setEntityRegistry(entityRegistry);
        }
        if (ob.escrowManager() == address(0)) {
            ob.setEscrowManager(core.escrowManager);
        }
        vm.stopBroadcast();
    }

    /**
     * @notice Optionally unpause the token after deployment.
     * @param token Address of the fungible token proxy
     * @param forceTransferActor Address that receives FORCE_TRANSFER_ROLE
     * @param unpauseToken Whether to unpause the token
     */
    function _setupToken(address token, address forceTransferActor, bool unpauseToken) internal {
        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        DEUSSToken(token).grantRoles(forceTransferActor, DEUSSToken(token).FORCE_TRANSFER_ROLE());
        if (unpauseToken && IBaseToken(token).paused()) {
            IBaseToken(token).unpause();
        }
        vm.stopBroadcast();
    }

    /**
     * @notice Register and enable an entity/account for a protocol component if not already present.
     * @param entityRegistry Address of the EntityRegistry proxy
     * @param account Protocol account to register and enable
     * @param seed Domain separator for the deterministic entity ID
     */
    function _ensureProtocolEntityAccount(address entityRegistry, address account, string memory seed) internal {
        EntityRegistry er = EntityRegistry(entityRegistry);
        bytes32 entityId = keccak256(abi.encodePacked(account, seed));
        bool entityExists;
        bool accountLinked;
        EntityStatus status;

        vm.startBroadcast(_activeNetworkConfig.adminKey);
        try er.getEntityStatus(entityId) returns (EntityStatus currentStatus) {
            entityExists = true;
            status = currentStatus;
        } catch {
            entityExists = false;
        }

        if (!entityExists) {
            er.registerEntity(entityId, Constants.DEUSS_PROTOCOL_ENTITY, "");
        }

        if (!entityExists || status != EntityStatus.ENABLED) {
            er.setEntityStatus(entityId, EntityStatus.ENABLED, "");
        }

        if (er.doesAccountExist(account)) {
            accountLinked = er.getEntityId(account) == entityId;
        }

        if (!accountLinked) {
            er.registerAccount(account, entityId, 0);
        } else if (!er.isAccountEnabled(account)) {
            er.setAccountStatus(account, AccountStatus.ENABLED, "");
        }
        vm.stopBroadcast();
    }

    /**
     * @notice Transfer beacon and proxy ownership of all protocol contracts (excluding EBSI) to the TimelockController.
     * @param suite Deployed suite with all contract addresses
     */
    function _transferOwnershipToTimelock(Suite memory suite) internal {
        address tc = timelockController;

        vm.startBroadcast(_activeNetworkConfig.deployerKey);

        // Beacons
        _transferBeaconOwnership(suite.registries.bondRegistryBeacon, tc);
        _transferBeaconOwnership(suite.registries.entityRegistryBeacon, tc);
        _transferBeaconOwnership(suite.registries.walletPolicyRegistryBeacon, tc);
        _transferBeaconOwnership(suite.registries.walletFactoryBeacon, tc);
        _transferBeaconOwnership(suite.core.assetManagerBeacon, tc);
        _transferBeaconOwnership(suite.core.marketplaceBeacon, tc);
        _transferBeaconOwnership(suite.core.escrowManagerBeacon, tc);
        _transferBeaconOwnership(suite.core.orderbookMarketplaceBeacon, tc);
        _transferBeaconOwnership(suite.core.bondMarketFilterBeacon, tc);
        _transferBeaconOwnership(suite.multiToken.deussTokenBeacon, tc);
        _transferBeaconOwnership(suite.wallet.companyWalletBeacon, tc);
        _transferBeaconOwnership(suite.utils.marketplaceLensBeacon, tc);

        // Proxy contracts
        _transferContractOwnership(suite.registries.bondRegistry, tc);
        _transferContractOwnership(suite.registries.entityRegistry, tc);
        _transferContractOwnership(suite.registries.walletPolicyRegistry, tc);
        _transferContractOwnership(suite.registries.walletFactory, tc);
        _transferContractOwnership(suite.core.assetManager, tc);
        _transferContractOwnership(suite.core.marketplace, tc);
        _transferContractOwnership(suite.core.escrowManager, tc);
        _transferContractOwnership(suite.core.orderbookMarketplace, tc);
        _transferContractOwnership(suite.core.bondMarketFilter, tc);
        _transferContractOwnership(suite.multiToken.deussToken, tc);
        _transferContractOwnership(suite.utils.marketplaceLens, tc);

        vm.stopBroadcast();
    }

    /**
     * @notice Define an entity type only if it does not already exist.
     * @param er EntityRegistry instance
     * @param typeId Numeric type identifier
     * @param name Human-readable type name
     * @param caps Capability bitmask for the entity type
     */
    function _defineEntityTypeIfMissing(EntityRegistry er, uint256 typeId, bytes32 name, uint256 caps) internal {
        try er.getEntityTypeMeta(typeId) returns (EntityTypeMeta memory) {
            return;
        } catch {
            er.defineEntityType(typeId, name, caps);
        }
    }

    /**
     * @notice Schedule and execute a grantRoles call via the TimelockController.
     * @param target Contract to call grantRoles on
     * @param user Address to receive the roles
     * @param roles Role bitmask to grant
     */
    function _grantRoles(address target, address user, uint256 roles) internal {
        bytes memory data = abi.encodeWithSignature("grantRoles(address,uint256)", user, roles);

        vm.startBroadcast(_activeNetworkConfig.timelockControllerAdminKey);
        TimelockController(timelockController)
            .schedule(
                target,
                0,
                data,
                bytes32(0),
                Constants.TIMELOCK_CONTROLLER_OP_SALT,
                Constants.TIMELOCK_CONTROLLER_MIN_DELAY
            );
        vm.stopBroadcast();

        vm.warp(block.timestamp + Constants.TIMELOCK_CONTROLLER_MIN_DELAY);

        vm.startBroadcast(_activeNetworkConfig.timelockControllerAdminKey);
        TimelockController(timelockController)
            .execute(target, 0, data, bytes32(0), Constants.TIMELOCK_CONTROLLER_OP_SALT);
        vm.stopBroadcast();
    }

    /**
     * @notice Load bootstrap configuration from environment variables, applying defaults where absent.
     * @return config Populated BootstrapConfig struct
     */
    function _loadBootstrapConfig() internal view virtual returns (BootstrapConfig memory config) {
        string[] memory defaultCurrencies = new string[](1);
        defaultCurrencies[0] = "EUR";

        config.unpauseToken = vm.envOr("BOOTSTRAP_UNPAUSE_TOKEN", true);
        config.allowedCurrencies = vm.envOr("BOOTSTRAP_ALLOWED_CURRENCIES", ",", defaultCurrencies);
        config.registerEscrowEntity = vm.envOr("BOOTSTRAP_REGISTER_ESCROW_ENTITY", true);

        string memory entityName = vm.envOr("BOOTSTRAP_COMPANY_ENTITY_NAME", string("COMPANY"));
        config.companyEntityName = bytes32(bytes(entityName));
        config.companyEntityCaps = vm.envOr("BOOTSTRAP_COMPANY_ENTITY_CAPS", uint256(0));
    }

    /**
     * @notice Convert the first 3 characters of a string to bytes3.
     * @param s Input string (must be at least 3 characters)
     * @return result bytes3 representation of the first 3 characters
     */
    function _toBytes3(string memory s) internal pure returns (bytes3 result) {
        bytes memory b = bytes(s);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            result := mload(add(b, 32))
        }
    }

    /**
     * @notice Transfer ownership of a proxy contract to `newOwner` if not already set.
     * @param target Address of the ownable proxy contract
     * @param newOwner Address to transfer ownership to
     */
    function _transferContractOwnership(address target, address newOwner) private {
        if (ITransferOwnable(target).owner() != newOwner) {
            ITransferOwnable(target).transferOwnership(newOwner);
        }
    }

    /**
     * @notice Transfer ownership of an UpgradeableBeacon to `newOwner` if not already set.
     * @param beacon Address of the UpgradeableBeacon
     * @param newOwner Address to transfer ownership to
     */
    function _transferBeaconOwnership(address beacon, address newOwner) private {
        if (UpgradeableBeacon(beacon).owner() != newOwner) {
            UpgradeableBeacon(beacon).transferOwnership(newOwner);
        }
    }

    /**
     * @notice Return whether WalletFactory already has the expected proxy-deployer configuration.
     * @param walletFactory Address of WalletFactory
     * @param ebsi EBSI contracts struct
     * @param config EBSI configuration
     * @return configured True when factory, registry, and DID already match
     */
    function _isWalletFactoryProxyDeployerConfigured(
        address walletFactory,
        EBSIContracts memory ebsi,
        EBSIConfig memory config
    ) private view returns (bool configured) {
        IProxyDeployer proxyDeployer = IProxyDeployer(walletFactory);
        return proxyDeployer.getFactory() == ebsi.proxyFactory
            && proxyDeployer.getRegistry() == ebsi.proxyTemplateRegistry
            && keccak256(bytes(proxyDeployer.getDid())) == keccak256(bytes(config.entityRegistryDID));
    }

    /**
     * @notice Return whether WalletFactory already maps COMPANY_WALLET_TYPE to the expected template.
     * @param walletFactory Address of WalletFactory
     * @return configured True when the template mapping matches the expected company wallet template
     */
    function _isCompanyWalletTemplateConfigured(address walletFactory) private view returns (bool configured) {
        bytes32 configuredTemplateId =
            IWalletFactory(walletFactory).getWalletTemplateIdForType(Constants.COMPANY_WALLET_TYPE);
        bytes32 expectedTemplateId =
            keccak256(abi.encode(Constants.COMPANY_WALLET_TEMPLATE_NAME, Constants.COMPANY_WALLET_TEMPLATE_VERSION));
        return configuredTemplateId == expectedTemplateId;
    }

    /**
     * @notice Return whether WalletFactory already holds the TRUSTED_ISSUER_ROLE.
     * @param proxyFactory Address of ProxyFactory
     * @param account Account to inspect
     * @return hasRole True when the account already has the role
     */
    function _hasTrustedIssuerRole(address proxyFactory, address account) private view returns (bool hasRole) {
        ProxyFactory factory = ProxyFactory(proxyFactory);
        return factory.hasRole(factory.TRUSTED_ISSUER_ROLE(), account);
    }

    /**
     * @notice Create a ProxyTemplate struct
     * @param name Template name
     * @param version Template version
     * @param beaconAddress Beacon contract address
     * @param initSelector Initialization function selector
     * @param repoURI Repository URI
     * @param auditURI Audit report URI
     * @param creationCode Contract creation code for hash
     * @return ProxyTemplate struct
     */
    function _createTemplate(
        string memory name,
        string memory version,
        address beaconAddress,
        bytes4 initSelector,
        string memory repoURI,
        string memory auditURI,
        bytes memory creationCode
    ) private pure returns (IProxyTemplateRegistry.ProxyTemplate memory) {
        return IProxyTemplateRegistry.ProxyTemplate({
            name: name,
            version: version,
            beaconAddress: beaconAddress,
            repoURI: repoURI,
            auditURI: auditURI,
            contractHash: keccak256(creationCode),
            initSelector: initSelector,
            storageLayoutHash: keccak256(abi.encodePacked(name, "_STORAGE_LAYOUT_", version)),
            isActive: true
        });
    }
}
