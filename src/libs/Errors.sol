// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

/**
 * @title Errors
 * @author DEUSS Team
 * @notice Library containing custom errors
 * @dev Canonical revert reasons for the protocol (bonds, marketplace, wallet, deployment scripts). Prefer these
 *      over plain strings so integrators and tooling can decode stable selectors across releases.
 */
library Errors {
    /*//////////////////////////////////////////////////////////////
                                GENERAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Throw an error when address is zero
    error ZeroAddress();

    /// @notice Throw an error when the roles contain at least one undefined role
    error InvalidRoles();

    /// @notice Throw an error when array lengths are mismatched
    error LengthMismatch();

    /// @notice Thrown when the bytes length is invalid for expected string conversion
    error StringExtensions__InvalidBytesLength();

    /// @notice Thrown when a string contains at least one byte outside 7-bit ASCII
    error StringExtensions__NonAsciiCharacter();

    /// @notice Thrown when a string contains an ASCII byte outside the expected character set
    error StringExtensions__InvalidCharacter();

    /*//////////////////////////////////////////////////////////////
                               DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Throw an error when a deployment is attempted on an unconfigured network
    error DeployConfig__NetworkNotConfigured(uint256 chainId);

    /// @notice Throw an error when the registry is invalid
    error ProxyDeployer__InvalidRegistry(address registry, address expectedRegistry);

    /// @notice Throw an error when template already exists
    error ProxyDeployer__TemplateAlreadyExists(string name, string version);

    /// @notice Throw an error when template is not found
    error ProxyDeployer__TemplateNotFound(bytes32 templateId);

    /// @notice Throw an error when template is not active
    error ProxyDeployer__TemplateNotActive(string name, string version);

    /// @notice Throw an error when EBSI proxy factory is not set
    error DeployConfig__EBSIProxyFactoryNotSet();

    /// @notice Throw an error when EBSI proxy registry is not set
    error DeployConfig__EBSIProxyRegistryNotSet();

    /// @notice Throw an error when EBSI did registry is not set
    error DeployConfig__EBSIDidRegistryNotSet();

    /// @notice Throw an error when beacon CompanyWallet is not set
    error DeployConfig__BeaconCWNotSet();

    /// @notice Throw an error when the deployment file does not exist in ./deployments/
    error DeploymentFileNotFound();

    /// @notice Thrown when a deterministic (CREATE2) contract deployment fails
    error Create2DeploymentFailed(address predictedAddress);

    /*/////////////////////////////////////////////////////////////
                             BOND REGISTRY
    //////////////////////////////////////////////////////////////*/

    /// @notice Throw an error when 'bondNominalValue' is zero
    error BondRegistry__BondNominalValueIsZero();

    /// @notice Throw an error when `BondStatus` is invalid for performing the operation
    error BondRegistry__InvalidBondStatus(bytes12 isin);

    /// @notice Throw an error when a currency is not allowed
    error BondRegistry__InvalidCurrency();

    /// @notice Throw an error when 'maxSupply' is zero
    error BondRegistry__MaxSupplyIsZero();

    /// @notice Throw an error when issuance amount is zero
    error BondRegistry__IssuanceAmountIsZero();

    /// @notice Throw an error when issuance would exceed maxSupply
    error BondRegistry__MaxSupplyExceeded(uint256 requested, uint256 available);

    /// @notice Throw an error when future issuance has been permanently closed
    error BondRegistry__IssuanceClosed(bytes12 isin);

    /// @notice Throw an error when operation requires zero tranches but bond already has issued tranches
    error BondRegistry__BondAlreadyIssued(bytes12 isin);

    /// @notice Throw an error when an invalid tranche id is provided
    error BondRegistry__InvalidTrancheId(uint16 trancheId);

    /// @notice Throw an error when caller is not authorized to issue (must be publisher or issuer)
    error BondRegistry__UnauthorizedIssuer(address caller);

    /// @notice Throw an error when caller is not authorized to close issuance
    error BondRegistry__UnauthorizedIssuanceCloser(address caller);

    /// @notice Throw an error when caller is not authorized for the requested burn kind
    error BondRegistry__UnauthorizedBurnCaller(address caller, uint8 kind);

    /// @notice Throw an error when burn source is invalid for the requested burn kind
    error BondRegistry__InvalidBurnSource(address from, bytes12 isin, uint8 kind);

    /// @notice Throw an error when issuer reclaim would burn frozen issuer-held inventory
    error BondRegistry__FrozenIssuerReclaimDenied(
        address issuer, bytes12 isin, uint8 version, uint256 requested, uint256 available
    );

    /// @notice Throw an error when `bondIssue` is called after maturity date
    error BondRegistry__MaturityDateExpired();

    /// @notice Throw an error when issuanceCountry is zero
    error BondRegistry__IssuanceCountryIsZero();

    /// @notice Throw an error when bond issuer wallet is not enabled in the EntityRegistry
    error BondRegistry__IssuerNotEnabled(address issuer);

    /// @notice Throw an error when issuer recovery is requested with the current issuer
    error BondRegistry__IssuerUnchanged(address issuer);

    /// @notice Throw an error when a required BondRegistry reason code is zero
    error BondRegistry__ZeroReason();

    /// @notice Throw an error when bond does not exist
    error BondRegistry__NonExistentBond(bytes12 isin);

    /// @notice Throw an error when the token contract is not a valid DEUSSToken bound to this registry
    error BondRegistry__InvalidMultiToken(address multiToken);

    /// @notice Throw an error when attempting to change the shared token contract after bonds were issued
    error BondRegistry__MultiTokenLocked();

    /// @notice Throw an error when the `couponRates` arrays contain different lengths
    error BondRegistry__CouponRatesLengthMismatch();

    /// @notice Throw an error if the `couponRates`.`paymentTimestamps` array is not ordered ASC
    error BondRegistry__PaymentTimestampsUnordered();

    /// @notice Throw an error if the first coupon payment timestamp is zero
    error BondRegistry__PaymentTimestampZero();

    /// @notice Throw an error if the terminal coupon timestamp is after maturity
    error BondRegistry__PaymentTimestampAfterMaturity();

    /// @notice Throw an error if the last coupon rate is not zero
    error BondRegistry__CouponRatesLastRateNotZero();

    /// @notice Throw an error if the coupon type is fixed but the coupon rates are not of length 2
    error BondRegistry__CouponRatesUnexpectedLength();

    /// @notice Throw an error if adjacent coupon rates are duplicated
    error BondRegistry__CouponRatesDuplicate();

    /// @notice Throw an error when trying to close a bond with non-zero total supply
    error BondRegistry__TotalSupplyNotZero();

    /// @notice Throw an error when appending a scoring record with a zero issue date
    error BondRegistry__ScoringZeroIssueDate();

    /// @notice Throw an error when appending a scoring record where expirationDate is not after issueDate
    error BondRegistry__ScoringExpirationNotAfterIssue();

    /// @notice Throw an error when appending a scoring record with a zero distributorId
    error BondRegistry__ScoringZeroDistributorId();

    /// @notice Throw an error when defaultProbabilityBps exceeds 10_000
    error BondRegistry__ScoringProbabilityTooHigh(uint16 value);

    /// @notice Throw an error when querying scoring for a wallet that has no scoring records
    error BondRegistry__ScoringNotFound(address wallet);

    /// @notice Throw an error when scoringId is 0 or greater than the wallet-local scoring count
    error BondRegistry__InvalidScoringId(address wallet, uint256 scoringId);

    /// @notice Throw an error when a successor version is already in Published status for this ISIN
    error BondRegistry__SuccessorAlreadyPublished(bytes12 isin);

    /// @notice Throw an error when the active version is not Issued (e.g. Suspended), preventing successor publication
    error BondRegistry__ActiveVersionNotIssuable(bytes12 isin);

    /// @notice Throw an error when attempting to change immutable guarantee metadata on a published version
    error BondRegistry__GuaranteeStatusImmutable(bytes12 isin);

    /*//////////////////////////////////////////////////////////////
                              DEUSS TOKEN
    //////////////////////////////////////////////////////////////*/

    /// @notice Throw an error when the caller is not the bond registry
    error Token__CallerNotBondRegistry(address caller);

    /// @notice Throw an error when bond registry is already configured
    error BaseToken__BondRegistryAlreadySet();

    /// @notice Throw an error when entity registry is already configured
    error BaseToken__EntityRegistryAlreadySet();

    /// @notice Throw an error when the address balance is insufficient to execute the transfer
    error Token__InsufficientBalance();

    /// @notice Throw an error when array length is zero or array lengths are not equal
    error Token__InvalidArrayLength();

    /// @notice Throw an error when the amount is zero
    error Token__ZeroAmount();

    /// @notice Throw an error when the approval is rejected by the EntityRegistry
    error Token__ApprovalNotAllowed(address sender, address spender, uint256 tokenId, uint256 amount);

    /// @notice Throw an error when attempting to protect an address that is already protected
    error Token__AddressAlreadyProtected(address account);

    /// @notice Throw an error when attempting a privileged outbound action from a protected custody address
    error Token__AddressProtected(address account);

    /// @notice Throw an error when a transfer is rejected by the EntityRegistry
    error Token__TransferNotAllowed(address from, address to, uint256 tokenId);

    /// @notice Throw an error when a transfer attempts to push tokens into protected custody
    error Token__ProtectedReceiverTransferNotAllowed(address from, address to, address operator, uint256 tokenId);

    /// @notice Throw an error when the caller is not an enabled wallet
    error Token__CallerNotEnabled(address caller);

    /// @notice Throw an error when granting operator approval to a wallet that is not enabled
    error Token__OperatorNotEnabled(address operator);

    /// @notice Throw an error when a token ID is paused
    error Token__TokenIdIsPaused(uint256 tokenId);

    /// @notice Throw an error when trying to pause a token ID that is already paused
    error Token__TokenIdAlreadyPaused(uint256 tokenId);

    /// @notice Throw an error when trying to unpause a token ID that is not paused
    error Token__TokenIdNotPaused(uint256 tokenId);

    /// @notice Throw an error when trying to query data at a future block number
    error Token__BlockInFuture(uint256 currentBlock, uint256 queriedBlock);

    /*//////////////////////////////////////////////////////////////
                             PROXY DEPLOYER
    //////////////////////////////////////////////////////////////*/

    /// @notice Throw an error when string is empty
    error EmptyString();

    /*//////////////////////////////////////////////////////////////
                             WALLET FACTORY
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when caller is not a manager for an entity in wallet factory
    error WalletFactory__NotEntityManager(address caller, bytes32 entityId);

    /// @notice Thrown when entity is not enabled for wallet creation
    error WalletFactory__EntityNotEnabled(bytes32 entityId);

    /// @notice Thrown when wallet initialization payload is empty
    error WalletFactory__InitDataEmpty();

    /// @notice Thrown when the configured entity registry does not implement the expected interface
    error WalletFactory__InvalidEntityRegistry(address entityRegistry);

    /*//////////////////////////////////////////////////////////////
                           INTEREST DISCOVERY
    //////////////////////////////////////////////////////////////*/

    /// @notice Throw an error when the dispute buffer period is below the minimum allowed value
    error Marketplace__DisputeBufferPeriodTooLow(uint256 disputeBufferPeriod);

    /// @notice Throw an error when the dispute buffer period is above the maximum allowed value
    error Marketplace__DisputeBufferPeriodTooHigh(uint256 disputeBufferPeriod);

    /// @notice Throw an error when the offer expiry threshold is below the minimum allowed value
    error Marketplace__OfferExpiryThresholdTooLow(uint256 offerExpiryThreshold);

    /// @notice Throw an error when the offer expiry threshold is above the maximum allowed value
    error Marketplace__OfferExpiryThresholdTooHigh(uint256 offerExpiryThreshold);

    /// @notice Throw an error when the maximum offer lifetime exceeds the hard cap
    error Marketplace__MaxOfferLifetimeTooHigh(uint256 maxOfferLifetime);

    /// @notice Throw an error when the maximum offer lifetime is below the minimum offer expiry threshold
    error Marketplace__MaxOfferLifetimeBelowOfferExpiryThreshold(
        uint256 maxOfferLifetime, uint256 offerExpiryThreshold
    );

    /// @notice Throw an error when the payment expiry threshold is below the minimum allowed value
    error Marketplace__PaymentExpiryThresholdTooLow(uint256 paymentExpiryThreshold);

    /// @notice Throw an error when the payment expiry threshold is above the maximum allowed value
    error Marketplace__PaymentExpiryThresholdTooHigh(uint256 paymentExpiryThreshold);

    /// @notice Throw an error when the caller is not authorized
    error Marketplace__NotAuthorized(address sender);

    /// @notice Throw an error when an offer uses an unsupported sale mode encoding
    error Marketplace__InvalidSaleMode(uint8 saleMode);

    /// @notice Throw an error when a marketplace-only action is used on an interest-discovery offer
    error Marketplace__NotMarketplaceOffer(uint256 offerId);

    /// @notice Throw an error when an interest-discovery-only action is used on a marketplace offer
    error Marketplace__NotInterestDiscoveryOffer(uint256 offerId);

    /// @notice Throw an error when counter offers are enabled on an interest-discovery offer
    error Marketplace__CounterOffersMustBeDisabled();

    /// @notice Throw an error when allowlisted direct buyers are configured for an unsupported sale mode
    error Marketplace__AllowedBuyersNotAllowed();

    /// @notice Throw an error when a redemption offer is created without any allowed buyer
    error Marketplace__AllowedBuyersRequired();

    /// @notice Throw an error when the same allowed buyer is provided more than once
    error Marketplace__DuplicateAllowedBuyer(address buyer);

    /// @notice Throw an error when caller is not allowed to directly accept the offer
    error Marketplace__BuyerNotAllowed(uint256 offerId, address buyer);

    /// @notice Throw an error when `minSaleUnits` is non-zero for a marketplace offer
    error Marketplace__MinSaleUnitsNotAllowed(uint256 minSaleUnits);

    /// @notice Throw an error when `minSaleUnits` is invalid for an interest-discovery offer
    error Marketplace__InvalidMinSaleUnits(uint256 minSaleUnits, uint256 totalAmount, uint256 lot);

    /// @notice Throw an error when the offer has expired
    error Marketplace__OfferExpired(uint256 expiry, uint256 currentTimestamp);

    /// @notice Throw an error when the offer has not expired yet
    error Marketplace__OfferNotExpired(uint256 expiry, uint256 currentTimestamp);

    /// @notice Throw an error when the counter offer has expired
    error Marketplace__CounterOfferExpired(uint256 expiry, uint256 currentTimestamp);

    /// @notice Throw an error when the provided expiry is below the configured minimum threshold
    error Marketplace__InvalidExpiry(uint256 expiry, uint256 currentTimestamp);

    /// @notice Throw an error when the provided expiry exceeds the configured maximum lifetime
    error Marketplace__ExpiryTooFar(uint256 expiry, uint256 currentTimestamp, uint256 maxOfferLifetime);

    /// @notice Throw an error when the amount is zero
    error Marketplace__ZeroAmount();

    /// @notice Throw an error when the lot size is too large
    error Marketplace__LotSizeTooLarge();

    /// @notice Throw an error when the total amount is not a multiple of the lot size
    error Marketplace__TotalAmountNotMultipleOfLot();

    /// @notice Throw an error when the price is zero
    error Marketplace__ZeroPrice();

    /// @notice Throw an error when the currency is invalid
    error Marketplace__InvalidCurrency(bytes3 currency);

    /// @notice Throw an error when the currency already exists
    error Marketplace__CurrencyAlreadyExists(bytes3 currency);

    /// @notice Throw an error when the currency does not exist
    error Marketplace__CurrencyDoesNotExist(bytes3 currency);

    /// @notice Throw an error when the deal status is invalid
    error Marketplace__InvalidStatus(uint8 status);

    /// @notice Throw an error when the deal is not expired
    error Marketplace__DealNotExpired();

    /// @notice Throw an error when trying to mark deal as paid after payment deadline
    error Marketplace__PaymentDeadlineExpired();

    /// @notice Throw an error when trying to mark an already arbitrated deal as paid
    error Marketplace__DealAlreadyArbitrated();

    /// @notice Throw an error when the dispute period has expired
    error Marketplace__DisputePeriodExpired();

    /// @notice Throw an error when the deal is not in dispute
    error Marketplace__DealNotInDispute();

    /// @notice Throw an error when the dispute period has not expired
    error Marketplace__DisputePeriodNotExpired();

    /// @notice Throw an error when the available amount is insufficient
    error Marketplace__InsufficientAvailableAmount(uint256 amount, uint256 available);

    /// @notice Throw an error when the amount is not a multiple of the lot size
    error Marketplace__AmountNotMultipleOfLot(uint256 lot, uint256 amount);

    /// @notice Throw an error when the sender is the owner of the offer
    error Marketplace__SenderIsOwner();

    /// @notice Throw an error when counter offers are not allowed for the offer
    error Marketplace__CounterOffersNotAllowed();

    /// @notice Throw an error when the user has reached the counter offer limit for an offer
    error Marketplace__CounterOfferLimitReached();

    /// @notice Throw an error when the configured per-user counter-offer limit is zero
    error Marketplace__MaxCounterOffersPerUserZero();

    /// @notice Throw an error when trying to interact with an already cancelled offer
    error Marketplace__OfferAlreadyCancelled(uint256 offerId);

    /// @notice Throw an error when trying to withdraw available amount before cancellation
    error Marketplace__OfferNotCancelled(uint256 offerId);

    /// @notice Throw an error when no amount is available for cancellation withdrawal
    error Marketplace__NoAvailableAmount(uint256 offerId);

    /// @notice Throw an error when an interest is missing
    error Marketplace__InterestNotFound(uint256 interestId);

    /// @notice Throw an error when an interest is not in the expected lifecycle status
    error Marketplace__InvalidInterestStatus(uint256 interestId, uint8 status);

    /// @notice Throw an error when interest activation is attempted before reaching the threshold
    error Marketplace__ThresholdNotReached(uint256 offerId, uint256 interestedUnits, uint256 minSaleUnits);

    /// @notice Throw an error when failed-book cancellation is attempted after reaching the threshold
    error Marketplace__ThresholdAlreadyReached(uint256 offerId, uint256 interestedUnits, uint256 minSaleUnits);

    /// @notice Throw an error when interest activation is attempted after the activation deadline
    error Marketplace__InterestActivationWindowExpired(
        uint256 offerId, uint256 activationDeadline, uint256 currentTimestamp
    );

    /// @notice Throw an error when batched interest closure is attempted before the activation deadline passes
    error Marketplace__InterestActivationWindowOpen(
        uint256 offerId, uint256 activationDeadline, uint256 currentTimestamp
    );

    /// @notice Throw an error when the activation deadline cannot be computed safely
    error Marketplace__InterestActivationDeadlineOverflow(
        uint256 offerId, uint256 saleEnd, uint256 paymentExpiryThreshold
    );

    /// @notice Throw an error when a batched interest does not belong to the expected offer
    error Marketplace__InterestOfferMismatch(uint256 interestId, uint256 offerId);

    /// @notice Throw an error when asset manager dependency is not configured
    error Marketplace__AssetManagerNotSet();

    /// @notice Throw an error when interacting with an offer that does not exist
    error Marketplace__OfferDoesNotExist(uint256 offerId);

    /// @notice Throw an error when interacting with a deal that does not exist
    error Marketplace__DealDoesNotExist(uint256 dealId);

    /// @notice Throw an error when interacting with a frozen offer
    error Marketplace__OfferFrozen(uint256 offerId);

    /// @notice Throw an error when interacting with a frozen deal
    error Marketplace__DealFrozen(uint256 dealId);

    /// @notice Throw an error when the offer is not frozen but seizure requires it
    error Marketplace__OfferNotFrozen(uint256 offerId);

    /// @notice Throw an error when the deal is not frozen but seizure requires it
    error Marketplace__DealNotFrozen(uint256 dealId);

    /// @notice Throw an error when a seizure reason is zero
    error Marketplace__ZeroReason();

    /// @notice Throw an error when the escrow id returned by EscrowManager differs from the reserved id
    error Marketplace__EscrowIdMismatch(uint256 actualEscrowId, uint256 expectedEscrowId);

    /*//////////////////////////////////////////////////////////////
                              ASSET MANAGER
    //////////////////////////////////////////////////////////////*/

    /// @notice Throw an error when asset type is invalid
    error AssetManager__InvalidAssetType();

    /// @notice Throw an error when token is not enabled in the whitelist
    error AssetManager__AssetNotSupported(address token, uint256 tokenId);

    /// @notice Throw an error when tokenId-level allowlist mode is disabled for token
    error AssetManager__TokenIdAllowlistDisabled(address token);

    /// @notice Throw an error when tokenId is not enabled in token-level allowlist
    error AssetManager__TokenIdNotSupported(address token, uint256 tokenId);

    /// @notice Throw an error when token id is invalid for the token standard
    error AssetManager__InvalidTokenId(uint256 tokenId);

    /// @notice Throw an error when ERC721 amount is not equal to 1
    error AssetManager__InvalidAmountForERC721(uint256 amount);

    /// @notice Throw an error when BondRegistry dependency is already set
    error AssetManager__BondRegistryAlreadySet();

    /// @notice Throw an error when ERC6909 bond metadata is required but BondRegistry is not configured
    error AssetManager__BondRegistryNotSet();

    /// @notice Throw an error when BondRegistry has no metadata for the requested token ID
    error AssetManager__BondMetadataNotFound(address token, uint256 tokenId);

    /// @notice Throw an error when BondRegistry metadata points to a different token contract
    error AssetManager__BondTokenMismatch(address token, uint256 tokenId, address registryToken);

    /*//////////////////////////////////////////////////////////////
                         DEUSS BOND VALIDATOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Throw an error when the provided token does not match the bond's token contract
    error DeussBondValidator__TokenMismatch(address provided, address expected);

    /// @notice Throw an error when the bond's status does not permit trading on the orderbook
    error DeussBondValidator__NotTradable(uint256 tokenId, uint8 status);

    /*//////////////////////////////////////////////////////////////
                       ENTITY ELIGIBILITY GUARD
    //////////////////////////////////////////////////////////////*/

    /// @notice Throw an error when a wallet (or linked entity) is not allowed
    error EntityEligibilityGuard__EntityWalletNotAllowed(address wallet);

    /// @notice Throw an error when an entity type is not in the allowlist
    error EntityEligibilityGuard__EntityTypeNotAllowed(uint256 typeId);

    /*//////////////////////////////////////////////////////////////
                        ORDERBOOK MARKETPLACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Throw an error when the escrow id returned by EscrowManager differs from the reserved id
    error OrderbookMarketplace__EscrowIdMismatch(uint256 actualEscrowId, uint256 expectedEscrowId);

    /// @notice Throw an error when the amount is zero
    error OrderbookMarketplace__ZeroAmount();

    /// @notice Throw an error when the price is zero
    error OrderbookMarketplace__ZeroPrice();

    /// @notice Throw an error when the price range is invalid (minPrice > maxPrice)
    error OrderbookMarketplace__InvalidPriceRange(uint256 minPrice, uint256 maxPrice);

    /// @notice Throw an error when minMatchAmount exceeds totalAmount
    error OrderbookMarketplace__MinAmountExceedsTotal(uint256 minMatchAmount, uint256 totalAmount);

    /// @notice Throw an error when trader filter is not empty when it should be
    error OrderbookMarketplace__TradeFilterNotEmpty();

    /// @notice Throw an error when trader filter is empty when it should not be
    error OrderbookMarketplace__TradeFilterEmpty();

    /// @notice Throw an error when trader filter address list exceeds maximum length
    error OrderbookMarketplace__TraderFilterTooLarge(uint256 length);

    /// @notice Throw an error when payment expiry threshold is below the allowed minimum
    error OrderbookMarketplace__PaymentExpiryThresholdTooLow(uint256 paymentExpiryThreshold);

    /// @notice Throw an error when payment expiry threshold exceeds the allowed maximum
    error OrderbookMarketplace__PaymentExpiryThresholdTooHigh(uint256 paymentExpiryThreshold);

    /// @notice Throw an error when minimum order expiry threshold is below the allowed minimum
    error OrderbookMarketplace__MinExpiryThresholdTooLow(uint256 minExpiryThreshold);

    /// @notice Throw an error when dispute buffer period is below the allowed minimum
    error OrderbookMarketplace__DisputeBufferPeriodTooLow(uint256 disputeBufferPeriod);

    /// @notice Throw an error when dispute buffer period exceeds the allowed maximum
    error OrderbookMarketplace__DisputeBufferPeriodTooHigh(uint256 disputeBufferPeriod);

    /// @notice Throw an error when the caller is not authorized
    error OrderbookMarketplace__NotAuthorized(address sender);

    /// @notice Throw when querying or operating on an order ID that does not exist
    error OrderbookMarketplace__OrderNotFound(uint256 orderId);

    /// @notice Throw an error when trying to cancel an order with no available amount
    error OrderbookMarketplace__NoAvailableAmount(uint256 orderId);

    /// @notice Throw an error when a provided order expiry does not satisfy the configured threshold
    error OrderbookMarketplace__InvalidExpiry(uint256 expiry, uint256 currentTimestamp);

    /// @notice Throw an error when trying to clean up an order whose expiry has not passed yet
    error OrderbookMarketplace__OrderNotExpired(uint256 orderId, uint256 expiry, uint256 currentTimestamp);

    /// @notice Throw an error when trade status is invalid for the operation
    error OrderbookMarketplace__InvalidTradeStatus(uint8 currentStatus);

    /// @notice Throw an error when trade is not in a status that can be settled
    error OrderbookMarketplace__TradeNotSettleable(uint8 status);

    /// @notice Throw when querying or operating on a trade ID that does not exist
    error OrderbookMarketplace__TradeNotFound(uint256 tradeId);

    /// @notice Throw an error when trying to mark trade as unpaid before payment deadline
    error OrderbookMarketplace__TradeNotExpired();

    /// @notice Throw an error when dispute period has already expired
    error OrderbookMarketplace__DisputePeriodExpired();

    /// @notice Throw an error when dispute period has not expired yet
    error OrderbookMarketplace__DisputePeriodNotExpired();

    /// @notice Throw an error when trade is not currently in dispute
    error OrderbookMarketplace__TradeNotInDispute();

    /// @notice Throw an error when dispute resolution status is invalid
    error OrderbookMarketplace__InvalidDisputeResolution(uint8 status);

    /// @notice Throw when asset manager is not configured
    error OrderbookMarketplace__AssetManagerNotSet();

    /// @notice Thrown when getTWAP is called before any trade has been recorded for the token
    error OrderbookMarketplace__NoObservations();

    /// @notice Thrown when getTWAP timeElapsed is zero (found observation is at current block)
    error OrderbookMarketplace__InsufficientTWAPAge();

    /// @notice Thrown when a trade price causes the TWAP cumulative accumulator to exceed uint224 max
    error OrderbookMarketplace__TWAPAccumulatorOverflow();
    /// @notice Throw when a delegate is not authorized by the trader
    error OrderbookMarketplace__DelegateNotAuthorized(address delegate, address trader);

    /// @notice Throw an error when an order is frozen
    error OrderbookMarketplace__OrderFrozen(uint256 orderId);

    /// @notice Throw an error when a trade is frozen
    error OrderbookMarketplace__TradeFrozen(uint256 tradeId);

    /// @notice Throw an error when trying to seize order with zero available amount
    error OrderbookMarketplace__NoAvailableAmountToSeize(uint256 orderId);

    /// @notice Throw an error when trying to seize order that is not frozen
    error OrderbookMarketplace__CannotSeizeUnfrozenOrder(uint256 orderId);

    /// @notice Throw an error when trying to seize trade that is not frozen
    error OrderbookMarketplace__CannotSeizeUnfrozenTrade(uint256 tradeId);

    /// @notice Throw an error when trying to seize trade when parent sell order is not frozen
    error OrderbookMarketplace__ParentOrderNotFrozen(uint256 sellOrderId);

    /// @notice Throw an error when reason is zero
    error OrderbookMarketplace__ZeroReason();

    /// @notice Throw an error when freeze reason is zero
    error OrderbookMarketplace__ZeroFreezeReason();

    /// @notice Throw when number of active SELL markets would exceed the cap
    error OrderbookMarketplace__TooManyActiveSellMarkets();

    /// @notice Throw when cancelOrder is called on a synthetic batch BUY order (IOC by construction)
    error OrderbookMarketplace__BatchOrderCannotBeCancelled(uint256 orderId);

    /*//////////////////////////////////////////////////////////////
                         BOND MARKET FILTER
    //////////////////////////////////////////////////////////////*/

    /// @notice Throw when a BondFilter range bound is inverted (from > to on a bounded side)
    error BondMarketFilter__InvalidFilterRange();

    /*//////////////////////////////////////////////////////////////
                            ESCROW MANAGER
    //////////////////////////////////////////////////////////////*/

    /// @notice Throw an error when amount is zero
    error EscrowManager__ZeroAmount();

    /// @notice Throw an error when module type is invalid (zero bytes32)
    error EscrowManager__InvalidModuleType();

    /// @notice Throw an error when module address is invalid (zero address)
    error EscrowManager__InvalidModuleAddress();

    /// @notice Throw an error when module address is already bound to a different module type
    error EscrowManager__ModuleTypeMismatch(bytes32 existingModuleType, bytes32 requestedModuleType);

    /// @notice Throw an error when module is already registered and active for the provided module type
    error EscrowManager__ModuleAlreadyRegistered(address moduleAddress, bytes32 moduleType);

    /// @notice Throw an error when module is not registered in EscrowManager
    error EscrowManager__ModuleNotRegistered(address moduleAddress);

    /// @notice Throw an error when module is not authorized for given module type
    error EscrowManager__ModuleNotAuthorized(address moduleAddress, bytes32 moduleType);

    /// @notice Throw an error when a module with active escrows is being deactivated
    error EscrowManager__ModuleHasActiveEscrows(address moduleAddress, uint256 activeEscrows);

    /// @notice Throw an error when depositor is zero address
    error EscrowManager__InvalidDepositor();

    /// @notice Throw an error when token address is zero address
    error EscrowManager__InvalidTokenAddress();

    /// @notice Throw an error when asset manager dependency is not configured
    error EscrowManager__AssetManagerNotSet();

    /// @notice Throw an error when escrow with given id does not exist
    error EscrowManager__EscrowNotFound(uint256 escrowId);

    /// @notice Throw an error when beneficiary is zero address
    error EscrowManager__InvalidBeneficiary();

    /// @notice Throw an error when trying to withdraw with insufficient balance
    error EscrowManager__InsufficientBalance();

    /// @notice Thrown when a token transfer from or to the EscrowManager fails
    error EscrowManager__TokensTransferFailed();

    /// @notice Throw an error when an invalid asset type is supplied
    error EscrowManager__InvalidAssetType(uint8 assetType);

    /// @notice Throw an error when ERC721 transfer amount is not equal to 1
    error EscrowManager__InvalidERC721Amount(uint256 amount);

    /// @notice Thrown when a sweep request exceeds the available surplus for the asset
    error EscrowManager__SweepExceedsSurplus(uint256 requested, uint256 surplus);

    /// @notice Thrown when a sweep amount is zero
    error EscrowManager__InvalidSweepAmount();

    /// @notice Thrown when the amount received by the escrow after an ERC20 transfer does not match the requested deposit amount
    error EscrowManager__DepositAmountMismatch();

    /*//////////////////////////////////////////////////////////////
                             DEPENDENCIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Throw an error when bond registry dependency is already configured
    error DependenciesBase__BondRegistryAlreadySet();

    /// @notice Throw an error when escrow manager dependency is already configured
    error DependenciesBase__EscrowManagerAlreadySet();

    /// @notice Throw an error when entity registry dependency is already configured
    error DependenciesBase__EntityRegistryAlreadySet();

    /*//////////////////////////////////////////////////////////////
                            ENTITY REGISTRY
    //////////////////////////////////////////////////////////////*/
    /// @notice Thrown when entityId is zero
    error ER__EntityIdZero();

    /// @notice Thrown when entity is already registered
    error ER__EntityAlreadyRegistered(bytes32 entityId);

    /// @notice Thrown when entity is not registered
    error ER__EntityNotRegistered(bytes32 entityId);

    /// @notice Thrown when operating on a disabled entity
    error ER__EntityNotEnabled(bytes32 entityId);

    /// @notice Thrown when entity status is NONE for status updates
    error ER__EntityStatusNone();

    /// @notice Thrown when entity type id is zero
    error ER__EntityTypeIdZero();

    /// @notice Thrown when entity type name is zero
    error ER__EntityTypeNameZero(uint256 typeId);

    /// @notice Thrown when entity type is not registered
    error ER__EntityTypeNotRegistered(uint256 typeId);

    /// @notice Thrown when updating a frozen entity type
    error ER__EntityTypeFrozen(uint256 typeId);

    /// @notice Thrown when caller is neither protocol admin nor entity authority
    error ER__NotEntityAuthorityOrAdmin(address sender, bytes32 entityId);

    /// @notice Thrown when setting the same authority address for an entity
    error ER__EntityAuthorityAlreadySet(bytes32 entityId, address authority);

    /// @notice Thrown when a registered authority account is not enabled
    error ER__EntityAuthorityAccountNotEnabled(address authority, bytes32 entityId);

    /// @notice Thrown when a registered authority account is linked to another entity
    error ER__EntityAuthorityAccountLinkedToDifferentEntity(
        address authority, bytes32 expectedEntityId, bytes32 actualEntityId
    );

    /// @notice Thrown when caller is neither protocol admin nor entity manager
    error ER__NotEntityManagerOrAdmin(address sender, bytes32 entityId);

    /// @notice Thrown when a registered manager account is not enabled
    error ER__EntityManagerAccountNotEnabled(address manager, bytes32 entityId);

    /// @notice Thrown when a registered manager account is linked to another entity
    error ER__EntityManagerAccountLinkedToDifferentEntity(
        address manager, bytes32 expectedEntityId, bytes32 actualEntityId
    );

    /// @notice Thrown when account is already registered
    error ER__AccountAlreadyRegistered(address account);

    /// @notice Thrown when account is not registered
    error ER__AccountNotRegistered(address account);

    /// @notice Thrown when no pending account registration exists for the account and entity
    error ER__AccountRegistrationNotPending(address account, bytes32 entityId);

    /// @notice Thrown when account status is NONE for status updates
    error ER__AccountStatusNone();

    /// @notice Thrown when account is already linked to the entity
    error ER__AccountAlreadyLinked(address account, bytes32 entityId);

    /// @notice Thrown when account is still configured as authority for an entity
    error ER__AccountIsEntityAuthority(address account, bytes32 entityId);

    /// @notice Thrown when account is still configured as manager for an entity
    error ER__AccountIsEntityManager(address account, bytes32 entityId);

    /// @notice Thrown when the deployed company wallet is zero address
    error ER__CompanyWalletAddressZero();

    /// @notice Thrown when the wallet type id is zero
    error ER__CompanyWalletTypeIdZero();

    /// @notice Thrown when the wallet type has no configured template
    error ER__CompanyWalletTypeNotConfigured(bytes32 walletType);

    /*//////////////////////////////////////////////////////////////
                             COMPANY WALLET
    //////////////////////////////////////////////////////////////*/
    /// @notice Throw an error when the operation target is the zero address, not a contract, or the same as the caller contract
    error CompanyWallet__InvalidCallTarget();

    /// @notice Throw an error when the call data is too short
    error CompanyWallet__InvalidCallData();

    /// @notice Throw an error when a forwarded native value does not match msg.value
    error CompanyWallet__MsgValueMismatch();

    /// @notice Throw an error when the sender is unauthorized to execute operation
    error CompanyWallet__Unauthorized();

    /// @notice Throw an error when the configured policy registry is zero or has no code
    error CompanyWallet__InvalidPolicyRegistry(address policyRegistry);

    /// @notice Throw an error when the configured policy registry does not implement IPolicyRegistry
    error CompanyWallet__UnsupportedPolicyRegistry(address policyRegistry);

    /// @notice Throw an error when ownership is transferred to the current owner
    error CompanyWallet__OwnerTransferToSelf();

    /// @notice Throw an error when manually advancing the policy epoch without an audit reason
    error CompanyWallet__ZeroPolicyEpochReason();

    /// @notice Throw an error when renounceOwnership is called (disabled for wallets)
    error CompanyWallet__RenounceOwnershipDisabled();

    /*//////////////////////////////////////////////////////////////
                            POLICY REGISTRY
    //////////////////////////////////////////////////////////////*/

    /// @notice Throw an error when the wallet is not a deployed contract
    error PolicyRegistry__InvalidWallet(address wallet);

    /// @notice Throw an error when the caller is not authorized for wallet policy management
    error PolicyRegistry__Unauthorized(address caller, address wallet);

    /// @notice Throw an error when the policy admin is invalid
    error PolicyRegistry__InvalidPolicyAdmin(address admin);

    /// @notice Throw an error when the delegated wallet policy admin is already granted
    error PolicyRegistry__WalletPolicyAdminAlreadyGranted(address wallet, address admin);

    /// @notice Throw an error when the delegated wallet policy admin is not granted
    error PolicyRegistry__WalletPolicyAdminNotGranted(address wallet, address admin);

    /// @notice Throw an error when the policy module is invalid
    error PolicyRegistry__InvalidPolicyModule(address module);

    /// @notice Throw an error when the policy module is not allowlisted
    error PolicyRegistry__PolicyModuleNotAllowed(address module);

    /// @notice Throw an error when granting an empty role bitmap
    error PolicyRegistry__ZeroRoles();

    /// @notice Throw an error when a user already has all granted roles
    error PolicyRegistry__UserRolesAlreadyGranted(address wallet, address user, uint256 roles);

    /// @notice Throw an error when a user does not currently have all revoked roles
    error PolicyRegistry__UserRolesNotGranted(address wallet, address user, uint256 roles);

    /// @notice Throw an error when an operation already has all granted roles
    error PolicyRegistry__OperationRolesAlreadyGranted(address wallet, address target, bytes4 selector, uint256 roles);

    /// @notice Throw an error when an operation does not currently have all revoked roles
    error PolicyRegistry__OperationRolesNotGranted(address wallet, address target, bytes4 selector, uint256 roles);

    /// @notice Throw an error when a selector is zero
    error PolicyRegistry__ZeroSelector();
}
