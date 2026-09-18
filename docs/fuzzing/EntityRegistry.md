# EntityRegistry Fuzz Coverage

Vertical entrypoint: [`test/fuzzing/FuzzEntityRegistryIntegrity.sol`](../../test/fuzzing/FuzzEntityRegistryIntegrity.sol)
Invariants: [`test/fuzzing/properties/Properties_ER.sol`](../../test/fuzzing/properties/Properties_ER.sol)
Descriptions: [`test/fuzzing/properties/PropertiesDescriptions.sol`](../../test/fuzzing/properties/PropertiesDescriptions.sol)

## Scope

Direct exercise of [`EntityRegistry`](../registry/EntityRegistry.md) entity registration, entity status changes, pending account registration request/acceptance, immediate admin account registration, account status changes, account removal and transfer, entity-manager toggling, authority and metadata updates, account role-flag updates, entity-type lifecycle, getter/validation views, RBAC overloads, and initializer-lock behavior. The harness defines the three supported entity types (`BROKER`, `NATURAL_PERSON`, `DEUSS_PROTOCOL`), pre-registers the core protocol wallets plus the three marketplace users, then drives extra registry state through dedicated fuzz-only pools:

- `FUZZ_WALLETS` (`0x40000`..`0x80000`) are the only wallets this vertical registers, removes, and transfers.
- `MANAGERS` (`0x90000`..`0xB0000`) are the caller/subject pool for manager-sensitive actions.

The harness itself holds all `EntityRegistry` roles, but `requestAccountRegistration` deliberately pranks as a selected manager so the vertical exercises the real `entity manager or admin` authorization path. Pending requests are tracked as bounded `(account, entityId)` pairs, which lets later fuzz steps accept, overwrite, revoke, or stale-check them independently. `setEntityStatus` is restricted to fuzz-created entities, so the setup entities that back `Marketplace`, `EscrowManager`, and the core actors cannot be disabled accidentally.

## Handlers

| Entrypoint | Caller | Target | Purpose |
|---|---|---|---|
| `fuzz_registerEntity` | harness (`address(this)`, `ONBOARDING`) | `entityRegistry.registerEntity(bytes32,uint256,string)` | Create a new enabled entity with one of the defined type IDs |
| `fuzz_setEntityStatus` | harness (`address(this)`, `GUARD`) | `entityRegistry.setEntityStatus` | Enable or disable a fuzz-created entity |
| `fuzz_registerAccount` | selected manager (`MANAGER1..3`) then selected wallet | `entityRegistry.requestAccountRegistration` + `entityRegistry.acceptAccountRegistration` | Exercise the entity-manager authorization path and account-side acceptance for wallet onboarding |
| `fuzz_requestAccountRegistration` | selected manager (`MANAGER1..3`) | `entityRegistry.requestAccountRegistration` | Create pending account-registration requests without accepting them in the same handler |
| `fuzz_acceptAccountRegistration` | selected pending wallet | `entityRegistry.acceptAccountRegistration` | Accept a pending request created by an earlier fuzz step |
| `fuzz_requestAccountRegistrationOverwrite` | two selected managers | `entityRegistry.requestAccountRegistration` twice for one pair | Assert repeated requests for the same `(account, entityId)` overwrite pending requester/role data |
| `fuzz_requestAccountRegistrationMultipleEntities` | selected manager | `entityRegistry.requestAccountRegistration` for two entities | Assert one account can hold independent pending requests for multiple entities |
| `fuzz_pendingAccountRegistrationInvalidInputs` | selected manager / selected wallet | request/accept negative paths | Cover zero account, zero/missing/disabled entity, registered-account, and missing-pending reverts |
| `fuzz_acceptAccountRegistrationAlreadyRegistered` | selected wallet | `entityRegistry.acceptAccountRegistration` | Assert acceptance reverts while the account is already registered elsewhere |
| `fuzz_requesterRevocationBeforeAcceptance` | selected manager then selected wallet | `setEntityManager(false)` + `acceptAccountRegistration` | Assert acceptance reverts if the original requester is no longer manager/admin |
| `fuzz_stalePendingRegistrationAfterRemoval` | selected manager then selected wallet | request, direct register, remove, accept | Cover pending requests that survive direct registration and account removal |
| `fuzz_adminRegisterAccount` | harness (`address(this)`, `ADMIN_ROLE`) | `entityRegistry.registerAccount` | Exercise immediate admin account registration as a distinct path |
| `fuzz_registerAccountUnauthorized` | non-admin fuzz actor | `entityRegistry.registerAccount` | Assert non-admin callers cannot use immediate registration |
| `fuzz_registerAccountInvalidInputs` | harness (`address(this)`, `ADMIN_ROLE`) | `entityRegistry.registerAccount` negative paths | Cover zero account, zero/missing/disabled entity, and already-registered account reverts |
| `fuzz_setAccountStatus` | harness (`address(this)`, `GUARD`) | `entityRegistry.setAccountStatus` | Enable or disable a registered fuzz wallet |
| `fuzz_removeAccount` | harness (`address(this)`, `WALLET_TRANSFER`) | `entityRegistry.removeAccount` | Remove a registered fuzz wallet and free it for reuse |
| `fuzz_transferAccountToEntity` | harness (`address(this)`, `WALLET_TRANSFER`) | `entityRegistry.transferAccountToEntity` | Relink a registered fuzz wallet to a different enabled entity |
| `fuzz_setEntityManager` | harness (`address(this)`, `ADMIN_ROLE`) | `entityRegistry.setEntityManager` | Toggle whether a manager address is enabled for an entity |
| `fuzz_registerEntityWithAccess` | harness (`address(this)`, `ONBOARDING`) | `entityRegistry.registerEntity(bytes32,uint256,string,address,address[])` | Cover the authority/managers overload and assert the configured authority + managers are stored |
| `fuzz_registerEntityBatch` | harness (`address(this)`, `ONBOARDING`) | `entityRegistry.registerEntityBatch` | Register two entities through the batch overload and verify both are persisted |
| `fuzz_setEntityMetadata` | harness (`address(this)`, `ONBOARDING`) | `entityRegistry.setEntityMetadata` | Update an enabled entity's metadata reference |
| `fuzz_setEntityAuthority` | harness (`address(this)` then current authority) | `entityRegistry.setEntityAuthority` | Cover both admin-driven authority assignment and authority-driven rotation |
| `fuzz_setAccountRoleFlags` | harness (`address(this)`, `ONBOARDING`) | `entityRegistry.setAccountRoleFlags` | Update `roleFlags` on a known-good registered account |
| `fuzz_entityRegistryViewSurface` | harness (`address(this)`, `GUARD` / view) | getters + `canTransfer` / `canApprove` | Probe success and expected-revert view paths, zero-address validation branches, and disabled-account / disabled-entity validation branches |
| `fuzz_entityTypeSurface` | harness (`address(this)`, `ENTITY_TYPE_MANAGER`) | `defineEntityType`, `freezeEntityType`, `getEntityTypeMeta` | Assert zero-name type definitions revert, define a fresh entity type, freeze it, and assert frozen updates revert |
| `fuzz_entityRegistryAdminSurface` | harness (`address(this)`, owner) | `grantRoles(address,uint256)` + `grantRoles(address[],uint256)` | Cover both RBAC grant overloads plus invalid-role rejection |
| `fuzz_entityRegistryInitializeAgain` | harness (`address(this)`) | `entityRegistry.initialize` | Assert the live proxy cannot be initialized twice |
| `fuzz_entityRegistryFreshDeployment` | harness (`address(this)`) | `new EntityRegistry()` + locked `initialize` | Cover constructor-time initializer locking on a fresh implementation deployment |
| `fuzz_entityAccountSwapAndPopSurface` | harness (`address(this)`, `ONBOARDING` / `WALLET_TRANSFER`) | register/transfer/remove account lifecycle | Force the swap-and-pop branch in `entity.accounts[]`, then remove the remaining account |

`fuzz_registerAccount` keeps the original combined request-and-accept lifecycle for backwards-compatible coverage. The newer pending-registration handlers split request and acceptance across separate fuzz calls, and targeted handlers pin down overwrite, multi-pending, requester-revocation, already-registered, and stale-after-removal behavior. The immediate `registerAccount` admin path is covered separately under `ER-110` .. `ER-115`.

## Invariants

### `registerEntity` — group 10

Checked in `registerEntityPostconditions` for `fuzz_registerEntity`.

| ID | Condition | Checked |
|---|---|---|
| ER-10 | Registered entity is stored with `status = ENABLED` and the selected `typeId` | on success |
| ER-11 | Newly registered entity starts with an empty `accounts[]` array | on success |
| ER-12 | No unexpected reverts | on revert |

### `setEntityStatus` — group 20

Checked in `setEntityStatusPostconditions` for `fuzz_setEntityStatus`.

| ID | Condition | Checked |
|---|---|---|
| ER-20 | Entity status matches the requested `ENABLED` / `DISABLED` value | on success |
| ER-21 | No unexpected reverts | on revert |

### `requestAccountRegistration` + `acceptAccountRegistration` — group 30

Checked in `registerAccountPostconditions` for `fuzz_registerAccount`.

| ID | Condition | Checked |
|---|---|---|
| ER-30 | Accepted account is stored as `ENABLED`, linked to the selected entity, and marked as registered | on success |
| ER-31 | Target entity account count increments by exactly 1 after acceptance | on success |
| ER-32 | No unexpected reverts when the selected requester is already an enabled manager for the entity | on revert (`managerAuthorized = true`) |
| ER-33 | If the selected requester is not an enabled manager, the request must revert with `ER__NotEntityManagerOrAdmin` | on revert (`managerAuthorized = false`) |

### Pending account registration — groups 92-107

Checked in `requestAccountRegistrationPostconditions`, `acceptAccountRegistrationPostconditions`, and targeted pending handlers.

| ID | Condition | Checked |
|---|---|---|
| ER-92 | Pending request stores the requested role flags and requester | request success |
| ER-93 | Requesting pending registration does not register the account or change entity account count | request success |
| ER-94 | Re-requesting the same `(account, entityId)` overwrites pending requester/role data | overwrite handler |
| ER-95 | One account can have independent pending requests for two entities | multi-entity handler |
| ER-96 | Unauthorized requesters revert with `ER__NotEntityManagerOrAdmin` | request revert |
| ER-97 | Zero account requests revert with `ZeroAddress` | request negative surface |
| ER-98 | Zero, missing, and disabled entities revert with their specific entity-state selector | request negative surface |
| ER-99 | Requests for already registered accounts revert with `ER__AccountAlreadyRegistered` | request negative surface |
| ER-100 | Accepting a pending request registers the wallet and applies pending role flags | accept success |
| ER-101 | Accepting a pending request increments entity account count | accept success |
| ER-102 | Accepted pending request is deleted | accept success |
| ER-103 | Accepting without a pending request reverts with `ER__AccountRegistrationNotPending` | accept negative surface |
| ER-104 | Accepting while already registered reverts with `ER__AccountAlreadyRegistered` | accept negative surface |
| ER-105 | Accepting after requester manager revocation reverts with `ER__NotEntityManagerOrAdmin` | revocation handler |
| ER-106 | Failed accept after requester revocation leaves pending request data intact | revocation handler |
| ER-107 | Pending request survives direct registration and account removal until it is accepted | stale-removal handler |

### `setAccountStatus` — group 40

Checked in `setAccountStatusPostconditions` for `fuzz_setAccountStatus`.

| ID | Condition | Checked |
|---|---|---|
| ER-40 | Account status matches the requested `ENABLED` / `DISABLED` value | on success |
| ER-41 | No unexpected reverts | on revert |

### `removeAccount` — group 50

Checked in `removeAccountPostconditions` for `fuzz_removeAccount`.

| ID | Condition | Checked |
|---|---|---|
| ER-50 | Removed account is no longer registered (`status = NONE`) | on success |
| ER-51 | Source entity account count decreases by exactly 1 | on success |
| ER-52 | No unexpected reverts | on revert |

### `transferAccountToEntity` — group 60

Checked in `transferAccountPostconditions` for `fuzz_transferAccountToEntity`.

| ID | Condition | Checked |
|---|---|---|
| ER-60 | Transferred account points to the new entity and remains registered | on success |
| ER-61 | Old entity account count decreases by exactly 1 | on success |
| ER-62 | New entity account count increments by exactly 1 | on success |
| ER-63 | No unexpected reverts | on revert |

### `setEntityManager` — group 70

Checked in `setEntityManagerPostconditions` for `fuzz_setEntityManager`.

| ID | Condition | Checked |
|---|---|---|
| ER-70 | `isEntityManager(entityId, manager)` matches the requested boolean | on success |
| ER-71 | No unexpected reverts | on revert |

## Auxiliary Coverage Surfaces

The handlers below are direct surface checks rather than lifecycle-transition groups:

| ID | Handler | Condition |
|---|---|---|
| ER-80 | `fuzz_registerEntityWithAccess` | Access overload stores the chosen authority and enabled managers while preserving base entity-registration invariants |
| ER-81 | `fuzz_registerEntityBatch`, `fuzz_setEntityMetadata` | Metadata references are stored as expected |
| ER-82 | `fuzz_setEntityAuthority` | Authority assignment/rotation stores the expected authority |
| ER-83 | `fuzz_setAccountRoleFlags` | Account role flags store the requested bitmap |
| ER-84 | `fuzz_entityRegistryViewSurface` | Getter/validation surface returns expected values for enabled accounts and zero-address transfer/approve allowances |
| ER-85 | `fuzz_entityRegistryViewSurface` | Disabled accounts are rejected by account-gated approval checks |
| ER-86 | `fuzz_entityRegistryViewSurface` | Disabled accounts/entities are rejected by account-gated transfer checks |
| ER-87 | `fuzz_entityTypeSurface` | `defineEntityType` stores non-zero name/caps and starts unfrozen |
| ER-88 | `fuzz_entityTypeSurface` | `freezeEntityType` stores the frozen flag |
| ER-89 | `fuzz_entityRegistryAdminSurface` | `grantRoles` scalar and batch overloads grant the selected valid role |
| ER-90 | `fuzz_entityRegistryViewSurface`, `fuzz_entityRegistryFreshDeployment` | ERC-165 support reports expected interfaces and rejects the invalid interface ID |
| ER-91 | `fuzz_entityAccountSwapAndPopSurface` | Account transfer/removal lifecycle preserves entity account indices and links through swap-and-pop paths |
| ER-110 | `fuzz_adminRegisterAccount` | Admin `registerAccount` immediately stores an enabled account with the requested entity and role flags |
| ER-111 | `fuzz_adminRegisterAccount` | Admin `registerAccount` increments the target entity account count |
| ER-112 | `fuzz_registerAccountUnauthorized` | Non-admin `registerAccount` reverts with Solady `Unauthorized()` |
| ER-113 | `fuzz_registerAccountInvalidInputs` | Admin `registerAccount` rejects zero account |
| ER-114 | `fuzz_registerAccountInvalidInputs` | Admin `registerAccount` rejects zero, missing, or disabled entity with the expected selector |
| ER-115 | `fuzz_registerAccountInvalidInputs` | Admin `registerAccount` rejects already registered accounts |

`fuzz_entityRegistryInitializeAgain` and `fuzz_entityRegistryFreshDeployment` also assert initializer locking on the live proxy and on a freshly deployed implementation.

### Cross-cutting invariants

These are re-evaluated after every successful EntityRegistry action.

| ID | Condition |
|---|---|
| ER-01 | For every tracked entity, each account in `entity.accounts[]` links back to that entity with the correct 1-based `entityAccountIndex` |

## Preconditions

Summary of the clamping and state-selection logic applied before each handler issues a protocol call. Full implementation in [`helper/preconditions/PreconditionsEntityRegistry.sol`](../../test/fuzzing/helper/preconditions/PreconditionsEntityRegistry.sol).

| Handler | Clamp rules |
|---|---|
| `registerEntity` | `entityId` is deterministically derived as `keccak256(abi.encodePacked(address(this), entityNonce))`, then `entityNonce` increments. `typeId` is chosen from `{BROKER_ENTITY, NATURAL_PERSON_ENTITY, DEUSS_PROTOCOL_ENTITY}` via `typeIdSeed % 3`. |
| `setEntityStatus` | Entity picked from `FuzzEntityBucket.Existing`, so only fuzz-created entities are reachable. Requested status is `ENABLED` when `enable = true`, otherwise `DISABLED`. |
| `registerAccount` | Wallet picked from `FuzzAccountBucket.Free`. Entity picked from `EntityBucket.Enabled`, so disabled entities are excluded. Requester is `MANAGERS[managerSeed % MANAGERS.length]`; successful requests are accepted by the wallet. The precondition records whether that manager is already enabled for the entity so postconditions can distinguish expected success from expected authorization failure. |
| `requestAccountRegistration` | Wallet picked from `FuzzAccountBucket.Free`; pending-only requests leave that wallet in the free bucket until acceptance. Entity is picked from `EntityBucket.Enabled`; requester comes from `MANAGERS`. |
| `acceptAccountRegistration` | Pending pair picked from the bounded pending-registration set. Postconditions classify failure by the contract's check order: entity enabled, account not registered, pending request exists, requester still manager/admin. |
| `requestAccountRegistrationOverwrite` | Wallet and entity are selected like `requestAccountRegistration`; two distinct managers are enabled before issuing two requests for the same pair. |
| `requestAccountRegistrationMultipleEntities` | Wallet is selected from `FuzzAccountBucket.Free`; two distinct enabled entities are selected; one manager is enabled for both before issuing the two requests. |
| `pendingAccountRegistrationInvalidInputs` | Uses one valid enabled entity/manager pair, plus a fresh disabled fuzz entity and a missing synthetic entity ID, to pin each request/accept validation selector. |
| `acceptAccountRegistrationAlreadyRegistered` | Creates a valid pending request, registers the same wallet directly into a different enabled entity, then asserts accept reverts before consuming the pending request. |
| `requesterRevocationBeforeAcceptance` | Creates a valid pending request, disables the requester manager flag, and asserts accept reverts while pending data remains. |
| `stalePendingRegistrationAfterRemoval` | Creates a valid pending request, directly registers and removes the same account through a different entity, verifies the pending request remains, then accepts it. |
| `adminRegisterAccount` | Wallet picked from `FuzzAccountBucket.Free`; entity picked from `EntityBucket.Enabled`; role flags are passed through directly. |
| `registerAccountUnauthorized` | Same valid account/entity selection as `adminRegisterAccount`, but the call is pranked from `FUZZ_ESCROW_UNAUTH_CALLER`, which has no `ADMIN_ROLE`. |
| `registerAccountInvalidInputs` | Uses a selected free wallet, a valid enabled entity, a missing synthetic entity ID, a fresh disabled fuzz entity, and `USER1` restored to enabled status for the already-registered branch. |
| `setAccountStatus` | Wallet picked from `FuzzAccountBucket.Registered`. Its linked entity must still be `ENABLED`, matching the protocol precondition for `setAccountStatus`. Requested status is `ENABLED` when `enable = true`, otherwise `DISABLED`. |
| `removeAccount` | Wallet picked from `FuzzAccountBucket.Registered`. The linked `entityId` is read from the current account record and used for before/after count assertions. Registered fuzz wallets are disjoint from the authority/manager subject pools, so the governance-account guard is covered by unit tests rather than this lifecycle fuzz path. |
| `transferAccountToEntity` | Wallet picked from `FuzzAccountBucket.Registered`. Source entity must be `ENABLED`. Destination entity is picked from `EntityBucket.Enabled` and must differ from the current entity. Registered fuzz wallets are disjoint from the authority/manager subject pools, so the governance-account guard is covered by unit tests rather than this lifecycle fuzz path. |
| `setEntityManager` | Entity picked from `EntityBucket.Existing`, so both setup entities and fuzz-created entities are eligible. Manager subject is `MANAGERS[managerSeed % MANAGERS.length]`; `enabled` is passed through directly. |
| `registerEntityWithAccess` | Reuses `registerEntity`'s unique-ID generation and supported-type selection, then chooses a non-zero authority and two distinct non-zero manager addresses from the unregistered fuzz manager pool so bootstrap access assignments satisfy the registered-account lifecycle checks. |
| `registerEntityBatch` | Reuses the deterministic `registerEntity` ID/type derivation twice so both batch items are valid and unique. |
| `setEntityMetadata` | Entity is picked from `EntityBucket.Enabled`; metadata is selected from a small fixed fuzz-only string set. |
| `setEntityAuthority` | Entity is picked from `EntityBucket.Existing`; the handler chooses two non-zero authority addresses distinct from the current authority so both the admin path and authority-rotation path stay valid. |
| `setAccountRoleFlags` | Uses the always-registered core actor `USER1`, restoring its entity/account enabled state first if a previous fuzz action temporarily disabled it. |
| `entityRegistryViewSurface` | Uses the always-registered core actor `USER1`, restores it to a clean enabled state, toggles account/entity status only temporarily to probe negative validation branches, then restores the original enabled state before returning. |
| `entityTypeSurface` | Mints a fresh synthetic `typeId` from the harness nonce, first asserts that `defineEntityType(typeId, 0, caps)` reverts, then defines and freezes the type with a non-zero name. |
| `entityRegistryAdminSurface` | Grants valid roles only to fuzz-only sink addresses (`FUZZ_WALLET_4`..`FUZZ_WALLET_7`) so the broader harness caller model is unchanged. |
| `entityRegistryInitializeAgain` | No state selection: it directly probes the already-initialized live proxy. |
| `entityRegistryFreshDeployment` | No state selection: it deploys a fresh standalone implementation and checks that the constructor's `_disableInitializers()` lock is active. |
| `entityAccountSwapAndPopSurface` | Requires two distinct wallets from `FuzzAccountBucket.Free`; it then registers both into a fresh source entity, transfers the first into a fresh target entity, and removes the second. |

All clamp failures raise `ClampFail(string)`, which the integrity layer accepts as a skip rather than a bug.
