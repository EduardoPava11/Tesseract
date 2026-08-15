# nn/descent: STUDIED AND INTEGRATED (2026-08-14)

Daniel's ruling that closed the lab (2026-08-12): "WHY do you keep
making different paths? DescentAssign vs DyadAssign... we are working
on a model that requires MLX JEPA-H then port to iPhone... for
performance. I want beauty."

Daniel's ruling that finished it (2026-08-14): "this should be studied
and integrated."

This lab drifted into a SECOND assignment path duplicating DyadAssign's
job. The path is closed. The FINDINGS are not: they have been read out
and placed where the code can act on them. This file is the record of
what was learned, where each lesson now lives, and what remains open.

## The measurement (val, 96 held-out trees, 768-tree synthetic corpus)

| pipeline | 2-class | 16-class | leaf | mean excess distortion (OKLab) |
|---|---|---|---|---|
| greedy-L2 (means only)    | 0.9652 | 0.8601 | 0.8601 | 0.000634 |
| lookahead-L2 (lawful)     | 0.9652 | 0.9652 | 0.9652 | 0.000076 |
| net v4 (stage-1 corr.)    | 0.9737 | 0.9737 | 0.9737 | 0.000050 |
| exhaustive teacher        | 1.0    | 1.0    | 1.0    | 0        |

## What was integrated, and where

**1. The guard against greedy descent. THIS IS THE VALUABLE RESULT.**
The obvious "optimization" of the shipped assignment is to walk the
PairTree greedily: 7 levels x 2 evals instead of 128 exhaustive. The
table above prices that idea. It costs 8x the excess distortion and
14 points of leaf agreement. The finding now sits as a standing guard
in the code it protects, `DyadPipeline.assignRoles`, with the numbers
inline, so the next reader who reaches for the speedup meets the
measurement first. An inverse result is still a result.

**2. Why the lawful version does not deploy either.** Lookahead-L2
prices at ~80 distance evals against 128 exhaustive. On the ANE both
are matmul-shaped, so the eval-count saving does not exist where
assignment actually runs (`DyadANE.assign` is tried first;
`assignRoles` is the fallback and the parity reference). The lab's own
honesty note said this and it stands. Recorded in the same guard.

**3. Exactness where the law is not blind.** The contraction sequence
(all stages learned, then commitment, then the stage-1 half choice)
landed on the single decision where the law is provably blind, and
DL6 proved stage 2 EXACT given the half. That is the shape the one
model line inherits: learn only where the law cannot see, keep
everything downstream exact. It is why `assignRoles` and the 32-level
`pairDitherFrame` search stay exhaustive rather than learned.

**4. The corpus emitter and the self-gating pattern.** Carried to
nn/jepa, which is the live lab. `make corpus-descent` still emits this
lab's corpus and stays wired, because the corpus is the evidence
behind the table above and corpora are programs.

**5. DL6 and DL7 stay law.** `spec/neural/DescentLadder.hs`, in the
CORE suite, green. DL6 conditional exactness, DL7 lookahead dominance.
Lookahead-L2 is a lawful ALGORITHM upgrade to assignment. If it ever
ships it ships INSIDE the existing DyadAssign/CPU path, never as a
separate artifact.

## What was NOT integrated, deliberately

**net v4 (5,889 params) and DescentAssign.mlpackage.** The net buys
+0.85pp over lookahead-L2 for an entire second model artifact on the
capture path. The ONE-MODEL decree forbids it and the trade does not
justify an exception. The model line is nn/jepa. `train.py` and
`build_model.py` remain readable as the record of how the numbers were
produced. Do not extend them, do not bundle the mlpackage, and do not
resume this as a path.

## The one open opportunity, awaiting a ruling

The CPU assignment fallback runs 262,144 pixels x 128 candidates per
export. That path is live in FACE mode and in the simulator, though not
on the ANE. Lookahead-L2 would cut it to roughly 80 evals at 0.9652
agreement. It is NOT taken, because it changes GIF bytes and because it
would make the ANE's parity reference approximate. It needs Daniel's
ruling and a device pass, and if taken it goes inside `assignRoles`.

Original results preserved in RESULTS.md for the record.
