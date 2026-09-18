# BondMarketFilter Contract Documentation

## Overview
`BondMarketFilter` is the DEUSS-Bond implementation of `IMarketFilter`, the pluggable resolver interface consumed by `OrderbookMarketplace.placeBatchOrder()`. It evaluates caller-supplied `BondFilter` payloads against bond metadata fetched through per-token `IBondMetadataAdapter` adapters. This indirection keeps the marketplace token-agnostic and lets new bond issuers with heterogeneous metadata sources be added by registering a new adapter — without touching the orderbook.

## Prerequisites
- Contract must be initialized with an owner
- `ADMIN` role must be granted to accounts authorized to register or clear metadata adapters
- For each token that should be batch-filterable, an `IBondMetadataAdapter` must be registered via `setAdapter(token, adapter)`
- Tokens with no adapter silently evaluate to `matchesFilter == false`, so the marketplace skips them without reverting

## Contract Architecture
- Inherits from `OwnableRolesExtension` for role-based access control
- Inherits from `Initializable` for proxy initialization
- Implements `IMarketFilter`
- Stores a `mapping(address token => IBondMetadataAdapter)` — global (not keyed by orderbook); the same resolver instance can be shared across multiple marketplaces
- Deployed behind an `UpgradeableBeacon` proxy via `BondMarketFilterDeployer`

## Core Functions

### matchesFilter(address token, uint256 tokenId, bytes calldata filterData) → bool

Implements `IMarketFilter.matchesFilter`. Called by `OrderbookMarketplace` for every candidate market during `placeBatchOrder`.

**Behavior:**
1. Looks up the adapter for `token`. If no adapter is configured, returns `false`
2. ABI-decodes `filterData` into `BondFilter`. Invalid ABI causes a revert (caller bug, fail loud)
3. Validates filter ranges — reverts with `BondMarketFilter__InvalidFilterRange` on any inverted bounded range (`maturityFrom > maturityTo`, `bondNominalValueFrom > bondNominalValueTo`, or `couponRateFrom > couponRateTo` with non-zero upper bound)
4. Calls `adapter.getBond(token, tokenId)` inside a `try/catch`; any adapter revert yields `false` (allows mixed-asset markets without breaking batch orders)
5. Rejects bonds not in `BondStatus.Issued`
6. Evaluates each clause: maturity range, bondNominalValue range, currency whitelist/blacklist, issuer whitelist/blacklist, coupon type, coupon rate range (the last one fetches the current rate through `adapter.getCurrentCouponRate(bond)` only when at least one of the range bounds is non-zero)

**Returns:** `true` if the bond passes every clause, `false` otherwise. Reverts only on explicit caller bugs (bad ABI, inverted ranges).

### setAdapter(address token, address adapter)

Registers or clears the metadata adapter for a token. Passing `address(0)` disables bond filtering for that token — subsequent `matchesFilter` calls return `false` for this token.

**Prerequisites:**
- Caller must have `ADMIN` role
- `token` must be non-zero

**Events:**
- `AdapterSet(token, adapter)`: Always emitted

**Errors:**
- `Unauthorized()`: When caller does not have `ADMIN` role
- `ZeroAddress()`: When `token` is the zero address

### adapter(address token) → address

Returns the currently registered adapter for a token (`address(0)` if none).

### encodeFilter(BondFilter calldata filter) → bytes

Convenience `pure` helper that returns `abi.encode(filter)` — useful for Solidity tests and deployment scripts that want to build `filterData` without hand-rolling the encoding.

## BondFilter struct

| Field | Type | Semantics |
|---|---|---|
| `maturityFrom` | `uint256` | Inclusive lower bound on `bond.maturityDate` (0 = unbounded) |
| `maturityTo` | `uint256` | Inclusive upper bound on `bond.maturityDate` (0 = unbounded) |
| `currencyWhitelist` | `bytes3[]` | If non-empty, `bond.currency` must be in the list |
| `currencyBlacklist` | `bytes3[]` | If non-empty and `bond.currency` is in the list, reject |
| `couponRateFrom` | `uint256` | Inclusive lower bound on current coupon rate in basis points |
| `couponRateTo` | `uint256` | Inclusive upper bound on current coupon rate in basis points (0 = unbounded) |
| `couponRateTypes` | `CouponRateType[]` | If non-empty, `bond.couponRateType` must be in the list |
| `issuerWhitelist` | `address[]` | If non-empty, `bond.issuer` must be in the list |
| `issuerBlacklist` | `address[]` | If non-empty and `bond.issuer` is in the list, reject |
| `bondNominalValueFrom` | `uint256` | Inclusive lower bound on `bond.bondNominalValue` (0 = unbounded) |
| `bondNominalValueTo` | `uint256` | Inclusive upper bound on `bond.bondNominalValue` (0 = unbounded) |

Empty whitelist ⇒ permissive (all allowed). Empty blacklist ⇒ nothing rejected. Ranges use `0` as the sentinel for "no bound" on a given side.

## IBondMetadataAdapter

The adapter normalizes heterogeneous bond registries to the DEUSS `Bond` shape expected by `BondMarketFilter`:

```solidity
interface IBondMetadataAdapter {
    function getBond(address token, uint256 tokenId) external view returns (Bond memory bond);
    function getCurrentCouponRate(Bond calldata bond) external view returns (uint256 rate);
}
```

The reference implementation `DeussBondMetadataAdapter` wraps the current DEUSS `BondRegistry` and token registry. It verifies that the queried token is the registry's configured token, resolves metadata with `getBondByTokenId(tokenId)`, and resolves the live coupon rate with `getCurrentCouponRateForBond(bond)`. Third-party issuers implement their own adapters over their own registries and register them with `setAdapter`.

Adapters are expected to revert on unknown `(token, tokenId)` pairs. `BondMarketFilter` catches the revert and treats the market as non-matching — so mixing DEUSS bonds with other ERC-6909 tokens in the same orderbook is safe.

### DeussBondMetadataAdapter

`DeussBondMetadataAdapter` is the protocol adapter used for DEUSS-issued ERC-6909 bonds.

**Core functions:**
- `getBond(address token, uint256 tokenId)`: Requires `token == bondRegistry.getToken()` and returns `bondRegistry.getBondByTokenId(tokenId)`.
- `getCurrentCouponRate(Bond calldata bond)`: Returns `bondRegistry.getCurrentCouponRateForBond(bond)`.

**Trust assumptions:**
- The adapter trusts the configured `BondRegistry` as the source of truth for token address, bond metadata, and coupon-rate checkpoints.
- `BondMarketFilter` treats adapter reverts as non-matches, so adapter failures skip the candidate market rather than reverting the whole batch order.

## Deployment

`BondMarketFilterDeployer` deploys the implementation, `UpgradeableBeacon`, and `BeaconProxy` via CREATE2. The deployer initializes the proxy with the deployer address as the initial owner.

The bootstrap flow (`DeployProtocol.s.sol` + `BootstrapProtocol.s.sol`) additionally:
1. Grants `ADMIN` to the configured actor via `_setupBondMarketFilter`
2. Deploys `DeussBondMetadataAdapter(bondRegistry)`
3. Wires the DEUSS token via `setAdapter(token, deussAdapter)`
4. Wires the resolver into `OrderbookMarketplace` via the `marketFilter_` initialize argument (fed through `OrderbookMarketplaceDeployer`)
5. Transfers proxy and beacon ownership to the `TimelockController`

## Errors

- `BondMarketFilter__InvalidFilterRange()`: Any inverted bounded filter range (maturity / bondNominalValue / coupon-rate)
- `ZeroAddress()`: `setAdapter` called with zero `token`, or `initialize` called with zero owner

## Design Notes

- **Token-agnostic resolver**: the marketplace never sees `BondFilter` — it passes `bytes` through. Range validation and bond-status gating happen entirely inside the resolver
- **Opaque payload**: the decoded `BondFilter` is never stored; every `matchesFilter` call decodes fresh. This avoids storage for per-order filters
- **Try/catch on adapter**: non-bond tokens or unknown `tokenId`s never revert the batch order — they silently evaluate to `false`, letting the orderbook move on to the next market
- **Per-token adapters**: supporting multiple issuers with different metadata sources requires no marketplace change — just a new adapter and `setAdapter` call
