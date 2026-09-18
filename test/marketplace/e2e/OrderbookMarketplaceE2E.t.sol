// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {SharedE2EFixture} from "test/fixtures/SharedE2EFixture.t.sol";
import {IOrderbookMarketplace} from "src/marketplace/interfaces/IOrderbookMarketplace.sol";
import {OrderbookMarketplace} from "src/marketplace/OrderbookMarketplace.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";
import {StringExtensions} from "src/libs/StringExtensions.sol";

contract OrderbookMarketplaceE2ETest is SharedE2EFixture {
    using StringExtensions for string;

    /*//////////////////////////////////////////////////////////////
                           SCENARIO CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 private constant _TRADE_AMOUNT = 100;
    uint256 private constant _TRADE_PRICE = OFFER_UNIT_PRICE;

    /*//////////////////////////////////////////////////////////////
                            SET UP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();
        _approveEscrowOperator(_buyerWallet);
    }

    /*//////////////////////////////////////////////////////////////
          test_e2e_orderbook_sellOrder_buyOrder_match_paid_settled
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. _issuerWallet places a SELL order for _TRADE_AMOUNT at _TRADE_PRICE;
     *      tokens are immediately locked in escrow.
     *   2. _buyerWallet places a matching BUY order at the same price and amount;
     *      the orderbook executes a trade (TradeExecuted event emitted).
     *   3. _paymentProvider marks the trade COMPLETED (TradePaid event).
     *   4. settleTrade releases escrowed tokens to _buyerWallet (TradeSettled event).
     *
     * Purpose: prove the basic end-to-end happy path of the orderbook — sell order
     *          placement, price-matching buy order, payment confirmation, and final
     *          settlement all work correctly together.
     */
    function test_e2e_orderbook_sellOrder_buyOrder_match_paid_settled() public {
        bytes12 isin = BOND_ISIN_ERC6909_FT._isinToBytes12();

        uint256 issuerBalanceBefore = IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId);
        uint256 buyerBalanceBefore = IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId);

        uint256 sellOrderId = _placeSellOrder(isin, _TRADE_AMOUNT, _TRADE_PRICE, _issuerWallet);

        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId),
            issuerBalanceBefore - _TRADE_AMOUNT,
            "issuer balance after sell order"
        );
        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId),
            _TRADE_AMOUNT,
            "escrow balance after sell order"
        );

        uint256 buyOrderId = _placeBuyOrder(isin, _TRADE_AMOUNT, _TRADE_PRICE, _buyerWallet);

        uint256[] memory tradeIds = OrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        assertEq(tradeIds.length, 1, "expected one trade");
        uint256 tradeId = tradeIds[0];

        IOrderbookMarketplace.Trade memory trade = OrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        assertEq(trade.buyer, _buyerWallet);
        assertEq(trade.seller, _issuerWallet);
        assertEq(trade.amount, _TRADE_AMOUNT);
        assertEq(uint8(trade.status), uint8(IOrderbookMarketplace.TradeStatus.PENDING));
        assertEq(trade.sellOrderId, sellOrderId);
        assertEq(trade.buyOrderId, buyOrderId);

        _markTradePaid(tradeId);

        assertEq(
            uint8(OrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId).status),
            uint8(IOrderbookMarketplace.TradeStatus.PAID)
        );

        _settleTrade(tradeId);

        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId),
            buyerBalanceBefore + _TRADE_AMOUNT,
            "buyer balance after settlement"
        );
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), 0, "escrow balance after settlement");

        assertEq(
            uint8(OrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId).status),
            uint8(IOrderbookMarketplace.TradeStatus.SETTLED)
        );

        IOrderbookMarketplace.Order memory sellOrder = OrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(sellOrder.trader, address(0));
        assertEq(sellOrder.amounts.sold, 0);
        assertEq(sellOrder.amounts.inDeals, 0);
        assertEq(sellOrder.amounts.available, 0);
    }

    /*//////////////////////////////////////////////////////////////
    test_e2e_orderbook_partialMatch_respectsMinAmount_and_leavesRemainderOpen
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. _issuerWallet places a SELL order for 100 units with minMatchAmount = 50.
     *   2. _buyerWallet places a BUY order for 60 units (≥ minMatch) → trade executes
     *      for 60; sell order has 40 units remaining available.
     *   3. Trade is paid and settled; _buyerWallet receives 60 bonds.
     *   4. _secondBuyerWallet places a BUY order for 30 units (< minMatch = 50);
     *      the order does NOT match — sell order liquidity stays at 40.
     *
     * Purpose: prove that minMatchAmount is enforced correctly — a buy order below
     *          the threshold does not consume sell-order liquidity, while a buy order
     *          above the threshold triggers a partial fill and leaves the remainder open.
     */
    function test_e2e_orderbook_partialMatch_respectsMinAmount_and_leavesRemainderOpen() public {
        bytes12 isin = BOND_ISIN_ERC6909_FT._isinToBytes12();

        uint256 sellAmount = 100;
        uint256 minMatch = 50;
        uint256 firstBuyAmt = 60;
        uint256 secondBuyAmt = 30;

        uint256 sellOrderId = _placeSellOrderWithMinMatch(isin, sellAmount, _TRADE_PRICE, minMatch, _issuerWallet);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), sellAmount, "escrow after sell order");

        uint256 buy1Id = _placeBuyOrder(isin, firstBuyAmt, _TRADE_PRICE, _buyerWallet);

        uint256[] memory tradeIds = OrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        assertEq(tradeIds.length, 1, "one trade after first buy");
        uint256 tradeId1 = tradeIds[0];

        IOrderbookMarketplace.Trade memory trade1 = OrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId1);
        assertEq(trade1.amount, firstBuyAmt, "trade amount");
        assertEq(uint8(trade1.status), uint8(IOrderbookMarketplace.TradeStatus.PENDING));

        IOrderbookMarketplace.Order memory sellMid = OrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(sellMid.amounts.available, sellAmount - firstBuyAmt, "sell avail after partial match");
        assertEq(sellMid.amounts.inDeals, firstBuyAmt, "sell inDeals after partial");

        _markTradePaid(tradeId1);
        _settleTrade(tradeId1);
        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), firstBuyAmt, "buyer1 balance after settlement"
        );

        IOrderbookMarketplace.Order memory sellAfterSettle =
            OrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(sellAfterSettle.amounts.available, sellAmount - firstBuyAmt, "sell available after settlement");
        assertEq(sellAfterSettle.amounts.inDeals, 0, "sell inDeals after settlement");

        _placeBuyOrder(isin, secondBuyAmt, _TRADE_PRICE, _secondBuyerWallet);

        uint256[] memory tradeIds2 = OrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        assertEq(tradeIds2.length, 1, "still one trade on sell order");

        IOrderbookMarketplace.Order memory sellFinal = OrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(sellFinal.amounts.available, sellAmount - firstBuyAmt, "sell avail unchanged: under-min");
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_secondBuyerWallet, _bondFTId), 0);

        (buy1Id);
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_orderbook_unpaid_dispute_unpaid_returnsAssets
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. _issuerWallet places a SELL order; _buyerWallet places a matching BUY order
     *      → trade is created in PENDING state.
     *   2. Payment deadline passes without payment; markTradeUnpaid is called
     *      (permissionless after deadline) → trade transitions to UNPAID.
     *   3. settleTrade on the UNPAID trade restores escrowed tokens to the sell
     *      order's available inventory after the dispute buffer expires.
     *
     * Purpose: prove the unpaid unhappy path of the orderbook — the orderbook has no
     *          dispute mechanism; a missed payment simply cancels the trade and returns
     *          sell-side liquidity to the open order so it can be re-matched.
     */
    function test_e2e_orderbook_unpaid_dispute_unpaid_returnsAssets() public {
        bytes12 isin = BOND_ISIN_ERC6909_FT._isinToBytes12();

        uint256 issuerBalanceBefore = IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId);

        uint256 sellOrderId = _placeSellOrder(isin, _TRADE_AMOUNT, _TRADE_PRICE, _issuerWallet);
        uint256 buyOrderId = _placeBuyOrder(isin, _TRADE_AMOUNT, _TRADE_PRICE, _buyerWallet);

        uint256[] memory tradeIds = OrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        assertEq(tradeIds.length, 1, "expected one trade");
        uint256 tradeId = tradeIds[0];

        IOrderbookMarketplace.Trade memory trade = OrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        vm.warp(trade.paymentDeadline + 1);

        _markOrderbookTradeUnpaid(tradeId);

        assertEq(
            uint8(OrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId).status),
            uint8(IOrderbookMarketplace.TradeStatus.UNPAID)
        );

        vm.warp(trade.disputeBuffer + 1);
        _settleTrade(tradeId);

        assertEq(
            uint8(OrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId).status),
            uint8(IOrderbookMarketplace.TradeStatus.CANCELLED)
        );
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), 0, "buyer receives nothing");
        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId),
            issuerBalanceBefore - _TRADE_AMOUNT,
            "seller tokens remain escrowed"
        );
        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, _bondFTId), _TRADE_AMOUNT, "escrow: sell-side inventory"
        );

        IOrderbookMarketplace.Order memory sellOrder = OrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(sellOrder.amounts.available, _TRADE_AMOUNT, "sell order available restored");
        assertEq(sellOrder.amounts.inDeals, 0, "sell order inDeals cleared");

        (buyOrderId);
    }
}
