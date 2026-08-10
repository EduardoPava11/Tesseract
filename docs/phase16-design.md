# PHASE-16 — the Ladder-Steered Two-Pass Phase Budget (design v2)

**Revision of PHASE-16 v1 under the two adversarial reports (engineering D1–D9, theory F1–F9), all findings absorbed.** The two-pass skeleton, J-FREEZE, the trace design, the mask format, and the ANE insulation story survive — both reports attacked and held them. What did not survive: v1's classifier. The n₂\*/48 order parameter split against a background pole that does not exist at any reachable σ (F2/F4/D2), the hypergeometric segregation test's null was contradicted by PQ4's own depth-sorted allocation and its threshold sat at the null's mean (F3), top-2 was blind to epoch adjacency (F6), and the "derived from PhaseEnergy" story transplanted formulas while swapping the fields under them (F1). v2 replaces all three closed forms with one mechanism-true statistic — the **per-voxel free-energy comparison between the two BinomialCadence ensembles that pass 1 actually executes** — and states plainly what that is: cadence readback, with PhaseEnergy supplying the formalism (phases as ensembles, order as a free-energy sign, interface as a sign change of the phase field) and the ladder supplying the carriers, TL5's microstates, and TL7's free-block certificates.

Verified against source: `spec/output/TriScaleLadder.hs` (TL1–TL7), `spec/statistics/PhaseEnergy.hs` (banner hs:460–470, spin hs:191–193, walls hs:195–201, mStag hs:226–231), `Tesseract/Tesseract/TriScaleLadder.swift` (:26–32 UInt64 carrier, :120–126 mass fold, :140–154 freeBlocks, :157–168 telemetry), `BinomialCadence.swift` (:25–41 σ_base = 63/8, c_e = (2e+1)·63/8; :59–61 σ(d) = σ_base·(2−d); :89–107 gaussianProbs), `PerfectQuantizer.swift` (:110–130 F-S, :162–199 group-global epoch threading), `DyadPipeline.swift` (:31/:93–94 EMA α = 0.3, :111–127 roles), `DyadPalette.swift` (:180–182 totalW guard), `CentroidRefiner.swift` (:22–23, :189–197), `RefineAccumulator.swift` (:67–71), `GIFMachine.swift` (:205–244 arms, :212–221 mirror seams, :107–116 `mirrored`, :223–230 `mirrorFrames`), `GIFEncoder.swift` (:26–28/:55–57 trace param, :107–110 measure comment), `CameraManager.swift` (:901–916 depth record path, :969/:1000–1005/:1016/:1022), `FaceCaptureManager.swift` (:322/:362/:367).

---

## 0. Defect ledger — every finding, its disposition

Nothing from either report is dropped silently. **Fixed** = design changed; **carried** = kept as an explicitly flagged risk.

| finding | disposition |
|---|---|
| D1/F5 — P8 output confinement false for DYAD (EMA/global tables) and TESSERACT (F-S nonlocal, group-global threading) | **Fixed**: P8 split into P8a VACUITY (byte-identity, provable) + P8b INPUT confinement; global byte effects stated plainly (§2, §4) |
| D2/F2 — 48 split classifies time-in-cadence; BG channel strobes at the cadence period, noise-dominated where lit | **Fixed**: n₂\*/48 deleted; slice-aware likelihood-ratio sign test between the two closed-form BinomialCadence ensembles (§2) — separation now holds at every slice, computed witness included |
| D3 — mirror seam misread; tesseract pass 2 loses MIRROR; refined inherits live index/rgb mispairing bug | **Fixed**: mirror-last unified across all three arms; `mirrorFrames`-before-allocation retired; refined mispairing fixed as a deliberate, flagged byte change (§1, §5 step 6, Risk 8) |
| D4 — the REFINED "single weight buffer" does not exist | **Fixed**: mechanism restated as gated copies of `frame.depths` (identity `sanitizedWeight(g·d) = g·sanitizedWeight(d)`, g ∈ {0,1}, NaN·0 path included, asserted by a new parity fixture); explicit-parameter fallback specified if the audit finds another `depths` consumer (§5 step 8, Risk 9) |
| D5 — stale measure comment / `gifMeasure` / manager telemetry over pass-1 cube after steered tesseract | **Fixed**: `makeGIF` returns the shipped index frames; measure and `rungTelemetry` computed from the shipped cube; §3 basis statement made consistent (`telemetry basis = shipped`, `mask basis = pass1`) |
| D6 — Risk-5 text false (`analyze` has a totalW > 0 mid-gray guard); real hazard is a per-frame all-BG slice dragging the EMA to mid-gray | **Fixed**: per-frame gate bypass (zero gated weight ⇒ that frame uses ungated weights, traced); risk text corrected (§2, Risk 5) |
| D7 — P12 self-falsifying (the mask itself is container bytes); refined/tesseract encoder call sites never pass `trace` | **Fixed**: P12 restated over structural bytes with extensions exempt; the two call-site changes named in step 6 |
| D8 — degenerate-rule parenthesization lets an all-BG-plus-BORDER burst through | **Fixed**: nil iff SUBJ = ∅ **or** BG = ∅, unconditionally (§2) |
| D9/F9 — stag doesn't fit the UInt64 carrier; σ/e3 planes redundant; "spin verbatim" wrong (matches `phiOf`, not `spin`) | **Fixed**: 5 UInt64 planes (e0–e2, M, q; σ and e3 derived); stag demoted to an Int64 diagnostic sibling outside the mass fold with a signed-total law; "verbatim" language deleted |
| F1 — classifier not on PhaseEnergy/ladder quantities; role inversion unstated; TL7 returned but unconsumed; sweep.py field swap | **Fixed**: free-energy formalism with TL5 microstates explicit (shared entropy term, traced) and TL7 consumed as the no-interface gate; role-inversion and field-honesty paragraphs added; sweep.py claim deleted. **Carried** (Risk 7): PE's σ-spin observables are traced diagnostics, not load-bearing — the one reading of ruling 3 this design cannot satisfy without judging role indices (ANE leak) |
| F3 — hypergeometric null contradicted by depth-sorted allocation; threshold at null mean; temporal-MSB BORDER flash | **Fixed**: segregation test deleted entirely (its algebra was verified correct — retired as the wrong null, not as wrong math); BORDER = phase-field sign disagreement among the voxel's r32 children; no σ-MSB anywhere in v2, so the flash artifact cannot occur |
| F4 — 48 has no symmetry protection; "ground state" category error | **Fixed**: threshold is now the likelihood crossing, slice-derived; no midpoint constant exists |
| F6 — top-2 blind to adjacency; non-adjacent leftover epochs in mixed color groups | **Fixed** for BG recall (quadratic moment sends (32,0,0,32) to BG); **carried** (Risk 6) for the converse: SUBJ pixels in depth-mixed groups can inherit far-flavored leftover epochs |
| F7 — circularity unstated; meters-P0 dependency unstated | **Fixed**: circularity stated as the design's premise (§2 "what this judgment is"); meters-shaped input gets a graceful-degradation argument + spec witness + orient-conflict nil (§2, P17) |
| F8 — "small analogues" doesn't prove the pinned constant | **Fixed**: old P3 gone with its test; all v2 constants proved by interval-certified enclosure computed at full size in `Rational` (P3′) |

Verified-sound items retained on the reports' authority: DYAD/REFINED net-Δ≈0 cost structure, frame-parallel tesseract re-quantize, ANE fixed-shape insulation (DyadANE.swift:43–56) and the pure-CPU pass-1 basis killing XP1/XP2 leaks, `quantizeFrame` determinism under an all-ones gate, the depth record path delivering s ∈ [0,1] (CameraManager.swift:901–916), and DY8's trace parser tolerating an appended PHASE16 section.

---

## 1. The two-pass structure

Unchanged in skeleton from v1 — pass 1 is `PerfectQuantizer.quantizeFrame` (already run for every method at CameraManager.swift:969 / FaceCaptureManager.swift:322), pass 2 is the allocation `GIFMachine.makeGIF` already performs, and the ladder + judgment sit between them at the single seam (:205). Amended per D3/D5:

```
managers (capture + quantize unchanged)       GIFMachine.makeGIF (the single seam)
────────────────────────────────────          ─────────────────────────────────────────
64 CapturedFrames                             PASS 1 ARTIFACT: frames[].paletteIndices
  → PerfectQuantizer.quantizeFrame  ────────►   (UNMIRRORED lattice cube, every method)
  → [QuantizedFrame]  (PASS 1)                        │
                                              TriScaleLadder.judgmentLadder(frames)
                                                e0..e2 + M + q planes → poolL → poolL
                                                + TL7 per-block free predicate (returned)
                                                      │
                                              PhaseJudgment16.judge(r16, r32, freeBits)
                                                → mask: 4096 trits (SUBJ/BORDER/BG, §2)
                                                → nil ⇒ pass 2 = identity   │
                                                      │                     └──► packed into
                                                      ▼                          GIF trace
                                              PASS 2 (once, judgment frozen):
                                                dyad      → DyadPipeline.process(…, judgment)
                                                refined   → CentroidRefiner.refineAuto(…, judgment)
                                                tesseract → quantizeFrame re-run, dEff = depth·g
                                                      │
                                              MIRROR LAST (all three arms): output index
                                              frames flipped via mirrored(:107); mask trit
                                              planes flipped identically → export orientation
                                                      │
                                              GIFEncoder (byte-locked container; trace on
                                              ALL THREE call sites)  → returns Data + the
                                              SHIPPED index frames (D5)
```

**Judgment domain** — unchanged and load-bearing: the **pass-1 lattice cube**, for every method. It is what the ladder measures, it is pure-CPU deterministic (no XP1/XP2 ANE near-tie leakage into the mask), and the fallback chain (:227–229) inherits one coherent judgment.

**J-FREEZE** — unchanged: judgment computed once from the pass-1 cube, pass 2 applied exactly once. The composite map is discontinuous (largest-remainder counts, PerfectQuantizer.swift:245–258); an iterate-to-fixed-point loop is a data-dependent trip count (CentroidRefiner.swift:22–23) and is refused. `judge(pass-2 cube) == mask` is **not** a soundness condition (P10's deliberate counterexample witness).

**Mirror discipline (D3, rewritten).** v1's "apply mirror last, exactly as today" was wrong about today: only DYAD mirrors output indices (:216–218); REFINED and TESSERACT mirror **input** frames (:232, :239) via `mirrorFrames` (:223–230), which flips `paletteIndices` only, leaving `rawRGB`/`depths` unflipped — so a steered tesseract re-quantize would silently ship unmirrored, and refined's stage-A already pairs mirrored indices with unmirrored colors (CentroidRefiner.swift:189–197; RefineAccumulator.swift:67–71), a live mispairing bug. v2 unifies on **mirror-last**: every arm judges, allocates, and (for tesseract) re-quantizes on unmirrored frames; the mirror is applied to the final output index frames only; the mask's 16 per-slice 16×16 trit planes are mirrored identically, so the traced mask matches shipped bytes (P13, now true of the implementation). Pre-allocation `mirrorFrames` is retired. This changes mirrored-REFINED bytes versus today — a bug fix, inside the "only HOW indices/tables are chosen" latitude, flagged as Risk 8. One audit obligation before landing: confirm the encoder's `frames:` entry consumes only `paletteIndices` (+ refined tables), so an output-side index flip is complete (step 6).

**Provenance return (D5).** `makeGIF` returns the shipped index frames alongside `Data`. The tesseract measure comment is rebuilt from the pass-2 cube inside the arm; managers compute `gifMeasure`/`allIndices` and the post-encode `TriScaleLadder.telemetry` from the returned shipped cube (CameraManager.swift:1000–1022, :1016; FaceCaptureManager.swift:362–367). Signature change accepted; §3's basis statement is now consistent: *telemetry measures shipped bytes; the mask's basis is pass 1, and the trace header says so.*

**Cost, honestly** (64³):

| item | cost |
|---|---|
| Ladder: 5 planes at rung64 + two poolings + per-voxel compares | ~4–8 ms CPU |
| Judgment: 4096 voxels × integer compares + 8-child sign check | < 1 ms |
| DYAD / REFINED pass 2 | **replaces** today's single run — net Δ ≈ 0 |
| TESSERACT pass 2 | one steered re-quantize, ~20–60 ms CPU, frame-parallel |
| Mask pack + trace (+ threshold table) | ~1.3 KB text |
| Memory | +~10.5 MB transient (5 UInt64 planes) + 2.1 MB if the Int64 stag diagnostic is materialized; ~2 MB with an on-the-fly first fold (TL1 guarantees equality) |

Worst case (tesseract): today + ~70 ms. Default (dyad): today + ~10 ms.

---

## 2. The phase judgment — the free-energy sign of the cadence ensembles

**What this judgment is, stated first (F7).** Pass 1 writes depth into the epoch axis: PQ4 plus `σ(d) = σ_base·(2−d)` (BinomialCadence.swift:59–61) means near pixels draw epochs from a tight Gaussian cadence and far pixels from one exactly twice as wide. The face is identifiable from realized indices *because and only because* pass 1 put it there — the judgment is **cadence readback**: it recovers, per 16-voxel, which of the two generative ensembles pass 1's mechanism was executing. Ruling 1 permits exactly this (the literal ladder over realized indices steers); the design claims nothing more. The PhaseEnergy contribution is the formalism, honestly scoped below.

**The carriers (D9).** `rung64` gains **five UInt64 planes**, each pooling by the existing `poolL` with TL1/TL3 by construction (all are non-negative integer sums):

| plane | per fine cell (pixel p, frame z; e = index ≫ 6) | at the 16-voxel (4×4 px × 4 frames = 64 cells) |
|---|---|---|
| `e0,e1,e2` | epoch indicators (`e3 = count − e0 − e1 − e2`, derived — F9's redundancy removed) | exact epoch histogram (n₀..n₃), Σ = 64 |
| `M` | **cadence moment** `(8z − 63(2e+1))²` — the integer form of `64·(z − c_e)²`, c_e = (2e+1)·63/8 exactly (BinomialCadence.swift:35–38, σ_base = 63/8) | S_v = Σ M ∈ [0, 64·441²] — the decision statistic |
| `q` | Q16 depth lift (v1's J3 lift, unchanged) | M_v — consistency check only (below) |

The σ-count plane is **derived** where needed (`e2 + e3` — it equals `phiOf`'s ≥128 count, hs:222–223; v1's "spin verbatim" wording is retracted per F9: `spin` is +1 *below* 128). The staggered plane survives only as an **Int64 diagnostic sibling** outside `RungCube` and outside the `mass()` fold (TriScaleLadder.swift:120–126 stays pure UInt64), with its own signed-total conservation law (P1′) — it is PE8 continuity in the trace, never a decision input. The TL7 per-block free predicate that `freeBlocks` (:140–154) computes and discards into counts is **returned** and, unlike v1, **consumed** (below).

**The two ensembles.** For frame z, the closed-form epoch distributions pass 1 draws from are `p_near(z) = gaussianProbs(z, σ_base)` and `p_far(z) = gaussianProbs(z, 2σ_base)` (BinomialCadence.swift:89–107) — the two σ poles of the mechanism itself, not a fictitious uniform state (F2/F4: the old "mixed pole" (16,16,16,16) required σ ≫ 47 and exists at no depth; it is deleted, along with the 48 midpoint and its false Ising-symmetry claim).

**The decision — a free-energy sign.** The per-voxel log-likelihood under either ensemble decomposes as `log P(n | p) = log W(n₀..n₃) + Σₑ nₑ log pₑ` — multinomial entropy plus ensemble energy. `W` is exactly TL5's `microstates` object; it is **shared by both ensembles and cancels in the difference**, which the spec states rather than hides (F1): the classifier is the energy difference, and `log W` is traced per voxel as its entropy s_v (TL7-free voxels are the W = 1, zero-conditional-entropy certificates). Because the two ensembles are Gaussians over shared centers with σ_far = 2σ_near, the log-ratio collapses to the cadence moment:

```
ln p_near,e(z) − ln p_far,e(z) = −(3 / (8σ_base²)) · (z − c_e)²  +  β(z),
    β(z) = ln( Z_far(z) / Z_near(z) )  >  0
```

so, over the voxel's 64 cells (frames 4s..4s+3 of slice s):

```
NEAR (subject phase)   iff   3·S_v  <  Θ_s          Θ_s = 508032 · Σ_{j=0..3} β(4s+j)
FAR  (background phase) iff  3·S_v  >  Θ_s
```

(508032 = 512·σ_base²·16 with σ_base² = 3969/64 — every factor derived.) **S_v is an exact integer; Θ_s is a derived transcendental constant**, pinned per slice as an interval-certified dyadic-rational enclosure [Θ_lo, Θ_hi] proved in the spec by `Rational` interval arithmetic on the exp/log series (P3′; this replaces v1's hypergeometric threshold, and F8's "small analogues" defect with it — the enclosure is computed at full size). S_v ≤ Θ_lo → NEAR; S_v ≥ Θ_hi → FAR; inside the enclosure gap → BORDER. Zero fitted parameters: constants are *computed*, never swept (the one decree-interpretation point — pinned transcendental-constant enclosures as "closed-form" — is flagged in Risk 10 for Daniel's sign-off).

**Why this fixes D2/F2/F6 — computed witness** (double-precision preview; the spec pins exact enclosures). At slice 0, z = 1.5-equivalent, per-cell expected moment `E[M]`: near ensemble ≈ 3.3×10³, far ensemble ≈ 1.46×10⁴, threshold Θ_s/64 ≈ 6.3×10³ — separation with wide margins **at the loop ends**, exactly where the old n₂\* test classified background as SUBJ (far top-2 mass 0.957). The quadratic moment weights *which* epochs, not merely concentration: the non-adjacent bimodal (32,0,0,32) voxel that n₂\* scored m = +1 lands deep in FAR (F6). The threshold varies with slice, so the strobing-at-cadence-period failure is gone by construction. The expected-margin law is provable per slice: `E_far[3S] − Θ > 0` and `Θ − E_near[3S] > 0` for **all 16 slices** (KL divergence positivity, made concrete as 32 rational-enclosure inequalities, P4′), and the spec computes **enclosed misclassification bounds** per slice by exhaustive enumeration of the C(67,3) = 47,905 epoch histograms against interval-valued multinomial probabilities (P15) — the exact operating characteristics, from zero capture data. A pleasing derived consonance, not a tuned one: the crossover σ\* where the two ensembles tie sits near √2·σ_base, i.e. depth ≈ 0.6 — the phase boundary the likelihood test draws in depth space lands essentially on DY6's existing face threshold (spec computes the exact value; preview only).

**BORDER — the interface, without the broken null (F3).** v1's segregation test is deleted: its hypergeometric algebra was verified correct, but its exchangeable-placement null is structurally violated by PQ4's depth-sorted contiguous allocation (PerfectQuantizer.swift:183–199) — every mixed voxel is "segregated by construction" — and its threshold sat at the null's mean (≈ coin-flip false positives). v2's interface is what an interface is in the phase formalism: **the locus where the phase field changes sign inside the voxel.** Each of the voxel's 8 r32 children (2×2 px × 2 frames — the ladder's own telescoping blocks, TL5) gets the same test at child scale: `3·S_c` vs `Θ_c = 127008·(β(z) + β(z+1))` enclosures. A voxel is **BORDER iff at least one child is strictly NEAR-side and at least one strictly FAR-side** (children inside their gap carry no evidence and force nothing); otherwise the voxel-level verdict stands, with the voxel-level gap also → BORDER. No σ-MSB appears anywhere in v2, so F3's whole-frame temporal BORDER flash at the epoch-1→2 handover cannot occur — a static far region is FAR at every slice and a static near region NEAR at every slice (KL positivity), so sign changes arise only at genuine spatial depth boundaries or genuinely ambiguous σ ≈ √2·σ_base material.

**TL7 consumption (F1).** A voxel whose TL7 predicate is true (≤1 of 8 children carrying lattice mass — W = 1, zero conditional entropy) **skips the child-disagreement test** and classifies by its voxel-level statistic alone: empty children pin their cells' epoch mass at e = 0 by *emptiness*, not by cadence, and mixed emptiness would otherwise manufacture fake sign disagreements. Free blocks are the ladder's own "no evidence here" certificates, and the judgment now honors them — the returned predicate has a real consumer.

**Orientation → consistency check (F7).** v1's label-swap bit is retired: the labels are intrinsically oriented, because the NEAR ensemble *is* the subject regime by pass-1's own law (PQ4 + σ(d)). The pooled-depth comparison survives as a **consistency check**: `(Σ_{v∈SUBJ} M_v)·|BG| ≥ (Σ_{v∈BG} M_v)·|SUBJ|` (cross-multiplied, exact). If it fails, the verdict is **nil** with `reason=orient-conflict` — a contradiction between depth and cadence readback signals corrupted input (notably the audited depth-meters P0), and the conservative response is today's bytes, not a label swap. This is the only place depth enters the judgment.

**Meters-P0 degradation (F7).** If LIVE depth arrives in meters and clamps toward 1, every pixel rides near-σ, the readback classifies everything NEAR, BG = ∅, and the degenerate rule fires — byte-identical passthrough, not a wrong steer. The record path is believed fixed (`DepthSignal.signalOrFill`, CameraManager.swift:901–916, delivers s ∈ [0,1]); the spec still carries a meters-shaped-input witness (P17) so the degradation is law, not luck.

**Degenerate rule (D8, pinned).** `judge` returns nil — pass 2 = identity, today's bytes — when any of: the burst is not 64³ (ladder guard, TriScaleLadder.swift:157–159); **SUBJ = ∅ or BG = ∅, unconditionally** (so all-BG-plus-BORDER cannot proceed to a tiny-support solve); orient-conflict. Trace records `PHASE16 v2 verdict=nil reason=…`.

**What steering does** — v1's seams, unchanged mechanics, with two amendments (D4, D6). Gate `g(f,p) = mask[slice(f), cell(p)] == BG ? 0 : 1`:

- **DYAD stats** (DyadPipeline.swift:93): `weights[p] = Double(depths[p]) · g`. **Per-frame guard (D6):** `DyadPalette.analyze` does not crash on zero weight — it returns mid-gray stats behind its `totalW > 0` guard (DyadPalette.swift:180–182; v1's "undefined behavior" claim was false) — but a wholly-BG frame would drag every later frame's tables toward mid-gray through the α = 0.3 EMA. Rule: if a frame's gated weight sum is 0, that frame uses **ungated** weights and the trace records `frame=t gate=bypassed`. The EMA chain always re-runs from frame 0.
- **DYAD roles** (:111–127): `face = (d > 0.6) ∧ (g == 1)`; BG speckle with d > 0.6 forced far, t = 1 → index 255 exactly (DY6′). Inside SUBJ and BORDER the depth rules are untouched — the gate only removes, never promotes (P9). The bleed band's pair-dither survives inside BORDER voxels.
- **REFINED** (D4, restated — v1's "single weight buffer" does not exist): the gate is pre-multiplied into **gated copies of `frame.depths`** handed to `refineAuto`, reaching both the CPU fold's inline `sanitizedWeight(depths[p])` (CentroidRefiner.swift:191) and the Metal driver's flattened depth buffer (RefineAccumulator.swift:67–71) with zero kernel edits — valid because `sanitizedWeight(g·d) = g·sanitizedWeight(d)` for g ∈ {0,1} including the NaN·0 → NaN → 0 path (reviewer-verified; pinned by a new parity fixture in step 8). Contingency, flagged: if the landing audit finds any *other* consumer of `depths` inside `refineAuto`, or the identity fails, fall back to an explicit per-pixel weight parameter threaded into both paths — an honest kernel edit with `MetalRefineParityTests` extended to cover it. WL3 unchanged: wholly-BG-traffic entries keep canonical bytes.
- **TESSERACT**: one steered re-run of `quantizeFrame` with `dEff = depths·g` at the diffusion seam (:111) and per-group σ (:175–177), on unmirrored frames, output indices mirrored last (§1). Same function, one parameter — not a fork.

**Effect confinement, restated honestly (D1/F5).** BG demotion is the only **input** channel: gated inputs differ from ungated inputs only at BG-classified pixels' contributions (P8b). **Byte effects are global**: gated DYAD stats move all 256 table entries and, through the EMA, every subsequent frame; refined centroid motion is global; tesseract's F-S diffusion pushes altered residuals into neighboring SUBJ pixels and the group-global epoch threading re-partitions whole color groups. v1's claim that pass-2 bytes differ *only at BG pixels* was false and is withdrawn. What remains provable is **vacuity** (P8a): a judgment with zero BG voxels — including every nil verdict — is byte-identical to today, because SUBJ and BORDER both gate at g = 1 and every depth rule is unchanged.

**Honesty about ruling 3 (F1).** The classifier lives on: the ladder's carriers and telescoping structure (TL1/TL3/TL5-blocks), TL5's microstate object (as the shared, traced entropy term that provably cancels in the decision), TL7's free-block certificates (consumed), and the phase *formalism* of PhaseEnergy — phases as statistical ensembles, order as a free-energy sign, interface as a sign change, transition as a crossover of finite width (the enclosure gap and the exact error tables are that width, made literal). It does **not** live on PhaseEnergy's frame observables — `walls`/`isingSum` (PE4), `sOcc`, `mStag` (PE8), `ePal` — which are defined on the σ-spin/role field of a single 64² frame. Those are carried as traced diagnostics for continuity. Two inversions are stated, not smuggled: (a) PE's banner (hs:466–468) puts the *subject* on the disordered side **of the role field**; here the subject is the ordered phase **of the epoch field** — different fields, both statements true; (b) making the σ-spin observables load-bearing would require judging DYAD role indices, which reintroduces the ANE near-tie leak §1 exists to kill. If Daniel wants PE's observables in the decision loop, that is a design change with a named cost — flagged as Risk 7, not silently resolved either way.

---

## 3. The ladder's promotion — which laws survive

**Survive verbatim: TL1–TL7.** They constrain the pooling algebra, which mentions no consumer. The new planes are additional carriers under the same laws (P1), with the stag diagnostic under a signed-total variant (P1′) — its conservation is of a signed total, not "mass," and it stays out of the UInt64 `mass()` fold (D9). TL7 is upgraded twice: its per-block predicate is returned, and it now has a consumer inside `judge` (the no-interface gate).

**Retired: the MEASUREMENT-ONLY header** (TriScaleLadder.hs:27–32, TriScaleLadder.swift:18–20, spec `main` banner) **and v1-JUDGE-16's J10/J11.** The amended guarantee, written into both headers:

> **THE LADDER STEERS (PHASE-16 v2, 2026-08-10):** pass-2 GIF bytes depend on this ladder computed over the **pass-1** lattice cube, through the PhaseJudgment16 mask — computed once, frozen (J-FREEZE), applied exactly once. `RungTelemetry` is computed over the **shipped** cube and remains a pure measurement of shipped bytes; it is not the mask's basis and is not required to reproduce it. The export is self-certifying **by inclusion, not re-derivation**: the packed mask (basis=pass1) and the threshold-table id ride the GIF trace, so the judgment is reconstructible from the export alone even though pass-1 indices are not shipped. It still trains nothing: `judge` is closed-form pooling plus derived integer comparisons against interval-certified derived constants — zero fitted parameters (★NO-CAPTURE-TRAINING).

**Amended provenance.** DY8 survives unamended: the mask steers the *weights* into `DyadPalette.analyze`, not the solver; traced pass-2 `frameStats` rebuild every palette byte (GIFMachine.swift:175–193 untouched — the parser stops at the first non-9-token line, so the appended PHASE16 section is safe). Full reconstruction is `pass2(inputs, traced mask, traced stats) = shipped bytes`. The EMA consequence is stated plainly: the judgment steers the smoothed **trajectory** — frame t's gating reaches frames t+1… through α = 0.3 — and per-frame unsteered counterfactuals are not reconstructible from the export (Risk 3).

---

## 4. Spec sketch — `spec/output/PhaseJudgment16.hs`

Runghc, check-mark main, house LCG, Integer/Rational-exact decisions, explicit witnesses, Makefile tally 31 → 32. Nothing lands in Swift until green.

- **P1 CARRIER EXTENSION** — e0..e2, M, q pool by `poolL` with TL1 composition and TL3 conservation exactly (staged-vs-direct witness on a hand-built cube). **P1′**: the Int64 stag diagnostic composes with signed-total conservation under the fixed (+,−,−,+) parity and is excluded from the UInt64 mass fold.
- **P2 ENSEMBLE IDENTITY** — `M_cell = (8z − 63(2e+1))²` equals `64·(z − c_e)²` with c_e from `BinomialCadence.centers` exactly; the derived σ-count (e2+e3) equals `phiOf`·4096 per frame on Bayer-tiled fixtures (PE7 lift, with the `spin`-complement relation stated correctly per F9).
- **P3′ THRESHOLD ENCLOSURES, DERIVED** — [Θ_lo, Θ_hi] per slice (and per frame-pair for children) computed by `Rational` interval arithmetic on exp/log series with proved remainder bounds, **at full size** (F8); the enclosure derivation is printed by the spec; the Swift constant table is emitted from it and hash-pinned.
- **P4′ SEPARATION AT EVERY SLICE** — `E_far[3S] > Θ_hi` and `E_near[3S] < Θ_lo` proved as rational-enclosure inequalities for all 16 slices and all 32 child frame-pairs (replaces v1's pole witnesses; this is the law D2 showed v1 could not have passed). Witness table includes slice 0 (the old failure point) and the loop minimum.
- **P5 MONOTONE, INTEGER** — S_v ∈ ℤ; moving one cell's epoch strictly toward the slice-nearest center never increases S_v; classification is monotone in S_v; no Double in any decision.
- **P6 NEUTRAL BORDER** — enclosure-gap voxels, child-disagreement voxels, and no-evidence children all resolve to BORDER; BORDER gates at g = 1; witness: such voxels' pixels carry today's weights unchanged.
- **P7′ ORIENT-CONSISTENCY** — the cross-multiplied depth comparison is total, deterministic, antisymmetric under population swap; failure ⇒ verdict nil (never a label swap); nil ⇒ P8a bytes.
- **P8a VACUITY** — zero BG voxels (including every nil verdict, non-64³, single-phase, orient-conflict) ⇒ pass 2 byte-identical to today; toy-pipeline witness proves **byte equality**. **P8b INPUT CONFINEMENT** — gated inputs differ from ungated only at BG pixels' contributions; the spec text states explicitly that *output* bytes may differ globally (EMA, tables, diffusion, group threading) and that v1's output-locality claim is withdrawn (D1/F5).
- **P9 GATE ONLY REMOVES** — inside SUBJ ∪ BORDER the pass-2 face mask equals today's `d > 0.6` pointwise; the judgment can veto a BG speckle, never invent a face pixel.
- **P10 J-FREEZE** — `judge` pure in the pass-1 cube; one application; a deliberate witness exhibits `judge(pass-2 cube) ≠ mask`, documenting that re-derivation is not a soundness condition.
- **P11 MASK ROUND-TRIP** — 4096 trits, 5 per byte (3⁵ = 243), 820 bytes + header (version=2, basis=pass1, class counts, orient-check bit, threshold-table hash); `unpack ∘ pack = id`; trace line parses back exactly.
- **P12 STRUCTURAL CONTAINER INVARIANCE** (D7) — no **structural** container byte (dims, frame count, 5 cs delays, 256×256 replication, per-method table scheme, LCT flags) depends on the mask, for any mask; comment/application-extension bytes are explicitly exempt (the mask lives there). Matches how the contract tests already parse (GIFOutputContractTests.swift:58–72, DyadGIFContractTests.swift:146–152).
- **P13 MIRROR COVARIANCE** — M and e-planes are x-independent per cell, so judging the mirrored cube equals mirroring the mask's trit planes exactly; stag flips sign under x → 63−x (63 odd), |·| invariant; mask stored in export orientation — and, per D3, the implementation now actually has one mirror seam for this law to be true of.
- **P14 DECREE CONFORMANCE** — every decision constant is derived (ensemble log-ratio, interval enclosures, cross-multiplication); zero fitted parameters; no UI; always-on.
- **P15 ERROR CHARACTERISTICS** — per-slice type-I/type-II misclassification bounds by exhaustive enumeration of the 47,905 epoch histograms against interval multinomials — the exact noise floor D2 demanded, from zero captures.
- **P16 FREE-BLOCK GATE** — TL7-free voxels never classify BORDER via child disagreement; witness: a voxel with one populated child and seven empty ones classifies by its voxel statistic.
- **P17 METERS DEGRADATION** — a meters-shaped depth burst (clamped-to-1 field) yields BG = ∅ or orient-conflict ⇒ nil ⇒ P8a bytes; the corrupted input cannot produce a wrong steer, only no steer.

Companion amendments, same commit as the Swift role change: `DyadPalette.hs` DY6 → **DY6′** (face requires non-BG voxel; BG ∧ d > τ ⇒ 255); `TriScaleLadder.hs` header + banner per §3 (axioms untouched); the parity-fixture law for the `sanitizedWeight` gate identity (D4).

---

## 5. Swift touchpoints, implementation order

1. **`spec/output/PhaseJudgment16.hs`** — P1–P17 green, threshold table emitted + hash-pinned. Blocks everything.
2. **`spec/output/TriScaleLadder.hs` + `spec/quantization/DyadPalette.hs`** — header amendment, DY6′, gate-identity fixture.
3. **`TriScaleLadder.swift`** — `judgmentRung64` sibling carrying e0..e2/M/q (+ optional Int64 stag diagnostic outside the mass fold, D9); `poolL` extended; `ladder(frames:)` returns pooled cubes + the TL7 per-block predicate (:140–168 extended, not replaced); `telemetry` reimplemented on top, semantics unchanged, **now fed the shipped cube by the managers** (D5).
4. **NEW `PhaseJudgment16.swift`** (~180 lines, pure): moment compares against the pinned integer threshold table, child sign test, TL7 gate, orient-consistency, nil rule (D8 parenthesization pinned: SUBJ = ∅ ∨ BG = ∅), trit pack/unpack, mask mirroring.
5. **NEW `PhaseJudgment16Tests.swift`** — spec-parity vectors for P1–P17, including the byte-identity vacuity fixture, the meters fixture (P17), and the mask round-trip.
6. **`GIFMachine.swift`** — ladder + judgment computed once before the `switch` (:210); threaded into all three arms; **mirror-last unification** (D3): retire pre-allocation `mirrorFrames` (:232, :239), flip output index frames in every arm via `mirrored` (:107), flip the mask identically; audit that the encoder `frames:` entry reads only indices (+ tables) — if not, route all arms through the `indexFrames:` entry; **pass `trace:` at the refined and tesseract call sites** (:233–242 — the parameter already exists, GIFEncoder.swift:26–28/:55–57; D7); tesseract arm rebuilds the measure comment from the pass-2 cube; `makeGIF` returns shipped index frames (D5); fallback (:227–229) passes the same judgment down.
7. **`DyadPipeline.swift`** — `process(frames:bleed:judgment:)`: weights gated at :93 with the **per-frame zero-weight bypass** (D6, traced); roles gated at :111–127 with t = 1 forcing; `pairDither`/`DyadANE.assign` untouched; pass-2 stats traced (DY8 intact).
8. **`CentroidRefiner.swift` / `RefineAccumulator.swift`** — gated `frame.depths` copies (D4) feeding both the CPU fold (:191) and the Metal flatten (:67–71); new parity test asserting `sanitizedWeight(g·d) = g·sanitizedWeight(d)` incl. NaN; audit for other `depths` consumers, with the explicit-weights-parameter fallback (and extended `MetalRefineParityTests`) if the audit or identity fails.
9. **`PerfectQuantizer.swift`** — `quantizeFrame(gate: [Float]?)`, nil ⇒ identity: `dEff = depth·gate` at :111 and :175–177. Managers' pass-1 call sites pass nil.
10. **`CameraManager.swift` / `FaceCaptureManager.swift`** — capture/quantize loops unchanged; `gifMeasure`/`allIndices`/`rungTelemetry` computed from `makeGIF`'s returned shipped frames (:1000–1022, :1016; FaceCaptureManager :362–367) — signature change accepted (D5).
11. **Verification** — `GIFOutputContractTests`, `DyadGIFContractTests`, `TriScaleLadderTests` green unmodified; `MetalRefineParityTests` green (extended only under the step-8 fallback); new PhaseJudgment16Tests green. Compile-only + tests + specs; device feel is the only real gate, on Daniel's device pass. Note for that pass: mirrored-REFINED exports change bytes (Risk 8) — expected.

---

## 6. Risks, honest — every carried item

1. **Tesseract double-encode cost** (~20–60 ms) — real only for tesseract; capped by J-FREEZE's single application.
2. **Residual statistical misclassification.** The likelihood test is the optimal discriminator between the two ensembles, and P15 bounds its per-slice error exactly — but the bound is not zero: 64 draws per voxel, and real depths put σ between the poles, so material near d ≈ 0.6 (the derived crossover) classifies near-chance. The safety asymmetry holds: only false **BG** on true subject demotes pixels; false SUBJ/BORDER is neutral (P6/P8a). If device feel fails here, the lawful fix is pass-1's σ mapping, not judgment tuning (★NO-CAPTURE-TRAINING).
3. **EMA trajectory semantics** — gating steers the smoothed trajectory; per-frame unsteered counterfactuals are not export-reconstructible. Documented; not fixable without breaking DY7.
4. **J-FREEZE re-derivation trap** — `judge(pass-2 cube) ≠ mask` in general (P10's witness); the trace header's `basis=pass1` is the guard against future "verification" mistakes.
5. **Degenerate frames** — the per-frame all-BG slice is handled by the traced bypass (D6); the *global* degenerate cases by the pinned nil rule (D8). The old mid-gray-drag hazard is closed; the bypass itself means one frame of a steered export is locally unsteered — traced, visible in provenance.
6. **Mixed color groups** (F6 residual) — epoch threading is group-global (PerfectQuantizer.swift:162–199): SUBJ pixels sharing a display color with far material can inherit far-flavored leftover epochs, inflating S_v toward false BG — the harmful direction. Mitigated by 64-cell pooling and the BORDER buffer; carried to the device gate. (The converse — far pixels inheriting concentrated leftovers — is now correctly caught by the quadratic moment.)
7. **Ruling-3 conformance is by formalism + ladder quantities, not by PE's frame observables.** `walls`, `sOcc`, `mStag`, `ePal` are traced diagnostics only; making them load-bearing requires judging role indices, reintroducing the ANE near-tie leak. The role-field/epoch-field order inversion is stated in §2. **This framing needs Daniel's explicit sign-off**; if refused, the design changes, with the leak as its named cost.
8. **Mirrored-REFINED bytes change** — the mirror-last unification fixes the live index/rgb mispairing (D3); mirrored refined exports differ from today's. Deliberate, inside the contract's "HOW indices/tables are chosen" latitude, called out for the device pass.
9. **D4 contingency** — the gated-depths mechanism rests on the `sanitizedWeight` gate identity and on `depths` having no other consumer inside `refineAuto`; both are asserted by test/audit, with the explicit-parameter (kernel-edit) fallback specified if either fails.
10. **Transcendental threshold constants** — Θ enclosures are derived and interval-certified, but they are pinned numeric constants of a transcendental quantity, a hair beyond "closed-form integer" in the strictest decree reading. Zero fitted parameters holds; flagged for Daniel's interpretation call.
11. **Granularity** — a subject smaller than one 4×4-px × 4-frame voxel cannot earn SUBJ; fast motion lands as BORDER bands — neutral, recoverable at the next 20 cs slice.
12. **Circularity, plainly** — the judgment reads back pass-1's depth decision through the cadence; where depth was wrong at capture, the judgment is wrong the same way, and the orient-consistency check + P17 catch only the gross corruption modes (meters-shaped, contradictory), not subtle depth error.

---

**Decree conformance:** container byte-locked over structural bytes, extensions exempt (P12); ★NO-CAPTURE-TRAINING — all constants derived, zero fitted (P14, with Risk 10's interpretation flag); SIMPLICITY — always-on, no toggle, no settings key, no UI; spec-first — step 1 blocks everything; iterative-not-replacement — pass 2 is pass 1's machinery plus one parameter at the JUDGE-16 seams, the only new module is the judgment. Rulings: (1) the literal `TriScaleLadder` over realized pass-1 indices steers, measurement-only retired by §3's amended header; (2) always-on, full 820-byte/4096-trit mask + threshold-table id riding the trace, reconstructible from the export alone; (3) face and background as the two cadence **ensembles** — order as a per-voxel free-energy sign on the ladder's carriers, TL5's microstates as the traced (and provably cancelling) entropy term, TL7's free blocks consumed as pure-phase certificates, and the border as the literal sign change of the phase field inside the voxel — with depth reduced to a single global consistency check that can only veto, never steer.
