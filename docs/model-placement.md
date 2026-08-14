# THE MODEL'S PLACE, AND WHAT CAPTURE MUST RETAIN

Daniel, 2026-08-14, two rulings the same day pointing the same way:

> *"follow the scene — match the true motion"*

> *"The model should not dictate HOW we capture. It should help us create the
> data from which we make the editing possible to produce GIFs. You need to
> update the H-JEPA model and ensure that the capture logic is sound. Not
> training yet. Just architecture."*

This document is architecture only. No model was trained, no corpus emitted, no
weights changed. One line of code changed, below.

---

## 0. What changed today

`CameraConfig.jepaH` → **false** (`Tesseract/Camera/CameraManager.swift:123`).

Two independent reasons, one flag:

- **MEASUREMENT.** On the synthetic corpus the head lands at churn **7.921**
  against a true **9.592** — it holds the palette **17.4% steadier than the
  scene actually is**, and sits **2.67× further from truth** than the
  oracle-EMA baseline it replaced (model 1.671 vs EMA\* 0.626). New gate B5 in
  `nn/jepa/train.py`: ✗. Every shipped gate passed because every shipped gate
  compared the model to a *baseline* and none to *truth*.
- **RULING.** Smoothing the ring at `DyadPipeline.swift:378`, before the tables
  solve, is the model deciding bytes at capture time. That is the model
  dictating how we capture.

The attempted repair is recorded and rejected: a per-dim variance-restoring
calibration (≈1.21) passes B5 (0.381 < 0.626) and fails B3 and FID (RMSE
0.05602 → 0.07008). **B3 and B5 cannot both hold for a smoother** — B3 rewards
less motion without bound, B5 requires motion to match truth. Opt-in behind
`B5_CALIBRATE=1`, default off.

---

## 1. Three jobs, one boundary

| | job | may write |
|---|---|---|
| **CAPTURE** | produce sound, complete DATA — the scene's own motion, unsmoothed | the record |
| **PIPELINE** | be the DECODER — data + edit → tables → indices → GIF, deterministically | the artifact |
| **MODEL** | supply COORDINATES a person can move through | nothing |

**The boundary, stated once:** the model sits between the retained data and the
user's hands — never between the sensor and the record. It may read everything
and write nothing. This is WS10's licensing restated at the architecture level
rather than the parameter level.

---

## 2. ★ THE CENTRAL FINDING — editing is impossible today, and not for the
## reason anyone assumed

It is not that the edit surface is missing. **Its input is destroyed.**

- `QuantizedFrame` carries what editing needs: `rawRGB` (64² sRGB triples) and
  `depths` (64² floats), per frame (`Tesseract/Camera/FrameBuffer.swift:11-19`).
- Those frames live in a local `quantizedFrames` array inside the capture
  closure (`CameraManager.swift:715-752`) and are released when the closure
  returns.
- `GIFLibrary.archive` takes a `Data` (`GIFLibrary.swift:29`) — the encoded GIF
  and nothing else.

So within milliseconds of being made, the only copy of the editable data is
freed. Everything downstream — reweave, dials, one-capture-many-GIFs — is
blocked on this and on nothing else.

**The arithmetic.** 64 frames × 4096 px × (3 RGB + 1 depth) × 4 B =
**4,194,304 B = 4.00 MiB** per capture, uncompressed, in the format already in
memory. That is the price of the app being an edit app.

### Capture requirements

- **CR1 — RETAIN, IN THE APP. ★ RULED 2026-08-14:** *"we should not try to put
  any big metadata into the GIF — the data should live in the app, as the user
  should be able to re-edit to make new GIFs."* The cube (RGB + depth +
  per-frame timestamps) persists in the app's own store, keyed to the archived
  GIF. The GIF stays a GIF: it keeps only the small provenance trace it already
  carries (DYAD STATS v3, GROUNDHUE v2, the mixture — bytes, not megabytes), so
  a shared GIF is still self-describing and still small, while the 4 MiB that
  makes it re-editable stays on the device where the editing happens. The
  GIF-internal application-extension option is **withdrawn**.
- **CR2 — THE GENERATOR PERSISTS.** Already true: the GIF carries DYAD STATS v3
  + GROUNDHUE v2 + the mixture, so the table is reproducible from the artifact
  itself. Retention must not weaken this.
- **CR3 — IDENTITY RE-WEAVE IS THE SOUNDNESS GATE.**
  `reweave(cube, identityEdit)` must reproduce the archived GIF **byte for
  byte**. Retention that cannot round-trip is not evidence that the capture was
  sound; it is a second copy of an unknown. CR3 is the only test that proves
  the retained data is the data the artifact came from.

---

## 3. Is the capture logic sound? The audit

Each defect below is listed by what it does to **editability**, which is a
stricter bar than fidelity: a capture can look fine and still be un-editable if
the retained record does not determine the artifact.

| # | defect | evidence | why it blocks editing |
|---|---|---|---|
| C1 | the editable cube is discarded at export | `CameraManager.swift:715-752`, `GIFLibrary.swift:29` | there is nothing to edit — §2 |
| C2 | `rawRGB` is nil in preview, populated only while recording | `FrameBuffer.swift:14` | the live surface and the kept artifact fit on different evidence; EM13's one-encoder law holds for the LAW, not the EVIDENCE |
| C3 | acquisition aliasing: `.photo` preview downscale + 144:1 point-sample | `docs/CAPTURE-FUNNELS.md` | aliased data cannot be un-aliased by any edit; every re-weave inherits it |
| C4 | RGB:depth registration ratio pinned at 3 | `CameraManager.swift:460, :371` (two log lines already exist) | if the delivered ratio is ~1.5 every role decision applies to a mis-scaled region, so the retained roles are wrong and every edit built on them is wrong |
| C5 | NaN cascade on constant per-frame depth | two-phase fit ⇒ temperature +inf ⇒ crossover NaN ⇒ t NaN | FACE reaches it on any tracking drop and unavoidably on frame 0; the frame's own table is poisoned, so the retained record is not re-weavable |
| C6 | dead far branch (`fars` all-false at every production call site) | `DyadPipeline.swift:446, :1096, :793` | the retained roles never exercise a path the laws still describe — the record and the spec disagree about what happened |

C1 is the blocker. C4 and C5 are the two that make retained data *silently*
wrong, which is worse than missing. C3 is irreversible and therefore must be
fixed before any capture worth keeping is taken.

---

## 4. The H-JEPA, re-architected

**OLD (retired today).** Encoder over the 16-slot ring → smoothed state →
tables. It wrote the record: the model chose what the capture said happened.

**NEW — ★ RULED 2026-08-14:** *"the model is a tool for categorizing the
64×64×64 GIF space… trained on synthetic data about composition of the voxels
and their colors and their entropy."*

**The H-JEPA is a CATEGORIZER of cube space.** Not a smoother, not a predictor,
not an assigner. Its output is *where in the space of possible 64³ cubes this
cube sits* — and that coordinate is what the edit surface moves through.

- **Input:** the RETAINED cube (CR1), not the live stream. It never sees a
  frame before that frame is recorded.
- **Output:** a hierarchical latent with **one level per rung**. The *H* in
  H-JEPA is the rung ladder — which the additive law
  (`spec/output/AdditiveLadder.hs`) already proved is the index's own
  structure, so the levels are not a modelling choice but the artifact's:

  | latent level | writes | what moving there does to the picture |
  |---|---|---|
  | 16 | bit 6 | the coarse colour family of whole 4×4×4 regions |
  | 32 | bits 5–3 | the family within each 2×2×2 |
  | 64 | bits 2–0 | the leaf — fine detail only |

- **Decoder:** the SHIPPED PIPELINE. A latent point → the 13 generating numbers
  → `PairTree.solveFigures` → tables → indices. Nothing new decodes anything.
  Every point in the latent lands on a lawful GIF *because the decoder is the
  law* — the model cannot produce an illegal artifact even in principle.
- **When it runs:** at EDIT time. No 20 Hz budget, no ANE dispatch pressure, no
  capture-path risk, no cost to a capture the user never edits.
- **What it may never do:** write the record, alter the retained cube, re-weight
  the energy (E is calibrated, one bit = one bit), or touch palette bytes.

**Why this satisfies the ruling.** The model no longer decides how the scene is
captured. It organises data that already exists into coordinates a person can
move through — which is exactly "help us create the data from which we make the
editing possible."

### 4.1 The corpus — and the fact that it is already specified

*"Synthetic data about composition of the voxels and their colors and their
entropy."* Those three words name coordinates this repo already has laws and
green axioms for. The corpus does not need inventing; it needs emitting.

| Daniel's word | the coordinate | where it is already law |
|---|---|---|
| **composition** | per-stratum conformance + the 8 dyadic rungs of the index | `AdditiveLadder.hs` AD11/AD12, `WeaveState.hs` WS4 |
| **colors** | class occupancy at each rung against the 1024 invariant; the σ/figure split φ | AD4, `TilingEntropy.hs` TE5 |
| **entropy** | E = N·log₂K − N·H₀ in bits, split by stratum; E_wall for arrangement | TE1–TE10, WS3, AD9 |

So a cube's category coordinate is the **33-number weave state (WS6) plus the
four-stratum census (AD11/AD12)** — 33 + 8 numbers, every one of them already
defined, proved, and computable from an emitted cube with no device and no
capture. `AdditiveCensus.swift` already computes the census half on any cube.

**What the corpus must span** — the space, not a walk through it: cubes at
varied E (ordered → balanced), varied conformance (free assignment → lawfully
stratified), varied occupancy (collapsed → all 256 alive), varied role mass
m_g, and varied arrangement coherence (coherent → scrambled, the 2.8× LZW axis).
Emission is a Haskell law file beside the existing three emitters, obeying
NO-CAPTURE-TRAINING by construction: nothing in that list requires a photograph.

**CHOICE — fitted or trained.** The categorizer can be *fitted per capture*
(deterministic, no weights, available immediately — the 41 numbers ARE a
coordinate already) or *learned across the corpus* (an encoder that discovers
which regions of the space are perceptually distinct, so the edit dial moves in
steps a person can see rather than steps that are numerically uniform). The
fitted form ships without a run; the learned form is what the ruling above asks
for, and it is the one training run this architecture needs.

---

## 4.2 ★ THE CAPTURE'S OBJECTIVE — colour diversity, and information flows

**RULED 2026-08-14:** *"the capture should capture color diversity. information
should flow."*

This settles what capture is FOR, which the app has never stated. Capture is not
trying to make a beautiful GIF — the edit makes GIFs. **Capture is trying to
bring back as much distinct colour as the scene contains**, so the edit has
something to move through. That objective is already measurable in this repo's
own currency, and the meters exist:

| the objective | the meter | today's reading |
|---|---|---|
| colour diversity | entries alive per frame / per cube | ceiling **144 of 256**; ground half **10 of 128** |
| diversity by stratum | classes used at each rung vs its level | `ADDITIVE CENSUS v1`, live in every export |
| flow, not loss | E and the rate ledger at each stratum | `RATE LEDGER v1`, live |

**INFORMATION SHOULD FLOW — the principle, stated as a test.** No stage may
destroy information it was not declared to destroy. Every §3 defect is a
violation of exactly this, which is why they belong to one audit and not six:

- **C1** destroys the whole cube, undeclared → the flow ends at the artifact.
- **C3** destroys detail before the pipeline starts (aliasing), irreversibly.
- **C4/C5** corrupt rather than destroy — worse, because the flow continues
  carrying wrong values that nothing downstream can detect.
- **C6** describes a flow that does not happen.

A declared loss is a ratio in the rate ladder. An undeclared loss is a defect.
That is the whole rule, and it is the same rule `docs/rate-ladder-redesign.md`
already applies to the strata — now applied to the capture path.

**MEASUREMENT, and the tension it names.** Diversity and flow are not the same
axis. Balanced-random at rung 64 costs 44686 b where balanced-coherent costs
15894 b — the same diversity, 2.8× the wire. So the capture objective is
*diversity with coherence*: bring back every colour the scene has, arranged the
way the scene arranged it. E_hist and E_wall are independent strata (WS3), which
is precisely what makes that pair achievable rather than a compromise.

---

## 5. What is NOT being done

No training. No corpus emission. No weight changes. `nn/jepa`'s artifacts are
byte-identical to what shipped; the only edits there are the B5 gate and its
opt-in calibration, both measurement.

---

## 6. Rulings

**RULED 2026-08-14**

1. ~~Where retention lives~~ → **in the app**, not in the GIF. No big metadata
   in the artifact; the cube lives in the app's store so the user can re-edit
   into new GIFs (§2, CR1).
2. ~~What the model is~~ → **a categorizer of the 64³ GIF space** (§4), trained
   on synthetic composition / colour / entropy (§4.1), never on the capture
   path (§1).
3. ~~What capture is for~~ → **colour diversity, with information flowing**
   (§4.2).
4. ~~Colour timing~~ → **follow the scene**; `jepaH` off until the
   truth-referenced retrain (§0).

**STILL OWED**

5. **How much is kept.** 4.00 MiB per capture. All captures, the last N, or only
   those the user marks — a user-visible storage decision, and the only ruling
   that gates CR1's implementation.
6. **Fitted or learned categorizer** (§4.1's CHOICE). The fitted form ships
   without a training run; the learned form is what "trained on synthetic data"
   asks for and is the one run this architecture needs.
7. **C3/C4/C5 order.** All three make retained data untrustworthy. C4 and C5 are
   cheap guards; C3 is a pixel change needing a device pass. Retaining a cube
   captured through an un-audited path stores the defect rather than the scene,
   so this ordering question is upstream of CR1's value, not downstream.
8. **Whether the live surface may ever show a model.** With jepaH off the
   preview carries the scene's true motion; re-introducing any model on the live
   path re-opens the boundary §1 just drew.
