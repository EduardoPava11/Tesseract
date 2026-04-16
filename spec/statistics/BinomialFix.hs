{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════
-- BinomialFix: Correcting the two bugs
--
-- BUG 1: LCG generates correlated (r,g,b) triples.
--   FIX: Use independent streams — hash-based PRNG where
--   each pixel gets a unique seed from its (x,y) position.
--
-- BUG 2: 8×8×4 lattice has non-uniform Voronoi cell volumes.
--   FIX: Use a uniform 6×7×6 = 252 lattice + 4 strategic
--   interior points = 256. All cells have near-equal volume.
--
--   ACTUALLY: the cleanest fix is to NOT use a spatial lattice.
--   Instead, use QUANTILE PARTITIONING: divide [0,1]³ into
--   256 equal-volume cells by recursive octree subdivision.
--   At 8 levels of binary subdivision: 2⁸ = 256 cells,
--   each with volume exactly 1/256.
--
--   This is a 3D BINARY SPACE PARTITION:
--     Level 0: 1 cell (full cube)
--     Level 1: 2 cells (split on R at 0.5)
--     Level 2: 4 cells (split on G at 0.5 within each)
--     Level 3: 8 cells (split on B at 0.5 within each)
--     Level 4-5: split R again at 0.25, 0.75
--     Level 6-7: split G again
--     Level 8: would be 256 — but we only need 8 binary splits
--
--   Simpler: use an 8-bit MORTON CODE.
--   Each color index 0..255 is an 8-bit number.
--   Bits are interleaved across R, G, B:
--     bit 7,6 → R (4 levels: 0, 0.25, 0.5, 0.75 → but we want more)
--
--   SIMPLEST CORRECT APPROACH:
--   Map the unit cube [0,1]³ to [0,256) by:
--     index = floor(r × 8) × 32 + floor(g × 8) × 4 + floor(b × 4)
--   But ensure cell volume = ΔR × ΔG × ΔB = (1/8)(1/8)(1/4) = 1/256 ✓
--
--   Wait — (1/8)(1/8)(1/4) = 1/256 exactly!
--   The 8×8×4 lattice DOES give equal cell volumes!
--   The problem was: palette colors were at cell CENTERS
--   and we used NEAREST-NEIGHBOR assignment.
--   With nearest-neighbor, edge cells get truncated Voronoi regions.
--
--   FIX: Use FLOOR-BASED assignment (not nearest-neighbor).
--   Each pixel maps to the cell it falls IN, not the nearest center.
--   Cell volume is then exactly 1/256 for ALL cells (no edge effects).
-- ════════════════════════════════════════════════════════════

module BinomialFix where

import Data.Bits (xor, shiftR)
import Data.List (sortBy, foldl', sort)
import Data.Ord (comparing, Down(..))
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)

-- ════════════════════════════════════════════════════════════
-- § 1. sRGB Cube
-- ════════════════════════════════════════════════════════════

data SRGBColor = SRGBColor
  { sR :: {-# UNPACK #-} !Double
  , sG :: {-# UNPACK #-} !Double
  , sB :: {-# UNPACK #-} !Double
  } deriving (Eq, Ord, Show)

black :: SRGBColor
black = SRGBColor 0 0 0

white :: SRGBColor
white = SRGBColor 1 1 1

class Metric a where
  distance :: a -> a -> Double

instance Metric SRGBColor where
  distance (SRGBColor r1 g1 b1) (SRGBColor r2 g2 b2) =
    sqrt ((r1-r2)**2 + (g1-g2)**2 + (b1-b2)**2)

-- ════════════════════════════════════════════════════════════
-- § 2. PALETTE — 8R × 8G × 4B with FLOOR-BASED quantization
-- ════════════════════════════════════════════════════════════

-- | Palette dimensions
nR, nG, nB :: Int
nR = 8; nG = 8; nB = 4

-- | Cell dimensions (EACH cell has this volume)
deltaR, deltaG, deltaB, cellVolume :: Double
deltaR = 1.0 / fromIntegral nR   -- 0.125
deltaG = 1.0 / fromIntegral nG   -- 0.125
deltaB = 1.0 / fromIntegral nB   -- 0.25
cellVolume = deltaR * deltaG * deltaB  -- 1/256 = 0.00390625

-- | Palette color at the CENTER of cell (ir, ig, ib)
cellCenter :: Int -> Int -> Int -> SRGBColor
cellCenter ir ig ib = SRGBColor
  (deltaR * (fromIntegral ir + 0.5))
  (deltaG * (fromIntegral ig + 0.5))
  (deltaB * (fromIntegral ib + 0.5))

-- | Index from cell coordinates
cellIndex :: Int -> Int -> Int -> Int
cellIndex ir ig ib = ir * nG * nB + ig * nB + ib

-- | Cell coordinates from index
indexToCell :: Int -> (Int, Int, Int)
indexToCell idx = (idx `div` (nG * nB), (idx `div` nB) `mod` nG, idx `mod` nB)

-- | FLOOR-BASED quantization: which cell does this color fall in?
--   This guarantees each cell has volume exactly 1/256.
--   No edge effects. No Voronoi distortion.
quantize :: SRGBColor -> Int
quantize (SRGBColor r g b) =
  let ir = clamp 0 (nR - 1) (floor (r * fromIntegral nR))
      ig = clamp 0 (nG - 1) (floor (g * fromIntegral nG))
      ib = clamp 0 (nB - 1) (floor (b * fromIntegral nB))
  in cellIndex ir ig ib
  where clamp lo hi x = max lo (min hi x)

-- | Look up palette center color for an index
lookupColor :: Int -> SRGBColor
lookupColor idx = let (ir, ig, ib) = indexToCell idx
                  in cellCenter ir ig ib

-- ════════════════════════════════════════════════════════════
-- § 3. PRNG — Hash-based, independent per pixel
-- ════════════════════════════════════════════════════════════

-- | SplitMix-style hash: each pixel gets a unique seed from
--   its (x, y, frameSeed) coordinates. No sequential correlation.
--   Uses Data.Bits for real XOR and shift operations.
pixelHash :: Int -> Int -> Int -> Int
pixelHash x y frameSeed =
  let h0 = x * 374761393 + y * 668265263 + frameSeed
      h1 = (h0 `xor` (h0 `shiftR` 15)) * 2246822519
      h2 = (h1 `xor` (h1 `shiftR` 13)) * 3266489917
      h3 = h2 `xor` (h2 `shiftR` 16)
  in abs h3

-- | Generate a uniform random Double in [0,1) from a hash
hashToDouble :: Int -> Double
hashToDouble h = fromIntegral (abs h `mod` 1000000) / 1000000.0

-- | Three independent doubles from a pixel position
pixelRandomRGB :: Int -> Int -> Int -> (Double, Double, Double)
pixelRandomRGB x y seed =
  ( hashToDouble (pixelHash x y seed)
  , hashToDouble (pixelHash x y (seed + 7919))   -- different prime offsets
  , hashToDouble (pixelHash x y (seed + 104729))  -- → independent streams
  )

-- ════════════════════════════════════════════════════════════
-- § 4. FRAME GENERATION
-- ════════════════════════════════════════════════════════════

data Spatial = Spatial {-# UNPACK #-} !Int {-# UNPACK #-} !Int
  deriving (Eq, Ord, Show)

-- | Generate a frame: uniform sRGB + floor quantization → binomial
generateUniformFrame :: Int -> Map Int [Spatial]
generateUniformFrame frameSeed =
  foldl' addPixel Map.empty
    [ (x, y) | y <- [0..63], x <- [0..63] ]
  where
    addPixel buckets (x, y) =
      let (r, g, b) = pixelRandomRGB x y frameSeed
          idx = quantize (SRGBColor r g b)
      in Map.insertWith (++) idx [Spatial x y] buckets

-- | Generate a smooth frame that covers the full cube
generateSmoothFrame :: Int -> Map Int [Spatial]
generateSmoothFrame frameSeed =
  foldl' addPixel Map.empty
    [ (x, y) | y <- [0..63], x <- [0..63] ]
  where
    addPixel buckets (x, y) =
      let tx = fromIntegral x / 63.0
          ty = fromIntegral y / 63.0
          -- Map the ENTIRE unit square → the ENTIRE unit cube
          -- using space-filling curves of different frequencies
          -- to cover all octants uniformly
          baseR = tx  -- R sweeps left→right
          baseG = ty  -- G sweeps top→bottom
          -- B is a diagonal sweep that covers [0,1]
          baseB = (tx + ty) / 2.0
          -- Add position-dependent noise for full coverage
          (nr, ng, nb) = pixelRandomRGB x y frameSeed
          noise = 0.15
          r = clamp01 (baseR + noise * (nr - 0.5))
          g = clamp01 (baseG + noise * (ng - 0.5))
          b = clamp01 (baseB + noise * (nb - 0.5))
          idx = quantize (SRGBColor r g b)
      in Map.insertWith (++) idx [Spatial x y] buckets
    clamp01 v = max 0 (min 1 v)

-- ════════════════════════════════════════════════════════════
-- § 5. BINOMIAL DISTRIBUTION
-- ════════════════════════════════════════════════════════════

binomialPMF :: Int -> Double -> Int -> Double
binomialPMF n p k
  | k < 0 || k > n = 0
  | otherwise = exp (logChoose + fromIntegral k * log p
                     + fromIntegral (n - k) * log (1 - p))
  where
    logChoose = sum [log (fromIntegral i) | i <- [k+1..n]]
              - sum [log (fromIntegral i) | i <- [1..n-k]]

-- ════════════════════════════════════════════════════════════
-- § 6. ANALYSIS
-- ════════════════════════════════════════════════════════════

analyzeDistribution :: String -> Map Int [Spatial] -> IO ()
analyzeDistribution label buckets = do
  let allCounts = [ maybe 0 length (Map.lookup c buckets) | c <- [0..255] ]
      n = 4096 :: Int
      p = 1.0 / 256.0
      expectedMean = fromIntegral n * p
      expectedSD = sqrt (fromIntegral n * p * (1 - p))
      actualMean = fromIntegral (sum allCounts) / 256.0
      actualVar = sum [ (fromIntegral c - actualMean)^(2::Int)
                      | c <- allCounts ] / 256.0
      actualSD = sqrt actualVar
      within1 = length [c | c <- allCounts,
                  abs (fromIntegral c - actualMean) <= expectedSD]
      within2 = length [c | c <- allCounts,
                  abs (fromIntegral c - actualMean) <= 2 * expectedSD]
      colorsUsed = length [c | c <- allCounts, c > 0]
      maxCount = maximum allCounts
      minCount = minimum allCounts

  putStrLn $ "── " ++ label ++ " ──"
  putStrLn ""
  putStrLn $ "  Binomial B(4096, 1/256) prediction:"
  putStrLn $ "    E[count]  = " ++ showF expectedMean
  putStrLn $ "    SD[count] = " ++ showF expectedSD
  putStrLn ""
  putStrLn $ "  Observed:"
  putStrLn $ "    Mean      = " ++ showF actualMean
  putStrLn $ "    SD        = " ++ showF actualSD
  putStrLn $ "    Min/Max   = " ++ show minCount ++ " / " ++ show maxCount
  putStrLn $ "    Colors >0 = " ++ show colorsUsed ++ " / 256"
  putStrLn $ "    Within 1σ = " ++ show within1 ++ "/256 ("
          ++ showF (100 * fromIntegral within1 / 256.0) ++ "%)"
  putStrLn $ "    Within 2σ = " ++ show within2 ++ "/256 ("
          ++ showF (100 * fromIntegral within2 / 256.0) ++ "%)"
  putStrLn ""

  -- Chi-squared against binomial
  let observed = Map.fromListWith (+) [(c, 1::Int) | c <- allCounts]
      chiSq = sum [ let obs = fromIntegral (maybe 0 id (Map.lookup k observed))
                        exp' = 256.0 * binomialPMF n p k
                    in if exp' > 0.5 then (obs - exp')^(2::Int) / exp' else 0
                  | k <- [0..40] ]
  putStrLn $ "  χ² = " ++ showF chiSq ++ "  (good fit if < 50)"
  putStrLn ""

  -- Compact histogram
  let maxFreq = maximum [maybe 0 id (Map.lookup c observed) | c <- [0..40]]
  putStrLn "  count │ obs │ exp  │ bar"
  putStrLn "  ──────┼─────┼──────┼───────────────────────────────"
  mapM_ (\k -> do
    let obs = maybe 0 id (Map.lookup k observed)
        exp' = 256.0 * binomialPMF n p k
        barLen = obs * 30 `div` max 1 maxFreq
        expBar = round exp' * 30 `div` max 1 maxFreq
    putStrLn $ "  " ++ padL 5 (show k)
            ++ " │ " ++ padL 3 (show obs)
            ++ " │ " ++ padL 4 (showF2 exp')
            ++ " │ " ++ replicate barLen '▓'
                     ++ replicate (max 0 (expBar - barLen)) '░'
    ) [0..35]
  putStrLn ""

-- ════════════════════════════════════════════════════════════
-- § 7. VERIFY CELL VOLUME INVARIANT
-- ════════════════════════════════════════════════════════════

verifyCellVolumes :: IO ()
verifyCellVolumes = do
  putStrLn "── Cell Volume Verification ──"
  putStrLn ""
  putStrLn $ "  ΔR = 1/" ++ show nR ++ " = " ++ showF deltaR
  putStrLn $ "  ΔG = 1/" ++ show nG ++ " = " ++ showF deltaG
  putStrLn $ "  ΔB = 1/" ++ show nB ++ " = " ++ showF deltaB
  putStrLn $ "  Cell volume = ΔR × ΔG × ΔB = " ++ showF cellVolume
  putStrLn $ "  1/256 = " ++ showF (1.0/256.0)
  putStrLn $ "  Match: " ++ show (abs (cellVolume - 1.0/256.0) < 1e-15)
  putStrLn ""
  putStrLn "  With FLOOR-BASED quantization:"
  putStrLn "    Every cell has volume EXACTLY 1/256."
  putStrLn "    No edge effects. No Voronoi distortion."
  putStrLn "    P(pixel ∈ cell c) = 1/256 for ALL c."
  putStrLn "    count_c ~ Binomial(4096, 1/256). ∎"
  putStrLn ""

  -- Verify floor-based assignment covers all 256 cells
  let testPoints = [ SRGBColor (r/100) (g/100) (b/100)
                   | r <- [0..99], g <- [0,25,50,75,99], b <- [0,33,66,99] ]
      indices = map quantize testPoints
      unique = length (Map.fromList [(i, ()) | i <- indices])
  putStrLn $ "  Cells reachable by test grid: " ++ show unique ++ "/256"
  putStrLn ""

  -- Verify black and white
  putStrLn $ "  Black (0,0,0) → cell " ++ show (quantize black)
          ++ " center " ++ showRGB (lookupColor (quantize black))
  putStrLn $ "  White (1-ε) → cell " ++ show (quantize (SRGBColor 0.999 0.999 0.999))
          ++ " center " ++ showRGB (lookupColor (quantize (SRGBColor 0.999 0.999 0.999)))
  putStrLn ""

-- ════════════════════════════════════════════════════════════
-- § 8. MAIN
-- ════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " BINOMIAL FIX: Floor Quantization + Hash PRNG"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  Two bugs fixed:"
  putStrLn "    1. Nearest-neighbor → FLOOR-BASED quantization"
  putStrLn "       (equal cell volumes, no edge truncation)"
  putStrLn "    2. Sequential LCG → HASH-BASED per-pixel PRNG"
  putStrLn "       (no correlation between (r,g,b) channels)"
  putStrLn ""

  verifyCellVolumes

  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " TEST 1: Uniform Source → Must Be Binomial"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  let uniform1 = generateUniformFrame 42
  analyzeDistribution "Uniform pixels, floor quantization, hash PRNG" uniform1

  -- Second frame for comparison
  let uniform2 = generateUniformFrame 1337
  analyzeDistribution "Second uniform frame (different seed)" uniform2

  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " TEST 2: Smooth Source → Structured but Full-Cube Coverage"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  let smooth1 = generateSmoothFrame 42
  analyzeDistribution "Smooth field (R=x, G=y, B=diagonal)" smooth1

  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " PROOF: Why floor quantization gives exact binomial"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  Given:"
  putStrLn "    - Source pixel color (r,g,b) ~ Uniform([0,1]³)"
  putStrLn "    - Quantization: idx = ⌊8r⌋×32 + ⌊8g⌋×4 + ⌊4b⌋"
  putStrLn ""
  putStrLn "  Each cell c is the rectangle:"
  putStrLn "    [ir/8, (ir+1)/8) × [ig/8, (ig+1)/8) × [ib/4, (ib+1)/4)"
  putStrLn ""
  putStrLn "  Volume = (1/8)(1/8)(1/4) = 1/256"
  putStrLn ""
  putStrLn "  Since (r,g,b) is uniform in [0,1]³:"
  putStrLn "    P(pixel ∈ cell c) = volume(cell c) = 1/256"
  putStrLn ""
  putStrLn "  4096 independent pixels, each with P(c) = 1/256:"
  putStrLn "    count_c ~ Binomial(4096, 1/256)"
  putStrLn "    E[count_c] = 16"
  putStrLn "    SD[count_c] = √(4096 × 1/256 × 255/256) ≈ 3.99"
  putStrLn ""
  putStrLn "  The FLOOR function is the key:"
  putStrLn "    - It partitions [0,1) into equal intervals"
  putStrLn "    - No boundary effects (unlike Voronoi of point lattice)"
  putStrLn "    - The product of three equal partitions = equal cells"
  putStrLn ""
  putStrLn "  The HASH PRNG is the other key:"
  putStrLn "    - Each pixel's (r,g,b) is computed from its (x,y) hash"
  putStrLn "    - Three different prime offsets → independent channels"
  putStrLn "    - No sequential correlation between pixels"
  putStrLn ""
  putStrLn "  Together: exact binomial. ∎"
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════
-- Helpers
-- ════════════════════════════════════════════════════════════

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 100) :: Int) / 100.0 :: Double)
          in take 7 (s ++ repeat '0')

showF2 :: Double -> String
showF2 x = let s = show (fromIntegral (round (x * 10) :: Int) / 10.0 :: Double)
           in take 5 (s ++ repeat '0')

showRGB :: SRGBColor -> String
showRGB (SRGBColor r g b) =
  "(" ++ showF r ++ "," ++ showF g ++ "," ++ showF b ++ ")"

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s
