#!/usr/bin/env python3
"""JepaH.mlpackage (JH3): the ONE model, folded.

    y [16, 6]  the capture's raw latent ring (obs at the 5 Hz cadence)
      |
    in-graph whitening (per-dim ring mean/sd)
    regime = per-dim (r1, r2, r3) ring autocorrelations
    HEAD: regime hypernet -> symmetric 5-tap kernel + jump gate
          -> smoothed whitened ring -> de-whitened states
    ENC:  the JEPA encoder embeddings (the representation channel;
          its prediction residual is the surprise/telemetry signal)
      |
    shat [16, 6]  smoothed generating states (feed the table law)
    emb  [16, D]  embeddings

Weights folded as constants from jepa_weights.npz. Fixed shapes, no
loops — the fusable pattern. Built HERE (nn/jepa/), untracked;
placement is JH4, behind a flag, gated on the device pass.
Verified against the python v7 forward on val captures.
"""

import json
import numpy as np
import coremltools as ct
from coremltools.converters.mil import Builder as mb

RING, DIM, D = 16, 6, 24
W = np.load("jepa_weights.npz")
f32 = lambda k: W[k].astype(np.float32)
EA, EAb = f32("enc.a.weight"), f32("enc.a.bias")
EB, EBb = f32("enc.b.weight"), f32("enc.b.bias")
R1, R1b = f32("head.r1.weight"), f32("head.r1.bias")
R2, R2b = f32("head.r2.weight"), f32("head.r2.bias")


def rshift(x, k):
    """Ring shift along axis 0 of a [16, D] tensor via slicing."""
    if k == 0:
        return x
    k = k % RING
    a = mb.slice_by_index(x=x, begin=[k, 0], end=[RING, DIM])
    b = mb.slice_by_index(x=x, begin=[0, 0], end=[k, DIM])
    return mb.concat(values=[a, b], axis=0)


@mb.program(input_specs=[mb.TensorSpec(shape=(RING, DIM))])
def jepah(y):
    # ── in-graph whitening (per dim over the ring) ──
    mu = mb.reduce_mean(x=y, axes=[0], keep_dims=True)
    ctr = mb.sub(x=y, y=mu)
    var = mb.reduce_mean(x=mb.mul(x=ctr, y=ctr), axes=[0], keep_dims=True)
    sd = mb.add(x=mb.sqrt(x=var), y=np.float32(1e-12))
    yw = mb.real_div(x=ctr, y=sd)                       # [16,6]

    # ── regime: per-dim circular autocorrelations r1, r2, r3 ──
    rs = []
    for lag in (1, 2, 3):
        prod = mb.mul(x=yw, y=rshift(yw, lag))
        rs.append(mb.reduce_mean(x=prod, axes=[0], keep_dims=False))  # [6]
    regime = mb.stack(values=rs, axis=1)                # [6,3]

    # ── head hypernet: kernel + gate params per dim ──
    h = mb.gelu(x=mb.add(x=mb.matmul(x=regime, y=R1.T), y=R1b))
    p = mb.add(x=mb.matmul(x=h, y=R2.T), y=R2b)         # [6,5]
    klog = mb.slice_by_index(x=p, begin=[0, 0], end=[DIM, 3])
    a = mb.softmax(x=klog, axis=1)                      # [6,3]
    a0 = mb.transpose(x=mb.slice_by_index(x=a, begin=[0, 0], end=[DIM, 1]),
                      perm=[1, 0])                      # [1,6]
    a1 = mb.transpose(x=mb.slice_by_index(x=a, begin=[0, 1], end=[DIM, 2]),
                      perm=[1, 0])
    a2 = mb.transpose(x=mb.slice_by_index(x=a, begin=[0, 2], end=[DIM, 3]),
                      perm=[1, 0])
    gs = mb.softplus(x=mb.transpose(
        x=mb.slice_by_index(x=p, begin=[0, 3], end=[DIM, 4]), perm=[1, 0]))
    gb = mb.transpose(x=mb.slice_by_index(x=p, begin=[0, 4], end=[DIM, 5]),
                      perm=[1, 0])

    # ── symmetric 5-tap ring filter + jump gate ──
    yp1 = rshift(yw, 1); ym1 = rshift(yw, RING - 1)
    yp2 = rshift(yw, 2); ym2 = rshift(yw, RING - 2)
    smooth = mb.add(
        x=mb.add(x=mb.mul(x=a0, y=yw),
                 y=mb.mul(x=mb.mul(x=a1, y=0.5), y=mb.add(x=yp1, y=ym1))),
        y=mb.mul(x=mb.mul(x=a2, y=0.5), y=mb.add(x=yp2, y=ym2)))
    d = mb.abs(x=mb.sub(x=yw, y=mb.mul(x=mb.add(x=yp1, y=ym1), y=0.5)))
    g = mb.sigmoid(x=mb.add(x=mb.mul(x=gs, y=d), y=gb))
    sw = mb.add(x=mb.mul(x=mb.sub(x=np.float32(1.0), y=g), y=smooth),
                y=mb.mul(x=g, y=yw))

    # ── de-whiten ──
    shat = mb.add(x=mb.mul(x=sw, y=sd), y=mu)

    # ── the representation channel ──
    e1 = mb.gelu(x=mb.add(x=mb.matmul(x=yw, y=EA.T), y=EAb))
    emb = mb.add(x=mb.matmul(x=e1, y=EB.T), y=EBb)

    return shat, emb


def build():
    m = ct.convert(jepah, convert_to="mlprogram",
                   compute_precision=ct.precision.FLOAT32,
                   compute_units=ct.ComputeUnit.CPU_ONLY,
                   minimum_deployment_target=ct.target.iOS17)
    m.save("JepaH.mlpackage")
    print("  built JepaH.mlpackage (fp32 verify build)")
    return m


def np_forward(y):
    """Python v7 reference (mirrors train.py exactly)."""
    def gelu(x):
        from math import erf, sqrt
        return 0.5 * x * (1 + np.vectorize(erf)(x / sqrt(2)))
    mu = y.mean(0, keepdims=True)
    sd = y.std(0, keepdims=True) + 1e-12
    yw = (y - mu) / sd
    def rsh(x, k): return np.roll(x, -k, axis=0)
    regime = np.stack([(yw * rsh(yw, lag)).mean(0) for lag in (1, 2, 3)],
                      axis=1)
    h = gelu(regime @ R1.T + R1b)
    p = h @ R2.T + R2b
    ex = np.exp(p[:, :3] - p[:, :3].max(1, keepdims=True))
    a = ex / ex.sum(1, keepdims=True)
    gs = np.log1p(np.exp(p[:, 3]))
    gb = p[:, 4]
    yp1, ym1 = rsh(yw, 1), rsh(yw, -1)
    yp2, ym2 = rsh(yw, 2), rsh(yw, -2)
    smooth = a[:, 0] * yw + 0.5 * a[:, 1] * (yp1 + ym1) \
        + 0.5 * a[:, 2] * (yp2 + ym2)
    d = np.abs(yw - 0.5 * (yp1 + ym1))
    g = 1 / (1 + np.exp(-(gs * d + gb)))
    sw = (1 - g) * smooth + g * yw
    return sw * sd + mu


def verify(m):
    caps = [json.loads(l) for l in open("corpus/trajectories.jsonl")]
    worst = 0.0
    for c in caps[-8:]:
        y = np.array(c["obs"], dtype=np.float32)
        ref = np_forward(y.astype(np.float64))
        out = m.predict({"y": y})
        shat = [v for v in out.values() if v.shape == (RING, DIM)][0]
        worst = max(worst, float(np.max(np.abs(shat - ref))))
    print(f"  parity vs python v7: max |diff| = {worst:.2e}")
    assert worst < 1e-4, "parity gate failed"
    print("  PARITY GATE ✓")


if __name__ == "__main__":
    model = build()
    verify(model)
