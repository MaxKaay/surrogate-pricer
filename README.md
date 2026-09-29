# Surrogate Pricer

On-chain fair-value quotes for path-dependent payoffs (autocallables on stock
tokens): an integer MLP distilled from a Monte Carlo teacher, running as a
Stylus contract, behind a model-free note core on Robinhood Chain, settled in USDG.

Architecture and the lessons it's built on: [docs/architecture.md](docs/architecture.md).
Frontend guide to the frozen v1 interfaces: [docs/interfaces.md](docs/interfaces.md).

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

## Stylus model status (2026-09-29)

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

## Commands

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
