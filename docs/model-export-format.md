# Model export format — `student_export.json` v1 (pricer)

The boundary between the distillation lane (Monte Carlo teacher → float student)
and the contracts lane (Stylus). If it's not in this document, it doesn't cross
the boundary. Reference implementation: [`tools/pricer_quant.py`](../tools/pricer_quant.py)
(`quantize()` produces this file from a float MLP; `forward()` is the bit-exact
twin of the contract).

Derived from GapGuard's `student-export-format.md`, with the changes listed at
the end. Those changes are deliberate and backed by measurements.

## Workflow for the distillation lane

1. Train the float student on **`normalized_float_inputs(raws)`**, i.e. the
   integer normalization divided by `qmax`, not on your own scaling. Then
   training and the chain see identical inputs (no train/serve skew).
   Target: `(priceBps − offsetBps) / priceScaleBps`.
2. Relu hidden layers, one linear output. Weights as numpy arrays with shape `(out, in)`.
3. `pq.quantize(weights, biases, calib_x, price_scale_bps, offset_bps)` → export dict.
   Write it as JSON. Then generate golden vectors with `pq.forward()` (see
   `tools/make_synthetic.py` for the exact layout).
4. Report fidelity for the **integer** student (`pq.forward`) against the teacher.
   That's the number the chain reproduces, not the float model.
5. Build the contract with `PRICER_MODEL_DIR=<dir> cargo build`. The build
   recomputes the hash and proves no overflow is possible, or it fails.

## Inputs — featureSpecVersion 1

The field order is the `PricerInputs` struct order in `NoteQuoter.sol`. The
ranges equal the teacher spec §4 and the NoteQuoter bounds. **Out of range →
the model reverts `OutOfRange(uint8 field, int64 value)`.** It never clamps,
so the pricer fails closed even when called directly rather than through
NoteQuoter (it's meant as a shared building block).

| # | Field | Min | Max |
|---|---|---|---|
| 0 | spotBpsOfInitial | 2,000 | 30,000 |
| 1 | distToKnockInBps | −8,000 | 20,000 |
| 2 | volBpsAnnual | 1,500 | 15,000 |
| 3 | kiBarrierBps | 4,000 | 9,000 |
| 4 | acBarrierBps | 9,000 | 11,000 |
| 5 | couponBpsPerPeriod | 0 | 1,500 |
| 6 | timeToMaturitySecs | 604,800 | 63,072,000 |
| 7 | timeToNextObsSecs | 0 | 604,800 |
| 8 | observationsRemaining | 1 | 104 |
| 9 | flags (bit0 knockedIn) | 0 | 1 |

Normalization (binding, integer floor division, non-negative operands):
`x = ((v − min)·2·qmax + range//2) // range − qmax`, with `qmax = 2^(activationBits−1) − 1`.

## Schema

```jsonc
{
  "exportFormatVersion": 1,
  "featureSpecVersion": 1,
  "weightsHash": "0x…",                  // keccak256 of canonical form, see below
  "architecture": {
    "inputDim": 10,
    "layers": [ {"in": 10, "out": 64, "activation": "relu"}, …,
                {"in": 48, "out": 1, "activation": "linear"} ],
    "parameterCount": 3873
  },
  "quantization": { "weightBits": 16, "activationBits": 16 },
  "featureNormalization": [ {"name": "spotBpsOfInitial", "min": 2000, "max": 30000}, … ],
  "layers": [
    { "weightsHex": "0x…",               // int8 or int16 LE two's complement, row-major (out, in)
      "bias": [ … ],                     // int64, scale = s_in·s_w[i]; |b| < 2^53
      "requantMultiplierQ16": [ … ],     // per output channel, in [2^15, 2^16)
      "requantShift": [ … ] },           // per output channel; total shift S = 16 + shift, 1 ≤ S ≤ 62
    { "weightsHex": "0x…", "bias": [ … ] }   // head: no requant fields
  ],
  "output": { "multiplierQ16": …, "shift": …, "offsetBps": 10000 }
}
```

## Arithmetic (binding)

All in i64. Per hidden layer, channel `i`:

1. `acc = b[i] + Σ_j w[i,j]·x[j]`
2. `acc = max(acc, 0)` (relu)
3. `y = round_shift(acc · M[i], 16 + shift[i])`, saturated to `[−qmax−1, qmax]`

Head: `price = round_shift(acc · M, 16 + shift) + offsetBps`, clamped to `[0, 65535]`, returned as `uint16`.

`round_shift(p, S)`: rounds half away from zero, **sign-magnitude**:
`p ≥ 0 ? (p + 2^(S−1)) >> S : −((−p + 2^(S−1)) >> S)`.

## Canonical form and hash

`weightsHash = keccak256(json.dumps(export_with_weightsHash="0x", sort_keys=True,
separators=(",", ":"), ensure_ascii=False).encode())`. **No floats anywhere in
the file.** The build script re-serializes and re-hashes it in Rust, and
integer-only JSON has exactly one canonical spelling in both languages. The
contract returns the recomputed hash from `weightsHash()`.

## Golden vectors (`golden_vectors.json`)

- `weightsHash`: must equal the compiled model's hash (CI checks this).
- `modelVectors`: exactly 100 rows of `{features, expectedPriceBps}` from
  `pq.forward()`. Included: all-min, all-max, all-mid, each field at both
  bounds with the rest at mid, and the remainder sampled consistently.
  CI requires **exact** equality.
- `rejectVectors`: `{features, fieldIndex}`. One per bound the ABI type can
  express. CI requires the revert with that field index.

## Changes from GapGuard's format, and why

| Change | Why (measured on a 3,873-parameter synthetic student) |
|---|---|
| **16-bit weights and activations** (were int8) | Stylus arithmetic is i64 regardless, so width is free in gas; it only costs code size (15.3 KB of the 24 KB limit). Post-training int8 weights alone cost **p99 110 bps / max 343 bps** on a price head spanning ~16,000 bps. That breaks the 50 bps K1 budget before the teacher error is even counted. int16: **p99 1.2 / max 3.2 bps**. Inputs were also coarse at 8 bits: a 1.1% step in spot. |
| **Activation scale = calibration max × 2** (not a percentile) | At the 99.99th percentile, one held-out input saturated a channel: max error 190 bps. One bit of headroom removes it. |
| **Per-channel requant multiplier/shift** (was one per layer) | Per-channel weight scales require a per-channel multiplier, or channels get rescaled wrongly. |
| **Linear head with multiplier/offset** (was sigmoid LUT) | A price isn't a probability. An int8 output would have ~40 bps resolution. |
| **Sign-magnitude rounding** (was `(p + copysign(half, p)) >> S`) | With an arithmetic shift, the old formula floors −0.25 to −1. The head can go negative, so this matters. |
| **int64 bias, integer-only JSON, `exportFormatVersion`** | int32 overflows at 16×16-bit scales. Floats make the canonical hash library-dependent. |
| **Out-of-range → revert** (was clamp on the student side) | Callers other than NoteQuoter get the same fail-closed guarantee. In-range behavior is unchanged. |
