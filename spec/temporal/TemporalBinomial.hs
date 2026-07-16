{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- TemporalBinomial: The R1 Axis as a Binomial Cadence
--
-- R1 ⊕ R3 = R4.  R1 is time. R3 is color. R4 is the tesseract.
--
-- The 4 epoch palettes don't snap at frames 0/16/32/48.
-- Instead, each frame z has a PROBABILITY DISTRIBUTION over
-- the 4 epochs: P(d|z) ∝ exp(-(z-μ_d)²/2σ²).
--
-- This single Gaussian model governs:
--   1. Where epoch boundaries fall (soft crossovers)
--   2. Per-color temporal counts (binomial per frame)
--   3. Cross-epoch transitions (smooth mixing)
--
-- All three are the same binomial viewed from different angles.
-- ════════════════════════════════════════════════════════════════

module TemporalBinomial where

import Data.Bits (xor, shiftR)
import Data.Char (chr)
import Data.List (sortBy, foldl', intercalate)
import Data.Ord (comparing, Down(..))
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import System.Directory (createDirectoryIfMissing)
import System.IO (withFile, IOMode(..), hSetBinaryMode, hPutStr)

-- ════════════════════════════════════════════════════════════════
-- § 1. TYPES
-- ════════════════════════════════════════════════════════════════

data SRGBColor = SRGBColor !Double !Double !Double deriving (Eq, Ord, Show)
data Spatial = Spatial !Int !Int deriving (Eq, Ord, Show)

-- | Temporal model: P(epoch d | frame z) for all frames
data TemporalModel = TemporalModel
  { tmProbs   :: !(Map Int [Double])  -- frame → [P(d=0), P(d=1), P(d=2), P(d=3)]
  , tmSigma   :: !Double
  , tmCenters :: ![Double]
  }

-- ════════════════════════════════════════════════════════════════
-- § 2. THE BINOMIAL TEMPORAL MODEL
-- ════════════════════════════════════════════════════════════════

-- | Epoch centers: equispaced across [0, 63]
--   μ_d = (2d + 1) × 63 / 8
epochCenters :: [Double]
epochCenters = [(2 * fromIntegral d + 1) * 63.0 / 8.0 | d <- [0..3]]
-- = [7.875, 23.625, 39.375, 55.125]

-- | Gaussian width: same for all epochs
sigma :: Double
sigma = 63.0 / 8.0  -- = 7.875

-- | Build the temporal model: P(d|z) for all 64 frames
buildTemporalModel :: TemporalModel
buildTemporalModel =
  let probs = Map.fromList
        [ (z, normalizeProbs [gaussian (fromIntegral z) mu sigma | mu <- epochCenters])
        | z <- [0..63] ]
  in TemporalModel probs sigma epochCenters

-- | Gaussian kernel (unnormalized)
gaussian :: Double -> Double -> Double -> Double
gaussian z mu sig = exp (-(z - mu)**2 / (2 * sig**2))

-- | Normalize probabilities to sum to 1
normalizeProbs :: [Double] -> [Double]
normalizeProbs ps = let s = sum ps in map (/ s) ps

-- | Get P(d|z) from the model
epochProb :: TemporalModel -> Int -> Int -> Double
epochProb tm z d = (tmProbs tm Map.! z) !! d

-- ════════════════════════════════════════════════════════════════
-- § 3. EPOCH SAMPLING
-- ════════════════════════════════════════════════════════════════

-- | Hash-based PRNG
pixelHash :: Int -> Int -> Int -> Int
pixelHash x y seed =
  let h0 = x * 374761393 + y * 668265263 + seed
      h1 = (h0 `xor` (h0 `shiftR` 15)) * 2246822519
      h2 = (h1 `xor` (h1 `shiftR` 13)) * 3266489917
  in abs (h2 `xor` (h2 `shiftR` 16))

hashToDouble :: Int -> Double
hashToDouble h = fromIntegral (abs h `mod` 1000000) / 1000000.0

-- | Sample an epoch from P(d|z) using a hash-derived uniform random number
sampleEpoch :: TemporalModel -> Int -> Int -> Int -> Int -> Int
sampleEpoch tm z x y seed =
  let probs = tmProbs tm Map.! z
      u = hashToDouble (pixelHash x y (seed + z * 997))
      -- CDF sampling: find the epoch where cumulative prob exceeds u
  in cdfSample probs u

cdfSample :: [Double] -> Double -> Int
cdfSample probs u = go 0 0
  where
    go d cumul
      | d >= length probs - 1 = d
      | cumul + (probs !! d) >= u = d
      | otherwise = go (d + 1) (cumul + (probs !! d))

-- ════════════════════════════════════════════════════════════════
-- § 4. TESSERACT PALETTE (4⁴ = 256)
-- ════════════════════════════════════════════════════════════════

quantize4D :: Int -> SRGBColor -> Int
quantize4D epoch (SRGBColor r g b) =
  let d = clamp 0 3 epoch
      a = clamp 0 3 (floor (r * 4))
      b' = clamp 0 3 (floor (g * 4))
      c = clamp 0 3 (floor (b * 4))
  in d * 64 + a * 16 + b' * 4 + c

lookupColor :: Int -> SRGBColor
lookupColor idx =
  let (_d, r1) = idx `divMod` 64
      (a, r2) = r1 `divMod` 16
      (b, c) = r2 `divMod` 4
  in SRGBColor ((fromIntegral a + 0.5) / 4.0)
               ((fromIntegral b + 0.5) / 4.0)
               ((fromIntegral c + 0.5) / 4.0)

clamp :: Int -> Int -> Int -> Int
clamp lo hi x = max lo (min hi x)

clamp01 :: Double -> Double
clamp01 v = max 0 (min 0.999 v)

-- ════════════════════════════════════════════════════════════════
-- § 5. GIF GENERATION WITH BINOMIAL CADENCE
-- ════════════════════════════════════════════════════════════════

-- | Generate all 64 frames using the binomial temporal model
generateGIF :: Int -> TemporalModel -> Map Int (Map (Int,Int) Int)
generateGIF seed tm =
  Map.fromList [(z, generateFrame seed tm z) | z <- [0..63]]

generateFrame :: Int -> TemporalModel -> Int -> Map (Int,Int) Int
generateFrame seed tm z =
  let base = Map.fromList
        [ ((x,y), computeColor seed tm z x y)
        | y <- [0..63], x <- [0..63] ]
  in injectAnchors seed tm z base

computeColor :: Int -> TemporalModel -> Int -> Int -> Int -> Int
computeColor seed tm z x y =
  let tx = fromIntegral x / 63.0
      ty = fromIntegral y / 63.0
      tz = fromIntegral z / 63.0
      -- Base image
      baseR = tx
      baseG = ty
      baseB = 0.5 + 0.3 * sin (pi * (tx + ty))
      -- Temporal perturbation
      (pr, pg, pb) = ( hashToDouble (pixelHash x y (seed + 999))
                     , hashToDouble (pixelHash x y (seed + 999 + 7919))
                     , hashToDouble (pixelHash x y (seed + 999 + 104729)) )
      amp = 0.12
      r = clamp01 (baseR + amp * sin (2 * pi * tz + pr * 2 * pi))
      g = clamp01 (baseG + amp * sin (2 * pi * tz + pg * 2 * pi))
      b = clamp01 (baseB + amp * sin (2 * pi * tz * 0.7 + pb * 2 * pi))
      -- SAMPLE epoch from P(d|z) — the binomial cadence
      epoch = sampleEpoch tm z x y seed
  in quantize4D epoch (SRGBColor r g b)

-- | Inject anchors with epoch-aware indices
injectAnchors :: Int -> TemporalModel -> Int -> Map (Int,Int) Int -> Map (Int,Int) Int
injectAnchors seed tm z pixels =
  let -- Sample epoch for anchor pixels too
      bEpoch = sampleEpoch tm z 0 0 (seed + 777)
      wEpoch = sampleEpoch tm z 63 63 (seed + 888)
      bIdx = bEpoch * 64           -- black = (d, 0, 0, 0)
      wIdx = wEpoch * 64 + 63      -- white = (d, 3, 3, 3)
      bx1 = (pixelHash 0 z (seed + 1)) `mod` 16
      by1 = (pixelHash 1 z (seed + 2)) `mod` 16
      bx2 = (pixelHash 2 z (seed + 3)) `mod` 16
      by2 = (pixelHash 3 z (seed + 4)) `mod` 16
      wx1 = 48 + (pixelHash 4 z (seed + 5)) `mod` 16
      wy1 = 48 + (pixelHash 5 z (seed + 6)) `mod` 16
      wx2 = 48 + (pixelHash 6 z (seed + 7)) `mod` 16
      wy2 = 48 + (pixelHash 7 z (seed + 8)) `mod` 16
  in Map.insert (bx1,by1) bIdx $ Map.insert (bx2,by2) bIdx
   $ Map.insert (wx1,wy1) wIdx $ Map.insert (wx2,wy2) wIdx
   $ pixels

-- ════════════════════════════════════════════════════════════════
-- § 6. TEMPORAL AXIOMS
-- ════════════════════════════════════════════════════════════════

eps :: Double
eps = 1e-10

-- (T1) P(d|z) sums to 1 for all z
axiom_T1_normalize :: TemporalModel -> Bool
axiom_T1_normalize tm =
  all (\z -> abs (sum (tmProbs tm Map.! z) - 1.0) < eps) [0..63]

-- (T2) P(d|z) is smooth: |P(d|z) - P(d|z+1)| < threshold for all z, d
axiom_T2_smooth :: TemporalModel -> Bool
axiom_T2_smooth tm =
  all (\z ->
    let p1 = tmProbs tm Map.! z
        p2 = tmProbs tm Map.! (z+1)
        maxJump = maximum (zipWith (\a b -> abs (a-b)) p1 p2)
    in maxJump < 0.10  -- less than 10% change per frame
    ) [0..62]

-- (T3) Epoch centers are equispaced
axiom_T3_equispaced :: Bool
axiom_T3_equispaced =
  let gaps = zipWith (-) (tail epochCenters) epochCenters
      meanGap = sum gaps / fromIntegral (length gaps)
  in all (\g -> abs (g - meanGap) < eps) gaps

-- (T4) Mixing is symmetric around each epoch center
-- (T4) Interior epochs (1,2) are symmetric around their centers.
--   Edge epochs (0,3) are truncated by [0,63] boundary — expected asymmetry.
axiom_T4_symmetric :: TemporalModel -> Bool
axiom_T4_symmetric tm =
  all (\(d, mu) ->
    let delta = 4.0
        zL = max 0 (round (mu - delta))
        zR = min 63 (round (mu + delta))
        pL = epochProb tm zL d
        pR = epochProb tm zR d
    in abs (pL - pR) < 0.05
    ) [(1, epochCenters !! 1), (2, epochCenters !! 2)]  -- only interior epochs

-- (T5) At crossovers: P(d) ≈ P(d+1) ≈ 0.5
axiom_T5_crossover :: TemporalModel -> Bool
axiom_T5_crossover tm =
  all (\(d, cross) ->
    let z = round cross
        pd = epochProb tm z d
        pd1 = epochProb tm z (d+1)
    in abs (pd - pd1) < 0.15  -- within 15% of each other
    ) [ (d, (epochCenters !! d + epochCenters !! (d+1)) / 2) | d <- [0..2] ]

-- (T6) Per-epoch "dominated" frame count ≈ 16
axiom_T6_epochCount :: TemporalModel -> Bool
axiom_T6_epochCount tm =
  let dominated d = length [z | z <- [0..63], epochProb tm z d > 0.4]
  in all (\d -> let n = dominated d in n >= 10 && n <= 22) [0..3]

-- (T7) Cross-boundary Jaccard ≈ within-boundary Jaccard
axiom_T7_smoothJaccard :: Map Int (Map (Int,Int) Int) -> Bool
axiom_T7_smoothJaccard frames =
  let jaccards = [srgbJaccard (frames Map.! z) (frames Map.! (z+1)) | z <- [0..62]]
      -- Old epoch boundaries were at z=15,31,47 — check they're no worse
      boundaryJ = [jaccards !! z | z <- [15, 31, 47]]
      interiorJ = [jaccards !! z | z <- [7, 23, 39, 55]]
      avgBoundary = avg boundaryJ
      avgInterior = avg interiorJ
  in avgBoundary > avgInterior * 0.5  -- boundaries at least half as coherent
  where
    srgbJaccard f1 f2 =
      let shared = length [() | ((x,y), c1) <- Map.toList f1
                          , case Map.lookup (x,y) f2 of
                              Just c2 -> lookupColor c1 == lookupColor c2
                              Nothing -> False]
      in fromIntegral shared / 4096.0

avg :: [Double] -> Double
avg [] = 0
avg xs = sum xs / fromIntegral (length xs)

-- ════════════════════════════════════════════════════════════════
-- § 7. PPM EXPORT
-- ════════════════════════════════════════════════════════════════

writePPM :: FilePath -> Map (Int,Int) Int -> IO ()
writePPM path frame = withFile path WriteMode $ \h -> do
  hSetBinaryMode h True
  hPutStr h "P6\n64 64\n255\n"
  mapM_ (\y -> mapM_ (\x -> do
    let idx = Map.findWithDefault 0 (x, y) frame
        SRGBColor r g b = lookupColor idx
    hPutStr h [chr (round (r*255)), chr (round (g*255)), chr (round (b*255))]
    ) [0..63]) [0..63]

exportFrames :: FilePath -> Map Int (Map (Int,Int) Int) -> IO ()
exportFrames dir frames =
  mapM_ (\z -> do
    let frame = frames Map.! z
        path = dir ++ "/frame_" ++ (if z < 10 then "0" else "") ++ show z ++ ".ppm"
    writePPM path frame
    ) [0..63]

-- ════════════════════════════════════════════════════════════════
-- § 8. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " TemporalBinomial: The R1 Axis as a Binomial Cadence"
  putStrLn " One model governs epoch placement, counts, and transitions."
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""

  let tm = buildTemporalModel

  -- Show the model
  putStrLn "── Temporal Model: P(epoch d | frame z) ──"
  putStrLn ""
  putStrLn $ "  σ = " ++ showF sigma
  putStrLn $ "  Epoch centers: " ++ intercalate ", " (map showF epochCenters)
  putStrLn ""

  -- Cadence visualization: ASCII plot of P(d|z) for each epoch
  putStrLn "  frame │ P(d=0) P(d=1) P(d=2) P(d=3) │ dominant │ cadence"
  putStrLn "  ──────┼────────────────────────────────┼──────────┼─────────────────"
  mapM_ (\z -> do
    let ps = tmProbs tm Map.! z
        dominant = snd $ maximum [(ps !! d, d) | d <- [0..3]]
        bar d = replicate (round (ps !! d * 20)) "▓░▒█" !! d
        cadenceBar = concat [replicate (max 0 (round (ps !! d * 15))) (("0123" !! d))
                            | d <- [0..3]]
    putStrLn $ "  " ++ padL 5 (show z)
            ++ " │ " ++ unwords [padL 5 (showF2 (ps !! d)) | d <- [0..3]]
            ++ " │ epoch " ++ show dominant
            ++ "  │ " ++ cadenceBar
    ) [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 63]
  putStrLn ""

  -- Crossover frames
  putStrLn "── Epoch Crossovers ──"
  putStrLn ""
  mapM_ (\d -> do
    let cross = (epochCenters !! d + epochCenters !! (d+1)) / 2
        z = round cross
        pd = epochProb tm z d
        pd1 = epochProb tm z (d+1)
    putStrLn $ "  Epoch " ++ show d ++ "→" ++ show (d+1)
            ++ " crossover at frame " ++ show z
            ++ ": P(" ++ show d ++ ")=" ++ showF pd
            ++ " P(" ++ show (d+1) ++ ")=" ++ showF pd1
    ) [0..2]
  putStrLn ""

  -- Generate GIF
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " GENERATING BINOMIAL-CADENCE GIF"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  let frames = generateGIF 42 tm
  putStrLn "  64 frames generated with soft epoch transitions."
  putStrLn ""

  -- Observed epoch distribution per frame
  putStrLn "── Observed Epoch Distribution (sample frames) ──"
  putStrLn ""
  putStrLn "  frame │ epoch0 │ epoch1 │ epoch2 │ epoch3 │ expected dominant"
  putStrLn "  ──────┼────────┼────────┼────────┼────────┼─────────────────"
  mapM_ (\z -> do
    let frame = frames Map.! z
        epochCounts = [length [() | c <- Map.elems frame, c `div` 64 == d] | d <- [0..3]]
        ps = tmProbs tm Map.! z
    putStrLn $ "  " ++ padL 5 (show z)
            ++ " │ " ++ unwords [padL 6 (show (epochCounts !! d)) | d <- [0..3]]
            ++ " │ " ++ show (snd (maximum [(ps !! d, d) | d <- [0..3]]))
    ) [0, 8, 15, 16, 17, 24, 31, 32, 33, 40, 47, 48, 49, 56, 63]
  putStrLn ""

  -- Jaccard coherence across ALL boundaries
  putStrLn "── Temporal Coherence (sRGB Jaccard per frame transition) ──"
  putStrLn ""
  let jaccards = [srgbJac (frames Map.! z) (frames Map.! (z+1)) | z <- [0..62]]
  putStrLn "  frame │ Jaccard │ bar"
  putStrLn "  ──────┼─────────┼──────────────────────────────"
  mapM_ (\z ->
    putStrLn $ "  " ++ padL 2 (show z) ++ "→" ++ padL 2 (show (z+1))
            ++ " │ " ++ padL 7 (showF (jaccards !! z))
            ++ " │ " ++ replicate (round (jaccards !! z * 50)) '█'
            ++ if z `elem` [15, 31, 47] then " ← old boundary" else ""
    ) [0, 7, 14, 15, 16, 23, 30, 31, 32, 39, 46, 47, 48, 55, 62]
  putStrLn ""
  let avgAll = avg jaccards
      avgBoundary = avg [jaccards !! z | z <- [15, 31, 47]]
      avgInterior = avg [jaccards !! z | z <- [7, 23, 39, 55]]
  putStrLn $ "  Mean Jaccard (all):        " ++ showF avgAll
  putStrLn $ "  Mean Jaccard (old bounds): " ++ showF avgBoundary
  putStrLn $ "  Mean Jaccard (interior):   " ++ showF avgInterior
  putStrLn $ "  Ratio boundary/interior:   " ++ showF (avgBoundary / avgInterior)
  putStrLn ""

  -- Axiom verification
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " AXIOM VERIFICATION"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  check "T1 Σ P(d|z) = 1 for all z" [axiom_T1_normalize tm]
  check "T2 P(d|z) is smooth (<10% change/frame)" [axiom_T2_smooth tm]
  check "T3 Epoch centers equispaced" [axiom_T3_equispaced]
  check "T4 Mixing symmetric around centers" [axiom_T4_symmetric tm]
  check "T5 Crossovers at ~50/50" [axiom_T5_crossover tm]
  check "T6 Per-epoch dominated frames ≈ 16" [axiom_T6_epochCount tm]
  check "T7 Boundary coherence ≥ 50% of interior" [axiom_T7_smoothJaccard frames]
  putStrLn ""

  -- Export
  putStrLn "── Exporting PPM frames ──"
  createDirectoryIfMissing True "_out/beautiful_gif"
  exportFrames "_out/beautiful_gif" frames
  putStrLn "  Done. 64 frames at spec/_out/beautiful_gif/"
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " THE CADENCE"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  The R1 axis is not 4 hard blocks."
  putStrLn "  It's 4 overlapping Gaussian bells:"
  putStrLn ""
  putStrLn "    P(d|z) ∝ exp(-(z-μ_d)²/2σ²)"
  putStrLn ""
  putStrLn "  At epoch centers: one bell dominates."
  putStrLn "  At crossovers: two bells share the frame."
  putStrLn "  The cadence IS the rhythm of these 4 bells."
  putStrLn ""
  putStrLn "  The same pixel can be epoch 0's red in frame 14"
  putStrLn "  and epoch 1's red in frame 17 — chosen by a coin"
  putStrLn "  flip weighted by the bell curves. No hard walls."
  putStrLn ""
  putStrLn "  This is R1 ⊕ R3 = R4 made continuous."
  putStrLn "══════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

srgbJac :: Map (Int,Int) Int -> Map (Int,Int) Int -> Double
srgbJac f1 f2 =
  let shared = length [() | ((x,y), c1) <- Map.toList f1
                      , case Map.lookup (x,y) f2 of
                          Just c2 -> lookupColor c1 == lookupColor c2
                          Nothing -> False]
  in fromIntegral shared / 4096.0

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 1000) :: Int) / 1000.0 :: Double)
          in take 7 (s ++ repeat '0')

showF2 :: Double -> String
showF2 x = let s = show (fromIntegral (round (x * 100) :: Int) / 100.0 :: Double)
           in take 5 (s ++ repeat '0')

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      n = length results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name ++ " (" ++ show n ++ " cases)"
