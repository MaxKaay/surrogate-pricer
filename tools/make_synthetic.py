"""Synthetic student + golden vectors for the Stylus lane.

The target is a TOY price function, not the Monte Carlo teacher. Its only job
is to give the Stylus contract realistic weights (real activation ranges, real
requant multipliers, a 3-5K parameter budget) so the integer port, the hash
pin and gas can be tested before the distillation lane ships a real export.

Usage: tools/.venv/bin/python tools/make_synthetic.py [--out model/synthetic]
Deterministic given --seed.
"""

from __future__ import annotations

import argparse
import json
import pathlib

import numpy as np
import torch

import pricer_quant as pq

WEEK = 604_800


def sample_raw(rng: np.random.Generator, n: int) -> list[list[int]]:
    """Internally consistent inputs, the way NoteQuoter derives them."""
    rows = []
    while len(rows) < n:
        spot = int(rng.integers(2_000, 30_001))
        ki = int(rng.integers(4_000, 9_001))
        dist = spot - ki
        if not (-8_000 <= dist <= 20_000):
            continue
        ttm = int(rng.integers(WEEK, 63_072_001))
        nxt = int(rng.integers(0, min(WEEK, ttm) + 1))
        obs = max(1, min(104, 1 + (ttm - nxt) // WEEK))
        rows.append([
            spot, dist,
            int(rng.integers(1_500, 15_001)),
            ki,
            int(rng.integers(9_000, 11_001)),
            int(rng.integers(0, 1_501)),
            ttm, nxt, obs,
            int(rng.integers(0, 2)),
        ])
    return rows


def toy_price(r: list[int]) -> float:
    """Smooth, autocall-shaped stand-in: par + expected coupons, minus a
    knock-in put that grows with vol, time and proximity to the barrier."""
    spot, dist, vol, ki, ac, cpn, ttm, _nxt, obs, flags = r
    t = ttm / 31_536_000
    sig = vol / 10_000
    width = max(sig * np.sqrt(t), 0.05)
    p_ki = 1.0 if flags & 1 else 1 / (1 + np.exp(dist / 10_000 / width * 2.5))
    put = p_ki * max(0.0, 10_000 - spot * 0.9) * 0.9
    p_call = 1 / (1 + np.exp(-(spot - ac) / 10_000 / width * 2.0))
    coupons = cpn * min(obs, 8) * (0.35 + 0.4 * p_call)
    return float(np.clip(10_000 + coupons - put, 0, 30_000))


def fit(x: np.ndarray, y: np.ndarray, widths: list[int], seed: int, steps: int):
    torch.manual_seed(seed)
    mods, prev = [], x.shape[1]
    for w in widths:
        mods += [torch.nn.Linear(prev, w), torch.nn.ReLU()]
        prev = w
    mods.append(torch.nn.Linear(prev, 1))
    net = torch.nn.Sequential(*mods).double()
    opt = torch.optim.Adam(net.parameters(), lr=3e-3)
    xt, yt = torch.from_numpy(x), torch.from_numpy(y)[:, None]
    for step in range(steps):
        idx = torch.randint(0, len(xt), (512,))
        loss = torch.mean((net(xt[idx]) - yt[idx]) ** 2)
        opt.zero_grad()
        loss.backward()
        opt.step()
        if step == steps // 2:
            for g in opt.param_groups:
                g["lr"] = 1e-3
    lin = [m for m in net if isinstance(m, torch.nn.Linear)]
    return [m.weight.detach().numpy().copy() for m in lin], [m.bias.detach().numpy().copy() for m in lin]


def float_forward(ws, bs, x):
    h = x
    for i, (W, b) in enumerate(zip(ws, bs)):
        h = h @ W.T + b
        if i < len(ws) - 1:
            h = np.maximum(h, 0)
    return h[:, 0]


def golden_rows(rng: np.random.Generator) -> list[list[int]]:
    lo = [f.lo for f in pq.FIELDS]
    hi = [f.hi for f in pq.FIELDS]
    mid = [(f.lo + f.hi) // 2 for f in pq.FIELDS]
    rows = [lo, hi, mid]
    # each field at its bounds with the rest at mid: locks the normalization edges
    for i in range(len(pq.FIELDS)):
        for v in (lo[i], hi[i]):
            r = list(mid)
            r[i] = v
            rows.append(r)
    rows += sample_raw(rng, 100 - len(rows))
    return rows


def reject_rows() -> list[dict]:
    """One out-of-range value per bound that the ABI type can express."""
    type_min = {"distToKnockInBps": -(2**31)}
    mid = [(f.lo + f.hi) // 2 for f in pq.FIELDS]
    out = []
    for i, f in enumerate(pq.FIELDS):
        for v in (f.lo - 1, f.hi + 1):
            if v < type_min.get(f.name, 0):
                continue
            r = list(mid)
            r[i] = v
            out.append({"features": dict(zip(pq.FIELD_NAMES, r)), "fieldIndex": i})
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="model/synthetic")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--widths", default="64,48")
    ap.add_argument("--train", type=int, default=60_000)
    ap.add_argument("--steps", type=int, default=6_000)
    ap.add_argument("--bits", type=int, default=16, help="activation/input bits")
    ap.add_argument("--wbits", type=int, default=16, help="weight bits (8 or 16)")
    args = ap.parse_args()

    rng = np.random.default_rng(args.seed)
    widths = [int(w) for w in args.widths.split(",")]
    raws = sample_raw(rng, args.train)
    x = pq.normalized_float_inputs(raws, args.bits)
    offset, scale = 10_000, 5_000.0
    y = (np.array([toy_price(r) for r in raws]) - offset) / scale

    ws, bs = fit(x, y, widths, args.seed, args.steps)
    export = pq.quantize(ws, bs, x[:20_000], price_scale_bps=scale, offset_bps=offset, 
                         activation_bits=args.bits, weight_bits=args.wbits)

    # quantization loss on held-out inputs (float student vs integer student)
    held = sample_raw(np.random.default_rng(args.seed + 1), 5_000)
    f_bps = float_forward(ws, bs, pq.normalized_float_inputs(held, args.bits)) * scale + offset
    q_bps = np.array([pq.forward(export, r) for r in held])
    t_bps = np.array([toy_price(r) for r in held])
    qerr, ferr = np.abs(q_bps - f_bps), np.abs(f_bps - t_bps)

    rows = golden_rows(np.random.default_rng(args.seed + 2))
    vectors = {
        "featureSpecVersion": pq.FEATURE_SPEC_VERSION,
        "weightsHash": export["weightsHash"],
        "modelVectors": [
            {"features": dict(zip(pq.FIELD_NAMES, r)), "expectedPriceBps": pq.forward(export, r)} for r in rows
        ],
        "rejectVectors": reject_rows(),
    }
    for rv in vectors["rejectVectors"]:
        try:
            pq.forward(export, rv["features"])
            raise AssertionError(f"reject vector accepted: {rv}")
        except pq.OutOfRange as e:
            assert e.index == rv["fieldIndex"]

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "student_export.json").write_text(json.dumps(export, indent=1) + "\n")
    (out / "golden_vectors.json").write_text(json.dumps(vectors, indent=1) + "\n")
    report = {
        "note": "SYNTHETIC toy target, not the Monte Carlo teacher. Quantization numbers only.",
        "weightBits": args.wbits,
        "activationBits": args.bits,
        "parameterCount": export["architecture"]["parameterCount"],
        "weightsHash": export["weightsHash"],
        "quantizationErrorBps": {"p50": float(np.median(qerr)), "p99": float(np.percentile(qerr, 99)),
                                 "max": float(qerr.max())},
        "floatFitErrorBps": {"p50": float(np.median(ferr)), "p99": float(np.percentile(ferr, 99)),
                             "max": float(ferr.max())},
    }
    (out / "report.json").write_text(json.dumps(report, indent=1) + "\n")
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
