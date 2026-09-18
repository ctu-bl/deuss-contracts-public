# OrderbookMarketplace Fuzz Coverage

## Status

[`OrderbookMarketplace`](../marketplace/OrderbookMarketplace.md) has a directed fuzz vertical:
[`test/fuzzing/FuzzOrderbookMarketplaceIntegrity.sol`](../../test/fuzzing/FuzzOrderbookMarketplaceIntegrity.sol).

The vertical uses [`HandlerOrderbookMarketplace.sol`](../../test/fuzzing/helper/handlers/HandlerOrderbookMarketplace.sol)
to execute compact public-flow and defensive-branch coverage for `OrderbookMarketplace`, `BondMarketFilter`,
and a few residual Marketplace/EscrowManager branches. It is composed into the default `Fuzz` target.

Directed assertions are property-backed through [`Properties_ORDERBOOK.sol`](../../test/fuzzing/properties/Properties_ORDERBOOK.sol)
(`OB-10` .. `OB-14`) and [`Properties_BMF.sol`](../../test/fuzzing/properties/Properties_BMF.sol)
(`BMF-10`, `BMF-20`, `BMF-30`). Residual Marketplace and EscrowManager defensive branches use `MKT-82`
and `ESCR-71`/`ESCR-72`.

The deployed setup mirrors the production timing constants from `DeployConstants.sol`: 3-day payment expiry, 30-minute minimum non-zero order expiry, and 3-day dispute buffer.

This is not yet a full stateful orderbook invariant harness. It does not maintain order, trade, market, TWAP, or
order-linked escrow buckets in `FuzzStateIndex`. The current OB/BMF properties assert directed coverage outcomes;
they do not yet prove stateful order/trade accounting.

## Protocol Logic Not Covered Here

## Directed Coverage

Entrypoints:

| Entrypoint | Target surface |
|---|---|
| `fuzz_bondMarketFilterSurface` | Adapter wiring, empty and ranged filters, whitelist/blacklist filters, coupon filters, missing adapter/token behavior, and invalid range reverts |
| `fuzz_orderbookMarketplaceSurface` | Admin setters/views, order placement, cancellation, and delegation |
| `fuzz_orderbookMarketplaceTradeSurface` | Matching, trade payment, unpaid/dispute/settlement, TWAP observations, and trade-linked views |
| `fuzz_orderbookMarketplaceFreezeSeizureSurface` | Frozen order/trade handling and governed order/trade seizure |
| `fuzz_orderbookMarketplaceBatchSurface` | Batch order matching, skipped candidate markets, and active sell market views |
| `fuzz_orderbookMarketplaceOpenBookViewSurface` | Open-book view behavior across active, frozen, cancelled, and separate-market orders |
| `fuzz_orderbookMarketplaceInternalValidationSurface` | Isolated internal validation, trader-filter, order-creation, and TWAP observation branches |
| `fuzz_orderbookMarketplaceInternalMatchBuySurface` | Isolated internal buy-order matching break and skip branches |
| `fuzz_orderbookMarketplaceInternalMatchSellSurface` | Isolated internal sell-order matching break and skip branches |
| `fuzz_orderbookMarketplaceInternalResidualAndBatchSurface` | Isolated residual matching, batch-market, and filter-skip branches |
| `fuzz_marketplaceEscrowResidualSurface` | Residual defensive branches in Marketplace and EscrowManager coverage harnesses |

## Directed Properties

| ID | Condition |
|---|---|
| OB-10 | Admin-set address wiring on `OrderbookMarketplace` matches the expected configured contracts |
| OB-11 | Admin-set numeric configuration and `MAX_RECENT_OBSERVATIONS` match the expected values |
| OB-12 | Directed delegate mutator calls do not unexpectedly revert |
| OB-13 | Directed Orderbook revert cases return the expected selector |
| OB-14 | Isolated internal coverage surfaces do not unexpectedly revert |
| BMF-10 | `setAdapter` stores the expected metadata adapter |
| BMF-20 | `matchesFilter` returns the expected directed predicate result |
| BMF-30 | Invalid filter ranges revert with the expected selector |

## Remaining Gaps

The meaningful orderbook flows below have directed execution coverage but do not yet have stateful invariant
properties over tracked order/trade snapshots:

- Escrow accounting for partially matched sell orders and settled trades
- Buyer/seller authorization through enabled entity accounts and delegation
- Payment-deadline and dispute-buffer edge cases
- Frozen order/trade behavior blocking normal progression but allowing governed seizure
- Synthetic batch-buy order accounting, especially skipped candidate markets
- TWAP accumulator correctness across multiple trades and timestamps
- Active sell market cap and per-market price-time priority behavior

## Suggested Full Invariant Harness Shape

- Add order, trade, and market buckets to `FuzzStateIndex`
- Add snapshots for orders, trades, TWAP observations, and escrow links
- Add properties for order amount conservation, escrow conservation, trade lifecycle status, authorization, and TWAP bounds

TODO: Decide whether orderbook fuzzing should reuse the existing real ERC-6909 bond token and AssetManager setup or use a separate token pool to keep `Marketplace` state independent.
