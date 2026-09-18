// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {
    TimelockControllerUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

/**
 * @title TimelockController
 * @author DEUSS Team
 * @notice Upgradeable timelock controller. Thin wrapper around OZ's
 *         TimelockControllerUpgradeable that locks the implementation against
 *         direct initialization.
 */
contract TimelockController is TimelockControllerUpgradeable {
    /// @notice Lock the implementation contract against direct initialization.
    constructor() {
        _disableInitializers();
    }
}
