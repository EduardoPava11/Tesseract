# V1 UI ARC — SixFour tiling adoption, FACE unification, P0 fixes

**Status: EXECUTED 2026-08-04.** Commits `7181987..c2fd39d` (8 phases, all
pushed). This is the record of the arc; current rules live in CLAUDE.md and
`scripts/lint-grid.sh`. Device-verified: Phase 1 (depth + exports, Daniel).
**Owed: one consolidated device pass of the converted UI (checklist below).**

## What this arc was

Pre-1.0, the app had a proven 4pt-atom lattice (S1+S2, commit `ca86edc`) but
no drawing vocabulary on top of it: glass materials, rounded corners, 17
ad-hoc white-alpha values, sub-11pt fonts, a parallel hand-pixeled FACE UI,
and two launch-blocking P0s. This arc ported SixFour's S3 cell vocabulary,
made every scene layout-as-data, unified FACE into the shared state views,
fixed the P0s, and closed the App Store checklist items.

## The commits

| Commit | Phase | What |
|---|---|---|
| `7181987` | 1 | **P0 fixes.** DepthSignal meters→[0,1] contract (spec DS1–DS4, disparity-affine, dNear 0.25m → 1, dFar 1.5m → 0, invalid → 0.5) on BOTH readback paths; per-frame min/max normalization removed (σ must not flicker across the 64-frame capture). `compose()` re-encodes; `exportCurrent(completion:)` replaces `tapExport` (gene captured BEFORE `.done`); animator publishes per-panel `exportA/B`; `GIFSaver.presentShareSheet` is the ONE share implementation. |
| `7d5b62a` | 2 | **Cell vocabulary** (`Tesseract/UI/Cells/`, 10 files): Ink tokens + TypeRows registry {3,5,7,9,13}, CellText/CellSymbol (AA-off rasterize-and-snap), CellSprite/CellIcon/CellButton, CellSlider/CellActionButton/CellFrameButton, CellChecker/CellBusyTile, CellEase, SurfaceClock (THE one 20Hz CADisplayLink), CellMechanics (the control-face algebra, spec twin `spec/ui/CellMechanics.hs` UM1–UM6), ControlBrackets + ControlFrame. |
| `3be92c0` | 3 | **Layout as data.** 10 proven scenes in GridLayout (disjoint ∧ in-bounds ∧ touch-floor at DEBUG launch); chrome split into per-pill 44pt claims; `controlFaces` map (brackets ONLY for image-content: panelA/B, refineGif, eliteCell0–8); LINT-CONTROL-FACE. |
| `6240599` | 4 | **Conversion: chrome + simple states.** BEAT live (lit 1 tick in 4, reduce-motion pins off); Idle/Recording/Processing/Error/Result/LivePreview/PaletteSwatch on the vocabulary; data-driven signatures (the FACE seam); LINT-DRAW-VOCAB. DELETED: epoch-grid overlay (alpha-over-content). |
| `4936358` | 5 | **DualExplore + Refining rebuilt.** ExplorePanel = 68-cell bracket face, projection strips IN the gutter ring; long-press arming inverts; CellSlider scrubber (detent per frame); cell sparklines; refine tap = busy brackets while re-encoding. DELETED: CubeGIFView (and the in-strip frame indicator; the scrubber knob carries frame position). |
| `b5b65f1` | 6 | **FACE unified.** FaceCaptureView DELETED; `faceBody` maps FaceCaptureState onto the shared state views; FacePreviewStateView + shared BirkhoffGauge; `previewMeasure` published by FaceCaptureManager; FIX: `modeSwitchAllowed` now guards FACE mid-capture. Lifecycle unchanged: `.onChange(of: appMode)` is the sole AVCaptureSession ↔ ARSession owner. |
| `146bf7b` | 7 | **Elite map placed** (eliteMapScene, own gridCentered canvas): nine 20-cell bracket tiles (80pt ≥ the 11-cell floor), selected = inverted, empty = checker; beauty badge moved to a11y label + detail (badges obscure content pixels). |
| `c2fd39d` | 8 | **Ship checklist.** Whole-tree lint governance; PrivacyInfo.xcprivacy (no tracking / no collection / no required-reason APIs, verified bundled); dark + tinted icon variants; versions verified. |

## Laws now in force (enforced by scripts/lint-grid.sh, every build)

- **LINT-PLACEMENT** — `place(_ region:)` is the only positioning.
- **LINT-SINGLE-LATTICE / SINGLE-PITCH** — one atom owner; sizes are
  `Lattice.gif/pt` only.
- **LINT-DRAW-VOCAB** — converted views draw ONLY through Cell*: no
  `.opacity` (except 0), no materials/glass, no RoundedRectangle/Circle/
  stroke/shadow, no bare `Text`, no `ProgressView`. Primitives allowlist:
  `UI/Cells/Cell*`, `PixelGrid`, `SurfaceClock`, `Ink`, `GIFPlayerView`.
- **LINT-CONTROL-FACE** — every `interactive: true` region names a face
  (frame | brackets) in `CellMechanics.controlFaces` (runtime mirror in
  `GridLayout.selfCheck`).
- **LINT-GOLDEN-MECHANICS** — the algebra exists as spec + Swift twin and
  the spec is registered in `spec/Makefile`.

Design invariants worth restating: state is opaque ink transforms, never
alpha (ghost/lit/inverted/busy/checker); only idle reads the clock; brackets
never obscure a content pixel; all chrome timing derives from the ONE 20Hz
tick (`goldenBeat[1] == false` is the reduce-motion anchor).

## Owed: the consolidated device pass

Phases 4–7 are machine-verified only (build + lint + 12 sim suites + scene
selfChecks). On device, check:

1. **LIVE** happy path end to end; BEAT on record ring + unselected pill;
   pills disabled mid-capture; small-register (rows 3/5) legibility.
2. **Dual explore**: swipe steering, long-press compose (brackets invert
   while arming), scrubber detents, per-panel tap-share, elite button
   reachable during explore.
3. **Refining**: rotate α; tap → red brackets → share sheet shows the
   CURRENT composite (not the teacher).
4. **FACE** (doubles as the long-standing first thorough FACE run):
   repeated LIVE↔FACE switching without TrueDepth deadlock; mirroring;
   face dot; full capture → result; mode switch blocked mid-recording.
5. **Elite map**: open from preview + explore; select/animate/share/keep/
   close.
6. **Reduce Motion**: no BEAT, no shimmer anywhere.

Deliberate deletions to veto if missed on device: the epoch-grid preview
overlay; the moving frame-indicator line on projection strips; the per-cell
beauty badge in the elite grid.

## Open for 1.0 (outside this arc)

- Pre-existing sim failures (verified failing at baseline `3d77ae9`):
  `BlockPyramidTests.testSampleCounts_matchLevel`,
  `GeneCapsuleTests.testCapsule_roundTrip`,
  `GeneNNTests.testGenePerturb_producesDifferentOutput`; plus the 4 latent
  AxiomTests (CLAUDE.md known item).
- Audit P1s: LZW decode round-trip test; session-interruption handling.
- Launch screen stays generated (GENERATE_INFOPLIST_FILE: YES is
  load-bearing for signing); light-mode devices see a brief system-white
  flash. Revisit only with a signing-safe plan.
- Deployment target iOS 26.0 — owner's call at submission.
- FACE has no elite-map access (organisms are LIVE-gene artifacts);
  product decision deferred post-1.0.
- nn/refine MLX prototype + saliency U-Net (REFINE-PASSES.md step 4–5)
  continue independently of this arc.
