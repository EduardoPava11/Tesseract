import Foundation

/// Shared per-tick easing (ported from SixFour) — UI presentation only.
/// EVERY animation derives from the ONE 20 fps `SurfaceClock.tick`:
/// progress `(tick − startTick) / durationTicks`, shaped by smoothstep.
/// No new clock, no rate change.
enum CellEase {
    /// Linear progress 0…1 from `startTick` over `ticks` ticks (clamped).
    static func linear(_ tick: Int, since startTick: Int, ticks: Int) -> Double {
        guard ticks > 0 else { return 1 }
        return min(1, max(0, Double(tick - startTick) / Double(ticks)))
    }

    /// Smoothstep-eased progress 0…1: `p²(3 − 2p)` — flat at both ends.
    static func progress(_ tick: Int, since startTick: Int, ticks: Int) -> Double {
        let p = linear(tick, since: startTick, ticks: ticks)
        return p * p * (3 - 2 * p)
    }
}
