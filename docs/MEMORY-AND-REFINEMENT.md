# THE GIF AS A MEMORY — head:tail, successive refinement, and what memory actually keeps

Research consolidation, 2026-08-13. Three literature sweeps: successive-refinement
coding theory, palette/index-map compression, and the cognitive science of visual
short-term memory. Companion to [ATLAS.md](ATLAS.md) §7 (the octave) and
[CAPTURE-FUNNELS.md](CAPTURE-FUNNELS.md).

**Daniel's proposal (2026-08-13):** *stratify the compression into head:tail with an
index to decode; query heads quickly, tails for higher-order precision; codify early
the per-frame palette permutation and dither pattern. Watching while watching. We are
approximating memory. This is the GIF. A memory.*

**Verdict:** the scheme has a name (successive refinement), a theorem (Equitz & Cover
1991), and roughly half of it is already built and proved in `spec/quantization/PairTree.hs`.
The palette permutation it requires is **exactly free** in GIF. The dither it requires
is **already** the right one. What is missing is any wiring between those parts.

---

## 1. The theorem

W. Equitz & T. Cover, "Successive Refinement of Information," *IEEE Trans. IT*
37(2):269–275, 1991. [PDF](https://isl.stanford.edu/~cover/papers/transIT/0269equi.pdf)

**Theorem 2.** Two-stage coding achieves rate-distortion optimality at *both* rates
— no penalty for having stopped early — **iff** there is a conditional distribution with
`p(x̂₁, x̂₂ | x) = p(x̂₂ | x) · p(x̂₁ | x̂₂)`, i.e. **X → X̂₂ → X̂₁ is a Markov chain**.
The coarse reconstruction must be derivable from the fine one alone.

**The corollary that matters**, verbatim from the abstract:

> "This implies in particular that **tree structured descriptions are optimal if and
> only if the rate distortion problem is successively refinable.**"

A prefix tree is not *an* implementation of head:tail. It is *the* canonical one.

**Refinable:** Gaussian under squared error; any finite alphabet under Hamming;
Laplacian under absolute error. **Not refinable:** a symmetric ternary source under
absolute error (Theorem 3 gives the exact condition).

**Tesseract sits in the proved-good case.** `PairTree.swift` splits a *fitted Gaussian*
— "splitting N(μ, Σ) at its mean along eigenaxis u" — and OKLab distance is Euclidean,
i.e. MSE.

**The caveat that costs real bits.** Refinability is asymptotic in blocklength. Equitz
& Cover open by noting a *single* Gaussian variable is **not** successively refinable:
the optimal 3-bit Lloyd–Max quantizer is not a refinement of the optimal 2-bit one.
Per-pixel palette assignment is blocklength 1. Lastras & Berger (*IEEE Trans. IT*
47(3), 2001) bound the damage universally: **≤ 0.5 bit/sample** under MSE.

**Successive refinement ≠ multiple description.** MD pays a mandatory redundancy term
`I(X̂₀; X̂₁)` because either description alone must be useful. SR is the corner where
that term vanishes. *If the loss mode is "the reader stopped early," pay zero. Do not
build MD redundancy into a prefix-truncation problem.*

---

## 2. What Tesseract already has

`PairTree.swift:28-32`, verbatim:

> "Leaf order: generation choices are the index bits, FIRST generation = MSB (bit 6) —
> low bits are the finest pairings, so prefix truncation pools depth-first subtrees
> (PT5, the rung alignment). σ half: T[255−i] = ground(gm, T[i]) — the complement
> preserves every pairing level (PT6)."

The GIF index byte is already a head:tail code:

| bits | meaning |
|---|---|
| 7 | which half — subject or ground (the σ involution) |
| 6…0 | the seven tree generations, coarsest first |

Green axioms in `spec/quantization/PairTree.hs`:

- **PT5** — the prefix law: truncated index ≡ coarser palette
- **PT7** — analytic conservation: children's means average back to the parent
- **PT9** — leaf/node coherence: the depth-4 node has exactly the mean of its 8-leaf
  octet. The check line reads **"2×2×2↔1"**.

**The index to decode already exists too.** The DYAD STATS v3 line in the GIF comment
— 13 numbers per frame — regenerates every palette byte, and `RESOLVING`
(`GIFMachine.swift:195`) reads it back and re-solves the tables **byte-equal**. The
file carries its own decoder.

**PT7/PT9 and the OctaveCodec's CX2 are the same theorem in two domains:** a palette
node is the exact mean of its children; a spacetime cell is the exact mean of its
2×2×2 leaves. Refinement in color, refinement in space-time. One operator.

---

## 3. The palette permutation is exactly free — in GIF, and only in GIF

**Theorem (LZW parse invariance).** LZW's compressed length is *exactly* invariant
under any permutation of the used alphabet. Induction on the greedy parse: relabeling
maps the initial table entry-wise, phrase boundaries are identical, every new entry is
the σ-image of the original, so code count, code-width increments, and clear timings
all coincide. GIF stores the table verbatim, so **file size is exactly invariant**.

Verified three ways: byte-identical GIF sizes across 3 images × 3 random
256-permutations; an independent code counter giving 6,773 codes for identity and
every permutation.

**Caveat:** invariance holds only *inside the used alphabet size*. Permuting values
0–63 out into 0–255 changes GIF's minimum code size and does change the file.

**Two consequences.**

1. **The whole log₂(256!) ≈ 1684 bits of ordering freedom can be spent on structure.**
   The tension between prefix semantics and compression does not exist here.
2. **No palette reordering can ever shrink a GIF.** Any such proposal is a no-op. The
   only GIF-side levers are palette *content* and *cardinality*.

Outside LZW the picture inverts completely — reordering is worth a great deal to
predictive and context coders. One measured example, same image ordered vs permuted:

| | ordered | permuted |
|---|---|---|
| H₀ of index image | 5.713 bpp | 5.713 (invariant by construction) |
| H₀ of MED residual | **2.905 bpp** | **6.906 bpp** |
| gzip of raw indices | 32,840 B | 32,906 B (+0.2%) |
| gzip of MED residual | 27,500 B | 53,377 B (+94%) |

**The general law** (Pinho & Neves survey, *IEEE TIP* 13(11), 2004): *the optimal index
order is a function of the decoder's model* — |Δ| smoothness for predictive coders,
bit-plane region compactness for bit-plane coders, frequency ordering for palette
truncation, and **exactly nothing for LZW**. Since our decoder is LZW, bind the order
to whatever we want to **query** against.

Reordering theory, for reference: the objective is Minimum Linear Arrangement,
**NP-complete** (Garey, Johnson & Stockmeyer 1976). Best heuristic is Memon &
Venkateswaran's pairwise merge, O(M⁴) (*IEEE TIP* 5(11), 1996). Zeng, Li & Lei (ICIP
2000) get within 3–5% at O(M³); Pinho & Neves (*IVC* 24(5), 2006) proved the two are
the same algorithm under stated restrictions.

---

## 4. GIF89a's own head:tail machinery — all of it currently off

Encoder writes Image Descriptor packed byte `0x87` = `1000 0111`.

| bit | field | our value | what it would buy |
|---|---|---|---|
| 7 | Local Color Table | 1 | (in use) |
| **6** | **Interlace** | **0** | four-pass row progression: rows 0,8,16…; 4,12,20…; 2,6,10…; then odd |
| **5** | **Sort** | **0** | see below |
| 2–0 | LCT size | 111 (256) | (in use) |

**Sort Flag**, [GIF89a spec](https://www.w3.org/Graphics/GIF/spec-gif89a.txt), defined
for both the GCT (lines 830–840) and LCT (lines 1067–1078), verbatim:

> "Indicates whether the Local Color Table is sorted. If the flag is set, the Local
> Color Table is sorted, in order of decreasing importance… This assists a decoder,
> with fewer available colors, in choosing the best subset of colors; **the decoder may
> use an initial segment of the table to render the graphic.**"

**That is a prefix-quality contract on the palette, standardized in 1989.**

The spec suggests frequency ordering; a refinable tree wants hierarchical ordering, and
one permutation cannot serve both semantics. **But the tree can satisfy the flag's
actual contract honestly** by laying the table out in level order — entries 0–1 are the
two depth-1 node means, 2–3 complete depth-2, 4–7 complete depth-3, and so on. Then an
initial segment genuinely *is* the best 2ᵏ-color subset. That relabeling is a bit
reversal of the current leaf order, and by §3 it costs nothing.

Also: *"an unlimited number of images may be present per Data Stream,"* each with its
own sub-rectangle, own LCT, and a transparency index — so refinement **layers** are
legal syntax, not a hack.

---

## 5. The dither is already scale-nested, and that is a theorem

Bayer's recursion, `M_{2n} = 4·(J₂ ⊗ M_n) + (M₁ ⊗ J_n)`, has the property that for
0 ≤ m ≤ k with stride s = 2^{k−m}:

> `{(x,y) : M_k(x,y) < 4^m}` is the sublattice `{(s·x′, s·y′)}`, and on it
> **`M_k(s·x′, s·y′) = M_m(x′, y′)`**.

**The first 4ᵐ ranks of the fine array ARE the coarse array, dilated.** Closed form
(verified numerically at k=4): `M_k(x,y) = radix4_digit_reverse(Morton(x⊕y, y))` —
so the Bayer ordering is literally the **van der Corput radical inverse in base 4** of
the Morton curve of the sheared coordinates, and the van der Corput prefix theorem
transfers verbatim.

**Two nesting properties, routinely conflated. Keep them apart:**

- **N1, level-nesting:** thresholding at successive grays gives nested "on" sets.
  Tautological for any threshold array.
- **N2, scale-nesting:** prefixes of the ordering are exact coarse copies at a coarser
  lattice. **Bayer has this. Void-and-cluster and blue-noise masks do not.**

★ **This inverts standard halftoning advice.** "Upgrade Bayer to blue noise" is correct
for a single fixed scale and **wrong** if the dither must refine across scales. Our
existing 4×4 matrix (`DyadPipeline.swift:70`) is already the head:tail dither.

**The price of nesting is known and named.** Mitsa & Parker (*JOSA A* 9(11), 1992),
verbatim: *"It is this restriction that is responsible for the superiority of
error-diffusion techniques over conventional ordered dither, since the dot profiles for
error diffusion are independent and can be optimum for many gray levels."* One ordering
(N! choices) instead of independent per-level patterns (∏ C(N,g) choices) — **the
identical trade as successive refinement versus per-rate-optimal codes.**

**Warning for any future dither work.** Georgiev & Fajardo's swap-optimized blue-noise
masks (SIGGRAPH 2016 Talks) **lose the thresholding property**. If prefixes must be
good, use sequential greedy construction, never a swap optimizer.

---

## 6. Prior art for a refinable palette — it exists

**Chen, Kwong & Feng, "A new compression scheme for color-quantized images,"** *IEEE
TCSVT* 12(10):904–908, 2002. Verbatim: *"a **binary-tree structure of color indexes**
is proposed. With this structure, the new algorithm can progressively recover an image
from **two colors to all of the colors** … a lossless recovery is achieved."* Reported
~30–40% smaller than GIF or PNG with progressive transmission.

**Podlasov & Fränti (ICIP 2006)** improve it in exactly the place we are exposed:
*"**merge-based** color quantization instead of the original **splitting** strategy …
better compression performance and a **better reproduction quality in the color
progression**."*

Also: **Rauschenbach (SPIE 4067, 2000)** — color-progressive rather than
resolution-progressive palette images, via color-map sorting + bitplane prediction +
Golomb coding. **Neves & Pinho (ICASSP 2006)** — reorder by recursively splitting the
palette MSB-first into G1/G2, then G11/G12 and G21/G22, so "the index's high bits are
the coarse color grouping."

**Four literatures converged on one recipe: high-order bits carry the coarse decision.**
Bayer's dither recursion; Neves & Pinho's bit-plane split; Chen's binary color tree;
and `PairTree`. We arrived from the Gaussian-splitting side; they arrived from coding.

**Modern codecs abandoned global permutation entirely.** HEVC-SCC and AV1 use small
*per-block* palettes (2–8 entries in AV1) with an inter-block **palette predictor**
and run/copy-above index coding. Palette mode is worth −15.5% BD-rate on screen
content, ~0.0% on camera content. **Tesseract already has that architecture in another
guise:** per-frame LCTs (the ★PERFRAME-PALETTE decree) with a predictor across frames
— the JEPA-H head smoothing the 16-slot ring *is* the palette predictor.

---

## 7. Zero-cost indexes, and where "after watching we process" comes from

Every scheme that gets both properties — valid coarse decode from a prefix, *and* good
quality at every prefix length — derives its index rather than transmitting it:

| scheme | index | wire cost |
|---|---|---|
| **EZW** (Shapiro 1993) | significance map as P/N/ZTR/IZ symbols, coded inline | large |
| **SPIHT** (Said & Pearlman 1996) | LIP/LIS/LSP lists **re-derived from the execution path** | **zero** |
| **RDE** (Li & Lei 1999) | expected R-D slope, computable at both ends | zero |
| **EBCOT/JPEG2000** (Taubman 2000) | tag trees + comma codes in packet headers | small, separately compressed |

SPIHT, verbatim: *"if the encoder and decoder have the same sorting algorithm, then the
decoder can duplicate the encoder's execution path if it receives the results of the
magnitude comparisons, and the **ordering information can be recovered from the
execution path**."*

**Tesseract is already near that ideal**: 13 numbers regenerate 768 bytes of table. The
tree *structure* costs nothing; only the Gaussian's parameters are on the wire.

**"After watching we process" is EBCOT's architecture.** JPEG 2000 codes every block to
completion and *then* decides what to keep, using measured R-D slopes (PCRD-opt). The
Lagrangian separates per block, and Chou–Lookabaugh–Gray's pruning theorem (*IEEE
Trans. IT* 35(2), 1989) proves the hull-optimal subtrees are **nested** as λ sweeps —
the same argument for trees that PCRD-opt is for code-blocks.

**Truncating off the hull is catastrophic:** measured penalties **>10 dB** for
non-R-D-optimal truncation points. *Embeddedness alone is worth nothing; embeddedness
with hull-optimal truncation points is the property worth having.*

**The design-order warning that most affects us.** Pruning is optimal only *given the
tree*, and growth is greedy top-down — so **the first split determines the 2-entry
palette forever**. `PT8` splits on argmax variance, which optimizes leaves. If the 2-,
4-, and 8-entry heads must look good, enforce it during *growing* (Riskin–Gray, or an
explicit multi-rate Lagrangian), or grow bottom-up per Podlasov & Fränti.

---

## 8. What memory actually keeps

The GIF is 64 frames at 20 Hz over 3.2 s. Here is what the literature predicts a human
retains of such a burst.

**Total retrievable ≈ 4–9 items, not 64.** Endress & Potter (*JEP:General* 143(2),
2014) — RSVP at 4/s, lists to 100 pictures: capacity **9.1** from 21-item lists, **30**
from 100-item lists, no clear ceiling. Whole report at ~10 Hz gives ~3.4 of 5
(Nieuwenstein & Potter 2006). Sperling's whole-report ceiling is ~4.5.

★ **Novelty is the single largest lever in the entire literature.** With a small
*reused* item pool, Endress & Potter's capacity collapses to **2.7–4.4 items**.
Proactive interference across repeated captures beats encoding rate, decay, and set
size combined.

**Recency dominant; primacy weak or absent.** Endress & Potter found *no* primacy at
4 Hz. Primacy is the rate-sensitive component and needs rehearsal time that 50 ms/frame
does not afford. Expect **flat-then-rising, not U-shaped**.

**The recency window is a time ratio, not a count.** SIMPLE's discriminability
`η = exp(−c·|log Tᵢ − log Tⱼ|)` depends only on the *ratio* of ages. With typical
c ≈ 3, items within ≈1.4× the last item's age — at 50 ms/frame with a 1 s gap, ~8
frames; with a 0.5 s gap, ~4. *(Derivation from the fitted equation, not a measured
value.)* **Murdock's classic 8-item window does not transfer to 8 frames.**

**50 ms/item is exactly the visual encoding floor, with zero headroom** (benchmark
2.4). 20 fps is at the limit of what can be encoded at all.

**Precision loss over our exact window.** Pertzov et al. (*JEP:HPP* 39(5), 2013), set
size 4: uncued **1.5 deg/s** (spatial) and **2.2 deg/s** (color), both significant.
Over 3.2 s that is ~5–7° added onto a ~13° baseline — a **35–50% error increase**.

★ **A retro-cue erases that loss entirely**: validly cued slopes are **0.2 and 0.5
deg/s, indistinguishable from zero**. But the cue needs ~1 s to act — nothing at 300 ms,
clear by 1,000 ms.

★ **And a visual suffix destroys recency.** Hu et al. (*JEP:HPP* 40(4), 2014): a
to-be-ignored visual event **250 ms after the last item selectively abolishes recency**
(suffix × position F(6,114) = 3.38, p < .01, η² = .15) with **no effect on early
positions** (all p > .10). The tail's advantage is an attentional priority state, not
storage.

**Tesseract transitions WEAVING → SOLVING within roughly one display tick (~50 ms) of
the 64th frame, into a busy scene.** That is inside the suffix window. The SOLVING
scene then occupies the retro-cue window and currently spends it on telemetry.

*(Epistemic note: these are lab findings about item memory in controlled displays.
Applying them to a camera UI is a real leap — but a checkable one, and the predicted
direction is unambiguous.)*

**Corrections to widely-repeated numbers.** Zhang & Luck (2009) is often cited as
showing near-perfect retention at 1 and 4 s. The actual mixture parameters at set size
3: **26% of color items already unavailable at 1 second**, 39% at 10 s, with precision
(SD) *constant* throughout. **Items vanish; they do not blur.** Contested by Donkin et
al. (2015), who find sudden death emerges as primary only when a verbal-labeling
component is modeled.

**The war is not settled.** The 17-author consensus (Oberauer et al., *Psych. Bulletin*
144(9), 2018): *"the time course of forgetting over the short term is contested and as
yet unclear."* Oberauer (2026, *JEP:LMC* 52(2)) reports the sharpest anti-decay result
yet — **more free time between items improves recall**. Do not build on either side
having won.

---

## 8b. ★ THE HEAD QUESTION, ANSWERED

**Should the head be ensemble statistics over everything, or a few items at high
precision?** The literature answers: **build a hierarchical head — and at 64 frames /
50 ms, the ensemble dominates, because "a few items at high precision" is not actually
on the menu.**

### Why the ensemble

1. **It is free and does not consume item capacity.** Ariely (2001): mean size judged
   accurately while individual membership is at chance. Ensemble statistics are stored
   *alongside* and partly *independently of* item representations.
2. **It is what survives when items don't.** Swallow, Zacks & Abrams (2009), at a
   **five-second** delay: conceptual/gist memory holds (d = 1.46) while perceptual
   detail **reverses sign** (d = −0.411).
3. **Gist genuinely arrives first, by a measured margin.** Greene & Oliva (2009):
   global scene properties at **34 ms**, basic-level categories at **50 ms**, difficulty
   controlled, t(19) = 7.94. Coarse-first is the measured order of operations.
4. **★ The ensemble makes the items better, not worse.** *JEP:HPP* (2020): individual
   item precision **tracks the precision of the stored mean**, which tracks the
   *physical range* of the set — items are reported **more precisely when the set is
   more homogeneous**. A summary head is not a tax on the tail; it is a prior that
   improves it.
5. **It is Bayes-optimal.** Brady & Alvarez's three-level model, **one free parameter**
   (encoding noise = 25 px, not fit to the bias data), reproduces the human bias at
   **r = .89**. Biasing items toward the ensemble *minimises expected error*.
6. **At 64 items, the alternative isn't available.** Total retrievable is ~4–9. A head
   of "a few items" would cover **under 15%** of the burst.

### Why some items anyway

- **The last item is genuinely privileged, and free.** Gorgoraptis et al. (2011): the
  final item of a sequence is stored **with precision equivalent to a simultaneous
  array of the same size** (F(1,83) = 0.18, p = 0.67), while everything earlier is far
  worse (F(1,7) = 47.7, p < .001).
- **The ensemble bias is small and conditional.** Registered replication (N = 663):
  **dz = 0.23**, only 57.8% biased in the expected direction. And the *group-level*
  bias **vanishes entirely** when the grouping dimension is task-irrelevant (bias
  0.99–1.00). An arbitrary partition buys nothing.
- **Adam, Vogel & Awh (2017)** remains the standing counter-evidence: whole report finds
  non-zero information for only 3–4 items at set size 6, confidence tracking the guess
  parameter at r = .94.

### The three-level head

| level | what | condition |
|---|---|---|
| **1 — display ensemble** | regression toward the whole-set mean | **unconditional**; survives task-irrelevant grouping and unstructured displays |
| **2 — group ensemble** | mean within a partition | only over a **task-relevant** grouping; an arbitrary one measures 0.99 (p = .39) |
| **3 — a few high-precision items** | specifically **the most recent** | free by recency, not chosen by importance |

### It depends sharply on set size and rate

| regime | verdict |
|---|---|
| ≤3 items, ≥500 ms each | **Items win.** Kool et al.: at set size 3, uniform performance, *no recency at all*. Nothing is being lost, so there is no ensemble pressure. |
| 4–8 items, moderate rate | **Mixed.** Where Brady & Alvarez measured the bias; ensemble contributes ~18% of the reported value. |
| **64 items at 50 ms — ours** | **Ensemble dominates, decisively.** Encoding is at its saturation floor with zero headroom; the burst is **one attentional episode**; item capacity is ~4–9 of 64. The ensemble is the only representation that scales. |

**Tesseract already computes the ensemble form** — nine numbers per frame, EMA'd on a
16-slot ring, while watching. That is the right head. It was arrived at for unrelated
reasons.

### ★★ The corollary that redirects the whole design

**The tail's job is BINDING, not fidelity.**

Gorgoraptis et al. (2011), sequential vs simultaneous presentation of the same items:

| mixture parameter | sequential | simultaneous | test |
|---|---|---|---|
| **κ (fidelity)** | — | — | F(1,75) = 0.47, **p = 0.50 — indistinguishable** |
| α (report target) | 74% | 93% | p < .001 |
| **β (report NON-target = misbinding)** | **19%** | **4%** | F(1,60) = **46.5**, p < .001 |
| γ (random guess) | 7% | 3% | p = .028 |

**A sequence does not lose its frames. It loses which content belonged to which frame.**
Fidelity is *statistically identical*; the entire cost is misbinding. Corroborated by
Bays, Catalao & Husain (2009), who re-decomposed Zhang & Luck's set-size-6 data and
found random guessing was **14%, not 62%** — most apparent item loss is misbinding.
And by Sligte et al. (2008): *"errors in iconic memory are location errors and not
intrusion errors — the location of items is lost over time and not the identity."*

So a refining tail should **not** spend its budget sharpening frames. The frames are
already as sharp as 50 ms allows (encoding saturates: the slope from 200 ms to 2,000 ms
for simple features is **not different from zero**, t(11) = 0.61, p = .555). It should
spend it on **re-establishing which content belongs to which frame** — the thing a
64-frame single-episode encoding actually destroys.

### Two more findings that constrain the design

**Capacity is constant in bits, not items.** Brady, Konkle & Alvarez (2009): learning
four colour pairings took K from **2.7 → 5.4** while the Huffman-coded bit total stayed
**constant** (model r = −.96, 92% of variance, ~10 bits). Removing the regularities
dropped K back to 3.0 with bits unchanged. **Learned redundancy is a better lever than
either precision or summary statistics.** *(Their caveat: the "10 bits" depends on
encoding assumptions; what is assumption-free is that bits are constant while items are
not.)*

**More exposure buys nothing; more silence buys 4×.** Intraub (1980), via Potter (2012):
a picture shown **110 ms in RSVP is remembered 20% of the time; the same 110 ms followed
by a 1,390 ms blank is remembered 84%.** Combined with encoding saturation and Wyble et
al.'s finding that **episode termination requires a ~150 ms gap** — a 64-frame burst at
50 ms with no gaps is encoded as **one episode**, with good content accuracy and
degraded internal ordering (within-episode order accuracy 79% vs 91% when separated).

### One framing to retire

If the design rhetoric is ever "memory is sparse," note that Rensink co-authored both
the 1999 sparse-representation claim **and its withdrawal**. Simons & Rensink (2005),
verbatim: *"the existence of change blindness **does not on its own necessitate sparse
representations**."* Hollingworth (2004) found objects remembered above chance across
**402 intervening objects**; Mitroff et al. (2004) found that on *missed-change* trials
observers recognise **both** pre- and post-change objects above chance. **The bottleneck
is the comparison operation, not storage** — which is the same conclusion as the
binding result above, reached from the other direction.

### The biological analogue of the refining tail

Sligte, Scholte & Lamme (2008), *PLoS ONE* 3(2):e1699 — three stores, separated by when
a retro-cue arrives:

| store | capacity | duration | destroyed by |
|---|---|---|---|
| iconic | unlimited (tested to 32) | few hundred ms | light masks |
| **fragile VSTM** | **>10 objects** — "always about twice robust VSTM" | **~4 s**, decaying | **pattern masks that spatially overlap** |
| robust VSTM | ~4 | stable to 4 s | — |

**A ~4-second, ~2×-capacity buffer sits between the sensory image and durable memory,
and what kills it is overwrite, not time.** Our 3.2 s window is almost exactly its
lifetime. If the design wants a biological warrant for a head:tail split with a
short-lived high-capacity tail, this is it.

---

## 9. The gap between the artifact and the proposal

| the proposal wants | what exists | what is missing |
|---|---|---|
| head:tail split | PT5/PT7/PT9, proved | nothing *uses* the prefix except one fixed 32-level chaos target |
| an index to decode | DYAD STATS v3, byte-exact via `RESOLVING` | it is a comment, not a queryable structure |
| declared to the reader | Sort Flag exists in GIF89a | set to 0; table is in leaf order, not level order |
| refinable dither | Bayer 4×4 is scale-nested by theorem | the nesting is never exploited across rungs |
| palette permutation as a resource | free by LZW invariance | spent implicitly, never as a named decision |
| non-uniform allocation | — | every frame gets an identical 256-entry LCT |

That last row is the one memory speaks to most directly. **Tesseract spends its tail
perfectly uniformly.** Memory does not: it keeps a summary of everything plus detail
for a handful, weighted toward the end, and loses the rest all-or-none. If the GIF is
a memory, uniform allocation is the thing that is wrong.

---

## 10. Numbers worth carrying

- **≤ 0.5 bit/sample** — universal worst-case penalty for successive refinement
  (Lastras & Berger 2001). For refinable sources: **zero**.
- **> 10 dB** — measured penalty for truncating off the R-D convex hull.
- **10–30%** — measured scalability penalty in SVC/SHVC, entirely attributable to
  closed-loop prediction and per-layer syntax, neither of which we have.
- **exactly 0** — cost of any palette permutation in GIF.
- **4–9 of 64** — items a human retains from a 3.2 s burst. **~3** if content repeats
  across captures.
- **250 ms** — the window in which a following visual event destroys recency.
- **~1,000 ms** — the delay at which a retro-cue starts rescuing precision.
