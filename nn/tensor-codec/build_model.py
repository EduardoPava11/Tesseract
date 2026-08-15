#!/usr/bin/env python3
"""TensorEncode: the capture tensor's ENCODE as ONE fused ANE graph.

Daniel, 2026-08-14: "I need ANE to be able to encode+compress the
signal information."

Spec: spec/neural/TensorEncoder.hs (TA1-TA9, all green). The bytes it
produces are spec/output/CaptureTensor.hs's (CT1-CT11); the ladder is
Octave.hs's; the wire format is FeedCompression.hs's. This script owns
only the graph.

★ WHY THIS FITS THE ENGINE AT ALL (TA1). The 2x2x2 spacetime pool
FACTORS into a temporal pair-average and a spatial 2x2 average, and
the two commute. Fold frame pairs into the channel axis and the
temporal half becomes a 1x1 CONVOLUTION; the spatial half is a stock
avg_pool. So the octave transform needs no 3D operator -- the thing
the engine is worst at -- and is built entirely from the two things
it is best at.

    cube   [64, 3, 64, 64]   fine rung, OKLab, 20 fps
      |  fold pairs to channels -> conv 6->3 (weights 1/2) -> avg_pool 2x2
    l32    [32, 3, 32, 32]   10 fps
      |  the same two operators again
    l16    [16, 3, 16, 16]   5 fps -- its 256 cells per tick ARE the palette
      |
    parent = nearest-upsample(l_coarse)     x2 in all three axes
    r      = l_fine - parent                the residual
    sign   = r >= 0                         THE STORED BIT (CT4)
    dev    = pool(|r|)                      what the threshold is fitted to

The CPU keeps exactly two jobs, and neither is dense: fit the
two-phase mixture that DERIVES the significance threshold (CT7 -- a
fit over 4096 numbers, not 262144), and pack the bitstream. Every
per-voxel operation is on the engine.

fp16 discipline, and why it is not a compromise here (TA3/TA5):
  - the coarse picture is 3 x fp16 = 48 bits per cell, INSIDE the 64
    bits CT2 already forced. The engine's native precision costs the
    rung that is the palette nothing.
  - the only decision the graph makes is a sign, and a flipped sign
    costs exactly 2*min(|r|, g) of extra error -- not 2g. A flip can
    only happen where |r| is under the engine's resolution, so it is
    bounded by twice that. This is the encoder's XP2.

Builds TensorEncode.mlpackage HERE, then gates it against a float64
NumPy reference (the spec law verbatim) and reports sign agreement,
deviation error, and Mac timing. Copy to
Tesseract/Learn/ML/TensorEncode.mlpackage when the gate passes.
"""

import time

import numpy as np
import coremltools as ct
from coremltools.converters.mil import Builder as mb

F64, S64, CH = 64, 64, 3        # fine rung: 64 frames of 64x64, 3 channels
F32, S32 = 32, 32
F16, S16 = 16, 16

# CT8: a loud rung-16 root carries 8 rung-32 children and 64 rung-64
# descendants. The subtree statistic weights them by how many they are,
# so the deviation is the plain mean over all 72 -- no chosen constant.
N32, N64 = 8, 64
NSUB = N32 + N64                # 72


def fold_weight():
    """conv 6->3 averaging a folded frame pair: out[c] = (a[c]+b[c])/2."""
    w = np.zeros((CH, 2 * CH, 1, 1), dtype=np.float32)
    for c in range(CH):
        w[c, c, 0, 0] = 0.5
        w[c, c + CH, 0, 0] = 0.5
    return w


def unfold_weight():
    """conv 3->6 duplicating a frame: both halves of the pair get it."""
    w = np.zeros((2 * CH, CH, 1, 1), dtype=np.float32)
    for c in range(CH):
        w[c, c, 0, 0] = 1.0
        w[c + CH, c, 0, 0] = 1.0
    return w


FOLD = fold_weight()
UNFOLD = unfold_weight()


def pool_down(x, frames, side):
    """One octave down: temporal 1x1 conv, then spatial avg_pool (TA1)."""
    folded = mb.reshape(x=x, shape=[frames // 2, 2 * CH, side, side])
    timed = mb.conv(x=folded, weight=FOLD, strides=[1, 1], pad_type="valid")
    return mb.avg_pool(x=timed, kernel_sizes=[2, 2], strides=[2, 2],
                       pad_type="valid")


def parent_of(coarse, frames, side):
    """Nearest upsample x2 in all three axes: the child's parent (CT4)."""
    spread = mb.conv(x=coarse, weight=UNFOLD, strides=[1, 1],
                     pad_type="valid")
    timed = mb.reshape(x=spread, shape=[frames * 2, CH, side, side])
    return mb.upsample_nearest_neighbor(x=timed, scale_factor_height=2,
                                        scale_factor_width=2)


@mb.program(input_specs=[mb.TensorSpec(shape=(F64, CH, S64, S64))])
def tensor_encode(cube):
    # ── the ladder: two applications of the same two operators ──
    l32 = pool_down(cube, F64, S64)                 # [32, 3, 32, 32]
    l16 = pool_down(l32, F32, S32)                  # [16, 3, 16, 16]

    # ── the residuals, one per fine rung ──
    p64 = parent_of(l32, F32, S32)                  # [64, 3, 64, 64]
    r64 = mb.sub(x=cube, y=p64)
    p32 = parent_of(l16, F16, S16)                  # [32, 3, 32, 32]
    r32 = mb.sub(x=l32, y=p32)

    # ── the stored decision (CT4): one sign bit per child ──
    zero = np.float32(0.0)
    sign64 = mb.cast(x=mb.greater_equal(x=r64, y=zero), dtype="fp32")
    sign32 = mb.cast(x=mb.greater_equal(x=r32, y=zero), dtype="fp32")

    # ── the step sizes, which are ALSO what gets stored ──
    # g32 is the mean |r32| over a root's 8 children and g64 the mean
    # |r64| over its 64 descendants, both landing on the rung-16 grid.
    # They are the same two operators again -- abs, then pool -- and
    # emitting them (rather than the combined deviation) is what lets
    # the ANE be a real TWIN of the encoder: the format stores g, so a
    # graph that emitted only signs would leave the CPU to recompute
    # every magnitude it just discarded.
    g32 = pool_down(mb.abs(x=r32), F32, S32)        # mean |r32| per 16-cell
    g64 = pool_down(pool_down(mb.abs(x=r64), F64, S64), F32, S32)

    # Named explicitly: MIL does not preserve declaration order in the
    # feature dictionary, and a Swift wrapper reading outputs by
    # position would be a defect waiting for the next graph edit.
    # dev16 = (8*g32 + 64*g64)/72 is CPU arithmetic over 12288 numbers,
    # so it stays off the graph rather than duplicating a law.
    return (mb.identity(x=l16, name="l16"),
            mb.identity(x=sign32, name="sign32"),
            mb.identity(x=sign64, name="sign64"),
            mb.identity(x=g32, name="g32"),
            mb.identity(x=g64, name="g64"))


# ════════════════════════════════════════════════════════════════
# The float64 reference: the spec's arithmetic, written plainly.
# ════════════════════════════════════════════════════════════════

def ref_pool(x):
    f, c, h, w = x.shape
    t = 0.5 * (x[0::2] + x[1::2])
    return t.reshape(f // 2, c, h // 2, 2, w // 2, 2).mean(axis=(3, 5))


def ref_parent(coarse, frames, side):
    up = np.repeat(np.repeat(coarse, 2, axis=2), 2, axis=3)
    return np.repeat(up, 2, axis=0)


def reference(cube):
    l32 = ref_pool(cube)
    l16 = ref_pool(l32)
    r64 = cube - ref_parent(l32, F32, S32)
    r32 = l32 - ref_parent(l16, F16, S16)
    g32 = ref_pool(np.abs(r32))
    g64 = ref_pool(ref_pool(np.abs(r64)))
    return l16, (r32 >= 0), (r64 >= 0), g32, g64


def dev16_of(g32, g64):
    """CT7's statistic: the mean deviation over all 72 descendants."""
    return (N32 / NSUB) * g32 + (N64 / NSUB) * g64


# ════════════════════════════════════════════════════════════════
# The gate
# ════════════════════════════════════════════════════════════════

def derived_threshold(dev16):
    """CT7: the significance threshold is DERIVED, never chosen -- the
    crossover of a two-phase tied-variance mixture fitted to the
    capture's OWN subtree deviations, the same mechanism DepthMixture
    uses for the figure/ground split. A capture with no quiet phase
    has no crossover, and CT7 says it pays flat; that verdict is a
    branch of the law (a prior), not a downgrade."""
    z = np.log(np.maximum(dev16.ravel(), 1e-12))
    lo, hi = np.quantile(z, 0.25), np.quantile(z, 0.75)
    mu, var, w = np.array([lo, hi]), z.var(), 0.5
    for _ in range(200):
        d = np.exp(-0.5 * (z[:, None] - mu) ** 2 / var) * np.array([w, 1 - w])
        p = d / np.maximum(d.sum(axis=1, keepdims=True), 1e-300)
        n = p.sum(axis=0)
        if n.min() < 1:
            break
        mu = (p * z[:, None]).sum(axis=0) / n
        var = max((p * (z[:, None] - mu) ** 2).sum() / len(z), 1e-12)
        w = n[0] / len(z)
    # BIC: is two phases worth four parameters over two?
    ll2 = np.log(np.maximum(
        (np.exp(-0.5 * (z[:, None] - mu) ** 2 / var)
         / np.sqrt(2 * np.pi * var) * np.array([w, 1 - w])).sum(axis=1),
        1e-300)).sum()
    v1 = z.var()
    ll1 = (-0.5 * ((z - z.mean()) ** 2 / v1 + np.log(2 * np.pi * v1))).sum()
    if 2 * (ll2 - ll1) < 3 * np.log(len(z)) or abs(mu[1] - mu[0]) < 1e-9:
        return None, "single phase: no quiet population, flat is the law"
    # Tied variance ⇒ the crossover is the log-odds-weighted midpoint.
    cross = 0.5 * (mu[0] + mu[1]) + var * np.log((1 - w) / w) / (mu[1] - mu[0])
    return float(np.exp(cross)), "two phases"


def report_bytes(label, dev16, thr, verdict):
    roots = dev16.size                       # 4096 cells x 3 channels
    if thr is None:
        loud = 1.0
    else:
        loud = float(np.mean(dev16 >= thr))
    coarse = 4096 * CH * 2                   # rung 16, fp16 (TA5)
    sig = roots // 8                         # one significance bit each
    signs = int(np.ceil(loud * roots * 72 / 8))
    total = coarse + sig + signs
    flat = F64 * S64 * S64 * CH              # 8-bit voxel colour today
    print(f"  {label}")
    print(f"    verdict           {verdict}")
    print(f"    loud subtrees     {100 * loud:.1f}%")
    print(f"    colour bytes      {total} "
          f"(coarse {coarse} + sig {sig} + signs {signs})")
    print(f"    vs 8-bit voxels   {flat} B, ratio {flat / total:.1f} : 1")


def synthetic_cube(seed=20260814, noise=0.0015):
    """A cube with the structure the zerotree exists to exploit: a
    moving figure over a quiet ground, per NO-CAPTURE-TRAINING (the
    corpus is synthetic statistical variance, never a photograph)."""
    rng = np.random.default_rng(seed)
    t = np.arange(F64)[:, None, None, None]
    y = np.arange(S64)[None, None, :, None]
    x = np.arange(S64)[None, None, None, :]
    ground = 0.42 + 0.02 * np.sin(0.09 * x + 0.05 * y)
    cx = 32 + 12 * np.sin(2 * np.pi * t / F64)
    cy = 32 + 8 * np.cos(2 * np.pi * t / F64)
    figure = np.exp(-(((x - cx) ** 2 + (y - cy) ** 2) / 90.0))
    chan = np.array([1.0, 0.35, -0.2]).reshape(1, CH, 1, 1)
    cube = ground + chan * figure * 0.45
    if noise > 0:
        cube += rng.normal(0, noise, size=(F64, CH, S64, S64))
    return np.clip(cube, 0, 1).astype(np.float32)


def main():
    print(f"building: {F64} frames x {CH} ch x {S64}^2 -> rungs 64/32/16")
    t0 = time.time()
    model = ct.convert(
        tensor_encode,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        compute_units=ct.ComputeUnit.ALL,
        minimum_deployment_target=ct.target.iOS17,
    )
    model.save("TensorEncode.mlpackage")
    print(f"converted + saved in {time.time() - t0:.1f}s")

    cube = synthetic_cube()
    ref_l16, ref_s32, ref_s64, ref_g32, ref_g64 = reference(cube.astype(np.float64))

    out = model.predict({"cube": cube})
    print("outputs:", sorted(out.keys()))
    g_l16, g_s32 = out["l16"], out["sign32"]
    g_s64, g_g32, g_g64 = out["sign64"], out["g32"], out["g64"]

    def agree(a, b):
        return 100.0 * np.mean((a > 0.5) == b)

    print("")
    print("  ── THE GATE ──")
    print(f"  l16   max abs err   {np.abs(g_l16 - ref_l16).max():.3e}"
          f"   (fp16 ulp at 0.5 is {2**-11:.3e})")
    print(f"  sign64 agreement    {agree(g_s64, ref_s64):.4f}%")
    print(f"  sign32 agreement    {agree(g_s32, ref_s32):.4f}%")
    print(f"  g32   max abs err   {np.abs(g_g32 - ref_g32).max():.3e}")
    print(f"  g64   max abs err   {np.abs(g_g64 - ref_g64).max():.3e}")

    # TA3: every disagreement must be a residual the engine could not
    # see. Report the WORST one, which is the number the law bounds.
    dis = (g_s64 > 0.5) != ref_s64
    if dis.any():
        r64 = (cube.astype(np.float64)
               - ref_parent(ref_pool(cube.astype(np.float64)), F32, S32))
        print(f"  worst disagreeing |r64|  {np.abs(r64[dis]).max():.3e}"
              f"   ({dis.sum()} of {dis.size})")
    else:
        print("  sign64: no disagreements at all")

    print("")
    print("  ── THE COMPRESSION (CT7's DERIVED threshold) ──")
    for label, c in [("figure over ground, sensor noise", cube),
                     ("the same cube, noiseless", synthetic_cube(noise=0.0))]:
        _, _, _, a, b = reference(c.astype(np.float64))
        d16 = dev16_of(a, b)
        thr, verdict = derived_threshold(d16)
        report_bytes(label, d16, thr, verdict)

    t0 = time.time()
    n = 10
    for _ in range(n):
        model.predict({"cube": cube})
    print(f"  dispatch            {1000 * (time.time() - t0) / n:.1f} ms "
          f"(Mac; A19 figure owed on device)")


if __name__ == "__main__":
    main()
