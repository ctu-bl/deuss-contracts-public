// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {
    TimelockControllerUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {TimelockController} from "src/governance/TimelockController.sol";
import {Create2Deployer} from "../base/Create2Deployer.sol";

// slither-disable-start too-many-digits
/**
 * @title TimelockControllerDeployer
 * @author DEUSS Team
 * @notice TimelockControllerDeployer is responsible for deploying the Timelock controller contract.
 */
contract TimelockControllerDeployer is Create2Deployer {
    /// @notice The TimelockController contract
    TimelockControllerUpgradeable public immutable timelockController;

    /**
     * @notice Constructor to deploy TimelockController implementation, Beacon, and BeaconProxy via CREATE2
     * @param initialMinDelay The minimum delay in seconds for timelock operations
     * @param proposers Accounts granted PROPOSER_ROLE (can propose operations)
     * @param executors Accounts granted EXECUTOR_ROLE (can execute ready operations)
     * @param initialAdmin The account granted ADMIN_ROLE (can manage roles without delay); use address(0) to skip
     * @param timelockControllerSalt A unique value to ensure unique CREATE2 deployment addresses
     */
    constructor(
        uint256 initialMinDelay,
        address[] memory proposers,
        address[] memory executors,
        address initialAdmin,
        string memory timelockControllerSalt
    ) {
        // deploy TimelockController Implementation contract
        address timelockControllerImpl =
            _deployImplementationViaCreate2(timelockControllerSalt, type(TimelockController).creationCode, bytes(""));
        // deploy TimelockController Beacon contract
        address timelockControllerBeacon =
            _deployBeaconViaCreate2(timelockControllerSalt, timelockControllerImpl, address(this));
        // deploy TimelockController Proxy contract and initialize it
        timelockController = TimelockControllerUpgradeable(
            payable(_deployBeaconProxyViaCreate2(
                    timelockControllerSalt,
                    timelockControllerBeacon,
                    abi.encodeWithSelector(
                        TimelockControllerUpgradeable.initialize.selector,
                        initialMinDelay,
                        proposers,
                        executors,
                        initialAdmin
                    )
                ))
        );
        // transfer beacon ownership to the deployed timelock so upgrades go through governance
        UpgradeableBeacon(timelockControllerBeacon).transferOwnership(address(timelockController));
    }
}
// slither-disable-end too-many-digits
