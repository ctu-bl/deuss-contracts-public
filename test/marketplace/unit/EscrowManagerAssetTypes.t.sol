// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {MarketplaceFixture} from "test/fixtures/MarketplaceFixture.t.sol";
import {AssetManager} from "src/marketplace/AssetManager.sol";
import {EscrowManager} from "src/marketplace/EscrowManager.sol";
import {IEscrowManager} from "src/marketplace/interfaces/IEscrowManager.sol";
import {AssetType, Escrow} from "src/marketplace/MarketStructs.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";
import {Errors} from "src/libs/Errors.sol";

contract MockERC20Token is ERC20 {
    constructor() ERC20("Mock20", "M20") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockERC721Token is ERC721 {
    constructor() ERC721("Mock721", "M721") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract MockERC1155Token is ERC1155 {
    constructor() ERC1155("") {}

    function mint(address to, uint256 tokenId, uint256 amount) external {
        _mint(to, tokenId, amount, "");
    }
}

contract MockFeeOnTransferERC20 is ERC20 {
    constructor() ERC20("FeeToken", "FTK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fee = amount / 100; // 1% fee burned
            super._update(from, address(0), fee);
            super._update(from, to, amount - fee);
        } else {
            super._update(from, to, amount);
        }
    }
}

contract MockERC6909TransferFalse {
    mapping(address owner => mapping(uint256 tokenId => uint256 amount)) internal _balances;

    function mint(address to, uint256 tokenId, uint256 amount) external {
        _balances[to][tokenId] += amount;
    }

    function balanceOf(address owner, uint256 tokenId) external view returns (uint256) {
        return _balances[owner][tokenId];
    }

    function transferFrom(address, address, uint256, uint256) external pure returns (bool) {
        return false;
    }
}

// solhint-disable-next-line no-empty-blocks
contract NonReceiver {}

contract MockAssetManagerInvalidType {
    function validateAsset(address, uint256, uint256) external pure returns (AssetType, uint256) {
        return (AssetType.NONE, 0);
    }
}

contract MockAssetManagerERC721 {
    function validateAsset(address, uint256, uint256) external pure returns (AssetType, uint256) {
        return (AssetType.ERC721, 0);
    }
}

contract EscrowManagerHarness is EscrowManager {
    function setEscrowForTest(uint256 escrowId, Escrow calldata escrow_) external {
        EscrowManagerState storage $ = _escrowManagerStorage();
        $.escrows[escrowId] = escrow_;
        if (escrowId > $.nextEscrowId) {
            $.nextEscrowId = escrowId;
        }
        $.reservedByAsset[_assetKey(escrow_.assetType, escrow_.tokenAddress, escrow_.tokenId)] += escrow_.amount;
    }

    function setModuleStateForTest(bytes32 moduleType, address moduleAddress, bool authorized) external {
        EscrowManagerState storage $ = _escrowManagerStorage();
        $.moduleTypeOf[moduleAddress] = moduleType;
        $.isAuthorizedModule[moduleType][moduleAddress] = authorized;
    }

    function getReservedByAsset(AssetType assetType, address token, uint256 tokenId) external view returns (uint256) {
        return _escrowManagerStorage().reservedByAsset[_assetKey(assetType, token, tokenId)];
    }
}

contract EscrowManagerAssetTypesTest is MarketplaceFixture {
    function test_createWithdrawClaim_success_erc20() public {
        MockERC20Token token = new MockERC20Token();
        uint256 amount = 1_000e18;
        token.mint(_company, amount);

        _setAsset(address(token), AssetType.ERC20);

        vm.prank(_company);
        token.approve(_escrowManager, amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(amount, _company, address(token), 0);

        assertEq(token.balanceOf(_company), 0);
        assertEq(token.balanceOf(_escrowManager), amount);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).withdraw(escrowId, 300e18);
        assertEq(token.balanceOf(_company), 300e18);
        assertEq(token.balanceOf(_escrowManager), 700e18);

        address beneficiary = makeAddr("erc20Beneficiary");
        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).claim(escrowId, 200e18, beneficiary);
        assertEq(token.balanceOf(beneficiary), 200e18);
        assertEq(token.balanceOf(_escrowManager), 500e18);
    }

    function test_createAndClaim_success_erc721() public {
        MockERC721Token token = new MockERC721Token();
        uint256 tokenId = 77;
        token.mint(_company, tokenId);

        _setAsset(address(token), AssetType.ERC721);

        vm.prank(_company);
        token.approve(_escrowManager, tokenId);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(1, _company, address(token), tokenId);

        assertEq(token.ownerOf(tokenId), _escrowManager);

        address beneficiary = makeAddr("erc721Beneficiary");
        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).claim(escrowId, 1, beneficiary);
        assertEq(token.ownerOf(tokenId), beneficiary);
    }

    function test_createAndClaim_success_erc721ToCompanyWallet() public {
        MockERC721Token token = new MockERC721Token();
        uint256 tokenId = 78;
        token.mint(_company, tokenId);

        _setAsset(address(token), AssetType.ERC721);

        vm.prank(_company);
        token.approve(_escrowManager, tokenId);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(1, _company, address(token), tokenId);

        address beneficiaryOwner = makeAddr("erc721CompanyWalletOwner");
        (address beneficiaryWallet,) = _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, beneficiaryOwner);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).claim(escrowId, 1, beneficiaryWallet);

        assertEq(token.ownerOf(tokenId), beneficiaryWallet);
    }

    function test_createAndWithdraw_success_erc721ToCompanyWalletDepositor() public {
        MockERC721Token token = new MockERC721Token();
        uint256 tokenId = 79;
        token.mint(_company, tokenId);

        _setAsset(address(token), AssetType.ERC721);

        vm.prank(_company);
        token.approve(_escrowManager, tokenId);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(1, _company, address(token), tokenId);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).withdraw(escrowId, 1);

        assertEq(token.ownerOf(tokenId), _company);
    }

    function test_createWithdrawClaim_success_erc1155() public {
        MockERC1155Token token = new MockERC1155Token();
        uint256 tokenId = 5;
        uint256 amount = 50;
        address depositor = makeAddr("erc1155Depositor");
        token.mint(depositor, tokenId, amount);

        _setAsset(address(token), AssetType.ERC1155);

        vm.prank(depositor);
        token.setApprovalForAll(_escrowManager, true);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(amount, depositor, address(token), tokenId);

        assertEq(token.balanceOf(_escrowManager, tokenId), amount);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).withdraw(escrowId, 20);
        assertEq(token.balanceOf(depositor, tokenId), 20);

        address beneficiary = makeAddr("erc1155Beneficiary");
        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).claim(escrowId, 10, beneficiary);
        assertEq(token.balanceOf(beneficiary, tokenId), 10);
        assertEq(token.balanceOf(_escrowManager, tokenId), 20);
    }

    function test_createAndClaim_success_erc1155ToCompanyWallet() public {
        MockERC1155Token token = new MockERC1155Token();
        uint256 tokenId = 6;
        uint256 amount = 50;
        uint256 claimedAmount = 20;
        address depositor = makeAddr("erc1155WalletClaimDepositor");
        token.mint(depositor, tokenId, amount);

        _setAsset(address(token), AssetType.ERC1155);

        vm.prank(depositor);
        token.setApprovalForAll(_escrowManager, true);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(amount, depositor, address(token), tokenId);

        address beneficiaryOwner = makeAddr("erc1155CompanyWalletOwner");
        (address beneficiaryWallet,) = _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, beneficiaryOwner);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).claim(escrowId, claimedAmount, beneficiaryWallet);

        assertEq(token.balanceOf(beneficiaryWallet, tokenId), claimedAmount);
        assertEq(token.balanceOf(_escrowManager, tokenId), amount - claimedAmount);
    }

    function test_createAndWithdraw_success_erc1155ToCompanyWalletDepositor() public {
        MockERC1155Token token = new MockERC1155Token();
        uint256 tokenId = 7;
        uint256 amount = 50;
        uint256 withdrawnAmount = 20;
        token.mint(_company, tokenId, amount);

        _setAsset(address(token), AssetType.ERC1155);

        vm.prank(_company);
        token.setApprovalForAll(_escrowManager, true);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(amount, _company, address(token), tokenId);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).withdraw(escrowId, withdrawnAmount);

        assertEq(token.balanceOf(_company, tokenId), withdrawnAmount);
        assertEq(token.balanceOf(_escrowManager, tokenId), amount - withdrawnAmount);
    }

    function test_createWithdrawClaim_success_erc6909() public {
        uint256 amount = 1000;
        _setAsset(_tokenAddr, AssetType.ERC6909);
        assertTrue(IDEUSSToken(_tokenAddr).isAddressProtected(_escrowManager));

        _approveEscrowManager(_company, _bondFTId, amount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(amount, _company, _tokenAddr, _bondFTId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), amount);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).withdraw(escrowId, 300);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId), BOND_MAX_SUPPLY - amount + 300);

        address beneficiary = makeAddr("erc6909Beneficiary");
        _createAndRegisterEntityWallet(_entityRegistryAdmin, beneficiary);
        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).claim(escrowId, 200, beneficiary);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(beneficiary, _bondFTId), 200);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), 500);
    }

    function test_adminRecovery_reverts_protectedEscrow_erc6909() public {
        uint256 amount = 1000;
        _setAsset(_tokenAddr, AssetType.ERC6909);
        assertTrue(IDEUSSToken(_tokenAddr).isAddressProtected(_escrowManager));
        address beneficiary = makeAddr("protectedEscrowBeneficiary");
        _createAndRegisterEntityWallet(_entityRegistryAdmin, beneficiary);

        _approveEscrowManager(_company, _bondFTId, amount);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).createEscrow(amount, _company, _tokenAddr, _bondFTId);

        vm.prank(_brAddr);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__AddressProtected.selector, _escrowManager));
        IDEUSSToken(_tokenAddr).burn(_escrowManager, _bondFTId, 100);

        vm.prank(_tokenAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__AddressProtected.selector, _escrowManager));
        IDEUSSToken(_tokenAddr).forcedTransfer(_escrowManager, beneficiary, _bondFTId, 100);
    }

    function test_freezePartialTokens_reverts_protectedEscrow_erc6909() public {
        uint256 amount = 1000;
        _setAsset(_tokenAddr, AssetType.ERC6909);
        assertTrue(IDEUSSToken(_tokenAddr).isAddressProtected(_escrowManager));

        _approveEscrowManager(_company, _bondFTId, amount);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).createEscrow(amount, _company, _tokenAddr, _bondFTId);

        vm.prank(_tokenAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__AddressProtected.selector, _escrowManager));
        IDEUSSToken(_tokenAddr).freezePartialTokens(_escrowManager, _bondFTId, 100);
    }

    function test_createEscrow_reverts_invalidAssetType_fromManager() public {
        MockERC20Token token = new MockERC20Token();
        uint256 amount = 100e18;
        token.mint(_company, amount);
        address invalidTypeManager = address(new MockAssetManagerInvalidType());

        vm.prank(_adminID);
        EscrowManager(_escrowManager).setAssetManager(invalidTypeManager);

        vm.prank(_company);
        token.approve(_escrowManager, amount);

        vm.prank(_marketplace);
        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__InvalidAssetType.selector, uint8(AssetType.NONE)));
        IEscrowManager(_escrowManager).createEscrow(amount, _company, address(token), 0);
    }

    function test_createEscrow_reverts_invalidERC721Amount_fromManager() public {
        MockERC721Token token = new MockERC721Token();
        uint256 tokenId = 11;
        token.mint(_company, tokenId);
        address erc721Manager = address(new MockAssetManagerERC721());

        vm.prank(_adminID);
        EscrowManager(_escrowManager).setAssetManager(erc721Manager);

        vm.prank(_company);
        token.approve(_escrowManager, tokenId);

        vm.prank(_marketplace);
        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__InvalidERC721Amount.selector, 2));
        IEscrowManager(_escrowManager).createEscrow(2, _company, address(token), tokenId);
    }

    function test_withdraw_reverts_invalidAssetType_fromStoredEscrow() public {
        EscrowManagerHarness harness = _deployHarness();

        harness.setEscrowForTest(
            1,
            Escrow({
                depositor: _company,
                assetType: AssetType.NONE,
                tokenAddress: makeAddr("token"),
                tokenId: 1,
                amount: 2,
                moduleType: harness.MARKETPLACE_MODULE(),
                moduleAddress: address(0)
            })
        );

        vm.prank(_marketplace);
        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__InvalidAssetType.selector, uint8(AssetType.NONE)));
        harness.withdraw(1, 1);
    }

    function test_withdraw_reverts_invalidERC721Amount_fromStoredEscrow() public {
        EscrowManagerHarness harness = _deployHarness();

        harness.setEscrowForTest(
            1,
            Escrow({
                depositor: _company,
                assetType: AssetType.ERC721,
                tokenAddress: makeAddr("token"),
                tokenId: 1,
                amount: 2,
                moduleType: harness.MARKETPLACE_MODULE(),
                moduleAddress: address(0)
            })
        );

        vm.prank(_marketplace);
        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__InvalidERC721Amount.selector, 2));
        harness.withdraw(1, 2);
    }

    function test_claim_reverts_invalidAssetType_fromStoredEscrow() public {
        EscrowManagerHarness harness = _deployHarness();

        harness.setEscrowForTest(
            1,
            Escrow({
                depositor: _company,
                assetType: AssetType.NONE,
                tokenAddress: makeAddr("token"),
                tokenId: 1,
                amount: 1,
                moduleType: harness.MARKETPLACE_MODULE(),
                moduleAddress: address(0)
            })
        );

        vm.prank(_marketplace);
        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__InvalidAssetType.selector, uint8(AssetType.NONE)));
        harness.claim(1, 1, makeAddr("beneficiary"));
    }

    function test_registerModule_success_whenBoundToSameTypeButUnauthorized() public {
        EscrowManagerHarness harness = _deployHarness();
        bytes32 moduleType = keccak256("LEGACY_MODULE");
        address moduleAddress = makeAddr("legacyModule");

        harness.setModuleStateForTest(moduleType, moduleAddress, false);

        address harnessOwner = harness.owner();
        uint256 adminRole = harness.ADMIN();
        vm.prank(harnessOwner);
        harness.grantRoles(_adminID, adminRole);
        assertTrue(harness.hasAnyRole(_adminID, adminRole));

        vm.expectEmit();
        emit IEscrowManager.ModuleRegistered(moduleType, moduleAddress);

        vm.prank(_adminID);
        harness.registerModule(moduleType, moduleAddress);

        assertEq(harness.moduleTypeOf(moduleAddress), moduleType);
        assertTrue(harness.isAuthorizedModule(moduleType, moduleAddress));
    }

    function _setAsset(address token, AssetType assetType) internal {
        vm.prank(_adminID);
        AssetManager(_assetManager).setAsset(token, assetType, true, false);
    }

    function _deployHarness() internal returns (EscrowManagerHarness harness) {
        EscrowManagerHarness implementation = new EscrowManagerHarness();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), _deployer);
        bytes memory initData =
            abi.encodeWithSelector(EscrowManager.initialize.selector, _deployer, _marketplace, _orderbookMarketplace);
        harness = EscrowManagerHarness(address(new BeaconProxy(address(beacon), initData)));
    }

    function _deployHarnessWithAdmin(address admin) internal returns (EscrowManagerHarness harness) {
        harness = _deployHarness();
        address harnessOwner = harness.owner();
        uint256 adminRole = harness.ADMIN();
        vm.prank(harnessOwner);
        harness.grantRoles(admin, adminRole);
        vm.prank(admin);
        harness.setAssetManager(_assetManager);
    }

    /*//////////////////////////////////////////////////////////////
                            RESERVED ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    function test_sweep_createEscrow_incrementsReserved_erc20() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();
        uint256 amount = 500e18;
        token.mint(_company, amount);
        _setAsset(address(token), AssetType.ERC20);

        vm.prank(_company);
        token.approve(address(harness), amount);

        vm.prank(_marketplace);
        harness.createEscrow(amount, _company, address(token), 0);

        assertEq(harness.getReservedByAsset(AssetType.ERC20, address(token), 0), amount);
    }

    function test_sweep_createEscrow_incrementsReserved_erc721() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC721Token token = new MockERC721Token();
        uint256 tokenId = 42;
        token.mint(_company, tokenId);
        _setAsset(address(token), AssetType.ERC721);

        vm.prank(_company);
        token.approve(address(harness), tokenId);

        vm.prank(_marketplace);
        harness.createEscrow(1, _company, address(token), tokenId);

        assertEq(harness.getReservedByAsset(AssetType.ERC721, address(token), tokenId), 1);
    }

    function test_sweep_createEscrow_incrementsReserved_erc1155() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC1155Token token = new MockERC1155Token();
        uint256 tokenId = 7;
        uint256 amount = 100;
        address depositor = makeAddr("erc1155Depositor");
        token.mint(depositor, tokenId, amount);
        _setAsset(address(token), AssetType.ERC1155);

        vm.prank(depositor);
        token.setApprovalForAll(address(harness), true);

        vm.prank(_marketplace);
        harness.createEscrow(amount, depositor, address(token), tokenId);

        assertEq(harness.getReservedByAsset(AssetType.ERC1155, address(token), tokenId), amount);
    }

    function test_sweep_withdraw_decrementsReserved() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();
        uint256 amount = 500e18;
        token.mint(_company, amount);
        _setAsset(address(token), AssetType.ERC20);

        vm.prank(_company);
        token.approve(address(harness), amount);

        vm.prank(_marketplace);
        uint256 escrowId = harness.createEscrow(amount, _company, address(token), 0);

        vm.prank(_marketplace);
        harness.withdraw(escrowId, 200e18);

        assertEq(harness.getReservedByAsset(AssetType.ERC20, address(token), 0), 300e18);
    }

    function test_sweep_claim_decrementsReserved() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();
        uint256 amount = 500e18;
        token.mint(_company, amount);
        _setAsset(address(token), AssetType.ERC20);

        vm.prank(_company);
        token.approve(address(harness), amount);

        vm.prank(_marketplace);
        uint256 escrowId = harness.createEscrow(amount, _company, address(token), 0);

        vm.prank(_marketplace);
        harness.claim(escrowId, 150e18, makeAddr("sweepClaimBeneficiary"));

        assertEq(harness.getReservedByAsset(AssetType.ERC20, address(token), 0), 350e18);
    }

    function test_createEscrow_reservedAccountingInvariant_noSurplus_erc6909() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).createEscrow(BOND_MAX_SUPPLY, _company, _tokenAddr, _bondFTId);

        // Entire balance is reserved — surplus must be zero
        assertEq(IEscrowManager(_escrowManager).getSweepableAmount(AssetType.ERC6909, _tokenAddr, _bondFTId), 0);
    }

    function test_createEscrow_success_protectedEscrowManagerPullsErc6909() public {
        uint256 escrowAmount = BOND_MAX_SUPPLY / 4;
        assertTrue(IDEUSSToken(_tokenAddr).isAddressProtected(_escrowManager));

        _approveEscrowManager(_company, _bondFTId, escrowAmount);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(escrowAmount, _company, _tokenAddr, _bondFTId);

        Escrow memory escrow = IEscrowManager(_escrowManager).getEscrow(escrowId);
        assertEq(escrow.amount, escrowAmount);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), escrowAmount);
    }

    function test_createEscrow_multipleEscrows_accumulatesReserved_erc6909() public {
        uint256 firstAmount = BOND_MAX_SUPPLY / 4;
        uint256 secondAmount = BOND_MAX_SUPPLY / 5;
        _approveEscrowManager(_company, _bondFTId, firstAmount + secondAmount);

        vm.startPrank(_marketplace);
        IEscrowManager(_escrowManager).createEscrow(firstAmount, _company, _tokenAddr, _bondFTId);
        IEscrowManager(_escrowManager).createEscrow(secondAmount, _company, _tokenAddr, _bondFTId);
        vm.stopPrank();

        // Both amounts reserved — no surplus
        assertEq(IEscrowManager(_escrowManager).getSweepableAmount(AssetType.ERC6909, _tokenAddr, _bondFTId), 0);
    }

    function test_withdraw_decrementsReservedAccounting_erc6909() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(BOND_MAX_SUPPLY, _company, _tokenAddr, _bondFTId);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).withdraw(escrowId, BOND_MAX_SUPPLY / 2);

        // Reserved decreased with withdrawal — remaining balance still fully reserved
        assertEq(IEscrowManager(_escrowManager).getSweepableAmount(AssetType.ERC6909, _tokenAddr, _bondFTId), 0);
    }

    function test_claim_decrementsReservedAccounting_erc6909() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);

        vm.prank(_marketplace);
        uint256 escrowId = IEscrowManager(_escrowManager).createEscrow(BOND_MAX_SUPPLY, _company, _tokenAddr, _bondFTId);

        address beneficiary = makeAddr("accountingBeneficiary");
        (address beneficiaryWallet,) = _createAndRegisterEntityWalletForCompany(_erAdmin, beneficiary);
        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).claim(escrowId, BOND_MAX_SUPPLY / 2, beneficiaryWallet);

        // Reserved decreased with claim — remaining balance still fully reserved
        assertEq(IEscrowManager(_escrowManager).getSweepableAmount(AssetType.ERC6909, _tokenAddr, _bondFTId), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            SWEEP - SUCCESS
    //////////////////////////////////////////////////////////////*/

    function test_sweep_erc20_surplusOnly() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();
        uint256 escrowAmount = 500e18;
        uint256 strayAmount = 100e18;
        address beneficiary = makeAddr("sweepErc20Beneficiary");
        _setAsset(address(token), AssetType.ERC20);

        token.mint(_company, escrowAmount);
        token.mint(address(harness), strayAmount);

        vm.prank(_company);
        token.approve(address(harness), escrowAmount);

        vm.prank(_marketplace);
        harness.createEscrow(escrowAmount, _company, address(token), 0);

        assertEq(harness.getSweepableAmount(AssetType.ERC20, address(token), 0), strayAmount);

        vm.expectEmit();
        emit IEscrowManager.Swept(AssetType.ERC20, address(token), 0, beneficiary, strayAmount);

        vm.prank(_adminID);
        harness.sweep(AssetType.ERC20, address(token), 0, strayAmount, beneficiary);

        assertEq(token.balanceOf(beneficiary), strayAmount);
        assertEq(harness.getSweepableAmount(AssetType.ERC20, address(token), 0), 0);
        assertEq(harness.getReservedByAsset(AssetType.ERC20, address(token), 0), escrowAmount);
    }

    function test_sweep_erc20_partialSurplus() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();
        address beneficiary = makeAddr("sweepPartialBeneficiary");
        token.mint(address(harness), 100e18);

        vm.prank(_adminID);
        harness.sweep(AssetType.ERC20, address(token), 0, 40e18, beneficiary);

        assertEq(token.balanceOf(beneficiary), 40e18);
        assertEq(harness.getSweepableAmount(AssetType.ERC20, address(token), 0), 60e18);
    }

    function test_sweep_erc721_unreservedToken() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC721Token token = new MockERC721Token();
        uint256 tokenId = 99;
        address beneficiary = makeAddr("sweepErc721Beneficiary");
        token.mint(address(harness), tokenId);

        assertEq(harness.getSweepableAmount(AssetType.ERC721, address(token), tokenId), 1);

        vm.prank(_adminID);
        harness.sweep(AssetType.ERC721, address(token), tokenId, 1, beneficiary);

        assertEq(token.ownerOf(tokenId), beneficiary);
        assertEq(harness.getSweepableAmount(AssetType.ERC721, address(token), tokenId), 0);
    }

    function test_sweep_erc1155_surplusOnly() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC1155Token token = new MockERC1155Token();
        uint256 tokenId = 5;
        uint256 escrowAmount = 50;
        uint256 strayAmount = 20;
        address depositor = makeAddr("sweepErc1155Depositor");
        address beneficiary = makeAddr("sweepErc1155Beneficiary");
        _setAsset(address(token), AssetType.ERC1155);

        token.mint(depositor, tokenId, escrowAmount);
        token.mint(address(harness), tokenId, strayAmount);

        vm.prank(depositor);
        token.setApprovalForAll(address(harness), true);

        vm.prank(_marketplace);
        harness.createEscrow(escrowAmount, depositor, address(token), tokenId);

        assertEq(harness.getSweepableAmount(AssetType.ERC1155, address(token), tokenId), strayAmount);

        vm.prank(_adminID);
        harness.sweep(AssetType.ERC1155, address(token), tokenId, strayAmount, beneficiary);

        assertEq(token.balanceOf(beneficiary, tokenId), strayAmount);
        assertEq(harness.getSweepableAmount(AssetType.ERC1155, address(token), tokenId), 0);
    }

    function test_sweep_erc1155_partialSurplus() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC1155Token token = new MockERC1155Token();
        uint256 tokenId = 5;
        address beneficiary = makeAddr("sweepErc1155PartialBeneficiary");

        token.mint(address(harness), tokenId, 100);

        vm.prank(_adminID);
        harness.sweep(AssetType.ERC1155, address(token), tokenId, 40, beneficiary);

        assertEq(token.balanceOf(beneficiary, tokenId), 40);
        assertEq(harness.getSweepableAmount(AssetType.ERC1155, address(token), tokenId), 60);
    }

    function test_sweep_erc6909_surplusOnly() public {
        uint256 escrowAmount = 500;
        uint256 strayAmount = 100;
        address beneficiary = makeAddr("sweepErc6909Beneficiary");
        _createAndRegisterEntityWallet(_entityRegistryAdmin, beneficiary);

        _approveEscrowManager(_company, _bondFTId, escrowAmount + strayAmount);

        vm.prank(_marketplace);
        IEscrowManager(_escrowManager).createEscrow(escrowAmount, _company, _tokenAddr, _bondFTId);

        vm.prank(_escrowManager);
        IDEUSSToken(_tokenAddr).transferFrom(_company, _escrowManager, _bondFTId, strayAmount);

        assertEq(
            IEscrowManager(_escrowManager).getSweepableAmount(AssetType.ERC6909, _tokenAddr, _bondFTId), strayAmount
        );

        vm.prank(_adminID);
        EscrowManager(_escrowManager).sweep(AssetType.ERC6909, _tokenAddr, _bondFTId, strayAmount, beneficiary);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(beneficiary, _bondFTId), strayAmount);
        assertEq(IEscrowManager(_escrowManager).getSweepableAmount(AssetType.ERC6909, _tokenAddr, _bondFTId), 0);
    }

    function test_sweep_erc6909_partialSurplus() public {
        uint256 strayAmount = 100;
        uint256 sweptAmount = 40;
        address beneficiary = makeAddr("sweepErc6909PartialBeneficiary");
        _createAndRegisterEntityWallet(_entityRegistryAdmin, beneficiary);

        _approveEscrowManager(_company, _bondFTId, strayAmount);

        vm.prank(_escrowManager);
        IDEUSSToken(_tokenAddr).transferFrom(_company, _escrowManager, _bondFTId, strayAmount);

        vm.prank(_adminID);
        EscrowManager(_escrowManager).sweep(AssetType.ERC6909, _tokenAddr, _bondFTId, sweptAmount, beneficiary);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(beneficiary, _bondFTId), sweptAmount);
        assertEq(
            IEscrowManager(_escrowManager).getSweepableAmount(AssetType.ERC6909, _tokenAddr, _bondFTId),
            strayAmount - sweptAmount
        );
    }

    /*//////////////////////////////////////////////////////////////
                            SWEEP - REVERTS
    //////////////////////////////////////////////////////////////*/

    function test_sweep_reverts_zeroAmount() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();

        vm.prank(_adminID);
        vm.expectRevert(Errors.EscrowManager__InvalidSweepAmount.selector);
        harness.sweep(AssetType.ERC20, address(token), 0, 0, makeAddr("b"));
    }

    function test_sweep_reverts_zeroBeneficiary() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();
        token.mint(address(harness), 100e18);

        vm.prank(_adminID);
        vm.expectRevert(Errors.EscrowManager__InvalidBeneficiary.selector);
        harness.sweep(AssetType.ERC20, address(token), 0, 50e18, address(0));
    }

    function test_sweep_reverts_invalidAssetType_none() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();

        vm.prank(_adminID);
        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__InvalidAssetType.selector, uint8(AssetType.NONE)));
        harness.sweep(AssetType.NONE, address(token), 0, 1, makeAddr("b"));
    }

    function test_sweep_reverts_notAdmin() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();
        token.mint(address(harness), 100e18);

        address notAdmin = makeAddr("notAdmin");
        vm.prank(notAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        harness.sweep(AssetType.ERC20, address(token), 0, 50e18, makeAddr("b"));
    }

    function test_sweep_reverts_exceedsSurplus() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();
        uint256 escrowAmount = 500e18;
        uint256 strayAmount = 100e18;
        _setAsset(address(token), AssetType.ERC20);

        token.mint(_company, escrowAmount);
        token.mint(address(harness), strayAmount);

        vm.prank(_company);
        token.approve(address(harness), escrowAmount);

        vm.prank(_marketplace);
        harness.createEscrow(escrowAmount, _company, address(token), 0);

        vm.prank(_adminID);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EscrowManager__SweepExceedsSurplus.selector, strayAmount + 1, strayAmount)
        );
        harness.sweep(AssetType.ERC20, address(token), 0, strayAmount + 1, makeAddr("b"));
    }

    function test_sweep_reverts_noSurplus() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();
        uint256 amount = 500e18;
        _setAsset(address(token), AssetType.ERC20);

        token.mint(_company, amount);

        vm.prank(_company);
        token.approve(address(harness), amount);

        vm.prank(_marketplace);
        harness.createEscrow(amount, _company, address(token), 0);

        vm.prank(_adminID);
        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__SweepExceedsSurplus.selector, 1, 0));
        harness.sweep(AssetType.ERC20, address(token), 0, 1, makeAddr("b"));
    }

    function test_sweep_reverts_erc20_nonZeroTokenId_cannotAccessReservedBalance() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();
        uint256 escrowAmount = 500e18;
        uint256 strayAmount = 100e18;
        uint256 wrongTokenId = 123;
        _setAsset(address(token), AssetType.ERC20);

        token.mint(_company, escrowAmount);
        token.mint(address(harness), strayAmount);

        vm.prank(_company);
        token.approve(address(harness), escrowAmount);

        vm.prank(_marketplace);
        harness.createEscrow(escrowAmount, _company, address(token), 0);

        vm.prank(_adminID);
        vm.expectRevert(abi.encodeWithSelector(Errors.AssetManager__InvalidTokenId.selector, wrongTokenId));
        harness.sweep(AssetType.ERC20, address(token), wrongTokenId, strayAmount + 1, makeAddr("b"));
    }

    function test_sweep_reverts_erc721_invalidAmount() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC721Token token = new MockERC721Token();

        vm.prank(_adminID);
        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__InvalidERC721Amount.selector, 2));
        harness.sweep(AssetType.ERC721, address(token), 1, 2, makeAddr("b"));
    }

    function test_sweep_reverts_erc721_receiverRejected() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC721Token token = new MockERC721Token();
        uint256 tokenId = 99;
        NonReceiver beneficiary = new NonReceiver();

        token.mint(address(harness), tokenId);

        vm.prank(_adminID);
        vm.expectRevert();
        harness.sweep(AssetType.ERC721, address(token), tokenId, 1, address(beneficiary));
    }

    function test_sweep_reverts_erc1155_receiverRejected() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC1155Token token = new MockERC1155Token();
        uint256 tokenId = 5;
        NonReceiver beneficiary = new NonReceiver();

        token.mint(address(harness), tokenId, 10);

        vm.prank(_adminID);
        vm.expectRevert();
        harness.sweep(AssetType.ERC1155, address(token), tokenId, 10, address(beneficiary));
    }

    function test_sweep_reverts_erc6909_transferFailure() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC6909TransferFalse token = new MockERC6909TransferFalse();
        uint256 tokenId = 7;

        token.mint(address(harness), tokenId, 100);

        vm.prank(_adminID);
        vm.expectRevert(Errors.EscrowManager__TokensTransferFailed.selector);
        harness.sweep(AssetType.ERC6909, address(token), tokenId, 100, makeAddr("b"));
    }

    function test_sweep_reverts_reservedErc721() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC721Token token = new MockERC721Token();
        uint256 tokenId = 10;
        _setAsset(address(token), AssetType.ERC721);

        token.mint(_company, tokenId);
        vm.prank(_company);
        token.approve(address(harness), tokenId);

        vm.prank(_marketplace);
        harness.createEscrow(1, _company, address(token), tokenId);

        assertEq(harness.getSweepableAmount(AssetType.ERC721, address(token), tokenId), 0);

        vm.prank(_adminID);
        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__SweepExceedsSurplus.selector, 1, 0));
        harness.sweep(AssetType.ERC721, address(token), tokenId, 1, makeAddr("b"));
    }

    /*//////////////////////////////////////////////////////////////
                        SWEEP - MIXED SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_sweep_mixedEscrowsAndStray_sameAsset() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();
        uint256 escrow1 = 300e18;
        uint256 escrow2 = 200e18;
        uint256 stray = 150e18;
        address beneficiary = makeAddr("sweepMixedBeneficiary");
        _setAsset(address(token), AssetType.ERC20);

        token.mint(_company, escrow1 + escrow2);
        token.mint(address(harness), stray);

        vm.prank(_company);
        token.approve(address(harness), escrow1 + escrow2);

        vm.startPrank(_marketplace);
        uint256 escrowId1 = harness.createEscrow(escrow1, _company, address(token), 0);
        harness.createEscrow(escrow2, _company, address(token), 0);
        vm.stopPrank();

        vm.prank(_marketplace);
        harness.withdraw(escrowId1, 100e18);

        // reserved = 300 + 200 - 100 = 400, actual = 300 + 200 + 150 - 100 = 550, surplus = 150
        assertEq(harness.getSweepableAmount(AssetType.ERC20, address(token), 0), stray);

        vm.prank(_adminID);
        harness.sweep(AssetType.ERC20, address(token), 0, stray, beneficiary);

        assertEq(token.balanceOf(beneficiary), stray);
        assertEq(harness.getSweepableAmount(AssetType.ERC20, address(token), 0), 0);
    }

    function test_sweep_differentTokenIds_tracked_independently() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC1155Token token = new MockERC1155Token();
        uint256 tokenId1 = 1;
        uint256 tokenId2 = 2;
        address depositor = makeAddr("sweepMultiIdDepositor");
        address beneficiary = makeAddr("sweepMultiIdBeneficiary");
        _setAsset(address(token), AssetType.ERC1155);

        token.mint(depositor, tokenId1, 100);
        token.mint(depositor, tokenId2, 50);
        token.mint(address(harness), tokenId1, 30);
        token.mint(address(harness), tokenId2, 10);

        vm.prank(depositor);
        token.setApprovalForAll(address(harness), true);

        vm.startPrank(_marketplace);
        harness.createEscrow(100, depositor, address(token), tokenId1);
        harness.createEscrow(50, depositor, address(token), tokenId2);
        vm.stopPrank();

        assertEq(harness.getSweepableAmount(AssetType.ERC1155, address(token), tokenId1), 30);
        assertEq(harness.getSweepableAmount(AssetType.ERC1155, address(token), tokenId2), 10);

        vm.prank(_adminID);
        harness.sweep(AssetType.ERC1155, address(token), tokenId1, 30, beneficiary);

        assertEq(harness.getSweepableAmount(AssetType.ERC1155, address(token), tokenId2), 10);
        assertEq(token.balanceOf(beneficiary, tokenId1), 30);
    }

    function test_getSweepableAmount_noBalance_returnsZero() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();

        assertEq(harness.getSweepableAmount(AssetType.ERC20, address(token), 0), 0);
    }

    function test_getSweepableAmount_reverts_invalidAssetType_none() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();

        vm.expectRevert(abi.encodeWithSelector(Errors.EscrowManager__InvalidAssetType.selector, uint8(AssetType.NONE)));
        harness.getSweepableAmount(AssetType.NONE, address(token), 0);
    }

    function test_getSweepableAmount_reverts_erc20_nonZeroTokenId() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();
        uint256 wrongTokenId = 123;

        vm.expectRevert(abi.encodeWithSelector(Errors.AssetManager__InvalidTokenId.selector, wrongTokenId));
        harness.getSweepableAmount(AssetType.ERC20, address(token), wrongTokenId);
    }

    function test_getSweepableAmount_erc721_notOwned_returnsZero() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC721Token token = new MockERC721Token();

        assertEq(harness.getSweepableAmount(AssetType.ERC721, address(token), 999), 0);
    }

    function test_getSweepableAmount_erc1155_noBalance_returnsZero() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC1155Token token = new MockERC1155Token();

        assertEq(harness.getSweepableAmount(AssetType.ERC1155, address(token), 5), 0);
    }

    function test_getSweepableAmount_erc6909_noBalance_returnsZero() public view {
        assertEq(IEscrowManager(_escrowManager).getSweepableAmount(AssetType.ERC6909, _tokenAddr, _bondFTId), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    CREATE ESCROW - DEPOSIT AMOUNT CHECK
    //////////////////////////////////////////////////////////////*/

    function test_createEscrow_reverts_depositAmountMismatch_erc20() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockFeeOnTransferERC20 token = new MockFeeOnTransferERC20();
        uint256 amount = 100e18;
        token.mint(_company, amount);
        _setAsset(address(token), AssetType.ERC20);

        vm.prank(_company);
        token.approve(address(harness), amount);

        vm.prank(_marketplace);
        vm.expectRevert(Errors.EscrowManager__DepositAmountMismatch.selector);
        harness.createEscrow(amount, _company, address(token), 0);
    }

    function test_createEscrow_success_exactDepositReceived_erc20() public {
        EscrowManagerHarness harness = _deployHarnessWithAdmin(_adminID);
        MockERC20Token token = new MockERC20Token();
        uint256 amount = 500e18;
        token.mint(_company, amount);
        _setAsset(address(token), AssetType.ERC20);

        vm.prank(_company);
        token.approve(address(harness), amount);

        vm.prank(_marketplace);
        uint256 escrowId = harness.createEscrow(amount, _company, address(token), 0);

        assertEq(token.balanceOf(address(harness)), amount);
        assertEq(harness.getReservedByAsset(AssetType.ERC20, address(token), 0), amount);
        assertEq(harness.getEscrow(escrowId).amount, amount);
    }
}
