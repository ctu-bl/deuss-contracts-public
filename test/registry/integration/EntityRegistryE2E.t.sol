// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Errors} from "src/libs/Errors.sol";
import {Entity, Account as RegistryAccount, EntityStatus} from "src/registry/EntityStructs.sol";
import {CompanyFixture} from "test/fixtures/CompanyFixture.t.sol";

contract EntityRegistryE2ETest is CompanyFixture {
    uint256 private constant _BROKER_ENTITY = 77;
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 private constant _BROKER_ENTITY_NAME = bytes32("BROKER");
    uint256 private constant _BROKER_CAPS = 0;

    uint256 private constant _ROLE_BUY_ONLY = 1;
    uint256 private constant _ROLE_BUY_AND_SELL = 3;

    string private constant _BROKER_METADATA_REF = "ipfs://broker";

    function test_e2e_brokerOnboarding_registerRetailWallets_withRoleFlags() public {
        address authority = makeAddr("broker-authority");
        address manager = makeAddr("broker-manager");
        bytes32 entityId = _setupBrokerEntity(authority, manager);

        address investor1 = makeAddr("retail-investor-1");
        address investor2 = makeAddr("retail-investor-2");

        address wallet1 = _createCompanyWallet(entityId, investor1, manager);
        address wallet2 = _createCompanyWallet(entityId, investor2, manager);

        _registerWalletAsManager(entityId, wallet1, investor1, _ROLE_BUY_AND_SELL, manager);
        _registerWalletAsManager(entityId, wallet2, investor2, _ROLE_BUY_ONLY, manager);

        Entity memory entity = _er.getEntity(entityId);
        assertEq(entity.typeId, _BROKER_ENTITY);
        assertEq(uint8(entity.status), uint8(EntityStatus.ENABLED));
        assertEq(_er.getEntityAuthority(entityId), authority);
        assertTrue(_er.isEntityManager(entityId, manager));

        RegistryAccount memory account1 = _er.getAccount(wallet1);
        RegistryAccount memory account2 = _er.getAccount(wallet2);
        assertEq(account1.entityId, entityId);
        assertEq(account2.entityId, entityId);
        assertEq(account1.roleFlags, _ROLE_BUY_AND_SELL);
        assertEq(account2.roleFlags, _ROLE_BUY_ONLY);
        assertTrue(_er.canTransfer(wallet1, wallet2, wallet1, 0, 0));

        address[] memory entityAccounts = _er.getEntityAccounts(entityId);
        assertEq(entityAccounts.length, 2);
        _assertContains(entityAccounts, wallet1);
        _assertContains(entityAccounts, wallet2);
    }

    function test_e2e_managerRevoked_cannotCreateOrRegister() public {
        address authority = makeAddr("broker-authority");
        address manager = makeAddr("broker-manager");
        bytes32 entityId = _setupBrokerEntity(authority, manager);

        vm.prank(authority);
        _er.setEntityManager(entityId, manager, false);
        assertFalse(_er.isEntityManager(entityId, manager));

        vm.expectRevert(abi.encodeWithSelector(Errors.WalletFactory__NotEntityManager.selector, manager, entityId));
        _createCompanyWallet(entityId, makeAddr("retail-investor"), manager);

        address account = makeAddr("retail-account");
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__NotEntityManagerOrAdmin.selector, manager, entityId));
        _er.requestAccountRegistration(account, entityId, _ROLE_BUY_ONLY);
    }

    function test_e2e_authorityRotation_movesManagerControl() public {
        address authorityA = makeAddr("broker-authority-a");
        address managerA = makeAddr("broker-manager-a");
        bytes32 entityId = _setupBrokerEntity(authorityA, managerA);

        address authorityB = makeAddr("broker-authority-b");
        vm.prank(authorityA);
        _er.setEntityAuthority(entityId, authorityB);
        assertEq(_er.getEntityAuthority(entityId), authorityB);

        address managerB = makeAddr("broker-manager-b");
        vm.prank(authorityA);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__NotEntityAuthorityOrAdmin.selector, authorityA, entityId));
        _er.setEntityManager(entityId, managerB, true);

        vm.prank(authorityB);
        _er.setEntityManager(entityId, managerB, true);
        assertTrue(_er.isEntityManager(entityId, managerB));

        address investor = makeAddr("retail-investor");
        address wallet = _createCompanyWallet(entityId, investor, managerB);
        _registerWalletAsManager(entityId, wallet, investor, _ROLE_BUY_ONLY, managerB);

        RegistryAccount memory account = _er.getAccount(wallet);
        assertEq(account.entityId, entityId);
        assertEq(account.roleFlags, _ROLE_BUY_ONLY);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _setupBrokerEntity(address authority, address manager) internal returns (bytes32 entityId) {
        vm.startPrank(_erAdmin);
        _er.defineEntityType(_BROKER_ENTITY, _BROKER_ENTITY_NAME, _BROKER_CAPS);

        entityId = keccak256(abi.encodePacked("broker-entity", authority, manager));
        address[] memory managers = new address[](1);
        managers[0] = manager;
        _er.registerEntity(entityId, _BROKER_ENTITY, _BROKER_METADATA_REF, authority, managers);
        vm.stopPrank();
    }

    function _registerWalletAsManager(
        bytes32 entityId,
        address wallet,
        address owner,
        uint256 roleFlags,
        address manager
    ) internal {
        _requestAndAcceptWalletAccountRegistration(manager, wallet, entityId, owner, roleFlags);
    }

    function _assertContains(address[] memory accounts, address target) internal pure {
        bool found;
        for (uint256 i; i < accounts.length; ++i) {
            if (accounts[i] == target) {
                found = true;
                break;
            }
        }

        assertTrue(found);
    }
}
