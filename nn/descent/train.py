#!/usr/bin/env python3
"""Descent-ladder J2: train the multi-exit assignment scorer.

Daniel's rulings (2026-08-12): the capture-assist model's first job
is P4 assignment descent; the 3-model ladder is ONE descent with
three exit depths, nested by OUTPUTS (spec DL2); corpus = synthetic
only (make corpus-descent); sizes are reported, never targeted.

The model is a SHARED per-candidate scorer (one weight set serves
all three stages -- the "one descent" made literal): for a target
lab and a candidate lab it emits a score; softmax over the stage's
candidates picks the child. Exit 1 = 2-class, exit 2 = 16-class,
exit 3 = leaf (128). Teacher = the corpus's EXHAUSTIVE labels
(spec DL5), so the net is graded against ground truth the greedy
descent itself cannot always reach -- beating the greedy-L2
baseline is the interesting gate.

Gates (printed, saved to results.json):
  G1 determinism: fixed seeds, reproducible first-step loss
  G2 val free-descent leaf accuracy >= greedy-L2 descent baseline
  G3 output nesting is structural in free descent (DL2)
  G4 residual errors are near-ties (teacher-margin analysis)
  G5 parameter count REPORTED (device-measured doctrine)
"""

import json
import math
import numpy as np
import mlx.core as mx
import mlx.nn as nn
import mlx.optimizers as optim
from mlx.utils import tree_flatten

HALF_MEAN = math.sqrt(2.0 / math.pi)
HALF_VAR = 1.0 - 2.0 / math.pi

# ── Mirrors (DyadPalette.hs color core; PairTree analytic tree) ──

def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
               [0.2119034982, 0.6806995451, 0.1073969566],
               [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553,  0.7936177850, -0.0040720468],
               [1.9779984951, -2.4285922050,  0.4505937099],
               [0.0259040371,  0.7827717662, -0.8086757660]])

def srgb8_to_oklab(rgb8):
    lin = srgb_to_linear(np.asarray(rgb8, dtype=np.float64) / 255.0)
    lms = lin @ M1.T
    return np.cbrt(lms) @ M2.T

def node_means(mu, var):
    """Analytic axis-aligned tree: node (mean, remaining-var) at
    depths 1 and 4 -- the spread is the lookahead radius greedy-L2
    ignores, and the feature that makes commitment learnable."""
    def descend(mean, v, depth):
        if depth == 0:
            return [(mean, v)]
        a = int(np.argmax(v))          # tie -> lowest, matches the law
        off = math.sqrt(v[a]) * HALF_MEAN
        vv = v.copy(); vv[a] *= HALF_VAR
        lo = mean.copy(); lo[a] -= off
        hi = mean.copy(); hi[a] += off
        return descend(lo, vv, depth - 1) + descend(hi, vv, depth - 1)
    mu = np.asarray(mu, dtype=np.float64)
    var = np.asarray(var, dtype=np.float64)
    n1 = descend(mu, var, 1)
    n4 = descend(mu, var, 4)
    d1 = np.array([m for m, _ in n1]); v1 = np.array([v for _, v in n1])
    d4 = np.array([m for m, _ in n4]); v4 = np.array([v for _, v in n4])
    return d1, v1, d4, v4

# ── Corpus ───────────────────────────────────────────────────────

def load(path="corpus/samples.jsonl"):
    samples = []
    with open(path) as f:
        for line in f:
            samples.append(json.loads(line))
    return samples

def assemble(samples):
    rows = []
    for s in samples:
        d1, v1, d4, v4 = node_means(s["mu"], s["var"])
        leaf_labs = srgb8_to_oklab(np.array(s["figures"]))
        for p in s["probes"]:
            rows.append(dict(
                lab=np.array(p["lab"]), leaf=p["leaf"], c16=p["c16"],
                c2=p["c2"], d1=d1, v1=v1, d4=d4, v4=v4,
                leaves=leaf_labs, seed=s["seed"]))
    return rows

# ── Model: one shared per-candidate scorer, stage-conditioned ────

class Scorer(nn.Module):
    """Commitment scorer for stages 1-2 ONLY. Stage 3 (the leaf) is
    the EXACT L2 argmin -- provably optimal given the octet, so it
    is law, not learning (the first training run measured exactly
    this: the net beat greedy at commitment and lost at the leaf)."""

    def __init__(self, hidden=32):
        super().__init__()
        # features: diff(3) + |diff|(3) + spread sd(3) + whitened
        # diff (Mahalanobis, 3) + target(3) — the commitment problem's
        # natural coordinates
        self.l1 = nn.Linear(15, hidden)
        self.l2 = nn.Linear(hidden, hidden)
        self.l3 = nn.Linear(hidden, 1)

    def __call__(self, target, cands, spreads):
        # target [N,3], cands [N,C,3], spreads [N,C,3] (remaining var)
        N, C, _ = cands.shape
        t = mx.broadcast_to(target[:, None, :], (N, C, 3))
        diff = cands - t
        sd = mx.sqrt(spreads) + 1e-6
        x = mx.concatenate(
            [diff, mx.abs(diff), sd, mx.abs(diff) / sd, t], axis=-1)
        h = nn.gelu(self.l1(x))
        h = nn.gelu(self.l2(h))
        return self.l3(h)[..., 0]        # [N,C] logits

def ce(logits, labels):
    return mx.mean(nn.losses.cross_entropy(logits, labels))

# ── Assembly into arrays (teacher-forced stages) ─────────────────

def arrays(rows):
    lab = np.stack([r["lab"] for r in rows])
    s1_c = np.stack([r["d1"] for r in rows])
    s1_v = np.stack([r["v1"] for r in rows])
    s1_y = np.array([r["c2"] for r in rows])
    s2_c = np.stack([r["d4"][r["c2"] * 8:(r["c2"] + 1) * 8] for r in rows])
    s2_v = np.stack([r["v4"][r["c2"] * 8:(r["c2"] + 1) * 8] for r in rows])
    s2_y = np.array([r["c16"] % 8 for r in rows])
    return (mx.array(lab.astype(np.float32)),
            [(mx.array(c.astype(np.float32)), mx.array(v.astype(np.float32)),
              mx.array(y)) for c, v, y in
             [(s1_c, s1_v, s1_y), (s2_c, s2_v, s2_y)]])

# ── Free descent (the net drives) + greedy-L2 baseline ───────────

def free_descent(model, rows):
    hits = np.zeros(3, dtype=int)
    nest_ok = True
    err_margin, hit_margin = [], []
    for r in rows:
        t = mx.array(r["lab"].astype(np.float32))[None, :]
        c1 = int(mx.argmax(model(t,
            mx.array(r["d1"].astype(np.float32))[None],
            mx.array(r["v1"].astype(np.float32))[None])[0]).item())
        kids = r["d4"][c1 * 8:(c1 + 1) * 8]
        kv = r["v4"][c1 * 8:(c1 + 1) * 8]
        c2 = int(mx.argmax(model(t,
            mx.array(kids.astype(np.float32))[None],
            mx.array(kv.astype(np.float32))[None])[0]).item())
        c16 = c1 * 8 + c2
        # stage 3 is LAW: exact L2 argmin within the octet
        leaves = r["leaves"][c16 * 8:(c16 + 1) * 8]
        c3 = int(np.argmin(np.sum((leaves - r["lab"]) ** 2, axis=1)))
        leaf = c16 * 8 + c3
        hits[0] += (c1 == r["c2"])
        hits[1] += (c16 == r["c16"])
        hits[2] += (leaf == r["leaf"])
        nest_ok &= (leaf >> 3 == c16) and (leaf >> 6 == c1)   # DL2
        d = np.sum((r["leaves"] - r["lab"]) ** 2, axis=1)
        srt = np.sort(d)
        margin = math.sqrt(srt[1]) - math.sqrt(srt[0])
        (hit_margin if leaf == r["leaf"] else err_margin).append(margin)
    n = len(rows)
    return hits / n, nest_ok, err_margin, hit_margin

def greedy_l2(rows):
    hits = np.zeros(3, dtype=int)
    for r in rows:
        c1 = int(np.argmin(np.sum((r["d1"] - r["lab"]) ** 2, axis=1)))
        kids = r["d4"][c1 * 8:(c1 + 1) * 8]
        c2 = int(np.argmin(np.sum((kids - r["lab"]) ** 2, axis=1)))
        c16 = c1 * 8 + c2
        leaves = r["leaves"][c16 * 8:(c16 + 1) * 8]
        c3 = int(np.argmin(np.sum((leaves - r["lab"]) ** 2, axis=1)))
        leaf = c16 * 8 + c3
        hits[0] += (c1 == r["c2"]); hits[1] += (c16 == r["c16"])
        hits[2] += (leaf == r["leaf"])
    return hits / len(rows)

# ── Train ────────────────────────────────────────────────────────

def main():
    samples = load()
    train_rows = assemble([s for s in samples if s["seed"] <= 224])
    val_rows = assemble([s for s in samples if s["seed"] > 224])
    print(f"corpus: {len(train_rows)} train / {len(val_rows)} val probes "
          f"({len(samples)} trees)")

    mx.random.seed(64)
    model = Scorer()
    n_params = sum(v.size for _, v in tree_flatten(model.parameters()))

    lab, stages = arrays(train_rows)

    def loss_fn(m):
        return sum(ce(m(lab, c, v), y) for (c, v, y) in stages)

    # G1 determinism: the seeded first loss must reproduce.
    first = float(loss_fn(model).item())
    mx.random.seed(64)
    model2 = Scorer()
    g1 = abs(float(loss_fn(model2).item()) - first) < 1e-6

    opt = optim.adam(learning_rate=3e-3) if hasattr(optim, "adam") \
        else optim.Adam(learning_rate=3e-3)
    lg = nn.value_and_grad(model, loss_fn)
    for it in range(900):
        l, grads = lg(model)
        opt.update(model, grads)
        mx.eval(model.parameters())
        if it % 150 == 0:
            print(f"  iter {it:4d}  loss {float(l.item()):.4f}")

    base_v = greedy_l2(val_rows)
    acc_v, nest_ok, err_m, hit_m = free_descent(model, val_rows)
    base_t = greedy_l2(train_rows)
    acc_t, _, _, _ = free_descent(model, train_rows)

    g2 = acc_v[2] >= base_v[2]
    g3 = nest_ok
    med_err = float(np.median(err_m)) if err_m else 0.0
    med_hit = float(np.median(hit_m)) if hit_m else 0.0
    g4 = (not err_m) or med_err < med_hit    # errors live at tighter margins

    print()
    print(f"  exits (vs exhaustive teacher), VAL:  "
          f"net {acc_v.round(4).tolist()}  greedy-L2 {base_v.round(4).tolist()}")
    print(f"  exits, TRAIN:                        "
          f"net {acc_t.round(4).tolist()}  greedy-L2 {base_t.round(4).tolist()}")
    print(f"  G1 determinism: {'✓' if g1 else '✗'}")
    print(f"  G2 net >= greedy on val leaf: {'✓' if g2 else '✗'} "
          f"({acc_v[2]:.4f} vs {base_v[2]:.4f})")
    print(f"  G3 output nesting structural (DL2): {'✓' if g3 else '✗'}")
    print(f"  G4 errors are near-ties: {'✓' if g4 else '✗'} "
          f"(median margin errors {med_err:.5f} vs hits {med_hit:.5f})")
    print(f"  G5 params REPORTED: {n_params} "
          f"(size is a device-measured decision, not a target)")

    flat = dict(tree_flatten(model.parameters()))
    np.savez("scorer_weights.npz",
             **{k: np.array(v) for k, v in flat.items()})
    json.dump(dict(
        train=dict(net=acc_t.tolist(), greedy=base_t.tolist()),
        val=dict(net=acc_v.tolist(), greedy=base_v.tolist()),
        gates=dict(G1=bool(g1), G2=bool(g2), G3=bool(g3), G4=bool(g4)),
        margins=dict(median_error=med_err, median_hit=med_hit,
                     n_errors=len(err_m)),
        params=int(n_params),
    ), open("results.json", "w"), indent=2)
    print("  saved scorer_weights.npz + results.json")

if __name__ == "__main__":
    main()
