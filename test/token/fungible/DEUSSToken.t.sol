// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC6909} from "@openzeppelin/contracts/interfaces/IERC6909.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC6909Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC6909/ERC6909Upgradeable.sol";
import {Initializable} from "solady/src/utils/Initializable.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";
import {console2} from "forge-std/Test.sol";

import {Errors} from "src/libs/Errors.sol";
import {IBaseToken} from "src/token/base/IBaseToken.sol";
import {BaseToken} from "src/token/base/BaseToken.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";
import {DEUSSToken} from "src/token/fungible/DEUSSToken.sol";
import {IEntityRegistry} from "src/registry/interfaces/IEntityRegistry.sol";
import {AccountStatus} from "src/registry/EntityStructs.sol";
import {MockDEUSSToken, MockDEUSSTokenContextHarness} from "test/mocks/MockContracts.sol";

// test files
import {FTFixture} from "test/fixtures/FTFixture.t.sol";

contract DEUSSTokenStorageHarness is DEUSSToken {
    function exposedBaseTokenStorageLocation() external pure returns (bytes32) {
        return _BASE_TOKEN_STORAGE_LOCATION;
    }

    function exposedDeussTokenStorageLocation() external pure returns (bytes32) {
        return _DEUSS_TOKEN_STORAGE_LOCATION;
    }
}

contract DEUSSTokenTest is FTFixture {
    IDEUSSToken public token;

    bytes32 private constant _PAUSABLE_STORAGE_LOCATION =
        0xcd5ed15c6e187e77e9aee88184c21f4f2182ab5827cb3b7e07fbedcd63f03300;
    uint256 private constant _LEGACY_PAUSABLE_SLOT = 106;

    uint256 public initCwBalance;
    address[] private _froms;
    address[] private _tos;
    uint256[] private _amounts;

    function setUp() public override {
        super.setUp();
        console2.log("Proxy DEUSSToken:", _tokenAddr);

        token = IDEUSSToken(_tokenAddr);
        initCwBalance = token.totalSupply(_bondFTId);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC-7201 NAMESPACED STORAGE
    //////////////////////////////////////////////////////////////*/

    function test_namespacedStorageLocations_success_matchErc7201Formula() public {
        DEUSSTokenStorageHarness harness = new DEUSSTokenStorageHarness();
        bytes32 baseLocation = harness.exposedBaseTokenStorageLocation();
        bytes32 deussLocation = harness.exposedDeussTokenStorageLocation();

        assertEq(baseLocation, _erc7201Location("deuss.baseToken.storage"));
        assertEq(deussLocation, _erc7201Location("deuss.deussToken.storage"));
        assertEq(uint256(baseLocation) & 0xff, 0);
        assertEq(uint256(deussLocation) & 0xff, 0);
        assertTrue(baseLocation != deussLocation);
    }

    function test_namespacedState_success_usesErc7201Storage() public view {
        // BaseToken dependencies: bondRegistry (field offset 0), entityRegistry (field offset 1).
        bytes32 baseRoot = _erc7201Location("deuss.baseToken.storage");
        assertEq(_loadAddress(_tokenAddr, baseRoot), address(IBaseToken(_tokenAddr).bondRegistry()));
        assertEq(_loadAddress(_tokenAddr, _slotOffset(baseRoot, 1)), address(IBaseToken(_tokenAddr).entityRegistry()));

        // DEUSSToken `protectedAddress` is field offset 0; entry slot = keccak256(account, deussRoot).
        bytes32 deussRoot = _erc7201Location("deuss.deussToken.storage");
        assertTrue(token.isAddressProtected(_escrowManager));
        bytes32 protectedSlot = keccak256(abi.encode(_escrowManager, deussRoot));
        assertEq(uint256(vm.load(_tokenAddr, protectedSlot)), 1);

        // Isolation: the pre-namespace sequential slot (56) derivation for the same key holds nothing.
        assertEq(vm.load(_tokenAddr, keccak256(abi.encode(_escrowManager, uint256(56)))), bytes32(0));
    }

    /**
     * ==============================================================
     *                      ONLY OWNER FUNCTIONS
     * ==============================================================
     */

    /*//////////////////////////////////////////////////////////////
                                  INIT
    //////////////////////////////////////////////////////////////*/
    function test_init_success() public view {
        assertNotEq(_tokenAddr, address(0));
        assertEq(BaseToken(_tokenAddr).owner(), _timelockController);
        assertEq(token.version(), "1.0.0");
        assertEq(token.totalSupply(_bondFTId), BOND_MAX_SUPPLY);
        assertEq(token.balanceOf(_cwAddr, _bondFTId), initCwBalance);
    }

    function test_init_success_protectsEscrowManager() public view {
        assertTrue(token.isAddressProtected(_escrowManager));
    }

    function test_init_revert_reinitialize() public {
        // ARRANGE
        address bondRegistryAddress = makeAddr("bondRegistry");
        address entityRegistryAddress = makeAddr("entityRegistry");
        address owner = makeAddr("owner");

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        DEUSSToken(_tokenAddr).initialize(owner, bondRegistryAddress, entityRegistryAddress, _escrowManager);
    }

    function test_initialize_reverts_onImplementationDirectly() public {
        address bondRegistryAddress = makeAddr("bondRegistry");
        address entityRegistryAddress = makeAddr("entityRegistry");
        address owner = makeAddr("owner");
        DEUSSToken implementation = new DEUSSToken();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(owner, bondRegistryAddress, entityRegistryAddress, _escrowManager);
    }

    function test_contextInternal_msgData_coverage() public {
        MockDEUSSTokenContextHarness harness = new MockDEUSSTokenContextHarness();
        bytes memory data = harness.exposedMsgData();

        assertEq(data.length, 4);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes4(data), MockDEUSSTokenContextHarness.exposedMsgData.selector);
    }

    function test_contextInternal_contextSuffixLength_coverage() public {
        MockDEUSSTokenContextHarness harness = new MockDEUSSTokenContextHarness();
        assertEq(harness.exposedContextSuffixLength(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                              protectAddress
    //////////////////////////////////////////////////////////////*/
    function test_protectAddress_success() public {
        bytes memory data = abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, _newWallet);
        _timelockSchedule(_tokenAddr, data);

        vm.expectEmit(true, true, false, true);
        emit IDEUSSToken.ProtectedAddressSet(_newWallet, true);
        _timelockExecute(_tokenAddr, data);

        assertTrue(token.isAddressProtected(_newWallet));
    }

    function test_protectAddress_revert_alreadyProtected() public {
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, _newWallet));
        vm.prank(_timelockController);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__AddressAlreadyProtected.selector, _newWallet));
        token.protectAddress(_newWallet);
    }

    function test_protectAddress_revert_unauthorizedCaller() public {
        vm.prank(_notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        token.protectAddress(_newWallet);
    }

    function test_protectAddress_revert_zeroAddress() public {
        bytes memory data = abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, address(0));
        _timelockSchedule(_tokenAddr, data);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _timelockExecute(_tokenAddr, data);
    }

    /*//////////////////////////////////////////////////////////////
                               upgradeTo
    //////////////////////////////////////////////////////////////*/
    function test_upgradeTo_success_beaconOwner() public {
        address newImpl = address(new MockDEUSSToken());

        _timelockOp(address(_tokenBeacon), abi.encodeWithSelector(_tokenBeacon.upgradeTo.selector, newImpl));

        assertEq(MockDEUSSToken(_tokenAddr).VERSION(), 2);
        assertTrue(MockDEUSSToken(_tokenAddr).isNewVersion());
    }

    function test_upgradeTo_reverts_notBeaconOwner() public {
        address newImpl = address(new MockDEUSSToken());

        vm.prank(_notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableUnauthorizedAccount.selector, _notOwner));
        _tokenBeacon.upgradeTo(newImpl);
    }

    function test_beaconDowngrade_success() public {
        address originalImpl = _tokenBeacon.implementation();

        address newImpl = address(new MockDEUSSToken());
        _timelockOp(address(_tokenBeacon), abi.encodeWithSelector(_tokenBeacon.upgradeTo.selector, newImpl));
        assertEq(_tokenBeacon.implementation(), newImpl);

        _timelockOp(address(_tokenBeacon), abi.encodeWithSelector(_tokenBeacon.upgradeTo.selector, originalImpl));
        assertEq(_tokenBeacon.implementation(), originalImpl);
    }

    /*//////////////////////////////////////////////////////////////
                               grantRoles
    //////////////////////////////////////////////////////////////*/
    function test_grantRoles_success_oneRole() public {
        // ARRANGE
        address newUser = makeAddr("newUser");
        uint256 roles = BaseToken(_tokenAddr).BURNER_ROLE();

        assertEq(BaseToken(_tokenAddr).rolesOf(newUser), 0);

        // ACT
        bytes memory data = abi.encodeWithSelector(OwnableRoles.grantRoles.selector, newUser, roles);
        _timelockSchedule(_tokenAddr, data);

        vm.expectEmit(true, true, false, false);
        emit OwnableRoles.RolesUpdated(newUser, roles);
        _timelockExecute(_tokenAddr, data);

        // ASSERT
        assertEq(BaseToken(_tokenAddr).rolesOf(newUser), roles);
    }

    function test_grantRoles_success_multipleRoles() public {
        // ARRANGE
        address newUser = makeAddr("newUser");
        uint256 roles = BaseToken(_tokenAddr).ALL_ROLES();

        assertEq(BaseToken(_tokenAddr).rolesOf(newUser), 0);

        // ACT
        bytes memory data = abi.encodeWithSelector(OwnableRoles.grantRoles.selector, newUser, roles);
        _timelockSchedule(_tokenAddr, data);

        vm.expectEmit(true, true, false, false);
        emit OwnableRoles.RolesUpdated(newUser, roles);
        _timelockExecute(_tokenAddr, data);

        // ASSERT
        assertEq(BaseToken(_tokenAddr).rolesOf(newUser), roles);
    }

    function test_grantRoles_revert_unauthorizedCaller() public {
        // ARRANGE
        address newUser = makeAddr("newUser");
        uint256 roles = (BaseToken(_tokenAddr).BURNER_ROLE());

        // ACT & ASSERT: Expect revert when caller is not owner
        vm.expectRevert(Ownable.Unauthorized.selector);
        BaseToken(_tokenAddr).grantRoles(newUser, roles);
    }

    function test_grantRoles_revert_invalidRoles() public {
        // ARRANGE
        address newUser = makeAddr("newUser");
        uint256 roles = (BaseToken(_tokenAddr).ALL_ROLES()) + 1;

        // ACT & ASSERT: Expect revert when invalid roles are setup
        bytes memory data = abi.encodeWithSelector(OwnableRoles.grantRoles.selector, newUser, roles);
        _timelockSchedule(_tokenAddr, data);
        vm.expectRevert(Errors.InvalidRoles.selector);
        _timelockExecute(_tokenAddr, data);
    }

    function test_grantRoles_revert_paramIsZeroAddress() public {
        // ARRANGE
        uint256 roles = (BaseToken(_tokenAddr).ALL_ROLES());

        // ACT & ASSERT: Expect revert when the user parameter is zero address
        bytes memory data = abi.encodeWithSelector(OwnableRoles.grantRoles.selector, address(0), roles);
        _timelockSchedule(_tokenAddr, data);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _timelockExecute(_tokenAddr, data);
    }

    function test_grantRoles_array_success_oneRole() public {
        // ARRANGE
        address[] memory users = new address[](1);
        users[0] = makeAddr("newUser");
        uint256 roles = BaseToken(_tokenAddr).BURNER_ROLE();

        assertEq(BaseToken(_tokenAddr).rolesOf(users[0]), 0);

        // ACT
        bytes memory data = abi.encodeWithSignature("grantRoles(address[],uint256)", users, roles);
        _timelockSchedule(_tokenAddr, data);

        vm.expectEmit(true, true, false, false);
        emit OwnableRoles.RolesUpdated(users[0], roles);
        _timelockExecute(_tokenAddr, data);

        // ASSERT
        assertEq(BaseToken(_tokenAddr).rolesOf(users[0]), roles);
    }

    function test_grantRoles_array_success_multipleRoles() public {
        // ARRANGE
        address[] memory users = new address[](1);
        users[0] = makeAddr("newUser");
        uint256 roles = BaseToken(_tokenAddr).ALL_ROLES();

        assertEq(BaseToken(_tokenAddr).rolesOf(users[0]), 0);

        // ACT
        bytes memory data = abi.encodeWithSignature("grantRoles(address[],uint256)", users, roles);
        _timelockSchedule(_tokenAddr, data);

        vm.expectEmit(true, true, false, false);
        emit OwnableRoles.RolesUpdated(users[0], roles);
        _timelockExecute(_tokenAddr, data);

        // ASSERT
        assertEq(BaseToken(_tokenAddr).rolesOf(users[0]), roles);
    }

    function test_grantRoles_array_revert_unauthorizedCaller() public {
        // ARRANGE
        address[] memory users = new address[](1);
        users[0] = makeAddr("newUser");
        uint256 roles = (BaseToken(_tokenAddr).BURNER_ROLE());

        // ACT & ASSERT: Expect revert when caller is not owner
        vm.expectRevert(Ownable.Unauthorized.selector);
        BaseToken(_tokenAddr).grantRoles(users, roles);
    }

    function test_grantRoles_array_revert_invalidRoles() public {
        // ARRANGE
        address[] memory users = new address[](1);
        users[0] = makeAddr("newUser");
        uint256 roles = (BaseToken(_tokenAddr).ALL_ROLES()) + 1;

        // ACT & ASSERT: Expect revert when invalid roles are setup
        bytes memory data = abi.encodeWithSignature("grantRoles(address[],uint256)", users, roles);
        _timelockSchedule(_tokenAddr, data);
        vm.expectRevert(Errors.InvalidRoles.selector);
        _timelockExecute(_tokenAddr, data);
    }

    function test_grantRoles_array_revert_paramContainsZeroAddress() public {
        // ARRANGE
        address[] memory users = new address[](1);
        users[0] = address(0);
        uint256 roles = BaseToken(_tokenAddr).ALL_ROLES();

        // ACT & ASSERT: Expect revert when caller is zero address
        bytes memory data = abi.encodeWithSignature("grantRoles(address[],uint256)", users, roles);
        _timelockSchedule(_tokenAddr, data);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _timelockExecute(_tokenAddr, data);
    }

    /*//////////////////////////////////////////////////////////////
                            setBondRegistry
    //////////////////////////////////////////////////////////////*/
    function test_setBondRegistry_revert_alreadySet() public {
        // ARRANGE
        address newBondRegistry = makeAddr("newBondRegistry");

        // ACT & ASSERT: Expect revert when the bond registry is already configured
        bytes memory data = abi.encodeWithSelector(IBaseToken.setBondRegistry.selector, newBondRegistry);
        _timelockSchedule(_tokenAddr, data);
        vm.expectRevert(Errors.BaseToken__BondRegistryAlreadySet.selector);
        _timelockExecute(_tokenAddr, data);
    }

    function test_setBondRegistry_revert_notOwner() public {
        // ARRANGE
        address newBondRegistry = makeAddr("newBondRegistry");

        // ACT & ASSERT: Expect revert when caller is not the owner
        vm.prank(_tokenAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        token.setBondRegistry(newBondRegistry);
    }

    function test_setBondRegistry_revert_zeroAddress() public {
        // ARRANGE
        address zeroAddress = address(0);

        // ACT & ASSERT: Expect revert when the new bond registry is the zero address
        bytes memory data = abi.encodeWithSelector(IBaseToken.setBondRegistry.selector, zeroAddress);
        _timelockSchedule(_tokenAddr, data);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _timelockExecute(_tokenAddr, data);
    }

    /*//////////////////////////////////////////////////////////////
                            setEntityRegistry
    //////////////////////////////////////////////////////////////*/
    function test_setEntityRegistry_revert_alreadySet() public {
        // ARRANGE
        address newEntityRegistry = makeAddr("newEntityRegistry");

        // ACT & ASSERT: Expect revert when the entity registry is already configured
        bytes memory data = abi.encodeWithSelector(IBaseToken.setEntityRegistry.selector, newEntityRegistry);
        _timelockSchedule(_tokenAddr, data);
        vm.expectRevert(Errors.BaseToken__EntityRegistryAlreadySet.selector);
        _timelockExecute(_tokenAddr, data);
    }

    function test_setEntityRegistry_revert_notOwner() public {
        // ARRANGE
        address newEntityRegistry = makeAddr("newEntityRegistry");

        // ACT & ASSERT: Expect revert when caller is not the owner
        vm.prank(_tokenAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        token.setEntityRegistry(newEntityRegistry);
    }

    function test_setEntityRegistry_revert_zeroAddress() public {
        // ARRANGE
        address zeroAddress = address(0);

        // ACT & ASSERT: Expect revert when the new entity registry is the zero address
        bytes memory data = abi.encodeWithSelector(IBaseToken.setEntityRegistry.selector, zeroAddress);
        _timelockSchedule(_tokenAddr, data);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _timelockExecute(_tokenAddr, data);
    }

    /**
     * ==============================================================
     *                      ONLY ROLES FUNCTIONS
     * ==============================================================
     */

    /*//////////////////////////////////////////////////////////////
                                pause
    //////////////////////////////////////////////////////////////*/
    function test_pause_success() public {
        // ARRANGE
        assertEq(token.paused(), false);

        // ACT
        bytes memory data = abi.encodeWithSelector(IBaseToken.pause.selector);
        _timelockSchedule(_tokenAddr, data);

        vm.expectEmit(false, false, false, true);
        emit PausableUpgradeable.Paused(_timelockController);
        _timelockExecute(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ASSERT
        assertEq(token.paused(), true);
    }

    function test_pause_revert_unauthorizedCaller() public {
        // ACT & ASSERT: Expect revert when the caller does not have permission to pause
        vm.prank(_tokenAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        token.pause();
    }

    function test_pause_revert_alreadyPaused() public {
        // ACT
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ASSERT: Expect revert when the token is already paused
        vm.prank(_timelockController);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.pause();
    }

    /*//////////////////////////////////////////////////////////////
                                unpause
    //////////////////////////////////////////////////////////////*/
    function test_unpause_success() public {
        // ARRANGE
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ACT
        bytes memory data = abi.encodeWithSelector(IBaseToken.unpause.selector);
        _timelockSchedule(_tokenAddr, data);

        vm.expectEmit(false, false, false, true);
        emit PausableUpgradeable.Unpaused(_timelockController);
        _timelockExecute(_tokenAddr, data);

        // ASSERT
        assertEq(token.paused(), false);
    }

    function test_unpause_revert_notPaused() public {
        // ACT & ASSERT: Expect revert when the token is not paused
        bytes memory data = abi.encodeWithSelector(IBaseToken.unpause.selector);
        _timelockSchedule(_tokenAddr, data);
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        _timelockExecute(_tokenAddr, data);
    }

    function test_unpause_revert_unauthorizedCaller() public {
        // ARRANGE
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ACT & ASSERT: Expect revert when the caller does not have permission to unpause
        vm.prank(_tokenAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        token.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                paused
    //////////////////////////////////////////////////////////////*/
    function test_paused_success_usesUpgradeableStorageNamespace() public {
        // ARRANGE
        bytes32 legacySlot = bytes32(uint256(_LEGACY_PAUSABLE_SLOT));
        assertEq(token.paused(), false);
        assertEq(vm.load(_tokenAddr, _PAUSABLE_STORAGE_LOCATION), bytes32(0));

        // ACT & ASSERT: old non-upgradeable Pausable slot no longer controls the pause flag.
        vm.store(_tokenAddr, legacySlot, bytes32(uint256(1)));
        assertEq(token.paused(), false);

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        assertEq(token.paused(), true);
        assertEq(vm.load(_tokenAddr, _PAUSABLE_STORAGE_LOCATION), bytes32(uint256(1)));

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.unpause.selector));

        assertEq(token.paused(), false);
        assertEq(vm.load(_tokenAddr, _PAUSABLE_STORAGE_LOCATION), bytes32(0));
        assertEq(vm.load(_tokenAddr, legacySlot), bytes32(uint256(1)));
    }

    /*//////////////////////////////////////////////////////////////
                            pauseTokenId
    //////////////////////////////////////////////////////////////*/
    function test_pauseTokenId_success() public {
        // ARRANGE
        assertEq(token.isTokenPaused(_bondFTId), false);

        // ACT
        vm.prank(_brAddr);
        vm.expectEmit(true, true, false, false);
        emit IBaseToken.TokenPaused(_bondFTId, _brAddr);
        token.pauseTokenId(_bondFTId);

        // ASSERT
        assertEq(token.isTokenPaused(_bondFTId), true);
    }

    function test_pauseTokenId_revert_notBondRegistry() public {
        // ACT & ASSERT: Expect revert when caller is not the bond registry
        vm.prank(_notOwner);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__CallerNotBondRegistry.selector, _notOwner));
        token.pauseTokenId(_bondFTId);
    }

    function test_pauseTokenId_revert_alreadyPaused() public {
        // ARRANGE
        vm.prank(_brAddr);
        token.pauseTokenId(_bondFTId);

        // ACT & ASSERT: Expect revert when tokenId is already paused
        vm.prank(_brAddr);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__TokenIdAlreadyPaused.selector, _bondFTId));
        token.pauseTokenId(_bondFTId);
    }

    function test_pauseTokenId_success_contractPaused() public {
        // ARRANGE
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ACT: Token-id suspension remains available while the contract is globally paused.
        vm.prank(_brAddr);
        vm.expectEmit(true, true, false, false);
        emit IBaseToken.TokenPaused(_bondFTId, _brAddr);
        token.pauseTokenId(_bondFTId);

        // ASSERT
        assertEq(token.paused(), true);
        assertEq(token.isTokenPaused(_bondFTId), true);
    }

    /*//////////////////////////////////////////////////////////////
                           unpauseTokenId
    //////////////////////////////////////////////////////////////*/
    function test_unpauseTokenId_success() public {
        // ARRANGE
        vm.prank(_brAddr);
        token.pauseTokenId(_bondFTId);
        assertEq(token.isTokenPaused(_bondFTId), true);

        // ACT
        vm.prank(_brAddr);
        vm.expectEmit(true, true, false, false);
        emit IBaseToken.TokenUnpaused(_bondFTId, _brAddr);
        token.unpauseTokenId(_bondFTId);

        // ASSERT
        assertEq(token.isTokenPaused(_bondFTId), false);
    }

    function test_unpauseTokenId_revert_notBondRegistry() public {
        // ARRANGE
        vm.prank(_brAddr);
        token.pauseTokenId(_bondFTId);

        // ACT & ASSERT: Expect revert when caller is not the bond registry
        vm.prank(_notOwner);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__CallerNotBondRegistry.selector, _notOwner));
        token.unpauseTokenId(_bondFTId);
    }

    function test_unpauseTokenId_revert_notPaused() public {
        // ACT & ASSERT: Expect revert when tokenId is not paused
        vm.prank(_brAddr);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__TokenIdNotPaused.selector, _bondFTId));
        token.unpauseTokenId(_bondFTId);
    }

    function test_unpauseTokenId_revert_contractPaused() public {
        // ARRANGE
        vm.prank(_brAddr);
        token.pauseTokenId(_bondFTId);

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ACT & ASSERT: Expect revert when contract is paused
        vm.prank(_brAddr);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.unpauseTokenId(_bondFTId);
    }

    /*//////////////////////////////////////////////////////////////
                          freezePartialTokens
    //////////////////////////////////////////////////////////////*/
    function test_freezePartialTokens_success() public {
        // ARRANGE
        uint256 frozenAmount = initCwBalance / 2;

        // ACT
        vm.prank(_tokenAdmin);
        vm.expectEmit(true, true, true, false);
        emit IDEUSSToken.TokensFrozen(_cwAddr, _bondFTId, frozenAmount);
        token.freezePartialTokens(_cwAddr, _bondFTId, frozenAmount);

        // ASSERT
        assertEq(token.frozenBalanceOf(_cwAddr, _bondFTId), frozenAmount);
    }

    function test_freezePartialTokens_success_tokenIdPaused() public {
        // ARRANGE
        uint256 frozenAmount = initCwBalance / 2;
        vm.prank(_brAddr);
        token.pauseTokenId(_bondFTId);

        // ACT
        vm.prank(_tokenAdmin);
        vm.expectEmit(true, true, true, false);
        emit IDEUSSToken.TokensFrozen(_cwAddr, _bondFTId, frozenAmount);
        token.freezePartialTokens(_cwAddr, _bondFTId, frozenAmount);

        // ASSERT
        assertEq(token.frozenBalanceOf(_cwAddr, _bondFTId), frozenAmount);
    }

    function test_freezePartialTokens_revert_unauthorizedCaller() public {
        // ARRANGE
        uint256 frozenAmount = initCwBalance / 2;

        _timelockOp(
            _tokenAddr,
            abi.encodeWithSelector(
                OwnableRoles.revokeRoles.selector, _tokenAdmin, BaseToken(_tokenAddr).TOKEN_FREEZER_ROLE()
            )
        );

        // ACT & ASSERT: Expect revert when the caller does not have permission to freeze tokens
        vm.prank(_tokenAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        token.freezePartialTokens(_cwAddr, _bondFTId, frozenAmount);
    }

    function test_freezePartialTokens_success_callerNotEnabled() public {
        // ARRANGE
        uint256 frozenAmount = initCwBalance / 2;

        vm.prank(_erAdmin);
        _er.setAccountStatus(_tokenAdmin, AccountStatus.DISABLED, "");

        // ACT
        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_cwAddr, _bondFTId, frozenAmount);

        // ASSERT: Freezer authority is RBAC-only; caller registry status is not required.
        assertEq(token.frozenBalanceOf(_cwAddr, _bondFTId), frozenAmount);
    }

    function test_freezePartialTokens_revert_protectedAddress() public {
        // ARRANGE
        uint256 frozenAmount = initCwBalance / 2;
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, _cwAddr));

        // ACT & ASSERT: Protected custody balances cannot be frozen.
        vm.prank(_tokenAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__AddressProtected.selector, _cwAddr));
        token.freezePartialTokens(_cwAddr, _bondFTId, frozenAmount);
    }

    function test_freezePartialTokens_revert_zeroAmount() public {
        // ACT & ASSERT: Expect revert when the amount is zero
        vm.prank(_tokenAdmin);
        vm.expectRevert(Errors.Token__ZeroAmount.selector);
        token.freezePartialTokens(_cwAddr, _bondFTId, 0);
    }

    function test_freezePartialTokens_revert_zeroWallet() public {
        // ACT & ASSERT: Expect revert when the wallet has no balance
        vm.prank(_tokenAdmin);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.freezePartialTokens(address(0), _bondFTId, initCwBalance);
    }

    function test_freezePartialTokens_revert_insufficientBalance() public {
        // ARRANGE
        uint256 amountExceedingBalance = 2 * initCwBalance;

        // ACT & ASSERT: Expect revert when the balance is insufficient
        vm.prank(_tokenAdmin);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.freezePartialTokens(_cwAddr, _bondFTId, amountExceedingBalance);
    }

    function test_freezePartialTokens_revert_paused() public {
        // ARRANGE
        uint256 frozenAmount = initCwBalance / 2;

        // Set pause
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ACT & ASSERT: Expect revert when the contract is paused
        vm.prank(_tokenAdmin);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.freezePartialTokens(_cwAddr, _bondFTId, frozenAmount);
    }

    /*//////////////////////////////////////////////////////////////
                         unfreezePartialTokens
    //////////////////////////////////////////////////////////////*/
    function test_unfreezePartialTokens_success() public {
        // ARRANGE
        uint256 unfreezeAmount = initCwBalance / 2;

        // Freeze tokens
        vm.startPrank(_tokenAdmin);
        token.freezePartialTokens(_cwAddr, _bondFTId, unfreezeAmount);

        // ACT
        vm.expectEmit(true, true, true, false);
        emit IDEUSSToken.TokensUnfrozen(_cwAddr, _bondFTId, unfreezeAmount);
        token.unfreezePartialTokens(_cwAddr, _bondFTId, unfreezeAmount);
        vm.stopPrank();

        // ASSERT
        assertEq(token.frozenBalanceOf(_cwAddr, _bondFTId), 0);
    }

    function test_unfreezePartialTokens_success_tokenIdPaused() public {
        // ARRANGE
        uint256 unfreezeAmount = initCwBalance / 2;

        // Freeze tokens
        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_cwAddr, _bondFTId, unfreezeAmount);
        vm.prank(_brAddr);
        token.pauseTokenId(_bondFTId);

        // ACT
        vm.expectEmit(true, true, true, false);
        emit IDEUSSToken.TokensUnfrozen(_cwAddr, _bondFTId, unfreezeAmount);
        vm.prank(_tokenAdmin);
        token.unfreezePartialTokens(_cwAddr, _bondFTId, unfreezeAmount);

        // ASSERT
        assertEq(token.frozenBalanceOf(_cwAddr, _bondFTId), 0);
    }

    function test_unfreezePartialTokens_revert_unauthorizedCaller() public {
        // ARRANGE
        uint256 unfreezeAmount = initCwBalance / 2;

        // Set restrictions
        _timelockOp(
            _tokenAddr,
            abi.encodeWithSelector(
                OwnableRoles.revokeRoles.selector, _tokenAdmin, BaseToken(_tokenAddr).TOKEN_FREEZER_ROLE()
            )
        );

        // ACT & ASSERT: Expect revert when the caller does not have permission to unfreeze tokens
        vm.prank(_tokenAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        token.unfreezePartialTokens(_cwAddr, _bondFTId, unfreezeAmount);
    }

    function test_unfreezePartialTokens_success_callerNotEnabled() public {
        // ARRANGE
        uint256 unfreezeAmount = initCwBalance / 2;

        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_cwAddr, _bondFTId, unfreezeAmount);

        vm.prank(_erAdmin);
        _er.setAccountStatus(_tokenAdmin, AccountStatus.DISABLED, "");

        // ACT
        vm.prank(_tokenAdmin);
        token.unfreezePartialTokens(_cwAddr, _bondFTId, unfreezeAmount);

        // ASSERT: Freezer authority is RBAC-only; caller registry status is not required.
        assertEq(token.frozenBalanceOf(_cwAddr, _bondFTId), 0);
    }

    function test_unfreezePartialTokens_revert_zeroAmount() public {
        // ACT & ASSERT: Expect revert when the amount is zero
        vm.prank(_tokenAdmin);
        vm.expectRevert(Errors.Token__ZeroAmount.selector);
        token.unfreezePartialTokens(_cwAddr, _bondFTId, 0);
    }

    function test_unfreezePartialTokens_revert_zeroWallet() public {
        // ACT & ASSERT: Expect revert when the wallet has no frozen tokens
        vm.prank(_tokenAdmin);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.unfreezePartialTokens(address(0), _bondFTId, initCwBalance);
    }

    function test_unfreezePartialTokens_revert_insufficientFrozenTokens() public {
        // ARRANGE
        uint256 frozenAmount = initCwBalance / 2;
        uint256 excessiveUnfreezeAmount = 2 * frozenAmount;

        // Freeze tokens
        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_cwAddr, _bondFTId, frozenAmount);

        // ACT & ASSERT: Expect revert when attempting to unfreeze more tokens than are frozen
        vm.prank(_tokenAdmin);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.unfreezePartialTokens(_cwAddr, _bondFTId, excessiveUnfreezeAmount);
    }

    function test_unfreezePartialTokens_revert_paused() public {
        // ARRANGE
        uint256 unfreezeAmount = initCwBalance / 2;

        // Set pause
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ACT & ASSERT: Expect revert when the contract is paused
        vm.prank(_tokenAdmin);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.unfreezePartialTokens(_cwAddr, _bondFTId, unfreezeAmount);
    }

    /*//////////////////////////////////////////////////////////////
                             forcedTransfer
    //////////////////////////////////////////////////////////////*/
    function test_forcedTransfer_success_unfrozenTokens() public {
        // ARRANGE
        uint256 forcedTransferAmount = initCwBalance / 2;

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        // ACT
        vm.prank(_tokenAdmin);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Transfer(_tokenAdmin, _cwAddr, _tokenRecipient3, _bondFTId, forcedTransferAmount);
        token.forcedTransfer(_cwAddr, _tokenRecipient3, _bondFTId, forcedTransferAmount);

        // ASSERT
        assertEq(token.totalSupply(_bondFTId), initCwBalance);
        assertEq(token.balanceOf(_cwAddr, _bondFTId), (initCwBalance - forcedTransferAmount));
        assertEq(token.balanceOf(_tokenRecipient3, _bondFTId), forcedTransferAmount);
    }

    function test_forcedTransfer_success_frozenTokens() public {
        // Freeze
        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_cwAddr, _bondFTId, initCwBalance);

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        // ACT
        vm.prank(_tokenAdmin);
        vm.expectEmit(true, true, true, false);
        emit IDEUSSToken.TokensUnfrozen(_cwAddr, _bondFTId, initCwBalance);
        token.forcedTransfer(_cwAddr, _tokenRecipient3, _bondFTId, initCwBalance);

        // ASSERT
        assertEq(token.totalSupply(_bondFTId), initCwBalance);
        assertEq(token.balanceOf(_cwAddr, _bondFTId), 0);
        assertEq(token.balanceOf(_tokenRecipient3, _bondFTId), initCwBalance);
    }

    function test_forcedTransfer_success_tokenIdIsPaused() public {
        // ARRANGE
        uint256 forcedTransferAmount = initCwBalance / 2;
        vm.prank(_brAddr);
        token.pauseTokenId(_bondFTId);

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        // ACT
        vm.prank(_tokenAdmin);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Transfer(_tokenAdmin, _cwAddr, _tokenRecipient3, _bondFTId, forcedTransferAmount);
        token.forcedTransfer(_cwAddr, _tokenRecipient3, _bondFTId, forcedTransferAmount);

        // ASSERT
        assertEq(token.totalSupply(_bondFTId), initCwBalance);
        assertEq(token.balanceOf(_cwAddr, _bondFTId), (initCwBalance - forcedTransferAmount));
        assertEq(token.balanceOf(_tokenRecipient3, _bondFTId), forcedTransferAmount);
    }

    function test_forcedTransfer_revert_unauthorizedCaller() public {
        // ARRANGE
        uint256 forcedTransferAmount = initCwBalance / 2;

        // Set restrictions
        _timelockOp(
            _tokenAddr,
            abi.encodeWithSelector(
                OwnableRoles.revokeRoles.selector, _tokenAdmin, BaseToken(_tokenAddr).FORCE_TRANSFER_ROLE()
            )
        );

        // ACT & ASSERT: Expect revert when the caller does not have permission to force transfer tokens
        vm.prank(_tokenAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        token.forcedTransfer(_cwAddr, _tokenRecipient3, _bondFTId, forcedTransferAmount);
    }

    function test_forcedTransfer_revert_zeroAmount() public {
        // ACT & ASSERT: Expect revert when the amount is zero
        vm.prank(_tokenAdmin);
        vm.expectRevert(Errors.Token__ZeroAmount.selector);
        token.forcedTransfer(_cwAddr, _tokenRecipient3, _bondFTId, 0);
    }

    function test_forcedTransfer_revert_insufficientBalance() public {
        // ARRANGE
        uint256 forcedTransferAmount = 2 * initCwBalance;

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        // ACT & ASSERT: Expect revert when the sender's balance is insufficient
        vm.prank(_tokenAdmin);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.forcedTransfer(_cwAddr, _tokenRecipient3, _bondFTId, forcedTransferAmount);
    }

    function test_forcedTransfer_revert_paused() public {
        // ARRANGE
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        // ACT & ASSERT: Expect revert when the contract is paused
        vm.prank(_tokenAdmin);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.forcedTransfer(_cwAddr, _tokenRecipient3, _bondFTId, initCwBalance);
    }

    function test_forcedTransfer_revert_toZeroAddress() public {
        vm.mockCall(
            _erAddr, abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, address(0)), abi.encode(true)
        );

        // ACT & ASSERT: Expect revert when the receiver is zero address
        vm.prank(_tokenAdmin);
        vm.expectRevert(abi.encodeWithSelector(ERC6909Upgradeable.ERC6909InvalidReceiver.selector, address(0)));
        token.forcedTransfer(_cwAddr, address(0), _bondFTId, initCwBalance);
    }

    function test_forcedTransfer_revert_fromZeroAddress() public {
        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        // ACT & ASSERT: Expect revert when the sender is zero address
        vm.prank(_tokenAdmin);
        vm.expectRevert(abi.encodeWithSelector(ERC6909Upgradeable.ERC6909InvalidSender.selector, address(0)));
        token.forcedTransfer(address(0), _tokenRecipient3, _bondFTId, initCwBalance);
    }

    function test_forcedTransfer_revert_transferNotAllowed() public {
        // ARRANGE
        uint256 forcedTransferAmount = initCwBalance / 2;

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(false)
        );

        // ACT & ASSET: Expect revert when transfer is not allowed for `to`
        vm.prank(_tokenAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Token__TransferNotAllowed.selector, _cwAddr, _tokenRecipient3, _bondFTId)
        );
        token.forcedTransfer(_cwAddr, _tokenRecipient3, _bondFTId, forcedTransferAmount);
    }

    function test_forcedTransfer_revert_callerNotEnabled() public {
        // ARRANGE: create a caller with FORCE_TRANSFER_ROLE but no registered wallet
        address disabledCaller = _createAddress("disabledCaller");
        _grantRoles(_tokenAddr, disabledCaller, BaseToken(_tokenAddr).FORCE_TRANSFER_ROLE());

        // ACT & ASSERT: Expect revert when caller wallet is not enabled
        vm.prank(disabledCaller);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__CallerNotEnabled.selector, disabledCaller));
        token.forcedTransfer(_cwAddr, _tokenRecipient3, _bondFTId, initCwBalance / 2);
    }

    function test_forcedTransfer_success_fromNotEnabled() public {
        // ARRANGE: disable a holder after it receives tokens, then recover the balance
        uint256 forcedTransferAmount = initCwBalance / 4;

        vm.prank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, forcedTransferAmount);

        vm.prank(_erAdmin);
        _er.setAccountStatus(_tokenRecipient1, AccountStatus.DISABLED, "");

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        uint256 recipientBalanceBefore = token.balanceOf(_tokenRecipient3, _bondFTId);

        // ACT & ASSERT: Disabled source wallets can be recovered by an enabled force-transfer caller
        vm.prank(_tokenAdmin);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Transfer(_tokenAdmin, _tokenRecipient1, _tokenRecipient3, _bondFTId, forcedTransferAmount);
        token.forcedTransfer(_tokenRecipient1, _tokenRecipient3, _bondFTId, forcedTransferAmount);

        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), 0);
        assertEq(token.balanceOf(_tokenRecipient3, _bondFTId), recipientBalanceBefore + forcedTransferAmount);
    }

    function test_forcedTransfer_revert_fromProtected() public {
        uint256 forcedTransferAmount = initCwBalance / 2;

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, _cwAddr));

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        vm.prank(_tokenAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__AddressProtected.selector, _cwAddr));
        token.forcedTransfer(_cwAddr, _tokenRecipient3, _bondFTId, forcedTransferAmount);
    }

    function test_forcedTransfer_revert_toProtected() public {
        uint256 forcedTransferAmount = initCwBalance / 2;

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, _tokenRecipient3));

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        vm.prank(_tokenAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Token__ProtectedReceiverTransferNotAllowed.selector,
                _cwAddr,
                _tokenRecipient3,
                _tokenAdmin,
                _bondFTId
            )
        );
        token.forcedTransfer(_cwAddr, _tokenRecipient3, _bondFTId, forcedTransferAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                approve
    //////////////////////////////////////////////////////////////*/
    function test_approve_success_fromZeroToNonZero() public {
        // ARRANGE
        address spender = makeAddr("spender");
        _registerWallet(spender);

        // ACT & ASSERT
        vm.prank(_cwAddr);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Approval(_cwAddr, spender, _bondFTId, initCwBalance);
        assertTrue(token.approve(spender, _bondFTId, initCwBalance));
        assertEq(token.allowance(_cwAddr, spender, _bondFTId), initCwBalance);
    }

    function test_approve_success_fromNonZeroToZero() public {
        // ARRANGE
        address spender = makeAddr("spender");
        _registerWallet(spender);

        vm.startPrank(_cwAddr);
        assertTrue(token.approve(spender, _bondFTId, initCwBalance));

        // ACT
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Approval(_cwAddr, spender, _bondFTId, 0);
        assertTrue(token.approve(spender, _bondFTId, 0));
        assertEq(token.allowance(_cwAddr, spender, _bondFTId), 0);
        vm.stopPrank();
    }

    function test_approve_success_selfAsSpender() public {
        // ACT & ASSERT
        vm.prank(_cwAddr);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Approval(_cwAddr, _cwAddr, _bondFTId, initCwBalance);
        assertTrue(token.approve(_cwAddr, _bondFTId, initCwBalance));
        assertEq(token.allowance(_cwAddr, _cwAddr, _bondFTId), initCwBalance);
    }

    function test_approve_revert_tokenPaused() public {
        // ARRANGE
        address spender = makeAddr("spender");
        _registerWallet(spender);

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ACT & ASSERT: Expect revert when contract is paused
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.approve(spender, _bondFTId, initCwBalance);
    }

    function test_approve_revert_zeroSpender() public {
        // ACT & ASSERT: Expect revert when spender is zero
        vm.prank(_cwAddr);
        vm.expectRevert(abi.encodeWithSelector(ERC6909Upgradeable.ERC6909InvalidSpender.selector, address(0)));
        token.approve(address(0), _bondFTId, initCwBalance);
    }

    function test_approve_revert_transferNoAllowed() public {
        // ARRANGE
        address spender = makeAddr("spender");

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.canApprove.selector, _cwAddr, spender, _bondFTId, initCwBalance),
            abi.encode(false)
        );

        // ACT & ASSERT: Expect revert when transfer is not allowed
        vm.prank(_cwAddr);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Token__ApprovalNotAllowed.selector, _cwAddr, spender, _bondFTId, initCwBalance
            )
        );
        token.approve(spender, _bondFTId, initCwBalance);
    }

    function test_approve_success_nonZeroToNonZeroOverwrite() public {
        // ARRANGE: set an initial non-zero allowance
        address spender = makeAddr("spender");
        _registerWallet(spender);

        vm.startPrank(_cwAddr);
        token.approve(spender, _bondFTId, initCwBalance);

        // ACT & ASSERT: ERC-6909 approve overwrites the existing allowance.
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Approval(_cwAddr, spender, _bondFTId, initCwBalance / 2);
        assertTrue(token.approve(spender, _bondFTId, initCwBalance / 2));
        assertEq(token.allowance(_cwAddr, spender, _bondFTId), initCwBalance / 2);
        vm.stopPrank();
    }

    function test_approve_success_nonZeroToEnabledSpender() public {
        // ARRANGE
        address spender = makeAddr("spender");
        _registerWallet(spender);

        // ACT & ASSERT: nonzero approval to an enabled spender succeeds
        vm.prank(_cwAddr);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Approval(_cwAddr, spender, _bondFTId, initCwBalance);
        assertTrue(token.approve(spender, _bondFTId, initCwBalance));
        assertEq(token.allowance(_cwAddr, spender, _bondFTId), initCwBalance);
    }

    function test_approve_success_zeroWhenSpenderDisabled() public {
        // ARRANGE: grant allowance then disable the spender
        address spender = makeAddr("spender");
        _registerWallet(spender);

        vm.prank(_cwAddr);
        token.approve(spender, _bondFTId, initCwBalance);

        vm.prank(_erAdmin);
        _er.setAccountStatus(spender, AccountStatus.DISABLED, "");

        // ACT & ASSERT: revocation (amount == 0) succeeds even though spender is disabled
        vm.prank(_cwAddr);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Approval(_cwAddr, spender, _bondFTId, 0);
        assertTrue(token.approve(spender, _bondFTId, 0));
        assertEq(token.allowance(_cwAddr, spender, _bondFTId), 0);
    }

    function test_approve_revert_nonZeroToDisabledSpender() public {
        // ARRANGE: register then disable the spender
        address spender = makeAddr("spender");
        _registerWallet(spender);

        vm.prank(_erAdmin);
        _er.setAccountStatus(spender, AccountStatus.DISABLED, "");

        // ACT & ASSERT: nonzero approval to a disabled spender reverts
        vm.prank(_cwAddr);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Token__ApprovalNotAllowed.selector, _cwAddr, spender, _bondFTId, initCwBalance
            )
        );
        token.approve(spender, _bondFTId, initCwBalance);
    }

    /*//////////////////////////////////////////////////////////////
                              setOperator
    //////////////////////////////////////////////////////////////*/
    function test_setOperator_success() public {
        // ARRANGE
        address operator = makeAddr("operator");
        _createAndRegisterEntityWallet(_erAdmin, operator);

        // ACT & ASSERT
        vm.prank(_cwAddr);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.OperatorSet(_cwAddr, operator, true);
        bool success = token.setOperator(operator, true);
        assertTrue(success);
        assertTrue(token.isOperator(_cwAddr, operator));
    }

    function test_setOperator_success_revoke() public {
        // ARRANGE
        address operator = makeAddr("operator");
        _createAndRegisterEntityWallet(_erAdmin, operator);

        vm.startPrank(_cwAddr);
        token.setOperator(operator, true);

        // ACT & ASSERT
        vm.expectEmit(true, true, true, true);
        emit IERC6909.OperatorSet(_cwAddr, operator, false);
        token.setOperator(operator, false);
        assertFalse(token.isOperator(_cwAddr, operator));
        vm.stopPrank();
    }

    function test_setOperator_revert_operatorNotEnabled() public {
        // ARRANGE: Unregistered wallet (not enabled in ER)
        address operator = makeAddr("operator");

        // ACT & ASSERT
        vm.prank(_cwAddr);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__OperatorNotEnabled.selector, operator));
        token.setOperator(operator, true);
    }

    function test_setOperator_revert_ownerNotEnabled() public {
        // ARRANGE: Register an enabled operator, then disable the owner account
        address operator = makeAddr("operator");
        _createAndRegisterEntityWallet(_erAdmin, operator);

        vm.prank(_erAdmin);
        _er.setAccountStatus(_cwAddr, AccountStatus.DISABLED, "");

        // ACT & ASSERT: disabled owners cannot stage new durable operator approvals
        vm.prank(_cwAddr);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__OperatorNotEnabled.selector, operator));
        token.setOperator(operator, true);
        assertFalse(token.isOperator(_cwAddr, operator));
    }

    function test_setOperator_success_revoke_whenOperatorDisabled() public {
        // ARRANGE: Register operator, approve it, then disable it in ER
        address operator = makeAddr("operator");
        _createAndRegisterEntityWallet(_erAdmin, operator);

        vm.prank(_cwAddr);
        token.setOperator(operator, true);
        assertTrue(token.isOperator(_cwAddr, operator));

        vm.prank(_erAdmin);
        _er.setAccountStatus(operator, AccountStatus.DISABLED, "");

        // ACT & ASSERT: Revocation should still be possible
        vm.prank(_cwAddr);
        bool success = token.setOperator(operator, false);
        assertTrue(success);
        assertFalse(token.isOperator(_cwAddr, operator));
    }

    function test_setOperator_success_revoke_whenOwnerDisabled() public {
        // ARRANGE: Register and approve operator, then disable the owner account
        address operator = makeAddr("operator");
        _createAndRegisterEntityWallet(_erAdmin, operator);

        vm.prank(_cwAddr);
        token.setOperator(operator, true);
        assertTrue(token.isOperator(_cwAddr, operator));

        vm.prank(_erAdmin);
        _er.setAccountStatus(_cwAddr, AccountStatus.DISABLED, "");

        // ACT & ASSERT: revocation should still be possible
        vm.prank(_cwAddr);
        bool success = token.setOperator(operator, false);
        assertTrue(success);
        assertFalse(token.isOperator(_cwAddr, operator));
    }

    function test_setOperator_revert_paused() public {
        // ARRANGE
        address operator = makeAddr("operator");
        _createAndRegisterEntityWallet(_erAdmin, operator);

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ACT & ASSERT: Expect revert when contract is paused
        vm.prank(_cwAddr);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.setOperator(operator, true);
    }

    /*//////////////////////////////////////////////////////////////
                                  mint
    //////////////////////////////////////////////////////////////*/
    function test_mint_success() public {
        // ACT
        vm.prank(_brAddr);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Transfer(_brAddr, address(0), _cwAddr, _bondFTId, initCwBalance);
        token.mint(_cwAddr, _bondFTId, initCwBalance);

        // ASSERT
        assertEq(token.totalSupply(_bondFTId), 2 * initCwBalance);
        assertEq(token.balanceOf(_cwAddr, _bondFTId), 2 * initCwBalance);
    }

    function test_mint_revert_unauthorizedCaller() public {
        // ACT & ASSERT: Expect revert when the caller does not have permission to mint tokens
        vm.prank(_notOwner);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__CallerNotBondRegistry.selector, _notOwner));
        token.mint(_cwAddr, _bondFTId, initCwBalance);
    }

    function test_mint_revert_zeroAmount() public {
        // ACT & ASSERT: Expect revert when the mint amount is zero
        vm.prank(_brAddr);
        vm.expectRevert(Errors.Token__ZeroAmount.selector);
        token.mint(_cwAddr, _bondFTId, 0);
    }

    function test_mint_revert_paused() public {
        // ARRANGE
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ACT & ASSERT: Expect revert when minting while the contract is paused
        vm.prank(_brAddr);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.mint(_cwAddr, _bondFTId, initCwBalance);
    }

    function test_mint_revert_toZeroAddress() public {
        // ACT & ASSERT: Expect revert when `to` is zero address
        vm.prank(_brAddr);
        vm.expectRevert(abi.encodeWithSelector(ERC6909Upgradeable.ERC6909InvalidReceiver.selector, address(0)));
        token.mint(address(0), _bondFTId, initCwBalance);
    }

    function test_mint_revert_toNotEnabled() public {
        // ARRANGE: create an address that is NOT wallet-enabled
        address notEnabledTo = _createAddress("notEnabledTo");

        // ACT & ASSERT: Expect revert when `to` wallet is not enabled
        vm.prank(_brAddr);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Token__TransferNotAllowed.selector, address(0), notEnabledTo, _bondFTId)
        );
        token.mint(notEnabledTo, _bondFTId, initCwBalance);
    }

    function test_mint_success_toProtectedAddress() public {
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, _cwAddr));

        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, initCwBalance);

        assertEq(token.totalSupply(_bondFTId), 2 * initCwBalance);
        assertEq(token.balanceOf(_cwAddr, _bondFTId), 2 * initCwBalance);
    }

    /*//////////////////////////////////////////////////////////////
                                  burn
    //////////////////////////////////////////////////////////////*/
    function test_burn_success_bondRegistryCaller() public {
        // ARRANGE
        uint256 burntAmount = initCwBalance / 2;
        uint256 balanceAfter = initCwBalance - burntAmount;

        // ACT
        vm.prank(_brAddr);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Transfer(_brAddr, _cwAddr, address(0), _bondFTId, burntAmount);
        token.burn(_cwAddr, _bondFTId, burntAmount);

        // ASSERT
        assertEq(token.totalSupply(_bondFTId), balanceAfter);
        assertEq(token.balanceOf(_cwAddr, _bondFTId), balanceAfter);
    }

    function test_burn_success_frozenTokens() public {
        // ARRANGE
        uint256 burntAmount = initCwBalance / 2;
        uint256 balanceAfter = initCwBalance - burntAmount;

        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_cwAddr, _bondFTId, initCwBalance);

        // ACT
        vm.prank(_brAddr);
        vm.expectEmit(true, true, true, false);
        emit IDEUSSToken.TokensUnfrozen(_cwAddr, _bondFTId, burntAmount);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Transfer(_brAddr, _cwAddr, address(0), _bondFTId, burntAmount);
        token.burn(_cwAddr, _bondFTId, burntAmount);

        // ASSERT
        assertEq(token.totalSupply(_bondFTId), balanceAfter);
        assertEq(token.balanceOf(_cwAddr, _bondFTId), balanceAfter);
    }

    function test_burn_reverts_callerNotBondRegistry() public {
        vm.prank(_tokenAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__CallerNotBondRegistry.selector, _tokenAdmin));
        token.burn(_cwAddr, _bondFTId, initCwBalance / 2);
    }

    function test_burn_success_fromNotEnabled() public {
        // ARRANGE: disable a holder after it receives tokens, then burn from it through BondRegistry
        uint256 burnAmount = initCwBalance / 4;

        vm.prank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, burnAmount);

        vm.prank(_erAdmin);
        _er.setAccountStatus(_tokenRecipient1, AccountStatus.DISABLED, "");

        uint256 totalSupplyBefore = token.totalSupply(_bondFTId);

        // ACT & ASSERT: Disabled source wallets can be burned by BondRegistry
        vm.prank(_brAddr);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Transfer(_brAddr, _tokenRecipient1, address(0), _bondFTId, burnAmount);
        token.burn(_tokenRecipient1, _bondFTId, burnAmount);

        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), 0);
        assertEq(token.totalSupply(_bondFTId), totalSupplyBefore - burnAmount);
    }

    function test_burn_reverts_zeroAmount() public {
        // ACT & ASSERT: Expect revert when burn amount is zero
        vm.prank(_brAddr);
        vm.expectRevert(Errors.Token__ZeroAmount.selector);
        token.burn(_cwAddr, _bondFTId, 0);
    }

    function test_burn_reverts_insufficientBalance() public {
        // ACT & ASSERT: Expect revert when trying to burn more than the available balance
        vm.prank(_brAddr);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.burn(_cwAddr, _bondFTId, initCwBalance + 1);
    }

    function test_burn_reverts_fromZeroAddress() public {
        // ACT & ASSERT: Expect revert when 'from' is zero address and amount is zero
        vm.prank(_brAddr);
        vm.expectRevert(abi.encodeWithSelector(ERC6909Upgradeable.ERC6909InvalidSender.selector, address(0)));
        token.burn(address(0), _bondFTId, initCwBalance);
    }

    function test_burn_reverts_paused() public {
        // ARRANGE
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ACT & ASSERT: Expect revert when contract is paused
        vm.prank(_brAddr);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.burn(_cwAddr, _bondFTId, initCwBalance);
    }

    function test_burn_reverts_fromProtected() public {
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, _cwAddr));

        vm.prank(_brAddr);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__AddressProtected.selector, _cwAddr));
        token.burn(_cwAddr, _bondFTId, initCwBalance / 2);
    }

    /*//////////////////////////////////////////////////////////////
                          batchForcedTransfer
    //////////////////////////////////////////////////////////////*/
    function test_batchForcedTransfer_success() public {
        // ARRANGE
        uint256 mintAmount = 2 * initCwBalance;
        uint256 transferAmount = mintAmount / 2;
        uint256 forcedTransferAmount = transferAmount / 2;

        // Mint tokens for two recipients
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, mintAmount);
        vm.startPrank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient2, _bondFTId, transferAmount);
        vm.stopPrank();

        // Prepare data for batch transfer
        _froms.push(_tokenRecipient1);
        _froms.push(_tokenRecipient2);

        _tos.push(_tokenRecipient3);
        _tos.push(_tokenRecipient3);

        _amounts.push(forcedTransferAmount);
        _amounts.push(forcedTransferAmount);

        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount);
        assertEq(token.balanceOf(_tokenRecipient2, _bondFTId), transferAmount);
        assertEq(token.balanceOf(_tokenRecipient3, _bondFTId), 0);

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        // ACT: Execute batch forced transfer
        vm.prank(_tokenAdmin);
        token.batchForcedTransfer(_froms, _tos, _bondFTId, _amounts);

        // ASSERT updated balances
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount - forcedTransferAmount);
        assertEq(token.balanceOf(_tokenRecipient2, _bondFTId), transferAmount - forcedTransferAmount);
        assertEq(token.balanceOf(_tokenRecipient3, _bondFTId), 2 * forcedTransferAmount);
    }

    function test_batchForcedTransfer_success_bondClosed() public {
        // ARRANGE
        uint256 mintAmount = 2 * initCwBalance;
        uint256 transferAmount = mintAmount / 2;
        uint256 forcedTransferAmount = transferAmount / 2;

        // Mint tokens for two recipients
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, mintAmount);
        vm.startPrank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient2, _bondFTId, transferAmount);
        vm.stopPrank();

        // Prepare data for batch transfer
        _froms.push(_tokenRecipient1);
        _froms.push(_tokenRecipient2);

        _tos.push(_tokenRecipient3);
        _tos.push(_tokenRecipient3);

        _amounts.push(forcedTransferAmount);
        _amounts.push(forcedTransferAmount);

        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount);
        assertEq(token.balanceOf(_tokenRecipient2, _bondFTId), transferAmount);
        assertEq(token.balanceOf(_tokenRecipient3, _bondFTId), 0);

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        // ACT: Execute batch forced transfer
        vm.prank(_tokenAdmin);
        token.batchForcedTransfer(_froms, _tos, _bondFTId, _amounts);

        // ASSERT updated balances
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount - forcedTransferAmount);
        assertEq(token.balanceOf(_tokenRecipient2, _bondFTId), transferAmount - forcedTransferAmount);
        assertEq(token.balanceOf(_tokenRecipient3, _bondFTId), 2 * forcedTransferAmount);
    }

    function test_batchForcedTransfer_success_frozenTokens() public {
        // ARRANGE
        uint256 mintAmount = 2 * initCwBalance;
        uint256 transferAmount = mintAmount / 2;
        uint256 forcedTransferAmount = transferAmount / 2;

        // Mint tokens for two recipients
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, mintAmount);
        vm.startPrank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient2, _bondFTId, transferAmount);
        vm.stopPrank();

        // Prepare data for batch transfer
        _froms.push(_tokenRecipient1);
        _froms.push(_tokenRecipient2);

        _tos.push(_tokenRecipient3);
        _tos.push(_tokenRecipient3);

        _amounts.push(forcedTransferAmount);
        _amounts.push(forcedTransferAmount);

        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount);
        assertEq(token.balanceOf(_tokenRecipient2, _bondFTId), transferAmount);
        assertEq(token.balanceOf(_tokenRecipient3, _bondFTId), 0);

        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_tokenRecipient1, _bondFTId, transferAmount);

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        // ACT: Execute batch forced transfer
        vm.prank(_tokenAdmin);
        token.batchForcedTransfer(_froms, _tos, _bondFTId, _amounts);

        // ASSERT updated balances
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount - forcedTransferAmount);
        assertEq(token.balanceOf(_tokenRecipient2, _bondFTId), transferAmount - forcedTransferAmount);
        assertEq(token.balanceOf(_tokenRecipient3, _bondFTId), 2 * forcedTransferAmount);
    }

    function test_batchForcedTransfer_revert_invalidArrayLengths_froms_tos() public {
        // ARRANGE
        uint256 mintAmount = 2 * initCwBalance;
        uint256 transferAmount = mintAmount / 2;
        uint256 forcedTransferAmount = transferAmount / 2;

        // Mint tokens for two recipients
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, mintAmount);
        vm.startPrank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient2, _bondFTId, transferAmount);
        vm.stopPrank();

        // Prepare mismatched arrays for batch transfer
        _froms.push(_tokenRecipient1);
        _froms.push(_tokenRecipient2);

        _tos.push(_tokenRecipient3);

        _amounts.push(forcedTransferAmount);

        // ACT & ASSERT: Expect revert due to mismatched lengths of `_froms` and `_tos`
        vm.prank(_tokenAdmin);
        vm.expectRevert(Errors.Token__InvalidArrayLength.selector);
        token.batchForcedTransfer(_froms, _tos, _bondFTId, _amounts);
    }

    function test_batchForcedTransfer_revert_invalidArrayLengths_tos_amounts() public {
        // ARRANGE
        uint256 mintAmount = 2 * initCwBalance;
        uint256 transferAmount = mintAmount / 2;
        uint256 forcedTransferAmount = transferAmount / 2;

        // Mint tokens for two recipients
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, mintAmount);
        vm.startPrank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient2, _bondFTId, transferAmount);
        vm.stopPrank();

        // Prepare mismatched arrays for batch transfer
        _froms.push(_tokenRecipient1);
        _froms.push(_tokenRecipient2);

        _tos.push(_tokenRecipient3);
        _tos.push(_tokenRecipient3);

        _amounts.push(forcedTransferAmount);

        // ACT & ASSERT: Expect revert due to mismatched lengths of `_tos` and `_amounts`
        vm.prank(_tokenAdmin);
        vm.expectRevert(Errors.Token__InvalidArrayLength.selector);
        token.batchForcedTransfer(_froms, _tos, _bondFTId, _amounts);
    }

    function test_batchForcedTransfer_revert_insufficientBalance() public {
        // ARRANGE
        uint256 mintAmount = 2 * initCwBalance;
        uint256 transferAmount = mintAmount / 2;
        uint256 forcedTransferAmount = transferAmount;

        // Mint tokens for two recipients
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, mintAmount);
        vm.startPrank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient2, _bondFTId, transferAmount);
        vm.stopPrank();

        // Prepare data for batch transfer
        _froms.push(_tokenRecipient1);
        _froms.push(_tokenRecipient2);

        _tos.push(_tokenRecipient3);
        _tos.push(_tokenRecipient3);

        _amounts.push(2 * forcedTransferAmount);
        _amounts.push(forcedTransferAmount);

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        // ACT & ASSERT: Expect revert the balance is insufficient
        vm.prank(_tokenAdmin);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.batchForcedTransfer(_froms, _tos, _bondFTId, _amounts);
    }

    function test_batchForcedTransfer_revert_unauthorizedCaller() public {
        // ARRANGE
        uint256 mintAmount = 2 * initCwBalance;
        uint256 transferAmount = mintAmount / 2;

        // Mint tokens for two recipients
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, mintAmount);
        vm.startPrank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient2, _bondFTId, transferAmount);
        vm.stopPrank();

        // ACT & ASSERT: Expect revert when a caller is not granted `FORCE_TRANSFER_ROLE`
        vm.prank(_cwAddr);
        vm.expectRevert(Ownable.Unauthorized.selector);
        token.batchForcedTransfer(_froms, _tos, _bondFTId, _amounts);
    }

    function test_batchForcedTransfer_revert_senderZeroAddress() public {
        // ARRANGE
        uint256 mintAmount = 2 * initCwBalance;
        uint256 transferAmount = mintAmount / 2;
        uint256 forcedTransferAmount = transferAmount / 2;

        // Mint tokens for two recipients
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, mintAmount);
        vm.startPrank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient2, _bondFTId, transferAmount);
        vm.stopPrank();

        // Prepare data for batch transfer
        _froms.push(_tokenRecipient1);
        _froms.push(address(0));

        _tos.push(_tokenRecipient3);
        _tos.push(_tokenRecipient3);

        _amounts.push(forcedTransferAmount);
        _amounts.push(forcedTransferAmount);

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        // ACT & ASSERT: Expect revert when the sender is zero
        vm.prank(_tokenAdmin);
        vm.expectRevert(abi.encodeWithSelector(ERC6909Upgradeable.ERC6909InvalidSender.selector, address(0)));
        token.batchForcedTransfer(_froms, _tos, _bondFTId, _amounts);
    }

    function test_batchForcedTransfer_revert_receiverZeroAddress() public {
        // ARRANGE
        uint256 mintAmount = 2 * initCwBalance;
        uint256 transferAmount = mintAmount / 2;
        uint256 forcedTransferAmount = transferAmount / 2;

        // Mint tokens for two recipients
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, mintAmount);
        vm.startPrank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient2, _bondFTId, transferAmount);
        vm.stopPrank();

        // Prepare data for batch transfer
        _froms.push(_tokenRecipient1);
        _froms.push(_tokenRecipient2);

        _tos.push(address(0));
        _tos.push(address(0));

        _amounts.push(forcedTransferAmount);
        _amounts.push(forcedTransferAmount);

        vm.mockCall(
            _erAddr, abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, address(0)), abi.encode(true)
        );

        // ACT & ASSERT: Expect revert when the receiver is zero address
        vm.prank(_tokenAdmin);
        vm.expectRevert(abi.encodeWithSelector(ERC6909Upgradeable.ERC6909InvalidReceiver.selector, address(0)));
        token.batchForcedTransfer(_froms, _tos, _bondFTId, _amounts);
    }

    function test_batchForcedTransfer_revert_zeroAmount() public {
        // ARRANGE
        uint256 mintAmount = 2 * initCwBalance;
        uint256 transferAmount = mintAmount / 2;

        // Mint tokens for two recipients
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, mintAmount);
        vm.startPrank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient2, _bondFTId, transferAmount);
        vm.stopPrank();

        // Prepare data for batch transfer
        _froms.push(_tokenRecipient1);
        _froms.push(_tokenRecipient2);

        _tos.push(_tokenRecipient3);
        _tos.push(_tokenRecipient3);

        _amounts.push(0);
        _amounts.push(0);

        // ACT & ASSERT: Expect revert when an amount is zero
        vm.prank(_tokenAdmin);
        vm.expectRevert(Errors.Token__ZeroAmount.selector);
        token.batchForcedTransfer(_froms, _tos, _bondFTId, _amounts);
    }

    function test_batchForcedTransfer_revert_paused() public {
        // ARRANGE
        uint256 mintAmount = 2 * initCwBalance;
        uint256 transferAmount = mintAmount / 2;
        uint256 forcedTransferAmount = transferAmount / 2;

        // Mint tokens for two recipients
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, mintAmount);
        vm.startPrank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient2, _bondFTId, transferAmount);
        vm.stopPrank();

        // Prepare data for batch transfer
        _froms.push(_tokenRecipient1);
        _froms.push(_tokenRecipient2);

        _tos.push(_tokenRecipient3);
        _tos.push(_tokenRecipient3);

        _amounts.push(forcedTransferAmount);
        _amounts.push(forcedTransferAmount);

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        // ACT & ASSERT: Expect revert when contract is paused
        vm.prank(_tokenAdmin);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.batchForcedTransfer(_froms, _tos, _bondFTId, _amounts);
    }

    function test_batchForcedTransfer_toIsNotAllowed() public {
        // ARRANGE
        uint256 mintAmount = 2 * initCwBalance;
        uint256 transferAmount = mintAmount / 2;
        uint256 forcedTransferAmount = transferAmount / 2;

        // Mint tokens for two recipients
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, mintAmount);
        vm.startPrank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient2, _bondFTId, transferAmount);
        vm.stopPrank();

        // Prepare data for batch transfer
        _froms.push(_tokenRecipient1);
        _froms.push(_tokenRecipient2);

        _tos.push(_tokenRecipient3);
        _tos.push(_tokenRecipient3);

        _amounts.push(forcedTransferAmount);
        _amounts.push(forcedTransferAmount);

        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount);
        assertEq(token.balanceOf(_tokenRecipient2, _bondFTId), transferAmount);
        assertEq(token.balanceOf(_tokenRecipient3, _bondFTId), 0);

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(false)
        );

        // ACT: Execute batch forced transfer
        vm.prank(_tokenAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Token__TransferNotAllowed.selector, _tokenRecipient1, _tokenRecipient3, _bondFTId
            )
        );
        token.batchForcedTransfer(_froms, _tos, _bondFTId, _amounts);
    }

    function test_batchForcedTransfer_revert_callerNotEnabled() public {
        // ARRANGE: create a caller with FORCE_TRANSFER_ROLE but no registered wallet
        address disabledCaller = _createAddress("disabledCaller");
        _grantRoles(_tokenAddr, disabledCaller, BaseToken(_tokenAddr).FORCE_TRANSFER_ROLE());

        _froms.push(_tokenRecipient1);
        _tos.push(_tokenRecipient3);
        _amounts.push(initCwBalance / 2);

        // ACT & ASSERT: Expect revert when caller wallet is not enabled
        vm.prank(disabledCaller);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__CallerNotEnabled.selector, disabledCaller));
        token.batchForcedTransfer(_froms, _tos, _bondFTId, _amounts);
    }

    function test_batchForcedTransfer_success_fromNotEnabled() public {
        // ARRANGE: disable a holder after it receives tokens, then recover the balance
        uint256 forcedTransferAmount = initCwBalance / 4;

        vm.prank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, forcedTransferAmount);

        vm.prank(_erAdmin);
        _er.setAccountStatus(_tokenRecipient1, AccountStatus.DISABLED, "");

        _froms.push(_tokenRecipient1);
        _tos.push(_tokenRecipient3);
        _amounts.push(forcedTransferAmount);

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        uint256 recipientBalanceBefore = token.balanceOf(_tokenRecipient3, _bondFTId);

        // ACT & ASSERT: Disabled source wallets can be recovered by an enabled force-transfer caller
        vm.prank(_tokenAdmin);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Transfer(_tokenAdmin, _tokenRecipient1, _tokenRecipient3, _bondFTId, forcedTransferAmount);
        token.batchForcedTransfer(_froms, _tos, _bondFTId, _amounts);

        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), 0);
        assertEq(token.balanceOf(_tokenRecipient3, _bondFTId), recipientBalanceBefore + forcedTransferAmount);
    }

    function test_batchForcedTransfer_revert_fromProtected() public {
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, _cwAddr));

        _froms.push(_cwAddr);
        _tos.push(_tokenRecipient3);
        _amounts.push(initCwBalance / 2);

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        vm.prank(_tokenAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__AddressProtected.selector, _cwAddr));
        token.batchForcedTransfer(_froms, _tos, _bondFTId, _amounts);
    }

    function test_batchForcedTransfer_revert_toProtected() public {
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, _tokenRecipient3));

        _froms.push(_cwAddr);
        _tos.push(_tokenRecipient3);
        _amounts.push(initCwBalance / 2);

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _tokenRecipient3),
            abi.encode(true)
        );

        vm.prank(_tokenAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Token__ProtectedReceiverTransferNotAllowed.selector,
                _cwAddr,
                _tokenRecipient3,
                _tokenAdmin,
                _bondFTId
            )
        );
        token.batchForcedTransfer(_froms, _tos, _bondFTId, _amounts);
    }

    /*//////////////////////////////////////////////////////////////
                               burnBatch
    //////////////////////////////////////////////////////////////*/

    function test_burnBatch_success_bondRegistryCaller() public {
        // ARRANGE
        uint256 transferAmount = initCwBalance / 2;
        uint256 burntAmount = initCwBalance / 4;

        // Mint tokens for two recipients
        vm.startPrank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient2, _bondFTId, transferAmount);
        vm.stopPrank();

        // ASSERT: Confirm initial total supply
        assertEq(token.totalSupply(_bondFTId), initCwBalance);

        // ARRANGE: Prepare recipients and burn amounts
        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(burntAmount);
        _amounts.push(burntAmount);

        // ACT: Execute batch burn
        vm.prank(_brAddr);
        token.burnBatch(_tos, _bondFTId, _amounts);

        // ASSERT: Validate updated total supply and balances
        assertEq(token.totalSupply(_bondFTId), initCwBalance - (2 * burntAmount));
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount - burntAmount);
        assertEq(token.balanceOf(_tokenRecipient2, _bondFTId), transferAmount - burntAmount);
    }

    function test_burnBatch_success_frozenTokens() public {
        // ARRANGE
        uint256 transferAmount = initCwBalance / 2;
        uint256 burntAmount = initCwBalance / 4;

        vm.startPrank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient2, _bondFTId, transferAmount);
        vm.stopPrank();

        // ASSERT: Confirm initial total supply
        assertEq(token.totalSupply(_bondFTId), initCwBalance);

        // ARRANGE: Prepare recipients and burn amounts
        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(burntAmount);
        _amounts.push(burntAmount);

        vm.startPrank(_tokenAdmin);
        token.freezePartialTokens(_tokenRecipient1, _bondFTId, burntAmount + burntAmount / 2);
        vm.stopPrank();

        // ACT: Execute batch burn
        vm.prank(_brAddr);
        token.burnBatch(_tos, _bondFTId, _amounts);

        // ASSERT: Validate updated total supply and balances
        assertEq(token.totalSupply(_bondFTId), initCwBalance - (2 * burntAmount));
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount - burntAmount);
        assertEq(token.balanceOf(_tokenRecipient2, _bondFTId), transferAmount - burntAmount);
    }

    function test_burnBatch_reverts_invalidArrayLengths() public {
        // ARRANGE: Prepare mismatched recipients and amounts arrays
        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(initCwBalance);

        // ACT & ASSERT: Expect revert due to mismatched array lengths
        vm.prank(_brAddr);
        vm.expectRevert(Errors.Token__InvalidArrayLength.selector);
        token.burnBatch(_tos, _bondFTId, _amounts);
    }

    function test_burnBatch_reverts_callerNotBondRegistry() public {
        // ARRANGE: Prepare recipients and amounts arrays
        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(initCwBalance);

        // ACT & ASSERT: Expect revert due to unauthorized caller
        vm.prank(_cwAddr);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__CallerNotBondRegistry.selector, _cwAddr));
        token.burnBatch(_tos, _bondFTId, _amounts);
    }

    function test_burnBatch_success_fromNotEnabled() public {
        // ARRANGE: disable a holder after it receives tokens, then burn from it through BondRegistry
        uint256 burnAmount = initCwBalance / 4;

        vm.prank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, burnAmount);

        vm.prank(_erAdmin);
        _er.setAccountStatus(_tokenRecipient1, AccountStatus.DISABLED, "");

        _tos.push(_tokenRecipient1);
        _amounts.push(burnAmount);

        uint256 totalSupplyBefore = token.totalSupply(_bondFTId);

        // ACT & ASSERT: Disabled source wallets can be burned by BondRegistry
        vm.prank(_brAddr);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Transfer(_brAddr, _tokenRecipient1, address(0), _bondFTId, burnAmount);
        token.burnBatch(_tos, _bondFTId, _amounts);

        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), 0);
        assertEq(token.totalSupply(_bondFTId), totalSupplyBefore - burnAmount);
    }

    function test_burnBatch_reverts_fromProtected() public {
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, _cwAddr));

        _tos.push(_cwAddr);
        _amounts.push(initCwBalance / 2);

        vm.prank(_brAddr);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__AddressProtected.selector, _cwAddr));
        token.burnBatch(_tos, _bondFTId, _amounts);
    }

    /*//////////////////////////////////////////////////////////////
                        batchFreezePartialTokens
    //////////////////////////////////////////////////////////////*/
    function test_batchFreezePartialTokens_success() public {
        // ARRANGE
        uint256 amount = initCwBalance / 2;
        vm.startPrank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, amount);
        token.transferFrom(_cwAddr, _tokenRecipient2, _bondFTId, amount);
        vm.stopPrank();

        // Prepare addresses and freeze token amounts
        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(amount);
        _amounts.push(amount);

        // ACT
        vm.prank(_tokenAdmin);
        token.batchFreezePartialTokens(_tos, _bondFTId, _amounts);

        // ASSERT: Validate frozen token balances
        assertEq(token.frozenBalanceOf(_tokenRecipient1, _bondFTId), amount);
        assertEq(token.frozenBalanceOf(_tokenRecipient2, _bondFTId), amount);
    }

    function test_batchFreezePartialTokens_revert_invalidArrayLengths() public {
        // ARRANGE
        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(initCwBalance);

        // ACT & ASSERT: Expect revert due to mismatched array lengths
        vm.prank(_tokenAdmin);
        vm.expectRevert(Errors.Token__InvalidArrayLength.selector);
        token.batchFreezePartialTokens(_tos, _bondFTId, _amounts);
    }

    function test_batchFreezePartialTokens_revert_unauthorizedCaller() public {
        // ARRANGE
        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(initCwBalance);

        _timelockOp(
            _tokenAddr,
            abi.encodeWithSelector(
                OwnableRoles.revokeRoles.selector, _tokenAdmin, BaseToken(_tokenAddr).TOKEN_FREEZER_ROLE()
            )
        );

        // ACT & ASSERT: Expect revert when the caller does not have permission to freeze tokens
        vm.prank(_tokenAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        token.batchFreezePartialTokens(_tos, _bondFTId, _amounts);
    }

    function test_batchFreezePartialTokens_success_callerNotEnabled() public {
        // ARRANGE
        _tos.push(_cwAddr);
        uint256 amount = initCwBalance / 2;
        _amounts.push(amount);

        vm.prank(_erAdmin);
        _er.setAccountStatus(_tokenAdmin, AccountStatus.DISABLED, "");

        // ACT
        vm.prank(_tokenAdmin);
        token.batchFreezePartialTokens(_tos, _bondFTId, _amounts);

        // ASSERT: Freezer authority is RBAC-only; caller registry status is not required.
        assertEq(token.frozenBalanceOf(_cwAddr, _bondFTId), amount);
    }

    function test_batchFreezePartialTokens_revert_protectedAddress() public {
        // ARRANGE
        _tos.push(_cwAddr);
        uint256 amount = initCwBalance / 2;
        _amounts.push(amount);
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, _cwAddr));

        // ACT & ASSERT: Protected custody balances cannot be frozen through the batch entrypoint.
        vm.prank(_tokenAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__AddressProtected.selector, _cwAddr));
        token.batchFreezePartialTokens(_tos, _bondFTId, _amounts);
    }

    /*//////////////////////////////////////////////////////////////
                       batchUnfreezePartialTokens
    //////////////////////////////////////////////////////////////*/
    function test_batchUnfreezePartialTokens_success() public {
        // ARRANGE
        uint256 transferAmount = initCwBalance / 2;
        uint256 unfreezeAmount = initCwBalance / 4;

        vm.startPrank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient2, _bondFTId, transferAmount);
        vm.stopPrank();

        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(unfreezeAmount);
        _amounts.push(unfreezeAmount);

        vm.startPrank(_tokenAdmin);
        token.freezePartialTokens(_tokenRecipient1, _bondFTId, transferAmount);
        token.freezePartialTokens(_tokenRecipient2, _bondFTId, transferAmount);

        // ASSERT: Validate initial frozen token balances
        assertEq(token.frozenBalanceOf(_tokenRecipient1, _bondFTId), transferAmount);
        assertEq(token.frozenBalanceOf(_tokenRecipient2, _bondFTId), transferAmount);

        // ACT: Unfreeze partial tokens in a batch operation
        token.batchUnfreezePartialTokens(_tos, _bondFTId, _amounts);

        // ASSERT: Validate updated frozen token balances
        assertEq(token.frozenBalanceOf(_tokenRecipient1, _bondFTId), unfreezeAmount);
        assertEq(token.frozenBalanceOf(_tokenRecipient2, _bondFTId), unfreezeAmount);
        vm.stopPrank();
    }

    function test_batchUnfreezePartialTokens_revert_invalidArrayLengths() public {
        // ARRANGE
        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(initCwBalance);

        // ACT & ASSERT: Expect revert due to mismatched array lengths
        vm.prank(_tokenAdmin);
        vm.expectRevert(Errors.Token__InvalidArrayLength.selector);
        token.batchUnfreezePartialTokens(_tos, _bondFTId, _amounts);
    }

    function test_batchUnfreezePartialTokens_revert_unauthorizedCaller() public {
        // ARRANGE
        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(initCwBalance);

        _timelockOp(
            _tokenAddr,
            abi.encodeWithSelector(
                OwnableRoles.revokeRoles.selector, _tokenAdmin, BaseToken(_tokenAddr).TOKEN_FREEZER_ROLE()
            )
        );

        // ACT & ASSERT: Expect revert when the caller does not have permission to freeze tokens
        vm.prank(_tokenAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        token.batchUnfreezePartialTokens(_tos, _bondFTId, _amounts);
    }

    function test_batchUnfreezePartialTokens_success_callerNotEnabled() public {
        // ARRANGE
        uint256 amount = initCwBalance / 2;

        _tos.push(_cwAddr);
        _amounts.push(amount);

        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_cwAddr, _bondFTId, amount);

        vm.prank(_erAdmin);
        _er.setAccountStatus(_tokenAdmin, AccountStatus.DISABLED, "");

        // ACT
        vm.prank(_tokenAdmin);
        token.batchUnfreezePartialTokens(_tos, _bondFTId, _amounts);

        // ASSERT: Freezer authority is RBAC-only; caller registry status is not required.
        assertEq(token.frozenBalanceOf(_cwAddr, _bondFTId), 0);
    }

    /**
     * ==============================================================
     *                        OTHER FUNCTIONS
     * ==============================================================
     */

    /*//////////////////////////////////////////////////////////////
                                transfer
    //////////////////////////////////////////////////////////////*/
    function test_transfer_success_owner() public {
        // ARRANGE
        uint256 transferAmount = initCwBalance / 2;

        // ACT
        vm.prank(_cwAddr);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Transfer(_cwAddr, _cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transfer(_tokenRecipient1, _bondFTId, transferAmount);

        // ASSERT
        assertEq(token.totalSupply(_bondFTId), initCwBalance);
        assertEq(token.balanceOf(_cwAddr, _bondFTId), transferAmount);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount);
    }

    function test_transfer_success_sufficientFreeBalance() public {
        // ARRANGE
        uint256 frozenAmount = initCwBalance / 2;
        uint256 freeBalance = initCwBalance - frozenAmount;

        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_cwAddr, _bondFTId, frozenAmount);

        // ACT
        vm.prank(_cwAddr);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Transfer(_cwAddr, _cwAddr, _tokenRecipient1, _bondFTId, freeBalance);
        token.transfer(_tokenRecipient1, _bondFTId, freeBalance);

        // ASSERT
        assertEq(token.totalSupply(_bondFTId), initCwBalance);
        assertEq(token.balanceOf(_cwAddr, _bondFTId), frozenAmount);
        assertEq(token.frozenBalanceOf(_cwAddr, _bondFTId), frozenAmount);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), freeBalance);
    }

    function test_transfer_revert_pushToProtectedReceiver() public {
        uint256 transferAmount = 1;

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, _tokenRecipient1));

        vm.prank(_cwAddr);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Token__ProtectedReceiverTransferNotAllowed.selector,
                _cwAddr,
                _tokenRecipient1,
                _cwAddr,
                _bondFTId
            )
        );
        token.transfer(_tokenRecipient1, _bondFTId, transferAmount);
    }

    function test_transfer_revert_insufficientFreeBalance() public {
        // ARRANGE
        uint256 frozenAmount = (initCwBalance / 2) + 1;
        uint256 transferredAmount = initCwBalance / 2;

        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_cwAddr, _bondFTId, frozenAmount);

        // ACT & ASSERT: Expect revert when unfrozen balance is insufficient
        vm.prank(_cwAddr);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.transfer(_tokenRecipient1, _bondFTId, transferredAmount);
    }

    function test_transfer_revert_zeroAmount() public {
        // ACT & ASSERT: Expect revert when amount is zero
        vm.prank(_cwAddr);
        vm.expectRevert(Errors.Token__ZeroAmount.selector);
        token.transfer(_tokenRecipient1, _bondFTId, 0);
    }

    function test_transfer_revert_insufficientBalance() public {
        // ACT & ASSERT: Expect revert when the balance is insufficient
        vm.prank(_cwAddr);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.transfer(_tokenRecipient1, _bondFTId, initCwBalance + 1);
    }

    function test_transfer_revert_paused() public {
        // ARRANGE
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, initCwBalance);

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ACT & ASSERT: Expect revert when contract is paused
        vm.prank(_cwAddr);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.transfer(_tokenRecipient1, _bondFTId, initCwBalance);
    }

    function test_transfer_revert_invalidTokenId() public {
        // ARRANGE
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, initCwBalance);

        // ACT & ASSERT: Expect revert when the tokenId is invalid (no balance for tokenId 0)
        vm.prank(_cwAddr);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.transfer(_tokenRecipient1, 0, initCwBalance);
    }

    function test_transfer_revert_toZeroAddress() public {
        // ARRANGE
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, initCwBalance);

        // ACT & ASSERT: Expect revert when 'to is zero address
        vm.prank(_cwAddr);
        vm.expectRevert(abi.encodeWithSelector(ERC6909Upgradeable.ERC6909InvalidReceiver.selector, address(0)));
        token.transfer(address(0), _bondFTId, initCwBalance);
    }

    function test_transfer_revert_senderZeroAddress() public {
        // ARRANGE
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, initCwBalance);

        // ACT & ASSERT: Expect revert when 'sender' is zero address
        vm.prank(address(0));
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.transfer(_tokenRecipient1, _bondFTId, initCwBalance);
    }

    /*//////////////////////////////////////////////////////////////
                              transferFrom
    //////////////////////////////////////////////////////////////*/
    function test_transferFrom_success_owner() public {
        // ARRANGE
        uint256 transferAmount = initCwBalance / 2;

        // ACT
        vm.prank(_cwAddr);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Transfer(_cwAddr, _cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);

        // ASSERT
        assertEq(token.totalSupply(_bondFTId), initCwBalance);
        assertEq(token.balanceOf(_cwAddr, _bondFTId), transferAmount);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount);
    }

    function test_transferFrom_success_fromProtectedAddress() public {
        uint256 transferAmount = initCwBalance / 2;

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, _cwAddr));

        vm.prank(_cwAddr);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);

        assertEq(token.totalSupply(_bondFTId), initCwBalance);
        assertEq(token.balanceOf(_cwAddr, _bondFTId), transferAmount);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount);
    }

    function test_transferFrom_success_protectedReceiverPullsWithAllowance() public {
        uint256 transferAmount = initCwBalance / 2;

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, _tokenRecipient1));

        vm.prank(_cwAddr);
        token.approve(_tokenRecipient1, _bondFTId, transferAmount);

        vm.prank(_tokenRecipient1);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);

        assertEq(token.balanceOf(_cwAddr, _bondFTId), initCwBalance - transferAmount);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount);
        assertEq(token.allowance(_cwAddr, _tokenRecipient1, _bondFTId), 0);
    }

    function test_transferFrom_success_sufficientFreeBalance() public {
        // ARRANGE
        uint256 frozenAmount = initCwBalance / 2;
        uint256 freeBalance = initCwBalance - frozenAmount;

        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_cwAddr, _bondFTId, frozenAmount);

        // ACT
        vm.prank(_cwAddr);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Transfer(_cwAddr, _cwAddr, _tokenRecipient1, _bondFTId, freeBalance);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, freeBalance);

        // ASSERT
        assertEq(token.totalSupply(_bondFTId), initCwBalance);
        assertEq(token.balanceOf(_cwAddr, _bondFTId), frozenAmount);
        assertEq(token.frozenBalanceOf(_cwAddr, _bondFTId), frozenAmount);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), freeBalance);
    }

    function test_transferFrom_success_operator() public {
        // ARRANGE
        address operator = makeAddr("operator");
        _registerWallet(operator);
        uint256 transferAmount = initCwBalance / 2;

        vm.startPrank(_cwAddr);
        token.setOperator(operator, true);
        vm.stopPrank();

        // ACT
        vm.prank(operator);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Transfer(operator, _cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);

        // ASSERT
        assertEq(token.totalSupply(_bondFTId), initCwBalance);
        assertEq(token.balanceOf(_cwAddr, _bondFTId), transferAmount);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount);
    }

    function test_transferFrom_success_allowance() public {
        // ARRANGE
        address spender = makeAddr("spender");
        _registerWallet(spender);

        vm.prank(_cwAddr);
        token.approve(spender, _bondFTId, initCwBalance);

        // ACT
        vm.prank(spender);
        vm.expectEmit(true, true, true, true);
        emit IERC6909.Transfer(spender, _cwAddr, _tokenRecipient1, _bondFTId, initCwBalance);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, initCwBalance);

        // ASSERT
        assertEq(token.totalSupply(_bondFTId), initCwBalance);
        assertEq(token.balanceOf(_cwAddr, _bondFTId), 0);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), initCwBalance);
    }

    function test_transferFrom_revert_notOperator() public {
        // ARRANGE
        address operator = makeAddr("operator");
        _registerWallet(operator);
        uint256 transferAmount = initCwBalance / 2;

        // ACT & ASSERT: Expect revert when the caller is not operator for owner
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909Upgradeable.ERC6909InsufficientAllowance.selector, operator, 0, transferAmount, _bondFTId
            )
        );
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferAmount);
    }

    function test_transferFrom_revert_insufficientAllowance() public {
        // ARRANGE
        address spender = makeAddr("spender");
        _registerWallet(spender);
        uint256 allowance = initCwBalance / 2;

        vm.prank(_cwAddr);
        token.approve(spender, _bondFTId, allowance);

        // ACT & ASSERT: Expect revert when caller allowance is insufficient for transfer
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909Upgradeable.ERC6909InsufficientAllowance.selector, spender, allowance, initCwBalance, _bondFTId
            )
        );
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, initCwBalance);
    }

    function test_transferFrom_revert_insufficientFreeBalance() public {
        // ARRANGE
        uint256 frozenAmount = initCwBalance / 2 + 1;
        uint256 transferredAmount = initCwBalance / 2;

        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_cwAddr, _bondFTId, frozenAmount);

        // ACT & ASSERT: Expect revert when unfrozen balance is insufficient
        vm.prank(_cwAddr);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, transferredAmount);
    }

    function test_transferFrom_revert_zeroAmount() public {
        // ACT & ASSERT: Expect revert when amount is zero
        vm.prank(_cwAddr);
        vm.expectRevert(Errors.Token__ZeroAmount.selector);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, 0);
    }

    function test_transferFrom_revert_insufficientBalance() public {
        // ACT & ASSERT: Expect revert when the balance is insufficient
        vm.prank(_cwAddr);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, initCwBalance + 1);
    }

    function test_transferFrom_revert_paused() public {
        // ARRANGE
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ACT & ASSERT: Expect revert when contract is paused
        vm.prank(_cwAddr);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, initCwBalance);
    }

    function test_transferFrom_revert_tokenIdIsPaused() public {
        // ARRANGE
        vm.prank(_brAddr);
        token.pauseTokenId(_bondFTId);

        // ACT & ASSERT: Expect revert when token id is paused
        vm.prank(_cwAddr);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__TokenIdIsPaused.selector, _bondFTId));
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, initCwBalance);
    }

    function test_transferFrom_revert_transferIsNotAllowed() public {
        // ARRANGE
        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(
                IEntityRegistry.canTransfer.selector, _cwAddr, _tokenRecipient1, _cwAddr, _bondFTId, initCwBalance
            ),
            abi.encode(false)
        );

        // ACT & ASSERT: Expect revert when transfer is not allowed
        vm.prank(_cwAddr);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Token__TransferNotAllowed.selector, _cwAddr, _tokenRecipient1, _bondFTId)
        );
        token.transferFrom(_cwAddr, _tokenRecipient1, _bondFTId, initCwBalance);
    }

    function test_transferFrom_revert_invalidTokenId() public {
        // ACT & ASSERT: Expect revert when the tokenId is invalid (no balance for tokenId 0)
        vm.prank(_cwAddr);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.transferFrom(_cwAddr, _tokenRecipient1, 0, initCwBalance);
    }

    function test_transferFrom_revert_toZeroAddress() public {
        // ACT & ASSERT: Expect revert when 'to is zero address
        vm.prank(_cwAddr);
        vm.expectRevert(abi.encodeWithSelector(ERC6909Upgradeable.ERC6909InvalidReceiver.selector, address(0)));
        token.transferFrom(_cwAddr, address(0), _bondFTId, initCwBalance);
    }

    function test_transferFrom_revert_senderZeroAddress() public {
        // ACT & ASSERT: Expect revert when 'sender' is zero address and amount is zero
        vm.prank(address(0));
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.transferFrom(address(0), _tokenRecipient1, _bondFTId, initCwBalance);
    }

    /*//////////////////////////////////////////////////////////////
                           batchTransferFrom
    //////////////////////////////////////////////////////////////*/

    function test_batchTransferFrom_success() public {
        // ARRANGE
        uint256 transferAmount = initCwBalance / 2;

        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(transferAmount);
        _amounts.push(transferAmount);

        // ASSERT: initial state
        assertEq(token.balanceOf(_cwAddr, _bondFTId), initCwBalance);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), 0);
        assertEq(token.balanceOf(_tokenRecipient2, _bondFTId), 0);

        // ACT
        vm.prank(_cwAddr);
        token.batchTransferFrom(_cwAddr, _tos, _bondFTId, _amounts);

        // ASSERT
        assertEq(token.balanceOf(_cwAddr, _bondFTId), 0);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount);
        assertEq(token.balanceOf(_tokenRecipient2, _bondFTId), transferAmount);
    }

    function test_batchTransferFrom_success_operator() public {
        // ARRANGE
        address operator = makeAddr("operator");
        _registerWallet(operator);
        uint256 transferAmount = initCwBalance / 2;

        vm.prank(_cwAddr);
        token.setOperator(operator, true);

        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(transferAmount);
        _amounts.push(transferAmount);

        // ASSERT: initial state
        assertEq(token.balanceOf(_cwAddr, _bondFTId), initCwBalance);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), 0);
        assertEq(token.balanceOf(_tokenRecipient2, _bondFTId), 0);

        // ACT
        vm.prank(operator);
        token.batchTransferFrom(_cwAddr, _tos, _bondFTId, _amounts);

        // ASSERT
        assertEq(token.balanceOf(_cwAddr, _bondFTId), 0);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount);
        assertEq(token.balanceOf(_tokenRecipient2, _bondFTId), transferAmount);
    }

    function test_batchTransferFrom_success_allowance() public {
        // ARRANGE
        address operator = makeAddr("operator");
        _registerWallet(operator);
        uint256 transferAmount = initCwBalance / 2;

        vm.prank(_cwAddr);
        token.approve(operator, _bondFTId, initCwBalance);

        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(transferAmount);
        _amounts.push(transferAmount);

        // ASSERT: initial state
        assertEq(token.balanceOf(_cwAddr, _bondFTId), initCwBalance);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), 0);
        assertEq(token.balanceOf(_tokenRecipient2, _bondFTId), 0);

        // ACT
        vm.prank(operator);
        token.batchTransferFrom(_cwAddr, _tos, _bondFTId, _amounts);

        // ASSERT
        assertEq(token.balanceOf(_cwAddr, _bondFTId), 0);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount);
        assertEq(token.balanceOf(_tokenRecipient2, _bondFTId), transferAmount);
    }

    function test_batchTransferFrom_revert_pushToProtectedReceiverByOperator() public {
        address operator = makeAddr("operator");
        _registerWallet(operator);
        uint256 transferAmount = initCwBalance / 2;

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, _tokenRecipient1));

        vm.prank(_cwAddr);
        token.setOperator(operator, true);

        _tos.push(_tokenRecipient1);
        _amounts.push(transferAmount);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Token__ProtectedReceiverTransferNotAllowed.selector,
                _cwAddr,
                _tokenRecipient1,
                operator,
                _bondFTId
            )
        );
        token.batchTransferFrom(_cwAddr, _tos, _bondFTId, _amounts);
    }

    function test_batchTransferFrom_revert_invalidArrayLengths() public {
        // ARRANGE
        _tos.push(_tokenRecipient2);
        _tos.push(_tokenRecipient1);
        _amounts.push(initCwBalance / 2);

        // ACT & ASSERT: Expect revert due to mismatched array lengths
        vm.prank(_tokenRecipient1);
        vm.expectRevert(Errors.Token__InvalidArrayLength.selector);
        token.batchTransferFrom(_tokenRecipient1, _tos, _bondFTId, _amounts);
    }

    function test_batchTransferFrom_revert_senderZeroAddress() public {
        // ARRANGE
        uint256 transferAmount = initCwBalance / 2;

        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(transferAmount);
        _amounts.push(transferAmount);

        // ACT & ASSERT: Expect revert when the sender is zero address
        vm.prank(address(0));
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.batchTransferFrom(address(0), _tos, _bondFTId, _amounts);
    }

    function test_batchTransferFrom_revert_receiverZeroAddress() public {
        // ARRANGE
        uint256 transferAmount = initCwBalance / 2;

        _tos.push(address(0));
        _tos.push(_tokenRecipient2);
        _amounts.push(transferAmount);
        _amounts.push(transferAmount);

        // ACT & ASSERT: Expect revert when the receiver is zero address
        vm.prank(_cwAddr);
        vm.expectRevert(abi.encodeWithSelector(ERC6909Upgradeable.ERC6909InvalidReceiver.selector, address(0)));
        token.batchTransferFrom(_cwAddr, _tos, _bondFTId, _amounts);
    }

    function test_batchTransferFrom_revert_notOperator() public {
        // ARRANGE
        address operator = makeAddr("operator");
        _registerWallet(operator);
        uint256 transferAmount = initCwBalance / 2;

        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(transferAmount);
        _amounts.push(transferAmount);

        // ACT & ASSERT: Expect revert when the caller is not operator
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909Upgradeable.ERC6909InsufficientAllowance.selector, operator, 0, _amounts[0], _bondFTId
            )
        );
        token.batchTransferFrom(_cwAddr, _tos, _bondFTId, _amounts);
    }

    function test_batchTransferFrom_revert_insufficientAllowance() public {
        // ARRANGE
        address operator = makeAddr("operator");
        _registerWallet(operator);
        uint256 transferAmount = initCwBalance / 2;

        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(transferAmount);
        _amounts.push(transferAmount);

        vm.prank(_cwAddr);
        token.approve(operator, _bondFTId, transferAmount / 2);

        // ACT & ASSERT: Expect revert when the caller does not have sufficient allowance
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909Upgradeable.ERC6909InsufficientAllowance.selector,
                operator,
                transferAmount / 2,
                _amounts[0],
                _bondFTId
            )
        );
        token.batchTransferFrom(_cwAddr, _tos, _bondFTId, _amounts);
    }

    function test_batchTransferFrom_revert_tokenFrozen() public {
        // ARRANGE
        uint256 transferAmount = initCwBalance / 2;

        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(transferAmount);
        _amounts.push(transferAmount);

        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_cwAddr, _bondFTId, transferAmount / 2);

        // ACT & ASSERT: Expect revert when tokens are frozen
        vm.prank(_cwAddr);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.batchTransferFrom(_cwAddr, _tos, _bondFTId, _amounts);
    }

    function test_batchTransferFrom_revert_insufficientBalance() public {
        // ARRANGE
        uint256 transferAmount = initCwBalance;

        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(transferAmount);
        _amounts.push(transferAmount);

        // ACT & ASSERT: Expect revert when the sender balance is insufficient
        vm.prank(_cwAddr);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.batchTransferFrom(_cwAddr, _tos, _bondFTId, _amounts);
    }

    function test_batchTransferFrom_revert_paused() public {
        // ARRANGE
        uint256 transferAmount = initCwBalance / 2;

        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(transferAmount);
        _amounts.push(transferAmount);

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ACT & ASSERT: Expect revert when contract is paused
        vm.prank(_cwAddr);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.batchTransferFrom(_cwAddr, _tos, _bondFTId, _amounts);
    }

    function test_batchTransferFrom_revert_zeroAmount() public {
        // ARRANGE
        uint256 transferAmount = initCwBalance / 2;

        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(transferAmount);
        _amounts.push(0);

        // ACT & ASSERT: Expect revert when amount is zero
        vm.prank(_cwAddr);
        vm.expectRevert(Errors.Token__ZeroAmount.selector);
        token.batchTransferFrom(_cwAddr, _tos, _bondFTId, _amounts);
    }

    function test_batchTransferFrom_revert_tokenIdIsPaused() public {
        // ARRANGE
        uint256 transferAmount = initCwBalance / 2;

        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(transferAmount);
        _amounts.push(transferAmount);

        vm.prank(_brAddr);
        token.pauseTokenId(_bondFTId);

        // ACT & ASSERT: Expect revert when token id is paused
        vm.prank(_cwAddr);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__TokenIdIsPaused.selector, _bondFTId));
        token.batchTransferFrom(_cwAddr, _tos, _bondFTId, _amounts);
    }

    function test_batchTransferFrom_revert_transferIsNotAllowed() public {
        // ARRANGE
        uint256 transferAmount = initCwBalance / 2;

        _tos.push(_tokenRecipient1);
        _tos.push(_tokenRecipient2);
        _amounts.push(transferAmount);
        _amounts.push(transferAmount);

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(
                IEntityRegistry.canTransfer.selector, _cwAddr, _tokenRecipient1, _cwAddr, _bondFTId, transferAmount
            ),
            abi.encode(false)
        );

        // ACT & ASSERT: Expect revert when transfer is not allowed
        vm.prank(_cwAddr);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Token__TransferNotAllowed.selector, _cwAddr, _tokenRecipient1, _bondFTId)
        );
        token.batchTransferFrom(_cwAddr, _tos, _bondFTId, _amounts);
    }

    /*//////////////////////////////////////////////////////////////
                  batchTransferFrom (Multiple TokenIds)
    //////////////////////////////////////////////////////////////*/

    function test_batchTransferFromMultipleTokenIds_success() public {
        // ARRANGE
        uint256 tokenId2 = _bondFTId + 1;
        uint256 transferAmount1 = initCwBalance / 4;
        uint256 transferAmount2 = initCwBalance / 2;

        // Mint second tokenId
        vm.prank(_brAddr);
        token.mint(_cwAddr, tokenId2, initCwBalance);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = _bondFTId;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = transferAmount1;
        amounts[1] = transferAmount2;

        // ASSERT: initial state
        assertEq(token.balanceOf(_cwAddr, _bondFTId), initCwBalance);
        assertEq(token.balanceOf(_cwAddr, tokenId2), initCwBalance);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), 0);
        assertEq(token.balanceOf(_tokenRecipient1, tokenId2), 0);

        // ACT
        vm.prank(_cwAddr);
        token.batchTransferFrom(_cwAddr, _tokenRecipient1, tokenIds, amounts);

        // ASSERT
        assertEq(token.balanceOf(_cwAddr, _bondFTId), initCwBalance - transferAmount1);
        assertEq(token.balanceOf(_cwAddr, tokenId2), initCwBalance - transferAmount2);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount1);
        assertEq(token.balanceOf(_tokenRecipient1, tokenId2), transferAmount2);
    }

    function test_batchTransferFromMultipleTokenIds_success_operator() public {
        // ARRANGE
        address operator = makeAddr("operator");
        _registerWallet(operator);
        uint256 tokenId2 = _bondFTId + 1;
        uint256 transferAmount1 = initCwBalance / 4;
        uint256 transferAmount2 = initCwBalance / 2;

        // Mint second tokenId
        vm.prank(_brAddr);
        token.mint(_cwAddr, tokenId2, initCwBalance);

        vm.prank(_cwAddr);
        token.setOperator(operator, true);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = _bondFTId;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = transferAmount1;
        amounts[1] = transferAmount2;

        // ACT
        vm.prank(operator);
        token.batchTransferFrom(_cwAddr, _tokenRecipient1, tokenIds, amounts);

        // ASSERT
        assertEq(token.balanceOf(_cwAddr, _bondFTId), initCwBalance - transferAmount1);
        assertEq(token.balanceOf(_cwAddr, tokenId2), initCwBalance - transferAmount2);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount1);
        assertEq(token.balanceOf(_tokenRecipient1, tokenId2), transferAmount2);
    }

    function test_batchTransferFromMultipleTokenIds_success_allowance() public {
        // ARRANGE
        address operator = makeAddr("operator");
        _registerWallet(operator);
        uint256 tokenId2 = _bondFTId + 1;
        uint256 transferAmount1 = initCwBalance / 4;
        uint256 transferAmount2 = initCwBalance / 2;

        // Mint second tokenId
        vm.prank(_brAddr);
        token.mint(_cwAddr, tokenId2, initCwBalance);

        vm.startPrank(_cwAddr);
        token.approve(operator, _bondFTId, initCwBalance);
        token.approve(operator, tokenId2, initCwBalance);
        vm.stopPrank();

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = _bondFTId;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = transferAmount1;
        amounts[1] = transferAmount2;

        // ACT
        vm.prank(operator);
        token.batchTransferFrom(_cwAddr, _tokenRecipient1, tokenIds, amounts);

        // ASSERT
        assertEq(token.balanceOf(_cwAddr, _bondFTId), initCwBalance - transferAmount1);
        assertEq(token.balanceOf(_cwAddr, tokenId2), initCwBalance - transferAmount2);
        assertEq(token.balanceOf(_tokenRecipient1, _bondFTId), transferAmount1);
        assertEq(token.balanceOf(_tokenRecipient1, tokenId2), transferAmount2);
    }

    function test_batchTransferFromMultipleTokenIds_revert_pushToProtectedReceiverByOperator() public {
        address operator = makeAddr("operator");
        _registerWallet(operator);
        uint256 tokenId2 = _bondFTId + 1;
        uint256 transferAmount1 = initCwBalance / 4;
        uint256 transferAmount2 = initCwBalance / 2;

        vm.prank(_brAddr);
        token.mint(_cwAddr, tokenId2, initCwBalance);

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IDEUSSToken.protectAddress.selector, _tokenRecipient1));

        vm.prank(_cwAddr);
        token.setOperator(operator, true);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = _bondFTId;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = transferAmount1;
        amounts[1] = transferAmount2;

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Token__ProtectedReceiverTransferNotAllowed.selector,
                _cwAddr,
                _tokenRecipient1,
                operator,
                _bondFTId
            )
        );
        token.batchTransferFrom(_cwAddr, _tokenRecipient1, tokenIds, amounts);
    }

    function test_batchTransferFromMultipleTokenIds_revert_invalidArrayLengths() public {
        // ARRANGE
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = _bondFTId;
        tokenIds[1] = _bondFTId + 1;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = initCwBalance / 2;

        // ACT & ASSERT: Expect revert due to mismatched array lengths
        vm.prank(_cwAddr);
        vm.expectRevert(Errors.Token__InvalidArrayLength.selector);
        token.batchTransferFrom(_cwAddr, _tokenRecipient1, tokenIds, amounts);
    }

    function test_batchTransferFromMultipleTokenIds_revert_zeroAmount() public {
        // ARRANGE
        uint256 tokenId2 = _bondFTId + 1;

        vm.prank(_brAddr);
        token.mint(_cwAddr, tokenId2, initCwBalance);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = _bondFTId;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = initCwBalance / 2;
        amounts[1] = 0;

        // ACT & ASSERT: Expect revert when amount is zero
        vm.prank(_cwAddr);
        vm.expectRevert(Errors.Token__ZeroAmount.selector);
        token.batchTransferFrom(_cwAddr, _tokenRecipient1, tokenIds, amounts);
    }

    function test_batchTransferFromMultipleTokenIds_revert_senderZeroAddress() public {
        // ARRANGE
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = _bondFTId;
        tokenIds[1] = _bondFTId + 1;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = initCwBalance / 2;
        amounts[1] = initCwBalance / 2;

        // ACT & ASSERT: Expect revert when the sender is zero address
        vm.prank(address(0));
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.batchTransferFrom(address(0), _tokenRecipient1, tokenIds, amounts);
    }

    function test_batchTransferFromMultipleTokenIds_revert_receiverZeroAddress() public {
        // ARRANGE
        uint256 tokenId2 = _bondFTId + 1;

        vm.prank(_brAddr);
        token.mint(_cwAddr, tokenId2, initCwBalance);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = _bondFTId;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = initCwBalance / 2;
        amounts[1] = initCwBalance / 2;

        // ACT & ASSERT: Expect revert when the receiver is zero address
        vm.prank(_cwAddr);
        vm.expectRevert(abi.encodeWithSelector(ERC6909Upgradeable.ERC6909InvalidReceiver.selector, address(0)));
        token.batchTransferFrom(_cwAddr, address(0), tokenIds, amounts);
    }

    function test_batchTransferFromMultipleTokenIds_revert_notOperator() public {
        // ARRANGE
        address operator = makeAddr("operator");
        _registerWallet(operator);
        uint256 tokenId2 = _bondFTId + 1;

        vm.prank(_brAddr);
        token.mint(_cwAddr, tokenId2, initCwBalance);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = _bondFTId;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = initCwBalance / 2;
        amounts[1] = initCwBalance / 2;

        // ACT & ASSERT: Expect revert when the caller is not operator
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909Upgradeable.ERC6909InsufficientAllowance.selector, operator, 0, amounts[0], tokenIds[0]
            )
        );
        token.batchTransferFrom(_cwAddr, _tokenRecipient1, tokenIds, amounts);
    }

    function test_batchTransferFromMultipleTokenIds_revert_insufficientAllowance() public {
        // ARRANGE
        address operator = makeAddr("operator");
        _registerWallet(operator);
        uint256 tokenId2 = _bondFTId + 1;
        uint256 transferAmount = initCwBalance / 2;

        vm.prank(_brAddr);
        token.mint(_cwAddr, tokenId2, initCwBalance);

        vm.startPrank(_cwAddr);
        token.approve(operator, _bondFTId, transferAmount / 2);
        token.approve(operator, tokenId2, initCwBalance);
        vm.stopPrank();

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = _bondFTId;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = transferAmount;
        amounts[1] = transferAmount;

        // ACT & ASSERT: Expect revert when the caller does not have sufficient allowance
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909Upgradeable.ERC6909InsufficientAllowance.selector,
                operator,
                transferAmount / 2,
                amounts[0],
                tokenIds[0]
            )
        );
        token.batchTransferFrom(_cwAddr, _tokenRecipient1, tokenIds, amounts);
    }

    function test_batchTransferFromMultipleTokenIds_revert_insufficientBalance() public {
        // ARRANGE
        uint256 tokenId2 = _bondFTId + 1;

        vm.prank(_brAddr);
        token.mint(_cwAddr, tokenId2, initCwBalance / 2);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = _bondFTId;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = initCwBalance / 2;
        amounts[1] = initCwBalance;

        // ACT & ASSERT: Expect revert when the sender balance is insufficient
        vm.prank(_cwAddr);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.batchTransferFrom(_cwAddr, _tokenRecipient1, tokenIds, amounts);
    }

    function test_batchTransferFromMultipleTokenIds_revert_tokenFrozen() public {
        // ARRANGE
        uint256 tokenId2 = _bondFTId + 1;
        uint256 transferAmount = initCwBalance / 2;

        vm.prank(_brAddr);
        token.mint(_cwAddr, tokenId2, initCwBalance / 4);

        // Freeze some tokens to reduce free balance, then try to transfer more than total balance
        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_cwAddr, tokenId2, initCwBalance / 8);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = _bondFTId;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = transferAmount;
        amounts[1] = transferAmount;

        // ACT & ASSERT: Expect revert when trying to transfer more than total balance
        vm.prank(_cwAddr);
        vm.expectRevert(Errors.Token__InsufficientBalance.selector);
        token.batchTransferFrom(_cwAddr, _tokenRecipient1, tokenIds, amounts);
    }

    function test_batchTransferFromMultipleTokenIds_revert_paused() public {
        // ARRANGE
        uint256 tokenId2 = _bondFTId + 1;

        vm.prank(_brAddr);
        token.mint(_cwAddr, tokenId2, initCwBalance);

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = _bondFTId;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = initCwBalance / 2;
        amounts[1] = initCwBalance / 2;

        // ACT & ASSERT: Expect revert when contract is paused
        vm.prank(_cwAddr);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.batchTransferFrom(_cwAddr, _tokenRecipient1, tokenIds, amounts);
    }

    function test_batchTransferFromMultipleTokenIds_revert_tokenIdIsPaused() public {
        // ARRANGE
        uint256 tokenId2 = _bondFTId + 1;

        vm.prank(_brAddr);
        token.mint(_cwAddr, tokenId2, initCwBalance);

        vm.prank(_brAddr);
        token.pauseTokenId(_bondFTId);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = _bondFTId;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = initCwBalance / 2;
        amounts[1] = initCwBalance / 2;

        // ACT & ASSERT: Expect revert when tokenId is paused
        vm.prank(_cwAddr);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__TokenIdIsPaused.selector, _bondFTId));
        token.batchTransferFrom(_cwAddr, _tokenRecipient1, tokenIds, amounts);
    }

    function test_batchTransferFromMultipleTokenIds_revert_transferIsNotAllowed() public {
        // ARRANGE
        uint256 tokenId2 = _bondFTId + 1;
        uint256 transferAmount = initCwBalance / 2;

        vm.prank(_brAddr);
        token.mint(_cwAddr, tokenId2, initCwBalance);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = _bondFTId;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = transferAmount;
        amounts[1] = transferAmount;

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(
                IEntityRegistry.canTransfer.selector, _cwAddr, _tokenRecipient1, _cwAddr, _bondFTId, transferAmount
            ),
            abi.encode(false)
        );

        // ACT & ASSERT: Expect revert when transfer is not allowed
        vm.prank(_cwAddr);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Token__TransferNotAllowed.selector, _cwAddr, _tokenRecipient1, _bondFTId)
        );
        token.batchTransferFrom(_cwAddr, _tokenRecipient1, tokenIds, amounts);
    }

    /*//////////////////////////////////////////////////////////////
                              balanceOfAt
    //////////////////////////////////////////////////////////////*/

    function test_balanceOfAt_success_historicalAcrossBlocks() public {
        // ARRANGE
        uint256 transferAt100 = initCwBalance / 10;
        uint256 transferAt101 = initCwBalance / 20;
        uint256 firstTransferAt200 = initCwBalance / 12;
        uint256 secondTransferAt200 = initCwBalance / 15;
        uint256 balanceAt101 = transferAt100 + transferAt101;

        vm.roll(100);
        vm.prank(_cwAddr);
        token.transfer(_tokenRecipient1, _bondFTId, transferAt100);

        vm.roll(101);
        vm.prank(_cwAddr);
        token.transfer(_tokenRecipient1, _bondFTId, transferAt101);

        // ASSERT
        assertEq(token.balanceOfAt(_tokenRecipient1, _bondFTId, 99), 0);
        assertEq(token.balanceOfAt(_tokenRecipient1, _bondFTId, 100), transferAt100);
        assertEq(token.balanceOfAt(_tokenRecipient1, _bondFTId, 101), balanceAt101);

        vm.roll(200);
        vm.startPrank(_cwAddr);
        token.transfer(_tokenRecipient1, _bondFTId, firstTransferAt200);
        token.transfer(_tokenRecipient1, _bondFTId, secondTransferAt200);
        vm.stopPrank();

        // ASSERT: same block updates should be reflected as the final value for that block
        assertEq(token.balanceOfAt(_tokenRecipient1, _bondFTId, 199), balanceAt101);
        assertEq(
            token.balanceOfAt(_tokenRecipient1, _bondFTId, 200), balanceAt101 + firstTransferAt200 + secondTransferAt200
        );
    }

    function test_balanceOfAt_revert_futureBlock() public {
        // ARRANGE
        uint256 futureBlock = block.number + 1;

        // ACT & ASSERT
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__BlockInFuture.selector, block.number, futureBlock));
        token.balanceOfAt(_cwAddr, _bondFTId, futureBlock);
    }

    /*//////////////////////////////////////////////////////////////
                              totalSupplyAt
    //////////////////////////////////////////////////////////////*/

    function test_totalSupplyAt_success_historicalAcrossBlocks() public {
        // ARRANGE
        uint256 initialSupply = token.totalSupply(_bondFTId);
        uint256 mintedAt400 = initCwBalance / 5;
        uint256 burntAt401 = initCwBalance / 10;
        uint256 mintedAt500 = initCwBalance / 4;
        uint256 burntAt500 = initCwBalance / 8;
        uint256 supplyAt401 = initialSupply + mintedAt400 - burntAt401;

        vm.roll(400);
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, mintedAt400);

        vm.roll(401);
        vm.prank(_brAddr);
        token.burn(_cwAddr, _bondFTId, burntAt401);

        // ASSERT: historical snapshots across different blocks
        assertEq(token.totalSupplyAt(_bondFTId, 399), initialSupply);
        assertEq(token.totalSupplyAt(_bondFTId, 400), initialSupply + mintedAt400);
        assertEq(token.totalSupplyAt(_bondFTId, 401), supplyAt401);

        vm.roll(500);
        vm.prank(_brAddr);
        token.mint(_cwAddr, _bondFTId, mintedAt500);
        vm.prank(_brAddr);
        token.burn(_cwAddr, _bondFTId, burntAt500);

        // ASSERT: same block updates should be reflected as the final value for that block
        assertEq(token.totalSupplyAt(_bondFTId, 499), supplyAt401);
        assertEq(token.totalSupplyAt(_bondFTId, 500), supplyAt401 + mintedAt500 - burntAt500);
    }

    function test_totalSupplyAt_revert_futureBlock() public {
        // ARRANGE
        uint256 futureBlock = block.number + 1;

        // ACT & ASSERT
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__BlockInFuture.selector, block.number, futureBlock));
        token.totalSupplyAt(_bondFTId, futureBlock);
    }

    /*//////////////////////////////////////////////////////////////
                            frozenBalanceOfAt
    //////////////////////////////////////////////////////////////*/

    function test_frozenBalanceOfAt_success_historicalAcrossBlocks() public {
        // ARRANGE
        uint256 frozenAt700 = initCwBalance / 4;
        uint256 unfreezeAt701 = initCwBalance / 10;
        uint256 firstFreezeAt800 = initCwBalance / 5;
        uint256 secondFreezeAt800 = initCwBalance / 10;
        uint256 unfreezeAt800 = initCwBalance / 20;
        uint256 frozenAt701 = frozenAt700 - unfreezeAt701;

        vm.roll(700);
        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_cwAddr, _bondFTId, frozenAt700);

        vm.roll(701);
        vm.prank(_tokenAdmin);
        token.unfreezePartialTokens(_cwAddr, _bondFTId, unfreezeAt701);

        // ASSERT: historical snapshots across different blocks
        assertEq(token.frozenBalanceOfAt(_cwAddr, _bondFTId, 699), 0);
        assertEq(token.frozenBalanceOfAt(_cwAddr, _bondFTId, 700), frozenAt700);
        assertEq(token.frozenBalanceOfAt(_cwAddr, _bondFTId, 701), frozenAt701);

        vm.roll(800);
        vm.startPrank(_tokenAdmin);
        token.freezePartialTokens(_cwAddr, _bondFTId, firstFreezeAt800);
        token.freezePartialTokens(_cwAddr, _bondFTId, secondFreezeAt800);
        token.unfreezePartialTokens(_cwAddr, _bondFTId, unfreezeAt800);
        vm.stopPrank();

        // ASSERT: same block updates should be reflected as the final value for that block
        assertEq(token.frozenBalanceOfAt(_cwAddr, _bondFTId, 799), frozenAt701);
        assertEq(
            token.frozenBalanceOfAt(_cwAddr, _bondFTId, 800),
            frozenAt701 + firstFreezeAt800 + secondFreezeAt800 - unfreezeAt800
        );
    }

    function test_frozenBalanceOfAt_revert_futureBlock() public {
        // ARRANGE
        uint256 futureBlock = block.number + 1;

        // ACT & ASSERT
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__BlockInFuture.selector, block.number, futureBlock));
        token.frozenBalanceOfAt(_cwAddr, _bondFTId, futureBlock);
    }

    /*//////////////////////////////////////////////////////////////
                           availableBalanceOfAt
    //////////////////////////////////////////////////////////////*/

    function test_availableBalanceOfAt_success_historicalAcrossBlocks() public {
        // ARRANGE
        uint256 transferInAt1000 = initCwBalance / 5;
        uint256 freezeAt1001 = initCwBalance / 10;
        uint256 transferOutAt1002 = initCwBalance / 15;
        uint256 unfreezeAt1003 = initCwBalance / 20;
        uint256 transferInAt1100 = initCwBalance / 4;
        uint256 freezeAt1100 = initCwBalance / 10;
        uint256 transferOutAt1100 = initCwBalance / 20;
        uint256 unfreezeAt1100 = initCwBalance / 50;
        uint256 availableAt1003 = transferInAt1000 - transferOutAt1002 - freezeAt1001 + unfreezeAt1003;

        vm.roll(1000);
        vm.prank(_cwAddr);
        token.transfer(_tokenRecipient1, _bondFTId, transferInAt1000);

        vm.roll(1001);
        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_tokenRecipient1, _bondFTId, freezeAt1001);

        vm.roll(1002);
        vm.prank(_tokenRecipient1);
        token.transfer(_tokenRecipient2, _bondFTId, transferOutAt1002);

        vm.roll(1003);
        vm.prank(_tokenAdmin);
        token.unfreezePartialTokens(_tokenRecipient1, _bondFTId, unfreezeAt1003);

        // ASSERT: historical snapshots across different blocks
        assertEq(token.availableBalanceOfAt(_tokenRecipient1, _bondFTId, 999), 0);
        assertEq(token.availableBalanceOfAt(_tokenRecipient1, _bondFTId, 1000), transferInAt1000);
        assertEq(token.availableBalanceOfAt(_tokenRecipient1, _bondFTId, 1001), transferInAt1000 - freezeAt1001);
        assertEq(
            token.availableBalanceOfAt(_tokenRecipient1, _bondFTId, 1002),
            transferInAt1000 - transferOutAt1002 - freezeAt1001
        );
        assertEq(token.availableBalanceOfAt(_tokenRecipient1, _bondFTId, 1003), availableAt1003);

        vm.roll(1100);
        vm.prank(_cwAddr);
        token.transfer(_tokenRecipient1, _bondFTId, transferInAt1100);
        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_tokenRecipient1, _bondFTId, freezeAt1100);
        vm.prank(_tokenRecipient1);
        token.transfer(_tokenRecipient2, _bondFTId, transferOutAt1100);
        vm.prank(_tokenAdmin);
        token.unfreezePartialTokens(_tokenRecipient1, _bondFTId, unfreezeAt1100);

        // ASSERT: same block updates should be reflected as the final value for that block
        assertEq(token.availableBalanceOfAt(_tokenRecipient1, _bondFTId, 1099), availableAt1003);
        assertEq(
            token.availableBalanceOfAt(_tokenRecipient1, _bondFTId, 1100),
            availableAt1003 + transferInAt1100 - transferOutAt1100 - freezeAt1100 + unfreezeAt1100
        );
    }

    function test_availableBalanceOfAt_revert_futureBlock() public {
        // ARRANGE
        uint256 futureBlock = block.number + 1;

        // ACT & ASSERT
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__BlockInFuture.selector, block.number, futureBlock));
        token.availableBalanceOfAt(_cwAddr, _bondFTId, futureBlock);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function test_version() public view {
        assertEq(token.version(), "1.0.0");
    }

    function test_supportsInterface() public view {
        assertTrue(token.supportsInterface(type(IBaseToken).interfaceId));
        assertTrue(token.supportsInterface(type(IDEUSSToken).interfaceId));
        assertTrue(token.supportsInterface(type(IERC6909).interfaceId));
        assertTrue(token.supportsInterface(type(IERC165).interfaceId));
    }
}
