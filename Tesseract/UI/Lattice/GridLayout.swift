// GridLayout.swift
// Tesseract
//
// LAYOUT IS DATA. A scene is a list of named rectangular cell claims,
// machine-checked disjoint, in-bounds, and touch-floor legal. Views
// place themselves ONLY through View.place(_:) with one of these
// regions — hand positioning is banned by scripts/lint-grid.sh.
//
// Every interactive region names a face in CellMechanics.controlFaces
// (frame | brackets) — enforced by LINT-CONTROL-FACE.

import Foundation

/// A widget's rectangular claim on the 100×218 atom grid.
struct GridRegion: Equatable {
    let name: String
    let col: Int
    let row: Int
    let w: Int
    let h: Int
    let interactive: Bool

    // Labeled by design: four bare Ints in a row invite col/row and
    // w/h transpositions that selfCheck can't always catch (an
    // in-bounds transposed region is legal — and wrong).
    init(_ name: String, col: Int, row: Int, w: Int, h: Int,
         interactive: Bool = false) {
        self.name = name
        self.col = col; self.row = row
        self.w = w; self.h = h
        self.interactive = interactive
    }

    func overlaps(_ o: GridRegion) -> Bool {
        col < o.col + o.w && o.col < col + w &&
        row < o.row + o.h && o.row < row + h
    }
}

enum GridLayout {

    // ── Chrome ──
    // SIMPLICITY DECREE (2026-08-09): no shared chrome. The main
    // surface is preview + record + settings, nothing else. Mode
    // selection moved into the settings scene.
    static let chrome: [GridRegion] = []

    /// The one piece of surface chrome: the settings button, top-right.
    static let settingsButton = GridRegion("settingsButton", col: 73, row: 14, w: 24, h: 13, interactive: true)

    // ── Capture scene (CameraState.previewing, LIVE) ──
    static let preview = GridRegion("preview", col: 18, row: 48, w: 64, h: 64)
    static let record = GridRegion("record", col: 39, row: 172, w: 22, h: 22, interactive: true)

    // SIMPLICITY: the capture surface is exactly three claims.
    static let captureScene: [GridRegion] = [
        preview, record, settingsButton,
    ]

    // ── Face preview scene (FACE .previewing) ──
    // faceDot is placed transiently (2s after each face-found/lost
    // transition, then hidden) — decree amendment 2026-08-09.
    static let faceDot = GridRegion("faceDot", col: 18, row: 116, w: 64, h: 6)

    static let facePreviewScene: [GridRegion] = [
        preview, record, settingsButton, faceDot,
    ]

    // ── Recording scene (shared LIVE + FACE) ──
    static let recCounter = GridRegion("recCounter", col: 18, row: 120, w: 64, h: 10)
    static let recProgress = GridRegion("recProgress", col: 18, row: 134, w: 64, h: 4)
    static let recTime = GridRegion("recTime", col: 18, row: 142, w: 64, h: 5)

    static let recordingScene: [GridRegion] = chrome + [
        preview, recCounter, recProgress, recTime,
    ]

    // ── Processing scene (shared; boards render empty for FACE) ──
    static let procTitle = GridRegion("procTitle", col: 18, row: 30, w: 64, h: 8)
    static let procBoards = GridRegion("procBoards", col: 10, row: 48, w: 79, h: 28)
    /// The palette being created: 16×16 entries at 2 cells (128 pt).
    static let procPalette = GridRegion("procPalette", col: 34, row: 80, w: 32, h: 32)
    static let procBar = GridRegion("procBar", col: 18, row: 116, w: 64, h: 4)
    static let procPct = GridRegion("procPct", col: 18, row: 124, w: 64, h: 10)
    static let procPhase = GridRegion("procPhase", col: 10, row: 138, w: 80, h: 12)

    static let processingScene: [GridRegion] = chrome + [
        procTitle, procBoards, procPalette, procBar, procPct, procPhase,
    ]

    // ── Result scene (shared LIVE + FACE) ──
    static let resultGif = GridRegion("resultGif", col: 18, row: 48, w: 64, h: 64)
    static let resultMetrics = GridRegion("resultMetrics", col: 18, row: 116, w: 64, h: 10)
    static let resultShare = GridRegion("resultShare", col: 5, row: 172, w: 27, h: 13, interactive: true)
    static let resultKeep = GridRegion("resultKeep", col: 36, row: 172, w: 27, h: 13, interactive: true)
    static let resultRetake = GridRegion("resultRetake", col: 67, row: 172, w: 27, h: 13, interactive: true)
    /// Second register for KEEP outcomes (photos denied / save failed).
    static let resultNote = GridRegion("resultNote", col: 10, row: 130, w: 80, h: 6)

    static let resultScene: [GridRegion] = chrome + [
        resultGif, resultMetrics, resultShare, resultKeep, resultRetake,
        resultNote,
    ]

    // ── Idle scene ──
    static let idleTitle = GridRegion("idleTitle", col: 26, row: 90, w: 48, h: 12)
    static let idleSub = GridRegion("idleSub", col: 26, row: 106, w: 48, h: 6)
    static let idleBusy = GridRegion("idleBusy", col: 44, row: 118, w: 12, h: 12)
    static let idleHint = GridRegion("idleHint", col: 18, row: 134, w: 64, h: 5)

    static let idleScene: [GridRegion] = chrome + [
        idleTitle, idleSub, idleBusy, idleHint,
    ]

    // ── Error scene (shared LIVE + FACE) ──
    static let errTitle = GridRegion("errTitle", col: 18, row: 88, w: 64, h: 8)
    static let errMsg = GridRegion("errMsg", col: 10, row: 100, w: 80, h: 14)
    static let errRetry = GridRegion("errRetry", col: 20, row: 120, w: 26, h: 13, interactive: true)
    static let errSettings = GridRegion("errSettings", col: 54, row: 120, w: 26, h: 13, interactive: true)

    static let errorScene: [GridRegion] = chrome + [
        errTitle, errMsg, errRetry, errSettings,
    ]

    // ── Settings scene (fullScreenCover — its own canvas) ──
    // CAMERA row (LIVE/FACE) + LOOK radio (the 64³ machine's methods).
    static let setTitle = GridRegion("setTitle", col: 18, row: 20, w: 64, h: 10)
    static let setModeLabel = GridRegion("setModeLabel", col: 18, row: 44, w: 64, h: 6)
    static let setModeLive = GridRegion("setModeLive", col: 18, row: 54, w: 28, h: 13, interactive: true)
    static let setModeFace = GridRegion("setModeFace", col: 54, row: 54, w: 28, h: 13, interactive: true)
    static let setLookLabel = GridRegion("setLookLabel", col: 18, row: 78, w: 64, h: 6)
    static let lookDyad = GridRegion("lookDyad", col: 18, row: 90, w: 64, h: 13, interactive: true)
    static let lookRefine = GridRegion("lookRefine", col: 18, row: 107, w: 64, h: 13, interactive: true)
    static let lookTess = GridRegion("lookTess", col: 18, row: 124, w: 64, h: 13, interactive: true)
    // The two useful-and-simple toggles: DYAD background bleed,
    // export mirroring. Both persisted (ExportSettings).
    static let toggleBleed = GridRegion("toggleBleed", col: 18, row: 144, w: 64, h: 13, interactive: true)
    static let toggleMirror = GridRegion("toggleMirror", col: 18, row: 161, w: 64, h: 13, interactive: true)
    /// The GIF archive entry (2026-08-10): review old GIFs + palettes.
    static let setLibrary = GridRegion("setLibrary", col: 18, row: 178, w: 64, h: 13, interactive: true)
    static let setClose = GridRegion("setClose", col: 38, row: 197, w: 24, h: 13, interactive: true)

    static let settingsScene: [GridRegion] = [
        setTitle, setModeLabel, setModeLive, setModeFace,
        setLookLabel, lookDyad, lookRefine, lookTess,
        toggleBleed, toggleMirror, setLibrary, setClose,
    ]

    // ── Library scene (fullScreenCover — its own canvas) ──
    // 3×3 grid of archived GIFs (20-cell tiles), then the selected
    // GIF playing beside its 256-entry palette, provenance line, and
    // SHARE / DELETE. Latest nine; older files stay on disk.
    static let libTitle = GridRegion("libTitle", col: 18, row: 14, w: 64, h: 10)
    static let libCell0 = GridRegion("libCell0", col: 16, row: 28, w: 20, h: 20, interactive: true)
    static let libCell1 = GridRegion("libCell1", col: 38, row: 28, w: 20, h: 20, interactive: true)
    static let libCell2 = GridRegion("libCell2", col: 60, row: 28, w: 20, h: 20, interactive: true)
    static let libCell3 = GridRegion("libCell3", col: 16, row: 50, w: 20, h: 20, interactive: true)
    static let libCell4 = GridRegion("libCell4", col: 38, row: 50, w: 20, h: 20, interactive: true)
    static let libCell5 = GridRegion("libCell5", col: 60, row: 50, w: 20, h: 20, interactive: true)
    static let libCell6 = GridRegion("libCell6", col: 16, row: 72, w: 20, h: 20, interactive: true)
    static let libCell7 = GridRegion("libCell7", col: 38, row: 72, w: 20, h: 20, interactive: true)
    static let libCell8 = GridRegion("libCell8", col: 60, row: 72, w: 20, h: 20, interactive: true)
    static let libDetailGif = GridRegion("libDetailGif", col: 6, row: 104, w: 44, h: 44)
    static let libDetailPalette = GridRegion("libDetailPalette", col: 56, row: 108, w: 32, h: 32)
    static let libInfo = GridRegion("libInfo", col: 6, row: 152, w: 88, h: 12)
    static let libShare = GridRegion("libShare", col: 14, row: 168, w: 27, h: 13, interactive: true)
    static let libDelete = GridRegion("libDelete", col: 59, row: 168, w: 27, h: 13, interactive: true)
    static let libClose = GridRegion("libClose", col: 38, row: 197, w: 24, h: 13, interactive: true)

    static let libCells: [GridRegion] = [
        libCell0, libCell1, libCell2, libCell3, libCell4,
        libCell5, libCell6, libCell7, libCell8,
    ]

    static let libraryScene: [GridRegion] =
        [libTitle] + libCells
        + [libDetailGif, libDetailPalette, libInfo, libShare, libDelete, libClose]

    /// Every proven scene, by name (for the launch selfCheck).
    static let allScenes: [(name: String, regions: [GridRegion])] = [
        ("capture", captureScene),
        ("facePreview", facePreviewScene),
        ("recording", recordingScene),
        ("processing", processingScene),
        ("result", resultScene),
        ("idle", idleScene),
        ("error", errorScene),
        ("settings", settingsScene),
        ("library", libraryScene),
    ]

    // ── Self-check: disjoint ∧ in-bounds ∧ touch-floor ∧ faces total ──

    static func selfCheck() {
        for (name, scene) in allScenes {
            check(scene: scene, named: name)
        }
        precondition(preview.w == TesseractLattice.previewCells
                  && preview.h == TesseractLattice.previewCells,
                     "preview region must be exactly the GIF (64×64 cells)")
        precondition(record.w == TesseractLattice.recordCells,
                     "record region must match the shutter footprint")
        // Every interactive region names a face (lawControlFaceTotal —
        // the runtime mirror of LINT-CONTROL-FACE).
        for (sceneName, scene) in allScenes {
            for r in scene where r.interactive {
                precondition(CellMechanics.controlFaces[r.name] != nil,
                             "\(sceneName).\(r.name) is interactive but has no control face")
            }
        }
    }

    private static func check(scene: [GridRegion], named name: String) {
        for r in scene {
            precondition(r.col >= 0 && r.row >= 0
                      && r.col + r.w <= TesseractLattice.cols
                      && r.row + r.h <= TesseractLattice.rows,
                         "\(name): region \(r.name) out of bounds")
            if r.interactive {
                precondition(min(r.w, r.h) >= TesseractLattice.touchFloorCells,
                             "\(name): interactive region \(r.name) below 44pt touch floor")
            }
        }
        for i in scene.indices {
            for j in scene.indices where j > i {
                precondition(!scene[i].overlaps(scene[j]),
                             "\(name): regions \(scene[i].name) and \(scene[j].name) overlap")
            }
        }
    }
}
