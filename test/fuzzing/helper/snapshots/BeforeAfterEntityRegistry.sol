// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Account, Entity} from "src/registry/EntityStructs.sol";
import {SnapshotTypes} from "./SnapshotTypes.sol";

/// @notice Before/after snapshot helpers and account-linkage checks for EntityRegistry fuzz actions.
abstract contract BeforeAfterEntityRegistry is SnapshotTypes {
    /*//////////////////////////////////////////////////////////////
                           SNAPSHOT ENTRYPOINTS
    //////////////////////////////////////////////////////////////*/

    function _beforeER(bytes32[] memory entityIds, address[] memory accounts) internal {
        _setERState(BEFORE, entityIds, accounts);
    }

    function _afterER(bytes32[] memory entityIds, address[] memory accounts) internal {
        _setERState(AFTER, entityIds, accounts);
    }

    /*//////////////////////////////////////////////////////////////
                         ENTITY CONSISTENCY
    //////////////////////////////////////////////////////////////*/

    function _setERState(uint8 callNum, bytes32[] memory entityIds, address[] memory accounts) internal {
        for (uint256 i; i < entityIds.length; ++i) {
            if (entityIds[i] == bytes32(0)) continue;
            _setEntityState(callNum, entityIds[i]);
        }
        for (uint256 i; i < accounts.length; ++i) {
            if (accounts[i] == address(0)) continue;
            _setAccountState(callNum, accounts[i]);
        }

        // Walk all tracked entities and verify bidirectional account-to-entity linkage.
        // For each entity, every account in entity.accounts[] must point back to that entity
        // with a matching 1-based entityAccountIndex.
        bool allConsistent = true;
        for (uint256 i; i < knownEntityIds.length; ++i) {
            bytes32 entityId = knownEntityIds[i];
            if (entityId == bytes32(0)) continue;

            address[] memory entityAccounts = entityRegistry.getEntityAccounts(entityId);
            for (uint256 j; j < entityAccounts.length; ++j) {
                address acct = entityAccounts[j];
                if (!entityRegistry.isAccountRegistered(acct)) {
                    allConsistent = false;
                    break;
                }
                Account memory acctData = entityRegistry.getAccount(acct);
                if (acctData.entityId != entityId) {
                    allConsistent = false;
                    break;
                }
                // entityAccountIndex is 1-based and must match the loop position.
                if (acctData.entityAccountIndex != j + 1) {
                    allConsistent = false;
                    break;
                }
            }
            if (!allConsistent) break;
        }
        states[callNum].allTrackedEntityAccountsConsistent = allConsistent;
    }

    /*//////////////////////////////////////////////////////////////
                          SNAPSHOT SETTERS
    //////////////////////////////////////////////////////////////*/

    function _setEntityState(uint8 callNum, bytes32 entityId) internal {
        Entity memory entity = entityRegistry.getEntity(entityId);
        states[callNum].entityStates[entityId].status = entity.status;
        states[callNum].entityStates[entityId].typeId = entity.typeId;
        states[callNum].entityStates[entityId].accountCount = entity.accounts.length;
    }

    function _setAccountState(uint8 callNum, address account) internal {
        if (entityRegistry.isAccountRegistered(account)) {
            Account memory acct = entityRegistry.getAccount(account);
            states[callNum].accountStates[account].status = acct.status;
            states[callNum].accountStates[account].entityId = acct.entityId;
            states[callNum].accountStates[account].roleFlags = acct.roleFlags;
            states[callNum].accountStates[account].registered = true;
        } else {
            delete states[callNum].accountStates[account];
        }
    }
}
