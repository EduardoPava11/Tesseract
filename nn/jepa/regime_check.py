#!/usr/bin/env python3
"""Regime-coverage diagnostic: does a real capture's latent ring
produce autocorrelation regimes (r1, r2, r3) inside the synthetic
corpus cloud the head trained on?

Usage: python3 regime_check.py <capture.gif> [more.gif ...]

Reads ONLY the capture's embedded DYAD STATS provenance (the GIF
carries its own generator) and compares regimes against
corpus/trajectories.jsonl. Diagnostic only — no capture byte enters
any corpus (★NO-CAPTURE-TRAINING). NOTE: a capture's STATS lines
are the RAW ring only when its traced alpha=1 AND it predates the
jepaH slot-hold (post-JH4 captures trace the smoothed state); the
tool warns accordingly.

Findings 2026-08-12 (docs/jepah-device-findings-2026-08-12.md):
centroid dims densely covered; log-variance persistence sits past
the corpus's 99% r1 edge -> proposed JH5 alpha*-uniform corpus.
"""

import json
import sys
import numpy as np


def comments_of(path):
    b = open(path, "rb").read()
    pos = 13 + (3 * (2 << (b[10] & 7)) if b[10] >> 7 else 0)
    out = []
    while pos < len(b) and b[pos] != 0x3B:
        if b[pos] == 0x21:
            label = b[pos + 1]
            pos += 2
            chunks = []
            while b[pos] != 0:
                n = b[pos]
                chunks.append(b[pos + 1:pos + 1 + n])
                pos += 1 + n
            pos += 1
            if label == 0xFE:
                out.append(b"".join(chunks).decode("utf8", "replace"))
        elif b[pos] == 0x2C:
            if b[pos + 9] >> 7:
                pos += 3 * (2 << (b[pos + 9] & 7))
            pos += 10
            pos += 1  # LZW min code size
            while b[pos] != 0:
                pos += 1 + b[pos]
            pos += 1
        else:
            raise ValueError(f"unknown block 0x{b[pos]:02x}")
    return "\n".join(out)


def regimes_of_ring(y):
    mu = y.mean(0, keepdims=True)
    sd = y.std(0, keepdims=True) + 1e-12
    w = (y - mu) / sd
    return np.stack([(w * np.roll(w, -l, axis=0)).mean(0)
                     for l in (1, 2, 3)], axis=1)


def ring_of_capture(path):
    text = comments_of(path)
    lines = text.splitlines()
    alpha = float([l for l in lines if l.startswith("DYAD MIXTURE")][0]
                  .split("alpha=")[1].split()[0])
    jepah = any(l.startswith("DYAD JEPAH") for l in lines)
    stats = [list(map(float, l.split()[:9])) for l in lines
             if l and (l[0].isdigit() or l[0] == '-')
             and len(l.split()) == 13]
    s = np.array(stats)
    eps = 1e-12
    lat = np.stack([s[:, 0], s[:, 1], s[:, 2],
                    np.log(np.maximum(s[:, 3], eps)),
                    np.log(np.maximum(s[:, 6], eps)),
                    np.log(np.maximum(s[:, 8], eps))], axis=1)
    slots = 16
    ring = lat.reshape(slots, len(lat) // slots, 6).mean(1)
    return ring, alpha, jepah


def main():
    caps = [json.loads(l) for l in open("corpus/trajectories.jsonl")]
    corp = np.concatenate(
        [regimes_of_ring(np.array(c["obs"])) for c in caps[::8]], axis=0)
    lo = np.percentile(corp, 1, axis=0)
    hi = np.percentile(corp, 99, axis=0)
    sub = corp[::7]
    self2 = ((sub[None] - sub[:, None]) ** 2).sum(-1)
    np.fill_diagonal(self2, np.inf)
    self_nn = float(np.median(np.sqrt(self2.min(1))))
    print(f"corpus cloud ({len(corp)} dim-samples): "
          f"r1 [{lo[0]:+.2f},{hi[0]:+.2f}] r2 [{lo[1]:+.2f},{hi[1]:+.2f}] "
          f"r3 [{lo[2]:+.2f},{hi[2]:+.2f}]  self-NN median {self_nn:.3f}")

    names = ["l", "a", "b", "logC00", "logC11", "logC22"]
    for path in sys.argv[1:]:
        ring, alpha, jepah = ring_of_capture(path)
        tag = path.split("/")[-1]
        note = "" if (alpha == 1 and not jepah) \
            else "  [WARN: traced state is smoothed, not raw]"
        print(f"\n{tag} (alpha={alpha:g}, jepah={jepah}){note}")
        R = regimes_of_ring(ring)
        for d in range(6):
            r = R[d]
            inside = all(lo[k] - 0.05 <= r[k] <= hi[k] + 0.05
                         for k in range(3))
            nn = float(np.sqrt(((corp - r) ** 2).sum(-1).min()))
            mark = "inside" if inside else "** OUTSIDE cloud **"
            print(f"  {names[d]:7s} r1={r[0]:+.3f} r2={r[1]:+.3f} "
                  f"r3={r[2]:+.3f}  NN={nn:.3f}  {mark}")


if __name__ == "__main__":
    main()
