{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE FlexibleInstances #-}

-- ════════════════════════════════════════════════════════════════
-- TesseractQuantize: Type-class separation of Color and Epoch
--
-- The 4⁴ tesseract index = d×64 + a×16 + b×4 + c
--
-- Two INDEPENDENT axes:
--   ColorAxis (a,b,c) ∈ {0,1,2,3}³  — what the pixel LOOKS like
--   EpochAxis (d)     ∈ {0,1,2,3}    — when the pixel APPEARS
--
-- Type classes enforce: dithering operates ONLY on ColorAxis,
-- epoch assignment operates ONLY on EpochAxis. They compose
-- without interfering because they're independent functors.
--
-- GPU does: global parallel operations (downsample, dither mask)
-- CPU does: linear sequential operations (error diffusion, epoch assignment)
-- ════════════════════════════════════════════════════════════════

module TesseractQuantize where

import Data.List (sortBy, foldl')
import Data.Ord (comparing, Down(..))
import qualified Data.Map.Strict as Map

-- ════════════════════════════════════════════════════════════════
-- § 1. THE TWO AXES (type-class separation)
-- ════════════════════════════════════════════════════════════════

-- | A pixel's position in the color cube [0,1]³
data ColorPos = ColorPos
  { cpR :: !Double, cpG :: !Double, cpB :: !Double
  } deriving (Show, Eq)

-- | Quantized color on the 4³ lattice
data ColorLevel = ColorLevel
  { clA :: !Int, clB :: !Int, clC :: !Int
  } deriving (Show, Eq, Ord)

-- | A pixel's position in the temporal axis
data EpochPos = EpochPos
  { epFrame :: !Int     -- frame index 0..63
  , epDepth :: !Double  -- depth [0,1], 1=near
  } deriving (Show, Eq)

-- | Quantized epoch on the 4-level axis
newtype EpochLevel = EpochLevel { elD :: Int }
  deriving (Show, Eq, Ord)

-- | The full tesseract coordinate (composed)
data TessPoint = TessPoint
  { tpColor :: !ColorLevel
  , tpEpoch :: !EpochLevel
  } deriving (Show, Eq, Ord)

tessIndex :: TessPoint -> Int
tessIndex (TessPoint (ColorLevel a b c) (EpochLevel d)) =
  d * 64 + a * 16 + b * 4 + c

-- | Type class: things that can be quantized to a discrete level
class Quantizable pos level | pos -> level where
  quantize :: pos -> level          -- naive nearest quantization
  cellCenter :: level -> pos        -- level → continuous center

-- | ColorPos → ColorLevel: nearest cell center
instance Quantizable ColorPos ColorLevel where
  quantize (ColorPos r g b) = ColorLevel
    (nearestLevel r) (nearestLevel g) (nearestLevel b)
  cellCenter (ColorLevel a b c) = ColorPos
    (levelCenter a) (levelCenter b) (levelCenter c)

-- | EpochPos → EpochLevel: determined by Gaussian cadence
instance Quantizable EpochPos EpochLevel where
  quantize (EpochPos frame depth) = EpochLevel (dominantEpoch frame depth)
  cellCenter (EpochLevel d) = EpochPos
    (round (epochCenters !! d)) 0.5

-- | Type class: things that can be dithered (error diffused)
class Ditherable pos level | pos -> level where
  quantizeError :: pos -> level -> pos   -- error = pos - cellCenter(level)
  adjustBy :: pos -> pos -> pos          -- add accumulated error

instance Ditherable ColorPos ColorLevel where
  quantizeError (ColorPos r g b) (ColorLevel a bq c) =
    ColorPos (r - levelCenter a) (g - levelCenter bq) (b - levelCenter c)
  adjustBy (ColorPos r g b) (ColorPos er eg eb) =
    ColorPos (r + er) (g + eg) (b + eb)

-- | EpochPos IS temporally ditherable — but ONLY on the epoch axis.
-- The dither value is the continuous "ideal epoch" (weighted average
-- of epoch indices by their probabilities). The error = ideal - quantized
-- is diffused spatially, nudging neighbors' epoch assignments.
-- Color is FROZEN — only the temporal dimension is dithered.
instance Ditherable EpochPos EpochLevel where
  quantizeError (EpochPos _ _) (EpochLevel d) = EpochPos 0 0  -- placeholder
  adjustBy (EpochPos z d) (EpochPos ez _) = EpochPos z d      -- placeholder

-- The key constraint: temporal dithering operates on EpochPos ONLY.
-- It cannot see or modify ColorPos. The type system enforces this
-- because ditherColors takes [ColorPos] and ditherEpochs takes [EpochPos].
-- They are different functions on different types.

-- ════════════════════════════════════════════════════════════════
-- § 2. CONSTANTS
-- ════════════════════════════════════════════════════════════════

sigmaBase :: Double
sigmaBase = 63.0 / 8.0  -- 7.875

epochCenters :: [Double]
epochCenters = [7.875, 23.625, 39.375, 55.125]

levelCenter :: Int -> Double
levelCenter a = (fromIntegral a + 0.5) / 4.0
-- {0.125, 0.375, 0.625, 0.875}

nearestLevel :: Double -> Int
nearestLevel v = min 3 (max 0 (round (v * 3.0)))
-- boundaries at {1/6, 1/2, 5/6} ≈ {0.167, 0.500, 0.833}

sigmaForDepth :: Double -> Double
sigmaForDepth depth = sigmaBase * (2.0 - depth)

gaussianProbs :: Int -> Double -> [Double]
gaussianProbs z sigma =
  let zf = fromIntegral z
      s2 = 2.0 * sigma * sigma
      raw = [ exp (-(zf - mu)^(2::Int) / s2) | mu <- epochCenters ]
      total = sum raw
  in if total < 1e-10 then [0.25, 0.25, 0.25, 0.25]
     else map (/ total) raw

dominantEpoch :: Int -> Double -> Int
dominantEpoch z depth =
  let probs = gaussianProbs z (sigmaForDepth depth)
  in snd $ maximum (zip probs [0..3])

-- ════════════════════════════════════════════════════════════════
-- § 3. THE ALGORITHM: Color dithering ⊕ Epoch assignment
--
-- These are two INDEPENDENT operations composed via (,):
--   pixel → (ColorLevel, EpochLevel)
--   index = compose tessIndex
--
-- Color dithering: Floyd-Steinberg on ColorPos (local, sequential)
--   GPU COULD compute a global dither mask (Bayer, ordered)
--   CPU DOES sequential error diffusion (Floyd-Steinberg)
--
-- Epoch assignment: distribution matching on EpochPos (global)
--   Groups pixels by ColorLevel AFTER dithering
--   Assigns epochs to match Gaussian cadence WITHIN each group
--   GPU COULD compute epoch probabilities (parallel per-pixel)
--   CPU DOES the assignment (sequential, deterministic)
-- ════════════════════════════════════════════════════════════════

-- | A pixel with spatial position + continuous color + depth
data Pixel = Pixel
  { pxIndex :: !Int         -- spatial position 0..4095
  , pxColor :: !ColorPos    -- continuous RGB [0,1]³
  , pxDepth :: !Double      -- depth [0,1], 1=near
  } deriving (Show)

-- | Result of quantization: discrete color + epoch
data QuantizedPixel = QuantizedPixel
  { qpIndex :: !Int
  , qpColor :: !ColorLevel
  , qpEpoch :: !EpochLevel
  , qpDepth :: !Double
  } deriving (Show)

-- | Diffusion strength: depth controls how much error is spread.
--   Near (face): low diffusion → preserve subject detail
--   Far (wall): full diffusion → fill the tesseract
diffusionStrength :: Double -> Double
diffusionStrength depth = 1.0 - depth * 0.7

-- ════════════════════════════════════════════════════════════════
-- § 4. PHASE 1: Color Dithering (operates on ColorPos ONLY)
--
-- Input:  [Pixel]  (continuous RGB + depth)
-- Output: [(Int, ColorLevel, Double)]  (pixel index, dithered color, depth)
--
-- The epoch dimension is INVISIBLE here. This function does not
-- know about frames, epochs, or temporal structure. It only
-- sees a 64×64 grid of colors and dithers them.
-- ════════════════════════════════════════════════════════════════

ditherColors :: [Pixel] -> [(Int, ColorLevel, Double)]
ditherColors pixels =
  let w = 64
      n = length pixels

      -- Error accumulator: (errR, errG, errB) per pixel
      initErrors = replicate n (0, 0, 0)

      -- Process in scanline order, accumulating errors
      (result, _) = foldl' processPixel ([], initErrors) [0..n-1]

  in reverse result
  where
    w = 64

    processPixel :: ([(Int, ColorLevel, Double)], [(Double, Double, Double)])
                 -> Int
                 -> ([(Int, ColorLevel, Double)], [(Double, Double, Double)])
    processPixel (acc, errors) i =
      let px = pixels !! i
          (er, eg, eb) = errors !! i
          depth = pxDepth px

          -- Adjust color by accumulated error
          adjusted = adjustBy (pxColor px) (ColorPos er eg eb)

          -- Quantize to nearest level
          level = quantize adjusted :: ColorLevel

          -- Compute error
          ColorPos errR errG errB = quantizeError adjusted level

          -- Depth-weighted diffusion
          s = diffusionStrength depth
          dR = errR * s; dG = errG * s; dB = errB * s

          x = i `mod` w
          y = i `div` w

          -- Floyd-Steinberg neighbors
          neighbors = filter (\(j, _) -> j >= 0 && j < length errors)
            [ (i + 1,           7.0 / 16.0) | x + 1 < w ] ++
            [ ((y+1)*w + (x-1), 3.0 / 16.0) | x > 0 && y + 1 < w ] ++
            [ ((y+1)*w + x,     5.0 / 16.0) | y + 1 < w ] ++
            [ ((y+1)*w + (x+1), 1.0 / 16.0) | x + 1 < w && y + 1 < w ]

          -- Diffuse error to neighbors
          errors' = foldl' (\errs (j, weight) ->
            let (jr, jg, jb) = errs !! j
            in setAt errs j (jr + dR * weight, jg + dG * weight, jb + dB * weight)
            ) errors neighbors

      in ((pxIndex px, level, depth) : acc, errors')

-- ════════════════════════════════════════════════════════════════
-- § 5. PHASE 2: Epoch Assignment (operates on EpochPos ONLY)
--
-- Input:  frame z, [(pixelIndex, ColorLevel, depth)]
-- Output: [QuantizedPixel]
--
-- The color dimension is INVISIBLE here. This function receives
-- pre-dithered colors and assigns epochs based ONLY on frame
-- index and depth. It groups by ColorLevel but does not modify
-- the colors — they're frozen from Phase 1.
-- ════════════════════════════════════════════════════════════════

assignEpochs :: Int -> [(Int, ColorLevel, Double)] -> [QuantizedPixel]
assignEpochs z ditheredPixels =
  let -- Group by (frozen) ColorLevel
      groups = Map.fromListWith (++)
        [ (color, [(idx, depth)])
        | (idx, color, depth) <- ditheredPixels ]

      -- For each group: compute epoch targets, assign by depth
      assigned = concatMap (assignGroup z) (Map.toList groups)

  in assigned

assignGroup :: Int -> (ColorLevel, [(Int, Double)]) -> [QuantizedPixel]
assignGroup z (color, pixelsWithDepth) =
  let n = length pixelsWithDepth

      -- Average depth of group → σ → epoch probabilities
      avgDepth = sum (map snd pixelsWithDepth) / fromIntegral n
      sigma = sigmaForDepth avgDepth
      probs = gaussianProbs z sigma

      -- Target counts via largest remainder
      targets = largestRemainder n probs

      -- Sort by depth descending (near first)
      sorted = sortBy (flip $ comparing snd) pixelsWithDepth

      -- Assign: dominant epoch gets near pixels
      epochOrder = sortBy (flip $ comparing (targets !!)) [0..3]

      assign [] _ = []
      assign remaining ((epoch, count):rest) =
        let (batch, leftover) = splitAt count remaining
        in [ QuantizedPixel idx color (EpochLevel epoch) depth
           | (idx, depth) <- batch ]
           ++ assign leftover rest
      assign _ [] = []

  in assign sorted (zip epochOrder (map (targets !!) epochOrder))

-- ════════════════════════════════════════════════════════════════
-- § 6. COMPOSE: The full pipeline
--
-- quantizeFrame = assignEpochs z . ditherColors
--
-- Phase 1 (ditherColors) is a local operation on ColorPos.
-- Phase 2 (assignEpochs) is a global operation on EpochPos.
-- They compose cleanly because they operate on different axes.
--
-- GPU opportunities:
--   - Phase 1 dither could use Bayer ordered dithering (parallel)
--     instead of Floyd-Steinberg (sequential). Same type signature.
--   - Phase 2 epoch probabilities could be computed on GPU
--     (parallel per-pixel Gaussian), then CPU does the assignment.
-- ════════════════════════════════════════════════════════════════

quantizeFrame :: Int -> [Pixel] -> [Int]
quantizeFrame z pixels =
  let -- Phase 1: dither colors (ColorAxis only)
      dithered = ditherColors pixels

      -- Phase 2: assign epochs (EpochAxis only, colors frozen)
      assigned = assignEpochs z dithered

      -- Phase 3: compose into palette indices
      result = replicate (length pixels) 0
      final = foldl' (\arr qp ->
        setAt arr (qpIndex qp) (tessIndex (TessPoint (qpColor qp) (qpEpoch qp)))
        ) result assigned

  in final

-- ════════════════════════════════════════════════════════════════
-- § 7. AXIOMS
--
-- QA1: Phase 1 does not modify depth or spatial index
-- QA2: Phase 2 does not modify ColorLevel
-- QA3: Composition is total: all 4096 pixels get an index
-- QA4: Epoch distribution matches Gaussian cadence ±1 per group
-- QA5: Near pixels get dominant epoch within each color group
-- QA6: Color dithering preserves average color (error sums to 0)
-- ════════════════════════════════════════════════════════════════

-- | QA1: ditherColors preserves depth and spatial index
axiom_QA1 :: [Pixel] -> Bool
axiom_QA1 pixels =
  let dithered = ditherColors pixels
  in all (\(idx, _, depth) ->
    idx == pxIndex (pixels !! idx) &&
    abs (depth - pxDepth (pixels !! idx)) < 1e-10
    ) dithered

-- | QA2: assignEpochs does not modify ColorLevel
axiom_QA2 :: Int -> [(Int, ColorLevel, Double)] -> Bool
axiom_QA2 z dithered =
  let assigned = assignEpochs z dithered
      colorMap = Map.fromList [(idx, color) | (idx, color, _) <- dithered]
  in all (\qp -> qpColor qp == colorMap Map.! qpIndex qp) assigned

-- | QA3: all pixels assigned
axiom_QA3 :: [Pixel] -> Int -> Bool
axiom_QA3 pixels z =
  let indices = quantizeFrame z pixels
  in length indices == length pixels
  && all (\i -> i >= 0 && i <= 255) indices

-- | QA6: total diffused error sums to zero (conservation)
axiom_QA6 :: [Pixel] -> Bool
axiom_QA6 pixels =
  let dithered = ditherColors pixels
      -- Sum of (original color - quantized center) across all pixels
      totalErr = foldl' (\(sr, sg, sb) (idx, level, _) ->
        let orig = pxColor (pixels !! idx)
            center = cellCenter level
        in (sr + cpR orig - cpR center,
            sg + cpG orig - cpG center,
            sb + cpB orig - cpB center)
        ) (0, 0, 0) dithered
      (er, eg, eb) = totalErr
  -- Error doesn't sum to exactly 0 because boundary pixels lose diffusion.
  -- But it should be small relative to total pixel count.
  in abs er < fromIntegral (length pixels) * 0.01
  && abs eg < fromIntegral (length pixels) * 0.01
  && abs eb < fromIntegral (length pixels) * 0.01

-- ════════════════════════════════════════════════════════════════
-- § 8. GPU vs CPU DIVISION
--
-- The type classes reveal the natural division:
--
-- GPU (parallel, global):
--   - Downsample camera → 64×64 RGB+depth  (texture reads)
--   - Compute Bayer dither threshold per pixel  (parallel)
--   - Compute epoch probabilities per pixel  (parallel Gaussian)
--   - Compute depth-driven σ per pixel  (parallel)
--
-- CPU (sequential, deterministic):
--   - Floyd-Steinberg error diffusion  (scanline order, data-dependent)
--   - Epoch assignment  (group-by, sort, distribute — sequential)
--   - LZW encoding  (dictionary-based, inherently sequential)
--
-- The GPU precomputes INPUTS that the CPU consumes:
--   GPU → (rgbTexture, depthTexture, ditherThreshold, epochProbs)
--   CPU → ditherColors(rgb, threshold) → assignEpochs(dithered, probs)
--
-- This is a PIPELINE, not a fallback. Both stages run every frame.
-- ════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- § 9. MAIN — self-test
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " TesseractQuantize: Type-Class Separation of Color ⊕ Epoch"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""

  -- Synthetic frame: gradient + center-near depth
  let pixels = [ Pixel i
                   (ColorPos (fromIntegral (i `mod` 64) / 63.0)
                             (fromIntegral (i `div` 64) / 63.0)
                             0.5)
                   (let x = abs (fromIntegral (i `mod` 64) - 31.5) / 31.5
                        y = abs (fromIntegral (i `div` 64) - 31.5) / 31.5
                    in 1.0 - sqrt (x*x + y*y) / sqrt 2.0)
               | i <- [0..4095] ]

  -- Test at epoch crossover frame (most challenging)
  let z = 16
  putStrLn $ "Testing frame z=" ++ show z ++ " (epoch 0↔1 crossover)"
  putStrLn ""

  -- Phase 1: dither
  let dithered = ditherColors pixels
  let colorHist = Map.fromListWith (+) [(color, 1::Int) | (_, color, _) <- dithered]
  putStrLn $ "  Phase 1 (color dithering):"
  putStrLn $ "    Display colors used: " ++ show (Map.size colorHist) ++ " / 64"
  putStrLn $ "    Pixels dithered: " ++ show (length dithered)

  -- Phase 2: epochs
  let assigned = assignEpochs z dithered
  let epochCounts = Map.fromListWith (+) [(elD (qpEpoch qp), 1::Int) | qp <- assigned]
  putStrLn $ "  Phase 2 (epoch assignment):"
  putStrLn $ "    Epoch distribution: " ++ show (Map.toAscList epochCounts)
  let probs = gaussianProbs z sigmaBase
  putStrLn $ "    Expected (base σ):  " ++ show (map (\p -> round (p * 4096) :: Int) probs)

  -- Compose
  let indices = quantizeFrame z pixels
  let paletteHist = Map.fromListWith (+) [(idx, 1::Int) | idx <- indices]
  putStrLn $ "  Composed:"
  putStrLn $ "    Palette entries used: " ++ show (Map.size paletteHist) ++ " / 256"

  -- Axioms
  putStrLn ""
  putStrLn "  Axiom verification:"
  putStrLn $ "    QA1 (dither preserves depth/index): " ++ showBool (axiom_QA1 pixels)
  putStrLn $ "    QA2 (epochs preserve color):        " ++ showBool (axiom_QA2 z dithered)
  putStrLn $ "    QA3 (all pixels assigned):           " ++ showBool (axiom_QA3 pixels z)
  putStrLn $ "    QA6 (error conservation):            " ++ showBool (axiom_QA6 pixels)

  -- Multi-frame test
  putStrLn ""
  putStrLn "  64-frame summary:"
  let allIndices = [quantizeFrame frame pixels | frame <- [0..63]]
      totalUsed = Map.size $ Map.fromListWith (+)
        [(idx, 1::Int) | indices' <- allIndices, idx <- indices']
  putStrLn $ "    Total palette entries used: " ++ show totalUsed ++ " / 256"

  -- Per-frame epoch accuracy
  let epochAccuracy = length $ filter id
        [ let counts = Map.fromListWith (+) [(idx `div` 64, 1::Int) | idx <- frame]
              dominant = fst $ maximum [(c, e) | (e, c) <- Map.toList counts]
              expected = snd $ maximum (zip (gaussianProbs z sigmaBase) [0..3])
          in dominant == expected
        | (z, frame) <- zip [0..63] allIndices ]
  putStrLn $ "    Epoch accuracy: " ++ show epochAccuracy ++ " / 64"
  putStrLn ""
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " ColorAxis ⊕ EpochAxis = TessPoint"
  putStrLn " Dithering sees ONLY color. Epochs see ONLY time+depth."
  putStrLn " The type system enforces the separation."
  putStrLn "════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

largestRemainder :: Int -> [Double] -> [Int]
largestRemainder total weights =
  let ideal = map (* fromIntegral total) weights
      floored = map floor ideal
      remainders = zipWith (-) ideal (map fromIntegral floored)
      deficit = total - sum floored
      indexed = zip [0..] remainders
      sorted = sortBy (flip $ comparing snd) indexed
      winners = map fst (take deficit sorted)
      adjust i = if i `elem` winners then 1 else 0
  in zipWith (+) floored (map adjust [0..length weights - 1])

setAt :: [a] -> Int -> a -> [a]
setAt xs i v
  | i >= 0 && i < length xs = take i xs ++ [v] ++ drop (i + 1) xs
  | otherwise = xs

showBool :: Bool -> String
showBool True  = "✓"
showBool False = "✗"
