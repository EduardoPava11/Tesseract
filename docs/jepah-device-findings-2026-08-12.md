# JEPA-H device findings — 2026-08-12

The first three device captures through the JEPA-H line, reviewed
hard. Every number below was recomputed from the GIFs' own embedded
provenance (comment channels) with independent parsers — no app
telemetry taken on faith.

## The three captures

| | FD48C96C (pre-JepaH) | 11EB44F0 (JH4, split cadence) | 70D4B515 (JH4b, one ring) |
|---|---|---|---|
| unique LCTs           | 64    | 64 (figure halves: 16) | **16 — the slot law, exact** |
| palette churn (B)     | 1.885 | 2.092                  | **1.078 (−43% vs baseline)** |
| figure-half churn     | 1.608 | 1.381 (−14%)           | (whole table holds)          |
| ground-half churn     | 2.161 | **2.802 (+30% — the defect)** | (whole table holds)   |
| chaos bill Σ log W    | 84,573 | 0                     | 0                            |
| STATS log unique lines| 64    | 64                     | **16 — one state per slot**  |
| max σ codes/frame     | 15    | 16 (at the 32-level bound) | ≤ bound                  |

## Finding 1 — the split-cadence defect (JH4 → JH4b)

JH4 froze the stats at the 5 Hz ring through the model but left the
bg-moments triple on the 20 Hz per-frame EMA; capture 11EB44F0's
derived α = 0.949 made that path ≈ raw. Half of every palette
churned against a frozen other half: ground churn +30%. This
violated ruling R2 (one smoothing law for all generating state).

Fix (commit 5d95fd4): the ring carries 9 dims — the 6 corpus stats
dims plus (meanL, meanLnC, log sdLnC). The v7 head is per-dim and
scale-free (whitening + autocorrelation regime), so the learned
regime→kernel map covers the extra dims WITHOUT retraining;
smoothRing is dim-agnostic. Bg gaps carry-fill around the loop
torus. Capture 70D4B515 confirms: whole tables hold per slot,
churn −49% vs the defective build.

LESSON: any state that shapes palette bytes must ride the same
ring. Never leave a dimension on a different cadence.

## Finding 2 — Σ log W → 0 is structural

logW is the chaos entropy bill over ground-half occupancy per 4³
spacetime block. Slot-held palettes make every 4³ background block
land on ONE σ index (the 4-frame slot and the 4³ chaos block are
the same 2×2×2 atom composed twice), so W = 1 everywhere. A
temporal law zeroed a spatial entropy bill.

## Finding 3 — regime coverage (will more training help?)

The head reads only the ring autocorrelations (r1, r2, r3) per dim,
so the training question is measurable: do real rings produce
regimes outside the corpus cloud? FD48C96C traced at α = 1, so its
STATS lines are the RAW ring. Against the corpus regime cloud
(1st–99th pct: r1 [−0.28, +0.82], r2 [−0.46, +0.60], r3 [−0.52, +0.36]):

- centroid l, a, b: INSIDE, densely covered (NN dist 0.016–0.027
  vs corpus self-NN median 0.083). Nothing to gain here.
- log-variances C00, C11: r1 = 0.89 / 0.87 — OUTSIDE the 99% edge.
  Real variance trajectories are more persistent than the most
  persistent ring the sampler generates, because the corpus drew
  σ_q, σ_e from an arbitrary range (0.01–0.06 of dim width) that
  caps the achievable persistence. The head extrapolates smoothly
  there (NN dist 0.043–0.066, still under self-spacing), but it is
  extrapolating.

Diagnostic: nn/jepa/regime_check.py (reads a capture's own STATS
provenance; no capture byte enters any corpus — ★NO-CAPTURE-TRAINING
intact).

## Verdict on "more training"

- More iterations, same corpus: NO. Converged; the ~15% gap to the
  RTS oracle bound is mostly the irreducible cost of estimating the
  regime from 16 slots.
- More capacity: NO. v6 proved capacity re-opens memorization; the
  149-param structural head is why it transferred at all.
- Better corpus: YES, modestly (single-digit churn/RMSE yield).
  The lawful fix kills a naked constant at the same time:

  **α*-UNIFORM CORPUS (proposed JH5)**: the local-level family's
  regime manifold is fully parameterized by the steady-state gain
  α*(q) ∈ (0,1). Sample α* ~ U(0,1) and derive q = α*²/(1−α*)
  instead of sampling σ_q, σ_e from arbitrary ranges. Full regime
  coverage BY CONSTRUCTION — no naked range, no capture data.

Ranking of remaining beauty levers: (1) Daniel's device verdict on
the 5 Hz palette rhythm — no training touches it; (2) the JEPA
encoder's surprise channel, trained but unwired; (3) the α*-uniform
retrain.
