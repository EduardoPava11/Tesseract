# Tesseract Haskell Specifications

Haskell specs model the **ideal** behavior of the Tesseract app.
Each script is self-contained, runnable, and verifies its own axioms.

```
make test            # run all core specs (quiet: ✓/✗ per file)
make test-verbose    # run all core specs (full output)
make test-algebra    # run just one layer
make test-one F=temporal/ContinuousDepthCadence.hs   # run one file
make list            # show all specs
```

## Directory Layout

### algebra/ — Core mathematical foundation
| File | What it specifies |
|---|---|
| `Tesseract.hs` | R1+R3=R4 direct sum, 4^4 lattice, 22 axioms (A1-A7, P1-P5, C1-C4, T1-T5, E1-E3) |
| `DirectSum.hs` | R1+R2=R3 direct sum pattern, projection/injection axioms, non-negative cone |
| `TesseractDistances.hs` | Intra/inter-color distances, Hamming K~Binomial(4,3/4), distance separation |

### quantization/ — Pipeline from pixels to palette indices
| File | What it specifies |
|---|---|
| `TesseractSpec.hs` | Unified pipeline spec: blocks, histograms, Go boards, dithering, type classes (R,G,B,T) |
| `TesseractAxes.hs` | 4 orthogonal axes, 14-bin histograms, bell-shaped target distribution, bin assignment |
| `TesseractQuantize.hs` | Type-class separation: Phase 1 color dithering (F-S), Phase 2 epoch assignment, GPU/CPU split |
| `PerfectQuantize.hs` | Distribution-exact CPU pass: largest-remainder, depth-sorted, axioms PQ1-PQ5 |

### temporal/ — Epoch model, depth cadence, error diffusion
| File | What it specifies |
|---|---|
| `TemporalBinomial.hs` | R1 axis as Gaussian cadence, P(epoch d|frame z), soft crossovers, per-frame binomial |
| `ContinuousDepthCadence.hs` | sigma(depth) = sigma_base * (2 - depth), no zones, axioms CD1-CD8 |
| `DepthBinomial.hs` | Depth histogram, subject detection, Birkhoff M=O/C on depth, depth*color coupling |
| `TemporalLoop.hs` | Bidirectional error diffusion around 64 frames, eliminates edge asymmetry |

### spatial/ — Go board analysis for color structure
| File | What it specifies |
|---|---|
| `TesseractGo.hs` | 19x19 blocks as Go positions, 3 channel-pair boards, territory, liberties, complexity |
| `ColorGraphs.hs` | Per-color spatial graphs (~16 pixels each), paired graph analysis, Jaccard coherence |
| `SpatialTransport.hs` | Earth Mover's Distance between color graphs, assignment solver |

### statistics/ — Binomial model and deviation analysis
| File | What it specifies |
|---|---|
| `BinomialCube.hs` | 8R*8G*4B=256 sRGB cube, B(4096,1/256), spatial transport between frames |
| `BinomialFix.hs` | Floor quantization (equal cell volumes) + hash PRNG (independent channels) |
| `DeviationManifold.hs` | Deviation from binomial IS the image, manifold dimension: 0D-3D classification |

### output/ — End-to-end, analysis, geometry, assets
| File | What it specifies |
|---|---|
| `RealTesseract.hs` | Reads 64 PPM frames, tesseract quantization, deviation analysis, PPM export |
| `GIFAnalysis.hs` | Grades a GIF: palette fidelity, epoch distribution, Birkhoff M, manifold dim |
| `FrameGeometry.hs` | TrueDepth pixel math: 1080x1920 RGB, 360x640 depth, crop and step sizes |
| `TemporalSpatialGIF.hs` | Voxel(z,x,y) as sRGB(z/63,x/63,y/63), White/Black anchors, beauty axioms |
| `GenIcon.hs` | 1024x1024 app icon: isometric tesseract hexagon, 4x4 color grids per face |
| `BreakInvariants.hs` | Tests what happens when spec invariants are violated |

### neural/ — Para categorical NN vocabulary
| File | What it specifies |
|---|---|
| `ScaleInvariant.hs` | σ_base(N)=(N-1)/8, μ_d=(2d+1)×σ_base, size-invariant crossovers, axioms B15-B19 |
| `Para.hs` | Para(C) morphisms, composition, parallel product, Learner, DepthMorphism ⊂ R1, axioms PA1-PA6 |
| `DepthInference.hs` | 3-layer NN (PatchEncoder;Compress;DepthHead), 593 params, feeds existing pipeline, axioms DI1-DI5 |
| `TeacherStudent.hs` | Training contract: teacher=PerfectQuantizer, student=NN depth→same pipeline, axioms TS1-TS6 |

### deprecated/ — Removed ideas with rationale
| File | Why |
|---|---|
| `KataGoClient.hs` | Black-box NN for dithering guidance. Opaque, over-engineered. Territory analysis sufficient. |
| `DEPRECATED.md` | Full explanation of what KataGo was and why it was removed |
