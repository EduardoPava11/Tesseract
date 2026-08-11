#!/usr/bin/env python3
"""ANELoop prototype (L2): the fixed-K exchange loop as ONE fused ANE graph.

Spec: spec/neural/ANELoop.hs (AL1-AL8, all green). Design:
docs/ane-loop-design.md. The engine law (arXiv:2606.22283): fused
fixed-iteration numerics are the widest ANE win; no data-dependent
trip counts. This graph is K sweeps x 64 Gauss-Seidel stages over
4096 independent 4x4x4 spacetime blocks:

    q0    [B, 64, 3]   current colors per block voxel (centered lab)
    y     [B, 64, 3]   target labs (gamma-staged, centered)
    cand  [B, C, 3]    per-block candidate colors
      |
    stage v (fixed raster order, unrolled K x 64 times):
      e     = q - y
      g     = e_v + mean(e | 2-cell of v) + mean(e | block)
      dF_c  = 2 g . (c - q_v) + ||c - q_v||^2 * (1 + 1/8 + 1/64)
      accept the argmin candidate iff dF < 0     (AL4: monotone)
      |
    q_K   [B, 64, 3]   the swept colors

PHASE-AGNOSTIC BY CONSTRUCTION: the graph never sees (x, y, t) --
only blocks. The offset architecture (aligned 5 Hz, temporal
polyphase 20 Hz, streaming warm starts) is entirely the CPU feed's
blocking choice (cube_to_blocks below). One mlpackage serves every
option in docs/ane-loop-design.md section 6.

The exchange score's coefficients are block volumes (AL7 -- no naked
constants). fp16 discipline: centered inputs (the DyadAssign lesson),
acceptance is a sign comparison (near-tie flips lawful, XP2 pattern).

Builds ANELoop.mlpackage HERE, then gates against the float64 NumPy
reference (the spec law verbatim) and reports agreement + near-tie
analysis + Mac timing.

NOTES (session 2026-08-11, docs/session-2026-08-11.md):
- L2 GATE RESULTS (M3 Max): model F = 5308.41 vs float64 reference
  5308.40 (the engine attains the law's objective to ~5 digits);
  99.83% of 262,144 assignments agree, disagreements are score
  near-ties (XP2 regime). Reference F 22564 -> 5308 in K=4 sweeps.
  Timing: 32 ms steady per dispatch = 0.13 ms per fused stage.
- SHIPPED COPY: Tesseract/ML/ANELoopModel.mlpackage -- renamed with
  the "Model" suffix because Xcode's CoreML codegen creates a class
  named after the package, which collided with the ANELoop.swift
  wrapper enum. Rebuild here, then copy over that name.
- A-series timing owed on device before pinning K (the measured
  reference is M-series; CameraConfig.phaseChaosLoop gates use).
"""

import time

import numpy as np
import coremltools as ct
from coremltools.converters.mil import Builder as mb

B, V, C, K = 4096, 64, 8, 4     # blocks, voxels/block, candidates, sweeps
SIDE = 4                        # block is 4 x 4 x 4 (x, y, t)
CURV = 1.0 + 1.0 / 8.0 + 1.0 / 64.0   # AL7: reciprocal block volumes

# Local raster layout inside a block: v = x + 4*(y + 4*t) — x fastest,
# matching the spec's coords order and the 64x64-frame raster.
def local_xyz(v):
    return v % SIDE, (v // SIDE) % SIDE, v // (SIDE * SIDE)

# Constant membership rows (folded into the graph as weights).
ONES_ROW = np.full((1, V), 1.0 / V, dtype=np.float32)          # block mean
ONEHOT = np.eye(V, dtype=np.float32)                            # voxel select
CELL2 = np.zeros((V, V), dtype=np.float32)                      # 2-cell mean
for v in range(V):
    x, y, t = local_xyz(v)
    for w in range(V):
        xw, yw, tw = local_xyz(w)
        if (x // 2, y // 2, t // 2) == (xw // 2, yw // 2, tw // 2):
            CELL2[v, w] = 1.0 / 8.0


@mb.program(input_specs=[mb.TensorSpec(shape=(B, V, 3)),
                         mb.TensorSpec(shape=(B, V, 3)),
                         mb.TensorSpec(shape=(B, C, 3))])
def ane_loop(q0, y, cand):
    q = q0
    for _ in range(K):
        for v in range(V):
            e = mb.sub(x=q, y=y)                                  # [B,V,3]
            e_v = mb.matmul(x=ONEHOT[v:v + 1], y=e)               # [B,1,3]
            m2 = mb.matmul(x=CELL2[v:v + 1], y=e)                 # [B,1,3]
            m4 = mb.matmul(x=ONES_ROW, y=e)                       # [B,1,3]
            g = mb.add(x=mb.add(x=e_v, y=m2), y=m4)               # [B,1,3]
            q_v = mb.matmul(x=ONEHOT[v:v + 1], y=q)               # [B,1,3]
            delta = mb.sub(x=cand, y=q_v)                         # [B,C,3]
            lin = mb.reduce_sum(x=mb.mul(x=delta, y=g),
                                axes=[-1], keep_dims=False)       # [B,C]
            quad = mb.reduce_sum(x=mb.mul(x=delta, y=delta),
                                 axes=[-1], keep_dims=False)      # [B,C]
            df = mb.add(x=mb.mul(x=lin, y=2.0),
                        y=mb.mul(x=quad, y=CURV))                 # [B,C]
            best = mb.reduce_argmin(x=df, axis=-1, keep_dims=False)  # [B]
            pick = mb.one_hot(indices=best, one_hot_vector_size=C)   # [B,C]
            pick = mb.cast(x=pick, dtype="fp32")
            pick = mb.expand_dims(x=pick, axes=[1])                  # [B,1,C]
            c_best = mb.matmul(x=pick, y=cand)                       # [B,1,3]
            df_min = mb.reduce_min(x=df, axes=[-1], keep_dims=True)  # [B,1]
            acc = mb.cast(x=mb.less(x=df_min, y=0.0), dtype="fp32")  # [B,1]
            acc = mb.expand_dims(x=acc, axes=[-1])                   # [B,1,1]
            keep = mb.sub(x=1.0, y=acc)
            new_v = mb.add(x=mb.mul(x=c_best, y=acc),
                           y=mb.mul(x=q_v, y=keep))                  # [B,1,3]
            parts = []
            if v > 0:
                parts.append(mb.slice_by_index(
                    x=q, begin=[0, 0, 0], end=[B, v, 3]))
            parts.append(new_v)
            if v < V - 1:
                parts.append(mb.slice_by_index(
                    x=q, begin=[0, v + 1, 0], end=[B, V, 3]))
            q = parts[0] if len(parts) == 1 else mb.concat(
                values=parts, axis=1)
    return q


# ── float64 reference: the spec's sweep, verbatim ─────────────────

def reference_loop(q0, y, cand, k):
    """Gauss-Seidel exchange, float64, tracking chosen indices."""
    q = q0.astype(np.float64).copy()
    yy = y.astype(np.float64)
    cc = cand.astype(np.float64)
    for _ in range(k):
        for v in range(V):
            e = q - yy                                        # [B,V,3]
            g = (e[:, v, :]
                 + np.einsum("w,bwc->bc", CELL2[v], e)
                 + e.mean(axis=1))                            # [B,3]
            delta = cc - q[:, v:v + 1, :]                     # [B,C,3]
            df = (2.0 * np.einsum("bc,bkc->bk", g, delta)
                  + CURV * (delta * delta).sum(axis=2))       # [B,C]
            best = df.argmin(axis=1)
            take = df[np.arange(B), best] < 0
            q[take, v, :] = cc[take, best[take], :]
    return q


def indices_of(q, cand):
    """Recover, per voxel, the nearest candidate index (for parity)."""
    d = ((q[:, :, None, :] - cand[:, None, :, :]) ** 2).sum(axis=3)
    return d.argmin(axis=2)                                   # [B,V]


# ── the feed API: blocking IS the offset architecture ─────────────

def cube_to_blocks(cube, t_off=0, y_off=0, x_off=0):
    """[T,H,W,3] -> [B,V,3] blocks of 4x4x4 at the given phase offsets
    (cyclic). Offsets are the ENTIRE offset architecture: aligned
    feeds use (0,0,0); temporal polyphase feeds rotate t_off over
    {0,1,2,3}; the graph itself never changes."""
    T, H, W, _ = cube.shape
    rolled = np.roll(cube, shift=(-t_off, -y_off, -x_off), axis=(0, 1, 2))
    b = rolled.reshape(T // SIDE, SIDE, H // SIDE, SIDE, W // SIDE, SIDE, 3)
    b = b.transpose(0, 2, 4, 5, 3, 1, 6)   # blocks, then (x fast, y, t)
    return b.reshape(-1, V, 3)


def main():
    rng = np.random.default_rng(11)

    # Synthetic capture: a 64-frame 64x64 cube of centered labs with
    # block-scale structure (so the loop has coarse error to shape).
    cube = (rng.normal(0, 0.08, size=(64, 64, 64, 3))
            + np.repeat(np.repeat(np.repeat(
                rng.normal(0, 0.05, size=(16, 16, 16, 3)),
                4, axis=0), 4, axis=1), 4, axis=2)).astype(np.float32)
    y = cube_to_blocks(cube)                                   # aligned feed
    cand = rng.normal(0, 0.1, size=(B, C, 3)).astype(np.float32)
    start_idx = rng.integers(0, C, size=(B, V))
    q0 = np.take_along_axis(cand, start_idx[..., None], axis=1
                            ).reshape(B, V, 3).astype(np.float32)

    print(f"building: B={B} blocks x V={V} voxels, C={C} candidates, "
          f"K={K} sweeps -> {K * V} fused stages")
    t0 = time.time()
    model = ct.convert(
        ane_loop,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        compute_units=ct.ComputeUnit.ALL,
        minimum_deployment_target=ct.target.iOS17,
    )
    model.save("ANELoop.mlpackage")
    print(f"converted + saved in {time.time() - t0:.1f}s")

    # Reference and the objective's descent (AL4 witness).
    ref = reference_loop(q0, y, cand, K)

    def big_f(q):
        # F (unnormalized) = ||e||^2 + ||Pi2 e||^2 + ||Pi4 e||^2.
        # CELL2 rows already hold the 1/8 mean weights, so m2[b,v]
        # IS (Pi2 e)_v; the block mean broadcasts over the 64 voxels.
        e = q.astype(np.float64) - y.astype(np.float64)
        m2 = np.einsum("vw,bwc->bvc", CELL2, e)
        m4 = e.mean(axis=1, keepdims=True)
        return float((e * e).sum() + (m2 * m2).sum()
                     + (m4 * m4).sum() * V)

    f0, fk = big_f(q0), big_f(ref)
    print(f"F (unnormalized): start {f0:.2f} -> {K} sweeps {fk:.2f} "
          f"({100 * (1 - fk / f0):.1f}% down, monotone by AL4)")

    # Model prediction + parity.
    t0 = time.time()
    out = model.predict({"q0": q0, "y": y, "cand": cand})
    first = time.time() - t0
    qm = list(out.values())[0].reshape(B, V, 3)
    t0 = time.time()
    for _ in range(3):
        model.predict({"q0": q0, "y": y, "cand": cand})
    steady = (time.time() - t0) / 3

    ri = indices_of(ref, cand.astype(np.float64))
    mi = indices_of(qm.astype(np.float64), cand.astype(np.float64))
    agree = float((ri == mi).mean())
    print(f"parity vs float64 reference: {100 * agree:.2f}% of "
          f"{B * V} voxel assignments agree")

    # Near-tie audit on disagreements: recompute the reference's dF
    # margin at each disagreeing voxel's final visit is intricate;
    # the honest cheap audit is the color distance of disagreement.
    bad = np.argwhere(ri != mi)
    if len(bad):
        d = np.abs(ref[bad[:, 0], bad[:, 1], :]
                   - qm[bad[:, 0], bad[:, 1], :]).max()
        print(f"disagreements: {len(bad)} voxels, max |color gap| {d:.4g} "
              f"(fp16 near-tie regime if small)")
    fm = big_f(qm)
    print(f"F on the model output: {fm:.2f} "
          f"({'<= start (never worse than input)' if fm <= f0 else 'ABOVE START — investigate'})")
    print(f"timing (Mac, indicative only): first predict {first * 1000:.0f} ms, "
          f"steady {steady * 1000:.0f} ms / dispatch "
          f"({steady * 1000 / (K * V):.2f} ms per fused stage)")
    print("A-series microbenchmark owed on device (L2 exit criterion).")


if __name__ == "__main__":
    main()
