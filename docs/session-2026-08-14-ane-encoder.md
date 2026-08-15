# Session: the address, the engine, the space, and the surface

2026-08-14, continuing from `docs/session-2026-08-14-tensor.md` on
branch `tensor-and-no-fallback-decree`. Four directions, in the order
you gave them.

---

## 1. The directory, finished

The previous pass named the engine's six directories after ATLAS
categories. It left the job half done, and the reason is worth stating
plainly because it is the kind of thing that stays invisible: **three
organising ideas were living in one tree.**

| idea | directories |
|---|---|
| ATLAS jobs | `Signal/ Solve/ Learn/ Weave/ Edit/ Meter/` |
| Apple technologies | `Metal/ ML/` |
| MVC leftovers | `Model/ Views/ UI/ App/` |

A file's address told you its job in six directories out of thirteen.
It now does in all ten.

### The move that answers your ruling

You asked for organisation "now that we have a more complete idea of
memory management", and that named the missing axis: **byte lifetime**.
Persistence was spread across three directories that did not know about
each other, plus one struct buried at the top of an unrelated file:

```
CubeStore         Edit/           Documents/Cubes    1.75 MiB/capture
GIFLibrary        Weave/          Documents/Library  the artifacts
ArrangementStore  UI/Widgets/     UserDefaults       the widget layout
ExportSettings    inside GIFMachine.swift            BLEED, MIRROR
```

`Store/` now holds all four. That is not tidiness: **UserDefaults is
the only required-reason API this app declares** (`PrivacyInfo`,
CA92.1), and a declaration is auditable exactly when every writer of it
shares an address.

### The rest

- `Camera/` → `Sense/`, completing the ATLAS categories.
- `Metal/` and `ML/` dissolved. They were technologies, not jobs: a
  `.metal` file belongs with the law it implements (`Quantize.metal` →
  `Solve/`, `ANELoop.metal` → `Learn/`), and an mlpackage belongs with
  the model line that loads it (`ML/` → `Learn/ML/`).
- `Model/` dissolved. It held two coordinate laws (`Axes`,
  `TesseractCoord` → `Law/`) and one meter (`GoBoard` → `Meter/`) under
  an MVC name that means nothing in this app.
- `App/` + `UI/` + `Views/` → `Surface/` with `App/ Cells/ Lattice/
  Scenes/ Widgets/`. "UI" is a technology word; SURFACE is this app's
  own word, the one `EditMachine` speaks.

Everything moved with `git mv`, so history follows each file.
`project.yml` globs the tree, so none of it cost a build change.

### One invariant got stronger, and it is worth copying

`lint-grid.sh`'s primitive drawing-vocabulary allowlist was a hand-kept
name list — `Cell*.swift` plus `PixelGrid`, `SurfaceClock`, `Ink`, and
`Views/GIFPlayerView`, which sat in a *different directory* from every
other primitive it was grouped with. It is now `Surface/Cells/`. **The
allowlist is a directory, so it cannot drift from itself.** The set is
unchanged; the maintenance burden is gone.

---

## 2. The ANE encodes and compresses the signal

> *"you are an engineer and I need ANE to be able to encode+compress
> the signal information."*

Spec `spec/neural/TensorEncoder.hs` (TA1–TA9, green). Lab
`nn/tensor-codec/build_model.py`. Ports `Store/CaptureTensor.swift`
(the CPU law) and `Store/TensorANE.swift` (the engine twin), gated by
`CaptureTensorTests` + `TensorANEParityTests`, 11 tests green.

### ★ TA1 is the unlock, and it is a small piece of algebra

The natural way to write this transform is a 3D operator over the
spacetime cube, and that is the thing the Neural Engine schedules
worst. It does not need one.

**The 2×2×2 spacetime pool FACTORS into a temporal pair-average and a
spatial 2×2 average, and the two commute.** Fold frame pairs into the
channel axis and the temporal half becomes a **1×1 convolution**
(`out[c] = ½·a[c] + ½·b[c]` is a 2C→C pointwise conv with fixed
weights); the spatial half is a stock `avg_pool`. So the whole octave
transform is built from the two operators the engine is *best* at:

```
cube  [64, 3, 64, 64]
  |  reshape → conv 6→3 (½,½) → avg_pool 2×2
l32   [32, 3, 32, 32]
  |  the same two operators again
l16   [16, 3, 16, 16]       its 256 cells per tick ARE the palette
  |
parent = nearest-upsample(coarse)   ×2 in all three axes
r      = fine − parent
sign   = r ≥ 0                      THE STORED BIT (CT4)
g      = pool(|r|)                  THE STORED STEP
```

One dispatch. **0.9 ms on M3 Max**; the A19 figure is owed to the
device pass.

The CPU keeps two jobs and neither is dense: fit the mixture that
*derives* the significance threshold (4096 numbers, not 262144), and
pack the bitstream.

### ★ TA3 is the load-bearing law: fp16 is safe by arithmetic

The obvious worry: the engine is fp16, the encoder's only decision is a
*comparison*, and a flipped comparison could silently degrade every
retained capture forever. That is the exact shape of defect the
no-stubs decree exists to forbid, so it is answered with a bound rather
than a hope.

**A flipped sign costs exactly `2·min(|r|, g)` of extra reconstruction
error — not `2g`.** The reconstruction moves by 2g, but the *error*
moves by at most twice the residual. And a flip can only happen where
|r| is below the engine's resolution. So where the engine can act at
all, the act is worth nothing. This is the encoder's XP2.

Measured twice, independently:

| | agreement | worst disagreeing \|r\| | fp16 ulp there |
|---|---|---|---|
| authoring gate (float64 ref) | 98.30% of 786432 | 4.853e-4 | 4.883e-4 |
| `TensorANEParityTests` | 97.14% | 4.389e-4 | 4.883e-4 |

**Every single disagreement is a residual the engine could not see.**

### ★ TA5: fp16 is free at the rung that is the palette

CT2 forces 64 bits per rung-16 cell. Three fp16 channels spend 48. The
engine's native precision costs the coarse picture — the rung whose 256
cells per tick *are* the 256 centroids — nothing at all, because it
fits inside an allocation the counting had already forced, with 16 bits
spare.

### The format stores `g` rather than predicting it

CT4 leaves `g` a parameter; CT10 describes a predictor that reads the
parent and the previous tick, trained in `nn/jepa`. Storing the
subtree's own measured deviation instead costs 4 B per loud root and
buys two things worth more:

1. **the decode needs no trained weights**, so a tensor retained today
   is still decodable after any future retrain. A format whose decode
   depends on a model version is a time bomb;
2. **no naked `k` and `j` enter the app** while the predictor does not
   yet exist.

A trained predictor becomes format v2, never a second runtime path.

### Measured

`CaptureTensorTests`, on the synthetic figure-over-ground fixture:
**1,099,586 B against CubeStore's 1,835,024 B**, rmse 0.0060.

---

## 3. ★ THE FINDING THAT NEEDS YOUR RULING

The zerotree's whole saving depends on the capture having a genuinely
**quiet phase**, and a sensor noise floor destroys that phase.

Measured on the same cube (`nn/tensor-codec/noise_floor.py`):

| | verdict | loud | colour bytes | rmse |
|---|---|---|---|---|
| noiseless | two phases | 24.9% | 53607 | 0.00581 |
| noise floor 0.0015 | **ONE phase** | 100% | 136704 | 0.00574 |

CT7 is not wrong. It asks *"are there two populations of deviation
magnitude"*, and under a noise floor there genuinely are not — so its
own branch says pay flat, and the encoder stores 110 KB of noise signs.

But the question that decides whether a sign is worth a bit is a
different one: *"is this subtree louder than noise alone would make
it"*. The candidate answer is Donoho & Johnstone (1994), and it is
derived exactly the way the crossover is — σ = MAD/0.6745 is a Gaussian
identity, not a tuning, and σ·√(2 ln N) is the universal threshold. It
kills 27.9% of subtrees for +0.9% rmse.

**Nothing has been changed.** Which question the significance bit asks
is your ruling, and both candidates are derived, so neither introduces
a constant.

★ One consequence either way: **the 95.3%-quiet figure the zerotree was
ruled on is optimistic for any capture with real sensor noise.** The
previous session's own caveat said the fixtures might be too quiet;
this is that caveat coming true from the other direction.

---

## 4. The colour latent: the model's space already exists

> *"The model we train MUST be wise in the 64×64×64 GIF creation
> because 256 colour every 64 frames is something that CAN be explored
> in latent colour space."*

Spec `spec/neural/ColourLatent.hs` (CL1–CL8, green).

**The latent space is not something to invent. It is already there,
already exact, and every GIF the app has ever exported already carries
its own coordinates.** A GIF's colour is 64 × 256 × 3 = 49152 bytes,
and all of it is generated by **13 numbers per frame = 832 numbers**,
by a decoder that already ships and is already gated byte-for-byte
(`GIFMachine.rebuildTables`, "DYAD STATS v3"). **59 : 1, exact.**

That reframes the training problem completely:

| | |
|---|---|
| the space | exists, and is exact (CL1) |
| the decoder | is the shipped law, and is TOTAL — no illegal point exists to reach (CL2, CL3) |
| the symmetry | the lawful relabelings are the 256 XOR-by-mask permutations, which commute with σ exactly; the model must be a quotient by them or it reads labels instead of colour (CL4, CL5) |
| the hierarchy | forced at three levels [4, 32, 256] by AdditiveLadder's strata — not a hyperparameter (CL7) |
| **the METRIC** | **the one thing missing** (CL6) |

### CL6 is the finding

Euclidean distance in the 13 numbers is not colour distance — that much
is obvious, and would be fixable by weighting the axes. The stronger
fact, which is what the axiom checks: **the ratio between a mean step
and a variance step changes with position** (1.9 at one covariance, 0.8
at ten times it). A single diagonal metric cannot be right in both
places.

So **the training run this architecture needs is a metric learner, not
a generator.** The generator already ships. That is a far better-posed
problem than "train a model on GIFs", and it is what
`docs/model-placement.md` §4.1's open CHOICE was really asking.

Corpus emission and the run itself are **not done**.

---

## 5. Form follows function: the memory is on the surface

The app's function grew a third phase this session. It CAPTURES, it
RETAINS, and it EDITS. Capture and edit both speak on the surface.
Retention did not — and it is the one that spends the user's storage,
about a megabyte per capture, forever.

`CubeStore.totalBytes()` already existed for exactly this, with the
comment "the figure the SET cover shows, so keep-all is a visible cost
rather than a silent one". **It had no reader.**

The SET cover now carries a reporting-only block under RESET LAYOUT, in
the same metric voice the result scene uses:

```
KEPT FOR RE-EDITING
    12.4        1.0        12
    HELD        EACH    MOMENTS
```

Two new `GridRegion`s (`setStorageLabel`, `setStorage`), both
reporting-only, so no touch floor and no control face. The lattice
laws' disjointness check gates them like every other region.

A cost the user pays and cannot see is the same silence the no-stub
decree bans in the engine, one layer up: nothing fails, so nothing gets
decided. This also unblocks the open **ruling 5** in
`docs/model-placement.md` ("how much is kept") by making the number
visible before you rule on it.

---

## 6. Gates

- **spec** — `TensorEncoder.hs` and `ColourLatent.hs` added and
  registered; suite run at the end of the session.
- **Swift** — 385 tests, 11 of them new, 0 failures.
- **grid lint** — clean. It caught my own prose twice today, which is
  how I know `LINT-NO-FALLBACK` bites.
- **device pass** — still owed, on everything since 2026-08-11, and now
  also on the A19 dispatch figure for `TensorEncode`.

## 7. What is owed, in dependency order

1. **The significance ruling** (§3). It changes the retained bytes, so
   it is upstream of the call-site swap.
2. **CR3 on the tensor**: identity re-weave must reproduce the archived
   GIF byte for byte *from the tensor* before anything stops writing
   `CubeStore`. The two formats coexist deliberately until then.
3. **P2**, unchanged from the last session: move the depth-fit CALL to
   the edit path. The file is in `Edit/`; the call is not.
4. **The corpus emitter** for the colour latent (CL8's sampler), then
   the metric run.
5. **Depth is 95% of the tensor.** Colour is solved; every remaining
   byte is depth at the precision CT6 fixed. That is a ruling waiting
   to be asked, not a defect.
6. **The device pass**.

## 8. One mistake, recorded

I bundled the mlpackage into the app before rebuilding it, so the app
carried a graph with the previous session's output names while the lab
had the new ones. The parity test failed with `XCTUnwrap failed:
expected non-nil value` — which told me nothing, because the wrapper
lumped a prediction failure in with the two lawful nil cases.

Splitting it took one edit and the next run said, in one line:
`TensorEncode returned unexpected features: ["l16", "sign32", "dev32",
"dev16", "sign64"]`. The decree paid for itself inside an hour.
`TensorANE` now traps in DEBUG on a prediction error, because a graph
compiled for a shape and fed that shape cannot fail for a lawful
reason.
