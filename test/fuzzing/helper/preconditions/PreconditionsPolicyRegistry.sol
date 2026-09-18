// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, gas-struct-packing */

import {PolicyRegistryHelpers} from "../PolicyRegistryHelpers.sol";
import {FuzzPolicyTarget} from "../../mocks/PolicyRegistryFuzzMocks.sol";
import {PreconditionsBase} from "./PreconditionsBase.sol";

abstract contract PreconditionsPolicyRegistry is PolicyRegistryHelpers, PreconditionsBase {
    // -------------------------------------------------------------------------
    // Parameter structs
    // -------------------------------------------------------------------------

    // PolicyRegistry does not expose enumerable mapping keys, so this harness
    // keeps the exact before-state needed for each action in these params
    // instead of routing PolicyRegistry state through BeforeAfter.sol.

    struct PolicyWalletAdminParams {
        address wallet;
        address otherWallet;
        address owner;
        address caller;
        address admin;
        bool callerIsOwner;
        bool wasGranted;
        bool otherWalletWasGranted;
    }

    struct PolicyEpochAdvanceParams {
        address wallet;
        address otherWallet;
        address owner;
        address caller;
        address admin;
        address user;
        address target;
        bytes4 selector;
        bytes data;
        uint256 roles;
        bytes32 reason;
    }

    struct PolicyUserRolesParams {
        address wallet;
        address otherWallet;
        address owner;
        address caller;
        address user;
        uint256 roles;
        uint256 beforeRoles;
        uint256 otherWalletBeforeRoles;
        bool operatorAuthorized;
    }

    struct PolicyOperationRolesParams {
        address wallet;
        address otherWallet;
        address owner;
        address caller;
        address target;
        bytes4 selector;
        uint256 roles;
        uint256 beforeRoles;
        uint256 otherWalletBeforeRoles;
        bool operatorAuthorized;
    }

    struct PolicyOperationModuleParams {
        address wallet;
        address otherWallet;
        address owner;
        address caller;
        address target;
        bytes4 selector;
        address module;
        address beforeModule;
        address otherWalletBeforeModule;
        bool operatorAuthorized;
        bool moduleAllowed;
    }

    struct PolicyModuleAllowedParams {
        address module;
        bool allowed;
        bool beforeAllowed;
    }

    struct PolicyRoleLabelParams {
        uint8 roleId;
        bytes32 label;
        bytes32 beforeLabel;
    }

    struct PolicyOperationData {
        address target;
        bytes4 selector;
        bytes data;
        bool isSetFlag;
        bool expectedFlagValue;
        uint256 expectedNumberValue;
    }

    struct PolicyLookupParams {
        address wallet;
        address caller;
        address target;
        uint256 value;
        bytes data;
    }

    struct PolicyExecuteParams {
        address wallet;
        address owner;
        address caller;
        address target;
        uint256 value;
        bytes data;
        bool expectedAuthorized;
        uint256 beforeCallCount;
        bool beforeFlag;
        uint256 beforeNumber;
        bool isSetFlag;
        bool expectedFlagValue;
        uint256 expectedNumberValue;
    }

    struct PolicyEpochParams {
        address wallet;
        address currentOwner;
        address newOwner;
        address user;
        address admin;
        address target;
        bytes4 selector;
        address module;
        bool moduleSeeded;
        uint256 roles;
    }

    // -------------------------------------------------------------------------
    // Precondition builders
    // -------------------------------------------------------------------------

    function walletPolicyAdminPreconditions(uint256 walletSeed, uint256 adminSeed, uint256 callerSeed)
        internal
        returns (PolicyWalletAdminParams memory params)
    {
        (params.wallet, params.owner, params.otherWallet) = _pickPolicyWallet(walletSeed);
        params.admin = _pickPolicyAdminMaybeZero(adminSeed);
        params.caller = _pickPolicyCaller(params.owner, callerSeed);
        params.callerIsOwner = params.caller == params.owner;
        params.wasGranted = policyRegistry.isWalletPolicyAdmin(params.wallet, params.admin);
        params.otherWalletWasGranted = policyRegistry.isWalletPolicyAdmin(params.otherWallet, params.admin);
    }

    function policyEpochAdvancePreconditions(uint256 walletSeed, uint256 pathSeed, uint256 stateSeed)
        internal
        returns (PolicyEpochAdvanceParams memory params)
    {
        (params.wallet, params.owner, params.otherWallet) = _pickPolicyWallet(walletSeed);
        params.admin = POLICY_ADMINS[_derivePolicyEpochSeed(stateSeed, "admin") % POLICY_ADMINS.length];
        params.user = users[_derivePolicyEpochSeed(stateSeed, "user") % users.length];
        params.caller = _pickPolicyEpochAdvanceCaller(params.owner, params.admin, pathSeed);

        uint256 rolesSeed = (_derivePolicyEpochSeed(stateSeed, "roles") % POLICY_MAX_ROLE_BITMAP) + 1;
        PolicyOperationData memory operation = _pickPolicyOperation(
            _derivePolicyEpochSeed(stateSeed, "operation") % 2,
            _derivePolicyEpochSeed(stateSeed, "data") % (POLICY_MAX_ROLE_BITMAP + 1)
        );
        params.target = operation.target;
        params.selector = operation.selector;
        params.data = operation.data;
        params.roles = rolesSeed;
        params.reason = _pickPolicyEpochAdvanceReason(pathSeed, stateSeed);

        _seedPolicyEpochAdvanceState(params);
        // Capture both the selected wallet and its sibling after seeding: PR-70/71/73/75
        // compare the selected wallet, while PR-74 proves sibling wallet isolation.
        _beforePolicyRegistry(params.wallet, params.admin, params.user, params.target, params.selector, 0, params.data);
        _beforePolicyRegistry(
            params.otherWallet, params.admin, params.user, params.target, params.selector, 0, params.data
        );
    }

    function _seedPolicyEpochAdvanceState(PolicyEpochAdvanceParams memory params) internal {
        if (!policyRegistry.isWalletPolicyAdmin(params.wallet, params.admin)) {
            fl.doFunctionCall(
                address(policyRegistry),
                abi.encodeWithSelector(policyRegistry.grantWalletPolicyAdmin.selector, params.wallet, params.admin),
                params.owner
            );
        }

        fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(_SET_USER_ROLES_SELECTOR, params.wallet, params.user, params.roles),
            params.owner
        );

        fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(
                _SET_OPERATION_ROLES_SELECTOR, params.wallet, params.target, params.selector, params.roles
            ),
            params.owner
        );

        if (!policyRegistry.isPolicyModuleAllowed(address(policyAllowModule))) {
            fl.doFunctionCall(
                address(policyRegistry),
                abi.encodeWithSelector(
                    policyRegistry.setPolicyModuleAllowed.selector, address(policyAllowModule), true
                ),
                governance
            );
        }

        fl.doFunctionCall(
            address(policyRegistry),
            abi.encodeWithSelector(
                _SET_OPERATION_MODULE_SELECTOR,
                params.wallet,
                params.target,
                params.selector,
                address(policyAllowModule)
            ),
            params.owner
        );
    }

    function policyUserRolesPreconditions(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 userSeed,
        uint256 rolesSeed,
        bool allowZeroRoles
    ) internal returns (PolicyUserRolesParams memory params) {
        (params.wallet, params.owner, params.otherWallet) = _pickPolicyWallet(walletSeed);
        params.caller = _pickPolicyCaller(params.owner, callerSeed);
        params.user = _pickPolicyUserMaybeZero(userSeed);
        params.roles = _normalizePolicyRoles(rolesSeed, allowZeroRoles);
        params.beforeRoles = policyRegistry.getUserRoles(params.wallet, params.user);
        params.otherWalletBeforeRoles = policyRegistry.getUserRoles(params.otherWallet, params.user);
        params.operatorAuthorized = _isPolicyOperator(params.wallet, params.owner, params.caller);
    }

    function policyOperationRolesPreconditions(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 rolesSeed,
        bool allowZeroRoles
    ) internal returns (PolicyOperationRolesParams memory params) {
        PolicyOperationData memory operation = _pickPolicyOperation(operationSeed, rolesSeed);
        (params.wallet, params.owner, params.otherWallet) = _pickPolicyWallet(walletSeed);
        params.caller = _pickPolicyCaller(params.owner, callerSeed);
        params.target = operation.target;
        params.selector = operation.selector;
        params.roles = _normalizePolicyRoles(rolesSeed, allowZeroRoles);
        params.beforeRoles = policyRegistry.getOperationRoles(params.wallet, params.target, params.selector);
        params.otherWalletBeforeRoles =
            policyRegistry.getOperationRoles(params.otherWallet, params.target, params.selector);
        params.operatorAuthorized = _isPolicyOperator(params.wallet, params.owner, params.caller);
    }

    function policyOperationModulePreconditions(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 moduleSeed
    ) internal returns (PolicyOperationModuleParams memory params) {
        PolicyOperationData memory operation = _pickPolicyOperation(operationSeed, moduleSeed);
        (params.wallet, params.owner, params.otherWallet) = _pickPolicyWallet(walletSeed);
        params.caller = _pickPolicyCaller(params.owner, callerSeed);
        params.target = operation.target;
        params.selector = operation.selector;
        params.module = _pickPolicyModule(moduleSeed);
        params.beforeModule = policyRegistry.getOperationModule(params.wallet, params.target, params.selector);
        params.otherWalletBeforeModule =
            policyRegistry.getOperationModule(params.otherWallet, params.target, params.selector);
        params.operatorAuthorized = _isPolicyOperator(params.wallet, params.owner, params.caller);
        params.moduleAllowed = params.module == address(0) || policyRegistry.isPolicyModuleAllowed(params.module);
    }

    function policyModuleAllowedPreconditions(uint256 moduleSeed, bool allowed)
        internal
        returns (PolicyModuleAllowedParams memory params)
    {
        params.module = _pickNonZeroPolicyModule(moduleSeed);
        params.allowed = allowed;
        params.beforeAllowed = policyRegistry.isPolicyModuleAllowed(params.module);
    }

    function policyRoleLabelPreconditions(uint256 roleSeed, uint256 labelSeed)
        internal
        returns (PolicyRoleLabelParams memory params)
    {
        params.roleId = uint8(fl.clamp(roleSeed, 0, type(uint8).max));
        params.label = bytes32(labelSeed);
        params.beforeLabel = policyRegistry.roleLabels(params.roleId);
    }

    function policyLookupPreconditions(
        uint256 walletSeed,
        uint256 callerSeed,
        uint256 operationSeed,
        uint256 dataSeed,
        uint256 requestKindSeed
    ) internal returns (PolicyLookupParams memory params) {
        address owner;
        (params.wallet, owner,) = _pickPolicyWallet(walletSeed);
        params.caller = _pickPolicyCaller(owner, callerSeed);
        PolicyOperationData memory operation = _pickPolicyOperation(operationSeed, dataSeed);
        params.target = operation.target;
        params.data = operation.data;

        uint256 requestKind = fl.clamp(requestKindSeed, 0, 4);
        if (requestKind == 1) {
            params.wallet = address(0);
        } else if (requestKind == 2) {
            params.caller = address(0);
        } else if (requestKind == 3) {
            params.target = address(0);
        } else if (requestKind == 4) {
            params.data = hex"123456";
        }
    }

    function policyExecutePreconditions(uint256 walletSeed, uint256 callerSeed, uint256 operationSeed, uint256 dataSeed)
        internal
        returns (PolicyExecuteParams memory params)
    {
        (params.wallet, params.owner,) = _pickPolicyWallet(walletSeed);
        params.caller = _pickPolicyCaller(params.owner, callerSeed);
        PolicyOperationData memory operation = _pickPolicyOperation(operationSeed, dataSeed);
        params.target = operation.target;
        params.data = operation.data;
        // Owner can always execute; for non-owners mirror the on-chain role/module evaluation.
        params.expectedAuthorized = params.caller == params.owner
            || _expectedPolicyCanExecute(params.wallet, params.caller, params.target, 0, params.data);
        params.beforeCallCount = policyTarget.callCount();
        params.beforeFlag = policyTarget.flag();
        params.beforeNumber = policyTarget.number();
        params.isSetFlag = operation.isSetFlag;
        params.expectedFlagValue = operation.expectedFlagValue;
        params.expectedNumberValue = operation.expectedNumberValue;
    }

    /// @dev Builds parameters for advancing the dedicated epoch wallet's policy version.
    /// Ownership rotates between the two known epoch-wallet owners so the transfer always
    /// succeeds (never a self-transfer) and the current owner is always prankable. Roles are
    /// forced non-zero and the module is the allowlisted allow-module so the seeded state is
    /// guaranteed present before the version advance.
    function policyEpochPreconditions(uint256 seed) internal returns (PolicyEpochParams memory params) {
        params.wallet = address(policyEpochWallet);
        params.currentOwner = policyEpochWallet.owner();
        params.newOwner = params.currentOwner == POLICY_EPOCH_WALLET_OWNER_A
            ? POLICY_EPOCH_WALLET_OWNER_B
            : POLICY_EPOCH_WALLET_OWNER_A;

        params.user = _pickPolicyUser(seed);
        params.admin = _pickPolicyAdmin(seed >> 8);
        PolicyOperationData memory operation = _pickPolicyOperation(seed >> 16, seed >> 24);
        params.target = operation.target;
        params.selector = operation.selector;
        // Only seed an operation module when the allow-module is currently allowlisted. The global
        // allowlist can be toggled off by fuzz_setPolicyModuleAllowed, which would make the seeding
        // setOperationModule call revert; in that case the module dimension is skipped while the other
        // three policy dimensions still seed, so the reset proof stays meaningful.
        if (policyRegistry.isPolicyModuleAllowed(address(policyAllowModule))) {
            params.module = address(policyAllowModule);
            params.moduleSeeded = true;
        } else {
            params.module = address(0);
            params.moduleSeeded = false;
        }
        params.roles = _normalizePolicyRoles(seed >> 32, false);
    }

    // -------------------------------------------------------------------------
    // Pickers
    // -------------------------------------------------------------------------

    function _pickPolicyWallet(uint256 walletSeed)
        internal
        returns (address wallet, address owner, address otherWallet)
    {
        if (fl.clamp(walletSeed, 0, 1) == 0) {
            return (address(policyWalletA), POLICY_WALLET_OWNER_A, address(policyWalletB));
        }
        return (address(policyWalletB), POLICY_WALLET_OWNER_B, address(policyWalletA));
    }

    function _pickPolicyAdmin(uint256 adminSeed) internal returns (address) {
        return POLICY_ADMINS[fl.clamp(adminSeed, 0, POLICY_ADMINS.length - 1)];
    }

    /// @dev ~1-in-4 chance of address(0) to exercise the InvalidPolicyAdmin revert path.
    function _pickPolicyAdminMaybeZero(uint256 adminSeed) internal returns (address) {
        uint256 option = fl.clamp(adminSeed, 0, POLICY_ADMINS.length);
        if (option == 0) return address(0);
        return POLICY_ADMINS[option - 1];
    }

    function _pickPolicyUser(uint256 userSeed) internal returns (address) {
        return users[fl.clamp(userSeed, 0, users.length - 1)];
    }

    /// @dev ~1-in-4 chance of address(0) to exercise the ZeroAddress revert path.
    function _pickPolicyUserMaybeZero(uint256 userSeed) internal returns (address) {
        uint256 option = fl.clamp(userSeed, 0, users.length);
        if (option == 0) return address(0);
        return users[option - 1];
    }

    function _pickPolicyCaller(address owner, uint256 callerSeed) internal returns (address caller) {
        uint256 option = fl.clamp(callerSeed, 0, 7);
        if (option == 0) return owner;
        if (option < 4) return POLICY_ADMINS[option - 1];
        if (option < 7) return users[option - 4];
        return POLICY_OUTSIDER;
    }

    function _pickPolicyEpochAdvanceCaller(address owner, address admin, uint256 callerSeed)
        internal
        pure
        returns (address caller)
    {
        uint256 option = callerSeed % 4;
        if (option < 2) return owner;
        if (option == 2) return admin;
        return POLICY_OUTSIDER;
    }

    function _pickPolicyEpochAdvanceReason(uint256 pathSeed, uint256 stateSeed) internal pure returns (bytes32 reason) {
        if (pathSeed % 4 == 1) {
            return bytes32(0);
        }
        return keccak256(abi.encodePacked("FUZZ_POLICY_EPOCH_ADVANCE", stateSeed));
    }

    function _derivePolicyEpochSeed(uint256 seed, string memory salt) internal pure returns (uint256 derivedSeed) {
        return uint256(keccak256(abi.encode(seed, salt)));
    }

    function _normalizePolicyRoles(uint256 rolesSeed, bool allowZeroRoles) internal returns (uint256 roles) {
        if (allowZeroRoles) {
            return fl.clamp(rolesSeed, 0, POLICY_MAX_ROLE_BITMAP);
        }
        return fl.clamp(rolesSeed, 1, POLICY_MAX_ROLE_BITMAP);
    }

    function _pickPolicyOperation(uint256 operationSeed, uint256 dataSeed)
        internal
        returns (PolicyOperationData memory operation)
    {
        operation.target = address(policyTarget);
        if (fl.clamp(operationSeed, 0, 1) == 0) {
            bool flagValue = dataSeed % 2 == 1;
            operation.selector = FuzzPolicyTarget.setFlag.selector;
            operation.data = abi.encodeWithSelector(operation.selector, flagValue);
            operation.isSetFlag = true;
            operation.expectedFlagValue = flagValue;
        } else {
            uint256 numberValue = fl.clamp(dataSeed, 0, POLICY_MAX_ROLE_BITMAP);
            operation.selector = FuzzPolicyTarget.setNumber.selector;
            operation.data = abi.encodeWithSelector(operation.selector, numberValue);
            operation.isSetFlag = false;
            operation.expectedNumberValue = numberValue;
        }
    }

    function _pickPolicyModule(uint256 moduleSeed) internal returns (address module) {
        uint256 option = fl.clamp(moduleSeed, 0, 4);
        if (option == 0) return address(0);
        if (option == 1) return address(policyAllowModule);
        if (option == 2) return address(policyDenyModule);
        if (option == 3) return address(policyRevertingModule);
        return address(policyInvalidReturnModule);
    }

    function _pickNonZeroPolicyModule(uint256 moduleSeed) internal returns (address module) {
        uint256 option = fl.clamp(moduleSeed, 0, 3);
        if (option == 0) return address(policyAllowModule);
        if (option == 1) return address(policyDenyModule);
        if (option == 2) return address(policyRevertingModule);
        return address(policyInvalidReturnModule);
    }
}
