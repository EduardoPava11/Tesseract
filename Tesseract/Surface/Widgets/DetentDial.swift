// DetentDial.swift
// Tesseract
//
// PORT of spec/ui/DetentDial.hs (DD1–DD10). The Haskell is
// authoritative; this is a port and may not improve on it.
//
// THE DIAL IS A CIRCLE WITH DETENTS (Daniel's ruling, 2026-08-13:
// "a UI with widgets that allow for incremental movements. think
// circles and degrees of freedom"). The ruling answers a question it
// was not asked: "full 64³ every tick" is only affordable because a
// TICK IS A DETENT CROSSING, not a touch sample. At 120 Hz a
// continuous knob would demand 120 cubes per second of drag; a
// detented one demands at most one per stop (DD3, DD6).
//
// The second half of the ruling is the ladder. κ COMPOSES (Octave
// OV13), so the coarse read is a genuine PREFIX of the fine one: the
// drag renders 16³ while the finger moves, 32³ as each detent is
// crossed, 64³ on release — and the user is never shown a value the
// final render contradicts (DD5).
//
// ★ NO NAKED COUNTS. Not one detent count is written down here.
// Every count is a MEASUREMENT of the law that dial drives
// (DyadPalette.ladder, Rung.allCases, RoleAlloc), so a change to the
// law moves the dial automatically — and DD10 is the alarm bell that
// rings if a source law drifts out from under a dial.
//
// Drawing is the app's own cell idiom (UI/Cells): one CellSprite at
// the gifPx atom, opaque ink only, no vectors and no AA. The view
// sizes itself to `law.sideCells` atoms and is PLACED by its caller
// through View.place(_:) with a machine-checked GridRegion — this
// file mints no rectangles of its own (scripts/lint-grid.sh).

import Foundation
import SwiftUI
import simd

// ════════════════════════════════════════════════════════════════
// § 0. The source law the RoleSplit dial drives
// ════════════════════════════════════════════════════════════════

/// PORT of spec/quantization/RoleAllocation.hs `shippingAlloc` — the
/// figure:ground depth split, in bits. DERIVED, never written: the
/// (7,4) pair is a CONSEQUENCE of the tree and the spacetime atom,
/// not a constant someone typed.
enum RoleAlloc {
    /// d_F = treeDepth: the figure half is 2^7 = 128 leaves — exactly
    /// `DyadPalette.primaryCount` (DY/PT7). Measuring the palette is
    /// what makes this derived rather than declared.
    static let figureBits = Int(log2(Double(DyadPalette.primaryCount)))

    /// The spacetime block's axes (x, y, t). Not written as 3: one κ
    /// step pools 2×2×2 = 8 children (TriScaleLadder TL1, RateLadder
    /// RL1), so the axis count IS log₂ of the rung's cell ratio.
    static let cubeAxes = Int(log2(Double(Rung.fine.cells / Rung.mid.cells)))

    /// d_B: the chaos targets quantize at the NODE stratum — one node
    /// per leaf OCTET (PairTree P2, the "32-level"), i.e. `cubeAxes`
    /// generations above the leaves.
    static let groundBits = figureBits - cubeAxes

    /// Total bits the RoleSplit dial divides. The dial has one stop
    /// per lawful split INCLUDING both ends, hence the +1 in DD1.
    static let totalBits = figureBits + groundBits
}

// ════════════════════════════════════════════════════════════════
// § 1. The dials (DD1, DD7, DD8)
// ════════════════════════════════════════════════════════════════

/// The four laws a dial can drive. A fifth dial is not a runtime
/// error — it is unrepresentable (the spec's `Law`, case for case).
enum DialLaw: String, CaseIterable, Sendable, Codable {
    /// Which attractor gets which basin.
    case allocation
    /// Which rung the user is looking at.
    case rungPick
    /// How the bits divide figure from ground.
    case roleSplit
    /// OKLab hue × chroma — the 2-DOF one.
    case colourDisc

    /// (DD1) DERIVED, NEVER WRITTEN. One entry per degree of freedom.
    /// Each element is a measurement of its source law's own data.
    var detents: [Int] {
        switch self {
        case .allocation:
            // The eight BALANCED pairs (AttractorRAG's pairLadder IS
            // DyadPalette.ladder — the binomial half, PT6).
            return [DyadPalette.ladder.count]
        case .rungPick:
            // The rungs, read in parallel (Octave OV1 — three cases).
            return [Rung.allCases.count]
        case .roleSplit:
            // One stop per lawful figure:ground split, both ends
            // included: 11 bits ⇒ 12 stops.
            return [RoleAlloc.totalBits + 1]
        case .colourDisc:
            // Hue from the FLOOR rung (16, because 16 × 16 = 256 is
            // the bijection); chroma from the balanced pairs (8).
            return [DetentDial.floorRungSide, DyadPalette.ladder.count]
        }
    }

    /// (DD7) Degrees of freedom is just the arity of that list.
    var dof: Int { detents.count }

    /// (DD8) Total distinguishable positions — for the colour disc
    /// this is 128, half the palette, the σ mirror completing it.
    var positions: Int { detents.reduce(1, *) }

    /// The finest axis on this dial — the one the radius law must pay
    /// for. Non-empty by construction (every case returns a literal
    /// list of at least one measurement); the `?? 1` is unreachable.
    var maxDetents: Int { detents.max() ?? 1 }

    /// (DD4) The radius this dial needs so every detent arc clears the
    /// touch floor: k arcs of ≥ touchFloorCells need circumference
    /// ≥ k·floor, so r ≥ k·floor/τ. `tauLower` under-states τ, which
    /// OVER-states the radius — the law can never under-size a dial.
    var minRadiusCells: Double {
        Double(maxDetents * TesseractLattice.touchFloorCells) / DetentDial.tauLower
    }

    /// The dial's square footprint in atoms: the diameter its own law
    /// demands, rounded UP to a whole atom on each side (so the disc
    /// is symmetric about its centre, CellButton's convention), and
    /// floored at the touch floor — a whole dial is itself a control.
    var sideCells: Int {
        max(TesseractLattice.touchFloorCells, 2 * Int(minRadiusCells.rounded(.up)))
    }

    /// The dial's square word, in the EditMachine's voice (EM6).
    var word: String {
        switch self {
        case .allocation: return "ALLOC"
        case .rungPick:   return "RUNG"
        case .roleSplit:  return "ROLE"
        case .colourDisc: return "COLOUR"
        }
    }
}

// ════════════════════════════════════════════════════════════════
// § 2. The circle (DD2, DD9)
// ════════════════════════════════════════════════════════════════

enum DetentDial {

    /// A strict RATIONAL LOWER BOUND on τ = 2π (6.283185…), written as
    /// the spec writes it. Used ONLY where a lower bound is the
    /// conservative answer (the radius law, the arc-gap raster). A
    /// mathematical bound, not a fitted constant.
    static let tauLower = 157.0 / 25.0

    /// Degrees in a full turn — the circle's own arithmetic.
    static let fullTurnDegrees = 360.0

    /// The BIJECTION FLOOR rung side (16): 16 × 16 = 256 entries. Read
    /// off the ladder, never written (Octave OV2).
    static let floorRungSide = Rung.allCases.map(\.side).min() ?? 0

    /// The rungs, coarse → fine. The interaction ladder (DD5) and the
    /// rungPick dial both index THIS order, so "detent 0" and "the
    /// cheapest render" name the same rung by construction.
    static let rungLadder: [Rung] = Rung.allCases.sorted { $0.side < $1.side }

    /// Hardware fact, not a tuning knob: ProMotion delivers touch
    /// samples at 120 Hz, so a one-second sweep of a CONTINUOUS
    /// control would produce this many candidate recomputes. Declared
    /// by the spec; used only in the DD6 cost proof.
    static let touchSamplesPerSweep = 120

    /// One atom's half-width, in cells — the raster's own unit, used
    /// to open a hairline gap between neighbouring detent arcs.
    static let halfAtomCells = Double(TesseractLattice.subPt) / Double(TesseractLattice.gifPx)

    /// Which detent an angle lands in. Equal arcs, floor-then-mod, so
    /// the map is TOTAL over ℝ: winding past 360° wraps (DD9's ℤ_k),
    /// and a negative angle is the same detent as its positive turn.
    static func detentAt(k: Int, angle: Double) -> Int {
        precondition(k > 0, "DD1: a dial with no detents is not a dial")
        let i = Int(floor(angle * Double(k) / fullTurnDegrees))
        let m = i % k
        return m < 0 ? m + k : m
    }

    /// The angle a detent snaps TO. Exact in binary for every shipping
    /// k (360/3, /8, /12, /16 = 120, 45, 30, 22.5).
    static func snapAngle(k: Int, index: Int) -> Double {
        Double(index) * fullTurnDegrees / Double(k)
    }

    /// The RADIAL axis of a 2-DOF dial (DD7: the colour disc alone).
    /// The same equal-division law as `detentAt`, applied to the
    /// normalised radius instead of the angle — the disc is the
    /// palette in POLAR form (DD8), so both coordinates divide evenly.
    static func ringAt(k: Int, radiusFraction: Double) -> Int {
        precondition(k > 0, "DD1: a dial with no detents is not a dial")
        let f = min(max(radiusFraction, 0), 1)
        return min(k - 1, Int(floor(f * Double(k))))
    }

    /// (DD3) A tick is a CROSSING, not a sample: the number of index
    /// changes along a path of angles. The spec's `ticks`, verbatim.
    static func ticks(k: Int, path: [Double]) -> Int {
        let idx = path.map { detentAt(k: k, angle: $0) }
        return zip(idx, idx.dropFirst()).filter { $0 != $1 }.count
    }

    // ── the touch → circle door ──────────────────────────────────
    //
    // Clockwise from TOP, matching CellGeom.turn exactly, so the ink
    // and the finger agree by construction rather than by adjustment.

    /// The angle in degrees of a touch point within a `sideCells`
    /// square dial, clockwise from top.
    static func angle(at p: CGPoint, sideCells: Int) -> Double {
        let c = Lattice.gif(sideCells) / 2
        let dx = Double(p.x - c), dy = Double(p.y - c)
        var a = atan2(dx, -dy)
        if a < 0 { a += 2 * Double.pi }
        return a / (2 * Double.pi) * fullTurnDegrees
    }

    /// The normalised radius of a touch point: 0 at the centre, 1 at
    /// the dial's rim.
    static func radiusFraction(at p: CGPoint, sideCells: Int) -> Double {
        let c = Lattice.gif(sideCells) / 2
        guard c > 0 else { return 0 }
        let dx = Double(p.x - c), dy = Double(p.y - c)
        return (dx * dx + dy * dy).squareRoot() / Double(c)
    }

    // ── the cost proof (DD6) ─────────────────────────────────────

    /// Work is voxels.
    static func cost(side: Int) -> Int { side * side * side }

    /// One full sweep, detented: the cheap rung on every touch sample,
    /// the middle rung on every detent crossed, the full cube once on
    /// release.
    static func costDetented(_ law: DialLaw) -> Int {
        touchSamplesPerSweep * cost(side: DialGesture.dragging.rung.side)
        + law.maxDetents * cost(side: DialGesture.crossed.rung.side)
        + cost(side: DialGesture.released.rung.side)
    }

    /// The same sweep with no detents and no ladder: the full cube on
    /// every touch sample.
    static var costContinuous: Int {
        touchSamplesPerSweep * cost(side: DialGesture.released.rung.side)
    }

    /// DEBUG law check, run beside the lattice selfChecks. DD4 and DD9
    /// are the two that can be broken from OUTSIDE this file (a source
    /// law drifting), so they are asserted at launch, not just in the
    /// test bundle.
    static func selfCheck() {
        for law in DialLaw.allCases {
            assert(law.detents.allSatisfy { $0 > 0 }, "DD1 \(law.rawValue): counts positive")
            assert(law.minRadiusCells > 0, "DD4 \(law.rawValue): radius positive")
            assert(2 * law.minRadiusCells <= Double(TesseractLattice.cols),
                   "DD4 \(law.rawValue): dial must fit the canvas width")
            assert(law.sideCells >= TesseractLattice.touchFloorCells,
                   "DD4 \(law.rawValue): a dial is itself a control")
            for k in law.detents {
                assert((0..<k).allSatisfy { detentAt(k: k, angle: snapAngle(k: k, index: $0)) == $0 },
                       "DD9 \(law.rawValue): snap must land in its own detent")
            }
            assert(costDetented(law) * 10 < costContinuous,
                   "DD6 \(law.rawValue): the detent must pay for itself")
        }
        assert(rungLadder.map(\.side) == rungLadder.map(\.side).sorted(),
               "DD5: the ladder is stated coarse to fine")
    }
}

// ════════════════════════════════════════════════════════════════
// § 3. The interaction ladder (DD5)
// ════════════════════════════════════════════════════════════════

/// The three phases of a dial gesture. STRUCTURAL: the map onto the
/// rungs is a total switch onto the real `Rung` enum, so an
/// off-ladder render side is unrepresentable.
enum DialGesture: CaseIterable, Sendable {
    /// While the finger moves: the cheapest rung.
    case dragging
    /// On a detent crossing: the middle.
    case crossed
    /// On release: the truth.
    case released

    var rung: Rung {
        switch self {
        case .dragging: return .coarse
        case .crossed:  return .mid
        case .released: return .fine
        }
    }
}

// ════════════════════════════════════════════════════════════════
// § 4. The value and the tracker (DD3, DD9)
// ════════════════════════════════════════════════════════════════

/// A dial's position: one index per degree of freedom, each living in
/// its own ℤ_k. Out-of-range is unrepresentable — every initialiser
/// and every step wraps (DD9), which is what "returnable by feel"
/// means operationally.
struct DialValue: Equatable, Sendable, Codable {
    let law: DialLaw
    private(set) var indices: [Int]

    init(law: DialLaw) {
        self.law = law
        self.indices = Array(repeating: 0, count: law.dof)
    }

    init(law: DialLaw, indices: [Int]) {
        self.law = law
        let ks = law.detents
        self.indices = (0..<ks.count).map { axis in
            let k = ks[axis]
            let raw = axis < indices.count ? indices[axis] : 0
            let m = raw % k
            return m < 0 ? m + k : m
        }
    }

    /// The index on one axis, or 0 for an axis this dial does not have.
    func index(axis: Int) -> Int {
        axis >= 0 && axis < indices.count ? indices[axis] : 0
    }

    /// (DD9) Step one axis by `delta` detents, wrapping. A full turn
    /// (k steps) is the identity from ANY origin.
    func stepped(axis: Int, by delta: Int) -> DialValue {
        guard axis >= 0 && axis < indices.count else { return self }
        var next = indices
        next[axis] = indices[axis] + delta
        return DialValue(law: law, indices: next)
    }

    /// The value with one axis set (already wrapped by the initialiser).
    func setting(axis: Int, to index: Int) -> DialValue {
        guard axis >= 0 && axis < indices.count else { return self }
        var next = indices
        next[axis] = index
        return DialValue(law: law, indices: next)
    }

    /// The rung this dial names — rungPick only, and it reads the SAME
    /// coarse→fine ladder DD5's gesture map does.
    var rung: Rung? {
        guard law == .rungPick else { return nil }
        let ladder = DetentDial.rungLadder
        let i = index(axis: 0)
        return i < ladder.count ? ladder[i] : nil
    }

    /// The dial's spoken value, for the cover's label region.
    var readout: String {
        let ks = law.detents
        let stops = (0..<ks.count)
            .map { "\(indices[$0] + 1)/\(ks[$0])" }
            .joined(separator: " ")
        return "\(law.word) \(stops)"
    }
}

/// (DD3) THE TRACKER. It stores the last detent and emits ONLY on
/// change: there is no per-sample callback, so a 120 Hz ProMotion drag
/// inside one arc costs nothing (DD6). One tracker per dial per axis.
struct DialTracker: Sendable {
    let k: Int
    private(set) var index: Int

    init(k: Int, index: Int = 0) {
        precondition(k > 0, "DD1: a dial with no detents is not a dial")
        self.k = k
        let m = index % k
        self.index = m < 0 ? m + k : m
    }

    /// Feed one touch sample on the ANGULAR axis. Returns true iff a
    /// detent was CROSSED.
    mutating func sample(angle: Double) -> Bool {
        cross(to: DetentDial.detentAt(k: k, angle: angle))
    }

    /// Feed one touch sample on the RADIAL axis (2-DOF dials only).
    mutating func sample(radiusFraction: Double) -> Bool {
        cross(to: DetentDial.ringAt(k: k, radiusFraction: radiusFraction))
    }

    private mutating func cross(to next: Int) -> Bool {
        guard next != index else { return false }
        index = next
        return true
    }
}

// ════════════════════════════════════════════════════════════════
// § 5. The control
// ════════════════════════════════════════════════════════════════

/// The dial, drawn as a `sideCells × sideCells` block of atoms: one
/// CellSprite, opaque ink only (Ink.ink selected · Ink.accent the
/// crossed axis · Ink.ledGhost the rest · the 2×2 checker when
/// disabled, the CellMechanics face for that state). Neighbouring
/// arcs are separated by a HAIRLINE the width of a half-atom, so the
/// detents are visible as detents rather than as a smooth ring.
///
/// PLACEMENT: this view sizes itself to its law's footprint and is
/// placed by its caller through `View.place(_:)` with a machine-
/// checked GridRegion (the dial cover's `dialColour` / `dialRole` /
/// `dialAlloc` / `dialRung`). It mints no rectangle of its own.
///
/// GESTURE (DD3): the callback fires at drag START (drop to 16³), on
/// every detent CROSSING (32³), and on RELEASE (64³) — never per touch
/// sample. The binding is written only when a detent is crossed.
struct DetentDialView: View {
    let law: DialLaw
    @Binding var value: DialValue
    /// False renders the CellMechanics `disabled` face (the 2×2
    /// checker) and refuses the gesture — the state the three
    /// byte-moving dials ship in until Daniel rules on them.
    var enabled: Bool = true
    /// The render ladder callback: (phase, value at that phase).
    var onGesture: (DialGesture, DialValue) -> Void = { _, _ in }

    @State private var trackers: [DialTracker] = []

    private var side: Int { law.sideCells }

    var body: some View {
        CellSprite(cols: side, rows: side, cellPt: Lattice.gifPx) { c, r in
            ink(col: c, row: r)
        }
        .frame(width: Lattice.gif(side), height: Lattice.gif(side))
        .contentShape(Rectangle())
        .gesture(drag, including: enabled ? .all : .none)
        .accessibilityElement()
        .accessibilityLabel(law.word)
        .accessibilityValue(value.readout)
        // No `.isAdjustable` trait: SwiftUI's AccessibilityTraits has no
        // such member (that is UIKit's UIAccessibilityTraitAdjustable).
        // `accessibilityAdjustableAction` IS the SwiftUI spelling — it
        // applies the adjustable trait itself.
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            let delta = direction == .increment ? 1 : -1
            let next = value.stepped(axis: 0, by: delta)
            value = next
            trackers = trackersFor(next)
            onGesture(.crossed, next)
            onGesture(.released, next)
        }
    }

    // ── the gesture (DD3, DD5) ───────────────────────────────────

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if trackers.isEmpty {
                    trackers = trackersFor(value)
                    onGesture(.dragging, value)      // drop to 16³
                }
                sample(g.location)
            }
            .onEnded { g in
                sample(g.location)
                trackers = []
                onGesture(.released, value)          // the truth, once
            }
    }

    private func trackersFor(_ v: DialValue) -> [DialTracker] {
        law.detents.enumerated().map { DialTracker(k: $1, index: v.index(axis: $0)) }
    }

    /// One touch sample. Writes NOTHING unless a detent is crossed.
    private func sample(_ p: CGPoint) {
        guard !trackers.isEmpty else { return }
        var t = trackers
        var crossed = t[0].sample(angle: DetentDial.angle(at: p, sideCells: side))
        if law.dof > 1 {
            let f = DetentDial.radiusFraction(at: p, sideCells: side)
            crossed = t[1].sample(radiusFraction: f) || crossed
        }
        trackers = t
        guard crossed else { return }
        let next = DialValue(law: law, indices: t.map(\.index))
        value = next
        onGesture(.crossed, next)                    // 32³, once per stop
    }

    // ── the ink (one cell at a time, pure) ───────────────────────

    private func ink(col c: Int, row r: Int) -> SIMD3<UInt8>? {
        let n = side
        let cx = Double(n) / 2, cy = Double(n) / 2
        let outer = Double(n) / 2
        let d = CellGeom.dist(c, r, cx, cy)
        guard d <= outer else { return nil }

        // 1-DOF dials are a RING (the shutter's band law: the ring is
        // (recordCells − recordDiscCells)/2 atoms thick, the app's one
        // ring thickness). The 2-DOF disc uses its whole area, because
        // its second axis IS the radius.
        let bandCells = Double(TesseractLattice.recordCells - TesseractLattice.recordDiscCells) / 2
        let inner = law.dof > 1 ? 0 : max(0, outer - bandCells)
        guard d >= inner else { return nil }

        let kAngle = law.detents[0]
        let deg = CellGeom.turn(c, r, cx, cy) * DetentDial.fullTurnDegrees
        let arc = DetentDial.detentAt(k: kAngle, angle: deg)
        // The sector's own width in cells at this radius (tauLower
        // under-states the circumference, so the sector is never
        // over-stated and the hairline never over-eats).
        let sector = DetentDial.tauLower * d / Double(kAngle)
        guard clears(gap: arcGapCells(deg: deg, k: kAngle, radius: d), sector: sector)
        else { return nil }

        var ring = 0
        if law.dof > 1 {
            let kRing = law.detents[1]
            let f = d / outer
            ring = DetentDial.ringAt(k: kRing, radiusFraction: f)
            let band = outer / Double(kRing)
            let off = d - Double(ring) * band
            guard clears(gap: min(off, band - off), sector: band) else { return nil }
        }

        guard enabled else {
            // The CellMechanics `disabled` treatment: the 2×2 checker.
            return CellChecker.ink(c, r, lit: Ink.ledGhost, ghost: CellChecker.dark)
        }

        let onArc = arc == value.index(axis: 0)
        if law.dof == 1 { return onArc ? Ink.ink : Ink.ledGhost }
        let onRing = ring == value.index(axis: 1)
        if onArc && onRing { return Ink.ink }
        return (onArc || onRing) ? Ink.accent : Ink.ledGhost
    }

    /// Arc-length distance from a cell to its nearest detent boundary,
    /// in cells. `tauLower` under-states the circumference, so the gap
    /// is never wider than a half-atom of real arc.
    private func arcGapCells(deg: Double, k: Int, radius: Double) -> Double {
        let arcDeg = DetentDial.fullTurnDegrees / Double(k)
        let off = deg - Double(DetentDial.detentAt(k: k, angle: deg)) * arcDeg
        return min(off, arcDeg - off) / DetentDial.fullTurnDegrees * DetentDial.tauLower * radius
    }

    /// A cell is inked when it stands at least a half-atom clear of its
    /// detent boundary. A hairline that would eat its own sector is no
    /// hairline at all: where the sector is thinner than two half-atoms
    /// (the colour disc's 16 hue arcs near the centre) the boundary
    /// goes implicit, because erasing the sector would say "no detent
    /// here", which is false.
    private func clears(gap: Double, sector: Double) -> Bool {
        sector <= 2 * DetentDial.halfAtomCells || gap >= DetentDial.halfAtomCells
    }
}
