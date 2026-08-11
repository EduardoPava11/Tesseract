#!/usr/bin/env python3
# derive.py — the Wada ground-law constants, from the dictionary itself.
#
# Source: Sanzo Wada, "A Dictionary of Colour Combinations" (配色総鑑,
# 1933-34), digitized as colors.json (159 colors, 348 combinations;
# via mattdesl/dictionary-of-colour-combinations, sRGB swatches).
#
# Measured facts (OKLab, all 1128 in-combination pairs, each pair
# ordered by chroma into FIGURE = more chromatic / GROUND = less):
#
#   hue     |Δh| is near-uniform on [0°,180°] — Wada does not
#           constrain the hue interval. The σ = hue+180° mirror of
#           DYAD-256 is therefore retained unchanged.
#   chroma  ln C_G = alphaC + betaC · ln C_S   (r = +0.30)
#   light   L_G is statistically independent of L_S (r = -0.03):
#           the ground's lightness is drawn about muG regardless of
#           the figure. Deterministic reading: shift the mirrored
#           ensemble so its center lands at muG, offsets preserved.
#
# Output: the three constants pinned in
#   spec/quantization/DyadPalette.hs   (wadaGroundL, wadaAlphaC, wadaBetaC)
# and their ports. Re-run:  python3 scripts/wada/derive.py
#
# NOTE (session 2026-08-11, ruling R2 — docs/phase-palette-design.md):
# these dictionary constants are the single-phase / no-evidence
# FALLBACK PRIOR only. The live table law fits the same functional
# family's three parameters per capture from the background class's
# own moments (DyadPalette.groundMoments; spec PhasePalette.hs §10,
# PP8). The identity cap (ground ≤ figure chroma) lives on the prior
# path alone — it is the dictionary's role law, not the scene's.

import json, math, os, statistics as st

HERE = os.path.dirname(os.path.abspath(__file__))
data = json.load(open(os.path.join(HERE, "colors.json")))


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def oklab(rgb):
    r, g, b = (srgb_to_linear(v / 255) for v in rgb)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = l ** (1 / 3), m ** (1 / 3), s ** (1 / 3)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


labs = [oklab(c["rgb"]) for c in data]
LC = [(L, math.hypot(a, b)) for L, a, b in labs]

combos = {}
for i, c in enumerate(data):
    for k in c["combinations"]:
        combos.setdefault(k, []).append(i)

pairs = []
for members in combos.values():
    for i in range(len(members)):
        for j in range(i + 1, len(members)):
            pairs.append((members[i], members[j]))

# Order each pair by chroma: S = figure (more chromatic), G = ground.
ordered = []
for a, b in pairs:
    (La, Ca), (Lb, Cb) = LC[a], LC[b]
    ordered.append(((La, Ca), (Lb, Cb)) if Ca >= Cb else ((Lb, Cb), (La, Ca)))

L_G = [g[0] for _, g in ordered]
lnC_S = [math.log(s[1]) for s, _ in ordered]
lnC_G = [math.log(g[1]) for _, g in ordered]

muG = st.mean(L_G)
betaC = st.covariance(lnC_S, lnC_G) / st.variance(lnC_S)
alphaC = st.mean(lnC_G) - betaC * st.mean(lnC_S)

print(f"pairs           = {len(ordered)}  (combinations: {len(combos)})")
print(f"wadaGroundL     = {muG!r}")
print(f"wadaAlphaC      = {alphaC!r}")
print(f"wadaBetaC       = {betaC!r}")
print(f"L correlation   = {st.correlation([s[0] for s, _ in ordered], L_G):+.4f}"
      "   (independence: the ensemble-shift reading)")
print(f"lnC correlation = {st.correlation(lnC_S, lnC_G):+.4f}")
print(f"identity-cap crossover C* = exp(alphaC/(1-betaC)) = "
      f"{math.exp(alphaC / (1 - betaC)):.6f}")
