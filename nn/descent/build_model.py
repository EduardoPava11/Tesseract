#!/usr/bin/env python3
"""DescentAssign: the v4 descent ladder as ONE fused graph.

One dispatch per frame (the DyadAssign pattern):

    t      [4096, 3]   staged OKLab targets (a frame's pixels)
    d1     [2, 3]      depth-1 node means        (analytic tree)
    v1     [2, 3]      depth-1 remaining vars
    kids1  [2, 2, 3]   depth-1 children means
    d4     [16, 3]     depth-4 node means
    leaves [128, 3]    clamped figure labs (what Swift searches)
      |
    stage 1  LEARNED: residual-on-spine corrector (weights folded
             as constants; spine = z-scored min descendant dist^2)
    stage 2  LAW (DL6): conditional octet-min lookahead -- exact
    stage 3  LAW: exact leaf argmin within the octet
      |
    leaf [4096], c16 [4096], c2 [4096]   -- the three ladder exits

Fixed shapes, fixed depth (3), no loops: the fusable ANE pattern.
Builds DescentAssign.mlpackage HERE (nn/descent/ -- NOT Tesseract/ML:
app placement is gated on the A19 bench + device pass), then
verifies against the exact NumPy v4 reference on held-out corpus
trees: exit agreement plus the near-tie posture on disagreements.
"""

import json
import math
import numpy as np
import coremltools as ct
from coremltools.converters.mil import Builder as mb

P = 4096
W = np.load("scorer_weights.npz")
W1, B1 = W["l1.weight"].astype(np.float32), W["l1.bias"].astype(np.float32)
W2, B2 = W["l2.weight"].astype(np.float32), W["l2.bias"].astype(np.float32)
W3, B3 = W["l3.weight"].astype(np.float32), W["l3.bias"].astype(np.float32)
CORR_SCALE = np.float32(0.1)     # the residual gate from training
EPS = np.float32(1e-9)


@mb.program(input_specs=[mb.TensorSpec(shape=(P, 3)),
                         mb.TensorSpec(shape=(2, 3)),
                         mb.TensorSpec(shape=(2, 3)),
                         mb.TensorSpec(shape=(2, 2, 3)),
                         mb.TensorSpec(shape=(16, 3)),
                         mb.TensorSpec(shape=(128, 3))])
def descent(t, d1, v1, kids1, d4, leaves):
    # ── shared distance machinery ──
    tsq = mb.reduce_sum_square(x=t, axes=[1], keep_dims=True)        # [P,1]

    # d4 distances^2: [P,16]
    d4sq = mb.reduce_sum_square(x=d4, axes=[1], keep_dims=False)     # [16]
    d4dot = mb.matmul(x=t, y=mb.transpose(x=d4, perm=[1, 0]))        # [P,16]
    dist4 = mb.add(x=mb.sub(x=tsq, y=mb.mul(x=d4dot, y=2.0)), y=d4sq)
    dist4 = mb.relu(x=dist4)                                          # >= 0

    # leaf distances^2: [P,128]
    lsq = mb.reduce_sum_square(x=leaves, axes=[1], keep_dims=False)
    ldot = mb.matmul(x=t, y=mb.transpose(x=leaves, perm=[1, 0]))
    distL = mb.relu(x=mb.add(x=mb.sub(x=tsq, y=mb.mul(x=ldot, y=2.0)), y=lsq))

    # ── stage 1: learned corrector on the lookahead spine ──
    # per-half features, concatenated along a new candidate axis
    feats = []
    spines = []
    for h in (0, 1):
        m = mb.slice_by_index(x=d1, begin=[h, 0], end=[h + 1, 3])     # [1,3]
        diff = mb.sub(x=m, y=t)                                       # [P,3]
        adiff = mb.abs(x=diff)
        v = mb.slice_by_index(x=v1, begin=[h, 0], end=[h + 1, 3])
        sd = mb.add(x=mb.sqrt(x=mb.relu(x=v)), y=np.float32(1e-6))    # [1,3]
        mahal = mb.real_div(x=adiff, y=sd)
        sdr = mb.tile(x=sd, reps=[P, 1])                              # [P,3]
        # child distances (2)
        cds = []
        for c in (0, 1):
            k = mb.slice_by_index(x=kids1, begin=[h, c, 0],
                                  end=[h + 1, c + 1, 3])
            k = mb.reshape(x=k, shape=[1, 3])
            kd = mb.sub(x=k, y=t)
            cds.append(mb.sqrt(x=mb.add(
                x=mb.reduce_sum_square(x=kd, axes=[1], keep_dims=True),
                y=np.float32(1e-12))))
        cdist = mb.concat(values=cds, axis=1)                         # [P,2]
        # sorted distances to the half's 8 depth-4 descendants
        half4 = mb.slice_by_index(x=dist4, begin=[0, h * 8],
                                  end=[P, (h + 1) * 8])               # [P,8]
        half4d = mb.sqrt(x=mb.add(x=half4, y=np.float32(1e-12)))
        dsorted, _ = mb.topk(x=half4d, k=8, axis=1, ascending=True)
        x = mb.concat(values=[diff, adiff, sdr, mahal, cdist,
                              dsorted, t], axis=1)                    # [P,25]
        h1 = mb.gelu(x=mb.add(x=mb.matmul(
            x=x, y=W1.T), y=B1))
        h2 = mb.gelu(x=mb.add(x=mb.matmul(x=h1, y=W2.T), y=B2))
        corr = mb.add(x=mb.matmul(x=h2, y=W3.T), y=B3)                # [P,1]
        feats.append(corr)
        spines.append(mb.reduce_min(x=half4, axes=[1], keep_dims=True))
    corr2 = mb.concat(values=feats, axis=1)                           # [P,2]
    spine = mb.concat(values=spines, axis=1)                          # [P,2]
    smu = mb.reduce_mean(x=spine, axes=[1], keep_dims=True)
    sctr = mb.sub(x=spine, y=smu)
    svar = mb.reduce_mean(x=mb.mul(x=sctr, y=sctr), axes=[1], keep_dims=True)
    sz = mb.real_div(x=sctr, y=mb.add(x=mb.sqrt(x=svar), y=EPS))
    vhat = mb.add(x=sz, y=mb.mul(x=corr2, y=CORR_SCALE))              # [P,2]
    c1 = mb.reduce_argmin(x=vhat, axis=1, keep_dims=False)            # [P]

    # ── stage 2 (LAW): conditional octet-min lookahead ──
    # No gathers: mask the other half with a large penalty and take
    # a GLOBAL argmin — pure elementwise + reduce, the ANE-friendly
    # select (same pattern as DyadAssign's role select).
    BIG = np.float32(1e9)
    octmin = mb.reduce_min(x=mb.reshape(x=distL, shape=[P, 16, 8]),
                           axes=[2], keep_dims=False)                 # [P,16]
    c1i = mb.cast(x=c1, dtype="int32")
    hot2 = mb.cast(x=mb.one_hot(indices=c1i, one_hot_vector_size=2),
                   dtype="fp32")                                       # [P,2]
    mask16 = mb.reshape(
        x=mb.tile(x=mb.expand_dims(x=hot2, axes=[2]), reps=[1, 1, 8]),
        shape=[P, 16])                                                # [P,16]
    pen16 = mb.mul(x=mb.sub(x=np.float32(1.0), y=mask16), y=BIG)
    c16 = mb.cast(x=mb.reduce_argmin(x=mb.add(x=octmin, y=pen16),
                                     axis=1, keep_dims=False),
                  dtype="int32")                                      # [P]

    # ── stage 3 (LAW): exact leaf argmin within the octet ──
    hot16 = mb.cast(x=mb.one_hot(indices=c16, one_hot_vector_size=16),
                    dtype="fp32")                                      # [P,16]
    mask128 = mb.reshape(
        x=mb.tile(x=mb.expand_dims(x=hot16, axes=[2]), reps=[1, 1, 8]),
        shape=[P, 128])
    pen128 = mb.mul(x=mb.sub(x=np.float32(1.0), y=mask128), y=BIG)
    leaf = mb.cast(x=mb.reduce_argmin(x=mb.add(x=distL, y=pen128),
                                      axis=1, keep_dims=False),
                   dtype="int32")

    return leaf, c16, c1i


def build():
    m = ct.convert(descent, convert_to="mlprogram",
                   compute_precision=ct.precision.FLOAT32,
                   compute_units=ct.ComputeUnit.CPU_ONLY,
                   minimum_deployment_target=ct.target.iOS17)
    m.save("DescentAssign.mlpackage")
    print("  built DescentAssign.mlpackage (fp32 verify build)")
    return m


# ── NumPy v4 reference (mirrors train.py exactly) ────────────────

def gelu(x):
    return 0.5 * x * (1 + np.vectorize(math.erf)(x / math.sqrt(2)))

def reference(t, d1, v1, kids1, d4, leaves):
    dist4 = ((t[:, None, :] - d4[None]) ** 2).sum(2)
    distL = ((t[:, None, :] - leaves[None]) ** 2).sum(2)
    vhat = []
    for h in (0, 1):
        diff = d1[h][None] - t
        sd = np.sqrt(np.maximum(v1[h], 0)) + 1e-6
        cd = np.stack([np.sqrt(((kids1[h, c][None] - t) ** 2).sum(1) + 1e-12)
                       for c in (0, 1)], axis=1)
        half4 = np.sqrt(dist4[:, h * 8:(h + 1) * 8] + 1e-12)
        x = np.concatenate([diff, np.abs(diff),
                            np.repeat(sd[None], len(t), 0),
                            np.abs(diff) / sd[None], cd,
                            np.sort(half4, axis=1), t], axis=1)
        h1 = gelu(x @ W1.T + B1)
        h2 = gelu(h1 @ W2.T + B2)
        vhat.append((h2 @ W3.T + B3)[:, 0])
    corr = np.stack(vhat, axis=1)
    spine = np.stack([dist4[:, :8].min(1), dist4[:, 8:].min(1)], axis=1)
    mu = spine.mean(1, keepdims=True)
    sd = np.sqrt(((spine - mu) ** 2).mean(1, keepdims=True)) + 1e-9
    v = (spine - mu) / sd + 0.1 * corr
    c1 = v.argmin(1)
    octmin = distL.reshape(len(t), 16, 8).min(2)
    rows = np.arange(len(t))
    halfoct = octmin[rows[:, None], (c1 * 8)[:, None] + np.arange(8)[None]]
    c16 = c1 * 8 + halfoct.argmin(1)
    octL = distL[rows[:, None], (c16 * 8)[:, None] + np.arange(8)[None]]
    leaf = c16 * 8 + octL.argmin(1)
    return leaf, c16, c1, distL


def verify(m):
    import train as T
    samples = T.load()
    val = [s for s in samples if s["seed"] > len(samples) * 7 // 8][:4]
    total = agree = 0
    nt = []
    for s in val:
        d1, v1, kids1, d4, _, _ = T.node_means(s["mu"], s["var"])
        leaves = T.srgb8_to_oklab(np.array(s["figures"]))
        probes = np.array([p["lab"] for p in s["probes"]])
        reps = int(np.ceil(P / len(probes)))
        t = np.tile(probes, (reps, 1))[:P]
        ref_leaf, ref_c16, ref_c1, distL = reference(
            t, d1, v1, kids1, d4, leaves)
        out = m.predict(dict(
            t=t.astype(np.float32), d1=d1.astype(np.float32),
            v1=v1.astype(np.float32), kids1=kids1.astype(np.float32),
            d4=d4.astype(np.float32), leaves=leaves.astype(np.float32)))
        keys = sorted(out.keys())
        got = {k: out[k].astype(int).ravel() for k in keys}
        # identify outputs by value range
        leaf_k = [k for k in keys if got[k].max() >= 16][0]
        ok = got[leaf_k] == ref_leaf
        agree += ok.sum(); total += len(ok)
        srt = np.sort(np.sqrt(distL), axis=1)
        nt += (srt[:, 1] - srt[:, 0])[~ok].tolist()
    rate = agree / total
    med = float(np.median(nt)) if nt else 0.0
    print(f"  parity vs NumPy v4 reference: {agree}/{total} = {rate:.6f}")
    print(f"  disagreements: {len(nt)} (median leaf margin {med:.6f} — "
          f"near-tie territory)" if nt else "  disagreements: 0")
    json.dump(dict(parity=rate, disagreements=len(nt), median_margin=med),
              open("mlpackage_parity.json", "w"), indent=2)
    assert rate > 0.999, "parity gate failed"
    print("  PARITY GATE ✓ (fp32 CPU build; fp16/ANE variant is a "
          "device-bench decision)")


if __name__ == "__main__":
    # node_means in train.py returns 6 values (d1,v1,c1,d4,v4,c4)
    model = build()
    verify(model)
