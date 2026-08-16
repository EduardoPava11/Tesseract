# WHERE THE COMPUTATION HAPPENS, BY COLOUR TIER

Daniel, 2026-08-16: "map out WHERE we do the computation so that they
maximize signal", and "I want performance but not at the cost of
quality."

The organising rule, from the brief: a colour space buys ONE property
and gives up another, and the tier you compute in must match the
operation you want to be correct.

    Tier 1/2 LINEAR    light adds. Every LIGHT-INTEGRATING operator
                       belongs here: downsample, blur, box filter,
                       octave pool, Haar lifting, resampling.
    Tier 4   OKLab     Euclidean distance means something. Every
                       PERCEPTUAL operator belongs here: palette
                       centroids, nearest-entry assignment, the
                       gamma-staging contraction, colour statistics.

★ THE TEST THAT SEPARATES THEM: does the operator model LIGHT ARRIVING
somewhere (a sensor cell, a display pixel, a pooled block), or does it
model a JUDGEMENT about colour (which of these is nearer, where is the
centre of this cluster)? Light integrates linearly. Judgement does not.

## The audit

Every linear operator in the pipeline, and the tier it actually runs in.

| operator | file | operates on | verdict |
|:--|:--|:--|:--|
| `downsampleRGB` | Quantize.metal | bgra8Unorm, POINT SAMPLED | no averaging at all (see below) |
| `stageAerial` | DyadPipeline.swift:~185 | OKLab | CORRECT, it is a perceptual contraction |
| `chaosPool` | DyadPipeline.swift:704 | OKLab | ★ WRONG TIER, measured below |
| aerial chaos blur | Quantize.metal:~150 | OKLab | ★ WRONG TIER, same law, same error |
| `PairTree` node means | PairTree.swift | OKLab | CORRECT, codebook centroids are a judgement |
| `DyadPalette.analyze` | DyadPalette.swift:473 | sRGB8 to OKLab | CORRECT, perceptual statistics |
| `TriScaleLadder` pool | TriScaleLadder.swift | exact UInt64 LATTICE SUMS | not colour, no tier question |
| `CaptureTensor.poolDown` | CaptureTensor.swift:114 | UNDECLARED Float | ★ OPEN, decide before the swap |

## ★ The measured error: chaosPool averages in OKLab

`chaosPool` sums `lab.l`, `lab.a`, `lab.b` over a 4x4 block and divides
by 16. That is a spatial mean, a light-integrating operation, computed
on Tier-4 coordinates. The cube root does not commute with averaging,
so the result is not the colour of the averaged light.

Measured, OKLab-averaging against linear-light averaging:

    block                        dL        dC       |dOKLab|
    high-contrast edge        -0.2199    0.0088     0.2201
    skin over dark ground     -0.1222    0.0257     0.1248
    saturated blue / yellow   -0.0744    0.0701     0.1022
    smooth mid-grey ramp      -0.0012    0.0000     0.0012
    4000 random blocks                   median     0.0386
                                         p95        0.0598

★ FOR SCALE: the palette's own median nearest-neighbour spacing is
0.0093 OKLab (measured during the DY17 work). So the MEDIAN error is
about 4x the palette's resolution and a high-contrast edge is about
24x. The pooled target lands several palette entries away from where
the light actually is.

★ AND THE ERROR HAS A SIGN. The cube root is concave, so by Jensen
mean(cbrt(x)) <= cbrt(mean(x)) and dL is NEGATIVE everywhere. The
chaos blur systematically DARKENS the background, worst exactly where
contrast is highest, which is the boundary between figure and ground.
It is a bias, not noise, and no amount of averaging removes it.

★ IT IS IN BOTH PORTS. Quantize.metal's aerial chaos blur does the
same thing (`sum += P.centroid.xyz + gq * (lq - P.centroid.xyz)` then
`/ 16.0`), so CPU and GPU agree with each other and both differ from
the light. AerialParityTests will stay green through this fix, which is
worth knowing: parity is not correctness.

## ★ THE FIX IS ALSO THE FASTER PATH: pool first, then stage

Today the sigma path stages every pixel and then pools:

    4096 pixels -> oklab -> stageAerial -> pool 16:1 -> 256 targets

Correct AND cheaper is to reverse it:

    4096 pixels -> pool 16:1 in LINEAR -> 256 -> oklab -> stageAerial

Two things fall out at once:

1. QUALITY. The spatial mean now happens where light adds, so the
   0.0386 median bias goes away by construction rather than by tuning.
2. PERFORMANCE. `oklab(fromSRGB8:)` is six transcendentals (three
   `pow(_, 2.4)`, three `cbrt`) and `stageAerial` follows it. Doing
   both on 256 block means instead of 4096 pixels is 16x LESS work on
   the sigma path.

★ AND IT NEEDS DEPTH POOLED FIRST, WHICH THE LAW ALREADY WANTS. The
staging exponent gamma(s) is per-pixel, so pooling before staging
requires a pooled s. TL9 already says depth's native rung IS 16: "one
reliable readback of that choice needs the 64 draws a 16-rung voxel
aggregates". So pooling depth to rung 16 before staging is not a
concession, it is the resolution the law assigns depth anyway.

## The entrance, and a trap waiting there

`downsampleRGB` is a bare `srcTexture.read(uint2(srcX, srcY))`: a POINT
SAMPLE, no filter. The funnel measured the consequence, 143 of 144
samples discarded at the steepest stratum in the pipeline, and RateLadder
step S0 queues a box prefilter to fix the aliasing.

★ WHEN S0 IS BUILT IT MUST AVERAGE IN LINEAR LIGHT. The source is
`bgra8Unorm`, which is sRGB-ENCODED. A box filter written naively over
those bytes repeats exactly the chaosPool error, at 144:1 instead of
16:1, at the widest funnel in the app. The cheap correct form is to let
the sampler do it: a `.linear` filtered read on an `srgb` pixel format
converts to linear, filters, and converts back in hardware for free.
Getting this wrong at S0 would be more expensive than every other
colour decision in the pipeline combined.

## What is already in the right tier, and why it stays

- `stageAerial` contracts about c_F in OKLab. That is a PERCEPTUAL
  operation, the aerial mirror law's chroma octave. It belongs where it
  is, and moving it to linear would break DY9/DY10.
- `PairTree`'s analytic splits take means and variances in OKLab. A
  codebook centroid is a judgement about which colours cluster, not a
  light integration, so OKLab is right. This is the same reason k-means
  for quantisation is run in a perceptual space.
- `DyadPalette.analyze` computes the 13 numbers in OKLab. Same argument.
- `TriScaleLadder` sums exact UInt64 lattice levels, which are index
  counts and not colour at all. No tier question arises.

## Open, and it should be settled before the call-site swap

`CaptureTensor.poolDown` IS the octave kappa, a 2x2x2 spacetime mean,
and it is the most linear operator in the codebase. Nothing declares
which tier its input is in: `encode(colour:depths:)` takes a `Level` of
bare `Float`, and the only callers are tests whose fixtures fill it with
undeclared 0..1 values.

Because CaptureTensor has no app call site yet (CR3 staged the swap),
this is free to decide NOW and expensive to decide later. The answer
follows the rule at the top: the octave is a light-integrating pool, so
its Level holds LINEAR values, and the declaration belongs in CT's own
axioms rather than in a comment.

## What this map does not settle

- Whether OKLab beats CIELAB for DIFFERENCE PREDICTION, which the brief
  flags as contested. Nothing here depends on it: every OKLab use above
  is a centroid or a contraction, not a delta-E claim.
- Whether the assignment argmin should use HyAB rather than L2. That is
  a real experiment and a separate one; the palette entries are 20 to 60
  delta-E apart, which is the large-difference regime HyAB was fitted
  for. It does not interact with the tier question.
- Any of this on a device. Every number above is Mac-side arithmetic on
  synthetic blocks.
