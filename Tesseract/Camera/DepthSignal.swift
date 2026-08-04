import Foundation

/// Meters → [0,1] depth signal — the LIVE-mode producer contract.
///
/// Swift twin of `spec/temporal/DepthSignal.hs` (DS1–DS4, exact-rational).
/// Golden-pinned by `DepthSignalTests`. Downstream consumers
/// (`BinomialCadence.sigmaForDepth`, `CentroidRefiner`, the D-channel
/// preview) all assume s ∈ [0,1], 1 = near, 0.5 = invalid fill —
/// FaceCadence FC2 pins FACE mode to the same convention.
///
/// The map is affine in DISPARITY (1/m, the TrueDepth native quantity)
/// between two pinned anchors, then clamped:
///
///     s(m) = clamp01((1/m − 1/dFar) / (1/dNear − 1/dFar))
///
/// A fixed map, not per-frame normalization: σ(s) is applied per frame
/// across the 64-frame capture, so the signal must be a pure function
/// of meters or the epoch cadence flickers.
enum DepthSignal {
    /// Closest expected face distance — maps to s = 1.
    static let dNear: Float = 0.25
    /// Background cutoff — maps to s = 0.
    static let dFar: Float = 1.5
    /// Neutral signal for missing / non-finite / non-positive depth.
    static let fill: Float = 0.5

    private static let invNear = 1 / dNear
    private static let invFar = 1 / dFar

    /// The law. Caller guarantees `meters` is finite and positive;
    /// use `signalOrFill` at sensor readback boundaries.
    static func signal(meters: Float) -> Float {
        let s = (1 / meters - invFar) / (invNear - invFar)
        return min(1, max(0, s))
    }

    /// Total producer-side version: invalid sensor values → `fill`.
    static func signalOrFill(meters: Float) -> Float {
        guard meters.isFinite, meters > 0 else { return fill }
        return signal(meters: meters)
    }
}
