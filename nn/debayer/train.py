#!/usr/bin/env python3
"""
BAYER-RESIDUAL CONTRACT v1 -- tiny residual debayer, MLX prototype.

Operator (the thing a Metal kernel must reproduce, exactly):

    out = clamp01( passthrough( MHC(m) + f_theta(m) ) )

  m           RGGB Bayer mosaic, 1 channel, [0,1], sRGB-encoded, H x W.
  MHC(m)      Malvar-He-Cutler linear demosaic (5x5 filters) = bilinear B(m)
              plus a fixed linear cross-channel correction.  So the operator
              is of the contract form clamp01(B(m) + F(m)) with
              F = (MHC - B) + f_theta, the fixed part being a 5x5 linear tap.
  f_theta     4 bias-free 3x3 convs (4->16->16->16->3), ReLU between, last
              layer zero-initialised.  5,616 parameters.  Receptive field
              exactly 9x9 full-res pixels.  No normalisation, no attention.
  passthrough at every mosaic site the physically measured channel is set to
              the measured value (BR2 exact by construction).
  padding     all spatial ops read the mosaic through reflect-101 (mirror
              about the edge pixel) padding: position -k maps to +k.  This
              preserves CFA phase, so flat fields stay flat at borders.
              In Metal: mirrored addressing, NOT clamp-to-edge.

Laws:
  BR1 flat-field identity      (checked numerically, tol 1e-2)
  BR2 sample passthrough        (exact by construction, checked)
  BR3 bounded [0,1]             (hard clamp, checked)
  BR4 exposure equivariance     (bias-free ReLU net is 1-homogeneous, so
                                 exact up to clamping; checked, tol 3e-2)
  BR5 PSNR(student) - PSNR(bilinear) >= +1.0 dB on held-out data

Run:  /opt/homebrew/bin/python3 train.py            (full train + eval + laws)
      /opt/homebrew/bin/python3 train.py --epochs 2 (smoke test)

Deterministic: single seed drives numpy data gen, patch sampling and MLX init.
"""

import argparse
import glob
import json
import os
import time

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view
from PIL import Image, ImageDraw

import mlx.core as mx
import mlx.nn as nn
import mlx.optimizers as optim
from mlx.utils import tree_flatten

SEED = 20260716
PATCH = 32          # supervised patch size
HALO = 4            # net needs 4 px of context (four 3x3 valid convs)
CTX = PATCH + 2 * HALO   # 40
HERE = os.path.dirname(os.path.abspath(__file__))
PHOTO_DIR = os.path.expanduser("~/Pictures/Photo Booth Library/Pictures")

# ----------------------------------------------------------------------------
# CFA geometry (RGGB): (0,0)=R (0,1)=G1 (1,0)=G2 (1,1)=B
# ----------------------------------------------------------------------------

def bayer_masks(h, w):
    yy, xx = np.mgrid[0:h, 0:w]
    mR = ((yy % 2 == 0) & (xx % 2 == 0)).astype(np.float32)
    mG1 = ((yy % 2 == 0) & (xx % 2 == 1)).astype(np.float32)
    mG2 = ((yy % 2 == 1) & (xx % 2 == 0)).astype(np.float32)
    mB = ((yy % 2 == 1) & (xx % 2 == 1)).astype(np.float32)
    return mR, mG1, mG2, mB


def measured_mask3(h, w):
    """(h,w,3) indicator of which output channel was physically measured."""
    mR, mG1, mG2, mB = bayer_masks(h, w)
    return np.stack([mR, mG1 + mG2, mB], axis=-1)


def mosaic_from_rgb(img):
    """img (h,w,3) float32 -> mosaic (h,w) float32."""
    h, w, _ = img.shape
    pm3 = measured_mask3(h, w)
    return (img * pm3).sum(axis=-1).astype(np.float32)


# ----------------------------------------------------------------------------
# Classical demosaics (numpy reference; all correlations, filters symmetric)
# ----------------------------------------------------------------------------

def conv_valid(x, K):
    """x (...,H,W), K (kh,kw) -> valid correlation (...,H-kh+1,W-kw+1)."""
    win = sliding_window_view(x, K.shape, axis=(-2, -1))
    return np.einsum('...ij,ij->...', win, K.astype(np.float32),
                     optimize=True).astype(np.float32)


K_CROSS = np.array([[0, 1, 0], [1, 0, 1], [0, 1, 0]], np.float32) / 4
K_HORIZ = np.array([[0, 0, 0], [1, 0, 1], [0, 0, 0]], np.float32) / 2
K_VERT = K_HORIZ.T.copy()
K_DIAG = np.array([[1, 0, 1], [0, 0, 0], [1, 0, 1]], np.float32) / 4

# Malvar-He-Cutler 5x5 filters (coefficients x 1/8), ICASSP 2004 Fig. 2.
K_MHC_G = np.array([[0, 0, -1, 0, 0],
                    [0, 0, 2, 0, 0],
                    [-1, 2, 4, 2, -1],
                    [0, 0, 2, 0, 0],
                    [0, 0, -1, 0, 0]], np.float32) / 8
K_MHC_A = np.array([[0, 0, 0.5, 0, 0],          # R at G, same-colour row
                    [0, -1, 0, -1, 0],
                    [-1, 4, 5, 4, -1],
                    [0, -1, 0, -1, 0],
                    [0, 0, 0.5, 0, 0]], np.float32) / 8
K_MHC_AT = K_MHC_A.T.copy()                     # R at G, same-colour column
K_MHC_D = np.array([[0, 0, -1.5, 0, 0],         # R at B / B at R
                    [0, 2, 0, 2, 0],
                    [-1.5, 0, 6, 0, -1.5],
                    [0, 2, 0, 2, 0],
                    [0, 0, -1.5, 0, 0]], np.float32) / 8


def _compose(m, mR, mG1, mG2, mB, at_g1_r, at_g2_r, at_b_r,
             at_rb_g, at_g1_b, at_g2_b, at_r_b):
    r = m * mR + at_g1_r * mG1 + at_g2_r * mG2 + at_b_r * mB
    g = m * (mG1 + mG2) + at_rb_g * (mR + mB)
    b = m * mB + at_g1_b * mG1 + at_g2_b * mG2 + at_r_b * mR
    return np.stack([r, g, b], axis=-1).astype(np.float32)


def bilinear_from_padded(P, h, w):
    """P: mosaic mirror-padded by HALO (>=1). Returns (h,w,3) bilinear."""
    k = HALO
    m = P[k:k + h, k:k + w]
    mR, mG1, mG2, mB = bayer_masks(h, w)
    c = conv_valid(P, K_CROSS)[k - 1:k - 1 + h, k - 1:k - 1 + w]
    hh = conv_valid(P, K_HORIZ)[k - 1:k - 1 + h, k - 1:k - 1 + w]
    vv = conv_valid(P, K_VERT)[k - 1:k - 1 + h, k - 1:k - 1 + w]
    dd = conv_valid(P, K_DIAG)[k - 1:k - 1 + h, k - 1:k - 1 + w]
    return _compose(m, mR, mG1, mG2, mB,
                    at_g1_r=hh, at_g2_r=vv, at_b_r=dd,
                    at_rb_g=c,
                    at_g1_b=vv, at_g2_b=hh, at_r_b=dd)


def mhc_from_padded(P, h, w):
    """P: mosaic mirror-padded by HALO (>=2). Returns (h,w,3) Malvar-He-Cutler."""
    k = HALO
    m = P[k:k + h, k:k + w]
    mR, mG1, mG2, mB = bayer_masks(h, w)
    g = conv_valid(P, K_MHC_G)[k - 2:k - 2 + h, k - 2:k - 2 + w]
    a = conv_valid(P, K_MHC_A)[k - 2:k - 2 + h, k - 2:k - 2 + w]
    at = conv_valid(P, K_MHC_AT)[k - 2:k - 2 + h, k - 2:k - 2 + w]
    d = conv_valid(P, K_MHC_D)[k - 2:k - 2 + h, k - 2:k - 2 + w]
    return _compose(m, mR, mG1, mG2, mB,
                    at_g1_r=a, at_g2_r=at, at_b_r=d,
                    at_rb_g=g,
                    at_g1_b=at, at_g2_b=a, at_r_b=d)


def mirror_pad(m, k=HALO):
    return np.pad(m, k, mode='reflect')  # reflect-101: phase-preserving


# ----------------------------------------------------------------------------
# Numpy reference forward (canonical FP32 operator -> golden.npz)
# ----------------------------------------------------------------------------

LEAK = np.float32(0.0625)  # 1/16: FP16-exact, one multiply in Metal


def net_forward_np(weights, planes):
    """planes (H,W,4) -> residual (H-8,W-8,3). weights: list of (O,3,3,I)."""
    x = planes
    for i, w in enumerate(weights):
        win = sliding_window_view(x, (3, 3), axis=(0, 1))  # (H-2,W-2,C,3,3)
        x = np.einsum('yxcij,oijc->yxo', win, w, optimize=True).astype(np.float32)
        if i < len(weights) - 1:
            x = np.where(x > 0, x, LEAK * x).astype(np.float32)
    return x


def operator_np(weights, mosaic):
    """Full operator on a standalone mosaic (h,w). Returns clamped (h,w,3)."""
    h, w = mosaic.shape
    P = mirror_pad(mosaic.astype(np.float32))
    pmR, pmG1, pmG2, pmB = bayer_masks(h + 2 * HALO, w + 2 * HALO)
    planes = P[..., None] * np.stack([pmR, pmG1, pmG2, pmB], axis=-1)
    resid = net_forward_np(weights, planes.astype(np.float32))
    base = mhc_from_padded(P, h, w)
    out = base + resid
    pm3 = measured_mask3(h, w)
    meas3 = mosaic[..., None] * pm3
    out = out * (1.0 - pm3) + meas3
    return np.clip(out, 0.0, 1.0).astype(np.float32)


# ----------------------------------------------------------------------------
# Data: Photo Booth photos + procedural content
# ----------------------------------------------------------------------------

def load_photos():
    paths = sorted(glob.glob(os.path.join(PHOTO_DIR, '*.jpg')))
    imgs = []
    for p in paths:
        im = Image.open(p).convert('RGB')
        imgs.append(np.asarray(im, np.float32) / 255.0)
    return paths, imgs


def _pil_to_np(im):
    return np.asarray(im.convert('RGB'), np.float32) / 255.0


def gen_procedural(rng, n=80, S=256):
    """Deterministic list of (name, image). Covers flats, gradients, checkers,
    band-limited colour noise, hard gratings, text/edge content."""
    imgs = []
    for i in range(n):
        kind = i % 6
        if kind == 0:   # flat field
            c = rng.random(3).astype(np.float32)
            img = np.broadcast_to(c, (S, S, 3)).copy()
            name = 'flat'
        elif kind == 1:  # two-colour linear gradient, random direction
            c0, c1 = rng.random(3), rng.random(3)
            th = rng.random() * np.pi
            yy, xx = np.mgrid[0:S, 0:S] / (S - 1)
            t = (xx * np.cos(th) + yy * np.sin(th))
            t = (t - t.min()) / (t.max() - t.min())
            img = (c0 + t[..., None] * (c1 - c0)).astype(np.float32)
            name = 'gradient'
        elif kind == 2:  # checkerboard at several scales (incl. rare 1px worst case)
            s = int(rng.choice([1, 2, 3, 4, 8, 16],
                               p=[0.08, 0.24, 0.20, 0.20, 0.16, 0.12]))
            c0, c1 = rng.random(3), rng.random(3)
            yy, xx = np.mgrid[0:S, 0:S]
            pat = ((yy // s + xx // s) % 2)[..., None]
            img = (c0 * (1 - pat) + c1 * pat).astype(np.float32)
            name = f'checker{s}'
        elif kind == 3:  # band-limited colour noise (upsampled low-res noise);
            # s=1 (pure pixel noise) is unreconstructable under a CFA -- keep
            # it rare so it teaches fallback behaviour without dominating loss
            s = int(rng.choice([1, 2, 4, 8, 16],
                               p=[0.10, 0.30, 0.25, 0.20, 0.15]))
            low = (rng.random((S // s, S // s, 3)) * 255).astype(np.uint8)
            im = Image.fromarray(low).resize(
                (S, S), Image.NEAREST if s == 1 else Image.BILINEAR)
            img = _pil_to_np(im)
            name = f'noise{s}'
        elif kind == 4:  # square-wave gratings (moire stressor)
            p = int(rng.choice([2, 3, 4, 6]))
            c0, c1 = rng.random(3), rng.random(3)
            yy, xx = np.mgrid[0:S, 0:S]
            axis = rng.integers(3)
            u = xx if axis == 0 else (yy if axis == 1 else xx + yy)
            pat = ((u // p) % 2)[..., None]
            img = (c0 * (1 - pat) + c1 * pat).astype(np.float32)
            name = f'grating{p}'
        else:            # text-like edges: lines, boxes, glyphs
            bg = tuple((rng.random(3) * 255).astype(int))
            im = Image.new('RGB', (S, S), bg)
            dr = ImageDraw.Draw(im)
            for _ in range(24):
                col = tuple((rng.random(3) * 255).astype(int))
                x0, y0 = rng.integers(0, S, 2)
                x1, y1 = rng.integers(0, S, 2)
                shape = rng.integers(3)
                if shape == 0:
                    dr.line([int(x0), int(y0), int(x1), int(y1)],
                            fill=col, width=int(rng.integers(1, 4)))
                elif shape == 1:
                    dr.rectangle([min(x0, x1), min(y0, y1),
                                  max(x0, x1), max(y0, y1)], outline=col,
                                 width=int(rng.integers(1, 3)))
                else:
                    dr.text((int(x0), int(y0)), 'Ag5#kQ', fill=col)
            img = _pil_to_np(im)
            name = 'edges'
        imgs.append((name, np.clip(img, 0, 1).astype(np.float32)))
    return imgs


def sample_patches(rng, img, n):
    """n standalone PATCH x PATCH GT crops at even offsets (RGGB preserved)."""
    h, w, _ = img.shape
    out = np.empty((n, PATCH, PATCH, 3), np.float32)
    for i in range(n):
        iy = 2 * int(rng.integers(0, (h - PATCH) // 2 + 1))
        ix = 2 * int(rng.integers(0, (w - PATCH) // 2 + 1))
        out[i] = img[iy:iy + PATCH, ix:ix + PATCH]
    return out


def precompute(gts, chunk=512):
    """gts (N,32,32,3) -> P (N,40,40) mirror-padded mosaics, base (N,32,32,3)
    MHC, bil (N,32,32,3) bilinear."""
    N = gts.shape[0]
    P = np.empty((N, CTX, CTX), np.float32)
    base = np.empty((N, PATCH, PATCH, 3), np.float32)
    bil = np.empty((N, PATCH, PATCH, 3), np.float32)
    pm3 = measured_mask3(PATCH, PATCH)
    for i0 in range(0, N, chunk):
        g = gts[i0:i0 + chunk]
        m = (g * pm3).sum(axis=-1)
        Pc = np.pad(m, ((0, 0), (HALO, HALO), (HALO, HALO)), mode='reflect')
        P[i0:i0 + chunk] = Pc
        base[i0:i0 + chunk] = _batch_classical(Pc, mhc=True)
        bil[i0:i0 + chunk] = _batch_classical(Pc, mhc=False)
    return P, base, bil


def _batch_classical(Pc, mhc):
    """Pc (N,40,40) padded mosaics -> (N,32,32,3)."""
    n = Pc.shape[0]
    h = wdt = PATCH
    k = HALO
    m = Pc[:, k:k + h, k:k + wdt]
    mR, mG1, mG2, mB = bayer_masks(h, wdt)
    if mhc:
        g = conv_valid(Pc, K_MHC_G)[:, k - 2:k - 2 + h, k - 2:k - 2 + wdt]
        a = conv_valid(Pc, K_MHC_A)[:, k - 2:k - 2 + h, k - 2:k - 2 + wdt]
        at = conv_valid(Pc, K_MHC_AT)[:, k - 2:k - 2 + h, k - 2:k - 2 + wdt]
        d = conv_valid(Pc, K_MHC_D)[:, k - 2:k - 2 + h, k - 2:k - 2 + wdt]
        r = m * mR + a * mG1 + at * mG2 + d * mB
        gg = m * (mG1 + mG2) + g * (mR + mB)
        b = m * mB + at * mG1 + a * mG2 + d * mR
    else:
        c = conv_valid(Pc, K_CROSS)[:, k - 1:k - 1 + h, k - 1:k - 1 + wdt]
        hh = conv_valid(Pc, K_HORIZ)[:, k - 1:k - 1 + h, k - 1:k - 1 + wdt]
        vv = conv_valid(Pc, K_VERT)[:, k - 1:k - 1 + h, k - 1:k - 1 + wdt]
        dd = conv_valid(Pc, K_DIAG)[:, k - 1:k - 1 + h, k - 1:k - 1 + wdt]
        r = m * mR + hh * mG1 + vv * mG2 + dd * mB
        gg = m * (mG1 + mG2) + c * (mR + mB)
        b = m * mB + vv * mG1 + hh * mG2 + dd * mR
    return np.stack([r, gg, b], axis=-1).astype(np.float32)


# ----------------------------------------------------------------------------
# Model (MLX)
# ----------------------------------------------------------------------------

class ResidualNet(nn.Module):
    """4->16->16->16->3, 3x3 valid convs, no bias, leaky-ReLU(1/16) between,
    last layer zero-init. 5,616 params. Bias-free + leaky ReLU => the net is
    positively 1-homogeneous: f(a*m) = a*f(m) exactly for a >= 0 (BR4).
    Plain ReLU dies into the trivial residual=0 optimum here; the leak keeps
    gradient flowing and costs one extra multiply in the Metal kernel."""

    def __init__(self):
        super().__init__()
        self.c1 = nn.Conv2d(4, 16, 3, padding=0, bias=False)
        self.c2 = nn.Conv2d(16, 16, 3, padding=0, bias=False)
        self.c3 = nn.Conv2d(16, 16, 3, padding=0, bias=False)
        self.c4 = nn.Conv2d(16, 3, 3, padding=0, bias=False)

    def __call__(self, x):
        x = nn.leaky_relu(self.c1(x), float(LEAK))
        x = nn.leaky_relu(self.c2(x), float(LEAK))
        x = nn.leaky_relu(self.c3(x), float(LEAK))
        return self.c4(x)


def param_count(model):
    return sum(v.size for _, v in tree_flatten(model.parameters()))


def weights_list(model):
    """FP32 numpy weights in forward order, each (O,3,3,I) [MLX layout]."""
    return [np.array(model.c1.weight, copy=True).astype(np.float32),
            np.array(model.c2.weight, copy=True).astype(np.float32),
            np.array(model.c3.weight, copy=True).astype(np.float32),
            np.array(model.c4.weight, copy=True).astype(np.float32)]


# ----------------------------------------------------------------------------
# Training / eval
# ----------------------------------------------------------------------------

MSE_FLOOR = 1e-10  # caps per-patch PSNR at 100 dB (exact-flat patches)


def psnr_from_mse(mse):
    return float(10.0 * np.log10(1.0 / max(float(mse), MSE_FLOOR)))


def psnr_stats(per_patch_mse):
    """Primary metric: mean per-patch CPSNR (literature standard).
    Also reports pooled-MSE PSNR (dominated by the hardest patches)."""
    m = np.asarray(per_patch_mse, np.float64)
    return {'mean_patch_db': float(np.mean([psnr_from_mse(v) for v in m])),
            'pooled_db': psnr_from_mse(float(np.mean(m)))}


def evaluate_mlx(model, P, base, gt, pmask4_mx, pm3_mx, batch=512):
    """Per-patch MSE of the full clamped operator. Returns (N,) array."""
    N = P.shape[0]
    out_mse = np.empty(N, np.float64)
    for i0 in range(0, N, batch):
        Pb = mx.array(P[i0:i0 + batch])
        planes = Pb[..., None] * pmask4_mx
        r = model(planes)
        out = mx.array(base[i0:i0 + batch]) + r
        g = mx.array(gt[i0:i0 + batch])
        meas = g * pm3_mx
        out = out * (1 - pm3_mx) + meas
        out = mx.clip(out, 0.0, 1.0)
        d = out - g
        out_mse[i0:i0 + batch] = np.array(mx.mean(d * d, axis=(1, 2, 3)))
    return out_mse


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--epochs', type=int, default=60)
    ap.add_argument('--batch', type=int, default=128)
    ap.add_argument('--lr', type=float, default=1e-3)
    args = ap.parse_args()

    t_start = time.time()
    rng = np.random.default_rng(SEED)
    mx.random.seed(SEED)

    # ---- corpus -------------------------------------------------------------
    photo_paths, photos = load_photos()
    proc = gen_procedural(rng)
    perm = rng.permutation(len(proc))
    proc_train = [proc[i] for i in perm[:64]]
    proc_eval = [proc[i] for i in perm[64:]]
    # last photo (sorted order) held out entirely
    train_photos, eval_photos = photos[:-1], photos[-1:]
    print(f'photos: {len(train_photos)} train, {len(eval_photos)} held out '
          f'({os.path.basename(photo_paths[-1])})')
    print(f'procedural: {len(proc_train)} train, {len(proc_eval)} held out')

    train_gt = np.concatenate(
        [sample_patches(rng, im, 2600) for im in train_photos] +
        [sample_patches(rng, im, 60) for _, im in proc_train])
    eval_gt_photo = np.concatenate(
        [sample_patches(rng, im, 1200) for im in eval_photos])
    eval_gt_proc = np.concatenate(
        [sample_patches(rng, im, 50) for _, im in proc_eval])
    eval_gt = np.concatenate([eval_gt_photo, eval_gt_proc])
    n_eval_photo = eval_gt_photo.shape[0]
    print(f'patches: {train_gt.shape[0]} train, {eval_gt.shape[0]} eval '
          f'({n_eval_photo} photo / {eval_gt.shape[0] - n_eval_photo} procedural)')

    print('precomputing classical demosaics ...')
    trP, trBase, _ = precompute(train_gt)
    evP, evBase, evBil = precompute(eval_gt)

    # ---- classical baselines on held-out ------------------------------------
    def patch_mse(pred, gt):
        d = np.clip(pred, 0, 1) - gt
        return np.mean(d * d, axis=(1, 2, 3)).astype(np.float64)

    def split_stats(mse):
        return {'all': psnr_stats(mse),
                'photo': psnr_stats(mse[:n_eval_photo]),
                'proc': psnr_stats(mse[n_eval_photo:])}

    stats = {}
    mse_bil = patch_mse(evBil, eval_gt)
    mse_mhc = patch_mse(evBase, eval_gt)
    stats['bilinear'] = split_stats(mse_bil)
    stats['mhc'] = split_stats(mse_mhc)
    print(f"bilinear PSNR: {stats['bilinear']}")
    print(f"MHC      PSNR: {stats['mhc']}")
    # sanity: MHC must beat bilinear on natural photos (pooled 'all' can
    # invert: unreconstructable 1px procedural noise dominates pooled MSE
    # and punishes MHC's high-gain correction)
    assert (stats['mhc']['photo']['mean_patch_db'] >
            stats['bilinear']['photo']['mean_patch_db']), \
        'MHC must beat bilinear on photos'

    # ---- model --------------------------------------------------------------
    model = ResidualNet()
    model.c4.weight = mx.zeros_like(model.c4.weight)  # start == exact MHC
    mx.eval(model.parameters())
    n_params = param_count(model)
    print(f'params: {n_params}')
    assert n_params <= 8000

    pmask4_np = np.stack(bayer_masks(CTX, CTX), axis=-1)
    pmask4_mx = mx.array(pmask4_np)
    pm3_mx = mx.array(measured_mask3(PATCH, PATCH))

    LOSS_EPS = 1e-8  # 80 dB knee: below this a patch is "done", stop polishing

    def loss_fn(mdl, Pb, baseb, gtb):
        planes = Pb[..., None] * pmask4_mx
        r = mdl(planes)
        out = baseb + r
        meas = gtb * pm3_mx
        out = out * (1 - pm3_mx) + meas          # BR2 passthrough (masks grad)
        d = out - gtb                            # pre-clamp
        mse = mx.mean(d * d, axis=(1, 2, 3))
        # per-patch log-MSE == negative mean per-patch PSNR (the BR5 metric).
        # Plain L1/L2 lets irreducible hard patches dominate and lets the net
        # dirty near-flat patches; log-MSE weights each patch's dB equally.
        return mx.mean(mx.log(mse + LOSS_EPS))

    N = train_gt.shape[0]
    steps_per_epoch = N // args.batch
    total_steps = steps_per_epoch * args.epochs
    sched = optim.cosine_decay(args.lr, total_steps, 1e-4)
    opt = optim.Adam(learning_rate=sched)
    lvg = nn.value_and_grad(model, loss_fn)

    print(f'training: {args.epochs} epochs x {steps_per_epoch} steps, '
          f'batch {args.batch}')
    t_train = time.time()
    for ep in range(args.epochs):
        idx = rng.permutation(N)
        ep_loss = 0.0
        for s in range(steps_per_epoch):
            # NB: no exposure augmentation -- the bias-free net is exactly
            # 1-homogeneous, so scaling (P, base, gt) by a only rescales the
            # loss; it adds no information (BR4 holds by construction).
            b = idx[s * args.batch:(s + 1) * args.batch]
            Pb = mx.array(trP[b])
            baseb = mx.array(trBase[b])
            gtb = mx.array(train_gt[b])
            loss, grads = lvg(model, Pb, baseb, gtb)
            opt.update(model, grads)
            mx.eval(model.parameters(), opt.state)
            ep_loss += float(loss)
        if ep % 5 == 0 or ep == args.epochs - 1:
            mse = evaluate_mlx(model, evP, evBase, eval_gt, pmask4_mx, pm3_mx)
            st = psnr_stats(mse)
            wn = {k: float(mx.sqrt(mx.sum(v * v)))
                  for k, v in tree_flatten(model.parameters())}
            print(f'epoch {ep:3d}  logMSE {ep_loss / steps_per_epoch:+.4f}  '
                  f"eval {st['mean_patch_db']:.2f} dB/patch "
                  f"({st['pooled_db']:.2f} pooled)  |c4| {wn['c4.weight']:.4f}")
    train_secs = time.time() - t_train

    # ---- final eval (student fp32 + fp16 weights) ---------------------------
    W = weights_list(model)
    W16 = [w.astype(np.float16) for w in W]
    W16_32 = [w.astype(np.float32) for w in W16]

    def student_eval(weights):
        mdl = ResidualNet()
        mdl.c1.weight = mx.array(weights[0]); mdl.c2.weight = mx.array(weights[1])
        mdl.c3.weight = mx.array(weights[2]); mdl.c4.weight = mx.array(weights[3])
        mx.eval(mdl.parameters())
        return evaluate_mlx(mdl, evP, evBase, eval_gt, pmask4_mx, pm3_mx)

    stats['student'] = split_stats(student_eval(W))
    stats['student_fp16'] = split_stats(student_eval(W16_32))
    print(f"student  PSNR: {stats['student']}")
    print(f"stud16   PSNR: {stats['student_fp16']}")
    # BR5 gate: mean per-patch CPSNR on the full held-out set
    br5_margin = (stats['student']['all']['mean_patch_db'] -
                  stats['bilinear']['all']['mean_patch_db'])
    br5_pass = br5_margin >= 1.0

    # ---- numpy/MLX parity ----------------------------------------------------
    par_gt = eval_gt[:8]
    pm3 = measured_mask3(PATCH, PATCH)
    par_mos = (par_gt * pm3).sum(axis=-1)
    out_np = np.stack([operator_np(W, m) for m in par_mos])
    mdl = ResidualNet()
    mdl.c1.weight = mx.array(W[0]); mdl.c2.weight = mx.array(W[1])
    mdl.c3.weight = mx.array(W[2]); mdl.c4.weight = mx.array(W[3])
    mx.eval(mdl.parameters())
    Pb = mx.array(evP[:8])
    planes = Pb[..., None] * pmask4_mx
    out_mx = mx.array(evBase[:8]) + mdl(planes)
    meas = mx.array(par_gt) * pm3_mx
    out_mx = mx.clip(out_mx * (1 - pm3_mx) + meas, 0, 1)
    parity = float(np.max(np.abs(np.array(out_mx) - out_np)))
    print(f'numpy/MLX parity (max abs): {parity:.3e}')

    # ---- BR law checks (numpy reference operator) ----------------------------
    laws = {}
    lrng = np.random.default_rng(SEED + 1)

    # BR1 flat-field identity
    colors = np.concatenate([lrng.random((20, 3)).astype(np.float32),
                             [[0, 0, 0], [1, 1, 1], [1, 0, 0], [0, 1, 0],
                              [0, 0, 1], [0.5, 0.5, 0.5]]]).astype(np.float32)
    br1 = 0.0
    for c in colors:
        gt = np.broadcast_to(c, (PATCH, PATCH, 3)).astype(np.float32)
        out = operator_np(W, mosaic_from_rgb(gt))
        br1 = max(br1, float(np.max(np.abs(out - gt))))
    laws['BR1'] = {'max_err': br1, 'tol': 1e-2, 'pass': br1 <= 1e-2}

    # BR2 sample passthrough
    br2 = 0.0
    for gt in eval_gt[:200]:
        m = mosaic_from_rgb(gt)
        out = operator_np(W, m)
        br2 = max(br2, float(np.max(np.abs((out * pm3).sum(-1) - m))))
    laws['BR2'] = {'max_err': br2, 'tol': 1e-2, 'pass': br2 <= 1e-2}

    # BR3 bounded
    lo, hi = 1.0, 0.0
    for gt in eval_gt[:200]:
        out = operator_np(W, mosaic_from_rgb(gt))
        lo, hi = min(lo, float(out.min())), max(hi, float(out.max()))
    laws['BR3'] = {'min': lo, 'max': hi, 'pass': lo >= 0.0 and hi <= 1.0}

    # BR4 exposure equivariance
    br4 = 0.0
    for gt in eval_gt[:100]:
        m = mosaic_from_rgb(gt)
        f1 = operator_np(W, m)
        for a in (0.5, 0.75, 1.0):
            fa = operator_np(W, np.float32(a) * m)
            br4 = max(br4, float(np.max(np.abs(fa - a * f1))))
    laws['BR4'] = {'max_err': br4, 'tol': 3e-2, 'pass': br4 <= 3e-2}

    laws['BR5'] = {'margin_db': br5_margin, 'tol': 1.0, 'pass': bool(br5_pass)}
    for k, v in laws.items():
        print(k, v)

    # ---- artifacts ------------------------------------------------------------
    np.savez(os.path.join(HERE, 'weights.npz'),
             c1=W[0], c2=W[1], c3=W[2], c4=W[3])
    np.savez(os.path.join(HERE, 'weights_fp16.npz'),
             c1=W16[0], c2=W16[1], c3=W16[2], c4=W16[3])

    # golden: flat, checker, natural, gradient+noise -- exact FP32 outputs
    g_flat = np.broadcast_to(np.float32([0.7, 0.3, 0.2]),
                             (PATCH, PATCH, 3)).astype(np.float32)
    yy, xx = np.mgrid[0:PATCH, 0:PATCH]
    pat = (((yy // 2 + xx // 2) % 2)[..., None]).astype(np.float32)
    g_check = (np.float32([0.9, 0.8, 0.1]) * (1 - pat) +
               np.float32([0.1, 0.2, 0.7]) * pat).astype(np.float32)
    g_nat = eval_photos[0][480:480 + PATCH, 700:700 + PATCH].astype(np.float32)
    grng = np.random.default_rng(SEED + 2)
    t = (xx / (PATCH - 1)).astype(np.float32)[..., None]
    g_grad = np.clip(np.float32([0.1, 0.4, 0.8]) * (1 - t) +
                     np.float32([0.9, 0.6, 0.2]) * t +
                     (grng.standard_normal((PATCH, PATCH, 3)) * 0.05), 0, 1
                     ).astype(np.float32)
    names = ['flat', 'checker2', 'natural', 'gradient_noise']
    g_gts = np.stack([g_flat, g_check, g_nat, g_grad])
    g_mos = np.stack([mosaic_from_rgb(g) for g in g_gts])
    g_out = np.stack([operator_np(W, m) for m in g_mos])
    np.savez(os.path.join(HERE, 'golden.npz'),
             names=np.array(names), mosaics=g_mos, outputs=g_out,
             ground_truth=g_gts)

    wall = time.time() - t_start
    results = {'params': n_params, 'psnr': stats, 'laws': laws,
               'parity_np_mlx': parity, 'train_secs': train_secs,
               'wall_secs': wall, 'epochs': args.epochs,
               'train_patches': int(N), 'eval_patches': int(eval_gt.shape[0]),
               'held_out_photo': os.path.basename(photo_paths[-1])}
    with open(os.path.join(HERE, 'results.json'), 'w') as f:
        json.dump(results, f, indent=2)
    print(json.dumps(results, indent=2))
    print(f'wall-clock: {wall:.1f}s (train {train_secs:.1f}s)')


if __name__ == '__main__':
    main()
