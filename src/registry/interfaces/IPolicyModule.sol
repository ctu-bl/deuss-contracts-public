// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title IPolicyModule
 * @author DEUSS Team
 * @notice Placeholder interface for future granular wallet policy modules.
 */
interface IPolicyModule is IERC165 {
    /**
     * @notice Returns whether a wallet call passes additional module validation.
     * @param wallet Wallet performing the call.
     * @param caller Transaction sender attempting execution.
     * @param target Call target.
     * @param value Native value forwarded by the wallet.
     * @param data Encoded call data.
     * @return True if the module allows execution.
     */
    function canExecute(address wallet, address caller, address target, uint256 value, bytes calldata data)
        external
        view
        returns (bool);
}
