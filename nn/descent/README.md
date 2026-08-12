# nn/descent — the assignment descent and the 3-model ladder

Daniel's rulings (2026-08-12, after the adversarial review of the
model-ladder research synthesis — docs/jepa-h-adversarial-review-
2026-08-12.md, where 0 of 6 claims survived as written):

- The capture-assist model's **first job is P4**: hierarchical
  assignment — the pair-tree descent (3 stages, fan-outs [2,8,8],
  18 candidates vs 128 exhaustive) under the XP2 near-tie posture.
- The **3-model ladder is committed structurally**: M16 / M32 / M64
  are ONE descent with three exit depths, nested by **outputs**
  (early exit == quotient of the full answer — spec DL2), never by
  weights (weight nesting would break the DYAD STATS provenance
  law).
- **Corpus = synthetic only** (★NO-CAPTURE-TRAINING). No pixels, no
  captures, no library traces.
- **Sizes, cadences, and K are device-measured parameters.** They
  appear in no law and no corpus property. The A19 bench
  (ANELoopBenchTests, ⌘U on the 17 Pro) and the RATE LEDGER decide;
  citations only motivate.

## Law

spec/neural/DescentLadder.hs — DL1–DL5 green:
DL1 shape (constant serial depth 3), DL2 output nesting (the ladder
law), DL3 separated exactness, DL4 near-tie bound (excess distortion
≤ 2× the smallest stage gap, checked per probe), DL5 corpus law
(deterministic sampler, exhaustive teacher only).

## Corpus

`cd spec && make corpus-descent` → `corpus/samples.jsonl` +
`corpus/manifest.json`, emitted by spec/output/DescentCorpusEmit.hs,
which **self-gates** (leaf count, v7 involution byte law, PT9
node/octet coherence, teacher sanity, determinism) before writing.

Per sample: generating stats (centroid + diagonal variances — the
v1 axis-aligned manifold; full-PCA sampling is J2 and needs a
mirrored Jacobi with parity gates), the 128 clamped figure bytes,
and 192 probes each labeled by the EXHAUSTIVE teacher at all three
exits (leaf / 16-class / 2-class). Coarse labels are quotients of
the leaf label — the teacher nests exactly as the student must.

## Next (J2+, each behind its gate)

1. Train the multi-exit descent net on Mac (MLX): shared trunk,
   three heads at the exit depths; grade each exit against its
   teacher column. Distillation only — the exact algorithm remains
   the law; the net is a placement, like DyadAssign.
2. Full-PCA corpus manifold (mirrored Jacobi + parity vs the
   Haskell spec).
3. mlpackage export + XP2 parity harness vs the exact CPU search
   (the DyadAssign pattern: near-tie flips are the only permitted
   difference).
4. Placement is gated on the A19 bench and a device pass. Nothing
   ships to the app from this lab before those land.
