// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {OrderbookMarketplace} from "src/marketplace/OrderbookMarketplace.sol";
import {IOrderbookMarketplace} from "src/marketplace/interfaces/IOrderbookMarketplace.sol";
import {Errors} from "src/libs/Errors.sol";
import {MarketplaceFixture} from "test/fixtures/MarketplaceFixture.t.sol";
import {DEUSSToken} from "src/token/fungible/DEUSSToken.sol";

contract TWAPOracleTest is MarketplaceFixture {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address internal _buyer;
    address internal _seller;
    address internal _paymentHandler;
    uint256 internal _tokenId;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();

        _tokenId = _bondFTId;

        (_buyer,) = _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("twapBuyer"), 0);
        (_seller,) = _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("twapSeller"), 0);

        _paymentHandler = makeAddr("twapPaymentHandler");
        uint256 paymentHandlerRole = OrderbookMarketplace(_orderbookMarketplace).PAYMENT_HANDLER();
        _grantRoles(_orderbookMarketplace, _paymentHandler, paymentHandlerRole);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Place a fixed-price SELL order and a matching BUY order in the same block at `ts`.
    ///      Returns the trade ID from the matched pair.
    function _matchAt(uint256 ts, uint256 price, uint256 amount) internal returns (uint256 tradeId) {
        vm.warp(ts);

        // Ensure seller has tokens
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _tokenId, amount);
        _approveEscrowManagerAsOperator(_seller);

        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: price,
                maxPrice: price,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: price,
                maxPrice: price,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        uint256[] memory ids = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        tradeId = ids[ids.length - 1];
    }

    /*//////////////////////////////////////////////////////////////
                    getTWAP
    //////////////////////////////////////////////////////////////*/

    /// @notice Trades at t=100 (price 20), t=300 (price 22), t=500 (price 23).
    ///         getTWAP(secondsAgo=400) at t=600 must return 21 (integer division of 21.4).
    function test_getTWAP_returnsExpectedValue() public {
        // Trade 1 at t=100, price=20
        _matchAt(100, 20, 1);
        // Trade 2 at t=300, price=22
        _matchAt(300, 22, 1);
        // Trade 3 at t=500, price=23
        _matchAt(500, 23, 1);

        // Verify stored observations
        // Obs[1]: {timestamp: 100, cumulativePrice: 0}
        IOrderbookMarketplace.Observation memory obs1 =
            IOrderbookMarketplace(_orderbookMarketplace).getObservation(_tokenAddr, _tokenId, 1);
        assertEq(obs1.timestamp, 100);
        assertEq(obs1.cumulativePrice, 0);

        // Obs[2]: {timestamp: 300, cumulativePrice: 4000}  (0 + 20 * (300-100))
        IOrderbookMarketplace.Observation memory obs2 =
            IOrderbookMarketplace(_orderbookMarketplace).getObservation(_tokenAddr, _tokenId, 2);
        assertEq(obs2.timestamp, 300);
        assertEq(obs2.cumulativePrice, 4000);

        // Obs[3]: {timestamp: 500, cumulativePrice: 8400}  (4000 + 22 * (500-300))
        IOrderbookMarketplace.Observation memory obs3 =
            IOrderbookMarketplace(_orderbookMarketplace).getObservation(_tokenAddr, _tokenId, 3);
        assertEq(obs3.timestamp, 500);
        assertEq(obs3.cumulativePrice, 8400);

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getLastTradedPrice(_tokenAddr, _tokenId), 23);

        // At t=600, secondsAgo=400 -> targetTime=200 -> closest obs (floor) = obs[1] {t=100, c=0}
        // currentCumulative = 8400 + 23*(600-500) = 10700
        // TWAP = (10700 - 0) / (600 - 100) = 10700/500 = 21 (integer division)
        vm.warp(600);
        uint256 twap = IOrderbookMarketplace(_orderbookMarketplace).getTWAP(_tokenAddr, _tokenId, 400);
        assertEq(twap, 21);
    }

    /// @notice Querying TWAP before any trade has been recorded must revert.
    function test_getTWAP_reverts_noObservations() public {
        vm.expectRevert(Errors.OrderbookMarketplace__NoObservations.selector);
        IOrderbookMarketplace(_orderbookMarketplace).getTWAP(_tokenAddr, _tokenId, 100);
    }

    /// @notice Querying at the exact block of the only observation must revert (timeElapsed = 0).
    function test_getTWAP_reverts_insufficientAge_sameBlock() public {
        _matchAt(100, 20, 1);

        // Still at t=100; secondsAgo=0 -> targetTime=100 -> foundObs.timestamp=100 -> timeElapsed=0
        vm.expectRevert(Errors.OrderbookMarketplace__InsufficientTWAPAge.selector);
        IOrderbookMarketplace(_orderbookMarketplace).getTWAP(_tokenAddr, _tokenId, 0);
    }

    /// @notice With one observation at t=100 and query at t=200, TWAP over [100,200] = lastPrice.
    function test_getTWAP_singleObservation_returnsLastPrice() public {
        _matchAt(100, 50, 1);

        vm.warp(200);
        // foundObs = obs[1] {t=100, c=0}, latestObs = same
        // currentCumulative = 0 + 50*(200-100) = 5000
        // TWAP = (5000 - 0) / (200-100) = 50
        uint256 twap = IOrderbookMarketplace(_orderbookMarketplace).getTWAP(_tokenAddr, _tokenId, 100);
        assertEq(twap, 50);
    }

    /// @notice secondsAgo larger than any recorded history falls back to the oldest observation.
    function test_getTWAP_secondsAgoExceedsHistory_usesOldestObservation() public {
        _matchAt(100, 50, 1);
        _matchAt(200, 60, 1);

        vm.warp(300);
        // block.timestamp=300, secondsAgo=150 -> targetTime=150
        // observations at t=100 and t=200; floor of 150 -> obs[1] at t=100
        // latestObs = obs[2] {t=200, c=5000}
        // currentCumulative = 5000 + 60*(300-200) = 11000
        // TWAP = (11000 - 0) / (300-100) = 11000/200 = 55
        uint256 twap = IOrderbookMarketplace(_orderbookMarketplace).getTWAP(_tokenAddr, _tokenId, 150);
        assertEq(twap, 55);
    }

    /// @notice secondsAgo larger than the current block timestamp clamps to targetTime = 0
    ///         and still falls back to the oldest retained observation.
    function test_getTWAP_secondsAgoExceedsCurrentTimestamp_usesOldestObservation() public {
        _matchAt(100, 50, 1);
        _matchAt(200, 60, 1);

        vm.warp(300);
        // block.timestamp=300, secondsAgo=301 -> targetTime clamps to 0
        // observations at t=100 and t=200; no observation is at or before 0 -> fallback to obs[1] at t=100
        // latestObs = obs[2] {t=200, c=5000}
        // currentCumulative = 5000 + 60*(300-200) = 11000
        // TWAP = (11000 - 0) / (300-100) = 11000/200 = 55
        uint256 twap = IOrderbookMarketplace(_orderbookMarketplace).getTWAP(_tokenAddr, _tokenId, 301);
        assertEq(twap, 55);
    }

    /*//////////////////////////////////////////////////////////////
                      FLOOR LOOKUP (BINARY SEARCH)
    //////////////////////////////////////////////////////////////*/

    /// @notice targetTime falls exactly on an observation's timestamp -> use that observation.
    function test_getTWAP_exactTimestampMatch() public {
        _matchAt(100, 20, 1);
        _matchAt(300, 22, 1);
        _matchAt(500, 23, 1);

        vm.warp(600);
        // secondsAgo=300 -> targetTime=300 -> exact match obs[2] {t=300, c=4000}
        // currentCumulative = 8400 + 23*100 = 10700
        // TWAP = (10700 - 4000) / (600-300) = 6700/300 = 22
        uint256 twap = IOrderbookMarketplace(_orderbookMarketplace).getTWAP(_tokenAddr, _tokenId, 300);
        assertEq(twap, 22);
    }

    /// @notice targetTime is between two observations -> use the earlier one (floor).
    function test_getTWAP_targetBetweenObservations_usesFloor() public {
        _matchAt(100, 10, 1);
        _matchAt(200, 20, 1);
        _matchAt(400, 30, 1);

        vm.warp(500);
        // secondsAgo=250 -> targetTime=250 -> floor = obs[2] {t=200, c=1000}  (0 + 10*100)
        // currentCumulative = (1000 + 20*200) + 30*(500-400) = 5000 + 3000 = (obs[3]=5000) + 30*100 = 8000
        // Recalc:
        // obs[1] t=100 c=0
        // obs[2] t=200 c=0+10*(200-100)=1000
        // obs[3] t=400 c=1000+20*(400-200)=5000
        // lastPrice=30
        // currentCumulative = 5000 + 30*(500-400) = 8000
        // TWAP = (8000 - 1000) / (500 - 200) = 7000/300 = 23
        uint256 twap = IOrderbookMarketplace(_orderbookMarketplace).getTWAP(_tokenAddr, _tokenId, 250);
        assertEq(twap, 23);
    }

    /// @notice targetTime is before all observations -> fall back to oldest observation.
    function test_getTWAP_targetBeforeAllObservations_usesOldest() public {
        _matchAt(500, 20, 1);
        _matchAt(700, 22, 1);

        vm.warp(1000);
        // secondsAgo=600 -> targetTime=400 -> no obs with timestamp <= 400 -> fallback to obs[1] {t=500, c=0}
        // currentCumulative = (0 + 20*200) + 22*(1000-700) = 4000 + 6600 = (obs[2]=4000) + 22*300 = 10600
        // TWAP = (10600 - 0) / (1000-500) = 10600/500 = 21
        uint256 twap = IOrderbookMarketplace(_orderbookMarketplace).getTWAP(_tokenAddr, _tokenId, 600);
        assertEq(twap, 21);
    }

    /*//////////////////////////////////////////////////////////////
                        OBSERVATION RECORDING
    //////////////////////////////////////////////////////////////*/

    /// @notice The TWAPObservationRecorded event is emitted on every trade.
    function test_recordObservation_emitsEvent() public {
        vm.warp(100);
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _tokenId, 1);
        _approveEscrowManagerAsOperator(_seller);

        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 1,
                minPrice: 20,
                maxPrice: 20,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        vm.expectEmit(true, true, false, true);
        emit IOrderbookMarketplace.TWAPObservationRecorded(
            _tokenAddr,
            _tokenId,
            uint32(100),
            uint224(0), // cumulativePrice = 0 + 0 * 100 = 0 (lastPrice was 0 before first trade)
            20
        );

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 1,
                minPrice: 20,
                maxPrice: 20,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    /// @notice A trade that would push lastPrice * timeElapsed above uint224 max must revert
    ///         instead of silently corrupting the accumulator.
    function test_recordObservation_reverts_accumulatorOverflow() public {
        // First trade at t=1 sets lastPrice = type(uint224).max
        _matchAt(1, type(uint224).max, 1);

        // Manually stage the second trade so vm.expectRevert catches exactly the BUY call
        // that triggers the match.
        vm.warp(3);
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _tokenId, 1);
        _approveEscrowManagerAsOperator(_seller);

        // SELL placed first — no match yet, no revert
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 1,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // BUY triggers the match: contribution = type(uint224).max * 2 > type(uint224).max → revert
        vm.expectRevert(Errors.OrderbookMarketplace__TWAPAccumulatorOverflow.selector);
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 1,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    /*//////////////////////////////////////////////////////////////
                     MULTIPLE TOKENS — INDEPENDENCE
    //////////////////////////////////////////////////////////////*/

    /// @notice TWAP observations for distinct (tokenAddress, tokenId) pairs do not interfere.
    function test_getTWAP_multipleTokensAreIndependent() public {
        // Two different token IDs on the same address.
        // We reuse _tokenAddr but need a second tokenId.
        // The easiest path: verify that querying a token with no trades still reverts.
        _matchAt(100, 100, 1);

        // A non-existent tokenId has no observations
        uint256 otherTokenId = _tokenId + 9999;
        vm.expectRevert(Errors.OrderbookMarketplace__NoObservations.selector);
        IOrderbookMarketplace(_orderbookMarketplace).getTWAP(_tokenAddr, otherTokenId, 1);

        // Our token still works
        vm.warp(200);
        uint256 twap = IOrderbookMarketplace(_orderbookMarketplace).getTWAP(_tokenAddr, _tokenId, 50);
        assertEq(twap, 100);
    }

    /*//////////////////////////////////////////////////////////////
                    GETOBSERVATION / GETLASTTRADEDPRICE
    //////////////////////////////////////////////////////////////*/

    /// @notice Observations are written into successive ring-buffer slots, one per executed trade.
    function test_getObservation_recordsPerTradeAtExpectedSlots() public {
        IOrderbookMarketplace.Observation memory emptyObservation =
            IOrderbookMarketplace(_orderbookMarketplace).getObservation(_tokenAddr, _tokenId, 1);
        assertEq(emptyObservation.timestamp, 0);
        assertEq(emptyObservation.cumulativePrice, 0);

        _matchAt(100, 10, 1);
        IOrderbookMarketplace.Observation memory obs1 =
            IOrderbookMarketplace(_orderbookMarketplace).getObservation(_tokenAddr, _tokenId, 1);
        assertEq(obs1.timestamp, 100);
        assertEq(obs1.cumulativePrice, 0);

        _matchAt(200, 20, 1);
        IOrderbookMarketplace.Observation memory obs2 =
            IOrderbookMarketplace(_orderbookMarketplace).getObservation(_tokenAddr, _tokenId, 2);
        assertEq(obs2.timestamp, 200);
        assertEq(obs2.cumulativePrice, 1000);

        _matchAt(300, 30, 1);
        IOrderbookMarketplace.Observation memory obs3 =
            IOrderbookMarketplace(_orderbookMarketplace).getObservation(_tokenAddr, _tokenId, 3);
        assertEq(obs3.timestamp, 300);
        assertEq(obs3.cumulativePrice, 3000);
    }

    /// @notice Last traded price starts at zero and updates to the most recent trade price.
    function test_getLastTradedPrice_updatesAfterEachTrade() public {
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getLastTradedPrice(_tokenAddr, _tokenId), 0);

        _matchAt(100, 10, 1);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getLastTradedPrice(_tokenAddr, _tokenId), 10);

        _matchAt(200, 25, 1);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getLastTradedPrice(_tokenAddr, _tokenId), 25);
    }

    /*//////////////////////////////////////////////////////////////
                    CONSECUTIVE TRADES IN SAME BLOCK
    //////////////////////////////////////////////////////////////*/

    /// @notice Multiple trades in the same block each write an observation, but the
    ///         second and subsequent ones have timeElapsed = 0 so they add 0 to the accumulator.
    ///         The TWAP should reflect only the first trade's price up to the next block.
    function test_getTWAP_twoTradesInSameBlock() public {
        // First trade in block 100
        _matchAt(100, 10, 1);
        // Second trade also in block 100
        _matchAt(100, 20, 1);

        // obs[1]: {t=100, c=0}  (firstTrade: c = 0 + 0*100 = 0, lastPrice becomes 10)
        // obs[2]: {t=100, c=0}  (secondTrade: c = 0 + 10*0 = 0,  lastPrice becomes 20)
        IOrderbookMarketplace.Observation memory obs2 =
            IOrderbookMarketplace(_orderbookMarketplace).getObservation(_tokenAddr, _tokenId, 2);
        assertEq(obs2.timestamp, 100);
        assertEq(obs2.cumulativePrice, 0);

        vm.warp(200);
        // foundObs = obs[2] (latest with t<=targetTime when secondsAgo=0 would be same block,
        // but with secondsAgo=50 -> targetTime=150 -> floor is obs[2] {t=100, c=0})
        // currentCumulative = 0 + 20*(200-100) = 2000
        // TWAP = (2000 - 0) / (200-100) = 20
        uint256 twap = IOrderbookMarketplace(_orderbookMarketplace).getTWAP(_tokenAddr, _tokenId, 50);
        assertEq(twap, 20);
    }

    /*//////////////////////////////////////////////////////////////
                      CIRCULAR BUFFER WRAP-AROUND
    //////////////////////////////////////////////////////////////*/

    /// @notice After exactly MAX_RECENT_OBSERVATIONS (256) trades the buffer is full and
    ///         the 257th trade overwrites index 1 (oldest slot) with fresh data.
    function test_circularBuffer_overwritesFirstRetainedSlotAfterWrap() public {
        uint16 maxObs = OrderbookMarketplace(_orderbookMarketplace).MAX_RECENT_OBSERVATIONS();

        // Place maxObs + 1 trades at t=1, t=2, …, t=maxObs+1 to trigger wrap
        for (uint256 i = 1; i < uint256(maxObs) + 2; ++i) {
            _matchAt(i, 100 + i, 1);
        }

        IOrderbookMarketplace.Observation memory overwrittenSlot =
            IOrderbookMarketplace(_orderbookMarketplace).getObservation(_tokenAddr, _tokenId, 1);
        assertEq(overwrittenSlot.timestamp, uint32(uint256(maxObs) + 1));

        IOrderbookMarketplace.Observation memory oldestRetainedSlot =
            IOrderbookMarketplace(_orderbookMarketplace).getObservation(_tokenAddr, _tokenId, 2);
        assertEq(oldestRetainedSlot.timestamp, 2);
    }

    /// @notice After the buffer wraps, getTWAP still works correctly using the now-oldest
    ///         valid slot rather than the physically-zeroed slot at index 0.
    function test_circularBuffer_twapWorksAfterWrap() public {
        uint16 maxObs = OrderbookMarketplace(_orderbookMarketplace).MAX_RECENT_OBSERVATIONS();

        // Fill buffer exactly — 256 trades, each 1 second apart, all price = 100
        for (uint256 i = 1; i < uint256(maxObs) + 1; ++i) {
            _matchAt(i, 100, 1);
        }

        // One more trade to cause wrap: after trade 256 currentIndex = 0, so trade 257 writes to slot 1.
        _matchAt(uint256(maxObs) + 1, 200, 1);

        // After wrap:
        // - slot 1 now contains trade 257 at t=257, price=200
        // - slot 2 is the oldest retained observation and still corresponds to trade 2 at t=2
        //
        // At t=258 with secondsAgo=10:
        // - targetTime = 258 - 10 = 248
        // - the floor observation is trade 248 at t=248
        // - obs[248] cumulativePrice = 100 * (248 - 1) = 24700
        // - latestObs is trade 257 at t=257 with cumulativePrice = 100 * (257 - 1) = 25600
        // - currentCumulative = 25600 + 200 * (258 - 257) = 25800
        // - TWAP = (25800 - 24700) / (258 - 248) = 1100 / 10 = 110
        vm.warp(uint256(maxObs) + 2);
        uint256 twap = IOrderbookMarketplace(_orderbookMarketplace).getTWAP(_tokenAddr, _tokenId, 10);
        assertEq(twap, 110, "TWAP positive after wrap");
    }
}
