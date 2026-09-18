// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {vm} from "@perimetersec/fuzzlib/src/IHevm.sol";
import {Errors} from "src/libs/Errors.sol";
import {BondStatus, CouponRateType} from "src/registry/BondStructs.sol";
import {BondMarketFilter} from "src/marketplace/filters/BondMarketFilter.sol";
import {IOrderbookMarketplace} from "src/marketplace/interfaces/IOrderbookMarketplace.sol";
import {PreconditionsBase} from "../preconditions/PreconditionsBase.sol";
import {PostconditionsOrderbookMarketplace} from "../postconditions/PostconditionsOrderbookMarketplace.sol";

/// @title HandlerOrderbookMarketplace
/// @notice Directed coverage handlers for OrderbookMarketplace and BondMarketFilter.
abstract contract HandlerOrderbookMarketplace is PreconditionsBase, PostconditionsOrderbookMarketplace {
    bytes4 internal constant _ORDERBOOK_PANIC_SELECTOR = 0x4e487b71;

    function handler_bondMarketFilterSurface(uint256 seed) public {
        uint256 tokenId = _nextOrderbookTokenId(seed);
        uint256 missingTokenId = _nextOrderbookTokenId(seed);
        address tokenAddress = address(fuzzERC1155);

        bondMarketFilter.setAdapter(tokenAddress, address(fuzzBondAdapter));
        bondMarketFilterAdapterPostconditions(bondMarketFilter.adapter(tokenAddress), address(fuzzBondAdapter));

        BondMarketFilter.BondFilter memory filter = _emptyBondFilter();
        bondMarketFilter.encodeFilter(filter);

        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(address(fuzzERC20), tokenId, abi.encode(filter)), false
        );
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, missingTokenId, abi.encode(filter)), false
        );

        _configureFuzzBond(
            tokenId, bytes3(bytes(BOND_CURRENCY)), issuer, BondStatus.Issued, CouponRateType.FIXED, 1_000, 500
        );
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), true
        );

        uint256 inactiveTokenId = _nextOrderbookTokenId(seed);
        _configureFuzzBond(
            inactiveTokenId,
            bytes3(bytes(BOND_CURRENCY)),
            issuer,
            BondStatus.Suspended,
            CouponRateType.FIXED,
            1_000,
            500
        );
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, inactiveTokenId, abi.encode(filter)), false
        );

        _exerciseBondFilterRanges(tokenAddress, tokenId);
        _exerciseBondFilterLists(tokenAddress, tokenId);
        _exerciseBondFilterCouponBranches(tokenAddress, tokenId);
        _exerciseBondFilterInvalidRanges(tokenAddress, tokenId);
    }

    function handler_orderbookMarketplaceSurface(uint256 seed) public {
        uint256 tokenId = _nextOrderbookTokenId(seed);
        _configureFuzzBond(
            tokenId, bytes3(bytes(BOND_CURRENCY)), issuer, BondStatus.Issued, CouponRateType.FIXED, 1_000, 500
        );

        _exerciseOrderbookAdminSurface();
        _exerciseOrderbookCancellationSurface(tokenId);
    }

    function handler_orderbookMarketplaceTradeSurface(uint256 seed) public {
        _exerciseOrderbookTradeSurface(_nextOrderbookTokenId(seed));
    }

    function handler_orderbookMarketplaceFreezeSeizureSurface(uint256 seed) public {
        _exerciseOrderbookFreezeSeizureSurface(_nextOrderbookTokenId(seed));
    }

    function handler_orderbookMarketplaceBatchSurface(uint256 seed) public {
        _exerciseOrderbookBatchSurface(_nextOrderbookTokenId(seed));
    }

    function handler_orderbookMarketplaceOpenBookViewSurface(uint256 seed) public {
        _exerciseOrderbookOpenBookViewSurface(_nextOrderbookTokenId(seed));
    }

    function handler_orderbookMarketplaceInternalValidationSurface(uint256 seed) public {
        _exerciseOrderbookInternalValidationCoverage(seed);
    }

    function handler_orderbookMarketplaceInternalMatchBuySurface(uint256 seed) public {
        _exerciseOrderbookInternalMatchBuyCoverage(seed);
    }

    function handler_orderbookMarketplaceInternalMatchSellSurface(uint256 seed) public {
        _exerciseOrderbookInternalMatchSellCoverage(seed);
    }

    function handler_orderbookMarketplaceInternalResidualAndBatchSurface(uint256 seed) public {
        _exerciseOrderbookInternalResidualAndBatchCoverage(seed);
    }

    function handler_marketplaceEscrowResidualSurface() public {
        uint256 erc721TokenId = ++fuzzERC721TokenCursor;
        fuzzERC721.mint(address(escrowManagerCoverage), erc721TokenId);
        escrowManagerERC721BalanceCoveragePostconditions(
            escrowManagerCoverage.exposedBalanceHeldERC721(address(fuzzERC721), erc721TokenId)
        );
        escrowManagerCoverage.exposedTransferERC721(address(fuzzERC721), erc721TokenId, USER3);

        _expectMarketplaceCoverageRevert(
            address(marketplaceCoverage),
            abi.encodeWithSelector(marketplaceCoverage.exposedInvalidCancellationSaleMode.selector),
            _ORDERBOOK_PANIC_SELECTOR
        );
        _expectMarketplaceCoverageRevert(
            address(marketplaceCoverage),
            abi.encodeWithSelector(marketplaceCoverage.exposedInvalidPaymentExpirySaleMode.selector),
            Errors.Marketplace__InvalidSaleMode.selector
        );
        _expectMarketplaceCoverageRevert(
            address(marketplaceCoverage),
            abi.encodeWithSelector(marketplaceCoverage.exposedInvalidInterestStatus.selector),
            Errors.Marketplace__InvalidInterestStatus.selector
        );
        _expectMarketplaceCoverageRevert(
            address(marketplaceCoverage),
            abi.encodeWithSelector(marketplaceCoverage.exposedValidateMarketplaceSaleMode.selector),
            Errors.Marketplace__NotMarketplaceOffer.selector
        );
        _expectEscrowManagerCoverageRevert(
            address(escrowManagerCoverage),
            abi.encodeWithSelector(escrowManagerCoverage.exposedInvalidTransferAsset.selector, address(fuzzERC20)),
            Errors.EscrowManager__InvalidAssetType.selector
        );
        _expectEscrowManagerCoverageRevert(
            address(escrowManagerCoverage),
            abi.encodeWithSelector(escrowManagerCoverage.exposedInvalidBalanceHeld.selector, address(fuzzERC20)),
            Errors.EscrowManager__InvalidAssetType.selector
        );
    }

    function _exerciseOrderbookAdminSurface() internal {
        orderbookMarketplace.setAssetManager(address(assetManager));
        orderbookMarketplace.setEntityRegistry(address(entityRegistry));
        orderbookMarketplace.setEscrowManager(address(escrowManager));
        orderbookMarketplace.setPaymentExpiryThreshold(PAYMENT_EXPIRY_THRESHOLD);
        orderbookMarketplace.setMinExpiryThreshold(ORDERBOOK_MIN_EXPIRY_THRESHOLD);
        orderbookMarketplace.setDisputeBufferPeriod(DISPUTE_BUFFER_PERIOD);
        orderbookMarketplace.setMarketFilter(address(bondMarketFilter));

        orderbookAdminSurfacePostconditions();
    }

    function _exerciseOrderbookCancellationSurface(uint256 tokenId) internal {
        address[] memory zeroFilterAddresses = new address[](1);
        IOrderbookMarketplace.OrderInput memory zeroFilterInput = IOrderbookMarketplace.OrderInput({
            tokenAddress: address(fuzzERC1155),
            tokenId: tokenId,
            totalAmount: 1,
            minPrice: 1,
            maxPrice: 1,
            minMatchAmount: 0,
            traderFilterMode: IOrderbookMarketplace.TraderFilterMode.WHITELIST,
            traderFilterAddresses: zeroFilterAddresses,
            side: IOrderbookMarketplace.OrderSide.BUY,
            expiry: 0
        });
        _expectOrderbookRevert(
            address(orderbookMarketplace),
            abi.encodeWithSelector(orderbookMarketplace.placeOrder.selector, zeroFilterInput, address(0)),
            Errors.ZeroAddress.selector
        );

        uint256 buyOrderId = _placeOrderbookOrder(
            USER2,
            tokenId,
            2,
            1,
            2,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.BUY,
            0
        );
        vm.prank(USER2);
        orderbookMarketplace.cancelOrder(buyOrderId, address(0));

        uint256 sellOrderId = _placeOrderbookOrder(
            USER1,
            tokenId,
            2,
            2,
            3,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.SELL,
            0
        );
        vm.prank(USER1);
        orderbookMarketplace.cancelOrder(sellOrderId, address(0));

        (bool delegateSuccess, bytes memory delegateReturnData) = fl.doFunctionCall(
            address(orderbookMarketplace),
            abi.encodeWithSelector(orderbookMarketplace.setDelegate.selector, USER2, true),
            USER1
        );
        orderbookDelegatePostconditions(delegateSuccess, delegateReturnData);

        uint256 delegatedOrderId = _placeOrderbookOrderOnBehalf(USER2, USER1, tokenId, 1, 2, 3);
        vm.prank(USER2);
        orderbookMarketplace.cancelOrder(delegatedOrderId, USER1);

        (bool revokeSuccess, bytes memory revokeReturnData) = fl.doFunctionCall(
            address(orderbookMarketplace),
            abi.encodeWithSelector(orderbookMarketplace.setDelegate.selector, USER2, false),
            USER1
        );
        orderbookDelegatePostconditions(revokeSuccess, revokeReturnData);

        uint256 expiringOrderId = _placeOrderbookOrder(
            USER1,
            tokenId,
            1,
            2,
            3,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.SELL,
            block.timestamp + ORDERBOOK_MIN_EXPIRY_THRESHOLD + 1
        );
        _expectOrderbookRevert(
            address(orderbookMarketplace),
            abi.encodeWithSelector(orderbookMarketplace.cleanupExpiredOrder.selector, expiringOrderId),
            Errors.OrderbookMarketplace__OrderNotExpired.selector
        );
        vm.warp(block.timestamp + ORDERBOOK_MIN_EXPIRY_THRESHOLD + 2);
        orderbookMarketplace.cleanupExpiredOrder(expiringOrderId);
    }

    // solhint-disable-next-line function-max-lines
    function _exerciseOrderbookTradeSurface(uint256 tokenId) internal {
        _configureFuzzBond(
            tokenId, bytes3(bytes(BOND_CURRENCY)), issuer, BondStatus.Issued, CouponRateType.FIXED, 1_000, 500
        );
        uint256 paidSellOrderId = _placeOrderbookOrder(
            USER1,
            tokenId,
            2,
            2,
            4,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.SELL,
            0
        );
        uint256 paidBuyOrderId = _placeOrderbookOrder(
            USER2,
            tokenId,
            2,
            1,
            3,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.BUY,
            0
        );
        uint256 paidTradeId = _firstTradeId(paidSellOrderId);
        _exerciseOrderbookViews(tokenId, paidBuyOrderId, paidSellOrderId, paidTradeId);
        orderbookMarketplace.markTradePaid(paidTradeId);
        orderbookMarketplace.settleTrade(paidTradeId);

        vm.warp(block.timestamp + 1);
        uint256 secondSellOrderId = _placeOrderbookOrder(
            USER1,
            tokenId,
            1,
            2,
            4,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.SELL,
            0
        );
        _placeOrderbookOrder(
            USER2,
            tokenId,
            1,
            1,
            3,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.BUY,
            0
        );
        uint256 secondTradeId = _firstTradeId(secondSellOrderId);
        orderbookMarketplace.getObservation(address(fuzzERC1155), tokenId, 1);
        orderbookMarketplace.getLastTradedPrice(address(fuzzERC1155), tokenId);
        vm.warp(block.timestamp + 1);
        orderbookMarketplace.getTWAP(address(fuzzERC1155), tokenId, 1);
        orderbookMarketplace.markTradePaid(secondTradeId);
        orderbookMarketplace.settleTrade(secondTradeId);

        uint256 unpaidBuyOrderId = _placeOrderbookOrder(
            USER2,
            tokenId,
            1,
            1,
            4,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.BUY,
            0
        );
        uint256 unpaidSellOrderId = _placeOrderbookOrder(
            USER1,
            tokenId,
            1,
            2,
            4,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.SELL,
            0
        );
        uint256 unpaidTradeId = _firstTradeId(unpaidSellOrderId);
        IOrderbookMarketplace.Trade memory unpaidTrade = orderbookMarketplace.getTrade(unpaidTradeId);
        vm.warp(unpaidTrade.paymentDeadline + 1);
        orderbookMarketplace.markTradeUnpaid(unpaidTradeId);
        _expectOrderbookRevert(
            address(orderbookMarketplace),
            abi.encodeWithSelector(orderbookMarketplace.settleTrade.selector, unpaidTradeId),
            Errors.OrderbookMarketplace__DisputePeriodNotExpired.selector
        );
        vm.prank(USER2);
        orderbookMarketplace.initiateDispute(unpaidTradeId);
        _expectOrderbookRevert(
            address(orderbookMarketplace),
            abi.encodeWithSelector(
                orderbookMarketplace.resolveDispute.selector, unpaidTradeId, IOrderbookMarketplace.TradeStatus.CANCELLED
            ),
            Errors.OrderbookMarketplace__InvalidDisputeResolution.selector
        );
        orderbookMarketplace.resolveDispute(unpaidTradeId, IOrderbookMarketplace.TradeStatus.UNPAID);
        unpaidTrade = orderbookMarketplace.getTrade(unpaidTradeId);
        vm.warp(unpaidTrade.disputeBuffer + 1);
        orderbookMarketplace.settleTrade(unpaidTradeId);
        vm.prank(USER2);
        orderbookMarketplace.cancelOrder(unpaidBuyOrderId, address(0));
        vm.prank(USER1);
        orderbookMarketplace.cancelOrder(unpaidSellOrderId, address(0));

        orderbookMarketplace.getOrder(unpaidBuyOrderId);
    }

    // solhint-disable-next-line function-max-lines
    function _exerciseOrderbookFreezeSeizureSurface(uint256 tokenId) internal {
        _configureFuzzBond(
            tokenId, bytes3(bytes(BOND_CURRENCY)), issuer, BondStatus.Issued, CouponRateType.FIXED, 1_000, 500
        );

        uint256 sellOrderId = _placeOrderbookOrder(
            USER1,
            tokenId,
            1,
            2,
            3,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.SELL,
            0
        );
        orderbookMarketplace.setOrderFrozen(sellOrderId, true, keccak256("FUZZ_FREEZE"));
        orderbookMarketplace.getOrderBook(address(fuzzERC1155), tokenId);
        orderbookMarketplace.setOrderFrozen(sellOrderId, false, keccak256("FUZZ_UNFREEZE"));
        orderbookMarketplace.setOrderFrozen(sellOrderId, true, keccak256("FUZZ_REFREEZE"));
        orderbookMarketplace.seizeOrder(sellOrderId, USER3, keccak256("FUZZ_SEIZE"));

        uint256 buyOrderId = _placeOrderbookOrder(
            USER2,
            tokenId,
            1,
            1,
            3,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.BUY,
            0
        );
        orderbookMarketplace.setOrderFrozen(buyOrderId, true, keccak256("FUZZ_BUY_FREEZE"));
        orderbookMarketplace.seizeOrder(buyOrderId, USER3, keccak256("FUZZ_BUY_SEIZE"));

        uint256 tradeSellOrderId = _placeOrderbookOrder(
            USER1,
            tokenId,
            1,
            2,
            3,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.SELL,
            0
        );
        _placeOrderbookOrder(
            USER2,
            tokenId,
            1,
            1,
            3,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.BUY,
            0
        );
        uint256 tradeId = _firstTradeId(tradeSellOrderId);
        orderbookMarketplace.setOrderFrozen(tradeSellOrderId, true, keccak256("FUZZ_TRADE_ORDER_FREEZE"));
        orderbookMarketplace.setTradeFrozen(tradeId, true, keccak256("FUZZ_TRADE_FREEZE"));
        orderbookMarketplace.setTradeFrozen(tradeId, false, keccak256("FUZZ_TRADE_UNFREEZE"));
        orderbookMarketplace.setTradeFrozen(tradeId, true, keccak256("FUZZ_TRADE_REFREEZE"));
        orderbookMarketplace.seizeTrade(tradeId, USER3, keccak256("FUZZ_TRADE_SEIZE"));

        uint256 disputedSellOrderId = _placeOrderbookOrder(
            USER1,
            tokenId,
            1,
            2,
            3,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.SELL,
            0
        );
        _placeOrderbookOrder(
            USER2,
            tokenId,
            1,
            1,
            3,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.BUY,
            0
        );
        uint256 disputedTradeId = _firstTradeId(disputedSellOrderId);
        IOrderbookMarketplace.Trade memory disputedTrade = orderbookMarketplace.getTrade(disputedTradeId);
        vm.warp(disputedTrade.paymentDeadline + 1);
        orderbookMarketplace.markTradeUnpaid(disputedTradeId);
        vm.prank(USER2);
        orderbookMarketplace.initiateDispute(disputedTradeId);
        orderbookMarketplace.setOrderFrozen(disputedSellOrderId, true, keccak256("FUZZ_DISPUTE_ORDER_FREEZE"));
        orderbookMarketplace.setTradeFrozen(disputedTradeId, true, keccak256("FUZZ_DISPUTE_TRADE_FREEZE"));
        orderbookMarketplace.seizeTrade(disputedTradeId, USER3, keccak256("FUZZ_DISPUTE_TRADE_SEIZE"));
    }

    function _exerciseOrderbookBatchSurface(uint256 tokenId) internal {
        uint256 secondTokenId = tokenId + 1;
        _configureFuzzBond(
            tokenId, bytes3(bytes(BOND_CURRENCY)), issuer, BondStatus.Issued, CouponRateType.FIXED, 1_000, 500
        );
        _configureFuzzBond(secondTokenId, bytes3("USD"), USER2, BondStatus.Issued, CouponRateType.ZERO_COUPON, 2_000, 0);

        orderbookMarketplace.placeBatchOrder(_batchInput(1, 1, 2, _emptyBondFilter()));

        uint256 firstSellOrderId = _placeOrderbookOrder(
            USER1,
            tokenId,
            2,
            2,
            2,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.SELL,
            0
        );
        _placeOrderbookOrder(
            USER1,
            secondTokenId,
            2,
            1,
            1,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.SELL,
            0
        );

        BondMarketFilter.BondFilter memory filter = _emptyBondFilter();
        IOrderbookMarketplace.BatchOrderInput memory input = _batchInput(3, 1, 3, filter);
        vm.prank(USER2);
        uint256 batchOrderId = orderbookMarketplace.placeBatchOrder(input);
        _settleOrderbookTrades(batchOrderId);
        IOrderbookMarketplace.Order memory remainingFirstOrder = orderbookMarketplace.getOrder(firstSellOrderId);
        if (remainingFirstOrder.trader != address(0) && remainingFirstOrder.amounts.available != 0) {
            vm.prank(USER1);
            orderbookMarketplace.cancelOrder(firstSellOrderId, address(0));
        }

        uint256 skipTokenId = secondTokenId + 1;
        _configureFuzzBond(
            skipTokenId, bytes3(bytes(BOND_CURRENCY)), issuer, BondStatus.Suspended, CouponRateType.FIXED, 1_000, 500
        );
        uint256 skipSellOrderId = _placeOrderbookOrder(
            USER1,
            skipTokenId,
            1,
            1,
            1,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.SELL,
            0
        );
        vm.prank(USER2);
        orderbookMarketplace.placeBatchOrder(_batchInput(1, 1, 1, filter));
        vm.prank(USER1);
        orderbookMarketplace.cancelOrder(skipSellOrderId, address(0));

        orderbookMarketplace.getOrder(firstSellOrderId);
        orderbookMarketplace.activeSellMarkets();
    }

    function _exerciseOrderbookOpenBookViewSurface(uint256 tokenId) internal {
        uint256 secondTokenId = tokenId + 1;
        _configureFuzzBond(
            tokenId, bytes3(bytes(BOND_CURRENCY)), issuer, BondStatus.Issued, CouponRateType.FIXED, 1_000, 500
        );
        _configureFuzzBond(
            secondTokenId, bytes3(bytes(BOND_CURRENCY)), issuer, BondStatus.Issued, CouponRateType.FIXED, 1_000, 500
        );

        uint256 buyOrderId = _placeOrderbookOrder(
            USER2,
            tokenId,
            1,
            1,
            1,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.BUY,
            0
        );
        uint256 firstSellOrderId = _placeOrderbookOrder(
            USER1,
            tokenId,
            1,
            3,
            4,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.SELL,
            0
        );
        uint256 secondSellOrderId = _placeOrderbookOrder(
            USER1,
            tokenId,
            1,
            3,
            4,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.SELL,
            0
        );
        uint256 otherMarketSellOrderId = _placeOrderbookOrder(
            USER1,
            secondTokenId,
            1,
            3,
            4,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            _emptyAddressArray(),
            IOrderbookMarketplace.OrderSide.SELL,
            0
        );

        orderbookMarketplace.getOrderBook(address(fuzzERC1155), tokenId);
        orderbookMarketplace.setOrderFrozen(buyOrderId, true, keccak256("FUZZ_BOOK_BUY_FREEZE"));
        orderbookMarketplace.getOrderBook(address(fuzzERC1155), tokenId);
        orderbookMarketplace.setOrderFrozen(buyOrderId, false, keccak256("FUZZ_BOOK_BUY_UNFREEZE"));

        vm.prank(USER2);
        orderbookMarketplace.cancelOrder(buyOrderId, address(0));
        vm.prank(USER1);
        orderbookMarketplace.cancelOrder(firstSellOrderId, address(0));
        vm.prank(USER1);
        orderbookMarketplace.cancelOrder(secondSellOrderId, address(0));
        vm.prank(USER1);
        orderbookMarketplace.cancelOrder(otherMarketSellOrderId, address(0));
    }

    function _exerciseOrderbookViews(uint256 tokenId, uint256 buyOrderId, uint256 sellOrderId, uint256 tradeId)
        internal
        view
    {
        orderbookMarketplace.getOrder(buyOrderId);
        orderbookMarketplace.getOrder(sellOrderId);
        orderbookMarketplace.getTrade(tradeId);
        orderbookMarketplace.getTradeIdsByOrderId(sellOrderId);
        orderbookMarketplace.isTraderAllowedForOrder(sellOrderId, USER2);
        orderbookMarketplace.getOrderBook(address(fuzzERC1155), tokenId);
        orderbookMarketplace.activeSellMarkets();
    }

    function _exerciseOrderbookInternalValidationCoverage(uint256 seed) internal {
        address[] memory emptyAddresses = _emptyAddressArray();
        address[] memory filterAddresses = new address[](1);
        filterAddresses[0] = USER1;

        (bool success, bytes memory returnData) = _callOrderbookCoverage(
            abi.encodeWithSelector(
                orderbookCoverage.exerciseInternalValidationSurface.selector,
                address(entityRegistry),
                address(fuzzMarketFilter),
                USER1,
                USER2,
                emptyAddresses,
                filterAddresses
            )
        );
        orderbookInternalCoveragePostconditions(success, returnData);

        seed;
    }

    function _exerciseOrderbookInternalMatchBuyCoverage(uint256 seed) internal {
        (bool success, bytes memory returnData) = _callOrderbookCoverage(
            abi.encodeWithSelector(
                orderbookCoverage.exerciseInternalMatchBuySurface.selector, address(fuzzMarketFilter), USER1, USER2
            )
        );
        orderbookInternalCoveragePostconditions(success, returnData);

        seed;
    }

    function _exerciseOrderbookInternalMatchSellCoverage(uint256 seed) internal {
        (bool success, bytes memory returnData) = _callOrderbookCoverage(
            abi.encodeWithSelector(
                orderbookCoverage.exerciseInternalMatchSellSurface.selector, address(fuzzMarketFilter), USER1, USER2
            )
        );
        orderbookInternalCoveragePostconditions(success, returnData);

        seed;
    }

    function _exerciseOrderbookInternalResidualAndBatchCoverage(uint256 seed) internal {
        IOrderbookMarketplace.BatchOrderInput memory batch = _batchInput(2, 1, 10, _emptyBondFilter());
        if (seed % 2 == 1) {
            batch.filterData = hex"ff";
        }

        (bool success, bytes memory returnData) = _callOrderbookCoverage(
            abi.encodeWithSelector(
                orderbookCoverage.exerciseInternalResidualAndBatchSurface.selector,
                address(fuzzMarketFilter),
                USER1,
                USER2,
                batch
            )
        );
        orderbookInternalCoveragePostconditions(success, returnData);
    }

    /* solhint-disable avoid-low-level-calls */
    function _callOrderbookCoverage(bytes memory callData) internal returns (bool success, bytes memory returnData) {
        (success, returnData) = address(orderbookCoverage).call(callData);
    }
    /* solhint-enable avoid-low-level-calls */

    function _placeOrderbookOrder(
        address trader,
        uint256 tokenId,
        uint256 amount,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 minMatchAmount,
        IOrderbookMarketplace.TraderFilterMode traderFilterMode,
        address[] memory traderFilterAddresses,
        IOrderbookMarketplace.OrderSide side,
        uint256 expiry
    ) internal returns (uint256 orderId) {
        if (side == IOrderbookMarketplace.OrderSide.SELL) {
            _mintAndApproveOrderbookInventory(trader, tokenId, amount);
        }

        IOrderbookMarketplace.OrderInput memory input = IOrderbookMarketplace.OrderInput({
            tokenAddress: address(fuzzERC1155),
            tokenId: tokenId,
            totalAmount: amount,
            minPrice: minPrice,
            maxPrice: maxPrice,
            minMatchAmount: minMatchAmount,
            traderFilterMode: traderFilterMode,
            traderFilterAddresses: traderFilterAddresses,
            side: side,
            expiry: expiry
        });

        vm.prank(trader);
        orderId = orderbookMarketplace.placeOrder(input, address(0));
    }

    function _placeOrderbookOrderOnBehalf(
        address delegate,
        address trader,
        uint256 tokenId,
        uint256 amount,
        uint256 minPrice,
        uint256 maxPrice
    ) internal returns (uint256 orderId) {
        _mintAndApproveOrderbookInventory(trader, tokenId, amount);

        IOrderbookMarketplace.OrderInput memory input = IOrderbookMarketplace.OrderInput({
            tokenAddress: address(fuzzERC1155),
            tokenId: tokenId,
            totalAmount: amount,
            minPrice: minPrice,
            maxPrice: maxPrice,
            minMatchAmount: 0,
            traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
            traderFilterAddresses: _emptyAddressArray(),
            side: IOrderbookMarketplace.OrderSide.SELL,
            expiry: 0
        });

        vm.prank(delegate);
        orderId = orderbookMarketplace.placeOrder(input, trader);
    }

    function _settleOrderbookTrades(uint256 orderId) internal {
        uint256[] memory tradeIds = orderbookMarketplace.getTradeIdsByOrderId(orderId);
        for (uint256 i; i < tradeIds.length; ++i) {
            uint256 tradeId = tradeIds[i];
            IOrderbookMarketplace.Trade memory trade = orderbookMarketplace.getTrade(tradeId);
            if (trade.status == IOrderbookMarketplace.TradeStatus.PENDING) {
                orderbookMarketplace.markTradePaid(tradeId);
            }
            trade = orderbookMarketplace.getTrade(tradeId);
            if (trade.status == IOrderbookMarketplace.TradeStatus.PAID) {
                orderbookMarketplace.settleTrade(tradeId);
            }
        }
    }

    function _batchInput(uint256 amount, uint256 minPrice, uint256 maxPrice, BondMarketFilter.BondFilter memory filter)
        internal
        pure
        returns (IOrderbookMarketplace.BatchOrderInput memory input)
    {
        input = IOrderbookMarketplace.BatchOrderInput({
            totalAmount: amount,
            minPrice: minPrice,
            maxPrice: maxPrice,
            minMatchAmount: 0,
            filterData: abi.encode(filter),
            traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
            traderFilterAddresses: new address[](0)
        });
    }

    function _mintAndApproveOrderbookInventory(address owner, uint256 tokenId, uint256 amount) internal {
        fuzzERC1155.mint(owner, tokenId, amount);
        vm.prank(owner);
        fuzzERC1155.setApprovalForAll(address(escrowManager), true);
    }

    function _firstTradeId(uint256 orderId) internal view returns (uint256 tradeId) {
        uint256[] memory tradeIds = orderbookMarketplace.getTradeIdsByOrderId(orderId);
        require(tradeIds.length != 0, ClampFail("no orderbook trade"));
        return tradeIds[0];
    }

    function _nextOrderbookTokenId(uint256 seed) internal returns (uint256 tokenId) {
        seed;
        orderbookTokenCursor += 100;
        tokenId = 1_000_000 + orderbookTokenCursor;
    }

    function _configureFuzzBond(
        uint256 tokenId,
        bytes3 currency,
        address bondIssuer,
        BondStatus status,
        CouponRateType couponRateType,
        uint256 bondNominalValue,
        uint256 rate
    ) internal {
        fuzzBondAdapter.configureBond(
            address(fuzzERC1155),
            tokenId,
            currency,
            bondIssuer,
            status,
            couponRateType,
            bondNominalValue,
            block.timestamp + 365 days,
            rate
        );
    }

    function _emptyBondFilter() internal pure returns (BondMarketFilter.BondFilter memory filter) {
        filter = BondMarketFilter.BondFilter({
            maturityFrom: 0,
            maturityTo: 0,
            currencyWhitelist: new bytes3[](0),
            currencyBlacklist: new bytes3[](0),
            couponRateFrom: 0,
            couponRateTo: 0,
            couponRateTypes: new CouponRateType[](0),
            issuerWhitelist: new address[](0),
            issuerBlacklist: new address[](0),
            bondNominalValueFrom: 0,
            bondNominalValueTo: 0
        });
    }

    function _exerciseBondFilterRanges(address tokenAddress, uint256 tokenId) internal {
        BondMarketFilter.BondFilter memory filter = _emptyBondFilter();
        filter.maturityFrom = block.timestamp + 400 days;
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), false
        );

        filter = _emptyBondFilter();
        filter.maturityTo = block.timestamp + 1 days;
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), false
        );

        filter = _emptyBondFilter();
        filter.bondNominalValueFrom = 2_000;
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), false
        );

        filter = _emptyBondFilter();
        filter.bondNominalValueTo = 500;
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), false
        );
    }

    function _exerciseBondFilterLists(address tokenAddress, uint256 tokenId) internal {
        BondMarketFilter.BondFilter memory filter = _emptyBondFilter();
        filter.currencyWhitelist = new bytes3[](1);
        filter.currencyWhitelist[0] = bytes3("USD");
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), false
        );

        filter.currencyWhitelist[0] = bytes3(bytes(BOND_CURRENCY));
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), true
        );

        filter = _emptyBondFilter();
        filter.currencyBlacklist = new bytes3[](1);
        filter.currencyBlacklist[0] = bytes3(bytes(BOND_CURRENCY));
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), false
        );

        filter.currencyBlacklist[0] = bytes3("USD");
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), true
        );

        filter = _emptyBondFilter();
        filter.issuerWhitelist = new address[](1);
        filter.issuerWhitelist[0] = USER2;
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), false
        );

        filter.issuerWhitelist[0] = issuer;
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), true
        );

        filter = _emptyBondFilter();
        filter.issuerBlacklist = new address[](1);
        filter.issuerBlacklist[0] = issuer;
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), false
        );

        filter.issuerBlacklist[0] = USER2;
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), true
        );
    }

    function _exerciseBondFilterCouponBranches(address tokenAddress, uint256 tokenId) internal {
        BondMarketFilter.BondFilter memory filter = _emptyBondFilter();
        filter.couponRateTypes = new CouponRateType[](1);
        filter.couponRateTypes[0] = CouponRateType.ZERO_COUPON;
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), false
        );

        filter.couponRateTypes[0] = CouponRateType.FIXED;
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), true
        );

        filter = _emptyBondFilter();
        filter.couponRateFrom = 600;
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), false
        );

        filter = _emptyBondFilter();
        filter.couponRateTo = 400;
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), false
        );

        filter = _emptyBondFilter();
        filter.couponRateFrom = 400;
        filter.couponRateTo = 600;
        bondMarketFilterMatchPostconditions(
            bondMarketFilter.matchesFilter(tokenAddress, tokenId, abi.encode(filter)), true
        );
    }

    function _exerciseBondFilterInvalidRanges(address tokenAddress, uint256 tokenId) internal {
        BondMarketFilter.BondFilter memory filter = _emptyBondFilter();
        filter.maturityFrom = 2;
        filter.maturityTo = 1;
        _expectBondMarketFilterRevert(
            address(bondMarketFilter),
            abi.encodeWithSelector(bondMarketFilter.matchesFilter.selector, tokenAddress, tokenId, abi.encode(filter)),
            Errors.BondMarketFilter__InvalidFilterRange.selector
        );

        filter = _emptyBondFilter();
        filter.couponRateFrom = 2;
        filter.couponRateTo = 1;
        _expectBondMarketFilterRevert(
            address(bondMarketFilter),
            abi.encodeWithSelector(bondMarketFilter.matchesFilter.selector, tokenAddress, tokenId, abi.encode(filter)),
            Errors.BondMarketFilter__InvalidFilterRange.selector
        );

        filter = _emptyBondFilter();
        filter.bondNominalValueFrom = 2;
        filter.bondNominalValueTo = 1;
        _expectBondMarketFilterRevert(
            address(bondMarketFilter),
            abi.encodeWithSelector(bondMarketFilter.matchesFilter.selector, tokenAddress, tokenId, abi.encode(filter)),
            Errors.BondMarketFilter__InvalidFilterRange.selector
        );
    }

    function _expectOrderbookRevert(address target, bytes memory callData, bytes4 expectedSelector) internal {
        (bool success, bytes memory returnData) = fl.doFunctionCall(target, callData, address(this));
        orderbookExpectedRevertPostconditions(success, returnData, expectedSelector);
    }

    function _expectBondMarketFilterRevert(address target, bytes memory callData, bytes4 expectedSelector) internal {
        (bool success, bytes memory returnData) = fl.doFunctionCall(target, callData, address(this));
        bondMarketFilterInvalidRangePostconditions(success, returnData, expectedSelector);
    }

    function _expectMarketplaceCoverageRevert(address target, bytes memory callData, bytes4 expectedSelector) internal {
        (bool success, bytes memory returnData) = fl.doFunctionCall(target, callData, address(this));
        marketplaceDefensiveBranchPostconditions(success, returnData, expectedSelector);
    }

    function _expectEscrowManagerCoverageRevert(address target, bytes memory callData, bytes4 expectedSelector)
        internal
    {
        (bool success, bytes memory returnData) = fl.doFunctionCall(target, callData, address(this));
        escrowManagerInvalidAssetCoveragePostconditions(success, returnData, expectedSelector);
    }
}
