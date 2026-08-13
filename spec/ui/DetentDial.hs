-- DetentDial.hs — THE DIAL IS A CIRCLE WITH DETENTS
--
-- Daniel's ruling (2026-08-13): "This is where we need a UI with
-- widgets that allow for incremental movements. think circles and
-- degrees of freedom."
--
-- The ruling answers a question it was not asked. "FULL 64^3 every
-- tick" is only affordable if a TICK is well defined, and a circle
-- with detents defines it: a tick is a DETENT CROSSING, not a touch
-- sample. At 120 Hz a continuous knob would demand 120 full cubes per
-- second of drag; a detented one demands at most one per stop.
--
-- The second half of the ruling is the ladder. Because the rungs are
-- a successive refinement (Octave OV13: kappa COMPOSES, so the coarse
-- read is a genuine prefix of the fine one), the drag can render 16^3
-- while the finger moves, 32^3 as each detent is crossed, and 64^3 on
-- release, and the user is NEVER shown a value the final render
-- contradicts. The codec's refinement becomes the interaction's.
--
-- ★ NO NAKED COUNTS. Not one detent count is written down. Every
-- count is derived from the data of the law that dial drives, so a
-- change to the law moves the dial automatically.
--
-- Companion specs (authoritative, do not restate their laws here):
--   spec/quantization/AttractorRAG.hs  — pairLadder, the sigma mirror
--   spec/quantization/Octave.hs        — the rung sides, OV13
--   spec/quantization/RoleAllocation.hs— dFig : dGnd
--   spec/ui/WidgetGrid.hs              — the atom grid, the touch floor
--
-- Axioms DD1-DD10.

module Main where

import Data.List (nub, sort)
import Data.Ratio ((%))
import System.Exit (exitFailure)

type Q = Rational

-- ══ The data the dials are derived FROM ═════════════════
-- Mirrored from the companion specs. Each is asserted against its
-- source shape in DD10 so a drift there is caught here.

-- AttractorRAG: eight BALANCED pairs, both members equal.
pairLadder :: [Int]
pairLadder = [1, 1, 2, 4, 8, 16, 32, 64]

-- Octave: the three rungs, read in PARALLEL. 16 is the floor because
-- 16 x 16 = 256 is the palette bijection.
rungSides :: [Int]
rungSides = [16, 32, 64]

-- RoleAllocation: the shipping figure:ground split, in bits.
roleBits :: (Int, Int)
roleBits = (7, 4)

-- WidgetGrid WG9: one atom cell is 4 pt, so Apple's 44 pt touch
-- floor is 11 cells. A dial obeys the same floor as any widget.
touchFloorCells :: Int
touchFloorCells = 11

-- Hardware fact, not a tuning knob: ProMotion delivers touch samples
-- at 120 Hz, so a one-second sweep of a continuous control produces
-- this many candidate recomputes.
touchSamplesPerSweep :: Int
touchSamplesPerSweep = 120

-- A strict RATIONAL LOWER BOUND on tau = 2*pi (6.283185...). Used
-- only where a lower bound yields the CONSERVATIVE answer, so the
-- radius law can never under-size a dial. A mathematical bound, not
-- a fitted constant.
tauLower :: Q
tauLower = 157 % 25          -- 6.28 < 2*pi

-- ══ The dials ═══════════════════════════════════════════

data Law
  = Allocation      -- which attractor gets which basin
  | RungPick        -- which rung the user is looking at
  | RoleSplit       -- how the bits divide figure from ground
  | ColourDisc      -- OKLab hue x chroma: the 2-DOF one
  deriving (Eq, Show, Enum, Bounded)

allLaws :: [Law]
allLaws = [minBound .. maxBound]

-- (DD1) DERIVED, NEVER WRITTEN. One entry per degree of freedom.
detents :: Law -> [Int]
detents Allocation = [length pairLadder]                 -- 8
detents RungPick   = [length rungSides]                  -- 3
detents RoleSplit  = [fst roleBits + snd roleBits + 1]   -- 12 stops for 11 bits
detents ColourDisc = [minimum rungSides, length pairLadder]
                     -- hue from the FLOOR rung (16, the bijection);
                     -- chroma from the balanced pairs (8).

-- (DD7) Degrees of freedom is just the arity of that list.
dof :: Law -> Int
dof = length . detents

-- Total distinguishable positions.
positions :: Law -> Int
positions = product . detents

-- ══ The circle ══════════════════════════════════════════

-- Which detent an angle in [0, 360) lands in. Equal arcs.
detentAt :: Int -> Q -> Int
detentAt k a = fromIntegral (floor (a * fromIntegral k / 360) :: Integer) `mod` k

-- The angle a detent snaps TO.
snapAngle :: Int -> Int -> Q
snapAngle k i = fromIntegral i * 360 / fromIntegral k

-- A tick is a CROSSING, not a sample (DD3).
ticks :: Int -> [Q] -> Int
ticks k path = length (filter id (zipWith (/=) idx (drop 1 idx)))
  where idx = map (detentAt k) path

-- The radius a dial needs so every detent clears the touch floor:
-- k arcs of >= touchFloorCells each need circumference >= k*floor,
-- so r >= k*floor/tau. tauLower makes this an over-estimate.
minRadiusCells :: Law -> Q
minRadiusCells law =
  fromIntegral (maximum (detents law) * touchFloorCells) / tauLower

-- ══ The interaction ladder (DD5) ════════════════════════

data Gesture = Dragging | Crossed | Released
  deriving (Eq, Ord, Show, Enum, Bounded)

-- While moving, the cheapest rung. On a detent, the middle. On
-- release, the truth.
renderSide :: Gesture -> Int
renderSide Dragging = minimum rungSides
renderSide Crossed  = rungSides !! 1
renderSide Released = maximum rungSides

-- Work is voxels.
cost :: Int -> Integer
cost side = fromIntegral side ^ (3 :: Int)

-- One full sweep of the dial, detented: the cheap rung on every touch
-- sample, the middle rung on every detent crossed, the full cube once
-- on release.
costDetented :: Law -> Integer
costDetented law =
  fromIntegral touchSamplesPerSweep * cost (renderSide Dragging)
  + fromIntegral (maximum (detents law)) * cost (renderSide Crossed)
  + cost (renderSide Released)

-- The same sweep with no detents and no ladder: the full cube on
-- every touch sample.
costContinuous :: Integer
costContinuous = fromIntegral touchSamplesPerSweep * cost (maximum rungSides)

-- ══ Axioms ══════════════════════════════════════════════

-- (DD1) Every count is derived. Nothing in `detents` is a literal:
-- each equals a measurement of its source law's own data.
axiom_DD1 :: Bool
axiom_DD1 =
     detents Allocation == [length pairLadder]
  && detents RungPick   == [length rungSides]
  && detents RoleSplit  == [uncurry (+) roleBits + 1]
  && detents ColourDisc == [minimum rungSides, length pairLadder]
  && all (all (> 0)) (map detents allLaws)

-- (DD2) TOTALITY. Every angle in [0, 360) lands in exactly one
-- detent, and every detent is reachable. Checked on a fine sweep.
axiom_DD2 :: Bool
axiom_DD2 = all totalFor allLaws
  where
    totalFor law = all totalFor1 (detents law)
    totalFor1 k =
      let sweep = [ fromIntegral n % 4 | n <- [0 .. 1439 :: Integer] ]  -- 0.25 deg steps
          idx   = map (detentAt k) sweep
      in  all (\i -> i >= 0 && i < k) idx
          && sort (nub idx) == [0 .. k - 1]

-- (DD3) A TICK IS A CROSSING. A path with many samples inside one arc
-- emits zero ticks; a path that leaves and returns ends where it
-- began. This is what makes "full 64^3 every tick" affordable.
axiom_DD3 :: Bool
axiom_DD3 =
     ticks k jitterInsideOneArc == 0
  && ticks k outAndBack == 2
  && detentAt k (head outAndBack) == detentAt k (last outAndBack)
  where
    k   = head (detents Allocation)              -- 8 detents, 45 deg arcs
    arc = 360 % fromIntegral k
    -- 40 samples wandering inside the first arc: no crossing at all.
    jitterInsideOneArc =
      [ (arc * fromIntegral n) / 100 | n <- [1 .. 40 :: Integer] ]
    -- into the next arc and back again: exactly two crossings.
    outAndBack = [ arc / 4, arc / 2, arc * 3 / 2, arc / 2, arc / 4 ]

-- (DD4) A dial must be big enough for its own law. A dial whose
-- detents are finer than the touch floor is ILLEGAL, and the bound
-- says exactly how large it has to be. The 100-cell canvas width is
-- the ceiling every dial must fit inside.
axiom_DD4 :: Bool
axiom_DD4 = all fits allLaws
  where
    canvasWidthCells = 100 :: Q   -- WidgetGrid: the 100 x 218 atom grid
    fits law =
      let r = minRadiusCells law
      in  r > 0 && 2 * r <= canvasWidthCells

-- (DD5) THE RUNG LADDER IS THE INTERACTION LADDER. The three gesture
-- phases map onto the three rungs in strictly increasing order, each
-- side divides the next, and every side is a real rung. The division
-- is the point: it is what makes the coarse render a PREFIX of the
-- fine one rather than a different picture.
axiom_DD5 :: Bool
axiom_DD5 =
     map renderSide [Dragging, Crossed, Released] == sort rungSides
  && and [ renderSide a < renderSide b
         | (a, b) <- zip gs (drop 1 gs) ]
  && all (`elem` rungSides) (map renderSide gs)
  && renderSide Crossed  `mod` renderSide Dragging == 0
  && renderSide Released `mod` renderSide Crossed  == 0
  where gs = [minBound .. maxBound] :: [Gesture]

-- (DD6) THE DETENT PAYS FOR ITSELF. A full sweep of any dial costs
-- strictly less detented-with-ladder than continuous-at-full-rate,
-- and by a wide margin. This is the whole justification for the
-- interaction model, stated as arithmetic rather than intuition.
axiom_DD6 :: Bool
axiom_DD6 =
     all (\law -> costDetented law < costContinuous) allLaws
  && all (\law -> costDetented law * 10 < costContinuous) allLaws

-- (DD7) DEGREES OF FREEDOM. Exactly one dial is 2-DOF, and it is the
-- colour one: a knob cannot express a plane. Everything else is an
-- angle alone.
axiom_DD7 :: Bool
axiom_DD7 =
     [ law | law <- allLaws, dof law == 2 ] == [ColourDisc]
  && all (\law -> dof law == 1) [Allocation, RungPick, RoleSplit]
  && all (\law -> dof law >= 1) allLaws

-- (DD8) ★ THE DISC IS THE PALETTE IN POLAR FORM. The colour disc's
-- two axes multiply to exactly HALF the palette, and the sigma mirror
-- completes it. Neither axis was chosen: hue comes from the floor
-- rung (16, because 16 x 16 = 256 is the bijection) and chroma from
-- the eight balanced pairs. That their product is 128 is a
-- consequence, and it is the same 128-mirrored-to-256 structure
-- AttractorRAG already proves.
axiom_DD8 :: Bool
axiom_DD8 =
     positions ColourDisc == 128
  && positions ColourDisc * 2 == paletteSize
  && paletteSize == minimum rungSides * minimum rungSides
  where paletteSize = 256

-- (DD9) RETURNABILITY. The detents form the cyclic group Z_k: a full
-- turn is the identity, and stepping k times returns to the start
-- from ANY origin. This is the property a continuous dial cannot
-- have, and it is what "by feel" means operationally — the user can
-- get back to a setting without looking.
axiom_DD9 :: Bool
axiom_DD9 = all cyclic allLaws
  where
    cyclic law = all cyclic1 (detents law)
    cyclic1 k =
      let step i = (i + 1) `mod` k
          orbit i = iterate step i !! k
      in  all (\i -> orbit i == i) [0 .. k - 1]
          && all (\i -> detentAt k (snapAngle k i) == i) [0 .. k - 1]

-- (DD10) NO DRIFT. The source data still has the shape the dials
-- assume. If AttractorRAG's ladder stops being eight balanced pairs,
-- or Octave's floor stops being 16, this fails HERE rather than
-- silently mis-sizing a dial.
axiom_DD10 :: Bool
axiom_DD10 =
     length pairLadder == 8
  && take 2 pairLadder == [1, 1]                  -- the pairs are balanced
  && sort rungSides == rungSides                  -- stated coarse to fine
  && minimum rungSides == 16
  && maximum rungSides == 64
  && uncurry (+) roleBits == 11
  && fst roleBits > snd roleBits                  -- figure outranks ground
  && touchFloorCells == 11

-- ══ Harness ═════════════════════════════════════════════

checks :: [(String, Bool)]
checks =
  [ ("DD1  detent counts are derived, never written",      axiom_DD1)
  , ("DD2  every angle lands in exactly one detent",       axiom_DD2)
  , ("DD3  a tick is a crossing, not a touch sample",      axiom_DD3)
  , ("DD4  a dial is big enough for its own law",          axiom_DD4)
  , ("DD5  the rung ladder IS the interaction ladder",     axiom_DD5)
  , ("DD6  the detent pays for itself",                    axiom_DD6)
  , ("DD7  only colour is 2-DOF",                          axiom_DD7)
  , ("DD8  the disc is the palette in polar form",         axiom_DD8)
  , ("DD9  detents form Z_k: returnable by feel",          axiom_DD9)
  , ("DD10 the source laws have not drifted",              axiom_DD10)
  ]

main :: IO ()
main = do
  putStrLn "DetentDial — the dial is a circle with detents"
  putStrLn ""
  putStrLn "  law          DOF  detents      positions  min radius (cells)"
  mapM_ row [minBound .. maxBound]
  putStrLn ""
  putStrLn "  gesture    rung   cost (voxels)"
  mapM_ gRow [minBound .. maxBound]
  putStrLn ""
  putStrLn ("  sweep cost  detented(Allocation) = "
            ++ show (costDetented Allocation)
            ++ "   continuous = " ++ show costContinuous)
  putStrLn ""
  mapM_ line checks
  putStrLn ""
  let bad = length (filter (not . snd) checks)
  putStrLn ("  " ++ show (length checks - bad) ++ "/"
            ++ show (length checks) ++ " axioms hold")
  if bad > 0 then exitFailure else pure ()
  where
    row law =
      putStrLn ("  " ++ pad 12 (show law)
                ++ " " ++ pad 4 (show (dof law))
                ++ " " ++ pad 12 (show (detents law))
                ++ " " ++ pad 10 (show (positions law))
                ++ " " ++ show (approx (minRadiusCells law)))
    gRow g =
      putStrLn ("  " ++ pad 10 (show g)
                ++ " " ++ pad 6 (show (renderSide g))
                ++ " " ++ show (cost (renderSide g)))
    line (nm, ok) = putStrLn ("  " ++ (if ok then "\10003" else "\10007") ++ " " ++ nm)
    pad n s = s ++ replicate (max 0 (n - length s)) ' '
    -- two decimal places, without pulling in a formatter
    approx q = fromIntegral (round (q * 100) :: Integer) / (100 :: Double)
