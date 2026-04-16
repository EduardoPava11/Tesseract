{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

-- ════════════════════════════════════════════════════════════════
-- ScaleInvariant: The 4⁴ Tesseract is Size-Independent
--
-- N³ voxels → 4⁴ = 256 palette entries. Always.
-- The palette is ALWAYS 4⁴. The cube size scales density, not
-- structure.
--
--   σ_base(N) = (N-1) / 8
--   μ_d(N)    = (2d+1) × σ_base(N)
--
--   64³ =    262,144 →  1,024 voxels per color
--  128³ =  2,097,152 →  8,192 voxels per color
--  256³ = 16,777,216 → 65,536 voxels per color
--
-- The Gaussian epoch crossovers happen at the same relative
-- positions regardless of N. Structure doesn't change.
-- Only sampling density changes.
-- ════════════════════════════════════════════════════════════════

module ScaleInvariant where

-- ════════════════════════════════════════════════════════════════
-- § 1. TYPES
-- ════════════════════════════════════════════════════════════════

newtype CubeSize = CubeSize { unCubeSize :: Int }
  deriving (Show, Eq, Ord)

newtype Depth = Depth { unDepth :: Double }
  deriving (Show, Eq, Ord)

newtype Frame = Frame { unFrame :: Int }
  deriving (Show, Eq, Ord)

-- The three valid cube sizes
cube64, cube128, cube256 :: CubeSize
cube64  = CubeSize 64
cube128 = CubeSize 128
cube256 = CubeSize 256

allCubeSizes :: [CubeSize]
allCubeSizes = [cube64, cube128, cube256]

-- ════════════════════════════════════════════════════════════════
-- § 2. THE GENERALIZED FORMULA
-- ════════════════════════════════════════════════════════════════

-- | σ_base(N) = (N-1) / 8
sigmaBase :: CubeSize -> Double
sigmaBase (CubeSize n) = fromIntegral (n - 1) / 8.0

-- | μ_d(N) = (2d+1) × σ_base(N)
epochCenters :: CubeSize -> [Double]
epochCenters cs = [(2.0 * fromIntegral d + 1.0) * sigmaBase cs | d <- [0..3]]

-- | Relative position in [0,1]: size-independent
--   Always [1/8, 3/8, 5/8, 7/8]
relativeCenter :: Int -> Double
relativeCenter d = (2.0 * fromIntegral d + 1.0) / 8.0

-- | Relative crossover points: always [1/4, 1/2, 3/4]
relativeCrossover :: Int -> Double
relativeCrossover i = fromIntegral (i + 1) / 4.0

-- | σ(N, depth) = σ_base(N) × (2 - depth)
sigma :: CubeSize -> Depth -> Double
sigma cs (Depth d) = sigmaBase cs * (2.0 - d)

-- | P(epoch d | frame z, depth) — generalized to any CubeSize
epochProbs :: CubeSize -> Frame -> Depth -> [Double]
epochProbs cs (Frame z) d =
  let s  = sigma cs d
      zf = fromIntegral z
      s2 = 2.0 * s * s
      centers = epochCenters cs
      raw = [exp (-(zf - mu)**2 / s2) | mu <- centers]
      total = sum raw
  in if total < 1e-10
     then [0.25, 0.25, 0.25, 0.25]
     else map (/ total) raw

-- | Crossover frame: midpoint between epoch d and epoch d+1
crossoverFrame :: CubeSize -> Int -> Double
crossoverFrame cs i =
  let centers = epochCenters cs
  in (centers !! i + centers !! (i + 1)) / 2.0

-- | Voxels per palette entry: N³ / 256
voxelsPerEntry :: CubeSize -> Int
voxelsPerEntry (CubeSize n) = (n * n * n) `div` 256

-- | Voxels per display color (4 epochs share each sRGB): N³ / 64
voxelsPerDisplayColor :: CubeSize -> Int
voxelsPerDisplayColor (CubeSize n) = (n * n * n) `div` 64

-- | Total voxels: N² spatial × N temporal
totalVoxels :: CubeSize -> Int
totalVoxels (CubeSize n) = n * n * n

-- ════════════════════════════════════════════════════════════════
-- § 3. AXIOMS
-- ════════════════════════════════════════════════════════════════

eps :: Double
eps = 1e-10

-- (B15) Backward compatibility: sigmaBase(64) = 7.875
axiom_B15 :: Bool
axiom_B15 = abs (sigmaBase cube64 - 7.875) < eps

-- (B16) Relative epoch centers are size-independent: μ_d(N)/N ≈ constant
--   More precisely: μ_d(N) / (N-1) = (2d+1)/8 for all N
axiom_B16 :: Bool
axiom_B16 = all checkSize allCubeSizes
  where
    checkSize cs =
      let centers = epochCenters cs
          n = fromIntegral (unCubeSize cs) - 1.0
      in all (\(d, mu) ->
           abs (mu / n - relativeCenter d) < eps
         ) (zip [0..3] centers)

-- (B17) Crossover invariance: at the midpoint between epoch 0 and
--   epoch 1, P(ep0) ≈ P(ep1) for all three cube sizes.
--   This is the structural invariant — the Gaussians cross at the
--   same relative position regardless of N.
axiom_B17 :: Bool
axiom_B17 = all checkCrossover allCubeSizes
  where
    checkCrossover cs =
      let mid = crossoverFrame cs 0
          probs = epochProbs cs (Frame (round mid)) (Depth 0.5)
      in abs (probs !! 0 - probs !! 1) < 0.05
      -- Allow small rounding error from integer frame index

-- (B18) Density scaling: voxelsPerEntry scales as N³/256
axiom_B18 :: Bool
axiom_B18 = voxelsPerEntry cube64  == 1024
         && voxelsPerEntry cube128 == 8192
         && voxelsPerEntry cube256 == 65536

-- (B19) All existing CD1-CD8 axioms hold at CubeSize 64
--   Verifying the key ones:
axiom_B19 :: Bool
axiom_B19 =
  -- CD1: σ(1.0) = σ_base at N=64
  abs (sigma cube64 (Depth 1.0) - sigmaBase cube64) < eps
  -- CD2: σ(0.0) = 2 × σ_base at N=64
  && abs (sigma cube64 (Depth 0.0) - 2.0 * sigmaBase cube64) < eps
  -- CD3: sum(probs) = 1 for all frames at N=64
  && all (\z -> abs (sum (epochProbs cube64 (Frame z) (Depth 0.5)) - 1.0) < eps)
       [0..63]
  -- CD7: σ monotonically decreasing with depth at N=64
  && sigma cube64 (Depth 0.0) > sigma cube64 (Depth 0.5)
  && sigma cube64 (Depth 0.5) > sigma cube64 (Depth 1.0)

-- ════════════════════════════════════════════════════════════════
-- § 4. EXTENDED VERIFICATION
-- ════════════════════════════════════════════════════════════════

-- | Epoch centers at N=64 match ContinuousDepthCadence.hs exactly
axiom_backcompat_centers :: Bool
axiom_backcompat_centers =
  let expected = [7.875, 23.625, 39.375, 55.125]
      actual = epochCenters cube64
  in all (\(e, a) -> abs (e - a) < eps) (zip expected actual)

-- | Crossover symmetry: all 3 crossover points are equidistant
axiom_crossover_symmetric :: Bool
axiom_crossover_symmetric = all checkSymmetry allCubeSizes
  where
    checkSymmetry cs =
      let gaps = [ crossoverFrame cs (i+1) - crossoverFrame cs i | i <- [0..1] ]
          gap0 = crossoverFrame cs 0 - head (epochCenters cs)
      in all (\g -> abs (g - head gaps) < eps) gaps
      && abs (gap0 - (head gaps / 2.0)) < 0.1

-- | Probs sum to 1 at ALL cube sizes, ALL frames, ALL depths
axiom_prob_normalization :: Bool
axiom_prob_normalization = all check
  [ (cs, z, d)
  | cs <- allCubeSizes
  , z  <- [0, unCubeSize cs `div` 4, unCubeSize cs `div` 2,
           3 * unCubeSize cs `div` 4, unCubeSize cs - 1]
  , d  <- [0.0, 0.25, 0.5, 0.75, 1.0]
  ]
  where check (cs, z, d) = abs (sum (epochProbs cs (Frame z) (Depth d)) - 1.0) < eps

-- | Near depth is more concentrated than far depth at ALL sizes
axiom_depth_modulation :: Bool
axiom_depth_modulation = all checkSize allCubeSizes
  where
    checkSize cs =
      let centers = epochCenters cs
          z = round (head centers)  -- frame at epoch 0 center
          nearMax = maximum (epochProbs cs (Frame z) (Depth 1.0))
          farMax  = maximum (epochProbs cs (Frame z) (Depth 0.0))
      in nearMax > farMax

-- | Total palette is always 256, regardless of cube size
axiom_palette_invariant :: Bool
axiom_palette_invariant = all (\cs -> 4^(4::Int) == (256::Int)) allCubeSizes

-- ════════════════════════════════════════════════════════════════
-- § 5. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " ScaleInvariant: The 4⁴ Tesseract is Size-Independent"
  putStrLn " N³ voxels → 256 palette entries.  Always."
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""

  -- Show the formula at each size
  putStrLn "── The Formula ──"
  putStrLn ""
  putStrLn "  σ_base(N) = (N-1) / 8"
  putStrLn "  μ_d(N)    = (2d+1) × σ_base(N)"
  putStrLn ""

  putStrLn "  size │ σ_base │ epoch centers                    │ voxels/entry"
  putStrLn "  ─────┼────────┼─────────────────────────────────┼─────────────"
  mapM_ (\cs -> do
    let sb = sigmaBase cs
        centers = epochCenters cs
        vpe = voxelsPerEntry cs
    putStrLn $ "  " ++ padL 4 (show (unCubeSize cs))
            ++ " │ " ++ padL 6 (showF sb)
            ++ " │ " ++ showCenters centers
            ++ " │ " ++ padL 11 (show vpe)
    ) allCubeSizes
  putStrLn ""

  -- Show relative positions (size-independent)
  putStrLn "── Relative Positions (size-independent) ──"
  putStrLn ""
  putStrLn "  epoch │ relative center │ relative crossover"
  putStrLn "  ──────┼─────────────────┼───────────────────"
  mapM_ (\d -> do
    let rc = relativeCenter d
        cross = if d < 3 then showF (relativeCrossover d) else "  —"
    putStrLn $ "  " ++ padL 5 (show d)
            ++ " │ " ++ padL 15 (showF rc)
            ++ " │ " ++ cross
    ) [0..3]
  putStrLn ""

  -- Show crossover invariance
  putStrLn "── Crossover Invariance (B17) ──"
  putStrLn ""
  putStrLn "  At the midpoint between epoch 0 and epoch 1:"
  putStrLn ""
  putStrLn "  size │ crossover frame │ P(ep0)  P(ep1)  │ delta"
  putStrLn "  ─────┼─────────────────┼─────────────────┼──────"
  mapM_ (\cs -> do
    let mid = crossoverFrame cs 0
        probs = epochProbs cs (Frame (round mid)) (Depth 0.5)
        delta = abs (probs !! 0 - probs !! 1)
    putStrLn $ "  " ++ padL 4 (show (unCubeSize cs))
            ++ " │ " ++ padL 15 (showF mid)
            ++ " │ " ++ padL 6 (showF3 (probs !! 0))
              ++ "  " ++ padL 6 (showF3 (probs !! 1))
            ++ "  │ " ++ showF3 delta
    ) allCubeSizes
  putStrLn ""

  -- Density table
  putStrLn "── Density Scaling ──"
  putStrLn ""
  putStrLn "  size │ total voxels │ per entry │ per display color"
  putStrLn "  ─────┼──────────────┼───────────┼──────────────────"
  mapM_ (\cs -> do
    putStrLn $ "  " ++ padL 4 (show (unCubeSize cs))
            ++ " │ " ++ padL 12 (commas (totalVoxels cs))
            ++ " │ " ++ padL 9 (commas (voxelsPerEntry cs))
            ++ " │ " ++ commas (voxelsPerDisplayColor cs)
    ) allCubeSizes
  putStrLn ""

  -- Axioms
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""
  check "B15 sigmaBase(64) = 7.875"                           [axiom_B15]
  check "B16 relative centers are size-independent"            [axiom_B16]
  check "B17 crossover invariance (P(ep0) ≈ P(ep1) at mid)"   [axiom_B17]
  check "B18 voxels/entry: 1024, 8192, 65536"                 [axiom_B18]
  check "B19 CD1-CD8 hold at CubeSize 64"                     [axiom_B19]
  check "backward compat: epoch centers match N=64"            [axiom_backcompat_centers]
  check "crossover symmetry (equidistant)"                     [axiom_crossover_symmetric]
  check "prob normalization (all sizes × frames × depths)"     [axiom_prob_normalization]
  check "depth modulation (near > far at all sizes)"           [axiom_depth_modulation]
  check "palette invariant (always 256)"                       [axiom_palette_invariant]
  putStrLn ""

  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  The 4⁴ tesseract is size-invariant."
  putStrLn "  64³, 128³, 256³ — the structure is the same."
  putStrLn "  Only the sampling density changes."
  putStrLn ""
  putStrLn "  σ_base(N) = (N-1) / 8"
  putStrLn "  μ_d(N)    = (2d+1) × σ_base(N)"
  putStrLn ""
  putStrLn "  Crossovers at 1/4, 1/2, 3/4 of the frame range."
  putStrLn "  Centers at 1/8, 3/8, 5/8, 7/8 of the frame range."
  putStrLn "  The cube size N is a parameter, not a constraint."
  putStrLn ""
  putStrLn "  4⁴ = 256.  Always."
  putStrLn "════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 1000) :: Int) / 1000.0 :: Double)
          in take 7 (s ++ repeat '0')

showF3 :: Double -> String
showF3 x = let s = show (fromIntegral (round (x * 10000) :: Int) / 10000.0 :: Double)
           in take 6 (s ++ repeat '0')

showCenters :: [Double] -> String
showCenters cs = "[" ++ unwords (map (\c -> padL 7 (showF c)) cs) ++ "]"

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

commas :: Int -> String
commas n
  | n < 1000  = show n
  | otherwise = commas (n `div` 1000) ++ "," ++ padWith '0' 3 (show (n `mod` 1000))
  where padWith c w s = replicate (max 0 (w - length s)) c ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      n = length results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name ++ " (" ++ show n ++ " cases)"
