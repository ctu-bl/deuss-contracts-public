// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable gas-small-strings */

import {SharedE2EFixture} from "test/fixtures/SharedE2EFixture.t.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {DealStatus, Deal, InterestDiscoveryState, Offer} from "src/marketplace/MarketStructs.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";
import {Errors} from "src/libs/Errors.sol";

contract MarketplaceGovernanceE2ETest is SharedE2EFixture {
    /*//////////////////////////////////////////////////////////////
                           SCENARIO CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 private constant _FULL_AMOUNT = BOND_ISSUE_COUNT;
    uint256 private constant _QUARTER_AMOUNT = _FULL_AMOUNT / 4;

    bytes32 private constant _SEIZURE_REASON = keccak256("SEIZURE");

    /*//////////////////////////////////////////////////////////////
      test_e2e_offerFrozen_acceptBlocked_thenUnfrozen_paid_settled
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. issuerWallet registers an offer.
     *   2. _freezer freezes the offer (compliance hold).
     *   3. _buyerWallet attempts to accept → reverts; freeze is an operational pause.
     *   4. _freezer lifts the freeze.
     *   5. _buyerWallet accepts, payment resolves, deal settles.
     *
     * Purpose: prove that an offer-level compliance freeze blocks new accepts
     *          without mutating inventory, and that once the freeze is lifted the
     *          normal payment and settlement path resumes unchanged.
     */
    function test_e2e_offerFrozen_acceptBlocked_thenUnfrozen_paid_settled() public {
        uint256 offerId = _registerOffer();

        _setOfferFrozen(offerId, true);

        assertTrue(_isOfferFrozen(offerId), "offer frozen");

        vm.prank(_buyerWallet);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferFrozen.selector, offerId));
        Marketplace(_marketplace).acceptOffer(offerId, _QUARTER_AMOUNT);

        Offer memory snap = _getOffer(offerId);
        assertEq(snap.amounts.available, _FULL_AMOUNT, "available unchanged while frozen");
        assertEq(snap.amounts.inDeals, 0, "inDeals unchanged while frozen");

        _setOfferFrozen(offerId, false);

        assertFalse(_isOfferFrozen(offerId), "offer unfrozen");

        uint256 dealId = _acceptOffer(offerId, _QUARTER_AMOUNT, _buyerWallet);
        _resolvePayment(dealId, true);

        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _QUARTER_AMOUNT);

        Offer memory final_ = _getOffer(offerId);
        assertEq(final_.amounts.sold, _QUARTER_AMOUNT);
        assertEq(final_.amounts.available, _FULL_AMOUNT - _QUARTER_AMOUNT);
        assertEq(final_.amounts.inDeals, 0);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));
    }

    /*//////////////////////////////////////////////////////////////
       test_e2e_partiallyFilledOffer_frozen_availableSeized_inFlightDealStillSettles
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. issuerWallet registers an offer; _buyerWallet accepts 1/4 (PENDING deal).
     *   2. Compliance freezes the offer and seizes only the remaining 3/4 available
     *      inventory to a beneficiary.
     *   3. Offer is unfrozen so the in-flight deal can continue.
     *   4. paymentProvider marks the pending deal paid; deal settles.
     *
     * Purpose: prove that governance can confiscate only the free inventory on a
     *          partially-filled offer while preserving the already-committed deal
     *          slice, which can still complete after the freeze is lifted.
     */
    function test_e2e_partiallyFilledOffer_frozen_availableSeized_inFlightDealStillSettles() public {
        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, _QUARTER_AMOUNT, _buyerWallet);

        Offer memory midSnap = _getOffer(offerId);
        assertEq(midSnap.amounts.available, _FULL_AMOUNT - _QUARTER_AMOUNT);
        assertEq(midSnap.amounts.inDeals, _QUARTER_AMOUNT);

        uint256 escrowAfterAccept = IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId);

        _setOfferFrozen(offerId, true);

        address seizureBeneficiary = makeAddr("seizureBeneficiary");
        _createAndRegisterEntityWallet(_erAdmin, seizureBeneficiary);
        uint256 expectedSeized = _FULL_AMOUNT - _QUARTER_AMOUNT;

        _seizeAvailable(offerId, seizureBeneficiary, _SEIZURE_REASON);

        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(seizureBeneficiary, _bondFTId),
            expectedSeized,
            "beneficiary received seized"
        );
        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId),
            escrowAfterAccept - expectedSeized,
            "escrow: only in-deal slice"
        );

        assertTrue(_isOfferCancelled(offerId), "offer cancelled after seize");
        Offer memory afterSeize = _getOffer(offerId);
        assertEq(afterSeize.amounts.available, 0);
        assertEq(afterSeize.amounts.inDeals, _QUARTER_AMOUNT, "inDeals untouched by seize");

        _setOfferFrozen(offerId, false);

        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _QUARTER_AMOUNT, "buyer receives their portion"
        );
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), 0, "escrow fully cleared");

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));

        Offer memory final_ = _getOffer(offerId);
        assertEq(final_.amounts.available, 0);
        assertEq(final_.amounts.inDeals, 0);
        assertEq(final_.amounts.sold, _QUARTER_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
        test_e2e_paidDeal_frozen_and_seized_transfersDealInventory_toBeneficiary
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. issuerWallet registers an offer; _buyerWallet accepts 1/4; payment is
     *      marked PAID before settlement.
     *   2. Compliance freezes both the offer and the deal.
     *   3. Seizure role seizes the committed 1/4 deal amount to a beneficiary.
     *
     * Purpose: prove the governance seizure path for already-committed deal
     *          inventory, where a paid but unsettled deal is forcibly redirected
     *          to a beneficiary instead of the buyer.
     */
    function test_e2e_paidDeal_frozen_and_seized_transfersDealInventory_toBeneficiary() public {
        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, _QUARTER_AMOUNT, _buyerWallet);

        _resolvePayment(dealId, true);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.PAID));

        _setOfferFrozen(offerId, true);
        _setDealFrozen(dealId, true);

        assertTrue(_isOfferFrozen(offerId), "offer frozen");
        assertTrue(_isDealFrozen(dealId), "deal frozen");

        address seizureBeneficiary = makeAddr("dealSeizureBeneficiary");
        _createAndRegisterEntityWallet(_erAdmin, seizureBeneficiary);

        _seizeDeal(dealId, seizureBeneficiary, _SEIZURE_REASON);

        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(seizureBeneficiary, _bondFTId),
            _QUARTER_AMOUNT,
            "beneficiary received deal amount"
        );
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), 0, "buyer receives nothing");
        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId),
            _FULL_AMOUNT - _QUARTER_AMOUNT,
            "escrow: available inventory"
        );

        Deal memory seizedDeal = _getDeal(dealId);
        assertEq(uint8(seizedDeal.status), uint8(DealStatus.SEIZED));

        Offer memory offer = _getOffer(offerId);
        assertEq(offer.amounts.inDeals, 0, "inDeals cleared by seizeDeal");
        assertEq(offer.amounts.sold, 0, "sold not incremented on seizure");
        assertEq(offer.amounts.available, _FULL_AMOUNT - _QUARTER_AMOUNT, "available unchanged by seizeDeal");
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_paidDeal_frozen_settlementBlocked_thenUnfrozenSettles
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. A deal is accepted and marked PAID.
     *   2. Compliance freezes the deal before settlement.
     *   3. Settlement reverts while the deal is frozen.
     *   4. Compliance unfreezes the deal and settlement succeeds.
     *
     * Purpose: prove deal freezes block normal settlement, not only new accepts
     *          or seizure flows.
     */
    function test_e2e_paidDeal_frozen_settlementBlocked_thenUnfrozenSettles() public {
        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, _QUARTER_AMOUNT, _buyerWallet);
        _resolvePayment(dealId, true);

        _setDealFrozen(dealId, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DealFrozen.selector, dealId));
        _settleDeal(dealId);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.PAID), "deal remains paid");
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), 0, "buyer not settled while frozen");

        _setDealFrozen(dealId, false);
        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _QUARTER_AMOUNT);
        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_marketplace_frozen_reservedInterestSeized_toBeneficiary
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. An INTEREST_DISCOVERY offer has both available and reserved inventory.
     *   2. Compliance freezes the offer.
     *   3. Seizure claims both free inventory and the reserved-interest bucket.
     *
     * Purpose: prove the governance seizure path handles fundraising reservations,
     *          where reserved inventory is released in aggregate without activating deals.
     */
    function test_e2e_marketplace_frozen_reservedInterestSeized_toBeneficiary() public {
        uint256 offerId = _registerInterestDiscoveryOffer(_FULL_AMOUNT);
        uint256 interestId = _expressInterest(offerId, _QUARTER_AMOUNT, _buyerWallet);

        InterestDiscoveryState memory stateBefore = _getInterestDiscoveryState(offerId);
        assertEq(stateBefore.reservedInterestUnits, _QUARTER_AMOUNT, "reserved before seizure");

        _setOfferFrozen(offerId, true);

        address seizureBeneficiary = makeAddr("interestSeizureBeneficiary");
        _createAndRegisterEntityWallet(_erAdmin, seizureBeneficiary);

        _seizeAvailable(offerId, seizureBeneficiary, _SEIZURE_REASON);

        (bool cancelled,, bool reservedInterestSeized) = Marketplace(_marketplace).getOfferFlags(offerId);
        assertTrue(cancelled, "offer cancelled");
        assertTrue(reservedInterestSeized, "reserved bucket not marked seized");
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(seizureBeneficiary, _bondFTId), _FULL_AMOUNT);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), 0);

        Offer memory offer = _getOffer(offerId);
        assertEq(offer.amounts.available, 0, "available zeroed");
        assertEq(offer.amounts.inDeals, 0, "no activated deals");

        InterestDiscoveryState memory stateAfter = _getInterestDiscoveryState(offerId);
        assertEq(stateAfter.reservedInterestUnits, 0, "reserved zeroed");
        assertEq(_getInterest(interestId).amount, _QUARTER_AMOUNT, "interest record retained");
    }
}
