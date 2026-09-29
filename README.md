# Surrogate Pricer

On-chain fair-value quotes for path-dependent payoffs (autocallables on stock
tokens): an integer MLP distilled from a Monte Carlo teacher, running as a
Stylus contract, behind a model-free note core on Robinhood Chain, settled in USDG.

> **The Big Short, fixed.** In 2008 crash insurance was **priced wrong**, the sellers
> **couldn't pay** (AIG needed $182B), and the **banks decided what positions were worth**.
> Surrogate Pricer keeps the good part (crash protection, and yield for taking risk) and fixes all
> three: a **public price anyone can recompute**, **full collateral** locked from day one, and
> **marks computed in public**. See [docs/pitch.md](docs/pitch.md).

## What it is

- **A note core:** maturity-dated autocallable notes on Robinhood stock tokens, fully collateralized
  in USDG. Minting locks the maximum payout and creates two ERC-20s:
  - **NOTE:** coupons, with the loss if knocked in
  - **WRITER:** the other side, i.e. crash protection
- **A pricer:** a 16-bit integer surrogate of a Monte Carlo pricer, running in Stylus (~45k gas per
  quote). It quotes what a note is worth *right now*, where no closed form exists.
- **A Desk** that buys and sells NOTE at the pricer's quote plus a visible, capped fee.

**Settlement never touches the model.** Payouts are exact arithmetic on recorded fixings.

## Who it's for

| Role | Holds | Gets |
|---|---|---|
| **Yield seeker** | NOTE | Monthly coupons; carries the crash risk (at most what they paid) |
| **Protection buyer** (a hedger, or by default the Desk's LPs) | WRITER | A payout if the stock knocks in; pays the coupons |
| **Integrators** (apps, other protocols) | – | One public, verifiable price for every position |

Six walkthroughs with numbers: [docs/user-stories.md](docs/user-stories.md).

## Why it matters

- **A big product with a hidden price:** US structured notes hit a record $149.4B in 2024. German issuers
  alone hold €100.1B in listed structured securities, and Robinhood stock tokens are EU-only, so
  that's our home market. Issuers' markups of about 1–3% over fair value are measured academically.
- **Nobody on-chain can price path-dependent notes**, so they don't exist there, or settlement
  trusts an operator's number. Earlier attempts (Ribbon, Friktion, Cega) proved demand, then died
  on economics and exploits. The lessons are in [docs/market.md](docs/market.md).

## How it works

Architecture and the lessons it's built on: [docs/architecture.md](docs/architecture.md).
Frontend guide to the frozen v1 interfaces: [docs/interfaces.md](docs/interfaces.md).
Limitations and risks: [docs/risk.md](docs/risk.md).

## Deployed contracts

Robinhood Chain testnet (chain ID 46630). Addresses will be added after deployment
(submission format: `network: address — label`).

| Contract | Address | Explorer |
|---|---|---|
| SurrogatePricer (Stylus) | TBD | TBD |
| SeriesFactory | TBD | TBD |
| NoteQuoter | TBD | TBD |
| FixingsRecorder | TBD | TBD |
| Desk (ERC-4626) | TBD | TBD |
| USDG (Paxos, existing) | `0x7E955252E15c84f5768B83c41a71F9eba181802F` | [explorer](https://explorer.testnet.chain.robinhood.com/address/0x7E955252E15c84f5768B83c41a71F9eba181802F) |

## Demo

- Frontend: TBD
- Demo video (≤ 2:00): TBD
- Pitch video (≤ 2:00): TBD

## Judging criteria → evidence

| Criterion | Evidence |
|---|---|
| Smart contract quality | Model-free core with no admin, no pause and no upgrade; a separate USDG escrow per series; every rule traced to a real exploit ([architecture.md](docs/architecture.md)); the Stylus model matches its Python reference exactly on 100 golden vectors, rejects out-of-range inputs, and has its `weightsHash` recomputed at build. Core invariant tests: TBD |
| Product-market fit | $149.4B US / €100.1B German structured-note markets; hidden issuer markups; two-sided on-chain users ([market.md](docs/market.md), [user-stories.md](docs/user-stories.md)) |
| Innovation and creativity | Monte-Carlo-class pricing of path-dependent payoffs inside a transaction: a surrogate distilled from a simulation (the labels come from code, not market data), verifiable by anyone |
| Real problem solving | Structured-note prices are the issuer's private model; this makes every quote public and recomputable |
| Use of Arbitrum technology | Stylus is the enabling constraint (15.3 KB, ~45k gas per quote, reproducible `cargo stylus verify`); deployed on Robinhood Chain (Arbitrum Orbit) |
| Presentation | Pitch and demo videos: TBD |

## Sponsor technologies

- **Robinhood Chain:** the venue; the stock tokens are the underlyings; Chainlink feeds for fixings.
- **Paxos USDG:** collateral, coupons and settlement currency (6 decimals; the design accounts for the issuer's freeze and pause powers).
- **OpenZeppelin Contracts v5.7.0:** token and vault building blocks (git submodule).

## How we differ

- **Arboretum** (closed-form Black-Scholes in Stylus) stops where closed form ends; we start there.
- **Contour** (structured notes on stock tokens) priced its terms off-chain; our price is on-chain and recomputable.
- **Ribbon, Friktion, Cega** sold opaque option vaults; we issue maturity-dated notes you can enter and exit at a public price.

## Built during the buildathon

All code was written during the buildathon window (Sep 14 to Oct 4, 2026). This repo was
created Sep 29, 2026. Commit `db8f539` imports Solidity from the team's own
[gap-guard](https://github.com/johba37/gap-guard) repo, which was also created Sep 29.
OpenZeppelin Contracts and forge-std are unmodified dependencies (git submodules).
The progress log will be added before submission.

## Roadmap (written as the prize milestones)

The prize pays 25% on signing, 25% after a 1-month check-in, and 50% after a mainnet launch plus an agreed KPI.
- **M1 (check-in):** the real Monte Carlo teacher and distilled weights with a published fidelity report; the Desk live on testnet; invariant and fuzz suites; an external review of the core.
- **M2 (mainnet launch):** core, pricer and Desk on Robinhood Chain mainnet (chain 4663) with real feeds and conservative caps. KPI candidates: USDG notional issued, number of series, and integrations calling the pricer.
- **M3:** a collateral valuation oracle for NOTE/WRITER, built with the lessons of the Pendle PT-reUSD cascade; a mint-and-sell Router; a second payoff type.

## For developers

```
contracts/src/interfaces/  frozen v1 interfaces (factory, series, tokens, quoter, Desk, recorder, pricer)
contracts/src/             FixingsRecorder, NoteQuoter (legacy API), MockChainlinkFeed
abi/                       interface ABIs for the frontend (contracts/script/export-abi.sh)
stylus/pricer-model/       Rust/Stylus model contract: priceBps(PricerInputs), weightsHash()
tools/pricer_quant.py      integer reference (bit-exact twin), float→int quantizer, hash
tools/make_synthetic.py    synthetic student + golden vectors (toy target, NOT the teacher)
model/synthetic/           student_export.json, golden_vectors.json, report.json
docs/model-export-format.md  the distillation ↔ contract boundary
```

### Stylus model status (2026-09-29)

| Check | Result |
|---|---|
| Golden vectors (100) vs Python reference | exact, native `cargo test` and on a local Nitro dev node |
| Out-of-range inputs | revert `OutOfRange(uint8,int64)` (selector `0xd49f98cf`), all bounds tested |
| `weightsHash()` | recomputed at build time; a flipped weight byte fails the build |
| ABI | callable from Solidity through NoteQuoter's `ISurrogatePricer` / `PricerInputs` struct |
| Activation on Robinhood Chain testnet (46630) | `cargo stylus check` passes: 15.3 KB compressed, data fee 0.000077 ETH |
| Execution gas per quote | **~45,000** (Solidity caller, `gasleft()` delta, uncached init included, independent of input) |
| Quantization error (int16 vs float, synthetic) | p50 0.3 / p99 1.2 / max 3.2 bps |

The model is **synthetic** until the distillation lane ships a real export.
To swap it in: `PRICER_MODEL_DIR=<dir with student_export.json + golden_vectors.json> cargo test`.

### Commands

```sh
# Python reference (numpy, torch for the synthetic fit, pycryptodome for keccak)
python3 -m venv --system-site-packages tools/.venv && tools/.venv/bin/pip install pycryptodome
cd tools && ../tools/.venv/bin/python make_synthetic.py --out ../model/synthetic

# Solidity
cd contracts && forge test && script/export-abi.sh

# Stylus contract
cd stylus/pricer-model
cargo test                                   # golden vectors + ABI path
cargo stylus check --endpoint https://rpc.testnet.chain.robinhood.com
cargo stylus deploy --endpoint <rpc> --private-key-path <file>

# Local gas measurement
docker run -d --rm --name sp-devnode -p 127.0.0.1:8547:8547 \
  offchainlabs/nitro-node:v3.11.4-7d5ac27 --dev --http.addr 0.0.0.0 --http.api=net,web3,eth,debug
```

Toolchain is pinned in `rust-toolchain.toml` (1.91.0) for reproducible
`cargo stylus verify`.

## License

[MIT](LICENSE)
