# CENTERS — the cell-center reconstruction, from first principles to SIMT

*Companion to `spec/quantization/Centers.hs` (axioms CN1–CN6, verified in
exact rational arithmetic). This document is the derivation and the
computational consequences; the spec file is the proof harness.*

---

## 1. The object

Each color channel is quantized by the pair

```
E : [0,1) → Z₄        E(x) = min(3, ⌊4x⌋)          (encoder)
D : Z₄ → [0,1)        D(k) = (k + ½)/4              (decoder)
```

so the reconstruction points are `{1/8, 3/8, 5/8, 7/8}`, i.e. sRGB bytes
`{32, 96, 159, 223}` after `round(·×255)` (the odd-looking 159 is exact:
`5/8 × 255 = 159.375`). Swift: `TesseractCoord.sRGB`, `TessLevel.center`
/ `.byte` in `Model/Axes.swift`. Metal: `Quantize.metal`. Haskell:
`spec/algebra/Tesseract.hs § 7`.

The full palette is the integer lattice

```
𝕋 = Z₄⁴ ∋ (d, a, b, c)     |𝕋| = 4⁴ = 256
```

with the temporal epoch `d` as a fourth, *non-metric* axis (§ 6).

## 2. Why centers: the Lloyd–Max argument

A scalar quantizer is a partition `{S_k}` of the domain plus a
reconstruction point `r_k` per cell. For a density `p`, the mean squared
error is

```
MSE = Σ_k ∫_{S_k} (x − r_k)² p(x) dx
```

Optimal quantizers satisfy two *necessary conditions* (Lloyd 1957,
Max 1960):

1. **Nearest-neighbor partition** — each `x` maps to the nearest `r_k`
   (the partition is the Voronoi diagram of the reconstruction set);
2. **Centroid reconstruction** — each `r_k` is the conditional mean
   (centroid) of its cell.

For the floor partition `S_k = [k/4, (k+1)/4)` under uniform density,
the centroid of `S_k` is its **midpoint** `(k+½)/4`. That settles
condition 2. Condition 6 of the spec (CN6) closes the loop: the Voronoi
boundaries of the center set are the midpoints of adjacent centers,

```
((k+½)/4 + (k+1+½)/4) / 2 = (k+1)/4
```

— which are *exactly the floor boundaries*. So with centers, floor
encoding **is** nearest-neighbor encoding: both Lloyd–Max conditions
hold simultaneously and the quantizer is a fixed point of Lloyd
iteration. No other reconstruction set has this property for the floor
partition.

**The rejected endpoint scheme** `D'(k) = k/3` (Tesseract64's
`nibbleToFloat`, bytes `{0, 85, 170, 255}`) fails both discriminating
conditions. Note carefully what it does *not* fail: the section law
`E ∘ D' = id` holds for endpoints too (`⌊4k/3⌋ = k` for `k ≤ 2`, clamp
at 3). The failures are geometric:

- **Centroid (CN4):** by the parallel-axis theorem,
  `∫_cell (x−r)² dx = ∫_cell (x−mid)² dx + Δ·(r−mid)²`, so any `r ≠ mid`
  pays a strictly positive penalty. Per cell the excess is
  `Δ(r−mid)² ∈ {1/256, 1/2304, 1/2304, 1/256}` — the outer cells pay 9×
  more, which is why endpoint reconstruction visibly crushes shadows and
  blows highlights.
- **Voronoi (CN6):** the Voronoi cells of `{0, 1/3, 2/3, 1}` have widths
  `{1/6, 1/3, 1/3, 1/6}` — a *different partition* than floor. Any
  consumer doing nearest-neighbor against endpoint colors silently
  disagrees with the floor encoder about 1/6 of the domain. This
  inconsistency class is precisely what `spec/statistics/BinomialFix.hs`
  documents.

## 3. Exact error accounting

With centers, the per-cell integral is the second central moment of a
uniform interval:

```
∫_{cell} (x − mid)² dx = Δ³/12 = (1/4)³/12 = 1/768        (per cell)
Σ_k                    = 4 · Δ³/12 = Δ²/12 = 1/192         (per axis)
E‖x − D(E(x))‖²        = 3 · Δ²/12 = 1/64                  (RGB cube)
```

All three are verified as exact `Rational` identities (CN4, CN5) — no
epsilon, no floating point. The classical form `Δ²/12` is the uniform
quantization-noise variance; at b = 2 bits/channel this is the familiar
`SNR ≈ 6.02·b dB` regime. The additivity across axes (`3·` above) is
not an approximation: the error random variables of independent axes
are orthogonal in `L²`, so squared norms add — the same parallel-axis
orthogonality used per cell, applied across the tensor factors.

**Dither interacts with centers, not against them.** The app's spatial
dither (`PerfectQuantizer`, from `PerfectQuantize.hs`) perturbs *which
cell* a pixel lands in so that cell *occupancy* matches the bell target;
within-cell reconstruction stays at the centroid. Occupancy shaping and
reconstruction optimality are orthogonal decisions — conflating them is
how the endpoint scheme was born (stretching reconstruction to reach
pure black/white, a job the bell's two anchor strata already do:
`BellPalette.hs` BP5).

## 4. Tensor formulation

Write a captured cube as `X ∈ [0,1)^{S×S×3}` (S = 64) with a depth
field `Z ∈ [0,1]^{S×S}` and frame index `t ∈ {0..63}`.

**Encode** is an elementwise tensor map followed by a contraction:

```
K   = min(3, ⌊4X⌋)                    K ∈ Z₄^{S×S×3}      (color nibbles)
d   ~ Cat(softmax-free Gaussian pmf)  d ∈ Z₄^{S×S}        (epoch, § 6)
idx = ⟨(d,K), w⟩,  w = (64,16,4,1)    idx ∈ Z₂₅₆^{S×S}    (palette index)
```

The stride vector `w` is the mixed-radix (base-4) positional weighting;
`⟨·,·⟩` is a contraction over the last axis. Equivalently, with one-hot
encodings `1_d ∈ {0,1}⁴` etc., the index one-hot is the Kronecker
product `1_d ⊗ 1_a ⊗ 1_b ⊗ 1_c ∈ {0,1}²⁵⁶` — the palette is literally
the tensor product of four 4-level axes, which is the precise sense in
which "the palette is a tesseract."

**Decode** is a gather plus an affine map:

```
X̂ = (K + ½) · Δ         (elementwise; Δ = 1/4)
or  X̂ = P[idx]           (gather against P ∈ R^{256×3}, P[i] = center colors)
```

Both encode and decode are *branch-free, elementwise, fused-multiply-add
shaped* — the whole quantizer is `fma → floor → clamp → contraction`,
which is why it vectorizes perfectly in both SIMD and SIMT senses below.
The GIF file then stores `idx` (the contraction result) and `P` (the
gather table): a GIF is a serialized tensor factorization — indices ⊗
palette.

## 5. SIMD — the CPU lanes

The Swift port keeps the 4-fold structure in registers:

- `BinomialCadence.centers` is `SIMD4<Float>` — the four epoch centers
  `(2d+1)·σ_base` are an affine map of the iota vector `(1,3,5,7)`,
  computed once and broadcast (`BinomialCadence.swift`).
- `epochProbabilities` evaluates four Gaussians in one `SIMD4` lane
  group: subtract-center, square, scale, `exp`, then a horizontal sum
  for normalization — one lane per epoch, no loop.
- The color encode `min(3, Int(x·4))` compiles to vectorizable
  `fmul + cvt + min` with **no branches**; the clamp is a saturating
  min, not an `if`. This is the CN2/CN3 geometry paying rent: because
  cells are equal-width and half-open, the encoder needs no per-cell
  boundary table — multiply and floor *is* the binary search.
- `TesseractCoord` packs `(d,a,b,c)` in four `UInt8`s; index/inverse are
  shift-add (`&*`/`quotientAndRemainder` on powers of 4 — strength-
  reduced to shifts), keeping the bijection (Block.hs C8) allocation-free.

SIMD-width note: the natural vector here is width 4 (the axes), not the
hardware width (NEON 128-bit = 4×Float32 exactly). The 4-level, 4-axis
design means one hardware vector *is* one semantic unit — nothing is
wasted, nothing is split.

## 6. SIMT — the GPU grid

The Metal path (`MetalPipeline` + `Quantize.metal`) maps one thread per
output pixel over an `S×S` grid — the SIMT regime, where the unit of
efficiency is the *warp/simdgroup* executing in lockstep:

- **Zero divergence in the hot path.** Floor-encode, clamp, index
  contraction, and center reconstruction contain no data-dependent
  branches, so all lanes of a simdgroup retire together. The only
  data-dependent operation is the epoch draw, and it is branch-free
  too: sample `u ~ U[0,1)`, then `d = Σᵢ [u > cdfᵢ]` — three compares
  and adds against the `SIMD4` CDF, uniform across the warp.
- **The palette is warp-cheap.** `P` is 256×3 bytes = 768 B — it fits
  in constant/threadgroup memory with room to spare; a gather against
  it never leaves the fast path. (This is a luxury of `4⁴ = 256`: the
  entire codebook costs less than one cache line per axis level.)
- **Coalescing:** threads are laid out row-major over the S×S grid, so
  texture reads/writes are contiguous per simdgroup; the downsample
  kernels reduce `768/S`-pixel blocks with uniform strides
  (`CameraConfig.rgbStep`).
- **Depth contract:** the kernel consumes depth already normalized to
  `[0,1], 1 = near` — σ(depth) = σ_base·(2−depth) is then a single fma
  per pixel. (The audit's #1 bug is exactly a violation of this
  contract on the GPU readback path: raw meters in, NaN probabilities
  out at 2.0 m. The contract, not the kernel, is the invariant.)
- **Idempotence under re-quantization:** because `E(D(k)) = k` (CN2)
  and nearest-center = floor (CN6), re-running the quantizer over its
  own output is the identity — preview, re-process, and export cannot
  drift, no matter how many GPU passes compose. With endpoints, CN6's
  failure means a nearest-neighbor pass over reconstructed colors would
  *re-bin* 1/6 of the domain per pass.

## 7. The epoch axis is different, on purpose

The three color axes are *metric* (MSE governs, centroids win). The
epoch axis is *categorical*: `d` is not rounded from a continuous
epoch value; it is **sampled** from a depth-conditioned Gaussian pmf
over `{0,1,2,3}` (`BinomialCadence`, `ContinuousDepthCadence.hs`).
There is no "epoch centroid" because there is no epoch metric — the
correct object is the probability simplex Δ³, and the design targets
the *distribution* of epochs (temporal dither), not a per-pixel
minimum-distortion epoch. This is why `R¹ ⊕ R³ = R⁴` in the algebra
splits cleanly: the direct sum separates the axis where expectation
matters (time → cadence) from the axes where variance matters
(color → centers). Only the R³ factor carries the Lloyd–Max structure;
CN1–CN6 are theorems about that factor.

## 8. Where each fact lives

| Fact | Proof | Production |
|---|---|---|
| centers `{1/8,3/8,5/8,7/8}`, bytes `{32,96,159,223}` | CN1 | `Axes.swift` `TessLevel.byte`, `TesseractCoord.sRGB8` |
| `E∘D = id` | CN2 | preview/export stability |
| equal cells, volume `1/256` | CN3 | `TesseractCoord.cellVolume` |
| centroid + parallel axis, endpoint penalty | CN4 | (design rationale; `BinomialFix.hs`) |
| total distortion `1/64` exact | CN5 | error budget |
| Voronoi(centers) = floor partition | CN6 | branch-free encoder; idempotent pipeline |
| index bijection over `Z₄⁴` | Block.hs C8 | `TesseractCoord.init(index:)` |
| epoch pmf sums to 1 at all K | LevelTests / C9 | `BinomialCadence.epochProbabilities` |

*Everything in the Proof column runs under `make test` in `spec/` and
fails the suite loudly (truthful harness, 2026-08-03). Everything in
the Production column is compiled Swift/Metal.*
