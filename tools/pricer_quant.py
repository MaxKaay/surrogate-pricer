"""Integer reference for the Surrogate Pricer student (featureSpecVersion 1).

This module is the bit-exact definition of what the Stylus contract computes.
Anything the contract does must be reproducible here with plain integers, and
the golden vectors are generated from `forward()` below — never from a float
model. Spec: docs/model-export-format.md.

Three jobs:
  * `normalize()` / `forward()`   — the integer forward pass (the contract's twin)
  * `quantize()`                  — float MLP (numpy arrays) -> student_export dict
  * `canonical_bytes()` / `weights_hash()` — the hash the contract pins
"""

from __future__ import annotations

import json
from dataclasses import dataclass

import numpy as np
from Crypto.Hash import keccak

FEATURE_SPEC_VERSION = 1
EXPORT_FORMAT_VERSION = 1


@dataclass(frozen=True)
class Field:
    name: str
    lo: int
    hi: int


# Order = PricerInputs struct order (NoteQuoter.sol) = model input order.
# Ranges = teacher-spec.md §4 = NoteQuoter bounds. Out of range reverts.
FIELDS: tuple[Field, ...] = (
    Field("spotBpsOfInitial", 2_000, 30_000),
    Field("distToKnockInBps", -8_000, 20_000),
    Field("volBpsAnnual", 1_500, 15_000),
    Field("kiBarrierBps", 4_000, 9_000),
    Field("acBarrierBps", 9_000, 11_000),
    Field("couponBpsPerPeriod", 0, 1_500),
    Field("timeToMaturitySecs", 604_800, 63_072_000),
    Field("timeToNextObsSecs", 0, 604_800),
    Field("observationsRemaining", 1, 104),
    Field("flags", 0, 1),
)
FIELD_NAMES = tuple(f.name for f in FIELDS)

PRICE_MAX_BPS = 65_535  # uint16 return type


class OutOfRange(ValueError):
    def __init__(self, index: int, value: int):
        super().__init__(f"{FIELDS[index].name}={value} outside [{FIELDS[index].lo}, {FIELDS[index].hi}]")
        self.index = index
        self.value = value


# ---------------------------------------------------------------------------
# Integer primitives (binding; mirrored 1:1 in stylus/src/engine.rs)
# ---------------------------------------------------------------------------

def round_shift(p: int, s: int) -> int:
    """p / 2**s rounded half away from zero. Sign-magnitude, so negative values
    round symmetrically (a plain `(p - half) >> s` floors -0.25 to -1)."""
    assert s >= 1
    half = 1 << (s - 1)
    if p >= 0:
        return (p + half) >> s
    return -((-p + half) >> s)


def qmax(bits: int) -> int:
    return (1 << (bits - 1)) - 1


def normalize(raw: dict[str, int] | list[int], bits: int = 16) -> list[int]:
    """Raw feature units -> signed `bits`-wide ints in [-qmax, qmax].
    Out-of-range raises (the contract reverts); inputs are never clamped."""
    q = qmax(bits)
    values = [raw[f.name] for f in FIELDS] if isinstance(raw, dict) else list(raw)
    out = []
    for i, (f, x) in enumerate(zip(FIELDS, values)):
        if not (f.lo <= x <= f.hi):
            raise OutOfRange(i, x)
        rng = f.hi - f.lo
        out.append(((x - f.lo) * 2 * q + rng // 2) // rng - q)
    return out


def _wdtype(bits: int) -> str:
    return {8: "i1", 16: "<i2"}[bits]


def _layer_int(x: list[int], layer: dict, out_dim: int, in_dim: int, wbits: int) -> list[int]:
    w = np.frombuffer(bytes.fromhex(layer["weightsHex"][2:]), dtype=_wdtype(wbits)).reshape(out_dim, in_dim)
    acc = []
    for i in range(out_dim):
        a = sum(int(w[i, j]) * x[j] for j in range(in_dim)) + layer["bias"][i]
        assert -(2**63) <= a < 2**63, "int64 accumulator overflow"
        acc.append(a)
    return acc


def forward(export: dict, raw) -> int:
    """Integer forward pass. Returns priceBpsOfNotional (uint16)."""
    bits = export["quantization"]["activationBits"]
    wbits = export["quantization"]["weightBits"]
    q = qmax(bits)
    x = normalize(raw, bits)
    arch = export["architecture"]["layers"]
    for spec, layer in zip(arch[:-1], export["layers"][:-1]):
        acc = _layer_int(x, layer, spec["out"], spec["in"], wbits)
        x = []
        for i, a in enumerate(acc):
            a = max(a, 0)  # relu
            y = round_shift(a * layer["requantMultiplierQ16"][i], 16 + layer["requantShift"][i])
            x.append(max(-q - 1, min(q, y)))
    head_spec, head = arch[-1], export["layers"][-1]
    (acc,) = _layer_int(x, head, head_spec["out"], head_spec["in"], wbits)
    out = export["output"]
    price = round_shift(acc * out["multiplierQ16"], 16 + out["shift"]) + out["offsetBps"]
    return max(0, min(PRICE_MAX_BPS, price))


# ---------------------------------------------------------------------------
# Float -> int8 quantization (usable by the distillation lane as-is)
# ---------------------------------------------------------------------------

def normalized_float_inputs(raws: list, bits: int = 16) -> np.ndarray:
    """What the float student must be trained on: the *integer* normalization
    divided by qmax, so float training and on-chain inference see identical
    inputs (no train/serve skew)."""
    return np.array([normalize(r, bits) for r in raws], dtype=np.float64) / qmax(bits)


def _mult_shift(m: float) -> tuple[int, int]:
    """Real multiplier m > 0 -> (M, shift) with m ≈ M / 2**(16+shift),
    M in [2**15, 2**16)."""
    assert m > 0
    mant, exp = np.frexp(m)  # m = mant * 2**exp, mant in [0.5, 1)
    M = int(round(mant * 65536))
    if M == 65536:
        M, exp = 32768, exp + 1
    shift = -int(exp)
    assert 1 <= 16 + shift <= 62, f"multiplier {m} out of representable range"
    return M, shift


def quantize(weights: list[np.ndarray], biases: list[np.ndarray], calib_x: np.ndarray,
             price_scale_bps: float, offset_bps: int, act_headroom: float = 2.0,
             activation_bits: int = 16, weight_bits: int = 16) -> dict:
    """Float MLP (relu hidden layers, linear head, trained on
    normalized_float_inputs -> (priceBps - offset_bps) / price_scale_bps) ->
    student_export dict (weightsHash filled in).

    weights[l] has shape (out, in). calib_x is float input in [-1, 1] used to
    size the per-tensor activation scales. Arithmetic is i64 in the contract
    whatever the widths, so 16-bit weights/activations cost no extra gas —
    only code size (weights are embedded in the wasm). int8 weights were
    measured at ~110 bps p99 on a synthetic price head: too coarse for K1.
    """
    qw = qmax(weight_bits)
    q = qmax(activation_bits)
    s_in = 1.0 / q
    h = calib_x
    layers_out, arch = [], []
    n = len(weights)
    for l, (W, b) in enumerate(zip(weights, biases)):
        out_dim, in_dim = W.shape
        sw = np.maximum(np.abs(W).max(axis=1), 1e-12) / qw
        Wq = np.clip(np.round(W / sw[:, None]), -qw, qw).astype(_wdtype(weight_bits))
        bq = np.round(b / (s_in * sw)).astype(np.int64)
        assert np.all(np.abs(bq) < 2**53), "bias beyond exact-JSON-integer range"
        entry = {
            "weightsHex": "0x" + Wq.tobytes().hex(),
            "bias": [int(v) for v in bq],
        }
        h = h @ W.T + b
        if l < n - 1:
            h = np.maximum(h, 0.0)
            # calibration max x headroom: an input region calibration missed
            # must not saturate (one bit of 16 buys it; saturation cost 190 bps)
            s_out = max(float(h.max()) * act_headroom, 1e-12) / q
            ms = [_mult_shift(s_in * sw[i] / s_out) for i in range(out_dim)]
            entry["requantMultiplierQ16"] = [m for m, _ in ms]
            entry["requantShift"] = [s for _, s in ms]
            arch.append({"in": in_dim, "out": out_dim, "activation": "relu"})
            s_in = s_out
        else:
            assert out_dim == 1
            head_m, head_s = _mult_shift(s_in * sw[0] * price_scale_bps)
            arch.append({"in": in_dim, "out": 1, "activation": "linear"})
        layers_out.append(entry)

    export = {
        "exportFormatVersion": EXPORT_FORMAT_VERSION,
        "featureSpecVersion": FEATURE_SPEC_VERSION,
        "weightsHash": "0x",
        "architecture": {
            "inputDim": len(FIELDS),
            "layers": arch,
            "parameterCount": int(sum(W.size + b.size for W, b in zip(weights, biases))),
        },
        "quantization": {"weightBits": weight_bits, "activationBits": activation_bits},
        "featureNormalization": [{"name": f.name, "min": f.lo, "max": f.hi} for f in FIELDS],
        "layers": layers_out,
        "output": {"multiplierQ16": head_m, "shift": head_s, "offsetBps": int(offset_bps)},
    }
    export["weightsHash"] = weights_hash(export)
    return export


# ---------------------------------------------------------------------------
# Canonical serialization + hash
# ---------------------------------------------------------------------------

def _assert_integers_only(v) -> None:
    """Floats are banned from the export so the canonical form has exactly one
    spelling in every JSON library (the Rust build script re-hashes it)."""
    if isinstance(v, float):
        raise TypeError("float in export; encode as integer")
    if isinstance(v, dict):
        for x in v.values():
            _assert_integers_only(x)
    elif isinstance(v, list):
        for x in v:
            _assert_integers_only(x)


def canonical_bytes(export: dict) -> bytes:
    blanked = dict(export, weightsHash="0x")
    _assert_integers_only(blanked)
    return json.dumps(blanked, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def weights_hash(export: dict) -> str:
    return "0x" + keccak.new(digest_bits=256, data=canonical_bytes(export)).hexdigest()
