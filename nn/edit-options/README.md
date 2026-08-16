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

The app ships ONE point of a 32768-point space.
`RoleAllocation.identityEdit` takes the RL4-derived depth split and the
FINE READ ALONE, because the app only uses the 64-cubed stream:
`eCoarse = eMid = 0`.

RL4 is reverse water-filling, `b_i - b_j = half log2 (lam_i / lam_j)`,
which minimises RATE. It has never claimed to make the best picture.

★ MEASURED, AND THE RESULT IS SHARPER THAN "SOME ROWS ARE BETTER".
For every scene whose derived `dGnd` is 5 or below, EXACTLY ONE
allocation strictly dominates the derived point, and it is always the
same move:

    derived            dominated by
    (dFig 7, dGnd 0)   (6, 1)
    (dFig 7, dGnd 3)   (6, 4)
    (dFig 7, dGnd 5)   (6, 6)

That is `(dFig - 1, dGnd + 1)`: move one bit from the figure to the
ground. At an even figure share the two have IDENTICAL rate, 4.5 bits
against 4.5, so this is not a cheaper option, it is the same price for
strictly less truncation error.

It falls out of the law's shape: `derivedAlloc` pins `dFig = treeDepth`
ALWAYS and spends the whole water-filling gap on `dGnd`, so one side of
the trade sits clamped at the ceiling and the exchange is never
considered.

★ AND THE HONEST CAVEAT. This is measured on the synthetic scenes
below, at an even figure share, with cosine-shaped leaves. It is a
property of the law AND of the fixture, and it stays a finding about
this corpus until a real capture says the same thing. It is written
here rather than in a commit message because someone will want to
check it.

Counts of rows beating the derived point on detail, of 32768:

    dGnd-0  7168     dGnd-3  4096     dGnd-6  0
    dGnd-1  6144     dGnd-4  3072     dGnd-7  0
    dGnd-2  5120     dGnd-5  2048

At dGnd 6 and 7 the derived point is already optimal, which is the
law working exactly as intended at the top of its range.

## The corpus

    make corpus-edit          # from spec/, about 2.5 minutes

    8 scenes  x  32768 edits  =  262144 rows  =  64^3

★ WHERE THE EIGHT COMES FROM, because the first draft could not
answer it. That version used eight scenes with invented names,
invented spreads and invented seeds, picked so that
8 x 32768 = 262144 = 64^3. The row count was reverse-engineered from a
sentence somebody wanted to write, and it carried twenty-four naked
constants against a standing decree that forbids them.

The law answers it. `derivedAlloc` reads exactly ONE thing about a
scene, the ratio `lamF / lamB`, through
`dGnd = clamp (treeDepth - halfLog4 (lamF / lamB))`, with `dFig` at
`treeDepth` always. So the derived allocation takes EXACTLY
`widgetCells` distinct values, one per `dGnd` in 0..7, and the complete
scene axis is that enumeration. Each scene is built by inverting
`halfLog4`: a variance ratio of `4^(treeDepth - dGnd)`.

Eight is DERIVED, and 64^3 falls out instead of being aimed at.

The 32768 is NOT a sample either. `editSpace` is the complete
enumeration of five 8-state dials (RoleAllocation, and Octave OV11
"so the edit space stays 8^5"), so every permutation appears exactly
once per scene.

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

★ AND ONE GATE EXISTS BECAUSE IT WAS MISSING. The first draft
PARAPHRASED `derivedAlloc` instead of copying it, inventing a
`base = 4` that appears nowhere in the law and putting the water-filling
gap on `dFig` instead of `dGnd`. Every `derived` flag in that corpus was
wrong, on all 262144 rows. The self-gate did not catch it because it
checked `nodesAt` against the Rational law and not this function: the
arithmetic that was ported carefully got gated, the one retyped from
memory did not. Four gates now cover it, including that `dFig` is
`treeDepth` on every derived point and that the scene axis is complete.

`spec/output/EditCorpusEmit.hs` verifies THIRTEEN properties before it
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
