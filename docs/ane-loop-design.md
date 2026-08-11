# THE ANE LOOP — latent computation over the signal tower (design v0)

**Daniel's ruling (2026-08-11):** R, G, B, depth have scales and
cadences such that information is preserved and reinforced as signal.
How this signal is passed is up to the latent computation. Loops.
We need ANE loops.

**Grounding:** the phase-palette law (docs/phase-palette-design.md,
PP1–PP16 green), the tri-scale ladder (TL1–TL9), and the measured ANE
reference (arXiv:2606.22283): ~0.23 ms dispatch floor; the widest ANE
win is FIXED-ITERATION numerics fused into ONE static graph (5-point
stencil × 32 iterations ≈ 10× GPU at ≈ 49× energy efficiency); no
data-dependent trip counts; fp16 compute with fp32 accumulation;
matrices fold into the graph as constant weights. The shipped
DyadAssign.mlpackage is one feed-forward dispatch per capture — the
loop is the missing dimension.

---

## 1. The signal architecture the loop lives in

The channels already carry their scales and cadences:

- **RGB** rides the 64-rung at 20 Hz — 64×64 per frame, 64 frames.
- **Depth** is judged at rung 16 at 5 Hz — 64 draws per judgment,
  4096 judgments per loop (TL9: THE RESOLUTION OF DEPTH).
- The pooling tower 64³ → 32³ → 16³ is EXACT (TL1–TL5 lattice sums):
  restriction loses nothing that the coarser read owns — information
  is *preserved* by construction, and the multinomial microstates
  (TL5) say exactly how much fine freedom each coarse cell retains.

**The clock identity (AL8):** 20 Hz / 5 Hz = 4 = the time extent of
one 4³ spacetime block. Between two rung-16 judgments the RGB stream
fills exactly one block. The channels interlock without resampling —
the loop's iteration clock is already in the architecture.

## 2. Three exact facts that dictate the loop's shape

All three are theorems of the phase objective F = D₁₆+D₃₂+D₆₄
(spec/quantization/PhasePalette.hs PP1), proved in
spec/neural/ANELoop.hs:

1. **Band eigen-law (AL1):** the kernel M = I + Π₂ + Π₄ acts on the
   Haar bands as M·e = 1·u1 + 2·u2 + 3·u4 — the bands are M's
   eigenspaces with eigenvalues exactly {1, 2, 3}. The objective is
   DIAGONAL in the tower basis; per-band descent steps {1, ½, ⅓} are
   derived, not tuned (no naked constants).
2. **Block decomposition (AL2):** F splits as an exact sum over 4³
   spacetime blocks — voxels in different blocks never interact
   through M. Blocks are embarrassingly parallel; all coupling is
   inside the 64 voxels of a block (TL9's samplesPerJudgment).
3. **Monotone exchange (AL4):** within a block, a fixed-order sweep
   of single-voxel exchanges, each accepted only when ΔF ≤ 0, is
   monotone in F and needs no convergence test — the trip count is
   compile-time fixed, which is exactly the ANE's hard requirement.

## 3. The loop (v1: algebraic; the latent slot is explicit)

State per 4³ block: the 64 voxel indices (current assignment), the
64 target labs (γ-staged, centered — the DyadAssign conditioning
law), the block's palette slice, and the three band residuals.

One iteration (one sweep, K sweeps fused into the graph):

    restrict   exact block means at 2- and 4-scale (integer-exact
               sums; AL3 mass conservation through every iteration)
    update     per-voxel exchange against the block's candidate
               colors, scored by the EXACT incremental form
               ΔF = 2·⟨e_v + m₂ + m₄, δ⟩ + ‖δ‖²·(1 + 1/8 + 1/64)
               — coefficients are the block volumes, derived;
               accept iff ΔF ≤ 0 (AL4, AL7)
    prolong    corrected residuals redistribute to the finer bands
               (the 3:2:1 exchange rate prices every move)

- **Fixed K.** No convergence test (ANE hard limit). K is chosen as
  a measured worst-case sweep count on the synthetic family; each
  extra sweep is monotone (AL4), so overshoot is safe, never wrong.
- **One dispatch.** All 16³ = 4096 blocks × K sweeps × 64 exchange
  stages fused into a single static graph — the stencil-×-32
  pattern, which is the engine's widest measured win.
- **fp16 discipline:** centered coordinates (the DyadAssign lesson —
  ~10× resolution), fp32 accumulation for the block sums, and the
  acceptance test is a COMPARISON (sign of ΔF), which fp16 can only
  flip on near-ties — lawful either way, the XP2 pattern.
- **Exact CPU twin.** The identical fixed-order sweep in Swift; the
  ANE result must agree up to near-ties (the DyadANEParity pattern).

**The latent slot.** v1's update operator is algebraic (the exchange
under M). The ruling's "how the signal is passed is up to the latent
computation" names the successor: the per-block update can be a
LEARNED operator (a small conv/matmul folded into the graph as
constant weights) trained on SYNTHETIC corpora only (the
NO-CAPTURE-TRAINING decree pattern from Tesseract's sibling), with
the algebraic law as teacher and the axioms as the acceptance gate.
The graph shape does not change — only the folded weights do. That
is the entire migration path: same loop, swappable passer.

## 4. What the loop computes first (placement)

The loop is the missing solver for two open items of the phase
plan, one mechanism for both:

- **Step 4+ (chaos):** the count solver fixes rung-16 pooled means;
  the loop's sweeps spend the residual freedom on the u2 band
  (PP-c's 7 dof per transition) and the u1 arrangement — descent on
  F instead of naive Bayer placement, monotone by AL4.
- **Step 6 (order):** subject-side noise shaping under the M-kernel
  (the G5 carried artifact class — banding at 3× weight): the same
  exchange sweep, run on face blocks, moves quantization error from
  u4 into u1 where the reads forgive it.

Preview keeps the quench (20 Hz budget); the loop runs at export
(and, if the device pass affords it, at the 5 Hz judgment cadence on
the rung-16 state — the clock identity makes that alignment exact).

## 5½. THE OFFSET ARCHITECTURES (Daniel, 2026-08-11: "if we offset
## we can cover more ground")

The compression statement, made precise: each channel's stream is
compressed into its (x, y, t) block components at its rung — the
feed's blocking transpose IS the compression stage. A rung-16 output
is 4 deep in t relative to the 64×64 stream: the first 64×64 exists
at frame 1, but the first 16×16 judgment exists only at frame 4.
Hence the cadence — and the offset question: WHERE the 4×4×4 windows
sit is a free parameter the aligned law never exercised.

The prototype's graph is PHASE-AGNOSTIC (it sees blocks, never
coordinates), so every option below is a CPU-side blocking choice
against the SAME mlpackage. Options:

- **A — ALIGNED (baseline, the shipped semantics).** Hop 4 in t.
  One judgment per 4 frames (5 Hz), each frame in exactly one
  window. Latency up to 4 frames; cost 1×. Block boundaries are
  stationary: temporal seams sit at the same frames every time.
- **B — TEMPORAL POLYPHASE.** Four interleaved partitions at t
  offsets {0,1,2,3}, hop 1: after the 4-frame warmup, a rung-16
  output EVERY frame (20 Hz effective), each covering the last 4
  frames. Every frame boundary is interior to 3 of the 4 phases —
  temporal seams dissolve by averaging. Cost: 4× dispatches naively;
  see E for the amortization that makes it ~1 sweep per frame.
- **C — SPACETIME STAGGER.** Rotate a spatial half-shift (2 px in
  x and/or y) along with the temporal phase — a diagonal lattice of
  offsets, e.g. (t,y,x) ∈ {(0,0,0),(1,2,0),(2,0,2),(3,2,2)}. Covers
  spatial block seams too, at NO extra phase count beyond B's four.
  Caveat (honest): F has no cross-block terms (AL2), so per-phase
  the objective simply SEES different seams; the cross-boundary
  smoothing materializes in the union of phases, and fully pays off
  only when the latent passer (L4) carries state across phases.
- **D — OVERLAPPED OBJECTIVE.** Add the shifted pools into F itself
  (F′ = aligned + shifted; curvature 1 + 2/8 + 2/64, still derived;
  monotone exchange survives). REQUIRES A RULING: F′'s reads are no
  longer the GIF's aligned pools — it changes the objective R1
  confirmed. Held.
- **E — STREAMING WARM START (recurrent cadence).** The loop state
  persists across hops: each new window warm-starts from the
  previous fixed point shifted by the hop, so K_eff ≈ 1–2 sweeps
  per tick instead of K cold sweeps. Combined with B this is the
  live 20 Hz loop at roughly ONE sweep per frame of steady-state
  cost — and AL4 makes every extra sweep safe, so load spikes
  degrade gracefully (fewer sweeps, still monotone).
- **F — PER-CHANNEL RUNGS ("their respective scales").** L rides
  the 64-rung; a, b ride 32 or 16 — chroma subsampling as law,
  consonant with the aerial γ (chroma already compresses with
  distance) and the spectral octave ladder. Changes M per channel
  (derived weights, no new constants) but changes the objective —
  candidate ruling, natural companion to D. Held for Daniel.

**Recommendation: B + E** — temporal polyphase with streaming warm
starts. It is the only option that raises the judgment cadence to
20 Hz, covers the temporal seams, needs no objective change and no
new ruling, and its steady-state cost is ~1 sweep/frame on a graph
whose per-sweep cost the ANE amortizes by construction. Add C's
diagonal stagger if spatial seams show on device; D and F wait for
rulings.

## 5. Staged plan

- **L1 (spec — DONE with this doc):** spec/neural/ANELoop.hs, axioms
  AL1–AL8; the model cube carries the tower, the sweeps, and the
  monotonicity proof obligations.
- **L2 (lab) — BUILT 2026-08-11:** nn/ane-loop/build_model.py →
  ANELoop.mlpackage. B=4096 blocks × K=4 sweeps × 64 stages fused
  (256 stages, ~4k ops; 181 s one-time conversion). GATES: reference
  F 22564 → 5308 (76.5% down, monotone); model output F = 5308.41 vs
  reference 5308.40 — the engine attains the float64 law's objective
  to 5 digits; per-assignment agreement 99.83% (444/262144 flips are
  score-near-ties choosing equally-good candidates — the XP2
  regime). TIMING (M3 Max, indicative): 32 ms steady per dispatch =
  0.13 ms per fused stage — a whole capture's sweep in one dispatch,
  6× headroom inside the 5 Hz budget; with B+E warm starts
  (K_eff 1–2) it fits the 20 Hz polyphase budget. A-series
  microbenchmark still owed on device (L2 exit criterion).
- **L3 (Swift) — LANDED 2026-08-11:** ANELoop.swift = the exact CPU
  twin (the law), the one-dispatch engine wrapper
  (ANELoopModel.mlpackage bundled; "Model" suffix keeps Xcode's
  generated class clear of the enum), and refineFarBlocks — the
  flag-gated consumer (CameraConfig.phaseChaosLoop, default OFF, no
  settings surface): fully-far 4³ blocks only, candidates = the
  block's top-2³ occupied ground colors, per-block centering, inert
  blocks frozen EXACTLY by y := q0 (zero error rejects every
  exchange — no mask input needed). Face/band bytes untouched ⇒
  DY6 band laws hold verbatim; partial (boundary) blocks stay v4.
  Gates: ANELoopTests (AL4/AL5/AL6 on the twin; σ-half closure;
  face bytes fixed; F-never-worse via the PhaseTelemetry kernel;
  flag-off byte-identity) + all DYAD suites green.
- **L4 (latent):** the learned passer — synthetic corpus, algebraic
  teacher, axiom gate. Separate ruling before any training lands.

Open questions for Daniel: (a) K's worst-case budget (measure first,
then pin with provenance); (b) whether the 5 Hz live loop (rung-16
state) ships in v1 or export-only; (c) the latent passer's corpus
family when L4 arrives.
