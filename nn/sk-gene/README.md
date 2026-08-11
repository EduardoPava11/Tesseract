# nn/sk-gene — the gene passer

The SK gene calculus made trainable. Genes are size-7 S,K terms; the
model learns WHAT S and K do (docs/sk-gene-calculus-2026-08-11.md).

**The gauge principle (§12, ruling 2026-08-11):** the core is
axis-anonymous — ONE application map, TWO action tokens (S, K); the
identity of x, y, t lives outside, in the encoder/grounding wiring.
Axis-typing the operators would make meaning frame-dependent and break
the transfer of the Wolfram findings (which are axis-relabeling
invariant). Confirmed empirically: anonymity costs nothing (E1).

- `corpus/` — emitted by `make corpus` in spec/ (spec/output/SKCorpusEmit.hs,
  self-gated against spec/neural/SKGeneSemantics.hs AX1–AX8):
  27,419 typed reduction pairs, 2,692 NF classes, manifest with pins.
  The axis field documents the standard gauge; the passer reads only sym.
- `train_passer.py` — v2 axis-anonymous reduction JEPA (MLX, Mac-side,
  synthetic-only). One app map folded over a phase-free hash-consed DAG
  (20,897 nodes, 14 levels), 2 action tokens, EMA targets, 8,304 params.
  Gates P1, E2, P2–P4, E1, P5.
- `weights.npz`, `results.json` — v2 artifacts (P5 reload-parity gated).
- `weights-axis-typed.npz`, `results-axis-typed.json` — v1 baseline
  (three axis-typed app maps, 17,760 params), kept for the E1 comparison.

Latest run (2026-08-11, 4000 steps, 19s): 7/7 gates green.
Rollout→NF 0.988 (vs 0.989 axis-typed — anonymity free, E1);
swapping S↔K on held-out pairs loses 83.2% of the time (the two
symbols carry all the semantics); axis-label permutation changes no
model input (E2, exact).

**Color-side codec (built 2026-08-11 after the codec-gap-audit
workflow; doc §13):**

- Contract: `spec/neural/OctaveCodec.hs` CX1–CX7 (7/7 green) — composed
  binary σ_g(x) = (x±g(x)), κ = mean; retraction/projection/classicality
  structural for ARBITRARY generators; CX6 = ∀-codebook annihilator law
  g_C(x) = dist²(x,C)·ĝ(x); CX7 = dynamic per-capture palettes safe.
- `train_codec.py` — learns only the conditional detail prior (3,294
  params, Gaussian head; scale-persistence log-magnitude ctx; stage
  index never conditioned — that would be axis-typing). Corpus =
  nn/dither/data.py (sampler-of-record). Gates D1–D6 green: ΔNLL −0.87
  vs unconditional baseline, cluster-robust 22/24 elements; classicality
  exact vs a REAL build_dyad palette; retraction 6e-8.
- `codec_weights.npz`, `codec_results.json` — artifacts (incl. feature
  standardization for the fold).
- Adopted derived rulings (veto-able): G1 level-conditioning admissible
  (scale physical, axis gauge); G2a architectural vanishing, no loss.

**The fold (built 2026-08-11, `build_fold.py` — the build_model.py
pattern verbatim):**

- `SKGenePasser.mlpackage` — the 16-step gene rollout FULLY UNROLLED
  (UNROLL=16 derived, SK5; halted lanes idle via act mask, SK9; no
  data-dependent control flow). Inputs z0/tokvec/act at B=4096;
  predictor weights folded as constants; fp16, iOS17.
- `SKGeneCodec.mlpackage` — the masked 3-level octave expansion
  (OctaveCodec CX contract). Inputs x0/lev/palette (palette is an
  INPUT — CX6/CX7); dist² in DIFFERENCE form so codeword rows are
  exactly zero even in fp16.
- `gene_table.npz` — compile-time gene data: enc(gene) [16896,24]
  (float64 DAG encoder), token ids, act masks, halt times, nfIds,
  2,692 attractor latents, the 2-row token table.
- Gates (`fold_results.json`): F1 passer parity 99.93% attractor
  agreement on 1,475 held genes, the 1 flip inside the derived
  4·‖Δzn‖ near-tie bound (XP2 law); F2 all 256 REAL-palette codewords
  copy EXACTLY through the fp16 graph; F3 in-graph retraction 2.4e-4
  < the 16·2⁻¹¹ machine bound; F4 off-codebook parity 6.5e-4
  (reported). LOGEPS = 1e-4 is fp16-safe by design (1e-6 is fp16
  subnormal — flush-to-zero would NaN the log).

**The grounding (built 2026-08-11, doc §14):**

- `train_ground.py` — the term↔color coupling encoder E: color octave
  block (Haar-coefficient features + level) → the genes' 24-dim latent
  space. ONLY E trains; passer + codec FROZEN. Laws: pred(E(const x),
  S) ≈ E(Ŝx), pred(E(X), K) ≈ E(const K̂X). Manifold anchor =
  moment-match to the gene_table cloud (derived). Codeword S-pairs
  teach the fixed points.
- Gates G1–G6 green (`ground_results.json`, `ground_weights.npz`,
  14,382 params): beats identity on moved events −0.55±0.14 (3σ);
  ★token transfer −0.72±0.03 (term-trained S/K tokens organize color
  dynamics); ★codewords = latent fixed points of expansion (0.013 vs
  0.023, 3σ); retrieval top-1 24.5% vs 0.4% chance.

Swift/app integration is NOT included: ship copies to Tesseract/ML/
(with the "Model" suffix rename), the wrapper, and any runtime surface
await Daniel's integration ruling (flag-gate culture, phaseChaosLoop
precedent). No captures anywhere.
