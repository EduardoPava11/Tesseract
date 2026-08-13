# THE ATLAS — every stage of the machine, named and placed

Built 2026-08-13 by a seven-reader sweep of the whole tree (capture, solver, ANE,
learned core, GIF weave, surface, isp-spec). **106 stage entries → 101 canonical
stages, 447 tunables.** The tunables live in [ATLAS-TUNABLES.md](ATLAS-TUNABLES.md);
this file is the map.

The purpose is not documentation. It is the precondition for evolving Tesseract
from a fixed capture app into a customizable one: **you cannot expose a knob you
have not named.** Every stage below carries a coordinate, and every frozen choice
inside it is catalogued. §7 is the direction that falls out of the map.

---

## 1. How to read a coordinate

Every stage has two axes:

**MOVEMENT** — *when it runs*, named by the square-word the grid is speaking at
that moment. The SurfaceMachine's six words are already the user's mental model
of the app; the atlas simply admits that they are also the engine's clock.
Two timeless bands hold what never runs.

**CATEGORY** — *what kind of thing it is*. Eight kinds:

| category | means | promotion rule |
|---|---|---|
| `SENSE` | hardware in — pixels, depth, mesh | only the gate is a knob |
| `SIGNAL` | derived control fields that steer other stages | knobs here move everything downstream |
| `SOLVE` | deterministic optimization; same input → same bytes | the look lives here |
| `LEARN` | trained; weights frozen at build time | corpus is a program, never captured data |
| `WEAVE` | assembly into the GIF89a byte stream | contract-locked, few knobs |
| `SURFACE` | what the user sees and touches | the SET cover is the only home for choices |
| `METER` | measures the cube but changes no byte | **the promotion pool — see §6** |
| `LAW` | constrains, never transforms; specs, lints, tests | changing a law is changing the app |

`METER` is the category the readers did not have and the machine most needs. Nine
stages measure the cube in exquisite detail and then throw the answer into a GIF
comment. Every one of them is a control signal that has not been promoted yet.

---

## 2. The spine in one breath

Front camera opens → RGB+depth arrive paired at 20 Hz → both crop to a centered
square and downsample to 64×64 → depth becomes a `[0,1]` nearness signal → 64 such
frames accumulate into the pinned 64³ cube → a two-Gaussian mixture splits every
pixel into subject/ground and hands out a soft role `t` → chroma is compressed
toward the frame centroid by γ(s) → nine numbers per frame (OKLab centroid +
covariance + PCA) are smoothed across a 16-slot ring by the JEPA head → a 7-generation
analytic pair tree grows 128 primaries → the ground half is built by mirroring each
primary through the Wada law into slots 255−i → every pixel takes an argmin against
its half → an ordered Bayer mask bleeds the boundary and a 4×4×4 spacetime mean
blurs the ground → 64 index frames and 64 768-byte local color tables assemble into
a GIF89a whose comment carries the generating numbers → archived, shown, kept.

**Capture is capture-then-compute.** Nothing solves during recording. That is why
WEAVING is the emptiest movement in the atlas and why the solve gets a whole scene
of its own.

---

## 3. THE MOVEMENTS

### ⓪ WAKING — the device opens

| stage | cat | what it does | anchor |
|---|---|---|---|
| `OPENING` | SENSE | AVCaptureSession (.photo, 32BGRA + DepthFloat16, 20 fps locked, portrait+mirrored) or ARSession (1 face) | `CameraManager.swift:278` |
| `GATING` | LAW | the four refusal predicates: permission, front `.builtInUltraWideCamera` (Center Stage), TrueDepth, ARKit face tracking | `CameraManager.swift:292` |
| `LATTICE` | LAW | atom = 4 pt = 1 displayed GIF pixel; the 100×218 cell canvas; every dimension in cells | `TesseractLattice.swift:30` |
| `PLACING` | SURFACE | layout-as-data: 9 scenes of disjoint, in-bounds `GridRegion`s, self-checked at DEBUG launch | `GridLayout.swift:40` |
| `INKING` | SURFACE | the closed opaque-ink token vocabulary + type registers (micro/label/body/counter/display) | `Ink.swift:8` |
| `TICKING` | SIGNAL | the one UI clock: CADisplayLink at 20 Hz, 1 tick = 5 cs = one GIF frame | `SurfaceClock.swift:44` |
| `SURFACING` | SIGNAL | `CameraState`/`FaceCaptureState` → the six words; totality proven both ways | `SurfaceMachine.swift:65` |

*Face:* `IdleStateView` — wordmark, `4^4 = 256`, a static checker, the word WAKING.

### ① WATCHING — 20 Hz, nothing is being kept

| stage | cat | what it does | anchor |
|---|---|---|---|
| `PAIRING` | SENSE | `AVCaptureDataOutputSynchronizer` emits (RGB, depth?) per hardware frame; depth may be absent | `CameraManager.swift:817` |
| `WRAPPING` | SENSE | zero-copy `CVPixelBuffer` → `MTLTexture` via the texture cache | `MetalPipeline.swift:182` |
| `POOLING` | SENSE | GPU centered crop (768 RGB / 256 depth) + integer-stride downsample to 64², 90° rotation baked in | `Quantize.metal:186` |
| `SQUARING` | SIGNAL | the same contract on CPU — the fallback twin and the spec's geometry (G1–G7) | `CameraManager.swift:496` |
| `READING` | SIGNAL | textures → CPU arrays; **meters → `[0,1]` nearness** — the contract boundary every consumer trusts | `MetalPipeline.swift:367` |
| `NEARING` | SIGNAL | disparity-affine s(m) = clamp01((1/m − 1/d_far)/(1/d_near − 1/d_far)); invalid → ½ | `DepthSignal.swift:19` |
| `MESHING` | SIGNAL | FACE twin: ~1220 ARKit vertices → anatomical signal s = 1 − dist(v, nose)/R, barycentric | `FaceCaptureManager.swift:227` |
| `GLIMPSING` | SOLVE | the 5 Hz solve: the coarse read handed to `process` — stats, ground law, live table, the palette being born (EM13: the export encoder, not a preview twin) | `DyadPipeline.swift:732` |
| `SHADOWING` | SOLVE | GPU preview assign (argmin vs 128 primaries, σ-mirror) at 20 Hz; CPU reference on failure | `Quantize.metal:57` |
| `SWITCHING` | SURFACE | LIVE ↔ FACE: synchronous TrueDepth ownership handoff, one owner only | `ContentView.swift:75` |
| `FACING` `GLYPHING` `SPRITING` | SURFACE | control-face treatment table, 1-bit AA-off glyph rasters, cell-indexed sprites | `CellMechanics.swift:44` |

*Face:* `LivePreviewStateView` / `FacePreviewStateView` — the 64-cell preview, the
beat-ringed shutter, SET. **This is the one surface** (SIMPLICITY decree).

### ② WEAVING — 64 frames are being kept

| stage | cat | what it does | anchor |
|---|---|---|---|
| `HOLDING` | SENSE | the frame buffer fills to exactly 64; drops leave no holes (dense reindex, real timestamps kept) | `FrameBuffer.swift:29` |
| `CADENCING` | SIGNAL | σ(s) = σ_base·(2−s), σ_base = (K−1)/8 = 7.875; four Gaussian epoch centers | `BinomialCadence.swift:18` |

*Face:* `RecordingStateView` — `n / 64` and a 64-column bar that **is** the cube filling.

The whole movement is two stages. Everything else waits.

### ③ SOLVING — the engine

**The control signals**

| stage | cat | what it does | anchor |
|---|---|---|---|
| `SPLITTING` | SIGNAL | tied-variance two-Gaussian EM over the pooled depth field → crossover s*, temperature τ = σ²/(μ_F−μ_B), soft role t(s) — **constant-free**, BIC-gated | `DepthMixture.swift:72` |
| `SCANNING` | METER | top-left 19×19 → three Go boards (R/G, G/B, B/R) for the solve scene | `GoBoard.swift:70` |

**The palette solve** (per frame, 64 times)

| stage | cat | what it does | anchor |
|---|---|---|---|
| `STAGING` | SOLVE | chroma compressed toward the (1−t)-weighted centroid by γ(s) = 1/(2−s) — aerial perspective | `DyadPipeline.swift:87` |
| `SIGHTING` | SIGNAL | the **nine generating numbers**: OKLab centroid + 3×3 covariance + sign-canonical PCA (Jacobi) | `DyadPalette.swift:287` |
| `STEADYING` | LEARN | JEPA-H head smooths the 16-slot ring (slot = 4 frames = 5 Hz); 149 floats, parity 9e-16 | `JepaHHead.swift:44` |
| `BRANCHING` | SOLVE | 7-generation analytic pair tree of closed-form half-Gaussian splits → 128 primaries + 16 depth-4 node means | `PairTree.swift:60` |
| `SHELLING` | SOLVE | the flag-off ancestor: binomial ladder [1,1,2,4,8,16,32,64] on concentric PC1×PC2 ellipse shells | `DyadPalette.swift:44` |
| `GROUNDING` | SOLVE | T[255−i] = ground(T[i]) — v7 same-hue: hue kept, chroma power law, rigid L-shift (Wada-derived) | `DyadPalette.swift:145` |
| `ASSIGNING` | SOLVE | argmin: face → 0…127, ground → σ-mirror 255−i. One fused ANE dispatch; exact CPU path on any failure | `DyadPipeline.swift:406` |
| `BLEEDING` | SOLVE | Bayer 4×4 threshold flips coverage back to the primary side; σ-side pixels target the **4×4×4 spacetime block mean** | `DyadPipeline.swift:69` |
| `CHURNING` | SOLVE | fixed-K exchange sweeps over 4³ blocks (ANE graph / Metal SIMT / CPU). **Flag OFF** | `ANELoop.swift:232` |
| `LATTICING` | SOLVE | the legacy 4⁴ quantizer — depth-weighted Floyd-Steinberg per channel + Gaussian-cadence epoch. Feeds preview + meters only | `PerfectQuantizer.swift:38` |

**The meters** (measure, change nothing)

| stage | cat | what it measures | anchor |
|---|---|---|---|
| `METERING` | METER | DYAD ENERGY: E_pal (Σ chroma²) and E_dist (domain-wall fraction + occupancy entropy — an Ising energy) | `DyadEnergy.swift:32` |
| `WITNESSING` | METER | PHASE F: D₁₆/D₃₂/D₆₄ distortions, Haar band energies u4/u2/u1, chaos entropy per 4³ spacetime block | `PhaseTelemetry.swift:59` |
| `SCORING` | METER | DYAD HARMONY (Ou & Luo CH) + BirkhoffMeasure (order, complexity, beauty = O/C) | `DyadHarmony.swift:44` |
| `RUNGING` | METER | **the octave ladder**: exact 2×2×2 pooling 64³ → 32³ → 16³, mass conservation, free-block counts | `TriScaleLadder.swift:78` |
| `HUMMING` | METER | Sethares roughness of the cadence comb per 16³ voxel — an urgency field, ruled but unwired | `Dissonance.swift:25` |

*Face:* `ProcessingStateView` — the word, the three Go boards, and a 16×16 swatch of
the palette **being born**.

### ④ SEALED — bytes

| stage | cat | what it does | anchor |
|---|---|---|---|
| `JUDGING` | LAW | eligibility: all 64 frames non-empty with raw RGB. No fallback chain, by decree | `GIFMachine.swift:51` |
| `FLIPPING` | WEAVE | mirror as an index-domain swap — exact, involutive, no color math | `GIFMachine.swift:57` |
| `LEDGERING` | METER | the provenance comment: DYAD SETTINGS / MIXTURE / STATS v3 / HARMONY / JEPAH / SK GENES | `GIFMachine.swift:72` |
| `FATTENING` | WEAVE | each index replicated into a 4×4 block — index domain, no interpolation; `decimate ∘ replicate = id` | `GIFEncoder.swift:148` |
| `STITCHING` | WEAVE | GIF89a: LSD, GCT = frame 0's table, NETSCAPE loop, comments, then 64 frames each with its **own 768-byte LCT** | `GIFEncoder.swift:34` |
| `RESOLVING` | SOLVE | reads the trace back and re-solves the tables **byte-equal** — the GIF carries its own generator | `GIFMachine.swift:195` |
| `ARCHIVING` | WEAVE | every successful export auto-files to Documents/Library. No sidecar DB; the GIF is self-describing | `GIFLibrary.swift:29` |
| `KEEPING` | SURFACE | Photos save (bytes as-is) or share sheet | `GIFSaver.swift:20` |
| `SHELVING` `REPLAYING` | SURFACE | the 3×3 library cover; `UIImageView` playback at the encoder's own declared rate | `LibraryView.swift:26` |

*Face:* `ResultStateView` — the playing GIF, five metrics, SHARE / KEEP / AGAIN.

### ⑤ REFUSED — the four terminals

`REFUSING` [SURFACE] speaks the two-register voice: an all-caps word in reject red,
then one lowercase sentence. `NO CENTER STAGE`, `NO TRUEDEPTH`, `NO FACE TRACKING`
are terminal (no RETRY, by SM4); `CAMERA OFF` and `EXPORT FAILED` recover.

### ∞ THE LAW BAND — never runs

`TIMEKEEPING` (DS/DM/MS temporal axioms) · `GRIDDING` (the 4⁴ coordinate algebra) ·
`CROPPING` (FrameGeometry G1–G7) · `DECREEING` (46 spec files green; byte-exact table
regeneration) · `GUARDING` (SM1–SM5, UM1–UM6, L1–L5, lint, DEBUG self-checks) ·
`BENCHING` (ANE dispatch floor 0.23 ms, per-stage fit) · `PROVING` (Metal/MLX parity 3e-7) ·
`TWINNING` (the byte-gated float64 Python port of the solver) · `FUSING` (build-time
mlpackage construction).

### ∞ THE FORGE — Mac-side, frozen into the binary

The learned core never trains on device and never trains on captured data
(★NO-CAPTURE-TRAINING). The corpus **is a program**: `(file, seed)` regenerates it
byte-identically.

`SEEDING` (the GIF89a statistical-variance sampler) → `DREAMING` (1024 capture rings,
tables rendered by the Haskell solver itself) → `LEARNING` (5,789 params) → `FOLDING`
(mlpackage) → `BRIDGING` (149 floats emitted as Swift, parity 9e-16) → **`STEADYING`
in the app.**

The gene line: `REDUCING` (16,896 size-7 SK terms → 27,419 typed reduction pairs) →
`PASSING` (axis-anonymous reduction JEPA, rollout→NF 0.988) → `OCTAVING` (the composed
binary σ/κ detail prior) → `COUPLING` (color octave blocks → the gene latent) →
`FREEZING` (three fused mlpackages) → `TELLING` (one provenance line).

Retired but law-bearing: `DESCENDING` (nn/descent — forked the assignment path; killed
by the ONE-MODEL decree, its nesting laws survive), `DEBAYERING` (front cameras emit no
Bayer), `DITHER-PLANNING` (planned, unbuilt).

### ∞ THE ATTIC — isp-spec, read-only, and more relevant than it looks

Marked deprecated. It is also where the color science you are asking for is already
written and proven:

| stage | what it holds |
|---|---|
| `ATTIC:SEEING` | `downsampleMean2Oklab` — **the octave-mean primitive: the coarse cell is literally the mean color of its children** |
| `ATTIC:DITHERING` | `bayerDownsampleBW` — mean-pool L, *then* threshold. The canonical statement that **fine scale = dither of the coarse mean** |
| `ATTIC:DOUBLING` | the **palette octave**: each parent color i splits into (2i, 2i+1); law C2 — pairing children recovers the parent exactly |
| `ATTIC:FINGERPRINTING` | the joint ladder: L0 1024² full-color → L6 16² 64-color. **Space halves as palette doubles** |
| `ATTIC:SPINNING` | a 192-color spine shared by all frames + 16 × 64-color deltas, one per 4-frame group — **palettes evolving through time**, structured |
| `ATTIC:COMPOSING` | `compose64` — all 7 levels resampled to 64² and blended by **a 7-weight vector**. Linear, differentiable |
| `ATTIC:BELLING` | the binomial beauty measure the app still ships as BirkhoffMeasure |
| `ATTIC:PYRAMIDING` | the conservation S·K = 4096 at every level; L6 = (64, 64) is the shape the live app later pinned |

---

## 4. What every stage is guarded by

101 stages, 46 green Haskell spec files, 27 XCTest suites, one lint pass, DEBUG-launch
self-checks. The discipline is unchanged: **spec with axioms before the Swift port**,
and camera code is compile-only off device.

---

## 5. Where choices live today

Two. `bleed` (coverage dither band vs hard classes) and `mirror`, both in the SET
cover, both `UserDefaults`. Plus the LIVE/FACE mode pill. That is the entire
customization surface of a machine with 447 frozen choices in it.

Six more are internal flags one line from being user-visible — `pairTree`,
`jepaHSteady`, `skGenes`, `phaseChaosLoop`, `groundV7`, `aneAssign` — each gated in
`CameraConfig` and each already law-covered.

---

## 6. The promotion pool

The five METER stages compute, per capture, an exact description of how the cube
spends itself across scales — and then write it to a comment. `RUNGING` already pools
the cube 64³ → 32³ → 16³ by exact 2×2×2 sums and proves mass conserved.
`WITNESSING` already computes the Haar band energies u4/u2/u1 of that same tower.

**Nothing reads them.** Promoting a meter to a control signal is the single cheapest
structural move available, because the measurement is already proven correct.

---

## 7. THE OCTAVE — the direction

> *"2×2×2 ↔ 1 at the three scales CAN be taught in color science. Think of that as the
> greyscale approximation of a binary black and white tiling, but in 3D+1D — the
> per-frame color palettes evolve through time, their dithering too."*

The map says this is not a new feature. **The machine is already an octave machine
in four separate places that do not know about each other.**

| where | the 2×2×2 ↔ 1 relation, as it exists today | status |
|---|---|---|
| `RUNGING` | exact 2×2×2 pooling of the 64³ spacetime cube → 32³ → 16³, mass conserved (TL3) | **meter only** |
| `BLEEDING` | the σ-side targets the mean of its 4×4×4 spacetime block (S4 chaos blur) | shipping |
| `OCTAVING` / `OctaveCodec.hs` | σ_g(x) = (x+g, x−g) composed over 3 wired levels → 8 leaves whose **mean is exactly x**, for *any* learned generator (CX2); codewords copy exactly (CX6) | trained, **unwired** |
| `ATTIC:SEEING`+`DITHERING`+`DOUBLING` | mean-pool then threshold; parent color ↔ child pair; space halves as palette doubles | proven, **unported** |

And the three "16"s in the app are the same 16: the temporal ring (16 slots × 4
frames = the 5 Hz cadence), the spatial rung (16³ pooling), and the palette prefix
(16 depth-4 pair-tree nodes = the 32-level chaos target). The octave is already the
app's native unit of thought. It has simply never been given a name or a dial.

### The object to build

**One operator, four dimensions, three levels.** Take the cube as 64×64×64 in
(x, y, t) — space is 64², time is 64 frames, and they are already the same axis in
`BLEEDING` and `RUNGING`. Then:

- **κ (contract)** — a 2×2×2 spacetime block becomes one cell whose color is the
  **OKLab mean** of its eight children. Proven exactly in `ATTIC:SEEING` and
  `RUNGING`; the latter already runs it on every capture.
- **σ (expand)** — one cell becomes eight, `x ± g(x)` per level. `OctaveCodec` proves
  the mean survives *whatever* g learns (CX2), so **the coarse color can never drift**.
  This is the load-bearing safety property: a user can move the dither hard and the
  exposure, white point, and cast stay exactly where the solver put them.
- **the detail** is what κ throws away: seven Haar coefficients per block, which
  `WITNESSING` already computes and bands as u4/u2/u1.

That is the greyscale-approximation-of-a-binary-tiling statement, lifted to color and
to 3D+1D: **the coarse cell is the mean; the fine scale is the dither that realizes
it; the temporal axis is just the third octave direction.** Nothing new is required
to say it — only to wire it.

### The dial

The customization surface is then **a 3-vector: how much detail each octave keeps.**
`ATTIC:COMPOSING` already implements exactly this as a weight profile
(`flatWeights` vs `laplacianWeights`), linear and differentiable. Under the SET
cover's one-screen budget that is one control — a three-band equalizer for the cube:

- **coarse (16³)** up → the ground holds still across 4-frame groups, colors read as
  fields. This is the `BLEEDING` temporal group and the JEPA ring, exposed.
- **mid (32³)** up → structure at the scale the pair tree actually resolves.
- **fine (64³)** up → per-frame, per-pixel shimmer; the dither carries the image.

And because per-frame LCTs are already the law (★PERFRAME-PALETTE decree), the
palette *is* free to evolve per frame — the octave weights simply decide **how fast**
it is allowed to, in exactly the way `ATTIC:SPINNING` groups four frames to a delta.

### What it is not

It is not a filter, a preset list, or a second model path. The one-model decree
(nn/jepa) holds: `OCTAVING`'s generator is already trained, already frozen, and takes
the palette **as input, never as weights** (CX7 — the reason per-capture dynamic
palettes are safe). Wiring it is a promotion, not a fork.

### The order of work, spec-first as always

1. **Name the operator in Haskell** — one spec that states κ and σ over the 64³
   spacetime cube in OKLab, with the mean-exactness law lifted from `OctaveCodec`
   CX1–CX3 and the pooling law from `TriScaleLadder` TL3. One file, axioms first.
2. **Promote `RUNGING` from METER to SIGNAL** — it already computes the tower; give
   it an output the solver can read.
3. **Port `ATTIC:SEEING` / `ATTIC:DITHERING`** — the two primitives, unchanged, out of
   the deprecated tree and under the live specs. They are already proven; they need a
   home, not a rewrite.
4. **Wire `BLEEDING` to the tower** — its 4×4×4 block mean becomes level 2 of the
   octave rather than a private constant, and its Bayer threshold becomes the level's
   detail realization.
5. **Only then, the dial.** Three weights in `ExportSettings`, one control in the SET
   cover, defaults that reproduce today's bytes exactly (weights that make the
   identity — the same zero-init discipline `DITHER-PLANNING` ruled for Model A).

Step 5 changes what users see. Steps 1–4 change nothing at all, and each is
verifiable against bytes that already exist.

---

## 8. Open, owed

A device pass on the 17 Pro is owed for every arc since 2026-08-11 — the rate ladder,
the JEPA head at SOLVING, the surface machine, the per-frame palette decree, and the
SK genes. The atlas does not change that. Nothing in §7 should be wired before the
existing shipping path has been seen on hardware.
