# EntityRegistry I-1 Extension Fuzz Coverage

Vertical entrypoint: [`test/fuzzing/FuzzEntityRegistryIntegrity.sol`](../../test/fuzzing/FuzzEntityRegistryIntegrity.sol)
Invariants: [`test/fuzzing/properties/Properties_ER.sol`](../../test/fuzzing/properties/Properties_ER.sol)
Descriptions: [`test/fuzzing/properties/PropertiesDescriptions.sol`](../../test/fuzzing/properties/PropertiesDescriptions.sol)

## Scope

This is a short extension doc for the I-1 (account↔entity linkage) invariant added to the existing EntityRegistry vertical. The base coverage is documented in [`EntityRegistry.md`](./EntityRegistry.md); this file describes only the added `invariant_ER_92` round-trip check.

`invariant_ER_92` complements the forward walk of `ER-01` (which walks each entity's `accounts[]` array and confirms every member links back with the correct 1-based `entityAccountIndex`) by checking the reverse direction: starting from a registered account, its stored 1-based `entityAccountIndex` must dereference back to itself inside the linked entity's `accounts[]` array, with no out-of-range, stale, or mismatched slot. This specifically validates that array length and index bookkeeping stay consistent after a swap-and-pop removal. The extension is **passing** in the consistency campaign.

## Handlers

The extension reuses the existing `fuzz_entityAccountSwapAndPopSurface` handler (caller `address(this)` under the `ONBOARDING` / `WALLET_TRANSFER` roles) and is evaluated in `setAccountStatusPostconditions` and `registerAccountPostconditions`. No new handler is added.

| Entrypoint | Caller | Target | Purpose |
|---|---|---|---|
| `fuzz_entityAccountSwapAndPopSurface` | harness (`address(this)`, `ONBOARDING` / `WALLET_TRANSFER`) | register/transfer/remove account lifecycle | Forces the swap-and-pop branch in `entity.accounts[]`, then asserts the surviving account's index round-trips (`ER_92`) alongside `ER_01` / `ER_91` |

## Invariants

### Account-side linkage round-trip (I-1 extension)

Checked via `invariant_ER_92(account)` after swap-and-pop removal (`fuzz_entityAccountSwapAndPopSurface`) and in account-registration/status postconditions.

| ID | Condition | Checked |
|---|---|---|
| ER-92 (I-1) | The account is registered, carries a non-zero 1-based `entityAccountIndex` within range of the linked entity's compacted `accounts[]`, and `accounts[entityAccountIndex - 1] == account` (round-trip holds after swap-and-pop) | on the swap-and-pop / account-registration paths |
