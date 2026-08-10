#!/usr/bin/env python3
"""Python port of the DYAD-256 solver, byte-gated on spec fixtures.

Op-for-op float64 port of spec/quantization/DyadPalette.hs sections
2-5 (the authoritative solver). Every arithmetic choice mirrors GHC:

  - cbrt as x ** (1/3)      (GHC (**) = C pow; np.cbrt differs in ulp)
  - round half-to-even      (Haskell `round` == Python `round`)
  - explicit left-to-right sums (never np.sum's pairwise reduction)
  - Jacobi pivot chosen by lexicographic (|a_ij|, i, j) max, 50 iters,
    1e-12 break, atan — identical tie semantics
  - sortOn (Down . fst) == stable sort by descending eigenvalue

GATE: `python3 dyad_solver.py` re-solves every fixture sample set and
compares the 768-byte table hex byte-for-byte. Any mismatch exits 1 —
and nothing downstream (the phase sweep's E_pal axis) may run on an
ungated solver. Regenerate fixtures after any solver change:
  cd spec && runghc -W -package-env=- quantization/EmitDyadFixtures.hs \
    > ../nn/phase/fixtures.json
"""

import json
import math
import os
import sys

LADDER = [1, 1, 2, 4, 8, 16, 32, 64]
N_LEVELS = 8
PRIMARY_COUNT = 128


# ── OKLab ─────────────────────────────────────────────────────────

def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def cbrt(x):
    return -((-x) ** (1 / 3)) if x < 0 else x ** (1 / 3)


def srgb8_to_oklab(rgb):
    r = srgb_to_linear(rgb[0] / 255)
    g = srgb_to_linear(rgb[1] / 255)
    b = srgb_to_linear(rgb[2] / 255)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l3, m3, s3 = cbrt(l), cbrt(m), cbrt(s)
    return (0.2104542553 * l3 + 0.7936177850 * m3 - 0.0040720468 * s3,
            1.9779984951 * l3 - 2.4285922050 * m3 + 0.4505937099 * s3,
            0.0259040371 * l3 + 0.7827717662 * m3 - 0.8086757660 * s3)


def oklab_to_linear(lab):
    ll, aa, bb = lab
    l3 = ll + 0.3963377774 * aa + 0.2158037573 * bb
    m3 = ll - 0.1055613458 * aa - 0.0638541728 * bb
    s3 = ll - 0.0894841775 * aa - 1.2914855480 * bb
    l, m, s = l3 ** 3, m3 ** 3, s3 ** 3
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)


def in_gamut(lab):
    return all(-1e-6 <= c <= 1 + 1e-6 for c in oklab_to_linear(lab))


def oklab_to_srgb8(lab):
    def to8(c):
        v = round(linear_to_srgb(max(0.0, min(1.0, c))) * 255)  # half-to-even
        return max(0, min(255, v))
    r, g, b = oklab_to_linear(lab)
    return (to8(r), to8(g), to8(b))


# ── comp + clamp ──────────────────────────────────────────────────

def comp(lab):
    return (lab[0], -lab[1], -lab[2])


def chroma_clamp(lab):
    if in_gamut(lab):
        return lab
    l, a, b = lab
    lo, hi = 0.0, 1.0
    for _ in range(40):
        mid = (lo + hi) / 2
        if in_gamut((l, a * mid, b * mid)):
            lo = mid
        else:
            hi = mid
    return (l, a * lo, b * lo)


def clamp_l(lab):
    return (max(0.0, min(1.0, lab[0])), lab[1], lab[2])


def complement_of(rgb):
    return oklab_to_srgb8(chroma_clamp(comp(srgb8_to_oklab(rgb))))


# ── statistics (incl. DY8 canonDir) ───────────────────────────────

def canon_dir(v):
    x, y, z = v
    if x > 1e-9:
        return v
    if x < -1e-9:
        return (-x, -y, -z)
    if y > 1e-9:
        return v
    if y < -1e-9:
        return (-x, -y, -z)
    return v if z >= 0 else (-x, -y, -z)


def jacobi3(mat):
    a = [row[:] for row in mat]
    v = [[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0]]
    for _ in range(50):
        mx, p, q = max((abs(a[i][j]), i, j) for i in range(3) for j in range(i + 1, 3))
        if mx < 1e-12:
            break
        if abs(a[p][p] - a[q][q]) < 1e-15:
            theta = math.pi / 4
        else:
            theta = 0.5 * math.atan(2 * a[p][q] / (a[p][p] - a[q][q]))
        sn, cs = math.sin(theta), math.cos(theta)
        app = cs * cs * a[p][p] + 2 * sn * cs * a[p][q] + sn * sn * a[q][q]
        aqq = sn * sn * a[p][p] - 2 * sn * cs * a[p][q] + cs * cs * a[q][q]
        na = [row[:] for row in a]
        na[p][p] = app
        na[q][q] = aqq
        na[p][q] = 0.0
        na[q][p] = 0.0
        for r in range(3):
            if r != p and r != q:
                arp = cs * a[r][p] + sn * a[r][q]
                arq = -sn * a[r][p] + cs * a[r][q]
                na[r][p] = arp
                na[p][r] = arp
                na[r][q] = arq
                na[q][r] = arq
        a = na
        nv = [row[:] for row in v]
        for r in range(3):
            nv[r][p] = cs * v[r][p] + sn * v[r][q]
            nv[r][q] = -sn * v[r][p] + cs * v[r][q]
        v = nv
    values = [a[0][0], a[1][1], a[2][2]]
    vectors = [(v[0][i], v[1][i], v[2][i]) for i in range(3)]
    return values, vectors


def mk_stats(centroid, cov):
    values, vectors = jacobi3(cov)
    order = sorted(range(3), key=lambda i: -values[i])   # stable desc
    pcs = [(canon_dir(vectors[i]), values[i]) for i in order]
    return centroid, cov, pcs


def analyze(samples):
    if not samples:
        return mk_stats((0.5, 0.0, 0.0), [[0.0] * 3 for _ in range(3)])
    labs = [srgb8_to_oklab(tuple(s)) for s in samples]
    n = float(len(labs))
    cl = ca = cb = 0.0
    for l, _, _ in labs:
        cl += l
    for _, a, _ in labs:
        ca += a
    for _, _, b in labs:
        cb += b
    centroid = (cl / n, ca / n, cb / n)
    devs = [[l - centroid[0], a - centroid[1], b - centroid[2]] for l, a, b in labs]
    cov = [[0.0] * 3 for _ in range(3)]
    for i in range(3):
        for j in range(3):
            acc = 0.0
            for d in devs:
                acc += d[i] * d[j]
            cov[i][j] = acc / n
    return mk_stats(centroid, cov)


def guarded_std(v):
    return max(1e-3, math.sqrt(max(0.0, v)))


# ── the solver ────────────────────────────────────────────────────

def rho(k):
    return 2 * k / (N_LEVELS - 1)


def shell_raw(stats, k):
    centroid, _, pcs = stats
    c1, c2, c3 = centroid
    (d1x, d1y, d1z), v1 = pcs[0]
    (d2x, d2y, d2z), v2 = pcs[1]
    g1, g2 = guarded_std(v1), guarded_std(v2)
    r = rho(k)
    n = LADDER[k]
    out = []
    for j in range(n):
        th = 2 * math.pi * j / n
        out.append((c1 + r * (math.cos(th) * g1 * d1x + math.sin(th) * g2 * d2x),
                    c2 + r * (math.cos(th) * g1 * d1y + math.sin(th) * g2 * d2y),
                    c3 + r * (math.cos(th) * g1 * d1z + math.sin(th) * g2 * d2z)))
    return out


def primaries(stats):
    out = []
    for k in range(N_LEVELS):
        for p in shell_raw(stats, k):
            out.append(oklab_to_srgb8(chroma_clamp(clamp_l(p))))
    return out


def build_dyad(samples):
    prims = primaries(analyze(samples))
    return prims + [complement_of(p) for p in reversed(prims)]


def table_hex(table):
    return "".join(f"{r:02x}{g:02x}{b:02x}" for r, g, b in table)


# ── the gate ──────────────────────────────────────────────────────

def gate(path=None):
    path = path or os.path.join(os.path.dirname(__file__), "fixtures.json")
    fixtures = json.load(open(path))["fixtures"]
    failures = 0
    for f in fixtures:
        got = table_hex(build_dyad(f["samples"]))
        want = f["table_hex"]
        if got == want:
            print(f"  OK   {f['name']}")
        else:
            failures += 1
            diff = next(i for i in range(len(want)) if got[i] != want[i]) // 6
            print(f"  FAIL {f['name']} first differing entry index {diff}")
    if failures:
        print(f"GATE FAILED: {failures}/{len(fixtures)} fixtures mismatch")
        return 1
    print(f"GATE PASSED: {len(fixtures)}/{len(fixtures)} tables byte-exact vs the Haskell spec")
    return 0


if __name__ == "__main__":
    sys.exit(gate())
