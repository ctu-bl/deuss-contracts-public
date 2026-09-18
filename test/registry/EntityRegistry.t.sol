// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";

import {CompanyFixture} from "test/fixtures/CompanyFixture.t.sol";
import {Errors} from "src/libs/Errors.sol";
import {
    Account as RegistryAccount,
    AccountStatus,
    Entity,
    EntityStatus,
    EntityTypeMeta,
    PendingAccountRegistration
} from "src/registry/EntityStructs.sol";
import {IEntityRegistry} from "src/registry/interfaces/IEntityRegistry.sol";
import {EntityRegistry} from "src/registry/EntityRegistry.sol";
import {MockEntityRegistry} from "test/mocks/MockContracts.sol";

contract EntityRegistryStorageHarness is EntityRegistry {
    function exposedEntityRegistryStorageLocation() external pure returns (bytes32) {
        return _ENTITY_REGISTRY_STORAGE_LOCATION;
    }
}

contract EntityRegistryTest is CompanyFixture {
    address private _erAdminOnly;
    address private _erGuard;
    address private _erOnboarding;
    address private _erWalletTransfer;
    address private _erEntityTypeManager;

    function setUp() public virtual override {
        super.setUp();

        _erAdminOnly = makeAddr("erAdminOnly");
        _erGuard = makeAddr("erGuard");
        _erOnboarding = makeAddr("erOnboarding");
        _erWalletTransfer = makeAddr("erWalletTransfer");
        _erEntityTypeManager = makeAddr("erEntityTypeManager");

        _grantRoles(_erAddr, _erAdminOnly, _er.ADMIN_ROLE());
        _grantRoles(_erAddr, _erGuard, _er.GUARD());
        _grantRoles(_erAddr, _erOnboarding, _er.ONBOARDING());
        _grantRoles(_erAddr, _erWalletTransfer, _er.WALLET_TRANSFER());
        _grantRoles(_erAddr, _erEntityTypeManager, _er.ENTITY_TYPE_MANAGER());
    }

    /*//////////////////////////////////////////////////////////////
                          ERC-7201 NAMESPACED STORAGE
    //////////////////////////////////////////////////////////////*/

    function test_namespacedStorageLocation_success_matchesErc7201Formula() public {
        EntityRegistryStorageHarness harness = new EntityRegistryStorageHarness();
        bytes32 storageLocation = harness.exposedEntityRegistryStorageLocation();

        assertEq(storageLocation, _erc7201Location("deuss.entityRegistry.storage"));
        assertEq(uint256(storageLocation) & 0xff, 0);
    }

    function test_namespacedState_success_usesErc7201Storage() public {
        bytes32 entityId = keccak256("ns-entity");
        address account = makeAddr("ns-account");

        vm.prank(_erOnboarding);
        _er.registerEntity(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF);
        vm.prank(_erAdminOnly);
        _er.registerAccount(account, entityId, ROLE_FLAGS_EMPTY);
        assertTrue(_er.isAccountRegistered(account));

        // `accounts` is field offset 1; entry slot = keccak256(account, root + 1).
        bytes32 accountEntrySlot = keccak256(abi.encode(account, _entityRegistryAccountsSlot()));
        assertTrue(vm.load(_erAddr, accountEntrySlot) != bytes32(0));

        // Isolation: the pre-namespace sequential slot (1) for the same key holds nothing.
        assertEq(vm.load(_erAddr, keccak256(abi.encode(account, uint256(1)))), bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                             defineEntityType
    //////////////////////////////////////////////////////////////*/

    function test_defineEntityType_success() public {
        uint256 typeId = 11;

        vm.prank(_erEntityTypeManager);
        // forge-lint: disable-next-line(unsafe-typecast)
        _er.defineEntityType(typeId, bytes32("BROKER"), 7);

        EntityTypeMeta memory meta = _er.getEntityTypeMeta(typeId);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(meta.name, bytes32("BROKER"));
        assertEq(meta.caps, 7);
        assertFalse(meta.frozen);
    }

    function test_defineEntityType_reverts_zeroTypeId() public {
        vm.prank(_erEntityTypeManager);
        vm.expectRevert(Errors.ER__EntityTypeIdZero.selector);
        // forge-lint: disable-next-line(unsafe-typecast)
        _er.defineEntityType(0, bytes32("ZERO"), 0);
    }

    function test_defineEntityType_reverts_zeroName() public {
        uint256 typeId = 12;

        vm.prank(_erEntityTypeManager);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityTypeNameZero.selector, typeId));
        _er.defineEntityType(typeId, bytes32(0), 7);
    }

    function test_defineEntityType_reverts_whenTypeFrozen() public {
        uint256 typeId = 22;

        vm.startPrank(_erEntityTypeManager);
        // forge-lint: disable-next-line(unsafe-typecast)
        _er.defineEntityType(typeId, bytes32("FROZEN"), 1);
        _er.freezeEntityType(typeId);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityTypeFrozen.selector, typeId));
        // forge-lint: disable-next-line(unsafe-typecast)
        _er.defineEntityType(typeId, bytes32("UPDATED"), 2);
        vm.stopPrank();
    }

    function test_defineEntityType_reverts_unauthorizedCaller_withoutEntityTypeManagerRole() public {
        uint256 typeId = 77;

        address[] memory unauthorizedCallers = new address[](5);
        unauthorizedCallers[0] = _erAdminOnly;
        unauthorizedCallers[1] = _erGuard;
        unauthorizedCallers[2] = _erOnboarding;
        unauthorizedCallers[3] = _erWalletTransfer;
        unauthorizedCallers[4] = _notOwner;

        bytes4 unauthorizedSelector = bytes4(keccak256("Unauthorized()"));
        for (uint256 i; i < unauthorizedCallers.length;) {
            vm.expectRevert(unauthorizedSelector);
            vm.prank(unauthorizedCallers[i]);
            // forge-lint: disable-next-line(unsafe-typecast)
            _er.defineEntityType(typeId, bytes32("FORBIDDEN"), 1);
            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                             freezeEntityType
    //////////////////////////////////////////////////////////////*/

    function test_freezeEntityType_success() public {
        uint256 typeId = 33;

        vm.startPrank(_erEntityTypeManager);
        // forge-lint: disable-next-line(unsafe-typecast)
        _er.defineEntityType(typeId, bytes32("ENTITY_TYPE"), 1);
        _er.freezeEntityType(typeId);
        vm.stopPrank();

        EntityTypeMeta memory meta = _er.getEntityTypeMeta(typeId);
        assertTrue(meta.frozen);
    }

    function test_freezeEntityType_reverts_unauthorizedCaller_withoutEntityTypeManagerRole() public {
        uint256 typeId = 34;

        vm.prank(_erEntityTypeManager);
        // forge-lint: disable-next-line(unsafe-typecast)
        _er.defineEntityType(typeId, bytes32("ENTITY_TYPE"), 1);

        address[] memory unauthorizedCallers = new address[](5);
        unauthorizedCallers[0] = _erAdminOnly;
        unauthorizedCallers[1] = _erGuard;
        unauthorizedCallers[2] = _erOnboarding;
        unauthorizedCallers[3] = _erWalletTransfer;
        unauthorizedCallers[4] = _notOwner;

        bytes4 unauthorizedSelector = bytes4(keccak256("Unauthorized()"));
        for (uint256 i; i < unauthorizedCallers.length;) {
            vm.expectRevert(unauthorizedSelector);
            vm.prank(unauthorizedCallers[i]);
            _er.freezeEntityType(typeId);
            unchecked {
                ++i;
            }
        }
    }

    function test_freezeEntityType_reverts_zeroTypeId() public {
        vm.prank(_erEntityTypeManager);
        vm.expectRevert(Errors.ER__EntityTypeIdZero.selector);
        _er.freezeEntityType(0);
    }

    function test_freezeEntityType_reverts_entityTypeNotRegistered() public {
        uint256 missingTypeId = 404;

        vm.prank(_erEntityTypeManager);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityTypeNotRegistered.selector, missingTypeId));
        _er.freezeEntityType(missingTypeId);
    }

    function test_freezeEntityType_reverts_capsOnlyMalformedType() public {
        uint256 typeId = 405;
        _setEntityTypeCaps(typeId, 7);

        vm.prank(_erEntityTypeManager);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityTypeNotRegistered.selector, typeId));
        _er.freezeEntityType(typeId);
    }

    /*//////////////////////////////////////////////////////////////
                               registerEntity
    //////////////////////////////////////////////////////////////*/

    function test_registerEntity_success() public {
        bytes32 entityId = keccak256("entity-register-success");

        vm.expectEmit(true, true, false, true);
        emit IEntityRegistry.EntityRegistered(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF);

        vm.prank(_erOnboarding);
        _er.registerEntity(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF);

        Entity memory entity = _er.getEntity(entityId);
        assertEq(entity.typeId, COMPANY_ENTITY);
        assertEq(uint8(entity.status), uint8(EntityStatus.ENABLED));
    }

    function test_registerEntity_reverts_invalidAndDuplicate() public {
        bytes32 entityId = keccak256("entity-invalid");

        vm.startPrank(_erOnboarding);

        vm.expectRevert(Errors.ER__EntityIdZero.selector);
        _er.registerEntity(bytes32(0), COMPANY_ENTITY, EMPTY_METADATA_REF);

        vm.expectRevert(Errors.ER__EntityTypeIdZero.selector);
        _er.registerEntity(entityId, 0, EMPTY_METADATA_REF);

        _er.registerEntity(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF);

        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityAlreadyRegistered.selector, entityId));
        _er.registerEntity(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF);

        vm.stopPrank();
    }

    function test_registerEntity_reverts_entityTypeNotRegistered() public {
        bytes32 entityId = keccak256("entity-unregistered-type");
        uint256 unregisteredTypeId = 999;

        vm.prank(_erOnboarding);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityTypeNotRegistered.selector, unregisteredTypeId));
        _er.registerEntity(entityId, unregisteredTypeId, EMPTY_METADATA_REF);
    }

    function test_registerEntity_reverts_unauthorizedCaller_withoutOnboardingRole() public {
        bytes32 entityId = keccak256("entity-register-unauthorized");
        // solhint-disable-next-line gas-small-strings
        address account = makeAddr("entity-register-unauthorized-caller");

        address[] memory unauthorizedCallers = new address[](5);
        unauthorizedCallers[0] = _erAdminOnly;
        unauthorizedCallers[1] = _erGuard;
        unauthorizedCallers[2] = _erWalletTransfer;
        unauthorizedCallers[3] = _notOwner;
        unauthorizedCallers[4] = account;

        bytes4 unauthorizedSelector = bytes4(keccak256("Unauthorized()"));
        for (uint256 i; i < unauthorizedCallers.length;) {
            vm.expectRevert(unauthorizedSelector);
            vm.prank(unauthorizedCallers[i]);
            _er.registerEntity(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF);
            unchecked {
                ++i;
            }
        }
    }

    function test_registerEntity_withAuthorityAndManagers_success() public {
        bytes32 entityId = keccak256("entity-register-with-access");
        address authority = makeAddr("entity-authority");
        address manager1 = makeAddr("entity-manager-1");
        address manager2 = makeAddr("entity-manager-2");
        address[] memory managers = new address[](2);
        managers[0] = manager1;
        managers[1] = manager2;

        vm.expectEmit(true, true, false, true);
        emit IEntityRegistry.EntityRegistered(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF);
        vm.expectEmit(true, true, true, true);
        emit IEntityRegistry.EntityAuthorityUpdated(entityId, address(0), authority);
        vm.expectEmit(true, true, true, true);
        emit IEntityRegistry.EntityManagerUpdated(entityId, manager1, true);
        vm.expectEmit(true, true, true, true);
        emit IEntityRegistry.EntityManagerUpdated(entityId, manager2, true);

        vm.prank(_erOnboarding);
        _er.registerEntity(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF, authority, managers);

        Entity memory entity = _er.getEntity(entityId);
        assertEq(entity.typeId, COMPANY_ENTITY);
        assertEq(uint8(entity.status), uint8(EntityStatus.ENABLED));
        assertEq(_er.getEntityAuthority(entityId), authority);
        assertTrue(_er.isEntityManager(entityId, manager1));
        assertTrue(_er.isEntityManager(entityId, manager2));
    }

    function test_registerEntity_withAuthorityAndManagers_reverts_zeroAuthority() public {
        bytes32 entityId = keccak256("entity-register-zero-authority");
        address[] memory managers = new address[](1);
        managers[0] = makeAddr("entity-manager");

        vm.prank(_erOnboarding);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _er.registerEntity(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF, address(0), managers);
    }

    function test_registerEntity_withAuthorityAndManagers_reverts_zeroManager() public {
        bytes32 entityId = keccak256("entity-register-zero-manager");
        address authority = makeAddr("entity-authority-zero-manager");
        address[] memory managers = new address[](2);
        managers[0] = makeAddr("entity-manager-ok");
        managers[1] = address(0);

        vm.prank(_erOnboarding);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _er.registerEntity(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF, authority, managers);
    }

    /*//////////////////////////////////////////////////////////////
                             registerEntityBatch
    //////////////////////////////////////////////////////////////*/

    function test_registerEntityBatch_success() public {
        bytes32[] memory ids = new bytes32[](2);
        uint256[] memory types = new uint256[](2);
        string[] memory refs = new string[](2);

        ids[0] = keccak256("batch-1");
        ids[1] = keccak256("batch-2");
        types[0] = COMPANY_ENTITY;
        types[1] = NATURAL_PERSON_ENTITY;
        refs[0] = "ipfs://batch-1";
        refs[1] = "ipfs://batch-2";

        vm.prank(_erOnboarding);
        _er.registerEntityBatch(ids, types, refs);

        assertEq(_er.getEntityTypeId(ids[0]), COMPANY_ENTITY);
        assertEq(_er.getEntityTypeId(ids[1]), NATURAL_PERSON_ENTITY);
    }

    function test_registerEntityBatch_reverts_lengthMismatch() public {
        bytes32[] memory ids = new bytes32[](2);
        uint256[] memory types = new uint256[](1);
        string[] memory refs = new string[](2);

        ids[0] = keccak256("mismatch-1");
        ids[1] = keccak256("mismatch-2");
        types[0] = COMPANY_ENTITY;
        refs[0] = "a";
        refs[1] = "b";

        vm.prank(_erOnboarding);
        vm.expectRevert(Errors.LengthMismatch.selector);
        _er.registerEntityBatch(ids, types, refs);
    }

    function test_registerEntityBatch_reverts_unauthorizedCaller_withoutOnboardingRole() public {
        address account = makeAddr("batch-unauthorized-caller");

        bytes32[] memory ids = new bytes32[](2);
        uint256[] memory types = new uint256[](2);
        string[] memory refs = new string[](2);

        ids[0] = keccak256("batch-unauthorized-1");
        ids[1] = keccak256("batch-unauthorized-2");
        types[0] = COMPANY_ENTITY;
        types[1] = NATURAL_PERSON_ENTITY;
        refs[0] = "ipfs://batch-unauthorized-1";
        refs[1] = "ipfs://batch-unauthorized-2";

        address[] memory unauthorizedCallers = new address[](5);
        unauthorizedCallers[0] = _erAdminOnly;
        unauthorizedCallers[1] = _erGuard;
        unauthorizedCallers[2] = _erWalletTransfer;
        unauthorizedCallers[3] = _notOwner;
        unauthorizedCallers[4] = account;

        bytes4 unauthorizedSelector = bytes4(keccak256("Unauthorized()"));
        for (uint256 i; i < unauthorizedCallers.length;) {
            vm.expectRevert(unauthorizedSelector);
            vm.prank(unauthorizedCallers[i]);
            _er.registerEntityBatch(ids, types, refs);
            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                               setEntityStatus
    //////////////////////////////////////////////////////////////*/

    function test_setEntityStatus_success() public {
        bytes32 entityId = keccak256("entity-status-success");
        _registerEntity(entityId);

        vm.expectEmit(true, false, false, true);
        emit IEntityRegistry.EntityStatusUpdated(entityId, EntityStatus.ENABLED, EntityStatus.DISABLED, "");

        vm.prank(_erGuard);
        _er.setEntityStatus(entityId, EntityStatus.DISABLED, "");

        assertEq(uint8(_er.getEntityStatus(entityId)), uint8(EntityStatus.DISABLED));
    }

    function test_setEntityStatus_storesReason() public {
        bytes32 entityId = keccak256("entity-status-reason");
        bytes memory reason = bytes("COMPLIANCE_BREACH");
        _registerEntity(entityId);

        vm.prank(_erAdmin);
        _er.setEntityStatus(entityId, EntityStatus.DISABLED, reason);

        assertEq(_er.getEntity(entityId).statusReason, reason);
    }

    function test_setEntityStatus_reverts_noneStatus() public {
        bytes32 entityId = keccak256("entity-status-none");
        _registerEntity(entityId);

        vm.prank(_erAdmin);
        vm.expectRevert(Errors.ER__EntityStatusNone.selector);
        _er.setEntityStatus(entityId, EntityStatus.NONE, "");
    }

    function test_setEntityStatus_reverts_entityNotRegistered() public {
        bytes32 notRegistered = keccak256("entity-status-not-registered");

        vm.prank(_erGuard);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotRegistered.selector, notRegistered));
        _er.setEntityStatus(notRegistered, EntityStatus.DISABLED, "");
    }

    function test_setEntityStatus_reverts_unauthorizedCaller_withoutGuardRole() public {
        bytes32 entityId = keccak256("entity-status-unauthorized");
        // solhint-disable-next-line gas-small-strings
        address account = makeAddr("entity-status-unauthorized-caller");
        _registerEntity(entityId);

        address[] memory unauthorizedCallers = new address[](5);
        unauthorizedCallers[0] = _erAdminOnly;
        unauthorizedCallers[1] = _erOnboarding;
        unauthorizedCallers[2] = _erWalletTransfer;
        unauthorizedCallers[3] = _notOwner;
        unauthorizedCallers[4] = account;

        bytes4 unauthorizedSelector = bytes4(keccak256("Unauthorized()"));
        for (uint256 i; i < unauthorizedCallers.length;) {
            vm.expectRevert(unauthorizedSelector);
            vm.prank(unauthorizedCallers[i]);
            _er.setEntityStatus(entityId, EntityStatus.DISABLED, "");
            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                              setEntityMetadata
    //////////////////////////////////////////////////////////////*/

    function test_setEntityMetadata_success() public {
        bytes32 entityId = keccak256("entity-set-metadata");
        _registerEntity(entityId);

        vm.prank(_erOnboarding);
        _er.setEntityMetadata(entityId, "ipfs://entity-meta");

        assertEq(_er.getEntityMetadataRef(entityId), "ipfs://entity-meta");
    }

    function test_setEntityMetadata_reverts_entityNotEnabled() public {
        bytes32 entityId = keccak256("entity-set-metadata-disabled");
        _registerEntity(entityId);

        vm.prank(_erGuard);
        _er.setEntityStatus(entityId, EntityStatus.DISABLED, "");

        vm.prank(_erOnboarding);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotEnabled.selector, entityId));
        _er.setEntityMetadata(entityId, "ipfs://disabled");
    }

    function test_setEntityMetadata_reverts_zeroEntityId() public {
        vm.prank(_erOnboarding);
        vm.expectRevert(Errors.ER__EntityIdZero.selector);
        _er.setEntityMetadata(bytes32(0), "ipfs://zero-entity");
    }

    function test_setEntityMetadata_reverts_unauthorizedCaller_withoutOnboardingRole() public {
        bytes32 entityId = keccak256("entity-set-metadata-unauthorized");
        address account = makeAddr("metadata-unauthorized-caller");
        _registerEntity(entityId);

        address[] memory unauthorizedCallers = new address[](5);
        unauthorizedCallers[0] = _erAdminOnly;
        unauthorizedCallers[1] = _erGuard;
        unauthorizedCallers[2] = _erWalletTransfer;
        unauthorizedCallers[3] = _notOwner;
        unauthorizedCallers[4] = account;

        bytes4 unauthorizedSelector = bytes4(keccak256("Unauthorized()"));
        for (uint256 i; i < unauthorizedCallers.length;) {
            vm.expectRevert(unauthorizedSelector);
            vm.prank(unauthorizedCallers[i]);
            _er.setEntityMetadata(entityId, "ipfs://unauthorized");
            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                              setEntityAuthority
    //////////////////////////////////////////////////////////////*/

    function test_setEntityAuthority_success_byAdmin() public {
        bytes32 entityId = keccak256("entity-authority-admin");
        address authority = makeAddr("authority");
        _registerEntity(entityId);

        vm.prank(_erAdminOnly);
        _er.setEntityAuthority(entityId, authority);

        assertEq(_er.getEntityAuthority(entityId), authority);
    }

    function test_setEntityAuthority_success_byAuthority() public {
        bytes32 entityId = keccak256("entity-authority-rotate");
        address authority = makeAddr("authority");
        address newAuthority = makeAddr("newAuthority");
        _registerEntity(entityId);

        vm.prank(_erAdminOnly);
        _er.setEntityAuthority(entityId, authority);

        vm.prank(authority);
        _er.setEntityAuthority(entityId, newAuthority);

        assertEq(_er.getEntityAuthority(entityId), newAuthority);
    }

    function test_setEntityAuthority_success_registeredEnabledAuthorityAccount() public {
        bytes32 entityId = keccak256("entity-auth-reg");
        address authority = makeAddr("registered-authority");
        address newAuthority = makeAddr("new-registered-authority");
        _registerEntity(entityId);
        _registerStandardAccount(entityId, authority);

        vm.prank(_erAdminOnly);
        _er.setEntityAuthority(entityId, authority);

        assertEq(_er.getEntityAuthority(entityId), authority);

        vm.prank(authority);
        _er.setEntityAuthority(entityId, newAuthority);

        assertEq(_er.getEntityAuthority(entityId), newAuthority);
    }

    function test_setEntityAuthority_success_refreshesStaleSameAuthorityAfterReenable() public {
        bytes32 entityId = keccak256("entity-auth-refresh-same");
        address authority = makeAddr("refresh-same-authority");
        address manager = makeAddr("refresh-same-manager");
        _registerEntity(entityId);
        _registerStandardAccount(entityId, authority);

        vm.prank(_erAdminOnly);
        _er.setEntityAuthority(entityId, authority);

        vm.prank(_erGuard);
        _er.setAccountStatus(authority, AccountStatus.DISABLED, "");
        vm.prank(_erGuard);
        _er.setAccountStatus(authority, AccountStatus.ENABLED, "");

        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__NotEntityAuthorityOrAdmin.selector, authority, entityId));
        _er.setEntityManager(entityId, manager, true);

        vm.prank(_erAdminOnly);
        vm.expectEmit(true, true, true, true);
        emit IEntityRegistry.EntityAuthorityUpdated(entityId, authority, authority);
        _er.setEntityAuthority(entityId, authority);

        vm.prank(authority);
        _er.setEntityManager(entityId, manager, true);

        assertEq(_er.getEntityAuthority(entityId), authority);
        assertTrue(_er.isEntityManager(entityId, manager));
    }

    function test_setEntityAuthority_reverts_zeroAddress() public {
        bytes32 entityId = keccak256("entity-authority-zero");
        _registerEntity(entityId);

        vm.prank(_erAdminOnly);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _er.setEntityAuthority(entityId, address(0));
    }

    function test_setEntityAuthority_reverts_sameAddressAlreadySet() public {
        bytes32 entityId = keccak256("entity-authority-same");
        address authority = makeAddr("authority");
        _registerEntity(entityId);

        vm.startPrank(_erAdminOnly);
        _er.setEntityAuthority(entityId, authority);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityAuthorityAlreadySet.selector, entityId, authority));
        _er.setEntityAuthority(entityId, authority);
        vm.stopPrank();
    }

    function test_setEntityAuthority_reverts_unauthorized() public {
        bytes32 entityId = keccak256("entity-authority-unauthorized");
        address authority = makeAddr("authority");
        address unauthorized = makeAddr("unauthorized");
        _registerEntity(entityId);

        vm.prank(_erAdminOnly);
        _er.setEntityAuthority(entityId, authority);

        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__NotEntityAuthorityOrAdmin.selector, unauthorized, entityId));
        _er.setEntityAuthority(entityId, makeAddr("newAuthority"));
    }

    function test_setEntityAuthority_reverts_disabledRegisteredAuthorityAccount() public {
        bytes32 entityId = keccak256("entity-auth-disabled");
        address authority = makeAddr("disabled-registered-authority");
        _registerEntity(entityId);
        _registerStandardAccount(entityId, authority);

        vm.prank(_erGuard);
        _er.setAccountStatus(authority, AccountStatus.DISABLED, "");

        vm.prank(_erAdminOnly);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ER__EntityAuthorityAccountNotEnabled.selector, authority, entityId)
        );
        _er.setEntityAuthority(entityId, authority);
    }

    function test_setEntityAuthority_reverts_registeredAuthorityAccountLinkedToAnotherEntity() public {
        bytes32 managedEntity = keccak256("entity-auth-x-managed");
        bytes32 linkedEntity = keccak256("entity-auth-x-account");
        address authority = makeAddr("x-linked-auth");
        _registerEntity(managedEntity);
        _registerEntity(linkedEntity);
        _registerStandardAccount(linkedEntity, authority);

        vm.prank(_erAdminOnly);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ER__EntityAuthorityAccountLinkedToDifferentEntity.selector,
                authority,
                managedEntity,
                linkedEntity
            )
        );
        _er.setEntityAuthority(managedEntity, authority);
    }

    function test_setEntityAuthority_reverts_disabledCurrentAuthorityCannotRotate() public {
        bytes32 entityId = keccak256("entity-auth-disabled-current");
        address authority = makeAddr("disabled-current-authority");
        address newAuthority = makeAddr("disabled-current-new-authority");
        _registerEntity(entityId);
        _registerStandardAccount(entityId, authority);

        vm.prank(_erAdminOnly);
        _er.setEntityAuthority(entityId, authority);

        vm.prank(_erGuard);
        _er.setAccountStatus(authority, AccountStatus.DISABLED, "");

        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__NotEntityAuthorityOrAdmin.selector, authority, entityId));
        _er.setEntityAuthority(entityId, newAuthority);
    }

    function test_setEntityAuthority_reverts_removedSourceAuthorityCannotManageOldEntity() public {
        bytes32 entityId = keccak256("entity-auth-remove-own");
        address authority = makeAddr("removed-own-entity-authority");
        address replacementAuthority = makeAddr("removed-repl-auth");
        address newManager = makeAddr("removed-own-entity-manager");
        _registerEntity(entityId);
        _registerStandardAccount(entityId, authority);

        vm.startPrank(_erAdminOnly);
        _er.setEntityAuthority(entityId, authority);
        _er.setEntityAuthority(entityId, replacementAuthority);
        vm.stopPrank();

        vm.prank(_erWalletTransfer);
        _er.removeAccount(authority, "");

        assertEq(_er.getEntityAuthority(entityId), replacementAuthority);

        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__NotEntityAuthorityOrAdmin.selector, authority, entityId));
        _er.setEntityManager(entityId, newManager, true);
    }

    function test_setEntityAuthority_reverts_transferredSourceAuthorityCannotManageOldEntity() public {
        bytes32 oldEntityId = keccak256("entity-auth-transfer-old");
        bytes32 newEntityId = keccak256("entity-auth-transfer-new");
        address authority = makeAddr("transferred-own-entity-authority");
        address replacementAuthority = makeAddr("xferred-repl-auth");
        address newManager = makeAddr("transferred-own-entity-manager");
        _registerEntity(oldEntityId);
        _registerEntity(newEntityId);
        _registerStandardAccount(oldEntityId, authority);

        vm.startPrank(_erAdminOnly);
        _er.setEntityAuthority(oldEntityId, authority);
        _er.setEntityAuthority(oldEntityId, replacementAuthority);
        vm.stopPrank();

        vm.prank(_erWalletTransfer);
        _er.transferAccountToEntity(authority, newEntityId);

        assertEq(_er.getEntityAuthority(oldEntityId), replacementAuthority);
        assertEq(_er.getEntityId(authority), newEntityId);

        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__NotEntityAuthorityOrAdmin.selector, authority, oldEntityId));
        _er.setEntityManager(oldEntityId, newManager, true);
    }

    function test_setEntityAuthority_reverts_removedAuthorityAccountCannotManageStaleTargetEntity() public {
        bytes32 sourceEntityId = keccak256("entity-authority-remove-source");
        bytes32 targetEntityId = keccak256("entity-authority-remove-target");
        address authority = makeAddr("removed-cross-entity-authority");
        address newManager = makeAddr("removed-authority-new-manager");
        _registerEntity(sourceEntityId);
        _registerEntity(targetEntityId);

        vm.prank(_erAdminOnly);
        _er.setEntityAuthority(targetEntityId, authority);

        _registerStandardAccount(sourceEntityId, authority);

        vm.prank(_erWalletTransfer);
        _er.removeAccount(authority, "");

        vm.prank(authority);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ER__NotEntityAuthorityOrAdmin.selector, authority, targetEntityId)
        );
        _er.setEntityManager(targetEntityId, newManager, true);
    }

    function test_setEntityAuthority_reverts_transferredAuthorityAccountCannotManageStaleTargetEntity() public {
        bytes32 sourceEntityId = keccak256("entity-authority-transfer-source");
        bytes32 targetEntityId = keccak256("entity-authority-transfer-target");
        address authority = makeAddr("xferred-xentity-auth");
        address newManager = makeAddr("xferred-auth-manager");
        _registerEntity(sourceEntityId);
        _registerEntity(targetEntityId);

        vm.prank(_erAdminOnly);
        _er.setEntityAuthority(targetEntityId, authority);

        _registerStandardAccount(sourceEntityId, authority);

        vm.prank(_erWalletTransfer);
        _er.transferAccountToEntity(authority, targetEntityId);

        vm.prank(authority);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ER__NotEntityAuthorityOrAdmin.selector, authority, targetEntityId)
        );
        _er.setEntityManager(targetEntityId, newManager, true);
    }

    function test_setEntityAuthority_reverts_entityNotRegistered() public {
        bytes32 entityId = keccak256("entity-authority-missing");

        vm.prank(_erAdminOnly);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotRegistered.selector, entityId));
        _er.setEntityAuthority(entityId, makeAddr("authority"));
    }

    /*//////////////////////////////////////////////////////////////
                               setEntityManager
    //////////////////////////////////////////////////////////////*/

    function test_setEntityManager_success_byAdmin() public {
        bytes32 entityId = keccak256("entity-manager-admin");
        address manager = makeAddr("manager");
        _registerEntity(entityId);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, manager, true);

        assertTrue(_er.isEntityManager(entityId, manager));
    }

    function test_setEntityManager_success_disableByAdmin() public {
        bytes32 entityId = keccak256("entity-manager-disable-admin");
        address manager = makeAddr("disabled-by-admin-manager");
        _registerEntity(entityId);

        vm.startPrank(_erAdminOnly);
        _er.setEntityManager(entityId, manager, true);
        _er.setEntityManager(entityId, manager, false);
        vm.stopPrank();

        assertFalse(_er.isEntityManager(entityId, manager));
    }

    function test_setEntityManager_success_byAuthority() public {
        bytes32 entityId = keccak256("entity-manager-authority");
        address authority = makeAddr("authority");
        address manager = makeAddr("manager");
        _registerEntity(entityId);

        vm.prank(_erAdminOnly);
        _er.setEntityAuthority(entityId, authority);

        vm.prank(authority);
        _er.setEntityManager(entityId, manager, true);

        assertTrue(_er.isEntityManager(entityId, manager));
    }

    function test_setEntityManager_success_registeredEnabledManagerAccount() public {
        bytes32 entityId = keccak256("entity-manager-reg-account");
        address manager = makeAddr("registered-manager");
        _registerEntity(entityId);
        _registerStandardAccount(entityId, manager);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, manager, true);

        assertTrue(_er.isEntityManager(entityId, manager));
    }

    function test_setEntityManager_reverts_zeroAddress() public {
        bytes32 entityId = keccak256("entity-manager-zero");
        _registerEntity(entityId);

        vm.prank(_erAdminOnly);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _er.setEntityManager(entityId, address(0), true);
    }

    function test_setEntityManager_reverts_entityNotRegistered() public {
        bytes32 entityId = keccak256("entity-manager-missing");

        vm.prank(_erAdminOnly);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotRegistered.selector, entityId));
        _er.setEntityManager(entityId, makeAddr("manager"), true);
    }

    function test_setEntityManager_reverts_disabledRegisteredManagerAccount() public {
        bytes32 entityId = keccak256("entity-manager-disabled-account");
        address manager = makeAddr("disabled-registered-manager");
        _registerEntity(entityId);
        _registerStandardAccount(entityId, manager);

        vm.prank(_erGuard);
        _er.setAccountStatus(manager, AccountStatus.DISABLED, "");

        vm.prank(_erAdminOnly);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityManagerAccountNotEnabled.selector, manager, entityId));
        _er.setEntityManager(entityId, manager, true);
    }

    function test_setEntityManager_reverts_registeredManagerAccountLinkedToAnotherEntity() public {
        bytes32 managedEntity = keccak256("manager-xlink-managed");
        bytes32 linkedEntity = keccak256("manager-xlink-account");
        address manager = makeAddr("cross-linked-registered-manager");
        _registerEntity(managedEntity);
        _registerEntity(linkedEntity);
        _registerStandardAccount(linkedEntity, manager);

        vm.prank(_erAdminOnly);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ER__EntityManagerAccountLinkedToDifferentEntity.selector, manager, managedEntity, linkedEntity
            )
        );
        _er.setEntityManager(managedEntity, manager, true);
    }

    /*//////////////////////////////////////////////////////////////
                               registerAccount
    //////////////////////////////////////////////////////////////*/

    function test_registerAccount_reverts_entityManagerMustRequestAcceptance() public {
        bytes32 entityId = keccak256("entity-register-manager-reverts");
        address entityManager = makeAddr("entityManager");
        address owner = makeAddr("owner");

        vm.prank(_erOnboarding);
        _er.registerEntity(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF);
        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, entityManager, true);

        address wallet = _createCompanyWallet(entityId, owner, entityManager);

        vm.prank(entityManager);
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        _er.registerAccount(wallet, entityId, ROLE_FLAGS_EMPTY);

        assertFalse(_er.isAccountRegistered(wallet));
        assertFalse(_er.isAccountEnabled(wallet));
    }

    /*//////////////////////////////////////////////////////////////
                         requestAccountRegistration
    //////////////////////////////////////////////////////////////*/

    function test_requestAccountRegistration_success_byRegisteredEnabledEntityManager() public {
        bytes32 entityId = keccak256("register-reg-manager");
        address entityManager = makeAddr("registeredEntityManager");
        address owner = makeAddr("registeredManagerOwner");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, entityManager);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, entityManager, true);

        address wallet = _createCompanyWallet(entityId, owner, entityManager);

        vm.prank(entityManager);
        _er.requestAccountRegistration(wallet, entityId, ROLE_FLAGS_EMPTY);

        vm.prank(wallet);
        _er.acceptAccountRegistration(entityId);

        assertTrue(_er.isAccountRegistered(wallet));
        assertTrue(_er.isAccountEnabled(wallet));
    }

    function test_registerAccount_success_standardByAdmin() public {
        bytes32 entityId = keccak256("entity-register-standard");
        address account = makeAddr("protocolAccount");
        _registerEntity(entityId);

        vm.prank(_erAdminOnly);
        _er.registerAccount(account, entityId, ROLE_FLAGS_EMPTY);

        RegistryAccount memory accountData = _er.getAccount(account);
        assertEq(accountData.entityId, entityId);
    }

    function test_registerAccount_reverts_unauthorizedCaller_withoutAdminRole() public {
        bytes32 entityId = keccak256("entity-register-not-admin");
        address owner = makeAddr("owner");

        vm.prank(_erOnboarding);
        _er.registerEntity(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF);
        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, _erAdminOnly, true);

        address wallet = _createCompanyWallet(entityId, owner, _erAdminOnly);

        vm.prank(_notOwner);
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        _er.registerAccount(wallet, entityId, ROLE_FLAGS_EMPTY);
    }

    function test_registerAccount_reverts_alreadyRegistered() public {
        bytes32 entityId = keccak256("entity-account-duplicate");
        address account = makeAddr("duplicate-account");

        _registerEntity(entityId);

        vm.prank(_erAdminOnly);
        _er.registerAccount(account, entityId, ROLE_FLAGS_EMPTY);

        vm.prank(_erAdminOnly);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__AccountAlreadyRegistered.selector, account));
        _er.registerAccount(account, entityId, ROLE_FLAGS_EMPTY);
    }

    function test_registerAccount_reverts_entityNotRegistered() public {
        bytes32 missingEntity = keccak256("entity-account-missing");
        address account = makeAddr("entity-account-missing-account");

        vm.prank(_erAdminOnly);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotRegistered.selector, missingEntity));
        _er.registerAccount(account, missingEntity, ROLE_FLAGS_EMPTY);
    }

    function test_registerAccount_reverts_zeroEntityId() public {
        address account = makeAddr("entity-account-zero-entity");

        vm.prank(_erAdminOnly);
        vm.expectRevert(Errors.ER__EntityIdZero.selector);
        _er.registerAccount(account, bytes32(0), ROLE_FLAGS_EMPTY);
    }

    function test_registerAccount_reverts_entityNotEnabled() public {
        bytes32 entityId = keccak256("entity-account-disabled");
        address account = makeAddr("entity-account-disabled-account");

        _registerEntity(entityId);

        vm.prank(_erGuard);
        _er.setEntityStatus(entityId, EntityStatus.DISABLED, "");

        vm.prank(_erAdminOnly);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotEnabled.selector, entityId));
        _er.registerAccount(account, entityId, ROLE_FLAGS_EMPTY);
    }

    function test_requestAccountRegistration_reverts_disabledManagerAccountAuthorityRevoked() public {
        bytes32 entityId = keccak256("entity-register-disabled-manager");
        address manager = makeAddr("disabled-manager-account");
        address account = makeAddr("disabled-manager-new-account");
        _registerEntity(entityId);
        _registerStandardAccount(entityId, manager);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, manager, true);
        assertTrue(_er.isEntityManager(entityId, manager));

        vm.prank(_erGuard);
        _er.setAccountStatus(manager, AccountStatus.DISABLED, "");

        assertFalse(_er.isEntityManager(entityId, manager));

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__NotEntityManagerOrAdmin.selector, manager, entityId));
        _er.requestAccountRegistration(account, entityId, ROLE_FLAGS_EMPTY);
    }

    function test_requestAccountRegistration_reverts_removedManagerAccountAuthorityRevoked() public {
        bytes32 entityId = keccak256("entity-register-removed-manager");
        address manager = makeAddr("removed-manager-account");
        address account = makeAddr("removed-manager-new-account");
        _registerEntity(entityId);
        _registerStandardAccount(entityId, manager);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, manager, true);
        assertTrue(_er.isEntityManager(entityId, manager));

        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, manager, false);

        vm.prank(_erWalletTransfer);
        _er.removeAccount(manager, "");

        assertFalse(_er.isEntityManager(entityId, manager));

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__NotEntityManagerOrAdmin.selector, manager, entityId));
        _er.requestAccountRegistration(account, entityId, ROLE_FLAGS_EMPTY);
    }

    function test_requestAccountRegistration_reverts_transferredManagerAccountAuthorityRevokedForOldEntity() public {
        bytes32 oldEntityId = keccak256("reg-manager-transfer-old");
        bytes32 newEntityId = keccak256("reg-manager-transfer-new");
        address manager = makeAddr("transferred-manager-account");
        address account = makeAddr("transferred-manager-new-account");
        _registerEntity(oldEntityId);
        _registerEntity(newEntityId);
        _registerStandardAccount(oldEntityId, manager);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(oldEntityId, manager, true);
        assertTrue(_er.isEntityManager(oldEntityId, manager));

        vm.prank(_erAdminOnly);
        _er.setEntityManager(oldEntityId, manager, false);

        vm.prank(_erWalletTransfer);
        _er.transferAccountToEntity(manager, newEntityId);

        assertFalse(_er.isEntityManager(oldEntityId, manager));
        assertEq(_er.getEntityId(manager), newEntityId);

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__NotEntityManagerOrAdmin.selector, manager, oldEntityId));
        _er.requestAccountRegistration(account, oldEntityId, ROLE_FLAGS_EMPTY);
    }

    function test_requestAccountRegistration_reverts_removedManagerAccountCannotRegainStaleTargetAuthority() public {
        bytes32 sourceEntityId = keccak256("stale-mgr-remove-src");
        bytes32 targetEntityId = keccak256("stale-mgr-remove-dst");
        address manager = makeAddr("removed-stale-x-mgr");
        address account = makeAddr("removed-mgr-new-acct");
        _registerEntity(sourceEntityId);
        _registerEntity(targetEntityId);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(targetEntityId, manager, true);
        assertTrue(_er.isEntityManager(targetEntityId, manager));

        _registerStandardAccount(sourceEntityId, manager);
        assertFalse(_er.isEntityManager(targetEntityId, manager));

        vm.prank(_erWalletTransfer);
        _er.removeAccount(manager, "");

        assertFalse(_er.isEntityManager(targetEntityId, manager));

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__NotEntityManagerOrAdmin.selector, manager, targetEntityId));
        _er.requestAccountRegistration(account, targetEntityId, ROLE_FLAGS_EMPTY);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(targetEntityId, manager, true);

        assertTrue(_er.isEntityManager(targetEntityId, manager));
    }

    function test_requestAccountRegistration_reverts_transferredManagerAccountCannotRegainStaleTargetAuthority()
        public
    {
        bytes32 sourceEntityId = keccak256("stale-mgr-xfer-src");
        bytes32 targetEntityId = keccak256("stale-mgr-xfer-dst");
        address manager = makeAddr("xferred-stale-x-mgr");
        address account = makeAddr("xferred-mgr-new-acct");
        _registerEntity(sourceEntityId);
        _registerEntity(targetEntityId);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(targetEntityId, manager, true);
        assertTrue(_er.isEntityManager(targetEntityId, manager));

        _registerStandardAccount(sourceEntityId, manager);
        assertFalse(_er.isEntityManager(targetEntityId, manager));

        vm.prank(_erWalletTransfer);
        _er.transferAccountToEntity(manager, targetEntityId);

        assertFalse(_er.isEntityManager(targetEntityId, manager));

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__NotEntityManagerOrAdmin.selector, manager, targetEntityId));
        _er.requestAccountRegistration(account, targetEntityId, ROLE_FLAGS_EMPTY);
    }

    function test_requestAccountRegistration_success_byEntityManager() public {
        bytes32 entityId = keccak256("entity-request-account");
        address entityManager = makeAddr("request-manager");
        address account = makeAddr("request-account");

        _registerEntity(entityId);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, entityManager, true);

        vm.expectEmit(true, true, true, true);
        emit IEntityRegistry.AccountRegistrationRequested(account, entityId, ROLE_FLAGS_UPDATED, entityManager);

        vm.prank(entityManager);
        _er.requestAccountRegistration(account, entityId, ROLE_FLAGS_UPDATED);

        PendingAccountRegistration memory pending = _er.getPendingAccountRegistration(account, entityId);
        assertEq(pending.roleFlags, ROLE_FLAGS_UPDATED);
        assertEq(pending.requester, entityManager);
        assertFalse(_er.isAccountRegistered(account));
        assertFalse(_er.isAccountEnabled(account));
    }

    function test_requestAccountRegistration_success_byAdmin() public {
        bytes32 entityId = keccak256("entity-request-account-admin");
        address account = makeAddr("request-admin-account");

        _registerEntity(entityId);

        vm.expectEmit(true, true, true, true);
        emit IEntityRegistry.AccountRegistrationRequested(account, entityId, ROLE_FLAGS_UPDATED, _erAdminOnly);

        vm.prank(_erAdminOnly);
        _er.requestAccountRegistration(account, entityId, ROLE_FLAGS_UPDATED);

        PendingAccountRegistration memory pending = _er.getPendingAccountRegistration(account, entityId);
        assertEq(pending.roleFlags, ROLE_FLAGS_UPDATED);
        assertEq(pending.requester, _erAdminOnly);
        assertFalse(_er.isAccountRegistered(account));
        assertFalse(_er.isAccountEnabled(account));
    }

    function test_requestAccountRegistration_success_updatesExistingRequestForSameEntity() public {
        bytes32 entityId = keccak256("entity-request-update");
        address firstManager = makeAddr("request-update-first-manager");
        address secondManager = makeAddr("request-update-second-manager");
        address account = makeAddr("request-update-account");

        _registerEntity(entityId);

        vm.startPrank(_erAdminOnly);
        _er.setEntityManager(entityId, firstManager, true);
        _er.setEntityManager(entityId, secondManager, true);
        vm.stopPrank();

        vm.prank(firstManager);
        _er.requestAccountRegistration(account, entityId, ROLE_FLAGS_INITIAL);

        vm.prank(secondManager);
        _er.requestAccountRegistration(account, entityId, ROLE_FLAGS_UPDATED);

        PendingAccountRegistration memory pending = _er.getPendingAccountRegistration(account, entityId);
        assertEq(pending.roleFlags, ROLE_FLAGS_UPDATED);
        assertEq(pending.requester, secondManager);

        vm.prank(account);
        _er.acceptAccountRegistration(entityId);

        RegistryAccount memory accountData = _er.getAccount(account);
        assertEq(accountData.entityId, entityId);
        assertEq(accountData.roleFlags, ROLE_FLAGS_UPDATED);
    }

    function test_requestAccountRegistration_success_doesNotBlockOtherEntityRequest() public {
        bytes32 squattingEntity = keccak256("squatting-entity-request");
        bytes32 intendedEntity = keccak256("intended-entity-request");
        address squattingManager = makeAddr("squatting-manager");
        address intendedManager = makeAddr("intended-manager");
        address account = makeAddr("squatted-account");

        _registerEntity(squattingEntity);
        _registerEntity(intendedEntity);

        vm.startPrank(_erAdminOnly);
        _er.setEntityManager(squattingEntity, squattingManager, true);
        _er.setEntityManager(intendedEntity, intendedManager, true);
        vm.stopPrank();

        vm.prank(squattingManager);
        _er.requestAccountRegistration(account, squattingEntity, ROLE_FLAGS_EMPTY);

        vm.prank(intendedManager);
        _er.requestAccountRegistration(account, intendedEntity, ROLE_FLAGS_UPDATED);

        vm.prank(account);
        _er.acceptAccountRegistration(intendedEntity);

        RegistryAccount memory accountData = _er.getAccount(account);
        assertEq(accountData.entityId, intendedEntity);
        assertEq(accountData.roleFlags, ROLE_FLAGS_UPDATED);
    }

    function test_requestAccountRegistration_success_staleRequestCanBeAcceptedAfterAccountRemoval() public {
        bytes32 firstEntity = keccak256("first-pending-entity");
        bytes32 secondEntity = keccak256("second-pending-entity");
        address firstManager = makeAddr("first-pending-manager");
        address secondManager = makeAddr("second-pending-manager");
        address account = makeAddr("multi-pending-account");

        _registerEntity(firstEntity);
        _registerEntity(secondEntity);

        vm.startPrank(_erAdminOnly);
        _er.setEntityManager(firstEntity, firstManager, true);
        _er.setEntityManager(secondEntity, secondManager, true);
        vm.stopPrank();

        vm.prank(firstManager);
        _er.requestAccountRegistration(account, firstEntity, ROLE_FLAGS_INITIAL);

        vm.prank(secondManager);
        _er.requestAccountRegistration(account, secondEntity, ROLE_FLAGS_UPDATED);

        vm.prank(account);
        _er.acceptAccountRegistration(firstEntity);

        PendingAccountRegistration memory acceptedPending = _er.getPendingAccountRegistration(account, firstEntity);
        PendingAccountRegistration memory stalePending = _er.getPendingAccountRegistration(account, secondEntity);
        assertEq(acceptedPending.requester, address(0));
        assertEq(acceptedPending.roleFlags, 0);
        assertEq(stalePending.requester, secondManager);
        assertEq(stalePending.roleFlags, ROLE_FLAGS_UPDATED);

        vm.prank(account);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__AccountAlreadyRegistered.selector, account));
        _er.acceptAccountRegistration(secondEntity);

        vm.prank(_erWalletTransfer);
        _er.removeAccount(account, "");

        vm.prank(account);
        _er.acceptAccountRegistration(secondEntity);

        RegistryAccount memory accountData = _er.getAccount(account);
        assertEq(accountData.entityId, secondEntity);
        assertEq(accountData.roleFlags, ROLE_FLAGS_UPDATED);
    }

    function test_requestAccountRegistration_reverts_unauthorizedCaller_withoutManagerOrAdminRole() public {
        bytes32 entityId = keccak256("entity-request-unauthorized");
        address account = makeAddr("req-unauth-account");

        _registerEntity(entityId);

        vm.prank(_notOwner);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__NotEntityManagerOrAdmin.selector, _notOwner, entityId));
        _er.requestAccountRegistration(account, entityId, ROLE_FLAGS_EMPTY);
    }

    function test_requestAccountRegistration_reverts_alreadyRegistered() public {
        bytes32 entityId = keccak256("entity-request-already");
        address account = makeAddr("req-already-account");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, account);

        vm.prank(_erAdminOnly);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__AccountAlreadyRegistered.selector, account));
        _er.requestAccountRegistration(account, entityId, ROLE_FLAGS_EMPTY);
    }

    function test_requestAccountRegistration_reverts_zeroEntityId() public {
        address account = makeAddr("request-zero-entity-account");

        vm.prank(_erAdminOnly);
        vm.expectRevert(Errors.ER__EntityIdZero.selector);
        _er.requestAccountRegistration(account, bytes32(0), ROLE_FLAGS_EMPTY);
    }

    function test_requestAccountRegistration_reverts_entityNotRegistered() public {
        bytes32 missingEntity = keccak256("request-missing-entity");
        address account = makeAddr("request-missing-entity-account");

        vm.prank(_erAdminOnly);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotRegistered.selector, missingEntity));
        _er.requestAccountRegistration(account, missingEntity, ROLE_FLAGS_EMPTY);
    }

    function test_requestAccountRegistration_reverts_entityNotEnabled() public {
        bytes32 entityId = keccak256("request-disabled-entity");
        address account = makeAddr("request-disabled-entity-account");

        _registerEntity(entityId);

        vm.prank(_erGuard);
        _er.setEntityStatus(entityId, EntityStatus.DISABLED, "");

        vm.prank(_erAdminOnly);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotEnabled.selector, entityId));
        _er.requestAccountRegistration(account, entityId, ROLE_FLAGS_EMPTY);
    }

    function test_requestAccountRegistration_reverts_zeroAddress() public {
        bytes32 entityId = keccak256("entity-request-zero-account");

        _registerEntity(entityId);

        vm.prank(_erAdminOnly);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _er.requestAccountRegistration(address(0), entityId, ROLE_FLAGS_EMPTY);
    }

    /*//////////////////////////////////////////////////////////////
                         acceptAccountRegistration
    //////////////////////////////////////////////////////////////*/

    function test_acceptAccountRegistration_success_byExternallyOwnedAccount() public {
        bytes32 entityId = keccak256("entity-accept-eoa");
        address entityManager = makeAddr("entity-accept-manager");
        address account = makeAddr("entity-accept-account");

        _registerEntity(entityId);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, entityManager, true);

        vm.prank(entityManager);
        _er.requestAccountRegistration(account, entityId, ROLE_FLAGS_UPDATED);

        vm.expectEmit(true, true, true, true);
        emit IEntityRegistry.AccountRegistered(account, entityId, ROLE_FLAGS_UPDATED);
        vm.expectEmit(true, true, true, true);
        emit IEntityRegistry.AccountRegistrationAccepted(account, entityId, ROLE_FLAGS_UPDATED, entityManager);

        vm.prank(account);
        _er.acceptAccountRegistration(entityId);

        RegistryAccount memory accountData = _er.getAccount(account);
        assertEq(accountData.entityId, entityId);
        assertEq(accountData.roleFlags, ROLE_FLAGS_UPDATED);
        assertTrue(_er.isAccountEnabled(account));

        PendingAccountRegistration memory pending = _er.getPendingAccountRegistration(account, entityId);
        assertEq(pending.requester, address(0));
        assertEq(pending.roleFlags, 0);
    }

    function test_acceptAccountRegistration_success_byCompanyWalletExecution() public {
        bytes32 entityId = keccak256("entity-accept-wallet");
        address entityManager = makeAddr("entity-accept-wallet-manager");
        address owner = makeAddr("entity-accept-wallet-owner");

        vm.prank(_erOnboarding);
        _er.registerEntity(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF);
        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, entityManager, true);

        address wallet = _createCompanyWallet(entityId, owner, entityManager);

        _requestAndAcceptWalletAccountRegistration(entityManager, wallet, entityId, owner, ROLE_FLAGS_EMPTY);

        assertTrue(_er.isAccountRegistered(wallet));
        assertTrue(_er.isAccountEnabled(wallet));
    }

    function test_acceptAccountRegistration_reverts_zeroEntityId() public {
        address account = makeAddr("accept-zero-entity-account");

        vm.prank(account);
        vm.expectRevert(Errors.ER__EntityIdZero.selector);
        _er.acceptAccountRegistration(bytes32(0));
    }

    function test_acceptAccountRegistration_reverts_entityNotRegistered() public {
        bytes32 missingEntity = keccak256("accept-missing-entity");
        address account = makeAddr("accept-missing-entity-account");

        vm.prank(account);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotRegistered.selector, missingEntity));
        _er.acceptAccountRegistration(missingEntity);
    }

    function test_acceptAccountRegistration_reverts_entityNotEnabled() public {
        bytes32 entityId = keccak256("accept-disabled-entity");
        address entityManager = makeAddr("accept-disabled-manager");
        address account = makeAddr("accept-disabled-account");

        _registerEntity(entityId);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, entityManager, true);

        vm.prank(entityManager);
        _er.requestAccountRegistration(account, entityId, ROLE_FLAGS_EMPTY);

        vm.prank(_erGuard);
        _er.setEntityStatus(entityId, EntityStatus.DISABLED, "");

        vm.prank(account);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotEnabled.selector, entityId));
        _er.acceptAccountRegistration(entityId);
    }

    function test_acceptAccountRegistration_reverts_notPending() public {
        bytes32 entityId = keccak256("entity-accept-missing");
        address account = makeAddr("entity-accept-missing-account");

        _registerEntity(entityId);

        vm.prank(account);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__AccountRegistrationNotPending.selector, account, entityId));
        _er.acceptAccountRegistration(entityId);
    }

    function test_acceptAccountRegistration_reverts_alreadyRegistered() public {
        bytes32 entityId = keccak256("entity-accept-already-registered");
        address account = makeAddr("accept-already-account");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, account);

        vm.prank(account);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__AccountAlreadyRegistered.selector, account));
        _er.acceptAccountRegistration(entityId);
    }

    function test_acceptAccountRegistration_reverts_whenRequesterNoLongerAuthorized() public {
        bytes32 entityId = keccak256("entity-accept-requester-disabled");
        address entityManager = makeAddr("entity-accept-disabled-manager");
        address account = makeAddr("entity-accept-disabled-account");

        _registerEntity(entityId);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, entityManager, true);

        vm.prank(entityManager);
        _er.requestAccountRegistration(account, entityId, ROLE_FLAGS_EMPTY);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, entityManager, false);

        vm.prank(account);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__NotEntityManagerOrAdmin.selector, entityManager, entityId));
        _er.acceptAccountRegistration(entityId);
    }

    /*//////////////////////////////////////////////////////////////
                              setAccountStatus
    //////////////////////////////////////////////////////////////*/

    function test_setAccountStatus_success() public {
        bytes32 entityId = keccak256("entity-status");
        address manager = makeAddr("manager");
        address owner = makeAddr("owner");

        vm.prank(_erOnboarding);
        _er.registerEntity(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF);
        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, manager, true);

        address wallet = _createCompanyWallet(entityId, owner, manager);

        _requestAndAcceptWalletAccountRegistration(manager, wallet, entityId, owner, ROLE_FLAGS_EMPTY);

        vm.prank(_erGuard);
        _er.setAccountStatus(wallet, AccountStatus.DISABLED, "");

        assertFalse(_er.isAccountEnabled(wallet));
    }

    function test_setAccountStatus_storesReason() public {
        bytes32 entityId = keccak256("entity-account-status-reason");
        address manager = makeAddr("manager-reason");
        address owner = makeAddr("owner-reason");
        bytes memory reason = bytes("KYC_EXPIRED");

        vm.startPrank(_erAdmin);
        _er.registerEntity(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF);
        _er.setEntityManager(entityId, manager, true);
        vm.stopPrank();

        address wallet = _createCompanyWallet(entityId, owner, manager);

        _requestAndAcceptWalletAccountRegistration(manager, wallet, entityId, owner, ROLE_FLAGS_EMPTY);

        vm.prank(_erAdmin);
        _er.setAccountStatus(wallet, AccountStatus.DISABLED, reason);

        assertEq(_er.getAccount(wallet).statusReason, reason);
    }

    function test_setAccountStatus_reverts_notRegistered() public {
        address unknown = makeAddr("unknown-account");

        vm.prank(_erGuard);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__AccountNotRegistered.selector, unknown));
        _er.setAccountStatus(unknown, AccountStatus.DISABLED, "");
    }

    function test_setAccountStatus_reverts_unauthorizedCaller_withoutGuardRole() public {
        // solhint-disable-next-line gas-small-strings
        bytes32 entityId = keccak256("entity-account-status-unauthorized");
        address account = makeAddr("account-status-unauthorized");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, account);

        address[] memory unauthorizedCallers = new address[](5);
        unauthorizedCallers[0] = _erAdminOnly;
        unauthorizedCallers[1] = _erOnboarding;
        unauthorizedCallers[2] = _erWalletTransfer;
        unauthorizedCallers[3] = _notOwner;
        unauthorizedCallers[4] = account;

        bytes4 unauthorizedSelector = bytes4(keccak256("Unauthorized()"));
        for (uint256 i; i < unauthorizedCallers.length;) {
            vm.expectRevert(unauthorizedSelector);
            vm.prank(unauthorizedCallers[i]);
            _er.setAccountStatus(account, AccountStatus.DISABLED, "");
            unchecked {
                ++i;
            }
        }
    }

    function test_setAccountStatus_reverts_zeroAddress() public {
        vm.prank(_erGuard);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _er.setAccountStatus(address(0), AccountStatus.DISABLED, "");
    }

    function test_setAccountStatus_reverts_noneStatus() public {
        bytes32 entityId = keccak256("entity-account-status-none");
        address account = makeAddr("account-status-none");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, account);

        vm.prank(_erGuard);
        vm.expectRevert(Errors.ER__AccountStatusNone.selector);
        _er.setAccountStatus(account, AccountStatus.NONE, "");
    }

    function test_setAccountStatus_reverts_whenEntityDisabled() public {
        bytes32 entityId = keccak256("entity-account-status-disabled");
        address account = makeAddr("account-status-disabled");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, account);

        vm.prank(_erGuard);
        _er.setEntityStatus(entityId, EntityStatus.DISABLED, "");

        vm.prank(_erGuard);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotEnabled.selector, entityId));
        _er.setAccountStatus(account, AccountStatus.DISABLED, "");
    }

    /*//////////////////////////////////////////////////////////////
                            setAccountRoleFlags
    //////////////////////////////////////////////////////////////*/

    function test_setAccountRoleFlags_success() public {
        bytes32 entityId = keccak256("entity-account-role-flags");
        address account = makeAddr("account-role-flags");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, account);

        vm.prank(_erOnboarding);
        _er.setAccountRoleFlags(account, ROLE_FLAGS_UPDATED);

        RegistryAccount memory updated = _er.getAccount(account);
        assertEq(updated.roleFlags, ROLE_FLAGS_UPDATED);
    }

    function test_setAccountRoleFlags_reverts_notRegistered() public {
        address unknown = makeAddr("unknown-account");

        vm.prank(_erOnboarding);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__AccountNotRegistered.selector, unknown));
        _er.setAccountRoleFlags(unknown, ROLE_FLAGS_UPDATED);
    }

    function test_setAccountRoleFlags_reverts_zeroAddress() public {
        vm.prank(_erOnboarding);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _er.setAccountRoleFlags(address(0), ROLE_FLAGS_UPDATED);
    }

    function test_setAccountRoleFlags_reverts_whenEntityDisabled() public {
        bytes32 entityId = keccak256("entity-account-role-disabled");
        address account = makeAddr("account-role-disabled");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, account);

        vm.prank(_erGuard);
        _er.setEntityStatus(entityId, EntityStatus.DISABLED, "");

        vm.prank(_erOnboarding);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotEnabled.selector, entityId));
        _er.setAccountRoleFlags(account, ROLE_FLAGS_UPDATED);
    }

    function test_setAccountRoleFlags_reverts_unauthorizedCaller_withoutOnboardingRole() public {
        bytes32 entityId = keccak256("entity-account-role-unauthorized");
        address account = makeAddr("account-role-unauthorized");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, account);

        address[] memory unauthorizedCallers = new address[](5);
        unauthorizedCallers[0] = _erAdminOnly;
        unauthorizedCallers[1] = _erGuard;
        unauthorizedCallers[2] = _erWalletTransfer;
        unauthorizedCallers[3] = _notOwner;
        unauthorizedCallers[4] = account;

        bytes4 unauthorizedSelector = bytes4(keccak256("Unauthorized()"));
        for (uint256 i; i < unauthorizedCallers.length;) {
            vm.expectRevert(unauthorizedSelector);
            vm.prank(unauthorizedCallers[i]);
            _er.setAccountRoleFlags(account, ROLE_FLAGS_UPDATED);
            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                               removeAccount
    //////////////////////////////////////////////////////////////*/

    function test_removeAccount_success_forStandardAccount() public {
        bytes32 entityId = keccak256("entity-remove-standard");
        address standardAccount = makeAddr("remove-standard-account");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, standardAccount);

        vm.prank(_erWalletTransfer);
        _er.removeAccount(standardAccount, "");

        assertFalse(_er.doesAccountExist(standardAccount));
    }

    function test_removeAccount_reverts_whenAccountIsEntityManager() public {
        bytes32 entityId = keccak256("entity-remove-manager");
        address managerAccount = makeAddr("remove-manager-account");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, managerAccount);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, managerAccount, true);

        vm.prank(_erWalletTransfer);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__AccountIsEntityManager.selector, managerAccount, entityId));
        _er.removeAccount(managerAccount, "");
    }

    function test_removeAccount_reverts_whenDisabledAccountIsEntityManager() public {
        bytes32 entityId = keccak256("rm-disabled-manager");
        address managerAccount = makeAddr("rm-disabled-manager-account");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, managerAccount);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(entityId, managerAccount, true);

        vm.prank(_erGuard);
        _er.setAccountStatus(managerAccount, AccountStatus.DISABLED, "");

        vm.prank(_erWalletTransfer);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__AccountIsEntityManager.selector, managerAccount, entityId));
        _er.removeAccount(managerAccount, "");
    }

    function test_removeAccount_success_afterManagerRevoked() public {
        bytes32 entityId = keccak256("entity-remove-revoked-manager");
        address managerAccount = makeAddr("remove-revoked-manager-account");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, managerAccount);

        vm.startPrank(_erAdminOnly);
        _er.setEntityManager(entityId, managerAccount, true);
        _er.setEntityManager(entityId, managerAccount, false);
        vm.stopPrank();

        vm.prank(_erWalletTransfer);
        _er.removeAccount(managerAccount, "");

        assertFalse(_er.doesAccountExist(managerAccount));
        assertFalse(_er.isEntityManager(entityId, managerAccount));
    }

    function test_removeAccount_reverts_whenAccountIsEntityAuthority() public {
        bytes32 entityId = keccak256("entity-remove-authority");
        address authorityAccount = makeAddr("remove-authority-account");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, authorityAccount);

        vm.prank(_erAdminOnly);
        _er.setEntityAuthority(entityId, authorityAccount);

        vm.prank(_erWalletTransfer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ER__AccountIsEntityAuthority.selector, authorityAccount, entityId)
        );
        _er.removeAccount(authorityAccount, "");
    }

    function test_removeAccount_reverts_whenDisabledAccountIsEntityAuthority() public {
        bytes32 entityId = keccak256("rm-disabled-authority");
        address authorityAccount = makeAddr("rm-disabled-authority-account");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, authorityAccount);

        vm.prank(_erAdminOnly);
        _er.setEntityAuthority(entityId, authorityAccount);

        vm.prank(_erGuard);
        _er.setAccountStatus(authorityAccount, AccountStatus.DISABLED, "");

        vm.prank(_erWalletTransfer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ER__AccountIsEntityAuthority.selector, authorityAccount, entityId)
        );
        _er.removeAccount(authorityAccount, "");
    }

    function test_removeAccount_reverts_whenDisabledEntityHasGovernanceAccount() public {
        bytes32 entityId = keccak256("rm-disabled-entity-auth");
        address authorityAccount = makeAddr("rm-disabled-entity-auth-account");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, authorityAccount);

        vm.prank(_erAdminOnly);
        _er.setEntityAuthority(entityId, authorityAccount);

        vm.prank(_erGuard);
        _er.setEntityStatus(entityId, EntityStatus.DISABLED, "");

        vm.prank(_erWalletTransfer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ER__AccountIsEntityAuthority.selector, authorityAccount, entityId)
        );
        _er.removeAccount(authorityAccount, "");
    }

    function test_removeAccount_reverts_authorityBeforeManager_whenAccountHasBothGovernanceRoles() public {
        bytes32 entityId = keccak256("rm-both-gov");
        address governanceAccount = makeAddr("rm-both-gov-account");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, governanceAccount);

        vm.startPrank(_erAdminOnly);
        _er.setEntityAuthority(entityId, governanceAccount);
        _er.setEntityManager(entityId, governanceAccount, true);
        vm.stopPrank();

        vm.prank(_erWalletTransfer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ER__AccountIsEntityAuthority.selector, governanceAccount, entityId)
        );
        _er.removeAccount(governanceAccount, "");
    }

    function test_removeAccount_success_afterAuthorityRotated() public {
        bytes32 entityId = keccak256("entity-remove-rotated-authority");
        address authorityAccount = makeAddr("remove-rotated-authority-account");
        address newAuthority = makeAddr("remove-new-authority");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, authorityAccount);

        vm.startPrank(_erAdminOnly);
        _er.setEntityAuthority(entityId, authorityAccount);
        _er.setEntityAuthority(entityId, newAuthority);
        vm.stopPrank();

        vm.prank(_erWalletTransfer);
        _er.removeAccount(authorityAccount, "");

        assertFalse(_er.doesAccountExist(authorityAccount));
        assertEq(_er.getEntityAuthority(entityId), newAuthority);
    }

    function test_removeAccount_success_whenAccountIsGovernanceForUnlinkedEntity() public {
        bytes32 linkedEntity = keccak256("rm-linked");
        bytes32 otherEntity = keccak256("rm-other-gov");
        address account = makeAddr("rm-other-gov-account");

        _registerEntity(linkedEntity);
        _registerEntity(otherEntity);

        vm.startPrank(_erAdminOnly);
        _er.setEntityAuthority(otherEntity, account);
        _er.setEntityManager(otherEntity, account, true);
        vm.stopPrank();

        _registerStandardAccount(linkedEntity, account);

        vm.prank(_erWalletTransfer);
        _er.removeAccount(account, "");

        assertFalse(_er.doesAccountExist(account));
        assertEq(_er.getEntityAuthority(otherEntity), account);
        assertFalse(_er.isEntityManager(otherEntity, account));
    }

    function test_removeAccount_reverts_notRegistered() public {
        address account = makeAddr("unknown-remove-account");

        vm.prank(_erWalletTransfer);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__AccountNotRegistered.selector, account));
        _er.removeAccount(account, "");
    }

    function test_removeAccount_reverts_unauthorizedCaller_withoutWalletTransferRole() public {
        bytes32 entityId = keccak256("entity-remove-unauthorized");
        address account = makeAddr("remove-unauthorized-account");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, account);

        address[] memory unauthorizedCallers = new address[](5);
        unauthorizedCallers[0] = _erAdminOnly;
        unauthorizedCallers[1] = _erGuard;
        unauthorizedCallers[2] = _erOnboarding;
        unauthorizedCallers[3] = _notOwner;
        unauthorizedCallers[4] = account;

        bytes4 unauthorizedSelector = bytes4(keccak256("Unauthorized()"));
        for (uint256 i; i < unauthorizedCallers.length;) {
            vm.expectRevert(unauthorizedSelector);
            vm.prank(unauthorizedCallers[i]);
            _er.removeAccount(account, "");
            unchecked {
                ++i;
            }
        }
    }

    function test_removeAccount_reverts_notAdmin() public {
        bytes32 entityId = keccak256("entity-remove-not-admin");
        address account = makeAddr("remove-not-admin-account");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, account);

        vm.prank(_notOwner);
        vm.expectRevert();
        _er.removeAccount(account, "");
    }

    /*//////////////////////////////////////////////////////////////
                           transferAccountToEntity
    //////////////////////////////////////////////////////////////*/

    function test_transferAccountToEntity_success_swapAndPop() public {
        bytes32 sourceEntity = keccak256("entity-transfer-source");
        bytes32 targetEntity = keccak256("entity-transfer-target");
        address account1 = makeAddr("transfer-account-1");
        address account2 = makeAddr("transfer-account-2");

        _registerEntity(sourceEntity);
        _registerEntity(targetEntity);

        _registerStandardAccount(sourceEntity, account1);
        _registerStandardAccount(sourceEntity, account2);

        vm.prank(_erWalletTransfer);
        _er.transferAccountToEntity(account1, targetEntity);

        address[] memory sourceAccounts = _er.getEntityAccounts(sourceEntity);
        assertEq(sourceAccounts.length, 1);
        assertEq(sourceAccounts[0], account2);
        assertEq(_er.getEntityId(account1), targetEntity);
    }

    function test_transferAccountToEntity_reverts_whenAccountIsSourceEntityManager() public {
        bytes32 sourceEntity = keccak256("entity-transfer-manager-source");
        bytes32 targetEntity = keccak256("entity-transfer-manager-target");
        address managerAccount = makeAddr("transfer-manager-account");

        _registerEntity(sourceEntity);
        _registerEntity(targetEntity);
        _registerStandardAccount(sourceEntity, managerAccount);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(sourceEntity, managerAccount, true);

        vm.prank(_erWalletTransfer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ER__AccountIsEntityManager.selector, managerAccount, sourceEntity)
        );
        _er.transferAccountToEntity(managerAccount, targetEntity);

        assertEq(_er.getEntityId(managerAccount), sourceEntity);
    }

    function test_transferAccountToEntity_reverts_whenDisabledAccountIsSourceEntityManager() public {
        bytes32 sourceEntity = keccak256("xfer-disabled-mgr-src");
        bytes32 targetEntity = keccak256("xfer-disabled-mgr-dst");
        address managerAccount = makeAddr("xfer-disabled-manager");

        _registerEntity(sourceEntity);
        _registerEntity(targetEntity);
        _registerStandardAccount(sourceEntity, managerAccount);

        vm.prank(_erAdminOnly);
        _er.setEntityManager(sourceEntity, managerAccount, true);

        vm.prank(_erGuard);
        _er.setAccountStatus(managerAccount, AccountStatus.DISABLED, "");

        vm.prank(_erWalletTransfer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ER__AccountIsEntityManager.selector, managerAccount, sourceEntity)
        );
        _er.transferAccountToEntity(managerAccount, targetEntity);

        assertEq(_er.getEntityId(managerAccount), sourceEntity);
    }

    function test_transferAccountToEntity_success_afterSourceManagerRevoked() public {
        bytes32 sourceEntity = keccak256("xfer-rev-mgr-src");
        bytes32 targetEntity = keccak256("xfer-rev-mgr-dst");
        address managerAccount = makeAddr("transfer-revoked-manager-account");

        _registerEntity(sourceEntity);
        _registerEntity(targetEntity);
        _registerStandardAccount(sourceEntity, managerAccount);

        vm.startPrank(_erAdminOnly);
        _er.setEntityManager(sourceEntity, managerAccount, true);
        _er.setEntityManager(sourceEntity, managerAccount, false);
        vm.stopPrank();

        vm.prank(_erWalletTransfer);
        _er.transferAccountToEntity(managerAccount, targetEntity);

        assertEq(_er.getEntityId(managerAccount), targetEntity);
        assertFalse(_er.isEntityManager(sourceEntity, managerAccount));
    }

    function test_transferAccountToEntity_reverts_whenAccountIsSourceEntityAuthority() public {
        bytes32 sourceEntity = keccak256("entity-transfer-authority-source");
        bytes32 targetEntity = keccak256("entity-transfer-authority-target");
        address authorityAccount = makeAddr("transfer-authority-account");

        _registerEntity(sourceEntity);
        _registerEntity(targetEntity);
        _registerStandardAccount(sourceEntity, authorityAccount);

        vm.prank(_erAdminOnly);
        _er.setEntityAuthority(sourceEntity, authorityAccount);

        vm.prank(_erWalletTransfer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ER__AccountIsEntityAuthority.selector, authorityAccount, sourceEntity)
        );
        _er.transferAccountToEntity(authorityAccount, targetEntity);

        assertEq(_er.getEntityId(authorityAccount), sourceEntity);
    }

    function test_transferAccountToEntity_reverts_whenDisabledAccountIsSourceEntityAuthority() public {
        bytes32 sourceEntity = keccak256("xfer-disabled-auth-src");
        bytes32 targetEntity = keccak256("xfer-disabled-auth-dst");
        address authorityAccount = makeAddr("xfer-disabled-authority");

        _registerEntity(sourceEntity);
        _registerEntity(targetEntity);
        _registerStandardAccount(sourceEntity, authorityAccount);

        vm.prank(_erAdminOnly);
        _er.setEntityAuthority(sourceEntity, authorityAccount);

        vm.prank(_erGuard);
        _er.setAccountStatus(authorityAccount, AccountStatus.DISABLED, "");

        vm.prank(_erWalletTransfer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ER__AccountIsEntityAuthority.selector, authorityAccount, sourceEntity)
        );
        _er.transferAccountToEntity(authorityAccount, targetEntity);

        assertEq(_er.getEntityId(authorityAccount), sourceEntity);
    }

    function test_transferAccountToEntity_reverts_authorityBeforeManager_whenAccountHasBothSourceRoles() public {
        bytes32 sourceEntity = keccak256("xfer-both-gov-src");
        bytes32 targetEntity = keccak256("xfer-both-gov-dst");
        address governanceAccount = makeAddr("xfer-both-gov-account");

        _registerEntity(sourceEntity);
        _registerEntity(targetEntity);
        _registerStandardAccount(sourceEntity, governanceAccount);

        vm.startPrank(_erAdminOnly);
        _er.setEntityAuthority(sourceEntity, governanceAccount);
        _er.setEntityManager(sourceEntity, governanceAccount, true);
        vm.stopPrank();

        vm.prank(_erWalletTransfer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ER__AccountIsEntityAuthority.selector, governanceAccount, sourceEntity)
        );
        _er.transferAccountToEntity(governanceAccount, targetEntity);

        assertEq(_er.getEntityId(governanceAccount), sourceEntity);
    }

    function test_transferAccountToEntity_success_afterSourceAuthorityRotated() public {
        bytes32 sourceEntity = keccak256("xfer-rot-auth-src");
        bytes32 targetEntity = keccak256("xfer-rot-auth-dst");
        address authorityAccount = makeAddr("xfer-rot-auth-acct");
        address newAuthority = makeAddr("transfer-new-authority");

        _registerEntity(sourceEntity);
        _registerEntity(targetEntity);
        _registerStandardAccount(sourceEntity, authorityAccount);

        vm.startPrank(_erAdminOnly);
        _er.setEntityAuthority(sourceEntity, authorityAccount);
        _er.setEntityAuthority(sourceEntity, newAuthority);
        vm.stopPrank();

        vm.prank(_erWalletTransfer);
        _er.transferAccountToEntity(authorityAccount, targetEntity);

        assertEq(_er.getEntityId(authorityAccount), targetEntity);
        assertEq(_er.getEntityAuthority(sourceEntity), newAuthority);
    }

    function test_transferAccountToEntity_success_whenAccountIsGovernanceForUnlinkedEntity() public {
        bytes32 sourceEntity = keccak256("xfer-linked-src");
        bytes32 targetEntity = keccak256("xfer-linked-dst");
        bytes32 otherEntity = keccak256("xfer-other-gov");
        address account = makeAddr("xfer-other-gov-account");

        _registerEntity(sourceEntity);
        _registerEntity(targetEntity);
        _registerEntity(otherEntity);

        vm.startPrank(_erAdminOnly);
        _er.setEntityAuthority(otherEntity, account);
        _er.setEntityManager(otherEntity, account, true);
        vm.stopPrank();

        _registerStandardAccount(sourceEntity, account);

        vm.prank(_erWalletTransfer);
        _er.transferAccountToEntity(account, targetEntity);

        assertEq(_er.getEntityId(account), targetEntity);
        assertEq(_er.getEntityAuthority(otherEntity), account);
        assertFalse(_er.isEntityManager(otherEntity, account));
    }

    function test_transferAccountToEntity_reverts_accountAlreadyLinked() public {
        bytes32 sourceEntity = keccak256("entity-transfer-same-source");
        bytes32 targetEntity = keccak256("entity-transfer-same-target");
        address account = makeAddr("transfer-account");

        _registerEntity(sourceEntity);
        _registerEntity(targetEntity);
        _registerStandardAccount(sourceEntity, account);

        vm.prank(_erWalletTransfer);
        _er.transferAccountToEntity(account, targetEntity);

        vm.prank(_erWalletTransfer);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__AccountAlreadyLinked.selector, account, targetEntity));
        _er.transferAccountToEntity(account, targetEntity);
    }

    function test_transferAccountToEntity_reverts_notRegistered() public {
        // solhint-disable-next-line gas-small-strings
        bytes32 targetEntity = keccak256("entity-transfer-target-only");
        address missing = makeAddr("transfer-missing");

        _registerEntity(targetEntity);

        vm.prank(_erWalletTransfer);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__AccountNotRegistered.selector, missing));
        _er.transferAccountToEntity(missing, targetEntity);
    }

    function test_transferAccountToEntity_reverts_unauthorizedCaller_withoutWalletTransferRole() public {
        // solhint-disable-next-line gas-small-strings
        bytes32 sourceEntity = keccak256("entity-transfer-unauthorized-source");
        // solhint-disable-next-line gas-small-strings
        bytes32 targetEntity = keccak256("entity-transfer-unauthorized-target");
        address account = makeAddr("transfer-unauthorized-account");

        _registerEntity(sourceEntity);
        _registerEntity(targetEntity);
        _registerStandardAccount(sourceEntity, account);

        address[] memory unauthorizedCallers = new address[](5);
        unauthorizedCallers[0] = _erAdminOnly;
        unauthorizedCallers[1] = _erGuard;
        unauthorizedCallers[2] = _erOnboarding;
        unauthorizedCallers[3] = _notOwner;
        unauthorizedCallers[4] = account;

        bytes4 unauthorizedSelector = bytes4(keccak256("Unauthorized()"));
        for (uint256 i; i < unauthorizedCallers.length;) {
            vm.expectRevert(unauthorizedSelector);
            vm.prank(unauthorizedCallers[i]);
            _er.transferAccountToEntity(account, targetEntity);
            unchecked {
                ++i;
            }
        }
    }

    function test_transferAccountToEntity_reverts_zeroAccount() public {
        // solhint-disable-next-line gas-small-strings
        bytes32 targetEntity = keccak256("entity-transfer-zero-account-target");
        _registerEntity(targetEntity);

        vm.prank(_erWalletTransfer);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _er.transferAccountToEntity(address(0), targetEntity);
    }

    function test_transferAccountToEntity_reverts_newEntityZero() public {
        // solhint-disable-next-line gas-small-strings
        bytes32 sourceEntity = keccak256("entity-transfer-source-zero-target");
        address account = makeAddr("transfer-account-zero-target");

        _registerEntity(sourceEntity);
        _registerStandardAccount(sourceEntity, account);

        vm.prank(_erWalletTransfer);
        vm.expectRevert(Errors.ER__EntityIdZero.selector);
        _er.transferAccountToEntity(account, bytes32(0));
    }

    function test_transferAccountToEntity_reverts_newEntityNotRegistered() public {
        // solhint-disable-next-line gas-small-strings
        bytes32 sourceEntity = keccak256("entity-transfer-missing-target-source");
        bytes32 missingTargetEntity = keccak256("entity-transfer-missing-target");
        address account = makeAddr("transfer-missing-target-account");

        _registerEntity(sourceEntity);
        _registerStandardAccount(sourceEntity, account);

        vm.prank(_erWalletTransfer);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotRegistered.selector, missingTargetEntity));
        _er.transferAccountToEntity(account, missingTargetEntity);
    }

    function test_transferAccountToEntity_reverts_newEntityNotEnabled() public {
        // solhint-disable-next-line gas-small-strings
        bytes32 sourceEntity = keccak256("entity-transfer-disabled-target-source");
        bytes32 targetEntity = keccak256("entity-transfer-disabled-target");
        address account = makeAddr("transfer-disabled-target-account");

        _registerEntity(sourceEntity);
        _registerEntity(targetEntity);
        _registerStandardAccount(sourceEntity, account);

        vm.prank(_erGuard);
        _er.setEntityStatus(targetEntity, EntityStatus.DISABLED, "");

        vm.prank(_erWalletTransfer);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotEnabled.selector, targetEntity));
        _er.transferAccountToEntity(account, targetEntity);
    }

    function test_transferAccountToEntity_reverts_when_oldEntityDisabled() public {
        bytes32 sourceEntity = keccak256("entity-transfer-disabled-source");
        bytes32 targetEntity = keccak256("entity-transfer-disabled-target");
        address account = makeAddr("transfer-disabled-account");

        _registerEntity(sourceEntity);
        _registerEntity(targetEntity);
        _registerStandardAccount(sourceEntity, account);

        vm.prank(_erGuard);
        _er.setEntityStatus(sourceEntity, EntityStatus.DISABLED, "");

        vm.prank(_erWalletTransfer);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotEnabled.selector, sourceEntity));
        _er.transferAccountToEntity(account, targetEntity);
    }

    function test_transferAccountToEntity_reverts_whenEntityAccountIndexCorrupted() public {
        bytes32 sourceEntity = keccak256("entity-corrupted-index-source");
        bytes32 targetEntity = keccak256("entity-corrupted-index-target");
        address corrupted = makeAddr("account-corrupted-entity-index");

        _registerEntity(sourceEntity);
        _registerEntity(targetEntity);
        _registerStandardAccount(sourceEntity, corrupted);

        _setEntityAccountIndex(corrupted, 0);

        vm.prank(_erWalletTransfer);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__AccountNotRegistered.selector, corrupted));
        _er.transferAccountToEntity(corrupted, targetEntity);
    }

    /*//////////////////////////////////////////////////////////////
                            validation hooks
    //////////////////////////////////////////////////////////////*/

    function test_canTransfer_and_canApprove_success() public {
        bytes32 entityId = keccak256("entity-validation-success");
        address from = makeAddr("transfer-from");
        address to = makeAddr("transfer-to");
        address operator = makeAddr("transfer-operator");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, from);
        _registerStandardAccount(entityId, to);
        _registerStandardAccount(entityId, operator);

        assertTrue(_er.canTransfer(from, to, operator, 0, 0));
        assertTrue(_er.canApprove(from, to, 0, 0));
    }

    function test_canTransfer_and_canApprove_returnFalse_forDisabledParticipants() public {
        bytes32 entityId = keccak256("entity-validation-disabled");
        address from = makeAddr("transfer-from");
        address to = makeAddr("transfer-to");
        address operator = makeAddr("transfer-operator");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, from);
        _registerStandardAccount(entityId, to);
        _registerStandardAccount(entityId, operator);

        vm.prank(_erGuard);
        _er.setAccountStatus(from, AccountStatus.DISABLED, "");
        assertFalse(_er.canTransfer(from, to, operator, 0, 0));
        assertFalse(_er.canApprove(from, to, 0, 0));

        vm.prank(_erGuard);
        _er.setAccountStatus(from, AccountStatus.ENABLED, "");
        vm.prank(_erGuard);
        _er.setAccountStatus(to, AccountStatus.DISABLED, "");
        assertFalse(_er.canTransfer(from, to, operator, 0, 0));
        assertFalse(_er.canApprove(from, to, 0, 0));

        vm.prank(_erGuard);
        _er.setAccountStatus(to, AccountStatus.ENABLED, "");
        vm.prank(_erGuard);
        _er.setAccountStatus(operator, AccountStatus.DISABLED, "");
        assertFalse(_er.canTransfer(from, to, operator, 0, 0));
    }

    function test_canTransfer_and_canApprove_allowZeroAddressParticipants() public {
        bytes32 entityId = keccak256("entity-validation-zero-address");
        address account = makeAddr("account");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, account);

        assertTrue(_er.canTransfer(address(0), account, account, 0, 0));
        assertTrue(_er.canTransfer(account, address(0), account, 0, 0));
        assertTrue(_er.canTransfer(account, account, address(0), 0, 0));
        assertTrue(_er.canApprove(address(0), account, 0, 0));
        assertTrue(_er.canApprove(account, address(0), 0, 0));
    }

    function test_isAccountEnabled_returnsFalse_whenLinkedEntityDisabled() public {
        bytes32 entityId = keccak256("entity-enabled-disabled");
        address account = makeAddr("entity-disabled-account");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, account);
        assertTrue(_er.isAccountEnabled(account));

        vm.prank(_erGuard);
        _er.setEntityStatus(entityId, EntityStatus.DISABLED, "");

        assertFalse(_er.isAccountEnabled(account));
    }

    /*//////////////////////////////////////////////////////////////
                                   views
    //////////////////////////////////////////////////////////////*/

    function test_getEntity_reverts_guardChecks() public {
        bytes32 notRegistered = keccak256("not-registered");

        vm.expectRevert(Errors.ER__EntityIdZero.selector);
        _er.getEntity(bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotRegistered.selector, notRegistered));
        _er.getEntity(notRegistered);
    }

    function test_getEntityStatus_reverts_guardChecks() public {
        bytes32 notRegistered = keccak256("not-registered");

        vm.expectRevert(Errors.ER__EntityIdZero.selector);
        _er.getEntityStatus(bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotRegistered.selector, notRegistered));
        _er.getEntityStatus(notRegistered);
    }

    function test_getEntityAuthority_and_isEntityManager_reverts_entityNotRegistered() public {
        bytes32 notRegistered = keccak256("not-registered");

        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotRegistered.selector, notRegistered));
        _er.getEntityAuthority(notRegistered);

        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityNotRegistered.selector, notRegistered));
        _er.isEntityManager(notRegistered, makeAddr("manager"));
    }

    function test_getEntityTypeMeta_reverts_invalidType() public {
        vm.expectRevert(Errors.ER__EntityTypeIdZero.selector);
        _er.getEntityTypeMeta(0);

        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityTypeNotRegistered.selector, 999));
        _er.getEntityTypeMeta(999);
    }

    function test_getEntityTypeMeta_reverts_capsOnlyMalformedType() public {
        uint256 typeId = 1000;
        _setEntityTypeCaps(typeId, 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.ER__EntityTypeNotRegistered.selector, typeId));
        _er.getEntityTypeMeta(typeId);
    }

    function test_getAccount_and_accountEntityViews_revert_accountNotRegistered() public {
        address missingAccount = makeAddr("missing-account");

        vm.expectRevert(abi.encodeWithSelector(Errors.ER__AccountNotRegistered.selector, missingAccount));
        _er.getAccount(missingAccount);

        vm.expectRevert(abi.encodeWithSelector(Errors.ER__AccountNotRegistered.selector, missingAccount));
        _er.getEntityId(missingAccount);

        vm.expectRevert(abi.encodeWithSelector(Errors.ER__AccountNotRegistered.selector, missingAccount));
        _er.getEntityTypeIdByAccount(missingAccount);
    }

    function test_getters_successPaths() public {
        bytes32 entityId = keccak256("entity-getters");
        address account = makeAddr("getter-account");

        _registerEntity(entityId);
        _registerStandardAccount(entityId, account);

        Entity memory entity = _er.getEntity(entityId);
        assertEq(entity.typeId, COMPANY_ENTITY);
        assertEq(uint8(_er.getEntityStatus(entityId)), uint8(EntityStatus.ENABLED));

        RegistryAccount memory accountData = _er.getAccount(account);
        assertEq(accountData.entityId, entityId);

        address[] memory entityAccounts = _er.getEntityAccounts(entityId);
        assertEq(entityAccounts.length, 1);
        assertEq(entityAccounts[0], account);

        assertEq(_er.getEntityId(account), entityId);
        assertEq(_er.getEntityTypeId(entityId), COMPANY_ENTITY);
        assertEq(_er.getEntityTypeIdByAccount(account), COMPANY_ENTITY);

        assertTrue(_er.doesAccountExist(account));
        assertFalse(_er.doesAccountExist(makeAddr("missing")));
        assertTrue(_er.isAccountRegistered(account));
        assertTrue(_er.isAccountEnabled(account));
    }

    /*//////////////////////////////////////////////////////////////
                               grantRoles
    //////////////////////////////////////////////////////////////*/

    function test_grantRoles_array_success() public {
        address[] memory admins = new address[](2);
        admins[0] = makeAddr("new-admin-1");
        admins[1] = makeAddr("new-admin-2");
        uint256 adminRole = _er.ADMIN_ROLE();

        bytes memory data = abi.encodeWithSignature("grantRoles(address[],uint256)", admins, adminRole);
        _timelockOp(_erAddr, data);
    }

    function test_grantRoles_array_reverts_invalidRoles() public {
        address[] memory admins = new address[](1);
        admins[0] = makeAddr("new-admin-1");
        uint256 invalidRoles = _er.ADMIN_ROLE() | (_er.ENTITY_TYPE_MANAGER() << 1);

        bytes memory data = abi.encodeWithSignature("grantRoles(address[],uint256)", admins, invalidRoles);
        _timelockSchedule(_erAddr, data);
        vm.expectRevert(Errors.InvalidRoles.selector);
        _timelockExecute(_erAddr, data);
    }

    function test_grantRoles_single_reverts_invalidRoles() public {
        uint256 invalidRoles = _er.ADMIN_ROLE() | (_er.ENTITY_TYPE_MANAGER() << 1);

        bytes memory data = abi.encodeWithSignature("grantRoles(address,uint256)", makeAddr("new-admin"), invalidRoles);
        _timelockSchedule(_erAddr, data);
        vm.expectRevert(Errors.InvalidRoles.selector);
        _timelockExecute(_erAddr, data);
    }

    /*//////////////////////////////////////////////////////////////
                            supportsInterface
    //////////////////////////////////////////////////////////////*/

    function test_supportsInterface_success() public view {
        assertTrue(_er.supportsInterface(type(IEntityRegistry).interfaceId));
        assertTrue(_er.supportsInterface(type(IERC165).interfaceId));
        assertFalse(_er.supportsInterface(bytes4(0x12345678)));
    }

    /*//////////////////////////////////////////////////////////////
                             upgradeToAndCall
    //////////////////////////////////////////////////////////////*/

    function test_upgradeTo_success_beaconOwner() public {
        address newImpl = address(new MockEntityRegistry());

        bytes memory data = abi.encodeWithSelector(_erBeacon.upgradeTo.selector, newImpl);
        _timelockOp(address(_erBeacon), data);

        assertEq(MockEntityRegistry(address(_er)).VERSION(), 2);
        assertTrue(MockEntityRegistry(address(_er)).isNewVersion());
    }

    function test_upgradeTo_reverts_notBeaconOwner() public {
        address newImpl = address(new MockEntityRegistry());

        vm.prank(_notGov);
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableUnauthorizedAccount.selector, _notGov));
        _erBeacon.upgradeTo(newImpl);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _registerEntity(bytes32 entityId) internal {
        vm.prank(_erOnboarding);
        _er.registerEntity(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF);
    }

    function _registerStandardAccount(bytes32 entityId, address account) internal {
        vm.prank(_erAdminOnly);
        _er.registerAccount(account, entityId, ROLE_FLAGS_EMPTY);
    }

    function _setEntityAccountIndex(address account, uint256 entityAccountIndex) internal {
        bytes32 baseSlot = keccak256(abi.encode(account, _entityRegistryAccountsSlot()));
        bytes32 entityAccountIndexSlot = bytes32(uint256(baseSlot) + 4);
        vm.store(address(_er), entityAccountIndexSlot, bytes32(entityAccountIndex));
    }

    function _setEntityTypeCaps(uint256 typeId, uint256 caps) internal {
        bytes32 baseSlot = keccak256(abi.encode(typeId, _entityRegistryEntityTypeMetaSlot()));
        bytes32 capsSlot = bytes32(uint256(baseSlot) + 1);
        vm.store(address(_er), capsSlot, bytes32(caps));
    }

    function _entityRegistryAccountsSlot() internal pure returns (bytes32) {
        return _slotOffset(_erc7201Location("deuss.entityRegistry.storage"), 1);
    }

    function _entityRegistryEntityTypeMetaSlot() internal pure returns (bytes32) {
        return _slotOffset(_erc7201Location("deuss.entityRegistry.storage"), 4);
    }
}
