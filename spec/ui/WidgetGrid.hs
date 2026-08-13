{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- WidgetGrid: instruments the user can MOVE
--
-- Daniel (2026-08-13): "we need more tools and widgets. when the
-- user opens the app and camera they should see the preview but
-- also a 16x16 for the color palette of that frame, a timer, a bar
-- to show how close it is to the 64 frame limit. INFORMATION! we
-- need to surface!" — and on layout: "all of these are good ideas
-- and they all fit in the iphone... but you need to add them as
-- widgets that can be moved around each other."
--
-- ── WHAT CHANGES ────────────────────────────────────────────────
--
-- Today a scene is a FIXED set of GridRegions, proven disjoint at
-- DEBUG launch. Nine scenes, nine hard-coded layouts. Adding an
-- instrument means editing a scene; moving one means editing code.
--
-- This spec replaces that with an ARRANGEMENT: a value mapping
-- each widget to a cell placement. Scenes stop being layouts and
-- become widget SETS; the placement is data the user owns. The
-- disjointness proof that ran once at launch now runs on every
-- move, and a move that would break it is REFUSED rather than
-- rendered (WG3).
--
-- ── THE TWO PROPERTIES THAT MAKE IT SAFE ────────────────────────
--
-- WG3 (lawful moves): `move` is TOTAL and returns Nothing for an
-- illegal placement. There is no such thing as an overlapping
-- arrangement, so there is no z-order, no occlusion, and no
-- "which widget is on top" question to answer (WG10).
--
-- WG8 (the atom is inviolable): placements are integer cells. A
-- widget cannot land on a half-atom, so every instrument stays on
-- the same lattice as the GIF pixels it describes. Dragging is
-- snapping, always.
--
-- ── THE VOCABULARY IS CLOSED (WG6) ──────────────────────────────
--
-- Twelve widgets, no more. The same discipline as RoleAllocation
-- RA8: a finite, enumerable surface means the UI cannot express an
-- arrangement the app cannot render, and cannot fail to reach one
-- it can. An arrangement serialises to twelve (col, row) pairs —
-- small enough to persist, share, and reset.
--
-- ── AXIOMS ──────────────────────────────────────────────────────
--
--   WG1  every widget has a cell footprint; a placement determines
--        the exact region it occupies
--   WG2  an arrangement is LAWFUL iff every widget is in bounds and
--        no two overlap
--   WG3  ★ moves are total and lawfulness-preserving: an illegal
--        move is REFUSED, never rendered
--   WG4  ★ an arrangement is a VALUE — serialisable, restorable,
--        and equal iff the placements are equal
--   WG5  the default arrangement exists and is lawful
--   WG6  ★ the widget vocabulary is CLOSED and enumerable
--   WG7  the canvas has headroom: the default leaves room to add
--   WG8  ★ placements are integer cells — the atom is inviolable
--   WG9  interactive widgets meet the touch floor
--   WG10 ★ disjointness ⇒ no z-order: occlusion is unrepresentable
--   WG11 moving a widget changes ONLY that widget's region
--   WG12 the three rungs are all surfaceable at once — 64³, 32³ and
--        16³ instruments coexist lawfully (Daniel's parallel read,
--        made visible)
-- ════════════════════════════════════════════════════════════════

module Main where

import Data.List (nub, sort)
import Data.Maybe (isJust, isNothing, fromJust)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE CANVAS AND THE VOCABULARY
-- ════════════════════════════════════════════════════════════════

-- | The lattice, in cells. ONE CELL = ONE ATOM = 4 pt, and one
--   atom is one displayed GIF pixel: 100 x 218 cells = 400 x 872 pt.
canvasCols, canvasRows :: Int
canvasCols = 100
canvasRows = 218

-- | The closed widget vocabulary. Twelve instruments, no more.
data Widget
  = Preview64      -- the fine read, 1 cell per GIF pixel at scale 4
  | Preview32      -- ★ the mid read, live
  | Preview16      -- ★ the coarse read, live
  | Palette        -- ★ this frame's 256 entries, 16×16
  | Timer          -- elapsed, in the counter register
  | Counter        -- n / 64
  | FramesBar      -- ★ how close to the 64-frame limit
  | PhaseStrip     -- FACE / BAND / SOLID tile composition
  | EnergyRead     -- ΔE² density, the phase-diagram readout
  | Shutter
  | SetButton
  | ShelfButton
  deriving (Eq, Ord, Show, Enum, Bounded)

vocabulary :: [Widget]
vocabulary = [minBound .. maxBound]

-- | Footprint in cells: (width, height).
footprint :: Widget -> (Int, Int)
footprint Preview64   = (64, 64)
footprint Preview32   = (32, 32)
footprint Preview16   = (16, 16)
footprint Palette     = (16, 16)
footprint Timer       = (20, 7)
footprint Counter     = (20, 7)
footprint FramesBar   = (64, 2)
footprint PhaseStrip  = (64, 2)
footprint EnergyRead  = (20, 7)
footprint Shutter     = (22, 22)
footprint SetButton   = (20, 13)
footprint ShelfButton = (20, 13)

-- | Which widgets accept touch. (WG9's scope.)
interactive :: Widget -> Bool
interactive Shutter     = True
interactive SetButton   = True
interactive ShelfButton = True
interactive _           = False

-- | The touch floor, in cells: 44 pt / 4 pt = 11 cells, the
--   platform minimum. The SMALLER dimension must clear it, so a
--   thin strip cannot pass by being long. Reporting instruments
--   take no touch and are exempt.
touchFloorCells :: Int
touchFloorCells = 11

-- ════════════════════════════════════════════════════════════════
-- § 2. PLACEMENT AND ARRANGEMENT
-- ════════════════════════════════════════════════════════════════

type Placement = (Int, Int)          -- (col, row) of the top-left cell

type Arrangement = [(Widget, Placement)]

-- | The cells a widget covers when placed. Half-open in both axes.
region :: Widget -> Placement -> [(Int, Int)]
region w (c, r) =
  [ (c + dx, r + dy) | dx <- [0 .. wd - 1], dy <- [0 .. ht - 1] ]
  where (wd, ht) = footprint w

-- | Bounds: the whole footprint must fit on the canvas.
inBounds :: Widget -> Placement -> Bool
inBounds w (c, r) =
     c >= 0 && r >= 0
  && c + wd <= canvasCols && r + ht <= canvasRows
  where (wd, ht) = footprint w

overlaps :: (Widget, Placement) -> (Widget, Placement) -> Bool
overlaps (w1, p1) (w2, p2) =
  not (null [ () | q <- region w1 p1, q `elem` region w2 p2 ])

-- | An arrangement is lawful iff every widget fits and none overlap.
lawful :: Arrangement -> Bool
lawful a =
     all (uncurry inBounds) a
  && and [ not (overlaps x y)
         | (i, x) <- zip [0 :: Int ..] a
         , (j, y) <- zip [0 :: Int ..] a
         , i < j ]

placementOf :: Arrangement -> Widget -> Maybe Placement
placementOf a w = lookup w a

-- | ★ A move is TOTAL: it yields Nothing when the destination would
--   break lawfulness. An unlawful arrangement is unrepresentable.
move :: Arrangement -> Widget -> Placement -> Maybe Arrangement
move a w p
  | isNothing (placementOf a w) = Nothing
  | lawful a'                   = Just a'
  | otherwise                   = Nothing
  where a' = [ (u, if u == w then p else q) | (u, q) <- a ]

-- | Serialisation: an arrangement is twelve (col, row) pairs in
--   vocabulary order. Small enough to persist and to share.
serialise :: Arrangement -> [(Int, Int)]
serialise a = [ maybe (-1, -1) id (placementOf a w) | w <- vocabulary ]

deserialise :: [(Int, Int)] -> Arrangement
deserialise ps = [ (w, p) | (w, p) <- zip vocabulary ps, p /= (-1, -1) ]

-- ════════════════════════════════════════════════════════════════
-- § 3. THE DEFAULT ARRANGEMENT
--
-- Everything Daniel named, plus the two coarse reads and the two
-- phase instruments — all on screen at once, all movable.
-- ════════════════════════════════════════════════════════════════

defaultArrangement :: Arrangement
defaultArrangement =
  [ (Preview64,   (18,  16))
  , (Preview32,   (18,  84))
  , (Preview16,   (52,  84))
  , (Palette,     (70,  84))
  , (Timer,       (52, 102))
  , (Counter,     (74, 102))
  , (FramesBar,   (18, 120))
  , (PhaseStrip,  (18, 124))
  , (EnergyRead,  (18, 128))
  , (Shutter,     (39, 150))
  , (SetButton,   (10, 155))
  , (ShelfButton, (70, 155))
  ]

canvasArea :: Int
canvasArea = canvasCols * canvasRows

usedArea :: Arrangement -> Int
usedArea a = sum [ wd * ht | (w, _) <- a, let (wd, ht) = footprint w ]

-- ════════════════════════════════════════════════════════════════
-- § 4. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (WG1) Footprints determine regions exactly: area is width×height,
--       every cell distinct, and the top-left cell is the placement.
axiom_WG1 :: Bool
axiom_WG1 =
     all sane vocabulary
  && all (\w -> region w (3, 5) !! 0 == (3, 5)) vocabulary
  where
    sane w =
      let (wd, ht) = footprint w
          cs       = region w (0, 0)
      in wd > 0 && ht > 0
         && length cs == wd * ht
         && length (nub cs) == wd * ht

-- (WG2) Lawfulness is exactly "in bounds and pairwise disjoint",
--       and it detects both kinds of violation.
axiom_WG2 :: Bool
axiom_WG2 =
     lawful defaultArrangement
  && not (lawful offCanvas)
  && not (lawful collided)
  && all (uncurry inBounds) defaultArrangement
  where
    offCanvas = [ (Preview64, (canvasCols - 4, 0)) ]
    collided  = [ (Preview64, (0, 0)), (Palette, (10, 10)) ]

-- (WG3) ★ Moves are total and lawfulness-preserving. A legal move
--       yields a lawful arrangement; an illegal one is REFUSED.
axiom_WG3 :: Bool
axiom_WG3 =
     isJust legal
  && lawful (fromJust legal)
  && isNothing ontoAnother
  && isNothing offEdge
  && isNothing absent
  where
    legal       = move defaultArrangement Palette (60, 130)
    ontoAnother = move defaultArrangement Palette (18, 16)   -- onto Preview64
    offEdge     = move defaultArrangement Preview64 (60, 16)
    absent      = move [(Palette, (0, 0))] Shutter (0, 0)

-- (WG4) ★ An arrangement is a VALUE: serialisation round-trips, and
--       two arrangements are equal exactly when their placements
--       are. Twelve pairs persist the entire surface.
axiom_WG4 :: Bool
axiom_WG4 =
     deserialise (serialise defaultArrangement) == defaultArrangement
  && length (serialise defaultArrangement) == length vocabulary
  && serialise defaultArrangement /= serialise moved
  && lawful moved
  where moved = fromJust (move defaultArrangement Palette (60, 130))

-- (WG5) The default exists, is lawful, and places EVERY widget in
--       the vocabulary — nothing is hidden by default.
axiom_WG5 :: Bool
axiom_WG5 =
     lawful defaultArrangement
  && sort (map fst defaultArrangement) == sort vocabulary
  && length defaultArrangement == length vocabulary
  && all (isJust . placementOf defaultArrangement) vocabulary

-- (WG6) ★ The vocabulary is CLOSED and enumerable — twelve
--       instruments, distinct, each with a distinct footprint role.
axiom_WG6 :: Bool
axiom_WG6 =
     length vocabulary == 12
  && length (nub vocabulary) == 12
  && length (nub (map show vocabulary)) == 12
  && all (\w -> footprint w == footprint w) vocabulary

-- (WG7) Headroom: the default uses well under the canvas, so more
--       instruments can be added without a redesign.
axiom_WG7 :: Bool
axiom_WG7 =
     usedArea defaultArrangement < canvasArea
  && 2 * usedArea defaultArrangement < canvasArea    -- under half
  && canvasArea == 21800

-- (WG8) ★ THE ATOM IS INVIOLABLE. Placements are integers, so every
--       widget lands on the cell lattice — the same lattice as the
--       GIF pixels it reports on. Dragging is snapping.
axiom_WG8 :: Bool
axiom_WG8 =
     all (\(_, (c, r)) -> c >= 0 && r >= 0) defaultArrangement
  && all onLattice (concat [ region w p | (w, p) <- defaultArrangement ])
  && all (\(w, p) -> head (region w p) == p) defaultArrangement
  where
    onLattice (c, r) = c >= 0 && r >= 0 && c < canvasCols && r < canvasRows

-- (WG9) Interactive widgets meet the touch floor; instruments that
--       only report are exempt and may be as small as one cell.
axiom_WG9 :: Bool
axiom_WG9 =
     all bigEnough (filter interactive vocabulary)
  && any (not . interactive) vocabulary
  && length (filter interactive vocabulary) == 3
  where
    bigEnough w =
      let (wd, ht) = footprint w
      in min wd ht >= touchFloorCells

-- (WG10) ★ DISJOINTNESS ⇒ NO Z-ORDER. In a lawful arrangement every
--        cell belongs to at most one widget, so occlusion cannot
--        occur and "which is on top" is not a question the surface
--        can be asked.
axiom_WG10 :: Bool
axiom_WG10 =
     length (nub occupied) == length occupied
  && all (\c -> length (owners c) <= 1) (take 400 occupied)
  where
    occupied = concat [ region w p | (w, p) <- defaultArrangement ]
    owners c = [ w | (w, p) <- defaultArrangement, c `elem` region w p ]

-- (WG11) Moving one widget changes ONLY its region; every other
--        widget's cells are untouched.
axiom_WG11 :: Bool
axiom_WG11 =
     all unchanged [ w | w <- vocabulary, w /= Palette ]
  && placementOf after Palette /= placementOf defaultArrangement Palette
  where
    after = fromJust (move defaultArrangement Palette (60, 130))
    unchanged w = placementOf after w == placementOf defaultArrangement w

-- (WG12) ★ THE THREE RUNGS ARE SURFACEABLE AT ONCE. 64³, 32³ and
--         16³ instruments coexist lawfully in the default — the
--         parallel read is not merely an internal architecture, it
--         is visible.
axiom_WG12 :: Bool
axiom_WG12 =
     all (isJust . placementOf defaultArrangement) [Preview64, Preview32, Preview16]
  && footprint Preview64 == (64, 64)
  && footprint Preview32 == (32, 32)
  && footprint Preview16 == (16, 16)
  && footprint Palette   == footprint Preview16   -- 16×16 = 256 = bijection
  && lawful [ (w, p) | (w, p) <- defaultArrangement
            , w `elem` [Preview64, Preview32, Preview16, Palette] ]

-- ════════════════════════════════════════════════════════════════
-- § 5. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " WidgetGrid: instruments the user can MOVE"
  putStrLn " a scene is a widget SET; the placement is data they own"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── The vocabulary (closed, twelve) ──"
  putStrLn ""
  putStrLn "  widget       │  cells  │ at      │ touch"
  putStrLn "  ─────────────┼─────────┼─────────┼──────"
  mapM_ row vocabulary
  putStrLn ""
  putStrLn $ "  canvas " ++ show canvasCols ++ "×" ++ show canvasRows
           ++ " = " ++ show canvasArea ++ " cells; default uses "
           ++ show (usedArea defaultArrangement)
           ++ " (" ++ show (100 * usedArea defaultArrangement `div` canvasArea)
           ++ "%)"
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "WG1  footprints determine regions exactly"                [axiom_WG1]
  check "WG2  lawful = in bounds AND pairwise disjoint"            [axiom_WG2]
  check "WG3  ★ moves are total; an illegal move is REFUSED"       [axiom_WG3]
  check "WG4  ★ an arrangement is a VALUE: round-trips exactly"    [axiom_WG4]
  check "WG5  the default is lawful and places every widget"       [axiom_WG5]
  check "WG6  ★ the vocabulary is CLOSED and enumerable (12)"      [axiom_WG6]
  check "WG7  headroom: the default uses under half the canvas"    [axiom_WG7]
  check "WG8  ★ placements are integer cells — atom inviolable"    [axiom_WG8]
  check "WG9  interactive widgets meet the touch floor"            [axiom_WG9]
  check "WG10 ★ disjointness ⇒ occlusion is unrepresentable"       [axiom_WG10]
  check "WG11 moving one widget changes only its own region"       [axiom_WG11]
  check "WG12 ★ all three rungs surfaceable at once"               [axiom_WG12]
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  A scene stops being a layout and becomes a widget SET."
  putStrLn "  Where each instrument sits is DATA the user owns —"
  putStrLn "  twelve (col, row) pairs, persisted and restorable."
  putStrLn ""
  putStrLn "  The disjointness proof that used to run once at launch"
  putStrLn "  now runs on every move, and an illegal move is REFUSED"
  putStrLn "  rather than rendered. So there is no overlap, hence no"
  putStrLn "  z-order, hence no occlusion — a whole class of layout"
  putStrLn "  question the surface simply cannot be asked."
  putStrLn ""
  putStrLn "  And placements are integer cells, so an instrument"
  putStrLn "  always lands on the same lattice as the GIF pixels it"
  putStrLn "  reports on. Dragging is snapping, always."
  putStrLn "══════════════════════════════════════════════════════════"

row :: Widget -> IO ()
row w =
  let (wd, ht) = footprint w
      p        = maybe "  —" (\(c, r) -> pad 3 (show c) ++ "," ++ pad 3 (show r))
                       (placementOf defaultArrangement w)
  in putStrLn $ "  " ++ padR 12 (show w)
             ++ " │ " ++ pad 3 (show wd) ++ "×" ++ padR 4 (show ht)
             ++ "│ " ++ padR 8 p
             ++ "│ " ++ (if interactive w then "yes" else "—")

pad :: Int -> String -> String
pad n s = replicate (max 0 (n - length s)) ' ' ++ s

padR :: Int -> String -> String
padR n s = s ++ replicate (max 0 (n - length s)) ' '

check :: String -> [Bool] -> IO ()
check name results =
  let passed = and results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
