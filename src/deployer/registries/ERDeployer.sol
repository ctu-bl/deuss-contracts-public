// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {EntityRegistry} from "src/registry/EntityRegistry.sol";
import {Create2Deployer} from "../base/Create2Deployer.sol";

/**
 * @title ERDeployer
 * @author DEUSS Team
 * @notice ERDeployer is responsible for deploying the EntityRegistry contracts.
 */
contract ERDeployer is Create2Deployer {
    /// @notice The EntityRegistry contract
    EntityRegistry public immutable entityRegistry;

    /**
     * @notice Constructor that deploys the EntityRegistry implementation and proxy contracts
     * @param owner Temporary owner of EntityRegistry during bootstrap
     * @param erSalt A unique value to ensure unique deployment addresses
     */
    constructor(address owner, string memory erSalt) {
        // deploy EntityRegistry implementation contract
        address erImpl = _deployImplementationViaCreate2(erSalt, type(EntityRegistry).creationCode, bytes(""));
        // deploy EntityRegistry beacon contract
        address erBeacon = _deployBeaconViaCreate2(erSalt, erImpl, owner);
        // deploy EntityRegistry proxy contract and initialize it
        entityRegistry = EntityRegistry(
            _deployBeaconProxyViaCreate2(
                erSalt, erBeacon, abi.encodeWithSelector(EntityRegistry.initialize.selector, owner)
            )
        );
    }
}
