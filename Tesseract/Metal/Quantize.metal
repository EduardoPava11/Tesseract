// Quantize.metal
// Tesseract
//
// Port of DepthBinomial.hs to Metal compute shader.
// Per-pixel: σ_i = σ_base × (2 - d_i)
// Continuous depth, no zones. One GPU pass.
//
// Input:  RGB texture (64×64) + depth texture (64×64) + frame params
// Output: palette index buffer (4096 UInt8 values)

#include <metal_stdlib>
using namespace metal;

// ════════════════════════════════════════════════════════════════
// § 1. HASH PRNG (port of Haskell pixelHash)
// ════════════════════════════════════════════════════════════════

inline uint pixelHash(uint x, uint y, uint seed) {
    uint h0 = x * 374761393u + y * 668265263u + seed;
    uint h1 = (h0 ^ (h0 >> 15)) * 2246822519u;
    uint h2 = (h1 ^ (h1 >> 13)) * 3266489917u;
    return h2 ^ (h2 >> 16);
}

inline float hashToFloat(uint h) {
    return float(h % 1000000u) / 1000000.0f;
}

// ════════════════════════════════════════════════════════════════
// § 2. CDF SAMPLING
// ════════════════════════════════════════════════════════════════

inline uint8_t cdfSample(float4 probs, float u) {
    float cumul = 0.0f;
    for (int d = 0; d < 3; d++) {
        cumul += probs[d];
        if (cumul >= u) return uint8_t(d);
    }
    return 3;
}

// ════════════════════════════════════════════════════════════════
// § 3. PARAMETERS
// ════════════════════════════════════════════════════════════════

// NOTE: float4 MUST come first to avoid 16-byte alignment padding.
// Swift struct must match this layout exactly.
struct QuantizeParams {
    float4 epochCenters;    // offset 0  (16 bytes, 16-byte aligned)
    float sigmaBase;        // offset 16 (4 bytes)
    uint frameIndex;        // offset 20
    uint seed;              // offset 24
    uint width;             // offset 28
    uint height;            // offset 32
    uint debugFlags;        // offset 36
    uint _pad;              // offset 40 (pad to 48 = 16-byte multiple)
    // Total: 48 bytes
};

// ════════════════════════════════════════════════════════════════
// § 4. MAIN KERNEL: quantizeWithDepth
// ════════════════════════════════════════════════════════════════

kernel void quantizeWithDepth(
    texture2d<float, access::read> rgbTexture   [[texture(0)]],
    texture2d<float, access::read> depthTexture [[texture(1)]],
    device uint8_t* output                       [[buffer(0)]],
    constant QuantizeParams& params              [[buffer(1)]],
    // Debug: per-epoch pixel counts (4 atomic counters)
    device atomic_uint* epochCounts              [[buffer(2)]],
    // Debug: sigma histogram (32 bins from σ=7 to σ=16)
    device atomic_uint* sigmaHist                [[buffer(3)]],
    uint2 gid                                    [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= params.width || gid.y >= params.height) return;

    uint pixelIdx = gid.y * params.width + gid.x;

    // ── Read RGB ──
    float4 rgba = rgbTexture.read(gid);
    float r = rgba.r;
    float g = rgba.g;
    float b = rgba.b;

    // ── Read Depth ──
    // depth texture: r channel = depth in [0,1], 1=near, 0=far
    float depth = depthTexture.read(gid).r;
    // Clamp to valid range
    depth = clamp(depth, 0.0f, 1.0f);

    // ── Continuous σ: σ_i = σ_base × (2 - d_i) ──
    // d=1 (near/face): σ = σ_base × 1.0 → stable
    // d=0 (far/wall):  σ = σ_base × 2.0 → volatile
    float sigma_i = params.sigmaBase * (2.0f - depth);

    // ── Debug: log sigma to histogram ──
    {
        // Map σ from [7, 16] to bin [0, 31]
        int sigmaBin = clamp(int((sigma_i - 7.0f) * 32.0f / 9.0f), 0, 31);
        atomic_fetch_add_explicit(&sigmaHist[sigmaBin], 1, memory_order_relaxed);
    }

    // ── Epoch probabilities with per-pixel σ ──
    float z = float(params.frameIndex);
    float s2 = 2.0f * sigma_i * sigma_i;

    float4 probs;
    probs[0] = exp(-(z - params.epochCenters[0]) * (z - params.epochCenters[0]) / s2);
    probs[1] = exp(-(z - params.epochCenters[1]) * (z - params.epochCenters[1]) / s2);
    probs[2] = exp(-(z - params.epochCenters[2]) * (z - params.epochCenters[2]) / s2);
    probs[3] = exp(-(z - params.epochCenters[3]) * (z - params.epochCenters[3]) / s2);

    float total = probs[0] + probs[1] + probs[2] + probs[3];
    // Guard against division by zero (all probs near zero for extreme σ)
    if (total < 1e-10f) {
        probs = float4(0.25f);  // uniform fallback
    } else {
        probs /= total;
    }

    // ── Hash-based epoch sampling ──
    uint hash = pixelHash(gid.x, gid.y, params.seed + params.frameIndex * 997u);
    uint8_t epoch = cdfSample(probs, hashToFloat(hash));

    // ── Debug: count epoch assignments ──
    atomic_fetch_add_explicit(&epochCounts[epoch], 1, memory_order_relaxed);

    // ── Quantize RGB to 4³ grid ──
    uint8_t a = uint8_t(clamp(r * 4.0f, 0.0f, 3.0f));
    uint8_t bq = uint8_t(clamp(g * 4.0f, 0.0f, 3.0f));
    uint8_t c = uint8_t(clamp(b * 4.0f, 0.0f, 3.0f));

    // ── Tesseract index: d×64 + a×16 + b×4 + c ──
    output[pixelIdx] = epoch * 64 + a * 16 + bq * 4 + c;
}

// ════════════════════════════════════════════════════════════════
// § 5. DOWNSAMPLE KERNEL: camera resolution → 64×64
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
