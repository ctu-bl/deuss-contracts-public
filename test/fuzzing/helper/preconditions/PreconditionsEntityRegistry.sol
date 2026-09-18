// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore */

import {EntityStatus, AccountStatus} from "src/registry/EntityStructs.sol";
import {EntityBucket, FuzzAccountBucket, FuzzEntityBucket} from "../FuzzStateIndex.sol";
import {PreconditionsBase} from "./PreconditionsBase.sol";

abstract contract PreconditionsEntityRegistry is PreconditionsBase {
    struct RegisterEntityParams {
        bytes32 entityId;
        uint256 typeId;
    }

    struct SetEntityStatusParams {
        bytes32 entityId;
        EntityStatus status;
    }

    struct RegisterAccountParams {
        address wallet;
        bytes32 entityId;
        address manager;
        bool managerAuthorized;
    }

    struct RequestAccountRegistrationParams {
        address wallet;
        bool requesterAuthorized;
        address requester;
        bytes32 entityId;
        uint256 roleFlags;
    }

    struct AcceptAccountRegistrationParams {
        address wallet;
        bool accountRegistered;
        bool entityEnabled;
        bool requesterAuthorized;
        address requester;
        bytes32 entityId;
        uint256 roleFlags;
    }

    struct AdminRegisterAccountParams {
        address wallet;
        bytes32 entityId;
        uint256 roleFlags;
    }

    struct SetAccountStatusParams {
        address wallet;
        AccountStatus status;
    }

    struct RemoveAccountParams {
        address wallet;
        bytes32 entityId;
    }

    struct TransferAccountParams {
        address wallet;
        bytes32 oldEntityId;
        bytes32 newEntityId;
    }

    struct SetEntityManagerParams {
        bytes32 entityId;
        address manager;
        bool enabled;
    }

    // Entity types eligible for registration by fuzz handlers.
    uint256 internal constant ER_TYPE_COUNT = 3;

    function registerEntityPreconditions(uint256 typeIdSeed) internal returns (RegisterEntityParams memory params) {
        // Generate a unique entity ID from the harness address and the current nonce.
        params.entityId = keccak256(abi.encodePacked(address(this), entityNonce));
        require(params.entityId != bytes32(0), ClampFail("entity id is zero"));

        ++entityNonce;

        uint256[3] memory types = [BROKER_ENTITY, NATURAL_PERSON_ENTITY, DEUSS_PROTOCOL_ENTITY];
        params.typeId = types[typeIdSeed % ER_TYPE_COUNT];
    }

    function setEntityStatusPreconditions(uint256 entitySeed, bool enable)
        internal
        returns (SetEntityStatusParams memory params)
    {
        // Only mutate fuzz-created entities so setup entities used by the
        // Marketplace vertical slice are never accidentally disabled.
        (bool found, bytes32 entityId) = _pickFuzzEntityFromBucket(FuzzEntityBucket.Existing, entitySeed);
        require(found, ClampFail("no fuzz entity to update status"));

        params.entityId = entityId;
        params.status = enable ? EntityStatus.ENABLED : EntityStatus.DISABLED;
    }

    function registerAccountPreconditions(uint256 walletSeed, uint256 entitySeed, uint256 managerSeed)
        internal
        returns (RegisterAccountParams memory params)
    {
        params.wallet = _freeFuzzWalletOrRevert(walletSeed);
        params.entityId = _enabledEntityOrRevert(entitySeed);
        params.manager = managers[managerSeed % managers.length];
        params.managerAuthorized = _isEntityManagerSet(params.entityId, params.manager);
    }

    function requestAccountRegistrationPreconditions(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 managerSeed,
        uint256 roleFlagsSeed
    ) internal returns (RequestAccountRegistrationParams memory params) {
        params.wallet = _freeFuzzWalletOrRevert(walletSeed);
        params.entityId = _enabledEntityOrRevert(entitySeed);
        params.requester = managers[managerSeed % managers.length];
        params.roleFlags = roleFlagsSeed;
        params.requesterAuthorized = _isEntityManagerSet(params.entityId, params.requester);
    }

    function authorizedRequestAccountRegistrationPreconditions(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 managerSeed,
        uint256 roleFlagsSeed
    ) internal returns (RequestAccountRegistrationParams memory params) {
        params.wallet = _freeFuzzWalletOrRevert(walletSeed);
        params.entityId = _enabledEntityOrRevert(entitySeed);
        params.requester = managers[managerSeed % managers.length];
        _ensureEntityManager(params.entityId, params.requester, true);
        params.roleFlags = roleFlagsSeed;
        params.requesterAuthorized = true;
    }

    function acceptAccountRegistrationPreconditions(uint256 pendingSeed)
        internal
        returns (AcceptAccountRegistrationParams memory params)
    {
        (bool found, address wallet, bytes32 entityId) = _pickTrackedPendingRegistration(pendingSeed);
        require(found, ClampFail("no pending registration"));

        params.wallet = wallet;
        params.entityId = entityId;

        AccountStatus accountStatus = AccountStatus.NONE;
        if (_isAccountRegistered(wallet)) {
            accountStatus = _getAccountData(wallet).status;
        }
        params.accountRegistered = accountStatus != AccountStatus.NONE;
        params.entityEnabled = _getEntityStatus(entityId) == EntityStatus.ENABLED;

        params.requester = _getPendingRegistration(wallet, entityId).requester;
        params.roleFlags = _getPendingRegistration(wallet, entityId).roleFlags;
        params.requesterAuthorized = entityRegistry.hasAnyRole(params.requester, entityRegistry.ADMIN_ROLE())
            || _isEntityManagerSet(entityId, params.requester);
    }

    function adminRegisterAccountPreconditions(uint256 walletSeed, uint256 entitySeed, uint256 roleFlagsSeed)
        internal
        returns (AdminRegisterAccountParams memory params)
    {
        params.wallet = _freeFuzzWalletOrRevert(walletSeed);
        params.entityId = _enabledEntityOrRevert(entitySeed);
        params.roleFlags = roleFlagsSeed;
    }

    function setAccountStatusPreconditions(uint256 walletSeed, bool enable)
        internal
        returns (SetAccountStatusParams memory params)
    {
        (bool found, address wallet) = _pickFuzzAccountFromBucket(FuzzAccountBucket.Registered, walletSeed);
        require(found, ClampFail("no wallet to update"));

        bytes32 entityId = _getAccountData(wallet).entityId;
        require(_getEntityStatus(entityId) == EntityStatus.ENABLED, ClampFail("account entity is not enabled"));

        params.wallet = wallet;
        params.status = enable ? AccountStatus.ENABLED : AccountStatus.DISABLED;
    }

    function removeAccountPreconditions(uint256 walletSeed) internal returns (RemoveAccountParams memory params) {
        (bool found, address wallet) = _pickFuzzAccountFromBucket(FuzzAccountBucket.Registered, walletSeed);
        require(found, ClampFail("no wallet to remove"));

        params.wallet = wallet;
        params.entityId = _getAccountData(wallet).entityId;
    }

    function transferAccountPreconditions(uint256 walletSeed, uint256 entitySeed)
        internal
        returns (TransferAccountParams memory params)
    {
        (bool walletFound, address wallet) = _pickFuzzAccountFromBucket(FuzzAccountBucket.Registered, walletSeed);
        require(walletFound, ClampFail("no wallet to move"));

        bytes32 oldEntityId = _getAccountData(wallet).entityId;
        require(_getEntityStatus(oldEntityId) == EntityStatus.ENABLED, ClampFail("source entity is not enabled"));

        (bool entityFound, bytes32 newEntityId) =
            _pickEntityFromBucketDifferentFrom(EntityBucket.Enabled, oldEntityId, entitySeed);
        require(entityFound, ClampFail("no dst entity"));

        params.wallet = wallet;
        params.oldEntityId = oldEntityId;
        params.newEntityId = newEntityId;
    }

    function setEntityManagerPreconditions(uint256 entitySeed, uint256 managerSeed, bool enabled)
        internal
        returns (SetEntityManagerParams memory params)
    {
        (bool found, bytes32 entityId) = _pickEntityFromBucket(EntityBucket.Existing, entitySeed);
        require(found, ClampFail("no entity for mgr"));

        address manager = managers[managerSeed % managers.length];

        params.entityId = entityId;
        params.manager = manager;
        params.enabled = enabled;
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _freeFuzzWalletOrRevert(uint256 walletSeed) internal returns (address wallet) {
        (bool found, address pickedWallet) = _pickFuzzAccountFromBucket(FuzzAccountBucket.Free, walletSeed);
        require(found, ClampFail("no free fuzz wallet to register"));
        return pickedWallet;
    }

    function _freeFuzzWalletDifferentFromOrRevert(uint256 walletSeed, address exclude)
        internal
        returns (address wallet)
    {
        for (uint256 i; i < FUZZ_STATE_INDEX_PICK_ATTEMPTS; ++i) {
            (bool found, address pickedWallet) =
                _pickFuzzAccountFromBucket(FuzzAccountBucket.Free, uint256(keccak256(abi.encode(walletSeed, i))));
            if (found && pickedWallet != exclude) {
                return pickedWallet;
            }
        }

        revert ClampFail("no spare free fuzz wallet");
    }

    function _enabledEntityOrRevert(uint256 entitySeed) internal returns (bytes32 entityId) {
        (bool found, bytes32 pickedEntityId) = _pickEntityFromBucket(EntityBucket.Enabled, entitySeed);
        require(found, ClampFail("no enabled entity"));
        return pickedEntityId;
    }

    function _enabledEntityDifferentFromOrRevert(uint256 entitySeed, bytes32 excludedEntity)
        internal
        returns (bytes32 entityId)
    {
        (bool found, bytes32 pickedEntityId) =
            _pickEntityFromBucketDifferentFrom(EntityBucket.Enabled, excludedEntity, entitySeed);
        require(found, ClampFail("no distinct enabled entity"));
        return pickedEntityId;
    }

    function _ensureEntityManager(bytes32 entityId, address manager, bool enabled) internal {
        if (_isEntityManagerSet(entityId, manager) == enabled) return;
        entityRegistry.setEntityManager(entityId, manager, enabled);
    }

    function _managerDifferentFrom(uint256 managerSeed, address excluded) internal view returns (address manager) {
        uint256 start = managerSeed % managers.length;
        for (uint256 i; i < managers.length; ++i) {
            address candidate = managers[(start + i) % managers.length];
            if (candidate != excluded) return candidate;
        }

        revert ClampFail("no distinct manager");
    }

    function _missingEntityId(uint256 seed) internal view returns (bytes32 entityId) {
        entityId = keccak256(abi.encodePacked("missing-entity", address(this), seed, entityNonce));
        require(entityId != bytes32(0), ClampFail("missing entity id zero"));
    }
}
