# EscrowManager Fuzz Coverage

Vertical entrypoint: [`test/fuzzing/FuzzEscrowManagerIntegrity.sol`](../../test/fuzzing/FuzzEscrowManagerIntegrity.sol)
Invariants: [`test/fuzzing/properties/Properties_ESCROW.sol`](../../test/fuzzing/properties/Properties_ESCROW.sol)
Descriptions: [`test/fuzzing/properties/PropertiesDescriptions.sol`](../../test/fuzzing/properties/PropertiesDescriptions.sol)

## Scope

Direct exercise of [`EscrowManager`](../marketplace/EscrowManager.md) deposits, withdrawals, claims, module authorization, direct surplus funding, and surplus recovery — bypassing the `Marketplace` offer flow. The harness registers a dedicated test module (`FUZZ_ESCROW_TEST_MODULE` at `0xC0000`) under its own module type and routes authorized actions through it, so this vertical is isolated from the `Marketplace` / `OrderbookMarketplace` wirings.

## Handlers

| Entrypoint | Caller | Target | Purpose |
|---|---|---|---|
| `fuzz_createEscrow` | `FUZZ_ESCROW_TEST_MODULE` | `escrowManager.createEscrow` | Authorized deposit path |
| `fuzz_createEscrowUnauthorized` | `FUZZ_ESCROW_UNAUTH_CALLER` (`0xD0000`) | `escrowManager.createEscrow` | Authorization boundary |
| `fuzz_withdraw` | `FUZZ_ESCROW_TEST_MODULE` | `escrowManager.withdraw` | Return tokens to depositor |
| `fuzz_claim` | `FUZZ_ESCROW_TEST_MODULE` | `escrowManager.claim` | Transfer escrow to beneficiary |
| `fuzz_directTransferToEscrow` | tracked user (`USER1..3`) | `token.transfer` | Exercise the protected-receiver guard for direct bond-token pushes into `EscrowManager` |
| `fuzz_multiStandardEscrowSurface` | `FUZZ_ESCROW_TEST_MODULE` | `createEscrow`, `escrows`, `supportsInterface`, `withdraw` | Exercise ERC20, ERC721, and ERC1155 escrow transfer branches with fuzz-only mocks |
| `fuzz_sweep` | harness admin (`address(this)`) | `escrowManager.sweep` | Recover untracked surplus |
| `fuzz_registerModule` | harness admin | `escrowManager.registerModule` | Register a candidate module address |
| `fuzz_deactivateModule` | harness admin | `escrowManager.deactivateModule` | Deactivate a registered module |

`FUZZ_ESCROW_TEST_MODULE` and `FUZZ_ESCROW_UNAUTH_CALLER` are intentionally kept out of the engine sender sets (`0x10000`, `0x20000`, `0x30000`) so the fuzzer cannot impersonate them — authorized calls only reach the EscrowManager through the handler-controlled prank.

## Invariants

### `createEscrow` — group 20

Checked in `createEscrowPostconditions` for `fuzz_createEscrow`.

| ID | Condition | Checked |
|---|---|---|
| ESCR-20 | `createEscrow` stores depositor, tokenAddress, tokenId, amount, asset type (`ERC6909`) and module type correctly | on success |
| ESCR-21 | `nextEscrowId` increments by exactly 1 | on success |
| ESCR-22 | `EscrowManager` bond balance grows by `amount` | on success |
| ESCR-23 | Depositor bond balance shrinks by `amount` | on success |
| ESCR-24 | `escrowReserved` grows by `amount` | on success |
| ESCR-25 | No unexpected reverts (`allowedErrors` is empty) | on revert |

### Multi-standard and residual coverage — group 70

Checked by the multi-standard escrow surface and the Orderbook residual coverage handler.

| ID | Condition |
|---|---|
| ESCR-70 | ERC20/ERC721/ERC1155 approval, create, getter/interface, and withdraw coverage calls do not unexpectedly revert |
| ESCR-71 | ERC721 `balanceHeld` coverage reports one for the minted escrow-held token |
| ESCR-72 | Invalid asset-type residual coverage reverts with the expected selector |

### `createEscrow` — authorization boundary

Checked in `createEscrowUnauthorizedPostconditions` for `fuzz_createEscrowUnauthorized`.

| ID | Condition |
|---|---|
| ESCR-26 | The call must revert with `EscrowManager__ModuleNotRegistered(address)` or `EscrowManager__ModuleNotAuthorized(address,bytes32)` — any other outcome is a bug |

### `withdraw` — group 30

Checked in `withdrawEscrowPostconditions` for `fuzz_withdraw`.

| ID | Condition | Checked |
|---|---|---|
| ESCR-30 | `escrow.amount` shrinks by the withdrawn amount | on success |
| ESCR-31 | Depositor bond balance grows by the withdrawn amount | on success |
| ESCR-32 | `EscrowManager` bond balance shrinks by the withdrawn amount | on success |
| ESCR-33 | No unexpected reverts | on revert |

### `claim` — group 40

Checked in `claimEscrowPostconditions` for `fuzz_claim`.

| ID | Condition | Checked |
|---|---|---|
| ESCR-40 | `escrow.amount` shrinks by the claimed amount | on success |
| ESCR-41 | Beneficiary bond balance grows by the claimed amount | on success |
| ESCR-42 | `EscrowManager` bond balance shrinks by the claimed amount | on success |
| ESCR-43 | No unexpected reverts | on revert |

### `sweep` — group 50

Checked in `sweepPostconditions` for `fuzz_sweep`.

| ID | Condition | Checked |
|---|---|---|
| ESCR-50 | `trackedEscrowAmountSum` is preserved — sweep must not touch reserved escrows | on success |
| ESCR-51 | `escrowBalance >= escrowReserved` is preserved | on success |
| ESCR-52 | No unexpected reverts | on revert |

### `directTransferToEscrow` — group 53

Checked in `directTransferToEscrowPostconditions` for `fuzz_directTransferToEscrow`.

This action exercises the direct-push path into protected `EscrowManager`. If a deployment or test setup leaves the receiver unprotected, a successful transfer creates sweepable surplus; in the protected default setup the expected revert is `Token__ProtectedReceiverTransferNotAllowed`.

| ID | Condition | Checked |
|---|---|---|
| ESCR-53 | Sender bond balance shrinks by the transferred amount | on success |
| ESCR-54 | `EscrowManager` bond balance grows by the transferred amount | on success |
| ESCR-55 | `trackedEscrowAmountSum` is preserved | on success |
| ESCR-56 | `escrowReserved` is preserved | on success |
| ESCR-57 | `escrowSweepable` grows by the transferred amount | on success |
| ESCR-58 | Only the protected-receiver push-transfer guard is an expected revert | on revert |

### Multi-standard escrow surface

`fuzz_multiStandardEscrowSurface` deploys and configures fuzz-only ERC20, ERC721, and ERC1155 tokens in setup, then creates and fully withdraws one synthetic escrow through the authorized test module. These escrows are not added to the tracked ERC6909 escrow buckets, because their purpose is branch coverage for transfer-standard handling, `escrows(id)`, and `supportsInterface` rather than bond-token accounting invariants.

### Global invariants — group 60

These run after any successful action via `onSuccessInvariantsGeneral` and are also checked from module-lifecycle postconditions.

| ID | Condition | Checked |
|---|---|---|
| ESCR-01 | `EscrowManager` bond balance equals `trackedEscrowAmountSum + escrowSweepable` | after any success |
| ESCR-60 | `escrowBalance >= escrowReserved` must hold at all times | after any success |
| ESCR-61 | `registerModule` and `deactivateModule` do not mutate `trackedEscrowAmountSum`, `escrowBalance`, or `escrowReserved` | on success of lifecycle ops |
| ESCR-62 | After `deactivateModule`, the module address is no longer authorized and its `moduleTypeOf` entry is cleared | on success of `fuzz_deactivateModule` |
| ESCR-63 | `registerModule` does not unexpectedly revert | on revert |
| ESCR-64 | `deactivateModule` only reverts with `ModuleHasActiveEscrows` after handler preconditions | on revert |

## Preconditions

Summary of the clamping and state-selection logic applied before each handler issues a protocol call. Full implementation in [`helper/preconditions/PreconditionsEscrowManager.sol`](../../test/fuzzing/helper/preconditions/PreconditionsEscrowManager.sol).

| Handler | Clamp rules |
|---|---|
| `createEscrow` / `createEscrowUnauthorized` | Token must not be paused. Depositor picked from tracked users with `balance > frozenBalance` and `isOperator(user, escrowManager) == true`; amount clamped to `[1, freeBalance]` where `freeBalance = balance - frozenBalance`. Unauthorized variant reuses the same param shape so the only distinguishing factor is the prank target. |
| `withdraw` | Token must not be paused. Escrow picked from `EscrowBucket.FuzzTestFunded` (filtered by `moduleType == FUZZ_ESCROW_TEST_MODULE_TYPE` and `amount > 0`). Amount clamped to `[1, escrow.amount]`. |
| `claim` | Token must not be paused. Same escrow-bucket rule as `withdraw`. Amount clamped to `[1, escrow.amount]`. Beneficiary picked uniformly from tracked users. |
| `directTransferToEscrow` | Token must not be paused. Sender picked from tracked users with `balance > frozenBalance`; amount clamped to `[1, freeBalance]`. Unlike `createEscrow`, this is a direct push transfer; protected `EscrowManager` is expected to reject it. |
| `multiStandardEscrowSurface` | Picks ERC20, ERC721, or ERC1155 from the fuzz-only mock set. Mints enough test inventory to the selected depositor, approves `EscrowManager`, creates one authorized escrow, checks getter/interface surfaces, then withdraws the full synthetic amount. |
| `sweep` | Token must not be paused. Requires non-zero `getSweepableAmount(ERC6909, token, bondTokenId)`. Amount clamped to `[1, surplus]`. Beneficiary picked uniformly from tracked users. |
| `registerModule` | Candidate picked from tracked users; requires `moduleTypeOf(candidate) == bytes32(0)` so an already-registered address cannot be re-registered. |
| `deactivateModule` | Scans tracked users in rotation from the seed and picks the first one where `moduleTypeOf(user) == FUZZ_ESCROW_TEST_MODULE_TYPE`. Core modules (`MARKETPLACE_MODULE`, `ORDERBOOK_MARKETPLACE_MODULE`) and `FUZZ_ESCROW_TEST_MODULE` itself are never reachable from this handler. |

All clamp failures raise `ClampFail(string)`, which the integrity layer accepts as a legitimate "skip this tick" outcome rather than a bug.
