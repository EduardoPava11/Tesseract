#!/usr/bin/env python3
"""Phase-diagram sweep v1 (DITHER-NN plan + PhaseEnergy spec).

Builds the empirical picture of the ORDER <-> SUBJECT transition from
the format itself (no capture data):

MODE A — exact per-class physics: frames tiled by the Bayer canonical
of every coverage class k. Deterministic: phi = k/16 (PE7), m_st peaks
at 1 exactly at k=8 (PE8), wall density = the AF ground line (PE5).

MODE B — capture-analog profiles: synthetic depth ramps d(x) spanning
[0.40, 0.65] (all three regions coexist), role law v3 + bayer4 at the
SIDE level (sigma vs primary — by the PairPermutations decoupling
theorem these observables are palette-independent), ensemble over
seeds with ramp jitter. Measures the transition profile phi(d), the
fluctuation ridge Var_block(phi), block Binder cumulants U_L for
L in {4,8,16,32} (the pyramid trick), and block-phi bimodality depth
(the 'subject presence' scalar). Verdict: crossover vs sharpening,
ridge width vs the 0.15 depth band.

HONEST LIMIT (v1): the E_pal axis only bites through index-level
occupancy entropy, which needs the Python DYAD solver port (gated
byte-exact against spec fixtures) — milestone'd, not faked here.
Deterministic: same seeds -> byte-identical npz.
"""

import numpy as np

SIDE = 64
TAU, BLEED_W, BLEED_G = 0.6, 0.15, 0.5
BAYER = np.array([0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
                 ).reshape(4, 4)
BAYER_T = (BAYER + 0.5) / 16


def pull(d):
    t = np.clip((TAU - d) / BLEED_W, 0, 1) ** BLEED_G
    return np.where(d >= TAU, 0.0, t)


def side_field(depth):
    """Role law v3 at the side level: +1 primary, -1 sigma."""
    x, y = np.meshgrid(np.arange(SIDE), np.arange(SIDE), indexing="xy")
    bay = BAYER_T[y % 4, x % 4]
    t = pull(depth)
    face = depth > TAU
    far = (~face) & (t >= 1)
    band_sigma = (~face) & (~far) & (bay < t)
    sigma = far | band_sigma
    return np.where(sigma, -1, 1)


def observables(s):
    phi = (s < 0).mean()
    x, y = np.meshgrid(np.arange(SIDE), np.arange(SIDE), indexing="xy")
    m_st = abs((((-1) ** (x + y)) * s).mean())
    walls = (s[:, 1:] != s[:, :-1]).sum() + (s[1:, :] != s[:-1, :]).sum()
    return phi, m_st, walls / (2 * SIDE * (SIDE - 1))


def block_phi(s, L):
    b = (s < 0).reshape(SIDE // L, L, SIDE // L, L).mean(axis=(1, 3))
    return b.ravel()


def binder(phis):
    m = 2 * phis - 1
    m2 = (m ** 2).mean()
    m4 = (m ** 4).mean()
    return 1 - m4 / (3 * m2 ** 2) if m2 > 1e-12 else 0.0


def bimodality(phis, bins=8):
    h, _ = np.histogram(phis, bins=bins, range=(0, 1))
    h = h / max(1, h.sum())
    peaks = max(h[0], h[1]), max(h[-1], h[-2])
    valley = h[2:-2].min() if bins > 4 else h.min()
    lo = min(peaks)
    return float(np.log((lo + 1e-9) / (valley + 1e-9))) if lo > 0 else 0.0


def mode_a():
    print("MODE A — exact per-class physics (deterministic):")
    print("   k    phi     m_st    w(walls)")
    x, y = np.meshgrid(np.arange(SIDE), np.arange(SIDE), indexing="xy")
    rows = []
    for k in range(17):
        s = np.where(BAYER[y % 4, x % 4] < k, -1, 1)
        phi, m_st, w = observables(s)
        rows.append((k, phi, m_st, w))
        assert abs(phi - k / 16) < 1e-12, "PE7 broken"
        print(f"  {k:2d}  {phi:.4f}  {m_st:.4f}  {w:.4f}")
    assert rows[8][2] == 1.0, "PE8 broken (k=8 Neel)"
    return np.array(rows)


def mode_b(n_seeds=64):
    print("\nMODE B — depth-ramp ensemble (capture-analog):")
    rng = np.random.default_rng(2026_08_09)
    depth_bins = np.linspace(0.40, 0.65, 26)
    prof_phi = np.zeros(len(depth_bins) - 1)
    prof_var = np.zeros(len(depth_bins) - 1)
    counts = np.zeros(len(depth_bins) - 1)
    binders = {L: [] for L in (4, 8, 16, 32)}
    bimods = []
    for _ in range(n_seeds):
        off = rng.uniform(-0.02, 0.02)
        x, _ = np.meshgrid(np.arange(SIDE), np.arange(SIDE), indexing="xy")
        depth = 0.40 + off + (0.65 - 0.40) * x / (SIDE - 1)
        depth += rng.normal(0, 0.004, size=depth.shape)   # capture jitter
        s = side_field(depth)
        bphi4 = block_phi(s, 4)
        bd4 = depth.reshape(SIDE // 4, 4, SIDE // 4, 4).mean(axis=(1, 3)).ravel()
        idx = np.clip(np.digitize(bd4, depth_bins) - 1, 0, len(counts) - 1)
        for i, p in zip(idx, bphi4):
            prof_phi[i] += p
            prof_var[i] += p * p
            counts[i] += 1
        for L in binders:
            binders[L].append(binder(block_phi(s, L)))
        bimods.append(bimodality(bphi4))
    mean_phi = prof_phi / np.maximum(1, counts)
    var_phi = prof_var / np.maximum(1, counts) - mean_phi ** 2
    centers = (depth_bins[:-1] + depth_bins[1:]) / 2
    ridge = centers[np.argmax(var_phi)]
    half = var_phi.max() / 2
    above = centers[var_phi > half]
    width = above.max() - above.min() if len(above) else 0.0
    print(f"  fluctuation ridge at depth d = {ridge:.3f} "
          f"(band spans {TAU - BLEED_W:.2f}..{TAU:.2f})")
    print(f"  ridge FWHM = {width:.3f} depth units vs band width {BLEED_W}")
    ub = {L: float(np.mean(v)) for L, v in binders.items()}
    print("  block Binder U_L:", {L: round(v, 3) for L, v in ub.items()})
    spread = max(ub.values()) - min(ub.values())
    verdict = "CROSSOVER (no L-sharpening)" if spread < 0.15 else "SHARPENING"
    print(f"  verdict: {verdict}  (U_L spread {spread:.3f})")
    print(f"  subject-presence bimodality depth: mean {np.mean(bimods):.2f}")
    return dict(centers=centers, mean_phi=mean_phi, var_phi=var_phi,
                ridge=ridge, width=width, binder={str(L): v for L, v in ub.items()},
                bimodality=float(np.mean(bimods)), verdict=verdict)


def main():
    a = mode_a()
    b = mode_b()
    np.savez_compressed("phase_profile.npz", mode_a=a,
                        centers=b["centers"], mean_phi=b["mean_phi"],
                        var_phi=b["var_phi"])
    print(f"\nwrote phase_profile.npz — ridge {b['ridge']:.3f}, "
          f"width {b['width']:.3f}, verdict {b['verdict']}")
    print("NOTE v1: side-level only; the E_pal axis activates via index-level")
    print("entropy once the Python solver port lands (gated on spec fixtures).")


if __name__ == "__main__":
    main()
