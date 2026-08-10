# SESSION RECORD 2026-08-09 — the DYAD machine arc (SUNSET)

One session, spec-first throughout. Commit chain on main:
`d29f4ad` (DYAD-256 machine) → `7d6083e` (PERM-A refocus) →
`7388358` (codebook) → `7074c5f` (phase energies) → `4f1c629`
(solver gate + E_pal axis). Suites at sunset: **spec 30/30,
simulator 93/93**.

## What exists now

- **DYAD-256** (`spec/quantization/DyadPalette.hs`, DY1–DY8): paired
  per-frame palettes — σ(i)=255−i, comp = (L,−a,−b) in OKLab (linear
  involution), 128 primaries on binomial polar shells around the
  face's stats, complements generated. `table = f(centroid, Σ)`
  single-valued (DY8 sign-canonical PCA — the deterministic flicker
  law). Role law v3: face → primaries; background σ-mirror
  PAIR-DITHER band (Bayer 4×4, coverage = pull t, both endpoints
  continuous) bleeding to exact 255.
- **The 64³ machine** (`spec/output/ExportMethods.hs`): methods
  tesseract | refined | dyad behind persisted `ExportSettings`
  (+ BLEED, MIRROR toggles), eligibility fallback, one `GIFMachine`
  choke point. Placement laws XP1/XP2 (role exact on any engine;
  δ-bounded engines flip only near-ties).
- **ANE assignment** (`Tesseract/ML/DyadAssign.mlpackage`, authored
  `nn/dyad-assign/build_model.py`): one dispatch per capture; centered
  OKLab inputs (the fp16 conditioning lesson: 81% → 99%+); exact CPU
  fallback; parity 99.4% with max near-tie gap ~7e-6.
- **Provenance**: every DYAD GIF's comment carries HARMONY (Ou & Luo),
  SETTINGS, STATS v1 (9 doubles/frame — rebuilds every palette byte,
  tested from raw GIF bytes), and ENERGY v1 (E_pal, E_dist, φ, m_st,
  walls, s per frame).
- **UI (simplicity decree)**: loading → preview + record + SET;
  settings cover = CAMERA / LOOK / BLEED / MIRROR; A/B dual-explore
  and elite gallery unreachable (modules compiled, flow never enters).
- **PERM-A** (`spec/quantization/PairPermutations.hs`, PP1–PP7 +
  `nn/perm-a/codebook.json`): the model domain = arrangements within
  binomial tile classes C(16,k). Decoupling (color = k/16, class-only)
  and lawfulness (no permutation leaves its class) proven; Bayer
  exhaustively adjacency-optimal at every class (all 65,536 tiles
  measured); codebook = 80 canonical texture rungs.
- **Phase model** (`spec/statistics/PhaseEnergy.hs`, PE1–PE12 +
  `nn/phase/sweep.py`): E_pal = Σ chroma² with an exact closed form in
  the 9-number state; E_dist = the open-lattice Ising wall energy +
  occupancy entropy; order parameters (φ, m_st, s) separate
  SOLID / NÉEL BAND / FACE. Measured: crossover (ridge d=0.595,
  sub-bin width; no critical point), and s rises monotonically with
  the closed-form variance energy (0.41 → 0.78, saturating when all
  128 primaries engage).
- **Corpus doctrine** (`spec/statistics/StatsVariance.hs`, SV1–SV7 +
  `nn/dither/data.py`): NO capture data anywhere — training AND
  evaluation on the format's statistical manifold (format-uniform
  prior, ring-OU + jumps); held-out = seed ranges; the device
  feel-test is the only real-world gate.
- **Solver port** (`nn/phase/dyad_solver.py`): byte-gated 8/8 against
  `spec/quantization/EmitDyadFixtures.hs` fixtures. Regenerate
  fixtures after ANY solver change.

## Decrees ratified this session

1. SIMPLICITY (UI): one surface; choices behind SET; no menus.
2. NO-CAPTURE-TRAINING: corpora = GIF89a statistical variance.
3. A/B dual-explore deprecated ("no real significance").
4. PERM-A: the model chooses arrangements, never colors.

## Owed (next session picks up here)

- **Consolidated device pass**: loading→preview feel, SET cover,
  bleed v3 Bayer texture on a real face, MIRROR orientation vs
  preview, BLEED off/on, ANE residency + A-series microbenchmark
  (Instruments), harmony/energy TRACE spot-check on a real export.
- **Depth-meters P0** (pre-existing): taints LIVE masks/gauges.
- DITHER-NN plan (docs/DITHER-NN-PLAN.md): M1 metrics measured on
  corpus trajectories → M3 specs → PERM-A classifier in the MLX lab.
- Devil's-staircase check (fine-t index-level band sweep).
- Optional: subject-presence gauge (block-φ bimodality) on the
  surface — Daniel's call under the simplicity decree.
- Ou & Luo constants: one-time eyeball vs the journal paper.
- A/B module deletion pass — ask first.
