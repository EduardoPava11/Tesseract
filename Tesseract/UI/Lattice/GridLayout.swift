// GridLayout.swift
// Tesseract
//
// LAYOUT IS DATA. A scene is a list of named rectangular cell claims,
// machine-checked disjoint, in-bounds, and touch-floor legal. Views
// place themselves ONLY through View.place(_:) with one of these
// regions — hand positioning is banned by scripts/lint-grid.sh.

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

    // ── Chrome (every LIVE state) ──
    static let modeBar = GridRegion("modeBar", col: 0, row: 14, w: 100, h: 11, interactive: true)
    static let eliteButton = GridRegion("eliteButton", col: 76, row: 30, w: 22, h: 11, interactive: true)

    // ── Capture scene (CameraState.previewing) ──
    static let gauge = GridRegion("gauge", col: 18, row: 30, w: 54, h: 10)
    static let preview = GridRegion("preview", col: 18, row: 48, w: 64, h: 64)
    static let channels = GridRegion("channels", col: 23, row: 116, w: 54, h: 15)
    static let captureInfo = GridRegion("captureInfo", col: 18, row: 135, w: 64, h: 5)
    static let palette = GridRegion("palette", col: 12, row: 176, w: 16, h: 16)
    static let record = GridRegion("record", col: 41, row: 174, w: 18, h: 18, interactive: true)

    /// The proven scene: all claims that can coexist on the capture surface.
    static let captureScene: [GridRegion] = [
        modeBar, eliteButton,
        gauge, preview, channels, captureInfo, palette, record,
    ]

    // ── Self-check: disjoint ∧ in-bounds ∧ touch-floor legal ──

    static func selfCheck() {
        let scene = captureScene
        for r in scene {
            precondition(r.col >= 0 && r.row >= 0
                      && r.col + r.w <= TesseractLattice.cols
                      && r.row + r.h <= TesseractLattice.rows,
                         "region \(r.name) out of bounds")
            if r.interactive {
                precondition(min(r.w, r.h) >= TesseractLattice.touchFloorCells,
                             "interactive region \(r.name) below 44pt touch floor")
            }
        }
        for i in scene.indices {
            for j in scene.indices where j > i {
                precondition(!scene[i].overlaps(scene[j]),
                             "regions \(scene[i].name) and \(scene[j].name) overlap")
            }
        }
        precondition(preview.w == TesseractLattice.previewCells
                  && preview.h == TesseractLattice.previewCells,
                     "preview region must be exactly the GIF (64×64 cells)")
        precondition(record.w == TesseractLattice.recordCells,
                     "record region must match the shutter footprint")
    }
}
