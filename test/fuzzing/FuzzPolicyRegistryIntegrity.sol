// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {FuzzIntegrityBase} from "./FuzzIntegrityBase.sol";
import {HandlerPolicyRegistry} from "./helper/handlers/HandlerPolicyRegistry.sol";

/**
 * @title FuzzPolicyRegistryIntegrity
 * @notice Checks handler integrity for the PolicyRegistry fuzz harness.
 */
contract FuzzPolicyRegistryIntegrity is HandlerPolicyRegistry, FuzzIntegrityBase {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         INTEGRITY                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // =========================================================================
    // Admin management
    // =========================================================================

    function fuzz_grantWalletPolicyAdmin(uint256 walletSeed, uint256 adminSeed, uint256 callerSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_grantWalletPolicyAdmin.selector, walletSeed, adminSeed, callerSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-GRANT-WALLET-POLICY-ADMIN");
        }
    }

    function fuzz_revokeWalletPolicyAdmin(uint256 walletSeed, uint256 adminSeed, uint256 callerSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_revokeWalletPolicyAdmin.selector, walletSeed, adminSeed, callerSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-REVOKE-WALLET-POLICY-ADMIN");
        }
    }

    // =========================================================================
    // Policy epoch
    // =========================================================================

    function fuzz_advancePolicyEpoch(uint256 walletSeed, uint256 pathSeed, uint256 stateSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_advancePolicyEpoch.selector, walletSeed, pathSeed, stateSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-ADVANCE-POLICY-EPOCH");
        }
    }

    // =========================================================================
    // User roles — single-item
    // =========================================================================

    function fuzz_grantUserRoles(uint256 walletSeed, uint256 callerSeed, uint256 userSeed, uint256 rolesSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_grantUserRoles.selector, walletSeed, callerSeed, userSeed, rolesSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-GRANT-USER-ROLES");
        }
    }

    function fuzz_revokeUserRoles(uint256 walletSeed, uint256 callerSeed, uint256 userSeed, uint256 rolesSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_revokeUserRoles.selector, walletSeed, callerSeed, userSeed, rolesSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-REVOKE-USER-ROLES");
        }
    }

    function fuzz_setUserRoles(uint256 walletSeed, uint256 callerSeed, uint256 userSeed, uint256 rolesSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_setUserRoles.selector, walletSeed, callerSeed, userSeed, rolesSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-SET-USER-ROLES");
        }
    }

    // =========================================================================
    // User roles — batch overloads
    // =========================================================================

    function fuzz_grantUserRolesBatch(uint256 walletSeed, uint256 callerSeed, uint256 userSeed, uint256 rolesSeed)
        public
    {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_grantUserRolesBatch.selector, walletSeed, callerSeed, userSeed, rolesSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-GRANT-USER-ROLES-BATCH");
        }
    }

    function fuzz_revokeUserRolesBatch(uint256 walletSeed, uint256 callerSeed, uint256 userSeed, uint256 rolesSeed)
        public
    {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_revokeUserRolesBatch.selector, walletSeed, callerSeed, userSeed, rolesSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-REVOKE-USER-ROLES-BATCH");
        }
    }

    function fuzz_setUserRolesBatch(uint256 walletSeed, uint256 callerSeed, uint256 userSeed, uint256 rolesSeed)
        public
    {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_setUserRolesBatch.selector, walletSeed, callerSeed, userSeed, rolesSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-SET-USER-ROLES-BATCH");
        }
    }

    // =========================================================================
    // Operation roles — single-item
    // =========================================================================

    function fuzz_grantOperationRoles(uint256 walletSeed, uint256 callerSeed, uint256 operationSeed, uint256 rolesSeed)
        public
    {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_grantOperationRoles.selector, walletSeed, callerSeed, operationSeed, rolesSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-GRANT-OPERATION-ROLES");
        }
    }

    function fuzz_revokeOperationRoles(uint256 walletSeed, uint256 callerSeed, uint256 operationSeed, uint256 rolesSeed)
        public
    {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_revokeOperationRoles.selector,
            walletSeed,
            callerSeed,
            operationSeed,
            rolesSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-REVOKE-OPERATION-ROLES");
        }
    }

    function fuzz_setOperationRoles(uint256 walletSeed, uint256 callerSeed, uint256 operationSeed, uint256 rolesSeed)
        public
    {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_setOperationRoles.selector, walletSeed, callerSeed, operationSeed, rolesSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-SET-OPERATION-ROLES");
        }
    }

    // =========================================================================
    // Operation roles — batch overloads
    // =========================================================================

    function fuzz_grantOperationRolesBatch(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 rolesSeed
    ) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_grantOperationRolesBatch.selector,
            walletSeed,
            callerSeed,
            operationSeed,
            rolesSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-GRANT-OPERATION-ROLES-BATCH");
        }
    }

    function fuzz_revokeOperationRolesBatch(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 rolesSeed
    ) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_revokeOperationRolesBatch.selector,
            walletSeed,
            callerSeed,
            operationSeed,
            rolesSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-REVOKE-OPERATION-ROLES-BATCH");
        }
    }

    function fuzz_setOperationRolesBatch(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 rolesSeed
    ) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_setOperationRolesBatch.selector,
            walletSeed,
            callerSeed,
            operationSeed,
            rolesSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-SET-OPERATION-ROLES-BATCH");
        }
    }

    // =========================================================================
    // Operation module — single-item and batch
    // =========================================================================

    function fuzz_setOperationModule(uint256 walletSeed, uint256 callerSeed, uint256 operationSeed, uint256 moduleSeed)
        public
    {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_setOperationModule.selector, walletSeed, callerSeed, operationSeed, moduleSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-SET-OPERATION-MODULE");
        }
    }

    function fuzz_setOperationModuleBatch(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 moduleSeed
    ) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_setOperationModuleBatch.selector,
            walletSeed,
            callerSeed,
            operationSeed,
            moduleSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-SET-OPERATION-MODULE-BATCH");
        }
    }

    // =========================================================================
    // Global config
    // =========================================================================

    function fuzz_setPolicyModuleAllowed(uint256 moduleSeed, bool allowed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerPolicyRegistry.handler_setPolicyModuleAllowed.selector, moduleSeed, allowed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-SET-POLICY-MODULE-ALLOWED");
        }
    }

    function fuzz_setRoleLabel(uint256 roleSeed, uint256 labelSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerPolicyRegistry.handler_setRoleLabel.selector, roleSeed, labelSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-SET-ROLE-LABEL");
        }
    }

    // =========================================================================
    // View and execution checks
    // =========================================================================

    function fuzz_checkPolicyLookup(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 dataSeed,
        uint256 requestKindSeed
    ) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_checkPolicyLookup.selector,
            walletSeed,
            callerSeed,
            operationSeed,
            dataSeed,
            requestKindSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-CHECK-POLICY-LOOKUP");
        }
    }

    function fuzz_checkPolicyLookupWithAllowModule(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 dataSeed
    ) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_checkPolicyLookupWithAllowModule.selector,
            walletSeed,
            callerSeed,
            operationSeed,
            dataSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-CHECK-POLICY-MODULE-LOOKUP");
        }
    }

    function fuzz_companyWalletAdminSurface(uint256 walletSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerPolicyRegistry.handler_companyWalletAdminSurface.selector, walletSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-COMPANY-WALLET-SURFACE");
        }
    }

    function fuzz_executePolicyCall(uint256 walletSeed, uint256 callerSeed, uint256 operationSeed, uint256 dataSeed)
        public
    {
        bytes memory callData = abi.encodeWithSelector(
            HandlerPolicyRegistry.handler_executePolicyCall.selector, walletSeed, callerSeed, operationSeed, dataSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-EXECUTE-POLICY-CALL");
        }
    }

    // =========================================================================
    // Policy version (ownership epoch)
    // =========================================================================

    function fuzz_advancePolicyVersionResetsState(uint256 seed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerPolicyRegistry.handler_advancePolicyVersionResetsState.selector, seed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "PR-ADVANCE-POLICY-VERSION");
        }
    }
}
