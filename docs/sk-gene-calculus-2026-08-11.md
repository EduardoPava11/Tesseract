# SK Gene Calculus: the math for porting S,K combinators onto the 64³ tower

**Date:** 2026-08-11
**Provenance:** exhaustive size-7 enumeration in `~/SKCentennial` (all 16,896
S,K expressions categorized by halting time under leftmost-outermost
reduction; 2 divergers), after Wolfram, *Combinators: A Centennial View*
(2020). Executable laws: `spec/neural/SKGeneCalculus.hs` (gates SK1–SK10).

**The ask:** train a model that learns `2×2×2 ↔ 1` in color latent space, so
that S,K permutations become *genes* activated at runtime. S = expansion,
K = contraction.

**The abstraction (the whole point):** do NOT train 16,896 genes. Train **two
primitive maps** — one binary expansion, one binary contraction — and obtain
every gene as a composition. The calculus supplies the composition rules; the
enumeration supplies the gene taxonomy; the tower supplies the space the
genes act on.

---

## §1. Two primitives generate everything

Let L be the color latent space (OKLab-derived, dimension d abstract).

    σ : L  → L²     primitive expansion   (the S side: copy + differentiate)
    κ : L² → L      primitive contraction (the K side: merge + discard)

The octave maps are the **cube** of the primitives, folded over the
2×2×2 block's fixed depth-3 octree (axis order x, y, z per the weave-order
convention — 7 internal nodes):

    Ŝ = unfold of σ, three levels : L  → L⁸    (1 → 2 → 4 → 8)
    K̂ = fold   of κ, three levels : L⁸ → L     (8 → 4 → 2 → 1)

So `2×2×2 ↔ 1` is not an 8-ary problem; it is a binary problem instantiated
three times. Everything the model learns lives in (σ, κ).

## §2. The retract structure (the exact laws)

    Law A (retraction)   K̂ ∘ Ŝ = id_L          "one cell survives the round trip"
    Law B (idempotent)   ê := Ŝ ∘ K̂,  ê∘ê = ê   (follows from A)

(L, Ŝ, K̂) is a **section–retraction pair**: L ◁ L⁸. The image M = im(Ŝ) ⊂ L⁸
is the *parent-coherent manifold*; ê is the projector onto it. Law A at the
octave follows from the binary law κ∘σ = id by the fold/unfold structure.

**Why the tower makes it type-free.** Combinators are untyped: any term
applies to any term. A fixed map L → L⁸ is typed. The resolution is Scott's
reflexivity move (D∞), done *spatially*: the pyramid uses the **same** latent
space L at every scale, so contraction (descend one level) and expansion
(ascend one level) are endo-operations on the tower. The pyramid's
self-similarity is the reflexive object.

**Boundedness is a theorem, not a compromise.** Nontrivial combinatory
algebras are infinite (Barendregt); no exact combinatory algebra exists on a
256-codebook or a finite pyramid. Therefore the port is **bounded
combinatory dynamics**: the laws are enforced up to a *derived* horizon
(UNROLL = 16 steps, §5) and divergence means *saturating block capacity*,
not literal infinity. 64³ PINNED is the physical bound that makes this
honest.

## §3. Haar skeleton: laws by parameterization, not by penalty

Index the block corners by ε ∈ {0,1}³. The characters of (ℤ/2)³ are
χ_w(ε) = (−1)^{w·ε}, w ∈ {0,1}³. Analysis and synthesis:

    parent  a   = (1/8) Σ_ε b_ε                       (DC, w = 0)
    details d_w = (1/8) Σ_ε χ_w(ε) b_ε   (w ≠ 0)      (7 of them)
    b_ε         = a + Σ_{w≠0} χ_w(ε) d_w              (exact reconstruction)

Band structure by Hamming weight |w|: **3 axis + 3 edge + 1 corner = 3:3:1**.
(Distinct from PP1's cross-scale 3:2:1 — do not conflate: 3:3:1 is
within-octave, 3:2:1 is across the 16/32/64 ladder.)

**Parameterize so Law A cannot fail:**

    K̂(b)   = (1/8) Σ_ε b_ε                            (exact DC — pure weakening)
    Ŝ_g(x)_ε = x + Σ_{w≠0} χ_w(ε) g_w(x)              (g_w : L → L learned)

Then DC(Ŝ_g(x)) = x for **every** choice of g, because Σ_ε χ_w(ε) = 0 for
w ≠ 0. Law A holds *by construction* — no round-trip loss term, no naked
constant. The entire trainable content of expansion is the **7 detail
generators g_w**: the conditional prior p(details | parent, context) — this
is wavelet-domain super-resolution, one octave at a time. A learned κ
correction beyond DC is admissible only if it vanishes on im(Ŝ).

## §4. Copy/erase, and the palette as the classical basis

Curry–Howard reading: **K is weakening** (erase an argument), **S contains
contraction** (duplicate an argument). Linear logic makes the two structural
rules explicit as a comonoid: copy δ: L → L⊗L and erase. In our port, σ *is*
the copy and κ∘σ = id is the Frobenius "special" law.

Classical-structures theorem (Coecke–Pavlović–Vicary): the exactly-copyable
states of a copy map form a **basis**. Port this as a constraint:

    σ(c) = (c, c)  and  κ(c, c) = c   exactly, for every dyad-256 codeword c.

Off-codebook latents copy only approximately. Consequences:

- **The palette is the classical basis of the gene algebra.** S-duplication
  is exact precisely on palette codewords (the palette IS the image, again).
- The **copy defect** ‖σ(x) − (x,x)‖ is a per-cell classicality measure —
  a derived scalar that feeds the phase machinery (E_var temperature axis).

## §5. Gene semantics: activation at runtime

**Gene pool** = all size-7 S,K terms: |SK₇| = Catalan(6)·2⁷ = 132·128 =
**16,896**. A gene g activates at cell x, level ℓ by seeding the term g·x
and performing **one leftmost-outermost reduction step per frame**:

- each **K-event** fires a contraction: the argument block is erased, its
  content summarized down the ladder by K̂ (the DC of what is discarded may
  tint the parent — the residue of erasure);
- each **S-event** fires an expansion: the argument is copied and
  distributed up the ladder by Ŝ (exact on palette codewords, defective
  elsewhere — chaos leaks in exactly where the image is least classical).

**Exact size dynamics** (leaf count; proved per-event in the spec):

    K x y  → x            Δ = −(|y| + 1)  ≤ −2     strict contraction
    S x y z → x z (y z)   Δ = |z| − 1     ≥  0     expansion iff z compound

    Bookkeeping identity: |final| − |initial| = Σ_S (|z|−1) − Σ_K (|y|+1)

Corollary: divergence requires unboundedly many S-events with growing
arguments; K-density forces halting. Both actual divergers are pure-S.

**Gene taxonomy** (from the exhaustive run; regression-pinned in SK2):

    halting time t :  0     1     2     3    4    5   6   7  8  9  10 11 14 15   ∞
    count          : 2128  6976  4540  2204 723  204  77  25  4  3  6  2  1  1    2

- **ORDER genes** (t ≤ 2): 13,644 of 16,896 (80.8%) — transients that settle
  almost immediately.
- **BOUNDARY genes** (3 ≤ t ≤ 15): 3,250 — the critical tail; longest halter
  `s[s[s[s]]][s][s][s]` at t = 15.
- **CHAOS genes** (divergent): exactly 2 — `s[s][s][s[s]][s][s]` and
  `s[s[s]][s][s][s][s]` — the immortal genes; size grows ~exponentially
  until block capacity clamps it (bounded-divergence rule). Their measured
  growth rate is the CHAOS temperature constant — derived, not chosen.

Phase assignment rides the existing law (subject→ORDER, boundary→critical
tail, background→CHAOS, per phase-palette); the t-binning above is the
distribution's own head/tail split and should stay derived (DepthMixture
pattern) if it ever becomes a threshold in code.

**Derived constants (no naked constants):**

- **UNROLL = 16**: max halting time over SK₇ is 15, plus one idle step.
  Gate SK5 proves classification at cap 16 ≡ cap 1000. This is the ANE
  fixed-iteration trip count (fuse one static 16-step graph; 0.23 ms
  dispatch floor ⇒ one dispatch per activation).
- **Fixed-point law**: the step function is the identity on normal forms
  (gate SK9), so halted genes idle safely inside the fixed unroll.

## §6. Training program (NO-CAPTURE-TRAINING compliant)

Corpus: the GIF89a statistical-variance sampler (synthetic), in OKLab.
Nothing here requires captures; eval is synthetic; device feel is the only
real gate.

Learn, in order of consequence:

1. **g_w** (7 detail generators = the S side): match the corpus conditional
   statistics of Haar details given parent — mixture-fit machinery per the
   DepthMixture pattern, no thresholds by hand.
2. **κ correction** (optional, K side): robust merge beyond DC, constrained
   to vanish on im(Ŝ) so Law A survives.
3. **Codebook classicality**: project dyad-256 codewords to fixed points of
   copy (σ(c) = (c,c), κ(c,c) = c) — a constraint, not a loss.

Structural guarantees (Law A, DC exactness) are by parameterization (§3) and
cost zero loss terms.

## §7. Swift/Metal hooks (later, not now)

- (σ, κ) as tiny per-axis maps (matrices/MLPs) — the *only* weights.
- Gene table: 16,896 × (term, halting time, phase class) precomputed by the
  Haskell enumeration and shipped as data.
- Activation: one fused 16-step ANE graph per the ANE loop design; gene
  choice indexes the table, never changes the graph shape.
- Relation to `spec/neural/Gene.hs` (the 4,548-param capsule): orthogonal
  for now. The SK gene is a *compositional program over two primitives*;
  the capsule is a monolithic policy. If they meet, the capsule's role is
  to *choose which SK genes activate where* — selection over programs, not
  weights.

---

## §8. Axis-typed calculus: x, y, and t (ruling 2026-08-11)

The third axis of the capture cube is **time** — the 4³ blocks are
spacetime blocks (ANELoop AL2). So the octree's three levels are one
expansion/contraction per axis, and the primitives become **typed**:

    σ_a : L → L²,   κ_a : L² → L,   a ∈ {x, y, t},   κ_a ∘ σ_a = id

Six operator tokens total: (S,x) (S,y) (S,t) (K,x) (K,y) (K,t).

- **σ_t is temporal expansion = frame synthesis** (the gene *animates*:
  its S_t events generate frames — GIF as temporal dither, made literal).
- **κ_t is motion contraction** (a motion summary descends the cadence).
- σ_x, σ_y / κ_x, κ_y are the spatial super-resolution / pooling pair.

**Separability is exact** (gate AX1): three binary Haar stages applied
t→y→x equal the direct (ℤ/2)³ character transform and invert exactly. The
octave really is the *cube* of the 2-point primitive — so per-axis learned
operators compose to a lawful octave with no new assumptions.

**Axis clock**: a reduction event at redex App-depth d acts along axis
(d mod 3), the octree's axis cycle. Derived, not chosen: term depth = tower
level, tower level = axis phase.

## §9. Learned semantics: the symbols stay symbols

Ruling: the model learns WHAT S and K do. So §3's Haar anchoring demotes
from *definition* to *initialization/skeleton*, and the calculus's real
export becomes **data**:

    every reduction step  =  one (state, action, next-state) tuple
    state      = term embedded in the tower (latents on blocks)
    action     = the typed token (symbol, axis) — 6-word vocabulary
    next-state = the reduct

**Reduction is an invariance.** Two terms related by a reduction step
denote the same value; the latent space must learn the quotient. Training
pulls the latent of the redex (given the action token) onto the latent of
the reduct — prediction in representation space, never in pixels. What
"S" and "K" *mean* is then whatever operator networks make these
predictions succeed; the only hand-imposed structure left is the retract
law (§2, kept by construction) and the classical-basis constraint (§4).

Note S's full shape: S f g u → (f u)(g u). Expansion is **copy +
differentiate** — the two children share u but are transformed by
different contexts f, g. So the downward predictor must emit *jointly
distributed siblings* conditioned on (parent, operand latents, token, z),
where the latent z absorbs the one-to-many of expansion — z is exactly
the 7-detail slot of §3.

**The corpus card** (exact, pinned in SKGeneSemantics.hs AX2–AX5):

    27,419  typed reduction pairs at UNROLL=16 (= Σ t·n_t + 2·16)
     6      actions, all realized — histogram:
            K: 7441 (x) / 6892 (y) / 4649 (t)
            S: 3988 (x) / 2995 (y) / 1454 (t)
    2,692   distinct normal forms among the 16,894 halters —
            the semantic quotient: the denotation space is 2,692
            attractors + 2 orbits, NOT 16,896 points
    1,148   size of the largest denotation class
    41      max term size on any halting trajectory (= max NF size)
    187     max term size a diverger reaches at the unroll horizon
            — the per-activation capacity the tower must host

The quotient is the point: 16,894 genes but only 2,692 meanings. A latent
space that separates 2,692 attractors (plus 2 orbits) has fully learned
the semantics; gene diversity beyond that is *trajectory* diversity —
different paths through latent space to the same attractor, which is
exactly what plays as animation.

## §10. Is H-JEPA the right model? Yes — as the chassis, with three additions

H-JEPA is the only mainstream family whose losses live **entirely in
latent space** (matches the ruling; no pixel reconstruction, no
reconstruction bias), whose **hierarchy** matches the tower, and which has
a proven **action-conditioned rollout** variant (V-JEPA 2-AC for robot
control; DINO-WM for world models on frozen features). The mapping:

    calculus                          H-JEPA piece
    ─────────────────────────────────────────────────────────────
    latent L, same at every scale     shared representation space
                                      (the reflexivity of §2)
    κ_a (K-side)                      upward predictor (children → parent
                                      target from the EMA encoder)
    σ_a (S-side)                      downward predictor + latent z
                                      (z = the 7-detail slot)
    (symbol, axis) token              action conditioning (V-JEPA 2-AC)
    reduction step                    world-model rollout step
    27,419 typed pairs                the (s, a, s′) training set
    2,692 normal forms                attractors; denotation = invariant
    2 divergers                       non-contracting orbits (CHAOS)
    EMA target encoder                targets at every scale + anti-collapse
    UNROLL = 16                       fixed rollout depth (fused ANE graph)

What stock H-JEPA does **not** give — the three additions the calculus
supplies:

1. **Law losses**: reduction-invariance (this section) and the emergent
   algebra check — with app: L×L → L the learned application,
   app(app(k̂,f),ĝ) ≈ f̂ and the S-law become *measured residuals* on
   held-out synthetic terms, not assumptions.
2. **Retract by construction** (§2–§3): stock JEPA has no section–
   retraction structure between scales; ours is exact and free.
3. **Classical basis** (§4): dyad-256 codewords as the exactly-copyable
   states; stock JEPA has no quantized classical structure.

Dispatched alternatives (research-driven, not a menu): pixel autoencoders
and VQ-VAE train in pixel space (violates the ruling, imports
reconstruction bias); latent diffusion could model the one-to-many of σ
but its iterative sampler does not fit the one-fused-dispatch ANE budget —
if the z-prior ever needs more than a small MDN, bolt a distilled sampler
on *later*; neural program interpreters (NPI-line) supervise execution
traces — we keep exactly their good idea (traces as supervision, symbols
as conditioning) inside the JEPA loss, without their pixel-free-ness
problem in reverse. Verdict: **action-conditioned H-JEPA + the three
additions**. Train Mac-side on the synthetic corpus; runtime stays the
fixed 16-step fused graph of §5.
