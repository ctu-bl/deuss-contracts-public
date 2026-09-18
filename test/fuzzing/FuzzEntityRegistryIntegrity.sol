// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {FuzzIntegrityBase} from "./FuzzIntegrityBase.sol";
import {HandlerEntityRegistry} from "./helper/handlers/HandlerEntityRegistry.sol";

/**
 * @title FuzzEntityRegistryIntegrity
 * @notice Checks handler integrity for the EntityRegistry fuzz harness.
 *
 * Each public `fuzz_*` function encodes the matching `handler_*` selector, delegates
 * into address(this) via `_testSelf`, and allows only `ClampFail` on the failure path.
 * Direct `handler_*` calls by the fuzzer engine are blocked via the engine config blacklist.
 */
contract FuzzEntityRegistryIntegrity is HandlerEntityRegistry, FuzzIntegrityBase {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         INTEGRITY                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Checks the integrity of `handler_registerEntity`
     * @param typeIdSeed Seed used to rotate through the defined entity types
     */
    function fuzz_registerEntity(uint256 typeIdSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEntityRegistry.handler_registerEntity.selector, typeIdSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-REGISTER-ENTITY");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setEntityStatus`
     * @param entitySeed Seed used to select a tracked fuzz entity
     * @param enable True to enable, false to disable
     */
    function fuzz_setEntityStatus(uint256 entitySeed, bool enable) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEntityRegistry.handler_setEntityStatus.selector, entitySeed, enable);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-SET-ENTITY-STATUS");
        }
    }

    /**
     * @notice Checks the integrity of `handler_registerAccount`
     * @param walletSeed Seed used to select a free wallet from fuzzWallets
     * @param entitySeed Seed used to select an enabled entity to link the wallet into
     * @param managerSeed Seed used to select a caller from the managers pool
     */
    function fuzz_registerAccount(uint256 walletSeed, uint256 entitySeed, uint256 managerSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEntityRegistry.handler_registerAccount.selector, walletSeed, entitySeed, managerSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-REGISTER-ACCOUNT");
        }
    }

    /**
     * @notice Checks the integrity of `handler_requestAccountRegistration`
     * @param walletSeed Seed used to select a free wallet from fuzzWallets
     * @param entitySeed Seed used to select an enabled entity to request
     * @param managerSeed Seed used to select a caller from the managers pool
     * @param roleFlagsSeed Seed used as the requested role flags
     */
    function fuzz_requestAccountRegistration(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 managerSeed,
        uint256 roleFlagsSeed
    ) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEntityRegistry.handler_requestAccountRegistration.selector,
            walletSeed,
            entitySeed,
            managerSeed,
            roleFlagsSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-PENDING-REQUEST");
        }
    }

    /**
     * @notice Checks the integrity of `handler_acceptAccountRegistration`
     * @param pendingSeed Seed used to select a tracked pending request
     */
    function fuzz_acceptAccountRegistration(uint256 pendingSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEntityRegistry.handler_acceptAccountRegistration.selector, pendingSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-PENDING-ACCEPT");
        }
    }

    /**
     * @notice Checks the integrity of `handler_requestAccountRegistrationOverwrite`
     * @param walletSeed Seed used to select a free wallet from fuzzWallets
     * @param entitySeed Seed used to select an enabled entity
     * @param managerSeed Seed used to derive requester managers
     * @param roleFlagsSeed Seed used to derive role flags
     */
    function fuzz_requestAccountRegistrationOverwrite(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 managerSeed,
        uint256 roleFlagsSeed
    ) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEntityRegistry.handler_requestAccountRegistrationOverwrite.selector,
            walletSeed,
            entitySeed,
            managerSeed,
            roleFlagsSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-PENDING-OVERWRITE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_requestAccountRegistrationMultipleEntities`
     * @param walletSeed Seed used to select a free wallet from fuzzWallets
     * @param entitySeed Seed used to select the first enabled entity
     * @param otherEntitySeed Seed used to select the second enabled entity
     * @param managerSeed Seed used to select the requester manager
     * @param roleFlagsSeed Seed used to derive role flags
     */
    function fuzz_requestAccountRegistrationMultipleEntities(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 otherEntitySeed,
        uint256 managerSeed,
        uint256 roleFlagsSeed
    ) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEntityRegistry.handler_requestAccountRegistrationMultipleEntities.selector,
            walletSeed,
            entitySeed,
            otherEntitySeed,
            managerSeed,
            roleFlagsSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-PENDING-MULTI");
        }
    }

    /**
     * @notice Checks the integrity of `handler_adminRegisterAccount`
     * @param walletSeed Seed used to select a free wallet from fuzzWallets
     * @param entitySeed Seed used to select an enabled entity
     * @param roleFlagsSeed Seed used as the stored role flags
     */
    function fuzz_adminRegisterAccount(uint256 walletSeed, uint256 entitySeed, uint256 roleFlagsSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEntityRegistry.handler_adminRegisterAccount.selector, walletSeed, entitySeed, roleFlagsSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-ADMIN-REGISTER");
        }
    }

    /**
     * @notice Checks the integrity of `handler_registerAccountUnauthorized`
     * @param walletSeed Seed used to select a free wallet from fuzzWallets
     * @param entitySeed Seed used to select an enabled entity
     * @param roleFlagsSeed Seed used as the attempted role flags
     */
    function fuzz_registerAccountUnauthorized(uint256 walletSeed, uint256 entitySeed, uint256 roleFlagsSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEntityRegistry.handler_registerAccountUnauthorized.selector, walletSeed, entitySeed, roleFlagsSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-ADMIN-REGISTER-UNAUTH");
        }
    }

    /**
     * @notice Checks the integrity of `handler_registerAccountInvalidInputs`
     * @param walletSeed Seed used to select a free wallet from fuzzWallets
     * @param entitySeed Seed used to select an enabled entity
     * @param typeIdSeed Seed used for temporary disabled entity setup
     * @param roleFlagsSeed Seed used as the attempted role flags
     */
    function fuzz_registerAccountInvalidInputs(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 typeIdSeed,
        uint256 roleFlagsSeed
    ) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEntityRegistry.handler_registerAccountInvalidInputs.selector,
            walletSeed,
            entitySeed,
            typeIdSeed,
            roleFlagsSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-ADMIN-REGISTER-INVALID");
        }
    }

    /**
     * @notice Checks the integrity of `handler_pendingAccountRegistrationInvalidInputs`
     * @param walletSeed Seed used to select a free wallet from fuzzWallets
     * @param entitySeed Seed used to select an enabled entity
     * @param typeIdSeed Seed used for temporary disabled entity setup
     * @param managerSeed Seed used to select the requester manager
     * @param roleFlagsSeed Seed used as the requested role flags
     */
    function fuzz_pendingAccountRegistrationInvalidInputs(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 typeIdSeed,
        uint256 managerSeed,
        uint256 roleFlagsSeed
    ) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEntityRegistry.handler_pendingAccountRegistrationInvalidInputs.selector,
            walletSeed,
            entitySeed,
            typeIdSeed,
            managerSeed,
            roleFlagsSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-PENDING-INVALID");
        }
    }

    /**
     * @notice Checks the integrity of `handler_acceptAccountRegistrationAlreadyRegistered`
     * @param walletSeed Seed used to select a free wallet from fuzzWallets
     * @param entitySeed Seed used to select the pending entity
     * @param otherEntitySeed Seed used to select the direct-registration entity
     * @param managerSeed Seed used to select the requester manager
     * @param roleFlagsSeed Seed used as the requested role flags
     */
    function fuzz_acceptAccountRegistrationAlreadyRegistered(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 otherEntitySeed,
        uint256 managerSeed,
        uint256 roleFlagsSeed
    ) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEntityRegistry.handler_acceptAccountRegistrationAlreadyRegistered.selector,
            walletSeed,
            entitySeed,
            otherEntitySeed,
            managerSeed,
            roleFlagsSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-PENDING-ACCOUNT-REGISTERED");
        }
    }

    /**
     * @notice Checks the integrity of `handler_requesterRevocationBeforeAcceptance`
     * @param walletSeed Seed used to select a free wallet from fuzzWallets
     * @param entitySeed Seed used to select the pending entity
     * @param managerSeed Seed used to select the requester manager
     * @param roleFlagsSeed Seed used as the requested role flags
     */
    function fuzz_requesterRevocationBeforeAcceptance(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 managerSeed,
        uint256 roleFlagsSeed
    ) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEntityRegistry.handler_requesterRevocationBeforeAcceptance.selector,
            walletSeed,
            entitySeed,
            managerSeed,
            roleFlagsSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-PENDING-REQUESTER-REVOKED");
        }
    }

    /**
     * @notice Checks the integrity of `handler_stalePendingRegistrationAfterRemoval`
     * @param walletSeed Seed used to select a free wallet from fuzzWallets
     * @param entitySeed Seed used to select the pending entity
     * @param otherEntitySeed Seed used to select the direct-registration entity
     * @param managerSeed Seed used to select the requester manager
     * @param roleFlagsSeed Seed used as the requested role flags
     */
    function fuzz_stalePendingRegistrationAfterRemoval(
        uint256 walletSeed,
        uint256 entitySeed,
        uint256 otherEntitySeed,
        uint256 managerSeed,
        uint256 roleFlagsSeed
    ) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEntityRegistry.handler_stalePendingRegistrationAfterRemoval.selector,
            walletSeed,
            entitySeed,
            otherEntitySeed,
            managerSeed,
            roleFlagsSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-PENDING-STALE-REMOVAL");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setAccountStatus`
     * @param walletSeed Seed used to select a registered fuzz wallet
     * @param enable True to enable the account, false to disable it
     */
    function fuzz_setAccountStatus(uint256 walletSeed, bool enable) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEntityRegistry.handler_setAccountStatus.selector, walletSeed, enable);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-SET-ACCOUNT-STATUS");
        }
    }

    /**
     * @notice Checks the integrity of `handler_removeAccount`
     * @param walletSeed Seed used to select a registered fuzz wallet to remove
     */
    function fuzz_removeAccount(uint256 walletSeed) public {
        bytes memory callData = abi.encodeWithSelector(HandlerEntityRegistry.handler_removeAccount.selector, walletSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-REMOVE-ACCOUNT");
        }
    }

    /**
     * @notice Checks the integrity of `handler_transferAccountToEntity`
     * @param walletSeed Seed used to select a registered fuzz wallet
     * @param entitySeed Seed used to select a destination entity
     */
    function fuzz_transferAccountToEntity(uint256 walletSeed, uint256 entitySeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEntityRegistry.handler_transferAccountToEntity.selector, walletSeed, entitySeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-TRANSFER-ACCOUNT");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setEntityManager`
     * @param entitySeed Seed used to select a tracked entity
     * @param managerSeed Seed used to select a manager address from users
     * @param enabled True to add the manager, false to remove it
     */
    function fuzz_setEntityManager(uint256 entitySeed, uint256 managerSeed, bool enabled) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEntityRegistry.handler_setEntityManager.selector, entitySeed, managerSeed, enabled
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-SET-ENTITY-MANAGER");
        }
    }

    /**
     * @notice Checks the integrity of `handler_registerEntityWithAccess`
     * @param typeIdSeed Seed used to select one of the defined entity types
     * @param authoritySeed Seed used to derive authority and manager addresses
     */
    function fuzz_registerEntityWithAccess(uint256 typeIdSeed, uint256 authoritySeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEntityRegistry.handler_registerEntityWithAccess.selector, typeIdSeed, authoritySeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-REGISTER-ENTITY-ACCESS");
        }
    }

    /**
     * @notice Checks the integrity of `handler_registerEntityBatch`
     * @param typeIdSeed Seed used to derive both entity type selections
     */
    function fuzz_registerEntityBatch(uint256 typeIdSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEntityRegistry.handler_registerEntityBatch.selector, typeIdSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-REGISTER-ENTITY-BATCH");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setEntityMetadata`
     * @param entitySeed Seed used to select an enabled entity
     * @param metadataSeed Seed used to select a fuzz metadata ref
     */
    function fuzz_setEntityMetadata(uint256 entitySeed, uint256 metadataSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEntityRegistry.handler_setEntityMetadata.selector, entitySeed, metadataSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-SET-ENTITY-METADATA");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setEntityAuthority`
     * @param entitySeed Seed used to select a tracked entity
     * @param authoritySeed Seed used to derive the authority rotation path
     */
    function fuzz_setEntityAuthority(uint256 entitySeed, uint256 authoritySeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEntityRegistry.handler_setEntityAuthority.selector, entitySeed, authoritySeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-SET-ENTITY-AUTHORITY");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setAccountRoleFlags`
     * @param roleFlagsSeed Seed used to derive the stored role bitmap
     */
    function fuzz_setAccountRoleFlags(uint256 roleFlagsSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEntityRegistry.handler_setAccountRoleFlags.selector, roleFlagsSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-SET-ACCOUNT-ROLE-FLAGS");
        }
    }

    /**
     * @notice Checks the integrity of `handler_entityRegistryViewSurface`
     */
    function fuzz_entityRegistryViewSurface() public {
        bytes memory callData = abi.encodeWithSelector(HandlerEntityRegistry.handler_entityRegistryViewSurface.selector);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-VIEW-SURFACE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_entityTypeSurface`
     * @param capsSeed Seed used to derive the stored capability bitmap
     */
    function fuzz_entityTypeSurface(uint256 capsSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEntityRegistry.handler_entityTypeSurface.selector, capsSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-TYPE-SURFACE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_entityRegistryAdminSurface`
     * @param roleSeed Seed used to select a valid role for the grant overloads
     */
    function fuzz_entityRegistryAdminSurface(uint256 roleSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEntityRegistry.handler_entityRegistryAdminSurface.selector, roleSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-ADMIN-SURFACE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_entityRegistryInitializeAgain`
     */
    function fuzz_entityRegistryInitializeAgain() public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEntityRegistry.handler_entityRegistryInitializeAgain.selector);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-INITIALIZE-AGAIN");
        }
    }

    /**
     * @notice Checks the integrity of `handler_entityRegistryFreshDeployment`
     */
    function fuzz_entityRegistryFreshDeployment() public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEntityRegistry.handler_entityRegistryFreshDeployment.selector);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-FRESH-DEPLOYMENT");
        }
    }

    /**
     * @notice Checks the integrity of `handler_entityAccountSwapAndPopSurface`
     * @param typeIdSeed Seed used to select entity types for the temporary entities
     * @param firstWalletSeed Seed used to select the first free fuzz wallet
     * @param secondWalletSeed Seed used to select a distinct second free fuzz wallet
     */
    function fuzz_entityAccountSwapAndPopSurface(uint256 typeIdSeed, uint256 firstWalletSeed, uint256 secondWalletSeed)
        public
    {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEntityRegistry.handler_entityAccountSwapAndPopSurface.selector,
            typeIdSeed,
            firstWalletSeed,
            secondWalletSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "ER-SWAPPOP-SURFACE");
        }
    }
}
