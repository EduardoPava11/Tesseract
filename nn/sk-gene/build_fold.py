#!/usr/bin/env python3
"""
THE FOLD -- SK gene passer + color codec as fused ANE graphs.

House pattern: nn/ane-loop/build_model.py verbatim (MIL builder,
weights folded as constants, fp16, fixed trip counts, gated against
the float64 law on this Mac before anything ships).

Two mlpackages + one data table:

  SKGenePasser.mlpackage   the 16-step gene rollout, FULLY UNROLLED
                           (UNROLL=16 is DERIVED: max halting time 15
                           + one idle step, spec SK5; halted lanes
                           idle via the act mask, spec SK9 — every
                           lane runs the same program, no
                           data-dependent control flow).
        inputs   z0     [B, 24]      cell latent (from gene_table)
                 tokvec [B, 16, 24]  per-step action-token embedding
                 act    [B, 16, 1]   1 = step active, 0 = idle
        output   z16    [B, 24]      the landed latent
        folded   pw1 pb1 pw2 pb2 (the predictor -- 2,472 params)

  SKGeneCodec.mlpackage    the masked 3-level octave expansion
                           (OctaveCodec.hs CX1-CX7 contract).
        inputs   x0      [B, 3]      parent OKLab
                 lev     [B, 3]      octave-level one-hot
                 palette [256, 3]    the capture's dyad-256 (INPUT,
                                     never weights -- CX6/CX7)
        output   leaves  [B, 8, 3]
        folded   w1 b1 w2 b2 w3 b3 fmean fstd (3,294 params)
        law      dist2 uses the DIFFERENCE form (x-c)^2, so a
                 codeword's row is EXACTLY zero even in fp16 --
                 classicality survives the engine bit-exactly.

  gene_table.npz           the compile-time gene data (doc section 7):
                           enc(gene) fp32 [16896, 24] (float64 DAG
                           encoder), token ids int8 [16896, 16],
                           act mask [16896, 16], haltTime, nfId,
                           attractor latents [2692, 24], the 2-row
                           token embedding table, phase class.

Gates (derived thresholds; XP2 near-tie law for decisions):
  F1 passer parity     CoreML fp16 rollout vs float64 law on the
                       held-out genes: nearest-attractor decisions
                       agree except where the margin is below the
                       measured fp16 distance perturbation (near-tie)
  F2 codec classicality all 256 real-palette codewords copy EXACTLY
                       through the fp16 graph (difference-form law)
  F3 codec retraction  in-graph mean-of-8 == x0 within the machine
                       bound 16*2^-11 (3 levels of fp16 rounding)
  F4 codec parity      off-codebook leaves vs float64 law (reported)

Run:  /opt/homebrew/bin/python3 build_fold.py
"""

import json
import math
import os
import sys
import time

import numpy as np
import coremltools as ct
from coremltools.converters.mil import Builder as mb

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "dither"))
sys.path.insert(0, os.path.join(HERE, "..", "phase"))
import data as sampler                      # noqa: E402
import dyad_solver                          # noqa: E402

B, D, T, HID, LEVELS = 4096, 24, 16, 48, 3
BG = 512                                    # rung-16 blocks per capture
LOGEPS = 1e-4                               # fp16-safe (train_codec.py)
LN10 = math.log(10.0)

PW = {k: v for k, v in np.load(os.path.join(HERE, "weights.npz")).items()}
CW = {k: v for k, v in
      np.load(os.path.join(HERE, "codec_weights.npz")).items()}
GRW = {k: v for k, v in
       np.load(os.path.join(HERE, "ground_weights.npz")).items()}

# Haar character matrix, leaf order ε=(t,y,x) → idx = 4t+2y+x
H8 = np.zeros((8, 8), np.float32)
for w in range(8):
    for e in range(8):
        H8[w, e] = (-1) ** bin(w & e).count("1") / 8.0


# ── float64 term encoder (the passer's compile-time half) ───────────

def parse(s):
    pos = 0
    def atom():
        nonlocal pos
        c = s[pos]; pos += 1
        node = c
        while pos < len(s) and s[pos] == "[":
            pos += 1
            arg = atom()
            assert s[pos] == "]"; pos += 1
            node = (node, arg)
        return node
    r = atom()
    assert pos == len(s)
    return r


def enc64(term, memo):
    if term in memo:
        return memo[term]
    if term == "s":
        v = PW["e_s"].astype(np.float64)
    elif term == "k":
        v = PW["e_k"].astype(np.float64)
    else:
        l = enc64(term[0], memo); r = enc64(term[1], memo)
        x = np.concatenate([l, r, l * r])
        h = np.maximum(x @ PW["aw1"].astype(np.float64)
                       + PW["ab1"].astype(np.float64), 0)
        v = h @ PW["aw2"].astype(np.float64) + PW["ab2"].astype(np.float64)
    memo[term] = v
    return v


def pred64(z, tok_id):
    t = PW["tok"].astype(np.float64)[tok_id]
    x = np.concatenate([z, t])
    h = np.maximum(x @ PW["pw1"].astype(np.float64)
                   + PW["pb1"].astype(np.float64), 0)
    return z + h @ PW["pw2"].astype(np.float64) + PW["pb2"].astype(np.float64)


def build_gene_table():
    pairs = []
    with open(os.path.join(HERE, "corpus", "pairs.jsonl")) as f:
        for line in f:
            pairs.append(json.loads(line))
    genes = {}
    for p in pairs:
        g = genes.setdefault(p["geneId"], {
            "gene": p["gene"], "toks": np.zeros(T, np.int8),
            "act": np.zeros(T, np.float32), "halt": -1, "nf": -1,
            "nfterm": None})
        s = p["step"]
        if s < T:
            g["toks"][s] = 0 if p["sym"] == "S" else 1
            g["act"][s] = 1.0
        if p["fate"] == "halt":
            g["halt"] = max(g["halt"], p["step"] + 1)
            g["nf"] = p["nfId"]
            g["nfterm"] = p["post"]
    memo = {}
    n = max(genes) + 1
    z0 = np.zeros((n, D), np.float32)
    toks = np.zeros((n, T), np.int8)
    act = np.zeros((n, T), np.float32)
    halt = np.full(n, -1, np.int32)
    nf = np.full(n, -1, np.int32)
    nfterms = {}
    for gid, g in genes.items():
        z0[gid] = enc64(parse(g["gene"]), memo).astype(np.float32)
        toks[gid], act[gid] = g["toks"], g["act"]
        halt[gid], nf[gid] = g["halt"], g["nf"]
        if g["nf"] >= 0:
            nfterms[g["nf"]] = g["nfterm"]
    n_nf = max(nfterms) + 1
    attract = np.zeros((n_nf, D), np.float32)
    for nid, term in nfterms.items():
        attract[nid] = enc64(parse(term), memo).astype(np.float32)
    return z0, toks, act, halt, nf, attract, genes


# ── the two MIL programs ────────────────────────────────────────────

@mb.program(input_specs=[mb.TensorSpec(shape=(B, D)),
                         mb.TensorSpec(shape=(B, T, D)),
                         mb.TensorSpec(shape=(B, T, 1))])
def sk_passer(z0, tokvec, act):
    pw1 = PW["pw1"].astype(np.float32)
    pb1 = PW["pb1"].astype(np.float32)
    pw2 = PW["pw2"].astype(np.float32)
    pb2 = PW["pb2"].astype(np.float32)
    z = z0
    for t in range(T):
        tok = mb.slice_by_index(x=tokvec, begin=[0, t, 0],
                                end=[B, t + 1, D],
                                squeeze_mask=[False, True, False])
        a = mb.slice_by_index(x=act, begin=[0, t, 0], end=[B, t + 1, 1],
                              squeeze_mask=[False, True, False])
        xc = mb.concat(values=[z, tok], axis=1)
        h = mb.relu(x=mb.add(x=mb.matmul(x=xc, y=pw1), y=pb1))
        dz = mb.add(x=mb.matmul(x=h, y=pw2), y=pb2)
        z = mb.add(x=z, y=mb.mul(x=a, y=dz))
    return z


@mb.program(input_specs=[mb.TensorSpec(shape=(B, 3)),
                         mb.TensorSpec(shape=(B, LEVELS)),
                         mb.TensorSpec(shape=(256, 3))])
def sk_codec(x0, lev, palette):
    w1 = CW["w1"].astype(np.float32); b1 = CW["b1"].astype(np.float32)
    w2 = CW["w2"].astype(np.float32); b2 = CW["b2"].astype(np.float32)
    w3 = CW["w3"].astype(np.float32); b3 = CW["b3"].astype(np.float32)
    fmean = CW["fmean"].astype(np.float32)
    finv = (1.0 / CW["fstd"]).astype(np.float32)
    pal = mb.expand_dims(x=palette, axes=[0])            # [1,256,3]

    def ghat(v, ctx):
        logmag = mb.mul(x=mb.log(x=mb.add(x=mb.abs(x=ctx), y=LOGEPS)),
                        y=np.float32(1.0 / LN10))
        feat = mb.concat(values=[v, ctx, logmag, lev], axis=1)
        xn = mb.mul(x=mb.sub(x=feat, y=fmean), y=finv)
        h = mb.relu(x=mb.add(x=mb.matmul(x=xn, y=w1), y=b1))
        h = mb.relu(x=mb.add(x=mb.matmul(x=h, y=w2), y=b2))
        out = mb.add(x=mb.matmul(x=h, y=w3), y=b3)
        mu = mb.slice_by_index(x=out, begin=[0, 0], end=[B, 3])
        logs = mb.clip(x=mb.slice_by_index(x=out, begin=[0, 3],
                                           end=[B, 6]),
                       alpha=-12.0, beta=2.0)
        return mb.add(x=mu, y=mb.exp(x=logs))

    def mask(v):
        # DIFFERENCE form: a codeword's row is exactly zero in fp16.
        # The min over 256 entries is a PAIRWISE-MINIMUM TREE, not
        # reduce_min: the A19 ANE lowers reduce_min to batched TopK
        # whose DHNW product (4096×128) exceeds the 65,536 limit
        # (device log 2026-08-11: ANECCompile FAILED). Eight rounds
        # of elementwise minimum are ANE-legal and exactness-
        # preserving — a codeword's exact 0 survives every round.
        vx = mb.expand_dims(x=v, axes=[1])               # [B,1,3]
        diff = mb.sub(x=vx, y=pal)                       # [B,256,3]
        d2f = mb.reduce_sum(x=mb.mul(x=diff, y=diff), axes=[-1],
                            keep_dims=False)             # [B,256]
        cur, width = d2f, 256
        while width > 1:
            half = width // 2
            a = mb.slice_by_index(x=cur, begin=[0, 0], end=[B, half])
            b_ = mb.slice_by_index(x=cur, begin=[0, half],
                                   end=[B, width])
            cur = mb.minimum(x=a, y=b_)
            width = half
        return cur                                       # [B,1]

    nodes = [(x0, mb.mul(x=x0, y=np.float32(0.0)))]      # (value, ctx)
    for _ in range(3):
        nxt = []
        for v, ctx in nodes:
            g = mb.mul(x=mask(v), y=ghat(v, ctx))
            nxt.append((mb.add(x=v, y=g), g))
            nxt.append((mb.sub(x=v, y=g), g))
        nodes = nxt
    leaves = mb.stack(values=[mb.expand_dims(x=v, axes=[1])
                              for v, _ in nodes], axis=1)
    return mb.reshape(x=leaves, shape=[B, 8, 3])


@mb.program(input_specs=[mb.TensorSpec(shape=(BG, 27))])
def sk_ground(feats):
    """THE CORE as a model: the grounding encoder E (doc §14).
    CONTRACT = the DyadAssign lesson: the input is the PRE-
    STANDARDIZED feature vector (Haar characters + level, centered
    and scaled in float32 on the CPU). Standardizing inside the
    fp16 graph divides fp16-rounded near-equal values by tiny σ
    and amplifies rounding to O(1) — measured E error 2.23 before
    this contract, ~1e-2 after. The engine runs the MLP only."""
    gw1 = GRW["w1"].astype(np.float32); gb1 = GRW["b1"].astype(np.float32)
    gw2 = GRW["w2"].astype(np.float32); gb2 = GRW["b2"].astype(np.float32)
    gw3 = GRW["w3"].astype(np.float32); gb3 = GRW["b3"].astype(np.float32)
    h = mb.relu(x=mb.add(x=mb.matmul(x=feats, y=gw1), y=gb1))
    h = mb.relu(x=mb.add(x=mb.matmul(x=h, y=gw2), y=gb2))
    return mb.add(x=mb.matmul(x=h, y=gw3), y=gb3)


def ground_feats32(blocks, lev_oh):
    """The CPU half of the contract: float32 standardized features."""
    coef = np.einsum("we,nec->nwc", H8, blocks.astype(np.float32))
    feat = np.concatenate([coef.reshape(len(blocks), 24),
                           lev_oh.astype(np.float32)], axis=1)
    return ((feat - GRW["fmean"]) / GRW["fstd"]).astype(np.float32)


def ground_law32(feats):
    """float32 reference MLP (the SKGeneFixtures discipline)."""
    h = np.maximum(feats @ GRW["w1"] + GRW["b1"], 0).astype(np.float32)
    h = np.maximum(h @ GRW["w2"] + GRW["b2"], 0).astype(np.float32)
    return (h @ GRW["w3"] + GRW["b3"]).astype(np.float32)


# ── float64 codec law (the gate reference) ──────────────────────────

def codec_law64(x0, lev_oh, C):
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
    return np.stack([v for v, _ in nodes], axis=1)       # [B,8,3]


def main():
    rng = np.random.default_rng(20260811)
    t0 = time.time()
    z0g, toks, act, halt, nf, attract, genes = build_gene_table()
    np.savez(os.path.join(HERE, "gene_table.npz"),
             z0=z0g, toks=toks, act=act, halt=halt, nf=nf,
             attract=attract, tok_table=PW["tok"])
    print(f"gene_table.npz: {len(z0g)} genes, {len(attract)} attractors, "
          f"{halt.max()} max halt ({time.time()-t0:.1f}s)")

    print("building SKGenePasser (16 fused steps) + SKGeneCodec "
          "(3 fused levels, 7 masked splits)")
    t0 = time.time()
    passer = ct.convert(sk_passer, convert_to="mlprogram",
                        compute_precision=ct.precision.FLOAT16,
                        compute_units=ct.ComputeUnit.ALL,
                        minimum_deployment_target=ct.target.iOS17)
    passer.save(os.path.join(HERE, "SKGenePasser.mlpackage"))
    codec = ct.convert(sk_codec, convert_to="mlprogram",
                       compute_precision=ct.precision.FLOAT16,
                       compute_units=ct.ComputeUnit.ALL,
                       minimum_deployment_target=ct.target.iOS17)
    codec.save(os.path.join(HERE, "SKGeneCodec.mlpackage"))
    ground = ct.convert(sk_ground, convert_to="mlprogram",
                        compute_precision=ct.precision.FLOAT16,
                        compute_units=ct.ComputeUnit.ALL,
                        minimum_deployment_target=ct.target.iOS17)
    ground.save(os.path.join(HERE, "SKGeneGround.mlpackage"))
    print(f"converted + saved in {time.time()-t0:.1f}s "
          f"(+ SKGeneGround: THE CORE as a model, {BG} blocks/dispatch)")

    # ── F1: passer parity on the held-out genes (XP2 near-tie law) ──
    held = [g for g in range(len(z0g))
            if g % 10 == 7 and halt[g] > 0][:B]
    n_h = len(held)
    z0b = np.zeros((B, D), np.float32); z0b[:n_h] = z0g[held]
    tokv = np.zeros((B, T, D), np.float32)
    actb = np.zeros((B, T, 1), np.float32)
    tokv[:n_h] = PW["tok"][toks[held]]
    actb[:n_h, :, 0] = act[held]
    out = passer.predict({"z0": z0b, "tokvec": tokv, "act": actb})
    z16 = next(iter(out.values()))[:n_h]

    ref = np.stack([
        _roll64(z0g[g].astype(np.float64), toks[g], act[g]) for g in held])
    An = attract / np.maximum(
        np.linalg.norm(attract, axis=1, keepdims=True), 1e-8)

    def normed(z):
        return z / np.maximum(np.linalg.norm(z, axis=1, keepdims=True), 1e-8)

    def decide(zn):
        d = ((zn[:, None, :] - An[None]) ** 2).sum(-1)
        srt = np.sort(d, axis=1)
        return d.argmin(1), srt[:, 1] - srt[:, 0]
    zn16, zn64 = normed(z16.astype(np.float64)), normed(ref)
    dec16, _ = decide(zn16)
    dec64, marg64 = decide(zn64)
    # decisions live on the unit sphere: for unit u,v,a
    # |d²(u,a) − d²(v,a)| = |2(v−u)·a| ≤ 2‖u−v‖, so a per-gene
    # perturbation can flip only margins below 4·‖Δzn‖ (derived)
    pert = np.linalg.norm(zn16 - zn64, axis=1)
    dis = dec16 != dec64
    near_tie = marg64 < 4 * pert
    agree = 1 - dis.mean()
    ok1 = bool(np.all(~dis | near_tie))
    print((f"F1 {'✓' if ok1 else '✗'} passer parity: {agree:.2%} attractor "
           f"agreement on {n_h} held genes; {int(dis.sum())} flips, all "
           f"within the derived 4·‖Δzn‖ near-tie bound "
           f"(median ‖Δzn‖ {np.median(pert):.1e}, max {pert.max():.1e})")
          if ok1 else
          (f"F1 ✗ passer parity: {agree:.2%}, flips beyond the "
           f"4·‖Δzn‖ near-tie bound exist"))

    # ── F2/F3/F4: codec gates on a real palette ─────────────────────
    el = sampler.sequence(9_000_050)
    f0 = el["frames"][0].astype(np.float64)
    face = f0[el["mask"] > 0.5]
    rgb8 = [dyad_solver.oklab_to_srgb8(tuple(px)) for px in face[:4096]]
    C = np.array([dyad_solver.srgb8_to_oklab(tuple(e))
                  for e in dyad_solver.build_dyad(rgb8)], np.float64)
    Cf = C.astype(np.float32)

    x0 = np.zeros((B, 3), np.float32)
    x0[:256] = Cf                              # codewords
    off = f0.reshape(-1, 3)[
        rng.choice(4096, B - 256, replace=True)].astype(np.float32)
    x0[256:] = off                             # real off-codebook colors
    lev = np.zeros((B, LEVELS), np.float32); lev[:, 0] = 1
    out = codec.predict({"x0": x0, "lev": lev, "palette": Cf})
    leaves = next(iter(out.values()))          # [B,8,3]

    # the graph computes in fp16: the lawful identity is against the
    # fp16 representation both x0 and palette actually take inside
    xq = x0[:256].astype(np.float16).astype(np.float32)
    ok2 = bool(np.all(leaves[:256] == xq[:, None, :]))
    print(f"F2 {'✓' if ok2 else '✗'} codec classicality: all 256 REAL "
          f"palette codewords copy EXACTLY through the fp16 graph "
          f"(difference-form dist² law, fp16 representation)")

    bound = 16 * 2.0 ** -11                    # 3 fp16 stages, derived
    recon_err = float(np.max(np.abs(leaves.mean(axis=1) - x0)))
    ok3 = recon_err < bound
    print(f"F3 {'✓' if ok3 else '✗'} codec retraction in-graph: "
          f"max |mean₈ − x₀| = {recon_err:.2e} (< 16·2⁻¹¹ = {bound:.2e})")

    ref_leaves = codec_law64(x0[256:].astype(np.float64),
                             lev[256:].astype(np.float64), C)
    par = float(np.max(np.abs(leaves[256:].astype(np.float64) - ref_leaves)))
    print(f"F4 ~ codec parity vs float64 law (off-codebook): "
          f"max abs {par:.2e} (reported; fp16 engine precision)")

    # ── F5: THE CORE model — E parity + rollout decisions ───────────
    cube = el["frames"].astype(np.float64)
    for _ in range(2):                       # 64³ → 16³ (level 2)
        s = cube.shape
        cube = cube.reshape(s[0] // 2, 2, s[1] // 2, 2,
                            s[2] // 2, 2, 3).mean(axis=(1, 3, 5))
    R = cube.reshape(8, 2, 8, 2, 8, 2, 3)
    gblocks = R.transpose(0, 2, 4, 1, 3, 5, 6).reshape(BG, 8, 3)
    glev = np.zeros((BG, LEVELS), np.float32); glev[:, 2] = 1
    gfeats = ground_feats32(gblocks, glev)
    out = ground.predict({"feats": gfeats})
    z_cml = next(iter(out.values()))
    z_law = ground_law32(gfeats)

    gid = int(np.argmax(halt))               # the longest halter's schedule
    def roll32(zs):
        z = zs.astype(np.float32)
        for t in range(T):
            if act[gid][t] > 0:
                tokv = PW["tok"][int(toks[gid][t])].astype(np.float32)
                x = np.concatenate([z, np.tile(tokv, (len(z), 1))], axis=1)
                h = np.maximum(x @ PW["pw1"] + PW["pb1"], 0)
                z = (z + h @ PW["pw2"] + PW["pb2"]).astype(np.float32)
        return z
    d_cml, m_cml = decide(normed(roll32(z_cml).astype(np.float64)))
    d_law, m_law = decide(normed(roll32(z_law).astype(np.float64)))
    pert5 = np.linalg.norm(normed(roll32(z_cml).astype(np.float64))
                           - normed(roll32(z_law).astype(np.float64)),
                           axis=1)
    dis5 = d_cml != d_law
    # guard against vacuous near-tie passes: the typical perturbation
    # must be small against the typical margin (both measured)
    sane = float(np.median(pert5)) < float(np.median(m_law)) / 4
    ok5f = bool(np.all(~dis5 | (m_law < 4 * pert5))) and sane
    print(f"F5 {'✓' if ok5f else '✗'} ground (THE CORE) parity: E max abs "
          f"{float(np.max(np.abs(z_cml - z_law))):.2e}; rollout decisions "
          f"{1 - dis5.mean():.2%} agree on {BG} real blocks "
          f"(median ‖Δzn‖ {np.median(pert5):.1e} ≪ median margin "
          f"{np.median(m_law):.2f}); flips all near-ties")

    results = {
        "passer": {"agreement": float(agree), "held": n_h,
                   "flips": int(dis.sum()),
                   "pert_median": float(np.median(pert)),
                   "pert_max": float(pert.max())},
        "codec": {"classicality_exact": ok2, "recon_err": recon_err,
                  "recon_bound": bound, "offbook_parity": par},
        "ground": {"e_max_abs": float(np.max(np.abs(z_cml - z_law))),
                   "rollout_agreement": float(1 - dis5.mean())},
        "gates": {"F1": ok1, "F2": ok2, "F3": ok3, "F5": ok5f},
    }
    with open(os.path.join(HERE, "fold_results.json"), "w") as f:
        json.dump(results, f, indent=2)
    n_green = sum(results["gates"].values())
    print(f"\n  {n_green}/4 gates green (+F4 reported) → SKGeneGround + "
          f"SKGenePasser + SKGeneCodec mlpackages, gene_table.npz")
    if n_green < 4:
        raise SystemExit(1)


def _roll64(z, tok_ids, act_mask):
    for t in range(T):
        if act_mask[t] > 0:
            z = pred64(z, int(tok_ids[t]))
    return z


if __name__ == "__main__":
    main()
