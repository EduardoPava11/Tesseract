# Descent-ladder J2 — first trained model (2026-08-12)

**Verdict: all gates green.** The learned commitment scorer beats the
analytic greedy-L2 descent against the exhaustive teacher on 32
held-out trees it never saw, at 1,601 parameters.

| Exit (val, unseen trees) | net | greedy-L2 | teacher |
|---|---|---|---|
| 2-class  | **0.9624** | 0.9588 | 1.0 |
| 16-class | **0.8923** | 0.8807 | 1.0 |
| leaf     | **0.8923** | 0.8807 | 1.0 |

Gates: G1 determinism ✓ · G2 net ≥ greedy on val leaf ✓ (+1.16 pp) ·
G3 output nesting structural (DL2) ✓ · G4 residual errors are
near-ties ✓ (median teacher margin at errors 0.0013 vs 0.0048 at
hits — 3.6× tighter, the XP2 posture measured) · G5 params
REPORTED: 1,601 (sizes are device decisions, never targets).

## The architecture the first run taught us

Run 1 (all three stages learned) measured the truth: the net BEAT
greedy at octet commitment and LOST at the leaf, where L2 argmin is
provably optimal given the octet. So the shipped shape is hybrid —
**learn only the commitment (stages 1–2), keep the exact law at the
leaf.** Leaf accuracy = commitment accuracy identically, because a
correct octet makes the exact within-octet argmin agree with the
exhaustive teacher by construction.

The winning feature was the **lookahead radius greedy ignores**:
each candidate node's remaining spread (analytic, free from the
tree), plus the whitened (Mahalanobis) difference. Greedy compares
distances to node MEANS; the exhaustive winner depends on where the
node's LEAVES land — mean + spread determines them exactly (the
tree is analytic), so commitment is learnable in principle to 100%.

Corpus: 256 synthetic trees × 192 probes (make corpus-descent,
self-gated emitter), split 224 train / 32 val by tree. Scaling
trees 48→256 was what closed the generalization gap (train-only
wins are worthless across palettes).

## Open (in order)

1. mlpackage fold (MIL Builder, DyadAssign pattern): fused
   free-descent graph — stages as batched matmuls with folded
   weights, argmax+gather between stages, exact-argmin leaf stage.
2. Full-PCA corpus manifold (mirrored Jacobi + parity gates).
3. XP2 parity harness vs the exact CPU search on the Swift side.
4. Placement: gated on the A19 bench (⌘U) + device pass. The win
   to beat on-device: 18 candidate scorings vs 128, IF the bench
   says the dispatch shape pays.
