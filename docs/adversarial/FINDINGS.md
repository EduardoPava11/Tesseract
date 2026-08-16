# FINDINGS, adversarial run 2026-08-15

Five survivors. Each was filed by an adversary, then attacked by an
independent skeptic whose job was to refute it. Only findings the
skeptic failed to kill appear here. Severity is the skeptic's corrected
severity, not the finder's.

Ranked most severe first.

| # | ID | Dimension | Severity | Status |
|:--|:--|:--|:--|:--|
| 1 | P3-AERIAL-KERNEL-UNGATED | ports | major | UNGATED |
| 2 | P2-STAGED-TARGET-TWO-CONVENTIONS | ports | major | DIVERGENT |
| 3 | N3-THRESHOLD-CROSSOVER-SIGN | numbers | major | DIVERGENT |
| 4 | CL7-LITERAL-EQUALS-ITSELF | vacuous | major | VACUOUS |
| 5 | N4-SPEC-LEDGER-9B-VS-13B | numbers | minor | DIVERGENT |

Findings 1, 2, 3 and 5 were reproduced by running code. Finding 4 was
reproduced by running the mutated spec file. Nothing here is reasoned
about only.

## 1. P3, the aerialPreview kernel has no parity gate at all

TARGET: `Tesseract/Solve/Quantize.metal:6` (the kernel), gated nowhere.
`TesseractTests/DyadPipelineTests.swift:413-429` is the only test that
mentions it.

CLAIM AS THE REPO STATES IT. CLAUDE.md, NO STUBS NO FALLBACKS: "A twin.
One law, two engines, and a parity test proving they agree ... A twin
without a live parity gate is just a fallback that has not been caught
yet." `Quantize.metal:6` calls `aerialPreview` "the 20 Hz GPU twin of
DyadPipeline.Live.assign".

DEFECT. There is no parity gate. The complete list of tests that
dispatch a Metal kernel is MetalGeometryParityTests (downsample),
ANELoopSIMTParityTests and ANELoopBenchTests (ANELoop.metal).
`MetalPipeline.aerialAssign` is called from exactly one place in the
repo, `CameraManager.swift:934`, which is the shipping live path, and
from zero tests. `testBleedAndPhaseReachTheMetalState` asserts five
struct field copies (`metal.bleed == solve.bleed`,
`metal.sStar == Float(solve.mixture.crossover)`, and three more). It
never builds a texture, never dispatches, never compares an index. It
proves the parameters were handed over, not that the same picture comes
out. This is the FrameGeometry lesson repeating one directory over.

The gate that does not exist would have caught two things on its first
run.

(a) The staging divergence of finding 2, at 3.0% to 11.7% of pixels.

(b) A degenerate per frame fit hands the kernel `sStar = Float(NaN)`
and `tau = Float(+inf)`. The CPU has the C5 coverage guard
(`coverage(_:fit:twoPhase:bleed:)` returns 0); the kernel has no
degeneracy input at all, and its BLEED-off line 102
`t = (t < 0.5) ? 0.0 : 1.0` maps NaN to 1.0, routing every Bayer
threshold to sigma. Result: 4096/4096 pixels flip role, a whole screen
inversion of a preview frame.

The laws riding on the kernel and unmeasured on the GPU: the AERIAL
MIRROR LAW (DY9/DY10 gamma staging), the role and coverage law (DM8
plus C5), the BLEED branch of the role law, the v7 CHAOS BLUR (DY16),
and PAIR TREE P2's prefix law.

BREAK TEST. Write `AerialParityTests`. Build a 64x64 rgba16Float RGB
texture and a depth texture from a synthetic figure over ground field,
drive `DyadPipeline.Live` to get a real `solve`, then assert
`metal.aerialAssign(state: live.metalState!)` equals
`live.assign(rgb:depths:)` index for index with no tolerance, the same
discipline `MetalGeometryParityTests` already uses on the downsample
path.

For leg (a), 16 frames of a healthy scene is enough: 3.49% mismatch with
BLEED on, 4.27% with BLEED off, 11.65% when the subject leaves mid ring.

For leg (b) the fixture must be specific, and the finder's original
fixture would NOT have exposed it. Needed: a coarse frame of constant
depth inside a ring whose pooled fit still votes two phase AND
alpha = 1. `DepthMixture.localLevelAlpha:184,195` returns 1 whenever
`series.count < 3` (the two coarse frame ring about 0.2 s into every
session) or `bigR == 0` (smooth drift). Constant depth is common because
`DepthSignal` clamps everything past `dFar` = 1.5 m to exactly 0. Under
that fixture the mismatch is 4096/4096, every one an opposite half role
flip, with `twoPhase = true`, `s* = nan`, `tau = inf`,
`mixture.isDegenerate = YES`.

SKEPTIC VERDICT: NOT REFUTED, severity corrected critical to major.
The skeptic built a standalone harness outside the repo, compiled the
app's own `DyadPipeline.swift` plus its full dependency closure
(DyadPalette, PairTree, DepthMixture, DepthSignal, StrataDescent,
JepaHHead, PerfectQuantizer, FrameBuffer, ExportSettings, ANELoop, and
CameraConfig extracted verbatim from CameraManager.swift) for macOS, and
dispatched the repo's own `Quantize.metal` through
`MTLDevice.makeLibrary(source:)` with the exact buffer layout
`MetalPipeline.aerialAssign` uses (48 byte AerialParams, 128 prims, up
to 16 nodes, 1/dNear and 1/dFar, 8x8 threadgroups). Six scenarios, 64
frames each. Both legs reproduced. Re-ran the degenerate case with
`MTLCompileOptions.fastMathEnabled` both true and false: identical.
Every face side mismatch (143/143, 175/175, 349/349, 912/912) is picked
by the un-round-tripped staging, so it is systematic, not fp noise.

Corrected down from critical because this is the LIVE preview only.
`aerialAssign` is called from `CameraManager.swift:934` and nowhere
else; the export runs StrataDescent on CPU and ANE. No exported GIF byte
moves and nothing crashes. It is still the default shipping path, and a
whole screen inversion under BLEED off is exactly the "one setting, two
answers on one screen" defect the D1 test was written for and
structurally cannot see.

## 2. P2, one law, three implementations, two conventions for what the argmin reads

TARGET: `spec/quantization/DyadPalette.hs:521-523` (authoritative)
versus `Tesseract/Solve/DyadPipeline.swift:200-207` versus
`Tesseract/Solve/Quantize.metal:85-90`.

CLAIM AS THE REPO STATES IT. CLAUDE.md:410: "Haskell is authoritative;
Swift/Metal are ports." `DyadPipeline.swift:196-199`: `stagedField` is
"the DY12 construction ... Export and preview call this, there is no
second staging." `Quantize.metal:83-84`: "the DY12 byte round-trip the
CPU reference applies".

DEFECT. The three implementations disagree about which y-hat the nearest
primary search consumes.

Authoritative Haskell `aerialPrimary` (`DyadPalette.hs:522-523`) is
`nearestPrimaryLab tbl (stageAerial cF s (srgb8ToOklab c))`, the
CONTINUOUS staged y-hat. `stageOf` at line 794, used by DY10 and DY11 at
803, 805 and 807, is the same. The only round tripped staging in the
entire spec is DY12's own line 858, and DY12 is about STATS (`analyze`
takes RGB8); its three clauses are determinism, involution exactness and
centroid stability, every one of which is invariant under which y-hat
the assignment reads.

The Swift port hoisted DY12's stats round trip onto the ASSIGNMENT path.
`stagedField` returns `(UInt8, UInt8, UInt8)` and both consumers
(`Live.assign:1130-1132` and `process:323,338`) feed
`oklab(fromSRGB8: staged)` to the argmin.

The Metal kernel round trips the INPUT only (line 85) and feeds the
continuous y-hat (lines 90 and 165). So the kernel matches the Haskell
and the Swift does not, and the two shipped ports disagree with each
other.

Sixteen DyadPalette axioms are green and cannot see it, because no axiom
ever states which y-hat the argmin consumes. This is the Quantize.metal
vacuous axiom template exactly.

BREAK TEST, spec side, run and failing. Add this axiom to a copy of
`spec/quantization/DyadPalette.hs`:

```haskell
axiom_DY17 = and [ nearestPrimaryLab tbl y
                     == nearestPrimaryLab tbl (srgb8ToOklab (oklabToSrgb8 y))
                 | c <- randColors8 31 400 ++ skinColors 7 400
                 , s <- [0, 0.1 .. 1.0]
                 , let y = stageAerial cF s (srgb8ToOklab c) ]
  where tbl = buildDyad (skinColors 1 324)
        cF  = srgb8ToOklab (head tbl)
```

Run `cd spec/quantization && runghc -W -package-env=- -i. RT.hs`.
Result: total 8800, mismatch 368, that is 4.18%. Mean displacement
8.4057e-4 OKLab, max 1.9555e-3, four orders of magnitude above the fp32
eps (8.3e-08) the kernel header licenses as "the only permitted
difference".

BREAK TEST, Swift side, run and failing. Compile the app's own
`Tesseract/Solve/DyadPalette.swift` unmodified into a standalone harness
(`swiftc -O main.swift Tesseract/Solve/DyadPalette.swift`) and compare
the two conventions on a 64x64 field: random field 157/4096 = 3.83%,
skin field 199/4096 = 4.86%, mean displacement 8.9447e-4.

BREAK TEST, port side, the gate that should exist: dispatch
`MetalPipeline.aerialAssign(state:)` on a synthetic 64x64 field and
assert index for index equality with `live.assign(rgb:depths:)`. It
mismatches on 2% to 9% of the 4096 pixels. No such test exists, which is
finding 1.

One line probe that decides which port is wrong: change
`Quantize.metal:90` to round trip y-hat
(`yhat = oklabFromSrgbGPU(round(saturate(srgbFromOklabGPU(yhat))*255)/255)`)
and the GPU/CPU mismatch drops to fp32 noise, but then Metal contradicts
`aerialPrimary`. The spec has to rule and today it has not.

SKEPTIC VERDICT: NOT REFUTED, severity corrected critical to major.
Both languages reproduce independently, Haskell at the finder's exact
368/8800 and Swift at 3.83% and 4.86% using the app's own file. Every
refutation route died: `oklabToSrgb8` appears in the spec's quantization
directory exactly once, at `DyadPalette.hs:858` inside DY12 feeding
`buildDyad` (table construction, which Swift also does), so the
divergence is purely the assignment's y-hat. `stageAerial` in
`PhasePalette.hs:796` and `GroundHue.hs:835` is continuous in both.
StrataDescent's spec names no staging convention at all. Zero tests
instantiate `MetalPipeline`.
`TesseractTests/DyadANEParityTests.swift:86-90` is blind by
construction: it builds `frameLabs` with `DyadPipeline.stageAerial` and
NO round trip, so it feeds the continuous convention to BOTH sides of
its own comparison.

The flips are not cosmetically null. Median OKLab separation between the
two candidate primaries at a flip is 0.01778 (p90 0.03471, max 0.04146)
against a palette median nearest neighbour spacing of 0.00930, so a flip
jumps about 1.9x the palette's own resolution.

TWO CORRECTIONS TO THE FINDER. First, the Metal kernel is preview only
by its own header (lines 7 to 9), so the EXPORTED bytes are the round
tripped ones. The export is the side deviating from authoritative
Haskell and the GPU preview is the side that matches it; the finding's
phrase "these bytes are exported" invites the opposite read. Second,
severity is major not critical: both conventions are internally lawful
(DY10 seam death and the involution hold either way, the emitted pair is
still q or partner(q)), nothing crashes, and
`DyadPipeline.swift:1140-1158` already confesses in writing to a LARGER
acknowledged preview versus export divergence (StrataDescent versus free
128 search) on the same path.

The sigma side diverges identically: CPU `chaosPool` pools round tripped
labs, kernel lines 127 to 141 pool continuous.

## 3. N3, the Python reference threshold uses an inverted crossover sign

TARGET: `nn/tensor-codec/build_model.py:212` (the wrong side) against
`spec/temporal/DepthMixture.hs:182` and `DepthMixture.swift` (the right
side), consumed at `Tesseract/Store/CaptureTensor.swift:227`.

CLAIM AS THE REPO STATES IT. CLAUDE.md presents CaptureTensor.swift as
"the CPU law" with TensorANE.swift its "engine TWIN" and
`nn/tensor-codec/build_model.py` as the reference the port is gated
against: one law, three implementations. CLAUDE.md cites the Python
24.9% loud fraction and the Swift 1,099,586 B nine lines apart as if
they came from one measurement.

DEFECT. They came from two measurements that differ by 60%. On the
identical synthetic cube (`CaptureTensorTests.swift:20` is formula for
formula identical to `build_model.py:233 synthetic_cube`: same seed
20260814, same ground 0.42 + 0.02*sin(0.09x + 0.05y), same exp(-d2/90)
figure, same [1.0, 0.35, -0.2]*0.45 channel weights) Python returns
0.24862 loud and Swift returns 0.15576 loud, that is 1914 of 12288
roots.

The finder's diagnosis (two different fitters) is WRONG and the
corrected diagnosis is stronger. Both EMs converge to identical
parameters to 8 significant figures: muB = -7.31834806,
muF = -5.01066412, sigma = 0.7791933850870635, piB = 0.8442852078757347.
The entire divergence is one inverted sign in the closed form.
`build_model.py:212` writes `log((1-w)/w)` where
`spec/temporal/DepthMixture.hs:182` and `DepthMixture.swift` write
`log(piB/(1-piB))`.

Which side is wrong was proved, not asserted. At the Swift crossover the
two weighted component densities are equal, ratio 1.0000, a true equal
posterior crossover. At the Python point the quiet component is 29.40x
the loud one, so Python's value is the reflection of the true crossover
about the midpoint and is not a crossover at all. Corroborated twice
more: with piB = 0.844 the equal posterior boundary must shift toward
the minority loud component (Swift's -5.720 sits above the -6.165
midpoint, Python's -6.609 below it), and Python's 24.9% loud exceeds the
loud component's own fitted weight of 15.6%, which is internally
incoherent.

The gate does not exist. `CaptureTensorTests.swift:145-146` asserts only
`loud > 0` and `loud < 12288`, which passes for every published
fraction. `CaptureTensor.hs:259` asserts `cheaperAt 0.047`. CT8's
comment says 8.9%. Nothing compares any two implementations.

CONSEQUENCE, sharper than the finder's. `spec/neural/TensorEncoder.hs`
TA9 asserts `colourRatio > 20` using a hardcoded 0.047, and that
assertion is FALSE at the loud fraction the shipped Swift law actually
measures on the documented fixture (18.15 : 1) and false at the Python
one (14.67 : 1). Recomputed with the spec's own `signBytesAt` at
0.047 / 0.15576 / 0.24862 the ratio is 25.12 / 18.15 / 14.67. TA9 is
green only because it quantifies over its own restated literal rather
than over any measurement. That is the MerkleSearch restated constants
template verbatim.

SEPARATE DEFECT FOUND WHILE CHECKING CONSEQUENCE.
`nn/tensor-codec/noise_floor.py`, the script CLAUDE.md:276 cites for its
ruling table, prints the REVERSE of what CLAUDE.md reports (noiseless
gives single phase and pay flat; noisy gives two phases at 22.7%),
because `noise_floor.py:89` passes `reference(cube)[3]`, which is g32
alone, not `dev16_of(g32, g64)`. The ruling Daniel is being asked to
make is documented from a different script than the one cited.

BREAK TEST, Python side:
`cd nn/tensor-codec && python3 -c "from build_model import *; import numpy as np; c=synthetic_cube(noise=0.0).astype(np.float64); _,_,_,a,b=reference(c); d=dev16_of(a,b); t,v=derived_threshold(d); print(v, float((d>=t).mean()))"`
prints `two phases 0.24861653645833334`.

BREAK TEST, Swift side, without the simulator: port `DepthMixture.fit`,
`isTwoPhase` and `crossover` line by line to Python and run on the SAME
saved dev16 array: thr 0.0032805115, loud 0.15576171875, count 1914.
Cross check 1914 against `CaptureTensor.bytesPerCapture`:
16 + 1048576 + 24576 + 1536 + 1914*13 = 1,099,586, exactly CLAUDE.md's
published Swift figure.

The decisive one line proof of which side is wrong: print the two
weighted component densities at each candidate crossover. Swift ratio
1.0000, Python ratio 29.40.

The gate that should exist: a parity test asserting
`abs(swiftLoud - pythonLoud) < 0.01` on this fixture. It fails today.

SKEPTIC VERDICT: NOT REFUTED, mechanism corrected, severity major. The
numeric divergence reproduces exactly and 1914 reproduces CLAUDE.md's
1,099,586 B to the byte. The finder misdiagnosed the mechanism; the
corrected mechanism (one inverted sign) is a smaller cause with a larger
blast radius, because it also indicts TA9.

What keeps this out of critical: the Python crossover ships nothing. The
mlpackage graph (`build_model.py:107-145`) emits only l16, sign32,
sign64, g32, g64; the threshold fit is CPU side Swift, which is the
correct implementation and matches the Haskell law. No on device byte is
wrong. The damage is to the reference implementation, to a green spec
axiom that is false at the real value, and to the measured figures
Daniel is ruling on.

## 4. CL7, an axiom that compares a literal to itself

TARGET: `spec/neural/ColourLatent.hs:424-429` (axiom_CL7).

CLAIM AS THE REPO STATES IT. "THE LEVELS ARE THE ARTIFACT'S, NOT THE
MODEL'S. AdditiveLadder already proved the index is three strata, so a
hierarchical latent has its depth FORCED at three and its widths forced
at the strata's own level counts. Nothing here is a hyperparameter."
CLAUDE.md leans on this twice, including in ruling R-D to force the
unbuilt model's internal ladder 64 to 16 to 4.

DEFECT. The axiom body is

```haskell
axiom_CL7 =
     levels == [4, 32, 256]
  && product [4, 8, 8] == 256
  && length levels == 3
  where levels = [4, 32, 256]
```

The first conjunct compares a locally bound literal to the same literal
written twice, that is `x == x`. The second and third are closed
arithmetic on further literals. The axiom has no free variable and no
reference to anything outside its own `where` clause.

Its cited source of truth is AdditiveLadder's `stLevel` fields
(s16 = 4, s32 = 32, s64 = 256), and ColourLatent.hs imports only
Data.Bits and Data.List. No spec file imports any other spec module,
anywhere in the suite, so the citation is a comment and the numbers are
a hand copied restatement. That is the MerkleSearch failure mode in its
purest form. "Nothing here is a hyperparameter" is established by
nothing. The three literals ARE the hyperparameter.

A second restatement sits in the same axiom: `product [4, 8, 8]` is a
different tuple from DL1 and AD6's fan outs `[2, 8, 8]`.

CONSEQUENCE. CLAUDE.md ruling R-D says the model's "Internal ladder
64 -> 16 -> 4, which is CL7's strata [256, 32, 4] ... both forced."
Those are not the same ladder. 64 -> 16 -> 4 has ratio 4, CL7's levels
have ratio 8, and only the trailing 4 coincides. A ruling forcing an
unbuilt model's architecture already cites CL7 as authority for a triple
CL7 does not contain.

BREAK TEST. `cp spec/neural/ColourLatent.hs /tmp/CL.hs`; change
`module ColourLatent where` to `module Main where`; change BOTH
occurrences of `[4, 32, 256]` inside axiom_CL7 (the comparison at line
426 and the `where levels =` binding at line 429) to `[9, 77, 1000]`.
Run `runghc -W -package-env=- /tmp/CL.hs`. It prints
`CL7  the levels are the artifact's, not the model's` with a green tick,
alongside CL1 to CL8 all green and "all axioms hold". A latent hierarchy
of widths 9 / 77 / 1000 has nothing to do with AdditiveLadder's strata,
and the axiom certifies it.

SKEPTIC VERDICT: NOT REFUTED, severity corrected critical to major, one
leg of the finding weakened. The break test reproduces exactly. Gate
search found nothing: `grep -rn "4, 32, 256\|256, 32, 4"` over every .hs
and .swift file in the repo returns exactly two hits,
`ColourLatent.hs:426` and `:429`, the two halves of the tautology. No
Swift port of ColourLatent exists (none of the 48 files in
TesseractTests touches it). No spec file imports another spec module, so
the cross file check is architecturally impossible today.
`scripts/lint-grid.sh` has no constant restatement check.

LEG WEAKENED. The finder wrote "change AdditiveLadder's stLevel and CL7
stays green forever". The skeptic mutated AdditiveLadder.hs's s32
stLevel from 32 to 77 and ran it: AD3, AD4 and AD5 go red. So
AdditiveLadder is NOT blind to its own drift and the suite is stronger
than the finding claimed. That does not save CL7: the defect is CL7
asserting its own literals, which the break test shows will certify any
triple whatsoever.

Corrected from critical because no shipped byte, no test and no Swift
port depends on CL7; R-D is marked OPEN and not started; and the
restated literals are currently CORRECT against
`AdditiveLadder.hs:70-72`, unlike MerkleSearch which had them wrong. The
defect is that the axiom certifies nothing and would certify anything.

## 5. N4, the spec byte ledger charges 9 B per loud root, the format writes 13 B

TARGET: `spec/neural/TensorEncoder.hs:178-180` (`signBytesAt`), printed
by `tensorBytes` as "TOTAL 1079902 B".

CLAIM AS THE REPO STATES IT. TA9's ledger prints the retained tensor as
"colour signs, loud 5198 B / TOTAL 1079902 B", and CLAUDE.md states the
format "stores g rather than predicting it" at a cost of "4 B per loud
root".

DEFECT. `signBytesAt` charges `loud * 12288 * 72 / 8` = 9 B per loud
root, counting only the 8 + 64 sign bits and omitting the 4 B of g the
format actually writes. The shipped port charges the right amount:
`CaptureTensor.swift:405` `perLoud = 4 + (children32 + children64) / 8`
= 13 B, and `writeSubtree` (lines 303 to 311) emits two fp16 g values
before the 72 sign bits, which `decode` reads back off the wire. So the
spec's ledger is 44% light on the loud payload and its printed TOTAL can
never be produced by the encoder it describes.

TA9 does not catch it because both clauses it gates
(`colourRatio > 20`, `depthShare > 0.95`) survive the undercount.

ROOT CAUSE IS DEEPER THAN A TYPO. `spec/output/CaptureTensor.hs`, the
file that owns the stored bytes, prices a PREDICTED-g format throughout:
StepFn and withTemporal derive g from parent and prev, CT4 is
"parametric in g", CT7 and CT8 budget 1 + 72 BITS, no byte for g. The
port deliberately stores g (its own header says "costs 4 B per loud
root") and the Haskell was never updated.

SECOND VACUOUS AXIOM ON THE SAME DIVERGENCE. TA6's prose claims "the
DECODER recomputes g from stored parents", which the shipped `decode`
contradicts, and TA6's body is
`and [ signBit r == signBit r' | (r, r') <- zip rs rs ]`. `zip rs rs`
pairs a list with itself. It is a tautology.

PROPAGATION. The same 9 B model is repeated at
`nn/tensor-codec/build_model.py:222` and
`nn/tensor-codec/noise_floor.py:75`, so CLAUDE.md's quoted "24.9% loud,
14.7 : 1" is really 11.94 : 1 at the shipped 13 B (flat row 5.75 goes to
4.23). The noiseless versus noise ranking the ruling rests on is
unaffected.

BREAK TEST. In a copy of `spec/neural/TensorEncoder.hs` change
`ceiling (loud * fromIntegral (cells16 * channels) * 72 / 8)` to
`* 104 / 8` (13 B per root, matching `CaptureTensor.swift:405`) and run
`runghc -W -package-env=- TensorEncoder.hs`. The printed TOTAL moves
1079902 to 1082212 B and "colour signs, loud" moves 5198 to 7508 B,
while all nine axioms STILL PASS. That is the proof the spec's byte
model and the shipped byte model differ and that no axiom notices.

Gate search that should have existed:
`grep -rn "signBytes|perLoud|bytesPerCapture|1079902|1099586"` across
spec, nn, TesseractTests, Tesseract, docs and CLAUDE.md finds no test
comparing the spec's `tensorBytes` to Swift's `bytesPerCapture`.
`CaptureTensorTests` only PRINTS `data.count`, it never asserts it
against the ledger.

SKEPTIC VERDICT: NOT REFUTED, severity minor, two corrections to the
finder.

(a) The mutation as written yields 7508 / 1082212, NOT the finder's
claimed 7514 / 1082218. 7514 requires ceiling the root COUNT first then
multiplying by 13, which is Swift's shape, so the finder reported the
Swift figure rather than the command's output. They computed that line
rather than running it.

(b) `signBytesAt` is honestly named for what it computes. The defect is
`tensorBytes` and the printed "TOTAL" claiming to be the whole retained
capture.

Minor because no axiom flips at 13 B (verified: colourRatio 23.39 is
still above 20, depthShare 0.9689 is still above 0.95, tensor still far
under CubeStore), the Swift ledger is independently correct, and
SettingsView reads `CubeStore.bytesPerCapture` rather than the tensor's.
It is a blind ledger and a propagated documentation figure, not a wrong
byte on device.

## KILLED

Three findings were filed and destroyed by the skeptic. They are kept
because a killed finding is positive evidence that the axiom base is
sound at that point, and that is worth as much as a survivor.

### AD9-TREE-SHAPE-UNPINNED, killed (vacuous dimension)

FILED AS: `AdditiveLadder.hs:453` (axiom_AD9) claims per rung colour
budget and per rung energy budget are one object, but nothing ties
`levelEnergies` to PairTree's sibling maps, "and nothing can, because no
spec file imports another spec module".

KILLED BECAUSE: `spec/neural/WeaveState.hs:369` (axiom_WS4) does exactly
that and needs no import. It re-derives `prefixE k` inside its own file
as the MSB truncation `(i shiftR (8 - k))` and asserts
`sum(levels 0..1) == prefixE 2` and `sum(levels 0..4) == prefixE 5`,
plus monotonicity. The skeptic applied the finder's EXACT `splitNode`
mutation to WeaveState.hs: WS4 went red while WS1 to WS3 and WS5 to WS10
stayed green. WeaveState.hs is in the Makefile at line 76 and in
`make test`.

Further: WS4's two cut points (level 2 and level 5) are precisely AD9's
stratum boundaries (widths 1 + 1 + 3 + 3, cuts at 1, 2, 5). Combined
with AD9's own `roleTermIsPhi` and TE4's total equals E, all FOUR
stratum energies are uniquely determined by properties actually proved
in the suite. AD9's own check line reads "(TE/WS4)", naming WS4 as where
the chain rule is grounded, which is the CITE-DO-NOT-RESTATE pattern
CLAUDE.md endorses. This is NOT the Quantize.metal failure mode: there
the rotation lived in the kernel, in a comment, and in NO axiom
anywhere; here the tree shape lives in an axiom that fails the moment
you change it.

Consequence was also thin: `TilingEnergy.levelEnergies` has no
application consumer, `stratumEnergies` has no Swift port, and all three
Haskell copies of `levelEnergies` are byte identical today
(md5 056a3fc3e719aa7963092b02d11057f0 each), so no drift has occurred.

WHAT SURVIVES, much smaller than what was filed: the correspondence is
proved ONCE, in the file holding the third copy of the function, and the
definition is copy pasted into AdditiveLadder.hs and TilingEntropy.hs,
so mutating the AL or TE copy alone is invisible to that file's own run.
That is duplication hygiene in a meter with no consumer, closable by one
WS4 style `prefixE` assertion inside AD9.

### F6, killed (chain dimension), and INVERTED

FILED AS: `docs/workflow-2026-08-15-bin-standard.md:296` claims the
triple (dE, dE_wall, dE_time) breaks a contested voxel tie with no
weights, and that "the pair is what makes it work, not either scalar".
The finder claimed the triple is really a pair and that E does no voxel
level work.

KILLED BECAUSE THE DIAGNOSIS IS BACKWARDS. `TilingEntropy.hs:180`
defines `spin i = i >= 128`, and both `wallCount` and `wallCountTime`
are built on `spin` alone, so E_wall and E_time read BIT 7 (role) ONLY.
The contested flips are the DL6 stage 1 half, which
`AdditiveLadder.hs:67` pins as `s16 = Stratum "rung16" 6 1 16 4`, that
is bit 6, the pair (a, a XOR 64). A bit 6 flip CANNOT move spin.
Measured on a 4 frame cube of TE's own probes through TE's own
`cubeValue`:

```
bit-6 flip t=1 c=2000  dE=-3.6468584568574443   dE_wall=0.0  dE_time=0.0
bit-6 flip t=2 c=3000  dE=-0.34620197302865563  dE_wall=0.0  dE_time=0.0
bit-6 flip t=3 c=77    dE= 0.2719167006762291   dE_wall=0.0  dE_time=0.0
bit-7 flip t=0 c=1000  dE=-1.453  dE_wall=-49.678  dE_time=-6.34e-3
```

On exactly the flips the doc claims the triple arbitrates, dE_wall and
dE_time are IDENTICALLY ZERO and dE is the only axis that moves. Holds
in shipped code too: `Tesseract/Meter/TilingEnergy.swift:199` is
`static func spin(_ i: UInt8) -> Bool { i >= 128 }`.

Three further failures. (a) "Zero bits of discrimination precisely where
the search converges" holds ONLY at an exactly uniform pooled histogram;
on the real probe cube (E = 11607.029) dE over the 128 candidate pairs
gives 208 distinct values out of 256 ordered. (b) The finder's own
degeneracy metric indicts its nominated rescue harder than its target:
`wallEnergy f = bonds * (1 - hBin w (bonds - w))` is a function of ONE
scalar count over 8064 bonds, so per flip dE_wall admits at most 9
distinct values against E's 208. (c) The ulp argument attacks a phrase
the source defines figuratively: `MerkleSearch.hs:78` fixes "rounding
error" as "under 1% of range".

RESIDUE, doc scoped: line 296 IS unsound, but in the OPPOSITE direction.
The triple collapses to a single scalar on bit 6 flips, so "the pair is
what makes it work, not either scalar" is false there, and the E_wall
rescue the doc leans on (1573.06 against 0.26) is unavailable at bit 6.
No shipped byte or axiom rests on it; the search is a proposal and
ANELoop is gated behind `CameraConfig.phaseChaosLoop`.

### F7, killed (chain dimension)

FILED AS: `docs/workflow-2026-08-15-bin-standard.md:261`, "AND IT COSTS
ZERO BYTES ... the posterior is not data", alleged to be false because
retention is lossy.

KILLED BY A GATE THAT ALREADY EXISTS.
`TesseractTests/CubeStoreTests.swift:130`
`testIdentityReweaveReproducesTheIndicesAndTables` asserts that
re-weaving from the RETAINED cube yields byte identical indexFrames AND
tables, with line 152 `testCR3FailsLoudlyIfTheCubeIsPerturbed` as its
anti vacuity companion. It passes because the shipped retention is
exact, not lossy: `DyadPipeline.swift:317` runs `srgb8(from:)` as the
FIRST act on the cube, so every downstream stage is a function of 8 bit
samples, CubeStore stores exactly those 8 bits, and
`to8(Float(b)/255) == b` for every b. Drift is ZERO, which is the break
test's own s = 0.0 row printing 0.0 disagreement. The break test
contains its own refutation.

The finder anchored on CaptureTensor's CT11 rmse 0.0060. CaptureTensor
and TensorANE have ZERO call sites anywhere in Tesseract/ outside each
other; CLAUDE.md:665 says the call site swap "was staged behind CR3".
That rmse governs no shipped byte.

The remedy sentence was a direct misread. CLAUDE.md:694-697 says the
export TRANSIENTLY holds about 17 MB of staged OKLab that dies when the
closure returns, nine times the retained cube. `stagedField` is a pure
function of the 8 bit samples, so it is recomputable and need not be
retained. CubeStore.swift's header names the closure death as the defect
CR1 CLOSED; the finder quoted the pre-CR1 defect statement as current
state.

Two supporting numbers were selectively read: `nn/descent/train.py:357`
median_error 9.025e-4 is the median margin of the 485 probes the net got
WRONG (the low tail by construction), while the population median is
4.16e-3; and 12.6% (one algorithm, two fields) versus 3.48% (two
algorithms, one field) are different quantities.

The finder also inverted the code: `rebuildTables` selects
`PairTree.table` versus `DyadPalette.table` from `isV3` read off the
TRACE HEADER STRING, not from `CameraConfig.pairTree`, so the rebuild is
a pure function of traced bytes, the opposite of the alleged impurity.

RESIDUE, informational: if the CaptureTensor call site swap lands,
retention becomes lossy and CR3's identity reweave test would fail
LOUDLY rather than silently. That is CT11 working as written.

## PROCESS NOTE

The shared scratchpad is written concurrently by more than one session.
One skeptic's first `AdditiveLadder.hs` copy was overwritten mid test by
another agent's file carrying a different mutation. Anyone re-running a
break test in a bare scratchpad directory should namespace it first.
