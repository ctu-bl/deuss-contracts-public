// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ICompanyWallet} from "src/wallet/ICompanyWallet.sol";
import {SnapshotTypes} from "./SnapshotTypes.sol";

/// @notice Before/after snapshot helpers for PolicyRegistry fuzz actions.
abstract contract BeforeAfterPolicyRegistry is SnapshotTypes {
    /*//////////////////////////////////////////////////////////////
                         POLICY SNAPSHOTS
    //////////////////////////////////////////////////////////////*/

    function _beforePolicyRegistry(
        address wallet,
        address admin,
        address user,
        address target,
        bytes4 selector,
        uint256 value,
        bytes memory data
    ) internal {
        _setPolicyRegistryState(BEFORE, wallet, admin, user, target, selector, value, data);
    }

    function _afterPolicyRegistry(
        address wallet,
        address admin,
        address user,
        address target,
        bytes4 selector,
        uint256 value,
        bytes memory data
    ) internal {
        _setPolicyRegistryState(AFTER, wallet, admin, user, target, selector, value, data);
    }

    function _setPolicyRegistryState(
        uint8 callNum,
        address wallet,
        address admin,
        address user,
        address target,
        bytes4 selector,
        uint256 value,
        bytes memory data
    ) internal {
        if (wallet == address(0)) return;

        states[callNum].policyWalletStates[wallet].ownershipEpoch = ICompanyWallet(wallet).ownershipEpoch();
        states[callNum].policyWalletStates[wallet].owner = ICompanyWallet(wallet).owner();
        states[callNum].policyAdminStates[wallet][admin] = policyRegistry.isWalletPolicyAdmin(wallet, admin);
        states[callNum].policyUserRoleStates[wallet][user] = policyRegistry.getUserRoles(wallet, user);

        bytes32 operationKey = _policyOperationKey(target, selector);
        states[callNum].policyOperationStates[wallet][operationKey].roles =
            policyRegistry.getOperationRoles(wallet, target, selector);
        states[callNum].policyOperationStates[wallet][operationKey].module =
            policyRegistry.getOperationModule(wallet, target, selector);

        states[callNum].policyExecutionStates[wallet][_policyExecutionKey(user, target, value, data)] =
            policyRegistry.canExecute(wallet, user, target, value, data);
    }

    function _policyOperationKey(address target, bytes4 selector) internal pure returns (bytes32) {
        return keccak256(abi.encode(target, selector));
    }

    function _policyExecutionKey(address user, address target, uint256 value, bytes memory data)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(user, target, value, data));
    }
}
