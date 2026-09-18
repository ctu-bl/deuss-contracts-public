# EntityEligibilityGuard Documentation

## Overview

`EntityEligibilityGuard` is a reusable abstract guard for contracts that need to check whether a wallet belongs to an enabled entity and whether that entity's type is allowed for a protocol flow. The checks resolve account and entity state through [`EntityRegistry`](EntityRegistry.md).

The guard is used through `EligibilityModuleBase`, which combines:
- `DependenciesBase`: one-shot dependency setters for `BondRegistry`, `EscrowManager`, and `EntityRegistry`
- `EntityEligibilityGuard`: internal entity-enabled and entity-type checks
- `IEntityEligibilityAdmin`: admin-facing entity type allowlist setters

Current marketplace usage is documented in [`Marketplace`](../marketplace/Marketplace.md).

## Prerequisites

- Inheriting contracts must grant `ADMIN` to accounts authorized to wire dependencies and entity-type allowlists
- `EntityRegistry` must be configured when eligibility checks are intended to be enforced
- Allowed entity type IDs must be configured before guarded flows are opened

## Contract Architecture

- `DependenciesBase` stores `_bondRegistry`, `_escrowManager`, and `_entityRegistry`
- Dependency setters are one-shot and revert if the dependency has already been set
- `EntityEligibilityGuard` stores `mapping(uint256 typeId => bool allowed) _allowedEntityTypes`
- `EligibilityModuleBase` exposes `setAllowedEntityType` and `setAllowedEntityTypes`

## Authorization Model

- `ADMIN`: Can set dependencies through `setBondRegistry`, `setEscrowManager`, `setEntityRegistry`
- `ADMIN`: Can update allowed entity types through `setAllowedEntityType` and `setAllowedEntityTypes`
- Owner: Can grant/revoke `ADMIN` through `OwnableRolesExtension`

## Core Functions and Flows

### setBondRegistry(address bondRegistry)

Stores the `BondRegistry` dependency.

**Important Notes:**
- Reverts with `ZeroAddress()` for zero address
- Reverts with `DependenciesBase__BondRegistryAlreadySet()` if already configured

### setEscrowManager(address escrowManager)

Stores the `EscrowManager` dependency.

**Important Notes:**
- Reverts with `ZeroAddress()` for zero address
- Reverts with `DependenciesBase__EscrowManagerAlreadySet()` if already configured

### setEntityRegistry(address entityRegistry)

Stores the `EntityRegistry` dependency used by eligibility checks.

**Important Notes:**
- Reverts with `ZeroAddress()` for zero address
- Reverts with `DependenciesBase__EntityRegistryAlreadySet()` if already configured

### setAllowedEntityType(uint256 typeId, bool allowed)

Enables or disables one entity type ID.

**Events:**
- `EntityTypeAllowed(typeId, allowed)`

### setAllowedEntityTypes(uint256[] calldata typeIds, bool allowed)

Batch version of `setAllowedEntityType`.

### _validateEntityWalletEnabled(address wallet)

Internal validation used by inheriting modules.

**Behavior:**
- If `EntityRegistry` is not configured, returns without reverting
- Otherwise requires `IEntityRegistry(entityRegistry).isAccountEnabled(wallet) == true`

**Errors:**
- `EntityEligibilityGuard__EntityWalletNotAllowed(wallet)`

### _validateEntityTypeAllowed(address wallet)

Internal validation for entity type allowlisting.

**Behavior:**
- If `EntityRegistry` is not configured, returns without reverting
- Otherwise resolves `getEntityTypeIdByAccount(wallet)` and requires that type ID to be allowed

**Errors:**
- `EntityEligibilityGuard__EntityTypeNotAllowed(typeId)`

### _validateEntityWalletAndTypeAllowed(address wallet)

Checks wallet enablement first, then entity type allowlist status.

### _validateEntityWalletsAndTypesAllowed(address[] memory wallets)

Batch version of `_validateEntityWalletAndTypeAllowed`.

## Trust and Security Notes

- Leaving `EntityRegistry` unset disables the guard checks. This is useful for staged initialization but should be treated as a bootstrap-only state when eligibility is required.
- Dependency setters are intentionally one-shot in `DependenciesBase`; rotating these dependencies requires an inheriting contract to provide an explicit override.
- Entity type IDs are protocol configuration. Docs and deployment scripts should keep the expected entity type IDs aligned with `EntityRegistry` setup.
