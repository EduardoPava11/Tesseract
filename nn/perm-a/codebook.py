#!/usr/bin/env python3
"""PERM-A codebook: exhaustive enumeration of the binomial pair-tile universe.

The model's action space (DITHER-NN plan section 9d, spec
spec/quantization/PairPermutations.hs) is arrangements of 4x4 pair-tiles
within a coverage class k. The universe is 2^16 = 65,536 tiles — small
enough to ENUMERATE, not sample. This program measures all of it and
emits the per-class codebook the model will classify over:

  per class k:  D4 orbits, exact adjacency extremes (is Bayer truly
                optimal? — answered exhaustively), and a TEXTURE LADDER:
                for each achievable adjacency level, the max-D4-symmetry
                orbit (tie: lexicographically smallest canonical) —
                dispersed -> clustered, beauty-first at every rung.

Deterministic, no randomness at all. Output codebook.json is a derived
but load-bearing artifact (the model + runtime consume it): committed,
like the debayer golden vectors.
"""

import json
from collections import defaultdict

CELLS = 16
BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
LADDER_CAP = 16

# ── D4 as index permutations on row-major 4x4 ─────────────────────

def idx(x, y):
    return y * 4 + x

D4 = []
for f in (lambda x, y: (x, y), lambda x, y: (3 - y, x),
          lambda x, y: (3 - x, 3 - y), lambda x, y: (y, 3 - x),
          lambda x, y: (3 - x, y), lambda x, y: (x, 3 - y),
          lambda x, y: (y, x), lambda x, y: (3 - y, 3 - x)):
    D4.append([idx(*f(x, y)) for y in range(4) for x in range(4)])

NEIGHBOR_PAIRS = [(idx(x, y), idx((x + dx) % 4, (y + dy) % 4))
                  for y in range(4) for x in range(4)
                  for dx, dy in ((1, 0), (0, 1))]


def bit(t, i):
    return (t >> i) & 1


def apply_perm(p, t):
    out = 0
    for i in range(CELLS):
        if bit(t, p[i]):
            out |= 1 << i
    return out


def coverage(t):
    return bin(t).count("1")


def adjacency(t):
    return sum(1 for a, b in NEIGHBOR_PAIRS if bit(t, a) == bit(t, b))


def sym_order(t):
    return sum(1 for p in D4 if apply_perm(p, t) == t)


def canonical(t):
    return min(apply_perm(p, t) for p in D4)


def bayer_tile(k):
    t = 0
    for i, o in enumerate(BAYER):
        if o < k:
            t |= 1 << i
    return t


def main():
    # ── Enumerate everything once ────────────────────────────────
    orbits = defaultdict(dict)   # k -> canonical -> record
    class_counts = defaultdict(int)
    for t in range(1 << CELLS):
        k = coverage(t)
        class_counts[k] += 1
        c = canonical(t)
        rec = orbits[k].get(c)
        if rec is None:
            orbits[k][c] = {"mask": c, "adjacency": adjacency(c),
                            "sym": sym_order(c), "orbit": 1}
        else:
            rec["orbit"] += 1

    # PP1 mirror: class sizes are C(16, k)
    from math import comb
    for k in range(CELLS + 1):
        assert class_counts[k] == comb(CELLS, k), f"PP1 broken at k={k}"

    # ── Per class: extremes, Bayer verdict, texture ladder ───────
    codebook = {}
    print("  k  orbits  adj[min..max]  bayer  exhaustive-min?  ladder")
    print("  ── ──────  ────────────  ─────  ───────────────  ──────")
    for k in range(CELLS + 1):
        recs = list(orbits[k].values())
        amin = min(r["adjacency"] for r in recs)
        amax = max(r["adjacency"] for r in recs)
        bayer_adj = adjacency(bayer_tile(k))
        optimal = bayer_adj == amin

        by_adj = defaultdict(list)
        for r in recs:
            by_adj[r["adjacency"]].append(r)
        ladder = []
        for a in sorted(by_adj):
            best = max(by_adj[a], key=lambda r: (r["sym"], -r["mask"]))
            ladder.append(best)
        if len(ladder) > LADDER_CAP:
            step = (len(ladder) - 1) / (LADDER_CAP - 1)
            ladder = [ladder[round(i * step)] for i in range(LADDER_CAP)]

        codebook[str(k)] = ladder
        print(f"  {k:2d} {len(recs):6d}  [{amin:2d} .. {amax:2d}]     "
              f"{bayer_adj:3d}    {'YES' if optimal else 'NO '}            "
              f"{len(ladder)} rungs")

    with open("codebook.json", "w") as f:
        json.dump(codebook, f, indent=1)
    n_entries = sum(len(v) for v in codebook.values())
    print(f"\nwrote codebook.json: {n_entries} entries across 17 classes "
          f"(canonical masks; runtime expands D4 orbits)")

    # Checkerboard sanity (PP5 mirror): class 8 minimum is 0 and Bayer hits it.
    assert adjacency(bayer_tile(8)) == 0
    assert min(r["adjacency"] for r in orbits[8].values()) == 0
    print("PP1/PP5 mirrors hold; enumeration exhaustive (65,536 tiles).")


if __name__ == "__main__":
    main()
