// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore */

import {PostconditionsBase} from "./PostconditionsBase.sol";

/// @title PostconditionsOrderbookMarketplace
/// @notice Postcondition dispatch for directed OrderbookMarketplace and BondMarketFilter surfaces.
abstract contract PostconditionsOrderbookMarketplace is PostconditionsBase {
    function bondMarketFilterAdapterPostconditions(address actualAdapter, address expectedAdapter) internal {
        invariant_BMF_10(actualAdapter, expectedAdapter);
    }

    function bondMarketFilterMatchPostconditions(bool actualMatch, bool expectedMatch) internal {
        invariant_BMF_20(actualMatch, expectedMatch);
    }

    function bondMarketFilterInvalidRangePostconditions(bool success, bytes memory returnData, bytes4 expectedSelector)
        internal
    {
        invariant_BMF_30(success, _returnSelector(returnData), expectedSelector);
    }

    function escrowManagerERC721BalanceCoveragePostconditions(uint256 actualBalance) internal {
        invariant_ESCR_71(actualBalance);
    }

    function escrowManagerInvalidAssetCoveragePostconditions(
        bool success,
        bytes memory returnData,
        bytes4 expectedSelector
    ) internal {
        invariant_ESCR_72(success, _returnSelector(returnData), expectedSelector);
    }

    function marketplaceDefensiveBranchPostconditions(bool success, bytes memory returnData, bytes4 expectedSelector)
        internal
    {
        invariant_MKT_82(success, _returnSelector(returnData), expectedSelector);
    }

    function orderbookAdminSurfacePostconditions() internal {
        invariant_OB_10(orderbookMarketplace.assetManager(), address(assetManager));
        invariant_OB_10(orderbookMarketplace.entityRegistry(), address(entityRegistry));
        invariant_OB_10(orderbookMarketplace.escrowManager(), address(escrowManager));
        invariant_OB_10(orderbookMarketplace.marketFilter(), address(bondMarketFilter));
        invariant_OB_11(orderbookMarketplace.paymentExpiryThreshold(), PAYMENT_EXPIRY_THRESHOLD);
        invariant_OB_11(orderbookMarketplace.minExpiryThreshold(), ORDERBOOK_MIN_EXPIRY_THRESHOLD);
        invariant_OB_11(orderbookMarketplace.disputeBufferPeriod(), DISPUTE_BUFFER_PERIOD);
        invariant_OB_11(uint256(orderbookMarketplace.MAX_RECENT_OBSERVATIONS()), 256);
    }

    function orderbookDelegatePostconditions(bool success, bytes memory returnData) internal {
        invariant_OB_12(success, _returnSelector(returnData));
    }

    function orderbookExpectedRevertPostconditions(bool success, bytes memory returnData, bytes4 expectedSelector)
        internal
    {
        invariant_OB_13(success, _returnSelector(returnData), expectedSelector);
    }

    function orderbookInternalCoveragePostconditions(bool success, bytes memory returnData) internal {
        invariant_OB_14(success, _returnSelector(returnData));
    }
}
