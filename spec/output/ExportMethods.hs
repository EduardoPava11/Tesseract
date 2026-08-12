{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- ExportMethods: The 64³ GIF Machine
--
-- The app is one machine: every export is 64 frames of 64×64
-- palette indices, and EVERY frame carries its own 256-entry Local
-- Color Table. DYAD-256 per-frame palettes are the ONLY export law
-- (Daniel's decree, 2026-08-12, non-negotiable): the tesseract and
-- refined global-table methods, their fallback chain, and the
-- persisted method setting are DELETED. A capture that cannot run
-- DYAD exports NOTHING — the refusal is honest (nil surfaced as an
-- error), never a silent downgrade to a global table.
--
-- PLACEMENT LAW (unchanged): the law-bearing stages (tables,
-- involution, role masks) are exact; the pixel-assignment stage may
-- run on an approximate engine (ANE, fp16) that perturbs distances
-- by at most δ. Bounded perturbation can only flip assignments
-- whose winning gap is ≤ 2δ — near-ties, where either index is
-- lawful — and can never touch the role law, because the role
-- select is exact.
-- ════════════════════════════════════════════════════════════════

module ExportMethods where

import Data.List (nub)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE MACHINE
-- ════════════════════════════════════════════════════════════════

machineSide, machineFrames, machineEntries, machinePixels :: Int
machineSide    = 64
machineFrames  = 64
machineEntries = 256
machinePixels  = machineSide * machineSide

-- ════════════════════════════════════════════════════════════════
-- § 2. THE ONE METHOD, CAPTURES, HONEST REFUSAL
-- ════════════════════════════════════════════════════════════════

data Method = Dyad
  deriving (Eq, Show, Enum, Bounded)

-- | What a capture can offer the machine.
data Capture = Capture
  { hasRawRGB :: Bool     -- per-pixel color survives to export
  , hasDepth  :: Bool     -- face mask in the depth slot
  , nFrames   :: Int
  , side      :: Int
  } deriving (Eq, Show)

lawfulShape :: Capture -> Bool
lawfulShape c = nFrames c == machineFrames && side c == machineSide

-- | Dyad needs pixels and a mask.
eligible :: Capture -> Bool
eligible c = hasRawRGB c && hasDepth c

-- | Requested export → what actually happens. No fallback chain:
--   an ineligible capture exports Nothing, honestly.
export :: Capture -> Maybe Method
export c = if eligible c then Just Dyad else Nothing

allCaptures :: [Capture]
allCaptures =
  [ Capture rgb d n s
  | rgb <- [False, True], d <- [False, True]
  , n <- [0, 1, machineFrames], s <- [1, machineSide] ]

-- ════════════════════════════════════════════════════════════════
-- § 3. THE TABLE SCHEME (what the GIF stream carries — always)
-- ════════════════════════════════════════════════════════════════

-- | GIF89a image-descriptor packed byte: LCT present, 2^(7+1) = 256
--   entries — on EVERY frame of EVERY export.
packedByte :: Int
packedByte = 0x87

-- | Total palette bytes carried by one export: one 768-byte Local
--   Color Table per frame (frame 0's table doubles as the GCT).
tableBytes :: Int
tableBytes = machineFrames * 3 * machineEntries

-- ════════════════════════════════════════════════════════════════
-- § 4. PLACEMENT MODEL — exact laws, approximate assignment
--
-- The engine model: assignment sees distances d_j + e_j with
-- |e_j| ≤ δ (fp16 input rounding ≈ 1e-3 in OKLab units). The role
-- select (face/background) is exact on every engine.
-- ════════════════════════════════════════════════════════════════

-- | Exact nearest: minimum distance, ties → LOWEST index.
exactAssign :: [Double] -> Int
exactAssign ds = snd (minimum (zip ds [0 ..]))

-- | Assignment under a bounded perturbation.
approxAssign :: [Double] -> [Double] -> Int
approxAssign ds es = exactAssign (zipWith (+) ds es)

-- | Winning gap: runner-up minus winner.
gap :: [Double] -> Double
gap ds = case take 2 (nub (sortAsc ds)) of
  (a : b : _) -> b - a
  _           -> 1 / 0        -- all equal: any index is the winner
  where sortAsc = foldr insert []
        insert x [] = [x]
        insert x (y : ys) = if x <= y then x : y : ys else y : insert x ys

-- | One pixel through the role stage (bleed v2): face pixels take
--   the (possibly approximate) argmin; background pixels take its
--   σ-mirror 255 − argmin; FULLY PULLED background bypasses
--   assignment entirely — an exact select, engine-independent.
rolePixel :: Bool -> Bool -> [Double] -> [Double] -> Int
rolePixel isFace far ds es
  | isFace    = approxAssign ds es
  | far       = machineEntries - 1
  | otherwise = machineEntries - 1 - approxAssign ds es

-- Deterministic pseudo-random trials (no System.Random)
lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

delta :: Double
delta = 1e-3

-- | 200 trials: 128 distances in [0,1), perturbations in [−δ, δ].
trials :: [([Double], [Double])]
trials =
  [ ( take 128 (uniforms (2 * t + 1))
    , map (\u -> (2 * u - 1) * delta) (take 128 (uniforms (2 * t + 2))) )
  | t <- [1 .. 200] ]

-- ════════════════════════════════════════════════════════════════
-- § 5. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (XM1) The machine: 64 × 64 × 64, 256 entries; the wire scheme is
--       per-frame LCTs, 49152 palette bytes per export, packed
--       byte 0x87 — there is no global-table row to describe.
axiom_XM1 :: Bool
axiom_XM1 =
     machineSide == 64 && machineFrames == 64 && machinePixels == 4096
  && machineEntries == 256
  && tableBytes == 49152
  && packedByte == 0x87

-- (XM2) Honest refusal: export produces Dyad exactly on eligible
--       captures and Nothing otherwise — no capture is ever served
--       by a method it cannot lawfully run, and no fallback exists.
axiom_XM2 :: Bool
axiom_XM2 =
     and [ (export c == Just Dyad) == eligible c | c <- allCaptures ]
  && and [ (export c == Nothing) == not (eligible c) | c <- allCaptures ]

-- (XM3) Monotone eligibility: a capture that gains capabilities
--       never loses its export.
axiom_XM3 :: Bool
axiom_XM3 =
  and [ maybe True (const (export (richer c) == Just Dyad)) (export c)
      | c <- allCaptures ]
  where richer c = c { hasRawRGB = True, hasDepth = True }

-- (XM4) One method: Dyad is the whole method space.
axiom_XM4 :: Bool
axiom_XM4 = [minBound .. maxBound] == [Dyad]

-- (XP1) Role law under ANY engine: fully pulled background is 255
--       exactly; bleed-band background stays inside the complement
--       half 128..255, no matter how distances are perturbed.
axiom_XP1 :: Bool
axiom_XP1 =
     all (\(ds, es) -> rolePixel False True ds es == 255) trials
  && all (\(ds, es) -> let i = rolePixel False False ds es
                       in i >= 128 && i <= 255) trials

-- (XP2) Near-tie law, both directions: a winning gap > 2δ forces
--       exact agreement; every disagreement has gap ≤ 2δ.
axiom_XP2 :: Bool
axiom_XP2 = all ok trials
  where
    ok (ds, es) =
      let agree = approxAssign ds es == exactAssign ds
      in (gap ds <= 2 * delta) || agree      -- gap > 2δ ⇒ agree
      && (agree || gap ds <= 2 * delta)      -- disagree ⇒ near-tie

-- ════════════════════════════════════════════════════════════════
-- § 6. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " ExportMethods: the 64³ GIF machine"
  putStrLn " one shape, ONE method, per-frame palettes, exact laws"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  method │ needs        │ tables"
  putStrLn "  ───────┼──────────────┼─────────────────"
  putStrLn "  Dyad   │ rgb + depth  │ 64 × 768 B local (0x87)"
  putStrLn ""
  putStrLn "  no fallback chain: ineligible capture → Nothing (honest)"
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "XM1 machine: 64×64×64, 256 entries, per-frame LCTs 0x87"    [axiom_XM1]
  check "XM2 honest refusal: Dyad iff eligible, else Nothing"        [axiom_XM2]
  check "XM3 monotone: gaining capabilities never loses the export"  [axiom_XM3]
  check "XM4 one method: Dyad is the whole method space"             [axiom_XM4]
  check "XP1 roles on any engine: bg in σ-half, far bg = 255"        [axiom_XP1]
  check "XP2 near-tie law: gap > 2δ forces engine agreement"         [axiom_XP2]
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  The app is a 64³ GIF machine with ONE law: every frame"
  putStrLn "  carries its own palette. A capture that cannot support"
  putStrLn "  the law is refused honestly — never downgraded."
  putStrLn ""
  putStrLn "  Placement is free where the law permits: tables and"
  putStrLn "  role masks are exact on the CPU; pixel assignment may"
  putStrLn "  run on an approximate engine, because a δ-bounded"
  putStrLn "  perturbation can only flip near-ties — and near-ties"
  putStrLn "  are lawful either way."
  putStrLn "══════════════════════════════════════════════════════════"

check :: String -> [Bool] -> IO ()
check name results =
  let mark = if and results then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
