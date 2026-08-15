// Arrangement.swift
// Tesseract
//
// PORT of spec/ui/WidgetGrid.hs (WG1–WG12). The Haskell is
// authoritative; this is a port and may not improve on it.
//
// A scene stops being a layout and becomes a widget SET; WHERE each
// instrument sits is DATA the user owns — twelve (col, row) pairs,
// persisted and resettable. The disjointness proof that ran once at
// launch (GridLayout.selfCheck) now runs on every move, through the
// SAME checker (GridLayout.isLawful), and an illegal move is REFUSED
// rather than rendered.
//
// FOUR LAWS ARE STRUCTURAL HERE — no test can fail because no program
// can express the violation:
//
//   WG3  there is no mutating `move`. `moving(_:to:)` returns an
//        Optional and `nil` IS the refusal, so an unlawful Arrangement
//        never reaches a renderer.
//   WG4  Arrangement is a `struct` of `Placement` values: Equatable,
//        Sendable, Codable. Equality IS placement equality.
//   WG5  storage is a fixed-length array indexed by case ordinal, so
//        "a widget that is not placed" cannot be constructed. (The
//        spec's `move`-on-an-absent-widget case, axiom_WG3's fourth
//        clause, is therefore unrepresentable rather than tested.)
//   WG8  Placement holds two Ints and has no CGFloat initialiser. The
//        only points→cells door is Lattice.cells(_:), so a drag can
//        only ever SNAP; a widget cannot land on a half-atom.
//   WG10 disjointness (WG2, enforced on every move) removes z-order
//        entirely: the surface draws one ZStack with one .place() per
//        widget and no zIndex, because occlusion cannot arise.
//
// The remaining axioms are tests, one per law, in
// TesseractTests/ArrangementTests.swift.

import Foundation

// ════════════════════════════════════════════════════════════════
// § 1. THE VOCABULARY (WG6) AND THE FOOTPRINT TABLE (WG1)
// ════════════════════════════════════════════════════════════════

/// WG6 ★ — the CLOSED vocabulary. Twelve instruments, in the spec's
/// `vocabulary` order (spec/ui/WidgetGrid.hs §1). A thirteenth widget
/// is not a runtime error; it is not expressible.
///
/// Raw values are the GridRegion names, so LINT-CONTROL-FACE and
/// `CellMechanics.controlFaces` key off the same string the spec
/// enumerates.
enum Widget: String, CaseIterable, Sendable, Hashable, Codable {
    case preview64      // the fine read, 1 cell per GIF pixel
    case preview32      // ★ the mid read, live
    case preview16      // ★ the coarse read, live
    case palette        // ★ this frame's 256 entries, 16×16
    case timer          // elapsed, in the counter register
    case counter        // n / 64
    case framesBar      // ★ how close to the 64-frame limit
    case phaseStrip     // FACE / BAND / SOLID tile composition
    case energyRead     // ΔE² density, the phase-diagram readout
    case shutter
    case setButton
    case shelfButton

    /// Position in `allCases` — the index into `Arrangement.slots`, and
    /// the spec's `vocabulary` position. Memoized: the ordinal is read
    /// on every region build.
    var ordinal: Int { Widget.ordinals[self]! }

    private static let ordinals: [Widget: Int] = {
        var m = [Widget: Int](minimumCapacity: allCases.count)
        for (i, w) in allCases.enumerated() { m[w] = i }
        return m
    }()
}

/// WG1 — one row of the footprint table. Written in `GridRegion`'s
/// labeled shape on purpose: LINT-CONTROL-FACE reads one regex over
/// both declaration files, and four bare Ints in a row invite the
/// w/h transposition that a bounds check cannot catch.
struct WidgetSpec: Sendable, Equatable {
    let name: String
    let w: Int
    let h: Int
    let interactive: Bool

    init(_ name: String, w: Int, h: Int, interactive: Bool = false) {
        self.name = name
        self.w = w; self.h = h
        self.interactive = interactive
    }
}

extension Widget {

    /// WG1 — the footprint table, spec/ui/WidgetGrid.hs `footprint` +
    /// `interactive`, transcribed row for row. TOTAL by switch: a
    /// widget without a footprint is unrepresentable.
    ///
    /// NO NAKED CONSTANTS: every dimension that an existing law already
    /// owns is written as that law's constant, so re-basing the ladder
    /// or the button row re-sizes the instruments with no edit here.
    /// The dimensions that only the spec owns (the 20×7 readout
    /// register, the 2-cell strip, the 20-cell button width) are cited
    /// to the spec's own table — the spec IS the authority for them.
    var spec: WidgetSpec {
        switch self {
        // L5 / TL: the fine rung IS the GIF — 64 atoms, 1 per pixel.
        case .preview64:
            return WidgetSpec("preview64",
                              w: TesseractLattice.previewCells,
                              h: TesseractLattice.previewCells)
        // The ladder's own sides (FeedFormat Rung, TriScaleLadder).
        case .preview32:
            return WidgetSpec("preview32", w: Rung.mid.side, h: Rung.mid.side)
        case .preview16:
            return WidgetSpec("preview16", w: Rung.coarse.side, h: Rung.coarse.side)
        // 16² = 256 = the table: the palette is the bijection, drawn at
        // one atom per entry (WG12's `footprint Palette == footprint
        // Preview16` clause is this line).
        case .palette:
            return WidgetSpec("palette", w: Rung.coarse.side, h: Rung.coarse.side)
        // The readout register: 20 × 7 cells (spec §1 footprint table).
        case .timer:
            return WidgetSpec("timer",
                              w: Widget.readoutCols, h: Widget.readoutRows)
        case .counter:
            return WidgetSpec("counter",
                              w: Widget.readoutCols, h: Widget.readoutRows)
        case .energyRead:
            return WidgetSpec("energyRead",
                              w: Widget.readoutCols, h: Widget.readoutRows)
        // Strips span the GIF exactly, so a bar reads as "this many of
        // those pixels" (spec §1: 64 × 2).
        case .framesBar:
            return WidgetSpec("framesBar",
                              w: TesseractLattice.previewCells, h: Widget.stripRows)
        case .phaseStrip:
            return WidgetSpec("phaseStrip",
                              w: TesseractLattice.previewCells, h: Widget.stripRows)
        // The shutter footprint is the lattice's (88 pt, 2026-08-10).
        case .shutter:
            return WidgetSpec("shutter",
                              w: TesseractLattice.recordCells,
                              h: TesseractLattice.recordCells,
                              interactive: true)
        // Action rows: the standard 52 pt button height.
        case .setButton:
            return WidgetSpec("setButton",
                              w: Widget.buttonCols,
                              h: TesseractLattice.buttonRowCells,
                              interactive: true)
        case .shelfButton:
            return WidgetSpec("shelfButton",
                              w: Widget.buttonCols,
                              h: TesseractLattice.buttonRowCells,
                              interactive: true)
        }
    }

    /// spec/ui/WidgetGrid.hs §1: the readout register is 20 × 7 cells
    /// (80 × 28 pt) — wide enough for `TypeRows.counter` ink, short
    /// enough that three of them stack inside one preview height.
    static let readoutCols = 20
    static let readoutRows = 7
    /// spec §1: a strip is 2 cells tall — the thinnest instrument the
    /// atom admits above a hairline, and exempt from the touch floor
    /// because it reports and never takes touch (WG9).
    static let stripRows = 2
    /// spec §1: the action-button width. Height comes from the lattice.
    static let buttonCols = 20

    /// WG9's scope: which widgets accept touch.
    var interactive: Bool { spec.interactive }

    /// The whole table, for callers that want it by key. Derived from
    /// the switch — there is one declaration, not two.
    static let specs: [Widget: WidgetSpec] =
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.spec) })
}

// ════════════════════════════════════════════════════════════════
// § 2. PLACEMENT (WG8)
// ════════════════════════════════════════════════════════════════

/// WG8 ★ — THE ATOM IS INVIOLABLE. Integers only; there is no CGFloat
/// initialiser, so a widget cannot land on a half-atom and every
/// instrument stays on the same lattice as the GIF pixels it reports
/// on. `Lattice.cells(_:)` is the only points→cells door, which is
/// what makes dragging SNAPPING, always.
struct Placement: Equatable, Hashable, Sendable, Codable {
    let col: Int
    let row: Int

    init(col: Int, row: Int) {
        self.col = col
        self.row = row
    }
}

// ════════════════════════════════════════════════════════════════
// § 3. ARRANGEMENT (WG2 / WG3 / WG4 / WG5 / WG11)
// ════════════════════════════════════════════════════════════════

/// WG4 ★ — an arrangement is a VALUE: serialisable, restorable, and
/// equal exactly when the placements are equal.
struct Arrangement: Equatable, Sendable, Codable {

    /// Indexed by `Widget.ordinal`. Fixed length ⇒ WG5 totality is
    /// STRUCTURAL: "this widget is not placed" cannot be constructed,
    /// so `placement(of:)` returns a Placement and not an Optional.
    private var slots: [Placement]

    private init(slots: [Placement]) {
        self.slots = slots
    }

    // ── The canvas (spec §1) ──

    static let canvasCols = TesseractLattice.cols   // 100
    static let canvasRows = TesseractLattice.rows   // 218
    static let canvasArea = canvasCols * canvasRows // 21800

    // ── Reading (WG1) ──

    func placement(of w: Widget) -> Placement { slots[w.ordinal] }

    /// WG1 — the ONLY region producer. A widget's footprint plus its
    /// placement determines the exact cells it occupies; no view may
    /// mint a rectangle of its own (LINT-REGION-SOURCE).
    func region(for w: Widget) -> GridRegion {
        let s = w.spec
        let p = slots[w.ordinal]
        return GridRegion(s.name, col: p.col, row: p.row,
                          w: s.w, h: s.h, interactive: s.interactive)
    }

    /// Every region, in vocabulary order.
    var regions: [GridRegion] { Widget.allCases.map { region(for: $0) } }

    /// The regions of a widget SET — a scene, now that scenes are sets
    /// rather than layouts. A subset of a lawful arrangement is lawful
    /// (WG2 is a conjunction over pairs), so every scene inherits the
    /// whole arrangement's proof.
    func regions(for set: Set<Widget>) -> [GridRegion] {
        Widget.allCases.filter { set.contains($0) }.map { region(for: $0) }
    }

    // ── Lawfulness (WG2) ──

    /// WG2 — in bounds AND pairwise disjoint, decided by the SAME
    /// checker that proves the static scenes at launch. GridLayout's
    /// predicate additionally requires interactive regions to clear the
    /// touch floor; for this vocabulary that clause is constant-true
    /// (every interactive footprint's short axis is ≥ 11 cells — pinned
    /// by the WG9 test), so `isLawful` agrees with the spec's `lawful`
    /// on every arrangement, and the port is a port.
    var isLawful: Bool { GridLayout.isLawful(regions) }

    /// WG7 — the area the instruments claim, for the headroom law.
    var usedArea: Int {
        Widget.allCases.reduce(0) { $0 + $1.spec.w * $1.spec.h }
    }

    // ── Moving (WG3, WG11) ──

    /// WG3 ★ — TOTAL and lawfulness-preserving. `nil` IS the refusal:
    /// an illegal move is never rendered, and because there is no
    /// mutating `move`, an unlawful Arrangement never exists at all.
    ///
    /// WG11 — the returned copy rewrites ONE slot, so every other
    /// widget's region is untouched by construction.
    func moving(_ w: Widget, to p: Placement) -> Arrangement? {
        var a = self
        a.slots[w.ordinal] = p
        return a.isLawful ? a : nil
    }

    // ── The default (WG5) ──

    /// spec/ui/WidgetGrid.hs §3 `defaultArrangement`, transcribed in
    /// vocabulary order with no reordering: everything Daniel named
    /// (palette, timer, frames bar) plus the two coarse reads and the
    /// two phase instruments — all on screen at once, all movable.
    /// Verified lawful, `usedArea = 7312` of 21800 (WG7).
    static let `default` = Arrangement(slots: [
        Placement(col: 18, row:  16),   // preview64
        Placement(col: 18, row:  84),   // preview32
        Placement(col: 52, row:  84),   // preview16
        Placement(col: 70, row:  84),   // palette
        Placement(col: 52, row: 102),   // timer
        Placement(col: 74, row: 102),   // counter
        Placement(col: 18, row: 120),   // framesBar
        Placement(col: 18, row: 124),   // phaseStrip
        Placement(col: 18, row: 128),   // energyRead
        Placement(col: 39, row: 150),   // shutter
        Placement(col: 10, row: 155),   // setButton
        Placement(col: 70, row: 155),   // shelfButton
    ])

    // ── Serialisation (WG4) ──

    /// Twelve (col, row) pairs flattened in vocabulary order — 24 ints,
    /// small enough to persist, share, and reset.
    var serialised: [Int] { slots.flatMap { [$0.col, $0.row] } }

    /// The inverse. `nil` on ANY shape error — a half-decoded surface is
    /// worse than the default one (see ArrangementStore).
    ///
    /// Shape only: this initialiser does not judge lawfulness, because
    /// `Arrangement` is also the natural way to express the spec's
    /// unlawful fixtures. Callers that restore from storage MUST check
    /// `isLawful` — `ArrangementStore.load` does.
    init?(serialised: [Int]) {
        guard serialised.count == 2 * Widget.allCases.count else { return nil }
        var s = [Placement]()
        s.reserveCapacity(Widget.allCases.count)
        for i in stride(from: 0, to: serialised.count, by: 2) {
            s.append(Placement(col: serialised[i], row: serialised[i + 1]))
        }
        self.slots = s
    }
}
