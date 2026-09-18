// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Create2Deployer} from "../base/Create2Deployer.sol";
import {EscrowManager} from "../../marketplace/EscrowManager.sol";

// slither-disable-start too-many-digits
/**
 * @title EscrowManagerDeployer
 * @author DEUSS Team
 * @notice EscrowManagerDeployer is responsible for deploying the Escrow Manager contract.
 */
contract EscrowManagerDeployer is Create2Deployer {
    /// @notice The Escrow Manager contract
    EscrowManager public immutable escrowManager;

    /**
     * @notice Constructor to deploy Escrow Manager via CREATE2
     * @param owner Temporary owner of EscrowManager during bootstrap
     * @param marketplace The Marketplace contract address (optional)
     * @param orderbookMarketplace The Orderbook Marketplace contract address (optional)
     * @param escrowManagerSalt A unique value to ensure unique deployment address
     */
    constructor(address owner, address marketplace, address orderbookMarketplace, string memory escrowManagerSalt) {
        // deploy Escrow Manager Implementation contract
        address escrowManagerImpl =
            _deployImplementationViaCreate2(escrowManagerSalt, type(EscrowManager).creationCode, bytes(""));
        // deploy Escrow Manager Beacon contract
        address escrowManagerBeacon = _deployBeaconViaCreate2(escrowManagerSalt, escrowManagerImpl, owner);
        // deploy Escrow Manager Proxy contract
        bytes memory escrowManagerInitData =
            abi.encodeWithSelector(EscrowManager.initialize.selector, owner, marketplace, orderbookMarketplace);
        escrowManager =
            EscrowManager(_deployBeaconProxyViaCreate2(escrowManagerSalt, escrowManagerBeacon, escrowManagerInitData));
    }
}
// slither-disable-end too-many-digits
