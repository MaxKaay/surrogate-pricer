# Market

Why a public price for path-dependent notes matters. This is a condensed version of the team's
research (compiled 2026-09-29), with sources.

## The product exists, and it's big

- **US structured notes: a record $149.4B issued in 2024, +46% year on year**
  ([SRP via GenTwo](https://gentwo.com/reports/structured-products-digital-assets/)), and more
  than $220B in 2025 ([Markets Media](https://www.marketsmedia.com/tp-icap-debuts-ats-for-u-s-structured-note-trading/)).
- **$122B of autocallables sold in the US in four years**, mostly by five banks
  ([SLCG](https://www.slcg.com/resources/blog/714)).
- **Europe, where Robinhood stock tokens are available:** German issuers alone hold
  **€100.1B** in listed structured securities, 96.5% of it investment products
  ([BSW, Mar 2025](https://www.derbsw.de/de/marktvolumen/)). Express-Zertifikate (autocallables)
  and Bonus-Zertifikate (barrier notes) are standard retail products there.
- Wall Street is repackaging autocallables for mass retail: Calamos CAIE paid a 17.5% inaugural
  distribution rate, and more than 10 rival autocallable ETFs followed within a year
  ([Calamos](https://www.calamos.com/about/news/press-releases/2025/caie-delivers-strong-first-distribution-following-successful-launch/)).

## The problem: only the issuer knows the price

- **Notes are worth less than you pay on day one.** Fees are embedded and disclosed only in the fine
  print ([SEC](https://www.sec.gov/newsroom/speeches-statements/speech-amy-starr-structured-products)).
- **Implicit markups of about 1–3% over fair value** have been measured academically
  ([MDPI JRFM](https://www.mdpi.com/1911-8074/16/9/401)).
- **The 100 worst autocallables lost investors $1.0B, 55% of face value**
  ([SLCG](https://www.slcg.com/resources/blog/714)).
- **Regulators are looking:** FINRA opened a targeted sweep into "worst-of" structured notes in May 2026
  ([AdvisorHub](https://www.advisorhub.com/finra-targets-high-risk-structured-notes-in-regulatory-sweep/)).
- **Secondary markets:** in the US, notes are mostly hold-to-maturity (the first ATS only launched in
  2026). In Europe, certificates trade on exchanges with issuer quotes
  ([BSW exchange turnover](https://www.derbsw.de/de/boersenumsaetze/)). **Either way, the price
  comes from the issuer's private model.** That's the wedge: a public, recomputable price.

## Why earlier on-chain attempts failed, and what we do differently

Ribbon (>$300M peak TVL), Friktion (>$110M) and Cega (autocallable-style notes, shut down end-2024)
proved demand, then died on economics, shocks and exploits, not on lack of interest. 9 of 13 DeFi
structured-product protocols were gone or had pivoted by late 2024
([Messari](https://messari.io/report/ribbon-finance), [Bitget/Odaily](https://www.bitget.com/news/detail/12560604293248)).

| Lesson | What we do |
|---|---|
| Opaque, locked, weekly-rollover option vaults failed | Maturity-dated NOTE/WRITER ERC-20s with an on-chain quote to enter and exit |
| Coupons that depend on 2–3 market makers (Cega) are fragile | Two on-chain sides: yield seekers hold NOTE, hedgers or Desk LPs hold WRITER |
| A standalone retail dApp capped growth | The pricer is a primitive other protocols can call, and composability is the distribution |
| Shared collateral pools got drained (Ribbon/Aevo, Opyn) | A separate USDG escrow per series ([architecture.md](architecture.md), rule [1]) |

## Who it's for

EU/EEA holders of Robinhood stock tokens: yield seekers who want defined-outcome income, and
holders who want crash protection without selling. Plus the protocols that serve them
(see [user-stories.md](user-stories.md)).
