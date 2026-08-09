# DITHER-NN: the 256-color dither CNN stack + the frame-delta model

*Plan of 2026-08-09, produced by a research + design + judge workflow
(3 research agents over the repo / prior-art memories / literature,
3 independent designers, 1 adversarial judge). Status: PLAN — nothing
here is implemented.*

## 0. The ask

Two models, both ANE-resident, both serving the DYAD-256 pipeline:

- **Model A — the dither net.** The current assignment is pure
  nearest-color, so face shading ramps band. Train a model on "all the
  ways we can dither 256 colors" and beat nearest-neighbor perceptually
  at 64×64.
- **Model B — the delta model.** Trained on "the 256 deltas between
  the frames": background/lighting changes make the per-frame palette
  solver + assignment misbehave (flicker). Stabilize temporally.

## 1. What three independent designs converged on

The panel produced three full designs from three angles
(self-supervised STE-first; classical-teacher-zoo distillation;
temporal-first ring). They agree on far more than they differ, and the
agreements are the plan's spine:

1. **Dither = a bounded pre-quantization perturbation, not a new
   assigner.** Model A outputs a small OKLab delta (‖δ‖∞ ≤ ~0.03–0.06,
   about half a shell spacing), added to the centered pixel BEFORE the
   existing `−2·P·Cᵀ + ‖C‖²` argmin. The shipped assignment graph, the
   role/bleed selects, and every DY/XP law stay untouched. Zero-init
   of the last layer makes the untrained net **bit-identical to
   today's output** — the current pipeline is the t=0 checkpoint.
2. **Debayer-class trunk.** 4 bias-free 3×3 convs (~6–8k params,
   assert ≤ 8,000), leaky-ReLU 1/16 (fp16-exact), full 64×64
   resolution, receptive field 9×9. No norm, no attention, no stride —
   spatial bottlenecks destroy dither structure.
3. **Baked blue-noise input channels (NIB).** A conv net structurally
   cannot emit dither on flat ramps without a symmetry-breaking noise
   input (Xia's Noise Incentive Block finding). Ship 64 pre-baked
   blue-noise masks, one per frame, as graph constants — temporal
   blue-noise with zero runtime randomness, so the determinism law
   survives.
4. **STE training.** Forward = the hard argmin, bit-matching the
   shipped graph; backward = softmax(−d²/τ), τ annealed. Loss =
   perceptual low-pass reconstruction (per-patch log-MSE, the debayer
   metric) + an **explicit FFT radial-anisotropy penalty** on the
   error image — the literature is unanimous that blue noise only
   emerges with a spectral loss. Supervised regression to
   Floyd–Steinberg outputs is a known dead end (averages the dither
   away); the teacher zoo, if used at all, is a phase-1 warm start.
5. **"256 deltas" = palette-entry deltas (unanimous).** All three
   designs independently chose interpretation (a): the trajectory of
   the **128 free primaries** across the 64-frame ring, [64,128,3]
   (the involution generates the other 128, so "256 deltas" is 128
   free deltas plus their σ-mirrors). Index k means the same binomial
   shell position every frame, so per-index deltas are well-defined
   with no matching step, 32× cheaper than pixel space, and one
   corrected entry de-flickers every pixel sharing it. Pixel-space
   deltas (interpretation b) are **not discarded**: they become
   training-time losses (stable-pixel index-churn penalties,
   ring-average low-pass fidelity at 20 fps) and, in the ring design,
   conditioning channels — but no pixel-delta tensor ships on device.
6. **Model B = tiny 1D circular temporal convs over the 64-frame
   ring** (~2k params, kernel 3–5, entries shared), emitting bounded
   per-entry corrections to the primaries only; complements are
   REGENERATED through the involution + chroma clamp, so DY2 holds by
   construction. Two of three designs ship it on **CPU** (64×128×3 is
   microseconds — dispatch-floor territory where the ANE loses).
7. **One fused mlpackage.** Everything extends the existing
   DyadAssign graph: conv trunk → bounded delta → existing
   matmul/argmin → role selects, one dispatch per capture, fixed
   shapes, no gather/scatter (renders use the one-hot-matmul trick).

## 2. Do this FIRST: the deterministic flicker law (no model)

All three designs flagged the same suspicion independently: part of
the observed palette flicker is likely a **solver artifact, not a
learning problem** — PCA sign/mode flips between near-equal
eigenvalue solutions re-aim the shells frame to frame. The fix is a
sign-canonicalization + canonical shell-ordering law in
`spec/quantization/DyadPalette.hs` (e.g. PC1·L̂ ≥ 0, tie-broken
deterministically), ported to Swift, measured by an index-churn metric
on replayed real bursts.

**Land this before any training** — otherwise Model B is trained
against a bug and the flicker gates measure the wrong thing. It may
capture most of the temporal win for free; if so, ship the law and
shrink (or shelve) Model B rather than force it.

## 3. Model A — DitherResidual (nn/dither/)

- **Inputs** (per frame, full 64×64): centered OKLab pixels [3]
  (the established fp16 conditioning fix — centering is mandatory);
  baked blue-noise NIB [1–2]; palette conditioning as ~4–8 broadcast
  stat channels (centroid, PC axes/σ — the table is a pure function of
  Stats, so stats = table); face mask [1]; optionally Model B's
  per-frame embedding and/or ring channels (temporal diff, previous
  frame's rendered quantization error — the temporal-error-diffusion
  idea from the ring design).
- **Trunk:** 4 bias-free 3×3 convs, ~11–18 → 16 → 16 → 16 → 3,
  leaky 1/16, zero-init last layer, tanh-bounded δ.
- **Output:** δ added to centered lab; assignment unchanged.
- **Laws** (spec/neural/DitherResidual.hs, untrained stand-ins,
  BayerResidual.hs pattern): DR0 identity-at-init (zero net ⇒ indices
  == DyadAssign, exact); DR1 role law under ANY δ (face 0..127, bleed
  band σ-half, far bg 255 — the XP1 quantifier form); DR2 ‖δ‖ bound;
  DR3 determinism (baked noise only); DR4 budget ≤ 8,000 params;
  DR5/DR6 perceptual + churn gates marked VERIFIED-BY-TRAINING.

## 4. Model B — PaletteFlow (nn/palette-flow/)

- **Input:** the ring trajectory of free primaries [64,128,3]
  (+ frame deltas, + shell-radius/ladder-level channels, + per-frame
  stats via 1×1).
- **Trunk:** circular 1D temporal convs along the 64-frame ring,
  shared across entries, ~2k params, zero-init last layer.
- **Output:** bounded per-entry correction (‖Δ‖∞ ≤ ~0.03) to the 128
  primaries; complements regenerated via involution + chroma clamp.
- **Placement:** CPU Swift fp32 mirroring numpy op-for-op (µs of
  work; below the 0.23 ms ANE dispatch floor), same precedent as
  CentroidRefiner — unless fused into the big graph for free.
- **Laws** (spec/quantization/PaletteFlow.hs): PF1 involution exact
  after correction; PF2 drift bound; PF3 flat-trajectory fixed point
  (constant stats ⇒ zero correction); PF4 ring equivariance (rotating
  the 64-frame ring rotates the output); PF5 gamut clamp preserved.
- **Caution (judge-grade risk):** DyadPalette already EMAs the stats
  (DY7); a second smoother can lag genuine lighting changes. The
  luminance-exempt stability masking exists for exactly this, and the
  §2 law may make much of Model B unnecessary — measure first.

## 5. Data pipeline: GIF89a STATISTICAL VARIANCE (nn/dither/data.py)

★ DOCTRINE (Daniel, 2026-08-09): **no training on capture data.**
Not lab dumps, not Photo Booth, not kept GIFs. The models train on
the format's own statistical variance — the space of generating
states the 64³ machine can express. Since DY8 + the STATS provenance,
that space is concrete: a state is 9 numbers (OKLab centroid +
covariance), a capture is a 64-frame ring trajectory through it, and
the state generates BOTH sides of every training pair:

- **the palette**, via the lawful solver (`table = f(stats)`,
  single-valued, byte-exact), and
- **the imagery**, by sampling pixels from the very distribution the
  statistics describe: N(centroid, Σ), spatially shaped.

The corpus is a PROGRAM, not files:

1. **State sampler.** Centroid ~ prior over the sRGB-representable
   OKLab region (uniform — deliberately face-agnostic: the format's
   variance, not a demographic's). Σ = R·diag(λ)·Rᵀ with R uniform
   over rotations (LCG quaternion) and eigenvalues log-uniform across
   the representable range — from collapsed (λ→0, the degenerate
   sample sets DY5 already covers) to gamut-wide. Every DY law holds
   at every sample by construction.
2. **Field generator (Model A's images).** 64×64 pixel labs =
   centroid + chol(Σ)·w(x,y), where w is a unit-marginal Gaussian
   random field with a SAMPLED spatial spectrum (per-octave
   amplitudes): low-frequency-heavy fields are banding country,
   flat-spectrum fields are noise country — the dither-difficulty
   knob is explicit and swept. Masks are synthetic smooth blobs
   (role structure without faces).
3. **Trajectory sampler (Model B's sequences).** Ring-periodic
   Ornstein-Uhlenbeck bridges in stats space (centroid walk +
   covariance walk via log/exp so PSD is preserved — DY7's convexity
   law generalized), plus JUMP events: sudden centroid shifts and Σ
   rotations model exactly the lighting/background changes Model B
   exists for. Trajectory hyperparameters (drift, jump rate, jump
   size) are themselves sampled — the variance of the variance.
4. One SEED drives everything; the corpus regenerates byte-identically
   from (sampler code, seed). Held-out = a disjoint seed range, not a
   withheld subject.

★ RATIFIED (Daniel, 2026-08-09): **fully synthetic, end to end.**
Real captures appear NOWHERE in the pipeline — not in gradients, not
in gates. Shipping gates (DR5/DR6) run on held-out synthetic seed
ranges; the ONLY contact with the real world is Daniel's on-device
feel-test. The prior stays format-uniform (no fitting to kept GIFs).
Trajectories are ring-OU bridges + jump events.

## 6. Training (debayer template, one train.py per model)

Single self-contained MLX script each: one seed, Adam + cosine
1e-3 → 1e-4, in-run law checks, numpy/MLX parity print, emits
weights.npz / weights_fp16.npz / golden.npz / results.json. Losses as
per §1.4 plus: stable-pixel index-churn penalty (depth/mesh masks
stand in for optical flow, luminance-exempt so lighting response — and
the background bleed, which is SUPPOSED to move — is not punished as
flicker), and the SATOR72 ring-average loss (score the 20 fps low-pass
percept over the closed 64-ring, which rewards temporal dithering).
Warm-up epochs on plain fidelity before temporal/spectral terms
(indirect losses fail to bootstrap). Optional curriculum K=16→64→128
primaries to force dither structure early.

## 7. ANE placement + parity

One fused mlprogram extending `nn/dyad-assign/build_model.py`
(fixed shapes, fp16, iOS17+, compute_units ALL): [optional PaletteFlow
head →] involution regeneration → conv trunk → bounded δ → existing
scores/argmin → role + bleed selects. No data-dependent trip counts;
any render/histogram is a one-hot matmul; hierarchical fp16
accumulation for reductions. CPU keeps centering, stats, solver — the
established division of labor.

Numeric chain, debayer/dyad-assign style: float64 numpy reference →
golden vectors → build_model asserts (role law exact; every fp16
disagreement a near-tie, gap ≤ 2e-3; agreement gate) → metal-harness
clone (one run.sh, FP32 ≤ 2e-3) → Instruments ANE-residency check and
**A-series microbenchmark** (the 0.23 ms floor is Mac-measured only).
Known tension to spec honestly: dithering deliberately pushes pixels
toward decision boundaries, so raw index-agreement gates will fall;
the XP2 near-tie law is the right form, but the agreement threshold
may need restating as rendered-error equivalence — renegotiate in
spec, never silently loosen.

## 8. Milestones (composite; each independently verifiable)

- **M1 — Flicker law + metrics.** PCA sign-canonicalization law in
  spec + Swift; churn/banding/anisotropy metrics in numpy; measure
  the deterministic win on ≥ 10 replayed real bursts. Baseline set.
- **M2 — Corpus program.** nn/dither/data.py: the state sampler,
  field generator, and ring-OU trajectory sampler of §5; byte-identical
  regeneration from one seed; held-out seed range declared. Spec-first:
  the samplers get Haskell axioms (PSD preservation, ring closure,
  marginal-matches-stats) before the numpy port. No capture data.
- **M3 — Specs.** DitherResidual.hs + PaletteFlow.hs with untrained
  stand-ins; spec suite grows green (27 → 29).
- **M4 — STE at identity.** train.py with zero-init nets reproduces
  DyadAssign indices exactly over the corpus; gradients pass
  finite-difference checks.
- **M5 — Model A gate.** ≥ +1.0 dB low-pass rendered PSNR over
  nearest-neighbor on the held-out subject; anisotropy below the
  Floyd–Steinberg reference; visual check on ramp stressors.
- **M6 — Model B gate.** ≥ 40–50% stable-pixel index-churn reduction
  vs the **M1-canonicalized** baseline at ≤ 0.2 dB fidelity cost —
  or the honest conclusion that M1's law already took the win.
- **M7 — Ship.** Fused mlpackage (superset graph, same tensor
  contract), parity chain green, Instruments residency + A-series
  numbers in report.md, wired behind the ExportSettings method
  (e.g. `dyad` → `dyad+nn` variant), GIF comment TRACE extended with
  model hashes, consolidated device pass.

## 9. Verdict

*(The workflow's adversarial-judge agent failed on API errors three
times; this verdict is the session synthesis over the three complete
designs, not a fourth agent's output.)*

- **STE-DYAD (self-supervised STE-first) — 8/10, winner on training
  doctrine.** No teacher ceiling, the DR0 identity-at-init floor
  makes the worst case exactly today's output, and conditioning the
  net on 8 broadcast Stats channels (the table IS a function of
  Stats) is the most economical use of the DYAD structure. Weakest
  assumption: self-supervised low-pass losses have degenerate optima
  — its own spectral-loss + bound mitigations are load-bearing.
- **DYAD-RING (temporal-first) — 7.5/10, winner on data + temporal
  thinking.** The lab-dump corpus plan, the M1-first deterministic
  flicker law, and the previous-frame rendered-error conditioning
  channel (true temporal error diffusion; the ring closes) are all
  taken into the composite. Weakest assumption: the two-pass graph
  with a [64,4096,128] one-hot intermediate may fall off the ANE —
  its own 2-dispatch fallback acknowledges this.
- **ZOO-64 (teacher distillation) — 7/10, winner on evaluation.**
  Distillation-to-teachers as a *final* objective is a known dead end
  (blurry teacher averaging), but the dither zoo + fixed judge metric
  is the right cheap M1-adjacent artifact: it makes "beats
  Floyd–Steinberg where banding is visible" measurable before any
  training. Its CPU placement argument for Model B is correct and
  adopted.

**Composite (what §1–§8 encode):** STE-first training with the zoo as
optional warm start and permanent evaluation metric; DYAD-RING's
corpus, flicker-law-first ordering, and temporal conditioning;
ZOO-64's CPU placement for Model B.

## 9b. Addendum (2026-08-09): Model C — DitherCritic, the analyzer

Daniel asked whether a trained model could *categorize and analyze*
dithering (the critic side, vs. the generators above). Literature says
yes, with exact precedent:

- **GIFnets (Google, CVPR 2020)** is our stack's mirror image:
  PaletteNet + DitherNet + **BandingNet** — the third being a trained
  banding *detector* used as a differentiable perceptual loss for GIF
  encoding. A learned analyzer driving a learned ditherer is a proven
  pattern, on GIFs specifically.
- **CAMBI (Netflix)** is the honest counterpoint: a hand-crafted,
  white-box, no-reference banding index with a few visually-motivated
  parameters — for *scoring* alone, no training needed. CBAND-family
  work exists precisely because big CNN critics are too heavy; compact
  models tailored to banding are the norm.
- **DHD (Digital Halftone Database)** work classifies halftone types
  (clustered/dispersed, periodic/aperiodic) — dither-style
  classification is an established, easy supervised task.

**Design:** a debayer-class classifier (≤8k params, or smaller — an
FFT-radial-spectrum → MLP variant may need only hundreds), input a
64×64 rendered frame (or its error image), output: dither family
{banded/none, error-diffused, ordered, blue-noise, white-noise} +
strength. **Labels are free**: the M1 zoo generator renders them by
construction (every training patch knows which ditherer made it) —
self-labeled corpus, no annotation.

**Three roles:**
1. *Corpus audit + regression gates*: "Model A's output classifies as
   blue-noise, never banded or white-noise" becomes a testable law
   alongside DR5/DR6.
2. *Optional differentiable loss* in phase-2 training (the BandingNet
   role) — but the FIXED judge (FFT anisotropy + CAMBI-style banding
   steps) remains the shipping gate, because training against a
   learned critic invites metric gaming (§9 risk).
3. *On-device provenance*: it is small enough to ride the ANE and tag
   each capture's GIF comment TRACE with its measured dither
   character — the machine self-reporting what it made.

Milestone slot: M1.5 (right after the zoo exists, before any
generator training) — it is the cheapest artifact in the plan and
makes every later gate sharper.

## 9c. Addendum (2026-08-09): color theory — why the PAIRS matter to dithering

Daniel's framing: "dithering of colors approximates other colors."
The literature grounds this precisely, and the σ-involution turns out
to be doing more work than we designed it for.

1. **The ditherable gamut is the convex hull, not the palette**
   (Neugebauer halftoning theory: any color inside the hull of the
   primaries is reachable by area coverage; print science tessellates
   the hull and mixes by barycentric weights). Our 256 colors are 256
   points; what the machine can *show* is their hull. The 128
   primaries hug the face's blob — but every σ-pair spans a chord
   straight through the neutral axis, because comp preserves L and
   negates chroma: **the OKLab midpoint of pair (i, σ(i)) is exactly
   the gray (L_i, 0, 0)**. DYAD secretly carries a full neutral ramp,
   reachable only by dithering pairs. (Caveat to measure in the M1
   zoo: physical spatial mixing averages in linear light, not OKLab,
   so the 50% mix lands *near* the L-matched gray, not exactly on it.)

2. **One pair, two spatial regimes** (Chevreul): at LOW spatial
   frequency — the background against the face — juxtaposed
   complements *intensify* each other (simultaneous contrast: "place
   blue next to orange and both appear more intense"). At HIGH spatial
   frequency — pixel-scale dither — the same pair *assimilates* and
   mixes toward neutral (partitive/additive-averaging mixing;
   assimilation-vs-contrast flips with spatial frequency). DYAD
   already uses the first regime (the complementary background IS the
   Chevreul effect); Model A unlocks the second from the same 256
   entries. Same pairs, two perceptual services.

3. **σ-pairs are the uniquely lawful TEMPORAL dither partners**
   (vision science): isoluminant chromatic flicker fuses above
   ~10–15 Hz, while luminance flicker needs 35–60 Hz to fuse. At
   20 fps, frame-alternation is 10 Hz — hopeless for luminance
   dither, right at the fusion edge for pure chromatic alternation.
   Because comp preserves L *exactly*, alternating i ↔ σ(i) across
   frames modulates chroma only — zero luminance flicker by
   construction. The involution is precisely the constraint that
   makes SATOR72-style temporal dithering viable at 20 fps. This
   should become a law for any temporal-dither mode: frame-to-frame
   index changes at stable pixels prefer moves along
   (near-)isoluminant chords — σ-partners first.

4. **Pair beauty is scorable in closed form** (Ou & Luo's two-color
   harmony model, CIELAB, fit to 1,431 judged pairs; extended
   additively to 3+ colors as sums of pair harmonies). No training
   needed — it's a formula. Slot it into the fixed judge and/or as a
   DitherCritic feature head: score the solved palette's pair
   harmonies per frame, and let the M1 metrics report harmony
   alongside banding/anisotropy. Their headline effects (equal-hue /
   equal-chroma harmonious; higher lightness more harmonious) also
   suggest the binomial shells — which hold chroma rings at matched
   radii — are already harmony-friendly by construction.

**Consequences for the models:** Model A's conditioning already
carries the pair structure (primaries + involution); the training
losses should add (a) a hull-coverage feature — how far outside the
primary hull a target pixel lies predicts *where* dithering is needed
— and (b) the isoluminant-chord preference for temporal index churn.
The bleed also gains a theory-true upgrade path: instead of the hue
jumping 180° at the silhouette, the band can DITHER between primary
and partner as t grows — passing through gray exactly as physical
paint would, "bleeding" in the literal color sense.

## 10. Open questions for Daniel

1. "256 deltas": the panel unanimously reads this as the palette-entry
   trajectory (128 free + σ-mirrors). Confirm, or redirect to pixel
   deltas as a shipped input.
2. ~~Lab-dump corpus~~ RESOLVED: no capture data anywhere — fully
   synthetic training AND evaluation (held-out seed ranges); device
   feel-test is the only real gate. Prior stays format-uniform.
   Trajectories = ring-OU + jumps. (All ratified 2026-08-09.)
3. Model B scope: comfortable with "measure M1's deterministic law
   first, possibly shelve Model B" as the honest path?
