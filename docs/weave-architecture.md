# THE TESSERACT ARCHITECTURE — one cube, three views, one edit

Tesseract is a front-camera machine that turns 3.2 s of R,G,B + depth into a GIF89a of 64 frames × 64² palette indices with one 768-byte Local Color Table per frame, and then lets the user re-weave that same retained cube into different GIFs by moving a small integer tuple. This document fixes who owns which rung, where entropy is allowed to sit, what each of the four signal channels is responsible for, what a model may and may not write, and what an edit costs — and it corrects, in place, the four claims the first draft of this architecture got wrong.

---

## 0. The four things being organized

Daniel, 2026-08-14: *"What I need is a clear architecture. We need to organize: the three views, the background and user entropy concentrations, and use the R,G,B,depth signal to maximize fidelity and color. This is an EDIT app so we only need the models to inform the weave so that we can edit to make different GIFs."*

Restated as four questions this document must answer with numbers:

1. **THE THREE VIEWS.** 16³ ≡ 32³ ≡ 64³ — which rung owns which decision, at which cadence, and what may cross between them in each direction.
2. **ENTROPY CONCENTRATION BY ROLE.** The user half (figure) addresses 128 entries over ~25 % of the cells; the background half addresses ≤ 16 entries over ~75 %. What that costs, what it buys, and what the correct target is.
3. **THE SIGNAL.** R,G,B and depth are not two fidelity channels. Depth is the ALLOCATION channel and RGB is the RECONSTRUCTION channel; colour impact and reconstruction distortion have different meters.
4. **MODELS INFORM ONLY.** One model line, one licensing law (WS10), and a structural placement that makes "informs, never decides" checkable rather than promised.

Standing decrees are assumed, not restated: front-only; per-frame LCTs only; no naked constants; no-capture-training; provenance (the table is a pure function of the traced generating numbers); simplicity; edit-is-the-whole-app; iterative not replacement; spec-first.

---

## 1. The three views

**THEOREM (structural, no ruling needed).** The ladder is closed at {64, 32, 16}. `Rung` is an enum whose rawValue is simultaneously the side and the frame count, with `delayCs` derived from the single loop constant, so an off-ladder rung is unrepresentable and TL4's integer-centisecond clause is enforced by the type rather than asserted: 320/128 = 2.5 cs has no representation (`Tesseract/Tesseract/FeedFormat.swift:110-140`; `spec/output/TriScaleLadder.hs:169-177`). Any future rung proposal is answered by TL4, not by taste.

| rung | owns | cadence | rate (balanced, coherent) | crosses DOWN | crosses UP |
|------|------|---------|---------------------------|--------------|------------|
| **64²** | ASSIGNMENT — one index per GIF pixel; arrangement energy E_wall; the dither's phase placement | 20 Hz | 15894 idx b + 6144 table = 22038 b · **5.4 b/cell** · table share 27.9 % | (source) | the frame's occupancy histogram |
| **32²** | *nothing today* — CHOICE below | 10 Hz | 7446 + 6144 = 13590 b · **13.3 b/cell** · 45.2 % | κ-pooled feed | the measured nesting defect |
| **16²** | SOLVE — the table, the depth mixture, the JEPA ring, the σ blur target, E_hist | 5 Hz | 2324 + 6144 = 8468 b · **33.1 b/cell** · 72.6 % | κ-pooled feed | the 16 slot tables + sweep budget K |

Rate rows are measured with the encoder's own LZW law (`docs/occupancy-workflow.md:24-32`).

**DOWNWARD, evidence only.** κ pools the four-channel feed (L,a,b,d). Indices are never pooled — a palette index is not a linear quantity; the feed is pooled and then re-assigned (`DyadPipeline.swift:1017-1024`, `:1032-1044`).

**UPWARD, decisions only.** The rung-16 slot solve (table + primaries + σ address book), the runtime sweep budget K, and the polyphase phase target. No pixels, no indices, no colours travel upward.

**MEASUREMENT.** Rung 32 owns no byte-affecting decision anywhere in shipped code: it appears at `TriScaleLadder.swift:176` (telemetry), `FeedFormat.swift:371-379` (unwired), `Arrangement.swift:113` (display widget).

**★ RULED (Daniel, 2026-08-14): "all rungs require a meaningful additive to the creation of GIFs."** The CERTIFICATE choice is withdrawn. No rung may hold a measurement-only job: each of the three writes bits that land in the emitted index. §1.3 is the law that replaces this paragraph, and it also repairs §1.1 — balance is no longer authored at 64 and hoped to survive pooling; each rung authors its own stratum natively.

### 1.1 REPAIR — "balance authored at 64 nests 16→4→1 for free" is not a theorem

The first draft carried this as proved. It is not, for three independent reasons:

- **THEOREM (spec).** `poolAt` is a stride-2 **SUM** over all eight block members at phase `o` — the phase moves the block ORIGIN, it does not select a sublattice — and TL11 proves the eight phases sum to a [1,2,1]³ tent (`spec/output/TriScaleLadder.hs:313-320, :350-357, :359-386`). "Selecting a phase — which is what the 2×2×2 pool *is*" (`docs/occupancy-workflow.md:66-75`) misreads TL10–TL12.
- **THEOREM (shipped carrier).** The coarse reads pool the FEED and then call `assign` (`DyadPipeline.swift:1032-1044`), so a coarse index is `quantize(mean)`, never a decimated fine index. On the measured device scene the wall is near-monochrome (ground-hue diagnosis, R = 0.9913): it pools to one point and takes ONE index at every coarse rung regardless of how the fine frame is dithered. Occupancy does not descend at all.
- **MEASUREMENT (certificate scope).** The 2000/2000 bipartite-matching evidence is a one-step 4:1 spatial selection at phase 0. Two κ steps with all eight phases at each level is a 3-index (axial) transportation feasibility problem; axial transportation polytopes are not integral and Birkhoff/Hall does not extend.

**Consequence:** "author fine, validate coarse" survives as a *direction* (constraints belong in the dither, not in a per-rung repair pass) and is demoted from THEOREM to OPEN. §1.3 dissolves the question rather than answering it: under the additive law nothing has to survive pooling, because each rung writes its own bits directly.

### 1.3 THE ADDITIVE LAW — every rung writes bits of every index

Daniel's ruling, 2026-08-14. The three views are not three resolutions of one
decision; they are **three strata of one index**, and the index is their sum.
This is not a new mechanism — it is two shipped laws read together:

- **PT5 (proved, `spec/quantization/PairTree.hs:256-271`).** Truncating ℓ bits
  of the nearest-leaf index equals the nearest level-ℓ centroid:
  quantize-coarse ≡ coarsen-quantized, exactly. So a prefix IS a coarse
  palette, and the remaining bits ARE a refinement.
- **DL1 (proved, `spec/neural/DescentLadder.hs:31-33`).** The descent has fixed
  serial depth 3 with fan-outs [2,8,8] — one bit, then two bit-triples. The
  triples are the 2×2×2 atom. DL2's output nesting says an early exit equals
  the class above, which is the same statement from the model side.

Assign each stratum to the rung whose voxel count pays for it. Daniel ruled the
role bit OUT of the rung strata (depth owns allocation, the rungs own colour),
so rung 16 carries the odd bit and the role plane is priced separately:

| stratum | writer | voxels | bits | bits/cube | balanced occupancy |
|---------|--------|--------|------|-----------|--------------------|
| **role** (bit 7) | depth, via the Bayer coverage code | 4096 | log₂17 | 16742.2 b (2.04 KiB) | — |
| **rung 16³** (bit 6) | 16³ | 4096 | 1 | 4096 b (0.5 KiB) | **1024 per class** |
| **rung 32³** (bits 5–3) | 32³ | 32768 | 3 | 98304 b (12 KiB) | **1024 per class** |
| **rung 64³** (bits 2–0) | 64³ | 262144 | 3 | 786432 b (96 KiB) | **1024 per class** |
| **Σ** | | | **8** | **905574.2 b = 110.54 KiB** | |

against 262144 × 8 = 2097152 b = 256 KiB if every voxel chose freely: a
**2.3158:1 structural ratio**, paid for by the ladder's shape rather than by any
coder. Spec `spec/output/AdditiveLadder.hs`, AD1–AD10 green.

(Observation, not a theorem: the shipped export already measures ~111.6 KB of
LZW wire — the same order as this budget, i.e. LZW is already finding
approximately this much structure empirically. It is not evidence for the law.)

**THEOREM (AD7) — the role bit is DERIVED, not written.** σ is a threshold of
the fixed Bayer matrix against the rung-16 coverage field, so a 4×4 tile has
exactly **17** reachable σ patterns (RL6's coverage code), nested in k, and the
whole fine σ plane reconstructs from the coarse field alone. A free bit plane
at the fine rung would cost 262144 b = 32 KiB and admit 2^16 patterns per tile;
the derived form costs 2.04 KiB. The band mechanism pays for itself.

**THEOREM (the invariant the previous framing lacked).** Voxels multiply by 8
per rung and classes multiply by 8 per rung, so **balanced occupancy is the
same number at every rung: 1024 voxels per class.** That is what
16³ ≡ 32³ ≡ 64³ means for colour, stated as one constant instead of the
16 / 4 / 1 per-frame ladder that had zero slack at its coarsest end.

**Consequences:**

1. **Occupancy becomes per-stratum and LOCAL.** Rung 16 balances 4 ways over
   4096 voxels; each rung-32 node balances its own octet; each rung-64 node
   balances its own octet. Fan-out 8 at a node, never 256 globally — which is
   exactly the "8:1 grounded in latent algos" the PAIR TREE ruling asked for.
2. **§2.8's cap is re-derived, not repealed.** The role mass split still binds
   what a single 16² *frame* can show; the additive law moves the accounting to
   the cube, where 1024-per-class is reachable at every rung.
3. **The energy already decomposes this way.** WS4 proves
   E = E₄ + E₃₂|₄ + E₂₅₆|₃₂ exactly (2+3+3), so each rung's bit contribution
   has its own energy term and the terms sum. Per-rung colour budget and
   per-rung energy budget are the same object.
4. **Assignment becomes the log-time descent** the PairTree ruling named as its
   destination, and DL6/DL7 (conditional exactness, dominance) already price
   its accuracy.

**★ RULED (Daniel, 2026-08-14) — the σ bit stays separate.** The
role/allocation bit sits above all three strata and is written by depth, not by
any rung: depth owns allocation (§3), the strata own colour. The rejected
alternative (fold it into rung 16 as a 1+1 split) would have made rung 16 write
2 bits and the cube budget 892928 b = 109.0 KiB at ratio 2.349:1 — cheaper on
paper, but it prices the band's per-pixel routing as a rung decision, which it
is not.

**SPEC LANDED:** `spec/output/AdditiveLadder.hs`, AD1–AD10 green — the
partition, the composition identity, forced rung seating, the 1024 invariant,
prefix consistency (PT5's algebraic half), descent correspondence (DL1/DL2),
the derived role bit (AD7), the budget, energy alignment with the TE/WS4 chain
rule, and AD10: *no rung is silent* — for each rung there exist indices
differing only in that rung's bits, so no rung can be demoted to telemetry
without changing the artifact. The Swift port lands at S8.

### 1.2 Ladder defects to close before any dial ships (all byte-neutral or byte-fixing, no ruling owed)

| defect | evidence | fix |
|---|---|---|
| κ materialized 7× over 3 carriers, no call between them | `TriScaleLadder.swift:100`; `FeedFormat.swift:301`; `OctaveRead.swift:183`; `DyadPipeline.swift:594, :475-497, :936-963, :1040-1076`; `Quantize.metal:118-140` | one κ, carrier as a parameter, every site delegates |
| two `Rung` vocabularies, no bridge | `FeedFormat.swift:118` vs `OctaveRead.swift:95-130` | delete `OctaveRead.Rung` |
| `JepaHHead.slots = 16` is a literal whose comment claims derivation, and it silently co-indexes the S4 chaos group | `JepaHHead.swift:26`; `DyadPipeline.swift:172, :487, :688-700, :855` | `slots = Rung.coarse.frames` |
| Metal chaos blur hardcodes block `4u` / normalizer `16.0f` while the CPU twin derives it | `Quantize.metal:118-140` vs `DyadPipeline.swift:594-596` | pass through `AerialParams` as the Bayer and DepthSignal anchors already are |
| σ blur block is a RATIO of whatever side it runs on → rungs 8 and 4 at the coarse reads | `DyadPipeline.swift:594-596` called at `:1100` from `:1032-1044` vs TL9 stating depth's rung absolutely (`TriScaleLadder.hs:259-275`) | **Ruling 1** |
| live windows pool SPACE only while the solve pools spacetime, both named "rung 16" | `DyadPipeline.swift:1040-1076` vs `:936-963`; claim of agreement at `WidgetSurfaceView.swift:322-327` | widgets read the ring the solve already builds |
| export anchors temporal groups at burst frame 0, live ring at a free-running counter whose first group is a 1-frame degenerate | `DyadPipeline.swift:487` vs `:928-932` | lock the live phase to capture frame 0 — removes a difference, adds no law |
| `CubeMode.inference = 128` names a cube TL4 cannot encode | `CameraManager.swift:42-49` | delete, or derive `CubeMode` from `Rung.fine` |
| `rungTelemetry` is `@Published` on both managers with no consumer; the RUNG detent is specified and placed nowhere | `CameraManager.swift:138, :750, :764`; `FaceCaptureManager.swift:63, :451`; `DetentDial.swift:76` | wire the read-only meter |

**MEASUREMENT (correction).** WS8's +31.25 % (5376 vs 4096 cell visits) is the SPATIAL shadow — three planes of ONE frame. Under a spacetime κ a rung-32 read exists every 2 fine frames and rung-16 every 4, so the amortized cost of reading all three views is 4096 + 512 + 64 = 4672 visits, **+14.06 %**. Cite that number, not 31.25 %.

---

## 2. Entropy concentration

### 2.1 The ceiling, exactly

**THEOREM.** The per-frame index alphabet is **A = {0…127} ∪ {255 − canon[c] : c ∈ 0..15}, |A| ≤ 144** — not 145. `fars` is all-false at every production call site (`DyadPipeline.swift:446, :1096`), so the far → 255 branch (`:793`) is dead code and `DyadANE`'s `v == 255` lawfulness gate (`DyadANE.swift:128-131`) is dead with it. Index 255 is reachable only as `255 − canon[0]`. The spec already agrees: `coloursUsed shippingAlloc == 144` (`spec/quantization/RoleAllocation.hs`, RA7).

**THEOREM (closes O0's discrepancy).** The device audit's **164** is a UNION over the 64-frame cube, not a per-frame count: tables are per-frame (`DyadPipeline.swift:431-437`), so σ indices accumulate across frames while indices 0…127 contribute at most 128 once. 164 = 128 figure + 36 distinct σ across the cube is the only arithmetic that closes; 128+10 = 138 and 144 both fall short. The audit's "ground half 10 of 128" is a per-frame count and 10 ≤ 16 is fully explained (`spec/quantization/GroundHue.hs:861-880`, GH15).

**THEOREM (why 10 and not 16).** `canonical16` never performs a real selection. PT7's conservation makes each depth-4 node the exact centroid of its 8 leaves, so leaves j and j XOR 7 are antipodal and exactly equidistant; the minimum is a 2-, 4- or 8-way tie resolved by the strict `<` / lowest-index seed (`PairTree.swift:92-100` with `:67-83`). `childVars` depends only on DEPTH, so all 16 octets share identical geometry and every canonical leaf sits at the SAME offset from its node mean — a constant systematic displacement of the whole σ half. The docstring "the octet member nearest its node's mean" (`PairTree.swift:52-55`) is vacuous. Only ~10 of the 16 nodes ever win on a near-monochrome wall.

### 2.2 REPAIR — the sign of the energy

The first draft denominated the whole app in bits and called E = 0 the ground state to aim at. **That inverts the sign.**

**THEOREM.** E = N·log₂K − N·H₀ = N·D(p‖uniform) — bits *saved*, not bits spent. TE3 pins the solid frame at the ceiling E = 32768 b = 8 b/cell and the balanced frame at E = 0 (`spec/statistics/TilingEntropy.hs:249-270`, TE10 at `:362`). So E = 0 is the state of ZERO order-0 compressibility: the maximum index bill.

Therefore the role split's cost must be restated with its sign attached:

**THEOREM.** With ground mass m_g, max attainable H₀ = H(m_g) + 4·m_g + 7·(1−m_g), so E_hist ≥ N·(1 + 3m_g − H(m_g)) = 4096 × 2.438722 = **9989 b/frame** at m_g = 0.75. That is 2.44 of 8 bits per cell. It is simultaneously a **colour ceiling** (30.5 % of the alphabet's capacity is structurally dead) and a **rate saving** (9989 b/frame the wire does not carry). E_hist and E_wall are independent strata (WS3), so arrangement recovers none of it in either direction.

**THEOREM (correcting an arithmetic error in the first draft).** TE5 fixes E₀ = N·(1 − h(φ)) and h ≥ 0, so E₀ ≤ N = 4096 b. The first draft quoted E₀ = 5261 b at m_g = 0.75; the correct value is 4096 × (1 − 0.811278) = **773.0 b**.

**THEOREM.** The "2688 wasted LCT bits" (112 dead σ entries × 24 b, 43.75 % of the table) are **not recoverable by widening the address**: the LCT is 6144 b whether 1 entry or 256 are reachable. Widening recovers exactly zero table bits and spends index bits.

### 2.3 What the lift actually costs

Two independent derivations agree to the bit.

**THEOREM (the spec's own rate law).** RA5: rateBits(t̄, Alloc f b) = 1 + (1−t̄)·f + t̄·b. Moving b from 4 to 7 costs m_g·3 bits/cell = 0.75 × 3 = 2.25 b/cell = **9216 b/frame**, and drops the E_hist floor from 9989 b to 773 b (ΔE = −9216 b). Same number, opposite sign — that is the identity, not a coincidence.

**MEASUREMENT (adversarial simulation, LZW calibrated byte-exact against the two published points 2324 b and 44686 b).** Coherent m_g = 0.75 scene, σ address 16 → 128:

| rung | idx b before | idx b after | wire before | wire after | Δ |
|---|---|---|---|---|---|
| 64² | 8139 | 16015 | 14283 | 22159 | **+55.1 %** |
| 32² | — | — | — | — | +26.3 % |
| 16² | — | — | — | — | +4.5 % |
| cube | | | 111.6 KB | 173.1 KB | +61.5 KB |

**Note the inversion of the workflow's own reading.** `docs/occupancy-workflow.md:38-45` argues occupancy is "a coarse-rung problem first" because a dead entry wastes a larger share of the rung-16 wire. Under the lift the *cost* runs the other way: +55.1 % at rung 64 and +4.5 % at rung 16. The dead-entry share is also mis-bracketed in the first draft — 2688/22038 = 12.2 % divides by the BALANCED frame's wire; a frame with 112 dead entries costs 7269 b at rung 64 and 6441 b at rung 16, giving 37.0 % and 41.7 %.

### 2.4 REPAIR — the σ address width is DERIVED, not chosen

This is the keystone, and it removes the largest open ruling in the workflow by converting it into a measurement.

**THEOREM (already spec-green).** `derivedAlloc λ_F λ_B = Alloc treeDepth (clamp (7 − ⌊log₄(λ_F/λ_B)⌋))`, constant-free, integer arithmetic only, λ_F and λ_B the role-weighted generalised variances of the staged field (`spec/quantization/RoleAllocation.hs:175-190`). RA3 pins `derivedAlloc (64/1) 1 == Alloc 7 4` — **today's shipping allocation is the derived one at a variance ratio in [64, 256)** — and `derivedAlloc 1 1 == Alloc 7 7`, i.e. equal variances derive all 256. RA4 (FIGURE PRIORITY) proves d_F == treeDepth for every ratio in either direction: the user is never quantised to feed the background.

So the diagonal ladder is not a taste and its replacement is not a taste either. **The σ half is narrow because the background IS narrow.** The one number that decides O2/O3 is λ_F/λ_B measured on device:

| measured λ_F/λ_B | derived d_B | σ entries | verdict |
|---|---|---|---|
| ≥ 256 | ≤ 3 | ≤ 8 | today's 16-node prefix is already too wide |
| [64, 256) | 4 | 16 | shipped behaviour is CORRECT; the lift spends 9216 b/frame on colours the background does not have |
| [16, 64) | 5 | 32 | partial lift, derived |
| [4, 16) | 6 | 64 | |
| [1, 4) | 7 | 128 | full lift, derived — no ruling required |

This satisfies NO NAKED CONSTANTS at the exact point the workflow was about to plant one, and it makes O2 and O3 a single instrumented step rather than a single ruling.

### 2.5 What still blocks occupancy even after the address widens

- **THEOREM.** The σ target field is FLAT by construction: the spec's own v7 note reads *"All 16 pixels of a block share one target, hence one σ index: the far field is flat at rung 16"* (`spec/quantization/DyadPalette.hs:538`, § 6d; `DyadPipeline.swift:636-651`). Widening raises the CEILING; it does not raise OCCUPANCY. The one device measurement that predicts the benefit is the **shadow census** (§7, S1).
- **MEASUREMENT (simulation).** Shell geometry, not address width, is the binding variable. With 128 σ addresses already lifted: palette matched to the field → E_hist 1668 b, 253.8/256 alive; background sd 0.5× figure → 5633 b, 219.9 alive; 0.25× → 11571 b, 162.6 alive. Geometry mismatch re-loses 3965 b of the 9216 b freed — 43 %. GH15's `n ∝ √λ` is fitted to the FIGURE's eigenvalues alone; the background's variance never enters the *geometry*, only (via `derivedAlloc`) the *count*.
- **THEOREM.** The eigen-dither proposed in the first draft cannot reach the target it is proposed for. A Bayer-4 offset field has exactly 16 states (`spec/statistics/TilingEntropy.hs:195`), so a constant-colour region takes at most 16 distinct leaves however large it is — 8× short of 128. Reaching 128 needs ≥ 128 offset states, i.e. a 16×16 dither whose period is 16 cells = 64 px on the 256 px output (four visible bands), and the mandated period-4-in-time at 20 fps is a 5 Hz modulation of a flat background, at the peak of flicker sensitivity, beating against the 5 Hz table cadence. **The eigen-dither is NOT adopted.**
- **THEOREM.** The ANE chaos loop cannot widen the alphabet: its candidate set is the block's already-occupied σ indices (`ANELoop.swift:277-297`). It is an E_wall operator and the ask is an E_hist question. It can therefore be flipped freely for device comparison without disturbing any occupancy measurement.

### 2.6 REPAIR — WB13, in the only form that is true

The first draft proposed: *E = 0 ⟹ n_i = n_{255−i} ⟹ image cast = table cast = 0.* **The premise is unreachable and the implication is weaker than advertised.**

**THEOREM.** Under the shipped role law indices 0…127 are reachable only by figure pixels (`DyadPipeline.swift:800`) and 128…255 only by ground pixels (`:642`). Summing pair-balance n_i = n_{255−i} over i ∈ [0,127] gives figure mass = ground mass, i.e. **pair-balance ⟺ m_g = 0.5 exactly**, which no face scene delivers (DM3 plants π_B = 0.75, `spec/temporal/DepthMixture.hs:276`). Further, WB4 is an (a,b) statement (`spec/quantization/WhiteBalance.hs:222-228`) while the shipped pair is (l, a, b) ↔ (l+ΔL, −a, −b) (`DyadPalette.swift:398`), so the L half never cancels.

**WB13, adopted in the weak form — MASS AS GENERATOR.** The ground mirror's centre solves *occupancy-weighted* neutrality m_F·mean_fig + m_g·mean_gnd = c, rather than the table's unweighted neutrality. This gives zero image chroma cast at ANY m_g, costs exactly one new traced number (m_g, which the mixture already computes → DYAD STATS v4), keeps the table a pure function of traced generators, and is completely orthogonal to the occupancy program. Adopt it; discard the ground-state framing that motivated it.

**THEOREM (the regression WB13-weak defuses).** On the balanced branch the table satisfies WB4/WB5 and violates the warning WB7 exists to give — `balancedButCollinear` (`WhiteBalance.hs:27-36, :252`). Ground = (l+ΔL, −a, −b) is exactly `comp()` (`DyadPalette.swift:120-122, :398`), reached whenever `gm.balanced` (`:355, :373`). With mean(canonical leaves) = figure centroid − a fixed offset, the background renders at ≈ −c_F with mass m_g: predicted image cast ratio ≈ m_g × 0.987, **sign-flipped** versus the pre-2026-08-14 mirror (device numbers `WhiteBalance.hs:12-14`: table centroid |c| = 0.0494, mean entry chroma 0.0500). That is the blue haze DY14 v7 was ruled to kill, reproduced by occupancy instead of by the table. It is the first thing the device pass looks at.

### 2.7 The other ground state: the LCT is not a law

**THEOREM (a saving that points the opposite way).** GIF89a permits an image-descriptor size code 0..7 per frame; the encoder hardcodes packed byte **0x87** = 2^(7+1) = 256 entries on every frame (`Tesseract/GIF/GIFEncoder.swift:110-118`), and a contract test pins it (`TesseractTests/DyadGIFContractTests.swift:96-100`). A frame with ≤ 128 live entries legally emits a **384-byte LCT**: 3072 b/frame, **196,608 b = 24 KB per export**, and the WS relabeling proof makes the dense repack free. Today's ≤ 144 alphabet just misses the 128 threshold.

So the palette has two ground states, and they are opposite: **WIDE** (256 alive, +55.1 % of the rung-64 wire, maximum colour impact) and **NARROW** (≤ 128 alive, −24 KB per export, half-size tables at every rung). Ruling 3.

### 2.8 Occupancy targets that are actually reachable

**THEOREM.** Aliveness per frame is capped at min(128, m_F·N) + min(128, m_g·N). At m_g = 0.75: rung 64 and rung 32 can reach 256; **rung 16 caps at 192/256**. So O6's acceptance test — a rung-16 frame that is a permutation of the 256 — is unreachable for any m_g ≠ 0.5, not by the ≤144 alphabet (256/144 = 1.78) but by the role mass split, which is the ROLE layer's entire reason to exist. **O6 as written is retired.** Its replacement is the CONDITIONAL ground state: uniform *within* each half, whose residual floor is E₀ = N(1 − h(m_g)) = 773 / 193 / 48.3 b at rungs 64 / 32 / 16, declared and budgeted rather than treated as failure.

**MEASUREMENT.** Transport is not free and has nowhere been in the ledger. Forced permutation vs free nearest-neighbour, 24 trials, 3-D OKLab-shaped Gaussian, optimal assignment: rung 16 = 1.83× MSE (+2.6 dB) with a matched palette, 5.20× (+7.2 dB) with a palette fitted narrower than the field; rung 64 forced-16-per-entry = 1.24× (+0.9 dB), matching the d = 3 high-rate prediction of 1.28×. Every balance gate carries a D term from now on.

---

## 3. The signal

**MEASUREMENT.** Depth never reaches a byte. s ∈ [0,1] drives exactly four things: the mixture posterior t (`DyadPipeline.swift:212-217`), the γ(s) = 1/(2−s) chroma staging (`:180-194`), the (1−t)/t analysis weights (`:315, :358-363`), and the Bayer coverage routing (`:630`). RGB carries 100 % of the reconstructed signal.

**CORRECTION to the first draft's slogan.** "Depth writes bit 7 and nothing else" is false by the same list: γ stages chroma (proved hue-*contracting*, GH14) and the (1−t)/t weights select which pixels fit the figure Gaussian, i.e. depth reaches the table indirectly. The defensible statement is: **a depth error is an allocation error, never a colour error.** Depth levers are judged on the rate ledger and on role correctness; RGB levers alone move reconstruction distortion.

| channel | owns | meter |
|---|---|---|
| **d** (TrueDepth LIVE / ARKit FACE) | the role split (which half of 256 a cell may address), the band, γ's octave, the analysis weights, m_g | role composition + rate ledger |
| **L** | the tree's first split, the temporal octave carrier | PHASE F distortion D |
| **a, b** | the figure's chroma extent, hue diversity, the mirror centre | measured image cast + distinct entries |

### 3.1 Input-path defects (fix before any colour claim is judged)

1. **REGISTRATION — highest severity on the path.** The 768/256 crops subtend the same field of view only if W_rgb == 3·W_depth (`CameraManager.swift:61-63`; `spec/output/FrameGeometry.hs:28` pins scaleFactor = 3, and G6 at `:125-136` validates only against pairs already 3:1). `.photo` forces preview-sized RGB (`docs/CAPTURE-FUNNELS.md §2`) while `:361-372` selects the WIDEST Float16 depth format. If the ratio is ~1.5, every role decision is applied to a mis-scaled region and nothing downstream is meaningful. Both numbers are ALREADY logged (`CameraManager.swift:460, :371`); one device run settles it, and `feedback_no_crop_changes` does not block reading a log.
2. **DEPTH PREFILTER.** The 16:1 downsample is an unfiltered point sample (`Quantize.metal:220-224`; CPU twin `CameraManager.swift:629-630, :643-644`) taken from the format deliberately chosen to be the highest-resolution available. The pipeline measures its own depth aliasing and reports it to the mixture as scene structure. The FACE twin box-averages correctly (`FaceCaptureManager.swift:320-345`), so the two modes already disagree. 16 texels vs RGB's 144; touches no palette law.
3. **TOTALITY.** Constant per-frame depth against a two-phase pooled field gives temperature = σ²/(μF−μB) = +inf and crossover = NaN (`DepthMixture.swift:31-34`), so t = NaN for every pixel: nothing masked, no Bayer test passes, the frame collapses onto ≤16 σ entries and NaN weights poison its centroid and table. FACE reaches this on any tracking drop (`FaceCaptureManager.swift:192`) and unavoidably on frame 0 (unfiltered, `DepthMixture.swift:197`). `coverage` needs the guard `isTwoPhase` already has (`:105`). *Verdict PLAUSIBLE — arithmetic-confirmed, not device-observed.*
4. **CLAMP ATOMS.** `DepthSignal` clamps to [0,1] with fill 0.5 and anchors dNear 0.25 / dFar 1.5 (`DepthSignal.swift:25, :32-35`), so the fitted field carries point masses at 0 and 1 and a delta at 0.5 that the tied-variance model has no term for; the planted fixture uses interior clusters at 0.05/0.75 (`DepthMixture.hs:276`). For any wall beyond 1.5 m the background collapses onto s = 0 exactly, τ shrinks, the band narrows, and concentration onto ≤16 σ entries gets *worse* in the common scene. **CHOICE:** two Gaussians + three atoms, BIC-selected exactly as DM9 selects component count, with the atom LOCATIONS derived from the clamp map's preimage (not written as 0/0.5/1 literals). *Alternative:* keep two Gaussians and add a planted fixture carrying the atoms so at least the failure is characterised. Note the fill cannot be "derived from the fitted crossover" — the fill is an INPUT to the field the crossover is fitted on; break the loop by excluding invalid pixels as a WEIGHT, not a value. Nothing measures the invalid-pixel rate and `isFilteringEnabled = true` (`CameraManager.swift:357`) hides how often it fires; that number is owed first.
5. **BAND SEMANTICS.** Dropouts read fill 0.5, which lands at or beside the crossover, so the band — the only class reaching both halves of the table — is where TrueDepth is least trustworthy (hair, glasses, IR-absorbers). Defensible (uncertainty ⇒ dither) but currently an accident of a literal. Record it as a law or derive it.
6. **PREVIEW EVIDENCE.** Export fits tables on 4096 samples/frame, the live driver on 256 (`DyadPipeline.swift:1004-1013` vs the export path). Additionally, fitting on a 64-sample-pooled field and applying to the full-band field contracts the shells: with incoherent variance fraction f, pooled sd = √(1−f+f/64) × fine sd, so f = 0.25 → 0.868× and 8.25 % of fine cells fall outside the outermost shell; f = 0.5 → 0.713× / 15.41 %; f = 0.75 → 0.512× / 30.62 %. Those cells clamp onto extreme entries — an occupancy pile-up no balancing pass removes.

### 3.2 Colour levers, with their true prices

- **γ vs stageLOnly.** GH14 proves γ-staging hue-CONTRACTING, exact in ℚ: every staged hue moves toward the face's hue, the far background contracted by exactly γ(0) = ½ (`spec/quantization/GroundHue.hs:824-849`). `stageLOnly` (`:476`) buys the same temporal octave in lightness alone and is proved hue-exact. Ruling 5.
- **The unstaged read.** The background hue resultant must be read on the UNSTAGED field: on a synthetic face-disc/wall frame a true 180° separation fits as 0.4° staged vs 179.0° unstaged (`DyadPipeline.swift:336-357`). The staged read is not a shrink but a non-monotone map returning ZERO in exactly the blue-wall/warm-face case the law exists for.
- **The inert fourth coordinate.** The fitted Δh is computed, EMA'd, JEPA-smoothed and traced, then never applied: `DyadPalette.swift:373` short-circuits to the balanced branch before `rot` is read at `:414`, and the only reader (`priorMoments`, `:264-268`) hard-codes `.identity`. GH1–GH11, the ring's two extra hue dims (`DyadPipeline.swift:745`) and the GROUNDHUE v2 trace (`GIFMachine.swift:151-153`) cost compute and buy zero bytes — the second instance of the 2026-08-11 inert-fix trap.
- **WB2/WB8/WB9 have no Swift port.** No chroma-cap floor (`minimumCap = 64/510` exists only at `WhiteBalance.hs:166`), no hue-distributed shells (`distributedHalf`, `:130`), and `chromaClamp` (`DyadPalette.swift:126-138`) is a many-to-one gamut collapse — the test pins 250, not 256 (`DyadPaletteTests.swift:660-663`). WB8's arithmetic reason for 4–11 collisions per frame is live. Ruling 6.
- **GH12 — the σ search is mis-targeted on every shipped balanced capture.** The blur search minimises d(node, target) while the pixel is displayed as ground(node); these diverge whenever β_C ≠ 1 or ΔL ≠ 0, and the balanced branch applies l+ΔL unconditionally (`DyadPalette.swift:398`). **Step A (display-only rotation) is index-identical and free in LZW — ship it as the riskless half.** Step B (pre-image search in the ground frame) moves pixels.
- **The metric — NOT free.** `dLab2` is plain squared Euclidean OKLab (`DyadPalette.swift:630-633`) at the figure search (`DyadPipeline.swift:797`), the 32-level chaos search (`:639`) and canonical-leaf selection (`PairTree.swift:96`), while the generator is an anisotropic Gaussian whose eigenvalues the tree splits by. Mahalanobis on the already-fitted Σ matches the generating metric — but it introduces an eigenvalue floor (rank-deficient Σ on a flat scene is unbounded) and it rescales the score gaps XP2's fp16 lawfulness rests on (measured 98.76 % agreement, max gap 2.6e-5, `nn/dyad-assign/build_model.py`). Either re-run that verification under the whitened metric with a derived floor, or drop the lever. The first draft's "no new constant" claim is withdrawn.
- **CHOICE — pin `activeColorSpace` and lock AE/AWB at the shutter.** No exposureMode, whiteBalanceMode, activeColorSpace or isGlobalToneMappingEnabled appears anywhere in the Swift sources. A 64-frame capture is 3.2 s of continuous AE+AWB hunting, so the EMA and the JEPA ring are smoothing CAMERA drift, and it lands in K̂ directly. If wide-colour auto-configuration delivers Display P3 while both OKLab ports use Ottosson's sRGB matrices (`DyadPalette.swift:77-89`, `Quantize.metal:33-51`), every chroma moment, the hue resultant, WB8's gamut argument and chromaClamp's own gamut test are computed on inflated chroma. Neither pin introduces a constant — the values are the device's own converged state — but both change pixels. Ruling 7.
- **CLOSED.** The depth meters-vs-[0,1] P0 is closed on every live path (`MetalPipeline.swift:409-411`; `CameraManager.swift:633, :646`; in-kernel `Quantize.metal:74-81` with anchors from DepthSignal; Live's pooling is NaN-total at `DyadPipeline.swift:952, :1068`). `docs/loom-4d-interplay-design.md:112` is stale.

### 3.3 The judge

Both halves are already wired: PHASE F distortion D = D₁₆ + D₃₂ + D₆₄ in OKLab against rawRGB (`PhaseTelemetry.swift:147-169`) and the RATE LEDGER's H₀/K̂/M from the encoder's own LZW (`GIFMachine.swift:158-176`). **The (D, K̂) pair is the gate for every lever, with one distinction the first draft collapsed:** for FIDELITY levers it is a revert rule (a lever that moves neither D nor K̂ down is reverted); for ALLOCATION levers it is a REPORT, because widening the address is K̂-increasing by construction and the revert rule would auto-revert the entire colour program. Nothing on the list has been through it — no device capture has been taken since the WhiteBalance change landed.

---

## 4. The models

**THEOREM.** Exactly one learned model is in the byte-determining path: the 149-weight JEPA-H v7 ring smoother, pure Swift on CPU, invoked once per solve before any table is built (`JepaHHead.swift:44`; `DyadPipeline.swift:378`). It sits on the CPU precisely because 149 weights fall below the measured 0.23 ms ANE dispatch floor (an M1 number).

**THEOREM.** `DyadAssign` is NOT a model: a fused exact-arithmetic graph (sRGB→OKLab matmul + cbrt, batched −2·P·Cᵀ + ‖C‖², argmin, in-graph role select; `nn/dyad-assign/build_model.py:10-22`, `DyadANE.swift:36-45`) with zero learned parameters. The ANE decides bytes while carrying no weights, so "models never decide bytes" is already satisfied at assignment BY CONSTRUCTION; fp16's only lawful deviation is a near-tie argmin flip (XP2).

**MEASUREMENT.** Four internal flags exist, not six: `phaseChaosLoop = false`, `skGenes = true`, `pairTree = true`, `jepaH = true` (`CameraManager.swift:59-125`). `docs/ATLAS.md:230` names `jepaHSteady`, `groundV7`, `aneAssign`, none of which exist — the atlas's flag inventory must match `CameraConfig` exactly or §6's promotion pool reasons about imaginary switches. 4.5 MB of mlpackages ship; only DyadAssign (524 KB) is on a live path, SKGene (256 KB) loads only inside a `#if DEBUG` print, ANELoop (3.7 MB, 82 % of the payload) only if the flag flips.

### 4.1 REPAIR — the hard line is WS10, not the trace

The first draft proposed a single "mechanical test": *a model may write only into quantities that appear in the DYAD STATS trace*. **That test is strictly broader than WS10 and legalises exactly what WS10 forbids by name.**

**THE LAW, in two clauses that must BOTH hold:**

- **WS10 (binding).** A reading may steer ONLY warm starts, runtime K, and the EMA gain. It may never re-weight the energy (E is calibrated: one bit is one bit), touch palette bytes, or alter the **ground law** (`spec/neural/WeaveState.hs:483-495`).
- **PROVENANCE (necessary, not sufficient).** Anything a model does write must appear in the traced generating numbers, so the table stays a pure function of them and the GIF carries its own generator (`DyadPipeline.swift:436`; `GIFMachine.swift:115-131`).

**DEFECT (WS10 violation, shipped).** `let bgForFrame = jepa != nil ? jepa!.bg[f] : smoothedBg` (`DyadPipeline.swift:428`) sends the JEPA ring's smoothed BACKGROUND MOMENTS into `solveFrame(warm:background:)` (`:566-582`), which is a straight-line pure function with no iteration — so the head determines the ground law's generating input, not an initial condition. **Repair: the ground moments revert to the EMA law; JEPA-H steers the warm start only.** This is a defect fix inside a shipped mechanism, not a rewrite.

**DEFECT (WS10 inversion, shipped).** The export's rung-16 solve cadence is enforced by a MODEL: tables hold across 4-frame slots only when `jepaH` is on (`DyadPipeline.swift:375, :403`); flag-off the export solves per-frame at 20 Hz, while the live path's cadence is structural (`:928-932`). **Repair: group the 64 frames into 16 slots BEFORE solving.** The gate is *16 distinct LCTs at BOTH flag states* — and note honestly that jepaH-ON bytes MOVE, because slot-pooled statistics are not the head's per-frame smoothed statistics; asserting byte-identity here is self-contradictory.

**THEOREM (what that makes visible).** With the cadence structural, a 64-frame export contains 16 DISTINCT LCTs each repeated 4× byte-identically: 75 % of 64 × 6144 = 393,216 palette bits are exact repeats, and GIF89a cannot dedupe them (a frame with no LCT inherits the GCT, not its predecessor). Keeping them slot-constant vs letting them move at 20 Hz costs the same bytes either way — a rare free colour choice. Ruling 8. (RA6's `movesAtShallowDepth` — "at a shallow rung consecutive frames realise different node sets", annotated *per-frame LCT decree* — argues against holding the tree still for 3 frames of every 4, so the ruling is real, not rhetorical.)

**EM11 — no cross-edit warm starts.** `render` must be a function of (capture, edit) ALONE (`spec/ui/EditMachine.hs:386-395`). Making "the previous edit's converged solve the next edit's warm start" makes render a function of the PATH through edit space, and since the warm start is what `frameStats.append(warm)` traces and the table is a pure function of it, the bytes genuinely differ — falsifying the identity-edit acceptance test the moment a dial moves out and back. **The mechanism is deleted from this architecture.** Edit latency comes from algorithm, not from carried state.

**THEOREM (and it removes a whole layer of the first draft).** The σ widening needs no DescentLadder. Assignment is a fixed-shape dense 128-way matmul whose cost is identical whether the σ half addresses 16 or 128; the ANE never sees the σ prefix at all — the prefix is a CPU post-pass over band pixels, and its 128-wide branch ALREADY SHIPS as the `nodes.isEmpty` fallback (`DyadPipeline.swift:636-660`, `:470` "Assignment/ANE stay untouched"). A data-dependent 3-stage gather would replace the fixed-shape / fixed-iteration pattern the graph was built around. DL1–DL7 remain spec-green (18 candidates vs 128, DL6 proving stages 2–3 are LAW; `spec/neural/DescentLadder.hs:221-232, :298-317`) and enter as an ALGORITHM inside DyadAssign if and when a device bench asks for it — never as a second artifact. `nn/descent` stays retired.

**PROMOTION DEBT.** `jepaH = true` was promoted on 2 of its own 4 beauty gates: `results.json` records DET/B1/B3/FID; B2 (DYAD HARMONY) was never computed and B4 was checked as state RMSE rather than PHASE F distortion (`nn/jepa/README.md:33-48`). The tracked artifact contradicts the writeup: `results.json avg.churn_true = 9.5923` against `RESULTS.md:11`'s printed truth 8.45 — under the artifact's own number the head (7.92) churns 17 % BELOW truth, i.e. over-smooths, which is exactly the failure mode that flattens the motion the user edits against. The ring also carries 11 dims on a head trained on 6, never gate-measured. Per NO-CAPTURE-TRAINING, B2/B4 are computed on held-out synthetic seed ranges; Daniel's device feel is the only real gate. Ruling 9.

**DEFECT (silent flag coupling).** `ANELoop.refineFarBlocks` resolves candidate colours through FRAME 0's palette while resolving current colours per-frame (`ANELoop.swift:336`, CPU twin `:380`, vs `:315`). Under per-frame LCTs it minimises in the wrong colour coordinates for 3 of 4 frames. Inert today only because JEPA-H makes each slot's tables byte-identical and the block time boundary aligns with the ring slots — the structural-cadence change touches exactly that coupling, so fix it in the same step.

**HARDWARE HONESTY.** Every ANE number in the repo is M-series: 32 ms/dispatch and 0.13 ms per fused stage on M3 Max (`nn/ane-loop/build_model.py:37-42`); `ANELoop.sweeps = 4` is an explicit prototype constant awaiting the A-series pin (`ANELoop.swift:37`). Four decisions are jointly gated on one ⌘U bench on the phone (`TesseractTests/ANELoopBenchTests.swift`): pinning K, promoting `phaseChaosLoop`, K1-streaming vs K = 4 fused, and Metal SIMT vs ANE. **The bench moves to step S1**, because this architecture is device-first and every cycle claim in it is otherwise a projection.

---

## 5. The edit

**MEASUREMENT.** There is no edit today. The app never constructs `EditMachine.Surface.editing` (`ContentView.swift:175, 239, 269, 277`), so SEALED is unreachable and TUNING is entered only as the camera's `.done` screen (`EditMachine.swift:315`). The user's whole edit surface is two persisted bits (BLEED, MIRROR — `SettingsView.swift:40-62`, `GIFMachine.swift:20-43`) plus a 25-integer widget arrangement that changes zero GIF bytes (`ArrangementStore.swift:41, :47-58`). Everything here is extension; nothing is removed.

### 5.1 The edit value is the spec's, unchanged

**REPAIR.** The first draft invented `Edit = (d_F, d_B, alloc, colourDisc, rung)` and then cited RA7/RA8/RA9 for it. Those axioms quantify over `editSpace`, which is a different object. **The Edit is exactly the spec's five-tuple:**

```
Edit { eFig, eGnd, eCoarse, eMid, eFine }   each 0..7,  |editSpace| = 8^5 = 32768   (RA8)
identityEdit = Edit 7 4 0 0 7                (RA9 — today's shipping bytes)
```

(`spec/quantization/RoleAllocation.hs:203-231`.) Consequences that must be honoured:

- **RUNG IS NOT AN EDIT COORDINATE.** EM11's injectivity clause `(render c e1 == render c e2) == (e1 == e2)` fails by construction for two edits differing only in a byte-neutral view selector. The rung selector is a VIEW control on the LEDGER surface, not an Edit field.
- **eFig is pinned, not free, under the derived law.** RA4 proves `dFig == treeDepth` for every variance ratio in either direction — the user is never quantised to feed the background. A ROLE dial therefore moves **eGnd only, 8 stops**, and the ported 12-stop `roleSplit` law (`DetentDial.swift:96-99`) is off-law as a byte dial: positions with d_F ≥ 8 sit outside `editSpace` and would break RA7 (`2^8 + 2^3 = 264 > 256`). The dial vocabulary is a UI object; the edit space is the spec's.
- **The three octave weights are the three-view edit.** eCoarse/eMid/eFine are a simplex over the three parallel reads (OV6/OV8), identity (0,0,7) = the fine read alone. They are the coordinates that make THE THREE VIEWS an edit rather than chrome. Their semantics are deferred to the octave spec and they are therefore not in V1 — but they are not replaced by anything either.
- **Every dial position is byte-legal by construction.** RA2/RA7: an edit is a TRUNCATION DEPTH on ONE tree, and the σ involution means the ground costs no independent entries, so `coloursUsed ≤ 256` over all of editSpace. The UI needs no validation layer — WG3's refuse-by-construction discipline.
- **RA5 prices every detent:** rateBits = 1 + (1−t̄)·eFig + t̄·eGnd bits/cell, monotone in each and ≤ 8 everywhere. The dial's cost is not a guess.
- **RA6 says what a detent FEELS like:** cell spacing at depth d is 2^(7−d) leaf steps, so each bit taken from the ground EXACTLY DOUBLES the colour jump a ground pixel makes between frames. eGnd = 7 is sub-JND drift; 4 is today's shimmer; 2 is hard frame-to-frame phase flips. That is Daniel's "illusion of phase transformation frame by frame" as a rate choice, not an effect.

### 5.2 One encoder, and what "recompute tier" is allowed to mean

**THEOREM.** The one-encoder law is enforced by a parameter, not by discipline: `DyadPipeline.process(rgb:depths:withinVariance:bleed:chaosLoop:keeping:onFrameTable:)` is the single encoder and `Disposition` (.generatingState vs .artifact) is the only licensed difference between WATCHING and WEAVING (`DyadPipeline.swift:65-68, :263-267`; correspondence pinned at `EditMachine.swift:250-267`). An edit is an ARGUMENT to that call.

**REPAIR.** The first draft's four-tier "recompute ladder" was three byte-producing paths that never call `process` — the second encoder its own thesis forbids, and EM8's forbidden blend (figure bytes from edit N−1 beside σ bytes from edit N). The repaired rule:

> **A recompute tier is a MEMOIZATION of one `process(cube, edit)` call, never a route.** A tier is lawful only if (a) it re-emits the WHOLE frame, (b) the skipped stages' inputs are *proved* unchanged by that edit, and (c) a test gates the tier byte-identical against the full path. There is no partial-cube surface and no fast approximation.

| tier | licensed by | edits | cost |
|---|---|---|---|
| **T0 — RELABEL** | *empty* | — | — |
| **T1 — TABLE ONLY** | proof that the edit is index-invariant (today's only member: GH12 step A) | display-only σ rotation | 16 slot solves, ~6 KB rewritten |
| **T2 — GROUND** | eGnd touches only the σ target stratum (`nodes16`/`canonical16` in FrameSolve); table bytes rebuild at full depth from the traced numbers (`PairTree.swift:113-118`) | eGnd | one assign pass over the ground half |
| **T3 — FULL** | — | eFig, octave weights, BLEED | full solve + reassign |

**T0 is empty, and that must be said plainly.** The first draft's "free first edits" were MIRROR — which already ships as a persisted `ExportSettings` bit applied INSIDE the encoder (`GIFMachine.swift:26, 57-66, 296-297`) — and palette relabeling, which is invisible by the very proof cited for it: WS2's freeness holds because table rows and indices are permuted TOGETHER, which is the identity on the decoded picture; permuting only one breaks the σ involution and the provenance law. And "apply to an already-archived GIF with no cube" is a byte-producing path outside `process`, i.e. the second encoder EM13 deleted DyadPreview to prevent.

### 5.3 One capture, many GIFs — the mechanism

- **DEFECT.** `encodeGIF()` is the only encode path, runs once at recording completion, and reads `ExportSettings` inside that call (`CameraManager.swift:510, :593 → :659, :733`; `FaceCaptureManager.swift:238 → :374`).
- **Lift `makeGIF`, not `encodeGIF`.** `GIFMachine.makeGIF(frames:settings:onFrameTable:)` (`GIFMachine.swift:281-305`) is already the (cube, settings) → bytes function. `encodeGIF`'s Phases 1–2 are a dead pre-pass on every encode: 64× `blockToGoBoards` (decorative, drives the SOLVING screen) and 64× `PerfectQuantizer.quantizeFrame` producing a `BirkhoffMeasure` nothing reads (`CameraManager.swift:676-718`; `GIFMachine.eligible` checks only `rawRGB != nil`). Lifting `encodeGIF` as written drags both into every dial tick.
- **RETENTION — the cube must go to disk.** `FrameBuffer.exportCapturedFrames` returns without clearing and only `startRecording()` empties it (`FrameBuffer.swift:65-69, :42`), and `reshoot()` only sets `.previewing` (`ContentView.swift:269-272`). So "one live capture, many GIFs until the next shutter" means every GIF already in the library is uneditable forever and the editable set expires at the next shutter — which is re-capture, which is not an edit. **MEASUREMENT:** a cube is 64 frames × 4096 cells × 4 Floats × 4 B = **4,194,304 B ≈ 4.2 MB** of two flat arrays (`CapturedFrame.swift:15-21`), smaller than a research problem. Persist it as a sidecar at SEAL.
- **PUT THE EDIT IN THE TRACE.** Today `DYAD SETTINGS` records exactly `bleed=` and `mirror=` (`GIFMachine.swift:100`). Two variants of one capture made by different eGnd would emit identical trace lines and be indistinguishable in the library. RA10 pins the payoff as *"a whole library of variants is recoverable from ONE capture plus five small integers per entry"* (`RoleAllocation.hs:428-437`). Five integers plus m_g on the trace closes the shelf gap, satisfies RA10, and removes the model/user double standard the first draft carried (policing models with a trace rule while exempting the user's dial).
- **LIBRARY.** `GIFLibrary` names files `tesseract_<unix second>.gif` and lists by sorting that name (`GIFLibrary.swift:29-47`), so two variants sealed in the same second silently overwrite. A variant discriminator is required before EM10 fork-freedom ships. AttractorRAG is explicitly out of V1: 'attractor' and 'balanced pair' are different objects, only the pair exists in Swift (`DyadPalette.swift:55, :65` vs `spec/quantization/AttractorRAG.hs:128-132`), and AR8's store-version pin is a persistence obligation that must not ride the first dial.
- **WHAT THE USER EDITS AGAINST.** The role posterior — the exact thing eGnd reallocates — is computed at every 5 Hz solve and thrown away; `PhaseStripWidget` renders its NOT-YET-FED face because no manager publishes the face/band/solid composition (`WidgetSurfaceView.swift:399-412` vs `DyadPipeline.swift:212-216`). Publishing composition on `FrameSolve` changes no bytes and is the cheapest way to make allocation legible before a dial moves it. TUNING also needs an A/B against `identityEdit` — RA9 guarantees it is byte-identical to today — because "a different GIF" is only legible next to the one it differs from.
- **LATENCY.** Nothing in the repo states an edit budget, and the shipped encode owns a modal SOLVING screen with a four-phase per-frame progress bar (`CameraManager.swift:672-739`; `ContentView.swift:185-188`). **CHOICE:** the budget is the loop's own unit — one detent resolves within one 5 cs frame at T1/T2, and T3 renders progressively through the `onFrameTable` callback that already streams per-frame tables to the UI, so latency reads as a visible weave rather than a bar. *Alternative:* state a device-measured budget per tier after S1 and let T3 be modal.

---

## 6. The layer map

| layer | rung | cadence | in | out | may change bytes |
|---|---|---|---|---|---|
| **FEED** — registered four-channel evidence; box-prefiltered depth; declared clamp/NaN contract | 64 | 20 Hz | AVFoundation front video, TrueDepth / ARKit depth, DepthSignal anchors | (l,a,b,d) cells at 64; invalid-pixel rate | yes |
| **κ** — the ONE 2×2×2 spacetime pool, carrier-parametric, phase-tagged, phase-locked to capture frame 0 | all | 20 Hz in → 10/5 Hz reads | FEED cube, target rung, polyphase (dx,dy,dt) | 32³ and 16³ views | no |
| **ROLE** — two-Gaussian tied-variance mixture; t, crossover, τ, masses, m_g; totality guard; DM11 τ-lift | 16 | 5 Hz (TL9) | κ's 16³ depth view, prior mass, BLEED | t lifted to 64, mask, twoPhase, (m_F, m_band, m_g), analysis weights, role composition | yes |
| **ALLOC** — `derivedAlloc λ_F λ_B`; d_F = 7 (RA4), d_B = 7 − ⌊log₄(λ_F/λ_B)⌋, overridden by the Edit's eGnd | 16 | 5 Hz | staged-field generalised variances, Edit | (d_F, d_B) + the RA5 rate line | yes |
| **TABLE** — PairTree solve, σ involution, mirror centre (WB13-weak), per-frame LCT; slot grouping is STRUCTURAL | 16 solve, applied at 64 | solve 5 Hz, emit 20 Hz | warm start, background moments (EMA law), m_g, ALLOC, Edit | 64 × 768 palette bytes + DYAD STATS v4 | **yes** |
| **ASSIGN** — DyadAssign exact-arithmetic graph (figure) + CPU pair-dither (band/σ) | 64 | 20 Hz | staged Lab, the slot's table, t, Bayer coverage, Edit | 64 × 4096 index bytes | **yes** |
| **ARRANGE** — E_wall only: polyphase placement, ANE fixed-K exchange on far blocks; provably cannot widen the alphabet | 64 authored, 32 certified | per export / per edit | index frames, occupancy histogram, runtime K | rearranged indices, identical histogram | yes |
| **EDIT BUS** — one `Edit` threaded as an argument; routes to the cheapest *proved-equal* tier; `reweave(cube:edit:)` is the only entry point | all | per detent | dial detents, persisted cube, Edit | a GIF per SEAL; identity edit reproduces the capture's bytes | no (re-parameterises) |
| **LEDGER** — occupancy census (distinct, distinct ≥128, shadow census), 8-rung dyadic budget, E_hist/E_wall, (D, K̂), measured cast, transport gap | all | accumulate per frame, report per export | indices, tables, raw field | trace lines + the widget surface's numbers | no |
| **INFORM** — JEPA-H 149 CPU weights + the surprise channel; warm start, K, EMA gain, nothing else | 16 | 5 Hz, once per slot, inside `process` | the WeaveState numbers, per-slot pooled stats | warm start, K, EMA gain | no |

---

## 7. Sequence

Reconciled with `docs/occupancy-workflow.md` O0–O6 rather than replacing it. Steps that change bytes owe a Haskell axiom first.

| step | content | maps to | gate |
|---|---|---|---|
| **S1 — INSTRUMENT** (no pixels) | Per-frame per-rung occupancy census (distinct, distinct ≥ 128) asserting ≤ 144 and ≤ 16; the **SHADOW CENSUS** — the distinct 128-leaf σ argmin each pixel WOULD have taken, one extra argmin per pixel; **λ_F/λ_B** measured on the staged field; **m_g** measured and its 20 Hz stability; the §0 rate table per capture; invalid-depth rate; the RGB and depth buffer dimensions (`CameraManager.swift:460, :371`); baseline (D, K̂); the ⌘U ANE bench on the phone | **O0** + **O1**, unchanged | census reproduces 10-of-128 from first principles and closes 164 as a cube union; registration ratio confirms scaleFactor = 3 or the crop law reopens; every frame satisfies ≤ 144 / ≤ 16 or the flag state is not what the code reads |
| **S2 — UNIFY THE LADDER** (byte-identical) | The eight §1.2 defects: one κ, one `Rung`, `slots = Rung.coarse.frames`, block through `AerialParams`, absolute σ blur rung (Ruling 1), live phase locked to frame 0, delete `CubeMode.inference`, delete the dead far branch and the `v == 255` gate, wire `rungTelemetry` and role composition to the surface | — | export byte-identical on a stored cube; Metal/CPU aerial parity; a LIVE-path golden frame (an export-only gate cannot test the σ blur rung, the phase lock, or the Rung unification) |
| **S3 — SIGNAL TRUTH** (first pixels; §3.1 items 2–4) | Depth box-prefilter on both twins; `coverage` totality guard on μF > μB; clamp atoms with locations derived from the clamp preimage, BIC-selected as DM9 selects component count, planted fixture carrying them; invalid pixels excluded by weight | — | (D, K̂) does not regress; invalid-pixel rate published; DepthMixture axioms named before the port |
| **S4 — STRUCTURAL CADENCE + WS10 REPAIR** | Group the export's 64 frames into 16 slots before solving; revert `bgForFrame` to the EMA law; fix ANELoop's frame-0 palette resolution in the same edit (the coupling being removed is what keeps it inert) | — | exactly 16 distinct LCTs with jepaH ON *and* OFF; jepaH-ON bytes MOVE and are reported, not asserted identical; `phaseChaosLoop` can now be flipped without silent coupling |
| **S5 — THE σ QUESTION, ANSWERED BY MEASUREMENT** | Read λ_F/λ_B and the shadow census from S1. If the ratio is < 64, the derived allocation widens d_B by law and the port is one loop bound; if ≥ 64, the diagonal ladder is confirmed correct and O2/O3 close as *no change*. Spec first either way: correct `DyadPalette.hs:538` (which states a law the code does not run), strengthen DY6/DY11 past `farSpread ≥ 4` (which 16 satisfies — that is why the suite never caught the narrowing), and give `canonical16` a tie-free selector with its own PT axiom | **O2 + O3 collapsed** into one instrumented step | shadow-census occupancy must exceed today's ≤16 by more than the geometry-mismatch simulation predicts (matched 253.8 alive / 0.5× 219.9 / 0.25× 162.6); (D, K̂) reported not reverted; v7's no-blue-haze survives on device |
| **S6 — MASS AS GENERATOR (WB13-weak) + the colour route** | Mirror centre solves m_F·mean_fig + m_g·mean_gnd = c; m_g enters DYAD STATS **v4**; the WB7/WB8 route ruled and executed; GH12 step A shipped (index-identical, free); the fitted Δh applied or its machinery deleted | risk clause of `occupancy-workflow.md §3` | measured image cast below the S1 baseline; a rebuild from v4 reproduces the bytes exactly; ORIENTATION GUARD holds (`phase-palette-law` P0). **S5 and S6 must be measured in ONE device session** — widening the σ address makes the image-level haze worse before WB13-weak removes it |
| **S7 — THE EDIT BUS** | Lift `makeGIF` into `reweave(cube:edit:)`; thread the spec's `Edit` through `process` into `PairTree.solveFigures` and the σ target quantization; persist the 4.2 MB cube sidecar; add the five integers + m_g to the trace; variant discriminator in `GIFLibrary`; construct `EditMachine.Surface.editing`; ship the **eGnd** dial with an A/B against identityEdit; publish role composition | — | `reweave(cube, identityEdit)` reproduces the capture's own GIF byte-for-byte (RA9); the RA8 totality test enumerates the dial product and every point encodes; per-tier latency measured on device; launch surface still preview + record + SET |
| **S8 — ARRANGEMENT, ONLY IF S5 WIDENED** | Polyphase authoring at rung 64 (the eigen-dither is NOT the mechanism — §2.5); rung-32 certificate measured, not inherited; conditional-ground-state acceptance | **O4**, **O5** with a distortion term added to its gate; **O6 retired** and replaced by within-half uniformity (bijection is unreachable for m_g ≠ 0.5) | rung-32 occupancy reaches 4/colour without being touched; transport distortion reported alongside E_hist (rung 64 forced-16 = +0.9 dB; rung 16 forced permutation = +2.6 dB matched, +7.2 dB mismatched); coherent arrangement stays near 15894 b, not 44686 b |

---

## 8. Rulings owed

**1. σ chaos-blur target rung.** *Absolute rung 16* (TL9 states depth's rung absolutely, `TriScaleLadder.hs:259-275`) vs *relative two-κ-steps-down of whatever read it runs on* (shipped, `DyadPipeline.swift:594-596`, which blurs at rungs 8 and 4 during the coarse reads). **Recommend ABSOLUTE**, with the target rung passed explicitly; the three views cannot be three views of one law otherwise. If relative, TL9's absolute claim must be restated and the widgets are honestly showing a different object than the export.

**2. Rung 32's job. ★ RULED 2026-08-14 — neither option.** Daniel: *"all rungs require a meaningful additive to the creation of GIFs."* Both alternatives offered here (certificate, pure view) are measurement-only jobs and both are refused. Rung 32 writes bits 5–3 of every index; see §1.3. The remaining question is not what rung 32 is *for* but where the additive law's axiom file lands — S8.

**3. WIDE vs NARROW palette.** *WIDE:* pursue 256 alive, +55.1 % of the rung-64 wire, maximum colour impact. *NARROW:* hold the frame alphabet ≤ 128, emit a 384-byte LCT (size code 6 instead of the hardcoded 0x87), save 3072 b/frame = 24 KB per export, and change `DyadGIFContractTests.swift:96-100`. **These are the palette's two ground states and they are opposite.** Recommend deciding WIDE only if S1's shadow census shows the background actually occupies what it would address; otherwise NARROW is the only *measured* saving in the system and it is currently invisible because 6144 b is treated as a law.

**4. The σ shell geometry.** *Keep the strict involution* T[255−i] = ground(T[i]) (DY2/PT6/WB1) and accept that the σ shells inherit the FIGURE's radii, or *fit the σ shell radii to the background's own covariance* (keep the hue mirror, break only the radial half) which recovers up to 3965 b of the 9216 b freed. **Recommend deciding after S5** — the second option breaks the pairing WB4's cast theorem rests on and needs its own axiom.

**5. GH14 — where the temporal octave is bought.** *`stageLOnly`* (proved hue-exact, `GroundHue.hs:476`) vs *γ on all three OKLab coordinates* (shipped DY9, proved hue-contracting, far background contracted by exactly ½). **Recommend stageLOnly**: one line, a proof on one side, and every colour claim about the background is downstream of it.

**6. WB7/WB8 route (mutually exclusive).** *A:* the FIGURE half moves to hue-distributed shells at cap ≥ 64/510 — balance AND diversity AND 256 unique. *B:* the PairTree Gaussian stays and the σ half gets the fitted Δh back — diversity and the wall's own hue, at the cost of WB4 balance. Shipped code takes NEITHER and computes Δh only to discard it. **Recommend A**, with WB13-weak supplying the neutrality; the underlying question for Daniel is *on the wall, zero colour cast or the wall's own hue*.

**7. Capture pinning.** May the session pin `activeColorSpace` and lock AE/AWB at the shutter? Neither introduces a constant (the values are the device's converged state) but both change pixels. **Recommend yes** — a 3.2 s AE/AWB hunt is being smoothed by a 149-weight head and lands in K̂ as if it were scene motion.

**8. Table cadence.** *16 distinct LCTs each held 4 frames* (minimum churn, TL8/TL9 made visible) vs *64 distinct at 20 Hz* (identical byte count, more colour impact per frame, and RA6's `movesAtShallowDepth` argues the shallow tree is supposed to move). Free either way in bytes. **Recommend 16 for V1** with 64 available as the octave dial's top detent later.

**9. `jepaH` default.** Stay ON before B2 (DYAD HARMONY) and B4-as-PHASE-F are computed, given `churn_true = 9.5923` implies 17 % over-smoothing? **Recommend: stay ON until S4 lands** (so that flipping the flag changes smoothing and nothing else), then compute B2/B4 on held-out synthetic seeds and re-decide.

**10. Where the dials live.** *Static GridRegions in the TUNING scene* (launch surface untouched; but TUNING is then a second surface the user navigates) vs *rows in the SET cover* (which `docs/ATLAS-TUNABLES.md:821` names as THE expansion point) vs *widgets* (forces WG6's closed vocabulary from 12 to 16 and an `ArrangementStore.schema` bump that costs every user their layout once). **This is a decree collision between SIMPLICITY and EDIT-IS-THE-WHOLE-APP and it is Daniel's to rule, not the architecture's.** Recommend TUNING regions; record it as an amendment to SIMPLICITY if taken.

**11. `canonical16`'s selector.** PT7 makes the minimum an exact 2-, 4- or 8-way tie in every case, so today's 16 background colours are chosen by index order and float rounding with a constant systematic displacement. Options: minimum eccentricity under the CLAMPED sRGB8 geometry the assignment actually searches, or an explicit antipodal-pair convention. Either is a NEW LAW owing a PT axiom — replacing one unchosen law with another is not a bug fix.

**12. V1 edit scope.** *eGnd alone* (provenance-light, tree-consumed, RA6-legible) vs *the full 8^5 including the octave weights* (which requires the octave spec's semantics and the DYAD STATS v4 trace at once). **Recommend eGnd alone**, with the octave weights named as the second increment so the three views become an edit rather than chrome.

---

## 9. Risks and accepted debts

**RISKS**

1. **The haze returns by OCCUPANCY, sign-flipped.** With the balanced branch shipping ground = (l+ΔL, −a, −b) and a ≤16-entry σ alphabet whose canonical leaves sit at a constant offset from their node means, the predicted image cast is ≈ m_g × 0.987 toward −c_F. WB7 named this failure and its diversity half has no Swift port. First thing the device pass looks at; S5 and S6 must not be judged in separate sessions.
2. **Widening the address without occupancy makes the file bigger and no more colourful.** The v7 blur makes the σ target field flat by construction, so the ceiling rises while occupancy does not; the wire rises 55.1 % at rung 64 regardless. The shadow census in S1 is the only thing standing between that ruling and a coin flip.
3. **Registration voids everything above it.** If the delivered front-camera RGB:depth ratio is ~1.5 rather than the pinned 3, every role decision is applied to a mis-scaled region and no measurement in this document means anything. Two log lines already exist.
4. **The NaN cascade no test covers.** Constant per-frame depth against a two-phase pooled field ⇒ temperature = +inf, crossover = NaN, t = NaN everywhere, the frame collapses onto ≤16 σ entries and poisons its own table. FACE reaches it on any tracking drop and unavoidably on frame 0. Arithmetic-confirmed, not device-observed — and no occupancy number is trustworthy until the guard lands, which is why it sits in S3.
5. **The default-ON model is unpromoted by its own charter and its artifact disagrees with its writeup.** If the 17 % over-smoothing is real, JEPA-H is flattening exactly the motion the edit app exists to let the user shape, and every measurement taken with it on inherits the distortion.
6. **Provenance break by dial.** eGnd changes emitted INDICES; a rebuilder reading a v3 trace recomputes the *derived* allocation, not the user's. The GIF stops carrying its own generator for the index stream until the Edit is traced. This is the 2026-08-14 GROUNDHUE v1→v2 lesson verbatim — that incident is recorded in the codebase as *"exactly what the first cut of this change shipped"* (`GIFMachine.swift:145-150`).
7. **Every compute number is M-series.** 32 ms/dispatch, 0.13 ms per fused stage, a 0.23 ms dispatch floor, `sweeps = 4` as an explicit prototype constant. Moving the bench to S1 is the only thing that turns this architecture's cost ordering into measurement.

**ACCEPTED DEBTS**

- **The occupancy program is a COLOUR purchase priced in bits, not a rate recovery.** It is accepted as such. The "2688 wasted LCT bits" are unrecoverable; the honest ledger entry is +9216 b/frame at m_g = 0.75 (RA5 and the calibrated LZW simulation agree exactly) in exchange for 2.44 b/cell of alphabet capacity. Anyone reading the first draft's framing should read this paragraph instead.
- **O6 is retired as an acceptance test.** The rung-16 bijection requires m_g = 0.5 exactly and is unreachable at any alphabet width; the reachable target is within-half uniformity with a declared residual E₀ of 773 / 193 / 48.3 b at rungs 64 / 32 / 16.
- **The "author fine, validate coarse nests for free" theorem is downgraded to OPEN.** The certificate covers one 4:1 spatial step at phase 0; the operator in question is a SUM, and the coarse reads re-assign rather than decimate.
- **The preview's evidence gap is not closed in V1.** The export fits on 4096 samples/frame and the preview on 256, with a shell contraction of 0.868×/0.713×/0.512× at incoherent fractions 0.25/0.5/0.75. EM13's one-encoder law holds for the LAW and not for the EVIDENCE. Accepted, declared, and named as the thing a stats/covariance lift (analogous to DM11's τ-lift) would repair.
- **VoiceOver debt** (2026-08-13 port ruling) is unchanged.
- **`m_g = 0.75` is a planted fixture constant** (DM3) until S1 measures it. It must not become a traced generator in S6 before it is a measurement.
- **The dial vocabulary and the edit space are two objects** and will stay two: `DetentDial`'s detent counts (8 / 3 / 12 / 16×8) are a UI law; `editSpace` (8^5) is the byte law. Only the second is cited for totality.
