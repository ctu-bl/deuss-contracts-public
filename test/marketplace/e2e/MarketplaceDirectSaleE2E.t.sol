// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {SharedE2EFixture} from "test/fixtures/SharedE2EFixture.t.sol";
import {IMarketplace} from "src/marketplace/interfaces/IMarketplace.sol";
import {
    CounterOfferInput,
    Deal,
    DealStatus,
    Offer,
    OfferInput,
    PaymentResolutionInput,
    SaleMode
} from "src/marketplace/MarketStructs.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";
import {Errors} from "src/libs/Errors.sol";

contract MarketplaceDirectSaleE2ETest is SharedE2EFixture {
    /*//////////////////////////////////////////////////////////////
                        SCENARIO CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 private constant _SALE_AMOUNT = OFFER_LOT * 4;
    uint256 private constant _BATCH_DEAL_AMOUNT = OFFER_LOT * 2;

    /*//////////////////////////////////////////////////////////////
      test_e2e_directSale_allowlist_blocksNonBuyer_and_allowlistedBuyer_settles
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. issuerWallet registers a MARKETPLACE offer with a buyer allowlist.
     *   2. _secondBuyerWallet cannot accept the offer or create a counter-offer.
     *   3. _buyerWallet is allowlisted, accepts the offer, pays, and settles.
     *
     * Purpose: prove direct-sale allowlists are enforced at the marketplace
     *          boundary while the allowlisted buyer can still complete the full
     *          paid settlement journey.
     */
    function test_e2e_directSale_allowlist_blocksNonBuyer_and_allowlistedBuyer_settles() public {
        address[] memory allowedBuyers = _singleAllowedBuyer(_buyerWallet);

        uint256 offerId = _registerDirectOffer(_SALE_AMOUNT, allowedBuyers, SaleMode.MARKETPLACE, true);
        _assertStoredAllowedBuyer(offerId, _buyerWallet);
        _assertNonBuyerBlocked(offerId);

        uint256 dealId = _acceptAndSettleOffer(offerId, _SALE_AMOUNT, _buyerWallet);
        _assertSuccessfulSale(offerId, dealId, _buyerWallet, _SALE_AMOUNT);
    }

    function _assertNonBuyerBlocked(uint256 offerId) internal {
        vm.prank(_secondBuyerWallet);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__BuyerNotAllowed.selector, offerId, _secondBuyerWallet)
        );
        IMarketplace(_marketplace).acceptOffer(offerId, _SALE_AMOUNT);

        vm.prank(_secondBuyerWallet);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__BuyerNotAllowed.selector, offerId, _secondBuyerWallet)
        );
        IMarketplace(_marketplace)
            .createCounterOffer(
                CounterOfferInput({
                offerId: offerId,
                expiry: block.timestamp + COUNTER_OFFER_EXPIRY,
                amount: OFFER_LOT,
                unitPrice: OFFER_UNIT_PRICE
            })
            );
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_redemption_allowlistedBuyer_settles_and_unpaidPath_returnsWithdrawableInventory
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. issuerWallet registers a REDEMPTION offer for _buyerWallet.
     *   2. _buyerWallet accepts, payment is confirmed, and the deal settles.
     *   3. A second REDEMPTION offer is accepted but expires unpaid.
     *   4. The unpaid deal restores inventory to the offer and the issuer cancels
     *      the offer to withdraw the returned bonds.
     *
     * Purpose: prove redemption-mode allowlist settlement and the failed-payment
     *          recovery path that returns inventory to the issuer.
     */
    function test_e2e_redemption_allowlistedBuyer_settles_and_unpaidPath_returnsWithdrawableInventory() public {
        address[] memory allowedBuyers = _singleAllowedBuyer(_buyerWallet);

        uint256 paidDealId = _registerAndSettlePaidRedemption(allowedBuyers);
        _assertSuccessfulDeal(paidDealId, _buyerWallet, _SALE_AMOUNT);

        _assertUnpaidRedemptionReturnsInventory(allowedBuyers);
    }

    function _registerAndSettlePaidRedemption(address[] memory allowedBuyers) internal returns (uint256 dealId) {
        uint256 offerId = _registerDirectOffer(_SALE_AMOUNT, allowedBuyers, SaleMode.REDEMPTION, false);
        dealId = _acceptAndSettleOffer(offerId, _SALE_AMOUNT, _buyerWallet);
    }

    function _assertUnpaidRedemptionReturnsInventory(address[] memory allowedBuyers) internal {
        uint256 issuerBalanceBeforeFailedOffer = IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId);

        uint256 failedOfferId = _registerDirectOffer(_SALE_AMOUNT, allowedBuyers, SaleMode.REDEMPTION, false);
        uint256 failedDealId = _acceptOffer(failedOfferId, _SALE_AMOUNT, _buyerWallet);

        Deal memory failedDeal = _getDeal(failedDealId);
        vm.warp(failedDeal.paymentDeadline + 1);
        _resolvePayment(failedDealId, false);

        failedDeal = _getDeal(failedDealId);
        vm.warp(failedDeal.disputeBuffer + 1);
        _settleDeal(failedDealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _SALE_AMOUNT);
        assertEq(uint8(_getDeal(failedDealId).status), uint8(DealStatus.UNSUCCESSFUL));

        Offer memory restoredOffer = _getOffer(failedOfferId);
        assertEq(restoredOffer.amounts.available, _SALE_AMOUNT);
        assertEq(restoredOffer.amounts.inDeals, 0);
        assertEq(restoredOffer.amounts.sold, 0);

        _cancelOffer(failedOfferId, _issuerWallet);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId), issuerBalanceBeforeFailedOffer);
        assertTrue(_isOfferCancelled(failedOfferId));
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_resolvePayments_mixedOutcomes_skipsInvalid_and_restoresInventory
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. Two buyers accept a direct marketplace offer.
     *   2. The first deal is initially marked UNPAID after the payment deadline.
     *   3. resolvePayments corrects the first deal to PAID, marks the second deal
     *      UNPAID, and skips an invalid deal id without reverting the batch.
     *   4. The paid deal settles to the buyer; the unpaid deal later restores
     *      inventory to the offer after its dispute buffer.
     *
     * Purpose: prove the batched payment-resolution operator flow across mixed
     *          paid/unpaid outcomes and per-item failure isolation.
     */
    function test_e2e_resolvePayments_mixedOutcomes_skipsInvalid_and_restoresInventory() public {
        uint256 offerId = _registerDirectOffer(_BATCH_DEAL_AMOUNT * 3, new address[](0), SaleMode.MARKETPLACE, true);

        uint256 latePaidDealId = _acceptOffer(offerId, _BATCH_DEAL_AMOUNT, _buyerWallet);
        uint256 unpaidDealId = _acceptOffer(offerId, _BATCH_DEAL_AMOUNT, _secondBuyerWallet);

        _markDealUnpaidAfterDeadline(latePaidDealId);
        _resolveMixedPayments(latePaidDealId, unpaidDealId);

        assertEq(uint8(_getDeal(latePaidDealId).status), uint8(DealStatus.PAID));
        assertEq(uint8(_getDeal(unpaidDealId).status), uint8(DealStatus.UNPAID));

        _settleDeal(latePaidDealId);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _BATCH_DEAL_AMOUNT);

        _settleAfterDisputeBuffer(unpaidDealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_secondBuyerWallet, _bondFTId), 0);
        assertEq(uint8(_getDeal(unpaidDealId).status), uint8(DealStatus.UNSUCCESSFUL));

        Offer memory offer = _getOffer(offerId);
        assertEq(offer.amounts.available, _BATCH_DEAL_AMOUNT * 2);
        assertEq(offer.amounts.inDeals, 0);
        assertEq(offer.amounts.sold, _BATCH_DEAL_AMOUNT);
    }

    function _singleAllowedBuyer(address buyer) internal pure returns (address[] memory allowedBuyers) {
        allowedBuyers = new address[](1);
        allowedBuyers[0] = buyer;
    }

    function _assertStoredAllowedBuyer(uint256 offerId, address buyer) internal view {
        address[] memory storedAllowedBuyers = _getAllowedBuyers(offerId);
        assertEq(storedAllowedBuyers.length, 1);
        assertEq(storedAllowedBuyers[0], buyer);
    }

    function _acceptAndSettleOffer(uint256 offerId, uint256 amount, address buyer) internal returns (uint256 dealId) {
        dealId = _acceptOffer(offerId, amount, buyer);
        _resolvePayment(dealId, true);
        _settleDeal(dealId);
    }

    function _assertSuccessfulDeal(uint256 dealId, address buyer, uint256 amount) internal view {
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(buyer, _bondFTId), amount);
        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));
    }

    function _assertSuccessfulSale(uint256 offerId, uint256 dealId, address buyer, uint256 amount) internal view {
        _assertSuccessfulDeal(dealId, buyer, amount);

        Offer memory offer = _getOffer(offerId);
        assertEq(offer.amounts.available, 0);
        assertEq(offer.amounts.inDeals, 0);
        assertEq(offer.amounts.sold, amount);
    }

    function _markDealUnpaidAfterDeadline(uint256 dealId) internal {
        Deal memory deal = _getDeal(dealId);
        vm.warp(deal.paymentDeadline + 1);
        _resolvePayment(dealId, false);
    }

    function _resolveMixedPayments(uint256 latePaidDealId, uint256 unpaidDealId) internal {
        uint256 invalidDealId = type(uint256).max;
        PaymentResolutionInput[] memory resolutions = new PaymentResolutionInput[](3);
        resolutions[0] = PaymentResolutionInput({dealId: latePaidDealId, paid: true});
        resolutions[1] = PaymentResolutionInput({dealId: unpaidDealId, paid: false});
        resolutions[2] = PaymentResolutionInput({dealId: invalidDealId, paid: false});

        vm.expectEmit(true, true, true, false);
        emit IMarketplace.PaymentResolutionSkipped(invalidDealId, false, _paymentProvider, "");
        vm.expectEmit(true, true, true, true);
        emit IMarketplace.PaymentResolutionsBatchProcessed(_paymentProvider, 3, 2, 1);
        _resolvePayments(resolutions);
    }

    function _settleAfterDisputeBuffer(uint256 dealId) internal {
        Deal memory deal = _getDeal(dealId);
        vm.warp(deal.disputeBuffer + 1);
        _settleDeal(dealId);
    }

    function _registerDirectOffer(
        uint256 amount,
        address[] memory allowedBuyers,
        SaleMode saleMode,
        bool allowCounterOffers
    ) internal returns (uint256 offerId) {
        OfferInput memory input = OfferInput({
            tokenAddress: _tokenAddr,
            tokenId: _bondFTId,
            totalAmount: amount,
            lot: OFFER_LOT,
            unitPrice: OFFER_UNIT_PRICE,
            currency: BOND_CURRENCY_BYTES3,
            expiry: block.timestamp + OFFER_EXPIRY,
            allowCounterOffers: allowCounterOffers,
            allowedBuyers: allowedBuyers,
            saleMode: saleMode,
            minSaleUnits: 0
        });

        vm.prank(_issuerWallet);
        offerId = IMarketplace(_marketplace).registerOffer(input);
    }
}
