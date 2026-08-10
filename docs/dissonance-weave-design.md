# FINAL DESIGN — DISSONANCE WOVEN: octaves→color, depth→urgency, the archive as a live set

**Winner: SPECTRAL PALETTE** (both judges, 35/35 and 35/35-tiebreak), with five grafts adopted from the judges' consensus: (1) the tuned constant `s_t` is **deleted** and replaced by SET-LIST DISSONANCE's derived σ(d)-as-critical-band calibration (SD7's `Δc = 2σ_base ⇒ x = x*` theorem); (2) the **strict byte posture** — no new GIF bytes until a decreed contract amendment; (3) the **χ eye-kernel** (CIEDE2000-resolution Sethares over CIELAB) as the eye-side dual on every archive edge; (4) LADDER-OCTAVE's **F0-lock theorem** (the byte-locked container makes every archive a harmonic scale on one 0.3125 Hz fundamental); (5) the **dip-survival honesty discipline** (every port states which consonances survive at its resolution). Judge split on SD12's `⌈2n/3⌉` dramaturgy peak is reconciled by **demoting it from axiom to named design parameter** (judge 1's re-labeling demand, judge 2's graft — both satisfied). LADDER-OCTAVE's LO9 urgency (g of a scaled frequency, no Δf) is **rejected** as kernel misuse per judge 1; its DFT channel-timbre stays in reserve.

---

## 1. The weave, exact

### 1.0 The kernel (one object, three ports)

For components p₁ = (pos₁, w₁), p₂ = (pos₂, w₂) on a perceptual axis with local resolution field CB(·):

```
x = x* · Δ(pos₁,pos₂) / CB(pos_min)
d(p₁,p₂) = w₁·w₂ · g(x),   g(x) = e^(−b1·x) − e^(−b2·x)
```

Pinned constants (Sethares reference implementation, aatishb dissonance-worker.js — **b1 = 3.51**, not the brief's 3.5; state in the spec header):

```
b1 = 3.51   b2 = 5.75   x* = 0.24   s1 = 0.0207   s2 = 18.96
x̂ = ln(b2/b1)/(b2−b1) = 0.220350    g(x̂) = 0.179756
```

Amplitude combination: **product** w₁·w₂ (1993 JASA; exact bilinearity), min-variant noted as accepted alternative. Timbre = finite multiset; D(T) = Σ_{i<j} d(pᵢ,pⱼ); design = local minimization of D over an interval action. Three ports fill the slots three ways; the kernel and its laws are written once.

### 1.1 Octaves in RGB produce color (the quantization port)

**Partials.** Each RGB channel of the 4⁴ lattice is a 4-rung octave comb: level ℓ ∈ {0..3} of channel X sounds at

```
f(X, ℓ) = m_X · 125 · 2^ℓ Hz,   (m_R, m_G, m_B) = (4, 5, 6)
```

— the just triad, R fundamental at P&L's canonical 500 Hz, so the audio critical-band field CB(f) = s1·f + s2 is inherited verbatim (declared as *injection into the reference axis*, per the winner's honesty note). Twelve pinned integer frequencies: R {500, 1000, 2000, 4000}, G {625, 1250, 2500, 5000}, B {750, 1500, 3000, 6000}. Level-aligned cross-channel ratios are exactly 5:4, 6:5, 3:2 by integer cross-multiplication.

**Amplitudes = occupancy.** Per-channel level marginals of the index histogram: exact integer counts summing to 4096 per channel per frame (20 Hz), 262144 per loop — riding the same lawful u64 sum carrier as TriScaleLadder (TL1–TL3; TriScaleLadder.swift RungCube).

**The quadratic form.** The loop's dissonance is a constant-kernel quadratic form in the occupancy 12-vector:

```
D = ½ aᵀG a,   G_ij = g(x*·|fᵢ−fⱼ| / (s1·min(fᵢ,fⱼ) + s2)),  G symmetric, zero-diagonal, ≥ 0
```

G is a compile-time constant — the eye's sibling of E_pal's closed 9-number form (DyadEnergy.swift:41–65).

**Tuning = scale design.** Per loop, sequential guarded grid argmin (1200 steps/octave) of the cross-dissonance places the G comb, then the B comb, at the minima of the loop's **own** occupancy spectrum, with a 1/12-octave pitch-class guard excluding comb coincidence (unison = hue collapse). Uniform occupancy pins (δG*, δB*) = (269, 836)/1200; a dark-skewed occupancy moves δG* to 325 — 56 grid steps ≈ 17° of hue. **No fixed palette is consonant for every image** — Sethares' punchline as mechanism, Daniel's structural rhyme run literally: palette optimization over a perceptual pair metric.

**Color out, three exact maps:**
- pitch class q = frac(log₂ f) → hue angle h = 360°·q (octave equivalence **is** the hue circle; tuned uniform classes at 0°/197°/101°);
- integer octave number → lightness shell on the existing DyadPalette ladder ρ_k = 2k/7;
- the chord (a,b,c)'s circular resultant of three class vectors weighted 2^ℓ → hue + chroma factor (dominant channel pulls hue within 4°; grays a=b=c keep resultant 0.16–0.17 → low chroma).

**The byte contract is a theorem, not a constraint:** the σ-involution T[255−i] = comp(T[i]) is exactly the tritone q ↦ q + ½ (hue+180°, tritone² = id = σ∘σ). The chart colors only the 128 σ-representatives; the involution derives the rest. Any port coloring both halves independently would break DyadGIFContractTests — this one cannot.

### 1.2 Depth produces urgency (the temporal port) — merged form, zero tuned constants

**The graft that changes the winner.** SPECTRAL PALETTE's bond/beat structure is kept; its tuned calibration `s_t = 1.0903 s` is deleted. The critical band of the epoch axis is the shipped cadence width itself.

**Positions.** Depth d sets σ(d) = (63/8)·(2−d) frames (BinomialCadence.swift:57–61). Each depth has a cadence frequency ν(d) ∝ 1/σ(d) (physically ν(d) = 20/(2π·σ(d)) Hz; the formula below is unit-free). Near/far is an exact octave: ν(1)/ν(0) = 2.

**The bond roughness.** For adjacent rung-16 voxels u, v with EMA depths d_u, d_v and exact u64 depth-mass block sums w_u, w_v (depths-as-weights per DyadPipeline.swift:91–93; carrier per TriScaleLadder.swift):

```
U(u,v) = w_u·w_v · g(x_uv),   x_uv = x* · Δν/ν_min = x* · (σ_max/σ_min − 1)
       = x* · ( (2−d_min)/(2−d_max) − 1 ),   d_min ≤ d_max the two depths
```

The local resolution slot is filled by the **farther** voxel's own cadence bandwidth (CB = ν_min, mirroring f_min) — the CIEDE2000 move with a shipped field, not a constant.

**Derived calibration theorem (replaces SP11's fiat).** Because σ spans exactly one octave, full near/far contrast lands at x = x*·(2−1) = **x\* exactly**, and g(x*)/g(x̂) = 0.9961 — the quarter-critical-band roughness peak, 0.4% off maximum, as a *theorem of shipped constants*. The companion within-voxel identity (SD7): epoch centers are spaced Δc = 63/4 = 2σ_base, so the far pole's own epoch spread rides x₁(0) = x*·Δc/σ(0) = x* exactly. Both facts fall out of BinomialCadence's constants; nothing is tuned.

**Consequences, provable:** equal-depth interiors are exactly silent (g(0) = 0); U is strictly monotone in depth contrast and the lattice never reaches past the peak (max x = x* < x̂); U is bilinear in the two masses; and a given depth *gap* beats faster in the near field than the far field (σ smaller ⇒ resolution finer) — a P&L-faithful asymmetry, stated honestly. Sign: **far = volatile = urgent halo, near = stable tonic subject** — the decreed reading (CD4/CD5 banner, face threshold 0.6), CALM SUBJECT / URGENT HALO.

**The clock (TL9, verbatim).** Urgency is a 16³ field: 16×16 spatial × 16 temporal voxels (4×4 px × 4 frames), judged at 5 Hz (100 div 20 = 5), 4096 judgments per 3.2 s loop, 64 draws each (= 64³), on exactly **11776 bonds** = 16 slices × 480 spatial 4-neighbor + 4096 time-wrapped temporal (the NETSCAPE loop closes time into a torus). Pooled: Û = 16-sample envelope (one per 20 cs slice), Ū = loop scalar. The per-voxel pooled margin coincides with phase16-design §2's free-energy margin |S_v − Θ_s| — the same statistic, now with a psychophysical unit.

**What urgency drives (decree-safe, two channels, both index/table choice):**
1. high-U voxels route into the existing bayer4/pairDither bleed band (DyadPipeline.swift:141–151) — urgency renders as σ-mirror shimmer at the Néel frequency that m_st already reads back (DyadEnergy.swift:90,105), closing the phase-observable loop;
2. a chroma gain 1 + κ·Ū on the beating epoch's table entries (κ proposed ¼, shell-capped) — **held until its own axiom section exists** (see §5).

### 1.3 The live set of loops (the harmony port)

**F0-lock (grafted theorem).** The byte-locked container (320 cs, 64 frames, 5 cs) forces every exported loop onto the same fundamental F0 = 100/320 = 0.3125 Hz (binary-exact 5/16); the rung rates 5/10/20 Hz are harmonics 16/32/64 of the loop. Every archive is therefore *intrinsically* a harmonic scale on one fundamental — the set-as-scale is lawful, not imposed.

**The set** = the loop archive: today MapElites' EliteMap (compiled, UI-unreachable per SIMPLICITY), tomorrow the 𝔇 phase archive ("the archive IS the phase portrait"). Cells store gene + certificate + occupancy 12-vector + tuning (δG*, δB*) + Û trace — not the full GIF, per the 𝔇 plan. All quantities recoverable from exported bytes (DY8).

**The inter-loop metric, ear and eye:**

```
X_ear(T₁,T₂) = a₁ᵀ G a₂            (exact polarization: D(T₁∪T₂) = D(T₁) + D(T₂) + X)
χ_eye(L,M)   = Σᵢⱼ wᵢwⱼ · g( x*·ΔE_ij / (1 + 0.045·C_min) ) / (W_L·W_M)
```

X_ear is symmetric, bilinear, X(T,T) = 2D(T) — the dissonance of two loops *played together* decomposes exactly. χ_eye fills the slots the honest direction: position = CIELAB (DyadHarmony.srgb8ToCIELAB), critical band = CIEDE2000's S_C with C_min playing f_min, weight = occupancy. Every archive edge carries the dyad **(X_ear, χ_eye)** — the structural rhyme made literal in one tuple. Ou & Luo CH keeps riding exports untouched.

**Ordering, three closed-form stages:**
1. **Admission** — a candidate enters its phase cell at a local minimum of ΣX against members, opposed by the existing repulsionScore over (rhythm, spread) so the set spans the phase portrait while transitions stay consonant.
2. **Dramaturgy** — the played order is constrained to strictly urgency-unimodal sequences in Ū peaking at position P(n); **P(n) = ⌈2n/3⌉ is a named design parameter (theater convention), not an axiom** — the judges' split, reconciled.
3. **Tuning the transitions** — among feasible orders, argmin Σ_k X(L_k, L_{k+1}); deterministic (witness X values pairwise distinct), exhaustive for n ≤ 9. Scale design lifted one level: the set is a scale whose notes are loops.
4. **Key** — two loops share a key when (δG*, δB*) agree; the setlist annotates key changes as hue-rotation events landing at arc positions.

---

## 2. Spec module plan

### File: `spec/statistics/Dissonance.hs` — chosen, justified

Of the two offered homes, **statistics** wins over `spec/temporal/`: the kernel is domain-free (the six-slot architecture — g never mentions time, color, or Hz), and its Tesseract-wide identity is a *pairwise-summed statistic over weighted multisets* — the same epistemic family as E_pal's closed 9-number Stats form and the DY8 stats provenance. Placing it under `temporal/` would subordinate the object to one of its three ports; the temporal port already has its axis specs (ContinuousDepthCadence, TemporalBinomial). House style: standalone runghc script à la TriScaleLadder.hs, registered in spec/Makefile under a STATISTICS layer folded into CORE.

**Reconciliation with the two repo-resident specs (judge 2's demand, explicit):** `spec/quantization/SpectralPalette.hs` keeps the quantization-side detail (chart, tuning, chord hue) but its SP10/SP11 urgency axioms are **amended** to the derived calibration (s_t deleted); `spec/harmony/SetListDissonance.hs` is **demoted to the set layer** — its SD7 theorem is subsumed by DS9 below, its Q=2 chord-roughness coloring is retired in favor of the winner's tuning mechanism, its SD12 setlist machinery survives with the peak re-labeled a parameter. LadderOctave.hs stays in scratchpad; only its F0-lock is promoted (DS12). One kernel, one urgency definition, no competing survivors.

### Axioms DS1–DS16

Verification strategy legend: **[E]** exact (integer/Rational arithmetic or algebraic identity, `==`), **[P·tol]** pinned numeric with stated tolerance, **[G·step]** grid search with grid-step error bound.

**Kernel laws (the P&L shape, canonical):**
- **DS1 UNISON ZERO, SILENT TAIL** [E + P·1e-12]: g(0) = 0 exactly; g strictly decreasing past x̂ on grid 1e-3; g(8) < 1e-12. Coincident and widely-spaced components are both consonant — dissonance is a bump, not a wall.
- **DS2 ONE INTERIOR PEAK, CLOSED FORM** [P·1e-6 + G·1e-4]: x̂ = ln(b2/b1)/(b2−b1) = 0.220350; g(x̂) = 0.179756; exactly one sign change of g′ on [0,10]. Header states b1 = **3.51** (code constant), not 3.5 (brief).
- **DS3 QUARTER-CB HONESTY** [P·1e-3]: x̂/x* = 0.918 — the peak sits 8% below Sethares' nominal x*; stated, not re-litigated.
- **DS4 BILINEAR, SYMMETRIC** [P·1e-12 + E]: d(λw₁, μw₂) = λμ·d; d(p,q) = d(q,p). Product form pinned; min-variant note (degree-1 homogeneity) in header.
- **DS5 QUADRATIC FORM, POLARIZATION** [P·1e-12]: pair-summed D = ½aᵀGa; D(a₁+a₂) = D(a₁) + D(a₂) + a₁ᵀGa₂; D(λa) = λ²D. Merging loops decomposes exactly.
- **DS6 THE HARMONIC-DIP LAW** [G·5e-4]: witness f0 = 500 Hz, 7 partials, aₖ = 0.88^(k−1); strict local minima of D_T(α) on [1, 2.3] within 0.01 of each of {6/5, 5/4, 4/3, 3/2, 5/3, 2/1}; depth ordering recovers the classical ranking D(2/1) < D(3/2) < D(5/3) < D(4/3) < D(5/4) < D(6/5). Extra 7-limit dips (7/6, 7/5, 7/4) asserted permitted, not excluded.
- **DS7 DIP-SURVIVAL DISCIPLINE** [rule, enforced per port]: every port axiomatizes *which* dips survive at its declared CB field (the bass-ear rule — a coarse-resolution port may lawfully hear only {3/2, 2/1} and must say so); the reference field s1·f + s2 with all five constants is the pinned baseline.

**Quantization port:**
- **DS8 THE CHART IS EXACT** [E]: 12 pinned integer frequencies m_X·125·2^ℓ; intra-channel steps exact octaves; level-aligned cross-channel ratios exactly 5:4, 6:5, 3:2 by integer cross-multiplication; occupancy marginals exact u64 counts summing to 4096/channel/frame (the TL1–TL3 carrier).
- **DS9 TUNING, PINNED AND TIMBRE-DEPENDENT** [G·1/1200]: uniform occupancy → (δG*, δB*) = (269, 836)/1200 under the 1/12 guard; δ = 0 (just 4:5:6) is not a resting point; dark-skew witness (u³ warp, LCG seed 2) moves δG* to 325. The punchline as axiom: consonance depends on the timbre.
- **DS10 TRITONE = INVOLUTION** [P·1e-9, 1e-12]: pitch class level-invariant across all four octaves; σ-involution is q ↦ q + ½ (hue+180°), tritone² = id = σ∘σ; the chart colors 128 σ-representatives only. The byte contract as theorem.
- **DS11 CHORD HUE** [P·4°, 1e-9]: dominant-channel chords pull hue to the channel class within 4°; grays keep circular resultant in (0.16, 0.17), all grays identical hue.

**Temporal port (the merged urgency — the load-bearing amendment):**
- **DS12 DERIVED CALIBRATION** [E + P·1e-3]: x_uv = x*·((2−d_min)/(2−d_max) − 1); full contrast (0,1) lands at x = x* **exactly** (Double-exact: σ ratio 2 is dyadic); g(x*)/g(x̂) = 0.9961; companion identity Δc = 2σ_base ⇒ within-voxel far pole x₁(0) = x* exact. No free constants.
- **DS13 URGENCY LAWS** [E + G·1e-3 + P·1e-12]: U = 0 at equal depth exactly; strictly monotone in each depth argument; max over lattice depths = x* < x̂ (never past peak); bilinear in masses (2×3 = 6×); near-field asymmetry stated (same gap rougher near than far).
- **DS14 THE URGENCY CLOCK** [E]: 16³ = 4096 judgments/loop at 5 Hz (100 div (320 div 16) = 5); 64 draws/judgment (= 64³); exactly 11776 bonds = 16×480 spatial + 4096 time-wrapped (NETSCAPE torus). TL9 restated.

**Harmony port:**
- **DS15 F0-LOCK + CROSS-LOOP ALGEBRA** [E + P·1e-12]: F0 = 5/16 Hz exact; rung rates = harmonics 16/32/64; X_ear symmetric, bilinear, X(T,T) = 2D(T); χ_eye symmetric, bilinear in occupancy, zero at coincidence, bounded by g(x̂).
- **DS16 THE SETLIST EXISTS, IS DETERMINISTIC** [E + P·1e-9]: witness archive → feasible urgency-unimodal orders = C(n−1, P(n)−1); unique argmin of ΣX with margin > 1e-9. Header labels P(n) = ⌈2n/3⌉ **DESIGN PARAMETER**, retunable by decree only — explicitly *not* psychophysics.

**Pre-port gate (spec-first):** the chroma-gain law (identity at Ū = 0; shell-cap; commutation with the involution's chroma-radial action comp(L,a,b) = (L,−a,−b)) must be authored as a DS17 section and pass green **before** any Swift touches tables. κ's value is Daniel's (Q5).

---

## 3. Swift/Metal touchpoints, in order (design only — no Swift lands in this workflow)

1. **`DissonanceKernel.swift`** — g, x̂, g(x̂), the 12×12 matrix G as a compile-time constant array; pure functions, DyadEnergy closed-form style ("computable from an index frame and a table alone").
2. **Occupancy 12-vector** — per-channel level marginals from the existing index histogram (DyadEnergy.swift:95–99 path) / RungCube u64 sums (TriScaleLadder.swift); per-frame at 20 Hz, per-loop totals.
3. **`SpectralTuning`** — 1200-point sequential guarded argmin over G-comb then B-comb; emits the 128-representative hue chart; table construction through the existing DyadPalette shell machinery (radii ρ_k, counts [1,1,2,4,8,16,32,64] untouched; assignment is the free choice); involution derives entries 128–255. Must pass DyadGIFContractTests unmodified.
4. **`UrgencyField`** — 16³ bond roughness from EMA depths (DyadPipeline α = 0.3) and σ(d) (BinomialCadence read, never written); 11776 bonds; pooled Û (16 samples) and Ū; margin surfaced beside the phase16 S_v/Θ_s machinery.
5. **Bleed-band routing** — high-U voxels into pairDither's bayer4 band (DyadPipeline.swift:141–151), index choice only; m_st readback confirms the shimmer channel.
6. **Chroma gain** — gated behind DS17 green + Daniel's κ (Q5); table choice only; κ = 1 byte-identical to canon.
7. **Archive integration** — MapElites/𝔇 cells gain {12-vector, (δG*, δB*), Û trace}; edge dyad (X_ear, χ_eye); admission + dramaturgy-constrained setlist ordering. Ordering and telemetry only; the archive surface stays unreachable.
8. **Provenance** — **strict byte posture (grafted):** all new quantities live in archive metadata only. The proposed `SPECTRUM v1` STATS comment line ships only after a decreed contract amendment + DyadGIFContractTests update (Q4).

---

## 4. What stays untouched

- **The container**: 64×64×64 → 256×256, 5 cs, NETSCAPE loop, 320 cs — every byte-locked field; all new structure is table choice, index choice, archive metadata, and ordering.
- **The ladder laws**: TriScaleLadder TL1–TL9 are read as the carrier and the clock, never amended.
- **BinomialCadence**: σ(d), centers c_e, gaussianProbs — urgency *reads* the cadence spectrum back; iterative-not-replacement.
- **DyadHarmony (Ou & Luo)**: keeps riding every export; χ_eye is a sibling on the same summation skeleton, not a replacement.
- **DyadPalette canon**: shell radii ρ_k, shell counts, σ-involution, comp = (L,−a,−b), gamut law.
- **Decrees**: ★NO-CAPTURE-TRAINING (everything closed-form: G is constant, tuning is a deterministic grid argmin — same epistemic class as runghc checks; LADDER-OCTAVE's capture-shaped κ-EMA was rejected partly on this ground); SIMPLICITY (zero UI; EliteMap stays unreachable); spec-first (DS1–DS16 green before any Swift); ★FRONT-ONLY; no-crop.

---

## 5. Open questions for Daniel

1. **Key drift.** Per-loop tuning rotates G/B hues between loops — "the same" lattice color drifts across a live set (key changes at arc positions). Accept as the point, or freeze tuning per set/per session?
2. **Urgency sign.** Far = urgent (calm subject, urgent halo) is decreed by CD4/CD5 + the face-tonic law and is what's spec'd. If the dramaturgy ever wants near = urgent (face-forward crescendo), it is one monotone flip — decide before the Swift port, not after.
3. **The felt channel.** Bleed-band shimmer, chroma gain, or both? Shimmer is index-only and closes the m_st loop; chroma gain needs DS17 + κ.
4. **Provenance amendment.** Decree (or refuse) the `SPECTRUM v1` STATS comment line + DyadGIFContractTests update; until then everything stays archive-side.
5. **κ.** Proposed ¼, shell-capped — pick, or defer the chroma channel entirely.
6. **Dramaturgy peak.** P(n) = ⌈2n/3⌉ is theater convention; confirm or choose your arc.
7. **Reserve axis.** LADDER-OCTAVE's real-DFT channel timbre (actual per-frame u64 sums → 96 partials on F0, Rayleigh CB floor) is honest raw material held in scratchpad — want it promoted later as a second, *measured* timbre axis beside the injected chart?
