# Descent-ladder — performance runs (2026-08-12)

## Where it stands (v4)

Val, 96 held-out trees (768-tree synthetic corpus, `make corpus-descent`):

| pipeline | 2-class | 16-class | leaf | mean excess distortion (OKLab) |
|---|---|---|---|---|
| greedy-L2 (means only)      | 0.9652 | 0.8601 | 0.8601 | 0.000634 |
| **lookahead-L2 (lawful)**   | 0.9652 | 0.9652 | 0.9652 | 0.000076 |
| **net v4 (stage-1 corr.)**  | **0.9737** | **0.9737** | **0.9737** | **0.000050** |
| exhaustive teacher          | 1.0 | 1.0 | 1.0 | 0 |

Error rate vs teacher fell 10.8% → 2.6% (4×) across the performance
runs; excess distortion fell 92% vs greedy. 5,889 params (reported).
Gates G1–G5 all green, including G2 against the STRONGER lookahead
baseline (+0.85 pp) and G4 (residual errors are near-ties: median
teacher margin 0.0009 at errors vs 0.0042 at hits).

## What the runs discovered (each contraction is a law now)

1. **Run 1 (all stages learned)** — net beat greedy at commitment,
   lost at the leaf ⇒ the leaf is law (exact argmin).
2. **Runs 2–3 (learned commitment + spread/Mahalanobis/child
   features, value distillation)** — modest gains, and the
   descendant-summary feature exposed the real find:
3. **Lookahead-L2** — commit to the candidate whose DESCENDANT
   layer holds the nearest point. Stage 2 becomes EXACT given the
   half (now spec law DL6: conditional exactness), stage 1 becomes
   a much stronger baseline (spec law DL7: lookahead dominance).
   A shared learned correction on top of the exact stage HURT it
   (run 3's regression) ⇒ contract the learning again:
4. **v4 — the net corrects STAGE 1 ONLY.** Everything after the
   half choice is law. Features: diff, |diff|, spread, Mahalanobis,
   child distances, and the FULL SORTED 8-descendant distance
   vector (reuse of distances later stages compute anyway).
   Residual-on-spine: at zero correction the model IS lookahead-L2;
   training starts from the strongest lawful baseline.

The learnable surface contracted three times — all → commitment →
stage-1 half choice — landing exactly on the one decision where the
law is provably blind. The remaining 2.6% error is the half-boundary
near-tie region (median margin 0.0009 ≈ one sRGB8 quantum in OKLab).

## Distance-eval budget (honesty note)

Lookahead stages price at ~80 distance evals vs 128 exhaustive; on
ANE both are matmul-shaped, so the deployed win is the multi-exit
ladder semantics + the learned stage-1 slot, not raw eval count —
the A19 bench decides placement shapes (device-measured doctrine).

## mlpackage fold — DONE (2026-08-12)

`build_model.py` → `DescentAssign.mlpackage` (regenerable; not
tracked, per the nn/ artifact precedent): ONE fused graph, fixed
shapes, no loops, no gathers — the conditional selects are one-hot
masks + global argmin (the DyadAssign role-select pattern, ANE-
friendly). Corrector weights folded as constants from
scorer_weights.npz. **Parity gate: 16,384/16,384 = 100% agreement
with the NumPy v4 reference, zero disagreements** (fp32 CPU verify
build; the fp16/ANE variant is a device-bench decision).

## Open (in order)

1. Full-PCA corpus manifold (mirrored Jacobi + parity gates).
2. XP2 parity harness vs the exact CPU search on the Swift side.
3. Placement: gated on the A19 bench (⌘U) + device pass — bench
   the fused graph's dispatch cost against DyadAssign's there.
