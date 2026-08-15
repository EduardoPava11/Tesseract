import Foundation
import QuartzCore
import Observation

/// THE ONE UI clock (ported from SixFour). A single `CADisplayLink` pinned
/// to `CameraConfig.targetFPS` (20 Hz) via `preferredFrameRateRange` —
/// no other Timer/clock may tick the chrome. (GIF playback inside
/// `GIFPlayerView` stays UIImageView-driven: that is content playback,
/// not chrome.)
///
/// Each tick flips the heartbeat `phase` bit and calls `onTick`.
/// Reduce-motion pins the heartbeat to 0 (static canvas) but the link
/// keeps firing so per-tick logic still runs. The clock never stops
/// itself; the owning view drives `start()`/`stop()`.
@MainActor
@Observable
final class SurfaceClock {

    /// The 20 fps heartbeat bit (0/1). Flipped each tick unless
    /// reduce-motion pins it to 0.
    private(set) var heartbeat: Int = 0

    /// Monotonic tick counter since `start()` — the free-running phase
    /// every animation derives from (1 tick = 5 cs).
    private(set) var tick: Int = 0

    /// When true, the heartbeat bit is pinned to 0 and the BEAT
    /// affordance is suppressed by callers (they evaluate treatments at
    /// tick 1, provably beat-free).
    var reduceMotion: Bool {
        didSet { if reduceMotion { heartbeat = 0 } }
    }

    private(set) var running: Bool = false

    /// The per-tick closure the surface registers. Set before `start()`.
    @ObservationIgnored var onTick: (() -> Void)?

    @ObservationIgnored private var link: CADisplayLink?

    init(reduceMotion: Bool = false) { self.reduceMotion = reduceMotion }

    /// Start the single display link, pinned to the logic rate.
    func start() {
        guard !running else { return }
        let hz = Float(CameraConfig.targetFPS)
        let link = CADisplayLink(target: SurfaceClockProxy(self), selector: #selector(SurfaceClockProxy.fire))
        link.preferredFrameRateRange = .init(minimum: hz, maximum: hz, preferred: hz)
        link.add(to: .main, forMode: .common)
        self.link = link
        running = true
    }

    func stop() {
        link?.invalidate()
        link = nil
        running = false
    }

    /// One tick — flips the heartbeat (unless reduce-motion), runs `onTick`.
    fileprivate func fire() {
        tick &+= 1
        if !reduceMotion { heartbeat ^= 1 }
        onTick?()
    }
}

/// A tiny ObjC target so `CADisplayLink` can hold a WEAK reference to the
/// clock (the link otherwise retains its target and leaks it).
@MainActor
private final class SurfaceClockProxy: NSObject {
    weak var clock: SurfaceClock?
    init(_ clock: SurfaceClock) { self.clock = clock; super.init() }
    @objc func fire() { clock?.fire() }
}
