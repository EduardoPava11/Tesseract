#!/usr/bin/env python3
"""JEPA-H (JH2): the ONE model — train on trajectory rings, promote
by BEAUTY gates only.

Pipeline (nn/jepa/README.md):
  corpus (Haskell law) -> whiten -> encoder + arc-mask JEPA pretext
  (EMA target) + state head -> beauty gates vs the oracle-gain EMA
  baseline -> weights for the JH3 fold.

The deployed hook this trains for: at SOLVING time the capture's
full 16-slot latent ring exists; the model re-smooths it before
tables are solved. Steadier ring -> less palette churn -> flatter
LZW residue. So the gates are:

  PARITY  python renderer byte-matches the Haskell-emitted tables
          (before any gate may use python-rendered tables)
  B3      churn(model tables)  <  churn(EMA tables)
  B1lab   LZW(model LCT stream) < LZW(EMA LCT stream)
  FID     state RMSE(model) < RMSE(EMA)  (fidelity guard: smoothing
          must track truth, not flatline)
  DET     deterministic under the seed

Baseline is the ORACLE-gain EMA: alpha*(q) per dim with the TRUE
sigma_q/sigma_e from the sampler -- stronger than the app's
estimated gain. Beating the oracle is the honest bar.
"""

import json
import math
import os
import numpy as np
import mlx.core as mx
import mlx.nn as nn
import mlx.optimizers as optim
from mlx.utils import tree_flatten, tree_map

RING, DIM = 16, 6
HALF_MEAN = math.sqrt(2.0 / math.pi)
HALF_VAR = 1.0 - 2.0 / math.pi

# ── Table renderer (mirrors the Haskell law; parity-gated) ───────

M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
               [0.2119034982, 0.6806995451, 0.1073969566],
               [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553,  0.7936177850, -0.0040720468],
               [1.9779984951, -2.4285922050,  0.4505937099],
               [0.0259040371,  0.7827717662, -0.8086757660]])
M1i = np.linalg.inv(M1)
M2i = np.linalg.inv(M2)
WADA_L = 0.6170482164370319
WADA_A = -1.3176036044137163
WADA_B = 0.7469411483195036

def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

def linear_to_srgb(c):
    return np.where(c <= 0.0031308, 12.92 * c, 1.055 * c ** (1 / 2.4) - 0.055)

def hs_cbrt(x):
    """Mirror of the Haskell cbrt: x ** (1/3) via pow, NOT the
    correctly-rounded np.cbrt — they differ by 1 ULP at rounding
    boundaries, and the parity bridge caught exactly that."""
    x = np.asarray(x, dtype=np.float64)
    return np.where(x < 0, -((-x) ** (1.0 / 3.0)), x ** (1.0 / 3.0))

def srgb8_to_oklab(rgb8):
    # EXPLICIT left-to-right dots mirroring the Haskell expressions —
    # numpy matmul's blocked summation order diverges by 1 ULP at
    # rounding boundaries (the parity bridge caught a byte at
    # x.50000... vs x.49999...).
    lin = srgb_to_linear(np.asarray(rgb8, dtype=np.float64) / 255.0)
    r, g, b = lin[..., 0], lin[..., 1], lin[..., 2]
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s_ = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l3, m3, s3 = hs_cbrt(l), hs_cbrt(m), hs_cbrt(s_)
    return np.stack([
        0.2104542553 * l3 + 0.7936177850 * m3 - 0.0040720468 * s3,
        1.9779984951 * l3 - 2.4285922050 * m3 + 0.4505937099 * s3,
        0.0259040371 * l3 + 0.7827717662 * m3 - 0.8086757660 * s3,
    ], axis=-1)

def oklab_to_linear(lab):
    lab = np.asarray(lab, dtype=np.float64)
    l, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    l3 = l + 0.3963377774 * a + 0.2158037573 * b
    m3 = l - 0.1055613458 * a - 0.0638541728 * b
    s3 = l - 0.0894841775 * a - 1.2914855480 * b
    ll = l3 * l3 * l3
    mm = m3 * m3 * m3
    ss = s3 * s3 * s3
    return np.stack([
        4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss,
        -1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss,
        -0.0041960863 * ll - 0.7034186147 * mm + 1.7076147010 * ss,
    ], axis=-1)

def in_gamut(lab):
    rgb = oklab_to_linear(lab)
    return np.all((rgb >= -1e-6) & (rgb <= 1 + 1e-6), axis=-1)

def chroma_clamp(lab):
    lab = np.array(lab, dtype=np.float64)
    ok = in_gamut(lab)
    if np.all(ok):
        return lab
    lo = np.zeros(len(lab)); hi = np.ones(len(lab))
    for _ in range(40):
        mid = (lo + hi) / 2
        test = lab.copy()
        test[:, 1] *= np.where(ok, 1, mid)
        test[:, 2] *= np.where(ok, 1, mid)
        good = in_gamut(test)
        lo = np.where(ok, lo, np.where(good, mid, lo))
        hi = np.where(ok, hi, np.where(good, hi, mid))
    out = lab.copy()
    out[:, 1] *= np.where(ok, 1, lo)
    out[:, 2] *= np.where(ok, 1, lo)
    return out

def oklab_to_srgb8(lab):
    lab = np.array(lab, dtype=np.float64)
    lab[:, 0] = np.clip(lab[:, 0], 0, 1)          # clampL
    lab = chroma_clamp(lab)
    lin = np.clip(oklab_to_linear(lab), 0, 1)
    # np.round is half-even, matching GHC `round`
    return np.clip(np.round(linear_to_srgb(lin) * 255), 0, 255).astype(int)

def tree_figures(state):
    """Analytic axis-aligned tree from (l,a,b, log-variances)."""
    mean = np.array(state[:3], dtype=np.float64)
    var = np.exp(np.array(state[3:], dtype=np.float64))
    def descend(m, v, depth):
        if depth == 0:
            return [m]
        a = int(np.argmax(v))
        off = math.sqrt(v[a]) * HALF_MEAN
        vv = v.copy(); vv[a] *= HALF_VAR
        lo = m.copy(); lo[a] -= off
        hi = m.copy(); hi[a] += off
        return descend(lo, vv, depth - 1) + descend(hi, vv, depth - 1)
    leaves = np.array(descend(mean, var, 7))
    return oklab_to_srgb8(leaves)

def ground_prior(cL, figs8):
    lab = srgb8_to_oklab(figs8)
    c = np.sqrt(lab[:, 1] ** 2 + lab[:, 2] ** 2)
    l2 = lab[:, 0] + (WADA_L - cL)
    with np.errstate(divide="ignore", invalid="ignore"):
        cg = np.minimum(c, np.exp(WADA_A + WADA_B * np.log(np.maximum(c, 1e-300))))
        s = np.where(c > 0, cg / np.maximum(c, 1e-300), 0.0)
    out = np.stack([l2, lab[:, 1] * s, lab[:, 2] * s], axis=1)
    return oklab_to_srgb8(out)

def render_table(state):
    figs = tree_figures(state)
    cL = srgb8_to_oklab(figs[0:1])[0, 0]
    grounds = ground_prior(cL, figs[::-1])
    return np.concatenate([figs, grounds], axis=0).reshape(-1)   # 768 ints

# ── Corpus ───────────────────────────────────────────────────────

def load(path="corpus/trajectories.jsonl"):
    caps = []
    with open(path) as f:
        for line in f:
            caps.append(json.loads(line))
    return caps

def parity_bridge(caps, n=6):
    total = ok = 0
    for c in caps[:n]:
        for t in range(RING):
            mine = render_table(np.array(c["states"][t]))
            ok += int(np.array_equal(mine, np.array(c["tables"][t])))
            total += 1
    print(f"  PARITY bridge: {ok}/{total} tables byte-exact vs Haskell")
    assert ok == total, "python renderer diverged from the law"

# ── Model ────────────────────────────────────────────────────────

D = 24

class Encoder(nn.Module):
    def __init__(self):
        super().__init__()
        self.a = nn.Linear(DIM, D)
        self.b = nn.Linear(D, D)
    def __call__(self, x):
        return self.b(nn.gelu(self.a(x)))

class Predictor(nn.Module):
    def __init__(self):
        super().__init__()
        self.a = nn.Linear(3 * D + 4, 48)
        self.b = nn.Linear(48, D)
    def __call__(self, x):
        return self.b(nn.gelu(self.a(x)))

class StateHead(nn.Module):
    """v7: a regime-conditioned SYMMETRIC RING FILTER — a structure
    that cannot memorize. Free MLPs on windows overfit (v4: val
    worse than raw obs) or drift back to it with capacity (v6).
    Here the head has NO slot-content parameters at all: a shared
    regime MLP maps each dim's (r1, r2, r3) ring autocorrelations
    to (a) a 5-tap symmetric positive kernel (softmax over 3
    logits, mirrored — a true smoother family containing identity
    and near-RTS interior behavior) and (b) a jump gate (trust raw
    where |y - midpoint(neighbors)| spikes: level shifts must snap,
    not smear). Generalization is structural: only the REGIME is
    learned, never the trajectory."""
    def __init__(self):
        super().__init__()
        self.r1 = nn.Linear(3, 16)
        self.r2 = nn.Linear(16, 5)   # 3 kernel logits + gate scale/bias

    def __call__(self, y, regime):
        # y [B,16,DIM], regime [B,DIM,3]
        B = y.shape[0]
        p = self.r2(nn.gelu(self.r1(regime)))          # [B,DIM,5]
        klog = p[..., :3]
        gs = nn.softplus(p[..., 3:4])                   # gate scale > 0
        gb = p[..., 4:5]
        a = mx.softmax(klog, axis=-1)                   # [B,DIM,3]
        a0, a1, a2 = a[..., 0], a[..., 1], a[..., 2]
        yp1 = ring_shift(y, 1); ym1 = ring_shift(y, -1)
        yp2 = ring_shift(y, 2); ym2 = ring_shift(y, -2)
        a0e = a0[:, None, :]; a1e = a1[:, None, :]; a2e = a2[:, None, :]
        smooth = (a0e * y + 0.5 * a1e * (yp1 + ym1)
                  + 0.5 * a2e * (yp2 + ym2))
        # jump gate: deviation from the neighbor midpoint
        d = mx.abs(y - 0.5 * (yp1 + ym1))
        g = mx.sigmoid(gs[:, None, :, 0] * d + gb[:, None, :, 0])
        return (1 - g) * smooth + g * y

class JepaH(nn.Module):
    def __init__(self):
        super().__init__()
        self.enc = Encoder()
        self.pred = Predictor()
        self.head = StateHead()

def ring_shift(x, k):
    return mx.concatenate([x[:, k:, :], x[:, :k, :]], axis=1)

def ring_autocorr(y, lag):
    """Per-dim circular autocorrelation of the whitened ring
    (whitened => lag-0 variance is 1, so this IS the correlation)."""
    return mx.mean(y * ring_shift(y, lag), axis=1)      # [B,DIM]

def regime_of(y):
    """Per-capture, per-dim (r1, r2, r3) — the local-level model's
    sufficient statistics for the smoothing weight."""
    return mx.stack([ring_autocorr(y, 1), ring_autocorr(y, 2),
                     ring_autocorr(y, 3)], axis=-1)     # [B,DIM,3]

def whiten_np(y):
    mu = y.mean(axis=0, keepdims=True)
    sd = y.std(axis=0, keepdims=True) + 1e-12
    return (y - mu) / sd, mu, sd

# ── Training ─────────────────────────────────────────────────────

VAR_W, COV_W = 0.1, 0.04     # VICReg-lite weights (reported)
EMA_TAU = 0.99

def main():
    caps = load()
    n = len(caps)
    split = n * 7 // 8
    print(f"corpus: {n} capture rings -> {split} train / {n - split} val")
    parity_bridge(caps)

    Yw, S_w, MUSD = [], [], []
    for c in caps:
        y = np.array(c["obs"]); s = np.array(c["states"])
        yw, mu, sd = whiten_np(y)
        Yw.append(yw); S_w.append((s - mu) / sd); MUSD.append((mu, sd))
    Yw = np.stack(Yw); S_w = np.stack(S_w)

    ytr = mx.array(Yw[:split].astype(np.float32))
    strn = mx.array(S_w[:split].astype(np.float32))

    mx.random.seed(64)
    model = JepaH()
    target_enc = Encoder()
    # target starts as a copy of the online encoder
    target_enc.update(tree_map(lambda p: p, model.enc.parameters()))
    n_params = sum(v.size for _, v in tree_flatten(model.parameters()))

    pos_oh = mx.eye(4)

    def loss_fn(m, arc_start):
        B = ytr.shape[0]
        emb = m.enc(ytr)                                # [B,16,D]
        masked = [(arc_start + i) % RING for i in range(4)]
        vis = [i for i in range(RING) if i not in masked]
        ctx = mx.mean(emb[:, vis, :], axis=1)           # [B,D]
        prev = emb[:, (arc_start - 1) % RING, :]
        nxt = emb[:, (arc_start + 4) % RING, :]
        tgt = target_enc(ytr)                           # EMA target
        l_jepa = 0.0
        for i, sl in enumerate(masked):
            pin = mx.concatenate(
                [ctx, prev, nxt, mx.broadcast_to(pos_oh[i][None], (B, 4))],
                axis=1)
            p = m.pred(pin)
            l_jepa = l_jepa + mx.mean((p - mx.stop_gradient(tgt[:, sl, :])) ** 2)
        l_jepa = l_jepa / 4
        shat = m.head(ytr, regime_of(ytr))
        l_state = mx.mean((shat - strn) ** 2)
        # VICReg-lite anti-collapse on online embeddings
        e = emb.reshape(-1, D)
        std = mx.sqrt(mx.var(e, axis=0) + 1e-6)
        l_var = mx.mean(nn.relu(1.0 - std))
        ec = e - mx.mean(e, axis=0, keepdims=True)
        cov = (ec.T @ ec) / e.shape[0]
        l_cov = (mx.sum(cov * cov) - mx.sum(mx.diag(cov) ** 2)) / D
        return 4.0 * l_state + l_jepa + VAR_W * l_var + COV_W * l_cov

    first = float(loss_fn(model, 0).item())
    mx.random.seed(64)
    m2 = JepaH()
    det = abs(float(loss_fn(m2, 0).item()) - first) < 1e-6

    sched = optim.cosine_decay(3e-3, 4000, 1e-4)
    opt = optim.AdamW(learning_rate=sched, weight_decay=1e-3)
    lg = nn.value_and_grad(model, loss_fn)
    for it in range(4000):
        l, grads = lg(model, (it % 4) * 4)              # arcs tile (JH2)
        opt.update(model, grads)
        # EMA target update
        target_enc.update(tree_map(
            lambda tp, op: EMA_TAU * tp + (1 - EMA_TAU) * op,
            target_enc.parameters(), model.enc.parameters()))
        mx.eval(model.parameters(), target_enc.parameters())
        if it % 300 == 0:
            print(f"  iter {it:4d}  loss {float(l.item()):.4f}")

    # ── Evaluation: beauty gates on val captures ──
    def alpha_star(q):
        return (-q + math.sqrt(q * q + 4 * q)) / 2

    def rts_smoother(y, sigq, sige):
        """Fixed-interval RTS smoother per dim — the linear-Gaussian
        optimum; printed as the reference bound, not a gate."""
        T_, D_ = y.shape
        out = np.zeros_like(y)
        for d in range(D_):
            q, r = sigq[d] ** 2, max(sige[d] ** 2, 1e-18)
            m = np.zeros(T_); P = np.zeros(T_)
            mp = np.zeros(T_); Pp = np.zeros(T_)
            m_, P_ = y[0, d], r
            m[0], P[0] = m_, P_
            mp[0], Pp[0] = m_, P_
            for t in range(1, T_):
                mpred, Ppred = m_, P_ + q
                mp[t], Pp[t] = mpred, Ppred
                K = Ppred / (Ppred + r)
                m_ = mpred + K * (y[t, d] - mpred)
                P_ = (1 - K) * Ppred
                m[t], P[t] = m_, P_
            ms, Ps = m[T_ - 1], P[T_ - 1]
            out[T_ - 1, d] = ms
            for t in range(T_ - 2, -1, -1):
                C = P[t] / Pp[t + 1]
                ms = m[t] + C * (ms - mp[t + 1])
                out[t, d] = ms
        return out

    def ema_filter(y, alphas):
        out = np.zeros_like(y)
        out[0] = y[0]
        for t in range(1, len(y)):
            out[t] = out[t - 1] + alphas * (y[t] - out[t - 1])
        return out

    def model_states(ci):
        yw = mx.array(Yw[ci][None].astype(np.float32))
        shat = np.array(model.head(yw, regime_of(yw)))[0]
        mu, sd = MUSD[ci]
        return shat * sd + mu

    def lzw_bytes(stream):
        # GIF-LZW cost of a byte stream (minCodeSize 8) — same coder
        # family as the wire; the palette-side bit meter.
        clear, end = 256, 257
        table = {}
        next_code, size = 258, 9
        bits = 0
        cur = -1
        def emit(n):
            nonlocal bits
            bits += n
        emit(size)  # clear
        for px in stream:
            if cur < 0:
                cur = px; continue
            key = (cur << 8) | px
            if key in table:
                cur = table[key]
            else:
                emit(size)
                if next_code <= 4095:
                    table[key] = next_code
                    next_code += 1
                    if next_code > (1 << size) and size < 12:
                        size += 1
                else:
                    emit(size)
                    table.clear(); next_code, size = 258, 9
                cur = px
        emit(size); emit(size)
        return (bits + 7) // 8

    def churn(tables):
        t = np.array(tables, dtype=np.int64)
        return float(np.mean(np.abs(t - np.roll(t, -1, axis=0))))

    # Fit the B5 calibration on the TRAIN split only: per dim, the
    # ratio of the true increment scale to the model's own.
    #
    # ★ DEFAULT OFF (2026-08-14). Measured: the calibration PASSES B5
    # (0.381 vs the baseline's 0.626) and FAILS B3 and FID — churn
    # rises above oracle-EMA by construction, and cumsum
    # reconstruction costs state RMSE (0.05602 → 0.07008). That is
    # not a bad fix, it is proof that B3 and B5 CANNOT both hold for
    # a smoother: B3 rewards less motion without bound, B5 requires
    # the motion to match truth. Which one governs is Daniel's
    # ruling, not a training choice. Set B5_CALIBRATE=1 to reproduce.
    CAL = None
    if os.environ.get("B5_CALIBRATE") == "1":
        num = np.zeros(DIM); den = np.zeros(DIM)
        for ci in range(split):
            st = np.array(caps[ci]["states"])
            sm = model_states(ci)
            num += np.sqrt(np.mean(np.diff(st, axis=0) ** 2, axis=0))
            den += np.sqrt(np.mean(np.diff(sm, axis=0) ** 2, axis=0))
        CAL = np.where(den > 1e-12, num / np.maximum(den, 1e-12), 1.0)
        print(f"  B5 calibration ON (train split, per dim): {CAL.round(3).tolist()}")

    res = {k: [] for k in ["churn_true", "churn_obs", "churn_ema",
                           "churn_model", "lzw_ema", "lzw_model",
                           "rmse_ema", "rmse_model", "rmse_rts"]}
    for ci in range(split, n):
        c = caps[ci]
        s = np.array(c["states"]); y = np.array(c["obs"])
        q = (np.array(c["sigq"]) / np.array(c["sige"])) ** 2
        al = np.array([alpha_star(max(qd, 1e-12)) for qd in q])
        s_ema = ema_filter(y, al)
        s_model = model_states(ci)
        # ── B5 REPAIR: variance-restoring calibration ──────────────
        # A smoother shrinks the state's slot-to-slot motion; the
        # optimal shrinkage for RMSE is not the honest one for an
        # EDIT app, where that motion IS the content. Rescale the
        # model's own increments so their scale matches the state
        # the sampler actually generates. One scalar per dim, fitted
        # ONCE on the training split (no test leakage), applied to
        # every capture: not a tuned constant but a moment match —
        # the same move DyadPalette's beta-compander makes on chroma.
        if CAL is not None:
            d = np.diff(s_model, axis=0) * CAL
            s_model = np.concatenate([s_model[:1],
                                      s_model[:1] + np.cumsum(d, axis=0)], axis=0)
        T = {k: [render_table(v[t]) for t in range(RING)]
             for k, v in [("true", s), ("obs", y),
                          ("ema", s_ema), ("model", s_model)]}
        res["churn_true"].append(churn(T["true"]))
        res["churn_obs"].append(churn(T["obs"]))
        res["churn_ema"].append(churn(T["ema"]))
        res["churn_model"].append(churn(T["model"]))
        res["lzw_ema"].append(lzw_bytes(np.array(T["ema"]).reshape(-1)))
        res["lzw_model"].append(lzw_bytes(np.array(T["model"]).reshape(-1)))
        res["rmse_ema"].append(float(np.sqrt(np.mean((s_ema - s) ** 2))))
        res["rmse_model"].append(float(np.sqrt(np.mean((s_model - s) ** 2))))
        s_rts = rts_smoother(y, np.array(c["sigq"]), np.array(c["sige"]))
        res["rmse_rts"].append(float(np.sqrt(np.mean((s_rts - s) ** 2))))

    avg = {k: float(np.mean(v)) for k, v in res.items()}
    b3 = avg["churn_model"] < avg["churn_ema"]
    b1 = avg["lzw_model"] < avg["lzw_ema"]
    fid = avg["rmse_model"] < avg["rmse_ema"]
    # B5 CHURN FIDELITY (added 2026-08-14). B3 rewards LESS churn
    # without bound, so a model that flattens the state entirely
    # scores best — and the app is an EDIT app, where the motion
    # being flattened is the thing the user came to shape. The
    # honest target is the TRUE churn, not zero: the model must land
    # CLOSER to truth than the baseline it replaces.
    d_model = abs(avg["churn_model"] - avg["churn_true"])
    d_ema = abs(avg["churn_ema"] - avg["churn_true"])
    b5 = d_model <= d_ema
    avg["churn_dist_model"] = d_model
    avg["churn_dist_ema"] = d_ema

    print()
    print(f"  churn  true {avg['churn_true']:.3f} | obs {avg['churn_obs']:.3f}"
          f" | EMA* {avg['churn_ema']:.3f} | model {avg['churn_model']:.3f}")
    print(f"  LZW(LCT stream)  EMA* {avg['lzw_ema']:.0f} B"
          f" | model {avg['lzw_model']:.0f} B")
    print(f"  state RMSE  EMA* {avg['rmse_ema']:.5f}"
          f" | model {avg['rmse_model']:.5f}"
          f" | RTS bound {avg['rmse_rts']:.5f}")
    print(f"  DET determinism: {'✓' if det else '✗'}")
    print(f"  B3  churn: model < oracle-EMA: {'✓' if b3 else '✗'}")
    print(f"  B1  LZW:   model < oracle-EMA: {'✓' if b1 else '✗'}")
    print(f"  FID rmse:  model < oracle-EMA: {'✓' if fid else '✗'}")
    print(f"  B5  churn fidelity |model−true| {d_model:.3f}"
          f" <= |EMA*−true| {d_ema:.3f}: {'✓' if b5 else '✗'}")
    print(f"  params REPORTED: {n_params}")

    flat = dict(tree_flatten(model.parameters()))
    np.savez("jepa_weights.npz", **{k: np.array(v) for k, v in flat.items()})
    json.dump(dict(avg=avg, gates=dict(DET=bool(det), B3=bool(b3),
                                       B1=bool(b1), FID=bool(fid),
                                       B5=bool(b5)),
                   params=int(n_params)),
              open("results.json", "w"), indent=2)
    print("  saved jepa_weights.npz + results.json")

if __name__ == "__main__":
    main()
