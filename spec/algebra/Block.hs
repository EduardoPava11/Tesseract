{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

-- ════════════════════════════════════════════════════════════════
-- Block: Two Cubes — Training 64³ and Inference 128³
--
-- CUBE INVARIANT: S = K (spatial side = frame count)
--   Training:  64³  = 64×64×64    (proven on device, rich histograms)
--   Inference: 128³ = 128×128×128  (2× every axis, Metal-only)
--
--   ┌───────────┬─────┬─────┬─────────┬───────────┬─────────┐
--   │ Mode      │  S  │  K  │ S²×K    │ step      │ σ_base  │
--   ├───────────┼─────┼─────┼─────────┼───────────┼─────────┤
--   │ Training  │  64 │  64 │  262144 │ 12 (coarse)│  7.875  │
--   │ Inference │ 128 │ 128 │ 2097152 │  6 (medium)│ 15.875  │
--   └───────────┴─────┴─────┴─────────┴───────────┴─────────┘
--
-- PYRAMID: 3 spatial scales from the 768 crop (NOT from the mode).
--   Coarse: stride 12, 12×12 = 144 samples
--   Medium: stride 6,   6×6  =  36 samples
--   Fine:   stride 3,   3×3  =   9 samples
--
-- At Training: native = Coarse. Medium/Fine = sub-block context.
-- At Inference: native = Medium. Coarse = neighborhood. Fine = sub-pixel.
--
-- inputDim = 137. Unchanged across modes. The NN always sees 3 scales.
-- ════════════════════════════════════════════════════════════════

module Block where

import Data.List (foldl', sort)
import qualified Data.Map.Strict as Map

-- ════════════════════════════════════════════════════════════════
-- § 1. CUBE MODE — Training and Inference
-- ════════════════════════════════════════════════════════════════

data CubeMode = Training | Inference
  deriving (Show, Eq, Ord, Enum, Bounded)

allModes :: [CubeMode]
allModes = [Training, Inference]

-- | Spatial side S
spatialSide :: CubeMode -> Int
spatialSide Training  = 64
spatialSide Inference = 128

-- | Frame count K = S (cube: S = K)
frameCount :: CubeMode -> Int
frameCount = spatialSide

-- | Pixels per frame = S²
pixelsPerFrame :: CubeMode -> Int
pixelsPerFrame m = let s = spatialSide m in s * s

-- | Total voxels = S³ (cube)
totalVoxels :: CubeMode -> Int
totalVoxels m = let s = spatialSide m in s * s * s

-- ════════════════════════════════════════════════════════════════
-- § 2. THE 4⁴ PALETTE — always 256
-- ════════════════════════════════════════════════════════════════

paletteSize :: Int
paletteSize = 256

epochCount :: Int
epochCount = 4

framesPerEpoch :: CubeMode -> Int
framesPerEpoch m = frameCount m `div` epochCount

pixelsPerColorPerFrame :: CubeMode -> Int
pixelsPerColorPerFrame m = pixelsPerFrame m `div` paletteSize

voxelsPerColor :: CubeMode -> Int
voxelsPerColor m = totalVoxels m `div` paletteSize

-- ════════════════════════════════════════════════════════════════
-- § 3. UNIVERSAL CROP: 768 RGB, 256 depth
-- ════════════════════════════════════════════════════════════════

rgbCrop :: Int
rgbCrop = 768

depthCrop :: Int
depthCrop = 256

scaleFactor :: Int
scaleFactor = 3

-- | RGB step at each mode's spatial resolution
rgbStep :: CubeMode -> Int
rgbStep m = rgbCrop `div` spatialSide m

-- | Depth step at each mode's spatial resolution
depthStep :: CubeMode -> Int
depthStep m = depthCrop `div` spatialSide m

-- | RGB samples per block at each mode
rgbSamples :: CubeMode -> Int
rgbSamples m = let s = rgbStep m in s * s

-- ════════════════════════════════════════════════════════════════
-- § 4. PYRAMID SCALES — spatial context from the 768 crop
--
-- The crop always gives 3 strides: 12, 6, 3.
-- These are SPATIAL CONTEXT, not tied to the cube mode.
--
--   Coarse: 768/64  = 12, block = 12×12 = 144 samples
--   Medium: 768/128 =  6, block =  6×6  =  36 samples
--   Fine:   768/256 =  3, block =  3×3  =   9 samples
--
-- The stride numbers come from dividing 768 by powers of 2:
--   768/64 = 12, 768/128 = 6, 768/256 = 3.
-- These are the crop's natural resolution hierarchy.
-- ════════════════════════════════════════════════════════════════

data PyramidScale = Coarse | Medium | Fine
  deriving (Show, Eq, Ord, Enum, Bounded)

pyramidStride :: PyramidScale -> Int
pyramidStride Coarse = 12
pyramidStride Medium = 6
pyramidStride Fine   = 3

pyramidSamples :: PyramidScale -> Int
pyramidSamples sc = let s = pyramidStride sc in s * s

-- | Which pyramid scale is NATIVE for this mode?
--   Training:  Coarse (12×12) — each output pixel IS a coarse block
--   Inference: Medium (6×6) — each output pixel IS a medium block
nativeScale :: CubeMode -> PyramidScale
nativeScale Training  = Coarse
nativeScale Inference = Medium

-- ════════════════════════════════════════════════════════════════
-- § 5. ALGEBRAIC TYPES
-- ════════════════════════════════════════════════════════════════

data RGB = RGB { rgbR :: !Double, rgbG :: !Double, rgbB :: !Double }
  deriving (Show, Eq, Ord)

newtype Depth = Depth { unDepth :: Double }
  deriving (Show, Eq, Ord)

data Pos = Pos { posX :: !Int, posY :: !Int }
  deriving (Show, Eq, Ord)

newtype Frame = Frame { unFrame :: Int }
  deriving (Show, Eq, Ord)

-- ════════════════════════════════════════════════════════════════
-- § 6. EPOCH — scales with K (= S for cubes)
-- ════════════════════════════════════════════════════════════════

newtype Epoch = Epoch { unEpoch :: Int } deriving (Show, Eq, Ord)

sigmaBaseFor :: CubeMode -> Double
sigmaBaseFor m = fromIntegral (frameCount m - 1) / 8.0

epochCentersFor :: CubeMode -> [Double]
epochCentersFor m =
  let sb = sigmaBaseFor m
  in [fromIntegral (2 * d + 1) * sb | d <- [0..3::Int]]

sigmaFor :: CubeMode -> Depth -> Double
sigmaFor m (Depth d) = sigmaBaseFor m * (2.0 - d)

epochProbs :: CubeMode -> Frame -> Depth -> [Double]
epochProbs m (Frame z) depth =
  let s = sigmaFor m depth
      zf = fromIntegral z
      s2 = 2.0 * s * s
      raw = [exp (-(zf - mu)**2 / s2) | mu <- epochCentersFor m]
      total = sum raw
  in if total < 1e-10 then [0.25, 0.25, 0.25, 0.25]
     else map (/ total) raw

dominantEpoch :: CubeMode -> Frame -> Depth -> Epoch
dominantEpoch m z d =
  let probs = epochProbs m z d
  in Epoch $ snd $ maximum (zip probs [0..3])

-- ════════════════════════════════════════════════════════════════
-- § 7. PALETTE INDEX — 4⁴ = 256
-- ════════════════════════════════════════════════════════════════

data TessCoord = TessCoord !Int !Int !Int !Int
  deriving (Show, Eq, Ord)

paletteIndex :: TessCoord -> Int
paletteIndex (TessCoord d a b c) = d * 64 + a * 16 + b * 4 + c

indexToCoord :: Int -> TessCoord
indexToCoord i =
  let (d, r1) = i `divMod` 64
      (a, r2) = r1 `divMod` 16
      (b, c)  = r2 `divMod` 4
  in TessCoord d a b c

-- ════════════════════════════════════════════════════════════════
-- § 8. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (C1) Cube: S = K at all modes
axiom_C1 :: Bool
axiom_C1 = all (\m -> spatialSide m == frameCount m) allModes

-- (C2) 4⁴ = 256
axiom_C2 :: Bool
axiom_C2 = paletteSize == 4 ^ (4::Int)

-- (C3) 4 divides K at all modes
axiom_C3 :: Bool
axiom_C3 = all (\m -> frameCount m `mod` epochCount == 0) allModes

-- (C4) 768/S integer at both modes
axiom_C4 :: Bool
axiom_C4 = all (\m ->
  rgbCrop `mod` spatialSide m == 0 &&
  depthCrop `mod` spatialSide m == 0
  ) allModes

-- (C5) rgbStep = depthStep × 3
axiom_C5 :: Bool
axiom_C5 = all (\m -> rgbStep m == depthStep m * scaleFactor) allModes

-- (C6) step × S = crop
axiom_C6 :: Bool
axiom_C6 = all (\m ->
  rgbStep m * spatialSide m == rgbCrop &&
  depthStep m * spatialSide m == depthCrop
  ) allModes

-- (C7) Pyramid samples: 144, 36, 9
axiom_C7 :: Bool
axiom_C7 = pyramidSamples Coarse == 144
        && pyramidSamples Medium ==  36
        && pyramidSamples Fine   ==   9

-- (C8) Index ↔ TessCoord bijection
axiom_C8 :: Bool
axiom_C8 = all (\i -> paletteIndex (indexToCoord' i) == i) [0..255]
  where indexToCoord' i = let (d,r1) = i `divMod` 64
                              (a,r2) = r1 `divMod` 16
                              (b,c) = r2 `divMod` 4
                          in TessCoord d a b c

-- (C9) Epoch probs sum to 1
axiom_C9 :: Bool
axiom_C9 = all (\m ->
  all (\(z, d) ->
    abs (sum (epochProbs m (Frame z) (Depth d)) - 1.0) < 1e-10
    ) [ (z, d)
      | z <- [0, frameCount m `div` 4, frameCount m `div` 2, frameCount m - 1]
      , d <- [0, 0.25, 0.5, 0.75, 1.0]
      ]
  ) allModes

-- (C10) σ monotone in depth
axiom_C10 :: Bool
axiom_C10 = all (\m ->
  sigmaFor m (Depth 1.0) < sigmaFor m (Depth 0.5) &&
  sigmaFor m (Depth 0.5) < sigmaFor m (Depth 0.0)
  ) allModes

-- (C11) Native scale: Training=Coarse, Inference=Medium
axiom_C11 :: Bool
axiom_C11 = nativeScale Training == Coarse
         && nativeScale Inference == Medium

-- (C12) Frames per epoch
axiom_C12 :: Bool
axiom_C12 = framesPerEpoch Training == 16
         && framesPerEpoch Inference == 32

-- (C13) Inference is 2× training on every axis
axiom_C13 :: Bool
axiom_C13 = spatialSide Inference == 2 * spatialSide Training
         && frameCount Inference == 2 * frameCount Training

-- (C14) Total voxels = S³
axiom_C14 :: Bool
axiom_C14 = all (\m -> totalVoxels m == spatialSide m ^ (3::Int)) allModes

-- ════════════════════════════════════════════════════════════════
-- § 9. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " Block: Training 64³ → Inference 128³"
  putStrLn " S = K (cube). Pyramid: Coarse/Medium/Fine (spatial context)."
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── Two Cubes ──"
  putStrLn ""
  putStrLn "  mode      │  S  │  K  │ S³        │ native │ K/4 │ σ_base"
  putStrLn "  ──────────┼─────┼─────┼───────────┼────────┼─────┼───────"
  mapM_ (\m ->
    putStrLn $ "  " ++ padL 9 (show m)
            ++ " │" ++ padL 4 (show (spatialSide m))
            ++ " │" ++ padL 4 (show (frameCount m))
            ++ " │" ++ padL 10 (show (totalVoxels m))
            ++ " │" ++ padL 7 (show (nativeScale m))
            ++ " │" ++ padL 4 (show (framesPerEpoch m))
            ++ " │ " ++ showF (sigmaBaseFor m)
    ) allModes
  putStrLn ""

  putStrLn "── Pyramid Scales (from 768 crop, mode-independent) ──"
  putStrLn ""
  mapM_ (\sc ->
    putStrLn $ "  " ++ padL 7 (show sc)
            ++ ": stride " ++ show (pyramidStride sc)
            ++ ", " ++ show (pyramidStride sc) ++ "×" ++ show (pyramidStride sc)
            ++ " = " ++ show (pyramidSamples sc) ++ " samples"
    ) [Coarse, Medium, Fine]
  putStrLn ""

  putStrLn "── Epoch Centers ──"
  mapM_ (\m ->
    putStrLn $ "  " ++ padL 9 (show m) ++ ": K=" ++ padL 3 (show (frameCount m))
            ++ "  μ=" ++ show (map (\c -> fromIntegral (round (c * 100)) / 100 :: Double)
                               (epochCentersFor m))
    ) allModes
  putStrLn ""

  -- Axioms
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""
  check "C1  S = K (cube)"                          [axiom_C1]
  check "C2  4⁴ = 256"                              [axiom_C2]
  check "C3  4 | K"                                  [axiom_C3]
  check "C4  768/S and 256/S integer"                [axiom_C4]
  check "C5  rgbStep = depthStep × 3"               [axiom_C5]
  check "C6  step × S = crop"                        [axiom_C6]
  check "C7  pyramid: 144, 36, 9"                    [axiom_C7]
  check "C8  index ↔ TessCoord"                     [axiom_C8]
  check "C9  Σ epochProbs = 1"                       [axiom_C9]
  check "C10 σ monotone in depth"                    [axiom_C10]
  check "C11 native: Training=Coarse, Inference=Medium" [axiom_C11]
  check "C12 frames/epoch: 16, 32"                   [axiom_C12]
  check "C13 Inference = 2× Training"                [axiom_C13]
  check "C14 totalVoxels = S³"                       [axiom_C14]
  putStrLn ""

  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn "  Training:  64³.  Train the gene. Swipe until beauty."
  putStrLn "  Inference: 128³. Test the gene. 2× every axis."
  putStrLn "  Pyramid: Coarse(144) Medium(36) Fine(9). Always 3 scales."
  putStrLn "  The NN sees 137 floats at both modes. Same architecture."
  putStrLn "════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 1000) :: Int) / 1000.0 :: Double)
          in take 7 (s ++ repeat '0')

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      n = length results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name ++ " (" ++ show n ++ " cases)"
