# BondMarketFilter Fuzz Coverage

## Status

[`BondMarketFilter`](../marketplace/BondMarketFilter.md) is exercised through the directed
[`OrderbookMarketplace`](OrderbookMarketplace.md) fuzz vertical.

The harness calls `BondMarketFilter.matchesFilter` directly against fuzz-configured bond metadata and also reaches
the integrated `placeBatchOrder` path through `HandlerOrderbookMarketplace`. `DeussBondMetadataAdapter` itself does
not currently have dedicated fuzz coverage; the directed filter checks use a fuzz metadata adapter.

Invariants: [`test/fuzzing/properties/Properties_BMF.sol`](../../test/fuzzing/properties/Properties_BMF.sol)
(`BMF-10`, `BMF-20`, `BMF-30`).

## Directed Coverage

- Adapter set/get wiring
- ABI encoding of empty and populated `BondFilter` payloads
- Maturity, denomination, coupon-rate, coupon-type, currency, and issuer filter clauses
- Whitelist and blacklist hit/miss branches
- Missing adapter and missing token behavior
- Invalid maturity, coupon-rate, and denomination range reverts
- Integrated `placeBatchOrder` filter matching through the Orderbook directed surface

## Directed Properties

| ID | Condition |
|---|---|
| BMF-10 | Adapter set/get wiring stores the expected adapter |
| BMF-20 | Directed `matchesFilter` hit/miss cases match the harness expectation |
| BMF-30 | Invalid maturity, coupon-rate, and denomination ranges revert with `InvalidFilterRange` |

## Protocol Logic Not Covered Here

- Adapter revert handling in `matchesFilter`
- `DeussBondMetadataAdapter.getBond` token-address check against `BondRegistry.getToken()`
- `DeussBondMetadataAdapter.getCurrentCouponRate` passthrough to `BondRegistry.getCurrentCouponRateForBond`

## Protocol Risks to Target If Added

- Batch orders matching markets that should be filtered out
- Batch orders skipping markets that should match
- Reverts from unknown tokens breaking the whole batch path instead of returning `false`
- Current coupon rate filters using stale or incorrect rate checkpoints
- Incorrect handling of empty whitelist/blacklist arrays

## Suggested Harness Shape

- Extend the existing Orderbook directed surface with a mock reverting adapter.
- Add adapter-specific checks against `DeussBondMetadataAdapter` and known published/issued bonds.
- Properties should distinguish caller bugs that should revert, such as invalid ABI or inverted ranges, from non-matching candidate markets that should return `false`.

TODO: Decide whether deeper filter coverage should remain inside `FuzzOrderbookMarketplaceIntegrity.sol` or move into a standalone `FuzzBondMarketFilterIntegrity.sol`.
