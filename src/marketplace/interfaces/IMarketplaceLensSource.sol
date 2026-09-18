// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Deal, Interest, InterestDiscoveryState, Offer} from "../MarketStructs.sol";

/**
 * @title IMarketplaceLensSource
 * @author DEUSS Team
 * @notice Compact read surface exposed by Marketplace for external lens contracts
 */
interface IMarketplaceLensSource {
    /**
     * @notice Returns the grouped offer-side state required by the lens
     * @param offerId Offer identifier
     * @return offer Offer data snapshot
     * @return state Interest-discovery state snapshot
     * @return interestIds Interest identifiers linked to the offer
     * @return allowedBuyers Direct-sale allowlist linked to the offer
     * @return escrowId Escrow identifier linked to the offer
     */
    function getOfferData(uint256 offerId)
        external
        view
        returns (
            Offer memory offer,
            InterestDiscoveryState memory state,
            uint256[] memory interestIds,
            address[] memory allowedBuyers,
            uint256 escrowId
        );

    /**
     * @notice Returns grouped offer flags required by the lens
     * @param offerId Offer identifier
     * @return cancelled Explicit offer cancellation flag
     * @return frozen Offer frozen flag
     * @return reservedInterestSeized True when the reserved interest bucket was seized via `seizeOfferEscrow`
     */
    function getOfferFlags(uint256 offerId)
        external
        view
        returns (bool cancelled, bool frozen, bool reservedInterestSeized);

    /**
     * @notice Returns the grouped deal-side state required by the lens
     * @param dealId Deal identifier
     * @return deal Deal data snapshot
     * @return frozen Deal frozen flag
     */
    function getDealData(uint256 dealId) external view returns (Deal memory deal, bool frozen);

    /**
     * @notice Returns one interest snapshot required by the lens
     * @param interestId Interest identifier
     * @return interest Raw stored interest snapshot (no effective-status projection)
     */
    function getInterestData(uint256 interestId) external view returns (Interest memory interest);
}
