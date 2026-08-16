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

# ── LINT-NO-TAUTOLOGY ───────────────────────────────────────────
# ★ AN AXIOM THAT CANNOT FAIL IS WORSE THAN NO AXIOM, because it
# reports green (Daniel, 2026-08-15: "all you have said is 'its green'
# yeah it is all related and made to hit green your job is to break
# things and prove things about the app we are building").
#
# This repo diagnosed the disease TWICE and never encoded a check:
#   FrameGeometry  Quantize.metal claimed "verified by G5-G10", and
#                  every one of those axioms is invariant under a
#                  relabelling of the output grid, so a 90 degree
#                  rotation lived in the kernel undetected.
#   MerkleSearch   restated another spec's measurement table in its own
#                  comment, got it wrong, and every axiom passed
#                  because they quantified over THAT TABLE.
# An adversarial run then found two more of the mechanical shape, both
# fixed in cacb55d. Those two shapes are greppable, so they are checked
# here. The relabelling-invariance shape is NOT mechanical and this
# lint does not pretend to catch it.
#
# Scope is spec/, which is the first time this script leaves the view
# tree. That is deliberate: the spec layer is the thing every other
# layer is checked against, so a blind axiom there is the most
# expensive kind.
#
# Escape hatch, mirroring the others:
#   -- LINT-ALLOW-TAUTOLOGY: <reason>
# on the line, which makes each instance a decision someone signed.

# T1: a list zipped with ITSELF. `zip rs rs` pairs each element with
# itself, so `f a == f b` over it is `f a == f a`. This was TA6.
while IFS= read -r line; do
  echo "$line" | grep -q "LINT-ALLOW-TAUTOLOGY" && continue
  # COMMENTS ARE EXEMPT, and they must be: a fix is worth explaining,
  # and TensorEncoder's TA6 now quotes the exact defect it replaced.
  # A lint that forbids naming the bug it prevents forces the next
  # reader to rediscover it.
  echo "$line" | sed -E 's/^[^:]*:[0-9]+://' | grep -qE "^[[:space:]]*--" && continue
  note "LINT-NO-TAUTOLOGY: a list zipped with itself compares elements to themselves:"
  echo "      $line"
done < <(grep -rnE "\bzip(With +[A-Za-z_][A-Za-z0-9_']*)? +([A-Za-z_][A-Za-z0-9_']*) +\2\b" \
           spec --include="*.hs" || true)

# ★ A GENERAL `x == x` CHECK WAS WRITTEN AND THEN DELETED, and the
# reason belongs here so nobody adds it back. It fired on six axioms
# and every one was a real law: `blend (0,0,1) feed == feed` is an
# identity, `loopK 0 palette8 targets q0 == q0` is a fixed point,
# `applyPerm p t == t` counts a symmetry group's order. `f x == x` is
# the canonical way to STATE an identity law, and a lint that flags
# those is worse than no lint, because it gets switched off and takes
# the true positives with it. The vacuous shape is not "both sides
# mention the same name", it is "both sides are the same LITERAL",
# which is what T3 tests.

# T3: THE CL7 SHAPE, and the one worth the effort. A binding whose
# ALL-LITERAL value is then compared against that same binding:
#     axiom = levels == [4, 32, 256]  where levels = [4, 32, 256]
# Both sides are the same constant, so it certifies any value.
#
# ★ THE LITERAL RESTRICTION IS LOAD-BEARING, not caution. DetentDial's
# DD1 has this exact SHAPE, `detents Allocation == [length pairLadder]`
# against a definition that reads the same, and it is a GOOD axiom: the
# right side is a DERIVATION, so literalising the definition to [8]
# breaks it. Restating a derivation pins a definition to its source.
# Restating a constant pins nothing. Only the second is the defect, so
# the value must be digits and separators alone.
for f in $(grep -rl "" spec --include="*.hs" 2>/dev/null || true); do
  while IFS= read -r bind; do
    name=$(echo "$bind" | sed -E 's/^.*[^A-Za-z0-9_'"'"']([A-Za-z_][A-Za-z0-9_'"'"']*) *= *\[.*$/\1/')
    lit=$(echo "$bind" | sed -E 's/^[^=]*= *(\[[^]]*\]).*$/\1/')
    [ -z "$name" ] && continue
    [ -z "$lit" ] && continue
    # literals ONLY: digits and separators. A derivation restated is a
    # pin, not a tautology. See the note above.
    echo "$lit" | grep -qE "^\[[0-9,.eE+ -]*\]$" || continue
    hit=$(grep -nF "$name == $lit" "$f" 2>/dev/null | grep -v "LINT-ALLOW-TAUTOLOGY" || true)
    [ -z "$hit" ] && continue
    note "LINT-NO-TAUTOLOGY: a binding compared against its own literal (derive it, do not restate it):"
    echo "      $f: $name = $lit"
    echo "      $hit"
  done < <(grep -E "^[^-]*\b[A-Za-z_][A-Za-z0-9_']* *= *\[[^]]*\]" "$f" 2>/dev/null || true)
done

if [ $FAIL -eq 0 ]; then
  echo "  ✓ grid lint clean ($(echo $GOVERNED | wc -w | tr -d ' ') governed dirs)"
  exit 0
else
  echo ""
  echo "  Grid constitution violated. Sizes are atoms: Lattice.gif(n) / Lattice.pt(n)."
  exit 1
fi
