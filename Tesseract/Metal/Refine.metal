// Refine.metal
// Tesseract
//
// Stage A of pass-2 centroid refinement (docs/REFINE-PASSES.md) as a
// GPU fold. BIT-EXACT parity with CentroidRefiner.stageA by
// construction:
//
//   * every per-pixel contribution is quantized to 2^16 fixed point
//     with the SAME IEEE ops in the SAME order as the Swift reference
//     (MTL_FAST_MATH is disabled project-wide — no reassociation, no
//     fma contraction), then
//   * accumulated with INTEGER atomics — integer addition commutes
//     with no rounding, so any thread scheduling produces the same
//     sums. The parity test asserts equality, not tolerance.
//
// Accumulator layout: per (frame, entry) slot of 8 uints
//   [wsum, w·r, w·g, w·b, count, pad, pad, pad]
// Per-frame partials keep every sum < 2^28 (4096 px × 2^16), safely
// inside uint32; the CPU combines the 64 frame partials in UInt64.

#include <metal_stdlib>
using namespace metal;

constant float kScale = 65536.0f;   // == RefineKernelABI.scale
constant uint kSlot = 8;            // == RefineKernelABI.slotStride

// The ABI is authored in Swift (RefineKernelABI); these asserts pin
// this side of the contract at compile time. Slot order:
// [wSum, w·r, w·g, w·b, count, pad, pad, pad].
static_assert(kSlot == 8, "slot stride must match RefineKernelABI.slotStride");
static_assert(kScale == 65536.0f, "scale must match RefineKernelABI.scale (2^16)");

kernel void refineAccumulate(
    device const uchar*   indices        [[buffer(0)]],  // F·P
    device const float*   rgb            [[buffer(1)]],  // F·P·3
    device const float*   weights        [[buffer(2)]],  // F·P
    device atomic_uint*   accum          [[buffer(3)]],  // F·256·8
    constant uint&        pixelsPerFrame [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]])               // (pixel, frame)
{
    const uint p = gid.x;
    const uint f = gid.y;
    if (p >= pixelsPerFrame) { return; }

    const uint px = f * pixelsPerFrame + p;
    const uint entry = uint(indices[px]);

    float w = weights[px];
    if (!isfinite(w)) { w = 0.0f; }
    w = min(1.0f, max(0.0f, w));

    // Two-step multiply, round-to-nearest-even — mirrors quantizeTerm.
    const float r = rgb[px * 3 + 0];
    const float g = rgb[px * 3 + 1];
    const float b = rgb[px * 3 + 2];
    const uint wq  = uint(rint(w * kScale));
    const uint wrq = uint(rint((w * r) * kScale));
    const uint wgq = uint(rint((w * g) * kScale));
    const uint wbq = uint(rint((w * b) * kScale));

    device atomic_uint* slot = accum + (f * 256 + entry) * kSlot;
    atomic_fetch_add_explicit(slot + 0, wq,  memory_order_relaxed);
    atomic_fetch_add_explicit(slot + 1, wrq, memory_order_relaxed);
    atomic_fetch_add_explicit(slot + 2, wgq, memory_order_relaxed);
    atomic_fetch_add_explicit(slot + 3, wbq, memory_order_relaxed);
    atomic_fetch_add_explicit(slot + 4, 1u,  memory_order_relaxed);
}
