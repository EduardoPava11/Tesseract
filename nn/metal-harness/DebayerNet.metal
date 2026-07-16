// BAYER-RESIDUAL CONTRACT v1 -- Metal port of nn/debayer operator:
//   out = clamp01( passthrough( MHC(m) + f_theta(m) ) )
// RGGB phase from absolute pixel parity: (0,0)=R (0,1)=G1 (1,0)=G2 (1,1)=B.
// Border addressing: reflect-101 (x[-k] := x[+k]) -- phase-preserving.
// f_theta: 4 bias-free 3x3 convs (4->16->16->16->3), leaky-ReLU slope 1/16,
// weights in MLX (O,kH,kW,I) layout baked as constant arrays (see DebayerWeights.h).
// One kernel, 8x8 output tile per threadgroup; 16x16 mirrored mosaic tile and
// all intermediate activations live in threadgroup memory; FP32 accumulation.

#include <metal_stdlib>
using namespace metal;

#include "DebayerWeights.h"

#define TILE 8          // output tile edge = threadgroup dims
#define HALO 4          // four valid 3x3 convs
#define MT   16         // mosaic tile edge = TILE + 2*HALO
#define L1   14         // layer-1 activation grid edge (MT - 2)
#define L2   12
#define L3   10
#define NTHREADS (TILE * TILE)

static inline int mirror101(int i, int n) {
    if (i < 0) i = -i;
    if (i >= n) i = 2 * n - 2 - i;
    return i;
}

// ---- Malvar-He-Cutler 5x5 taps (x 1/8), correlations, centered at (cy,cx) ----
#define M_(dy, dx) M[(cy + (dy)) * MT + (cx + (dx))]

static inline float mhcG(threadgroup const float *M, int cy, int cx) {
    return 0.125f * (4.0f * M_(0, 0)
                   + 2.0f * (M_(0, -1) + M_(0, 1) + M_(-1, 0) + M_(1, 0))
                   - 1.0f * (M_(0, -2) + M_(0, 2) + M_(-2, 0) + M_(2, 0)));
}
static inline float mhcA(threadgroup const float *M, int cy, int cx) {   // same-color row
    return 0.125f * (5.0f * M_(0, 0)
                   + 4.0f * (M_(0, -1) + M_(0, 1))
                   - 1.0f * (M_(0, -2) + M_(0, 2))
                   - 1.0f * (M_(-1, -1) + M_(-1, 1) + M_(1, -1) + M_(1, 1))
                   + 0.5f * (M_(-2, 0) + M_(2, 0)));
}
static inline float mhcAT(threadgroup const float *M, int cy, int cx) {  // same-color column
    return 0.125f * (5.0f * M_(0, 0)
                   + 4.0f * (M_(-1, 0) + M_(1, 0))
                   - 1.0f * (M_(-2, 0) + M_(2, 0))
                   - 1.0f * (M_(-1, -1) + M_(-1, 1) + M_(1, -1) + M_(1, 1))
                   + 0.5f * (M_(0, -2) + M_(0, 2)));
}
static inline float mhcD(threadgroup const float *M, int cy, int cx) {   // R at B / B at R
    return 0.125f * (6.0f * M_(0, 0)
                   + 2.0f * (M_(-1, -1) + M_(-1, 1) + M_(1, -1) + M_(1, 1))
                   - 1.5f * (M_(0, -2) + M_(0, 2) + M_(-2, 0) + M_(2, 0)));
}

static inline float lrelu(float v) { return v > 0.0f ? v : v * 0.0625f; }

// ---- full operator, templated on baked weight precision ----
template <typename WT>
static void debayer_impl(device const float *mosaic,
                         device float *outRGB,
                         constant WT *W1, constant WT *W2,
                         constant WT *W3, constant WT *W4,
                         int H, int W,
                         ushort2 tid, ushort2 tgid,
                         threadgroup float *tgM,
                         threadgroup float *bufA,
                         threadgroup float *bufB)
{
    const int lin = tid.y * TILE + tid.x;
    const int baseY = int(tgid.y) * TILE - HALO;   // virtual coord of tile origin
    const int baseX = int(tgid.x) * TILE - HALO;

    // load 16x16 mosaic tile with reflect-101 addressing; reflect-101 preserves
    // parity, so phase can be taken from the (possibly negative) virtual coord
    for (int idx = lin; idx < MT * MT; idx += NTHREADS) {
        int ly = idx / MT, lx = idx % MT;
        tgM[idx] = mosaic[mirror101(baseY + ly, H) * W + mirror101(baseX + lx, W)];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // layer 1: 4 one-hot phase planes -> 16 ch. plane_c(y,x) = m * [phase==c],
    // so the 4-channel conv collapses to one MAC per tap using the tap's phase.
    for (int p = lin; p < L1 * L1; p += NTHREADS) {
        int py = p / L1, px = p % L1;
        float acc[16];
        for (int o = 0; o < 16; ++o) acc[o] = 0.0f;
        for (int ky = 0; ky < 3; ++ky) {
            for (int kx = 0; kx < 3; ++kx) {
                int my = py + ky, mx = px + kx;
                float m = tgM[my * MT + mx];
                int ph = ((baseY + my) & 1) * 2 + ((baseX + mx) & 1);
                constant WT *wp = W1 + (ky * 3 + kx) * 4 + ph;   // + o*36
                for (int o = 0; o < 16; ++o) acc[o] += m * float(wp[o * 36]);
            }
        }
        for (int o = 0; o < 16; ++o) bufA[p * 16 + o] = lrelu(acc[o]);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // layer 2: 16 -> 16, bufA(L1) -> bufB(L2)
    for (int p = lin; p < L2 * L2; p += NTHREADS) {
        int py = p / L2, px = p % L2;
        float acc[16];
        for (int o = 0; o < 16; ++o) acc[o] = 0.0f;
        for (int ky = 0; ky < 3; ++ky) {
            for (int kx = 0; kx < 3; ++kx) {
                threadgroup const float *xin = bufA + ((py + ky) * L1 + (px + kx)) * 16;
                constant WT *wp = W2 + (ky * 3 + kx) * 16;       // + o*144 + i
                for (int i = 0; i < 16; ++i) {
                    float xv = xin[i];
                    for (int o = 0; o < 16; ++o) acc[o] += xv * float(wp[o * 144 + i]);
                }
            }
        }
        for (int o = 0; o < 16; ++o) bufB[p * 16 + o] = lrelu(acc[o]);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // layer 3: 16 -> 16, bufB(L2) -> bufA(L3) (layer-1 values are dead now)
    for (int p = lin; p < L3 * L3; p += NTHREADS) {
        int py = p / L3, px = p % L3;
        float acc[16];
        for (int o = 0; o < 16; ++o) acc[o] = 0.0f;
        for (int ky = 0; ky < 3; ++ky) {
            for (int kx = 0; kx < 3; ++kx) {
                threadgroup const float *xin = bufB + ((py + ky) * L2 + (px + kx)) * 16;
                constant WT *wp = W3 + (ky * 3 + kx) * 16;
                for (int i = 0; i < 16; ++i) {
                    float xv = xin[i];
                    for (int o = 0; o < 16; ++o) acc[o] += xv * float(wp[o * 144 + i]);
                }
            }
        }
        for (int o = 0; o < 16; ++o) bufA[p * 16 + o] = lrelu(acc[o]);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // layer 4 (16 -> 3, no activation) + MHC + passthrough + clamp, per own pixel
    const int gy = int(tgid.y) * TILE + tid.y;
    const int gx = int(tgid.x) * TILE + tid.x;
    if (gy >= H || gx >= W) return;

    float r0 = 0.0f, r1 = 0.0f, r2 = 0.0f;
    for (int ky = 0; ky < 3; ++ky) {
        for (int kx = 0; kx < 3; ++kx) {
            threadgroup const float *xin = bufA + ((tid.y + ky) * L3 + (tid.x + kx)) * 16;
            constant WT *wp = W4 + (ky * 3 + kx) * 16;
            for (int i = 0; i < 16; ++i) {
                float xv = xin[i];
                r0 += xv * float(wp[i]);
                r1 += xv * float(wp[144 + i]);
                r2 += xv * float(wp[288 + i]);
            }
        }
    }

    const int cy = tid.y + HALO, cx = tid.x + HALO;
    const float m = tgM[cy * MT + cx];
    const int ph = (gy & 1) * 2 + (gx & 1);

    float R, G, B;
    switch (ph) {
        case 0:  R = m;                  G = mhcG(tgM, cy, cx); B = mhcD(tgM, cy, cx);  break;
        case 1:  R = mhcA(tgM, cy, cx);  G = m;                 B = mhcAT(tgM, cy, cx); break;
        case 2:  R = mhcAT(tgM, cy, cx); G = m;                 B = mhcA(tgM, cy, cx);  break;
        default: R = mhcD(tgM, cy, cx);  G = mhcG(tgM, cy, cx); B = m;                  break;
    }
    R += r0; G += r1; B += r2;
    if (ph == 0) R = m; else if (ph == 3) B = m; else G = m;   // passthrough overrides residual

    device float *o = outRGB + (gy * W + gx) * 3;
    o[0] = clamp(R, 0.0f, 1.0f);
    o[1] = clamp(G, 0.0f, 1.0f);
    o[2] = clamp(B, 0.0f, 1.0f);
}

#define DEBAYER_KERNEL(NAME, WT, SUF)                                          \
kernel void NAME(device const float *mosaic  [[buffer(0)]],                    \
                 device float *outRGB        [[buffer(1)]],                    \
                 constant int2 &dims         [[buffer(2)]], /* (H, W) */       \
                 ushort2 tid  [[thread_position_in_threadgroup]],              \
                 ushort2 tgid [[threadgroup_position_in_grid]])                \
{                                                                              \
    threadgroup float tgM[MT * MT];                                            \
    threadgroup float bufA[L1 * L1 * 16];                                      \
    threadgroup float bufB[L2 * L2 * 16];                                      \
    debayer_impl<WT>(mosaic, outRGB, C1_##SUF, C2_##SUF, C3_##SUF, C4_##SUF,   \
                     dims.x, dims.y, tid, tgid, tgM, bufA, bufB);              \
}

DEBAYER_KERNEL(debayer_f32, float, F32)
DEBAYER_KERNEL(debayer_f16, half,  F16)
