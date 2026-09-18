// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";
import {Errors} from "src/libs/Errors.sol";
import {Initializable} from "solady/src/utils/Initializable.sol";
import {IMarketplaceLens} from "src/marketplace/interfaces/IMarketplaceLens.sol";
import {IMarketplaceLensSource} from "src/marketplace/interfaces/IMarketplaceLensSource.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {MarketplaceLens} from "src/marketplace/lens/MarketplaceLens.sol";
import {MarketplaceStorage} from "src/marketplace/MarketplaceStorage.sol";
import {
    Deal,
    DealStatus,
    Interest,
    InterestDiscoveryState,
    InterestStatus,
    Offer,
    OfferInput
} from "src/marketplace/MarketStructs.sol";
import {MarketplaceFixture} from "test/fixtures/MarketplaceFixture.t.sol";

contract MockMarketplaceLensV2 is MarketplaceLens {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract MarketplaceLensTest is MarketplaceFixture {
    IMarketplaceLens internal _lens;
    IMarketplaceLensSource internal _source;

    function setUp() public override {
        super.setUp();
        _lens = IMarketplaceLens(_marketplaceLens);
        _source = IMarketplaceLensSource(_marketplace);
    }

    function _marketplaceConfig() internal view returns (MarketplaceStorage.Config memory config) {
        (config,) = Marketplace(_marketplace).getConfigAndCounters();
    }

    /*//////////////////////////////////////////////////////////////
                              initialize
    //////////////////////////////////////////////////////////////*/

    function test_initialize_success() public {
        MarketplaceLens lens = _deployLensProxy(makeAddr("owner"), _marketplace);
        assertEq(lens.marketplace(), _marketplace);
    }

    function test_initialize_reverts_reinitialize() public {
        MarketplaceLens lens = _deployLensProxy(makeAddr("owner"), _marketplace);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        lens.initialize(makeAddr("owner2"), _marketplace);
    }

    function test_initialize_reverts_onImplementationDirectly() public {
        MarketplaceLens implementation = new MarketplaceLens();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(makeAddr("owner"), _marketplace);
    }

    /*//////////////////////////////////////////////////////////////
                                deployment
    //////////////////////////////////////////////////////////////*/

    function test_deployment_reverts_zeroOwner() public {
        MarketplaceLens implementation = new MarketplaceLens();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), makeAddr("owner"));
        bytes memory initData = abi.encodeWithSelector(MarketplaceLens.initialize.selector, address(0), _marketplace);

        vm.expectRevert(Errors.ZeroAddress.selector);
        new BeaconProxy(address(beacon), initData);
    }

    function test_deployment_reverts_zeroMarketplace() public {
        MarketplaceLens implementation = new MarketplaceLens();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), makeAddr("owner"));
        bytes memory initData =
            abi.encodeWithSelector(MarketplaceLens.initialize.selector, makeAddr("owner"), address(0));

        vm.expectRevert(Errors.ZeroAddress.selector);
        new BeaconProxy(address(beacon), initData);
    }

    /*//////////////////////////////////////////////////////////////
                                upgradeTo
    //////////////////////////////////////////////////////////////*/

    function test_upgradeTo_success_beaconOwner() public {
        address owner = makeAddr("owner");
        (MarketplaceLens lens, UpgradeableBeacon beacon) = _deployLensProxyWithBeacon(owner, _marketplace);
        address newImpl = address(new MockMarketplaceLensV2());

        vm.prank(owner);
        beacon.upgradeTo(newImpl);

        assertEq(beacon.implementation(), newImpl);
        assertEq(MockMarketplaceLensV2(address(lens)).version(), 2);
    }

    function test_upgradeTo_reverts_notBeaconOwner() public {
        address owner = makeAddr("owner");
        (, UpgradeableBeacon beacon) = _deployLensProxyWithBeacon(owner, _marketplace);
        address newImpl = address(new MockMarketplaceLensV2());
        address notOwner = makeAddr("notOwner");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableUnauthorizedAccount.selector, notOwner));
        beacon.upgradeTo(newImpl);
    }

    /*//////////////////////////////////////////////////////////////
                            getOfferData
    //////////////////////////////////////////////////////////////*/

    function test_getOfferData_success() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        (
            Offer memory offer,
            InterestDiscoveryState memory state,
            uint256[] memory interestIds,
            address[] memory allowedBuyers,
            uint256 escrowId
        ) = _source.getOfferData(offerId);
        (bool cancelled, bool frozen, bool reservedInterestSeized) = _source.getOfferFlags(offerId);

        assertEq(offer.owner, _company);
        assertEq(offer.amounts.available, BOND_MAX_SUPPLY);
        assertEq(state.minSaleUnits, 0);
        assertEq(state.interestedUnits, 0);
        assertEq(state.reservedInterestUnits, 0);
        assertEq(state.paymentExpiryThreshold, 0);
        assertEq(interestIds.length, 0);
        assertEq(allowedBuyers.length, 0);
        assertEq(escrowId, _getEscrowIdByOfferId(offerId));
        assertFalse(cancelled);
        assertFalse(frozen);
        assertFalse(reservedInterestSeized);
    }

    /*//////////////////////////////////////////////////////////////
                             getDealData
    //////////////////////////////////////////////////////////////*/

    function test_getDealData_success() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        (Deal memory deal, bool frozen) = _source.getDealData(dealId);

        assertEq(deal.offerId, offerId);
        assertEq(deal.buyer, buyer);
        assertEq(deal.amount, MIN_AMOUNT);
        assertEq(uint8(deal.status), uint8(DealStatus.PENDING));
        assertFalse(frozen);
    }

    function test_getDealData_success_nonExistingDeal() public view {
        (Deal memory deal, bool frozen) = _source.getDealData(type(uint256).max);

        assertEq(uint8(deal.status), uint8(DealStatus.NON_EXISTING));
        assertFalse(frozen);
    }

    /*//////////////////////////////////////////////////////////////
                           getInterestData
    //////////////////////////////////////////////////////////////*/

    function test_getInterestData_success() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 2);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        Interest memory interest = _source.getInterestData(interestId);
        assertEq(interest.offerId, offerId);
        assertEq(interest.investor, investor);
        assertEq(interest.amount, MIN_AMOUNT);
        assertEq(uint8(interest.status), uint8(InterestStatus.EXPRESSED));
    }

    function test_getInterestData_reverts_interestNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InterestNotFound.selector, type(uint256).max));
        _source.getInterestData(type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                               getOffer
    //////////////////////////////////////////////////////////////*/

    function test_getOffer_success() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        Offer memory offer = _lens.getOffer(offerId);
        assertEq(offer.owner, _company);
        assertEq(offer.amounts.available, BOND_MAX_SUPPLY);
    }

    function test_getAllowedBuyers_success() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        address allowedBuyer = _createAndRegisterOtherCompany();
        OfferInput memory offer = _createOfferInput();
        offer.allowedBuyers = new address[](1);
        offer.allowedBuyers[0] = allowedBuyer;

        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        address[] memory allowedBuyers = _lens.getAllowedBuyers(offerId);
        assertEq(allowedBuyers.length, 1);
        assertEq(allowedBuyers[0], allowedBuyer);
    }

    /*//////////////////////////////////////////////////////////////
                                getDeal
    //////////////////////////////////////////////////////////////*/

    function test_getDeal_success() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        Deal memory deal = _lens.getDeal(dealId);
        assertEq(deal.offerId, offerId);
        assertEq(deal.buyer, buyer);
    }

    /*//////////////////////////////////////////////////////////////
                              getInterest
    //////////////////////////////////////////////////////////////*/

    function test_getInterest_success_returnsExpressedInterest() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 2);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        Interest memory interest = _lens.getInterest(interestId);
        assertEq(uint8(interest.status), uint8(InterestStatus.EXPRESSED));
        assertEq(interest.offerId, offerId);
    }

    function test_getInterest_success_projectsClosedAfterFailedBookCancellation() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 2);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.warp(_getOffer(offerId).expiry + 1);

        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);

        Interest memory interest = _lens.getInterest(interestId);
        assertEq(uint8(interest.status), uint8(InterestStatus.CLOSED));
    }

    function test_getInterest_success_keepsExpressedWhenReservationsNotReleased() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 2);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        uint256 interestId = Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        vm.warp(_getOffer(offerId).expiry + 1);

        Interest memory interest = _lens.getInterest(interestId);
        assertEq(uint8(interest.status), uint8(InterestStatus.EXPRESSED));
    }

    function test_getInterest_success_projectsSeizedAfterOfferEscrowSeizure() public {
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

        Interest memory rawInterest = _source.getInterestData(interestId);
        Interest memory projectedInterest = _lens.getInterest(interestId);

        assertEq(uint8(rawInterest.status), uint8(InterestStatus.EXPRESSED));
        assertEq(uint8(projectedInterest.status), uint8(InterestStatus.SEIZED));
    }

    function test_getInterest_reverts_interestNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__InterestNotFound.selector, type(uint256).max));
        _lens.getInterest(type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        getInterestIdsByOfferId
    //////////////////////////////////////////////////////////////*/

    function test_getInterestIdsByOfferId_success() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 3);
        address investorOne = _createAndRegisterOtherCompany();
        address investorTwo = _createAndRegisterOtherCompany();

        vm.prank(investorOne);
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);
        vm.prank(investorTwo);
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        uint256[] memory interestIds = _lens.getInterestIdsByOfferId(offerId);
        assertEq(interestIds.length, 2);
        assertEq(interestIds[0], 1);
        assertEq(interestIds[1], 2);
    }

    /*//////////////////////////////////////////////////////////////
                     getInterestDiscoveryState
    //////////////////////////////////////////////////////////////*/

    function test_getInterestDiscoveryState_success() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT * 3);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        InterestDiscoveryState memory state = _lens.getInterestDiscoveryState(offerId);
        assertEq(state.minSaleUnits, MIN_AMOUNT * 3);
        assertEq(state.interestedUnits, MIN_AMOUNT);
        assertEq(state.reservedInterestUnits, MIN_AMOUNT);
        assertEq(state.paymentExpiryThreshold, _marketplaceConfig().interestDiscoveryPaymentExpiryThreshold);
    }

    /*//////////////////////////////////////////////////////////////
                         isOfferCancelled
    //////////////////////////////////////////////////////////////*/

    function test_isOfferCancelled_success() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        assertFalse(_lens.isOfferCancelled(offerId));

        vm.prank(_company);
        Marketplace(_marketplace).cancelOffer(offerId);

        assertTrue(_lens.isOfferCancelled(offerId));
    }

    /*//////////////////////////////////////////////////////////////
                    isReservedInterestSeized
    //////////////////////////////////////////////////////////////*/

    function test_isReservedInterestSeized_success() public {
        _approveEscrowManager(_company, _bondFTId, BOND_ISSUANCE_NOMINAL_VALUE / BOND_NOMINAL_VALUE);
        uint256 offerId = _registerInterestDiscoveryOfferAsCompany(MIN_AMOUNT);
        address investor = _createAndRegisterOtherCompany();

        vm.prank(investor);
        Marketplace(_marketplace).expressInterest(offerId, MIN_AMOUNT);

        assertFalse(_lens.isReservedInterestSeized(offerId));

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);
        address beneficiary = _createAndRegisterOtherCompany();
        vm.prank(_deployer);
        Marketplace(_marketplace).seizeOfferEscrow(offerId, beneficiary, keccak256("REASON"));

        assertTrue(_lens.isReservedInterestSeized(offerId));
    }

    /*//////////////////////////////////////////////////////////////
                           isOfferFrozen
    //////////////////////////////////////////////////////////////*/

    function test_isOfferFrozen_success() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        assertFalse(_lens.isOfferFrozen(offerId));

        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        assertTrue(_lens.isOfferFrozen(offerId));
    }

    /*//////////////////////////////////////////////////////////////
                            isDealFrozen
    //////////////////////////////////////////////////////////////*/

    function test_isDealFrozen_success() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();
        address buyer = _createAndRegisterOtherCompany();
        uint256 dealId = _acceptOffer(offerId, MIN_AMOUNT, buyer);

        assertFalse(_lens.isDealFrozen(dealId));

        vm.prank(_freezer);
        Marketplace(_marketplace).setDealFrozen(dealId, true);

        assertTrue(_lens.isDealFrozen(dealId));
    }

    /*//////////////////////////////////////////////////////////////
                        getEscrowIdByOfferId
    //////////////////////////////////////////////////////////////*/

    function test_getEscrowIdByOfferId_success() public {
        _approveEscrowManager(_company, _bondFTId, BOND_MAX_SUPPLY);
        uint256 offerId = _registerOfferAsCompany();

        assertEq(_lens.getEscrowIdByOfferId(offerId), 1);
    }

    function _deployLensProxy(address owner, address marketplace) internal returns (MarketplaceLens lens) {
        (lens,) = _deployLensProxyWithBeacon(owner, marketplace);
    }

    function _deployLensProxyWithBeacon(address owner, address marketplace)
        internal
        returns (MarketplaceLens lens, UpgradeableBeacon beacon)
    {
        MarketplaceLens implementation = new MarketplaceLens();
        beacon = new UpgradeableBeacon(address(implementation), owner);
        bytes memory initData = abi.encodeWithSelector(MarketplaceLens.initialize.selector, owner, marketplace);
        lens = MarketplaceLens(address(new BeaconProxy(address(beacon), initData)));
    }
}
