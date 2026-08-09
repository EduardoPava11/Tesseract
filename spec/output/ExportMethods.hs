{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- ExportMethods: The 64³ GIF Machine
--
-- The app is one machine: every export is 64 frames of 64×64
-- palette indices against a 256-entry table scheme. What varies is
-- the METHOD — how indices and tables are produced:
--
--   Tesseract  canonical 4⁴ lattice, one global table
--   Refined    lattice indices, pass-2 cell-clamped global table
--   Dyad       DYAD-256 paired per-frame local tables
--
-- Methods are selected by a SETTING and resolved by ELIGIBILITY:
-- a capture that cannot support a method falls down a fixed chain
-- that always terminates at Tesseract, which accepts anything.
--
-- PLACEMENT LAW: a method's law-bearing stages (tables, involution,
-- role masks) are exact; its pixel-assignment stage may run on an
-- approximate engine (ANE, fp16) that perturbs distances by at most
-- δ. Bounded perturbation can only flip assignments whose winning
-- gap is ≤ 2δ — near-ties, where either index is lawful — and can
-- never touch the role law, because the role select is exact.
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
-- § 2. METHODS, CAPTURES, ELIGIBILITY
-- ════════════════════════════════════════════════════════════════

data Method = Tesseract | Refined | Dyad
  deriving (Eq, Show, Enum, Bounded)

methods :: [Method]
methods = [minBound .. maxBound]

-- | Chain position: higher = richer method.
rank :: Method -> Int
rank = fromEnum

-- | What a capture can offer its method.
data Capture = Capture
  { hasRawRGB :: Bool     -- per-pixel color survives to export
  , hasDepth  :: Bool     -- face mask in the depth slot
  , nFrames   :: Int
  , side      :: Int
  } deriving (Eq, Show)

lawfulShape :: Capture -> Bool
lawfulShape c = nFrames c == machineFrames && side c == machineSide

-- | Dyad needs pixels and a mask; the lattice methods accept anything.
eligible :: Method -> Capture -> Bool
eligible Dyad c = hasRawRGB c && hasDepth c
eligible _    _ = True

fallback :: Method -> Maybe Method
fallback Dyad      = Just Refined
fallback Refined   = Just Tesseract
fallback Tesseract = Nothing

-- | Requested method → method actually run.
resolve :: Method -> Capture -> Method
resolve m c
  | eligible m c = m
  | otherwise    = maybe Tesseract (`resolve` c) (fallback m)

allCaptures :: [Capture]
allCaptures =
  [ Capture rgb d n s
  | rgb <- [False, True], d <- [False, True]
  , n <- [0, 1, machineFrames], s <- [1, machineSide] ]

-- ════════════════════════════════════════════════════════════════
-- § 3. THE SETTING (persisted string, total parse)
-- ════════════════════════════════════════════════════════════════

defaultMethod :: Method
defaultMethod = Dyad

render :: Method -> String
render Tesseract = "tesseract"
render Refined   = "refined"
render Dyad      = "dyad"

parse :: String -> Maybe Method
parse s = lookup s [(render m, m) | m <- methods]

parseOrDefault :: String -> Method
parseOrDefault = maybe defaultMethod id . parse

-- ════════════════════════════════════════════════════════════════
-- § 4. TABLE SCHEMES (what the GIF stream carries)
-- ════════════════════════════════════════════════════════════════

data TableScheme = GlobalTable | PerFrameTables
  deriving (Eq, Show)

scheme :: Method -> TableScheme
scheme Dyad = PerFrameTables
scheme _    = GlobalTable

-- | GIF89a image-descriptor packed byte under each scheme.
packedByte :: TableScheme -> Int
packedByte GlobalTable    = 0x00
packedByte PerFrameTables = 0x87   -- LCT present, 2^(7+1) = 256 entries

-- | Total palette bytes carried by one export.
tableBytes :: TableScheme -> Int
tableBytes GlobalTable    = 3 * machineEntries
tableBytes PerFrameTables = machineFrames * 3 * machineEntries

-- ════════════════════════════════════════════════════════════════
-- § 5. PLACEMENT MODEL — exact laws, approximate assignment
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
-- § 6. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (XM1) The machine: 64 × 64 × 64, 256 entries; scheme bytes fixed.
axiom_XM1 :: Bool
axiom_XM1 =
     machineSide == 64 && machineFrames == 64 && machinePixels == 4096
  && machineEntries == 256
  && tableBytes GlobalTable == 768
  && tableBytes PerFrameTables == 49152
  && packedByte GlobalTable == 0x00 && packedByte PerFrameTables == 0x87

-- (XM2) Resolution: total, lawful, terminating — the resolved
--       method is always eligible, and Tesseract resolves to itself
--       on every capture.
axiom_XM2 :: Bool
axiom_XM2 =
     and [ eligible (resolve m c) c | m <- methods, c <- allCaptures ]
  && and [ resolve Tesseract c == Tesseract | c <- allCaptures ]

-- (XM3) Monotone eligibility: a capture that gains capabilities
--       never resolves DOWN the chain.
axiom_XM3 :: Bool
axiom_XM3 =
  and [ rank (resolve m (richer c)) >= rank (resolve m c)
      | m <- methods, c <- allCaptures ]
  where richer c = c { hasRawRGB = True, hasDepth = True }

-- (XM4) The setting round-trips: parse ∘ render = Just, renders are
--       distinct, garbage parses to Nothing and defaults to Dyad.
axiom_XM4 :: Bool
axiom_XM4 =
     all (\m -> parse (render m) == Just m) methods
  && length (nub (map render methods)) == length methods
  && parse "garbage" == Nothing
  && parseOrDefault "garbage" == defaultMethod

-- (XM5) Scheme law: only Dyad carries per-frame tables.
axiom_XM5 :: Bool
axiom_XM5 = scheme Dyad == PerFrameTables
         && all (\m -> m == Dyad || scheme m == GlobalTable) methods

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
-- § 7. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " ExportMethods: the 64³ GIF machine"
  putStrLn " one shape, many methods, one setting, exact laws"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "── The method table ──"
  putStrLn ""
  putStrLn "  method     │ setting     │ needs        │ tables"
  putStrLn "  ───────────┼─────────────┼──────────────┼─────────────────"
  mapM_ (\m -> putStrLn $
          "  " ++ padR 10 (show m)
       ++ " │ " ++ padR 11 (render m)
       ++ " │ " ++ padR 12 (needs m)
       ++ " │ " ++ schemeDesc (scheme m))
        methods
  putStrLn ""
  putStrLn $ "  default = " ++ render defaultMethod
          ++ ";  fallback chain: dyad → refined → tesseract"
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "XM1 machine: 64×64×64, 256 entries, scheme bytes fixed"    [axiom_XM1]
  check "XM2 resolve: total, resolved method always eligible"       [axiom_XM2]
  check "XM3 monotone: gaining capabilities never demotes"          [axiom_XM3]
  check "XM4 setting: round-trip, distinct, garbage → default"      [axiom_XM4]
  check "XP1 roles on any engine: bg in σ-half, far bg = 255"       [axiom_XP1]
  check "XP2 near-tie law: gap > 2δ forces engine agreement"        [axiom_XP2]
  check "XM5 scheme: only Dyad carries per-frame tables"            [axiom_XM5]
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  The app is a 64³ GIF machine. Methods differ only in"
  putStrLn "  how indices and tables are made; the shape, the stream,"
  putStrLn "  and the setting are one. Eligibility resolves every"
  putStrLn "  request to a method that can run, ending at Tesseract."
  putStrLn ""
  putStrLn "  Placement is free where the law permits: tables and"
  putStrLn "  role masks are exact on the CPU; pixel assignment may"
  putStrLn "  run on an approximate engine, because a δ-bounded"
  putStrLn "  perturbation can only flip near-ties — and near-ties"
  putStrLn "  are lawful either way."
  putStrLn "══════════════════════════════════════════════════════════"
  where
    needs Dyad = "rgb + depth"
    needs _    = "indices"
    schemeDesc GlobalTable    = "1 × 768 B global"
    schemeDesc PerFrameTables = "64 × 768 B local"

check :: String -> [Bool] -> IO ()
check name results =
  let mark = if and results then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name

padR :: Int -> String -> String
padR n s = s ++ replicate (max 0 (n - length s)) ' '
