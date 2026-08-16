// Quantize.metal
// Tesseract
//
// GPU downsample kernels (camera-resolution RGB + depth → the 64×64
// capture grid, 90° CCW baked into the read) + the aerialPreview
// kernel: the 20 Hz GPU twin of DyadPipeline.Live.assign under THE
// AERIAL MIRROR LAW (spec §6c v5). Export quantization stays CPU/ANE;
// this kernel serves the live preview only.
//
// ★ THE CLAIM THAT USED TO SIT HERE WAS FALSE, and it is corrected
// rather than deleted because it is exactly the kind of comment this
// codebase has been burned by twice. It read "near-tie fp32 flips vs
// the CPU reference are the only permitted difference." Measured
// 2026-08-15, TWO WAYS, and both refute it:
//   3.8% to 11.7% of pixels attributable to the staging convention
//     alone, isolated by reimplementing both conventions side by side;
//   65.80% end to end (2695 of 4096) between a real dispatch of this
//     kernel and DyadPipeline.Live.assign on a figure-over-ground
//     fixture, printed by AerialParityTests on every run.
// The gap between those two numbers is NOT yet accounted for and must
// not be assumed to be more of the same cause. One known candidate is
// already written down in CLAUDE.md: the live sigma-side chaos target
// pools the CURRENT frame where the export pools the 4-frame S4 group.
// Whatever the split, the divergence is SYSTEMATIC, not a near tie. The
// authoritative DyadPalette.hs:521 aerialPrimary searches on the
// CONTINUOUS staged value; DyadPipeline.stagedField returns UInt8
// triples that both consumers convert back to OKLab before the
// argmin; this kernel round-trips its INPUT and stages in float. So
// THIS KERNEL MATCHES THE SPEC AND THE SWIFT DOES NOT. Which
// convention is law is Daniel's ruling, tracked by
// AerialParityTests.testAerialKernelMatchesTheCPUAssignmentOnEveryPixel
// and owed an axiom (DY17) naming which staged value the argmin reads.
// Nothing in the sixteen green DyadPalette axioms says.
//
// The old quantizeWithDepth kernel was removed 2026-08-10: it read raw
// TrueDepth METERS where the [0,1] signal contract applied. Here the
// meters→signal map is applied IN the kernel from parameters supplied
// by DepthSignal.swift (single source of the anchors).

#include <metal_stdlib>
using namespace metal;

// ════════════════════════════════════════════════════════════════
// § 0. AERIAL PREVIEW — γ staging + σ-routing on the GPU
// ════════════════════════════════════════════════════════════════

// Layout mirrored by AerialParamsSwift (three 16-byte rows, 48 bytes).
struct AerialParams {
    float4 centroid;   // xyz = OKLab c_F (the γ-staging centroid)
    float4 scalars;    // x = s*, y = τ, z = 1/dNear, w = 1/dFar
    uint4  flags;      // x = twoPhase, y = side (64), z = node count
                       // (★PAIR TREE: 16 when the 32-level targets ride),
                       // w = BLEED (0 ⇒ hard MAP classes, no dither band)
};

// sRGB → OKLab (Björn Ottosson's matrices — mirror of DyadPalette.swift).
inline float srgbToLinearGPU(float c) {
    return c <= 0.04045f ? c / 12.92f : powr((c + 0.055f) / 1.055f, 2.4f);
}

inline float3 oklabFromSrgbGPU(float3 srgb) {
    float r = srgbToLinearGPU(srgb.r);
    float g = srgbToLinearGPU(srgb.g);
    float b = srgbToLinearGPU(srgb.b);
    float l = 0.4122214708f * r + 0.5363325363f * g + 0.0514459929f * b;
    float m = 0.2119034982f * r + 0.6806995451f * g + 0.1073969566f * b;
    float s = 0.0883024619f * r + 0.2817188376f * g + 0.6299787005f * b;
    float l3 = powr(l, 1.0f / 3.0f);
    float m3 = powr(m, 1.0f / 3.0f);
    float s3 = powr(s, 1.0f / 3.0f);
    return float3(
        0.2104542553f * l3 + 0.7936177850f * m3 - 0.0040720468f * s3,
        1.9779984951f * l3 - 2.4285922050f * m3 + 0.4505937099f * s3,
        0.0259040371f * l3 + 0.7827717662f * m3 - 0.8086757660f * s3);
}

// The Bayer 4×4 (DyadPalette §6 v3) — same matrix as the CPU side.
constant int aerialBayer[4][4] = {
    {0, 8, 2, 10}, {12, 4, 14, 6}, {3, 11, 1, 9}, {15, 7, 13, 5}
};

kernel void aerialPreview(
    texture2d<float, access::read> rgbTexture   [[texture(0)]],
    texture2d<float, access::read> depthTexture [[texture(1)]],
    device const float4* prims                  [[buffer(0)]],   // 128 OKLab
    constant AerialParams& P                    [[buffer(1)]],
    device uchar* out                           [[buffer(2)]],
    device const float4* nodes                  [[buffer(3)]],   // ★PAIR TREE: 16 depth-4
                                                                  // means, w = canonical leaf;
                                                                  // count in P.flags.z
    uint2 gid                                   [[thread_position_in_grid]]
) {
    uint side = P.flags.y;
    if (gid.x >= side || gid.y >= side) return;

    // Depth METERS → [0,1] signal (DepthSignal contract, anchors from
    // the params so DepthSignal.swift stays the single source).
    float m = depthTexture.read(gid).r;
    float s;
    if (isfinite(m) && m > 0.0f) {
        s = clamp((1.0f / m - P.scalars.w) / (P.scalars.z - P.scalars.w),
                  0.0f, 1.0f);
    } else {
        s = 0.5f;   // DepthSignal.fill
    }

    // Quantize the sample to sRGB8 first (the DY12 byte round-trip the
    // CPU reference applies), then to OKLab.
    float3 rgb8 = round(saturate(rgbTexture.read(gid).rgb) * 255.0f) / 255.0f;
    float3 lab = oklabFromSrgbGPU(rgb8);

    // γ staging: ŷ = c_F + γ(s)·(y − c_F), γ = 1/(2−s)  (DY9/DY10).
    float gamma = 1.0f / (2.0f - s);
    float3 yhat = P.centroid.xyz + gamma * (lab - P.centroid.xyz);

    // Coverage t = mixture posterior (0 when single-phase, R3), then
    // the BLEED collapse. Exact mirror of the CPU law
    // DyadPipeline.coverage(_:fit:twoPhase:bleed:): with BLEED off the
    // band is not softened but ABSENT — t becomes the hard MAP class,
    // so no Bayer threshold can route a tile to the σ side mid-band.
    // Without this the setting answered on the CPU and the export but
    // not on the LIVE surface, which is the default path.
    //
    // ★ THE DEGENERACY GUARD, added 2026-08-15 after an adversarial
    // run measured 4096/4096 role flips on the DEFAULT LIVE PATH.
    // The CPU twin's FIRST line is
    //     guard twoPhase, !fit.isDegenerate else { return 0 }
    // and this kernel had no degeneracy input at all. A degenerate
    // per-frame fit packs s* = NaN and tau = +inf into the params;
    // the exponential then yields NaN, and the BLEED-off collapse
    // below asks `t < 0.5`, which is FALSE for NaN, so t became 1.0
    // and EVERY pixel routed to the sigma side. A silent, total
    // inversion of the surface.
    //
    // It is not a corner case: DepthMixture.localLevelAlpha returns 1
    // whenever series.count < 3, so the two-coarse-frame ring about
    // 0.2 s into every session can vote two-phase on a degenerate
    // fit. Gated by AerialParityTests.
    float t = 0.0f;
    if (P.flags.x != 0u && isfinite(P.scalars.x) && isfinite(P.scalars.y)) {
        t = 1.0f / (1.0f + exp((s - P.scalars.x) / P.scalars.y));
        if (P.flags.w == 0u) { t = (t < 0.5f) ? 0.0f : 1.0f; }
    }

    // σ-routing at coverage t (Bayer threshold on the grid position).
    // v7 CHAOS BLUR (Daniel's ruling, 2026-08-12, spec §6d): the σ
    // side targets the rung-16 BLOCK MEAN of the staged field — the
    // background blurs as it becomes chaos. The same-hue ground
    // (DY14 v7) makes the plain σ-mirror hue-faithful; the comp
    // re-route is dead. CPU twin: DyadPipeline.pairDitherFrame
    // (the ONE dither — export and live surface both call it).
    float th = (float(aerialBayer[gid.y % 4][gid.x % 4]) + 0.5f) / 16.0f;
    bool sigmaSide = (th < t);
    uint idx;
    if (sigmaSide) {
        // chaos blur: rung-16 spatial block mean of ŷ (spec §6d)
        uint bx = (gid.x / 4u) * 4u;
        uint by = (gid.y / 4u) * 4u;
        float3 sum = float3(0.0f);
        for (uint dy = 0; dy < 4u; dy++) {
            for (uint dx = 0; dx < 4u; dx++) {
                uint2 q = uint2(bx + dx, by + dy);
                float mq = depthTexture.read(q).r;
                float sq;
                if (isfinite(mq) && mq > 0.0f) {
                    sq = clamp((1.0f / mq - P.scalars.w) / (P.scalars.z - P.scalars.w),
                               0.0f, 1.0f);
                } else {
                    sq = 0.5f;   // DepthSignal.fill
                }
                float3 rq = round(saturate(rgbTexture.read(q).rgb) * 255.0f) / 255.0f;
                float3 lq = oklabFromSrgbGPU(rq);
                float gq = 1.0f / (2.0f - sq);
                sum += P.centroid.xyz + gq * (lq - P.centroid.xyz);
            }
        }
        float3 target = sum / 16.0f;
        uint nodeCount = P.flags.z;
        if (nodeCount > 0u) {
            // ★PAIR TREE P2 (prefix law): 32-level quantization —
            // nearest depth-4 node, emit its canonical leaf's partner
            // (CPU twin: DyadPipeline.pairDitherFrame).
            uint best = 0;
            float bestD = INFINITY;
            for (uint c = 0; c < nodeCount; c++) {
                float3 d = nodes[c].xyz - target;
                float dist = dot(d, d);
                if (dist < bestD) { bestD = dist; best = c; }
            }
            idx = 255u - uint(nodes[best].w);
        } else {
            uint best = 0;
            float bestD = INFINITY;
            for (uint j = 0; j < 128; j++) {
                float3 d = prims[j].xyz - target;
                float dist = dot(d, d);
                if (dist < bestD) { bestD = dist; best = j; }
            }
            idx = 255u - best;
        }
    } else {
        uint best = 0;
        float bestD = INFINITY;
        for (uint j = 0; j < 128; j++) {
            float3 d = prims[j].xyz - yhat;
            float dist = dot(d, d);
            if (dist < bestD) { bestD = dist; best = j; }
        }
        idx = best;
    }
    out[gid.y * side + gid.x] = uchar(idx);
}

// ════════════════════════════════════════════════════════════════
// § 1. DOWNSAMPLE KERNEL: camera resolution → 64×64
// ════════════════════════════════════════════════════════════════

// Dynamic downsample params (universal 768 crop, from Block.hs)
struct DownsampleParams {
    uint cropX;         // (sensorWidth - cropSize) / 2
    uint cropY;         // (sensorHeight - cropSize) / 2
    uint step;          // cropSize / outputSize, integer
    uint halfStep;      // step / 2
    uint outputSize;    // 64, 128, or 256
    uint _pad;          // pad to 24 bytes (6 × uint)
};

// Port of FrameGeometry.hs rgbSource/depthSource:
//   srcX = cropX + gid.y * step + halfStep     (90° CCW: output Y → source X)
//   srcY = cropY + (63 - gid.x) * step + halfStep  (90° CCW: inverted output X → source Y)
//
// Verified by Haskell axioms G5-G10 for all 4096 output pixels.

kernel void downsampleRGB(
    texture2d<float, access::read> srcTexture   [[texture(0)]],
    texture2d<float, access::write> dstTexture  [[texture(1)]],
    constant DownsampleParams& params           [[buffer(0)]],
    uint2 gid                                   [[thread_position_in_grid]]
) {
    if (gid.x >= params.outputSize || gid.y >= params.outputSize) return;

    // 90° CCW: videoRotationAngle=90 reports portrait dims but pixel memory
    // may still be landscape. Rotate in the read.
    uint srcX = params.cropX + gid.y * params.step + params.halfStep;
    uint srcY = params.cropY + (params.outputSize - 1 - gid.x) * params.step + params.halfStep;

    float4 color = srcTexture.read(uint2(srcX, srcY));
    dstTexture.write(color, gid);
}

kernel void downsampleDepth(
    texture2d<float, access::read> srcTexture   [[texture(0)]],
    texture2d<float, access::write> dstTexture  [[texture(1)]],
    constant DownsampleParams& params           [[buffer(0)]],
    uint2 gid                                   [[thread_position_in_grid]]
) {
    if (gid.x >= params.outputSize || gid.y >= params.outputSize) return;

    // 90° CCW (same as RGB)
    uint srcX = params.cropX + gid.y * params.step + params.halfStep;
    uint srcY = params.cropY + (params.outputSize - 1 - gid.x) * params.step + params.halfStep;

    float4 depth = srcTexture.read(uint2(srcX, srcY));
    dstTexture.write(depth, gid);
}
