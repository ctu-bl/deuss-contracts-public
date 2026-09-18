// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, gas-strict-inequalities */

import {Errors} from "src/libs/Errors.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {PreconditionsPolicyRegistry} from "../preconditions/PreconditionsPolicyRegistry.sol";
import {PostconditionsBase} from "./PostconditionsBase.sol";

abstract contract PostconditionsPolicyRegistry is PostconditionsBase {
    // =========================================================================
    // Admin management
    // =========================================================================

    function grantWalletPolicyAdminPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsPolicyRegistry.PolicyWalletAdminParams memory params
    ) internal {
        if (success) {
            invariant_PR_10(params.wallet, params.admin);
            invariant_PR_12(params.otherWallet, params.admin, params.otherWalletWasGranted);
        } else {
            // Contract check order: Unauthorized → InvalidPolicyAdmin → AlreadyGranted
            bytes4 expectedSelector = !params.callerIsOwner
                ? Errors.PolicyRegistry__Unauthorized.selector
                : params.admin == address(0)
                    ? Errors.PolicyRegistry__InvalidPolicyAdmin.selector
                    : params.wasGranted ? Errors.PolicyRegistry__WalletPolicyAdminAlreadyGranted.selector : bytes4(0);
            invariant_PR_13(_returnSelector(returnData), expectedSelector);
        }
    }

    function revokeWalletPolicyAdminPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsPolicyRegistry.PolicyWalletAdminParams memory params
    ) internal {
        if (success) {
            invariant_PR_11(params.wallet, params.admin);
            invariant_PR_12(params.otherWallet, params.admin, params.otherWalletWasGranted);
        } else {
            // Contract check order: Unauthorized → InvalidPolicyAdmin → NotGranted
            bytes4 expectedSelector = !params.callerIsOwner
                ? Errors.PolicyRegistry__Unauthorized.selector
                : params.admin == address(0)
                    ? Errors.PolicyRegistry__InvalidPolicyAdmin.selector
                    : !params.wasGranted ? Errors.PolicyRegistry__WalletPolicyAdminNotGranted.selector : bytes4(0);
            invariant_PR_13(_returnSelector(returnData), expectedSelector);
        }
    }

    // =========================================================================
    // Policy epoch
    // =========================================================================

    function advancePolicyEpochPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsPolicyRegistry.PolicyEpochAdvanceParams memory params
    ) internal {
        // Capture both wallets after the attempted epoch advance so the invariants can compare
        // selected-wallet effects and sibling-wallet isolation against the BEFORE snapshots.
        _afterPolicyRegistry(params.wallet, params.admin, params.user, params.target, params.selector, 0, params.data);
        _afterPolicyRegistry(
            params.otherWallet, params.admin, params.user, params.target, params.selector, 0, params.data
        );
        invariant_PR_75(
            params.wallet, params.admin, params.user, params.target, params.selector, params.roles, params.data
        );

        if (success) {
            invariant_PR_70(params.wallet);
            invariant_PR_71(params.wallet, params.admin, params.user, params.target, params.selector, params.data);
        } else {
            bytes4 expectedSelector = params.caller != params.owner
                ? Ownable.Unauthorized.selector
                : params.reason == bytes32(0) ? Errors.CompanyWallet__ZeroPolicyEpochReason.selector : bytes4(0);
            invariant_PR_72(_returnSelector(returnData), expectedSelector);
            invariant_PR_73(params.wallet, params.admin, params.user, params.target, params.selector, params.data);
        }

        invariant_PR_74(params.otherWallet, params.admin, params.user, params.target, params.selector, params.data);
    }

    // =========================================================================
    // User roles
    // =========================================================================

    function grantUserRolesPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsPolicyRegistry.PolicyUserRolesParams memory params
    ) internal {
        if (success) {
            invariant_PR_20(params.wallet, params.user, params.beforeRoles, params.roles);
            invariant_PR_23(params.otherWallet, params.user, params.otherWalletBeforeRoles);
        } else {
            // Contract check order: Unauthorized → ZeroAddress → ZeroRoles → AlreadyGranted
            bytes4 expectedSelector = !params.operatorAuthorized
                ? Errors.PolicyRegistry__Unauthorized.selector
                : params.user == address(0)
                    ? Errors.ZeroAddress.selector
                    : params.roles == 0
                        ? Errors.PolicyRegistry__ZeroRoles.selector
                        : (params.beforeRoles & params.roles) == params.roles
                            ? Errors.PolicyRegistry__UserRolesAlreadyGranted.selector
                            : bytes4(0);
            invariant_PR_24(_returnSelector(returnData), expectedSelector);
        }
    }

    function revokeUserRolesPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsPolicyRegistry.PolicyUserRolesParams memory params
    ) internal {
        if (success) {
            invariant_PR_21(params.wallet, params.user, params.beforeRoles, params.roles);
            invariant_PR_23(params.otherWallet, params.user, params.otherWalletBeforeRoles);
        } else {
            // Contract check order: Unauthorized → ZeroAddress → ZeroRoles → NotGranted
            bytes4 expectedSelector = !params.operatorAuthorized
                ? Errors.PolicyRegistry__Unauthorized.selector
                : params.user == address(0)
                    ? Errors.ZeroAddress.selector
                    : params.roles == 0
                        ? Errors.PolicyRegistry__ZeroRoles.selector
                        : (params.beforeRoles & params.roles) != params.roles
                            ? Errors.PolicyRegistry__UserRolesNotGranted.selector
                            : bytes4(0);
            invariant_PR_24(_returnSelector(returnData), expectedSelector);
        }
    }

    function setUserRolesPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsPolicyRegistry.PolicyUserRolesParams memory params
    ) internal {
        if (success) {
            invariant_PR_22(params.wallet, params.user, params.roles);
            invariant_PR_23(params.otherWallet, params.user, params.otherWalletBeforeRoles);
        } else {
            // Contract check order: Unauthorized → ZeroAddress
            bytes4 expectedSelector = !params.operatorAuthorized
                ? Errors.PolicyRegistry__Unauthorized.selector
                : params.user == address(0) ? Errors.ZeroAddress.selector : bytes4(0);
            invariant_PR_24(_returnSelector(returnData), expectedSelector);
        }
    }

    // =========================================================================
    // Operation roles
    // =========================================================================

    function grantOperationRolesPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsPolicyRegistry.PolicyOperationRolesParams memory params
    ) internal {
        if (success) {
            invariant_PR_30(params.wallet, params.target, params.selector, params.beforeRoles, params.roles);
            invariant_PR_33(params.otherWallet, params.target, params.selector, params.otherWalletBeforeRoles);
        } else {
            // Contract check order: Unauthorized → ZeroRoles → (ZeroAddress/ZeroSelector) → AlreadyGranted
            // Target and selector are always valid from _pickPolicyOperation, so ZeroAddress/ZeroSelector
            // cannot fire when roles != 0.
            bytes4 expectedSelector = !params.operatorAuthorized
                ? Errors.PolicyRegistry__Unauthorized.selector
                : params.roles == 0
                    ? Errors.PolicyRegistry__ZeroRoles.selector
                    : (params.beforeRoles & params.roles) == params.roles
                        ? Errors.PolicyRegistry__OperationRolesAlreadyGranted.selector
                        : bytes4(0);
            invariant_PR_34(_returnSelector(returnData), expectedSelector);
        }
    }

    function revokeOperationRolesPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsPolicyRegistry.PolicyOperationRolesParams memory params
    ) internal {
        if (success) {
            invariant_PR_31(params.wallet, params.target, params.selector, params.beforeRoles, params.roles);
            invariant_PR_33(params.otherWallet, params.target, params.selector, params.otherWalletBeforeRoles);
        } else {
            // Contract check order: Unauthorized → ZeroRoles → (ZeroAddress/ZeroSelector) → NotGranted
            bytes4 expectedSelector = !params.operatorAuthorized
                ? Errors.PolicyRegistry__Unauthorized.selector
                : params.roles == 0
                    ? Errors.PolicyRegistry__ZeroRoles.selector
                    : (params.beforeRoles & params.roles) != params.roles
                        ? Errors.PolicyRegistry__OperationRolesNotGranted.selector
                        : bytes4(0);
            invariant_PR_34(_returnSelector(returnData), expectedSelector);
        }
    }

    function setOperationRolesPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsPolicyRegistry.PolicyOperationRolesParams memory params
    ) internal {
        if (success) {
            invariant_PR_32(params.wallet, params.target, params.selector, params.roles);
            invariant_PR_33(params.otherWallet, params.target, params.selector, params.otherWalletBeforeRoles);
        } else {
            bytes4 expectedSelector =
                !params.operatorAuthorized ? Errors.PolicyRegistry__Unauthorized.selector : bytes4(0);
            invariant_PR_34(_returnSelector(returnData), expectedSelector);
        }
    }

    // =========================================================================
    // Operation module
    // =========================================================================

    function setOperationModulePostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsPolicyRegistry.PolicyOperationModuleParams memory params
    ) internal {
        if (success) {
            invariant_PR_40(params.wallet, params.target, params.selector, params.module);
            invariant_PR_41(params.otherWallet, params.target, params.selector, params.otherWalletBeforeModule);
        } else {
            bytes4 expectedSelector = !params.operatorAuthorized
                ? Errors.PolicyRegistry__Unauthorized.selector
                : !params.moduleAllowed ? Errors.PolicyRegistry__PolicyModuleNotAllowed.selector : bytes4(0);
            invariant_PR_42(_returnSelector(returnData), expectedSelector);
        }
    }

    // =========================================================================
    // Global config
    // =========================================================================

    function setPolicyModuleAllowedPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsPolicyRegistry.PolicyModuleAllowedParams memory params
    ) internal {
        if (success) {
            invariant_PR_50(params.module, params.allowed);
        } else {
            // setPolicyModuleAllowed is onlyOwner; the handler always calls as governance.
            // Any revert here is unexpected — no specific error selector is anticipated.
            invariant_PR_52(_returnSelector(returnData));
        }
    }

    function setRoleLabelPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsPolicyRegistry.PolicyRoleLabelParams memory params
    ) internal {
        if (success) {
            invariant_PR_51(params.roleId, params.label);
        } else {
            // setRoleLabel is onlyOwner; the handler always calls as governance.
            // Any revert here is unexpected.
            invariant_PR_53(_returnSelector(returnData));
        }
    }

    // =========================================================================
    // View and execution checks
    // =========================================================================

    function policyLookupPostconditions(PreconditionsPolicyRegistry.PolicyLookupParams memory params) internal {
        invariant_PR_60(params.wallet, params.caller, params.target, params.value, params.data);
        invariant_PR_61(params.wallet, params.caller, params.target, params.value, params.data);
        if (params.target != address(0) && params.data.length >= 4) {
            invariant_PR_63(params.target, _selectorFromPolicyData(params.data));
        }
    }

    function policyExecutePostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsPolicyRegistry.PolicyExecuteParams memory params
    ) internal {
        invariant_PR_62(
            success,
            _returnSelector(returnData),
            params.expectedAuthorized,
            params.wallet,
            params.beforeCallCount,
            params.beforeFlag,
            params.beforeNumber,
            params.isSetFlag,
            params.expectedFlagValue,
            params.expectedNumberValue
        );
    }

    function companyWalletSuccessPostconditions(bool success, bytes memory returnData) internal {
        invariant_PR_64(success, _returnSelector(returnData));
    }

    function companyWalletRenouncePostconditions(bool success, bytes memory returnData) internal {
        invariant_PR_65(success, _returnSelector(returnData));
    }

    function policyAllowModuleSeedPostconditions(bool success) internal {
        invariant_PR_76(success);
    }

    function policyOwnerSeedPostconditions(bool success) internal {
        invariant_PR_77(success);
    }

    // =========================================================================
    // Policy version (ownership epoch)
    // =========================================================================

    function advancePolicyVersionPostconditions(
        bool success,
        PreconditionsPolicyRegistry.PolicyEpochParams memory params,
        uint256 epochBefore,
        uint256 epochAfter,
        uint256 userRolesBefore,
        bool adminBefore,
        uint256 operationRolesBefore,
        address moduleBefore
    ) internal {
        invariant_PR_72(success);
        // The version advance is a directed owner-only transfer that must succeed; PR-72 records any
        // unexpected revert. Only evaluate the monotonicity and reset invariants on the success path.
        if (!success) {
            return;
        }

        invariant_PR_70(epochBefore, epochAfter);
        invariant_PR_71_PRE_USER_ROLES(userRolesBefore);
        invariant_PR_71_PRE_ADMIN(adminBefore);
        invariant_PR_71_PRE_OPERATION_ROLES(operationRolesBefore);
        invariant_PR_71_USER_ROLES(params.wallet, params.user);
        invariant_PR_71_ADMIN(params.wallet, params.admin);
        invariant_PR_71_OPERATION_ROLES(params.wallet, params.target, params.selector);
        if (params.moduleSeeded) {
            invariant_PR_71_PRE_OPERATION_MODULE(moduleBefore);
            invariant_PR_71_OPERATION_MODULE(params.wallet, params.target, params.selector);
        }
    }
}
