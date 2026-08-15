# Session sunset: the tensor, the decrees, and one repo

2026-08-14. Branch `tensor-and-no-fallback-decree`. Read this before
touching the ladder, the tensor or the directory.

This session started as a technical-debt cleanup and turned into three
rulings that changed the architecture. It also contains two mistakes I
made that are worth more to you than the successes, so they are written
plainly rather than buried.

---

## 1. The decrees, which are now enforced rather than remembered

**NO STUBS, NO FALLBACKS.** Your words: "I HATE stubs and I HATE
fallbacks. Stubs are unfinished work and fallbacks are technical debt
made useful."

This is in `CLAUDE.md` at identity level, written as the general form of
a rule the app already lived by in one place: a capture that cannot run
DYAD exports nothing, never a silent downgrade. Two build-gated checks
in `scripts/lint-grid.sh` enforce it:

- `LINT-NO-STUB` bans TODO, FIXME, XXX, HACK, STUB across the whole app.
  It passed on its first run. The app had zero stubs already, because
  `Reweave` established the pattern: an unimplemented edit returns a
  REFUSAL with a reason, and a refusal is finished work.
- `LINT-NO-FALLBACK` bans the word itself. It caught 20 sites and, on
  its first run, caught my own decree text, which is how I know it bites.

Nineteen of the 20 were honest paths carrying a dishonest name. They are
now named for what they are: **twin** (one law, two engines, proven equal
by a parity test), **prior** (a branch of the law itself), **verdict**,
**platform path**, **format law**, **refusal**. One was real debt: a
guard in `DyadANE` lumped "no engine on this device" together with "the
caller passed a ragged cube", so a defect routed silently to CPU forever.
Split. The defect now traps in DEBUG.

If you need the word, the escape hatch is `// LINT-ALLOW-FALLBACK:
<reason>` on the line, mirroring the existing `LINT-ALLOW-POSITION`. That
makes every instance a decision someone signed.

---

## 2. The capture tensor

Your specification: 16x16 is the unit at 5 fps, its 256 cells ARE the
256 centroids, and `4(64x64) == 2(32x32) == 1(16x16)`.

Cells stand 1 : 8 : 64, so the equivalent float resolution is FORCED at
64 : 8 : 1, and every rung carries the same 262144 bits. That is not a
choice anyone made; it falls out of the counting.

The fine rungs are ONE SIGN BIT per child, `child = parent + sign * g`.
Measured: one bit beat FOUR flat bits (0.01655 against 0.02043) at a
quarter of the cost.

`spec/output/CaptureTensor.hs`, CT1 to CT11. Its scope is deliberately
narrow: it owns the retained bytes and nothing else, and cites the three
specs that own the rest.

### THE SPLIT, and why it exists

Free signs contradicted FOUR green axioms across two specs: OV5 (mean
invariance for every dial setting) and OctaveCodec's CX1, CX2, CX3,
where CX1 is named that file's load-bearing law.

You ruled the split rather than picking a winner, and it holds because
they are genuinely two objects:

| | |
|---|---|
| reads and codec | mean invariance EXACT, for any g. The octave dials stay provably safe: no setting moves exposure, white point or cast. |
| stored tensor | one FREE sign bit per child, ruled on measured evidence (about a third sharper, 4.2 output levels against 6.1). Never claims CX1. |
| declared price | a GIF made live and the same GIF remade from the tensor differ, bounded by g. CT11 states it as a law. |

`Octave.hs` carries a scope note at OV5 so the split reads from both
sides. Worth keeping in mind: the wired codec costs ZERO sign bits,
because a child derives its signs from its own position, but it can only
express separable variation. The stored form pays one bit per child to
express what the wiring cannot. Neither dominates.

### Zerotrees

EZW (1993) and SPIHT (1996) solved this and the app was not using it.
The flat scheme paid one bit per child whether the subtree said anything
or not, and **95.3% of subtrees say nothing**:

```
flat, one bit per child       262144 b   rmse 0.01655
significance, one level        45064 b   rmse 0.01793   -82.81%
full zerotree, 16 kills 32+64   30232 b   rmse 0.02409   -89.75%
```

The threshold is DERIVED, never chosen: the crossover of a two-phase
mixture on the capture's own subtree deviations, the same mechanism
ruled for the rung-64 override. A quiet subtree is `g = 0` (CT9), so
silence uses the decode law already stated and adds no second
reconstruction path, which the no-fallback decree would have forbidden.

### What g reads

The parent AND the previous tick at its rung (CT10). This is DHVC 2.0's
conditioning, and the 5/10/20 fps rungs were already producing the
temporal half and discarding it. g stays a parameter, so every law holds
for any g and training cannot reopen one.

### The redundancy, kept

The stack holds 8/7 of the fine rung's cells. `FeedCompression.hs` FC4
states it exactly as 73/64. You ruled it kept, and the reason is
structural: in this pyramid each level downsamples only the low-pass
channel, so **the coarse level is a PICTURE**. That is the only reason
16x16 can BE the 256 centroids. Under a critically sampled wavelet it is
a frequency band and cannot be a palette at all. The 14% is what the
palette costs.

---

## 3. S8 and P1: the rungs do real work now

**S8** (`Solve/StrataDescent.swift`): the rungs WRITE the index instead
of metering it. Commitments use lookahead, not the nearest node mean,
which is `nn/descent`'s finding spent: greedy measured 0.8601 leaf
agreement at 8x the excess distortion, lookahead-L2 0.9652. The fine
search is 8 candidates instead of 128, so whole-cube distance
evaluations fell from about 33.5M to 4.5M. It made the pipeline cheaper,
not more expensive.

**P1** (`Signal/ResolutionGate.swift`): depth picks the resolution.
Your ruling: "use the stack IN relation to depth, NOT color."

The depth measurement (`TesseractTests/DepthQualityHarness`) settled it
in an unexpected direction. The two phases separate at **9 sigma or more
at every rung**, even under harsh noise with 60% silhouette dropout, and
the posterior commits everywhere. So confidence is NOT the criterion and
the gate contains no confidence test. What changes across rungs is pure
geometry: **edge error is exactly the block size**, 1.00 / 2.00 / 4.00
fine cells.

So the fine rung is spent at the BOUNDARY, not on the subject. The gate
is a RIDGE, not a ramp: solid figure and solid ground are the same case.
`ResolutionLadder.hs` was amended (its old gate spent the fine rung on
the subject's interior, using naked 1/3 and 2/3 thresholds). The new
thresholds are the Bayer matrix's own levels, so no constant is chosen.

Measured budget on a realistic field: **rung16 89.8%, rung32 1.5%,
rung64 8.7%**. That ~9% agrees with the zerotree's 95.3%-quiet finding,
because they are the same fact seen twice.

★ HONEST CAVEAT: rung 32 gets only 1.5% of cells. It is not silent, so
AD10 is satisfied, but it is close to it. If a device pass shows the
outer shell buying nothing, collapsing to a two-rung gate is the obvious
simplification and would be a real one, not a loss.

---

## 4. The directory (P5)

`Tesseract/Tesseract/` held 28 files and 7,700 lines with no organising
idea. It is gone, and so is `Tesseract/GIF/`. The engine now sits under
your own ATLAS categories, so a file's job is its address:

```
Signal/  OctaveRead, FeedFormat, TriScaleLadder, ResolutionGate,
         DepthSignal, FaceMeshSignal
Solve/   DyadPipeline, DyadPalette, PairTree, StrataDescent, DyadANE,
         PerfectQuantizer, TesseractPalette, BinomialCadence
Learn/   JepaHHead, SKGene, ANELoop, + weights
Weave/   GIFEncoder, GIFSaver, GIFMachine, GIFLibrary
Edit/    CubeStore, Reweave, DepthMixture
Meter/   AdditiveCensus, PhaseTelemetry, DyadEnergy, DyadHarmony,
         Dissonance, BirkhoffMeasure, PhaseTiling
```

Everything moved with `git mv`, so history follows each file. `App/`,
`UI/` and `Views/` did NOT move, because `lint-grid.sh` states the grid
constitution in terms of those exact paths. `project.yml` globs the
tree, so the moves cost no build change.

`DepthMixture` sits in `Edit/` deliberately, per your ruling that the
depth analysis belongs to the edit phase. **The file has moved; the call
site has not.** `DyadPipeline.process` still fits at capture. That is P2
and it is NOT done.

---

## 5. Two mistakes, recorded because they cost you time

**I duplicated three specs.** I wrote `CaptureTensor.hs` restating the
ladder that `Octave.hs` (OV1-OV13), `FeedCompression.hs` (FC1-FC10) and
`OctaveCodec.hs` (CX1-CX7) already owned, all three green, two with
shipped Swift ports. I presented FC4's 73/64 pyramid tax to you as a
fresh finding from a web search. It was already a proved axiom in your
own suite. Eight axioms have been deleted and the file re-scoped.

**I let you rule against a proved law without telling you.** When I
asked free-versus-balanced signs, I cited the ATLAS calling
mean-preservation load-bearing, but not that OV5 and CX1-CX3 were GREEN
AXIOMS asserting it. You made that call without knowing you were
overturning four proofs. The split repaired it, but you should have had
that fact before the question, not after.

The lesson is now a habit and it is cheap: **before writing a spec,
grep the registry for the object it describes.** `spec/README.md` says
the Makefile is the registry of record. It is, and I did not read it.

---

## 6. Gates, and what is owed

Green at sunset: **spec 59/59**, **Swift 374 tests, 0 failures**, grid
lint clean.

Owed, in dependency order:

1. **P2**: move the depth-fit CALL to the edit path. The file is already
   in `Edit/`; the call in `DyadPipeline.process` is not moved. This
   blocks P3, because you cannot re-weight a fit that is already baked.
2. **P3**: the background's say becomes a user dial. Today
   `analyze weights = 1 - t`, fixed by ruling R1. It becomes
   `beta * (1 - t)` with beta on the edit cover, and beta = 1 must
   reproduce today byte for byte.
3. **P4**: the synthetic corpus as 16^3 / 32^3 / 64^3 from the 256
   colours and their OKLab relationships. `FeedCompression.hs` FC10
   already specifies the sampler interface, so this is a port.
4. **The tensor's Swift port**, replacing `CubeStore`.
5. **`DyadANE`'s graph is superseded** by S8 and the export no longer
   consults it. Rebuilding it for the descent is `nn/dyad-assign` work.
6. **The live surface still runs the old free search.** The app holds
   two assignment laws right now, which contradicts EM13. The close is
   written on the line that owes it in `DyadPipeline.Live.assign`.
7. **A device pass**, owed on everything since 2026-08-11.

Measurement harnesses for all of the above are in the test target and
are meant to be re-run, not trusted: `DepthQualityHarness`,
`TensorShapeHarness`, `LadderOptionsHarness`. My fixtures are quieter
than a real face, so the 95.3%-quiet figure may be optimistic. Point
them at a real retained capture before spending anything on it.
