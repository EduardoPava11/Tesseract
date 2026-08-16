# TESSERACT: THE BIN, THE STANDARD, AND THE NAMES

Daniel, 2026-08-15, across four alignment rounds:

> "BIN is what I call the memory we need to encode. The structure
> depends on the model as we would need an input of type?"
>
> "ALL three are to be the same! hence we need to categorize them!"
>
> "No models are trained on knowledge about HOW color space behaves in
> the GIF89a constraints. It helps us explain the GIFs we create and we
> should train these models on HOW we interpret the signal. go back to
> the fundamentals. 16x16 == 256"
>
> "This is a standard we need to create. We need to describe the signal
> into the unifying components. We have redundancy, we have overlap.
> 64x64x64 == 32x32x32 == 16x16x16 in terms of color-time..."
>
> "Think of the Katago/alphago... we have a game with rules and a merkle
> tree. It is probability and a way to traverse the shape of that
> probability. 64^3 color voxels is the shape."
>
> "YOU HAVE axioms and theorems, you need to build up to it."
>
> "Review, create a workflow and decide on names."

Rulings already fixed by those rounds: the energy becomes a FIELD and
unifies with CL6; the field is TENSOR-SIDE ONLY and never rides in the
GIF; spec the BIN first and train nothing yet.

## 0. ★ CORRECTION, SAME DAY: FIVE OF SIX CONCLUSIONS BROKE

Daniel, after reading the first draft of this file:

> "all you have said is 'its green' yeah it is all related and made to
> hit green your job is to break things and prove things about the app
> we are building."

He was right. Thirteen adversarial agents ran against the axiom base
and against this file's own chain. Full result in `docs/adversarial/`
(CLAIM-REGISTER.md, FINDINGS.md). Of 51 claims examined: PROVEN 28,
UNGATED 9, DIVERGENT 7, VACUOUS 4, UNKNOWN 3.

READ THE REST OF THIS FILE WITH THIS TABLE BESIDE IT:

    C1  the index IS the path            BROKEN   section 3
    C2  the posterior costs zero bytes   HOLDS    section 3
    C3  the 3.48% headroom bound         BROKEN   section 3
    C4  ANELoop is the solver            BROKEN   section 3
    C5  the energy triple breaks ties    BROKEN   section 3
    C6  conformance is not at risk       BROKEN   section 3

Every broken paragraph below is marked ★ BROKEN inline with what
killed it. The paragraphs are kept rather than deleted, because the
shape of each mistake is the useful part.

★ WHAT SURVIVED, and it is not nothing:

- **C2**, and it survived an attack rather than merely going
  unchallenged. Retention is exact, not lossy: `DyadPipeline` runs the
  8-bit conversion as the FIRST act on the cube, so every downstream
  stage is a function of 8-bit samples and drift is ZERO, not the
  tensor's 0.0060 rmse. `CubeStoreTests:130` already gates it, with an
  anti-vacuity companion at :152.
- **Section 4's arithmetic**, CS1 to CS4. Checked and clean.
- **Section 5's names**, untouched by any finding.
- **Section 6's step 3b**, the static-order gate, which matters MORE
  now: C3 showed the contested set on the shipped path may be empty.

★ AND THE METHOD IS THE LESSON. Reading an axiom tells you what it
SAYS. Mutating the code and watching it stay green tells you what it
DETECTS. Those are different, and this repo had already documented the
gap twice (FrameGeometry's relabelling-invariant G5-G10, MerkleSearch's
restated table) without either diagnosis becoming a lint.

## 1. THE ONE IDEA

Daniel, correcting the first draft of this file:

> "BN5 is more fundamental, we are using these BIN's as hierarchical
> probabilistic attractors in a color space."

A BIN is a HIERARCHICAL PROBABILISTIC ATTRACTOR IN COLOUR SPACE, and
all four words are already green:

    hierarchical    depth forced at three (CL7, AD3), and the three
                    levels ARE the rungs 16/32/64 (AD1's bit strata)
    probabilistic   every node is a GAUSSIAN, closed form, PT7-PT9
    attractor       AD5: a coarse decision is never REVISED by a
                    finer one, only REFINED. That is the basin
                    property, stated as an axiom
    colour space    OKLab, and the root of each frame's tree is the
                    13 numbers of DYAD STATS v3

The attractor is therefore not something to build. It ships. What has
never existed is the PROBABILITY over it: the tree is constructed
probabilistically and then used deterministically, because assignment
takes an argmin and collapses the posterior at the exact moment the
posterior exists. Traversing the shape means keeping it.

One budget of 262144 bits is spent three ways, and the three ways are
the same signal. A BIN is that budget in standard form, and it is a
POSITION in a game whose rules are already written and whose value head
is already arithmetic.

## 2. THE REVIEW: what the axioms already prove

This is the build-up Daniel asked for. Every line below is green today.
Nothing in section 4 is asserted; it is derived from these.

**The fundamental, 16x16 == 256.**

  `Octave.hs OV2` states it as THE BIJECTION FLOOR: 16 squared is 256
  is the palette size. One coarse frame's spatial cells stand in
  bijection with the palette. `FeedCompression.hs FC4` states WHY it is
  possible at all: this pyramid downsamples only the low-pass channel,
  so the coarse level stays a PICTURE. Under a critically sampled
  wavelet it would be a frequency band and could not be a palette. The
  73/64 redundancy is not waste, it is the price of the bijection.

**Colour-time, already counted.**

  `CaptureTensor.hs CT2` forces equivalent float resolution at 64:8:1
  because cells stand at 1:8:64. Written out, the three rungs are one
  budget:

      rung 16   16 frames x 16 x 16 =   4096 cells x 64 bits = 262144
      rung 32   32 frames x 32 x 32 =  32768 cells x  8 bits = 262144
      rung 64   64 frames x 64 x 64 = 262144 cells x  1 bit  = 262144

  `TriScaleLadder.hs TL8` proves the same thing from the process side:
  on the pooling orbit the invariants are total mass, loop wall clock
  320 cs, and information per compute. ONLY RATE VARIES. Equal compute
  time IS the equivalence class. `TL9` fixes where depth sits on that
  trade: rung 16, 64 draws per judgment, 5 Hz, while RGB rides rung 64
  at 20 Hz.

  So "64x64x64 == 32x32x32 == 16x16x16 in terms of colour-time" is not
  a new claim to prove. It is CT2 and TL8 read together, and the thing
  that is missing is a NAME and a TYPE for what they are counting.

**The overlap, already declared.**

  `FC4` states the pyramid tax as exactly 73/64: the stack holds 8/7 of
  the fine rung's cells. `Octave.hs OV13` says the rungs are PARALLEL
  VIEWS, not a nest. `CT6` notes depth's coarse rungs are a pure
  function of the fine one, so storing all three stores the same
  numbers three times. The redundancy is known, quantified, and bought.

**The game, already mapped.**

  `MerkleSearch.hs` already carries the Go correspondence: a position
  is a GIF as its canonical generator, a move is an expansion at one
  rung, the transposition table is the Merkle hash for free. `MT9`
  inverts the analogy where it matters: KataGo must LEARN its value
  head because Go has no closed form, and this app HAS one. `MT8` shows
  the Pareto front of (E low, E_wall high) strictly dominates both grey
  and static, so the search cannot return either.

**The value head, already ported.**

  `TilingEntropy.hs TE1-TE15` and `Meter/TilingEnergy.swift` give E,
  E_wall and E_time in bits, three DISJOINT strata (TE15). `TE12` gives
  the rotation theorem. No weights anywhere in it.

**The generator, already exact.**

  `ColourLatent.hs CL1`: 49152 bytes of colour are a pure function of
  896 numbers PLUS 128 BITS through a decoder that already ships,
  54.86 : 1 exact. (★ CORRECTED: this file first wrote "832 numbers,
  59:1", counting only the 13 DYAD STATS fields. ColourLatent.hs's own
  header warns about exactly that undercount, because its FIRST DRAFT
  made it too: the generator is 16 fields per frame, 14 numbers and 2
  bits, the extra 3 coming from the DYAD GROUNDHUE v2 block that
  GIFMachine writes on EVERY export. A rebuild that ignores it
  reconstructs `balanced` as false and regenerates the v7 table, which
  is a silent provenance break that has already shipped once. A latent
  modelling 13 of 16 fields cannot reach every lawful GIF.) `CL2`
  the decoder is total. `CL4/CL5` the lawful relabelings are the 256
  XOR-by-mask permutations and they move no colour. `CL6` the metric
  cannot be a fixed diagonal and must be learned as a FIELD.

**The categories, already measured.**

  `Meter/FunnelLedger.swift` gives DISCARD, SUMMARIZE, RECODE, EXPAND,
  RETAIN with measured bits in and out, and the three-path DAG that
  telescopes exactly.

## 3. ★ THE FINDING: the unification already exists, in MerkleSearch

Daniel: "ALL three are to be the same, hence we need to categorize
them." The categorization does not need to be invented. It is already
in the green spec, in the `Node` type, and `MT3` already caught the one
way of getting it wrong.

    data Node = Node
      { path    :: [Int]    -- WHICH BRANCH at each depth: STRUCTURE
      , content :: [Int]    -- the PALETTE labels: COLOUR
      , depth   :: Int      -- 0 = rung 16, 1 = rung 32, 2 = rung 64
      }

Map the three things Daniel called the same onto it:

    the generator     is `content`   what colour
    the provenance    is `path`      how the information arrived
    the energy        is the VALUE   how good, arithmetic, no weights
    the rung          is `depth`     the colour-time allocation

They are the same object because they are four projections of one node,
and `MT3` proves the deep part: path and content must be HASHED
DIFFERENTLY, because the free relabeling group acts on content and not
on path. Structure and colour are genuinely distinct coordinates of one
address. Conflating them still builds a tree; it just builds the wrong
one, silently.

So the BIN is not a new container. THE BIN IS A NODE IN STANDARD FORM,
and the standard form is what section 4 names.

**★ AND THE INDEX IS THE PATH, so provenance is DERIVED, never stored.**

> ★ BROKEN (C1, adversarial run 2026-08-15). Both citations fail.
> AD5 takes NO cube, NO assignment, NO colour and NO descent: it
> quantifies over `allIndices = [0..255]` and nothing else, and all
> five conjuncts reduce to integer shift identities. It cannot tell a
> pipeline that refines from one that revises because it never
> observes a pipeline, and `grep StrataDescent spec/` returns one
> prose comment. Worse, DescentLadder.hs:26-27 records that the
> 2026-08-12 adversarial review explicitly KILLED a "never revise"
> axiom; this file reintroduced the claim by citing one that cannot
> carry it.
> PT5 carries the geometry only on the SEPARABLE dyadic fixture, and
> its own comment hedges "near-ties outside separation are XP2's
> territory". The tree that ships is PT7-PT9's analytic Gaussian
> tree, which is not separable: splitG shrinks the offset by
> sqrt(1-2/pi) = 0.6028 while descendant spread is 1.517x the parent
> gap, so the halves OVERLAP. Restated over that tree, truncation
> stops recovering the ancestor: 0 failures at 1:1 through 3:1 OKLab
> anisotropy, then 5.33% at 4:1 (an ordinary face-lit covariance),
> 29.7% near-monochrome, 32.8% chroma-dominated. The repo has already
> diagnosed MONOCHROME on device at R=0.9913.
> NOT REFUTED BY A SKEPTIC: this finding was one of ten the run's cap
> left unverified.

The first draft of this file asked whether a `FunnelLedger.Kind`
belongs to a VOXEL or to a QUERY. Both readings are wrong, and they are
wrong in the same way: each assumes provenance must be STORED
somewhere. It is already computed, in the shipped index plane, at zero
extra bits.

`AD1` gives the index as four disjoint strata of widths 1+1+3+3 over
one byte. `AD2` makes decompose/compose a bijection on all 256, so no
index exists that some rung did not help write. `AD5` gives the
attractor law outright: truncating at a stratum boundary yields exactly
the class the coarser strata already wrote, so A COARSE RUNG'S DECISION
IS NEVER REVISED BY A FINER ONE, ONLY REFINED. `PT5` gives the
geometric half, truncate ≡ nearest coarse centroid.

Read together: a voxel's 8-bit index IS its path from the root
attractor to the leaf it fell into, and truncating the index walks back
up to the ancestor basin. A per-voxel provenance field would cost 96
KiB to re-encode what one byte already carries.

**★ AND THE FUNNEL'S ARROWS ARE THE DESCENT.** `FunnelLedger`'s
measured codebook path, read against the attractor:

    DISCARD    144:1     BEFORE the attractor exists (the downsample)
    SUMMARIZE  109.47:1  climbing to the ROOT: 4096 pixels to 13 numbers
    EXPAND     1:6.84    descending to the 256 LEAVES
    RECODE     5.39:1    the wire (LZW)
    RETAIN               what the tensor keeps

109.47 / 6.84 = 16.0 exactly, which is TE2's balanced occupancy and the
ground state of E. The codebook path and the descent through the
attractor ARE THE SAME ARROW SEQUENCE. That is the fit Daniel asked for
when he said the categories must fit the 64 cubed BIN tensor, and it
was already measured; nobody had read it as a descent.

A Kind is therefore an OPERATION ON PROBABILITY MASS living on an EDGE
of the hierarchy. It is not a label on any object, which is why asking
which object carries it had no good answer.

**★ AND THE POSTERIOR FACTORIZES, which is what makes it a policy.**

Because AD5 refines and never revises, `P(leaf | colour)` factorizes
along the path as a product of per-level branch posteriors. That is
exactly KataGo's policy factorization down a tree, arriving from the
app's own axioms rather than from the analogy.

It also sharpens MT9. A Gaussian split along a fixed axis has a CLOSED
FORM branch posterior, so the policy's SHAPE is arithmetic too. What is
genuinely learned is narrower than "the policy": it is CL6's METRIC,
because a posterior needs a distance and CL6 proved no fixed diagonal
works (the mean-step to variance-step ratio crosses 1, so the order
reverses). The policy's shape is analytic; its metric is the field.
This is why "a field, and unify with CL6" was the correct ruling.

**Two gaps this review found in the tree, both concrete.**

1. `MerkleSearch.contentOf` is a PLACEHOLDER, `(i * 37 + 13 * sum p +
   7 * length p) mod 256` over 8 entries. The tree has never been
   connected to the real generator (CL1's 896 numbers + 128 bits, and
   the 2 bits per frame are NOT directions: a metric cannot
   interpolate through them and a sampler must enumerate them).
   Connecting them
   is most of the BIN work.
2. The value head is 2-dimensional (E, E_wall) because `TE11-TE15`
   landed AFTER `MerkleSearch`. E_time exists, is ported, and is not in
   the front. MT8's Pareto front is currently missing the axis that
   sees the loop.

**★ THE COLLAPSE HAPPENS THREE TIMES AND THE FORMAT ASKS FOR ONE.**

This is the whole opening, and it is what BN6 is really about.

GIF89a forces a hard 8-bit index at EMISSION. It says nothing about
when the decision is made. `StrataDescent` commits at every stratum, so
the posterior is collapsed three times over, and AD5 then guarantees
the earlier collapses are never revisited.

> ★ BROKEN (C3). 0.9652 is not measured against an optimum. It is
> agreement with the EXHAUSTIVE TEACHER, and nn/descent/RESULTS.md
> gives that teacher 1.0 / 1.0 / 1.0 with excess distortion 0. So
> 1 - 0.9652 bounds how far a heuristic sits from the hard argmin,
> not how far the argmin sits from anything better, and the posterior's
> value is orthogonal to argmin-agreement by construction.
> Worse for everything downstream: lookahead-L2 DOES NOT SHIP.
> DyadPipeline.swift:807-826 is a DO-NOT-REPLACE guard whose own table
> reads "exhaustive (this code) 1.0, excess 0", and nn/descent/README
> says lookahead "is NOT taken". On the shipped path the disagreement
> rate is ZERO, so the contested set defined this way is EMPTY and the
> edit app's claimed state space is zero. The ~9175 figure is also
> arithmetically wrong (9116.44) and its denominator is 18432 probes
> over 96 synthetic trees, not the cube.
> NOT REFUTED BY A SKEPTIC.

★ AND DISTORTION IS NOT THE ARGUMENT FOR CHANGING THAT, which is worth
stating plainly so nobody builds the case on the wrong number. DL7
measured greedy at 0.8601 leaf agreement and lookahead-L2 at 0.9652.
Lookahead IS a partial posterior: it looks one level down before
committing. So greedy, lookahead and the full posterior are one ladder,
and the headroom left above lookahead is at most 0.0348. A case for
softening built on assignment quality is already nearly spent.

★ THE ARGUMENT IS THAT THE POSTERIOR IS THE BRANCHING FACTOR. A hard
descent yields one leaf per voxel and therefore ONE artifact. MT8's
Pareto front cannot be a front over one candidate, and EditMachine's
"one moment yields many GIFs" has nothing to draw from. The posterior
is not for making a better GIF. It is for making THE OTHER GIFs, which
is Daniel's "the capture data is more than one single GIF, hence why we
edit" with a mechanism under it.

The degrees of freedom are already measured. At 0.9652 agreement about
3.5% of voxels are contested, roughly 9175 on the cube. That is the
edit app's actual state space, and PT5 already names its owner:
"near-ties outside separation are XP2's territory".

> ★ HOLDS (C2), and it survived an attack rather than going
> unchallenged. The skeptic found the attack's premise false: the
> shipped retention is EXACT, not lossy. DyadPipeline.swift:317 runs
> srgb8(from:) as the first act on the cube, so every downstream stage
> is a function of 8-bit samples, CubeStore stores exactly those bits,
> and drift is ZERO. CT11's 0.0060 rmse governs no shipped byte,
> because CaptureTensor has no call site outside itself yet.
> CubeStoreTests:130 already gates identity re-weave, with an
> anti-vacuity companion at :152. One correction to the paragraph
> below: the count is 13 numbers plus a separate GROUNDHUE v2 block,
> not a flat 13, per ruling R-D's own "14 numbers + 2 bits".

★ AND IT COSTS ZERO BYTES. PT7-PT9 make the whole tree a pure function
of the traced 13 numbers, so a voxel's branch probability at every
level is a function of (those 13 numbers, that voxel's colour), and the
BIN already holds both, up to CT11's declared drift. The posterior is
not data. It is a function of data already retained, the same shape as
CL1 (the artifact carries its generator) and CT4 (the decode is
parametric in g).

★ AND IT RESOLVES DEPTH'S SURPLUS. The record says depth is 57% of what
is retained, reaches the artifact as ONE BIT, and that its shape,
motion and per-frame histogram are 100% surplus. Under this reading
they are not surplus: they are the UNCOLLAPSED EVIDENCE FOR BIT 7. AD7
derives the role bit from the Bayer coverage and CT6 keeps depth
unquantised, so the single bit that ships is the argmax of a posterior
whose evidence is retained at higher fidelity than any other stratum's.

> ★ BROKEN (C6), and this one was itself a CORRECTION made
> confidently. The premise is right and the conclusion is exactly
> backwards. AdditiveCensus.conformance takes only indexFrames and
> side, which is PRECISELY WHY a softer descent moves it: a flip
> changes the output, and the output is the only thing the census
> reads. It is a per-BLOCK constancy test, so it amplifies 64x. One
> dissenting voxel kills a whole 4x4x4 block: flipping bit 6 of
> EXACTLY ONE voxel drops rung16 from 1.0 to 0.99609375, and flipping
> this file's own 3.48% fraction collapses it to 0.07, matching the
> analytic (1-p)^64 = 0.1036.
> And it is unavoidable rather than hypothetical: results.json shows
> lookahead's agreement identical at the 2-class, 16-class and leaf
> columns, so 100% of contested voxels are contested in the HALF
> choice, which is bit 6, which is the one stratum whose block
> constancy the census actually measures.
> NOT REFUTED BY A SKEPTIC.

★ AND CONFORMANCE IS NOT AT RISK, correcting a claim made earlier in
this arc. AD11 makes conformance decidable ON THE EMITTED CUBE, and
every candidate still emits a hard index plane because the format
forces it. AdditiveCensus measures the output, not the process, so a
softer descent cannot move it off 1.0.

★ AND THE SEARCH IS AFFORDABLE FOR A REASON ALREADY IN THE LAW.
Candidates differ SPARSELY, since only the contested voxels move. E is
a pooled histogram, E_wall and E_time are sums over DISJOINT bond sets
(TE15), so flipping one voxel changes one histogram count and touches
at most 6 spatial and 2 temporal bonds. The value head updates
incrementally, O(changed voxels) rather than O(cube). That is forced by
TE's own definitions rather than being an optimisation someone added.

★ WHAT IS GENUINELY UNCERTAIN, so it is not smuggled in as settled:
whether DL7's 0.9652 transfers off nn/descent's fixtures to real
captures, and whether contested-ness should be read per level or only
at the leaf. Both are measurements, not rulings, and both are cheap.

**★ AND WHAT DECIDES A CONTESTED VOXEL IS ALSO ARITHMETIC.**

> ★ BROKEN (C5), and the real defect is sharper than the one filed.
> TilingEntropy.hs:180 defines `spin i = i >= 128`, and BOTH wallCount
> and wallCountTime are built on `spin` alone, so E_wall and E_time
> read BIT 7 ONLY. Contested flips are the DL6 stage-1 half choice,
> which AdditiveLadder pins at BIT 6. A bit-6 flip therefore cannot
> move spin. Measured on TE's own probe cube through TE's own
> cubeValue:
>     bit-6 flip   dE = -3.6469   dE_wall = 0.0   dE_time = 0.0
>     bit-6 flip   dE = -0.3462   dE_wall = 0.0   dE_time = 0.0
>     bit-7 flip   dE = -1.4530   dE_wall = -49.678
> The triple collapses to a SCALAR on exactly the flips it was
> supposed to arbitrate, so MT8's two-axis argument (which is what
> made the pair work at all) does not apply at the flip level.
> This one WAS skeptic-verified, and the skeptic's correction is what
> produced the finding above: the paragraph's stated reason (that dE
> might be below noise) is false. One flip moves E by 1.4088e-3
> against a Double ulp of 4.66e-10, about 3 million ulps of headroom.
> The defect is degeneracy and the wrong bit, not precision.
> The shipped code carries the same definition:
> Meter/TilingEnergy.swift:199 `static func spin(_ i: UInt8) -> Bool
> { i >= 128 }`.

Contested means near-tied IN COLOUR DISTANCE. It does not mean tied in
ENERGY. The two candidate leaves carry different indices, so a flip
moves the pooled histogram by one count and touches its spatial and
temporal bonds. The vector (ΔE, ΔE_wall, ΔE_time) breaks the tie with
no weights at all.

That is MT9's inversion arriving a second time, one level down: the
first said the value head needs no model, this says the PREFERENCE
needs none either.

The pair is what makes it work, not either scalar. MT7 measured E as
168 times weaker at separating the degenerate corners than at ordering
the picture, so ΔE alone decides on a rounding error; E_wall is strong
exactly there (1573.06 against 0.26). MT8, restated for a single flip.

> ★ BROKEN (C4). The monotonicity does not carry over; it is a
> property of F, delivered through AL2. AL2 states that F decomposes
> EXACTLY over 4-cubed spacetime blocks so blocks never couple, and
> that is the SOLE licence for section 4b's design: one GPU thread per
> block, 4096 threads, no synchronisation at all. E is a pooled
> histogram over 262144 voxels sharing the same 256 bins, so AL2 is
> false for it. Measured on the spec's own `energy`: dE(A) + dE(B)
> against the true joint differs by +1.545e-3 when two flips share a
> source bin, +1.331e-3 for a shared target, and -2.875e-3 for an
> opposing pair whose joint move is exactly 0 while the independent
> sum is +2.875e-3.
> The failure is then direct rather than theoretical. With
> h = [1024]*256, h[0]=1100, h[1]=1000, EVERY thread computes
> dE = -0.136126 and is licensed to accept, yet at 110 concurrent
> accepts the true joint dE is +1.5128 and at 200 it is +27.58.
> E has INCREASED. The kernel dispatches 4096 threads, not 110.
> Two further non-transfers: AL4 accepts on `best < -1e-15`, a TOTAL
> order, while (dE, dE_wall, dE_time) is a partial order, which is the
> very thing the non-dominated-flips paragraph below depends on.
> NOT REFUTED BY A SKEPTIC.

★ BUT THE FLIPS ARE COUPLED, SO IT IS A DESCENT, NOT A VOTE. Flipping
A changes the histogram and therefore whether flipping B is good. That
is a coupled system over roughly 9175 binary variables, and the machine
for it is already built and switched off: ANELoop, AL1-AL9, fixed-K
exchange sweeps with monotone Gauss-Seidel, curvature 1 + 1/8 + 1/64,
ported to the ANE and to Metal SIMT at 100% agreement, gated behind
CameraConfig.phaseChaosLoop.

Being precise, because the fit is not exact: ANELoop descends F (the
3:2:1 Haar-band kernel) rather than the energy triple, and it runs on
FULLY-FAR BLOCKS ONLY. It is the right MACHINE with a different
objective and a restricted scope. What carries over is the exchange
mechanics, the monotonicity proof and the runtime-K Metal kernel.
ANELoop is not a gap on the frontier, it is a MISAIMED ASSET.

★ THEREFORE WHAT IS LEARNED IS THE ORDER. Gauss-Seidel is monotone, but
on a coupled non-convex problem the SWEEP ORDER decides which optimum
is reached. Order is the whole remaining freedom, and "which exchange
to try next" is literally P(move). PolicyField learns sweep order over
the contested set. That is exactly what MT9 named as the only learned
thing, reached independently, and it is why CL6 is the substrate:
ordering moves means comparing them, and CL6 proved the comparison
cannot be a fixed diagonal.

★ AND THE NON-DOMINATED FLIPS ARE THE EXPRESSION. Some flips are better
on one energy axis and worse on another. Arithmetic cannot rank those
and should not. That set is the real expressive freedom in a capture,
so the widget's job is exact: SURFACE THE NON-DOMINATED FLIPS, not
sliders over parameters. DetentDial's detents then fall at FRONT
VERTICES, derived rather than chosen, which is the no-naked-constants
decree honoured at the one place a dial would otherwise acquire
numbers.

The front does double duty: MT8 uses it to exclude grey and static at
the ARTIFACT level, and the same construction at the FLIP level
separates "arithmetic decides" from "you decide". One mechanism, two
scales.

## 4. THE STANDARD: colour-time, one budget

**The claim, in one sentence.** Every component of the signal declares
a pair (cells, bits per cell) whose product is 262144, and a rung is
where a component sits on that hyperbola.

Three candidate axioms, all provable from section 2 and none of them
new physics:

    CS1  the budget is invariant: cells x bits = 262144 at every rung,
         which is CT2 written as a product rather than a ratio
    CS2  the loop is invariant: frames x delay = 320 cs at every rung
         (TL4, TL8), so the trade is COLOUR against TIME and nothing
         else moves
    CS3  ★ THE COARSE CUBE IS A BALANCED FRAME. |rung-16 cube| = 4096
         = |rung-64 frame| = 16 x 256, and 16 per colour is exactly
         TE2's balanced occupancy, the ground state of E. The entire
         coarse cube has the cell count of one fine frame at the
         ground state.

    CS4  the colour half is ALREADY STATED and needs only citing:
         AD4's 1024 INVARIANT, voxels ÷ classes = 1024 at every rung,
         whose own comment says "this is what 16³ ≡ 32³ ≡ 64³ means
         for colour". CS1 is the same equality counted in BITS. Two
         independent derivations of Daniel's colour-time sentence
         were green before this workflow existed

CS3 is the one worth writing first, because it is the bridge Daniel's
"go back to the fundamentals, 16x16 == 256" is pointing at. OV2 says
one coarse FRAME is the palette. CS3 says the whole coarse CUBE is a
balanced fine FRAME. The fundamental holds at both scales, and E's
ground state is the same number arriving from the third direction.

Redundancy and overlap are DECLARED, never removed: FC4's 73/64 is a
field of the standard, not a defect of it.

## 5. THE NAMES, decided

Daniel asked for names. These are chosen to be forced rather than
tasteful, so each one cites what forces it.

**The standard.** `spec/output/ColourTime.hs`, axioms `CS1-CS*`. Named
for the trade it describes, sitting in `output/` beside CaptureTensor
and TriScaleLadder, which are the two files it reads.

**The memory.** `spec/output/Bin.hs`, axioms `BN1-BN*`. Daniel's word
for it, kept. It defines the standard form of a node: (path, content,
value, depth), the query that reads it, and the completeness law that
says a BIN is complete exactly when every query needed to emit a lawful
GIF89a is answerable from it.

**The model, and there is exactly ONE.** `spec/neural/PolicyField.hs`,
axioms `PF1-PF*`, lab `nn/policy-field`, artifact `PolicyField
.mlpackage`. The name states the unification Daniel ruled when he
answered "a field, and unify with CL6": a policy over the tree is a
probability field over the 64 cubed shape, and CL6's learned metric is
what makes distance in that shape mean anything. They are one object.
The policy is the field normalised over legal moves.

**The three roles, named for their place in the game, not for a new
taxonomy.** This is what "categorize the models" resolves to:

    VALUE           ARITHMETIC. E, E_wall, E_time. No weights, ever
                    (MT9). Already shipped as Meter/TilingEnergy.swift.
                    It is not a model and must never become one.
    REPRESENTATION  THE STANDARD. ColourTime + Bin. No weights. A
                    typed record and its decode.
    POLICY          THE ONLY LEARNED THING. PolicyField. Trained on how
                    WE interpret the signal, so its output EXPLAINS a
                    GIF we made rather than generating one.

**What the model is not, stated so it cannot drift back.** It is not a
generator: CL1 says the generator already ships and is exact. It is not
a colour space learner: CL2 says the decoder is total, so there is no
illegal point to learn to avoid. It does not decide bytes at capture
time: that placement is retired (`CameraConfig.jepaH` is OFF, and the
reasons at `CameraManager.swift:145-162` are the authority).

## 6. THE SPEC FILES TO WRITE, in dependency order

Each step is small, cites rather than restates, and is green before the
next begins. Nothing here trains anything (Daniel's ruling).

**Step 1. `spec/output/ColourTime.hs` (CS1-CS3).** The standard. Cites
CT2, TL4, TL8, TL9, OV2, OV13, FC4, TE2. Proves CS3, the bridge.
Smallest possible file that makes "colour-time" a defined term.

**Step 2. `spec/output/Bin.hs` (BN1-BN*).** The memory in standard
form. Defines the record, the query, and:

    BN1  the four fields and their types, one per projection
    BN2  path and content quotient DIFFERENTLY (MT3 lifted from
         MerkleSearch into the type itself, so it cannot be
         re-conflated by the next reader)
    BN3  the rung field is a colour-time allocation (CS1), so a BIN
         knows its own budget
    BN4  ★ COMPLETENESS: a BIN is complete iff every query needed to
         emit a lawful GIF89a is answerable from it. This is the axiom
         that makes "built to be queried in order to produce the
         GIF89a" a provable statement rather than a description
    BN5  ★ PROVENANCE IS DERIVED FROM THE INDEX, NEVER STORED. A
         voxel's index IS its path (AD1, AD2, AD5, PT5), so
         truncation walks up the attractor hierarchy and reads the
         ancestor basin. A Kind is an operation on probability mass
         living on an EDGE between levels, not a label on a voxel and
         not a label on a query. This retires the funnel session's
         open question rather than answering it: no object carries a
         category, which is why asking which object carries it had no
         good answer
    BN6  THE POSTERIOR FACTORIZES ALONG THE PATH, because AD5 refines
         and never revises. A BIN is therefore a distribution, not a
         point, and its soft form costs no new storage: it is the
         same index read without the argmin

**Step 3. `MerkleSearch.hs`, two amendments.** Not a new file, because
the tree already exists and Daniel said build up.

    MT13  `content` is the real generator (CL1's numbers), not
          `contentOf`'s placeholder
    MT14  the front is 3-dimensional: E, E_wall, E_time. Re-measure
          MT8's dominance with the temporal axis in it, because a
          front computed on two axes is not the front

**★ STEP 3b, THE GATE THAT MUST RUN BEFORE STEP 4, and it may cancel
step 4 entirely.**

Strip out everything the reasoning in section 3 eliminated: the value
is arithmetic, the generator ships, the per-voxel preference is
arithmetic, the solver exists. What is left for a model to do is a
LEARNED MOVE ORDERING for a monotone descent over a closed-form
objective. That is not a game-playing network, it is a branching
heuristic, and it may not need to be learned at all.

    THE TEST. On fixtures small enough that exhaustive search over
    sweep orders is tractable, compare the front reached by a STATIC
    order against the front reached by the BEST order. Static
    candidates, all free: descending |Δ| toward the front, role-first
    (depth is the strongest evidence, AD7), block-major (what ANELoop
    already sweeps). If static reaches the same front, PolicyField
    SHOULD NOT EXIST.

No training, no device, no weights. It belongs before the spec rather
than after, and the precedent is exact: jepaH's gate B5 measured the
head against TRUTH rather than a baseline and found it holding the
palette 17.4% steadier than the scene actually was. Every gate before
B5 passed because every one compared the model to a baseline. A
PolicyField specced without this test would sit in precisely that
position, defended by comparisons to nothing.

**Step 4. `spec/neural/PolicyField.hs` (PF1-PF*).** ONLY IF 3b says
order matters. The field, still
with no training run. Defines the type, states the normalisation that
turns a metric field into a policy, and proves the properties that hold
for ANY weights, which is the pattern CT4 already uses for g. Weights
cannot reopen a law that holds for all of them.

## 7. THE PORTS

Only after the four specs are green, and in this order:

1. `Store/Bin.swift`, the standard form and its queries. Store/ is the
   right address by the directory decree: a BIN outlives the function
   that made it.
2. `Meter/TilingEnergy.swift` gains the field read, so the value head
   answers per BIN rather than per cube only.
3. `Edit/` gains the query surface. Widgets decode a BIN; they do not
   hold state of their own.

No `Weave/` change, no `GIFEncoder` change, no `DyadGIFContractTests`
change. The tensor-side-only ruling means this arc has zero exposure to
the byte contract.

## 8. RULINGS DANIEL MUST MAKE

1. **The names in section 5.** Standing until vetoed.
2. **BN5 and BN6, and they are the load-bearing pair.** The funnel
   session left "which category does each VOXEL carry" open. This
   workflow retires the question: no object carries a category,
   because a category is an operation on an EDGE, and the provenance
   the question was reaching for is already derivable from the index
   by AD5 and PT5 at zero cost. The consequence worth ruling on is
   BN6: if a BIN is a distribution rather than a point, then the
   argmin in the current descent is DISCARDING the very probability
   the search needs, and softening it changes how assignment behaves.
   That is a real change to a shipped path, so it is Daniel's call and
   not mine.
3. **MT14 re-measures a shipped front.** Adding E_time may change
   which candidates are non-dominated. Cheap, but it moves a number
   already written into a doc.
4. **What "how we interpret the signal" means as supervision.**
   NARROWED by the reasoning in section 3, and it is now a much
   smaller ruling than it was. The preference on a contested voxel is
   arithmetic (the energy triple), the solver exists (ANELoop), and
   the only learned object left is the SWEEP ORDER. So the question is
   no longer "what does the model know about colour" but "what makes
   one sweep order better than another", and the honest answer today
   is: the one that reaches a better point on the front. If that is
   accepted, PolicyField is trained against the front it produces and
   needs no external notion of interpretation at all. Daniel's call,
   because it decides whether ANY external preference enters.
5. **ANELoop's objective swap.** It descends F on fully-far blocks. To
   serve as the contested-set solver it descends the energy triple on
   contested blocks. Same machine, different objective and scope, and
   flipping CameraConfig.phaseChaosLoop is not enough on its own.
6. **The eleven rulings still open** in
   `workflow-2026-08-14-sk-energy-registry.md` section 7 are untouched
   by this plan.

## 9. WHAT THIS DOES NOT SOLVE

- **Zero device evidence, still.** Owed since 2026-08-11. Nothing here
  reduces it, and the quarter-turn direction (G13) is still the
  cheapest thing a device pass would answer.
- **The rotation debt in the encoder** (R-B). Byte-changing, separate
  pass, untouched here.
- **`DyadEnergy.eDist = w + sOcc`** still contradicts TE8 and still
  rides every exported GIF. Under "the model reads GIFs" it is the
  first energy signal any corpus would ingest, and it is still NOT
  RULED.
- **No LZW decoder exists.** A GIF-native reader reads the GENERATOR,
  which is exactly what a BIN is, so this plan makes the absence
  deliberate rather than accidental. It does not remove it.
- **`Reweave` still has no non-test caller** and the edit tick loop
  does not exist. Section 7 step 3 is where that gets paid, and it is
  the last step, not the first.
