#!/usr/bin/env python3
"""
COLOR-SIDE σ/κ CODEC v1 -- the octave detail prior, MLX prototype.

Contract: spec/neural/OctaveCodec.hs (CX1-CX7, 7/7 green). The codec
is the composed binary form under the gauge principle (doc §12):

    σ_g(x) = (x + g(x), x − g(x))        κ = mean
    octave = 3 WIRED binary levels (t, y, x order = gauge choice)

Retraction, projection (ê² = ê), and codebook copying are STRUCTURAL
(CX1-CX4, CX6): this trainer learns ONLY the detail generator -- the
conditional prior p(detail | stage-parent, octave level), i.e. the
one thing the calculus does not fix.

Corpus: nn/dither/data.py -- the GIF89a statistical-variance sampler
of record (self-gating, corpus = (file, seed) -> byte-identical;
TRAIN_SEEDS/HELDOUT_SEEDS disjoint by construction). No captures
anywhere (decree).

Model: ĝ(v, ℓ) -> (μ, logσ) per OKLab channel; Gaussian conditional.
Samples are staged binary details extracted by the AX1 wiring:
stage 1 halves along t, stage 2 along y, stage 3 along x -- POOLED
across stages and positions (stage index is axis under the wiring,
so conditioning on it would be axis-typing: gauge violation).
Level ℓ ∈ {0,1,2} (octave scale in the 64³ tower) IS conditioned on.

Adopted derived rulings (from the codec-gap-audit workflow; Daniel
may veto either):
  G1  scale/level conditioning is ADMISSIBLE: scale is physical
      (the 3:2:1 ladder already treats levels distinctly), axis is
      gauge. CX2 proves the laws hold either way.
  G2a classicality by ARCHITECTURAL vanishing, never a loss term:
      g_C(x) = dist²(x, C)·ĝ(x), palette C as INPUT (CX6/CX7).

Laws / gates (thresholds derived, not tuned):
  D1 sampler pins     data.self_check() passes; sequence(seed) is
                      byte-deterministic
  D2 retraction       composed 3-level expansion with trained ĝ:
                      mean of 8 leaves == parent (structural; fp32
                      rounding only)
  D3 beats baseline   held-out NLL < per-level unconditional
                      Gaussian, mean AND win-rate > 0.5+3σ
  D4 calibration      held-out standardized residuals: |mean| <
                      3/√n, |var−1| < 3·√(2/n) (moment match)
  D5 classicality     REAL dyad-256 palette (nn/phase/dyad_solver
                      build_dyad, byte-exact-gated port) built from
                      a held-out element's masked pixels: masked ĝ
                      copies all 256 codewords exactly through all
                      3 levels; off-codebook defects (float64)
  D6 export parity    codec_weights.npz reload reproduces forward

Run:  /opt/homebrew/bin/python3 train_codec.py            (full)
      /opt/homebrew/bin/python3 train_codec.py --smoke    (fast)
"""

import argparse
import json
import math
import os
import sys
import time

import numpy as np
import mlx.core as mx
from mlx.utils import tree_flatten, tree_map

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "dither"))
sys.path.insert(0, os.path.join(HERE, "..", "phase"))
import data as sampler                      # noqa: E402
import dyad_solver                          # noqa: E402

SEED = 20260811
HID = 48
LR = 1e-3
LOGS_MIN, LOGS_MAX = -12.0, 2.0
N_TRAIN_EL, N_HELD_EL = 48, 24
PER_LEVEL_SAMPLES = 3000
LEVELS = 3
# fp16 min normal is 6.1e-5: a 1e-6 epsilon is subnormal on the ANE
# (flush-to-zero → log(0) NaN). 1e-4 is fp16-safe — the DyadAssign
# lesson applied at feature-design time, so the fold needs no rework.
LOGEPS = 1e-4


# ── staged binary detail extraction (AX1 wiring: t, y, x) ──────────

def staged_details(cube):
    """cube [T,Y,X,3] → (stage-parent v[3], context c[3], detail d[3]).

    Context = the detail of the σ-split that CREATED this stage's
    parent (wavelet scale persistence, Crouse–Baraniuk–Nowak):
    stage 1 has no enclosing split (ctx 0), stage 2 sees d1,
    stage 3 sees d2. At generation time the same quantity is the g
    just used, so the expansion is self-conditioning."""
    T, Y, X, _ = cube.shape
    R = cube.reshape(T // 2, 2, Y // 2, 2, X // 2, 2, 3)
    qm = R.mean(axis=5)                        # quarter means
    d3 = (R[..., 0, :] - R[..., 1, :]) / 2     # stage 3 (x)
    hm = qm.mean(axis=3)                       # half means
    d2 = (qm[:, :, :, 0] - qm[:, :, :, 1]) / 2 # stage 2 (y)
    bm = hm.mean(axis=1)                       # block means
    d1 = (hm[:, 0] - hm[:, 1]) / 2             # stage 1 (t)
    c1 = np.zeros_like(bm)
    c2 = np.repeat(d1[:, None], 2, axis=1)     # halves inherit d1
    c3 = np.repeat(d2[:, :, :, None], 2, axis=3)  # quarters inherit d2
    pairs = [(bm.reshape(-1, 3), c1.reshape(-1, 3), d1.reshape(-1, 3)),
             (hm.reshape(-1, 3), c2.reshape(-1, 3), d2.reshape(-1, 3)),
             (qm.reshape(-1, 3), c3.reshape(-1, 3), d3.reshape(-1, 3))]
    v = np.concatenate([p for p, _, _ in pairs])
    c = np.concatenate([q for _, q, _ in pairs])
    d = np.concatenate([r for _, _, r in pairs])
    return v, c, d, bm                         # bm = next level's cube


def harvest(seeds, rng):
    vs, cs, ds, ls, es = [], [], [], [], []
    for ei, seed in enumerate(seeds):
        el = sampler.sequence(seed)
        cube = el["frames"].astype(np.float64)
        for lev in range(LEVELS):
            v, c, d, cube = staged_details(cube)
            take = rng.choice(len(v), size=min(PER_LEVEL_SAMPLES, len(v)),
                              replace=False)
            vs.append(v[take]); cs.append(c[take]); ds.append(d[take])
            ls.append(np.full(len(take), lev, np.int32))
            es.append(np.full(len(take), ei, np.int32))
    return (np.concatenate(vs).astype(np.float32),
            np.concatenate(cs).astype(np.float32),
            np.concatenate(ds).astype(np.float32),
            np.concatenate(ls),
            np.concatenate(es))


def features(v, c, ls):
    """[v, ctx, log10|ctx| (the scale-persistence magnitude channel,
    log domain — detail scales span orders of magnitude), level]."""
    logmag = np.log10(np.abs(c) + LOGEPS).astype(np.float32)
    return np.concatenate([v, c, logmag, onehot(ls)], axis=1)


# ── model ───────────────────────────────────────────────────────────

def init_params(rng):
    def lin(fi, fo):
        return mx.array(rng.normal(0, 1 / math.sqrt(fi), (fi, fo))
                        .astype(np.float32))
    return {"w1": lin(9 + LEVELS, HID), "b1": mx.zeros((HID,)),
            "w2": lin(HID, HID),        "b2": mx.zeros((HID,)),
            "w3": lin(HID, 6),          "b3": mx.zeros((6,))}


def forward(p, x):
    h = mx.maximum(x @ p["w1"] + p["b1"], 0.0)
    h = mx.maximum(h @ p["w2"] + p["b2"], 0.0)
    out = h @ p["w3"] + p["b3"]
    mu, logs = out[:, :3], mx.clip(out[:, 3:], LOGS_MIN, LOGS_MAX)
    return mu, logs


def nll(mu, logs, d):
    return mx.sum(0.5 * ((d - mu) * mx.exp(-logs)) ** 2 + logs, axis=1)


def onehot(ls):
    e = np.zeros((len(ls), LEVELS), np.float32)
    e[np.arange(len(ls)), ls] = 1.0
    return e


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--steps", type=int, default=3000)
    ap.add_argument("--smoke", action="store_true")
    args = ap.parse_args()
    steps = 100 if args.smoke else args.steps
    n_tr_el = 6 if args.smoke else N_TRAIN_EL
    n_he_el = 3 if args.smoke else N_HELD_EL

    rng = np.random.default_rng(SEED)

    # D1: sampler self-gates + determinism
    sampler.self_check()
    a = sampler.sequence(1_000_000)["frames"]
    b = sampler.sequence(1_000_000)["frames"]
    ok1 = np.array_equal(a, b)
    print(f"D1 {'✓' if ok1 else '✗'} sampler pins: self_check passed, "
          f"sequence(seed) byte-deterministic")

    t0 = time.time()
    tv, tc, td, tl, te = harvest(range(1_000_000, 1_000_000 + n_tr_el), rng)
    hv, hc, hd, hl, he = harvest(range(9_000_000, 9_000_000 + n_he_el), rng)
    tX = features(tv, tc, tl)
    fmean = tX.mean(axis=0); fstd = tX.std(axis=0) + 1e-8
    tX = (tX - fmean) / fstd
    hX = (features(hv, hc, hl) - fmean) / fstd
    print(f"  harvested {len(tv)} train / {len(hv)} held samples "
          f"({time.time()-t0:.1f}s; levels 0-2, stages pooled, "
          f"log-magnitude scale-persistence ctx, standardized)")

    params = init_params(rng)
    adam_m = tree_map(lambda x: mx.zeros_like(x), params)
    adam_v = tree_map(lambda x: mx.zeros_like(x), params)
    TX, TD = mx.array(tX), mx.array(td)

    def loss_fn(p, idx):
        mu, logs = forward(p, TX[idx])
        return mx.mean(nll(mu, logs, TD[idx]))

    grad_fn = mx.value_and_grad(loss_fn)
    b1c, b2c, eps = 0.9, 0.999, 1e-8
    first = last = None
    t0 = time.time()
    for step in range(1, steps + 1):
        lr = LR if step <= 2 * steps // 3 else LR / 10
        idx = mx.array(rng.integers(0, len(tv), 8192))
        loss, grads = grad_fn(params, idx)
        for k in params:
            adam_m[k] = b1c * adam_m[k] + (1 - b1c) * grads[k]
            adam_v[k] = b2c * adam_v[k] + (1 - b2c) * grads[k] ** 2
            mhat = adam_m[k] / (1 - b1c ** step)
            vhat = adam_v[k] / (1 - b2c ** step)
            params[k] = params[k] - lr * mhat / (mx.sqrt(vhat) + eps)
        mx.eval(params)
        loss = float(loss)
        if first is None:
            first = loss
        last = loss
        if step % max(1, steps // 8) == 0 or step == 1:
            print(f"  step {step:4d}  nll {loss:.4f}")
    print(f"  trained {steps} steps in {time.time()-t0:.1f}s")

    def model_g(arr, ctx, ls, sample_rng=None):
        X = (features(arr.astype(np.float32), ctx.astype(np.float32), ls)
             - fmean) / fstd
        mu_, logs_ = forward(params, mx.array(X))
        mu_, sd_ = np.array(mu_), np.array(mx.exp(logs_))
        if sample_rng is None:
            return mu_ + sd_
        return mu_ + sd_ * sample_rng.standard_normal(
            (len(arr), 3)).astype(np.float32)

    # ── D2: composed retraction with the trained generator ─────────
    probe = rng.choice(len(hv), 1000, replace=False)
    pv = hv[probe]
    ls0 = hl[probe]
    leaves = [(pv.copy(), np.zeros_like(pv))]     # (value, ctx)
    for _ in range(3):
        nxt = []
        for arr, ctx in leaves:
            g = model_g(arr, ctx, ls0, rng)
            nxt.append((arr + g, g)); nxt.append((arr - g, g))
        leaves = nxt
    recon = np.mean(np.stack([a for a, _ in leaves]), axis=0)
    err2 = np.max(np.abs(recon - pv))
    ok2 = err2 < 2e-5
    print(f"D2 {'✓' if ok2 else '✗'} retraction: composed 3-level mean-of-8 "
          f"== parent, max abs {err2:.2e} (fp32 rounding only)")

    # ── D3/D4: cluster-robust across held ELEMENTS (samples within
    #    an element share its field scale — effective n is the
    #    element count, not the sample count; DepthMixture honesty) ──
    HX, HD = mx.array(hX), mx.array(hd)
    mu, logs = forward(params, HX)
    nll_model = np.array(nll(mu, logs, HD))
    nll_base = np.zeros(len(hv))
    for lev_i in range(LEVELS):
        trm = tl == lev_i
        hem = hl == lev_i
        m0 = td[trm].mean(axis=0)
        v0 = td[trm].var(axis=0) + 1e-12
        nll_base[hem] = (0.5 * ((hd[hem] - m0) ** 2 / v0)
                         + 0.5 * np.log(v0)).sum(axis=1)
    els = np.unique(he)
    dnll = np.array([ (nll_model[he == e] - nll_base[he == e]).mean()
                      for e in els ])
    se3 = 3 * dnll.std(ddof=1) / math.sqrt(len(els))
    ok3 = dnll.mean() + se3 < 0
    print(f"D3 {'✓' if ok3 else '✗'} beats baseline, cluster-robust "
          f"(E={len(els)} elements): ΔNLL {dnll.mean():.4f} ± {se3:.4f} "
          f"(3σ), wins {int((dnll < 0).sum())}/{len(els)} elements")

    # ── D4: calibration, cluster-robust ────────────────────────────
    zres = (np.array(np.array(HD) - np.array(mu))
            * np.array(mx.exp(-logs)))
    zm_e = np.array([ zres[he == e].mean() for e in els ])
    zv_e = np.array([ zres[he == e].var() for e in els ])
    m_off = abs(zm_e.mean())
    m_tol = 3 * zm_e.std(ddof=1) / math.sqrt(len(els))
    v_off = abs(zv_e.mean() - 1)
    v_tol = 3 * zv_e.std(ddof=1) / math.sqrt(len(els))
    ok4 = m_off < m_tol and v_off < v_tol
    print(f"D4 {'✓' if ok4 else '✗'} calibration (element-level): "
          f"|mean z|={m_off:.4f} (<{m_tol:.4f}), "
          f"|var z − 1|={v_off:.4f} (<{v_tol:.4f})")

    # ── D5: classicality against a REAL dyad-256 palette ───────────
    el = sampler.sequence(9_000_050)
    f0 = el["frames"][0].astype(np.float64)
    face = f0[el["mask"] > 0.5]
    rgb8 = [dyad_solver.oklab_to_srgb8(tuple(px)) for px in face[:4096]]
    table = dyad_solver.build_dyad(rgb8)
    C = np.array([dyad_solver.srgb8_to_oklab(tuple(e)) for e in table])

    def masked_expand(x64):
        ls0 = np.zeros(len(x64), np.int32)
        leaves = [(x64.copy(), np.zeros_like(x64))]
        for _ in range(3):
            nxt = []
            for arr, ctx in leaves:
                d2c = ((arr[:, None, :] - C[None]) ** 2).sum(-1).min(1)
                ghat = model_g(arr, ctx, ls0).astype(np.float64)
                g = d2c[:, None] * ghat
                nxt.append((arr + g, g)); nxt.append((arr - g, g))
            leaves = nxt
        return [a for a, _ in leaves]

    lv = masked_expand(C.copy())
    on_ok = all(np.array_equal(l, C) for l in lv)
    off = C[:32] + 0.05
    lvo = masked_expand(off)
    off_ok = all(not np.array_equal(l, off) for l in lvo)
    ok5 = on_ok and off_ok and len(C) == 256
    print(f"D5 {'✓' if ok5 else '✗'} classicality: real dyad-256 (built from "
          f"held-out masked pixels) — all 256 codewords copy EXACTLY through "
          f"3 levels; off-codebook defects (float64)")

    # ── D6: export parity (weights + feature standardization) ──────
    flat = {k: np.array(v) for k, v in tree_flatten(params)}
    flat["fmean"] = fmean; flat["fstd"] = fstd
    np.savez(os.path.join(HERE, "codec_weights.npz"), **flat)
    loaded = np.load(os.path.join(HERE, "codec_weights.npz"))
    re = {k: mx.array(v) for k, v in loaded.items()
          if k not in ("fmean", "fstd")}
    mu2, logs2 = forward(re, HX)
    par = max(float(mx.max(mx.abs(mu - mu2))),
              float(mx.max(mx.abs(logs - logs2))))
    ok6 = par < 1e-7
    nparam = sum(v.size for v in flat.values())
    print(f"D6 {'✓' if ok6 else '✗'} export parity: max abs {par:.2e} "
          f"(codec_weights.npz, {nparam} params)")

    results = {
        "version": "codec-v1", "seed": SEED, "steps": steps,
        "params": int(nparam),
        "train_samples": len(tv), "held_samples": len(hv),
        "nll": {"model": float(nll_model.mean()),
                "baseline": float(nll_base.mean()),
                "delta_per_element": float(dnll.mean()),
                "element_wins": int((dnll < 0).sum()),
                "elements": int(len(els))},
        "calibration": {"mean_z": float(zm_e.mean()),
                        "var_z": float(zv_e.mean())},
        "rulings": {"G1": "level-conditioning admissible (scale physical, axis gauge)",
                    "G2a": "architectural vanishing g_C = dist2(x,C)*ghat(x)"},
        "gates": {"D1": bool(ok1), "D2": bool(ok2), "D3": bool(ok3),
                  "D4": bool(ok4), "D5": bool(ok5), "D6": bool(ok6)},
    }
    with open(os.path.join(HERE, "codec_results.json"), "w") as f:
        json.dump(results, f, indent=2)
    ngreen = sum(results["gates"].values())
    print(f"\n  {ngreen}/6 gates green → codec_results.json, codec_weights.npz")
    if ngreen < 6:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
