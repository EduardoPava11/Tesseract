#!/bin/bash
# lint-grid.sh — the grid constitution, enforced (exit 1 fails the build).
# Ported from SixFour's lint discipline, trimmed to Tesseract's scope.
#
# Governed directories (migrated to the lattice):
#   Tesseract/App, Tesseract/Views/States, Tesseract/UI
# Not yet governed (migration TODO — extend GOVERNED as they convert):
#   Tesseract/Views/{FaceCaptureView,EliteMapView,CubeGIFView,
#                    GIFPlayerView,PaletteSwatchView}.swift
#
# Invariants:
#   LINT-PLACEMENT      .position(/.offset( only with // LINT-ALLOW-POSITION
#   LINT-SINGLE-LATTICE gifPx/subPt/cellPt declared ONLY in the two
#                       lattice files (sole owner of cell↔point math)
#   LINT-SINGLE-PITCH   numeric literals in .frame/.padding/spacing/
#                       minLength must go through Lattice.gif/pt (0 allowed)

set -u
cd "$(dirname "$0")/.."

GOVERNED="Tesseract/App Tesseract/Views/States Tesseract/UI"
FAIL=0

note() { echo "  ✗ $1"; FAIL=1; }

# ── LINT-PLACEMENT ──────────────────────────────────────────────
while IFS= read -r line; do
  echo "$line" | grep -q "LINT-ALLOW-POSITION" && continue
  note "LINT-PLACEMENT: hand positioning without LINT-ALLOW-POSITION:"
  echo "      $line"
done < <(grep -rn "\.position(\|\.offset(" $GOVERNED --include="*.swift" || true)

# ── LINT-SINGLE-LATTICE ─────────────────────────────────────────
while IFS= read -r line; do
  case "$line" in
    */UI/Lattice/TesseractLattice.swift:*|*/UI/Lattice/Lattice.swift:*) continue ;;
  esac
  note "LINT-SINGLE-LATTICE: lattice constant declared outside the lattice:"
  echo "      $line"
done < <(grep -rn "static let \(gifPx\|subPt\|cellPt\)" $GOVERNED --include="*.swift" || true)

# ── LINT-SINGLE-PITCH ───────────────────────────────────────────
# Any .frame/.padding/spacing:/minLength: line containing a bare number
# must reference Lattice.gif( or Lattice.pt( (or be a literal 0 /
# .infinity / a derived expression with no digit literal).
while IFS= read -r line; do
  code="${line#*:*:}"
  echo "$code" | grep -q "Lattice\.\(gif\|pt\)(" && continue
  # allow pure zeros and lines whose only digits are in comments
  stripped=$(echo "$code" | sed 's|//.*||')
  echo "$stripped" | grep -q "\.frame(\|\.padding(\|spacing:\|minLength:" || continue
  digits=$(echo "$stripped" | grep -o "[: (][0-9][0-9.]*" | grep -v "[: (]0[,)]*$" || true)
  [ -z "$digits" ] && continue
  note "LINT-SINGLE-PITCH: raw number in layout (use Lattice.gif/pt):"
  echo "      $line"
done < <(grep -rn "\.frame(\|\.padding(\|spacing:\|minLength:" $GOVERNED --include="*.swift" | grep "[0-9]" || true)

if [ $FAIL -eq 0 ]; then
  echo "  ✓ grid lint clean ($(echo $GOVERNED | wc -w | tr -d ' ') governed dirs)"
  exit 0
else
  echo ""
  echo "  Grid constitution violated. Sizes are atoms: Lattice.gif(n) / Lattice.pt(n)."
  exit 1
fi
