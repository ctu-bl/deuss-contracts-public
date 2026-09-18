// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Entity, Account, EntityTypeMeta, PendingAccountRegistration} from "src/registry/EntityStructs.sol";

/**
 * @title EntityRegistryStorage
 * @author DEUSS Team
 * @notice Storage contract for the EntityRegistry contract
 */
abstract contract EntityRegistryStorage {
    /**
     * @notice Entity, account, governance, and entity-type storage.
     * @custom:storage-location erc7201:deuss.entityRegistry.storage
     */
    struct EntityRegistryState {
        /// @notice Maps entity ID to entity data, including the linked account list.
        mapping(bytes32 entityId => Entity entity) entities;
        /// @notice Maps account address to account data.
        mapping(address account => Account accountData) accounts;
        /// @notice Maps entity ID to the authority address for that entity.
        mapping(bytes32 entityId => address authority) entityAuthorities;
        /// @notice Tracks whether an address is an enabled manager for an entity.
        mapping(bytes32 entityId => mapping(address manager => bool enabled)) entityManagers;
        /// @notice Tracks account lifecycle nonces used to invalidate scoped authority and manager assignments.
        mapping(address account => uint256 nonce) accountScopedAssignmentNonce;
        /// @notice Records the account lifecycle nonce captured when an entity authority was assigned.
        mapping(bytes32 entityId => uint256 nonce) entityAuthorityAssignmentNonce;
        /// @notice Records the account lifecycle nonce captured when an entity manager was assigned.
        mapping(bytes32 entityId => mapping(address manager => uint256 nonce)) entityManagerAssignmentNonce;
        /// @notice Tracks account registration requests awaiting account-side acceptance.
        mapping(address account => mapping(bytes32 entityId => PendingAccountRegistration request))
            pendingAccountRegistrations;
        /// @notice Maps entity type ID to entity type metadata.
        mapping(uint256 typeId => EntityTypeMeta meta) entityTypeMeta;
    }

    /**
     * @notice ERC-7201 storage location for EntityRegistry state.
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("deuss.entityRegistry.storage"))) - 1))
     *      & ~bytes32(uint256(0xff))
     */
    // slither-disable-next-line unused-state
    bytes32 internal constant _ENTITY_REGISTRY_STORAGE_LOCATION =
        0x9ca5966875a07769ac7cc366d5f33d11a7418483289c2d2340b0e06f8dfd3600;

    /**
     * @notice Returns EntityRegistry namespaced storage.
     * @return $ Namespaced storage pointer.
     */
    // slither-disable-next-line uninitialized-storage,assembly
    function _entityRegistryStorage() internal pure returns (EntityRegistryState storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _ENTITY_REGISTRY_STORAGE_LOCATION
        }
    }
}
