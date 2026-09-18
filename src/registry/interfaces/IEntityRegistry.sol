// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {
    Entity,
    Account,
    EntityStatus,
    AccountStatus,
    EntityTypeMeta,
    PendingAccountRegistration
} from "../EntityStructs.sol";

/**
 * @title IEntityRegistry
 * @author DEUSS Team
 * @notice Interface for EntityRegistry combining entity validation and account management.
 */
interface IEntityRegistry is IERC165 {
    /**
     * @notice Emitted when a new entity is registered.
     * @param entityId Entity identifier.
     * @param typeId Entity type identifier.
     * @param metadataRef Offchain metadata reference.
     */
    event EntityRegistered(bytes32 indexed entityId, uint256 indexed typeId, string metadataRef);

    /**
     * @notice Emitted when entity status changes.
     * @param entityId Entity identifier.
     * @param oldStatus Previous entity status.
     * @param newStatus New entity status.
     * @param reason Reason code for the status change.
     */
    event EntityStatusUpdated(
        bytes32 indexed entityId, EntityStatus indexed oldStatus, EntityStatus indexed newStatus, bytes reason
    );

    /**
     * @notice Emitted when entity metadata reference changes.
     * @param entityId Entity identifier.
     * @param metadataRef New metadata reference.
     */
    event EntityMetadataUpdated(bytes32 indexed entityId, string metadataRef);

    /**
     * @notice Emitted when authority for an entity changes.
     * @param entityId Entity identifier.
     * @param previousAuthority Previous authority address.
     * @param authority New authority address.
     */
    event EntityAuthorityUpdated(
        bytes32 indexed entityId, address indexed previousAuthority, address indexed authority
    );

    /**
     * @notice Emitted when manager permissions for an entity are updated.
     * @param entityId Entity identifier.
     * @param manager Manager address.
     * @param enabled New enabled flag.
     */
    event EntityManagerUpdated(bytes32 indexed entityId, address indexed manager, bool indexed enabled);

    /**
     * @notice Emitted when an account is registered for an entity.
     * @param account Registered account address.
     * @param entityId Linked entity identifier.
     * @param roleFlags Account role bitmask metadata.
     */
    event AccountRegistered(address indexed account, bytes32 indexed entityId, uint256 indexed roleFlags);

    /**
     * @notice Emitted when account registration is requested and awaits account acceptance.
     * @param account Account address asked to join the entity.
     * @param entityId Target entity identifier.
     * @param roleFlags Account role bitmask metadata to apply on acceptance.
     * @param requester Entity manager or admin that requested the registration.
     */
    event AccountRegistrationRequested(
        address indexed account, bytes32 indexed entityId, uint256 indexed roleFlags, address requester
    );

    /**
     * @notice Emitted when an account accepts a pending registration request.
     * @param account Account address that accepted the request.
     * @param entityId Entity identifier linked to the account.
     * @param roleFlags Account role bitmask metadata applied at registration.
     * @param requester Entity manager or admin that requested the registration.
     */
    event AccountRegistrationAccepted(
        address indexed account, bytes32 indexed entityId, uint256 indexed roleFlags, address requester
    );

    /**
     * @notice Emitted when account status changes.
     * @param account Account address.
     * @param oldStatus Previous account status.
     * @param newStatus New account status.
     * @param reason Reason code for the status change.
     */
    event AccountStatusUpdated(
        address indexed account, AccountStatus indexed oldStatus, AccountStatus indexed newStatus, bytes reason
    );

    /**
     * @notice Emitted when account role flags are updated with entity context.
     * @param account Account address.
     * @param entityId Linked entity identifier.
     * @param newFlags New role flags.
     * @param oldFlags Previous role flags.
     */
    event AccountRoleFlagsUpdated(
        address indexed account, bytes32 indexed entityId, uint256 indexed newFlags, uint256 oldFlags
    );

    /**
     * @notice Emitted when account is moved between entities.
     * @param account Account address.
     * @param oldEntityId Previous entity identifier.
     * @param newEntityId New entity identifier.
     */
    event AccountEntityTransferred(address indexed account, bytes32 indexed oldEntityId, bytes32 indexed newEntityId);

    /**
     * @notice Emitted when entity type metadata is updated.
     * @param typeId Entity type identifier.
     * @param name Entity type name.
     * @param caps Entity type capability bitmask.
     */
    event EntityTypeMetaUpdated(uint256 indexed typeId, bytes32 indexed name, uint256 indexed caps);

    /**
     * @notice Emitted when an entity type is frozen.
     * @param typeId Entity type identifier.
     */
    event EntityTypeFrozen(uint256 indexed typeId);

    /**
     * @notice Registers an entity.
     * @param entityId Entity identifier.
     * @param typeId Entity type identifier.
     * @param metadataRef Offchain metadata reference.
     */
    function registerEntity(bytes32 entityId, uint256 typeId, string calldata metadataRef) external;

    /**
     * @notice Registers an entity with authority and enabled managers.
     * @param entityId Entity identifier.
     * @param typeId Entity type identifier.
     * @param metadataRef Offchain metadata reference.
     * @param authority Authority address for the entity.
     * @param managers Manager addresses to enable for the entity.
     */
    function registerEntity(
        bytes32 entityId,
        uint256 typeId,
        string calldata metadataRef,
        address authority,
        address[] calldata managers
    ) external;

    /**
     * @notice Registers a batch of entities.
     * @param entityIds Entity identifiers.
     * @param typeIds Entity type identifiers.
     * @param metadataRefs Offchain metadata references.
     */
    function registerEntityBatch(
        bytes32[] calldata entityIds,
        uint256[] calldata typeIds,
        string[] calldata metadataRefs
    ) external;

    /**
     * @notice Updates entity status.
     * @param entityId Entity identifier.
     * @param status New entity status.
     * @param reason Reason code for the status change.
     */
    function setEntityStatus(bytes32 entityId, EntityStatus status, bytes calldata reason) external;

    /**
     * @notice Updates entity metadata reference.
     * @param entityId Entity identifier.
     * @param metadataRef New metadata reference.
     */
    function setEntityMetadata(bytes32 entityId, string calldata metadataRef) external;

    /**
     * @notice Sets authority account for an entity.
     * @dev Registered authority accounts must be enabled and linked to `entityId`.
     * @param entityId Entity identifier.
     * @param authority Authority address.
     */
    function setEntityAuthority(bytes32 entityId, address authority) external;

    /**
     * @notice Enables or disables entity manager.
     * @dev Registered manager accounts must be enabled and linked to `entityId`.
     * @param entityId Entity identifier.
     * @param manager Manager address.
     * @param enabled New enabled flag.
     */
    function setEntityManager(bytes32 entityId, address manager, bool enabled) external;

    /**
     * @notice Updates account status.
     * @param account Account address.
     * @param status New account status.
     * @param reason Reason code for the status change.
     */
    function setAccountStatus(address account, AccountStatus status, bytes calldata reason) external;

    /**
     * @notice Updates account role flags.
     * @param account Account address.
     * @param roleFlags New role flags bitmask.
     */
    function setAccountRoleFlags(address account, uint256 roleFlags) external;

    /**
     * @notice Transfers account to another entity.
     * @dev Administrative relinking utility for operational cases (e.g. migrations/restructuring).
     *      This function does not change account ownership and is not a key-recovery mechanism.
     *      The account must not be the current authority or have its manager flag enabled for its source entity.
     * @param account Account address.
     * @param newEntityId Target entity identifier.
     */
    function transferAccountToEntity(address account, bytes32 newEntityId) external;

    /**
     * @notice Registers an account under an entity through the protocol admin path.
     * @dev Entity managers must use `requestAccountRegistration`; the account becomes active only after
     *      `acceptAccountRegistration`.
     * @param account Account address.
     * @param entityId Entity identifier.
     * @param roleFlags Account role flags bitmask metadata.
     */
    function registerAccount(address account, bytes32 entityId, uint256 roleFlags) external;

    /**
     * @notice Requests account registration under an entity.
     * @param account Account address asked to join the entity.
     * @param entityId Entity identifier.
     * @param roleFlags Account role flags bitmask metadata to apply on acceptance.
     */
    function requestAccountRegistration(address account, bytes32 entityId, uint256 roleFlags) external;

    /**
     * @notice Accepts a pending account registration for `msg.sender`.
     * @param entityId Entity identifier to join.
     */
    function acceptAccountRegistration(bytes32 entityId) external;

    /**
     * @notice Removes an account from registry.
     * @dev The account must not be the current authority or have its manager flag enabled for its linked entity.
     * @param account Account address.
     * @param reason Reason code for the removal.
     */
    function removeAccount(address account, bytes calldata reason) external;

    /**
     * @notice Grants roles to one user.
     * @param user User address.
     * @param roles Roles bitmask.
     */
    function grantRoles(address user, uint256 roles) external payable;

    /**
     * @notice Grants roles to multiple users.
     * @param users User addresses.
     * @param roles Roles bitmask.
     */
    function grantRoles(address[] calldata users, uint256 roles) external payable;

    /**
     * @notice Defines or updates entity type metadata.
     * @param typeId Entity type identifier.
     * @param name Non-zero entity type name.
     * @param caps Optional entity type capability bitmask.
     */
    function defineEntityType(uint256 typeId, bytes32 name, uint256 caps) external;

    /**
     * @notice Freezes an entity type.
     * @param typeId Entity type identifier.
     */
    function freezeEntityType(uint256 typeId) external;

    /**
     * @notice Returns entity record.
     * @param entityId Entity identifier.
     * @return entity Entity record.
     */
    function getEntity(bytes32 entityId) external view returns (Entity memory entity);

    /**
     * @notice Returns status for an entity.
     * @param entityId Entity identifier.
     * @return status Entity status.
     */
    function getEntityStatus(bytes32 entityId) external view returns (EntityStatus status);

    /**
     * @notice Returns entity metadata reference.
     * @param entityId Entity identifier.
     * @return metadataRef Offchain metadata reference.
     */
    function getEntityMetadataRef(bytes32 entityId) external view returns (string memory metadataRef);

    /**
     * @notice Returns account record.
     * @param account Account address.
     * @return accountRecord Account record.
     */
    function getAccount(address account) external view returns (Account memory accountRecord);

    /**
     * @notice Returns pending account registration details for an account/entity pair.
     * @param account Account address.
     * @param entityId Entity identifier.
     * @return request Pending registration data; `requester == address(0)` means no pending request.
     */
    function getPendingAccountRegistration(address account, bytes32 entityId)
        external
        view
        returns (PendingAccountRegistration memory request);

    /**
     * @notice Returns all accounts for an entity.
     * @param entityId Entity identifier.
     * @return accounts Entity accounts.
     */
    function getEntityAccounts(bytes32 entityId) external view returns (address[] memory accounts);

    /**
     * @notice Returns linked entity identifier for an account.
     * @param account Account address.
     * @return entityId Linked entity identifier.
     */
    function getEntityId(address account) external view returns (bytes32 entityId);

    /**
     * @notice Returns configured authority for an entity.
     * @param entityId Entity identifier.
     * @return authority Authority address.
     */
    function getEntityAuthority(bytes32 entityId) external view returns (address authority);

    /**
     * @notice Returns whether address is enabled manager for an entity.
     * @param entityId Entity identifier.
     * @param manager Manager address.
     * @return isManager True if manager is enabled for entity.
     */
    function isEntityManager(bytes32 entityId, address manager) external view returns (bool isManager);

    /**
     * @notice Returns entity type metadata.
     * @param typeId Entity type identifier.
     * @return meta Entity type metadata.
     */
    function getEntityTypeMeta(uint256 typeId) external view returns (EntityTypeMeta memory meta);

    /**
     * @notice Returns entity type id for an entity.
     * @param entityId Entity identifier.
     * @return typeId Entity type id.
     */
    function getEntityTypeId(bytes32 entityId) external view returns (uint256 typeId);

    /**
     * @notice Returns entity type id for an account.
     * @param account Account address.
     * @return typeId Entity type id.
     */
    function getEntityTypeIdByAccount(address account) external view returns (uint256 typeId);

    /**
     * @notice Returns whether account is registered.
     * @param account Account address.
     * @return exists True if account exists.
     */
    function doesAccountExist(address account) external view returns (bool exists);

    /**
     * @notice Returns whether account is registered.
     * @param account Account address.
     * @return registered True if registered.
     */
    function isAccountRegistered(address account) external view returns (bool registered);

    /**
     * @notice Returns whether account and linked entity are enabled.
     * @param account Account address.
     * @return enabled True if enabled.
     */
    function isAccountEnabled(address account) external view returns (bool enabled);

    /**
     * @notice Validates transfer participants against registry policy.
     * @param from Token sender.
     * @param to Token recipient.
     * @param operator Transfer operator.
     * @param tokenId Token identifier.
     * @param amount Transfer amount.
     * @return allowed True if transfer is allowed.
     */
    function canTransfer(address from, address to, address operator, uint256 tokenId, uint256 amount)
        external
        view
        returns (bool allowed);

    /**
     * @notice Validates approval participants against registry policy.
     * @param owner Token owner.
     * @param spender Approval spender.
     * @param tokenId Token identifier.
     * @param amount Approval amount.
     * @return allowed True if approval is allowed.
     */
    function canApprove(address owner, address spender, uint256 tokenId, uint256 amount)
        external
        view
        returns (bool allowed);
}
