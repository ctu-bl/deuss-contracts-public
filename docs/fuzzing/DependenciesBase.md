# DependenciesBase Fuzz Coverage

Vertical entrypoint: [`test/fuzzing/FuzzDEPIntegrity.sol`](../../test/fuzzing/FuzzDEPIntegrity.sol)
Invariants: [`test/fuzzing/properties/Properties_DEP.sol`](../../test/fuzzing/properties/Properties_DEP.sol)
Descriptions: [`test/fuzzing/properties/PropertiesDescriptions.sol`](../../test/fuzzing/properties/PropertiesDescriptions.sol)

## Scope

Direct exercise of `DependenciesBase` write-once dependency wiring (G-7 / I-4). `DependenciesBase` is an inherited wiring base; its setters are exercised through an already-deployed in-harness consumer that inherits it (via `EligibilityModuleBase` → `EntityEligibilityGuard` → `DependenciesBase`), so all setter calls route through that consumer instance. The base exposes three dependency slots: `bondRegistry`, `escrowManager`, and `entityRegistry`. In setup the `escrowManager` and `entityRegistry` slots are already wired (non-zero) and `bondRegistry` is unset, so the handlers exercise: (a) overwrite attempts against already-wired slots, (b) the first legitimate `0 → concrete` transition of the unset slot, and (c) unauthorized-caller rejection.

The authorized caller is the ADMIN role holder (`address(this)`). The unauthorized handler pranks a non-admin caller drawn from the users pool. Each slot setter (`setBondRegistry` / `setEscrowManager` / `setEntityRegistry`) has no path to clear a populated slot and reverts with the matching per-slot `AlreadySet` error on a second set.

All invariants in this vertical are **passing** in the consistency campaign.

## Handlers

| Entrypoint | Caller | Target | Purpose |
|---|---|---|---|
| `fuzz_setDependency` | ADMIN (`address(this)`) | `DependenciesBase.setBondRegistry` / `setEscrowManager` / `setEntityRegistry` (on the consumer instance) | Authorized set of a chosen slot to a non-zero candidate; covers first 0→concrete wiring and already-set rejection |
| `fuzz_setDependencyUnauthorized` | non-admin caller (users pool) | same three setters (on the consumer instance) | Unauthorized set attempt; must revert and leave all slots unchanged (G-7) |

The handler selects which of the three slots to target by seed and derives a non-zero candidate address from a value seed.

## Invariants

### `setDependency` — write-once wiring (G-7 / I-4)

Checked in `setDependencyPostconditions` for `fuzz_setDependency`.

| ID | Condition | Checked |
|---|---|---|
| DEP-01 (G-7 / I-4) | A non-zero dependency slot is never overwritten with a different address (write-once, no-overwrite); evaluated for all three slots | every call |
| DEP-02 (G-7 / I-4) | A slot that was non-zero never resets back to zero (no clear path) | every call |
| DEP-04 (G-7 / I-4) | The only acceptable revert for an authorized non-zero set is the matching per-slot `AlreadySet` error (set against an already-wired slot is rejected, not silently overwritten) | on revert |

### `setDependencyUnauthorized` — access control (G-7)

Checked in `setDependencyPostconditions` for `fuzz_setDependencyUnauthorized`.

| ID | Condition | Checked |
|---|---|---|
| DEP-03 (G-7) | An unauthorized caller can never set a dependency: the call must revert with `Unauthorized()` and every slot must be unchanged | always |
