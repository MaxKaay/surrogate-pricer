# Interfaces v1: guide for the frontend

**Frozen 2026-09-29.** The Solidity interfaces in
[`contracts/src/interfaces/`](../contracts/src/interfaces/) are the contract between
the contracts and the frontend. ABIs for viem/wagmi are in [`abi/`](../abi/)
(regenerate with `contracts/script/export-abi.sh`). Any change goes through a PR that
updates the interface, the ABI and this file together. Layer picture:
[architecture.md](architecture.md).

## Status

| Contract | Interface | Implementation |
|---|---|---|
| SurrogatePricer (Stylus) | `ISurrogatePricer` | done (`stylus/pricer-model`, synthetic weights) |
| FixingsRecorder | `IFixingsRecorder` | done, implements the interface |
| SeriesFactory, NoteSeries, SeriesToken | `ISeriesFactory`, `INoteSeries`, `ISeriesToken` | next |
| NoteQuoter | `INoteQuoter` | legacy terms-based version exists; rework to series-based |
| Desk | `IDesk` (ERC-4626) | after the core |

Robinhood Chain testnet: chain ID 46630, RPC `https://rpc.testnet.chain.robinhood.com`,
USDG `0x7E955252E15c84f5768B83c41a71F9eba181802F` (6 decimals). Deployed addresses will be
listed here.

## Units

| Quantity | Unit |
|---|---|
| NOTE, WRITER, USDG amounts | base units, 6 decimals. 1 NOTE = 1 USDG notional |
| `priceBps`, `feeBps`, barriers, coupon | bps: of notional (price, fee, coupon) or of the initial fixing (barriers) |
| `payoutPerNote`, `maxPayoutPerNote` | USDG base units per 1 NOTE (1e6 base units) |
| feed prices, `initialFixing`, fixings | feed decimals (8) |
| times | unix seconds (`uint40`) |
| `volBpsAnnual` | annualized implied vol in bps (e.g. 5000 = 50%) |

## Screens and the calls behind them

**Market list.** `desk.listedSeries()` → for each series:
`desk.listing(s)` (vol, cap, sold), `series.terms()`, `series.state()`,
`quoter.notePriceBps(s, listing.volBpsAnnual)`. When a quote reverts, show why (see Errors)
rather than hiding the series.

**Note detail.** Everything from the market list, plus:
- `quoter.inputs(s, vol)`: exactly what the model saw. Showing it is the transparency pitch.
- `series.pendingObservation()`.
- Fixing history: `FixingRecorded` events on `series.recorder()`, and `ObservationProcessed` on the series.
- `weightsHash`: from `notePriceBps`, or from `NoteBought` for past trades.

**Buy NOTE.**
1. `desk.quoteBuy(s, amount, feeBps)` → `(cost, priceBps)`.
2. `USDG.approve(desk, maxCost)` with `maxCost = cost + slippage`.
3. `desk.buy(s, amount, maxCost, feeBps, feeReceiver, to)`.

`feeBps`/`feeReceiver` are the integrator fee: our frontend can charge one (≤ `MAX_FEE_BPS`) or pass 0.

**Sell NOTE (early exit).** `desk.quoteSell` → `NOTE.approve(desk, amount)` → `desk.sell(..., minProceeds, ...)`.

**Redeem after settlement.**
- If `state().phase == Settled`: `series.redeem(noteAmount, writerAmount, to)`. No approval
  needed; it burns the caller's tokens. `previewRedeem` gives the amount.
- If the phase is still Live but maturity or an autocall fixing has passed: call
  `series.advance()` first (anyone can), or just call `redeem`, which advances internally.

**Hedger: mint a pair.** `USDG.approve(series, previewMint(n))` → `series.mint(n, to)`.
You get `n` NOTE and `n` WRITER. Sell the NOTE to the Desk or keep it.
`series.redeemPair(n, to)` unwinds the pair at any time.

**LP.** Standard ERC-4626 on the Desk: `deposit`/`withdraw`/`redeem`. Check
`maxDeposit`/`maxWithdraw` first: they return 0 while any held series can't be quoted
(weekends, pending fixing). Say so in the UI; don't let the transaction revert.

**Keeper (anyone, could be a button).** For each observation time that has passed:
find the round (binary search over `feed.getRoundData`: the last round at or before
`obsTime`) → `recorder.recordFixing(obsTime, roundId)` → `series.advance()`.

## Events to index

| Contract | Event | Use |
|---|---|---|
| Factory | `SeriesCreated(seriesId, feed, series, note, writer, terms)` | series list |
| Recorder | `FixingRecorded(obsTime, roundId, price, timestamp)` | price path chart |
| Series | `Struck`, `ObservationProcessed`, `Settled` | lifecycle timeline |
| Series | `Minted`, `PairRedeemed`, `Redeemed` | positions |
| Desk | `NoteBought`, `NoteSold` (carry `priceBps`, `feeBps`, `weightsHash`) | trade history, "which model priced this" |
| Desk | `SeriesListed`, `SeriesDelisted`, ERC-4626 `Deposit`/`Withdraw` | admin + LP views |

## Errors worth a human message

When decoding, merge the ABIs: the Desk bubbles up errors from the quoter and the
pricer, so include `INoteQuoter` and `ISurrogatePricer` errors.

| Error | Show |
|---|---|
| `FeedStale(updatedAt)` | "Market closed: quotes resume when the feed updates" (weekends) |
| `FixingPending(obsTime)` | "Observation at … awaiting its fixing": offer the keeper button |
| `TooCloseToObservation(obsTime)` | "Trading pauses shortly before each observation" |
| `OutOfRange(field, value)` | "Outside the model's certified range (field …)": the model refuses rather than guesses |
| `NotLive()` | not struck yet, or already settled |
| `CapExceeded`, `Slippage`, `FeeTooHigh` | self-explanatory |

## What is deliberately not here

No demo flags in production contracts: the demo uses staged feed history on the mock
feed. No NOTE collateral oracle yet (roadmap). No router or permit yet: plain approve + call.
