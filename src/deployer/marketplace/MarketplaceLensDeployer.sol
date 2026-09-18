// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Create2Deployer} from "../base/Create2Deployer.sol";
import {Errors} from "../../libs/Errors.sol";
import {MarketplaceLens} from "../../marketplace/lens/MarketplaceLens.sol";

/**
 * @title MarketplaceLensDeployer
 * @author DEUSS Team
 * @notice Deploys the MarketplaceLens implementation, beacon, and beacon proxy via CREATE2
 */
contract MarketplaceLensDeployer is Create2Deployer {
    /// @notice The MarketplaceLens proxy contract
    MarketplaceLens public immutable marketplaceLens;

    /**
     * @notice Constructor to deploy MarketplaceLens via CREATE2
     * @param owner Temporary owner of MarketplaceLens during bootstrap
     * @param marketplace The Marketplace proxy address read by the lens
     * @param marketplaceLensSalt A unique value to ensure unique deployment address
     */
    constructor(address owner, address marketplace, string memory marketplaceLensSalt) {
        require(owner != address(0), Errors.ZeroAddress());
        require(marketplace != address(0), Errors.ZeroAddress());

        address marketplaceLensImpl =
            _deployImplementationViaCreate2(marketplaceLensSalt, type(MarketplaceLens).creationCode, bytes(""));
        address marketplaceLensBeacon = _deployBeaconViaCreate2(marketplaceLensSalt, marketplaceLensImpl, owner);

        bytes memory marketplaceLensInitData =
            abi.encodeWithSelector(MarketplaceLens.initialize.selector, owner, marketplace);

        marketplaceLens = MarketplaceLens(
            _deployBeaconProxyViaCreate2(marketplaceLensSalt, marketplaceLensBeacon, marketplaceLensInitData)
        );
    }
}
