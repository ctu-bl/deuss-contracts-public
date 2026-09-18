// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {console2} from "forge-std/Test.sol";
// dependencies
import {ERC6909Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC6909/ERC6909Upgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {OwnableRoles} from "src/utils/OwnableRolesExtension.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {BondRegistry} from "src/registry/BondRegistry.sol";
import {
    BondInput,
    Bond,
    BondStatus,
    BurnKind,
    CouponFrequency,
    CouponRateType,
    CouponRates,
    Scoring,
    Tranche
} from "src/registry/BondStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {StringExtensions} from "src/libs/StringExtensions.sol";
import {IBondRegistry} from "src/registry/interfaces/IBondRegistry.sol";
import {IEntityRegistry} from "src/registry/interfaces/IEntityRegistry.sol";
import {AccountStatus} from "src/registry/EntityStructs.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";
import {DEUSSToken} from "src/token/fungible/DEUSSToken.sol";
import {IBaseToken} from "src/token/base/IBaseToken.sol";
import {MockDEUSSToken} from "test/mocks/MockContracts.sol";
// scripts and test files
import {FTFixture} from "test/fixtures/FTFixture.t.sol";
import {MockBondRegistry} from "test/mocks/MockContracts.sol";

contract MockTokenRevertsOnSupportsInterface {
    error SupportsInterfaceReverted();

    function supportsInterface(bytes4) external pure returns (bool) {
        revert SupportsInterfaceReverted();
    }
}

contract MockTokenRevertsOnBondRegistry {
    error BondRegistryReverted();

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IBaseToken).interfaceId;
    }

    function bondRegistry() external pure returns (IBondRegistry) {
        revert BondRegistryReverted();
    }
}

contract BondRegistryStorageHarness is BondRegistry {
    function exposedBondRegistryStorageLocation() external pure returns (bytes32) {
        return _BOND_REGISTRY_STORAGE_LOCATION;
    }
}

contract BondRegistryTest is FTFixture {
    using StringExtensions for string;

    uint8 public constant INITIAL_VERSION = 1;

    address private _cancelOperator = makeAddr("cancelOperator");
    address private _closeOperator = makeAddr("closeOperator");
    address private _currencyOperator = makeAddr("currencyOperator");
    address private _suspendOperator = makeAddr("suspendOperator");
    address private _unsuspendOperator = makeAddr("unsuspendOperator");
    address private _issuerRecoveryOperator = makeAddr("issuerRecoveryOperator");

    BondInput private _newBondFT;
    BondInput private _nonExistentBond;

    uint256 private _newBondFTId;

    function _grantBondRegistryRoles(address user, uint256 roles) internal {
        _grantRoles(_brAddr, user, roles);
    }

    function _grantBondRegistryBurner(address user) internal {
        _grantBondRegistryRoles(user, _br.BURNER());
    }

    function _grantEnabledBondRegistryBurner(address user) internal {
        _registerWallet(user);
        _grantBondRegistryBurner(user);
    }

    function _bondBaseSlot(bytes12 isinBytes, uint8 version) internal pure returns (bytes32) {
        bytes32 outerSlot = keccak256(abi.encode(bytes32(isinBytes), _slotOffset(_bondRegistryStorageRoot(), 1)));
        return keccak256(abi.encode(uint256(version), uint256(outerSlot)));
    }

    function _bondRegistryStorageRoot() internal pure returns (bytes32) {
        return _erc7201Location("deuss.bondRegistry.storage");
    }

    function _setBondStatus(bytes12 isinBytes, uint8 version, BondStatus status_) internal {
        bytes32 headerSlot = bytes32(uint256(_bondBaseSlot(isinBytes, version)) + 1);
        uint256 header = uint256(vm.load(_brAddr, headerSlot));
        uint256 shift = 20 * 8;
        header = (header & ~(uint256(0xFF) << shift)) | (uint256(uint8(status_)) << shift);
        vm.store(_brAddr, headerSlot, bytes32(header));
    }

    function _setBondTrancheCount(bytes12 isinBytes, uint8 version, uint16 trancheCount_) internal {
        bytes32 headerSlot = bytes32(uint256(_bondBaseSlot(isinBytes, version)) + 1);
        uint256 header = uint256(vm.load(_brAddr, headerSlot));
        uint256 trancheCountMask = uint256(type(uint16).max) << 176;
        header = (header & ~trancheCountMask) | (uint256(trancheCount_) << 176);
        vm.store(_brAddr, headerSlot, bytes32(header));
    }

    function _invalidBondRegistryRoleBit() internal view returns (uint256) {
        return _br.ISSUER_RECOVERY() << 1;
    }

    function _scoringOperator() internal returns (address operator) {
        operator = makeAddr("scoringOperator");
        _grantBondRegistryRoles(operator, _br.SCORING());
    }

    function _defaultScoring() internal pure returns (Scoring memory) {
        return Scoring({
            defaultProbabilityBps: 500,
            issueDate: 1_000_000,
            expirationDate: 2_000_000,
            // forge-lint: disable-next-line(unsafe-typecast)
            distributorId: bytes32("distributor1")
        });
    }

    function setUp() public override {
        super.setUp();
        console2.log("Proxy Bond Registry:", _brAddr);

        string memory newISIN = "SK0001002060";

        _newBondFT = _bondFT;
        _newBondFT.isin = newISIN;

        _newBondFT.maturityDate = 2 * _newBondFT.maturityDate;

        _nonExistentBond.isin = newISIN;

        _newBondFTId = uint256(keccak256(abi.encodePacked(newISIN._isinToBytes12(), uint8(1))));

        _grantBondRegistryRoles(_cancelOperator, _br.CANCEL());
        _grantBondRegistryRoles(_closeOperator, _br.CLOSE());
        _grantBondRegistryRoles(_currencyOperator, _br.CURRENCY());
        _grantBondRegistryRoles(_suspendOperator, _br.SUSPEND());
        _grantBondRegistryRoles(_unsuspendOperator, _br.UNSUSPEND());
        _grantBondRegistryRoles(_issuerRecoveryOperator, _br.ISSUER_RECOVERY());
    }

    function test_initialState() public view {
        assertEq(Ownable(_brAddr).owner(), _timelockController);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC-7201 NAMESPACED STORAGE
    //////////////////////////////////////////////////////////////*/

    function test_namespacedStorageLocation_success_matchesErc7201Formula() public {
        BondRegistryStorageHarness harness = new BondRegistryStorageHarness();
        bytes32 storageLocation = harness.exposedBondRegistryStorageLocation();

        assertEq(storageLocation, _erc7201Location("deuss.bondRegistry.storage"));
        assertEq(uint256(storageLocation) & 0xff, 0);
    }

    function test_namespacedState_success_usesErc7201Storage() public view {
        // `token` is field offset 0, so it shares the namespace root slot.
        assertEq(address(uint160(uint256(vm.load(_brAddr, _bondRegistryStorageRoot())))), _br.getToken());

        // `bonds` is field offset 1; the fixture bond (version 1) is stored under the namespaced slot.
        bytes32 bondSlot = _bondBaseSlot(_bondFT.isin._isinToBytes12(), INITIAL_VERSION);
        assertTrue(vm.load(_brAddr, bondSlot) != bytes32(0));

        // Isolation: the pre-namespace sequential slot (1) derivation for the same bond holds nothing.
        bytes32 legacyOuter = keccak256(abi.encode(bytes32(_bondFT.isin._isinToBytes12()), uint256(1)));
        bytes32 legacyBondSlot = keccak256(abi.encode(uint256(INITIAL_VERSION), uint256(legacyOuter)));
        assertEq(vm.load(_brAddr, legacyBondSlot), bytes32(0));
    }

    function test_initialize_zeroOwner_fallsBackToMsgSender() public {
        BondRegistry implementation = new BondRegistry();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), address(this));
        address initializer = makeAddr("initializer");
        bytes memory initData = abi.encodeWithSelector(BondRegistry.initialize.selector, address(0));

        vm.prank(initializer);
        BondRegistry registry = BondRegistry(address(new BeaconProxy(address(beacon), initData)));

        assertEq(Ownable(address(registry)).owner(), initializer);
    }

    /*//////////////////////////////////////////////////////////////
                              upgradeTo
    //////////////////////////////////////////////////////////////*/
    function test_upgradeTo_success_beaconOwner() public {
        address newImpl = address(new MockBondRegistry());

        _timelockOp(address(_brBeacon), abi.encodeWithSelector(_brBeacon.upgradeTo.selector, newImpl));

        assertEq(MockBondRegistry(_brAddr).VERSION(), 2);
        assertTrue(MockBondRegistry(_brAddr).isNewVersion());
    }

    function test_upgradeTo_reverts_notBeaconOwner() public {
        address newImpl = address(new MockBondRegistry());

        vm.prank(_notGov);
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableUnauthorizedAccount.selector, _notGov));
        _brBeacon.upgradeTo(newImpl);
    }

    function test_beaconDowngrade_success() public {
        address originalImpl = _brBeacon.implementation();

        address newImpl = address(new MockBondRegistry());
        _timelockOp(address(_brBeacon), abi.encodeWithSelector(_brBeacon.upgradeTo.selector, newImpl));
        assertEq(_brBeacon.implementation(), newImpl);

        _timelockOp(address(_brBeacon), abi.encodeWithSelector(_brBeacon.upgradeTo.selector, originalImpl));
        assertEq(_brBeacon.implementation(), originalImpl);
    }

    /*//////////////////////////////////////////////////////////////
                            setMultiToken
    //////////////////////////////////////////////////////////////*/
    function test_setMultiToken_success() public {
        // Fixture deployment already configures and locks the token contract.
        // Clear only the lock flag to exercise the success path. `token`/`multiTokenLocked` are packed
        // at field offset 0 of the bond-registry namespace, so the packed slot is the namespace root.
        bytes32 tokenAndLockSlot = _bondRegistryStorageRoot();
        uint256 packedTokenAndLock = uint256(vm.load(_brAddr, tokenAndLockSlot));
        uint256 lockByteMask = uint256(0xff) << 160;
        vm.store(_brAddr, tokenAndLockSlot, bytes32(packedTokenAndLock & ~lockByteMask));

        // ACT
        _timelockOp(_brAddr, abi.encodeWithSelector(IBondRegistry.setMultiToken.selector, _tokenAddr));

        // ASSERT
        assertEq(_br.getToken(), _tokenAddr);
    }

    function test_setMultiToken_revert_unauthorizedCaller() public {
        vm.prank(_notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.setMultiToken(_tokenAddr);
    }

    function test_setMultiToken_revert_allRolesHolderCannotCallOwnerFunction() public {
        address roleHolder = makeAddr("allRolesHolder");
        _grantBondRegistryRoles(roleHolder, _br.ALL_BR_ROLES());

        vm.prank(roleHolder);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.setMultiToken(_tokenAddr);
    }

    function test_setMultiToken_revert_zeroAddress() public {
        bytes memory data = abi.encodeWithSelector(IBondRegistry.setMultiToken.selector, address(0));
        _timelockSchedule(_brAddr, data);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _timelockExecute(_brAddr, data);
    }

    function test_setMultiToken_revert_wrongBondRegistry() public {
        // ARRANGE: Mock bondRegistry() on the token to return a different address
        vm.mockCall(_tokenAddr, abi.encodeWithSelector(IBaseToken.bondRegistry.selector), abi.encode(address(0)));

        // ACT & ASSERT: Expect revert when token's bondRegistry is not this registry
        bytes memory data = abi.encodeWithSelector(IBondRegistry.setMultiToken.selector, _tokenAddr);
        _timelockSchedule(_brAddr, data);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidMultiToken.selector, _tokenAddr));
        _timelockExecute(_brAddr, data);
    }

    function test_setMultiToken_revert_missingIBaseTokenInterfaceSupport() public {
        // ARRANGE: Mock supportsInterface(IBaseToken) to return false
        vm.mockCall(
            _tokenAddr,
            abi.encodeWithSelector(IERC165.supportsInterface.selector, type(IBaseToken).interfaceId),
            abi.encode(false)
        );

        // ACT & ASSERT
        bytes memory data = abi.encodeWithSelector(IBondRegistry.setMultiToken.selector, _tokenAddr);
        _timelockSchedule(_brAddr, data);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidMultiToken.selector, _tokenAddr));
        _timelockExecute(_brAddr, data);
    }

    function test_setMultiToken_revert_supportsInterfaceCallReverts() public {
        // ARRANGE
        MockTokenRevertsOnSupportsInterface badToken = new MockTokenRevertsOnSupportsInterface();
        vm.etch(_tokenAddr, address(badToken).code);

        // ACT & ASSERT
        bytes memory data1 = abi.encodeWithSelector(IBondRegistry.setMultiToken.selector, _tokenAddr);
        _timelockSchedule(_brAddr, data1);
        vm.expectRevert();
        _timelockExecute(_brAddr, data1);
    }

    function test_setMultiToken_revert_bondRegistryCallReverts() public {
        // ARRANGE
        MockTokenRevertsOnBondRegistry badToken = new MockTokenRevertsOnBondRegistry();
        vm.etch(_tokenAddr, address(badToken).code);

        // ACT & ASSERT
        bytes memory data2 = abi.encodeWithSelector(IBondRegistry.setMultiToken.selector, _tokenAddr);
        _timelockSchedule(_brAddr, data2);
        vm.expectRevert();
        _timelockExecute(_brAddr, data2);
    }

    function test_setMultiToken_revert_changeAfterBondIssued() public {
        // ARRANGE: Deploy another valid token proxy bound to the same BR/ER.
        UpgradeableBeacon otherTokenBeacon = new UpgradeableBeacon(address(new MockDEUSSToken()), _deployer);
        BeaconProxy otherToken = new BeaconProxy(
            address(otherTokenBeacon),
            abi.encodeWithSelector(DEUSSToken.initialize.selector, _deployer, _brAddr, _erAddr, _escrowManager)
        );

        // ACT & ASSERT: Any issued bond locks the shared token pointer against rebinding
        bytes memory data = abi.encodeWithSelector(IBondRegistry.setMultiToken.selector, address(otherToken));
        _timelockSchedule(_brAddr, data);
        vm.expectRevert(Errors.BondRegistry__MultiTokenLocked.selector);
        _timelockExecute(_brAddr, data);
    }

    /*//////////////////////////////////////////////////////////////
                                closeBond
    //////////////////////////////////////////////////////////////*/
    function test_closeBond_success() public {
        // ARRANGE: Burn all issued tokens so total supply is zero
        uint256 supply = IDEUSSToken(_tokenAddr).totalSupply(_bondFTId);
        vm.prank(_brAddr);
        IDEUSSToken(_tokenAddr).burn(_cwAddr, _bondFTId, supply);

        // ACT
        vm.prank(_closeOperator);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.BondRedeemed(_bondFT.isin._isinToBytes12(), INITIAL_VERSION, _closeOperator);
        _br.closeBond(_bondFT.isin, 1);

        assertEq(uint256(_br.bondStatus(_bondFT.isin)), uint256(BondStatus.Redeemed));
    }

    function test_closeBond_success_unpausesTokenIdWhenClosingFromSuspended() public {
        // ARRANGE: suspend the bond, which pauses its tokenId
        _grantBondRegistryRoles(_closeOperator, _br.SUSPEND());
        vm.prank(_closeOperator);
        _br.suspendBond(_bondFT.isin, 1);
        assertEq(uint256(_br.bondStatus(_bondFT.isin)), uint256(BondStatus.Suspended));
        assertTrue(IBaseToken(_tokenAddr).isTokenPaused(_bondFTId));

        // ARRANGE: Burn all supply to zero so the suspended bond becomes closeable
        uint256 supply = IDEUSSToken(_tokenAddr).totalSupply(_bondFTId);
        vm.prank(_brAddr);
        IDEUSSToken(_tokenAddr).burn(_cwAddr, _bondFTId, supply);

        // ACT: close from Suspended -> Redeemed
        vm.prank(_closeOperator);
        _br.closeBond(_bondFT.isin, 1);

        // ASSERT: terminal Redeemed status and the tokenId is no longer paused
        assertEq(uint256(_br.bondStatus(_bondFT.isin)), uint256(BondStatus.Redeemed));
        assertFalse(IBaseToken(_tokenAddr).isTokenPaused(_bondFTId));
    }

    function test_closeBond_revert_unauthorizedCaller() public {
        // ACT & ASSERT: Expect revert when caller does not have `CLOSE`
        vm.prank(_notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.closeBond(_bondFT.isin, 1);
    }

    function test_closeBond_revert_wrongAuthorizedRole() public {
        uint256 supply = IDEUSSToken(_tokenAddr).totalSupply(_bondFTId);
        vm.prank(_brAddr);
        IDEUSSToken(_tokenAddr).burn(_cwAddr, _bondFTId, supply);

        vm.prank(_publisher);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.closeBond(_bondFT.isin, 1);
    }

    function test_closeBond_revert_NonExistentBond() public {
        // ACT & ASSERT: Expect revert when bond does not exist
        vm.prank(_closeOperator);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, _newBondFT.isin._isinToBytes12())
        );
        _br.closeBond(_newBondFT.isin, 1);
    }

    function test_closeBond_revert_bondNotIssued() public {
        // ARRANGE: Publish a new bond but don't issue it
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        // ACT & ASSERT: Expect revert when the bond is not issued
        vm.prank(_closeOperator);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, _newBondFT.isin._isinToBytes12())
        );
        _br.closeBond(_newBondFT.isin, 1);
    }

    function test_closeBond_revert_bondAlreadyRedeemed() public {
        // ARRANGE: Burn all issued tokens so the first closeBond can succeed
        uint256 supply = IDEUSSToken(_tokenAddr).totalSupply(_bondFTId);
        vm.prank(_brAddr);
        IDEUSSToken(_tokenAddr).burn(_cwAddr, _bondFTId, supply);

        // ACT & ASSERT: Expect revert when the bond was already closed
        vm.startPrank(_closeOperator);
        _br.closeBond(_bondFT.isin, 1);
        // After first closeBond, status is Redeemed, which fails the closeable-status check
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, _bondFT.isin._isinToBytes12())
        );
        _br.closeBond(_bondFT.isin, 1);
        vm.stopPrank();
    }

    function test_closeBond_revert_totalSupplyNotZero() public {
        // ACT & ASSERT: Expect revert when total supply is not zero (tokens still in circulation)
        vm.prank(_closeOperator);
        vm.expectRevert(Errors.BondRegistry__TotalSupplyNotZero.selector);
        _br.closeBond(_bondFT.isin, 1);
    }

    function test_closeBond_revert_activeVersionWithPendingSuccessor() public {
        bytes12 isinBytes = _bondFT.isin._isinToBytes12();

        vm.prank(_publisher);
        _br.publishBond(_bondFT);

        uint256 supply = IDEUSSToken(_tokenAddr).totalSupply(_bondFTId);
        vm.prank(_brAddr);
        IDEUSSToken(_tokenAddr).burn(_cwAddr, _bondFTId, supply);

        vm.prank(_closeOperator);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__SuccessorAlreadyPublished.selector, isinBytes));
        _br.closeBond(_bondFT.isin, 1);

        Bond memory oldBond = _br.getBondAtVersion(isinBytes, 1);
        Bond memory successorBond = _br.getBondAtVersion(isinBytes, 2);

        assertEq(_br.getActiveVersion(isinBytes), 1);
        assertEq(_br.getLatestVersion(isinBytes), 2);
        assertEq(uint8(oldBond.status), uint8(BondStatus.Issued));
        assertEq(uint8(successorBond.status), uint8(BondStatus.Published));

        vm.prank(_publisher);
        _br.issueBond(_bondFT.isin, 2, 100);

        oldBond = _br.getBondAtVersion(isinBytes, 1);
        successorBond = _br.getBondAtVersion(isinBytes, 2);

        assertEq(_br.getActiveVersion(isinBytes), 2);
        assertEq(_br.getLatestVersion(isinBytes), 2);
        assertEq(uint8(oldBond.status), uint8(BondStatus.Replaced));
        assertEq(uint8(successorBond.status), uint8(BondStatus.Issued));
    }

    function test_closeBond_success_afterPendingSuccessorCancelled() public {
        bytes12 isinBytes = _bondFT.isin._isinToBytes12();

        vm.prank(_publisher);
        _br.publishBond(_bondFT);

        vm.prank(_cancelOperator);
        _br.cancelBond(_bondFT.isin, 2);

        uint256 supply = IDEUSSToken(_tokenAddr).totalSupply(_bondFTId);
        vm.prank(_brAddr);
        IDEUSSToken(_tokenAddr).burn(_cwAddr, _bondFTId, supply);

        vm.prank(_closeOperator);
        _br.closeBond(_bondFT.isin, 1);

        Bond memory oldBond = _br.getBondAtVersion(isinBytes, 1);

        assertEq(_br.getActiveVersion(isinBytes), 1);
        assertEq(_br.getLatestVersion(isinBytes), 2);
        assertEq(uint8(oldBond.status), uint8(BondStatus.Redeemed));
    }

    function test_closeBond_success_protectedEscrowDustPushBlockedAndSupplyBurnable() public {
        address burner = makeAddr("registryBurner");
        uint256 dustAmount = 1;
        _grantEnabledBondRegistryBurner(burner);

        vm.prank(_cwAddr);
        IDEUSSToken(_tokenAddr).transfer(_tokenRecipient1, _bondFTId, dustAmount);

        vm.prank(_tokenRecipient1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Token__ProtectedReceiverTransferNotAllowed.selector,
                _tokenRecipient1,
                _escrowManager,
                _tokenRecipient1,
                _bondFTId
            )
        );
        IDEUSSToken(_tokenAddr).transfer(_escrowManager, _bondFTId, dustAmount);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_tokenRecipient1, _bondFTId), dustAmount);

        vm.startPrank(burner);
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _tokenRecipient1, dustAmount, BurnKind.FINAL_SETTLEMENT);
        _br.burnBond(
            _bondFT.isin._isinToBytes12(),
            1,
            _cwAddr,
            IDEUSSToken(_tokenAddr).balanceOf(_cwAddr, _bondFTId),
            BurnKind.FINAL_SETTLEMENT
        );
        vm.stopPrank();

        vm.prank(_closeOperator);
        _br.closeBond(_bondFT.isin, 1);

        assertEq(uint256(_br.bondStatus(_bondFT.isin)), uint256(BondStatus.Redeemed));
    }

    /*//////////////////////////////////////////////////////////////
                                cancelBond
    //////////////////////////////////////////////////////////////*/
    function test_cancelBond_success() public {
        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();

        // ARRANGE: Publish a new bond
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        // ACT: Cancel the bond
        vm.prank(_cancelOperator);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.BondCancelled(_newBondFT.isin._isinToBytes12(), INITIAL_VERSION, _cancelOperator);
        _br.cancelBond(_newBondFT.isin, 1);

        // ASSERT
        Bond memory cancelledBond = _br.getBondAtVersion(isinBytes, 1);
        assertEq(uint256(cancelledBond.status), uint256(BondStatus.Cancelled));
        assertEq(_br.getLatestVersion(isinBytes), 1);
        assertEq(_br.getActiveVersion(isinBytes), 0);
    }

    function test_cancelBond_success_allowsRepublishWithFreshVersionAfterFirstVersionCancelled() public {
        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();
        uint256 republishedTokenId = uint256(keccak256(abi.encodePacked(isinBytes, uint8(2))));

        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_cancelOperator);
        _br.cancelBond(_newBondFT.isin, 1);

        assertEq(_br.getLatestVersion(isinBytes), 1);
        assertEq(_br.getActiveVersion(isinBytes), 0);

        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        Bond memory republishedBond = _br.getBond(_newBondFT.isin);
        Bond memory cancelledBond = _br.getBondAtVersion(isinBytes, 1);
        assertEq(_br.getLatestVersion(isinBytes), 2);
        assertEq(_br.getActiveVersion(isinBytes), 2);
        assertEq(uint256(republishedBond.status), uint256(BondStatus.Published));
        assertEq(uint256(cancelledBond.status), uint256(BondStatus.Cancelled));
        assertEq(republishedBond.tokenId, republishedTokenId);
        assertNotEq(republishedBond.tokenId, _newBondFTId);
    }

    function test_cancelBond_success_republishDoesNotReuseStaleAllowanceTokenId() public {
        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();
        uint256 cancelledTokenId = _newBondFTId;
        uint256 replacementTokenId = uint256(keccak256(abi.encodePacked(isinBytes, uint8(2))));
        address staleSpender = _tokenRecipient1;
        address receiver = _tokenRecipient2;
        uint256 staleAllowance = 500;
        uint256 issuanceAmount = 1_000;

        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_cwAddr);
        IDEUSSToken(_tokenAddr).approve(staleSpender, cancelledTokenId, staleAllowance);

        vm.prank(_cancelOperator);
        _br.cancelBond(_newBondFT.isin, 1);

        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        Bond memory replacementBond = _br.getBond(_newBondFT.isin);
        assertEq(replacementBond.tokenId, replacementTokenId);
        assertNotEq(replacementBond.tokenId, cancelledTokenId);
        assertEq(IDEUSSToken(_tokenAddr).allowance(_cwAddr, staleSpender, cancelledTokenId), staleAllowance);
        assertEq(IDEUSSToken(_tokenAddr).allowance(_cwAddr, staleSpender, replacementTokenId), 0);

        vm.prank(_cwAddr);
        _br.issueBond(_newBondFT.isin, 2, issuanceAmount);

        vm.prank(staleSpender);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909Upgradeable.ERC6909InsufficientAllowance.selector,
                staleSpender,
                0,
                staleAllowance,
                replacementTokenId
            )
        );
        IDEUSSToken(_tokenAddr).transferFrom(_cwAddr, receiver, replacementTokenId, staleAllowance);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(receiver, replacementTokenId), 0);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_cwAddr, replacementTokenId), issuanceAmount);
    }

    function test_cancelBond_success_allowsRepublishSuccessorAfterCancelled() public {
        bytes12 isinBytes = _bondFT.isin._isinToBytes12();
        BondInput memory successorInput = _bondFT;
        successorInput.isGuaranteed = true;

        vm.prank(_publisher);
        _br.publishBond(successorInput);

        vm.prank(_cancelOperator);
        _br.cancelBond(_bondFT.isin, 2);

        Bond memory activeBond = _br.getBond(_bondFT.isin);
        assertEq(_br.getLatestVersion(isinBytes), 2);
        assertEq(_br.getActiveVersion(isinBytes), 1);
        assertEq(uint256(activeBond.status), uint256(BondStatus.Issued));

        vm.prank(_publisher);
        _br.publishBond(successorInput);

        Bond memory cancelledSuccessor = _br.getBondAtVersion(isinBytes, 2);
        Bond memory republishedSuccessor = _br.getBondAtVersion(isinBytes, 3);
        assertEq(_br.getLatestVersion(isinBytes), 3);
        assertEq(_br.getActiveVersion(isinBytes), 1);
        assertEq(uint256(cancelledSuccessor.status), uint256(BondStatus.Cancelled));
        assertEq(uint256(republishedSuccessor.status), uint256(BondStatus.Published));
        assertTrue(republishedSuccessor.isGuaranteed);
    }

    function test_cancelBond_revert_unauthorizedCaller() public {
        // ARRANGE: Publish a new bond
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        // ACT & ASSERT: Expect revert when caller does not have `CANCEL`
        vm.prank(_notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.cancelBond(_newBondFT.isin, 1);
    }

    function test_cancelBond_revert_wrongAuthorizedRole() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.cancelBond(_newBondFT.isin, 1);
    }

    function test_cancelBond_revert_NonExistentBond() public {
        // ACT & ASSERT: Expect revert when bond does not exist
        vm.prank(_cancelOperator);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, _newBondFT.isin._isinToBytes12())
        );
        _br.cancelBond(_newBondFT.isin, 1);
    }

    function test_cancelBond_revert_bondAlreadyIssued() public {
        // ACT & ASSERT: Expect revert when the bond is already issued
        vm.prank(_cancelOperator);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, _bondFT.isin._isinToBytes12())
        );
        _br.cancelBond(_bondFT.isin, 1);
    }

    function test_cancelBond_revert_bondAlreadyIssued_whenPublishedStatusCorrupted() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 3_000);

        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();
        _setBondStatus(isinBytes, 1, BondStatus.Published);

        vm.prank(_cancelOperator);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__BondAlreadyIssued.selector, isinBytes));
        _br.cancelBond(_newBondFT.isin, 1);
    }

    function test_cancelBond_reverts_whenPublishedVersionIsNotLatest() public {
        vm.prank(_publisher);
        _br.publishBond(_bondFT);

        bytes12 isinBytes = _bondFT.isin._isinToBytes12();
        _setBondStatus(isinBytes, 1, BondStatus.Published);
        _setBondTrancheCount(isinBytes, 1, 0);

        vm.prank(_cancelOperator);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, isinBytes));
        _br.cancelBond(_bondFT.isin, 1);
    }

    /*//////////////////////////////////////////////////////////////
                                grantRoles
    //////////////////////////////////////////////////////////////*/
    function test_grantRoles_success() public {
        // ARRANGE
        address newUser = makeAddr("newUser");
        uint256 roles = _br.PUBLISHER();

        assertEq(_br.rolesOf(newUser), 0);

        // ACT
        _timelockOp(_brAddr, abi.encodeWithSelector(OwnableRoles.grantRoles.selector, newUser, roles));

        // ASSERT
        assertEq(_br.rolesOf(newUser), roles);
    }

    function test_grantRoles_success_allBondRegistryRoles() public {
        address newUser = makeAddr("allBondRegistryRolesUser");
        uint256 roles = _br.ALL_BR_ROLES();

        _grantBondRegistryRoles(newUser, roles);

        assertEq(_br.rolesOf(newUser), roles);
    }

    function test_grantRoles_revert_paramIsZeroAddress() public {
        // ARRANGE
        uint256 roles = _br.PUBLISHER();

        // ACT & ASSERT: Expect revert when the user parameter is zero address
        bytes memory data = abi.encodeWithSelector(OwnableRoles.grantRoles.selector, address(0), roles);
        _timelockSchedule(_brAddr, data);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _timelockExecute(_brAddr, data);
    }

    function test_grantRoles_revert_unauthorizedCaller() public {
        // ARRANGE
        address newUser = makeAddr("newUser");
        uint256 roles = _br.PUBLISHER();

        // ACT & ASSERT: Expect revert when caller is not owner
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.grantRoles(newUser, roles);
    }

    function test_grantRoles_revert_invalidRoles() public {
        // ARRANGE
        address newUser = makeAddr("newUser");
        uint256 roles = _br.ALL_BR_ROLES() | _invalidBondRegistryRoleBit();

        // ACT & ASSERT: Expect revert when invalid roles are setup
        bytes memory data = abi.encodeWithSelector(OwnableRoles.grantRoles.selector, newUser, roles);
        _timelockSchedule(_brAddr, data);
        vm.expectRevert(Errors.InvalidRoles.selector);
        _timelockExecute(_brAddr, data);
    }

    function test_grantRoles_revert_allBondRegistryRolesPlusInvalidBit() public {
        address newUser = makeAddr("invalidMaskUser");
        uint256 roles = _br.ALL_BR_ROLES() | _invalidBondRegistryRoleBit();

        bytes memory data = abi.encodeWithSelector(OwnableRoles.grantRoles.selector, newUser, roles);
        _timelockSchedule(_brAddr, data);
        vm.expectRevert(Errors.InvalidRoles.selector);
        _timelockExecute(_brAddr, data);
    }

    function test_grantRoles_array_success() public {
        // ARRANGE
        address[] memory users = new address[](1);
        users[0] = makeAddr("newUser");
        uint256 roles = _br.PUBLISHER();

        assertEq(_br.rolesOf(users[0]), 0);

        // ACT
        _timelockOp(_brAddr, abi.encodeWithSignature("grantRoles(address[],uint256)", users, roles));

        // ASSERT
        assertEq(_br.rolesOf(users[0]), roles);
    }

    function test_grantRoles_array_success_allBondRegistryRoles() public {
        address[] memory users = new address[](2);
        users[0] = makeAddr("allRolesArrayUser0");
        users[1] = makeAddr("allRolesArrayUser1");
        uint256 roles = _br.ALL_BR_ROLES();

        _timelockOp(_brAddr, abi.encodeWithSignature("grantRoles(address[],uint256)", users, roles));

        assertEq(_br.rolesOf(users[0]), roles);
        assertEq(_br.rolesOf(users[1]), roles);
    }

    function test_grantRoles_array_revert_paramContainsZeroAddress() public {
        // ARRANGE
        address[] memory users = new address[](1);
        users[0] = address(0);
        uint256 roles = _br.PUBLISHER();

        // ACT & ASSERT: Expect revert when caller is zero address
        bytes memory data = abi.encodeWithSignature("grantRoles(address[],uint256)", users, roles);
        _timelockSchedule(_brAddr, data);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _timelockExecute(_brAddr, data);
    }

    function test_grantRoles_array_revert_unauthorizedCaller() public {
        // ARRANGE
        address[] memory users = new address[](1);
        users[0] = makeAddr("newUser");
        uint256 roles = _br.PUBLISHER();

        // ACT & ASSERT: Expect revert when caller is not owner
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.grantRoles(users, roles);
    }

    function test_grantRoles_array_revert_invalidRoles() public {
        // ARRANGE
        address[] memory users = new address[](1);
        users[0] = makeAddr("newUser");
        uint256 roles = _br.ALL_BR_ROLES() | _invalidBondRegistryRoleBit();

        // ACT & ASSERT: Expect revert when invalid roles are setup
        bytes memory data = abi.encodeWithSignature("grantRoles(address[],uint256)", users, roles);
        _timelockSchedule(_brAddr, data);
        vm.expectRevert(Errors.InvalidRoles.selector);
        _timelockExecute(_brAddr, data);
    }

    function test_grantRoles_array_revert_allBondRegistryRolesPlusInvalidBit() public {
        address[] memory users = new address[](1);
        users[0] = makeAddr("invalidArrayMaskUser");
        uint256 roles = _br.ALL_BR_ROLES() | _invalidBondRegistryRoleBit();

        bytes memory data = abi.encodeWithSignature("grantRoles(address[],uint256)", users, roles);
        _timelockSchedule(_brAddr, data);
        vm.expectRevert(Errors.InvalidRoles.selector);
        _timelockExecute(_brAddr, data);
    }

    function test_grantRoles_success_combinedRoles() public {
        address newUser = makeAddr("combinedRoleUser");
        uint256 roles = _br.PUBLISHER() | _br.CURRENCY() | _br.SUSPEND();

        _timelockOp(_brAddr, abi.encodeWithSelector(OwnableRoles.grantRoles.selector, newUser, roles));

        assertEq(_br.rolesOf(newUser), roles);
    }

    function test_combinedRoles_publisherAndCancel_followExpectedAccessMatrix() public {
        address operator = makeAddr("publisherCancelOperator");
        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();
        BondInput memory updatedBond = _newBondFT;
        uint256 timeShift = 1 days;
        updatedBond.maturityDate += timeShift;

        _grantBondRegistryRoles(operator, _br.PUBLISHER() | _br.CANCEL());

        vm.prank(operator);
        _br.publishBond(_newBondFT);

        vm.prank(operator);
        _br.updatePublishedBond(updatedBond, 1);

        vm.prank(operator);
        _br.cancelBond(_newBondFT.isin, 1);

        assertEq(uint256(_br.getBondAtVersion(isinBytes, 1).status), uint256(BondStatus.Cancelled));
        assertEq(_br.getLatestVersion(isinBytes), 1);
        assertEq(_br.getActiveVersion(isinBytes), 0);

        vm.prank(operator);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.closeBond(_bondFT.isin, 1);

        vm.prank(operator);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.suspendBond(_bondFT.isin, 1);

        vm.prank(operator);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.unsuspendBond(_bondFT.isin, 1);
    }

    function test_allBondRegistryRoles_canExecuteAllRoleGatedFunctions() public {
        address operator = makeAddr("allRolesOperator");
        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();
        BondInput memory updatedBond = _newBondFT;
        uint256 supply = IDEUSSToken(_tokenAddr).totalSupply(_bondFTId);
        uint256 timeShift = 1 days;

        updatedBond.maturityDate += timeShift;

        _grantBondRegistryRoles(operator, _br.ALL_BR_ROLES());

        vm.prank(operator);
        _br.setAllowedCurrency("USD", true);
        assertTrue(_br.isCurrencyAllowed("USD"));

        vm.prank(operator);
        _br.publishBond(_newBondFT);

        vm.prank(operator);
        _br.updatePublishedBond(updatedBond, 1);

        vm.prank(operator);
        _br.cancelBond(_newBondFT.isin, 1);
        assertEq(uint256(_br.getBondAtVersion(isinBytes, 1).status), uint256(BondStatus.Cancelled));
        assertEq(_br.getLatestVersion(isinBytes), 1);
        assertEq(_br.getActiveVersion(isinBytes), 0);

        vm.prank(operator);
        _br.suspendBond(_bondFT.isin, 1);
        assertEq(uint256(_br.bondStatus(_bondFT.isin)), uint256(BondStatus.Suspended));

        vm.prank(operator);
        _br.unsuspendBond(_bondFT.isin, 1);
        assertEq(uint256(_br.bondStatus(_bondFT.isin)), uint256(BondStatus.Issued));

        vm.prank(_brAddr);
        IDEUSSToken(_tokenAddr).burn(_cwAddr, _bondFTId, supply);

        vm.prank(operator);
        _br.closeBond(_bondFT.isin, 1);
        assertEq(uint256(_br.bondStatus(_bondFT.isin)), uint256(BondStatus.Redeemed));
    }

    /*//////////////////////////////////////////////////////////////
                        publishBond
    //////////////////////////////////////////////////////////////*/
    function test_publishBond_success() public {
        // ACT
        vm.prank(_publisher);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.BondPublished(
            _newBondFT.isin._isinToBytes12(),
            _newBondFT.issuer,
            1,
            _newBondFTId,
            _tokenAddr,
            _newBondFT.currency._currencyToBytes3(),
            _newBondFT.bondNominalValue,
            _newBondFT.maxSupply,
            _newBondFT.maturityDate,
            _newBondFT.couponFrequency,
            _newBondFT.couponRateType,
            _newBondFT.isGuaranteed,
            _newBondFT.issuanceCountry,
            _publisher
        );
        _br.publishBond(_newBondFT);

        // ASSERT
        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(bond.isin, _newBondFT.isin._isinToBytes12());
        assertEq(bond.issuer, _newBondFT.issuer);
        assertEq(uint256(bond.status), uint256(BondStatus.Published));
        assertEq(uint256(bond.couponFrequency), uint256(CouponFrequency.Annual));
        assertEq(bond.currency, BOND_CURRENCY._currencyToBytes3());
        assertEq(bond.bondNominalValue, BOND_NOMINAL_VALUE);
        assertEq(bond.couponRates.paymentTimestamps.length, 2);
        assertEq(bond.couponRates.rates.length, 2);
        assertEq(bond.couponRates.rates[0], BOND_COUPON_RATE);
        assertEq(uint8(bond.couponRateType), uint8(BOND_COUPON_RATE_TYPE));
        assertEq(bond.maxSupply, BOND_MAX_SUPPLY);
        assertEq(bond.mintedSupply, 0);
        assertEq(bond.trancheCount, 0);
        assertEq(bond.maturityDate, _newBondFT.maturityDate);
        assertEq(bond.tokenAddress, _tokenAddr);
        assertEq(bond.isGuaranteed, _newBondFT.isGuaranteed);
        assertEq(uint256(bond.issuanceCountry), uint256(_newBondFT.issuanceCountry));
    }

    function test_publishBond_success_storesIsGuaranteedTrue() public {
        BondInput memory guaranteedBond = _newBondFT;
        guaranteedBond.isGuaranteed = true;

        vm.prank(_publisher);
        _br.publishBond(guaranteedBond);

        Bond memory bond = _br.getBond(guaranteedBond.isin);
        assertTrue(bond.isGuaranteed);
    }

    function test_publishBond_success_storesIsGuaranteedFalse() public {
        BondInput memory nonGuaranteedBond = _newBondFT;
        nonGuaranteedBond.isGuaranteed = false;

        vm.prank(_publisher);
        _br.publishBond(nonGuaranteedBond);

        Bond memory bond = _br.getBond(nonGuaranteedBond.isin);
        assertFalse(bond.isGuaranteed);
    }

    function test_publishBond_revert_unauthorizedCaller() public {
        // ACT & ASSERT: Expect revert when the caller does not have `PUBLISHER`
        vm.prank(_notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.publishBond(_newBondFT);
    }

    function test_publishBond_revert_wrongAuthorizedRole() public {
        vm.prank(_cancelOperator);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.publishBond(_newBondFT);
    }

    function test_publishBond_revert_issuerZeroAddress() public {
        BondInput memory bondWithInvalidIssuer = _newBondFT;
        bondWithInvalidIssuer.issuer = address(0);

        // ACT & ASSERT: Expect revert when the issuer is zero address
        vm.prank(_publisher);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _br.publishBond(bondWithInvalidIssuer);
    }

    function test_publishBond_revert_issuerNotEnabled() public {
        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, _newBondFT.issuer),
            abi.encode(false)
        );

        vm.prank(_publisher);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__IssuerNotEnabled.selector, _newBondFT.issuer));
        _br.publishBond(_newBondFT);
    }

    function test_publishBond_revert_invalidIsinLen() public {
        // ARRANGE
        BondInput memory bondWithInvalidIsin = _newBondFT;
        bondWithInvalidIsin.isin = "SK";

        // ACT & ASSERT: Expect revert when invalid length of ISIN
        vm.prank(_publisher);
        vm.expectRevert(Errors.StringExtensions__InvalidBytesLength.selector);
        _br.publishBond(bondWithInvalidIsin);
    }

    function test_publishBond_revert_isinWithNonAsciiChar() public {
        // ARRANGE
        BondInput memory bondWithInvalidIsin = _newBondFT;
        bondWithInvalidIsin.isin = unicode"Sé000100205";

        // ACT & ASSERT: Expect revert when ISIN contains non-ASCII bytes
        vm.prank(_publisher);
        vm.expectRevert(Errors.StringExtensions__NonAsciiCharacter.selector);
        _br.publishBond(bondWithInvalidIsin);
    }

    function test_publishBond_revert_isinWithControlChar() public {
        BondInput memory bondWithInvalidIsin = _newBondFT;
        bondWithInvalidIsin.isin = "SK00010020\n9";

        vm.prank(_publisher);
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _br.publishBond(bondWithInvalidIsin);
    }

    function test_publishBond_revert_isinWithPunctuation() public {
        BondInput memory bondWithInvalidIsin = _newBondFT;
        bondWithInvalidIsin.isin = "SK00010020-9";

        vm.prank(_publisher);
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _br.publishBond(bondWithInvalidIsin);
    }

    function test_publishBond_revert_isinWithLowercaseCountryCode() public {
        BondInput memory bondWithInvalidIsin = _newBondFT;
        bondWithInvalidIsin.isin = "sk0001002059";

        vm.prank(_publisher);
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _br.publishBond(bondWithInvalidIsin);
    }

    function test_publishBond_revert_isinWithNonDigitCheckPosition() public {
        BondInput memory bondWithInvalidIsin = _newBondFT;
        bondWithInvalidIsin.isin = "SK000100205A";

        vm.prank(_publisher);
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _br.publishBond(bondWithInvalidIsin);
    }

    function test_publishBond_revert_isinIsEmptyString() public {
        // ARRANGE
        BondInput memory bondWithInvalidIsin = _newBondFT;
        bondWithInvalidIsin.isin = "";

        // ACT & ASSERT: Expect revert when ISIN is empty string
        vm.prank(_publisher);
        vm.expectRevert(Errors.StringExtensions__InvalidBytesLength.selector);
        _br.publishBond(bondWithInvalidIsin);
    }

    function test_publishBond_success_existingIsinCreatesNextPublishedVersion() public {
        BondInput memory successorInput = _bondFT;
        successorInput.isGuaranteed = true;

        vm.prank(_publisher);
        _br.publishBond(successorInput);

        Bond memory activeBond = _br.getBond(_bondFT.isin);
        Bond memory successorBond = _br.getBondAtVersion(_bondFT.isin._isinToBytes12(), 2);

        assertEq(_br.getActiveVersion(_bondFT.isin._isinToBytes12()), 1);
        assertEq(_br.getLatestVersion(_bondFT.isin._isinToBytes12()), 2);
        assertEq(uint8(activeBond.status), uint8(BondStatus.Issued));
        assertEq(uint8(successorBond.status), uint8(BondStatus.Published));
        assertEq(successorBond.tokenId, uint256(keccak256(abi.encodePacked(_bondFT.isin._isinToBytes12(), uint8(2)))));
        assertFalse(activeBond.isGuaranteed);
        assertTrue(successorBond.isGuaranteed);
    }

    function test_publishBond_revert_successorAlreadyPublished() public {
        vm.startPrank(_publisher);
        _br.publishBond(_bondFT);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.BondRegistry__SuccessorAlreadyPublished.selector, _bondFT.isin._isinToBytes12()
            )
        );
        _br.publishBond(_bondFT);
        vm.stopPrank();
    }

    function test_publishBond_revert_activeVersionNotIssuable() public {
        vm.prank(_suspendOperator);
        _br.suspendBond(_bondFT.isin, 1);

        vm.prank(_publisher);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.BondRegistry__ActiveVersionNotIssuable.selector, _bondFT.isin._isinToBytes12()
            )
        );
        _br.publishBond(_bondFT);
    }

    function test_issueBond_success_successorCutoverSwitchesActiveVersionAndMarksOldVersionReplaced() public {
        vm.prank(_publisher);
        _br.publishBond(_bondFT);

        vm.prank(_publisher);
        _br.issueBond(_bondFT.isin, 2, 100);

        bytes12 isinBytes = _bondFT.isin._isinToBytes12();
        Bond memory activeBond = _br.getBond(_bondFT.isin);
        Bond memory oldBond = _br.getBondAtVersion(isinBytes, 1);
        Bond memory newBond = _br.getBondAtVersion(isinBytes, 2);

        assertEq(_br.getActiveVersion(isinBytes), 2);
        assertEq(activeBond.tokenId, newBond.tokenId);
        assertEq(uint8(oldBond.status), uint8(BondStatus.Replaced));
        assertEq(uint8(newBond.status), uint8(BondStatus.Issued));
    }

    function test_issueBond_revert_successorCutoverWhenPreviousVersionIsSuspended() public {
        vm.prank(_publisher);
        _br.publishBond(_bondFT);

        vm.prank(_suspendOperator);
        _br.suspendBond(_bondFT.isin, 1);

        assertTrue(IBaseToken(_tokenAddr).isTokenPaused(_bondFTId));

        bytes12 isinBytes = _bondFT.isin._isinToBytes12();
        vm.prank(_publisher);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, isinBytes));
        _br.issueBond(_bondFT.isin, 2, 100);
    }

    function test_publishBond_revert_invalidCurrencyLen() public {
        // ARRANGE
        BondInput memory invalidBond = _newBondFT;
        invalidBond.currency = "TTTT";

        // ACT & ASSERT: Expect revert when the currency string length is not equal to 3
        vm.prank(_publisher);
        vm.expectRevert(Errors.StringExtensions__InvalidBytesLength.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_currencyIsEmptyString() public {
        // ARRANGE
        BondInput memory invalidBond = _newBondFT;
        invalidBond.currency = "";

        // ACT & ASSERT: Expect revert when the currency string length is not equal to 3
        vm.prank(_publisher);
        vm.expectRevert(Errors.StringExtensions__InvalidBytesLength.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_currencyWithNonAsciiChar() public {
        // ARRANGE
        BondInput memory invalidBond = _newBondFT;
        invalidBond.currency = unicode"Té";

        // ACT & ASSERT: Expect revert when the currency contains non-ASCII bytes
        vm.prank(_publisher);
        vm.expectRevert(Errors.StringExtensions__NonAsciiCharacter.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_currencyWithControlChar() public {
        BondInput memory invalidBond = _newBondFT;
        invalidBond.currency = "EU\n";

        vm.prank(_publisher);
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_currencyWithLowercase() public {
        BondInput memory invalidBond = _newBondFT;
        invalidBond.currency = "usd";

        vm.prank(_publisher);
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_currencyWithDigit() public {
        BondInput memory invalidBond = _newBondFT;
        invalidBond.currency = "EU1";

        vm.prank(_publisher);
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_currencyIsNotAllowed() public {
        // ARRANGE
        BondInput memory invalidBond = _newBondFT;
        invalidBond.currency = "TTT";

        // ACT & ASSERT: Expect revert when the currency is not allowed
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__InvalidCurrency.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_bondNominalValueIsZero() public {
        // ARRANGE
        BondInput memory invalidBond = _newBondFT;
        invalidBond.bondNominalValue = 0;

        // ACT & ASSERT: Expect revert when the bondNominalValue is zero
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__BondNominalValueIsZero.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_maxSupplyIsZero() public {
        // ARRANGE
        BondInput memory invalidBond = _newBondFT;
        invalidBond.maxSupply = 0;

        // ACT & ASSERT: Expect revert when the max supply is zero
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__MaxSupplyIsZero.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_issuanceCountryIsZero() public {
        BondInput memory invalidBond = _newBondFT;
        invalidBond.issuanceCountry = 0;

        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__IssuanceCountryIsZero.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_maturityDateExpired() public {
        // ARRANGE
        BondInput memory invalidBond = _newBondFT;
        invalidBond.maturityDate = block.timestamp - 1;

        // ACT & ASSERT: Expect revert when the maturity date is in the past
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__MaturityDateExpired.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_couponRatesLengthMismatch() public {
        // ARRANGE
        BondInput memory invalidBond = _newBondFT;
        invalidBond.couponRates.paymentTimestamps = new uint256[](1);
        invalidBond.couponRates.rates = new uint256[](2);

        // ACT & ASSERT: Expect revert when the coupon payment timestamps and rates are not the same length
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__CouponRatesLengthMismatch.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_paymentTimestampsUnordered() public {
        // ARRANGE
        BondInput memory invalidBond = _newBondFT;
        invalidBond.couponRates.paymentTimestamps = new uint256[](2);
        invalidBond.couponRates.paymentTimestamps[0] = 2;
        invalidBond.couponRates.paymentTimestamps[1] = 1;
        invalidBond.couponRates.rates = new uint256[](2);

        // ACT & ASSERT: Expect revert when the coupon payment timestamps are not ordered ASC
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__PaymentTimestampsUnordered.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_paymentTimestampZero() public {
        // ARRANGE
        BondInput memory invalidBond = _newBondFT;
        invalidBond.couponRates.paymentTimestamps[0] = 0;

        // ACT & ASSERT: Expect revert if the first payment timestamp is zero
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__PaymentTimestampZero.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_couponRatesLastRateNotZero() public {
        // ARRANGE
        BondInput memory invalidBond = _newBondFT;
        invalidBond.couponRates.rates[1] = 1;

        // ACT & ASSERT: Expect revert if the last coupon rate is not zero
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__CouponRatesLastRateNotZero.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_paymentTimestampAfterMaturity() public {
        BondInput memory invalidBond = _newBondFT;
        invalidBond.couponRates.paymentTimestamps[1] = invalidBond.maturityDate + 1;

        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__PaymentTimestampAfterMaturity.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_couponRatesDuplicateWithEqualIntervals() public {
        // ARRANGE
        BondInput memory invalidBond = _newBondFT;
        invalidBond.couponRateType = CouponRateType.FLOATING;
        invalidBond.couponRates.paymentTimestamps = new uint256[](3);
        invalidBond.couponRates.paymentTimestamps[0] = 1;
        invalidBond.couponRates.paymentTimestamps[1] = 1;
        invalidBond.couponRates.paymentTimestamps[2] = 13;
        invalidBond.couponRates.rates = new uint256[](3);
        invalidBond.couponRates.rates[0] = 1000;
        invalidBond.couponRates.rates[1] = 1000;
        invalidBond.couponRates.rates[2] = 0;

        // ACT & ASSERT: Equal consecutive intervals fail ordering checks before duplicate-rate checks.
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__PaymentTimestampsUnordered.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_couponRatesUnexpectedLength() public {
        // ARRANGE
        BondInput memory invalidBond = _newBondFT;
        invalidBond.couponRateType = CouponRateType.FIXED;
        invalidBond.couponRates.paymentTimestamps = new uint256[](3);
        invalidBond.couponRates.paymentTimestamps[0] = 1;
        invalidBond.couponRates.paymentTimestamps[1] = 2;
        invalidBond.couponRates.paymentTimestamps[2] = 3;
        invalidBond.couponRates.rates = new uint256[](3);
        invalidBond.couponRates.rates[0] = 500;
        invalidBond.couponRates.rates[1] = 600;
        invalidBond.couponRates.rates[2] = 0;

        // ACT & ASSERT: Expect revert if the coupon type is fixed but length of `couponRates` is not 2
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__CouponRatesUnexpectedLength.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_equalConsecutivePaymentTimestamps() public {
        // ARRANGE: equal consecutive timestamps with different rates — strict order fails
        BondInput memory invalidBond = _newBondFT;
        invalidBond.couponRateType = CouponRateType.FLOATING;
        invalidBond.couponRates.paymentTimestamps = new uint256[](3);
        invalidBond.couponRates.paymentTimestamps[0] = 1;
        invalidBond.couponRates.paymentTimestamps[1] = 1; // equal to previous — must be strictly greater
        invalidBond.couponRates.paymentTimestamps[2] = 3;
        invalidBond.couponRates.rates = new uint256[](3);
        invalidBond.couponRates.rates[0] = 500;
        invalidBond.couponRates.rates[1] = 600;
        invalidBond.couponRates.rates[2] = 0;

        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__PaymentTimestampsUnordered.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_equalConsecutivePaymentTimestamps_fixed() public {
        // ARRANGE: FIXED bond with [x, x] — the NM-004 scenario that used to pass validation
        // and caused getCouponRateAt to silently return 0 instead of the real rate
        BondInput memory invalidBond = _newBondFT;
        invalidBond.couponRateType = CouponRateType.FIXED;
        invalidBond.couponRates.paymentTimestamps = new uint256[](2);
        invalidBond.couponRates.paymentTimestamps[0] = 13;
        invalidBond.couponRates.paymentTimestamps[1] = 13; // equal — must be strictly greater
        invalidBond.couponRates.rates = new uint256[](2);
        invalidBond.couponRates.rates[0] = 500;
        invalidBond.couponRates.rates[1] = 0;

        // ACT & ASSERT
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__PaymentTimestampsUnordered.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_duplicateAdjacentCouponRates() public {
        // ARRANGE
        BondInput memory invalidBond = _newBondFT;
        invalidBond.couponRateType = CouponRateType.FLOATING;
        invalidBond.couponRates.paymentTimestamps = new uint256[](3);
        invalidBond.couponRates.paymentTimestamps[0] = 1;
        invalidBond.couponRates.paymentTimestamps[1] = 2;
        invalidBond.couponRates.paymentTimestamps[2] = 3;
        invalidBond.couponRates.rates = new uint256[](3);
        invalidBond.couponRates.rates[0] = 500;
        invalidBond.couponRates.rates[1] = 500;
        invalidBond.couponRates.rates[2] = 0;

        // ACT & ASSERT
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__CouponRatesDuplicate.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_zeroCouponWithNonEmptyArrays() public {
        // ARRANGE
        BondInput memory invalidBond = _newBondFT;
        invalidBond.couponRateType = CouponRateType.ZERO_COUPON;
        // ZERO_COUPON should have empty arrays, but we provide non-empty ones
        invalidBond.couponRates.paymentTimestamps = new uint256[](1);
        invalidBond.couponRates.paymentTimestamps[0] = 1;
        invalidBond.couponRates.rates = new uint256[](1);
        invalidBond.couponRates.rates[0] = 100;

        // ACT & ASSERT: Expect revert when ZERO_COUPON has non-empty arrays
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__CouponRatesUnexpectedLength.selector);
        _br.publishBond(invalidBond);
    }

    function test_publishBond_revert_floatingWithLessThanTwoElements() public {
        // ARRANGE
        BondInput memory invalidBond = _newBondFT;
        invalidBond.couponRateType = CouponRateType.FLOATING;
        // FLOATING requires at least 2 elements, but we provide only 1
        invalidBond.couponRates.paymentTimestamps = new uint256[](1);
        invalidBond.couponRates.paymentTimestamps[0] = 1;
        invalidBond.couponRates.rates = new uint256[](1);
        invalidBond.couponRates.rates[0] = 0;

        // ACT & ASSERT: Expect revert when FLOATING has less than 2 elements
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__CouponRatesUnexpectedLength.selector);
        _br.publishBond(invalidBond);
    }

    /*//////////////////////////////////////////////////////////////
                            updatePublishedBond
    //////////////////////////////////////////////////////////////*/
    function test_updatePublishedBond_success() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.bondNominalValue = 2 * _newBondFT.bondNominalValue;

        // ACT
        vm.prank(_publisher);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.PublishedBondUpdated(
            _newBondFT.isin._isinToBytes12(),
            1,
            _publisher,
            updatedBond.issuer,
            _newBondFTId,
            _tokenAddr,
            updatedBond.currency._currencyToBytes3(),
            updatedBond.bondNominalValue,
            updatedBond.maxSupply,
            updatedBond.maturityDate,
            updatedBond.couponFrequency,
            updatedBond.couponRateType,
            updatedBond.isGuaranteed,
            updatedBond.issuanceCountry
        );
        _br.updatePublishedBond(updatedBond, 1);

        // ASSERT
        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(bond.bondNominalValue, updatedBond.bondNominalValue);
        assertEq(bond.tokenAddress, _tokenAddr);
        assertEq(bond.isGuaranteed, updatedBond.isGuaranteed);
        assertEq(uint256(bond.issuanceCountry), uint256(updatedBond.issuanceCountry));
    }

    function test_updatePublishedBond_success_whenIsGuaranteedMatchesStored() public {
        BondInput memory guaranteedBond = _newBondFT;
        guaranteedBond.isGuaranteed = true;

        vm.prank(_publisher);
        _br.publishBond(guaranteedBond);

        BondInput memory updatedBond = guaranteedBond;
        updatedBond.bondNominalValue = 2 * guaranteedBond.bondNominalValue;

        vm.prank(_publisher);
        _br.updatePublishedBond(updatedBond, 1);

        Bond memory bond = _br.getBond(guaranteedBond.isin);
        assertEq(bond.bondNominalValue, updatedBond.bondNominalValue);
        assertTrue(bond.isGuaranteed);
    }

    function test_updatePublishedBond_success_changeIssuanceCountry() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.issuanceCountry = ISO_3166_CZECHIA;

        vm.prank(_publisher);
        _br.updatePublishedBond(updatedBond, 1);

        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(uint256(bond.issuanceCountry), uint256(ISO_3166_CZECHIA));
    }

    function test_updatePublishedBond_revert_whenChangingIsGuaranteed() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.isGuaranteed = !_newBondFT.isGuaranteed;

        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();
        vm.prank(_publisher);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__GuaranteeStatusImmutable.selector, isinBytes));
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_success_changeCouponRateType() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.couponRateType = CouponRateType.ZERO_COUPON;
        updatedBond.couponRates = CouponRates({paymentTimestamps: new uint256[](0), rates: new uint256[](0)});

        // ACT
        vm.prank(_publisher);
        _br.updatePublishedBond(updatedBond, 1);

        // ASSERT
        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(uint8(bond.couponRateType), uint8(CouponRateType.ZERO_COUPON));
    }

    function test_updatePublishedBond_success_changeToFloatingRate() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.couponRateType = CouponRateType.FLOATING;

        // Create floating rate coupon structure
        uint256[] memory paymentTimestamps = new uint256[](3);
        paymentTimestamps[0] = 1;
        paymentTimestamps[1] = 13;
        paymentTimestamps[2] = 25;

        uint256[] memory rates = new uint256[](3);
        rates[0] = 1000;
        rates[1] = 1200;
        rates[2] = 0;

        updatedBond.couponRates = CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});

        // ACT
        vm.prank(_publisher);
        _br.updatePublishedBond(updatedBond, 1);

        // ASSERT
        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(uint8(bond.couponRateType), uint8(CouponRateType.FLOATING));
        assertEq(bond.couponRates.rates.length, 3);
    }

    function test_updatePublishedBond_revert_unauthorizedCaller() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;

        // ACT & ASSERT: Expect revert when caller does not have `PUBLISHER`
        vm.prank(_notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_issuanceCountryIsZero() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.issuanceCountry = 0;

        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__IssuanceCountryIsZero.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_wrongAuthorizedRole() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;

        vm.prank(_cancelOperator);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishBond_revert_issuerZeroAddress() public {
        BondInput memory updatedBond = _newBondFT;
        updatedBond.issuer = address(0);

        // ACT & ASSERT: Expect revert when the issuer is zero address
        vm.prank(_publisher);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _br.publishBond(updatedBond);
    }

    function test_updatePublishedBond_revert_nonExistentBond() public {
        // ACT & ASSERT: Expect revert when bond does not exist
        vm.prank(_publisher);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, _newBondFT.isin._isinToBytes12())
        );
        _br.updatePublishedBond(_newBondFT, 1);
    }

    function test_updatePublishedBond_revert_invalidBondStatus() public {
        // ACT & ASSERT: Expect revert when bond is already issued (not Published)
        BondInput memory updatedBond = _bondFT;

        vm.prank(_publisher);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, _bondFT.isin._isinToBytes12())
        );
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_bondIsIssued() public {
        // ARRANGE: Publish and then issue so bond is in Issued status
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 3_000);

        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();
        BondInput memory updatedBond = _newBondFT;
        // solhint-disable-next-line gas-increment-by-one
        updatedBond.maturityDate += 1 days;

        // ACT & ASSERT: Cannot amend an Issued bond
        vm.prank(_publisher);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, isinBytes));
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_nonExistentVersion() public {
        // ARRANGE: Publish bond at version 1, try to update version 2 (does not exist)
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();
        BondInput memory updatedBond = _newBondFT;
        updatedBond.maturityDate = updatedBond.maturityDate + 2 days;

        // ACT & ASSERT: Non-existent version yields InvalidBondStatus (Unregistered != Published)
        vm.prank(_publisher);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, isinBytes));
        _br.updatePublishedBond(updatedBond, 2);
    }

    function test_updatePublishedBond_revert_bondNominalValueIsZero() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.bondNominalValue = 0;

        // ACT & ASSERT: Expect revert when the bondNominalValue is zero
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__BondNominalValueIsZero.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_success_validFloatingCouponRates() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.couponRateType = CouponRateType.FLOATING;
        // Valid floating rate structure with multiple rate changes
        uint256[] memory paymentTimestamps = new uint256[](4);
        paymentTimestamps[0] = 1;
        paymentTimestamps[1] = 13;
        paymentTimestamps[2] = 25;
        paymentTimestamps[3] = 37;
        uint256[] memory rates = new uint256[](4);
        rates[0] = 1000; // 10% for first year
        rates[1] = 1200; // 12% for second year
        rates[2] = 1500; // 15% for third year
        rates[3] = 0; // End marker
        updatedBond.couponRates = CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});

        // ACT
        vm.prank(_publisher);
        _br.updatePublishedBond(updatedBond, 1);

        // ASSERT
        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(uint8(bond.couponRateType), uint8(CouponRateType.FLOATING));
        assertEq(bond.couponRates.rates.length, 4);
        assertEq(bond.couponRates.rates[0], 1000);
        assertEq(bond.couponRates.rates[1], 1200);
        assertEq(bond.couponRates.rates[2], 1500);
        assertEq(bond.couponRates.rates[3], 0);

        // In the new model, updatePublishedBond amends in place — no Replaced version, same version stays Published
        assertEq(uint256(bond.status), uint256(BondStatus.Published));
    }

    function test_updatePublishedBond_success_zeroCouponEmptyRates() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.couponRateType = CouponRateType.ZERO_COUPON;
        updatedBond.couponRates = CouponRates({paymentTimestamps: new uint256[](0), rates: new uint256[](0)});

        // ACT
        vm.prank(_publisher);
        _br.updatePublishedBond(updatedBond, 1);

        // ASSERT
        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(uint8(bond.couponRateType), uint8(CouponRateType.ZERO_COUPON));
        assertEq(bond.couponRates.rates.length, 0);
        assertEq(bond.couponRates.paymentTimestamps.length, 0);
    }

    function test_updatePublishedBond_success_fixedCouponValidRates() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.couponRateType = CouponRateType.FIXED;
        // Valid fixed rate structure with exactly 2 elements
        uint256[] memory paymentTimestamps = new uint256[](2);
        paymentTimestamps[0] = 1;
        paymentTimestamps[1] = 13; // After 13 months, rate becomes 0
        uint256[] memory rates = new uint256[](2);
        rates[0] = 500; // 5% fixed rate
        rates[1] = 0; // End marker
        updatedBond.couponRates = CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});

        // ACT
        vm.prank(_publisher);
        _br.updatePublishedBond(updatedBond, 1);

        // ASSERT
        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(uint8(bond.couponRateType), uint8(CouponRateType.FIXED));
        assertEq(bond.couponRates.rates.length, 2);
        assertEq(bond.couponRates.rates[0], 500);
        assertEq(bond.couponRates.rates[1], 0);
    }

    function test_updatePublishedBond_success_allowsIssuerChange() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        // Change issuer in update
        BondInput memory updatedBond = _newBondFT;
        updatedBond.issuer = address(0x1234);
        _registerWallet(updatedBond.issuer);
        updatedBond.bondNominalValue = 2 * _newBondFT.bondNominalValue;

        // ACT
        vm.prank(_publisher);
        _br.updatePublishedBond(updatedBond, 1);

        // ASSERT: Issuer in the latest version is the new one from input
        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(bond.issuer, address(0x1234));
    }

    function test_updatePublishedBond_revert_issuerNotEnabled() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        address disabledIssuer = makeAddr("disabledIssuer");
        updatedBond.issuer = disabledIssuer;

        vm.mockCall(
            _erAddr,
            abi.encodeWithSelector(IEntityRegistry.isAccountEnabled.selector, disabledIssuer),
            abi.encode(false)
        );

        vm.prank(_publisher);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__IssuerNotEnabled.selector, disabledIssuer));
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_success_keepSameIssueDate() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        // Update with same issue date (should not require future check)
        BondInput memory updatedBond = _newBondFT;
        updatedBond.bondNominalValue = 2 * _newBondFT.bondNominalValue;
        // Keep issue date the same

        // ACT
        vm.prank(_publisher);
        _br.updatePublishedBond(updatedBond, 1);

        // ASSERT
        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(bond.bondNominalValue, updatedBond.bondNominalValue);
    }

    function test_updatePublishedBond_success_multipleUpdates() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        uint256 version1TokenId = _br.getTokenId(_newBondFT.isin);

        // First update: amends version 1 in place
        BondInput memory updatedBond1 = _newBondFT;
        updatedBond1.bondNominalValue = 2 * _newBondFT.bondNominalValue;
        vm.prank(_publisher);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.PublishedBondUpdated(
            _newBondFT.isin._isinToBytes12(),
            1,
            _publisher,
            updatedBond1.issuer,
            version1TokenId,
            _tokenAddr,
            updatedBond1.currency._currencyToBytes3(),
            updatedBond1.bondNominalValue,
            updatedBond1.maxSupply,
            updatedBond1.maturityDate,
            updatedBond1.couponFrequency,
            updatedBond1.couponRateType,
            updatedBond1.isGuaranteed,
            updatedBond1.issuanceCountry
        );
        _br.updatePublishedBond(updatedBond1, 1);

        // Second update: amends version 1 in place again
        BondInput memory updatedBond2 = updatedBond1;
        updatedBond2.bondNominalValue = 3 * _newBondFT.bondNominalValue;
        vm.prank(_publisher);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.PublishedBondUpdated(
            _newBondFT.isin._isinToBytes12(),
            1,
            _publisher,
            updatedBond2.issuer,
            version1TokenId,
            _tokenAddr,
            updatedBond2.currency._currencyToBytes3(),
            updatedBond2.bondNominalValue,
            updatedBond2.maxSupply,
            updatedBond2.maturityDate,
            updatedBond2.couponFrequency,
            updatedBond2.couponRateType,
            updatedBond2.isGuaranteed,
            updatedBond2.issuanceCountry
        );
        _br.updatePublishedBond(updatedBond2, 1);

        // ASSERT: Bond at version 1 should have the second update values
        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(bond.bondNominalValue, updatedBond2.bondNominalValue);

        // TokenId stays the same — amendments don't create new versions
        uint256 currentTokenId = _br.getTokenId(_newBondFT.isin);
        assertEq(currentTokenId, version1TokenId);

        // Only one version exists — active and latest both remain at 1
        assertEq(_br.getActiveVersion(_newBondFT.isin._isinToBytes12()), 1);
        assertEq(_br.getLatestVersion(_newBondFT.isin._isinToBytes12()), 1);
    }

    function test_updatePublishedBond_revert_invalidCurrency() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.currency = "XYZ"; // Not allowed currency

        // ACT & ASSERT
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__InvalidCurrency.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_success_changeCurrencyToAllowedEuropeanCurrency() public {
        string memory newCurrency = "CZK";

        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_currencyOperator);
        _br.setAllowedCurrency(newCurrency, true);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.currency = newCurrency;

        vm.prank(_publisher);
        _br.updatePublishedBond(updatedBond, 1);

        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(bond.currency, newCurrency._currencyToBytes3());
    }

    function test_updatePublishedBond_success_unchangedCurrencyAfterRemoval() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_currencyOperator);
        _br.setAllowedCurrency(_newBondFT.currency, false);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.maxSupply = _newBondFT.maxSupply + 1;

        vm.prank(_publisher);
        _br.updatePublishedBond(updatedBond, 1);

        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(bond.currency, _newBondFT.currency._currencyToBytes3());
        assertEq(bond.maxSupply, updatedBond.maxSupply);
    }

    function test_updatePublishedBond_revert_isinWithControlChar() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.isin = "SK00010020\n9";

        vm.prank(_publisher);
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_currencyWithLowercase() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.currency = "usd";

        vm.prank(_publisher);
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_maxSupplyIsZero() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.maxSupply = 0;

        // ACT & ASSERT
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__MaxSupplyIsZero.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_maturityDateExpired() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.maturityDate = block.timestamp - 1;

        // ACT & ASSERT
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__MaturityDateExpired.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_couponRatesLengthMismatch() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.couponRates.paymentTimestamps = new uint256[](3);
        updatedBond.couponRates.rates = new uint256[](2);

        // ACT & ASSERT
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__CouponRatesLengthMismatch.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_zeroCouponWithNonEmptyRates() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.couponRateType = CouponRateType.ZERO_COUPON;
        // Zero coupon should have empty arrays but we provide non-empty
        uint256[] memory paymentTimestamps = new uint256[](2);
        paymentTimestamps[0] = 1;
        paymentTimestamps[1] = 2;
        uint256[] memory rates = new uint256[](2);
        rates[0] = 1000;
        rates[1] = 0;
        updatedBond.couponRates = CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});

        // ACT & ASSERT
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__CouponRatesUnexpectedLength.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_fixedCouponWrongLength() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.couponRateType = CouponRateType.FIXED;
        // Fixed coupon requires exactly 2 elements, provide 3
        uint256[] memory paymentTimestamps = new uint256[](3);
        paymentTimestamps[0] = 1;
        paymentTimestamps[1] = 13;
        paymentTimestamps[2] = 25;
        uint256[] memory rates = new uint256[](3);
        rates[0] = 1000;
        rates[1] = 1000;
        rates[2] = 0;
        updatedBond.couponRates = CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});

        // ACT & ASSERT
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__CouponRatesUnexpectedLength.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_floatingCouponTooFewElements() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.couponRateType = CouponRateType.FLOATING;
        // Floating coupon requires at least 2 elements, provide 1
        uint256[] memory paymentTimestamps = new uint256[](1);
        paymentTimestamps[0] = 1;
        uint256[] memory rates = new uint256[](1);
        rates[0] = 0;
        updatedBond.couponRates = CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});

        // ACT & ASSERT
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__CouponRatesUnexpectedLength.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_paymentTimestampZero() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        // First payment timestamp is 0
        uint256[] memory paymentTimestamps = new uint256[](2);
        paymentTimestamps[0] = 0; // Invalid: first timestamp cannot be 0
        paymentTimestamps[1] = 2;
        uint256[] memory rates = new uint256[](2);
        rates[0] = 1000;
        rates[1] = 0;
        updatedBond.couponRates = CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});

        // ACT & ASSERT
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__PaymentTimestampZero.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_paymentTimestampAfterMaturity() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.couponRates.paymentTimestamps[1] = updatedBond.maturityDate + 1;

        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__PaymentTimestampAfterMaturity.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_lastRateNotZero() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        // Last rate must be 0
        uint256[] memory paymentTimestamps = new uint256[](2);
        paymentTimestamps[0] = 1;
        paymentTimestamps[1] = 13;
        uint256[] memory rates = new uint256[](2);
        rates[0] = 1000;
        rates[1] = 500; // Invalid: last rate must be 0
        updatedBond.couponRates = CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});

        // ACT & ASSERT
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__CouponRatesLastRateNotZero.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_paymentTimestampsUnordered() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.couponRateType = CouponRateType.FLOATING;
        // Payment intervals must be in ascending order
        uint256[] memory paymentTimestamps = new uint256[](3);
        paymentTimestamps[0] = 10;
        paymentTimestamps[1] = 5; // Invalid: 5 < 10, not ascending
        paymentTimestamps[2] = 20;
        uint256[] memory rates = new uint256[](3);
        rates[0] = 1000;
        rates[1] = 1200;
        rates[2] = 0;
        updatedBond.couponRates = CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});

        // ACT & ASSERT
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__PaymentTimestampsUnordered.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_equalConsecutivePaymentTimestamps() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.couponRateType = CouponRateType.FLOATING;
        // Equal consecutive timestamps are not allowed (must be strictly ascending)
        uint256[] memory paymentTimestamps = new uint256[](3);
        paymentTimestamps[0] = 1;
        paymentTimestamps[1] = 1; // equal to previous — must be strictly greater
        paymentTimestamps[2] = 13;
        uint256[] memory rates = new uint256[](3);
        rates[0] = 1000;
        rates[1] = 1200;
        rates[2] = 0;
        updatedBond.couponRates = CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});

        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__PaymentTimestampsUnordered.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_couponRatesDuplicateWithEqualIntervals() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.couponRateType = CouponRateType.FLOATING;
        uint256[] memory paymentTimestamps = new uint256[](3);
        paymentTimestamps[0] = 1;
        paymentTimestamps[1] = 1;
        paymentTimestamps[2] = 13;
        uint256[] memory rates = new uint256[](3);
        rates[0] = 1000;
        rates[1] = 1000;
        rates[2] = 0;
        updatedBond.couponRates = CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});

        // ACT & ASSERT: Equal consecutive intervals fail ordering checks before duplicate-rate checks.
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__PaymentTimestampsUnordered.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_equalConsecutivePaymentTimestamps_fixed() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.couponRateType = CouponRateType.FIXED;
        // FIXED bond with [x, x] — the NM-004 scenario
        uint256[] memory paymentTimestamps = new uint256[](2);
        paymentTimestamps[0] = 13;
        paymentTimestamps[1] = 13; // equal — must be strictly greater
        uint256[] memory rates = new uint256[](2);
        rates[0] = 500;
        rates[1] = 0;
        updatedBond.couponRates = CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});

        // ACT & ASSERT
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__PaymentTimestampsUnordered.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_duplicateAdjacentCouponRates() public {
        // ARRANGE: Publish a new bond first
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.couponRateType = CouponRateType.FLOATING;
        uint256[] memory paymentTimestamps = new uint256[](3);
        paymentTimestamps[0] = 1;
        paymentTimestamps[1] = 2;
        paymentTimestamps[2] = 13;
        uint256[] memory rates = new uint256[](3);
        rates[0] = 1000;
        rates[1] = 1000;
        rates[2] = 0;
        updatedBond.couponRates = CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});

        // ACT & ASSERT
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__CouponRatesDuplicate.selector);
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_bondSuspended() public {
        // ARRANGE: Publish and issue a bond, then suspend it
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, BOND_MAX_SUPPLY);

        vm.prank(_suspendOperator);
        _br.suspendBond(_newBondFT.isin, 1);

        BondInput memory updatedBond = _newBondFT;

        // ACT & ASSERT: Cannot update a suspended bond
        vm.prank(_publisher);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, _newBondFT.isin._isinToBytes12())
        );
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_bondCancelled() public {
        // ARRANGE: Publish then cancel a bond
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);
        vm.prank(_cancelOperator);
        _br.cancelBond(_newBondFT.isin, 1);

        BondInput memory updatedBond = _newBondFT;

        // ACT & ASSERT: Cannot update a cancelled bond
        vm.prank(_publisher);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, _newBondFT.isin._isinToBytes12())
        );
        _br.updatePublishedBond(updatedBond, 1);
    }

    function test_updatePublishedBond_revert_bondRedeemed() public {
        // Note: Using _bondFT which is already issued in the fixture
        // Burn all tokens then close/redeem the bond
        uint256 supply = IDEUSSToken(_tokenAddr).totalSupply(_bondFTId);
        vm.prank(_brAddr);
        IDEUSSToken(_tokenAddr).burn(_cwAddr, _bondFTId, supply);
        vm.prank(_closeOperator);
        _br.closeBond(_bondFT.isin, 1);

        BondInput memory updatedBond = _bondFT;

        // ACT & ASSERT: Cannot update a closed bond
        vm.prank(_publisher);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, _bondFT.isin._isinToBytes12())
        );
        _br.updatePublishedBond(updatedBond, 1);
    }

    /*//////////////////////////////////////////////////////////////
                                issueBond
    //////////////////////////////////////////////////////////////*/
    function test_issueBond_success() public {
        // ARRANGE: Publish a new bond
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_newBondFT.issuer, _newBondFTId), 0);
        assertEq(IDEUSSToken(_tokenAddr).totalSupply(_newBondFTId), 0);

        // ACT: Issue bond
        vm.prank(_publisher);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.BondIssued(_newBondFT.isin._isinToBytes12(), _newBondFTId, BOND_MAX_SUPPLY, 1, 1, _publisher);
        _br.issueBond(_newBondFT.isin, 1, BOND_MAX_SUPPLY);

        // ASSERT
        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(uint256(bond.status), uint256(BondStatus.Issued));
        assertEq(bond.trancheCount, 1);
        assertEq(bond.mintedSupply, BOND_MAX_SUPPLY);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_newBondFT.issuer, _newBondFTId), BOND_MAX_SUPPLY);
        assertEq(IDEUSSToken(_tokenAddr).totalSupply(_newBondFTId), BOND_MAX_SUPPLY);
    }

    function test_issueBond_revert_unauthorizedCaller() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        address arbitraryCaller = makeAddr("arbitraryCaller");

        vm.prank(arbitraryCaller);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__UnauthorizedIssuer.selector, arbitraryCaller));
        _br.issueBond(_newBondFT.isin, 1, BOND_MAX_SUPPLY);
    }

    function test_issueBond_reverts_whenIssuerDisabled() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_erAdmin);
        _er.setAccountStatus(_newBondFT.issuer, AccountStatus.DISABLED, "");

        vm.prank(_newBondFT.issuer);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__IssuerNotEnabled.selector, _newBondFT.issuer));
        _br.issueBond(_newBondFT.isin, 1, BOND_MAX_SUPPLY);
    }

    function test_issueBond_reverts_whenDisabledIssuerAlsoPublisher() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);
        _grantBondRegistryRoles(_newBondFT.issuer, _br.PUBLISHER());

        vm.prank(_erAdmin);
        _er.setAccountStatus(_newBondFT.issuer, AccountStatus.DISABLED, "");

        vm.prank(_newBondFT.issuer);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__IssuerNotEnabled.selector, _newBondFT.issuer));
        _br.issueBond(_newBondFT.isin, 1, BOND_MAX_SUPPLY);
    }

    function test_issueBond_success_afterUpdatePublishedBond() public {
        // ARRANGE: Publish a new bond
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        // Update the published bond with new bondNominalValue
        BondInput memory updatedBond = _newBondFT;
        updatedBond.bondNominalValue = 2 * _newBondFT.bondNominalValue;
        updatedBond.maxSupply = 10 * BOND_MAX_SUPPLY;

        vm.prank(_publisher);
        _br.updatePublishedBond(updatedBond, 1);

        // updatePublishedBond amends v1 in place, tokenId stays the same
        uint256 updatedBondFTId = _newBondFTId;

        // ACT: Issue bond after update — still version 1, same tokenId
        vm.prank(_publisher);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.BondIssued(
            _newBondFT.isin._isinToBytes12(), updatedBondFTId, updatedBond.maxSupply, 1, 1, _publisher
        );
        _br.issueBond(_newBondFT.isin, 1, updatedBond.maxSupply);

        // ASSERT: Bond should be issued with updated parameters
        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(uint256(bond.status), uint256(BondStatus.Issued));
        assertEq(bond.bondNominalValue, updatedBond.bondNominalValue);
        assertEq(bond.mintedSupply, updatedBond.maxSupply);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_newBondFT.issuer, updatedBondFTId), updatedBond.maxSupply);
        assertEq(IDEUSSToken(_tokenAddr).totalSupply(updatedBondFTId), updatedBond.maxSupply);
    }

    function test_issueBond_success_decrementsRemainingIssuableSupply() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 3_000);

        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(bond.mintedSupply, 3_000);
        assertEq(bond.remainingIssuableSupply, BOND_MAX_SUPPLY - 3_000);
        assertFalse(bond.issuanceClosed);
    }

    function test_issueBond_reverts_issuanceClosed() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 3_000);

        vm.prank(_newBondFT.issuer);
        _br.closeIssuance(_newBondFT.isin, 1);

        vm.prank(_publisher);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__IssuanceClosed.selector, _newBondFT.isin._isinToBytes12())
        );
        _br.issueBond(_newBondFT.isin, 1, 1);
    }

    function test_issueBond_revert_nonExistentBond() public {
        // ACT & ASSERT: Expect revert when bond does not exist
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, _newBondFT.isin._isinToBytes12())
        );
        _br.issueBond(_newBondFT.isin, 1, 1000);
    }

    function test_issueBond_revert_zeroAmount() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__IssuanceAmountIsZero.selector);
        _br.issueBond(_newBondFT.isin, 1, 0);
    }

    function test_issueBond_revert_bondSuspended() public {
        // ARRANGE: Publish a new bond, issue it, then suspend it
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, BOND_MAX_SUPPLY);

        vm.prank(_suspendOperator);
        _br.suspendBond(_newBondFT.isin, 1);

        // ACT & ASSERT: Expect revert when bond is suspended
        vm.prank(_publisher);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, _newBondFT.isin._isinToBytes12())
        );
        _br.issueBond(_newBondFT.isin, 1, 1);
    }

    function test_issueBond_revert_timestampAfterMaturityDate() public {
        // ARRANGE
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.warp(_newBondFT.maturityDate);

        // ACT & ASSERT: Expect revert when the bond is issued after maturity date
        vm.prank(_publisher);
        vm.expectRevert(Errors.BondRegistry__MaturityDateExpired.selector);
        _br.issueBond(_newBondFT.isin, 1, BOND_MAX_SUPPLY);
    }

    function test_issueBond_success_twoTranches() public {
        // ARRANGE: Publish a new bond
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();
        uint256 amount1 = 3_000;
        uint256 amount2 = 4_000;

        // ACT: First tranche
        vm.prank(_publisher);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.BondIssued(isinBytes, _newBondFTId, amount1, 1, 1, _publisher);
        _br.issueBond(_newBondFT.isin, 1, amount1);

        // ASSERT after first tranche
        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(bond.trancheCount, 1);
        assertEq(bond.mintedSupply, amount1);
        assertEq(uint256(bond.status), uint256(BondStatus.Issued));

        // ACT: Second tranche issued from Issued status
        vm.prank(_publisher);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.BondIssued(isinBytes, _newBondFTId, amount2, 2, 1, _publisher);
        _br.issueBond(_newBondFT.isin, 1, amount2);

        // ASSERT after second tranche
        bond = _br.getBond(_newBondFT.isin);
        assertEq(bond.trancheCount, 2);
        assertEq(bond.mintedSupply, amount1 + amount2);
        assertEq(uint256(bond.status), uint256(BondStatus.Issued));
        assertEq(bond.tokenId, _newBondFTId);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_newBondFT.issuer, _newBondFTId), amount1 + amount2);
        assertEq(IDEUSSToken(_tokenAddr).totalSupply(_newBondFTId), amount1 + amount2);
    }

    function test_issueBond_success_mintedSupplyInvariantThreeTranches() public {
        // ARRANGE
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        uint256 amount1 = 2_000;
        uint256 amount2 = 3_000;
        uint256 amount3 = 1_000;

        // ACT: Issue three tranches
        vm.startPrank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, amount1);
        _br.issueBond(_newBondFT.isin, 1, amount2);
        _br.issueBond(_newBondFT.isin, 1, amount3);
        vm.stopPrank();

        // ASSERT: mintedSupply == sum of all tranche issueCounts
        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(bond.trancheCount, 3);
        assertEq(bond.mintedSupply, amount1 + amount2 + amount3);

        Tranche memory t1 = _br.getTranche(_newBondFT.isin._isinToBytes12(), 1);
        Tranche memory t2 = _br.getTranche(_newBondFT.isin._isinToBytes12(), 2);
        Tranche memory t3 = _br.getTranche(_newBondFT.isin._isinToBytes12(), 3);
        assertEq(t1.issueCount, amount1);
        assertEq(t2.issueCount, amount2);
        assertEq(t3.issueCount, amount3);
        assertEq(t1.issueCount + t2.issueCount + t3.issueCount, bond.mintedSupply);
    }

    function test_issueBond_revert_capExceededOnSecondTranche() public {
        // ARRANGE: Issue first tranche consuming most of the cap
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        uint256 firstAmount = 8_000;
        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, firstAmount);

        // ACT & ASSERT: Second tranche exceeds remaining cap (2_000 left, requesting 3_000)
        uint256 excessAmount = 3_000;
        vm.prank(_publisher);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.BondRegistry__MaxSupplyExceeded.selector, excessAmount, BOND_MAX_SUPPLY - firstAmount
            )
        );
        _br.issueBond(_newBondFT.isin, 1, excessAmount);
    }

    function test_issueBond_success_sameTokenIdAcrossTranches() public {
        // ARRANGE
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        // ACT: Issue two tranches
        vm.startPrank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 3_000);
        _br.issueBond(_newBondFT.isin, 1, 3_000);
        vm.stopPrank();

        // ASSERT: Both tranches minted into the same tokenId
        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(bond.tokenId, _newBondFTId);
        assertEq(bond.trancheCount, 2);
        assertEq(IDEUSSToken(_tokenAddr).totalSupply(_newBondFTId), 6_000);
    }

    function test_issueBond_success_issuerCanIssueSubsequentTranches() public {
        // ARRANGE: issuer (bond.issuer = _cwAddr) can also call issueBond
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        // ACT: First tranche by publisher, second by issuer directly
        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 2_000);

        vm.prank(_newBondFT.issuer);
        _br.issueBond(_newBondFT.isin, 1, 2_000);

        // ASSERT
        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertEq(bond.trancheCount, 2);
        assertEq(bond.mintedSupply, 4_000);
    }

    /*//////////////////////////////////////////////////////////////
                        setAllowedCurrency
    //////////////////////////////////////////////////////////////*/
    function test_setAllowedCurrency_success_enable() public {
        // ARRANGE
        string memory newCurrency = "USD";

        assertFalse(_br.isCurrencyAllowed(newCurrency));

        // ACT: Add a new currency
        vm.prank(_currencyOperator);
        emit IBondRegistry.AllowedCurrencyUpdated(newCurrency._currencyToBytes3(), true, _currencyOperator);
        _br.setAllowedCurrency(newCurrency, true);

        assertTrue(_br.isCurrencyAllowed(newCurrency));
    }

    function test_setAllowedCurrency_success_disable() public {
        // ARRANGE
        string memory newCurrency = "USD";

        assertFalse(_br.isCurrencyAllowed(newCurrency));

        // ACT: Add a new currency
        vm.startPrank(_currencyOperator);
        _br.setAllowedCurrency(newCurrency, true);

        assertTrue(_br.isCurrencyAllowed(newCurrency));

        emit IBondRegistry.AllowedCurrencyUpdated(newCurrency._currencyToBytes3(), false, _currencyOperator);
        _br.setAllowedCurrency(newCurrency, false);
        vm.stopPrank();

        assertFalse(_br.isCurrencyAllowed(newCurrency));
    }

    function test_setAllowedCurrency_revert_unauthorizedCaller() public {
        // ARRANGE
        string memory newCurrency = "USD";

        assertFalse(_br.isCurrencyAllowed(newCurrency));

        // ACT & ASSERT: Expect revert when caller does not have `CURRENCY`
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.setAllowedCurrency(newCurrency, true);
    }

    function test_setAllowedCurrency_revert_wrongAuthorizedRole() public {
        string memory newCurrency = "USD";

        vm.prank(_cancelOperator);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.setAllowedCurrency(newCurrency, true);
    }

    function test_isCurrencyAllowed_revert_currencyWithLowercase() public {
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _br.isCurrencyAllowed("usd");
    }

    function test_setAllowedCurrency_revert_currencyWithControlChar() public {
        vm.prank(_currencyOperator);
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _br.setAllowedCurrency("EU\n", true);
    }

    function test_setAllowedCurrency_revert_currencyWithLowercase() public {
        vm.prank(_currencyOperator);
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _br.setAllowedCurrency("usd", true);
    }

    function test_setAllowedCurrency_revert_currencyWithDigit() public {
        vm.prank(_currencyOperator);
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _br.setAllowedCurrency("EU1", true);
    }

    /*//////////////////////////////////////////////////////////////
                                suspendBond
    //////////////////////////////////////////////////////////////*/
    function test_suspendBond_success() public {
        // ACT: Suspend bond
        vm.prank(_suspendOperator);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.BondSuspended(_bondFT.isin._isinToBytes12(), INITIAL_VERSION, _suspendOperator);
        _br.suspendBond(_bondFT.isin, 1);

        // ASSERT
        assertEq(uint256(_br.bondStatus(_bondFT.isin)), uint256(BondStatus.Suspended));
        assertTrue(IBaseToken(_tokenAddr).isTokenPaused(_bondFTId));
    }

    function test_suspendBond_revert_unauthorizedCaller() public {
        // ACT & ASSERT: Expect revert when caller does not have `SUSPEND`
        vm.prank(_notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.suspendBond(_bondFT.isin, 1);
    }

    function test_suspendBond_revert_wrongAuthorizedRole() public {
        vm.prank(_publisher);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.suspendBond(_bondFT.isin, 1);
    }

    function test_suspendBond_revert_nonExistentBond() public {
        // ACT & ASSERT: Expect revert when the bond does not exist for ISIN
        vm.prank(_suspendOperator);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, _newBondFT.isin._isinToBytes12())
        );
        _br.suspendBond(_newBondFT.isin, 1);
    }

    function test_suspendBond_revert_invalidBondStatus() public {
        // ARRANGE: Publish a new bond but don't issue it
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        // ACT & ASSERT: Expect a revert when the ISIN is not issued
        vm.prank(_suspendOperator);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, _newBondFT.isin._isinToBytes12())
        );
        _br.suspendBond(_newBondFT.isin, 1);
    }

    function test_suspendBond_success_contractPaused() public {
        // ARRANGE: Activate the global emergency pause first.
        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ACT: Per-bond suspension can still be curated while the token is globally paused.
        vm.prank(_suspendOperator);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.BondSuspended(_bondFT.isin._isinToBytes12(), INITIAL_VERSION, _suspendOperator);
        _br.suspendBond(_bondFT.isin, 1);

        // ASSERT
        assertTrue(IBaseToken(_tokenAddr).paused());
        assertEq(uint256(_br.bondStatus(_bondFT.isin)), uint256(BondStatus.Suspended));
        assertTrue(IBaseToken(_tokenAddr).isTokenPaused(_bondFTId));
    }

    /*//////////////////////////////////////////////////////////////
                                unsuspendBond
    //////////////////////////////////////////////////////////////*/
    function test_unsuspendBond_success() public {
        // ARRANGE: Suspend bond first
        vm.prank(_suspendOperator);
        _br.suspendBond(_bondFT.isin, 1);

        assertEq(uint256(_br.bondStatus(_bondFT.isin)), uint256(BondStatus.Suspended));

        // ACT: Unsuspend bond
        vm.prank(_unsuspendOperator);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.BondUnsuspended(_bondFT.isin._isinToBytes12(), INITIAL_VERSION, _unsuspendOperator);
        _br.unsuspendBond(_bondFT.isin, 1);

        // ASSERT
        assertEq(uint256(_br.bondStatus(_bondFT.isin)), uint256(BondStatus.Issued));
        assertFalse(IBaseToken(_tokenAddr).paused());
    }

    function test_unsuspendBond_revert_unauthorizedCaller() public {
        // ACT & ASSERT: Expect revert when caller does not have `UNSUSPEND`
        vm.prank(_notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.unsuspendBond(_bondFT.isin, 1);
    }

    function test_unsuspendBond_revert_wrongAuthorizedRole() public {
        vm.prank(_suspendOperator);
        _br.suspendBond(_bondFT.isin, 1);

        vm.prank(_suspendOperator);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.unsuspendBond(_bondFT.isin, 1);
    }

    function test_unsuspendBond_revert_nonExistentBond() public {
        // ACT & ASSERT: Expect revert when the bond does not exist for ISIN
        vm.prank(_unsuspendOperator);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, _newBondFT.isin._isinToBytes12())
        );
        _br.unsuspendBond(_newBondFT.isin, 1);
    }

    function test_unsuspendBond_revert_invalidBondStatus() public {
        // ACT & ASSERT: Expect a revert when the ISIN is not suspended.
        vm.prank(_unsuspendOperator);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, _bondFT.isin._isinToBytes12())
        );
        _br.unsuspendBond(_bondFT.isin, 1);
    }

    function test_unsuspendBond_revert_contractPaused() public {
        // ARRANGE: Suspend first, then activate the global emergency pause.
        vm.prank(_suspendOperator);
        _br.suspendBond(_bondFT.isin, 1);

        _timelockOp(_tokenAddr, abi.encodeWithSelector(IBaseToken.pause.selector));

        // ACT & ASSERT: Unsuspension cannot weaken per-tokenId controls during global pause.
        vm.prank(_unsuspendOperator);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        _br.unsuspendBond(_bondFT.isin, 1);

        assertEq(uint256(_br.bondStatus(_bondFT.isin)), uint256(BondStatus.Suspended));
        assertTrue(IBaseToken(_tokenAddr).isTokenPaused(_bondFTId));
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    function test_bondStatus() public view {
        // success
        assertEq(uint256(_br.bondStatus(BOND_ISIN_ERC6909_FT._isinToBytes12())), uint256(BondStatus.Issued));
    }

    function test_bondStatus_nonExistentBond_returnsUnregistered() public view {
        // For non-existent bonds, bondStatus returns BondStatus.Unregistered (default value 0)
        assertEq(uint256(_br.bondStatus(NON_EXISTENT_ISIN._isinToBytes12())), uint256(BondStatus.Unregistered));
    }

    function test_getCouponRateAt_fixedRate() public view {
        // success
        assertEq(_br.getCouponRateAt(BOND_ISIN_ERC6909_FT, block.timestamp), BOND_COUPON_RATE);
    }

    function test_getCouponRateAt_success_returnsZeroAtMaturity() public view {
        assertEq(_br.getCouponRateAt(BOND_ISIN_ERC6909_FT, _maturityDate), 0);
        assertEq(_br.getCouponRateAt(BOND_ISIN_ERC6909_FT, _maturityDate + 1), 0);
    }

    function test_getCouponRateAt_floatingRates_allIntervalsAccessible() public {
        // ARRANGE: publish a floating bond with strictly-ascending timestamp checkpoints.
        BondInput memory floatingBond = _newBondFT;
        floatingBond.couponRateType = CouponRateType.FLOATING;
        uint256 start = block.timestamp;
        uint256[] memory paymentTimestamps = new uint256[](4);
        paymentTimestamps[0] = start;
        paymentTimestamps[1] = start + 100 days;
        paymentTimestamps[2] = start + 200 days;
        paymentTimestamps[3] = start + 300 days;
        uint256[] memory rates = new uint256[](4);
        rates[0] = 1000;
        rates[1] = 1200;
        rates[2] = 1500;
        rates[3] = 0;
        floatingBond.couponRates = CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});

        vm.prank(_publisher);
        _br.publishBond(floatingBond);

        // ACT & ASSERT: each boundary returns the rate that starts at that timestamp.
        assertEq(_br.getCouponRateAt(floatingBond.isin, start), 1000);
        assertEq(_br.getCouponRateAt(floatingBond.isin, start + 50 days), 1000);
        assertEq(_br.getCouponRateAt(floatingBond.isin, start + 100 days), 1200);
        assertEq(_br.getCouponRateAt(floatingBond.isin, start + 150 days), 1200);
        assertEq(_br.getCouponRateAt(floatingBond.isin, start + 200 days), 1500);
        assertEq(_br.getCouponRateAt(floatingBond.isin, start + 300 days - 1), 1500);
        assertEq(_br.getCouponRateAt(floatingBond.isin, start + 300 days), 0);
        assertEq(_br.getCouponRateAt(floatingBond.isin, start - 1), 0);
    }

    function test_getCouponRateAt_revert_nonExistentBond() public {
        // fail
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, NON_EXISTENT_ISIN._isinToBytes12())
        );
        _br.getCouponRateAt(NON_EXISTENT_ISIN, 1);
    }

    function test_getLatestCouponRate() public view {
        // success
        assertEq(_br.getLatestCouponRate(BOND_ISIN_ERC6909_FT), BOND_COUPON_RATE);
    }

    function test_getLatestCouponRate_zeroCoupon() public {
        // ARRANGE: publish a zero-coupon bond (empty rates array → length == 0 < 2)
        BondInput memory zeroCouponBond = _newBondFT;
        zeroCouponBond.couponRateType = CouponRateType.ZERO_COUPON;
        zeroCouponBond.couponRates = CouponRates({paymentTimestamps: new uint256[](0), rates: new uint256[](0)});

        vm.prank(_publisher);
        _br.publishBond(zeroCouponBond);

        // ACT & ASSERT: Expect 0 returned when rates array length < 2
        assertEq(_br.getLatestCouponRate(zeroCouponBond.isin), 0);
    }

    function test_getLatestCouponRate_revert_nonExistentBond() public {
        // fail
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, NON_EXISTENT_ISIN._isinToBytes12())
        );
        _br.getLatestCouponRate(NON_EXISTENT_ISIN);
    }

    function test_getAllCouponRates() public view {
        // success
        (uint256[] memory paymentTimestamps, uint256[] memory rates) = _br.getAllCouponRates(BOND_ISIN_ERC6909_FT);
        assertEq(paymentTimestamps.length, 2);
        assertEq(rates.length, 2);
        assertEq(rates[0], BOND_COUPON_RATE);
    }

    function test_getAllCouponRates_revert_nonExistentBond() public {
        // fail
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, NON_EXISTENT_ISIN._isinToBytes12())
        );
        _br.getAllCouponRates(NON_EXISTENT_ISIN);
    }

    function test_getCouponRatesLength() public view {
        // success
        assertEq(_br.getCouponRatesLength(BOND_ISIN_ERC6909_FT), 2);
    }

    function test_getCouponRatesLength_revert_nonExistentBond() public {
        // fail
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, NON_EXISTENT_ISIN._isinToBytes12())
        );
        _br.getCouponRatesLength(NON_EXISTENT_ISIN);
    }

    function test_getBond_success_byString() public view {
        Bond memory bond = _br.getBond(BOND_ISIN_ERC6909_FT);
        assertEq(bond.isin, BOND_ISIN_ERC6909_FT._isinToBytes12());
        assertEq(bond.tokenAddress, _tokenAddr);
        assertEq(uint256(bond.couponFrequency), uint256(CouponFrequency.Annual));
        assertEq(uint8(bond.couponRateType), uint8(BOND_COUPON_RATE_TYPE));
        assertEq(bond.currency, BOND_CURRENCY._currencyToBytes3());
        assertEq(bond.bondNominalValue, BOND_NOMINAL_VALUE);
        assertEq(bond.maturityDate, _maturityDate);
        assertEq(uint256(bond.issuanceCountry), uint256(BOND_ISSUANCE_COUNTRY));
    }

    function test_getBond_success_byBytes12() public view {
        Bond memory bond = _br.getBond(BOND_ISIN_ERC6909_FT._isinToBytes12());
        assertEq(bond.isin, BOND_ISIN_ERC6909_FT._isinToBytes12());
        assertEq(bond.tokenAddress, _tokenAddr);
        assertEq(uint256(bond.issuanceCountry), uint256(BOND_ISSUANCE_COUNTRY));
    }

    function test_getBond_revert_nonExistentBond() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, NON_EXISTENT_ISIN._isinToBytes12())
        );
        _br.getBond(NON_EXISTENT_ISIN);
    }

    function test_getBondAtVersion_success() public {
        // ARRANGE: Publish a new bond (version 1) and then amend it in-place
        vm.startPrank(_publisher);
        _br.publishBond(_newBondFT);

        Bond memory version1Before = _br.getBondAtVersion(_newBondFT.isin._isinToBytes12(), 1);
        assertEq(version1Before.bondNominalValue, _newBondFT.bondNominalValue);

        BondInput memory updatedBond = _newBondFT;
        updatedBond.bondNominalValue = 2 * _newBondFT.bondNominalValue;

        _br.updatePublishedBond(updatedBond, 1);
        vm.stopPrank();

        // ASSERT: updatePublishedBond amends version 1 in-place; bondNominalValue is updated
        Bond memory version1After = _br.getBondAtVersion(_newBondFT.isin._isinToBytes12(), 1);
        assertEq(version1After.bondNominalValue, updatedBond.bondNominalValue);
        assertEq(uint256(version1After.issuanceCountry), uint256(updatedBond.issuanceCountry));
    }

    function test_getBondAtVersion_revert_nonExistentBond() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, NON_EXISTENT_ISIN._isinToBytes12())
        );
        _br.getBondAtVersion(NON_EXISTENT_ISIN._isinToBytes12(), 1);
    }

    function test_getBondByTokenId_success() public view {
        Bond memory bond = _br.getBondByTokenId(_bondFTId);
        assertEq(bond.isin, BOND_ISIN_ERC6909_FT._isinToBytes12());
        assertEq(bond.tokenId, _bondFTId);
        assertEq(uint8(bond.status), uint8(BondStatus.Issued));
        assertEq(uint256(bond.issuanceCountry), uint256(BOND_ISSUANCE_COUNTRY));
    }

    function test_getBondViews_returnPersistedIsGuaranteed() public {
        BondInput memory guaranteedBond = _newBondFT;
        guaranteedBond.isGuaranteed = true;

        vm.prank(_publisher);
        _br.publishBond(guaranteedBond);

        bytes12 isinBytes = guaranteedBond.isin._isinToBytes12();
        uint256 tokenId = _br.getTokenId(guaranteedBond.isin);

        assertTrue(_br.getBond(guaranteedBond.isin).isGuaranteed);
        assertTrue(_br.getBondAtVersion(isinBytes, 1).isGuaranteed);
        assertTrue(_br.getBondByTokenId(tokenId).isGuaranteed);
    }

    function test_getBondByTokenId_revert_nonExistentBond() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, bytes12(0)));
        _br.getBondByTokenId(type(uint256).max);
    }

    function test_getBondSeriesByTokenId_success() public view {
        (bytes12 isin, uint8 version) = _br.getBondSeriesByTokenId(_bondFTId);
        assertEq(isin, BOND_ISIN_ERC6909_FT._isinToBytes12());
        assertEq(version, 1);
    }

    function test_getBondSeriesByTokenId_revert_nonExistentBond() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, bytes12(0)));
        _br.getBondSeriesByTokenId(type(uint256).max);
    }

    function test_getTokenId_success() public view {
        uint256 tokenId = _br.getTokenId(BOND_ISIN_ERC6909_FT);
        assertEq(tokenId, _bondFTId);
    }

    function test_getTokenId_revert_nonExistentBond() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, NON_EXISTENT_ISIN._isinToBytes12())
        );
        _br.getTokenId(NON_EXISTENT_ISIN);
    }

    function test_getTrancheCount_success() public view {
        // _bondFT was issued once in FTFixture setUp
        assertEq(_br.getTrancheCount(BOND_ISIN_ERC6909_FT._isinToBytes12()), 1);
    }

    function test_getTrancheCount_revert_nonExistentBond() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, NON_EXISTENT_ISIN._isinToBytes12())
        );
        _br.getTrancheCount(NON_EXISTENT_ISIN._isinToBytes12());
    }

    function test_getTrancheCount_success_multiTranche() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.startPrank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 2_000);
        _br.issueBond(_newBondFT.isin, 1, 3_000);
        vm.stopPrank();

        assertEq(_br.getTrancheCount(_newBondFT.isin._isinToBytes12()), 2);
    }

    function test_getTranche_success_byTrancheId() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 3_000);

        Tranche memory t1 = _br.getTranche(_newBondFT.isin._isinToBytes12(), 1);
        uint256 firstIssuanceTime = t1.issueDate;
        assertEq(t1.issueCount, 3_000);
        assertEq(firstIssuanceTime, block.timestamp);

        vm.warp(block.timestamp + 1 days);
        uint256 secondIssuanceTime = block.timestamp;
        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 4_000);
        Tranche memory t2 = _br.getTranche(_newBondFT.isin._isinToBytes12(), 2);
        assertEq(t2.issueCount, 4_000);
        assertEq(t2.issueDate, secondIssuanceTime);
        assertGt(t2.issueDate, t1.issueDate);
    }

    function test_getTranche_success_byVersionAndTrancheId() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 3_000);

        vm.warp(block.timestamp + 1 days);
        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 4_000);

        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();
        Tranche memory tranche = _br.getTranche(isinBytes, 1, 2);
        assertEq(tranche.issueCount, 4_000);
        assertGt(tranche.issueDate, 0);
    }

    function test_getTranche_revert_byTrancheIdInvalidId() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 3_000);

        // trancheId 0 is invalid
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidTrancheId.selector, uint16(0)));
        _br.getTranche(_newBondFT.isin._isinToBytes12(), 0);

        // trancheId beyond trancheCount is invalid
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidTrancheId.selector, uint16(2)));
        _br.getTranche(_newBondFT.isin._isinToBytes12(), 2);
    }

    function test_getTranche_revert_byVersionInvalidId() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 3_000);

        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();

        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidTrancheId.selector, uint16(0)));
        _br.getTranche(isinBytes, 1, 0);

        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidTrancheId.selector, uint16(2)));
        _br.getTranche(isinBytes, 1, 2);
    }

    function test_getTranche_revert_byTrancheIdNonExistentBond() public {
        bytes12 nonExistentIsin = NON_EXISTENT_ISIN._isinToBytes12();
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, nonExistentIsin));
        _br.getTranche(nonExistentIsin, 1);
    }

    function test_getTranche_revert_byVersionNonExistentBond() public {
        bytes12 nonExistentIsin = NON_EXISTENT_ISIN._isinToBytes12();
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, nonExistentIsin));
        _br.getTranche(nonExistentIsin, 1, 1);
    }

    function test_getLatestTranche_success() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 3_000);

        vm.warp(block.timestamp + 1 days);
        uint256 secondIssuanceTime = block.timestamp;
        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 4_000);

        Tranche memory latest = _br.getLatestTranche(_newBondFT.isin._isinToBytes12());
        assertEq(latest.issueCount, 4_000);
        assertEq(latest.issueDate, secondIssuanceTime);
    }

    function test_getLatestTranche_revert_noTranches() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        // Bond published but not yet issued — no tranches exist
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidTrancheId.selector, uint16(0)));
        _br.getLatestTranche(_newBondFT.isin._isinToBytes12());
    }

    function test_getLatestTranche_revert_nonExistentBond() public {
        bytes12 nonExistentIsin = NON_EXISTENT_ISIN._isinToBytes12();
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, nonExistentIsin));
        _br.getLatestTranche(nonExistentIsin);
    }

    function test_getTranche_success_convenienceByBytes12() public view {
        // _bondFT was issued once in FTFixture (BOND_MAX_SUPPLY tokens) — tranche 1
        Tranche memory t = _br.getTranche(BOND_ISIN_ERC6909_FT._isinToBytes12());
        assertEq(t.issueCount, BOND_MAX_SUPPLY);
    }

    function test_getTranche_success_convenienceByString() public view {
        Tranche memory t = _br.getTranche(BOND_ISIN_ERC6909_FT);
        assertEq(t.issueCount, BOND_MAX_SUPPLY);
    }

    function test_getTranche_revert_convenienceNoTranches() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        // Published but not issued — convenience getter on bytes12 should revert
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidTrancheId.selector, uint16(0)));
        _br.getTranche(_newBondFT.isin._isinToBytes12());
    }

    function test_getTranche_revert_convenienceByBytes12NonExistentBond() public {
        bytes12 nonExistentIsin = NON_EXISTENT_ISIN._isinToBytes12();
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, nonExistentIsin));
        _br.getTranche(nonExistentIsin);
    }

    function test_getTranche_revert_convenienceByStringNonExistentBond() public {
        bytes12 nonExistentIsin = NON_EXISTENT_ISIN._isinToBytes12();
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, nonExistentIsin));
        _br.getTranche(NON_EXISTENT_ISIN);
    }

    function test_getTranche_revert_convenienceByStringNoTranches() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidTrancheId.selector, uint16(0)));
        _br.getTranche(_newBondFT.isin);
    }

    /*//////////////////////////////////////////////////////////////
                              closeIssuance
    //////////////////////////////////////////////////////////////*/

    function test_closeIssuance_success_issuer() public {
        vm.prank(_bondFT.issuer);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.BondIssuanceClosed(_bondFT.isin._isinToBytes12(), INITIAL_VERSION, _bondFT.issuer);
        _br.closeIssuance(_bondFT.isin, 1);

        Bond memory bond = _br.getBond(_bondFT.isin);
        assertTrue(bond.issuanceClosed);
    }

    function test_closeIssuance_success_publisher() public {
        vm.prank(_publisher);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.BondIssuanceClosed(_bondFT.isin._isinToBytes12(), INITIAL_VERSION, _publisher);
        _br.closeIssuance(_bondFT.isin, 1);

        Bond memory bond = _br.getBond(_bondFT.isin);
        assertTrue(bond.issuanceClosed);
    }

    function test_closeIssuance_success_suspendedBond() public {
        vm.prank(_suspendOperator);
        _br.suspendBond(_bondFT.isin, 1);

        vm.prank(_bondFT.issuer);
        _br.closeIssuance(_bondFT.isin, 1);

        Bond memory bond = _br.getBond(_bondFT.isin);
        assertTrue(bond.issuanceClosed);
    }

    function test_closeIssuance_reverts_whenIssuerDisabled() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 3_000);

        vm.prank(_erAdmin);
        _er.setAccountStatus(_newBondFT.issuer, AccountStatus.DISABLED, "");

        vm.prank(_newBondFT.issuer);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__IssuerNotEnabled.selector, _newBondFT.issuer));
        _br.closeIssuance(_newBondFT.isin, 1);
    }

    function test_closeIssuance_reverts_whenDisabledIssuerAlsoPublisher() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 3_000);

        _grantBondRegistryRoles(_newBondFT.issuer, _br.PUBLISHER());

        vm.prank(_erAdmin);
        _er.setAccountStatus(_newBondFT.issuer, AccountStatus.DISABLED, "");

        vm.prank(_newBondFT.issuer);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__IssuerNotEnabled.selector, _newBondFT.issuer));
        _br.closeIssuance(_newBondFT.isin, 1);
    }

    function test_closeIssuance_success_byPublisher_whenIssuerDisabled() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 3_000);

        vm.prank(_erAdmin);
        _er.setAccountStatus(_newBondFT.issuer, AccountStatus.DISABLED, "");

        vm.prank(_publisher);
        _br.closeIssuance(_newBondFT.isin, 1);

        Bond memory bond = _br.getBond(_newBondFT.isin);
        assertTrue(bond.issuanceClosed);
    }

    function test_closeIssuance_reverts_unauthorizedCaller() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 3_000);

        vm.prank(_notOwner);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__UnauthorizedIssuanceCloser.selector, _notOwner));
        _br.closeIssuance(_newBondFT.isin, 1);
    }

    function test_closeIssuance_reverts_alreadyClosed() public {
        vm.prank(_newBondFT.issuer);
        _br.closeIssuance(_bondFT.isin, 1);

        vm.prank(_newBondFT.issuer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__IssuanceClosed.selector, _bondFT.isin._isinToBytes12())
        );
        _br.closeIssuance(_bondFT.isin, 1);
    }

    function test_closeIssuance_reverts_invalidBondStatus() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_cancelOperator);
        _br.cancelBond(_newBondFT.isin, 1);

        vm.prank(_newBondFT.issuer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, _newBondFT.isin._isinToBytes12())
        );
        _br.closeIssuance(_newBondFT.isin, 1);
    }

    function test_closeIssuance_reverts_publishedBond() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_newBondFT.issuer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, _newBondFT.isin._isinToBytes12())
        );
        _br.closeIssuance(_newBondFT.isin, 1);
    }

    function test_closeIssuance_reverts_nonExistentBondVersion() public {
        vm.prank(_newBondFT.issuer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, _bondFT.isin._isinToBytes12())
        );
        _br.closeIssuance(_bondFT.isin, 2);
    }

    /*//////////////////////////////////////////////////////////////
                              rotateIssuer
    //////////////////////////////////////////////////////////////*/

    function test_rotateIssuer_success_publishedBond() public {
        address newIssuer = makeAddr("publishedRecoveryIssuer");
        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();
        bytes32 reason = keccak256("ISSUER_RECOVERY");
        _registerWallet(newIssuer);

        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_issuerRecoveryOperator);
        vm.expectEmit(true, true, true, true, _brAddr);
        emit IBondRegistry.BondIssuerRotated(
            isinBytes, 1, _newBondFT.issuer, newIssuer, reason, _issuerRecoveryOperator
        );
        _br.rotateIssuer(_newBondFT.isin, 1, newIssuer, reason);

        assertEq(_br.getBond(_newBondFT.isin).issuer, newIssuer);
    }

    function test_rotateIssuer_success_issuedBondEnablesFutureIssuance() public {
        address newIssuer = makeAddr("issuedRecoveryIssuer");
        uint256 firstIssueAmount = 3_000;
        uint256 recoveredIssueAmount = 1;
        bytes32 reason = keccak256("ISSUER_RECOVERY");
        _registerWallet(newIssuer);

        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, firstIssueAmount);

        vm.prank(_erAdmin);
        _er.setAccountStatus(_newBondFT.issuer, AccountStatus.DISABLED, "issuer disabled");

        vm.prank(_issuerRecoveryOperator);
        _br.rotateIssuer(_newBondFT.isin, 1, newIssuer, reason);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, recoveredIssueAmount);

        assertEq(_br.getBond(_newBondFT.isin).issuer, newIssuer);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(newIssuer, _newBondFTId), recoveredIssueAmount);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_newBondFT.issuer, _newBondFTId), firstIssueAmount);
    }

    function test_rotateIssuer_success_suspendedBond() public {
        address newIssuer = makeAddr("suspendedRecoveryIssuer");
        bytes32 reason = keccak256("ISSUER_RECOVERY");
        _registerWallet(newIssuer);

        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 1);

        vm.prank(_suspendOperator);
        _br.suspendBond(_newBondFT.isin, 1);

        vm.prank(_issuerRecoveryOperator);
        _br.rotateIssuer(_newBondFT.isin, 1, newIssuer, reason);

        assertEq(_br.getBond(_newBondFT.isin).issuer, newIssuer);
    }

    function test_rotateIssuer_reverts_unauthorizedCaller() public {
        address newIssuer = makeAddr("unauthorizedRecoveryIssuer");
        _registerWallet(newIssuer);

        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_publisher);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.rotateIssuer(_newBondFT.isin, 1, newIssuer, keccak256("ISSUER_RECOVERY"));
    }

    function test_rotateIssuer_reverts_nonExistentBondVersion() public {
        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();
        address newIssuer = makeAddr("nonExistentRecoveryIssuer");
        _registerWallet(newIssuer);

        vm.prank(_issuerRecoveryOperator);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, isinBytes));
        _br.rotateIssuer(_newBondFT.isin, 1, newIssuer, keccak256("ISSUER_RECOVERY"));
    }

    function test_rotateIssuer_reverts_cancelledBond() public {
        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();
        address newIssuer = makeAddr("cancelledRecoveryIssuer");
        _registerWallet(newIssuer);

        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_cancelOperator);
        _br.cancelBond(_newBondFT.isin, 1);

        vm.prank(_issuerRecoveryOperator);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, isinBytes));
        _br.rotateIssuer(_newBondFT.isin, 1, newIssuer, keccak256("ISSUER_RECOVERY"));
    }

    function test_rotateIssuer_reverts_redeemedBond() public {
        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();
        address newIssuer = makeAddr("redeemedRecoveryIssuer");
        _registerWallet(newIssuer);

        vm.prank(_publisher);
        _br.publishBond(_newBondFT);
        _setBondStatus(isinBytes, 1, BondStatus.Redeemed);

        vm.prank(_issuerRecoveryOperator);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, isinBytes));
        _br.rotateIssuer(_newBondFT.isin, 1, newIssuer, keccak256("ISSUER_RECOVERY"));
    }

    function test_rotateIssuer_success_replacedBond() public {
        bytes12 isinBytes = _newBondFT.isin._isinToBytes12();
        address newIssuer = makeAddr("replacedRecoveryIssuer");
        bytes32 reason = keccak256("ISSUER_RECOVERY");
        _registerWallet(newIssuer);

        vm.prank(_publisher);
        _br.publishBond(_newBondFT);
        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 1, 100);
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);
        vm.prank(_publisher);
        _br.issueBond(_newBondFT.isin, 2, 100);

        vm.prank(_issuerRecoveryOperator);
        vm.expectEmit(true, true, true, true, _brAddr);
        emit IBondRegistry.BondIssuerRotated(
            isinBytes, 1, _newBondFT.issuer, newIssuer, reason, _issuerRecoveryOperator
        );
        _br.rotateIssuer(_newBondFT.isin, 1, newIssuer, reason);

        Bond memory oldBond = _br.getBondAtVersion(isinBytes, 1);
        assertEq(uint8(oldBond.status), uint8(BondStatus.Replaced));
        assertEq(oldBond.issuer, newIssuer);
        assertEq(_br.getActiveVersion(isinBytes), 2);
    }

    function test_rotateIssuer_reverts_zeroIssuer() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_issuerRecoveryOperator);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _br.rotateIssuer(_newBondFT.isin, 1, address(0), keccak256("ISSUER_RECOVERY"));
    }

    function test_rotateIssuer_reverts_sameIssuer() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_issuerRecoveryOperator);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__IssuerUnchanged.selector, _newBondFT.issuer));
        _br.rotateIssuer(_newBondFT.isin, 1, _newBondFT.issuer, keccak256("ISSUER_RECOVERY"));
    }

    function test_rotateIssuer_reverts_zeroReason() public {
        address newIssuer = makeAddr("zeroReasonRecoveryIssuer");
        _registerWallet(newIssuer);

        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_issuerRecoveryOperator);
        vm.expectRevert(Errors.BondRegistry__ZeroReason.selector);
        _br.rotateIssuer(_newBondFT.isin, 1, newIssuer, bytes32(0));
    }

    function test_rotateIssuer_reverts_newIssuerNotEnabled() public {
        address newIssuer = makeAddr("disabledRecoveryIssuer");

        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        vm.prank(_issuerRecoveryOperator);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__IssuerNotEnabled.selector, newIssuer));
        _br.rotateIssuer(_newBondFT.isin, 1, newIssuer, keccak256("ISSUER_RECOVERY"));
    }

    /*//////////////////////////////////////////////////////////////
                                burnBond
    //////////////////////////////////////////////////////////////*/

    function test_burnBond_success_issuerHeldReclaim_restoresRemainingIssuableSupply() public {
        uint256 burnAmount = 250;
        Bond memory bondBefore = _br.getBond(_bondFT.isin);

        vm.prank(_bondFT.issuer);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.BondBurned(
            _bondFT.isin._isinToBytes12(),
            INITIAL_VERSION,
            _bondFT.issuer,
            burnAmount,
            BurnKind.ISSUER_RECLAIM,
            _bondFT.issuer
        );
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _bondFT.issuer, burnAmount, BurnKind.ISSUER_RECLAIM);

        Bond memory bondAfter = _br.getBond(_bondFT.isin);
        assertEq(bondAfter.mintedSupply, bondBefore.mintedSupply);
        assertEq(bondAfter.remainingIssuableSupply, bondBefore.remainingIssuableSupply + burnAmount);
        assertEq(IDEUSSToken(_tokenAddr).totalSupply(_bondFTId), BOND_MAX_SUPPLY - burnAmount);
    }

    function test_burnBond_reverts_issuerHeldReclaim_frozenIssuerInventory() public {
        IDEUSSToken token = IDEUSSToken(_tokenAddr);
        uint256 burnAmount = 250;

        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_bondFT.issuer, _bondFTId, BOND_MAX_SUPPLY);

        vm.prank(_bondFT.issuer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.BondRegistry__FrozenIssuerReclaimDenied.selector,
                _bondFT.issuer,
                _bondFT.isin._isinToBytes12(),
                INITIAL_VERSION,
                burnAmount,
                0
            )
        );
        _br.burnBond(
            _bondFT.isin._isinToBytes12(), INITIAL_VERSION, _bondFT.issuer, burnAmount, BurnKind.ISSUER_RECLAIM
        );
    }

    function test_burnBond_success_issuerHeldReclaim_allowsUnfrozenIssuerInventoryWhenPartiallyFrozen() public {
        IDEUSSToken token = IDEUSSToken(_tokenAddr);
        uint256 frozenAmount = 100;
        uint256 burnAmount = 250;
        Bond memory bondBefore = _br.getBond(_bondFT.isin);

        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_bondFT.issuer, _bondFTId, frozenAmount);

        vm.prank(_bondFT.issuer);
        _br.burnBond(
            _bondFT.isin._isinToBytes12(), INITIAL_VERSION, _bondFT.issuer, burnAmount, BurnKind.ISSUER_RECLAIM
        );

        Bond memory bondAfter = _br.getBond(_bondFT.isin);
        assertEq(bondAfter.mintedSupply, bondBefore.mintedSupply);
        assertEq(bondAfter.remainingIssuableSupply, bondBefore.remainingIssuableSupply + burnAmount);
        assertEq(token.totalSupply(_bondFTId), BOND_MAX_SUPPLY - burnAmount);
        assertEq(token.balanceOf(_bondFT.issuer, _bondFTId), BOND_MAX_SUPPLY - burnAmount);
        assertEq(token.frozenBalanceOf(_bondFT.issuer, _bondFTId), frozenAmount);
    }

    function test_burnBond_reverts_issuerHeldReclaim_aboveUnfrozenIssuerInventoryWhenPartiallyFrozen() public {
        IDEUSSToken token = IDEUSSToken(_tokenAddr);
        uint256 frozenAmount = 100;
        uint256 freeBalance = BOND_MAX_SUPPLY - frozenAmount;
        uint256 burnAmount = freeBalance + 1;
        Bond memory bondBefore = _br.getBond(_bondFT.isin);

        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_bondFT.issuer, _bondFTId, frozenAmount);

        vm.prank(_bondFT.issuer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.BondRegistry__FrozenIssuerReclaimDenied.selector,
                _bondFT.issuer,
                _bondFT.isin._isinToBytes12(),
                INITIAL_VERSION,
                burnAmount,
                freeBalance
            )
        );
        _br.burnBond(
            _bondFT.isin._isinToBytes12(), INITIAL_VERSION, _bondFT.issuer, burnAmount, BurnKind.ISSUER_RECLAIM
        );

        Bond memory bondAfter = _br.getBond(_bondFT.isin);
        assertEq(bondAfter.remainingIssuableSupply, bondBefore.remainingIssuableSupply);
        assertEq(token.balanceOf(_bondFT.issuer, _bondFTId), BOND_MAX_SUPPLY);
        assertEq(token.frozenBalanceOf(_bondFT.issuer, _bondFTId), frozenAmount);
    }

    function test_burnBond_success_lifecycleSettlement_doesNotRestoreRemainingIssuableSupply() public {
        address burner = makeAddr("registryBurner");
        uint256 burnAmount = 200;
        _grantEnabledBondRegistryBurner(burner);

        vm.prank(_cwAddr);
        IDEUSSToken(_tokenAddr).transfer(_tokenRecipient1, _bondFTId, burnAmount);

        Bond memory bondBefore = _br.getBond(_bondFT.isin);

        vm.prank(burner);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.BondBurned(
            _bondFT.isin._isinToBytes12(),
            INITIAL_VERSION,
            _tokenRecipient1,
            burnAmount,
            BurnKind.FINAL_SETTLEMENT,
            burner
        );
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _tokenRecipient1, burnAmount, BurnKind.FINAL_SETTLEMENT);

        Bond memory bondAfter = _br.getBond(_bondFT.isin);
        assertEq(bondAfter.mintedSupply, bondBefore.mintedSupply);
        assertEq(bondAfter.remainingIssuableSupply, bondBefore.remainingIssuableSupply);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_tokenRecipient1, _bondFTId), 0);
    }

    function test_burnBond_success_lifecycleSettlement_byBurnerWhenIssuerDisabled() public {
        address burner = makeAddr("registryBurner");
        uint256 burnAmount = 200;
        _grantEnabledBondRegistryBurner(burner);

        vm.prank(_cwAddr);
        IDEUSSToken(_tokenAddr).transfer(_tokenRecipient1, _bondFTId, burnAmount);

        vm.prank(_erAdmin);
        _er.setAccountStatus(_bondFT.issuer, AccountStatus.DISABLED, "");

        vm.prank(burner);
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _tokenRecipient1, burnAmount, BurnKind.FINAL_SETTLEMENT);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_tokenRecipient1, _bondFTId), 0);
    }

    function test_burnBond_success_finalSettlement_allowsIssuerOwnBalance() public {
        uint256 burnAmount = 250;
        Bond memory bondBefore = _br.getBond(_bondFT.isin);

        vm.prank(_bondFT.issuer);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.BondBurned(
            _bondFT.isin._isinToBytes12(),
            INITIAL_VERSION,
            _bondFT.issuer,
            burnAmount,
            BurnKind.FINAL_SETTLEMENT,
            _bondFT.issuer
        );
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _bondFT.issuer, burnAmount, BurnKind.FINAL_SETTLEMENT);

        Bond memory bondAfter = _br.getBond(_bondFT.isin);
        assertEq(bondAfter.mintedSupply, bondBefore.mintedSupply);
        assertEq(bondAfter.remainingIssuableSupply, bondBefore.remainingIssuableSupply);
        assertEq(IDEUSSToken(_tokenAddr).totalSupply(_bondFTId), BOND_MAX_SUPPLY - burnAmount);
    }

    function test_burnBond_success_finalSettlement_allowsFrozenIssuerInventory() public {
        IDEUSSToken token = IDEUSSToken(_tokenAddr);
        uint256 burnAmount = 250;
        Bond memory bondBefore = _br.getBond(_bondFT.isin);

        vm.prank(_tokenAdmin);
        token.freezePartialTokens(_bondFT.issuer, _bondFTId, BOND_MAX_SUPPLY);

        vm.prank(_bondFT.issuer);
        _br.burnBond(
            _bondFT.isin._isinToBytes12(), INITIAL_VERSION, _bondFT.issuer, burnAmount, BurnKind.FINAL_SETTLEMENT
        );

        Bond memory bondAfter = _br.getBond(_bondFT.isin);
        assertEq(bondAfter.mintedSupply, bondBefore.mintedSupply);
        assertEq(bondAfter.remainingIssuableSupply, bondBefore.remainingIssuableSupply);
        assertEq(token.totalSupply(_bondFTId), BOND_MAX_SUPPLY - burnAmount);
        assertEq(token.balanceOf(_bondFT.issuer, _bondFTId), BOND_MAX_SUPPLY - burnAmount);
        assertEq(token.frozenBalanceOf(_bondFT.issuer, _bondFTId), BOND_MAX_SUPPLY - burnAmount);
    }

    function test_burnBond_success_lifecycleSettlement_allowsReplacedVersion() public {
        address burner = makeAddr("registryBurner");
        uint256 burnAmount = 50;
        _grantEnabledBondRegistryBurner(burner);

        vm.prank(_publisher);
        _br.publishBond(_bondFT);
        vm.prank(_publisher);
        _br.issueBond(_bondFT.isin, 2, 100);

        vm.prank(_cwAddr);
        IDEUSSToken(_tokenAddr).transfer(_tokenRecipient1, _bondFTId, burnAmount);

        vm.prank(burner);
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _tokenRecipient1, burnAmount, BurnKind.FINAL_SETTLEMENT);

        Bond memory oldBond = _br.getBondAtVersion(_bondFT.isin._isinToBytes12(), 1);
        assertEq(uint8(oldBond.status), uint8(BondStatus.Replaced));
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_tokenRecipient1, _bondFTId), 0);
    }

    function test_burnBond_success_finalSettlement_allowsIssuerOwnBalanceOnReplacedVersion() public {
        uint256 burnAmount = 50;

        vm.prank(_publisher);
        _br.publishBond(_bondFT);
        vm.prank(_publisher);
        _br.issueBond(_bondFT.isin, 2, 100);

        vm.prank(_bondFT.issuer);
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _bondFT.issuer, burnAmount, BurnKind.FINAL_SETTLEMENT);

        Bond memory oldBond = _br.getBondAtVersion(_bondFT.isin._isinToBytes12(), 1);
        assertEq(uint8(oldBond.status), uint8(BondStatus.Replaced));
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_bondFT.issuer, _bondFTId), BOND_MAX_SUPPLY - burnAmount);
    }

    function test_burnBond_reverts_unauthorizedCaller_issuerHeldReclaim() public {
        vm.prank(_publisher);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.BondRegistry__UnauthorizedBurnCaller.selector, _publisher, uint8(BurnKind.ISSUER_RECLAIM)
            )
        );
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _bondFT.issuer, 1, BurnKind.ISSUER_RECLAIM);
    }

    function test_burnBond_reverts_invalidSource_issuerHeldReclaim() public {
        vm.prank(_cwAddr);
        IDEUSSToken(_tokenAddr).transfer(_tokenRecipient1, _bondFTId, 1);

        vm.prank(_bondFT.issuer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.BondRegistry__InvalidBurnSource.selector,
                _tokenRecipient1,
                _bondFT.isin._isinToBytes12(),
                uint8(BurnKind.ISSUER_RECLAIM)
            )
        );
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _tokenRecipient1, 1, BurnKind.ISSUER_RECLAIM);
    }

    function test_burnBond_reverts_issuerFinalSettlement_forThirdPartyBalance() public {
        vm.prank(_cwAddr);
        IDEUSSToken(_tokenAddr).transfer(_tokenRecipient1, _bondFTId, 1);

        vm.prank(_bondFT.issuer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.BondRegistry__InvalidBurnSource.selector,
                _tokenRecipient1,
                _bondFT.isin._isinToBytes12(),
                uint8(BurnKind.FINAL_SETTLEMENT)
            )
        );
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _tokenRecipient1, 1, BurnKind.FINAL_SETTLEMENT);
    }

    function test_burnBond_reverts_otherIssuerFinalSettlement_onForeignBond() public {
        address otherIssuer = makeAddr("otherIssuer");
        _registerWallet(otherIssuer);

        BondInput memory otherBond = _newBondFT;
        otherBond.issuer = otherIssuer;

        vm.prank(_publisher);
        _br.publishBond(otherBond);

        vm.prank(otherIssuer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.BondRegistry__UnauthorizedBurnCaller.selector, otherIssuer, uint8(BurnKind.FINAL_SETTLEMENT)
            )
        );
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, otherIssuer, 1, BurnKind.FINAL_SETTLEMENT);
    }

    function test_burnBond_reverts_callerWithoutBurnerRole_lifecycleSettlement() public {
        vm.prank(_notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.BondRegistry__UnauthorizedBurnCaller.selector, _notOwner, uint8(BurnKind.FINAL_SETTLEMENT)
            )
        );
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _bondFT.issuer, 1, BurnKind.FINAL_SETTLEMENT);
    }

    function test_burnBond_reverts_burnerCallerNotEnabled_lifecycleSettlement() public {
        address burner = makeAddr("registryBurner");
        uint256 burnAmount = 200;
        _grantEnabledBondRegistryBurner(burner);

        vm.prank(_cwAddr);
        IDEUSSToken(_tokenAddr).transfer(_tokenRecipient1, _bondFTId, burnAmount);

        vm.prank(_erAdmin);
        _er.setAccountStatus(burner, AccountStatus.DISABLED, "");

        vm.prank(burner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.BondRegistry__UnauthorizedBurnCaller.selector, burner, uint8(BurnKind.FINAL_SETTLEMENT)
            )
        );
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _tokenRecipient1, burnAmount, BurnKind.FINAL_SETTLEMENT);
    }

    function test_burnBond_reverts_nonExistentBondVersion() public {
        address burner = makeAddr("registryBurner");
        _grantBondRegistryBurner(burner);

        vm.prank(burner);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, _bondFT.isin._isinToBytes12())
        );
        _br.burnBond(_bondFT.isin._isinToBytes12(), 2, _bondFT.issuer, 1, BurnKind.FINAL_SETTLEMENT);
    }

    function test_burnBond_reverts_invalidBondStatus_suspended() public {
        vm.prank(_suspendOperator);
        _br.suspendBond(_bondFT.isin, 1);

        vm.prank(_bondFT.issuer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, _bondFT.isin._isinToBytes12())
        );
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _bondFT.issuer, 1, BurnKind.ISSUER_RECLAIM);
    }

    function test_burnBond_reverts_invalidBondStatus_lifecycleSettlementSuspended() public {
        address burner = makeAddr("registryBurner");
        _grantBondRegistryBurner(burner);

        vm.prank(_suspendOperator);
        _br.suspendBond(_bondFT.isin, 1);

        vm.prank(burner);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__InvalidBondStatus.selector, _bondFT.isin._isinToBytes12())
        );
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _bondFT.issuer, 1, BurnKind.FINAL_SETTLEMENT);
    }

    function test_burnBond_reverts_issuerReclaim_whenIssuerDisabled() public {
        vm.prank(_erAdmin);
        _er.setAccountStatus(_bondFT.issuer, AccountStatus.DISABLED, "");

        vm.prank(_bondFT.issuer);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__IssuerNotEnabled.selector, _bondFT.issuer));
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _bondFT.issuer, 1, BurnKind.ISSUER_RECLAIM);
    }

    function test_burnBond_reverts_finalSettlement_issuerPath_whenIssuerDisabled() public {
        vm.prank(_erAdmin);
        _er.setAccountStatus(_bondFT.issuer, AccountStatus.DISABLED, "");

        vm.prank(_bondFT.issuer);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__IssuerNotEnabled.selector, _bondFT.issuer));
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _bondFT.issuer, 1, BurnKind.FINAL_SETTLEMENT);
    }

    function test_burnBond_reverts_finalSettlement_disabledIssuerAlsoBurner() public {
        _grantBondRegistryBurner(_bondFT.issuer);

        vm.prank(_erAdmin);
        _er.setAccountStatus(_bondFT.issuer, AccountStatus.DISABLED, "");

        vm.prank(_bondFT.issuer);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__IssuerNotEnabled.selector, _bondFT.issuer));
        _br.burnBond(_bondFT.isin._isinToBytes12(), 1, _bondFT.issuer, 1, BurnKind.FINAL_SETTLEMENT);
    }

    /*//////////////////////////////////////////////////////////////
                             burnBondBatch
    //////////////////////////////////////////////////////////////*/

    function test_burnBondBatch_success_issuerHeldReclaim() public {
        address[] memory froms = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        froms[0] = _bondFT.issuer;
        froms[1] = _bondFT.issuer;
        amounts[0] = 100;
        amounts[1] = 200;

        vm.prank(_bondFT.issuer);
        _br.burnBondBatch(_bondFT.isin._isinToBytes12(), 1, froms, amounts, BurnKind.ISSUER_RECLAIM);

        Bond memory bond = _br.getBond(_bondFT.isin);
        assertEq(bond.remainingIssuableSupply, 300);
        assertEq(IDEUSSToken(_tokenAddr).totalSupply(_bondFTId), BOND_MAX_SUPPLY - 300);
    }

    function test_burnBondBatch_reverts_issuerHeldReclaim_frozenIssuerInventory() public {
        address[] memory froms = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        froms[0] = _bondFT.issuer;
        froms[1] = _bondFT.issuer;
        amounts[0] = 100;
        amounts[1] = 200;

        vm.prank(_tokenAdmin);
        IDEUSSToken(_tokenAddr).freezePartialTokens(_bondFT.issuer, _bondFTId, BOND_MAX_SUPPLY);

        vm.prank(_bondFT.issuer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.BondRegistry__FrozenIssuerReclaimDenied.selector,
                _bondFT.issuer,
                _bondFT.isin._isinToBytes12(),
                INITIAL_VERSION,
                300,
                0
            )
        );
        _br.burnBondBatch(_bondFT.isin._isinToBytes12(), INITIAL_VERSION, froms, amounts, BurnKind.ISSUER_RECLAIM);
    }

    function test_burnBondBatch_success_lifecycleSettlement() public {
        address burner = makeAddr("batchBurner");
        address[] memory froms = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        _grantEnabledBondRegistryBurner(burner);

        vm.startPrank(_cwAddr);
        IDEUSSToken(_tokenAddr).transfer(_tokenRecipient1, _bondFTId, 100);
        IDEUSSToken(_tokenAddr).transfer(_tokenRecipient2, _bondFTId, 200);
        vm.stopPrank();

        froms[0] = _tokenRecipient1;
        froms[1] = _tokenRecipient2;
        amounts[0] = 100;
        amounts[1] = 200;

        vm.prank(burner);
        _br.burnBondBatch(_bondFT.isin._isinToBytes12(), 1, froms, amounts, BurnKind.FINAL_SETTLEMENT);

        Bond memory bond = _br.getBond(_bondFT.isin);
        assertEq(bond.remainingIssuableSupply, 0);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_tokenRecipient1, _bondFTId), 0);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_tokenRecipient2, _bondFTId), 0);
    }

    function test_burnBondBatch_reverts_burnerCallerNotEnabled_lifecycleSettlement() public {
        address burner = makeAddr("batchBurner");
        address[] memory froms = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        _grantEnabledBondRegistryBurner(burner);

        vm.startPrank(_cwAddr);
        IDEUSSToken(_tokenAddr).transfer(_tokenRecipient1, _bondFTId, 100);
        IDEUSSToken(_tokenAddr).transfer(_tokenRecipient2, _bondFTId, 200);
        vm.stopPrank();

        froms[0] = _tokenRecipient1;
        froms[1] = _tokenRecipient2;
        amounts[0] = 100;
        amounts[1] = 200;

        vm.prank(_erAdmin);
        _er.setAccountStatus(burner, AccountStatus.DISABLED, "");

        vm.prank(burner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.BondRegistry__UnauthorizedBurnCaller.selector, burner, uint8(BurnKind.FINAL_SETTLEMENT)
            )
        );
        _br.burnBondBatch(_bondFT.isin._isinToBytes12(), 1, froms, amounts, BurnKind.FINAL_SETTLEMENT);
    }

    function test_burnBondBatch_reverts_issuerReclaim_whenIssuerDisabled() public {
        address[] memory froms = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        froms[0] = _bondFT.issuer;
        amounts[0] = 1;

        vm.prank(_erAdmin);
        _er.setAccountStatus(_bondFT.issuer, AccountStatus.DISABLED, "");

        vm.prank(_bondFT.issuer);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__IssuerNotEnabled.selector, _bondFT.issuer));
        _br.burnBondBatch(_bondFT.isin._isinToBytes12(), 1, froms, amounts, BurnKind.ISSUER_RECLAIM);
    }

    function test_burnBondBatch_reverts_finalSettlement_issuerPath_whenIssuerDisabled() public {
        address[] memory froms = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        froms[0] = _bondFT.issuer;
        amounts[0] = 1;

        vm.prank(_erAdmin);
        _er.setAccountStatus(_bondFT.issuer, AccountStatus.DISABLED, "");

        vm.prank(_bondFT.issuer);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__IssuerNotEnabled.selector, _bondFT.issuer));
        _br.burnBondBatch(_bondFT.isin._isinToBytes12(), 1, froms, amounts, BurnKind.FINAL_SETTLEMENT);
    }

    function test_burnBondBatch_reverts_finalSettlement_disabledIssuerAlsoBurner() public {
        address[] memory froms = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        froms[0] = _bondFT.issuer;
        amounts[0] = 1;
        _grantBondRegistryBurner(_bondFT.issuer);

        vm.prank(_erAdmin);
        _er.setAccountStatus(_bondFT.issuer, AccountStatus.DISABLED, "");

        vm.prank(_bondFT.issuer);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__IssuerNotEnabled.selector, _bondFT.issuer));
        _br.burnBondBatch(_bondFT.isin._isinToBytes12(), 1, froms, amounts, BurnKind.FINAL_SETTLEMENT);
    }

    function test_burnBondBatch_reverts_lengthMismatch() public {
        address[] memory froms = new address[](1);
        uint256[] memory amounts = new uint256[](2);
        froms[0] = _bondFT.issuer;
        amounts[0] = 1;
        amounts[1] = 2;

        vm.prank(_bondFT.issuer);
        vm.expectRevert(Errors.LengthMismatch.selector);
        _br.burnBondBatch(_bondFT.isin._isinToBytes12(), 1, froms, amounts, BurnKind.ISSUER_RECLAIM);
    }

    function test_burnBondBatch_reverts_nonExistentBondVersion() public {
        address burner = makeAddr("batchBurner");
        address[] memory froms = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        _grantBondRegistryBurner(burner);
        froms[0] = _bondFT.issuer;
        amounts[0] = 1;

        vm.prank(burner);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, _bondFT.isin._isinToBytes12())
        );
        _br.burnBondBatch(_bondFT.isin._isinToBytes12(), 2, froms, amounts, BurnKind.FINAL_SETTLEMENT);
    }

    function test_burnBondBatch_reverts_invalidSource_issuerHeldReclaim() public {
        address[] memory froms = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        froms[0] = _bondFT.issuer;
        froms[1] = _tokenRecipient1;
        amounts[0] = 1;
        amounts[1] = 1;

        vm.prank(_bondFT.issuer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.BondRegistry__InvalidBurnSource.selector,
                _tokenRecipient1,
                _bondFT.isin._isinToBytes12(),
                uint8(BurnKind.ISSUER_RECLAIM)
            )
        );
        _br.burnBondBatch(_bondFT.isin._isinToBytes12(), 1, froms, amounts, BurnKind.ISSUER_RECLAIM);
    }

    /*//////////////////////////////////////////////////////////////
                              supportsInterface
    //////////////////////////////////////////////////////////////*/
    function test_supportsInterface_success() public view {
        assertTrue(_br.supportsInterface(type(IBondRegistry).interfaceId));
        assertTrue(_br.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_revert_notSupportedInterface() public view {
        bytes4 interfaceId = 0x12345678;
        assertFalse(_br.supportsInterface(interfaceId));
    }

    /*//////////////////////////////////////////////////////////////
                             SCORING role
    //////////////////////////////////////////////////////////////*/

    function test_scoring_roleConstant_isBit7() public view {
        assertEq(_br.SCORING(), 1 << 7);
    }

    function test_scoring_allBrRoles_includesScoring() public view {
        assertEq(_br.ALL_BR_ROLES() & _br.SCORING(), _br.SCORING());
    }

    function test_issuerRecovery_roleConstant_isBit8() public view {
        assertEq(_br.ISSUER_RECOVERY(), 1 << 8);
    }

    function test_issuerRecovery_allBrRoles_includesIssuerRecovery() public view {
        assertEq(_br.ALL_BR_ROLES() & _br.ISSUER_RECOVERY(), _br.ISSUER_RECOVERY());
    }

    function test_issuerRecovery_invalidBit_isAboveIssuerRecovery() public view {
        assertEq(_invalidBondRegistryRoleBit(), _br.ISSUER_RECOVERY() << 1);
    }

    function test_grantRoles_success_includingScoring() public {
        address newUser = makeAddr("scoringUser");
        uint256 roles = _br.SCORING();

        _grantBondRegistryRoles(newUser, roles);

        assertEq(_br.rolesOf(newUser), roles);
    }

    function test_grantRoles_success_includingIssuerRecovery() public {
        address newUser = makeAddr("issuerRecoveryUser");
        uint256 roles = _br.ISSUER_RECOVERY();

        _grantBondRegistryRoles(newUser, roles);

        assertEq(_br.rolesOf(newUser), roles);
    }

    function test_grantRoles_revert_scoringPlusInvalidBit() public {
        address newUser = makeAddr("scoringInvalidUser");
        uint256 roles = _br.ALL_BR_ROLES() | _invalidBondRegistryRoleBit();

        bytes memory data = abi.encodeWithSelector(OwnableRoles.grantRoles.selector, newUser, roles);
        _timelockSchedule(_brAddr, data);
        vm.expectRevert(Errors.InvalidRoles.selector);
        _timelockExecute(_brAddr, data);
    }

    /*//////////////////////////////////////////////////////////////
                           appendScoring
    //////////////////////////////////////////////////////////////*/

    function test_appendScoring_success_emitsEvent() public {
        address operator = _scoringOperator();
        address wallet = makeAddr("issuerWallet");
        Scoring memory s = _defaultScoring();

        vm.prank(operator);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.ScoringAppended(
            wallet, 1, s.defaultProbabilityBps, s.issueDate, s.expirationDate, s.distributorId, operator
        );
        _br.appendScoring(wallet, s);
    }

    function test_appendScoring_success_incrementsCount() public {
        address operator = _scoringOperator();
        address wallet = makeAddr("issuerWallet");

        assertEq(_br.getScoringCount(wallet), 0);

        vm.prank(operator);
        _br.appendScoring(wallet, _defaultScoring());

        assertEq(_br.getScoringCount(wallet), 1);
    }

    function test_appendScoring_success_idIs1Based() public {
        address operator = _scoringOperator();
        address wallet = makeAddr("issuerWallet");
        Scoring memory s = _defaultScoring();

        vm.prank(operator);
        _br.appendScoring(wallet, s);

        Scoring memory stored = _br.getScoringAt(wallet, 1);
        assertEq(stored.defaultProbabilityBps, s.defaultProbabilityBps);
        assertEq(stored.issueDate, s.issueDate);
        assertEq(stored.expirationDate, s.expirationDate);
        assertEq(stored.distributorId, s.distributorId);
    }

    function test_appendScoring_success_probabilityAtMaxBps() public {
        address operator = _scoringOperator();
        address wallet = makeAddr("issuerWallet");
        Scoring memory s = _defaultScoring();
        s.defaultProbabilityBps = _br.MAX_PROBABILITY_BPS();

        vm.prank(operator);
        _br.appendScoring(wallet, s);

        assertEq(_br.getScoringAt(wallet, 1).defaultProbabilityBps, _br.MAX_PROBABILITY_BPS());
    }

    function test_appendScoring_success_probabilityAtZero() public {
        address operator = _scoringOperator();
        address wallet = makeAddr("issuerWallet");
        Scoring memory s = _defaultScoring();
        s.defaultProbabilityBps = 0;

        vm.prank(operator);
        _br.appendScoring(wallet, s);

        assertEq(_br.getScoringAt(wallet, 1).defaultProbabilityBps, 0);
    }

    function test_appendScoring_revert_unauthorizedCaller() public {
        address nonScorer = makeAddr("nonScorer");
        address wallet = makeAddr("issuerWallet");

        vm.prank(nonScorer);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _br.appendScoring(wallet, _defaultScoring());
    }

    function test_appendScoring_revert_zeroWallet() public {
        address operator = _scoringOperator();

        vm.prank(operator);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _br.appendScoring(address(0), _defaultScoring());
    }

    function test_appendScoring_revert_zeroIssueDate() public {
        address operator = _scoringOperator();
        address wallet = makeAddr("issuerWallet");
        Scoring memory s = _defaultScoring();
        s.issueDate = 0;

        vm.prank(operator);
        vm.expectRevert(Errors.BondRegistry__ScoringZeroIssueDate.selector);
        _br.appendScoring(wallet, s);
    }

    function test_appendScoring_revert_expirationNotAfterIssue_equal() public {
        address operator = _scoringOperator();
        address wallet = makeAddr("issuerWallet");
        Scoring memory s = _defaultScoring();
        s.expirationDate = s.issueDate;

        vm.prank(operator);
        vm.expectRevert(Errors.BondRegistry__ScoringExpirationNotAfterIssue.selector);
        _br.appendScoring(wallet, s);
    }

    function test_appendScoring_revert_expirationBeforeIssue() public {
        address operator = _scoringOperator();
        address wallet = makeAddr("issuerWallet");
        Scoring memory s = _defaultScoring();
        s.expirationDate = s.issueDate - 1;

        vm.prank(operator);
        vm.expectRevert(Errors.BondRegistry__ScoringExpirationNotAfterIssue.selector);
        _br.appendScoring(wallet, s);
    }

    function test_appendScoring_revert_zeroDistributorId() public {
        address operator = _scoringOperator();
        address wallet = makeAddr("issuerWallet");
        Scoring memory s = _defaultScoring();
        s.distributorId = bytes32(0);

        vm.prank(operator);
        vm.expectRevert(Errors.BondRegistry__ScoringZeroDistributorId.selector);
        _br.appendScoring(wallet, s);
    }

    function test_appendScoring_revert_probabilityAboveMax() public {
        address operator = _scoringOperator();
        address wallet = makeAddr("issuerWallet");
        Scoring memory s = _defaultScoring();
        s.defaultProbabilityBps = _br.MAX_PROBABILITY_BPS() + 1;

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__ScoringProbabilityTooHigh.selector, s.defaultProbabilityBps)
        );
        _br.appendScoring(wallet, s);
    }

    /*//////////////////////////////////////////////////////////////
                           getScoringCount
    //////////////////////////////////////////////////////////////*/

    function test_getScoringCount_returnsZeroForUntouchedWallet() public {
        address wallet = makeAddr("untouchedWallet");
        assertEq(_br.getScoringCount(wallet), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            getScoringAt
    //////////////////////////////////////////////////////////////*/

    function test_getScoringAt_success_exactStoredRecord() public {
        address operator = _scoringOperator();
        address wallet = makeAddr("issuerWallet");
        Scoring memory s = _defaultScoring();

        vm.prank(operator);
        _br.appendScoring(wallet, s);

        Scoring memory result = _br.getScoringAt(wallet, 1);
        assertEq(result.defaultProbabilityBps, s.defaultProbabilityBps);
        assertEq(result.issueDate, s.issueDate);
        assertEq(result.expirationDate, s.expirationDate);
        assertEq(result.distributorId, s.distributorId);
    }

    function test_getScoringAt_revert_idZero() public {
        address wallet = makeAddr("issuerWallet");

        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidScoringId.selector, wallet, 0));
        _br.getScoringAt(wallet, 0);
    }

    function test_getScoringAt_revert_idAboveCount() public {
        address operator = _scoringOperator();
        address wallet = makeAddr("issuerWallet");

        vm.prank(operator);
        _br.appendScoring(wallet, _defaultScoring());

        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidScoringId.selector, wallet, 2));
        _br.getScoringAt(wallet, 2);
    }

    function test_getScoringAt_revert_idAboveCountWhenEmpty() public {
        address wallet = makeAddr("emptyWallet");

        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__InvalidScoringId.selector, wallet, 1));
        _br.getScoringAt(wallet, 1);
    }

    /*//////////////////////////////////////////////////////////////
                           getLatestScoring
    //////////////////////////////////////////////////////////////*/

    function test_getLatestScoring_success_returnsMostRecent() public {
        address operator = _scoringOperator();
        address wallet = makeAddr("issuerWallet");

        Scoring memory s1 = _defaultScoring();
        Scoring memory s2 = _defaultScoring();
        s2.defaultProbabilityBps = 1_000;
        // forge-lint: disable-next-line(unsafe-typecast)
        s2.distributorId = bytes32("distributor2");

        vm.startPrank(operator);
        _br.appendScoring(wallet, s1);
        _br.appendScoring(wallet, s2);
        vm.stopPrank();

        Scoring memory latest = _br.getLatestScoring(wallet);
        assertEq(latest.defaultProbabilityBps, s2.defaultProbabilityBps);
        assertEq(latest.distributorId, s2.distributorId);
    }

    function test_getLatestScoring_revert_noScoringExists() public {
        address wallet = makeAddr("noScoringWallet");

        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__ScoringNotFound.selector, wallet));
        _br.getLatestScoring(wallet);
    }

    /*//////////////////////////////////////////////////////////////
                    wallet independence and history
    //////////////////////////////////////////////////////////////*/

    function test_scoring_historiesAreIndependentPerWallet() public {
        address operator = _scoringOperator();
        address walletA = makeAddr("walletA");
        address walletB = makeAddr("walletB");

        Scoring memory sA = _defaultScoring();
        // forge-lint: disable-next-line(unsafe-typecast)
        sA.distributorId = bytes32("distA");
        Scoring memory sB = _defaultScoring();
        // forge-lint: disable-next-line(unsafe-typecast)
        sB.distributorId = bytes32("distB");

        vm.startPrank(operator);
        _br.appendScoring(walletA, sA);
        _br.appendScoring(walletB, sB);
        vm.stopPrank();

        assertEq(_br.getScoringCount(walletA), 1);
        assertEq(_br.getScoringCount(walletB), 1);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(_br.getScoringAt(walletA, 1).distributorId, bytes32("distA"));
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(_br.getScoringAt(walletB, 1).distributorId, bytes32("distB"));
    }

    function test_scoring_olderRecordsPreservedAfterNewAppend() public {
        address operator = _scoringOperator();
        address wallet = makeAddr("issuerWallet");

        Scoring memory s1 = _defaultScoring();
        // forge-lint: disable-next-line(unsafe-typecast)
        s1.distributorId = bytes32("dist1");
        Scoring memory s2 = _defaultScoring();
        // forge-lint: disable-next-line(unsafe-typecast)
        s2.distributorId = bytes32("dist2");

        vm.startPrank(operator);
        _br.appendScoring(wallet, s1);
        _br.appendScoring(wallet, s2);
        vm.stopPrank();

        assertEq(_br.getScoringCount(wallet), 2);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(_br.getScoringAt(wallet, 1).distributorId, bytes32("dist1"));
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(_br.getScoringAt(wallet, 2).distributorId, bytes32("dist2"));
    }

    /*//////////////////////////////////////////////////////////////
                          getCurrentCouponRate
    //////////////////////////////////////////////////////////////*/

    function test_getCurrentCouponRate_zeroCoupon() public {
        BondInput memory zeroCouponBond = _newBondFT;
        zeroCouponBond.couponRateType = CouponRateType.ZERO_COUPON;
        zeroCouponBond.couponRates = CouponRates({paymentTimestamps: new uint256[](0), rates: new uint256[](0)});

        vm.prank(_publisher);
        _br.publishBond(zeroCouponBond);

        assertEq(_br.getCurrentCouponRate(zeroCouponBond.isin._isinToBytes12()), 0);
    }

    function test_getCurrentCouponRate_fixed_returnsConstantRate() public view {
        // _bondFT was issued in setup and block.timestamp is inside its coupon timestamp schedule.
        assertEq(_br.getCurrentCouponRate(BOND_ISIN_ERC6909_FT._isinToBytes12()), BOND_COUPON_RATE);
    }

    function test_getCurrentCouponRate_success_unissuedReturnsZero() public {
        vm.prank(_publisher);
        _br.publishBond(_newBondFT);

        assertEq(_br.getCurrentCouponRate(_newBondFT.isin._isinToBytes12()), 0);
    }

    function test_getCurrentCouponRate_success_beforeFirstCheckpointReturnsZero() public {
        BondInput memory futureCouponBond = _newBondFT;
        futureCouponBond.couponRates.paymentTimestamps[0] = block.timestamp + 1 days;

        vm.prank(_publisher);
        _br.publishBond(futureCouponBond);

        vm.prank(_publisher);
        _br.issueBond(futureCouponBond.isin, 1, BOND_MAX_SUPPLY);

        assertEq(_br.getCurrentCouponRate(futureCouponBond.isin._isinToBytes12()), 0);
    }

    function test_getCurrentCouponRateForBond_success_unknownTrancheReturnsZero() public view {
        Bond memory bond = _br.getBond(BOND_ISIN_ERC6909_FT);
        bond.tokenId = uint256(keccak256("unknown-token-id"));

        assertEq(_br.getCurrentCouponRateForBond(bond), 0);
    }

    function test_getCurrentCouponRate_success_atMaturityReturnsZero() public {
        bytes12 isinBytes = BOND_ISIN_ERC6909_FT._isinToBytes12();
        vm.warp(_maturityDate);

        assertEq(_br.getCurrentCouponRate(isinBytes), 0);
    }

    function test_getCurrentCouponRate_successorPublishedButNotIssued_returnsActiveVersionRate() public {
        // ARRANGE: v1 of _bondFT is Issued (from setUp). Publish v2 without issuing it.
        vm.prank(_publisher);
        _br.publishBond(_bondFT);

        bytes12 isinBytes = BOND_ISIN_ERC6909_FT._isinToBytes12();
        assertEq(_br.getActiveVersion(isinBytes), 1);
        assertEq(_br.getLatestVersion(isinBytes), 2);

        // ACT & ASSERT: rate must come from v1's tranche, not v2's (which has no issueDate yet)
        assertEq(_br.getCurrentCouponRate(isinBytes), BOND_COUPON_RATE);
    }

    function test_getCurrentCouponRate_revertsOnUnknown() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, NON_EXISTENT_ISIN._isinToBytes12())
        );
        _br.getCurrentCouponRate(NON_EXISTENT_ISIN._isinToBytes12());
    }
}
