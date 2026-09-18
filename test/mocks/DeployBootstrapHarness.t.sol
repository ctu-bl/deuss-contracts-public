// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BootstrapBase} from "script/bootstrap/BootstrapBase.s.sol";
import {Suite} from "script/DeployTypes.sol";

/**
 * @title DeployBootstrapHarness
 * @notice Shared test harness that combines DeployProtocol and BootstrapBase into
 *         a single deployable contract for use in tests and integration scenarios.
 */
contract DeployBootstrapHarness is BootstrapBase {
    /**
     * @notice Deploy all contracts and immediately apply bootstrap wiring.
     * @return suite Fully deployed and wired suite
     */
    function deploySuite() public returns (Suite memory suite) {
        _initAddresses();
        suite = _deploySuiteContracts();
        applyBootstrap(suite);
        transferOwnershipToTimelock(suite);
    }

    /**
     * @notice Deploy all contracts without applying bootstrap wiring.
     * @return suite Struct with all deployed addresses; core modules are unlinked.
     */
    function deployOnly() public returns (Suite memory suite) {
        _initAddresses();
        return _deploySuiteContracts();
    }

    /**
     * @notice Override the deployer key for subsequent script-side operations.
     * @dev Test-only helper used to simulate reruns where the original deployer can
     *      no longer administer the EBSI contracts.
     * @param deployerKey_ Replacement deployer private key
     */
    function setDeployerKey(uint256 deployerKey_) external {
        _activeNetworkConfig.deployerKey = deployerKey_;
    }
}
