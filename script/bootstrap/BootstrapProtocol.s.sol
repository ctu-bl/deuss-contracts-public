// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BootstrapBase} from "./BootstrapBase.s.sol";
import {DeploymentArtifacts} from "../lib/DeploymentArtifacts.s.sol";
import {Suite} from "../DeployTypes.sol";
import {SetupEBSIInfrastructure} from "../SetupEBSIInfrastructure.s.sol";

/**
 * @title BootstrapProtocol
 * @author DEUSS Team
 * @notice Operator-facing bootstrap script.
 *         Reads the deployment JSON written by DeployProtocol, then applies all
 *         required protocol wiring and minimal environment setup via BootstrapBase.
 *         On the first successful run it also hands contract ownership to the
 *         TimelockController, so subsequent reruns require the current owner to
 *         execute any remaining owner-gated steps.
 */
contract BootstrapProtocol is BootstrapBase, DeploymentArtifacts {
    /**
     * @notice Load deployment addresses and apply bootstrap to the deployed suite.
     * @return suite Populated Suite with all deployed contract addresses
     */
    function run() public override returns (Suite memory suite) {
        ebsiInfrastructure = new SetupEBSIInfrastructure();
        _initAddresses();
        suite = _loadSuiteFromManifest();
        timelockController = payable(suite.governance.timelockController);
        applyBootstrap(suite);
        transferOwnershipToTimelock(suite);
    }
}
