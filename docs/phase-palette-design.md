# PHASE-PALETTE — the Phase-Diagram Palette Law (design v0)

> **STATUS 2026-08-11:** rulings R1–R5 CONFIRMED by Daniel ("yes
> continue"). Step 1 DONE — spec/quantization/PhasePalette.hs,
> PP1–PP16 all green, enrolled in the Makefile (suite 38/38).
> Step 2 DONE — PhaseTelemetry.swift (bands + chaos bill + PHASE F
> trace line in the DYAD provenance comment; measurement only) +
> PhaseTelemetryTests. Step 3 DONE — scene-fit ground law (PP8):
> GroundMoments moment-matched per capture (uncapped), Wada prior
> on the single-phase/no-evidence path (capped), stats-α EMA on the
> background triple, DYAD STATS v2 trace (rebuildTables reads v1
> and v2), DyadPreview unified. Next: step 4 (flag-gated chaos
> count solver, additive beside the v4 far law per R3).

**Daniel's ruling (2026-08-10, verbatim intent):** the background goes to
CHAOS, the subject stays in ORDER, and there is a BOUNDARY LAYER; do the
math of a phase diagram so that each 64×64 frame's 256 colors best
represent the scene at the 16×16, 32×32, and 64×64 reads; go back to
information theory.

**Provenance:** research workflow `phase-diagram-palette-research`
(11 agents: 3 repo-grounding readers over PhaseEnergy.hs /
TriScaleLadder / DyadPalette+DepthMixture, 4 literature sweeps —
deterministic annealing [Rose–Gurewitz–Fox 1990, Rose 1998],
multi-scale rate-distortion [Zador/Gersho, Equitz–Cover], max-entropy
dither [Jaynes, Ulichney, Schuchman], phase interfaces [Allen–Cahn,
lever rule] — 1 synthesis, 3 adversarial verifiers). Every finding of
the three verifiers is dispositioned in §0; nothing is dropped
silently. Claims are tagged [LIT] (literature), [DERIVED] (provable
from repo objects), [CONJ] (needs proof or measurement).

---

## 0. Defect ledger — every verifier finding, its disposition

Math attack (M), decree audit (C), completeness critic (G).
**Fixed** = this document changed; **carried** = kept as flagged risk;
**ruling** = blocked on Daniel.

| finding | disposition |
|---|---|
| M1 — Gibbs per-voxel minimizers require D linear in p; the pooled M-kernel couples voxels within blocks, so "minimizing F gives Gibbs assignments" is false as a theorem | **Fixed**: the Gibbs family is kept as the *definition* of the chaos ensemble (Jaynes max-ent under the mean constraint, which IS linear), not as the minimizer of F; F's exact minimization is done by the block count solver (§4), never by independent per-voxel sampling. The unbooked randomization variance term is now booked (§6). |
| M2 — PP1 keystone identity verified sound; "for random error fields" qualifier spurious | **Fixed**: PP1 stated for ALL fields. Equitz–Cover demoted to a comment (deterministic pooling trivially costs no rate). |
| M3 — "posterior IS a Gibbs measure with temperature τ" fixes an arbitrary gauge; Allen–Cahn ξ = τ/√2 requires a tuned stiffness κ; both decorative | **Fixed**: demoted to remarks; no downstream quantity uses ξ or the gauge. The load-bearing facts stay: t(s) logistic with slope 1/τ, τ = σ²/Δμ from the fit, width τ·ln 81 exact. |
| M4 — lever rule is not Maxwell (phases at different temperatures, no conserved density); conclusion survives as Bayesian model averaging | **Fixed**: the band law p_v = t·P_order + (1−t)·P_chaos is justified as posterior model averaging over class membership — constant-free, and identical in form. Thermodynamic language demoted to analogy. |
| M5 — λ (conjugate to mean color) conflated with Rose's β = −dR/dD (conjugate to distortion); rung (R_K, D_K) slopes are not RD-curve slopes | **Fixed**: category error deleted. λ remains the max-ent multiplier of the mean-color constraint; the rung slopes are renamed *operating-point slopes*, telemetry only (PP15 weakened to slope ordering). |
| M6 — PP9 "EXACT" contradicts §4's own "to quantization floor"; distance-to-hull clause needs rational projection | **Fixed**: PP9 restated with denominator-64 quantization floor on both clauses. |
| M7 — PP10 false at hull vertices (W = 1 possible); log W = LZW bill contradicts spectrum-blindness | **Fixed**: PP10 restated with the vertex exception; log W demoted from "the byte bill" to a traced lower-bound estimate, regressed against real LZW in step 6. |
| M8 — the doubling ladder is NOT exact for isotropic Gaussians (post-split populations go anisotropic); "1,1 = centroid + birth" underived | **Fixed**: ladder honestly recorded as the frozen heuristic fallback it is (A2 axiom), DA-*inspired*, not DA-derived. Critical-temperature gating stays step 6 research. |
| M9 — Zador allocation and √(5/3) inflation sound; scalar per-class band weight w_i heuristic (M not class-diagonal) | **Carried**: w_i ∈ [1,3] flagged as a bound, not a constant; allocation law uses measured masses/covariances only. |
| M10 — "21/16" white-dither factor unsourced; 3-point convexity contentless | **Fixed**: 21/16 deleted; PP15 = slope ordering only. |
| C1 — void-and-cluster mask carries hidden constants (filter σ, initial density); per-frame lattice shift vector unspecified | **Fixed**: v1 uses NO blue-noise mask. The chaos arrangement law is the deterministic max-log-W count solver + the existing Bayer lattice (crystalline arrangement of a max-entropy *count vector* — entropy lives in the occupancy, arrangement stays constant-free). Blue-noise becomes step-6 research gated on deriving its parameters. |
| C2 — step 4 would REPLACE the v4 binomial far law that Daniel chose twice and device-evidenced | **Ruling R3**: chaos solver ships as an additive, flag-gated mode beside v4; nothing is deleted without sign-off. |
| C3 — AERIAL MIRROR (σ·γ = σ_base, γ-staging, comp-halo) interaction unaddressed | **Fixed**: §4 states the composition: γ-staging is the T = 0 (order/band) geometry and is untouched; the chaos phase operates on POOLED targets c_B computed from staged labs, so σ(s)·γ(s) invariance is preserved by construction. [DERIVED, needs the PP16 axiom.] |
| C4 — PP8 breaks the self-describing-table property (partner half needs background moments not in LCT bytes) | **Fixed**: DYAD STATS trace v2 gains the background moment block; testGIFCarriesItsGenerator law extended, not dropped (§3). |
| C5 — forbidding i↔255−i temporal alternation contradicts the recorded SATOR72 temporal-dither candidate | **Carried**: direction change flagged; the mirror is now a ROLE boundary. SATOR72 note updated when this lands. |
| C6 — band-Bayer-vs-blue-noise "measured decision" had no metric | **Fixed**: v1 keeps Bayer in the band (C1 disposition makes this global); the step-6 comparison metric is named: F itself plus traced LZW bytes. |
| G1 — per-frame vs per-capture table unstated | **Fixed**: per-frame LCTs remain the law (the shipped DYAD contract); the solver is per-frame on EMA'd stats exactly as today. §3. |
| G2 — OKLab mean ≠ OKLab of the physically pooled scene | **Ruling R5**: the reads are DEFINED as OKLab-mean pools (the TL1 lattice sums the ladder already computes). The linear-light alternative is stated with its cost; Daniel picks the read's meaning. |
| G3 — spacetime vs per-frame reads | **Fixed**: the objective uses the ladder's 2×2×2 spacetime pools (TL8's own objects). Per-frame spatial reads are a different ruling; flagged under R5. |
| G4 — subject motion / boundary flicker across 64 frames | **Carried**: the mixture is per-capture (pooled fit, as shipped); per-frame refit is rejected (crossover flicker). Boundary coherence inherits the shipped EMA/α law. Open item O2. |
| G5 — order-phase banding (T = 0 quench dumps gradient error into u4 at 3×) has no v1 law | **Carried**: known artifact class; subject-side noise shaping is step 6 (DBS-lite under the M-kernel). The 3× price is at least now priced. |
| G6 — no codewords reserved for the interface's own mixed colors | **Carried**: the band shows {q, partner(q)} pair-dither; true mixed colors are represented in pooled reads by coverage. Open item O3 if device feel disagrees. |
| G7 — overload (target outside ground hull) has no corrective law | **Fixed**: PP9's floor clause + policy: project to hull, error booked at 3× in u4, traced. Hull expansion is step 6. |
| G8/G9 — u2-stage solver and count-vector tie-break unspecified | **Fixed**: tie-break = max log W, then lowest-index lexicographic (DY-style determinism); the u2 stage is greedy within TL6's 7 freed dof per transition, existence guaranteed by TL5/TL6 telescoping. [DERIVED] |
| G10 — preview/export parity at 20 Hz unaddressed | **Carried**: preview shows the T = 0 quench + band law (today's DyadPreview); the chaos solver is export-time (rung-16 cadence, 5 Hz budget). Preview ≠ export in the far field is an accepted, flagged gap until device pass. Open item O4. |
| G11 — no byte ceiling for chaos entropy | **Fixed**: traced log W total per capture; no cap in v1 (the ruling accepts the cost), but the trace makes the bill visible before any cap ruling. |
| G12 — R_16/R_32 undefined | **Fixed**: PP15 no longer references rates; only D_K and slope ordering. |
| G13 — single-phase (BIC) assignment law unspecified | **Fixed**: single-phase ⇒ ALL-ORDER (the shipped DM9 behavior: all-face), Wada-prior partner half, chaos solver inert. |
| G14 — band mask decision criterion | **Fixed**: see C6. |
| G15 — "best represents" unfalsifiable before device | **Fixed**: acceptance = measured F decrease on fixture captures (step 2 baselines) + the PP axioms; device feel stays the only real gate per decree. |

---

## 1. The objective — one functional, zero free parameters

One capture is the 64³ spacetime cube of OKLab pixels x_v. Choose a
256-entry table T per frame (128 primaries + 128 generated partners)
and an index field q. Error field e_v = T[q_v] − x_v. The three reads
are the TriScaleLadder pools P_K (exact 2×2×2 spacetime means,
TL1/TL2), and D_K is the per-cell mean squared OKLab error of the K³
read. Minimize

    F[T, q] = D_16 + D_32 + D_64        (equal weights: TL8 ruling)

**PP1, the keystone identity [DERIVED, exact for ALL error fields]:**
with e split into nested orthogonal Haar bands (u4 constant on 4³
blocks, u2 the 2³ refinement, u1 the remainder),

    D_16 + D_32 + D_64 = (1/N) · (3·‖u4‖² + 2·‖u2‖² + 1·‖u1‖²)
                       = (1/N) · (‖e‖² + ‖Π₂e‖² + ‖Π₄e‖²).

Consequences: (i) TL8's three equal reads are ONE quadratic metric
eᵀMe, M = I + Π₂ + Π₄ — a derived low-pass kernel with no knobs;
(ii) the exchange rate between coarse-band and fine-band error is
exactly **3 : 2 : 1** — error moved from pooled bands into u1 by
dithering is discounted up to 3×; (iii) the objective sits in the
model-based-halftoning class [LIT: DBS], with the kernel forced by the
ruling rather than an HVS model.

The entropy term: chaos is NOT a term added to F. The chaos phase is
*defined* (§4) as the max-entropy ensemble subject to pooled-read
fidelity — Jaynes' construction, whose constraint is linear, so the
Gibbs form is legitimate there (M1). F itself is minimized by the
deterministic count solver; the shipped hard nearest-primary pipeline
is exactly F's subject-region minimizer at zero entropy (PP2).

## 2. The phase diagram — order, chaos, and the boundary

All parameters come from the shipped DepthMixture fit
(t(s) = logistic((s*−s)/τ), τ = σ²/Δμ) and measured OKLab moments.
No new constants anywhere in this section.

- **ORDER (t < 1/32):** the T = 0 quench. Hard nearest-primary
  assignment — the shipped ANE one-search, bit for bit (PP2). Zero
  conditional entropy: the subject is a crystal.
- **CHAOS (t > 31/32):** the max-entropy phase. Assignment carries
  maximal index entropy subject to correct pooled reads (§4). Its
  temperature diagnostic is T_bg = 2·λ_max(C_B) — Rose's critical
  temperature of the background's own covariance [LIT], measured per
  capture: at T_bg the one-cluster description is marginal, i.e. the
  background is *held at the edge where structure dissolves*. Traced,
  not tuned.
- **BOUNDARY (1/32 ≤ t ≤ 31/32):** posterior model averaging (M4):
  p_v = t_v·P_order + (1−t_v)·P_chaos. The mixture weight IS the
  posterior — no link function, no constant. The shipped Bayer
  coverage law (σ-side tiles = #thresholds below t, PE7's φ = k/16)
  is exactly this averaging discretized to 16 levels [DERIVED]: the
  v4 band machinery survives as the finite-resolution form of the
  phase-coexistence law. Width stays emergent: τ·ln 81 (10–90%),
  trichotomy at the Bayer extrema {1/32, 31/32} (DM8).

Remark (demoted per M3): the logistic posterior is tanh-family and
interface-shaped; the Allen–Cahn identification is an analogy, and no
downstream quantity depends on it.

## 3. The palette solver — 256 colors for the SCENE

**The allocation phase diagram [DERIVED]:** Zador's density p(x)^(3/5)
would give the background MORE codewords (bigger covariance). The
CHAOS ruling rejects that, and the rejection is exact: in the chaos
phase, fine-band background error is not distortion — only pooled
statistics are. Then the background's codeword demand collapses from
*density coverage* to *hull-and-moment coverage*: enough colors to
span its gamut convexly and match second moments, O(hull vertices),
independent of pixel count.

    ORDER  = density regime  (codewords track the subject, Zador density)
    CHAOS  = hull/moment regime (codewords are mixing vertices;
                                 the INDEX FIELD carries the entropy)

That sentence is the phase diagram.

**Survives exactly:** σ(i) = 255−i; the table law T[255−i] = g(T[i])
(partner half generated, never searched — load-bearing for the ANE
one-search); per-frame LCTs on EMA'd stats (G1); the binomial ladder
[1,1,2,4,8,16,32,64] as the frozen, DA-*inspired* fallback (M8) —
legitimate degenerate-spectrum solution, not a derived schedule.

**Changes (ruling-forced, honest):**
- The partner half g is fit to the BACKGROUND's own measured moments
  per capture (the scene law), keeping the Wada functional family
  (hue mirror, chroma power law, rigid L-shift) but solving its three
  parameters from the capture's background class. The Wada dictionary
  constants demote to the fallback prior for single-phase/thin
  backgrounds — exactly parallel to the ladder's degenerate fallback.
  **[Ruling R2]**
- DYAD STATS trace v2 gains the background moment block so
  testGIFCarriesItsGenerator's self-reproduction law survives (C4).
- Shell radii inflate by √(5/3) — the exact Zador consequence
  (Gaussian^(3/5) ∝ N(c, (5/3)C)), axiom-gated, device-compared
  (PP11; placement optimality stays [CONJ]).
- Nearest-in-partner-half is nearest under g's pullback metric once g
  is not an isometry — stated, not hidden; in the chaos phase
  per-pixel nearest is not the objective anyway.

## 4. The chaos law — the background's index distribution

Per rung-16 spacetime block (4³ = 64 voxels = TL9's
samplesPerJudgment), with n = (n_i) the ground-half index counts:

    maximize  log W(n) = log(64! / Π n_i!)         (TL5's multinomial)
    subject to (1/64)·Σ n_i·T[i] = c_B(block)      (pooled fidelity)

[DERIVED: Jaynes max-ent on the entropy TL5 already computes; the
continuum solution is Gibbs in colors, n_i ∝ exp(−λ·T[i]), λ the
mean-color multiplier — and ONLY that (M5).]

- **v1 solver:** best denominator-64 rational approximation of c_B's
  convex hull weights; ties broken by max log W then lexicographic
  lowest index (G8/G9 — deterministic, PP14). Pooled error hits the
  quantization floor (PP9); out-of-hull targets project, the residual
  books at 3× in u4 and is traced (G7).
- **Arrangement:** v1 arranges counts on the existing Bayer lattice —
  the entropy lives in the *occupancy*, the arrangement stays
  constant-free (C1). Blue-noise/hyperuniform arrangement is step-6
  research, admitted only with derived parameters.
- **u2 stage:** residual freedom after rung-16 exactness (TL6's 7 dof
  per transition, telescoping disjoint) is spent greedily on the u2
  band (PP-c).
- **Aerial composition (C3):** c_B is computed from γ-STAGED labs, so
  the chaos phase sits downstream of σ(s)·γ(s) = σ_base — the aerial
  invariant is untouched (PP16).
- **Temporal law:** the block spans 4 frames; the count constraint is
  spacetime. Background L stays slowly varying; temporal entropy is
  spent in the chroma plane (chromatic flicker fuses ≥ ~10–15 Hz at
  20 fps; luminance does not [LIT]). No i↔255−i alternation across
  the role boundary (C5).
- **The byte bill:** Σ log W over background blocks, traced per
  capture — a lower-bound estimate of the LZW cost of chaos (M7),
  regressed against real bytes in step 6. L2 ("near-zero LZW cost")
  is formally retired; the ruling buys entropy and the trace shows
  the price.
- **TL7 inversion:** the free-block certificate becomes the ORDER
  detector — chaos is anti-concentration (PP10, vertex exception
  noted).

## 5. The boundary layer

Profile = the mixture posterior (crossover, per PhaseEnergy's honesty
clause — finite systems round first-order transitions [LIT]). Width =
τ·ln 81, emergent. Law = §2's model averaging, realized by the
shipped coverage dither; v1 keeps Bayer here (C6). The
no-new-constants axiom (PP7): every boundary quantity factors through
(μ_F, μ_B, σ, π_F, π_B); any increasing affine reparametrization of
depth leaves emitted indices unchanged (DM4 lifted to the palette
law); every literal in the module is an exact combinatorial identity
carrying a derivation comment.

## 6. Multi-scale error accounting

PP1 prices every placement: u4 error (banding) costs 3×, u1 costs 1×.
Dithering is noise shaping — it buys up to the 3× discount by moving
error into u1 [LIT mechanism; the booked randomization variance of M1
is the ‖deviation-from-mean‖² term the count solver minimizes at the
floor]. Side conditions recorded: Schuchman-type decorrelation, and
the hull (overload) condition. Subject-side noise shaping under the
M-kernel is step 6 (G5 carried — v1's known artifact class).

## 7. Candidate axioms (PhasePalette.hs)

- **PP1** band identity, exact for all fields (M2).
- **PP2** quench limit: Temp = 0 assignment == shipped nearest-primary
  search bit for bit (near-tie clause only divergence).
- **PP3** chaos limit: with only the mass constraint, occupancy tends
  uniform on the available ground half; entropy maximal given
  occupancy.
- **PP4** temperature provenance: T_bg = 2·λ_max(C_B) recomputes
  byte-exactly from background-weighted covariance; no other
  temperature literal exists.
- **PP5** coverage law: band σ-side fraction = k/16 exactly; block
  expectation = t·c_order + (1−t)·c_chaos at rational t (PE7 lift).
- **PP6** interface width: 10–90 width = τ·ln 81 exactly.
- **PP7** affine covariance: increasing affine depth maps leave
  emitted indices unchanged.
- **PP8** table functionality: partner half regenerates byte-exactly
  from (primary half, background moments); single-phase ⇒ Wada prior;
  both pure functions; trace v2 carries the moments (C4).
- **PP9** chaos pooled fidelity: in-hull targets are met to the
  denominator-64 quantization floor; out-of-hull error equals
  distance-to-hull at the same floor (M6).
- **PP10** anti-concentration: every chaos block with ≥ 2 available
  ground colors and non-vertex target has W(n) > 1; Σ log W is the
  traced entropy bill estimate (M7).
- **PP11** shell inflation: Zador density of N(c, C) is N(c, (5/3)C);
  radii √(5/3)·ρ_k [density exact; distortion improvement CONJ].
- **PP12** allocation monotonicity: background codeword share strictly
  increasing in its mass and covariance volume; all-subject limit
  recovered as f_B → 0.
- **PP13** mass conservation: TL3 holds on the emitted cube.
- **PP14** determinism: table, counts, arrangement, indices are pure
  functions of (capture statistics, frame index) — byte-identical
  recomputation (DY8 lift).
- **PP15** slope ordering: measured per-rung D_K slopes are positive
  and ordered [measured axiom; no rate claims (M5/G12)].
- **PP16** aerial composition: chaos targets computed on staged labs;
  σ(s)·γ(s) = σ_base holds on the emitted cube.

## 8. Staged implementation — and the rulings that block it

**Step 0 — REQUIRED RULINGS (Daniel):**
- **R1** Promote TriScaleLadder pooling into the palette objective
  (supersedes "MEASUREMENT ONLY" / "no GIF byte depends on it" —
  beyond phase16's ruling 1 scope).
- **R2** Demote Wada dictionary constants to single-phase fallback;
  partner half fit per capture to background moments (changes the
  recorded v5-W table law).
- **R3** Chaos solver ships as an additive flag-gated mode beside the
  device-evidenced v4 binomial far law — nothing deleted (C2).
- **R4** v1 keeps Bayer arrangement everywhere (blue-noise deferred
  until its parameters are derivable) (C1/C6).
- **R5** The read's meaning: OKLab-mean spacetime pools (the ladder's
  own objects) vs linear-light per-frame pools (G2/G3).

**Step 1 — spec only:** PhasePalette.hs, PP1–PP16; prove PP1, PP5,
PP6, PP7, PP9, PP13, PP16 exactly; measured axioms behind fixtures.
**Step 2 — telemetry:** D_K + Haar band split + Σ log W traced on
real captures; no GIF byte changes; establishes PP15 baselines and
the F acceptance metric (G15).
**Step 3 — table law:** background-moment g fit + Wada fallback
(PP8) + trace v2; ANE untouched.
**Step 4 — chaos solver:** flag-gated count solver + Bayer
arrangement as an export mode; band law unchanged; ANE untouched.
**Step 5 — shell inflation** √(5/3), axiom-gated, device-compared.
**Step 6 — research:** critical-temperature shell gating, derived
blue-noise, subject-side DBS-lite noise shaping, LZW-vs-log W
regression, hull expansion.

**Open items:** O1 per-frame table solver cost at 5 Hz cadence;
O2 boundary temporal coherence under subject motion (G4); O3
interface-color codewords if device feel demands (G6); O4
preview/export far-field parity (G10).

Every step compile-only + spec-green; device feel remains the only
real gate.
