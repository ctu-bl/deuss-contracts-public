// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IOrderbookMarketplace} from "./interfaces/IOrderbookMarketplace.sol";

/* solhint-disable max-states-count */

/**
 * @title OrderbookMarketplaceStorage
 * @author DEUSS Team
 * @notice Storage contract for OrderbookMarketplace that defines all state variables and constants
 * @dev This contract contains all storage variables used by OrderbookMarketplace
 * @dev Uses ERC-7201 namespaced storage for all mutable state
 */
abstract contract OrderbookMarketplaceStorage {
    /**
     * @notice Per-token TWAP state: circular observation buffer + last price
     * @dev Each Observation (uint32 timestamp + uint224 cumulativePrice) packs into exactly
     *      one 32-byte slot. The 256-slot array therefore occupies 256 consecutive storage
     *      slots inside the mapping value layout.
     *      currentIndex – physical index of the most-recently written observation
     *      observationCount – number of valid entries currently in the buffer [0, 256]
     *      lastPrice – unit price of the most recent trade; projected forward in TWAP reads
     */
    struct TWAPState {
        IOrderbookMarketplace.Observation[256] observations;
        uint16 currentIndex;
        uint16 observationCount;
        uint256 lastPrice;
    }

    /**
     * @notice All mutable OrderbookMarketplace state.
     * @custom:storage-location erc7201:deuss.orderbookMarketplace.storage
     */
    struct OrderbookMarketplaceState {
        /// @notice Address of the configured asset manager contract
        address assetManager;
        /// @notice Address of the entity registry contract
        address entityRegistry;
        /// @notice Address of the escrow manager contract
        address escrowManager;
        /// @notice Address of the pluggable IMarketFilter resolver used by placeBatchOrder()
        address marketFilter;
        /// @notice Payment expiry threshold in seconds
        uint256 paymentExpiryThreshold;
        /// @notice Dispute buffer period in seconds
        uint256 disputeBufferPeriod;
        /// @notice Minimum required order expiry duration in seconds
        uint256 minExpiryThreshold;
        /// @notice Counter for generating unique order IDs
        uint256 ordersCount;
        /// @notice Counter for generating unique trade IDs
        uint256 tradesCount;
        /// @notice Mapping of order ID to Order struct
        mapping(uint256 orderId => IOrderbookMarketplace.Order order) orders;
        /// @notice Mapping of trade ID to Trade struct
        mapping(uint256 tradeId => IOrderbookMarketplace.Trade trade) trades;
        /// @notice Mapping of order ID to trader filter addresses
        mapping(uint256 orderId => mapping(address trader => bool)) orderTraderFilter;
        /// @notice Per-trader delegate authorization
        mapping(address trader => mapping(address delegate => bool)) delegations;
        /// @notice Mapping of order ID to frozen status
        mapping(uint256 orderId => bool frozen) orderFrozen;
        /// @notice Mapping of trade ID to frozen status
        mapping(uint256 tradeId => bool frozen) tradeFrozen;
        /// @notice Mapping of token address and token ID to buy order IDs
        mapping(address tokenAddress => mapping(uint256 tokenId => uint256[] buyOrderIds)) buyOrderIdsByTokenId;
        /// @notice Mapping of token address and token ID to sell order IDs
        mapping(address tokenAddress => mapping(uint256 tokenId => uint256[] sellOrderIds)) sellOrderIdsByTokenId;
        /// @notice Mapping of order ID to trade IDs
        mapping(uint256 orderId => uint256[] tradeIds) tradeIdsByOrderId;
        /// @notice Mapping of sell order ID to EscrowManager escrow ID
        mapping(uint256 orderId => uint256 escrowId) escrowIdByOrderId;
        /// @notice TWAP state keyed by (tokenAddress, tokenId)
        mapping(address tokenAddress => mapping(uint256 tokenId => TWAPState)) twapStates;
        /// @notice Enumerable set of markets that currently have at least one active SELL order
        IOrderbookMarketplace.Market[] activeSellMarkets;
        /// @notice 1-based index into activeSellMarkets for a given (tokenAddress, tokenId)
        mapping(address tokenAddress => mapping(uint256 tokenId => uint256 indexPlusOne)) activeSellMarketIndex;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

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
     * @notice Minimum value for the order expiry threshold configuration
     * @dev The minimum required order expiry duration must be at least this value
     */
    uint256 public constant MIN_ORDER_EXPIRY_THRESHOLD = 30 minutes;

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
     * @notice ERC-7201 storage location for all mutable orderbook marketplace state
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("deuss.orderbookMarketplace.storage"))) - 1))
     *      & ~bytes32(uint256(0xff))
     */
    // slither-disable-next-line unused-state
    bytes32 internal constant _ORDERBOOK_MARKETPLACE_STORAGE_LOCATION =
        0x79ea8b011a47713354185639eb0111ae61d66b4fa2e4fcda0a25dd7bc2691100;

    /**
     * @notice Returns the namespaced orderbook marketplace storage
     * @return $ Namespaced orderbook marketplace storage pointer
     */
    // slither-disable-start uninitialized-storage
    // slither-disable-next-line assembly
    function _orderbookMarketplaceStorage() internal pure returns (OrderbookMarketplaceState storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _ORDERBOOK_MARKETPLACE_STORAGE_LOCATION
        }
    }
    // slither-disable-end uninitialized-storage
}
