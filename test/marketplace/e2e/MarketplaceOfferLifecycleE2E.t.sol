// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {SharedE2EFixture} from "test/fixtures/SharedE2EFixture.t.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {DealStatus, Deal, Offer, PaymentResolutionInput} from "src/marketplace/MarketStructs.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";

contract MarketplaceOfferLifecycleE2ETest is SharedE2EFixture {
    /*//////////////////////////////////////////////////////////////
                        SCENARIO CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 private constant _FULL_AMOUNT = BOND_ISSUE_COUNT;
    uint256 private constant _HALF_AMOUNT = _FULL_AMOUNT / 2;
    uint256 private constant _QUARTER_AMOUNT = _FULL_AMOUNT / 4;

    /*//////////////////////////////////////////////////////////////
                    test_e2e_offer_fullFill_paid_settled
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. _issuerWallet registers an offer for the full issue volume.
     *   2. _buyerWallet accepts the full amount, creating a single pending deal.
     *   3. _paymentProvider marks the deal paid.
     *   4. The settler settles the deal and releases all bonds to the buyer.
     *
     * Purpose: prove the basic happy path for an Marketplace offer where
     *          one buyer consumes the full inventory and the deal completes
     *          cleanly through payment confirmation and settlement.
     */
    function test_e2e_offer_fullFill_paid_settled() public {
        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, _FULL_AMOUNT, _buyerWallet);

        _resolvePayment(dealId, true);

        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId), 0);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), 0);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _FULL_AMOUNT);

        Offer memory offer = _getOffer(offerId);
        assertEq(offer.amounts.available, 0);
        assertEq(offer.amounts.inDeals, 0);
        assertEq(offer.amounts.sold, _FULL_AMOUNT);

        Deal memory deal = _getDeal(dealId);
        assertEq(uint8(deal.status), uint8(DealStatus.SUCCESSFUL));
    }

    /*//////////////////////////////////////////////////////////////
            test_e2e_offer_partialMultiBuyer_inventoryAccounting
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. _issuerWallet registers an offer for the full issue volume.
     *   2. _buyerWallet accepts half the inventory.
     *   3. _secondBuyerWallet accepts the remaining half.
     *   4. Both deals are marked paid and then settled in sequence.
     *
     * Purpose: prove that offer inventory accounting stays coherent across
     *          multiple concurrent buyers, partial fills, and staggered
     *          settlements.
     */
    function test_e2e_offer_partialMultiBuyer_inventoryAccounting() public {
        uint256 offerId = _registerOffer();

        uint256 deal1 = _acceptOffer(offerId, _HALF_AMOUNT, _buyerWallet);

        Offer memory mid1 = _getOffer(offerId);
        assertEq(mid1.amounts.available, _HALF_AMOUNT, "available after first accept");
        assertEq(mid1.amounts.inDeals, _HALF_AMOUNT, "inDeals after first accept");
        assertEq(mid1.amounts.sold, 0, "sold after first accept");

        uint256 deal2 = _acceptOffer(offerId, _HALF_AMOUNT, _secondBuyerWallet);

        Offer memory mid2 = _getOffer(offerId);
        assertEq(mid2.amounts.available, 0, "available after second accept");
        assertEq(mid2.amounts.inDeals, _FULL_AMOUNT, "inDeals after second accept");
        assertEq(mid2.amounts.sold, 0, "sold after second accept");

        _resolvePayment(deal1, true);
        _settleDeal(deal1);

        Offer memory mid3 = _getOffer(offerId);
        assertEq(mid3.amounts.inDeals, _HALF_AMOUNT, "inDeals after first settlement");
        assertEq(mid3.amounts.sold, _HALF_AMOUNT, "sold after first settlement");

        _resolvePayment(deal2, true);
        _settleDeal(deal2);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _HALF_AMOUNT);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_secondBuyerWallet, _bondFTId), _HALF_AMOUNT);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), 0);

        Offer memory final_ = _getOffer(offerId);
        assertEq(final_.amounts.available, 0);
        assertEq(final_.amounts.inDeals, 0);
        assertEq(final_.amounts.sold, _FULL_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
            test_e2e_offer_unpaid_dispute_paid_settled
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. _buyerWallet accepts part of the offer and opens a pending deal.
     *   2. The payment deadline passes and the deal is marked UNPAID.
     *   3. _buyerWallet initiates a dispute.
     *   4. The arbitrator resolves the dispute as PAID, after which the deal is settled.
     *
     * Purpose: prove that an unpaid deal can still resolve successfully through
     *          arbitration, and that settlement follows the arbitrated PAID
     *          outcome rather than the initial unpaid mark.
     */
    function test_e2e_offer_unpaid_dispute_paid_settled() public {
        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, _QUARTER_AMOUNT, _buyerWallet);

        Deal memory dealSnap = _getDeal(dealId);
        vm.warp(dealSnap.paymentDeadline + 1);

        _resolvePayment(dealId, false);

        _initiateDispute(dealId, _buyerWallet);

        _resolveDisputeID(dealId, DealStatus.PAID);

        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _QUARTER_AMOUNT);

        Offer memory offer = _getOffer(offerId);
        assertEq(offer.amounts.sold, _QUARTER_AMOUNT);
        assertEq(offer.amounts.available, _FULL_AMOUNT - _QUARTER_AMOUNT);
        assertEq(offer.amounts.inDeals, 0);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_offer_unpaid_dispute_unpaid_restore_and_withdrawAvailable
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. _buyerWallet accepts part of the offer and leaves the deal pending.
     *   2. The payment deadline passes and the deal is marked UNPAID.
     *   3. _buyerWallet disputes the unpaid result.
     *   4. The arbitrator confirms UNPAID, the issuer cancels the offer, and
     *      the failed deal later settles back into the cancelled offer.
     *   5. _issuerWallet withdraws the inventory that returned after settlement.
     *
     * Purpose: prove the failed-payment recovery path where a disputed deal is
     *          ultimately resolved as unpaid, inventory flows back to the
     *          cancelled offer, and the issuer can reclaim the remaining bonds.
     */
    function test_e2e_offer_unpaid_dispute_unpaid_restore_and_withdrawAvailable() public {
        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, _QUARTER_AMOUNT, _buyerWallet);

        uint256 issuerBalanceBefore = IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId);
        uint256 escrowBalanceBefore = IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId);

        Deal memory dealSnap = _getDeal(dealId);
        vm.warp(dealSnap.paymentDeadline + 1);
        _resolvePayment(dealId, false);

        _initiateDispute(dealId, _buyerWallet);

        _resolveDisputeID(dealId, DealStatus.UNPAID);

        _cancelOffer(offerId, _issuerWallet);

        dealSnap = _getDeal(dealId);
        vm.warp(dealSnap.disputeBuffer + 1);
        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), 0);
        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.UNSUCCESSFUL));

        Offer memory offer = _getOffer(offerId);
        assertEq(offer.amounts.available, _QUARTER_AMOUNT);
        assertEq(offer.amounts.inDeals, 0);
        assertEq(offer.amounts.sold, 0);

        _withdrawAvailable(offerId, _issuerWallet);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId), issuerBalanceBefore + _FULL_AMOUNT);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), escrowBalanceBefore - _FULL_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
       test_e2e_offer_cancelWithActiveDeal_dealStillSettles
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. _issuerWallet registers an offer for the full issue volume.
     *   2. _buyerWallet accepts _QUARTER_AMOUNT, leaving the rest still available.
     *   3. _issuerWallet cancels the offer while that deal is still pending.
     *   4. The available inventory is returned immediately, but the pending deal
     *      remains active, is marked paid, and settles normally.
     *
     * Purpose: prove that offer cancellation only pulls back free inventory and
     *          does not invalidate or unwind an already-open deal that still has
     *          to complete through the normal payment and settlement flow.
     */
    function test_e2e_offer_cancelWithActiveDeal_dealStillSettles() public {
        uint256 issuerBefore = IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId);

        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, _QUARTER_AMOUNT, _buyerWallet);

        Offer memory snap = _getOffer(offerId);
        assertEq(snap.amounts.available, _FULL_AMOUNT - _QUARTER_AMOUNT, "available after accept");
        assertEq(snap.amounts.inDeals, _QUARTER_AMOUNT, "inDeals after accept");
        _cancelOffer(offerId, _issuerWallet);

        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId),
            issuerBefore - _QUARTER_AMOUNT,
            "issuer recovered available"
        );
        assertTrue(_isOfferCancelled(offerId), "offer cancelled");

        Offer memory snapAfterCancel = _getOffer(offerId);
        assertEq(snapAfterCancel.amounts.available, 0, "available zeroed");
        assertEq(snapAfterCancel.amounts.inDeals, _QUARTER_AMOUNT, "inDeals unaffected");

        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _QUARTER_AMOUNT, "buyer received bond amount"
        );

        Offer memory finalOffer = _getOffer(offerId);
        assertEq(finalOffer.amounts.inDeals, 0, "inDeals cleared after settlement");
        assertEq(finalOffer.amounts.sold, _QUARTER_AMOUNT, "sold reflects settled deal");

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL), "deal SUCCESSFUL");
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_offer_unpaid_latePaidAfterDeadline_settled
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. _buyerWallet accepts part of the offer and a pending deal is created.
     *   2. The payment deadline passes and the deal is marked UNPAID.
     *   3. Before any dispute is opened, the payment handler corrects the record
     *      and marks the same deal PAID.
     *   4. The deal then settles successfully.
     *
     * Purpose: prove the contract accepts the late-paid correction path from
     *          UNPAID back to PAID while no arbitration has started, allowing the
     *          deal to continue to normal settlement.
     */
    function test_e2e_offer_unpaid_latePaidAfterDeadline_settled() public {
        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, _QUARTER_AMOUNT, _buyerWallet);

        Deal memory snap = _getDeal(dealId);
        vm.warp(snap.paymentDeadline + 1);

        _resolvePayment(dealId, false);

        _resolvePayment(dealId, true);

        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _QUARTER_AMOUNT);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), _FULL_AMOUNT - _QUARTER_AMOUNT);

        Offer memory offer = _getOffer(offerId);
        assertEq(offer.amounts.sold, _QUARTER_AMOUNT);
        assertEq(offer.amounts.available, _FULL_AMOUNT - _QUARTER_AMOUNT);
        assertEq(offer.amounts.inDeals, 0);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_offer_batchedPaymentResolution_skipsInvalid_and_settlesValid
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. Two marketplace deals are opened from the same offer.
     *   2. The first deal is resolved and settled before the batch runs.
     *   3. resolvePayments is called for both deals in one batch.
     *   4. The already-settled deal is skipped internally, while the pending deal is marked PAID.
     *   5. The valid batch item settles normally.
     *
     * Purpose: prove the batched payment API works for normal marketplace deals
     *          and isolates invalid items without blocking valid resolutions.
     */
    function test_e2e_offer_batchedPaymentResolution_skipsInvalid_and_settlesValid() public {
        uint256 offerId = _registerOffer();
        uint256 settledDealId = _acceptOffer(offerId, _QUARTER_AMOUNT, _buyerWallet);
        uint256 pendingDealId = _acceptOffer(offerId, _QUARTER_AMOUNT, _secondBuyerWallet);

        _resolvePayment(settledDealId, true);
        _settleDeal(settledDealId);

        PaymentResolutionInput[] memory resolutions = new PaymentResolutionInput[](2);
        resolutions[0] = PaymentResolutionInput({dealId: settledDealId, paid: true});
        resolutions[1] = PaymentResolutionInput({dealId: pendingDealId, paid: true});

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayments(resolutions);

        assertEq(uint8(_getDeal(settledDealId).status), uint8(DealStatus.SUCCESSFUL), "settled deal unchanged");
        assertEq(uint8(_getDeal(pendingDealId).status), uint8(DealStatus.PAID), "pending deal paid");

        _settleDeal(pendingDealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _QUARTER_AMOUNT);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_secondBuyerWallet, _bondFTId), _QUARTER_AMOUNT);

        Offer memory finalOffer = _getOffer(offerId);
        assertEq(finalOffer.amounts.sold, _HALF_AMOUNT);
        assertEq(finalOffer.amounts.inDeals, 0);
        assertEq(finalOffer.amounts.available, _HALF_AMOUNT);
    }
}
