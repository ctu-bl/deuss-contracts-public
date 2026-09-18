// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {PolicyRegistry} from "src/registry/PolicyRegistry.sol";
import {Create2Deployer} from "../base/Create2Deployer.sol";

/**
 * @title PolicyRegistryDeployer
 * @author DEUSS Team
 * @notice Deploys the wallet PolicyRegistry via CREATE2.
 */
contract PolicyRegistryDeployer is Create2Deployer {
    /// @notice The deployed PolicyRegistry contract.
    PolicyRegistry public immutable policyRegistry;

    /**
     * @notice Deploys PolicyRegistry via CREATE2.
     * @param owner Temporary owner of PolicyRegistry during bootstrap
     * @param policyRegistrySalt A unique value to ensure unique deployment addresses.
     */
    constructor(address owner, string memory policyRegistrySalt) {
        address policyRegistryImpl =
            _deployImplementationViaCreate2(policyRegistrySalt, type(PolicyRegistry).creationCode, bytes(""));
        address policyRegistryBeacon = _deployBeaconViaCreate2(policyRegistrySalt, policyRegistryImpl, owner);
        policyRegistry = PolicyRegistry(
            _deployBeaconProxyViaCreate2(
                policyRegistrySalt,
                policyRegistryBeacon,
                abi.encodeWithSelector(PolicyRegistry.initialize.selector, owner)
            )
        );
    }
}
