// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore */

import {
    AssetType,
    Deal,
    Escrow,
    Interest,
    InterestDiscoveryState,
    Offer,
    SaleMode
} from "src/marketplace/MarketStructs.sol";
import {SnapshotTypes} from "./SnapshotTypes.sol";

/// @notice Before/after snapshot helpers and bounded consistency checks for marketplace fuzz actions.
abstract contract BeforeAfterMarketplace is SnapshotTypes {
    /*//////////////////////////////////////////////////////////////
                         MARKETPLACE SNAPSHOT
    //////////////////////////////////////////////////////////////*/

    function _setMarketplaceState(
        uint8 callNum,
        address[] memory actors,
        uint256[] memory offerIds,
        uint256[] memory dealIds,
        uint256[] memory interestIds
    ) internal {
        for (uint256 i; i < actors.length; ++i) {
            if (actors[i] == address(0)) continue;
            _setActorState(callNum, actors[i]);
        }

        for (uint256 i; i < offerIds.length; ++i) {
            if (offerIds[i] == 0) continue;
            _setOfferState(callNum, offerIds[i]);
        }

        for (uint256 i; i < dealIds.length; ++i) {
            if (dealIds[i] == 0) continue;
            _setDealState(callNum, dealIds[i]);
        }

        for (uint256 i; i < interestIds.length; ++i) {
            if (interestIds[i] == 0) continue;
            _setInterestState(callNum, interestIds[i]);
        }

        (uint256 trackedBalanceSum, bool allTrackedFrozenBalancesBounded) = _trackedBalanceSumAndFrozenBounded();
        (uint256 trackedEscrowAmountSum, bool allTrackedOffersBounded, bool allTrackedEscrowsMatchOfferHoldings) =
            _trackedEscrowSnapshot(callNum);

        states[callNum].trackedBalanceSum = trackedBalanceSum;
        states[callNum].escrowBalance = token.balanceOf(address(escrowManager), bondTokenId);
        states[callNum].trackedEscrowAmountSum = trackedEscrowAmountSum;
        states[callNum].escrowSweepable =
            escrowManager.getSweepableAmount(AssetType.ERC6909, address(token), bondTokenId);
        states[callNum].escrowReserved = states[callNum].escrowBalance > states[callNum].escrowSweepable
            ? states[callNum].escrowBalance - states[callNum].escrowSweepable
            : 0;
        states[callNum].nextEscrowId = escrowManager.nextEscrowId();
        states[callNum].totalSupply = token.totalSupply(bondTokenId);
        states[callNum].totalSupplyAtCurrentBlock = token.totalSupplyAt(bondTokenId, block.number);
        states[callNum].bondNominalValue = bondRegistry.getBondByTokenId(bondTokenId).bondNominalValue;
        states[callNum].trackedFaceValueSum = trackedBalanceSum * states[callNum].bondNominalValue;
        states[callNum].offerCounter = _getOfferCounter();
        states[callNum].dealCounter = _getDealCounter();
        states[callNum].interestCounter = _getInterestCounter();
        states[callNum].bondStatus = bondRegistry.bondStatus(BOND_ISIN);
        states[callNum].tokenPaused = token.paused();
        states[callNum].tokenIdPaused = token.isTokenPaused(bondTokenId);
        states[callNum].allTrackedFrozenBalancesBounded = allTrackedFrozenBalancesBounded;
        states[callNum].allTrackedOffersBounded = allTrackedOffersBounded;
        states[callNum].allTrackedEscrowsMatchOfferHoldings = allTrackedEscrowsMatchOfferHoldings;

        states[callNum].latestBondVersion = _getLatestBondVersion();
        states[callNum].activeBondVersion = _getActiveBondVersion();
    }

    function _trackedBalanceSumAndFrozenBounded()
        private
        view
        returns (uint256 trackedBalanceSum, bool allTrackedFrozenBalancesBounded)
    {
        uint256 harnessBalance = token.balanceOf(address(this), bondTokenId);
        uint256 escrowBalance = token.balanceOf(address(escrowManager), bondTokenId);

        trackedBalanceSum = harnessBalance + escrowBalance;
        allTrackedFrozenBalancesBounded = true;

        if (token.frozenBalanceOf(address(this), bondTokenId) > harnessBalance) {
            allTrackedFrozenBalancesBounded = false;
        }
        if (token.frozenBalanceOf(address(escrowManager), bondTokenId) > escrowBalance) {
            allTrackedFrozenBalancesBounded = false;
        }

        for (uint256 i; i < users.length; ++i) {
            uint256 userBalance = token.balanceOf(users[i], bondTokenId);
            trackedBalanceSum += userBalance;
            if (token.frozenBalanceOf(users[i], bondTokenId) > userBalance) {
                allTrackedFrozenBalancesBounded = false;
            }
        }
    }

    function _trackedEscrowSnapshot(uint8 callNum)
        private
        returns (uint256 trackedEscrowAmountSum, bool allTrackedOffersBounded, bool allTrackedEscrowsMatchOfferHoldings)
    {
        allTrackedOffersBounded = true;
        allTrackedEscrowsMatchOfferHoldings = true;

        (trackedEscrowAmountSum, allTrackedOffersBounded, allTrackedEscrowsMatchOfferHoldings) =
            _trackedOfferEscrowSnapshot();
        trackedEscrowAmountSum += _trackedStandaloneEscrowSnapshot(callNum);
    }

    function _trackedOfferEscrowSnapshot()
        private
        view
        returns (uint256 trackedEscrowAmountSum, bool allTrackedOffersBounded, bool allTrackedEscrowsMatchOfferHoldings)
    {
        allTrackedOffersBounded = true;
        allTrackedEscrowsMatchOfferHoldings = true;

        // Walk the bounded tracked-offer set in addition to the per-call IDs. This
        // gives broader invariant coverage without needing to enumerate all offers.
        for (uint256 i; i < knownOfferIds.length; ++i) {
            uint256 offerId = knownOfferIds[i];
            if (offerId == 0) continue;

            Offer memory offer = _getOffer(offerId);
            if (offer.owner == address(0)) continue;

            uint256 used = offer.amounts.available + offer.amounts.inDeals + offer.amounts.sold;
            if (used > offer.amounts.total) {
                allTrackedOffersBounded = false;
            }

            uint256 escrowId = _getEscrowIdByOfferId(offerId);
            if (escrowId == 0) continue;

            Escrow memory escrow = escrowManager.getEscrow(escrowId);
            trackedEscrowAmountSum += escrow.amount;
            if (escrow.amount != _trackedOfferEscrowAmount(offerId, offer)) {
                allTrackedEscrowsMatchOfferHoldings = false;
            }
        }
    }

    function _trackedStandaloneEscrowSnapshot(uint8 callNum) private returns (uint256 trackedEscrowAmountSum) {
        // Walk the bounded standalone escrow set for escrows created directly against
        // EscrowManager (outside the Marketplace offer flow) so balance
        // invariants stay consistent when both sources coexist.
        for (uint256 i; i < knownEscrowIds.length; ++i) {
            uint256 escrowId = knownEscrowIds[i];
            if (escrowId == 0) continue;

            Escrow memory escrow = escrowManager.getEscrow(escrowId);
            if (escrow.moduleType != FUZZ_ESCROW_TEST_MODULE_TYPE) continue;

            trackedEscrowAmountSum += escrow.amount;
            _setEscrowState(callNum, escrowId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         MARKETPLACE SETTERS
    //////////////////////////////////////////////////////////////*/

    function _setActorState(uint8 callNum, address actor) internal {
        states[callNum].actorStates[actor].balance = token.balanceOf(actor, bondTokenId);
        states[callNum].actorStates[actor].frozenBalance = token.frozenBalanceOf(actor, bondTokenId);
        states[callNum].actorStates[actor].balanceAtCurrentBlock = token.balanceOfAt(actor, bondTokenId, block.number);
        states[callNum].actorStates[actor].frozenBalanceAtCurrentBlock =
            token.frozenBalanceOfAt(actor, bondTokenId, block.number);
        states[callNum].actorStates[actor].availableBalanceAtCurrentBlock =
            token.availableBalanceOfAt(actor, bondTokenId, block.number);
        states[callNum].actorStates[actor].escrowApproved = token.isOperator(actor, address(escrowManager));
    }

    function _setOfferState(uint8 callNum, uint256 offerId) internal {
        (Offer memory offer, InterestDiscoveryState memory state,, address[] memory allowedBuyers,) =
            marketplace.getOfferData(offerId);
        (bool cancelled, bool frozen, bool reservedInterestSeized) = marketplace.getOfferFlags(offerId);
        uint256 escrowId = _getEscrowIdByOfferId(offerId);

        states[callNum].offerStates[offerId].owner = offer.owner;
        states[callNum].offerStates[offerId].escrowId = escrowId;
        states[callNum].offerStates[offerId].total = offer.amounts.total;
        states[callNum].offerStates[offerId].available = offer.amounts.available;
        states[callNum].offerStates[offerId].inDeals = offer.amounts.inDeals;
        states[callNum].offerStates[offerId].sold = offer.amounts.sold;
        states[callNum].offerStates[offerId].lot = offer.lot;
        states[callNum].offerStates[offerId].unitPrice = offer.unitPrice;
        states[callNum].offerStates[offerId].expiry = offer.expiry;
        states[callNum].offerStates[offerId].cancelled = cancelled;
        states[callNum].offerStates[offerId].frozen = frozen;
        states[callNum].offerStates[offerId].reservedInterestSeized = reservedInterestSeized;
        states[callNum].offerStates[offerId].allowCounterOffers = offer.allowCounterOffers;
        states[callNum].offerStates[offerId].saleMode = offer.saleMode;
        states[callNum].offerStates[offerId].minSaleUnits = state.minSaleUnits;
        states[callNum].offerStates[offerId].paymentExpiryThreshold = state.paymentExpiryThreshold;
        states[callNum].offerStates[offerId].interestedUnits = state.interestedUnits;
        states[callNum].offerStates[offerId].reservedInterestUnits = state.reservedInterestUnits;
        states[callNum].offerStates[offerId].allowedBuyerCount = allowedBuyers.length;
        states[callNum].offerStates[offerId].allowedBuyers = allowedBuyers;

        if (escrowId != 0) {
            // Offer snapshots pull in the linked escrow snapshot so offer-level and
            // escrow-level assertions use a consistent view of locked tokens.
            _setEscrowState(callNum, escrowId);
        }
    }

    function _setDealState(uint8 callNum, uint256 dealId) internal {
        (Deal memory deal, bool frozen) = marketplace.getDealData(dealId);

        states[callNum].dealStates[dealId].offerId = deal.offerId;
        states[callNum].dealStates[dealId].amount = deal.amount;
        states[callNum].dealStates[dealId].buyer = deal.buyer;
        states[callNum].dealStates[dealId].price = deal.price;
        states[callNum].dealStates[dealId].counterOfferExpiry = deal.counterOfferExpiry;
        states[callNum].dealStates[dealId].paymentDeadline = deal.paymentDeadline;
        states[callNum].dealStates[dealId].disputeBuffer = deal.disputeBuffer;
        states[callNum].dealStates[dealId].status = deal.status;
        states[callNum].dealStates[dealId].dealType = deal.dealType;
        states[callNum].dealStates[dealId].frozen = frozen;

        if (deal.offerId != 0) {
            // Deal postconditions also reason about the linked offer balances, so a
            // deal snapshot refreshes the corresponding offer transitively.
            _setOfferState(callNum, deal.offerId);
        }
    }

    function _setInterestState(uint8 callNum, uint256 interestId) internal {
        Interest memory interest = _getInterest(interestId);

        states[callNum].interestStates[interestId].offerId = interest.offerId;
        states[callNum].interestStates[interestId].amount = interest.amount;
        states[callNum].interestStates[interestId].investor = interest.investor;
        states[callNum].interestStates[interestId].price = interest.price;
        states[callNum].interestStates[interestId].status = uint8(interest.status);

        if (interest.offerId != 0) {
            _setOfferState(callNum, interest.offerId);
        }
    }

    function _setEscrowState(uint8 callNum, uint256 escrowId) internal {
        Escrow memory escrow = escrowManager.getEscrow(escrowId);

        states[callNum].escrowStates[escrowId].depositor = escrow.depositor;
        states[callNum].escrowStates[escrowId].tokenAddress = escrow.tokenAddress;
        states[callNum].escrowStates[escrowId].tokenId = escrow.tokenId;
        states[callNum].escrowStates[escrowId].amount = escrow.amount;
    }

    function _trackedOfferEscrowAmount(uint256 offerId, Offer memory offer) internal view returns (uint256 amount) {
        amount = offer.amounts.available + offer.amounts.inDeals;
        if (offer.saleMode == SaleMode.INTEREST_DISCOVERY) {
            amount += _getInterestDiscoveryState(offerId).reservedInterestUnits;
        }
    }
}
