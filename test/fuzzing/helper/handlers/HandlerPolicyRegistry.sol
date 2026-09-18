// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {CompanyWallet} from "src/wallet/CompanyWallet.sol";
import {ICompanyWallet} from "src/wallet/ICompanyWallet.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {OperationModule, OperationRoles} from "src/registry/PolicyStructs.sol";
import {PreconditionsPolicyRegistry} from "../preconditions/PreconditionsPolicyRegistry.sol";
import {PostconditionsPolicyRegistry} from "../postconditions/PostconditionsPolicyRegistry.sol";

/// @title HandlerPolicyRegistry
/// @notice Stateful fuzz handlers for the wallet-scoped PolicyRegistry vertical slice.
abstract contract HandlerPolicyRegistry is PreconditionsPolicyRegistry, PostconditionsPolicyRegistry {
    // =========================================================================
    // Admin management
    // =========================================================================

    /// @notice Attempts to grant a delegated wallet policy admin.
    /// @dev Tests the owner-only grant path and all expected failure modes:
    /// unauthorized caller (PR-13/Unauthorized), zero admin address
    /// (InvalidPolicyAdmin), and duplicate grant (AlreadyGranted).
    /// On success, sibling wallet isolation is verified via PR-12.
    /// @param walletSeed Seed used to choose policyWalletA or policyWalletB.
    /// @param adminSeed  Seed used to choose a policy admin candidate; ~1-in-4
    ///                   chance of address(0) to exercise InvalidPolicyAdmin.
    /// @param callerSeed Seed used to choose the transaction sender (owner,
    ///                   admin, user, or outsider).
    function handler_grantWalletPolicyAdmin(uint256 walletSeed, uint256 adminSeed, uint256 callerSeed) public {
        PolicyWalletAdminParams memory params = walletPolicyAdminPreconditions(walletSeed, adminSeed, callerSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(policyRegistry.grantWalletPolicyAdmin.selector, params.wallet, params.admin),
            params.caller
        );

        grantWalletPolicyAdminPostconditions(success, returnData, params);
    }

    /// @notice Attempts to revoke a delegated wallet policy admin.
    /// @dev Tests the owner-only revoke path and all expected failure modes:
    /// unauthorized caller (Unauthorized), zero admin address
    /// (InvalidPolicyAdmin), and revoke-when-not-granted (NotGranted).
    /// On success, sibling wallet isolation is verified via PR-12.
    /// @param walletSeed Seed used to choose policyWalletA or policyWalletB.
    /// @param adminSeed  Seed used to choose a policy admin candidate; ~1-in-4
    ///                   chance of address(0) to exercise InvalidPolicyAdmin.
    /// @param callerSeed Seed used to choose the transaction sender.
    function handler_revokeWalletPolicyAdmin(uint256 walletSeed, uint256 adminSeed, uint256 callerSeed) public {
        PolicyWalletAdminParams memory params = walletPolicyAdminPreconditions(walletSeed, adminSeed, callerSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(policyRegistry.revokeWalletPolicyAdmin.selector, params.wallet, params.admin),
            params.caller
        );

        revokeWalletPolicyAdminPostconditions(success, returnData, params);
    }

    // =========================================================================
    // Policy epoch
    // =========================================================================

    /// @notice Attempts to advance a wallet policy epoch through the CompanyWallet owner surface.
    /// @dev Preconditions prepare current-epoch delegated admin, user-role, operation-role, and module state,
    /// then postconditions verify that a successful epoch advance makes that state unreachable while preserving
    /// sibling wallet state. Also covers owner-only and non-zero reason failure paths.
    /// @param walletSeed Seed used to choose policyWalletA or policyWalletB.
    /// @param pathSeed   Seed used to choose success, zero-reason, or unauthorized paths.
    /// @param stateSeed  Seed used to derive delegated policy state and non-zero reason material.
    function handler_advancePolicyEpoch(uint256 walletSeed, uint256 pathSeed, uint256 stateSeed) public {
        PolicyEpochAdvanceParams memory params = policyEpochAdvancePreconditions(walletSeed, pathSeed, stateSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            params.wallet, abi.encodeCall(CompanyWallet.advancePolicyEpoch, (params.reason)), params.caller
        );

        advancePolicyEpochPostconditions(success, returnData, params);
    }

    // =========================================================================
    // User roles — single-item
    // =========================================================================

    /// @notice Attempts to grant user roles for a wallet via the scalar overload.
    /// @dev Tests the happy path (PR-20) and all expected failure modes:
    /// unauthorized caller (PR-24), zero user address (ZeroAddress), zero role
    /// bitmap (ZeroRoles), and already-granted bits (UserRolesAlreadyGranted).
    /// Role bitmap is allowed to be zero so the ZeroRoles path is exercised.
    /// On success, sibling wallet isolation is verified via PR-23.
    /// @param walletSeed Seed used to choose the target wallet.
    /// @param callerSeed Seed used to choose the transaction sender.
    /// @param userSeed   Seed used to choose a user address; ~1-in-4 chance of
    ///                   address(0) to exercise the ZeroAddress revert path.
    /// @param rolesSeed  Seed used to derive the role bitmap; may produce zero.
    function handler_grantUserRoles(uint256 walletSeed, uint256 callerSeed, uint256 userSeed, uint256 rolesSeed)
        public
    {
        PolicyUserRolesParams memory params =
            policyUserRolesPreconditions(walletSeed, callerSeed, userSeed, rolesSeed, true);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(_GRANT_USER_ROLES_SELECTOR, params.wallet, params.user, params.roles),
            params.caller
        );

        grantUserRolesPostconditions(success, returnData, params);
    }

    /// @notice Attempts to revoke user roles for a wallet via the scalar overload.
    /// @dev Tests the happy path (PR-21) and all expected failure modes:
    /// unauthorized caller (PR-24), zero user address (ZeroAddress), zero role
    /// bitmap (ZeroRoles), and not-yet-granted bits (UserRolesNotGranted).
    /// On success, sibling wallet isolation is verified via PR-23.
    /// @param walletSeed Seed used to choose the target wallet.
    /// @param callerSeed Seed used to choose the transaction sender.
    /// @param userSeed   Seed used to choose a user address; ~1-in-4 chance of
    ///                   address(0) to exercise the ZeroAddress revert path.
    /// @param rolesSeed  Seed used to derive the role bitmap; may produce zero.
    function handler_revokeUserRoles(uint256 walletSeed, uint256 callerSeed, uint256 userSeed, uint256 rolesSeed)
        public
    {
        PolicyUserRolesParams memory params =
            policyUserRolesPreconditions(walletSeed, callerSeed, userSeed, rolesSeed, true);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(_REVOKE_USER_ROLES_SELECTOR, params.wallet, params.user, params.roles),
            params.caller
        );

        revokeUserRolesPostconditions(success, returnData, params);
    }

    /// @notice Attempts to overwrite user roles for a wallet via the scalar overload.
    /// @dev Tests the exact-overwrite path (PR-22) including clearing to zero.
    /// Also covers unauthorized callers (PR-24) and zero user (ZeroAddress).
    /// On success, sibling wallet isolation is verified via PR-23.
    /// @param walletSeed Seed used to choose the target wallet.
    /// @param callerSeed Seed used to choose the transaction sender.
    /// @param userSeed   Seed used to choose a user address; ~1-in-4 chance of
    ///                   address(0) to exercise the ZeroAddress revert path.
    /// @param rolesSeed  Seed used to derive the exact role bitmap to store (may be zero).
    function handler_setUserRoles(uint256 walletSeed, uint256 callerSeed, uint256 userSeed, uint256 rolesSeed) public {
        PolicyUserRolesParams memory params =
            policyUserRolesPreconditions(walletSeed, callerSeed, userSeed, rolesSeed, true);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(_SET_USER_ROLES_SELECTOR, params.wallet, params.user, params.roles),
            params.caller
        );

        setUserRolesPostconditions(success, returnData, params);
    }

    // =========================================================================
    // User roles — batch overloads
    // =========================================================================

    /// @notice Attempts to grant user roles via the batch overload (single-element array).
    /// @dev Exercises the batch loop path with the same invariants as the scalar
    /// form. The single-element array keeps the handler deterministic while still
    /// covering the overload's iteration logic. Zero user and zero roles paths
    /// are exercised identically to the scalar form.
    /// @param walletSeed Seed used to choose the target wallet.
    /// @param callerSeed Seed used to choose the transaction sender.
    /// @param userSeed   Seed used to choose a user address; ~1-in-4 chance of
    ///                   address(0) to exercise the ZeroAddress revert path.
    /// @param rolesSeed  Seed used to derive the role bitmap; may produce zero.
    function handler_grantUserRolesBatch(uint256 walletSeed, uint256 callerSeed, uint256 userSeed, uint256 rolesSeed)
        public
    {
        PolicyUserRolesParams memory params =
            policyUserRolesPreconditions(walletSeed, callerSeed, userSeed, rolesSeed, true);

        address[] memory users = new address[](1);
        users[0] = params.user;

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(_GRANT_USER_ROLES_BATCH_SELECTOR, params.wallet, users, params.roles),
            params.caller
        );

        grantUserRolesPostconditions(success, returnData, params);
    }

    /// @notice Attempts to revoke user roles via the batch overload (single-element array).
    /// @dev Exercises the batch loop path with the same invariants as the scalar
    /// form. Zero user and zero roles paths are exercised identically to the
    /// scalar form.
    /// @param walletSeed Seed used to choose the target wallet.
    /// @param callerSeed Seed used to choose the transaction sender.
    /// @param userSeed   Seed used to choose a user address; ~1-in-4 chance of
    ///                   address(0) to exercise the ZeroAddress revert path.
    /// @param rolesSeed  Seed used to derive the role bitmap; may produce zero.
    function handler_revokeUserRolesBatch(uint256 walletSeed, uint256 callerSeed, uint256 userSeed, uint256 rolesSeed)
        public
    {
        PolicyUserRolesParams memory params =
            policyUserRolesPreconditions(walletSeed, callerSeed, userSeed, rolesSeed, true);

        address[] memory users = new address[](1);
        users[0] = params.user;

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(_REVOKE_USER_ROLES_BATCH_SELECTOR, params.wallet, users, params.roles),
            params.caller
        );

        revokeUserRolesPostconditions(success, returnData, params);
    }

    /// @notice Attempts to overwrite user roles via the batch overload (single-element arrays).
    /// @dev The batch setUserRoles overload requires users.length == roles.length;
    /// both single-element arrays satisfy this. Covers the zero-roles clear
    /// path (PR-22) and zero user (ZeroAddress) revert path.
    /// @param walletSeed Seed used to choose the target wallet.
    /// @param callerSeed Seed used to choose the transaction sender.
    /// @param userSeed   Seed used to choose a user address; ~1-in-4 chance of
    ///                   address(0) to exercise the ZeroAddress revert path.
    /// @param rolesSeed  Seed used to derive the exact role bitmap (may be zero).
    function handler_setUserRolesBatch(uint256 walletSeed, uint256 callerSeed, uint256 userSeed, uint256 rolesSeed)
        public
    {
        PolicyUserRolesParams memory params =
            policyUserRolesPreconditions(walletSeed, callerSeed, userSeed, rolesSeed, true);

        address[] memory users = new address[](1);
        users[0] = params.user;
        uint256[] memory roles = new uint256[](1);
        roles[0] = params.roles;

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(_SET_USER_ROLES_BATCH_SELECTOR, params.wallet, users, roles),
            params.caller
        );

        setUserRolesPostconditions(success, returnData, params);
    }

    // =========================================================================
    // Operation roles — single-item
    // =========================================================================

    /// @notice Attempts to grant roles for a wallet operation via the scalar overload.
    /// @dev Tests the happy path (PR-30) and all expected failure modes:
    /// unauthorized caller (PR-34), zero role bitmap (ZeroRoles), and
    /// already-granted bits (OperationRolesAlreadyGranted). Role bitmap is
    /// allowed to be zero so the ZeroRoles path is exercised. Sibling wallet
    /// isolation is verified via PR-33.
    /// @param walletSeed    Seed used to choose the target wallet.
    /// @param callerSeed    Seed used to choose the transaction sender.
    /// @param operationSeed Seed used to select setFlag or setNumber as the
    ///                      target operation on FuzzPolicyTarget.
    /// @param rolesSeed     Seed used to derive the role bitmap; may produce zero.
    function handler_grantOperationRoles(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 rolesSeed
    ) public {
        PolicyOperationRolesParams memory params = policyOperationRolesPreconditions(
            walletSeed, callerSeed, operationSeed, rolesSeed, true
        );

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(
                _GRANT_OPERATION_ROLES_SELECTOR, params.wallet, params.target, params.selector, params.roles
            ),
            params.caller
        );

        grantOperationRolesPostconditions(success, returnData, params);
    }

    /// @notice Attempts to revoke roles for a wallet operation via the scalar overload.
    /// @dev Tests the happy path (PR-31) and all expected failure modes:
    /// unauthorized caller (PR-34), zero role bitmap (ZeroRoles), and
    /// not-yet-granted bits (OperationRolesNotGranted). Sibling wallet
    /// isolation is verified via PR-33.
    /// @param walletSeed    Seed used to choose the target wallet.
    /// @param callerSeed    Seed used to choose the transaction sender.
    /// @param operationSeed Seed used to select the target operation.
    /// @param rolesSeed     Seed used to derive the role bitmap; may produce zero.
    function handler_revokeOperationRoles(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 rolesSeed
    ) public {
        PolicyOperationRolesParams memory params = policyOperationRolesPreconditions(
            walletSeed, callerSeed, operationSeed, rolesSeed, true
        );

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(
                _REVOKE_OPERATION_ROLES_SELECTOR, params.wallet, params.target, params.selector, params.roles
            ),
            params.caller
        );

        revokeOperationRolesPostconditions(success, returnData, params);
    }

    /// @notice Attempts to overwrite roles for a wallet operation via the scalar overload.
    /// @dev Tests the exact-overwrite path (PR-32) including clearing to zero.
    /// Also covers unauthorized callers (PR-34). Sibling wallet isolation is
    /// verified via PR-33.
    /// @param walletSeed    Seed used to choose the target wallet.
    /// @param callerSeed    Seed used to choose the transaction sender.
    /// @param operationSeed Seed used to select the target operation.
    /// @param rolesSeed     Seed used to derive the exact role bitmap (may be zero).
    function handler_setOperationRoles(uint256 walletSeed, uint256 callerSeed, uint256 operationSeed, uint256 rolesSeed)
        public
    {
        PolicyOperationRolesParams memory params =
            policyOperationRolesPreconditions(walletSeed, callerSeed, operationSeed, rolesSeed, true);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(
                _SET_OPERATION_ROLES_SELECTOR, params.wallet, params.target, params.selector, params.roles
            ),
            params.caller
        );

        setOperationRolesPostconditions(success, returnData, params);
    }

    // =========================================================================
    // Operation roles — batch overloads
    // =========================================================================

    /// @notice Attempts to grant operation roles via the batch overload (single-element array).
    /// @dev Single-element OperationRoles array exercises the batch iteration
    /// path with the same invariants as the scalar form. Zero role bitmap is
    /// allowed so the ZeroRoles path is exercised.
    /// @param walletSeed    Seed used to choose the target wallet.
    /// @param callerSeed    Seed used to choose the transaction sender.
    /// @param operationSeed Seed used to select the target operation.
    /// @param rolesSeed     Seed used to derive the role bitmap; may produce zero.
    function handler_grantOperationRolesBatch(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 rolesSeed
    ) public {
        PolicyOperationRolesParams memory params = policyOperationRolesPreconditions(
            walletSeed, callerSeed, operationSeed, rolesSeed, true
        );

        OperationRoles[] memory operations = new OperationRoles[](1);
        operations[0] = OperationRoles({target: params.target, selector: params.selector, roles: params.roles});

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(_GRANT_OPERATION_ROLES_BATCH_SELECTOR, params.wallet, operations),
            params.caller
        );

        grantOperationRolesPostconditions(success, returnData, params);
    }

    /// @notice Attempts to revoke operation roles via the batch overload (single-element array).
    /// @dev Single-element array exercises the batch iteration path with the
    /// same invariants as the scalar form. Zero role bitmap is allowed.
    /// @param walletSeed    Seed used to choose the target wallet.
    /// @param callerSeed    Seed used to choose the transaction sender.
    /// @param operationSeed Seed used to select the target operation.
    /// @param rolesSeed     Seed used to derive the role bitmap; may produce zero.
    function handler_revokeOperationRolesBatch(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 rolesSeed
    ) public {
        PolicyOperationRolesParams memory params = policyOperationRolesPreconditions(
            walletSeed, callerSeed, operationSeed, rolesSeed, true
        );

        OperationRoles[] memory operations = new OperationRoles[](1);
        operations[0] = OperationRoles({target: params.target, selector: params.selector, roles: params.roles});

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(_REVOKE_OPERATION_ROLES_BATCH_SELECTOR, params.wallet, operations),
            params.caller
        );

        revokeOperationRolesPostconditions(success, returnData, params);
    }

    /// @notice Attempts to overwrite operation roles via the batch overload (single-element array).
    /// @dev Covers the exact-overwrite path (PR-32) including clearing to zero.
    /// @param walletSeed    Seed used to choose the target wallet.
    /// @param callerSeed    Seed used to choose the transaction sender.
    /// @param operationSeed Seed used to select the target operation.
    /// @param rolesSeed     Seed used to derive the exact role bitmap (may be zero).
    function handler_setOperationRolesBatch(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 rolesSeed
    ) public {
        PolicyOperationRolesParams memory params = policyOperationRolesPreconditions(
            walletSeed, callerSeed, operationSeed, rolesSeed, true
        );

        OperationRoles[] memory operations = new OperationRoles[](1);
        operations[0] = OperationRoles({target: params.target, selector: params.selector, roles: params.roles});

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(_SET_OPERATION_ROLES_BATCH_SELECTOR, params.wallet, operations),
            params.caller
        );

        setOperationRolesPostconditions(success, returnData, params);
    }

    // =========================================================================
    // Operation module — single-item and batch
    // =========================================================================

    /// @notice Attempts to configure the policy module for a wallet operation.
    /// @dev Module is selected from: zero address (clear), policyAllowModule,
    /// policyDenyModule, policyRevertingModule, or policyInvalidReturnModule.
    /// Covers unauthorized callers (PR-42) and non-allowlisted modules
    /// (PolicyModuleNotAllowed). Sibling wallet isolation is verified via PR-41.
    /// @param walletSeed    Seed used to choose the target wallet.
    /// @param callerSeed    Seed used to choose the transaction sender.
    /// @param operationSeed Seed used to select the target operation.
    /// @param moduleSeed    Seed used to select the module address (0 = clear).
    function handler_setOperationModule(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 moduleSeed
    ) public {
        PolicyOperationModuleParams memory params =
            policyOperationModulePreconditions(walletSeed, callerSeed, operationSeed, moduleSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(
                _SET_OPERATION_MODULE_SELECTOR, params.wallet, params.target, params.selector, params.module
            ),
            params.caller
        );

        setOperationModulePostconditions(success, returnData, params);
    }

    /// @notice Attempts to configure the policy module via the batch overload (single-element array).
    /// @dev Exercises the batch iteration path with the same invariants as the
    /// scalar form. Module selection and authorization checks are identical.
    /// @param walletSeed    Seed used to choose the target wallet.
    /// @param callerSeed    Seed used to choose the transaction sender.
    /// @param operationSeed Seed used to select the target operation.
    /// @param moduleSeed    Seed used to select the module address (0 = clear).
    function handler_setOperationModuleBatch(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 moduleSeed
    ) public {
        PolicyOperationModuleParams memory params =
            policyOperationModulePreconditions(walletSeed, callerSeed, operationSeed, moduleSeed);

        OperationModule[] memory operations = new OperationModule[](1);
        operations[0] = OperationModule({target: params.target, selector: params.selector, module: params.module});

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(_SET_OPERATION_MODULE_BATCH_SELECTOR, params.wallet, operations),
            params.caller
        );

        setOperationModulePostconditions(success, returnData, params);
    }

    // =========================================================================
    // Global config
    // =========================================================================

    /// @notice Sets global allowlist status for one of the fuzz policy modules.
    /// @dev Always called as the registry owner (address(this)) so any revert
    /// is unexpected and triggers invariant PR-52. Covers both allow and
    /// disallow transitions (PR-50).
    /// @param moduleSeed Seed used to select one of the four non-zero fuzz modules.
    /// @param allowed    Whether the module should be allowlisted.
    function handler_setPolicyModuleAllowed(uint256 moduleSeed, bool allowed) public {
        PolicyModuleAllowedParams memory params = policyModuleAllowedPreconditions(moduleSeed, allowed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(policyRegistry.setPolicyModuleAllowed.selector, params.module, params.allowed),
            governance
        );

        setPolicyModuleAllowedPostconditions(success, returnData, params);
    }

    /// @notice Sets compact metadata for a role id.
    /// @dev Always called as the registry owner so any revert is unexpected and
    /// triggers invariant PR-53. Role id is clamped to [0, 255] (PR-51).
    /// @param roleSeed  Seed used to derive a role id in [0, 255].
    /// @param labelSeed Seed used to derive the role label bytes32.
    function handler_setRoleLabel(uint256 roleSeed, uint256 labelSeed) public {
        PolicyRoleLabelParams memory params = policyRoleLabelPreconditions(roleSeed, labelSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(policyRegistry.setRoleLabel.selector, params.roleId, params.label),
            governance
        );

        setRoleLabelPostconditions(success, returnData, params);
    }

    // =========================================================================
    // View and execution checks
    // =========================================================================

    /// @notice Checks view-only policy lookup behavior against the harness model.
    /// @dev Calls canExecute, checkOperationModule, and computeOperationKey
    /// against both structurally valid requests (requestKindSeed == 0) and
    /// structurally invalid ones — zero wallet, zero caller, zero target, or
    /// calldata shorter than four bytes. Verifies invariants PR-60, PR-61,
    /// and PR-63.
    /// @param walletSeed      Seed used to choose the queried wallet.
    /// @param callerSeed      Seed used to choose the queried caller.
    /// @param operationSeed   Seed used to select the target operation.
    /// @param dataSeed        Seed used to derive operation calldata.
    /// @param requestKindSeed Selects a valid (0) or invalid (1–4) request
    ///                        field: 1 = zero wallet, 2 = zero caller,
    ///                        3 = zero target, 4 = short calldata.
    function handler_checkPolicyLookup(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 dataSeed,
        uint256 requestKindSeed
    ) public {
        PolicyLookupParams memory params = policyLookupPreconditions(
            walletSeed, callerSeed, operationSeed, dataSeed, requestKindSeed
        );

        policyLookupPostconditions(params);
    }

    /// @notice Seeds an allow-module policy and checks the module-authorized canExecute branch.
    /// @param walletSeed Seed used to choose the queried wallet.
    /// @param callerSeed Seed used to choose the queried caller.
    /// @param operationSeed Seed used to select the target operation.
    /// @param dataSeed Seed used to derive operation calldata and roles.
    function handler_checkPolicyLookupWithAllowModule(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 dataSeed
    ) public {
        address owner;
        PolicyLookupParams memory params;
        (params.wallet, owner,) = _pickPolicyWallet(walletSeed);
        params.caller = _pickPolicyUser(callerSeed);
        PolicyOperationData memory operation = _pickPolicyOperation(operationSeed, dataSeed);
        params.target = operation.target;
        params.data = operation.data;

        uint256 roles = _normalizePolicyRoles(dataSeed, false);
        if (!policyRegistry.isPolicyModuleAllowed(address(policyAllowModule))) {
            (bool allowSuccess,) = fl.doFunctionCall(
                address(policyRegistry),
                abi.encodeWithSelector(
                    policyRegistry.setPolicyModuleAllowed.selector, address(policyAllowModule), true
                ),
                governance
            );
            policyAllowModuleSeedPostconditions(allowSuccess);
        }

        _seedPolicyOwnerCall(
            abi.encodeWithSelector(_SET_USER_ROLES_SELECTOR, params.wallet, params.caller, roles), owner
        );
        _seedPolicyOwnerCall(
            abi.encodeWithSelector(
                _SET_OPERATION_ROLES_SELECTOR, params.wallet, params.target, operation.selector, roles
            ),
            owner
        );
        _seedPolicyOwnerCall(
            abi.encodeWithSelector(
                _SET_OPERATION_MODULE_SELECTOR,
                params.wallet,
                params.target,
                operation.selector,
                address(policyAllowModule)
            ),
            owner
        );

        policyLookupPostconditions(params);
    }

    /// @notice Exercises CompanyWallet receive, policy-registry update, ERC165 surface, and disabled renounce.
    /// @param walletSeed Seed used to choose policyWalletA or policyWalletB.
    function handler_companyWalletAdminSurface(uint256 walletSeed) public {
        address wallet;
        address owner;
        (wallet, owner,) = _pickPolicyWallet(walletSeed);

        (bool receiveSuccess, bytes memory receiveReturnData) = fl.doFunctionCall(wallet, "", POLICY_OUTSIDER);
        companyWalletSuccessPostconditions(receiveSuccess, receiveReturnData);

        (bool setPolicySuccess, bytes memory setPolicyReturnData) = fl.doFunctionCall(
            wallet, abi.encodeWithSelector(CompanyWallet.setPolicyRegistry.selector, address(policyRegistry)), owner
        );
        companyWalletSuccessPostconditions(setPolicySuccess, setPolicyReturnData);

        // Exercise the ERC165 surface across both advertised ids (ICompanyWallet, IERC721Receiver), the inherited
        // IERC165 id (super), and an unsupported id — covering every leg of `supportsInterface`.
        bytes4[4] memory walletInterfaceIds = [
            type(ICompanyWallet).interfaceId,
            type(IERC721Receiver).interfaceId,
            type(IERC165).interfaceId,
            ERC165_INVALID_INTERFACE_ID
        ];
        for (uint256 i; i < walletInterfaceIds.length; ++i) {
            (bool supportsSuccess, bytes memory supportsReturnData) = fl.doFunctionCall(
                wallet,
                abi.encodeWithSelector(CompanyWallet.supportsInterface.selector, walletInterfaceIds[i]),
                POLICY_OUTSIDER
            );
            companyWalletSuccessPostconditions(supportsSuccess, supportsReturnData);
        }

        (bool renounceSuccess, bytes memory renounceReturnData) =
            fl.doFunctionCall(wallet, abi.encodeWithSignature("renounceOwnership()"), owner);
        companyWalletRenouncePostconditions(renounceSuccess, renounceReturnData);
    }

    /// @notice Attempts execution through CompanyWallet and checks registry enforcement.
    /// @dev The wallet owner always bypasses the policy check. Non-owners are
    /// subject to PolicyRegistry.canExecute. Verifies PR-62: rejected calls
    /// must not mutate policyTarget state, and accepted calls must increment
    /// callCount with the wallet address as lastCaller.
    /// @param walletSeed    Seed used to choose the executing wallet.
    /// @param callerSeed    Seed used to choose the transaction sender.
    /// @param operationSeed Seed used to select the target operation.
    /// @param dataSeed      Seed used to derive operation calldata.
    function handler_executePolicyCall(uint256 walletSeed, uint256 callerSeed, uint256 operationSeed, uint256 dataSeed)
        public
    {
        PolicyExecuteParams memory params = policyExecutePreconditions(walletSeed, callerSeed, operationSeed, dataSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            params.wallet,
            abi.encodeWithSelector(CompanyWallet.execute.selector, params.target, params.value, params.data),
            params.caller
        );

        policyExecutePostconditions(success, returnData, params);
    }

    // =========================================================================
    // Policy version (ownership epoch) monotonicity and reset
    // =========================================================================

    /// @notice Advances the dedicated epoch wallet's policy version and checks reset + monotonicity.
    /// @dev Seeds wallet-scoped policy (user roles, wallet policy admin, operation roles, and an
    /// operation module) at the current epoch as the wallet owner, then transfers wallet ownership
    /// to rotate the ownership epoch. Verifies PR-70 (the version increments by exactly one and never
    /// decreases), PR-71 (the seeded state existed at the previous epoch and is reset at the new
    /// epoch), and PR-72 (the transfer does not unexpectedly revert). A dedicated wallet is used so
    /// the epoch advance does not disturb the epoch-scoped state of policyWalletA/B.
    /// @param seed Seed used to derive the seeded user, admin, operation, and role bitmap.
    function handler_advancePolicyVersionResetsState(uint256 seed) public {
        PolicyEpochParams memory params = policyEpochPreconditions(seed);

        // Seed wallet-scoped policy at the current epoch as the wallet owner.
        _seedPolicyStateAsOwner(params);

        // Capture the populated before-state at the current epoch.
        uint256 userRolesBefore = policyRegistry.getUserRoles(params.wallet, params.user);
        bool adminBefore = policyRegistry.isWalletPolicyAdmin(params.wallet, params.admin);
        uint256 operationRolesBefore = policyRegistry.getOperationRoles(params.wallet, params.target, params.selector);
        address moduleBefore = policyRegistry.getOperationModule(params.wallet, params.target, params.selector);
        uint256 epochBefore = policyEpochWallet.ownershipEpoch();

        // Advance the policy version by transferring wallet ownership to the rotated owner.
        // transferOwnership is inherited from Solady Ownable, so encode by signature.
        (bool success,) = fl.doFunctionCall(
            params.wallet, abi.encodeWithSignature("transferOwnership(address)", params.newOwner), params.currentOwner
        );

        uint256 epochAfter = policyEpochWallet.ownershipEpoch();

        advancePolicyVersionPostconditions(
            success, params, epochBefore, epochAfter, userRolesBefore, adminBefore, operationRolesBefore, moduleBefore
        );
    }

    /// @dev Seeds the four wallet-scoped policy dimensions at the current epoch as the wallet owner.
    /// Each grant must succeed; a silently reverted grant would make the PR-71 reset check vacuous.
    function _seedPolicyStateAsOwner(PolicyEpochParams memory params) internal {
        _seedPolicyOwnerCall(
            abi.encodeWithSelector(_GRANT_USER_ROLES_SELECTOR, params.wallet, params.user, params.roles),
            params.currentOwner
        );
        _seedPolicyOwnerCall(
            abi.encodeWithSelector(policyRegistry.grantWalletPolicyAdmin.selector, params.wallet, params.admin),
            params.currentOwner
        );
        _seedPolicyOwnerCall(
            abi.encodeWithSelector(
                _GRANT_OPERATION_ROLES_SELECTOR, params.wallet, params.target, params.selector, params.roles
            ),
            params.currentOwner
        );
        // The operation module is only seeded when the allow-module is currently allowlisted (see
        // policyEpochPreconditions); otherwise setOperationModule would revert with PolicyModuleNotAllowed.
        if (params.moduleSeeded) {
            _seedPolicyOwnerCall(
                abi.encodeWithSelector(
                    _SET_OPERATION_MODULE_SELECTOR, params.wallet, params.target, params.selector, params.module
                ),
                params.currentOwner
            );
        }
    }

    function _seedPolicyOwnerCall(bytes memory data, address caller) internal {
        (bool success,) = fl.doFunctionCall(address(policyRegistry), data, caller);
        policyOwnerSeedPostconditions(success);
    }
}
