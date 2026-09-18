// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

/**
 * @notice Represents the status of an entity
 * @param NONE Entity does not exist in the registry
 * @param DISABLED Entity is registered but disabled
 * @param ENABLED Entity is active and allowed
 */
enum EntityStatus {
    NONE,
    DISABLED,
    ENABLED
}

/**
 * @notice Represents the status of an account
 * @param NONE Account does not exist in the registry
 * @param DISABLED Account is registered but disabled
 * @param ENABLED Account is active and allowed
 */
enum AccountStatus {
    NONE,
    DISABLED,
    ENABLED
}

/**
 * @notice Represents the scoped account assignment kind.
 * @param AUTHORITY Entity authority assignment
 * @param MANAGER Entity manager assignment
 */
enum ScopedAccountKind {
    AUTHORITY,
    MANAGER
}

/**
 * @notice Core entity record
 * @param typeId Entity type identifier
 * @param status Entity status
 * @param statusReason Last status change reason code
 * @param metadataRef Optional offchain metadata reference
 * @param accounts Accounts linked to the entity
 */
struct Entity {
    uint256 typeId;
    EntityStatus status;
    bytes statusReason;
    string metadataRef;
    address[] accounts;
}

/**
 * @notice Account record linked to an entity
 * @param entityId Linked entity ID
 * @param status Account status
 * @param statusReason Last status change reason code
 * @param roleFlags Account-level role flags (informational)
 * @param entityAccountIndex 1-based index in entity accounts array
 */
struct Account {
    bytes32 entityId;
    AccountStatus status;
    bytes statusReason;
    uint256 roleFlags;
    uint256 entityAccountIndex;
}

/**
 * @notice Pending account registration awaiting account-side acceptance
 * @param roleFlags Account-level role flags to apply when accepted
 * @param requester Entity manager or admin that requested the registration
 */
struct PendingAccountRegistration {
    uint256 roleFlags;
    address requester;
}

/**
 * @notice Entity type metadata for offchain interpretation
 * @param name Type name. A non-zero value marks the entity type as registered.
 * @param caps Optional capability flags. See docs/registry/EntityRegistry.md for usage guidance.
 * @param frozen Whether the type is frozen against updates
 */
struct EntityTypeMeta {
    bytes32 name;
    uint256 caps;
    bool frozen;
}
