// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Initializable} from "solady/src/utils/Initializable.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPolicyRegistry} from "src/registry/interfaces/IPolicyRegistry.sol";
import {PolicyRegistry} from "src/registry/PolicyRegistry.sol";
import {ModuleExecutionCheck, OperationModule, OperationRoles} from "src/registry/PolicyStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {ICompanyWallet} from "src/wallet/ICompanyWallet.sol";
import {CompanyWallet} from "src/wallet/CompanyWallet.sol";
import {CompanyFixture} from "test/fixtures/CompanyFixture.t.sol";
import {
    MockInvalidReturnPolicyModule,
    MockPolicyModule,
    MockTargetContract,
    MockPolicyRegistryV2
} from "test/mocks/MockContracts.sol";

error RecoverableOwnerProxy__Unauthorized(address caller);
error RecoverableOwnerProxy__CallFailed(bytes returnData);

contract RecoverableOwnerProxy {
    address internal _controller;
    address internal immutable _recoverer;

    constructor(address controller_, address recoverer_) {
        _controller = controller_;
        _recoverer = recoverer_;
    }

    function controller() external view returns (address currentController) {
        return _controller;
    }

    function recover(address replacementController) external {
        if (msg.sender != _recoverer) {
            revert RecoverableOwnerProxy__Unauthorized(msg.sender);
        }

        _controller = replacementController;
    }

    function callAsOwner(address target, bytes calldata data) external returns (bytes memory returnData) {
        if (msg.sender != _controller) {
            revert RecoverableOwnerProxy__Unauthorized(msg.sender);
        }

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) = target.call(data);
        if (!success) {
            revert RecoverableOwnerProxy__CallFailed(result);
        }

        return result;
    }
}

contract PolicyRegistryStorageHarness is PolicyRegistry {
    function exposedPolicyRegistryStorageLocation() external pure returns (bytes32) {
        return _POLICY_REGISTRY_STORAGE_LOCATION;
    }
}

contract PolicyRegistryTest is CompanyFixture {
    PolicyRegistry internal _policyRegistry;
    UpgradeableBeacon internal _policyRegistryBeacon;
    MockTargetContract internal _target;
    address internal _walletAdmin;
    address internal _user;
    address internal _secondOwner;
    address internal _secondWallet;
    MockPolicyModule internal _allowModule;
    MockPolicyModule internal _denyModule;
    MockPolicyModule internal _revertingModule;
    MockInvalidReturnPolicyModule internal _invalidReturnModule;

    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant _ROLE_LABEL_TRADER = bytes32("TRADER");
    uint256 internal constant _ROLE_A = 1;
    uint256 internal constant _ROLE_B = 2;
    uint256 internal constant _ROLE_C = 4;
    uint8 internal constant _ROLE_LABEL_ID = 7;
    bytes4 internal constant _GRANT_USER_ROLES_SELECTOR = 0xba517e94;
    bytes4 internal constant _GRANT_OPERATION_ROLES_SELECTOR = 0x3f3daf31;

    function setUp() public override {
        super.setUp();

        _policyRegistry = PolicyRegistry(_suite.registries.walletPolicyRegistry);
        _policyRegistryBeacon = UpgradeableBeacon(_suite.registries.walletPolicyRegistryBeacon);
        _target = new MockTargetContract();
        _walletAdmin = makeAddr("walletAdmin");
        _user = makeAddr("walletUser");
        _secondOwner = makeAddr("secondOwner");
        (_secondWallet,) = _createAndRegisterEntityWalletForCompany(_erAdmin, _secondOwner);
        _allowModule = new MockPolicyModule(true, false);
        _denyModule = new MockPolicyModule(false, false);
        _revertingModule = new MockPolicyModule(false, true);
        _invalidReturnModule = new MockInvalidReturnPolicyModule();
    }

    /*//////////////////////////////////////////////////////////////
                          ERC-7201 NAMESPACED STORAGE
    //////////////////////////////////////////////////////////////*/

    function test_namespacedStorageLocation_success_matchesErc7201Formula() public {
        PolicyRegistryStorageHarness harness = new PolicyRegistryStorageHarness();
        bytes32 storageLocation = harness.exposedPolicyRegistryStorageLocation();

        assertEq(storageLocation, _erc7201Location("deuss.policyRegistry.storage"));
        assertEq(uint256(storageLocation) & 0xff, 0);
    }

    function test_namespacedState_success_usesErc7201Storage() public {
        vm.prank(_company);
        _policyRegistry.grantUserRoles(_cwAddr, _user, _ROLE_A);
        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), _ROLE_A);

        bytes32 root = _erc7201Location("deuss.policyRegistry.storage");
        uint256 epoch = ICompanyWallet(_cwAddr).ownershipEpoch();

        // `walletUserRoles` is field offset 0; nested slot = keccak(user, keccak(epoch, keccak(wallet, root))).
        bytes32 entrySlot =
            keccak256(abi.encode(_user, keccak256(abi.encode(epoch, keccak256(abi.encode(_cwAddr, root))))));
        assertEq(uint256(vm.load(address(_policyRegistry), entrySlot)), _ROLE_A);

        // Isolation: the pre-namespace sequential slot (0) derivation for the same keys holds nothing.
        bytes32 legacySlot =
            keccak256(abi.encode(_user, keccak256(abi.encode(epoch, keccak256(abi.encode(_cwAddr, uint256(0)))))));
        assertEq(vm.load(address(_policyRegistry), legacySlot), bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                               initialize
    //////////////////////////////////////////////////////////////*/

    function test_initialize_success_whenCalledThroughProxy() public {
        PolicyRegistry registry = _deployPolicyRegistry(_deployer);

        assertEq(registry.owner(), _deployer);
    }

    function test_initialize_reverts_zeroOwner() public {
        PolicyRegistry implementation = new PolicyRegistry();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), _deployer);
        bytes memory initData = abi.encodeWithSelector(PolicyRegistry.initialize.selector, address(0));

        vm.expectRevert(Errors.ZeroAddress.selector);
        new BeaconProxy(address(beacon), initData);
    }

    function test_initialize_reverts_reinitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        _policyRegistry.initialize(_deployer);
    }

    /*//////////////////////////////////////////////////////////////
                              upgradeTo
    //////////////////////////////////////////////////////////////*/

    function test_upgradeTo_success_whenCallerIsBeaconOwner() public {
        MockPolicyRegistryV2 implementation = new MockPolicyRegistryV2();

        _timelockOp(
            address(_policyRegistryBeacon),
            abi.encodeWithSelector(_policyRegistryBeacon.upgradeTo.selector, address(implementation))
        );

        assertTrue(MockPolicyRegistryV2(address(_policyRegistry)).isNewVersion());
    }

    function test_upgradeTo_reverts_whenCallerIsNotBeaconOwner() public {
        MockPolicyRegistryV2 implementation = new MockPolicyRegistryV2();

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableUnauthorizedAccount.selector, _company));
        _policyRegistryBeacon.upgradeTo(address(implementation));
    }

    /*//////////////////////////////////////////////////////////////
                         grantWalletPolicyAdmin
    //////////////////////////////////////////////////////////////*/

    function test_grantWalletPolicyAdmin_success_whenCalledByWalletOwner() public {
        vm.expectEmit(true, true, true, false);
        emit IPolicyRegistry.WalletPolicyAdminGranted(_cwAddr, _walletAdmin, _company);

        vm.prank(_company);
        _policyRegistry.grantWalletPolicyAdmin(_cwAddr, _walletAdmin);

        assertTrue(_policyRegistry.isWalletPolicyAdmin(_cwAddr, _walletAdmin));
    }

    function test_grantWalletPolicyAdmin_reverts_zeroAdmin() public {
        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__InvalidPolicyAdmin.selector, address(0)));
        _policyRegistry.grantWalletPolicyAdmin(_cwAddr, address(0));
    }

    function test_grantWalletPolicyAdmin_reverts_zeroWallet() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__InvalidWallet.selector, address(0)));
        _policyRegistry.grantWalletPolicyAdmin(address(0), _walletAdmin);
    }

    function test_grantWalletPolicyAdmin_reverts_walletWithoutCode() public {
        address walletEoa = makeAddr("walletEoa");
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__InvalidWallet.selector, walletEoa));
        _policyRegistry.grantWalletPolicyAdmin(walletEoa, _walletAdmin);
    }

    function test_grantWalletPolicyAdmin_reverts_whenAdminAlreadyGranted() public {
        vm.startPrank(_company);
        _policyRegistry.grantWalletPolicyAdmin(_cwAddr, _walletAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.PolicyRegistry__WalletPolicyAdminAlreadyGranted.selector, _cwAddr, _walletAdmin
            )
        );
        _policyRegistry.grantWalletPolicyAdmin(_cwAddr, _walletAdmin);
        vm.stopPrank();
    }

    function test_grantWalletPolicyAdmin_reverts_whenCallerIsNotWalletOwner() public {
        vm.prank(_walletAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, _walletAdmin, _cwAddr));
        _policyRegistry.grantWalletPolicyAdmin(_cwAddr, makeAddr("otherAdmin"));
    }

    /*//////////////////////////////////////////////////////////////
                        revokeWalletPolicyAdmin
    //////////////////////////////////////////////////////////////*/

    function test_revokeWalletPolicyAdmin_success_whenCalledByWalletOwner() public {
        vm.prank(_company);
        _policyRegistry.grantWalletPolicyAdmin(_cwAddr, _walletAdmin);

        vm.expectEmit(true, true, true, false);
        emit IPolicyRegistry.WalletPolicyAdminRevoked(_cwAddr, _walletAdmin, _company);

        vm.prank(_company);
        _policyRegistry.revokeWalletPolicyAdmin(_cwAddr, _walletAdmin);

        assertFalse(_policyRegistry.isWalletPolicyAdmin(_cwAddr, _walletAdmin));
    }

    function test_revokeWalletPolicyAdmin_reverts_zeroAdmin() public {
        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__InvalidPolicyAdmin.selector, address(0)));
        _policyRegistry.revokeWalletPolicyAdmin(_cwAddr, address(0));
    }

    function test_revokeWalletPolicyAdmin_reverts_zeroWallet() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__InvalidWallet.selector, address(0)));
        _policyRegistry.revokeWalletPolicyAdmin(address(0), _walletAdmin);
    }

    function test_revokeWalletPolicyAdmin_reverts_walletWithoutCode() public {
        address walletEoa = makeAddr("walletEoa");
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__InvalidWallet.selector, walletEoa));
        _policyRegistry.revokeWalletPolicyAdmin(walletEoa, _walletAdmin);
    }

    function test_revokeWalletPolicyAdmin_reverts_whenAdminNotGranted() public {
        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.PolicyRegistry__WalletPolicyAdminNotGranted.selector, _cwAddr, _walletAdmin)
        );
        _policyRegistry.revokeWalletPolicyAdmin(_cwAddr, _walletAdmin);
    }

    function test_revokeWalletPolicyAdmin_reverts_whenCallerIsNotWalletOwner() public {
        vm.prank(_company);
        _policyRegistry.grantWalletPolicyAdmin(_cwAddr, _walletAdmin);

        vm.prank(_walletAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, _walletAdmin, _cwAddr));
        _policyRegistry.revokeWalletPolicyAdmin(_cwAddr, _walletAdmin);
    }

    function test_walletPolicyAdmin_isInvalidated_afterOwnershipTransfer() public {
        _grantWalletPolicyAdmin();

        vm.prank(_company);
        CompanyWallet(payable(_cwAddr)).transferOwnership(_secondOwner);

        assertEq(ICompanyWallet(_cwAddr).owner(), _secondOwner);

        // Old delegated admin must no longer be authorized after epoch advance.
        vm.prank(_walletAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, _walletAdmin, _cwAddr));
        _policyRegistry.setUserRoles(_cwAddr, _walletAdmin, _ROLE_A);
    }

    /*//////////////////////////////////////////////////////////////
                             grantUserRoles
    //////////////////////////////////////////////////////////////*/

    function test_grantUserRoles_success_whenCalledByWalletOwner() public {
        vm.expectEmit(true, true, true, true);
        emit IPolicyRegistry.WalletUserRolesGranted(_cwAddr, _user, _ROLE_A, _company);

        vm.prank(_company);
        _policyRegistry.grantUserRoles(_cwAddr, _user, _ROLE_A);

        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), _ROLE_A);
    }

    function test_grantUserRoles_success_whenCalledByDelegatedPolicyAdmin() public {
        _grantWalletPolicyAdmin();

        vm.prank(_walletAdmin);
        _policyRegistry.grantUserRoles(_cwAddr, _user, _ROLE_A);

        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), _ROLE_A);
    }

    function test_grantUserRoles_success_whenAddingNewRolesToExistingBitmap() public {
        vm.startPrank(_company);
        _policyRegistry.grantUserRoles(_cwAddr, _user, _ROLE_A);
        _policyRegistry.grantUserRoles(_cwAddr, _user, _ROLE_B);
        vm.stopPrank();

        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), _ROLE_A | _ROLE_B);
    }

    function test_grantUserRoles_reverts_whenCallerIsUnauthorized() public {
        address outsider = makeAddr("outsider");

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, outsider, _cwAddr));
        _policyRegistry.grantUserRoles(_cwAddr, _user, _ROLE_A);
    }

    function test_grantUserRoles_reverts_zeroWallet() public {
        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__InvalidWallet.selector, address(0)));
        _policyRegistry.grantUserRoles(address(0), _user, _ROLE_A);
    }

    function test_grantUserRoles_reverts_walletWithoutCode() public {
        address walletEoa = makeAddr("walletEoa");

        vm.prank(walletEoa);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__InvalidWallet.selector, walletEoa));
        _policyRegistry.grantUserRoles(walletEoa, _user, _ROLE_A);
    }

    function test_grantUserRoles_reverts_zeroUser() public {
        vm.prank(_company);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _policyRegistry.grantUserRoles(_cwAddr, address(0), _ROLE_A);
    }

    function test_grantUserRoles_reverts_zeroRoles() public {
        vm.prank(_company);
        vm.expectRevert(Errors.PolicyRegistry__ZeroRoles.selector);
        _policyRegistry.grantUserRoles(_cwAddr, _user, 0);
    }

    function test_grantUserRoles_reverts_whenRolesAlreadyGranted() public {
        vm.startPrank(_company);
        _policyRegistry.grantUserRoles(_cwAddr, _user, _ROLE_A | _ROLE_B);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.PolicyRegistry__UserRolesAlreadyGranted.selector, _cwAddr, _user, _ROLE_A)
        );
        _policyRegistry.grantUserRoles(_cwAddr, _user, _ROLE_A);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         grantUserRoles(batch)
    //////////////////////////////////////////////////////////////*/

    function test_grantUserRolesBatch_success_whenCalledByWalletOwner() public {
        address[] memory users = _users(_user, _walletAdmin);

        vm.prank(_company);
        _policyRegistry.grantUserRoles(_cwAddr, users, _ROLE_C);

        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), _ROLE_C);
        assertEq(_policyRegistry.getUserRoles(_cwAddr, _walletAdmin), _ROLE_C);
    }

    function test_grantUserRolesBatch_reverts_whenCallerIsUnauthorized() public {
        address outsider = makeAddr("outsider");
        address[] memory users = _users(_user, _walletAdmin);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, outsider, _cwAddr));
        _policyRegistry.grantUserRoles(_cwAddr, users, _ROLE_A);
    }

    function test_grantUserRolesBatch_reverts_zeroRoles() public {
        address[] memory users = _users(_user, _walletAdmin);

        vm.prank(_company);
        vm.expectRevert(Errors.PolicyRegistry__ZeroRoles.selector);
        _policyRegistry.grantUserRoles(_cwAddr, users, 0);
    }

    function test_grantUserRolesBatch_reverts_zeroUser() public {
        address[] memory users = _users(_user, address(0));

        vm.prank(_company);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _policyRegistry.grantUserRoles(_cwAddr, users, _ROLE_A);
    }

    function test_grantUserRolesBatch_reverts_whenRolesAlreadyGranted() public {
        address[] memory users = _users(_user, _walletAdmin);

        vm.prank(_company);
        _policyRegistry.grantUserRoles(_cwAddr, users, _ROLE_A);

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.PolicyRegistry__UserRolesAlreadyGranted.selector, _cwAddr, _user, _ROLE_A)
        );
        _policyRegistry.grantUserRoles(_cwAddr, users, _ROLE_A);
    }

    /*//////////////////////////////////////////////////////////////
                            revokeUserRoles
    //////////////////////////////////////////////////////////////*/

    function test_revokeUserRoles_success_whenCalledByWalletOwner() public {
        vm.prank(_company);
        _policyRegistry.grantUserRoles(_cwAddr, _user, _ROLE_A | _ROLE_B);

        vm.expectEmit(true, true, false, true);
        emit IPolicyRegistry.WalletUserRolesRevoked(_cwAddr, _user, _ROLE_A, _company);

        vm.prank(_company);
        _policyRegistry.revokeUserRoles(_cwAddr, _user, _ROLE_A);

        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), _ROLE_B);
    }

    function test_revokeUserRoles_success_whenCalledByDelegatedPolicyAdmin() public {
        _grantWalletPolicyAdmin();
        vm.prank(_company);
        _policyRegistry.grantUserRoles(_cwAddr, _user, _ROLE_A | _ROLE_B);

        vm.prank(_walletAdmin);
        _policyRegistry.revokeUserRoles(_cwAddr, _user, _ROLE_B);

        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), _ROLE_A);
    }

    function test_revokeUserRoles_reverts_whenCallerIsUnauthorized() public {
        address outsider = makeAddr("outsider");

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, outsider, _cwAddr));
        _policyRegistry.revokeUserRoles(_cwAddr, _user, _ROLE_A);
    }

    function test_revokeUserRoles_reverts_zeroUser() public {
        vm.prank(_company);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _policyRegistry.revokeUserRoles(_cwAddr, address(0), _ROLE_A);
    }

    function test_revokeUserRoles_reverts_zeroRoles() public {
        vm.prank(_company);
        vm.expectRevert(Errors.PolicyRegistry__ZeroRoles.selector);
        _policyRegistry.revokeUserRoles(_cwAddr, _user, 0);
    }

    function test_revokeUserRoles_reverts_whenRolesNotGranted() public {
        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.PolicyRegistry__UserRolesNotGranted.selector, _cwAddr, _user, _ROLE_C)
        );
        _policyRegistry.revokeUserRoles(_cwAddr, _user, _ROLE_C);
    }

    /*//////////////////////////////////////////////////////////////
                        revokeUserRoles(batch)
    //////////////////////////////////////////////////////////////*/

    function test_revokeUserRolesBatch_success_whenCalledByWalletOwner() public {
        address[] memory users = _users(_user, _walletAdmin);

        vm.prank(_company);
        _policyRegistry.grantUserRoles(_cwAddr, users, _ROLE_A | _ROLE_B);

        vm.prank(_company);
        _policyRegistry.revokeUserRoles(_cwAddr, users, _ROLE_B);

        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), _ROLE_A);
        assertEq(_policyRegistry.getUserRoles(_cwAddr, _walletAdmin), _ROLE_A);
    }

    function test_revokeUserRolesBatch_reverts_whenCallerIsUnauthorized() public {
        address outsider = makeAddr("outsider");
        address[] memory users = _users(_user, _walletAdmin);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, outsider, _cwAddr));
        _policyRegistry.revokeUserRoles(_cwAddr, users, _ROLE_A);
    }

    function test_revokeUserRolesBatch_reverts_zeroRoles() public {
        address[] memory users = _users(_user, _walletAdmin);

        vm.prank(_company);
        vm.expectRevert(Errors.PolicyRegistry__ZeroRoles.selector);
        _policyRegistry.revokeUserRoles(_cwAddr, users, 0);
    }

    function test_revokeUserRolesBatch_reverts_zeroUser() public {
        address[] memory users = _users(_user, address(0));

        vm.prank(_company);
        _policyRegistry.grantUserRoles(_cwAddr, _user, _ROLE_A);

        vm.prank(_company);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _policyRegistry.revokeUserRoles(_cwAddr, users, _ROLE_A);
    }

    function test_revokeUserRolesBatch_reverts_whenRolesNotGranted() public {
        address[] memory users = _users(_user, _walletAdmin);

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.PolicyRegistry__UserRolesNotGranted.selector, _cwAddr, _user, _ROLE_A)
        );
        _policyRegistry.revokeUserRoles(_cwAddr, users, _ROLE_A);
    }

    /*//////////////////////////////////////////////////////////////
                              setUserRoles
    //////////////////////////////////////////////////////////////*/

    function test_setUserRoles_success_whenCalledByWalletOwner() public {
        vm.expectEmit(true, true, false, true);
        emit IPolicyRegistry.WalletUserRolesSet(_cwAddr, _user, _ROLE_A | _ROLE_B | _ROLE_C);

        vm.prank(_company);
        _policyRegistry.setUserRoles(_cwAddr, _user, _ROLE_A | _ROLE_B | _ROLE_C);

        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), _ROLE_A | _ROLE_B | _ROLE_C);
    }

    function test_setUserRoles_success_whenCalledByDelegatedPolicyAdmin() public {
        _grantWalletPolicyAdmin();

        vm.prank(_walletAdmin);
        _policyRegistry.setUserRoles(_cwAddr, _user, _ROLE_B);

        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), _ROLE_B);
    }

    function test_setUserRoles_success_whenRolesDifferAcrossWallets() public {
        vm.prank(_company);
        _policyRegistry.setUserRoles(_cwAddr, _user, _ROLE_A);

        vm.prank(_secondOwner);
        _policyRegistry.setUserRoles(_secondWallet, _user, _ROLE_B);

        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), _ROLE_A);
        assertEq(_policyRegistry.getUserRoles(_secondWallet, _user), _ROLE_B);
    }

    function test_setUserRoles_reverts_whenCallerIsUnauthorized() public {
        address outsider = makeAddr("outsider");

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, outsider, _cwAddr));
        _policyRegistry.setUserRoles(_cwAddr, _user, _ROLE_A);
    }

    function test_setUserRoles_reverts_zeroUser() public {
        vm.prank(_company);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _policyRegistry.setUserRoles(_cwAddr, address(0), _ROLE_A);
    }

    /*//////////////////////////////////////////////////////////////
                           setUserRoles(batch)
    //////////////////////////////////////////////////////////////*/

    function test_setUserRolesBatch_success_whenCalledByWalletOwner() public {
        address[] memory users = _users(_user, _walletAdmin);
        uint256[] memory roles = _userRoles(_ROLE_A, _ROLE_B);

        vm.prank(_company);
        _policyRegistry.setUserRoles(_cwAddr, users, roles);

        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), _ROLE_A);
        assertEq(_policyRegistry.getUserRoles(_cwAddr, _walletAdmin), _ROLE_B);
    }

    function test_setUserRolesBatch_reverts_whenCallerIsUnauthorized() public {
        address outsider = makeAddr("outsider");
        address[] memory users = _users(_user, _walletAdmin);
        uint256[] memory roles = _userRoles(_ROLE_A, _ROLE_B);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, outsider, _cwAddr));
        _policyRegistry.setUserRoles(_cwAddr, users, roles);
    }

    function test_setUserRolesBatch_reverts_whenArrayLengthsMismatch() public {
        address[] memory users = _users(_user, _walletAdmin);
        uint256[] memory roles = new uint256[](1);
        roles[0] = _ROLE_A;

        vm.prank(_company);
        vm.expectRevert(Errors.LengthMismatch.selector);
        _policyRegistry.setUserRoles(_cwAddr, users, roles);
    }

    function test_setUserRolesBatch_reverts_zeroUser() public {
        address[] memory users = _users(_user, address(0));
        uint256[] memory roles = _userRoles(_ROLE_A, _ROLE_B);

        vm.prank(_company);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _policyRegistry.setUserRoles(_cwAddr, users, roles);
    }

    /*//////////////////////////////////////////////////////////////
                           grantOperationRoles
    //////////////////////////////////////////////////////////////*/

    function test_grantOperationRoles_success_whenCalledByWalletOwner() public {
        vm.expectEmit(true, true, true, true);
        emit IPolicyRegistry.WalletOperationRolesGranted(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A, _company
        );

        vm.prank(_company);
        _policyRegistry.grantOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A
        );

        assertEq(
            _policyRegistry.getOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            _ROLE_A
        );
    }

    function test_grantOperationRoles_success_whenCalledByDelegatedPolicyAdmin() public {
        _grantWalletPolicyAdmin();

        vm.prank(_walletAdmin);
        _policyRegistry.grantOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A
        );

        assertEq(
            _policyRegistry.getOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            _ROLE_A
        );
    }

    function test_grantOperationRoles_success_whenAddingNewRolesToExistingBitmap() public {
        vm.startPrank(_company);
        _policyRegistry.grantOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A
        );
        _policyRegistry.grantOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_B
        );
        vm.stopPrank();

        assertEq(
            _policyRegistry.getOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            _ROLE_A | _ROLE_B
        );
    }

    function test_grantOperationRoles_reverts_whenCallerIsUnauthorized() public {
        address outsider = makeAddr("outsider");

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, outsider, _cwAddr));
        _policyRegistry.grantOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A
        );
    }

    function test_grantOperationRoles_reverts_zeroRoles() public {
        vm.prank(_company);
        vm.expectRevert(Errors.PolicyRegistry__ZeroRoles.selector);
        _policyRegistry.grantOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, 0);
    }

    function test_grantOperationRoles_reverts_zeroTarget() public {
        vm.prank(_company);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _policyRegistry.grantOperationRoles(_cwAddr, address(0), MockTargetContract.simulateSuccess.selector, _ROLE_A);
    }

    function test_grantOperationRoles_reverts_zeroSelector() public {
        vm.prank(_company);
        vm.expectRevert(Errors.PolicyRegistry__ZeroSelector.selector);
        _policyRegistry.grantOperationRoles(_cwAddr, address(_target), bytes4(0), _ROLE_A);
    }

    function test_grantOperationRoles_reverts_whenRolesAlreadyGranted() public {
        vm.startPrank(_company);
        _policyRegistry.grantOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.PolicyRegistry__OperationRolesAlreadyGranted.selector,
                _cwAddr,
                address(_target),
                MockTargetContract.simulateSuccess.selector,
                _ROLE_A
            )
        );
        _policyRegistry.grantOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        grantOperationRoles(batch)
    //////////////////////////////////////////////////////////////*/

    function test_grantOperationRolesBatch_success_whenCalledByWalletOwner() public {
        OperationRoles[] memory operations = _operationRolesBatch(_ROLE_A, _ROLE_B);

        vm.prank(_company);
        _policyRegistry.grantOperationRoles(_cwAddr, operations);

        assertEq(
            _policyRegistry.getOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            _ROLE_A
        );
        assertEq(
            _policyRegistry.getOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateFailure.selector),
            _ROLE_B
        );
    }

    function test_grantOperationRolesBatch_reverts_whenCallerIsUnauthorized() public {
        address outsider = makeAddr("outsider");
        OperationRoles[] memory operations = _operationRolesBatch(_ROLE_A, _ROLE_B);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, outsider, _cwAddr));
        _policyRegistry.grantOperationRoles(_cwAddr, operations);
    }

    function test_grantOperationRolesBatch_reverts_zeroRoles() public {
        OperationRoles[] memory operations = _operationRolesBatch(0, _ROLE_B);

        vm.prank(_company);
        vm.expectRevert(Errors.PolicyRegistry__ZeroRoles.selector);
        _policyRegistry.grantOperationRoles(_cwAddr, operations);
    }

    function test_grantOperationRolesBatch_reverts_zeroTarget() public {
        OperationRoles[] memory operations = _operationRolesBatch(_ROLE_A, _ROLE_B);
        operations[1].target = address(0);

        vm.prank(_company);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _policyRegistry.grantOperationRoles(_cwAddr, operations);
    }

    function test_grantOperationRolesBatch_reverts_zeroSelector() public {
        OperationRoles[] memory operations = _operationRolesBatch(_ROLE_A, _ROLE_B);
        operations[1].selector = bytes4(0);

        vm.prank(_company);
        vm.expectRevert(Errors.PolicyRegistry__ZeroSelector.selector);
        _policyRegistry.grantOperationRoles(_cwAddr, operations);
    }

    function test_grantOperationRolesBatch_reverts_whenRolesAlreadyGranted() public {
        OperationRoles[] memory operations = _operationRolesBatch(_ROLE_A, _ROLE_B);

        vm.prank(_company);
        _policyRegistry.grantOperationRoles(_cwAddr, operations);

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.PolicyRegistry__OperationRolesAlreadyGranted.selector,
                _cwAddr,
                address(_target),
                MockTargetContract.simulateSuccess.selector,
                _ROLE_A
            )
        );
        _policyRegistry.grantOperationRoles(_cwAddr, operations);
    }

    /*//////////////////////////////////////////////////////////////
                           revokeOperationRoles
    //////////////////////////////////////////////////////////////*/

    function test_revokeOperationRoles_success_whenCalledByWalletOwner() public {
        vm.prank(_company);
        _policyRegistry.grantOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A | _ROLE_B
        );

        vm.expectEmit(true, true, true, true);
        emit IPolicyRegistry.WalletOperationRolesRevoked(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A, _company
        );

        vm.prank(_company);
        _policyRegistry.revokeOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A
        );

        assertEq(
            _policyRegistry.getOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            _ROLE_B
        );
    }

    function test_revokeOperationRoles_success_whenCalledByDelegatedPolicyAdmin() public {
        _grantWalletPolicyAdmin();

        vm.prank(_company);
        _policyRegistry.grantOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A | _ROLE_B
        );

        vm.prank(_walletAdmin);
        _policyRegistry.revokeOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_B
        );

        assertEq(
            _policyRegistry.getOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            _ROLE_A
        );
    }

    function test_revokeOperationRoles_reverts_whenCallerIsUnauthorized() public {
        address outsider = makeAddr("outsider");

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, outsider, _cwAddr));
        _policyRegistry.revokeOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A
        );
    }

    function test_revokeOperationRoles_reverts_zeroRoles() public {
        vm.prank(_company);
        vm.expectRevert(Errors.PolicyRegistry__ZeroRoles.selector);
        _policyRegistry.revokeOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, 0);
    }

    function test_revokeOperationRoles_reverts_zeroTarget() public {
        vm.prank(_company);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _policyRegistry.revokeOperationRoles(_cwAddr, address(0), MockTargetContract.simulateSuccess.selector, _ROLE_A);
    }

    function test_revokeOperationRoles_reverts_zeroSelector() public {
        vm.prank(_company);
        vm.expectRevert(Errors.PolicyRegistry__ZeroSelector.selector);
        _policyRegistry.revokeOperationRoles(_cwAddr, address(_target), bytes4(0), _ROLE_A);
    }

    function test_revokeOperationRoles_reverts_whenRolesNotGranted() public {
        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.PolicyRegistry__OperationRolesNotGranted.selector,
                _cwAddr,
                address(_target),
                MockTargetContract.simulateFailure.selector,
                _ROLE_A
            )
        );
        _policyRegistry.revokeOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateFailure.selector, _ROLE_A
        );
    }

    /*//////////////////////////////////////////////////////////////
                       revokeOperationRoles(batch)
    //////////////////////////////////////////////////////////////*/

    function test_revokeOperationRolesBatch_success_whenCalledByWalletOwner() public {
        OperationRoles[] memory operations = _operationRolesBatch(_ROLE_A, _ROLE_B);

        vm.prank(_company);
        _policyRegistry.grantOperationRoles(_cwAddr, operations);

        vm.prank(_company);
        _policyRegistry.revokeOperationRoles(_cwAddr, operations);

        assertEq(
            _policyRegistry.getOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector), 0
        );
        assertEq(
            _policyRegistry.getOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateFailure.selector), 0
        );
    }

    function test_revokeOperationRolesBatch_reverts_whenCallerIsUnauthorized() public {
        address outsider = makeAddr("outsider");
        OperationRoles[] memory operations = _operationRolesBatch(_ROLE_A, _ROLE_B);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, outsider, _cwAddr));
        _policyRegistry.revokeOperationRoles(_cwAddr, operations);
    }

    function test_revokeOperationRolesBatch_reverts_zeroRoles() public {
        OperationRoles[] memory operations = _operationRolesBatch(0, _ROLE_B);

        vm.prank(_company);
        vm.expectRevert(Errors.PolicyRegistry__ZeroRoles.selector);
        _policyRegistry.revokeOperationRoles(_cwAddr, operations);
    }

    function test_revokeOperationRolesBatch_reverts_zeroTarget() public {
        OperationRoles[] memory operations = _operationRolesBatch(_ROLE_A, _ROLE_B);
        operations[1].target = address(0);

        vm.prank(_company);
        _policyRegistry.grantOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A
        );

        vm.prank(_company);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _policyRegistry.revokeOperationRoles(_cwAddr, operations);
    }

    function test_revokeOperationRolesBatch_reverts_zeroSelector() public {
        OperationRoles[] memory operations = _operationRolesBatch(_ROLE_A, _ROLE_B);
        operations[1].selector = bytes4(0);

        vm.prank(_company);
        _policyRegistry.grantOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A
        );

        vm.prank(_company);
        vm.expectRevert(Errors.PolicyRegistry__ZeroSelector.selector);
        _policyRegistry.revokeOperationRoles(_cwAddr, operations);
    }

    function test_revokeOperationRolesBatch_reverts_whenRolesNotGranted() public {
        OperationRoles[] memory operations = _operationRolesBatch(_ROLE_A, _ROLE_B);

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.PolicyRegistry__OperationRolesNotGranted.selector,
                _cwAddr,
                address(_target),
                MockTargetContract.simulateSuccess.selector,
                _ROLE_A
            )
        );
        _policyRegistry.revokeOperationRoles(_cwAddr, operations);
    }

    /*//////////////////////////////////////////////////////////////
                            setOperationRoles
    //////////////////////////////////////////////////////////////*/

    function test_setOperationRoles_success_whenCalledByWalletOwner() public {
        vm.expectEmit(true, true, true, true);
        emit IPolicyRegistry.WalletOperationRolesSet(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A | _ROLE_C
        );

        vm.prank(_company);
        _policyRegistry.setOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A | _ROLE_C
        );

        assertEq(
            _policyRegistry.getOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            _ROLE_A | _ROLE_C
        );
    }

    function test_setOperationRoles_success_whenCalledByDelegatedPolicyAdmin() public {
        _grantWalletPolicyAdmin();

        vm.prank(_walletAdmin);
        _policyRegistry.setOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_B
        );

        assertEq(
            _policyRegistry.getOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            _ROLE_B
        );
    }

    function test_setOperationRoles_reverts_whenCallerIsUnauthorized() public {
        address outsider = makeAddr("outsider");

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, outsider, _cwAddr));
        _policyRegistry.setOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A
        );
    }

    function test_setOperationRoles_reverts_zeroTarget() public {
        vm.prank(_company);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _policyRegistry.setOperationRoles(_cwAddr, address(0), MockTargetContract.simulateSuccess.selector, _ROLE_A);
    }

    function test_setOperationRoles_reverts_zeroSelector() public {
        vm.prank(_company);
        vm.expectRevert(Errors.PolicyRegistry__ZeroSelector.selector);
        _policyRegistry.setOperationRoles(_cwAddr, address(_target), bytes4(0), _ROLE_A);
    }

    /*//////////////////////////////////////////////////////////////
                         setOperationRoles(batch)
    //////////////////////////////////////////////////////////////*/

    function test_setOperationRolesBatch_success_whenCalledByWalletOwner() public {
        OperationRoles[] memory operations = _operationRolesBatch(_ROLE_A, _ROLE_B);

        vm.prank(_company);
        _policyRegistry.setOperationRoles(_cwAddr, operations);

        assertEq(
            _policyRegistry.getOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            _ROLE_A
        );
        assertEq(
            _policyRegistry.getOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateFailure.selector),
            _ROLE_B
        );
    }

    function test_setOperationRolesBatch_reverts_whenCallerIsUnauthorized() public {
        address outsider = makeAddr("outsider");
        OperationRoles[] memory operations = _operationRolesBatch(_ROLE_A, _ROLE_B);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, outsider, _cwAddr));
        _policyRegistry.setOperationRoles(_cwAddr, operations);
    }

    function test_setOperationRolesBatch_reverts_zeroTarget() public {
        OperationRoles[] memory operations = _operationRolesBatch(_ROLE_A, _ROLE_B);
        operations[1].target = address(0);

        vm.prank(_company);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _policyRegistry.setOperationRoles(_cwAddr, operations);
    }

    function test_setOperationRolesBatch_reverts_zeroSelector() public {
        OperationRoles[] memory operations = _operationRolesBatch(_ROLE_A, _ROLE_B);
        operations[1].selector = bytes4(0);

        vm.prank(_company);
        vm.expectRevert(Errors.PolicyRegistry__ZeroSelector.selector);
        _policyRegistry.setOperationRoles(_cwAddr, operations);
    }

    /*//////////////////////////////////////////////////////////////
                            setOperationModule
    //////////////////////////////////////////////////////////////*/

    function test_setOperationModule_success_whenCalledByWalletOwner() public {
        _allowPolicyModule(address(_allowModule));

        vm.expectEmit(true, true, true, true);
        emit IPolicyRegistry.WalletOperationModuleSet(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_allowModule)
        );

        vm.prank(_company);
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_allowModule)
        );

        assertEq(
            _policyRegistry.getOperationModule(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            address(_allowModule)
        );
    }

    function test_setOperationModule_success_whenCalledByDelegatedPolicyAdmin() public {
        _grantWalletPolicyAdmin();
        _allowPolicyModule(address(_allowModule));

        vm.prank(_walletAdmin);
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_allowModule)
        );

        assertEq(
            _policyRegistry.getOperationModule(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            address(_allowModule)
        );
    }

    function test_setOperationModule_success_whenClearingModuleWithZeroAddress() public {
        _allowPolicyModule(address(_allowModule));

        vm.startPrank(_company);
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_allowModule)
        );
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(0)
        );
        vm.stopPrank();

        assertEq(
            _policyRegistry.getOperationModule(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            address(0)
        );
    }

    function test_setOperationModule_reverts_whenCallerIsUnauthorized() public {
        address outsider = makeAddr("outsider");

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, outsider, _cwAddr));
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_allowModule)
        );
    }

    function test_setOperationModule_reverts_zeroTarget() public {
        vm.prank(_company);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _policyRegistry.setOperationModule(
            address(_cwAddr), address(0), MockTargetContract.simulateSuccess.selector, address(0)
        );
    }

    function test_setOperationModule_reverts_zeroSelector() public {
        vm.prank(_company);
        vm.expectRevert(Errors.PolicyRegistry__ZeroSelector.selector);
        _policyRegistry.setOperationModule(_cwAddr, address(_target), bytes4(0), address(0));
    }

    function test_setOperationModule_reverts_whenModuleNotAllowlisted() public {
        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.PolicyRegistry__PolicyModuleNotAllowed.selector, address(_allowModule))
        );
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_allowModule)
        );
    }

    function test_setOperationModule_reverts_whenModuleAddressHasNoCode() public {
        address eoa = makeAddr("moduleEoa");

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__InvalidPolicyModule.selector, eoa));
        _policyRegistry.setOperationModule(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, eoa);
    }

    function test_setOperationModule_reverts_whenModuleContractDoesNotSupportInterface() public {
        MockTargetContract invalidModule = new MockTargetContract();
        _allowPolicyModule(address(_allowModule));

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.PolicyRegistry__InvalidPolicyModule.selector, address(invalidModule))
        );
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(invalidModule)
        );
    }

    /*//////////////////////////////////////////////////////////////
                         setOperationModule(batch)
    //////////////////////////////////////////////////////////////*/

    function test_setOperationModuleBatch_success_whenCalledByWalletOwner() public {
        _allowPolicyModule(address(_allowModule));
        _allowPolicyModule(address(_denyModule));
        OperationModule[] memory operations = _operationModuleBatch(address(_allowModule), address(_denyModule));

        vm.prank(_company);
        _policyRegistry.setOperationModule(_cwAddr, operations);

        assertEq(
            _policyRegistry.getOperationModule(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            address(_allowModule)
        );
        assertEq(
            _policyRegistry.getOperationModule(_cwAddr, address(_target), MockTargetContract.simulateFailure.selector),
            address(_denyModule)
        );
    }

    function test_setOperationModuleBatch_reverts_whenCallerIsUnauthorized() public {
        address outsider = makeAddr("outsider");
        OperationModule[] memory operations = _operationModuleBatch(address(_allowModule), address(_denyModule));

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, outsider, _cwAddr));
        _policyRegistry.setOperationModule(_cwAddr, operations);
    }

    function test_setOperationModuleBatch_reverts_zeroTarget() public {
        OperationModule[] memory operations = _operationModuleBatch(address(0), address(0));
        operations[1].target = address(0);

        vm.prank(_company);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _policyRegistry.setOperationModule(_cwAddr, operations);
    }

    function test_setOperationModuleBatch_reverts_zeroSelector() public {
        OperationModule[] memory operations = _operationModuleBatch(address(0), address(0));
        operations[1].selector = bytes4(0);

        vm.prank(_company);
        vm.expectRevert(Errors.PolicyRegistry__ZeroSelector.selector);
        _policyRegistry.setOperationModule(_cwAddr, operations);
    }

    function test_setOperationModuleBatch_reverts_whenModuleNotAllowlisted() public {
        OperationModule[] memory operations = _operationModuleBatch(address(_allowModule), address(0));

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.PolicyRegistry__PolicyModuleNotAllowed.selector, address(_allowModule))
        );
        _policyRegistry.setOperationModule(_cwAddr, operations);
    }

    function test_setOperationModuleBatch_reverts_whenModuleAddressHasNoCode() public {
        address eoa = makeAddr("moduleEoa");
        OperationModule[] memory operations = _operationModuleBatch(eoa, address(0));

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__InvalidPolicyModule.selector, eoa));
        _policyRegistry.setOperationModule(_cwAddr, operations);
    }

    function test_setOperationModuleBatch_reverts_whenModuleContractDoesNotSupportInterface() public {
        MockTargetContract invalidModule = new MockTargetContract();
        OperationModule[] memory operations = _operationModuleBatch(address(invalidModule), address(0));

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.PolicyRegistry__InvalidPolicyModule.selector, address(invalidModule))
        );
        _policyRegistry.setOperationModule(_cwAddr, operations);
    }

    /*//////////////////////////////////////////////////////////////
                               setRoleLabel
    //////////////////////////////////////////////////////////////*/

    function test_setRoleLabel_success_whenCalledByOwner() public {
        bytes memory data =
            abi.encodeWithSelector(IPolicyRegistry.setRoleLabel.selector, _ROLE_LABEL_ID, _ROLE_LABEL_TRADER);
        _timelockSchedule(address(_policyRegistry), data);

        vm.expectEmit(true, true, false, false);
        emit IPolicyRegistry.RoleLabelSet(_ROLE_LABEL_ID, _ROLE_LABEL_TRADER);
        _timelockExecute(address(_policyRegistry), data);

        assertEq(_policyRegistry.roleLabels(_ROLE_LABEL_ID), _ROLE_LABEL_TRADER);
    }

    function test_setRoleLabel_reverts_whenCallerIsNotOwner() public {
        vm.prank(_company);
        vm.expectRevert();
        _policyRegistry.setRoleLabel(_ROLE_LABEL_ID, _ROLE_LABEL_TRADER);
    }

    /*//////////////////////////////////////////////////////////////
                           setPolicyModuleAllowed
    //////////////////////////////////////////////////////////////*/

    function test_setPolicyModuleAllowed_success_whenSettingAllowedTrue() public {
        bytes memory data =
            abi.encodeWithSelector(IPolicyRegistry.setPolicyModuleAllowed.selector, address(_allowModule), true);
        _timelockSchedule(address(_policyRegistry), data);

        vm.expectEmit(true, false, false, true);
        emit IPolicyRegistry.PolicyModuleAllowed(address(_allowModule), true);
        _timelockExecute(address(_policyRegistry), data);

        assertTrue(_policyRegistry.isPolicyModuleAllowed(address(_allowModule)));
    }

    function test_setPolicyModuleAllowed_success_whenSettingAllowedFalse() public {
        _allowPolicyModule(address(_allowModule));
        bytes memory data =
            abi.encodeWithSelector(IPolicyRegistry.setPolicyModuleAllowed.selector, address(_allowModule), false);
        _timelockSchedule(address(_policyRegistry), data);

        vm.expectEmit(true, false, false, true);
        emit IPolicyRegistry.PolicyModuleAllowed(address(_allowModule), false);
        _timelockExecute(address(_policyRegistry), data);

        assertFalse(_policyRegistry.isPolicyModuleAllowed(address(_allowModule)));
    }

    function test_setPolicyModuleAllowed_reverts_whenCallerIsNotOwner() public {
        vm.prank(_company);
        vm.expectRevert();
        _policyRegistry.setPolicyModuleAllowed(address(_allowModule), true);
    }

    function test_setPolicyModuleAllowed_reverts_zeroModule() public {
        bytes memory data = abi.encodeWithSelector(IPolicyRegistry.setPolicyModuleAllowed.selector, address(0), true);
        _timelockSchedule(address(_policyRegistry), data);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__InvalidPolicyModule.selector, address(0)));
        _timelockExecute(address(_policyRegistry), data);
    }

    function test_setPolicyModuleAllowed_reverts_whenModuleAddressHasNoCode() public {
        address eoa = makeAddr("moduleEoa");

        bytes memory data = abi.encodeWithSelector(IPolicyRegistry.setPolicyModuleAllowed.selector, eoa, true);
        _timelockSchedule(address(_policyRegistry), data);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__InvalidPolicyModule.selector, eoa));
        _timelockExecute(address(_policyRegistry), data);
    }

    function test_setPolicyModuleAllowed_reverts_whenModuleContractDoesNotSupportInterface() public {
        MockTargetContract invalidModule = new MockTargetContract();

        bytes memory data =
            abi.encodeWithSelector(IPolicyRegistry.setPolicyModuleAllowed.selector, address(invalidModule), true);
        _timelockSchedule(address(_policyRegistry), data);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.PolicyRegistry__InvalidPolicyModule.selector, address(invalidModule))
        );
        _timelockExecute(address(_policyRegistry), data);
    }

    /*//////////////////////////////////////////////////////////////
                               canExecute
    //////////////////////////////////////////////////////////////*/

    function test_canExecute_success_whenBaseAuthorizationPassesWithoutModule() public {
        _grantBaseAuthorization(_cwAddr, _user, _ROLE_A, _ROLE_A, MockTargetContract.simulateSuccess.selector);

        assertTrue(_policyRegistry.canExecute(_cwAddr, _user, address(_target), 0, _successCallData()));
    }

    function test_canExecute_success_whenModuleApprovesExecution() public {
        _grantBaseAuthorization(_cwAddr, _user, _ROLE_A, _ROLE_A, MockTargetContract.simulateSuccess.selector);
        _allowPolicyModule(address(_allowModule));

        vm.prank(_company);
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_allowModule)
        );

        assertTrue(_policyRegistry.canExecute(_cwAddr, _user, address(_target), 0, _successCallData()));
    }

    function test_canExecute_success_returnsFalseForInvalidRequestZeroWallet() public view {
        assertFalse(_policyRegistry.canExecute(address(0), _user, address(_target), 0, _successCallData()));
    }

    function test_canExecute_success_returnsFalseForInvalidRequestZeroCaller() public view {
        assertFalse(_policyRegistry.canExecute(_cwAddr, address(0), address(_target), 0, _successCallData()));
    }

    function test_canExecute_success_returnsFalseForInvalidRequestZeroTarget() public view {
        assertFalse(_policyRegistry.canExecute(_cwAddr, _user, address(0), 0, _successCallData()));
    }

    function test_canExecute_success_returnsFalseForInvalidRequestShortCallData() public view {
        assertFalse(_policyRegistry.canExecute(_cwAddr, _user, address(_target), 0, hex"123456"));
    }

    function test_canExecute_success_returnsFalseWhenUserHasNoRoles() public view {
        assertFalse(_policyRegistry.canExecute(_cwAddr, _user, address(_target), 0, _successCallData()));
    }

    function test_canExecute_success_returnsFalseWhenOperationHasNoMatchingRoles() public {
        _grantBaseAuthorization(_cwAddr, _user, _ROLE_A, _ROLE_B, MockTargetContract.simulateSuccess.selector);

        assertFalse(_policyRegistry.canExecute(_cwAddr, _user, address(_target), 0, _successCallData()));
    }

    function test_canExecute_success_returnsFalseWhenConfiguredModuleIsNotAllowlisted() public {
        _grantBaseAuthorization(_cwAddr, _user, _ROLE_A, _ROLE_A, MockTargetContract.simulateSuccess.selector);
        _allowPolicyModule(address(_allowModule));

        vm.prank(_company);
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_allowModule)
        );

        _timelockOp(
            address(_policyRegistry),
            abi.encodeWithSelector(IPolicyRegistry.setPolicyModuleAllowed.selector, address(_allowModule), false)
        );

        assertFalse(_policyRegistry.canExecute(_cwAddr, _user, address(_target), 0, _successCallData()));
    }

    function test_canExecute_success_returnsFalseWhenModuleRejectsExecution() public {
        _grantBaseAuthorization(_cwAddr, _user, _ROLE_A, _ROLE_A, MockTargetContract.simulateSuccess.selector);
        _allowPolicyModule(address(_denyModule));

        vm.prank(_company);
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_denyModule)
        );

        assertFalse(_policyRegistry.canExecute(_cwAddr, _user, address(_target), 0, _successCallData()));
    }

    function test_canExecute_success_returnsFalseWhenModuleCallReverts() public {
        _grantBaseAuthorization(_cwAddr, _user, _ROLE_A, _ROLE_A, MockTargetContract.simulateSuccess.selector);
        _allowPolicyModule(address(_revertingModule));

        vm.prank(_company);
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_revertingModule)
        );

        assertFalse(_policyRegistry.canExecute(_cwAddr, _user, address(_target), 0, _successCallData()));
    }

    function test_canExecute_success_returnsFalseWhenModuleReturnsInvalidPayload() public {
        _grantBaseAuthorization(_cwAddr, _user, _ROLE_A, _ROLE_A, MockTargetContract.simulateSuccess.selector);
        _allowPolicyModule(address(_invalidReturnModule));

        vm.prank(_company);
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_invalidReturnModule)
        );

        assertFalse(_policyRegistry.canExecute(_cwAddr, _user, address(_target), 0, _successCallData()));
    }

    /*//////////////////////////////////////////////////////////////
                           checkOperationModule
    //////////////////////////////////////////////////////////////*/

    function test_checkOperationModule_success_returnsEmptyResultWhenNoModuleConfigured() public view {
        ModuleExecutionCheck memory result =
            _policyRegistry.checkOperationModule(_cwAddr, _user, address(_target), 0, _successCallData());

        assertFalse(result.hasModule);
        assertEq(result.module, address(0));
        assertFalse(result.moduleAllowed);
        assertFalse(result.moduleCallSucceeded);
        assertFalse(result.moduleAuthorized);
    }

    function test_checkOperationModule_success_returnsAuthorizedResultWhenModuleApproves() public {
        _allowPolicyModule(address(_allowModule));

        vm.prank(_company);
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_allowModule)
        );

        ModuleExecutionCheck memory result =
            _policyRegistry.checkOperationModule(_cwAddr, _user, address(_target), 0, _successCallData());

        assertTrue(result.hasModule);
        assertEq(result.module, address(_allowModule));
        assertTrue(result.moduleAllowed);
        assertTrue(result.moduleCallSucceeded);
        assertTrue(result.moduleAuthorized);
    }

    function test_checkOperationModule_success_returnsDisallowedResultWhenModuleRemovedFromAllowlist() public {
        _allowPolicyModule(address(_allowModule));

        vm.prank(_company);
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_allowModule)
        );

        _timelockOp(
            address(_policyRegistry),
            abi.encodeWithSelector(IPolicyRegistry.setPolicyModuleAllowed.selector, address(_allowModule), false)
        );

        ModuleExecutionCheck memory result =
            _policyRegistry.checkOperationModule(_cwAddr, _user, address(_target), 0, _successCallData());

        assertTrue(result.hasModule);
        assertEq(result.module, address(_allowModule));
        assertFalse(result.moduleAllowed);
        assertFalse(result.moduleCallSucceeded);
        assertFalse(result.moduleAuthorized);
    }

    function test_checkOperationModule_success_returnsRejectedResultWhenModuleReturnsFalse() public {
        _allowPolicyModule(address(_denyModule));

        vm.prank(_company);
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_denyModule)
        );

        ModuleExecutionCheck memory result =
            _policyRegistry.checkOperationModule(_cwAddr, _user, address(_target), 0, _successCallData());

        assertTrue(result.hasModule);
        assertEq(result.module, address(_denyModule));
        assertTrue(result.moduleAllowed);
        assertTrue(result.moduleCallSucceeded);
        assertFalse(result.moduleAuthorized);
    }

    function test_checkOperationModule_success_returnsFailedResultWhenModuleCallReverts() public {
        _allowPolicyModule(address(_revertingModule));

        vm.prank(_company);
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_revertingModule)
        );

        ModuleExecutionCheck memory result =
            _policyRegistry.checkOperationModule(_cwAddr, _user, address(_target), 0, _successCallData());

        assertTrue(result.hasModule);
        assertEq(result.module, address(_revertingModule));
        assertTrue(result.moduleAllowed);
        assertFalse(result.moduleCallSucceeded);
        assertFalse(result.moduleAuthorized);
    }

    function test_checkOperationModule_success_returnsFailedResultWhenModuleReturnsInvalidPayload() public {
        _allowPolicyModule(address(_invalidReturnModule));

        vm.prank(_company);
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_invalidReturnModule)
        );

        ModuleExecutionCheck memory result =
            _policyRegistry.checkOperationModule(_cwAddr, _user, address(_target), 0, _successCallData());

        assertTrue(result.hasModule);
        assertEq(result.module, address(_invalidReturnModule));
        assertTrue(result.moduleAllowed);
        assertFalse(result.moduleCallSucceeded);
        assertFalse(result.moduleAuthorized);
    }

    function test_checkOperationModule_success_returnsEmptyResultForZeroWallet() public view {
        ModuleExecutionCheck memory result =
            _policyRegistry.checkOperationModule(address(0), _user, address(_target), 0, _successCallData());

        assertFalse(result.hasModule);
        assertEq(result.module, address(0));
    }

    function test_checkOperationModule_success_returnsEmptyResultForZeroCaller() public view {
        ModuleExecutionCheck memory result =
            _policyRegistry.checkOperationModule(_cwAddr, address(0), address(_target), 0, _successCallData());

        assertFalse(result.hasModule);
        assertEq(result.module, address(0));
    }

    function test_checkOperationModule_success_returnsEmptyResultForZeroTarget() public view {
        ModuleExecutionCheck memory result =
            _policyRegistry.checkOperationModule(_cwAddr, _user, address(0), 0, _successCallData());

        assertFalse(result.hasModule);
        assertEq(result.module, address(0));
    }

    function test_checkOperationModule_success_returnsEmptyResultForShortCallData() public view {
        ModuleExecutionCheck memory result =
            _policyRegistry.checkOperationModule(_cwAddr, _user, address(_target), 0, hex"123456");

        assertFalse(result.hasModule);
        assertEq(result.module, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function test_isWalletPolicyAdmin_success_returnsFalseWhenUnset() public view {
        assertFalse(_policyRegistry.isWalletPolicyAdmin(_cwAddr, _walletAdmin));
    }

    function test_isWalletPolicyAdmin_success_returnsTrueWhenGranted() public {
        _grantWalletPolicyAdmin();
        assertTrue(_policyRegistry.isWalletPolicyAdmin(_cwAddr, _walletAdmin));
    }

    function test_isPolicyModuleAllowed_success_returnsFalseWhenUnset() public view {
        assertFalse(_policyRegistry.isPolicyModuleAllowed(address(_allowModule)));
    }

    function test_isPolicyModuleAllowed_success_returnsTrueWhenAllowlisted() public {
        _allowPolicyModule(address(_allowModule));
        assertTrue(_policyRegistry.isPolicyModuleAllowed(address(_allowModule)));
    }

    function test_roleLabels_success_returnsDefaultValueWhenUnset() public view {
        assertEq(_policyRegistry.roleLabels(1), bytes32(0));
    }

    function test_roleLabels_success_returnsStoredValueWhenSet() public {
        _timelockOp(
            address(_policyRegistry),
            abi.encodeWithSelector(IPolicyRegistry.setRoleLabel.selector, _ROLE_LABEL_ID, _ROLE_LABEL_TRADER)
        );
        assertEq(_policyRegistry.roleLabels(_ROLE_LABEL_ID), _ROLE_LABEL_TRADER);
    }

    function test_getUserRoles_success_returnsDefaultValueWhenUnset() public view {
        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), 0);
    }

    function test_getUserRoles_success_returnsStoredValueWhenSet() public {
        vm.prank(_company);
        _policyRegistry.setUserRoles(_cwAddr, _user, _ROLE_A);
        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), _ROLE_A);
    }

    function test_getOperationRoles_success_returnsDefaultValueWhenUnset() public view {
        assertEq(
            _policyRegistry.getOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector), 0
        );
    }

    function test_getOperationRoles_success_returnsStoredValueWhenSet() public {
        vm.prank(_company);
        _policyRegistry.setOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A
        );
        assertEq(
            _policyRegistry.getOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            _ROLE_A
        );
    }

    function test_getOperationModule_success_returnsDefaultValueWhenUnset() public view {
        assertEq(
            _policyRegistry.getOperationModule(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            address(0)
        );
    }

    function test_getOperationModule_success_returnsStoredValueWhenSet() public {
        _allowPolicyModule(address(_allowModule));

        vm.prank(_company);
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_allowModule)
        );

        assertEq(
            _policyRegistry.getOperationModule(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            address(_allowModule)
        );
    }

    function test_computeOperationKey_success_returnsExpectedHash() public view {
        assertEq(
            _policyRegistry.computeOperationKey(address(_target), MockTargetContract.simulateSuccess.selector),
            keccak256(abi.encode(address(_target), MockTargetContract.simulateSuccess.selector))
        );
    }

    function test_supportsInterface_success_returnsTrueForPolicyRegistry() public view {
        assertTrue(_policyRegistry.supportsInterface(type(IPolicyRegistry).interfaceId));
        assertTrue(_policyRegistry.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_success_returnsFalseForUnsupportedInterface() public view {
        assertFalse(_policyRegistry.supportsInterface(bytes4(0x12345678)));
    }

    /*//////////////////////////////////////////////////////////////
                          OWNERSHIP EPOCH
    //////////////////////////////////////////////////////////////*/

    function test_advancePolicyEpoch_success_invalidatesRecoverableOwnerPolicyState() public {
        // ARRANGE: create a wallet whose owner address is a stable recoverable account proxy.
        address controller = makeAddr("controller");
        address recoverer = makeAddr("recoverer");
        address replacementController = makeAddr("replacementController");
        RecoverableOwnerProxy ownerProxy = new RecoverableOwnerProxy(controller, recoverer);
        (address wallet,) = _createAndRegisterEntityWalletForCompany(_erAdmin, address(ownerProxy));

        // ARRANGE: the original controller configures delegated policy for epoch 1.
        vm.prank(controller);
        ownerProxy.callAsOwner(
            address(_policyRegistry), abi.encodeCall(IPolicyRegistry.grantWalletPolicyAdmin, (wallet, _walletAdmin))
        );

        vm.startPrank(controller);
        ownerProxy.callAsOwner(
            address(_policyRegistry), abi.encodeWithSelector(_GRANT_USER_ROLES_SELECTOR, wallet, _user, _ROLE_A)
        );
        ownerProxy.callAsOwner(
            address(_policyRegistry),
            abi.encodeWithSelector(
                _GRANT_OPERATION_ROLES_SELECTOR,
                wallet,
                address(_target),
                MockTargetContract.simulateSuccess.selector,
                _ROLE_A
            )
        );
        vm.stopPrank();

        assertEq(ICompanyWallet(wallet).owner(), address(ownerProxy));
        assertEq(ICompanyWallet(wallet).ownershipEpoch(), 1);
        assertTrue(_policyRegistry.isWalletPolicyAdmin(wallet, _walletAdmin));
        assertTrue(_policyRegistry.canExecute(wallet, _user, address(_target), 0, _successCallData()));

        // ACT: recovery rotates the proxy controller, but the CompanyWallet owner address is unchanged.
        vm.prank(recoverer);
        ownerProxy.recover(replacementController);

        // ASSERT: without an epoch advance, previous delegated policy remains active in epoch 1.
        assertEq(ownerProxy.controller(), replacementController);
        assertEq(ICompanyWallet(wallet).owner(), address(ownerProxy));
        assertEq(ICompanyWallet(wallet).ownershipEpoch(), 1);
        assertTrue(_policyRegistry.isWalletPolicyAdmin(wallet, _walletAdmin));
        assertTrue(_policyRegistry.canExecute(wallet, _user, address(_target), 0, _successCallData()));

        bytes32 reason = keccak256("KERNEL_RECOVERY");

        vm.expectEmit(true, true, true, true, wallet);
        emit ICompanyWallet.OwnershipEpochAdvanced(1, 2, reason, address(ownerProxy));

        // ACT: the recovered controller deliberately advances the wallet policy epoch.
        vm.prank(replacementController);
        ownerProxy.callAsOwner(wallet, abi.encodeCall(ICompanyWallet.advancePolicyEpoch, (reason)));

        // ASSERT: all epoch-scoped delegated policy from before recovery is now unreachable.
        assertEq(ICompanyWallet(wallet).ownershipEpoch(), 2);
        assertFalse(_policyRegistry.isWalletPolicyAdmin(wallet, _walletAdmin));
        assertEq(_policyRegistry.getUserRoles(wallet, _user), 0);
        assertEq(
            _policyRegistry.getOperationRoles(wallet, address(_target), MockTargetContract.simulateSuccess.selector), 0
        );
        assertFalse(_policyRegistry.canExecute(wallet, _user, address(_target), 0, _successCallData()));

        vm.prank(_walletAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, _walletAdmin, wallet));
        _policyRegistry.setUserRoles(wallet, _user, _ROLE_B);

        // ASSERT: the recovered controller can configure fresh policy in the new epoch.
        vm.startPrank(replacementController);
        ownerProxy.callAsOwner(
            address(_policyRegistry), abi.encodeWithSelector(_GRANT_USER_ROLES_SELECTOR, wallet, _user, _ROLE_B)
        );
        ownerProxy.callAsOwner(
            address(_policyRegistry),
            abi.encodeWithSelector(
                _GRANT_OPERATION_ROLES_SELECTOR,
                wallet,
                address(_target),
                MockTargetContract.simulateSuccess.selector,
                _ROLE_B
            )
        );
        vm.stopPrank();

        assertTrue(_policyRegistry.canExecute(wallet, _user, address(_target), 0, _successCallData()));
    }

    function test_ownershipEpoch_isInvalidated_oldAdminCannotManagePolicy() public {
        // Set up: owner grants admin rights and configures roles.
        _grantWalletPolicyAdmin();
        vm.startPrank(_company);
        _policyRegistry.grantUserRoles(_cwAddr, _user, _ROLE_A);
        _policyRegistry.grantOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_A
        );
        vm.stopPrank();

        // Sanity: execution works before transfer.
        assertTrue(_policyRegistry.canExecute(_cwAddr, _user, address(_target), 0, _successCallData()));

        // Transfer ownership — epoch advances.
        vm.prank(_company);
        CompanyWallet(payable(_cwAddr)).transferOwnership(_secondOwner);

        // Old delegated admin is rejected.
        vm.prank(_walletAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.PolicyRegistry__Unauthorized.selector, _walletAdmin, _cwAddr));
        _policyRegistry.setUserRoles(_cwAddr, _user, _ROLE_B);

        // Old user roles are gone — canExecute returns false.
        assertFalse(_policyRegistry.canExecute(_cwAddr, _user, address(_target), 0, _successCallData()));
        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), 0);
        assertEq(
            _policyRegistry.getOperationRoles(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector), 0
        );
        assertFalse(_policyRegistry.isWalletPolicyAdmin(_cwAddr, _walletAdmin));
    }

    function test_ownershipEpoch_newOwnerStartsWithCleanSlate() public {
        // Old owner configures policy.
        vm.prank(_company);
        _policyRegistry.grantUserRoles(_cwAddr, _user, _ROLE_A);

        // Transfer — epoch advances.
        vm.prank(_company);
        CompanyWallet(payable(_cwAddr)).transferOwnership(_secondOwner);

        // New owner can write fresh policy at the new epoch.
        vm.startPrank(_secondOwner);
        _policyRegistry.grantUserRoles(_cwAddr, _user, _ROLE_B);
        _policyRegistry.grantOperationRoles(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, _ROLE_B
        );
        vm.stopPrank();

        // Policy written by the new owner is active.
        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), _ROLE_B);
        assertTrue(_policyRegistry.canExecute(_cwAddr, _user, address(_target), 0, _successCallData()));
    }

    function test_ownershipEpoch_secondTransfer_invalidatesFirstOwnerPolicy() public {
        // First transfer: company → secondOwner.
        vm.prank(_company);
        CompanyWallet(payable(_cwAddr)).transferOwnership(_secondOwner);

        // secondOwner configures policy.
        vm.prank(_secondOwner);
        _policyRegistry.grantUserRoles(_cwAddr, _user, _ROLE_A);
        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), _ROLE_A);

        // Second transfer: secondOwner → company.
        address thirdOwner = makeAddr("thirdOwner");
        vm.prank(_secondOwner);
        CompanyWallet(payable(_cwAddr)).transferOwnership(thirdOwner);

        // Policy from the second ownership period is now gone.
        assertEq(_policyRegistry.getUserRoles(_cwAddr, _user), 0);
    }

    function test_ownershipEpoch_operationModule_isInvalidated_afterTransfer() public {
        _allowPolicyModule(address(_allowModule));

        vm.prank(_company);
        _policyRegistry.setOperationModule(
            _cwAddr, address(_target), MockTargetContract.simulateSuccess.selector, address(_allowModule)
        );
        assertEq(
            _policyRegistry.getOperationModule(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            address(_allowModule)
        );

        // Transfer — epoch advances, old module mapping gone.
        vm.prank(_company);
        CompanyWallet(payable(_cwAddr)).transferOwnership(_secondOwner);

        assertEq(
            _policyRegistry.getOperationModule(_cwAddr, address(_target), MockTargetContract.simulateSuccess.selector),
            address(0)
        );
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _grantWalletPolicyAdmin() internal {
        vm.prank(_company);
        _policyRegistry.grantWalletPolicyAdmin(_cwAddr, _walletAdmin);
    }

    function _allowPolicyModule(address module) internal {
        _timelockOp(
            address(_policyRegistry),
            abi.encodeWithSelector(IPolicyRegistry.setPolicyModuleAllowed.selector, module, true)
        );
    }

    function _grantBaseAuthorization(
        address wallet,
        address user,
        uint256 userRoles,
        uint256 operationRoles,
        bytes4 selector
    ) internal {
        vm.startPrank(ICompanyWallet(wallet).owner());
        _policyRegistry.setUserRoles(wallet, user, userRoles);
        _policyRegistry.setOperationRoles(wallet, address(_target), selector, operationRoles);
        vm.stopPrank();
    }

    function _users(address first, address second) internal pure returns (address[] memory users) {
        users = new address[](2);
        users[0] = first;
        users[1] = second;
    }

    function _userRoles(uint256 first, uint256 second) internal pure returns (uint256[] memory roles) {
        roles = new uint256[](2);
        roles[0] = first;
        roles[1] = second;
    }

    function _operationRolesBatch(uint256 firstRoles, uint256 secondRoles)
        internal
        view
        returns (OperationRoles[] memory operations)
    {
        operations = new OperationRoles[](2);
        operations[0] = OperationRoles({
            target: address(_target), selector: MockTargetContract.simulateSuccess.selector, roles: firstRoles
        });
        operations[1] = OperationRoles({
            target: address(_target), selector: MockTargetContract.simulateFailure.selector, roles: secondRoles
        });
    }

    function _operationModuleBatch(address firstModule, address secondModule)
        internal
        view
        returns (OperationModule[] memory operations)
    {
        operations = new OperationModule[](2);
        operations[0] = OperationModule({
            target: address(_target), selector: MockTargetContract.simulateSuccess.selector, module: firstModule
        });
        operations[1] = OperationModule({
            target: address(_target), selector: MockTargetContract.simulateFailure.selector, module: secondModule
        });
    }

    function _successCallData() internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(MockTargetContract.simulateSuccess.selector, true);
    }
}
