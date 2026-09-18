// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Create2Deployer} from "../base/Create2Deployer.sol";
import {AssetManager} from "../../marketplace/AssetManager.sol";

// slither-disable-start too-many-digits
/**
 * @title AssetManagerDeployer
 * @author DEUSS Team
 * @notice AssetManagerDeployer is responsible for deploying the Asset Manager contract.
 */
contract AssetManagerDeployer is Create2Deployer {
    /// @notice The Asset Manager contract
    AssetManager public immutable assetManager;

    /**
     * @notice Constructor to deploy Asset Manager via CREATE2
     * @param owner Temporary owner of AssetManager during bootstrap
     * @param assetManagerSalt A unique value to ensure unique deployment address
     */
    constructor(address owner, string memory assetManagerSalt) {
        // deploy Asset Manager Implementation contract
        address assetManagerImpl =
            _deployImplementationViaCreate2(assetManagerSalt, type(AssetManager).creationCode, bytes(""));
        // deploy Asset Manager Beacon contract
        address assetManagerBeacon = _deployBeaconViaCreate2(assetManagerSalt, assetManagerImpl, owner);
        // deploy Asset Manager Proxy contract
        bytes memory assetManagerInitData = abi.encodeWithSelector(AssetManager.initialize.selector, owner);
        assetManager =
            AssetManager(_deployBeaconProxyViaCreate2(assetManagerSalt, assetManagerBeacon, assetManagerInitData));
    }
}
// slither-disable-end too-many-digits
