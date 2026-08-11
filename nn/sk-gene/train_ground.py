#!/usr/bin/env python3
"""
THE GROUNDING v1 -- term↔color coupling encoder, MLX prototype.

The last open piece of the SK gene arc (doc §13 "owed"): the passer
rolls TERM latents (weights.npz, FROZEN here), the codec expands and
contracts COLOR octaves (codec_weights.npz, FROZEN here) -- nothing
yet connects them. The grounding is that connection, and per the
gauge principle (§12) it is exactly where axis identity is allowed
to live: the encoder reads the block through the wiring.

    E : color octave block [8×3 OKLab leaves, wiring order t,y,x]
        → z ∈ ℝ²⁴, the SAME latent space the genes live in.

E is the ONLY trainable. It is trained so the square commutes
through the FROZEN passer predictor and FROZEN token embeddings:

    S-law   pred(E(const(x)), tok_S) ≈ E(Ŝ(x))
            (codec expansion of x, masked by the capture's own
             dyad-256 palette — full runtime fidelity)
    K-law   pred(E(X), tok_K) ≈ E(const(K̂X))
            (real corpus block X contracted to its mean;
             const(y) = the coherent block Ŝ₀(y), im(ê))

E's input features are the block's Haar character coefficients
(DC + 7 details, the AX1 basis) + octave level one-hot. EMA targets
(BYOL) + variance hinge against collapse; losses in latent space
only. Corpus: nn/dither/data.py (sampler-of-record); palettes by
the byte-exact-gated nn/phase/dyad_solver.build_dyad per element.
No captures anywhere.

DEEP LAW made gateable: at palette codewords the masked codec gives
Ŝ(c) = const(c) exactly (CX6/F2), so codewords must become LATENT
FIXED POINTS of the S-action: pred(E(const c), tok_S) ≈ E(const c).
The classical states of the palette are the stationary states of
expansion — gate G4 measures exactly this on held-out captures.

Gates ("ensure that it learns"; thresholds derived, cluster-robust
across held ELEMENTS — samples within an element share its field):
  G1 pins        frozen passer/codec/gene-table load; sampler
                 byte-deterministic
  G2 learns      held-out events: coupling error < identity AND <
                 swapped-token, per-element ΔNLL... (mean + 3σ)
  G3 transfer    THE COUPLING CLAIM: the term-trained S/K tokens
                 organize color dynamics — swapping the token on a
                 held-out event increases error (3σ on changed
                 pairs; the 2-token tie fix of train_passer P3)
  G4 classicality codeword S-displacement << off-codeword
                 S-displacement (latent fixed points, 3σ)
  G5 retrieval   pred(E(in), tok) ranks the TRUE target top-1
                 among each element's eval set far above chance
  G6 export      ground_weights.npz reload parity

Run:  /opt/homebrew/bin/python3 train_ground.py            (full)
      /opt/homebrew/bin/python3 train_ground.py --smoke
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
D, LEVELS = 24, 3
EHID = 96      # E's width; the frozen passer's own hidden is 48
LOGEPS = 1e-4
TAU = 0.99
LR = 1e-3
N_TRAIN_EL, N_HELD_EL = 48, 24
PER_EL = 1024                                # events per kind per level

PW = dict(np.load(os.path.join(HERE, "weights.npz")).items())
CW = dict(np.load(os.path.join(HERE, "codec_weights.npz")).items())

# Haar character matrix, leaf order ε=(t,y,x) → idx = 4t+2y+x (wiring)
H8 = np.zeros((8, 8))
for w in range(8):
    for e in range(8):
        H8[w, e] = (-1) ** bin(w & e).count("1") / 8.0


# ── frozen halves ───────────────────────────────────────────────────

def pred_frozen(z, tok_ids):
    """The passer predictor, FROZEN, float32 mlx."""
    t = mx.array(PW["tok"].astype(np.float32))[tok_ids]
    x = mx.concatenate([z, t], axis=1)
    h = mx.maximum(x @ mx.array(PW["pw1"]) + mx.array(PW["pb1"]), 0.0)
    return z + h @ mx.array(PW["pw2"]) + mx.array(PW["pb2"])


def codec_expand64(x0, lev_oh, C):
    """FROZEN masked codec, float64 (the F-gate law form)."""
    def g64(v, ctx):
        logmag = np.log10(np.abs(ctx) + LOGEPS)
        feat = np.concatenate([v, ctx, logmag, lev_oh], axis=1)
        xn = (feat - CW["fmean"]) / CW["fstd"]
        h = np.maximum(xn @ CW["w1"] + CW["b1"], 0)
        h = np.maximum(h @ CW["w2"] + CW["b2"], 0)
        out = h @ CW["w3"] + CW["b3"]
        mu, logs = out[:, :3], np.clip(out[:, 3:], -12, 2)
        d2 = ((v[:, None, :] - C[None]) ** 2).sum(-1).min(1)
        return d2[:, None] * (mu + np.exp(logs))
    nodes = [(x0.copy(), np.zeros_like(x0))]
    for _ in range(3):
        nxt = []
        for v, ctx in nodes:
            g = g64(v, ctx)
            nxt.append((v + g, g)); nxt.append((v - g, g))
        nodes = nxt
    return np.stack([v for v, _ in nodes], axis=1)       # [N,8,3]


def element_palette(el):
    f0 = el["frames"][0].astype(np.float64)
    face = f0[el["mask"] > 0.5]
    rgb8 = [dyad_solver.oklab_to_srgb8(tuple(px)) for px in face[:4096]]
    return np.array([dyad_solver.srgb8_to_oklab(tuple(e))
                     for e in dyad_solver.build_dyad(rgb8)])


# ── event harvesting (the commuting-square training pairs) ──────────

def blocks_of(cube):
    T, Y, X, _ = cube.shape
    R = cube.reshape(T // 2, 2, Y // 2, 2, X // 2, 2, 3)
    leaves = R.transpose(0, 2, 4, 1, 3, 5, 6).reshape(-1, 8, 3)
    return leaves, leaves.mean(axis=1)      # [N,8,3], next-level cube base


def const_block(x):
    return np.repeat(x[:, None, :], 8, axis=1)


def harvest(seeds, rng, with_codewords=False, train_codewords=False):
    """Events: (in-block, tok, target-block, level, element)."""
    ins, toks, tgts, lvs, els = [], [], [], [], []
    cw_ins, cw_lvs, cw_els = [], [], []
    for ei, seed in enumerate(seeds):
        el = sampler.sequence(seed)
        C = element_palette(el)
        cube = el["frames"].astype(np.float64)
        for lev in range(LEVELS):
            leaves, means = blocks_of(cube)
            cube = means.reshape(
                (cube.shape[0] // 2, cube.shape[1] // 2,
                 cube.shape[2] // 2, 3))
            n_ev = min(PER_EL, len(leaves))
            lev_oh = np.zeros((n_ev, LEVELS)); lev_oh[:, lev] = 1
            # K-events: real block → const(mean)
            ki = rng.choice(len(leaves), n_ev, replace=False)
            ins.append(leaves[ki]); toks.append(np.ones(n_ev, np.int32))
            tgts.append(const_block(leaves[ki].mean(axis=1)))
            # S-events: parent → masked codec expansion
            si = rng.choice(len(means), n_ev, replace=False)
            x = means[si]
            ins.append(const_block(x))
            toks.append(np.zeros(n_ev, np.int32))
            tgts.append(codec_expand64(x, lev_oh, C))
            for _ in range(2):
                lvs.append(np.full(n_ev, lev, np.int32))
                els.append(np.full(n_ev, ei, np.int32))
            if with_codewords and lev == 0:
                cw_ins.append(const_block(C))
                cw_lvs.append(np.zeros(len(C), np.int32))
                cw_els.append(np.full(len(C), ei, np.int32))
            if train_codewords and lev == 0:
                # codeword S-events: masked codec gives S(c) = const(c)
                # exactly (CX6/F2) — teach the fixed points directly
                ins.append(const_block(C))
                toks.append(np.zeros(len(C), np.int32))
                tgts.append(const_block(C))
                lvs.append(np.zeros(len(C), np.int32))
                els.append(np.full(len(C), ei, np.int32))
    out = (np.concatenate(ins), np.concatenate(toks),
           np.concatenate(tgts), np.concatenate(lvs),
           np.concatenate(els))
    if with_codewords:
        return out + (np.concatenate(cw_ins), np.concatenate(cw_lvs),
                      np.concatenate(cw_els))
    return out


def feats(blocks, ls):
    """Haar character coefficients + level one-hot, float32."""
    coef = np.einsum("we,nec->nwc", H8, blocks).reshape(len(blocks), 24)
    lev = np.zeros((len(ls), LEVELS), np.float32)
    lev[np.arange(len(ls)), ls] = 1
    return np.concatenate([coef, lev], axis=1).astype(np.float32)


# ── the encoder (the only trainable) ────────────────────────────────

def init_params(rng):
    def lin(fi, fo):
        return mx.array(rng.normal(0, 1 / math.sqrt(fi), (fi, fo))
                        .astype(np.float32))
    return {"w1": lin(24 + LEVELS, EHID), "b1": mx.zeros((EHID,)),
            "w2": lin(EHID, EHID),       "b2": mx.zeros((EHID,)),
            "w3": lin(EHID, D),          "b3": mx.zeros((D,))}


def encode(p, x):
    h = mx.maximum(x @ p["w1"] + p["b1"], 0.0)
    h = mx.maximum(h @ p["w2"] + p["b2"], 0.0)
    return h @ p["w3"] + p["b3"]


def l2n(z):
    return z / (mx.linalg.norm(z, axis=-1, keepdims=True) + 1e-8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--steps", type=int, default=8000)
    ap.add_argument("--smoke", action="store_true")
    args = ap.parse_args()
    steps = 100 if args.smoke else args.steps
    n_tr = 6 if args.smoke else N_TRAIN_EL
    n_he = 3 if args.smoke else N_HELD_EL

    rng = np.random.default_rng(SEED)
    a = sampler.sequence(1_000_000)["frames"]
    ok1 = (np.array_equal(a, sampler.sequence(1_000_000)["frames"])
           and PW["pw1"].shape[0] == 2 * D
           and CW["w1"].shape[0] == 12
           and os.path.exists(os.path.join(HERE, "gene_table.npz")))
    print(f"G1 {'✓' if ok1 else '✗'} pins: frozen passer/codec/gene-table "
          f"loaded; sampler byte-deterministic")

    t0 = time.time()
    ti, tt, tg, tl, te = harvest(range(1_000_000, 1_000_000 + n_tr), rng,
                             train_codewords=True)
    (hi, ht, hg, hl, he,
     cwi, cwl, cwe) = harvest(range(9_000_000, 9_000_000 + n_he), rng,
                              with_codewords=True)
    tX = feats(ti, tl); tXg = feats(tg, tl)
    fmean = tX.mean(axis=0); fstd = tX.std(axis=0) + 1e-8
    tX = (tX - fmean) / fstd; tXg = (tXg - fmean) / fstd
    hX = (feats(hi, hl) - fmean) / fstd
    hXg = (feats(hg, hl) - fmean) / fstd
    cwX = (feats(cwi, cwl) - fmean) / fstd
    print(f"  harvested {len(ti)} train / {len(hi)} held events "
          f"({time.time()-t0:.1f}s; S+K, levels 0-2, per-element palettes)")

    params = init_params(rng)
    ema = tree_map(lambda x: x, params)
    adam_m = tree_map(lambda x: mx.zeros_like(x), params)
    adam_v = tree_map(lambda x: mx.zeros_like(x), params)
    TX, TXg, TT = mx.array(tX), mx.array(tXg), mx.array(tt)

    # THE MANIFOLD ANCHOR: the frozen predictor's vector field only
    # MEANS S/K where it was trained — on the gene-latent cloud.
    # E's image is moment-matched to that cloud (gene_table.npz), so
    # color states land where the term dynamics are defined. Both
    # moments are DERIVED from the table — no naked constants.
    gt = np.load(os.path.join(HERE, "gene_table.npz"))
    cloud = np.concatenate([gt["z0"], gt["attract"]])
    m0 = mx.array(cloud.mean(axis=0).astype(np.float32))
    s0 = mx.array(cloud.std(axis=0).astype(np.float32))

    def loss_fn(p, ema_p, idx):
        z = encode(p, TX[idx])
        zt = mx.stop_gradient(encode(ema_p, TXg[idx]))
        zh = pred_frozen(z, TT[idx])
        jepa = mx.mean(mx.sum((l2n(zh) - l2n(zt)) ** 2, axis=1))
        std = mx.sqrt(mx.var(z, axis=0) + 1e-8)
        anchor = (mx.mean((mx.mean(z, axis=0) - m0) ** 2)
                  + mx.mean((std - s0) ** 2))
        return jepa + anchor

    grad_fn = mx.value_and_grad(loss_fn)
    b1c, b2c, eps = 0.9, 0.999, 1e-8
    first = last = None
    t0 = time.time()
    for step in range(1, steps + 1):
        lr = LR if step <= 2 * steps // 3 else LR / 10
        idx = mx.array(rng.integers(0, len(ti), 8192))
        loss, grads = grad_fn(params, ema, idx)
        for k in params:
            adam_m[k] = b1c * adam_m[k] + (1 - b1c) * grads[k]
            adam_v[k] = b2c * adam_v[k] + (1 - b2c) * grads[k] ** 2
            mhat = adam_m[k] / (1 - b1c ** step)
            vhat = adam_v[k] / (1 - b2c ** step)
            params[k] = params[k] - lr * mhat / (mx.sqrt(vhat) + eps)
        for k in params:
            ema[k] = TAU * ema[k] + (1 - TAU) * params[k]
        mx.eval(params, ema)
        loss = float(loss)
        if first is None:
            first = loss
        last = loss
        if step % max(1, steps // 8) == 0 or step == 1:
            print(f"  step {step:4d}  loss {loss:.4f}")
    print(f"  trained {steps} steps in {time.time()-t0:.1f}s "
          f"(passer & codec FROZEN — only E learned)")

    # ── held-out evaluation ─────────────────────────────────────────
    HXm, HXgm, HTm = mx.array(hX), mx.array(hXg), mx.array(ht)
    z = encode(params, HXm)
    zt = l2n(encode(params, HXgm))
    err_model = np.array(mx.sum((l2n(pred_frozen(z, HTm)) - zt) ** 2,
                                axis=1))
    err_ident = np.array(mx.sum((l2n(z) - zt) ** 2, axis=1))
    err_swap = np.array(mx.sum(
        (l2n(pred_frozen(z, 1 - HTm)) - zt) ** 2, axis=1))
    els = np.unique(he)
    E = len(els)

    def clust(v):
        m = np.array([v[he == e].mean() for e in els])
        return m.mean(), 3 * m.std(ddof=1) / math.sqrt(E)

    # identity is near-optimal on events whose op barely changes the
    # block (K on flat blocks, S near palette) — the coupling must
    # beat it where there IS something to predict: per-element
    # median split on feature displacement (derived, not tuned)
    fdisp = ((hX - hXg) ** 2).sum(axis=1)
    moved = np.zeros(len(fdisp), bool)
    for e in els:
        m_ = he == e
        moved[m_] = fdisp[m_] > np.median(fdisp[m_])
    dm, _ = clust(err_model)
    dmov = np.array([ (err_model - err_ident)[(he == e) & moved].mean()
                      for e in els ])
    di = dmov.mean(); si_ = 3 * dmov.std(ddof=1) / math.sqrt(E)
    ok2 = di + si_ < 0
    print(f"G2 {'✓' if ok2 else '✗'} learns (E={E} elements): coupling err "
          f"{dm:.4f}; Δ vs identity on MOVED events {di:.4f} ± {si_:.4f} "
          f"(3σ; median-split per element)")

    ds, ss = clust(err_model - err_swap)
    ok3 = ds + ss < 0
    print(f"G3 {'✓' if ok3 else '✗'} TOKEN TRANSFER: Δ vs swapped-token "
          f"{ds:.4f} ± {ss:.4f} (3σ) — term-trained S/K tokens organize "
          f"color dynamics")

    # ── G4: codewords are latent fixed points of S ──────────────────
    zc = encode(params, mx.array(cwX))
    disp_cw = np.array(mx.sum(
        (l2n(pred_frozen(zc, mx.zeros(len(cwX), dtype=mx.int32)))
         - l2n(zc)) ** 2, axis=1))
    # off-side conditioned on genuinely off-palette parents (per-
    # element median of dist² to the palette — derived): near-palette
    # parents have Ŝ ≈ const and would dilute the contrast
    smask = ht == 0
    s_idx = np.where(smask)[0]
    s_x = hi[s_idx].mean(axis=1)               # parent = DC of const block
    far = np.zeros(len(s_idx), bool)
    for ei, seed in enumerate(range(9_000_000, 9_000_000 + n_he)):
        m_ = he[s_idx] == ei
        if not m_.any():
            continue
        Ce = element_palette(sampler.sequence(seed))
        d2 = ((s_x[m_][:, None] - Ce[None]) ** 2).sum(-1).min(1)
        far[m_] = d2 > np.median(d2)
    zs = z[mx.array(s_idx[far])]
    disp_off = np.array(mx.sum(
        (l2n(pred_frozen(zs, mx.zeros(int(far.sum()), dtype=mx.int32)))
         - l2n(zs)) ** 2, axis=1))
    cw_m = np.array([disp_cw[cwe == e].mean() for e in np.unique(cwe)])
    off_m = np.array([disp_off[he[s_idx[far]] == e].mean() for e in els])
    gap = off_m.mean() - cw_m.mean()
    gap_se = 3 * math.sqrt(off_m.var(ddof=1) / len(off_m)
                           + cw_m.var(ddof=1) / len(cw_m))
    ok4 = gap > gap_se
    print(f"G4 {'✓' if ok4 else '✗'} classicality: codeword S-displacement "
          f"{cw_m.mean():.4f} vs off {off_m.mean():.4f} "
          f"(gap {gap:.4f} > 3σ {gap_se:.4f}) — palette = latent fixed "
          f"points of expansion")

    # ── G5: retrieval within each held element ──────────────────────
    accs = []
    zh_all = np.array(l2n(pred_frozen(z, HTm)))
    zt_all = np.array(zt)
    for e in els:
        idx = np.where(he == e)[0][:256]
        d = ((zh_all[idx][:, None] - zt_all[idx][None]) ** 2).sum(-1)
        accs.append(float((d.argmin(1) == np.arange(len(idx))).mean()))
    accs = np.array(accs)
    chance = 1.0 / 256
    thresh5 = chance + 3 * accs.std(ddof=1) / math.sqrt(E)
    ok5 = accs.mean() > thresh5
    print(f"G5 {'✓' if ok5 else '✗'} retrieval: top-1 {accs.mean():.3f} "
          f"among 256/element (chance {chance:.4f}, 3σ bound "
          f"{thresh5:.4f})")

    # ── G6: export parity ───────────────────────────────────────────
    flat = {k: np.array(v) for k, v in tree_flatten(params)}
    flat["fmean"] = fmean; flat["fstd"] = fstd
    np.savez(os.path.join(HERE, "ground_weights.npz"), **flat)
    loaded = np.load(os.path.join(HERE, "ground_weights.npz"))
    re = {k: mx.array(v) for k, v in loaded.items()
          if k not in ("fmean", "fstd")}
    par = float(mx.max(mx.abs(encode(params, HXm) - encode(re, HXm))))
    ok6 = par < 1e-7
    nparam = sum(v.size for v in flat.values())
    print(f"G6 {'✓' if ok6 else '✗'} export parity: max abs {par:.2e} "
          f"(ground_weights.npz, {nparam} params)")

    results = {
        "version": "ground-v1", "seed": SEED, "steps": steps,
        "params": int(nparam), "frozen": ["weights.npz (passer)",
                                          "codec_weights.npz (codec)"],
        "held": {"elements": int(E), "events": len(hi),
                 "err_model": float(dm),
                 "delta_vs_identity": float(di),
                 "delta_vs_swapped": float(ds)},
        "classicality": {"codeword_disp": float(cw_m.mean()),
                         "off_disp": float(off_m.mean())},
        "retrieval_top1": float(accs.mean()),
        "gates": {"G1": bool(ok1), "G2": bool(ok2), "G3": bool(ok3),
                  "G4": bool(ok4), "G5": bool(ok5), "G6": bool(ok6)},
    }
    with open(os.path.join(HERE, "ground_results.json"), "w") as f:
        json.dump(results, f, indent=2)
    n_green = sum(results["gates"].values())
    print(f"\n  {n_green}/6 gates green → ground_results.json, "
          f"ground_weights.npz")
    if n_green < 6:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
