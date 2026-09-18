# EscrowManager Authorization Fuzz Coverage

Vertical entrypoint: [`test/fuzzing/FuzzEscrowAuthIntegrity.sol`](../../test/fuzzing/FuzzEscrowAuthIntegrity.sol)
Invariants: [`test/fuzzing/properties/Properties_ESAU.sol`](../../test/fuzzing/properties/Properties_ESAU.sol)
Descriptions: [`test/fuzzing/properties/PropertiesDescriptions.sol`](../../test/fuzzing/properties/PropertiesDescriptions.sol)

## Scope

Authorization-flow coverage for [`EscrowManager`](../marketplace/EscrowManager.md) — the second half of the "AssetManager and escrow authorization flow" task, complementing [`AssetManager.md`](AssetManager.md). This vertical targets the module authorization matrix, the admin gate on mutators, and the authorization checks on the module-only entrypoints.

Positive-path escrow lifecycle (createEscrow, withdraw, claim with real token transfers) is exercised by the [`Marketplace`](Marketplace.md) vertical through ESCR-10..15; this vertical focuses on the authorization surface **around** those entrypoints.

The harness operates on a dedicated pool of four synthetic module addresses (`0xE551..0xE554`) and four module-type hashes (`{bytes32(0), keccak256("FUZZ_MODULE_TYPE_A/B/C")}`). The fuzz types are distinct from the real `MARKETPLACE_MODULE` / `ORDERBOOK_MARKETPLACE_MODULE` hashes, so a fuzz-registered module can never be authorized to touch a real escrow. The admin calls themselves come from `address(this)` (harness holds ADMIN); the non-admin rejection handlers call as one of the three engine sender addresses (`0x10000`, `0x20000`, `0x30000`).

## Handlers

| Entrypoint | Caller | Target | Purpose |
|---|---|---|---|
| `fuzz_registerModule` | harness (admin) | `escrowManager.registerModule` | Drive the module-registration state machine over the fuzz pool |
| `fuzz_registerModuleUnauthorized` | `currentActor` | `escrowManager.registerModule` | Assert the ADMIN gate rejects non-admins |
| `fuzz_deactivateModule` | harness (admin) | `escrowManager.deactivateModule` | Drive the deactivation state machine |
| `fuzz_deactivateModuleUnauthorized` | `currentActor` | `escrowManager.deactivateModule` | ADMIN gate |
| `fuzz_setAssetManager` | harness (admin) | `escrowManager.setAssetManager` | Rotate the wired AssetManager; restores the real wiring before returning |
| `fuzz_setAssetManagerUnauthorized` | `currentActor` | `escrowManager.setAssetManager` | ADMIN gate |
| `fuzz_createEscrowAsActor` | `currentActor` (EOA) | `escrowManager.createEscrow` | Confirm `_requireAuthorizedCallerModule` rejects non-module callers |
| `fuzz_withdrawAsActor` | unauthorized pool address | `escrowManager.withdraw` | Confirm the `EscrowNotFound` vs `ModuleNotAuthorized` selector mapping |
| `fuzz_claimAsActor` | unauthorized pool address | `escrowManager.claim` | Same as above for `claim` |
| `fuzz_sweep` | harness (admin) | `escrowManager.sweep` | Exercise sweep's full revert surface on a documented asset pool |
| `fuzz_sweepUnauthorized` | `currentActor` | `escrowManager.sweep` | ADMIN gate |

The admin handlers call through `address(this)` via `fl.doFunctionCall(target, data, admin)`. The `setAssetManager` handler is the only one that must carry a manual restore step: if it successfully rotated the AssetManager away from the real one, it immediately re-applies the real address before returning so subsequent `fuzz_registerOffer` calls keep working (otherwise `Marketplace.registerOffer` would start reverting with `AssetNotSupported` and break OFER-13). `fuzz_registerModule` / `fuzz_deactivateModule` operate entirely on the fuzz pool and never touch real registrations.

## Invariants

### Cross-cutting invariants

Re-evaluated after every successful or reverted handler through `_runEscrowAuthGlobals`. These iterate the full module pool so a storage collision in any mutator would surface regardless of which pair was targeted.

| ID | Condition |
|---|---|
| ESAU-01 | For every module in the pool, `moduleTypeOf[m] != 0` iff `isAuthorizedModule[moduleTypeOf[m]][m] == true` — the two mappings stay in perfect sync |
| ESAU-02 | Each module in the pool is authorized under at most one type simultaneously |

### `registerModule` — group 10

Checked in `registerModulePostconditions` for `fuzz_registerModule`.

| ID | Condition | Checked |
|---|---|---|
| ESAU-10 | `moduleTypeOf[m] == type` and `isAuthorizedModule[type][m] == true` after the call | on success |
| ESAU-11 | No other `(type, addr)` pair in the pool is mutated | on success & on revert |
| ESAU-12 | Revert selector matches the first failing predicate evaluated against pre-state: `InvalidModuleType` (type==0) → `InvalidModuleAddress` (addr==0) → `ModuleTypeMismatch` (different type already registered) → `ModuleAlreadyRegistered` (same type already registered) | on revert |
| ESAU-13 | Success implies non-zero type, non-zero module address, and no pre-existing registration for that address | on success |

### `deactivateModule` — group 20

Checked in `deactivateModulePostconditions` for `fuzz_deactivateModule`.

| ID | Condition | Checked |
|---|---|---|
| ESAU-20 | `moduleTypeOf[m] == 0` and `isAuthorizedModule[type][m] == false` after the call | on success |
| ESAU-21 | No other `(type, addr)` pair in the pool is mutated | on success & on revert |
| ESAU-22 | Revert selector matches the first failing predicate: `InvalidModuleType` → `InvalidModuleAddress` → `ModuleNotRegistered` (pre-state type was 0) → `ModuleTypeMismatch` (pre-state type differed) → `ModuleHasActiveEscrows` | on revert |
| ESAU-23 | Success implies non-zero type, non-zero module address, and matching pre-state registration for that address/type pair | on success |

### `setAssetManager` — group 30

Checked in `setAssetManagerPostconditions` for `fuzz_setAssetManager`.

| ID | Condition | Checked |
|---|---|---|
| ESAU-30 | `assetManager == newAddress` after a successful call | on success |
| ESAU-31 | Revert selector is `ZeroAddress` (the only documented failure mode) | on revert |
| ESAU-32 | The module authorization matrix is not touched by the call | on success & on revert |
| ESAU-33 | A failed `setAssetManager` attempt implies the requested address was zero | on revert |
| ESAU-34 | The directed self-call that restores the real AssetManager succeeds | after successful rotation |

### `createEscrow` authorization — group 40

Checked in `createEscrowAsActorPostconditions` for `fuzz_createEscrowAsActor`. The caller is always a USER (EOA, never a module), so `_requireAuthorizedCallerModule` hits the first guard.

| ID | Condition | Checked |
|---|---|---|
| ESAU-40 | Revert selector is `ModuleNotRegistered` | every call |
| ESAU-41 | Authorization matrix, `nextEscrowId`, and AssetManager wiring are all unchanged | every call |
| ESAU-42 | The call itself must fail; success would mean an unregistered caller created an escrow | every call |

### `withdraw` / `claim` authorization — group 50

Checked in `withdrawOrClaimAsActorPostconditions` for `fuzz_withdrawAsActor` and `fuzz_claimAsActor`. The caller is a pool address that is never authorized for any real escrow's moduleType.

| ID | Condition | Checked |
|---|---|---|
| ESAU-50 | Revert selector is `EscrowNotFound` when the targeted escrow slot is empty, otherwise `ModuleNotAuthorized` | every call |
| ESAU-51 | Authorization matrix and `nextEscrowId` are unchanged | every call |
| ESAU-52 | The call itself must fail; success would mean an unauthorized caller moved escrowed funds | every call |

### `sweep` — group 60

Checked in `sweepPostconditions` for `fuzz_sweep`. Inputs are restricted (see Preconditions below) so only documented revert branches are reachable.

| ID | Condition | Checked |
|---|---|---|
| ESAU-60 | Revert selector matches the first failing predicate: `InvalidAssetType` (NONE) → `InvalidTokenId` (ERC20 + tid≠0) → `InvalidSweepAmount` (amount==0) → `InvalidBeneficiary` (beneficiary==0) → `InvalidERC721Amount` (ERC721 + amt≠1) → `SweepExceedsSurplus` (amount > surplus) | on revert |
| ESAU-61 | Authorization matrix is not touched regardless of outcome | every call |

### Admin gate (`Unauthorized`) — group 70

Checked in `adminUnauthorizedPostconditions` for every `*Unauthorized` handler.

| ID | Condition | Checked |
|---|---|---|
| ESAU-70 | Revert selector is solady's `Ownable.Unauthorized.selector` | every call |
| ESAU-71 | Authorization matrix, AssetManager wiring, and `nextEscrowId` are all unchanged | every call |
| ESAU-72 | The admin-guarded call itself must fail for a non-admin caller | every call |

## Preconditions

Summary of the clamping and state-selection logic. Full implementation in [`helper/preconditions/PreconditionsEscrowAuth.sol`](../../test/fuzzing/helper/preconditions/PreconditionsEscrowAuth.sol).

| Handler | Clamp rules |
|---|---|
| `registerModule` / `deactivateModule` (both authorized and unauthorized variants) | `moduleType` picked from `{bytes32(0), FUZZ_MODULE_TYPE_A, B, C}` — index 0 is zero so `InvalidModuleType` is reachable from the same modulo-based seed picker. `moduleAddr` picked from `address(0)` or the four-address fuzz pool so `InvalidModuleAddress` remains reachable. |
| `setAssetManager` (both variants) | Candidate selected evenly across `{real AssetManager (no-op), synthetic non-zero (rotate+restore), address(0) (ZeroAddress revert)}`, one third of the time each. |
| `createEscrowAsActor` | Caller is always `currentActor`, one of the tracked engine users, which are EOAs and are never registered as modules, guaranteeing the authorization gate fires first. `amount`, `depositor` (picked from tracked users), and `tokenId` are passed through raw. |
| `withdrawAsActor` / `claimAsActor` | `escrowId` clamped to `[0, nextEscrowId + 2]` so both the empty-slot branch (`EscrowNotFound`) and the existing-but-unauthorized branch (`ModuleNotAuthorized`) are reachable. Caller is the dedicated `FUZZ_ESCROW_UNAUTH_CALLER`, which is kept out of the mutable module pools and validated as unregistered during setup. |
| `sweep` (both variants) | `assetType ∈ {NONE, ERC20, ERC721, ERC6909}` — ERC1155 is excluded because its `balanceOf(address, uint256)` selector aliases ERC6909's on the real bond token, which would let the ERC1155 branch reach `_transferAsset` and revert with empty data on a missing `safeTransferFrom`. For `ERC20`, `tokenId` is forced non-zero so `InvalidTokenId` fires before the ERC20 balance probe (our ERC6909 token has no `balanceOf(address)`). `amount ∈ {0, 1, 2, 3}` so both the ERC721 `amount == 1` and general `InvalidSweepAmount` branches are common. Beneficiary is selected from zero address or the tracked users. |

All clamp failures raise `ClampFail(string)`, which the integrity layer accepts as a skip. In practice the module and type pools are non-empty after setup, so clamp failures do not occur under normal fuzzing.
