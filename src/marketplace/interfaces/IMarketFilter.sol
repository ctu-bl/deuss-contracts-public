// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

/**
 * @title IMarketFilter
 * @author DEUSS Team
 * @notice Pluggable resolver used by OrderbookMarketplace to evaluate batch-order filters against candidate markets.
 *         Filter payload is opaque bytes; each concrete resolver defines its own encoding (e.g. BondMarketFilter
 *         decodes as BondFilter). Implementations must return false (not revert) for tokens they do not recognize
 *         so the marketplace can transparently skip non-matching markets.
 */
interface IMarketFilter {
    /**
     * @notice Returns whether the given (token, tokenId) market satisfies the caller-supplied filter
     * @param token Token contract address of the market
     * @param tokenId Token identifier of the market
     * @param filterData ABI-encoded filter payload (resolver-specific)
     * @return matches True if the market satisfies every filter clause, false otherwise
     */
    function matchesFilter(address token, uint256 tokenId, bytes calldata filterData)
        external
        view
        returns (bool matches);
}
