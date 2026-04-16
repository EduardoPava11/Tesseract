{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- GIFAnalysis: Rate a GIF Against the 4⁴ Tesseract Spec
--
-- Reads 64 PPM frames, analyzes:
--   1. Palette fidelity (how close to the 4³=64 sRGB lattice)
--   2. Epoch distribution (does it follow binomial cadence?)
--   3. Temporal coherence (smooth transitions?)
--   4. Birkhoff M = O/C (beauty measure)
--   5. Manifold dimension (what kind of image?)
--   6. Depth-SNR evidence (center stable, edges volatile?)
--   7. Overall grade A-F
-- ════════════════════════════════════════════════════════════════

module GIFAnalysis where

import Data.Char (ord, chr)
import Data.List (sort, group, sortBy, foldl', nub, minimumBy)
import qualified Data.ByteString as BS
import Data.Word (Word8)
import Data.Ord (comparing, Down(..))
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)

-- ════════════════════════════════════════════════════════════════
-- § 1. PPM READER
-- ════════════════════════════════════════════════════════════════

type RGB = (Int, Int, Int)  -- 0-255 per channel

readPPM :: FilePath -> IO [RGB]
readPPM path = do
  raw <- BS.readFile path
  let bytes = map fromIntegral (BS.unpack raw) :: [Int]
      dataStart = skipHeader bytes 0 0
      pixelBytes = drop dataStart bytes
  return $ extractPixels pixelBytes
  where
    skipHeader bs pos nl
      | nl >= 3 = pos
      | pos >= length bs = pos
      | bs !! pos == 10 = skipHeader bs (pos+1) (nl+1)
      | otherwise = skipHeader bs (pos+1) nl
    extractPixels [] = []
    extractPixels (r:g:b:rest) = (r, g, b) : extractPixels rest
    extractPixels _ = []

-- ════════════════════════════════════════════════════════════════
-- § 2. TESSERACT LATTICE (4³ = 64 sRGB colors)
-- ════════════════════════════════════════════════════════════════

-- | The 64 sRGB display colors from the tesseract
--   Each at center of its 4×4×4 cell: (a+0.5)/4 for a ∈ {0,1,2,3}
latticeColors :: [RGB]
latticeColors =
  [ ( round ((fromIntegral a + 0.5) / 4.0 * 255)
    , round ((fromIntegral b + 0.5) / 4.0 * 255)
    , round ((fromIntegral c + 0.5) / 4.0 * 255) )
  | a <- [0..3], b <- [0..3], c <- [0..3 :: Int] ]

-- | Map an RGB pixel to the nearest tesseract lattice index (0-63)
nearestLattice :: RGB -> (Int, Double)  -- (index, distance)
nearestLattice (r, g, b) =
  let dists = [ (i, dist (r,g,b) lc) | (i, lc) <- zip [0..] latticeColors ]
  in minimumBy (comparing snd) dists
  where
    dist (r1,g1,b1) (r2,g2,b2) =
      sqrt (fromIntegral ((r1-r2)^(2::Int) + (g1-g2)^(2::Int) + (b1-b2)^(2::Int)))

-- | Quantize RGB to tesseract (a,b,c) cell
quantizeToCell :: RGB -> (Int, Int, Int)
quantizeToCell (r, g, b) =
  ( min 3 (r * 4 `div` 256)
  , min 3 (g * 4 `div` 256)
  , min 3 (b * 4 `div` 256) )

-- ════════════════════════════════════════════════════════════════
-- § 3. ANALYSIS FUNCTIONS
-- ════════════════════════════════════════════════════════════════

-- | Palette fidelity: how many unique lattice colors used, mean quant error
paletteFidelity :: [[RGB]] -> (Int, Double, Int)
paletteFidelity frames =
  let allPixels = concat frames
      mapped = map nearestLattice allPixels
      usedIndices = nub (map fst mapped)
      meanError = sum (map snd mapped) / fromIntegral (length mapped)
      uniqueRaw = length (nub allPixels)
  in (length usedIndices, meanError, uniqueRaw)

-- | Per-frame color histogram (64 bins = lattice colors)
frameHistogram :: [RGB] -> Map Int Int
frameHistogram pixels =
  Map.fromListWith (+) [(fst (nearestLattice p), 1) | p <- pixels]

-- | Birkhoff M = O/C for a frame
birkhoffFrame :: [RGB] -> (Double, Double, Double, Double)  -- (M, O, C, dim)
birkhoffFrame pixels =
  let hist = frameHistogram pixels
      total = fromIntegral (length pixels) :: Double
      -- All 64 bins (with zeros)
      allCounts = [Map.findWithDefault 0 i hist | i <- [0..63]]
      expected = total / 64.0
      -- Order: deviation from uniform
      order = sqrt (sum [(fromIntegral c - expected)^(2::Int) | c <- allCounts])
      -- Complexity: normalized entropy
      probs = [fromIntegral c / total | c <- allCounts, c > 0]
      entropy = negate (sum [p * log p | p <- probs, p > 0])
      maxEntropy = log 64.0
      complexity = entropy / maxEntropy
      -- Manifold dim
      participation = 1.0 / sum [p*p | p <- probs]
      prNorm = log (max 1 participation) / log 64.0
      dim = 3.0 * (0.6 * (entropy / maxEntropy) + 0.4 * prNorm)
  in (order / max complexity 0.001, order, complexity, dim)

-- | Temporal coherence: Jaccard between adjacent frames (lattice-projected)
temporalCoherence :: [[RGB]] -> [Double]
temporalCoherence frames =
  zipWith jaccard frames (tail frames)
  where
    jaccard f1 f2 =
      let q1 = map quantizeToCell f1
          q2 = map quantizeToCell f2
          shared = length [() | (a, b) <- zip q1 q2, a == b]
      in fromIntegral shared / fromIntegral (length f1)

-- | Depth-SNR evidence: center pixels should be more stable than edge pixels
depthSNREvidence :: [[RGB]] -> (Double, Double)  -- (center_stability, edge_stability)
depthSNREvidence frames =
  let -- Quantize all frames to lattice
      quantized = map (map quantizeToCell) frames
      -- For each pixel position, count how many frames it stays the same as previous
      nFrames = length frames
      -- Center region: 24-40 in both x and y (16×16 = 256 pixels)
      centerPixels = [(x, y) | x <- [24..39], y <- [24..39]]
      -- Edge region: first/last 8 rows and columns
      edgePixels = [(x, y) | x <- [0..63], y <- [0..63],
                    x < 8 || x >= 56 || y < 8 || y >= 56]
      -- Stability = fraction of adjacent frames where pixel doesn't change
      pixelStability pos =
        let vals = [((quantized !! f) !! (snd pos * 64 + fst pos)) | f <- [0..nFrames-1]]
            stable = length [() | (a, b) <- zip vals (tail vals), a == b]
        in fromIntegral stable / fromIntegral (nFrames - 1)
      centerStab = avg (map pixelStability centerPixels)
      edgeStab = avg (map pixelStability edgePixels)
  in (centerStab, edgeStab)

avg :: [Double] -> Double
avg [] = 0
avg xs = sum xs / fromIntegral (length xs)

-- ════════════════════════════════════════════════════════════════
-- § 4. GRADING
-- ════════════════════════════════════════════════════════════════

data GIFGrade = GIFGrade
  { grPaletteCoverage  :: Double  -- fraction of 64 colors used
  , grQuantError       :: Double  -- mean distance to lattice
  , grBirkhoffM        :: Double  -- beauty measure
  , grManifoldDim      :: Double  -- expected ~1.5-2.0 for face
  , grCoherence        :: Double  -- mean Jaccard
  , grDepthSNR         :: Double  -- center/edge stability ratio
  , grOverall          :: Char    -- A-F
  } deriving (Show)

gradeGIF :: Int -> Double -> Double -> Double -> Double -> Double -> GIFGrade
gradeGIF nColors quantErr birkhoffM dim coherence depthRatio =
  let coverage = fromIntegral nColors / 64.0
      -- Score each metric 0-100
      sCoverage  = min 100 (coverage * 100)
      sQuant     = max 0 (100 - quantErr * 2)  -- lower error = higher score
      sBirkhoff  = min 100 (birkhoffM / 10)  -- scale appropriately
      sDim       = if dim >= 1.0 && dim <= 2.5 then 80 else 40  -- face range
      sCoherence = min 100 (coherence * 120)  -- 0.83 → 100
      sDepth     = if depthRatio > 1.0 then 80 else 40  -- center more stable
      total = (sCoverage + sQuant + sBirkhoff + sDim + sCoherence + sDepth) / 6
      grade | total >= 80 = 'A'
            | total >= 65 = 'B'
            | total >= 50 = 'C'
            | total >= 35 = 'D'
            | otherwise   = 'F'
  in GIFGrade coverage quantErr birkhoffM dim coherence depthRatio grade

-- ════════════════════════════════════════════════════════════════
-- § 5. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " GIF Analysis: Tesseract 4⁴ Spec Compliance Report"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  -- Read all 64 frames
  putStrLn "  Reading 64 frames..."
  frames <- mapM (\i ->
    let path = "/tmp/gif_analysis/frame_" ++ padNum i ++ ".ppm"
    in readPPM path
    ) [1..64]
  let nFrames = length frames
  let pixelsPerFrame = length (head frames)
  putStrLn $ "  Frames: " ++ show nFrames
  putStrLn $ "  Pixels/frame: " ++ show pixelsPerFrame
  putStrLn ""

  -- 1. Palette Fidelity
  putStrLn "── 1. PALETTE FIDELITY ──"
  putStrLn ""
  let (nLattice, meanErr, nUniqueRaw) = paletteFidelity frames
  putStrLn $ "  Unique raw RGB colors: " ++ show nUniqueRaw
  putStrLn $ "  Mapped to lattice:     " ++ show nLattice ++ " / 64"
  putStrLn $ "  Mean quant error:      " ++ showF meanErr ++ " (0 = perfect lattice hit)"
  putStrLn ""

  -- Show top colors
  let allHist = Map.fromListWith (+)
        [(fst (nearestLattice p), 1::Int) | f <- frames, p <- f]
      topColors = take 10 (sortBy (comparing (Down . snd)) (Map.toList allHist))
  putStrLn "  Top 10 colors (lattice index, count, sRGB):"
  mapM_ (\(idx, cnt) -> do
    let (r, g, b) = latticeColors !! idx
    putStrLn $ "    [" ++ padL 2 (show idx) ++ "] "
            ++ padL 7 (show cnt) ++ " px  ("
            ++ padL 3 (show r) ++ "," ++ padL 3 (show g) ++ "," ++ padL 3 (show b) ++ ")"
    ) topColors
  putStrLn ""

  -- 2. Birkhoff Measure
  putStrLn "── 2. BIRKHOFF M = O/C ──"
  putStrLn ""
  let frameMeasures = map birkhoffFrame frames
      (ms, os, cs, ds) = unzip4 frameMeasures
      avgM = avg ms; avgO = avg os; avgC = avg cs; avgDim = avg ds
  putStrLn $ "  Mean Beauty (M):    " ++ showF avgM
  putStrLn $ "  Mean Order (O):     " ++ showF avgO
  putStrLn $ "  Mean Complexity(C): " ++ showF avgC
  putStrLn $ "  Mean Manifold dim:  " ++ showF avgDim
  putStrLn ""
  putStrLn "  Per-frame M (sample):"
  mapM_ (\z -> do
    let (m, o, c, d) = frameMeasures !! z
    putStrLn $ "    frame " ++ padL 2 (show z)
            ++ " │ M=" ++ padL 7 (showF m)
            ++ " O=" ++ padL 7 (showF o)
            ++ " C=" ++ padL 5 (showF c)
            ++ " dim=" ++ showF d
    ) [0, 8, 16, 24, 32, 48, 63]
  putStrLn ""

  -- 3. Temporal Coherence
  putStrLn "── 3. TEMPORAL COHERENCE ──"
  putStrLn ""
  let jaccards = temporalCoherence frames
      avgJ = avg jaccards
      minJ = minimum jaccards
      maxJ = maximum jaccards
  putStrLn $ "  Mean Jaccard:  " ++ showF avgJ
  putStrLn $ "  Min Jaccard:   " ++ showF minJ
  putStrLn $ "  Max Jaccard:   " ++ showF maxJ
  putStrLn ""
  putStrLn "  Per-transition (sample):"
  mapM_ (\z ->
    putStrLn $ "    " ++ padL 2 (show z) ++ "→" ++ padL 2 (show (z+1))
            ++ " │ " ++ showF (jaccards !! z)
            ++ "  " ++ replicate (round (jaccards !! z * 40)) '█'
    ) [0, 7, 15, 16, 31, 32, 47, 48, 62]
  putStrLn ""

  -- 4. Depth-SNR Evidence
  putStrLn "── 4. DEPTH-SNR EVIDENCE ──"
  putStrLn ""
  let (centerStab, edgeStab) = depthSNREvidence frames
      snrRatio = centerStab / max edgeStab 0.001
  putStrLn $ "  Center stability (face):       " ++ showF centerStab
  putStrLn $ "  Edge stability (background):   " ++ showF edgeStab
  putStrLn $ "  Ratio (center/edge):           " ++ showF snrRatio
  if snrRatio > 1.0
    then putStrLn "  ★ Center MORE stable → depth-SNR IS working"
    else putStrLn "  ✗ Center NOT more stable → depth-SNR may not be effective"
  putStrLn ""

  -- 5. Overall Grade
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " REPORT CARD"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  let grade = gradeGIF nLattice meanErr avgM avgDim avgJ snrRatio
  putStrLn $ "  Palette coverage:  " ++ showF (grPaletteCoverage grade * 100) ++ "%"
          ++ " (" ++ show nLattice ++ "/64 colors)"
  putStrLn $ "  Quant error:       " ++ showF (grQuantError grade)
  putStrLn $ "  Birkhoff M:        " ++ showF (grBirkhoffM grade)
  putStrLn $ "  Manifold dim:      " ++ showF (grManifoldDim grade)
  putStrLn $ "  Coherence:         " ++ showF (grCoherence grade)
  putStrLn $ "  Depth SNR ratio:   " ++ showF (grDepthSNR grade)
  putStrLn ""
  putStrLn $ "  ╔═══════════════════════╗"
  putStrLn $ "  ║  GRADE:  " ++ [grOverall grade] ++ "            ║"
  putStrLn $ "  ╚═══════════════════════╝"
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 100) :: Int) / 100.0 :: Double)
          in take 7 (s ++ repeat '0')

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

padNum :: Int -> String
padNum n | n < 10 = "00" ++ show n
         | n < 100 = "0" ++ show n
         | otherwise = show n

unzip4 :: [(a,b,c,d)] -> ([a],[b],[c],[d])
unzip4 [] = ([],[],[],[])
unzip4 ((a,b,c,d):xs) = let (as,bs,cs,ds) = unzip4 xs in (a:as, b:bs, c:cs, d:ds)
