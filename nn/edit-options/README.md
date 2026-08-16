# nn/edit-options: the lab that proposes better GIFs

Daniel, 2026-08-16, on what this model is for:

> "Keep the model as a tool in the edit phase. Ie when we have encoded
> the capture in a tensor. Ie Bins so generate better detailed options"
>
> "An large set of generated data. Size 64^3 all possible permutations"
>
> "I want the model to help me build the best 64^3 voxel gifs."

## The one thing this model does

It runs in the EDIT phase, after capture is encoded, and it proposes
edits worth looking at. It does not run at capture time, it does not
decide a byte, and nothing the app exports depends on it being right.
The chosen edit is always re-rendered exactly.

## Why it has a job at all, measured rather than assumed

The app ships ONE point of a 32768-point space and that point is a
corner. `RoleAllocation.identityEdit` takes the RL4-derived depth split
and the FINE READ ALONE, because the app only uses the 64-cubed stream:
`eCoarse = eMid = 0`.

★ AND THE DERIVED POINT IS DERIVED FOR THE WRONG THING. RL4 is reverse
water-filling, `b_i - b_j = half log2 (lam_i / lam_j)`. That minimises
RATE. It has never claimed to make the best picture.

Measured on the corpus, edits strictly better than the shipped point on
truncation error, out of 32768 per scene:

    flat-ground        5632        chroma-heavy       7680
    warm-face          7680        dim-room           7680
    high-contrast      7680        backlit            9728
    near-monochrome    7680        even-light         7680

So roughly 7700 lawful options per capture beat the one on screen for
detail, and today you cannot see any of them. That is the gap this
model exists to close.

## The corpus

    make corpus-edit          # from spec/, about 2.5 minutes

    8 synthetic scenes  x  32768 edits  =  262144 rows  =  64^3

The 32768 is NOT a sample. `editSpace` is the complete enumeration of
five 8-state dials (RoleAllocation, and Octave OV11 "so the edit space
stays 8^5"), so every permutation appears exactly once per scene.

Emitted to `corpus/edits.jsonl`, one row per line:

    scene      which synthetic capture
    edit       [eFig, eGnd, eCoarse, eMid, eFine], each 0..7
    colours    distinct colours realised (coloursUsed)
    rate       expected index width in bits (rateBits)
    distFig    mean squared truncation error, figure half
    distGnd    the same, ground half
    derived    whether this row IS the RL4 point for the scene

`corpus/manifest.json` pins the shape. The corpus is gitignored, like
every other emitted corpus in this repo.

## Self-gating

`spec/output/EditCorpusEmit.hs` verifies NINE properties before it
writes a byte, and aborts on any failure, following the SKCorpusEmit
contract. Among them: the space really is 8^5 with no repeats, the
corpus really is 64^3 rows, truncation at full depth is lossless,
truncation error is MONOTONE in depth (so the dial means something),
and the emitter's Double arithmetic agrees with RoleAllocation's own
Rational law on every scene at every depth.

That last one is the point of the design: exact where it is law, fast
where it is data. Rational arithmetic over 262144 renders is not
something to wait for, so the Double path carries the work and the
Rational path proves it did not drift.

## What is NOT here yet, said plainly

- **The preference.** Every label in the corpus is exact arithmetic.
  Which of two lawful edits looks BETTER is a human judgement and this
  lab does not invent one. Until that signal exists the model can only
  learn the rate-distortion surface, which the arithmetic already gives
  exactly, so THERE IS NOTHING WORTH TRAINING YET.
- **Real scene features.** The eight scenes are 128-leaf trees on the L
  axis with a figure share. A real capture's features are the retained
  generator, 64 x (14 numbers + 2 bits). Widening the scene model is the
  next emitter change, not a trainer change.
- **The octave dials do nothing in these rows.** `eCoarse`, `eMid` and
  `eFine` are enumerated and carried, but the current measures depend
  only on the two truncation depths, so all 512 octave settings of a
  given `(eFig, eGnd)` share a label. That is honest rather than
  hidden: making them bite needs the three parallel reads in the
  emitter, and it is the largest single gap in this corpus.
