// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Initializable} from "solady/src/utils/Initializable.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {CompanyFixture} from "test/fixtures/CompanyFixture.t.sol";
import {Errors} from "src/libs/Errors.sol";
import {EntityStatus} from "src/registry/EntityStructs.sol";
import {PolicyRegistry} from "src/registry/PolicyRegistry.sol";
import {ICompanyWallet} from "src/wallet/ICompanyWallet.sol";
import {IWalletFactory} from "src/wallet/IWalletFactory.sol";
import {WalletFactory} from "src/wallet/WalletFactory.sol";
import {IProxyDeployer} from "src/deployer/IProxyDeployer.sol";
import {MockZeroAddressProxyFactory} from "test/mocks/MockContracts.sol";

contract MockWalletFactoryV2 is WalletFactory {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract WalletFactoryHarness is WalletFactory {
    function exposedResolveWalletTemplateId(bytes32 walletType) external view returns (bytes32) {
        return _resolveWalletTemplateId(walletType);
    }

    function exposedWalletFactoryStorageLocation() external pure returns (bytes32) {
        return _WALLET_FACTORY_STORAGE_LOCATION;
    }
}

contract WalletFactoryTest is CompanyFixture {
    bytes32 internal constant _PROXY_DEPLOYER_STORAGE_LOCATION =
        0x1be1affc245663ccf83f54f59d85d277ef7c71c2f359e52ff58373abee3d2900;
    bytes32 internal constant _BROKER_WALLET_TYPE = keccak256("BROKER_WALLET_TYPE");
    bytes32 internal constant _UNKNOWN_WALLET_TYPE = keccak256("UNKNOWN_WALLET_TYPE");

    WalletFactory internal _walletFactory;
    UpgradeableBeacon internal _walletFactoryBeacon;

    function setUp() public override {
        super.setUp();
        _walletFactory = WalletFactory(_wfAddr);
        _walletFactoryBeacon = UpgradeableBeacon(_suite.registries.walletFactoryBeacon);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC-7201 NAMESPACED STORAGE
    //////////////////////////////////////////////////////////////*/

    function test_namespacedStorageLocation_success_matchesErc7201Formula() public {
        WalletFactoryHarness implementation = new WalletFactoryHarness();
        bytes32 storageLocation = implementation.exposedWalletFactoryStorageLocation();

        assertEq(storageLocation, _erc7201Location("deuss.walletFactory.storage"));
        assertEq(uint256(storageLocation) & 0xff, 0);
    }

    function test_namespacedState_success_usesErc7201Storage() public view {
        bytes32 root = _erc7201Location("deuss.walletFactory.storage");

        // `entityRegistry` is field offset 0 in WalletFactoryState.
        assertEq(_loadAddress(_wfAddr, root), _walletFactory.entityRegistry());

        // `walletTemplateIdByType` is field offset 1; its entry slot is keccak256(key, root + 1).
        bytes32 templateEntrySlot = keccak256(abi.encode(COMPANY_WALLET_TYPE, _slotOffset(root, 1)));
        assertEq(
            vm.load(_wfAddr, templateEntrySlot), bytes32(_walletFactory.getWalletTemplateIdForType(COMPANY_WALLET_TYPE))
        );
    }

    function test_initialize_reverts_zeroEntityRegistry() public {
        WalletFactory implementation = new WalletFactory();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), _deployer);
        bytes memory initData = abi.encodeWithSelector(WalletFactory.initialize.selector, address(0), _deployer);

        vm.expectRevert(Errors.ZeroAddress.selector);
        new BeaconProxy(address(beacon), initData);
    }

    function test_initialize_reverts_zeroOwner() public {
        WalletFactory implementation = new WalletFactory();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), _deployer);
        bytes memory initData = abi.encodeWithSelector(WalletFactory.initialize.selector, _erAddr, address(0));

        vm.expectRevert(Errors.ZeroAddress.selector);
        new BeaconProxy(address(beacon), initData);
    }

    function test_initialize_reverts_invalidEntityRegistry() public {
        WalletFactory implementation = new WalletFactory();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), _deployer);
        PolicyRegistry invalidEntityRegistry = _deployPolicyRegistry(_deployer);
        bytes memory initData =
            abi.encodeWithSelector(WalletFactory.initialize.selector, address(invalidEntityRegistry), _deployer);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.WalletFactory__InvalidEntityRegistry.selector, address(invalidEntityRegistry))
        );
        new BeaconProxy(address(beacon), initData);
    }

    function test_initialize_reverts_reinitialize() public {
        vm.prank(_deployer);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        _walletFactory.initialize(_erAddr, _deployer);
    }

    function test_initialize_success_emitsEntityRegistrySet() public {
        WalletFactory implementation = new WalletFactory();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), _deployer);
        bytes memory initData = abi.encodeWithSelector(WalletFactory.initialize.selector, _erAddr, _deployer);

        address predictedProxy = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));

        vm.expectEmit(true, false, false, true, predictedProxy);
        emit IWalletFactory.EntityRegistrySet(_erAddr);
        WalletFactory deployed = WalletFactory(address(new BeaconProxy(address(beacon), initData)));

        assertEq(deployed.entityRegistry(), _erAddr);
    }

    function test_createWallet_reverts_emptyInitData() public {
        bytes32 entityId = keccak256("wf-empty-init");
        address manager = makeAddr("wfManager");

        _registerEntityWithManager(entityId, manager);

        vm.prank(manager);
        vm.expectRevert(Errors.WalletFactory__InitDataEmpty.selector);
        _walletFactory.createWallet(
            IWalletFactory.CreateWalletParams({
                entityId: entityId, walletType: COMPANY_WALLET_TYPE, initData: bytes("")
            })
        );
    }

    function test_createWallet_reverts_notEntityManager() public {
        bytes32 entityId = keccak256("wf-not-manager");
        address manager = makeAddr("wfManager");
        address outsider = makeAddr("wfOutsider");

        _registerEntityWithManager(entityId, manager);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.WalletFactory__NotEntityManager.selector, outsider, entityId));
        _walletFactory.createWallet(
            IWalletFactory.CreateWalletParams({
                entityId: entityId,
                walletType: COMPANY_WALLET_TYPE,
                initData: abi.encodeCall(
                    ICompanyWallet.initialize, (makeAddr("owner"), _suite.registries.walletPolicyRegistry)
                )
            })
        );
    }

    function test_createWallet_reverts_entityNotEnabled() public {
        bytes32 entityId = keccak256("wf-disabled-entity");
        address manager = makeAddr("wfManager");

        _registerEntityWithManager(entityId, manager);

        vm.prank(_erAdmin);
        _er.setEntityStatus(entityId, EntityStatus.DISABLED, "");

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(Errors.WalletFactory__EntityNotEnabled.selector, entityId));
        _walletFactory.createWallet(
            IWalletFactory.CreateWalletParams({
                entityId: entityId,
                walletType: COMPANY_WALLET_TYPE,
                initData: abi.encodeCall(
                    ICompanyWallet.initialize, (makeAddr("owner"), _suite.registries.walletPolicyRegistry)
                )
            })
        );
    }

    function test_createWallet_reverts_zeroWalletType() public {
        bytes32 entityId = keccak256("wf-zero-wallet-type");
        address manager = makeAddr("wfManager");

        _registerEntityWithManager(entityId, manager);

        vm.prank(manager);
        vm.expectRevert(Errors.ER__CompanyWalletTypeIdZero.selector);
        _walletFactory.createWallet(
            IWalletFactory.CreateWalletParams({
                entityId: entityId,
                walletType: bytes32(0),
                initData: abi.encodeCall(
                    ICompanyWallet.initialize, (makeAddr("owner"), _suite.registries.walletPolicyRegistry)
                )
            })
        );
    }

    function test_createWallet_reverts_unconfiguredWalletType() public {
        bytes32 entityId = keccak256("wf-unconfigured-type");
        address manager = makeAddr("wfManager");

        _registerEntityWithManager(entityId, manager);

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ER__CompanyWalletTypeNotConfigured.selector, _UNKNOWN_WALLET_TYPE)
        );
        _walletFactory.createWallet(
            IWalletFactory.CreateWalletParams({
                entityId: entityId,
                walletType: _UNKNOWN_WALLET_TYPE,
                initData: abi.encodeCall(
                    ICompanyWallet.initialize, (makeAddr("owner"), _suite.registries.walletPolicyRegistry)
                )
            })
        );
    }

    function test_createWallet_success_withTypedTemplate() public {
        bytes32 entityId = keccak256("wf-typed-success");
        address manager = makeAddr("wfManager");
        address owner = makeAddr("wfOwner");

        _registerEntityWithManager(entityId, manager);

        bytes32 companyTemplateId = _walletFactory.getWalletTemplateIdForType(COMPANY_WALLET_TYPE);
        IProxyDeployer.TemplateConfig memory cfg = IProxyDeployer(_wfAddr).getTemplateConfig(companyTemplateId);

        bytes memory data = abi.encodeWithSelector(
            IWalletFactory.setWalletTemplateForType.selector, _BROKER_WALLET_TYPE, cfg.name, cfg.version
        );
        _timelockOp(_wfAddr, data);

        vm.prank(manager);
        address wallet = _walletFactory.createWallet(
            IWalletFactory.CreateWalletParams({
                entityId: entityId,
                walletType: _BROKER_WALLET_TYPE,
                initData: abi.encodeCall(ICompanyWallet.initialize, (owner, _suite.registries.walletPolicyRegistry))
            })
        );

        assertTrue(wallet != address(0));
        assertEq(ICompanyWallet(wallet).owner(), owner);
        assertEq(ICompanyWallet(wallet).policyRegistry(), _suite.registries.walletPolicyRegistry);
    }

    function test_createWallet_success_withCustomInitData() public {
        bytes32 entityId = keccak256("wf-custom-init");
        address manager = makeAddr("wfManager");
        address owner = makeAddr("wfOwner");
        PolicyRegistry customPolicyRegistry = _deployPolicyRegistry(_deployer);

        _registerEntityWithManager(entityId, manager);

        vm.prank(manager);
        address wallet = _walletFactory.createWallet(
            IWalletFactory.CreateWalletParams({
                entityId: entityId,
                walletType: COMPANY_WALLET_TYPE,
                initData: abi.encodeCall(ICompanyWallet.initialize, (owner, address(customPolicyRegistry)))
            })
        );

        assertEq(ICompanyWallet(wallet).owner(), owner);
        assertEq(ICompanyWallet(wallet).policyRegistry(), address(customPolicyRegistry));
    }

    function test_createWallet_reverts_whenProxyFactoryReturnsZeroAddress() public {
        bytes32 entityId = keccak256("wf-zero-proxy");
        address manager = makeAddr("wfManager");

        _registerEntityWithManager(entityId, manager);

        MockZeroAddressProxyFactory mockFactory = new MockZeroAddressProxyFactory(IProxyDeployer(_wfAddr).getRegistry());

        bytes memory data = abi.encodeWithSelector(IProxyDeployer.setFactory.selector, address(mockFactory));
        _timelockOp(_wfAddr, data);

        vm.prank(manager);
        vm.expectRevert(Errors.ER__CompanyWalletAddressZero.selector);
        _walletFactory.createWallet(
            IWalletFactory.CreateWalletParams({
                entityId: entityId,
                walletType: COMPANY_WALLET_TYPE,
                initData: abi.encodeCall(
                    ICompanyWallet.initialize, (makeAddr("owner"), _suite.registries.walletPolicyRegistry)
                )
            })
        );
    }

    function test_setWalletTemplateForType_success_reusesActiveTemplate() public {
        bytes32 companyTemplateId = _walletFactory.getWalletTemplateIdForType(COMPANY_WALLET_TYPE);
        IProxyDeployer.TemplateConfig memory cfg = IProxyDeployer(_wfAddr).getTemplateConfig(companyTemplateId);

        bytes memory data = abi.encodeWithSelector(
            IWalletFactory.setWalletTemplateForType.selector, _BROKER_WALLET_TYPE, cfg.name, cfg.version
        );
        _timelockSchedule(_wfAddr, data);

        vm.expectEmit(true, true, false, true);
        emit IWalletFactory.WalletTemplateForTypeSet(_BROKER_WALLET_TYPE, companyTemplateId, cfg.name, cfg.version);
        _timelockExecute(_wfAddr, data);

        assertEq(_walletFactory.getWalletTemplateIdForType(_BROKER_WALLET_TYPE), companyTemplateId);
    }

    function test_setWalletTemplateForType_success_whenTemplateInactive() public {
        bytes32 companyTemplateId = _walletFactory.getWalletTemplateIdForType(COMPANY_WALLET_TYPE);
        IProxyDeployer.TemplateConfig memory cfg = IProxyDeployer(_wfAddr).getTemplateConfig(companyTemplateId);

        bytes memory deactivateData =
            abi.encodeWithSelector(IProxyDeployer.deactivateTemplateConfig.selector, companyTemplateId);
        _timelockOp(_wfAddr, deactivateData);

        bytes memory data = abi.encodeWithSelector(
            IWalletFactory.setWalletTemplateForType.selector, _BROKER_WALLET_TYPE, cfg.name, cfg.version
        );
        _timelockSchedule(_wfAddr, data);

        vm.expectEmit(true, false, false, true);
        emit IProxyDeployer.TemplateConfigAdded(companyTemplateId, cfg.name, cfg.version);
        vm.expectEmit(true, true, false, true);
        emit IWalletFactory.WalletTemplateForTypeSet(_BROKER_WALLET_TYPE, companyTemplateId, cfg.name, cfg.version);
        _timelockExecute(_wfAddr, data);

        assertEq(_walletFactory.getWalletTemplateIdForType(_BROKER_WALLET_TYPE), companyTemplateId);
    }

    function test_setWalletTemplateForType_reverts_notOwner() public {
        bytes32 companyTemplateId = _walletFactory.getWalletTemplateIdForType(COMPANY_WALLET_TYPE);
        IProxyDeployer.TemplateConfig memory cfg = IProxyDeployer(_wfAddr).getTemplateConfig(companyTemplateId);

        vm.prank(_notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _walletFactory.setWalletTemplateForType(_BROKER_WALLET_TYPE, cfg.name, cfg.version);
    }

    function test_setWalletTemplateForType_reverts_zeroWalletType() public {
        bytes32 companyTemplateId = _walletFactory.getWalletTemplateIdForType(COMPANY_WALLET_TYPE);
        IProxyDeployer.TemplateConfig memory cfg = IProxyDeployer(_wfAddr).getTemplateConfig(companyTemplateId);

        bytes memory data =
            abi.encodeWithSelector(IWalletFactory.setWalletTemplateForType.selector, bytes32(0), cfg.name, cfg.version);
        _timelockSchedule(_wfAddr, data);
        vm.expectRevert(Errors.ER__CompanyWalletTypeIdZero.selector);
        _timelockExecute(_wfAddr, data);
    }

    function test_getters_success() public view {
        bytes32 companyTemplateId = _walletFactory.getWalletTemplateIdForType(COMPANY_WALLET_TYPE);
        assertEq(_walletFactory.getWalletTemplateIdForType(COMPANY_WALLET_TYPE), companyTemplateId);
        assertEq(_walletFactory.entityRegistry(), _erAddr);
    }

    function test_proxyDeployerStorage_success_usesErc7201Namespace() public view {
        assertEq(_loadAddress(_wfAddr, _PROXY_DEPLOYER_STORAGE_LOCATION), IProxyDeployer(_wfAddr).getFactory());
        assertEq(
            _loadAddress(_wfAddr, _slotOffset(_PROXY_DEPLOYER_STORAGE_LOCATION, 1)),
            IProxyDeployer(_wfAddr).getRegistry()
        );

        for (uint256 slot = 51; slot < 55; ++slot) {
            assertEq(vm.load(_wfAddr, bytes32(slot)), bytes32(0));
        }
    }

    function test_upgradeTo_success_owner() public {
        MockWalletFactoryV2 newImplementation = new MockWalletFactoryV2();

        bytes memory data = abi.encodeWithSelector(UpgradeableBeacon.upgradeTo.selector, address(newImplementation));
        _timelockOp(address(_walletFactoryBeacon), data);

        assertEq(MockWalletFactoryV2(address(_walletFactory)).version(), 2);
    }

    function test_resolveWalletTemplateId_internalBranches_viaHarness() public {
        WalletFactoryHarness implementation = new WalletFactoryHarness();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), _deployer);
        bytes memory initData = abi.encodeWithSelector(WalletFactory.initialize.selector, _erAddr, _deployer);
        WalletFactoryHarness harness = WalletFactoryHarness(address(new BeaconProxy(address(beacon), initData)));

        vm.startPrank(_deployer);
        IProxyDeployer(address(harness)).setRegistry(IProxyDeployer(_wfAddr).getRegistry());
        IProxyDeployer(address(harness)).setFactory(IProxyDeployer(_wfAddr).getFactory());

        bytes32 companyTemplateId = _walletFactory.getWalletTemplateIdForType(COMPANY_WALLET_TYPE);
        IProxyDeployer.TemplateConfig memory cfg = IProxyDeployer(_wfAddr).getTemplateConfig(companyTemplateId);
        harness.setWalletTemplateForType(_BROKER_WALLET_TYPE, cfg.name, cfg.version);
        vm.stopPrank();

        vm.expectRevert(Errors.ER__CompanyWalletTypeIdZero.selector);
        harness.exposedResolveWalletTemplateId(bytes32(0));

        assertEq(harness.exposedResolveWalletTemplateId(_BROKER_WALLET_TYPE), companyTemplateId);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.ER__CompanyWalletTypeNotConfigured.selector, _UNKNOWN_WALLET_TYPE)
        );
        harness.exposedResolveWalletTemplateId(_UNKNOWN_WALLET_TYPE);
    }

    function _registerEntityWithManager(bytes32 entityId, address manager) internal {
        vm.startPrank(_erAdmin);
        _er.registerEntity(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF);
        _er.setEntityManager(entityId, manager, true);
        vm.stopPrank();
    }
}
