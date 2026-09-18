// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {SharedE2EFixture} from "test/fixtures/SharedE2EFixture.t.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {MarketplaceBase} from "src/marketplace/MarketplaceBase.sol";
import {DealStatus, Deal, Offer, OfferInput} from "src/marketplace/MarketStructs.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";
import {Errors} from "src/libs/Errors.sol";

contract MarketplaceCounterOfferE2ETest is SharedE2EFixture {
    /*//////////////////////////////////////////////////////////////
                        SCENARIO CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Full issue volume expressed as bond units.
    uint256 private constant _FULL_AMOUNT = BOND_ISSUE_COUNT;
    /// @dev Counter-offer proposes to buy 1/4 of the total supply.
    uint256 private constant _COUNTER_AMOUNT = _FULL_AMOUNT / 4;
    /// @dev Negotiated price is 10% below the original offer price.
    uint256 private constant _COUNTER_PRICE = OFFER_UNIT_PRICE * 9 / 10;
    /// @dev Minimum valid counter-offer lifetime (offerExpiryThreshold = 1 day).
    uint256 private constant _CO_EXPIRY_OFFSET = 1 days;

    /*//////////////////////////////////////////////////////////////
        test_e2e_counterOffer_accepted_negotiatedPrice_settled
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. issuerWallet registers an offer.
     *   2. _buyerWallet creates a counter-offer at a lower negotiated price.
     *   3. issuerWallet accepts the counter-offer via resolveCounterOffer.
     *      Deal transitions PROPOSED -> PENDING; inventory is locked.
     *   4. paymentProvider marks paid; deal settles successfully.
     *
     * Purpose: prove the negotiated-price happy path where a buyer proposes a
     *          counter-offer below the listed price, the issuer accepts it, and
     *          the resulting deal settles like a normal paid trade.
     */
    function test_e2e_counterOffer_accepted_negotiatedPrice_settled() public {
        uint256 offerId = _registerOffer();

        uint256 expiry = block.timestamp + _CO_EXPIRY_OFFSET;
        uint256 dealId = _createCounterOffer(offerId, _COUNTER_AMOUNT, _COUNTER_PRICE, expiry, _buyerWallet);

        Deal memory snap = _getDeal(dealId);
        assertEq(uint8(snap.status), uint8(DealStatus.PROPOSED));
        assertEq(snap.price, _COUNTER_PRICE * _COUNTER_AMOUNT, "counter price recorded");

        Offer memory offerBefore = _getOffer(offerId);
        assertEq(offerBefore.amounts.available, _FULL_AMOUNT, "available before acceptance");
        assertEq(offerBefore.amounts.inDeals, 0, "inDeals before acceptance");

        _resolveCounterOffer(dealId, true);

        Offer memory offerAfter = _getOffer(offerId);
        assertEq(offerAfter.amounts.available, _FULL_AMOUNT - _COUNTER_AMOUNT, "available after acceptance");
        assertEq(offerAfter.amounts.inDeals, _COUNTER_AMOUNT, "inDeals after acceptance");

        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _COUNTER_AMOUNT);

        Deal memory settled = _getDeal(dealId);
        assertEq(uint8(settled.status), uint8(DealStatus.SUCCESSFUL));

        Offer memory finalOffer = _getOffer(offerId);
        assertEq(finalOffer.amounts.sold, _COUNTER_AMOUNT);
        assertEq(finalOffer.amounts.inDeals, 0);
        assertEq(finalOffer.amounts.available, _FULL_AMOUNT - _COUNTER_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_counterOffer_rejected_cancelled_or_expired_offerInventoryUnchanged
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. issuerWallet registers an offer.
     *   2. _buyerWallet creates one counter-offer that issuerWallet rejects.
     *   3. _buyerWallet creates another counter-offer and cancels it before expiry.
     *   4. A non-buyer cannot cancel a live counter-offer.
     *   5. Expired counter-offers cannot be resolved or cancelled.
     *
     * Purpose: prove that unsuccessful counter-offers do not consume offer
     *          inventory, whether they are explicitly declined, cancelled by the
     *          buyer, rejected for unauthorized cancellation, or aged past expiry.
     */
    function test_e2e_counterOffer_rejected_cancelled_or_expired_offerInventoryUnchanged() public {
        uint256 offerId = _registerOffer();

        uint256 rejectExpiry = block.timestamp + _CO_EXPIRY_OFFSET;
        uint256 rejectedDealId =
            _createCounterOffer(offerId, _COUNTER_AMOUNT, _COUNTER_PRICE, rejectExpiry, _buyerWallet);

        _resolveCounterOffer(rejectedDealId, false);

        Deal memory rejectedDeal = _getDeal(rejectedDealId);
        assertEq(uint8(rejectedDeal.status), uint8(DealStatus.DECLINED));

        Offer memory offerAfterReject = _getOffer(offerId);
        assertEq(offerAfterReject.amounts.available, _FULL_AMOUNT, "available unchanged after reject");
        assertEq(offerAfterReject.amounts.inDeals, 0, "inDeals unchanged after reject");
        assertEq(offerAfterReject.amounts.sold, 0, "sold unchanged after reject");

        uint256 cancelExpiry = block.timestamp + _CO_EXPIRY_OFFSET;
        uint256 cancelledDealId =
            _createCounterOffer(offerId, _COUNTER_AMOUNT, _COUNTER_PRICE, cancelExpiry, _buyerWallet);

        _cancelCounterOffer(cancelledDealId, _buyerWallet);

        assertEq(uint8(_getDeal(cancelledDealId).status), uint8(DealStatus.CANCELLED));

        Offer memory offerAfterCancel = _getOffer(offerId);
        assertEq(offerAfterCancel.amounts.available, _FULL_AMOUNT, "available unchanged after cancel");
        assertEq(offerAfterCancel.amounts.inDeals, 0, "inDeals unchanged after cancel");
        assertEq(offerAfterCancel.amounts.sold, 0, "sold unchanged after cancel");

        uint256 liveExpiry = block.timestamp + _CO_EXPIRY_OFFSET;
        uint256 liveDealId = _createCounterOffer(offerId, _COUNTER_AMOUNT, _COUNTER_PRICE, liveExpiry, _buyerWallet);
        address nonBuyer = makeAddr("counterOfferNonBuyer");
        vm.prank(nonBuyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__NotAuthorized.selector, nonBuyer));
        Marketplace(_marketplace).cancelCounterOffer(liveDealId);

        assertEq(uint8(_getDeal(liveDealId).status), uint8(DealStatus.PROPOSED), "live CO still proposed");

        uint256 expiry = block.timestamp + _CO_EXPIRY_OFFSET;
        uint256 expiredDealId = _createCounterOffer(offerId, _COUNTER_AMOUNT, _COUNTER_PRICE, expiry, _buyerWallet);

        Deal memory expiredDeal = _getDeal(expiredDealId);
        vm.warp(expiredDeal.counterOfferExpiry + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__CounterOfferExpired.selector, expiredDeal.counterOfferExpiry, block.timestamp
            )
        );
        _resolveCounterOffer(expiredDealId, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__CounterOfferExpired.selector, expiredDeal.counterOfferExpiry, block.timestamp
            )
        );
        _cancelCounterOffer(expiredDealId, _buyerWallet);

        expiredDeal = _getDeal(expiredDealId);
        assertEq(uint8(expiredDeal.status), uint8(DealStatus.PROPOSED), "expired CO still proposed");
        assertLt(expiredDeal.counterOfferExpiry, block.timestamp, "counter-offer is expired");

        Offer memory offerAfterExpiry = _getOffer(offerId);
        assertEq(offerAfterExpiry.amounts.available, _FULL_AMOUNT, "available unchanged after expiry");
        assertEq(offerAfterExpiry.amounts.inDeals, 0, "inDeals unchanged after expiry");
        assertEq(offerAfterExpiry.amounts.sold, 0, "sold unchanged after expiry");
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_counterOffer_notAllowed_and_limitReached_doNotConsumeInventory
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. An offer with allowCounterOffers = false rejects counter-offer creation.
     *   2. Governance lowers the per-user counter-offer limit to one.
     *   3. The first counter-offer succeeds, while the second from the same buyer reverts.
     *
     * Purpose: prove both offer-level and platform-level counter-offer gates
     *          are enforced without consuming seller inventory.
     */
    function test_e2e_counterOffer_notAllowed_and_limitReached_doNotConsumeInventory() public {
        OfferInput memory noCounterOfferInput = _createOfferInput();
        noCounterOfferInput.expiry = block.timestamp + OFFER_EXPIRY;
        noCounterOfferInput.totalAmount = _COUNTER_AMOUNT;
        noCounterOfferInput.allowCounterOffers = false;

        vm.prank(_issuerWallet);
        uint256 noCounterOfferId = Marketplace(_marketplace).registerOffer(noCounterOfferInput);

        vm.expectRevert(Errors.Marketplace__CounterOffersNotAllowed.selector);
        _createCounterOffer(
            noCounterOfferId, _COUNTER_AMOUNT, _COUNTER_PRICE, block.timestamp + _CO_EXPIRY_OFFSET, _buyerWallet
        );

        vm.prank(_adminID);
        MarketplaceBase(_marketplace).setMaxCounterOffersPerUser(1);

        OfferInput memory limitedOfferInput = _createOfferInput();
        limitedOfferInput.expiry = block.timestamp + OFFER_EXPIRY;
        limitedOfferInput.totalAmount = _COUNTER_AMOUNT;
        vm.prank(_issuerWallet);
        uint256 limitedOfferId = Marketplace(_marketplace).registerOffer(limitedOfferInput);
        _createCounterOffer(
            limitedOfferId, _COUNTER_AMOUNT, _COUNTER_PRICE, block.timestamp + _CO_EXPIRY_OFFSET, _buyerWallet
        );

        vm.expectRevert(Errors.Marketplace__CounterOfferLimitReached.selector);
        _createCounterOffer(
            limitedOfferId, _COUNTER_AMOUNT, _COUNTER_PRICE, block.timestamp + _CO_EXPIRY_OFFSET, _buyerWallet
        );

        Offer memory noCounterOffer = _getOffer(noCounterOfferId);
        assertEq(noCounterOffer.amounts.available, _COUNTER_AMOUNT, "disabled offer available");
        assertEq(noCounterOffer.amounts.inDeals, 0, "disabled offer inDeals");

        Offer memory limitedOffer = _getOffer(limitedOfferId);
        assertEq(limitedOffer.amounts.available, _COUNTER_AMOUNT, "limited offer available");
        assertEq(limitedOffer.amounts.inDeals, 0, "limited offer inDeals");
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_counterOffer_frozenDealOrOffer_blocksCancelAndResolve_thenSettles
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. Buyer creates a live counter-offer.
     *   2. Freezing the proposed deal blocks buyer cancellation.
     *   3. Freezing the parent offer blocks issuer resolution.
     *   4. Once both freezes are lifted, the issuer accepts and the deal settles.
     *
     * Purpose: prove compliance freezes apply to counter-offer lifecycle actions,
     *          not only direct offer acceptance and settlement.
     */
    function test_e2e_counterOffer_frozenDealOrOffer_blocksCancelAndResolve_thenSettles() public {
        uint256 offerId = _registerOffer();
        uint256 dealId = _createCounterOffer(
            offerId, _COUNTER_AMOUNT, _COUNTER_PRICE, block.timestamp + _CO_EXPIRY_OFFSET, _buyerWallet
        );

        _setDealFrozen(dealId, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DealFrozen.selector, dealId));
        _cancelCounterOffer(dealId, _buyerWallet);

        _setDealFrozen(dealId, false);
        _setOfferFrozen(offerId, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferFrozen.selector, offerId));
        _resolveCounterOffer(dealId, true);

        _setOfferFrozen(offerId, false);
        _resolveCounterOffer(dealId, true);

        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _COUNTER_AMOUNT);
        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));
    }
}
