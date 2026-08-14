// ArrangementTests.swift
// Tesseract
//
// Swift mirrors of spec/ui/WidgetGrid.hs (WG1–WG12) — the Haskell is
// authoritative; these tests prove the port did not drift from it.
// Pure logic, no camera: runs on the simulator.
//
// Five laws are STRUCTURAL and have no test, because no program can
// express the violation (documented at the head of Arrangement.swift):
//
//   WG3  (4th clause) the spec's `move`-on-an-ABSENT-widget case:
//        `Widget` is total over `Arrangement.slots`, so "the widget is
//        not in the arrangement" cannot be constructed. The other three
//        clauses ARE tested below.
//   WG4  `struct Arrangement: Equatable, Sendable, Codable` over
//        `Placement` values — equality IS placement equality by
//        synthesis. The round trip is tested; the value-ness is not
//        testable, it is the type.
//   WG5  (totality) fixed-length storage indexed by case ordinal.
//   WG8  `Placement` has two `Int` members and no CGFloat initialiser,
//        so a half-atom placement is unrepresentable. The lattice
//        consequences ARE tested.
//   WG10 disjointness is enforced on every move and there is no
//        `zIndex` in the surface, so occlusion has no representation.
//        The occupancy consequence IS tested.

import XCTest
@testable import Tesseract

final class ArrangementTests: XCTestCase {

    // MARK: - Fixtures

    /// The spec's own `defaultArrangement` table (spec §3), independent
    /// of the Swift transcription so the test can disagree with it.
    private let specDefault: [(Widget, Int, Int)] = [
        (.preview64,   18,  16),
        (.preview32,   18,  84),
        (.preview16,   52,  84),
        (.palette,     70,  84),
        (.timer,       52, 102),
        (.counter,     74, 102),
        (.framesBar,   18, 120),
        (.phaseStrip,  18, 124),
        (.energyRead,  18, 128),
        (.shutter,     39, 150),
        (.setButton,   10, 155),
        (.shelfButton, 70, 155),
    ]

    /// The spec's `footprint` / `interactive` tables (spec §1), written
    /// as the literals the Haskell writes. Arrangement.swift derives the
    /// same numbers from lattice + ladder constants; this is the pin
    /// that says the derivation lands on the spec.
    private let specFootprints: [(Widget, Int, Int, Bool)] = [
        (.preview64,   64, 64, false),
        (.preview32,   32, 32, false),
        (.preview16,   16, 16, false),
        (.palette,     16, 16, false),
        (.timer,       20,  7, false),
        (.counter,     20,  7, false),
        (.framesBar,   64,  2, false),
        (.phaseStrip,  64,  2, false),
        (.energyRead,  20,  7, false),
        (.shutter,     22, 22, true),
        (.setButton,   20, 13, true),
        (.shelfButton, 20, 13, true),
    ]

    /// An arrangement with some placements overridden — the only way to
    /// build the spec's UNLAWFUL fixtures, since `moving` refuses them
    /// by design (WG3). Shape-valid, lawfulness unjudged.
    private func arrangement(_ overrides: [Widget: Placement]) -> Arrangement {
        var s = Arrangement.default.serialised
        for (w, p) in overrides {
            s[2 * w.ordinal] = p.col
            s[2 * w.ordinal + 1] = p.row
        }
        return Arrangement(serialised: s)!
    }

    /// The cells a region covers, in the spec's `region` order (dx
    /// outer, dy inner — so element 0 is the placement).
    private func cells(_ r: GridRegion) -> [Placement] {
        (0..<r.w).flatMap { dx in
            (0..<r.h).map { dy in Placement(col: r.col + dx, row: r.row + dy) }
        }
    }

    // MARK: - WG1: footprints determine regions

    func testWG1_footprintsDetermineRegions() {
        let a = Arrangement.default
        for w in Widget.allCases {
            let s = w.spec
            let p = a.placement(of: w)
            let r = a.region(for: w)

            XCTAssertGreaterThan(s.w, 0, "\(w): width must be positive")
            XCTAssertGreaterThan(s.h, 0, "\(w): height must be positive")
            XCTAssertEqual(r.name, w.rawValue,
                           "\(w): the region name IS the vocabulary name")
            XCTAssertEqual(r.col, p.col, "\(w): region col is the placement")
            XCTAssertEqual(r.row, p.row, "\(w): region row is the placement")
            XCTAssertEqual(r.w, s.w)
            XCTAssertEqual(r.h, s.h)
            XCTAssertEqual(r.interactive, s.interactive)

            let cs = cells(r)
            XCTAssertEqual(cs.count, s.w * s.h, "\(w): area is width × height")
            XCTAssertEqual(Set(cs).count, s.w * s.h, "\(w): every cell distinct")
            XCTAssertEqual(cs[0], p, "\(w): the top-left cell IS the placement")
        }
    }

    func testWG1_footprintTableMatchesTheSpec() {
        XCTAssertEqual(specFootprints.count, Widget.allCases.count)
        for (w, width, height, touch) in specFootprints {
            XCTAssertEqual(w.spec.w, width, "\(w): spec width")
            XCTAssertEqual(w.spec.h, height, "\(w): spec height")
            XCTAssertEqual(w.spec.interactive, touch, "\(w): spec interactivity")
            XCTAssertEqual(w.spec.name, w.rawValue)
            XCTAssertEqual(Widget.specs[w], w.spec, "the table IS the switch")
        }
        // The pinned derivations (NO NAKED CONSTANTS): if the lattice or
        // the ladder moves, these are the lines that must move with it.
        XCTAssertEqual(Widget.preview64.spec.w, TesseractLattice.previewCells)
        XCTAssertEqual(Widget.preview32.spec.w, Rung.mid.side)
        XCTAssertEqual(Widget.preview16.spec.w, Rung.coarse.side)
        XCTAssertEqual(Widget.palette.spec.w, Rung.coarse.side)
        XCTAssertEqual(Widget.framesBar.spec.w, TesseractLattice.previewCells)
        XCTAssertEqual(Widget.shutter.spec.w, TesseractLattice.recordCells)
        XCTAssertEqual(Widget.setButton.spec.h, TesseractLattice.buttonRowCells)
        // 16² = 256 = the table — the palette widget IS the bijection.
        XCTAssertEqual(Widget.palette.spec.w * Widget.palette.spec.h, 256)
    }

    func testWG1_defaultMatchesTheSpecTableVerbatim() {
        XCTAssertEqual(specDefault.count, Widget.allCases.count)
        for (w, col, row) in specDefault {
            XCTAssertEqual(Arrangement.default.placement(of: w),
                           Placement(col: col, row: row),
                           "\(w): spec §3 defaultArrangement")
        }
    }

    // MARK: - WG2: lawful = in bounds AND pairwise disjoint

    func testWG2_lawfulIsBoundsAndDisjoint() {
        XCTAssertTrue(Arrangement.default.isLawful, "the default is lawful")
        for r in Arrangement.default.regions {
            XCTAssertTrue(GridLayout.inBounds(r), "\(r.name) must be in bounds")
        }

        // spec fixture: offCanvas = Preview64 @ (canvasCols - 4, 0).
        let offCanvas = arrangement([
            .preview64: Placement(col: Arrangement.canvasCols - 4, row: 0)
        ])
        XCTAssertFalse(GridLayout.isLawful(offCanvas.regions(for: [.preview64])),
                       "a widget hanging off the canvas is unlawful on its own")
        XCTAssertFalse(offCanvas.isLawful)

        // spec fixture: collided = Preview64 @ (0,0) + Palette @ (10,10).
        let collided = arrangement([
            .preview64: Placement(col: 0, row: 0),
            .palette: Placement(col: 10, row: 10),
        ])
        XCTAssertFalse(
            GridLayout.isLawful(collided.regions(for: [.preview64, .palette])),
            "two overlapping widgets are unlawful even though both fit")
        XCTAssertFalse(collided.isLawful)
    }

    func testWG2_theCheckerIsTheOneUsedAtLaunch() {
        // WG2 must not acquire a second implementation: the runtime move
        // check IS the launch proof. Both go through GridLayout.isLawful,
        // and GridLayout.check preconditions on the same three clauses.
        XCTAssertTrue(GridLayout.isLawful(Arrangement.default.regions))
        for (_, scene) in GridLayout.allScenes {
            XCTAssertTrue(GridLayout.isLawful(scene),
                          "every static scene passes the same predicate")
        }
    }

    // MARK: - WG3: moves are total; an illegal move is REFUSED

    func testWG3_movesAreTotal() {
        let d = Arrangement.default

        // legal
        let legal = d.moving(.palette, to: Placement(col: 60, row: 130))
        XCTAssertNotNil(legal)
        XCTAssertTrue(legal!.isLawful, "a legal move yields a lawful value")
        XCTAssertEqual(legal!.placement(of: .palette),
                       Placement(col: 60, row: 130))

        // onto another widget → REFUSED (preview64 sits at 18,16)
        XCTAssertNil(d.moving(.palette, to: Placement(col: 18, row: 16)),
                     "moving onto another widget is refused, not rendered")

        // off the edge → REFUSED (60 + 64 = 124 > 100 cols)
        XCTAssertNil(d.moving(.preview64, to: Placement(col: 60, row: 16)),
                     "moving off the canvas is refused")

        // negative placements are off the canvas too (WG8's c ≥ 0).
        XCTAssertNil(d.moving(.timer, to: Placement(col: -1, row: 102)))
        XCTAssertNil(d.moving(.timer, to: Placement(col: 52, row: -1)))

        // A refusal leaves the receiver untouched — `moving` is not a
        // mutation, so there is nothing to roll back.
        XCTAssertEqual(d, Arrangement.default)
    }

    func testWG3_everyRefusedMoveWouldHaveBeenUnlawful() {
        // The refusal is not a heuristic: nil ⟺ the candidate is unlawful.
        let d = Arrangement.default
        for w in Widget.allCases {
            for col in stride(from: 0, to: Arrangement.canvasCols, by: 7) {
                for row in stride(from: 0, to: Arrangement.canvasRows, by: 13) {
                    let p = Placement(col: col, row: row)
                    let candidate = arrangement([w: p])
                    XCTAssertEqual(d.moving(w, to: p) != nil, candidate.isLawful,
                                   "\(w) → (\(col),\(row)): refusal must track lawfulness")
                }
            }
        }
    }

    // MARK: - WG4: an arrangement is a VALUE

    func testWG4_serialisationRoundTrips() {
        let d = Arrangement.default
        XCTAssertEqual(d.serialised.count, 2 * Widget.allCases.count,
                       "twelve (col, row) pairs — 24 ints")
        XCTAssertEqual(Arrangement(serialised: d.serialised), d,
                       "round trip is the identity")

        let moved = d.moving(.palette, to: Placement(col: 60, row: 130))!
        XCTAssertNotEqual(moved.serialised, d.serialised)
        XCTAssertNotEqual(moved, d, "equal iff the placements are equal")
        XCTAssertTrue(moved.isLawful)
        XCTAssertEqual(Arrangement(serialised: moved.serialised), moved)

        // Shape errors are refused.
        XCTAssertNil(Arrangement(serialised: []))
        XCTAssertNil(Arrangement(serialised: Array(d.serialised.dropLast())))
        XCTAssertNil(Arrangement(serialised: d.serialised + [0]))
    }

    func testWG4_codableRoundTrips() throws {
        let moved = Arrangement.default.moving(.timer, to: Placement(col: 2, row: 2))!
        let data = try JSONEncoder().encode(moved)
        XCTAssertEqual(try JSONDecoder().decode(Arrangement.self, from: data), moved)
    }

    // MARK: - WG5: the default exists, is lawful, places EVERY widget

    func testWG5_defaultIsLawful() {
        XCTAssertTrue(Arrangement.default.isLawful)
        // Totality is STRUCTURAL (fixed-length storage), so the strongest
        // statement a test can make is that every widget reads back a
        // placement and the serialisation covers the whole vocabulary.
        var seen = Set<Widget>()
        for w in Widget.allCases {
            _ = Arrangement.default.placement(of: w)
            seen.insert(w)
        }
        XCTAssertEqual(seen.count, Widget.allCases.count)
        XCTAssertEqual(Arrangement.default.regions.count, Widget.allCases.count)
    }

    // MARK: - WG6: the vocabulary is CLOSED and enumerable

    func testWG6_vocabularyIsClosed() {
        XCTAssertEqual(Widget.allCases.count, 12,
                       "twelve instruments — the dials are NOT among them "
                       + "(they ship on their own cover; adding one here "
                       + "falsifies axiom_WG6 in the authoritative spec)")
        XCTAssertEqual(Set(Widget.allCases.map(\.rawValue)).count, 12,
                       "raw values distinct")
        XCTAssertEqual(Widget.allCases.map(\.rawValue),
                       ["preview64", "preview32", "preview16", "palette",
                        "timer", "counter", "framesBar", "phaseStrip",
                        "energyRead", "shutter", "setButton", "shelfButton"],
                       "order matches spec/ui/WidgetGrid.hs `vocabulary`")
        for (i, w) in Widget.allCases.enumerated() {
            XCTAssertEqual(w.ordinal, i, "\(w): ordinal is the storage index")
        }
    }

    // MARK: - WG7: headroom

    func testWG7_headroom() {
        let used = Arrangement.default.usedArea
        XCTAssertEqual(Arrangement.canvasArea, 21800, "100 × 218 cells")
        XCTAssertEqual(used, 7312, "the measured default occupancy")
        XCTAssertLessThan(used, Arrangement.canvasArea)
        XCTAssertLessThan(2 * used, Arrangement.canvasArea,
                          "the default uses under HALF the canvas. This is "
                          + "the gate that fails the day a dial joins the "
                          + "surface (all four → 13656, 2 × 13656 > 21800) "
                          + "— leave it exactly as the spec states it.")
    }

    // MARK: - WG8: placements are integer cells

    func testWG8_atomIsInviolable() {
        for w in Widget.allCases {
            let p = Arrangement.default.placement(of: w)
            XCTAssertGreaterThanOrEqual(p.col, 0, "\(w): col ≥ 0")
            XCTAssertGreaterThanOrEqual(p.row, 0, "\(w): row ≥ 0")
            for c in cells(Arrangement.default.region(for: w)) {
                XCTAssertTrue(c.col >= 0 && c.col < Arrangement.canvasCols
                              && c.row >= 0 && c.row < Arrangement.canvasRows,
                              "\(w): cell (\(c.col),\(c.row)) off the lattice")
            }
        }
        // The canvas IS the app's lattice — no second grid.
        XCTAssertEqual(Arrangement.canvasCols, TesseractLattice.cols)
        XCTAssertEqual(Arrangement.canvasRows, TesseractLattice.rows)
    }

    // MARK: - WG9: interactive widgets meet the touch floor

    func testWG9_touchFloor() {
        let touchy = Widget.allCases.filter(\.interactive)
        XCTAssertEqual(touchy.count, 3, "shutter, setButton, shelfButton")
        XCTAssertEqual(Set(touchy), [.shutter, .setButton, .shelfButton])
        XCTAssertTrue(Widget.allCases.contains { !$0.interactive },
                      "reporting instruments exist and are exempt")
        for w in touchy {
            XCTAssertGreaterThanOrEqual(min(w.spec.w, w.spec.h),
                                        TesseractLattice.touchFloorCells,
                                        "\(w): the SMALLER axis must clear 44 pt")
        }
        // Consequence: GridLayout.isLawful's touch-floor clause is
        // constant-true over this vocabulary, so the shared checker
        // agrees with the spec's `lawful` on EVERY arrangement — the
        // port neither weakens nor strengthens WG2.
        for w in Widget.allCases {
            let r = Arrangement.default.region(for: w)
            XCTAssertTrue(GridLayout.meetsTouchFloor(r), "\(w)")
        }
    }

    // MARK: - WG10: disjointness ⇒ no z-order

    func testWG10_noCellHasTwoOwners() {
        var owner = [Placement: Widget]()
        for w in Widget.allCases {
            for c in cells(Arrangement.default.region(for: w)) {
                XCTAssertNil(owner[c],
                             "cell (\(c.col),\(c.row)) claimed by both "
                             + "\(owner[c]?.rawValue ?? "?") and \(w.rawValue)")
                owner[c] = w
            }
        }
        XCTAssertEqual(owner.count, Arrangement.default.usedArea,
                       "occupied cells == summed footprints ⇒ zero overlap")
    }

    // MARK: - WG11: a move is local

    func testWG11_moveIsLocal() {
        let d = Arrangement.default
        let after = d.moving(.palette, to: Placement(col: 60, row: 130))!
        XCTAssertNotEqual(after.placement(of: .palette), d.placement(of: .palette))
        for w in Widget.allCases where w != .palette {
            XCTAssertEqual(after.placement(of: w), d.placement(of: w),
                           "\(w) must be untouched by moving the palette")
            XCTAssertEqual(after.region(for: w), d.region(for: w))
        }
    }

    // MARK: - WG12: the three rungs coexist

    func testWG12_threeRungsAtOnce() {
        XCTAssertEqual([Widget.preview64.spec.w, Widget.preview64.spec.h], [64, 64])
        XCTAssertEqual([Widget.preview32.spec.w, Widget.preview32.spec.h], [32, 32])
        XCTAssertEqual([Widget.preview16.spec.w, Widget.preview16.spec.h], [16, 16])
        XCTAssertEqual([Widget.palette.spec.w, Widget.palette.spec.h],
                       [Widget.preview16.spec.w, Widget.preview16.spec.h],
                       "16×16 = 256 = the bijection")
        let rungs: Set<Widget> = [.preview64, .preview32, .preview16, .palette]
        XCTAssertTrue(GridLayout.isLawful(Arrangement.default.regions(for: rungs)),
                      "the parallel read is visible, not merely internal")
    }

    /// The law every scene set relies on: a scene is now a SUBSET of the
    /// one global arrangement, and a subset of a lawful arrangement is
    /// lawful (WG2 is a conjunction over pairs). Proved exhaustively over
    /// all 2¹² subsets, so no future scene set needs its own proof.
    func testEverySubsetOfALawfulArrangementIsLawful() {
        let all = Widget.allCases
        for mask in 0..<(1 << all.count) {
            var set = Set<Widget>()
            for (i, w) in all.enumerated() where mask & (1 << i) != 0 { set.insert(w) }
            XCTAssertTrue(GridLayout.isLawful(Arrangement.default.regions(for: set)),
                          "subset \(mask) must be lawful")
        }
    }

    func testRegionsForSetKeepsVocabularyOrder() {
        let set: Set<Widget> = [.shutter, .palette, .preview64]
        XCTAssertEqual(Arrangement.default.regions(for: set).map(\.name),
                       ["preview64", "palette", "shutter"])
    }

    // MARK: - WG4 (persistence): the fallback is the whole design

    private func scratch() -> UserDefaults {
        let d = UserDefaults(suiteName: "tesseract.arrangement.tests")!
        d.removePersistentDomain(forName: "tesseract.arrangement.tests")
        return d
    }

    func testPersistenceRoundTrips() {
        let d = scratch()
        let moved = Arrangement.default.moving(.palette, to: Placement(col: 60, row: 130))!
        ArrangementStore.save(moved, to: d)
        XCTAssertEqual(ArrangementStore.load(d), moved)
        XCTAssertEqual(d.array(forKey: ArrangementStore.key)?.count,
                       ArrangementStore.storedCount, "1 schema + 24 ints = 25")
    }

    func testPersistenceFallsBackOnEveryCorruption() {
        let d = scratch()
        let good = [ArrangementStore.schema] + Arrangement.default.serialised

        // 1. missing
        XCTAssertEqual(ArrangementStore.load(d), .default)

        // 2. not [Int]
        d.set(["nope", "nope"], forKey: ArrangementStore.key)
        XCTAssertEqual(ArrangementStore.load(d), .default)

        // 3. wrong length
        d.set(Array(good.dropLast()), forKey: ArrangementStore.key)
        XCTAssertEqual(ArrangementStore.load(d), .default)

        // 4. wrong schema
        d.set([ArrangementStore.schema + 1] + Arrangement.default.serialised,
              forKey: ArrangementStore.key)
        XCTAssertEqual(ArrangementStore.load(d), .default)

        // 5. shape error from the payload. With the length gate above,
        //    dropFirst() always has 24 elements, so Arrangement(serialised:)
        //    cannot fail here — the guard is belt-and-braces against a
        //    future storedCount change. Proved directly instead:
        XCTAssertNil(Arrangement(serialised: Array(good.dropFirst().dropFirst())))

        // 6. well-formed but UNLAWFUL (preview64 hanging off the canvas)
        let bad = arrangement([.preview64: Placement(col: 96, row: 0)])
        XCTAssertFalse(bad.isLawful)
        d.set([ArrangementStore.schema] + bad.serialised, forKey: ArrangementStore.key)
        XCTAssertEqual(ArrangementStore.load(d), .default,
                       "an unlawful persisted layout must never reach a renderer")

        // Reset makes "reset" and "never arranged" the same state.
        ArrangementStore.save(
            Arrangement.default.moving(.timer, to: Placement(col: 2, row: 2))!, to: d)
        XCTAssertNotEqual(ArrangementStore.load(d), .default)
        ArrangementStore.reset(d)
        XCTAssertNil(d.array(forKey: ArrangementStore.key))
        XCTAssertEqual(ArrangementStore.load(d), .default)
    }
}
