// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {AccountStatus} from "src/registry/EntityStructs.sol";
import {EscrowManager, Escrow} from "src/marketplace/EscrowManager.sol";
import {AssetManager} from "src/marketplace/AssetManager.sol";
import {IEscrowManager} from "src/marketplace/interfaces/IEscrowManager.sol";
import {IMarketplace} from "src/marketplace/interfaces/IMarketplace.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {MarketplaceBase} from "src/marketplace/MarketplaceBase.sol";
import {MarketplaceStorage} from "src/marketplace/MarketplaceStorage.sol";
import {DEUSSToken} from "src/token/fungible/DEUSSToken.sol";
import {
    AssetType,
    CounterOfferInput,
    Deal,
    DealStatus,
    DealType,
    Interest,
    InterestDiscoveryState,
    InterestStatus,
    Offer,
    OfferInput,
    PaymentResolutionInput,
    SaleMode
} from "src/marketplace/MarketStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {ERC6909Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC6909/ERC6909Upgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {stdError} from "forge-std/StdError.sol";
// test files
import {MarketplaceFixture} from "test/fixtures/MarketplaceFixture.t.sol";

contract MarketplaceValidateSaleModeHarness is Marketplace {
    function exposedValidateSaleMode(uint8 rawSaleMode) external pure {
        _validateSaleMode(rawSaleMode);
    }

    function exposedGetPaymentExpiryThreshold(SaleMode saleMode) external view returns (uint256 threshold) {
        return _getPaymentExpiryThreshold(saleMode);
    }

    function exposedSetInterestDiscoveryPaymentExpiryThreshold(uint256 offerId, uint256 threshold) external {
        _marketplaceStorage().interestDiscoveryStateByOfferId[offerId].paymentExpiryThreshold = threshold;
    }

    function exposedGetInterestActivationDeadline(uint256 offerId, uint256 saleEnd)
        external
        view
        returns (uint256 activationDeadline)
    {
        return _getInterestActivationDeadline(offerId, saleEnd);
    }

    function exposedPrepareOfferCancellationWithRawSaleMode(uint8 rawSaleMode)
        external
        returns (uint256 withdrawAmount)
    {
        uint256 offerId = 1;
        mapping(uint256 offerId => Offer offer) storage offers = _marketplaceStorage().offers;
        Offer storage offer = offers[offerId];

        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0x00, offerId)
            mstore(0x20, offers.slot)
            let offerSlot := keccak256(0x00, 0x40)
            sstore(offerSlot, shl(32, rawSaleMode))
        }

        return _prepareOfferCancellation(offerId, offer);
    }
}

contract MarketplaceDealMutationHarness is Marketplace {
    function exposedSetDealAmount(uint256 dealId, uint256 amount) external {
        _marketplaceStorage().deals[dealId].amount = amount;
    }
}

contract MarketplaceTest is MarketplaceFixture {
    // All marketplace state lives in the ERC-7201 namespace `deuss.marketplace.storage`. Within
    // MarketplaceState the `offers` mapping is field offset 11 (Config occupies slots 0-6, assetManager 7,
    // Counters 8-10, offers 11), so the mapping's base slot is the namespace root + 11.
    uint256 internal constant _MARKETPLACE_OFFERS_SLOT =
        uint256(0xf7a56b15168bcb08515667a141d475c0860a6405d548a81fdf3dd5a1c8926a00) + 11;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();
    }

    function _config() internal view returns (MarketplaceStorage.Config memory config) {
        (config,) = Marketplace(_marketplace).getConfigAndCounters();
    }

    function _interestDiscoveryPaymentExpiryThreshold(uint256 offerId)
        internal
        view
        returns (uint256 paymentExpiryThreshold)
    {
        return _getInterestDiscoveryState(offerId).paymentExpiryThreshold;
    }

    function _interestActivationDeadline(uint256 offerId) internal view returns (uint256 activationDeadline) {
        return _getOffer(offerId).expiry + _interestDiscoveryPaymentExpiryThreshold(offerId);
    }

    function _createAndRegisterWalletForType(uint256 typeId, string memory ownerLabel)
        internal
        returns (address wallet)
    {
        wallet = makeAddr(ownerLabel);
        bytes32 entityId = keccak256(abi.encodePacked(wallet, ownerLabel));

        vm.startPrank(_entityRegistryAdmin);
        _er.registerEntity(entityId, typeId, EMPTY_METADATA_REF);
        _er.registerAccount(wallet, entityId, ROLE_FLAGS_EMPTY);
        vm.stopPrank();
    }

    function _singletonBuyerArray(address buyer) internal pure returns (address[] memory allowedBuyers) {
        allowedBuyers = new address[](1);
        allowedBuyers[0] = buyer;
    }

    function _paymentResolution(uint256 dealId, bool paid)
        internal
        pure
        returns (PaymentResolutionInput memory resolution)
    {
        resolution = PaymentResolutionInput({dealId: dealId, paid: paid});
    }

    function _warpPastPaymentDeadline(uint256 dealId) internal {
        vm.warp(_getDeal(dealId).paymentDeadline + 1);
    }

    function _overwriteOfferSaleMode(uint256 offerId, SaleMode saleMode) internal {
        // `saleMode` is the fifth packed byte in the Offer head slot.
        bytes32 offerSlot = keccak256(abi.encode(offerId, _MARKETPLACE_OFFERS_SLOT));
        uint256 saleModeOffsetBits = 8 * 4;
        bytes32 slotValue = vm.load(_marketplace, offerSlot);
        bytes32 clearedValue = slotValue & ~bytes32(uint256(0xff) << saleModeOffsetBits);
        bytes32 updatedValue = clearedValue | bytes32(uint256(uint8(saleMode)) << saleModeOffsetBits);
        vm.store(_marketplace, offerSlot, updatedValue);
    }

    function _overwriteOfferAllowCounterOffers(uint256 offerId, bool allowCounterOffers) internal {
        // `allowCounterOffers` is the fourth packed byte in the Offer head slot.
        bytes32 offerSlot = keccak256(abi.encode(offerId, _MARKETPLACE_OFFERS_SLOT));
        uint256 allowCounterOffersOffsetBits = 8 * 3;
        bytes32 slotValue = vm.load(_marketplace, offerSlot);
        bytes32 clearedValue = slotValue & ~bytes32(uint256(0xff) << allowCounterOffersOffsetBits);
        bytes32 updatedValue =
            clearedValue | bytes32(uint256(allowCounterOffers ? 1 : 0) << allowCounterOffersOffsetBits);
        vm.store(_marketplace, offerSlot, updatedValue);
    }

    /*//////////////////////////////////////////////////////////////
                        registerOffer as COMPANY
    //////////////////////////////////////////////////////////////*/
    function test_registerOfferAsCompany_success() public {
        // ARRANGE & ACT
        Balances memory balancesBefore = _snapshotBalances();
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);

        vm.expectEmit();
        emit IEscrowManager.EscrowCreated(
            1,
            EscrowManager(_escrowManager).MARKETPLACE_MODULE(),
            _company,
            _tokenAddr,
            _bondFTId,
            BOND_MAX_SUPPLY,
            AssetType.ERC6909
        );

        vm.expectEmit();
        emit IMarketplace.OfferRegistered(1, _company, _tokenAddr, _bondFTId, AssetType.ERC6909, SaleMode.MARKETPLACE);

        vm.expectEmit();
        emit IMarketplace.OfferTermsRegistered(
            1, BOND_MAX_SUPPLY, MIN_AMOUNT, UNIT_PRICE, BOND_CURRENCY_BYTES3, OFFER_EXPIRY, true
        );

        vm.expectEmit();
        emit IMarketplace.AmountsUpdated(1, BOND_MAX_SUPPLY, 0, 0);

        uint256 offerId = _registerOfferAsCompany();

        // ASSERT
        // variables in interest discovery
        Offer memory offerRegistered = _getOffer(offerId);
        assertEq(uint8(offerRegistered.assetType), uint8(AssetType.ERC6909));
        assertEq(offerRegistered.owner, _company);
        assertEq(offerRegistered.tokenAddress, _tokenAddr);
        assertEq(offerRegistered.tokenId, _bondFTId);
        assertEq(offerRegistered.lot, MIN_AMOUNT);
        assertEq(offerRegistered.unitPrice, UNIT_PRICE);
        assertEq(offerRegistered.currency, BOND_CURRENCY_BYTES3);
        assertEq(offerRegistered.expiry, OFFER_EXPIRY);
        assertEq(offerRegistered.amounts.total, BOND_MAX_SUPPLY);
        assertEq(offerRegistered.amounts.available, BOND_MAX_SUPPLY);
        assertEq(offerRegistered.amounts.inDeals, 0);
        assertEq(offerRegistered.amounts.sold, 0);
        // variables in escrow manager
        uint256 escrowId = _getEscrowIdByOfferId(offerId);
        Escrow memory escrow = EscrowManager(_escrowManager).getEscrow(escrowId);
        assertEq(escrow.depositor, _company);
        assertEq(escrow.tokenAddress, _tokenAddr);
        assertEq(escrow.tokenId, _bondFTId);
        assertEq(escrow.amount, BOND_MAX_SUPPLY);
        // variables in fungible token
        Balances memory balancesAfter = _snapshotBalances();
        assertEq(balancesAfter.company, balancesBefore.company - balancesAfter.escrow);
        assertEq(balancesAfter.escrow, balancesBefore.escrow + (BOND_MAX_SUPPLY));
    }

    function test_registerOfferAsCompany_reverts_escrowIdMismatch() public {
        OfferInput memory offer = _createOfferInput();
        uint256 expectedEscrowId = 77;
        uint256 actualEscrowId = expectedEscrowId + 1;

        vm.mockCall(
            _escrowManager,
            abi.encodeWithSelector(IEscrowManager.previewNextEscrowId.selector),
            abi.encode(expectedEscrowId)
        );
        vm.mockCall(
            _escrowManager,
            abi.encodeWithSelector(
                IEscrowManager.createEscrow.selector, offer.totalAmount, _company, offer.tokenAddress, offer.tokenId
            ),
            abi.encode(actualEscrowId)
        );

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__EscrowIdMismatch.selector, actualEscrowId, expectedEscrowId)
        );
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_assetManagerNotSet() public {
        OfferInput memory offer = _createOfferInput();
        MarketplaceStorage.Config memory config = _config();
        Marketplace marketplaceImpl = new Marketplace();
        UpgradeableBeacon marketplaceBeacon = new UpgradeableBeacon(address(marketplaceImpl), _deployer);
        address marketplaceNoAssetManager = address(
            new BeaconProxy(
                address(marketplaceBeacon),
                abi.encodeWithSelector(
                    Marketplace.initialize.selector,
                    _deployer,
                    config.offerExpiryThreshold,
                    config.maxOfferLifetime,
                    config.marketplacePaymentExpiryThreshold,
                    config.redemptionPaymentExpiryThreshold,
                    config.interestDiscoveryPaymentExpiryThreshold,
                    config.disputeBufferPeriod,
                    address(0),
                    _escrowManager,
                    _entityRegistry,
                    config.maxCounterOffersPerUser
                )
            )
        );

        vm.startPrank(_deployer);
        uint256 adminRole = Marketplace(marketplaceNoAssetManager).ADMIN();
        Marketplace(marketplaceNoAssetManager).grantRoles(_deployer, adminRole);
        Marketplace(marketplaceNoAssetManager).setAllowedEntityType(COMPANY_ENTITY, true);
        Marketplace(marketplaceNoAssetManager).addCurrency(BOND_CURRENCY_BYTES3);
        vm.stopPrank();

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__AssetManagerNotSet.selector));
        Marketplace(marketplaceNoAssetManager).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_unsupportedAsset() public {
        OfferInput memory offer = _createOfferInput();
        offer.tokenAddress = makeAddr("unsupportedToken");

        vm.expectRevert(
            abi.encodeWithSelector(Errors.AssetManager__AssetNotSupported.selector, offer.tokenAddress, offer.tokenId)
        );

        vm.prank(_company);
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_invalidTokenIdForConfiguredERC20() public {
        OfferInput memory offer = _createOfferInput();

        vm.startPrank(_adminID);
        AssetManager(_assetManager).setAsset(_tokenAddr, AssetType.ERC20, true, false);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Errors.AssetManager__InvalidTokenId.selector, offer.tokenId));

        vm.prank(_company);
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_zeroPrice() public {
        OfferInput memory offer = _createOfferInput();
        offer.unitPrice = 0;

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__ZeroPrice.selector));
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_invalidCurrency() public {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes3 invalidCurrency = bytes3("SKK");
        OfferInput memory offer = _createOfferInput();
        offer.currency = invalidCurrency;

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InvalidCurrency.selector, invalidCurrency));
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_invalidExpiry() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        OfferInput memory offer = _createOfferInput();

        vm.warp(offer.expiry + 1);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__InvalidExpiry.selector, offer.expiry, block.timestamp)
        );

        vm.prank(_company);
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_expiryEqualsBlockTimestamp() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        OfferInput memory offer = _createOfferInput();

        // Set expiry to current block.timestamp — should be rejected
        offer.expiry = block.timestamp;

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__InvalidExpiry.selector, offer.expiry, block.timestamp)
        );

        vm.prank(_company);
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_expiryBelowOfferExpiryThreshold() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        OfferInput memory offer = _createOfferInput();

        uint256 offerExpiryThreshold = _config().offerExpiryThreshold;
        // Set expiry to just under the minimum lifetime
        offer.expiry = block.timestamp + offerExpiryThreshold - 1;

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__InvalidExpiry.selector, offer.expiry, block.timestamp)
        );

        vm.prank(_company);
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_success_expiryAtExactOfferExpiryThreshold() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        OfferInput memory offer = _createOfferInput();

        uint256 offerExpiryThreshold = _config().offerExpiryThreshold;
        // Set expiry to exactly the minimum lifetime boundary — should succeed
        offer.expiry = block.timestamp + offerExpiryThreshold;

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        Offer memory offerRegistered = _getOffer(offerId);
        assertEq(offerRegistered.expiry, offer.expiry);
    }

    function test_registerOfferAsCompany_success_expiryAtMaxOfferLifetime() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        OfferInput memory offer = _createOfferInput();

        uint256 maxOfferLifetime = _config().maxOfferLifetime;
        offer.expiry = block.timestamp + maxOfferLifetime;

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        Offer memory offerRegistered = _getOffer(offerId);
        assertEq(offerRegistered.expiry, offer.expiry);
    }

    function test_registerOfferAsCompany_reverts_expiryAboveMaxOfferLifetime() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        OfferInput memory offer = _createOfferInput();

        uint256 maxOfferLifetime = _config().maxOfferLifetime;
        offer.expiry = block.timestamp + maxOfferLifetime + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__ExpiryTooFar.selector, offer.expiry, block.timestamp, maxOfferLifetime
            )
        );
        vm.prank(_company);
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_expiryUintMax() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        OfferInput memory offer = _createOfferInput();

        uint256 maxOfferLifetime = _config().maxOfferLifetime;
        offer.expiry = type(uint256).max;

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__ExpiryTooFar.selector, offer.expiry, block.timestamp, maxOfferLifetime
            )
        );
        vm.prank(_company);
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerInterestDiscoveryOffer_reverts_expiryUintMaxBeforeEscrow() public {
        OfferInput memory offer = _createInterestDiscoveryOfferInput(MIN_AMOUNT);
        uint256 maxOfferLifetime = _config().maxOfferLifetime;
        offer.expiry = type(uint256).max;
        uint256 escrowBefore = DEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__ExpiryTooFar.selector, offer.expiry, block.timestamp, maxOfferLifetime
            )
        );
        vm.prank(_company);
        Marketplace(_marketplace).registerOffer(offer);

        assertEq(DEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), escrowBefore);
    }

    function test_registerOfferAsCompany_reverts_zeroTotalAmount() public {
        OfferInput memory offer = _createOfferInput();
        offer.totalAmount = 0;

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__ZeroAmount.selector));
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_zeroLotSize() public {
        OfferInput memory offer = _createOfferInput();
        offer.lot = 0;

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__ZeroAmount.selector));
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_lotSizeTooLarge() public {
        OfferInput memory offer = _createOfferInput();
        offer.lot = offer.totalAmount + 1;

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__LotSizeTooLarge.selector));
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_totalNotMultipleOfLot() public {
        OfferInput memory offer = _createOfferInput();
        offer.totalAmount = 1000;
        offer.lot = 300; // 1000 is not a multiple of 300

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__TotalAmountNotMultipleOfLot.selector));
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_totalAmountTooLarge() public {
        OfferInput memory offer = _createOfferInput();
        offer.totalAmount = (BOND_MAX_SUPPLY) * 2;

        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY * 2);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Token__InsufficientBalance.selector));
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_lowAllowance() public {
        OfferInput memory offer = _createOfferInput();
        offer.totalAmount = (BOND_MAX_SUPPLY);

        _approveEscrowManager(_company, _bondFTId, (BOND_MAX_SUPPLY) / 2);
        // _mockCompanyRegistry(_company, true);

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909Upgradeable.ERC6909InsufficientAllowance.selector,
                _escrowManager,
                (BOND_MAX_SUPPLY) / 2,
                offer.totalAmount,
                _bondFTId
            )
        );
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_notAuthorized() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        OfferInput memory offer = _createOfferInput();

        address notAuthorized = makeAddr("notAuthorized");

        vm.prank(notAuthorized);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, notAuthorized)
        );
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_entityTypeNotAllowed() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        OfferInput memory offer = _createOfferInput();

        vm.prank(_adminID);
        Marketplace(_marketplace).setAllowedEntityType(COMPANY_ENTITY, false);

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityTypeNotAllowed.selector, COMPANY_ENTITY)
        );
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_invalidSaleMode() public {
        uint8 invalidSaleMode = uint8(type(SaleMode).max) + 1;
        MarketplaceValidateSaleModeHarness harness = new MarketplaceValidateSaleModeHarness();

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InvalidSaleMode.selector, invalidSaleMode));
        harness.exposedValidateSaleMode(invalidSaleMode);
    }

    function test_getPaymentExpiryThreshold_reverts_invalidSaleMode() public {
        MarketplaceValidateSaleModeHarness harness = new MarketplaceValidateSaleModeHarness();

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__InvalidSaleMode.selector, uint8(SaleMode.INTEREST_DISCOVERY))
        );
        harness.exposedGetPaymentExpiryThreshold(SaleMode.INTEREST_DISCOVERY);
    }

    function test_getInterestActivationDeadline_reverts_overflow() public {
        MarketplaceValidateSaleModeHarness harness = new MarketplaceValidateSaleModeHarness();
        uint256 offerId = 1;
        uint256 paymentExpiryThreshold = 1;
        uint256 saleEnd = type(uint256).max;

        harness.exposedSetInterestDiscoveryPaymentExpiryThreshold(offerId, paymentExpiryThreshold);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__InterestActivationDeadlineOverflow.selector,
                offerId,
                saleEnd,
                paymentExpiryThreshold
            )
        );
        harness.exposedGetInterestActivationDeadline(offerId, saleEnd);
    }

    function test_prepareOfferCancellation_reverts_invalidRawSaleModeEnumPanic() public {
        uint8 invalidSaleMode = uint8(type(SaleMode).max) + 1;
        MarketplaceValidateSaleModeHarness harness = new MarketplaceValidateSaleModeHarness();

        vm.expectRevert(stdError.enumConversionError);
        harness.exposedPrepareOfferCancellationWithRawSaleMode(invalidSaleMode);
    }

    function test_registerOffer_success_interestDiscoveryInitializesThresholdState() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);

        uint256 minSaleUnits = MIN_AMOUNT * 3;
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(minSaleUnits);

        Offer memory offer = _getOffer(offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);

        assertEq(uint8(offer.saleMode), uint8(SaleMode.INTEREST_DISCOVERY));
        assertFalse(offer.allowCounterOffers);
        assertEq(state.minSaleUnits, minSaleUnits);
        assertEq(state.interestedUnits, 0);
        assertEq(state.reservedInterestUnits, 0);
        assertEq(state.paymentExpiryThreshold, _config().interestDiscoveryPaymentExpiryThreshold);
    }

    function test_registerOffer_reverts_interestDiscoveryCounterOffersEnabled() public {
        OfferInput memory offer = _createInterestDiscoveryOfferInput(MIN_AMOUNT);
        offer.allowCounterOffers = true;

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__CounterOffersMustBeDisabled.selector));
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOffer_reverts_interestDiscoveryInvalidMinSaleUnits() public {
        OfferInput memory offer = _createInterestDiscoveryOfferInput(MIN_AMOUNT - 1);

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__InvalidMinSaleUnits.selector, MIN_AMOUNT - 1, offer.totalAmount, offer.lot
            )
        );
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOffer_reverts_interestDiscoveryZeroMinSaleUnits() public {
        OfferInput memory offer = _createInterestDiscoveryOfferInput(0);

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__InvalidMinSaleUnits.selector, 0, offer.totalAmount, offer.lot)
        );
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOffer_reverts_interestDiscoveryMinSaleUnitsAboveTotalAmount() public {
        OfferInput memory offer =
            _createInterestDiscoveryOfferInput((BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE) + MIN_AMOUNT);

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__InvalidMinSaleUnits.selector, offer.minSaleUnits, offer.totalAmount, offer.lot
            )
        );
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOfferAsCompany_reverts_marketplaceMinSaleUnitsNotAllowed() public {
        OfferInput memory offer = _createOfferInput();
        offer.minSaleUnits = MIN_AMOUNT;

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__MinSaleUnitsNotAllowed.selector, offer.minSaleUnits));
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOffer_success_marketplaceStoresAllowedBuyers() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address otherCompany = _createAndRegisterOtherCompany();
        address anotherBuyer = _createAndRegisterWalletForType(COMPANY_ENTITY, "anotherBuyer");

        OfferInput memory offer = _createOfferInput();
        offer.allowedBuyers = new address[](2);
        offer.allowedBuyers[0] = otherCompany;
        offer.allowedBuyers[1] = anotherBuyer;

        uint256 offerId;
        vm.prank(_company);
        offerId = Marketplace(_marketplace).registerOffer(offer);

        address[] memory allowedBuyers = _getAllowedBuyers(offerId);
        assertEq(allowedBuyers.length, 2);
        assertEq(allowedBuyers[0], otherCompany);
        assertEq(allowedBuyers[1], anotherBuyer);
    }

    function test_registerOffer_reverts_interestDiscoveryAllowedBuyersNotAllowed() public {
        OfferInput memory offer = _createInterestDiscoveryOfferInput(MIN_AMOUNT);
        offer.allowedBuyers = _singletonBuyerArray(_createAndRegisterOtherCompany());

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__AllowedBuyersNotAllowed.selector));
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOffer_reverts_redemptionAllowedBuyersRequired() public {
        OfferInput memory offer = _createOfferInput();
        offer.saleMode = SaleMode.REDEMPTION;
        offer.allowCounterOffers = false;
        offer.allowedBuyers = new address[](0);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__AllowedBuyersRequired.selector));
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOffer_reverts_redemptionCounterOffersEnabled() public {
        address allowedBuyer = _createAndRegisterOtherCompany();

        OfferInput memory offer = _createOfferInput();
        offer.saleMode = SaleMode.REDEMPTION;
        offer.allowCounterOffers = false;
        offer.allowedBuyers = _singletonBuyerArray(allowedBuyer);
        offer.allowCounterOffers = true;

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__CounterOffersMustBeDisabled.selector));
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOffer_reverts_duplicateAllowedBuyer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address otherCompany = _createAndRegisterOtherCompany();

        OfferInput memory offer = _createOfferInput();
        offer.allowedBuyers = new address[](2);
        offer.allowedBuyers[0] = otherCompany;
        offer.allowedBuyers[1] = otherCompany;

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DuplicateAllowedBuyer.selector, otherCompany));
        Marketplace(_marketplace).registerOffer(offer);
    }

    function test_registerOffer_reverts_zeroAllowedBuyer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);

        OfferInput memory offer = _createOfferInput();
        offer.saleMode = SaleMode.REDEMPTION;
        offer.allowCounterOffers = false;
        offer.allowedBuyers = new address[](1);
        offer.allowedBuyers[0] = address(0);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        Marketplace(_marketplace).registerOffer(offer);
    }

    /*//////////////////////////////////////////////////////////////
                              acceptOffer
    //////////////////////////////////////////////////////////////*/

    function test_acceptOffer_success_byOtherCompany() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        Balances memory balancesBefore = _snapshotBalances();
        MarketplaceStorage.Config memory config = _config();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 expectedDealId = 1;
        // ACT
        vm.expectEmit();
        emit IMarketplace.DealCreated(offerId, expectedDealId, otherCompany, DealType.OFFER, 1000, 1000 * UNIT_PRICE);
        vm.expectEmit();
        emit IMarketplace.DealTermsRegistered(
            expectedDealId,
            config.marketplacePaymentExpiryThreshold + block.timestamp,
            0,
            config.marketplacePaymentExpiryThreshold + block.timestamp + config.disputeBufferPeriod
        );
        vm.expectEmit();
        emit IMarketplace.AmountsUpdated(offerId, 9000, 1000, 0);
        vm.prank(otherCompany);
        uint256 dealId = Marketplace(_marketplace).acceptOffer(offerId, 1000);
        // ASSERT
        // variables in interest discovery
        Offer memory offerRegistered = _getOffer(offerId);
        assertEq(offerRegistered.amounts.total, BOND_MAX_SUPPLY);
        assertEq(offerRegistered.amounts.available, 9000);
        assertEq(offerRegistered.amounts.inDeals, 1000);
        assertEq(offerRegistered.amounts.sold, 0);
        Deal memory deal = _getDeal(dealId);
        assertEq(deal.offerId, offerId);
        assertEq(deal.amount, 1000);
        assertEq(deal.buyer, otherCompany);
        assertEq(deal.price, UNIT_PRICE * 1000);
        assertEq(deal.paymentDeadline, config.marketplacePaymentExpiryThreshold + block.timestamp);
        assertEq(
            deal.disputeBuffer, config.marketplacePaymentExpiryThreshold + config.disputeBufferPeriod + block.timestamp
        );
        assertEq(uint8(deal.status), uint8(DealStatus.PENDING));
        // amounts in escrow manager have NOT changed
        Escrow memory escrow = EscrowManager(_escrowManager).getEscrow(_getEscrowIdByOfferId(offerId));
        assertEq(escrow.amount, BOND_MAX_SUPPLY);
        // amounts in fungible token have NOT changed
        Balances memory balancesAfter = _snapshotBalances();
        assertEq(balancesAfter.company, balancesBefore.company);
        assertEq(balancesAfter.escrow, balancesBefore.escrow);
    }

    function test_acceptOffer_reverts_expiredOffer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        // get offer expiry
        uint256 offerExpiry = _getOffer(offerId).expiry;

        // Warp time past offer expiry
        vm.warp(offerExpiry + 1);

        address otherCompany = _createAndRegisterOtherCompany();
        vm.prank(otherCompany);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferExpired.selector, offerExpiry, block.timestamp));
        Marketplace(_marketplace).acceptOffer(offerId, 1000);
    }

    function test_acceptOffer_success_marketplaceAllowedBuyer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();

        OfferInput memory offer = _createOfferInput();
        offer.allowedBuyers = _singletonBuyerArray(allowedBuyer);

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        vm.prank(allowedBuyer);
        uint256 dealId = Marketplace(_marketplace).acceptOffer(offerId, MIN_AMOUNT);

        Deal memory deal = _getDeal(dealId);
        assertEq(deal.buyer, allowedBuyer);
        assertEq(deal.offerId, offerId);
    }

    function test_acceptOffer_reverts_marketplaceBuyerNotAllowed() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();
        address blockedBuyer = _createAndRegisterWalletForType(COMPANY_ENTITY, "blockedBuyer");

        OfferInput memory offer = _createOfferInput();
        offer.allowedBuyers = _singletonBuyerArray(allowedBuyer);

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        vm.prank(blockedBuyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__BuyerNotAllowed.selector, offerId, blockedBuyer));
        Marketplace(_marketplace).acceptOffer(offerId, MIN_AMOUNT);
    }

    function test_acceptOffer_success_redemptionAllowedBuyer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();

        OfferInput memory offer = _createOfferInput();
        offer.saleMode = SaleMode.REDEMPTION;
        offer.allowCounterOffers = false;
        offer.allowedBuyers = _singletonBuyerArray(allowedBuyer);

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        vm.prank(allowedBuyer);
        uint256 dealId = Marketplace(_marketplace).acceptOffer(offerId, MIN_AMOUNT);

        Offer memory registeredOffer = _getOffer(offerId);
        Deal memory deal = _getDeal(dealId);
        assertEq(uint8(registeredOffer.saleMode), uint8(SaleMode.REDEMPTION));
        assertEq(deal.buyer, allowedBuyer);
    }

    function test_acceptOffer_success_redemptionUsesRedemptionPaymentDeadline() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();
        uint256 redemptionPaymentExpiryThreshold = 4 days;

        vm.prank(_adminID);
        MarketplaceBase(_marketplace).setRedemptionPaymentExpiryThreshold(redemptionPaymentExpiryThreshold);

        OfferInput memory offer = _createOfferInput();
        offer.saleMode = SaleMode.REDEMPTION;
        offer.allowCounterOffers = false;
        offer.allowedBuyers = _singletonBuyerArray(allowedBuyer);

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        vm.prank(allowedBuyer);
        uint256 dealId = Marketplace(_marketplace).acceptOffer(offerId, MIN_AMOUNT);

        Deal memory deal = _getDeal(dealId);
        assertEq(deal.paymentDeadline, block.timestamp + redemptionPaymentExpiryThreshold);
        assertEq(deal.disputeBuffer, block.timestamp + redemptionPaymentExpiryThreshold + _config().disputeBufferPeriod);
    }

    function test_acceptOffer_reverts_redemptionBuyerNotAllowed() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();
        address blockedBuyer = _createAndRegisterWalletForType(COMPANY_ENTITY, "redemptionBlockedBuyer");

        OfferInput memory offer = _createOfferInput();
        offer.saleMode = SaleMode.REDEMPTION;
        offer.allowCounterOffers = false;
        offer.allowedBuyers = _singletonBuyerArray(allowedBuyer);

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        vm.prank(blockedBuyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__BuyerNotAllowed.selector, offerId, blockedBuyer));
        Marketplace(_marketplace).acceptOffer(offerId, MIN_AMOUNT);
    }

    function test_acceptOffer_reverts_interestDiscoveryOffer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address otherCompany = _createAndRegisterOtherCompany();

        vm.prank(otherCompany);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotMarketplaceOffer.selector, offerId));
        Marketplace(_marketplace).acceptOffer(offerId, MIN_AMOUNT);
    }

    function test_acceptOffer_reverts_invalidAmount() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        // Try to accept amount not multiple of lot size
        uint256 amount = BOND_MAX_SUPPLY - 1;
        address otherCompany = _createAndRegisterOtherCompany();
        vm.prank(otherCompany);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__AmountNotMultipleOfLot.selector, MIN_AMOUNT, amount));
        Marketplace(_marketplace).acceptOffer(offerId, amount);
    }

    function test_acceptOffer_reverts_zeroAmount() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();

        vm.prank(otherCompany);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__ZeroAmount.selector));
        Marketplace(_marketplace).acceptOffer(offerId, 0);
    }

    function test_acceptOffer_reverts_insufficientAmount() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        // Try to accept more than available
        uint256 available = _getOffer(offerId).amounts.available;
        address otherCompany = _createAndRegisterOtherCompany();
        vm.prank(otherCompany);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__InsufficientAvailableAmount.selector, available + 1, available)
        );
        Marketplace(_marketplace).acceptOffer(offerId, available + 1);
    }

    function test_acceptOffer_reverts_senderIsOwner() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        // Company tries to accept their own offer
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__SenderIsOwner.selector));
        vm.prank(_company);
        Marketplace(_marketplace).acceptOffer(offerId, MIN_AMOUNT);
    }

    function test_acceptOffer_reverts_buyerTypeNotAllowed() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address naturalPersonWallet = _createAndRegisterWalletForType(NATURAL_PERSON_ENTITY, "naturalPersonBuyer");

        vm.prank(_adminID);
        Marketplace(_marketplace).setAllowedEntityType(NATURAL_PERSON_ENTITY, false);

        vm.prank(naturalPersonWallet);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityTypeNotAllowed.selector, NATURAL_PERSON_ENTITY)
        );
        Marketplace(_marketplace).acceptOffer(offerId, MIN_AMOUNT);
    }

    function test_acceptOffer_reverts_sellerWalletDisabled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(_company, AccountStatus.DISABLED, "");

        vm.prank(otherCompany);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, _company)
        );
        Marketplace(_marketplace).acceptOffer(offerId, MIN_AMOUNT);
    }

    function test_acceptOffer_reverts_buyerWalletDisabled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(otherCompany, AccountStatus.DISABLED, "");

        vm.prank(otherCompany);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, otherCompany)
        );
        Marketplace(_marketplace).acceptOffer(offerId, MIN_AMOUNT);
    }

    function test_acceptOffer_reverts_offerCancelled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();

        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);

        vm.prank(otherCompany);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferAlreadyCancelled.selector, offerId));
        Marketplace(_marketplace).acceptOffer(offerId, MIN_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            expressInterest
    //////////////////////////////////////////////////////////////*/

    function test_expressInterest_success_reachesThresholdAndReservesInventory() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 2);
        address investorOne = _createAndRegisterOtherCompany();
        (address investorTwo,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("thresholdInvestorTwo"));

        vm.prank(investorOne);
        uint256 firstInterestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.prank(investorTwo);
        uint256 secondInterestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        Offer memory offer = _getOffer(offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        Interest memory firstInterest = _getInterest(firstInterestId);
        Interest memory secondInterest = _getInterest(secondInterestId);
        uint256[] memory interestIds = _getInterestIdsByOfferId(offerId);

        assertEq(offer.amounts.available, (BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE) - (MIN_AMOUNT * 2));
        assertEq(offer.amounts.inDeals, 0);
        assertEq(state.interestedUnits, MIN_AMOUNT * 2);
        assertEq(state.reservedInterestUnits, MIN_AMOUNT * 2);
        assertEq(uint8(firstInterest.status), uint8(InterestStatus.EXPRESSED));
        assertEq(uint8(secondInterest.status), uint8(InterestStatus.EXPRESSED));
        assertEq(firstInterest.price, MIN_AMOUNT * UNIT_PRICE);
        assertEq(secondInterest.price, MIN_AMOUNT * UNIT_PRICE);
        assertEq(interestIds.length, 2);
        assertEq(interestIds[0], firstInterestId);
        assertEq(interestIds[1], secondInterestId);
    }

    function test_expressInterest_reverts_marketplaceOffer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerOfferAsCompany();
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotInterestDiscoveryOffer.selector, offerId));
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);
    }

    function test_expressInterest_reverts_redemptionOffer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();
        address investor = _createAndRegisterWalletForType(COMPANY_ENTITY, "redemptionInterestInvestor");

        OfferInput memory offer = _createOfferInput();
        offer.saleMode = SaleMode.REDEMPTION;
        offer.allowCounterOffers = false;
        offer.allowedBuyers = _singletonBuyerArray(allowedBuyer);

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        vm.prank(investor);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotInterestDiscoveryOffer.selector, offerId));
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);
    }

    function test_expressInterest_reverts_expiredOffer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.warp(OFFER_EXPIRY + 1);

        vm.prank(investor);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__OfferExpired.selector, OFFER_EXPIRY, block.timestamp)
        );
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);
    }

    function test_expressInterest_reverts_zeroAmount() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__ZeroAmount.selector));
        Marketplace(_marketplace).expressInterest(offerId, 0);
    }

    function test_expressInterest_reverts_amountNotMultipleOfLot() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();
        uint256 amount = MIN_AMOUNT - 1;

        vm.prank(investor);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__AmountNotMultipleOfLot.selector, MIN_AMOUNT, amount));
        Marketplace(_marketplace).expressInterest(offerId, amount);
    }

    function test_expressInterest_reverts_insufficientAmount() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();
        uint256 available = _getOffer(offerId).amounts.available;

        vm.prank(investor);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__InsufficientAvailableAmount.selector, available + MIN_AMOUNT, available
            )
        );
        Marketplace(_marketplace).expressInterest(offerId, available + MIN_AMOUNT);
    }

    function test_expressInterest_reverts_senderIsOwner() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__SenderIsOwner.selector));
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);
    }

    function test_expressInterest_reverts_investorTypeNotAllowed() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address naturalPersonWallet = _createAndRegisterWalletForType(NATURAL_PERSON_ENTITY, "naturalPersonInterest");

        vm.prank(_adminID);
        Marketplace(_marketplace).setAllowedEntityType(NATURAL_PERSON_ENTITY, false);

        vm.prank(naturalPersonWallet);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityTypeNotAllowed.selector, NATURAL_PERSON_ENTITY)
        );
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);
    }

    function test_expressInterest_reverts_sellerWalletDisabled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(_company, AccountStatus.DISABLED, "");

        vm.prank(investor);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, _company)
        );
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                             activateInterest
    //////////////////////////////////////////////////////////////*/

    function test_activateInterest_success_createsDealWithDedicatedPaymentExpiry() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        MarketplaceStorage.Config memory config = _config();
        uint256 paymentExpiry = _interestDiscoveryPaymentExpiryThreshold(offerId);
        uint256 disputeBuffer = config.disputeBufferPeriod;

        vm.prank(makeAddr("permissionlessActivator"));
        uint256 dealId = Marketplace(_marketplace).activateInterest(interestId);

        Deal memory deal = _getDeal(dealId);
        Interest memory interest = _getInterest(interestId);
        Offer memory offer = _getOffer(offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);

        assertEq(deal.offerId, offerId);
        assertEq(deal.amount, MIN_AMOUNT);
        assertEq(deal.buyer, investor);
        assertEq(deal.price, MIN_AMOUNT * UNIT_PRICE);
        uint256 expectedPaymentDeadline = offer.expiry + paymentExpiry;
        assertEq(deal.paymentDeadline, expectedPaymentDeadline);
        assertEq(deal.disputeBuffer, expectedPaymentDeadline + disputeBuffer);
        assertEq(uint8(deal.status), uint8(DealStatus.PENDING));
        assertEq(uint8(interest.status), uint8(InterestStatus.ACTIVATED));
        assertEq(offer.amounts.available, (BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE) - MIN_AMOUNT);
        assertEq(offer.amounts.inDeals, MIN_AMOUNT);
        assertEq(state.reservedInterestUnits, 0);
    }

    function test_activateInterest_success_afterSaleEndWithinActivationWindow() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.warp(OFFER_EXPIRY + 1);
        uint256 activatedAt = block.timestamp;
        uint256 paymentExpiry = _interestDiscoveryPaymentExpiryThreshold(offerId);

        vm.prank(makeAddr("postExpiryActivator"));
        uint256 dealId = Marketplace(_marketplace).activateInterest(interestId);

        Deal memory deal = _getDeal(dealId);
        assertEq(deal.offerId, offerId);
        assertEq(deal.buyer, investor);
        assertEq(deal.amount, MIN_AMOUNT);
        assertEq(deal.paymentDeadline, activatedAt + paymentExpiry);
        assertEq(uint8(deal.status), uint8(DealStatus.PENDING));
    }

    function test_activateInterest_success_atActivationDeadlineBoundaryGivesFreshPaymentWindow() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        uint256 activationDeadline = _interestActivationDeadline(offerId);
        uint256 paymentExpiry = _interestDiscoveryPaymentExpiryThreshold(offerId);
        vm.warp(activationDeadline);

        uint256 dealId = Marketplace(_marketplace).activateInterest(interestId);

        Deal memory deal = _getDeal(dealId);
        assertEq(deal.paymentDeadline, activationDeadline + paymentExpiry);
        assertGt(deal.paymentDeadline, block.timestamp);

        vm.warp(block.timestamp + 1);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);
        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.PAID));
    }

    function test_activateInterest_success_usesOfferPaymentExpirySnapshotAfterConfigReduction() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();
        uint256 snapshottedPaymentExpiry = _getInterestDiscoveryState(offerId).paymentExpiryThreshold;
        uint256 reducedPaymentExpiry = MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD();
        assertLt(reducedPaymentExpiry, snapshottedPaymentExpiry);

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.prank(_adminID);
        Marketplace(_marketplace).setInterestDiscoveryPaymentExpiryThreshold(reducedPaymentExpiry);

        vm.warp(OFFER_EXPIRY + reducedPaymentExpiry + 1);
        uint256 activatedAt = block.timestamp;

        uint256 dealId = Marketplace(_marketplace).activateInterest(interestId);

        Deal memory deal = _getDeal(dealId);
        uint256 expectedPaymentDeadline = activatedAt + snapshottedPaymentExpiry;
        assertEq(deal.paymentDeadline, expectedPaymentDeadline);
        assertEq(deal.disputeBuffer, expectedPaymentDeadline + _config().disputeBufferPeriod);
    }

    function test_activateInterest_reverts_interestNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InterestNotFound.selector, 999));
        Marketplace(_marketplace).activateInterest(999);
    }

    function test_activateInterest_reverts_thresholdNotReached() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 2);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__ThresholdNotReached.selector, offerId, MIN_AMOUNT, MIN_AMOUNT * 2
            )
        );
        Marketplace(_marketplace).activateInterest(interestId);
    }

    function test_activateInterest_reverts_invalidInterestStatusAfterActivation() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        Marketplace(_marketplace).activateInterest(interestId);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__InvalidInterestStatus.selector, interestId, uint8(InterestStatus.ACTIVATED)
            )
        );
        Marketplace(_marketplace).activateInterest(interestId);
    }

    function test_activateInterest_reverts_afterActivationWindowExpired() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        uint256 activationDeadline = _interestActivationDeadline(offerId);
        vm.warp(activationDeadline + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__InterestActivationWindowExpired.selector,
                offerId,
                activationDeadline,
                block.timestamp
            )
        );
        Marketplace(_marketplace).activateInterest(interestId);
    }

    function test_activateInterest_success_afterInvestorTypeRemovedFromAllowlist() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address naturalPersonWallet = _createAndRegisterWalletForType(NATURAL_PERSON_ENTITY, "naturalPersonActivator");

        vm.prank(_adminID);
        Marketplace(_marketplace).setAllowedEntityType(NATURAL_PERSON_ENTITY, true);

        vm.prank(naturalPersonWallet);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.prank(_adminID);
        Marketplace(_marketplace).setAllowedEntityType(NATURAL_PERSON_ENTITY, false);

        uint256 dealId = Marketplace(_marketplace).activateInterest(interestId);

        Deal memory deal = _getDeal(dealId);
        Interest memory interest = _getInterest(interestId);
        assertEq(deal.buyer, naturalPersonWallet);
        assertEq(uint8(interest.status), uint8(InterestStatus.ACTIVATED));
    }

    function test_activateInterest_reverts_investorWalletDisabled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(investor, AccountStatus.DISABLED, "");

        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, investor)
        );
        Marketplace(_marketplace).activateInterest(interestId);
    }

    function test_activateInterest_reverts_sellerWalletDisabled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(_company, AccountStatus.DISABLED, "");

        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, _company)
        );
        Marketplace(_marketplace).activateInterest(interestId);
    }

    function test_activateInterest_reverts_redemptionOffer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        _overwriteOfferSaleMode(offerId, SaleMode.REDEMPTION);

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotInterestDiscoveryOffer.selector, offerId));
        Marketplace(_marketplace).activateInterest(interestId);
    }

    /*//////////////////////////////////////////////////////////////
                           closeExpiredInterests
    //////////////////////////////////////////////////////////////*/

    function test_closeExpiredInterests_success_releasesReservedInventoryInBatch() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 2);
        address investorOne = _createAndRegisterOtherCompany();
        (address investorTwo,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("thresholdInvestorThree"));

        vm.prank(investorOne);
        uint256 firstInterestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);
        vm.prank(investorTwo);
        uint256 secondInterestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        Marketplace(_marketplace).activateInterest(firstInterestId);

        uint256 activationDeadline = _interestActivationDeadline(offerId);
        vm.warp(activationDeadline + 1);

        uint256[] memory interestIds = new uint256[](1);
        interestIds[0] = secondInterestId;

        vm.prank(_adminID);
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);

        Offer memory offer = _getOffer(offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        Interest memory secondInterest = _getInterest(secondInterestId);

        assertEq(state.reservedInterestUnits, 0);
        assertEq(uint8(secondInterest.status), uint8(InterestStatus.CLOSED));
        assertEq(offer.amounts.available, (BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE) - MIN_AMOUNT);
        assertEq(offer.amounts.inDeals, MIN_AMOUNT);
    }

    function test_closeExpiredInterests_success_emptyBatchDoesNotChangeAmounts() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        uint256 activationDeadline = _interestActivationDeadline(offerId);
        vm.warp(activationDeadline + 1);

        uint256[] memory interestIds = new uint256[](0);
        vm.prank(_company);
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);

        Offer memory offer = _getOffer(offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        assertEq(offer.amounts.available, (BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE) - MIN_AMOUNT);
        assertEq(state.reservedInterestUnits, MIN_AMOUNT);
    }

    function test_closeExpiredInterests_success_whileOfferFrozen() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 2);
        address investorOne = _createAndRegisterOtherCompany();
        address investorTwo = _createAndRegisterOtherCompany();

        vm.prank(investorOne);
        uint256 firstInterestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);
        vm.prank(investorTwo);
        uint256 secondInterestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        Marketplace(_marketplace).activateInterest(firstInterestId);

        uint256 activationDeadline = _interestActivationDeadline(offerId);
        vm.warp(activationDeadline + 1);

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        uint256[] memory interestIds = new uint256[](1);
        interestIds[0] = secondInterestId;

        vm.prank(_adminID);
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);

        Offer memory offer = _getOffer(offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        Interest memory secondInterest = _getInterest(secondInterestId);

        assertTrue(_isOfferFrozen(offerId));
        assertEq(state.reservedInterestUnits, 0);
        assertEq(uint8(secondInterest.status), uint8(InterestStatus.CLOSED));
        assertEq(offer.amounts.available, (BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE) - MIN_AMOUNT);
        assertEq(offer.amounts.inDeals, MIN_AMOUNT);
    }

    function test_closeExpiredInterests_reverts_marketplaceOffer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerOfferAsCompany();
        uint256[] memory interestIds = new uint256[](0);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotInterestDiscoveryOffer.selector, offerId));
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);
    }

    function test_closeExpiredInterests_reverts_redemptionOffer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();
        OfferInput memory offer = _createOfferInput();
        offer.saleMode = SaleMode.REDEMPTION;
        offer.allowCounterOffers = false;
        offer.allowedBuyers = _singletonBuyerArray(allowedBuyer);
        uint256[] memory interestIds = new uint256[](0);

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotInterestDiscoveryOffer.selector, offerId));
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);
    }

    function test_closeExpiredInterests_reverts_notAuthorized() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();
        uint256[] memory interestIds = new uint256[](0);

        vm.prank(investor);
        vm.expectRevert(Ownable.Unauthorized.selector);
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);
    }

    function test_closeExpiredInterests_reverts_whenOwnerDisabled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        uint256[] memory interestIds = new uint256[](0);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(_company, AccountStatus.DISABLED, "");

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, _company));
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);
    }

    function test_closeExpiredInterests_reverts_whenDisabledOwnerAlsoOperator() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        uint256[] memory interestIds = new uint256[](0);
        _grantRoles(_marketplace, _company, Marketplace(_marketplace).INTEREST_DISCOVERY_OPERATOR());

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(_company, AccountStatus.DISABLED, "");

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, _company));
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);
    }

    function test_closeExpiredInterests_reverts_pureAdminWithoutOperatorRole() public {
        // ADMIN no longer grants the right to close expired interests.
        // Only INTEREST_DISCOVERY_OPERATOR (or the enabled offer owner) may do so.
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address pureAdmin = makeAddr("pureAdmin");
        _grantRoles(_marketplace, pureAdmin, Marketplace(_marketplace).ADMIN());

        uint256[] memory interestIds = new uint256[](0);
        vm.prank(pureAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);
    }

    function test_closeExpiredInterests_success_byOperator_whenOwnerDisabled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        uint256 activationDeadline = _interestActivationDeadline(offerId);
        vm.warp(activationDeadline + 1);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(_company, AccountStatus.DISABLED, "");

        uint256[] memory interestIds = new uint256[](1);
        interestIds[0] = interestId;
        vm.prank(_adminID);
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);

        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        assertEq(state.reservedInterestUnits, 0);
    }

    function test_closeExpiredInterests_reverts_beforeActivationWindowCloses() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        uint256 activationDeadline = _interestActivationDeadline(offerId);

        uint256[] memory interestIds = new uint256[](1);
        interestIds[0] = interestId;

        vm.warp(activationDeadline);
        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__InterestActivationWindowOpen.selector, offerId, activationDeadline, block.timestamp
            )
        );
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);
    }

    function test_closeExpiredInterests_reverts_beforeSnapshottedActivationWindowClosesAfterConfigReduction() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();
        uint256 snapshottedPaymentExpiry = _getInterestDiscoveryState(offerId).paymentExpiryThreshold;
        uint256 reducedPaymentExpiry = MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD();
        assertLt(reducedPaymentExpiry, snapshottedPaymentExpiry);

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.prank(_adminID);
        Marketplace(_marketplace).setInterestDiscoveryPaymentExpiryThreshold(reducedPaymentExpiry);

        uint256[] memory interestIds = new uint256[](1);
        interestIds[0] = interestId;

        vm.warp(OFFER_EXPIRY + reducedPaymentExpiry + 1);
        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__InterestActivationWindowOpen.selector,
                offerId,
                OFFER_EXPIRY + snapshottedPaymentExpiry,
                block.timestamp
            )
        );
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);
    }

    function test_closeExpiredInterests_reverts_thresholdNotReached() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 2);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        uint256 activationDeadline = _interestActivationDeadline(offerId);
        vm.warp(activationDeadline + 1);

        uint256[] memory interestIds = new uint256[](1);
        interestIds[0] = interestId;

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__ThresholdNotReached.selector, offerId, MIN_AMOUNT, MIN_AMOUNT * 2
            )
        );
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);
    }

    function test_closeExpiredInterests_reverts_interestOfferMismatch() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 halfOfferAmount = (BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE) / 2;
        OfferInput memory firstOffer = _createInterestDiscoveryOfferInput(MIN_AMOUNT);
        firstOffer.totalAmount = halfOfferAmount;
        OfferInput memory secondOffer = _createInterestDiscoveryOfferInput(MIN_AMOUNT);
        secondOffer.totalAmount = halfOfferAmount;
        uint256 firstOfferId;
        uint256 secondOfferId;
        vm.startPrank(_company);
        firstOfferId = Marketplace(_marketplace).registerOffer(firstOffer);
        secondOfferId = Marketplace(_marketplace).registerOffer(secondOffer);
        vm.stopPrank();
        address investor = _createAndRegisterOtherCompany();
        address secondInvestor = _createAndRegisterWalletForType(COMPANY_ENTITY, "secondThresholdInvestor");

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(firstOfferId, MIN_AMOUNT);
        vm.prank(secondInvestor);
        Marketplace(_marketplace).expressInterest(secondOfferId, MIN_AMOUNT);

        uint256 activationDeadline = _interestActivationDeadline(secondOfferId);
        vm.warp(activationDeadline + 1);

        uint256[] memory interestIds = new uint256[](1);
        interestIds[0] = interestId;

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__InterestOfferMismatch.selector, interestId, secondOfferId)
        );
        Marketplace(_marketplace).closeExpiredInterests(secondOfferId, interestIds);
    }

    function test_closeExpiredInterests_reverts_invalidInterestStatus() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);
        Marketplace(_marketplace).activateInterest(interestId);

        uint256 activationDeadline = _interestActivationDeadline(offerId);
        vm.warp(activationDeadline + 1);

        uint256[] memory interestIds = new uint256[](1);
        interestIds[0] = interestId;

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__InvalidInterestStatus.selector, interestId, uint8(InterestStatus.ACTIVATED)
            )
        );
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);
    }

    /*//////////////////////////////////////////////////////////////
                                cancelOffer
    //////////////////////////////////////////////////////////////*/

    function test_cancelOffer_success_fullAmount() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        Balances memory balancesBefore = _snapshotBalances();
        uint256 cancelTimestamp = block.timestamp;
        // ACT
        vm.expectEmit();
        emit IMarketplace.OfferCancelled(offerId, _company);
        vm.expectEmit();
        emit IMarketplace.AmountsUpdated(offerId, 0, 0, 0);

        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);
        // ASSERT
        // variables in interest discovery
        Offer memory offerRegistered = _getOffer(offerId);
        assertEq(offerRegistered.amounts.available, 0);
        assertEq(offerRegistered.amounts.inDeals, 0);
        assertEq(offerRegistered.amounts.sold, 0);
        assertEq(offerRegistered.expiry, cancelTimestamp);
        assertEq(_isOfferCancelled(offerId), true);
        // variables in escrow manager
        Escrow memory escrow = EscrowManager(_escrowManager).getEscrow(_getEscrowIdByOfferId(offerId));
        assertEq(escrow.amount, 0);
        // variables in fungible token
        Balances memory balancesAfter = _snapshotBalances();
        assertEq(balancesAfter.company, balancesBefore.company + balancesBefore.escrow);
        assertEq(balancesAfter.escrow, 0);
    }

    function test_cancelOffer_success_partialAmount() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        uint256 amountOfBondsToBuy = 1000;
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, amountOfBondsToBuy, otherCompany);
        Balances memory balancesBefore = _snapshotBalances();
        // ACT
        vm.expectEmit();
        emit IMarketplace.OfferCancelled(offerId, _company);
        vm.expectEmit();
        emit IMarketplace.AmountsUpdated(offerId, 0, amountOfBondsToBuy, 0);

        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);
        // ASSERT
        // variables in interest discovery
        Offer memory offerRegistered = _getOffer(offerId);
        assertEq(offerRegistered.amounts.available, 0);
        assertEq(offerRegistered.amounts.inDeals, amountOfBondsToBuy);
        assertEq(offerRegistered.amounts.sold, 0);
        // variables in escrow manager
        Escrow memory escrow = EscrowManager(_escrowManager).getEscrow(_getEscrowIdByOfferId(offerId));
        assertEq(escrow.amount, amountOfBondsToBuy);
        // variables in fungible token
        Balances memory balancesAfter = _snapshotBalances();
        assertEq(balancesAfter.company, balancesBefore.escrow - amountOfBondsToBuy);
        assertEq(balancesAfter.escrow, amountOfBondsToBuy);
        // amounts in deal have NOT changed
        Deal memory deal = _getDeal(dealId);
        assertEq(deal.amount, amountOfBondsToBuy);
    }

    function test_cancelOffer_reverts_alreadyCancelled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferAlreadyCancelled.selector, offerId));
        Marketplace(_marketplace).cancelOffer(offerId);
    }

    function test_cancelOffer_reverts_notAuthorized() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();

        vm.prank(otherCompany);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, otherCompany));
        Marketplace(_marketplace).cancelOffer(offerId);
    }

    function test_cancelOffer_reverts_directSaleByInterestDiscoveryOperator() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        vm.prank(_adminID);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, _adminID));
        Marketplace(_marketplace).cancelOffer(offerId);
    }

    function test_cancelOffer_reverts_whenOwnerDisabled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(_company, AccountStatus.DISABLED, "");

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, _company));
        Marketplace(_marketplace).cancelOffer(offerId);
    }

    function test_cancelOffer_reverts_noAvailableAmount_whenFullyResolved() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        uint256 totalAmount = BOND_MAX_SUPPLY;
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, totalAmount, otherCompany);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);
        Marketplace(_marketplace).settleDeal(dealId);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NoAvailableAmount.selector, offerId));
        Marketplace(_marketplace).cancelOffer(offerId);
    }

    function test_cancelOffer_success_whenNoAvailableButInDeals() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        uint256 totalAmount = BOND_MAX_SUPPLY;
        address otherCompany = _createAndRegisterOtherCompany();
        _acceptOffer(offerId, totalAmount, otherCompany);

        Balances memory balancesBeforeCancel = _snapshotBalances();

        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);

        Offer memory offer = _getOffer(offerId);
        Escrow memory escrow = EscrowManager(_escrowManager).getEscrow(_getEscrowIdByOfferId(offerId));

        assertEq(offer.amounts.available, 0);
        assertEq(offer.amounts.inDeals, totalAmount);
        assertEq(_isOfferCancelled(offerId), true);
        assertEq(escrow.amount, totalAmount);

        Balances memory balancesAfterCancel = _snapshotBalances();
        assertEq(balancesAfterCancel.company, balancesBeforeCancel.company);
        assertEq(balancesAfterCancel.escrow, balancesBeforeCancel.escrow);
    }

    function test_withdrawAvailable_reverts_offerNotCancelled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferNotCancelled.selector, offerId));
        Marketplace(_marketplace).withdrawAvailable(offerId);
    }

    function test_withdrawAvailable_reverts_noAvailableAmount() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NoAvailableAmount.selector, offerId));
        Marketplace(_marketplace).withdrawAvailable(offerId);
    }

    function test_withdrawAvailable_reverts_notAuthorized() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 amountOfBondsToBuy = 1000;

        uint256 dealId = _acceptOffer(offerId, amountOfBondsToBuy, otherCompany);

        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);

        Deal memory dealBeforePaymentResolution = _getDeal(dealId);
        vm.warp(dealBeforePaymentResolution.paymentDeadline + 1);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        Deal memory dealBeforeSettle = _getDeal(dealId);
        vm.warp(dealBeforeSettle.disputeBuffer + 1);
        Marketplace(_marketplace).settleDeal(dealId);

        vm.prank(otherCompany);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, otherCompany));
        Marketplace(_marketplace).withdrawAvailable(offerId);
    }

    function test_withdrawAvailable_reverts_whenOwnerDisabled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(_company, AccountStatus.DISABLED, "");

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, _company));
        Marketplace(_marketplace).withdrawAvailable(offerId);
    }

    function test_withdrawAvailable_success_afterFailedDealReturnsAmount() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 amountOfBondsToBuy = 1000;

        uint256 dealId = _acceptOffer(offerId, amountOfBondsToBuy, otherCompany);

        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);

        _warpPastPaymentDeadline(dealId);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        Deal memory dealBeforeSettle = _getDeal(dealId);
        vm.warp(dealBeforeSettle.disputeBuffer + 1);
        Marketplace(_marketplace).settleDeal(dealId);

        Offer memory offerBeforeWithdraw = _getOffer(offerId);
        assertEq(offerBeforeWithdraw.amounts.available, amountOfBondsToBuy);

        Balances memory balancesBeforeWithdraw = _snapshotBalances();

        vm.prank(_company);
        Marketplace(_marketplace).withdrawAvailable(offerId);

        Offer memory offerAfterWithdraw = _getOffer(offerId);
        Escrow memory escrowAfterWithdraw = EscrowManager(_escrowManager).getEscrow(_getEscrowIdByOfferId(offerId));
        Balances memory balancesAfterWithdraw = _snapshotBalances();

        assertEq(offerAfterWithdraw.amounts.available, 0);
        assertEq(offerAfterWithdraw.amounts.inDeals, 0);
        assertEq(offerAfterWithdraw.amounts.sold, 0);
        assertEq(_isOfferCancelled(offerId), true);
        assertEq(escrowAfterWithdraw.amount, 0);
        assertEq(balancesAfterWithdraw.company, balancesBeforeWithdraw.company + amountOfBondsToBuy);
    }

    function test_withdrawAvailable_reverts_whenDealUnpaidAndSellerDisabled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 amount = 1000;
        uint256 dealId = _acceptOffer(offerId, amount, buyer);

        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);

        _warpPastPaymentDeadline(dealId);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        Deal memory dealBeforeSettle = _getDeal(dealId);
        vm.warp(dealBeforeSettle.disputeBuffer + 1);
        Marketplace(_marketplace).settleDeal(dealId);

        Offer memory offerBefore = _getOffer(offerId);
        uint256 escrowId = _getEscrowIdByOfferId(offerId);
        uint256 escrowBefore = EscrowManager(_escrowManager).getEscrow(escrowId).amount;
        assertEq(offerBefore.amounts.available, amount);
        assertEq(escrowBefore, amount);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(_company, AccountStatus.DISABLED, "disabled-before-withdraw");

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, _company));
        Marketplace(_marketplace).withdrawAvailable(offerId);

        Offer memory offerAfter = _getOffer(offerId);
        uint256 escrowAfter = EscrowManager(_escrowManager).getEscrow(escrowId).amount;
        assertEq(offerAfter.amounts.available, amount);
        assertEq(offerAfter.amounts.inDeals, 0);
        assertEq(offerAfter.amounts.sold, 0);
        assertEq(escrowAfter, amount);
    }

    function test_withdrawAvailable_reverts_afterExpiryBelowThreshold() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 2);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.warp(OFFER_EXPIRY + 1);
        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__ThresholdNotReached.selector, offerId, MIN_AMOUNT, MIN_AMOUNT * 2
            )
        );
        Marketplace(_marketplace).withdrawAvailable(offerId);
    }

    function test_withdrawAvailable_success_afterExpiryAboveThresholdWithdrawsOnlyUnreservedAmount() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 2);
        address investorOne = _createAndRegisterOtherCompany();
        (address investorTwo,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("thresholdInvestorFour"));

        vm.prank(investorOne);
        uint256 firstInterestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);
        vm.prank(investorTwo);
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        Marketplace(_marketplace).activateInterest(firstInterestId);

        vm.warp(OFFER_EXPIRY + 1);
        vm.prank(_company);
        Marketplace(_marketplace).withdrawAvailable(offerId);

        Offer memory offer = _getOffer(offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);

        assertEq(offer.amounts.available, 0);
        assertEq(offer.amounts.inDeals, MIN_AMOUNT);
        assertEq(state.reservedInterestUnits, MIN_AMOUNT);
        assertEq(
            DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId),
            (BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE) - (MIN_AMOUNT * 2)
        );
        assertEq(DEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), MIN_AMOUNT * 2);
    }

    function test_withdrawAvailable_success_afterCloseExpiredInterestsWithdrawsReleasedReservedAmount() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        uint256 activationDeadline = _interestActivationDeadline(offerId);
        vm.warp(activationDeadline + 1);

        uint256[] memory interestIds = new uint256[](1);
        interestIds[0] = interestId;
        vm.prank(_company);
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);

        Offer memory offerBeforeWithdraw = _getOffer(offerId);
        InterestDiscoveryState memory stateBeforeWithdraw = _getInterestDiscoveryState(offerId);
        assertEq(offerBeforeWithdraw.amounts.available, BOND_MAX_SUPPLY);
        assertEq(stateBeforeWithdraw.reservedInterestUnits, 0);

        vm.prank(_company);
        Marketplace(_marketplace).withdrawAvailable(offerId);

        Offer memory offerAfterWithdraw = _getOffer(offerId);
        assertEq(offerAfterWithdraw.amounts.available, 0);
        assertEq(
            DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId), BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE
        );
        assertEq(DEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), 0);
    }

    function test_withdrawAvailable_reverts_interestDiscoveryBeforeExpiry() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__OfferNotExpired.selector, OFFER_EXPIRY, block.timestamp)
        );
        Marketplace(_marketplace).withdrawAvailable(offerId);
    }

    function test_withdrawAvailable_reverts_interestDiscoveryNotAuthorized() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, investor));
        Marketplace(_marketplace).withdrawAvailable(offerId);
    }

    function test_withdrawAvailable_reverts_interestDiscoveryAfterFailedBookCancellation() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 2);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.warp(OFFER_EXPIRY + 1);
        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferAlreadyCancelled.selector, offerId));
        Marketplace(_marketplace).withdrawAvailable(offerId);
    }

    function test_cancelOffer_reverts_interestDiscoveryBeforeExpiry() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__OfferNotExpired.selector, OFFER_EXPIRY, block.timestamp)
        );
        Marketplace(_marketplace).cancelOffer(offerId);
    }

    function test_cancelOffer_success_interestDiscoveryBelowThreshold() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 2);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.warp(OFFER_EXPIRY + 1);

        vm.expectEmit();
        emit IMarketplace.OfferCancelled(offerId, _company);
        vm.expectEmit();
        emit IMarketplace.AmountsUpdated(offerId, 0, 0, 0);

        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);

        Offer memory offer = _getOffer(offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);

        assertTrue(_isOfferCancelled(offerId));
        assertEq(offer.amounts.available, 0);
        assertEq(offer.amounts.inDeals, 0);
        assertEq(offer.amounts.sold, 0);
        assertEq(state.reservedInterestUnits, 0);
        assertEq(
            DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId), BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE
        );
        assertEq(DEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), 0);
    }

    function test_cancelOffer_success_interestDiscoveryBelowThreshold_byOperator() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 2);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.warp(OFFER_EXPIRY + 1);

        vm.expectEmit();
        emit IMarketplace.OfferCancelled(offerId, _adminID);
        vm.expectEmit();
        emit IMarketplace.AmountsUpdated(offerId, 0, 0, 0);

        vm.prank(_adminID);
        Marketplace(_marketplace).cancelOffer(offerId);

        Offer memory offer = _getOffer(offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);

        assertTrue(_isOfferCancelled(offerId));
        assertEq(offer.amounts.available, 0);
        assertEq(offer.amounts.inDeals, 0);
        assertEq(offer.amounts.sold, 0);
        assertEq(state.reservedInterestUnits, 0);
        assertEq(
            DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId), BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE
        );
        assertEq(DEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), 0);
    }

    function test_cancelOffer_reverts_interestDiscoveryBelowThreshold_byPureAdminWithoutOperatorRole() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 2);
        address investor = _createAndRegisterOtherCompany();
        address pureAdmin = makeAddr("pureCancelAdmin");
        _grantRoles(_marketplace, pureAdmin, Marketplace(_marketplace).ADMIN());

        vm.prank(investor);
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.warp(OFFER_EXPIRY + 1);

        vm.prank(pureAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        Marketplace(_marketplace).cancelOffer(offerId);
    }

    function test_cancelOffer_reverts_interestDiscoveryBelowThreshold_byOperator_whenOwnerDisabled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 2);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.warp(OFFER_EXPIRY + 1);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(_company, AccountStatus.DISABLED, "disabled-before-operator-cancel");

        vm.prank(_adminID);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, _adminID));
        Marketplace(_marketplace).cancelOffer(offerId);
    }

    function test_cancelOffer_reverts_interestDiscoveryThresholdReached() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.warp(OFFER_EXPIRY + 1);

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__ThresholdAlreadyReached.selector, offerId, MIN_AMOUNT, MIN_AMOUNT
            )
        );
        Marketplace(_marketplace).cancelOffer(offerId);
    }

    function test_cancelOffer_success_redemption() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();
        Balances memory balancesBefore = _snapshotBalances();
        uint256 cancelTimestamp = block.timestamp;

        OfferInput memory offer = _createOfferInput();
        offer.saleMode = SaleMode.REDEMPTION;
        offer.allowCounterOffers = false;
        offer.allowedBuyers = _singletonBuyerArray(allowedBuyer);

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);

        Offer memory offerRegistered = _getOffer(offerId);
        Escrow memory escrow = EscrowManager(_escrowManager).getEscrow(_getEscrowIdByOfferId(offerId));
        Balances memory balancesAfter = _snapshotBalances();

        assertTrue(_isOfferCancelled(offerId));
        assertEq(offerRegistered.amounts.available, 0);
        assertEq(offerRegistered.amounts.inDeals, 0);
        assertEq(offerRegistered.amounts.sold, 0);
        assertEq(offerRegistered.expiry, cancelTimestamp);
        assertEq(escrow.amount, 0);
        assertEq(balancesAfter.company, balancesBefore.company + balancesBefore.escrow);
        assertEq(balancesAfter.escrow, 0);
    }

    function test_withdrawAvailable_success_redemptionAfterFailedDealReturnsAmount() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();
        uint256 amountOfBondsToBuy = 1000;

        OfferInput memory offer = _createOfferInput();
        offer.saleMode = SaleMode.REDEMPTION;
        offer.allowCounterOffers = false;
        offer.allowedBuyers = _singletonBuyerArray(allowedBuyer);

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        vm.prank(allowedBuyer);
        uint256 dealId = Marketplace(_marketplace).acceptOffer(offerId, amountOfBondsToBuy);

        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);

        Deal memory dealBeforePaymentResolution = _getDeal(dealId);
        vm.warp(dealBeforePaymentResolution.paymentDeadline + 1);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        Deal memory dealBeforeSettle = _getDeal(dealId);
        vm.warp(dealBeforeSettle.disputeBuffer + 1);
        Marketplace(_marketplace).settleDeal(dealId);

        Offer memory offerBeforeWithdraw = _getOffer(offerId);
        assertEq(offerBeforeWithdraw.amounts.available, amountOfBondsToBuy);

        uint256 buyerBalanceBeforeWithdraw = DEUSSToken(_tokenAddr).balanceOf(allowedBuyer, _bondFTId);
        Balances memory balancesBeforeWithdraw = _snapshotBalances();

        vm.prank(_company);
        Marketplace(_marketplace).withdrawAvailable(offerId);

        Offer memory updatedOffer = _getOffer(offerId);
        Escrow memory escrow = EscrowManager(_escrowManager).getEscrow(_getEscrowIdByOfferId(offerId));
        Balances memory balancesAfterWithdraw = _snapshotBalances();

        assertEq(updatedOffer.amounts.available, 0);
        assertEq(updatedOffer.amounts.inDeals, 0);
        assertEq(updatedOffer.amounts.sold, 0);
        assertEq(escrow.amount, 0);
        assertEq(DEUSSToken(_tokenAddr).balanceOf(allowedBuyer, _bondFTId), buyerBalanceBeforeWithdraw);
        assertEq(balancesAfterWithdraw.company, balancesBeforeWithdraw.company + amountOfBondsToBuy);
        assertEq(balancesAfterWithdraw.escrow, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            COUNTER OFFERS
    //////////////////////////////////////////////////////////////*/

    function test_createCounterOffer_asCompany_success() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        uint256 expectedDealId = 1;
        uint256 expectedPaymentExpiry = 0; // counter offers must have no payment deadline!
        address otherCompany = _createAndRegisterOtherCompany();

        // ACT & ASSERT
        vm.expectEmit();
        emit IMarketplace.DealCreated(
            offerId, expectedDealId, otherCompany, DealType.COUNTER_OFFER, MIN_AMOUNT, MIN_AMOUNT * UNIT_PRICE
        );
        vm.expectEmit();
        emit IMarketplace.DealTermsRegistered(expectedDealId, expectedPaymentExpiry, _counterOfferExpiry(), 0);
        vm.expectEmit();
        emit IMarketplace.CounterOfferCreated(offerId, expectedDealId, otherCompany);
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);

        // ASSERT
        Deal memory deal = _getDeal(dealId);
        assertEq(deal.buyer, otherCompany);
        assertEq(uint8(deal.status), uint8(DealStatus.PROPOSED));
        assertEq(uint8(deal.dealType), uint8(DealType.COUNTER_OFFER));
    }

    function test_createCounterOffer_success_expiryAtMaxOfferLifetime() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 counterOfferExpiry = block.timestamp + _config().maxOfferLifetime;

        vm.prank(otherCompany);
        uint256 dealId = Marketplace(_marketplace)
            .createCounterOffer(
                CounterOfferInput({
                offerId: offerId, amount: MIN_AMOUNT, unitPrice: UNIT_PRICE, expiry: counterOfferExpiry
            })
            );

        Deal memory deal = _getDeal(dealId);
        assertEq(deal.counterOfferExpiry, counterOfferExpiry);
        assertEq(deal.buyer, otherCompany);
        assertEq(uint8(deal.status), uint8(DealStatus.PROPOSED));
        assertEq(uint8(deal.dealType), uint8(DealType.COUNTER_OFFER));
    }

    function test_createCounterOffer_success_marketplaceAllowlistedBuyer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();

        OfferInput memory offer = _createOfferInput();
        offer.allowedBuyers = _singletonBuyerArray(allowedBuyer);

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, allowedBuyer);

        Deal memory deal = _getDeal(dealId);
        assertEq(deal.offerId, offerId);
        assertEq(deal.buyer, allowedBuyer);
        assertEq(uint8(deal.status), uint8(DealStatus.PROPOSED));
    }

    function test_createCounterOffer_reverts_marketplaceBuyerNotAllowed() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();
        address blockedBuyer = _createAndRegisterWalletForType(COMPANY_ENTITY, "marketplaceBlockedCounterBuyer");

        OfferInput memory offer = _createOfferInput();
        offer.allowedBuyers = _singletonBuyerArray(allowedBuyer);

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__BuyerNotAllowed.selector, offerId, blockedBuyer));
        _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, blockedBuyer);
    }

    function test_createCounterOffer_reverts_redemptionOffer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();
        address blockedBuyer = _createAndRegisterWalletForType(COMPANY_ENTITY, "counterOfferBuyer");

        OfferInput memory offer = _createOfferInput();
        offer.saleMode = SaleMode.REDEMPTION;
        offer.allowCounterOffers = false;
        offer.allowedBuyers = _singletonBuyerArray(allowedBuyer);

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);
        _overwriteOfferAllowCounterOffers(offerId, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotMarketplaceOffer.selector, offerId));
        _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, blockedBuyer);
    }

    function test_createCounterOffer_reverts_redemptionAllowlistedBuyer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();

        OfferInput memory offer = _createOfferInput();
        offer.saleMode = SaleMode.REDEMPTION;
        offer.allowCounterOffers = false;
        offer.allowedBuyers = _singletonBuyerArray(allowedBuyer);

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);
        _overwriteOfferAllowCounterOffers(offerId, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotMarketplaceOffer.selector, offerId));
        _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, allowedBuyer);
    }

    function test_createCounterOffer_reverts_unauthorizedBuyer() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        // ACT
        address otherCompany = makeAddr("otherCompany");
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, otherCompany)
        );
        _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);
    }

    function test_createCounterOffer_reverts_sellerWalletDisabled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(_company, AccountStatus.DISABLED, "");

        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, _company)
        );
        _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);
    }

    function test_createCounterOffer_reverts_buyerTypeNotAllowed() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address naturalPersonWallet = _createAndRegisterWalletForType(NATURAL_PERSON_ENTITY, "naturalPersonCounter");

        vm.prank(_adminID);
        Marketplace(_marketplace).setAllowedEntityType(NATURAL_PERSON_ENTITY, false);

        vm.prank(naturalPersonWallet);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityTypeNotAllowed.selector, NATURAL_PERSON_ENTITY)
        );
        Marketplace(_marketplace)
            .createCounterOffer(
                CounterOfferInput({
                offerId: offerId, amount: MIN_AMOUNT, expiry: _counterOfferExpiry(), unitPrice: UNIT_PRICE
            })
            );
    }

    function test_createCounterOffer_reverts_expiredOffer() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();

        // get offer expiry
        uint256 offerExpiry = _getOffer(offerId).expiry;

        vm.warp(offerExpiry + 1);

        // ACT
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferExpired.selector, offerExpiry, block.timestamp));
        _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);
    }

    function test_createCounterOffer_reverts_invalidAmount() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        uint256 amount = BOND_MAX_SUPPLY - 1;
        address otherCompany = _createAndRegisterOtherCompany();

        // ACT
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__AmountNotMultipleOfLot.selector, MIN_AMOUNT, amount));
        _createCounterOffer(offerId, amount, UNIT_PRICE, otherCompany);
    }

    function test_createCounterOffer_reverts_zeroAmount() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();

        // ACT
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__ZeroAmount.selector));
        _createCounterOffer(offerId, 0, UNIT_PRICE, otherCompany);
    }

    function test_createCounterOffer_reverts_zeroUnitPrice() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();

        // ACT & ASSERT
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__ZeroPrice.selector));
        _createCounterOffer(offerId, MIN_AMOUNT, 0, otherCompany);
    }

    function test_createCounterOffer_reverts_insufficientAmount() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        uint256 available = _getOffer(offerId).amounts.available;
        address otherCompany = _createAndRegisterOtherCompany();

        // ACT
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__InsufficientAvailableAmount.selector, available + 1, available)
        );
        _createCounterOffer(offerId, available + 1, UNIT_PRICE, otherCompany);
    }

    function test_createCounterOffer_reverts_senderIsOwner() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        // Company tries to create counter offer to their own offer
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__SenderIsOwner.selector));
        vm.prank(_company);
        Marketplace(_marketplace)
            .createCounterOffer(
                CounterOfferInput({
                offerId: offerId, amount: MIN_AMOUNT, unitPrice: UNIT_PRICE, expiry: _counterOfferExpiry()
            })
            );
    }

    function test_createCounterOffer_reverts_counterOfferExpiry() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        address otherCompany = _createAndRegisterOtherCompany();

        // Company tries to create counter offer to their own offer
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__InvalidExpiry.selector, block.timestamp, block.timestamp)
        );
        vm.prank(otherCompany);
        Marketplace(_marketplace)
            .createCounterOffer(
                CounterOfferInput({
                offerId: offerId, amount: MIN_AMOUNT, unitPrice: UNIT_PRICE, expiry: block.timestamp
            })
            );
    }

    function test_createCounterOffer_reverts_counterOfferExpiryAboveMaxOfferLifetime() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 maxOfferLifetime = _config().maxOfferLifetime;
        uint256 counterOfferExpiry = block.timestamp + maxOfferLifetime + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__ExpiryTooFar.selector, counterOfferExpiry, block.timestamp, maxOfferLifetime
            )
        );
        vm.prank(otherCompany);
        Marketplace(_marketplace)
            .createCounterOffer(
                CounterOfferInput({
                offerId: offerId, amount: MIN_AMOUNT, unitPrice: UNIT_PRICE, expiry: counterOfferExpiry
            })
            );
    }

    function test_createCounterOffer_reverts_counterOffersNotAllowed() public {
        // ARRANGE - Create offer with allowCounterOffers = false
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address otherCompany = _createAndRegisterOtherCompany();
        OfferInput memory offer = _createOfferInput();
        offer.allowCounterOffers = false;

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        // ACT & ASSERT - Try to create counter offer
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__CounterOffersNotAllowed.selector));
        _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);
    }

    function test_createCounterOffer_reverts_offerCancelled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();

        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferAlreadyCancelled.selector, offerId));
        _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);
    }

    function test_createCounterOffer_reverts_counterOfferLimitReached() public {
        // ARRANGE - Create offer with counter offers allowed
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        // Get the max counter offers limit (should be 5)
        uint256 maxCounterOffers = _config().maxCounterOffersPerUser;

        // ACT - Create exactly maxCounterOffers counter offers
        address otherCompany = _createAndRegisterOtherCompany();
        for (uint256 i; i < maxCounterOffers; ++i) {
            vm.prank(otherCompany);
            Marketplace(_marketplace)
                .createCounterOffer(
                    CounterOfferInput({
                    offerId: offerId, amount: MIN_AMOUNT, unitPrice: UNIT_PRICE, expiry: _counterOfferExpiry()
                })
                );
        }

        // ASSERT - Try to create one more counter offer (should fail)
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__CounterOfferLimitReached.selector));
        _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);
    }

    function test_createCounterOffer_success_sameUserCanCreateMultipleBeforeLimit() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        // ACT - Create first counter offer
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 firstDealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);

        // ASSERT
        assertEq(_getDeal(firstDealId).buyer, otherCompany);

        // ACT - Create second counter offer
        uint256 secondDealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);

        // ASSERT
        assertEq(_getDeal(secondDealId).buyer, otherCompany);
    }

    function test_createCounterOffer_success_differentUsersIndependentCounters() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        uint256 maxCounterOffers = _config().maxCounterOffersPerUser;
        address otherCompany = _createAndRegisterOtherCompany();
        (address anotherOtherCompany,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("anotherOtherCompanyOwner"));

        // ACT - One user consumes their full per-offer quota.
        for (uint256 i; i < maxCounterOffers; ++i) {
            _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);
        }

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__CounterOfferLimitReached.selector));
        _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);

        // ASSERT - Another user still has an independent quota for the same offer.
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, anotherOtherCompany);
        assertEq(_getDeal(dealId).buyer, anotherOtherCompany);
    }

    function test_createCounterOffer_success_differentOffersIndependentCounters() public {
        // ARRANGE - Create two offers
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 maxCounterOffers = _config().maxCounterOffersPerUser;

        OfferInput memory offer1 = _createOfferInput();
        offer1.totalAmount = (BOND_MAX_SUPPLY) / 2;
        vm.prank(_company);
        uint256 offerId1 = Marketplace(_marketplace).registerOffer(offer1);

        OfferInput memory offer2 = _createOfferInput();
        offer2.totalAmount = (BOND_MAX_SUPPLY) / 2;
        vm.prank(_company);
        uint256 offerId2 = Marketplace(_marketplace).registerOffer(offer2);

        // ACT - Create counter offers on both offers
        address otherCompany = _createAndRegisterOtherCompany();
        for (uint256 i; i < maxCounterOffers; ++i) {
            _createCounterOffer(offerId1, MIN_AMOUNT, UNIT_PRICE, otherCompany);
        }

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__CounterOfferLimitReached.selector));
        _createCounterOffer(offerId1, MIN_AMOUNT, UNIT_PRICE, otherCompany);

        // ASSERT - The same user still has an independent quota for a different offer.
        uint256 dealId = _createCounterOffer(offerId2, MIN_AMOUNT, UNIT_PRICE, otherCompany);
        assertEq(_getDeal(dealId).offerId, offerId2);
    }

    /*//////////////////////////////////////////////////////////////
                           cancelCounterOffer
    //////////////////////////////////////////////////////////////*/

    function test_cancelCounterOffer_byBuyer_success() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);

        // ACT
        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            dealId, _getDeal(dealId).offerId, uint8(DealStatus.CANCELLED), uint8(_getDeal(dealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.CounterOfferCancelled(dealId, otherCompany);
        vm.prank(otherCompany);
        Marketplace(_marketplace).cancelCounterOffer(dealId);
    }

    function test_cancelCounterOffer_success_whenTypeRemovedAfterCreation() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);

        vm.prank(_adminID);
        Marketplace(_marketplace).setAllowedEntityType(COMPANY_ENTITY, false);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            dealId, _getDeal(dealId).offerId, uint8(DealStatus.CANCELLED), uint8(_getDeal(dealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.CounterOfferCancelled(dealId, otherCompany);
        vm.prank(otherCompany);
        Marketplace(_marketplace).cancelCounterOffer(dealId);
    }

    function test_cancelCounterOffer_reverts_expired() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);
        // get counter offer expiry
        Deal memory deal = _getDeal(dealId);
        uint256 counterOfferExpiry = deal.counterOfferExpiry;
        vm.warp(counterOfferExpiry + 1);

        // ACT
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__CounterOfferExpired.selector, counterOfferExpiry, block.timestamp
            )
        );
        vm.prank(otherCompany);
        Marketplace(_marketplace).cancelCounterOffer(dealId);
    }

    function test_cancelCounterOffer_reverts_whenBuyerDisabled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(otherCompany, AccountStatus.DISABLED, "");

        vm.prank(otherCompany);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, otherCompany));
        Marketplace(_marketplace).cancelCounterOffer(dealId);
    }

    function test_cancelCounterOffer_reverts_invalidStatus() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);
        vm.prank(_company);
        IMarketplace(_marketplace).resolveCounterOffer(dealId, true);

        // ACT
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(DealStatus.PENDING)));
        vm.prank(otherCompany);
        Marketplace(_marketplace).cancelCounterOffer(dealId);
    }

    function test_cancelCounterOffer_reverts_redemptionOffer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();

        uint256 offerId = _registerOfferAsCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, allowedBuyer);
        _overwriteOfferSaleMode(offerId, SaleMode.REDEMPTION);

        vm.prank(allowedBuyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotMarketplaceOffer.selector, offerId));
        Marketplace(_marketplace).cancelCounterOffer(dealId);
    }

    /*//////////////////////////////////////////////////////////////
                          resolveCounterOffer
    //////////////////////////////////////////////////////////////*/

    function test_resolveCounterOffer_accepted_success() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);
        uint256 offerAmount = (MIN_AMOUNT * UNIT_PRICE);
        uint256 dealAmount = MIN_AMOUNT;

        // ACT
        vm.expectEmit();
        emit IMarketplace.AmountsUpdated(
            offerId,
            offerAmount - dealAmount, // new `available`
            dealAmount, // new `inDeals`
            0 // new `sold`
        );
        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            dealId, _getDeal(dealId).offerId, uint8(DealStatus.PENDING), uint8(_getDeal(dealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.CounterOfferResolved(
            dealId, true, _bondFTId, MIN_AMOUNT, BOND_CURRENCY_BYTES3, otherCompany, _company
        );
        vm.prank(_company);
        Marketplace(_marketplace).resolveCounterOffer(dealId, true);
    }

    function test_resolveCounterOffer_accepted_reverts_afterOriginalOfferExpiry() public {
        // ARRANGE - create counter offer with expiry longer than original offer
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();

        uint256 offerExpiry = _getOffer(offerId).expiry;
        // Create counter offer with expiry well beyond original offer expiry
        CounterOfferInput memory counterOffer = CounterOfferInput({
            offerId: offerId, amount: MIN_AMOUNT, expiry: offerExpiry + 5 days, unitPrice: UNIT_PRICE
        });
        vm.prank(otherCompany);
        uint256 dealId = Marketplace(_marketplace).createCounterOffer(counterOffer);

        // Warp past original offer expiry but before counter offer expiry
        vm.warp(offerExpiry + 1);

        // ACT - resolve counter offer after original offer expired
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferExpired.selector, offerExpiry, block.timestamp));
        vm.prank(_company);
        Marketplace(_marketplace).resolveCounterOffer(dealId, true);
    }

    function test_resolveCounterOffer_notAccepted_success_afterOriginalOfferExpiry() public {
        // ARRANGE - create counter offer with expiry longer than original offer
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();

        uint256 offerExpiry = _getOffer(offerId).expiry;
        CounterOfferInput memory counterOffer = CounterOfferInput({
            offerId: offerId, amount: MIN_AMOUNT, expiry: offerExpiry + 5 days, unitPrice: UNIT_PRICE
        });
        vm.prank(otherCompany);
        uint256 dealId = Marketplace(_marketplace).createCounterOffer(counterOffer);

        vm.warp(offerExpiry + 1);

        // ACT - decline remains available after the original offer expires
        vm.prank(_company);
        Marketplace(_marketplace).resolveCounterOffer(dealId, false);

        // ASSERT
        Deal memory deal = _getDeal(dealId);
        assertEq(uint8(deal.status), uint8(DealStatus.DECLINED));
        assertEq(deal.counterOfferExpiry, 0);
    }

    function test_resolveCounterOffer_notAccepted_success() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);

        // ACT
        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            dealId, _getDeal(dealId).offerId, uint8(DealStatus.DECLINED), uint8(_getDeal(dealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.CounterOfferResolved(
            dealId, false, _bondFTId, MIN_AMOUNT, BOND_CURRENCY_BYTES3, otherCompany, _company
        );
        vm.prank(_company);
        Marketplace(_marketplace).resolveCounterOffer(dealId, false);
    }

    function test_resolveCounterOffer_notAccepted_success_whenTypeRemoved() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);

        vm.prank(_adminID);
        Marketplace(_marketplace).setAllowedEntityType(COMPANY_ENTITY, false);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            dealId, _getDeal(dealId).offerId, uint8(DealStatus.DECLINED), uint8(_getDeal(dealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.CounterOfferResolved(
            dealId, false, _bondFTId, MIN_AMOUNT, BOND_CURRENCY_BYTES3, otherCompany, _company
        );
        vm.prank(_company);
        Marketplace(_marketplace).resolveCounterOffer(dealId, false);
    }

    function test_resolveCounterOffer_accepted_reverts_redemptionOffer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();

        uint256 offerId = _registerOfferAsCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, allowedBuyer);
        _overwriteOfferSaleMode(offerId, SaleMode.REDEMPTION);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotMarketplaceOffer.selector, offerId));
        Marketplace(_marketplace).resolveCounterOffer(dealId, true);
    }

    function test_resolveCounterOffer_notAccepted_reverts_redemptionOffer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();

        uint256 offerId = _registerOfferAsCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, allowedBuyer);
        _overwriteOfferSaleMode(offerId, SaleMode.REDEMPTION);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotMarketplaceOffer.selector, offerId));
        Marketplace(_marketplace).resolveCounterOffer(dealId, false);
    }

    function test_resolveCounterOffer_reverts_offerCancelled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);

        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferAlreadyCancelled.selector, offerId));
        Marketplace(_marketplace).resolveCounterOffer(dealId, true);
    }

    function test_resolveCounterOffer_reverts_invalidStatus() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);
        vm.prank(_company);
        IMarketplace(_marketplace).resolveCounterOffer(dealId, true);

        // ACT
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(DealStatus.PENDING)));
        vm.prank(otherCompany);
        Marketplace(_marketplace).resolveCounterOffer(dealId, true);
    }

    function test_resolveCounterOffer_reverts_unauthorizedSeller() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);

        // ACT
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, otherCompany));
        vm.prank(otherCompany);
        Marketplace(_marketplace).resolveCounterOffer(dealId, true);
    }

    function test_resolveCounterOffer_reverts_whenOwnerDisabled() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(_company, AccountStatus.DISABLED, "");

        // ACT
        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, _company));
        Marketplace(_marketplace).resolveCounterOffer(dealId, true);
    }

    function test_resolveCounterOffer_reverts_zeroAmount() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);

        // Force a legacy/invalid counter-offer state with amount = 0 without hardcoding storage layout.
        address mutationImpl = address(new MarketplaceDealMutationHarness());
        _timelockOp(
            _suite.core.marketplaceBeacon, abi.encodeWithSelector(UpgradeableBeacon.upgradeTo.selector, mutationImpl)
        );
        MarketplaceDealMutationHarness(_marketplace).exposedSetDealAmount(dealId, 0);

        // ACT
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__ZeroAmount.selector));
        vm.prank(_company);
        Marketplace(_marketplace).resolveCounterOffer(dealId, true);
    }

    function test_resolveCounterOffer_reverts_insufficientAmount() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        uint256 dealAmount = MIN_AMOUNT * UNIT_PRICE;
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, dealAmount, UNIT_PRICE, otherCompany);
        // ARRANGE - accept another counter offer that decreases the available amount below the originally counter-offered amount
        uint256 dealId2 = _createCounterOffer(offerId, dealAmount, UNIT_PRICE, otherCompany);

        vm.prank(_company);
        IMarketplace(_marketplace).resolveCounterOffer(dealId2, true);

        // ACT
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InsufficientAvailableAmount.selector, dealAmount, 0));
        vm.prank(_company);
        Marketplace(_marketplace).resolveCounterOffer(dealId, true);
    }

    function test_resolveCounterOffer_reverts_expiredCounterOffer() public {
        // ARRANGE
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);

        uint256 offerId = _registerOfferAsCompany();

        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);

        // Get counter offer expiry
        Deal memory deal = _getDeal(dealId);
        uint256 counterOfferExpiry = deal.counterOfferExpiry;

        // Warp time past counter offer expiry
        vm.warp(counterOfferExpiry + 1);

        // ACT
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__CounterOfferExpired.selector, counterOfferExpiry, block.timestamp
            )
        );
        vm.prank(_company);
        Marketplace(_marketplace).resolveCounterOffer(dealId, true);
    }

    function test_resolveCounterOffer_accepted_reverts_whenBuyerTypeRemovedAfterCreation() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        vm.prank(_adminID);
        Marketplace(_marketplace).setAllowedEntityType(NATURAL_PERSON_ENTITY, true);

        address naturalPersonWallet =
            _createAndRegisterWalletForType(NATURAL_PERSON_ENTITY, "naturalPersonCounterBuyer");
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, naturalPersonWallet);

        vm.prank(_adminID);
        Marketplace(_marketplace).setAllowedEntityType(NATURAL_PERSON_ENTITY, false);

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityTypeNotAllowed.selector, NATURAL_PERSON_ENTITY)
        );
        Marketplace(_marketplace).resolveCounterOffer(dealId, true);
    }

    function test_resolveCounterOffer_reverts_acceptedWhenBuyerWalletDisabled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, otherCompany);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(otherCompany, AccountStatus.DISABLED, "");

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, otherCompany)
        );
        Marketplace(_marketplace).resolveCounterOffer(dealId, true);
    }

    /*//////////////////////////////////////////////////////////////
                            DEAL VALIDATION
    //////////////////////////////////////////////////////////////*/
    function test_resolvePayment_paid_success() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            dealId, _getDeal(dealId).offerId, uint8(DealStatus.PAID), uint8(_getDeal(dealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.PaymentResolved(dealId, true, _paymentProvider);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);
    }

    function test_resolvePayment_paid_reverts_unauthorizedPaymentHandler() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(Ownable.Unauthorized.selector);
        Marketplace(_marketplace).resolvePayment(dealId, true);
    }

    function test_resolvePayment_paid_reverts_invalidStatus() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        // Mark as paid first
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);

        // Try to mark as paid again
        vm.prank(_paymentProvider);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(DealStatus.PAID)));
        Marketplace(_marketplace).resolvePayment(dealId, true);
    }

    function test_resolvePayment_unpaid_success() public returns (uint256 dealId, address otherCompany) {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        otherCompany = _createAndRegisterOtherCompany();
        dealId = _acceptOffer(offerId, 1000, otherCompany);

        _warpPastPaymentDeadline(dealId);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            dealId, _getDeal(dealId).offerId, uint8(DealStatus.UNPAID), uint8(_getDeal(dealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.PaymentResolved(dealId, false, _paymentProvider);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);
    }

    function test_resolvePayment_unpaid_reverts_invalidStatus() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        // Mark as paid first
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);

        // Try to mark as not paid
        vm.prank(_paymentProvider);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(DealStatus.PAID)));
        Marketplace(_marketplace).resolvePayment(dealId, false);
    }

    function test_resolvePayment_unpaid_reverts_dealNotExpired() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        vm.prank(_paymentProvider);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DealNotExpired.selector));
        Marketplace(_marketplace).resolvePayment(dealId, false);
    }

    function test_resolvePayment_paid_reverts_paymentDeadlineExpired() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);
        Deal memory deal = _getDeal(dealId);

        vm.warp(deal.paymentDeadline + 1);

        vm.prank(_paymentProvider);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__PaymentDeadlineExpired.selector));
        Marketplace(_marketplace).resolvePayment(dealId, true);
    }

    function test_resolvePayment_paid_success_atDeadlineBoundary() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);
        Deal memory deal = _getDeal(dealId);

        vm.warp(deal.paymentDeadline);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);
    }

    function test_resolvePayment_paid_success_fromUnpaidAfterDeadline() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);
        Deal memory deal = _getDeal(dealId);

        vm.warp(deal.paymentDeadline + 1);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            dealId, _getDeal(dealId).offerId, uint8(DealStatus.PAID), uint8(_getDeal(dealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.PaymentResolved(dealId, true, _paymentProvider);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);
    }

    function test_resolvePayment_paid_reverts_dealAlreadyArbitrated() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);
        Deal memory deal = _getDeal(dealId);

        vm.warp(deal.paymentDeadline + 1);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        vm.prank(otherCompany);
        Marketplace(_marketplace).initiateDispute(dealId);

        vm.prank(_arbitrator);
        Marketplace(_marketplace).resolveDispute(dealId, DealStatus.UNPAID);

        vm.prank(_paymentProvider);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DealAlreadyArbitrated.selector));
        Marketplace(_marketplace).resolvePayment(dealId, true);
    }

    function test_resolvePayment_unpaid_reverts_atDeadlineBoundary() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);
        Deal memory deal = _getDeal(dealId);

        vm.warp(deal.paymentDeadline);

        vm.prank(makeAddr("anyone"));
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DealNotExpired.selector));
        Marketplace(_marketplace).resolvePayment(dealId, false);
    }

    function test_resolvePayment_unpaid_success_anyoneAfterDeadline() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);
        Deal memory deal = _getDeal(dealId);

        vm.warp(deal.paymentDeadline + 1);

        vm.prank(makeAddr("anyone"));
        Marketplace(_marketplace).resolvePayment(dealId, false);
    }

    function test_resolvePayment_paid_success_fromUnpaidStatus() public {
        // PREPARE: create a deal and mark as unpaid
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        _warpPastPaymentDeadline(dealId);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        // ACT: PAYMENT_HANDLER overrides UNPAID → PAID (late payment confirmation)
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);

        // ASSERT
        Deal memory updatedDeal = _getDeal(dealId);
        assertEq(uint8(updatedDeal.status), uint8(DealStatus.PAID));
    }

    function test_resolvePayment_paid_reverts_dealAlreadyArbitrated_afterUnpaidResolution() public {
        // PREPARE: create deal → unpaid → dispute → arbitrator resolves as UNPAID
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        _warpPastPaymentDeadline(dealId);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        vm.prank(otherCompany);
        Marketplace(_marketplace).initiateDispute(dealId);

        vm.prank(_arbitrator);
        Marketplace(_marketplace).resolveDispute(dealId, DealStatus.UNPAID);

        // ACT: PAYMENT_HANDLER cannot override arbitrator's decision
        vm.prank(_paymentProvider);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DealAlreadyArbitrated.selector));
        Marketplace(_marketplace).resolvePayment(dealId, true);
    }

    function test_resolvePayment_paid_reverts_dealInDispute() public {
        // PREPARE: create deal → unpaid → dispute initiated
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        _warpPastPaymentDeadline(dealId);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        vm.prank(otherCompany);
        Marketplace(_marketplace).initiateDispute(dealId);

        // ACT: PAYMENT_HANDLER cannot mark as paid while in dispute
        vm.prank(_paymentProvider);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(DealStatus.IN_DISPUTE))
        );
        Marketplace(_marketplace).resolvePayment(dealId, true);
    }

    function test_resolvePayment_paid_reverts_dealAlreadySettled() public {
        // PREPARE: create deal → paid → settled
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);
        Marketplace(_marketplace).settleDeal(dealId);

        // ACT: PAYMENT_HANDLER cannot mark as paid after settlement
        vm.prank(_paymentProvider);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(DealStatus.SUCCESSFUL))
        );
        Marketplace(_marketplace).resolvePayment(dealId, true);
    }

    function test_resolvePayments_success_mixedPaidAndUnpaid() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 correctedDealId = _acceptOffer(offerId, 1000, buyer);
        uint256 unpaidDealId = _acceptOffer(offerId, 1000, buyer);
        Deal memory correctedDeal = _getDeal(correctedDealId);

        vm.warp(correctedDeal.paymentDeadline + 1);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(correctedDealId, false);

        PaymentResolutionInput[] memory resolutions = new PaymentResolutionInput[](2);
        resolutions[0] = _paymentResolution(correctedDealId, true);
        resolutions[1] = _paymentResolution(unpaidDealId, false);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            correctedDealId,
            _getDeal(correctedDealId).offerId,
            uint8(DealStatus.PAID),
            uint8(_getDeal(correctedDealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.PaymentResolved(correctedDealId, true, _paymentProvider);
        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            unpaidDealId, _getDeal(unpaidDealId).offerId, uint8(DealStatus.UNPAID), uint8(_getDeal(unpaidDealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.PaymentResolved(unpaidDealId, false, _paymentProvider);
        vm.expectEmit();
        emit IMarketplace.PaymentResolutionsBatchProcessed(_paymentProvider, 2, 2, 0);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayments(resolutions);

        assertEq(uint8(_getDeal(correctedDealId).status), uint8(DealStatus.PAID));
        assertEq(uint8(_getDeal(unpaidDealId).status), uint8(DealStatus.UNPAID));
    }

    function test_resolvePayments_success_skipsFailureAndContinues() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 expiredPendingDealId = _acceptOffer(offerId, 1000, buyer);
        uint256 correctedDealId = _acceptOffer(offerId, 1000, buyer);
        uint256 unpaidDealId = _acceptOffer(offerId, 1000, buyer);
        Deal memory expiredPendingDeal = _getDeal(expiredPendingDealId);

        vm.warp(expiredPendingDeal.paymentDeadline + 1);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(correctedDealId, false);

        PaymentResolutionInput[] memory resolutions = new PaymentResolutionInput[](3);
        resolutions[0] = _paymentResolution(expiredPendingDealId, true);
        resolutions[1] = _paymentResolution(correctedDealId, true);
        resolutions[2] = _paymentResolution(unpaidDealId, false);
        bytes memory expectedFailure = abi.encodeWithSelector(Errors.Marketplace__PaymentDeadlineExpired.selector);

        vm.expectEmit();
        emit IMarketplace.PaymentResolutionSkipped(expiredPendingDealId, true, _paymentProvider, expectedFailure);
        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            correctedDealId,
            _getDeal(correctedDealId).offerId,
            uint8(DealStatus.PAID),
            uint8(_getDeal(correctedDealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.PaymentResolved(correctedDealId, true, _paymentProvider);
        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            unpaidDealId, _getDeal(unpaidDealId).offerId, uint8(DealStatus.UNPAID), uint8(_getDeal(unpaidDealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.PaymentResolved(unpaidDealId, false, _paymentProvider);
        vm.expectEmit();
        emit IMarketplace.PaymentResolutionsBatchProcessed(_paymentProvider, 3, 2, 1);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayments(resolutions);

        assertEq(uint8(_getDeal(expiredPendingDealId).status), uint8(DealStatus.PENDING));
        assertEq(uint8(_getDeal(correctedDealId).status), uint8(DealStatus.PAID));
        assertEq(uint8(_getDeal(unpaidDealId).status), uint8(DealStatus.UNPAID));
    }

    function test_resolvePayments_reverts_unauthorizedWhenAnyPaidResolutionIncluded() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 unpaidDealId = _acceptOffer(offerId, 1000, buyer);
        uint256 paidDealId = _acceptOffer(offerId, 1000, buyer);
        Deal memory unpaidDeal = _getDeal(unpaidDealId);

        vm.warp(unpaidDeal.paymentDeadline + 1);

        PaymentResolutionInput[] memory resolutions = new PaymentResolutionInput[](2);
        resolutions[0] = _paymentResolution(unpaidDealId, false);
        resolutions[1] = _paymentResolution(paidDealId, true);

        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(Ownable.Unauthorized.selector);
        Marketplace(_marketplace).resolvePayments(resolutions);

        assertEq(uint8(_getDeal(unpaidDealId).status), uint8(DealStatus.PENDING));
        assertEq(uint8(_getDeal(paidDealId).status), uint8(DealStatus.PENDING));
    }

    function test_resolvePayments_success_unpaidOnlyPermissionless() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 firstDealId = _acceptOffer(offerId, 1000, buyer);
        uint256 secondDealId = _acceptOffer(offerId, 1000, buyer);
        Deal memory firstDeal = _getDeal(firstDealId);

        vm.warp(firstDeal.paymentDeadline + 1);

        PaymentResolutionInput[] memory resolutions = new PaymentResolutionInput[](2);
        resolutions[0] = _paymentResolution(firstDealId, false);
        resolutions[1] = _paymentResolution(secondDealId, false);

        address resolver = makeAddr("anyone");

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            firstDealId, _getDeal(firstDealId).offerId, uint8(DealStatus.UNPAID), uint8(_getDeal(firstDealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.PaymentResolved(firstDealId, false, resolver);
        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            secondDealId, _getDeal(secondDealId).offerId, uint8(DealStatus.UNPAID), uint8(_getDeal(secondDealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.PaymentResolved(secondDealId, false, resolver);
        vm.expectEmit();
        emit IMarketplace.PaymentResolutionsBatchProcessed(resolver, 2, 2, 0);

        vm.prank(resolver);
        Marketplace(_marketplace).resolvePayments(resolutions);

        assertEq(uint8(_getDeal(firstDealId).status), uint8(DealStatus.UNPAID));
        assertEq(uint8(_getDeal(secondDealId).status), uint8(DealStatus.UNPAID));
    }

    function test_resolvePayments_success_duplicateDealIdsProcessInOrder() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, buyer);
        Deal memory deal = _getDeal(dealId);

        vm.warp(deal.paymentDeadline + 1);

        PaymentResolutionInput[] memory resolutions = new PaymentResolutionInput[](2);
        resolutions[0] = _paymentResolution(dealId, false);
        resolutions[1] = _paymentResolution(dealId, false);

        address resolver = makeAddr("anyone");
        bytes memory expectedFailure =
            abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(DealStatus.UNPAID));

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            dealId, _getDeal(dealId).offerId, uint8(DealStatus.UNPAID), uint8(_getDeal(dealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.PaymentResolved(dealId, false, resolver);
        vm.expectEmit();
        emit IMarketplace.PaymentResolutionSkipped(dealId, false, resolver, expectedFailure);
        vm.expectEmit();
        emit IMarketplace.PaymentResolutionsBatchProcessed(resolver, 2, 1, 1);

        vm.prank(resolver);
        Marketplace(_marketplace).resolvePayments(resolutions);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.UNPAID));
    }

    function test_resolvePayments_success_emptyBatch() public {
        PaymentResolutionInput[] memory resolutions = new PaymentResolutionInput[](0);
        address resolver = makeAddr("anyone");

        vm.expectEmit();
        emit IMarketplace.PaymentResolutionsBatchProcessed(resolver, 0, 0, 0);

        vm.prank(resolver);
        Marketplace(_marketplace).resolvePayments(resolutions);
    }

    function test_resolvePaymentBatchItem_reverts_directExternalCall() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, buyer);

        address caller = makeAddr("directBatchHelperCaller");

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, caller));
        Marketplace(_marketplace).resolvePaymentBatchItem(dealId, true, caller);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.PENDING));
    }

    function test_resolvePayments_success_whenDealAndParentOfferFrozen() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, buyer);

        vm.startPrank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);
        Marketplace(_marketplace).setDealFrozen(dealId, true);
        vm.stopPrank();

        PaymentResolutionInput[] memory resolutions = new PaymentResolutionInput[](1);
        resolutions[0] = _paymentResolution(dealId, true);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            dealId, _getDeal(dealId).offerId, uint8(DealStatus.PAID), uint8(_getDeal(dealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.PaymentResolved(dealId, true, _paymentProvider);
        vm.expectEmit();
        emit IMarketplace.PaymentResolutionsBatchProcessed(_paymentProvider, 1, 1, 0);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayments(resolutions);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.PAID));
    }

    /*//////////////////////////////////////////////////////////////
                                DISPUTE
    //////////////////////////////////////////////////////////////*/
    function test_initiateDispute_success() public returns (uint256) {
        (uint256 dealId, address otherCompany) = test_resolvePayment_unpaid_success();

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            dealId, _getDeal(dealId).offerId, uint8(DealStatus.IN_DISPUTE), uint8(_getDeal(dealId).status)
        );

        vm.prank(otherCompany);
        Marketplace(_marketplace).initiateDispute(dealId);

        return dealId;
    }

    function test_initiateDispute_reverts_unauthorizedBuyer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        // Mark as not paid
        _warpPastPaymentDeadline(dealId);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, makeAddr("unauthorized")));
        Marketplace(_marketplace).initiateDispute(dealId);
    }

    function test_initiateDispute_reverts_whenBuyerDisabled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        _warpPastPaymentDeadline(dealId);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(otherCompany, AccountStatus.DISABLED, "");

        vm.prank(otherCompany);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, otherCompany));
        Marketplace(_marketplace).initiateDispute(dealId);
    }

    function test_initiateDispute_reverts_invalidStatus() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(DealStatus.PENDING)));
        vm.prank(otherCompany);
        Marketplace(_marketplace).initiateDispute(dealId);
    }

    function test_initiateDispute_reverts_disputePeriodExpired() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        // Mark as not paid
        _warpPastPaymentDeadline(dealId);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        // Warp past dispute buffer period
        Deal memory deal = _getDeal(dealId);
        vm.warp(deal.disputeBuffer + 1);

        vm.prank(otherCompany);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DisputePeriodExpired.selector));
        Marketplace(_marketplace).initiateDispute(dealId);
    }

    function test_resolveDispute_success() public {
        uint256 dealId = test_initiateDispute_success();

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            dealId, _getDeal(dealId).offerId, uint8(DealStatus.PAID), uint8(_getDeal(dealId).status)
        );

        vm.prank(_arbitrator);
        Marketplace(_marketplace).resolveDispute(dealId, DealStatus.PAID);
    }

    function test_resolveDispute_reverts_unauthorizedArbitrator() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        // Mark as not paid and initiate dispute
        _warpPastPaymentDeadline(dealId);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);
        vm.prank(otherCompany);
        Marketplace(_marketplace).initiateDispute(dealId);

        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(Ownable.Unauthorized.selector);
        Marketplace(_marketplace).resolveDispute(dealId, DealStatus.PAID);
    }

    function test_resolveDispute_reverts_invalidStatus() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        vm.prank(_arbitrator);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DealNotInDispute.selector));
        Marketplace(_marketplace).resolveDispute(dealId, DealStatus.PAID);
    }

    function test_resolveDispute_reverts_invalidResolution() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        // Mark as not paid and initiate dispute
        _warpPastPaymentDeadline(dealId);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);
        vm.prank(otherCompany);
        Marketplace(_marketplace).initiateDispute(dealId);

        vm.prank(_arbitrator);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(DealStatus.PENDING)));
        Marketplace(_marketplace).resolveDispute(dealId, DealStatus.PENDING);
    }

    /*//////////////////////////////////////////////////////////////
                               SETTLEMENT
    //////////////////////////////////////////////////////////////*/
    function test_settleDeal_success() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);

        vm.expectEmit();
        emit IEscrowManager.Claimed(offerId, otherCompany, 1000, _tokenAddr, _bondFTId, AssetType.ERC6909);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            dealId, _getDeal(dealId).offerId, uint8(DealStatus.SUCCESSFUL), uint8(_getDeal(dealId).status)
        );

        vm.expectEmit();
        emit IMarketplace.AmountsUpdated(offerId, 9000, 0, 1000);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).settleDeal(dealId);
    }

    function test_settleDeal_success_unpaidMarksUnsuccessful() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        Deal memory unpaidDeal = _getDeal(dealId);
        vm.warp(unpaidDeal.paymentDeadline + 1);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        unpaidDeal = _getDeal(dealId);
        vm.warp(unpaidDeal.disputeBuffer + 1);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            dealId, _getDeal(dealId).offerId, uint8(DealStatus.UNSUCCESSFUL), uint8(_getDeal(dealId).status)
        );

        vm.expectEmit();
        emit IMarketplace.AmountsUpdated(offerId, BOND_MAX_SUPPLY, 0, 0);

        Marketplace(_marketplace).settleDeal(dealId);

        Offer memory offer = _getOffer(offerId);
        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.UNSUCCESSFUL));
        assertEq(offer.amounts.available, BOND_MAX_SUPPLY);
        assertEq(offer.amounts.inDeals, 0);
        assertEq(offer.amounts.sold, 0);
        assertEq(DEUSSToken(_tokenAddr).balanceOf(otherCompany, _bondFTId), 0);
    }

    function test_settleDeals_success_paidAndUnpaidBatch() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address firstBuyer = _createAndRegisterOtherCompany();
        (address secondBuyer,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("settleBatchSecondBuyer"));

        uint256 paidDealId = _acceptOffer(offerId, 1000, firstBuyer);
        uint256 unpaidDealId = _acceptOffer(offerId, 1000, secondBuyer);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(paidDealId, true);

        Deal memory unpaidDeal = _getDeal(unpaidDealId);
        vm.warp(unpaidDeal.paymentDeadline + 1);
        Marketplace(_marketplace).resolvePayment(unpaidDealId, false);

        unpaidDeal = _getDeal(unpaidDealId);
        vm.warp(unpaidDeal.disputeBuffer + 1);

        uint256[] memory dealIds = new uint256[](2);
        dealIds[0] = paidDealId;
        dealIds[1] = unpaidDealId;

        Marketplace(_marketplace).settleDeals(dealIds);

        Offer memory offer = _getOffer(offerId);
        assertEq(uint8(_getDeal(paidDealId).status), uint8(DealStatus.SUCCESSFUL));
        assertEq(uint8(_getDeal(unpaidDealId).status), uint8(DealStatus.UNSUCCESSFUL));
        assertEq(offer.amounts.available, BOND_MAX_SUPPLY - 1000);
        assertEq(offer.amounts.inDeals, 0);
        assertEq(offer.amounts.sold, 1000);
        assertEq(DEUSSToken(_tokenAddr).balanceOf(firstBuyer, _bondFTId), 1000);
        assertEq(DEUSSToken(_tokenAddr).balanceOf(secondBuyer, _bondFTId), 0);
    }

    function test_settleDeals_success_skipsInvalidDeal() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 paidDealId = _acceptOffer(offerId, 1000, buyer);
        uint256 pendingDealId = _acceptOffer(offerId, 1000, buyer);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(paidDealId, true);

        uint256[] memory dealIds = new uint256[](2);
        dealIds[0] = paidDealId;
        dealIds[1] = pendingDealId;

        vm.expectEmit();
        emit IMarketplace.DealSettlementSkipped(
            pendingDealId,
            address(this),
            abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(DealStatus.PENDING))
        );
        vm.expectEmit();
        emit IMarketplace.DealSettlementsBatchProcessed(address(this), 2, 1, 1);

        Marketplace(_marketplace).settleDeals(dealIds);

        assertEq(uint8(_getDeal(paidDealId).status), uint8(DealStatus.SUCCESSFUL));
        assertEq(uint8(_getDeal(pendingDealId).status), uint8(DealStatus.PENDING));
    }

    function test_settleDeals_success_skipsDisabledPaidBuyer() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        address disabledBuyer = makeAddr("settleBatchDisabledBuyer");
        _createAndRegisterEntityWallet(_entityRegistryAdmin, disabledBuyer);
        uint256 paidDealId = _acceptOffer(offerId, 1000, buyer);
        uint256 disabledBuyerDealId = _acceptOffer(offerId, 1000, disabledBuyer);

        vm.startPrank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(paidDealId, true);
        Marketplace(_marketplace).resolvePayment(disabledBuyerDealId, true);
        vm.stopPrank();

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(disabledBuyer, AccountStatus.DISABLED, "disabled-before-batch-settlement");

        uint256[] memory dealIds = new uint256[](2);
        dealIds[0] = disabledBuyerDealId;
        dealIds[1] = paidDealId;

        vm.expectEmit();
        emit IMarketplace.DealSettlementSkipped(
            disabledBuyerDealId,
            address(this),
            abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, disabledBuyer)
        );
        vm.expectEmit();
        emit IMarketplace.DealSettlementsBatchProcessed(address(this), 2, 1, 1);

        Marketplace(_marketplace).settleDeals(dealIds);

        Offer memory offer = _getOffer(offerId);
        assertEq(uint8(_getDeal(disabledBuyerDealId).status), uint8(DealStatus.PAID));
        assertEq(uint8(_getDeal(paidDealId).status), uint8(DealStatus.SUCCESSFUL));
        assertEq(offer.amounts.available, BOND_MAX_SUPPLY - 2000);
        assertEq(offer.amounts.inDeals, 1000);
        assertEq(offer.amounts.sold, 1000);
        assertEq(DEUSSToken(_tokenAddr).balanceOf(disabledBuyer, _bondFTId), 0);
        assertEq(DEUSSToken(_tokenAddr).balanceOf(buyer, _bondFTId), 1000);
    }

    function test_settleDeals_success_emptyBatch() public {
        uint256[] memory dealIds = new uint256[](0);

        vm.expectEmit();
        emit IMarketplace.DealSettlementsBatchProcessed(address(this), 0, 0, 0);
        Marketplace(_marketplace).settleDeals(dealIds);
    }

    function test_settleDealBatchItem_reverts_directExternalCall() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, buyer);

        address caller = makeAddr("directSettleBatchHelperCaller");

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, caller));
        Marketplace(_marketplace).settleDealBatchItem(dealId);
    }

    function test_settleDeal_success_redemption() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();

        OfferInput memory offer = _createOfferInput();
        offer.saleMode = SaleMode.REDEMPTION;
        offer.allowCounterOffers = false;
        offer.allowedBuyers = _singletonBuyerArray(allowedBuyer);

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        vm.prank(allowedBuyer);
        uint256 dealId = Marketplace(_marketplace).acceptOffer(offerId, 1000);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).settleDeal(dealId);

        Deal memory updatedDeal = _getDeal(dealId);
        Offer memory updatedOffer = _getOffer(offerId);

        assertEq(uint8(updatedDeal.status), uint8(DealStatus.SUCCESSFUL));
        assertEq(updatedOffer.amounts.available, 9000);
        assertEq(updatedOffer.amounts.inDeals, 0);
        assertEq(updatedOffer.amounts.sold, 1000);
        assertEq(DEUSSToken(_tokenAddr).balanceOf(allowedBuyer, _bondFTId), 1000);
    }

    function test_settleDeal_reverts_invalidStatus() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(DealStatus.PENDING)));
        Marketplace(_marketplace).settleDeal(dealId);
    }

    function test_settleDeal_reverts_disputePeriodNotExpired() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, 1000, otherCompany);

        // Mark as not paid
        _warpPastPaymentDeadline(dealId);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DisputePeriodNotExpired.selector));
        Marketplace(_marketplace).settleDeal(dealId);
    }

    function test_settleDeal_reverts_whenDealPaidAndBuyerDisabled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 amount = 1000;
        uint256 dealId = _acceptOffer(offerId, amount, buyer);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);

        Offer memory offerBefore = _getOffer(offerId);
        Deal memory dealBefore = _getDeal(dealId);
        uint256 escrowId = _getEscrowIdByOfferId(offerId);
        uint256 escrowBefore = EscrowManager(_escrowManager).getEscrow(escrowId).amount;
        assertEq(uint8(dealBefore.status), uint8(DealStatus.PAID));
        assertEq(offerBefore.amounts.available, BOND_MAX_SUPPLY - amount);
        assertEq(offerBefore.amounts.inDeals, amount);
        assertEq(escrowBefore, BOND_MAX_SUPPLY);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(buyer, AccountStatus.DISABLED, "disabled-before-settlement");

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, buyer));
        Marketplace(_marketplace).settleDeal(dealId);

        Offer memory offerAfter = _getOffer(offerId);
        Deal memory dealAfter = _getDeal(dealId);
        uint256 escrowAfter = EscrowManager(_escrowManager).getEscrow(escrowId).amount;
        assertEq(uint8(dealAfter.status), uint8(DealStatus.PAID));
        assertEq(offerAfter.amounts.available, BOND_MAX_SUPPLY - amount);
        assertEq(offerAfter.amounts.inDeals, amount);
        assertEq(offerAfter.amounts.sold, 0);
        assertEq(escrowAfter, BOND_MAX_SUPPLY);
    }

    /*//////////////////////////////////////////////////////////////
                           COMBINED COUNTER TESTS
    //////////////////////////////////////////////////////////////*/
    function test_identifiers_success_incrementSeparately() public {
        // ARRANGE - Use smaller offer amounts so we can create two offers with available balance
        uint256 halfOfferAmount = (BOND_MAX_SUPPLY) / 2; // 5000 tokens per offer

        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);

        // Create first offer with half the normal amount
        OfferInput memory offer1 = _createOfferInput();
        offer1.totalAmount = halfOfferAmount;

        vm.prank(_company);
        uint256 offerId1 = Marketplace(_marketplace).registerOffer(offer1);

        assertEq(offerId1, 1);

        // ACT - Create deal on first offer
        address otherCompany = _createAndRegisterOtherCompany();
        uint256 dealId1 = _acceptOffer(offerId1, halfOfferAmount, otherCompany);

        assertEq(dealId1, 1);

        // ACT - Create second offer
        OfferInput memory offer2 = _createOfferInput();
        offer2.totalAmount = halfOfferAmount;

        vm.prank(_company);
        uint256 offerId2 = Marketplace(_marketplace).registerOffer(offer2);

        assertEq(offerId2, 2);

        // ACT - Create deal on second offer
        uint256 dealId2 = _acceptOffer(offerId2, 1000, otherCompany);

        assertEq(dealId2, 2);
    }

    /*//////////////////////////////////////////////////////////////
                    FREEZE – setOfferFrozen / setDealFrozen
    //////////////////////////////////////////////////////////////*/

    function test_setOfferFrozen_freezer_canFreezeAndUnfreeze() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();

        vm.startPrank(_freezer);
        vm.expectEmit();
        emit IMarketplace.OfferFrozenSet(offerId, true);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);
        assertTrue(_isOfferFrozen(offerId));

        vm.expectEmit();
        emit IMarketplace.OfferFrozenSet(offerId, false);
        Marketplace(_marketplace).setOfferFrozen(offerId, false);
        assertFalse(_isOfferFrozen(offerId));
        vm.stopPrank();
    }

    function test_setOfferFrozen_nonFreezer_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address nonFreezer = makeAddr("nobody");

        vm.prank(nonFreezer);
        vm.expectRevert(Ownable.Unauthorized.selector);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);
    }

    function test_setOfferFrozen_adminWithoutFreezeRole_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();

        vm.prank(_adminID);
        vm.expectRevert(Ownable.Unauthorized.selector);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);
    }

    function test_setOfferFrozen_nonExistentOffer_reverts() public {
        uint256 nonExistentOffer = 9999;

        vm.prank(_freezer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferDoesNotExist.selector, nonExistentOffer));
        Marketplace(_marketplace).setOfferFrozen(nonExistentOffer, true);
    }

    function test_setDealFrozen_freezer_canFreezeAndUnfreeze() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        vm.startPrank(_freezer);
        vm.expectEmit();
        emit IMarketplace.DealFrozenSet(dealId, true);
        Marketplace(_marketplace).setDealFrozen(dealId, true);
        assertTrue(_isDealFrozen(dealId));

        vm.expectEmit();
        emit IMarketplace.DealFrozenSet(dealId, false);
        Marketplace(_marketplace).setDealFrozen(dealId, false);
        assertFalse(_isDealFrozen(dealId));
        vm.stopPrank();
    }

    function test_setDealFrozen_nonFreezer_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);
        address nonFreezer = makeAddr("nobody");

        vm.prank(nonFreezer);
        vm.expectRevert(Ownable.Unauthorized.selector);
        Marketplace(_marketplace).setDealFrozen(dealId, true);
    }

    function test_setDealFrozen_adminWithoutFreezeRole_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        vm.prank(_adminID);
        vm.expectRevert(Ownable.Unauthorized.selector);
        Marketplace(_marketplace).setDealFrozen(dealId, true);
    }

    function test_setDealFrozen_nonExistentDeal_reverts() public {
        uint256 nonExistentDeal = 9999;

        vm.prank(_freezer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DealDoesNotExist.selector, nonExistentDeal));
        Marketplace(_marketplace).setDealFrozen(nonExistentDeal, true);
    }

    /*//////////////////////////////////////////////////////////////
                FROZEN OFFER BLOCKS NORMAL OFFER ACTIVITY
    //////////////////////////////////////////////////////////////*/

    function test_frozenOffer_blocks_acceptOffer() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        address buyer = _createAndRegisterOtherCompany();
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferFrozen.selector, offerId));
        Marketplace(_marketplace).acceptOffer(offerId, MIN_AMOUNT);
    }

    function test_frozenOffer_blocks_cancelOffer() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferFrozen.selector, offerId));
        Marketplace(_marketplace).cancelOffer(offerId);
    }

    function test_frozenOffer_blocks_withdrawAvailable() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();

        // Cancel first so withdrawAvailable precondition is met, then re-freeze
        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferFrozen.selector, offerId));
        Marketplace(_marketplace).withdrawAvailable(offerId);
    }

    function test_frozenOffer_blocks_createCounterOffer() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        address buyer = _createAndRegisterOtherCompany();
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferFrozen.selector, offerId));
        Marketplace(_marketplace)
            .createCounterOffer(
                CounterOfferInput({
                offerId: offerId, expiry: _counterOfferExpiry(), amount: MIN_AMOUNT, unitPrice: UNIT_PRICE
            })
            );
    }

    /*//////////////////////////////////////////////////////////////
        FROZEN DEAL / FROZEN PARENT OFFER BLOCKS DEAL ACTIVITY
    //////////////////////////////////////////////////////////////*/

    function test_frozenDeal_blocks_cancelCounterOffer() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, buyer);

        vm.prank(_freezer);
        Marketplace(_marketplace).setDealFrozen(dealId, true);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DealFrozen.selector, dealId));
        Marketplace(_marketplace).cancelCounterOffer(dealId);
    }

    function test_frozenParentOffer_blocks_cancelCounterOffer() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, buyer);

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferFrozen.selector, offerId));
        Marketplace(_marketplace).cancelCounterOffer(dealId);
    }

    function test_frozenDeal_blocks_resolveCounterOffer() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, buyer);

        vm.prank(_freezer);
        Marketplace(_marketplace).setDealFrozen(dealId, true);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DealFrozen.selector, dealId));
        Marketplace(_marketplace).resolveCounterOffer(dealId, true);
    }

    function test_frozenOffer_blocks_resolveCounterOffer() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, buyer);

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferFrozen.selector, offerId));
        Marketplace(_marketplace).resolveCounterOffer(dealId, true);
    }

    // Option 1: resolvePayment is allowed while deal or parent offer is frozen
    function test_frozenDeal_allows_resolvePayment() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        vm.prank(_freezer);
        Marketplace(_marketplace).setDealFrozen(dealId, true);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.PAID));
    }

    function test_frozenParentOffer_allows_resolvePayment() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.PAID));
    }

    function test_frozenDeal_allows_initiateDispute() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        Deal memory deal = _getDeal(dealId);
        vm.warp(deal.paymentDeadline + 1);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        vm.prank(_freezer);
        Marketplace(_marketplace).setDealFrozen(dealId, true);

        vm.prank(buyer);
        Marketplace(_marketplace).initiateDispute(dealId);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.IN_DISPUTE));
    }

    function test_frozenDeal_allows_resolveDispute() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        Deal memory deal = _getDeal(dealId);
        vm.warp(deal.paymentDeadline + 1);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);
        vm.prank(buyer);
        Marketplace(_marketplace).initiateDispute(dealId);

        vm.prank(_freezer);
        Marketplace(_marketplace).setDealFrozen(dealId, true);

        vm.prank(_arbitrator);
        Marketplace(_marketplace).resolveDispute(dealId, DealStatus.PAID);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.PAID));
    }

    function test_frozenDeal_blocks_settleDeal() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);

        vm.prank(_freezer);
        Marketplace(_marketplace).setDealFrozen(dealId, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DealFrozen.selector, dealId));
        Marketplace(_marketplace).settleDeal(dealId);
    }

    function test_frozenParentOffer_blocks_settleDeal() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferFrozen.selector, offerId));
        Marketplace(_marketplace).settleDeal(dealId);
    }

    /*//////////////////////////////////////////////////////////////
                    seizeOfferEscrow – access control
    //////////////////////////////////////////////////////////////*/

    function test_seizeOfferEscrow_nonSeizureRole_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.prank(makeAddr("nobody"));
        vm.expectRevert(Ownable.Unauthorized.selector);
        Marketplace(_marketplace).seizeOfferEscrow(offerId, _company, keccak256("REASON"));
    }

    /*//////////////////////////////////////////////////////////////
                seizeOfferEscrow – validation reverts
    //////////////////////////////////////////////////////////////*/

    function test_seizeOfferEscrow_nonExistentOffer_reverts() public {
        uint256 nonExistentOffer = 9999;
        vm.prank(_deployer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferDoesNotExist.selector, nonExistentOffer));
        Marketplace(_marketplace).seizeOfferEscrow(nonExistentOffer, _company, keccak256("REASON"));
    }

    function test_seizeOfferEscrow_unfrozenOffer_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();

        vm.prank(_deployer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferNotFrozen.selector, offerId));
        Marketplace(_marketplace).seizeOfferEscrow(offerId, _company, keccak256("REASON"));
    }

    function test_seizeOfferEscrow_zeroBeneficiary_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.prank(_deployer);
        vm.expectRevert(Errors.ZeroAddress.selector);
        Marketplace(_marketplace).seizeOfferEscrow(offerId, address(0), keccak256("REASON"));
    }

    function test_seizeOfferEscrow_zeroReason_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address beneficiary = _createAndRegisterOtherCompany();

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.prank(_deployer);
        vm.expectRevert(Errors.Marketplace__ZeroReason.selector);
        Marketplace(_marketplace).seizeOfferEscrow(offerId, beneficiary, bytes32(0));
    }

    function test_seizeOfferEscrow_reverts_disabledBeneficiary() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address beneficiary = _createAndRegisterOtherCompany();

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(beneficiary, AccountStatus.DISABLED, "beneficiary disabled");

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.prank(_deployer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, beneficiary)
        );
        Marketplace(_marketplace).seizeOfferEscrow(offerId, beneficiary, keccak256("REASON"));
    }

    function test_seizeOfferEscrow_success_beneficiaryEntityTypeNotAllowed() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        uint256 totalAmount = BOND_MAX_SUPPLY;
        uint256 escrowId = _getEscrowIdByOfferId(offerId);
        uint256 escrowBefore = EscrowManager(_escrowManager).getEscrow(escrowId).amount;
        address beneficiary = _createAndRegisterWalletForType(NATURAL_PERSON_ENTITY, "seizureNaturalPerson");
        bytes32 reason = keccak256("SEIZURE");

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.expectEmit();
        emit IMarketplace.OfferEscrowSeized(offerId, beneficiary, totalAmount, reason, _deployer);

        vm.prank(_deployer);
        Marketplace(_marketplace).seizeOfferEscrow(offerId, beneficiary, reason);

        Offer memory offer = _getOffer(offerId);
        assertEq(offer.amounts.available, 0);
        assertTrue(_isOfferCancelled(offerId));
        assertEq(EscrowManager(_escrowManager).getEscrow(escrowId).amount, escrowBefore - totalAmount);
    }

    function test_seizeOfferEscrow_zeroAvailable_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        uint256 totalAmount = BOND_MAX_SUPPLY;
        address buyer = _createAndRegisterOtherCompany();
        _acceptOffer(offerId, totalAmount, buyer); // available becomes 0

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        address beneficiary = _createAndRegisterOtherCompany();
        vm.prank(_deployer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NoAvailableAmount.selector, offerId));
        Marketplace(_marketplace).seizeOfferEscrow(offerId, beneficiary, keccak256("REASON"));
    }

    /*//////////////////////////////////////////////////////////////
                    seizeOfferEscrow – success
    //////////////////////////////////////////////////////////////*/

    function test_seizeOfferEscrow_success_fullAvailable() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        uint256 totalAmount = BOND_MAX_SUPPLY;
        uint256 escrowId = _getEscrowIdByOfferId(offerId);
        uint256 escrowBefore = EscrowManager(_escrowManager).getEscrow(escrowId).amount;

        address beneficiary = _createAndRegisterOtherCompany();
        bytes32 reason = keccak256("SEIZURE");

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.expectEmit();
        emit IMarketplace.OfferCancelled(offerId, _deployer);
        vm.expectEmit();
        emit IMarketplace.AmountsUpdated(offerId, 0, 0, 0);
        vm.expectEmit();
        emit IMarketplace.OfferEscrowSeized(offerId, beneficiary, totalAmount, reason, _deployer);

        vm.prank(_deployer);
        Marketplace(_marketplace).seizeOfferEscrow(offerId, beneficiary, reason);

        Offer memory offer = _getOffer(offerId);
        assertEq(offer.amounts.available, 0);
        assertEq(offer.amounts.inDeals, 0);
        assertEq(offer.amounts.sold, 0);
        assertTrue(_isOfferCancelled(offerId));
        assertEq(EscrowManager(_escrowManager).getEscrow(escrowId).amount, escrowBefore - totalAmount);
    }

    function test_seizeOfferEscrow_success_partialAvailable() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        uint256 totalAmount = BOND_MAX_SUPPLY;
        uint256 dealAmount = MIN_AMOUNT;
        address buyer = _createAndRegisterOtherCompany();
        _acceptOffer(offerId, dealAmount, buyer);
        uint256 expectedSeized = totalAmount - dealAmount;

        address beneficiary = _createAndRegisterOtherCompany();
        bytes32 reason = keccak256("SEIZURE");

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.expectEmit();
        emit IMarketplace.OfferEscrowSeized(offerId, beneficiary, expectedSeized, reason, _deployer);

        vm.prank(_deployer);
        Marketplace(_marketplace).seizeOfferEscrow(offerId, beneficiary, reason);

        Offer memory offer = _getOffer(offerId);
        assertEq(offer.amounts.available, 0);
        assertEq(offer.amounts.inDeals, dealAmount); // inDeals untouched
        assertEq(offer.amounts.sold, 0); // sold untouched
    }

    /*//////////////////////////////////////////////////////////////
                    seizeDeal – access control
    //////////////////////////////////////////////////////////////*/

    function test_seizeDeal_nonSeizureRole_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        vm.startPrank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);
        Marketplace(_marketplace).setDealFrozen(dealId, true);
        vm.stopPrank();

        vm.prank(makeAddr("nobody"));
        vm.expectRevert(Ownable.Unauthorized.selector);
        Marketplace(_marketplace).seizeDeal(dealId, buyer, keccak256("REASON"));
    }

    /*//////////////////////////////////////////////////////////////
                seizeDeal – validation reverts
    //////////////////////////////////////////////////////////////*/

    function test_seizeDeal_nonExistentDeal_reverts() public {
        uint256 nonExistentDeal = 9999;
        vm.prank(_deployer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DealDoesNotExist.selector, nonExistentDeal));
        Marketplace(_marketplace).seizeDeal(nonExistentDeal, _company, keccak256("REASON"));
    }

    function test_seizeDeal_unfrozenDeal_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true); // offer frozen, deal NOT frozen

        vm.prank(_deployer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DealNotFrozen.selector, dealId));
        Marketplace(_marketplace).seizeDeal(dealId, buyer, keccak256("REASON"));
    }

    function test_seizeDeal_unfrozenParentOffer_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        vm.prank(_freezer);
        Marketplace(_marketplace).setDealFrozen(dealId, true); // deal frozen, offer NOT frozen

        vm.prank(_deployer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferNotFrozen.selector, offerId));
        Marketplace(_marketplace).seizeDeal(dealId, buyer, keccak256("REASON"));
    }

    function test_seizeDeal_zeroBeneficiary_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        vm.startPrank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);
        Marketplace(_marketplace).setDealFrozen(dealId, true);
        vm.stopPrank();

        vm.prank(_deployer);
        vm.expectRevert(Errors.ZeroAddress.selector);
        Marketplace(_marketplace).seizeDeal(dealId, address(0), keccak256("REASON"));
    }

    function test_seizeDeal_zeroReason_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);
        address beneficiary = _createAndRegisterOtherCompany();

        vm.startPrank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);
        Marketplace(_marketplace).setDealFrozen(dealId, true);
        vm.stopPrank();

        vm.prank(_deployer);
        vm.expectRevert(Errors.Marketplace__ZeroReason.selector);
        Marketplace(_marketplace).seizeDeal(dealId, beneficiary, bytes32(0));
    }

    function test_seizeDeal_reverts_disabledBeneficiary() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);
        address beneficiary = _createAndRegisterOtherCompany();

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(beneficiary, AccountStatus.DISABLED, "beneficiary disabled");

        vm.startPrank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);
        Marketplace(_marketplace).setDealFrozen(dealId, true);
        vm.stopPrank();

        vm.prank(_deployer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, beneficiary)
        );
        Marketplace(_marketplace).seizeDeal(dealId, beneficiary, keccak256("REASON"));
    }

    function test_seizeDeal_success_beneficiaryEntityTypeNotAllowed() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);
        address beneficiary = _createAndRegisterWalletForType(NATURAL_PERSON_ENTITY, "seizureDealNaturalPerson");

        _assertSeizeDealSuccess(offerId, dealId, beneficiary, DealStatus.PENDING);
    }

    function test_seizeDeal_invalidStatus_CANCELLED_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        // Create a counter offer and cancel it to produce a CANCELLED deal
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, buyer);
        vm.prank(buyer);
        Marketplace(_marketplace).cancelCounterOffer(dealId);

        vm.startPrank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);
        Marketplace(_marketplace).setDealFrozen(dealId, true);
        vm.stopPrank();

        vm.prank(_deployer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(DealStatus.CANCELLED)));
        Marketplace(_marketplace).seizeDeal(dealId, buyer, keccak256("REASON"));
    }

    function test_seizeDeal_invalidStatus_SUCCESSFUL_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);
        Marketplace(_marketplace).settleDeal(dealId);

        vm.startPrank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);
        Marketplace(_marketplace).setDealFrozen(dealId, true);
        vm.stopPrank();

        vm.prank(_deployer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(DealStatus.SUCCESSFUL))
        );
        Marketplace(_marketplace).seizeDeal(dealId, buyer, keccak256("REASON"));
    }

    function test_seizeDeal_invalidStatus_UNSUCCESSFUL_reverts() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        Deal memory deal = _getDeal(dealId);
        vm.warp(deal.paymentDeadline + 1);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        deal = _getDeal(dealId);
        vm.warp(deal.disputeBuffer + 1);
        Marketplace(_marketplace).settleDeal(dealId);

        vm.startPrank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);
        Marketplace(_marketplace).setDealFrozen(dealId, true);
        vm.stopPrank();

        vm.prank(_deployer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__InvalidStatus.selector, uint8(DealStatus.UNSUCCESSFUL))
        );
        Marketplace(_marketplace).seizeDeal(dealId, buyer, keccak256("REASON"));
    }

    /*//////////////////////////////////////////////////////////////
            seizeDeal – success for all seizable statuses
    //////////////////////////////////////////////////////////////*/

    function test_seizeDeal_success_statusPENDING() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);
        address beneficiary = _createAndRegisterOtherCompany();

        _assertSeizeDealSuccess(offerId, dealId, beneficiary, DealStatus.PENDING);
    }

    function test_seizeDeal_success_statusPAID() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);
        address beneficiary = _createAndRegisterOtherCompany();

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);

        _assertSeizeDealSuccess(offerId, dealId, beneficiary, DealStatus.PAID);
    }

    function test_seizeDeal_success_statusUNPAID() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);
        address beneficiary = _createAndRegisterOtherCompany();

        Deal memory deal = _getDeal(dealId);
        vm.warp(deal.paymentDeadline + 1);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        _assertSeizeDealSuccess(offerId, dealId, beneficiary, DealStatus.UNPAID);
    }

    function test_seizeDeal_success_statusIN_DISPUTE() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);
        address beneficiary = _createAndRegisterOtherCompany();

        Deal memory deal = _getDeal(dealId);
        vm.warp(deal.paymentDeadline + 1);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);
        vm.prank(buyer);
        Marketplace(_marketplace).initiateDispute(dealId);

        _assertSeizeDealSuccess(offerId, dealId, beneficiary, DealStatus.IN_DISPUTE);
    }

    /*//////////////////////////////////////////////////////////////
              REGRESSION – non-frozen flows remain unchanged
    //////////////////////////////////////////////////////////////*/

    function test_regression_normalAcceptAndSettle_unfrozenOffer() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        assertFalse(_isOfferFrozen(offerId));

        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);
        assertFalse(_isDealFrozen(dealId));

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, true);
        Marketplace(_marketplace).settleDeal(dealId);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));
    }

    function test_regression_SEIZED_enum_doesNotShiftExistingValues() public pure {
        assertEq(uint8(DealStatus.NON_EXISTING), 0);
        assertEq(uint8(DealStatus.PENDING), 1);
        assertEq(uint8(DealStatus.PAID), 2);
        assertEq(uint8(DealStatus.UNPAID), 3);
        assertEq(uint8(DealStatus.CANCELLED), 4);
        assertEq(uint8(DealStatus.IN_DISPUTE), 5);
        assertEq(uint8(DealStatus.PROPOSED), 6);
        assertEq(uint8(DealStatus.DECLINED), 7);
        assertEq(uint8(DealStatus.SUCCESSFUL), 8);
        assertEq(uint8(DealStatus.UNSUCCESSFUL), 9);
        assertEq(uint8(DealStatus.SEIZED), 10);
    }

    /*//////////////////////////////////////////////////////////////
        FREEZE – blocks interest-discovery entry points (Option 1)
    //////////////////////////////////////////////////////////////*/

    function test_frozenOffer_blocks_expressInterest() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.prank(investor);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferFrozen.selector, offerId));
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);
    }

    function test_cancelledOffer_blocks_expressInterest() public {
        // An INTEREST_DISCOVERY offer becomes cancelled after seizeOfferEscrow.
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);
        vm.prank(_deployer);
        Marketplace(_marketplace).seizeOfferEscrow(offerId, investor, keccak256("REASON"));

        // Offer is now cancelled; expressInterest must revert even after unfreeze.
        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, false);

        vm.prank(investor);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferAlreadyCancelled.selector, offerId));
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);
    }

    function test_frozenOffer_blocks_activateInterest() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.prank(investor);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferFrozen.selector, offerId));
        Marketplace(_marketplace).activateInterest(interestId);
    }

    function test_cancelledOffer_blocks_activateInterest() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 reserveAmount = MIN_AMOUNT;
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(reserveAmount);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, reserveAmount);

        // Seize remaining available (totalUnits - reserveAmount). This also cancels the offer and
        // zeroes reservedInterestUnits, but the interest record still shows EXPRESSED.
        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);
        address beneficiary = _createAndRegisterOtherCompany();
        vm.prank(_deployer);
        Marketplace(_marketplace).seizeOfferEscrow(offerId, beneficiary, keccak256("REASON"));

        // Offer is now cancelled; activateInterest must revert.
        vm.prank(investor);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferAlreadyCancelled.selector, offerId));
        Marketplace(_marketplace).activateInterest(interestId);
    }

    /*//////////////////////////////////////////////////////////////
      ALLOWED WHILE FROZEN – parent-offer-frozen variants (Option 1)
    //////////////////////////////////////////////////////////////*/

    function test_frozenParentOffer_allows_initiateDispute() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        Deal memory deal = _getDeal(dealId);
        vm.warp(deal.paymentDeadline + 1);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.prank(buyer);
        Marketplace(_marketplace).initiateDispute(dealId);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.IN_DISPUTE));
    }

    function test_frozenParentOffer_allows_resolveDispute() public {
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        Deal memory deal = _getDeal(dealId);
        vm.warp(deal.paymentDeadline + 1);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);
        vm.prank(buyer);
        Marketplace(_marketplace).initiateDispute(dealId);

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        vm.prank(_arbitrator);
        Marketplace(_marketplace).resolveDispute(dealId, DealStatus.PAID);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.PAID));
    }

    /*//////////////////////////////////////////////////////////////
        DEADLINE BEHAVIOR – freeze does NOT pause time (Option 1)
    //////////////////////////////////////////////////////////////*/

    function test_freeze_doesNotPreserve_paymentDeadline() public {
        // Freeze must not extend the payment deadline. After the deadline passes, resolvePayment
        // (paid=true) must fail with PaymentDeadlineExpired regardless of frozen state.
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        vm.prank(_freezer);
        Marketplace(_marketplace).setDealFrozen(dealId, true);

        // Warp past the payment deadline while the deal is frozen.
        Deal memory deal = _getDeal(dealId);
        vm.warp(deal.paymentDeadline + 1);

        // Payment handler should not be able to mark as paid – deadline expired, not due to freeze.
        vm.prank(_paymentProvider);
        vm.expectRevert(Errors.Marketplace__PaymentDeadlineExpired.selector);
        Marketplace(_marketplace).resolvePayment(dealId, true);
    }

    function test_freeze_doesNotPreserve_disputeWindow() public {
        // Freeze must not extend the dispute buffer. After the buffer passes, initiateDispute must
        // fail with DisputePeriodExpired regardless of frozen state.
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        Deal memory deal = _getDeal(dealId);
        vm.warp(deal.paymentDeadline + 1);
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, false);

        vm.prank(_freezer);
        Marketplace(_marketplace).setDealFrozen(dealId, true);

        // Warp past the dispute buffer while the deal is frozen.
        deal = _getDeal(dealId);
        vm.warp(deal.disputeBuffer + 1);

        // Buyer should not be able to dispute – window expired, not due to freeze.
        vm.prank(buyer);
        vm.expectRevert(Errors.Marketplace__DisputePeriodExpired.selector);
        Marketplace(_marketplace).initiateDispute(dealId);
    }

    function test_freeze_doesNotPreserve_offerExpiry() public {
        // Freeze must not extend offer expiry. After expiry the offer cannot be accepted even if
        // it was frozen and then unfrozen.
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        Offer memory offer = _getOffer(offerId);

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        // Warp past offer expiry while frozen.
        vm.warp(offer.expiry + 1);

        // Unfreeze the offer; it must still be expired.
        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, false);

        address buyer = _createAndRegisterOtherCompany();
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__OfferExpired.selector, offer.expiry, block.timestamp)
        );
        Marketplace(_marketplace).acceptOffer(offerId, MIN_AMOUNT);
    }

    function test_freeze_doesNotPreserve_counterOfferExpiry() public {
        // Freeze must not extend counter-offer expiry. After expiry the proposal remains expired
        // even if it is later unfrozen.
        _approveEscrowManagerAsOperator(_company);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _createCounterOffer(offerId, MIN_AMOUNT, UNIT_PRICE, buyer);

        vm.prank(_freezer);
        Marketplace(_marketplace).setDealFrozen(dealId, true);

        Deal memory deal = _getDeal(dealId);
        uint256 counterOfferExpiry = deal.counterOfferExpiry;
        vm.warp(counterOfferExpiry + 1);

        vm.prank(_freezer);
        Marketplace(_marketplace).setDealFrozen(dealId, false);

        vm.prank(_company);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__CounterOfferExpired.selector, counterOfferExpiry, block.timestamp
            )
        );
        Marketplace(_marketplace).resolveCounterOffer(dealId, true);
    }

    /*//////////////////////////////////////////////////////////////
        RESERVED INTEREST SEIZURE GAP – seizeOfferEscrow covers
        reservedInterestUnits on frozen INTEREST_DISCOVERY offers
    //////////////////////////////////////////////////////////////*/

    function test_seizeOfferEscrow_zeroAvailable_allReserved_seizesReservedToo() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 totalUnits = BOND_MAX_SUPPLY;
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(totalUnits);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, totalUnits);

        assertEq(_getOffer(offerId).amounts.available, 0);
        assertEq(_getInterestDiscoveryState(offerId).reservedInterestUnits, totalUnits);

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        address beneficiary = _createAndRegisterOtherCompany();
        uint256 escrowId = _getEscrowIdByOfferId(offerId);
        uint256 escrowBefore = EscrowManager(_escrowManager).getEscrow(escrowId).amount;

        vm.prank(_deployer);
        Marketplace(_marketplace).seizeOfferEscrow(offerId, beneficiary, keccak256("REASON"));

        Offer memory offer = _getOffer(offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        assertEq(offer.amounts.available, 0);
        assertEq(state.reservedInterestUnits, 0);
        assertTrue(_isOfferCancelled(offerId));
        assertEq(EscrowManager(_escrowManager).getEscrow(escrowId).amount, escrowBefore - totalUnits);
        assertEq(uint8(_getInterest(interestId).status), uint8(InterestStatus.SEIZED));
    }

    function test_seizeOfferEscrow_marketplace_zeroAvailableAndNoReserved_reverts() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        OfferInput memory offerInput = _createInterestDiscoveryOfferInput(MIN_AMOUNT);
        offerInput.totalAmount = MIN_AMOUNT;

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offerInput);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.prank(investor);
        Marketplace(_marketplace).activateInterest(interestId);

        Offer memory offer = _getOffer(offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        assertEq(offer.amounts.available, 0);
        assertEq(offer.amounts.inDeals, MIN_AMOUNT);
        assertEq(state.reservedInterestUnits, 0);

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        address beneficiary = _createAndRegisterOtherCompany();
        vm.prank(_deployer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NoAvailableAmount.selector, offerId));
        Marketplace(_marketplace).seizeOfferEscrow(offerId, beneficiary, keccak256("REASON"));
    }

    function test_seizeOfferEscrow_marketplace_withAvailableAndSomeReserved_seizesAvailableAndReserved() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 totalUnits = BOND_MAX_SUPPLY;
        uint256 reserveAmount = MIN_AMOUNT;
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(reserveAmount);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, reserveAmount);

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        address beneficiary = _createAndRegisterOtherCompany();
        bytes32 reason = keccak256("SEIZURE");
        uint256 escrowId = _getEscrowIdByOfferId(offerId);
        uint256 escrowBefore = EscrowManager(_escrowManager).getEscrow(escrowId).amount;

        vm.expectEmit();
        emit IMarketplace.OfferEscrowSeized(offerId, beneficiary, totalUnits, reason, _deployer);

        vm.prank(_deployer);
        Marketplace(_marketplace).seizeOfferEscrow(offerId, beneficiary, reason);

        Offer memory offer = _getOffer(offerId);
        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        assertEq(offer.amounts.available, 0);
        assertTrue(_isOfferCancelled(offerId));
        assertEq(state.reservedInterestUnits, 0);
        assertEq(EscrowManager(_escrowManager).getEscrow(escrowId).amount, escrowBefore - totalUnits);
        assertEq(uint8(_getInterest(interestId).status), uint8(InterestStatus.SEIZED));
    }

    function test_seizeOfferEscrow_marketplace_keepsRawInterestStorageButLensProjectsSeized() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investorOne = _createAndRegisterOtherCompany();
        address investorTwo = _createAndRegisterOtherCompany();

        vm.prank(investorOne);
        uint256 interestIdOne = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);
        vm.prank(investorTwo);
        uint256 interestIdTwo = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        address beneficiary = _createAndRegisterOtherCompany();
        vm.prank(_deployer);
        Marketplace(_marketplace).seizeOfferEscrow(offerId, beneficiary, keccak256("REASON"));

        Interest memory rawInterestOne = Marketplace(_marketplace).getInterestData(interestIdOne);
        Interest memory rawInterestTwo = Marketplace(_marketplace).getInterestData(interestIdTwo);
        assertEq(uint8(rawInterestOne.status), uint8(InterestStatus.EXPRESSED));
        assertEq(uint8(rawInterestTwo.status), uint8(InterestStatus.EXPRESSED));

        assertEq(uint8(_getInterest(interestIdOne).status), uint8(InterestStatus.SEIZED));
        assertEq(uint8(_getInterest(interestIdTwo).status), uint8(InterestStatus.SEIZED));
    }

    function test_closeExpiredInterests_reverts_whenOfferCancelled() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        address beneficiary = _createAndRegisterOtherCompany();
        vm.prank(_deployer);
        Marketplace(_marketplace).seizeOfferEscrow(offerId, beneficiary, keccak256("REASON"));

        assertTrue(_isOfferCancelled(offerId));

        vm.warp(block.timestamp + 60 days);

        uint256[] memory interestIds = new uint256[](1);
        interestIds[0] = interestId;

        vm.prank(_company);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferAlreadyCancelled.selector, offerId));
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);
    }

    function test_regression_DealStatus_SEIZED_enum_value_still_10() public pure {
        assertEq(uint8(DealStatus.SEIZED), 10);
    }

    function test_interestStatus_SEIZED_enum_value_is_4() public pure {
        assertEq(uint8(InterestStatus.NON_EXISTING), 0);
        assertEq(uint8(InterestStatus.EXPRESSED), 1);
        assertEq(uint8(InterestStatus.ACTIVATED), 2);
        assertEq(uint8(InterestStatus.CLOSED), 3);
        assertEq(uint8(InterestStatus.SEIZED), 4);
    }

    /*//////////////////////////////////////////////////////////////
                         PRIVATE TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    function _assertSeizeDealSuccess(uint256 offerId, uint256 dealId, address beneficiary, DealStatus expectedPreStatus)
        private
    {
        uint256 escrowId = _getEscrowIdByOfferId(offerId);
        uint256 escrowBefore = EscrowManager(_escrowManager).getEscrow(escrowId).amount;
        Offer memory offerBefore = _getOffer(offerId);
        Deal memory dealSnapshot = _getDeal(dealId);
        assertEq(uint8(dealSnapshot.status), uint8(expectedPreStatus));

        bytes32 reason = keccak256("SEIZURE");

        vm.startPrank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);
        Marketplace(_marketplace).setDealFrozen(dealId, true);
        vm.stopPrank();

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(
            dealId, _getDeal(dealId).offerId, uint8(DealStatus.SEIZED), uint8(_getDeal(dealId).status)
        );
        vm.expectEmit();
        emit IMarketplace.AmountsUpdated(
            offerId,
            offerBefore.amounts.available,
            offerBefore.amounts.inDeals - dealSnapshot.amount,
            offerBefore.amounts.sold
        );
        vm.expectEmit();
        emit IMarketplace.DealSeized(dealId, offerId, beneficiary, dealSnapshot.amount, reason, _deployer);

        vm.prank(_deployer);
        Marketplace(_marketplace).seizeDeal(dealId, beneficiary, reason);

        // deal → SEIZED
        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SEIZED));

        Offer memory offerAfter = _getOffer(offerId);
        assertEq(offerAfter.amounts.inDeals, offerBefore.amounts.inDeals - dealSnapshot.amount);
        assertEq(offerAfter.amounts.available, offerBefore.amounts.available);
        assertEq(offerAfter.amounts.sold, offerBefore.amounts.sold);

        assertEq(EscrowManager(_escrowManager).getEscrow(escrowId).amount, escrowBefore - dealSnapshot.amount);
    }
}
