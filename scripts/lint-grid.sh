#!/bin/bash
# lint-grid.sh — the grid constitution, enforced (exit 1 fails the build).
# Ported from SixFour's lint discipline, trimmed to Tesseract's scope.
#
# Governed directories (migrated to the lattice):
#   Tesseract/App, Tesseract/Views/States, Tesseract/UI,
#   Tesseract/Views/PaletteSwatchView.swift
# (GIFPlayerView is a primitive; CubeGIFView + FaceCaptureView were
#  deleted in the S3 pass — every surviving view is governed.)
#
# Invariants:
#   LINT-PLACEMENT      .position(/.offset( only with // LINT-ALLOW-POSITION
#   LINT-SINGLE-LATTICE gifPx/subPt/cellPt declared ONLY in the two
#                       lattice files (sole owner of cell↔point math)
#   LINT-SINGLE-PITCH   numeric literals in .frame/.padding/spacing/
#                       minLength must go through Lattice.gif/pt (0 allowed)
#   LINT-GOLDEN-MECHANICS  the control-face algebra exists in BOTH forms
#                       (spec/ui/CellMechanics.hs + UI/Cells/CellMechanics.swift)
#
# Primitive allowlist: the cell-vocabulary files (UI/Cells/Cell*.swift,
# PixelGrid, SurfaceClock, Ink) plus GIFPlayerView are the ONLY files
# allowed raw drawing vocabulary — future LINT-DRAW-VOCAB exempts them.

set -u
cd "$(dirname "$0")/.."

GOVERNED="Tesseract/App Tesseract/Views Tesseract/UI"
FAIL=0

# Files converted to the cell vocabulary: raw drawing vocab is banned
# (opacity, materials, shapes, strokes, shadows, bare Text, spinners).
# Grows as views convert; primitives (is_primitive) are exempt.
GOVERNED_VOCAB="
Tesseract/App/ContentView.swift
Tesseract/App/TesseractApp.swift
Tesseract/Views/States/IdleStateView.swift
Tesseract/Views/States/RecordingStateView.swift
Tesseract/Views/States/ProcessingStateView.swift
Tesseract/Views/States/ErrorStateView.swift
Tesseract/Views/States/ResultStateView.swift
Tesseract/Views/States/LivePreviewStateView.swift
Tesseract/Views/States/DualExploreStateView.swift
Tesseract/Views/States/DualExplorePanels.swift
Tesseract/Views/States/RefiningStateView.swift
Tesseract/Views/States/FacePreviewStateView.swift
Tesseract/Views/States/BirkhoffGauge.swift
Tesseract/Views/PaletteSwatchView.swift
Tesseract/Views/EliteMapView.swift
"

note() { echo "  ✗ $1"; FAIL=1; }

# The closed drawing-vocabulary layer.
is_primitive() {
  case "$1" in
    */UI/Cells/Cell*.swift|*/UI/Cells/PixelGrid.swift|*/UI/Cells/SurfaceClock.swift|*/UI/Cells/Ink.swift|*/Views/GIFPlayerView.swift)
      return 0 ;;
    *) return 1 ;;
  esac
}

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

# ── LINT-DRAW-VOCAB ─────────────────────────────────────────────
# Converted views draw ONLY through the cell vocabulary: no alpha, no
# glass, no AA shapes, no bare Text, no stock spinners. `.opacity(0)`
# (pure passthrough) is allowed.
for f in $GOVERNED_VOCAB; do
  [ -f "$f" ] || continue
  while IFS= read -r line; do
    code=$(echo "${line#*:}" | sed 's|//.*||')
    echo "$code" | grep -q "\.opacity(0)" && continue
    echo "$code" | grep -q "\.opacity(\|ultraThinMaterial\|glassEffect\|RoundedRectangle\|Circle()\|\.stroke(\|\.shadow(\|ProgressView\|[^l]Text(" || continue
    note "LINT-DRAW-VOCAB: raw drawing vocab in converted view (use Cell*):"
    echo "      $f:$line"
  done < <(grep -n "\.opacity(\|ultraThinMaterial\|glassEffect\|RoundedRectangle\|Circle()\|\.stroke(\|\.shadow(\|ProgressView\|Text(" "$f" || true)
done

# ── LINT-CONTROL-FACE ───────────────────────────────────────────
# Every interactive region declared in GridLayout must name a face
# (frame|brackets) in CellMechanics.controlFaces (lawControlFaceTotal).
while IFS= read -r name; do
  grep -q "\"$name\": \"" Tesseract/UI/Cells/CellMechanics.swift \
    || note "LINT-CONTROL-FACE: interactive region '$name' has no entry in CellMechanics.controlFaces"
done < <(grep "interactive: true" Tesseract/UI/Lattice/GridLayout.swift \
         | sed -n 's/.*GridRegion("\([^"]*\)".*/\1/p' | sort -u)

# ── LINT-GOLDEN-MECHANICS ───────────────────────────────────────
[ -f "spec/ui/CellMechanics.hs" ] || note "LINT-GOLDEN-MECHANICS: spec/ui/CellMechanics.hs missing"
[ -f "Tesseract/UI/Cells/CellMechanics.swift" ] || note "LINT-GOLDEN-MECHANICS: UI/Cells/CellMechanics.swift missing"
grep -q "ui/CellMechanics.hs" spec/Makefile || note "LINT-GOLDEN-MECHANICS: spec not registered in spec/Makefile"

if [ $FAIL -eq 0 ]; then
  echo "  ✓ grid lint clean ($(echo $GOVERNED | wc -w | tr -d ' ') governed dirs)"
  exit 0
else
  echo ""
  echo "  Grid constitution violated. Sizes are atoms: Lattice.gif(n) / Lattice.pt(n)."
  exit 1
fi
