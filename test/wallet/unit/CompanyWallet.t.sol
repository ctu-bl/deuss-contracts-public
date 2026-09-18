// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {CompanyWallet} from "src/wallet/CompanyWallet.sol";
import {ICompanyWallet} from "src/wallet/ICompanyWallet.sol";
import {PolicyRegistry} from "src/registry/PolicyRegistry.sol";
import {Errors} from "src/libs/Errors.sol";
import {CompanyFixture} from "test/fixtures/CompanyFixture.t.sol";
import {MockTargetContract} from "test/mocks/MockContracts.sol";

contract MockCompanyWalletERC721 is ERC721 {
    constructor() ERC721("WalletMock721", "WM721") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract MockCompanyWalletERC1155 is ERC1155 {
    constructor() ERC1155("") {}

    function mint(address to, uint256 tokenId, uint256 amount) external {
        _mint(to, tokenId, amount, "");
    }
}

contract CompanyWalletStorageHarness is CompanyWallet {
    function exposedCompanyWalletStorageLocation() external pure returns (bytes32) {
        return _COMPANY_WALLET_STORAGE_LOCATION;
    }
}

contract CompanyWalletTest is CompanyFixture {
    CompanyWallet internal _wallet;
    PolicyRegistry internal _policyRegistry;
    MockTargetContract internal _target;
    address internal _operator;

    function setUp() public override {
        super.setUp();

        _wallet = CompanyWallet(payable(_cwAddr));
        _policyRegistry = PolicyRegistry(_suite.registries.walletPolicyRegistry);
        _target = new MockTargetContract();
        _operator = makeAddr("operator");
    }

    /*//////////////////////////////////////////////////////////////
                          ERC-7201 NAMESPACED STORAGE
    //////////////////////////////////////////////////////////////*/

    function test_namespacedStorageLocation_success_matchesErc7201Formula() public {
        CompanyWalletStorageHarness harness = new CompanyWalletStorageHarness();
        bytes32 storageLocation = harness.exposedCompanyWalletStorageLocation();

        assertEq(storageLocation, _erc7201Location("deuss.companyWallet.storage"));
        assertEq(uint256(storageLocation) & 0xff, 0);
    }

    function test_namespacedState_success_usesErc7201Storage() public {
        bytes32 root = _erc7201Location("deuss.companyWallet.storage");

        // `policyRegistry` is field offset 1 and `ownershipEpoch` is field offset 2 in CompanyWalletState.
        assertEq(_loadAddress(_cwAddr, _slotOffset(root, 1)), _wallet.policyRegistry());
        assertEq(uint256(vm.load(_cwAddr, _slotOffset(root, 2))), _wallet.ownershipEpoch());

        // A new policy registry write lands under the same namespaced slot.
        PolicyRegistry newPolicyRegistry = _deployPolicyRegistry(_deployer);
        vm.prank(_company);
        _wallet.setPolicyRegistry(address(newPolicyRegistry));
        assertEq(_loadAddress(_cwAddr, _slotOffset(root, 1)), address(newPolicyRegistry));
    }

    function test_ownerAndPolicyRegistry_areConfigured() public view {
        assertEq(_wallet.owner(), _company);
        assertEq(_wallet.policyRegistry(), _suite.registries.walletPolicyRegistry);
    }

    function test_initialize_revertWhenOwnerIsZeroAddress() public {
        CompanyWallet implementation = new CompanyWallet();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), _company);
        bytes memory initData =
            abi.encodeWithSelector(CompanyWallet.initialize.selector, address(0), address(_policyRegistry));

        vm.expectRevert(Errors.ZeroAddress.selector);
        new BeaconProxy(address(beacon), initData);
    }

    function test_initialize_revertWhenPolicyRegistryContractDoesNotSupportInterface() public {
        CompanyWallet implementation = new CompanyWallet();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), _company);
        MockTargetContract invalidRegistry = new MockTargetContract();
        bytes memory initData =
            abi.encodeWithSelector(CompanyWallet.initialize.selector, _company, address(invalidRegistry));

        vm.expectRevert(
            abi.encodeWithSelector(Errors.CompanyWallet__UnsupportedPolicyRegistry.selector, address(invalidRegistry))
        );
        new BeaconProxy(address(beacon), initData);
    }

    function test_setPolicyRegistry_success() public {
        PolicyRegistry newPolicyRegistry = _deployPolicyRegistry(_deployer);

        vm.expectEmit(true, true, false, false);
        emit ICompanyWallet.PolicyRegistryUpdated(_suite.registries.walletPolicyRegistry, address(newPolicyRegistry));

        vm.prank(_company);
        _wallet.setPolicyRegistry(address(newPolicyRegistry));

        assertEq(_wallet.policyRegistry(), address(newPolicyRegistry));
    }

    function test_setPolicyRegistry_revertWhenCallerIsNotOwner() public {
        vm.prank(_notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _wallet.setPolicyRegistry(address(_policyRegistry));
    }

    function test_setPolicyRegistry_revertWhenRegistryIsInvalid() public {
        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.CompanyWallet__InvalidPolicyRegistry.selector, address(0)));
        _wallet.setPolicyRegistry(address(0));

        address eoa = makeAddr("policyRegistryEoa");
        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.CompanyWallet__InvalidPolicyRegistry.selector, eoa));
        _wallet.setPolicyRegistry(eoa);
    }

    function test_setPolicyRegistry_revertWhenRegistryContractDoesNotSupportInterface() public {
        MockTargetContract invalidRegistry = new MockTargetContract();

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.CompanyWallet__UnsupportedPolicyRegistry.selector, address(invalidRegistry))
        );
        _wallet.setPolicyRegistry(address(invalidRegistry));
    }

    function test_execute_success_ownerBypassesPolicyRegistry() public {
        bytes memory callData = abi.encodeWithSelector(MockTargetContract.simulateSuccess.selector, true);

        vm.expectEmit(true, true, false, true);
        emit ICompanyWallet.Execution(_company, address(_target), 0, callData, "");

        vm.prank(_company);
        _wallet.execute(address(_target), 0, callData);

        assertTrue(_target.state());
    }

    function test_execute_success_nonOwnerWhenAuthorizedByPolicyRegistry() public {
        _authorizeOperator(_operator, MockTargetContract.simulateSuccess.selector, address(_target), 1);
        bytes memory callData = abi.encodeWithSelector(MockTargetContract.simulateSuccess.selector, true);

        vm.expectEmit(true, true, false, true);
        emit ICompanyWallet.Execution(_operator, address(_target), 0, callData, "");

        vm.prank(_operator);
        _wallet.execute(address(_target), 0, callData);

        assertTrue(_target.state());
    }

    function test_receive_success_directTransfer() public {
        uint256 amount = 1 ether;
        address funder = makeAddr("funder");
        vm.deal(funder, amount);

        vm.expectEmit(true, false, false, true);
        emit ICompanyWallet.NativeReceived(funder, amount);

        vm.prank(funder);
        (bool success,) = address(_wallet).call{value: amount}("");

        assertTrue(success);
        assertEq(address(_wallet).balance, amount);
    }

    function test_execute_success_ownerCanForwardPrefundedEth() public {
        uint256 amount = 1 ether;
        vm.deal(_company, amount);

        vm.prank(_company);
        (bool fundingSuccess,) = address(_wallet).call{value: amount}("");
        assertTrue(fundingSuccess);

        bytes memory callData = abi.encodeWithSelector(MockTargetContract.acceptEther.selector);

        vm.expectEmit(true, true, false, true);
        emit ICompanyWallet.Execution(_company, address(_target), amount, callData, "");

        vm.prank(_company);
        _wallet.execute(address(_target), amount, callData);

        assertTrue(_target.state());
        assertEq(_target.receivedValue(), amount);
        assertEq(address(_wallet).balance, 0);
    }

    function test_execute_success_ownerCanForwardMsgValue() public {
        uint256 amount = 1 ether;
        bytes memory callData = abi.encodeWithSelector(MockTargetContract.acceptEther.selector);
        vm.deal(_company, amount);

        vm.expectEmit(true, true, false, true);
        emit ICompanyWallet.Execution(_company, address(_target), amount, callData, "");

        vm.prank(_company);
        _wallet.execute{value: amount}(address(_target), amount, callData);

        assertTrue(_target.state());
        assertEq(_target.receivedValue(), amount);
        assertEq(address(_wallet).balance, 0);
    }

    function test_execute_revertWhenNonOwnerIsUnauthorized() public {
        bytes memory callData = abi.encodeWithSelector(MockTargetContract.simulateSuccess.selector, true);

        vm.prank(_operator);
        vm.expectRevert(Errors.CompanyWallet__Unauthorized.selector);
        _wallet.execute(address(_target), 0, callData);
    }

    function test_execute_revertWhenMsgValueDoesNotMatchForwardedValue() public {
        bytes memory callData = abi.encodeWithSelector(MockTargetContract.acceptEther.selector);
        vm.deal(_company, 1 ether);

        vm.prank(_company);
        vm.expectRevert(Errors.CompanyWallet__MsgValueMismatch.selector);
        _wallet.execute{value: 1 ether}(address(_target), 0.5 ether, callData);
    }

    function test_execute_revertWhenTargetIsInvalid() public {
        bytes memory callData = abi.encodeWithSelector(MockTargetContract.simulateSuccess.selector, true);

        vm.prank(_company);
        vm.expectRevert(Errors.CompanyWallet__InvalidCallTarget.selector);
        _wallet.execute(address(0), 0, callData);

        vm.prank(_company);
        vm.expectRevert(Errors.CompanyWallet__InvalidCallTarget.selector);
        _wallet.execute(_cwAddr, 0, callData);

        vm.prank(_company);
        vm.expectRevert(Errors.CompanyWallet__InvalidCallTarget.selector);
        _wallet.execute(makeAddr("eoaTarget"), 0, callData);
    }

    function test_execute_revertWhenCallDataIsTooShort() public {
        vm.prank(_company);
        vm.expectRevert(Errors.CompanyWallet__InvalidCallData.selector);
        _wallet.execute(address(_target), 0, hex"");
    }

    function test_execute_bubblesTargetRevert() public {
        _authorizeOperator(_operator, MockTargetContract.simulateFailure.selector, address(_target), 1);
        bytes memory callData = abi.encodeWithSelector(MockTargetContract.simulateFailure.selector);

        vm.prank(_operator);
        vm.expectRevert(bytes("External call failed"));
        _wallet.execute(address(_target), 0, callData);
    }

    function test_execute_revertDoesNotLeakPrefundedEthToTarget() public {
        uint256 amount = 1 ether;
        vm.deal(_company, amount);

        // ARRANGE: prefund
        vm.prank(_company);
        (bool fundingSuccess,) = address(_wallet).call{value: amount}("");
        assertTrue(fundingSuccess);
        assertEq(address(_wallet).balance, amount);

        bytes memory callData = abi.encodeWithSelector(MockTargetContract.acceptEtherThenRevert.selector);

        // ACT
        vm.prank(_company);
        vm.expectRevert(bytes("Reverted after receiving ETH"));
        _wallet.execute(address(_target), amount, callData);

        // ASSERT
        assertEq(address(_wallet).balance, amount);
        assertEq(address(_target).balance, 0);
        assertEq(_target.receivedValue(), 0);
    }

    function test_execute_revertDoesNotLeakMsgValueEthToTarget() public {
        uint256 amount = 1 ether;
        vm.deal(_company, amount);

        bytes memory callData = abi.encodeWithSelector(MockTargetContract.acceptEtherThenRevert.selector);

        // ACT
        vm.prank(_company);
        vm.expectRevert(bytes("Reverted after receiving ETH"));
        _wallet.execute{value: amount}(address(_target), amount, callData);

        // ASSERT
        assertEq(_company.balance, amount);
        assertEq(address(_wallet).balance, 0);
        assertEq(address(_target).balance, 0);
        assertEq(_target.receivedValue(), 0);
    }

    function test_supportsInterface() public view {
        assertTrue(_wallet.supportsInterface(type(ICompanyWallet).interfaceId));
        assertTrue(_wallet.supportsInterface(type(IERC165).interfaceId));
        assertTrue(_wallet.supportsInterface(type(IERC721Receiver).interfaceId));
        assertTrue(_wallet.supportsInterface(type(IERC1155Receiver).interfaceId));
        assertFalse(_wallet.supportsInterface(0xffffffff));
    }

    function test_receive_success_erc721SafeTransfer() public {
        MockCompanyWalletERC721 token = new MockCompanyWalletERC721();
        uint256 tokenId = 77;
        address sender = makeAddr("erc721Sender");

        token.mint(sender, tokenId);

        vm.prank(sender);
        token.safeTransferFrom(sender, address(_wallet), tokenId);

        assertEq(token.ownerOf(tokenId), address(_wallet));
    }

    function test_receive_success_erc1155SafeTransfer() public {
        MockCompanyWalletERC1155 token = new MockCompanyWalletERC1155();
        uint256 tokenId = 5;
        uint256 amount = 50;
        address sender = makeAddr("erc1155Sender");

        token.mint(sender, tokenId, amount);

        vm.prank(sender);
        token.safeTransferFrom(sender, address(_wallet), tokenId, amount, "");

        assertEq(token.balanceOf(address(_wallet), tokenId), amount);
    }

    /*//////////////////////////////////////////////////////////////
                          OWNERSHIP EPOCH
    //////////////////////////////////////////////////////////////*/

    function test_ownershipEpoch_startsAtOne() public view {
        assertEq(_wallet.ownershipEpoch(), 1);
    }

    function test_ownershipEpoch_incrementsOnTransferOwnership() public {
        vm.prank(_company);
        _wallet.transferOwnership(makeAddr("newOwner"));
        assertEq(_wallet.ownershipEpoch(), 2);
    }

    function test_ownershipEpoch_incrementsOnCompleteOwnershipHandover() public {
        address pendingOwner = makeAddr("pendingOwner");
        vm.prank(pendingOwner);
        _wallet.requestOwnershipHandover();

        vm.prank(_company);
        _wallet.completeOwnershipHandover(pendingOwner);

        assertEq(_wallet.ownershipEpoch(), 2);
    }

    function test_advancePolicyEpoch_success_whenCalledByOwner() public {
        bytes32 reason = keccak256("KERNEL_RECOVERY");

        vm.expectEmit(true, true, true, true);
        emit ICompanyWallet.OwnershipEpochAdvanced(1, 2, reason, _company);

        vm.prank(_company);
        _wallet.advancePolicyEpoch(reason);

        assertEq(_wallet.ownershipEpoch(), 2);
        assertEq(_wallet.owner(), _company);
    }

    function test_advancePolicyEpoch_reverts_zeroReason() public {
        vm.prank(_company);
        vm.expectRevert(Errors.CompanyWallet__ZeroPolicyEpochReason.selector);
        _wallet.advancePolicyEpoch(bytes32(0));
    }

    function test_advancePolicyEpoch_reverts_whenCallerIsNotOwner() public {
        vm.prank(_notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _wallet.advancePolicyEpoch(keccak256("KERNEL_RECOVERY"));
    }

    function test_ownershipEpoch_emitsOwnershipEpochAdvanced() public {
        address newOwner = makeAddr("newOwner");

        vm.expectEmit(true, true, true, true);
        emit ICompanyWallet.OwnershipEpochAdvanced(1, 2, bytes32(0), _company);

        vm.prank(_company);
        _wallet.transferOwnership(newOwner);
    }

    function test_transferOwnership_reverts_whenTransferringToSelf() public {
        vm.prank(_company);
        vm.expectRevert(Errors.CompanyWallet__OwnerTransferToSelf.selector);
        _wallet.transferOwnership(_company);
    }

    function test_renounceOwnership_reverts() public {
        vm.prank(_company);
        vm.expectRevert(Errors.CompanyWallet__RenounceOwnershipDisabled.selector);
        _wallet.renounceOwnership();
    }

    function _authorizeOperator(address operator, bytes4 selector, address target, uint256 roles) internal {
        vm.startPrank(_company);
        _policyRegistry.grantUserRoles(_cwAddr, operator, roles);
        _policyRegistry.grantOperationRoles(_cwAddr, target, selector, roles);
        vm.stopPrank();
    }
}
