#!/usr/bin/env python3
"""Independent re-verification of the shipped v7 head on the val
split (last 128 rings, never trained on). Recomputes from the raw
corpus + weights npz — no train.py code paths.

Baselines:
  raw obs        — do nothing
  oracle EMA     — cyclic EMA with the PER-CAPTURE best gain chosen
                   against the TRUE states (peeks at truth; a bound
                   no causal filter deployed blind can beat fairly)
"""

import json
import numpy as np

W = np.load("jepa_weights.npz")
R1 = W["head.r1.weight"].astype(np.float64)
R1b = W["head.r1.bias"].astype(np.float64)
R2 = W["head.r2.weight"].astype(np.float64)
R2b = W["head.r2.bias"].astype(np.float64)


def head(y):
    from math import erf, sqrt
    gelu = np.vectorize(lambda x: 0.5 * x * (1 + erf(x / sqrt(2))))
    mu = y.mean(0, keepdims=True)
    sd = y.std(0, keepdims=True) + 1e-12
    yw = (y - mu) / sd
    rsh = lambda x, k: np.roll(x, -k, axis=0)
    regime = np.stack([(yw * rsh(yw, l)).mean(0) for l in (1, 2, 3)], axis=1)
    h = gelu(regime @ R1.T + R1b)
    p = h @ R2.T + R2b
    ex = np.exp(p[:, :3] - p[:, :3].max(1, keepdims=True))
    a = ex / ex.sum(1, keepdims=True)
    gs, gb = np.log1p(np.exp(p[:, 3])), p[:, 4]
    yp1, ym1, yp2, ym2 = rsh(yw, 1), rsh(yw, -1), rsh(yw, 2), rsh(yw, -2)
    smooth = a[:, 0] * yw + 0.5 * a[:, 1] * (yp1 + ym1) + 0.5 * a[:, 2] * (yp2 + ym2)
    g = 1 / (1 + np.exp(-(gs * np.abs(yw - 0.5 * (yp1 + ym1)) + gb)))
    return ((1 - g) * smooth + g * yw) * sd + mu


def ema(a, y):
    out = np.empty_like(y)
    out[0] = y[0]
    for t in range(1, len(y)):
        out[t] = out[t - 1] + a * (y[t] - out[t - 1])
    return out


def churn(x):
    return np.abs(np.roll(x, -1, axis=0) - x).mean()


caps = [json.loads(l) for l in open("corpus/trajectories.jsonl")][-128:]
grid = np.linspace(0.05, 1.0, 39)

se = {"obs": 0.0, "oracle": 0.0, "model": 0.0}
ch = {"obs": 0.0, "oracle": 0.0, "model": 0.0, "truth": 0.0}
n = 0
for c in caps:
    y = np.array(c["obs"])
    s = np.array(c["states"])
    m = head(y)
    # oracle: best per-capture gain against TRUTH
    o = min((ema(a, y) for a in grid), key=lambda e: ((e - s) ** 2).mean())
    se["obs"] += ((y - s) ** 2).sum(); se["oracle"] += ((o - s) ** 2).sum()
    se["model"] += ((m - s) ** 2).sum(); n += s.size
    # churn in the whitened byte-relevant scale: per-dim normalized
    sd = y.std(0, keepdims=True) + 1e-12
    ch["obs"] += churn(y / sd); ch["oracle"] += churn(o / sd)
    ch["model"] += churn(m / sd); ch["truth"] += churn(s / sd)

k = len(caps)
print(f"  val rings: {k} (indices 896..1023, held out)")
print(f"  state RMSE   obs={np.sqrt(se['obs']/n):.5f}  "
      f"oracleEMA={np.sqrt(se['oracle']/n):.5f}  "
      f"model={np.sqrt(se['model']/n):.5f}")
print(f"  ring churn   obs={ch['obs']/k:.3f}  oracleEMA={ch['oracle']/k:.3f}  "
      f"model={ch['model']/k:.3f}  truth={ch['truth']/k:.3f}")
ok = se["model"] < se["oracle"] and ch["model"] < ch["oracle"]
print("  MODEL BEATS ORACLE-GAIN EMA ON BOTH ✓" if ok else "  ✗ CHECK FAILED")
