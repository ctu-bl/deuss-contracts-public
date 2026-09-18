// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Create2Deployer} from "../base/Create2Deployer.sol";
import {Marketplace} from "../../marketplace/Marketplace.sol";

// slither-disable-start too-many-digits
/**
 * @title MarketplaceDeployer
 * @author DEUSS Team
 * @notice MarketplaceDeployer is responsible for deploying the Escrow contracts (Marketplace, Escrow, and Oracle).
 */
contract MarketplaceDeployer is Create2Deployer {
    /// @notice The Marketplace contract
    Marketplace public immutable marketplace;

    /// @notice Parameters required to deploy and initialize Marketplace
    struct MarketplaceDeployParams {
        address owner;
        uint256 offerExpiryThreshold;
        uint256 maxOfferLifetime;
        uint256 marketplacePaymentExpiryThreshold;
        uint256 redemptionPaymentExpiryThreshold;
        uint256 interestDiscoveryPaymentExpiryThreshold;
        uint256 disputeBufferPeriod;
        address assetManager;
        address escrowManager;
        address entityRegistry;
        uint256 maxCounterOffers;
        string marketplaceSalt;
    }

    /**
     * @notice Constructor to deploy Marketplace via CREATE2
     * @param params Marketplace deployment and initialization parameters
     */
    constructor(MarketplaceDeployParams memory params) {
        address marketplaceBeacon = _deployMarketplaceBeacon(params.marketplaceSalt, params.owner);
        bytes memory marketplaceInitData = _encodeMarketplaceInitData(params);

        marketplace =
            Marketplace(_deployBeaconProxyViaCreate2(params.marketplaceSalt, marketplaceBeacon, marketplaceInitData));
    }

    /**
     * @notice Deploy Marketplace implementation and beacon via CREATE2
     * @param marketplaceSalt A unique value to ensure unique deployment address
     * @param owner Temporary owner of Marketplace during bootstrap
     * @return marketplaceBeacon Marketplace beacon address
     */
    function _deployMarketplaceBeacon(string memory marketplaceSalt, address owner)
        private
        returns (address marketplaceBeacon)
    {
        address marketplaceImpl =
            _deployImplementationViaCreate2(marketplaceSalt, type(Marketplace).creationCode, bytes(""));

        marketplaceBeacon = _deployBeaconViaCreate2(marketplaceSalt, marketplaceImpl, owner);
    }

    /**
     * @notice Encode Marketplace initializer data
     * @param params Marketplace deployment and initialization parameters
     * @return marketplaceInitData Encoded Marketplace initializer call
     */
    function _encodeMarketplaceInitData(MarketplaceDeployParams memory params)
        private
        pure
        returns (bytes memory marketplaceInitData)
    {
        marketplaceInitData = abi.encodeWithSelector(
            Marketplace.initialize.selector,
            params.owner,
            params.offerExpiryThreshold,
            params.maxOfferLifetime,
            params.marketplacePaymentExpiryThreshold,
            params.redemptionPaymentExpiryThreshold,
            params.interestDiscoveryPaymentExpiryThreshold,
            params.disputeBufferPeriod,
            params.assetManager,
            params.escrowManager,
            params.entityRegistry,
            params.maxCounterOffers
        );
    }
}
// slither-disable-end too-many-digits
