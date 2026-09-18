// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {DEUSSToken} from "../../token/fungible/DEUSSToken.sol";
import {Create2Deployer} from "../base/Create2Deployer.sol";

// slither-disable-start too-many-digits
/**
 * @title TokenDeployer
 * @author DEUSS Team
 * @notice TokenDeployer is responsible for deploying the DEUSSToken contract.
 */
contract TokenDeployer is Create2Deployer {
    /// @notice The Token contract
    DEUSSToken public immutable token;

    /**
     * @notice Constructor to deploy Token via CREATE2
     * @param owner Temporary owner of token contract during bootstrap
     * @param bondRegistry The BondRegistry contract address
     * @param entityRegistry The EntityRegistry contract address
     * @param escrowManager The EscrowManager custody address to protect during initialization
     * @param tokenSalt A unique value to ensure unique deployment addresses
     */
    constructor(
        address owner,
        address bondRegistry,
        address entityRegistry,
        address escrowManager,
        string memory tokenSalt
    ) {
        // deploy Token Implementation contract
        address tokenImpl = _deployImplementationViaCreate2(tokenSalt, type(DEUSSToken).creationCode, bytes(""));
        // deploy Token Beacon contract
        address tokenBeacon = _deployBeaconViaCreate2(tokenSalt, tokenImpl, owner);
        // deploy Token Proxy contract and initialize it
        token = DEUSSToken(
            _deployBeaconProxyViaCreate2(
                tokenSalt,
                tokenBeacon,
                abi.encodeWithSelector(
                    DEUSSToken.initialize.selector, owner, bondRegistry, entityRegistry, escrowManager
                )
            )
        );
    }
}
// slither-disable-end too-many-digits
