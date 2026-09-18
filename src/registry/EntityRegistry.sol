// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Initializable} from "solady/src/utils/Initializable.sol";
// DEUSS:
import {AddressExtensions} from "src/libs/AddressExtensions.sol";
import {Errors} from "src/libs/Errors.sol";
import {OwnableRolesExtension} from "src/utils/OwnableRolesExtension.sol";
import {IEntityRegistry} from "src/registry/interfaces/IEntityRegistry.sol";
import {EntityRegistryStorage} from "src/registry/EntityRegistryStorage.sol";
import {
    Entity,
    Account,
    EntityStatus,
    AccountStatus,
    EntityTypeMeta,
    PendingAccountRegistration,
    ScopedAccountKind
} from "src/registry/EntityStructs.sol";

// slither-disable-start uninitialized-state
/**
 * @title EntityRegistry
 * @author DEUSS Team
 * @notice EntityRegistry combines entity validation and account management.
 */
contract EntityRegistry is IEntityRegistry, EntityRegistryStorage, OwnableRolesExtension, Initializable {
    using AddressExtensions for address;

    /// @notice Role identifier for addresses authorized to manage registry data
    uint256 public constant ADMIN_ROLE = _ROLE_0;
    /// @notice Role for lifecycle guard actions
    uint256 public constant GUARD = _ROLE_1;
    /// @notice Role for onboarding operations
    uint256 public constant ONBOARDING = _ROLE_2;
    /// @notice Role for account migration and relinking governance
    uint256 public constant WALLET_TRANSFER = _ROLE_3;
    /// @notice Role identifier for accounts authorized to create, update, and freeze entity type metadata
    uint256 public constant ENTITY_TYPE_MANAGER = _ROLE_4;
    /// @notice Bitmask of all roles supported by entity registry
    uint256 public constant ALL_ROLES = ADMIN_ROLE | GUARD | ONBOARDING | WALLET_TRANSFER | ENTITY_TYPE_MANAGER;

    // solhint-disable-next-line use-natspec
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with owner
     * @param owner_ The address that will own the contract
     */
    function initialize(address owner_) external initializer {
        __EntityRegistry_init(owner_);
    }

    /*//////////////////////////////////////////////////////////////
                              ENTITY TYPES
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IEntityRegistry
     */
    function defineEntityType(uint256 typeId, bytes32 name, uint256 caps) external onlyRoles(ENTITY_TYPE_MANAGER) {
        _defineEntityType(typeId, name, caps);
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function freezeEntityType(uint256 typeId) external onlyRoles(ENTITY_TYPE_MANAGER) {
        _requireEntityTypeExists(typeId);
        EntityTypeMeta storage meta = _entityRegistryStorage().entityTypeMeta[typeId];
        meta.frozen = true;
        emit EntityTypeFrozen(typeId);
    }

    /*//////////////////////////////////////////////////////////////
                                ENTITIES
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IEntityRegistry
     */
    function registerEntity(bytes32 entityId, uint256 typeId, string calldata metadataRef)
        external
        onlyRoles(ONBOARDING)
    {
        _registerEntity(entityId, typeId, metadataRef);
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function registerEntity(
        bytes32 entityId,
        uint256 typeId,
        string calldata metadataRef,
        address authority,
        address[] calldata managers
    ) external onlyRoles(ONBOARDING) {
        authority.assertAddressNotZero();

        _registerEntity(entityId, typeId, metadataRef);

        _setEntityAuthority(entityId, authority);

        for (uint256 i; i < managers.length;) {
            address manager = managers[i];
            manager.assertAddressNotZero();

            _setEntityManager(entityId, manager, true);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function registerEntityBatch(
        bytes32[] calldata entityIds,
        uint256[] calldata typeIds,
        string[] calldata metadataRefs
    ) external onlyRoles(ONBOARDING) {
        require(entityIds.length == typeIds.length && entityIds.length == metadataRefs.length, Errors.LengthMismatch());
        for (uint256 i; i < entityIds.length;) {
            _registerEntity(entityIds[i], typeIds[i], metadataRefs[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function setEntityStatus(bytes32 entityId, EntityStatus status, bytes calldata reason) external onlyRoles(GUARD) {
        require(status != EntityStatus.NONE, Errors.ER__EntityStatusNone());
        _setEntityStatus(entityId, status, reason);
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function setEntityMetadata(bytes32 entityId, string calldata metadataRef) external onlyRoles(ONBOARDING) {
        _requireEntityExistsAndEnabled(entityId);
        Entity storage entity = _entityRegistryStorage().entities[entityId];

        entity.metadataRef = metadataRef;
        emit EntityMetadataUpdated(entityId, metadataRef);
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function setEntityAuthority(bytes32 entityId, address authority) external {
        authority.assertAddressNotZero();
        _requireEntityExistsAndAdminOrAuthority(entityId, msg.sender);

        _setEntityAuthority(entityId, authority);
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function setEntityManager(bytes32 entityId, address manager, bool enabled) external {
        manager.assertAddressNotZero();
        _requireEntityExistsAndAdminOrAuthority(entityId, msg.sender);

        _setEntityManager(entityId, manager, enabled);
    }

    /*//////////////////////////////////////////////////////////////
                                ACCOUNTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IEntityRegistry
     */
    function setAccountStatus(address account, AccountStatus status, bytes calldata reason) external onlyRoles(GUARD) {
        account.assertAddressNotZero();
        require(status != AccountStatus.NONE, Errors.ER__AccountStatusNone());

        Account storage accountRecord = _entityRegistryStorage().accounts[account];
        require(accountRecord.status != AccountStatus.NONE, Errors.ER__AccountNotRegistered(account));

        bytes32 entityId = accountRecord.entityId;
        _requireEntityEnabled(entityId);

        AccountStatus oldStatus = accountRecord.status;
        accountRecord.status = status;
        accountRecord.statusReason = reason;

        if (status == AccountStatus.DISABLED) {
            _invalidateScopedAssignments(account);
        }

        emit AccountStatusUpdated(account, oldStatus, status, reason);
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function setAccountRoleFlags(address account, uint256 roleFlags) external onlyRoles(ONBOARDING) {
        account.assertAddressNotZero();
        Account storage accountRecord = _entityRegistryStorage().accounts[account];
        require(accountRecord.status != AccountStatus.NONE, Errors.ER__AccountNotRegistered(account));
        _requireEntityEnabled(accountRecord.entityId);

        uint256 oldFlags = accountRecord.roleFlags;
        accountRecord.roleFlags = roleFlags;
        emit AccountRoleFlagsUpdated(account, accountRecord.entityId, roleFlags, oldFlags);
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function registerAccount(address account, bytes32 entityId, uint256 roleFlags) external onlyRoles(ADMIN_ROLE) {
        account.assertAddressNotZero();
        _requireEntityExistsAndEnabled(entityId);

        EntityRegistryState storage $ = _entityRegistryStorage();
        require($.accounts[account].status == AccountStatus.NONE, Errors.ER__AccountAlreadyRegistered(account));

        _registerAccount(account, entityId, roleFlags);
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function requestAccountRegistration(address account, bytes32 entityId, uint256 roleFlags) external {
        account.assertAddressNotZero();
        _requireEntityExistsAndEnabled(entityId);
        _requireEntityAdminOrManager(entityId, msg.sender);

        EntityRegistryState storage $ = _entityRegistryStorage();
        require($.accounts[account].status == AccountStatus.NONE, Errors.ER__AccountAlreadyRegistered(account));

        $.pendingAccountRegistrations[account][entityId] =
            PendingAccountRegistration({roleFlags: roleFlags, requester: msg.sender});

        emit AccountRegistrationRequested(account, entityId, roleFlags, msg.sender);
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function acceptAccountRegistration(bytes32 entityId) external {
        address account = msg.sender;
        _requireEntityExistsAndEnabled(entityId);

        EntityRegistryState storage $ = _entityRegistryStorage();
        require($.accounts[account].status == AccountStatus.NONE, Errors.ER__AccountAlreadyRegistered(account));

        PendingAccountRegistration storage pending = $.pendingAccountRegistrations[account][entityId];
        address requester = pending.requester;
        require(requester != address(0), Errors.ER__AccountRegistrationNotPending(account, entityId));

        _requireEntityAdminOrManager(entityId, requester);

        uint256 roleFlags = pending.roleFlags;
        delete $.pendingAccountRegistrations[account][entityId];

        _registerAccount(account, entityId, roleFlags);

        emit AccountRegistrationAccepted(account, entityId, roleFlags, requester);
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function removeAccount(address account, bytes calldata reason) external onlyRoles(WALLET_TRANSFER) {
        account.assertAddressNotZero();
        AccountStatus oldStatus = _removeAccount(account);

        emit AccountStatusUpdated(account, oldStatus, AccountStatus.NONE, reason);
    }

    /**
     * @inheritdoc IEntityRegistry
     * @dev Administrative relinking utility.
     *      This changes only account-to-entity linkage and does not alter account owner state.
     *      Source-entity authority/manager assignments must be revoked before relinking.
     * @dev Should be called only from a wallet using multisig with timelock.
     */
    function transferAccountToEntity(address account, bytes32 newEntityId) external onlyRoles(WALLET_TRANSFER) {
        account.assertAddressNotZero();
        _requireEntityExistsAndEnabled(newEntityId);

        Account storage accountRecord = _entityRegistryStorage().accounts[account];
        require(accountRecord.status != AccountStatus.NONE, Errors.ER__AccountNotRegistered(account));

        bytes32 oldEntityId = accountRecord.entityId;
        _requireEntityEnabled(oldEntityId);
        require(oldEntityId != newEntityId, Errors.ER__AccountAlreadyLinked(account, newEntityId));
        _requireAccountNotEntityGovernance(oldEntityId, account);

        _invalidateScopedAssignments(account);
        _removeAccountFromEntity(oldEntityId, account);
        accountRecord.entityId = newEntityId;
        _addAccountToEntity(newEntityId, account);

        emit AccountEntityTransferred(account, oldEntityId, newEntityId);
    }

    /*//////////////////////////////////////////////////////////////
                               VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IEntityRegistry
     */
    function canTransfer(address from, address to, address operator, uint256, uint256) external view returns (bool) {
        if (!_isAccountEnabledOrZeroAddress(from)) return false;
        if (!_isAccountEnabledOrZeroAddress(to)) return false;
        if (!_isAccountEnabledOrZeroAddress(operator)) return false;
        return true;
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function canApprove(address owner, address spender, uint256, uint256) external view returns (bool) {
        if (!_isAccountEnabledOrZeroAddress(owner)) return false;
        if (!_isAccountEnabledOrZeroAddress(spender)) return false;
        return true;
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function isAccountRegistered(address account) external view returns (bool) {
        return _entityRegistryStorage().accounts[account].status != AccountStatus.NONE;
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function isAccountEnabled(address account) external view returns (bool) {
        return _isAccountEnabled(account);
    }

    /*//////////////////////////////////////////////////////////////
                    EXTERNAL FUNCTIONS THAT ARE VIEW
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IEntityRegistry
     */
    function doesAccountExist(address account) external view returns (bool) {
        return _entityRegistryStorage().accounts[account].status != AccountStatus.NONE;
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function getEntity(bytes32 entityId) external view returns (Entity memory) {
        _requireEntityExists(entityId);
        return _entityRegistryStorage().entities[entityId];
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function getEntityStatus(bytes32 entityId) external view returns (EntityStatus) {
        _requireEntityExists(entityId);
        return _entityRegistryStorage().entities[entityId].status;
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function getEntityMetadataRef(bytes32 entityId) external view returns (string memory) {
        _requireEntityExists(entityId);
        return _entityRegistryStorage().entities[entityId].metadataRef;
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function getAccount(address account) external view returns (Account memory) {
        _requireAccountExists(account);
        return _entityRegistryStorage().accounts[account];
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function getPendingAccountRegistration(address account, bytes32 entityId)
        external
        view
        returns (PendingAccountRegistration memory)
    {
        return _entityRegistryStorage().pendingAccountRegistrations[account][entityId];
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function getEntityAccounts(bytes32 entityId) external view returns (address[] memory) {
        _requireEntityExists(entityId);
        return _entityRegistryStorage().entities[entityId].accounts;
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function getEntityId(address account) external view returns (bytes32) {
        _requireAccountExists(account);
        return _entityRegistryStorage().accounts[account].entityId;
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function getEntityAuthority(bytes32 entityId) external view returns (address) {
        _requireEntityExists(entityId);
        return _entityRegistryStorage().entityAuthorities[entityId];
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function isEntityManager(bytes32 entityId, address manager) external view returns (bool) {
        _requireEntityExists(entityId);
        return _isEntityManagerEnabled(entityId, manager);
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function getEntityTypeMeta(uint256 typeId) external view returns (EntityTypeMeta memory) {
        _requireEntityTypeExists(typeId);
        return _entityRegistryStorage().entityTypeMeta[typeId];
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function getEntityTypeId(bytes32 entityId) external view returns (uint256) {
        _requireEntityExists(entityId);
        return _entityRegistryStorage().entities[entityId].typeId;
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function getEntityTypeIdByAccount(address account) external view returns (uint256) {
        _requireAccountExists(account);
        _requireEntityExists(_entityRegistryStorage().accounts[account].entityId);
        return _entityRegistryStorage().entities[_entityRegistryStorage().accounts[account].entityId].typeId;
    }

    /*//////////////////////////////////////////////////////////////
                                  RBAC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IEntityRegistry
     */
    function grantRoles(address user, uint256 roles)
        public
        payable
        override(IEntityRegistry, OwnableRolesExtension)
        onlyOwner
    {
        _requireValidRoles(roles);

        super.grantRoles(user, roles);
    }

    /**
     * @inheritdoc IEntityRegistry
     */
    function grantRoles(address[] calldata users, uint256 roles)
        public
        payable
        override(IEntityRegistry, OwnableRolesExtension)
        onlyOwner
    {
        _requireValidRoles(roles);

        super.grantRoles(users, roles);
    }

    /*//////////////////////////////////////////////////////////////
                    PUBLIC FUNCTIONS THAT ARE PURE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IEntityRegistry).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /*//////////////////////////////////////////////////////////////
                     INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /* solhint-enable no-empty-blocks */

    /* solhint-disable func-name-mixedcase */
    /**
     * @notice Initializes the contract with owner
     * @param owner_ The address that will own the contract
     */
    function __EntityRegistry_init(address owner_) internal onlyInitializing {
        owner_.assertAddressNotZero();
        _initializeOwner(owner_);
    }

    /* solhint-enable func-name-mixedcase */

    /**
     * @notice Defines or updates an entity type with the given metadata.
     * @param typeId The entity type identifier; must be non-zero.
     * @param name The human-readable name of the entity type; must be non-zero.
     * @param caps Capability bitmask associated with the entity type.
     */
    function _defineEntityType(uint256 typeId, bytes32 name, uint256 caps) internal {
        require(typeId != 0, Errors.ER__EntityTypeIdZero());
        require(name != bytes32(0), Errors.ER__EntityTypeNameZero(typeId));
        EntityTypeMeta storage meta = _entityRegistryStorage().entityTypeMeta[typeId];
        require(!meta.frozen, Errors.ER__EntityTypeFrozen(typeId));
        meta.name = name;
        meta.caps = caps;
        emit EntityTypeMetaUpdated(typeId, name, caps);
    }

    /**
     * @notice Registers a new entity in the registry.
     * @param entityId The entity identifier.
     * @param typeId The entity type identifier.
     * @param metadataRef Offchain metadata reference.
     */
    function _registerEntity(bytes32 entityId, uint256 typeId, string memory metadataRef) internal {
        require(entityId != bytes32(0), Errors.ER__EntityIdZero());
        require(typeId != 0, Errors.ER__EntityTypeIdZero());
        require(
            _entityRegistryStorage().entityTypeMeta[typeId].name != bytes32(0),
            Errors.ER__EntityTypeNotRegistered(typeId)
        );
        require(
            _entityRegistryStorage().entities[entityId].status == EntityStatus.NONE,
            Errors.ER__EntityAlreadyRegistered(entityId)
        );

        Entity storage entity = _entityRegistryStorage().entities[entityId];
        entity.typeId = typeId;
        entity.status = EntityStatus.ENABLED;
        entity.metadataRef = metadataRef;
        entity.statusReason = "";
        emit EntityRegistered(entityId, typeId, metadataRef);
    }

    /**
     * @notice Registers a new account against an entity with role flags.
     * @param account Account address being registered.
     * @param entityId Entity identifier linked to the account.
     * @param roleFlags Account role bitmask metadata.
     */
    function _registerAccount(address account, bytes32 entityId, uint256 roleFlags) internal {
        _entityRegistryStorage().accounts[account] = Account({
            entityId: entityId,
            status: AccountStatus.ENABLED,
            statusReason: "",
            roleFlags: roleFlags,
            entityAccountIndex: 0
        });

        _addAccountToEntity(entityId, account);

        emit AccountRegistered(account, entityId, roleFlags);
    }

    /**
     * @notice Updates the entity status with safety checks.
     * @param entityId Entity identifier.
     * @param status New entity status.
     * @param reason Reason code for the status change.
     */
    function _setEntityStatus(bytes32 entityId, EntityStatus status, bytes memory reason) internal {
        _requireEntityExists(entityId);
        Entity storage entity = _entityRegistryStorage().entities[entityId];

        EntityStatus oldStatus = entity.status;
        entity.status = status;
        entity.statusReason = reason;
        emit EntityStatusUpdated(entityId, oldStatus, status, reason);
    }

    /**
     * @notice Adds an account to an entity index.
     * @param entityId Entity identifier.
     * @param account Account address.
     */
    function _addAccountToEntity(bytes32 entityId, address account) internal {
        Entity storage entity = _entityRegistryStorage().entities[entityId];
        entity.accounts.push(account);
        _entityRegistryStorage().accounts[account].entityAccountIndex = entity.accounts.length;
    }

    /**
     * @notice Removes an account from an entity index.
     * @param entityId Entity identifier.
     * @param account Account address.
     */
    function _removeAccountFromEntity(bytes32 entityId, address account) internal {
        uint256 index = _entityRegistryStorage().accounts[account].entityAccountIndex;
        require(index != 0, Errors.ER__AccountNotRegistered(account));

        Entity storage entity = _entityRegistryStorage().entities[entityId];
        uint256 lastIndex = entity.accounts.length;
        if (index != lastIndex) {
            address lastAccount = entity.accounts[lastIndex - 1];
            entity.accounts[index - 1] = lastAccount;
            _entityRegistryStorage().accounts[lastAccount].entityAccountIndex = index;
        }

        entity.accounts.pop();
        _entityRegistryStorage().accounts[account].entityAccountIndex = 0;
    }

    /**
     * @notice Removes an account and clears its registry record.
     * @param account Account address.
     * @return oldStatus Previous account status before removal.
     */
    function _removeAccount(address account) internal returns (AccountStatus oldStatus) {
        Account storage accountRecord = _entityRegistryStorage().accounts[account];
        oldStatus = accountRecord.status;
        require(oldStatus != AccountStatus.NONE, Errors.ER__AccountNotRegistered(account));

        bytes32 entityId = accountRecord.entityId;
        _requireAccountNotEntityGovernance(entityId, account);
        _invalidateScopedAssignments(account);

        _removeAccountFromEntity(entityId, account);
        delete _entityRegistryStorage().accounts[account];
    }

    /**
     * @notice Ensures an account is not still a governance actor for the entity it leaves.
     * @param entityId Entity identifier being left.
     * @param account Account address being removed or relinked.
     */
    function _requireAccountNotEntityGovernance(bytes32 entityId, address account) internal view {
        EntityRegistryState storage $ = _entityRegistryStorage();
        require($.entityAuthorities[entityId] != account, Errors.ER__AccountIsEntityAuthority(account, entityId));
        require(!$.entityManagers[entityId][account], Errors.ER__AccountIsEntityManager(account, entityId));
    }

    /**
     * @notice Sets an authority after validating registered account state.
     * @param entityId Entity identifier.
     * @param authority Authority address.
     */
    function _setEntityAuthority(bytes32 entityId, address authority) internal {
        EntityRegistryState storage $ = _entityRegistryStorage();
        address previousAuthority = $.entityAuthorities[entityId];
        if (previousAuthority == authority && _isEntityAuthorityEnabled(entityId, authority)) {
            revert Errors.ER__EntityAuthorityAlreadySet(entityId, authority);
        }

        _requireRegisteredScopedAccountEnabledForEntity(entityId, authority, ScopedAccountKind.AUTHORITY);

        $.entityAuthorities[entityId] = authority;
        $.entityAuthorityAssignmentNonce[entityId] = $.accountScopedAssignmentNonce[authority];

        emit EntityAuthorityUpdated(entityId, previousAuthority, authority);
    }

    /**
     * @notice Enables or disables a manager after validating registered account state.
     * @param entityId Entity identifier.
     * @param manager Manager address.
     * @param enabled New manager flag.
     */
    function _setEntityManager(bytes32 entityId, address manager, bool enabled) internal {
        EntityRegistryState storage $ = _entityRegistryStorage();
        if (enabled) {
            _requireRegisteredScopedAccountEnabledForEntity(entityId, manager, ScopedAccountKind.MANAGER);
            $.entityManagerAssignmentNonce[entityId][manager] = $.accountScopedAssignmentNonce[manager];
        } else {
            delete $.entityManagerAssignmentNonce[entityId][manager];
        }

        $.entityManagers[entityId][manager] = enabled;

        emit EntityManagerUpdated(entityId, manager, enabled);
    }

    /**
     * @notice Invalidates scoped assignments tied to the current account lifecycle.
     * @param account Account whose lifecycle changed.
     */
    function _invalidateScopedAssignments(address account) internal {
        ++_entityRegistryStorage().accountScopedAssignmentNonce[account];
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNAL VIEW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks whether the account and its entity are enabled.
     * @param account Account address.
     * @return isEnabled True if account and linked entity are enabled.
     */
    function _isAccountEnabled(address account) internal view returns (bool) {
        Account storage accountRecord = _entityRegistryStorage().accounts[account];
        if (accountRecord.status != AccountStatus.ENABLED) {
            return false;
        }

        Entity storage entity = _entityRegistryStorage().entities[accountRecord.entityId];
        if (entity.status != EntityStatus.ENABLED) {
            return false;
        }
        return true;
    }

    /**
     * @notice Checks if an address is enabled or is the zero address.
     * @param addr Address to validate.
     * @return isAllowed True if zero address or enabled account.
     */
    function _isAccountEnabledOrZeroAddress(address addr) internal view returns (bool) {
        if (addr == address(0)) {
            return true;
        }
        return _isAccountEnabled(addr);
    }

    /**
     * @notice Checks whether a manager flag is currently effective for an entity.
     * @param entityId Entity identifier.
     * @param manager Manager address.
     * @return enabled True when the manager flag is set and registered account state does not invalidate it.
     */
    function _isEntityManagerEnabled(bytes32 entityId, address manager) internal view returns (bool enabled) {
        EntityRegistryState storage $ = _entityRegistryStorage();
        if (!$.entityManagers[entityId][manager]) {
            return false;
        }

        if ($.entityManagerAssignmentNonce[entityId][manager] != $.accountScopedAssignmentNonce[manager]) {
            return false;
        }

        Account storage managerAccount = $.accounts[manager];
        if (managerAccount.status == AccountStatus.NONE) {
            return true;
        }

        return managerAccount.status == AccountStatus.ENABLED && managerAccount.entityId == entityId;
    }

    /**
     * @notice Checks whether an authority is currently effective for an entity.
     * @param entityId Entity identifier.
     * @param authority Authority address.
     * @return enabled True when the authority assignment is not invalidated by account lifecycle state.
     */
    function _isEntityAuthorityEnabled(bytes32 entityId, address authority) internal view returns (bool enabled) {
        EntityRegistryState storage $ = _entityRegistryStorage();
        if ($.entityAuthorities[entityId] != authority) {
            return false;
        }

        if ($.entityAuthorityAssignmentNonce[entityId] != $.accountScopedAssignmentNonce[authority]) {
            return false;
        }

        Account storage authorityAccount = $.accounts[authority];
        if (authorityAccount.status == AccountStatus.NONE) {
            return true;
        }

        return authorityAccount.status == AccountStatus.ENABLED && authorityAccount.entityId == entityId;
    }

    /**
     * @notice Ensures an account record exists.
     * @param account Account address.
     */
    function _requireAccountExists(address account) internal view {
        require(
            _entityRegistryStorage().accounts[account].status != AccountStatus.NONE,
            Errors.ER__AccountNotRegistered(account)
        );
    }

    /**
     * @notice Ensures the entity exists and is registered.
     * @param entityId Entity identifier.
     */
    function _requireEntityExists(bytes32 entityId) internal view {
        require(entityId != bytes32(0), Errors.ER__EntityIdZero());
        require(
            _entityRegistryStorage().entities[entityId].status != EntityStatus.NONE,
            Errors.ER__EntityNotRegistered(entityId)
        );
    }

    /**
     * @notice Ensures an entity type exists.
     * @param typeId Entity type identifier.
     */
    function _requireEntityTypeExists(uint256 typeId) internal view {
        require(typeId != 0, Errors.ER__EntityTypeIdZero());

        EntityTypeMeta storage meta = _entityRegistryStorage().entityTypeMeta[typeId];
        require(meta.name != bytes32(0), Errors.ER__EntityTypeNotRegistered(typeId));
    }

    /**
     * @notice Ensures the entity is enabled.
     * @param entityId Entity identifier.
     */
    function _requireEntityEnabled(bytes32 entityId) internal view {
        require(
            _entityRegistryStorage().entities[entityId].status == EntityStatus.ENABLED,
            Errors.ER__EntityNotEnabled(entityId)
        );
    }

    /**
     * @notice Ensures an entity exists and is enabled.
     * @param entityId Entity identifier.
     */
    function _requireEntityExistsAndEnabled(bytes32 entityId) internal view {
        require(entityId != bytes32(0), Errors.ER__EntityIdZero());

        EntityStatus status = _entityRegistryStorage().entities[entityId].status;
        require(status != EntityStatus.NONE, Errors.ER__EntityNotRegistered(entityId));
        require(status == EntityStatus.ENABLED, Errors.ER__EntityNotEnabled(entityId));
    }

    /**
     * @notice Ensures the role mask contains only known roles for this contract.
     * @param roles Role mask provided in the call.
     */
    function _requireValidRoles(uint256 roles) internal pure {
        require(roles & ~ALL_ROLES == 0, Errors.InvalidRoles());
    }

    /**
     * @notice Requires a registered scoped account to be enabled and linked to the scoped entity.
     * @param entityId Entity identifier.
     * @param account Account address.
     * @param kind Scoped account kind used to preserve role-specific errors.
     */
    function _requireRegisteredScopedAccountEnabledForEntity(bytes32 entityId, address account, ScopedAccountKind kind)
        internal
        view
    {
        Account storage accountRecord = _entityRegistryStorage().accounts[account];
        if (accountRecord.status == AccountStatus.NONE) {
            // @dev early return: Account is not registered to any entity (and it does not have to be registered).
            return;
        }
        if (accountRecord.status != AccountStatus.ENABLED) {
            if (kind == ScopedAccountKind.AUTHORITY) {
                revert Errors.ER__EntityAuthorityAccountNotEnabled(account, entityId);
            }
            revert Errors.ER__EntityManagerAccountNotEnabled(account, entityId);
        }
        if (accountRecord.entityId != entityId) {
            if (kind == ScopedAccountKind.AUTHORITY) {
                revert Errors.ER__EntityAuthorityAccountLinkedToDifferentEntity(
                    account, entityId, accountRecord.entityId
                );
            }
            revert Errors.ER__EntityManagerAccountLinkedToDifferentEntity(account, entityId, accountRecord.entityId);
        }
    }

    /**
     * @notice Ensures caller is entity authority or protocol admin.
     * @param entityId Entity identifier.
     * @param sender Caller address.
     */
    function _requireEntityAdminOrAuthority(bytes32 entityId, address sender) internal view {
        if (hasAnyRole(sender, ADMIN_ROLE)) {
            return;
        }
        require(_isEntityAuthorityEnabled(entityId, sender), Errors.ER__NotEntityAuthorityOrAdmin(sender, entityId));
    }

    /**
     * @notice Ensures entity exists and sender is authority or protocol admin.
     * @param entityId Entity identifier.
     * @param sender Caller address.
     */
    function _requireEntityExistsAndAdminOrAuthority(bytes32 entityId, address sender) internal view {
        _requireEntityExists(entityId);
        _requireEntityAdminOrAuthority(entityId, sender);
    }

    /**
     * @notice Ensures caller is entity manager or protocol admin.
     * @param entityId Entity identifier.
     * @param sender Caller address.
     */
    function _requireEntityAdminOrManager(bytes32 entityId, address sender) internal view {
        if (hasAnyRole(sender, ADMIN_ROLE)) {
            return;
        }
        require(_isEntityManagerEnabled(entityId, sender), Errors.ER__NotEntityManagerOrAdmin(sender, entityId));
    }
}

// slither-disable-end uninitialized-state
