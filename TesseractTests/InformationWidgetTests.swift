// InformationWidgetTests.swift
// Tesseract
//
// Swift mirrors of the four instruments Daniel named, as ported in
// Tesseract/UI/Widgets/InformationWidgets.swift from spec/ui/
// WidgetGrid.hs (WG1 footprints, WG8 integer cells, WG12 the rungs
// and the 16×16 = 256 bijection).
//
// What is testable is tested: the palette's 16×16 totality, the bar's
// clamping, the timer's formatting — plus the two laws only the port
// can check, that every footprint equals the spec's row and that the
// timer's ink, rasterized by CellText at its real register, FITS its
// footprint (the SurfaceMachineTests pattern: exact ink, no estimates).
//
// Pure logic + UIKit raster — runs on the simulator.

import XCTest
import simd
@testable import Tesseract

final class InformationWidgetTests: XCTestCase {

    // MARK: - WG1: the footprint table is the spec's, row for row

    func testFootprintsMatchTheSpec() {
        // spec/ui/WidgetGrid.hs §1 `footprint`.
        XCTAssertEqual(PreviewWidget.footprint.w, 64)
        XCTAssertEqual(PreviewWidget.footprint.h, 64)
        XCTAssertEqual(PaletteWidget.footprint.w, 16)
        XCTAssertEqual(PaletteWidget.footprint.h, 16)
        XCTAssertEqual(TimerWidget.footprint.w, 20)
        XCTAssertEqual(TimerWidget.footprint.h, 7)
        XCTAssertEqual(FrameBarWidget.footprint.w, 64)
        XCTAssertEqual(FrameBarWidget.footprint.h, 2)
    }

    func testFootprintsComeFromTheOneTable() {
        // WG1: there is ONE footprint table (Widget.spec). A widget view
        // that restated its size would drift from the arrangement that
        // places it — these assertions are that seam, welded shut.
        XCTAssertEqual(PreviewWidget.footprint, Widget.preview64.spec)
        XCTAssertEqual(PaletteWidget.footprint, Widget.palette.spec)
        XCTAssertEqual(TimerWidget.footprint, Widget.timer.spec)
        XCTAssertEqual(FrameBarWidget.footprint, Widget.framesBar.spec)
        XCTAssertEqual(FrameBarReadout.cols, Widget.framesBar.spec.w)
        XCTAssertEqual(FrameBarReadout.rows, Widget.framesBar.spec.h)
        // WG9: none of the four reporters takes touch.
        for w in [Widget.preview64, .palette, .timer, .framesBar] {
            XCTAssertFalse(w.interactive, "\(w.rawValue) is a reporter")
        }
    }

    func testFootprintsAreDerivedNotWritten() {
        // The pinned dimensions must track their source laws, so a
        // re-based lattice or a moved rung fails HERE, not silently in
        // a mis-sized widget.
        XCTAssertEqual(PreviewWidget.footprint.w, TesseractLattice.previewCells)
        XCTAssertEqual(PreviewWidget.footprint.w, CameraConfig.outputSize,
                       "L5: the preview widget IS the GIF")
        XCTAssertEqual(PaletteWidget.footprint.w, PaletteReadout.side)
        XCTAssertEqual(PaletteWidget.footprint.w, Rung.coarse.side)
        XCTAssertEqual(FrameBarWidget.footprint.w, TesseractLattice.previewCells)
    }

    // MARK: - WG12 / the bijection: 16 × 16 = 256, totally

    func testPaletteIsSixteenBySixteen() {
        XCTAssertEqual(PaletteReadout.side, 16)
        XCTAssertEqual(PaletteReadout.entryCount, 256)
        XCTAssertEqual(PaletteReadout.entryCount, CameraConfig.paletteSize,
                       "16×16 must be exactly the palette (the bijection)")
        // WG12: footprint Palette == footprint Preview16 (the coarse read).
        XCTAssertEqual(PaletteWidget.footprint.w, Rung.coarse.side)
        XCTAssertEqual(PaletteWidget.footprint.h, Rung.coarse.side)
    }

    func testPaletteIndexIsABijectionOntoTheTable() {
        var seen: [Int] = []
        for r in 0 ..< PaletteReadout.side {
            for c in 0 ..< PaletteReadout.side {
                seen.append(PaletteReadout.index(col: c, row: r))
            }
        }
        XCTAssertEqual(seen.count, PaletteReadout.entryCount)
        XCTAssertEqual(Set(seen).count, PaletteReadout.entryCount,
                       "every cell must name a DISTINCT entry")
        XCTAssertEqual(seen.sorted(), Array(0 ..< PaletteReadout.entryCount),
                       "the cells must cover 0..<256 exactly — no resampling")
        // Row-major, the order the DYAD table is written in.
        XCTAssertEqual(PaletteReadout.index(col: 0, row: 0), 0)
        XCTAssertEqual(PaletteReadout.index(col: 15, row: 0), 15)
        XCTAssertEqual(PaletteReadout.index(col: 0, row: 1), 16)
        XCTAssertEqual(PaletteReadout.index(col: 15, row: 15), 255)
    }

    func testPaletteReadsEveryEntryExactlyOnce() {
        let table = Self.syntheticTable()
        XCTAssertTrue(PaletteReadout.isComplete(table))
        var inks: [SIMD3<UInt8>] = []
        for r in 0 ..< PaletteReadout.side {
            for c in 0 ..< PaletteReadout.side {
                let ink = PaletteReadout.ink(table, col: c, row: r)
                let e = table[PaletteReadout.index(col: c, row: r)]
                XCTAssertEqual(ink, SIMD3(e.0, e.1, e.2),
                               "cell (\(c),\(r)) must show its own entry")
                inks.append(ink)
            }
        }
        XCTAssertEqual(Set(inks.map { [$0.x, $0.y, $0.z] }).count, 256,
                       "256 distinct entries must render as 256 distinct cells")
    }

    // MARK: - Empty is a STATE, not a hole

    func testEmptyPaletteRendersTheCheckerNotAHole() {
        let empty: [(UInt8, UInt8, UInt8)] = []
        XCTAssertFalse(PaletteReadout.isComplete(empty))
        var lit = 0, ghost = 0
        for r in 0 ..< PaletteReadout.side {
            for c in 0 ..< PaletteReadout.side {
                let ink = PaletteReadout.ink(empty, col: c, row: r)
                if ink == Ink.ledGhost { lit += 1 }
                else if ink == CellChecker.dark { ghost += 1 }
                else { XCTFail("unsolved cell (\(c),\(r)) must wear the checker") }
            }
        }
        XCTAssertEqual(lit + ghost, PaletteReadout.entryCount)
        XCTAssertGreaterThan(lit, 0, "a checker, not a blank hole")
        XCTAssertGreaterThan(ghost, 0, "a checker, not a blank hole")
        XCTAssertEqual(lit, ghost, "the 2×2 checker splits 16×16 evenly")
    }

    func testPartialPaletteFallsBackPerCell() {
        // A short table can only come from a partial publish; each cell
        // answers for ITSELF rather than the whole widget going dark.
        let partial = Array(Self.syntheticTable().prefix(100))
        XCTAssertFalse(PaletteReadout.isComplete(partial))
        for i in 0 ..< PaletteReadout.entryCount {
            let c = i % PaletteReadout.side, r = i / PaletteReadout.side
            let ink = PaletteReadout.ink(partial, col: c, row: r)
            if i < partial.count {
                XCTAssertEqual(ink, SIMD3(partial[i].0, partial[i].1, partial[i].2))
            } else {
                XCTAssertTrue(ink == Ink.ledGhost || ink == CellChecker.dark,
                              "entry \(i) is unsolved and must wear the checker")
            }
        }
    }

    func testCheckerPhaseFlipsWithTheHeartbeat() {
        let empty: [(UInt8, UInt8, UInt8)] = []
        for r in 0 ..< PaletteReadout.side {
            for c in 0 ..< PaletteReadout.side {
                XCTAssertNotEqual(PaletteReadout.ink(empty, col: c, row: r, phase: 0),
                                  PaletteReadout.ink(empty, col: c, row: r, phase: 1),
                                  "the heartbeat must invert the checker parity")
            }
        }
    }

    // MARK: - The bar: clamped, total, monotone

    func testBarIsClampedAndTotal() {
        let cols = FrameBarWidget.footprint.w
        let total = CameraConfig.totalFrames
        XCTAssertEqual(FrameBarReadout.lit(frame: 0), 0)
        XCTAssertEqual(FrameBarReadout.lit(frame: total), cols)
        XCTAssertEqual(FrameBarReadout.lit(frame: -5), 0, "negative frames read empty")
        XCTAssertEqual(FrameBarReadout.lit(frame: total * 3), cols,
                       "past the limit the bar is FULL, never past full")
        XCTAssertEqual(FrameBarReadout.lit(frame: 10, total: 0), 0,
                       "an empty capture must not divide by zero")
        XCTAssertEqual(FrameBarReadout.lit(frame: 10, total: -4), 0)
        XCTAssertEqual(FrameBarReadout.lit(frame: 10, total: total, cols: 0), 0)
        for f in -8 ... (total + 8) {
            let n = FrameBarReadout.lit(frame: f)
            XCTAssertGreaterThanOrEqual(n, 0)
            XCTAssertLessThanOrEqual(n, cols)
        }
    }

    func testBarIsMonotone() {
        var last = 0
        for f in -8 ... (CameraConfig.totalFrames + 8) {
            let n = FrameBarReadout.lit(frame: f)
            XCTAssertGreaterThanOrEqual(n, last, "the bar may not run backwards")
            last = n
        }
    }

    func testOneLitCellIsExactlyOneFrame() {
        // cols == totalFrames == 64: the bar shows the limit at 1:1.
        XCTAssertEqual(FrameBarWidget.footprint.w, CameraConfig.totalFrames)
        for f in 0 ... CameraConfig.totalFrames {
            XCTAssertEqual(FrameBarReadout.lit(frame: f), f,
                           "frame \(f) must light exactly \(f) cells")
        }
    }

    func testBarStillWorksAtAForeignWidth() {
        // The clamp must not depend on cols == total.
        XCTAssertEqual(FrameBarReadout.lit(frame: 32, total: 64, cols: 16), 8)
        XCTAssertEqual(FrameBarReadout.lit(frame: 64, total: 64, cols: 16), 16)
        XCTAssertEqual(FrameBarReadout.lit(frame: 1, total: 64, cols: 16), 0)
    }

    // MARK: - The timer: a capture clock

    func testTimerFormatting() {
        XCTAssertEqual(TimerReadout.text(frame: 0), "0.0s")
        XCTAssertEqual(TimerReadout.text(frame: CameraConfig.targetFPS), "1.0s")
        XCTAssertEqual(TimerReadout.text(frame: CameraConfig.targetFPS / 2), "0.5s")
        // 64 frames at 20 fps = the whole weave.
        XCTAssertEqual(TimerReadout.text(frame: CameraConfig.totalFrames), "3.2s")
        XCTAssertEqual(TimerReadout.text(frame: -12), "0.0s",
                       "the capture clock does not run before WEAVING")
    }

    func testTimerIsTheCaptureClock() {
        XCTAssertEqual(TimerReadout.seconds(frame: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(TimerReadout.seconds(frame: CameraConfig.totalFrames),
                       Double(CameraConfig.totalFrames) / Double(CameraConfig.targetFPS),
                       accuracy: 1e-12)
        var last = -1.0
        for f in -4 ... CameraConfig.totalFrames {
            let s = TimerReadout.seconds(frame: f)
            XCTAssertGreaterThanOrEqual(s, 0)
            XCTAssertGreaterThanOrEqual(s, last)
            last = s
        }
    }

    // MARK: - The law only the port can check: the ink FITS

    @MainActor
    func testTimerInkFitsItsFootprint() throws {
        let regionWidth = Lattice.gif(TimerWidget.footprint.w)
        let regionHeight = Lattice.gif(TimerWidget.footprint.h)
        // Every reading a 64-frame weave can produce ("0.0s"…"3.2s"),
        // plus one decade of headroom: the clock is not upper-clamped,
        // so a longer capture must still fit before it wraps the region.
        var readings = (0 ... CameraConfig.totalFrames).map { TimerReadout.text(frame: $0) }
        readings.append("99.9s")
        for text in readings {
            let mask = try XCTUnwrap(CellText.snap(text, rows: TimerWidget.register),
                                     "\(text) must rasterize")
            let inkWidth = mask.size.width * Lattice.pt(1)
            let inkHeight = mask.size.height * Lattice.pt(1)
            XCTAssertLessThanOrEqual(inkWidth, regionWidth,
                "\(text) at \(TimerWidget.register) rows must fit the 20-cell timer " +
                "(\(inkWidth)pt ink vs \(regionWidth)pt region)")
            XCTAssertLessThanOrEqual(inkHeight, regionHeight,
                "\(text) must fit the 7-cell height (\(inkHeight)pt vs \(regionHeight)pt)")
        }
    }

    @MainActor
    func testPreviewEmptyLabelFitsTheWidget() throws {
        let text = "\(PreviewWidget.footprint.w) × \(PreviewWidget.footprint.h)"
        let mask = try XCTUnwrap(CellText.snap(text, rows: TypeRows.label))
        XCTAssertLessThanOrEqual(mask.size.width * Lattice.pt(1),
                                 Lattice.gif(PreviewWidget.footprint.w))
    }

    // MARK: - Fixtures

    /// 256 distinct entries — a table whose every cell is identifiable.
    private static func syntheticTable() -> [(UInt8, UInt8, UInt8)] {
        (0 ..< 256).map { i in
            (UInt8(i), UInt8(255 - i), UInt8(i / 2))
        }
    }
}
