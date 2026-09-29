# Architecture

Four layers. Each one works on its own, every position is an ERC-20, and the
model is only called by the Desk when pricing a trade. Settlement never
touches the model. Interfaces: [`contracts/src/interfaces/`](../contracts/src/interfaces/),
frontend guide: [interfaces.md](interfaces.md). The lessons in brackets come from the
research on Opyn, Pendle, Gnosis CTF, Siren and Cega (2026-09-29).

```
  buyer          LP          hedger                frontend / other protocols
    │             │             │                        │
    ▼             ▼             ▼ (mints pairs directly)  ▼ (events + views)
┌─ L3  INTEGRATIONS ─ opt-in; all policy lives here ─────────────────────────────────────┐
│                                                                                        │
│ Desk  (ERC-4626: LPs deposit USDG, shares are an ERC-20)                               │
│   • buy / sell NOTE at quote ± fee  (the pricer's only in-path use)                    │
│   • quotes a curated grid only: 1 series / underlying / week                  [2]      │
│   • keeps WRITER by default; no promise of WRITER liquidity                   [8]      │
│   • caps per series + TVL, ε-bands at barriers, rounds vs trader              [9]      │
│   • fee ≤ maxFeeBps; a slice goes to the backstop                                      │
│   • IS the market: no AMM pools for NOTE                                      [6]      │
│                                                                                        │
│ NoteOracle  (roadmap)  AggregatorV3 price per NOTE for lenders                [5]      │
│ Router      (stretch)  permit + buy in one transaction                                 │
│                                                                                        │
└────────────────────────────────────────────────────────────────────────────────────────┘
        │ quote()                                                       │ mint · redeem
        ▼                                                               │
┌─ L2  QUOTER ─ view only ─────────────────────────────────────┐        │
│                                                              │        │
│ NoteQuoter                                                   │        │
│   • note state from series + recorder, never from caller     │        │
│   • stale feed / out-of-range input → revert                 │        │
│   • fee is a call parameter, emitted in NoteQuoted           │        │
│   calls: SurrogatePricer, FixingsRecorder, feed              │        │
│                                                              │        │
└──────────────────────────────────────────────────────────────┘        │
══ MODEL BOUNDARY: nothing below calls the pricer ══════════════════════╪═════════════════
                                                                        ▼
┌─ L1  CORE ─ no model · no admin · no pause · no upgrade ───────────────────────────────┐
│                                                                                        │
│ NoteFactory.createSeries(terms, strikeTime)                                            │
│   • CREATE2 address = f(termsHash): same terms → same series                  [2]      │
│   • only factory clones may mint / burn (provenance check)                    [1]      │
│                                                                                        │
│ Series k ─ its own USDG escrow; claims ≤ own collateral                       [1]      │
│   • opens once the strike fixing is recorded                                  [2]      │
│   • mint n       lock n × maxPayout → n NOTE + n WRITER                                │
│   • redeemPair   burn both → collateral back, any time                                 │
│   • settle()     once; stores payoutPerUnit; moves no tokens                  [3][4]   │
│   • redeem(to)   pull; NOTE rounds down, WRITER = max − NOTE                  [3][4]   │
│   • mint after settle reverts; burn first; nonReentrant                       [3]      │
│   calls: FixingsRecorder, AutocallPayout                                               │
│                                                                                        │
│ NOTE   (ERC-20)  par + accrued coupons, or the loss if knocked in             [7]      │
│ WRITER (ERC-20)  maxPayout − NOTE: long knock-in put, short coupons           [7][8]   │
│                                                                                        │
└────────────────────────────────────────────────────────────────────────────────────────┘
                              ▼
┌─ L0  PRIMITIVES ─ pure or permissionless ──────────────────────────────────────────────┐
│                                                                                        │
│ SurrogatePricer (Stylus)  FixingsRecorder             AutocallPayout (library)         │
│   pure, w16a16, ~45k gas    permissionless, checked     pure: fixings → payout,        │
│   weightsHash pinned        against feed rounds;        same rules as teacher,         │
│   OutOfRange → revert       pause = staleness [!]       shared test vectors            │
│                                                                                        │
└────────────────────────────────────────────────────────────────────────────────────────┘
  feed:  Chainlink RHTSLA/USD, 24/5 → FixingsRecorder, NoteQuoter
  cash:  USDG, 6 decimals; the issuer can freeze, wipe and pause               [4]
```

## Why each rule is there

| Tag | Rule | Precedent |
|---|---|---|
| [1] | Each series has its own USDG escrow, and only factory clones may mint or burn | Opyn Gamma audit C01 (fake oToken redeems from the shared pool); Ribbon/Aevo legacy vaults drained for $2.7M through the shared MarginPool, Dec 2025 |
| [2] | Same terms → same series (CREATE2); a series opens at its strike fixing; the Desk quotes a small standard grid | Opyn fixed expiry at 08:00 UTC against fragmentation; Pendle subsidizes each maturity with incentives |
| [3] | `settle` flips once and stores the payout; NOTE rounds down, WRITER = max − NOTE; no mint after settlement; burn before transfer | Gnosis CTF audit (unbounded minting after resolution); Opyn v1 `msg.value` reuse in a loop ($371k) |
| [4] | Pull-based redemption to any `to`; `settle` moves no tokens | USDG's issuer can freeze, wipe and pause (6 decimals, UUPS, no transfer fee) |
| [5] | No lending-collateral oracle for NOTE yet | Pendle PT-reUSD: a $320k trade → 3% move → $36.4M of Morpho liquidations (Aug 2026) |
| [6] | The Desk is the market; no AMM pools for NOTE | Pendle needed a purpose-built AMM; NOTE's value jumps at every fixing |
| [7] | ERC-20 tokens, not ERC-1155 | Siren lost $3.5M to reentrancy through ERC-1155 receive hooks; CTF needed ERC-20 wrappers |
| [8] | The Desk holds WRITER by default; no promise of WRITER liquidity | Siren, Ribbon and Cega all ended up with the vault as the writer |
| [9] | Caps, ε-band before observations, rounding against the trader | Ribbon auctions cleared 1.7–2.8 vol points below exchange prices |
| [!] | Feed pauses detected by staleness | `oraclePaused()` is absent on the TSLA feed (probed), whatever Chainlink's docs say |

Sources: [Opyn Gamma OZ audit](https://www.openzeppelin.com/news/opyn-gamma-protocol-audit) ·
[Ribbon/Aevo drain](https://www.halborn.com/blog/post/explained-the-aevo-ribbon-finance-hack-december-2025) ·
[Opyn v1 post-mortem](https://medium.com/opyn/opyn-eth-put-exploit-post-mortem-1a009e3347a8) ·
[CTF audit](https://reports.chainsecurity.com/Polymarket/ChainSecurity_Polymarket_ConditionalTokens_Audit.pdf) ·
[USDG contract](https://github.com/paxosglobal/usdg-contract) ·
[Pendle AMM](https://docs.pendle.finance/pendle-v2/ProtocolMechanics/LiquidityEngines/AMM) ·
[PT-reUSD cascade](https://cryptobriefing.com/morpho-liquidations-pendle-reusd-cascade/) ·
[Siren exploit](https://quadrigainitiative.com/casestudy/sirenmarketreentrancybug.php) ·
[Ribbon auctions](https://www.research.ribbon.finance/blog/ribbon-auction-performance-analysis)

## Decisions baked into the interfaces

- **Implied vol is not a series term.** It changes the price, never the payout. Keeping it
  out of `SeriesTerms` keeps identical notes in one fungible series; vol is set per series
  in the Desk listing.
- **The payout rules are normative** (see `INoteSeries.sol`). The Monte Carlo teacher must
  implement exactly the same ones: accrued coupon, autocall at `>= ac`, knock-in at `< ki`,
  both latching and checked at fixings only.
- **No demo mode in production contracts.** The demo stages feed history on the mock feed
  and uses series whose strike lies in the past.
- **The Desk's LP flows pause while any held series can't be quoted** (weekends, pending
  fixing). Otherwise the share price would be unknown.
