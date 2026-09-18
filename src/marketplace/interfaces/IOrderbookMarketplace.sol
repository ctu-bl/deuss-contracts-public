// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

/// @title IOrderbookMarketplace
/// @notice Interface for the OrderbookMarketplace contract
/// @author DEUSS Team
interface IOrderbookMarketplace {
    /*//////////////////////////////////////////////////////////////
                            DATA STRUCTURES
    //////////////////////////////////////////////////////////////*/

    /// @notice Order side: BUY or SELL
    enum OrderSide {
        BUY,
        SELL
    }

    /// @notice Trade status across payment, dispute, settlement, and seizure lifecycle
    enum TradeStatus {
        NONE,
        PENDING,
        PAID,
        UNPAID,
        IN_DISPUTE,
        CANCELLED,
        SETTLED,
        SEIZED
    }

    /// @notice Trader filter mode for per-order access control
    enum TraderFilterMode {
        NONE,
        WHITELIST,
        BLACKLIST
    }

    /**
     * @notice A single price-accumulator snapshot stored in the TWAP circular buffer
     * @param timestamp  Block timestamp when the observation was recorded (seconds, uint32 safe until year 2106)
     * @param cumulativePrice  Running sum of lastPrice * timeElapsed at the moment of recording
     */
    struct Observation {
        uint32 timestamp;
        uint224 cumulativePrice;
    }

    /// @notice Order structure for limit orders
    struct Order {
        address tokenAddress;
        uint256 tokenId;
        address trader;
        uint256 minPrice;
        uint256 maxPrice;
        uint256 minMatchAmount;
        TraderFilterMode traderFilterMode;
        OrderSide side;
        uint256 timestamp;
        uint256 expiry;
        OrderAmounts amounts;
    }

    /**
     * @notice Structure representing the token amounts for an order
     * @param total Total amount in the order
     * @param available Amount available for new matches
     * @param inDeals Amount currently locked in pending trades
     * @param sold Amount successfully sold/bought
     */
    struct OrderAmounts {
        uint256 total;
        uint256 available;
        uint256 inDeals;
        uint256 sold;
    }

    /**
     * @notice Input structure for placing an order
     * @param tokenAddress Address of the token contract
     * @param tokenId Token ID
     * @param totalAmount Number of bonds to trade
     * @param minPrice Minimum price per bond unit
     * @param maxPrice Maximum price per bond unit (use minPrice == maxPrice for fixed price)
     * @param minMatchAmount Minimum amount for a single match (0 = no minimum)
     * @param traderFilterMode Trader filter mode (NONE, WHITELIST, or BLACKLIST)
     * @param traderFilterAddresses Addresses for the trader filter (must be empty for NONE, non-empty for WHITELIST/BLACKLIST)
     * @param side BUY or SELL
     * @param expiry Optional order expiry timestamp (0 = does not expire)
     */
    struct OrderInput {
        address tokenAddress;
        uint256 tokenId;
        uint256 totalAmount;
        uint256 minPrice;
        uint256 maxPrice;
        uint256 minMatchAmount;
        TraderFilterMode traderFilterMode;
        address[] traderFilterAddresses;
        OrderSide side;
        uint256 expiry;
    }

    /// @notice Lightweight identifier for a bond market
    struct Market {
        address tokenAddress;
        uint256 tokenId;
    }

    /**
     * @notice Input for placeBatchOrder() — immediate-or-cancel multi-market BUY
     * @param totalAmount Global amount budget shared across all matched markets
     * @param minPrice Minimum acceptable execution price per unit
     * @param maxPrice Maximum acceptable execution price per unit
     * @param minMatchAmount Minimum amount per individual match (0 = no minimum)
     * @param filterData Opaque filter payload forwarded to the configured IMarketFilter (resolver-specific encoding)
     * @param traderFilterMode NONE / WHITELIST / BLACKLIST
     * @param traderFilterAddresses Counterparty addresses for the trader filter
     */
    struct BatchOrderInput {
        uint256 totalAmount;
        uint256 minPrice;
        uint256 maxPrice;
        uint256 minMatchAmount;
        bytes filterData;
        TraderFilterMode traderFilterMode;
        address[] traderFilterAddresses;
    }

    /// @notice Trade structure representing a matched order pair
    struct Trade {
        uint256 tradeId;
        uint256 buyOrderId;
        uint256 sellOrderId;
        address tokenAddress;
        uint256 tokenId;
        address buyer;
        address seller;
        uint256 amount;
        uint256 unitPrice;
        TradeStatus status;
        uint256 timestamp;
        uint256 paymentDeadline;
        uint256 disputeBuffer;
    }

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the asset manager address is set
     * @param assetManager Address of the asset manager
     */
    event AssetManagerSet(address indexed assetManager);

    /**
     * @notice Emitted when the company wallet registry address is set
     * @param entityRegistry Address of the company wallet registry
     */
    event EntityRegistrySet(address indexed entityRegistry);

    /**
     * @notice Emitted when the escrow manager address is set
     * @param escrowManager Address of the escrow manager
     */
    event EscrowManagerSet(address indexed escrowManager);

    /**
     * @notice Emitted when the market filter address is set
     * @param marketFilter Address of the market filter resolver
     */
    event MarketFilterSet(address indexed marketFilter);

    /**
     * @notice Emitted when a new order is placed
     * @param orderId Unique order identifier
     * @param tokenId Token ID
     * @param trader Address placing the order
     * @param tokenAddress Address of the token contract
     * @param totalAmount Total order amount
     * @param unfilledAmount Unfilled order amount
     * @param minPrice Minimum price per unit
     * @param maxPrice Maximum price per unit
     * @param minMatchAmount Minimum amount for a single match
     * @param traderFilterMode Trader filter mode
     * @param side BUY or SELL
     * @param expiry Optional order expiry timestamp (0 = does not expire)
     */
    event OrderPlaced(
        uint256 indexed orderId,
        uint256 indexed tokenId,
        address indexed trader,
        address tokenAddress,
        uint256 totalAmount,
        uint256 unfilledAmount,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 minMatchAmount,
        TraderFilterMode traderFilterMode,
        OrderSide side,
        uint256 expiry
    );

    /**
     * @notice Emitted when a synthetic batch BUY order is placed
     * @dev Synthetic order has tokenAddress=0, tokenId=0; immediate-or-cancel (unmatched amount discarded)
     * @param orderId Unique order identifier (audit trail, referenced by Trade.buyOrderId)
     * @param trader Address placing the batch order
     * @param totalAmount Global amount budget
     * @param matchedAmount Amount actually matched across markets
     * @param minPrice Minimum acceptable execution price
     * @param maxPrice Maximum acceptable execution price
     * @param minMatchAmount Minimum amount per individual match
     * @param traderFilterMode Trader filter mode
     */
    event BatchOrderPlaced(
        uint256 indexed orderId,
        address indexed trader,
        uint256 totalAmount,
        uint256 matchedAmount,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 minMatchAmount,
        TraderFilterMode traderFilterMode
    );

    /**
     * @notice Emitted when an order is cancelled
     * @param orderId Order identifier
     * @param trader Address that owned the order whose available amount was removed from the orderbook
     * @param remainingAmount Amount that was still available
     */
    event OrderCancelled(uint256 indexed orderId, address indexed trader, uint256 indexed remainingAmount);

    /**
     * @notice Emitted when an order is automatically deleted
     * @param orderId The ID of the deleted order
     * @param trader The trader who owned the order
     */
    event OrderDeleted(uint256 indexed orderId, address indexed trader);

    /**
     * @notice Emitted when orders are matched and trade is executed
     * @param buyOrderId Buy order that was matched
     * @param sellOrderId Sell order that was matched
     * @param tokenId Token ID
     * @param tokenAddress Address of the token contract
     * @param buyer Buyer address
     * @param seller Seller address
     * @param amount Trade amount
     * @param unitPrice Trade price per unit
     */
    event TradeExecuted(
        uint256 indexed buyOrderId,
        uint256 indexed sellOrderId,
        uint256 indexed tokenId,
        address tokenAddress,
        address buyer,
        address seller,
        uint256 amount,
        uint256 unitPrice
    );

    /**
     * @notice Emitted when payment for a trade is confirmed
     * @param tradeId The ID of the trade
     * @param buyer The buyer address
     * @param seller The seller address
     */
    event TradePaid(uint256 indexed tradeId, address indexed buyer, address indexed seller);

    /**
     * @notice Emitted when tokens are transferred from escrow to buyer
     * @param tradeId The ID of the trade
     * @param buyer The buyer address
     * @param amount The amount of tokens transferred
     */
    event TradeSettled(uint256 indexed tradeId, address indexed buyer, uint256 indexed amount);

    /**
     * @notice Emitted when a trade is marked as unpaid after payment deadline expires
     * @param tradeId The ID of the trade
     * @param buyer The buyer address
     * @param seller The seller address
     */
    event TradeUnpaid(uint256 indexed tradeId, address indexed buyer, address indexed seller);

    /**
     * @notice Emitted when a buyer initiates a dispute for an unpaid trade
     * @param tradeId The ID of the disputed trade
     * @param buyer The buyer address
     * @param seller The seller address
     */
    event TradeDisputed(uint256 indexed tradeId, address indexed buyer, address indexed seller);

    /**
     * @notice Emitted when a dispute is resolved by the arbitrator
     * @param tradeId The ID of the disputed trade
     * @param status The resolved trade status
     * @param arbitrator The arbitrator address
     */
    event TradeDisputeResolved(uint256 indexed tradeId, TradeStatus status, address indexed arbitrator);

    /**
     * @notice Emitted when the payment expiry threshold is updated
     * @param paymentExpiryThreshold The new payment expiry threshold in seconds
     */
    event PaymentExpiryThresholdSet(uint256 indexed paymentExpiryThreshold);

    /* solhint-disable gas-indexed-events */
    /**
     * @notice Emitted whenever a TWAP observation is written to the circular buffer
     * @param tokenAddress  Token contract address
     * @param tokenId       Token ID (ISIN tranche)
     * @param timestamp     Block timestamp of the observation
     * @param cumulativePrice  Cumulative price-time accumulator value stored
     * @param lastPrice     Trade price that becomes the new lastPrice going forward
     */
    event TWAPObservationRecorded(
        address indexed tokenAddress,
        uint256 indexed tokenId,
        uint32 timestamp,
        uint224 cumulativePrice,
        uint256 lastPrice
    );
    /* solhint-enable gas-indexed-events */
    /**
     * @notice Emitted when a trader authorizes or revokes a delegate
     * @param trader Address of the trader
     * @param delegate Address of the delegate
     * @param authorized True if the delegate is authorized, false if revoked
     */
    event DelegateSet(address indexed trader, address indexed delegate, bool indexed authorized);

    /**
     * @notice Emitted when an order is frozen or unfrozen
     * @param orderId The ID of the order
     * @param frozen True if frozen, false if unfrozen
     * @param reason Opaque identifier for the legal/compliance reason
     * @param freezer The address that set the frozen state
     */
    event OrderFrozenSet(uint256 indexed orderId, bool indexed frozen, bytes32 indexed reason, address freezer);

    /**
     * @notice Emitted when a trade is frozen or unfrozen
     * @param tradeId The ID of the trade
     * @param frozen True if frozen, false if unfrozen
     * @param reason Opaque identifier for the legal/compliance reason
     * @param freezer The address that set the frozen state
     */
    event TradeFrozenSet(uint256 indexed tradeId, bool indexed frozen, bytes32 indexed reason, address freezer);

    /**
     * @notice Emitted when an order is seized
     * @param orderId The ID of the seized order
     * @param beneficiary The address that received the seized funds
     * @param amount The amount seized
     * @param reason Opaque identifier for the legal/compliance reason
     * @param seizer The address that performed the seizure
     */
    event OrderSeized(
        uint256 indexed orderId, address indexed beneficiary, uint256 amount, bytes32 indexed reason, address seizer
    );

    /**
     * @notice Emitted when a trade is seized
     * @param tradeId The ID of the seized trade
     * @param sellOrderId The ID of the parent sell order
     * @param beneficiary The address that received the seized funds
     * @param amount The amount seized
     * @param reason Opaque identifier for the legal/compliance reason
     * @param seizer The address that performed the seizure
     */
    event TradeSeized(
        uint256 indexed tradeId,
        uint256 indexed sellOrderId,
        address indexed beneficiary,
        uint256 amount,
        bytes32 reason,
        address seizer
    );

    /**
     * @notice Emitted when the minimum order expiry threshold is updated
     * @param minExpiryThreshold The new minimum order expiry threshold in seconds
     */
    event MinExpiryThresholdSet(uint256 indexed minExpiryThreshold);

    /**
     * @notice Emitted when the dispute buffer period is updated
     * @param disputeBufferPeriod The new dispute buffer period in seconds
     */
    event DisputeBufferPeriodSet(uint256 indexed disputeBufferPeriod);

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract
     * @param owner_ Address of the contract owner
     * @param assetManager_ Address of the asset manager
     * @param entityRegistry_ Address of the company wallet registry
     * @param escrowManager_ Address of the escrow manager
     * @param paymentExpiryThreshold_ Payment expiry threshold in seconds
     * @param minExpiryThreshold_ Minimum required order expiry duration in seconds
     * @param disputeBufferPeriod_ Dispute buffer period in seconds
     * @param marketFilter_ Address of the IMarketFilter resolver
     */
    function initialize(
        address owner_,
        address assetManager_,
        address entityRegistry_,
        address escrowManager_,
        uint256 paymentExpiryThreshold_,
        uint256 minExpiryThreshold_,
        uint256 disputeBufferPeriod_,
        address marketFilter_
    ) external;

    /**
     * @notice Sets the asset manager address
     * @param assetManager_ Address of the asset manager
     * @dev Only callable by addresses with the ADMIN role
     */
    function setAssetManager(address assetManager_) external;

    /**
     * @notice Sets the company wallet registry address
     * @param entityRegistry_ Address of the company wallet registry
     * @dev Only callable by addresses with the ADMIN role
     */
    function setEntityRegistry(address entityRegistry_) external;

    /**
     * @notice Sets the escrow manager address
     * @param escrowManager_ Address of the escrow manager
     * @dev Only callable by addresses with the ADMIN role
     */
    function setEscrowManager(address escrowManager_) external;

    /**
     * @notice Sets the IMarketFilter resolver address
     * @param marketFilter_ Address of the market filter resolver
     * @dev Only callable by addresses with the ADMIN role
     */
    function setMarketFilter(address marketFilter_) external;

    /**
     * @notice Authorize or revoke a delegate to place and cancel orders on behalf of the caller
     * @param delegate Address of the delegate
     * @param authorized True to authorize, false to revoke
     */
    function setDelegate(address delegate, bool authorized) external;

    /**
     * @notice Place a limit order to buy or sell bonds
     * @dev Automatically matches against existing orders and settles trades
     * @param input Order input parameters
     * @param onBehalfOf Trader address; pass address(0) for a direct (non-delegated) call
     * @return orderId Unique order identifier
     */
    function placeOrder(OrderInput calldata input, address onBehalfOf) external returns (uint256 orderId);

    /**
     * @notice Place an immediate-or-cancel multi-market BUY order filtered by the configured IMarketFilter
     * @dev Iterates active SELL markets, delegates filtering to IMarketFilter, and matches best-priced first
     * @dev Unmatched portion of totalAmount is discarded — no passive order is left in the book
     * @dev A synthetic Order with (tokenAddress=0, tokenId=0) is recorded for audit and trade linkage
     * @param input Batch order parameters including filter and trader constraints
     * @return orderId Unique identifier of the synthetic BUY order record
     */
    function placeBatchOrder(BatchOrderInput calldata input) external returns (uint256 orderId);

    /**
     * @notice Cancel an existing order
     * @param orderId Order to cancel
     * @param onBehalfOf Trader address; pass address(0) for a direct (non-delegated) call
     * @dev Only callable by the order trader or an authorized delegate acting on their behalf
     * @dev Works for expired orders as well and removes their remaining available amount from the orderbook
     */
    function cancelOrder(uint256 orderId, address onBehalfOf) external;

    /**
     * @notice Removes the available amount of an expired order from the orderbook
     * @param orderId Order to clean up
     * @dev Callable by anyone once the order expiry has strictly passed
     * @dev For SELL orders, withdraws the remaining available amount from escrow back to the order trader
     */
    function cleanupExpiredOrder(uint256 orderId) external;

    /**
     * @notice Mark a trade as paid by the buyer
     * @param tradeId ID of the trade to mark as paid
     * @dev Only callable by PAYMENT_HANDLER role
     * @dev Trade must be in PENDING status
     */
    function markTradePaid(uint256 tradeId) external;

    /**
     * @notice Mark a trade as unpaid after payment deadline expires
     * @param tradeId ID of the trade to mark as unpaid
     * @dev Callable by anyone after the payment deadline has passed
     * @dev Trade must be in PENDING status
     */
    function markTradeUnpaid(uint256 tradeId) external;

    /**
     * @notice Initiate a dispute for an unpaid trade
     * @param tradeId ID of the trade to dispute
     * @dev Only callable by the trade buyer
     * @dev Trade must be in UNPAID status and within the dispute buffer period
     */
    function initiateDispute(uint256 tradeId) external;

    /**
     * @notice Resolve a disputed trade
     * @param tradeId ID of the trade to resolve
     * @param status Resolved trade status, only PAID or UNPAID
     * @dev Only callable by ARBITRATOR role
     * @dev Trade must be in IN_DISPUTE status
     */
    function resolveDispute(uint256 tradeId, TradeStatus status) external;

    /**
     * @notice Settle a trade by transferring tokens from escrow or restoring order liquidity
     * @param tradeId ID of the trade to settle
     * @dev Anyone can call this after trade is PAID or UNPAID
     * @dev PAID: transfers escrow to buyer and finalizes trade as SETTLED
     * @dev UNPAID: reverts until dispute buffer expires, then returns matched amounts to available and finalizes trade as CANCELLED
     */
    function settleTrade(uint256 tradeId) external;

    /**
     * @notice Sets the payment expiry threshold
     * @param paymentExpiryThreshold_ The new payment expiry threshold in seconds
     * @dev Only callable by addresses with the ADMIN role
     * @dev Reverts if paymentExpiryThreshold_ is below MIN_PAYMENT_EXPIRY_THRESHOLD
     * @dev Reverts if paymentExpiryThreshold_ exceeds MAX_PAYMENT_EXPIRY_THRESHOLD
     */
    function setPaymentExpiryThreshold(uint256 paymentExpiryThreshold_) external;

    /**
     * @notice Sets the minimum order expiry threshold
     * @param minExpiryThreshold_ The new minimum required order expiry duration in seconds
     * @dev Only callable by addresses with the ADMIN role
     * @dev Reverts if minExpiryThreshold_ is below MIN_ORDER_EXPIRY_THRESHOLD
     */
    function setMinExpiryThreshold(uint256 minExpiryThreshold_) external;

    /**
     * @notice Set the frozen state of an order
     * @param orderId The ID of the order to freeze or unfreeze
     * @param frozen True to freeze, false to unfreeze
     * @param reason Opaque identifier for the legal/compliance reason
     * @dev Only callable by addresses with FREEZE_ROLE
     * @dev Order must exist; reason must be non-zero; emits OrderFrozenSet
     * @dev Frozen orders cannot be cancelled or used in matching
     */
    function setOrderFrozen(uint256 orderId, bool frozen, bytes32 reason) external;

    /**
     * @notice Set the frozen state of a trade
     * @param tradeId The ID of the trade to freeze or unfreeze
     * @param frozen True to freeze, false to unfreeze
     * @param reason Opaque identifier for the legal/compliance reason
     * @dev Only callable by addresses with FREEZE_ROLE
     * @dev Trade must exist; reason must be non-zero; emits TradeFrozenSet
     * @dev Frozen trades cannot be marked as paid, unpaid, or settled
     */
    function setTradeFrozen(uint256 tradeId, bool frozen, bytes32 reason) external;

    /**
     * @notice Seize available amount from a frozen order
     * @param orderId The ID of the order to seize from
     * @param beneficiary The address that will receive the seized tokens
     * @param reason Opaque identifier for the legal/compliance reason
     * @dev Only callable by addresses with SEIZURE_ROLE
     * @dev Order must be frozen and have non-zero available amount
     * @dev Sets available to 0 and transfers to beneficiary via escrow
     */
    function seizeOrder(uint256 orderId, address beneficiary, bytes32 reason) external;

    /**
     * @notice Seize a frozen trade
     * @param tradeId The ID of the trade to seize
     * @param beneficiary The address that will receive the seized tokens
     * @param reason Opaque identifier for the legal/compliance reason
     * @dev Only callable by addresses with SEIZURE_ROLE
     * @dev Trade must be frozen, parent SELL order must be frozen, and trade must be in
     *      PENDING/PAID/UNPAID/IN_DISPUTE
     * @dev Transfers trade amount to beneficiary and sets trade status to SEIZED
     */
    function seizeTrade(uint256 tradeId, address beneficiary, bytes32 reason) external;

    /**
     * @notice Sets the dispute buffer period
     * @param disputeBufferPeriod_ The new dispute buffer period in seconds
     * @dev Only callable by addresses with the ADMIN role
     * @dev Reverts if disputeBufferPeriod_ is below MIN_DISPUTE_BUFFER_PERIOD
     * @dev Reverts if disputeBufferPeriod_ exceeds MAX_DISPUTE_BUFFER_PERIOD
     */
    function setDisputeBufferPeriod(uint256 disputeBufferPeriod_) external;

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the asset manager address
     * @return address The asset manager address
     */
    function assetManager() external view returns (address);

    /**
     * @notice Gets the company wallet registry address
     * @return address The company wallet registry address
     */
    function entityRegistry() external view returns (address);

    /**
     * @notice Gets the escrow manager address
     * @return address The escrow manager address
     */
    function escrowManager() external view returns (address);

    /**
     * @notice Gets the IMarketFilter resolver address
     * @return address The market filter address
     */
    function marketFilter() external view returns (address);

    /**
     * @notice Gets the payment expiry threshold
     * @return uint256 The payment expiry threshold in seconds
     */
    function paymentExpiryThreshold() external view returns (uint256);

    /**
     * @notice Gets the minimum order expiry threshold
     * @return uint256 The minimum required order expiry duration in seconds
     */
    function minExpiryThreshold() external view returns (uint256);

    /**
     * @notice Gets the dispute buffer period
     * @return uint256 The dispute buffer period in seconds
     */
    function disputeBufferPeriod() external view returns (uint256);

    /**
     * @notice Get order details
     * @param orderId Order identifier
     * @return order Order struct
     */
    function getOrder(uint256 orderId) external view returns (Order memory order);

    /**
     * @notice Get the current order book for a token
     * @param tokenAddress Address of the token contract
     * @param tokenId Token ID
     * @return buyOrders Active non-expired buy orders sorted by price (best first: descending)
     * @return sellOrders Active non-expired sell orders sorted by price (best first: ascending)
     */
    function getOrderBook(address tokenAddress, uint256 tokenId)
        external
        view
        returns (Order[] memory buyOrders, Order[] memory sellOrders);

    /**
     * @notice Get trade details
     * @param tradeId Trade identifier
     * @return trade Trade struct
     */
    function getTrade(uint256 tradeId) external view returns (Trade memory trade);

    /**
     * @notice Get all trade IDs associated with an order
     * @param orderId Order identifier
     * @return tradeIds Array of trade IDs for this order
     */
    function getTradeIdsByOrderId(uint256 orderId) external view returns (uint256[] memory tradeIds);

    /**
     * @notice Get the escrow ID associated with a sell order
     * @param orderId Order identifier
     * @return escrowId EscrowManager escrow ID linked to the order
     */
    function getEscrowIdByOrderId(uint256 orderId) external view returns (uint256 escrowId);

    /**
     * @notice Check if a trader is allowed to match against an order
     * @param orderId Order identifier
     * @param trader Address to check
     * @return allowed True if the trader is allowed
     */
    function isTraderAllowedForOrder(uint256 orderId, address trader) external view returns (bool allowed);

    /**
     * @notice Returns the enumerable list of markets with at least one active SELL order
     * @return markets Array of (tokenAddress, tokenId) pairs; bounded by MAX_ACTIVE_SELL_MARKETS
     */
    function activeSellMarkets() external view returns (Market[] memory markets);

    /**
     * @notice Returns the Time-Weighted Average Price over the interval ending now
     * @dev Inspired by Uniswap V3 on-chain oracle.  Uses a 256-slot circular buffer of
     *      (timestamp, cumulativePrice) observations; observation lookup is O(log n)
     *      via binary search.
     *
     *      Algorithm:
     *        targetTime = block.timestamp - secondsAgo
     *        Find the observation with the largest timestamp <= targetTime (floor).
     *        If all observations are newer, fall back to the oldest one.
     *        currentCumulative = latestObs.cumulativePrice + lastPrice * (now - latestObs.timestamp)
     *        TWAP = (currentCumulative - foundObs.cumulativePrice) / (now - foundObs.timestamp)
     *
     * @param tokenAddress  Token contract address
     * @param tokenId       Token ID (ISIN tranche)
     * @param secondsAgo    How many seconds back the observation window starts
     * @return unitPrice    TWAP unit price over [block.timestamp - secondsAgo, block.timestamp]
     */
    function getTWAP(address tokenAddress, uint256 tokenId, uint256 secondsAgo)
        external
        view
        returns (uint256 unitPrice);

    /**
     * @notice Returns a single raw observation from the circular buffer
     * @param tokenAddress  Token contract address
     * @param tokenId       Token ID
     * @param index         Physical index in the circular buffer [0, MAX_RECENT_OBSERVATIONS)
     * @return observation  The stored Observation struct
     */
    function getObservation(address tokenAddress, uint256 tokenId, uint16 index)
        external
        view
        returns (Observation memory observation);

    /**
     * @notice Returns the number of valid observations currently stored for a token
     * @param tokenAddress  Token contract address
     * @param tokenId       Token ID
     * @return count        Number of observations in [1, MAX_RECENT_OBSERVATIONS]; 0 if no trades yet
     */
    function getObservationCount(address tokenAddress, uint256 tokenId) external view returns (uint16 count);

    /**
     * @notice Returns the last executed trade price for a token
     * @dev This is the price that will be projected forward until the next trade occurs
     * @param tokenAddress  Token contract address
     * @param tokenId       Token ID
     * @return price        Last trade unit price; 0 if no trades have occurred
     */
    function getLastTradedPrice(address tokenAddress, uint256 tokenId) external view returns (uint256 price);
}
