# Pitch: "The Big Short, fixed"

Opener for the pitch video and the deck. **Positioning rule:** we are the fix for 2008's three
flaws, never "a 2008 product". Use only the verified numbers below.

## Opening (~20 seconds)

> "In 2005, Michael Burry started paying for insurance against a housing crash. For two years
> he paid premiums, nothing happened, and his investors wanted out. Then the crash came: his
> fund made **$725 million**, and John Paulson made **$15 billion** in 2007.
> But that insurance only paid off like that because it was **priced wrong**. The sellers
> **couldn't pay**: AIG needed **$182 billion** from the government. And the banks **decided
> what the positions were worth**.
> Crash insurance and earning yield for taking risk are good products. 2008 got three things
> wrong. We fix all three."

## The three fixes (one slide)

| 2008 | Surrogate Pricer | How |
|---|---|---|
| **Priced wrong:** ratings and private bank models hid the real risk | **A public price anyone can recompute** | The pricer runs on-chain in Stylus; every `NoteQuoted` event carries the inputs and the model's `weightsHash`; anyone can re-run the Monte Carlo teacher and check the quote |
| **Sellers couldn't pay:** AIG sold protection it couldn't cover | **Fully collateralized** | Minting locks the note's maximum payout in the series' own USDG escrow. There is no AIG that can fail |
| **Banks controlled the marks** of the positions they were on the other side of | **Marks computed in public** | The same pricer values every position for everyone: buyers, sellers and any protocol that integrates it |

Two more differences, one sentence each: **one visible underlying** (a single stock token, not
thousands of hidden mortgages with unknown correlation), and **no leverage** (a note buyer can
lose at most what they paid, and sees that before buying).

## The characters, mapped to our roles

- **The hedger is Burry, but protecting stock they own.** They pay a premium (the coupon, via
  the WRITER side) and get paid in a crash. Anyone can take this side.
- **The yield seeker is the other side of 2008,** taking crash risk for income. The difference:
  they see the fair price, the fee and the worst case *before* buying.

## The honest line (say it before a judge asks)

> "You won't make Burry's money with this. His profit came from mispricing, and a fair public
> price removes that. And if our model is ever wrong somewhere, people will hunt for that spot
> just like Burry did. That's why quotes refuse near barriers and fixings, every series has a
> cap, and every quote can be checked against the simulation."

## Closing line options

"The Big Short, without the three flaws." · "Crash insurance, priced in public."

## Sources

- Burry: Scion made $725M for investors ($100M for Burry personally); first CDS bought May 2005:
  [Scion Asset Management](https://en.wikipedia.org/wiki/Scion_Asset_Management),
  [Michael Burry](https://en.wikipedia.org/wiki/Michael_Burry)
- Paulson $15B in 2007: [CNBC](https://www.cnbc.com/2009/01/23/the-man-who-made-too-much.html)
- AIG ~$182B government support (≈$70B Treasury + $112B NY Fed):
  [Congressional Research Service](https://www.congress.gov/crs-product/R42953)
- Don't quote multiples such as "100×". Burry's roughly $100M in premiums is secondary-sourced only.
