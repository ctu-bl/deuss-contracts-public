// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ModuleExecutionCheck, OperationModule, OperationRoles} from "../PolicyStructs.sol";

/**
 * @title IPolicyRegistry
 * @author DEUSS Team
 * @notice Shared wallet-scoped policy authority for CompanyWallet execution.
 */
interface IPolicyRegistry is IERC165 {
    /**
     * @notice Emitted when a delegated wallet policy admin is granted.
     * @param wallet Wallet being managed.
     * @param admin Delegated wallet policy admin.
     * @param caller Caller that performed the change.
     */
    event WalletPolicyAdminGranted(address indexed wallet, address indexed admin, address indexed caller);

    /**
     * @notice Emitted when a delegated wallet policy admin is revoked.
     * @param wallet Wallet being managed.
     * @param admin Delegated wallet policy admin.
     * @param caller Caller that performed the change.
     */
    event WalletPolicyAdminRevoked(address indexed wallet, address indexed admin, address indexed caller);

    /**
     * @notice Emitted when user roles are granted for a wallet.
     * @param wallet Wallet being managed.
     * @param user User whose roles changed.
     * @param roles Granted role bitmap.
     * @param caller Caller that performed the change.
     */
    event WalletUserRolesGranted(address indexed wallet, address indexed user, uint256 roles, address caller); // solhint-disable-line gas-indexed-events

    /**
     * @notice Emitted when user roles are revoked for a wallet.
     * @param wallet Wallet being managed.
     * @param user User whose roles changed.
     * @param roles Revoked role bitmap.
     * @param caller Caller that performed the change.
     */
    event WalletUserRolesRevoked(address indexed wallet, address indexed user, uint256 roles, address caller); // solhint-disable-line gas-indexed-events

    /**
     * @notice Emitted when user roles are overwritten for a wallet.
     * @param wallet Wallet being managed.
     * @param user User whose roles changed.
     * @param roles New exact role bitmap.
     */
    event WalletUserRolesSet(address indexed wallet, address indexed user, uint256 indexed roles);

    /**
     * @notice Emitted when operation roles are granted for a wallet.
     * @param wallet Wallet being managed.
     * @param target Operation target.
     * @param selector Operation selector.
     * @param roles Granted role bitmap.
     * @param caller Caller that performed the change.
     */
    event WalletOperationRolesGranted(
        address indexed wallet, address indexed target, bytes4 indexed selector, uint256 roles, address caller
    );

    /**
     * @notice Emitted when operation roles are revoked for a wallet.
     * @param wallet Wallet being managed.
     * @param target Operation target.
     * @param selector Operation selector.
     * @param roles Revoked role bitmap.
     * @param caller Caller that performed the change.
     */
    event WalletOperationRolesRevoked(
        address indexed wallet, address indexed target, bytes4 indexed selector, uint256 roles, address caller
    );

    /**
     * @notice Emitted when operation roles are overwritten for a wallet.
     * @param wallet Wallet being managed.
     * @param target Operation target.
     * @param selector Operation selector.
     * @param roles New exact role bitmap.
     */
    event WalletOperationRolesSet(
        address indexed wallet, address indexed target, bytes4 indexed selector, uint256 roles
    );

    /**
     * @notice Emitted when the policy module for a wallet operation is updated.
     * @param wallet Wallet being managed.
     * @param target Operation target.
     * @param selector Operation selector.
     * @param module Optional policy module. Zero address means no module.
     */
    event WalletOperationModuleSet(
        address indexed wallet, address indexed target, bytes4 indexed selector, address module
    );

    /**
     * @notice Emitted when compact metadata is set for a role id.
     * @param roleId Role bit index.
     * @param label Compact role label.
     */
    event RoleLabelSet(uint8 indexed roleId, bytes32 indexed label);

    /**
     * @notice Emitted when a policy module allowlist status changes.
     * @param module Policy module address.
     * @param allowed Whether the module is allowlisted.
     */
    event PolicyModuleAllowed(address indexed module, bool allowed); // solhint-disable-line gas-indexed-events

    /**
     * @notice Grants delegated wallet policy admin rights.
     * @param wallet Wallet being managed.
     * @param admin Admin to grant.
     */
    function grantWalletPolicyAdmin(address wallet, address admin) external;

    /**
     * @notice Revokes delegated wallet policy admin rights.
     * @param wallet Wallet being managed.
     * @param admin Admin to revoke.
     */
    function revokeWalletPolicyAdmin(address wallet, address admin) external;

    /**
     * @notice Grants roles to a wallet user.
     * @param wallet Wallet being managed.
     * @param user User whose roles are updated.
     * @param roles Roles to grant.
     */
    function grantUserRoles(address wallet, address user, uint256 roles) external;

    /**
     * @notice Grants the same role bitmap to multiple users for a wallet.
     * @param wallet Wallet being managed.
     * @param users Users whose roles are updated.
     * @param roles Roles to grant.
     */
    function grantUserRoles(address wallet, address[] calldata users, uint256 roles) external;

    /**
     * @notice Revokes roles from a wallet user.
     * @param wallet Wallet being managed.
     * @param user User whose roles are updated.
     * @param roles Roles to revoke.
     */
    function revokeUserRoles(address wallet, address user, uint256 roles) external;

    /**
     * @notice Revokes the same role bitmap from multiple users for a wallet.
     * @param wallet Wallet being managed.
     * @param users Users whose roles are updated.
     * @param roles Roles to revoke.
     */
    function revokeUserRoles(address wallet, address[] calldata users, uint256 roles) external;

    /**
     * @notice Sets the exact role bitmap for a wallet user.
     * @param wallet Wallet being managed.
     * @param user User whose roles are updated.
     * @param roles Exact role bitmap to store.
     */
    function setUserRoles(address wallet, address user, uint256 roles) external;

    /**
     * @notice Sets exact role bitmaps for multiple wallet users.
     * @param wallet Wallet being managed.
     * @param users Users whose roles are updated.
     * @param roles Exact role bitmaps to store.
     */
    function setUserRoles(address wallet, address[] calldata users, uint256[] calldata roles) external;

    /**
     * @notice Grants roles to a wallet operation.
     * @param wallet Wallet being managed.
     * @param target Operation target.
     * @param selector Operation selector.
     * @param roles Roles to grant.
     */
    function grantOperationRoles(address wallet, address target, bytes4 selector, uint256 roles) external;

    /**
     * @notice Grants roles to multiple wallet operations.
     * @param wallet Wallet being managed.
     * @param operations Operation updates.
     */
    function grantOperationRoles(address wallet, OperationRoles[] calldata operations) external;

    /**
     * @notice Revokes roles from a wallet operation.
     * @param wallet Wallet being managed.
     * @param target Operation target.
     * @param selector Operation selector.
     * @param roles Roles to revoke.
     */
    function revokeOperationRoles(address wallet, address target, bytes4 selector, uint256 roles) external;

    /**
     * @notice Revokes roles from multiple wallet operations.
     * @param wallet Wallet being managed.
     * @param operations Operation updates.
     */
    function revokeOperationRoles(address wallet, OperationRoles[] calldata operations) external;

    /**
     * @notice Sets the exact role bitmap for a wallet operation.
     * @param wallet Wallet being managed.
     * @param target Operation target.
     * @param selector Operation selector.
     * @param roles Exact role bitmap to store.
     */
    function setOperationRoles(address wallet, address target, bytes4 selector, uint256 roles) external;

    /**
     * @notice Sets exact role bitmaps for multiple wallet operations.
     * @param wallet Wallet being managed.
     * @param operations Operation updates.
     */
    function setOperationRoles(address wallet, OperationRoles[] calldata operations) external;

    /**
     * @notice Sets the optional policy module for a wallet operation.
     * @param wallet Wallet being managed.
     * @param target Operation target.
     * @param selector Operation selector.
     * @param module Optional policy module. Zero address clears the module.
     */
    function setOperationModule(address wallet, address target, bytes4 selector, address module) external;

    /**
     * @notice Sets optional policy modules for multiple wallet operations.
     * @param wallet Wallet being managed.
     * @param operations Operation-module updates.
     */
    function setOperationModule(address wallet, OperationModule[] calldata operations) external;

    /**
     * @notice Sets compact metadata for a role id.
     * @param roleId Role bit index.
     * @param label Compact role label.
     */
    function setRoleLabel(uint8 roleId, bytes32 label) external;

    /**
     * @notice Updates global allowlist status for a policy module.
     * @param module Policy module address.
     * @param allowed Whether the module should be allowlisted.
     */
    function setPolicyModuleAllowed(address module, bool allowed) external;

    /**
     * @notice Returns whether a wallet call is authorized.
     * @param wallet Wallet performing the call.
     * @param caller Transaction sender attempting execution.
     * @param target Call target.
     * @param value Native value forwarded by the wallet.
     * @param data Encoded call data.
     * @return True if execution is allowed.
     */
    function canExecute(address wallet, address caller, address target, uint256 value, bytes calldata data)
        external
        view
        returns (bool);

    /**
     * @notice Returns the diagnostic result for the optional module stage of policy evaluation.
     * @dev This helper does not perform the base wallet RBAC check. It is intended for debugging,
     * observability, and preflight inspection of the configured module path only.
     * @param wallet Wallet performing the call.
     * @param caller Transaction sender attempting execution.
     * @param target Call target.
     * @param value Native value forwarded by the wallet.
     * @param data Encoded call data.
     * @return result Structured module-stage evaluation details.
     */
    function checkOperationModule(address wallet, address caller, address target, uint256 value, bytes calldata data)
        external
        view
        returns (ModuleExecutionCheck memory result);

    /**
     * @notice Returns compact role metadata.
     * @param roleId Role bit index.
     * @return label Compact role label.
     */
    function roleLabels(uint8 roleId) external view returns (bytes32 label);

    /**
     * @notice Returns whether a policy module is globally allowlisted.
     * @param module Policy module being queried.
     * @return allowed True if the module is allowlisted.
     */
    function isPolicyModuleAllowed(address module) external view returns (bool allowed);

    /**
     * @notice Returns whether an address is a delegated wallet policy admin.
     * @param wallet Wallet being queried.
     * @param admin Address being checked.
     * @return True if delegated.
     */
    function isWalletPolicyAdmin(address wallet, address admin) external view returns (bool);

    /**
     * @notice Returns the current role bitmap for a wallet user.
     * @param wallet Wallet being queried.
     * @param user User being queried.
     * @return roles Exact stored role bitmap.
     */
    function getUserRoles(address wallet, address user) external view returns (uint256 roles);

    /**
     * @notice Returns the current allowed role bitmap for a wallet operation.
     * @param wallet Wallet being queried.
     * @param target Operation target.
     * @param selector Operation selector.
     * @return roles Exact stored role bitmap.
     */
    function getOperationRoles(address wallet, address target, bytes4 selector) external view returns (uint256 roles);

    /**
     * @notice Returns the configured optional policy module for a wallet operation.
     * @param wallet Wallet being queried.
     * @param target Operation target.
     * @param selector Operation selector.
     * @return module Configured module or zero address.
     */
    function getOperationModule(address wallet, address target, bytes4 selector) external view returns (address module);

    /**
     * @notice Computes the operation key for a target and selector.
     * @param target Operation target.
     * @param selector Operation selector.
     * @return operationKey Derived operation key.
     */
    function computeOperationKey(address target, bytes4 selector) external pure returns (bytes32 operationKey);
}
