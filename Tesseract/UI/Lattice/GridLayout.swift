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

    // ── Chrome (shared across main-canvas scenes) ──
    // The mode bar split into three touch-floor-legal claims (the old
    // full-width bar put ~24pt pills inside a 44pt strip).
    static let wordmark = GridRegion("wordmark", col: 3, row: 14, w: 30, h: 11)
    static let modeLive = GridRegion("modeLive", col: 55, row: 14, w: 20, h: 11, interactive: true)
    static let modeFace = GridRegion("modeFace", col: 77, row: 14, w: 20, h: 11, interactive: true)
    static let eliteButton = GridRegion("eliteButton", col: 76, row: 30, w: 22, h: 11, interactive: true)

    /// DEPRECATED — the pre-split full-width bar; ContentView still
    /// places it until the chrome conversion. Not in any scene array.
    static let modeBar = GridRegion("modeBar", col: 0, row: 14, w: 100, h: 11, interactive: true)

    /// Chrome present in every main-canvas scene.
    static let chrome: [GridRegion] = [wordmark, modeLive, modeFace]

    // ── Capture scene (CameraState.previewing, LIVE) ──
    static let gauge = GridRegion("gauge", col: 18, row: 30, w: 54, h: 10)
    static let preview = GridRegion("preview", col: 18, row: 48, w: 64, h: 64)
    static let channels = GridRegion("channels", col: 23, row: 116, w: 54, h: 15)
    static let captureInfo = GridRegion("captureInfo", col: 18, row: 135, w: 64, h: 5)
    static let palette = GridRegion("palette", col: 12, row: 176, w: 16, h: 16)
    static let record = GridRegion("record", col: 41, row: 174, w: 18, h: 18, interactive: true)

    static let captureScene: [GridRegion] = chrome + [
        eliteButton,
        gauge, preview, channels, captureInfo, palette, record,
    ]

    // ── Face preview scene (FACE .previewing; no elite gallery) ──
    static let faceDot = GridRegion("faceDot", col: 18, row: 116, w: 64, h: 6)

    static let facePreviewScene: [GridRegion] = chrome + [
        gauge, preview, faceDot, captureInfo, palette, record,
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
    static let procBar = GridRegion("procBar", col: 18, row: 116, w: 64, h: 4)
    static let procPct = GridRegion("procPct", col: 18, row: 124, w: 64, h: 10)
    static let procPhase = GridRegion("procPhase", col: 10, row: 138, w: 80, h: 10)

    static let processingScene: [GridRegion] = chrome + [
        procTitle, procBoards, procBar, procPct, procPhase,
    ]

    // ── Dual-explore scene ──
    // 68 = 64 tile + 1-cell gutter + 1-cell bracket per flank; the
    // projection strips live IN the gutter ring. Rows 27-41 stay clear
    // for the elite button.
    static let panelA = GridRegion("panelA", col: 16, row: 42, w: 68, h: 68, interactive: true)
    static let panelB = GridRegion("panelB", col: 16, row: 112, w: 68, h: 68, interactive: true)
    static let scrubber = GridRegion("scrubber", col: 18, row: 182, w: 64, h: 11, interactive: true)
    static let stats = GridRegion("stats", col: 18, row: 195, w: 64, h: 16)

    static let dualExploreScene: [GridRegion] = chrome + [
        eliteButton, panelA, panelB, scrubber, stats,
    ]

    // ── Refining scene ──
    static let refineGif = GridRegion("refineGif", col: 16, row: 44, w: 68, h: 68, interactive: true)
    static let alphaReadout = GridRegion("alphaReadout", col: 18, row: 120, w: 64, h: 8)
    static let refHints = GridRegion("refHints", col: 18, row: 132, w: 64, h: 6)

    static let refiningScene: [GridRegion] = chrome + [
        eliteButton, refineGif, alphaReadout, refHints,
    ]

    // ── Result scene (shared LIVE + FACE) ──
    static let resultGif = GridRegion("resultGif", col: 18, row: 48, w: 64, h: 64)
    static let resultMetrics = GridRegion("resultMetrics", col: 18, row: 116, w: 64, h: 10)
    static let resultShare = GridRegion("resultShare", col: 18, row: 174, w: 18, h: 11, interactive: true)
    static let resultKeep = GridRegion("resultKeep", col: 41, row: 174, w: 18, h: 11, interactive: true)
    static let resultRetake = GridRegion("resultRetake", col: 64, row: 174, w: 18, h: 11, interactive: true)

    static let resultScene: [GridRegion] = chrome + [
        eliteButton, resultGif, resultMetrics, resultShare, resultKeep, resultRetake,
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
    static let errRetry = GridRegion("errRetry", col: 24, row: 120, w: 22, h: 11, interactive: true)
    static let errSettings = GridRegion("errSettings", col: 54, row: 120, w: 22, h: 11, interactive: true)

    static let errorScene: [GridRegion] = chrome + [
        errTitle, errMsg, errRetry, errSettings,
    ]

    // ── Elite-map scene (fullScreenCover — its own canvas, no chrome) ──
    // Gallery tiles are 20×20 cells = 80pt, over the 11-cell touch floor.
    static let eliteHeader = GridRegion("eliteHeader", col: 18, row: 20, w: 64, h: 10)
    static let eliteColLabels = GridRegion("eliteColLabels", col: 16, row: 32, w: 64, h: 4)
    static let eliteRowLabel0 = GridRegion("eliteRowLabel0", col: 4, row: 38, w: 10, h: 20)
    static let eliteRowLabel1 = GridRegion("eliteRowLabel1", col: 4, row: 60, w: 10, h: 20)
    static let eliteRowLabel2 = GridRegion("eliteRowLabel2", col: 4, row: 82, w: 10, h: 20)
    static let eliteCell0 = GridRegion("eliteCell0", col: 16, row: 38, w: 20, h: 20, interactive: true)
    static let eliteCell1 = GridRegion("eliteCell1", col: 38, row: 38, w: 20, h: 20, interactive: true)
    static let eliteCell2 = GridRegion("eliteCell2", col: 60, row: 38, w: 20, h: 20, interactive: true)
    static let eliteCell3 = GridRegion("eliteCell3", col: 16, row: 60, w: 20, h: 20, interactive: true)
    static let eliteCell4 = GridRegion("eliteCell4", col: 38, row: 60, w: 20, h: 20, interactive: true)
    static let eliteCell5 = GridRegion("eliteCell5", col: 60, row: 60, w: 20, h: 20, interactive: true)
    static let eliteCell6 = GridRegion("eliteCell6", col: 16, row: 82, w: 20, h: 20, interactive: true)
    static let eliteCell7 = GridRegion("eliteCell7", col: 38, row: 82, w: 20, h: 20, interactive: true)
    static let eliteCell8 = GridRegion("eliteCell8", col: 60, row: 82, w: 20, h: 20, interactive: true)
    static let eliteDetail = GridRegion("eliteDetail", col: 28, row: 110, w: 44, h: 44)
    static let eliteMetrics = GridRegion("eliteMetrics", col: 18, row: 158, w: 64, h: 8)
    static let eliteShare = GridRegion("eliteShare", col: 24, row: 170, w: 20, h: 11, interactive: true)
    static let eliteKeep = GridRegion("eliteKeep", col: 56, row: 170, w: 20, h: 11, interactive: true)
    static let eliteClose = GridRegion("eliteClose", col: 40, row: 190, w: 20, h: 11, interactive: true)

    static let eliteCells: [GridRegion] = [
        eliteCell0, eliteCell1, eliteCell2,
        eliteCell3, eliteCell4, eliteCell5,
        eliteCell6, eliteCell7, eliteCell8,
    ]

    static let eliteMapScene: [GridRegion] =
        [eliteHeader, eliteColLabels,
         eliteRowLabel0, eliteRowLabel1, eliteRowLabel2]
        + eliteCells
        + [eliteDetail, eliteMetrics, eliteShare, eliteKeep, eliteClose]

    /// Every proven scene, by name (for the launch selfCheck).
    static let allScenes: [(name: String, regions: [GridRegion])] = [
        ("capture", captureScene),
        ("facePreview", facePreviewScene),
        ("recording", recordingScene),
        ("processing", processingScene),
        ("dualExplore", dualExploreScene),
        ("refining", refiningScene),
        ("result", resultScene),
        ("idle", idleScene),
        ("error", errorScene),
        ("eliteMap", eliteMapScene),
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
