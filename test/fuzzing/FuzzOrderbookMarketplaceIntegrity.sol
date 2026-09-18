// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {FuzzIntegrityBase} from "./FuzzIntegrityBase.sol";
import {HandlerOrderbookMarketplace} from "./helper/handlers/HandlerOrderbookMarketplace.sol";

/**
 * @title FuzzOrderbookMarketplaceIntegrity
 * @notice Checks directed coverage handlers for OrderbookMarketplace and BondMarketFilter.
 */
contract FuzzOrderbookMarketplaceIntegrity is HandlerOrderbookMarketplace, FuzzIntegrityBase {
    /**
     * @notice Checks BondMarketFilter adapter and predicate coverage.
     * @param seed Seed used to derive isolated fuzz token ids.
     */
    function fuzz_bondMarketFilterSurface(uint256 seed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerOrderbookMarketplace.handler_bondMarketFilterSurface.selector, seed);

        _runOrderbookSurface(callData, "SELF-BOND-MARKET-FILTER");
    }

    /**
     * @notice Checks OrderbookMarketplace admin, cancellation, and delegation surfaces.
     * @param seed Seed used to derive isolated fuzz token ids.
     */
    function fuzz_orderbookMarketplaceSurface(uint256 seed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerOrderbookMarketplace.handler_orderbookMarketplaceSurface.selector, seed);

        _runOrderbookSurface(callData, "SELF-ORDERBOOK-SURFACE");
    }

    /**
     * @notice Checks OrderbookMarketplace matching, payment, dispute, settlement, TWAP, and view surfaces.
     * @param seed Seed used to derive isolated fuzz token ids.
     */
    function fuzz_orderbookMarketplaceTradeSurface(uint256 seed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerOrderbookMarketplace.handler_orderbookMarketplaceTradeSurface.selector, seed);

        _runOrderbookSurface(callData, "SELF-ORDERBOOK-TRADE");
    }

    /**
     * @notice Checks OrderbookMarketplace freeze and seizure surfaces.
     * @param seed Seed used to derive isolated fuzz token ids.
     */
    function fuzz_orderbookMarketplaceFreezeSeizureSurface(uint256 seed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerOrderbookMarketplace.handler_orderbookMarketplaceFreezeSeizureSurface.selector, seed
        );

        _runOrderbookSurface(callData, "SELF-ORDERBOOK-FREEZE-SEIZE");
    }

    /**
     * @notice Checks OrderbookMarketplace batch order and active-market surfaces.
     * @param seed Seed used to derive isolated fuzz token ids.
     */
    function fuzz_orderbookMarketplaceBatchSurface(uint256 seed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerOrderbookMarketplace.handler_orderbookMarketplaceBatchSurface.selector, seed);

        _runOrderbookSurface(callData, "SELF-ORDERBOOK-BATCH");
    }

    /**
     * @notice Checks OrderbookMarketplace order book view surfaces.
     * @param seed Seed used to derive isolated fuzz token ids.
     */
    function fuzz_orderbookMarketplaceOpenBookViewSurface(uint256 seed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerOrderbookMarketplace.handler_orderbookMarketplaceOpenBookViewSurface.selector, seed
        );

        _runOrderbookSurface(callData, "SELF-ORDERBOOK-OPEN-BOOK");
    }

    /**
     * @notice Checks isolated OrderbookMarketplace internal validation, filter, order creation, and TWAP branches.
     * @param seed Seed used by the internal coverage harness.
     */
    function fuzz_orderbookMarketplaceInternalValidationSurface(uint256 seed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerOrderbookMarketplace.handler_orderbookMarketplaceInternalValidationSurface.selector, seed
        );

        _runOrderbookSurface(callData, "OB-INT-VALIDATION");
    }

    /**
     * @notice Checks isolated OrderbookMarketplace internal buy-order matching branches.
     * @param seed Seed used by the internal coverage harness.
     */
    function fuzz_orderbookMarketplaceInternalMatchBuySurface(uint256 seed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerOrderbookMarketplace.handler_orderbookMarketplaceInternalMatchBuySurface.selector, seed
        );

        _runOrderbookSurface(callData, "OB-INT-MATCH-BUY");
    }

    /**
     * @notice Checks isolated OrderbookMarketplace internal sell-order matching branches.
     * @param seed Seed used by the internal coverage harness.
     */
    function fuzz_orderbookMarketplaceInternalMatchSellSurface(uint256 seed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerOrderbookMarketplace.handler_orderbookMarketplaceInternalMatchSellSurface.selector, seed
        );

        _runOrderbookSurface(callData, "OB-INT-MATCH-SELL");
    }

    /**
     * @notice Checks isolated OrderbookMarketplace internal residual matching and batch-market branches.
     * @param seed Seed used by the internal coverage harness.
     */
    function fuzz_orderbookMarketplaceInternalResidualAndBatchSurface(uint256 seed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerOrderbookMarketplace.handler_orderbookMarketplaceInternalResidualAndBatchSurface.selector, seed
        );

        _runOrderbookSurface(callData, "OB-INT-RESIDUAL-BATCH");
    }

    /**
     * @notice Checks residual Marketplace and EscrowManager defensive branches.
     */
    function fuzz_marketplaceEscrowResidualSurface() public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerOrderbookMarketplace.handler_marketplaceEscrowResidualSurface.selector);

        _runOrderbookSurface(callData, "SELF-MKT-ESCROW-RESIDUAL");
    }

    function _runOrderbookSurface(bytes memory callData, string memory context) internal {
        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, context);
        }
    }
}
