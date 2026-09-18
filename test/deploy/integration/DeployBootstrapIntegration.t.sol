// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DeployBootstrapHarness} from "test/mocks/DeployBootstrapHarness.t.sol";
import {CoreContracts, Suite} from "script/DeployTypes.sol";
import {DeployConstants as Constants} from "script/DeployConstants.sol";
// Contracts
import {BondRegistry} from "src/registry/BondRegistry.sol";
import {EntityRegistry} from "src/registry/EntityRegistry.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {MarketplaceStorage} from "src/marketplace/MarketplaceStorage.sol";
import {OrderbookMarketplace} from "src/marketplace/OrderbookMarketplace.sol";
import {EscrowManager} from "src/marketplace/EscrowManager.sol";
import {AssetManager} from "src/marketplace/AssetManager.sol";
import {BondMarketFilter} from "src/marketplace/filters/BondMarketFilter.sol";
import {MarketplaceLens} from "src/marketplace/lens/MarketplaceLens.sol";
import {AssetType} from "src/marketplace/MarketStructs.sol";
import {IBaseToken} from "src/token/base/IBaseToken.sol";
import {DEUSSToken} from "src/token/fungible/DEUSSToken.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";
import {EntityTypeMeta} from "src/registry/EntityStructs.sol";
import {TimelockController} from "src/governance/TimelockController.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title DeployBootstrapIntegrationTest
 * @notice Integration tests covering the deploy → bootstrap operator path.
 */
contract DeployBootstrapIntegrationTest is Test {
    uint256 private constant _MARKETPLACE_ASSET_MANAGER_SLOT =
        0xf7a56b15168bcb08515667a141d475c0860a6405d548a81fdf3dd5a1c8926a07;

    DeployBootstrapHarness internal _harness;

    function setUp() public {
        _harness = new DeployBootstrapHarness();
    }

    /*//////////////////////////////////////////////////////////////
                     STAGE 1 — DEPLOY ONLY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice After DeployProtocol, every contract address must be non-zero.
     */
    function test_deploy_allContractAddressesAreNonZero() public {
        Suite memory suite = _harness.deployOnly();

        // Registries
        assertTrue(suite.registries.bondRegistry != address(0), "bondRegistry");
        assertTrue(suite.registries.entityRegistry != address(0), "entityRegistry");
        assertTrue(suite.registries.walletPolicyRegistry != address(0), "walletPolicyRegistry");
        assertTrue(suite.registries.walletFactory != address(0), "walletFactory");
        // Core
        assertTrue(suite.core.assetManager != address(0), "assetManager");
        assertTrue(suite.core.marketplace != address(0), "marketplace");
        assertTrue(suite.core.orderbookMarketplace != address(0), "orderbookMarketplace");
        assertTrue(suite.core.escrowManager != address(0), "escrowManager");
        // Token
        assertTrue(suite.multiToken.deussToken != address(0), "deussToken");
        // Utils
        assertTrue(suite.utils.marketplaceLens != address(0), "marketplaceLens");
        assertTrue(suite.utils.marketplaceLensBeacon != address(0), "marketplaceLensBeacon");
        assertTrue(suite.utils.marketplaceLensImpl != address(0), "marketplaceLensImpl");
    }

    /**
     * @notice After DeployProtocol, core modules must have only required initialization dependencies wired.
     *         BootstrapProtocol fills the remaining address(0) placeholders.
     */
    function test_deploy_coreModulesHaveExpectedInitialWiring() public {
        Suite memory suite = _harness.deployOnly();

        // Marketplace: assetManager and EntityRegistry are pre-set; escrowManager is wired during bootstrap.
        assertEq(Marketplace(suite.core.marketplace).getEscrowManager(), address(0), "Marketplace.escrowManager");
        assertEq(
            Marketplace(suite.core.marketplace).getEntityRegistry(),
            suite.registries.entityRegistry,
            "Marketplace.entityRegistry"
        );

        // OrderbookMarketplace: all three deps are zero
        assertEq(OrderbookMarketplace(suite.core.orderbookMarketplace).assetManager(), address(0), "OB.assetManager");
        assertEq(
            OrderbookMarketplace(suite.core.orderbookMarketplace).entityRegistry(), address(0), "OB.entityRegistry"
        );
        assertEq(OrderbookMarketplace(suite.core.orderbookMarketplace).escrowManager(), address(0), "OB.escrowManager");

        // EscrowManager: assetManager is zero, no modules authorised
        assertEq(EscrowManager(suite.core.escrowManager).assetManager(), address(0), "EM.assetManager");
        assertFalse(
            EscrowManager(suite.core.escrowManager)
                .isAuthorizedModule(
                    EscrowManager(suite.core.escrowManager).MARKETPLACE_MODULE(), suite.core.marketplace
                ),
            "EM.Marketplace not authorised"
        );

        // Token is not yet registered in BondRegistry
        assertEq(BondRegistry(suite.registries.bondRegistry).getToken(), address(0), "BR.token");

        // Token starts paused
        assertTrue(IBaseToken(suite.multiToken.deussToken).paused(), "token.paused");
        assertTrue(
            IDEUSSToken(suite.multiToken.deussToken).isAddressProtected(suite.core.escrowManager),
            "token.escrow protected"
        );
    }

    function test_deploy_marketplaceTimingDefaultsUseProductionConstants() public {
        Suite memory suite = _harness.deployOnly();

        MarketplaceStorage.Config memory marketplaceConfig = _marketplaceConfig(Marketplace(suite.core.marketplace));
        OrderbookMarketplace orderbook = OrderbookMarketplace(suite.core.orderbookMarketplace);

        assertEq(
            marketplaceConfig.marketplacePaymentExpiryThreshold,
            Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_MARKETPLACE_MODE,
            "Marketplace.paymentExpiry"
        );
        assertEq(
            marketplaceConfig.redemptionPaymentExpiryThreshold,
            Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_REDEMPTION_MODE,
            "MP.redemptionExpiry"
        );
        assertEq(
            marketplaceConfig.interestDiscoveryPaymentExpiryThreshold,
            Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_INTEREST_DISCOVERY_MODE,
            "MP.interestExpiry"
        );
        assertEq(
            marketplaceConfig.offerExpiryThreshold,
            Constants.MARKETPLACE_OFFER_EXPIRY_THRESHOLD,
            "Marketplace.offerExpiry"
        );
        assertEq(
            marketplaceConfig.disputeBufferPeriod,
            Constants.MARKETPLACE_DISPUTE_BUFFER_PERIOD,
            "Marketplace.disputeBuffer"
        );
        assertEq(orderbook.paymentExpiryThreshold(), Constants.ORDERBOOK_PAYMENT_EXPIRY_THRESHOLD, "OB.paymentExpiry");
        assertEq(orderbook.minExpiryThreshold(), Constants.ORDERBOOK_MIN_EXPIRY_THRESHOLD, "OB.minExpiry");
        assertEq(orderbook.MIN_ORDER_EXPIRY_THRESHOLD(), 30 minutes, "OB.minBound");
        assertEq(orderbook.disputeBufferPeriod(), Constants.ORDERBOOK_DISPUTE_BUFFER_PERIOD, "OB.disputeBuffer");
    }

    /*//////////////////////////////////////////////////////////////
                   STAGE 2 — BOOTSTRAP: CORE WIRING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice After BootstrapProtocol, every core cross-dependency must be wired.
     */
    function test_bootstrap_coreModulesAreFullyWired() public {
        Suite memory suite = _harness.deployOnly();
        _harness.applyBootstrap(suite);

        // Marketplace
        assertEq(_marketplaceAssetManager(suite.core.marketplace), suite.core.assetManager, "Marketplace.assetManager");
        assertEq(
            Marketplace(suite.core.marketplace).getEscrowManager(),
            suite.core.escrowManager,
            "Marketplace.escrowManager"
        );
        assertEq(
            Marketplace(suite.core.marketplace).getEntityRegistry(),
            suite.registries.entityRegistry,
            "Marketplace.entityRegistry"
        );

        // OrderbookMarketplace
        assertEq(
            OrderbookMarketplace(suite.core.orderbookMarketplace).assetManager(),
            suite.core.assetManager,
            "OB.assetManager"
        );
        assertEq(
            OrderbookMarketplace(suite.core.orderbookMarketplace).entityRegistry(),
            suite.registries.entityRegistry,
            "OB.entityRegistry"
        );
        assertEq(
            OrderbookMarketplace(suite.core.orderbookMarketplace).escrowManager(),
            suite.core.escrowManager,
            "OB.escrowManager"
        );

        // EscrowManager
        assertEq(EscrowManager(suite.core.escrowManager).assetManager(), suite.core.assetManager, "EM.assetManager");
        assertTrue(
            EscrowManager(suite.core.escrowManager)
                .isAuthorizedModule(
                    EscrowManager(suite.core.escrowManager).MARKETPLACE_MODULE(), suite.core.marketplace
                ),
            "EM.Marketplace authorised"
        );
        assertTrue(
            EscrowManager(suite.core.escrowManager)
                .isAuthorizedModule(
                    EscrowManager(suite.core.escrowManager).ORDERBOOK_MARKETPLACE_MODULE(),
                    suite.core.orderbookMarketplace
                ),
            "EM.OB authorised"
        );
    }

    function _marketplaceConfig(Marketplace marketplace)
        internal
        view
        returns (MarketplaceStorage.Config memory config)
    {
        (config,) = marketplace.getConfigAndCounters();
    }

    function _marketplaceAssetManager(address marketplace) internal view returns (address assetManager) {
        assetManager = address(uint160(uint256(vm.load(marketplace, bytes32(_MARKETPLACE_ASSET_MANAGER_SLOT)))));
    }

    function test_deploySuite_marketplaceAssetManagersAndDeussAssetConfigAreWiredWithoutFixtureBackfill() public {
        Suite memory suite = _harness.deploySuite();

        assertEq(
            OrderbookMarketplace(suite.core.orderbookMarketplace).assetManager(),
            suite.core.assetManager,
            "OB.assetManager"
        );
        assertEq(EscrowManager(suite.core.escrowManager).assetManager(), suite.core.assetManager, "EM.assetManager");

        (AssetType assetType, bool enabled, bool enforceTokenId) =
            AssetManager(suite.core.assetManager).getAssetConfig(suite.multiToken.deussToken);

        assertEq(uint8(assetType), uint8(AssetType.ERC6909), "assetType");
        assertTrue(enabled, "enabled");
        assertFalse(enforceTokenId, "enforceTokenId");
    }

    /*//////////////////////////////////////////////////////////////
                STAGE 2 — BOOTSTRAP: TOKEN & CURRENCY CONFIG
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice After bootstrap, the token must be registered in BondRegistry and unpaused.
     */
    function test_bootstrap_tokenIsRegisteredAndUnpaused() public {
        Suite memory suite = _harness.deployOnly();
        _harness.applyBootstrap(suite);

        assertEq(BondRegistry(suite.registries.bondRegistry).getToken(), suite.multiToken.deussToken, "BR.token");
        assertFalse(IBaseToken(suite.multiToken.deussToken).paused(), "token.unpaused");
    }

    function test_bootstrap_defaultDeussAssetConfiguration() public {
        Suite memory suite = _harness.deployOnly();
        _harness.applyBootstrap(suite);

        (AssetType assetType, bool enabled, bool enforceTokenId) =
            AssetManager(suite.core.assetManager).getAssetConfig(suite.multiToken.deussToken);

        assertEq(uint8(assetType), uint8(AssetType.ERC6909), "assetType");
        assertTrue(enabled, "enabled");
        assertFalse(enforceTokenId, "enforceTokenId");
        // Tradability is gated by a DeussBondValidator wired during bootstrap.
        assertTrue(
            AssetManager(suite.core.assetManager).getAssetValidator(suite.multiToken.deussToken) != address(0),
            "deuss validator wired"
        );
    }

    /**
     * @notice After bootstrap, EUR must be allowlisted in both BondRegistry and
     *         Marketplace (the default from BootstrapConfig).
     */
    function test_bootstrap_defaultCurrencyIsAllowlisted() public {
        Suite memory suite = _harness.deployOnly();
        _harness.applyBootstrap(suite);

        assertTrue(BondRegistry(suite.registries.bondRegistry).isCurrencyAllowed("EUR"), "BR.EUR allowed");
        assertTrue(Marketplace(suite.core.marketplace).isCurrencyAllowed(bytes3("EUR")), "Marketplace.EUR allowed");
    }

    /**
     * @notice After bootstrap, admin receives operational roles and timelock receives issuer recovery.
     */
    function test_bootstrap_defaultOperationalRolesAreGrantedToAdmin() public {
        Suite memory suite = _harness.deployOnly();
        _harness.applyBootstrap(suite);

        address admin = _harness.admin();
        address deployer = _harness.deployer();
        address timelock = suite.governance.timelockController;

        _assertBondRegistryBootstrapRoles(suite.registries.bondRegistry, admin, deployer, timelock);
        _assertCoreAdminRoles(suite.core, admin, deployer);
        _assertMarketplaceBootstrapRoles(suite.core.marketplace, admin, deployer, timelock);
        _assertOrderbookBootstrapRoles(suite.core.orderbookMarketplace, admin, deployer, timelock);
        _assertTokenBootstrapRoles(suite.multiToken.deussToken, admin, deployer, timelock);
    }

    function _assertBondRegistryBootstrapRoles(address bondRegistry, address admin, address deployer, address timelock)
        private
        view
    {
        BondRegistry br = BondRegistry(bondRegistry);
        uint256 brOperatorRoles =
            br.PUBLISHER() | br.CANCEL() | br.CLOSE() | br.CURRENCY() | br.SUSPEND() | br.UNSUSPEND() | br.SCORING();
        assertTrue(br.hasAllRoles(admin, brOperatorRoles), "admin BR operator roles");
        assertFalse(br.hasAnyRole(admin, br.BURNER()), "admin BR.BURNER");
        assertFalse(br.hasAnyRole(deployer, brOperatorRoles | br.BURNER() | br.ISSUER_RECOVERY()), "deployer BR roles");
        assertFalse(br.hasAnyRole(timelock, br.BURNER()), "timelock BR.BURNER");
        assertTrue(br.hasAnyRole(timelock, br.ISSUER_RECOVERY()), "timelock BR.ISSUER_RECOVERY");
    }

    function _assertCoreAdminRoles(CoreContracts memory core, address admin, address deployer) private view {
        AssetManager assetManager = AssetManager(core.assetManager);
        EscrowManager escrowManager = EscrowManager(core.escrowManager);
        BondMarketFilter bondMarketFilter = BondMarketFilter(core.bondMarketFilter);

        assertTrue(assetManager.hasAllRoles(admin, assetManager.ADMIN()), "admin AssetManager.ADMIN");
        assertFalse(assetManager.hasAnyRole(deployer, assetManager.ADMIN()), "deployer AssetManager.ADMIN");
        assertTrue(escrowManager.hasAllRoles(admin, escrowManager.ADMIN()), "admin EscrowManager.ADMIN");
        assertFalse(escrowManager.hasAnyRole(deployer, escrowManager.ADMIN()), "deployer EscrowManager.ADMIN");
        assertTrue(bondMarketFilter.hasAllRoles(admin, bondMarketFilter.ADMIN()), "admin BondMarketFilter.ADMIN");
        assertFalse(bondMarketFilter.hasAnyRole(deployer, bondMarketFilter.ADMIN()), "deployer BondMarketFilter.ADMIN");
    }

    function _assertMarketplaceBootstrapRoles(
        address marketplaceAddress,
        address admin,
        address deployer,
        address timelock
    ) private view {
        Marketplace marketplace = Marketplace(marketplaceAddress);
        uint256 marketplaceOperatorRoles = marketplace.ADMIN() | marketplace.PAYMENT_HANDLER()
            | marketplace.ARBITRATOR() | marketplace.FREEZE_ROLE() | marketplace.INTEREST_DISCOVERY_OPERATOR();

        assertTrue(marketplace.hasAllRoles(admin, marketplaceOperatorRoles), "admin Marketplace roles");
        assertFalse(marketplace.hasAnyRole(admin, marketplace.SEIZURE_ROLE()), "admin Marketplace.SEIZURE_ROLE");
        assertTrue(marketplace.hasAllRoles(timelock, marketplace.SEIZURE_ROLE()), "tl MP.SEIZURE_ROLE");
        assertFalse(marketplace.hasAnyRole(deployer, marketplaceOperatorRoles), "deployer Marketplace roles");
    }

    function _assertOrderbookBootstrapRoles(address orderbookAddress, address admin, address deployer, address timelock)
        private
        view
    {
        OrderbookMarketplace ob = OrderbookMarketplace(orderbookAddress);
        uint256 orderbookOperatorRoles = ob.ADMIN() | ob.PAYMENT_HANDLER() | ob.ARBITRATOR() | ob.FREEZE_ROLE();

        assertTrue(ob.hasAllRoles(admin, orderbookOperatorRoles), "admin Orderbook roles");
        assertFalse(ob.hasAnyRole(admin, ob.SEIZURE_ROLE()), "admin Orderbook.SEIZURE_ROLE");
        assertTrue(ob.hasAllRoles(timelock, ob.SEIZURE_ROLE()), "timelock Orderbook.SEIZURE_ROLE");
        assertFalse(ob.hasAnyRole(deployer, orderbookOperatorRoles), "deployer Orderbook roles");
    }

    function _assertTokenBootstrapRoles(address tokenAddress, address admin, address deployer, address timelock)
        private
        view
    {
        DEUSSToken token = DEUSSToken(tokenAddress);

        assertTrue(token.hasAllRoles(timelock, token.FORCE_TRANSFER_ROLE()), "tl token.FORCE_TRANSFER");
        assertFalse(token.hasAnyRole(admin, token.FORCE_TRANSFER_ROLE()), "admin Token.FORCE_TRANSFER_ROLE");
        assertFalse(token.hasAnyRole(deployer, token.FORCE_TRANSFER_ROLE()), "dep token.FORCE_TRANSFER");
    }

    function test_bootstrap_timelockActorReceivesOperationRoles() public {
        Suite memory suite = _harness.deployOnly();
        _harness.applyBootstrap(suite);

        TimelockController timelock = TimelockController(payable(suite.governance.timelockController));
        address actor = _harness.timelockControllerActor();

        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), actor), "actor PROPOSER_ROLE");
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), actor), "actor EXECUTOR_ROLE");
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), actor), "actor CANCELLER_ROLE");
    }

    function test_deploySuite_marketplaceLensOwnershipIsTransferredToTimelock() public {
        Suite memory suite = _harness.deploySuite();
        address timelock = suite.governance.timelockController;

        assertEq(MarketplaceLens(suite.utils.marketplaceLens).owner(), timelock, "lens owner");
        assertEq(UpgradeableBeacon(suite.utils.marketplaceLensBeacon).owner(), timelock, "lens beacon owner");
    }

    /*//////////////////////////////////////////////////////////////
             STAGE 2 — BOOTSTRAP: ENTITY TYPE & ESCROW ENTITY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice After bootstrap, the COMPANY_ENTITY type must be defined in EntityRegistry.
     */
    function test_bootstrap_companyEntityTypeIsDefined() public {
        Suite memory suite = _harness.deployOnly();
        _harness.applyBootstrap(suite);

        EntityTypeMeta memory meta =
            EntityRegistry(suite.registries.entityRegistry).getEntityTypeMeta(Constants.COMPANY_ENTITY);
        // Name must be non-empty (bootstrap sets it to "COMPANY" by default)
        assertTrue(meta.name != bytes32(0), "entity type name");
    }

    /**
     * @notice After bootstrap, the EscrowManager must be registered as a protocol entity
     *         (default: registerEscrowEntity = true).
     */
    function test_bootstrap_escrowManagerIsRegisteredAsEntity() public {
        Suite memory suite = _harness.deployOnly();
        _harness.applyBootstrap(suite);

        bytes32 entityId = keccak256(abi.encodePacked(suite.core.escrowManager, "escrow-entity"));
        EntityRegistry(suite.registries.entityRegistry).getEntityStatus(entityId);
        assertEq(
            EntityRegistry(suite.registries.entityRegistry).getEntityId(suite.core.escrowManager),
            entityId,
            "escrow entity account"
        );
    }

    function test_bootstrap_timelockIsRegisteredAsEnabledProtocolEntityAccount() public {
        Suite memory suite = _harness.deployOnly();
        _harness.applyBootstrap(suite);

        EntityRegistry er = EntityRegistry(suite.registries.entityRegistry);
        bytes32 entityId = keccak256(abi.encodePacked(suite.governance.timelockController, "timelock-entity"));

        er.getEntityStatus(entityId);
        assertEq(er.getEntityId(suite.governance.timelockController), entityId, "timelock entity account");
        assertTrue(er.isAccountEnabled(suite.governance.timelockController), "timelock account enabled");
    }

    /*//////////////////////////////////////////////////////////////
                    IDEMPOTENCY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Running BootstrapProtocol twice on the same suite must not revert.
     *         This is the core requirement for operational reliability.
     *         It is impossible after contract ownership is transferred to the timelock.
     */
    function test_bootstrap_isIdempotent() public {
        Suite memory suite = _harness.deployOnly();
        _harness.applyBootstrap(suite);
        // Second run must not revert
        _harness.applyBootstrap(suite);
    }

    /**
     * @notice Bootstrap reruns should succeed even when the original deployer can no longer
     *         administer EBSI, as long as WalletFactory is already fully wired.
     */
    function test_bootstrap_rerun_skipsPrivilegedEBSIRewiringWhenAlreadyConfigured() public {
        Suite memory suite = _harness.deployOnly();
        _harness.applyBootstrap(suite);

        // Revoke EBSI_ADMIN_ROLE from the deployer so it can no longer administer the template registry.
        bytes32 ebsiAdminRole = keccak256("EBSI_ADMIN_ROLE");
        address deployerAddr = _harness.deployer();
        vm.prank(deployerAddr);
        IAccessControl(suite.ebsi.proxyTemplateRegistry).revokeRole(ebsiAdminRole, deployerAddr);

        // Second run must succeed: WalletFactory is already fully wired, so EBSI steps are skipped.
        _harness.applyBootstrap(suite);
    }

    /**
     * @notice Bootstrap reruns should repair a missing EscrowManager account linkage even when
     *         the protocol entity already exists.
     */
    function test_bootstrap_rerun_repairsMissingEscrowAccountLink() public {
        Suite memory suite = _harness.deployOnly();
        _harness.applyBootstrap(suite);

        EntityRegistry er = EntityRegistry(suite.registries.entityRegistry);
        bytes32 entityId = keccak256(abi.encodePacked(suite.core.escrowManager, "escrow-entity"));

        vm.prank(_harness.admin());
        er.removeAccount(suite.core.escrowManager, "");

        assertFalse(er.doesAccountExist(suite.core.escrowManager), "escrow account removed");

        _harness.applyBootstrap(suite);

        assertTrue(er.doesAccountExist(suite.core.escrowManager), "escrow account restored");
        assertEq(er.getEntityId(suite.core.escrowManager), entityId, "escrow account relinked");
    }
}
