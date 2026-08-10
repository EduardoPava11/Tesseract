// Gene.metal
// Tesseract
//
// Port of spec/neural/Gene.hs: 137→32→4 forward pass.
//
// The Gene NN maps a BlockPyramid (137 floats) to a TessCoord (d,a,b,c).
// Each thread processes one output pixel.
// Histograms are pre-computed on CPU and passed as a flat buffer.
//
// Architecture:
//   InputEncoder : R^137 → R^32   (ATTENTION, 4416 params)
//        ReLU
//   OutputHead   : R^32 → R^5    (CORE, 165 params)
//        Sigmoid × 3.999 → floor → {0,1,2,3}⁴
//
// Total: 4,581 params. Gene capsule: ~4.5 KB (Int8).
//
// Output 5: (d,a,b,c) tesseract + g global/local weight.
//   d,a,b,c ∈ {0,1,2,3} — 4⁴ palette index
//   g ∈ [0,1] — 1=global (stable), 0=local (epoch-varying)

#include <metal_stdlib>
using namespace metal;

// ════════════════════════════════════════════════════════════════
// § 1. CONSTANTS (must match Gene.hs and GeneNN.swift)
// ════════════════════════════════════════════════════════════════

constant uint INPUT_DIM  = 137;
constant uint HIDDEN_DIM = 32;
constant uint OUTPUT_DIM = 5;  // (d, a, b, c, g)

// Weight layout in flat buffer:
//   [0 .. 4383]                W1: 32 × 137 = 4384 floats
//   [4384 .. 4415]             b1: 32 floats
//   [4416 .. 4575]             W2: 5 × 32  = 160 floats
//   [4576 .. 4580]             b2: 5 floats
//   Total: 4581 floats

constant uint W1_OFFSET = 0;
constant uint B1_OFFSET = HIDDEN_DIM * INPUT_DIM;            // 4384
constant uint W2_OFFSET = B1_OFFSET + HIDDEN_DIM;            // 4416
constant uint B2_OFFSET = W2_OFFSET + OUTPUT_DIM * HIDDEN_DIM; // 4576
constant uint TOTAL_WEIGHTS = B2_OFFSET + OUTPUT_DIM;         // 4581
// Pins the layout arithmetic (and keeps the constant referenced).
static_assert(TOTAL_WEIGHTS == 4581, "gene weight layout drifted");

// ════════════════════════════════════════════════════════════════
// § 2. METADATA (per-frame, per-organism state)
// ════════════════════════════════════════════════════════════════

struct GeneMetaParams {
    uint width;           // output grid width (S)
    uint height;          // output grid height (S)
    float frameNorm;      // z / (K-1) ∈ [0,1]
    float nRGB64;         // sample count at Level64  = 144
    float nRGB128;        // sample count at Level128 = 36
    float nRGB256;        // sample count at Level256 = 9
    float nDepth;         // depth sample count
    float entropyEpoch;   // H(d) / log(4) from prev organism
    float entropyR;       // H(a) / log(4)
    float entropyG;       // H(b) / log(4)
    float entropyB;       // H(c) / log(4)
    float entropyJoint;   // H(d,a,b,c) / log(256)
    // 48 bytes total (12 × 4)
};

// ════════════════════════════════════════════════════════════════
// § 3. SIGMOID
// ════════════════════════════════════════════════════════════════

inline float sigmoid(float x) {
    return 1.0f / (1.0f + exp(-x));
}

// ════════════════════════════════════════════════════════════════
// § 4. MAIN KERNEL: geneForward
//
// Each thread:
//   1. Reads pre-computed histogram data for this pixel
//   2. Appends metadata (depth, frame, sample counts, entropy)
//   3. Matmul: W1 × input + b1 → hidden
//   4. ReLU
//   5. Matmul: W2 × hidden + b2 → output
//   6. Sigmoid × 3.999 → floor → {0,1,2,3}⁴
//   7. Compose palette index: d×64 + a×16 + b×4 + c
// ════════════════════════════════════════════════════════════════

kernel void geneForward(
    // Pre-computed histogram pyramids: 126 floats per pixel
    device const float* histograms             [[buffer(0)]],
    // Per-pixel depth values (S² floats)
    device const float* depths                 [[buffer(1)]],
    // Output: palette indices (S² uint8)
    device uint8_t* output                     [[buffer(2)]],
    // Output: global/local weight per pixel (S² float)
    device float* globalWeights                [[buffer(3)]],
    // Gene weights: 4581 floats
    constant float* weights                    [[buffer(4)]],
    // Per-frame metadata
    constant GeneMetaParams& meta              [[buffer(5)]],
    uint2 gid                                  [[thread_position_in_grid]]
) {
    if (gid.x >= meta.width || gid.y >= meta.height) return;

    uint pixelIdx = gid.y * meta.width + gid.x;

    // ── Build 137-float input vector ──

    // Slots [0..125]: 126 histogram frequencies (pre-computed)
    // The histogram buffer stores 126 floats per pixel
    uint histBase = pixelIdx * 126;

    float input[INPUT_DIM];

    // Copy 126 histogram bins
    for (uint i = 0; i < 126; i++) {
        input[i] = histograms[histBase + i];
    }

    // Slot [126]: depth
    input[126] = clamp(depths[pixelIdx], 0.0f, 1.0f);

    // Slot [127]: frameNorm
    input[127] = meta.frameNorm;

    // Slots [128..131]: sample counts
    input[128] = meta.nRGB64;    // 144
    input[129] = meta.nRGB128;   // 36
    input[130] = meta.nRGB256;   // 9
    input[131] = meta.nDepth;

    // Slots [132..136]: entropy feedback
    input[132] = meta.entropyEpoch;
    input[133] = meta.entropyR;
    input[134] = meta.entropyG;
    input[135] = meta.entropyB;
    input[136] = meta.entropyJoint;

    // ── Layer 1: W1 × input + b1 → hidden (ATTENTION) ──

    float hidden[HIDDEN_DIM];
    for (uint h = 0; h < HIDDEN_DIM; h++) {
        float sum = weights[B1_OFFSET + h];  // bias
        uint wBase = W1_OFFSET + h * INPUT_DIM;
        for (uint i = 0; i < INPUT_DIM; i++) {
            sum += weights[wBase + i] * input[i];
        }
        // ReLU
        hidden[h] = max(0.0f, sum);
    }

    // ── Layer 2: W2 × hidden + b2 → output (CORE) ──

    float raw[OUTPUT_DIM];
    for (uint o = 0; o < OUTPUT_DIM; o++) {
        float sum = weights[B2_OFFSET + o];  // bias
        uint wBase = W2_OFFSET + o * HIDDEN_DIM;
        for (uint h = 0; h < HIDDEN_DIM; h++) {
            sum += weights[wBase + h] * hidden[h];
        }
        raw[o] = sum;
    }

    // ── First 4 outputs: Sigmoid × 3.999 → floor → {0,1,2,3} ──

    uint8_t d = uint8_t(min(3u, uint(sigmoid(raw[0]) * 3.999f)));
    uint8_t a = uint8_t(min(3u, uint(sigmoid(raw[1]) * 3.999f)));
    uint8_t bq = uint8_t(min(3u, uint(sigmoid(raw[2]) * 3.999f)));
    uint8_t c = uint8_t(min(3u, uint(sigmoid(raw[3]) * 3.999f)));

    // ── 5th output: Sigmoid → [0,1] global/local weight ──
    float g = sigmoid(raw[4]);

    // ── Write outputs ──
    output[pixelIdx] = d * 64 + a * 16 + bq * 4 + c;  // tesseract index
    globalWeights[pixelIdx] = g;                         // global/local weight
}
