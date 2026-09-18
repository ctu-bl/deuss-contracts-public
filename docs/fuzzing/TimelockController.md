# TimelockController Fuzz Coverage

Vertical entrypoint: [`test/fuzzing/FuzzTLIntegrity.sol`](../../test/fuzzing/FuzzTLIntegrity.sol)
Invariants: [`test/fuzzing/properties/Properties_TL.sol`](../../test/fuzzing/properties/Properties_TL.sol)
Postconditions: [`test/fuzzing/helper/postconditions/PostconditionsTL.sol`](../../test/fuzzing/helper/postconditions/PostconditionsTL.sol)
Descriptions: [`test/fuzzing/properties/PropertiesDescriptions.sol`](../../test/fuzzing/properties/PropertiesDescriptions.sol)

## Scope

Direct exercise of the governance `TimelockController` operation lifecycle: delay enforcement on schedule (G-15), execution gating (G-16), monotonic replay-free state transitions (I-8), and the done-anchor timestamp bound (E-1). The harness (`address(this)`) holds `PROPOSER_ROLE`, `EXECUTOR_ROLE`, and `CANCELLER_ROLE` (granted in setup), so role-gated calls are driven from a real role holder. `updateDelay` can only be called by the timelock itself, so it is routed through `address(timelock)` as the caller.

Operations are tracked once successfully scheduled (id, target, value, data, predecessor, salt, schedule timestamp, and the `minDelay` captured at schedule time) so the execute and cancel handlers can target real ops or random unscheduled ids. The fuzzer engine advances `block.timestamp` between calls, so tracked Waiting ops naturally mature into Ready over the campaign without an explicit time-forcing handler.

Legitimate `TimelockController` reverts on invalid-state operations are CORRECT behavior and are tolerated via `_allowTLRevert` (insufficient delay, unexpected operation state, unexecuted predecessor, unauthorized caller, invalid operation length, access-control rejection, and the harness `FailedCall()` artifact of the benign scheduled no-op). Only a SUCCESS on an invalid op falsifies, and that is caught on the success path. All invariants in this vertical are **passing** in the consistency campaign.

## Handlers

| Entrypoint | Caller | Target | Purpose |
|---|---|---|---|
| `fuzz_scheduleTL` | harness (`address(this)`, PROPOSER) | `timelock.schedule(target,value,data,predecessor,salt,delay)` | Schedule a single-call op (mix of valid and too-small delays, optional predecessor chaining); G-15 on success |
| `fuzz_executeTL` | harness (`address(this)`, EXECUTOR) | `timelock.execute(target,value,data,predecessor,salt)` | Execute a tracked or random op; enforces G-16, I-8 Ready→Done, and E-1 on success |
| `fuzz_cancelTL` | harness (`address(this)`, CANCELLER) | `timelock.cancel(opId)` | Cancel a tracked or random op; enforces I-8 no-Done-regression on success |
| `fuzz_updateDelayTL` | `address(timelock)` (self-call) | `timelock.updateDelay(newDelay)` | Update the minimum delay; only the timelock itself is authorized |

## Invariants

### `scheduleTL` — delay enforcement (G-15, I-8)

Checked in `scheduleTLPostconditions` for `fuzz_scheduleTL`.

| ID | Condition | Checked |
|---|---|---|
| TL-G15 (G-15) | The delay actually used to schedule is `>= getMinDelay()` at schedule time | on success |
| TL-I8 (I-8) | A freshly scheduled op does not regress an already-Done op (no Done → other) | on success |
| TL allowed-revert | Insufficient delay / op already exists / missing PROPOSER role revert correctly | on revert |

### `executeTL` — execution gating & lifecycle (G-16, I-8, E-1)

Checked in `executeTLPostconditions` for `fuzz_executeTL`.

| ID | Condition | Checked |
|---|---|---|
| TL-G16 (G-16) | A successful execute had the op Ready AND its predecessor Done (captured in the BEFORE snapshot) | on success |
| TL-I8 (I-8) | Execution moves the op Ready → Done; an unscheduled/non-ready op cannot reach the success path | on success |
| TL-E1 (E-1) | The op's effective (done-anchor) timestamp is never earlier than `scheduleTime + minDelayAtSchedule` (no privileged op effective early) | on success (when scheduleTime tracked) |
| TL-I8 (I-8) | If the op was not Ready before the call, the execute must NOT have succeeded (no replay / no Unset execution) | on revert |
| TL allowed-revert | Not-ready / unscheduled / predecessor-pending reverts are correct behavior | on revert |

### `cancelTL` — replay-free lifecycle (I-8)

Checked in `cancelTLPostconditions` for `fuzz_cancelTL`.

| ID | Condition | Checked |
|---|---|---|
| TL-I8 (I-8) | Cancellation never resurrects or regresses a previously-Done op | on success |
| TL allowed-revert | Cancelling an unscheduled/Done op reverts with the expected state error | on revert |

### `updateDelayTL` — self-authorized delay update

Checked in `updateDelayTLPostconditions` for `fuzz_updateDelayTL`.

| ID | Condition | Checked |
|---|---|---|
| TL-UPDATE-DELAY | On success, `getMinDelay()` equals the requested new delay | on success |
| TL allowed-revert | A non-self caller reverts with `TimelockUnauthorizedCaller` | on revert |
