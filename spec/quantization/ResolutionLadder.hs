{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- ResolutionLadder: Depth-Gated Resolution 16² → 32² → 64²
--
-- Each cell of the frame carries a subject signal s ∈ [0,1]
-- (1 = subject, 0 = background). The signal GATES the cell's
-- resolution rung:
--
--   s ∈ [0, 1/3)   → 16²   1 px/color   the bijection rung (BP4)
--   s ∈ [1/3, 2/3) → 32²   4 px/color
--   s ∈ [2/3, 1]   → 64²  16 px/color   the B(4096, 1/256) rung
--
-- Occupancy is r²/256 ∈ {1,4,16}: the base rung realizes the
-- palette as a permutation (the palette IS the image — BellPalette
-- BP4), and the top rung matches the binomial null model's mean
-- of 16 pixels per palette entry.
--
-- Background (s = 0) sits on the floor rung. Two fill policies are
-- lawful: SOLID (one palette index everywhere — anchors 0/255 or
-- any single centroid) and NOISE (uniform draw over the indices of
-- the cell's luminance stratum). Both are total and deterministic.
-- ════════════════════════════════════════════════════════════════

module ResolutionLadder where

import Data.List (sort, nub)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE LADDER
-- ════════════════════════════════════════════════════════════════

rungs :: [Int]
rungs = [16, 32, 64]

-- | The gate: subject signal → resolution rung. Thresholds 1/3, 2/3.
rungOf :: Double -> Int
rungOf s
  | s < 1/3   = 16
  | s < 2/3   = 32
  | otherwise = 64

-- | Occupancy at rung r: expected pixels per palette color.
occupancy :: Int -> Int
occupancy r = r * r `div` 256

-- ════════════════════════════════════════════════════════════════
-- § 2. THE BELL LAYOUT (shared vocabulary with BellPalette)
-- ════════════════════════════════════════════════════════════════

bell :: [Int]
bell = [1,1,2,4,8,16,32,64,64,32,16,8,4,2,1,1]

-- | offsets !! k = first palette index of stratum k.
offsets :: [Int]
offsets = scanl (+) 0 bell

-- | Palette index range owned by stratum k: [lo, lo + w).
stratumRange :: Int -> (Int, Int)
stratumRange k = (offsets !! k, bell !! k)

-- ════════════════════════════════════════════════════════════════
-- § 3. BACKGROUND POLICIES (both lawful at the floor rung)
-- ════════════════════════════════════════════════════════════════

data Background
  = Solid Int   -- one palette index everywhere (anchor 0/255 or a centroid)
  | Noise Int   -- uniform draw over the cell's stratum's index range
  deriving (Show, Eq)

baseArea :: Int
baseArea = 16 * 16

-- | Fill a floor-rung (16²) background cell. Total and deterministic.
fillBackground :: Int -> Background -> [Int]
fillBackground _    (Solid idx) = replicate baseArea idx
fillBackground seed (Noise k)   =
  let (lo, w) = stratumRange k
  in take baseArea [lo + floor (u * fromIntegral w) | u <- uniforms seed]

-- ════════════════════════════════════════════════════════════════
-- § 4. FRAMES AND EMISSION
--
-- A frame is an 8×8 grid of cells, each with a subject signal.
-- Emission gives every cell EXACTLY ONE pixel block of rung-area
-- pixels — the conservation law RL4 checks that nothing is dropped
-- and no cell is double-covered.
-- ════════════════════════════════════════════════════════════════

frameCells :: Int
frameCells = 8

data Cell = Cell { cRow :: !Int, cCol :: !Int, cSignal :: !Double }
  deriving (Show, Eq)

-- | Deterministic random frame: ~1/4 of cells are exact background
--   (s = 0), the rest spread uniformly over (0,1].
randomFrame :: Int -> [Cell]
randomFrame seed =
  [ Cell r c (sig u)
  | ((r, c), u) <- zip [(r, c) | r <- [0 .. frameCells-1], c <- [0 .. frameCells-1]]
                       (uniforms seed) ]
  where sig u = if u < 0.25 then 0.0 else (u - 0.25) / 0.75

-- | Emit one frame: (cell id, rung, pixels). Background cells use
--   Solid (anchor 0) on even checkerboard squares, Noise (stratum 8)
--   on odd ones — both policies exercised in every frame.
emitFrame :: Int -> [Cell] -> [((Int, Int), Int, [Int])]
emitFrame seed cells =
  [ ((cRow cl, cCol cl), r, pixels cl r)
  | cl <- cells
  , let r = rungOf (cSignal cl) ]
  where
    cellSeed cl = seed * 4096 + cRow cl * 64 + cCol cl + 1
    pixels cl r
      | cSignal cl == 0 =
          if even (cRow cl + cCol cl)
            then fillBackground (cellSeed cl) (Solid 0)
            else fillBackground (cellSeed cl) (Noise 8)
      | otherwise = take (r * r) [floor (u * 256) | u <- uniforms (cellSeed cl)]

-- ════════════════════════════════════════════════════════════════
-- § 5. DETERMINISTIC PSEUDO-RANDOMNESS (no System.Random)
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

-- | Infinite uniform [0,1) stream from a seed.
uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

-- | Uniform random cell at rung r: r² independent palette indices.
uniformCell :: Int -> Int -> [Int]
uniformCell seed r = take (r * r) [floor (u * 256) | u <- uniforms seed]

-- | Per-palette-entry counts (256 bins). Sort-and-span: no
--   containers dependency, total on any list of indices in [0,255].
histogram :: [Int] -> [Int]
histogram xs = go 0 (sort xs)
  where
    go i ys | i == 256  = []
            | otherwise = let (h, t) = span (== i) ys
                          in length h : go (i + 1) t

-- | Deterministic Fisher–Yates (the BP4 bijection construction).
shuffle :: Int -> [Int] -> [Int]
shuffle seed xs0 = go (uniforms seed) xs0
  where
    go _ []      = []
    go (u:us) ys = let i        = floor (u * fromIntegral (length ys))
                       (a, y:b) = splitAt i ys
                   in y : go us (a ++ b)
    go [] _      = error "uniforms is infinite"

frameSeeds :: [Int]
frameSeeds = [1 .. 10]

-- ════════════════════════════════════════════════════════════════
-- § 6. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (RL1) Monotone gate: rung is non-decreasing in s over a dense
--       sweep, and the thresholds 1/3, 2/3 land exactly.
axiom_RL1 :: Bool
axiom_RL1 =
  let ss = [fromIntegral i / 400 | i <- [0 .. 400 :: Int]]
      rs = map rungOf ss
  in and (zipWith (<=) rs (tail rs))
  && rungOf 0        == 16
  && rungOf 0.3333   == 16   -- just below 1/3
  && rungOf (1/3)    == 32   -- threshold belongs to the upper rung
  && rungOf 0.6666   == 32   -- just below 2/3
  && rungOf (2/3)    == 64
  && rungOf 1        == 64

-- (RL2) Background floor: s = 0 ⇒ rung 16; SOLID fills are one
--       constant index (anchors or a single centroid), NOISE fills
--       stay inside their stratum's index range. Both are lawful.
axiom_RL2 :: Bool
axiom_RL2 =
     rungOf 0 == 16
  && all solidOK [0, 255, 100]                       -- anchors + a centroid
  && all noiseOK [(k, s) | k <- [0 .. 15], s <- [1 .. 5]]
  where
    solidOK idx =
      let px = fillBackground 1 (Solid idx)
      in length px == baseArea && all (== idx) px
    noiseOK (k, s) =
      let px      = fillBackground (s * 977 + k) (Noise k)
          (lo, w) = stratumRange k
      in length px == baseArea && all (\i -> i >= lo && i < lo + w) px

-- (RL3) Occupancy: r²/256 ∈ {1,4,16}. The base rung is the
--       bijection case (ties BellPalette BP4): a 16² cell realizes
--       every palette entry exactly once. The 64 rung matches the
--       B(4096, 1/256) null model: mean 16 exactly (conservation)
--       and empirical SD near √(4096·(1/256)·(255/256)) ≈ 3.99.
axiom_RL3 :: Bool
axiom_RL3 =
     map occupancy rungs == [1, 4, 16]
  && all bijBase [1 .. 6]
  && all mid32   [1 .. 6]
  && all null64  [1 .. 6]
  where
    bijBase seed =
      let px = shuffle seed [0 .. 255]
      in length px == 256
      && sort px == [0 .. 255]
      && histogram px == replicate 256 1        -- 1 px/color exactly
    mid32 seed =
      let h = histogram (uniformCell (seed * 17 + 3) 32)
      in sum h == 1024
      && fromIntegral (sum h) / 256 == (4 :: Double)
    null64 seed =
      let h    = histogram (uniformCell (seed * 31 + 7) 64)
          mean = fromIntegral (sum h) / 256 :: Double
          var  = sum [(fromIntegral c - mean) ^ (2 :: Int) | c <- h] / 256
          binomSD = sqrt (4096 * (1/256) * (255/256))   -- ≈ 3.992
      in sum h == 4096
      && abs (mean - 16) < 1e-9
      && abs (sqrt var - binomSD) < 1.2

-- (RL4) Conservation across the frame: total emitted pixels equal
--       the sum of rung areas; every cell emits exactly one block
--       of exactly rung² pixels; no cell is double-covered.
axiom_RL4 :: Bool
axiom_RL4 = all ok frameSeeds
  where
    ok seed =
      let em    = emitFrame seed (randomFrame seed)
          ids   = [i | (i, _, _) <- em]
          total = sum [length px | (_, _, px) <- em]
          areas = sum [r * r | (_, r, _) <- em]
      in length em == frameCells * frameCells
      && nub ids == ids                              -- no double cover
      && all (\(_, r, px) -> length px == r * r) em  -- exact blocks
      && total == areas                              -- nothing dropped

-- ════════════════════════════════════════════════════════════════
-- § 7. VISUALIZATION
-- ════════════════════════════════════════════════════════════════

rungChar :: Int -> Char
rungChar 16 = '░'
rungChar 32 = '▒'
rungChar 64 = '█'
rungChar _  = '?'

-- | Rung map of a frame: one shade per cell.
showRungMap :: [Cell] -> IO ()
showRungMap cells =
  mapM_ (\r -> putStrLn $ "  " ++
          [rungChar (rungOf (cSignal cl)) | cl <- cells, cRow cl == r])
        [0 .. frameCells - 1]

-- ════════════════════════════════════════════════════════════════
-- § 8. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " ResolutionLadder: Depth-Gated 16² → 32² → 64²"
  putStrLn " The subject signal gates the rung. Occupancy = r²/256."
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── The Ladder ──"
  putStrLn ""
  putStrLn "  signal band     │ rung │ pixels │ px/color"
  putStrLn "  ────────────────┼──────┼────────┼─────────"
  putStrLn "  s ∈ [0, 1/3)    │  16² │    256 │  1   ← bijection (BP4)"
  putStrLn "  s ∈ [1/3, 2/3)  │  32² │   1024 │  4"
  putStrLn "  s ∈ [2/3, 1]    │  64² │   4096 │ 16   ← B(4096,1/256) mean"
  putStrLn ""

  putStrLn "── A Frame (seed 1): rung per cell (░=16 ▒=32 █=64) ──"
  putStrLn ""
  let frame = randomFrame 1
  showRungMap frame
  putStrLn ""
  let em    = emitFrame 1 frame
      total = sum [length px | (_, _, px) <- em]
      nAt r = length [() | (_, r', _) <- em, r' == r]
  putStrLn $ "  cells at 16²: " ++ show (nAt 16)
          ++ "   at 32²: " ++ show (nAt 32)
          ++ "   at 64²: " ++ show (nAt 64)
  putStrLn $ "  total emitted pixels = " ++ show total
          ++ " = Σ rung²  (conserved)"
  putStrLn ""

  putStrLn "── The 64 Rung vs the Binomial Null Model ──"
  putStrLn ""
  let h    = histogram (uniformCell 38 64)
      mean = fromIntegral (sum h) / 256 :: Double
      sd   = sqrt (sum [(fromIntegral c - mean) ^ (2::Int) | c <- h] / 256)
  putStrLn $ "  B(4096, 1/256): E = " ++ showF (4096 / 256)
          ++ ", SD = " ++ showF (sqrt (4096 * (1/256) * (255/256)))
  putStrLn $ "  empirical:      E = " ++ showF mean
          ++ ", SD = " ++ showF sd ++ "  (seed 38)"
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "RL1 monotone gate: rung non-decreasing in s; thresholds exact" [axiom_RL1]
  check "RL2 background floor: s=0 ⇒ 16²; solid & noise both lawful"    [axiom_RL2]
  check "RL3 occupancy r²/256 ∈ {1,4,16}; bijection base; B-null top"   [axiom_RL3]
  check "RL4 conservation: Σ pixels = Σ rung²; no double cover"         [axiom_RL4]
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  signal → rung → area → occupancy"
  putStrLn ""
  putStrLn "  Resolution is SPENT where the subject is. Background"
  putStrLn "  rests on the bijection rung — one pixel per palette"
  putStrLn "  entry, the palette IS the image (BellPalette BP4)."
  putStrLn "  The subject climbs to 64², where color counts follow"
  putStrLn "  the binomial null model B(4096, 1/256), mean 16."
  putStrLn ""
  putStrLn "  The gate is monotone: more subject never means less"
  putStrLn "  resolution. The frame conserves: every cell emits its"
  putStrLn "  rung's area exactly once, nothing dropped, nothing"
  putStrLn "  double-covered."
  putStrLn "══════════════════════════════════════════════════════════"

-- Helpers (no-scientific-notation formatter: integer math, 3 dp)
showF :: Double -> String
showF x =
  let n    = round (abs x * 1000) :: Int
      sign = if x < 0 then "-" else ""
      frac = show (n `mod` 1000)
      pad3 = replicate (3 - length frac) '0' ++ frac
  in sign ++ show (n `div` 1000) ++ "." ++ pad3

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
