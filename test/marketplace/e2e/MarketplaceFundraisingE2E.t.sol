// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable gas-small-strings */

import {SharedE2EFixture} from "test/fixtures/SharedE2EFixture.t.sol";
import {DealStatus, Interest, InterestDiscoveryState, InterestStatus, Offer} from "src/marketplace/MarketStructs.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";
import {Errors} from "src/libs/Errors.sol";

contract MarketplaceFundraisingE2ETest is SharedE2EFixture {
    /*//////////////////////////////////////////////////////////////
                        SCENARIO CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 private constant _FULL_AMOUNT = BOND_ISSUE_COUNT;
    uint256 private constant _HALF_AMOUNT = _FULL_AMOUNT / 2;
    uint256 private constant _QUARTER_AMOUNT = _FULL_AMOUNT / 4;

    /// @dev Minimum offer lifetime in DeployConstants (offerExpiryThreshold) = 1 day.
    uint256 private constant _OFFER_EXPIRY_THRESHOLD = 1 days;

    function _activationWindow(uint256 offerId) private view returns (uint256 activationWindow) {
        return _getInterestDiscoveryState(offerId).paymentExpiryThreshold;
    }

    function _activationDeadline(uint256 offerId) private view returns (uint256 activationDeadline) {
        return _getOffer(offerId).expiry + _activationWindow(offerId);
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_marketplace_thresholdReached_activated_paid_settled
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. _issuerWallet registers an INTEREST_DISCOVERY offer with minSaleUnits = HALF_AMOUNT.
     *   2. _buyerWallet expresses interest for the full amount (> threshold).
     *   3. After offer expiry, a third-party caller activates the interest.
     *   4. _paymentProvider marks the deal paid; deal settles; _buyerWallet receives bonds.
     *
     * Purpose: prove the threshold-reached happy path for fundraising mode,
     *          where a fully subscribed book can be activated after expiry and
     *          then complete through normal payment confirmation and settlement.
     */
    function test_e2e_marketplace_thresholdReached_activated_paid_settled() public {
        uint256 offerId = _registerInterestDiscoveryOffer(_HALF_AMOUNT);

        uint256 interestId = _expressInterest(offerId, _FULL_AMOUNT, _buyerWallet);

        InterestDiscoveryState memory stateAfterExpress = _getInterestDiscoveryState(offerId);
        assertEq(stateAfterExpress.interestedUnits, _FULL_AMOUNT, "interested units");
        assertEq(stateAfterExpress.reservedInterestUnits, _FULL_AMOUNT, "reserved units");
        assertEq(stateAfterExpress.minSaleUnits, _HALF_AMOUNT, "min sale units");

        Interest memory interest = _getInterest(interestId);
        assertEq(uint8(interest.status), uint8(InterestStatus.EXPRESSED), "EXPRESSED");

        Offer memory offerMid = _getOffer(offerId);
        assertEq(offerMid.amounts.available, 0, "available zeroed after express");

        vm.warp(block.timestamp + OFFER_EXPIRY + 1);

        address activator = makeAddr("activator");
        uint256 dealId = _activateInterest(interestId, activator);

        Interest memory activatedInterest = _getInterest(interestId);
        assertEq(uint8(activatedInterest.status), uint8(InterestStatus.ACTIVATED), "ACTIVATED");

        InterestDiscoveryState memory stateAfterActivate = _getInterestDiscoveryState(offerId);
        assertEq(stateAfterActivate.reservedInterestUnits, 0, "reserved zeroed after activate");

        Offer memory offerAfterActivate = _getOffer(offerId);
        assertEq(offerAfterActivate.amounts.inDeals, _FULL_AMOUNT, "inDeals == full after activate");

        _resolvePayment(dealId, true);

        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _FULL_AMOUNT);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), 0);

        Offer memory finalOffer = _getOffer(offerId);
        assertEq(finalOffer.amounts.sold, _FULL_AMOUNT, "sold == full");
        assertEq(finalOffer.amounts.inDeals, 0, "inDeals == 0");
        assertEq(finalOffer.amounts.available, 0, "available == 0");

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));
    }

    function test_e2e_marketplace_activationAtDeadline_receivesFreshPaymentWindow_paid_settled() public {
        uint256 offerId = _registerInterestDiscoveryOffer(_HALF_AMOUNT);
        uint256 interestId = _expressInterest(offerId, _FULL_AMOUNT, _buyerWallet);

        uint256 activationWindow = _activationWindow(offerId);
        uint256 activationDeadline = _activationDeadline(offerId);
        vm.warp(activationDeadline);

        uint256 dealId = _activateInterest(interestId, makeAddr("lateActivator"));

        assertEq(_getDeal(dealId).paymentDeadline, activationDeadline + activationWindow);
        assertGt(_getDeal(dealId).paymentDeadline, block.timestamp);

        vm.warp(block.timestamp + 1);
        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _FULL_AMOUNT);
        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_marketplace_exactThreshold_activated_paid_settled
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. _issuerWallet registers an INTEREST_DISCOVERY offer with minSaleUnits = HALF_AMOUNT.
     *   2. _buyerWallet expresses exactly HALF_AMOUNT.
     *   3. After offer expiry, the interest activates, is paid, and settles.
     *
     * Purpose: prove that the threshold comparison is inclusive and does not
     *          require oversubscription.
     */
    function test_e2e_marketplace_exactThreshold_activated_paid_settled() public {
        uint256 offerId = _registerInterestDiscoveryOffer(_HALF_AMOUNT);
        uint256 interestId = _expressInterest(offerId, _HALF_AMOUNT, _buyerWallet);

        Offer memory offer = _getOffer(offerId);
        vm.warp(offer.expiry + 1);

        uint256 dealId = _activateInterest(interestId, _buyerWallet);
        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _HALF_AMOUNT);
        assertEq(uint8(_getInterest(interestId).status), uint8(InterestStatus.ACTIVATED));
        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_marketplace_cumulativeThreshold_activatesMultipleInterests
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. Offer threshold is HALF_AMOUNT.
     *   2. Two buyers each express QUARTER_AMOUNT, cumulatively reaching threshold.
     *   3. After expiry, both interests activate and settle.
     *
     * Purpose: prove threshold accounting is based on aggregate book interest,
     *          not a single investor's expressed amount.
     */
    function test_e2e_marketplace_cumulativeThreshold_activatesMultipleInterests() public {
        uint256 offerId = _registerInterestDiscoveryOffer(_HALF_AMOUNT);
        uint256 interestId1 = _expressInterest(offerId, _QUARTER_AMOUNT, _buyerWallet);
        uint256 interestId2 = _expressInterest(offerId, _QUARTER_AMOUNT, _secondBuyerWallet);

        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        assertEq(state.interestedUnits, _HALF_AMOUNT, "threshold not reached cumulatively");
        assertEq(state.reservedInterestUnits, _HALF_AMOUNT, "reserved amount");

        Offer memory offer = _getOffer(offerId);
        vm.warp(offer.expiry + 1);

        uint256 dealId1 = _activateInterest(interestId1, _buyerWallet);
        uint256 dealId2 = _activateInterest(interestId2, _secondBuyerWallet);

        _resolvePayment(dealId1, true);
        _resolvePayment(dealId2, true);
        _settleDeal(dealId1);
        _settleDeal(dealId2);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _QUARTER_AMOUNT);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_secondBuyerWallet, _bondFTId), _QUARTER_AMOUNT);

        Offer memory finalOffer = _getOffer(offerId);
        assertEq(finalOffer.amounts.sold, _HALF_AMOUNT, "sold");
        assertEq(finalOffer.amounts.available, _HALF_AMOUNT, "available remainder");
        assertEq(finalOffer.amounts.inDeals, 0, "inDeals");
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_marketplace_postExpiryActivationWithinWindow_paid_settled
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. Offer registered with minSaleUnits = QUARTER_AMOUNT.
     *   2. _buyerWallet expresses interest for HALF_AMOUNT before sale end.
     *   3. Warp past saleEnd but still within the activation window.
     *   4. Activate, resolve payment, settle.
     *
     * Purpose: confirm that activation is valid at any point within
     *          [saleEnd, saleEnd + snapshotted activation window].
     */
    function test_e2e_marketplace_postExpiryActivationWithinWindow_paid_settled() public {
        uint256 offerId = _registerInterestDiscoveryOffer(_QUARTER_AMOUNT);
        uint256 interestId = _expressInterest(offerId, _HALF_AMOUNT, _buyerWallet);

        Offer memory offer = _getOffer(offerId);
        vm.warp(offer.expiry + _activationWindow(offerId) / 2);

        uint256 dealId = _activateInterest(interestId, _buyerWallet);

        assertEq(uint8(_getInterest(interestId).status), uint8(InterestStatus.ACTIVATED));
        assertEq(_getDeal(dealId).amount, _HALF_AMOUNT);

        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _HALF_AMOUNT);

        Offer memory finalOffer = _getOffer(offerId);
        assertEq(finalOffer.amounts.sold, _HALF_AMOUNT);
        assertEq(finalOffer.amounts.inDeals, 0);
        assertEq(finalOffer.amounts.available, _HALF_AMOUNT);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_marketplace_activationAfterWindow_reverts
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. Offer reaches its threshold exactly.
     *   2. The activation window elapses without activation.
     *   3. A later activation attempt reverts.
     *
     * Purpose: prove stale expressed interests cannot be activated indefinitely.
     */
    function test_e2e_marketplace_activationAfterWindow_reverts() public {
        uint256 offerId = _registerInterestDiscoveryOffer(_QUARTER_AMOUNT);
        uint256 interestId = _expressInterest(offerId, _QUARTER_AMOUNT, _buyerWallet);

        uint256 activationDeadline = _activationDeadline(offerId);
        vm.warp(activationDeadline + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__InterestActivationWindowExpired.selector,
                offerId,
                activationDeadline,
                block.timestamp
            )
        );
        _activateInterest(interestId, _buyerWallet);
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_marketplace_failedBook_cancelOffer_closesInterest
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. Offer registered with minSaleUnits = FULL_AMOUNT (hard threshold).
     *   2. _buyerWallet expresses only QUARTER_AMOUNT (below threshold).
     *   3. Offer expires; threshold is NOT reached.
     *   4. _issuerWallet calls cancelOffer — on a failed book this reclaims both
     *      available AND reserved inventory and marks the offer cancelled.
     *
     * Purpose: prove the failed-book recovery path where a fundraising offer
     *          never reaches its threshold, allowing the issuer to reclaim both
     *          unreserved and reserved inventory after expiry.
     */
    function test_e2e_marketplace_failedBook_cancelOffer_closesInterest() public {
        uint256 issuerBalanceBefore = IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId);

        uint256 offerId = _registerInterestDiscoveryOffer(_FULL_AMOUNT);

        uint256 escrowAfterRegister = IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId);
        assertEq(escrowAfterRegister, _FULL_AMOUNT, "escrow funded on register");
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId), 0, "issuer empty after register");

        uint256 interestId = _expressInterest(offerId, _QUARTER_AMOUNT, _buyerWallet);
        assertEq(uint8(_getInterest(interestId).status), uint8(InterestStatus.EXPRESSED));

        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        assertEq(state.interestedUnits, _QUARTER_AMOUNT, "interestedUnits");
        assertEq(state.reservedInterestUnits, _QUARTER_AMOUNT, "reservedInterestUnits");

        vm.warp(block.timestamp + OFFER_EXPIRY + 1);

        _cancelOffer(offerId, _issuerWallet);

        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId), issuerBalanceBefore, "issuer fully recovered"
        );
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), 0, "escrow empty");

        Offer memory finalOffer = _getOffer(offerId);
        assertEq(finalOffer.amounts.available, 0, "available zeroed");

        assertEq(uint8(_getInterest(interestId).status), uint8(InterestStatus.CLOSED), "lens: CLOSED after failed book");

        InterestDiscoveryState memory stateAfter = _getInterestDiscoveryState(offerId);
        assertEq(stateAfter.reservedInterestUnits, 0, "reserved zeroed");
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_marketplace_failedBook_multipleInvestors_closesAllReservedInterest
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. Offer requires FULL_AMOUNT to succeed.
     *   2. Two investors express a combined HALF_AMOUNT, below threshold.
     *   3. After expiry, issuer withdraws failed-book inventory.
     *
     * Purpose: prove failed-book closeout handles multiple reserved interests
     *          and releases all escrowed inventory.
     */
    function test_e2e_marketplace_failedBook_multipleInvestors_closesAllReservedInterest() public {
        uint256 issuerBalanceBefore = IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId);
        uint256 offerId = _registerInterestDiscoveryOffer(_FULL_AMOUNT);

        uint256 interestId1 = _expressInterest(offerId, _QUARTER_AMOUNT, _buyerWallet);
        uint256 interestId2 = _expressInterest(offerId, _QUARTER_AMOUNT, _secondBuyerWallet);

        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        assertEq(state.interestedUnits, _HALF_AMOUNT, "interested");
        assertEq(state.reservedInterestUnits, _HALF_AMOUNT, "reserved");

        Offer memory offer = _getOffer(offerId);
        vm.warp(offer.expiry + 1);

        _cancelOffer(offerId, _issuerWallet);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId), issuerBalanceBefore);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), 0, "escrow empty");
        assertEq(uint8(_getInterest(interestId1).status), uint8(InterestStatus.CLOSED), "interest1 closed");
        assertEq(uint8(_getInterest(interestId2).status), uint8(InterestStatus.CLOSED), "interest2 closed");

        InterestDiscoveryState memory stateAfter = _getInterestDiscoveryState(offerId);
        assertEq(stateAfter.reservedInterestUnits, 0, "reserved zeroed");
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_marketplace_thresholdReached_closeExpiredInterests_withdrawUnreserved_and_settleActiveDeal
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. Offer registered with minSaleUnits = QUARTER_AMOUNT.
     *   2. _buyerWallet expresses HALF_AMOUNT; _secondBuyerWallet expresses QUARTER_AMOUNT.
     *      Both interests are EXPRESSED; interestedUnits = 3/4. Threshold reached.
     *   3. After saleEnd, _buyerWallet's interest is activated (HALF_AMOUNT deal created).
     *   4. Payment is confirmed for the active deal before its payment deadline.
     *   5. Warp past activationDeadline.
     *   6. Issuer calls closeExpiredInterests for _secondBuyerWallet's unactivated interest.
     *      Released QUARTER_AMOUNT returns to offer.amounts.available.
     *   7. Issuer withdraws the now-unreserved available QUARTER_AMOUNT.
     *   8. Active deal settles; _buyerWallet receives HALF_AMOUNT.
     *
     * Purpose: prove the mixed-outcome fundraising path where one expressed
     *          interest activates into a live deal, another expires unactivated,
     *          and the issuer can close the expired interest, withdraw the
     *          released inventory, and still settle the active deal.
     */
    function test_e2e_marketplace_thresholdReached_closeExpiredInterests_withdrawUnreserved_and_settleActiveDeal()
        public
    {
        _approveEscrowOperator(_secondBuyerWallet);

        uint256 issuerBalanceBefore = IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId);
        uint256 offerId = _registerInterestDiscoveryOffer(_QUARTER_AMOUNT);

        uint256 interestId1 = _expressInterest(offerId, _HALF_AMOUNT, _buyerWallet);
        uint256 interestId2 = _expressInterest(offerId, _QUARTER_AMOUNT, _secondBuyerWallet);

        InterestDiscoveryState memory stateAfterBoth = _getInterestDiscoveryState(offerId);
        assertEq(stateAfterBoth.interestedUnits, _HALF_AMOUNT + _QUARTER_AMOUNT);
        assertEq(stateAfterBoth.reservedInterestUnits, _HALF_AMOUNT + _QUARTER_AMOUNT);

        Offer memory offerMid = _getOffer(offerId);
        assertEq(offerMid.amounts.available, _QUARTER_AMOUNT);

        vm.warp(block.timestamp + OFFER_EXPIRY + 1);

        uint256 dealId = _activateInterest(interestId1, _buyerWallet);
        assertEq(uint8(_getInterest(interestId1).status), uint8(InterestStatus.ACTIVATED));

        _resolvePayment(dealId, true);

        vm.warp(_activationDeadline(offerId) + 1);

        uint256[] memory toClose = new uint256[](1);
        toClose[0] = interestId2;

        _closeExpiredInterests(offerId, toClose, _issuerWallet);

        assertEq(uint8(_getInterest(interestId2).status), uint8(InterestStatus.CLOSED));

        Offer memory offerAfterClose = _getOffer(offerId);
        assertEq(offerAfterClose.amounts.available, _HALF_AMOUNT, "available after close");

        InterestDiscoveryState memory stateAfterClose = _getInterestDiscoveryState(offerId);
        assertEq(stateAfterClose.reservedInterestUnits, 0, "reserved zeroed after close");

        _withdrawAvailable(offerId, _issuerWallet);

        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId),
            issuerBalanceBefore - _HALF_AMOUNT,
            "issuer recovered unreserved"
        );

        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _HALF_AMOUNT);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), 0, "escrow empty");

        Offer memory finalOffer = _getOffer(offerId);
        assertEq(finalOffer.amounts.sold, _HALF_AMOUNT, "sold");
        assertEq(finalOffer.amounts.inDeals, 0, "inDeals");
        assertEq(finalOffer.amounts.available, 0, "available");

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));
    }
}
