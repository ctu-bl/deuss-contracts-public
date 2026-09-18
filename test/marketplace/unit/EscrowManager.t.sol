// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC6909} from "@openzeppelin/contracts/interfaces/IERC6909.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";
import {AssetType, Escrow} from "src/marketplace/MarketStructs.sol";
import {EscrowManager} from "src/marketplace/EscrowManager.sol";
import {IEscrowManager} from "src/marketplace/interfaces/IEscrowManager.sol";
import {Errors} from "src/libs/Errors.sol";
import {StringExtensions} from "src/libs/StringExtensions.sol";

// test files
import {MarketplaceFixture} from "test/fixtures/MarketplaceFixture.t.sol";
import {MockEscrowManager} from "test/mocks/MockContracts.sol";

contract EscrowManagerHarness is EscrowManager {
    function registerModuleHarness(bytes32 moduleType, address moduleAddress) external {
        _registerModule(moduleType, moduleAddress);
    }

    function exposedEscrowManagerStorageLocation() external pure returns (bytes32) {
        return _ESCROW_MANAGER_STORAGE_LOCATION;
    }
}

contract EscrowManagerTest is MarketplaceFixture {
    using StringExtensions for string;

    uint256 internal _amount;
    address internal _escrowManagerAdmin;
    UpgradeableBeacon internal _escrowManagerBeacon;

    bytes32 internal _auctionModuleType = keccak256("AUCTION_MODULE");
    address internal _auctionModule = makeAddr("auctionModule");

    function setUp() public override {
        super.setUp();

        _amount = BOND_MAX_SUPPLY;

        _escrowManagerAdmin = makeAddr("escrowManagerAdmin");
        _escrowManagerBeacon = UpgradeableBeacon(_suite.core.escrowManagerBeacon);

        uint256 adminRole = EscrowManager(_escrowManager).ADMIN();
        _grantRoles(_escrowManager, _escrowManagerAdmin, adminRole);
    }

    /*//////////////////////////////////////////////////////////////
                             upgradeTo
    //////////////////////////////////////////////////////////////*/
    function test_upgradeTo_success_beaconOwner() public {
        address newImpl = address(new MockEscrowManager());

        bytes memory data = abi.encodeWithSelector(_escrowManagerBeacon.upgradeTo.selector, newImpl);
        _timelockOp(address(_escrowManagerBeacon), data);

        assertEq(MockEscrowManager(_escrowManager).VERSION(), 2);
        assertTrue(MockEscrowManager(_escrowManager).isNewVersion());
    }

    function test_upgradeTo_reverts_notBeaconOwner() public {
        address newImpl = address(new MockEscrowManager());
        address notOwner = makeAddr("notOwner");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableUnauthorizedAccount.selector, notOwner));
        _escrowManagerBeacon.upgradeTo(newImpl);
    }

    function test_beaconDowngrade_success() public {
        address originalImpl = _escrowManagerBeacon.implementation();

        address newImpl = address(new MockEscrowManager());
        bytes memory upgradeData = abi.encodeWithSelector(_escrowManagerBeacon.upgradeTo.selector, newImpl);
        _timelockOp(address(_escrowManagerBeacon), upgradeData);
        assertEq(_escrowManagerBeacon.implementation(), newImpl);

        bytes memory downgradeData = abi.encodeWithSelector(_escrowManagerBeacon.upgradeTo.selector, originalImpl);
        _timelockOp(address(_escrowManagerBeacon), downgradeData);

        assertEq(_escrowManagerBeacon.implementation(), originalImpl);
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZE
    //////////////////////////////////////////////////////////////*/

    function test_initialize_success_zeroMarketplace() public {
        EscrowManager implementation = new EscrowManager();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), _deployer);
        bytes memory initData =
            abi.encodeWithSelector(EscrowManager.initialize.selector, _deployer, address(0), _orderbookMarketplace);

        EscrowManager newEscrowManager = EscrowManager(address(new BeaconProxy(address(beacon), initData)));

        bytes32 moduleType = newEscrowManager.MARKETPLACE_MODULE();
        assertEq(newEscrowManager.moduleTypeOf(address(0)), bytes32(0));
        assertFalse(newEscrowManager.isAuthorizedModule(moduleType, address(0)));
    }

    function test_initialize_success_zeroOrderbookMarketplace() public {
        EscrowManager implementation = new EscrowManager();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), _deployer);
        bytes memory initData =
            abi.encodeWithSelector(EscrowManager.initialize.selector, _deployer, _marketplace, address(0));

        EscrowManager newEscrowManager = EscrowManager(address(new BeaconProxy(address(beacon), initData)));

        bytes32 moduleType = newEscrowManager.ORDERBOOK_MARKETPLACE_MODULE();
        assertEq(newEscrowManager.moduleTypeOf(address(0)), bytes32(0));
        assertFalse(newEscrowManager.isAuthorizedModule(moduleType, address(0)));
    }

    function test_namespacedStorageLocation_success_matchesErc7201Formula() public {
        EscrowManagerHarness harness = new EscrowManagerHarness();
        bytes32 storageLocation = harness.exposedEscrowManagerStorageLocation();

        assertEq(storageLocation, _erc7201Location("deuss.escrowManager.storage"));
        assertEq(uint256(storageLocation) & 0xff, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_registerModule_success() public {
        vm.expectEmit();
        emit IEscrowManager.ModuleRegistered(_auctionModuleType, _auctionModule);

        vm.prank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).registerModule(_auctionModuleType, _auctionModule);

        assertEq(EscrowManager(_escrowManager).moduleTypeOf(_auctionModule), _auctionModuleType);
        assertTrue(EscrowManager(_escrowManager).isAuthorizedModule(_auctionModuleType, _auctionModule));
    }

    function test_registerModule_reverts_sameAddressAndType() public {
        vm.prank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).registerModule(_auctionModuleType, _auctionModule);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.EscrowManager__ModuleAlreadyRegistered.selector, _auctionModule, _auctionModuleType
            )
        );
        vm.prank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).registerModule(_auctionModuleType, _auctionModule);
    }

    function test_registerModule_reverts_zeroModuleType() public {
        vm.prank(_escrowManagerAdmin);
        vm.expectRevert(Errors.EscrowManager__InvalidModuleType.selector);
        IEscrowManager(_escrowManager).registerModule(bytes32(0), _auctionModule);
    }

    function test_registerModuleInternal_reverts_zeroModuleType() public {
        EscrowManagerHarness harness = new EscrowManagerHarness();
        vm.expectRevert(Errors.EscrowManager__InvalidModuleType.selector);
        harness.registerModuleHarness(bytes32(0), _auctionModule);
    }

    function test_registerModule_reverts_zeroAddress() public {
        vm.prank(_escrowManagerAdmin);
        vm.expectRevert(Errors.EscrowManager__InvalidModuleAddress.selector);
        IEscrowManager(_escrowManager).registerModule(_auctionModuleType, address(0));
    }

    function test_registerModule_reverts_notAdmin() public {
        address notAdmin = makeAddr("notAdmin");
        vm.prank(notAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        IEscrowManager(_escrowManager).registerModule(_auctionModuleType, _auctionModule);
    }

    function test_registerModule_reverts_addressBoundToDifferentType() public {
        address sharedModule = makeAddr("sharedModule");

        vm.startPrank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).registerModule(_auctionModuleType, sharedModule);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.EscrowManager__ModuleTypeMismatch.selector, _auctionModuleType, keccak256("RFQ")
            )
        );
        IEscrowManager(_escrowManager).registerModule(keccak256("RFQ"), sharedModule);
        vm.stopPrank();
    }

    function test_deactivateModule_success() public {
        vm.startPrank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).registerModule(_auctionModuleType, _auctionModule);

        vm.expectEmit();
        emit IEscrowManager.ModuleDeactivated(_auctionModuleType, _auctionModule);
        IEscrowManager(_escrowManager).deactivateModule(_auctionModuleType, _auctionModule);
        vm.stopPrank();

        assertEq(EscrowManager(_escrowManager).moduleTypeOf(_auctionModule), bytes32(0));
        assertFalse(EscrowManager(_escrowManager).isAuthorizedModule(_auctionModuleType, _auctionModule));
    }

    function test_deactivateModule_reverts_zeroModuleType() public {
        vm.prank(_escrowManagerAdmin);
        vm.expectRevert(Errors.EscrowManager__InvalidModuleType.selector);
        IEscrowManager(_escrowManager).deactivateModule(bytes32(0), _auctionModule);
    }

    function test_deactivateModule_reverts_zeroAddress() public {
        vm.prank(_escrowManagerAdmin);
        vm.expectRevert(Errors.EscrowManager__InvalidModuleAddress.selector);
        IEscrowManager(_escrowManager).deactivateModule(_auctionModuleType, address(0));
    }

    function test_deactivateModule_reverts_wrongType() public {
        vm.startPrank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).registerModule(_auctionModuleType, _auctionModule);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.EscrowManager__ModuleTypeMismatch.selector, _auctionModuleType, keccak256("RFQ")
            )
        );
        IEscrowManager(_escrowManager).deactivateModule(keccak256("RFQ"), _auctionModule);
        vm.stopPrank();
    }

    function test_deactivateModule_reverts_moduleNotRegistered() public {
        address unknownModule = makeAddr("unknownModule");

        vm.prank(_escrowManagerAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__ModuleNotRegistered.selector, unknownModule));
        IEscrowManager(_escrowManager).deactivateModule(_auctionModuleType, unknownModule);
    }

    function test_deactivateModule_reverts_notAdmin() public {
        address notAdmin = makeAddr("notAdmin");
        vm.prank(notAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        IEscrowManager(_escrowManager).deactivateModule(_auctionModuleType, _auctionModule);
    }

    function test_deactivateModule_reverts_activeEscrows() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        bytes32 moduleType = EscrowManager(_escrowManager).MARKETPLACE_MODULE();
        vm.prank(_escrowManagerAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__ModuleHasActiveEscrows.selector, _marketplace, 1));
        IEscrowManager(_escrowManager).deactivateModule(moduleType, _marketplace);
    }

    function test_deactivateModule_reverts_partialEscrowRemaining() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).withdraw(escrowId, _amount / 2);

        bytes32 moduleType = EscrowManager(_escrowManager).MARKETPLACE_MODULE();
        vm.prank(_escrowManagerAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__ModuleHasActiveEscrows.selector, _marketplace, 1));
        IEscrowManager(_escrowManager).deactivateModule(moduleType, _marketplace);
    }

    function test_deactivateModule_success_afterFullWithdraw() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).withdraw(escrowId, _amount);

        bytes32 moduleType = EscrowManager(_escrowManager).MARKETPLACE_MODULE();
        vm.prank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).deactivateModule(moduleType, _marketplace);

        assertEq(EscrowManager(_escrowManager).moduleTypeOf(_marketplace), bytes32(0));
        assertFalse(EscrowManager(_escrowManager).isAuthorizedModule(moduleType, _marketplace));
    }

    function test_deactivateModule_success_afterFullClaim() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        address beneficiary = makeAddr("beneficiary");
        (address beneficiaryWallet,) = _createAndRegisterEntityWalletForCompany(_erAdmin, beneficiary);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).claim(escrowId, _amount, beneficiaryWallet);

        bytes32 moduleType = EscrowManager(_escrowManager).MARKETPLACE_MODULE();
        vm.prank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).deactivateModule(moduleType, _marketplace);

        assertEq(EscrowManager(_escrowManager).moduleTypeOf(_marketplace), bytes32(0));
        assertFalse(EscrowManager(_escrowManager).isAuthorizedModule(moduleType, _marketplace));
    }

    function test_setAssetManager_success() public {
        address newAssetManager = makeAddr("newAssetManager");

        vm.expectEmit();
        emit IEscrowManager.AssetManagerSet(_assetManager, newAssetManager);

        vm.prank(_escrowManagerAdmin);
        EscrowManager(_escrowManager).setAssetManager(newAssetManager);

        assertEq(EscrowManager(_escrowManager).assetManager(), newAssetManager);
    }

    function test_setAssetManager_reverts_zeroAddress() public {
        vm.prank(_escrowManagerAdmin);
        vm.expectRevert(Errors.ZeroAddress.selector);
        EscrowManager(_escrowManager).setAssetManager(address(0));
    }

    function test_setAssetManager_reverts_notAdmin() public {
        address notAdmin = address(0xBEEF);
        address newAssetManager = makeAddr("newAssetManager");

        assertFalse(EscrowManager(_escrowManager).hasAnyRole(notAdmin, EscrowManager(_escrowManager).ADMIN()));

        vm.prank(notAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        EscrowManager(_escrowManager).setAssetManager(newAssetManager);
    }

    /*//////////////////////////////////////////////////////////////
                            CREATE ESCROW
    //////////////////////////////////////////////////////////////*/

    function test_previewNextEscrowId_success() public {
        uint256 previewBefore = IEscrowManager(_escrowManager).previewNextEscrowId();
        assertEq(previewBefore, EscrowManager(_escrowManager).nextEscrowId() + 1);

        _approveEscrowManager(_company, _bondFTId, _amount);
        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        uint256 previewAfter = IEscrowManager(_escrowManager).previewNextEscrowId();
        assertEq(previewAfter, EscrowManager(_escrowManager).nextEscrowId() + 1);
        assertEq(previewAfter, previewBefore + 1);
    }

    function test_createEscrow_success_fullAmount() public {
        Balances memory balancesBefore = _snapshotBalances();

        _approveEscrowManager(_company, _bondFTId, _amount);

        bytes32 moduleType = EscrowManager(_escrowManager).MARKETPLACE_MODULE();
        uint256 expectedEscrowId = EscrowManager(_escrowManager).nextEscrowId() + 1;

        vm.expectEmit();
        emit IEscrowManager.EscrowCreated(
            expectedEscrowId, moduleType, _company, _tokenAddr, _bondFTId, _amount, AssetType.ERC6909
        );

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        Balances memory balancesAfter = _snapshotBalances();
        assertEq(balancesAfter.company, balancesBefore.company - _amount);
        assertEq(balancesAfter.escrow, balancesBefore.escrow + _amount);

        Escrow memory escrow = IEscrowManager(_escrowManager).getEscrow(escrowId);
        assertEq(escrow.depositor, _company);
        assertEq(escrow.tokenAddress, _tokenAddr);
        assertEq(escrow.tokenId, _bondFTId);
        assertEq(escrow.amount, _amount);
        assertEq(escrow.moduleType, moduleType);
        assertEq(escrow.moduleAddress, _marketplace);

        (
            address depositor,
            AssetType assetType,
            address tokenAddress,
            uint256 tokenId,
            uint256 escrowAmount,
            bytes32 escrowModuleType,
            address moduleAddress
        ) = EscrowManager(_escrowManager).escrows(escrowId);
        assertEq(depositor, _company);
        assertEq(uint8(assetType), uint8(AssetType.ERC6909));
        assertEq(tokenAddress, _tokenAddr);
        assertEq(tokenId, _bondFTId);
        assertEq(escrowAmount, _amount);
        assertEq(escrowModuleType, moduleType);
        assertEq(moduleAddress, _marketplace);
    }

    function test_namespacedState_success_usesErc7201Storage() public {
        bytes32 storageLocation = _erc7201Location("deuss.escrowManager.storage");

        assertEq(_loadAddress(_escrowManager, storageLocation), EscrowManager(_escrowManager).assetManager());
        assertEq(
            _loadUint(_escrowManager, _slotOffset(storageLocation, 1)), EscrowManager(_escrowManager).nextEscrowId()
        );

        _approveEscrowManager(_company, _bondFTId, _amount);
        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        assertEq(
            _loadUint(_escrowManager, _slotOffset(storageLocation, 1)), EscrowManager(_escrowManager).nextEscrowId()
        );
    }

    function test_createEscrow_success_dynamicModule() public {
        vm.prank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).registerModule(_auctionModuleType, _auctionModule);

        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_auctionModule);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        Escrow memory escrow = IEscrowManager(_escrowManager).getEscrow(escrowId);
        assertEq(escrow.moduleType, _auctionModuleType);
        assertEq(escrow.moduleAddress, _auctionModule);
    }

    function test_createEscrow_success_afterModuleReactivation() public {
        vm.prank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).registerModule(_auctionModuleType, _auctionModule);

        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_auctionModule);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        vm.prank(_auctionModule);
        IEscrowManager(_escrowManager).withdraw(escrowId, _amount);

        vm.startPrank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).deactivateModule(_auctionModuleType, _auctionModule);
        IEscrowManager(_escrowManager).registerModule(_auctionModuleType, _auctionModule);
        vm.stopPrank();

        // ASSERT
        Escrow memory escrow = IEscrowManager(_escrowManager).getEscrow(escrowId);
        assertEq(escrow.moduleType, _auctionModuleType);
        assertEq(escrow.moduleAddress, _auctionModule);
    }

    function test_createEscrow_success_afterModuleRotationSameType() public {
        bytes32 moduleType = EscrowManager(_escrowManager).MARKETPLACE_MODULE();
        address newMarketplace = makeAddr("newMarketplace");

        vm.startPrank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).registerModule(moduleType, newMarketplace);
        IEscrowManager(_escrowManager).deactivateModule(moduleType, _marketplace);
        vm.stopPrank();

        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(newMarketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        Escrow memory escrow = IEscrowManager(_escrowManager).getEscrow(escrowId);
        assertEq(escrow.moduleType, moduleType);
        assertEq(escrow.moduleAddress, newMarketplace);
    }

    function test_createEscrow_success_orderbookDefaultModuleType() public {
        bytes32 orderbookModuleType = EscrowManager(_escrowManager).ORDERBOOK_MARKETPLACE_MODULE();

        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_orderbookMarketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        Escrow memory escrow = IEscrowManager(_escrowManager).getEscrow(escrowId);
        assertEq(escrow.moduleType, orderbookModuleType);
        assertEq(escrow.moduleAddress, _orderbookMarketplace);
    }

    function test_createEscrow_success_sameModuleSequentialEscrowIds() public {
        uint256 firstAmount = _amount / 4;
        uint256 secondAmount = _amount / 5;
        uint256 expectedFirstEscrowId = EscrowManager(_escrowManager).nextEscrowId() + 1;

        (uint256 firstEscrowId, uint256 secondEscrowId) =
            _createTwoEscrowsWithSameToken(_marketplace, _marketplace, firstAmount, secondAmount);

        assertEq(firstEscrowId, expectedFirstEscrowId);
        assertEq(secondEscrowId, firstEscrowId + 1);

        Escrow memory firstEscrow = IEscrowManager(_escrowManager).getEscrow(firstEscrowId);
        Escrow memory secondEscrow = IEscrowManager(_escrowManager).getEscrow(secondEscrowId);

        assertEq(firstEscrow.depositor, _company);
        assertEq(secondEscrow.depositor, _company);
        assertEq(firstEscrow.tokenId, _bondFTId);
        assertEq(secondEscrow.tokenId, _bondFTId);
        assertEq(firstEscrow.amount, firstAmount);
        assertEq(secondEscrow.amount, secondAmount);
    }

    function test_createEscrow_success_differentModulesSequentialEscrowIds() public {
        uint256 firstAmount = _amount / 4;
        uint256 secondAmount = _amount / 5;
        bytes32 marketplaceModuleType = EscrowManager(_escrowManager).MARKETPLACE_MODULE();

        vm.prank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).registerModule(_auctionModuleType, _auctionModule);

        (uint256 firstEscrowId, uint256 secondEscrowId) =
            _createTwoEscrowsWithSameToken(_marketplace, _auctionModule, firstAmount, secondAmount);

        assertEq(secondEscrowId, firstEscrowId + 1);
        assertEq(IEscrowManager(_escrowManager).getEscrow(firstEscrowId).moduleType, marketplaceModuleType);
        assertEq(IEscrowManager(_escrowManager).getEscrow(secondEscrowId).moduleType, _auctionModuleType);
    }

    function test_createEscrow_success_sameDepositorDifferentTokenIds() public {
        string memory secondIsin = "SK0001002060";
        uint256 firstAmount = _amount / 4;
        uint256 secondAmount = _amount / 5;

        vm.prank(_publisher);
        _br.publishBond(_createBond(secondIsin, _company));

        vm.prank(_company);
        _br.issueBond(secondIsin, 1, BOND_MAX_SUPPLY);

        bytes12 isinBytes = secondIsin._isinToBytes12();
        uint256 secondTokenId = uint256(keccak256(abi.encodePacked(isinBytes, uint8(1))));

        _approveEscrowManager(_company, _bondFTId, firstAmount);
        vm.prank(_company);
        IERC6909(_tokenAddr).approve(_escrowManager, secondTokenId, secondAmount);

        vm.startPrank(_marketplace);
        uint256 firstEscrowId =
            IEscrowManager(_escrowManager).createEscrow(firstAmount, _company, _tokenAddr, _bondFTId);
        uint256 secondEscrowId =
            IEscrowManager(_escrowManager).createEscrow(secondAmount, _company, _tokenAddr, secondTokenId);
        vm.stopPrank();

        Escrow memory firstEscrow = IEscrowManager(_escrowManager).getEscrow(firstEscrowId);
        Escrow memory secondEscrow = IEscrowManager(_escrowManager).getEscrow(secondEscrowId);

        assertEq(firstEscrow.depositor, secondEscrow.depositor);
        assertEq(firstEscrow.tokenAddress, _tokenAddr);
        assertEq(secondEscrow.tokenAddress, _tokenAddr);
        assertEq(firstEscrow.tokenId, _bondFTId);
        assertEq(secondEscrow.tokenId, secondTokenId);
    }

    function test_createEscrow_reverts_zeroAmount() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        vm.expectRevert(Errors.EscrowManager__ZeroAmount.selector);
        IEscrowManager(_escrowManager).createEscrow(0, _company, _tokenAddr, _bondFTId);
    }

    function test_createEscrow_reverts_zeroDepositor() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        vm.expectRevert(Errors.EscrowManager__InvalidDepositor.selector);
        IEscrowManager(_escrowManager).createEscrow(_amount, address(0), _tokenAddr, _bondFTId);
    }

    function test_createEscrow_reverts_zeroTokenAddress() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        vm.expectRevert(Errors.EscrowManager__InvalidTokenAddress.selector);
        IEscrowManager(_escrowManager).createEscrow(_amount, _company, address(0), _bondFTId);
    }

    function test_createEscrow_reverts_notAuthorized() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__ModuleNotRegistered.selector, address(this)));
        IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);
    }

    function test_createEscrow_reverts_notAuthorizedAfterDeactivation() public {
        vm.startPrank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).registerModule(_auctionModuleType, _auctionModule);
        IEscrowManager(_escrowManager).deactivateModule(_auctionModuleType, _auctionModule);
        vm.stopPrank();

        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_auctionModule);
        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__ModuleNotRegistered.selector, _auctionModule));
        IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);
    }

    function test_createEscrow_reverts_tokenTransferReturnsFalse() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.mockCall(_tokenAddr, abi.encodeWithSelector(IERC6909.transferFrom.selector), abi.encode(false));

        vm.prank(_marketplace);
        vm.expectRevert(Errors.EscrowManager__TokensTransferFailed.selector);
        IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);
    }

    function test_createEscrow_reverts_assetManagerNotSet_onFreshDeployment() public {
        EscrowManager implementation = new EscrowManager();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), _deployer);
        bytes memory initData =
            abi.encodeWithSelector(EscrowManager.initialize.selector, _deployer, _marketplace, _orderbookMarketplace);
        address freshEscrowManager = address(new BeaconProxy(address(beacon), initData));

        vm.prank(_marketplace);
        vm.expectRevert(Errors.EscrowManager__AssetManagerNotSet.selector);
        IEscrowManager(freshEscrowManager).createEscrow(100, makeAddr("depositor"), makeAddr("token"), 0);
    }

    /*//////////////////////////////////////////////////////////////
                                WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function test_withdraw_success() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        Balances memory balancesBefore = _snapshotBalances();
        uint256 withdrawAmount = _amount / 2;

        vm.expectEmit();
        emit IEscrowManager.Withdrawn(escrowId, _company, withdrawAmount, _tokenAddr, _bondFTId, AssetType.ERC6909);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).withdraw(escrowId, withdrawAmount);

        Balances memory balancesAfter = _snapshotBalances();
        assertEq(balancesAfter.company, balancesBefore.company + withdrawAmount);
        assertEq(balancesAfter.escrow, balancesBefore.escrow - withdrawAmount);

        Escrow memory escrow = IEscrowManager(_escrowManager).getEscrow(escrowId);
        assertEq(escrow.amount, _amount - withdrawAmount);
    }

    function test_withdraw_reverts_moduleReplacementBlockedByActiveEscrow() public {
        address newMarketplace = makeAddr("newMarketplace");
        bytes32 moduleType = EscrowManager(_escrowManager).MARKETPLACE_MODULE();

        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        vm.startPrank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).registerModule(moduleType, newMarketplace);
        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__ModuleHasActiveEscrows.selector, _marketplace, 1));
        IEscrowManager(_escrowManager).deactivateModule(moduleType, _marketplace);
        vm.stopPrank();

        Escrow memory escrow = IEscrowManager(_escrowManager).getEscrow(escrowId);
        assertEq(escrow.amount, _amount);
    }

    function test_withdraw_reverts_notAuthorized_wrongModuleType() public {
        vm.prank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).registerModule(_auctionModuleType, _auctionModule);

        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.EscrowManager__ModuleNotAuthorized.selector,
                _auctionModule,
                EscrowManager(_escrowManager).MARKETPLACE_MODULE()
            )
        );
        vm.prank(_auctionModule);
        IEscrowManager(_escrowManager).withdraw(escrowId, _amount / 2);
    }

    function test_withdraw_reverts_notAuthorized_escrowDoesNotExist() public {
        vm.prank(_marketplace);
        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__EscrowNotFound.selector, 999));
        IEscrowManager(_escrowManager).withdraw(999, _amount);
    }

    function test_withdraw_reverts_insufficientBalance() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        vm.prank(_marketplace);
        vm.expectRevert(Errors.EscrowManager__InsufficientBalance.selector);
        IEscrowManager(_escrowManager).withdraw(escrowId, _amount + 1);
    }

    function test_withdraw_reverts_zeroAmount() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        vm.prank(_marketplace);
        vm.expectRevert(Errors.EscrowManager__ZeroAmount.selector);
        IEscrowManager(_escrowManager).withdraw(escrowId, 0);
    }

    function test_withdraw_reverts_tokenTransferFailed() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        vm.mockCall(_tokenAddr, abi.encodeWithSelector(IERC6909.transferFrom.selector), abi.encode(false));

        vm.prank(_marketplace);
        vm.expectRevert(Errors.EscrowManager__TokensTransferFailed.selector);
        IEscrowManager(_escrowManager).withdraw(escrowId, _amount / 2);
    }

    /*//////////////////////////////////////////////////////////////
                                CLAIM
    //////////////////////////////////////////////////////////////*/

    function test_claim_success() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        Balances memory balancesBefore = _snapshotBalances();
        uint256 claimAmount = _amount / 2;
        address beneficiary = makeAddr("beneficiary");
        (address beneficiaryWallet,) = _createAndRegisterEntityWalletForCompany(_erAdmin, beneficiary);

        vm.expectEmit();
        emit IEscrowManager.Claimed(escrowId, beneficiaryWallet, claimAmount, _tokenAddr, _bondFTId, AssetType.ERC6909);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).claim(escrowId, claimAmount, beneficiaryWallet);

        Balances memory balancesAfter = _snapshotBalances();
        assertEq(balancesAfter.escrow, balancesBefore.escrow - claimAmount);

        Escrow memory escrow = IEscrowManager(_escrowManager).getEscrow(escrowId);
        assertEq(escrow.amount, _amount - claimAmount);
    }

    function test_claim_reverts_insufficientBalance() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        vm.prank(_marketplace);
        vm.expectRevert(Errors.EscrowManager__InsufficientBalance.selector);
        IEscrowManager(_escrowManager).claim(escrowId, _amount + 1, makeAddr("beneficiary"));
    }

    function test_claim_reverts_zeroAmount() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        vm.prank(_marketplace);
        vm.expectRevert(Errors.EscrowManager__ZeroAmount.selector);
        IEscrowManager(_escrowManager).claim(escrowId, 0, makeAddr("beneficiary"));
    }

    function test_claim_reverts_zeroBeneficiary() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        vm.prank(_marketplace);
        vm.expectRevert(Errors.EscrowManager__InvalidBeneficiary.selector);
        IEscrowManager(_escrowManager).claim(escrowId, _amount, address(0));
    }

    function test_claim_reverts_escrowDoesNotExist() public {
        vm.prank(_marketplace);
        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__EscrowNotFound.selector, 999));
        IEscrowManager(_escrowManager).claim(999, _amount, makeAddr("beneficiary"));
    }

    function test_claim_reverts_notAuthorized_wrongModuleType() public {
        vm.prank(_escrowManagerAdmin);
        IEscrowManager(_escrowManager).registerModule(_auctionModuleType, _auctionModule);

        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.EscrowManager__ModuleNotAuthorized.selector,
                _auctionModule,
                EscrowManager(_escrowManager).MARKETPLACE_MODULE()
            )
        );
        vm.prank(_auctionModule);
        IEscrowManager(_escrowManager).claim(escrowId, _amount, makeAddr("beneficiary"));
    }

    function test_claim_reverts_tokenTransferFailed() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        address beneficiary = makeAddr("beneficiary");
        vm.mockCall(_tokenAddr, abi.encodeWithSelector(IERC6909.transferFrom.selector), abi.encode(false));

        vm.prank(_marketplace);
        vm.expectRevert(Errors.EscrowManager__TokensTransferFailed.selector);
        IEscrowManager(_escrowManager).claim(escrowId, _amount / 2, beneficiary);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function test_getEscrow_success() public {
        _approveEscrowManager(_company, _bondFTId, _amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(_amount, _company, _tokenAddr, _bondFTId);

        Escrow memory escrow = IEscrowManager(_escrowManager).getEscrow(escrowId);
        assertEq(escrow.depositor, _company);
        assertEq(escrow.tokenAddress, _tokenAddr);
        assertEq(escrow.tokenId, _bondFTId);
        assertEq(escrow.amount, _amount);
        assertEq(escrow.moduleType, EscrowManager(_escrowManager).MARKETPLACE_MODULE());
        assertEq(escrow.moduleAddress, _marketplace);
    }

    function test_getEscrow_empty() public view {
        Escrow memory escrow = IEscrowManager(_escrowManager).getEscrow(999);
        assertEq(escrow.depositor, address(0));
        assertEq(escrow.tokenAddress, address(0));
        assertEq(escrow.tokenId, 0);
        assertEq(escrow.amount, 0);
        assertEq(escrow.moduleType, bytes32(0));
        assertEq(escrow.moduleAddress, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            INTERFACE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function test_supportsInterface_success() public view {
        assertTrue(EscrowManager(_escrowManager).supportsInterface(type(IEscrowManager).interfaceId));
        assertFalse(EscrowManager(_escrowManager).supportsInterface(0xffffffff));
    }

    /*//////////////////////////////////////////////////////////////
                            TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    function _createTwoEscrowsWithSameToken(
        address firstModule,
        address secondModule,
        uint256 firstAmount,
        uint256 secondAmount
    ) internal returns (uint256 firstEscrowId, uint256 secondEscrowId) {
        _approveEscrowManager(_company, _bondFTId, firstAmount + secondAmount);

        vm.prank(firstModule);
        firstEscrowId = IEscrowManager(_escrowManager).createEscrow(firstAmount, _company, _tokenAddr, _bondFTId);

        vm.prank(secondModule);
        secondEscrowId = IEscrowManager(_escrowManager).createEscrow(secondAmount, _company, _tokenAddr, _bondFTId);
    }
}
