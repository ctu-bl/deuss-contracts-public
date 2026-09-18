# CompanyWallet Fuzz Coverage

Vertical entrypoint: [`test/fuzzing/FuzzWALLETIntegrity.sol`](../../test/fuzzing/FuzzWALLETIntegrity.sol)
Invariants: [`test/fuzzing/properties/Properties_WALLET.sol`](../../test/fuzzing/properties/Properties_WALLET.sol)
Descriptions: [`test/fuzzing/properties/PropertiesDescriptions.sol`](../../test/fuzzing/properties/PropertiesDescriptions.sol)

## Scope

Direct exercise of `CompanyWallet` ownership-epoch monotonicity (I-3) and the `execute` authorization surface (G-8, G-9 / X-3). The vertical uses the dedicated pre-deployed wallet instances `walletEpochA` and `walletEpochB`. These wallets are separate from the `PolicyRegistry` role/module wallets (`policyWalletA` / `policyWalletB`) and the policy-version wallet (`policyEpochWallet`), so WALLET epoch churn does not reset or perturb epoch-scoped state owned by the PolicyRegistry verticals.

`transferOwnership` is the epoch-bumping operation: it routes through `_setOwner`, which advances `_ownershipEpoch` by exactly +1, and is `onlyOwner`, so the call is always made as the selected wallet's live current owner. After a successful transfer, the handler rotates the wallet back to its original owner. With the dedicated `walletEpochA/B` pair this restore is not needed to protect other verticals; it keeps the owner pool stable so non-owner execute paths continue to exercise the intended caller set. The I-3 epoch bump is captured in the before/after snapshot before the restore, and the restoring rotation keeps the epoch monotonic.

`execute` is exercised both as a non-bumping owner control (epoch must stay flat) and across the two authorization legs: an invalid execute target must revert with the target-guard selector (G-8), and a non-owner `execute` must succeed if and only if `PolicyRegistry.canExecute` authorizes the caller for the chosen `(target, selector)` (G-9 / X-3).

Campaign evidence for this vertical is tracked in [`test/fuzzing/INVARIANT_VALIDATION.md`](../../test/fuzzing/INVARIANT_VALIDATION.md).

## Handlers

| Entrypoint | Caller | Target | Purpose |
|---|---|---|---|
| `fuzz_changeOwner` | wallet's live current owner | `CompanyWallet.transferOwnership(address)` | Owner-authorized ownership transfer; advances the ownership epoch by +1 |
| `fuzz_execute` | wallet's live current owner | `CompanyWallet.execute(target,value,data)` | Owner-authorized non-bumping control call; the epoch must stay flat |
| `fuzz_executeInvalidTarget` | wallet's live current owner | `CompanyWallet.execute(target,value,data)` | Owner-authorized `execute` against an invalid target (`address(0)`, the wallet itself, or an EOA), which must revert (G-8) |
| `fuzz_executeAsNonOwner` | non-owner (`USER1..3` / `POLICY_OUTSIDER`) | `CompanyWallet.execute(target,value,data)` | Non-owner `execute`; success must equal the live `PolicyRegistry.canExecute` decision (G-9 / X-3) |

`fuzz_changeOwner` selects the incoming owner from the EOA pool `{USER1, USER2, USER3}`, rotating to the next candidate when the seeded one collides with the current owner (`_setOwner` rejects a transfer to the current owner). `fuzz_executeAsNonOwner` optionally grants the caller matching user and operation roles for `(target, selector)` first (best-effort, via the wallet owner), then reads `canExecute` after any grant as ground truth.

## Invariants

### `changeOwner` — epoch bump (I-3)

Checked in `changeOwnerPostconditions` for `fuzz_changeOwner`.

| ID | Condition | Checked |
|---|---|---|
| WALLET-01 (I-3) | A single epoch-bumping operation increments the epoch by exactly +1 | on success |
| WALLET-02 (I-3) | The epoch never decreases across the observed operation | on success |
| WALLET-03 (I-3) | The live wallet reports `ownershipEpoch >= 1` (initialized to 1 at deployment) | every observation |

### `execute` — non-bumping control (I-3)

Checked in `executePostconditions` for `fuzz_execute`.

| ID | Condition | Checked |
|---|---|---|
| WALLET-04 (I-3) | A non-bumping operation (`execute`) leaves the ownership epoch unchanged | on success |
| WALLET-03 (I-3) | The live wallet reports `ownershipEpoch >= 1` | every observation |

### `executeInvalidTarget` — target guard (G-8)

Checked in `executeInvalidTargetPostconditions` for `fuzz_executeInvalidTarget`.

| ID | Condition | Checked |
|---|---|---|
| WALLET-G8 (G-8) | Owner-authorized `execute` with an invalid target (`address(0)`, the wallet itself, or an EOA) must revert with `CompanyWallet__InvalidCallTarget` | always |

### `executeAsNonOwner` — policy authorization (G-9 / X-3)

Checked in `executeAsNonOwnerPostconditions` for `fuzz_executeAsNonOwner`.

| ID | Condition | Checked |
|---|---|---|
| WALLET-G9 (G-9 / X-3) | A non-owner `execute` succeeds if and only if the live `PolicyRegistry.canExecute` decision for the same caller/target/selector is `true` | always |
