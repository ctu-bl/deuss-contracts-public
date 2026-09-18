// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Errors} from "./Errors.sol";

/**
 * @title AddressExtensions
 * @author DEUSS Team
 * @notice Provides utility functions for address type
 * @dev Small helpers used in dependency wiring and input validation; keep revert data consistent via `Errors`.
 */
library AddressExtensions {
    /**
     * @notice Asserts that an address is not the zero address
     * @param caller The address to check
     * @dev Reverts with `Errors.ZeroAddress()` if `caller` is zero
     */
    function assertAddressNotZero(address caller) public pure {
        require(!(caller == address(0)), Errors.ZeroAddress());
    }
}
