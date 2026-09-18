// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable gas-small-strings */

import {Errors} from "src/libs/Errors.sol";
import {EntityRegistry} from "src/registry/EntityRegistry.sol";
import {AccountStatus, EntityStatus} from "src/registry/EntityStructs.sol";
import {EntityBucket} from "../FuzzStateIndex.sol";
import {PreconditionsEntityRegistry} from "../preconditions/PreconditionsEntityRegistry.sol";
import {PostconditionsEntityRegistry} from "../postconditions/PostconditionsEntityRegistry.sol";

/// @title HandlerEntityRegistry
/// @notice Stateful fuzz handlers for the EntityRegistry vertical slice.
abstract contract HandlerEntityRegistry is PreconditionsEntityRegistry, PostconditionsEntityRegistry {
    /// @notice Registers a new fuzz entity with the given type seed.
    /// @dev The entity ID is deterministically derived from address(this) and the current nonce.
    ///      On success the entity is added to both knownEntityIds and knownFuzzEntityIds so later
    ///      handlers can pick it as a target.
    /// @param typeIdSeed Seed used to select one of the three defined entity types.
    function handler_registerEntity(uint256 typeIdSeed) public {
        RegisterEntityParams memory params = registerEntityPreconditions(typeIdSeed);

        bytes32[] memory entityIdsToUpdate = _emptyBytes32Array();
        _beforeER(entityIdsToUpdate, _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(_REGISTER_ENTITY_SELECTOR, params.entityId, params.typeId, EMPTY_METADATA_REF)
        );

        if (success) {
            _trackFuzzEntityId(params.entityId);
        }

        registerEntityPostconditions(success, returnData, params);

        if (success) {
            _syncEntity(params.entityId);
            _syncFuzzEntity(params.entityId);
        }
    }

    /// @notice Enables or disables a fuzz-created entity.
    /// @dev Only fuzz-created entities are targeted so the setup entities that back the
    ///      Marketplace actors are not inadvertently disabled.
    /// @param entitySeed Seed used to select a tracked fuzz entity.
    /// @param enable True to enable, false to disable.
    function handler_setEntityStatus(uint256 entitySeed, bool enable) public {
        SetEntityStatusParams memory params = setEntityStatusPreconditions(entitySeed, enable);

        bytes32[] memory entityIds = _singleBytes32Array(params.entityId);
        _beforeER(entityIds, _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.setEntityStatus.selector, params.entityId, params.status, bytes(""))
        );

        setEntityStatusPostconditions(success, returnData, params);

        if (success) {
            _syncEntity(params.entityId);
            _syncFuzzEntity(params.entityId);
        }
    }

    /// @notice Requests and accepts registration for a free wallet into a tracked enabled entity.
    /// @dev The caller is drawn from the dedicated managers pool, so this exercises the real
    ///      manager authorization path on EntityRegistry.requestAccountRegistration instead of the
    ///      harness' ADMIN_ROLE override. On request success, the wallet accepts its pending
    ///      registration. On full success the wallet is marked as a registered fuzz account so later
    ///      handlers can pick it for status changes, transfers, and removal.
    /// @param walletSeed Seed used to select an unregistered wallet from fuzzWallets.
    /// @param entitySeed Seed used to select a currently enabled entity.
    /// @param managerSeed Seed used to select a caller from the managers pool.
    function handler_registerAccount(uint256 walletSeed, uint256 entitySeed, uint256 managerSeed) public {
        RegisterAccountParams memory params = registerAccountPreconditions(walletSeed, entitySeed, managerSeed);

        bytes32[] memory entityIds = _singleBytes32Array(params.entityId);
        address[] memory accounts = _singleActorArray(params.wallet);
        _beforeER(entityIds, accounts);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(
                entityRegistry.requestAccountRegistration.selector, params.wallet, params.entityId, ROLE_FLAGS_EMPTY
            ),
            params.manager
        );

        if (success) {
            (success, returnData) = fl.doFunctionCall(
                address(entityRegistry),
                abi.encodeWithSelector(entityRegistry.acceptAccountRegistration.selector, params.entityId),
                params.wallet
            );
        }

        if (success) {
            _setFuzzAccountRegistered(params.wallet, true);
        }

        registerAccountPostconditions(success, returnData, params);
    }

    /// @notice Creates a pending account-registration request without accepting it in the same fuzz step.
    /// @param walletSeed Seed used to select an unregistered wallet from fuzzWallets.
    /// @param entitySeed Seed used to select a currently enabled entity.
    /// @param managerSeed Seed used to select a caller from the managers pool.
    /// @param roleFlagsSeed Seed used as the requested role flags.
    function handler_requestAccountRegistration(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 managerSeed,
        uint256 roleFlagsSeed
    ) public {
        RequestAccountRegistrationParams memory params = requestAccountRegistrationPreconditions(
            walletSeed, entitySeed, managerSeed, roleFlagsSeed
        );

        bytes32[] memory entityIds = _singleBytes32Array(params.entityId);
        address[] memory accounts = _singleActorArray(params.wallet);
        _beforeER(entityIds, accounts);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(
                entityRegistry.requestAccountRegistration.selector, params.wallet, params.entityId, params.roleFlags
            ),
            params.requester
        );

        requestAccountRegistrationPostconditions(success, returnData, params);
    }

    /// @notice Accepts a previously tracked pending account-registration request in a later fuzz step.
    /// @param pendingSeed Seed used to select a tracked pending `(account, entityId)` pair.
    function handler_acceptAccountRegistration(uint256 pendingSeed) public {
        AcceptAccountRegistrationParams memory params = acceptAccountRegistrationPreconditions(pendingSeed);

        bytes32[] memory entityIds = _singleBytes32Array(params.entityId);
        address[] memory accounts = _singleActorArray(params.wallet);
        _beforeER(entityIds, accounts);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.acceptAccountRegistration.selector, params.entityId),
            params.wallet
        );

        acceptAccountRegistrationPostconditions(success, returnData, params);
    }

    /// @notice Requests the same `(account, entityId)` twice and verifies latest request data wins.
    /// @param walletSeed Seed used to select an unregistered wallet from fuzzWallets.
    /// @param entitySeed Seed used to select a currently enabled entity.
    /// @param managerSeed Seed used to select distinct requester managers.
    /// @param roleFlagsSeed Seed used to derive both role-flag values.
    function handler_requestAccountRegistrationOverwrite(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 managerSeed,
        uint256 roleFlagsSeed
    ) public {
        address wallet = _freeFuzzWalletOrRevert(walletSeed);
        bytes32 entityId = _enabledEntityOrRevert(entitySeed);
        address firstRequester = managers[managerSeed % managers.length];
        address secondRequester = _managerDifferentFrom(_deriveSeed(managerSeed, "overwrite-manager"), firstRequester);
        uint256 firstRoleFlags = roleFlagsSeed;
        uint256 secondRoleFlags = _deriveSeed(roleFlagsSeed, "overwrite-role-flags");

        _ensureEntityManager(entityId, firstRequester, true);
        _ensureEntityManager(entityId, secondRequester, true);

        bytes32[] memory entityIds = _singleBytes32Array(entityId);
        address[] memory accounts = _singleActorArray(wallet);
        _beforeER(entityIds, accounts);

        if (!_requestPendingRegistration(
                wallet, entityId, firstRoleFlags, firstRequester, "ER-PENDING-OVERWRITE: first request reverted"
            )) {
            return;
        }

        if (_requestPendingRegistration(
                wallet, entityId, secondRoleFlags, secondRequester, "ER-PENDING-OVERWRITE: second request reverted"
            )) {
            _trackPendingRegistration(wallet, entityId);
            requestAccountRegistrationOverwritePostconditions(wallet, entityId, secondRoleFlags, secondRequester);
        }
    }

    /// @notice Creates simultaneous pending requests for one account across two entities.
    /// @param walletSeed Seed used to select an unregistered wallet from fuzzWallets.
    /// @param entitySeed Seed used to select the first enabled entity.
    /// @param otherEntitySeed Seed used to select a second enabled entity.
    /// @param managerSeed Seed used to select the authorized requester manager.
    /// @param roleFlagsSeed Seed used to derive both role-flag values.
    function handler_requestAccountRegistrationMultipleEntities(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 otherEntitySeed,
        uint256 managerSeed,
        uint256 roleFlagsSeed
    ) public {
        address wallet = _freeFuzzWalletOrRevert(walletSeed);
        bytes32 entityIdA = _enabledEntityOrRevert(entitySeed);
        bytes32 entityIdB = _enabledEntityDifferentFromOrRevert(otherEntitySeed, entityIdA);
        address requester = managers[managerSeed % managers.length];
        uint256 roleFlagsA = roleFlagsSeed;
        uint256 roleFlagsB = _deriveSeed(roleFlagsSeed, "multi-entity-role-flags");

        _ensureEntityManager(entityIdA, requester, true);
        _ensureEntityManager(entityIdB, requester, true);

        bytes32[] memory entityIds = _twoBytes32Array(entityIdA, entityIdB);
        address[] memory accounts = _singleActorArray(wallet);
        _beforeER(entityIds, accounts);

        if (!_requestPendingRegistration(
                wallet, entityIdA, roleFlagsA, requester, "ER-PENDING-MULTI: first request reverted"
            )) {
            return;
        }

        if (_requestPendingRegistration(
                wallet, entityIdB, roleFlagsB, requester, "ER-PENDING-MULTI: second request reverted"
            )) {
            _trackPendingRegistration(wallet, entityIdA);
            _trackPendingRegistration(wallet, entityIdB);
            requestAccountRegistrationMultipleEntitiesPostconditions(
                wallet, entityIdA, entityIdB, roleFlagsA, roleFlagsB, requester
            );
        }
    }

    /// @notice Registers a free fuzz wallet directly through the admin-only `registerAccount` path.
    /// @param walletSeed Seed used to select an unregistered wallet from fuzzWallets.
    /// @param entitySeed Seed used to select a currently enabled entity.
    /// @param roleFlagsSeed Seed used as the stored account role flags.
    function handler_adminRegisterAccount(uint256 walletSeed, uint256 entitySeed, uint256 roleFlagsSeed) public {
        AdminRegisterAccountParams memory params =
            adminRegisterAccountPreconditions(walletSeed, entitySeed, roleFlagsSeed);

        bytes32[] memory entityIds = _singleBytes32Array(params.entityId);
        address[] memory accounts = _singleActorArray(params.wallet);
        _beforeER(entityIds, accounts);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(
                entityRegistry.registerAccount.selector, params.wallet, params.entityId, params.roleFlags
            ),
            address(this)
        );

        adminRegisterAccountPostconditions(success, returnData, params);
    }

    /// @notice Verifies non-admin callers cannot use the immediate account-registration path.
    /// @param walletSeed Seed used to select an unregistered wallet from fuzzWallets.
    /// @param entitySeed Seed used to select a currently enabled entity.
    /// @param roleFlagsSeed Seed used as the attempted role flags.
    function handler_registerAccountUnauthorized(uint256 walletSeed, uint256 entitySeed, uint256 roleFlagsSeed) public {
        AdminRegisterAccountParams memory params =
            adminRegisterAccountPreconditions(walletSeed, entitySeed, roleFlagsSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(
                entityRegistry.registerAccount.selector, params.wallet, params.entityId, params.roleFlags
            ),
            FUZZ_ESCROW_UNAUTH_CALLER
        );

        registerAccountUnauthorizedPostconditions(success, returnData);
    }

    /// @notice Covers the immediate-registration input and account-state revert branches.
    /// @param walletSeed Seed used to select an unregistered wallet from fuzzWallets.
    /// @param entitySeed Seed used to select a currently enabled entity.
    /// @param typeIdSeed Seed used when creating a temporary disabled entity.
    /// @param roleFlagsSeed Seed used as the attempted role flags.
    function handler_registerAccountInvalidInputs(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 typeIdSeed,
        uint256 roleFlagsSeed
    ) public {
        address wallet = _freeFuzzWalletOrRevert(walletSeed);
        bytes32 enabledEntityId = _enabledEntityOrRevert(entitySeed);

        _expectRegisterAccountRevert(address(0), enabledEntityId, roleFlagsSeed, Errors.ZeroAddress.selector, ER_113);
        _expectRegisterAccountRevert(wallet, bytes32(0), roleFlagsSeed, Errors.ER__EntityIdZero.selector, ER_114);
        _expectRegisterAccountRevert(
            wallet, _missingEntityId(entitySeed), roleFlagsSeed, Errors.ER__EntityNotRegistered.selector, ER_114
        );

        RegisterEntityParams memory disabledParams = registerEntityPreconditions(typeIdSeed);
        if (!_registerSwapAndPopEntity(
                disabledParams, "ER-ADMIN-REGISTER-INVALID: disabled entity setup registration reverted"
            )) {
            return;
        }
        _trackFuzzEntityId(disabledParams.entityId);
        entityRegistry.setEntityStatus(disabledParams.entityId, EntityStatus.DISABLED, bytes(""));
        _expectRegisterAccountRevert(
            wallet, disabledParams.entityId, roleFlagsSeed, Errors.ER__EntityNotEnabled.selector, ER_114
        );

        _restoreEnabledAccount(USER1);
        _expectRegisterAccountRevert(
            USER1, enabledEntityId, roleFlagsSeed, Errors.ER__AccountAlreadyRegistered.selector, ER_115
        );
    }

    /// @notice Covers request/accept validation branches for pending account registration.
    /// @param walletSeed Seed used to select an unregistered wallet from fuzzWallets.
    /// @param entitySeed Seed used to select a currently enabled entity.
    /// @param typeIdSeed Seed used when creating a temporary disabled entity.
    /// @param managerSeed Seed used to select the requester manager.
    /// @param roleFlagsSeed Seed used as the requested role flags.
    function handler_pendingAccountRegistrationInvalidInputs(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 typeIdSeed,
        uint256 managerSeed,
        uint256 roleFlagsSeed
    ) public {
        address wallet = _freeFuzzWalletOrRevert(walletSeed);
        bytes32 enabledEntityId = _enabledEntityOrRevert(entitySeed);
        address requester = managers[managerSeed % managers.length];
        _ensureEntityManager(enabledEntityId, requester, true);

        _expectRequestAccountRegistrationRevert(
            address(0), enabledEntityId, roleFlagsSeed, requester, Errors.ZeroAddress.selector, ER_97
        );
        _expectRequestAccountRegistrationRevert(
            wallet, bytes32(0), roleFlagsSeed, requester, Errors.ER__EntityIdZero.selector, ER_98
        );
        _expectRequestAccountRegistrationRevert(
            wallet,
            _missingEntityId(entitySeed),
            roleFlagsSeed,
            requester,
            Errors.ER__EntityNotRegistered.selector,
            ER_98
        );

        RegisterEntityParams memory disabledParams = registerEntityPreconditions(typeIdSeed);
        if (!_registerSwapAndPopEntity(
                disabledParams, "ER-PENDING-INVALID: disabled entity setup registration reverted"
            )) {
            return;
        }
        _trackFuzzEntityId(disabledParams.entityId);
        _ensureEntityManager(disabledParams.entityId, requester, true);
        entityRegistry.setEntityStatus(disabledParams.entityId, EntityStatus.DISABLED, bytes(""));
        _expectRequestAccountRegistrationRevert(
            wallet, disabledParams.entityId, roleFlagsSeed, requester, Errors.ER__EntityNotEnabled.selector, ER_98
        );

        _restoreEnabledAccount(USER1);
        _expectRequestAccountRegistrationRevert(
            USER1, enabledEntityId, roleFlagsSeed, requester, Errors.ER__AccountAlreadyRegistered.selector, ER_99
        );

        // ER-103 asserts acceptAccountRegistration reverts when no request is pending for
        // (wallet, enabledEntityId). A sibling handler (e.g. requestAccountRegistrationOverwrite) can
        // leave a dangling pending request for this same free wallet + enabled entity, which would make
        // the accept legitimately succeed. Skip the negative check when a real pending request exists.
        if (entityRegistry.getPendingAccountRegistration(wallet, enabledEntityId).requester != address(0)) {
            return;
        }

        (bool acceptSuccess, bytes memory acceptReturnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.acceptAccountRegistration.selector, enabledEntityId),
            wallet
        );
        acceptRegistrationMissingPendingPostconditions(acceptSuccess, acceptReturnData);
    }

    /// @notice Verifies accepting a pending request reverts once the account has been registered elsewhere.
    /// @param walletSeed Seed used to select an unregistered wallet from fuzzWallets.
    /// @param entitySeed Seed used to select the pending request entity.
    /// @param otherEntitySeed Seed used to select the immediate registration entity.
    /// @param managerSeed Seed used to select the requester manager.
    /// @param roleFlagsSeed Seed used as the requested role flags.
    function handler_acceptAccountRegistrationAlreadyRegistered(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 otherEntitySeed,
        uint256 managerSeed,
        uint256 roleFlagsSeed
    ) public {
        address wallet = _freeFuzzWalletOrRevert(walletSeed);
        bytes32 pendingEntityId = _enabledEntityOrRevert(entitySeed);
        bytes32 registeredEntityId = _enabledEntityDifferentFromOrRevert(otherEntitySeed, pendingEntityId);
        address requester = managers[managerSeed % managers.length];
        _ensureEntityManager(pendingEntityId, requester, true);

        if (!_requestPendingRegistration(
                wallet, pendingEntityId, roleFlagsSeed, requester, "ER-PENDING-REGISTERED: request reverted"
            )) {
            return;
        }
        _trackPendingRegistration(wallet, pendingEntityId);

        if (!_registerSwapAndPopAccount(
                wallet, registeredEntityId, "ER-PENDING-REGISTERED: admin registration reverted"
            )) {
            return;
        }
        _setFuzzAccountRegistered(wallet, true);

        (bool acceptSuccess, bytes memory acceptReturnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.acceptAccountRegistration.selector, pendingEntityId),
            wallet
        );

        acceptRegistrationAlreadyRegisteredPostconditions(acceptSuccess, acceptReturnData);
    }

    /// @notice Verifies revoking a requester manager before acceptance blocks the pending request.
    /// @param walletSeed Seed used to select an unregistered wallet from fuzzWallets.
    /// @param entitySeed Seed used to select the pending request entity.
    /// @param managerSeed Seed used to select the requester manager.
    /// @param roleFlagsSeed Seed used as the requested role flags.
    function handler_requesterRevocationBeforeAcceptance(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 managerSeed,
        uint256 roleFlagsSeed
    ) public {
        address wallet = _freeFuzzWalletOrRevert(walletSeed);
        bytes32 entityId = _enabledEntityOrRevert(entitySeed);
        address requester = managers[managerSeed % managers.length];
        _ensureEntityManager(entityId, requester, true);

        if (!_requestPendingRegistration(
                wallet, entityId, roleFlagsSeed, requester, "ER-PENDING-REVOKE: request reverted"
            )) {
            return;
        }
        _trackPendingRegistration(wallet, entityId);

        _ensureEntityManager(entityId, requester, false);

        (bool acceptSuccess, bytes memory acceptReturnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.acceptAccountRegistration.selector, entityId),
            wallet
        );

        requesterRevocationBeforeAcceptancePostconditions(
            acceptSuccess, acceptReturnData, wallet, entityId, roleFlagsSeed, requester
        );
    }

    /// @notice Exercises a pending request that survives direct registration and removal of the same account.
    /// @param walletSeed Seed used to select an unregistered wallet from fuzzWallets.
    /// @param entitySeed Seed used to select the original pending request entity.
    /// @param otherEntitySeed Seed used to select the temporary direct-registration entity.
    /// @param managerSeed Seed used to select the requester manager.
    /// @param roleFlagsSeed Seed used as the requested role flags.
    function handler_stalePendingRegistrationAfterRemoval(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 otherEntitySeed,
        uint256 managerSeed,
        uint256 roleFlagsSeed
    ) public {
        address wallet = _freeFuzzWalletOrRevert(walletSeed);
        bytes32 pendingEntityId = _enabledEntityOrRevert(entitySeed);
        bytes32 temporaryEntityId = _enabledEntityDifferentFromOrRevert(otherEntitySeed, pendingEntityId);
        address requester = managers[managerSeed % managers.length];
        _ensureEntityManager(pendingEntityId, requester, true);

        if (!_requestPendingRegistration(
                wallet, pendingEntityId, roleFlagsSeed, requester, "ER-PENDING-STALE: request reverted"
            )) {
            return;
        }
        _trackPendingRegistration(wallet, pendingEntityId);

        if (!_registerSwapAndPopAccount(wallet, temporaryEntityId, "ER-PENDING-STALE: temp register reverted")) {
            return;
        }
        _setFuzzAccountRegistered(wallet, true);

        if (!_removeSwapAndPopAccount(wallet)) {
            return;
        }
        _setFuzzAccountRegistered(wallet, false);
        stalePendingRegistrationPostconditions(wallet, pendingEntityId, roleFlagsSeed, requester);

        bytes32[] memory entityIds = _singleBytes32Array(pendingEntityId);
        address[] memory accounts = _singleActorArray(wallet);
        _beforeER(entityIds, accounts);

        (bool acceptSuccess, bytes memory acceptReturnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.acceptAccountRegistration.selector, pendingEntityId),
            wallet
        );

        AcceptAccountRegistrationParams memory params = AcceptAccountRegistrationParams({
            wallet: wallet,
            entityId: pendingEntityId,
            requester: requester,
            roleFlags: roleFlagsSeed,
            accountRegistered: false,
            entityEnabled: true,
            requesterAuthorized: true
        });
        acceptAccountRegistrationPostconditions(acceptSuccess, acceptReturnData, params);
    }

    /// @notice Changes the account status of a registered fuzz wallet.
    /// @dev Requires the wallet's entity to currently be enabled, matching the protocol's own
    ///      precondition for setAccountStatus.
    /// @param walletSeed Seed used to select a registered fuzz wallet.
    /// @param enable True to enable the account, false to disable it.
    function handler_setAccountStatus(uint256 walletSeed, bool enable) public {
        SetAccountStatusParams memory params = setAccountStatusPreconditions(walletSeed, enable);

        address[] memory accounts = _singleActorArray(params.wallet);
        _beforeER(_emptyBytes32Array(), accounts);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.setAccountStatus.selector, params.wallet, params.status, bytes(""))
        );

        setAccountStatusPostconditions(success, returnData, params);
    }

    /// @notice Removes a registered fuzz wallet from the EntityRegistry entirely.
    /// @dev On success the wallet is marked as free again so handler_registerAccount can reuse it.
    ///      This exercises the full wallet-linking lifecycle: register → remove → register again.
    /// @param walletSeed Seed used to select a registered fuzz wallet.
    function handler_removeAccount(uint256 walletSeed) public {
        RemoveAccountParams memory params = removeAccountPreconditions(walletSeed);

        bytes32[] memory entityIds = _singleBytes32Array(params.entityId);
        address[] memory accounts = _singleActorArray(params.wallet);
        _beforeER(entityIds, accounts);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.removeAccount.selector, params.wallet, bytes(""))
        );

        if (success) {
            _setFuzzAccountRegistered(params.wallet, false);
        }

        removeAccountPostconditions(success, returnData, params);
    }

    /// @notice Transfers a registered fuzz wallet to a different enabled entity.
    /// @dev Both source and destination entities must be enabled. The wallet tracking flag is not
    ///      changed because the wallet remains registered after the transfer.
    /// @param walletSeed Seed used to select a registered fuzz wallet.
    /// @param entitySeed Seed used to select an enabled destination entity different from the
    ///        wallet's current entity.
    function handler_transferAccountToEntity(uint256 walletSeed, uint256 entitySeed) public {
        TransferAccountParams memory params = transferAccountPreconditions(walletSeed, entitySeed);

        bytes32[] memory entityIds = _twoBytes32Array(params.oldEntityId, params.newEntityId);
        address[] memory accounts = _singleActorArray(params.wallet);
        _beforeER(entityIds, accounts);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.transferAccountToEntity.selector, params.wallet, params.newEntityId)
        );

        transferAccountPostconditions(success, returnData, params);
    }

    /// @notice Adds or removes a manager for a tracked entity.
    /// @dev Manager addresses are drawn from the dedicated managers set. The selected manager is
    ///      the subject of the mutation, not the caller. The call executes through the harness,
    ///      and address(this) holds ADMIN_ROLE, which overrides the entity-authority check.
    /// @param entitySeed Seed used to select a tracked entity.
    /// @param managerSeed Seed used to select a manager address from managers.
    /// @param enabled True to add the manager, false to remove it.
    function handler_setEntityManager(uint256 entitySeed, uint256 managerSeed, bool enabled) public {
        SetEntityManagerParams memory params = setEntityManagerPreconditions(entitySeed, managerSeed, enabled);

        _beforeER(_emptyBytes32Array(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(
                entityRegistry.setEntityManager.selector, params.entityId, params.manager, params.enabled
            )
        );

        setEntityManagerPostconditions(success, returnData, params);
    }

    /// @notice Registers a new entity through the authority/managers overload.
    /// @param typeIdSeed Seed used to select one of the supported entity types.
    /// @param authoritySeed Seed used to select the authority and manager set.
    function handler_registerEntityWithAccess(uint256 typeIdSeed, uint256 authoritySeed) public {
        RegisterEntityParams memory params = registerEntityPreconditions(typeIdSeed);

        address authority = _pickAuthorityDifferentFrom(address(0), address(0), authoritySeed);
        address[] memory managers = new address[](2);
        managers[0] = _pickAuthorityDifferentFrom(authority, address(0), _deriveSeed(authoritySeed, "mgr-0"));
        managers[1] = _pickAuthorityDifferentFrom(authority, managers[0], _deriveSeed(authoritySeed, "mgr-1"));

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(
                _REGISTER_ENTITY_WITH_ACCESS_SELECTOR,
                params.entityId,
                params.typeId,
                EMPTY_METADATA_REF,
                authority,
                managers
            )
        );

        if (success) {
            _trackFuzzEntityId(params.entityId);
        }
        registerEntityWithAccessPostconditions(success, returnData, params, authority, managers[0], managers[1]);
        if (success) {
            _syncEntity(params.entityId);
            _syncFuzzEntity(params.entityId);
        }
    }

    /// @notice Registers two entities via the batch overload.
    /// @param typeIdSeed Seed used to derive both batch type identifiers.
    function handler_registerEntityBatch(uint256 typeIdSeed) public {
        RegisterEntityParams memory paramsA = registerEntityPreconditions(typeIdSeed);
        RegisterEntityParams memory paramsB = registerEntityPreconditions(_deriveSeed(typeIdSeed, "batch-1"));

        bytes32[] memory entityIds = new bytes32[](2);
        entityIds[0] = paramsA.entityId;
        entityIds[1] = paramsB.entityId;

        uint256[] memory typeIds = new uint256[](2);
        typeIds[0] = paramsA.typeId;
        typeIds[1] = paramsB.typeId;

        string[] memory metadataRefs = new string[](2);
        metadataRefs[0] = _metadataRef(typeIdSeed);
        metadataRefs[1] = _metadataRef(_deriveSeed(typeIdSeed, "batch-meta-1"));

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.registerEntityBatch.selector, entityIds, typeIds, metadataRefs)
        );

        if (success) {
            _trackFuzzEntityId(paramsA.entityId);
            _trackFuzzEntityId(paramsB.entityId);
        }
        registerEntityBatchPostconditions(success, returnData, paramsA, paramsB, entityIds, metadataRefs);
        if (success) {
            _syncEntity(paramsA.entityId);
            _syncEntity(paramsB.entityId);
            _syncFuzzEntity(paramsA.entityId);
            _syncFuzzEntity(paramsB.entityId);
        }
    }

    /// @notice Updates entity metadata through the onboarding surface.
    /// @param entitySeed Seed used to select an enabled entity.
    /// @param metadataSeed Seed used to select one of the fuzz metadata refs.
    function handler_setEntityMetadata(uint256 entitySeed, uint256 metadataSeed) public {
        bytes32 entityId = _enabledEntityOrRevert(entitySeed);
        string memory metadataRef = _metadataRef(metadataSeed);

        _beforeER(_singleBytes32Array(entityId), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.setEntityMetadata.selector, entityId, metadataRef)
        );

        setEntityMetadataPostconditions(success, returnData, entityId, metadataRef);
    }

    /// @notice Rotates entity authority through both the admin and authority paths.
    /// @param entitySeed Seed used to select a tracked entity.
    /// @param authoritySeed Seed used to derive the authority rotation path.
    function handler_setEntityAuthority(uint256 entitySeed, uint256 authoritySeed) public {
        (bool found, bytes32 entityId) = _pickEntityFromBucket(EntityBucket.Existing, entitySeed);
        require(found, ClampFail("no entity for authority"));

        address currentAuthority = entityRegistry.getEntityAuthority(entityId);
        address firstAuthority = _pickAuthorityDifferentFrom(currentAuthority, address(0), authoritySeed);
        address secondAuthority =
            _pickAuthorityDifferentFrom(firstAuthority, currentAuthority, _deriveSeed(authoritySeed, "rotate"));

        (bool adminSuccess, bytes memory adminReturnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.setEntityAuthority.selector, entityId, firstAuthority)
        );

        if (!adminSuccess) {
            entityRegistryUnexpectedRevertPostconditions(
                adminSuccess, adminReturnData, "ER-AUTHORITY: admin authority update unexpectedly reverted"
            );
            return;
        }

        (bool authoritySuccess, bytes memory authorityReturnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.setEntityAuthority.selector, entityId, secondAuthority),
            firstAuthority
        );

        setEntityAuthorityPostconditions(authoritySuccess, authorityReturnData, entityId, secondAuthority);
    }

    /// @notice Updates account role flags on a known-good core account.
    /// @param roleFlagsSeed Seed used to derive the stored role bitmap.
    function handler_setAccountRoleFlags(uint256 roleFlagsSeed) public {
        bytes32 entityId = entityRegistry.getEntityId(USER1);
        _restoreEnabledAccount(USER1);

        uint256 roleFlags = roleFlagsSeed;
        address[] memory accounts = _singleActorArray(USER1);
        _beforeER(_singleBytes32Array(entityId), accounts);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.setAccountRoleFlags.selector, USER1, roleFlags)
        );

        setAccountRoleFlagsPostconditions(success, returnData, entityId, USER1, roleFlags);
    }

    /// @notice Exercises the getter, validation, and revert-check surface on the live registry.
    function handler_entityRegistryViewSurface() public {
        _restoreEnabledAccount(USER1);
        _restoreEnabledAccount(address(this));

        bytes32 entityId = entityRegistry.getEntityId(USER1);
        uint256 entityTypeId = entityRegistry.getEntityTypeId(entityId);

        entityRegistry.getEntity(entityId);
        entityRegistry.getEntityStatus(entityId);
        entityRegistry.getEntityMetadataRef(entityId);
        entityRegistry.getAccount(USER1);
        entityRegistry.getEntityAccounts(entityId);
        entityRegistry.getEntityId(USER1);
        entityRegistry.getEntityAuthority(entityId);
        entityRegistry.isEntityManager(entityId, MANAGER1);
        entityRegistry.getEntityTypeMeta(entityTypeId);
        entityRegistry.getEntityTypeId(entityId);
        entityRegistry.getEntityTypeIdByAccount(USER1);
        entityRegistryViewSurfaceInitialPostconditions(USER1, FUZZ_ESCROW_UNAUTH_CALLER);

        entityRegistry.setAccountStatus(USER1, AccountStatus.DISABLED, bytes(""));
        entityRegistryDisabledAccountPostconditions(USER1);
        entityRegistry.setAccountStatus(USER1, AccountStatus.ENABLED, bytes(""));

        entityRegistry.setEntityStatus(entityId, EntityStatus.DISABLED, bytes(""));
        entityRegistryDisabledEntityPostconditions(USER1);
        entityRegistry.setEntityStatus(entityId, EntityStatus.ENABLED, bytes(""));

        (bool zeroEntitySuccess, bytes memory zeroEntityReturnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.getEntity.selector, bytes32(0)),
            address(this)
        );
        entityRegistryExpectedRevertPostconditions(
            zeroEntitySuccess, zeroEntityReturnData, Errors.ER__EntityIdZero.selector, "ER-VIEW: zero entity guarded"
        );

        bytes32 missingEntity = keccak256("entity-registry-view-missing");
        (bool missingEntitySuccess, bytes memory missingEntityReturnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.getEntity.selector, missingEntity),
            address(this)
        );
        entityRegistryExpectedRevertPostconditions(
            missingEntitySuccess,
            missingEntityReturnData,
            Errors.ER__EntityNotRegistered.selector,
            "ER-VIEW: missing entity guarded"
        );

        (bool missingAccountSuccess, bytes memory missingAccountReturnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.getAccount.selector, FUZZ_ESCROW_UNAUTH_CALLER),
            address(this)
        );
        entityRegistryExpectedRevertPostconditions(
            missingAccountSuccess,
            missingAccountReturnData,
            Errors.ER__AccountNotRegistered.selector,
            "ER-VIEW: missing account guarded"
        );

        uint256 missingTypeId = _freshEntityTypeId();
        (bool missingTypeSuccess, bytes memory missingTypeReturnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.getEntityTypeMeta.selector, missingTypeId),
            address(this)
        );
        entityRegistryExpectedRevertPostconditions(
            missingTypeSuccess,
            missingTypeReturnData,
            Errors.ER__EntityTypeNotRegistered.selector,
            "ER-VIEW: missing entity type guarded"
        );

        entityRegistryViewSurfacePostconditions(entityId, USER1);
    }

    /// @notice Exercises entity-type definition, zero-name rejection, freeze, and frozen-update rejection.
    /// @param capsSeed Seed used to derive the stored capability bitmap.
    function handler_entityTypeSurface(uint256 capsSeed) public {
        uint256 typeId = _freshEntityTypeId();
        bytes32 name = bytes32(uint256(keccak256(abi.encodePacked(typeId, "entity-type-name"))) | 1);

        _expectEntityTypeNameZero(typeId, capsSeed);

        (bool defineSuccess, bytes memory defineReturnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.defineEntityType.selector, typeId, name, capsSeed)
        );

        if (!defineSuccess) {
            entityRegistryUnexpectedRevertPostconditions(
                defineSuccess, defineReturnData, "ER-TYPE: defineEntityType unexpectedly reverted"
            );
            return;
        }

        entityTypeDefinedPostconditions(typeId, name, capsSeed);

        (bool freezeSuccess, bytes memory freezeReturnData) = fl.doFunctionCall(
            address(entityRegistry), abi.encodeWithSelector(entityRegistry.freezeEntityType.selector, typeId)
        );

        if (!freezeSuccess) {
            entityRegistryUnexpectedRevertPostconditions(
                freezeSuccess, freezeReturnData, "ER-TYPE: freezeEntityType unexpectedly reverted"
            );
            return;
        }

        entityTypeFrozenPostconditions(typeId);

        _expectFrozenEntityTypeUpdateReverts(typeId, name, capsSeed);
    }

    /// @notice Exercises both grantRoles overloads plus invalid-role rejections.
    /// @param roleSeed Seed used to select a valid role bit for success-path grants.
    function handler_entityRegistryAdminSurface(uint256 roleSeed) public {
        uint256 role = _pickEntityRegistryRole(roleSeed);
        address[] memory grantees = new address[](2);
        grantees[0] = FUZZ_WALLET_4;
        grantees[1] = FUZZ_WALLET_5;

        (bool singleSuccess, bytes memory singleReturnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSignature("grantRoles(address,uint256)", FUZZ_WALLET_6, role),
            address(this)
        );

        if (!singleSuccess) {
            entityRegistryUnexpectedRevertPostconditions(
                singleSuccess, singleReturnData, "ER-ADMIN: single grantRoles unexpectedly reverted"
            );
            return;
        }

        (bool batchSuccess, bytes memory batchReturnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSignature("grantRoles(address[],uint256)", grantees, role),
            address(this)
        );

        if (batchSuccess) {
            entityRegistryAdminGrantPostconditions(FUZZ_WALLET_6, grantees, role);
        } else {
            entityRegistryUnexpectedRevertPostconditions(
                batchSuccess, batchReturnData, "ER-ADMIN: batch grantRoles unexpectedly reverted"
            );
            return;
        }

        uint256 invalidRoles = entityRegistry.ALL_ROLES() << 1;

        (bool invalidSingleSuccess, bytes memory invalidSingleReturnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSignature("grantRoles(address,uint256)", FUZZ_WALLET_7, invalidRoles),
            address(this)
        );
        entityRegistryExpectedRevertPostconditions(
            invalidSingleSuccess,
            invalidSingleReturnData,
            Errors.InvalidRoles.selector,
            "ER-ADMIN: single invalid role rejected"
        );

        (bool invalidBatchSuccess, bytes memory invalidBatchReturnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSignature("grantRoles(address[],uint256)", grantees, invalidRoles),
            address(this)
        );
        entityRegistryExpectedRevertPostconditions(
            invalidBatchSuccess,
            invalidBatchReturnData,
            Errors.InvalidRoles.selector,
            "ER-ADMIN: batch invalid role rejected"
        );
    }

    /// @notice Attempts to initialize the live proxy again.
    function handler_entityRegistryInitializeAgain() public {
        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.initialize.selector, address(this)),
            address(this)
        );

        entityRegistryExpectedRevertPostconditions(
            success, returnData, _INVALID_INITIALIZATION_SELECTOR, "ER-INIT: reinitializing proxy reverts"
        );
    }

    /// @notice Deploys a fresh implementation and verifies the initializer lock.
    function handler_entityRegistryFreshDeployment() public {
        EntityRegistry fresh = new EntityRegistry();

        entityRegistryFreshDeploymentPostconditions(fresh);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(fresh), abi.encodeWithSelector(fresh.initialize.selector, address(this)), address(this)
        );
        entityRegistryExpectedRevertPostconditions(
            success, returnData, _INVALID_INITIALIZATION_SELECTOR, "ER-FRESH: implementation initializer locked"
        );
    }

    /// @notice Forces the account-array swap-and-pop path and then removes the remaining account.
    /// @param typeIdSeed Seed used to select entity types for the temporary source and target entities.
    /// @param firstWalletSeed Seed used to select the first free fuzz wallet.
    /// @param secondWalletSeed Seed used to select a distinct second free fuzz wallet.
    // solhint-disable-next-line function-max-lines
    function handler_entityAccountSwapAndPopSurface(
        uint256 typeIdSeed,
        uint256 firstWalletSeed,
        uint256 secondWalletSeed
    ) public {
        // Create two temporary fuzz entities so account transfer has a distinct target.
        RegisterEntityParams memory sourceParams = registerEntityPreconditions(typeIdSeed);
        RegisterEntityParams memory targetParams = registerEntityPreconditions(_deriveSeed(typeIdSeed, "target"));

        address walletA = _freeFuzzWalletOrRevert(firstWalletSeed);
        address walletB = _freeFuzzWalletDifferentFromOrRevert(secondWalletSeed, walletA);

        // Register both entities directly; any revert means the harness setup path is inconsistent.
        if (!_registerSwapAndPopEntity(sourceParams, "ER-SWAPPOP: source entity registration unexpectedly reverted")) {
            // The helper already records the unexpected revert; stop before using a missing source entity.
            return;
        }

        if (!_registerSwapAndPopEntity(targetParams, "ER-SWAPPOP: target entity registration unexpectedly reverted")) {
            // The helper already records the unexpected revert; stop before transferring into a missing target.
            return;
        }

        _trackFuzzEntityId(sourceParams.entityId);
        _trackFuzzEntityId(targetParams.entityId);

        // Put two distinct accounts into the source entity so removal exercises swap-and-pop.
        if (!_registerSwapAndPopAccount(
                walletA, sourceParams.entityId, "ER-SWAPPOP: first account registration unexpectedly reverted"
            )) {
            // Stop before the scenario assumes the first source account exists.
            return;
        }

        if (!_registerSwapAndPopAccount(
                walletB, sourceParams.entityId, "ER-SWAPPOP: second account registration unexpectedly reverted"
            )) {
            // Stop before exercising swap-and-pop without the second source account.
            return;
        }

        _setFuzzAccountRegistered(walletA, true);
        _setFuzzAccountRegistered(walletB, true);

        // Snapshot the affected entities and accounts before transfer/remove mutate registry state.
        bytes32[] memory entityIds = _twoBytes32Array(sourceParams.entityId, targetParams.entityId);
        address[] memory accounts = _twoActorArray(walletA, walletB);
        _beforeER(entityIds, accounts);

        // Move one account away before removing the other to cover the source account-list edge case.
        if (!_transferSwapAndPopAccount(walletA, targetParams.entityId)) {
            // Stop because the post-transfer invariants require walletA to be in the target entity.
            return;
        }

        // Remove the remaining source account, then check registry array bookkeeping invariants.
        if (_removeSwapAndPopAccount(walletB)) {
            _setFuzzAccountRegistered(walletB, false);
            entityAccountSwapAndPopPostconditions(sourceParams.entityId, targetParams.entityId, walletA, walletB);
        } else {
            // Stop because the helper already recorded the failure and the after-snapshot would be invalid.
            return;
        }

        // Refresh harness mirrors so later handlers select from current registry state.
        _syncEntity(sourceParams.entityId);
        _syncEntity(targetParams.entityId);
        _syncFuzzEntity(sourceParams.entityId);
        _syncFuzzEntity(targetParams.entityId);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _requestPendingRegistration(
        address wallet,
        bytes32 entityId,
        uint256 roleFlags,
        address requester,
        string memory failureLabel
    ) private returns (bool success) {
        bytes memory returnData;
        (success, returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.requestAccountRegistration.selector, wallet, entityId, roleFlags),
            requester
        );

        if (!success) {
            entityRegistryUnexpectedRevertPostconditions(success, returnData, failureLabel);
        }
    }

    function _expectRegisterAccountRevert(
        address wallet,
        bytes32 entityId,
        uint256 roleFlags,
        bytes4 expectedSelector,
        string memory invariantLabel
    ) private {
        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.registerAccount.selector, wallet, entityId, roleFlags),
            address(this)
        );

        registerAccountInvalidInputPostconditions(success, returnData, expectedSelector, invariantLabel);
    }

    function _expectRequestAccountRegistrationRevert(
        address wallet,
        bytes32 entityId,
        uint256 roleFlags,
        address requester,
        bytes4 expectedSelector,
        string memory invariantLabel
    ) private {
        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.requestAccountRegistration.selector, wallet, entityId, roleFlags),
            requester
        );

        requestAccountRegistrationInvalidInputPostconditions(success, returnData, expectedSelector, invariantLabel);
    }

    function _expectEntityTypeNameZero(uint256 typeId, uint256 caps) private {
        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.defineEntityType.selector, typeId, bytes32(0), caps)
        );
        entityRegistryExpectedRevertPostconditions(
            success, returnData, Errors.ER__EntityTypeNameZero.selector, "ER-TYPE: zero-name type rejected"
        );
    }

    function _expectFrozenEntityTypeUpdateReverts(uint256 typeId, bytes32 name, uint256 capsSeed) private {
        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(
                entityRegistry.defineEntityType.selector, typeId, name, _deriveSeed(capsSeed, "frozen-update")
            )
        );
        entityRegistryExpectedRevertPostconditions(
            success, returnData, Errors.ER__EntityTypeFrozen.selector, "ER-TYPE: frozen type locked"
        );
    }

    function _registerSwapAndPopEntity(RegisterEntityParams memory params, string memory failureLabel)
        private
        returns (bool success)
    {
        bytes memory returnData;
        (success, returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(_REGISTER_ENTITY_SELECTOR, params.entityId, params.typeId, EMPTY_METADATA_REF)
        );

        if (!success) {
            entityRegistryUnexpectedRevertPostconditions(success, returnData, failureLabel);
        }
    }

    function _registerSwapAndPopAccount(address wallet, bytes32 entityId, string memory failureLabel)
        private
        returns (bool success)
    {
        bytes memory returnData;
        (success, returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.registerAccount.selector, wallet, entityId, ROLE_FLAGS_EMPTY),
            address(this)
        );

        if (!success) {
            entityRegistryUnexpectedRevertPostconditions(success, returnData, failureLabel);
        }
    }

    function _transferSwapAndPopAccount(address wallet, bytes32 targetEntityId) private returns (bool success) {
        bytes memory returnData;
        (success, returnData) = fl.doFunctionCall(
            address(entityRegistry),
            abi.encodeWithSelector(entityRegistry.transferAccountToEntity.selector, wallet, targetEntityId)
        );

        if (!success) {
            entityRegistryUnexpectedRevertPostconditions(
                success, returnData, "ER-SWAPPOP: transfer unexpectedly reverted"
            );
        }
    }

    function _removeSwapAndPopAccount(address wallet) private returns (bool success) {
        bytes memory returnData;
        (success, returnData) = fl.doFunctionCall(
            address(entityRegistry), abi.encodeWithSelector(entityRegistry.removeAccount.selector, wallet, bytes(""))
        );

        if (!success) {
            entityRegistryUnexpectedRevertPostconditions(
                success, returnData, "ER-SWAPPOP: removeAccount unexpectedly reverted"
            );
        }
    }

    function _metadataRef(uint256 seed) private pure returns (string memory) {
        if (seed % 3 == 0) return EMPTY_METADATA_REF;
        if (seed % 3 == 1) return "ipfs://entity-a";
        return "ipfs://entity-b";
    }

    function _pickAuthorityDifferentFrom(address excludeA, address excludeB, uint256 seed)
        private
        pure
        returns (address authority)
    {
        address[3] memory pool = [MANAGER1, MANAGER2, MANAGER3];
        uint256 start = seed % pool.length;
        for (uint256 i; i < pool.length; ++i) {
            address candidate = pool[(start + i) % pool.length];
            if (candidate != excludeA && candidate != excludeB) {
                return candidate;
            }
        }
        return MANAGER1;
    }

    function _pickEntityRegistryRole(uint256 roleSeed) private view returns (uint256 role) {
        uint256 idx = roleSeed % 5;
        if (idx == 0) return entityRegistry.ADMIN_ROLE();
        if (idx == 1) return entityRegistry.GUARD();
        if (idx == 2) return entityRegistry.ONBOARDING();
        if (idx == 3) return entityRegistry.WALLET_TRANSFER();
        return entityRegistry.ENTITY_TYPE_MANAGER();
    }

    function _freshEntityTypeId() private returns (uint256 typeId) {
        typeId = uint256(keccak256(abi.encodePacked(address(this), entityNonce, "entity-type")));
        if (typeId == 0) typeId = 1;
        ++entityNonce;
    }

    function _deriveSeed(uint256 seed, string memory salt) private pure returns (uint256 derivedSeed) {
        return uint256(keccak256(abi.encode(seed, salt)));
    }

    function _restoreEnabledAccount(address account) private {
        bytes32 entityId = entityRegistry.getEntityId(account);

        if (entityRegistry.getEntityStatus(entityId) != EntityStatus.ENABLED) {
            entityRegistry.setEntityStatus(entityId, EntityStatus.ENABLED, bytes(""));
        }
        if (!entityRegistry.isAccountEnabled(account)) {
            entityRegistry.setAccountStatus(account, AccountStatus.ENABLED, bytes(""));
        }
    }
}
