// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {WalletFactory} from "src/wallet/WalletFactory.sol";
import {Create2Deployer} from "../base/Create2Deployer.sol";

/**
 * @title WalletFactoryDeployer
 * @author DEUSS Team
 * @notice WalletFactoryDeployer is responsible for deploying the WalletFactory contract.
 */
contract WalletFactoryDeployer is Create2Deployer {
    /// @notice The WalletFactory contract
    WalletFactory public immutable walletFactory;

    /**
     * @notice Constructor to deploy WalletFactory implementation and proxy via CREATE2.
     * @param entityRegistry Address of EntityRegistry bound to WalletFactory
     * @param owner Temporary owner of WalletFactory during bootstrap.
     * @param walletFactorySalt A unique value to ensure unique deployment addresses.
     */
    constructor(address entityRegistry, address owner, string memory walletFactorySalt) {
        address walletFactoryImpl =
            _deployImplementationViaCreate2(walletFactorySalt, type(WalletFactory).creationCode, bytes(""));
        address walletFactoryBeacon = _deployBeaconViaCreate2(walletFactorySalt, walletFactoryImpl, owner);
        walletFactory = WalletFactory(
            _deployBeaconProxyViaCreate2(
                walletFactorySalt,
                walletFactoryBeacon,
                abi.encodeWithSelector(WalletFactory.initialize.selector, entityRegistry, owner)
            )
        );
    }
}
