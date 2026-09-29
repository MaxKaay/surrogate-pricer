# User stories

Plain-language walkthroughs for the pitch, the demo video and anyone new to the project.
All numbers are illustrative: each weekly series has fixed terms, and the pricer says what a
note is worth right now. Robinhood stock tokens are available to EU/EEA retail users, so think
of these people as Europeans holding US stock tokens. Not financial advice.

## Two roles, one note

- **Yield seekers** hold the **NOTE**: they earn monthly coupons and carry the crash risk.
- **Protection buyers** hold the **WRITER**: they fund the coupons and receive the NOTE holders'
  losses if the crash line is crossed. That's a long knock-in put, short coupons.

By default the **Desk's LPs** hold the WRITER side. A hedger can also take it directly by minting pairs.

## The note used in every example

| Term | Value |
|---|---|
| Size | 1 NOTE = 1 USDG notional; examples use 1,000 USDG |
| Length | 12 months, one **check date** (fixing) per month, recorded on-chain from the price feed |
| Coupon | 0.8% per month = 8 USDG per 1,000, paid on a check date if the stock is **≥ 70%** of its initial fixing |
| Autocall | From month 3: if the stock is **≥ 100%** on a check date, the note ends. You get 1,000 back plus that month's coupon |
| Knock-in | **70%**, checked on check dates only |
| At maturity | Never knocked in → 1,000 back. Knocked in *and* ends below the start → 1,000 × final ÷ initial |
| Collateral | Minting a pair locks the maximum payout (here 1,096 USDG per 1,000 notional) in the series' own escrow |

How the pieces fit:
- The **pricer** (Stylus) is a shared calculator.
- Each **series** holds its own USDG and applies the rules above, with **no model**.
- The **Desk** buys and sells NOTE at the pricer's quote ± a visible fee.
- **Apps** call the pricer too.

## 1. Anna wants a steady income from Apple

1. **She picks the Apple series in the app.** The Desk asks the pricer for a quote. The screen shows: *Fair value 997 USDG · Fee 3 USDG · You pay 1,000 USDG · 8 USDG per month while Apple ≥ 70%.*
2. **She pays 1,000 USDG and receives 1,000 NOTE.** The quote is logged on-chain with the model's `weightsHash`, so it can be checked later.
3. **On each check date** the fixing is recorded (permissionlessly), and the series pays coupons by its rules. No one decides anything by hand.
4. **How the year can end:**
   - Sideways (75–99%): 12 × 8 = 96 in coupons plus 1,000 back, **1,096 in total**.
   - Apple at 103% at month 3: autocall, 24 in coupons plus 1,000, **1,024 in total**.
   - Crash: months 1–5 pay 40. Apple is at 60% at the month-6 check, so the note knocks in and coupons stop. Apple ends at 65%, so she gets back 650. **690 in total, a loss of 310.** That's the risk she took for the coupons.
5. **Why the public price matters:** she knows the note was worth 997 when she paid 1,000, and the fee was shown to her, not hidden.

## 2. Ben protects his Nvidia without selling

Ben holds 10,000 USDG of Nvidia tokens and fears a crash, but doesn't want to sell.
1. **He chooses 10,000 USDG of Nvidia protection.** Nvidia is more volatile, so its series pays a higher coupon, say 1.0% per month. That's **100 USDG a month, his insurance cost**.
2. **He mints 10,000 pairs,** locking the maximum payout (1,000 + 12 × 10 = 1,120 per 1,000 notional, so 11,200 in total). He gets **10,000 NOTE + 10,000 WRITER**.
3. **He sells the NOTE to the Desk** for about 10,000 after the fee. His net stake is about 1,200, the most he can lose in coupons. The **WRITER is his protection**. *(A Router doing mint + sell in one transaction is a stretch goal.)*
4. **How the year can end:**
   - Calm: coupons cost him up to 1,200, and there's no payout. If the note autocalls early, the unused collateral comes back.
   - A 25% dip that never touches 70% on a check date: no payout. Think of it as insurance **with a deductible**.
   - Crash: 3 coupons are paid (300), Nvidia is at 62% at the month-4 check, and it ends at 60%. NOTE holders get 6,000. **WRITER gets the rest of the escrow, 4,900.** Net +3,700 for Ben, which covers most of his 4,000 loss on the tokens.
5. **Why the public price matters:** his insurance cost comes from the same public calculator the buyers see, so neither side is overcharged in secret.

## 3. Carla needs her money back early

Carla holds an Apple note like Anna's. After 4 months she needs cash.
1. **She sells her NOTE back to the Desk.** The pricer looks at Apple's price now, the 8 months left, the fixings so far (no knock-in yet) and the series terms.
2. **The screen shows:** *Fair value 1,008 · Fee 3 · You receive 1,005.* Apple is slightly below its initial fixing (otherwise the note would have autocalled), but up to 8 coupons are still ahead. The quote is rounded against the trader, which protects the Desk's LPs from people gaming tiny pricing errors.
3. **No quote near barriers and fixings, on weekends, or while a fixing is pending.** The value can jump in those moments, and the reference feed runs 24/5, so the Desk pauses instead of guessing. Stock tokens trade 24/7, but her exit waits until the market reopens. The app says so before she buys.
4. **Compare a bank note:** she'd sell back to the bank at whatever it bids, with no way to check.

## 4. Ben borrows more against his *protected* Nvidia *(demo-only in the MVP)*

A production collateral oracle for NOTE/WRITER is **roadmap**, deliberately (see
[architecture.md](architecture.md), rule [5]: the Pendle PT-reUSD cascade). The MVP shows this
story with a **demo-only valuation contract on testnet**. It needs no new model:
**WRITER value = max payout − NOTE quote**.

1. For Nvidia alone, a lender would lend about **50%, so 5,000 USDG**.
2. Ben deposits **Nvidia + WRITER together**. The lender values the Nvidia from the feed and the WRITER from the pricer.
3. If Nvidia knocks in, the WRITER pays out the loss. The bad case left is Nvidia ending just above 70% without a knock-in, a floor of about **7,000**. That supports **60–65%, so about 6,000 USDG**.
4. **Caveat: an autocall ends the protection.** If Nvidia is ≥ 100% on a check date, the collateral is plain Nvidia again, which means a **margin call when the stock went up**.
5. **No quotes on weekends** means the lender can't revalue then. It must freeze new borrows and apply an extra haircut to the last value.

This is the DeFi-lego point: **two separate apps, one pricer.** The protection only counts as
collateral because anyone can price it.

## 5. Emma builds a ladder

Emma splits 3,000 USDG across three series (Tesla, Apple, Microsoft) starting in different
weeks. The Desk quotes a small standard grid, one series per underlying per week, so laddering is
natural. Her coupons arrive at different times, one crash hits only a third of her money, and
her portfolio value is three pricer calls added up. Autocallable ETFs do this in TradFi;
here every price is visible.

## 6. The honest price tag

1. **Every quote shows three numbers:** fair value (from the pricer), fee (a call parameter capped at `maxFeeBps`, with a slice going to a backstop), and the total.
2. **Every quote is logged on-chain** (`NoteQuoted`) with its inputs and the model's `weightsHash`.
3. **Anyone can recompute it** by running the open Monte Carlo teacher on those inputs.
4. **Settlement never uses the model.** It's arithmetic on recorded fixings. The model only speaks at optional moments (buy, sell, valuation), and it refuses near barriers.
5. **Compare a bank note:** you pay par for something worth less on day one. Studies measure a hidden margin of about 1–3% ([market.md](market.md)).
