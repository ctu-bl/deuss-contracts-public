// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {Initializable} from "solady/src/utils/Initializable.sol";
import {Errors} from "../libs/Errors.sol";
import {ICompanyWallet} from "../wallet/ICompanyWallet.sol";
import {IPolicyModule} from "./interfaces/IPolicyModule.sol";
import {IPolicyRegistry} from "./interfaces/IPolicyRegistry.sol";
import {ModuleExecutionCheck, OperationModule, OperationRoles} from "./PolicyStructs.sol";
import {PolicyRegistryStorage} from "./PolicyRegistryStorage.sol";

// slither-disable-start uninitialized-state
/**
 * @title PolicyRegistry
 * @author DEUSS Team
 * @notice Shared wallet-scoped authorization authority for CompanyWallet instances.
 */
contract PolicyRegistry is IPolicyRegistry, PolicyRegistryStorage, Ownable, Initializable {
    using ERC165Checker for address;

    /**
     * @notice Locks any future initializations or reinitializations.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the global registry owner.
     * @param owner_ Global registry owner.
     */
    function initialize(address owner_) external initializer {
        require(owner_ != address(0), Errors.ZeroAddress());
        _initializeOwner(owner_);
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function grantWalletPolicyAdmin(address wallet, address admin) external {
        _requireWalletOwner(wallet);
        require(admin != address(0), Errors.PolicyRegistry__InvalidPolicyAdmin(admin));
        uint256 epoch = _getWalletEpoch(wallet);
        require(
            !_policyRegistryStorage().walletPolicyAdmins[wallet][epoch][admin],
            Errors.PolicyRegistry__WalletPolicyAdminAlreadyGranted(wallet, admin)
        );

        _policyRegistryStorage().walletPolicyAdmins[wallet][epoch][admin] = true;
        emit WalletPolicyAdminGranted(wallet, admin, msg.sender);
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function revokeWalletPolicyAdmin(address wallet, address admin) external {
        _requireWalletOwner(wallet);
        require(admin != address(0), Errors.PolicyRegistry__InvalidPolicyAdmin(admin));
        uint256 epoch = _getWalletEpoch(wallet);
        require(
            _policyRegistryStorage().walletPolicyAdmins[wallet][epoch][admin],
            Errors.PolicyRegistry__WalletPolicyAdminNotGranted(wallet, admin)
        );

        _policyRegistryStorage().walletPolicyAdmins[wallet][epoch][admin] = false;
        emit WalletPolicyAdminRevoked(wallet, admin, msg.sender);
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function grantUserRoles(address wallet, address user, uint256 roles) external {
        uint256 epoch = _getWalletEpoch(wallet);
        _requireWalletPolicyOperator(wallet, epoch);
        _grantUserRoles(wallet, epoch, user, roles);
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function grantUserRoles(address wallet, address[] calldata users, uint256 roles) external {
        uint256 epoch = _getWalletEpoch(wallet);
        _requireWalletPolicyOperator(wallet, epoch);

        uint256 length = users.length;
        for (uint256 i; i < length;) {
            _grantUserRoles(wallet, epoch, users[i], roles);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function revokeUserRoles(address wallet, address user, uint256 roles) external {
        uint256 epoch = _getWalletEpoch(wallet);
        _requireWalletPolicyOperator(wallet, epoch);
        _revokeUserRoles(wallet, epoch, user, roles);
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function revokeUserRoles(address wallet, address[] calldata users, uint256 roles) external {
        uint256 epoch = _getWalletEpoch(wallet);
        _requireWalletPolicyOperator(wallet, epoch);

        uint256 length = users.length;
        for (uint256 i; i < length;) {
            _revokeUserRoles(wallet, epoch, users[i], roles);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function setUserRoles(address wallet, address user, uint256 roles) external {
        uint256 epoch = _getWalletEpoch(wallet);
        _requireWalletPolicyOperator(wallet, epoch);
        _setUserRoles(wallet, epoch, user, roles);
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function setUserRoles(address wallet, address[] calldata users, uint256[] calldata roles) external {
        uint256 epoch = _getWalletEpoch(wallet);
        _requireWalletPolicyOperator(wallet, epoch);
        require(users.length == roles.length, Errors.LengthMismatch());

        uint256 length = users.length;
        for (uint256 i; i < length;) {
            _setUserRoles(wallet, epoch, users[i], roles[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function grantOperationRoles(address wallet, address target, bytes4 selector, uint256 roles) external {
        uint256 epoch = _getWalletEpoch(wallet);
        _requireWalletPolicyOperator(wallet, epoch);
        _grantOperationRoles(wallet, epoch, target, selector, roles);
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function grantOperationRoles(address wallet, OperationRoles[] calldata operations) external {
        uint256 epoch = _getWalletEpoch(wallet);
        _requireWalletPolicyOperator(wallet, epoch);

        uint256 length = operations.length;
        for (uint256 i; i < length;) {
            _grantOperationRoles(wallet, epoch, operations[i].target, operations[i].selector, operations[i].roles);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function revokeOperationRoles(address wallet, address target, bytes4 selector, uint256 roles) external {
        uint256 epoch = _getWalletEpoch(wallet);
        _requireWalletPolicyOperator(wallet, epoch);
        _revokeOperationRoles(wallet, epoch, target, selector, roles);
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function revokeOperationRoles(address wallet, OperationRoles[] calldata operations) external {
        uint256 epoch = _getWalletEpoch(wallet);
        _requireWalletPolicyOperator(wallet, epoch);

        uint256 length = operations.length;
        for (uint256 i; i < length;) {
            _revokeOperationRoles(wallet, epoch, operations[i].target, operations[i].selector, operations[i].roles);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function setOperationRoles(address wallet, address target, bytes4 selector, uint256 roles) external {
        uint256 epoch = _getWalletEpoch(wallet);
        _requireWalletPolicyOperator(wallet, epoch);
        _setOperationRoles(wallet, epoch, target, selector, roles);
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function setOperationRoles(address wallet, OperationRoles[] calldata operations) external {
        uint256 epoch = _getWalletEpoch(wallet);
        _requireWalletPolicyOperator(wallet, epoch);

        uint256 length = operations.length;
        for (uint256 i; i < length;) {
            _setOperationRoles(wallet, epoch, operations[i].target, operations[i].selector, operations[i].roles);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function setOperationModule(address wallet, address target, bytes4 selector, address module) external {
        uint256 epoch = _getWalletEpoch(wallet);
        _requireWalletPolicyOperator(wallet, epoch);
        _setOperationModule(wallet, epoch, target, selector, module);
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function setOperationModule(address wallet, OperationModule[] calldata operations) external {
        uint256 epoch = _getWalletEpoch(wallet);
        _requireWalletPolicyOperator(wallet, epoch);

        uint256 length = operations.length;
        for (uint256 i; i < length;) {
            _setOperationModule(wallet, epoch, operations[i].target, operations[i].selector, operations[i].module);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function setRoleLabel(uint8 roleId, bytes32 label) external onlyOwner {
        _policyRegistryStorage().roleLabels[roleId] = label;
        emit RoleLabelSet(roleId, label);
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function setPolicyModuleAllowed(address module, bool allowed) external onlyOwner {
        _validatePolicyModuleAddress(module);
        _policyRegistryStorage().allowedPolicyModules[module] = allowed;
        emit PolicyModuleAllowed(module, allowed);
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function canExecute(address wallet, address caller, address target, uint256 value, bytes calldata data)
        external
        view
        returns (bool)
    {
        if (!_hasValidExecutionRequest(wallet, caller, target, data)) {
            return false;
        }

        uint256 epoch = _getWalletEpoch(wallet);
        (bool baseAuthorized, bytes32 operationKey) = _checkBaseAuthorization(wallet, epoch, caller, target, data);
        if (!baseAuthorized) {
            return false;
        }

        ModuleExecutionCheck memory result =
            _checkOperationModule(wallet, epoch, caller, target, value, data, operationKey);
        if (!result.hasModule) {
            return true;
        }

        return result.moduleAuthorized;
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function checkOperationModule(address wallet, address caller, address target, uint256 value, bytes calldata data)
        external
        view
        returns (ModuleExecutionCheck memory result)
    {
        if (!_hasValidExecutionRequest(wallet, caller, target, data)) {
            return result;
        }

        uint256 epoch = _getWalletEpoch(wallet);
        return _checkOperationModule(
            wallet, epoch, caller, target, value, data, _computeOperationKey(target, bytes4(data[0:4]))
        );
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function isWalletPolicyAdmin(address wallet, address admin) external view returns (bool) {
        uint256 epoch = _getWalletEpoch(wallet);
        return _policyRegistryStorage().walletPolicyAdmins[wallet][epoch][admin];
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function isPolicyModuleAllowed(address module) external view returns (bool allowed) {
        return _policyRegistryStorage().allowedPolicyModules[module];
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function roleLabels(uint8 roleId) external view returns (bytes32 label) {
        return _policyRegistryStorage().roleLabels[roleId];
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function getUserRoles(address wallet, address user) external view returns (uint256 roles) {
        uint256 epoch = _getWalletEpoch(wallet);
        return _policyRegistryStorage().walletUserRoles[wallet][epoch][user];
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function getOperationRoles(address wallet, address target, bytes4 selector) external view returns (uint256 roles) {
        uint256 epoch = _getWalletEpoch(wallet);
        return _policyRegistryStorage().walletOperationRoles[wallet][epoch][_computeOperationKey(target, selector)];
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function getOperationModule(address wallet, address target, bytes4 selector)
        external
        view
        returns (address module)
    {
        uint256 epoch = _getWalletEpoch(wallet);
        return _policyRegistryStorage().walletOperationModules[wallet][epoch][_computeOperationKey(target, selector)];
    }

    /**
     * @inheritdoc IPolicyRegistry
     */
    function computeOperationKey(address target, bytes4 selector) external pure returns (bytes32 operationKey) {
        return _computeOperationKey(target, selector);
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(IPolicyRegistry).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @notice Grants additional roles to a wallet user.
     * @param wallet Wallet being managed.
     * @param epoch Current ownership epoch of the wallet.
     * @param user User whose roles are updated.
     * @param roles Role bitmap to add.
     */
    function _grantUserRoles(address wallet, uint256 epoch, address user, uint256 roles) internal {
        require(user != address(0), Errors.ZeroAddress());
        require(roles != 0, Errors.PolicyRegistry__ZeroRoles());

        uint256 currentRoles = _policyRegistryStorage().walletUserRoles[wallet][epoch][user];
        require((currentRoles & roles) != roles, Errors.PolicyRegistry__UserRolesAlreadyGranted(wallet, user, roles));

        _policyRegistryStorage().walletUserRoles[wallet][epoch][user] = currentRoles | roles;
        emit WalletUserRolesGranted(wallet, user, roles, msg.sender);
    }

    /**
     * @notice Revokes roles from a wallet user.
     * @param wallet Wallet being managed.
     * @param epoch Current ownership epoch of the wallet.
     * @param user User whose roles are updated.
     * @param roles Role bitmap to remove.
     */
    function _revokeUserRoles(address wallet, uint256 epoch, address user, uint256 roles) internal {
        require(user != address(0), Errors.ZeroAddress());
        require(roles != 0, Errors.PolicyRegistry__ZeroRoles());

        uint256 currentRoles = _policyRegistryStorage().walletUserRoles[wallet][epoch][user];
        require((currentRoles & roles) == roles, Errors.PolicyRegistry__UserRolesNotGranted(wallet, user, roles));

        _policyRegistryStorage().walletUserRoles[wallet][epoch][user] = currentRoles & ~roles;
        emit WalletUserRolesRevoked(wallet, user, roles, msg.sender);
    }

    /**
     * @notice Stores the exact role bitmap for a wallet user.
     * @param wallet Wallet being managed.
     * @param epoch Current ownership epoch of the wallet.
     * @param user User whose roles are updated.
     * @param roles Exact role bitmap to store.
     */
    function _setUserRoles(address wallet, uint256 epoch, address user, uint256 roles) internal {
        require(user != address(0), Errors.ZeroAddress());

        _policyRegistryStorage().walletUserRoles[wallet][epoch][user] = roles;
        emit WalletUserRolesSet(wallet, user, roles);
    }

    /**
     * @notice Grants additional roles to a wallet operation.
     * @param wallet Wallet being managed.
     * @param epoch Current ownership epoch of the wallet.
     * @param target Operation target.
     * @param selector Operation selector.
     * @param roles Role bitmap to add.
     */
    function _grantOperationRoles(address wallet, uint256 epoch, address target, bytes4 selector, uint256 roles)
        internal
    {
        require(roles != 0, Errors.PolicyRegistry__ZeroRoles());

        bytes32 operationKey = _requireOperationKey(target, selector);
        uint256 currentRoles = _policyRegistryStorage().walletOperationRoles[wallet][epoch][operationKey];
        require(
            (currentRoles & roles) != roles,
            Errors.PolicyRegistry__OperationRolesAlreadyGranted(wallet, target, selector, roles)
        );

        _policyRegistryStorage().walletOperationRoles[wallet][epoch][operationKey] = currentRoles | roles;
        emit WalletOperationRolesGranted(wallet, target, selector, roles, msg.sender);
    }

    /**
     * @notice Revokes roles from a wallet operation.
     * @param wallet Wallet being managed.
     * @param epoch Current ownership epoch of the wallet.
     * @param target Operation target.
     * @param selector Operation selector.
     * @param roles Role bitmap to remove.
     */
    function _revokeOperationRoles(address wallet, uint256 epoch, address target, bytes4 selector, uint256 roles)
        internal
    {
        require(roles != 0, Errors.PolicyRegistry__ZeroRoles());

        bytes32 operationKey = _requireOperationKey(target, selector);
        uint256 currentRoles = _policyRegistryStorage().walletOperationRoles[wallet][epoch][operationKey];
        require(
            (currentRoles & roles) == roles,
            Errors.PolicyRegistry__OperationRolesNotGranted(wallet, target, selector, roles)
        );

        _policyRegistryStorage().walletOperationRoles[wallet][epoch][operationKey] = currentRoles & ~roles;
        emit WalletOperationRolesRevoked(wallet, target, selector, roles, msg.sender);
    }

    /**
     * @notice Stores the exact role bitmap for a wallet operation.
     * @param wallet Wallet being managed.
     * @param epoch Current ownership epoch of the wallet.
     * @param target Operation target.
     * @param selector Operation selector.
     * @param roles Exact role bitmap to store.
     */
    function _setOperationRoles(address wallet, uint256 epoch, address target, bytes4 selector, uint256 roles)
        internal
    {
        bytes32 operationKey = _requireOperationKey(target, selector);
        _policyRegistryStorage().walletOperationRoles[wallet][epoch][operationKey] = roles;
        emit WalletOperationRolesSet(wallet, target, selector, roles);
    }

    /**
     * @notice Stores the optional policy module for a wallet operation.
     * @param wallet Wallet being managed.
     * @param epoch Current ownership epoch of the wallet.
     * @param target Operation target.
     * @param selector Operation selector.
     * @param module Optional policy module. Zero address clears the module.
     */
    function _setOperationModule(address wallet, uint256 epoch, address target, bytes4 selector, address module)
        internal
    {
        bytes32 operationKey = _requireOperationKey(target, selector);
        _requirePolicyModuleAllowed(module);
        _policyRegistryStorage().walletOperationModules[wallet][epoch][operationKey] = module;
        emit WalletOperationModuleSet(wallet, target, selector, module);
    }

    /**
     * @notice Requires the caller to be the wallet owner.
     * @param wallet Wallet being managed.
     */
    function _requireWalletOwner(address wallet) internal view {
        require(msg.sender == _getWalletOwner(wallet), Errors.PolicyRegistry__Unauthorized(msg.sender, wallet));
    }

    /**
     * @notice Requires the caller to be the wallet owner or a delegated wallet policy admin for the current epoch.
     * @param wallet Wallet being managed.
     * @param epoch Current ownership epoch of the wallet.
     */
    function _requireWalletPolicyOperator(address wallet, uint256 epoch) internal view {
        address walletOwner = _getWalletOwner(wallet);
        require(
            msg.sender == walletOwner || _policyRegistryStorage().walletPolicyAdmins[wallet][epoch][msg.sender],
            Errors.PolicyRegistry__Unauthorized(msg.sender, wallet)
        );
    }

    /**
     * @notice Returns the owner reported by a wallet contract.
     * @param wallet Wallet being queried.
     * @return walletOwner Current wallet owner.
     */
    function _getWalletOwner(address wallet) internal view returns (address walletOwner) {
        require(wallet != address(0), Errors.PolicyRegistry__InvalidWallet(wallet));
        require(wallet.code.length != 0, Errors.PolicyRegistry__InvalidWallet(wallet));
        walletOwner = ICompanyWallet(wallet).owner();
    }

    /**
     * @notice Returns the current ownership epoch reported by a wallet contract.
     *         Reverts with PolicyRegistry__InvalidWallet for zero or non-contract addresses.
     * @param wallet Wallet being queried.
     * @return epoch Current ownership epoch.
     */
    function _getWalletEpoch(address wallet) internal view returns (uint256 epoch) {
        require(wallet != address(0), Errors.PolicyRegistry__InvalidWallet(wallet));
        require(wallet.code.length != 0, Errors.PolicyRegistry__InvalidWallet(wallet));
        return ICompanyWallet(wallet).ownershipEpoch();
    }

    /**
     * @notice Requires a non-zero module to be valid and allowlisted.
     * @param module Policy module to validate.
     */
    function _requirePolicyModuleAllowed(address module) internal view {
        if (module == address(0)) {
            return;
        }

        _validatePolicyModuleAddress(module);
        require(
            _policyRegistryStorage().allowedPolicyModules[module], Errors.PolicyRegistry__PolicyModuleNotAllowed(module)
        );
    }

    /**
     * @notice Validates a wallet operation descriptor and returns its operation key.
     * @param target Operation target.
     * @param selector Operation selector.
     * @return operationKey Derived operation key.
     */
    function _requireOperationKey(address target, bytes4 selector) internal pure returns (bytes32 operationKey) {
        require(target != address(0), Errors.ZeroAddress());
        require(selector != bytes4(0), Errors.PolicyRegistry__ZeroSelector());
        return _computeOperationKey(target, selector);
    }

    /**
     * @notice Returns whether the wallet call passes the base bitmap authorization check.
     * @param wallet Wallet performing the call.
     * @param epoch Current ownership epoch of the wallet.
     * @param caller Transaction sender attempting execution.
     * @param target Call target.
     * @param data Encoded call data.
     * @return baseAuthorized True if the base bitmap check passes.
     * @return operationKey Derived operation key for the call.
     */
    // solhint-disable-next-line ordering
    function _checkBaseAuthorization(address wallet, uint256 epoch, address caller, address target, bytes calldata data)
        internal
        view
        returns (bool baseAuthorized, bytes32 operationKey)
    {
        uint256 userRoles = _policyRegistryStorage().walletUserRoles[wallet][epoch][caller];
        if (userRoles == 0) {
            return (false, bytes32(0));
        }

        operationKey = _computeOperationKey(target, bytes4(data[0:4]));
        uint256 operationRoles = _policyRegistryStorage().walletOperationRoles[wallet][epoch][operationKey];
        return ((userRoles & operationRoles) != 0, operationKey);
    }

    /**
     * @notice Evaluates the optional module stage for a wallet operation.
     * @param wallet Wallet performing the call.
     * @param epoch Current ownership epoch of the wallet.
     * @param caller Transaction sender attempting execution.
     * @param target Call target.
     * @param value Native value forwarded by the wallet.
     * @param data Encoded call data.
     * @param operationKey Derived operation key.
     * @return result Structured module-stage evaluation details.
     */
    function _checkOperationModule(
        address wallet,
        uint256 epoch,
        address caller,
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 operationKey
    ) internal view returns (ModuleExecutionCheck memory result) {
        result.module = _policyRegistryStorage().walletOperationModules[wallet][epoch][operationKey];
        result.hasModule = result.module != address(0);
        if (!result.hasModule) {
            return result;
        }

        result.moduleAllowed = _policyRegistryStorage().allowedPolicyModules[result.module];
        if (!result.moduleAllowed) {
            return result;
        }

        (bool success, bytes memory returnData) =
            result.module.staticcall(abi.encodeCall(IPolicyModule.canExecute, (wallet, caller, target, value, data)));
        if (!success || returnData.length != 32) {
            return result;
        }

        result.moduleCallSucceeded = true;
        result.moduleAuthorized = abi.decode(returnData, (bool));
    }

    /**
     * @notice Returns whether the execution request has the minimum fields needed for policy evaluation.
     * @param wallet Wallet performing the call.
     * @param caller Transaction sender attempting execution.
     * @param target Call target.
     * @param data Encoded call data.
     * @return valid True if the request is structurally valid.
     */
    function _hasValidExecutionRequest(address wallet, address caller, address target, bytes calldata data)
        internal
        pure
        returns (bool valid)
    {
        return wallet != address(0) && caller != address(0) && target != address(0) && data.length > 3;
    }

    /**
     * @notice Returns the canonical operation key for a target and selector pair.
     * @param target Operation target.
     * @param selector Operation selector.
     * @return operationKey Canonical operation key.
     */
    function _computeOperationKey(address target, bytes4 selector) internal pure returns (bytes32 operationKey) {
        return keccak256(abi.encode(target, selector));
    }

    /**
     * @notice Validates that a module address points to deployed code.
     * @param module Policy module address.
     */
    function _validatePolicyModuleAddress(address module) internal view {
        require(module != address(0), Errors.PolicyRegistry__InvalidPolicyModule(module));
        require(module.code.length != 0, Errors.PolicyRegistry__InvalidPolicyModule(module));
        require(
            module.supportsInterface(type(IPolicyModule).interfaceId),
            Errors.PolicyRegistry__InvalidPolicyModule(module)
        );
    }
}
// slither-disable-end uninitialized-state
