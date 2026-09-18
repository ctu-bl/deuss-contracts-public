// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {FuzzStorageVariables} from "./FuzzStorageVariables.sol";

/// @title PolicyRegistryHelpers
/// @notice Shared pure/view helpers for the PolicyRegistry fuzz harness.
/// @dev Inherited by PreconditionsPolicyRegistry and Properties_PR.  Only
///      pure/view logic lives here so the contract does not need FuzzBase.
abstract contract PolicyRegistryHelpers is FuzzStorageVariables {
    // -------------------------------------------------------------------------
    // Reference model
    // -------------------------------------------------------------------------

    /**
     * @notice Reference model for PolicyRegistry.canExecute.
     * @dev Mirrors the on-chain role/module evaluation so preconditions and
     *      invariants reason from the same source.  `value` is kept for
     *      signature parity but has no effect on role-based authorization.
     */
    function _expectedPolicyCanExecute(address wallet, address caller, address target, uint256, bytes memory data)
        internal
        view
        returns (bool)
    {
        if (wallet == address(0) || caller == address(0) || target == address(0) || data.length < 4) {
            return false;
        }

        uint256 userRoles = policyRegistry.getUserRoles(wallet, caller);
        if (userRoles == 0) {
            return false;
        }

        bytes4 selector = _selectorFromPolicyData(data);
        uint256 operationRoles = policyRegistry.getOperationRoles(wallet, target, selector);
        if ((userRoles & operationRoles) == 0) {
            return false;
        }

        address module = policyRegistry.getOperationModule(wallet, target, selector);
        if (module == address(0)) {
            return true;
        }
        if (!policyRegistry.isPolicyModuleAllowed(module)) {
            return false;
        }
        return module == address(policyAllowModule);
    }

    // -------------------------------------------------------------------------
    // Access-control predicate
    // -------------------------------------------------------------------------

    /**
     * @notice Returns true when caller is the wallet owner or a delegated policy admin.
     */
    function _isPolicyOperator(address wallet, address owner, address caller) internal view returns (bool) {
        return caller == owner || policyRegistry.isWalletPolicyAdmin(wallet, caller);
    }

    // -------------------------------------------------------------------------
    // Data utility
    // -------------------------------------------------------------------------

    /**
     * @notice Extracts the 4-byte selector from the head of encoded calldata.
     * @dev Returns bytes4(0) when data is shorter than 4 bytes.
     */
    function _selectorFromPolicyData(bytes memory data) internal pure returns (bytes4 selector) {
        if (data.length < 4) return bytes4(0);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            selector := mload(add(data, 32))
        }
    }
}
