// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Errors} from "../libs/Errors.sol";
import {MarketplaceStorage} from "./MarketplaceStorage.sol";
import {EligibilityModuleBase} from "../base/EligibilityModuleBase.sol";

/**
 * @title MarketplaceBase
 * @author DEUSS Team
 * @notice Base contract for Marketplace that handles common functionality and storage
 * @dev Shared admin/config events and setters on top of `MarketplaceStorage` and `EligibilityModuleBase`
 *      (entity allowlists + dependency wiring). Role `ADMIN` governs configuration;
 *      `INTEREST_DISCOVERY_OPERATOR` covers operational maintenance (e.g. closing expired interests).
 */
contract MarketplaceBase is MarketplaceStorage, EligibilityModuleBase {
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a new currency is added to the allowed set
     * @param currency The currency that was added (as bytes3)
     */
    event CurrencyAdded(bytes3 indexed currency);
    /**
     * @notice Emitted when a currency is removed from the allowed set
     * @param currency The currency that was removed (as bytes3)
     */
    event CurrencyRemoved(bytes3 indexed currency);
    /**
     * @notice Emitted when the asset manager address is set with previous and new addresses
     * @param previousAssetManager The previous asset manager address
     * @param assetManager The address of the asset manager contract
     */
    event AssetManagerSet(address indexed previousAssetManager, address indexed assetManager);
    /**
     * @notice Emitted when the minimum offer lifetime is set
     * @param offerExpiryThreshold The new minimum offer lifetime in seconds
     */
    event OfferExpiryThresholdSet(uint256 indexed offerExpiryThreshold);
    /**
     * @notice Emitted when the maximum offer lifetime is set
     * @param maxOfferLifetime The new maximum offer lifetime in seconds
     */
    event MaxOfferLifetimeSet(uint256 indexed maxOfferLifetime);
    /**
     * @notice Emitted when the payment expiry threshold is set
     * @param expiryThreshold The new expiry threshold in seconds
     */
    event MarketplacePaymentExpiryThresholdSet(uint256 indexed expiryThreshold);
    /**
     * @notice Emitted when the activated interest-discovery payment expiry threshold is set
     * @param expiryThreshold The new expiry threshold in seconds
     */
    event InterestDiscoveryPaymentExpiryThresholdSet(uint256 indexed expiryThreshold);
    /**
     * @notice Emitted when the redemption payment expiry threshold is set
     * @param expiryThreshold The new expiry threshold in seconds
     */
    event RedemptionPaymentExpiryThresholdSet(uint256 indexed expiryThreshold);
    /**
     * @notice Emitted when the dispute buffer period is set
     * @param disputeBufferPeriod The new dispute buffer period in seconds
     */
    event DisputeBufferPeriodSet(uint256 indexed disputeBufferPeriod);
    /**
     * @notice Emitted when the global per-user counter-offer cap is updated
     * @param maxCounterOffers The new maximum number of counter offers allowed per user per offer
     */
    event MaxCounterOffersPerUserSet(uint256 indexed maxCounterOffers);

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Sets the asset manager address
     * @param assetManager The address of the asset manager contract
     * @dev Only callable by addresses with ADMIN role
     * @dev Reverts if assetManager is zero address
     * @dev Emits AssetManagerSet event on success
     */
    function setAssetManager(address assetManager) public onlyRoles(ADMIN) {
        require(assetManager != address(0), Errors.ZeroAddress());
        _setAssetManager(assetManager);
    }

    /**
     * @notice Adds a new currency to the allowed set
     * @param currency The currency code to add encoded as bytes3 (e.g., bytes3("EUR"))
     * @dev Only callable by addresses with ADMIN role
     * @dev Reverts if currency already exists in the set
     * @dev Emits CurrencyAdded event on success
     */
    function addCurrency(bytes3 currency) public onlyRoles(ADMIN) {
        MarketplaceState storage $ = _marketplaceStorage();
        require(!$.allowedCurrencies[currency], Errors.Marketplace__CurrencyAlreadyExists(currency));
        $.allowedCurrencies[currency] = true;

        emit CurrencyAdded(currency);
    }

    /**
     * @notice Removes a currency from the allowed set
     * @param currency The currency code to remove encoded as bytes3 (e.g., bytes3("EUR"))
     * @dev Only callable by addresses with ADMIN role
     * @dev Reverts if currency does not exist in the set
     * @dev Emits CurrencyRemoved event on success
     */
    function removeCurrency(bytes3 currency) public onlyRoles(ADMIN) {
        MarketplaceState storage $ = _marketplaceStorage();
        require($.allowedCurrencies[currency], Errors.Marketplace__CurrencyDoesNotExist(currency));
        delete $.allowedCurrencies[currency];

        emit CurrencyRemoved(currency);
    }

    /**
     * @notice Sets the minimum lifetime for registering new offers and counter offers
     * @param offerExpiryThreshold The new minimum lifetime in seconds
     * @dev Only callable by addresses with ADMIN role
     * @dev Reverts if offerExpiryThreshold is below MIN_OFFER_EXPIRY_THRESHOLD
     * @dev Reverts if offerExpiryThreshold exceeds MAX_OFFER_EXPIRY_THRESHOLD
     * @dev Reverts if offerExpiryThreshold exceeds the configured maxOfferLifetime
     * @dev Emits OfferExpiryThresholdSet event on success
     */
    function setOfferExpiryThreshold(uint256 offerExpiryThreshold) public onlyRoles(ADMIN) {
        _setOfferExpiryThreshold(offerExpiryThreshold);
    }

    /**
     * @notice Sets the maximum lifetime for registered offers and counter offers
     * @param maxOfferLifetime The new maximum lifetime in seconds
     * @dev Only callable by addresses with ADMIN role
     * @dev Reverts if maxOfferLifetime exceeds MAX_CONFIGURABLE_OFFER_LIFETIME
     * @dev Reverts if maxOfferLifetime is below the configured offerExpiryThreshold
     * @dev Emits MaxOfferLifetimeSet event on success
     */
    function setMaxOfferLifetime(uint256 maxOfferLifetime) public onlyRoles(ADMIN) {
        _setMaxOfferLifetime(maxOfferLifetime);
    }

    /**
     * @notice Sets the payment expiry threshold for offers
     * @param marketplacePaymentExpiryThreshold The new payment expiry threshold for marketplace deals in seconds
     * @dev Only callable by addresses with ADMIN role
     * @dev Reverts if marketplacePaymentExpiryThreshold is below MIN_PAYMENT_EXPIRY_THRESHOLD
     * @dev Reverts if marketplacePaymentExpiryThreshold exceeds MAX_PAYMENT_EXPIRY_THRESHOLD
     * @dev Emits MarketplacePaymentExpiryThresholdSet event on success
     */
    function setMarketplacePaymentExpiryThreshold(uint256 marketplacePaymentExpiryThreshold) public onlyRoles(ADMIN) {
        _setMarketplacePaymentExpiryThreshold(marketplacePaymentExpiryThreshold);
    }

    /**
     * @notice Sets the payment expiry threshold snapshotted into newly registered interest-discovery offers
     * @param paymentExpiryThreshold The new threshold for future interest-discovery offers in seconds
     * @dev Only callable by addresses with ADMIN role
     * @dev Reverts if paymentExpiryThreshold is below MIN_PAYMENT_EXPIRY_THRESHOLD
     * @dev Reverts if paymentExpiryThreshold exceeds MAX_PAYMENT_EXPIRY_THRESHOLD
     * @dev Emits InterestDiscoveryPaymentExpiryThresholdSet event on success
     */
    function setInterestDiscoveryPaymentExpiryThreshold(uint256 paymentExpiryThreshold) public onlyRoles(ADMIN) {
        _setInterestDiscoveryPaymentExpiryThreshold(paymentExpiryThreshold);
    }

    /**
     * @notice Sets the payment expiry threshold for redemption deals
     * @param paymentExpiryThreshold The new payment expiry threshold for accepted redemption deals in seconds
     * @dev Only callable by addresses with ADMIN role
     * @dev Reverts if paymentExpiryThreshold is below MIN_PAYMENT_EXPIRY_THRESHOLD
     * @dev Reverts if paymentExpiryThreshold exceeds MAX_PAYMENT_EXPIRY_THRESHOLD
     * @dev Emits RedemptionPaymentExpiryThresholdSet event on success
     */
    function setRedemptionPaymentExpiryThreshold(uint256 paymentExpiryThreshold) public onlyRoles(ADMIN) {
        _setRedemptionPaymentExpiryThreshold(paymentExpiryThreshold);
    }

    /**
     * @notice Sets the dispute buffer period
     * @param disputeBufferPeriod The new dispute buffer period in seconds
     * @dev Only callable by addresses with ADMIN role
     * @dev Reverts if disputeBufferPeriod is below MIN_DISPUTE_BUFFER_PERIOD
     * @dev Reverts if disputeBufferPeriod exceeds MAX_DISPUTE_BUFFER_PERIOD
     * @dev This period determines how long after payment deadline disputes can be initiated
     * @dev Emits DisputeBufferPeriodSet event on success
     */
    function setDisputeBufferPeriod(uint256 disputeBufferPeriod) public onlyRoles(ADMIN) {
        _setDisputeBufferPeriod(disputeBufferPeriod);
    }

    /**
     * @notice Sets the maximum number of counter offers allowed per user per offer
     * @param maxCounterOffers The maximum number of counter offers allowed
     * @dev Only callable by addresses with ADMIN role
     * @dev Reverts if maxCounterOffers is zero
     */
    function setMaxCounterOffersPerUser(uint256 maxCounterOffers) public onlyRoles(ADMIN) {
        _setMaxCounterOffersPerUser(maxCounterOffers);
    }

    /*//////////////////////////////////////////////////////////////
                            GETTERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Gets the configurable Marketplace parameters and runtime identifier counters
     * @return config ABI-safe snapshot of marketplace configuration values
     * @return counters ABI-safe snapshot of the latest assigned identifiers
     */
    function getConfigAndCounters() public view returns (Config memory config, Counters memory counters) {
        MarketplaceState storage $ = _marketplaceStorage();
        Config storage configStorage = $.config;
        Counters storage countersStorage = $.counters;

        config.offerExpiryThreshold = configStorage.offerExpiryThreshold;
        config.marketplacePaymentExpiryThreshold = configStorage.marketplacePaymentExpiryThreshold;
        config.redemptionPaymentExpiryThreshold = configStorage.redemptionPaymentExpiryThreshold;
        config.interestDiscoveryPaymentExpiryThreshold = configStorage.interestDiscoveryPaymentExpiryThreshold;
        config.disputeBufferPeriod = configStorage.disputeBufferPeriod;
        config.maxCounterOffersPerUser = configStorage.maxCounterOffersPerUser;
        config.maxOfferLifetime = configStorage.maxOfferLifetime;

        counters.offerCounter = countersStorage.offerCounter;
        counters.dealCounter = countersStorage.dealCounter;
        counters.interestCounter = countersStorage.interestCounter;
    }

    /**
     * @notice Returns whether a currency is currently allowed for pricing
     * @param currency Currency code encoded as bytes3
     * @return allowed True when the currency is enabled
     */
    function isCurrencyAllowed(bytes3 currency) public view returns (bool allowed) {
        return _marketplaceStorage().allowedCurrencies[currency];
    }

    /**
     * @notice Gets the number of counter offers a user has made for a specific offer
     * @param user The address of the user
     * @param offerId The ID of the offer
     * @return The number of counter offers the user has made for this offer
     */
    function getCounterOfferCount(address user, uint256 offerId) public view returns (uint256) {
        return _marketplaceStorage().counterOfferCounts[user][offerId];
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Sets the asset manager address internally
     * @param assetManager The address of the asset manager contract
     * @dev Internal function that updates storage and emits event
     * @dev Emits AssetManagerSet event
     */
    function _setAssetManager(address assetManager) internal {
        MarketplaceState storage $ = _marketplaceStorage();
        address previousAssetManager = $.assetManager;
        $.assetManager = assetManager;

        emit AssetManagerSet(previousAssetManager, assetManager);
    }

    /**
     * @notice Sets the minimum offer lifetime internally
     * @param offerExpiryThreshold The new minimum offer lifetime in seconds
     * @dev Internal function that validates and updates storage
     * @dev Reverts if offerExpiryThreshold is below MIN_OFFER_EXPIRY_THRESHOLD
     * @dev Reverts if offerExpiryThreshold exceeds MAX_OFFER_EXPIRY_THRESHOLD
     * @dev Reverts if offerExpiryThreshold exceeds the configured maxOfferLifetime
     * @dev Skips the maxOfferLifetime cross-check while maxOfferLifetime is unset during initialization
     * @dev Emits OfferExpiryThresholdSet event
     */
    function _setOfferExpiryThreshold(uint256 offerExpiryThreshold) internal {
        require(
            !(offerExpiryThreshold < MIN_OFFER_EXPIRY_THRESHOLD),
            Errors.Marketplace__OfferExpiryThresholdTooLow(offerExpiryThreshold)
        );
        require(
            !(offerExpiryThreshold > MAX_OFFER_EXPIRY_THRESHOLD),
            Errors.Marketplace__OfferExpiryThresholdTooHigh(offerExpiryThreshold)
        );
        Config storage config = _marketplaceStorage().config;
        uint256 maxOfferLifetime = config.maxOfferLifetime;
        if (maxOfferLifetime != 0) {
            require(
                !(offerExpiryThreshold > maxOfferLifetime),
                Errors.Marketplace__MaxOfferLifetimeBelowOfferExpiryThreshold(maxOfferLifetime, offerExpiryThreshold)
            );
        }
        config.offerExpiryThreshold = offerExpiryThreshold;

        emit OfferExpiryThresholdSet(offerExpiryThreshold);
    }

    /**
     * @notice Sets the maximum offer lifetime internally
     * @param maxOfferLifetime The new maximum lifetime in seconds
     * @dev Reverts if maxOfferLifetime exceeds MAX_CONFIGURABLE_OFFER_LIFETIME
     * @dev Reverts if maxOfferLifetime is below the configured offerExpiryThreshold
     * @dev Emits MaxOfferLifetimeSet event
     */
    function _setMaxOfferLifetime(uint256 maxOfferLifetime) internal {
        require(
            !(maxOfferLifetime > MAX_CONFIGURABLE_OFFER_LIFETIME),
            Errors.Marketplace__MaxOfferLifetimeTooHigh(maxOfferLifetime)
        );
        Config storage config = _marketplaceStorage().config;
        uint256 offerExpiryThreshold = config.offerExpiryThreshold;
        require(
            !(maxOfferLifetime < offerExpiryThreshold),
            Errors.Marketplace__MaxOfferLifetimeBelowOfferExpiryThreshold(maxOfferLifetime, offerExpiryThreshold)
        );
        config.maxOfferLifetime = maxOfferLifetime;

        emit MaxOfferLifetimeSet(maxOfferLifetime);
    }

    /**
     * @notice Sets the payment expiry threshold internally
     * @param marketplacePaymentExpiryThreshold The new expiry threshold in seconds
     * @dev Internal function that validates and updates storage
     * @dev Reverts if marketplacePaymentExpiryThreshold is below MIN_PAYMENT_EXPIRY_THRESHOLD
     * @dev Reverts if marketplacePaymentExpiryThreshold exceeds MAX_PAYMENT_EXPIRY_THRESHOLD
     * @dev Emits MarketplacePaymentExpiryThresholdSet event
     */
    function _setMarketplacePaymentExpiryThreshold(uint256 marketplacePaymentExpiryThreshold) internal {
        require(
            !(marketplacePaymentExpiryThreshold < MIN_PAYMENT_EXPIRY_THRESHOLD),
            Errors.Marketplace__PaymentExpiryThresholdTooLow(marketplacePaymentExpiryThreshold)
        );
        require(
            !(marketplacePaymentExpiryThreshold > MAX_PAYMENT_EXPIRY_THRESHOLD),
            Errors.Marketplace__PaymentExpiryThresholdTooHigh(marketplacePaymentExpiryThreshold)
        );
        Config storage config = _marketplaceStorage().config;
        config.marketplacePaymentExpiryThreshold = marketplacePaymentExpiryThreshold;

        emit MarketplacePaymentExpiryThresholdSet(marketplacePaymentExpiryThreshold);
    }

    /**
     * @notice Sets the interest-discovery activation and payment expiry threshold internally
     * @param paymentExpiryThreshold The new threshold snapshotted into future interest-discovery offers
     * @dev Internal function that validates and updates storage
     * @dev Reverts if paymentExpiryThreshold is below MIN_PAYMENT_EXPIRY_THRESHOLD
     * @dev Reverts if paymentExpiryThreshold exceeds MAX_PAYMENT_EXPIRY_THRESHOLD
     * @dev Emits InterestDiscoveryPaymentExpiryThresholdSet event
     */
    function _setInterestDiscoveryPaymentExpiryThreshold(uint256 paymentExpiryThreshold) internal {
        require(
            !(paymentExpiryThreshold < MIN_PAYMENT_EXPIRY_THRESHOLD),
            Errors.Marketplace__PaymentExpiryThresholdTooLow(paymentExpiryThreshold)
        );
        require(
            !(paymentExpiryThreshold > MAX_PAYMENT_EXPIRY_THRESHOLD),
            Errors.Marketplace__PaymentExpiryThresholdTooHigh(paymentExpiryThreshold)
        );
        Config storage config = _marketplaceStorage().config;
        config.interestDiscoveryPaymentExpiryThreshold = paymentExpiryThreshold;

        emit InterestDiscoveryPaymentExpiryThresholdSet(paymentExpiryThreshold);
    }

    /**
     * @notice Sets the redemption payment expiry threshold internally
     * @param paymentExpiryThreshold The new expiry threshold for accepted redemption deals
     * @dev Reverts if paymentExpiryThreshold is below MIN_PAYMENT_EXPIRY_THRESHOLD
     * @dev Reverts if paymentExpiryThreshold exceeds MAX_PAYMENT_EXPIRY_THRESHOLD
     */
    function _setRedemptionPaymentExpiryThreshold(uint256 paymentExpiryThreshold) internal {
        require(
            !(paymentExpiryThreshold < MIN_PAYMENT_EXPIRY_THRESHOLD),
            Errors.Marketplace__PaymentExpiryThresholdTooLow(paymentExpiryThreshold)
        );
        require(
            !(paymentExpiryThreshold > MAX_PAYMENT_EXPIRY_THRESHOLD),
            Errors.Marketplace__PaymentExpiryThresholdTooHigh(paymentExpiryThreshold)
        );
        Config storage config = _marketplaceStorage().config;
        config.redemptionPaymentExpiryThreshold = paymentExpiryThreshold;

        emit RedemptionPaymentExpiryThresholdSet(paymentExpiryThreshold);
    }

    /**
     * @notice Sets the dispute buffer period internally
     * @param disputeBufferPeriod The new dispute buffer period in seconds
     * @dev Internal function that validates and updates storage
     * @dev Reverts if disputeBufferPeriod is below MIN_DISPUTE_BUFFER_PERIOD
     * @dev Reverts if disputeBufferPeriod exceeds MAX_DISPUTE_BUFFER_PERIOD
     * @dev Emits DisputeBufferPeriodSet event
     */
    function _setDisputeBufferPeriod(uint256 disputeBufferPeriod) internal {
        require(
            !(disputeBufferPeriod < MIN_DISPUTE_BUFFER_PERIOD),
            Errors.Marketplace__DisputeBufferPeriodTooLow(disputeBufferPeriod)
        );
        require(
            !(disputeBufferPeriod > MAX_DISPUTE_BUFFER_PERIOD),
            Errors.Marketplace__DisputeBufferPeriodTooHigh(disputeBufferPeriod)
        );
        Config storage config = _marketplaceStorage().config;
        config.disputeBufferPeriod = disputeBufferPeriod;

        emit DisputeBufferPeriodSet(disputeBufferPeriod);
    }

    /**
     * @notice Sets the maximum number of counter offers allowed per user per offer internally
     * @param maxCounterOffers The maximum number of counter offers allowed
     * @dev Reverts if maxCounterOffers is zero
     * @dev Emits MaxCounterOffersPerUserSet event
     */
    function _setMaxCounterOffersPerUser(uint256 maxCounterOffers) internal {
        require(maxCounterOffers > 0, Errors.Marketplace__MaxCounterOffersPerUserZero());
        Config storage config = _marketplaceStorage().config;
        config.maxCounterOffersPerUser = maxCounterOffers;

        emit MaxCounterOffersPerUserSet(maxCounterOffers);
    }

    /**
     * @notice Initializes the base contract
     * @param owner_ The address of the contract owner
     * @param offerExpiryThreshold The minimum offer lifetime in seconds
     * @param maxOfferLifetime The maximum offer lifetime in seconds
     * @param marketplacePaymentExpiryThreshold The payment expiry threshold for marketplace deals in seconds
     * @param redemptionPaymentExpiryThreshold The payment expiry threshold for redemption deals in seconds
     * @param interestDiscoveryPaymentExpiryThreshold The threshold snapshotted into new interest-discovery offers
     * @param disputeBufferPeriod The dispute buffer period in seconds
     * @param assetManager_ The address of the asset manager contract
     * @param escrowManager The address of the escrow manager contract
     * @param entityRegistry_ The address of the entity registry contract
     * @param maxCounterOffers The maximum number of counter offers per user per offer
     * @dev Initializes the contract with the provided parameters and sets up the initial state
     * @dev Only callable during contract initialization
     * @dev Sets up owner, offer lifetime bounds, payment thresholds, dispute buffer period, optional asset/escrow addresses, and EntityRegistry
     */
    function __MarketplaceBase_init( // solhint-disable-line func-name-mixedcase
        address owner_,
        uint256 offerExpiryThreshold,
        uint256 maxOfferLifetime,
        uint256 marketplacePaymentExpiryThreshold,
        uint256 redemptionPaymentExpiryThreshold,
        uint256 interestDiscoveryPaymentExpiryThreshold,
        uint256 disputeBufferPeriod,
        address assetManager_,
        address escrowManager,
        address entityRegistry_,
        uint256 maxCounterOffers
    ) internal onlyInitializing {
        _initializeOwner(msg.sender);
        _setOfferExpiryThreshold(offerExpiryThreshold);
        _setMaxOfferLifetime(maxOfferLifetime);
        _setMarketplacePaymentExpiryThreshold(marketplacePaymentExpiryThreshold);
        _setRedemptionPaymentExpiryThreshold(redemptionPaymentExpiryThreshold);
        _setInterestDiscoveryPaymentExpiryThreshold(interestDiscoveryPaymentExpiryThreshold);
        _setDisputeBufferPeriod(disputeBufferPeriod);
        _setMaxCounterOffersPerUser(maxCounterOffers);
        if (assetManager_ != address(0)) {
            _setAssetManager(assetManager_);
        }
        if (escrowManager != address(0)) {
            _setEscrowManager(escrowManager);
        }
        _setEntityRegistry(entityRegistry_);
        transferOwnership(owner_);
    }
}
