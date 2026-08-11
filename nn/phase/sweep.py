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


def mode_c(n_scales=10, n_seeds=12):
    """The E_pal axis, on the GATED solver (dyad_solver.py, byte-exact
    vs the Haskell spec): for each eigenvalue scale, solve real tables,
    draw imagery FROM the state, assign face pixels by nearest primary,
    and measure index entropy s. Tests the temperature-like hypothesis
    (s monotone in E_pal) and locates the fade line E_pal* where the
    subject's disorder collapses toward the solid."""
    import dyad_solver as ds
    print("\nMODE C — the E_pal axis (gated solver; face-region entropy):")
    print("  lam_scale   E_var(mean)  s_face(mean±sd)  colors_used")
    rng = np.random.default_rng(2026_08_10)
    scales = np.exp(np.linspace(np.log(1e-6), np.log(2e-2), n_scales))
    rows = []
    for lam in scales:
        epals, ents, used = [], [], []
        for _ in range(n_seeds):
            # State at this scale: random rotation, eigenvalues ~ lam
            # with mild spread; centroid = a nuisance, sampled in-gamut.
            q = rng.standard_normal(4)
            q /= np.linalg.norm(q)
            w_, x_, y_, z_ = q
            R = np.array([
                [1 - 2 * (y_ * y_ + z_ * z_), 2 * (x_ * y_ - w_ * z_), 2 * (x_ * z_ + w_ * y_)],
                [2 * (x_ * y_ + w_ * z_), 1 - 2 * (x_ * x_ + z_ * z_), 2 * (y_ * z_ - w_ * x_)],
                [2 * (x_ * z_ - w_ * y_), 2 * (y_ * z_ + w_ * x_), 2 * 0 + 1 - 2 * (x_ * x_ + y_ * y_)]])
            lams = lam * np.exp(rng.uniform(-0.5, 0.5, 3))
            cov = R @ np.diag(lams) @ R.T
            while True:
                c = np.array([rng.uniform(0.25, 0.75),
                              rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15)])
                if ds.in_gamut(tuple(c)):
                    break
            # Real table via the byte-gated solver path (stats direct).
            stats = ds.mk_stats(tuple(c), cov.tolist())
            prims = ds.primaries(stats)
            table = prims + [ds.ground_of(ds.centroid_l(prims), p) for p in reversed(prims)]
            # Temperature-like variable: the PRE-CLAMP closed-form
            # variance component of E_pal (PhaseEnergy PE1), exact in
            # the stats — immune to the clamp-loss and u8 noise (~±0.4)
            # that swamps a table-derived E_var at small eigenvalues.
            epals.append(_epal_var_state(ds, stats))
            # Imagery FROM the state (SV5 field), assigned to primaries.
            L = np.linalg.cholesky(cov + 1e-15 * np.eye(3))
            wf = np.stack([_unit_field(rng) for _ in range(3)], axis=-1)
            labs = (c + wf @ L.T).reshape(-1, 3)
            plabs = np.array([ds.srgb8_to_oklab(p) for p in prims])
            d2 = ((labs[:, None, :] - plabs[None, :, :]) ** 2).sum(-1)
            idx = d2.argmin(axis=1)
            counts = np.bincount(idx, minlength=128).astype(float)
            p = counts[counts > 0] / counts.sum()
            ents.append(float(-(p * np.log(p)).sum() / np.log(256)))
            used.append(int((counts > 0).sum()))
        rows.append((lam, float(np.mean(epals)), float(np.mean(ents)),
                     float(np.std(ents)), float(np.mean(used))))
        print(f"  {lam:9.2e}  {rows[-1][1]:10.4f}  {rows[-1][2]:.3f}±{rows[-1][3]:.3f}"
              f"      {rows[-1][4]:6.1f}")
    # Sort by the temperature-like variable itself, then test.
    by_evar = sorted(rows, key=lambda r: r[1])
    s = [r[2] for r in by_evar]
    monotone = all(s[i] <= s[i + 1] + 0.02 for i in range(len(s) - 1))
    print(f"  temperature-like (s rises with the closed-form variance"
          f" energy): {'CONFIRMED' if monotone else 'VIOLATED'}")
    print(f"  s_face spans {min(s):.3f} → {max(s):.3f}: matched-palette"
          f" disorder never fully dies (floor = the state's own colors)")
    return np.array(rows), monotone


def _epal_var_state(ds, stats):
    """Pre-clamp variance component of E_pal (PE1 closed form minus the
    256·|mu_ab|² centroid term), exact in the 9-number state."""
    c, _, pcs = stats
    d1, v1 = pcs[0]
    d2, v2 = pcs[1]
    g1, g2 = ds.guarded_std(v1), ds.guarded_std(v2)
    p1 = d1[1] * d1[1] + d1[2] * d1[2]
    p2 = d2[1] * d2[1] + d2[2] * d2[2]
    cross = c[1] * d1[1] + c[2] * d1[2]
    half = 0.0
    for k, n in enumerate(ds.LADDER):
        r = ds.rho(k)
        if n == 1 and k == 0:
            continue
        if n == 1:
            half += 2 * r * g1 * cross + r * r * g1 * g1 * p1
        elif n == 2:
            half += 2 * r * r * g1 * g1 * p1
        else:
            half += n * r * r / 2 * (g1 * g1 * p1 + g2 * g2 * p2)
    return 2 * half


def _unit_field(rng, side=SIDE, waves=24):
    freq = rng.uniform(0.5, 8.0, waves)
    ang = rng.uniform(0, 2 * np.pi, waves)
    phase = rng.uniform(0, 2 * np.pi, waves)
    x, y = np.meshgrid(np.arange(side), np.arange(side), indexing="xy")
    proj = (x[..., None] * np.cos(ang) + y[..., None] * np.sin(ang)) / side
    return np.sqrt(2 / waves) * np.cos(2 * np.pi * freq * proj + phase).sum(axis=-1)


def main():
    a = mode_a()
    b = mode_b()
    c_rows, c_monotone = mode_c()
    np.savez_compressed("phase_profile.npz", mode_a=a,
                        centers=b["centers"], mean_phi=b["mean_phi"],
                        var_phi=b["var_phi"], mode_c=c_rows)
    print(f"\nwrote phase_profile.npz — ridge {b['ridge']:.3f}, "
          f"width {b['width']:.3f}, verdict {b['verdict']}, "
          f"E_pal axis {'temperature-like' if c_monotone else 'NOT monotone'}")


if __name__ == "__main__":
    main()
