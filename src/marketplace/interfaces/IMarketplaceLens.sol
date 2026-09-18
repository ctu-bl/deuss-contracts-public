// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Deal, Interest, InterestDiscoveryState, Offer} from "../MarketStructs.sol";

/**
 * @title IMarketplaceLens
 * @author DEUSS Team
 * @notice Read-only external API for Marketplace state
 */
interface IMarketplaceLens {
    /**
     * @notice Returns the Marketplace contract this lens reads from
     * @return marketplace Address of the linked Marketplace proxy
     */
    function marketplace() external view returns (address marketplace);

    /**
     * @notice Returns whether an offer has been cancelled
     * @param offerId Offer identifier
     * @return cancelled True if offer was explicitly cancelled
     */
    function isOfferCancelled(uint256 offerId) external view returns (bool cancelled);

    /**
     * @notice Get offer details by ID
     * @param offerId The ID of the offer to retrieve
     * @return offer The complete offer structure containing all offer data
     */
    function getOffer(uint256 offerId) external view returns (Offer memory offer);

    /**
     * @notice Returns the direct-sale allowlist configured for an offer
     * @param offerId The offer identifier
     * @return allowedBuyers Array of allowlisted buyer accounts
     */
    function getAllowedBuyers(uint256 offerId) external view returns (address[] memory allowedBuyers);

    /**
     * @notice Get deal details by ID
     * @param dealId The ID of the deal to retrieve
     * @return deal The complete deal structure containing all deal data
     */
    function getDeal(uint256 dealId) external view returns (Deal memory deal);

    /**
     * @notice Get interest details by ID
     * @param interestId The ID of the interest to retrieve
     * @return interest The interest structure using lens-level effective-status projection
     * @dev Raw stored `EXPRESSED` interests may be projected as `CLOSED` (failed-book closeout)
     *      or `SEIZED` (offer-level reserved seizure)
     */
    function getInterest(uint256 interestId) external view returns (Interest memory interest);

    /**
     * @notice Get all interest IDs linked to an offer
     * @param offerId The offer identifier
     * @return interestIds Array of linked interest IDs
     */
    function getInterestIdsByOfferId(uint256 offerId) external view returns (uint256[] memory interestIds);

    /**
     * @notice Get interest-discovery-specific state by offer ID
     * @param offerId The offer identifier
     * @return state The interest-discovery state for the offer
     */
    function getInterestDiscoveryState(uint256 offerId) external view returns (InterestDiscoveryState memory state);

    /**
     * @notice Returns whether an offer is currently frozen
     * @param offerId Offer identifier
     * @return frozen True if the offer is frozen
     */
    function isOfferFrozen(uint256 offerId) external view returns (bool frozen);

    /**
     * @notice Returns whether a deal is currently frozen
     * @param dealId Deal identifier
     * @return frozen True if the deal is frozen
     */
    function isDealFrozen(uint256 dealId) external view returns (bool frozen);

    /**
     * @notice Gets the escrow ID for an offer
     * @param offerId Offer identifier
     * @return escrowId EscrowManager escrow ID linked to the offer
     */
    function getEscrowIdByOfferId(uint256 offerId) external view returns (uint256 escrowId);

    /**
     * @notice Returns whether all reserved interests for an offer were seized at the offer level
     * @param offerId Offer identifier
     * @return seized True when the reserved interest bucket was seized via `seizeOfferEscrow`
     */
    function isReservedInterestSeized(uint256 offerId) external view returns (bool seized);
}
