// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {SetupEBSIInfrastructure} from "./SetupEBSIInfrastructure.s.sol";
import {EBSIContracts} from "./DeployTypes.sol";

/**
 * @title DeployEBSI
 * @author DEUSS Team
 * @notice Standalone script to deploy EBSI infrastructure only
 * @dev Thin wrapper around SetupEBSIInfrastructure for standalone EBSI deployment
 *      Used by Makefile's `make deploy_ebsi` target
 */
contract DeployEBSI is SetupEBSIInfrastructure {
    /**
     * @notice Run standalone EBSI deployment
     * @return ebsi Struct containing all deployed EBSI contract addresses
     */
    function run() public returns (EBSIContracts memory ebsi) {
        ebsi = setupEBSI();
        saveEBSIDeploymentToJson(ebsi);
        return ebsi;
    }
}
