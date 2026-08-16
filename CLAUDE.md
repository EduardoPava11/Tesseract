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
EditMachine `.refused(.noCenterStage)` "NO CENTER STAGE", a
TERMINAL hardware refusal (EM7, formerly SM4; spec + Swift + tests
all carry it).
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

## ★ DIRECTORY: a file's job is its address (P5 2026-08-14, COMPLETED
## the same day under Daniel's memory-management ruling)

`Tesseract/Tesseract/` held 28 files and 7,700 lines with no organising
idea. The first pass gave the engine ATLAS-category names. The second
pass finished the job, because THREE organising ideas were still
fighting in one tree: ATLAS jobs (Signal/Solve/Learn/Weave/Edit/Meter),
Apple technologies (Metal/, ML/) and MVC leftovers (Model/, Views/,
UI/, App/). A file's address named its job in six directories of
thirteen. It now does in all ten:

  Sense/    the sensor and the frame off it (CameraManager,
            FaceCaptureManager, FrameBuffer, CapturedFrame,
            QuantizedImage)                          [was Camera/]
  Signal/   the three parallel reads (OctaveRead, FeedFormat,
            TriScaleLadder, ResolutionGate, DepthSignal,
            FaceMeshSignal, MetalPipeline)
  Solve/    palette and assignment (DyadPipeline, DyadPalette,
            PairTree, StrataDescent, DyadANE, PerfectQuantizer,
            TesseractPalette, BinomialCadence, Quantize.metal)
  Learn/    the one model line + every mlpackage (JepaHHead, SKGene,
            ANELoop, ANELoop.metal, ML/)
  Store/    ★ NEW — everything that OUTLIVES the function that made it
  Edit/     what re-editing does with what Store kept (Reweave,
            DepthMixture)
  Weave/    the artifact (GIFEncoder, GIFSaver, GIFMachine)
  Meter/    measurement only, no byte depends on these (AdditiveCensus,
            PhaseTelemetry, DyadEnergy, DyadHarmony, Dissonance,
            BirkhoffMeasure, PhaseTiling, GoBoard)
  Law/      the coordinate system nothing else may change (Axes,
            TesseractCoord)                          [was Model/]
  Surface/  the app's face: App/, Cells/, Lattice/, Scenes/, Widgets/,
            EditMachine                       [was App/ + UI/ + Views/]

★ WHY Store/ EXISTS, AND WHY IT IS THE POINT. Persistence was spread
across three directories that did not know about each other:
CubeStore in Edit/, GIFLibrary in Weave/, ArrangementStore in
UI/Widgets/, plus ExportSettings buried at the top of GIFMachine.swift.
No reader could see the whole memory bill from any one place, and
UserDefaults is the ONLY required-reason API this app declares
(PrivacyInfo, CA92.1) — a declaration that is auditable exactly when
every writer of it shares an address. Store/ now holds all four, plus
CaptureTensor and TensorANE.

Metal/ and ML/ were TECHNOLOGIES, not jobs: a .metal file belongs with
the law it implements, and an mlpackage with the model line that loads
it. Model/ held two coordinate laws and one meter under an MVC name
that means nothing here.

scripts/lint-grid.sh moved with the tree, and one invariant got
STRONGER by the move: the primitive drawing-vocabulary allowlist used
to be a hand-kept name list that included one file from a different
directory (Views/GIFPlayerView). It is now `Surface/Cells/` — the
allowlist IS a directory, so it cannot drift from itself. The set is
unchanged. project.yml globs the tree, so none of this cost a build
change. DepthMixture stays in Edit/ per the ruling that the depth
analysis belongs to the edit phase; its CALL SITE has still not moved
(P2, still owed).

## ★ THE CAPTURE TENSOR (Daniel's specification, 2026-08-14)

"16x16 is a unit. we take a measurement every 5fps. to make
16x16 == 256 centroids ... 4(64x64)==2(32x32)==1(16x16) ... What we
capture should be a proprietary tensor, the shape is the form, the
function is the app's sole purpose."

Spec `spec/output/CaptureTensor.hs`, CT1 to CT11, in the CORE suite.

★ ITS SCOPE IS NARROW, AND THAT IS THE POINT. The file owns ONLY the
retained bytes and the arithmetic that decodes them. Three specs already
own the ladder and it cites them rather than re-deriving them:
Octave.hs (OV1-OV13) owns THE THREE PARALLEL READS, FeedCompression.hs
(FC1-FC10) owns THE WIRE FORMAT including the 73/64 pyramid tax, and
OctaveCodec.hs (CX1-CX7) owns THE CODEC. An earlier draft restated all
of that as its own axioms, which is the schism this project retires
specs for.

★ THE SPLIT (Daniel's ruling, 2026-08-14). Free signs contradict OV5,
CX1, CX2 and CX3, all green. Rather than pick a winner Daniel split the
objects, because they ARE two objects:
  the reads and the codec   mean invariance EXACT, for any g. The
                            octave dials stay provably safe: no setting
                            moves exposure, white point or cast.
  the stored tensor         one FREE sign bit per child, ruled on
                            measured evidence (about a third sharper,
                            4.2 output levels against 6.1). It never
                            claims CX1.
  the declared price        a GIF made live and the same GIF remade
                            from the tensor differ, bounded by g (CT11).
Octave.hs carries a scope note at OV5 so the split is visible from
both sides. The wired codec costs ZERO sign bits (a child derives its
signs from its position) but expresses only separable variation; the
stored form pays one bit per child to express what the wiring cannot.
Neither dominates, which is why this is a ruling and not a dodge.
THE RUNGS ARE PARALLEL VIEWS, NOT A NEST (Octave.hs OV13). Daniel rejected the
nested descent explicitly: "16x16 rung check, 32x32 rung check, but
64x64 is using those two?! NO!"

  rung 16   16 frames of 16x16 =   4096 cells    5 fps
  rung 32   32 frames of 32x32 =  32768 cells   10 fps
  rung 64   64 frames of 64x64 = 262144 cells   20 fps

One coarse tick is 256 cells, which IS the palette: 256 centroids.
Cells stand 1 : 8 : 64, so EQUIVALENT FLOAT RESOLUTION IS FORCED at
64 : 8 : 1 and every rung carries the same 262144 bits (CT2). Side and
rate halve together (FeedCompression.hs FC1, FC2).

THE OCTAVE FORM: fine rungs are ONE SIGN BIT per child,
child = parent + sign*g. Measured: one bit beat FOUR flat bits (0.01655
against 0.02043) at a quarter of the cost. Signs are FREE, not balanced,
ruled on measured evidence (about a third sharper). The price is that
the detail dial also slides the colour, linearly, up to 3.36 output
levels at maximum dial. CT5 bounds it exactly rather than leaving it to
be discovered.

★ ZEROTREES (ruled 2026-08-14 after the literature pass; EZW 1993 /
SPIHT 1996 solved this and the app was not using it). A parent emits
ONE significance bit; quiet parents stop there and their children
decode as the parent exactly (g = 0, CT9, so no second reconstruction
path). A zerotree ROOT at rung 16 terminates 8 + 64 descendants with
that single symbol. MEASURED, 95.3% of subtrees are quiet:

  flat, one bit per child       262144 b   rmse 0.01655
  significance, one level        45064 b   rmse 0.01793   -82.81%
  full zerotree, 16 kills 32+64   30232 b   rmse 0.02409   -89.75%

The significance THRESHOLD IS DERIVED, never chosen (CT7): the
crossover of a two-phase mixture on the capture's own subtree
deviations, the same mechanism ruled for the rung-64 override. A
single-phase capture has no quiet phase and pays flat.

★ g READS THE PARENT AND THE PREVIOUS TICK (CT10). This is DHVC 2.0's
conditioning (lower-scale spatial reference plus same-scale temporal
reference), and the 5/10/20 fps rungs already provide the temporal half.
g stays a PARAMETER: every law holds for any g, so training cannot
reopen one. Trained in nn/jepa under a straight-through estimator.

★ THE REDUNDANCY IS KEPT, DECLARED AND BOUGHT (FeedCompression.hs FC4,
which states the pyramid tax as exactly 73/64). The stack holds
8/7 of the fine rung's cells. A critically sampled wavelet would carry
the same information with none, and that is exactly why the app cannot
use one: in this pyramid each level downsamples only the low-pass
channel, so THE COARSE LEVEL IS A PICTURE. That is the only reason
16x16 can BE the 256 centroids. Under a wavelet it is a frequency band
and cannot be a palette at all. Daniel: "redundancy is good for
engineering."

DEPTH IS NEVER QUANTISED (CT6). It decides figure from ground and sets
the cadence. Consequence, stated because it is large: depth at full
precision on all three rungs is 1168 KiB against colour's 288 KiB, so
depth is 80% of the tensor and the whole thing is 1456 KiB against
CubeStore's 1792 KiB. NOTE: kappa is exact, so the coarse depth rungs
are a pure function of the fine one; storing all three is storing the
same numbers three times, and deriving them is lossless.

The tensor REPLACES CubeStore by ruling. ★ THE SWIFT PORT LANDED
2026-08-14 (Store/CaptureTensor.swift + Store/TensorANE.swift, gated
by CaptureTensorTests + TensorANEParityTests, 11 tests green). See
★ THE ANE ENCODES below. The remaining step is the CALL-SITE swap,
which is staged behind CR3: identity re-weave must reproduce the
archived GIF byte for byte from the TENSOR before anything stops
writing the cube.

## ★ THE ANE ENCODES AND COMPRESSES THE SIGNAL (Daniel's ask,
## 2026-08-14: "I need ANE to be able to encode+compress the signal
## information")

Spec `spec/neural/TensorEncoder.hs`, TA1-TA9, in the CORE suite. It
owns ONE question — what may run on the engine without changing a
stored bit — and cites Octave/FeedCompression/OctaveCodec/CaptureTensor
for everything else. Lab: `nn/tensor-codec/build_model.py` builds
`TensorEncode.mlpackage` and gates it against a float64 NumPy
reference. Ports: Store/CaptureTensor.swift is the CPU law,
Store/TensorANE.swift is the engine TWIN.

★ TA1 IS WHY THIS FITS THE ENGINE AT ALL. The 2x2x2 spacetime pool
FACTORS into a temporal pair-average and a spatial 2x2 average, and
the two COMMUTE. Fold frame pairs into the channel axis and the
temporal half is a 1x1 CONVOLUTION; the spatial half is a stock
avg_pool. So the octave transform needs NO 3D operator (the thing the
engine schedules worst) and is built from the two operators it is best
at. The whole encode is: pool, pool, upsample, subtract, compare,
abs, pool. One dispatch, 0.9 ms on M3 Max; the A19 figure is owed.

★ TA3 IS THE LOAD-BEARING LAW, and it is the encoder's XP2. The
graph's only decision is a sign, and a FLIPPED sign costs exactly
2*min(|r|, g) of extra reconstruction error — NOT 2g. A flip can only
happen where |r| is under fp16's resolution, so the penalty is bounded
by twice that. MEASURED, twice: the authoring gate saw 98.30% of
786432 signs agree with the worst disagreeing |r| at 4.853e-4 against
an fp16 ulp of 4.883e-4, and TensorANEParityTests saw 97.14% agree
with the worst at 4.389e-4. EVERY disagreement is a residual the
engine could not see.

★ TA5: fp16 IS FREE AT THE RUNG THAT IS THE PALETTE. CT2 forces 64
bits per rung-16 cell; three fp16 channels spend 48. The engine's
native precision costs the coarse picture nothing, because it fits
inside an allocation the counting had already forced.

★ THE FORMAT STORES g RATHER THAN PREDICTING IT (Store/CaptureTensor
.swift). CT4 leaves g a parameter and CT10 describes a predictor for
it, trained in nn/jepa. Storing the subtree's OWN measured deviation
costs 4 B per loud root and buys two things worth more: the decode
needs no trained weights, so a tensor retained today stays decodable
after any retrain; and no naked k and j enter the app while the
predictor does not exist. A trained predictor is format v2, never a
second runtime path.

MEASURED SIZE (CaptureTensorTests, on the synthetic figure-over-ground
fixture): 1,099,586 B against CubeStore's 1,835,024 B, rmse 0.0060.
Colour went from 786432 B of voxel bytes to about 31000-137000
depending on the mixture's verdict.

★ AND THE FINDING THAT NEEDS A RULING. The zerotree's saving depends
entirely on the capture having a genuinely QUIET phase, and a sensor
noise floor destroys that phase. Measured (nn/tensor-codec/
noise_floor.py) on the same cube:

  noiseless           mixture finds two phases, 24.9% loud, 14.7 : 1
  noise floor 0.0015  mixture finds ONE phase -> CT7 says pay flat

CT7 is not wrong: it asks "are there two populations of deviation
magnitude", and under noise there genuinely are not. But the question
that decides whether a sign is worth a bit is "is this subtree louder
than noise alone". The candidate is Donoho-Johnstone (1994) MAD
thresholding, which is derived exactly the way the crossover is
(sigma = MAD/0.6745 is a Gaussian identity, not a tuning). Measured,
it kills 27.9% of subtrees for +0.9% rmse. NOT TAKEN — which question
the significance bit asks is Daniel's ruling, and the 95.3%-quiet
figure the zerotree was ruled on now looks optimistic for any capture
with real sensor noise.

## ★ S8: THE RUNGS WRITE THE INDEX (Daniel's ruling, 2026-08-14)

"All rungs require a meaningful additive to the creation of GIFs", and
"read the incoming information in 16x16, 32x32 and 64x64 so that we can
lift a coarse intuition into the final 64x64x64 voxel creation."

`Tesseract/Tesseract/StrataDescent.swift` is the port of
spec/output/AdditiveLadder.hs (AD1-AD12). The rungs now READ the
incoming staged signal and each WRITES its own bits of every index:

  bit 7    ROLE     figure/σ    depth, via the Bayer coverage (AD7)
  bit 6    rung 16³ 4-level     committed once per 4×4×4 spacetime block
  bits 5-3 rung 32³ 32-level    committed once per 2×2×2 block
  bits 2-0 rung 64³ 256-level   the exact leaf, per voxel

Commitments use LOOKAHEAD, not the nearest node mean. That is
nn/descent's finding spent: greedy measured 0.8601 leaf agreement at 8×
the excess distortion, lookahead-L2 measured 0.9652 (DL7 dominance),
and DL6 says the level below a good commitment is exact.

The tree was already this shape, which is why this is a port and not a
design: PairTree's 7 generations with first generation = MSB, PT5's
prefix law, DL1's fan-outs [2, 8, 8], and `nodes16` IS the depth-4
layer. 2 × 8 × 8 = 128.

FASTER, not a cost paid for structure: the fine search is 8 candidates
instead of 128, so whole-cube distance evaluations drop from about
33.5M to about 4.5M.

GATE: `StrataDescentTests` measures conformance with AdditiveCensus
(the spec's own meter) at 1.0 on every stratum, against ~0 at rungs 16
and 32 for the free search it replaces.

★ OWED, three items, all named in the code that owes them:
1. **The live surface still runs the old free search**
   (DyadPipeline.swift, in `Live.assign`). The app therefore holds TWO
   assignment laws right now, which contradicts EM13. The close fits
   the existing cadence: commit the half and node at the 5 Hz coarse
   solve, carry them on FrameSolve, run only stage C per frame at
   20 Hz. Quantize.metal's aerialPreview needs the same two buffers.
2. **DyadANE's fused graph implements the superseded free argmin**, so
   it is no longer this law's twin and the export does not consult it.
   Rebuilding it for the descent is nn/dyad-assign work.
3. **Conformance is 1.0 only on ROLE-PURE blocks.** AD3 notes the role
   bit was "lifted out of its pair", so the additive law wants σ to set
   bit 7 and SHARE the colour bits, while the shipped involution sets
   σ = 255 − j and complements all eight (DY2/PT6, locked by
   DyadGIFContractTests). A mixed block therefore carries bit 6 in both
   polarities. Reaching exactly 1.0 means relabelling the σ half from
   T[255−j] to T[128+j]. That is a palette PERMUTATION, free in LZW and
   visually identical, but it changes a decreed byte contract and needs
   Daniel's ruling. NOT taken unilaterally.

## ★ NO STUBS, NO FALLBACKS (Daniel's decree, 2026-08-14)

"I HATE stubs and I HATE fallbacks. Stubs are unfinished work and
fallbacks are technical debt made useful."

This is an identity decree, not a style note. It is the general form of
a rule this app already lives by in one place: a capture that cannot run
DYAD **exports nothing**, surfaced as `encodeFailedMessage`, never a
silent global-table downgrade. Generalize that everywhere.

**A stub is unfinished work wearing a finished face.** No TODO, no
FIXME, no placeholder return, no function that answers plausibly while
doing nothing. If a thing is not built, the app SAYS so. `Reweave` is
the pattern to copy: an unimplemented edit returns a REFUSAL with a
reason, because a dial that silently does nothing is worse than a dial
that says "not yet". A refusal is finished work. A stub is not.

**A fallback is two answers to one question, and the app picking one
behind your back.** The failure is not the second path. The failure is
the SILENCE: a fallback converts a bug into a permanent, invisible
performance or quality loss, and nothing ever fails, so nothing ever
gets fixed. Three things are NOT fallbacks and keep their place:

1. **A twin.** One law, two engines, and a parity test proving they
   agree. `DyadANE` and the CPU search are twins, gated by
   `DyadANEParityTests`. Call it a twin. A twin without a live parity
   gate is just a fallback that has not been caught yet.
2. **A branch of the law.** When the law itself has cases, both cases
   are the law. The single-phase BIC path is not a degraded two-phase
   path, it is what the mixture verdict MEANS (PP8's two-path law).
   Name it a prior, a case, a verdict. Never a fallback.
3. **A refusal.** Terminal, visible, with a reason, and no silent
   substitute behind it.

**Anything else is debt.** In particular: a `guard ... else { return
nil }` that lumps "this hardware lacks the engine" together with "the
caller passed me the wrong shape" is a bug-hider. Split it. Platform
absence is a fact about the device. A malformed argument is a defect,
and defects must trap in DEBUG rather than route quietly to a slower
path forever.

**A telemetry-only rung is a stub too.** Computing the 16³ and 32³
towers on every capture and then throwing them away is unfinished work,
which is exactly what AD10 says: ★ NO RUNG IS SILENT. That stub is now
closed on the export path; see ★S8 below.

ENFORCED AT BUILD TIME by `scripts/lint-grid.sh`: LINT-NO-STUB bans the
stub markers outright, and LINT-NO-FALLBACK bans the WORD in app source.
If a path is lawful, name it for what it is (twin, prior, verdict,
platform path, refusal). If you genuinely need the word, the escape
hatch is an explicit `// LINT-ALLOW-FALLBACK: <reason>` on the line,
which makes every instance a decision someone signed.

## Architecture

★ THE ATLAS (2026-08-13): `docs/ATLAS.md` is the full stage map — all 101
canonical stages on a MOVEMENT × CATEGORY coordinate (movement = which
EditMachine word is being spoken when the stage runs; category = SENSE /
SIGNAL / SOLVE / LEARN / WEAVE / SURFACE / METER / LAW). `docs/ATLAS-TUNABLES.md`
catalogues all 447 frozen choices with anchors. Read the atlas before adding a
stage, and give the new stage a name and a coordinate in it. §7 holds the
ruled next direction (THE OCTAVE — κ/σ over the 64³ spacetime cube; promote
RUNGING from METER to SIGNAL first, dial last).

Haskell is authoritative; Swift/Metal are ports (SixFour discipline).
- `spec/` — runghc axiom suite: `cd spec && make test` (59 files green
  as of 2026-08-14, verified by a full run — newest are
  ★AdditiveLadder.hs (AD1–AD10, Daniel's ruling "all rungs require a
  meaningful additive to the creation of GIFs": index = role·128 +
  r16·64 + r32·8 + r64, the three views are three STRATA of one index;
  balanced occupancy = 1024 voxels/class at EVERY rung; the role bit is
  DERIVED from the Bayer coverage code, 17 tile patterns not 2^16;
  budget 905574 b vs 2097152 flat = 2.316:1; AD10 no rung is telemetry),
  WeaveState.hs (WS1–WS10, the causal
  33-number state the capture-assist model may read: rung ladder
  1/4/16, 256! relabelings free in energy AND in LZW bits, the
  64-element orientation group, +31.25% for all three rungs) and
  TilingEntropy.hs, TE1–TE10: the
  energy of 256 colors on the 64×64 in BITS, E = N·log₂K − N·H₀, whose
  ground state is every color exactly 16× and is therefore surjective
  for free; the EDIT-APP arc added RoleAllocation.hs,
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
  Tesseract/Tesseract/TriScaleLadder.swift, 2026-08-10): SixFour's color-head
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
- `isp-spec/` moved to the `archive/isp-spec` branch (2026-08-14) and is
  gone from main. It was the deprecated rear-camera cabal ISP spec with no
  living Swift port here. Rear work now lives entirely on archive branches:
  `archive/isp-spec`, `archive/rear-rgbt`, `archive/dng-mode-v2`.
- `nn/` — Mac-side lab: MLX-trained 5,616-param residual debayer
  (`nn/debayer/`, +3.72 dB over bilinear) and its Metal parity harness
  (`nn/metal-harness/run.sh`, verified 3e-7 on M3 Max). Runs on Mac only.

## ★ THE COLOUR LATENT: the space the model is a map OF (Daniel's
## direction, 2026-08-14: "the model we train MUST be wise in the
## 64x64x64 GIF creation, because 256 colour every 64 frames is
## something that CAN be explored in latent colour space")

Spec `spec/neural/ColourLatent.hs`, CL1-CL8, in the CORE suite.

★ THE SPACE ALREADY EXISTS AND IS ALREADY EXACT. This is a fact about
the shipped app, not a proposal. A Tesseract GIF's colour is 64 frames
x 256 entries x 3 = 49152 bytes, and ALL of it is generated by 13
numbers per frame (DYAD STATS v3) = 832 numbers, through a decoder
that already ships and is already gated byte-for-byte
(GIFMachine.rebuildTables). 59 : 1, exact (CL1).

So the model does NOT need to learn a colour space. Consequences,
each a green axiom:

  CL2  the decoder is TOTAL — every point in the space decodes to a
       lawful table, including degenerate ones. The model cannot
       reach an illegal artifact because there is no illegal point.
  CL3  the sigma form survives decode entry by entry, so the latent
       cannot express a table that violates the decreed involution.
  CL4  the lawful relabelings are the XOR-by-mask permutations, which
       COMMUTE with sigma(i) = i xor 255 exactly. |G| = 256, not 256!
       — the decree removes most of WS's freedom. A model that
       distinguishes these is reading index labels, not colour.
  CL5  a relabeling moves no colour: E, occupancy and the LZW bill
       are invariant, checked on the table itself.
  CL6  ★ THE ONE THING MISSING. Euclidean distance in the 13 numbers
       is NOT colour distance, and no fixed reweighting fixes it: the
       ratio between a mean step and a variance step CHANGES with
       position (1.9 at one covariance, 0.8 at ten times it). A
       single diagonal metric cannot be right in both places, so the
       metric must be learned as a FIELD over the space.
  CL7  the hierarchy's depth is forced at three by AdditiveLadder's
       strata [4, 32, 256]. Not a hyperparameter.
  CL8  a sampler that draws in this space and decodes through the
       shipped law satisfies NO-CAPTURE-TRAINING and the
       model-placement ruling by CONSTRUCTION, not by discipline.

★ THE CONSEQUENCE FOR TRAINING. The run this architecture needs is a
METRIC LEARNER, not a generator — the generator already ships. That is
a far better-posed problem than "train a model on GIFs", and it is
what docs/model-placement.md § 4.1's open CHOICE (fitted vs learned)
was really asking. Corpus emission and the run itself are NOT done.

## ★ THE LOOP HAS AN ENERGY (Daniel's four rulings, 2026-08-15)

Daniel: "because the model can only understand GIF's, in terms of
color space we need it to be able to categorize the 256 colors times
64 frames in terms of deltas, GIF loops and dithering. ENERGY! H-JEPA
with synthetic data... When we capture the ANE is used to funnel the
scales and create the 'view', it is OK if the preview and capture
deviate since the capture data is more! it is more information than
one single GIF, hence why we edit"

Four rulings followed a full-tree read. Two are EXECUTED, two are OPEN.

★ R-A. THE VALUE HEAD GETS A TEMPORAL BOND, ON THE CLOSED LOOP.
EXECUTED. spec/statistics/TilingEntropy.hs gains TE11 to TE15 and
Tesseract/Meter/TilingEnergy.swift is the port, gated by
TilingEnergyTests (20 tests). E_time = B_t(1 - h(w_t)) over the cyclic
bonds (p,t) ~ (p,t+1 mod nf); B_t = nf*4096 = 262144 at 64 ticks, and
the last bond IS the 63 to 0 one. It is the SAME law as E_wall over a
different set of adjacent pairs, so no new constant enters.

  WHY IT WAS NEEDED. E pools the histogram over all frames and E_wall
  sums disjoint per-frame bond sets, so BOTH are symmetric in the 64
  frames: the app's only closed-form quality measure scored a GIF and
  its SHUFFLE identically (TE13 now states this as the thing that
  changed). It could not see a delta or a loop at all.

  AND IT IS THE MISSING HALF OF DEPTH. Depth is 57% of the retained
  capture and reaches the artifact as ONE BIT per voxel, the role bit
  (AD7). E_wall reads where that bit changes across the plane; nothing
  read where it changes along the loop, which is depth's motion.

  Ceilings, 64 ticks: index 2097152 b, spatial 516096 b, temporal
  262144 b. TE15: the three strata are disjoint and all in bits, so
  summing is LAWFUL; the app keeps them separate anyway because the
  ruling asked for the artifact to be categorized BY deltas and a sum
  discards exactly that. `CubeValue.bondEnergy` offers the one sum the
  law licenses (the two bond strata) and no other.

★ R-B. RULING 7 ANSWERED: A ROTATION OF Z/64 IS AN EQUIVALENCE.
EXECUTED as a THEOREM, not an assumption (TE12): a cyclic bond set is
carried to itself by a rotation, so w_t cannot move. Open since
2026-08-14 in docs/workflow-2026-08-14-sk-energy-registry.md section 7.

  ★ THE STATEMENT NEEDED PRECISION AND THE FIRST DRAFT FAILED. As
  exact equality of the three ENERGIES the axiom is FALSE: cWall sums
  16 Doubles and a rotation REASSOCIATES that sum. The invariance is
  EXACT on every integer observable (pooled histogram, wall multiset,
  w_t) and holds to reassociation noise on the floats. The theorem
  lives in the combinatorics; the last ulp is an artifact of adding in
  an order. Both halves are gated, in Haskell and in Swift.

  ★ OWED, AND IT IS BYTE-CHANGING: the shipped encoder is NOT rotation
  equivariant, which is now a measurable defect rather than a habit.
  The stats EMA seeds at tick 0 (DyadPipeline.swift:413-431), so tick
  0 takes raw statistics while tick 63 is fully smoothed; StrataDescent
  partitions time linearly with no `mod`; S4's chaos groups have
  "lawful degenerate" tails, and a tail cannot exist on a torus. The
  meter obeys the ruling today. The encoder owes it, and closing it
  changes exported bytes, so it needs its own pass.

★ R-C. CR3 IS SCOPED TO THE PICTURE. EXECUTED (comments and one test
name; the assertions never changed because they were already right).
`reweave(cube, .identity)` must reproduce INDEX FRAMES AND PALETTE
TABLES exactly. Frame-derived provenance may differ.

  The old "byte for byte" wording was false on the day it was written:
  the capture path calls `makeGIF(frames:)` and emits PHASE F and
  SK GENES; the re-weave path reaches `finish(..., frames: [])`, so
  those sections are STRUCTURALLY ABSENT. Reconstructing them needs
  the tensor to decode to rawRGB exactly, which CT11 declares it does
  not, so the strict reading permanently blocked the tensor from
  replacing the cube. ★ THIS UNBLOCKS THE CaptureTensor CALL-SITE
  SWAP, which was staged behind CR3 and nothing else.

★ R-D. THE MODEL IS HIERARCHICAL: 64 IN, 16 AND 4 INSIDE. OPEN, not
started. Input = what the GIF actually carries, 64 slots x 14 numbers
+ 2 bits (DYAD STATS v3 + GROUNDHUE v2, which `rebuildTables` already
decodes losslessly). Internal ladder 64 -> 16 -> 4, which is CL7's
strata [256, 32, 4] and the 64/32/16 rung ladder, both forced. Costs a
retrain and re-derives JH1's "ring = 16" as the MIDDLE level rather
than the input. Note before starting: the deployed head builds 11 dims
(DyadPipeline.swift:752-768) while nn/jepa/train.py:37 says
`RING, DIM = 16, 6`, so it ships running dims it never trained on,
gated by nothing.

★ THE DEVIATION RULING COSTS NOTHING, MEASURED. EM13 is a TAUTOLOGY:
spec/ui/EditMachine.hs:217 defines `encode c r = (c, r)`, the
identity, so `watchPath` and `weavePath` are literally the same
expression and the axiom is true by construction. It gates an
ARCHITECTURAL claim (one encoder, differing only in retention); it
never gated the byte identity its prose asserts. Applying "the preview
and the capture may deviate" changes ZERO green axioms and ZERO tests.

★ THE SURPLUS, MEASURED, because the ruling stands on it. Retained
1835024 B against a 262144 B index plane, 7:1 per voxel. Colour is
786432 -> 278528 (1.5:1, the quantization gap). ★ DEPTH IS 1048576 ->
32768, EXACTLY 32:1: it reaches the artifact as one bit per voxel plus
seven scalars for the whole capture in the DYAD MIXTURE line. Depth's
shape, its motion and its per-frame histogram are 100% surplus, and
depth is 57% of what is kept. Separately: the export TRANSIENTLY holds
about 17 MB of staged OKLab (`stagedLabsAll` + `unstagedLabsAll`,
6291456 B each) that dies when the closure returns, nine times the
retained cube.

★ AND THE FINDING THAT RESHAPES "THE MODEL CAN ONLY UNDERSTAND GIFS":
there is NO LZW DECODER anywhere in the repo. Every LZW in
Tesseract/, spec/ and nn/ is an encoder or a bit-counter, so an
archived GIF's index plane is unreadable by any code that exists. But
the GIF carries its own generator exactly, and `rebuildTables`
(GIFMachine.swift:207) decodes it. A GIF-native model reads the
GENERATOR, not the pixels, and that channel is already in every file
ever exported.

## ★ THE FUNNEL, MEASURED (Daniel's ask, 2026-08-15)

"a series of serious tests. so I know how the information from the
signal gets funneled. For example a raw reading of a series of related
numbers can be summarized into one bigger number. categorize
compression into its components. the function map our axioms and
theorems to test the swift and metal."

`Meter/FunnelLedger.swift` + `FunnelLedgerTests` (11 tests). Full
write-up and every number: `docs/session-2026-08-15-funnel.md`.

RateLadder has said since 2026-08-12 that the content-dependent strata
"declare 1 here, their factors are MEASURED per capture by the RATE
LEDGER". The shipped RATE LEDGER traces five end-to-end numbers and
decomposes NOTHING. The promised factors had never been measured.

★ THE FUNNEL IS A DAG, NOT A CHAIN. The latent forks off the same 64²
colour and rejoins at assignment as the thing indices point INTO.
Three paths, each telescoping exactly (RL2), each with a CONNECTIVITY
check beside it so a product cannot telescope vacuously:

  pixel     144 (discard) x 3 (VQ) x 5.39 (LZW)  = 2328 : 1
  codebook  109.47 (summarize) x 1:6.84 (expand) =   16 : 1
  depth     16 (discard) x 32 (to the role bit)  =  512 : 1

★ FOUR KINDS, BECAUSE A RATIO CANNOT TELL THEM APART. DISCARD (the
output is a MEMBER of the input), SUMMARIZE (a FUNCTION of all of it,
the one Daniel named), RECODE (every sample kept, fewer bits each),
EXPAND (more bits out than in, deterministically).

★ THE APP DISCARDS MORE THAN IT SUMMARIZES. The test was written
asserting the latent was the steepest stratum and FAILED: S2
summarizes at 109.47:1, S0 discards at 144:1. Quantize.metal's
downsampleRGB does ONE texture.read per output pixel, so 143 of 144
samples never reach the answer, with no prefilter. Measured on
Nyquist-pitch stripes the point sample and the box mean it is not
diverge by 127.5 levels of 255 (zero on a constant field, so the
divergence is a property of the SIGNAL). The discarded part is the
part NO EDIT CAN EVER RECOVER.

★ THE CODEBOOK PATH'S NET RATIO IS EXACTLY 16, and it is pinned by a
test: 4096 pixels described by 256 entries is N/K, and N/K = 16 is
TE2's BALANCED OCCUPANCY, the ground state of E. The palette costs one
sixteenth of the pixels it describes because that is what "256 colours
on a 64x64" means read as a rate.

★ THE CODER DECOMPOSES BY IDENTITY, NOT BY FITTING (TE10): plane - E =
the order-0 bill, and what LZW spends below that is what RUNS bought.
On the moving-disc fixture: plane 524288 b, occupancy 211676 b, order-0
bill 312612 b, LZW 97272 b, runs 68.9%. The fixture is smooth and
unusually run-friendly; a real capture moves that number.

## ★ ONE LAW, THREE PORTS: the funnel's entrance (2026-08-15)

`spec/output/FrameGeometry.hs` G11-G13 (NEW) +
`Signal/FrameGeometry.swift` (NEW; the spec had NO Swift port) +
`MetalGeometryParityTests` (NEW; nothing in the suite had ever touched
Metal's downsample path).

★ THE KERNEL'S OWN VERIFICATION CLAIM WAS VACUOUS, and the shape of
the mistake is the lesson. Quantize.metal:188-192 says "Port of
FrameGeometry.hs ... Verified by Haskell axioms G5-G10 for all 4096
output pixels." G5 is bounds, G6 alignment, G7 spacing, and every one
is INVARIANT UNDER A RELABELLING of the output grid. The kernel applies
a 90 degree rotation that the spec's `rgbSource` does not, and those
axioms pass either way. They could not have caught it being wrong. The
rotation lived in the kernel, in a comment, and in no axiom.

  G11  the rotation is a BIJECTION of the output grid, so it moves no
       information whatever else it is
  G12  it has order exactly four
  G13  ★ RGB and depth take the SAME turn. A quarter turn on one
       stream only would read every pixel's depth from the wrong place,
       SILENTLY. This is the axiom G5-G10 could not have provided.

★ HOW THE METAL IS GATED: the test paints each source texel with its
OWN coordinates in rgba32Float, so whatever the kernel writes to output
(i,j) IS the address it read. Exact, all 4096 pixels, no tolerance. A
colour check would have passed for any read inside a smooth region,
which is what the old comment rested on.

★ WHAT IT CANNOT SETTLE, and the test says so: whether the turn should
be counter-clockwise is a fact about pixel memory on a physical iPhone
17. No axiom and no simulator can answer it. The shipped direction is
recorded AS DATA so a device pass has something to contradict, and one
edit now answers it in all three ports.

## ★ NEXT: the categories must fit the 64³ BIN tensor (Daniel, 2026-08-15)

"We have found that there is a relationship between the funnel of
signal to edit. These categories MUST fit the 64x64x64 BIN tensor idea.
so that we can function map to an energy knowledge of a 64x64x64 voxel
mass satisfying the GIF89a format."

NOT STARTED. The pieces all landed today: the CATEGORIES
(`FunnelLedger.Kind`), the ENERGY (`TilingEnergy.CubeValue`, three
disjoint strata in bits), the TENSOR (`Store/CaptureTensor.swift`, call
site unblocked by R-C), the FORMAT (per-frame LCTs, byte-gated).

Four questions the next session must answer, in
docs/session-2026-08-15-funnel.md §5: is a BIN a voxel or a bin OF
voxels; which category does each VOXEL carry (today a category belongs
to a STRATUM, an arrow, not to a voxel, so this wants a per-voxel
provenance field that nothing computes); does the energy become a FIELD
(CL6 concluded the metric must be a field from the other side, and
these may be the same requirement arriving twice); and what GIF89a
actually permits such a field to ride in.

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
cadence the preview already fits at.
"DYAD JEPAH v7" trace line = the attribution; trace rebuild stays
byte-exact (the smoothed numbers ARE the generating state).

★ FLAG CameraConfig.jepaH IS **OFF** (flipped 2026-08-14, Daniel's
ruling, twice over. The reasons are written in full at
CameraManager.swift:145-162, which is the authority):
(1) "follow the scene, match the true motion". New gate B5 measures
the head against TRUTH rather than a baseline: churn 7.921 vs a true
9.592, i.e. it holds the palette 17.4% STEADIER than the scene is,
and sits 2.67× further from truth than the oracle-EMA it replaced.
Every previously-shipped gate passed because every one compared the
model to a BASELINE and none to truth.
(2) "the model should not dictate HOW we capture". Smoothing the
ring before the tables solve is the model deciding bytes at capture
time. That placement is retired; the model's home is the EDIT path
(docs/model-placement.md). Re-enable only after a truth-referenced
retrain AND a placement that reads the state without writing it.

nn/descent is RETIRED as a MODEL PATH, but the lab is still on disk
(corrected 2026-08-15: this line said "lab deleted 2026-08-14" and the
directory is present, with README.md retitled "STUDIED AND
INTEGRATED"; nothing was deleted, and DescentAssign.mlpackage is still
in it). Retired means: do not build on it, do not ship a second
assignment artifact.
DL6/DL7 stay law in spec/neural/DescentLadder.hs; lookahead-L2 belongs
inside DyadAssign if it ever ships, never as a separate artifact.

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

★ THE EDIT MACHINE (Daniel's ruling 2026-08-12 "the app should be
made of a strict grid; squares make words; the grid is a state
machine that surfaces what the app is doing", SUPERSEDED and widened
by the 2026-08-13 decree "EDIT is the whole app"):
spec/ui/EditMachine.hs EM1–EM13 → Tesseract/UI/EditMachine.swift,
gated by EditMachineTests. Capture is an input step, the shelf is
home, one moment yields many GIFs, the full 64³ re-solves EVERY TICK.
One machine serves LIVE and FACE (FaceCaptureState maps case for
case); ContentView error headlines, IdleStateView (WAKING),
RecordingStateView (WEAVING + time) and ProcessingStateView (SOLVING)
speak its words; every spoken word is rasterized by CellText at its
real register and must FIT its GridRegion: exact ink, no estimates.

★ THE SURFACE MACHINE IS RETIRED (spec + Swift + tests all deleted;
git history keeps them). This was a REPLACEMENT, not a widening, and
the reason is forced rather than preferred: the two edge relations
DISAGREE IN DIRECTION on five pairs (waking→watching, solving→sealed,
sealed→watching, exportFailed→watching, unknown→waking) and
EditMachine's laws are EXACT-SET laws, so no union of the two can
satisfy both specs. One word also collides (Refused Unknown speaks
"REFUSED" here, spoke "ERROR" there; EM6 requires distinctness).
SM1 to SM5 are NOT discarded. They are re-proved over the larger
machine: SM1 = EM6, SM2 = EM3, SM4 = EM7, SM5 = the one-scene-per-
state switch in ContentView, and SM3 SPLITS into EM4 (a solve that is
a CAPTURE must complete, the promise that the moment was kept) and
EM5 (a solve that is a TICK must be ABANDONABLE, the promise that
the dial answers). The full derivation lives in the headers of
spec/ui/EditMachine.hs and Tesseract/UI/EditMachine.swift; do not
reintroduce a second surface machine.

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
