# UI/UX LINE PASS — 2026-08-12

Full-coverage audit: every app Swift + Metal line (61 files, 9,945 lines;
coverage verified against wc -l), 10 reviewers + adversarial verification
+ completeness sweep. 77 confirmed findings, 1 refuted.

Severity: P0 user-visible bug / broken invariant · P1 should fix · P2 polish.
LOOK = fix changes rendered pixels/layout (needs Daniel's device ruling).

## [0] P2 safe — Tesseract/UI/Cells/PixelGrid.swift:9
**Doc comment (and the filename itself) reference `PixelImage` and a `PixelGrid` Canvas primitive that do not exist anywhere in the codebase; the file contains only the pixelFrame() extension.**

Verdict: CONFIRMED — Verified: grep over Tesseract/ finds no PixelImage type and no PixelGrid declaration anywhere; the file body is only the pixelFrame() View extension (lines 13-21). The palette is drawn by CellPalette via CellSprite (CellPalette.swift:19), which is CGContext-bitmap-based, not Canvas — so both named primitives and the drawing technology in the comment are phantoms. scripts/lint-grid.sh:51 keeps the filename load-bearing in the is_primitive allowlist. Charter 3 counts stragglers from excised paths as findings; this is doc-level only, so P2 is right.

Fix: Rewrite the scope comment to name the real primitives (GIFPlayerView for the 64x64 bitmap, CellSprite/CellPalette for the 256-cell palette — note CellSprite is a CGContext bitmap, not Canvas). If renaming the file to PixelFrame.swift or folding pixelFrame() into CellChrome.swift, update the is_primitive case at scripts/lint-grid.sh:51 and the prose list at lint-grid.sh:21 in the same commit, or the primitive exemption silently lapses.

## [1] P2 safe — Tesseract/UI/Cells/PixelGrid.swift:19
**pixelFrame()'s border `width: 1` is a raw point constant that derives from neither the atom (4pt) nor the half-atom (2pt) — the only bare non-lattice size in the UI layer.**

Verdict: CONFIRMED — Line 19 reads `.border(Color(srgb8: Ink.frameStroke), width: 1)`. TesseractLattice bottoms out at subPt = 2; no lattice constant owns 1pt. It escapes LINT-SINGLE-PITCH because that check only scans .frame/.padding/spacing:/minLength: lines (lint-grid.sh:82) and PixelGrid.swift is an is_primitive file besides. Ink.swift:27 blesses 'the 1pt frame' in prose only — that documents the color token, not a lattice owner for the width. Checked the rest of the UI layer: every other numeric width/height is Lattice-derived or CGContext pixel math, so 'only bare non-lattice size' holds. Not a documented ruling in CLAUDE.md, so not REFUTED; charter 1 says every visual size derives from the lattice.

Fix: Add `static let frameStrokePt: Int = 1` to TesseractLattice (documented as the sanctioned sub-atom hairline, with a selfCheck precondition frameStrokePt < subPt) and write `width: CGFloat(TesseractLattice.frameStrokePt)` at PixelGrid.swift:19 — same rendered pixels, no orphan literal. Do NOT widen to Lattice.pt(1)=2pt without Daniel's device ruling: that changes pixels around all six pixelFrame() consumers.

## [2] P2 safe — Tesseract/UI/Cells/CellChecker.swift:9
**CellChecker.bright is dead: it is never referenced anywhere in the app, and its value (235,235,235) duplicates Ink.ink.**

Verdict: CONFIRMED — grep for 'bright' across Tesseract/ and TesseractTests/ returns exactly one hit: the declaration itself (CellChecker.swift:9). CellBusyTile's lit default is Ink.ledGhost (line 31), not bright; CellChecker.ink takes lit/ghost as parameters, so nothing routes through bright. Ink.ink is (235,235,235) (Ink.swift:10) — exact duplicate. Charter 3 makes vestigial code a finding; P2 is right for a one-line dead constant.

Fix: Delete `static let bright` at CellChecker.swift:9 (or alias it to Ink.ink if a lit checker parity is wanted later, so the byte value keeps one owner).

## [3] P2 safe — Tesseract/UI/Cells/CellChecker.swift:10
**CellChecker.dark (16,16,16) has escaped its checker role and serves as the app's de facto background/void ink in six governed views, bypassing the Ink vocabulary that is supposed to own all chrome color.**

Verdict: CONFIRMED — Verified all seven non-declaration call sites: LivePreviewStateView.swift:59, FacePreviewStateView.swift:72, RecordingStateView.swift:37 (preview-placeholder fills), LibraryView.swift:89/104 (thumbnail placeholder + empty tile), ProcessingStateView.swift:55 (Go-board .empty cell), CellPalette.swift:20 (short-table fallback) — none is 2x2 parity math; only CellBusyTile's ghost default (CellChecker.swift:32) is genuine checker role. Ink.swift:4-7 declares ALL chrome color routes through Ink tokens; a checker constant moonlighting as the void ink is exactly the charter-6 consistency gap claimed. P2 correct: value is consistent everywhere, so no user-visible defect.

Fix: Promote the value into Ink (`static let void = SIMD3<UInt8>(16, 16, 16)`), make CellChecker.dark an alias of Ink.void, and repoint the seven non-checker call sites (LivePreviewStateView:59, FacePreviewStateView:72, RecordingStateView:37, LibraryView:89 and :104, ProcessingStateView:55, CellPalette:20) at Ink.void; leave CellBusyTile's ghost default on the CellChecker alias since that one IS the checker role. Identical bytes, no device ruling needed.

## [4] P2 safe — Tesseract/UI/Lattice/GridLayout.swift:94
**TesseractLattice.buttonRowCells (13, 'the standard action-button height') is not referenced by any of the ~14 GridRegions that embody it — every action row hard-codes h: 13, so re-ruling the standard would silently desync the scenes.**

Verdict: CONFIRMED — The claim itself holds, but the audit's evidence line 'zero call sites outside TesseractLattice.swift' is wrong: TesseractTests/LatticeLawTests.swift:31 (testButtonsMeetTheUpscaledRow) does consume buttonRowCells. That test asserts max(r.w, r.h) >= buttonRowCells for interactive regions — and every action row is 24-28 cells wide, so the width satisfies the bound regardless of height. Concretely: re-ruling 13 to 15 leaves every hard-coded h: 13 row passing (max widths 22-28 all >= 15), and shrinking a row to h: 11 also passes (min still meets the 11-cell touch floor). So the constant genuinely cannot pin the 14 hard-coded h: 13 declarations (GridLayout.swift lines 49, 94-96, 118-119, 132-133, 136-140, 164-166), and GridLayout.selfCheck (196-208) pins only preview/record. CLAUDE.md's UI section explicitly credits the 11-to-13 upscale to TesseractLattice.buttonRowCells, yet the constant is decorative at the declarations. Silent-desync claim survives; P2 stands.

Fix: Write `h: TesseractLattice.buttonRowCells` at the 14 action-row GridRegion declarations, or add a selfCheck/LatticeLawTests assertion that pins the HEIGHT exactly (r.h == buttonRowCells for the standard action rows) — the existing testButtonsMeetTheUpscaledRow uses max(w,h) >= buttonRowCells, which the widths satisfy vacuously and so cannot catch a re-rule. Note LatticeLawTests.swift:31 already references the constant; the gap is that the bound is too weak, not that the constant is unreferenced.

## [5] P2 safe — Tesseract/UI/Lattice/GridLayout.swift:46
**The empty `chrome` array and its five `chrome + [...]` concatenations are a vestige of the excised shared-chrome layer the SIMPLICITY DECREE deleted, and the pattern is applied inconsistently besides.**

Verdict: CONFIRMED — Verified in GridLayout.swift: line 46 declares `static let chrome: [GridRegion] = []` under the 'no shared chrome' SIMPLICITY comment; it is prepended at exactly lines 74 (recordingScene), 87 (processingScene), 100 (resultScene), 111 (idleScene), 121 (errorScene) and absent from captureScene, facePreviewScene, settingsScene, libraryScene — the split is a no-op that communicates a scene distinction that does not exist. grep confirms no other consumer of GridLayout.chrome anywhere (app or tests), so deletion is mechanical. Charter 3 counts vestigial code paths as findings; the decree comment at lines 43-45 survives the deletion, so the fix breaks no decree. P2 correct.

Fix: Delete the `chrome` declaration at line 46 and the five `chrome + ` prefixes at lines 74, 87, 100, 111, 121; the SIMPLICITY DECREE comment at lines 43-45 stays as the record. No other code references GridLayout.chrome, and the scene arrays are byte-identical after the change.

## [6] P0 LOOK — Tesseract/UI/Cells/CellText.swift:55
**CellText clips lowercase descenders at every register: the raster bitmap height is `rows` but SF Mono bold's line bottom (ascender − descender) exceeds it, so g/j/p/q/y are amputated.**

Verdict: CONFIRMED — Reproduced the metrics exactly on this machine (monospacedSystemFont bold): rows 7 → line bottom 8.244, rows 9 → 10.600, rows 11 → 12.955, rows 16 → 18.844 — all exceed h = rows, and draw(at: .zero) puts the baseline at ascender (≈0.97·rows), leaving 0.23 px of descender room at the label register, so descenders are fully cut with AA off. Lowercase really flows through these registers today: ErrorStateView.swift:25 (body message) and :59 (label sentence lines, the two-register voice), LibraryView.swift:46 'no gifs yet — record one', FacePreviewStateView.swift:88 'face'/'no face' and :97 'anatomical cadence…'. Only all-caps state words are pinned (SurfaceMachineTests.swift:118), which is why no gate sees it. Nothing in CLAUDE.md documents deliberate descender amputation; the charter's own error-voice surface is the victim, so P0 stands.

Fix: Keep h = rows but draw at y = CGFloat(rows) − (font.ascender − font.descender) so the descender band lands inside the bitmap; caps keep headroom at every register (offset + ascender − capHeight ≥ 0.59 px even at rows 7, and cap tops still start below y = 0 + margin). No golden rasters pin lowercase — SurfaceMachineTests' caps-word fit checks keep passing since mask dimensions are unchanged. Needs a device pass: every lowercase label shifts up 1–3 source pixels and grows descenders.

## [7] P1 safe — Tesseract/UI/Cells/CellMechanics.swift:62
**controlFaces still carries "lookDyad"/"lookRefine"/"lookTess" — stragglers from the LOOK radio deleted by the 2026-08-12 per-frame-palette decree.**

Verdict: CONFIRMED — Lines 62–64 are the only occurrences of these names anywhere in the repo (grep over Tesseract/, TesseractTests/, spec/); GridLayout.swift has no look* regions; CLAUDE.md records 'the SettingsView LOOK radio was deleted 2026-08-12'. The lint is one-directional (GridLayout.selfCheck line 205 checks region → face only), so dead keys pass silently, and the simplicity decree explicitly makes stragglers from excised features findings. CellMechanicsParityTests.swift:56 only asserts values are frame|brackets, so deleting the keys breaks no pin. P1 fits: real, should fix, not breaking.

Fix: Delete the three entries (CellMechanicsParityTests only checks values, so nothing re-pins). For the reverse direction, add a check in GridLayout.selfCheck — which already sees both tables — that every controlFaces key names a region in some allScenes scene, restoring the 'closed table' claim in the lines 51–54 comment.

## [8] P1 safe — Tesseract/UI/Cells/CellSprite.swift:89
**CellButton's disc fill is a raw `SIMD3(255, 255, 255)` literal, bypassing the Ink vocabulary and creating two different whites on one control.**

Verdict: CONFIRMED — Line 89 is exactly as claimed and Ink.swift has no full-white token — the header comment on Ink says 'ALL chrome color in the app routes through these tokens', so this is a literal rule-6 violation. Both callers (LivePreviewStateView.swift:80, FacePreviewStateView.swift:106) drive the ring between Ink.ink (235) and Ink.ledGhost, so the beat-lit ring at 235 sits against a 255 disc on the same button, and the disabled checker (line 99) uses fill(255)/ledGhost where the shared face algebra's checker (CellControlFace.swift faceInk case default) uses Ink.ink/ledGhost. No ruling documents the 255 white; the file's own doc (lines 71–77) covers geometry only.

Fix: Hoist to a named token — e.g. `Ink.shutter = SIMD3<UInt8>(255, 255, 255)` with a doc line stating the shutter disc is deliberately the one full-white element (byte-identical, no look change). Unifying on Ink.ink instead would change rendered pixels on the shutter and needs Daniel's device ruling; do not fold it into this fix.

## [9] P2 safe — Tesseract/UI/Cells/CellSprite.swift:22
**CellBitmap bakes chrome colors into an untagged DeviceRGB context, undercutting Ink's explicit byte-for-byte sRGB contract for color-bearing sprites (notably the CellPalette swatch that displays the GIF's table).**

Verdict: CONFIRMED — Line 22 uses CGColorSpaceCreateDeviceRGB() while Ink.swift:33–34 states the contract: 'EXPLICIT .sRGB space so on-screen chrome matches the GIF's color table byte-for-byte'. CellText/CellSymbol also use DeviceRGB but are template masks whose color comes from foregroundStyle(Color(srgb8:)), so only CellSprite carries real bytes — and CellPalette (line 23) pushes the actual 768-byte table through it. On current iOS untagged/DeviceRGB is rendered as sRGB, so no pixels differ today; this is a contract-hygiene finding, correctly P2.

Fix: Create the context with `CGColorSpace(name: CGColorSpace.sRGB)!` in CellBitmap.image (and, for hygiene, in CellText.snap and CellSymbol.snap). No pixels change on current iOS; the tag makes Ink's contract hold by construction.

## [10] P2 safe — Tesseract/UI/Cells/CellPalette.swift:25
**The accessibility label claims "Color palette, 256 entries" even when the table is nil/short and only the placeholder checker is rendered.**

Verdict: CONFIRMED — Line 25 applies the label unconditionally on the CellSprite; line 20 renders CellChecker.dark whenever table == nil || count < 768. The processing scene feeds it liveTable, which is nil before DyadPipeline's first onFrameTable publish, so during early SOLVING VoiceOver announces a 256-entry palette that is not on screen — a real charter rule-5 miss, minor in duration, so P2 is right.

Fix: Make the label conditional on a full table: `(table?.count ?? 0) >= 768 ? "Color palette, 256 entries" : "Color palette forming"` (matches the checker guard exactly, lowercase sentence register) — or accessibilityHidden(true) until the first table arrives.

## [11] P2 safe — Tesseract/UI/Cells/CellChrome.swift:36
**CellSymbol's rasterization uses a naked `* 0.82` point-size constant, violating the no-naked-constants decree in a Cells primitive.**

Verdict: CONFIRMED — Line 36 is exactly as claimed and every other dimension in the file derives from box/cell/Lattice; the site is reachable (ResultStateView passes symbol: keepSymbol through CellFrameButton line 89). One mitigating fact the audit missed: lines 51–53 aspect-fit the symbol into the box and draw(in:) re-rasterizes the vector at that size, so 0.82 only selects the symbol's optical variant/aspect, not the final cell size — which keeps this at P2 hygiene rather than a size bug.

Fix: Name and document it: a `symbolFit` constant on CellSymbol with a comment stating it picks the SF Symbols optical scale (the box aspect-fit at lines 51–53 sets the final size regardless), keeping the numeric value so no pixels change.

## [12] P2 safe — Tesseract/UI/Cells/CellSprite.swift:84
**CellButton's inline lattice comments are stale from before the 2026-08-10 upscale: `recordCells // 18` (actual 22) and `discR … // 7` (actual 9).**

Verdict: CONFIRMED — Line 84 comments `// 18` and line 87 comments `// 7`, but TesseractLattice.swift:46–47 pins recordCells = 22 and recordDiscCells = 18 (so discR = 9), and the header doc at lines 71–77 already states the correct 22/18/9/2 closure law — the inline numbers contradict the file's own doc in the layer where every number must be exact. Line 88's `// 2` is correct.

Fix: Update the two inline comments to `// 22` (line 84) and `// 9` (line 87); line 88's `// 2` stays.

## [13] P2 safe — Tesseract/UI/Cells/CellControlFace.swift:38
**ControlBrackets' doc comment still names the excised A/B and MAP-Elites surfaces ("the dual-explore panels, the refining GIF, elite cells") as its use cases.**

Verdict: CONFIRMED — The ghost text is at CellControlFace.swift:36–37 (the finding cites line 38, one off but the same doc block); those arcs are recorded as excised in CLAUDE.md's 2026-08-10 submission cleanup, and the component's only live consumer is LibraryView.swift:93 (the libCell* tiles, brackets per CellMechanics.controlFaces lines 70–72). Doc-only straggler, P2 is right.

Fix: Reword the doc block at lines 36–38 to name the live consumer — "controls whose content IS an image (the library's GIF tiles)" — keeping the never-obscure-a-content-pixel rationale.

## [14] P0 safe — Tesseract/Views/GIFPlayerView.swift:52
**updateUIView ignores data changes, so the library detail player keeps playing the FIRST selected GIF forever — tapping another tile moves the selection brackets but never changes the playing GIF.**

Verdict: CONFIRMED — updateUIView is empty (GIFPlayerView.swift:52-54). In LibraryView the player sits inside 'if let data = selectedData' (line 34) at stable structural identity; select(_:) swaps selectedData A→B without the branch going nil, so SwiftUI diffs the same representable and calls updateUIView, leaving the old animationImages on the UIImageView. Worse than claimed: CellPalette and infoLines are plain SwiftUI and DO update, so the displayed palette and provenance mismatch the still-playing old GIF. ResultStateView is unaffected because .done is torn down between captures.

Fix: Either rebuild the animation in updateUIView when data differs (store the last-decoded Data in a Coordinator, re-run the decode on change), or in LibraryView add .id(selected) to the GIFPlayerView so a selection change forces makeUIView. The .id route is one line and matches the tile-selection identity already in scope.

## [15] P0 safe — Tesseract/Views/LibraryView.swift:84
**The library grid decodes up to nine GIF thumbnails from disk on the main actor at 20 Hz — up to 180 file opens + first-frame decodes per second, continuously, for as long as the library is open.**

Verdict: CONFIRMED — tile(index:) calls GIFLibrary.thumbnail(of:) in body (line 84); thumbnail (GIFLibrary.swift:80-83) creates a fresh CGImageSourceCreateWithURL and decodes frame 0 with no cache. Body re-evaluates every tick because tiles read clock.tick (line 95) and closeButton reads it (line 151); SurfaceClock is @Observable with tick mutating at 20 Hz via CADisplayLink (SurfaceClock.swift:25,61-65). GIFLibrary.palette(of:) (line 40) and mixtureLine's full-file Data.range scan (line 113) also re-run per tick. All on the main actor — charter 7 (20 Hz loop, heavy @MainActor work) is violated; this is jank plus battery drain while the library is open.

Fix: Cache thumbnails in @State [URL: CGImage] populated in reload(), and memoize the palette Data and mixture line in select(_:). CellText already caches rasters, so with these two memos the per-tick body reduces to cheap cached reads for the chrome clock.

## [16] P1 LOOK — Tesseract/Views/LibraryView.swift:117
**The DYAD MIXTURE provenance line (~150 chars) rendered as single-line CellText at the micro register is ~720 pt wide — it overflows the 352 pt libInfo region and runs off the 400 pt grid canvas and the screen.**

Verdict: CONFIRMED — GIFMachine.dyadTrace's DYAD MIXTURE line (GIFMachine.swift:106-111) is ~150 chars; GIFLibrary.mixtureLine returns up to ~200 chars of it. CellText rasterizes monospaced bold at font size rows=4 (≈2.4 px/char) and displays at cell = Lattice.pt(1) = 2 pt (CellText.swift:17,51-54), ≈4.8 pt/char → ≈720 pt for the line. libInfo is w:88 cells = 352 pt (GridLayout.swift:163); .place sets a frame but nothing clips (Place.swift:13-20), so the centered oversize child escapes the 400 pt canvas. SurfaceMachineTests' fit teeth cover only machine words.

Fix: Wrap the mixture line into the region using the existing ErrorStateView.wrap(_:width:) at a character budget derived from libInfo.w and the micro-register advance (88 cells / ~2.4 cells-per-char ≈ 36+ chars/line, 12-cell-tall region fits 2-3 micro rows plus the size line), or display only the short ruled form (phases, mStar, alpha) and leave the full line in the file bytes.

## [17] P1 LOOK — Tesseract/Views/LibraryView.swift:36
**The library detail GIF displays the 256×256 px export in a 44-cell (176 pt) frame — 2.0625 device px per GIF pixel @3x — so nearest-neighbor produces uneven pixel columns, breaking the atom = GIF pixel law.**

Verdict: CONFIRMED — libDetailGif is 44×44 cells (GridLayout.swift:161) = 176 pt = 528 device px @3x over a 256 px GIF = 2.0625 px/px, i.e. 8.25 device px per 64-plane index pixel — non-integer, so nearest-neighbor renders visibly uneven pixel columns. The constitution's premise is 'the atom IS the GIF pixel' (TesseractLattice.swift:7-11); preview and result both display at 64 cells (exactly 3 device px per GIF px, 12 per index px), and the 16-cell tiles are also commensurate (3 px per index px) — the detail pane is the sole non-commensurate GIF surface. The 44-cell claim is lattice-derived, so this is the aesthetic law not the strict-grid rule; P1 stands because the whole app identity is the hard pixel.

Fix: Make libDetailGif's side a multiple of 16 cells so device px per 64×64 index pixel is an integer @3x (cells×12/64 ∈ ℤ): 48 cells (192 pt, 9 device px per index pixel) fits the current layout (col 6 + 48 = 54 < palette col 56; row 104 + 48 = 152 touches libInfo without overlap). Needs Daniel's layout ruling since it resizes the detail pane.

## [18] P1 safe — Tesseract/App/ContentView.swift:188
**The .unknown refusal path prints raw system/config strings as the lowercase explanatory register — e.g. 'Cannot add camera input' (capitalized) and ARKit's localizedDescription — breaking the two-register error voice.**

Verdict: CONFIRMED — Line 188 passes detail straight through for .unknown; SurfaceMachine.refusal defaults unmatched messages to .unknown(message) (SurfaceMachine.swift:107). CameraManager.configureSession returns capitalized literals 'Cannot add camera input' / 'Cannot add video output' / 'Cannot add depth output' (CameraManager.swift:279,295,301) and FaceCaptureManager posts error.localizedDescription verbatim for non-auth ARErrors (FaceCaptureManager.swift:468) — the same file's comment explicitly says raw system strings should not be echoed. One evidence correction: length is NOT unbounded on screen — ErrorStateView.detailLines word-wraps at 36 chars (ErrorStateView.swift:56-64) — but system-cased localized text in the lowercase register is a real charter-4 violation.

Fix: Map .unknown to one ruled lowercase sentence (e.g. 'the camera session failed, try again') and keep the raw string in the logger only (FaceCaptureManager already logs it); lowercase the three configureSession literals to match the ruled-message constants pattern.

## [19] P1 LOOK — Tesseract/Views/SettingsView.swift:120
**Ink.ledGhost (40,40,40) on the black canvas is ~1.4:1 contrast — the OFF-state toggle text, the unselected camera mode word, and the library hints are functionally invisible to low-vision users (WCAG needs 4.5:1).**

Verdict: CONFIRMED — Verified: ledGhost = SIMD3(40,40,40) (Ink.swift:12) on Color.black computes to ≈1.42:1 relative-luminance contrast. Sites confirmed: whole toggle label when off (SettingsView.swift:119-120), unselected mode word (102), CAMERA caption (31), LibraryView empty hint (46-47) and infoLines (116-117) — and additionally the error detail register itself (ErrorStateView.swift:59), which makes every explanatory error sentence near-invisible too. Ink.swift's 'replaces every white-with-alpha dim' comment documents the porting decision, not an accessibility ruling; charter 5 makes this a real finding.

Fix: Raise the ghost token toward ~120 gray (rgb(120,120,120) on black ≈ 4.8:1, passing 4.5:1) or keep titles in Ink.ink and reserve ledGhost for the ON/OFF suffix only. One token line recolors every secondary label including error details — needs Daniel's device ruling.

## [20] P2 safe — Tesseract/App/ContentView.swift:192
**resultPlaceholder is an unreachable vestigial branch that speaks an off-machine word ('NO GIF') in an un-placed, clock-less VStack.**

Verdict: CONFIRMED — Verified on both managers: CameraManager enters .done only when gifData != nil (CameraManager.swift:711-716), FaceCaptureManager routes nil encode to .error(encodeFailedMessage) (FaceCaptureManager.swift:413-414). gifMeasure cannot be nil when gifData is non-nil (encode requires non-empty quantizedFrames, and measure is built whenever frames are non-empty — CameraManager.swift:666-673, FaceCaptureManager.swift:369-376), so the 'if let gifData, let measure' guard always succeeds in .done. 'NO GIF' is not a SurfaceMachine word (SM1 gives SEALED for .done); the VStack claims no GridRegion and hardwires tick: 1.

Fix: Delete resultPlaceholder and both else-branches at the .done cases (ContentView.swift:144-146, 247-249); optionally assert gifData+measure in DEBUG. The nil-encode path already surfaces as the EXPORT FAILED refusal.

## [21] P2 safe — Tesseract/App/ContentView.swift:36
**Color.black literals (ContentView 36/109/214, SettingsView 24, LibraryView 24) bypass the Ink srgb8 vocabulary that the charter says all chrome color must route through.**

Verdict: CONFIRMED — Verified: exactly five Color.black sites (ContentView.swift:36,109,214; SettingsView.swift:24; LibraryView.swift:24) and Ink.swift declares 'ALL chrome color in the app routes through these tokens' (Ink.swift:4-5) with no canvas/void token. These are the only non-Ink SwiftUI color literals in the chrome (CellText's internal UIColor.white is a template-mask implementation detail, not chrome ink). Cosmetic vocabulary gap, byte-identical fix.

Fix: Add 'static let void = SIMD3<UInt8>(0, 0, 0)' to Ink and replace the five sites with Color(srgb8: Ink.void).ignoresSafeArea() — byte-identical pixels, closes the vocabulary.

## [22] P2 safe — Tesseract/App/ContentView.swift:107
**liveBody and faceBody are ~50-line hand-copied twins of the same state switch — LIVE/FACE parity (charter 9) holds only by manual discipline, and the pair must be edited in lockstep on every scene change.**

Verdict: CONFIRMED — Verified: lines 107-154 and 212-257 are parallel switches over CameraState/FaceCaptureState with identical Recording/Processing/done/error wiring. Slight overstatement in the evidence: they differ in THREE places, not one — the manager, boards (camera.processBoards vs nil), and the preview scene view (LivePreviewStateView vs FacePreviewStateView) — so an extraction must parameterize the preview view too. Parity currently HOLDS (no user-visible violation today), making this a preventive maintainability finding, correctly P2.

Fix: Extract one generic stateBody(state:previewImage:previewScene:gifData:measure:boards:progress:phase:table:onAgain:restart:reshoot:) taking the SurfaceMachine-mapped state (both enums already map case-for-case through SurfaceMachine), with the preview scene passed as a @ViewBuilder closure — the one intended divergence stays explicit.

## [23] P2 safe — Tesseract/Views/LibraryView.swift:130
**DELETE permanently removes the archived GIF on a single tap — no confirmation, no undo — for the app's only copy of a capture.**

Verdict: CONFIRMED — Verified: deleteButton (LibraryView.swift:130-145) calls GIFLibrary.delete(selected) directly; GIFLibrary.delete is try? FileManager.removeItem (GIFLibrary.swift:49-51). DELETE sits in the same button row as SHARE (libDelete col 59 vs libShare col 14, same row 168 — adjacent action row), and the library holds the only copy unless the user previously shared/saved. No decree rules single-tap destruction; the proposed on-grid arming fix does not violate the simplicity decree (no system dialog, no new chrome).

Fix: Arm in two taps using the existing vocabulary: first tap flips the CellFrameButton to the reject state with the word 'DELETE?', second tap within a ruled beat count (derive from clock ticks, no naked constant — e.g. one 20-tick second) deletes; any other tap disarms.

## [24] P2 safe — Tesseract/Views/LibraryView.swift:102
**The selected library tile exposes no .isSelected trait — VoiceOver users cannot tell which of the nine tiles the detail pane is showing.**

Verdict: CONFIRMED — Verified: tile(index:) sets only .accessibilityLabel("GIF n of m") (LibraryView.swift:102); selection is conveyed solely by ControlBrackets state (line 94), which is decorative. SettingsView.modeRow establishes the in-repo pattern: .accessibilityAddTraits(selected ? .isSelected : []) (SettingsView.swift:110). Straightforward charter-5 gap.

Fix: Add .accessibilityAddTraits(url == selected ? .isSelected : []) to the tile Button, matching the modeRow pattern.

## [25] P2 safe — Tesseract/Views/LibraryView.swift:61
**Only the latest nine GIFs are ever reachable; older exports accumulate invisibly and undeletably in Documents/Library forever — unbounded storage with no surface.**

Verdict: CONFIRMED — Verified: reload() takes prefix(9) (LibraryView.swift:61), no paging exists, and GIFLibrary.archive writes every successful export (GIFLibrary.swift:29-38, called from both managers). The behavior IS acknowledged in a code comment ('Latest nine; older files stay on disk', GridLayout.swift:150), but that is an implementer's note, not a Daniel ruling — no decree in CLAUDE.md or the library scene ruling covers unbounded growth. Each export is a few hundred KB of 64-frame 256×256 GIF, so silent accumulation is real but slow — P2 is the right severity.

Fix: Needs Daniel's ruling between: (a) page the 3×3 grid (same nine regions, swipe or a NEXT cell for the next nine), or (b) make the archive a ruled ring (archive prunes beyond the latest nine so disk matches the surface). The silent-growth state, not the nine-tile grid, is the bug.

## [26] P2 safe — Tesseract/Views/GIFPlayerView.swift:44
**Stale header ('64×64 GIF displayed at 256×256' — the contract has been 256×256 px since the per-frame-palette decree) and a naked 20.0 fps literal duplicating the 5 cs contract constant.**

Verdict: CONFIRMED — Verified: header lines 4-6 and the comment at line 22 ('scaling from 64→256') describe the pre-decree 64×64 wire size, while the export contract (CLAUDE.md) pins every GIF at 256×256 px via palette-index replication. Line 44 hardcodes '/ 20.0' where CameraConfig.targetFPS = 20 (CameraManager.swift:82) is the single source SurfaceClock already derives from (SurfaceClock.swift:46). The no-naked-constants decree makes the duplicated contract number a legitimate P2.

Fix: Update the header and line-22 comment to the 256×256 px contract, and compute animationDuration as Double(frameCount) / Double(CameraConfig.targetFPS).

## [27] P2 LOOK — Tesseract/Views/GIFPlayerView.swift:47
**GIF playback autoplays and loops forever regardless of Reduce Motion — the result and library surfaces animate continuously for users who asked the system for a static UI.**

Verdict: CONFIRMED — Verified: startAnimating() is unconditional with animationRepeatCount = 0 (GIFPlayerView.swift:45-47) and the view never consults reduce motion. The strongest rebuttal — SurfaceClock's carve-out comment ('GIF playback inside GIFPlayerView stays UIImageView-driven: that is content playback, not chrome', SurfaceClock.swift:7-9) — governs clock OWNERSHIP, not reduce-motion policy, exactly as the finding anticipated; reduce-motion handling in the clock only pins the chrome heartbeat. Content-vs-chrome is a defensible design line, and the app's product IS an animated GIF, so this stays P2 polish awaiting a ruling rather than anything higher.

Fix: When clock.reduceMotion (already plumbed through both covers), show the first frame and start animation on tap; needs Daniel's ruling since it changes what SEALED and the library detail show for reduce-motion users.

## [28] P2 safe — Tesseract/Views/LibraryView.swift:46
**The empty-library hint 'no gifs yet — record one' ships an em-dash in user-facing copy, against the standing no-em-dash decree.**

Verdict: CONFIRMED — Verified: line 46 literal is "no gifs yet — record one" — the only em-dash in user-facing copy in the app's views (comments don't ship). The no-em-dash decree targets prose Daniel ships under his name as an AI tell; shipped app copy qualifies. Trivial one-character fix, P2 correct. (Cited line corrected from 47 to 46 — the string starts on 46.)

Fix: Reword without the dash: "no gifs yet, record one".

## [29] P0 LOOK — Tesseract/Views/States/ProcessingStateView.swift:31
**The single-line phase text overflows the procPhase region and runs off the 400pt grid for LIVE's Go-analysis string**

Verdict: CONFIRMED — Verified end to end: CameraManager.swift:619 publishes "Go analysis \(i+1)/64 — complexity X.XX, N liberties" (46-50 chars) on every LIVE capture's phase-1 loop (0-40% of SOLVING, always reachable). CellText is single-line (snap() rasterizes the whole string, frame = mask width x 2pt with no truncation), Place.swift's .place() sets a center-aligned frame with NO clipping (grep confirms zero .clipped()/.clipShape in ContentView, Place.swift, and all state views), and procPhase is w:80 atoms = 320pt. At SF Mono bold size 7 (advance 0.6 x 7 = 4.2px, x2pt/cell) even the shortest variant (46 chars, ~388pt) overflows the region by ~68pt; the typical 49-char string (~412pt) also exceeds the 400pt canvas. SurfaceMachineTests.testWordsFitTheirRegions gates only the machine words, not phase strings, so nothing catches this. Broken strict-grid invariant, user-visible on every LIVE solve: P0 stands. One nuance: the region overflow (~70-90pt) is certain; the past-the-canvas part (~12pt) rides on the exact glyph advance and is marginal.

Fix: Word-wrap phase into procPhase (reuse ErrorStateView.wrap with a region-derived width — procPhase h:12 atoms fits two 7-cell label lines plus spacing) or shorten the Go-analysis string at CameraManager.swift:619 (e.g. "go 64/64 c 0.23 lib 12"); then extend SurfaceMachineTests.testWordsFitTheirRegions with the longest phase string rasterized at TypeRows.label against GridLayout.procPhase.

## [30] P1 LOOK — Tesseract/Views/States/ErrorStateView.swift:58
**Detail word-wrap width 36 is a naked constant not derived from the errMsg region or the label register**

Verdict: CONFIRMED — Line 58 is exactly Self.wrap(text, width: 36) with no derivation; the comment above ("word-wrap the detail to the region") claims region fit but nothing computes it. True capacity of errMsg (80 atoms = 320pt) at label register (7px glyphs, 4.2px advance, 2pt/px) is 38 chars, so 36 fits only coincidentally. TypeRows.label did grow 5 to 7 on 2026-08-10 (Ink.swift:50 comment "was 5"), so the failure mode is historically real. No gate exists: SurfaceMachineTests covers only machine words, and scripts/lint-grid.sh bans raw literals in frame/padding/spacing, not wrap widths. All four ruled detail strings (ContentView.swift:171-185, longest 61 chars) currently wrap to 2 lines of <=36 chars = ~302pt, so nothing overflows today — P1 (real, not breaking) is the right severity. Charter rule 1 violation; the no-naked-constants decree reinforces it.

Fix: Derive capacity from the region and the measured glyph advance — e.g. let advPx = CellText.snap("M", rows: TypeRows.label)!.size.width; let capacity = Int(Lattice.gif(GridLayout.errMsg.w) / (advPx * Lattice.pt(1))) — noting snap()'s per-char ceil (5px) yields a conservative 32 vs the true 38; or wrap by measuring candidate lines with CellText.snap directly. Add a fit test rasterizing each wrapped line of the four ruled detail strings against GridLayout.errMsg (width AND the h:14 line-count budget: max 3 lines at 14pt + 4pt spacing).

## [31] P2 LOOK — Tesseract/Views/States/ProcessingStateView.swift:31
**Phase strings render Title-case with ellipses in the lowercase explanatory register, breaking the two-register voice**

Verdict: CONFIRMED — Verified: the procPhase line renders at TypeRows.label in Ink.ledGhost — the exact register/ink the app's lowercase second voice uses everywhere else (ErrorStateView detail, ResultStateView keepNote "photos off, allow adding in Settings"). The strings it receives are Title-case fragments with trailing "...": CameraManager.swift:609 "Analyzing color structure...", :630 "Quantizing tesseract...", :662 "Encoding GIF...", :619 Go-analysis with an em-dash; FaceCaptureManager.swift:336 "Quantizing face tesseract...", :365 "Encoding GIF...". Attempted refutation: the two-register decree is stated for ERRORS, and no ruling governs phase-string casing — but the inconsistency within the same visual register is real and the SOLVING machine word (line 23) already carries the state, so the phase line is functionally the lowercase detail register. Correctly filed as P2 polish, and lowercasing changes rendered pixels so lookChanging=true is right. Bonus: "Quantizing tesseract..." also names the deleted tesseract method.

Fix: Lowercase the phase strings at their sources (CameraManager.swift:609/619/630/653/662/683, FaceCaptureManager.swift:336/359/365/386) and drop the trailing "..." and the em-dash; rename "Quantizing tesseract..." to something honest about the DYAD path (e.g. "quantizing frames") while touching those lines.

## [32] P2 safe — Tesseract/Views/States/FacePreviewStateView.swift:95
**captureInfoLine is unplaced, unreachable dead chrome; the "richer widgets survive below" comments in both preview views are stale**

Verdict: CONFIRMED — Grep across the repo finds exactly one occurrence of captureInfoLine — its declaration at FacePreviewStateView.swift:95-98; body (lines 24-42) places only preview/record/settings/faceDot. LivePreviewStateView.swift:18-20 claims "the richer widgets (gauge/channels/info/palette) survive below, unplaced" but that file contains zero unplaced widgets (channel-preview thumbs were excised 2026-08-10 per CLAUDE.md), so the two shared-surface files contradict each other. Attempted refutation: the FACE comment ("richer widgets survive below, unplaced") does document keeping unplaced vars at decree time — but the LIVE side's widgets were since deleted, making both comments false today, and charter rule 3 flags stragglers. Never rendered, so P2 deadcode is the right weight. The FACE file's header (lines 4-7, "Same footprints as the LIVE capture scene (gauge / preview / info / palette / record)") is stale for the same reason.

Fix: Delete captureInfoLine (FacePreviewStateView.swift:95-98) and rewrite the SIMPLICITY comments — FacePreviewStateView lines 16-17 AND its header lines 4-7, plus LivePreviewStateView lines 18-20 — to state the current truth: surface = preview + shutter + SET (+ transient face dot on FACE), nothing unplaced survives.

## [33] P2 safe — Tesseract/GIF/GIFSaver.swift:40
**SHARE can silently do nothing: presentShareSheet swallows both failure paths with bare returns**

Verdict: CONFIRMED — Verified: GIFSaver.swift:40 (guard saveToTempFile else return) and :48-49 (guard scene/rootViewController else return) both exit with no surface, no log. ContentView.swift:142 and :245 wire ResultStateView's onShare straight to it, and LibraryView.swift:122 does too — a failed tap is mute at all three call sites, unlike every other failure in the app (KEEP has the keepState/keepNote two-register machinery; encode failure surfaces encodeFailedMessage). Attempted refutation: both guards are near-unreachable in practice (temp-dir write on iOS, foreground keyWindow), which is exactly why this is P2 not P1 — but "near-unreachable" is not a documented ruling, and disk-full temp writes do fail in the wild. Confirmed at P2.

Fix: Make presentShareSheet return Bool (discardable) and surface failure at the callers: ResultStateView gains a shareNote lowercase line in the resultNote region mirroring keepNote (e.g. "the share sheet could not open, try again"); LibraryView.swift:122 gets the same treatment or at minimum a logger.error so the path is not silent.

## [34] P2 safe — Tesseract/Views/States/ResultStateView.swift:21
**The exported GIF — the screen's main content — is invisible to VoiceOver**

Verdict: CONFIRMED — Verified: ResultStateView.swift:21-25 applies no accessibility modifier to GIFPlayerView, and GIFPlayerView.swift contains zero accessibility calls (grep exit 1). It wraps a bare UIImageView, whose isAccessibilityElement defaults to false, so VoiceOver skips the artifact entirely; the scene reads as buttons plus the disconnected metric fragments. Attempted refutation: charter rule 5's letter covers interactive elements and decorative cell art, and the GIF is neither — but the SEALED scene's entire purpose being silent to VoiceOver is a genuine a11y gap, correctly weighted P2. Same gap exists at LibraryView's libDetailGif usage.

Fix: Add .accessibilityLabel("Exported GIF, 64 frames, looping") inside GIFPlayerView itself (set imageView.isAccessibilityElement = true + accessibilityLabel in makeUIView, or the SwiftUI modifier on the representable) so ResultStateView and LibraryView both inherit it.

## [35] P2 safe — Tesseract/Views/States/ResultStateView.swift:84
**Metrics read to VoiceOver as cryptic disconnected fragments ("12", "M", "0.23", "C", "dim", "col")**

Verdict: CONFIRMED — Verified: metric(_:_:) at lines 84-89 stacks two independent CellTexts with no .accessibilityElement(children: .ignore) grouping; CellText.swift:36 exposes each raw string via accessibilityLabel(Text(text)), so VoiceOver traverses ten fragments — value then single-letter label (M/O/C/dim/col) — with no decodable meaning. Contrast: ErrorStateView.detailLines (lines 62-63) and the faceDot (FacePreviewStateView:91-92) both do the correct grouping, so this is an omission, not a pattern. The rider is also verified: line 45 uses keepLabel as the accessibilityLabel, and keepLabel is "…" during .saving (line 104), so the button momentarily announces an ellipsis character. P2 correct.

Fix: In metric(), add .accessibilityElement(children: .ignore).accessibilityLabel("\(spokenName) \(value)") with spoken names (beauty/order/complexity/dimension/colors) passed alongside the glyph label; give the .saving keepState a spoken "Saving" (split display title from accessibility label at line 45).

## [36] P2 safe — Tesseract/Views/States/ProcessingStateView.swift:16
**Doc comment references "non-dyad looks", a feature deleted with the 2026-08-12 per-frame-palette decree**

Verdict: CONFIRMED — Verified: lines 15-16 read "per-frame DYAD table (nil until the palette pass begins, or for non-dyad looks)". CLAUDE.md's export contract (2026-08-12 decree) deleted the tesseract/refined methods and the LOOK setting — DYAD is the only export law, so "non-dyad looks" is an impossible state and the comment is stale documentation. Trivially real, trivially P2.

Fix: Trim the comment at ProcessingStateView.swift:15-16 to "The palette being created — per-frame DYAD table (nil until the palette pass begins)."

## [37] P1 safe — Tesseract/Camera/CameraManager.swift:680
**The SOLVING progress bar freezes at 85% for the entire DYAD per-frame palette solve — the heaviest, most user-facing phase of processing.**

Verdict: CONFIRMED — Verified: processProgress writes exist only at lines 618 (Go, 0-40%), 652 (quantize, 40-80%), 663 (0.85), and 703 (1.0). The onFrameTable closure (680-685) updates liveTable and processPhase but never processProgress, so the 64-cell bar and percent counter in ProcessingStateView (lines 29-30, 64-70) sit at 85% through the whole DYAD solve (mixture fits, staging, tables, pair dither, ANE dispatch, LZW). Mild mitigation — the phase text 'Solving palette f/64' and the CellPalette swatch do advance — but the progress instrument itself lies during the longest phase, against SM2's 'SOLVING must surface the solve'. FaceCaptureManager has the identical freeze (0.85 at line 366, next write 1.0 at 406). P1 stands.

Fix: Advance progress inside the onFrameTable closure: self.processProgress = 0.85 + Float(f + 1) / Float(frameTotal) * 0.15 (same in FaceCaptureManager.encodeGIF, whose bar has the identical freeze). Better: reweight phases to measured device wall time (Go and PerfectQuantizer are telemetry-feeders and much lighter than the DYAD solve). Note onFrameTable fires BEFORE assignment per DyadPipeline's doc, so the final assignment+encode stretch still needs a tail segment.

## [38] P1 LOOK — Tesseract/Camera/CameraManager.swift:666
**The Birkhoff measure shown on the result screen (M/O/C/dim/col) and embedded in the GIF comment describes the deleted tesseract-lattice quantization, not the DYAD indices actually exported.**

Verdict: CONFIRMED — Verified end to end: measure (666-673) aggregates PerfectQuantizer.quantizeFrame paletteIndices; DyadPipeline.process (DyadPipeline.swift 119-174) consumes only rawRGB and depths and emits its own indexFrames, which are what GIFEncoder writes; GIFEncoder.swift line 84 embeds the stale measure as 'Tesseract 4^4 | M=...' — the comment even still names the deleted method; ResultStateView lines 76-80 display it. The truncating integer division at 671 is real: with 64 frames, any entry totalling <64 hits averages to 0, deflating colorsUsed and skewing entropy. Compounding inconsistency: the live preview's BirkhoffMeasure IS computed from DYAD indices (makePreview line 748), so preview and result metrics describe different index spaces. The RATE LEDGER line already computes the honest M from the emitted cube, so the measure-comment is doubly redundant provenance. FaceCaptureManager 369-376 duplicates the bug. No CLAUDE.md ruling protects the stale measure. lookChanging correctly true — displayed numbers change, needs Daniel's ruling.

Fix: Compute the displayed/embedded BirkhoffMeasure from dyad.indexFrames inside GIFMachine.makeGIF (return it or add a callback), matching the preview which already measures DYAD indices; the RATE LEDGER M in dyadTrace is the operational precedent. Apply identically in FaceCaptureManager.encodeGIF (lines 369-376, same code). Keep the PerfectQuantizer histogram only for telemetry, labeled as such. Fix the truncating average regardless — pass totalCounts straight to BirkhoffMeasure(counts:) (its math normalizes by total, so per-frame averaging is unnecessary) or accumulate in Double. Needs Daniel's ruling since result-screen numbers and the GIF comment change.

## [39] P1 safe — Tesseract/Camera/CameraManager.swift:236
**stop() blocks the main actor with sessionQueue.sync { session.stopRunning() }, freezing the UI for the full session-teardown (typically 100-300+ ms) on every LIVE→FACE mode switch.**

Verdict: CONFIRMED — Verified: stop() (232-238) is @MainActor and does sessionQueue.sync { session.stopRunning() }; stopRunning blocks until teardown completes. The serial-queue pileup is real — start() enqueues configureAndStart whose startRunning 'blocks for hundreds of ms' (the file's own comment, 144-146), and a subsequent stop().sync waits behind it, so a quick LIVE→FACE toggle can stall the main thread for start+stop. Fires from the settings-cover CAMERA toggle via ContentView.onChange(of: appMode) line 81, exactly while the user is interacting. The synchronous handoff is documented only as a code-comment engineering choice for the TrueDepth single-owner invariant (ContentView 72-74), not a Daniel decree — CLAUDE.md has no ruling protecting it, and the charter (perf as UX) names main-actor blocking a finding. The fix must preserve strict stop-before-start ordering, which the completion-gated design does.

Fix: Make teardown async with a completion: sessionQueue.async { self.session.stopRunning(); DispatchQueue.main.async { onStopped() } }; set state = .idle immediately (SurfaceMachine already maps .idle to WAKING, so the transitional word is free), and have ContentView's .onChange gate faceCamera.start() on the completion instead of on stop()'s return — the TrueDepth single-owner invariant is preserved by ordering, not by blocking. Mirror the audit on FaceCaptureManager.stop() for the FACE→LIVE direction.

## [40] P2 LOOK — Tesseract/Camera/CameraManager.swift:630
**processPhase says 'Quantizing tesseract...' during Phase 2, naming the export method deleted by the 2026-08-12 per-frame-palette decree, on a screen whose export is DYAD.**

Verdict: CONFIRMED — Verified: line 630 sets 'Quantizing tesseract...', rendered by ProcessingStateView via CellText at TypeRows.label directly under the machine's SOLVING word; FaceCaptureManager line 336 says 'Quantizing face tesseract...' so LIVE and FACE diverge in wording for the same phase (charter rule 9); line 619's Go string carries an em-dash and the sibling strings are mixed-case prose with ellipses. One nuance the claim slightly overstates: the tesseract-lattice quantization genuinely still RUNS (its paletteIndices feed TriScaleLadder and Dissonance telemetry, plus the stale measure), so the string describes real work — but the method's export role was deleted, making the name misleading on a DYAD-export surface. P2 and lookChanging=true are right.

Fix: Rename the phase strings to describe the work in the surface's register without the deleted method name (e.g. 'measuring 5/64' for the telemetry quantize pass, 'solving palette 5/64' as already used), and unify the strings between CameraManager and FaceCaptureManager (line 336). Drop the em-dash in the Go analysis string (line 619). User-visible wording — wants Daniel's ruling.

## [41] P2 safe — Tesseract/Camera/CameraManager.swift:279
**Session-configuration failures break the two-register error voice: 'Cannot add camera input' / 'Cannot add video output' / 'Cannot add depth output' are capitalized, and line 349 surfaces raw error.localizedDescription (arbitrary system prose) as the explanatory sentence.**

Verdict: CONFIRMED — Verified: the three capitalized literals (279, 295, 301) and error.localizedDescription (349) return from configureSession, flow through SurfaceMachine.refusal(for:) which routes unmatched strings to .unknown(message) (SurfaceMachine.swift 107), and land in ErrorStateView's detail region whose documented contract is 'Lowercase explanatory register' (ErrorStateView.swift 17). Every ruled message constant is lowercase (182, 186, 190). localizedDescription can be multi-sentence capitalized system prose — a genuine register break. These are rare failure paths (headline renders as ERROR), so P2 is the right weight.

Fix: Lowercase the three literals ('cannot add camera input', 'cannot add video output', 'cannot add depth output') and replace the returned localizedDescription with a ruled lowercase sentence (e.g. 'the camera session could not be configured'); the underlying error is already logged at line 348.

## [42] P2 safe — Tesseract/Camera/CameraManager.swift:43
**CubeMode is a vestigial two-value enum whose .inference case and UI label strings ('64³ train' / '128³ infer') are unreachable — the 128³ runtime switch was excised after the 2026-08-03 device crash.**

Verdict: DOWNGRADED — The core factual claim is wrong: 'referenced nowhere outside CameraManager.swift' is refuted by TesseractTests/LevelTests.swift, which actively exercises CubeMode.allCases, .inference, spatialSide, frameCount, and framesPerEpoch (lines 15, 24, 33-34, 42, 53, 73) against the C1/C3/C12 axioms — and the code comment at lines 66-72 documents the deliberate decision to keep the two-cube algebra verified ('The two-cube algebra stays verified by LevelTests'). Deleting CubeMode as proposed would break a green test suite guarding a documented invariant. What survives adversarial reading: the .label property ('64³ train'/'128³ infer', lines 51-56) is referenced by nothing — LevelTests does not touch it — and IS leftover UI text from the excised runtime switch, a legitimate simplicity-decree straggler. Real but much smaller than claimed.

Fix: Delete only the unused .label property (lines 51-56). Keep CubeMode, .inference, and framesPerEpoch — LevelTests verifies the two-cube algebra by documented design, and removing them breaks the suite. Do not fold the constants into CameraConfig.

## [43] P2 safe — Tesseract/Camera/CameraManager.swift:507
**No-depth frames are filled with a naked 0.5 literal in two places instead of DepthSignal.fill, duplicating the invalid-depth constant the rest of the pipeline derives from one definition.**

Verdict: CONFIRMED — Verified: line 507 (depthValues ?? [Float](repeating: 0.5, ...)) and line 545 (readDepth's nil-base-address fallback) hardcode 0.5 while the per-pixel paths in the same functions use DepthSignal.fill and DepthSignal.signalOrFill (lines 567, 569, 581-582). DepthSignal.fill is the single documented definition ('0.5 = invalid fill', DepthSignal.swift line 25, pinned by DepthSignalTests and FaceCadence FC2), so the literals duplicate a defined constant against the no-naked-constants decree (CLAUDE.md 'CONSTANT-FREE ... no naked thresholds' + feedback_no_naked_constants). No visual divergence today (values equal), so P2 with lookChanging=false is exactly right.

Fix: Replace both 0.5 literals (lines 507 and 545) with DepthSignal.fill; also grep FaceCaptureManager for the same pattern while there.

## [44] P1 safe — Tesseract/Camera/FaceCaptureManager.swift:386
**The SOLVING progress bar freezes at 85% for the entire DYAD solve + encode because the onFrameTable callback updates processPhase but never processProgress.**

Verdict: CONFIRMED — Verified: processProgress is set to 0.85 at line 366, the onFrameTable closure (383-388) writes only self.liveTable and self.processPhase, and the next progress write is 1.0 at line 406 — the 64-cell procBar and procPct sit frozen through DyadPipeline, PhaseTelemetry, SKGene, and LZW encode. CameraManager has the byte-identical gap (0.85 at 663, closure 680-683, 1.0 at 703). The latency-inversion premise also checks out: the 0→80% PerfectQuantizer indices feed only BirkhoffMeasure/TriScaleLadder/Dissonance telemetry (verified in GIFMachine.makeGIF and DyadPipeline — the GIF is built from rawRGB+depths), so the bar's fastest span is the work that shapes no GIF byte. 'Longest user-facing phase' is plausible but unmeasured; the freeze itself is certain.

Fix: In the onFrameTable closure add self.processProgress = 0.85 + 0.13 * Float(f + 1) / Float(frameTotal) (reserve the last ~2% for GIFEncoder.encode + trace, which run after the final table callback); apply the identical fix in CameraManager's closure at lines 680-683. Longer term, rebalance the 0.8/0.2 split toward the DYAD phase — but measure first, since 'where the time goes' is asserted, not profiled.

## [45] P1 safe — Tesseract/Camera/FaceCaptureManager.swift:125
**FACE startRecording() does not clear liveTable (LIVE does), so a second FACE capture's SOLVING screen shows the previous capture's palette through the quantize pass; stale processProgress also flashes a full bar on entry.**

Verdict: CONFIRMED — Verified: FaceCaptureManager.startRecording (122-128) resets only gifData and gifMeasure; CameraManager.startRecording (223-230) additionally sets liveTable = nil at line 227. ContentView:237 passes faceCamera.liveTable straight into ProcessingStateView's CellPalette, and DyadPipeline's first onFrameTable fires only after the whole 0→80% quantize loop, so the stale 16×16 swatch is visible for the entire pass. The stale-progress flash is real but brief (the detached task's first MainActor.run at line 335 zeroes it within the first phase) and affects LIVE too, since CameraManager also never resets processProgress/processPhase in startRecording. Charter 9 violation stands: the shared ProcessingStateView surfaces differently by mode.

Fix: In FaceCaptureManager.startRecording() add liveTable = nil, processProgress = 0, processPhase = ""; add the processProgress/processPhase resets to CameraManager.startRecording too (it already clears liveTable) so both managers enter SOLVING identically.

## [46] P1 safe — Tesseract/Camera/FaceCaptureManager.swift:141
**The full CPU preview pipeline keeps running at 20 Hz during SOLVING, SEALED, and REFUSED — converting the full luma square, rasterizing the mesh, running DyadPreview, and publishing three @MainActor properties per frame — while no scene displays a preview.**

Verdict: CONFIRMED — Verified: processFrame (132-196) gates only on timestamp spacing — no state check. After frame 64 flips state to .processing (189-191) the ARSession keeps delivering (deliberately never paused, per ContentView's handoff comment), and every accepted frame still runs convertToGrid (box-average over the full min(w,h)² centered square), faceSignalGrid (~1220 vertices), dyadPreview.process, buildPreviewImage, BirkhoffMeasure, and a MainActor publish. ProcessingStateView, ResultStateView, and ErrorStateView render no preview, so the work is invisible and competes with the detached encode (charter 7) while invalidating ContentView at 20 Hz. The one-owner handoff design justifies keeping the session alive, not the per-frame CPU pipeline — the fix respects the decree.

Fix: Gate processFrame on a flag readable from the delegate queue — set true on start()/return-to-.previewing, false on entering .processing/.done/.error — and early-return after the throttle when false. Prefer an atomic/lock-protected bool over bare nonisolated(unsafe) since it is written from the MainActor and read on delegateQueue (unlike lastAcceptedTime, which is delegate-queue-only). Keep the ARSession itself running (the handoff design stands). Preview must remain live during .recording (RecordingStateView shows it).

## [47] P1 safe — Tesseract/Camera/FaceCaptureManager.swift:468
**Any ARSession failure other than cameraUnauthorized surfaces raw error.localizedDescription as the lowercase register of the two-register error voice.**

Verdict: CONFIRMED — Verified: session(_:didFailWithError:) (460-474) maps only ARError.cameraUnauthorized to CameraManager.cameraDeniedMessage; the else branch passes error.localizedDescription into .error(message). SurfaceMachine.refusal(for:) (101-108) returns .unknown(message) for any non-ruled string, and ContentView's .unknown case (187-188) renders it verbatim as ErrorStateView's detail under the generic ERROR headline — capitalized system prose in the lowercase register, breaking charter 4 on sensor/tracking failures. Rare path, but it is the only place in either manager where an unruled string reaches the error surface, and the charter states the rule unconditionally.

Fix: Map non-unauthorized ARSession failures to a ruled lowercase constant (e.g. nonisolated static let faceSessionFailedMessage = "the face session failed, try again"), log the raw localizedDescription via logger only, and add the constant to SurfaceMachine.refusal(for:). Note two decree constraints: spec/ui/SurfaceMachine.hs is authoritative, so a new refusal case means updating the Haskell spec + SurfaceMachineTests (word must fit its GridRegion), and the headline word itself is Daniel's to rule. A minimal compliant fix that avoids both: keep .unknown/ERROR but substitute the ruled lowercase sentence for the raw string.

## [48] P2 safe — Tesseract/Camera/FaceCaptureManager.swift:170
**previewMeasure is computed and published at 20 Hz but has zero consumers — dead per-frame work left over from the excised stats surface.**

Verdict: CONFIRMED — Verified by repo-wide grep: previewMeasure appears only at its declarations (FaceCaptureManager:48, CameraManager:122) and its own writes (FaceCaptureManager:174, CameraManager:434/514). No view, test, or other code reads it. BirkhoffMeasure(paletteIndices:) is built every accepted preview frame at line 170. CLAUDE.md confirms the GIFStats surface was excised 2026-08-10; charter 3 makes stragglers findings. The per-frame cost is small (a 4096-index histogram), so P2 is the right severity.

Fix: Delete the @Published previewMeasure property and the per-frame BirkhoffMeasure computation from the preview path in both managers (FaceCaptureManager 48/170/174; CameraManager 122/434/514). gifMeasure is separate and still consumed by ResultStateView — leave it.

## [49] P2 safe — Tesseract/Camera/FrameBuffer.swift:17
**QuantizedFrame.subjectAnalysis and anchorTrace have no consumer, yet both managers compute analyzeSubject and findAnchors for all 64 frames during SOLVING — dead work inside the user-facing latency window.**

Verdict: CONFIRMED — Verified: repo-wide grep finds no read of .subjectAnalysis anywhere and only one read of .anchorTrace — TesseractTests/AxiomTests.swift:600, on a frame the test itself constructs (producer-testing, not an app-path consumer). GIFMachine, DyadPipeline, TriScaleLadder, Dissonance, and GIFEncoder never touch either field; all other test call sites pass nil. So the substance stands, though 'no consumer anywhere' is slightly overstated (AxiomTests references the fields and the PerfectQuantizer functions at lines 501/519/575-600). The per-frame cost is small (linear passes over 4096 entries ×64), so P2 deadcode, not a latency P1.

Fix: Delete both fields from QuantizedFrame and the analyzeSubject/findAnchors calls at both construction sites (FaceCaptureManager 352-353, CameraManager 646-647). Correction to the original fix: PerfectQuantizer.analyzeSubject/findAnchors ARE referenced — by AxiomTests (lines 501, 519, 575-600) — so deleting the functions means pruning those axiom tests too, and every test file passing subjectAnalysis:/anchorTrace: nil (8 files) needs the mechanical constructor update.

## [50] P2 LOOK — Tesseract/Camera/FaceCaptureManager.swift:336
**The user-visible SOLVING phase string 'Quantizing face tesseract...' names the deleted tesseract export method and misdescribes the pass (its indices feed only telemetry and the measure; the GIF is DYAD).**

Verdict: CONFIRMED — Verified with one tempering: the pass genuinely IS tesseract-lattice quantization (PerfectQuantizer still quantizes to the 4⁴ lattice, and 'tesseract' legitimately survives as the app/lattice name), so 'names the deleted method' is only half right. But the output shapes no GIF byte (verified: GIFMachine builds the GIF from rawRGB+depths via DyadPipeline; paletteIndices feed only measure/TriScale/Dissonance), so presenting it as THE solve on the SOLVING surface is misleading, and the Title-case-plus-ellipsis register ('Quantizing face tesseract...', 'Encoding GIF...', LIVE's 'Quantizing tesseract...' at CameraManager:630 and 'Analyzing color structure...' at 609) drifts from the machine's ruled voice. CellText renders lowercase fine (monospaced raster), so the proposed register works. P2 polish is right.

Fix: Rename the phase strings in both managers to truthful, consistent lower-register strings ('measuring frame i/n', 'sealing gif', keeping 'Solving palette f/n' as the model) and drop the ellipses. lookChanging corrected to true: these words render on the SOLVING surface every capture, and the surface's spoken words are Daniel's ruling (SurfaceMachine precedent) — get the wording ruled before shipping.

## [51] P2 safe — Tesseract/Camera/FaceCaptureManager.swift:453
**The isProcessingFrame frame-drop guard is inert: processFrame runs synchronously on the serial delegate queue, so the flag is always false when checked.**

Verdict: CONFIRMED — Verified: session(_:didUpdate:) (450-458) sets isProcessingFrame = true, calls processFrame synchronously, and clears it in a defer within the same invocation. ARSessionDelegate callbacks arrive serially on delegateQueue (set at line 107, declared line 67 with the comment 'all delegate callbacks arrive serially'), so no second callback can ever observe the flag true — the guard at 453 never trips. The 'HaarScope pattern' comment describes a design that requires hopping to another queue; here slow processing just backs up the serial queue (each pending block retaining its ARFrame) with no protection from this flag.

Fix: Delete the flag and the guard (the timestamp throttle at processFrame line 135 is the real gate), or make the guard real by dispatching the heavy work off the delegate callback so ARKit can recycle frames — the former is the simplicity-decree-consistent choice.

## [52] P2 safe — Tesseract/Camera/FrameBuffer.swift:77
**FrameBuffer carries dead surface: isFull has zero callers, the capacity comment claims '64, 32, or 16' frames when CameraConfig pins 64 (or 128), and an empty '// MARK: - Export' section trails the file.**

Verdict: CONFIRMED — All three verified: grep finds isFull only at its definition (line 77) — both managers gate on frameBuffer.frameCount < CameraConfig.totalFrames directly; the line-36 comment 'S×K=4096: 64, 32, or 16' contradicts CubeMode (CameraManager:43-45: training=64, inference=128 — 16/32 are not modes, and 4096 is only S×K for the 64 case); lines 81-83 are a bare '// MARK: - Export' with no members. Straight charter-3 stragglers, correctly P2.

Fix: Delete isFull, correct the capacity comment to the CubeMode reality (64 pinned; 128 exists but is disabled — see CameraConfig.mode's comment about the MetalPipeline reallocation landmine), and remove the empty MARK section.

## [53] P2 safe — Tesseract/Camera/CapturedFrame.swift:23
**Orphaned doc comment 'Per-block Go evaluation from FULL camera resolution' documents a field that no longer exists in CapturedFrame.**

Verdict: CONFIRMED — Verified: lines 23-24 are a two-line doc comment followed by a blank line and then the timestamp field's own doc comment (26-27) — the Go-evaluation member it documented is gone (LIVE's Go analysis now runs in CameraManager.encodeGIF, publishing processBoards). The header claim is milder than stated: 'integer step at 64, 128, 256' (line 5) is arithmetically true of the 768 crop (steps 12/6/3) rather than a stale mode list, but 256 is indeed not a capture size (CubeMode = 64/128 only) and the 'Universal 768 crop / GPU downsample' framing is itself stale for FACE, which fills CapturedFrame from an ARKit centered-square CPU path with no 768 crop. Orphaned comment is the core finding; P2 correct.

Fix: Delete the orphaned comment (lines 23-25) and rewrite the header for both producers: LIVE = GPU downsample from the 768 crop, FACE = CPU conversion from the ARKit centered square; capture sizes are 64 or 128 per CubeMode (64 pinned).

## [54] P2 safe — Tesseract/Metal/MetalPipeline.swift:266
**Every 20 Hz preview frame pays TWO blocking CPU-GPU round trips: downsampleFrame commits and waitUntilCompleted (line 266), then aerialAssign builds a second command buffer and waits again (line 345), serializing the capture queue twice per frame.**

Verdict: CONFIRMED — Verified: downsampleFrame commits+waits at lines 265-266, then CameraManager.processFrame (Camera/CameraManager.swift:425) calls makePreview which calls metal.aerialAssign (CameraManager.swift:741) — a second fresh command buffer with commit+wait at lines 344-345, all on the same delegate queue. DyadPreview.refreshStride = 4 confirms the slow state changes on only 1 of 4 frames, so on 3 of 4 frames the aerial inputs (metalState primaries/params) are known before the downsample commits; the kernel's texture inputs (rgb64/depth64) are the downsample's outputs, so same-buffer sequential encoders give identical results. Real but tiny: two waits on 64-by-64 work is a couple of ms inside a 50 ms budget, so P2 is the right severity under charter rule 7.

Fix: On non-refresh frames (counter % DyadPreview.refreshStride != 0, so metalState is unchanged), encode the aerialPreview dispatch into the SAME command buffer as the downsample and wait once — byte-identical output, one sync instead of two. Requires passing the MetalState into downsampleFrame (or a fused variant) and deciding refresh-frame status from the counter before the readback. Keep the two-pass shape on the 5 Hz refresh frames, which need the readback to update the slow state before assignment. Note the single wait still blocks inside the delegate callback, which also keeps the makeTexture pixel-buffer lifetime safe (finding 6).

## [55] P2 safe — Tesseract/Metal/Quantize.metal:79
**DepthSignal.fill is duplicated as a hardcoded 0.5f literal in the kernel (lines 79 and 121) despite the file header's claim that the meters->signal map takes its parameters from DepthSignal.swift as the single source.**

Verdict: CONFIRMED — Verified: naked 0.5f with '// DepthSignal.fill' comments at Quantize.metal lines 79 and 121, while dNear/dFar anchors are passed via scalars.z/.w from DepthSignal (MetalPipeline.swift:322-324) precisely to keep DepthSignal.swift authoritative. DepthSignal.fill = 0.5 (Camera/DepthSignal.swift:25) and the CPU readback path uses signalOrFill (MetalPipeline.swift:398). The fill IS part of the meters->signal map (signalOrFill), so hardcoding it is inconsistent with the file's own header principle (lines 12-14) and with the no-naked-constants discipline. No pixel divergence today (both are 0.5), which is why P2 latent-risk is the right level, not higher. centroid.w and flags.w are both verified free (set to 0 at MetalPipeline.swift:321 and 327).

Fix: Pass the fill through a free params slot (centroid.w or flags.w — both are currently zero-filled) populated from DepthSignal.fill in aerialAssign, and read it at both kernel sites (lines 79 and 121). No pixel change today (fill == 0.5).

## [56] P2 safe — Tesseract/Metal/Quantize.metal:112
**Every sigma-side pixel independently recomputes its full 4x4 block mean — 16 texture-pair reads plus 16 OKLab conversions plus 16 depth->signal maps — so a background-dominated frame does up to 16x redundant work in the 20 Hz kernel.**

Verdict: CONFIRMED — Verified: lines 108-129 re-read depthTexture and rgbTexture and re-run oklabFromSrgbGPU + gamma staging for all 16 texels per sigma-side pixel, while the CPU twin (DyadPreview.assignCPU lines 183-199) pools the staged field once per block. CLAUDE.md records the '16-texel block pool in-kernel' as the shipped v7 port but documents the implementation, not a decree that it must recompute per pixel, so this is not a documented-ruling refutation. However the absolute cost is negligible (worst case 65k texel pairs across 4096 threads at 64x64) — pure P2 polish that cannot jank the surface. The finding's lookChanging=true was over-cautious: a fix that preserves the sequential dy/dx fp32 summation order (one lane computes, threadgroup broadcast) is bit-identical, since every pixel in a block already computes the identical sum today. Only a tree reduction would change order.

Fix: Have one lane per 4x4 block compute the block sum in the existing sequential dy/dx order and broadcast it via threadgroup memory (8x8 threadgroups contain four aligned 4x4 blocks; 64 is divisible so the barrier is safe under dispatchThreads). Preserving the summation order makes the output byte-identical — no device look needed. Avoid a parallel tree reduction, which would change fp32 summation order and flip near-ties (that variant would need Daniel's device ruling).

## [57] P2 safe — Tesseract/Metal/MetalPipeline.swift:4
**The file header 'Metal compute pipeline: downsample + quantize in one GPU pass' describes the excised quantizeWithDepth path (the raw-meters landmine deleted 2026-08-10) and misstates what the file now does.**

Verdict: CONFIRMED — Verified: line 4 still reads 'downsample + quantize in one GPU pass'. CLAUDE.md's EXCISED 2026-08-10 entry confirms MetalPipeline.processFrame + quantizeWithDepth were deleted ('Quantize.metal is downsample-only now' plus the later aerialPreview addition), and Quantize.metal's own header (lines 10-14) documents the removal while this one was never updated. The class today does GPU downsample + optional aerialPreview assignment with export quantization on CPU/ANE. A stale header pointing at a deleted-for-cause path is a straggler under the simplicity decree. Comment-only, no behavior change — P2 correct.

Fix: Reword lines 4-5 to: GPU downsample (camera res -> 64x64, 90-degree CCW rotation baked into the read) + the 20 Hz aerialPreview assignment twin of DyadPreview.assignCPU; export quantization is CPU/ANE. Drop the 'Logging at every step so we can catch exactly where things break' line or update it — logging is now throttled to every 20th frame.

## [58] P2 safe — Tesseract/Metal/MetalPipeline.swift:426
**fromRGBBuffer/fromDepthBuffer trap (crash, not error surface) if a device ever delivers a buffer narrower than the forced crop: (width - 768)/2 goes negative and UInt32(cropX) aborts mid-preview.**

Verdict: CONFIRMED — Verified: lines 426-427 and 438-439 compute (width - cropSize)/2 with Int and force-convert via UInt32() at lines 430-431 and 442-443 — a negative crop traps. No configuration-time guard exists: the session uses .photo preset with no RGB dimension check, and depth format selection just picks the widest Float16 format (CameraManager.swift:307-319); CameraConfig's own comment (line 60: 'fits any TrueDepth sensor >=1080 RGB, >=360 depth') states the assumption without enforcing it. Unreachable on known hardware, so P2 not P0. The proposed fix text was WRONG about the fallback being safe: processFrameCPU (line 493) and readDepth (line 567) guard only srcX < width, so a negative crop passes the guard and indexes a negative byte offset — UB/crash in the CPU path too. Corrected below. No decree conflict: feedback_no_crop_changes forbids changing cropSize, and this fix does not touch it.

Fix: Guard in both factories (width >= cropSize && height >= cropSize, returning nil/optional) and have downsampleFrame return nil on nil params — but ALSO fix the CPU fallback, which is equally unsafe: extend the guards at CameraManager.swift:493 and :567 to srcX >= 0 && srcY >= 0. Better still, since a sub-crop sensor can never produce the 64-square grid, surface it as a terminal two-register refusal (charter rule 4) at configureSession time rather than silently falling back.

## [59] P2 safe — Tesseract/Metal/MetalPipeline.swift:198
**makeTexture drops the CVMetalTexture wrapper before the GPU reads the texture; the returned MTLTexture's backing can be recycled by the camera's pixel-buffer pool, which is only safe today because downsampleFrame blocks with waitUntilCompleted inside the delegate callback.**

Verdict: DOWNGRADED — The lifetime reading is technically correct (cvTex is released at function exit, lines 193-203, and Apple's contract wants the CVMetalTexture held until GPU completion), but there is NO violation today: the delegate callback holds the CVPixelBuffer strongly for the duration of processFrame, and both downsampleFrame and aerialAssign waitUntilCompleted before returning, so the buffer provably outlives all GPU reads. The claim's escalation path is also wrong: finding 1's fix keeps a synchronous single wait inside the callback, so it does NOT introduce the hazard — only a future fully-async commit (which nothing currently proposes) would. This is prospective hardening, not a live defect; the 'do this now' urgency in the fix is unjustified. Keep as a P2 note to be applied together with any future async restructuring.

Fix: No standalone change needed today. If the pipeline is ever made asynchronous (commit without waitUntilCompleted inside the delegate callback), return the CVMetalTexture alongside the MTLTexture and release it in the command buffer's addCompletedHandler. Add a comment at makeTexture noting the lifetime is currently guaranteed by the synchronous waits plus the delegate-held pixel buffer, so the invariant is visible to whoever restructures the sync.

## [60] P1 safe — Tesseract/Tesseract/GIFMachine.swift:227
**The Birkhoff measure shown on RESULT (M/O/C/dim/col) and embedded in the 'Tesseract 4^4' GIF comment is computed from PerfectQuantizer paletteIndices the DYAD-only export never uses — user-facing metrics describe a cube that never ships.**

Verdict: CONFIRMED — Verified in full: CameraManager.swift:666-673 and FaceCaptureManager.swift:369-376 build gifMeasure from frame.paletteIndices; DyadPipeline.process (DyadPipeline.swift:122-123,162) reads only rawRGB/depths and GIFEncoder.encode gets dyad.indexFrames; ContentView.swift:137/240 passes gifMeasure to ResultStateView.metricsRow (74-81) and GIFEncoder.swift:84 writes it into the comment. No decree covers this — CLAUDE.md's own RATE LEDGER line already computes the operational M from the emitted indexFrames, so the phantom measure is a straggler of the 2026-08-12 DYAD-only pivot, not a ruling.

Fix: Compute the measure from dyad.indexFrames inside makeGIF (the histogram is mirror-invariant, so pre-mirror is fine) — note makeGIF returns only Data?, so either return a small (gif, measure) result or add an out parameter/callback; publish that as gifMeasure and pass it to GIFEncoder.encode; delete the paletteIndices aggregation blocks in both capture managers (CameraManager.swift:666-673, FaceCaptureManager.swift:369-376).

## [61] P1 safe — Tesseract/Tesseract/PerfectQuantizer.swift:38
**quantizeFrame runs 64 times over the 40%→80% SOLVING progress span producing palette indices the DYAD export never reads; the real DYAD solve is crammed into the last 15% of the bar.**

Verdict: CONFIRMED — Structurally exact: CameraManager.swift:634-655 (40→80% with per-frame MainActor hops; FACE is 0→80% at FaceCaptureManager.swift:340-361) runs quantizeFrame on every frame, GIFMachine.makeGIF re-derives indices from rawRGB via DyadPipeline, and the only paletteIndices consumers are the phantom measure plus TriScaleLadder.swift:90 / Dissonance.swift:216 telemetry — which CLAUDE.md describes as measuring 'the realized cube' (written pre-pivot, when the tesseract cube WAS the export). QuantizedFrame.measure is never read in-app. The 'half the latency' share is an estimate (DyadPipeline's OKLab staging + mixture fits are also heavy), but the progress-range misallocation and dead compute on the user-facing SOLVING path are real; while the progress bar sits at 0.85 the actual palette solve only updates the phase text.

Fix: Drop quantizeFrame (and its progress phase) from both record paths and re-span the bar over the DYAD solve using onFrameTable's per-frame callback — but DO NOT feed dyad.indexFrames straight into TriScaleLadder/DissonanceField: both decode indices through the 4⁴ TesseractCoord bijection (TriScaleLadder.swift:69-73, Dissonance.swift:218-220), which DYAD frame-local palette indices do not obey. Telemetry over the realized cube must decode through each frame's LCT (RGB-domain rungs) or be re-specced first (spec-before-port discipline); makeGIF must also expose dyad.indexFrames (it currently returns only Data?). Removing paletteIndices also touches the non-optional QuantizedFrame field and its test constructors.

## [62] P2 safe — Tesseract/Tesseract/GIFLibrary.swift:70
**mixtureLine slices raw file bytes without stripping GIF comment sub-block framing, so a DYAD MIXTURE line straddling the 255-byte sub-block boundary renders a garbage character in the LIBRARY detail scene.**

Verdict: DOWNGRADED — The parser deficiency is real (GIFEncoder.swift:184-190 inserts a length byte every 255 bytes; mixtureLine's own comment at line 68 acknowledges sub-blocks yet only cuts at newlines; LibraryView.swift:113/117 renders the result verbatim). But measured against the actual trace layout the trigger is narrow: the MIXTURE line starts at byte ~84 (HARMONY ~52 + SETTINGS 30 + newlines) and its nine values are positive [0,1]-domain quantities that typically print 4-8 chars under %.6g, ending near byte 233 — crossing 255 requires near-maximal widths on almost every field (mass e-notation, or a degenerate crossover/temperature fit blowing sStar/tau wide). Negative values are only possible for the degenerate crossover, not the routine fields. Real latent bug, rare trigger, worst case one replacement character in a micro-register provenance line → P2 polish, not P1.

Fix: Parse the comment extension properly: find the 0x21 0xFE introducer preceding the match, concatenate sub-blocks (skipping each length byte) into a clean string, then extract the DYAD MIXTURE line — this also makes the arbitrary 200-byte bound unnecessary.

## [63] P2 LOOK — Tesseract/Model/GoBoard.swift:69
**blockToGoBoards copies pixels[0..<361] linearly from a 64-wide row-major frame, so the SOLVING scene's three Go boards render scanline-wrapped strip data as a 19×19 square, misrepresenting the spatial color structure they claim to show.**

Verdict: CONFIRMED — Verified: GoBoard.swift:69-74 assigns stones[i] with no stride remap from frame.rgb (4096 px, side 64, passed at CameraManager.swift:614), and ProcessingStateView.swift:51-57 renders stones[y*19+x] as a square, one atom per cell. The 361 pixels cover ~5.6 scanlines; board rows wrap across scanline boundaries, so vertical scene structure appears as diagonal striping. The CameraManager.swift:602-604 comment ('This is a SAMPLE of the frame, not the full grid') documents the shortcut but is a code comment, not a decree, and does not cure the square rendering that GoBoard.swift's own header sells as SPATIAL COLOR STRUCTURE. LIVE-only (FACE passes boards: nil), so it is a P2 fidelity issue in a transient scene.

Fix: Sample a spatially coherent 19×19 window — stones[y*19+x] = pixels[(yOff+y)*64 + xOff+x] centered, or stride-subsample the full 64×64 (x,y → pixel[(y*64/19)*64 + x*64/19]) — so a board row corresponds to a spatial row. Changes rendered board pixels in the SOLVING scene → needs Daniel's device ruling.

## [64] P2 safe — Tesseract/Tesseract/PerfectQuantizer.swift:240
**analyzeSubject and findAnchors run 64 times on the SOLVING path but QuantizedFrame.subjectAnalysis and .anchorTrace are never read anywhere in the app — vestigial per-frame analysis adding dead work to user-facing processing.**

Verdict: CONFIRMED — Repo-wide grep confirms: populated at CameraManager.swift:646-647 and FaceCaptureManager.swift:352-353, the fields' only read is TesseractTests/AxiomTests.swift:600, and every other test constructs frames with nil. Both functions are O(4096) linear scans so the added latency is negligible — the substance is the SIMPLICITY-decree deadcode, not perf; P2 is the right severity. One correction to the finding's parenthetical: AxiomTests reads anchorTrace THROUGH the QuantizedFrame field (line 600), not only via direct calls. Note analyzeSubject's 0.6/0.4 naked thresholds fall under open ruling R5, which covers its constants, not its dead consumers.

Fix: Remove the two fields from QuantizedFrame (FrameBuffer.swift:17-18) and the calls from both record paths; in AxiomTests.testPipeline_syntheticFullRoundtrip repoint the line-600 assertion at the locally computed `anchors` (lines 575-576 call the functions directly and can keep pinning them); update the nil-passing test constructors.

## [65] P2 safe — Tesseract/Tesseract/GIFMachine.swift:171
**A bare print() of the SK GENES trace ships in release on the export (SOLVING) path.**

Verdict: CONFIRMED — Verified at GIFMachine.swift:171-173: unconditional print() inside the CameraConfig.skGenes gate, and the flag is ON in the shipped code (CameraManager.swift:103 `static let skGenes = true` — the code, not the memory note saying OFF, is what ships). Every sibling telemetry channel on this path (TriScale, Dissonance at CameraManager.swift:695-699) goes through logger.info. One short print per export is negligible perf, so this is hygiene/consistency, and no decree protects it. P2 stands.

Fix: Route through an os.Logger (GIFMachine has none today — add one, matching the TriScale/Dissonance pattern) or wrap the print in #if DEBUG; the trace still lands in the GIF comment either way.

## [66] P2 safe — Tesseract/Tesseract/BirkhoffMeasure.swift:38
**binomialExpected and noiseDeviation are referenced nowhere in app or tests, and the dangling 'MARK: - Frame Deviation (per-color breakdown)' at line 91 trails excised code.**

Verdict: CONFIRMED — Repo-wide grep hits only the definitions (BirkhoffMeasure.swift:35, 38-41); the spec's binomialExpectedValue in BinomialCube.hs is a different, unrelated Haskell function. The file ends at line 92 with nothing under the line-91 MARK — a straggler of the pre-unification arc, squarely the SIMPLICITY decree's 'vestigial code paths' category.

Fix: Delete the two statics (lines 34-41) and the trailing MARK comment (line 91).

## [67] P1 safe — Tesseract/GIF/GIFEncoder.swift:205
**LZW dictionary keyed by [UInt8] arrays makes SOLVING-screen encode cost scale with phrase length: every pixel hashes the full growing phrase and every dictionary miss allocates Array(current.dropLast()) plus a second O(len) rehash, over 64 frames of 4x-replicated 256x256 indices on the shipped export path.**

Verdict: CONFIRMED — Code verified: line 205 `var dictionary = [[UInt8]: Int]()`, line 246 hashes the full phrase per pixel, line 250 allocates+rehashes per miss. GIFMachine.swift:241 passes upscale=CameraConfig.exportUpscale=256/64=4 (CameraManager.swift:85-86), so encode LZW-compresses 64x65536 replicated pixels whose long runs grow phrases toward the 4096-code limit; this runs after the last 'Solving palette f/n' onFrameTable update, so it is silent SOLVING latency (charter 7). One nuance: the RATE LEDGER re-run (GIFMachine.swift:142, lzwCost) operates on the UNREPLICATED 64x64 frames (262k px total), so it adds only ~6%, not a second full encode - the dominant cost is the replicated stream itself. No decree protects the implementation; the byte contract (DyadGIFContractTests) is preserved because a chained-code dictionary emits the identical greedy parse.

Fix: Use the standard GIF LZW chained-code dictionary: key = (prefixCode << 8) | nextByte as an Int (or a flat 4096x256 table), value = code. O(1) hashing per pixel, zero per-miss allocations, byte-identical output stream (same codes, same order), so DyadGIFContractTests stay green. lzwCost (line 175) inherits the speedup for free.

## [68] P1 safe — Tesseract/Tesseract/DyadANE.swift:26
**The DyadAssign MLModel is loaded lazily inside the first export's stage-2 dispatch, so the first capture's SOLVING screen silently absorbs MLModel load plus first-run ANE compilation; the isAvailable preload hook exists but is referenced nowhere in the app target.**

Verdict: CONFIRMED — Code verified: line 26 is a lazy `static let model` with computeUnits = .all, first touched at DyadPipeline.swift:375 during stage 2 of the first export - after the last onFrameTable progress callback, so the CoreML load (per launch) and first-run ANE specialization (per install/cache) land silently on the SOLVING screen. Grep confirms zero isAvailable call sites in the app target; however it IS used by TesseractTests/DyadANEParityTests.swift:21 (XCTSkipUnless), so the original fix's 'delete the dead accessor' fallback would break the parity suite - fix text corrected. Warming during WAKING violates no decree (no UI surface, no settings).

Fix: Warm the model during WAKING: `_ = DyadANE.isAvailable` off-main (e.g. Task.detached(priority: .utility) from the capture manager's start path or the loading-screen phase) so the one-time CoreML load/ANE specialization happens under the loading screen instead of the first SOLVING. Do NOT delete isAvailable if preloading is declined - DyadANEParityTests.swift:21 gates on it.

## [69] P2 safe — Tesseract/GIF/GIFEncoder.swift:84
**Every export writes a 'Tesseract 4^4' provenance comment whose numbers describe the deleted tesseract global-table method, not the emitted DYAD cube: the BirkhoffMeasure is computed from PerfectQuantizer lattice paletteIndices that never reach the GIF, and the line quotes a global 'colors=N/256' the per-frame-palette exports no longer have.**

Verdict: CONFIRMED — Verified end to end: GIFEncoder line 84 formats the measure comment; GIFMachine.makeGIF:241 forwards the measure from CameraManager.swift:666-673 (and FaceCaptureManager.swift:369-375 identically), both aggregating QuantizedFrame.paletteIndices = PerfectQuantizer.quantizeFrame output (CameraManager.swift:635-645) - the pre-decree lattice quantization. The emitted indices are dyad.indexFrames (GIFMachine:236-239); the lattice indices never enter the GIF. The operational meter already ships as RATE LEDGER v1 (GIFMachine:128-147) computed from the real index cube. Not a documented ruling - the 2026-08-12 per-frame-palette decree deleted the method this comment describes. Caveat folded into the fix: the measure ALSO feeds ResultStateView via gifMeasure (ContentView.swift:137/240), so only the encoder comment/parameter goes, not the managers' computation (unless the result view is reworked separately).

Fix: Drop the measure comment (and the `measure:` parameter) from GIFEncoder.encode - GIFMachine.makeGIF stops forwarding it. Keep the managers' BirkhoffMeasure computation for now: gifMeasure still drives ResultStateView (ContentView.swift:137/240). Alternatively recompute the Birkhoff line from the emitted DYAD indexFrames so the provenance describes the bytes it rides in. Comment bytes only - no pixel change.

## [70] P2 safe — Tesseract/Tesseract/DyadPipeline.swift:213
**Stage 1 converts each frame's pixels through the pow/cbrt OKLab transform four times (analyze at line 165 converts samples internally, staging at line 168 converts them again, analyze on staged at line 173 converts the staged bytes, and line 213 converts the same staged bytes a fourth time) - roughly 0.5M redundant OKLab conversions per 64-frame capture on the SOLVING path.**

Verdict: CONFIRMED — All four conversion sites verified: DyadPalette.analyze (DyadPalette.swift:293) maps every sample through oklab(fromSRGB8:) and discards the labs; DyadPipeline lines 165 (analyze on samples), 166-170 (staging re-converts samples), 173 (analyze on staged bytes), and 213 (stagedLabs re-converts the same staged bytes) each redo it. The DY12 round-trip is preserved by the proposed reuse: lines 173 and 213 both convert the ALREADY srgb8-round-tripped bytes, so caching one conversion is byte-identical. One correction: the redundant count is ~524k (64 x 4096 px x 2 avoidable passes), not 'roughly 1M' - the claim's own evidence arithmetic gives 524,288; wall-clock impact is small (ms to tens of ms) next to the LZW encode. Real polish, P2 stands.

Fix: Add an analyze overload taking pre-converted [OKLabColor] (the existing byte overload delegates after mapping), convert samples once per frame for both line 165 and the line 168 staging, and hoist the staged-lab conversion so lines 173 and 213 share one [OKLabColor] array (compute stagedLabs in the stage-1a loop and store alongside stagedAll). Byte-identical results; DY12 round-trip untouched (staging still round-trips through srgb8).

## [71] P2 safe — Tesseract/GIF/GIFEncoder.swift:287
**saveToTempFile names the share file with a whole-second timestamp, so two shares of different GIFs within the same second write to the same URL and the second write clobbers the file the first share flow may still reference.**

Verdict: CONFIRMED — Code verified: line 287 `Int(Date().timeIntervalSince1970)` truncates to 1 s resolution, and GIFSaver.presentShareSheet (GIFSaver.swift:39-44) writes then hands the URL to UIActivityViewController, which reads lazily at activity-pick time. The window is narrow for human interaction (a second share sheet cannot present until the first is dismissed, and re-sharing the SAME GIF collides harmlessly with identical bytes), but share -> cancel -> open another library GIF -> share within one second produces a real clobber, and the fix is free. P2 contract polish is the right level.

Fix: Use UUID().uuidString (or a millisecond-resolution timestamp) in the filename so every share URL is unique; optionally clean old tesseract_*.gif temp files on launch.

## [72] P1 safe — Tesseract/Tesseract/Tesseract/TesseractPalette.swift:27
**TesseractPalette is a straggler of the deleted tesseract global-table export method: the app never references it, and its gifColorTable is the global color table the per-frame-palette decree (2026-08-12) killed.**

Verdict: CONFIRMED — Repo-wide grep verified: the only reference outside the file is TesseractTests/AxiomTests.swift:380 (testGCT_exactBytes); uniqueDisplayColors and epochsPerColor have zero references. GIFMachine.swift:216 writes DyadPalette.gifColorTable(table) per frame, and GIFEncoder.swift confirms GCT = frame 0's DYAD table, matching the CLAUDE.md 2026-08-12 per-frame-palette decree that deleted the tesseract/refined global-table methods. The AxiomTests 'LAYER 1b: GCT ROUNDTRIP' section now asserts a contract the shipped GIF no longer carries, which is exactly the charter rule 3 straggler class. DyadGIFContractTests (packed byte 0xF7 at b[10], GCT = frame 0's table) already locks the live contract, so the fix's coverage claim holds. Not decree-protected: no ruling keeps this file.

Fix: Delete TesseractPalette.swift and delete or re-pin AxiomTests.testGCT_exactBytes (the live GCT contract — GCT = frame 0's DYAD table, per-frame LCTs, ground law — is already gated by DyadGIFContractTests). Note TesseractCoord itself stays: buildPreviewImage and AxiomTests layer 1 still use TesseractCoord.sRGB8.

## [73] P2 safe — Tesseract/Tesseract/Model/TesseractCoord.swift:138
**The quantize(frame:r:g:b:) / quantize(epoch:r:g:b:) extension is dead — zero call sites in app, Metal, or tests.**

Verdict: CONFIRMED — grep across all .swift and .metal files finds 'quantize(frame:' and 'quantize(epoch:' only at their definitions (TesseractCoord.swift:142/151); the only other .quantize( hits are DyadPalette.quantize in DyadPaletteTests. The plausible refutation — the warm-up lattice quick-quantize fallback in makePreview — actually routes through PerfectQuantizer.previewQuantize (CameraManager.swift:750), not this extension. Genuinely dead code from the pre-unification preview path; deleting it changes no behavior and breaks no decree.

Fix: Delete the 'MARK: - Quantization' extension (TesseractCoord.swift lines 136-157).

## [74] P2 safe — Tesseract/Tesseract/Model/Axes.swift:136
**BinTarget (the 14-bin bell target distribution and its largest-remainder scaler) is referenced nowhere in the app or tests.**

Verdict: CONFIRMED — Repo-wide grep for BinTarget hits only its definition at Axes.swift:136. Verified the surgical claim about the rest of the file: PerfectQuantizer.swift lines 112-174 actively use ComposedColor, RBin/GBin/BBin, valueToBin, paletteIndex, and TessEpoch, and PerfectQuantizer is live (referenced by CameraManager, FaceCaptureManager, FrameBuffer, MetalPipeline as the warm-up preview quantizer). Neither BinTarget.counts nor BinTarget.scaled(to:) has any consumer, including tests. No spec or decree pins the Swift port of the 14-bin target table.

Fix: Delete the §6 BinTarget block (Axes.swift lines 128-163, comment header plus enum); keep the live newtype and composition sections (§1-§5).

## [75] P2 safe — Tesseract/Tesseract/Tesseract/SKGene.swift:117
**nearestAttractor re-normalizes all 96 attractors from the flat weight blob on every call, allocating two arrays per attractor per call — ~100k redundant normalizations and ~200k transient allocations per export, inside the user-facing SOLVING wait.**

Verdict: CONFIRMED — All evidence verified: line 117 is 'let an = normalized(Array(attractors[i * 24 ..< i * 24 + 24]))' inside the loop over SKGeneWeights.attractorNF.count, which is exactly 96 (counted); SKGene.trace calls nearestAttractor(z1) at line 238 for the two non-chaos classes over 8x8x8=512 blocks each = 1024 calls; CameraConfig.skGenes = true at CameraManager.swift:103 (GIFMachine.swift:164 comment says 'default ON'), and the trace runs inside GIFMachine's comment assembly (lines 166-170) before makeGIF returns, i.e. inside SOLVING. 1024 x 96 = 98,304 normalizations with an Array slice plus a map allocation each = ~197k transient allocations. P2 is the right severity: the wall-clock cost is likely a few ms next to trace's own 64-cube OKLab pooling, so this is polish, not jank. The fix is behavior-identical (cached deterministic computation).

Fix: Hoist the unit-normalized attractors into a one-time 'private static let attractorsUnit' (sliced and normalized once, matching the existing sliced-weight pattern at SKGene.swift lines 33-49) and index into it inside nearestAttractor. Bitwise-identical results, zero per-call allocation.

## [76] P2 safe — Tesseract/Tesseract/Tesseract/Dissonance.swift:229
**DissonanceField.telemetry (17 designTuning runs, each sweeping 2x1200-point detune curves with per-point comb allocations, plus 17 full 64-cube occupancy scans) and TriScaleLadder.telemetry run synchronously between GIF completion and the .done state transition, extending user-visible SOLVING for measurement-only work no GIF byte depends on.**

Verdict: CONFIRMED — Placement verified: CameraManager.swift:693-700 and FaceCaptureManager.swift:396-403 run TriScaleLadder.telemetry then DissonanceField.telemetry after GIFMachine.makeGIF/GIFLibrary.archive but before the MainActor.run block that sets state = .done, so the terminal state waits on telemetry both decree-bound as measurement-only (Dissonance.swift:15-16, TriScaleLadder.swift header, CLAUDE.md). designTuning cost verified exactly: 17 invocations (loop at line 239 + 16 slices at lines 241-244), each 1200x16 + 1200x32 = 57,600 dPair calls with a fresh comb array per grid point. One evidence correction: it is NOT '17 full 64-cube occupancy scans' — occupancy12 is called 17 times but the 16 slice calls scan 4 frames each, so total occupancy work is 2 full-cube passes (~524k index reads). The published rungTelemetry/dissonance properties have no consumers beyond the two logger.info lines (no view reads them), so reordering is free and breaks no decree. Real but modest (likely tens of ms of ~1M exp() calls on device): P2 stands.

Fix: Move both telemetry computations after the state transition, or into a detached task that captures quantizedFrames and publishes rungTelemetry/dissonance via MainActor when ready, so .done is reached as soon as the GIF bytes exist. The only consumers are the two logger lines, so ordering is unconstrained; the telemetry-only decrees (no GIF byte depends on either module) make the move decree-safe.

## Completeness sweep
COVERAGE REPORT — Tesseract UI/UX audit completeness check

(a) Source files vs claims:
- All 62 Swift/Metal files under /Users/daniel/Tesseract/Tesseract (9,945 lines total) appear in the claimed coverage, and every claimed linesRead exactly matches the wc -l count. No app source file is uncovered and none is materially under-read.
- Duplicates in the claim list (ProcessingStateView.swift, CellText.swift listed twice under relative + absolute paths) are harmless.
- NOT covered but arguably in scope for a full-coverage audit: the test suite at /Users/daniel/Tesseract/TesseractTests (26 files, incl. SurfaceMachineTests.swift, CellMechanicsParityTests.swift, LatticeLawTests.swift — UI-behavior contracts). Also nothing outside Tesseract/ was claimed except CLAUDE.md: spec/, isp-spec/, nn/, scripts/ were skipped (mostly non-UI, defensible).

(b) UI-adjacent surfaces structurally missed by the buckets:
1. /Users/daniel/Tesseract/project.yml (88 lines) — carries ALL Info.plist-driven UI strings because GENERATE_INFOPLIST_FILE: YES: NSCameraUsageDescription, NSPhotoLibraryAddUsageDescription (user-facing permission-dialog copy), CFBundleDisplayName, portrait-only orientation lock, and UILaunchScreen_Generation: true. None of this copy was reviewed by any bucket.
2. LaunchScreen — there is no LaunchScreen storyboard/xib; launch UI is the auto-generated blank screen via INFOPLIST_KEY_UILaunchScreen_Generation. Worth a deliberate finding (blank white flash vs app's dark surface) rather than silence.
3. /Users/daniel/Tesseract/Tesseract/Assets.xcassets — AppIcon.appiconset (icon_1024 + dark + tinted variants) and AccentColor.colorset (Contents.json shows whether an accent is actually defined; accent color leaks into system-tinted controls/alerts). Unreviewed.
4. GRID constitution lint phase — project.yml preBuildScripts runs scripts/lint-grid.sh (ENABLE_USER_SCRIPT_SANDBOXING: NO to allow it); the lint script itself, which enforces UI constitution rules, was not read.
5. /Users/daniel/Tesseract/Tesseract/PrivacyInfo.xcprivacy (29 lines) — privacy manifest; relevant given the OPEN ITMS-91053 manifest blocker noted in project memory.
6. No .strings/.xcstrings files exist — all user-facing copy is hardcoded in Swift plus the two project.yml usage strings; no localization surface missed beyond that.

Verdict: source-file coverage is complete and line-accurate; the structural gaps are project.yml (permission-dialog copy + launch/orientation config), scripts/lint-grid.sh, Assets.xcassets, PrivacyInfo.xcprivacy, and the TesseractTests UI-contract tests.