// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Create2Deployer} from "../base/Create2Deployer.sol";
import {BondMarketFilter} from "../../marketplace/filters/BondMarketFilter.sol";

// slither-disable-start too-many-digits
/**
 * @title BondMarketFilterDeployer
 * @author DEUSS Team
 * @notice Deploys the BondMarketFilter resolver via CREATE2 behind an UpgradeableBeacon proxy.
 *         Adapters are registered post-deploy via BondMarketFilter.setAdapter by the governance address.
 */
contract BondMarketFilterDeployer is Create2Deployer {
    /// @notice The deployed BondMarketFilter contract
    BondMarketFilter public immutable bondMarketFilter;

    /**
     * @notice Constructor to deploy BondMarketFilter via CREATE2
     * @param governance The governance address (owner + ADMIN operator for adapter management)
     * @param bondMarketFilterSalt A unique value to ensure unique deployment address
     */
    constructor(address governance, string memory bondMarketFilterSalt) {
        address impl =
            _deployImplementationViaCreate2(bondMarketFilterSalt, type(BondMarketFilter).creationCode, bytes(""));
        address beacon = _deployBeaconViaCreate2(bondMarketFilterSalt, impl, governance);
        bytes memory initData = abi.encodeWithSelector(BondMarketFilter.initialize.selector, governance);
        bondMarketFilter = BondMarketFilter(_deployBeaconProxyViaCreate2(bondMarketFilterSalt, beacon, initData));
    }
}
// slither-disable-end too-many-digits
