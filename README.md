# Tesseract

An iPhone front-camera app that makes small animated GIFs whose colour
system is solved per capture rather than chosen from a palette.

Every export is the same shape: **64 frames of 64x64 palette indices**,
written out at 256x256 pixels and exactly 20 fps. The name comes from
the original 4^4 = 256 entry (epoch, R, G, B) lattice. That lattice is
still the app's coordinate vocabulary (`TesseractCoord`), but it is no
longer how a GIF gets its colours. Since the 2026-08-12 decree the
export path is DYAD-256: **every frame carries its own 768-byte local
colour table**, solved from that frame's own statistics.

Haskell is authoritative. Swift and Metal are ports of it, and the
Mac-side MLX lab in `nn/` is where models are trained. New mechanisms
get a spec with named axioms BEFORE the port.

## Where to read next

`docs/ATLAS.md` is the map: all 101 canonical stages on a MOVEMENT x
CATEGORY coordinate. `docs/ATLAS-TUNABLES.md` catalogues the frozen
choices with source anchors. `CLAUDE.md` holds the standing decrees and
is the authority when a doc disagrees with it. Read the atlas before
adding a stage, and give any new stage a name and a coordinate in it.

## Device targeting

The app is for iPhones with the square-sensor 18MP Center Stage front
camera (iPhone 17, Air, 17 Pro, 17 Pro Max and later). The hardware
predicate uses no naked constant: that camera is the only front-position
`.builtInUltraWideCamera` ever shipped on iPhone. Both capture managers
gate on it at WAKING, and failure is a terminal refusal ("NO CENTER
STAGE"), not a degraded mode. Capture itself still runs on
`.builtInTrueDepthCamera`. Deployment target is iOS 26.0.

## Front camera only

This is a standing decree. Do not add rear-camera capture (Bayer DNG,
LiDAR, 48MP) without Daniel explicitly asking for it. Ambiguous RAW or
DNG requests do not count, because front cameras emit no Bayer DNGs, and
that contradiction is Daniel's to resolve rather than the implementer's.

RAW *processing* capability is welcome on main: Haskell specs, the `nn/`
Mac-side lab, pure Swift math. Rear *capture in the app* is not. All
rear work lives on archive branches, none of them merged, by design:
`archive/rear-rgbt` (photon-time RGBT burst), `archive/dng-mode-v2`
(NN-debayer DNG mode), `archive/isp-spec` (the physics-grounded ISP
cabal package, moved off main 2026-08-14).

## Two capture modes

Both fill the same pipeline slot with a per-pixel signal in [0,1], so
everything downstream is shared.

### LIVE, the TrueDepth depth cadence

Synchronized RGB plus depth at 20 fps via `AVCaptureDataOutputSynchronizer`,
a universal centred crop (768 squared RGB, 256 squared depth), downsampled
to the 64 cube. Depth drives the role split and the cadence.

### FACE, the ARKit anatomical cadence

`ARFaceTrackingConfiguration` delivers camera frames plus the roughly
1220-vertex face mesh, and **the mesh IS the depth**. The nose is the
vertex with maximum face-local z, and the per-vertex signal is
`s = 1 - ||v - nose|| / R`, which is scale-free: the same face at any
distance yields the same signal. Vertices project through ARKit's camera
and triangles rasterize barycentrically, with background exactly 0.
Spec `spec/temporal/FaceCadence.hs` (FC1 to FC8), port
`FaceMeshSignal.swift`, mirrored by `FaceMeshSignalTests`.

The TrueDepth camera admits one owner, so ARSession (FACE) and
AVCaptureSession (LIVE) cannot coexist. Mode switches stop one system
synchronously before starting the other.

## The export contract

Non-negotiable, per the 2026-08-12 decree:

- **Per-frame palettes only.** Every GIF carries one 768-byte Local
  Colour Table per frame (packed byte 0x87 on every image descriptor;
  the global table is frame 0's). The old tesseract and refined
  global-table methods, the fallback chain and the persisted LOOK
  setting are all deleted.
- **A capture that cannot run DYAD exports NOTHING.** The failure
  surfaces as an error, never as a silent global-table downgrade.
- **256x256 pixels, always**, by palette-index replication and never
  interpolation (`decimate . replicate = id`).
- **5 cs frame delay**, exactly 20 fps.
- Byte-level contract locked by `DyadGIFContractTests`.

Every GIF is self-describing. Provenance comments carry the generating
state (DYAD STATS, DYAD MIXTURE, DYAD HARMONY, RATE LEDGER, and the
telemetry channels), which is why the library needs no sidecar database.

## How a capture becomes a GIF

The role split is constant-free by decree (no naked thresholds). The
pull `t` is the posterior of a tied-variance two-phase mixture fitted on
the capture's own pooled depth field, so the near/far boundary is
derived from the data rather than chosen. Solid and band boundaries are
the Bayer extrema. A single-phase BIC verdict means all-face.

The figure half of the palette is an analytic dyadic tree
(`PairTree.swift`): splitting the fitted Gaussian at its mean along an
eigenaxis gives two half-Gaussians with exact moments, so the whole
7-generation tree is closed-form arithmetic in the 13 traced numbers.
The ground half is generated as the sigma mirror, keeping the figure's
own hue (the hue negation was killed in v7: it painted warm subjects
against a blue-grey background).

Assignment runs on the ANE as a fused exact-arithmetic graph with zero
learned parameters (`DyadAssign.mlpackage`, authored in
`nn/dyad-assign/`), with an exact CPU path as both fallback and parity
reference.

## The ladder

The pipeline is one compressor, from roughly 10^9 camera bits to roughly
10^6 GIF bits, declared as strata whose ratios telescope. The 2x2x2
spacetime pooling atom is an 8:1 ratio. The rungs are 16, 32 and 64: the
resolution of depth is rung 16 (5 Hz), while RGB rides rung 64 (20 Hz).
Every rung writes bits of every index (`index = role*128 + r16*64 +
r32*8 + r64`), so no rung is telemetry.

## Repository layout

```
project.yml            XcodeGen manifest (iOS 26, Swift 6, strict concurrency)
CLAUDE.md              standing decrees; the authority on disagreement
Tesseract/
  App/                 TesseractApp, ContentView
  Camera/              CameraManager (TrueDepth RGB+D sync), CameraConfig flags,
                       FaceCaptureManager (ARKit), FaceMeshSignal, DepthSignal
  Model/               TesseractCoord (index <-> (d,a,b,c)), Axes, GoBoard
  Tesseract/           the engine: DyadPipeline, DyadPalette, DyadANE, PairTree,
                       GIFMachine, TriScaleLadder, Dissonance, SKGene, ANELoop,
                       JepaHHead, PhaseTiling, CubeStore, GIFLibrary
  Metal/               Quantize.metal (downsample + aerialPreview),
                       ANELoop.metal (SIMT exchange loop), MetalPipeline
  ML/                  bundled mlpackages (DyadAssign, ANELoop, SKGene)
  GIF/                 GIFEncoder (raw-index GIF89a + LZW), GIFSaver
  UI/                  Lattice, Cells, Widgets, EditMachine
  Views/               state scenes, LibraryView, GIFPlayerView
TesseractTests/        357 tests mirroring the Haskell axioms
spec/                  runghc axiom suite, the authoritative layer
nn/                    Mac-side MLX lab (see below)
docs/                  ATLAS, design docs, session records
scripts/               lint-grid.sh (build-gated), wada/derive.py
```

## The Mac-side lab

`nn/` runs on Mac only and never on the phone.

- `nn/jepa` is **the** model line. One path, MLX-trained, beauty is the
  objective. Its head is currently OFF at capture (see below).
- `nn/dyad-assign` authored the assignment graph, which carries zero
  learned parameters by design.
- `nn/debayer` is the 5,616-param residual debayer (+3.72 dB over
  bilinear) with its Metal parity harness in `nn/metal-harness`.
- `nn/sk-gene`, `nn/ane-loop`, `nn/phase`, `nn/dither` are supporting
  labs for the gene calculus, the exchange loop, the dyad solver port
  and the corpus sampler.
- `nn/descent` is closed as a path and read out as lessons. Its
  README records what was integrated and what was deliberately not.

Corpora are PROGRAMS: an emitter plus a seed regenerates them
byte-identically, so they never enter the repo.

Training uses synthetic corpora only. Under the NO-CAPTURE-TRAINING
decree the corpora are GIF89a statistical variance from the app's own
stochastic laws, evaluation is synthetic, and device feel is the only
real gate.

## Build and test

The Xcode project is generated, not checked in.

```sh
brew install xcodegen                 # once
xcodegen generate
xcodebuild test -project Tesseract.xcodeproj -scheme Tesseract \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Camera code is compile-only off device, since the simulator has no
camera. The pure-logic suites do run headless. Signing on Daniel's Mac
uses team 9WANULVN2G (a cached wildcard profile signs offline), and
`GENERATE_INFOPLIST_FILE: YES` is load-bearing.

A build-phase lint (`scripts/lint-grid.sh`) enforces the grid
constitution and fails the build: sizes are atoms, regions come only
from the lattice, and converted views draw only through the cell
vocabulary.

The Haskell suite:

```sh
cd spec
make test            # the CORE suite, one line per file
make list            # every spec, including the extras CI skips
make test-one F=temporal/DepthMixture.hs
```

The harness is deliberately untrusting: a file fails on a nonzero exit
OR on any "✗" it prints, which closes the exit-code blindness of specs
that predate `exitFailure`. Never use that glyph decoratively.

## Status

**Green.** The spec CORE suite and the 357 Swift tests both pass. The
LIVE and FACE pipelines run end to end into the DYAD export.

**Owed.** A device pass is outstanding on most of the recent arc
(per-frame palettes v7, the pair tree, the aerial mirror law, the edit
machine, the ANE loop bench). The A19 microbenchmark is device-only and
skips in the simulator by design.

**Off by choice.** `CameraConfig.jepaH` is OFF as of 2026-08-14. Measured
against truth rather than against a baseline, the head held the palette
17.4% steadier than the scene actually is, and the ruling is that the
model should not dictate how we capture. Its home is the edit path.
`CameraConfig.phaseChaosLoop` is OFF pending the on-device comparison.
Both are one-line flips in `CameraManager.swift`, where the full reasons
are written down.
