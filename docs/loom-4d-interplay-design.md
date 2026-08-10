# FINAL DESIGN DIRECTION — JUDGE-16: the Signal Rung-16 Palette Budget

**Verdict basis.** Both judges independently selected JUDGE-16 (no split to reconcile). Per the second judge's explicit recommendation, two elements are grafted in from SF-16: (a) the **pre-multiplied single weight buffer** as the Metal-parity answer for the refined path, replacing JUDGE-16's weaker "gate buffer OR GPU bypass" option; (b) SF-16's **witness-pinned spec style** — tie-free integer quantization pinned to one expression, explicit threshold witnesses, and a determinism/recompute law. SF-16's "gate only removes" subset law and its inertness corollaries are also adopted as axioms. Nothing is taken from LOOM-16: both judges rejected its resolution-flattening Phase 2.5 (beyond the directive, a look change nobody asked for) and its flat-index-255 no-face foot-gun.

**The directive, resolved.** "Use R,G,B,depth & the loom — depth is for color — at 16×16 we CAN judge where the user is." Depth **steers** color allocation; it does not replace the epoch axis (iterative-not-replacement). The loom contributes its **geometry and laws** — exact u64 sum-pooling over 2×2×2 spacetime blocks, the 16-rung, the 320 cs time law — applied to the **signal carrier** (depth/face grids), not to realized indices. This is why the index-carrying TriScaleLadder can stay measurement-only without contradiction: **realized indices do not exist at steering time, but the signal does.** If Daniel means the literal TriScaleLadder object must steer, this design must be re-scoped (see Open Questions, last item) — we say so honestly rather than pretend.

---

## 1. The mechanism, exact

### 1.1 Where and when

Once per burst, at the top of `encodeGIF` in both managers (CameraManager.swift:967, FaceCaptureManager.swift:~320) — **before** the quantize loop, after all 64 `CapturedFrame`s are in memory. Zero capture-tick change, zero preview change. A pure function:

```
SubjectJudgment16.judge(depths: [[Float]])  // 64 frames × 4096 samples
```

Input is the shared `depths` slot: LIVE = `DepthSignal` disparity-affine signal ([0,1], 1=near, 0.5=invalid-fill); FACE = `FaceMeshSignal` anatomical raster (nose=1, background exactly 0, all-zeros when no face). Both modes feed it with zero mode-specific code.

### 1.2 Lift, pool, judge

**Lift (pinned, tie-free, exact in Haskell Rational and Swift alike):**

```
q(d) = min(65535, floor(65536 · clamp01(sanitize(d))))    as UInt64
```

`sanitize` = NaN→0, clamp [0,1] — exactly `CentroidRefiner.sanitizedWeight`. Never `round`: ties are outlawed by pinning the expression.

**Pool (the loom's own operator, on the signal carrier):** exact u64 sums over 2×2×2 spacetime blocks, applied twice — 64³ → 32³ → 16³. TL1 sum-composition and TL3 mass conservation hold verbatim on this carrier. The 16-rung of the signal cube = **16 time slices** (4 frames each = 20 cs at the export's 5 cs cadence; 16 × 20 = 320 cs, the loop) × a **16×16 cell grid** (4×4 px per cell). Each rung voxel aggregates 64 Q16 samples; mass M ∈ [0, C], capacity **C = 64 · 65535 = 4,194,240**.

**Judge (integer compares only, RL1's monotone gate at the 16×16 rung Daniel named):**

```
SUBJ    iff  3M ≥ 2C
BORDER  iff  C ≤ 3M < 2C
BG      iff  3M < C
```

4096 ternary judgments per burst (16 slices × 256 cells), each from 64 samples. Derived gate: `g(slice, cell) ∈ {1, 1, 0}` for {SUBJ, BORDER, BG}. Slice t governs exactly frames 4t..4t+3.

**Inertness corollaries (proved as spec cases, SF-16 style):**
- FACE no-face: all-zeros grid → q = 0 → M = 0 → all BG → zero SUBJ cells → **vacuous, byte-identical output**.
- LIVE all-invalid: 0.5-fill → q(0.5) = 32768 → M = 64·32768, 3M = 6,291,456 ∈ [C, 2C) → all BORDER → zero SUBJ cells → **vacuous, byte-identical output**.

A slice with zero SUBJ cells gates nothing for its 4 frames. A burst with no subject anywhere produces today's GIF byte-for-byte.

### 1.3 Allocation, per export method

**(1) DYAD — the real 256-entry budget (DY1/DY2 untouched).**
- *Stats seam* (DyadPipeline.swift:91): `weights[p] = depths[p] · g(slice(f), cell(p))`. `DyadPalette.analyze`'s `wi > 0` loop (DyadPalette.swift:176) then **structurally excludes every BG-cell pixel** from centroid + covariance, so the whitened σ and the binomial shell radii ρ_k = 2kσ/7 contract to the subject's OKLab spread — all 128 designed primaries (ladder [1,1,2,4,8,16,32,64]) tile subject colors densely. Since the 128 σ-mirrors are pure functions of the primaries, **all 256 entries become functions of subject-and-border pixels**. "Depth is for color," delivered.
- *Role seam* (DyadPipeline.swift:112–117): `mask[p] = (d > 0.6) ∧ (cell ∈ SUBJ ∪ BORDER)`. A BG-cell pixel with d ≥ 0.6 (false-near speckle) is **forced far: t = 1 → exactly index 255** = comp(centroid). This is the confinement that actually holds (judge 1 verified SF-16's softer veto leaks through the bleed band's t=0 primary-side tiles; forcing t=1 closes it). Background traffic is confined to the generated σ-mirror half plus the unchanged lawful bleed pair-dither. Masks/fars/pulls are built CPU-side before Stage 2 — **ANE assign contract and pairDither untouched**. EMA (α=0.3) and DY8 stats→table rebuild survive because the trace records post-gating stats.

**(2) REFINED.** StageA weight (CentroidRefiner.swift:191) becomes `sanitizedWeight(depths[p]) · g`, **pre-multiplied into the single weight buffer that both the CPU fold and the GPU RefineAccumulator consume** (SF-16 graft: no kernel change, `MetalRefineParityTests` bit-parity preserved by construction). Entries whose traffic lies wholly in BG cells accumulate zero mass and by WL3 keep canonical bytes exactly — the background keeps the full 4⁴ spine; subject mass alone spends the drift budget inside WL1 cell clamps. K=8, η=μ=0.5 unchanged.

**(3) TESSERACT (honest: the table is static data; no entry count can move).** Steering acts at the two assignment seams via `dEff[p] = depths[p] · g`:
- Diffusion `s = 1 − 0.7·dEff` (PerfectQuantizer.swift:111): BG cells → full diffusion (maximal diversity spread over background).
- Per-group `σ = σ_base·(2 − avg dEff)` (:175–177): BG cells → widest epoch Gaussian (temporal shimmer across all 4 epochs); SUBJ cells keep the tight dominant-epoch cadence. **The subject owns temporal stability; the epoch axis stays the epoch axis.**

### 1.4 Plumbing

Managers call `judge` once, expand per-frame gate arrays `[Float]` (4096; parameter default nil ⇒ identity), pass gates into `quantizeFrame` and the judgment into `GIFMachine.makeGIF`, which threads it to the dyad/refined branches and writes the 16 per-slice SUBJ counts into the provenance trace beside `bleed`. By the determinism law (J11), `makeGIF` given nil can recompute the identical judgment from `QuantizedFrame.depths`. Optional persisted key `"export.judgment"` follows the bleed precedent exactly (settings cover only, XM4 garbage→default, no UI chrome).

---

## 2. Spec module sketch — `spec/quantization/SubjectJudgment16.hs`

Runghc, check-mark main, seeded Integer grids, exact Rational thresholds, **explicit witnesses** (SF-16 style). Registered in spec/Makefile: tally 31 → 32, zero failures.

- **J1 SUM CARRIER COMPOSES** — on Q16 signal cubes, `pool2 . pool2 == pool4` exactly for every cube (TL1 lifted to the signal carrier; no rounded intermediate is ever a rung).
- **J2 MASS CONSERVED** — total Q16 mass invariant 64³→32³→16³; nothing dropped, nothing double-counted (TL3 analog).
- **J3 PINNED LIFT, TIE-FREE, MONOTONE** — `q(d) = min(65535, floor(65536·clamp01(d)))`; monotone in d, no `round`, no Double in any judgment; witnesses at q(0)=0, q(0.5)=32768, q(1)=65535. *(SF-16 graft.)*
- **J4 MONOTONE JUDGMENT, EXACT THRESHOLDS** — BG < BORDER < SUBJ by integer compares `3M ≥ C`, `3M ≥ 2C` with C = 64·65535 (RL1's 1/3, 2/3 gate at the 16-rung); raising any sample never demotes its cell; witnesses at M such that 3M = C−1, C, 2C−1, 2C.
- **J5 TIME LAW INHERITED** — 16 slices × 4 frames × 5 cs = 320 cs; slice t governs exactly frames 4t..4t+3; the 16 slices partition 0..63 (TL4 geometry).
- **J6 BUDGET CONFINEMENT (dyad)** — a BG cell contributes zero stats weight and no face role; every designed-primary assignment lies in a SUBJ∪BORDER cell; a BG-cell pixel with d ≥ θ is exactly index 255. DY1 (Σ ladder = 128) and DY2 (σ-involution in every table) untouched — checked on a toy role model.
- **J7 GATE ONLY REMOVES, NEVER PROMOTES** — `faceGated(p) = facePixel(p) ∧ cellOK(p)` is a pointwise subset of the raw d > 0.6 mask, and inside a SUBJ cell the two masks are equal. The judgment can veto a speckle; it can never invent face pixels the signal did not assert. *(SF-16's SF7, grafted.)*
- **J8 SPINE PRESERVED (refined)** — an entry whose gated traffic mass is zero has canonical bytes bit-exactly (WL3 lift); movement always inside WL1 cell clamps.
- **J9 VACUITY** — a slice with zero SUBJ cells gates nothing: its 4 frames' indices and tables byte-identical to the ungated pipeline. Corollaries proved as cases: FACE all-zeros grid is all-BG → vacuous; LIVE all-0.5-fill is all-BORDER → vacuous. A no-subject burst reproduces today's GIF byte-for-byte.
- **J10 MODE AGNOSTIC + DETERMINISTIC** — judgment is a total pure function of the signal grids alone; equal bytes → equal masks; recomputation downstream from `QuantizedFrame.depths` reproduces the managers' pre-quantize judgment bit-for-bit. *(SF-16's SF8, grafted.)*
- **J11 CONTAINER INVARIANCE + LOOM INDEPENDENCE** — no container byte (64 frames, 64×64→256×256 replication, 5 cs delay, table scheme) depends on the mask; TriScaleLadder over realized indices remains post-encode measurement-only — the judgment reads the signal carrier, never a rung sum, so "no GIF byte depends on the ladder" stays true.

**Companion amendment, same commit as the Swift role change:** `spec/quantization/DyadPalette.hs` DY6 → **DY6′**: face role requires SUBJ∪BORDER cell; BG ∧ d ≥ θ ⇒ exactly 255. DY1/DY2/DY8 untouched. (Spec-first discipline: the authoritative Haskell law must never go stale against Swift behavior — this was the judges' decisive strike against the runners-up.)

---

## 3. Swift touchpoints, implementation order

1. **`spec/quantization/SubjectJudgment16.hs`** — J1–J11 with witnesses; add to spec/Makefile; `make test` 31 → 32 green. Nothing else lands until this is green.
2. **`spec/quantization/DyadPalette.hs`** — DY6 → DY6′ amendment (may land with step 1; must land no later than step 6).
3. **NEW `Tesseract/Tesseract/SubjectJudgment16.swift`** (~120 lines, pure): pinned q lift, u64 2×2×2 pooling ×2, ternary judge, per-frame gate expansion. Mirror TriScaleLadder.swift style.
4. **NEW `TesseractTests/SubjectJudgment16Tests.swift`** — spec-parity vectors for J1–J11, including both inertness corollaries and a **vacuity byte-identity fixture** (no-subject burst → today's bytes exactly).
5. **`PerfectQuantizer.swift`** (:60–64, :111, :175–177) — `quantizeFrame` gains `gate: [Float]?` (nil ⇒ identity); `dEff = depth·gate` feeds the diffusion and σ seams.
6. **`DyadPipeline.swift`** (:71, :91, :112–117) — `process` gains judgment param; weights gated; mask/far cell-aware with the t=1 forcing; `pairDither` and `DyadANE.assign` untouched.
7. **`CentroidRefiner.swift`** (:183–201) — stageA weight = `sanitizedWeight(depths[p])·gate`, **pre-multiplied into the single weight buffer consumed by both CPU and GPU paths**; `MetalRefineParityTests` must stay bit-identical with zero kernel edits.
8. **`GIFMachine.swift`** (:88–103, :156–193, :211–242) — thread judgment to dyad/refined branches (nil → recompute from depths per J10); trace gains 16 per-slice SUBJ counts beside `bleed`; optional persisted `"export.judgment"` key.
9. **`CameraManager.swift`** (:967–989, :1011) and **`FaceCaptureManager.swift`** (:~320–345, :362) — compute judgment once before the quantize loop; thread gates and judgment. `TriScaleLadder.telemetry` call (:1016) unchanged, post-encode.
10. **Verification pass** — `GIFOutputContractTests`, `DyadGIFContractTests`, `MetalRefineParityTests`, `TriScaleLadderTests` all green **unmodified**. (Judge-verified: DyadGIFContractTests locks involution + container on fixture tables, not pipeline role bytes — no fixture regeneration expected; confirm on the first run and flag to Daniel if wrong.)

Compile-only + tests + specs; device feel is the only real gate, on Daniel's device pass.

---

## 4. What stays untouched, and why

- **Byte-locked container** — 64 frames × 64×64 indices → 256×256 by replication, 5 cs delay, per-method table scheme. The design changes only how indices and tables are *chosen* (J11).
- **TriScaleLadder (spec + Swift)** — stays measurement-only, verbatim, post-encode. Its *geometry and laws* govern the new module as template; its *object* is never promoted. No feedback loop: the judgment steers on the signal carrier; the ladder measures the realized output.
- **DY1/DY2 and the 128/128 involution** — the split is law, byte-locked by DyadGIFContractTests. All 256 entries become functions of the subject *through* the involution, not around it.
- **The epoch axis** — depth steers allocation and cadence; the 4⁴ palette stays (epoch, R, G, B). No axis replacement.
- **Capture loop, preview path, ANE assign, pairDither, GIFEncoder, FrameBuffer carriers, TesseractPalette** — all unchanged.
- **Decrees** — ★NO-CAPTURE-TRAINING (integer thresholds, exact sums, zero fitted parameters); SIMPLICITY (zero UI; at most one persisted settings-cover key on the bleed precedent); ★FRONT-ONLY (untouched); iterative-not-replacement (every change at a documented seam; J9 vacuity gives a byte-identical no-subject path).
- **Known debt, untouched and still flagged** — the dormant Quantize.metal meters-vs-[0,1] P0 (MetalPipeline.swift:262–267). SubjectJudgment16 consumes only DepthSignal-mapped CPU-path values, never `depth64Texture` raw meters.

**Honest residual risks:** (1) default-on steering changes every export's bytes with no A/B surface — J9 inertness on degenerate bursts is the safety floor, the settings key the escape hatch; (2) a subject smaller than one 4×4 cell, or heavy depth noise, can drop primary access for a 20 cs slice — the slice cadence recovers fast, and LIVE's 0.5-fill floor lands at BORDER (g=1), safe-conservative; (3) BORDER at full weight slightly dilutes shell contraction — deliberate, revisitable (Q2).

---

## 5. Open questions — Daniel only

1. **Always-on vs toggle.** J9 vacuity makes always-on safe on degenerate bursts. Ship v1 always-on, or behind a persisted `"export.judgment"` key (bleed precedent) for the first device pass?
2. **BORDER gate value.** Proposed: hard g=1. Alternative: the continuous cell mean M/C as the gate value (smoother shell contraction, one more monotonicity law). Which should hair/shoulders be — full citizen or proportional?
3. **LIVE invalid-fill 0.5.** Keep it counting toward cell mass (lands BORDER, safe), or exclude exact-fill samples as "no data" before pooling?
4. **Slice hysteresis.** 20 cs slices suppress flicker, but a fast face can cross a cell mid-slice. Add deterministic hysteresis (carry previous slice's verdict on BORDER ties) at the cost of one more law, or let v1 device feel decide?
5. **v2 depth of the budget lever.** Should the dyad shell ladder [1,1,2,4,8,16,32,64] itself reshape as a function of subject mass (any Σ=128 vector is DY1-compatible), or is placement-via-gated-stats the whole of v1? Recommendation: v1 = placement only.
6. **Provenance depth.** 16 per-slice SUBJ counts in the trace (tables already rebuild via DY8), or ride the full packed 4096-trit mask (~1 KB) so index frames are also reconstructible?
7. **The interpretive question, stated plainly.** This design uses the loom's rung-16 geometry, operator, and 320 cs time law on the **signal** carrier, and keeps the index-ladder measurement-only — because indices don't exist at steering time. If "use the loom" means the literal TriScaleLadder object must steer realized indices, that forces a two-pass quantize and a re-scope. Confirm the signal-carrier reading before step 1 lands.
