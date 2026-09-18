// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";
import {AssetManager} from "src/marketplace/AssetManager.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {IEscrowManager} from "src/marketplace/interfaces/IEscrowManager.sol";
import {AssetType, CounterOfferInput, OfferInput, SaleMode} from "src/marketplace/MarketStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {AccountStatus} from "src/registry/EntityStructs.sol";
import {MarketplaceFixture} from "test/fixtures/MarketplaceFixture.t.sol";

contract MockInterestERC20 is ERC20 {
    constructor() ERC20("Mock20", "M20") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ReentrantRegisterOfferERC20 is ERC20 {
    bytes4 internal constant _REENTRANCY_SELECTOR = bytes4(keccak256("Reentrancy()"));

    Marketplace internal _target;
    OfferInput internal _reentrantOffer;
    bool internal _attemptedReentry;
    bool internal _reentrancyBlocked;
    bool internal _reenteredSuccessfully;

    constructor() ERC20("Reentrant20", "R20") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function configure(address target, address escrowManager, OfferInput calldata offer) external {
        _target = Marketplace(target);
        _reentrantOffer = offer;
        _approve(address(this), escrowManager, type(uint256).max);
    }

    function attemptedReentry() external view returns (bool) {
        return _attemptedReentry;
    }

    function reentrancyBlocked() external view returns (bool) {
        return _reentrancyBlocked;
    }

    function reenteredSuccessfully() external view returns (bool) {
        return _reenteredSuccessfully;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (!_attemptedReentry && address(_target) != address(0)) {
            _attemptedReentry = true;
            try _target.registerOffer(_reentrantOffer) returns (uint256) {
                _reenteredSuccessfully = true;
            } catch (bytes memory reason) {
                // forge-lint: disable-next-line(unsafe-typecast)
                if (reason.length > 3 && bytes4(reason) == _REENTRANCY_SELECTOR) {
                    _reentrancyBlocked = true;
                }
            }
        }
        return super.transferFrom(from, to, value);
    }
}

contract ReentrantAcceptOfferERC20 is ERC20 {
    Marketplace internal _target;
    uint256 internal _offerId;
    uint256 internal _amount;
    bool internal _attemptedAccept;
    bool internal _acceptBlocked;
    bool internal _acceptSucceeded;

    constructor() ERC20("ReentrantAccept20", "RA20") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function configure(address target, uint256 offerId, uint256 amount) external {
        _target = Marketplace(target);
        _offerId = offerId;
        _amount = amount;
    }

    function attemptedAccept() external view returns (bool) {
        return _attemptedAccept;
    }

    function acceptBlocked() external view returns (bool) {
        return _acceptBlocked;
    }

    function acceptSucceeded() external view returns (bool) {
        return _acceptSucceeded;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (!_attemptedAccept && address(_target) != address(0)) {
            _attemptedAccept = true;
            try _target.acceptOffer(_offerId, _amount) returns (uint256) {
                _acceptSucceeded = true;
            } catch {
                _acceptBlocked = true;
            }
        }
        return super.transferFrom(from, to, value);
    }
}

contract ReentrantMarketplaceCallERC20 is ERC20 {
    bytes4 internal constant _REENTRANCY_SELECTOR = bytes4(keccak256("Reentrancy()"));

    address internal _target;
    bytes internal _payload;
    bool internal _attemptedCall;
    bool internal _reentrancyBlocked;
    bool internal _callSucceeded;

    constructor() ERC20("ReentrantCall20", "RC20") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function configure(address target, address escrowManager, bytes calldata payload) external {
        _target = target;
        _payload = payload;
        _approve(address(this), escrowManager, type(uint256).max);
    }

    function attemptedCall() external view returns (bool) {
        return _attemptedCall;
    }

    function reentrancyBlocked() external view returns (bool) {
        return _reentrancyBlocked;
    }

    function callSucceeded() external view returns (bool) {
        return _callSucceeded;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (!_attemptedCall && _target != address(0)) {
            _attemptedCall = true;
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, bytes memory reason) = _target.call(_payload);
            if (success) {
                _callSucceeded = true;
            } else {
                // forge-lint: disable-next-line(unsafe-typecast)
                if (reason.length > 3 && bytes4(reason) == _REENTRANCY_SELECTOR) {
                    _reentrancyBlocked = true;
                }
            }
        }
        return super.transferFrom(from, to, value);
    }
}

contract MockInterestERC721 is ERC721 {
    constructor() ERC721("Mock721", "M721") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract MockInterestERC1155 is ERC1155 {
    constructor() ERC1155("") {}

    function mint(address to, uint256 tokenId, uint256 amount) external {
        _mint(to, tokenId, amount, "");
    }
}

contract MarketplaceAssetTypesTest is MarketplaceFixture {
    function test_registerOffer_blocksReentrantTokenCallback() public {
        ReentrantRegisterOfferERC20 token = new ReentrantRegisterOfferERC20();
        uint256 outerAmount = 100e18;
        uint256 innerAmount = 40e18;
        uint256 lot = 10e18;

        _setAsset(address(token), AssetType.ERC20);
        _createAndRegisterEntityWallet(_entityRegistryAdmin, address(token));

        token.mint(_company, outerAmount);
        token.mint(address(token), innerAmount);

        vm.prank(_company);
        token.approve(_escrowManager, outerAmount);

        OfferInput memory reentrantOffer = _createOfferInputForAsset(address(token), 0, innerAmount, lot);
        token.configure(_marketplace, _escrowManager, reentrantOffer);

        OfferInput memory outerOffer = _createOfferInputForAsset(address(token), 0, outerAmount, lot);
        uint256 offerId = _registerOfferAsCompany(outerOffer);

        assertEq(offerId, 1);
        assertTrue(token.attemptedReentry());
        assertTrue(token.reentrancyBlocked());
        assertFalse(token.reenteredSuccessfully());
    }

    function test_registerOffer_blocksReentrantAcceptOfferCallback() public {
        ReentrantAcceptOfferERC20 token = new ReentrantAcceptOfferERC20();
        uint256 totalAmount = 100e18;
        uint256 lot = 10e18;

        _setAsset(address(token), AssetType.ERC20);
        _createAndRegisterEntityWallet(_entityRegistryAdmin, address(token));

        token.mint(_company, totalAmount);

        vm.prank(_company);
        token.approve(_escrowManager, totalAmount);

        token.configure(_marketplace, 1, lot);

        OfferInput memory offer = _createOfferInputForAsset(address(token), 0, totalAmount, lot);
        uint256 offerId = _registerOfferAsCompany(offer);

        assertEq(offerId, 1);
        assertTrue(token.attemptedAccept());
        assertTrue(token.acceptBlocked());
        assertFalse(token.acceptSucceeded());
    }

    function test_registerOffer_blocksReentrantExpressInterestCallback() public {
        ReentrantMarketplaceCallERC20 token = new ReentrantMarketplaceCallERC20();
        uint256 totalAmount = 100e18;
        uint256 lot = 10e18;

        _setAsset(address(token), AssetType.ERC20);
        _createAndRegisterEntityWallet(_entityRegistryAdmin, address(token));

        token.mint(_company, totalAmount);

        vm.prank(_company);
        token.approve(_escrowManager, totalAmount);

        token.configure(_marketplace, _escrowManager, abi.encodeCall(Marketplace.expressInterest, (1, lot)));

        OfferInput memory offer = _createOfferInputForAsset(address(token), 0, totalAmount, lot);
        offer.allowCounterOffers = false;
        offer.saleMode = SaleMode.INTEREST_DISCOVERY;
        offer.minSaleUnits = lot;

        uint256 offerId = _registerOfferAsCompany(offer);

        assertEq(offerId, 1);
        assertTrue(token.attemptedCall());
        assertTrue(token.reentrancyBlocked());
        assertFalse(token.callSucceeded());
    }

    function test_registerOffer_blocksReentrantCreateCounterOfferCallback() public {
        ReentrantMarketplaceCallERC20 token = new ReentrantMarketplaceCallERC20();
        uint256 totalAmount = 100e18;
        uint256 lot = 10e18;
        CounterOfferInput memory counterOffer =
            CounterOfferInput({offerId: 1, amount: lot, expiry: _counterOfferExpiry(), unitPrice: UNIT_PRICE});

        _setAsset(address(token), AssetType.ERC20);
        _createAndRegisterEntityWallet(_entityRegistryAdmin, address(token));

        token.mint(_company, totalAmount);

        vm.prank(_company);
        token.approve(_escrowManager, totalAmount);

        token.configure(_marketplace, _escrowManager, abi.encodeCall(Marketplace.createCounterOffer, (counterOffer)));

        OfferInput memory offer = _createOfferInputForAsset(address(token), 0, totalAmount, lot);
        uint256 offerId = _registerOfferAsCompany(offer);

        assertEq(offerId, 1);
        assertTrue(token.attemptedCall());
        assertTrue(token.reentrancyBlocked());
        assertFalse(token.callSucceeded());
    }

    function test_registerOffer_reverts_onEscrowIdMismatch() public {
        MockInterestERC20 token = new MockInterestERC20();
        uint256 totalAmount = 100e18;
        uint256 lot = 10e18;
        uint256 expectedOfferId = 1;
        uint256 wrongEscrowId = 2;

        _setAsset(address(token), AssetType.ERC20);
        _createAndRegisterEntityWallet(_entityRegistryAdmin, address(token));

        token.mint(_company, totalAmount);

        vm.prank(_company);
        token.approve(_escrowManager, totalAmount);

        OfferInput memory offer = _createOfferInputForAsset(address(token), 0, totalAmount, lot);

        vm.mockCall(
            _escrowManager,
            abi.encodeWithSelector(IEscrowManager.createEscrow.selector, totalAmount, _company, address(token), 0),
            abi.encode(wrongEscrowId)
        );

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__EscrowIdMismatch.selector, wrongEscrowId, expectedOfferId)
        );
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOffer_reverts_disabledSellerForERC20() public {
        MockInterestERC20 token = new MockInterestERC20();
        uint256 totalAmount = 100e18;
        uint256 lot = 10e18;

        _setAsset(address(token), AssetType.ERC20);
        token.mint(_company, totalAmount);

        vm.prank(_company);
        token.approve(_escrowManager, totalAmount);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(_company, AccountStatus.DISABLED, "disabled-seller");

        OfferInput memory offer = _createOfferInputForAsset(address(token), 0, totalAmount, lot);

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, _company)
        );
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_cancelOffer_reverts_interestDiscoveryERC20ByOperatorWhenOwnerDisabled() public {
        MockInterestERC20 token = new MockInterestERC20();
        uint256 totalAmount = 100e18;
        uint256 lot = 10e18;

        _setAsset(address(token), AssetType.ERC20);
        _createAndRegisterEntityWallet(_entityRegistryAdmin, address(token));

        token.mint(_company, totalAmount);

        vm.prank(_company);
        token.approve(_escrowManager, totalAmount);

        OfferInput memory offer = _createOfferInputForAsset(address(token), 0, totalAmount, lot);
        offer.saleMode = SaleMode.INTEREST_DISCOVERY;
        offer.allowCounterOffers = false;
        offer.minSaleUnits = lot * 2;

        uint256 offerId = _registerOfferAsCompany(offer);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        Marketplace(_marketplace).expressInterest(offerId, lot);

        vm.warp(offer.expiry + 1);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(_company, AccountStatus.DISABLED, "disabled-before-operator-cancel");

        vm.prank(_adminID);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, _adminID));
        Marketplace(_marketplace).cancelOffer(offerId);

        assertEq(token.balanceOf(_company), 0);
        assertEq(token.balanceOf(_escrowManager), totalAmount);
    }

    function test_paidSettlement_success_erc20() public {
        MockInterestERC20 token = new MockInterestERC20();
        uint256 totalAmount = 1000e18;
        uint256 tradeAmount = 200e18;
        token.mint(_company, totalAmount);

        _setAsset(address(token), AssetType.ERC20);

        vm.prank(_company);
        token.approve(_escrowManager, totalAmount);

        OfferInput memory offer = _createOfferInputForAsset(address(token), 0, totalAmount, 100e18);
        uint256 offerId = _registerOfferAsCompany(offer);
        uint256 dealId = _acceptOfferAsRegisteredBuyer(offerId, tradeAmount);
        _resolvePaidAndSettle(dealId);

        assertEq(token.balanceOf(_escrowManager), totalAmount - tradeAmount);
    }

    function test_settleDeal_reverts_disabledBuyerForERC20() public {
        MockInterestERC20 token = new MockInterestERC20();
        uint256 totalAmount = 1000e18;
        uint256 tradeAmount = 200e18;
        token.mint(_company, totalAmount);

        _setAsset(address(token), AssetType.ERC20);

        vm.prank(_company);
        token.approve(_escrowManager, totalAmount);

        OfferInput memory offer = _createOfferInputForAsset(address(token), 0, totalAmount, 100e18);
        uint256 offerId = _registerOfferAsCompany(offer);
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOfferAsBuyer(offerId, tradeAmount, buyer);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(buyer, AccountStatus.DISABLED, "disabled-before-erc20-settlement");

        uint256 escrowId = _getEscrowIdByOfferId(offerId);
        uint256 escrowBefore = IEscrowManager(_escrowManager).getEscrow(escrowId).amount;
        uint256 buyerBefore = token.balanceOf(buyer);

        vm.prank(_paymentProvider);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, buyer));
        Marketplace(_marketplace).settleDeal(dealId);

        assertEq(token.balanceOf(buyer), buyerBefore);
        assertEq(IEscrowManager(_escrowManager).getEscrow(escrowId).amount, escrowBefore);
    }

    function test_paidSettlement_success_erc721() public {
        MockInterestERC721 token = new MockInterestERC721();
        uint256 tokenId = 77;
        token.mint(_company, tokenId);

        _setAsset(address(token), AssetType.ERC721);

        vm.prank(_company);
        token.approve(_escrowManager, tokenId);

        OfferInput memory offer = _createOfferInputForAsset(address(token), tokenId, 1, 1);
        uint256 offerId = _registerOfferAsCompany(offer);
        address buyer = makeAddr("erc721Buyer");
        _createAndRegisterEntityWallet(_entityRegistryAdmin, buyer);
        uint256 dealId = _acceptOfferAsBuyer(offerId, 1, buyer);
        _resolvePaidAndSettle(dealId);

        assertEq(token.ownerOf(tokenId), buyer);
    }

    function test_settleDeal_reverts_disabledBuyerForERC721() public {
        MockInterestERC721 token = new MockInterestERC721();
        uint256 tokenId = 77;
        token.mint(_company, tokenId);

        _setAsset(address(token), AssetType.ERC721);

        vm.prank(_company);
        token.approve(_escrowManager, tokenId);

        OfferInput memory offer = _createOfferInputForAsset(address(token), tokenId, 1, 1);
        uint256 offerId = _registerOfferAsCompany(offer);
        address buyer = makeAddr("disabledERC721Buyer");
        _createAndRegisterEntityWallet(_entityRegistryAdmin, buyer);
        uint256 dealId = _acceptOfferAsBuyer(offerId, 1, buyer);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(buyer, AccountStatus.DISABLED, "disabled-erc721-settle");

        uint256 escrowId = _getEscrowIdByOfferId(offerId);
        uint256 escrowBefore = IEscrowManager(_escrowManager).getEscrow(escrowId).amount;

        vm.prank(_paymentProvider);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, buyer));
        Marketplace(_marketplace).settleDeal(dealId);

        assertEq(token.ownerOf(tokenId), _escrowManager);
        assertEq(IEscrowManager(_escrowManager).getEscrow(escrowId).amount, escrowBefore);
    }

    function test_paidSettlement_success_erc1155() public {
        MockInterestERC1155 token = new MockInterestERC1155();
        uint256 tokenId = 5;
        uint256 totalAmount = 50;
        uint256 tradeAmount = 20;
        address seller = makeAddr("erc1155Seller");
        _createAndRegisterEntityWallet(_entityRegistryAdmin, seller);
        token.mint(seller, tokenId, totalAmount);

        _setAsset(address(token), AssetType.ERC1155);

        vm.prank(seller);
        token.setApprovalForAll(_escrowManager, true);

        OfferInput memory offer = _createOfferInputForAsset(address(token), tokenId, totalAmount, 10);
        uint256 offerId = _registerOfferAsWallet(offer, seller);
        address buyer = makeAddr("erc1155Buyer");
        _createAndRegisterEntityWallet(_entityRegistryAdmin, buyer);
        uint256 dealId = _acceptOfferAsBuyer(offerId, tradeAmount, buyer);
        _resolvePaidAndSettle(dealId);

        assertEq(token.balanceOf(buyer, tokenId), tradeAmount);
        assertEq(token.balanceOf(_escrowManager, tokenId), totalAmount - tradeAmount);
    }

    function test_settleDeal_reverts_disabledBuyerForERC1155() public {
        MockInterestERC1155 token = new MockInterestERC1155();
        uint256 tokenId = 5;
        uint256 totalAmount = 50;
        uint256 tradeAmount = 20;
        address seller = makeAddr("erc1155DisabledBuyerSeller");
        _createAndRegisterEntityWallet(_entityRegistryAdmin, seller);
        token.mint(seller, tokenId, totalAmount);

        _setAsset(address(token), AssetType.ERC1155);

        vm.prank(seller);
        token.setApprovalForAll(_escrowManager, true);

        OfferInput memory offer = _createOfferInputForAsset(address(token), tokenId, totalAmount, 10);
        uint256 offerId = _registerOfferAsWallet(offer, seller);
        address buyer = makeAddr("disabledERC1155Buyer");
        _createAndRegisterEntityWallet(_entityRegistryAdmin, buyer);
        uint256 dealId = _acceptOfferAsBuyer(offerId, tradeAmount, buyer);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(buyer, AccountStatus.DISABLED, "disabled-erc1155-settle");

        uint256 escrowId = _getEscrowIdByOfferId(offerId);
        uint256 escrowBefore = IEscrowManager(_escrowManager).getEscrow(escrowId).amount;
        uint256 buyerBefore = token.balanceOf(buyer, tokenId);

        vm.prank(_paymentProvider);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, buyer));
        Marketplace(_marketplace).settleDeal(dealId);

        assertEq(token.balanceOf(buyer, tokenId), buyerBefore);
        assertEq(IEscrowManager(_escrowManager).getEscrow(escrowId).amount, escrowBefore);
    }

    function test_paidSettlement_success_erc6909() public {
        uint256 totalAmount = 1000;
        uint256 tradeAmount = 200;

        _setAsset(_tokenAddr, AssetType.ERC6909);

        _approveEscrowManager(_company, _bondFTId, totalAmount);

        OfferInput memory offer = _createOfferInputForAsset(_tokenAddr, _bondFTId, totalAmount, 100);
        uint256 offerId = _registerOfferAsCompany(offer);
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOfferAsBuyer(offerId, tradeAmount, buyer);
        _resolvePaidAndSettle(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(buyer, _bondFTId), tradeAmount);
    }

    function _setAsset(address token, AssetType assetType) internal {
        vm.prank(_adminID);
        AssetManager(_assetManager).setAsset(token, assetType, true, false);
    }

    function _createOfferInputForAsset(address token, uint256 tokenId, uint256 totalAmount, uint256 lot)
        internal
        view
        returns (OfferInput memory offer)
    {
        offer = _createOfferInput();
        offer.tokenAddress = token;
        offer.tokenId = tokenId;
        offer.totalAmount = totalAmount;
        offer.lot = lot;
    }

    function _registerOfferAsCompany(OfferInput memory offer) internal returns (uint256 offerId) {
        vm.prank(_company);
        offerId = Marketplace(_marketplace).registerOffer(offer);
    }

    function _registerOfferAsWallet(OfferInput memory offer, address wallet) internal returns (uint256 offerId) {
        vm.prank(wallet);
        offerId = Marketplace(_marketplace).registerOffer(offer);
    }

    function _acceptOfferAsRegisteredBuyer(uint256 offerId, uint256 amount) internal returns (uint256 dealId) {
        address buyer = _createAndRegisterOtherCompany();
        dealId = _acceptOfferAsBuyer(offerId, amount, buyer);
    }

    function _acceptOfferAsBuyer(uint256 offerId, uint256 amount, address buyer) internal returns (uint256 dealId) {
        vm.prank(buyer);
        dealId = Marketplace(_marketplace).acceptOffer(offerId, amount);
    }

    function _resolvePaidAndSettle(uint256 dealId) internal {
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).settleDeal(dealId);
    }
}
