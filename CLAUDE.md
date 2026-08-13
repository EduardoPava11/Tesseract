# Tesseract

iPhone camera app: 4⁴ = 256-entry (epoch, R, G, B) tesseract-palette GIFs.
Independent of SixFour.

## ★ FRONT-CAMERA ONLY — standing decree (Daniel, 2026-07-15)

This app uses the FRONT camera exclusively. Two modes:
- **LIVE** — TrueDepth synchronized RGB+depth; depth drives dither strength
  and the Gaussian epoch cadence.
- **FACE** — ARKit face mesh; anatomical signal (nose = 1, background = 0)
  fills the same pipeline slot (`spec/temporal/FaceCadence.hs`).

**Do NOT add rear-camera capture** (Bayer DNG, LiDAR, 48MP) without Daniel
explicitly saying "bring back the rear camera." Ambiguous RAW/DNG requests do
not count — front cameras emit no Bayer DNGs, and that contradiction is
Daniel's to resolve, not the implementer's. Rear work is preserved on
`archive/rear-rgbt` (photon-time RGBT burst) and `archive/dng-mode-v2`
(NN-debayer DNG mode); neither is merged, by design. RAW *processing*
capability (Haskell specs, the `nn/` Mac-side lab, pure Swift math) is
welcome on main; rear *capture in the app* is not.

## ★ CENTER STAGE gate — device targeting (Daniel, 2026-08-12)

The app is for iPhones with the square-sensor 18MP Center Stage front
camera (iPhone 17 / Air / 17 Pro / 17 Pro Max and later). Hardware
predicate, no naked constants: that camera is the ONLY front-position
`.builtInUltraWideCamera` ever shipped on iPhone (WWDC26 session 341
"Support the Center Stage front camera in your iOS app"). Both
managers gate on it at WAKING; failure = `noCenterStageMessage` →
SurfaceMachine `.refused(.noCenterStage)` "NO CENTER STAGE", a
TERMINAL hardware refusal (SM4, spec + Swift + tests all carry it).
Capture itself still runs on `.builtInTrueDepthCamera` — the 17
line's Face ID system keeps delivering synchronized RGB+depth, so
LIVE and FACE are unchanged on eligible devices.

STORE-LEVEL CUT (2026-08-12): UIRequiredDeviceCapabilities =
[arm64, front-facing-camera, iphone-performance-gaming-tier] via
INFOPLIST_KEY_ in project.yml (verified in the signed device build's
Info.plist; the key is emitted for device builds only — simulator
plists omit it by design). gaming-tier = A17 Pro+ (iPhone 15 Pro and
later) is the TIGHTEST key Apple publishes — no key exists for
Center Stage, TrueDepth, or A18/A19 — so 15 Pro/16-line users can
still install and hit the terminal NO CENTER STAGE screen. The App
Store description must state "Requires iPhone 17, iPhone Air, or
later", and App Review notes should say the same + why (reviewers
on 16-line hardware will see the refusal screen; that is the
designed behavior, not a bug).

iOS 27 note (researched 2026-08-12): iOS 27 is in beta (releases
~Sept 2026) and supports the same devices as iOS 26 (iPhone 11+),
so raising the deployment target buys NO hardware targeting — the
runtime gate is the mechanism. Deployment target stays iOS 26.0
(every 17-line device ships with 26); nothing here needs iOS 27
APIs, and this Mac's Xcode 26.6 has no 27 SDK yet. The new
Center Stage APIs (dynamicAspectRatio, AVCaptureSmartFramingMonitor,
sensor mounted PORTRAIT unlike older front cameras) are available
from iOS 26 if ever wanted.

## Architecture

★ THE ATLAS (2026-08-13): `docs/ATLAS.md` is the full stage map — all 101
canonical stages on a MOVEMENT × CATEGORY coordinate (movement = which
SurfaceMachine word is being spoken when the stage runs; category = SENSE /
SIGNAL / SOLVE / LEARN / WEAVE / SURFACE / METER / LAW). `docs/ATLAS-TUNABLES.md`
catalogues all 447 frozen choices with anchors. Read the atlas before adding a
stage, and give the new stage a name and a coordinate in it. §7 holds the
ruled next direction (THE OCTAVE — κ/σ over the 64³ spacetime cube; promote
RUNGING from METER to SIGNAL first, dial last).

Haskell is authoritative; Swift/Metal are ports (SixFour discipline).
- `spec/` — runghc axiom suite: `cd spec && make test` (54 files green
  as of 2026-08-13 — the EDIT-APP arc added RoleAllocation.hs,
  Octave.hs, EditMachine.hs, FeedCompression.hs, PhaseTiling.hs,
  WidgetGrid.hs, AttractorRAG.hs, then DetentDial.hs; the tally must
  stay at zero failures). ★ The harness fails a file on nonzero exit OR **any `✗`
  it prints** — never use that glyph decoratively in spec output,
  only in the axiom checklist. The 2026-08-11 UNIFICATION removed the pre-pivot gene-NN/
  MAP-Elites/VoxelCube/KataGo-era specs and dead Swift (git history
  keeps everything); spec/README.md is the current map.
  New mechanisms get a spec with axioms BEFORE the Swift port.
- The app is a 64³ GIF MACHINE (spec/output/ExportMethods.hs): every
  export is 64 frames of 64×64 indices with ONE method — DYAD-256
  per-frame palettes (2026-08-12 decree; the tesseract/refined
  global-table methods are deleted, ineligible captures export
  nothing). DYAD-256 (spec/quantization/DyadPalette.hs): paired
  per-frame palettes, face → primaries, background → σ-mirror
  pair-dither bleeding to 255.
- ★PHASE-PALETTE (2026-08-10/11, Daniel's ruling — background →
  CHAOS, subject → ORDER, boundary layer; information theory is the
  law; docs/phase-palette-design.md, rulings R1–R5 confirmed):
  F = D_16+D_32+D_64 over the ladder's spacetime pools = the 3:2:1
  Haar-band kernel (PP1, exact). Spec
  spec/quantization/PhasePalette.hs PP1–PP16 ALL GREEN (suite 38).
  STEP 2: PhaseTelemetry.swift traces "PHASE F v1" (D_K, bands,
  PP1 gap witness, Σ log W chaos bill) in the DYAD comment —
  measurement only. STEP 3 (ruling R2): the σ half is generated by
  the Wada FAMILY (hue mirror + chroma power law + rigid L-shift)
  with parameters MOMENT-MATCHED per capture to the background
  class (βC = sd-ratio of lnC, αC from means, ΔL from background
  mean L; staged labs, σ-side weights, stats-α EMA; uncapped) —
  T[255−i] = ground(gm, T[i]); the Wada dictionary constants
  (scripts/wada/derive.py) are the single-phase/no-evidence PRIOR
  (capped — the dictionary's role law). Trace "DYAD STATS v2" =
  9 stats + 3 moments + cap per frame; rebuildTables parses v1
  (prior path) AND v2 — the GIF still carries its full generator.
  The live surface fits the same law at the rung-16 cadence because
  it IS this pipeline (EM13). ASSIGNMENT never changed: comp = OKLab
  negation, DyadAssign ANE untouched.
- ★ANE LOOPS (2026-08-11, Daniel's ruling; docs/ane-loop-design.md):
  fixed-K exchange sweeps over 4³ spacetime blocks, descent on F.
  spec/neural/ANELoop.hs AL1–AL8 green (M diagonal in Haar bands,
  eigenvalues 3:2:1; F block-exact; monotone Gauss–Seidel with
  curvature 1+1/8+1/64; clock 20/5 = 4). L2: nn/ane-loop/ →
  ANELoopModel.mlpackage (4096 blocks × K=4 × 64 stages fused;
  model F matches float64 law to 5 digits, 99.83% assignments,
  32 ms/dispatch on M3 Max). L3: ANELoop.swift (CPU twin = law,
  engine wrapper, refineFarBlocks) flag-gated behind
  CameraConfig.phaseChaosLoop (DEFAULT OFF — flip one line for the
  device comparison; no settings surface without a ruling).
  Fully-far blocks only; face/band bytes untouched; ANELoopTests +
  all DYAD suites green. Offset architectures (§5½ of the doc):
  recommended B+E = temporal polyphase + streaming warm starts
  (20 Hz outputs after 4-frame warmup); rulings open for D
  (overlapped objective) and F (per-channel rungs). 17-PRO
  ENGINEERING (2026-08-11, target hardware = A19 Pro):
  ANELoopK1Model.mlpackage bundled (K=1 streaming unit for B+E —
  K_eff = dispatch count, no recompile; one sweep already takes F
  22564→6070) + ANELoopBenchTests = the owed A-series
  microbenchmark (device-only, compute-unit sweep incl. the A19
  GPU neural accelerators, two-point stage/floor fit, 5 Hz / 20 Hz
  budget verdicts). Daniel runs ⌘U on the phone to pin K. SIMT PORT
  (2026-08-11): AL9 green (spec §4b — running-sum sweep == law,
  exact over Rational); Metal/ANELoop.metal one-thread-per-block
  kernel (no sync, RUNTIME K — the adaptive-K port the fused ANE
  graph can't be) + ANELoop.sweepSIMT; ANELoopSIMTParityTests
  PASSED on 17 Pro sim: 100.00% agreement, F 119.06→25.71 equal on
  both ports; bench prints metal-simt rows for the direct GPU-vs-ANE
  comparison on A19. The role split is
  CONSTANT-FREE (spec/temporal/DepthMixture.hs, 2026-08-10 decree:
  no naked thresholds): pull t = posterior of a tied-variance
  two-phase mixture fit on the capture's own pooled depth field;
  solid/band boundaries = the Bayer extrema {1/32, 31/32}; analyze
  weights = 1−t; stats EMA α = derived Kalman gain (localLevelAlpha);
  BIC single-phase ⇒ all-face. The crossover is REPORTED in meters
  in the "DYAD MIXTURE" provenance comment. Assignment runs on the ANE
  (Tesseract/ML/DyadAssign.mlpackage, authored in nn/dyad-assign/,
  exact CPU fallback; placement laws XP1/XP2).
- The 16/32/64 ladder (spec/output/TriScaleLadder.hs →
  Tesseract/TriScaleLadder.swift, 2026-08-10): SixFour's color-head
  tri-scale pyramid ported to the export cube. Exact u64 lattice-level
  sums pooled over 2×2×2 spacetime blocks (64³→32³→16³); time law
  side × delay = 320 cs. MEASUREMENT ONLY — published as rungTelemetry
  on both capture managers; no GIF byte depends on it; trains nothing
  (★NO-CAPTURE-TRAINING). Distinct from quantization/ResolutionLadder
  (subject-gated per-cell resolution). TL8/TL9 (2026-08-10): 16³ ==
  32³ == 64³ in the information process, compute time = the
  equivalence; THE RESOLUTION OF DEPTH is rung 16 (64 draws per
  judgment, 4096 judgments/loop at 5 Hz; RGB rides 64-rung at 20 Hz).
  §8 OFFSET LAWS (2026-08-11, Daniel: "2×2×2 ↔ 1, think
  convolutions"): the stride-2 spacetime pool is ONE of 8 polyphase
  components ((ℤ/2)³); TL10–TL12 green — phases partition the loop
  torus (t-wrap exact by periodicity), the 8-phase orbit == the
  [1,2,1]³ tent prefilter (phase-cycled reads = anti-aliasing at box
  cost), offsets compose o₁+2o₂ so odd phases need fresh fine reads.
  CARRIER stays aligned (only phase 0 telescopes); phases are a READ
  cadence. Phase-cycling telemetry reads (ladder, Dissonance tuning)
  needs no ruling; offsetting the LIVE solve's GIF-shaping cadence
  AWAITS RULING (its ring is Rung.coarse.frames, so the 3.2 s span
  law now scales with the rung by construction).
  Gates: spec TL1–TL12 + TesseractTests/TriScaleLadderTests.
- THE DISSONANCE WEAVE (2026-08-10, design docs/dissonance-weave-design.md):
  Sethares/Plomp-Levelt roughness ported as ONE kernel, three ports —
  spec/statistics/Dissonance.hs (kernel, DS1–DS16; b1=3.51 b2=5.75
  x*=0.24 s1=0.0207 s2=18.96), spec/quantization/SpectralPalette.hs
  (octaves in RGB → color: channel combs (4,5,6)·125·2^ℓ Hz, tuning =
  argmin of the loop's own occupancy spectrum, σ-involution = tritone),
  spec/harmony/SetListDissonance.hs (F0-lock 0.3125 Hz; inter-loop
  (X_ear, χ_eye) dyad; set ordering). Depth → urgency: bond roughness
  on σ(d) cadence with ZERO tuned constants (near/far = exact octave ⇒
  x = x* theorem); urgency field 16³ at 5 Hz (TL9 clock).
  SWIFT PORT v1 LANDED (Dissonance.swift + DissonanceTests): kernel,
  G quadratic form, tuning at the rung-16 cadence (16 reads/loop,
  Daniel's TL8 ruling), urgency field published as `dissonance` on
  both managers. ★URGENCY IS A WEIGHT (the color-weight slot, no
  directional sign). Telemetry-only; felt channel decided after the
  device movement pass.
- `isp-spec/` — DEPRECATED rear-camera cabal ISP spec, read-only reference.
- `nn/` — Mac-side lab: MLX-trained 5,616-param residual debayer
  (`nn/debayer/`, +3.72 dB over bilinear) and its Metal parity harness
  (`nn/metal-harness/run.sh`, verified 3e-7 on M3 Max). Runs on Mac only.

## Export contract

★ PER-FRAME PALETTES ONLY (Daniel's decree, 2026-08-12, NON-
NEGOTIABLE): every GIF carries one 768-byte Local Color Table per
frame (packed byte 0x87 on every image descriptor; GCT = frame 0's
table). The tesseract/refined global-table methods, the fallback
chain, and the persisted LOOK setting are DELETED (GIFMachine,
GIFEncoder, CentroidRefiner/RefineAccumulator/Refine.metal, the
SettingsView LOOK radio, GIFOutputContractTests). A capture that
cannot run DYAD exports NOTHING — nil surfaced as
`encodeFailedMessage`, never a silent global-table downgrade.
Every GIF is 256×256 px (palette-index replication, never
interpolation; `decimate ∘ replicate = id`), exactly 5 cs frame
delay = 20 fps. Byte-level contract locked by `DyadGIFContractTests`
(per-frame LCTs + ground law in every table). DYAD exports carry a
"DYAD HARMONY" provenance comment (Ou & Luo pair score over all
frames).

★ THE PREVIEW IS THE GIF (Daniel's decree, 2026-08-13;
spec/ui/EditMachine.hs EM12/EM13): weave = watch + keep — WATCHING
and WEAVING run the SAME encoder and differ only in RETENTION, so a
second preview implementation cannot exist. DyadPreview.swift is
DELETED; `DyadPipeline.Live` is a DRIVER over `DyadPipeline` itself,
not a second law. The read pools the fine feed to the coarse rung
(κ = 4 in space × 4 in time) carrying the within-cell depth variance
so DM11's τ-lift keeps the band the fine rung's; the solve is
`DyadPipeline.process` over the 16-frame coarse cube = the last
3.2 s = one loop (so the surface shows the GIF the last loop would
have made — with the MS-filtered fits, the derived-α EMA, the ground
law AND ★JEPA-H, none of which the preview used to get); the 20 Hz
assignment at the fine rung calls the pipeline's own `stagedField` /
`assignRoles` / `chaosPool` / `pairDitherFrame`. The ladder is the
ONLY parameter — solve at rung 16 / 5 Hz (TL8/TL9), assign at rung
64 / 20 Hz, the same split `process` already obeys. BLEED is read
live, so the setting now answers on the surface. MetalState moved to
DyadPipeline; the aerialPreview kernel is unchanged. KNOWN REMAINING
GAP (deliberate): the live σ-side chaos target pools the CURRENT
frame only where the export pools the 4-frame S4 group — closing it
means feeding pooled targets to the kernel as a buffer instead of
its in-kernel 16-texel pool. DEVICE PASS OWED: the 5 Hz solve now
costs a pooled EM fit over 4096 coarse samples + 16 per-frame fits.

★ RATE LADDER (Daniel's ruling, 2026-08-12: "use the math and
redesign the whole pipeline — in small steps, stratified; 2×2×2 ↔ 1
is an 8:1 ratio of information"): the pipeline is one compressor
(camera ~10⁹ b → GIF89a ~10⁶ b) reframed as declared strata whose
ratios TELESCOPE — docs/rate-ladder-redesign.md is the strategy,
spec/output/RateLadder.hs (RL1–RL6 green) is the algebra: the 8:1
pooling atom + rung composition, polyphase partition, eigenvalue
allocation law (n ∝ √λ), the Birkhoff–Rigau meter M = (8−K̂)/8, the
17-level coverage code. STEP S0 SHIPPED (measurement only): "RATE
LEDGER v1 px lzw H0 K M" rides every DYAD comment, computed by the
encoder's own LZW (GIFEncoder.lzwCost) — the fitness function every
later stratum step is judged against. Steps S2–S6 (S0 box prefilter
kills decimation aliasing; S3 PC3 eigen-allocation; S4 spacetime
4×4×4 chaos blur on the loop torus; S5 band-block exchange scope;
S6 hue-conditioned harmony telemetry) AWAIT Daniel's step-order
ruling — each changes pixels and needs spec axioms + a device pass.

★ PAIR TREE (Daniel's ruling, 2026-08-12: "pair pairs so that the
8:1 ratio in all of the scales is grounded in latent algos" + "we
still need to train a model to help the capture"): the 256-entry
table is a dyadic pairing tree — sibling maps s_ℓ(i) = i XOR 2^ℓ,
eight commuting involutions whose TOTAL composition is σ(i) = 255−i
(the DYAD involution IS pairing-pairs all the way up); bit-triples
= the 2×2×2 atom, strata 256→32→4 aligned with the cube's rungs;
the binomial ladder survives as the balanced tree's growth rings;
splits are LATENT (local eigen-split at the node's own mean — RL4's
n∝√λ locally), replacing designed rings/angles. Prefix law:
truncated index ≡ coarser-level palette (chaos-blur targets should
quantize at the 32-level; assignment becomes a log-time descent →
the ANE shape). Design docs/pair-tree-palette.md; spec
spec/quantization/PairTree.hs PT1–PT6 GREEN (suite 43). CAPTURE-
ASSIST MODEL planned (nn/pair-tree/): distill the exact split
algorithm from the rung-16 slow state (SKGene G1–G6 grounding
pattern; corpora = synthetic GIF89a statistical variance per
★NO-CAPTURE-TRAINING).
★JEPA-H — THE ONE MODEL LINE (Daniel's decree 2026-08-12: no more
parallel paths; MLX JEPA-H → iPhone; BEAUTY is the objective):
nn/jepa is the only model lab. JH0–JH3 SHIPPED (commit eb4ead9):
spec/neural/JepaH.hs JH1–JH6; self-gating trajectory emitter
(make corpus-jepa, jump law); v7 = regime-conditioned symmetric
ring filter + jump gate (hypernet on ring autocorrelations, no
slot-content params — structurally cannot memorize; 5,789 params)
+ decoupled JEPA encoder (surprise channel). ALL BEAUTY GATES
GREEN vs the oracle-gain EMA (churn −11.7%, LZW(LCT) down, RMSE
better); JepaH.mlpackage folded, parity 2.7e-7. JH4 WIRED
(2026-08-12 "go hard"): the deployed head is PURE SWIFT ON CPU —
JepaHHead.swift + JepaHWeights.swift (149 weights; a 16×6 ring
sits far below the ANE dispatch floor, so the mlpackage stays the
Mac-side reference; nn/jepa/export_swift.py is the bridge, parity
9e-16 via nn/jepa/parity_swift.sh + JepaHParityTests). Placement:
DyadPipeline.jepaSmoothed pools the 64 per-frame stats to the
rung-16 ring, steadies ONE 9-dim ring = the corpus latent
(centroid + log-diagonals) PLUS the bg triple (meanL, meanLnC,
log sdLnC) — JH4b fix @5d95fd4 after the 11EB44F0 hard review
caught the split-cadence defect (figure half held per slot, churn
−14%, logW→0; ground half churned +30% on the 20 Hz EMA). The head
is per-dim + scale-free ⇒ extra dims need no retraining; off-
diagonals recombine r_ij·√(c_ii·c_jj) (PSD by construction); bg
gaps carry-fill around the torus; WHOLE tables hold at the 5 Hz
cadence the preview already fits at. Flag CameraConfig.jepaH
DEFAULT ON (one-line revert);
"DYAD JEPAH v7" trace line = the attribution; trace rebuild stays
byte-exact (the smoothed numbers ARE the generating state).
PROMOTION still owed: real-capture RATE LEDGER + HARMONY
before/after + Daniel's device pass. nn/descent is RETIRED to
lessons (DL6/DL7 stay law; lookahead-L2 belongs inside DyadAssign
if ever shipped).

★DESCENT LADDER (Daniel's alignment rulings 2026-08-12, after the
adversarial review docs/jepa-h-adversarial-review-2026-08-12.md
killed the research synthesis 0/6): the capture-assist model's
FIRST job is P4 assignment descent; the 3-MODEL LADDER (M16/M32/
M64) is committed STRUCTURALLY as one descent with three exit
depths, nested by OUTPUTS (DL2 quotient law), never weights;
corpus = synthetic only; sizes/cadences/K are DEVICE-MEASURED and
appear in no law. J0+J1 SHIPPED: spec/neural/DescentLadder.hs
DL1–DL5 green (suite 45) + self-gating emitter
(make corpus-descent → nn/descent/corpus, 48×192 probes, exhaustive
teacher labels at all three exits). nn/descent/README.md = the lab
contract. J2 (MLX training), full-PCA manifold, XP2 parity harness,
and ANY app placement are gated on the A19 bench + device pass.

★P1+P2+S4 SHIPPED 2026-08-12 (Daniel: "be bold"): the ANALYTIC
tree is live — closed-form Gaussian splits (half-normal moments:
child mean μ ± √λ·√(2/π)·u, child var λ(1−2/π) on the split axis,
basis never rotates; spec PT7–PT9 green) keep the table a pure
function of the traced 13 numbers → DYAD STATS v3 (rings remain
the v1/v2 rebuild path); σ-side chaos targets = 4×4×4 SPACETIME
block means (S4) quantized at the 32-LEVEL (16 depth-4 nodes ×
canonical leaves — prefix law, P2) in all three ports
(DyadPipeline.pairDitherFrame — export and live
surface alike — and the aerialPreview kernel buffer(3)); CameraConfig.pairTree = true (one-line revert);
PairTreeTests on sim. cL for the ground family = the stats
centroid (tree T[0] is a corner leaf, not the centroid). DEVICE
PASS OWED. P3 (Mac lab) / P4 (mlpackage + hierarchical ANE
descent) remain open.

★ v7 SAME-HUE GROUND + CHAOS BLUR (Daniel's ruling, 2026-08-12:
"the blue haze on the background is unprofessional; blur the
background as it becomes chaos"): the ground family's hue NEGATION
is dead — it made the whole σ half the complement of the face's
shells, so a warm subject painted every background pixel blue-gray
(R4 faithful-hue only re-routed the search; the displayed entries
were still hue-negated). groundLab now keeps the figure's hue
(chroma power law + rigid L-shift unchanged; Wada leaves hue
unconstrained, so the dictionary derivation stands). The σ-side
assignment target is the rung-16 BLOCK MEAN of the staged field ŷ
(4×4 blocks on 64² — the resolution of depth, TL9): the background
renders flat at rung 16 and the Bayer coverage t makes the blur
emerge exactly as fast as the chaos does — zero new constants,
seam-death preserved. Spec: DyadPalette.hs §3b/§6c/§6d, DY10/DY11
(hue-faithful axiom)/DY14 (colinear)/DY16 (blur laws) + PhasePalette
groundLab — all green. Ports: DyadPipeline.pairDitherFrame +
chaosPool (export and live surface alike), Quantize.metal
aerialPreview (16-texel block pool in-kernel). comp() survives as the §3 map (DY3) but no longer
routes assignment. ANE DyadAssign untouched. Device pass owed.

## UI (SIMPLICITY DECREE, 2026-08-09)

★ THE SURFACE MACHINE (Daniel's ruling, 2026-08-12: "the app should
be made of a strict grid; squares make words; the grid is a state
machine that surfaces what the app is doing — including after
capture"): spec/ui/SurfaceMachine.hs SM1–SM5 green (suite 44) →
Tesseract/UI/SurfaceMachine.swift. Six states, one square-word each:
WAKING → WATCHING → WEAVING → SOLVING → SEALED (+ REFUSED with the
ruled two-register headlines). Laws: SM2 the capture arc admits no
skips (after the shutter the grid MUST surface the solve — SOLVING
shows the palette being born); SM3 exactly {WEAVING, SOLVING} refuse
interruption (ContentView.modeSwitchAllowed now reads the machine);
SM4 terminals = the hardware refusals only, everything else reaches
WATCHING; SM5 one scene per state. ContentView error headlines,
IdleStateView (WAKING), RecordingStateView (WEAVING + time), and
ProcessingStateView (SOLVING) all speak the machine's words.
SurfaceMachineTests adds the strict-grid teeth: every spoken word is
rasterized by CellText at its real register and must FIT its
GridRegion — exact ink, no estimates. One machine serves LIVE and
FACE (FaceCaptureState maps case for case).

Launch = loading screen until the first preview frame, then ONE
surface: preview + record + SET. All choices live in the settings
cover (CAMERA live/face, BLEED, MIRROR — persisted via
ExportSettings; the LOOK radio was deleted 2026-08-12 with the
per-frame-palette decree). No mode chrome, no menus.

EXCISED 2026-08-10 (submission cleanup): the A/B dual-explore /
compose / refine arc, MAP-Elites gallery, gene NN (GeneNN/GeneModule/
GeneTrainer/SobolExplorer/Gene.metal, MLX-gated code that never
compiled), VoxelCube/CubeAnimator/GIFStats, BlockPyramid/Decision/
ResidualPipeline/EntropyMeasure, channel-preview thumbs, and the
dormant GPU quantize path (MetalPipeline.processFrame +
quantizeWithDepth — the raw-meters landmine; Quantize.metal is
downsample-only now). CameraState is the simple arc: idle →
previewing → recording → processing → done | error.

BUTTONS UPSCALED 2026-08-10 (form follows function: the atom IS the
GIF pixel; growth = MORE atoms, never a bigger atom): shutter 18→22
cells (88 pt), action rows 11→13 cells (52 pt,
TesseractLattice.buttonRowCells), settings/result/error buttons
widened. SECOND PASS same day: the whole TypeRows registry grew
(micro 4 / label 7 / body 9 / counter 11 / display 16 cells — 8 to
32 pt glyphs). Lattice laws gate in CI (LatticeLawTests).

2026-08-10 EVENING BATCH (Daniel's rulings):
- BINOMIAL BACKGROUND (spec DyadPalette §6 v4, DY6 farLaw/farSpread):
  far pixels take the σ-mirror of their OWN nearest primary — the
  background occupies the mirrored binomial shells; the solid
  comp(centroid) fill is dead. Known blemish: chroma seam at
  t = 31/32 (band pulled, far raw) — dissolves under the AERIAL
  MIRROR LAW, see docs/depth-color-scales.md.
- PREVIEW/EXPORT UNIFICATION v1 (was DyadPreview.swift; SUPERSEDED
  and DELETED by EM13, see ★THE PREVIEW IS THE GIF above): the
  cadence it established survives — assignment at 20 Hz on 64²,
  mixture/stats/derived-α/table at the 5 Hz rung-16 cadence (TL8/9).
- PALETTE-CREATION VISIBILITY: DyadPipeline.process(onFrameTable:) →
  liveTable on both managers → CellPalette swatch (16×16 entries) in
  the processing scene. CellPalette is a Cells primitive.
- GIF LIBRARY (GIFLibrary.swift + Views/LibraryView.swift, scene
  "library"): every successful export auto-archives to
  Documents/Library; settings cover → LIBRARY → 3×3 still tiles,
  detail = playing GIF + 256-entry palette (GCT) + DYAD MIXTURE
  provenance + SHARE/DELETE. No sidecar DB — the GIF is
  self-describing.
- AERIAL MIRROR LAW (docs/depth-color-scales.md): σ(s)·γ(s) =
  σ_base(K), γ = 1/(2−s) — chroma buys the temporal octave. SPEC
  (DY9–DY12, DM11/DM12) AND SWIFT+METAL PORT DONE (Daniel's go,
  2026-08-10 late, comp-halo default): DyadPipeline γ-stages every
  pixel + stats-on-ŷ (no band pull, no t=31/32 seam; ANE untouched);
  DepthMixture.fitLifted (τ-lift); the live surface = τ-lifted
  rung-16 fit + γ-staged assignment, FACE unified (CPU); Metal aerialPreview
  kernel = the 20 Hz GPU assignment twin (meters→signal in-kernel,
  anchors from DepthSignal; optional state, CPU fallback). OPEN:
  ruling R4 (comp-halo vs faithful-hue — DY11 measured faithful as
  aggregate-closer to ŷ; localized swap when ruled), R5
  (PerfectQuantizer naked constants), R6 (γ vs chroma-gain slots),
  workflow steps 4/5/8/9/10 (Mac census, synthetic harness,
  mirror-histogram provenance, byte gate, device pass).

## Build

- `xcodegen generate` then build scheme `Tesseract` (project not checked in).
- Signing on this Mac: team `9WANULVN2G` (cached wildcard profile signs
  offline; QFTX3897B7 has NO account here). `GENERATE_INFOPLIST_FILE: YES`
  is load-bearing.
- Camera code is COMPILE-ONLY off-device (simulator has no camera). Pure
  logic suites run on simulator: FaceMeshSignal, GIFUpscale,
  DyadGIFContract, MixtureStability, SKGene.
- Submission (2026-08-10): PrivacyInfo.xcprivacy declares the
  required-reason APIs (UserDefaults → CA92.1; the only covered API in
  use) — ITMS-91053 closed. TrueDepth has NO capability key: the
  runtime NO-TRUEDEPTH gate is the ship mechanism (terminal error
  state, no dead RETRY). The 4 latent AxiomTests failures are fixed
  (PQ5 re-pinned to the round+F-S law; Dissonance seam fixture used a
  zero-mass far half).
- Known open items: first on-device FACE run (mirroring unverified);
  DEBUG `FRONT-RAW PROBE` log line answers whether this device exposes
  any front RAW to third-party apps.
