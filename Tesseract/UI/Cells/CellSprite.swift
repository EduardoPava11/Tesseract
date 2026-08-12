import SwiftUI
import UIKit
import simd

/// Widgets drawn as blocks of CELLS at the lattice pitch (ported from
/// SixFour's cell vocabulary). Each cell's color is computed by pure math,
/// baked into a tiny `cols × rows` indexed bitmap, and nearest-neighbour
/// upscaled. No vectors, no AA, no glass.
enum CellBitmap {
    /// Build a `cols × rows` RGBA image (1 px per cell). `color` returns
    /// the cell's sRGB8, or `nil` for a transparent cell.
    static func image(cols: Int, rows: Int, color: (_ col: Int, _ row: Int) -> SIMD3<UInt8>?) -> UIImage? {
        guard cols > 0, rows > 0 else { return nil }
        var px = [UInt8](repeating: 0, count: cols * rows * 4)
        for r in 0 ..< rows {
            for c in 0 ..< cols {
                guard let s = color(c, r) else { continue }   // transparent
                let i = (r * cols + c) * 4
                px[i + 0] = s.x; px[i + 1] = s.y; px[i + 2] = s.z; px[i + 3] = 255
            }
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        return px.withUnsafeMutableBytes { raw -> UIImage? in
            guard let ctx = CGContext(data: raw.baseAddress, width: cols, height: rows,
                                      bitsPerComponent: 8, bytesPerRow: cols * 4,
                                      space: cs, bitmapInfo: info),
                  let cg = ctx.makeImage() else { return nil }
            return UIImage(cgImage: cg)
        }
    }
}

/// Renders a cell bitmap at a cell pitch. Default = the 2pt half-atom
/// (`Lattice.pt(1)`) for fine chrome; pass `Lattice.gifPx` (4pt) for
/// widgets whose pixels are the GIF's.
struct CellSprite: View {
    let cols: Int
    let rows: Int
    var cellPt: CGFloat = Lattice.pt(1)
    let color: (_ col: Int, _ row: Int) -> SIMD3<UInt8>?

    var body: some View {
        if let img = CellBitmap.image(cols: cols, rows: rows, color: color) {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .frame(width: cellPt * CGFloat(cols), height: cellPt * CGFloat(rows))
        }
    }
}

// MARK: - Cell geometry (pure)

enum CellGeom {
    /// Distance from cell (c,r) centre to (cx,cy), in cells.
    @inline(__always) static func dist(_ c: Int, _ r: Int, _ cx: Double, _ cy: Double) -> Double {
        let dx = Double(c) + 0.5 - cx, dy = Double(r) + 0.5 - cy
        return (dx * dx + dy * dy).squareRoot()
    }
    /// Angle of cell (c,r) about (cx,cy): 0 at top, clockwise, in [0,1).
    @inline(__always) static func turn(_ c: Int, _ r: Int, _ cx: Double, _ cy: Double) -> Double {
        let dx = Double(c) + 0.5 - cx, dy = Double(r) + 0.5 - cy
        var a = atan2(dx, -dy)
        if a < 0 { a += 2 * Double.pi }
        return a / (2 * Double.pi)
    }
}

// MARK: - The record button

/// The record button as a 22×22-cell block at the gifPx atom (88pt —
/// upscaled 2026-08-10): a 2-cell ring band directly abutting a filled
/// disc. Closure law: disc(r=9)·2 + ring(t=2)·2 = 22 =
/// `TesseractLattice.recordCells` (disc 18 = `recordDiscCells`). States
/// are cell transforms only: idle · busy (reject red) · disabled (2×2
/// checker). All geometry derives from the lattice constants.
struct CellButton: View {
    enum State { case idle, busy, disabled }
    var state: State = .idle
    /// Ring ink override — the BEAT drives this between `Ink.ledGhost`
    /// and `Ink.ink` on idle ticks; disc stays constant.
    var ringInk: SIMD3<UInt8>? = nil
    private let n = TesseractLattice.recordCells

    var body: some View {
        let discR = Double(TesseractLattice.recordDiscCells) / 2   // 9
        let ringT = Double(n - TesseractLattice.recordDiscCells) / 2   // 2
        let fill: SIMD3<UInt8> = state == .busy ? Ink.reject : Ink.pure
        let ring = state == .busy ? Ink.reject : (ringInk ?? fill)
        let cx = Double(n) / 2, cy = Double(n) / 2
        CellSprite(cols: n, rows: n, cellPt: Lattice.gifPx) { c, r2 in
            let d = CellGeom.dist(c, r2, cx, cy)
            let onDisc = d <= discR
            let onRing = d > discR && d <= discR + ringT
            guard onDisc || onRing else { return nil }
            if state == .disabled {
                let checkOn = ((c / 2) + (r2 / 2)) % 2 == 0
                return checkOn ? fill : Ink.ledGhost
            }
            return onRing ? ring : fill
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Pixel iconography

/// Pixel icons drawn as a `box×box` cell mask via `CellSprite`. The mask
/// is a pure `(col,row) -> Bool` predicate; `ink` fills the on-cells.
struct CellIcon: View {
    let box: Int
    var ink: SIMD3<UInt8> = Ink.ink
    var cellPt: CGFloat = Lattice.pt(1)
    let mask: (_ col: Int, _ row: Int, _ cx: Double, _ cy: Double) -> Bool
    var body: some View {
        let cx = Double(box) / 2, cy = Double(box) / 2
        CellSprite(cols: box, rows: box, cellPt: cellPt) { c, r in
            mask(c, r, cx, cy) ? ink : nil
        }
        .accessibilityHidden(true)
    }
}

extension CellIcon {
    /// The Share glyph: up-arrow rising out of an open tray.
    static func share(box: Int = 12, ink: SIMD3<UInt8> = Ink.ink,
                      cellPt: CGFloat = Lattice.pt(1)) -> CellIcon {
        CellIcon(box: box, ink: ink, cellPt: cellPt) { c, r, cx, _ in
            let midX = Int(cx)
            if r >= 1 && r <= box / 2 && (c == midX - 1 || c == midX) { return true }
            if r == 1 && (c == midX - 2 || c == midX + 1) { return true }
            if r == 2 && (c == midX - 3 || c == midX + 2) { return true }
            let trayTop = box / 2 + 1
            if r >= trayTop && (c == 2 || c == box - 3) { return true }
            if r == box - 2 && c >= 2 && c <= box - 3 { return true }
            return false
        }
    }

    /// The Retake glyph: a near-closed circular arrow with a head.
    static func retake(box: Int = 12, ink: SIMD3<UInt8> = Ink.ink,
                       cellPt: CGFloat = Lattice.pt(1)) -> CellIcon {
        CellIcon(box: box, ink: ink, cellPt: cellPt) { c, r, cx, cy in
            let d = CellGeom.dist(c, r, cx, cy)
            let onRing = d >= Double(box) / 2 - 2.2 && d <= Double(box) / 2 - 0.8
            let turn = CellGeom.turn(c, r, cx, cy)
            if onRing && !(turn > 0.05 && turn < 0.20) { return true }
            if (c == Int(cx) + 2 || c == Int(cx) + 3) && r == 1 { return true }
            return false
        }
    }

    /// A filled disc seal (face-detected dot, tinted by the caller).
    static func seal(box: Int = 12, ink: SIMD3<UInt8> = Ink.ink,
                     cellPt: CGFloat = Lattice.pt(1)) -> CellIcon {
        CellIcon(box: box, ink: ink, cellPt: cellPt) { c, r, cx, cy in
            CellGeom.dist(c, r, cx, cy) <= Double(box) / 2 - 0.6
        }
    }

}
