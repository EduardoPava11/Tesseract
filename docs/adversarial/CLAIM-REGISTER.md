# CLAIM REGISTER

Every major claim examined in the adversarial run of 2026-08-15, broken
and clean alike. A register that lists only failures is not a register.

STATUS is exactly one of:

* PROVEN, a gate exists, it quantifies over the thing the claim is about,
  and it fails when the claim is mutated.
* VACUOUS, a gate exists and cannot fail. It quantifies over its own
  restated literals, or it compares a term to itself.
* UNGATED, nothing checks it. Correct by inspection still counts as
  UNGATED. This is the standing rule of this directory.
* DIVERGENT, two or more implementations of the same law disagree, and
  the disagreement was measured.
* UNKNOWN, not settled in this pass, with the reason recorded.

Tally: PROVEN 28, UNGATED 9, DIVERGENT 7, VACUOUS 4, UNKNOWN 3.
51 rows.

## Ports and engines

| CLAIM | WHERE STATED | WHAT GATES IT | GATE IS SUFFICIENT? | STATUS |
|:--|:--|:--|:--|:--|
| aerialPreview is "the 20 Hz GPU twin of DyadPipeline.Live.assign" | Quantize.metal:6 | ★ AerialParityTests (NEW): a real dispatch against Live.assign, 4096 of 4096 exact, plus a degeneracy gate and its anti-vacuity companion | YES | PROVEN, was UNGATED |
| "Haskell is authoritative; Swift/Metal are ports" for the argmin target | CLAUDE.md:410 | ★ DY17 (NEW 2026-08-16) pins the argmin to the CONTINUOUS staged value, and its second conjunct proves the round-tripped search is a genuinely different function | YES, now. The gap was that DY10/DY11/DY12 never said WHICH staged value the argmin reads, so a port could pick either and pass | PROVEN, was DIVERGENT |
| stagedField is "the DY12 construction, export and preview call this, there is no second staging" | DyadPipeline.swift:196-199 | DY12 governs TABLE CONSTRUCTION and does round-trip; DY17 governs ASSIGNMENT and does not. Both call sites now use stagedFieldLab for the argmin | YES. There really are two staged values, by design, and the defect was using one for both | PROVEN, was DIVERGENT |
| The kernel applies "the DY12 byte round-trip the CPU reference applies" | Quantize.metal:83-84 | AerialParityTests, strict, 4096 of 4096 with no tolerance | YES. The kernel round-trips the INPUT and stages in float, which is exactly aerialPrimary. It was RIGHT all along and the Swift was wrong | PROVEN, was DIVERGENT |
| sigma routing polarity, Metal complement of pairDitherFrame complement of assignRoles | Quantize.metal:112-113, DyadPipeline.swift:650, 842 | inspection only, three inversions compose to identity | NO dispatch test exists | UNGATED, correct by inspection |
| The solid face mask needs no Metal representation | Quantize.metal, coverageFloor = 1/32 | inspection only, smallest Bayer threshold is exactly 1/32 so th < t is unsatisfiable | NO dispatch test exists | UNGATED, correct by construction |
| BLEED reaches the GPU as a hard MAP collapse | AerialParamsSwift.flags.w | testBleedAndPhaseReachTheMetalState | PARTIAL, pins the non-degenerate case only | UNGATED for the degenerate case |
| PAIR TREE P2 prefix law holds on the sigma side | Quantize.metal:143-150 vs DyadPipeline.swift:654-662 | inspection only, including the strict tie rule | NO dispatch test exists | UNGATED, correct by inspection |
| downsampleRGB and downsampleDepth agree CPU to GPU | MetalGeometryParityTests | coordinate painted source texels, exact, all 4096 pixels, both streams | YES | PROVEN |
| ANELoop.metal agrees with its CPU twin | ANELoopSIMTParityTests | real dispatch, 100.00% agreement | YES | PROVEN |
| DyadANE is a gated twin | DyadANEParityTests:105 | gates against assignRoles, the free argmin the export replaced with StrataDescent | NO, it is a faithful twin of a law nothing runs | UNGATED |
| SKGene loads three MLModels | SKGene.swift:140-158 | exposes only isGroundAvailable, isPasserAvailable, isCodecAvailable, no prediction( call in the file | NO | UNGATED |

## Numbers and ledgers

| CLAIM | WHERE STATED | WHAT GATES IT | GATE IS SUFFICIENT? | STATUS |
|:--|:--|:--|:--|:--|
| build_model.py is the reference the CPU law is gated against | CLAUDE.md, CaptureTensor.swift header | CaptureTensorTests.swift:145-146 asserts only 0 < loud < 12288 | NO, passes for every published fraction | DIVERGENT, 0.24862 vs 0.15576 on identical input |
| derived_threshold is the mixture crossover | build_model.py:212, log((1-w)/w) | nothing | NO | DIVERGENT, sign inverted vs DepthMixture.hs:182; density ratio 29.40 not 1.0 at the Python point |
| colourRatio > 20 for the retained tensor | TensorEncoder.hs TA9 | TA9, over its own hardcoded 0.047 | NO, false at the measured loud fractions (18.15 and 14.67) | VACUOUS |
| Retained tensor TOTAL is 1079902 B | TensorEncoder.hs tensorBytes, signBytesAt:178-180 | nothing compares it to CaptureTensor.bytesPerCapture | NO | DIVERGENT, 9 B per loud root vs the shipped 13 B |
| "The DECODER recomputes g from stored parents" | TensorEncoder.hs TA6 | TA6 body is and [ signBit r == signBit r' \| (r, r') <- zip rs rs ] | NO, zip rs rs pairs a list with itself | VACUOUS |
| Noise floor ruling table, noiseless vs noisy | CLAUDE.md:276, citing noise_floor.py | the script itself | NO, noise_floor.py:89 passes reference(cube)[3] (g32 alone) not dev16_of(g32, g64), and prints the reverse verdicts | DIVERGENT |
| CaptureTensor capture is 1,099,586 B | CLAUDE.md, CaptureTensorTests | reproduced exactly, and 16 + 1048576 + 24576 + 1536 + 1914*13 confirms it to the byte | YES | PROVEN |
| CubeStore capture is 1,835,024 B | CaptureTensorTests.swift:186 | XCTAssertEqual(16 + 64*4096*3 + 64*4096*4, 1_835_024) | YES | PROVEN |
| FunnelLedger ratios: 144, 3, 5.3899, product 2328.444115; 109.4699, 0.1462, product exactly 16.000000; depth 16 x 32 = 512 | CLAUDE.md:729-731, docs/session-2026-08-15-funnel.md | FunnelLedgerTests, each ratio computed, telescoping is a real product versus endpoint comparison | YES | PROVEN |
| Authoring gate 98.30%, worst residual 4.853e-4 against the 4.883e-4 fp16 ulp | TensorEncoder | reproduced off the committed mlpackage (98.3028%, 4.853e-04) | YES | PROVEN |
| TensorANE parity 97.14% | TensorANEParityTests | that suite was not run in this pass | NOT ASSESSED | UNKNOWN |
| DL7 scores 0.8601 / 0.9652, an 8x margin (6.343e-4 / 7.605e-5 = 8.34) | nn/descent/results.json, RESULTS.md, CLAUDE.md:309-310, two docs | consistent across five artifacts; train.py seeds twice and splits by corpus seed | PARTIAL, train.py was not re-run because it rewrites read only artifacts | UNKNOWN |
| TilingEntropy probe table: balanced 0.0, random 194.94, face 4182.21, three region 17910.68, neel 28672.0, solid 32768.0, ceiling 31922.0109 | TilingEntropy.hs | TE1 to TE15, and the table is computed, not a putStrLn literal | YES | PROVEN |
| MerkleSearch's restated (E, E_wall) probe pairs are correct | MerkleSearch.hs:50-60 | all six recomputed from TilingEntropy's own energy and wallEnergy, all match | YES for the values, the 2026-08-15 correction landed | PROVEN |
| MT7 and MT8 quantify over the probes list, not over TilingEntropy | MerkleSearch.hs, disclosed in its own header | nothing, and no import is possible | NO, but it is disclosed, not hidden | UNGATED |

## Axioms and the spec suite

| CLAIM | WHERE STATED | WHAT GATES IT | GATE IS SUFFICIENT? | STATUS |
|:--|:--|:--|:--|:--|
| "The levels are the artifact's, not the model's ... nothing here is a hyperparameter" | ColourLatent.hs:424-429, axiom_CL7 | CL7 itself: levels == [4, 32, 256] where levels = [4, 32, 256] | NO, it is x == x plus closed arithmetic | VACUOUS, certifies [9, 77, 1000] |
| Ruling R-D: the model's internal ladder 64 to 16 to 4 "is CL7's strata [256, 32, 4], both forced" | CLAUDE.md ruling R-D | nothing | NO, and the two ladders differ: ratio 4 versus ratio 8, only the trailing 4 coincides | UNGATED |
| AD9 energy alignment, per rung colour budget and per rung energy budget are one object | AdditiveLadder.hs:453 | WeaveState.hs:369 axiom_WS4 re-derives prefixE by MSB truncation and asserts the same two cut points | YES, the finder's splitNode mutation turns WS4 red | PROVEN |
| TE4 level energies are stratified by the palette's own tree | TilingEntropy.hs:437 | TilingEnergyTests.swift:172-178 pins all eight levelEnergies for faceFrame(7) exactly | YES on the Swift side | PROVEN |
| TE1 surjection count | TilingEntropy.hs | inclusion exclusion cross checked against an independent stirling2 recurrence at six small (n, k) pairs | YES, derivation versus derivation | PROVEN |
| TE11 wallCountFast == wallCount | TilingEntropy.hs | six structurally different frames, wall counts 0 / 8064 / 1984 / 4005 / 3048 | YES, a transposed or off by one count moves at least one | PROVEN |
| TE12 rotation fixes the temporal wall count exactly | TilingEntropy.hs | integer equality on w_t | YES on w_t; the cE and cWall halves are invariant under ANY frame permutation, which TE13 states itself | PROVEN |
| CL4 and CL5 group structure | ColourLatent.hs | computed over all 256 masks against the actual decoded table | YES | PROVEN |
| CL6 mean step over variance step is monotone and crosses 1 | ColourLatent.hs | six covariance scales through the real decoder, no threshold, no restated number | YES, fails if the decoder's nonlinearity is removed | PROVEN |
| AD7 seventeen tile patterns are nested | AdditiveLadder.hs | computed from bayerOrder, monotonicity over k rather than a pinned count | YES | PROVEN |
| CT4, CT5, CT9, CT11 | spec/output/CaptureTensor.hs | quantify over all 256 sign patterns and over the real expand function; CT5's drift identity fails if expand stops being mirror symmetric | YES | PROVEN |
| The spec harness fails a file on nonzero exit or any cross glyph | spec/Makefile | both spellings in use are the same codepoint U+2717 | YES, nothing escapes by spelling | PROVEN |
| No spec file imports any other spec module | whole suite | grep over every import line | YES, this is an architectural fact and the root cause of the restated constant family | PROVEN |
| AD2 and AD5 clauses such as classAt s64 i == i | AdditiveLadder.hs | reduce to i shiftR 0 == i, and to i div 8 == j div 8 given i div 8 == j div 8 | NO | VACUOUS, harmless, they pin definitions nothing else could contradict and no port depends on them |
| AL9 SIMT identity | spec | exact Rational arithmetic against a recomputing sweep, three seeds, three sweep counts | YES, it genuinely constrains the kernel | PROVEN |
| DL2, PT7, PT9 | spec | DL2 over actual descent outputs on actual probes; PT7 closes the law of total variance to 1e-12; PT9 checks depth 4 node mean equals the octet mean | YES, none are relabelling invariant | PROVEN |
| MT2 and MT3 canonical quotient | MerkleSearch.hs | 256 raw relabelings produce more than one distinct hash and exactly one canonical hash | YES | PROVEN |
| CS1 to CS4 arithmetic, cells x bits = 262144 at each rung, AD4's 1024 invariant | spec section 4 | checked | YES | PROVEN |
| PT5 monotonicity on the analytic tree | spec | measured 0 failures at every level over 900 to 1200 probes for PCA eigenvalue ratio up to 3:1; breaks at 4:1 and above | PARTIAL, regime bounded rather than settled | UNKNOWN |

## Retention, energy and the workflow docs

| CLAIM | WHERE STATED | WHAT GATES IT | GATE IS SUFFICIENT? | STATUS |
|:--|:--|:--|:--|:--|
| The posterior costs zero bytes, the table half | docs/workflow-2026-08-15-bin-standard.md:261 | DyadPipeline.solveFrame:594 builds the tree from warm stats, the trace records them, GIFMachine.rebuildTables reconstructs from the TRACE HEADER STRING | YES, the palette really is a pure function of traced numbers | PROVEN |
| Retention is exact, identity reweave reproduces indices and tables | CubeStoreTests.swift:130 | plus :152 testCR3FailsLoudlyIfTheCubeIsPerturbed as the anti vacuity companion; DyadPipeline.swift:317 runs srgb8(from:) first so everything downstream is a function of 8 bit samples | YES, and drift is zero, not small | PROVEN |
| "The vector (dE, dE_wall, dE_time) breaks the tie with no weights at all. The pair is what makes it work, not either scalar" | docs/workflow-2026-08-15-bin-standard.md:296 | nothing | NO, and it is false in the opposite direction: E_wall and E_time read bit 7 only (spin i = i >= 128), so on the bit 6 contested flips dE_wall and dE_time are identically zero and dE does all the work alone | DIVERGENT, doc versus measurement |
| AdditiveCensus measures the output, not the process | docs, AD11 | AdditiveCensus.swift takes only indexFrames and side, no descent state | YES, the premise is true | PROVEN |
| A single index flip moves E far above floating point noise | this run's hypothesis | 1.4088e-3 bits against a Double ulp of 4.66e-10 at E's index ceiling, about 3 million ulps of headroom | YES | PROVEN, the C5 precision hypothesis is refuted |

## The engine (added 2026-08-16)

Verified by call site enumeration over every `static func` in the three
files that own a `.prediction(` call, discounting comments and
flag-gated dead branches.

| CLAIM | WHERE STATED | WHAT GATES IT | GATE IS SUFFICIENT? | STATUS |
|:--|:--|:--|:--|:--|
| "Assignment runs on the ANE (DyadAssign.mlpackage)" | CLAUDE.md, architecture | nothing; DyadANE has ZERO call sites for any static func, the only mention on a live path is `_ = DyadANE.isAvailable` at CameraManager.swift:245 | NO, and the claim is false today: 524 K ships and never predicts | UNGATED, and the prose is stale |
| ANELoop is "flag-gated behind CameraConfig.phaseChaosLoop" | CLAUDE.md | the flag is `false` at CameraManager.swift:115 and `chaosRefine` guards on it, so `ANELoop.refineFarBlocks` is unreachable; `ANELoop.localXYT` IS called from PhaseTiling but is a pure index helper with no model in it | YES, the flag claim is accurate; the 3.6 MB it gates is dormant, not broken | PROVEN, and dormant |
| TensorANE is "the engine TWIN" of CaptureTensor | CLAUDE.md; TensorANE.swift:26 | `TensorANE.transform` appears exactly once outside its own file, at CaptureTensor.swift:198, INSIDE A DOC COMMENT | NO, there is no call | UNGATED, and dormant behind the CR3 call-site swap |
| Three SKGene mlpackages are loaded and used | SKGene.swift:140-144 | the models' ONLY use is `!= nil` in `isGroundAvailable` / `isPasserAvailable` / `isCodecAvailable`, printed in a debug line at GIFMachine.swift:187. `SKGene.trace` is pure CPU 4-cubed mean pooling. No `.prediction(` exists in the file | NO. Three Core ML models are instantiated on every export so that three Bools can report they instantiated | VACUOUS at runtime, and a LINT-NO-STUB violation by the decree's own words: "a telemetry-only rung is a stub too" |
| "The ANE does almost nothing shipped" (G7) | session-2026-08-15-sunset.md | this enumeration | YES, and it is stronger than stated: 7 mlpackages, 4.4 MB bundled, and ZERO predictions execute on any live path | PROVEN |

★ THE RULING OWED. Three options and none is obviously right, which is
why none was taken here: WIRE the models (they were trained for a
reason and CameraConfig.skGenes is `true`), DELETE them and reclaim
4.4 MB of a camera app's bundle, or keep them and make the dormancy
VISIBLE rather than implied by prose that says assignment runs on the
ANE. What must not persist is the current state, where the bundle pays
for seven models, the export pays to load three of them, and the
architecture notes describe a machine that is not running.
