#!/usr/bin/env python3
"""EVIDENCE FOR A RULING: what a sensor noise floor does to CT7.

Not a gate and not a law. This script measures one thing and reports
it, because the build_model.py gate turned up a result that
contradicts the 95.3%-quiet figure CaptureTensor's zerotree section
was ruled on:

  a cube with a figure over a quiet ground and NO sensor noise
      -> the mixture finds two phases, 24.9% loud
  the SAME cube with a 0.0015 noise floor
      -> the mixture finds ONE phase, so CT7's own branch says pay
         flat, and the encoder stores 110592 B of noise signs

CT7 is not wrong. It asks "are there two populations of deviation
magnitude", and under a noise floor there genuinely are not. But the
question that decides whether a sign is worth a bit is a different
one: "is this subtree louder than noise alone would make it". This
script measures whether answering THAT question instead would cost
any reconstruction quality.

The candidate criterion is Donoho & Johnstone (1994), which is
derived rather than chosen exactly the way the mixture crossover is:
the noise scale is the median absolute deviation of the finest
band divided by 0.6745 (the MAD-to-sigma constant for a Gaussian,
an identity, not a tuning), and the threshold is
sigma * sqrt(2 ln N) for N coefficients.

RUN:  python3 noise_floor.py
"""

import numpy as np

from build_model import (F64, S64, CH, N32, N64, NSUB,
                         ref_pool, ref_parent, reference,
                         synthetic_cube, derived_threshold)

F32, S32, F16, S16 = 32, 32, 16, 16


def residuals(cube):
    l32 = ref_pool(cube)
    l16 = ref_pool(l32)
    r64 = cube - ref_parent(l32, F32, S32)
    r32 = l32 - ref_parent(l16, F16, S16)
    return l16, l32, r32, r64


def reconstruct(cube, keep16):
    """Decode under CT4/CT9: child = parent + sign*g, and a quiet
    subtree is g = 0, which is the SAME law, not a second path.
    g here is the subtree's own deviation, the natural estimator and
    exactly what the ANE graph already emits."""
    l16, l32, r32, r64 = residuals(cube)
    keep = np.repeat(np.repeat(np.repeat(keep16, 2, axis=0), 2, axis=2), 2, axis=3)

    g32 = np.repeat(np.repeat(np.repeat(
        ref_pool(np.abs(r32)), 2, axis=0), 2, axis=2), 2, axis=3)
    rec32 = ref_parent(l16, F16, S16) + np.sign(r32 + 1e-30) * g32 * keep

    keep64 = np.repeat(np.repeat(np.repeat(keep, 2, axis=0), 2, axis=2), 2, axis=3)
    g64 = np.repeat(np.repeat(np.repeat(
        ref_pool(np.abs(r64)), 2, axis=0), 2, axis=2), 2, axis=3)
    rec64 = ref_parent(rec32, F32, S32) + np.sign(r64 + 1e-30) * g64 * keep64
    return rec64


def donoho(dev16, r64):
    """sigma from the finest band's MAD; threshold sigma*sqrt(2 ln N)."""
    sigma = np.median(np.abs(r64)) / 0.6745
    return sigma * np.sqrt(2 * np.log(r64.size)) / np.sqrt(NSUB), sigma


def bits(loud):
    return int(np.ceil(loud * 4096 * CH * 72 / 8)) + 4096 * CH // 8 + 4096 * CH * 2


def row(name, cube, keep16, loud):
    rec = reconstruct(cube, keep16)
    rmse = float(np.sqrt(np.mean((rec - cube) ** 2)))
    print(f"  {name:<34} {100*loud:5.1f}%   {bits(loud):8d} B   {rmse:.5f}")


def main():
    print("  criterion                           loud     colour     rmse")
    print("  " + "-" * 62)
    for label, noise in [("noiseless", 0.0), ("sensor noise 0.0015", 0.0015)]:
        cube = synthetic_cube(noise=noise).astype(np.float64)
        _, _, r32, r64 = residuals(cube)
        dev16 = reference(cube)[3]
        print(f"\n  === {label} ===")

        ones = np.ones_like(dev16)
        row("flat: every subtree pays", cube, ones, 1.0)

        thr, verdict = derived_threshold(dev16)
        if thr is None:
            print(f"  {'CT7 mixture: ' + verdict:<34}  -> flat")
        else:
            keep = (dev16 >= thr).astype(float)
            row("CT7 mixture crossover", cube, keep, float(keep.mean()))

        t, sigma = donoho(dev16, r64)
        keep = (dev16 >= t).astype(float)
        row(f"Donoho MAD (sigma {sigma:.5f})", cube, keep, float(keep.mean()))

    print("""
  READ THIS BEFORE ACTING ON IT. The mixture and the MAD threshold
  answer different questions and BOTH are derived. The ruling Daniel
  owns is which question the significance bit is asking:

    mixture   are there two populations of subtree deviation?
    MAD       is this subtree louder than sensor noise alone?

  Neither is a tuning knob and neither introduces a constant. CT7
  currently says the first. This measurement is the case for the
  second under a real noise floor, and nothing has been changed.""")


if __name__ == "__main__":
    main()
