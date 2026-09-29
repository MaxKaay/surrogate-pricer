# Submission checklist: Arbitrum Open House Singapore

The HackQuest form fields, with drafts where possible. **Every text field has a 300-character limit.**

**Deadline:** Sun **Oct 4, 2026, 23:59 SGT** (the buildathon page). The T&C PDF says Oct 1. Treat
the page as authoritative, but have a valid submission in by **Oct 1, 23:59 SGT** as a hedge.
Submissions can be updated until the deadline. **Registration** closes Oct 3, 01:01 SGT, and
requires an Arbitrum One wallet for prize payout.

## Registration: "Do you already have an idea?" (≤ 300 chars)

> SurrogatePricer: fair-value quotes for path-dependent payoffs. A 16-bit integer model distilled from a Monte Carlo teacher runs on-chain in Stylus (~45k gas), pricing autocallable notes on stock tokens at mint and exit. No closed form, no pricing API; settlement is exact. USDG on Robinhood Chain.

(297 chars.)

## Project submission form

| # | Field | Status | Draft / what to paste |
|---|---|---|---|
| 1 | Link to frontend/UI/website | ☐ TODO | The frontend URL (required) |
| 2 | Core protocol / smart contract addresses | ☐ after deploy | One per line, `network: address — label`. For example: `Robinhood Chain: 0x… — SurrogatePricer (Stylus)`, `Robinhood Chain: 0x… — NoteQuoter`, `Robinhood Chain: 0x… — FixingsRecorder`, `Robinhood Chain: 0x… — Desk` |
| 3 | Factory / pool contracts | ☐ after deploy | `Robinhood Chain: 0x… — SeriesFactory` (the organizers use this to track series deployments) |
| 4 | Token contract address | ☐ after deploy | NOTE and WRITER are per-series ERC-20s created by the factory. List one demo series' NOTE and WRITER, and point to the factory. No protocol token |
| 5 | Which parts were produced during the buildathon | ✅ draft | See below |
| 6 | Sponsor / partner technologies | ✅ | **Robinhood Chain, Paxos/USDG, OpenZeppelin**. Check that each is visibly used in the README |
| 7 | Contract address (HackQuest field) | ☐ after deploy | The main user-facing contract (Desk, or NoteQuoter if the Desk isn't deployed) |
| – | Demo video (≤ 2:00) | ☐ TODO | Buy → exit → the honest price tag (user stories 1, 3, 6) |
| – | Pitch video (≤ 2:00) | ☐ TODO | [pitch.md](pitch.md): The Big Short, fixed |
| – | Progress during the buildathon | ☐ TODO | A changelog-style list with dates and commit/PR links (winners in past editions did this) |
| – | Repo link | ✅ | Public repo, real commit history |

**Field 5 draft (259 chars):**

> All code was written during the buildathon (Sep 14 to Oct 4, 2026). This repo was created Sep 29; commit db8f539 imports Solidity from our own gap-guard repo, also created Sep 29. OpenZeppelin v5.7.0 and forge-std are unmodified dependencies (git submodules).

## Judging criteria (from the buildathon page)

Hard gate: deployed on an Arbitrum chain (Robinhood Chain qualifies). Four criteria:
**smart contract quality, product-market fit, innovation and creativity, real problem solving.**
**USDG integration** earns extra consideration. **At least 1 of 3 prizes is reserved for Robinhood Chain.**
The T&C also list: use of Arbitrum technology, presentation quality, and a novelty bonus.
Map each one to evidence in the README.

## Prize payout (T&C)

Overall prizes pay **25%** on signing a grant agreement, **25%** after a 1-month check-in (building
exclusively on Arbitrum), and **50%** after a **mainnet launch plus an agreed KPI**. The README roadmap
is written as those milestone candidates.

## Before pressing submit

- [ ] Deployed addresses in the README match the form
- [ ] Frontend link works in a fresh browser
- [ ] Both videos are ≤ 2:00 and public/unlisted
- [ ] README criteria → evidence table filled in, with no "TBD" left
- [ ] CI green on `main`
