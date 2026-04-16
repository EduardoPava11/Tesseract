{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- DeviationManifold: Binomial Deviation as 1D + 2D = 3D
--
-- The null model: B(4096, 1/256) per color per frame.
-- E[count_c] = 16.  Any real image DEVIATES from this.
--
-- The deviation decomposes via direct sum:
--   π₁(dev) = temporal envelope  (R1: total deviation per frame)
--   π₂(dev) = spatial texture    (R2: where deviation concentrates)
--
-- The manifold dimension of the image's color distribution
-- determines the shape of the deviation:
--   0D (point)   → single color  → maximal deviation
--   1D (curve)   → gradient      → heavy-tailed
--   2D (surface) → natural photo → moderate
--   3D (volume)  → noise         → zero (binomial)
-- ════════════════════════════════════════════════════════════════

module DeviationManifold where

import Data.Bits (xor, shiftR)
import Data.List (sortBy, foldl', sort, zip4)
import Data.Ord (comparing, Down(..))
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)

-- ════════════════════════════════════════════════════════════════
-- § 1. TYPES — sRGB, Spatial, Metric (self-contained)
-- ════════════════════════════════════════════════════════════════

data SRGBColor = SRGBColor !Double !Double !Double
  deriving (Eq, Ord, Show)

data Spatial = Spatial {-# UNPACK #-} !Int {-# UNPACK #-} !Int
  deriving (Eq, Ord, Show)

class Metric a where
  distance :: a -> a -> Double

instance Metric SRGBColor where
  distance (SRGBColor r1 g1 b1) (SRGBColor r2 g2 b2) =
    sqrt ((r1-r2)**2 + (g1-g2)**2 + (b1-b2)**2)

instance Metric Spatial where
  distance (Spatial x1 y1) (Spatial x2 y2) =
    sqrt (fromIntegral ((x1-x2)^(2::Int) + (y1-y2)^(2::Int)))

-- ════════════════════════════════════════════════════════════════
-- § 2. DIRECT SUM — R1 ⊕ R2 = R3 (from DirectSum.hs)
-- ════════════════════════════════════════════════════════════════

newtype R1 = R1 { unR1 :: Double } deriving (Show, Eq)
data R2 = R2 { r2x :: Double, r2y :: Double } deriving (Show, Eq)
data R3 = R3 { r3x :: Double, r3y :: Double, r3z :: Double } deriving (Show, Eq)

class VectorSpace v where
  vzero :: v
  vadd  :: v -> v -> v
  vscale :: Double -> v -> v

instance VectorSpace R1 where
  vzero = R1 0; vadd (R1 a) (R1 b) = R1 (a+b); vscale k (R1 a) = R1 (k*a)
instance VectorSpace R2 where
  vzero = R2 0 0; vadd (R2 a b) (R2 c d) = R2 (a+c) (b+d)
  vscale k (R2 a b) = R2 (k*a) (k*b)
instance VectorSpace R3 where
  vzero = R3 0 0 0; vadd (R3 a b c) (R3 d e f) = R3 (a+d) (b+e) (c+f)
  vscale k (R3 a b c) = R3 (k*a) (k*b) (k*c)

-- Direct sum projections/injections
project1 :: R3 -> R1
project1 (R3 a _ _) = R1 a
project2 :: R3 -> R2
project2 (R3 _ b c) = R2 b c
inject1 :: R1 -> R3
inject1 (R1 a) = R3 a 0 0
inject2 :: R2 -> R3
inject2 (R2 a b) = R3 0 a b

-- ════════════════════════════════════════════════════════════════
-- § 3. PALETTE + QUANTIZATION (from BinomialFix.hs)
-- ════════════════════════════════════════════════════════════════

nR, nG, nB :: Int
nR = 8; nG = 8; nB = 4

quantize :: SRGBColor -> Int
quantize (SRGBColor r g b) =
  let ir = clamp 0 (nR-1) (floor (r * fromIntegral nR))
      ig = clamp 0 (nG-1) (floor (g * fromIntegral nG))
      ib = clamp 0 (nB-1) (floor (b * fromIntegral nB))
  in ir * nG * nB + ig * nB + ib
  where clamp lo hi x = max lo (min hi x)

lookupColor :: Int -> SRGBColor
lookupColor idx =
  let (ir, rest) = idx `divMod` (nG * nB)
      (ig, ib) = rest `divMod` nB
      r = (fromIntegral ir + 0.5) / fromIntegral nR
      g = (fromIntegral ig + 0.5) / fromIntegral nG
      b = (fromIntegral ib + 0.5) / fromIntegral nB
  in SRGBColor r g b

-- ════════════════════════════════════════════════════════════════
-- § 4. HASH PRNG (from BinomialFix.hs)
-- ════════════════════════════════════════════════════════════════

pixelHash :: Int -> Int -> Int -> Int
pixelHash x y seed =
  let h0 = x * 374761393 + y * 668265263 + seed
      h1 = (h0 `xor` (h0 `shiftR` 15)) * 2246822519
      h2 = (h1 `xor` (h1 `shiftR` 13)) * 3266489917
      h3 = h2 `xor` (h2 `shiftR` 16)
  in abs h3

hashToDouble :: Int -> Double
hashToDouble h = fromIntegral (abs h `mod` 1000000) / 1000000.0

pixelRGB :: Int -> Int -> Int -> (Double, Double, Double)
pixelRGB x y seed =
  ( hashToDouble (pixelHash x y seed)
  , hashToDouble (pixelHash x y (seed + 7919))
  , hashToDouble (pixelHash x y (seed + 104729)) )

-- ════════════════════════════════════════════════════════════════
-- § 5. DEVIATION TYPES
-- ════════════════════════════════════════════════════════════════

-- | The null model expectation
binomialE :: Double
binomialE = 16.0  -- 4096 / 256

-- | Per-color deviation from the binomial null
data ColorDeviation = ColorDeviation
  { cdColor    :: !Int
  , cdFrame    :: !Int
  , cdDelta    :: !Double    -- count_c - 16
  , cdRelative :: !Double    -- (count_c - 16) / 16
  } deriving (Show)

-- | Full deviation field for one frame
data FrameDeviation = FrameDeviation
  { fdFrame      :: !Int
  , fdDeviations :: !(Map Int ColorDeviation)
  , fdMagnitude  :: !Double   -- L2 norm √(Σ δ²)
  , fdEntropy    :: !Double   -- normalized H/log(256)
  , fdEffDim     :: !Double   -- manifold dimension [0,3]
  } deriving (Show)

-- | Manifold dimensionality estimates
data ManifoldDim = ManifoldDim
  { mdParticipation :: !Double  -- [1, 256]
  , mdEntropy       :: !Double  -- [0, 1]
  , mdEstimate      :: !Double  -- [0, 3]
  } deriving (Show, Eq)

-- | Decomposed deviation: temporal ⊕ spatial
data DeviationDecomposition = DeviationDecomposition
  { ddTemporal :: !(Map Int R1)                    -- frame → magnitude
  , ddSpatial  :: !(Map Int (Map (Int,Int) R2))    -- frame → (x,y) → (δ_color, δ_spatial)
  } deriving (Show)

-- | Full deviation manifold for a tensor
data DeviationManifold = DeviationManifold
  { dmFrames       :: !(Map Int FrameDeviation)
  , dmDecomposition :: !DeviationDecomposition
  , dmDimension    :: !ManifoldDim
  , dmTotalDev     :: !Double
  } deriving (Show)

-- ════════════════════════════════════════════════════════════════
-- § 6. DEVIATION COMPUTATION
-- ════════════════════════════════════════════════════════════════

-- | Compute deviation field for one frame from color buckets
computeFrameDeviation :: Int -> Map Int [Spatial] -> FrameDeviation
computeFrameDeviation frameIdx buckets =
  let -- Compute counts and deviations for all 256 colors
      deviations = Map.fromList
        [ (c, ColorDeviation c frameIdx delta (delta / binomialE))
        | c <- [0..255]
        , let count = maybe 0 length (Map.lookup c buckets)
              delta = fromIntegral count - binomialE
        ]
      magnitude = sqrt (sum [cdDelta d ^ (2::Int) | d <- Map.elems deviations])
      -- Compute entropy and manifold dim from counts
      counts = Map.fromList [(c, maybe 0 length (Map.lookup c buckets)) | c <- [0..255]]
      ent = normalizedEntropy counts
      dim = estimateManifoldDim counts
  in FrameDeviation frameIdx deviations magnitude ent (mdEstimate dim)

-- ════════════════════════════════════════════════════════════════
-- § 7. MANIFOLD DIMENSION ESTIMATORS
-- ════════════════════════════════════════════════════════════════

-- | Participation ratio: effective number of occupied colors
--   = (Σ p_c)² / Σ p_c²   where p_c = count_c / 4096
--   Range: 1 (single color) to 256 (uniform)
participationRatio :: Map Int Int -> Double
participationRatio counts =
  let total = fromIntegral (sum (Map.elems counts)) :: Double
      probs = [fromIntegral c / total | c <- Map.elems counts, c > 0]
      sumP  = sum probs        -- = 1.0
      sumP2 = sum [p*p | p <- probs]
  in if sumP2 > 0 then sumP * sumP / sumP2 else 1.0

-- | Shannon entropy normalized by log(256)
--   Range: 0 (single color) to 1 (uniform)
normalizedEntropy :: Map Int Int -> Double
normalizedEntropy counts =
  let total = fromIntegral (sum (Map.elems counts)) :: Double
      probs = [fromIntegral c / total | c <- Map.elems counts, c > 0]
      h = negate (sum [p * log p | p <- probs, p > 0])
      maxH = log 256.0
  in h / maxH

-- | Combined manifold dimension estimate
--   Maps entropy to [0, 3]: dim = 3 × normalizedEntropy
--   Justification: entropy=1 → noise → 3D manifold fills cube
--                  entropy=0 → point → 0D manifold
estimateManifoldDim :: Map Int Int -> ManifoldDim
estimateManifoldDim counts =
  let pr = participationRatio counts
      ent = normalizedEntropy counts
      -- Map to [0, 3] using entropy (primary) + participation (secondary)
      -- Participation: 256 → 3D, 1 → 0D.  log(pr)/log(256) ∈ [0, 1]
      prNorm = log (max 1 pr) / log 256.0
      -- Combined: weighted average of two estimators
      est = 3.0 * (0.6 * ent + 0.4 * prNorm)
  in ManifoldDim pr ent est

-- ════════════════════════════════════════════════════════════════
-- § 8. DIRECT SUM DECOMPOSITION OF DEVIATION
-- ════════════════════════════════════════════════════════════════

-- | Project deviation field onto temporal axis (π₁)
--   Each frame gets a single R1 scalar: its deviation magnitude
projectDeviationTemporal :: [FrameDeviation] -> Map Int R1
projectDeviationTemporal fds =
  Map.fromList [(fdFrame fd, R1 (fdMagnitude fd)) | fd <- fds]

-- | Project deviation field onto spatial plane (π₂)
--   For each frame, each pixel (x,y) gets R2 = (δ_color, δ_clustering)
--   where:
--     δ_color = deviation of the color at this pixel from binomial
--     δ_clustering = local density deviation (how many same-color neighbors)
projectDeviationSpatial :: [FrameDeviation] -> Map Int (Map Int [Spatial])
                        -> Map Int (Map (Int,Int) R2)
projectDeviationSpatial fds frameBuckets =
  Map.fromList
    [ (fdFrame fd, buildSpatialField fd (Map.findWithDefault Map.empty (fdFrame fd) frameBuckets))
    | fd <- fds ]
  where
    buildSpatialField fd buckets =
      -- Build reverse map: pixel → color
      let pixToColor = Map.fromList
            [ ((x, y), c)
            | (c, pixels) <- Map.toList buckets
            , Spatial x y <- pixels ]
          -- For each pixel, compute R2 = (color_deviation, clustering_deviation)
      in Map.mapWithKey (\(x,y) c ->
            let colorDev = maybe 0 cdDelta (Map.lookup c (fdDeviations fd))
                -- Clustering deviation: count same-color neighbors / 8
                -- Expected under uniform: 8 * (count_c / 4096)
                neighbors = [ (x+dx, y+dy) | dx <- [-1,0,1], dy <- [-1,0,1]
                            , (dx,dy) /= (0,0)
                            , x+dx >= 0, x+dx < 64, y+dy >= 0, y+dy < 64 ]
                sameColor = length [n | n <- neighbors, Map.lookup n pixToColor == Just c]
                countC = maybe 0 (length) (Map.lookup c buckets)
                expectedNeighbors = 8.0 * fromIntegral countC / 4096.0
                clusterDev = fromIntegral sameColor - expectedNeighbors
            in R2 colorDev clusterDev
          ) pixToColor

-- | Full decomposition
decomposeDeviation :: [FrameDeviation] -> Map Int (Map Int [Spatial])
                   -> DeviationDecomposition
decomposeDeviation fds buckets =
  DeviationDecomposition
    (projectDeviationTemporal fds)
    (projectDeviationSpatial fds buckets)

-- ════════════════════════════════════════════════════════════════
-- § 9. MANIFOLD COMPARISON
-- ════════════════════════════════════════════════════════════════

-- | Wasserstein-1 distance between two deviation vectors
--   Sort both δ vectors, sum |δ_A[i] - δ_B[i]|.
--   Exact for 1D distributions. O(256 log 256).
wassersteinDeviation :: FrameDeviation -> FrameDeviation -> Double
wassersteinDeviation fd1 fd2 =
  let deltas1 = sort [cdDelta d | d <- Map.elems (fdDeviations fd1)]
      deltas2 = sort [cdDelta d | d <- Map.elems (fdDeviations fd2)]
  in sum (zipWith (\a b -> abs (a - b)) deltas1 deltas2) / fromIntegral (length deltas1)

-- | Shape distance between manifold dimensions
shapeDistance :: ManifoldDim -> ManifoldDim -> Double
shapeDistance m1 m2 =
  sqrt ( (mdEstimate m1 - mdEstimate m2) ** 2
       + ((mdEntropy m1 - mdEntropy m2) * 3) ** 2
       + ((log (mdParticipation m1) - log (mdParticipation m2)) / log 256) ** 2 )

-- ════════════════════════════════════════════════════════════════
-- § 10. TEST GENERATORS — 4 Manifold Types
-- ════════════════════════════════════════════════════════════════

-- | Type 0D: Single color (point manifold)
--   All 4096 pixels → same palette cell
--   Deviation: one color gets +4080, 255 others get -16
generateSingleColor :: Int -> Map Int [Spatial]
generateSingleColor targetColor =
  Map.singleton targetColor
    [Spatial x y | y <- [0..63], x <- [0..63]]

-- | Type 1D: Gradient (curve manifold)
--   R sweeps from 0→1 across x, G and B held constant
--   Only ~8 R-levels are visited → 8 colors dominate
generateGradient :: Int -> Map Int [Spatial]
generateGradient seed =
  foldl' addPixel Map.empty [(x,y) | y <- [0..63], x <- [0..63]]
  where
    addPixel buckets (x, y) =
      let r = fromIntegral x / 63.0
          g = 0.5  -- constant
          b = 0.5  -- constant
          -- Small noise to spread within cells
          (nr, _, _) = pixelRGB x y seed
          r' = clamp01 (r + 0.02 * (nr - 0.5))
          idx = quantize (SRGBColor r' g b)
      in Map.insertWith (++) idx [Spatial x y] buckets
    clamp01 v = max 0 (min 1 v)

-- | Type 2D: Photo-like (surface manifold)
--   R = f(x), G = f(y), B varies smoothly with both
--   Covers a 2D surface through the sRGB cube
generatePhotoLike :: Int -> Map Int [Spatial]
generatePhotoLike seed =
  foldl' addPixel Map.empty [(x,y) | y <- [0..63], x <- [0..63]]
  where
    addPixel buckets (x, y) =
      let tx = fromIntegral x / 63.0
          ty = fromIntegral y / 63.0
          r = tx
          g = ty
          b = 0.5 + 0.3 * sin ((tx + ty) * pi)
          (nr, ng, nb) = pixelRGB x y seed
          noise = 0.05
          r' = clamp01 (r + noise * (nr - 0.5))
          g' = clamp01 (g + noise * (ng - 0.5))
          b' = clamp01 (b + noise * (nb - 0.5))
          idx = quantize (SRGBColor r' g' b')
      in Map.insertWith (++) idx [Spatial x y] buckets
    clamp01 v = max 0 (min 1 v)

-- | Type 3D: Noise (volume manifold)
--   Uniform random in sRGB cube → fills all cells → binomial
generateNoise :: Int -> Map Int [Spatial]
generateNoise seed =
  foldl' addPixel Map.empty [(x,y) | y <- [0..63], x <- [0..63]]
  where
    addPixel buckets (x, y) =
      let (r, g, b) = pixelRGB x y seed
          idx = quantize (SRGBColor r g b)
      in Map.insertWith (++) idx [Spatial x y] buckets

-- ════════════════════════════════════════════════════════════════
-- § 11. AXIOMS
-- ════════════════════════════════════════════════════════════════

eps :: Double
eps = 1e-8

-- (D1) Zero-sum: Σ δ_c = 0 per frame
axiom_D1_zeroSum :: FrameDeviation -> Bool
axiom_D1_zeroSum fd =
  let total = sum [cdDelta d | d <- Map.elems (fdDeviations fd)]
  in abs total < eps

-- (D2) Manifold dimension bounded: 0 ≤ dim ≤ 3
axiom_D2_dimBounded :: ManifoldDim -> Bool
axiom_D2_dimBounded md =
  mdEstimate md >= 0 && mdEstimate md <= 3.0 + eps

-- (D3) Temporal ⊥ Spatial: inner product of π₁(d) and π₂(d) = 0
--   This follows from DirectSum: inject1(R1) lives in (a,0,0),
--   inject2(R2) lives in (0,b,c). Their dot product = 0 always.
axiom_D3_orthogonal :: R3 -> Bool
axiom_D3_orthogonal v =
  let t = inject1 (project1 v)  -- (a, 0, 0)
      s = inject2 (project2 v)  -- (0, b, c)
      dot = r3x t * r3x s + r3y t * r3y s + r3z t * r3z s
  in abs dot < eps

-- (D4) Null model → expected deviation magnitude near binomial SD
--   For B(4096, 1/256): E[magnitude²] = 256 × Var[count_c] = 256 × 15.94
--   So E[magnitude] ≈ √(256 × 15.94) ≈ 63.9
axiom_D4_nullModel :: [FrameDeviation] -> Bool
axiom_D4_nullModel fds =
  let mags = [fdMagnitude fd | fd <- fds]
      meanMag = sum mags / fromIntegral (length mags)
      expectedMag = sqrt (256.0 * 4096.0 * (1/256) * (255/256))  -- ≈ 63.9
  in abs (meanMag - expectedMag) < 15.0  -- within reasonable bounds

-- (D5) χ² ≥ 0 always
axiom_D5_chiSqNonNeg :: FrameDeviation -> Bool
axiom_D5_chiSqNonNeg fd =
  let chiSq = sum [cdDelta d ^ (2::Int) / binomialE | d <- Map.elems (fdDeviations fd)]
  in chiSq >= 0

-- (D6) Manifold dimension is permutation-invariant
axiom_D6_permInvariant :: Map Int Int -> Bool
axiom_D6_permInvariant counts =
  let dim1 = estimateManifoldDim counts
      -- Reverse the color labels
      reversed = Map.fromList (zip [255,254..0] (Map.elems counts))
      dim2 = estimateManifoldDim reversed
  in abs (mdEstimate dim1 - mdEstimate dim2) < eps
  && abs (mdEntropy dim1 - mdEntropy dim2) < eps

-- (D7) Decomposition identity: d = inject1(π₁(d)) + inject2(π₂(d))
axiom_D7_decomposition :: R3 -> Bool
axiom_D7_decomposition v =
  let reconstructed = vadd (inject1 (project1 v)) (inject2 (project2 v))
  in abs (r3x v - r3x reconstructed) < eps
  && abs (r3y v - r3y reconstructed) < eps
  && abs (r3z v - r3z reconstructed) < eps

-- ════════════════════════════════════════════════════════════════
-- § 12. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " DeviationManifold: Binomial Deviation as 1D + 2D = 3D"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""

  -- Generate 4 manifold types
  let singleC  = generateSingleColor 128
      gradient = generateGradient 42
      photo    = generatePhotoLike 42
      noise    = generateNoise 42

  -- Compute deviation fields
  let devSingle = computeFrameDeviation 0 singleC
      devGrad   = computeFrameDeviation 0 gradient
      devPhoto  = computeFrameDeviation 0 photo
      devNoise  = computeFrameDeviation 0 noise

  -- Manifold dimensions
  let dimSingle = estimateManifoldDim (toCounts singleC)
      dimGrad   = estimateManifoldDim (toCounts gradient)
      dimPhoto  = estimateManifoldDim (toCounts photo)
      dimNoise  = estimateManifoldDim (toCounts noise)

  putStrLn "── Manifold Dimensions ──"
  putStrLn ""
  putStrLn "  generator   │ dim  │ entropy │ participation │ colors>0 │ ‖δ‖"
  putStrLn "  ────────────┼──────┼─────────┼──────────────┼──────────┼──────"
  let showRow name dim dev counts =
        let used = length [c | c <- Map.elems counts, c > 0]
        in putStrLn $ "  " ++ padR 12 name
            ++ "│ " ++ padL 4 (showF (mdEstimate dim))
            ++ " │ " ++ padL 7 (showF (mdEntropy dim))
            ++ " │ " ++ padL 12 (showF (mdParticipation dim))
            ++ " │ " ++ padL 8 (show used)
            ++ " │ " ++ showF (fdMagnitude dev)
  showRow "0D single" dimSingle devSingle (toCounts singleC)
  showRow "1D gradient" dimGrad devGrad (toCounts gradient)
  showRow "2D photo" dimPhoto devPhoto (toCounts photo)
  showRow "3D noise" dimNoise devNoise (toCounts noise)
  putStrLn ""

  -- Show the inverse relationship: dim ↑ → deviation ↓
  putStrLn "── Key Relationship: manifold dim ↑ ⟹ ‖deviation‖ ↓ ──"
  putStrLn ""
  putStrLn $ "  0D (point):   dim=" ++ showF (mdEstimate dimSingle)
        ++ "  ‖δ‖=" ++ showF (fdMagnitude devSingle) ++ "  ← MAXIMAL deviation"
  putStrLn $ "  1D (curve):   dim=" ++ showF (mdEstimate dimGrad)
        ++ "  ‖δ‖=" ++ showF (fdMagnitude devGrad) ++ "  ← heavy tails"
  putStrLn $ "  2D (surface): dim=" ++ showF (mdEstimate dimPhoto)
        ++ "  ‖δ‖=" ++ showF (fdMagnitude devPhoto) ++ "  ← moderate"
  putStrLn $ "  3D (volume):  dim=" ++ showF (mdEstimate dimNoise)
        ++ "  ‖δ‖=" ++ showF (fdMagnitude devNoise) ++ "  ← MINIMAL (binomial)"
  putStrLn ""

  -- Zero-sum demonstration
  putStrLn "── Axiom D1: Zero-Sum (Σ δ_c = 0) ──"
  putStrLn ""
  let showSum name dev =
        let total = sum [cdDelta d | d <- Map.elems (fdDeviations dev)]
        in putStrLn $ "  " ++ padR 12 name ++ "Σδ = " ++ showF total
  showSum "0D single " devSingle
  showSum "1D gradient" devGrad
  showSum "2D photo  " devPhoto
  showSum "3D noise  " devNoise
  putStrLn ""

  -- Direct sum decomposition
  putStrLn "── Direct Sum Decomposition: dev = π₁(temporal) ⊕ π₂(spatial) ──"
  putStrLn ""

  -- Generate multiple noise frames for temporal decomposition
  let noiseFrames = [generateNoise (42 + i) | i <- [0..7]]
      noiseDevs = [computeFrameDeviation i f | (i, f) <- zip [0..] noiseFrames]
      temporal = projectDeviationTemporal noiseDevs
  putStrLn "  Temporal envelope (π₁) for 8 noise frames:"
  putStrLn "  frame │ ‖deviation‖ (R1 scalar)"
  putStrLn "  ──────┼────────────────────────"
  mapM_ (\(z, R1 mag) ->
    putStrLn $ "  " ++ padL 5 (show z) ++ " │ " ++ showF mag
            ++ "  " ++ replicate (round (mag / 2)) '█'
    ) (Map.toAscList temporal)
  putStrLn ""

  -- Show spatial texture for one noise frame
  let spatialFields = projectDeviationSpatial [devNoise]
                        (Map.singleton 0 noise)
      field0 = Map.findWithDefault Map.empty 0 spatialFields
      samplePixels = [((x,y), r2) | ((x,y), r2) <- Map.toList field0
                     , x `mod` 16 == 0, y `mod` 16 == 0]
  putStrLn "  Spatial texture (π₂) sample pixels in noise frame:"
  putStrLn "  (x,y)  │ R2 = (δ_color, δ_clustering)"
  putStrLn "  ───────┼──────────────────────────────"
  mapM_ (\((x,y), R2 dc ds) ->
    putStrLn $ "  (" ++ padL 2 (show x) ++ "," ++ padL 2 (show y) ++ ")"
            ++ " │ (" ++ padL 6 (showF dc) ++ ", " ++ padL 6 (showF ds) ++ ")"
    ) (take 8 samplePixels)
  putStrLn ""

  -- Manifold comparison via Wasserstein
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " MANIFOLD COMPARISON (Wasserstein-1 on deviation vectors)"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  let allDevs = [("0D single", devSingle, dimSingle),
                 ("1D grad  ", devGrad, dimGrad),
                 ("2D photo ", devPhoto, dimPhoto),
                 ("3D noise ", devNoise, dimNoise)]
  putStrLn "  Wasserstein distance matrix:"
  putStrLn $ "             │ " ++ unwords [padL 10 n | (n,_,_) <- allDevs]
  putStrLn $ "  ───────────┼" ++ replicate (11 * length allDevs) '─'
  mapM_ (\(n1, d1, _) -> do
    let dists = [wassersteinDeviation d1 d2 | (_, d2, _) <- allDevs]
    putStrLn $ "  " ++ padR 11 n1 ++ "│ "
            ++ unwords [padL 10 (showF d) | d <- dists]
    ) allDevs
  putStrLn ""

  putStrLn "  Shape distance matrix (manifold dimensions):"
  putStrLn $ "             │ " ++ unwords [padL 10 n | (n,_,_) <- allDevs]
  putStrLn $ "  ───────────┼" ++ replicate (11 * length allDevs) '─'
  mapM_ (\(n1, _, m1) -> do
    let dists = [shapeDistance m1 m2 | (_, _, m2) <- allDevs]
    putStrLn $ "  " ++ padR 11 n1 ++ "│ "
            ++ unwords [padL 10 (showF d) | d <- dists]
    ) allDevs
  putStrLn ""

  -- Axiom verification
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " AXIOM VERIFICATION"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""

  let allFrameDevs = [devSingle, devGrad, devPhoto, devNoise]
  let testVecs = [R3 1 2 3, R3 0 0 0, R3 (-1) 5 (-2), R3 0.5 0.3 0.8]

  check "D1 zero-sum: Σδ_c = 0"
    [axiom_D1_zeroSum fd | fd <- allFrameDevs]

  check "D2 dim bounded: 0 ≤ dim ≤ 3"
    [axiom_D2_dimBounded d | d <- [dimSingle, dimGrad, dimPhoto, dimNoise]]

  check "D3 temporal ⊥ spatial"
    [axiom_D3_orthogonal v | v <- testVecs]

  -- Generate 20 noise frames for D4
  let manyNoiseDevs = [computeFrameDeviation i (generateNoise (100+i)) | i <- [0..19]]
  check "D4 null model: E[‖δ‖] ≈ 63.9"
    [axiom_D4_nullModel manyNoiseDevs]

  check "D5 χ² ≥ 0"
    [axiom_D5_chiSqNonNeg fd | fd <- allFrameDevs]

  check "D6 permutation invariant"
    [axiom_D6_permInvariant (toCounts f) | f <- [singleC, gradient, photo, noise]]

  check "D7 decomposition identity"
    [axiom_D7_decomposition v | v <- testVecs]

  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " THE MANIFOLD INTERPRETATION"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  A 64³ tensor's color distribution traces a MANIFOLD"
  putStrLn "  through the sRGB cube. The manifold's dimension"
  putStrLn "  determines the deviation from binomial:"
  putStrLn ""
  putStrLn "    dim(manifold) + ‖deviation‖ / ‖deviation_max‖ ≈ constant"
  putStrLn ""
  putStrLn "  The deviation itself decomposes via direct sum:"
  putStrLn "    deviation = temporal ⊕ spatial"
  putStrLn "    π₁ = WHEN (which frames deviate most)"
  putStrLn "    π₂ = WHERE (which pixels carry the deviation)"
  putStrLn ""
  putStrLn "  For the neural network:"
  putStrLn "    Type A head sees δ(A,B) — the signed difference"
  putStrLn "    between two manifolds' deviations (torsor)."
  putStrLn "    Type B head measures the GAP between a K-color"
  putStrLn "    manifold and a 256-color manifold (projection)."
  putStrLn ""
  putStrLn "  The deviation from binomial IS the information content."
  putStrLn "  The manifold dimension IS the compression ratio."
  putStrLn "  1D + 2D = 3D IS the structure of that information."
  putStrLn "══════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

toCounts :: Map Int [Spatial] -> Map Int Int
toCounts = Map.map length

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 100) :: Int) / 100.0 :: Double)
          in take 7 (s ++ repeat '0')

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

padR :: Int -> String -> String
padR n s = s ++ replicate (max 0 (n - length s)) ' '

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      n = length results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name ++ " (" ++ show n ++ " cases)"
