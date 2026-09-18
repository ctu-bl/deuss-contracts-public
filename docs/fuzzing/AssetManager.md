# AssetManager Fuzz Coverage

Vertical entrypoint: [`test/fuzzing/FuzzAssetManagerIntegrity.sol`](../../test/fuzzing/FuzzAssetManagerIntegrity.sol)
Invariants: [`test/fuzzing/properties/Properties_ASSET.sol`](../../test/fuzzing/properties/Properties_ASSET.sol)
Descriptions: [`test/fuzzing/properties/PropertiesDescriptions.sol`](../../test/fuzzing/properties/PropertiesDescriptions.sol)
Target contract: [`src/marketplace/AssetManager.sol`](../../src/marketplace/AssetManager.sol)

## Scope

End-to-end exercise of [`AssetManager`](../marketplace/AssetManager.md) focused on the three concerns from the task brief:

- **Asset listing eligibility** — `setAsset`, `setAssetTokenId`, and the view getters (`isAssetSupported`, `isTokenIdAllowed`, `getAssetConfig`, `getAssetType`) must remain consistent under arbitrary reconfiguration.
- **Supported asset-type constraints** — `validateAsset` must enforce the shape rules for each `AssetType` (ERC20 requires `tokenId == 0`, ERC721 requires `amount == 1`, NONE is rejected via the disabled gate).
- **Module authorization assumptions used by marketplace flows** — only ADMIN may mutate configuration, while view functions are callable by any address (marketplace modules rely on this through flows such as [`EscrowManager.createEscrow`](../../src/marketplace/EscrowManager.sol) and [`Marketplace.registerOffer`](../../src/marketplace/Marketplace.sol)).

The harness operates on a dedicated pool of four synthetic token addresses (`0xA551..0xA554`) disjoint from `address(token)` wired into Marketplace. This keeps the `Marketplace` vertical stable under arbitrary AssetManager reconfiguration — fuzzing AssetManager cannot accidentally disable the real bond token and break OFER/ESCR invariants.

A bounded set of four tokenIds (`{0, 1, 2, 3}`) is used as the per-(token, tokenId) allowlist probe. `tokenId = 0` naturally covers the ERC20 `tokenId == 0` success branch; `{1, 2, 3}` covers the rejection branches.

## Handlers

| Entrypoint | Caller | Target | Purpose |
|---|---|---|---|
| `fuzz_setAsset` | `address(this)` (admin) | `assetManager.setAsset` | Configure token-level asset support (assetType, enabled, enforceTokenId) |
| `fuzz_setAssetUnauthorized` | `currentActor` (non-admin) | `assetManager.setAsset` | Confirm the ADMIN gate rejects a non-admin caller |
| `fuzz_setAssetTokenId` | `address(this)` (admin) | `assetManager.setAssetTokenId` | Toggle a tokenId-level allowlist entry |
| `fuzz_setAssetTokenIdUnauthorized` | `currentActor` (non-admin) | `assetManager.setAssetTokenId` | Confirm the ADMIN gate rejects a non-admin caller |
| `fuzz_validateAsset` | `address(this)` | `assetManager.validateAsset` | Exercise the shape-validation path and compare against the state-derived oracle |
| `fuzz_validateAssetAsActor` | `currentActor` | `assetManager.validateAsset` | Confirm the view has no authorization gate — marketplace modules call it as themselves |

The six entrypoints cover every mutator and the full authorization surface. `fuzz_validateAsset` and `fuzz_validateAssetAsActor` share preconditions and postconditions but differ in caller, so a regression that introduced an auth check on the view would be caught by the `AsActor` variant failing while the admin variant keeps passing.

## Invariants

### Global consistency

Re-evaluated on every successful mutation through the per-handler postconditions.

| ID | Condition | Checked |
|---|---|---|
| ASET-01 | `isAssetSupported(token, tokenId)` equals `enabled && (!enforceTokenId || isTokenIdAllowed(token, tokenId))` for every known tokenId | after `setAsset` / `setAssetTokenId` success |
| ASET-02 | `getAssetType(token)` reverts iff the token's config is disabled, and otherwise returns `config.assetType` | after `setAsset` success |

### `setAsset` — group 10

Checked in `setAssetPostconditions` for `fuzz_setAsset`.

| ID | Condition | Checked |
|---|---|---|
| ASET-10 | After success, `getAssetConfig(token)` returns exactly the `(assetType, enabled, enforceTokenId)` passed in | on success |
| ASET-11 | After success, every `isTokenIdAllowed(token, *)` entry is unchanged — the `_allowedTokenIds` mapping is sticky across `setAsset` calls | on success |
| ASET-12 | Revert selector is one of `{ZeroAddress, AssetManager__InvalidAssetType}` | on revert |
| ASET-13 | On revert, the failure matches the specific guard: `ZeroAddress` iff `token == 0`, otherwise `InvalidAssetType` and `enabled && assetType == NONE` must hold | on revert |
| ASET-14 | No other token in the fuzz pool has its config or allowlist mutated | on success & on revert |
| ASET-15 | Success implies `token != 0` and not `(enabled && assetType == NONE)`, so guard weakening is caught even if the call no longer reverts | on success |

### `setAssetTokenId` — group 20

Checked in `setAssetTokenIdPostconditions` for `fuzz_setAssetTokenId`.

| ID | Condition | Checked |
|---|---|---|
| ASET-20 | After success, `isTokenIdAllowed(token, tokenId)` equals the `enabled` argument | on success |
| ASET-21 | After success, the token-level `getAssetConfig(token)` is unchanged (only the allowlist entry moved) | on success |
| ASET-22 | Revert selector is one of `{AssetManager__AssetNotSupported, AssetManager__TokenIdAllowlistDisabled}` | on revert |
| ASET-23 | Precise selector mapping: `AssetNotSupported` iff pre-state `!enabled`; otherwise `TokenIdAllowlistDisabled` and pre-state `!enforceTokenId` must hold | on revert |
| ASET-14 | No other token in the fuzz pool has its config or allowlist mutated | on success & on revert |
| ASET-24 | Success implies the token was enabled and tokenId allowlisting was enforced in pre-state | on success |

### `validateAsset` — group 30

Checked in `validateAssetPostconditions` for both `fuzz_validateAsset` and `fuzz_validateAssetAsActor`.

| ID | Condition | Checked |
|---|---|---|
| ASET-30 | Success iff `enabled && (!enforceTokenId || isTokenIdAllowed) && (assetType != ERC20 || tokenId == 0) && (assetType != ERC721 || amount == 1)` | every call |
| ASET-31 | On revert, the selector matches the first failing predicate in the contract's evaluation order: `AssetNotSupported` → `TokenIdNotSupported` → `InvalidTokenId` → `InvalidAmountForERC721` | on revert (within ASET-30 body) |
| ASET-32 | `validateAsset` does not mutate any token's configuration or allowlist entry — view-function purity | every call |
| ASET-33 | On success, the returned `AssetType` equals the stored `config.assetType` and canonical nominal metadata is zero without a configured BondRegistry source | on success |

### Module authorization — group 40

Checked in `setAssetUnauthorizedPostconditions` / `setAssetTokenIdUnauthorizedPostconditions` for the corresponding `_Unauthorized` handlers.

| ID | Condition | Checked |
|---|---|---|
| ASET-40 | `setAsset` called by a non-admin always reverts with `Unauthorized()` (solady `onlyRoles` gate) | every call |
| ASET-41 | `setAssetTokenId` called by a non-admin always reverts with `Unauthorized()` | every call |
| ASET-42 | The entire fuzz pool is unchanged after any non-admin attempt (no partial mutation) | every call |

`fuzz_validateAssetAsActor` is the positive counterpart: the view must succeed for any caller on the same state the admin would observe — no separate invariant ID is needed because it reuses ASET-30..33.

## Preconditions

Summary of the clamping and state-selection logic. Full implementation in [`helper/preconditions/PreconditionsAssetManager.sol`](../../test/fuzzing/helper/preconditions/PreconditionsAssetManager.sol).

| Handler | Clamp rules |
|---|---|
| `setAsset` | `token` picked from `address(0)` or `knownAssetTokens`, so the `ZeroAddress` guard remains reachable; `assetType = AssetType(seed % 5)` so `NONE` is reachable and the `InvalidAssetType` branch is exercised; `enabled` and `enforceTokenId` passed through raw. |
| `setAssetTokenId` | `token` picked from `address(0)` or `knownAssetTokens`; `tokenId` picked from the bounded tokenId pool; `enabled` passed through raw. Preconditions do **not** gate on the current config so the success path, disabled-token revert, and allowlist-disabled revert are reachable. |
| `validateAsset` / `validateAssetAsActor` | `token` picked from `address(0)` or `knownAssetTokens`, and `tokenId` picked from the bounded pool (so `tokenId == 0` is common and the ERC20 success path is reachable); `amount` clamped to `amount % 8` so `amount == 1` is common and the ERC721 success branch is exercised. |
| Unauthorized variants | Identical input selection to their authorized counterparts; only the caller changes (`currentActor` instead of the harness). |

All clamp failures raise `ClampFail(string)`, which the integrity layer accepts as a skip rather than a bug — in practice the asset pools are never empty post-setup, so clamp failures do not occur under normal fuzzing.

## Why this coverage is sufficient

- **Every state transition has both a positive and negative oracle.** Every mutator checks both success-state correctness (ASET-10/20) AND revert-reason correctness (ASET-12/13/22/23) based on pre-state snapshots, not just "does not revert unexpectedly".
- **Cross-function consistency is pinned.** ASET-01 and ASET-02 tie the cheap view getters to the internal config, so a bug that de-synchronises them (e.g. `isAssetSupported` forgetting to honour `enabled`) fails immediately after any mutation.
- **`validateAsset` is a state-derived oracle, not just a reverts-check.** ASET-30 computes the expected outcome from the pre-state snapshot and asserts exact selector mapping — a bug that swapped the order of the shape checks would be caught.
- **Cross-token isolation (ASET-14) guards against storage collisions.** Mutators provably touch only the target token.
- **Sticky allowlist (ASET-11).** `setAsset` is verified to preserve `_allowedTokenIds` entries — this is the subtle property marketplace flows rely on when an admin briefly disables and re-enables a token.
- **Module authorization is checked from both sides.** ADMIN-only mutators reject non-admins (ASET-40/41/42); the auth-free view (`validateAsset`) is explicitly exercised by a non-admin caller (`fuzz_validateAssetAsActor`) so a regression adding an auth gate there would fail immediately.
