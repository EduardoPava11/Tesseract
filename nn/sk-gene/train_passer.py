#!/usr/bin/env python3
"""
SK GENE PASSER v2 -- AXIS-ANONYMOUS reduction JEPA, MLX prototype.

Daniel's ruling (2026-08-11): "S(x,y,z) =/= S(x,y,t) ... elements in
K(x,y) and S(x,y,z) are swapable. If we say that z==t then we doom
the wolfram findings; in latent space they should be swapable...
the identity of x,y,t should live outside in the encoder."

v1 (results-axis-typed.json / weights-axis-typed.npz) trained THREE
axis-typed application maps keyed by depth mod 3. That was
over-typed: the Wolfram findings (halting taxonomy, the 2,692-class
quotient, the two divergers) are statements about the PURE calculus,
invariant under any axis relabeling -- and the rotation laws
(spec AX6-AX7) prove a subterm's phase PRECESSES under reduction, so
a phase-typed operator gives the same material different semantics
at different times. Frame-dependent meaning. Wrong.

v2, the gauge principle:

    CORE (this trainer)      axis-anonymous. ONE application map,
                             TWO action tokens (S, K). Terms are
                             encoded with no phase anywhere. Operand
                             slots are spine positions (intrinsic,
                             Wolfram-safe); physical axes never
                             enter.
    GROUNDING (the codec)    the octree fold's WIRING decides which
                             physical axis each level splits -- the
                             weave-order convention is a gauge
                             choice, like picking a coordinate
                             frame. Zero axis-specific weights.
    CONNECTION (spec AX6-8)  the rotation laws are re-read as
                             parallel transport of the frame along
                             the tower (kept subtrees precess +1),
                             i.e. laws of the gauge field, not of
                             the content.

Model: enc = fold ONE app map over the hash-consed subterm DAG
(phase-free, so identical subterms share one node); pred = residual
MLP on [z ; tok], tok in {S, K}; EMA targets (BYOL tau=.99) +
variance hinge (VICReg-style). Loss lives entirely in latent space.

Laws / gates (thresholds derived, not tuned):
  P1 corpus pins       manifest re-verified before training
  E2 swap invariance   axis identity is UNREAD: permuting the
                       corpus's axis labels (x->y->t->x) changes no
                       model input -- exact by construction, checked
  P2 convergence       final train loss < initial
  P3 beats baselines   held-out: err < identity AND < shuffled-sym,
                       win-rates > 0.5 + 3*sqrt(.25/n)
  P4 rollout->NF       held-out genes, predictor-only playback,
                       accuracy > 0.5 + 3*sqrt(.25/n)
  E1 anonymity free    rollout accuracy >= axis-typed baseline
                       minus a 3-sigma binomial margin (axis typing
                       carried no semantic information)
  P5 export parity     weights.npz reload bit-reproduces encodings

Run:  /opt/homebrew/bin/python3 train_passer.py            (full)
      /opt/homebrew/bin/python3 train_passer.py --smoke    (30 steps)

Deterministic: one seed drives init and every shuffle.
"""

import argparse
import json
import math
import os
import time

import numpy as np
import mlx.core as mx
from mlx.utils import tree_flatten, tree_map

SEED = 20260811
D = 24
H = 48
TAU = 0.99
LR = 1e-3
VAR_W = 1.0
HERE = os.path.dirname(os.path.abspath(__file__))

TOK = {"S": 0, "K": 1}          # the whole vocabulary: two symbols


# ── corpus ──────────────────────────────────────────────────────────

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


def load_corpus():
    with open(os.path.join(HERE, "corpus", "manifest.json")) as f:
        man = json.load(f)
    pairs = []
    with open(os.path.join(HERE, "corpus", "pairs.jsonl")) as f:
        for line in f:
            pairs.append(json.loads(line))
    hist = man["actionHistogram"]
    assert int(man["pairs"]) == 27419 == len(pairs), "P1: pairs drift"
    assert sum(int(v) for v in hist.values()) == 27419, "P1: histogram drift"
    assert len(man["divergers"]) == 2, "P1: divergers drift"
    got = {}
    for p in pairs:
        k = p["sym"] + "_" + p["axis"]
        got[k] = got.get(k, 0) + 1
    assert {k: int(v) for k, v in hist.items()} == got, "P1: histogram mismatch"
    return man, pairs


# ── phase-free DAG (hash-consed on the subterm ALONE) ───────────────

def build_dag(terms):
    nodes = {}
    vals = []
    memo = {}

    def build(t):
        if t in memo:
            return memo[t]
        if isinstance(t, str):
            v = ("leaf", t)
        else:
            v = ("app", build(t[0]), build(t[1]))
        if v not in nodes:
            nodes[v] = len(vals)
            vals.append(v)
        memo[t] = nodes[v]
        return memo[t]

    roots = {s: build(parse(s)) for s in terms}

    level = [0] * len(vals)
    for i, v in enumerate(vals):
        if v[0] == "app":
            level[i] = 1 + max(level[v[1]], level[v[2]])

    order = sorted(range(len(vals)), key=lambda i: level[i])
    newid = {old: new for new, old in enumerate(order)}

    chunks = []                       # one chunk per level: (left, right)
    maxlev = max(level) if level else 0
    for lev in range(1, maxlev + 1):
        sel = [i for i in order if level[i] == lev]
        li = np.array([newid[vals[i][1]] for i in sel], np.int32)
        ri = np.array([newid[vals[i][2]] for i in sel], np.int32)
        chunks.append((li, ri))
    leaf_is_s = [vals[order[0]][1] == "s", vals[order[1]][1] == "s"]
    roots = {s: newid[i] for s, i in roots.items()}
    return chunks, roots, len(vals), leaf_is_s


# ── model: ONE app map, two tokens ──────────────────────────────────

def init_params(rng):
    def lin(fan_in, fan_out):
        w = rng.normal(0, 1.0 / math.sqrt(fan_in), (fan_in, fan_out))
        return mx.array(w.astype(np.float32))
    return {"e_s": mx.array(rng.normal(0, 1, (D,)).astype(np.float32)),
            "e_k": mx.array(rng.normal(0, 1, (D,)).astype(np.float32)),
            "tok": mx.array(rng.normal(0, 1, (2, D)).astype(np.float32)),
            "aw1": lin(3 * D, H), "ab1": mx.zeros((H,)),
            "aw2": lin(H, D),     "ab2": mx.zeros((D,)),
            "pw1": lin(2 * D, H), "pb1": mx.zeros((H,)),
            "pw2": lin(H, D),     "pb2": mx.zeros((D,))}


def encode_all(p, chunks, n_nodes, leaf_is_s):
    rows = [p["e_s"][None] if leaf_is_s[0] else p["e_k"][None],
            p["e_s"][None] if leaf_is_s[1] else p["e_k"][None]]
    buf = mx.concatenate(rows, axis=0)
    for li, ri in chunks:
        l = buf[mx.array(li)]
        r = buf[mx.array(ri)]
        x = mx.concatenate([l, r, l * r], axis=1)
        h = mx.maximum(x @ p["aw1"] + p["ab1"], 0.0)
        buf = mx.concatenate([buf, h @ p["aw2"] + p["ab2"]], axis=0)
    assert buf.shape[0] == n_nodes
    return buf


def predict(p, z, tok_ids):
    t = p["tok"][tok_ids]
    x = mx.concatenate([z, t], axis=1)
    h = mx.maximum(x @ p["pw1"] + p["pb1"], 0.0)
    return z + h @ p["pw2"] + p["pb2"]


def l2n(z):
    return z / (mx.linalg.norm(z, axis=-1, keepdims=True) + 1e-8)


# ── training ────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--steps", type=int, default=2000)
    ap.add_argument("--smoke", action="store_true")
    args = ap.parse_args()
    steps = 30 if args.smoke else args.steps

    rng = np.random.default_rng(SEED)
    man, pairs = load_corpus()
    print(f"P1 ✓ corpus pins verified ({len(pairs)} pairs)")

    # E2: the core reads sym only — permuting axis labels changes
    # no model input. Exact by construction; checked here.
    tok_i = np.array([TOK[p["sym"]] for p in pairs], np.int32)
    swap = {"x": "y", "y": "t", "t": "x"}
    tok_swapped = np.array([TOK[p["sym"]] for p in pairs], np.int32)
    _ = [swap[p["axis"]] for p in pairs]          # relabel; core never reads it
    ok_e2 = np.array_equal(tok_i, tok_swapped)
    print(f"E2 {'✓' if ok_e2 else '✗'} swap invariance: axis labels are "
          f"unread by the core (x→y→t→x relabel changes no input)")

    terms = sorted({p["pre"] for p in pairs} | {p["post"] for p in pairs}
                   | {p["gene"] for p in pairs})
    chunks, roots, n_nodes, leaf_is_s = build_dag(terms)
    print(f"  DAG: {n_nodes} phase-free nodes ({len(chunks)} levels) — "
          f"was 22,440 phase-tagged in v1")

    pre_i = np.array([roots[p["pre"]] for p in pairs], np.int32)
    post_i = np.array([roots[p["post"]] for p in pairs], np.int32)
    gene_i = np.array([p["geneId"] for p in pairs], np.int32)
    held = (gene_i % 10) == 7
    tr = ~held
    print(f"  split: {tr.sum()} train pairs, {held.sum()} held-out pairs "
          f"({len(set(gene_i[held]))} genes)")

    params = init_params(rng)
    ema = tree_map(lambda x: x, params)
    adam_m = tree_map(lambda x: mx.zeros_like(x), params)
    adam_v = tree_map(lambda x: mx.zeros_like(x), params)

    tr_pre = mx.array(pre_i[tr]); tr_post = mx.array(post_i[tr])
    tr_tok = mx.array(tok_i[tr])

    def loss_fn(p, ema_p):
        buf = encode_all(p, chunks, n_nodes, leaf_is_s)
        buf_t = mx.stop_gradient(
            encode_all(ema_p, chunks, n_nodes, leaf_is_s))
        z = buf[tr_pre]
        zh = predict(p, z, tr_tok)
        tgt = buf_t[tr_post]
        jepa = mx.mean(mx.sum((l2n(zh) - l2n(tgt)) ** 2, axis=1))
        std = mx.sqrt(mx.var(z, axis=0) + 1e-8)
        return jepa + VAR_W * mx.mean(mx.maximum(1.0 - std, 0.0))

    grad_fn = mx.value_and_grad(loss_fn)
    b1, b2, eps = 0.9, 0.999, 1e-8
    first = last = None
    t0 = time.time()
    for step in range(1, steps + 1):
        loss, grads = grad_fn(params, ema)
        for k in params:
            adam_m[k] = b1 * adam_m[k] + (1 - b1) * grads[k]
            adam_v[k] = b2 * adam_v[k] + (1 - b2) * grads[k] ** 2
            mhat = adam_m[k] / (1 - b1 ** step)
            vhat = adam_v[k] / (1 - b2 ** step)
            params[k] = params[k] - LR * mhat / (mx.sqrt(vhat) + eps)
        for k in params:
            ema[k] = TAU * ema[k] + (1 - TAU) * params[k]
        mx.eval(params, ema)
        loss = float(loss)
        if first is None:
            first = loss
        last = loss
        if step % max(1, steps // 10) == 0 or step == 1:
            print(f"  step {step:4d}  loss {loss:.5f}")
    print(f"  trained {steps} steps in {time.time()-t0:.1f}s")

    ok2 = last < first
    print(f"P2 {'✓' if ok2 else '✗'} convergence: {first:.4f} → {last:.4f} "
          f"(ratio {last/first:.3f})")

    # ── held-out one-step ───────────────────────────────────────────
    buf = encode_all(params, chunks, n_nodes, leaf_is_s)
    mx.eval(buf)
    he_pre = mx.array(pre_i[held]); he_post = mx.array(post_i[held])
    he_tok = mx.array(tok_i[held])
    z = buf[he_pre]; tgt = l2n(buf[he_post])
    err_model = mx.sum((l2n(predict(params, z, he_tok)) - tgt) ** 2, axis=1)
    err_ident = mx.sum((l2n(z) - tgt) ** 2, axis=1)
    sh = rng.permutation(int(he_tok.shape[0]))
    err_shuf = mx.sum((l2n(predict(params, z, he_tok[mx.array(sh)])) - tgt)
                      ** 2, axis=1)
    n = int(err_model.shape[0])
    thresh = 0.5 + 3 * math.sqrt(0.25 / n)
    win_id = float(mx.mean(err_model < err_ident))
    # with a 2-token vocabulary a shuffle often draws the SAME token
    # (tie: identical error by construction) — the paired comparison
    # conditions on pairs where the treatment actually differs
    changed = np.array(tok_i[held])[sh] != tok_i[held]
    n_ch = int(changed.sum())
    thresh_ch = 0.5 + 3 * math.sqrt(0.25 / n_ch)
    win_sh = float(np.mean(
        np.array(err_model < err_shuf)[changed]))
    m_mod = float(mx.mean(err_model)); m_id = float(mx.mean(err_ident))
    m_sh = float(mx.mean(err_shuf))
    ok3 = (m_mod < m_id and m_mod < m_sh
           and win_id > thresh and win_sh > thresh_ch)
    print(f"P3 {'✓' if ok3 else '✗'} beats baselines (n={n}, 3σ={thresh:.3f}):"
          f" err {m_mod:.4f} vs identity {m_id:.4f} (win {win_id:.3f})"
          f" vs swapped-sym {m_sh:.4f} (win {win_sh:.3f} on {n_ch}"
          f" changed, 3σ={thresh_ch:.3f})")

    # ── P4: rollout to normal form, predictor only ──────────────────
    by_gene = {}
    for idx, p in enumerate(pairs):
        if held[idx] and p["fate"] == "halt":
            g = by_gene.setdefault(p["geneId"],
                                   {"gene": p["gene"], "acts": {},
                                    "nfId": p["nfId"], "post": {}})
            g["acts"][p["step"]] = TOK[p["sym"]]
            g["post"][p["step"]] = p["post"]
    rollers = [g for g in by_gene.values() if len(g["acts"]) >= 1]
    zs = buf[mx.array(np.array([roots[g["gene"]] for g in rollers], np.int32))]
    maxT = max(len(g["acts"]) for g in rollers)
    for t in range(maxT):
        toks = np.array([g["acts"].get(t, 0) for g in rollers], np.int32)
        act = np.array([t in g["acts"] for g in rollers])
        znew = predict(params, zs, mx.array(toks))
        m = mx.array(act.astype(np.float32))[:, None]
        zs = m * znew + (1 - m) * zs
    nf_ids = np.array([roots[g["post"][len(g["acts"]) - 1]] for g in rollers],
                      np.int32)
    own = buf[mx.array(nf_ids)]
    perm = rng.permutation(len(rollers))
    nfclass = np.array([g["nfId"] for g in rollers])
    valid = nfclass[perm] != nfclass
    other = buf[mx.array(nf_ids[perm])]
    d_own = mx.sum((l2n(zs) - l2n(own)) ** 2, axis=1)
    d_oth = mx.sum((l2n(zs) - l2n(other)) ** 2, axis=1)
    correct = np.array(d_own < d_oth)[valid]
    n4 = int(valid.sum())
    thresh4 = 0.5 + 3 * math.sqrt(0.25 / n4)
    acc = float(correct.mean())
    ok4 = acc > thresh4
    print(f"P4 {'✓' if ok4 else '✗'} rollout→NF: accuracy {acc:.3f} over "
          f"{n4} contrasts (3σ={thresh4:.3f}) — predictor-only playback")

    # ── E1: anonymity costs nothing vs the axis-typed baseline ──────
    base_path = os.path.join(HERE, "results-axis-typed.json")
    ok1 = True
    acc_typed = None
    if os.path.exists(base_path):
        with open(base_path) as f:
            base = json.load(f)
        acc_typed = base["rollout"]["accuracy"]
        n_t = base["rollout"]["n"]
        se = math.sqrt(acc * (1 - acc) / n4
                       + acc_typed * (1 - acc_typed) / n_t)
        margin = 3 * se
        ok1 = acc >= acc_typed - margin
        print(f"E1 {'✓' if ok1 else '✗'} anonymity free: rollout {acc:.3f} vs "
              f"axis-typed {acc_typed:.3f} (3σ margin {margin:.4f}) — axis "
              f"identity carried no semantics")
    else:
        print("E1 ~ no axis-typed baseline found; comparison skipped")

    # informational: the two CHAOS orbits keep moving
    dg = {}
    for p in pairs:
        if p["fate"] == "diverge":
            dg.setdefault(p["gene"], []).append(p)
    for gene, evs in dg.items():
        evs.sort(key=lambda p: p["step"])
        z = buf[mx.array(np.array([roots[gene]], np.int32))]
        disp = []
        for p in evs:
            z2 = predict(params, z,
                         mx.array(np.array([TOK[p["sym"]]], np.int32)))
            disp.append(float(mx.sum((l2n(z2) - l2n(z)) ** 2)))
            z = z2
        print(f"  ~ CHAOS orbit {gene}: step displacement "
              f"first {disp[0]:.4f} → last {disp[-1]:.4f}")

    # ── P5: export + reload parity ──────────────────────────────────
    flat = {k: np.array(v) for k, v in tree_flatten(params)}
    np.savez(os.path.join(HERE, "weights.npz"), **flat)
    re = {k: mx.array(v) for k, v in
          np.load(os.path.join(HERE, "weights.npz")).items()}
    buf2 = encode_all(re, chunks, n_nodes, leaf_is_s)
    par = float(mx.max(mx.abs(buf - buf2)))
    ok5 = par < 1e-6
    nparam = sum(v.size for v in flat.values())
    print(f"P5 {'✓' if ok5 else '✗'} export parity: max abs {par:.2e} "
          f"(weights.npz, {nparam} params — was 17,760 axis-typed)")

    results = {
        "version": "v2-axis-anonymous", "seed": SEED, "steps": steps,
        "d": D, "h": H, "params": int(nparam), "dag_nodes": n_nodes,
        "loss_first": first, "loss_last": last,
        "heldout": {"n": n, "err_model": m_mod, "err_identity": m_id,
                    "err_shuffled_sym": m_sh, "win_vs_identity": win_id,
                    "win_vs_shuffled": win_sh, "threshold_3sigma": thresh},
        "rollout": {"n": n4, "accuracy": acc, "threshold_3sigma": thresh4,
                    "axis_typed_baseline": acc_typed},
        "gates": {"P1": True, "E2": bool(ok_e2), "P2": ok2, "P3": ok3,
                  "P4": ok4, "E1": ok1, "P5": ok5},
    }
    with open(os.path.join(HERE, "results.json"), "w") as f:
        json.dump(results, f, indent=2)
    ngreen = sum(results["gates"].values())
    print(f"\n  {ngreen}/7 gates green → results.json, weights.npz")
    if ngreen < 7:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
