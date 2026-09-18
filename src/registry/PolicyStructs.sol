// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

/**
 * @notice Batch item for operation-role updates.
 * @param target Operation target.
 * @param selector Operation selector.
 * @param roles Role bitmap.
 */
struct OperationRoles {
    address target;
    bytes4 selector;
    uint256 roles;
}

/**
 * @notice Batch item for operation-module updates.
 * @param target Operation target.
 * @param selector Operation selector.
 * @param module Optional policy module. Zero address clears the module.
 */
struct OperationModule {
    address target;
    bytes4 selector;
    address module;
}

/**
 * @notice Diagnostic result for the module stage of policy evaluation.
 * @param hasModule Whether a module is configured for the wallet operation.
 * @param module Configured module address, or zero if none is configured.
 * @param moduleAllowed Whether the configured module is currently allowlisted.
 * @param moduleCallSucceeded Whether the staticcall to the module completed successfully.
 * @param moduleAuthorized Whether the module allowed the operation.
 */
struct ModuleExecutionCheck {
    bool hasModule;
    address module;
    bool moduleAllowed;
    bool moduleCallSucceeded;
    bool moduleAuthorized;
}
