# BAYER-RESIDUAL CONTRACT v1 — training report

Date: 2026-07-16. Trained with MLX 0.30.1 on Apple GPU (`/opt/homebrew/bin/python3 train.py`, seed 20260716, deterministic). Wall-clock: **51.9 s total, 50.4 s training** (60 epochs x 90 steps, batch 128).

## Operator

```
out = clamp01( passthrough( MHC(m) + f_theta(m) ) )
```

- `m`: RGGB Bayer mosaic, 1 channel, [0,1], sRGB-encoded. Phase: (0,0)=R, (0,1)=G1, (1,0)=G2, (1,1)=B.
- `MHC`: Malvar-He-Cutler 5x5 linear demosaic = bilinear `B(m)` + fixed linear cross-channel correction. So the operator is of the contract form `clamp01(B(m) + F(m))` with `F = (MHC − B) + f_theta`; the fixed part is a 5x5 linear tap that costs nothing in the kernel and contributes ~+5.3 dB of the gain on photos (digest finding 1).
- `f_theta`: 4 bias-free 3x3 convs, leaky-ReLU(1/16) between, last layer zero-initialised. **5,616 parameters** (<= 8,000). Receptive field **exactly 9x9** (contract limit; note the digest's packed quarter-res recommendation has an 18x18 full-res RF and therefore violates the contract — its residual-over-MHC and zero-init motifs were kept, the packing was not).
- `passthrough`: at every mosaic site the measured output channel is hard-set to the measured value (a masked select in the kernel).
- Padding: **reflect-101** (mirror about the edge pixel, `x[-k] := x[+k]`) — preserves CFA phase, so flat fields stay flat at borders. In Metal: mirrored addressing, *not* clamp-to-edge.

No normalization, no attention, no bias. Bias-free + leaky-ReLU makes `f_theta` positively 1-homogeneous, so BR4 holds *by construction*, and plain ReLU is avoided because it collapsed into the dead residual-=-0 optimum during training (observed; documented in train.py).

## Parameters

| layer | in→out | kernel | params |
|---|---|---|---|
| c1 | 4→16 | 3x3, no bias | 576 |
| c2 | 16→16 | 3x3, no bias | 2,304 |
| c3 | 16→16 | 3x3, no bias | 2,304 |
| c4 | 16→3 | 3x3, no bias, zero-init | 432 |
| **total** | | | **5,616** |

## Data

- Photos: 4 Photo Booth JPEGs (1440x960); 3 train / **1 held out entirely** (`Photo on 2025-03-07 at 1.27 PM.jpg`).
- Procedural (deterministic, 256²): flats, 2-color gradients, checkers (1–16 px), band-limited color noise, square-wave gratings (period 2–6 px, incl. diagonal), line/box/text edges. 64 train / 16 held out.
- 11,640 train / 2,000 eval patches (1,200 photo / 800 procedural), 32x32, crop offsets even (RGGB-preserving), standalone-mosaicked with mirror padding — identical to the shipped operator, no train/infer mismatch.
- Loss: per-patch log-MSE (`mean(log(mse_patch + 1e-8))`) — equal (up to affine) to negative mean per-patch PSNR, i.e. the BR5 metric. Plain L1 was tried first and lost ~2.6 dB on the gate metric: irreducible 1-px noise patches dominate L1 and the net dirties near-flat patches to appease them.
- Adam, cosine decay 1e-3 → 1e-4, 60 epochs. No exposure augmentation (pointless: the net is exactly homogeneous, scaling a sample only rescales its loss).

## PSNR (held-out, clamped full operator)

Primary metric: **mean per-patch CPSNR** (literature standard; per-patch MSE floored at 1e-10 = 100 dB cap, reached only by exact flats, identically for all methods). Pooled-MSE PSNR in parentheses (it is dominated by the few unreconstructable pixel-noise patches).

| method | all (2,000) | photo (1,200) | procedural (800) |
|---|---|---|---|
| bilinear (contract baseline) | 47.14 (30.18) | 44.65 (42.46) | 50.89 (26.36) |
| Malvar-He-Cutler | 49.71 (28.98) | 49.93 (48.58) | 49.38 (25.03) |
| **student FP32** | **50.86 (29.22)** | **53.05 (51.93)** | 47.58 (25.25) |
| student FP16 weights | 50.86 (29.22) | 53.05 (51.93) | 47.58 (25.25) |

- **BR5 gate: +3.72 dB over bilinear (needs >= +1.0) — PASS.**
- On natural photos the student is +8.40 dB over bilinear and +3.11 dB over MHC.
- On procedural the student sits between MHC and bilinear: most of that split is flats/gradients where bilinear is already near-exact (~100 dB) while any nonzero residual costs mean-per-patch dB, plus genuinely irreducible 1-px noise. The student repairs MHC's overshoot there (pooled 25.25 vs 25.03) but does not fully reach bilinear's smooth-guess advantage (26.36). Honest trade, dominated by the photo gain.
- FP16 weights are PSNR-neutral (<= 0.01 dB everywhere): FP16-friendly confirmed.

## Law checks (numerical, against the trained net via the numpy reference operator)

| law | statement | measured | tol | pass |
|---|---|---|---|---|
| BR1 | flat-field identity, 26 colors incl. extremes | max err 7.11e-3 | 1e-2 | PASS |
| BR2 | sample passthrough, 200 held-out patches | max err 0.0 (exact by construction) | 1e-2 | PASS |
| BR3 | bounded, 200 held-out patches | min 0.0, max 1.0 (hard clamp) | [0,1] | PASS |
| BR4 | exposure equivariance, a ∈ {0.5, 0.75, 1.0}, 100 patches | max err 2.38e-7 (homogeneous by construction; residual err = FP roundoff + clamp) | 3e-2 | PASS |
| BR5 | mean per-patch PSNR margin over bilinear | +3.72 dB | >= +1.0 dB | PASS |

numpy-reference vs MLX forward parity: max abs diff 5.96e-8 over 8 patches.

## Kernel-writer's spec (enough to hand-write the Metal kernel)

One compute kernel; per output pixel everything below reads the mosaic through a 9x9 window with **mirror (reflect-101) addressing** at image borders: coordinate `-k` maps to `+k`, `H-1+k` maps to `H-1-k`.

1. **Classical part** (5x5 taps, coefficients are /8-exact — fine in half):
   - Bilinear: G at R/B = 4-neighbor cross mean; R/B at G = 2-neighbor mean along the same-color row/column; R at B and B at R = 4-neighbor diagonal mean; measured channel = m.
   - MHC correction, Malvar ICASSP04 filters (x 1/8), applied to the raw mosaic:
     - `K_G` (G at R and at B): center 4; cross at ±1: 2; cross at ±2: −1.
     - `K_A` (R at G1, B at G2 — same-color neighbors horizontal): center 5; (0,±1): 4; (0,±2): −1; (±1,±1): −1; (±2,0): +0.5.
     - `K_A^T` (R at G2, B at G1 — same-color neighbors vertical).
     - `K_D` (R at B, B at R): center 6; diagonals (±1,±1): 2; cross at ±2: −1.5.
   - Composition per phase (RGGB): R = m·[R] + K_A[G1] + K_A^T[G2] + K_D[B]; G = m·[G1,G2] + K_G[R,B]; B = m·[B] + K_A^T[G1] + K_A[G2] + K_D[R].
2. **Residual net** — input is 4 full-res planes `p_c(y,x) = m(y,x) · [phase(y,x) == c]`, c ∈ {R, G1, G2, B} (phase from absolute pixel parity):
   ```
   x1 = lrelu( conv3x3(planes, W1) )   # 4  -> 16
   x2 = lrelu( conv3x3(x1,     W2) )   # 16 -> 16
   x3 = lrelu( conv3x3(x2,     W3) )   # 16 -> 16
   r  =        conv3x3(x3,     W4)     # 16 -> 3
   lrelu(v) = v > 0 ? v : v * 0.0625   # slope 1/16, FP16-exact
   ```
   Convs are *correlations* (no kernel flip), stride 1, no bias. Weight layout in `weights.npz` / `weights_fp16.npz` (keys `c1..c4`) is MLX `(O, kH, kW, I)`: `W[o][ky][kx][i]` multiplies input channel `i` at spatial offset `(ky−1, kx−1)` and accumulates into output channel `o`. FP16 storage + FP16 accumulation is safe at this depth (measured PSNR-neutral).
3. **Assemble**: `rgb = mhc + r`; then per channel `c`: if phase measured `c`, `rgb[c] = m`; then `rgb = clamp(rgb, 0, 1)`.

16 channels = 4 half4 accumulators per pixel; all weights (11.2 KB fp16) fit in a `constant` buffer; a 16x16 output tile needs a (16+8)² mosaic tile in threadgroup memory (halo 4 for the net; the classical 5x5 lives inside that halo).

## Parity targets

`golden.npz`: `names` [flat, checker2, natural, gradient_noise], `mosaics` (4,32,32) f32, `outputs` (4,32,32,3) f32 — exact FP32 outputs of the numpy reference operator (bit-exactly reproducible from `weights.npz`; verified 0.0 max abs on re-run), plus `ground_truth` for reference. The natural patch is a fixed crop of the held-out photo. A Metal implementation should match `outputs` to within FP16 accumulation noise (~1e-3); the FP32 reference path in `train.py` (`operator_np`) is the canonical arbiter.

## Files

- `train.py` — everything: data gen, classical demosaics, model, training, laws, artifacts. Single seed.
- `weights.npz` (FP32), `weights_fp16.npz` (FP16), `golden.npz`, `results.json`, `train_log.txt`.
