// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {Errors} from "src/libs/Errors.sol";
import {ModuleExecutionCheck} from "src/registry/PolicyStructs.sol";
import {PolicyRegistryHelpers} from "../helper/PolicyRegistryHelpers.sol";
import {PropertiesBase} from "./PropertiesBase.sol";

abstract contract Properties_PR is PolicyRegistryHelpers, PropertiesBase {
    // =========================================================================
    // Admin management invariants
    // =========================================================================

    function invariant_PR_10(address wallet, address admin) internal {
        fl.eq(policyRegistry.isWalletPolicyAdmin(wallet, admin), true, PR_10);
    }

    function invariant_PR_11(address wallet, address admin) internal {
        fl.eq(policyRegistry.isWalletPolicyAdmin(wallet, admin), false, PR_11);
    }

    function invariant_PR_12(address wallet, address admin, bool expected) internal {
        fl.eq(policyRegistry.isWalletPolicyAdmin(wallet, admin), expected, PR_12);
    }

    function invariant_PR_13(bytes4 errorSelector, bytes4 expectedSelector) internal {
        _assertPolicyError(errorSelector, expectedSelector, PR_13);
    }

    // =========================================================================
    // Policy epoch invariants
    // =========================================================================

    function invariant_PR_70(address wallet) internal {
        fl.eq(
            states[AFTER].policyWalletStates[wallet].ownershipEpoch,
            states[BEFORE].policyWalletStates[wallet].ownershipEpoch + 1,
            PR_70_EPOCH
        );
        fl.eq(
            states[AFTER].policyWalletStates[wallet].owner, states[BEFORE].policyWalletStates[wallet].owner, PR_70_OWNER
        );
    }

    function invariant_PR_71(
        address wallet,
        address admin,
        address user,
        address target,
        bytes4 selector,
        bytes memory data
    ) internal {
        bytes32 operationKey = _policyOperationKey(target, selector);
        bytes32 executionKey = _policyExecutionKey(user, target, 0, data);

        fl.eq(states[AFTER].policyAdminStates[wallet][admin], false, PR_71_ADMIN);
        fl.eq(states[AFTER].policyUserRoleStates[wallet][user], 0, PR_71_USER_ROLES);
        fl.eq(states[AFTER].policyOperationStates[wallet][operationKey].roles, 0, PR_71_OPERATION_ROLES);
        fl.eq(states[AFTER].policyOperationStates[wallet][operationKey].module, address(0), PR_71_OPERATION_MODULE);
        fl.eq(states[AFTER].policyExecutionStates[wallet][executionKey], false, PR_71_CAN_EXECUTE);
    }

    function invariant_PR_72(bytes4 errorSelector, bytes4 expectedSelector) internal {
        _assertPolicyError(errorSelector, expectedSelector, PR_72);
    }

    function invariant_PR_73(
        address wallet,
        address admin,
        address user,
        address target,
        bytes4 selector,
        bytes memory data
    ) internal {
        bytes32 operationKey = _policyOperationKey(target, selector);
        bytes32 executionKey = _policyExecutionKey(user, target, 0, data);

        fl.eq(
            states[AFTER].policyWalletStates[wallet].ownershipEpoch,
            states[BEFORE].policyWalletStates[wallet].ownershipEpoch,
            PR_73_EPOCH
        );
        fl.eq(
            states[AFTER].policyWalletStates[wallet].owner, states[BEFORE].policyWalletStates[wallet].owner, PR_73_OWNER
        );
        fl.eq(
            states[AFTER].policyAdminStates[wallet][admin], states[BEFORE].policyAdminStates[wallet][admin], PR_73_ADMIN
        );
        fl.eq(
            states[AFTER].policyUserRoleStates[wallet][user],
            states[BEFORE].policyUserRoleStates[wallet][user],
            PR_73_USER_ROLES
        );
        fl.eq(
            states[AFTER].policyOperationStates[wallet][operationKey].roles,
            states[BEFORE].policyOperationStates[wallet][operationKey].roles,
            PR_73_OPERATION_ROLES
        );
        fl.eq(
            states[AFTER].policyOperationStates[wallet][operationKey].module,
            states[BEFORE].policyOperationStates[wallet][operationKey].module,
            PR_73_OPERATION_MODULE
        );
        fl.eq(
            states[AFTER].policyExecutionStates[wallet][executionKey],
            states[BEFORE].policyExecutionStates[wallet][executionKey],
            PR_73_CAN_EXECUTE
        );
    }

    function invariant_PR_74(
        address wallet,
        address admin,
        address user,
        address target,
        bytes4 selector,
        bytes memory data
    ) internal {
        bytes32 operationKey = _policyOperationKey(target, selector);
        bytes32 executionKey = _policyExecutionKey(user, target, 0, data);

        fl.eq(
            states[AFTER].policyWalletStates[wallet].ownershipEpoch,
            states[BEFORE].policyWalletStates[wallet].ownershipEpoch,
            PR_74_EPOCH
        );
        fl.eq(
            states[AFTER].policyWalletStates[wallet].owner, states[BEFORE].policyWalletStates[wallet].owner, PR_74_OWNER
        );
        fl.eq(
            states[AFTER].policyAdminStates[wallet][admin], states[BEFORE].policyAdminStates[wallet][admin], PR_74_ADMIN
        );
        fl.eq(
            states[AFTER].policyUserRoleStates[wallet][user],
            states[BEFORE].policyUserRoleStates[wallet][user],
            PR_74_USER_ROLES
        );
        fl.eq(
            states[AFTER].policyOperationStates[wallet][operationKey].roles,
            states[BEFORE].policyOperationStates[wallet][operationKey].roles,
            PR_74_OPERATION_ROLES
        );
        fl.eq(
            states[AFTER].policyOperationStates[wallet][operationKey].module,
            states[BEFORE].policyOperationStates[wallet][operationKey].module,
            PR_74_OPERATION_MODULE
        );
        fl.eq(
            states[AFTER].policyExecutionStates[wallet][executionKey],
            states[BEFORE].policyExecutionStates[wallet][executionKey],
            PR_74_CAN_EXECUTE
        );
    }

    function invariant_PR_75(
        address wallet,
        address admin,
        address user,
        address target,
        bytes4 selector,
        uint256 roles,
        bytes memory data
    ) internal {
        bytes32 operationKey = _policyOperationKey(target, selector);
        bytes32 executionKey = _policyExecutionKey(user, target, 0, data);

        fl.eq(states[BEFORE].policyAdminStates[wallet][admin], true, PR_75_ADMIN);
        fl.eq(states[BEFORE].policyUserRoleStates[wallet][user], roles, PR_75_USER_ROLES);
        fl.eq(states[BEFORE].policyOperationStates[wallet][operationKey].roles, roles, PR_75_OPERATION_ROLES);
        fl.eq(
            states[BEFORE].policyOperationStates[wallet][operationKey].module,
            address(policyAllowModule),
            PR_75_OPERATION_MODULE
        );
        fl.eq(states[BEFORE].policyExecutionStates[wallet][executionKey], true, PR_75_CAN_EXECUTE);
    }

    // =========================================================================
    // User role invariants
    // =========================================================================

    function invariant_PR_20(address wallet, address user, uint256 beforeRoles, uint256 roles) internal {
        fl.eq(policyRegistry.getUserRoles(wallet, user), beforeRoles | roles, PR_20);
    }

    function invariant_PR_21(address wallet, address user, uint256 beforeRoles, uint256 roles) internal {
        fl.eq(policyRegistry.getUserRoles(wallet, user), beforeRoles & ~roles, PR_21);
    }

    function invariant_PR_22(address wallet, address user, uint256 roles) internal {
        fl.eq(policyRegistry.getUserRoles(wallet, user), roles, PR_22);
    }

    function invariant_PR_23(address wallet, address user, uint256 expectedRoles) internal {
        fl.eq(policyRegistry.getUserRoles(wallet, user), expectedRoles, PR_23);
    }

    function invariant_PR_24(bytes4 errorSelector, bytes4 expectedSelector) internal {
        _assertPolicyError(errorSelector, expectedSelector, PR_24);
    }

    // =========================================================================
    // Operation role invariants
    // =========================================================================

    function invariant_PR_30(address wallet, address target, bytes4 selector, uint256 beforeRoles, uint256 roles)
        internal
    {
        fl.eq(policyRegistry.getOperationRoles(wallet, target, selector), beforeRoles | roles, PR_30);
    }

    function invariant_PR_31(address wallet, address target, bytes4 selector, uint256 beforeRoles, uint256 roles)
        internal
    {
        fl.eq(policyRegistry.getOperationRoles(wallet, target, selector), beforeRoles & ~roles, PR_31);
    }

    function invariant_PR_32(address wallet, address target, bytes4 selector, uint256 roles) internal {
        fl.eq(policyRegistry.getOperationRoles(wallet, target, selector), roles, PR_32);
    }

    function invariant_PR_33(address wallet, address target, bytes4 selector, uint256 expectedRoles) internal {
        fl.eq(policyRegistry.getOperationRoles(wallet, target, selector), expectedRoles, PR_33);
    }

    function invariant_PR_34(bytes4 errorSelector, bytes4 expectedSelector) internal {
        _assertPolicyError(errorSelector, expectedSelector, PR_34);
    }

    // =========================================================================
    // Operation module invariants
    // =========================================================================

    function invariant_PR_40(address wallet, address target, bytes4 selector, address module) internal {
        fl.eq(policyRegistry.getOperationModule(wallet, target, selector), module, PR_40);
    }

    function invariant_PR_41(address wallet, address target, bytes4 selector, address expectedModule) internal {
        fl.eq(policyRegistry.getOperationModule(wallet, target, selector), expectedModule, PR_41);
    }

    function invariant_PR_42(bytes4 errorSelector, bytes4 expectedSelector) internal {
        _assertPolicyError(errorSelector, expectedSelector, PR_42);
    }

    // =========================================================================
    // Global config invariants
    // =========================================================================

    function invariant_PR_50(address module, bool allowed) internal {
        fl.eq(policyRegistry.isPolicyModuleAllowed(module), allowed, PR_50);
    }

    function invariant_PR_51(uint8 roleId, bytes32 label) internal {
        fl.eq(uint256(policyRegistry.roleLabels(roleId)), uint256(label), PR_51);
    }

    function invariant_PR_52(bytes4 errorSelector) internal {
        bytes4[] memory emptyAllowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, emptyAllowedErrors, PR_52);
    }

    function invariant_PR_53(bytes4 errorSelector) internal {
        bytes4[] memory emptyAllowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, emptyAllowedErrors, PR_53);
    }

    // =========================================================================
    // Execution invariants
    // =========================================================================

    function invariant_PR_60(address wallet, address caller, address target, uint256 value, bytes memory data)
        internal
    {
        bool expected = _expectedPolicyCanExecute(wallet, caller, target, value, data);
        fl.eq(policyRegistry.canExecute(wallet, caller, target, value, data), expected, PR_60);
    }

    function invariant_PR_61(address wallet, address caller, address target, uint256 value, bytes memory data)
        internal
    {
        ModuleExecutionCheck memory result = policyRegistry.checkOperationModule(wallet, caller, target, value, data);

        if (wallet == address(0) || caller == address(0) || target == address(0) || data.length < 4) {
            fl.eq(result.hasModule, false, PR_61_HAS_MODULE);
            fl.eq(result.module, address(0), PR_61_MODULE);
            fl.eq(result.moduleAllowed, false, PR_61_MODULE_ALLOWED);
            fl.eq(result.moduleCallSucceeded, false, PR_61_MODULE_CALL_SUCCEEDED);
            fl.eq(result.moduleAuthorized, false, PR_61_MODULE_AUTHORIZED);
            return;
        }

        address module = policyRegistry.getOperationModule(wallet, target, _selectorFromPolicyData(data));
        fl.eq(result.hasModule, module != address(0), PR_61_HAS_MODULE);
        fl.eq(result.module, module, PR_61_MODULE);

        if (module == address(0)) {
            fl.eq(result.moduleAllowed, false, PR_61_MODULE_ALLOWED);
            fl.eq(result.moduleCallSucceeded, false, PR_61_MODULE_CALL_SUCCEEDED);
            fl.eq(result.moduleAuthorized, false, PR_61_MODULE_AUTHORIZED);
            return;
        }

        bool moduleAllowed = policyRegistry.isPolicyModuleAllowed(module);
        fl.eq(result.moduleAllowed, moduleAllowed, PR_61_MODULE_ALLOWED);
        if (!moduleAllowed) {
            fl.eq(result.moduleCallSucceeded, false, PR_61_MODULE_CALL_SUCCEEDED);
            fl.eq(result.moduleAuthorized, false, PR_61_MODULE_AUTHORIZED);
            return;
        }

        // policyRevertingModule reverts → success = false; policyInvalidReturnModule returns 1 byte → length ≠ 32.
        // Only policyAllowModule and policyDenyModule complete normally with a 32-byte bool.
        bool expectedCallSucceeded = module == address(policyAllowModule) || module == address(policyDenyModule);
        fl.eq(result.moduleCallSucceeded, expectedCallSucceeded, PR_61_MODULE_CALL_SUCCEEDED);
        fl.eq(result.moduleAuthorized, module == address(policyAllowModule), PR_61_MODULE_AUTHORIZED);
    }

    function invariant_PR_62(
        bool success,
        bytes4 errorSelector,
        bool expectedAuthorized,
        address wallet,
        uint256 beforeCallCount,
        bool beforeFlag,
        uint256 beforeNumber,
        bool isSetFlag,
        bool expectedFlagValue,
        uint256 expectedNumberValue
    ) internal {
        if (expectedAuthorized) {
            fl.eq(success, true, PR_62_SUCCESS);
            fl.eq(policyTarget.callCount(), beforeCallCount + 1, PR_62_CALL_COUNT);
            fl.eq(policyTarget.lastCaller(), wallet, PR_62_LAST_CALLER);
            if (isSetFlag) {
                fl.eq(policyTarget.flag(), expectedFlagValue, PR_62_FLAG);
            } else {
                fl.eq(policyTarget.number(), expectedNumberValue, PR_62_NUMBER);
            }
        } else {
            fl.eq(success, false, PR_62_SUCCESS);
            _assertPolicyError(errorSelector, Errors.CompanyWallet__Unauthorized.selector, PR_62_ERROR);
            fl.eq(policyTarget.callCount(), beforeCallCount, PR_62_CALL_COUNT);
            fl.eq(policyTarget.flag(), beforeFlag, PR_62_FLAG);
            fl.eq(policyTarget.number(), beforeNumber, PR_62_NUMBER);
        }
    }

    function invariant_PR_63(address target, bytes4 selector) internal {
        fl.eq(
            uint256(policyRegistry.computeOperationKey(target, selector)),
            uint256(keccak256(abi.encode(target, selector))),
            PR_63
        );
    }

    function invariant_PR_64(bool success, bytes4 errorSelector) internal {
        fl.eq(success, true, PR_64);
        if (!success) {
            bytes4[] memory emptyAllowedErrors = new bytes4[](0);
            fl.errAllow(errorSelector, emptyAllowedErrors, PR_64);
        }
    }

    function invariant_PR_65(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, PR_65);
        _assertPolicyError(errorSelector, Errors.CompanyWallet__RenounceOwnershipDisabled.selector, PR_65);
    }

    // =========================================================================
    // Policy version (ownership epoch) invariants
    // =========================================================================

    /// @dev CompanyWallet._setOwner increments the ownership epoch by exactly one on every
    /// ownership transfer, and the epoch is mutated through no other path. Per-transfer +1
    /// increments therefore imply a strictly monotonic, never-decreasing policy version.
    function invariant_PR_70(uint256 epochBefore, uint256 epochAfter) internal {
        fl.eq(epochAfter, epochBefore + 1, PR_70_INCREMENT);
        fl.gt(epochAfter, epochBefore, PR_70_MONOTONIC);
    }

    /// @dev Asserts the seeded user roles were present at the previous epoch.
    function invariant_PR_71_PRE_USER_ROLES(uint256 userRolesBefore) internal {
        fl.gt(userRolesBefore, 0, PR_71_PRE_USER_ROLES);
    }

    /// @dev Asserts the seeded admin was present at the previous epoch.
    function invariant_PR_71_PRE_ADMIN(bool adminBefore) internal {
        fl.t(adminBefore, PR_71_PRE_ADMIN);
    }

    /// @dev Asserts the seeded operation roles were present at the previous epoch.
    function invariant_PR_71_PRE_OPERATION_ROLES(uint256 operationRolesBefore) internal {
        fl.gt(operationRolesBefore, 0, PR_71_PRE_OPERATION_ROLES);
    }

    /// @dev Asserts seeded user roles are no longer visible at the advanced epoch.
    function invariant_PR_71_USER_ROLES(address wallet, address user) internal {
        fl.eq(policyRegistry.getUserRoles(wallet, user), 0, PR_71_USER_ROLES);
    }

    /// @dev Asserts seeded delegated admin state is no longer visible at the advanced epoch.
    function invariant_PR_71_ADMIN(address wallet, address admin) internal {
        fl.eq(policyRegistry.isWalletPolicyAdmin(wallet, admin), false, PR_71_ADMIN);
    }

    /// @dev Asserts seeded operation roles are no longer visible at the advanced epoch.
    function invariant_PR_71_OPERATION_ROLES(address wallet, address target, bytes4 selector) internal {
        fl.eq(policyRegistry.getOperationRoles(wallet, target, selector), 0, PR_71_OPERATION_ROLES);
    }

    /// @dev Asserts the operation module was present at the previous epoch when seeding was possible.
    function invariant_PR_71_PRE_OPERATION_MODULE(address moduleBefore) internal {
        fl.t(moduleBefore != address(0), PR_71_PRE_OPERATION_MODULE);
    }

    /// @dev Asserts the operation module is no longer visible at the advanced epoch.
    function invariant_PR_71_OPERATION_MODULE(address wallet, address target, bytes4 selector) internal {
        fl.eq(policyRegistry.getOperationModule(wallet, target, selector), address(0), PR_71_OPERATION_MODULE);
    }

    function invariant_PR_72(bool success) internal {
        fl.t(success, PR_72);
    }

    function invariant_PR_76(bool success) internal {
        fl.t(success, PR_76);
    }

    function invariant_PR_77(bool success) internal {
        fl.t(success, PR_77);
    }

    // =========================================================================
    // Internal helpers (require fl from FuzzBase via PropertiesBase)
    // =========================================================================

    function _assertPolicyError(bytes4 errorSelector, bytes4 expectedSelector, string memory reason) internal {
        if (expectedSelector == bytes4(0)) {
            bytes4[] memory emptyAllowedErrors = new bytes4[](0);
            fl.errAllow(errorSelector, emptyAllowedErrors, reason);
            return;
        }

        bytes4[] memory singleAllowedError = new bytes4[](1);
        singleAllowedError[0] = expectedSelector;
        fl.errAllow(errorSelector, singleAllowedError, reason);
    }
}
