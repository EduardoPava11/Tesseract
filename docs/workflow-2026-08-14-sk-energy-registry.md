# TESSERACT: ONE PLAN FOR THE 64³ ENERGY SPACE

## 1. THE ONE IDEA

The energy over the 64³ cube is not missing. Five exact energies are green and calibrated. The operators Daniel named, expansion and contraction, are not missing either: `pool = kappa` and `up = sigma's structural half` are already law in `spec/quantization/Octave.hs`, gated by OV4 and OV12, with SK6 and CX1 proving the retraction twice more. What is missing in all three strands is the same thing, and it is not theory: **CORRESPONDENCE**. The specs do not know which code ports them. The code cannot read the energies at the place where editing happens. And a whole query layer was designed on a seam that was already closed, because nobody greps the registry.

So this session ships correspondence, in both directions, by arithmetic. Spec to port, made machine-checked (the reorganization). Spec to device, made real for the one energy that has no port and the one energy that has no call site (the meters). And it ships a measured refusal of the third strand, so the SK query language is never proposed again.

**The three strands do NOT compose as designed, and saying so is the finding.** The SK query language is not the interface to the energy landscape: measured, its 16,896 size-7 terms denote only 323 distinct event words, folding to 51 distinct rung paths over a 3-rung cursor, with 87.9% of terms ending on the rung they started on and 51.2% never moving the cursor at all. It discriminates terms, not cubes. The MLX model has no well-posed objective: a fixed point of ANELoop's descent on a 4³ block is an element of candidates^64, an unbounded label set, and the descent it would label is gated to far-blocks-only, reached only behind `phaseChaosLoop = false`, and runs a naked `K = 4`. There is no model here to train. The reorganization does compose with the meters, because the same act (declare the port, check it exists, check it cites back) is what makes an unported energy visible as debt on a named directory.

One idea, then: **close the correspondence. No weights.**

## 2. WHAT IS ALREADY TRUE (needs no work)

- **The sigma/kappa seam is already law.** `Octave.hs` documents `pool` as kappa ("the operator TriScaleLadder already runs on every capture") and `up` as "sigma's structural half: replication", with OV4 gating `pool . up = id` over Rationals at the app's real rungs and OV12 gating mean-of-8 equals three nested binary means. SK6 gates `dc (expand0 x) == x` and `ê² = ê`. CX1 is strictly stronger: `kappa(sigma_g(x)) = x` for ANY g. `CaptureTensor.hs` already cites Octave for exactly this ground, including the free-sign non-retraction split (CT1) and its declared cost (CT11). **No axiom is owed. One comment line in `Tesseract/Store/CaptureTensor.swift` naming OV4/OV12/SK6 next to `poolDown`/`parentUp` closes the Swift-side gap, and that is the whole of it.** (Adjudicating the two reviewers: the spec side owns it, the Swift symbol names it nowhere. Both were right about different halves.)
- **F is already computable at edit time.** `PhaseTelemetry.measure` is a pure static function of `(indexFrames, tables, sourceRGB, side)` and exposes `var f { d16 + d32 + d64 }`; CubeStore retains rawRGB and depth under CR1. The claim that F is capture-only was false. Only a call site is missing.
- **E_pal already ships twice**, as `DyadEnergy.palette(table:)` and in the closed 9-number form.
- **H₀ is already computed and traced on every GIF** (`GIFMachine.swift:154`), so TilingEntropy's E is one subtraction.
- **The corpus laws are green and complete**: SV3 (exact 64-periodicity), SV4 (PSD and in gamut), SV6 (byte-identical from seed), SV7 (disjoint held-out ranges), DL5 (labels from exhaustive search only), FC10 (totality), CL8 (lawful by construction). No new corpus law is owed by anyone.
- **SV3 and JH3 do not conflict.** SV3 is a property of the stats sampler's trigonometric synthesis; JH3 is the head's filter algebra with `trajectory1` as a corpus generator. Neither quantifies over "paths". The proposed blocking ruling was manufactured; it is withdrawn.
- **TemporalLoop.hs already owns the loop-seam critique** in prose ("no frame is privileged", frame 63 accumulates everything). It was a registry grep miss.
- **AttractorRAG (AR1 to AR13) already owns codebook retrieval ranked by energy**: AR2 says the retrieval metric IS the energy metric, AR4 says k-NN is monotone, AR10 says the library IS the corpus. That is arithmetic, green, and unported. It is the real home for "query and observe possible paths".
- **The move cannot break a build**: spec/ has zero cross-spec imports (every import is base/containers/array/random/process/directory) and `project.yml` has zero `spec` references.
- The registry is **61 CORE and 74 total**, not 63. Use those numbers.

## 3. THE SPEC FILES TO WRITE

One new file and three amendments. That is all.

**NEW: `spec/Registry.hs`** (base + System.Directory only, run by `make ports`, NOT added to CORE, because it proves nothing about the cube and does directory IO against the working tree).

- **RG0** The principle: a spec's directory is the Tesseract/ directory that ports it; if nothing ports it, the directory that must; tie-break is DEFINER over CONSUMER; `forge/` means the port target is not the app; `deprecated/` means no port is owed, with a reason.
- **RG1** Filesystem/registry bijection: every .hs sits in exactly one Makefile variable whose name, up to a `_EXTRA` or `_GEN` suffix, lowercases to its own directory. (Repaired: the suffix arm is required, or the non-runnable specs make RG1 unsatisfiable on day one.)
- **RG2** Every spec declares its ports in its leading comment run (derived from file structure, not a chosen 40-line window): one or more `-- PORT: <path>` lines, or one `-- PORT: NONE (<TAG>: <reason>)`.
- **RG3** Every declared port exists on disk, **plus a bare-name arm**: any of the 74 spec basenames or any `*.swift` name appearing in a spec or Swift comment must resolve. (Repaired: without the bare-name arm the axiom has no teeth, since zero dangling paths exist today; with it, it fires immediately on `CentroidRefiner` in `Signal/DepthSignal.swift:7` and `docs/REFINE-PASSES.md:122`.)
- **RG4** The declared ports must lie under `Tesseract/` or `nn/`, and the set of jobs they occupy must contain the spec's own job, or the spec carries an OWED line naming its job's owing file. Ports outside the spec's job print as CROSS-CITES, which is accurate, not a defect. (Repaired: the strict mirror test is violated by FrameGeometry, GenIcon and BayerResidual, all correctly placed.)
- **RG5** `PORT: NONE` is a ledger entry, never a failure. Tags: **OWED** (names the file that owes it), **THEORY** (names a docs/ file containing the module name), **GENERATOR** (forge/ only), **PROVEN** (a green law kept because it is true, no port owed). (Repaired: without PROVEN, five files with no port and no doc are forced into OWED and the registry manufactures false debt, whose cheapest exit is a stub.)
- **RG6** A port is a mutual declaration: the named Swift/Metal file cites its spec's path back. Lands as a WARNING for one commit, fatal after, because the tree currently cites specs in four incompatible shapes.
- **RG7** The orphan ratchet: the count of .swift/.metal files under the ten governed directories that no PORT: block names may only decrease. The baseline is machine-written to `spec/ORPHANS.census` by `make orphans` on the move commit. **No number appears in the axiom text.** (Repaired: 30 was asserted, 39 is the measured count of non-citing files, and neither is the census, which is defined against a table that does not exist yet.)
- **RG8** The move is total and injective: 74 to 74, every old path absent, every new path present, and no line anywhere matches a retired layer, scanning `(spec[/ ])?(algebra|quantization|...)/` **plus bare basenames**, over `*.swift *.metal *.hs *.py *.json *.md *.sh` including `README.md` and both `nn/*/corpus/manifest.json`. (Repaired: the prefixed scan misses 12 real references, two of them in JSON consumed by training code.)
- **RG9** DEPRECATED is a real variable with a one-line reason per entry, provably disjoint from CORE.
- **RG10** `scripts/lint-grid.sh:151-159` stops naming four spec files; the clause becomes "every `spec/surface/*.hs` is in SURFACE and satisfies RG2/RG3/RG4/RG6".

**AMENDMENT 1, `spec/neural/ColourLatent.hs`: add CL9, SHIPPED ARITY.** The per-frame generator emits 14 continuous numbers and 2 bits (`capped` and `balanced` are both Bools written as "1"/"0" and parsed as `!= 0`), so a 64-tick path is 896 numbers + 128 bits, 54.86:1, not 960 + 64 at 51.2:1. Also fix: `decode` reads 9 of 15 declared coordinates, so CL2/CL3/CL8 are vacuous in cLA, cLB, cAB, cap, rotA, rotB (six, not four), and the docstring's "832 numbers" contradicts axiom_CL1's 960. Verified independently by two reviewers.

**AMENDMENT 2, `spec/neural/SKGeneSemantics.hs`: add AX9, THE EVENT-WORD QUOTIENT.** The 16,896 size-7 terms denote exactly N distinct event words, pinned as a literal in the file (measured at 323; the implementer recomputes and writes the number the tool prints). This is the sibling of AX4's 2,692 normal-form quotient, and it is the permanent, cheap answer to any future "SK terms as a query alphabet over the cube" proposal.

**AMENDMENT 3, `spec/temporal/MixtureStability.hs`: add MS8, THE LOOP SEAM, MEASURED.** Apply the shipped colour EMA (`DyadPalette.ema` with `DepthMixture.localLevelAlpha`, **not** `filterFits`, which is the depth mixture's filter) to an SV3 trajectory that was exactly 64-periodic before the filter touched it, and report the tick-63 to tick-0 discontinuity in latent units and in decoded ΔE. Exactly zero on a constant path (MS1). Report the number; the axiom is the measurement and its zero case, not a universal positivity claim. **MS8 does not authorize a ring-closed filter** (see Ruling 6).

Everything else proposed in the three designs is dropped: SQ1 to SQ12 in full, QP1 (fabricated operator M "restricted to the palette", attributed to PP1/AL1 which define it on the spacetime error field), QP3/QP4's ring law, QP5 to QP13, the path type, the basin categorizer.

## 4. THE HASKELL REORGANIZATION: FULL MANIFEST

Twelve job directories. `git mv` only in commit A, no content edits.

- **law/ (4):** algebra/Tesseract, quantization/TesseractAxes, quantization/Centers, quantization/TesseractQuantize
- **sense/ (1):** output/FrameGeometry
- **signal/ (7):** quantization/Octave, quantization/ResolutionLadder, output/FeedCompression, output/TriScaleLadder, temporal/DepthSignal, temporal/FaceCadence, temporal/DepthBinomial
- **solve/ (14):** quantization/{PerfectQuantize, DyadPalette, PairTree, GroundHue, WhiteBalance, BellPalette, DitherRamp, CentroidRefine, **PhasePalette**}, temporal/{ContinuousDepthCadence, TemporalBinomial, TemporalLoop}, neural/DescentLadder, output/AdditiveLadder
- **learn/ (7):** neural/{ANELoop, SKGeneCalculus, SKGeneSemantics, OctaveCodec, JepaH, ColourLatent}, algebra/DirectSum
- **store/ (3):** output/CaptureTensor, neural/TensorEncoder, quantization/AttractorRAG
- **edit/ (3):** temporal/DepthMixture, temporal/MixtureStability, quantization/RoleAllocation
- **weave/ (2):** output/ExportMethods, output/RateLadder
- **meter/ (18):** statistics/{PhaseEnergy, PhaseTiling, Dissonance, DeviationManifold, TilingEntropy, BinomialCube, BinomialFix, WassersteinPalette}, quantization/{SpectralPalette, **PairPermutations**}, neural/WeaveState, spatial/{TesseractGo, ColorGraphs}, algebra/TesseractDistances, output/{GIFAnalysis, TemporalSpatialGIF, **BreakInvariants**}, harmony/**SetListDissonance**
- **surface/ (4):** ui/{CellMechanics, EditMachine, WidgetGrid, DetentDial}
- **forge/ (9):** statistics/StatsVariance, neural/BayerResidual, quantization/EmitDyadFixtures, output/{SKCorpusEmit, DescentCorpusEmit, JepaCorpusEmit, GenIcon}, spatial/**SpatialTransport**, output/**RealTesseract**
- **deprecated/ (2):** KataGoClient, SurfaceMachine

Total 74, bijection, every file placed once. Four deviations from Survey C, each ruled: **PhasePalette goes to solve/**, because it DEFINES the objective the palette solver minimises and is cited by `Solve/DyadPalette.swift:149`; filing it at meter/ would put a byte-bearing law in the one directory whose decree is "no byte depends on these". **PairPermutations goes to meter/**, its only port being `Meter/DyadEnergy.swift`. **SetListDissonance goes to meter/**, next to its sibling Dissonance, with the orphan `Meter/DyadHarmony.swift` as a candidate port. **The three deprecation candidates stay at working addresses in commit A** and move to deprecated/ only in commit D, after Ruling 4, because BreakInvariants is CORE and green and deprecating it inside the move makes commit A's gate unachievable.

**The Makefile gets three variable kinds per job**: `<JOB>` (CORE, runs green in CI), `<JOB>_EXTRA` (not runnable in CI, one-line reason), `<JOB>_GEN` (generators, named targets only). This is the repair that makes commit A's gate possible: CORE-by-directory would drag `spatial/ColorGraphs.hs` (does not compile under `-package-env=-`), `output/GIFAnalysis.hs` and `output/TemporalSpatialGIF.hs` (read frames from a path on another machine) into `make test`. With the suffix scheme: METER 14 + METER_EXTRA 4, FORGE 2 (StatsVariance, BayerResidual, both CORE today and both green) + FORGE_GEN 5 + FORGE_EXTRA 2. CORE = 4+1+7+14+7+3+3+2+14+4+2 = **61, unchanged, file for file**.

`make list` prints per-directory counts and the total, so no fourth document can quote the census stale. `spec/README.md` gains a 74-row MOVED table so historical prose stays locatable, and gains the two corrections it owes: CaptureTensor is CT1 to CT11 (not CT15), AdditiveLadder is AD1 to AD12 (not AD10).

## 5. THE PORTS, IN DEPENDENCY ORDER

**P0. Citation normalisation (commit A0).** One shape everywhere: `spec/<layer>/<File>.hs`. Repairs the space-form (`spec output/RateLadder.hs` in `GIFEncoder.swift:176`, `GIFMachine.swift:78,132,144`), the bare-layer form (`quantization/RoleAllocation.hs §3` in `Reweave.swift:5`), the brace lists, and the bare module names. Includes `nn/descent/corpus/manifest.json:10` and `nn/jepa/corpus/manifest.json:8`, which are read by training code, and `docs/ATLAS-TUNABLES.md`, the prose predecessor of this whole registry (98 spec references, and its Swift paths are stale pre-P5: `Tesseract/Tesseract/Camera/CameraManager.swift`). *Gate: the four-form grep returns hits only in canonical form; xcodebuild and XCTest counts unchanged.*

**P1. Commit A, the move.** `git mv` plus the sed, plus the Makefile rewrite. *Gate: record `make test` and the XCTest count BEFORE touching anything; after, `make test` prints 61 passed / 0 failed identical to that baseline; RG8's scan returns zero; `git show --stat A` shows only renames plus hunks containing a retired layer prefix.*

**P2. Commit B, the PORT: ledger and Registry.hs.** **Derive** the PORT: map for the ~25 ported specs mechanically from the normalised Swift citations; hand-author only the `PORT: NONE` ledger for the other ~49, since that is the one fact the Swift side cannot express. *Gate: RG3's bare-name arm must FAIL first on the dead CentroidRefiner reference, then pass once corrected. Watch it fail before it passes; the inert-but-faithful-port trap is on the record.*

**P3. Commit C, the tools.** `make ports` (RG6 as warning for one commit), `make orphans` writing `spec/ORPHANS.census`, `lint-grid.sh` generic surface clause. *Gate: `make ports` fails on RG3/RG4 and never on OWED; lint-grid.sh exits 0 and names no spec filename.*

**P4. `Tesseract/Meter/TilingEnergy.swift`.** E, ε and E_wall from the emitted cube. The cheapest exact energy in the set and the only calibrated one with no port at all. Zero weights. *Gate: XCTest against TilingEntropy.hs's six pinned probes (balanced 0.0, random 194.94, face 4182.21, three-region 17910.68, Néel 28672.0, solid 32768.0) to a tolerance derived by the Higham bound `PhaseTiling.swift:643` already uses; and E == 8N − N·H₀ against GIFMachine's own traced H₀.*

**P5. The edit-time energy call site.** NOT a new meter. Call the existing `PhaseTelemetry.measure` with CubeStore's retained rawRGB, plus `DyadEnergy.palette`, plus P4, and return the **vector** (E_bits, F, E_pal) with a Pareto comparator. No method returns a Double. This is the first time the app's main objective is readable where editing happens. *Gate: on an archived capture whose CR3 identity re-weave passes, F from the retained cube equals F at capture to 1e-9; a lint asserts no call site collapses the triple to a scalar. Blocked on Ruling 8 (the tensor-replaces-CubeStore ruling), because CT11 declares a nonzero divergence and this gate must be CubeStore-era.*

**P6. The `poolDown`/`parentUp` comment.** One line in `Store/CaptureTensor.swift` citing OV4/OV12/SK6/CX1, plus the CT1 qualification that the stored free-sign form is not sigma. Five minutes.

**P7. Commit D, blocked on rulings.** Deprecations, the three splits (SKGeneSemantics, StatsVariance, TemporalLoop), the retire list.

**No Metal work. No ANE work. No new mlpackage.** The only ANE item is the `-- PARITY:` field extension, which exists to make Ruling 1 visible, not to add a graph.

## 6. THE MLX RUN

**There is none, and that is the answer, not a deferral.**

The categorizer as proposed is not well-posed. A fixed point of ANELoop's descent on a 4³ block is an assignment of 64 voxels to per-frame candidate sets, an element of a space of order 2^512, so "a codebook of distinct fixed points" has no closed alphabet and `−E[log p(b*|φ)]` is a categorical head over an unbounded label set. The claim that the Bayes floor is zero is also false: φ was specified as `poolDown`, an 8:1 mean whose complement is SK6's 7-dimensional kernel, so the floor is H(b*|φ) > 0 and unmeasured. And the landscape it would label is not the app's: the shipped descent runs far-blocks-only with everything else frozen to the identity, draws candidates from each block's own top-8 occupancy through four different per-frame palettes, runs a naked `K = 4` with an A-series pin owed, and is reached only via `CameraConfig.phaseChaosLoop`, which is `false`. A majority-class predictor would score well on that gate while carrying zero information.

The gate itself was also inadmissible: `nn/jepa/README.md` says "No other model artifacts" and "Accuracy-vs-teacher is not a promotion criterion for this line", and WS7 says a predictor is scored against persistence or not at all. "No baseline anywhere" over-corrects B5, whose lesson was that no gate compared to truth, not that baselines are forbidden. B5's own finding (model 1.671 versus EMA* 0.626) IS a baseline comparison.

**What replaces it is arithmetic that is already green: AttractorRAG.** AR1 gives attractors position, spread and provenance; AR2 makes the retrieval metric the energy metric; AR4 makes k-NN monotone and refinable; AR10 makes the library the corpus. That is the ranked, read-only, provenance-carrying codebook the design wanted, with no weights, and it is unported. It is the next real object, and it is blocked on a consumer: `Reweave` has no non-test caller and `ContentView` records that the dial-driven re-render is not built, so TUNING today holds exactly one edit, the identity.

**Three numbers must come back before any weights are trained, and none of them needs MLX:** (a) the fraction of the 4096 blocks that the shipped far-gate leaves live at `K = 4`; (b) whether the label alphabet is finite once BasinId is redefined onto a green finite set (SK10's three fates, PE11's (φ, m_st, s), or FC7's 16 shells); (c) the mutual information between a fixed-function feature map and that label. If (a) is small, the answer is the identity almost everywhere and there is nothing to learn.

## 7. RULINGS DANIEL MUST MAKE

1. **The three inert mlpackages.** SKGeneGround, SKGenePasser and SKGeneCodec are bundled, loaded, and never given a prediction; the only three `prediction(` calls in the tree are ANELoop, DyadANE, TensorANE. Wire each with a live parity gate against its CPU twin, or delete. A twin with no live parity gate is a fallback nobody has caught yet. *Blocks nothing; decides ~256 KB of bundle.*
2. **Which Birkhoff M is THE meter.** RateLadder's RL5 (derived, anchored, traced in every GIF) or `BirkhoffMeasure.swift` (naked 0.6/0.4 weights, `max(complexity, 0.001)` floor, spec is DeviationManifold which is outside CORE and uses the retired 8×8×4 palette) which is the one wired through FrameBuffer, both capture managers, GIFMachine's export tuple, ResultStateView and Reweave. Retire or re-prove the loser. *Blocks any landscape work that reads "the app's beauty measure".*
3. **`DyadEnergy.eDist = w + sOcc`.** This adds a dimensionless wall fraction to a normalized Shannon entropy, which TE8 explicitly prohibits, with no axiom behind it, and it rides every exported GIF as provenance. Correct to a vector with a version bump, or declare TE8 non-binding here and say why. *Contradicts a green axiom today.*
4. **The three deprecations** (SpatialTransport, RealTesseract, and **BreakInvariants, which is CORE and green**). BreakInvariants exists solely to prove three fatal flaws in SpatialTransport, and both are registered. That is the schism the registry prevents, but retiring a green CORE file is a ruling against green work. *Blocks commit D and changes CORE to 60.*
5. **`TemporalLoop.hs` is a false green.** Zero axioms, zero gates, no check function; it passes the truthful harness on `rc = 0` alone, and its section 4 concludes independent-frame rounding is optimal. Re-prove it with gates, or deprecate it. Either way the harness needs a third clause: a CORE file that prints no gate mark fails. *Blocks any loop-closure law.*
6. **May a non-causal temporal filter exist at all?** A ring-closed EMA on Z/64 reads frames > t, which contradicts WS5 ("frame t reads only frames ≤ t") and EM12/EM13 (one encoder; live and export differ only in retention, and a surface that could show something the export would not produce is unrepresentable). If yes, it is export-only and needs a DYAD STATS v4 tag with v3 retained, per the GROUNDHUE v1 to v2 precedent, because CR3 is byte-exact identity re-weave of an archived GIF. MS8 measures the seam; it does not authorize the fix. *Blocks any trajectory law.*
7. **Is a rotation of Z/64 an equivalence on the artifact?** The GIF writes NETSCAPE loop-forever, so no frame is privileged, yet every shipped filter seeds at frame 0 and the S4 pools and StrataDescent blocks partition time linearly. If yes, the path quotient is 64 times coarser than the code assumes. *Blocks any trajectory law.*
8. **Does the tensor replace CubeStore before or after P5 lands?** CT11 declares a nonzero, g-bounded divergence between a cube read live and one rebuilt from the tensor, so P5's 1e-9 gate is CubeStore-era by construction. *Blocks P5's gate wording.*
9. **`ANELoop.sweeps = 4` and `phaseChaosLoop = false`.** The K is a naked constant with an A-series pin owed, and the descent is behind a false flag. Nothing about basins, fixed points or labels is definable until both are answered. *Blocks any model.*
10. **CL6's prose versus its predicate.** CL6 concludes the metric "has to be LEARNED as a field" and calls that "the one thing a training run is for here". The pullback g = JᵀJ through the pre-quantisation continuous table is arithmetic and needs no weights; the version with an "M restricted to the palette" is fabricated and must not be built. This session builds neither. The ruling is owed before anyone proposes a metric again. *Blocks nothing now.*
11. **CL1's arity correction** (14 continuous + 2 bits). Factual and verified twice, but it edits a green axiom's headline claim. Confirm.

## 8. WHAT THIS DOES NOT SOLVE

- **The trajectory law is still missing**, and it is narrower than ColourLatent's header says. SV3/SV4/SV6/SV7 already own 64-periodic trajectories in the 9 stats dims. Nothing anywhere describes the temporal behaviour of the ground moments (deltaL, alphaC, betaC, capped), of GroundHue's rotation and balanced bit, or of the role and coverage field. That is the real hole, and it is blocked on Rulings 6 and 7.
- **Zero device evidence.** Nothing in this plan runs on a phone. The owed device pass from the previous session is still owed.
- **No basin, no barrier, no optimality result.** AL4 proves monotone descent and a stable fixed point. Nothing counts local minima or bounds a barrier. No metric on the space of cubes exists (the only two distances in the tree are non-CORE or over a retired palette).
- **Nothing reaches a user surface.** The edit tick loop the energy vector would feed does not exist; Reweave has no non-test caller. P5 is a meter with a test, not a feature.
- **`Weave/GIFEncoder.swift` still has no spec.** The LZW and GIF89a byte writer, the artifact the app exists to produce, is owned by no axiom, while WS2 already reasons about LZW cost. The orphan ratchet records that; it does not fix it.
- **Retention still has no axiom.** CR1 and CR3 are cited as law by CubeStore and Reweave and live only in `docs/model-placement.md`.
- **The sensor still has one spec** (FrameGeometry, the crop). FRONT-ONLY and CENTER STAGE are enforced by runtime predicates and prose.
- **Roughly 39 Swift and Metal files stay orphaned**, including all nine `Surface/Scenes/*.swift` and three of four `Store/` persistence files. The ratchet only forbids the number growing.
- **The SK gene layer stays provenance-only.** AX9 records why. If Daniel wants SK to do real work, it will not be as a cursor over a 3-rung ladder, and the next proposal must start from AX2/AX6/AX7, which already own what a reduction event means geometrically.