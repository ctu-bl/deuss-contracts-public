// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {DependenciesBase} from "src/base/DependenciesBase.sol";
import {EntityEligibilityGuard} from "src/registry/EntityEligibilityGuard.sol";
import {IEntityRegistry} from "src/registry/interfaces/IEntityRegistry.sol";
import {Errors} from "src/libs/Errors.sol";
import {StorageLayoutHelpers} from "test/fixtures/StorageLayoutHelpers.t.sol";

contract EntityEligibilityGuardHarness is EntityEligibilityGuard {
    function configureEntityRegistry(address registry_) external {
        _dependenciesStorage().entityRegistry = registry_;
    }

    function grantAdmin(address user) external {
        _grantRoles(user, ADMIN);
    }

    function exposedDependenciesStorageLocation() external pure returns (bytes32) {
        return _DEPENDENCIES_STORAGE_LOCATION;
    }

    function exposedEntityEligibilityStorageLocation() external pure returns (bytes32) {
        return _ENTITY_ELIGIBILITY_STORAGE_LOCATION;
    }

    function setAllowedEntityType(uint256 typeId, bool allowed) external {
        _setAllowedEntityType(typeId, allowed);
    }

    function setAllowedEntityTypes(uint256[] calldata typeIds, bool allowed) external {
        _setAllowedEntityTypes(typeIds, allowed);
    }

    function validateWalletEnabled(address wallet) external view {
        _validateEntityWalletEnabled(wallet);
    }

    function validateEntityTypeAllowed(address wallet) external view {
        _validateEntityTypeAllowed(wallet);
    }

    function validateEntityWalletAndTypeAllowed(address wallet) external view {
        _validateEntityWalletAndTypeAllowed(wallet);
    }

    function validateEntityWalletsAndTypesAllowed(address[] calldata wallets) external view {
        _validateEntityWalletsAndTypesAllowed(wallets);
    }

    function isEntityTypeAllowed(uint256 typeId) external view returns (bool) {
        return _entityEligibilityStorage().allowedEntityTypes[typeId];
    }
}

contract EntityEligibilityGuardTest is StorageLayoutHelpers {
    event EntityTypeAllowed(uint256 indexed typeId, bool indexed allowed);

    EntityEligibilityGuardHarness internal _harness;

    function setUp() public {
        _harness = new EntityEligibilityGuardHarness();
    }

    function test_namespacedStorageLocations_success_matchErc7201Formula() public view {
        bytes32 dependenciesLocation = _harness.exposedDependenciesStorageLocation();
        bytes32 eligibilityLocation = _harness.exposedEntityEligibilityStorageLocation();

        assertEq(dependenciesLocation, _erc7201Location("deuss.base.dependencies.storage"));
        assertEq(eligibilityLocation, _erc7201Location(_entityEligibilityNamespace()));
        assertEq(uint256(dependenciesLocation) & 0xff, 0);
        assertEq(uint256(eligibilityLocation) & 0xff, 0);
        assertTrue(dependenciesLocation != eligibilityLocation);
    }

    /*//////////////////////////////////////////////////////////////
                            setBondRegistry
    //////////////////////////////////////////////////////////////*/

    function test_setBondRegistry_success() public {
        address admin = makeAddr("dependenciesAdmin");
        address bondRegistry = makeAddr("bondRegistry");
        _harness.grantAdmin(admin);

        vm.expectEmit();
        emit DependenciesBase.BondRegistrySet(address(0), bondRegistry);

        vm.prank(admin);
        _harness.setBondRegistry(bondRegistry);

        assertEq(_harness.getBondRegistry(), bondRegistry);
        assertEq(
            vm.load(address(_harness), _erc7201Location("deuss.base.dependencies.storage")),
            bytes32(uint256(uint160(bondRegistry)))
        );
    }

    function test_setBondRegistry_reverts_notRoleAssigned() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _harness.setBondRegistry(makeAddr("bondRegistry"));
    }

    function test_setBondRegistry_reverts_zeroAddress() public {
        address admin = makeAddr("dependenciesAdmin");
        _harness.grantAdmin(admin);

        vm.prank(admin);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _harness.setBondRegistry(address(0));
    }

    function test_setBondRegistry_reverts_alreadySet() public {
        address admin = makeAddr("dependenciesAdmin");
        _harness.grantAdmin(admin);

        vm.startPrank(admin);
        _harness.setBondRegistry(makeAddr("bondRegistry"));

        vm.expectRevert(Errors.DependenciesBase__BondRegistryAlreadySet.selector);
        _harness.setBondRegistry(makeAddr("newBondRegistry"));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         setAllowedEntityType
    //////////////////////////////////////////////////////////////*/

    function test_setAllowedEntityType_success() public {
        vm.expectEmit();
        emit EntityTypeAllowed(1, true);
        _harness.setAllowedEntityType(1, true);

        assertTrue(_harness.isEntityTypeAllowed(1));
        bytes32 mappingSlot = keccak256(abi.encode(uint256(1), _erc7201Location(_entityEligibilityNamespace())));
        assertEq(vm.load(address(_harness), mappingSlot), bytes32(uint256(1)));
    }

    function test_setAllowedEntityTypes_success() public {
        uint256[] memory typeIds = new uint256[](2);
        typeIds[0] = 1;
        typeIds[1] = 2;

        vm.expectEmit();
        emit EntityTypeAllowed(1, true);
        vm.expectEmit();
        emit EntityTypeAllowed(2, true);
        _harness.setAllowedEntityTypes(typeIds, true);

        assertTrue(_harness.isEntityTypeAllowed(1));
        assertTrue(_harness.isEntityTypeAllowed(2));
    }

    function test_setAllowedEntityTypes_success_emptyArray() public {
        uint256[] memory typeIds = new uint256[](0);

        _harness.setAllowedEntityTypes(typeIds, true);
        assertFalse(_harness.isEntityTypeAllowed(1));
    }

    /*//////////////////////////////////////////////////////////////
                      validateEntityWalletEnabled
    //////////////////////////////////////////////////////////////*/

    function test_validateEntityWalletEnabled_success_noRegistryConfigured() public {
        _harness.validateWalletEnabled(makeAddr("wallet"));
    }

    function test_validateEntityWalletEnabled_success_walletEnabledInRegistry() public {
        address registry = makeAddr("registry");
        address wallet = makeAddr("wallet");
        _harness.configureEntityRegistry(registry);
        assertEq(_harness.getEntityRegistry(), registry);
        assertEq(
            vm.load(address(_harness), _slotOffset(_erc7201Location("deuss.base.dependencies.storage"), 2)),
            bytes32(uint256(uint160(registry)))
        );

        vm.mockCall(
            registry, abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, wallet), abi.encode(true)
        );

        _harness.validateWalletEnabled(wallet);
    }

    function test_validateEntityWalletEnabled_reverts_walletDisabledInRegistry() public {
        address registry = makeAddr("registry");
        address wallet = makeAddr("wallet");
        _harness.configureEntityRegistry(registry);

        vm.mockCall(
            registry, abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, wallet), abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, wallet));
        _harness.validateWalletEnabled(wallet);
    }

    /*//////////////////////////////////////////////////////////////
                      validateEntityTypeAllowed
    //////////////////////////////////////////////////////////////*/

    function test_validateEntityTypeAllowed_success_noRegistryConfigured() public {
        _harness.validateEntityTypeAllowed(makeAddr("wallet"));
    }

    function test_validateEntityTypeAllowed_success_whenTypeAllowed() public {
        address registry = makeAddr("registry");
        address wallet = makeAddr("wallet");
        uint256 typeId = 7;
        _harness.configureEntityRegistry(registry);
        _harness.setAllowedEntityType(typeId, true);

        vm.mockCall(
            registry,
            abi.encodeWithSelector(IEntityRegistry.getEntityTypeIdByAccount.selector, wallet),
            abi.encode(typeId)
        );

        _harness.validateEntityTypeAllowed(wallet);
    }

    function test_validateEntityTypeAllowed_reverts_whenTypeNotAllowed() public {
        address registry = makeAddr("registry");
        address wallet = makeAddr("wallet");
        uint256 typeId = 9;
        _harness.configureEntityRegistry(registry);

        vm.mockCall(
            registry,
            abi.encodeWithSelector(IEntityRegistry.getEntityTypeIdByAccount.selector, wallet),
            abi.encode(typeId)
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityTypeNotAllowed.selector, typeId));
        _harness.validateEntityTypeAllowed(wallet);
    }

    /*//////////////////////////////////////////////////////////////
                   validateEntityWalletAndTypeAllowed
    //////////////////////////////////////////////////////////////*/

    function test_validateEntityWalletAndTypeAllowed_success() public {
        address registry = makeAddr("registry");
        address wallet = makeAddr("wallet");
        uint256 typeId = 5;
        _harness.configureEntityRegistry(registry);
        _harness.setAllowedEntityType(typeId, true);

        vm.mockCall(
            registry, abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, wallet), abi.encode(true)
        );
        vm.mockCall(
            registry,
            abi.encodeWithSelector(IEntityRegistry.getEntityTypeIdByAccount.selector, wallet),
            abi.encode(typeId)
        );

        _harness.validateEntityWalletAndTypeAllowed(wallet);
    }

    function test_validateEntityWalletAndTypeAllowed_reverts_whenWalletDisabled() public {
        address registry = makeAddr("registry");
        address wallet = makeAddr("wallet");
        _harness.configureEntityRegistry(registry);

        vm.mockCall(
            registry, abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, wallet), abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, wallet));
        _harness.validateEntityWalletAndTypeAllowed(wallet);
    }

    function test_validateEntityWalletAndTypeAllowed_reverts_whenTypeNotAllowed() public {
        address registry = makeAddr("registry");
        address wallet = makeAddr("wallet");
        uint256 typeId = 11;
        _harness.configureEntityRegistry(registry);

        vm.mockCall(
            registry, abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, wallet), abi.encode(true)
        );
        vm.mockCall(
            registry,
            abi.encodeWithSelector(IEntityRegistry.getEntityTypeIdByAccount.selector, wallet),
            abi.encode(typeId)
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityTypeNotAllowed.selector, typeId));
        _harness.validateEntityWalletAndTypeAllowed(wallet);
    }

    /*//////////////////////////////////////////////////////////////
                  validateEntityWalletsAndTypesAllowed
    //////////////////////////////////////////////////////////////*/

    function test_validateEntityWalletsAndTypesAllowed_success_empty() public view {
        address[] memory wallets = new address[](0);
        _harness.validateEntityWalletsAndTypesAllowed(wallets);
    }

    function test_validateEntityWalletsAndTypesAllowed_success() public {
        address registry = makeAddr("registry");
        address wallet1 = makeAddr("wallet1");
        address wallet2 = makeAddr("wallet2");
        uint256 typeId1 = 21;
        uint256 typeId2 = 22;
        _harness.configureEntityRegistry(registry);
        _harness.setAllowedEntityType(typeId1, true);
        _harness.setAllowedEntityType(typeId2, true);

        vm.mockCall(
            registry, abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, wallet1), abi.encode(true)
        );
        vm.mockCall(
            registry,
            abi.encodeWithSelector(IEntityRegistry.getEntityTypeIdByAccount.selector, wallet1),
            abi.encode(typeId1)
        );
        vm.mockCall(
            registry, abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, wallet2), abi.encode(true)
        );
        vm.mockCall(
            registry,
            abi.encodeWithSelector(IEntityRegistry.getEntityTypeIdByAccount.selector, wallet2),
            abi.encode(typeId2)
        );

        address[] memory wallets = new address[](2);
        wallets[0] = wallet1;
        wallets[1] = wallet2;
        _harness.validateEntityWalletsAndTypesAllowed(wallets);
    }

    function test_validateEntityWalletsAndTypesAllowed_reverts_whenAnyWalletDisabled() public {
        address registry = makeAddr("registry");
        address wallet1 = makeAddr("wallet1");
        address wallet2 = makeAddr("wallet2");
        uint256 typeId1 = 31;
        _harness.configureEntityRegistry(registry);
        _harness.setAllowedEntityType(typeId1, true);

        vm.mockCall(
            registry, abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, wallet1), abi.encode(true)
        );
        vm.mockCall(
            registry,
            abi.encodeWithSelector(IEntityRegistry.getEntityTypeIdByAccount.selector, wallet1),
            abi.encode(typeId1)
        );
        vm.mockCall(
            registry, abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, wallet2), abi.encode(false)
        );

        address[] memory wallets = new address[](2);
        wallets[0] = wallet1;
        wallets[1] = wallet2;

        vm.expectRevert(abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, wallet2));
        _harness.validateEntityWalletsAndTypesAllowed(wallets);
    }

    function _entityEligibilityNamespace() internal pure returns (string memory) {
        return string.concat("deuss.registry.", "entityeligibilityguard.storage");
    }
}
