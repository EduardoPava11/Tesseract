# Depth ↔ Color across the 64/32/16 @ 20/10/5 ladder

*Investigation record, 2026-08-10. 7-agent workflow (3 code readers → 3
independent theory lenses → adversarial judge + synthesis), ~513k tokens.
STATUS: spec phase (steps 1–3) AND the Swift+Metal port (steps 6–7)
EXECUTED same day. The port ships the COMP-HALO default (one search,
ANE untouched); ruling R4 remains open — flipping to faithful-hue is a
localized change when ruled. Remaining: step 4 (Mac census), step 5
(synthetic harness), step 8 (mirror-histogram provenance), steps 9–10
(Mac byte gate + device pass).*

## What exists today (the map)

Depth enters through ONE producer contract (DepthSignal, disparity-affine)
and forks into three couplings that never talk to each other:

1. **TIME** — σ(s) = σ_base·(2−s), σ_base(K) = (K−1)/8: the Gaussian epoch
   cadence. Already K-parametric across 64/32/16 — the preview/export
   unification hook existed all along. Near/far is an EXACT OCTAVE:
   σ(0) = 2σ(1).
2. **COLOR** — the DepthMixture posterior t(s) selects role (face / band /
   far at the Bayer extrema) and weights the stats (1−t), but depth never
   modulates shell radius, level occupancy, or any per-scale palette
   quantity.
3. **TELEMETRY** — Dissonance urgency: the same octave makes full near/far
   contrast land at x = x* exactly (zero tuned constants); depth's native
   resolution is rung 16 (TL9).

Legacy debt found: PerfectQuantizer (tesseract/refined path) still holds
naked constants (0.7 diffusion scale, ±0.2 clamp, 0.6/0.4 subject zones) —
the mixture conversion covered DYAD only.

## The verdict: THE AERIAL MIRROR LAW (synthesis of three proposals)

Three lenses proposed laws (statistical-mechanics "Mirror Binomial",
signal-processing "σ-Crossover QMF", color-science "Aerial Octave"); the
judge verified each against the shipped code, killed two on stale premises
and a τ-collapsing rung-16 fit, and synthesized:

**THE INVARIANT:  σ(s) · γ(s) = σ_base(K)  — at every depth, every rung.**

A pixel buys its temporal octave with a chroma octave. Per pixel:

    ŷ = c_F + γ(s)·(y − c_F),   γ(s) = 1/(2−s) ∈ [½, 1]

- γ's 2 is the shipped cadence octave — **zero new constants**.
- Applied to ALL roles: deletes the band pre-pull g = 1−t AND the chroma
  seam at t = 31/32 that v4 shipped (band labs pulled, far labs raw —
  a real discontinuity the judge verified in DyadPipeline stage 1c).
- Aerial perspective arrives as law: far pixels live on inner-compressed
  shells of the mirror half; hue resolution coarsens with distance exactly
  as the binomial shell counts dictate; simultaneous contrast is free.
- t does COVERAGE ONLY (Bayer routing, DM8 extrema at all rungs);
  emission is always in {q, 255−q} so the involution and the GIF
  contract tests are untouched by construction.
- Stats coherence clause: analyze() runs on ŷ (not raw y) with the R1
  weights unchanged — the shells whiten the same distribution the
  assigner quantizes.
- Fit placement: EXPORT keeps the full-resolution pooled mixture fit
  (TriScaleLadder stays measurement-only, no GIF byte depends on rung
  pooling); only the PREVIEW refits on rung-16 judgments with the
  law-of-total-variance τ-lift (new axioms DM11/DM12 owed).

**Open rulings (Daniel's):**
- R4 aesthetic fork: keep the shipped comp-halo far side
  (partner(nearestPrimary(ŷ))) vs faithful-hue variant
  (255 − nearestPrimary(comp(ŷ))) — one line either way, decide on Mac
  renders + device feel, never an in-app A/B.
- R5: convert PerfectQuantizer's naked constants (out of scope for DYAD).
- R6: ratify that γ (per-pixel geometry) and any future global chroma
  gain (DS17 slot) are distinct.

## The investigation workflow (ordered, spec-first)

1. ✅ **Spec DyadPalette v5** (DONE 2026-08-10, same day): §6c —
   `gammaAerial`/`stageAerial`/`quantizeAerialAt` (comp-halo default) +
   `quantizeAerialFaithfulAt` (R4 variant, both spec'd, neither chosen).
   Axioms DY9 (invariant EXACT in rationals for K ∈ {64,32,16}, octave
   [½,1]), DY10 (seam-death: pair is t-free, staging 1-Lipschitz in s,
   s = 1 reduces exactly to the raw face select), DY11 (σ-half spread,
   chroma octave ratio exactly ½ at s = 0, and the MEASURED R4 datum:
   faithful-hue is aggregate-closer to ŷ on the σ side than comp-halo),
   DY12 (stats-on-ŷ: single-valued, involution byte-exact on staged
   tables, centroid stable across depths). DY1–DY8 pass unmodified.
2. ✅ **Spec DepthMixture DM11/DM12** (DONE): §4b `judgment64`
   (binomial(6), exactly 64 samples) + `plantedCapture` + `liftedFit`.
   DM11: the naive rung-16 τ collapses (> 10×) while the
   total-variance lift recovers (s*, τ) within 0.005 / 5%. DM12: the
   naive gap grows with within-judgment variance; the lifted gap stays
   bounded. Suite 36/36.
3. ✅ **Spec stats-on-ŷ** (DONE, folded into DY12).
4. **Mac baseline census**: parse the library's exported GIFs (STATS +
   DYAD MIXTURE comments), histogram mirror-half occupancy; v4 baseline —
   confirm the δ-at-255 is gone.
5. **Synthetic pushforward harness** (sampler program, NO-CAPTURE-TRAINING
   safe): planted depth × GIF89a-variance color fields at K = 64/32/16;
   assert the invariant, aerial-curve recovery (constant-chroma ramp →
   1/(2−s), far/near ratio → ½), predicted vs realized shell occupancy.
6. **Swift port** (only after 1–3 green): one-line staging change in
   DyadPipeline stage 1c; ANE mlpackage UNCHANGED; involution tests
   untouched.
7. **Preview**: DyadPreview's 5 Hz fit → the τ-lifted rung-16 fit.
8. **Provenance**: append the 8-bin mirror-level histogram to the DYAD
   MIXTURE comment.
9. **Mac generator round-trip gate**: rebuild tables AND index fields
   byte-exactly from GIF comments alone.
10. **Device pass** (the only real gate): ≥16 varied captures; occupancy
    G-test against each capture's OWN pushforward prediction; boundary
    Mann–Whitney; urgency Spearman join (d̂ = 0.9573); then the felt
    R4 decision.

## PORTED (steps 6–7, same day — the app update)

- **DyadPipeline** (export): stage 1a now γ-stages EVERY pixel about the
  frame's raw (1−t)-weighted centroid, round-trips through sRGB8 (the
  DY12 construction), and solves stats on ŷ; stage 1c runs one search on
  the staged labs for all roles — the v4 band pull and the t = 31/32
  chroma seam are gone. `fars` stays all-false; the ANE mlpackage is
  untouched.
- **DepthMixture.fitLifted** — the DM11 τ-lift as a Swift API.
- **DyadPreview** (preview): the 5 Hz slow state now fits on rung-16
  judgments (4×4 spatial blocks, means + within-variance) with the
  τ-lift; assignment is γ-staged. FACE mode joined the unified preview
  (CPU reference path — ARKit frames have no Metal pipeline).
- **Metal**: new `aerialPreview` kernel — the 20 Hz GPU twin of
  `assignCPU` (meters→signal in-kernel from DepthSignal-supplied
  anchors, sRGB→OKLab, γ staging, 128-primary search, Bayer σ-routing).
  Optional pipeline state; CPU fallback preserved. Preview-only:
  fp32 near-tie flips are the only permitted difference.

## SHIPPED earlier same day (v4 — the workflow's step-0 baseline)

- Binomial background: far = σ-mirror of the pixel's OWN nearest primary
  (DY6 v4 farLaw/farSpread; solid-255 dead). Known v4 blemish: the
  chroma seam at t = 31/32 — exactly what the Aerial Mirror Law's γ
  staging is designed to dissolve.
- Preview/export unification v1 (DyadPreview: 20 Hz assignment, 5 Hz
  per-frame fit — to be upgraded to the τ-lifted rung-16 fit in step 7).
- Palette-creation visibility (per-frame table published during
  processing), GIF library with palette + provenance review.

*Full workflow transcript: session task wfs6bv8mw; per-agent results in
the workflow journal.*
