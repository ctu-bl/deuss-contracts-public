// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Deal, Interest, InterestDiscoveryState, Offer} from "./MarketStructs.sol";

/* solhint-disable max-states-count */

/**
 * @title MarketplaceStorage
 * @author DEUSS Team
 * @notice Storage contract for Marketplace that defines all state variables and constants
 * @dev This contract contains all storage variables used by Marketplace and MarketplaceBase
 * @dev Uses ERC-7201 namespaced storage for all mutable state
 */
abstract contract MarketplaceStorage {
    /**
     * @notice Runtime configuration
     */
    struct Config {
        /// @notice Offer expiry threshold in seconds
        uint256 offerExpiryThreshold;
        /// @notice Payment expiry threshold in seconds
        uint256 marketplacePaymentExpiryThreshold;
        /// @notice Payment expiry threshold in seconds for redemption deals
        uint256 redemptionPaymentExpiryThreshold;
        /// @notice Payment expiry threshold snapshotted into new interest-discovery offers
        uint256 interestDiscoveryPaymentExpiryThreshold;
        /// @notice Dispute buffer period in seconds
        uint256 disputeBufferPeriod;
        /// @notice Maximum number of counter offers allowed per user per offer
        uint256 maxCounterOffersPerUser;
        /// @notice Maximum lifetime for offers and counter offers in seconds
        uint256 maxOfferLifetime;
    }

    /**
     * @notice Monotonic counters used to generate marketplace identifiers
     */
    struct Counters {
        /// @notice Counter for generating unique offer IDs
        uint256 offerCounter;
        /// @notice Counter for generating unique deal IDs
        uint256 dealCounter;
        /// @notice Counter for generating unique interest IDs
        uint256 interestCounter;
    }

    /**
     * @notice All mutable Marketplace state.
     * @custom:storage-location erc7201:deuss.marketplace.storage
     */
    struct MarketplaceState {
        /// @notice Runtime configuration
        Config config;
        /// @notice Address of the configured asset manager contract
        address assetManager;
        /// @notice Monotonic identifier counters
        Counters counters;
        /// @notice Mapping of offer ID to Offer struct
        mapping(uint256 offerId => Offer offer) offers;
        /// @notice Mapping of deal ID to Deal struct
        mapping(uint256 dealId => Deal deal) deals;
        /// @notice Mapping of interest ID to Interest struct
        mapping(uint256 interestId => Interest interest) interests;
        /// @notice Mapping of accepted pricing currencies
        mapping(bytes3 currency => bool allowed) allowedCurrencies;
        /// @notice Mapping of offer ID to the explicit direct-sale allowlist
        mapping(uint256 offerId => address[] allowedBuyers) allowedBuyersByOfferId;
        /// @notice Constant-time allowlist membership check for direct-sale offers
        mapping(uint256 offerId => mapping(address buyer => bool allowed)) isAllowedBuyerByOfferId;
        /// @notice Mapping of user address to offer ID to counter offer count
        mapping(address user => mapping(uint256 offerId => uint256 count)) counterOfferCounts;
        /// @notice Mapping of offer ID to EscrowManager escrow ID
        mapping(uint256 offerId => uint256 escrowId) escrowIdByOfferId;
        /// @notice Mapping of offer ID to interest-discovery-specific state
        mapping(uint256 offerId => InterestDiscoveryState state) interestDiscoveryStateByOfferId;
        /// @notice Mapping of offer ID to the set of interest IDs expressed against that offer
        mapping(uint256 offerId => uint256[] interestIds) interestIdsByOfferId;
        /// @notice Mapping of offer ID to explicit cancellation status
        mapping(uint256 offerId => bool cancelled) offerCancelled;
        /// @notice Mapping of offer ID to frozen status
        mapping(uint256 offerId => bool frozen) offerFrozen;
        /// @notice Mapping of deal ID to frozen status
        mapping(uint256 dealId => bool frozen) dealFrozen;
        /// @notice Mapping of offer ID to offer-level reserved-interest seizure flag
        mapping(uint256 offerId => bool seized) reservedInterestSeized;
    }

    /**
     * @notice Minimum value for the offer expiry threshold configuration
     * @dev The offer expiry threshold must be at least this value
     */
    uint256 public constant MIN_OFFER_EXPIRY_THRESHOLD = 1 days;

    /**
     * @notice Maximum value for the minimum offer lifetime configuration
     * @dev The minimum offer lifetime must not exceed this value
     */
    uint256 public constant MAX_OFFER_EXPIRY_THRESHOLD = 10 days;

    /**
     * @notice Hard cap for the maximum lifetime of offers and counter offers
     * @dev The runtime maxOfferLifetime configuration must not exceed this value
     */
    uint256 public constant MAX_CONFIGURABLE_OFFER_LIFETIME = 365 days;

    /**
     * @notice Minimum value for the payment expiry threshold configuration
     * @dev The payment expiry threshold must be at least this value
     */
    uint256 public constant MIN_PAYMENT_EXPIRY_THRESHOLD = 1 days;

    /**
     * @notice Maximum value for the payment expiry threshold configuration
     * @dev The payment expiry threshold must not exceed this value
     */
    uint256 public constant MAX_PAYMENT_EXPIRY_THRESHOLD = 10 days;

    /**
     * @notice Minimum dispute buffer period in seconds
     * @dev Minimum time required for dispute buffer period configuration
     */
    uint256 public constant MIN_DISPUTE_BUFFER_PERIOD = 1 days;

    /**
     * @notice Maximum dispute buffer period in seconds
     * @dev Maximum time allowed for dispute buffer period configuration
     */
    uint256 public constant MAX_DISPUTE_BUFFER_PERIOD = 10 days;

    /**
     * @notice ERC-7201 storage location for all mutable marketplace state
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("deuss.marketplace.storage"))) - 1))
     *      & ~bytes32(uint256(0xff))
     */
    // slither-disable-next-line unused-state
    bytes32 internal constant _MARKETPLACE_STORAGE_LOCATION =
        0xf7a56b15168bcb08515667a141d475c0860a6405d548a81fdf3dd5a1c8926a00;

    /**
     * @notice Returns the namespaced marketplace storage
     * @return $ Namespaced marketplace storage pointer
     */
    // slither-disable-next-line uninitialized-storage,assembly
    function _marketplaceStorage() internal pure returns (MarketplaceState storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _MARKETPLACE_STORAGE_LOCATION
        }
    }
}
