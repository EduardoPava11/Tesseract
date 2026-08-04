-- CellMechanics.hs
-- Tesseract spec — UI layer
--
-- THE CONTROL-FACE ALGEBRA: every interactive region wears a face whose
-- state is an OPAQUE ink transform, never alpha. Ported from SixFour's
-- Spec.CellMechanics; the Swift twin is hand-checked
-- (Tesseract/UI/Cells/CellMechanics.swift) and golden-pinned by
-- TesseractTests/CellMechanicsParityTests.
--
--   states     = idle | pressed | busy | disabled          (ordinals 0-3)
--   treatments = ghost | lit | inverted | busy | checker   (ordinals 0-4)
--   faces      = frame | brackets
--
--   treatment(state, tick) = table[state·2 + beat]
--     where beat = 1 iff state == idle AND tick ≡ 0 (mod 4)
--
--   UM1  table shape        8 entries = |states| × 2
--   UM2  treatments total   every entry names a real treatment ordinal —
--                           the lawFaceNoAlpha carrier: each treatment is
--                           an opaque ink, so a total table means no
--                           state can ever fall through to alpha
--   UM3  only idle ticks    pressed/busy/disabled are tick-invariant
--   UM4  beat period        beat true exactly on tick ≡ 0 (mod 4) — the
--                           5 Hz BEAT at the 20 Hz clock; goldenBeat[1]
--                           is False, the reduce-motion anchor
--   UM5  idle semantics     idle is ghost off-beat, lit on-beat
--   UM6  golden table       the flat table equals SixFour's shipped
--                           [0,1,2,2,3,3,4,4] (the cross-app pin)
--
-- TRUTHFUL harness: every law asserted, exits nonzero on failure.

module Main where

import System.Exit (exitFailure, exitSuccess)

data ControlState = Idle | Pressed | Busy | Disabled
  deriving (Eq, Ord, Enum, Bounded, Show)

data Treatment = Ghost | Lit | Inverted | BusyInk | Checker
  deriving (Eq, Ord, Enum, Bounded, Show)

beatPeriod :: Int
beatPeriod = 4

-- | The semantic definition — treatment as a function of state and beat.
treatmentOf :: ControlState -> Bool -> Treatment
treatmentOf Idle     beat = if beat then Lit else Ghost
treatmentOf Pressed  _    = Inverted
treatmentOf Busy     _    = BusyInk
treatmentOf Disabled _    = Checker

-- | The flat table the Swift twin ships: index = state·2 + (beat?1:0).
table :: [Int]
table = [ fromEnum (treatmentOf s b)
        | s <- [minBound .. maxBound], b <- [False, True] ]

beat :: ControlState -> Int -> Bool
beat s t = s == Idle && t `mod` beatPeriod == 0

-- | The full evaluator, as the Swift `faceTreatment(state:tick:)`.
faceTreatment :: ControlState -> Int -> Int
faceTreatment s t = table !! (fromEnum s * 2 + (if beat s t then 1 else 0))

goldenBeat :: [Bool]
goldenBeat = [ t `mod` beatPeriod == 0 | t <- [0 .. 15] ]

-- ════════════════════════════════════════════════════════════════
-- Laws
-- ════════════════════════════════════════════════════════════════

um1_shape :: Bool
um1_shape = length table == length ([minBound .. maxBound] :: [ControlState]) * 2

um2_total :: Bool
um2_total = all (\e -> e >= 0 && e <= fromEnum (maxBound :: Treatment)) table

um3_onlyIdleTicks :: Bool
um3_onlyIdleTicks = and
  [ faceTreatment s t1 == faceTreatment s t2
  | s <- [Pressed, Busy, Disabled], t1 <- [0 .. 15], t2 <- [0 .. 15] ]

um4_beatPeriod :: Bool
um4_beatPeriod = goldenBeat == [ t `mod` 4 == 0 | t <- [0 .. 15] ]
              && not (goldenBeat !! 1)

um5_idle :: Bool
um5_idle = and [ faceTreatment Idle t
                 == fromEnum (if t `mod` 4 == 0 then Lit else Ghost)
               | t <- [0 .. 15] ]

um6_golden :: Bool
um6_golden = table == [0, 1, 2, 2, 3, 3, 4, 4]

check :: String -> Bool -> IO Bool
check name ok = do
  putStrLn ((if ok then "  ✓ " else "  ✗ ") ++ name)
  return ok

main :: IO ()
main = do
  putStrLn "CellMechanics: the control-face algebra (opaque ink, one clock)"
  results <- sequence
    [ check "UM1 table shape: 8 = |states| × 2"                  um1_shape
    , check "UM2 treatments total (lawFaceNoAlpha carrier)"       um2_total
    , check "UM3 only idle reads the tick"                        um3_onlyIdleTicks
    , check "UM4 beat ≡ tick mod 4 == 0; goldenBeat[1] = False"   um4_beatPeriod
    , check "UM5 idle = ghost off-beat, lit on-beat"              um5_idle
    , check "UM6 golden table [0,1,2,2,3,3,4,4]"                  um6_golden
    ]
  putStrLn ("  golden table  = " ++ show table)
  putStrLn ("  golden beat   = " ++ show (map fromEnum goldenBeat))
  if and results then exitSuccess else exitFailure
