# Multicall3 Documentation

## Overview

`Multicall3` is a vendored utility contract for batching read and write calls into a single transaction or RPC call. It is deployed as a utility contract in the protocol deployment flow documented in [`deployment.md`](../deployment.md) and is compatible with the canonical Multicall/Multicall2/Multicall3 interfaces.

It does not own protocol state and does not define protocol roles.

## Core Functions

### aggregate(Call[] calldata calls)

Executes each call and reverts if any call fails. Returns the execution block number and raw return data.

### tryAggregate(bool requireSuccess, Call[] calldata calls)

Executes each call and returns `(success, returnData)` for every call. If `requireSuccess == true`, any failed call reverts the whole batch.

### tryBlockAndAggregate(bool requireSuccess, Call[] calldata calls)

Same as `tryAggregate`, with block number and block hash included in the return values.

### blockAndAggregate(Call[] calldata calls)

Same as `tryBlockAndAggregate(true, calls)`.

### aggregate3(Call3[] calldata calls)

Executes calls with per-call `allowFailure`. A failed call reverts the batch only when that call has `allowFailure == false`.

### aggregate3Value(Call3Value[] calldata calls)

Executes calls with per-call ETH value and per-call `allowFailure`.

**Important Notes:**
- The transaction `msg.value` must equal the exact sum of all per-call values.
- ETH is forwarded from `Multicall3` to each target call.

### Block and Chain Helpers

Provides helper views for block hash, block number, timestamp, coinbase, gas limit, base fee, chain ID, last block hash, and ETH balance.

## Trust and Integration Notes

- Calls are executed by `Multicall3`, so target contracts see `msg.sender == address(Multicall3)`, not the original externally owned account.
- Protocol functions that require the original caller, owner, or role holder generally should not be routed through `Multicall3` unless `Multicall3` itself is intentionally authorized.
- Return data is raw bytes. Off-chain callers are responsible for decoding it with the target ABI.
- Revert strings are kept compatible with upstream Multicall tooling.
