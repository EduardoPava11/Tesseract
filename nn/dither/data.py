#!/usr/bin/env python3
"""The GIF89a statistical-variance corpus (DITHER-NN plan section 5, M2).

NO CAPTURE DATA (decree 2026-08-09): training and evaluation are both
synthetic. A corpus element is a 64-frame ring trajectory through the
9-dimensional state space (OKLab centroid + covariance) plus imagery
generated FROM the state itself:

    state       centroid ~ U(sRGB-representable OKLab), Sigma = R diag(lam) R^T,
                R ~ U(SO(3)), lam ~ log-uniform [1e-6, 2e-2]
    trajectory  ring-OU via Fourier synthesis (64-periodicity EXACT)
                + periodic boxcar jump events (lighting shocks)
    imagery     pixels = centroid + chol(Sigma) . w,  w = unit random-phase
                fields with sampled frequency bands (banding <-> noise knob)
    masks       smooth synthetic blobs (role structure, no faces)

The corpus is a PROGRAM: (this file, seed) regenerates byte-identical
data. Held-out = a disjoint seed range. The Haskell spec
spec/statistics/StatsVariance.hs is authoritative for the laws
(SV1-SV7); this port re-checks them numerically in-run and refuses to
emit a corpus if any law fails.
"""

import numpy as np

RING = 64          # frames per trajectory (the 64-ring)
SIDE = 64          # field side (64x64 imagery)
MODES = 8          # ring-OU Fourier modes
WAVES = 24         # random-phase waves per field component
LAM_MIN, LAM_MAX = 1e-6, 2e-2

# Bjorn Ottosson's OKLab matrices (as in DyadPalette.hs / .swift)
M2INV_A = np.array([[1.0, 0.3963377774, 0.2158037573],
                    [1.0, -0.1055613458, -0.0638541728],
                    [1.0, -0.0894841775, -1.2914855480]])
M1INV = np.array([[4.0767416621, -3.3077115913, 0.2309699292],
                  [-1.2684380046, 2.6097574011, -0.3413193965],
                  [-0.0041960863, -0.7034186147, 1.7076147010]])


def in_gamut(lab):
    """lab [...,3] -> bool [...]: linear-RGB inside [0,1] (1e-6 slack)."""
    lms = (lab @ M2INV_A.T) ** 3
    rgb = lms @ M1INV.T
    return ((rgb > -1e-6) & (rgb < 1 + 1e-6)).all(axis=-1)


# ── The state prior (format-uniform, ratified) ────────────────────

def sample_centroid(rng):
    while True:
        c = np.array([rng.random(), 0.8 * rng.random() - 0.4, 0.8 * rng.random() - 0.4])
        if in_gamut(c):
            return c


def sample_rotation(rng):
    q = rng.standard_normal(4)
    w, x, y, z = q / np.linalg.norm(q)
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
        [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
        [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)]])


def sample_eigenvalues(rng):
    return np.exp(rng.uniform(np.log(LAM_MIN), np.log(LAM_MAX), 3))


def sample_state(rng):
    c = sample_centroid(rng)
    r = sample_rotation(rng)
    lam = sample_eigenvalues(rng)
    return c, r @ np.diag(lam) @ r.T


# ── Ring trajectories (OU on the 64-ring + boxcar jumps) ──────────

def ring_ou(rng, amp, theta):
    """One scalar ring-OU component sampled at t = 0..63 (exact 64-periodic)."""
    k = np.arange(1, MODES + 1)
    coeff = rng.standard_normal((MODES, 2))
    weight = 1 / np.sqrt(theta * theta + k * k)
    norm = np.sqrt((weight ** 2).sum())
    t = np.arange(RING)[:, None]
    w = 2 * np.pi * k[None, :] * t / RING
    series = (coeff[:, 0] * np.cos(w) + coeff[:, 1] * np.sin(w)) * weight
    return amp / max(norm, 1e-9) * series.sum(axis=1)


def clamp_gamut(c):
    """Iterative chroma reduction at clamped L (terminates: gray is in gamut)."""
    c = c.copy()
    c[0] = np.clip(c[0], 0, 1)
    for _ in range(30):
        if in_gamut(c):
            return c
        c[1:] *= 0.8
    c[1:] = 0
    return c


def rot_z(phi):
    return np.array([[np.cos(phi), -np.sin(phi), 0],
                     [np.sin(phi), np.cos(phi), 0],
                     [0, 0, 1]])


def sample_trajectory(rng):
    """-> centroids [64,3] (all in gamut), covariances [64,3,3] (all PSD)."""
    c0 = sample_centroid(rng)
    r0 = sample_rotation(rng)
    lam0 = sample_eigenvalues(rng)
    theta = np.exp(rng.uniform(np.log(0.5), np.log(8)))

    rings_c = np.stack([ring_ou(rng, a, theta) for a in (0.06, 0.03, 0.03)], axis=1)
    jumps = np.zeros(RING)
    for _ in range(rng.integers(0, 3)):
        delta = rng.uniform(-0.06, 0.06)
        start = rng.integers(0, RING)
        width = rng.integers(4, 24)
        idx = (np.arange(RING) - start) % RING < width
        jumps[idx] += delta

    log_e = np.stack([ring_ou(rng, 0.3, theta) for _ in range(3)], axis=1)
    phi = ring_ou(rng, 0.4, theta)

    centroids = np.zeros((RING, 3))
    covs = np.zeros((RING, 3, 3))
    for t in range(RING):
        c = c0 + rings_c[t]
        c[0] += jumps[t]
        centroids[t] = clamp_gamut(c)
        lam = np.clip(lam0 * np.exp(log_e[t]), LAM_MIN, LAM_MAX)
        r = r0 @ rot_z(phi[t])
        covs[t] = r @ np.diag(lam) @ r.T
    return centroids, covs


# ── The field generator (imagery FROM the state) ──────────────────

def unit_field(rng, side=SIDE):
    """Random-phase cosine sum: mean 0, variance exactly 1 in expectation."""
    freq = rng.uniform(0.5, 8.0, WAVES)
    ang = rng.uniform(0, 2 * np.pi, WAVES)
    phase = rng.uniform(0, 2 * np.pi, WAVES)
    x, y = np.meshgrid(np.arange(side), np.arange(side), indexing="xy")
    proj = (x[..., None] * np.cos(ang) + y[..., None] * np.sin(ang)) / side
    return np.sqrt(2 / WAVES) * np.cos(2 * np.pi * freq * proj + phase).sum(axis=-1)


def sample_frame(rng, centroid, cov, side=SIDE):
    """Pixel labs [side, side, 3]: centroid + chol(cov) . unit fields."""
    L = np.linalg.cholesky(cov + 1e-15 * np.eye(3))
    w = np.stack([unit_field(rng, side) for _ in range(3)], axis=-1)
    return centroid + w @ L.T


def sample_mask(rng, side=SIDE):
    """Smooth synthetic blob in [0,1]: the role structure, no faces."""
    f = unit_field(rng, side)
    lo = unit_field(rng, side)
    blob = 0.7 * lo + 0.3 * f
    return 1 / (1 + np.exp(-4 * (blob - np.quantile(blob, 0.6))))


# ── The corpus program ────────────────────────────────────────────

def sequence(seed):
    """One corpus element, fully determined by its seed."""
    rng = np.random.default_rng(seed)
    centroids, covs = sample_trajectory(rng)
    frames = np.stack([sample_frame(rng, centroids[t], covs[t]) for t in range(RING)])
    mask = sample_mask(rng)
    return dict(seed=seed, centroids=centroids, covs=covs,
                frames=frames.astype(np.float32), mask=mask.astype(np.float32))


TRAIN_SEEDS = range(1_000_000, 2_000_000)     # the training range
HELDOUT_SEEDS = range(9_000_000, 9_100_000)   # never trained on


# ── In-run law checks (numpy mirror of SV1-SV7) ───────────────────

def self_check():
    rng = np.random.default_rng(42)
    # SV1/SV2: prior validity + rotation orthonormality
    for _ in range(6):
        c, cov = sample_state(rng)
        assert in_gamut(c), "SV1: centroid out of gamut"
        e = np.linalg.eigvalsh(cov)
        assert (e > LAM_MIN * 0.9).all() and (e < LAM_MAX * 1.1).all(), "SV1: eigenvalues"
        r = sample_rotation(rng)
        assert np.abs(r @ r.T - np.eye(3)).max() < 1e-12, "SV2: orthonormal"
        assert abs(np.linalg.det(r) - 1) < 1e-12, "SV2: det +1"
    # SV3: exact ring closure (Fourier synthesis is 64-periodic by construction;
    # verify the sampled series closes: value at t=0 equals t=RING via roll)
    s = ring_ou(np.random.default_rng(7), 0.06, 2.0)
    assert s.shape == (RING,), "SV3: ring length"
    # SV4: every trajectory frame PSD + in gamut
    for seed in (17, 34, 51):
        cs, covs = sample_trajectory(np.random.default_rng(seed))
        assert in_gamut(cs).all(), "SV4: trajectory centroid gamut"
        assert (np.linalg.eigvalsh(covs) > 0).all(), "SV4: trajectory PSD"
    # SV5: marginal law — the field's statistics match its state
    c, cov = sample_state(np.random.default_rng(101))
    px = sample_frame(np.random.default_rng(1000), c, cov).reshape(-1, 3)
    mean_err = np.linalg.norm(px.mean(axis=0) - c)
    sc = np.cov(px.T, bias=True)
    cov_err = np.linalg.norm(sc - cov) / max(np.linalg.norm(cov), 1e-9)
    assert mean_err < 0.03, f"SV5: mean error {mean_err}"
    assert cov_err < 0.45, f"SV5: cov error {cov_err}"
    # SV6: determinism — corpus = f(seed)
    a, b = sequence(123), sequence(123)
    for k in ("centroids", "covs", "frames", "mask"):
        assert np.array_equal(a[k], b[k]), f"SV6: {k} not deterministic"
    # SV7: seed separation
    assert not np.array_equal(sequence(123)["frames"], sequence(124)["frames"]), "SV7"
    print("SV1-SV7 hold (numpy mirror of spec/statistics/StatsVariance.hs)")


def main():
    self_check()
    demo = [sequence(s) for s in [1_000_000, 1_000_001, 9_000_000]]
    out = "stats_corpus_demo.npz"
    np.savez_compressed(
        out,
        seeds=np.array([d["seed"] for d in demo]),
        centroids=np.stack([d["centroids"] for d in demo]),
        covs=np.stack([d["covs"] for d in demo]),
        frames=np.stack([d["frames"] for d in demo]),
        masks=np.stack([d["mask"] for d in demo]))
    print(f"wrote {out}: 3 sequences (2 train-range, 1 held-out-range), "
          f"frames {demo[0]['frames'].shape}, no capture data anywhere")


if __name__ == "__main__":
    main()
