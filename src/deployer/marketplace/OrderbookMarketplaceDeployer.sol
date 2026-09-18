// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Create2Deployer} from "../base/Create2Deployer.sol";
import {OrderbookMarketplace} from "../../marketplace/OrderbookMarketplace.sol";

// slither-disable-start too-many-digits
/**
 * @title OrderbookMarketplaceDeployer
 * @author DEUSS Team
 * @notice OrderbookMarketplaceDeployer is responsible for deploying the Orderbook Marketplace contract.
 */
contract OrderbookMarketplaceDeployer is Create2Deployer {
    /// @notice The Orderbook Marketplace contract
    OrderbookMarketplace public immutable orderbookMarketplace;

    /**
     * @notice Constructor to deploy Orderbook Marketplace via CREATE2
     * @param owner Temporary owner of OrderBook during bootstrap
     * @param assetManager The Asset Manager contract address
     * @param entityRegistry The Company Wallet Registry contract address
     * @param escrowManager The Escrow Manager contract address
     * @param paymentExpiryThreshold The payment expiry threshold in seconds
     * @param minExpiryThreshold The minimum required order expiry duration in seconds
     * @param disputeBufferPeriod The dispute buffer period in seconds
     * @param marketFilter The IMarketFilter resolver address
     * @param orderbookMarketplaceSalt A unique value to ensure unique deployment address
     */
    constructor(
        address owner,
        address assetManager,
        address entityRegistry,
        address escrowManager,
        uint256 paymentExpiryThreshold,
        uint256 minExpiryThreshold,
        uint256 disputeBufferPeriod,
        address marketFilter,
        string memory orderbookMarketplaceSalt
    ) {
        // deploy Orderbook Marketplace Implementation contract
        address orderbookMarketplaceImpl = _deployImplementationViaCreate2(
            orderbookMarketplaceSalt, type(OrderbookMarketplace).creationCode, bytes("")
        );
        // deploy Orderbook Marketplace Beacon contract
        address orderbookMarketplaceBeacon =
            _deployBeaconViaCreate2(orderbookMarketplaceSalt, orderbookMarketplaceImpl, owner);
        // deploy Orderbook Marketplace Proxy contract
        bytes memory orderbookMarketplaceInitData = abi.encodeWithSelector(
            OrderbookMarketplace.initialize.selector,
            owner,
            assetManager,
            entityRegistry,
            escrowManager,
            paymentExpiryThreshold,
            minExpiryThreshold,
            disputeBufferPeriod,
            marketFilter
        );
        orderbookMarketplace = OrderbookMarketplace(
            _deployBeaconProxyViaCreate2(
                orderbookMarketplaceSalt, orderbookMarketplaceBeacon, orderbookMarketplaceInitData
            )
        );
    }
}
// slither-disable-end too-many-digits
