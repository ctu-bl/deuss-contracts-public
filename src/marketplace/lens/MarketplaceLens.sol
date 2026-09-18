// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Initializable} from "solady/src/utils/Initializable.sol";
import {Errors} from "../../libs/Errors.sol";
import {OwnableRolesExtension} from "../../utils/OwnableRolesExtension.sol";
import {Deal, Interest, InterestDiscoveryState, InterestStatus, Offer} from "../MarketStructs.sol";
import {IMarketplaceLens} from "../interfaces/IMarketplaceLens.sol";
import {IMarketplaceLensSource} from "../interfaces/IMarketplaceLensSource.sol";

/**
 * @title MarketplaceLens
 * @author DEUSS Team
 * @notice Read-only helper contract exposing the user-facing getter API for one Marketplace instance
 * @dev Thin view layer over `IMarketplaceLensSource` (the live `Marketplace`); no custody or state
 *      changes. Useful for UIs/indexers to batch reads without duplicating logic on-chain.
 */
contract MarketplaceLens is IMarketplaceLens, Initializable, OwnableRolesExtension {
    /// @inheritdoc IMarketplaceLens
    address public marketplace;

    /**
     * @notice Locks any future initializations or reinitializations on the implementation contract
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the lens
     * @param owner_ Owner address for upgrade authorization
     * @param marketplace_ Marketplace proxy address
     */
    function initialize(address owner_, address marketplace_) external initializer {
        require(owner_ != address(0), Errors.ZeroAddress());
        require(marketplace_ != address(0), Errors.ZeroAddress());
        _initializeOwner(owner_);
        marketplace = marketplace_;
    }

    /**
     * @inheritdoc IMarketplaceLens
     */
    function isOfferCancelled(uint256 offerId) external view returns (bool cancelled) {
        // slither-disable-next-line unused-return
        (cancelled,,) = _source().getOfferFlags(offerId);
    }

    /**
     * @inheritdoc IMarketplaceLens
     */
    function getOffer(uint256 offerId) external view returns (Offer memory offer) {
        // slither-disable-next-line unused-return
        (offer,,,,) = _source().getOfferData(offerId);
    }

    /**
     * @inheritdoc IMarketplaceLens
     */
    function getAllowedBuyers(uint256 offerId) external view returns (address[] memory allowedBuyers) {
        // slither-disable-next-line unused-return
        (,,, allowedBuyers,) = _source().getOfferData(offerId);
    }

    /**
     * @inheritdoc IMarketplaceLens
     */
    function getDeal(uint256 dealId) external view returns (Deal memory deal) {
        // slither-disable-next-line unused-return
        (deal,) = _source().getDealData(dealId);
    }

    /**
     * @inheritdoc IMarketplaceLens
     */
    function getInterest(uint256 interestId) external view returns (Interest memory interest) {
        interest = _source().getInterestData(interestId);
        if (interest.status != InterestStatus.EXPRESSED) {
            return interest;
        }

        // Lazy projection: offer-level reserved seizure takes precedence
        // slither-disable-next-line unused-return
        (bool cancelled,, bool reservedInterestSeized) = _source().getOfferFlags(interest.offerId);
        if (reservedInterestSeized) {
            interest.status = InterestStatus.SEIZED;
            return interest;
        }

        // slither-disable-next-line unused-return
        (Offer memory offer, InterestDiscoveryState memory state,,,) = _source().getOfferData(interest.offerId);
        // slither-disable-next-line timestamp
        if (
            !_hasReachedThreshold(state.interestedUnits, state.minSaleUnits)
                && (cancelled || block.timestamp > offer.expiry) && state.reservedInterestUnits == 0
                && offer.amounts.available == 0
        ) {
            interest.status = InterestStatus.CLOSED;
        }
    }

    /**
     * @inheritdoc IMarketplaceLens
     */
    function getInterestIdsByOfferId(uint256 offerId) external view returns (uint256[] memory interestIds) {
        // slither-disable-next-line unused-return
        (,, interestIds,,) = _source().getOfferData(offerId);
    }

    /**
     * @inheritdoc IMarketplaceLens
     */
    function getInterestDiscoveryState(uint256 offerId) external view returns (InterestDiscoveryState memory state) {
        // slither-disable-next-line unused-return
        (, state,,,) = _source().getOfferData(offerId);
    }

    /**
     * @inheritdoc IMarketplaceLens
     */
    function isOfferFrozen(uint256 offerId) external view returns (bool frozen) {
        // slither-disable-next-line unused-return
        (, frozen,) = _source().getOfferFlags(offerId);
    }

    /**
     * @inheritdoc IMarketplaceLens
     */
    function isDealFrozen(uint256 dealId) external view returns (bool frozen) {
        // slither-disable-next-line unused-return
        (, frozen) = _source().getDealData(dealId);
    }

    /**
     * @inheritdoc IMarketplaceLens
     */
    function getEscrowIdByOfferId(uint256 offerId) external view returns (uint256 escrowId) {
        // slither-disable-next-line unused-return
        (,,,, escrowId) = _source().getOfferData(offerId);
    }

    /**
     * @inheritdoc IMarketplaceLens
     */
    function isReservedInterestSeized(uint256 offerId) external view returns (bool seized) {
        // slither-disable-next-line unused-return
        (,, seized) = _source().getOfferFlags(offerId);
    }

    /**
     * @notice Returns the typed source interface for the linked Marketplace contract
     * @return source Lens-source interface bound to `marketplace`
     */
    function _source() internal view returns (IMarketplaceLensSource source) {
        return IMarketplaceLensSource(marketplace);
    }

    /**
     * @notice Return whether cumulative expressed interest has reached the configured threshold
     * @param interestedUnits Cumulative expressed-interest amount
     * @param minSaleUnits Configured minimum threshold
     * @return reached True when `interestedUnits >= minSaleUnits`
     */
    function _hasReachedThreshold(uint256 interestedUnits, uint256 minSaleUnits) internal pure returns (bool reached) {
        return minSaleUnits - 1 < interestedUnits;
    }
}
