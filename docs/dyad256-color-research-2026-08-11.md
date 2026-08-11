# DYAD-256 Redesign: Synthesis of the Eight-Thread Harmony/Quantization Sweep

## 1. DIAGNOSIS

The diversity failure is overdetermined. Five independent mechanisms, each grounded in the findings, compound:

**(a) Scene-locked sampling caps diversity at the scene's chromatic spread.** Primaries come only from concentric ellipses of the captured face's OKLab distribution. A face is a narrow skin wedge (orange-red dominated); its per-PC sigma is typically a few 0.01 OKLab units. Ring spacing is 2σ/7 ≈ 0.29σ, which for such distributions falls **below the 0.02 dE_OK JND** (empirical detection ~0.004 in side-by-side comparison, Cirkel). Adjacent rings of the [1,1,2,4,8,16,32,64] ladder are therefore perceptually identical: many of the 128 primary slots buy zero perceived diversity.

**(b) The budget is tiny and the design wastes it.** sRGB holds only ~12k-16k distinguishable colors at dE76 = 2.3 (~1,700 spheres at the coarse dE_OK = 0.02); 256 optimally spread colors cover at most **~1.6% of distinguishable sRGB**. Every JND-collapsed duplicate is expensive. The chroma-only out-of-gamut clamp makes it worse: distinct outer-ring samples are crushed onto near-identical in-gamut points, directly manufacturing sameness.

**(c) The exact-negation mirror dumps 128 colors into the worst part of hue space.** comp(L,a,b) = (L,−a,−b) maps the skin wedge to cyan-green-purple, precisely the hues with the **lowest natural frequency and lowest measured combinability** (Forni et al. 2025: C(j) minima at hues 0/120/300 deg; natural landscape hue histograms are bimodal at blue and orange-yellow with green/purple minima). O'Donovan's Kuler data shows hue pairing is **not rotation-invariant**: green pairs with blue or yellow, not purple; only orange-cyan survives as a true 180-deg pair. The involution's skeleton (near-180 contrast) is supported (Forni: harmony peaks at 160-220 deg separation), but its exact form is contradicted for most hues.

**(d) comp() preserves L exactly, killing the single biggest published diversity lever.** O'Donovan's learned LASSO weights: lightness **spread** (max L − min L) is strongly positive, L **std** strongly negative in all three datasets; good themes are light-to-dark gradients. Schloss-Palmer: +|dValue| is the largest figural-preference factor (20.2% of variance) and third in pair preference (12.6%). Ou-Luo: H_dL = 0.14 + 0.15·tanh(−2 + 0.2·dL) rewards lightness contrast up to +0.29. The mirror 128 contribute **zero** lightness diversity, and the fixed ensemble L-shift to 0.617 compresses it further.

**(e) Harmony maximization is not the objective; the pair regime matters.** Ou-Luo's H_C rewards similarity, so any pure harmony maximizer collapses diversity; the model's own escape axes are lightness and the per-color hue term. And for the dyad itself: at dh = 180, dC = 0, the CIELAB metric hue difference is dH_ab = 2·C*, so DC = 2·C* and for face chroma C* > ~10 the pair saturates at H_C = **−0.49**, the disharmony floor. Schloss-Palmer rescue the structure: hue-contrastive pairs score badly as pairs but **figural preference on a ground increases with hue contrast**, so the face=figure / mirror=ground role law (b135959) is the defensible regime, provided the ground stays ground. Finally, Moon-Spencer: the small inter-ring deltas fall in the **first ambiguity band** (dHue < 7/100 circle, dChroma < 3 Munsell steps), which scores 0 or negative order; the current ladder is an ambiguity generator by construction.

## 2. THE STAGED PIPELINE

Six stages, all in OKLab (Ottosson M1/M2 matrices), with a CIELAB conversion side-channel for scoring (Ou-Luo/Moon-Spencer coefficients are CIELAB-calibrated; OKLab values are not drop-in).

**Stage 0: Measurement.** From the captured face: OKLab mean μ, principal axes PC1/PC2, per-axis σ, and the a-b covariance. From this session's capture, also the measured corr(a,b); Webster's natural-scene range is −0.27 to −0.60 (wet to dry), so the per-capture measured value replaces any invented coupling constant.

**Stage 1: Axis budget (L first, then b, then a).** Natural chromatic variance is hierarchical: σ_L : σ_blue-yellow : σ_red-green = 0.353 : 0.0732 : 0.00745, roughly **47:10:1** (Ruderman/Cronin/Chiao 1998, constants via secondary HAL source). Allocate quantization budget across axes by the standard bit-allocation law (Celebi survey):

    b_d = B_sum/D + (1/2)·log2( σ_d² / (∏_d' σ_d'²)^(1/D) )

using the **measured** per-axis σ from Stage 0 blended with the natural hierarchy as prior. This is the licensed "staged latent computation in LAB": L stage first (largest variance), then b (blue-yellow), then a.

**Stage 2: Diversity floor (scaffold).** A fixed, scene-independent lattice inside the sRGB solid in OKLab: Mojsilovic-Soljanin Fibonacci lattice per L-plane,

    r = s·n^(1/2),  θ = 2πnγ + φ,  γ = (√5−1)/2

with out-of-sRGB points discarded (δ = 1/2 gives constant areal density; the golden-ratio γ is the uniformity-maximal irrational; both from the patent, no free constants). This scaffold guarantees full-spectrum coverage independent of the scene, answering demand (a) directly. It also carries O(1) index arithmetic and built-in ordered dither via Fibonacci-neighbor substitution (index ±13/±21).

**Stage 3: Scene-adaptive split (replaces fixed ellipses).** Orchard-Bouman binary splitting of the face distribution: cluster stats R_n, m_n, N_n; split leaf of largest principal eigenvalue λ_n by the plane e_nᵀx = e_nᵀq_n; child stats by exact subtraction R_{2n+1} = R_n − R_{2n}. Seven levels gives exactly **128 leaves**. The current single global PC1×PC2 frame with binomial rings is the balanced-tree special case; λ-ordered splitting is the adaptive generalization, and λ_n is the principled "which region deserves more colors" rule. Optional finishing pass: histogram-weighted k-means (18-50% MSE reduction over divisive alone, Celebi).

**Stage 4: Binomial ladder reconciled with the JND floor.** Keep the binomial counts as the **target measure**, but draw with a spacing constraint: within each shell/subtree, weighted maximin (Dyer-Frieze: j* = argmax_j w_j·δ(x_j, C), δ(x,C) = min distance to already-chosen) with hard floor δ ≥ 0.02 dE_OK (≥ 0.004 if the pair will appear in side-by-side dithered fields). Alternative published recipes with their own constants: Braudaway suppression freq(c) *= (1 − exp(−0.25·‖c − c_prev‖²)) or Huang's argmax √freq·δ. Counts follow the binomial ladder; positions never collapse within a JND. Ring radii: re-derive from Moon-Spencer moment balance rather than the fixed 2k/7 (see §3).

**Stage 5: Ground register (replaces exact negation).** Three licensed corrections:
1. **Hue**: rotate each complement's hue partway from exact +180 toward the OKLab −b/+b (blue-yellow, daylight-locus) axis, weighted by distance from that axis (natural-stats thread: real scene contrast pairs live on blue-yellow; principal chromatic axes of natural scenes span only −90 to −45 deg in cone-opponent space, never red-green). Alternatively a lookup-table involution from the Kuler adjacent-pair probability table p_abc in colorCode.zip (data-driven partner hue per primary hue).
2. **Lightness**: make the involution act on L. Reframe the 0.617 target as a **contrast law**: shift the ground register away from the face's mean L, sign opposite the face's L center of mass, with magnitude chosen so each dyad hits Ou-Luo's reward zones: dL* ≥ ~15 CIELAB (H_dL midpoint is dL = 10, saturating by ~25) and Lsum ≥ ~134 (H_Lsum midpoint, mean L* ~67; note OKLab 0.617 ≈ L* 68 already sits near this sweet spot, so the existing constant survives as a derived quantity, not a naked one). Additionally stage the ground half along an L gradient per ring (O'Donovan: spread L, don't clone it).
3. **Chroma**: keep the muting (doubly supported: Schloss-Palmer harmony carries −SumChroma at 5.3%, figural preference carries +dChroma at 12.7%, figure more saturated than ground), but make the per-hue amount follow the Goethe-Itten extension law, muting scaled like light values 9:8:6:6:4:3 (yellow hardest, violet least), equivalently enforcing the Munsell area balance A_face/A_ground = (V_ground·C_ground)/(V_face·C_face) per dyad.

**Stage 6: Gamut map.** Any color still outside sRGB is mapped by a hue-preserving OKLab geodesic toward the cusp, never raw chroma scaling (which piles primaries and complements alike near the neutral axis). Better: because Stages 2-4 sample **inside** the sRGB solid from the start, this stage should be a no-op assertion, not a repair.

Constant licensing summary: γ, δ = 1/2 (Mojsilovic-Soljanin); 0.02/0.004 JND (Cirkel/OKLab literature); 47:10:1 (Ruderman); bit-allocation formula (Celebi); λ_n split rule and subtraction identities (Orchard-Bouman); dL ≥ 15, Lsum ≥ 134 (Ou-Luo tanh midpoints); −0.27..−0.60 a-b coupling (Webster, superseded per capture by measurement); 9:8:6:6:4:3 (Goethe via Westland). No invented thresholds remain.

## 3. THE BEAUTY DISTRIBUTION

"Binomial distribution of beauty" becomes precise as: **binomial counts over shells, importance-weighted within shells by a measured beauty density, with areas apportioned by the V·C balance law.**

**Per-color beauty density (the sampler's weight).** Ou-Luo's hue term is separable per color and closed-form, computed in CIELAB from each candidate's own (L*, C*, h):

    H_SY = E_C · (H_S + E_Y)
    E_C  = 0.5 + 0.5·tanh(−2 + 0.5·C*)
    H_S  = −0.08 − 0.14·sin(h + 50°) − 0.07·sin(2h + 90°)
    E_Y  = ((0.22·L* − 12.8)/10) · exp( (90−h)/10 − exp((90−h)/10) )

(Gumbel bump peaked at h = 90°, positive only for L* > 58.2: light yellow beautiful, olive ugly.) Sample ring candidates from the Stage-3 leaves and accept proportional to softmax(β·H_SY), keeping shell counts fixed. β is a temperature; H_SY is literally an external-field term addable to the existing E_pal phase-energy machinery. Note the exact separability of the palette score:

    mean CH = mean_pairs(H_C + H_L) + (2/n)·Σ_i H_SY(i)

so the beauty part is a **staged per-color latent**; only H_C + H_L are genuinely pairwise (32,640 ops for n = 256, or restrict the full model to the 128 face-ground dyad pairs and use the patent's non-adjacent form CH_N = 0.2 + 0.65·tanh(1.7 − 0.045·DC_N), DC_N = sqrt(dH² + (dC/1.30)²), for cross pairs).

**Pair-register weights (constraints between shells).** Schloss-Palmer variance increments give the signs and relative magnitudes with zero invented numbers: pair register E ∝ +23.8·SumCool − 17.1·|dHue| + 12.6·|dValue| − 5.3·SumChroma; figure register ∝ +18.7·SumCool + 20.2·|dValue| + 12.7·dChroma (signed, figure minus ground). Closed-form fallback: Colorgorical's PP = 75.15·(κ₁+κ₂) + 47.61·|ΔL| − 46.42·|ΔH| in CIE LCh (explains 51.8% of pair-preference variance in LCh). All three agree on the direction: spend diversity on **L**, keep hues familial, favor cool.

**The literal binomial score.** O'Donovan's LASSO (r = wᵀy + b, 334 features, weights public in weights.csv) scores 5-color themes. Score DYAD-256 as the **expected LASSO rating over binomial draws**: sample one color per shell with weights [1,1,2,4,8,16,32,64], score the 5-subsets, average. That is a binomial distribution of beauty with a learned, non-fabricated kernel. Kita-Miyata 2016 is the size-independent variant if one whole-palette number is preferred. Import two learned regularizers: the hue-entropy parabola (too few hues as bad as too many) and the min-pairwise-probability penalty (popular pairs, but not all similar).

**Angular measure (where on each ring).** Non-uniform: a two-component von Mises mixture on OKLab hue with peaks at the measured natural modes (blue ~200-240 and orange-yellow ~40-60 in HSL, mapped to OKLab hue), counts reweighted by Forni's combinability C(j) so blue/yellow rungs receive more of the 128 than green/purple rungs. Honesty note: Forni et al. fit no parametric distribution and report no preference-vs-nature correlation coefficient; the von Mises mixture is our parameterization of their histogram, and should be labeled as such in the spec.

**Areas/counts: the V·C law.** Treat each shell's count n_k as its area. Moon-Spencer balance about the adaptation point (use the face's OKLab mean as the N5 analog): moment Q_k = n_k · arm_k with the reconstructed closed form

    arm(V,C) = sqrt( (8·(V−5))² + C² )

(verified against 6+ table entries). The current ladder is maximally imbalanced (64 slots on the highest-arm outer ring). Fix: either n_k ∝ 1/arm_k, or keep the binomial doubling and choose ring radii so successive moment ratios land on Moon-Spencer's rewarded 1:1 / 2:1 / 3:1 ladder (geometric radii with arm halving per doubling makes n_k·arm_k constant, the +1.0 identity-of-moments case). Caveat carried: Moon-Spencer validates poorly as preference ground truth (Ito 1962; Westland 2007); use M = O/C as a generative scaffold and pair-classifier (push deltas out of the ambiguity bands into similarity or contrast bands), with device feel as the real gate.

## 4. DITHER-PAIR LAW

At 460 ppi and 300 mm: **94.8 px/deg** (0.633 arcmin/px); 1 px alternation = 47.4 cpd, 2 px = 23.7, 4 px = 11.9, 8 px = 5.9. Three regimes:

**Fusion (period ≤ 4-8 px, ≥ 12 cpd).** Beyond Mullen's chromatic acuity cutoff (~11-12 cpd for both opponent axes), a dyad's chroma difference is guaranteed invisible and the perceived color is the areal average of **linear cone excitations**: LMS(m) = (n₁·LMS_lin(c₁) + n₂·LMS_lin(c₂))/(n₁+n₂). Not the OKLab average: OKLab is a cube-root space, so by Jensen's inequality the linear-LMS mean of an OKLab-complement pair (L,a,b)/(L,−a,−b) is generally brighter and off-neutral. **Law: every σ-pair's predicted fusion color must be computed through linear LMS and stored as a palette citizen.** This is also the cheap diversity multiplier: the effective gamut is 256 points plus all fusible dyad midpoints; choosing the 128 primaries so pairwise linear-LMS midpoints tile OKLab multiplies perceived colors by orders of magnitude at zero palette cost, and pair counts along the shells naturally follow a binomial weighting (second-order binomial design).

**Texture visibility (1-2 px).** Luminance acuity extends to ~50-60 cpd, so only the **luminance** difference of a dyad can show as texture at fine pitch. comp() preserving OKLab L means primary/own-complement dithers fuse silently even at 2 px, but the ground L-shift breaks this: any pattern coarser than 2 px crossing the face/ground registers will show luminance texture unless within-pattern ΔL is kept to a few percent linear Y. Since Stage 5 deliberately adds L contrast between registers, the law is: **L-contrast lives between regions, never inside a fine dither pair.**

**Induction at the face/ground boundary.** Assimilation-to-contrast crossover is ~4 cpd (Smith-Jin-Pokorny), i.e. ~24 px period here. The Wada ground is a large low-frequency field, squarely in the simultaneous-contrast regime: complementary ground pushes perceived face color further from it, maximally along the S/blue-yellow axis, where Monnier-Shevell shifts reach Δs ≈ +0.25 to +0.32 (lime adjacent) and −0.05 to −0.45 (purple adjacent) at ~3.3 cpd, linear in inducer S-cone contrast. Ground chroma-muting is exactly the right lever (reduces the shift linearly). The 8-24 px band (5.9-11.9 cpd) is the assimilation trap: thin ground striping next to face cells drags face color toward the ground; avoid that scale or use it as a free desaturator. This S-axis induction is also the likely amplifier of the "blue face" orientation bug (high-s ground abutting low-s face).

**Verification tool.** S-CIELAB at sampPerDeg = 94.8 with the code-verified kernels (luminance halfwidths 0.05/0.225/7.0 deg, weights 1.00327/0.114416/−0.117686; red-green 0.0685/0.826 deg at 0.616725/0.383275; blue-yellow 0.0920/0.6451 deg at 0.567885/0.432115; BY dominant halfwidth 0.092 deg ≈ 8.7 px, so BY detail under ~9 px is heavily averaged). ΔE between filtered target and filtered rendering is the correct loss for choosing dyad pairs; three separable Gaussian convolutions, straight into the Metal preview path. Caveat: the 1997 paper's printed table uses a different parameterization that was unreachable (paywall); the constants above are the authors' own reference implementation, which is what the field runs.

## 5. GAMUT REALITY

**The GIF is sRGB, full stop.** CSS Color 4 mandates untagged images be treated as sRGB; iOS is fully color-managed and does the same (UIImage, WKWebView, Safari, Chrome all agree); the only ICC-in-GIF mechanism (ICCRGBG1012) is a dead unregistered experiment. A "P3 GIF" is unreachable without changing container. The iPhone 17 Pro pipeline is P3-exceeding at capture (ProRAW linear DNG) and ~98-100% P3 at display, but the GIF bottlenecks everything to 8-bit indexed sRGB, which is only ~**67%** of the panel's CIELAB volume (sRGB 832,870 dE³ vs P3 ~1.243M dE³; in OKLab ~0.0571 vs ~0.0767 cubic units).

Consequences for the gamut law: (1) build latents in OKLab freely, but the 256 output triples must live inside the sRGB solid, so make the sampler **gamut-aware from the start** (Stage 2/4 sample inside the solid) rather than sampling wide and crushing chroma after; the clamp is not an edge case, it is the boundary of the whole design space. (2) Face colors captured outside sRGB (saturated skin highlights under warm light; Bayer-native gamut exceeds P3) get the hue-preserving cusp-geodesic map, or primaries and complements both pile up near neutral. (3) The way to "use the full spectrum the display can express" within an sRGB container is §4's fusion law: dyad midpoints in linear LMS extend the perceived gamut beyond the 256 entries even though every entry is sRGB.

## 6. VERIFIABLE NEXT STEPS

Spec-first in DyadPalette.hs style: pure functions, golden tables, byte-exact gates.

1. **CIELAB scoring bridge.** Add OKLab → linear sRGB → XYZ → CIELAB conversion for scoring. Gate: byte-exact against Sharma-Wu-Dalal's published CIEDE2000 test pairs (their supplementary data exists precisely for this); the CIEDE2000 constants in this sweep are transcribed, not re-derived, so the test-pair gate is mandatory before any use.
2. **In-gamut sampling invariant.** Move sRGB-solid membership into the sampler; demote the chroma clamp to an assertion. Gate: property test that all 256 entries are in-gamut pre-clamp on a corpus of synthetic face distributions (no-capture decree: synthetic corpora), and that the clamp stage is the identity, byte-exact.
3. **JND-floor maximin.** Within-shell weighted maximin with δ ≥ 0.02 dE_OK. Gate: report and assert min pairwise dE_OK three ways: within the 128 primaries, within the 128 grounds, across the dyad boundary; regression test that the old sampler violates the floor and the new one satisfies it on the same synthetic inputs.
4. **Orchard-Bouman split spec.** 7-level binary split with R/m/N statistics. Gates: exact subtraction identities (R_{2n+1} = R_n − R_{2n}, same for m, N) as algebraic laws; exactly 128 leaves; the balanced-λ degenerate case reproduces the current ellipse-ring palette byte-exact (backward-compatibility table law).
5. **Beauty weight H_SY.** Implement E_C, H_S, E_Y with a golden table of hand-computed values (including h = 90°, L* = 58.2 sign-flip boundary, C* = 4/8 gate edges). Gate: golden-table byte-exact; monotonicity properties (E_C nondecreasing in C*, E_Y sign flips exactly at L* = 58.2). Use the journal H_Lsum coefficients (0.28 + 0.54·tanh(−3.88 + 0.029·Lsum)), not the patent's rounded variant.
6. **Ground register v2.** L-contrast law (sign opposite face L center of mass) + partial hue rotation toward the b axis + Goethe-scaled muting. Gates: every dyad satisfies dL* ≥ 15 and Lsum ≥ 134 after conversion (derived thresholds, cite Ou-Luo midpoints in the spec comment); measured per-capture corr(a,b) drives the ellipse coupling with the Webster range as a sanity bound, never as a constant.
7. **Dyad fusion table.** Per σ-pair, compute and store the linear-LMS fusion color. Gate: golden test that fusion(c, comp(c)) ≠ OKLab midpoint (the Jensen gap is the point), plus S-CIELAB-filtered ΔE between predicted fusion and a rendered 2-px checkerboard below threshold on synthetic renders.
8. **S-CIELAB verification harness.** Port the three separable-Gaussian kernels at sampPerDeg = 94.8. Gate: kernel constants byte-match separableFilters.m; weights sum to 1 per channel.
9. **Palette scoreboard (telemetry only, no new ledgers).** Report mean CH via the separability formula, Glasbey min-pairwise-distance, and expected O'Donovan LASSO score over binomial 5-draws (weights.csv is public; local copies of weights.csv/colorcomp.pdf already in this session's scratchpad at /private/tmp/claude-501/-Users-daniel/896b0837-0177-4c30-b2e0-9a922e7543ac/scratchpad/). Gate: deterministic scores on golden palettes; device feel remains the shipping gate per decree.

Order matters: 1-2 unblock everything; 3-4 fix diversity structurally; 5-6 install the beauty law; 7-8 make the dither claims testable; 9 closes the loop.

## 7. READING LIST

Priority-ordered, deduped:

1. O'Donovan, Agarwala, Hertzmann, Color Compatibility From Large Datasets, SIGGRAPH 2011. Project: https://www.dgp.toronto.edu/~donovan/color/ ; paper: .../colorcomp.pdf ; weights: .../weights.csv ; code+data: .../colorCode.zip (all live, HTTP 200; the only fully public learned harmony scorer with published coefficients as of 2026)
2. Ou & Luo, A colour harmony model for two-colour combinations, CRA 31:191-204, 2006. https://onlinelibrary.wiley.com/doi/abs/10.1002/col.20208 (open equations also in patent US9134179B2: https://patents.google.com/patent/US9134179B2/en)
3. Schloss & Palmer, Aesthetic response to color combinations, AP&P 73:551-571, 2011. https://pmc.ncbi.nlm.nih.gov/articles/PMC3037488/ ; publisher PDF with BCP-32 coordinates: https://palmerlab.berkeley.edu/pdf/Schloss%26Palmer(2011).pdf
4. Palmer & Schloss, An ecological valence theory of human color preference, PNAS 107:8877-8882, 2010. https://pmc.ncbi.nlm.nih.gov/articles/PMC2889342/
5. Ottosson, A perceptual color space for image processing (OKLab), 2020. https://bottosson.github.io/posts/oklab/
6. Zhang & Wandell S-CIELAB reference implementation, 1996. https://github.com/wandell/SCIELAB-1996 (use the code constants, not the paper table)
7. Orchard & Bouman, Color Quantization of Images, IEEE TSP 39:2677-2690, 1991. https://engineering.purdue.edu/~bouman/publications/orig-pdf/sp1.pdf
8. Celebi, Forty years of color quantization, AI Review 56:13953-14034, 2023. https://faculty.uca.edu/ecelebi/documents/AIRE_2023.pdf
9. Forni, Darmon, Benzaquen, Harmonious Color Pairings, arXiv:2508.15777, 2025. https://arxiv.org/abs/2508.15777
10. Webster, Mizokami & Webster, Seasonal variations in the color statistics of natural images, Network 18:213-233, 2007. https://labs.psych.unr.edu/websterlab/files/WebsterNetwork2007.pdf
11. Mojsilovic & Soljanin, Color quantization by Fibonacci lattices, IEEE TIP 10:1712-1725, 2001; full math in US 6,898,308: https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/6898308
12. Gramazio, Laidlaw, Schloss, Colorgorical, IEEE TVCG 23:521-530, 2017. https://vis.cs.brown.edu/docs/pdf/Gramazio-2016-CCD.pdf ; code: https://github.com/connorgr/colorgorical
13. Sharma, Wu, Dalal, CIEDE2000 implementation notes + test data, CRA 30:21-30, 2005. https://hajim.rochester.edu/ece/sites/gsharma/papers/CIEDE2000CRNAFeb05.pdf ; test data: https://www.ece.rochester.edu/~gsharma/ciede2000/
14. Glasbey et al., Colour displays for categorical images, CRA 32:304-309, 2007. https://strathprints.strath.ac.uk/30312/1/colorpaper_2006.pdf
15. Moon & Spencer, JOSA 34, 1944 (three papers): Aesthetic Measure https://opg.optica.org/josa/abstract.cfm?uri=josa-34-4-234 ; Geometric Formulation https://opg.optica.org/josa/abstract.cfm?uri=josa-34-1-46 ; Area https://opg.optica.org/josa/abstract.cfm?uri=josa-34-2-93 (paywalled; tables recovered from fragments + two secondaries)
16. Westland et al., Colour Harmony, CD&C 1:1-15, 2007. https://stephenwestland.co.uk/pdf/westland_laycock_cheung_henry_mahyar_CDC_2007.pdf (Munsell V·C balance, Goethe/Itten ratios, M&S critique)
17. Mullen, Chromatic contrast sensitivity, J Physiol 359:381-400, 1985. https://physoc.onlinelibrary.wiley.com/doi/10.1113/jphysiol.1985.sp015591
18. Smith, Jin, Pokorny, Spatial frequency in color induction, Vision Res 41:1007-1021, 2001. https://pubmed.ncbi.nlm.nih.gov/11301075/
19. Canham, Vazquez-Corral, Mathieu, Bertalmio, Matching visual induction effects, 2021. https://arxiv.org/pdf/2005.02694 (Monnier-Shevell magnitudes, Fig. 7)
20. Ruderman, Cronin, Chiao, Statistics of cone responses, JOSA A 15:2036-2045, 1998. https://opg.optica.org/josaa/abstract.cfm?uri=josaa-15-8-2036 (sigma constants via secondary HAL hal-01054307)
21. Kita & Miyata, Aesthetic Rating for arbitrary-length palettes, Pacific Graphics 2016. https://naokita.xyz/projects/ColorPalette/ColorPalette_pg2016.pdf
22. Ou et al., Additivity of colour harmony, CRA 36:355-372, 2011. https://onlinelibrary.wiley.com/doi/10.1002/col.20624
23. Wu, Efficient Statistical Computations for Optimal Color Quantization, Graphics Gems II, 1991. https://gist.github.com/bert/1192520
24. Cirkel, What's My dE(OK) JND?, 2025. https://www.keithcirkel.co.uk/whats-my-jnd/
25. Lindbloom, RGB Working Space info (gamut volumes), 2017. http://www.brucelindbloom.com/WorkingSpaceInfo.html
26. W3C, GIF89a spec: https://www.w3.org/Graphics/GIF/spec-gif89a.txt ; CSS Color 4 untagged rule: https://www.w3.org/TR/css-color-4/#untagged
27. Webster & Mollon, Adaptation and the color statistics of natural images, Vision Res 37:3283-3298, 1997. https://pubmed.ncbi.nlm.nih.gov/9425544/
28. Lin & Hanrahan, Modeling How People Extract Color Themes, CHI 2013. http://vis.stanford.edu/papers/color-themes

**Unverified or disputed, flagged for the spec:** Ou et al. 2018 universal refit coefficients (CRA 43:736-748) are paywalled and unrecoverable; implement the 2006 canon. Yang et al. TAP 2024 neural model has no verified public code or coefficients. Moon-Spencer Table XI discrepancy: hue similarity +1.1 vs +1.2 and glare −2.0 vs −0.2 across secondaries; the Optica-scraped primary supports +1.1 and −2.0. HyAB distance (|dL| + sqrt(da²+db²)) is secondary/unverified (source 403). Kolpatzik-Bouman SSQ allocation math is abstract-only (SPIE paywall). Ruderman sigmas and the CIEDE2000 constant transcription are secondary until gated (step 1 and step 9 above).
