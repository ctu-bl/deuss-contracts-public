// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Initializable} from "solady/src/utils/Initializable.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";
import {AssetManager} from "src/marketplace/AssetManager.sol";
import {AssetType} from "src/marketplace/MarketStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {IAssetManager} from "src/marketplace/interfaces/IAssetManager.sol";
import {IAssetValidator} from "src/marketplace/interfaces/IAssetValidator.sol";
import {MockAssetValidator} from "test/mocks/MockContracts.sol";
import {StorageLayoutHelpers} from "test/fixtures/StorageLayoutHelpers.t.sol";

contract MockAssetManagerV2 is AssetManager {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract AssetManagerStorageHarness is AssetManager {
    function exposedAssetManagerStorageLocation() external pure returns (bytes32) {
        return _ASSET_MANAGER_STORAGE_LOCATION;
    }
}

contract AssetManagerTest is StorageLayoutHelpers {
    AssetManager internal _assetManager;
    UpgradeableBeacon internal _assetManagerBeacon;
    address internal _owner;
    address internal _admin;
    address internal _outsider;
    address internal _token;

    function setUp() public {
        _owner = makeAddr("owner");
        _admin = makeAddr("admin");
        _outsider = makeAddr("outsider");
        _token = makeAddr("token");

        (_assetManager, _assetManagerBeacon) = _deployAssetManager(_owner);

        uint256 adminRole = _assetManager.ADMIN();
        vm.prank(_assetManager.owner());
        _assetManager.grantRoles(_admin, adminRole);
    }

    /*//////////////////////////////////////////////////////////////
                                initialize
    //////////////////////////////////////////////////////////////*/
    function test_initialize_setsOwner_withoutGrantingAdminRole() public view {
        assertEq(_assetManager.owner(), _owner);
        assertFalse(_assetManager.hasAnyRole(_owner, _assetManager.ADMIN()));
    }

    function test_initialize_reverts_reinitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        _assetManager.initialize(_owner);
    }

    /*//////////////////////////////////////////////////////////////
                                deployment
    //////////////////////////////////////////////////////////////*/
    function test_deployment_reverts_zeroOwner() public {
        AssetManager implementation = new AssetManager();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), _owner);
        bytes memory initData = abi.encodeWithSelector(AssetManager.initialize.selector, address(0));

        vm.expectRevert(Errors.ZeroAddress.selector);
        new BeaconProxy(address(beacon), initData);
    }

    function test_deployment_success_addressesAreUnique() public {
        (AssetManager secondAssetManager,) = _deployAssetManager(_owner);

        assertNotEq(address(_assetManager), address(secondAssetManager));
    }

    function test_deployment_success_deployedAddressIsNonZero() public {
        (AssetManager secondAssetManager,) = _deployAssetManager(_owner);

        assertNotEq(address(secondAssetManager), address(0));
    }

    function test_deployment_success_roleStateMatchesDefaultBehavior() public {
        (AssetManager secondAssetManager,) = _deployAssetManager(_outsider);

        assertEq(secondAssetManager.owner(), _outsider);
        assertFalse(secondAssetManager.hasAnyRole(_outsider, secondAssetManager.ADMIN()));
    }

    function test_namespacedStorageLocation_success_matchesErc7201Formula() public {
        AssetManagerStorageHarness harness = new AssetManagerStorageHarness();
        bytes32 storageLocation = harness.exposedAssetManagerStorageLocation();

        assertEq(storageLocation, _erc7201Location("deuss.assetManager.storage"));
        assertEq(uint256(storageLocation) & 0xff, 0);
    }

    /*//////////////////////////////////////////////////////////////
                                upgradeTo
    //////////////////////////////////////////////////////////////*/
    function test_upgradeTo_success_beaconOwner() public {
        MockAssetManagerV2 newImplementation = new MockAssetManagerV2();

        vm.prank(_owner);
        _assetManagerBeacon.upgradeTo(address(newImplementation));

        assertEq(MockAssetManagerV2(address(_assetManager)).version(), 2);
    }

    function test_upgradeTo_reverts_notBeaconOwner() public {
        MockAssetManagerV2 newImplementation = new MockAssetManagerV2();

        vm.prank(_outsider);
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableUnauthorizedAccount.selector, _outsider));
        _assetManagerBeacon.upgradeTo(address(newImplementation));
    }

    /*//////////////////////////////////////////////////////////////
                                setAsset
    //////////////////////////////////////////////////////////////*/
    function test_setAsset_success() public {
        vm.expectEmit(true, true, true, true);
        emit IAssetManager.AssetConfigured(_token, AssetType.ERC20, true, false);

        vm.prank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC20, true, false);

        (AssetType assetType, bool enabled, bool enforceTokenId) = _assetManager.getAssetConfig(_token);
        assertEq(uint8(assetType), uint8(AssetType.ERC20));
        assertTrue(enabled);
        assertFalse(enforceTokenId);
    }

    function test_setAsset_success_disableAsset() public {
        vm.startPrank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC20, true, false);
        _assetManager.setAsset(_token, AssetType.NONE, false, false);
        vm.stopPrank();

        (AssetType assetType, bool enabled, bool enforceTokenId) = _assetManager.getAssetConfig(_token);
        assertEq(uint8(assetType), uint8(AssetType.NONE));
        assertFalse(enabled);
        assertFalse(enforceTokenId);
    }

    function test_setAsset_reverts_zeroToken() public {
        vm.prank(_admin);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _assetManager.setAsset(address(0), AssetType.ERC20, true, false);
    }

    function test_setAsset_reverts_invalidTypeWhenEnabled() public {
        vm.prank(_admin);
        vm.expectRevert(Errors.AssetManager__InvalidAssetType.selector);
        _assetManager.setAsset(_token, AssetType.NONE, true, false);
    }

    function test_setAsset_reverts_notAdmin() public {
        vm.prank(_outsider);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _assetManager.setAsset(_token, AssetType.ERC20, true, false);
    }

    /*//////////////////////////////////////////////////////////////
                             setAssetTokenId
    //////////////////////////////////////////////////////////////*/
    function test_setAssetTokenId_success() public {
        vm.startPrank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC1155, true, true);
        vm.expectEmit(true, true, true, true);
        emit IAssetManager.AssetTokenIdConfigured(_token, 42, true);
        _assetManager.setAssetTokenId(_token, 42, true);
        vm.stopPrank();

        assertTrue(_assetManager.isTokenIdAllowed(_token, 42));
        bytes32 storageLocation = _erc7201Location("deuss.assetManager.storage");
        bytes32 assetConfigSlot = keccak256(abi.encode(_token, storageLocation));
        bytes32 tokenAllowlistSlot = keccak256(abi.encode(_token, _slotOffset(storageLocation, 1)));
        bytes32 tokenIdSlot = keccak256(abi.encode(uint256(42), tokenAllowlistSlot));

        assertTrue(vm.load(address(_assetManager), assetConfigSlot) != bytes32(0));
        assertEq(vm.load(address(_assetManager), tokenIdSlot), bytes32(uint256(1)));
    }

    function test_setAssetTokenId_reverts_assetNotSupported() public {
        vm.prank(_admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.AssetManager__AssetNotSupported.selector, _token, 1));
        _assetManager.setAssetTokenId(_token, 1, true);
    }

    function test_setAssetTokenId_reverts_tokenAllowlistDisabled() public {
        vm.prank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC1155, true, false);

        vm.prank(_admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.AssetManager__TokenIdAllowlistDisabled.selector, _token));
        _assetManager.setAssetTokenId(_token, 7, true);
    }

    function test_setAssetTokenId_reverts_notAdmin() public {
        vm.prank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC1155, true, true);

        vm.prank(_outsider);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _assetManager.setAssetTokenId(_token, 7, true);
    }

    /*//////////////////////////////////////////////////////////////
                              setAssetValidator
    //////////////////////////////////////////////////////////////*/
    function test_setAssetValidator_success() public {
        MockAssetValidator validator = new MockAssetValidator();

        vm.prank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC6909, true, false);

        vm.expectEmit(true, true, true, true);
        emit IAssetManager.AssetValidatorConfigured(_token, address(validator));

        vm.prank(_admin);
        _assetManager.setAssetValidator(_token, address(validator));

        assertEq(_assetManager.getAssetValidator(_token), address(validator));
    }

    function test_setAssetValidator_success_clearValidator() public {
        MockAssetValidator validator = new MockAssetValidator();

        vm.startPrank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC6909, true, false);
        _assetManager.setAssetValidator(_token, address(validator));

        vm.expectEmit(true, true, true, true);
        emit IAssetManager.AssetValidatorConfigured(_token, address(0));
        _assetManager.setAssetValidator(_token, address(0));
        vm.stopPrank();

        assertEq(_assetManager.getAssetValidator(_token), address(0));
    }

    function test_setAssetValidator_reverts_assetNotSupported() public {
        MockAssetValidator validator = new MockAssetValidator();

        vm.prank(_admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.AssetManager__AssetNotSupported.selector, _token, 0));
        _assetManager.setAssetValidator(_token, address(validator));
    }

    function test_setAssetValidator_reverts_notAdmin() public {
        MockAssetValidator validator = new MockAssetValidator();

        vm.prank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC6909, true, false);

        vm.prank(_outsider);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _assetManager.setAssetValidator(_token, address(validator));
    }

    /*//////////////////////////////////////////////////////////////
                              validateAsset
    //////////////////////////////////////////////////////////////*/
    function test_validateAsset_reverts_assetNotSupported() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AssetManager__AssetNotSupported.selector, _token, 0));
        _assetManager.validateAsset(_token, 0, 1);
    }

    function test_validateAsset_reverts_tokenIdNotSupported_whenEnforced() public {
        vm.prank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC1155, true, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.AssetManager__TokenIdNotSupported.selector, _token, 99));
        _assetManager.validateAsset(_token, 99, 5);
    }

    function test_validateAsset_success_tokenIdSupported_whenEnforced() public {
        vm.startPrank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC1155, true, true);
        _assetManager.setAssetTokenId(_token, 99, true);
        vm.stopPrank();

        AssetType assetType = _assetManager.validateAsset(_token, 99, 5);
        assertEq(uint8(assetType), uint8(AssetType.ERC1155));
    }

    function test_validateAsset_reverts_invalidTokenIdForERC20() public {
        vm.prank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC20, true, false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AssetManager__InvalidTokenId.selector, 1));
        _assetManager.validateAsset(_token, 1, 5);
    }

    function test_validateAsset_returnsERC20() public {
        vm.prank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC20, true, false);

        AssetType assetType = _assetManager.validateAsset(_token, 0, 5);
        assertEq(uint8(assetType), uint8(AssetType.ERC20));
    }

    function test_validateAsset_reverts_invalidAmountForERC721() public {
        vm.prank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC721, true, false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AssetManager__InvalidAmountForERC721.selector, 2));
        _assetManager.validateAsset(_token, 77, 2);
    }

    function test_validateAsset_returnsERC721() public {
        vm.prank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC721, true, false);

        AssetType assetType = _assetManager.validateAsset(_token, 77, 1);
        assertEq(uint8(assetType), uint8(AssetType.ERC721));
    }

    function test_validateAsset_returnsERC1155() public {
        vm.prank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC1155, true, false);

        AssetType assetType = _assetManager.validateAsset(_token, 7, 5);
        assertEq(uint8(assetType), uint8(AssetType.ERC1155));
    }

    function test_validateAsset_returnsERC6909() public {
        vm.prank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC6909, true, false);

        AssetType assetType = _assetManager.validateAsset(_token, 7, 5);
        assertEq(uint8(assetType), uint8(AssetType.ERC6909));
    }

    function test_validateAsset_success_invokesValidator() public {
        MockAssetValidator validator = new MockAssetValidator();

        vm.startPrank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC6909, true, false);
        _assetManager.setAssetValidator(_token, address(validator));
        vm.stopPrank();

        vm.expectCall(address(validator), abi.encodeCall(IAssetValidator.validate, (_token, 7, 5)));
        AssetType assetType = _assetManager.validateAsset(_token, 7, 5);

        assertEq(uint8(assetType), uint8(AssetType.ERC6909));
    }

    function test_validateAsset_reverts_whenValidatorReverts() public {
        MockAssetValidator validator = new MockAssetValidator();

        vm.startPrank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC6909, true, false);
        _assetManager.setAssetValidator(_token, address(validator));
        vm.stopPrank();

        validator.setShouldRevert(true);

        vm.expectRevert(MockAssetValidator.MockAssetValidator__Rejected.selector);
        _assetManager.validateAsset(_token, 7, 5);
    }

    function test_validateAsset_reverts_staticValidationBeforeValidator() public {
        MockAssetValidator validator = new MockAssetValidator();

        vm.startPrank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC20, true, false);
        _assetManager.setAssetValidator(_token, address(validator));
        vm.stopPrank();

        validator.setShouldRevert(true);

        vm.expectRevert(abi.encodeWithSelector(Errors.AssetManager__InvalidTokenId.selector, 1));
        _assetManager.validateAsset(_token, 1, 5);
    }

    /*//////////////////////////////////////////////////////////////
                            isAssetSupported
    //////////////////////////////////////////////////////////////*/
    function test_isAssetSupported_false_whenDisabled() public view {
        assertFalse(_assetManager.isAssetSupported(_token, 1));
    }

    function test_isAssetSupported_true_whenEnabledWithoutTokenAllowlist() public {
        vm.prank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC1155, true, false);

        assertTrue(_assetManager.isAssetSupported(_token, 999));
    }

    function test_isAssetSupported_false_whenTokenAllowlistEnabledButNotAllowed() public {
        vm.prank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC1155, true, true);

        assertFalse(_assetManager.isAssetSupported(_token, 999));
    }

    function test_isAssetSupported_true_whenTokenAllowlistEnabledAndAllowed() public {
        vm.startPrank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC1155, true, true);
        _assetManager.setAssetTokenId(_token, 999, true);
        vm.stopPrank();

        assertTrue(_assetManager.isAssetSupported(_token, 999));
    }

    function test_isAssetSupported_success_ignoresValidator() public {
        MockAssetValidator validator = new MockAssetValidator();
        validator.setShouldRevert(true);

        vm.startPrank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC6909, true, false);
        _assetManager.setAssetValidator(_token, address(validator));
        vm.stopPrank();

        assertTrue(_assetManager.isAssetSupported(_token, 7));
    }

    /*//////////////////////////////////////////////////////////////
                                getAssetType
    //////////////////////////////////////////////////////////////*/
    function test_getAssetType_reverts_assetNotSupported() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AssetManager__AssetNotSupported.selector, _token, 0));
        _assetManager.getAssetType(_token);
    }

    function test_getAssetType_success() public {
        vm.prank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC1155, true, false);

        AssetType assetType = _assetManager.getAssetType(_token);
        assertEq(uint8(assetType), uint8(AssetType.ERC1155));
    }

    /*//////////////////////////////////////////////////////////////
                                getAssetConfig
    //////////////////////////////////////////////////////////////*/
    function test_getAssetConfig_defaultValuesForUnknownToken() public view {
        (AssetType assetType, bool enabled, bool enforceTokenId) = _assetManager.getAssetConfig(_token);
        assertEq(uint8(assetType), uint8(AssetType.NONE));
        assertFalse(enabled);
        assertFalse(enforceTokenId);
    }

    /*//////////////////////////////////////////////////////////////
                              isTokenIdAllowed
    //////////////////////////////////////////////////////////////*/
    function test_isTokenIdAllowed_defaultFalse_thenTrueAfterConfig() public {
        assertFalse(_assetManager.isTokenIdAllowed(_token, 1));

        vm.startPrank(_admin);
        _assetManager.setAsset(_token, AssetType.ERC1155, true, true);
        _assetManager.setAssetTokenId(_token, 1, true);
        vm.stopPrank();

        assertTrue(_assetManager.isTokenIdAllowed(_token, 1));
    }

    /*//////////////////////////////////////////////////////////////
                                grantRoles
    //////////////////////////////////////////////////////////////*/
    function test_owner_canGrantAdminRoleToAnotherAddress() public {
        uint256 adminRole = _assetManager.ADMIN();

        vm.prank(_owner);
        _assetManager.grantRoles(_outsider, adminRole);

        vm.prank(_outsider);
        _assetManager.setAsset(_token, AssetType.ERC20, true, false);

        assertTrue(_assetManager.isAssetSupported(_token, 0));
    }

    function _deployAssetManager(address owner_)
        internal
        returns (AssetManager assetManager_, UpgradeableBeacon beacon_)
    {
        AssetManager implementation = new AssetManager();
        beacon_ = new UpgradeableBeacon(address(implementation), owner_);
        bytes memory initData = abi.encodeWithSelector(AssetManager.initialize.selector, owner_);
        assetManager_ = AssetManager(address(new BeaconProxy(address(beacon_), initData)));
    }
}
