# Sunset: the funnel, measured

2026-08-15, second session of the day. Read this and
`docs/session-2026-08-15-sunset.md` (the morning's) together: that one
drew the map, this one walked the first road on it and weighed what
was carried.

Everything here is on `main`.

---

## 0. What Daniel asked for, in order

1. "create a 64x64x64 GIF from capture data ... query the data in an
   edit scene so that the iphone can help the user explore the color
   space of their capture. There are many gaps."
2. "because the model can only understand GIF's ... categorize the 256
   colors times 64 frames in terms of deltas, GIF loops and dithering.
   ENERGY! H-JEPA with synthetic data ... it is OK if the preview and
   capture deviate since the capture data is more!"
3. "a series of serious tests. so I know how the information from the
   signal gets funneled ... a raw reading of a series of related
   numbers can be summarized into one bigger number. categorize
   compression into its components. the function map our axioms and
   theorems to test the swift and metal."
4. "there is a relationship between the funnel of signal to edit. These
   categories MUST fit the 64x64x64 BIN tensor idea. so that we can
   function map to an energy knowledge of a 64x64x64 voxel mass
   satisfying the GIF89a format."

Items 1 to 3 are executed or ruled. **Item 4 is the next session and
section 5 states it.**

---

## 1. THE FOUR RULINGS

Recorded in full in `CLAUDE.md` under "THE LOOP HAS AN ENERGY". Two
executed, two open.

| | ruling | state |
|---|---|---|
| R-A | E gets a temporal bond, on the CLOSED loop | EXECUTED |
| R-B | a rotation of Z/64 IS an equivalence (Ruling 7) | EXECUTED as a theorem; encoder owes it |
| R-C | CR3 is scoped to indices and tables | EXECUTED |
| R-D | the model is 64 in, 16 and 4 inside | OPEN, not started |

**R-A**, `spec/statistics/TilingEntropy.hs` TE11 to TE15 +
`Meter/TilingEnergy.swift` + 20 tests. E_time = B_t(1 - h(w_t)) over
the cyclic bonds, B_t = nf*4096 = 262144 at 64 ticks, and the last bond
is the 63 to 0 one. Same law as E_wall over a different set of adjacent
pairs, so no new constant enters.

Why it was needed, stated as the measurement that motivated it: E pools
the histogram and E_wall sums disjoint per-frame bond sets, so both are
SYMMETRIC in the 64 frames. **The app's only closed-form quality
measure scored a GIF and its shuffle identically.** TE13 is now the
axiom that says so, and says it no longer does.

**R-B** is a theorem rather than an assumption (TE12): a cyclic bond
set is carried to itself by a rotation, so w_t cannot move.

★ The statement needed sharpening and its first draft FAILED. Written
as exact equality of the three ENERGIES the axiom is false, because
cWall sums 16 Doubles and a rotation REASSOCIATES that sum. The true
form: exact on every integer observable (pooled histogram, wall
multiset, w_t), and equal to reassociation noise on the floats. The
theorem lives in the combinatorics; the last ulp is an artifact of
adding in an order. Both halves are gated in Haskell and in Swift.

**R-C**: the "byte for byte" wording was false on the day it was
written. The capture path calls `makeGIF(frames:)` and emits PHASE F
and SK GENES; the re-weave path reaches `finish(..., frames: [])`, so
those sections are structurally absent. Scoping CR3 to the PICTURE is
what `CubeStoreTests` always actually asserted, and it unblocks the
CaptureTensor call-site swap, which was staged behind CR3 and nothing
else.

---

## 2. THE FUNNEL, MEASURED

`Meter/FunnelLedger.swift` + `FunnelLedgerTests` (11 tests).

`spec/output/RateLadder.hs` has said since 2026-08-12 that the
content-dependent strata "declare 1 here, their factors are MEASURED
per capture by the RATE LEDGER, not assumed". The RATE LEDGER that
shipped traces five end-to-end numbers and decomposes nothing. **The
factors RateLadder promised to measure had never been measured.**

★ THE FUNNEL IS A DAG, NOT A CHAIN. The latent forks off the same 64
squared colour and rejoins at assignment as the thing indices point
INTO. Three paths, each telescoping exactly (RL2), checked with a
connectivity test beside it so the product cannot telescope vacuously:

```
PIXEL PATH                                    bits in     bits out    ratio
  S0 acquire RGB      G11-G13   DISCARD     226492416      1572864   144.0000
  S4 assign indices   RL1/AD    RECODE        1572864       524288     3.0000
  S5 LZW              RL5       RECODE         524288        97272     5.3899
  telescoped 2328.444115   end to end 2328.444115   connected yes

CODEBOOK PATH
  S2 solve the latent CL1       SUMMARIZE     1572864        14368   109.4699
  S3 grow the palette PT7-PT9   EXPAND          14368        98304     0.1462
  telescoped   16.000000   end to end   16.000000   connected yes

DEPTH PATH
  S0 acquire depth    G11-G13   DISCARD      33554432      2097152    16.0000
  S4b depth to role   AD7/DM    SUMMARIZE     2097152        65536    32.0000
  telescoped  512.000000   end to end  512.000000   connected yes
```

(16-tick fixture, a moving disc over a gradient.)

### 2a. The four KINDS, which are the point

A stratum can reach the same ratio four ways and the rate ladder's
bookkeeping cannot tell them apart. Daniel's phrasing is the design:

- **DISCARD** read one of the 144 and drop the rest. The output is a
  MEMBER of the input, not a function of it.
- **SUMMARIZE** compute one number FROM all 144. The output is a
  function of every input. This is the one Daniel named.
- **RECODE** keep every sample, spend fewer bits on each.
- **EXPAND** spend MORE bits than came in, deterministically.

### 2b. ★ The app DISCARDS more than it SUMMARIZES

The test was first written asserting S2, the latent, was the steepest
stratum. It failed. S2 summarizes at **109.47 : 1**; S0 discards at
**144 : 1**. `Quantize.metal`'s downsampleRGB does ONE `texture.read`
per output pixel, so 143 of every 144 samples never reach the answer,
with no prefilter.

Measured on Nyquist-pitch stripes, the point sample and the box mean it
is not diverge by **127.5 levels of 255** (zero on a constant field, so
the divergence is a property of the SIGNAL, not of the arithmetic).

**The discarded part is the part no edit can ever recover**, which is
why it matters to a session about editing.

### 2c. ★ The codebook path's net ratio is exactly 16

Not a coincidence, and now pinned by a test: 4096 pixels described by a
256-entry table is N/K, and N/K = 16 is the BALANCED OCCUPANCY of TE2,
the ground state of E, the rung. The palette costs exactly one
sixteenth of the pixels it describes because that is what "256 colours
on a 64 by 64" means, read as a rate.

### 2d. The coder, decomposed (TE10)

```
  index plane        524288 b
  E (occupancy)      211676 b   what the palette's own histogram saved
  order-0 bill       312612 b
  LZW actual          97272 b
  the context find   215340 b   runs bought 68.9%
```

TE10 makes the order-0 line an IDENTITY, not an estimate: E = N*8 -
N*H0, so N*H0 = plane - E. Caveat: the fixture is a smooth moving disc
and unusually run-friendly. A real capture will move that 68.9%.

---

## 3. ONE LAW, THREE PORTS: the funnel's entrance

`spec/output/FrameGeometry.hs` G11 to G13 (new) +
`Signal/FrameGeometry.swift` (new, the spec had NO Swift port) +
`MetalGeometryParityTests` (new, no test in this suite had ever touched
Metal's downsample path).

★ THE KERNEL'S OWN CLAIM WAS VACUOUS, and the shape of the mistake is
worth keeping. `Quantize.metal:188-192` says "Port of FrameGeometry.hs
rgbSource/depthSource ... Verified by Haskell axioms G5-G10 for all
4096 output pixels." G5 is bounds, G6 alignment, G7 spacing, and every
one is invariant under a relabelling of the output grid. The kernel
applies a 90 degree rotation that the spec's `rgbSource` does not, and
those axioms pass either way. **They could not have caught it being
wrong.** The rotation lived in the kernel, in a comment, and in no
axiom.

G11 the rotation is a bijection of the output grid, so it moves no
information. G12 it has order exactly four. G13 RGB and depth take the
SAME turn, which is why G6's alignment survives it, and is the axiom
G5-G10 could not have provided: a quarter turn on one stream only would
read every pixel's depth from the wrong place, silently.

★ HOW THE METAL IS ACTUALLY GATED: the test paints each source texel
with its OWN coordinates in rgba32Float, so whatever the kernel writes
to output pixel (i, j) IS the address it read. Exact, all 4096 pixels,
no tolerance. A colour check would have passed for any read inside a
smooth region, which is what the old comment was resting on.

★ WHAT THIS CANNOT SETTLE, said out loud in the test: whether the turn
should be counter-clockwise is a fact about pixel memory layout on a
physical iPhone 17. No axiom and no simulator can answer it. The tests
record the shipped direction AS DATA so a device pass has something to
contradict, and now one edit answers it in all three ports.

---

## 4. CORRECTIONS MADE TO EXISTING WORK

- **`spec/neural/MerkleSearch.hs` probe table was wrong.** It listed
  random static at (E = 0.00, E_wall = 82.64) while claiming to be
  TilingEntropy's own measurements. TE prints (194.94, 0.26), and no
  random frame can score E = 0 (a uniform draw over K bins has expected
  divergence about (K-1)/(2 ln 2) = 184 bits). The axioms passed
  because they quantify over THAT TABLE rather than over TE. **A spec
  that restates another spec's measurements takes on the job of keeping
  them true.** MT8, the load-bearing axiom, survived unchanged; MT7's
  exact-equality half did not and is restated against the measurement.
- **`CLAUDE.md` said `nn/descent` was deleted 2026-08-14.** The
  directory is present, `DescentAssign.mlpackage` included. Corrected
  to "retired as a model path, still on disk".
- **One of this session's own tests was vacuous and is fixed.**
  `testTheCoderSplitsIntoOccupancyAndContext` asserted that occupancy +
  lzw + context reconstitute the index plane. `contextFindBits` is
  DEFINED as order0 - lzw and `order0Bits` as plane - E, so the sum is
  an identity whatever the numbers are: the assertion could not fail.
  It now checks the plane against a figure the ledger did not compute,
  which also exposed that `indexPlaneBits` was hard-coded to 64 frames
  and wrong for every shorter cube.

---

## 5. ★ THE NEXT SESSION: the categories must fit the 64 cubed BIN tensor

Daniel, closing this session:

> "We have found that there is a relationship between the funnel of
> signal to edit. These categories MUST fit the 64x64x64 BIN tensor
> idea. so that we can function map to an energy knowledge of a
> 64x64x64 voxel mass satisfying the GIF89a format."

What exists to build this on, all landed today:

- **The categories.** `FunnelLedger.Kind` = DISCARD / SUMMARIZE /
  RECODE / EXPAND / RETAIN, each attached to a stratum with measured
  bits in and out and the axiom that governs it.
- **The energy.** `TilingEnergy.CubeValue` = (E, E_wall, E_time), three
  disjoint strata over the 64 cubed voxel mass, all in bits, TE15.
- **The tensor.** `Store/CaptureTensor.swift` CT1 to CT11, the 64 cubed
  retained form, ported and tested, call site not yet swapped (R-C
  unblocked that today).
- **The format.** Every export is 64 frames of 64 by 64 indices with
  per-frame LCTs, byte-gated by `DyadGIFContractTests`.

What the next session has to decide, stated as questions rather than
answered:

1. **Is a BIN a voxel, or a bin of voxels?** The name says binning. If
   the 64 cubed mass is binned, the bin count and the bin's own energy
   are the first two numbers to define, and CT2's 262144 bits per rung
   is the budget they must fit inside.
2. **Which category does each voxel carry?** Today a category belongs
   to a STRATUM (an arrow in the funnel), not to a voxel. Function
   mapping the categories onto the voxel mass means every voxel knows
   how its own information arrived: discarded from 143 siblings,
   summarized into a latent, recoded to 8 bits. That is a per-voxel
   provenance field and nothing computes one.
3. **Does the energy become per-bin?** E, E_wall and E_time are
   currently whole-cube scalars. An "energy knowledge of a 64 cubed
   voxel mass" suggests a FIELD, which is also what CL6 concluded from
   the other side (the metric must be a field, not a diagonal). These
   may be the same requirement arriving twice.
4. **What does GIF89a permit?** The constraint "satisfying the GIF89a
   format" is a real bound: 256 entries per frame, 8-bit indices, LZW
   over rows, per-frame LCTs. Any per-voxel field either rides inside
   those bits or rides in the comment, and the comment is where the
   generator already lives.

---

## 6. WHAT IS OWED, ranked

1. **The encoder's rotation debt (from R-B), and it changes bytes.**
   Three shipped behaviours are now defects rather than habits: the
   stats EMA seeds at tick 0 so tick 0 takes raw statistics while tick
   63 is fully smoothed (`DyadPipeline.swift:413-431`); `StrataDescent`
   partitions time linearly with no `mod`; S4's chaos groups have
   "lawful degenerate" tails and a tail cannot exist on a torus. The
   meter obeys the ruling. The encoder does not.
2. **Zero device evidence, still.** Owed since 2026-08-11 and nothing
   here reduces it. The quarter-turn direction (section 3) is now a
   specific, cheap thing a device pass would answer.
3. **R-D, the model.** Not started. Note before starting: the deployed
   head builds 11 dims (`DyadPipeline.swift:752-768`) while
   `nn/jepa/train.py:37` says `RING, DIM = 16, 6`. It ships running
   dims it never trained on, gated by nothing.
4. **`eDist = w + sOcc`** (`Meter/DyadEnergy.swift:76`) sums a
   dimensionless wall fraction with a normalised entropy, against TE8.
   It exists only in Swift, with no axiom behind it. Zero image bytes
   depend on it, but it rides every exported GIF as the only quantity
   in an artifact called an energy, so under "the model reads GIFs" it
   is the first energy signal any corpus would ingest. NOT RULED.
5. **No LZW decoder exists anywhere in the repo**, so an archived
   GIF's index plane is unreadable by any code that exists. The GIF
   carries its generator exactly instead (896 numbers + 128 bits,
   `rebuildTables`), so a GIF-native model reads the GENERATOR, not the
   pixels. Worth deciding deliberately rather than by default.
6. **`Reweave` still has no non-test caller** and the edit tick loop
   does not exist. `.tuning` renders the same scene as `.sealed`.
