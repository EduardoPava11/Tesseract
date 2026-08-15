#!/bin/bash
# lint-grid.sh — the grid constitution, enforced (exit 1 fails the build).
# Ported from SixFour's lint discipline, trimmed to Tesseract's scope.
#
# Governed directories (migrated to the lattice):
#   Tesseract/Surface (App/, Cells/, Lattice/, Scenes/, Widgets/)
# (GIFPlayerView is a primitive and now lives with the other cell
#  primitives; CubeGIFView, FaceCaptureView and PaletteSwatchView were
#  deleted in past passes — every surviving view is governed.)
#
# Invariants:
#   LINT-PLACEMENT      .position(/.offset( only with // LINT-ALLOW-POSITION
#   LINT-SINGLE-LATTICE gifPx/subPt/cellPt declared ONLY in the two
#                       lattice files (sole owner of cell↔point math)
#   LINT-SINGLE-PITCH   numeric literals in .frame/.padding/spacing/
#                       minLength must go through Lattice.gif/pt (0 allowed)
#   LINT-REGION-SOURCE  GridRegion is CONSTRUCTED only in the two lattice
#                       files that are machine-checked disjoint — a view
#                       that mints its own rect has hand-positioned
#                       through the sanctioned door
#   LINT-GOLDEN-MECHANICS  the control-face algebra exists in BOTH forms
#                       (spec/ui/CellMechanics.hs + Surface/Cells/CellMechanics.swift),
#                       and the widget/dial specs exist with their ports
#
# ★ THE PRIMITIVE ALLOWLIST IS NOW A DIRECTORY (2026-08-14). It used to
# be a hand-kept name list — Cell*.swift plus PixelGrid, SurfaceClock,
# Ink, and Views/GIFPlayerView, which sat in a different directory than
# every other primitive it was grouped with. Surface/Cells/ IS the
# closed drawing-vocabulary layer, so membership is the address and the
# list cannot drift from it. The set is UNCHANGED by the move except
# that GIFPlayerView now lives with the primitives it always was one of.
# The invariant that replaces the list: nothing that is not a drawing
# primitive may be added to Surface/Cells/.

set -u
cd "$(dirname "$0")/.."

GOVERNED="Tesseract/Surface"
FAIL=0

# Files converted to the cell vocabulary: raw drawing vocab is banned
# (opacity, materials, shapes, strokes, shadows, bare Text, spinners).
# Grows as views convert; primitives (is_primitive) are exempt.
GOVERNED_VOCAB="
Tesseract/Surface/App/ContentView.swift
Tesseract/Surface/App/TesseractApp.swift
Tesseract/Surface/Scenes/IdleStateView.swift
Tesseract/Surface/Scenes/RecordingStateView.swift
Tesseract/Surface/Scenes/ProcessingStateView.swift
Tesseract/Surface/Scenes/ErrorStateView.swift
Tesseract/Surface/Scenes/ResultStateView.swift
Tesseract/Surface/Scenes/LivePreviewStateView.swift
Tesseract/Surface/Scenes/FacePreviewStateView.swift
Tesseract/Surface/Scenes/LibraryView.swift
Tesseract/Surface/Widgets/InformationWidgets.swift
Tesseract/Surface/Widgets/DetentDial.swift
Tesseract/Surface/Widgets/WidgetSurfaceView.swift
"

note() { echo "  ✗ $1"; FAIL=1; }

# The closed drawing-vocabulary layer.
is_primitive() {
  case "$1" in
    */Surface/Cells/*.swift)
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
    */Surface/Lattice/TesseractLattice.swift:*|*/Surface/Lattice/Lattice.swift:*) continue ;;
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
# Every interactive region must name a face (frame|brackets) in
# CellMechanics.controlFaces (lawControlFaceTotal). BOTH declaration
# files are scanned: GridLayout's static GridRegion rows and the widget
# vocabulary's WidgetSpec rows (spec/ui/WidgetGrid.hs WG1/WG9). Widget
# regions are COMPUTED from an Arrangement, so scanning GridLayout alone
# would silently stop covering the app's three most-touched controls —
# a weakening by omission. WidgetSpec deliberately mirrors GridRegion's
# labeled shape so ONE regex reads both files.
LINT_FACE_SOURCES="Tesseract/Surface/Lattice/GridLayout.swift Tesseract/Surface/Widgets/Arrangement.swift"
while IFS= read -r name; do
  [ -z "$name" ] && continue
  grep -q "\"$name\": \"" Tesseract/Surface/Cells/CellMechanics.swift \
    || note "LINT-CONTROL-FACE: interactive region '$name' has no entry in CellMechanics.controlFaces"
done < <(grep -h "interactive: true" $LINT_FACE_SOURCES \
         | sed -n 's/.*\(GridRegion\|WidgetSpec\)("\([^"]*\)".*/\2/p' | sort -u)

# ── LINT-REGION-SOURCE ──────────────────────────────────────────
# A runtime arrangement opens exactly one hole: a view could fabricate
# a GridRegion inline and .place() it, laundering hand positioning past
# LINT-PLACEMENT. Regions are constructed ONLY in the lattice files
# whose output is machine-checked disjoint (GridLayout.isLawful).
while IFS= read -r line; do
  case "$line" in
    Tesseract/Surface/Lattice/GridLayout.swift:*|Tesseract/Surface/Widgets/Arrangement.swift:*) continue ;;
  esac
  code=$(echo "${line#*:}" | sed 's|//.*||')
  echo "$code" | grep -q "GridRegion(" || continue
  note "LINT-REGION-SOURCE: GridRegion constructed outside the lattice:"
  echo "      $line"
done < <(grep -rn "GridRegion(" $GOVERNED --include="*.swift" || true)

# ── LINT-GOLDEN-MECHANICS ───────────────────────────────────────
[ -f "spec/ui/CellMechanics.hs" ] || note "LINT-GOLDEN-MECHANICS: spec/ui/CellMechanics.hs missing"
[ -f "Tesseract/Surface/Cells/CellMechanics.swift" ] || note "LINT-GOLDEN-MECHANICS: Surface/Cells/CellMechanics.swift missing"
grep -q "ui/CellMechanics.hs" spec/Makefile || note "LINT-GOLDEN-MECHANICS: spec not registered in spec/Makefile"
[ -f "spec/ui/WidgetGrid.hs" ] || note "LINT-GOLDEN-MECHANICS: spec/ui/WidgetGrid.hs missing"
[ -f "spec/ui/DetentDial.hs" ] || note "LINT-GOLDEN-MECHANICS: spec/ui/DetentDial.hs missing"
[ -f "spec/ui/EditMachine.hs" ] || note "LINT-GOLDEN-MECHANICS: spec/ui/EditMachine.hs missing"
grep -q "ui/WidgetGrid.hs" spec/Makefile || note "LINT-GOLDEN-MECHANICS: WidgetGrid spec not registered in spec/Makefile"
grep -q "ui/DetentDial.hs" spec/Makefile || note "LINT-GOLDEN-MECHANICS: DetentDial spec not registered in spec/Makefile"
grep -q "ui/EditMachine.hs" spec/Makefile || note "LINT-GOLDEN-MECHANICS: EditMachine spec not registered in spec/Makefile"
[ -f "Tesseract/Surface/Widgets/Arrangement.swift" ] || note "LINT-GOLDEN-MECHANICS: Surface/Widgets/Arrangement.swift missing"
[ -f "Tesseract/Surface/Widgets/DetentDial.swift" ] || note "LINT-GOLDEN-MECHANICS: Surface/Widgets/DetentDial.swift missing"
[ -f "Tesseract/Surface/EditMachine.swift" ] || note "LINT-GOLDEN-MECHANICS: Surface/EditMachine.swift missing"

# ── LINT-NO-STUB ────────────────────────────────────────────────
# ★ NO STUBS (Daniel's decree 2026-08-14). A stub is unfinished work
# wearing a finished face. If a thing is not built, the app SAYS so:
# Reweave returns a REFUSAL with a reason. A refusal is finished work.
# Scope is the WHOLE app, not just the governed view dirs, because an
# engine stub is worse than a view stub, not better.
while IFS= read -r line; do
  note "LINT-NO-STUB: stub marker in app source (build it, or refuse with a reason):"
  echo "      $line"
done < <(grep -rnE "(TODO|FIXME|XXX|HACK|STUB)[: ]" Tesseract --include="*.swift" --include="*.metal" || true)

# ── LINT-NO-FALLBACK ────────────────────────────────────────────
# ★ NO FALLBACKS (same decree). The failure is not the second path, it
# is the SILENCE: a fallback turns a bug into a permanent invisible
# loss, so nothing fails and nothing gets fixed. Three things are not
# fallbacks and must be NAMED for what they are:
#   twin     one law, two engines, PROVEN equal by a parity test
#   prior    a branch of the law itself (the single-phase BIC verdict)
#   refusal  terminal, visible, reasoned, with no silent substitute
# So the WORD is banned in app source. Escape hatch, mirroring
# LINT-ALLOW-POSITION: `// LINT-ALLOW-FALLBACK: <reason>` on the line,
# which makes each instance a decision someone signed.
while IFS= read -r line; do
  echo "$line" | grep -q "LINT-ALLOW-FALLBACK" && continue
  note "LINT-NO-FALLBACK: name it (twin / prior / verdict / platform path / refusal):"
  echo "      $line"
done < <(grep -rniE "fall[- ]?backs?|falls back" Tesseract --include="*.swift" --include="*.metal" || true)

if [ $FAIL -eq 0 ]; then
  echo "  ✓ grid lint clean ($(echo $GOVERNED | wc -w | tr -d ' ') governed dirs)"
  exit 0
else
  echo ""
  echo "  Grid constitution violated. Sizes are atoms: Lattice.gif(n) / Lattice.pt(n)."
  exit 1
fi
