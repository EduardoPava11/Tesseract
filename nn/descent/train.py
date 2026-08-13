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
    """Analytic axis-aligned tree: node (mean, remaining-var, and the
    two CHILD means -- one-step lookahead geometry, free arithmetic)
    at depths 1 and 4."""
    def descend(mean, v, depth):
        if depth == 0:
            return [(mean, v)]
        a = int(np.argmax(v))          # tie -> lowest, matches the law
        off = math.sqrt(v[a]) * HALF_MEAN
        vv = v.copy(); vv[a] *= HALF_VAR
        lo = mean.copy(); lo[a] -= off
        hi = mean.copy(); hi[a] += off
        return descend(lo, vv, depth - 1) + descend(hi, vv, depth - 1)
    def children(mean, v):
        a = int(np.argmax(v))
        off = math.sqrt(v[a]) * HALF_MEAN
        lo = mean.copy(); lo[a] -= off
        hi = mean.copy(); hi[a] += off
        return lo, hi
    mu = np.asarray(mu, dtype=np.float64)
    var = np.asarray(var, dtype=np.float64)
    n1 = descend(mu, var, 1)
    n4 = descend(mu, var, 4)
    d1 = np.array([m for m, _ in n1]); v1 = np.array([v for _, v in n1])
    d4 = np.array([m for m, _ in n4]); v4 = np.array([v for _, v in n4])
    c1 = np.array([np.stack(children(m, v)) for m, v in n1])   # [2,2,3]
    c4 = np.array([np.stack(children(m, v)) for m, v in n4])   # [16,2,3]
    return d1, v1, c1, d4, v4, c4

# ── Corpus ───────────────────────────────────────────────────────

def load(path="corpus/samples.jsonl"):
    samples = []
    with open(path) as f:
        for line in f:
            samples.append(json.loads(line))
    return samples

def assemble(samples):
    trees = []
    for s in samples:
        d1, v1, c1, d4, v4, c4 = node_means(s["mu"], s["var"])
        leaf_labs = srgb8_to_oklab(np.array(s["figures"]))
        labs = np.stack([p["lab"] for p in s["probes"]])
        trees.append(dict(
            seed=s["seed"], labs=labs,
            leaf=np.array([p["leaf"] for p in s["probes"]]),
            c16=np.array([p["c16"] for p in s["probes"]]),
            c2=np.array([p["c2"] for p in s["probes"]]),
            d1=d1, v1=v1, c1=c1, d4=d4, v4=v4, c4=c4, leaves=leaf_labs))
    return trees

# ── Model: one shared per-candidate scorer, stage-conditioned ────

class Scorer(nn.Module):
    """Commitment VALUE model for stages 1-2 ONLY. Stage 3 (the
    leaf) is the EXACT L2 argmin. Predicts (a z-scored proxy of)
    each candidate subtree's min leaf distance -- distilling the
    exact lookahead the greedy descent lacks. Commit = argmin v.

    v4 (the final contraction): the net corrects STAGE 1 ONLY.
    Run 3 measured that lookahead-L2 (commit to the candidate whose
    descendant layer holds the nearest point) is exact at stage 2
    and 96.5% at stage 1 -- so stages 2-3 are LAW and the learned
    correction lives solely where the law is blind: the stage-1
    half choice. Features per candidate: diff(3), |diff|(3), sd(3),
    Mahalanobis(3), child distances(2), the FULL SORTED descendant
    distance vector (8 -- reuse of distances the later stages
    compute anyway), and the target(3) -- 25 dims."""

    def __init__(self, hidden=64):
        super().__init__()
        self.l1 = nn.Linear(25, hidden)
        self.l2 = nn.Linear(hidden, hidden)
        self.l3 = nn.Linear(hidden, 1)

    def __call__(self, target, cands, spreads, childs, desc):
        # target [N,3], cands [N,C,3], spreads [N,C,3],
        # childs [N,C,2,3], desc [N,C,D,3] (descendant layer)
        N, C, _ = cands.shape
        t = mx.broadcast_to(target[:, None, :], (N, C, 3))
        diff = cands - t
        sd = mx.sqrt(spreads) + 1e-6
        cd = childs - t[:, :, None, :]                    # [N,C,2,3]
        cdist = mx.sqrt(mx.sum(cd * cd, axis=-1) + 1e-12)  # [N,C,2]
        dd = desc - t[:, :, None, :]                       # [N,C,D,3]
        ddist = mx.sqrt(mx.sum(dd * dd, axis=-1) + 1e-12)  # [N,C,D]
        dsorted = mx.sort(ddist, axis=-1)                   # [N,C,8]
        x = mx.concatenate(
            [diff, mx.abs(diff), sd, mx.abs(diff) / sd, cdist, dsorted, t],
            axis=-1)
        h = nn.gelu(self.l1(x))
        h = nn.gelu(self.l2(h))
        # RESIDUAL ON THE EXACT LOOKAHEAD: the spine is the
        # descendant-layer min distance^2 (row-standardized); the MLP
        # is only a correction. At zero correction the model IS the
        # lookahead descent -- learning starts from the strongest
        # lawful baseline instead of from noise.
        dmin2 = mx.min(ddist, axis=-1) ** 2                 # [N,C]
        mu = mx.mean(dmin2, axis=1, keepdims=True)
        sdr = mx.sqrt(mx.var(dmin2, axis=1, keepdims=True)) + 1e-9
        spine = (dmin2 - mu) / sdr
        return spine + 0.1 * self.l3(h)[..., 0]  # [N,C] predicted value

def ce(logits, labels):
    return mx.mean(nn.losses.cross_entropy(logits, labels))

# ── Batched training data with VALUE targets ────────────────────
#
# For every candidate node, the exact lookahead value = min over
# its descendant leaves of d^2(leaf, probe). Training-time only
# (numpy, corpus prep) -- the deployed model never pays these
# evals; it learns to predict them. Targets are z-scored per row
# across the candidate set (self-normalizing: no scale constant).

def value_targets(tree):
    labs = tree["labs"]                       # [P,3]
    leaves = tree["leaves"]                   # [128,3]
    d2 = np.sum((labs[:, None, :] - leaves[None, :, :]) ** 2, axis=2)
    return np.stack([d2[:, :64].min(axis=1), d2[:, 64:].min(axis=1)], axis=1)

def zscore(v):
    m = v.mean(axis=1, keepdims=True)
    sd = v.std(axis=1, keepdims=True) + 1e-9
    return (v - m) / sd

def batch(trees):
    """Flatten all trees into STAGE-1 training arrays (v4: stages
    2-3 are law -- DL6 -- so only the half choice is trained)."""
    T, C1, S1, K1, D1, Y1, V1 = [], [], [], [], [], [], []
    for tr in trees:
        P = len(tr["labs"])
        v1 = value_targets(tr)
        T.append(tr["labs"])
        C1.append(np.repeat(tr["d1"][None], P, 0))
        S1.append(np.repeat(tr["v1"][None], P, 0))
        K1.append(np.repeat(tr["c1"][None], P, 0))
        desc1 = tr["d4"].reshape(2, 8, 3)      # each half's 8 d4 nodes
        D1.append(np.repeat(desc1[None], P, 0))
        Y1.append(tr["c2"])
        V1.append(zscore(v1))
    def cat(xs): return np.concatenate(xs, axis=0)
    f32 = lambda x: mx.array(cat(x).astype(np.float32))
    i32 = lambda x: mx.array(cat(x).astype(np.int32))
    return (f32(T),
            (f32(C1), f32(S1), f32(K1), f32(D1), i32(Y1), f32(V1)))

def stage_loss(m, t, c, sp, kids, d, y, vz):
    v = m(t, c, sp, kids, d)                  # predicted value [N,C]
    lce = mx.mean(nn.losses.cross_entropy(-v, y))
    lval = mx.mean((v - vz) ** 2)
    return lce + lval

# ── Vectorized free descent + baselines + distortion ─────────────

def net_values(model, tr):
    """Stage-1 corrector values only (v4)."""
    P = len(tr["labs"])
    t = mx.array(tr["labs"].astype(np.float32))
    rep = lambda a: mx.array(np.repeat(a[None], P, 0).astype(np.float32))
    desc1 = tr["d4"].reshape(2, 8, 3)
    return np.array(model(t, rep(tr["d1"]), rep(tr["v1"]),
                          rep(tr["c1"]), rep(desc1)))

def free_descent(model, trees):
    hits = np.zeros(3); n = 0; nest_ok = True
    err_margin, hit_margin = [], []
    excess = []
    for tr in trees:
        c1 = net_values(model, tr).argmin(axis=1)
        labs = tr["labs"]; leaves = tr["leaves"]
        d2 = np.sum((labs[:, None, :] - leaves[None, :, :]) ** 2, axis=2)
        # stage 2 is LAW: exact-conditional lookahead over octet minima
        oct_min = np.stack([d2[:, o * 8:(o + 1) * 8].min(axis=1)
                            for o in range(16)], axis=1)
        masked = np.full_like(oct_min, np.inf)
        for h in (0, 1):
            sel = c1 == h
            masked[sel, h * 8:(h + 1) * 8] = oct_min[sel, h * 8:(h + 1) * 8]
        c16 = masked.argmin(axis=1)
        oct_mask = np.full_like(d2, np.inf)
        for p in range(len(labs)):
            o = c16[p]
            oct_mask[p, o * 8:(o + 1) * 8] = d2[p, o * 8:(o + 1) * 8]
        leaf = oct_mask.argmin(axis=1)
        hits[0] += (c1 == tr["c2"]).sum()
        hits[1] += (c16 == tr["c16"]).sum()
        hits[2] += (leaf == tr["leaf"]).sum()
        nest_ok &= bool(np.all(leaf >> 3 == c16) and np.all(c16 >> 3 == c1))
        n += len(labs)
        srt = np.sort(np.sqrt(d2), axis=1)
        margins = srt[:, 1] - srt[:, 0]
        wrong = leaf != tr["leaf"]
        err_margin += margins[wrong].tolist()
        hit_margin += margins[~wrong].tolist()
        # excess distortion of the CHOSEN leaf vs the teacher's
        chosen = np.sqrt(d2[np.arange(len(labs)), leaf])
        best = np.sqrt(d2[np.arange(len(labs)), tr["leaf"]])
        excess += (chosen - best).tolist()
    return hits / n, nest_ok, err_margin, hit_margin, float(np.mean(excess))

def lookahead_l2(trees):
    """The lawful spine as its own baseline: commit to the candidate
    whose DESCENDANT LAYER holds the nearest point (stage 1: min
    over its 8 depth-4 nodes; stage 2: min over its 8 leaves =
    exact conditional). The net must beat THIS, not just greedy."""
    hits = np.zeros(3); n = 0; excess = []
    for tr in trees:
        labs = tr["labs"]
        d4c = np.sum((labs[:, None, :] - tr["d4"][None]) ** 2, axis=2)
        c1 = np.stack([d4c[:, :8].min(axis=1),
                       d4c[:, 8:].min(axis=1)], axis=1).argmin(axis=1)
        d2 = np.sum((labs[:, None, :] - tr["leaves"][None]) ** 2, axis=2)
        oct_min = np.stack([d2[:, o * 8:(o + 1) * 8].min(axis=1)
                            for o in range(16)], axis=1)
        masked = np.full_like(oct_min, np.inf)
        for h in (0, 1):
            sel = c1 == h
            masked[sel, h * 8:(h + 1) * 8] = oct_min[sel, h * 8:(h + 1) * 8]
        c16 = masked.argmin(axis=1)
        oct_mask = np.full_like(d2, np.inf)
        for p in range(len(labs)):
            o = c16[p]
            oct_mask[p, o * 8:(o + 1) * 8] = d2[p, o * 8:(o + 1) * 8]
        leaf = oct_mask.argmin(axis=1)
        hits[0] += (c1 == tr["c2"]).sum()
        hits[1] += (c16 == tr["c16"]).sum()
        hits[2] += (leaf == tr["leaf"]).sum()
        n += len(labs)
        chosen = np.sqrt(d2[np.arange(len(labs)), leaf])
        best = np.sqrt(d2[np.arange(len(labs)), tr["leaf"]])
        excess += (chosen - best).tolist()
    return hits / n, float(np.mean(excess))

def greedy_l2(trees):
    hits = np.zeros(3); n = 0; excess = []
    for tr in trees:
        labs = tr["labs"]
        d1c = np.sum((labs[:, None, :] - tr["d1"][None]) ** 2, axis=2)
        c1 = d1c.argmin(axis=1)
        d4c = np.sum((labs[:, None, :] - tr["d4"][None]) ** 2, axis=2)
        masked = np.full_like(d4c, np.inf)
        for h in (0, 1):
            sel = c1 == h
            masked[sel, h * 8:(h + 1) * 8] = d4c[sel, h * 8:(h + 1) * 8]
        c16 = masked.argmin(axis=1)
        d2 = np.sum((labs[:, None, :] - tr["leaves"][None]) ** 2, axis=2)
        oct_mask = np.full_like(d2, np.inf)
        for p in range(len(labs)):
            o = c16[p]
            oct_mask[p, o * 8:(o + 1) * 8] = d2[p, o * 8:(o + 1) * 8]
        leaf = oct_mask.argmin(axis=1)
        hits[0] += (c1 == tr["c2"]).sum()
        hits[1] += (c16 == tr["c16"]).sum()
        hits[2] += (leaf == tr["leaf"]).sum()
        n += len(labs)
        chosen = np.sqrt(d2[np.arange(len(labs)), leaf])
        best = np.sqrt(d2[np.arange(len(labs)), tr["leaf"]])
        excess += (chosen - best).tolist()
    return hits / n, float(np.mean(excess))

# ── Train ────────────────────────────────────────────────────────

def main():
    samples = load()
    n_trees = len(samples)
    split = int(n_trees * 7 / 8)
    train_trees = assemble([s for s in samples if s["seed"] <= split])
    val_trees = assemble([s for s in samples if s["seed"] > split])
    print(f"corpus: {n_trees} trees -> {split} train / {n_trees - split} val")

    mx.random.seed(64)
    model = Scorer()
    n_params = sum(v.size for _, v in tree_flatten(model.parameters()))

    t, st1 = batch(train_trees)

    def loss_fn(m):
        return stage_loss(m, t, *st1)      # stage 1 ONLY (v4)

    first = float(loss_fn(model).item())
    mx.random.seed(64)
    g1 = abs(float(loss_fn(Scorer()).item()) - first) < 1e-6

    opt = optim.AdamW(learning_rate=3e-3, weight_decay=1e-4)
    lg = nn.value_and_grad(model, loss_fn)
    for it in range(2000):
        l, grads = lg(model)
        opt.update(model, grads)
        mx.eval(model.parameters())
        if it % 200 == 0:
            print(f"  iter {it:4d}  loss {float(l.item()):.4f}")

    base_v, base_ex = greedy_l2(val_trees)
    look_v, look_ex = lookahead_l2(val_trees)
    acc_v, nest_ok, err_m, hit_m, net_ex = free_descent(model, val_trees)
    base_t, _ = greedy_l2(train_trees)
    look_t, _ = lookahead_l2(train_trees)
    acc_t, _, _, _, _ = free_descent(model, train_trees)

    g2 = acc_v[2] >= look_v[2]
    g3 = nest_ok
    med_err = float(np.median(err_m)) if err_m else 0.0
    med_hit = float(np.median(hit_m)) if hit_m else 0.0
    g4 = (not err_m) or med_err < med_hit

    print()
    print(f"  exits (vs teacher), VAL:  net {acc_v.round(4).tolist()}  "
          f"lookahead {look_v.round(4).tolist()}  greedy {base_v.round(4).tolist()}")
    print(f"  exits, TRAIN:             net {acc_t.round(4).tolist()}  "
          f"lookahead {look_t.round(4).tolist()}  greedy {base_t.round(4).tolist()}")
    print(f"  mean EXCESS distortion (val): net {net_ex:.6f}  "
          f"lookahead {look_ex:.6f}  greedy {base_ex:.6f}")
    print(f"  G1 determinism: {'✓' if g1 else '✗'}")
    print(f"  G2 net >= LOOKAHEAD on val leaf: {'✓' if g2 else '✗'} "
          f"({acc_v[2]:.4f} vs {look_v[2]:.4f})")
    print(f"  G3 output nesting structural (DL2): {'✓' if g3 else '✗'}")
    print(f"  G4 errors are near-ties: {'✓' if g4 else '✗'} "
          f"(median margin errors {med_err:.5f} vs hits {med_hit:.5f})")
    print(f"  G5 params REPORTED: {n_params}")

    flat = dict(tree_flatten(model.parameters()))
    np.savez("scorer_weights.npz", **{k: np.array(v) for k, v in flat.items()})
    json.dump(dict(
        trees=n_trees,
        train=dict(net=acc_t.tolist(), greedy=base_t.tolist()),
        val=dict(net=acc_v.tolist(), lookahead=look_v.tolist(),
                 greedy=base_v.tolist()),
        excess=dict(net=net_ex, lookahead=look_ex, greedy=base_ex),
        gates=dict(G1=bool(g1), G2=bool(g2), G3=bool(g3), G4=bool(g4)),
        margins=dict(median_error=med_err, median_hit=med_hit,
                     n_errors=len(err_m)),
        params=int(n_params),
    ), open("results.json", "w"), indent=2)
    print("  saved scorer_weights.npz + results.json")

if __name__ == "__main__":
    main()
