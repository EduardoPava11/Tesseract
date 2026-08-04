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

    init(_ name: String, _ col: Int, _ row: Int, _ w: Int, _ h: Int,
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
    static let modeBar = GridRegion("modeBar", 0, 14, 100, 11, interactive: true)
    static let eliteButton = GridRegion("eliteButton", 76, 30, 22, 11, interactive: true)

    // ── Capture scene (CameraState.previewing) ──
    static let gauge = GridRegion("gauge", 18, 30, 54, 10)
    static let preview = GridRegion("preview", 18, 48, 64, 64)
    static let channels = GridRegion("channels", 23, 116, 54, 15)
    static let captureInfo = GridRegion("captureInfo", 18, 135, 64, 5)
    static let palette = GridRegion("palette", 12, 176, 16, 16)
    static let record = GridRegion("record", 41, 174, 18, 18, interactive: true)

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
