// ANELoop.metal
// Tesseract
//
// THE SIMT PORT of the exchange loop (spec/neural/ANELoop.hs §4b,
// AL9; docs/ane-loop-design.md). One GPU thread per 4³ spacetime
// block: AL2 says blocks never couple, so 4096 threads need no
// synchronization, no atomics, no barriers — pure SIMT width.
//
// AL9's running sums are the whole trick: the block mean and the
// eight 2-cell means are carried and δ-updated after every accepted
// exchange (O(1) per stage), proven exactly equal to recomputation
// over Rational. Float rounding differs from the Double CPU twin —
// the parity gate accepts score-near-ties only (XP2), and AL4's
// monotone-acceptance keeps every result lawful regardless.
//
// Unlike the fused ANE graph (compile-time K), `sweeps` is a
// RUNTIME loop bound — this is the runtime-adaptive-K execution
// port for the B+E streaming cadence on the iPhone 17 Pro.
//
// MTL_FAST_MATH is disabled project-wide: IEEE ops in program
// order, no reassociation, no fma contraction — the visit law
// below mirrors ANELoop.sweepBlockCPU statement for statement
// (fold candidates in order, strict decrease only, ties keep the
// current index; AL7 curvature hardcoded as the derived constant).

#include <metal_stdlib>
using namespace metal;

constant float kCurvature = 1.0f + 1.0f / 8.0f + 1.0f / 64.0f;  // AL7

// Block-local raster v = x + 4(y + 4t) → 2-cell index (AL9 cellOf).
static inline uint cellOf(uint v) {
    const uint x = v & 3u;
    const uint y = (v >> 2) & 3u;
    const uint t = v >> 4;
    return (x >> 1) + 2u * ((y >> 1) + 2u * (t >> 1));
}

kernel void aneLoopSweepSIMT(
    device const float* y          [[buffer(0)]],   // B·64·3 targets
    device const float* cand       [[buffer(1)]],   // B·8·3 candidates
    device uchar*       q          [[buffer(2)]],   // B·64 indices, in/out
    constant uint&      sweeps     [[buffer(3)]],   // runtime K
    constant uint&      blockCount [[buffer(4)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= blockCount) { return; }
    device const float* yb = y + gid * 64u * 3u;
    device const float* cb = cand + gid * 8u * 3u;
    device uchar* qb = q + gid * 64u;

    float3 c[8];
    for (uint i = 0; i < 8u; i++) {
        c[i] = float3(cb[3u * i], cb[3u * i + 1u], cb[3u * i + 2u]);
    }

    uchar qi[64];
    float3 yv[64];
    float3 bsum = float3(0.0f);
    float3 c2[8] = { float3(0.0f), float3(0.0f), float3(0.0f), float3(0.0f),
                     float3(0.0f), float3(0.0f), float3(0.0f), float3(0.0f) };
    for (uint v = 0; v < 64u; v++) {
        qi[v] = qb[v];
        yv[v] = float3(yb[3u * v], yb[3u * v + 1u], yb[3u * v + 2u]);
        const float3 e = c[qi[v]] - yv[v];
        bsum += e;
        c2[cellOf(v)] += e;
    }

    for (uint k = 0; k < sweeps; k++) {
        for (uint v = 0; v < 64u; v++) {
            const float3 qv = c[qi[v]];
            const float3 g = (qv - yv[v])
                           + c2[cellOf(v)] * (1.0f / 8.0f)
                           + bsum * (1.0f / 64.0f);
            float best = 0.0f;               // ΔF of staying put
            uint bestIdx = uint(qi[v]);
            for (uint ci = 0; ci < 8u; ci++) {
                const float3 d = c[ci] - qv;
                const float df = 2.0f * dot(g, d) + kCurvature * dot(d, d);
                if (df < best) { best = df; bestIdx = ci; }
            }
            if (bestIdx != uint(qi[v])) {    // accepted: δ-update (AL9)
                const float3 d = c[bestIdx] - qv;
                bsum += d;
                c2[cellOf(v)] += d;
                qi[v] = uchar(bestIdx);
            }
        }
    }

    for (uint v = 0; v < 64u; v++) { qb[v] = qi[v]; }
}
