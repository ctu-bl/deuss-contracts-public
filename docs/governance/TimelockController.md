# TimelockController

## Overview

`TimelockController` is a thin upgradeable wrapper around OpenZeppelin's
`TimelockControllerUpgradeable`. It enforces a mandatory delay between when an
operation is *scheduled* and when it can be *executed*, providing a governance
safety window for all privileged protocol actions (role grants, beacon upgrades,
parameter changes).

The implementation contract disables its own initializers, so only the
BeaconProxy deployed by `TimelockControllerDeployer` can be initialized.

## Deployment

The contract is deployed via `TimelockControllerDeployer` using deterministic
CREATE2 addresses (salt: `governanceTimelockSalt`). Three contracts are created:

| Contract | Description |
|---|---|
| `TimelockController` (impl) | Logic contract — initializers disabled |
| `UpgradeableBeacon` | Beacon pointing to the impl |
| `BeaconProxy` | The live proxy; this is the address used everywhere |

The beacon's ownership is transferred to the proxy itself on deployment, so
future upgrades must go through the timelock.

## Roles

| Role | Constant | Description |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | `bytes32(0)` | Can grant/revoke all roles without delay. Set to the TimelockController proxy itself and `timelockControllerAdmin` at init. |
| `PROPOSER_ROLE` | `keccak256("PROPOSER_ROLE")` | Can schedule operations. Granted to `timelockControllerActor` during bootstrap. |
| `EXECUTOR_ROLE` | `keccak256("EXECUTOR_ROLE")` | Can execute ready operations. Granted to `timelockControllerActor` during bootstrap. |
| `CANCELLER_ROLE` | `keccak256("CANCELLER_ROLE")` | Can cancel pending operations. Granted to `timelockControllerActor` during bootstrap. |

OpenZeppelin 5.x does not use a separate `TIMELOCK_ADMIN_ROLE` constant. Granting `keccak256("TIMELOCK_ADMIN_ROLE")` creates an unused role and does not provide timelock admin authority.

Bootstrap grants `PROPOSER_ROLE`, `EXECUTOR_ROLE`, and `CANCELLER_ROLE` to `timelockControllerActor`
using the `timelockControllerAdminKey`.

## Minimum delay

| Context | Value |
|---|---|
| Production default | `1 days` (`TIMELOCK_CONTROLLER_MIN_DELAY`) |
| Override (testnet / Anvil) | `TIMELOCK_MIN_DELAY` env variable |

Setting `TIMELOCK_MIN_DELAY=0` allows `schedule` and `execute` to be called in
the same transaction, which is useful for testnet deployments and local testing.

```sh
# Testnet — no waiting
TIMELOCK_MIN_DELAY=0 forge script ...

# Production — uses the 1-day default (env var absent)
forge script ...
```

## Operation lifecycle

```
schedule(target, value, data, predecessor, salt, delay)
    │
    │  wait ≥ minDelay
    ▼
execute(target, value, data, predecessor, salt)
```

An operation id is computed as:
```
id = keccak256(abi.encode(target, value, data, predecessor, salt))
```

A `predecessor` of `bytes32(0)` means the operation has no dependency.

## Granting protocol roles

There are no standalone `script/setRoles/` helpers in the current repository. Bootstrap grants the default operational roles during `BootstrapProtocol.s.sol`. Later role changes should be scheduled and executed by the timelock against the target contract's owner-gated role function, usually `grantRoles(address,uint256)` or `grantRoles(address[],uint256)`.

For a delayed timelock, operators should:

1. ABI-encode the target contract call, for example `grantRoles(address,uint256)`.
2. `schedule(target, 0, data, predecessor, salt, minDelay)` through the timelock proposer.
3. Wait until the operation is ready.
4. `execute(target, 0, data, predecessor, salt)` through the timelock executor.

When `TIMELOCK_MIN_DELAY=0`, schedule and execute can occur in the same operational window, but they are still separate timelock calls unless a dedicated helper script is introduced later.

## Upgrading the implementation

Because the beacon is owned by the TimelockController proxy itself, upgrades
must be scheduled and executed through it:

```sh
# Schedule upgrade
cast send <TIMELOCK_ADDRESS> \
  "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
  <BEACON_ADDRESS> 0 \
  $(cast calldata "upgradeTo(address)" <NEW_IMPL>) \
  0x0 <SALT> <MIN_DELAY> \
  --private-key <PROPOSER_KEY>

# Execute after delay
cast send <TIMELOCK_ADDRESS> \
  "execute(address,uint256,bytes,bytes32,bytes32)" \
  <BEACON_ADDRESS> 0 \
  $(cast calldata "upgradeTo(address)" <NEW_IMPL>) \
  0x0 <SALT> \
  --private-key <EXECUTOR_KEY>
```
