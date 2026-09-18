// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BondFixture} from "./BondFixture.t.sol";
// contracts
import {DEUSSToken} from "src/token/fungible/DEUSSToken.sol";
import {AssetManager} from "src/marketplace/AssetManager.sol";
import {EscrowManager} from "src/marketplace/EscrowManager.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {OrderbookMarketplace} from "src/marketplace/OrderbookMarketplace.sol";
import {BondMarketFilter} from "src/marketplace/filters/BondMarketFilter.sol";
// structs
import {Bond} from "src/registry/BondStructs.sol";
import {AssetType, CounterOfferInput, DealStatus, OfferInput, SaleMode} from "src/marketplace/MarketStructs.sol";
// other
import {ERC6909Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC6909/ERC6909Upgradeable.sol";
import {Errors} from "src/libs/Errors.sol";

contract MarketplaceFixture is BondFixture {
    struct Balances {
        uint256 company;
        uint256 escrow;
        uint256 investor;
    }

    // addresses
    address internal _adminID;
    address internal _freezer;
    address internal _arbitrator;
    address internal _paymentProvider;

    address internal _investor;
    address internal _marketplace;
    address internal _orderbookMarketplace;
    address internal _assetManager;
    address internal _bondMarketFilter;
    // constants
    uint256 public constant MIN_AMOUNT = 10;
    uint256 public constant UNIT_PRICE = 1000;

    Bond internal _bond;

    address internal _bondRegistryAdmin;
    address internal _bondRegistry;
    address internal _entityRegistryAdmin;
    address internal _entityRegistry;

    // IMPORTANT: Tests expect `_company` to be the CompanyWallet contract address
    // But parent CompanyFixture defines _company as EOA owner, and _cwAddr as CompanyWallet
    // Solution: In setUp(), we'll reassign _company = _cwAddr for backward compatibility

    function setUp() public virtual override {
        super.setUp();

        // BondFixture already sets up bond registry, company wallet, and creates bonds
        // We just need to get the references and set up marketplace-specific components

        // Get contracts from parent fixture
        _bondRegistry = _brAddr;
        _entityRegistry = _erAddr;

        // IMPORTANT: Tests expect _company to be CompanyWallet address, not EOA
        // Parent sets _company as EOA owner, _cwAddr as CompanyWallet contract
        // We reassign _company to match test expectations
        _company = _cwAddr;

        // Setup additional roles for marketplace testing
        _bondRegistryAdmin = _publisher; // Use existing registrar as bond registry admin
        _entityRegistryAdmin = _erAdmin; // Use existing ER admin
        vm.label(_bondRegistryAdmin, "BondRegistryAdmin");
        vm.label(_entityRegistryAdmin, "EntityRegistryAdmin");

        // Issue the bond — full supply in one tranche
        vm.startPrank(_company);
        _br.issueBond(_bondFT.isin, 1, BOND_MAX_SUPPLY);
        vm.stopPrank();
        ///////////////////////
        // SETUP MARKETPLACE //
        ///////////////////////
        // setup addresses
        _adminID = makeAddr("adminID");
        _freezer = makeAddr("freezer");
        _arbitrator = makeAddr("arbitrator");
        _investor = makeAddr("investor");
        _paymentProvider = makeAddr("paymentProvider");
        // get contracts
        _marketplace = _suite.core.marketplace;
        _orderbookMarketplace = _suite.core.orderbookMarketplace;
        // set labels
        vm.label(_marketplace, "Marketplace");
        vm.label(_orderbookMarketplace, "OrderbookMarketplace");
        // set roles
        uint256 marketplaceAdminRole = Marketplace(_marketplace).ADMIN();
        uint256 marketplaceFreezeRole = Marketplace(_marketplace).FREEZE_ROLE();
        uint256 marketplaceArbitratorRole = Marketplace(_marketplace).ARBITRATOR();
        uint256 marketplacePaymentHandlerRole = Marketplace(_marketplace).PAYMENT_HANDLER();
        uint256 marketplaceSeizureRole = Marketplace(_marketplace).SEIZURE_ROLE();
        uint256 marketplaceOperatorRole = Marketplace(_marketplace).INTEREST_DISCOVERY_OPERATOR();
        uint256 escrowManagerAdminRole = EscrowManager(_escrowManager).ADMIN();
        _grantRoles(_marketplace, _adminID, marketplaceAdminRole);
        _grantRoles(_marketplace, _adminID, marketplaceOperatorRole);
        _grantRoles(_marketplace, _freezer, marketplaceFreezeRole);
        _grantRoles(_marketplace, _arbitrator, marketplaceArbitratorRole);
        _grantRoles(_marketplace, _paymentProvider, marketplacePaymentHandlerRole);
        _grantRoles(_marketplace, _deployer, marketplaceSeizureRole);
        _setupOrderbookMarketplaceRoles();
        _grantRoles(_escrowManager, _adminID, escrowManagerAdminRole);

        _assetManager = _suite.core.assetManager;
        uint256 assetManagerAdminRole = AssetManager(_assetManager).ADMIN();

        _grantRoles(_assetManager, _adminID, assetManagerAdminRole);

        // set contracts
        vm.startPrank(_adminID);
        AssetManager(_assetManager).setAsset(_tokenAddr, AssetType.ERC6909, true, false);
        Marketplace(_marketplace).setAssetManager(_assetManager);
        if (Marketplace(_marketplace).getEscrowManager() == address(0)) {
            Marketplace(_marketplace).setEscrowManager(_escrowManager);
        }
        if (Marketplace(_marketplace).getEntityRegistry() == address(0)) {
            Marketplace(_marketplace).setEntityRegistry(_entityRegistry);
        }
        Marketplace(_marketplace).setAllowedEntityType(COMPANY_ENTITY, true);
        if (!Marketplace(_marketplace).isCurrencyAllowed(BOND_CURRENCY_BYTES3)) {
            Marketplace(_marketplace).addCurrency(BOND_CURRENCY_BYTES3);
        }
        if (OrderbookMarketplace(_orderbookMarketplace).escrowManager() == address(0)) {
            OrderbookMarketplace(_orderbookMarketplace).setEscrowManager(_escrowManager);
        }
        if (OrderbookMarketplace(_orderbookMarketplace).entityRegistry() == address(0)) {
            OrderbookMarketplace(_orderbookMarketplace).setEntityRegistry(_entityRegistry);
        }
        EscrowManager(_escrowManager).setAssetManager(_assetManager);
        vm.stopPrank();

        // Grant ADMIN on the bootstrap-wired BondMarketFilter so tests can exercise setAdapter.
        _bondMarketFilter = _suite.core.bondMarketFilter;
        vm.label(_bondMarketFilter, "BondMarketFilter");
        uint256 bondMarketFilterAdminRole = BondMarketFilter(_bondMarketFilter).ADMIN();
        _grantRoles(_bondMarketFilter, _adminID, bondMarketFilterAdminRole);
    }

    /*//////////////////////////////////////////////////////////////
                            SETUP FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _setupOrderbookMarketplaceRoles() internal {
        uint256 orderbookMarketplaceAdminRole = OrderbookMarketplace(_orderbookMarketplace).ADMIN();
        uint256 orderbookMarketplacePaymentHandlerRole = OrderbookMarketplace(_orderbookMarketplace).PAYMENT_HANDLER();
        uint256 orderbookMarketplaceFreezeRole = OrderbookMarketplace(_orderbookMarketplace).FREEZE_ROLE();
        uint256 orderbookMarketplaceSeizureRole = OrderbookMarketplace(_orderbookMarketplace).SEIZURE_ROLE();
        uint256 orderbookMarketplaceArbitratorRole = OrderbookMarketplace(_orderbookMarketplace).ARBITRATOR();

        _grantRoles(_orderbookMarketplace, _adminID, orderbookMarketplaceAdminRole);
        _grantRoles(_orderbookMarketplace, _paymentProvider, orderbookMarketplacePaymentHandlerRole);
        _grantRoles(_orderbookMarketplace, _arbitrator, orderbookMarketplaceArbitratorRole);
        _grantRoles(_orderbookMarketplace, _freezer, orderbookMarketplaceFreezeRole);
        _grantRoles(
            _orderbookMarketplace, _governance, orderbookMarketplaceFreezeRole | orderbookMarketplaceSeizureRole
        );
    }

    function _setupMarket(uint256 amountOfBondsToBuy, address buyer)
        internal
        returns (uint256 offerId, uint256 dealId)
    {
        _approveEscrowManagerAsOperator(_company);
        offerId = _registerOfferAsCompany();
        dealId = _acceptOffer(offerId, amountOfBondsToBuy, buyer);
    }

    /*//////////////////////////////////////////////////////////////
                                HANDLERS
    //////////////////////////////////////////////////////////////*/
    function _approveEscrowManagerAsOperator(address approver) internal {
        // approval must be set for the ESCROW MANAGER as it is going to call transferFrom on ERC6909
        vm.prank(approver);
        ERC6909Upgradeable(_tokenAddr).setOperator(_escrowManager, true);
    }

    function _approveEscrowManager(address approver, uint256 id, uint256 amount) internal {
        // approval must be set for the ESCROW MANAGER as it is going to call transferFrom on ERC6909
        vm.prank(approver);
        ERC6909Upgradeable(_tokenAddr).approve(_escrowManager, id, amount);
    }

    function _registerOfferAsCompany() internal returns (uint256 offerId) {
        // ARRANGE
        OfferInput memory offer = _createOfferInput();

        vm.prank(_company);
        offerId = Marketplace(_marketplace).registerOffer(offer);
    }

    function _registerOfferAsUser() internal returns (uint256 offerId) {
        OfferInput memory offer = _createOfferInput();
        vm.prank(_investor);
        offerId = Marketplace(_marketplace).registerOffer(offer);
    }

    function _registerInterestDiscoveryOfferAsCompany(uint256 minSaleUnits) internal returns (uint256 offerId) {
        OfferInput memory offer = _createInterestDiscoveryOfferInput(minSaleUnits);

        vm.prank(_company);
        offerId = Marketplace(_marketplace).registerOffer(offer);
    }

    function _snapshotBalances() internal view returns (Balances memory balances) {
        balances.company = DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId);
        balances.escrow = DEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId);
        balances.investor = DEUSSToken(_tokenAddr).balanceOf(_investor, _bondFTId);
    }

    function _acceptOffer(uint256 offerId, uint256 amount, address buyer) internal returns (uint256 dealId) {
        vm.prank(buyer);
        dealId = Marketplace(_marketplace).acceptOffer(offerId, amount);
    }

    function _createOfferInput() internal view returns (OfferInput memory) {
        return OfferInput({
            tokenAddress: _tokenAddr,
            tokenId: _bondFTId,
            totalAmount: BOND_MAX_SUPPLY,
            lot: MIN_AMOUNT,
            unitPrice: UNIT_PRICE,
            currency: BOND_CURRENCY_BYTES3,
            expiry: OFFER_EXPIRY,
            allowCounterOffers: true,
            allowedBuyers: new address[](0),
            saleMode: SaleMode.MARKETPLACE,
            minSaleUnits: 0
        });
    }

    function _createInterestDiscoveryOfferInput(uint256 minSaleUnits) internal view returns (OfferInput memory offer) {
        offer = _createOfferInput();
        offer.allowCounterOffers = false;
        offer.saleMode = SaleMode.INTEREST_DISCOVERY;
        offer.minSaleUnits = minSaleUnits;
    }

    function _createCounterOffer(uint256 offerId, uint256 amount, uint256 unitPrice, address buyer)
        internal
        returns (uint256 dealId)
    {
        // Must satisfy createCounterOffer lifetime window: offerExpiryThreshold <= lifetime <= maxOfferLifetime.
        // Keep explicit 1 day + 1 second margin for clarity.
        CounterOfferInput memory counterOffer =
            CounterOfferInput({offerId: offerId, amount: amount, expiry: _counterOfferExpiry(), unitPrice: unitPrice});
        vm.prank(buyer);
        return Marketplace(_marketplace).createCounterOffer(counterOffer);
    }

    function _counterOfferExpiry() internal view returns (uint256) {
        return block.timestamp + COUNTER_OFFER_EXPIRY + 1 seconds;
    }

    function _createAndRegisterOtherCompany() internal returns (address otherCompany) {
        (otherCompany,) = _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("otherCompanyOwner"));
        vm.label(otherCompany, "OtherCompany");
    }

    /*//////////////////////////////////////////////////////////////
                              TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    function _dealCannotBeMarkedAsPaid(uint256 dealId, DealStatus status) internal {
        // Test: deal can be marked as PAID only if the status is PENDING or UNPAID (pre-arbitration)
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(status)));

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);
    }

    function _dealCannotBeMarkedAsPaidDueToArbitration(uint256 dealId) internal {
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DealAlreadyArbitrated.selector));

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);
    }

    function _dealCannotBeMarkedAsNotPaidDueToInvalidStatus(uint256 dealId, DealStatus status) internal {
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(status)));

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);
    }

    function _dealCannotBeMarkedAsNotPaidIfExpired(uint256 dealId) internal {
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DealNotExpired.selector));

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);
    }

    function _dealCannotBeSettledDueToInvalidStatus(uint256 dealId, DealStatus status) internal {
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(status)));

        Marketplace(_marketplace).settleDeal(dealId);
    }

    function _dealCannotBeSettledDueToDisputePeriodNotExpired(uint256 dealId) internal {
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DisputePeriodNotExpired.selector));

        Marketplace(_marketplace).settleDeal(dealId);
    }

    function _dealCannotBeDisputedDueToInvalidStatus(uint256 dealId, DealStatus status) internal {
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(status)));

        vm.prank(_investor);
        Marketplace(_marketplace).initiateDispute(dealId);
    }

    function _dealCannotBeDisputedIfExpired(uint256 dealId) internal {
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DisputePeriodExpired.selector));

        vm.prank(_investor);
        Marketplace(_marketplace).initiateDispute(dealId);
    }

    function _dealCannotBeResolvedWhenNotInDispute(uint256 dealId, DealStatus status) internal {
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DealNotInDispute.selector));

        vm.prank(_arbitrator);
        Marketplace(_marketplace).resolveDispute(dealId, status);
    }

    function _dealCannotBeResolvedWithInvalidStatus(uint256 dealId, DealStatus status) internal {
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(status)));

        vm.prank(_arbitrator);
        Marketplace(_marketplace).resolveDispute(dealId, status);
    }
}
