# Tesseract

An iPhone 17 Pro camera app that produces tiny animated GIFs whose entire color
system is a 4-dimensional lattice. Every GIF uses the same 4⁴ = 256-entry
palette: a point `(d, a, b, c) ∈ {0,1,2,3}⁴` where `d` is a temporal epoch and
`(a, b, c)` are quantized R, G, B levels, packed as index `i = d·64 + a·16 + b·4 + c`.
The direct sum ℝ¹ ⊕ ℝ³ = ℝ⁴ makes time a first-class color axis: 4 epochs share
each of the 64 display colors, so the palette *is* the tesseract. Output quality
is scored with Birkhoff's aesthetic measure `M = O / C`, where order `O` is
deviation from a binomial null model and complexity `C` is normalized Shannon
entropy. Everything is specified first in Haskell (axioms + QuickCheck laws +
golden vectors), then ported to Swift/Metal.

## Two capture modes

The app launches into a picker with two independent pipelines:

### 1. Live GIF (front TrueDepth camera)

Synchronized RGB + depth at 20 fps (`AVCaptureDataOutputSynchronizer`), a
universal centered crop (768² RGB, 256² depth), downsampled to the cube side.
Two cube modes obey the invariant S = K (spatial side = frame count):

| Mode | Cube | Frames/epoch | σ_base = (K−1)/8 |
|---|---|---|---|
| Training | 64×64×64 | 16 | 7.875 |
| Inference | 128×128×128 | 32 | 15.875 |

**Capture-then-compute**: all K frames are recorded raw (`CapturedFrame`),
*then* `PerfectQuantizer.quantizeGlobal` processes them together — the global
per-channel distribution matching needs every frame before any palette index is
committed. Per frame:

1. **Color dithering** — Floyd–Steinberg run independently on R, G, B
   (the axes never mix; no PCA, no joint clustering). Depth modulates the
   error-diffusion strength: near = accurate, far = diverse. Channel bins use
   14-bin histograms matched to a bell-shaped target demand.
2. **Epoch threading** — the temporal axis `d` is assigned by a Gaussian
   cadence with centers `μ_d = (2d+1)·σ_base` and per-pixel width
   `σ(depth) = σ_base·(2 − depth)`: near subjects lock crisply to their epoch,
   far background diffuses across epochs. No zones, no lookup tables — the
   formulas are ports of `spec/temporal/ContinuousDepthCadence.hs` and are
   verified by its axioms (CD1–CD8, PQ1–PQ5).
3. **Compose** — `i = d·64 + a·16 + b·4 + c`, canonical sRGB channel values
   {32, 96, 159, 223}.

A Metal compute path (`Quantize.metal`) implements the same math on GPU
(hash PRNG + CDF sampling over the four epoch probabilities) for the live
preview; the preview shows exactly what the GIF will look like.

The **GIF89a encoder is hand-rolled** (`GIFEncoder.swift`): the 768-byte global
color table is `TesseractPalette.gifColorTable` written byte-for-byte, and raw
palette indices go straight through LZW — no `CGImageDestination`, no
re-quantization, the tesseract structure survives into the file.

**Gene interaction loop.** On top of quantization sits a small, fully
transparent neural network (`GeneNN.swift`, `Gene.metal`): a 137 → 32 → 5 MLP
(4,581 params ≈ 4.5 KB as an Int8 "gene capsule") whose 5 outputs are
`(d, a, b, c)` plus a global/local palette weight `g`. The first 4,416 params
(ATTENTION) are user-trainable by swiping; the last 165 (CORE) are frozen. The
UI is a three-phase state machine — **Dual Explore → Compose → Refine** — with
two competing genes A and B, a composition order choice, and an α-blend refine
stage; MAP-Elites and a Sobol explorer drive the search. An MLX training loop
(`GeneTrainer.swift`) distills the user's final choice, but it is gated behind
`#if canImport(MLX)` and the MLX Swift package is not yet declared in
`project.yml`, so it is inert in the generated project. The teacher is always
`PerfectQuantizer`; the student NN only ever replaces the depth estimate and
feeds the same verified pipeline (`spec/neural/TeacherStudent.hs`).

**Beauty scoring.** `BirkhoffMeasure.swift` (port of
`spec/statistics/DeviationManifold.hs`): the null model is B(4096, 1/256) —
E = 16 pixels per palette entry per 64² frame. `O = √Σ(count_i − 16)²`,
`C = H/log 256`, `M = O/C`, plus a participation-ratio manifold-dimension
estimate in [0, 3]. The thesis: deviation from binomial *is* the image.

### 2. RAW burst (rear 48 MP camera)

`RAWCaptureManager` captures two Bayer ProRAW DNGs separated by a
user-configurable Δt (clamped ≥ 200 ms — the 48 MP ISP pipeline bails with
err −12710 below that). `RAWBurstPackage` assembles an AirDrop-ready folder:

```
a.dng           first full-sensor Bayer capture (e.g. 8064×6048)
b.dng           second capture
preview.jpg     embedded preview from A
manifest.json   Δt, sensor geometry, and the advisory 4096² center crop
                that the tesseract-isp Haskell spec reads from
```

The DNGs are untouched; the crop is advisory metadata. These bursts are the
input to the `isp-spec/` pipeline below.

## The Haskell specs

Haskell is authoritative; Swift and Metal are translations. There are two spec
trees.

### `spec/` — axiom scripts for the live-GIF app

Self-contained `runghc` scripts, each verifying its own axioms (`make test`).
Layers: `algebra/` (the ℝ¹⊕ℝ³ direct sum, 4⁴ lattice, 22 axioms; Hamming
distance K ~ Binomial(4, 3/4)), `quantization/` (14-bin axes, F–S/epoch split,
distribution-exact largest-remainder pass), `temporal/` (Gaussian cadence,
bidirectional error diffusion around the 64-frame loop), `spatial/` (19×19
blocks analyzed as Go positions: territory, liberties, complexity; EMD between
per-color spatial graphs), `statistics/` (the B(4096, 1/256) cube and the
deviation manifold), `neural/` (Para categorical NN vocabulary, the 3-layer
depth net, teacher–student contract), and `deprecated/` (removed ideas with
rationale — e.g. the KataGo black box).

### `isp-spec/` — `tesseract-isp`, a physics-grounded ISP (cabal package)

Two Bayer DNGs + Δt → a 4D GIF along axes **(R, G, B, T)**, where `T` is a
per-pixel *physical time* estimated from photon statistics — not a frame index.
Estimators are user-selectable: Poisson interarrival `T = t_exp/N̂` (MLE),
effective integration `T = N̂/Φ_ref`, and a Heisenberg precision floor
`σ_T = λ/(4πc√N)` derived from the energy–time bound with per-channel Bayer
wavelength anchors (R 640 nm, G 546 nm, B 427 nm). Mixed Poisson–Gaussian noise
goes through the Anscombe transform and an `Uncertain` carrier propagates σ
through every stage.

Structural pieces:

- **Scale pyramid** with the conservation law S·K = 4096 over 8 levels
  (2048²×2 frames … 64²×64 … 16²×256), `ISP.Pyramid`.
- **Pyramid-double path** (`ISP.Fingerprint`): 1024² Oklab → 7 levels down to
  16², *doubling* the palette at each step (2 → 4 → … → 64 colors) via the
  `ColorDouble` typeclass — three candidate instances (KMeans, PCA, Coproduct)
  kept open until benchmarked. The result is the **16×16×64 fingerprint**:
  a 16² index plane with a 64-color Oklab palette per frame. Oklab is the
  ruler; sRGB is the material.
- **Spine + delta global palette** (`ISP.PaletteSpine`): all 64 frames share a
  192-color spine; each 4-frame group carries its own 64-color delta fitted to
  the spine residuals — effective palette is always spine ++ delta = 256.
- **Laplacian composition** (`ISP.Compose`): the 7 pyramid planes are blended
  into one 64² Oklab frame with weights `w_k ∝ 2^(−|k−4|)` centered at the
  output level, then snapped to the effective palette (the one
  non-differentiable step; straight-through in a learned setting).
- **Binomial beauty** (`ISP.BinomialBeauty`, `ISP.BinomialEMD`): the target for
  a fingerprint's color-count histogram is the dyadic palindromic bell
  `[1,1,2,4,8,16,32,32,16,8,4,2,1,1]` (14 bins, `DyadicBell 5`), alongside
  B(4096, 1/256) and B(256, 1/64) nulls. Distance is 1-D Wasserstein
  (EMD = Σ|ΔCDF|, chosen over KL because empty outer bins make KL explode),
  giving the Order score `O = 1 − EMD/EMD_max` used in `M = O/C`.
  A MAP-Elites variant (`ISP.MapElitesBinomial`) searches over these
  descriptors.

Fourteen `ISP.Laws.*` QuickCheck modules cover the core stages (physics, noise,
uncertainty, Bayer, tesseract, pyramid, palette, pipeline, Oklab, dither,
ColorDouble, fingerprint, spine, binomial beauty); the EMD/Birkhoff/MAP-Elites
scoring modules do not yet have law counterparts. `tesseract-isp-golden` emits
JSON vectors the Swift port must reproduce.

## Repository layout

```
project.yml               XcodeGen manifest (iOS 26, Swift 6, strict concurrency)
Tesseract/
  App/                    TesseractApp, ContentView (mode picker + state machine UI)
  Camera/                 CameraManager (TrueDepth RGB+D sync), FrameBuffer,
                          RAWCaptureManager + RAWBurstPackage (48 MP DNG bursts)
  Model/                  TesseractCoord (index ↔ (d,a,b,c) bijection), Axes,
                          Histogram, GoBoard
  Tesseract/              PerfectQuantizer, BinomialCadence, BirkhoffMeasure,
                          EntropyMeasure, GeneNN/GeneTrainer/GeneCapsule,
                          MapElites, SobolExplorer, VoxelCube, animators, GIFStats
  Metal/                  Quantize.metal, Gene.metal, MetalPipeline
  GIF/                    GIFEncoder (raw-index GIF89a + LZW)
  Views/                  CubeGIFView, GIFPlayerView, PaletteSwatchView,
                          CaptureRAWView
TesseractTests/           Axiom/Level/BlockPyramid/GeneNN/GeneCapsule/MapElites/
                          Entropy/Swipe tests — mirror the Haskell axioms
spec/                     runghc axiom scripts (see spec/README.md)
isp-spec/                 tesseract-isp cabal package (see isp-spec/README.md)
```

## Build & run

**iOS app** — the Xcode project is generated, not checked in:

```sh
brew install xcodegen        # once
cd Tesseract
xcodegen generate
open Tesseract.xcodeproj     # build the Tesseract scheme on an iPhone
```

Requires a physical device for both modes (TrueDepth front camera; rear 48 MP
Bayer RAW needs iPhone 17 Pro-class hardware). Tests: the `Tesseract` scheme
runs `TesseractTests` on device/simulator.

**Haskell axiom specs**:

```sh
cd spec
make test            # all core specs, ✓/✗ per file
make list            # show every spec
```

**ISP spec**:

```sh
cd isp-spec
cabal build all
cabal test                                   # runs every ISP.Laws module
cabal run tesseract-isp-run -- a.dng b.dng --delta 0.2 -o out.gif
cabal run tesseract-isp-golden               # JSON vectors for the Swift port
```

## Status

**Working**
- Live-GIF pipeline end to end: TrueDepth capture → capture-then-compute
  PerfectQuantizer → tesseract-palette GIF89a, with live Metal preview and
  Birkhoff scoring.
- Three-phase gene interaction (Dual Explore → Compose → Refine) with GPU gene
  dispatch and MAP-Elites. The MLX training hook exists but is conditionally
  compiled and inactive until the MLX package is added to `project.yml`.
- `spec/` axiom suite and the Swift unit tests that mirror it.
- `tesseract-isp` library, law suite, golden-vector generator, and the
  reference CLI (fixture DNGs included).

**In progress**
- Rear-camera RAW burst capture (`RAWCaptureManager`, `RAWBurstPackage`,
  `CaptureRAWView`) and its wiring into `ContentView` — the on-device front end
  of the DNG → (R,G,B,T) track. Uncommitted.
- The Swift/Metal port of the `isp-spec` pyramid-double / fingerprint /
  spine+delta path (the Haskell spec and laws exist; the app still uses the
  live 4⁴ path).
- `ColorDouble` instance choice (KMeans vs PCA vs Coproduct) is deliberately
  open pending Birkhoff-score benchmarks, as is the spine/delta size
  allocation (currently 192 + 64).
