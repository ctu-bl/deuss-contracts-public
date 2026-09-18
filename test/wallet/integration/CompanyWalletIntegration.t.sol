// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {BondInput} from "src/registry/BondStructs.sol";
import {CompanyWallet} from "src/wallet/CompanyWallet.sol";
import {ICompanyWallet} from "src/wallet/ICompanyWallet.sol";
import {PolicyRegistry} from "src/registry/PolicyRegistry.sol";
import {IBondRegistry} from "src/registry/interfaces/IBondRegistry.sol";
import {IEntityRegistry} from "src/registry/interfaces/IEntityRegistry.sol";
import {IERC6909} from "@openzeppelin/contracts/interfaces/IERC6909.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";
import {IMarketplace} from "src/marketplace/interfaces/IMarketplace.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {MarketplaceBase} from "src/marketplace/MarketplaceBase.sol";
import {AssetManager} from "src/marketplace/AssetManager.sol";
import {EscrowManager} from "src/marketplace/EscrowManager.sol";
import {AssetType, Offer, OfferInput, SaleMode} from "src/marketplace/MarketStructs.sol";
import {StringExtensions} from "src/libs/StringExtensions.sol";
import {BondFixture} from "test/fixtures/BondFixture.t.sol";

contract CompanyWalletIntegrationTest is BondFixture {
    using StringExtensions for string;

    uint256 private constant _ROLE_DELEGATE_OFFER = 1;
    uint256 private constant _ROLE_DELEGATE_ISSUE = 2;
    uint256 private constant _ROLE_DELEGATE_REGISTER_OFFER = 4;
    uint256 private constant _ROLE_DELEGATE_ISSUE_AND_OFFER = _ROLE_DELEGATE_ISSUE | _ROLE_DELEGATE_REGISTER_OFFER;
    uint256 private constant _DEFAULT_OFFER_LOT = 10;
    uint256 private constant _DEFAULT_OFFER_UNIT_PRICE = 1000;

    CompanyWallet public companyWallet;
    PolicyRegistry internal _policyRegistry;

    BondInput internal _newBondFt;
    uint256 private _newBondFtId;

    address internal _companyWalletAddr;
    address internal _companyOwner;
    address internal _companyDelegate;
    address internal _marketplace;
    address internal _marketplaceAdmin;
    address internal _assetManager;

    function setUp() public override {
        super.setUp();

        _companyOwner = makeAddr("companyOwner");
        _companyDelegate = makeAddr("companyDelegate");
        _marketplaceAdmin = makeAddr("marketplaceAdmin");
        _policyRegistry = PolicyRegistry(_suite.registries.walletPolicyRegistry);

        _marketplace = _suite.core.marketplace;

        _grantRoles(_marketplace, _marketplaceAdmin, MarketplaceBase(_marketplace).ADMIN());
        _grantRoles(_escrowManager, _marketplaceAdmin, EscrowManager(_escrowManager).ADMIN());
        _assetManager = _suite.core.assetManager;
        _grantRoles(_assetManager, _marketplaceAdmin, AssetManager(_assetManager).ADMIN());

        _newBondFt = _bondFT;
        _newBondFt.isin = "SK0001002060";
        _newBondFtId = uint256(keccak256(abi.encodePacked(_newBondFt.isin._isinToBytes12(), uint8(1))));

        vm.startPrank(_marketplaceAdmin);
        AssetManager(_assetManager).setAsset(_tokenAddr, AssetType.ERC6909, true, false);
        MarketplaceBase(_marketplace).setAssetManager(_assetManager);
        if (MarketplaceBase(_marketplace).getEntityRegistry() == address(0)) {
            MarketplaceBase(_marketplace).setEntityRegistry(_erAddr);
        }
        Marketplace(_marketplace).setAllowedEntityType(COMPANY_ENTITY, true);
        if (MarketplaceBase(_marketplace).getEscrowManager() == address(0)) {
            MarketplaceBase(_marketplace).setEscrowManager(_escrowManager);
        }
        if (!MarketplaceBase(_marketplace).isCurrencyAllowed(BOND_CURRENCY_BYTES3)) {
            MarketplaceBase(_marketplace).addCurrency(BOND_CURRENCY_BYTES3);
        }
        EscrowManager(_escrowManager).setAssetManager(_assetManager);
        vm.stopPrank();
    }

    function test_ownerCanIssueAndOfferWithoutPolicyLookup() public {
        _companyWalletAddr = _registerCompany();
        companyWallet = CompanyWallet(payable(_companyWalletAddr));

        _publishBond();
        _issueBond(_companyOwner);

        assertEq(IDEUSSToken(_tokenAddr).totalSupply(_newBondFtId), BOND_MAX_SUPPLY);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_companyWalletAddr, _newBondFtId), BOND_MAX_SUPPLY);

        vm.prank(_companyWalletAddr);
        IERC6909(_tokenAddr).setOperator(_escrowManager, true);

        uint256 offerId = _registerOffer(_companyOwner);
        _assertOfferState(offerId);
    }

    function test_delegateCanOfferWhenAuthorizedInPolicyRegistry() public {
        _companyWalletAddr = _registerCompany();
        companyWallet = CompanyWallet(payable(_companyWalletAddr));

        _publishBond();
        _issueBond(_companyOwner);

        vm.prank(_companyOwner);
        _policyRegistry.grantUserRoles(_companyWalletAddr, _companyDelegate, _ROLE_DELEGATE_OFFER);

        vm.prank(_companyOwner);
        _policyRegistry.grantOperationRoles(
            _companyWalletAddr, _marketplace, IMarketplace.registerOffer.selector, _ROLE_DELEGATE_OFFER
        );

        vm.prank(_companyWalletAddr);
        IERC6909(_tokenAddr).setOperator(_escrowManager, true);

        uint256 offerId = _registerOffer(_companyDelegate);
        _assertOfferState(offerId);
    }

    function test_delegateCanIssueAndOfferWhenAuthorizedInPolicyRegistry() public {
        _companyWalletAddr = _registerCompany();
        companyWallet = CompanyWallet(payable(_companyWalletAddr));

        _publishBond();

        vm.startPrank(_companyOwner);
        _policyRegistry.grantUserRoles(_companyWalletAddr, _companyDelegate, _ROLE_DELEGATE_ISSUE_AND_OFFER);
        _policyRegistry.grantOperationRoles(
            _companyWalletAddr, _brAddr, IBondRegistry.issueBond.selector, _ROLE_DELEGATE_ISSUE
        );
        _policyRegistry.grantOperationRoles(
            _companyWalletAddr, _marketplace, IMarketplace.registerOffer.selector, _ROLE_DELEGATE_REGISTER_OFFER
        );
        vm.stopPrank();

        _issueBond(_companyDelegate);

        vm.prank(_companyWalletAddr);
        IERC6909(_tokenAddr).setOperator(_escrowManager, true);

        uint256 offerId = _registerOffer(_companyDelegate);
        _assertOfferState(offerId);
    }

    function _createOfferInput() internal view returns (OfferInput memory) {
        return OfferInput({
            tokenAddress: _tokenAddr,
            tokenId: _newBondFtId,
            totalAmount: BOND_MAX_SUPPLY,
            lot: _DEFAULT_OFFER_LOT,
            unitPrice: _DEFAULT_OFFER_UNIT_PRICE,
            currency: BOND_CURRENCY_BYTES3,
            expiry: OFFER_EXPIRY,
            allowCounterOffers: true,
            allowedBuyers: new address[](0),
            saleMode: SaleMode.MARKETPLACE,
            minSaleUnits: 0
        });
    }

    function _registerCompany() internal returns (address companyWalletAddress) {
        bytes32 entityId = keccak256(abi.encodePacked(_companyOwner, "company-entity"));
        vm.prank(_erAdmin);
        _er.registerEntity(entityId, COMPANY_ENTITY, EMPTY_METADATA_REF);
        vm.prank(_erAdmin);
        _er.setEntityManager(entityId, _erAdmin, true);
        companyWalletAddress = _createCompanyWallet(entityId, _companyOwner, _erAdmin);

        vm.expectEmit(true, true, true, false);
        emit IEntityRegistry.AccountRegistered(companyWalletAddress, entityId, ROLE_FLAGS_EMPTY);
        vm.prank(_erAdmin);
        _er.registerAccount(companyWalletAddress, entityId, ROLE_FLAGS_EMPTY);
    }

    function _publishBond() internal {
        _newBondFt.issuer = _companyWalletAddr;
        vm.prank(_publisher);
        vm.expectEmit(true, true, true, false);
        emit IBondRegistry.BondPublished(
            _newBondFt.isin._isinToBytes12(),
            _companyWalletAddr,
            1,
            _newBondFtId,
            _tokenAddr,
            _newBondFt.currency._currencyToBytes3(),
            _newBondFt.bondNominalValue,
            _newBondFt.maxSupply,
            _newBondFt.maturityDate,
            _newBondFt.couponFrequency,
            _newBondFt.couponRateType,
            _newBondFt.isGuaranteed,
            _newBondFt.issuanceCountry,
            _publisher
        );
        _br.publishBond(_newBondFt);
    }

    function _issueBond(address sender) internal {
        bytes memory callData =
            abi.encodeWithSignature("issueBond(string,uint8,uint256)", _newBondFt.isin, uint8(1), BOND_MAX_SUPPLY);

        vm.expectEmit(true, true, true, true);
        emit IERC6909.Transfer(_brAddr, address(0), _companyWalletAddr, _newBondFtId, BOND_MAX_SUPPLY);
        vm.expectEmit(true, true, true, true);
        emit IBondRegistry.BondIssued(
            _newBondFt.isin._isinToBytes12(), _newBondFtId, BOND_MAX_SUPPLY, 1, 1, _companyWalletAddr
        );
        vm.expectEmit(true, true, false, false);
        emit ICompanyWallet.Execution(sender, _brAddr, 0, callData, "");
        vm.prank(sender);
        companyWallet.execute(_brAddr, 0, callData);
    }

    function _registerOffer(address sender) internal returns (uint256 offerId) {
        OfferInput memory offer = _createOfferInput();
        bytes memory callData = abi.encodeWithSelector(IMarketplace.registerOffer.selector, offer);

        offerId = 1;
        vm.expectEmit(true, true, true, false);
        emit IMarketplace.OfferRegistered(
            offerId, _companyWalletAddr, _tokenAddr, _newBondFtId, AssetType.ERC6909, SaleMode.MARKETPLACE
        );
        vm.expectEmit(true, false, false, false);
        emit IMarketplace.OfferTermsRegistered(
            offerId,
            BOND_MAX_SUPPLY,
            _DEFAULT_OFFER_LOT,
            _DEFAULT_OFFER_UNIT_PRICE,
            BOND_CURRENCY_BYTES3,
            OFFER_EXPIRY,
            true
        );
        vm.expectEmit(true, true, false, false);
        emit ICompanyWallet.Execution(sender, _marketplace, 0, callData, "");
        vm.prank(sender);
        companyWallet.execute(_marketplace, 0, callData);
    }

    function _assertOfferState(uint256 offerId) internal view {
        Offer memory offerRegistered = _getOffer(offerId);
        assertEq(offerRegistered.owner, _companyWalletAddr);
        assertEq(uint8(offerRegistered.assetType), uint8(AssetType.ERC6909));
        assertEq(offerRegistered.tokenAddress, _tokenAddr);
        assertEq(offerRegistered.tokenId, _newBondFtId);
        assertEq(offerRegistered.amounts.total, BOND_MAX_SUPPLY);
        assertEq(offerRegistered.amounts.available, BOND_MAX_SUPPLY);
        assertEq(offerRegistered.amounts.inDeals, 0);
        assertEq(offerRegistered.amounts.sold, 0);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_companyWalletAddr, _newBondFtId), 0);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _newBondFtId), BOND_MAX_SUPPLY);
    }
}
