# ATLAS-TUNABLES — the customization surface

Generated from the 7-reader sweep (2026-08-13). Every frozen choice in the machine,
with its anchor and what a knob there would mean. `—` = deliberately not a knob.

**447 tunables across 101 stages.**


## ASSIGNING  ·  ANE · SOLVE

| what | where | current | knob |
|---|---|---|---|
| compute unit selection | `Tesseract/Tesseract/Tesseract/DyadANE.swift:30` | MLModelConfiguration.computeUnits = .all (scheduler picks ANE) | power/latency preference: .cpuAndNeuralEngine vs .all vs CPU-only |
| centering reference | `Tesseract/Tesseract/Tesseract/DyadANE.swift:85` | per-frame CENTROID = primaries[0] (argmin-invariant; buys ~10× fp16 resolution — measured 81%→98.8% agreement in the authoring script) | fixed conditioning law, not a knob |
| shape constants | `Tesseract/Tesseract/Tesseract/DyadANE.swift:22` | frameCount 64, pixelCount 4096, primaryCount 128 — fused into the mlpackage; any other capture shape gets nil | the 64³ pin propagated into a compiled graph; a resolution knob requires rebuilding the mlpackage |
| lawfulness gate (total function) | `Tesseract/Tesseract/Tesseract/DyadANE.swift:127` | reject whole capture (return nil → CPU) if any index breaks the role law | fixed safety; not user-facing |

## BENCHING  ·  ANE · LAW

| what | where | current | knob |
|---|---|---|---|
| budget tick constants | `docs/ane-loop-design.md:224` | 200 ms (5 Hz rung-16) and 50 ms (20 Hz polyphase) verdict windows | cadence targets — follow from TL8/TL9 clocks, not free |
| compute-unit sweep set | `TesseractTests/ANELoopBenchTests.swift:151` | {all, cpuAndNeuralEngine, cpuAndGPU, cpuOnly} + metal-simt | bench coverage only |

## CHURNING  ·  ANE · SOLVE

| what | where | current | knob |
|---|---|---|---|
| master flag | `Tesseract/Tesseract/Camera/CameraManager.swift:94` | CameraConfig.phaseChaosLoop = false (default OFF; internal by design — no settings surface without ruling) | THE candidate 'background texture: dithered vs solved' user toggle, pending device comparison |
| sweep count | `Tesseract/Tesseract/Tesseract/ANELoop.swift:37` | sweeps = 4 ('prototype K; A-series pin owed') | quality knob; AL4 monotonicity makes any K safe, so a slider is lawful |
| candidate count | `Tesseract/Tesseract/Tesseract/ANELoop.swift:36` | 8 = 2³ (one per sub-cell, combinatorial not tuned); candidates = block's top-8 occupied ground colors, ties→lowest (ANELoop.swift:290) | richer candidate sets change the search breadth |
| refine scope | `Tesseract/Tesseract/Tesseract/ANELoop.swift:284` | fully-far blocks only (every voxel pull ≥ coverageCeil AND index ≥128); coverageCeil = 31/32 = Bayer extremum (DyadPipeline.swift:79, derived) | extending to band or face blocks is design doc step 6 ('order' noise shaping) — a look-changing choice awaiting ruling |
| engine-vs-CPU route | `Tesseract/Tesseract/Tesseract/ANELoop.swift:351` | useANE=true default (ANELoop.swift:238) but only when blockCount==4096; ANE colors→indices via nearest-candidate recovery (ANELoop.swift:360); CPU twin otherwise | compute-unit preference |
| model compute units | `Tesseract/Tesseract/Tesseract/ANELoop.swift:119` | .all for both ANELoopModel and ANELoopK1Model | same knob as ASSIGNING |
| inert-block freezing | `Tesseract/Tesseract/Tesseract/ANELoop.swift:327` | y := q0 exactly (zero error rejects every exchange — no mask input needed by the graph) | structural trick, fixed |
| per-block centering on target mean | `Tesseract/Tesseract/Tesseract/ANELoop.swift:303` | always for live blocks (fp16 conditioning, the DyadAssign lesson) | fixed conditioning law |

## FUSING  ·  ANE · SOLVE

| what | where | current | knob |
|---|---|---|---|
| sweep count K baked into the graph | `nn/ane-loop/build_model.py:63` | argv, default 4 (compile-time; contrast SIMT runtime K) | quality-vs-speed of the chaos refine — device bench pins it; each K is a separate mlpackage |
| block geometry | `nn/ane-loop/build_model.py:57` | B=4096, V=64, C=8, SIDE=4 — the 4³ spacetime atom | pinned by AL2/AL8 (clock identity 20/5=4); not tunable without new spec |
| curvature | `nn/ane-loop/build_model.py:65` | 1 + 1/8 + 1/64 (AL7, reciprocal block volumes — derived, no naked constants) | none by decree |
| compute precision | `nn/ane-loop/build_model.py:192` | ct.precision.FLOAT16, ComputeUnit.ALL, iOS17 target (same at nn/dyad-assign/build_model.py:128) | fp32 variant would trade the ANE for accuracy |
| offset architecture = feed blocking only | `nn/ane-loop/build_model.py:158` | cube_to_blocks(t_off,y_off,x_off) — graph is phase-agnostic; aligned (0,0,0) is shipped semantics; options A–F in docs/ane-loop-design.md §5½, recommendation B+E (temporal polyphase + streaming warm starts → 20 Hz judgments at ~1 sweep/frame) | cadence/latency knob that never touches the model — a prime customization surface once ruled |
| DyadAssign parity thresholds | `nn/dyad-assign/build_model.py:201` | min_agree 0.985 (shells) / 0.95 (stress), tie gap ≤2e-3 at build_model.py:188 | gate strictness, lab-only |
| harness bleed constants | `nn/dyad-assign/build_model.py:101` | TAU=0.6, BLEED_W=0.15, BLEED_G=0.5 (test-feed staging only — the app derives these from the mixture) | lab fixture, not shipped |

## POOLING  ·  ANE · SENSE

| what | where | current | knob |
|---|---|---|---|
| universal RGB crop | `Tesseract/Tesseract/Camera/CameraManager.swift:61` | rgbCrop = 768, centered | zoom / framing knob — but ★NO-CROP-CHANGES decree requires device-verified readout dims |
| universal depth crop | `Tesseract/Tesseract/Camera/CameraManager.swift:62` | depthCrop = 256, centered | must track rgbCrop's field of view |
| grid side (the 64 of 64³) | `Tesseract/Tesseract/Camera/CameraManager.swift:73` | mode = .training → outputSize 64; PINNED (128³ switch removed after 2026-08-03 device crash — textures allocated once at 64, no reallocation path) | resolution knob is a full-pipeline reallocation project, not a constant flip |
| sampling kernel | `Tesseract/Tesseract/Metal/Quantize.metal:196` | single point sample at cell center (cropX + gid.y·step + halfStep) — nearest, no prefilter | RATE LADDER step S0 proposes a box prefilter to kill decimation aliasing; a 'sharp vs smooth capture' user knob lives exactly here |
| rotation baked into read | `Tesseract/Tesseract/Metal/Quantize.metal:197` | 90° CCW (portrait), fixed | orientation handling if landscape capture were ever allowed |
| threadgroup size | `Tesseract/Tesseract/Metal/MetalPipeline.swift:244` | 8×8×1 for the 64×64 grid | perf-only; not user-facing |
| no-depth-frame fill | `Tesseract/Tesseract/Metal/MetalPipeline.swift:291` | DepthSignal.fill = 0.5 neutral (never read stale depth64Texture) | policy for depth dropouts (freeze last vs neutral) could be exposed |
| clamp-to-origin for narrow buffers | `Tesseract/Tesseract/Metal/MetalPipeline.swift:441` | max(0, (width−crop)/2) — reads smaller region instead of trapping | robustness, fixed |

## PROVING  ·  ANE · LAW

| what | where | current | knob |
|---|---|---|---|
| parity gate | `nn/metal-harness/main.swift:3` | fp32 kernel ≤ 2e-3 max-abs vs golden | lab-only strictness |
| Metal compile flags | `nn/metal-harness/run.sh:13` | -O2 (note: bare metal CLI, not project.yml's MTL_FAST_MATH NO — the harness predates that decree) | should mirror the app's fast-math setting if the kernel ever ships |
| weight precision pair | `nn/metal-harness/gen_weights.py:33` | both FP32 and FP16 constant arrays emitted | fp16-only would halve the header |

## READING  ·  ANE · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| depth near anchor | `Tesseract/Tesseract/Camera/DepthSignal.swift:21` | dNear = 0.25 m | subject-distance calibration — a 'near plane' slider changes what counts as face-close |
| depth far anchor | `Tesseract/Tesseract/Camera/DepthSignal.swift:23` | dFar = 1.5 m | background cutoff distance — the single most user-meaningful depth knob |
| invalid-depth fill | `Tesseract/Tesseract/Camera/DepthSignal.swift:25` | fill = 0.5 (neutral mid-signal) | bias dropouts toward face or background |
| depth stored in rgba16Float R channel (4× memory), readback reads all 4 channels | `Tesseract/Tesseract/Metal/MetalPipeline.swift:399` | rgba16Float for both textures | perf-only (r16Float depth texture would quarter the readback) |

## SHADOWING  ·  ANE · SOLVE

| what | where | current | knob |
|---|---|---|---|
| GPU-vs-CPU preview assignment gate | `Tesseract/Tesseract/Camera/CameraManager.swift:761` | GPU only when gpuTexturesReady (depth present) and kernel compiled; else assignCPU | a battery/perf preference could force CPU or GPU |
| γ staging law | `Tesseract/Tesseract/Metal/Quantize.metal:88` | γ = 1/(2−s), fixed (DY9/DY10 — chroma buys the temporal octave) | a 'depth-color intensity' knob would reparameterize γ — needs a spec ruling (R6 γ-vs-chroma-gain slot is open) |
| coverage posterior | `Tesseract/Tesseract/Metal/Quantize.metal:94` | logistic 1/(1+exp((s−s*)/τ)) with s*,τ from the capture's own mixture fit (constant-free by decree); t=0 when single-phase | none — no naked thresholds; only the upstream mixture is the knob |
| σ-routing dither matrix | `Tesseract/Tesseract/Metal/Quantize.metal:53` | fixed Bayer 4×4 {0,8,2,10 / 12,4,14,6 / 3,11,1,9 / 15,7,13,5} | dither pattern choice (Bayer vs blue-noise vs error diffusion) — must change in lockstep with both CPU twins |
| chaos-blur block size (v7) | `Tesseract/Tesseract/Metal/Quantize.metal:109` | 4×4 spatial block mean in-kernel (rung 16, TL9 'resolution of depth') | background blur granularity — derived from the ladder, changing it breaks TL9 alignment |
| σ-side quantization level | `Tesseract/Tesseract/Metal/Quantize.metal:131` | nodeCount>0 → 32-level pair-tree (nearest of ≤16 depth-4 nodes, emit 255−canonicalLeaf); else 128-primary scan (fallback when pairTree off) | the PAIR TREE prefix law makes 'coarseness of the chaos' a level choice (4/32/256) |
| sRGB8 round-trip before OKLab | `Tesseract/Tesseract/Metal/Quantize.metal:84` | round(·255)/255 (DY12 byte round-trip parity with CPU) | fixed parity requirement |
| in-kernel depth fill | `Tesseract/Tesseract/Metal/Quantize.metal:79` | 0.5 (mirrors DepthSignal.fill; anchors passed via params so DepthSignal.swift stays single source) | tracks READING's fill |
| primaries/nodes buffer capacities | `Tesseract/Tesseract/Metal/MetalPipeline.swift:154` | 128 float4 primaries + 16 float4 nodes, storageModeShared | fixed to DYAD-256's 128/16 split |
| kernel optionality | `Tesseract/Tesseract/Metal/MetalPipeline.swift:100` | aerialPreview pipeline optional — absent kernel ⇒ CPU-only preview, app still works | graceful-degradation policy, fixed |

## STREAMING  ·  ANE · SOLVE

| what | where | current | knob |
|---|---|---|---|
| runtime sweep count | `Tesseract/Tesseract/Metal/ANELoop.metal:43` | sweeps buffer(3), any K ≥0 — one pipeline serves every sweep count; AL4 lets the CPU stop dispatching mid-budget lawfully | the live-loop quality/battery dial once B+E ships |
| curvature in-kernel | `Tesseract/Tesseract/Metal/ANELoop.metal:29` | kCurvature = 1 + 1/8 + 1/64 hardcoded as the derived constant (AL7) | none by decree |
| threadgroup width | `Tesseract/Tesseract/Tesseract/ANELoop.swift:211` | min(maxTotalThreadsPerThreadgroup, 64), 1-D over blockCount | perf-only; A19 occupancy tuning |
| fast-math | `project.yml:20` | MTL_FAST_MATH: NO project-wide — IEEE ops in program order, no reassociation, no fma contraction; the kernel mirrors sweepBlockCPU statement for statement | NOT a knob: the CPU/GPU parity contract depends on it |
| K1 streaming unit consumer | `Tesseract/Tesseract/Tesseract/ANELoop.swift:113` | bundled, loaded, unconsumed ('no runtime consumer until the device numbers pin the cadence') | wiring B+E = 20 Hz judgments; offset choice A–F is the open ruling (docs/ane-loop-design.md §5½) |
| synchronous dispatch | `Tesseract/Tesseract/Tesseract/ANELoop.swift:217` | waitUntilCompleted per call | async pipelining needed for the live 20 Hz loop |

## WRAPPING  ·  ANE · SENSE

| what | where | current | knob |
|---|---|---|---|
| default RGB pixel format for texture wrap | `Tesseract/Tesseract/Metal/MetalPipeline.swift:182` | .bgra8Unorm | alternate capture formats (wide-gamut, 10-bit) would need a knob here |
| depth format auto-detect fp16 vs fp32 | `Tesseract/Tesseract/Metal/MetalPipeline.swift:218` | DepthFloat16 → .r16Float else .r32Float | fixed policy; a precision preference could force fp32 depth |
| wrapper lifetime policy (hold until waitUntilCompleted) | `Tesseract/Tesseract/Metal/MetalPipeline.swift:210` | append to liveCVTextures, removeAll after wait | load-bearing correctness fix (2026-08-12 line pass); not user-facing |

## ATTIC:BELLING  ·  ATTIC · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| target model choice (typeclass with three instances) | `/Users/daniel/Tesseract/isp-spec/src/ISP/BinomialBeauty.hs:36` | FullCube B(4096,1/256), FingerprintBinomial B(256,1/64) (the null hypothesis), DyadicBell n (palindromic [1,1,2,4,...,2^n,2^n,...,4,2,1,1]) | the aesthetic target itself — 'how bell-shaped should color usage be' is a legitimate look knob |
| DyadicBell peak exponent | `/Users/daniel/Tesseract/isp-spec/src/ISP/BinomialBeauty.hs:49` | tests use n=5 (sum 128); n=6 gives the 256 ladder the live DYAD shells use | bell width/steepness |
| distance = EMD not KL (explicit rationale: KL explodes on empty bins) | `/Users/daniel/Tesseract/isp-spec/src/ISP/BinomialEMD.hs:8` | 1D Wasserstein via CDF differences | fixed by argument |
| Birkhoff regularizer floor on Complexity | `/Users/daniel/Tesseract/isp-spec/src/ISP/BirkhoffBinomial.hs:61` | M = O / max(C, 1e-6), callers warned to cap | fixed guard |
| rebinning of observed histogram to model bin count (mass-preserving piecewise-constant) | `/Users/daniel/Tesseract/isp-spec/src/ISP/FingerprintHistogram.hs:50` | rebinToLength | fixed |

## ATTIC:CLOCKING  ·  ATTIC · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| estimator variant (the ONE user-selectable statistical tool in this spec) | `/Users/daniel/Tesseract/isp-spec/src/ISP/Time.hs:15` | PoissonInterarrival (T = tExp/N) default; EffectiveIntegration phiRef and HeisenbergPrecision available | a literal 'time-axis flavor' picker — three physically-distinct T semantics already implemented |
| reference flux phiRef for EffectiveIntegration | `/Users/daniel/Tesseract/isp-spec/src/ISP/Time.hs:18` | caller-supplied, no default | calibration slider |
| photon-count floor in the Heisenberg clamp | `/Users/daniel/Tesseract/isp-spec/src/ISP/Time.hs:46` | max 1 nHat | fixed guard; not user-facing |

## ATTIC:COMPOSING  ·  ATTIC · WEAVE

| what | where | current | knob |
|---|---|---|---|
| level weight profile — the direct 'how much of each octave' mixer | `/Users/daniel/Tesseract/isp-spec/src/ISP/Compose.hs:24` | flatWeights (1/7 each) and laplacianWeights (2^-/k-4/, peaked at L4) both defined; choice is caller's | a 7-band scale equalizer: boosting L1 = more dither texture, boosting L6 = more posterized; the cleanest existing surface for teaching coarse-mean vs fine-dither |
| pyramid center level of laplacianWeights | `/Users/daniel/Tesseract/isp-spec/src/ISP/Compose.hs:31` | k=4 (64x64 output resolution) | focus-scale knob |
| output resolution | `/Users/daniel/Tesseract/isp-spec/src/ISP/Compose.hs:45` | 64x64 hard-coded | pinned by the 64-cubed decree |
| resampling kernels | `/Users/daniel/Tesseract/isp-spec/src/ISP/Compose.hs:55` | block mean down / nearest-neighbor up | up-sampler choice (nearest keeps the cell look; bilinear would smear — live contract demands replication) |
| snap is hard nearest-neighbor (comment: STE in a learned setup) | `/Users/daniel/Tesseract/isp-spec/src/ISP/Compose.hs:86` | argmin deltaE, non-differentiable | soft-assignment temperature if ever trained through |

## ATTIC:DITHERING  ·  ATTIC · SOLVE

| what | where | current | knob |
|---|---|---|---|
| matrix order choice: bayer2 / bayer4 / bayer8 all defined; every pipeline caller uses bayer2 | `/Users/daniel/Tesseract/isp-spec/src/ISP/Bayer/Dither.hs:37` | bayer2 (4 threshold levels) | dither-grain-size knob — 2/4/8 px pattern period, directly the texture-visibility regimes in the dyad256 research doc section 4 |
| half-step offset keeping thresholds off 0 and 1 | `/Users/daniel/Tesseract/isp-spec/src/ISP/Bayer/Dither.hs:34` | (x+0.5)/n^2 | fixed |
| dither operates on L channel ONLY (chroma discarded at the binary level) | `/Users/daniel/Tesseract/isp-spec/src/ISP/Bayer/Dither.hs:91` | planeMap okL | channel selection / per-axis dithering (a,b dither would give chromatic halftone) |
| matrix applied at the DOWNSAMPLED resolution (adjacent blocks see adjacent entries) | `/Users/daniel/Tesseract/isp-spec/src/ISP/Bayer/Dither.hs:86` | threshold after pool | pool-then-dither vs dither-then-pool order is exactly the coarse/fine octave contract to teach |
| binary lift endpoints | `/Users/daniel/Tesseract/isp-spec/src/ISP/Bayer/Dither.hs:99` | False->Oklab 0 0 0, True->Oklab 1 0 0 | duotone ink colors — an obvious look knob |

## ATTIC:DOUBLING  ·  ATTIC · SOLVE

| what | where | current | knob |
|---|---|---|---|
| operator choice — the deliberately DEFERRED decision of this spec (benchmark against Birkhoff beauty before pinning) | `/Users/daniel/Tesseract/isp-spec/src/ISP/ColorDouble.hs:7` | three instances shipped: KMeansSplit (data 2-means), PCASplit (mean +/- sqrt(lambda)*PC1 — the ancestor of the live analytic tree's eigen-split), CatCoproduct (fixed L +/- epsilon, categorical baseline); all Laws/Fingerprint tests run CatCoproduct | split-style picker: 'adaptive' vs 'principal' vs 'pure geometric' color growth |
| KMeans seed perturbation along L | `/Users/daniel/Tesseract/isp-spec/src/ISP/ColorDouble/KMeans.hs:41` | +/- 0.02 L | split-contrast floor |
| KMeansSplit iteration budget (constructor arg) | `/Users/daniel/Tesseract/isp-spec/src/ISP/ColorDouble/KMeans.hs:16` | callers pass 4 or 8 | quality dial |
| PCA power-iteration steps | `/Users/daniel/Tesseract/isp-spec/src/ISP/ColorDouble/PCA.hs:89` | 20 fixed | fixed |
| PCA child offset = sigma = sqrt(top eigenvalue), full 3D eigenvector | `/Users/daniel/Tesseract/isp-spec/src/ISP/ColorDouble/PCA.hs:35` | mean +/- sigma*v | offset multiplier (contrast of each doubling); compare live PT7-PT9 half-normal moments sqrt(2/pi)*sqrt(lambda) |
| coproduct epsilon | `/Users/daniel/Tesseract/isp-spec/src/ISP/ColorDouble/Coproduct.hs:25` | 0.02 along L | geometric-split spacing |

## ATTIC:FINGERPRINTING  ·  ATTIC · SOLVE

| what | where | current | knob |
|---|---|---|---|
| input resolution assumption | `/Users/daniel/Tesseract/isp-spec/src/ISP/Fingerprint.hs:49` | 1024x1024 hard-shaped (7 levels) | ladder depth = number of octaves |
| L1 bootstrap palette (binary black/white) | `/Users/daniel/Tesseract/isp-spec/src/ISP/Fingerprint.hs:104` | [Oklab 0 0 0, Oklab 1 0 0] | duotone seed colors — the whole doubling cascade inherits these two roots |
| fingerprint terminal level | `/Users/daniel/Tesseract/isp-spec/src/ISP/Fingerprint.hs:75` | L6 = 16x16 cells x 64 colors | descriptor granularity |
| reference planes = pure mean-pool chain of L0 (not the quantized previous level) | `/Users/daniel/Tesseract/isp-spec/src/ISP/Fingerprint.hs:58` | downsampleMean2Oklab chain | closed-loop (quantize-then-pool) vs open-loop (pool raw) pyramid — a structural knob relevant to teaching the octave relation |

## ATTIC:GLOBALWEAVE  ·  ATTIC · WEAVE

| what | where | current | knob |
|---|---|---|---|
| T dropped silently when projecting palette to RGB bytes | `/Users/daniel/Tesseract/isp-spec/src/ISP/GIF.hs:32` | only R,G,B emitted | T could instead modulate frame ordering or per-frame palettes (which is what the live DYAD-256 per-frame-LCT decree eventually did) |
| looping mode | `/Users/daniel/Tesseract/isp-spec/src/ISP/GIF.hs:69` | LoopingForever | loop-count/ping-pong option |
| minimum per-frame delay | `/Users/daniel/Tesseract/isp-spec/src/ISP/GIF.hs:55` | totalCs = max k (round(totalSec*100)) => every delay >= 1 cs | GIF-tick floor; live app pinned exactly 5 cs / 20 fps instead of physical deltaT |
| delays derived from PHYSICAL inter-capture time (feedback_temporal_interpolation lineage) | `/Users/daniel/Tesseract/isp-spec/src/ISP/GIF.hs:51` | sum of delays == deltaT | real-time vs fixed-rate playback toggle |

## ATTIC:MIRRORLAW  ·  ATTIC · LAW

| what | where | current | knob |
|---|---|---|---|
| the octave constant 2 in gamma(s)=1/(2-s) | `/Users/daniel/Tesseract/docs/depth-color-scales.md:44` | 2 = the shipped cadence octave (derived, not free) | generalizing the ratio (3:1, 8:1 spacetime) is precisely the 2x2x2<->1 teaching direction |
| sigma_base(K) = (K-1)/8 | `/Users/daniel/Tesseract/docs/depth-color-scales.md:18` | (K-1)/8 across K in {64,32,16} | cadence-depth coupling strength |
| R4 aesthetic fork on the far side | `/Users/daniel/Tesseract/docs/depth-color-scales.md:65` | comp-halo shipped default vs faithful-hue (DY11 measured faithful aggregate-closer); superseded by the v7 same-hue ruling per memory | a one-line style fork explicitly designed to be ruled, never an in-app A/B |
| PerfectQuantizer naked constants flagged as debt (R5) | `/Users/daniel/Tesseract/docs/depth-color-scales.md:29` | 0.7 diffusion, +/-0.2 clamp, 0.6/0.4 zones — since deleted with the global-table path | moot |

## ATTIC:PHOTONING  ·  ATTIC · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| wavelength anchors per channel | `/Users/daniel/Tesseract/isp-spec/src/ISP/Sensor/Physics.hs:35` | R=640nm, Gr=Gb=546nm, B=427nm | per-device CFA calibration; these three numbers set every Heisenberg floor and photon energy |
| FWHM per channel | `/Users/daniel/Tesseract/isp-spec/src/ISP/Sensor/Physics.hs:44` | 55/66/76 nm | spectral-width model (currently unused downstream — pure reference) |
| peak transmission per channel | `/Users/daniel/Tesseract/isp-spec/src/ISP/Sensor/Physics.hs:50` | 0.75/0.82/0.88 | QE calibration (also unused downstream) |
| Anscombe offset constant | `/Users/daniel/Tesseract/isp-spec/src/ISP/Sensor/Anscombe.hs:12` | 3/8 | fixed by theory — expose only as an 'exact vs generalized' transform choice (anscombe vs anscombeG) |
| Noise model Var = alpha*mean + beta (DNG NoiseProfile shape) | `/Users/daniel/Tesseract/isp-spec/src/ISP/Sensor/Noise.hs:20` | linear Poisson+Gaussian | noise-character preset (clean/filmic) by scaling alpha,beta |

## ATTIC:PINNING  ·  ATTIC · LAW

| what | where | current | knob |
|---|---|---|---|
| QuickCheck iteration budget | `/Users/daniel/Tesseract/isp-spec/test/Spec.hs:44` | maxSuccess=100 globally; withMaxSuccess 1-3 on 1024^2 pyramid properties | CI thoroughness |
| golden Heisenberg sample points | `/Users/daniel/Tesseract/isp-spec/golden/Main.hs:55` | N = 1e4 and 1e6 | fixed |

## ATTIC:PROJECTING  ·  ATTIC · SOLVE

| what | where | current | knob |
|---|---|---|---|
| Gr/Gb combiner: equal-weight mean (comment admits variance-weighted alternative) | `/Users/daniel/Tesseract/isp-spec/src/ISP/Tesseract.hs:32` | (Gr+Gb)/2 equal weights | inverse-variance-weighted G, or keep Gr/Gb split as a 5-channel art mode |

## ATTIC:PYRAMIDING  ·  ATTIC · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| conserved product | `/Users/daniel/Tesseract/isp-spec/src/ISP/Pyramid.hs:45` | 4096 | quality budget: a single 'total information' dial; live spec/ evolved this into RateLadder's telescoping 8:1 strata |
| level table (8 discrete S,K pairs) | `/Users/daniel/Tesseract/isp-spec/src/ISP/Pyramid.hs:24` | S halves L1->L8 while K doubles | expose pickByTargetK as a 'frames vs resolution' slider |
| minimum GIF tick used by pickByDeltaT | `/Users/daniel/Tesseract/isp-spec/src/ISP/Pyramid.hs:56` | caller-supplied, typically 0.01 s | playback-speed floor |

## ATTIC:QUADDING  ·  ATTIC · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| CFAPattern enum (RGGB/BGGR/GRBG/GBRG) — modeled but every caller uses RGGB | `/Users/daniel/Tesseract/isp-spec/src/ISP/Bayer.hs:27` | RGGB everywhere | sensor-mount orientation; V4 flips could expose a mirror/rotate capture toggle |
| V4 symmetry applied nowhere in the pipeline (applyV4 is spec-only algebra) | `/Users/daniel/Tesseract/isp-spec/src/ISP/Bayer.hs:70` | unused in runPipeline | flip/rotate augmentation knob for any future training or preview mirroring |

## ATTIC:QUANTIZING  ·  ATTIC · SOLVE

| what | where | current | knob |
|---|---|---|---|
| distance metric: Euclidean in raw 4D channel space, T weighted equally with R,G,B | `/Users/daniel/Tesseract/isp-spec/src/ISP/Palette.hs:26` | dist4 unweighted; module header defers OkLab+scaled-T to a future revision | a T-weight slider (how much time separates colors) and an OKLab toggle — both explicitly anticipated |
| palette size cap | `/Users/daniel/Tesseract/isp-spec/src/ISP/Pipeline.hs:66` | min 256 nPts | color-count knob (live app pinned 256 per frame instead) |
| k-means iteration budget | `/Users/daniel/Tesseract/isp-spec/src/ISP/Pipeline.hs:47` | cfgKMeansIter = 16 | quality/speed dial |
| convergence epsilon | `/Users/daniel/Tesseract/isp-spec/src/ISP/Palette.hs:72` | 1e-6 | fixed |
| PaletteMethod enum (MedianCut4D declared, never implemented) | `/Users/daniel/Tesseract/isp-spec/src/ISP/Palette.hs:18` | KMeans4D only | quantizer-algorithm choice slot |
| deterministic strided seeding | `/Users/daniel/Tesseract/isp-spec/src/ISP/Pipeline.hs:67` | seeds = points at i*n/k | seed strategy (kmeans++ etc.) |

## ATTIC:READING  ·  ATTIC · SENSE

| what | where | current | knob |
|---|---|---|---|
| CFA pattern hard-pinned to RGGB regardless of file contents | `/Users/daniel/Tesseract/isp-spec/src/ISP/DNG.hs:138` | RGGB | sensor-orientation / pattern picker if a raw path ever returns |
| exposure time default (tag not parsed) | `/Users/daniel/Tesseract/isp-spec/src/ISP/DNG.hs:142` | 1/120 s | shutter-speed knob feeding the T-axis |
| ISO default | `/Users/daniel/Tesseract/isp-spec/src/ISP/DNG.hs:143` | 100 | gain knob |
| noise profile default for all four channels | `/Users/daniel/Tesseract/isp-spec/src/ISP/DNG.hs:144` | NoiseProfile alpha=1.0 beta=16.0 | per-device calibrated noise; a 'grain' slider maps naturally onto alpha/beta |
| analog gain default | `/Users/daniel/Tesseract/isp-spec/src/ISP/DNG.hs:149` | 1.0 e-/DN | sensor calibration entry |
| synthetic-fixture sensor meta (black 512, white 65535, exposure 1/120, ISO 100) | `/Users/daniel/Tesseract/isp-spec/src/ISP/DNG.hs:62` | defaultSensorMeta | test-scene generator presets |

## ATTIC:RESEARCHING  ·  ATTIC · LAW

| what | where | current | knob |
|---|---|---|---|
| JND spacing floor for palette entries | `/Users/daniel/Tesseract/docs/dyad256-color-research-2026-08-11.md:37` | delta >= 0.02 dE_OK (0.004 for side-by-side dither pairs) | diversity-floor strictness |
| natural axis-variance prior for bit allocation | `/Users/daniel/Tesseract/docs/dyad256-color-research-2026-08-11.md:23` | sigma_L : sigma_by : sigma_rg = 47:10:1 (Ruderman) | blend weight between natural prior and measured per-capture sigma |
| beauty acceptance temperature | `/Users/daniel/Tesseract/docs/dyad256-color-research-2026-08-11.md:59` | softmax(beta * H_SY), beta open | an explicit 'taste temperature' knob |
| dyad contrast reward zones | `/Users/daniel/Tesseract/docs/dyad256-color-research-2026-08-11.md:41` | dL* >= ~15, Lsum >= ~134 (Ou-Luo tanh midpoints) | contrast preset (derived, not naked, per decree) |
| viewing-geometry anchor for all dither regimes | `/Users/daniel/Tesseract/docs/dyad256-color-research-2026-08-11.md:79` | 94.8 px/deg (460 ppi at 300 mm) | viewing-distance setting reshapes fusion/texture/induction bands |
| ground-register corrections replacing exact negation | `/Users/daniel/Tesseract/docs/dyad256-color-research-2026-08-11.md:39` | partial hue rotation toward blue-yellow axis + L-contrast involution + Goethe 9:8:6:6:4:3 muting | each is a candidate style dimension if ever ruled in |

## ATTIC:SAMPLING  ·  ATTIC · SOLVE

| what | where | current | knob |
|---|---|---|---|
| the whole explicit config record — the spec's own customization surface | `/Users/daniel/Tesseract/isp-spec/src/ISP/Pipeline.hs:42` | defaultConfig = PoissonInterarrival, L6, KMeans4D, BinQuad, 16 k-means iters, whiteLevelNorm=True | this IS the ancestor settings panel; note cfgLevel=L6 gives S=64,K=64 — the 64x64x64 shape the live app later pinned |
| debayer method enum (declared but not branched on — both paths do nearest-quad) | `/Users/daniel/Tesseract/isp-spec/src/ISP/Pipeline.hs:28` | BinQuad / NearestNeighbor, unused | debayer-quality choice slot, never implemented |
| white-level normalization on/off | `/Users/daniel/Tesseract/isp-spec/src/ISP/Pipeline.hs:109` | clamp01((x-black)/(white-black)) when True | linear vs raw-DN palette domain; an exposure-mapping knob |
| electron-variance floor | `/Users/daniel/Tesseract/isp-spec/src/ISP/Pipeline.hs:102` | max 1 (elecs x) | fixed guard |
| per-pixel T combiner across 4 channels | `/Users/daniel/Tesseract/isp-spec/src/ISP/Pipeline.hs:126` | weightedMeanU (inverse-variance) of tR,tGr,tGb,tB | channel-weighting for the time axis (e.g. green-only T) |
| frame interpolation law between the two captures | `/Users/daniel/Tesseract/isp-spec/src/ISP/Pipeline.hs:139` | linear lerp, alpha = f/(k-1) | easing-curve choice (ease-in/out, ping-pong) — direct 'motion feel' knob |
| nearest-quad sampling with no anti-alias | `/Users/daniel/Tesseract/isp-spec/src/ISP/Pipeline.hs:76` | nearest, v0 clarity | box/tent prefilter toggle (the live app's RateLadder S0 revisits exactly this) |

## ATTIC:SEEING  ·  ATTIC · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| sRGB transfer thresholds/constants | `/Users/daniel/Tesseract/isp-spec/src/ISP/Oklab.hs:52` | IEC 61966-2-1 (0.0031308/12.92/1.055/2.4) | fixed by standard — not a knob |
| Oklab M1/M2 matrices | `/Users/daniel/Tesseract/isp-spec/src/ISP/Oklab.hs:79` | Ottosson reference values (byte-identical constants reused in scripts/wada/derive.py:44 and the Swift/Metal ports) | working-space choice (OKLab vs CIELAB side-channel — the dyad256 research doc demands a CIELAB bridge for scoring) |
| deltaE = plain Euclidean | `/Users/daniel/Tesseract/isp-spec/src/ISP/Oklab.hs:110` | sqrt(dL^2+dA^2+dB^2) | perceptual-metric choice (weighted L, HyAB, CIEDE2000) — every assignment downstream inherits it |
| downsample = unweighted 2x2 mean, odd row/col truncated | `/Users/daniel/Tesseract/isp-spec/src/ISP/Oklab.hs:140` | box mean /4 | pooling kernel (box vs [1,2,1] tent — the live TL11 polyphase result says the 8-phase orbit of box == tent) |

## ATTIC:SPINNING  ·  ATTIC · SOLVE

| what | where | current | knob |
|---|---|---|---|
| spine/delta allocation — module comment says benchmark before pinning | `/Users/daniel/Tesseract/isp-spec/src/ISP/PaletteSpine.hs:33` | 192 shared + 64 local = 256 | a 'stability vs shimmer' slider: 256/0 = one global table, 0/256 = the shipped per-frame world; continuous in between |
| temporal group size | `/Users/daniel/Tesseract/isp-spec/src/ISP/PaletteSpine.hs:54` | 4 frames per delta (16 groups) | palette refresh cadence — another temporal octave knob (1/2/4/8/16 frames) |
| residual threshold: colors nearer than this to spine count as captured | `/Users/daniel/Tesseract/isp-spec/src/ISP/PaletteSpine.hs:78` | 0.04 (~2x the 0.02 Oklab JND, per comment) | novelty sensitivity of the delta palettes |
| k-means budget for spine and deltas | `/Users/daniel/Tesseract/isp-spec/src/ISP/PaletteSpine.hs:52` | 8 Lloyd iterations, deterministic strided init, 1e-6 convergence | quality dial |

## ATTIC:WADA  ·  ATTIC · LEARN

| what | where | current | knob |
|---|---|---|---|
| figure/ground assignment rule within each pair | `/Users/daniel/Tesseract/scripts/wada/derive.py:67` | ordered by chroma: more chromatic = FIGURE | role heuristic (chroma vs lightness vs area ordering) changes all three constants |
| the corpus itself | `/Users/daniel/Tesseract/scripts/wada/derive.py:35` | Wada 1933-34 dictionary only | swap-in palettes (Kuler/O'Donovan data per the research doc) = alternative 'taste priors' — a genuine user-facing style choice |
| prior role of the constants (ruling R2) | `/Users/daniel/Tesseract/scripts/wada/derive.py:24` | dictionary constants are the single-phase/no-evidence CAPPED fallback prior; live captures moment-match the same 3-parameter family per capture | prior-strength blend between dictionary taste and scene statistics |
| identity cap (ground chroma <= figure chroma) | `/Users/daniel/Tesseract/scripts/wada/derive.py:88` | cap lives on the prior path only | fixed by the R2 ruling |

## CADENCING  ·  CAPTURE · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| Base cadence width | `Tesseract/Tesseract/BinomialCadence.swift:25-27` | sigma_base(K) = (K-1)/8 — 7.875 at K=64 (derived from frame count, scale-aware) | The /8 divisor is the one residual designed ratio: a 'temporal contrast' knob scaling sigma_base changes how hard epochs snap |
| Depth modulation law | `Tesseract/Tesseract/BinomialCadence.swift:59-61 (spec CD law sigma = sigma_base * (2 - d), DS4 pins ratio to [1,2])` | linear (2 - s): near = 1x, far = 2x | The chaos-gain knob: widening the far multiplier (2 -> 3) makes backgrounds wilder; DS4's containment law would need re-pinning |
| Epoch count and centers | `Tesseract/Tesseract/BinomialCadence.swift:35-38` | 4 epochs at (2d+1)*sigma_base — hard-wired as SIMD4 (the 4^4 = 256 palette identity) | Structural, not a knob: 4 epochs x 4R x 4G x 4B = 256 is the palette algebra |
| Per-group vs per-pixel sigma in the quantizer | `Tesseract/Tesseract/PerfectQuantizer.swift:154, :250-251` | sigmaForDepth(avgDepth) on group means; separate subject/background sigmas | Granularity choice already stratified; follows the mixture's weights per ruling R1 |
| Temporal error-diffusion direction (spec-level) | `spec/temporal/TemporalLoop.hs:90-100` | bidirectional loop diffusion, multiple rounds (single-pass F-S ruled broken — frame-63 error pile-up); 0.7 error carry in the single-pass reference at :76 | Rounds count = smoothness of the temporal dither around the loop seam |

## HOLDING  ·  CAPTURE · WEAVE

| what | where | current | knob |
|---|---|---|---|
| Capacity = CameraConfig.totalFrames — recording auto-stops and flips to .processing when the 64th frame lands | `Tesseract/Camera/FrameBuffer.swift:36 + :56-60; transition at CameraManager.swift:479-482 and FaceCaptureManager.swift:213-216` | 64 (S = K cube invariant, pinned) | Loop-length knob is the cube-shape knob (see SQUARING); a shorter 'burst' mode = fewer frames means breaking S = K or padding |
| One-shot recording, no ring wraparound, buffer cleared on startRecording | `Tesseract/Camera/FrameBuffer.swift:40-46, :53-62` | append-until-full, isRecording flips off at capacity | A rolling pre-record ring ('capture the last 3.2 s') would let the shutter grab the past instead of the future |
| Frame indices come from frameBuffer.frameCount at capture time (drops never leave holes; timestamps carry real spacing) | `Tesseract/Camera/CameraManager.swift:442, :469-474` | dense reindexing 0..63 | Fixed contract; timestamps preserve real timing for any future retiming feature (temporal_interpolation feedback) |

## MESHING  ·  CAPTURE · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| FACE frame-accept throttle | `Tesseract/Camera/FaceCaptureManager.swift:86` | minFrameSpacing = 1/21 s (~20 fps to match LIVE) | Same capture-speed knob as LIVE's targetFPS; must move together |
| Anatomical signal formula: linear falloff from nose over face radius R | `Tesseract/Camera/FaceMeshSignal.swift:44-53 (spec FaceCadence.hs signals)` | s = 1 - d/R, clamped [0,1]; R = 0 => all 1 | Falloff-shape knob (linear/cosine/gamma) reshapes which facial regions stay crisp |
| Nose = vertex of max face-local z, ties to lowest index | `Tesseract/Camera/FaceMeshSignal.swift:31-38` | argmax z (topology-independent) | Anchor-point choice (nose/eyes/chin) would relocate the ORDER pole of the face |
| No-face frames emit an all-zero signal grid (whole frame = background/chaos) | `Tesseract/Camera/FaceCaptureManager.swift:174-176` | [Float](repeating: 0) | Could hold the last mesh, or use fill 0.5 like LIVE, instead of full-chaos frames |
| Overlap combine rule in the rasterizer | `Tesseract/Camera/FaceMeshSignal.swift:131` | max (surface nearer the nose wins) — NOTE the golden spec FaceCadence.hs uses FIRST-triangle-wins; the Swift max-combine is documented as harmless only on shared edges | Not a knob; a spec/port divergence to keep an eye on |
| YCbCr conversion matrix | `Tesseract/Camera/FaceCaptureManager.swift:334-337` | BT.601 full range (1.402 / 0.344136 / 0.714136 / 1.772) | Color-science choice (BT.709 would shift skin tones); currently frozen |
| Selfie mirror of both RGB grid and projected mesh x | `Tesseract/Camera/FaceCaptureManager.swift:250, :302` | always mirrored | Tie to the existing MIRROR ExportSettings toggle |
| Preview gating off-state | `Tesseract/Camera/FaceCaptureManager.swift:50-56, :158` | surfaceLive only in previewing/recording — SOLVING/SEALED pay no 20 Hz pipeline | Fixed efficiency policy |

## NEARING  ·  CAPTURE · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| Near anchor — face distance mapping to s = 1 | `Tesseract/Camera/DepthSignal.swift:21` | dNear = 0.25 m | Subject-distance calibration (arm's length vs tripod); DM4 proves the anchors are NOT load-bearing for the mixture segmentation, so this is safe to expose as a framing preference |
| Far anchor — background cutoff mapping to s = 0 | `Tesseract/Camera/DepthSignal.swift:23` | dFar = 1.5 m | Room-depth knob: widen for large rooms so mid-ground keeps gradient instead of clamping to 0 |
| Neutral fill for missing/invalid depth | `Tesseract/Camera/DepthSignal.swift:25` | fill = 0.5 | Bias missing depth toward face (crisp) or background (chaos) — an aesthetic failure-mode choice |
| Disparity-affine (1/m) rather than meters-affine mapping | `Tesseract/Camera/DepthSignal.swift:33 (spec/temporal/DepthSignal.hs:66)` | linear in 1/m between anchors, then clamp | Response-curve choice (disparity/linear/log) changes how depth translates to dither energy |

## OPENING  ·  CAPTURE · SENSE

| what | where | current | knob |
|---|---|---|---|
| Center Stage hardware gate: front .builtInUltraWideCamera must exist or the app terminally refuses (iPhone 17 line only) | `Tesseract/Camera/CameraManager.swift:292` | guard AVCaptureDevice.default(.builtInUltraWideCamera, .front) != nil — terminal, no retry (decree; same gate mirrored at FaceCaptureManager.swift:111) | A compatibility mode could relax the gate to any TrueDepth iPhone (capture already runs on .builtInTrueDepthCamera, so older hardware would physically work) |
| Capture device: TrueDepth camera, front position | `Tesseract/Camera/CameraManager.swift:301` | .builtInTrueDepthCamera / .front (FRONT-ONLY standing decree) | Rear/LiDAR capture is explicitly forbidden without Daniel's ask; not a knob to expose |
| Session preset — sensor FOV | `Tesseract/Camera/CameraManager.swift:283` | .photo (full 4:3 sensor, depth-capable) | A FOV/zoom choice (e.g. .high 16:9 vs .photo 4:3) would change what the 768 crop sees |
| Locked capture frame rate | `Tesseract/Camera/CameraManager.swift:82 (CameraConfig.targetFPS), applied at :316-318` | 20 fps, min == max duration | Capture-speed knob (10/20/30 fps) — directly sets the GIF's real-time span (64 frames / fps) since export delay is fixed at 5 cs |
| RGB pixel format | `Tesseract/Camera/CameraManager.swift:322` | kCVPixelFormatType_32BGRA | Fixed plumbing; not user-facing |
| Depth temporal smoothing on the sensor stream | `Tesseract/Camera/CameraManager.swift:335` | depthOutput.isFilteringEnabled = true | RAW vs SMOOTH depth toggle — off gives noisier, livelier σ cadence; a genuine look knob |
| Late-frame policy | `Tesseract/Camera/CameraManager.swift:324, :336` | alwaysDiscardsLateVideoFrames = true, alwaysDiscardsLateDepthData = true | Never-drop mode would trade latency for guaranteed 64 consecutive sensor frames |
| Depth format selection policy | `Tesseract/Camera/CameraManager.swift:339-347` | Float16 formats only, max width wins | Resolution/precision choice (Float32, lower-res-faster) if ever wanted |
| Orientation + selfie mirror | `Tesseract/Camera/CameraManager.swift:355-368` | videoRotationAngle = 90, isVideoMirrored = true on BOTH connections | Mirror on/off is already a persisted ExportSettings choice downstream; the capture-side mirror could be tied to it |
| ARKit face tracking config | `Tesseract/Camera/FaceCaptureManager.swift:122-124` | maximumNumberOfTrackedFaces = 1, isLightEstimationEnabled = false | Multi-face capture (mesh union) is an unexplored mode; light estimation could feed exposure signals |

## PAIRING  ·  CAPTURE · SENSE

| what | where | current | knob |
|---|---|---|---|
| Depth is optional per frame — dropped depth still emits an RGB-only frame (depth slots later filled with 0.5 neutral) | `Tesseract/Camera/CameraManager.swift:830-836` | proceed with nil depth; RGB drop skips the frame entirely | Strict pairing mode (skip frames without depth) would guarantee every cube cell has a real signal |
| Depth converted to DepthFloat16 on arrival regardless of native type | `Tesseract/Camera/CameraManager.swift:834` | converting(toDepthDataType: kCVPixelFormatType_DepthFloat16) | Fixed plumbing |
| Frame-timing log stride and outlier window | `Tesseract/Camera/CameraManager.swift:428, :435` | log every 20th frame; deltas ≥ 1.0 s discarded from the FPS average | Diagnostics only; could surface live FPS in the grid UI |

## SPLITTING  ·  CAPTURE · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| EM iteration count | `Tesseract/Tesseract/DepthMixture.swift:80 (spec DepthMixture.hs:166)` | fixed 64 steps from deterministic median-split init | Convergence-vs-latency; a derived stopping rule would fit the no-naked-constants decree better than exposing it |
| Role boundaries | `spec/temporal/DepthMixture.hs:194-195 (bayerMin 1/32, bayerMax 31/32)` | the Bayer 4x4 coverage extrema — LAW, not constants (DM8) | Deliberately not tunable; the decree's whole point |
| Live solve cadence | `Tesseract/Tesseract/DyadPipeline.swift:732` | refreshStride = Rung.fine.side / Rung.coarse.side (20 Hz / 4 = 5 Hz rung-16, TL8/TL9 clock) — DERIVED, not declared | Responsiveness-vs-battery knob; the read's ring length is tied to the same rung, so the 3.2 s span law holds by construction |
| Live read ring length | `Tesseract/Tesseract/DyadPipeline.swift:736` | ringFrames = Rung.coarse.frames = 16 coarse frames = one loop = 3.2 s of memory | Memory-span knob — how far back the live surface's temperament looks (EM13: it is exactly one GIF's worth of feed) |
| Per-frame refit + MS filtering vs one frozen pooled fit (the phi-collapse bug fix) | `spec/temporal/MixtureStability.hs:19-37 (law); Swift consumption via DepthMixture.localLevelAlpha at DyadPipeline.swift:183` | per-frame state (muF, muB, logit piB, log sigma) filtered by the derived local-level gain | STABILITY vs LIVENESS is inherent here but the gain is derived from the capture itself by design — surface only as telemetry |
| sigma floor in EM | `Tesseract/Tesseract/DepthMixture.swift:69 (max 1e-9)` | 1e-9 numerical guard | Not user-facing |

## SQUARING  ·  CAPTURE · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| Universal RGB crop side | `Tesseract/Camera/CameraManager.swift:61` | rgbCrop = 768, always centered (MetalPipeline.swift:439-444 clamps to origin when buffer is narrower) | Crop size/position = digital zoom + reframe; NO-CROP-CHANGES feedback decree says verify raw readout dims on device first |
| Universal depth crop side | `Tesseract/Camera/CameraManager.swift:62` | depthCrop = 256 | Must track rgbCrop's field of view; not independent |
| Cube shape S = K | `Tesseract/Camera/CameraManager.swift:73` | CameraConfig.mode = .training (64³ PINNED; .inference 128³ exists but crashes — MetalPipeline allocates textures once at 64) | The one deep shape knob; requires a full pipeline reallocation design per the audit note before ever exposing |
| CPU-fallback sampling policy: point-sample at each 12×12 block center (not box average) | `Tesseract/Camera/CameraManager.swift:521-527 (half = step/2 offset)` | single center texel per output pixel | Point vs box vs tent sampling = sharpness/alias character of the whole capture (RATE LADDER step S0 proposes the box prefilter) |
| 90-degree CCW rotation baked into the index math | `Tesseract/Camera/CameraManager.swift:522, :594` | srcX from output y, srcY from (outSize-1-x) | Fixed portrait contract |
| displayScale and exportSide derived views of the 64 grid | `Tesseract/Camera/CameraManager.swift:80, :85` | displayScale = 4 (256 px preview), exportSide = 256 (4x index replication) | Preview magnification knob; export side is contract-locked (decimate . replicate = id) |

## TIMEKEEPING  ·  CAPTURE · LAW

| what | where | current | knob |
|---|---|---|---|
| Planted-fixture geometry the laws are proven against (wall s=0.05 x 3072 px + face s=0.75 x 1024 px; rung-16 = 48+16 judgments of exactly 64 samples) | `spec/temporal/DepthMixture.hs:276, :312-314` | fixed deterministic binomial clusters, delta = 0.06 | Not a product knob — but any exposed capture knob (anchors, sigma gain, fps) needs matching fixture updates here first, per the spec-before-Swift discipline |

## ARCHIVING  ·  GIF · WEAVE

| what | where | current | knob |
|---|---|---|---|
| filename timestamp granularity | `/Users/daniel/Tesseract/Tesseract/Tesseract/GIFLibrary.swift:30` | Int(date.timeIntervalSince1970) — whole seconds (two exports in one second would collide, unlike the UUID temp files) | n/a to users, but a latent bug-shaped constant |
| auto-archive policy | `/Users/daniel/Tesseract/Tesseract/Camera/CameraManager.swift:710` | unconditional on success, no size cap, no retention limit | library size cap / auto-prune / opt-out toggle |
| storage location | `/Users/daniel/Tesseract/Tesseract/Tesseract/GIFLibrary.swift:18` | Documents/Library (visible to Files app backup semantics) | iCloud sync toggle |

## BROWSING  ·  GIF · SURFACE

| what | where | current | knob |
|---|---|---|---|
| library page capacity | `/Users/daniel/Tesseract/Tesseract/Views/LibraryView.swift:65` | prefix(9) — only the latest nine are ever visible, no paging | pagination / scroll-back through the whole archive |
| thumbnails still-only | `/Users/daniel/Tesseract/Tesseract/Tesseract/GIFLibrary.swift:79` | frame 0 still (nine playing GIFs would fight the 20 Hz chrome clock) | animate-on-select or low-fps animated tiles |
| which provenance line the detail shows | `/Users/daniel/Tesseract/Tesseract/Tesseract/GIFLibrary.swift:67` | only 'DYAD MIXTURE', sliced with a 200-byte bound (GIFLibrary.swift:71); HARMONY / RATE LEDGER / STATS lines are in the file but unsurfaced | a provenance inspector — the GIF already carries harmony, ledger meter M, and its full generator |
| tile geometry | `/Users/daniel/Tesseract/Tesseract/Views/LibraryView.swift:99` | 16-cell content in 20-cell claim, bracket-faced selection | grid density (lattice-law constrained) |

## CROPPING  ·  GIF · LAW

| what | where | current | knob |
|---|---|---|---|
| crop sizes and scale factor | `/Users/daniel/Tesseract/spec/output/FrameGeometry.hs:22` | rgbCrop 768, depthCrop 256, scaleFactor 3; OutputSize in {64,128,256} | decree-adjacent: no_crop_changes feedback forbids changing cropSize without device raw-dims verification |

## DREAMLAB  ·  GIF · LAW

| what | where | current | knob |
|---|---|---|---|
| beauty thresholds | `/Users/daniel/Tesseract/spec/output/TemporalSpatialGIF.hs:444` | coherence > 0.02; B2 sd/mean < 0.70; B4 dim in [1.0, 3.0]; perturbation amp 0.12 (line 208) | if BEAUTY ever becomes a user-visible score, these are its calibration constants (note: several violate the no-naked-constants decree — they predate it) |
| epoch cadence width | `/Users/daniel/Tesseract/spec/output/RealTesseract.hs:62` | sigma = 63/8 Gaussian over 4 epoch centers | temporal softness of the epoch axis (superseded by BinomialCadence in the app) |
| hard-coded lab output path | `/Users/daniel/Tesseract/spec/output/TemporalSpatialGIF.hs:671` | /Users/danielmosquera/beautiful_gif (stale username — the exportFrames call would fail on this Mac) | n/a; lab hygiene |

## FATTENING  ·  GIF · WEAVE

| what | where | current | knob |
|---|---|---|---|
| export canvas side (NOTE: actual is 256, not 512 — exportSide/outputSize = 256/64 = upscale 4) | `/Users/daniel/Tesseract/Tesseract/Camera/CameraManager.swift:85` | exportSide = 256, exportUpscale = 4 | output resolution picker (256/512/1024) — pure index replication scales freely; only file size changes |
| on-screen display scale (separate from export) | `/Users/daniel/Tesseract/Tesseract/Camera/CameraManager.swift:80` | displayScale = 4 (displaySize 256) | preview zoom |
| cube shape | `/Users/daniel/Tesseract/Tesseract/Camera/CameraManager.swift:73` | mode = .training => 64 frames x 64x64, PINNED (128-cube switch removed after device crash 2026-08-03) | decree-locked: 64-cubed is pinned; do not expose |

## FLIPPING  ·  GIF · SOLVE

| what | where | current | knob |
|---|---|---|---|
| mirror default (selfie orientation) | `/Users/daniel/Tesseract/Tesseract/Tesseract/GIFMachine.swift:35` | false (UserDefaults key export.mirror) | already user-facing in the SET cover — the model for how future knobs persist (ExportSettings.load/save) |
| bleed default (coverage dither band vs hard MAP classes) | `/Users/daniel/Tesseract/Tesseract/Tesseract/GIFMachine.swift:34` | true (UserDefaults key export.bleed) | already user-facing; the second existing knob |

## GRIDDING  ·  GIF · LAW

| what | where | current | knob |
|---|---|---|---|
| levels per axis | `/Users/daniel/Tesseract/Tesseract/Model/TesseractCoord.swift:10` | 4 per axis (4^4 = 256), diagonal 6.0, cellVolume 1/256 | none — the 256-entry wire and the DYAD sigma-involution sigma(i)=255-i both assume this shape |
| fine-bin count and bin->level breakpoints | `/Users/daniel/Tesseract/Tesseract/Model/Axes.swift:68` | 14 bins; 0-3 -> L0, 4-6 -> L1, 7-10 -> L2, 11-13 -> L3 (asymmetric by design) | dither granularity — but only if a future law re-derives the split |

## JUDGING  ·  GIF · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| eligibility predicate (DYAD-or-nothing law) | `/Users/daniel/Tesseract/Tesseract/Tesseract/GIFMachine.swift:52` | !frames.isEmpty && all rawRGB != nil; spec adds hasDepth (ExportMethods.hs:58) | decree-locked (per-frame-palette decree 2026-08-12): a customization UI must NOT reintroduce a global-table fallback; only the refusal copy could be surfaced |
| method space | `/Users/daniel/Tesseract/spec/output/ExportMethods.hs:42` | data Method = Dyad (singleton, XM4) | future export methods would enter here as new enum cases with their own eligibility |

## KEEPING  ·  GIF · SURFACE

| what | where | current | knob |
|---|---|---|---|
| Photos authorization scope | `/Users/daniel/Tesseract/Tesseract/GIF/GIFSaver.swift:21` | .addOnly (accepts .authorized or .limited) | none — minimal-permission choice is deliberate |
| share temp filename scheme | `/Users/daniel/Tesseract/Tesseract/GIF/GIFEncoder.swift:298` | tesseract_<UUID>.gif in temporaryDirectory (UUID fixed same-second collisions) | user-visible export filename pattern |
| denied-state button semantics | `/Users/daniel/Tesseract/Tesseract/Views/States/ResultStateView.swift:117` | ALLOW label + openSettingsURLString deep link, resets to idle on return | copy only; two-register error decree applies |

## LEDGERING  ·  GIF · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| STATS trace version / rebuild law selector | `/Users/daniel/Tesseract/Tesseract/Camera/CameraManager.swift:112` | CameraConfig.pairTree = true -> 'DYAD STATS v3' (analytic dyadic tree); false -> v2 ring solver | a LOOK-adjacent choice between the two palette generators (both stay rebuildable) |
| JEPA-H head on/off | `/Users/daniel/Tesseract/Tesseract/Camera/CameraManager.swift:123` | CameraConfig.jepaH = true (one-line revert) | a 'steady palette' toggle — trades ring churn for responsiveness |
| SK GENES measurement channel | `/Users/daniel/Tesseract/Tesseract/Camera/CameraManager.swift:103` | CameraConfig.skGenes = true (comment bytes only) | provenance verbosity switch |
| phase-chaos ANE loop | `/Users/daniel/Tesseract/Tesseract/Camera/CameraManager.swift:94` | CameraConfig.phaseChaosLoop = false (passed into DyadPipeline.process at GIFMachine.swift:245) | background-refinement quality knob (awaiting device comparison ruling) |
| harmony scoring scope | `/Users/daniel/Tesseract/Tesseract/Tesseract/GIFMachine.swift:85` | 128 sigma-pairs per table, mean-of-means + global min | which harmony statistic is shown/judged |
| meter width H_max | `/Users/daniel/Tesseract/Tesseract/Tesseract/GIFMachine.swift:149` | 8 bits/px (the wire's own index width; spec RateLadder.hs:123 hMax = 8) | none — derived from the 256-entry wire, not a free constant |
| declared strata ratios of the rate ladder | `/Users/daniel/Tesseract/spec/output/RateLadder.hs:54` | S0 acquisition 144:1, S5 VQ 3:1, others declared 1 (measured per capture) | future strata steps S2-S6 land here and each would be a declared, meterable choice |

## RESOLVING  ·  GIF · SOLVE

| what | where | current | knob |
|---|---|---|---|
| version dispatch (which generation law a stored GIF replays under) | `/Users/daniel/Tesseract/Tesseract/Tesseract/GIFMachine.swift:201` | prefix match v3 -> PairTree, v2 -> ring solver, v1 -> ring prior; 13 vs 9 numbers per line | none directly, but every future palette-law change must add a version tag here to keep old library GIFs self-reproducing |

## RUNGING  ·  GIF · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| the time law table (rung side -> GIF delay) | `/Users/daniel/Tesseract/Tesseract/Tesseract/TriScaleLadder.swift:50` | delayCs = [64:5, 32:10, 16:20], loopCs = 320 (side x delay = 320 at every rung; 128 has no integer delay — why the ladder caps at 64) | a rung/speed picker would have to move along this table, never off it |
| depth-resolution constants | `/Users/daniel/Tesseract/Tesseract/Tesseract/TriScaleLadder.swift:59` | baseRungSide 64, depthRungSide 16, samplesPerJudgment 64, judgmentsPerLoop 4096 (TL8/TL9 rulings) | ruled, not free |
| free-block meter threshold | `/Users/daniel/Tesseract/Tesseract/Tesseract/TriScaleLadder.swift:160` | block is 'free' iff <= 1 of its 8 children carry nonzero lattice mass (W = 1, zero bits) | none — the microstate chain rule defines it |

## SCANNING  ·  GIF · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| channel-dominance threshold that decides stone vs boundary | `/Users/daniel/Tesseract/Tesseract/Model/GoBoard.swift:63` | goThreshold: Float = 0.08 | a sensitivity slider for how much of the image reads as 'contested boundary' on the SOLVING boards |
| board size / sample region | `/Users/daniel/Tesseract/Tesseract/Model/GoBoard.swift:33` | GoBoard.size = 19, sampled from the TOP-LEFT 19x19 corner of the 64-side frame (blockToGoBoards line 73-77) | board position (center vs corner), board count, or full-frame pooled boards |
| share of the SOLVING progress bar given to Go analysis | `/Users/daniel/Tesseract/Tesseract/Camera/CameraManager.swift:646` | 0.40 (phase 1 of 3: 0->40%) | skip toggle: Go analysis is display-only guidance, could be disabled for faster solves |

## STITCHING  ·  GIF · WEAVE

| what | where | current | knob |
|---|---|---|---|
| frame delay / fps | `/Users/daniel/Tesseract/Tesseract/GIF/GIFEncoder.swift:21` | frameDelayCentiseconds = 5 (20 fps; contract: exactly 5 cs) | a speed knob — but constrained by the TL4 time law side x delay = 320 cs (only 5/10/20 cs are lawful at 64/32/16) |
| loop count | `/Users/daniel/Tesseract/Tesseract/GIF/GIFEncoder.swift:78` | 0x00 0x00 = infinite loop | play-once / N-loops option |
| disposal method + transparency | `/Users/daniel/Tesseract/Tesseract/GIF/GIFEncoder.swift:104` | packed 0x00: disposal=0, no transparent index | transparency support would need a reserved palette index (touches the 256-entry DYAD law) |
| background color index | `/Users/daniel/Tesseract/Tesseract/GIF/GIFEncoder.swift:61` | 0x00 | letterbox color if canvas ever exceeds image |
| per-frame LCT scheme | `/Users/daniel/Tesseract/Tesseract/GIF/GIFEncoder.swift:118` | 0x87 on EVERY image descriptor; tables must be exactly 768B x frame count (guard at :38) | DECREE-LOCKED (per-frame palettes only, 2026-08-12) — never expose |
| LZW parameters | `/Users/daniel/Tesseract/Tesseract/GIF/GIFEncoder.swift:219` | minCodeSize 8, maxCode 4095, clear-and-reinit on dictionary overflow | none — GIF89a fixed for 256-color streams |

## BRIDGING  ·  LEARN · LAW

| what | where | current | knob |
|---|---|---|---|
| weight count / head shape frozen at export | `nn/jepa/export_swift.py:19-22` | 149 floats: 16×3+16 + 5×16+5 | regenerated automatically on retrain — the customization hook for any retrained personality |
| fixture count | `nn/jepa/export_swift.py:78` | caps[-8:] (8 rings) | parity coverage |

## COUPLING  ·  LEARN · LEARN

| what | where | current | knob |
|---|---|---|---|
| encoder width | `nn/sk-gene/train_ground.py:77` | EHID = 96 (frozen passer hidden is 48) | grounding capacity |
| corpus sizes | `nn/sk-gene/train_ground.py:81-82` | N_TRAIN_EL=48, N_HELD_EL=24, PER_EL=1024 events per kind per level | training breadth |
| seed / tau / LR / logeps | `nn/sk-gene/train_ground.py:75-80` | SEED=20260811, TAU=0.99, LR=1e-3, LOGEPS=1e-4 | retraining recipe |

## DEBAYERING  ·  LEARN · LEARN

| what | where | current | knob |
|---|---|---|---|
| architecture budget | `spec/neural/BayerResidual.hs:14-16 and nn/debayer/train.py:343` | ≤8,000 params (actual 5,616), receptive field ≤9×9, no norm/attention/bias | Metal-kernel bakeability contract |
| leaky-ReLU slope | `nn/debayer/train.py:167` | LEAK = 1/16 (0.0625 — fp16-exact, one multiply in Metal) | none — hardware-derived |
| patch/halo/seed/lr | `nn/debayer/train.py:53-56,415` | SEED=20260716, PATCH=32, HALO=4, lr 1e-3 | retraining recipe |
| training photos location | `nn/debayer/train.py:58` | ~/Pictures/Photo Booth Library/Pictures (NOTE: predates the strict synthetic-corpus discipline; uses local photos, not captures from the app) | swap for the synthetic sampler if ever revived |
| ship gate | `spec/neural/BayerResidual.hs (BR5)` | +1.0 dB over bilinear minimum (measured +3.72) | quality bar |

## DESCENDING  ·  LEARN · LAW

| what | where | current | knob |
|---|---|---|---|
| descent fan-outs | `spec/neural/DescentLadder.hs (DL1)` | [2,8,8], serial depth 3 | if P4 hierarchical ANE descent ever ships (open item, gated on the A19 bench), this is its shape |
| ladder sizes/cadences/K | `spec/neural/DescentLadder.hs header ruling` | DEVICE-MEASURED parameters — they appear in NO law (the adversarial review killed every citation-derived constant) | the explicit contract that these become measured knobs |

## DITHER-PLANNING  ·  LEARN · LEARN

| what | where | current | knob |
|---|---|---|---|
| dither delta bound | `docs/DITHER-NN-PLAN.md:29` | ‖δ‖∞ ≤ ~0.03–0.06 (about half a shell spacing) | a literal DITHER STRENGTH knob if Model A ships |
| blue-noise mask bank | `docs/DITHER-NN-PLAN.md:38-43` | 64 pre-baked masks, one per frame, graph constants (zero runtime randomness — determinism law survives) | dither texture/pattern selection |
| Model B kernel | `docs/DITHER-NN-PLAN.md:64-69` | kernel 3–5, ~2k params, entries shared, primaries only | temporal-stability strength |

## DREAMING  ·  LEARN · LEARN

| what | where | current | knob |
|---|---|---|---|
| corpus size (capture rings) | `spec/output/JepaCorpusEmit.hs:236` | captureCount = 1024 | corpus breadth vs training time; more rings = broader regime coverage |
| jump-event law: probability, magnitude range, placement | `spec/output/JepaCorpusEmit.hs:187-210` | p=1/2 one level shift, U[3,8] drift-sigmas, uniform slot in 1..15, per-dim coin | how 'jumpy' the model expects lighting to be — a calm/energetic capture-style prior |
| ring geometry | `spec/neural/JepaH.hs:36-40` | frameCount=64, epochs=4, ringSlots=16 (derived), frameDelayCs=5 | pinned to the 64-cube; not user-facing while 64³ is pinned |
| latent dimensionality | `spec/neural/JepaH.hs:73-74` | latentDim = 6 (centroid + log-diagonal variances) | which generating-state channels the model dreams over |
| Wada prior ground constants baked into rendered tables | `spec/output/JepaCorpusEmit.hs:92-95` | wadaGroundL=0.6170482, wadaAlphaC=-1.3176036, wadaBetaC=0.7469411 | the single-phase/no-evidence background prior look |

## FOLDING  ·  LEARN · LEARN

| what | where | current | knob |
|---|---|---|---|
| compute precision / unit | `nn/jepa/build_model.py:102-103` | FLOAT32, CPU_ONLY (verify build) | fp16/ANE variant if the ring ever grows to dispatch-floor scale |
| deployment target | `nn/jepa/build_model.py:104` | iOS17 | none needed; reference artifact |
| parity tolerance | `nn/jepa/build_model.py:147` | assert worst < 1e-4 (measured 2.7e-07) | gate tightness |

## FREEZING  ·  LEARN · WEAVE

| what | where | current | knob |
|---|---|---|---|
| the curated gene set — WHICH of 16,896 genes ship | `nn/sk-gene/emit_swift.py:45 (curation loop) → SKGeneWeights.swift:32` | geneCount=98: 64 ORDER (halt∈{1,2}, distinct NFs, lowest ids) + 32 BOUNDARY (halt 3..15) + 2 CHAOS (the divergers) | the PRIME customization surface of the gene machine: a gene picker / per-capture gene selection |
| frozen dims | `Tesseract/Tesseract/SKGeneWeights.swift:12` | d=24, eHid=96, pHid=48, featDim=27, steps=16 | frozen with training |
| dispatch batch sizes | `nn/sk-gene/build_fold.py:73` | BG=512 blocks per ground dispatch; passer B=4096 | device-measured, not law |
| fp16 log epsilon | `nn/sk-gene/build_fold.py:74` | LOGEPS=1e-4 | none — fp16-derived |

## LEARNING  ·  LEARN · LEARN

| what | where | current | knob |
|---|---|---|---|
| embedding width | `nn/jepa/train.py:183` | D = 24 | encoder capacity of the surprise/representation channel |
| regime hypernet width | `nn/jepa/train.py:215-216` | r1: Linear(3,16), r2: Linear(16,5) | smoother expressiveness (the entire deployed model) |
| kernel support | `nn/jepa/train.py:225-231` | 5-tap symmetric (3 logits, mirrored), contains identity | max temporal smoothing radius on the 16-ring |
| VICReg-lite anti-collapse weights | `nn/jepa/train.py:265` | VAR_W=0.1, COV_W=0.04 | embedding-collapse guard strength |
| EMA target decay | `nn/jepa/train.py:266` | EMA_TAU = 0.99 | JEPA target-network inertia |
| state-loss weight vs JEPA pretext | `nn/jepa/train.py:320` | 4.0 * l_state + l_jepa | smoothing-fidelity vs representation trade |
| optimizer schedule | `nn/jepa/train.py:327-330` | cosine_decay(3e-3, 4000, 1e-4), AdamW wd=1e-3, 4000 iters, seed 64 | retraining recipe |
| mask arc length | `nn/jepa/train.py:297,331` | 4 contiguous slots, arcs tile (it%4)*4 | pretext difficulty (lawful lengths 1,2,4,8 per JH2) |
| train/val split | `nn/jepa/train.py:271` | n*7//8 | held-out fraction |
| promotion criteria (the beauty gates) | `nn/jepa/train.py:446-448` | B3 churn < oracle-EMA, B1 LZW(LCT) < oracle-EMA, FID rmse < oracle-EMA, DET deterministic — accuracy-vs-teacher is NOT a criterion | what 'better' means; a future UI could weight churn vs fidelity |

## OCTAVING  ·  LEARN · LEARN

| what | where | current | knob |
|---|---|---|---|
| hidden width / LR / seed | `nn/sk-gene/train_codec.py:74-76` | SEED=20260811, HID=48, LR=1e-3 | detail-prior capacity |
| log-sigma clamp | `nn/sk-gene/train_codec.py:77` | LOGS_MIN,LOGS_MAX = -12.0, 2.0 | prior sharpness bounds |
| corpus sizes | `nn/sk-gene/train_codec.py:78-80` | N_TRAIN_EL=48, N_HELD_EL=24, PER_LEVEL_SAMPLES=3000, LEVELS=3 | training breadth |
| fp16-safe log epsilon | `nn/sk-gene/train_codec.py:84` | LOGEPS = 1e-4 (1e-6 is fp16 subnormal — flush-to-zero would NaN the log) | none — hardware-derived |

## PASSING  ·  LEARN · LEARN

| what | where | current | knob |
|---|---|---|---|
| latent dim / hidden width | `nn/sk-gene/train_passer.py:75-76` | D=24, H=48 | gene-latent capacity |
| EMA tau / LR / variance weight / seed | `nn/sk-gene/train_passer.py:74-79` | SEED=20260811, TAU=0.99, LR=1e-3, VAR_W=1.0 | retraining recipe |
| steps | `nn/sk-gene/train_passer.py:209` | default 2000 (--smoke 30); latest run 4000 steps, 19 s | training budget |
| axis-typed baseline kept for comparison | `nn/sk-gene/weights-axis-typed.npz` | v1: three axis-typed app maps, 17,760 params (E1: anonymity costs nothing) | the gauge choice itself, already ruled |

## REDUCING  ·  LEARN · LEARN

| what | where | current | knob |
|---|---|---|---|
| gene size | `spec/neural/SKGeneCalculus.hs (SK1)` | size-7 terms (16,896 genes) | a larger calculus = richer gene vocabulary (SK8 would explode combinatorially) |
| unroll cap | `spec/neural/SKGeneCalculus.hs (SK5)` | UNROLL = 16, DERIVED (classification at cap 16 == cap 1000) | none — derived, not tuned |
| axis clock (gauge) | `spec/neural/SKGeneSemantics.hs axis-typing section` | axis = App-depth mod 3, cycling x→y→t; the passer reads only sym (axis-anonymous by the §12 gauge ruling) | the wiring — which physical axis each octree level splits |

## SEEDING  ·  LEARN · LEARN

| what | where | current | knob |
|---|---|---|---|
| corpus geometry | `nn/dither/data.py:26-29` | RING=64, SIDE=64, MODES=8 (ring-OU Fourier modes), WAVES=24 (waves per field) | texture spectrum of the synthetic world |
| eigenvalue (variance) range | `nn/dither/data.py:30` | LAM_MIN,LAM_MAX = 1e-6, 2e-2 | how noisy/flat synthetic captures can be |
| OU amplitudes and correlation time | `nn/dither/data.py:114-116` | centroid amps (0.06, 0.03, 0.03) for (L,a,b); theta ~ logU(0.5, 8); log-eigen amp 0.3; rotation amp 0.4 | the 'liveliness' prior of trajectories |
| jump events (lighting shocks) | `nn/dither/data.py:118-123` | 0–2 events, delta U(−0.06, 0.06), width U(4,24) frames | lighting-shock prior |
| mask blob law | `nn/dither/data.py:159-164` | sigmoid(4·(blob − q60)), 0.7 low-freq + 0.3 high | synthetic subject size/softness |
| seed ranges | `nn/dither/data.py:179-180` | TRAIN_SEEDS 1M–2M, HELDOUT_SEEDS 9M–9.1M (disjoint by construction) | train/held-out discipline |

## STEADYING  ·  LEARN · SOLVE

| what | where | current | knob |
|---|---|---|---|
| the deployment flag — the ONE learned unit in the pixel path | `Tesseract/Camera/CameraManager.swift:123` | static let jepaH = true (DEFAULT ON, one-line revert) | user-facing 'STEADY' toggle: model-smoothed vs EMA-smoothed palette; promotion still owes real-capture RATE LEDGER + HARMONY + device pass |
| ring slot count | `Tesseract/Tesseract/JepaHHead.swift:26` | slots = 16 (derived: frames/epochs) | pinned to the cube |
| corpus dims declared | `Tesseract/Tesseract/JepaHHead.swift:29` | dims = 6 (head is dim-agnostic by construction — extra dims need no retraining) | which state channels ride the ring (the bg triple was added post-training via the R2 'one smoothing law' ruling) |
| regime lags | `Tesseract/Tesseract/JepaHHead.swift:63` | lags [1,2,3] circular autocorrelations | frozen with the trained hypernet |
| whitening epsilon | `Tesseract/Tesseract/DyadPipeline.swift:457 and JepaHHead.swift:57` | eps = 1e-12 | none — the whitening-law epsilon, matches training |
| divisibility guard (partial-capture fallback) | `Tesseract/Tesseract/DyadPipeline.swift:454-455` | raw.count >= 16 && raw.count % 16 == 0 else nil → EMA | whether short captures get a padded ring instead of falling back |
| correlation clamp | `Tesseract/Tesseract/DyadPipeline.swift:509-511` | min(1, max(-1, cij/den)) | none — PSD safety |
| trace attribution | `Tesseract/Tesseract/GIFMachine.swift:117` | "DYAD JEPAH v7 ring=16" comment line when engaged | the before/after attribution for the promotion ledger; smoothed numbers ARE the traced generating state so rebuild stays byte-exact |

## TELLING  ·  LEARN · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| the flag | `Tesseract/Camera/CameraManager.swift:103` | static let skGenes = true (DEFAULT ON — comment bytes are provenance, not look; internal by simplicity decree) | a 'GENE READOUT' toggle, or promotion from telemetry to a felt channel (the owed felt-channel ruling) |
| gene representatives played | `Tesseract/Tesseract/SKGene.swift:202-204` | first curated gene of each phase class {0,1,2} — exactly 3 genes per capture | which genes 'read' the capture; could be user-chosen or capture-matched |
| encode level | `Tesseract/Tesseract/SKGene.swift:229` | level: 2 (rung-16 of the tower) | which octave the genes act on |
| pooling geometry | `Tesseract/Tesseract/SKGene.swift:174-176` | 64³→16³ by 4³ mean; guard frames>=64 && side>=64 | pinned to the cube |
| CPU vs fused-graph path | `Tesseract/Tesseract/SKGene.swift:140-153` | trace runs the pure-Swift CPU maps; mlpackages loaded (computeUnits=.all) only to prove availability | the one-dispatch ANE path is bundled but unused at runtime |

## TWINNING  ·  LEARN · LAW

| what | where | current | knob |
|---|---|---|---|
| solver shape constants (mirrors, not choices) | `nn/phase/dyad_solver.py:27-29` | LADDER=[1,1,2,4,8,16,32,64], N_LEVELS=8, PRIMARY_COUNT=128 | none here — these mirror the Haskell law; customize in DyadPalette.hs |
| Jacobi iteration budget | `nn/phase/dyad_solver.py:10-11 (docstring; body below)` | 50 iters, 1e-12 break, identical tie semantics | none — parity-load-bearing |

## ASSIGNING  ·  SOLVER · SOLVE

| what | where | current | knob |
|---|---|---|---|
| engine choice ANE vs CPU | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:407` | ANE if full 64-frame capture, else identical CPU search | none — parity posture (XP1/XP2) |
| solid-face boundary | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:288` | t < coverageFloor = 1/32 (Bayer's own finest threshold — structural, DM8) | none by decree (no naked thresholds) |
| background terminal index | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPalette.swift:441` | backgroundIndex = 255 | none — involution law |
| fars short-circuit | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:289` | all-false since v5 (both engines run the shared search) | none |

## BLEEDING  ·  SOLVER · SOLVE

| what | where | current | knob |
|---|---|---|---|
| BLEED setting (the one user-visible solver switch) | `/Users/daniel/Tesseract/Tesseract/Tesseract/GIFMachine.swift:34` | true (persisted 'export.bleed'; false = hard MAP classes, no band) | already exposed in SET cover — the template for future solver toggles |
| Bayer 4x4 matrix and midpoint normalization | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:70` | standard [[0,8,2,10],[12,4,14,6],[3,11,1,9],[15,7,13,5]], thresholds (m+0.5)/16 | dither texture family (Bayer vs other ordered masks) — a visible texture knob |
| coverage extrema = role boundaries | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:78` | floor 1/32, ceil 31/32 — the matrix's own extrema (DM8, structural) | none by decree |
| chaos-blur rung (spatial) | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:319` | rung=4 (4x4 blocks on 64^2 = rung 16, the resolution of depth) | background blur coarseness (8x8 = dreamier, 2x2 = crisper chaos) |
| chaos-blur temporal group | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:345` | 4-frame groups (spacetime 4x4x4, S4 'be bold') | background stillness cadence (1 = per-frame shimmer, 4 = held) |
| prefix level for sigma targets | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:376` | 32-level via nodes16 when tree on; full 128 prims when off | background palette rate (pairs with PAIRING node depth) |

## BRANCHING  ·  SOLVER · SOLVE

| what | where | current | knob |
|---|---|---|---|
| the pair-tree flag | `/Users/daniel/Tesseract/Tesseract/Camera/CameraManager.swift:112` | true (DEFAULT ON; ring solver stays for v1/v2 rebuilds) | palette architecture choice: latent dyadic tree vs designed binomial rings — a visible 'look' fork |
| tree depth = generations | `/Users/daniel/Tesseract/Tesseract/Tesseract/PairTree.swift:84` | descend(..., 7) => 128 leaves (pinned to 256-entry dyad) | none while 64^3/256 pinned |
| prefix-node depth for chaos targets | `/Users/daniel/Tesseract/Tesseract/Tesseract/PairTree.swift:68` | remaining==3 => 16 nodes (the 32-level) | background palette rate: 16/32/64-level prefix = coarser/finer chaos |
| half-normal moment coefficients | `/Users/daniel/Tesseract/Tesseract/Tesseract/PairTree.swift:39` | sqrt(2/pi), 1-2/pi — Gaussian moments, constant-free by construction | none — law |
| split-axis rule | `/Users/daniel/Tesseract/Tesseract/Tesseract/PairTree.swift:70` | argmax variance, ties lowest; basis never rotates | none — determinism (RL4 n proportional to sqrt(lambda)) |

## CHURNING  ·  SOLVER · SOLVE

| what | where | current | knob |
|---|---|---|---|
| the chaos-loop flag | `/Users/daniel/Tesseract/Tesseract/Camera/CameraManager.swift:94` | phaseChaosLoop = false (DEFAULT OFF, awaiting on-device comparison; no settings surface without ruling) | 'living background' toggle — exchange-refined chaos texture |
| scope restriction | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:400` | fully-far blocks only, two-phase captures only | S5 (band-block exchange scope) awaits step-order ruling |

## DECREEING  ·  SOLVER · LAW

| what | where | current | knob |
|---|---|---|---|
| STATS version tag selects the rebuild law | `/Users/daniel/Tesseract/Tesseract/Tesseract/GIFMachine.swift:124` | v3 when pairTree, else v2; parser accepts v1/v2/v3 (older library GIFs stay self-reproducing) | the version tag IS the forward-compatibility mechanism for any future palette-law knob |
| spec-only theory not yet ported | `/Users/daniel/Tesseract/spec/spatial/ColorGraphs.hs (+SpatialTransport.hs, TesseractGo.hs; statistics/StatsVariance.hs, WassersteinPalette.hs, BinomialCube.hs; quantization/BellPalette.hs, ResolutionLadder.hs, DitherRamp.hs, PairPermutations.hs, CentroidRefine.hs)` | reference/theory layer; StatsVariance.hs defines the NO-CAPTURE-TRAINING synthetic corpus; CentroidRefine's Swift port was deleted in the per-frame-palette decree | ResolutionLadder (subject-gated per-cell resolution) and PairPermutations (coverage-class texture) are dormant designs a customization UI could resurrect |

## GLIMPSING  ·  SOLVER · SURFACE

| what | where | current | knob |
|---|---|---|---|
| live solve stride | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:732` | refreshStride = Rung.fine.side / Rung.coarse.side (5 Hz rung-16 cadence) | preview palette liveliness vs battery (tied to TL8/TL9; offsetting awaits ruling) |
| live read block size | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:812` | side / Rung.coarse.side = 4x4 in space, refreshStride = 4 in time — the kappa atom twice; tau-lift restores what pooling removed | none — the ladder's own step |
| live read ring | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:859` | Rung.coarse.frames = 16 coarse frames handed to process() (3.2 s span) | scales with the rung by construction (span law) |
| NaN depth handling (live read) | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:824` | NaN -> DepthSignal.fill, clamp [0,1] | none |
| GPU vs CPU assignment | `/Users/daniel/Tesseract/Tesseract/Tesseract/Camera/CameraManager.swift:763` | Metal aerialPreview kernel when available (fp32, near-tie flips permitted), DyadPipeline.Live.assign otherwise; FACE mode = CPU path | none — parity posture |

## GROUNDING  ·  SOLVER · SOLVE

| what | where | current | knob |
|---|---|---|---|
| Wada dictionary prior constants | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPalette.swift:145` | wadaGroundL=0.6170482164, wadaAlphaC=-1.3176036044, wadaBetaC=0.7469411483 (moments of Sanzo Wada's 1933 dictionary, scripts/wada/derive.py) | the prior AESTHETIC itself — alternative dictionaries/palettes = selectable background 'ground mood' |
| identity cap (ground chroma <= figure chroma) | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPalette.swift:226` | prior path only (capped=true); scene fit uncapped | none — the dictionary's role law |
| v7 same-hue vs dead negation | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPalette.swift:220` | ground keeps figure hue (blue-haze negation deleted); comp() survives at :109 but no longer routes display | a ruled hue-relation choice (same-hue / complement / dictionary hue) is the obvious future knob |
| cL anchor for the ground family | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:266` | tree path: stats centroid L; ring path: L of T[0] | none — same number, honest source |
| bg-moment EMA carry | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:246` | same derived alpha as stats (one smoothing law, R2); frames without bg mass carry the smoothed triple | none — decree |

## HUMMING  ·  SOLVER · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| Sethares/Plomp-Levelt kernel constants | `/Users/daniel/Tesseract/Tesseract/Tesseract/Dissonance.swift:25` | b1=3.51 b2=5.75 x*=0.24 s1=0.0207 s2=18.96 (reference implementation) | none — literature reference |
| octave chart | `/Users/daniel/Tesseract/Tesseract/Tesseract/Dissonance.swift:50` | harmonics (4,5,6) just triad, fundamental 125 Hz, 4 octave partials | the chart's 'tuning system' — alternative triads = alternative color-harmony readings |
| detune grid + hue-collapse guard | `/Users/daniel/Tesseract/Tesseract/Tesseract/Dissonance.swift:87` | gridN=1200 (0.3 deg hue), guardGamma=1/12 semitone | tuning granularity if the felt channel ever ships |
| cadence sigma base | `/Users/daniel/Tesseract/Tesseract/Tesseract/Dissonance.swift:162` | 63/8 (BinomialCadence shipped value); near/far = exact octave => x=x* theorem, zero tuned constants | none — derived |
| read cadence | `/Users/daniel/Tesseract/Tesseract/Tesseract/Dissonance.swift:230` | rung 16, 4-frame slices at 5 Hz (TL8 ruling) | tied to LADDERING's rung |

## LATTICING  ·  SOLVER · SOLVE

| what | where | current | knob |
|---|---|---|---|
| error-diffusion clamp | `/Users/daniel/Tesseract/Tesseract/Tesseract/PerfectQuantizer.swift:74` | accumulated error clamped to +-0.2 per channel | dither aggressiveness (open ruling R5: naked constants) |
| depth-weighted diffusion strength | `/Users/daniel/Tesseract/Tesseract/Tesseract/PerfectQuantizer.swift:89` | s = 1 - depth*0.7 (near 30%, far 100%) | near/far texture contrast knob (naked constant, R5) |
| cell centers | `/Users/daniel/Tesseract/Tesseract/Tesseract/PerfectQuantizer.swift:64` | [0.125, 0.375, 0.625, 0.875] (Centers.hs unique-optimum theorem) | none — proved |
| analyzeSubject depth thresholds | `/Users/daniel/Tesseract/Tesseract/Tesseract/PerfectQuantizer.swift:244` | subject d > 0.6, background d < 0.4 (pre-mixture-law naked constants) | should be retired to the DepthMixture posterior (R5 candidate) |
| cadence base | `/Users/daniel/Tesseract/Tesseract/Tesseract/BinomialCadence.swift:26` | sigma_base(K) = (K-1)/8; sigma(d) = sigma_base*(2-d); epoch centers (2d+1)*sigma_base | the temporal 'breathing' of epochs across the 64-loop |
| probability normalization floor | `/Users/daniel/Tesseract/Tesseract/Tesseract/BinomialCadence.swift:100` | max(total, 1e-10) | none |

## METERING  ·  SOLVER · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| sigma-side split | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadEnergy.swift:87` | index >= 128 defines the sigma phase | none — involution law |
| entropy normalization | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadEnergy.swift:104` | log(256) | none |

## RUNGING  ·  SOLVER · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| time law constants | `/Users/daniel/Tesseract/Tesseract/Tesseract/TriScaleLadder.swift:50` | delayCs {64:5, 32:10, 16:20}, loopCs=320 (side x delay invariant; 128 has no integer delay) | none — GIF-centisecond arithmetic pins it |
| free-block threshold | `/Users/daniel/Tesseract/Tesseract/Tesseract/TriScaleLadder.swift:160` | nonzero children <= 1 => free (W=1) | none — TL7 definition |
| depth-resolution constants | `/Users/daniel/Tesseract/Tesseract/Tesseract/TriScaleLadder.swift:59` | baseRungSide=64, depthRungSide=16, 64 samples/judgment, 4096 judgments/loop (TL8/TL9) | the whole app's 5 Hz / 20 Hz cadence split hangs on these — a rung choice would be the deepest customization |
| polyphase offset reads (section 8) | `spec/output/TriScaleLadder.hs (TL10-TL12; no Swift port of offsets yet)` | phase 0 only; offsetting the live solve AWAITS RULING | read-cadence anti-aliasing (8-phase orbit = [1,2,1]^3 tent prefilter) |

## SCORING  ·  SOLVER · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| Ou & Luo model constants | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadHarmony.swift:58` | published 2006 values (1.46 chroma divisor, tanh coefficients, hue-effect sinusoids) | none — literature model |
| Birkhoff complexity floor | `/Users/daniel/Tesseract/Tesseract/Tesseract/BirkhoffMeasure.swift:29` | max(complexity, 0.001) | none |
| manifold-dimension blend | `/Users/daniel/Tesseract/Tesseract/Tesseract/BirkhoffMeasure.swift:64` | 3*(0.6*entropy + 0.4*participation-ratio) — naked weights | R5-class candidate; display-only |

## SHELLING  ·  SOLVER · SOLVE

| what | where | current | knob |
|---|---|---|---|
| the binomial ladder | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPalette.swift:44` | [1,1,2,4,8,16,32,64] over 8 levels (sum 128) | palette mass allocation across chroma shells — a strong 'look' knob if ever re-exposed |
| max shell radius | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPalette.swift:383` | rho(k)=2k/7 — outermost shell at 2 standard deviations | palette saturation reach (conservative vs vivid) |
| chroma clamp bisection | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPalette.swift:118` | 40 steps toward gamut boundary, chroma-only scaling | none — gamut law |
| gamut tolerance | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPalette.swift:92` | 1e-6 slack on linear RGB bounds | none |

## SIGHTING  ·  SOLVER · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| guarded std floor for shell radii | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPalette.swift:333` | max(1e-3, sqrt(var)) | minimum palette spread on flat scenes — a 'never fully gray' floor |
| Jacobi sweep cap and off-diagonal epsilon | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPalette.swift:341` | 50 sweeps, stop at 1e-12 | none — numeric law |
| eigenvector sign canonicalization epsilon | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPalette.swift:267` | 1e-9, first component above eps forced positive (DY8 anti-flicker) | none — determinism law |
| zero-mass fallback distribution | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPalette.swift:301` | mid-gray centroid L=0.5, zero covariance | the empty-capture palette (could be user-chosen ground tone) |
| EMA blends statistics, never colors | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPalette.swift:320` | lerp on centroid+covariance, PCA re-derived | none — anti-flicker architecture |

## SPLITTING  ·  SOLVER · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| EM iteration count | `/Users/daniel/Tesseract/Tesseract/Tesseract/DepthMixture.swift:80` | 64 fixed steps, median-split init | solver effort / responsiveness knob (more steps = tighter phase split) |
| tied-sigma floor | `/Users/daniel/Tesseract/Tesseract/Tesseract/DepthMixture.swift:69` | 1e-9 | minimum band softness; raising it widens the subject/background transition |
| BIC parameter counts deciding one vs two phases | `/Users/daniel/Tesseract/Tesseract/Tesseract/DepthMixture.swift:110` | k=4 (two-phase, tied) vs k=2 (single); bic2 < bic1 strict | a bias slider here = how eagerly the app declares a background exists (all-face vs split look) |
| tau-lift for the rung-16 preview fit | `/Users/daniel/Tesseract/Tesseract/Tesseract/DepthMixture.swift:123` | law-of-total-variance identity, always on for preview; export uses full-res pooled fit | none intended (identity), but preview/export fit parity is a switchable posture |
| local-level Kalman gain derivation (stats EMA alpha) | `/Users/daniel/Tesseract/Tesseract/Tesseract/DepthMixture.swift:155` | Muth 1960 steady-state gain from lag-1 autocorr; degenerate guards return alpha=1 (no smoothing) or 0 (freeze) | a user 'steadiness' knob could scale the derived alpha (currently constant-free by decree) |
| MS per-frame mixture filtering | `/Users/daniel/Tesseract/Tesseract/Tesseract/DepthMixture.swift:182` | always on in export (DyadPipeline:144); state theta=(muF,muB,logit piB,log sigma) | drift-vs-flicker character of the background boundary over the loop |

## STAGING  ·  SOLVER · SOLVE

| what | where | current | knob |
|---|---|---|---|
| the cadence octave in gamma(s)=1/(2-s) | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:88` | 2 (the shipped cadence octave; invariant sigma(s)*gamma(s)=sigma_base) | aerial-perspective strength: how hard distance mutes chroma (a 'depth haze' slider) |
| byte round-trip convention | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:173` | round half-to-even x255 (matches GHC round) | none — spec parity anchor |

## STEADYING  ·  SOLVER · LEARN

| what | where | current | knob |
|---|---|---|---|
| the JEPA-H flag | `/Users/daniel/Tesseract/Tesseract/Camera/CameraManager.swift:123` | true (DEFAULT ON, one-line revert; promotion owed device pass) | 'steady palette' toggle — model-smoothed vs EMA-smoothed table cadence |
| ring slot count | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:453` | JepaHHead.slots = 16 (the resolution of depth, TL9) | table update cadence (5 Hz now); other divisors of 64 are the natural menu |
| whitening/log epsilon | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:457` | 1e-12 | none |
| bg torus carry-fill | `/Users/daniel/Tesseract/Tesseract/Tesseract/DyadPipeline.swift:479` | nearest present slot carried around the ring; no evidence at all => Wada prior downstream | none — R2 one-smoothing-law ruling |

## WITNESSING  ·  SOLVER · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| pooling tower block sizes | `/Users/daniel/Tesseract/Tesseract/Tesseract/PhaseTelemetry.swift:60` | b in {2,4}; requires side and frames divisible by 4 | none — the 3:2:1 Haar kernel is PP1-exact |
| chaos-bill block | `/Users/daniel/Tesseract/Tesseract/Tesseract/PhaseTelemetry.swift:106` | 4^3 spacetime blocks, ground half = index >= 128, logFactorial table to 64 | none |

## COVERING  ·  SURFACE · SURFACE

| what | where | current | knob |
|---|---|---|---|
| BLEED toggle + default | `Tesseract/Tesseract/GIFMachine.swift:34 (default true), Tesseract/Views/SettingsView.swift:38 (row)` | bleed = true (coverage dither band vs hard MAP classes), key 'export.bleed' | already user-facing — the template for future export knobs |
| MIRROR toggle + default | `Tesseract/Tesseract/GIFMachine.swift:35 (default false), Tesseract/Views/SettingsView.swift:43 (row)` | mirror = false (exact index-domain horizontal flip), key 'export.mirror' | already user-facing; selfie orientation |
| the settings row inventory itself | `Tesseract/Views/SettingsView.swift:27` | SETTINGS title, CAMERA row, BLEED, MIRROR, LIBRARY, DONE — nothing else | THE expansion point: every future customization (per CLAUDE.md, flags like CameraConfig.phaseChaosLoop, jepaH, pairTree, skGenes are one-line code flags with 'no settings surface without a ruling') would surface as new rows here + regions in GridLayout.settingsScene + faces in CellMechanics.controlFaces |
| selection vocabulary | `Tesseract/Views/SettingsView.swift:78` | selected = full accent ring via CellSprite; unselected = ControlFrame idle/disabled | selection styling |

## FACE:REFUSED  ·  SURFACE · SURFACE

| what | where | current | knob |
|---|---|---|---|
| the six detail sentences | `Tesseract/App/ContentView.swift:172` | 'allow camera access in Settings...' / 'tesseract needs the Face ID camera...' / 'tesseract needs the center stage selfie camera of iPhone 17 or later' / 'this device cannot track the ARKit face mesh' / 'the GIF could not be encoded, record again' / fallback 'something went wrong, try again' (unknown details force-lowercased BY LAW) | refusal copy / localization |
| retry routing per refusal | `Tesseract/App/ContentView.swift:148` | cameraOff -> restart (.idle + start()); exportFailed -> reshoot (.previewing, session still live); unknown -> restart; terminals -> none | recovery policy (mirrors canStep edges) |
| wrap width derivation | `Tesseract/Views/States/ErrorStateView.swift:69` | measured from CellText raster of '0' at label register over errMsg.w; fallback 36, floor 8 | derived, not naked (no-naked-constants pattern); changes with region or register |

## FACE:SEALED  ·  SURFACE · SURFACE

| what | where | current | knob |
|---|---|---|---|
| metric row selection + formats | `Tesseract/Views/States/ResultStateView.swift:77` | M %.0f, O %.0f, C %.2f, dim %.1f, col %d — spacing Lattice.gif(4) | which verdict numbers a user sees (RATE LEDGER / HARMONY numbers exist in the GIF comment but are not surfaced) |
| KEEP state labels/symbols | `Tesseract/Views/States/ResultStateView.swift:100` | KEEP/.../KEPT/ALLOW/RETRY with square.and.arrow.down/ellipsis/checkmark/gearshape/exclamationmark.triangle | save-flow voice; ALLOW chosen over SETTINGS to fit the 22-cell button at body register |
| KEEP outcome notes (second register) | `Tesseract/Views/States/ResultStateView.swift:69` | 'photos off, allow adding in Settings' / 'the GIF did not save, try again' | explanation copy |
| buttons are static-tick | `Tesseract/Views/States/ResultStateView.swift:32` | tick: 1 passed (no BEAT on result buttons — only WATCHING's shutter beats) | which controls carry the BEAT |

## FACE:SOLVING  ·  SURFACE · SURFACE

| what | where | current | knob |
|---|---|---|---|
| board tints | `Tesseract/Views/States/ProcessingStateView.swift:40` | chanR/chanG/chanB pairs on 3 boards, labels R/G, G/B, B/R, Go cell = 1 atom (19 atoms/board) | solve visualization choice — FACE already shows a boards-less variant |
| palette swatch presence + size | `Tesseract/Views/States/ProcessingStateView.swift:27` | CellPalette(table:) default entryCells 2; checker until table arrives | palette-birth visibility (Daniel's 2026-08-10 ask made this a requirement — SM5 pins procPalette in the scene) |
| percent format | `Tesseract/Views/States/ProcessingStateView.swift:29` | %.0f%% at counter register | progress voice |

## FACE:WAKING  ·  SURFACE · SURFACE

| what | where | current | knob |
|---|---|---|---|
| wordmark and subtitle strings | `Tesseract/Views/States/IdleStateView.swift:13` | TESSERACT / '4^4 = 256' | branding; note the subtitle uses a superscript-4 character, outside SM1's word alphabet (it is payload, not a machine word) |
| busy tile size | `Tesseract/Views/States/IdleStateView.swift:17` | sideCells = idleBusy.w = 12, static phase 0 | could take clock.heartbeat for the live shimmer (currently static) |

## FACE:WATCHING  ·  SURFACE · SURFACE

| what | where | current | knob |
|---|---|---|---|
| settings button label | `Tesseract/Views/States/LivePreviewStateView.swift:36` | 'SET' in ledGhost body register | chrome labeling |
| preview placeholder | `Tesseract/Views/States/LivePreviewStateView.swift:60` | '64 x 64' on Ink.void | waiting-state look |
| face-dot dwell time | `Tesseract/Views/States/FacePreviewStateView.swift:39` | Task.sleep 2 seconds, then hidden (decree amendment 2026-08-09) | indicator persistence: transient vs always-on |
| face-dot seal size | `Tesseract/Views/States/FacePreviewStateView.swift:87` | box = 6 cells | indicator size |
| shutter BEAT ring | `Tesseract/Views/States/LivePreviewStateView.swift:76` | ringInk = Ink.ink on treatment 1 (1 tick in 4), else ledGhost; reduce-motion evaluates at tick 1 | pulse styling |

## FACE:WEAVING  ·  SURFACE · SURFACE

| what | where | current | knob |
|---|---|---|---|
| counter format | `Tesseract/Views/States/RecordingStateView.swift:17` | '\(frame) / \(total)' | counting voice (remaining vs elapsed) |
| progress bar geometry | `Tesseract/Views/States/RecordingStateView.swift:48` | 64 cols x 2 rows at the atom pitch, lit = round(frame/total*64) | bar styling; 64 columns intentionally = 64 frames |
| elapsed-time derivation | `Tesseract/Views/States/RecordingStateView.swift:22` | frame / CameraConfig.targetFPS, format %.1fs | display of the pinned 3.2 s capture (64/20) |

## FACING  ·  SURFACE · SURFACE

| what | where | current | knob |
|---|---|---|---|
| BEAT period (idle faces go lit 1 tick in N) | `Tesseract/UI/Cells/CellMechanics.swift:25` | beatPeriodTicks = 4 (5 Hz at the 20 Hz clock) | chrome pulse rate — pinned cross-app by UM6 golden table |
| treatment table | `Tesseract/UI/Cells/CellMechanics.swift:30` | [0,1,2,2,3,3,4,4] (SixFour's shipped golden pin) | alternative face behaviors (e.g. no beat) would fork the golden table |
| region -> face-kind map (closed) | `Tesseract/UI/Cells/CellMechanics.swift:55` | 27 entries; brackets ONLY on the 9 library tiles, frame everywhere else | every new interactive region MUST register here (LINT-CONTROL-FACE + selfCheck totality) |
| bracket geometry | `Tesseract/UI/Cells/CellControlFace.swift:49` | gutterCells = 1, armCells = 3 (the D1 spec) | selection-face styling |

## GLYPHING  ·  SURFACE · SURFACE

| what | where | current | knob |
|---|---|---|---|
| pixel font | `Tesseract/UI/Cells/CellText.swift:51` | UIFont.monospacedSystemFont(weight: .bold) at pointSize = rows | a font choice knob (any monospace works with raster-and-snap) |
| symbol em fraction (fit heuristic) | `Tesseract/UI/Cells/CellChrome.swift:39` | symbolEmFraction = 0.82, weight .semibold | icon density; owned raster heuristic from line pass 2026-08-12 |
| default symbol box | `Tesseract/UI/Cells/CellChrome.swift:11` | box = 12 cells | icon size register |

## GUARDING  ·  SURFACE · LAW

| what | where | current | knob |
|---|---|---|---|
| governed directory set + vocab-converted file list | `scripts/lint-grid.sh:28` | GOVERNED = Tesseract/App Tesseract/Views Tesseract/UI; GOVERNED_VOCAB grows as views convert | new views must be added to the vocab list to gain lint protection |
| primitive allowlist | `scripts/lint-grid.sh:21` | UI/Cells/Cell*.swift, PixelGrid, SurfaceClock, Ink, GIFPlayerView — the only raw-drawing files | new primitives must be allowlisted |

## INKING  ·  SURFACE · SURFACE

| what | where | current | knob |
|---|---|---|---|
| primary control ink | `Tesseract/UI/Cells/Ink.swift:10` | (235,235,235) | chrome theme — all chrome color routes through these tokens, so a theme = a token table swap |
| ghost/secondary ink | `Tesseract/UI/Cells/Ink.swift:12` | (40,40,40) | contrast knob |
| reject / accept / accent inks | `Tesseract/UI/Cells/Ink.swift:14` | (220,60,60) / (70,200,90) / (96,165,250) | semantic color theme |
| canvas black, void, pure-white shutter | `Tesseract/UI/Cells/Ink.swift:22` | (0,0,0) / (16,16,16) / (255,255,255) | background tone; pure is deliberately brighter than ink so the shutter is the brightest thing on screen |
| type registers (glyph heights in 2pt cells) | `Tesseract/UI/Cells/Ink.swift:58` | micro 4 / label 7 / body 9 / counter 11 / display 16 (all upscaled 2026-08-10) | text-size accessibility scale — but SurfaceMachineTests requires words to still fit regions |

## LATTICE  ·  SURFACE · LAW

| what | where | current | knob |
|---|---|---|---|
| atom size (pt per displayed GIF pixel) | `Tesseract/UI/Lattice/TesseractLattice.swift:30` | gifPx = 4 | a display-zoom knob; re-basing the atom re-lays the entire app with zero call-site edits (Lattice.swift:9 comment says exactly this) |
| half-atom fine-spacing unit | `Tesseract/UI/Lattice/TesseractLattice.swift:31` | subPt = 2 | tied to atom; must stay gifPx/2 (L2) |
| sanctioned sub-atom hairline (pixelFrame border) | `Tesseract/UI/Lattice/TesseractLattice.swift:35` | frameStrokePt = 1 | frame weight of content borders |
| grid dimensions (iPhone 17 Pro reference screen) | `Tesseract/UI/Lattice/TesseractLattice.swift:38` | cols = 100, rows = 218, hBleedPt = vBleedPt = 2 | per-device grid re-derivation if the app ever targets other screens; today hard-coded to 402x874 pt |
| HIG touch floor in cells | `Tesseract/UI/Lattice/TesseractLattice.swift:47` | touchFloorCells = 11 (44 pt) | accessibility large-touch mode could raise this |
| standard action-button height | `Tesseract/UI/Lattice/TesseractLattice.swift:48` | buttonRowCells = 13 (52 pt) | global control density knob (was 11 before the 2026-08-10 upscale) |
| preview widget side | `Tesseract/UI/Lattice/TesseractLattice.swift:49` | previewCells = 64 (256 pt, pinned = the GIF) | pinned by L5 to CameraConfig.outputSize — a preview-zoom knob would need a law change |
| shutter footprint / inner disc | `Tesseract/UI/Lattice/TesseractLattice.swift:50` | recordCells = 22, recordDiscCells = 18 | shutter size preference (upscaled 18->22 in 2026-08-10) |

## PLACING  ·  SURFACE · SURFACE

| what | where | current | knob |
|---|---|---|---|
| settings button claim (the one piece of surface chrome) | `Tesseract/UI/Lattice/GridLayout.swift:48` | col 73, row 14, w 24, h 13 | chrome position; SIMPLICITY decree caps chrome at this one region |
| preview claim (the GIF's on-screen home) | `Tesseract/UI/Lattice/GridLayout.swift:51` | col 18, row 48, 64x64 | vertical composition of the main surface |
| shutter claim | `Tesseract/UI/Lattice/GridLayout.swift:52` | col 39, row 172, 22x22 | left/right-handed shutter placement |
| transient face dot claim (FACE mode) | `Tesseract/UI/Lattice/GridLayout.swift:62` | col 18, row 116, 64x6 | indicator placement or an always-on option |
| SOLVING palette swatch claim | `Tesseract/UI/Lattice/GridLayout.swift:81` | procPalette col 34, row 80, 32x32 (16x16 entries at 2 cells) | palette-birth visualization size |
| settings scene rows (17-row rhythm) | `Tesseract/UI/Lattice/GridLayout.swift:129` | setTitle r20 / setModeLabel r44 / mode pills r54 / toggleBleed r78 / toggleMirror r95 / setLibrary r112 / setClose r197 | THE expansion surface: new customization rows must claim regions here (LOOK radio was deleted from this block 2026-08-12; the vacated rows are where future knobs go per the SIMPLICITY decree) |
| library grid: exactly 9 tiles | `Tesseract/UI/Lattice/GridLayout.swift:151` | libCell0..8, 20x20 cells each, 3x3 | archive page size / paging (older files stay on disk but are unreachable in UI) |
| library detail claims | `Tesseract/UI/Lattice/GridLayout.swift:160` | libDetailGif 44x44, libDetailPalette 32x32, libInfo 88x12 | detail composition |

## REPLAYING  ·  SURFACE · SURFACE

| what | where | current | knob |
|---|---|---|---|
| playback rate source | `Tesseract/Views/GIFPlayerView.swift:24` | fps = 100.0 / GIFEncoder.frameDelayCentiseconds (= 20 fps, derived not naked) | a slow-mo/scrub review mode |
| loop behavior | `Tesseract/Views/GIFPlayerView.swift:79` | animationRepeatCount = 0 (infinite) | play-once / bounce options |
| scaling | `Tesseract/Views/GIFPlayerView.swift:28` | scaleAspectFit + .nearest filters | pinned by the pixel-art contract |

## SHELVING  ·  SURFACE · SURFACE

| what | where | current | knob |
|---|---|---|---|
| shelf capacity | `Tesseract/Views/LibraryView.swift:65` | prefix(9) — latest nine; older files stay on disk but are UI-unreachable | paging/scrolling for the deeper archive |
| tile geometry | `Tesseract/Views/LibraryView.swift:99` | 16-cell GIF content in a 20-cell claim (brackets in the 1-cell gutter) | tile density |
| stills-not-playing choice | `Tesseract/Views/LibraryView.swift:9` | thumbnails are stills by design (nine playing GIFs would fight the chrome clock) | animated-tiles option with a perf budget |
| provenance truncation | `Tesseract/Views/LibraryView.swift:134` | fit() drops count/8 chars per iteration until the raster fits libInfo.w — measured, not guessed | which provenance fields display (full mixture line is longer than the region) |
| delete is immediate | `Tesseract/Views/LibraryView.swift:155` | no confirmation dialog before GIFLibrary.delete | a confirm step |

## SPRITING  ·  SURFACE · SURFACE

| what | where | current | knob |
|---|---|---|---|
| default sprite pitch | `Tesseract/UI/Cells/CellSprite.swift:40` | cellPt = Lattice.pt(1) (2pt) for fine chrome; Lattice.gifPx (4pt) for GIF-pixel widgets | per-widget resolution choice |
| checker block size | `Tesseract/UI/Cells/CellChecker.swift:15` | 2x2 cell parity ((c/2)+(r/2))&1 | busy-texture scale |
| palette swatch entry size | `Tesseract/UI/Cells/CellPalette.swift:15` | entryCells = 2 (32x32 cells = 128 pt) | swatch zoom |
| shutter geometry | `Tesseract/UI/Cells/CellSprite.swift:87` | discR = recordDiscCells/2 = 9, ringT = 2, derived from lattice constants | follows LATTICE recordCells knobs |
| icon glyph masks (share arrow, retake arrow, seal disc) | `Tesseract/UI/Cells/CellSprite.swift:127` | hand-drawn predicates, box 12 default; retake ring gap turn in (0.05, 0.20) | iconography set |

## SURFACING  ·  SURFACE · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| the six state words | `Tesseract/UI/SurfaceMachine.swift:38` | WAKING / WATCHING / WEAVING / SOLVING / SEALED / (CAMERA OFF, NO TRUEDEPTH, NO CENTER STAGE, NO FACE TRACKING, EXPORT FAILED, ERROR) | voice/language pack — SM1 constrains to uppercase letters+spaces and words must raster-fit their regions |
| un-interruptible state set | `Tesseract/UI/SurfaceMachine.swift:54` | {weaving, solving} return false | pinned by SM3; a 'cancel capture' feature would need a spec amendment |
| terminal refusals (no RETRY rendered) | `Tesseract/UI/SurfaceMachine.swift:117` | noTrueDepth, noCenterStage, noFaceTracking have no outgoing edges (SM4) | device-gate policy; the Center Stage gate (iPhone-17-line only) lives here as .noCenterStage |
| message-to-refusal keying | `Tesseract/UI/SurfaceMachine.swift:103` | exact string match on CameraManager.cameraDeniedMessage / noTrueDepthMessage / noCenterStageMessage / FaceCaptureManager.faceTrackingUnsupportedMessage / CameraManager.encodeFailedMessage, else .unknown | new failure classes register here |

## SWITCHING  ·  SURFACE · SURFACE

| what | where | current | knob |
|---|---|---|---|
| launch mode | `Tesseract/App/ContentView.swift:27` | appMode = .live | remember-last-mode (currently NOT persisted — resets to LIVE every launch, unlike BLEED/MIRROR which persist) |
| the mode set itself | `Tesseract/App/ContentView.swift:22` | exactly {LIVE, FACE} (front-only decree) | new capture modes register here + a settings pill + a manager |
| interruption gate | `Tesseract/App/ContentView.swift:92` | reads SurfaceMachine.state(...).interruptible per active mode | pinned by SM3 |

## TICKING  ·  SURFACE · SIGNAL

| what | where | current | knob |
|---|---|---|---|
| chrome clock rate | `Tesseract/UI/Cells/SurfaceClock.swift:46` | hz = Float(CameraConfig.targetFPS) = 20 | deliberately locked to the GIF's 20 fps — a battery-saver chrome rate would decouple it |
| reduce-motion behavior | `Tesseract/UI/Cells/SurfaceClock.swift:30` | heartbeat pinned to 0; link keeps firing; callers evaluate treatments at tick 1 (provably beat-free) | an explicit in-app 'calm chrome' toggle independent of the OS setting |
