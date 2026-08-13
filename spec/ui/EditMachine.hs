{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- EditMachine: the surface when EDIT is the whole app
--
-- Daniel's decree (2026-08-13): "EDIT is the whole app." Capture
-- becomes an input step; the shelf is home; one moment yields many
-- GIFs; the full 64³ re-solves EVERY TICK. This SUPERSEDES the
-- state set of spec/ui/SurfaceMachine.hs and amends the SIMPLICITY
-- decree (which forbade a reachable gallery) — Daniel ruled the
-- amendment explicitly.
--
-- SurfaceMachine's five laws are NOT discarded. They are restated
-- here and re-proved over the larger machine (EM6–EM8), because an
-- extension that quietly breaks its parent's laws is a rewrite
-- wearing a rewrite's clothes.
--
-- ── WHAT CHANGES, AND THE ONE LAW THAT MUST BEND ────────────────
--
-- SM3 said: exactly the working states (WEAVING, SOLVING) refuse
-- interruption. Under the tick decree the solve is no longer an
-- event — it is the steady state. If TUNING inherited SM3 the
-- dials would not answer, because every tick would have to run to
-- completion before the next could start.
--
-- So SM3 splits into two laws that were previously one:
--
--   EM4  a solve that is a CAPTURE (SOLVING) must complete —
--        it is the machine's promise that the moment was kept
--   EM5  a solve that is a TICK (TUNING) must be ABANDONABLE —
--        it is the machine's promise that the dial answers
--
-- The distinction is not latency, it is ownership: SOLVING owns
-- the only copy of a moment that will never recur; TUNING owns a
-- pure function of data already safely held (RA10), so discarding
-- a tick costs nothing but the compute already spent.
--
-- ── COHERENCE, THE LAW THAT MAKES ABANDONMENT SAFE ──────────────
--
-- EM8: the surface never shows a blend. Because a render is a pure
-- function of (capture, edit), every frame the user sees is
-- render(c, e) for SOME e they actually selected — never a mixture
-- of two edits, never a partially-updated cube. Ticks are
-- SUPERSEDED, not queued: last edit wins, and stale ticks are
-- discarded whole. That is what buys the right to abandon.
--
-- ── AXIOMS ──────────────────────────────────────────────────────
--
--   EM1  the shelf is home: WAKING leads to SHELVING, and every
--        non-refused state can reach the shelf again
--   EM2  ★ the machine has exactly TWO loops — WATCHING (reading
--        the live feed at all three rungs, and compressing it) and
--        TUNING (the tick). They are the two continuous processes;
--        every other state changes by leaving
--   EM3  the capture arc still admits no skips (SM2 preserved):
--        WEAVING is entered only from WATCHING, and every path
--        from WEAVING to a sealed GIF passes through SOLVING
--   EM4  capture-solve is un-interruptible (the SM3 half that keeps)
--   EM5  ★ tick-solve IS interruptible (the SM3 half that bends)
--   EM6  every state speaks a distinct square word (SM1 preserved)
--   EM7  terminals are exactly the hardware refusals (SM4 preserved)
--   EM8  ★ coherence: what is shown is render(capture, edit) for a
--        selected edit — never a blend, never a partial cube
--   EM9  reachability: no orphan states, no unreachable words
--   EM10 ★ fork freedom: the number of GIFs obtainable from ONE
--        capture is unbounded — SEALED returns to TUNING, so the
--        commit is a tap on the shelf, not an exit
--   EM11 path independence: the render depends on (capture, edit)
--        only — never on how TUNING was entered. Re-opening a
--        stored capture from the shelf reproduces its GIFs exactly
--   EM12 ★ weave = watch + keep. WATCHING is an ABSTRACTION of
--        WEAVING: identical work, and only RETENTION differs
--   EM13 ★ therefore the preview IS the GIF, bit for bit — the
--        port consequence is deleting DyadPreview, not merging it
-- ════════════════════════════════════════════════════════════════

module Main where

import Data.List (nub, sort)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE MACHINE
-- ════════════════════════════════════════════════════════════════

data Refusal
  = CameraOff
  | NoTrueDepth
  | NoCenterStage
  | NoFaceTracking
  | ExportFailed
  | Unknown
  deriving (Eq, Ord, Show)

data State
  = Waking          -- the device opens
  | Shelving        -- ★ HOME: the shelf of captures and their GIFs
  | Watching        -- live preview, nothing kept
  | Weaving         -- 64 frames being kept
  | Solving         -- the capture-solve; must complete
  | Tuning          -- ★ THE APP: dials turning, 64³ per tick
  | Sealed          -- a variant has been written to the shelf
  | Refused Refusal
  deriving (Eq, Ord, Show)

allStates :: [State]
allStates =
  [ Waking, Shelving, Watching, Weaving, Solving, Tuning, Sealed ]
  ++ map Refused [ CameraOff, NoTrueDepth, NoCenterStage
                 , NoFaceTracking, ExportFailed, Unknown ]

-- | The square word each state speaks. Uppercase letters and
--   spaces only (SM1). Kept short enough for the grid registers.
word :: State -> String
word Waking                    = "WAKING"
word Shelving                  = "SHELF"
word Watching                  = "WATCHING"
word Weaving                   = "WEAVING"
word Solving                   = "SOLVING"
word Tuning                    = "TUNING"
word Sealed                    = "SEALED"
word (Refused CameraOff)       = "CAMERA OFF"
word (Refused NoTrueDepth)     = "NO TRUEDEPTH"
word (Refused NoCenterStage)   = "NO CENTER STAGE"
word (Refused NoFaceTracking)  = "NO FACE TRACKING"
word (Refused ExportFailed)    = "EXPORT FAILED"
word (Refused Unknown)         = "REFUSED"

-- | The hardware refusals: terminal, no retry (SM4).
hardwareRefusals :: [State]
hardwareRefusals =
  [ Refused NoTrueDepth, Refused NoCenterStage, Refused NoFaceTracking ]

-- ── the edge set ────────────────────────────────────────────────

canStep :: State -> State -> Bool
canStep from to = (from, to) `elem` edges

edges :: [(State, State)]
edges =
  -- the device opens onto the shelf, or refuses
  [ (Waking, Shelving) ]
  ++ [ (Waking, r) | r <- map Refused allRefusals ]
  -- home: start a capture, or re-open a stored one
  ++ [ (Shelving, Watching), (Shelving, Tuning) ]
  -- ★ the live read: the feed enters at all three rungs, and is
  -- compressed as it arrives ("watching while watching")
  ++ [ (Watching, Watching) ]
  -- the capture arc, unchanged (SM2)
  ++ [ (Watching, Weaving), (Weaving, Solving) ]
  -- ★ the solve lands in the editor, not on a dead-end result
  ++ [ (Solving, Tuning) ]
  -- ★ the tick: the only self-loop
  ++ [ (Tuning, Tuning) ]
  -- commit, and keep going
  ++ [ (Tuning, Sealed), (Sealed, Tuning) ]
  -- leaving the editor
  ++ [ (Tuning, Shelving), (Tuning, Watching)
     , (Sealed, Shelving) ]
  -- soft refusals recover
  ++ [ (Refused CameraOff, Waking)
     , (Refused ExportFailed, Tuning)
     , (Refused Unknown, Shelving) ]
  where allRefusals = [ CameraOff, NoTrueDepth, NoCenterStage
                      , NoFaceTracking, ExportFailed, Unknown ]

-- | Whether a state may be left before its work finishes.
--   ★ The SM3 split: capture-solve may not, tick-solve must.
interruptible :: State -> Bool
interruptible Weaving = False   -- the moment is being kept
interruptible Solving = False   -- the only copy is in flight
interruptible Tuning  = True    -- ★ a pure function of held data
interruptible _       = True

-- ════════════════════════════════════════════════════════════════
-- § 2. THE TICK, AND WHAT COHERENCE MEANS
--
-- A render is modelled abstractly: an Edit selects one element of
-- the capture's image set. The spec does not re-derive the palette
-- (RoleAllocation.hs owns that) — it constrains the SURFACE, whose
-- only obligation is to show an element of that image, never a
-- blend of two.
-- ════════════════════════════════════════════════════════════════

type Edit    = Int          -- a point of RoleAllocation's edit space
type Capture = Int          -- an immutable moment

-- | The pure render (RA10). Injective in edit for a fixed capture,
--   which is what makes distinct dial settings distinguishable.
render :: Capture -> Edit -> (Capture, Edit)
render c e = (c, e)

-- | What the surface may legally display after a sequence of edits
--   arrives. Ticks are SUPERSEDED, not queued: the shown value is
--   the render of the LAST selected edit, and never anything else.
shown :: Capture -> [Edit] -> Maybe (Capture, Edit)
shown _ []  = Nothing
shown c es  = Just (render c (last es))

-- | The set of everything the surface could ever legally show for
--   a capture: exactly the image of render.
legalSurface :: Capture -> [Edit] -> [(Capture, Edit)]
legalSurface c space = map (render c) space

-- ── the live read: three rungs, one encoder (EM12) ──────────────
--
-- Octave.hs owns what the rungs MEAN and proves the three agree
-- (OV13). Here the only obligation is architectural: the same
-- transform runs in WATCHING and in WEAVING, and only retention
-- distinguishes them.

data Rung = R64 | R32 | R16 deriving (Eq, Ord, Show)

rungsRead :: [Rung]
rungsRead = [R64, R32, R16]

-- | The encoder. Compresses the feed at one rung.
encode :: Capture -> Rung -> (Capture, Rung)
encode c r = (c, r)

watchPath, weavePath :: Capture -> [(Capture, Rung)]
watchPath c = map (encode c) rungsRead
weavePath c = map (encode c) rungsRead

data Disposition = Discarded | Kept deriving (Eq, Show)

disposition :: State -> Maybe Disposition
disposition Watching = Just Discarded
disposition Weaving  = Just Kept
disposition _        = Nothing

-- ════════════════════════════════════════════════════════════════
-- § 3. REACHABILITY
-- ════════════════════════════════════════════════════════════════

successors :: State -> [State]
successors s = [ t | (f, t) <- edges, f == s ]

reachableFrom :: State -> [State]
reachableFrom s0 = go [s0] [s0]
  where
    go [] seen = seen
    go (x : xs) seen =
      let new = [ y | y <- successors x, y `notElem` seen ]
      in go (xs ++ new) (seen ++ new)

-- | Paths of bounded length, for the "no skips" proofs.
pathsFrom :: Int -> State -> [[State]]
pathsFrom 0 s = [[s]]
pathsFrom n s = [ s : p | t <- successors s, t /= s, p <- pathsFrom (n - 1) t ]
             ++ [[s]]

-- ════════════════════════════════════════════════════════════════
-- § 4. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (EM1) The shelf is home: waking opens onto it, and every state
--       that is not a hardware refusal can get back to it.
axiom_EM1 :: Bool
axiom_EM1 =
     canStep Waking Shelving
  && all (\s -> Shelving `elem` reachableFrom s)
         [ s | s <- allStates, s `notElem` hardwareRefusals ]
  && not (any (\s -> Shelving `elem` reachableFrom s) hardwareRefusals)

-- (EM2) ★ EXACTLY TWO LOOPS, and they are the machine's two
--       continuous processes. WATCHING reads the live feed at all
--       three rungs and compresses it; TUNING re-renders a held
--       capture. Every other state changes by LEAVING; these two
--       change by STAYING. Both must be leavable, and both must
--       be interruptible — a loop you cannot exit is a hang.
axiom_EM2 :: Bool
axiom_EM2 =
     canStep Watching Watching
  && canStep Tuning Tuning
  && [ s | s <- allStates, canStep s s ] == loops
  && all interruptible loops
  && all (\s -> length (successors s) >= 2) loops
  where loops = [Watching, Tuning]

-- (EM3) The capture arc still admits no skips (SM2 preserved):
--       WEAVING only from WATCHING; no path from WEAVING reaches
--       SEALED without passing through SOLVING and then TUNING.
axiom_EM3 :: Bool
axiom_EM3 =
     canStep Watching Weaving
  && [ s | s <- allStates, canStep s Weaving ] == [Watching]
  && not (canStep Weaving Sealed)
  && not (canStep Weaving Tuning)
  && not (canStep Solving Sealed)
  && all viaSolveThenTune (weavePaths 5)
  where
    weavePaths n = [ p | p <- pathsFrom n Weaving, Sealed `elem` p ]
    viaSolveThenTune p =
      let upto = takeWhile (/= Sealed) p
      in Solving `elem` upto && Tuning `elem` upto
         && idx Solving upto < idx Tuning upto
    idx x xs = length (takeWhile (/= x) xs)

-- (EM4) Capture-solve is un-interruptible. The half of SM3 that
--       keeps: while a moment is being kept or first solved, the
--       machine holds.
axiom_EM4 :: Bool
axiom_EM4 =
     not (interruptible Weaving)
  && not (interruptible Solving)
  && [ s | s <- allStates, not (interruptible s) ] == [Weaving, Solving]

-- (EM5) ★ Tick-solve IS interruptible. The half of SM3 that bends.
--       TUNING is both a working state and interruptible — the
--       combination SM3 forbade, licensed here by purity: a
--       discarded tick loses nothing but compute, because the
--       capture is immutable and the render is a function.
axiom_EM5 :: Bool
axiom_EM5 =
     interruptible Tuning
  && canStep Tuning Tuning                 -- it works
  && length (successors Tuning) > 1        -- and it can be left
  && all (\s -> interruptible s || not (canStep s s)) allStates

-- (EM6) SM1 preserved: distinct words, uppercase and spaces only,
--       none empty, across the LARGER state set.
axiom_EM6 :: Bool
axiom_EM6 =
     length (nub ws) == length ws
  && all (not . null) ws
  && all (all (\c -> c `elem` ['A' .. 'Z'] || c == ' ')) ws
  && length ws == length allStates
  where ws = map word allStates

-- (EM7) SM4 preserved: the terminals are EXACTLY the three
--       hardware refusals, even with four new states in play.
axiom_EM7 :: Bool
axiom_EM7 =
     all (\t -> null (successors t)) hardwareRefusals
  && [ s | s <- allStates, null (successors s) ] == sort hardwareRefusals
  && all (\r -> not (null (successors r)))
         [ Refused CameraOff, Refused ExportFailed, Refused Unknown ]

-- (EM8) ★ COHERENCE. Whatever sequence of edits arrives, what the
--       surface shows is the render of exactly ONE of them — the
--       last — and always lies in the image of render. No blend of
--       two edits, no partially-updated cube, is representable.
axiom_EM8 :: Bool
axiom_EM8 =
     all inImage sequences
  && all isLast sequences
  && shown 7 [] == Nothing
  && length (nub (legalSurface 7 space)) == length space
  where
    space     = [0 .. 31] :: [Edit]
    sequences = [ [3], [3, 9], [3, 9, 9], [0, 31, 12, 5], [31, 0] ]
    inImage es = case shown 7 es of
                   Nothing -> True
                   Just v  -> v `elem` legalSurface 7 space
    isLast es  = case shown 7 es of
                   Nothing -> null es
                   Just v  -> v == render 7 (last es)

-- (EM9) Reachability: every state is reachable from WAKING, and
--       no state is an orphan.
axiom_EM9 :: Bool
axiom_EM9 =
     sort (reachableFrom Waking) == sort allStates
  && all (\s -> s == Waking || not (null [ f | (f, t) <- edges, t == s ]))
         allStates

-- (EM10) ★ FORK FREEDOM: an unbounded number of GIFs per capture.
--        SEALED returns to TUNING, so the commit is a tap on the
--        shelf rather than an exit; the TUNING→SEALED→TUNING cycle
--        may be traversed arbitrarily often without re-capturing.
axiom_EM10 :: Bool
axiom_EM10 =
     canStep Tuning Sealed
  && canStep Sealed Tuning
  && Tuning `elem` reachableFrom Sealed
  && not (Weaving `elem` cycleStates)      -- no re-capture required
  && not (Solving `elem` cycleStates)
  where cycleStates = [Tuning, Sealed]

-- (EM11) Path independence: TUNING is entered from SOLVING (a
--        fresh capture) and from SHELVING (a stored one), and the
--        render is a function of (capture, edit) alone — so the
--        same capture re-opened later yields byte-identical GIFs.
axiom_EM11 :: Bool
axiom_EM11 =
     canStep Solving Tuning
  && canStep Shelving Tuning
  && and [ render c e == render c e | c <- caps, e <- eds ]
  && and [ (render c1 e == render c2 e) == (c1 == c2)
         | c1 <- caps, c2 <- caps, e <- eds ]
  && and [ (render c e1 == render c e2) == (e1 == e2)
         | c <- caps, e1 <- eds, e2 <- eds ]
  where caps = [1, 2, 3]
        eds  = [0, 5, 31]

-- (EM12) ★ WATCHING IS AN ABSTRACTION OF WEAVING — Daniel's ruling
--        (2026-08-13), in its strong form: RETENTION ONLY.
--
--          weave = watch + keep
--
--        The work is IDENTICAL — all three rungs encoded, palettes
--        solved, phase tiled — and the ONLY difference is that
--        WEAVING keeps the result. So the frame on the live surface
--        is not "like" the frame that will be exported; it IS that
--        frame, bit for bit (EM13).
--
--        The consequence for the port is not a merge but a
--        DELETION: DyadPreview is a second implementation of
--        DyadPipeline, and under this law a second implementation
--        cannot exist. There is one encoder. WATCHING calls it and
--        drops the result; WEAVING calls it and keeps it.
axiom_EM12 :: Bool
axiom_EM12 =
     watchPath 7 == weavePath 7                  -- one encoder
  && length rungsRead == 3                       -- all three rungs
  && rungsRead == [R64, R32, R16]
  && disposition Watching == Just Discarded
  && disposition Weaving  == Just Kept
  && [ s | s <- allStates, disposition s /= Nothing ] == [Watching, Weaving]
  && all (\s -> disposition s == Nothing || canStep s s || s == Weaving)
         allStates

-- (EM13) ★ THE PREVIEW IS THE GIF. Because the work is identical
--        and only retention differs, what the user judges while
--        WATCHING is exactly what WEAVING would have kept — so
--        there is no preview/export gap to reconcile, at any rung,
--        for any capture. A surface that could show something the
--        export would not produce is unrepresentable here.
axiom_EM13 :: Bool
axiom_EM13 =
     all (\c -> watchPath c == weavePath c) [0, 1, 7, 42]
  && all (\c -> map snd (watchPath c) == rungsRead) [0, 1, 7, 42]
  && watchPath 7 /= watchPath 8                  -- and it is capture-faithful
  && disposition Watching /= disposition Weaving  -- ONLY retention differs

-- ════════════════════════════════════════════════════════════════
-- § 5. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " EditMachine: the surface when EDIT is the whole app"
  putStrLn " capture is an input step; the shelf is home; tick = solve"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── The words ──"
  putStrLn ""
  mapM_ (\s -> putStrLn $ "  " ++ padR 18 (word s)
                       ++ (if interruptible s then "" else "  (holds)")
                       ++ (if s `elem` hardwareRefusals then "  (terminal)" else ""))
        allStates
  putStrLn ""

  putStrLn "── The arc ──"
  putStrLn ""
  putStrLn "                    (read 64∥32∥16)"
  putStrLn "                          ⟲"
  putStrLn "  WAKING → SHELF ⇄ WATCHING → WEAVING → SOLVING"
  putStrLn "                                            ↓"
  putStrLn "                        SHELF ⇄  TUNING ⟲ (tick)"
  putStrLn "                                    ⇅"
  putStrLn "                                 SEALED"
  putStrLn ""
  putStrLn $ "  states : " ++ show (length allStates)
  putStrLn $ "  edges  : " ++ show (length edges)
  putStrLn $ "  loops  : " ++ show [ word s | s <- allStates, canStep s s ]
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "EM1  the shelf is home; every non-terminal returns to it"  [axiom_EM1]
  check "EM2  ★ exactly TWO loops: WATCHING (read) + TUNING (tick)" [axiom_EM2]
  check "EM3  capture arc admits no skips (SM2 preserved)"          [axiom_EM3]
  check "EM4  capture-solve holds: WEAVING + SOLVING un-interrupt"  [axiom_EM4]
  check "EM5  ★ tick-solve is INTERRUPTIBLE (the SM3 split)"        [axiom_EM5]
  check "EM6  distinct square words over the larger set (SM1)"      [axiom_EM6]
  check "EM7  terminals are exactly the hardware refusals (SM4)"    [axiom_EM7]
  check "EM8  ★ coherence: shown = render(c, last e), never a blend"[axiom_EM8]
  check "EM9  reachability: no orphans, all reachable from WAKING"  [axiom_EM9]
  check "EM10 ★ fork freedom: unbounded GIFs per capture"           [axiom_EM10]
  check "EM11 path independence: render = f(capture, edit) only"    [axiom_EM11]
  check "EM12 ★ weave = watch + keep (RETENTION ONLY)"              [axiom_EM12]
  check "EM13 ★ THE PREVIEW IS THE GIF — no preview/export gap"     [axiom_EM13]
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  Two loops, not one. WATCHING reads the live feed at"
  putStrLn "  64³, 32³ and 16³ AT ONCE and compresses it as it"
  putStrLn "  arrives; WEAVING keeps what that same encoder makes."
  putStrLn "  One transform, two dispositions — no second preview"
  putStrLn "  path to drift out of sync."
  putStrLn ""
  putStrLn "  SM3 said the working states refuse interruption. That"
  putStrLn "  was one law doing two jobs. A capture-solve owns the"
  putStrLn "  only copy of a moment and must finish. A tick-solve"
  putStrLn "  owns a pure function of data already safely held, so"
  putStrLn "  it must be abandonable — otherwise the dial does not"
  putStrLn "  answer."
  putStrLn ""
  putStrLn "  Abandonment is safe because of coherence: the surface"
  putStrLn "  shows render(capture, edit) for an edit the user"
  putStrLn "  actually selected. Ticks are superseded, never queued,"
  putStrLn "  and a discarded tick costs only the compute spent."
  putStrLn ""
  putStrLn "  One moment. Unbounded GIFs. SEALED returns to TUNING."
  putStrLn "══════════════════════════════════════════════════════════"

padR :: Int -> String -> String
padR n s = s ++ replicate (max 0 (n - length s)) ' '

check :: String -> [Bool] -> IO ()
check name results =
  let passed = and results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
