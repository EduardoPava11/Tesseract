{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- RealTesseract: Your Face as a 4⁴ Tesseract GIF
--
-- 64 frames of your face (64×64 pixels) pushed through:
--   R1 ⊕ R3 = R4 tesseract (4⁴ = 256 palette)
--   Binomial temporal cadence (soft epoch transitions)
--
-- The deviation from B(4096, 1/256) IS your face.
-- ════════════════════════════════════════════════════════════════

module RealTesseract where

import Data.Bits (xor, shiftR)
import Data.Char (chr, ord)
import Data.List (sortBy, foldl')
import Data.Ord (comparing, Down(..))
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import System.IO (withFile, openBinaryFile, IOMode(..), hSetBinaryMode, hGetContents, hPutStr)
-- Using base IO only (no bytestring dependency)

-- ════════════════════════════════════════════════════════════════
-- § 1. TYPES
-- ════════════════════════════════════════════════════════════════

data SRGBColor = SRGBColor !Double !Double !Double deriving (Eq, Ord, Show)

-- ════════════════════════════════════════════════════════════════
-- § 2. TESSERACT PALETTE (from Tesseract.hs)
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

-- ════════════════════════════════════════════════════════════════
-- § 3. BINOMIAL TEMPORAL CADENCE (from TemporalBinomial.hs)
-- ════════════════════════════════════════════════════════════════

epochCenters :: [Double]
epochCenters = [(2 * fromIntegral d + 1) * 63.0 / 8.0 | d <- [0..3::Int]]

sigma :: Double
sigma = 63.0 / 8.0

-- | P(epoch d | frame z)
epochProbs :: Int -> [Double]
epochProbs z =
  let raw = [exp (-(fromIntegral z - mu)**2 / (2 * sigma**2)) | mu <- epochCenters]
      s = sum raw
  in map (/ s) raw

-- | Sample epoch from P(d|z) using pixel-hash
pixelHash :: Int -> Int -> Int -> Int
pixelHash x y seed =
  let h0 = x * 374761393 + y * 668265263 + seed
      h1 = (h0 `xor` (h0 `shiftR` 15)) * 2246822519
      h2 = (h1 `xor` (h1 `shiftR` 13)) * 3266489917
  in abs (h2 `xor` (h2 `shiftR` 16))

sampleEpoch :: Int -> Int -> Int -> Int -> Int
sampleEpoch z x y seed =
  let probs = epochProbs z
      u = fromIntegral (abs (pixelHash x y (seed + z * 997)) `mod` 1000000) / 1000000.0
  in cdfSample probs u

cdfSample :: [Double] -> Double -> Int
cdfSample probs u = go 0 0
  where
    go d cumul
      | d >= length probs - 1 = d
      | cumul + (probs !! d) >= u = d
      | otherwise = go (d + 1) (cumul + (probs !! d))

-- ════════════════════════════════════════════════════════════════
-- § 4. PPM READER
-- ════════════════════════════════════════════════════════════════

-- | Read a P6 PPM file → 64×64 sRGB pixel map
readPPM :: FilePath -> IO (Map (Int,Int) SRGBColor)
readPPM path = do
  h <- openBinaryFile path ReadMode
  contents <- hGetContents h
  let bytes = map ord contents
      -- Skip P6 header: 3 newlines, then raw pixel data
      dataStart = skipHeader bytes 0 0
      pixelBytes = drop dataStart bytes
      pixels = Map.fromList
        [ ((x, y), SRGBColor (fromIntegral r / 255.0)
                              (fromIntegral g / 255.0)
                              (fromIntegral b / 255.0))
        | y <- [0..63], x <- [0..63]
        , let idx = (y * 64 + x) * 3
              r = if idx < length pixelBytes then pixelBytes !! idx else 0
              g = if idx+1 < length pixelBytes then pixelBytes !! (idx+1) else 0
              b = if idx+2 < length pixelBytes then pixelBytes !! (idx+2) else 0
        ]
  return pixels
  where
    skipHeader bytes pos newlines
      | newlines >= 3 = pos
      | pos >= length bytes = pos
      | bytes !! pos == 10 = skipHeader bytes (pos+1) (newlines+1)
      | otherwise = skipHeader bytes (pos+1) newlines

-- ════════════════════════════════════════════════════════════════
-- § 5. QUANTIZE REAL FRAME
-- ════════════════════════════════════════════════════════════════

-- | Quantize a real source frame to the tesseract palette
--   with binomial temporal cadence.
quantizeRealFrame :: Int -> Int -> Map (Int,Int) SRGBColor -> Map (Int,Int) Int
quantizeRealFrame seed z sourcePixels =
  Map.mapWithKey (\(x, y) color ->
    let epoch = sampleEpoch z x y seed
    in quantize4D epoch color
  ) sourcePixels

-- ════════════════════════════════════════════════════════════════
-- § 6. PPM WRITER
-- ════════════════════════════════════════════════════════════════

writePPM :: FilePath -> Map (Int,Int) Int -> IO ()
writePPM path frame = withFile path WriteMode $ \h -> do
  hSetBinaryMode h True
  hPutStr h "P6\n64 64\n255\n"
  mapM_ (\y -> mapM_ (\x -> do
    let idx = Map.findWithDefault 0 (x, y) frame
        SRGBColor r g b = lookupColor idx
        rb = max 0 (min 255 (round (r * 255) :: Int))
        gb = max 0 (min 255 (round (g * 255) :: Int))
        bb = max 0 (min 255 (round (b * 255) :: Int))
    hPutStr h [chr rb, chr gb, chr bb]
    ) [0..63]) [0..63]

-- ════════════════════════════════════════════════════════════════
-- § 7. DEVIATION ANALYSIS
-- ════════════════════════════════════════════════════════════════

-- | Count palette entries in a frame
frameCounts :: Map (Int,Int) Int -> Map Int Int
frameCounts frame = Map.fromListWith (+) [(c, 1) | c <- Map.elems frame]

-- | Deviation magnitude: √(Σ (count_i - 16)²)
deviationMagnitude :: Map Int Int -> Double
deviationMagnitude counts =
  let allCounts = [maybe 0 id (Map.lookup i counts) | i <- [0..255]]
      deviations = [fromIntegral c - 16.0 | c <- allCounts]
  in sqrt (sum [d*d | d <- deviations])

-- | Manifold dimension (from DeviationManifold.hs)
normalizedEntropy :: Map Int Int -> Double
normalizedEntropy counts =
  let total = fromIntegral (sum (Map.elems counts)) :: Double
      probs = [fromIntegral c / total | c <- Map.elems counts, c > 0]
      h = negate (sum [p * log p | p <- probs, p > 0])
  in h / log 256.0

participationRatio :: Map Int Int -> Double
participationRatio counts =
  let total = fromIntegral (sum (Map.elems counts)) :: Double
      probs = [fromIntegral c / total | c <- Map.elems counts, c > 0]
      sumP2 = sum [p*p | p <- probs]
  in if sumP2 > 0 then 1.0 / sumP2 else 1.0

manifoldDim :: Map Int Int -> Double
manifoldDim counts =
  let ent = normalizedEntropy counts
      pr = participationRatio counts
      prNorm = log (max 1 pr) / log 256.0
  in 3.0 * (0.6 * ent + 0.4 * prNorm)

-- ════════════════════════════════════════════════════════════════
-- § 8. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " RealTesseract: Your Face as a 4⁴ Tesseract GIF"
  putStrLn " deviation from binomial = your face"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""

  -- Read all 64 source frames
  putStrLn "  Reading 64 source frames (64×64 PPM)..."
  sourceFrames <- mapM (\z -> do
    let path = "/Users/danielmosquera/source_64/frame_"
             ++ (if z < 10 then "0" else "") ++ show z ++ ".ppm"
    pixels <- readPPM path
    return (z, pixels)
    ) [1..64]
  putStrLn $ "  Read " ++ show (length sourceFrames) ++ " frames."
  putStrLn ""

  -- Source color analysis
  putStrLn "── Source Color Analysis ──"
  putStrLn ""
  let allSourceColors = concat [Map.elems pixels | (_, pixels) <- sourceFrames]
      rs = [r | SRGBColor r _ _ <- allSourceColors]
      gs = [g | SRGBColor _ g _ <- allSourceColors]
      bs = [b | SRGBColor _ _ b <- allSourceColors]
      meanR = sum rs / fromIntegral (length rs)
      meanG = sum gs / fromIntegral (length gs)
      meanB = sum bs / fromIntegral (length bs)
  putStrLn $ "  Total pixels: " ++ show (length allSourceColors)
  putStrLn $ "  Mean sRGB: (" ++ showF meanR ++ ", " ++ showF meanG ++ ", " ++ showF meanB ++ ")"
  putStrLn $ "  → Tesseract bin: (" ++ show (floor (meanR * 4) :: Int)
          ++ ", " ++ show (floor (meanG * 4) :: Int)
          ++ ", " ++ show (floor (meanB * 4) :: Int) ++ ")"
  putStrLn ""

  -- Quantize all frames with binomial cadence
  putStrLn "  Quantizing with 4⁴ tesseract + binomial cadence..."
  let seed = 42
      quantizedFrames = Map.fromList
        [ (z-1, quantizeRealFrame seed (z-1) pixels)
        | (z, pixels) <- sourceFrames ]
  putStrLn "  Done."
  putStrLn ""

  -- Deviation analysis
  putStrLn "── Deviation from Binomial (the face IS the signal) ──"
  putStrLn ""
  putStrLn "  frame │ colors │ ‖δ‖     │ dim   │ top color (count)"
  putStrLn "  ──────┼────────┼─────────┼───────┼──────────────────"
  mapM_ (\z -> do
    let frame = quantizedFrames Map.! z
        counts = frameCounts frame
        nColors = Map.size counts
        dev = deviationMagnitude counts
        dim = manifoldDim counts
        topColor = head (sortBy (comparing (Down . snd)) (Map.toList counts))
        (topIdx, topCnt) = topColor
        SRGBColor tr tg tb = lookupColor topIdx
    putStrLn $ "  " ++ padL 5 (show z)
            ++ " │ " ++ padL 6 (show nColors)
            ++ " │ " ++ padL 7 (showF dev)
            ++ " │ " ++ padL 5 (showF dim)
            ++ " │ idx " ++ padL 3 (show topIdx)
            ++ " (" ++ show topCnt ++ "px)"
            ++ " sRGB(" ++ showF tr ++ "," ++ showF tg ++ "," ++ showF tb ++ ")"
    ) [0, 8, 16, 24, 32, 40, 48, 56, 63]
  putStrLn ""

  -- Compare to noise
  putStrLn "── Comparison: Face vs Noise ──"
  putStrLn ""
  let faceDevs = [deviationMagnitude (frameCounts (quantizedFrames Map.! z)) | z <- [0..63]]
      faceDims = [manifoldDim (frameCounts (quantizedFrames Map.! z)) | z <- [0..63]]
      avgFaceDev = sum faceDevs / 64.0
      avgFaceDim = sum faceDims / 64.0
      -- Noise: expected deviation ≈ √(256 × 4096 × (1/256) × (255/256)) ≈ 63.9
      expectedNoiseDev = sqrt (256.0 * 4096.0 * (1/256) * (255/256))
  putStrLn $ "  Face:  mean ‖δ‖ = " ++ showF avgFaceDev
          ++ "  mean dim = " ++ showF avgFaceDim
  putStrLn $ "  Noise: expected ‖δ‖ = " ++ showF expectedNoiseDev
          ++ "  expected dim ≈ 3.0"
  putStrLn $ "  Ratio face/noise: " ++ showF (avgFaceDev / expectedNoiseDev) ++ "×"
  putStrLn ""
  putStrLn $ "  ★ Your face deviates from binomial by " ++ showF (avgFaceDev / expectedNoiseDev)
          ++ "× more"
  putStrLn "    than noise. That deviation IS the image."
  putStrLn ""

  -- Epoch distribution across frames
  putStrLn "── Binomial Cadence in Real Data ──"
  putStrLn ""
  putStrLn "  frame │ epoch0 │ epoch1 │ epoch2 │ epoch3"
  putStrLn "  ──────┼────────┼────────┼────────┼───────"
  mapM_ (\z -> do
    let frame = quantizedFrames Map.! z
        epochCounts = [length [() | c <- Map.elems frame, c `div` 64 == d] | d <- [0..3]]
    putStrLn $ "  " ++ padL 5 (show z)
            ++ " │ " ++ padL 6 (show (epochCounts !! 0))
            ++ " │ " ++ padL 6 (show (epochCounts !! 1))
            ++ " │ " ++ padL 6 (show (epochCounts !! 2))
            ++ " │ " ++ show (epochCounts !! 3)
    ) [0, 8, 15, 16, 17, 24, 31, 32, 33, 40, 47, 48, 49, 56, 63]
  putStrLn ""

  -- Export quantized frames
  putStrLn "── Exporting tesseract-quantized frames ──"
  mapM_ (\z -> do
    let frame = quantizedFrames Map.! z
        path = "/Users/danielmosquera/beautiful_gif/frame_"
             ++ (if z < 10 then "0" else "") ++ show z ++ ".ppm"
    writePPM path frame
    ) [0..63]
  putStrLn "  64 frames written to /Users/danielmosquera/beautiful_gif/"
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " Your face, quantized into a 4⁴ tesseract."
  putStrLn " The deviation from binomial IS the image."
  putStrLn " R1 (time) ⊕ R3 (color) = R4 (your face in 4D)."
  putStrLn "══════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 100) :: Int) / 100.0 :: Double)
          in take 7 (s ++ repeat '0')

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s
