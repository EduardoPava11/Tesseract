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

## §11. S(x,y,t) and K(x,y)/K(y,x): the rotation laws (ruling 2026-08-11)

Daniel's observation — S is ternary like the axis triple, K is binary and
ordered — is exact under the axis clock, and it goes deeper than arity.
Gates AX6–AX8 verify all of this on every one of the 27,419 corpus events.

**S(x,y,t) is literal.** An S-redex spine is three App nodes at
consecutive depths d, d+1, d+2 — all three axes exactly once — and its
operands root one per axis phase too: x@a, z@a+1, y@a+2 (a = d mod 3).
S is the intrinsically three-axis operator; there is no "S along one
axis". One S-event engages the whole (x, y, t) frame.

**K is two-axis, ordered, and chiral.** The K-spine covers exactly the
ordered pair (a, a+1) — under the depth clock only the forward-cyclic
pairs (x,y), (y,t), (t,x) ever occur, never the reversed ones. The
discarded operand roots at phase a+1, the kept one at a+2. The mirrored
projection K(y,x) is **not primitive**: keep-right = K·(SKK), size 4
versus 1, taking exactly 3 steps [K, S, K] versus K's single step (AX8).
The calculus *charges for mirrors* — chirality is broken at the primitive
level and restored only by paying leaves and time.

**Reduction twists.** Tracking per-axis App counts exactly (the closed
forms in `predictHist`):

    K-event: kept subtree x re-roots d+2 → d — its every App node
             rotates axis phase by +1. Contraction is a SCREW MOTION
             in (scale, axis-phase), not a plain projection.
    S-event: the copied argument z re-roots d+1 → d+2 in BOTH copies
             (rotates +1), the function context x rotates −1, y stays;
             the spine trades one (a+2)-App for a second (a+1)-App.

So computation does not stay on one axis: surviving content precesses
through x → y → t as it is contracted, and copies precess as they are
made. A gene is a choreography of axis precession — which is exactly what
a spacetime texture wants to be.

**Why halting-bounded genes = threadable inference.** The size-7 halting
prerequisite is a scheduling theorem in disguise:

- SK5: every halter finishes in ≤ 15 steps and SK9: the step function
  idles on normal forms ⇒ ALL lanes run the same fixed 16-step program
  with zero data-dependent control flow — halted lanes idle, divergent
  lanes clamp. Lane-uniform = SIMD/ANE/thread-safe by construction.
- AX5: per-activation memory is bounded a priori (41 for halters, 187 at
  the horizon for divergers) — static allocation per thread.
- AL2 (block decomposition): activations on different 4³ spacetime
  blocks are independent — thread-per-block with no synchronization.
- The vocabulary is 6 tokens ⇒ 6 small kernels; a gene compiles to a
  static schedule of ≤ 16 typed kernel launches, fusable into one graph.

"A model that is aware of computation is a better performer": the model
is conditioned on the computation itself — action tokens, halting class,
NF class id are all compile-time-known conditioning signals (trace
supervision in the NPI/scratchpad lineage). Nothing about the gene is
discovered at runtime; the runtime only *plays* it.

## §12. The gauge principle: axis identity lives in the encoder
       (ruling 2026-08-11, correcting §8–§9's over-typing)

Daniel's ruling: "S(x,y,z) ≠ S(x,y,t) — elements in K(x,y) and S(x,y,z)
are swapable. If we say z == t we doom the Wolfram findings; in latent
space they should be swapable. The identity of x,y,t should live outside,
in the encoder."

This is correct, and the first passer (v1) violated it. The Wolfram
findings — the halting taxonomy, the 2,692-class quotient, the two
divergers — are theorems about the PURE calculus, invariant under any
relabeling of axes. Operand slots are anonymous spine positions, not
physical directions. v1's three axis-typed application maps gave the same
subterm different semantics at different phases — and AX6–AX7 prove phase
PRECESSES under reduction, so v1's meaning was frame-dependent. Wrong at
the root.

**The corrected decomposition:**

    CORE        axis-anonymous. ONE application map; TWO action tokens
                (S, K). Terms encode with no phase anywhere. What
                survives from §8's typing is only what is intrinsic to
                the calculus: spine position (K's chirality, AX8) and
                depth structure. Physical axes never enter.
    GROUNDING   the octree fold's WIRING decides which physical axis
                each level splits. The weave-order convention is a
                gauge choice — a coordinate frame — carrying zero
                learned axis-specific weights. Swapping x,y,t = re-
                wiring the fold; no weights change.
    CONNECTION  the rotation laws (AX6–AX8) are re-read: they are not
                laws of content but of the FRAME — how the gauge
                parallel-transports along the tower (kept subtrees
                precess +1 per contraction). The core is the fiber;
                the axis clock is the connection on the bundle.

The 6-token vocabulary of §8 is thereby demoted to *documentation of the
embedding*: the corpus keeps its axis field (it describes the standard
gauge), but the passer reads only the symbol.

**Empirical confirmation** (train_passer.py v2, gate E1): the
axis-anonymous core reaches rollout→NF accuracy 0.988 vs 0.989 for the
axis-typed v1 — inside the 3σ binomial margin — with HALF the parameters
(8,304 vs 17,760) and a smaller DAG (20,897 phase-free nodes vs 22,440
phase-tagged). Axis identity carried no semantic information, exactly as
the calculus demands. Meanwhile the symbols alone carry sharp meaning:
on held-out pairs where a shuffle actually swaps S↔K, the true token
wins 83.2% (n=1,100, 3σ=0.545). And gate E2: permuting the corpus's axis
labels (x→y→t→x) changes no model input — swap invariance is exact by
construction, checked.

Consequence for the octave codec (§3): σ and κ are ONE binary pair
applied by the wiring to whichever axis a level rides — never σ_x, σ_y,
σ_t as separate weights. §8's per-axis reading survives only as the
grounding's wiring diagram. The Wolfram findings transfer to latent
dynamics verbatim BECAUSE the core is exactly as anonymous as the
calculus that produced them.

## §13. The color-side codec: gap audit, proofs, build (2026-08-11)

Built AFTER the codec-gap-audit workflow, per ruling ("IF you can prove
axioms, and theorems align with the haskell spec"). The audit's verdict:
R1/R2/R7 were closable by proof; two rulings and one spec gap remained;
the sampler-of-record already existed.

**Proofs (spec/neural/OctaveCodec.hs, CX1–CX7, all green, registered):**
the codec's exact laws in the form it is actually built — the composed
binary form σ_g(x) = (x + g(x), x − g(x)), κ = mean, three wired levels.
CX2 is the theorem the audit flagged missing (wired composition preserves
DC for arbitrary per-level, per-position generators — SK7 covered only
the flat form); CX5 aligns composed and flat (constant per-level details
land in character bands w=100/010/001, cross-bands zero); CX6 lifts SK8's
toy classicality to dyad-256 scale via the ∀-codebook annihilator law

    g_C(x) = dist²(x, C) · ĝ(x)

(vanishes exactly iff x ∈ C, any finite C — the palette is an INPUT,
never weights, the same move as the gauge principle); CX7 proves dynamic
per-capture palettes are safe (same ĝ, two captures, each copies its own
palette exactly, cross-palette points defect).

**Adopted derived rulings (Daniel may veto):**
- G1: scale/level conditioning of ĝ is ADMISSIBLE — scale is physical
  (the 3:2:1 ladder already treats levels distinctly), axis is gauge.
  CX2 proves the laws hold either way.
- G2a: classicality by ARCHITECTURAL vanishing (the CX6 mask), never a
  loss term — preserves "structural, not trained".

**Trainer (nn/sk-gene/train_codec.py, D1–D6 all green):** learns ONLY
the conditional detail prior p(d | stage-parent, ctx, level) — a 3,294-
param Gaussian head. Corpus = nn/dither/data.py, the sampler-of-record
((file, seed) → byte-identical; TRAIN/HELDOUT seed ranges disjoint).
Conditioning: stage-parent value + the enclosing split's detail in raw
AND log-magnitude form (wavelet scale persistence, Crouse–Baraniuk–
Nowak) + octave level. Stage index is NOT conditioned on — under the
wiring it is the axis, so conditioning on it would be axis-typing.
Results: ΔNLL −0.87 nats/sample vs the per-level unconditional Gaussian,
cluster-robust across 24 held-out elements (wins 22/24; element-level 3σ
statistics — samples within an element share its field scale, so
effective n is the element count); calibrated (|z̄| = 0.001,
var z − 1 = 0.06, inside element-level 3σ); composed retraction 6e-8
(fp32 rounding); classicality exact against a REAL dyad-256 palette
built by the byte-exact-gated nn/phase/dyad_solver.build_dyad from a
held-out element's masked pixels.

Owed: the fold (build_model.py pattern — both weight sets into fused
graph constants, fp16 centered-input discipline, parity gate vs the
float64 law) and the term↔color coupling (the passer's latent L and the
codec's OKLab octave meet at the grounding).

## §14. The grounding: term↔color coupling (2026-08-11, ruling
       "this sounds like the encoder... train and ensure it learns")

The coupling IS an encoder — and per §12 it is exactly where axis
identity is allowed to live: E reads the block through the wiring.

    E : color octave block [8×3 OKLab, wiring order] → z ∈ ℝ²⁴
        (the SAME latent space the genes live in)

E is the ONLY trainable (nn/sk-gene/train_ground.py, 14,382 params);
passer and codec are FROZEN. Training makes the square commute through
the frozen predictor and frozen token embeddings:

    S-law   pred(E(const(x)), tok_S) ≈ E(Ŝ(x))     (masked codec expand)
    K-law   pred(E(X), tok_K) ≈ E(const(K̂X))       (real-block contract)

E's features are the block's Haar character coefficients (the AX1
basis) + level. Two ingredients proved decisive:

1. **The manifold anchor**: the frozen predictor's vector field only
   MEANS S/K on the gene-latent cloud where it was trained — without an
   anchor E collapsed into regions where the two tokens act alike.
   E's output distribution is moment-matched to the gene_table cloud
   (both moments derived from the table; no naked constants).
2. **Codeword S-pairs in training**: the masked codec gives
   Ŝ(c) = const(c) exactly (CX6/F2), so codewords are legitimate
   fixed-point events — teaching them directly.

**Gates (G1–G6 all green; cluster-robust, derived thresholds):**
- G2 *learns*: on moved events (per-element median split — identity is
  near-optimal where the op changes nothing), coupling error beats
  identity by −0.55 ± 0.14 (3σ).
- G3 *THE COUPLING CLAIM*: swapping the term-trained S/K token on a
  held-out color event costs +0.72 ± 0.03 (3σ) — the tokens learned
  from TERM reduction organize COLOR dynamics through a frozen
  predictor. Term-S is color-expansion; term-K is color-contraction,
  measurably, cross-modally.
- G4 *classicality grounded*: codeword S-displacement 0.013 vs 0.023
  off-palette (3σ) — the palette's classical states are latent fixed
  points of expansion, closing the loop with §4.
- G5 *retrieval*: the predicted latent ranks the true post-event block
  top-1 at 24.5% among 256 per element (chance 0.4%).

The arc is closed: calculus (SK/AX/CX laws) → corpus (27,419 pairs) →
passer (term dynamics) → codec (color octave) → fold (two fp16 ANE
graphs + gene table) → grounding (one encoder joining them). Every
learned map is gated; every law is executable. What remains is
Daniel's: Swift integration rulings, and the device pass.
