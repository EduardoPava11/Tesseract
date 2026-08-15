{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- SurfaceMachine: the grid is a state machine
--
-- Daniel's ruling (2026-08-12): "The app should be made of a strict
-- grid. We have squares and with them the ability to make words.
-- The grid is a state machine that we use to surface what the app
-- is doing. Including after capture."
--
-- The pieces existed — the 100×218 atom grid, GridRegion scenes,
-- CellText words-as-squares — but the STATE MACHINE was scattered
-- (two ContentView switches, ad-hoc view titles). This spec is the
-- machine: one total map state → (word, scene), one lawful edge
-- relation, one interruptibility law. The Swift port
-- (SurfaceMachine.swift) is the single source ContentView consults.
--
--   SM1  voice: total, one distinct square-word per state
--   SM2  the capture arc: WEAVING → SOLVING → SEALED, no skips —
--        after capture the machine MUST surface the solve
--   SM3  un-interruptible work: exactly {WEAVING, SOLVING}
--   SM4  recoverability: non-terminal states reach WATCHING;
--        terminals are exactly the hardware refusals
--   SM5  scene discipline: one scene per state; SOLVING's scene
--        carries palette + progress + phase (after-capture law)
-- ════════════════════════════════════════════════════════════════

module SurfaceMachine where

import Data.List (nub)
import Data.Char (isUpper, isSpace)

-- ════════════════════════════════════════════════════════════════
-- § 1. STATES AND WORDS
-- ════════════════════════════════════════════════════════════════

-- NoCenterStage (Daniel's ruling, 2026-08-12): the app is for
-- iPhones with the Center Stage front camera — the square-sensor
-- selfie camera the iPhone 17 line introduced. The predicate is
-- hardware-derived (a front-position ultra-wide camera exists),
-- and like NoTrueDepth it is a terminal hardware refusal.
data Refusal = CameraOff | NoTrueDepth | NoCenterStage | NoFaceTracking
             | ExportFailed | Unknown
  deriving (Eq, Show, Enum, Bounded)

data S
  = Waking            -- session configuring / first frame pending
  | Watching          -- live preview, shutter armed
  | Weaving           -- recording the 64-frame cube
  | Solving           -- after capture: mixture, tree, tables, encode
  | Sealed            -- GIF encoded + archived
  | Refused Refusal   -- the two-register error voice
  deriving (Eq, Show)

allStates :: [S]
allStates = [Waking, Watching, Weaving, Solving, Sealed]
         ++ map Refused [minBound .. maxBound]

-- | THE word each state speaks in squares (CellText). Refusal
--   headlines are the ruled two-register voice (2026-08-09).
word :: S -> String
word Waking                   = "WAKING"
word Watching                 = "WATCHING"
word Weaving                  = "WEAVING"
word Solving                  = "SOLVING"
word Sealed                   = "SEALED"
word (Refused CameraOff)      = "CAMERA OFF"
word (Refused NoTrueDepth)    = "NO TRUEDEPTH"
word (Refused NoCenterStage)  = "NO CENTER STAGE"
word (Refused NoFaceTracking) = "NO FACE TRACKING"
word (Refused ExportFailed)   = "EXPORT FAILED"
word (Refused Unknown)        = "ERROR"

-- ════════════════════════════════════════════════════════════════
-- § 2. EDGES (the lawful transitions)
-- ════════════════════════════════════════════════════════════════

step :: S -> S -> Bool
step Waking    Watching  = True                    -- first preview frame
step Watching  Weaving   = True                    -- shutter
step Watching  Waking    = True                    -- mode switch restarts
step Weaving   Solving   = True                    -- capture complete
step Solving   Sealed    = True                    -- GIF sealed
step Sealed    Watching  = True                    -- AGAIN
step (Refused CameraOff)    Waking   = True        -- retry after grant
step (Refused ExportFailed) Watching = True        -- reshoot, session live
step (Refused Unknown)      Waking   = True
step s (Refused r) = refusalFrom s r               -- failures
step _ _ = False

-- | Which refusals can arise where: hardware gates fire while
--   waking; a denied camera too; export failure only from the
--   solve; unknown anywhere work happens.
refusalFrom :: S -> Refusal -> Bool
refusalFrom (Refused _) _      = False
refusalFrom s CameraOff        = s == Waking
refusalFrom s NoTrueDepth      = s == Waking
refusalFrom s NoCenterStage    = s == Waking
refusalFrom s NoFaceTracking   = s == Waking
refusalFrom s ExportFailed     = s == Solving
refusalFrom s Unknown          = s `elem` [Waking, Watching, Weaving, Solving]

-- | Settings/mode interruption law (ContentView.modeSwitchAllowed).
interruptible :: S -> Bool
interruptible Weaving = False
interruptible Solving = False
interruptible _       = True

-- | Terminal: no outgoing edges at all.
terminal :: S -> Bool
terminal s = not (any (step s) allStates)

reachable :: S -> S -> Bool
reachable from to = go [from] []
  where
    go [] _ = False
    go (x : xs) seen
      | x == to = True
      | x `elem` seen = go xs seen
      | otherwise = go (xs ++ [ n | n <- allStates, step x n ]) (x : seen)

-- ════════════════════════════════════════════════════════════════
-- § 3. SCENES (region names — the Swift GridLayout mirror)
-- ════════════════════════════════════════════════════════════════

scene :: S -> [String]
scene Waking      = ["idleTitle", "idleSub", "idleBusy", "idleHint"]
scene Watching    = ["preview", "record", "settingsButton"]
scene Weaving     = ["preview", "recCounter", "recProgress", "recTime"]
scene Solving     = ["procTitle", "procBoards", "procPalette",
                     "procBar", "procPct", "procPhase"]
scene Sealed      = ["resultGif", "resultMetrics", "resultNote",
                     "resultShare", "resultKeep", "resultRetake"]
scene (Refused _) = ["errTitle", "errMsg", "errRetry", "errSettings"]

-- ════════════════════════════════════════════════════════════════
-- § 4. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (SM1) VOICE: every state speaks exactly one word; words are
--       distinct, nonempty, and strictly square-speakable —
--       uppercase letters and spaces only (the pixel font's
--       vocabulary; digits ride payload rows, not the word).
axiom_SM1 :: Bool
axiom_SM1 =
     length (nub ws) == length ws
  && all (not . null) ws
  && all (all (\c -> isUpper c || isSpace c)) ws
  where ws = map word allStates

-- (SM2) THE CAPTURE ARC: WEAVING reaches SEALED only through
--       SOLVING — after capture the machine MUST surface the solve
--       (no edge Weaving → Sealed, no edge skipping the work);
--       and WEAVING is re-entered only through WATCHING.
axiom_SM2 :: Bool
axiom_SM2 =
     not (step Weaving Sealed)
  && step Weaving Solving && step Solving Sealed
  && [ s | s <- allStates, step s Weaving ] == [Watching]
  && reachable Weaving Sealed

-- (SM3) UN-INTERRUPTIBLE WORK: exactly the two working states
--       forbid settings/mode interruption, and each of their edges
--       lands somewhere that surfaces progress or a verdict.
axiom_SM3 :: Bool
axiom_SM3 =
     [ s | s <- allStates, not (interruptible s) ] == [Weaving, Solving]
  && all (`elem` [Solving, Sealed, Refused ExportFailed, Refused Unknown])
         [ n | s <- [Weaving, Solving], n <- allStates, step s n ]

-- (SM4) RECOVERABILITY: every non-terminal state reaches WATCHING;
--       the terminal states are EXACTLY the hardware refusals.
axiom_SM4 :: Bool
axiom_SM4 =
     all (\s -> terminal s || reachable s Watching) allStates
  && [ s | s <- allStates, terminal s ]
       == [Refused NoTrueDepth, Refused NoCenterStage, Refused NoFaceTracking]

-- (SM5) SCENE DISCIPLINE: every state has a nonempty scene with no
--       duplicate regions; SOLVING's scene carries the palette,
--       the progress bar, and the phase line — the after-capture
--       surfacing law ("including after capture").
axiom_SM5 :: Bool
axiom_SM5 =
     all (not . null . scene) allStates
  && all (\s -> length (nub (scene s)) == length (scene s)) allStates
  && all (`elem` scene Solving) ["procPalette", "procBar", "procPhase"]

-- ════════════════════════════════════════════════════════════════
-- § 5. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " SurfaceMachine: the grid is a state machine"
  putStrLn " squares make words; words surface what the app is doing"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  state     │ word             │ interruptible"
  putStrLn "  ──────────┼──────────────────┼──────────────"
  mapM_ (\s -> putStrLn $ "  " ++ padR 9 (label s)
                       ++ " │ " ++ padR 16 (word s)
                       ++ " │ " ++ (if interruptible s then "yes" else "NO"))
        allStates
  putStrLn ""
  check "SM1 voice: one distinct square-word per state"            [axiom_SM1]
  check "SM2 capture arc: WEAVING→SOLVING→SEALED, no skips"        [axiom_SM2]
  check "SM3 un-interruptible: exactly {WEAVING, SOLVING}"         [axiom_SM3]
  check "SM4 recovery: all reach WATCHING; terminals = hardware"   [axiom_SM4]
  check "SM5 scenes: unique regions; SOLVING surfaces the work"    [axiom_SM5]
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  The surface is not decoration on the pipeline; it is"
  putStrLn "  the pipeline's state made legible. One machine, one"
  putStrLn "  word per state, one scene per word — and after the"
  putStrLn "  shutter, the machine keeps talking: SOLVING shows the"
  putStrLn "  palette being born, SEALED shows the verdict."
  putStrLn "══════════════════════════════════════════════════════════"
  where
    label (Refused r) = take 9 ("R:" ++ show r)
    label s = show s

check :: String -> [Bool] -> IO ()
check name results =
  let mark = if and results then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name

padR :: Int -> String -> String
padR n s = s ++ replicate (max 0 (n - length s)) ' '
