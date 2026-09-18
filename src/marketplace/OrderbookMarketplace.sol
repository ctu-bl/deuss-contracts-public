// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Errors} from "../libs/Errors.sol";
import {Initializable} from "solady/src/utils/Initializable.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import {IOrderbookMarketplace} from "./interfaces/IOrderbookMarketplace.sol";
import {OrderbookMarketplaceStorage} from "./OrderbookMarketplaceStorage.sol";
import {OwnableRolesExtension} from "../utils/OwnableRolesExtension.sol";
import {IAssetManager} from "./interfaces/IAssetManager.sol";
import {IEntityRegistry} from "../registry/interfaces/IEntityRegistry.sol";
import {IEscrowManager} from "./interfaces/IEscrowManager.sol";
import {IMarketFilter} from "./interfaces/IMarketFilter.sol";

/// @title OrderbookMarketplace
/// @notice Orderbook marketplace for bond trading with price-time priority matching
/// @author DEUSS Team
contract OrderbookMarketplace is
    IOrderbookMarketplace,
    Initializable,
    ReentrancyGuard,
    OrderbookMarketplaceStorage,
    OwnableRolesExtension
{
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Role for administrative functions
     */
    uint256 public constant ADMIN = _ROLE_0;

    /**
     * @notice Role for handling payment confirmations
     */
    uint256 public constant PAYMENT_HANDLER = _ROLE_1;

    /**
     * @notice Maximum number of TWAP observations retained per token in the circular buffer
     * @dev 256 slots = one uint8 index wraps naturally; each slot is exactly 1 storage word
     */
    uint16 public constant MAX_RECENT_OBSERVATIONS = 256;

    /**
     * @notice Role for arbitrating payment disputes
     */
    uint256 public constant ARBITRATOR = _ROLE_2;

    /**
     * @notice Role for seizing frozen orders and trades
     */
    uint256 public constant SEIZURE_ROLE = _ROLE_3;

    /**
     * @notice Role for freezing/unfreezing orders and trades
     */
    uint256 public constant FREEZE_ROLE = _ROLE_4;

    /**
     * @notice Hard cap on the number of concurrently active SELL markets
     * @dev Bounds the iteration cost of placeBatchOrder()
     */
    uint256 public constant MAX_ACTIVE_SELL_MARKETS = 100;

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Disables direct initialization on the implementation contract
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IOrderbookMarketplace
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
    ) external initializer {
        _initializeOwner(owner_);
        _setAssetManager(assetManager_);
        _setEntityRegistry(entityRegistry_);
        _setEscrowManager(escrowManager_);
        _setPaymentExpiryThreshold(paymentExpiryThreshold_);
        _setMinExpiryThreshold(minExpiryThreshold_);
        _setDisputeBufferPeriod(disputeBufferPeriod_);
        _setMarketFilter(marketFilter_);
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function setAssetManager(address assetManager_) external onlyRoles(ADMIN) {
        require(assetManager_ != address(0), Errors.ZeroAddress());

        _setAssetManager(assetManager_);
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function setEntityRegistry(address entityRegistry_) external onlyRoles(ADMIN) {
        require(entityRegistry_ != address(0), Errors.ZeroAddress());

        _setEntityRegistry(entityRegistry_);
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function setEscrowManager(address escrowManager_) external onlyRoles(ADMIN) {
        require(escrowManager_ != address(0), Errors.ZeroAddress());

        _setEscrowManager(escrowManager_);
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function setPaymentExpiryThreshold(uint256 paymentExpiryThreshold_) external onlyRoles(ADMIN) {
        _setPaymentExpiryThreshold(paymentExpiryThreshold_);
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function setMinExpiryThreshold(uint256 minExpiryThreshold_) external onlyRoles(ADMIN) {
        _setMinExpiryThreshold(minExpiryThreshold_);
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function setDisputeBufferPeriod(uint256 disputeBufferPeriod_) external onlyRoles(ADMIN) {
        _setDisputeBufferPeriod(disputeBufferPeriod_);
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function setMarketFilter(address marketFilter_) external onlyRoles(ADMIN) {
        _setMarketFilter(marketFilter_);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function setDelegate(address delegate, bool authorized) external {
        require(delegate != address(0), Errors.ZeroAddress());

        _orderbookMarketplaceStorage().delegations[msg.sender][delegate] = authorized;

        emit DelegateSet(msg.sender, delegate, authorized);
    }

    // slither-disable-start reentrancy-no-eth,reentrancy-events
    /**
     * @inheritdoc IOrderbookMarketplace
     * @param input Order input parameters
     * @param onBehalfOf Address on whose behalf the order is placed (zero for self)
     * @return orderId Unique order identifier
     */
    function placeOrder(OrderInput calldata input, address onBehalfOf) external nonReentrant returns (uint256 orderId) {
        _validatePlaceOrderInputs(input.totalAmount, input.minPrice, input.maxPrice, input.minMatchAmount);
        _validateTraderFilter(input.traderFilterMode, input.traderFilterAddresses);
        _validateOrderExpiryThreshold(input.expiry);
        _validateAsset(input.tokenAddress, input.tokenId, input.totalAmount);
        address effectiveTrader = _resolveEffectiveTrader(onBehalfOf);

        orderId = _createOrderFromInput(input, effectiveTrader);
        _storeTraderFilter(orderId, input.traderFilterAddresses);

        uint256 unfilledAmount = _processOrderPlacement(input, orderId, effectiveTrader);
        _updatePlacedOrderAmounts(orderId, input.totalAmount, unfilledAmount);

        Order storage order = _orderbookMarketplaceStorage().orders[orderId];
        emit OrderPlaced(
            orderId,
            order.tokenId,
            order.trader,
            order.tokenAddress,
            order.amounts.total,
            order.amounts.available,
            order.minPrice,
            order.maxPrice,
            order.minMatchAmount,
            order.traderFilterMode,
            order.side,
            order.expiry
        );
    }

    // slither-disable-start timestamp
    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function placeBatchOrder(BatchOrderInput calldata input) external nonReentrant returns (uint256 orderId) {
        _validatePlaceOrderInputs(input.totalAmount, input.minPrice, input.maxPrice, input.minMatchAmount);
        _validateTraderFilter(input.traderFilterMode, input.traderFilterAddresses);
        _validateMsgSender(msg.sender);

        // Synthetic BUY Order record (tokenAddress=0, tokenId=0). Not pushed into _buyOrderIdsByTokenId:
        // the batch order is immediate-or-cancel and never participates in future matches.
        orderId = ++_orderbookMarketplaceStorage().ordersCount;
        _orderbookMarketplaceStorage().orders[orderId] = Order({
            tokenAddress: address(0),
            tokenId: 0,
            trader: msg.sender,
            minPrice: input.minPrice,
            maxPrice: input.maxPrice,
            minMatchAmount: input.minMatchAmount,
            traderFilterMode: input.traderFilterMode,
            side: OrderSide.BUY,
            timestamp: block.timestamp,
            expiry: 0,
            amounts: OrderAmounts({total: input.totalAmount, available: 0, inDeals: 0, sold: 0})
        });
        _storeTraderFilter(orderId, input.traderFilterAddresses);

        Market[] memory sorted = _buildSortedMarketList(input.filterData, input.maxPrice);
        uint256 matched = input.totalAmount - _matchBatchBuyOrder(sorted, orderId, input);

        emit BatchOrderPlaced(
            orderId,
            msg.sender,
            input.totalAmount,
            matched,
            input.minPrice,
            input.maxPrice,
            input.minMatchAmount,
            input.traderFilterMode
        );

        if (matched > 0) {
            _orderbookMarketplaceStorage().orders[orderId].amounts.inDeals = matched;
        } else {
            _deleteOrder(orderId, _orderbookMarketplaceStorage().orders[orderId]);
        }
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function cancelOrder(uint256 orderId, address onBehalfOf) external nonReentrant {
        Order storage order = _orderbookMarketplaceStorage().orders[orderId];
        require(order.trader != address(0), Errors.OrderbookMarketplace__OrderNotFound(orderId));
        require(!_orderbookMarketplaceStorage().orderFrozen[orderId], Errors.OrderbookMarketplace__OrderFrozen(orderId));

        // Intentionally does not use _resolveEffectiveTrader(): cancellation must first read
        // order.trader to verify ownership, so the direct path (onBehalfOf == 0) can skip the
        // entityRegistry check and simply assert msg.sender == order.trader.
        // _resolveEffectiveTrader() always validates msg.sender against the registry, which
        // would reject plain EOA callers even when no registry is configured — a different
        // contract-of-use than what cancelOrder requires.
        address effectiveTrader;
        if (onBehalfOf == address(0)) {
            require(msg.sender == order.trader, Errors.OrderbookMarketplace__NotAuthorized(msg.sender));
            effectiveTrader = msg.sender;
        } else {
            _validateMsgSender(msg.sender);
            _validateMsgSender(onBehalfOf);
            _validateDelegate(onBehalfOf, msg.sender);
            effectiveTrader = onBehalfOf;
            require(order.trader == effectiveTrader, Errors.OrderbookMarketplace__NotAuthorized(msg.sender));
        }

        // Synthetic batch BUY orders carry tokenAddress=0 and are IOC by construction.
        // A cancelled trade (markTradeUnpaid → settleTrade) can re-credit their `available` amount,
        // but they must never be cancellable: they have no escrow and are not on the book.
        require(order.tokenAddress != address(0), Errors.OrderbookMarketplace__BatchOrderCannotBeCancelled(orderId));

        _cleanupOrder(orderId, order);
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function cleanupExpiredOrder(uint256 orderId) external {
        Order storage order = _orderbookMarketplaceStorage().orders[orderId];
        require(order.trader != address(0), Errors.OrderbookMarketplace__OrderNotFound(orderId));
        require(!_orderbookMarketplaceStorage().orderFrozen[orderId], Errors.OrderbookMarketplace__OrderFrozen(orderId));
        require(
            _isOrderExpired(order.expiry),
            Errors.OrderbookMarketplace__OrderNotExpired(orderId, order.expiry, block.timestamp)
        );
        _cleanupOrder(orderId, order);
    }

    // slither-disable-end timestamp
    // slither-disable-end reentrancy-no-eth,reentrancy-events

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function markTradePaid(uint256 tradeId) external onlyRoles(PAYMENT_HANDLER) nonReentrant {
        Trade storage trade = _orderbookMarketplaceStorage().trades[tradeId];

        _validateTradeStatus(trade, TradeStatus.PENDING);
        require(!_orderbookMarketplaceStorage().tradeFrozen[tradeId], Errors.OrderbookMarketplace__TradeFrozen(tradeId));

        trade.status = TradeStatus.PAID;

        emit TradePaid(tradeId, trade.buyer, trade.seller);
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function markTradeUnpaid(uint256 tradeId) external nonReentrant {
        Trade storage trade = _orderbookMarketplaceStorage().trades[tradeId];

        _validateTradeStatus(trade, TradeStatus.PENDING);
        require(!_orderbookMarketplaceStorage().tradeFrozen[tradeId], Errors.OrderbookMarketplace__TradeFrozen(tradeId));

        // slither-disable-next-line timestamp
        require(block.timestamp > trade.paymentDeadline, Errors.OrderbookMarketplace__TradeNotExpired());

        trade.status = TradeStatus.UNPAID;

        emit TradeUnpaid(tradeId, trade.buyer, trade.seller);
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function initiateDispute(uint256 tradeId) external nonReentrant {
        Trade storage trade = _orderbookMarketplaceStorage().trades[tradeId];

        _validateTradeStatus(trade, TradeStatus.UNPAID);
        require(msg.sender == trade.buyer, Errors.OrderbookMarketplace__NotAuthorized(msg.sender));
        // slither-disable-next-line timestamp
        require(!(block.timestamp > trade.disputeBuffer), Errors.OrderbookMarketplace__DisputePeriodExpired());

        trade.status = TradeStatus.IN_DISPUTE;

        emit TradeDisputed(tradeId, trade.buyer, trade.seller);
    }

    // slither-disable-start timestamp
    /**
     * @inheritdoc IOrderbookMarketplace
     * @param tradeId The ID of the trade to resolve
     * @param status The new status for the trade (PAID or UNPAID)
     */
    function resolveDispute(uint256 tradeId, TradeStatus status) external onlyRoles(ARBITRATOR) nonReentrant {
        Trade storage trade = _orderbookMarketplaceStorage().trades[tradeId];

        require(trade.tradeId != 0, Errors.OrderbookMarketplace__TradeNotFound(tradeId));
        require(trade.status == TradeStatus.IN_DISPUTE, Errors.OrderbookMarketplace__TradeNotInDispute());
        require(
            status == TradeStatus.PAID || status == TradeStatus.UNPAID,
            Errors.OrderbookMarketplace__InvalidDisputeResolution(uint8(status))
        );

        trade.disputeBuffer = 0;
        trade.status = status;

        emit TradeDisputeResolved(tradeId, status, msg.sender);
    }

    // slither-disable-end timestamp

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function settleTrade(uint256 tradeId) external nonReentrant {
        Trade storage trade = _orderbookMarketplaceStorage().trades[tradeId];

        require(trade.tradeId != 0, Errors.OrderbookMarketplace__TradeNotFound(tradeId));
        require(!_orderbookMarketplaceStorage().tradeFrozen[tradeId], Errors.OrderbookMarketplace__TradeFrozen(tradeId));
        require(
            !_orderbookMarketplaceStorage().orderFrozen[trade.sellOrderId],
            Errors.OrderbookMarketplace__OrderFrozen(trade.sellOrderId)
        );
        require(
            !_orderbookMarketplaceStorage().orderFrozen[trade.buyOrderId],
            Errors.OrderbookMarketplace__OrderFrozen(trade.buyOrderId)
        );

        TradeStatus originalStatus = trade.status;
        bool isUnpaid = originalStatus == TradeStatus.UNPAID;

        require(
            isUnpaid || originalStatus == TradeStatus.PAID,
            Errors.OrderbookMarketplace__TradeNotSettleable(uint8(originalStatus))
        );
        if (isUnpaid) {
            // slither-disable-next-line timestamp
            require(block.timestamp > trade.disputeBuffer, Errors.OrderbookMarketplace__DisputePeriodNotExpired());
        }

        // Update SELL order amounts
        Order storage sellOrder = _orderbookMarketplaceStorage().orders[trade.sellOrderId];
        if (sellOrder.trader != address(0)) {
            // Fully settled paid-path order - delete to optimize matching loop
            if (!isUnpaid && sellOrder.amounts.available == 0 && sellOrder.amounts.inDeals == trade.amount) {
                _deleteOrder(trade.sellOrderId, sellOrder);
            } else {
                sellOrder.amounts.inDeals -= trade.amount;
                if (isUnpaid) {
                    sellOrder.amounts.available += trade.amount;
                } else {
                    sellOrder.amounts.sold += trade.amount;
                }
            }
        }

        // Update BUY order amounts
        Order storage buyOrder = _orderbookMarketplaceStorage().orders[trade.buyOrderId];
        if (buyOrder.trader != address(0)) {
            bool fullySettledPaid =
                !isUnpaid && buyOrder.amounts.available == 0 && buyOrder.amounts.inDeals == trade.amount;
            bool syntheticBatchLastTrade =
                buyOrder.tokenAddress == address(0) && buyOrder.amounts.inDeals == trade.amount;
            if (fullySettledPaid || syntheticBatchLastTrade) {
                _deleteOrder(trade.buyOrderId, buyOrder);
            } else {
                buyOrder.amounts.inDeals -= trade.amount;
                if (isUnpaid) {
                    buyOrder.amounts.available += trade.amount;
                } else {
                    buyOrder.amounts.sold += trade.amount;
                }
            }
        }

        trade.status = isUnpaid ? TradeStatus.CANCELLED : TradeStatus.SETTLED;

        if (!isUnpaid) {
            IEscrowManager(_orderbookMarketplaceStorage().escrowManager)
                .claim(_orderbookMarketplaceStorage().escrowIdByOrderId[trade.sellOrderId], trade.amount, trade.buyer);
        }

        emit TradeSettled(tradeId, trade.buyer, trade.amount);
    }

    /*//////////////////////////////////////////////////////////////
                        FREEZE/SEIZURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // slither-disable-start timestamp
    /**
     * @inheritdoc IOrderbookMarketplace
     * @param orderId The ID of the order to freeze or unfreeze
     * @param frozen True to freeze, false to unfreeze
     * @param reason Opaque identifier for the legal/compliance reason
     */
    function setOrderFrozen(uint256 orderId, bool frozen, bytes32 reason) external onlyRoles(FREEZE_ROLE) {
        Order storage order = _orderbookMarketplaceStorage().orders[orderId];
        require(order.trader != address(0), Errors.OrderbookMarketplace__OrderNotFound(orderId));
        require(reason != bytes32(0), Errors.OrderbookMarketplace__ZeroFreezeReason());

        _orderbookMarketplaceStorage().orderFrozen[orderId] = frozen;
        emit OrderFrozenSet(orderId, frozen, reason, msg.sender);
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function setTradeFrozen(uint256 tradeId, bool frozen, bytes32 reason) external onlyRoles(FREEZE_ROLE) {
        Trade storage trade = _orderbookMarketplaceStorage().trades[tradeId];
        require(trade.tradeId != 0, Errors.OrderbookMarketplace__TradeNotFound(tradeId));
        require(reason != bytes32(0), Errors.OrderbookMarketplace__ZeroFreezeReason());

        _orderbookMarketplaceStorage().tradeFrozen[tradeId] = frozen;
        emit TradeFrozenSet(tradeId, frozen, reason, msg.sender);
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function seizeOrder(uint256 orderId, address beneficiary, bytes32 reason) external onlyRoles(SEIZURE_ROLE) {
        Order storage order = _orderbookMarketplaceStorage().orders[orderId];
        require(order.trader != address(0), Errors.OrderbookMarketplace__OrderNotFound(orderId));
        require(
            _orderbookMarketplaceStorage().orderFrozen[orderId],
            Errors.OrderbookMarketplace__CannotSeizeUnfrozenOrder(orderId)
        );
        require(beneficiary != address(0), Errors.ZeroAddress());
        require(reason != bytes32(0), Errors.OrderbookMarketplace__ZeroReason());

        uint256 seizeAmount = order.amounts.available;
        require(seizeAmount != 0, Errors.OrderbookMarketplace__NoAvailableAmountToSeize(orderId));

        order.amounts.available = 0;
        OrderSide side = order.side;

        // Delete order if no pending trades remain, otherwise it stays dead
        // in the sorted arrays (unmatchable with available=0, uncancellable while frozen)
        if (order.amounts.inDeals == 0) {
            _deleteOrder(orderId, order);
        }

        if (side == OrderSide.SELL) {
            // slither-disable-next-line reentrancy-events
            IEscrowManager(_orderbookMarketplaceStorage().escrowManager)
                .claim(_orderbookMarketplaceStorage().escrowIdByOrderId[orderId], seizeAmount, beneficiary);
        } else {
            seizeAmount = 0;
        }

        emit OrderSeized(orderId, beneficiary, seizeAmount, reason, msg.sender);
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function seizeTrade(uint256 tradeId, address beneficiary, bytes32 reason) external onlyRoles(SEIZURE_ROLE) {
        Trade storage trade = _orderbookMarketplaceStorage().trades[tradeId];
        require(trade.tradeId != 0, Errors.OrderbookMarketplace__TradeNotFound(tradeId));
        require(
            _orderbookMarketplaceStorage().tradeFrozen[tradeId],
            Errors.OrderbookMarketplace__CannotSeizeUnfrozenTrade(tradeId)
        );

        uint256 sellOrderId = trade.sellOrderId;
        require(
            _orderbookMarketplaceStorage().orderFrozen[sellOrderId],
            Errors.OrderbookMarketplace__ParentOrderNotFrozen(sellOrderId)
        );
        require(beneficiary != address(0), Errors.ZeroAddress());
        require(reason != bytes32(0), Errors.OrderbookMarketplace__ZeroReason());
        TradeStatus status = trade.status;
        require(
            status == TradeStatus.PENDING || status == TradeStatus.PAID || status == TradeStatus.UNPAID
                || status == TradeStatus.IN_DISPUTE,
            Errors.OrderbookMarketplace__InvalidTradeStatus(uint8(status))
        );

        uint256 amount = trade.amount;

        // Effects before external call (checks-effects-interactions)
        trade.status = TradeStatus.SEIZED;

        Order storage sellOrder = _orderbookMarketplaceStorage().orders[sellOrderId];
        sellOrder.amounts.inDeals -= amount;
        // Delete the order if it was fully drained by this seizure, otherwise it would
        // remain dead in the sorted arrays (unmatchable and uncancellable).
        if (sellOrder.amounts.available == 0 && sellOrder.amounts.inDeals == 0) {
            _deleteOrder(sellOrderId, sellOrder);
        }

        uint256 buyOrderId = trade.buyOrderId;
        Order storage buyOrder = _orderbookMarketplaceStorage().orders[buyOrderId];
        buyOrder.amounts.inDeals -= amount;
        if (buyOrder.amounts.available == 0 && buyOrder.amounts.inDeals == 0) {
            _deleteOrder(buyOrderId, buyOrder);
        }

        // slither-disable-next-line reentrancy-events
        IEscrowManager(_orderbookMarketplaceStorage().escrowManager)
            .claim(_orderbookMarketplaceStorage().escrowIdByOrderId[sellOrderId], amount, beneficiary);

        emit TradeSeized(tradeId, sellOrderId, beneficiary, amount, reason, msg.sender);
    }

    // slither-disable-end timestamp

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function assetManager() external view returns (address) {
        return _orderbookMarketplaceStorage().assetManager;
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function entityRegistry() external view returns (address) {
        return _orderbookMarketplaceStorage().entityRegistry;
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function escrowManager() external view returns (address) {
        return _orderbookMarketplaceStorage().escrowManager;
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function paymentExpiryThreshold() external view returns (uint256) {
        return _orderbookMarketplaceStorage().paymentExpiryThreshold;
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function minExpiryThreshold() external view returns (uint256) {
        return _orderbookMarketplaceStorage().minExpiryThreshold;
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function disputeBufferPeriod() external view returns (uint256) {
        return _orderbookMarketplaceStorage().disputeBufferPeriod;
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function marketFilter() external view returns (address) {
        return _orderbookMarketplaceStorage().marketFilter;
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function getOrder(uint256 orderId) external view returns (Order memory) {
        return _orderbookMarketplaceStorage().orders[orderId];
    }

    // slither-disable-start timestamp
    /**
     * @inheritdoc IOrderbookMarketplace
     * @param tokenAddress Asset contract whose order book is being queried
     * @param tokenId Asset identifier whose order book is being queried
     * @return buyOrders Buy orders sorted by price (best first: descending)
     * @return sellOrders Sell orders sorted by price (best first: ascending)
     */
    function getOrderBook(address tokenAddress, uint256 tokenId)
        external
        view
        returns (Order[] memory buyOrders, Order[] memory sellOrders)
    {
        uint256[] storage buyOrderIds = _orderbookMarketplaceStorage().buyOrderIdsByTokenId[tokenAddress][tokenId];
        uint256[] storage sellOrderIds = _orderbookMarketplaceStorage().sellOrderIdsByTokenId[tokenAddress][tokenId];

        // Count matchable orders: available > 0 AND not frozen — mirrors the matching loops
        uint256 activeBuyCount;
        uint256 activeSellCount;

        uint256 buyOrderLength = buyOrderIds.length;
        for (uint256 i; i < buyOrderLength;) {
            uint256 id = buyOrderIds[i];
            Order storage order = _orderbookMarketplaceStorage().orders[id];
            if (
                order.amounts.available != 0 && !_orderbookMarketplaceStorage().orderFrozen[id]
                    && !_isOrderExpired(order.expiry)
            ) {
                ++activeBuyCount;
            }
            unchecked {
                ++i;
            }
        }

        uint256 sellOrderLength = sellOrderIds.length;
        for (uint256 i; i < sellOrderLength;) {
            uint256 id = sellOrderIds[i];
            Order storage order = _orderbookMarketplaceStorage().orders[id];
            if (
                order.amounts.available != 0 && !_orderbookMarketplaceStorage().orderFrozen[id]
                    && !_isOrderExpired(order.expiry)
            ) {
                ++activeSellCount;
            }
            unchecked {
                ++i;
            }
        }

        buyOrders = new Order[](activeBuyCount);
        sellOrders = new Order[](activeSellCount);

        uint256 buyIndex;
        for (uint256 i = buyOrderLength; i > 0;) {
            unchecked {
                --i;
            }
            uint256 id = buyOrderIds[i];
            if (_orderbookMarketplaceStorage().orderFrozen[id]) {
                continue;
            }
            Order memory order = _orderbookMarketplaceStorage().orders[id];
            if (order.amounts.available > 0 && !_isOrderExpired(order.expiry)) {
                buyOrders[buyIndex] = order;
                ++buyIndex;
            }
        }

        uint256 sellIndex;
        for (uint256 i = sellOrderLength; i > 0;) {
            unchecked {
                --i;
            }
            uint256 id = sellOrderIds[i];
            if (_orderbookMarketplaceStorage().orderFrozen[id]) {
                continue;
            }
            Order memory order = _orderbookMarketplaceStorage().orders[id];
            if (order.amounts.available > 0 && !_isOrderExpired(order.expiry)) {
                sellOrders[sellIndex] = order;
                ++sellIndex;
            }
        }
    }

    // slither-disable-end timestamp

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function getTWAP(address tokenAddress, uint256 tokenId, uint256 secondsAgo)
        external
        view
        returns (uint256 unitPrice)
    {
        TWAPState storage state = _orderbookMarketplaceStorage().twapStates[tokenAddress][tokenId];
        uint16 obsCount = state.observationCount;
        require(obsCount > 0, Errors.OrderbookMarketplace__NoObservations());
        // If secondsAgo is greater than the current block timestamp, set targetTime to 0
        // slither-disable-next-line timestamp
        uint32 targetTime = secondsAgo > block.timestamp ? 0 : uint32(block.timestamp - secondsAgo);

        // Oldest valid observation sits at physical index 1 when the buffer is not yet full
        // (observations are written starting at index 1, never index 0).
        // Once the buffer wraps, the oldest slot is (currentIndex + 1) % MAX.
        uint16 startIndex = obsCount < MAX_RECENT_OBSERVATIONS
            ? 1
            : uint16((uint256(state.currentIndex) + 1) % MAX_RECENT_OBSERVATIONS);

        uint16 foundIndex = _findClosestObservation(state, startIndex, obsCount, targetTime);

        Observation storage foundObs = state.observations[foundIndex];
        Observation storage latestObs = state.observations[state.currentIndex];

        // Project the accumulator from the latest stored snapshot to the current block
        uint256 currentCumulative =
            uint256(latestObs.cumulativePrice) + state.lastPrice * (block.timestamp - latestObs.timestamp);

        uint256 timeElapsed = block.timestamp - foundObs.timestamp;
        require(timeElapsed > 0, Errors.OrderbookMarketplace__InsufficientTWAPAge());

        unitPrice = (currentCumulative - foundObs.cumulativePrice) / timeElapsed;
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function getObservation(address tokenAddress, uint256 tokenId, uint16 index)
        external
        view
        returns (Observation memory observation)
    {
        return _orderbookMarketplaceStorage().twapStates[tokenAddress][tokenId].observations[index];
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function getObservationCount(address tokenAddress, uint256 tokenId) external view returns (uint16 count) {
        return _orderbookMarketplaceStorage().twapStates[tokenAddress][tokenId].observationCount;
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function getLastTradedPrice(address tokenAddress, uint256 tokenId) external view returns (uint256 price) {
        return _orderbookMarketplaceStorage().twapStates[tokenAddress][tokenId].lastPrice;
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function getTrade(uint256 tradeId) external view returns (Trade memory) {
        return _orderbookMarketplaceStorage().trades[tradeId];
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function getTradeIdsByOrderId(uint256 orderId) external view returns (uint256[] memory) {
        return _orderbookMarketplaceStorage().tradeIdsByOrderId[orderId];
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function getEscrowIdByOrderId(uint256 orderId) external view returns (uint256 escrowId) {
        return _orderbookMarketplaceStorage().escrowIdByOrderId[orderId];
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function isTraderAllowedForOrder(uint256 orderId, address trader) external view returns (bool) {
        return _isTraderAllowed(orderId, _orderbookMarketplaceStorage().orders[orderId].traderFilterMode, trader);
    }

    /**
     * @inheritdoc IOrderbookMarketplace
     */
    function activeSellMarkets() external view returns (Market[] memory) {
        return _orderbookMarketplaceStorage().activeSellMarkets;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new order and inserts it into the sorted order arrays
     * @param tokenAddress Address of the token contract
     * @param tokenId Token ID
     * @param totalAmount Total number of bonds in the order
     * @param minPrice Minimum price per bond unit
     * @param maxPrice Maximum price per bond unit
     * @param minMatchAmount Minimum amount for a single match (0 = no minimum)
     * @param traderFilterMode Trader filter mode (NONE, WHITELIST, or BLACKLIST)
     * @param side Order side (BUY or SELL)
     * @param expiry Optional order expiry timestamp (0 = does not expire)
     * @param effectiveTrader Address recorded as the order owner
     * @return orderId The unique identifier for the created order
     */
    // slither-disable-start timestamp
    function _createOrder(
        address tokenAddress,
        uint256 tokenId,
        uint256 totalAmount,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 minMatchAmount,
        TraderFilterMode traderFilterMode,
        OrderSide side,
        uint256 expiry,
        address effectiveTrader
    ) internal returns (uint256 orderId) {
        orderId = ++_orderbookMarketplaceStorage().ordersCount;
        _orderbookMarketplaceStorage().orders[orderId] = Order({
            tokenAddress: tokenAddress,
            tokenId: tokenId,
            trader: effectiveTrader,
            minPrice: minPrice,
            maxPrice: maxPrice,
            minMatchAmount: minMatchAmount,
            traderFilterMode: traderFilterMode,
            side: side,
            timestamp: block.timestamp,
            expiry: expiry,
            amounts: OrderAmounts({total: totalAmount, available: totalAmount, inDeals: 0, sold: 0})
        });

        if (side == OrderSide.BUY) {
            // BUY orders sorted ASC by maxPrice: highest maxPrice at highest index
            // Same-price orders: newer orders at lower index (FIFO when iterating from end)
            uint256[] storage buyOrders = _orderbookMarketplaceStorage().buyOrderIdsByTokenId[tokenAddress][tokenId];
            buyOrders.push(orderId);

            uint256 i = buyOrders.length - 1;
            // solhint-disable-next-line gas-strict-inequalities
            while (i > 0 && _orderbookMarketplaceStorage().orders[buyOrders[i - 1]].maxPrice >= maxPrice) {
                buyOrders[i] = buyOrders[i - 1];
                --i;
            }
            buyOrders[i] = orderId;
        } else {
            // SELL orders sorted DESC by minPrice: lowest minPrice at highest index
            // Same-price orders: newer orders at lower index (FIFO when iterating from end)
            uint256[] storage sellOrders = _orderbookMarketplaceStorage().sellOrderIdsByTokenId[tokenAddress][tokenId];
            _addActiveSellMarket(tokenAddress, tokenId);
            sellOrders.push(orderId);

            uint256 i = sellOrders.length - 1;
            // solhint-disable-next-line gas-strict-inequalities
            while (i > 0 && _orderbookMarketplaceStorage().orders[sellOrders[i - 1]].minPrice <= minPrice) {
                sellOrders[i] = sellOrders[i - 1];
                --i;
            }
            sellOrders[i] = orderId;
        }
    }

    // slither-disable-end timestamp

    /**
     * @notice Creates a new order from external place-order calldata
     * @param input Order input parameters
     * @param effectiveTrader Address recorded as the order owner
     * @return orderId The unique identifier for the created order
     */
    function _createOrderFromInput(OrderInput calldata input, address effectiveTrader)
        internal
        returns (uint256 orderId)
    {
        return _createOrder(
            input.tokenAddress,
            input.tokenId,
            input.totalAmount,
            input.minPrice,
            input.maxPrice,
            input.minMatchAmount,
            input.traderFilterMode,
            input.side,
            input.expiry,
            effectiveTrader
        );
    }

    /**
     * @notice Adds a (tokenAddress, tokenId) market to the active SELL set if not already tracked
     * @param tokenAddress Token contract address
     * @param tokenId Token id
     * @dev Enforces MAX_ACTIVE_SELL_MARKETS cap to bound placeBatchOrder iteration cost
     */
    function _addActiveSellMarket(address tokenAddress, uint256 tokenId) internal {
        if (_orderbookMarketplaceStorage().activeSellMarketIndex[tokenAddress][tokenId] != 0) {
            return;
        }
        require(
            _orderbookMarketplaceStorage().activeSellMarkets.length < MAX_ACTIVE_SELL_MARKETS,
            Errors.OrderbookMarketplace__TooManyActiveSellMarkets()
        );
        _orderbookMarketplaceStorage().activeSellMarkets.push(Market({tokenAddress: tokenAddress, tokenId: tokenId}));
        _orderbookMarketplaceStorage().activeSellMarketIndex[tokenAddress][tokenId] =
        _orderbookMarketplaceStorage().activeSellMarkets.length;
    }

    /**
     * @notice Removes a (tokenAddress, tokenId) market from the active SELL set via swap-pop
     * @param tokenAddress Token contract address
     * @param tokenId Token id
     * @dev Caller must ensure the market is tracked (invariant: only called after last SELL is removed)
     */
    function _removeActiveSellMarket(address tokenAddress, uint256 tokenId) internal {
        uint256 indexPlusOne = _orderbookMarketplaceStorage().activeSellMarketIndex[tokenAddress][tokenId];
        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = _orderbookMarketplaceStorage().activeSellMarkets.length - 1;
        if (index != lastIndex) {
            Market memory last = _orderbookMarketplaceStorage().activeSellMarkets[lastIndex];
            _orderbookMarketplaceStorage().activeSellMarkets[index] = last;
            _orderbookMarketplaceStorage().activeSellMarketIndex[last.tokenAddress][last.tokenId] = indexPlusOne;
        }
        _orderbookMarketplaceStorage().activeSellMarkets.pop();
        _orderbookMarketplaceStorage().activeSellMarketIndex[tokenAddress][tokenId] = 0;
    }

    /**
     * @notice Creates an escrow deposit for a SELL order
     * @param orderId Order ID to use as the escrow key
     * @param totalAmount Total amount of tokens to deposit into escrow
     * @param tokenAddress Address of the token contract
     * @param tokenId Token ID
     * @param effectiveTrader Address of the token depositor (the effective order owner)
     */
    function _createEscrow(
        uint256 orderId,
        uint256 totalAmount,
        address tokenAddress,
        uint256 tokenId,
        address effectiveTrader
    ) internal {
        uint256 expectedEscrowId = IEscrowManager(_orderbookMarketplaceStorage().escrowManager).previewNextEscrowId();
        _orderbookMarketplaceStorage().escrowIdByOrderId[orderId] = expectedEscrowId;
        // slither-disable-next-line reentrancy-benign
        uint256 actualEscrowId = IEscrowManager(_orderbookMarketplaceStorage().escrowManager)
            .createEscrow(totalAmount, effectiveTrader, tokenAddress, tokenId);
        require(
            actualEscrowId == expectedEscrowId,
            Errors.OrderbookMarketplace__EscrowIdMismatch(actualEscrowId, expectedEscrowId)
        );
    }

    /**
     * @notice Handles escrow creation and matching for a newly placed order
     * @param input Order input parameters
     * @param orderId Newly created order ID
     * @param effectiveTrader Effective trader identity of the incoming order
     * @return unfilledAmount Remaining unfilled amount after matching
     */
    function _processOrderPlacement(OrderInput calldata input, uint256 orderId, address effectiveTrader)
        internal
        returns (uint256 unfilledAmount)
    {
        if (input.side == OrderSide.BUY) {
            return _matchBuyOrder(
                input.tokenAddress,
                input.tokenId,
                orderId,
                input.totalAmount,
                input.minPrice,
                input.maxPrice,
                input.minMatchAmount,
                input.traderFilterMode,
                effectiveTrader
            );
        }

        // Seller places bond token into escrow. Buyer will claim it after payment
        // Bonds stay in escrow until PAYMENT_HANDLER confirms payment via markTradePaid()
        // slither-disable-next-line reentrancy-no-eth,reentrancy-events
        _createEscrow(orderId, input.totalAmount, input.tokenAddress, input.tokenId, effectiveTrader);

        return _matchSellOrder(
            input.tokenAddress,
            input.tokenId,
            orderId,
            input.totalAmount,
            input.minPrice,
            input.maxPrice,
            input.minMatchAmount,
            input.traderFilterMode,
            effectiveTrader
        );
    }

    /**
     * @notice Updates the stored order amounts after matching completes
     * @param orderId Newly created order ID
     * @param totalAmount Original order amount
     * @param unfilledAmount Remaining unfilled amount after matching
     */
    function _updatePlacedOrderAmounts(uint256 orderId, uint256 totalAmount, uint256 unfilledAmount) internal {
        if (unfilledAmount == totalAmount) {
            return;
        }

        Order storage order = _orderbookMarketplaceStorage().orders[orderId];
        order.amounts.available = unfilledAmount;
        order.amounts.inDeals = totalAmount - unfilledAmount;
    }

    /**
     * @notice Creates a trade record and emits TradeExecuted event
     * @param side Which side the new order is (BUY or SELL)
     * @param newOrderId ID of the order being placed
     * @param matchedOrderId ID of the existing order being matched
     * @param matchedOrder Storage reference to the matched order
     * @param matchAmount Amount being traded
     * @param newOrderTrader Address of the trader placing the new order
     */
    // slither-disable-start timestamp
    function _createTrade(
        OrderSide side,
        uint256 newOrderId,
        uint256 matchedOrderId,
        Order storage matchedOrder,
        uint256 matchAmount,
        address newOrderTrader
    ) internal {
        uint256 buyOrderId = side == OrderSide.BUY ? newOrderId : matchedOrderId;
        uint256 sellOrderId = side == OrderSide.BUY ? matchedOrderId : newOrderId;
        address buyer = side == OrderSide.BUY ? newOrderTrader : matchedOrder.trader;
        address seller = side == OrderSide.BUY ? matchedOrder.trader : newOrderTrader;
        uint256 tradePrice;
        if (side == OrderSide.BUY) {
            // BUY taker matches SELL maker → taker-favorable: lower bound of overlap = max(sellMin, buyMin)
            uint256 buyerMinPrice = _orderbookMarketplaceStorage().orders[newOrderId].minPrice;
            tradePrice = matchedOrder.minPrice > buyerMinPrice ? matchedOrder.minPrice : buyerMinPrice;
        } else {
            // SELL taker matches BUY maker → trade at buyer's maxPrice, capped at seller's maxPrice
            // so the execution price stays within both parties' stated ranges
            uint256 sellerMaxPrice = _orderbookMarketplaceStorage().orders[newOrderId].maxPrice;
            tradePrice = matchedOrder.maxPrice < sellerMaxPrice ? matchedOrder.maxPrice : sellerMaxPrice;
        }

        uint256 tradeId = ++_orderbookMarketplaceStorage().tradesCount;
        // slither-disable-next-line timestamp
        uint256 paymentDeadline = block.timestamp + _orderbookMarketplaceStorage().paymentExpiryThreshold;
        _orderbookMarketplaceStorage().trades[tradeId] = Trade({
            tradeId: tradeId,
            buyOrderId: buyOrderId,
            sellOrderId: sellOrderId,
            tokenAddress: matchedOrder.tokenAddress,
            tokenId: matchedOrder.tokenId,
            buyer: buyer,
            seller: seller,
            amount: matchAmount,
            unitPrice: tradePrice,
            status: TradeStatus.PENDING,
            timestamp: block.timestamp,
            paymentDeadline: paymentDeadline,
            disputeBuffer: paymentDeadline + _orderbookMarketplaceStorage().disputeBufferPeriod
        });

        _orderbookMarketplaceStorage().tradeIdsByOrderId[buyOrderId].push(tradeId);
        _orderbookMarketplaceStorage().tradeIdsByOrderId[sellOrderId].push(tradeId);

        _recordObservation(
            _orderbookMarketplaceStorage().twapStates[matchedOrder.tokenAddress][matchedOrder.tokenId],
            matchedOrder.tokenAddress,
            matchedOrder.tokenId,
            tradePrice,
            block.timestamp
        );

        emit TradeExecuted(
            buyOrderId,
            sellOrderId,
            matchedOrder.tokenId,
            matchedOrder.tokenAddress,
            buyer,
            seller,
            matchAmount,
            tradePrice
        );
    }

    // slither-disable-end timestamp

    /**
     * @notice Match an incoming BUY order against existing SELL orders for a single market
     * @param tokenAddress Address of the token contract
     * @param tokenId Token ID
     * @param orderId ID of the new BUY order
     * @param unfilledAmount Amount still unfilled on the new order
     * @param buyMinPrice Minimum price the buyer is willing to pay
     * @param buyMaxPrice Maximum price the buyer is willing to pay
     * @param newOrderMinMatchAmount Minimum match amount for the new order (0 = no minimum)
     * @param newOrderTraderFilterMode Whitelist/Blacklist mode for the new order
     * @param effectiveTrader Effective trader identity of the incoming order (may differ from msg.sender for delegated calls)
     * @return newUnfilledAmount Remaining unfilled amount after matching
     * @dev Reused by placeOrder (single market) and placeBatchOrder (called per candidate market)
     */
    function _matchBuyOrder(
        address tokenAddress,
        uint256 tokenId,
        uint256 orderId,
        uint256 unfilledAmount,
        uint256 buyMinPrice,
        uint256 buyMaxPrice,
        uint256 newOrderMinMatchAmount,
        TraderFilterMode newOrderTraderFilterMode,
        address effectiveTrader
    ) internal returns (uint256 newUnfilledAmount) {
        newUnfilledAmount = unfilledAmount;
        uint256[] storage sellOrders = _orderbookMarketplaceStorage().sellOrderIdsByTokenId[tokenAddress][tokenId];

        // Loop from lowest minPrice (most likely to match) to highest
        for (uint256 i = sellOrders.length; i > 0;) {
            if (newUnfilledAmount == 0) {
                break;
            }

            unchecked {
                --i;
            }
            uint256 sellOrderId = sellOrders[i];
            Order storage sellOrder = _orderbookMarketplaceStorage().orders[sellOrderId];

            if (buyMaxPrice < sellOrder.minPrice) {
                // no more sell orders to potentially match against
                break;
            }
            if (sellOrder.maxPrice < buyMinPrice) {
                // sell range ends below buyer's minimum — ranges don't overlap, skip
                continue;
            }
            if (_isOrderExpired(sellOrder.expiry)) {
                continue;
            }
            if (sellOrder.amounts.available == 0) {
                // this sell order has 0 available amount (but > 0 to be settled, so it's not deleted yet)
                // following sell orders might still have available amounts
                continue;
            }
            if (_orderbookMarketplaceStorage().orderFrozen[sellOrderId]) {
                // skip frozen orders
                continue;
            }
            if (effectiveTrader == sellOrder.trader) {
                // cannot match their own orders
                continue;
            }
            if (!_isTraderAllowed(orderId, newOrderTraderFilterMode, sellOrder.trader)) {
                continue;
            }
            if (!_isTraderAllowed(sellOrderId, sellOrder.traderFilterMode, effectiveTrader)) {
                continue;
            }

            uint256 matchAmount =
                newUnfilledAmount < sellOrder.amounts.available ? newUnfilledAmount : sellOrder.amounts.available;

            // skip if match amount is below either side's minimum
            if (newOrderMinMatchAmount > 0 && matchAmount < newOrderMinMatchAmount) {
                continue;
            }
            if (sellOrder.minMatchAmount > 0 && matchAmount < sellOrder.minMatchAmount) {
                continue;
            }

            newUnfilledAmount -= matchAmount;
            sellOrder.amounts.available -= matchAmount;
            sellOrder.amounts.inDeals += matchAmount;

            _createTrade(OrderSide.BUY, orderId, sellOrderId, sellOrder, matchAmount, effectiveTrader);
        }
    }

    /**
     * @notice Match a batch BUY across pre-sorted markets, filling the globally cheapest top-of-book each step
     * @param sorted Markets returned by _buildSortedMarketList (each has at least one ask <= buyMaxPrice)
     * @param orderId Synthetic batch BUY order ID
     * @param input Batch order input
     * @return remaining Buyer-side amount left unfilled
     */
    function _matchBatchBuyOrder(Market[] memory sorted, uint256 orderId, BatchOrderInput calldata input)
        internal
        returns (uint256 remaining)
    {
        remaining = input.totalAmount;
        uint256 mLen = sorted.length;

        for (uint256 iter; iter < input.totalAmount && remaining > 0; ++iter) {
            uint256 bestIdx = type(uint256).max;
            uint256 bestPrice = type(uint256).max;
            for (uint256 i; i < mLen; ++i) {
                uint256 p = _peekEligibleAskPrice(
                    sorted[i].tokenAddress, sorted[i].tokenId, orderId, remaining, input, msg.sender
                );
                if (p < bestPrice) {
                    bestPrice = p;
                    bestIdx = i;
                }
            }
            if (bestIdx == type(uint256).max) break;

            remaining = _matchBuyOrder(
                sorted[bestIdx].tokenAddress,
                sorted[bestIdx].tokenId,
                orderId,
                remaining,
                input.minPrice,
                bestPrice,
                input.minMatchAmount,
                input.traderFilterMode,
                msg.sender
            );
        }
    }

    /**
     * @notice Find the cheapest sell order in a market that would be matchable by `_matchBuyOrder`
     * @dev Mirrors the eligibility filters in `_matchBuyOrder` so the batch picker never selects a
     *      market whose top-of-book is blocked (frozen, expired, self-trade, trader-filtered, below
     *      either side's min-match) when a deeper, eligible ask exists. Walks asks cheapest-first and
     *      returns at the first eligible one; returns type(uint256).max if none qualify under the cap.
     * @param tokenAddress Address of the token contract
     * @param tokenId Token ID
     * @param buyOrderId ID of the batch BUY order
     * @param remaining Amount still unfilled on the batch order
     * @param input Batch order constraints
     * @param effectiveTrader Trader whose filters and self-trade checks apply
     * @return cheapest Min price of the cheapest eligible sell order, or type(uint256).max
     */
    function _peekEligibleAskPrice(
        address tokenAddress,
        uint256 tokenId,
        uint256 buyOrderId,
        uint256 remaining,
        BatchOrderInput calldata input,
        address effectiveTrader
    ) internal view returns (uint256 cheapest) {
        cheapest = type(uint256).max;
        uint256[] storage so = _orderbookMarketplaceStorage().sellOrderIdsByTokenId[tokenAddress][tokenId];
        for (uint256 j = so.length; j > 0;) {
            unchecked {
                --j;
            }
            uint256 sellOrderId = so[j];
            Order storage sellOrder = _orderbookMarketplaceStorage().orders[sellOrderId];

            if (input.maxPrice < sellOrder.minPrice) return cheapest;
            if (sellOrder.maxPrice < input.minPrice) continue;
            if (_isOrderExpired(sellOrder.expiry)) continue;
            if (sellOrder.amounts.available == 0) continue;
            if (_orderbookMarketplaceStorage().orderFrozen[sellOrderId]) continue;
            if (effectiveTrader == sellOrder.trader) continue;
            if (!_isTraderAllowed(buyOrderId, input.traderFilterMode, sellOrder.trader)) continue;
            if (!_isTraderAllowed(sellOrderId, sellOrder.traderFilterMode, effectiveTrader)) continue;

            uint256 matchAmount = remaining < sellOrder.amounts.available ? remaining : sellOrder.amounts.available;
            if (input.minMatchAmount > 0 && matchAmount < input.minMatchAmount) continue;
            if (sellOrder.minMatchAmount > 0 && matchAmount < sellOrder.minMatchAmount) continue;

            return sellOrder.minPrice;
        }
    }

    /**
     * @notice Match an incoming SELL order against existing BUY orders
     * @param tokenAddress Address of the token contract
     * @param tokenId Token ID
     * @param orderId ID of the new SELL order
     * @param unfilledAmount Amount still unfilled on the new order
     * @param sellMinPrice Minimum price the seller is willing to accept
     * @param sellMaxPrice Maximum price the seller is willing to accept
     * @param newOrderMinMatchAmount Minimum match amount for the new order (0 = no minimum)
     * @param newOrderTraderFilterMode Whitelist/Blacklist mode for the new order
     * @param effectiveTrader Effective trader identity of the incoming order (may differ from msg.sender for delegated calls)
     * @return newUnfilledAmount Remaining unfilled amount after matching
     */
    function _matchSellOrder(
        address tokenAddress,
        uint256 tokenId,
        uint256 orderId,
        uint256 unfilledAmount,
        uint256 sellMinPrice,
        uint256 sellMaxPrice,
        uint256 newOrderMinMatchAmount,
        TraderFilterMode newOrderTraderFilterMode,
        address effectiveTrader
    ) internal returns (uint256 newUnfilledAmount) {
        newUnfilledAmount = unfilledAmount;
        uint256[] storage buyOrders = _orderbookMarketplaceStorage().buyOrderIdsByTokenId[tokenAddress][tokenId];

        // Loop from highest maxPrice (most likely to match) to lowest
        for (uint256 i = buyOrders.length; i > 0;) {
            if (newUnfilledAmount == 0) {
                break;
            }

            unchecked {
                --i;
            }
            uint256 buyOrderId = buyOrders[i];
            Order storage buyOrder = _orderbookMarketplaceStorage().orders[buyOrderId];

            if (buyOrder.maxPrice < sellMinPrice) {
                // no more buy orders to potentially match against
                break;
            }
            if (buyOrder.minPrice > sellMaxPrice) {
                // buy range starts above seller's maximum — ranges don't overlap, skip
                continue;
            }
            if (_isOrderExpired(buyOrder.expiry)) {
                continue;
            }
            if (buyOrder.amounts.available == 0) {
                // this buy order has 0 available amount (but > 0 to be settled, so it's not deleted yet)
                // following buy orders might still have available amounts
                continue;
            }
            if (_orderbookMarketplaceStorage().orderFrozen[buyOrderId]) {
                // skip frozen orders
                continue;
            }
            if (effectiveTrader == buyOrder.trader) {
                // cannot match their own orders
                continue;
            }
            if (!_isTraderAllowed(orderId, newOrderTraderFilterMode, buyOrder.trader)) {
                continue;
            }
            if (!_isTraderAllowed(buyOrderId, buyOrder.traderFilterMode, effectiveTrader)) {
                continue;
            }

            uint256 matchAmount =
                newUnfilledAmount < buyOrder.amounts.available ? newUnfilledAmount : buyOrder.amounts.available;

            // skip if match amount is below either side's minimum
            if (newOrderMinMatchAmount > 0 && matchAmount < newOrderMinMatchAmount) {
                continue;
            }
            if (buyOrder.minMatchAmount > 0 && matchAmount < buyOrder.minMatchAmount) {
                continue;
            }

            newUnfilledAmount -= matchAmount;
            buyOrder.amounts.available -= matchAmount;
            buyOrder.amounts.inDeals += matchAmount;

            _createTrade(OrderSide.SELL, orderId, buyOrderId, buyOrder, matchAmount, effectiveTrader);
        }
    }

    /**
     * @notice Internal helper to delete an order from all storage structures
     * @param orderId Order ID to delete
     * @param order Storage reference to the order (must be loaded before calling)
     * @dev Assumes all safety checks are done by caller
     * @dev Removes from sorted arrays and deletes from _orders mapping
     */
    function _deleteOrder(uint256 orderId, Order storage order) internal {
        address tokenAddress = order.tokenAddress;
        uint256 tokenId = order.tokenId;
        OrderSide side = order.side;
        address trader = order.trader;

        if (side == OrderSide.BUY) {
            _removeFromArray(_orderbookMarketplaceStorage().buyOrderIdsByTokenId[tokenAddress][tokenId], orderId);
        } else {
            uint256[] storage sellOrders = _orderbookMarketplaceStorage().sellOrderIdsByTokenId[tokenAddress][tokenId];
            _removeFromArray(sellOrders, orderId);
            if (sellOrders.length == 0) {
                _removeActiveSellMarket(tokenAddress, tokenId);
            }
        }

        delete _orderbookMarketplaceStorage().orders[orderId];
        // Clear freeze state so the deleted order is not reported as frozen by downstream
        // checks (e.g., settleTrade). Once deleted, the order cannot be unfrozen via the
        // external API because setOrderFrozen requires the order to exist.
        delete _orderbookMarketplaceStorage().orderFrozen[orderId];

        emit OrderDeleted(orderId, trader);
    }

    /**
     * @notice Remove an element from an array by shifting left to preserve order
     * @param array Storage array to modify
     * @param value Value to remove
     * @dev Uses left-shift algorithm to maintain sorted order
     * @dev O(n) complexity but preserves price-time priority
     */
    function _removeFromArray(uint256[] storage array, uint256 value) internal {
        uint256 length = array.length;
        for (uint256 i = 0; i < length; ++i) {
            if (array[i] == value) {
                // Shift all elements left to preserve order
                for (uint256 j = i; j < length - 1; ++j) {
                    array[j] = array[j + 1];
                }
                array.pop();
                break;
            }
        }
    }

    /**
     * @notice Records a new TWAP observation in the circular buffer for a given token
     * @dev Called by _createTrade on every match.
     *      Cumulative price formula (Uniswap V3-style):
     *        newCumulative = prev.cumulativePrice + lastPrice * (currentTime - prev.timestamp)
     *      lastPrice is updated to `price` AFTER the observation is written, so the new price
     *      only starts contributing to the accumulator from this block forward.
     * @param state        Storage reference to the token's TWAPState
     * @param tokenAddress Token contract address (forwarded to the emitted event)
     * @param tokenId      Token ID (forwarded to the emitted event)
     * @param price        The trade unit price that was just executed
     * @param currentTime  block.timestamp at the time of the trade
     */
    // slither-disable-start timestamp
    function _recordObservation(
        TWAPState storage state,
        address tokenAddress,
        uint256 tokenId,
        uint256 price,
        uint256 currentTime
    ) internal {
        Observation storage prev = state.observations[state.currentIndex];

        // slither-disable-next-line timestamp
        uint256 timeElapsed = currentTime - prev.timestamp;
        // Accumulate: lastPrice held since prev.timestamp up to now.
        uint256 contribution = state.lastPrice * timeElapsed;
        uint256 accumulated = uint256(prev.cumulativePrice) + contribution;
        require(!(accumulated > type(uint224).max), Errors.OrderbookMarketplace__TWAPAccumulatorOverflow());
        uint224 newCumulative = uint224(accumulated);

        uint16 nextIndex = uint16((uint256(state.currentIndex) + 1) % MAX_RECENT_OBSERVATIONS);
        // @todo warning[unsafe-typecast]: typecasts that can truncate values should be checked
        state.observations[nextIndex] = Observation({timestamp: uint32(currentTime), cumulativePrice: newCumulative});
        state.currentIndex = nextIndex;

        if (state.observationCount < MAX_RECENT_OBSERVATIONS) {
            ++state.observationCount;
        }

        state.lastPrice = price;

        emit TWAPObservationRecorded(tokenAddress, tokenId, uint32(currentTime), newCumulative, price);
    }
    // slither-disable-end timestamp

    function _setAssetManager(address assetManager_) internal {
        _orderbookMarketplaceStorage().assetManager = assetManager_;

        emit AssetManagerSet(assetManager_);
    }

    function _setEntityRegistry(address entityRegistry_) internal {
        _orderbookMarketplaceStorage().entityRegistry = entityRegistry_;

        emit EntityRegistrySet(entityRegistry_);
    }

    /**
     * @notice Sets the escrow manager address internally
     * @param escrowManager_ Address of the escrow manager
     */
    function _setEscrowManager(address escrowManager_) internal {
        _orderbookMarketplaceStorage().escrowManager = escrowManager_;

        emit EscrowManagerSet(escrowManager_);
    }

    /**
     * @notice Sets the payment expiry threshold internally
     * @param paymentExpiryThreshold_ Payment expiry threshold in seconds
     * @dev Reverts if paymentExpiryThreshold_ is below MIN_PAYMENT_EXPIRY_THRESHOLD
     * @dev Reverts if paymentExpiryThreshold_ exceeds MAX_PAYMENT_EXPIRY_THRESHOLD
     */
    function _setPaymentExpiryThreshold(uint256 paymentExpiryThreshold_) internal {
        require(
            !(paymentExpiryThreshold_ < MIN_PAYMENT_EXPIRY_THRESHOLD),
            Errors.OrderbookMarketplace__PaymentExpiryThresholdTooLow(paymentExpiryThreshold_)
        );
        require(
            !(paymentExpiryThreshold_ > MAX_PAYMENT_EXPIRY_THRESHOLD),
            Errors.OrderbookMarketplace__PaymentExpiryThresholdTooHigh(paymentExpiryThreshold_)
        );
        _orderbookMarketplaceStorage().paymentExpiryThreshold = paymentExpiryThreshold_;

        emit PaymentExpiryThresholdSet(paymentExpiryThreshold_);
    }

    /**
     * @notice Sets the minimum order expiry threshold internally
     * @param minExpiryThreshold_ Minimum required order expiry duration in seconds
     * @dev Reverts if minExpiryThreshold_ is below MIN_ORDER_EXPIRY_THRESHOLD
     */
    function _setMinExpiryThreshold(uint256 minExpiryThreshold_) internal {
        require(
            !(minExpiryThreshold_ < MIN_ORDER_EXPIRY_THRESHOLD),
            Errors.OrderbookMarketplace__MinExpiryThresholdTooLow(minExpiryThreshold_)
        );
        _orderbookMarketplaceStorage().minExpiryThreshold = minExpiryThreshold_;

        emit MinExpiryThresholdSet(minExpiryThreshold_);
    }

    /**
     * @notice Sets the dispute buffer period internally
     * @param disputeBufferPeriod_ Dispute buffer period in seconds
     * @dev Reverts if disputeBufferPeriod_ is below MIN_DISPUTE_BUFFER_PERIOD
     * @dev Reverts if disputeBufferPeriod_ exceeds MAX_DISPUTE_BUFFER_PERIOD
     */
    function _setDisputeBufferPeriod(uint256 disputeBufferPeriod_) internal {
        require(
            !(disputeBufferPeriod_ < MIN_DISPUTE_BUFFER_PERIOD),
            Errors.OrderbookMarketplace__DisputeBufferPeriodTooLow(disputeBufferPeriod_)
        );
        require(
            !(disputeBufferPeriod_ > MAX_DISPUTE_BUFFER_PERIOD),
            Errors.OrderbookMarketplace__DisputeBufferPeriodTooHigh(disputeBufferPeriod_)
        );
        _orderbookMarketplaceStorage().disputeBufferPeriod = disputeBufferPeriod_;

        emit DisputeBufferPeriodSet(disputeBufferPeriod_);
    }

    /**
     * @notice Internal setter for the market filter resolver
     * @param marketFilter_ Market filter address
     */
    function _setMarketFilter(address marketFilter_) internal {
        require(marketFilter_ != address(0), Errors.ZeroAddress());
        _orderbookMarketplaceStorage().marketFilter = marketFilter_;
        emit MarketFilterSet(marketFilter_);
    }

    /**
     * @notice Stores trader filter addresses for an order
     * @param orderId Order ID
     * @param traderFilterAddresses Trader filter addresses
     */
    function _storeTraderFilter(uint256 orderId, address[] calldata traderFilterAddresses) internal {
        uint256 length = traderFilterAddresses.length;
        for (uint256 i; i < length;) {
            if (traderFilterAddresses[i] == address(0)) {
                revert Errors.ZeroAddress();
            }
            _orderbookMarketplaceStorage().orderTraderFilter[orderId][traderFilterAddresses[i]] = true;
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Removes an order's available amount from the orderbook and escrow if needed
     * @param orderId Order ID
     * @param order Storage reference to the order
     */
    function _cleanupOrder(uint256 orderId, Order storage order) internal {
        uint256 availableAmount = order.amounts.available;
        require(availableAmount != 0, Errors.OrderbookMarketplace__NoAvailableAmount(orderId));

        order.amounts.available = 0;
        OrderSide side = order.side;
        address trader = order.trader;

        if (order.amounts.inDeals == 0) {
            _deleteOrder(orderId, order);
        }

        if (side == OrderSide.SELL) {
            // slither-disable-next-line reentrancy-events
            IEscrowManager(_orderbookMarketplaceStorage().escrowManager)
                .withdraw(_orderbookMarketplaceStorage().escrowIdByOrderId[orderId], availableAmount);
        }

        emit OrderCancelled(orderId, trader, availableAmount);
    }

    /**
     * @notice Binary-search the circular buffer for the rightmost observation with timestamp <= targetTime
     * @dev Observations are in chronological order starting at `startIndex` (wrapping around MAX).
     *      Returns the physical buffer index of the best match.
     *      Fallback: if all observations are newer than targetTime, returns `startIndex` (oldest).
     * @param state      Storage reference to the token's TWAPState
     * @param startIndex Physical index of the oldest valid observation
     * @param obsCount   Number of valid observations currently in the buffer
     * @param targetTime Target timestamp (block.timestamp - secondsAgo)
     * @return foundIndex Physical buffer index of the chosen observation
     */
    function _findClosestObservation(TWAPState storage state, uint16 startIndex, uint16 obsCount, uint32 targetTime)
        internal
        view
        returns (uint16 foundIndex)
    {
        // Default to oldest observation — used when all stored timestamps are newer than targetTime
        foundIndex = startIndex;

        uint16 left = 0;
        uint16 right = obsCount - 1;

        // Find the rightmost (latest) observation whose timestamp <= targetTime
        while (!(left > right)) {
            uint16 mid = left + (right - left) / 2;
            uint16 physIndex = uint16((uint256(startIndex) + mid) % MAX_RECENT_OBSERVATIONS);

            // slither-disable-next-line timestamp
            if (!(state.observations[physIndex].timestamp > targetTime)) {
                foundIndex = physIndex;
                left = mid + 1;
            } else {
                // Guard against uint16 underflow when mid == 0
                if (mid == 0) break;
                right = mid - 1;
            }
        }
    }

    /**
     * @notice Validates that `delegate` is authorized to act on behalf of `trader`
     * @param trader The account that must have granted the delegation
     * @param delegate The account claiming to act on behalf of `trader`
     */
    function _validateDelegate(address trader, address delegate) internal view {
        require(
            _orderbookMarketplaceStorage().delegations[trader][delegate],
            Errors.OrderbookMarketplace__DelegateNotAuthorized(delegate, trader)
        );
    }

    /**
     * @notice Resolves the effective trader for a place-order call
     * @dev Validates msg.sender in both paths; for delegated calls also validates onBehalfOf and the delegation grant
     * @param onBehalfOf Address to act on behalf of; zero means the caller is acting directly
     * @return effectiveTrader The resolved trader address
     */
    function _resolveEffectiveTrader(address onBehalfOf) internal view returns (address effectiveTrader) {
        _validateMsgSender(msg.sender);
        if (onBehalfOf == address(0)) {
            return msg.sender;
        }
        _validateMsgSender(onBehalfOf);
        _validateDelegate(onBehalfOf, msg.sender);
        return onBehalfOf;
    }

    /**
     * @notice Validate message sender
     * @param sender address of the sender
     * @dev If entity registry is set, only enabled company wallets are allowed
     * @dev Reverts if the sender is not an enabled company wallet when registry is set
     * @dev Regular EOAs are rejected when company wallet registry is configured
     */
    function _validateMsgSender(address sender) internal view {
        address er = _orderbookMarketplaceStorage().entityRegistry;
        if (er != address(0)) {
            require(IEntityRegistry(er).isAccountEnabled(sender), Errors.OrderbookMarketplace__NotAuthorized(sender));
        }
    }

    /**
     * @notice Validates trade status matches expected status
     * @param trade Storage reference to the trade
     * @param expectedStatus Expected trade status
     */
    // slither-disable-start timestamp
    function _validateTradeStatus(Trade storage trade, TradeStatus expectedStatus) internal view {
        require(trade.tradeId != 0, Errors.OrderbookMarketplace__TradeNotFound(0));
        require(trade.status == expectedStatus, Errors.OrderbookMarketplace__InvalidTradeStatus(uint8(trade.status)));
    }

    /**
     * @notice Checks if a trader is allowed to match against an order based on its filter mode
     * @param orderId Order ID to check filter for
     * @param mode Trader filter mode of the order
     * @param trader Address to check
     * @return True if the trader is allowed
     */
    function _isTraderAllowed(uint256 orderId, TraderFilterMode mode, address trader) internal view returns (bool) {
        // slither-disable-next-line incorrect-equality
        if (mode == TraderFilterMode.NONE) {
            return true;
        }
        // slither-disable-next-line incorrect-equality
        if (mode == TraderFilterMode.WHITELIST) {
            return _orderbookMarketplaceStorage().orderTraderFilter[orderId][trader];
        }
        return !_orderbookMarketplaceStorage().orderTraderFilter[orderId][trader];
    }
    // slither-disable-end timestamp

    function _validateAsset(address tokenAddress, uint256 tokenId, uint256 totalAmount) internal view {
        address am = _orderbookMarketplaceStorage().assetManager;
        require(am != address(0), Errors.OrderbookMarketplace__AssetManagerNotSet());
        // Orderbook only needs the validation side effect; EscrowManager derives stored bond metadata independently.
        // slither-disable-next-line unused-return
        IAssetManager(am).validateAsset(tokenAddress, tokenId, totalAmount);
    }

    // Order expiry and batch market filtering intentionally rely on protocol-defined timestamp windows.
    // slither-disable-start timestamp
    /**
     * @notice Validates that a non-zero order expiry satisfies the configured minimum threshold
     * @param expiry Optional order expiry timestamp (0 = does not expire)
     */
    function _validateOrderExpiryThreshold(uint256 expiry) internal view {
        if (expiry == 0) {
            return;
        }

        require(
            !(expiry < block.timestamp + _orderbookMarketplaceStorage().minExpiryThreshold),
            Errors.OrderbookMarketplace__InvalidExpiry(expiry, block.timestamp)
        );
    }

    /**
     * @notice Checks whether an order expiry has strictly passed
     * @param expiry Optional order expiry timestamp (0 = does not expire)
     * @return True if the order has expired
     */
    function _isOrderExpired(uint256 expiry) internal view returns (bool) {
        return expiry != 0 && block.timestamp > expiry;
    }

    /**
     * @notice Build an ordered list of SELL markets that pass the configured filter, sorted by best ask ASC
     * @param filterData Opaque filter payload forwarded to the configured IMarketFilter
     * @param buyMaxPrice Upper bound on execution price
     * @return sorted Markets eligible for matching, sorted cheapest-first
     * @dev Filter evaluation is delegated to IMarketFilter — non-matching tokens (including non-bond tokens)
     *      are transparently skipped.
     */
    function _buildSortedMarketList(bytes calldata filterData, uint256 buyMaxPrice)
        internal
        view
        returns (Market[] memory sorted)
    {
        uint256 totalCount = _orderbookMarketplaceStorage().activeSellMarkets.length;
        Market[] memory tmpMarkets = new Market[](totalCount);
        uint256[] memory tmpPrices = new uint256[](totalCount);
        uint256 candidateCount;

        for (uint256 i; i < totalCount;) {
            Market memory m = _orderbookMarketplaceStorage().activeSellMarkets[i];
            (bool pass, uint256 peekPrice) = _evaluateMarketForBatch(m, filterData, buyMaxPrice);
            if (pass) {
                uint256 j = candidateCount;
                while (j > 0 && tmpPrices[j - 1] > peekPrice) {
                    tmpMarkets[j] = tmpMarkets[j - 1];
                    tmpPrices[j] = tmpPrices[j - 1];
                    unchecked {
                        --j;
                    }
                }
                tmpMarkets[j] = m;
                tmpPrices[j] = peekPrice;
                unchecked {
                    ++candidateCount;
                }
            }
            unchecked {
                ++i;
            }
        }

        sorted = new Market[](candidateCount);
        for (uint256 k; k < candidateCount;) {
            sorted[k] = tmpMarkets[k];
            unchecked {
                ++k;
            }
        }
    }

    /**
     * @notice Evaluate a single market against price ceiling and the configured IMarketFilter
     * @param m Market (tokenAddress, tokenId) to evaluate
     * @param filterData Opaque filter payload forwarded to the resolver
     * @param buyMaxPrice Upper bound on execution price
     * @return pass True if the market has liquidity at an acceptable ask and passes the filter
     * @return peekPrice Top-of-book SELL minPrice (0 if no liquidity)
     * @dev Extracted from _buildSortedMarketList to keep the outer loop's stack small (avoid stack-too-deep in non-via-ir builds such as `forge coverage`).
     */
    function _evaluateMarketForBatch(Market memory m, bytes calldata filterData, uint256 buyMaxPrice)
        internal
        view
        returns (bool pass, uint256 peekPrice)
    {
        uint256[] storage sellOrders = _orderbookMarketplaceStorage().sellOrderIdsByTokenId[m.tokenAddress][m.tokenId];
        peekPrice = _orderbookMarketplaceStorage().orders[sellOrders[sellOrders.length - 1]].minPrice;
        if (peekPrice > buyMaxPrice) {
            return (false, peekPrice);
        }
        // Market filters are configured protocol modules and are intentionally evaluated per candidate market.
        // slither-disable-next-line calls-loop
        if (!IMarketFilter(_orderbookMarketplaceStorage().marketFilter)
                .matchesFilter(m.tokenAddress, m.tokenId, filterData)) {
            return (false, peekPrice);
        }
        return (true, peekPrice);
    }

    // slither-disable-end timestamp

    /**
     * @notice Validate user inputs of the placeOrder() function
     * @param totalAmount Number of bonds to trade
     * @param minPrice Minimum price per bond unit
     * @param maxPrice Maximum price per bond unit
     * @param minMatchAmount Minimum amount for a single match
     */
    function _validatePlaceOrderInputs(uint256 totalAmount, uint256 minPrice, uint256 maxPrice, uint256 minMatchAmount)
        internal
        pure
    {
        if (totalAmount == 0) {
            revert Errors.OrderbookMarketplace__ZeroAmount();
        }
        if (minPrice == 0) {
            revert Errors.OrderbookMarketplace__ZeroPrice();
        }
        if (maxPrice < minPrice) {
            revert Errors.OrderbookMarketplace__InvalidPriceRange(minPrice, maxPrice);
        }
        if (minMatchAmount > totalAmount) {
            revert Errors.OrderbookMarketplace__MinAmountExceedsTotal(minMatchAmount, totalAmount);
        }
    }

    /**
     * @notice Validates trader filter configuration
     * @param mode Trader filter mode
     * @param addresses Trader filter addresses
     */
    function _validateTraderFilter(TraderFilterMode mode, address[] calldata addresses) internal pure {
        if (mode == TraderFilterMode.NONE && addresses.length > 0) {
            revert Errors.OrderbookMarketplace__TradeFilterNotEmpty();
        }
        if (mode != TraderFilterMode.NONE && addresses.length == 0) {
            revert Errors.OrderbookMarketplace__TradeFilterEmpty();
        }
        if (addresses.length > 50) {
            revert Errors.OrderbookMarketplace__TraderFilterTooLarge(addresses.length);
        }
    }
}
