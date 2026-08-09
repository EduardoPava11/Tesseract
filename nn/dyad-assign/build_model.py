#!/usr/bin/env python3
"""DyadAssign: the DYAD-256 pixel-assignment stage as ONE fused ANE graph.

One dispatch per capture (spec/output/ExportMethods.hs, XP1-XP2):

    rgb       [64, 4096, 3]  sRGB floats in [0,1]
    primaries [64, 128, 3]   per-frame OKLab tables (CPU-solved, law-bearing)
    mask      [64, 4096]     1 = face, 0 = background (thresholded on CPU)
      |
    in-graph: sRGB -> linear -> OKLab   (matmul + cbrt, fixed)
    scores  = -2 * P . C^T + ||C||^2    (batched matmul: argmin needs no ||P||^2)
    indices = select(mask, argmin(scores), 255)
      |
    indices   [64, 4096] int32

Fixed shapes, fixed iteration count (none), fp16 compute: the widest-win
ANE pattern (arXiv:2606.22283 — dispatch floor amortized over the whole
capture). The role law (background = 255) is a select INSIDE the graph,
so it is exact on every engine; fp16 can only flip near-tie argmins,
which are lawful either way (XP2).

Builds DyadAssign.mlpackage into ../../Tesseract/ML/ (bundled by Xcode),
then verifies against the float64 NumPy reference: assignment agreement
plus the near-tie bound on every disagreement.
"""

import numpy as np
import coremltools as ct
from coremltools.converters.mil import Builder as mb

F, P, K = 64, 4096, 128
OUT_DIR = "../../Tesseract/ML"

# Björn Ottosson's OKLab matrices (same constants as DyadPalette.hs/.swift)
M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
               [0.2119034982, 0.6806995451, 0.1073969566],
               [0.0883024619, 0.2817188376, 0.6299787005]], dtype=np.float32)
M2 = np.array([[0.2104542553,  0.7936177850, -0.0040720468],
               [1.9779984951, -2.4285922050,  0.4505937099],
               [0.0259040371,  0.7827717662, -0.8086757660]], dtype=np.float32)


# Inputs are CENTERED OKLab coordinates (pixel lab − the frame's
# CENTROID = primaries[0]), PRE-PULLED on the CPU for the background
# bleed. Centering rationale, both fp16 conditioning (measured):
# (1) uncentered scores carry a ~0.25 common-mode term while winning
# gaps are ~1e-3 → 81% agreement; (2) converting sRGB→OKLab in-graph
# rounds pixel positions at |lab| ≈ 0.67 (quantum ~5e-4) → 97.4%.
# Centered inputs at |lab_c| ≈ 0.13 round at ~6e-5. Centering is
# argmin-invariant, and the CPU already pays the (linear) conversion —
# the engine keeps the quadratic P·K search. Centering on the CENTROID
# (not the primaries' mean) makes the bleed pull a pure per-pixel gain
# on lab_c, applied CPU-side before the feed.
#
# Role law v2 (harsh bleed, DyadPalette.hs §6): face → argmin;
# background → σ-mirror 255 − argmin; FULLY pulled background → 255
# by exact select (`far`), engine-independent.
@mb.program(input_specs=[mb.TensorSpec(shape=(F, P, 3)),
                         mb.TensorSpec(shape=(F, K, 3)),
                         mb.TensorSpec(shape=(F, P)),
                         mb.TensorSpec(shape=(F, P))])
def dyad_assign(lab_c, prim_c, mask, far):
    # scores = -2 P.C^T + ||C||^2  (||P||^2 constant per pixel: argmin-free)
    ct_t = mb.transpose(x=prim_c, perm=[0, 2, 1])         # [F, 3, K]
    dots = mb.matmul(x=lab_c, y=ct_t)                     # [F, P, K]
    c2 = mb.reduce_sum(x=mb.mul(x=prim_c, y=prim_c),
                       axes=[2], keep_dims=False)         # [F, K]
    c2e = mb.expand_dims(x=c2, axes=[1])                  # [F, 1, K]
    scores = mb.add(x=mb.mul(x=dots, y=np.float32(-2.0)), y=c2e)

    idx = mb.reduce_argmin(x=scores, axis=2, keep_dims=False)   # [F, P] int32
    solid = mb.cast(x=mb.fill(shape=(F, P), value=np.float32(255.0)), dtype="int32")
    mirror = mb.sub(x=solid, y=idx)                       # 255 − argmin
    is_far = mb.greater(x=far, y=np.float32(0.5))
    bg = mb.select(cond=is_far, a=solid, b=mirror)
    face = mb.greater(x=mask, y=np.float32(0.5))
    return mb.select(cond=face, a=idx, b=bg, name="indices")


# ── NumPy float64 reference (mirrors DyadPalette.swift exactly) ──────

def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def srgb_to_oklab(rgb):
    linear = srgb_to_linear(rgb.astype(np.float64))
    lms = linear @ M1.T.astype(np.float64)
    lmsc = np.cbrt(np.clip(lms, 0, None))
    return lmsc @ M2.T.astype(np.float64)


def reference(lab_c, prim_c, mask, far):
    d = ((lab_c.astype(np.float64)[:, :, None, :]
          - prim_c.astype(np.float64)[:, None, :, :]) ** 2).sum(-1)
    idx = d.argmin(-1)
    bg = np.where(far > 0.5, 255, 255 - idx)
    return np.where(mask > 0.5, idx, bg), d


TAU, BLEED_W, BLEED_G = 0.6, 0.15, 0.5


def pull(depth):
    """DyadPalette.hs §6: 0 at the silhouette, 1 beyond tau − w."""
    t = np.clip((TAU - depth) / BLEED_W, 0, 1) ** BLEED_G
    return np.where(depth >= TAU, 0.0, t)


def center_and_pull(lab, prim, depth):
    """CPU-side staging, mirrored by DyadANE.swift/DyadPipeline:
    center on the CENTROID (primaries[0]), pre-pull background pixels."""
    centroid = prim[:, :1, :]
    lab_c = lab - centroid
    prim_c = prim - centroid
    t = pull(depth)
    gain = np.where(depth > TAU, 1.0, 1.0 - t)[..., None]
    mask = (depth > TAU).astype(np.float32)
    far = ((depth <= TAU) & (t >= 1)).astype(np.float32)
    return (lab_c * gain).astype(np.float32), prim_c.astype(np.float32), mask, far


def main():
    print(f"Building DyadAssign [{F}x{P}x{K}] mlprogram, fp16 ...")
    model = ct.convert(
        dyad_assign,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.ALL,
    )

    # ── Verify against the float64 reference (XP1/XP2) ───────────────

    def dyad_shell_primaries(rng):
        """Realistic tables: the solver's polar binomial shells around a
        per-frame drifting skin centroid (ladder 1,1,2,4,8,16,32,64)."""
        ladder = [1, 1, 2, 4, 8, 16, 32, 64]
        prim = np.zeros((F, K, 3), dtype=np.float32)
        base = srgb_to_oklab(np.array([[[0.66, 0.53, 0.42]]]))[0, 0]
        for f in range(F):
            c = base + rng.normal(0, 0.01, 3)
            g1, g2 = 0.06, 0.02                     # PC stds, L-dominant
            i = 0
            for k, n in enumerate(ladder):
                r = 2.0 * k / 7.0
                for j in range(n):
                    th = 2 * np.pi * j / n
                    prim[f, i] = c + [r * np.cos(th) * g1,
                                      r * np.sin(th) * g2 * 0.6,
                                      r * np.sin(th) * g2]
                    i += 1
        return prim

    def check(tag, rgb, prim, depth, min_agree):
        lab_c, prim_c, mask, far = center_and_pull(
            srgb_to_oklab(rgb), prim.astype(np.float64), depth)
        spec_names = [inp.name for inp in model.get_spec().description.input]
        got = model.predict(dict(zip(spec_names, [lab_c, prim_c, mask, far])))["indices"].astype(np.int64)
        want, d = reference(lab_c, prim_c, mask, far)

        farBg = (mask <= 0.5) & (far > 0.5)
        band = (mask <= 0.5) & (far <= 0.5)
        assert (got[farBg] == 255).all(), f"{tag}: far background must be 255 (XP1)"
        assert ((got[band] >= 128) & (got[band] <= 255)).all(), \
            f"{tag}: bleed band must stay in the complement half (XP1)"

        # Assigned pixels (face + bleed band) go through the argmin.
        face = mask > 0.5
        assigned = face | band
        agree = (got[assigned] == want[assigned]).mean()
        dis = assigned & (got != want)
        if dis.any():
            ds = np.sort(d[dis], axis=-1)
            max_gap = (ds[:, 1] - ds[:, 0]).max()
            # Compare choices in PRIMARY index space (σ-mirror band
            # indices map back through 255 − i).
            fi, pi = np.nonzero(dis)
            gotP = np.where(got[dis] >= 128, 255 - got[dis], got[dis])
            wantP = np.where(want[dis] >= 128, 255 - want[dis], want[dis])
            de = np.linalg.norm(prim[fi, gotP] - prim[fi, wantP], axis=-1)
            de_max = de.max()
        else:
            max_gap, de_max = 0.0, 0.0
        print(f"[{tag}] agreement {agree * 100:.3f}%  "
              f"disagreements {int(dis.sum())}  max gap {max_gap:.2e}  "
              f"max dE(choice) {de_max:.4f}")
        assert max_gap <= 2e-3, f"{tag}: gap {max_gap} is not a near-tie (XP2)"
        assert agree >= min_agree, f"{tag}: agreement {agree} below {min_agree}"

    rng = np.random.default_rng(1)
    rgb = np.clip(rng.normal([0.66, 0.53, 0.42], 0.10, (F, P, 3)), 0, 1).astype(np.float32)
    # Depth field: near face (0.6..1), a bleed band, and far background —
    # exercises face, σ-mirror band, and exact far-solid paths.
    depth = rng.random((F, P)).astype(np.float32)

    # Realistic DYAD shells: the law AND high agreement must hold.
    # Measured floor (CPU-centered inputs): 98.76% agreement with max
    # disagreement gap 2.6e-5 — every flip is a pixel ~6e-4 ΔE from a
    # Voronoi boundary, where the fp64 reference itself is unstable.
    check("shells", rgb, dyad_shell_primaries(rng), depth, min_agree=0.985)
    # Dense-random stress: near-tie law must hold; agreement reported.
    prim_stress = (srgb_to_oklab(np.array([[[0.66, 0.53, 0.42]]]))[0, 0]
                   + rng.normal(0, 0.05, (F, K, 3))).astype(np.float32)
    check("stress", rgb, prim_stress, depth, min_agree=0.95)

    import os
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, "DyadAssign.mlpackage")
    model.save(out)
    print(f"saved {out}")
    print("VERIFIED: role law exact, near-tie law holds (XP1/XP2)")


if __name__ == "__main__":
    main()
