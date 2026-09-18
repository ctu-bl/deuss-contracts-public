// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Bond} from "../../../registry/BondStructs.sol";

/**
 * @title IBondMetadataAdapter
 * @author DEUSS Team
 * @notice Normalizes heterogeneous bond metadata sources into the DEUSS Bond shape for consumption by BondMarketFilter.
 *         Adapters let new issuers or third-party registries be plugged in without touching the filter or the
 *         marketplace. Implementations must revert when the (token, tokenId) pair is not known so BondMarketFilter
 *         can fall back via try/catch.
 */
interface IBondMetadataAdapter {
    /**
     * @notice Returns the latest Bond record for the given token/tokenId
     * @param token Token contract address
     * @param tokenId Token identifier
     * @return bond Normalized bond metadata
     */
    function getBond(address token, uint256 tokenId) external view returns (Bond memory bond);

    /**
     * @notice Returns the coupon rate applicable to the supplied bond at the current block timestamp
     * @param bond Bond record previously returned by getBond
     * @return rate Current coupon rate (0 for ZERO_COUPON bonds or before the first checkpoint)
     */
    function getCurrentCouponRate(Bond calldata bond) external view returns (uint256 rate);
}
