// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable gas-small-strings */

import {SharedE2EFixture} from "test/fixtures/SharedE2EFixture.t.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {Deal, DealStatus, OfferInput, PaymentResolutionInput, SaleMode} from "src/marketplace/MarketStructs.sol";
import {Bond, BondStatus, BurnKind} from "src/registry/BondStructs.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";
import {StringExtensions} from "src/libs/StringExtensions.sol";
import {Errors} from "src/libs/Errors.sol";

contract MarketplaceRedemptionE2ETest is SharedE2EFixture {
    using StringExtensions for string;

    uint8 private constant _BOND_VERSION = 1;
    uint256 private constant _FIRST_REDEMPTION_AMOUNT = 120;
    uint256 private constant _SECOND_REDEMPTION_AMOUNT = 80;
    uint256 private constant _BATCH_FIRST_REDEMPTION_AMOUNT = 4_000;
    uint256 private constant _BATCH_SECOND_REDEMPTION_AMOUNT = 6_000;
    uint256 private constant _UNPAID_REDEMPTION_AMOUNT = 90;

    /**
     * Scenario:
     *   1. _buyerWallet acquires the full issued bond supply through the marketplace.
     *   2. _buyerWallet registers a REDEMPTION offer allowlisting only _issuerWallet.
     *   3. A non-allowlisted wallet cannot accept the redemption offer.
     *   4. _issuerWallet accepts, payment is resolved as paid, and settlement returns the bonds to issuer custody.
     *   5. _issuerWallet burns the redeemed bonds as FINAL_SETTLEMENT.
     *   6. A close-role actor closes the zero-supply bond into Redeemed status.
     *
     * Purpose: replace the removed BondLifecycleManager maturity-redemption happy path
     *          with the current Marketplace REDEMPTION + BondRegistry burn/close flow.
     */
    function test_e2e_marketAcquiredBond_fullRedemption_paid_burned_closed() public {
        _acquireFromMarketplace(_buyerWallet, BOND_ISSUE_COUNT);

        uint256 offerId = _registerRedemptionOffer(_buyerWallet, BOND_ISSUE_COUNT, _issuerWallet);

        vm.prank(_secondBuyerWallet);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__BuyerNotAllowed.selector, offerId, _secondBuyerWallet)
        );
        Marketplace(_marketplace).acceptOffer(offerId, BOND_ISSUE_COUNT);

        uint256 dealId = _acceptOffer(offerId, BOND_ISSUE_COUNT, _issuerWallet);
        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), 0, "holder redeemed balance");
        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId), BOND_ISSUE_COUNT, "issuer redeemed balance"
        );
        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL), "redemption deal status");

        _burnIssuerBalance(BOND_ISSUE_COUNT);

        assertEq(IDEUSSToken(_tokenAddr).totalSupply(_bondFTId), 0, "supply after final settlement burn");

        address closeActor = makeAddr("redemptionCloseActor");
        _grantRoles(_brAddr, closeActor, _br.CLOSE());

        vm.prank(closeActor);
        _br.closeBond(BOND_ISIN_ERC6909_FT, _BOND_VERSION);

        Bond memory bond = _br.getBondAtVersion(BOND_ISIN_ERC6909_FT._isinToBytes12(), _BOND_VERSION);
        assertEq(uint8(bond.status), uint8(BondStatus.Redeemed), "bond closed as redeemed");
    }

    /**
     * Scenario:
     *   1. Two holders acquire bonds through separate marketplace deals.
     *   2. Each holder registers a REDEMPTION offer allowlisting _issuerWallet.
     *   3. _issuerWallet accepts and settles both redemption offers.
     *   4. _issuerWallet batch-burns the redeemed inventory as FINAL_SETTLEMENT.
     *   5. closeBond still reverts because unreedeemed supply remains outstanding.
     *
     * Purpose: prove multi-holder partial redemption can be settled and burned
     *          without prematurely closing the bond lifecycle.
     */
    function test_e2e_multipleHolders_partialRedemption_batchBurn_supplyRemainsIssued() public {
        uint256 offerId = _registerOffer();

        uint256 firstDeal = _acceptOffer(offerId, _FIRST_REDEMPTION_AMOUNT, _buyerWallet);
        _resolvePayment(firstDeal, true);
        _settleDeal(firstDeal);

        uint256 secondDeal = _acceptOffer(offerId, _SECOND_REDEMPTION_AMOUNT, _secondBuyerWallet);
        _resolvePayment(secondDeal, true);
        _settleDeal(secondDeal);

        _approveEscrowOperator(_buyerWallet);
        _approveEscrowOperator(_secondBuyerWallet);

        uint256 firstRedemption = _registerRedemptionOffer(_buyerWallet, _FIRST_REDEMPTION_AMOUNT, _issuerWallet);
        uint256 secondRedemption =
            _registerRedemptionOffer(_secondBuyerWallet, _SECOND_REDEMPTION_AMOUNT, _issuerWallet);

        uint256 firstRedemptionDeal = _acceptOffer(firstRedemption, _FIRST_REDEMPTION_AMOUNT, _issuerWallet);
        _resolvePayment(firstRedemptionDeal, true);
        _settleDeal(firstRedemptionDeal);

        uint256 secondRedemptionDeal = _acceptOffer(secondRedemption, _SECOND_REDEMPTION_AMOUNT, _issuerWallet);
        _resolvePayment(secondRedemptionDeal, true);
        _settleDeal(secondRedemptionDeal);

        uint256 redeemedAmount = _FIRST_REDEMPTION_AMOUNT + _SECOND_REDEMPTION_AMOUNT;
        _burnIssuerBalanceBatch(_FIRST_REDEMPTION_AMOUNT, _SECOND_REDEMPTION_AMOUNT);

        assertEq(
            IDEUSSToken(_tokenAddr).totalSupply(_bondFTId),
            BOND_MAX_SUPPLY - redeemedAmount,
            "partial redemption supply"
        );

        address closeActor = makeAddr("partialRedemptionCloseActor");
        _grantRoles(_brAddr, closeActor, _br.CLOSE());

        vm.prank(closeActor);
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__TotalSupplyNotZero.selector));
        _br.closeBond(BOND_ISIN_ERC6909_FT, _BOND_VERSION);

        Bond memory bond = _br.getBondAtVersion(BOND_ISIN_ERC6909_FT._isinToBytes12(), _BOND_VERSION);
        assertEq(uint8(bond.status), uint8(BondStatus.Issued), "partially redeemed bond remains issued");
    }

    /**
     * Scenario:
     *   1. Two holders acquire the full issued bond supply through marketplace deals.
     *   2. Each holder registers a REDEMPTION offer allowlisting _issuerWallet.
     *   3. _issuerWallet accepts both redemption offers.
     *   4. The payment provider resolves both redemption payments in one resolvePayments batch.
     *   5. Both redemption deals settle, _issuerWallet batch-burns all redeemed supply, and closeBond marks Redeemed.
     *
     * Purpose: prove full multi-holder redemption can be resolved through the batched payment API
     *          and then completed through BondRegistry burn and close.
     */
    function test_e2e_multipleHolders_fullRedemption_batchedPaymentResolution_burned_closed() public {
        uint256 offerId = _registerOffer();

        uint256 firstDeal = _acceptOffer(offerId, _BATCH_FIRST_REDEMPTION_AMOUNT, _buyerWallet);
        _resolvePayment(firstDeal, true);
        _settleDeal(firstDeal);

        uint256 secondDeal = _acceptOffer(offerId, _BATCH_SECOND_REDEMPTION_AMOUNT, _secondBuyerWallet);
        _resolvePayment(secondDeal, true);
        _settleDeal(secondDeal);

        _approveEscrowOperator(_buyerWallet);
        _approveEscrowOperator(_secondBuyerWallet);

        uint256 firstRedemption = _registerRedemptionOffer(_buyerWallet, _BATCH_FIRST_REDEMPTION_AMOUNT, _issuerWallet);
        uint256 secondRedemption =
            _registerRedemptionOffer(_secondBuyerWallet, _BATCH_SECOND_REDEMPTION_AMOUNT, _issuerWallet);

        uint256 firstRedemptionDeal = _acceptOffer(firstRedemption, _BATCH_FIRST_REDEMPTION_AMOUNT, _issuerWallet);
        uint256 secondRedemptionDeal = _acceptOffer(secondRedemption, _BATCH_SECOND_REDEMPTION_AMOUNT, _issuerWallet);

        _resolvePaymentsBatchPaid(firstRedemptionDeal, secondRedemptionDeal);

        assertEq(uint8(_getDeal(firstRedemptionDeal).status), uint8(DealStatus.PAID), "first redemption paid");
        assertEq(uint8(_getDeal(secondRedemptionDeal).status), uint8(DealStatus.PAID), "second redemption paid");

        _settleDeal(firstRedemptionDeal);
        _settleDeal(secondRedemptionDeal);

        _burnIssuerBalanceBatch(_BATCH_FIRST_REDEMPTION_AMOUNT, _BATCH_SECOND_REDEMPTION_AMOUNT);

        assertEq(IDEUSSToken(_tokenAddr).totalSupply(_bondFTId), 0, "fully redeemed supply burned");

        address closeActor = makeAddr("batchRedemptionCloseActor");
        _grantRoles(_brAddr, closeActor, _br.CLOSE());

        vm.prank(closeActor);
        _br.closeBond(BOND_ISIN_ERC6909_FT, _BOND_VERSION);

        Bond memory bond = _br.getBondAtVersion(BOND_ISIN_ERC6909_FT._isinToBytes12(), _BOND_VERSION);
        assertEq(uint8(bond.status), uint8(BondStatus.Redeemed), "batch-redeemed bond closed");
    }

    /**
     * Scenario:
     *   1. _buyerWallet acquires bonds and offers them for REDEMPTION to _issuerWallet.
     *   2. _issuerWallet accepts but payment is resolved as unpaid after the deadline.
     *   3. After the dispute buffer expires, the unpaid deal settles back into the redemption offer.
     *   4. _buyerWallet cancels the offer and withdraws the returned inventory.
     *
     * Purpose: prove the failed redemption path returns escrowed bonds to the holder
     *          instead of transferring or burning them.
     */
    function test_e2e_redemption_unpaid_returnsInventoryToHolder() public {
        _acquireFromMarketplace(_buyerWallet, _UNPAID_REDEMPTION_AMOUNT);

        uint256 issuerBalanceBefore = IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId);
        uint256 totalSupplyBefore = IDEUSSToken(_tokenAddr).totalSupply(_bondFTId);

        uint256 offerId = _registerRedemptionOffer(_buyerWallet, _UNPAID_REDEMPTION_AMOUNT, _issuerWallet);
        uint256 dealId = _acceptOffer(offerId, _UNPAID_REDEMPTION_AMOUNT, _issuerWallet);

        Deal memory deal = _getDeal(dealId);
        vm.warp(deal.paymentDeadline + 1);
        _resolvePayment(dealId, false);

        deal = _getDeal(dealId);
        vm.warp(deal.disputeBuffer + 1);
        _settleDeal(dealId);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.UNSUCCESSFUL));

        _cancelOffer(offerId, _buyerWallet);

        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId),
            _UNPAID_REDEMPTION_AMOUNT,
            "holder inventory restored"
        );
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId), issuerBalanceBefore, "issuer unchanged");
        assertEq(IDEUSSToken(_tokenAddr).totalSupply(_bondFTId), totalSupplyBefore, "supply unchanged");
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _acquireFromMarketplace(address holder, uint256 amount) internal {
        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, amount, holder);
        _resolvePayment(dealId, true);
        _settleDeal(dealId);
        _approveEscrowOperator(holder);
    }

    function _registerRedemptionOffer(address holder, uint256 amount, address allowedBuyer)
        internal
        returns (uint256 offerId)
    {
        address[] memory allowedBuyers = new address[](1);
        allowedBuyers[0] = allowedBuyer;

        OfferInput memory input = OfferInput({
            tokenAddress: _tokenAddr,
            tokenId: _bondFTId,
            totalAmount: amount,
            lot: OFFER_LOT,
            unitPrice: OFFER_UNIT_PRICE,
            currency: BOND_CURRENCY_BYTES3,
            expiry: block.timestamp + OFFER_EXPIRY,
            allowCounterOffers: false,
            allowedBuyers: allowedBuyers,
            saleMode: SaleMode.REDEMPTION,
            minSaleUnits: 0
        });

        vm.prank(holder);
        offerId = Marketplace(_marketplace).registerOffer(input);
    }

    function _burnIssuerBalance(uint256 amount) internal {
        vm.prank(_issuerWallet);
        _br.burnBond(
            BOND_ISIN_ERC6909_FT._isinToBytes12(), _BOND_VERSION, _issuerWallet, amount, BurnKind.FINAL_SETTLEMENT
        );
    }

    function _burnIssuerBalanceBatch(uint256 firstAmount, uint256 secondAmount) internal {
        address[] memory froms = new address[](2);
        froms[0] = _issuerWallet;
        froms[1] = _issuerWallet;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = firstAmount;
        amounts[1] = secondAmount;

        vm.prank(_issuerWallet);
        _br.burnBondBatch(
            BOND_ISIN_ERC6909_FT._isinToBytes12(), _BOND_VERSION, froms, amounts, BurnKind.FINAL_SETTLEMENT
        );
    }

    function _resolvePaymentsBatchPaid(uint256 firstDealId, uint256 secondDealId) internal {
        PaymentResolutionInput[] memory resolutions = new PaymentResolutionInput[](2);
        resolutions[0] = PaymentResolutionInput({dealId: firstDealId, paid: true});
        resolutions[1] = PaymentResolutionInput({dealId: secondDealId, paid: true});

        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayments(resolutions);
    }
}
