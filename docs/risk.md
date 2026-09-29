# Limitations and risks

What can go wrong, and what bounds it. The mechanics live in [architecture.md](architecture.md);
this page is the honest summary.

## Model risk: what happens if the model is wrong

There are three distinct failure modes:

1. **The student deviates from the teacher.** The integer surrogate differs from the Monte Carlo
   teacher. This is bounded and published: golden vectors must match exactly, and fidelity is
   measured on an adversarial grid with the threshold fixed before distillation.
2. **The teacher is wrong about the world.** Perfect fidelity to a wrong model (for example a
   wrong volatility assumption) is still a wrong price.
3. **Bad inputs:** a stale feed, missing fixings, or out-of-range terms.

**The key asymmetry:** the terminal payoff is **never model-based**. Settlement is deterministic
arithmetic on recorded fixings. The model only speaks at *optional* moments (buying from or
selling to the Desk, valuation), and those moments get **adversarially selected**. Any region
where the model prices low will be found and traded against the writer. Public weights make that
search free for attackers, and our adversarial grid is the same search, run first.

**Mitigations, layered:**
- Full collateralization caps any loss at the series' maximum payout.
- ε-bands: no quotes near barriers and before observations.
- Rounding against the trader.
- Per-series caps and a Desk TVL cap.
- A fee-funded backstop.
- Continuous public audit: anyone can re-run the teacher against every `NoteQuoted` event.

In TradFi, model risk is hidden inside the bank and backstopped by its balance sheet. Here it is
bounded by collateral caps, published as a fidelity number, and monitored in public.

## Platform and market risks

| Risk | Consequence | How it's handled |
|---|---|---|
| **USDG issuer powers:** Paxos can freeze, wipe and pause USDG balances (6 decimals, UUPS) | A frozen address can't receive a redemption | Pull-based redemption to any `to`; `settle()` moves no tokens ([architecture.md](architecture.md), rule [4]) |
| **Reference feed runs 24/5 and can pause.** The TSLA feed has no `oraclePaused()` despite Chainlink's docs (probed 2026-09-29) | No reliable price on weekends or during pauses | Pauses are detected by staleness; the quoter reverts on a stale feed; the Desk's LP flows pause while a held series can't be quoted |
| **Fixings need someone to record them** | A missed fixing delays settlement | `recordFixing()` is permissionless and checked against feed rounds; anyone can call it |
| **WRITER liquidity** | Hedgers may not find buyers for WRITER | No promise of WRITER liquidity; the Desk holds WRITER by default (rule [8]) |
| **Weekend gap:** stock tokens trade 24/7, but quotes stop on weekends | Exits and valuations wait until the market reopens | Stated up front in the app and the docs |
| **Collateral use of NOTE/WRITER** | Oracle-driven liquidation cascades (Pendle PT-reUSD, Aug 2026) | No production collateral oracle yet; demo-only valuation contract; roadmap item with explicit limits |
| **Access:** Robinhood stock tokens are EU/EEA retail only (MiFID II; US persons, UK, CH, CA excluded) | The addressable users are European | The pitch and market sizing use EU figures ([market.md](market.md)) |

## Current status caveats (MVP)

- The deployed model is **synthetic** until the distillation lane ships the real Monte Carlo
  export (see the README status table).
- Testnet uses **mock price feeds** with staged history; there's no demo mode in production contracts.
- No external audit yet.
- Not financial advice. This is infrastructure: a pricer and a collateralized note core.
