// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {BondRegistry} from "../../registry/BondRegistry.sol";
import {Create2Deployer} from "../base/Create2Deployer.sol";

// slither-disable-start too-many-digits
/**
 * @title BRDeployer
 * @author DEUSS Team
 * @notice BRDeployer is responsible for deploying the Bond Registry related contracts.
 */
contract BRDeployer is Create2Deployer {
    /// @notice The Bond Registry contract
    BondRegistry public immutable bondRegistry;

    /**
     * @notice Constructor to deploy Bond Registry via CREATE2
     * @param owner Temporary owner of BondRegistry during bootstrap
     * @param brSalt A unique value to ensure unique deployment addresses
     */
    constructor(address owner, string memory brSalt) {
        // deploy Bond Registry Implementation contract
        address brImpl = _deployImplementationViaCreate2(brSalt, type(BondRegistry).creationCode, bytes(""));
        // deploy Bond Registry Beacon contract
        address brBeacon = _deployBeaconViaCreate2(brSalt, brImpl, owner);
        // deploy Bond Registry Proxy contract and initialize it
        bondRegistry = BondRegistry(
            _deployBeaconProxyViaCreate2(
                brSalt, brBeacon, abi.encodeWithSelector(BondRegistry.initialize.selector, owner)
            )
        );
    }
}
// slither-disable-end too-many-digits
