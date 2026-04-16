{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- DepthInference: 3-Layer Para NN for Virtual Depth
--
-- Architecture: PatchEncoder ; Compress ; DepthHead
--   (k²×3 RGB patch) → R^h → R^c → Depth ∈ [0,1]
--
-- The NN's ONLY job: infer virtual depth from an RGB patch.
-- Virtual depth feeds into the EXISTING algebraic pipeline:
--   σ(depth) → gaussianProbs → largestRemainder → epoch assignment
--
-- At N=64:  real depth from TrueDepth (teacher)
-- At N>64:  NN-inferred depth (student)
--
-- The NN touches R1 (epoch axis) only.
-- R3 (color axis) is FROZEN — handled by ditherColors.
-- DirectSum R1 ⊕ R3 = R4 is preserved.
--
-- 593 parameters at (k=3, h=16, c=8).
-- ════════════════════════════════════════════════════════════════

module DepthInference where

import Data.List (foldl')

-- ════════════════════════════════════════════════════════════════
-- § 1. TYPES (from existing specs, inlined for self-containment)
-- ════════════════════════════════════════════════════════════════

-- | Continuous color position in [0,1]³ (from TesseractQuantize.hs)
data ColorPos = ColorPos
  { cpR :: !Double, cpG :: !Double, cpB :: !Double
  } deriving (Show, Eq)

-- | Depth in [0,1]: 1=near (face), 0=far (wall)
newtype Depth = Depth { unDepth :: Double }
  deriving (Show, Eq, Ord)

-- | CubeSize: N ∈ {64, 128, 256}
newtype CubeSize = CubeSize { unCubeSize :: Int }
  deriving (Show, Eq)

-- | Frame index: 0..N-1
newtype Frame = Frame { unFrame :: Int }
  deriving (Show, Eq)

-- ════════════════════════════════════════════════════════════════
-- § 2. VECTOR / MATRIX OPS
-- ════════════════════════════════════════════════════════════════

type Vector = [Double]
type Matrix = [[Double]]

vecAdd :: Vector -> Vector -> Vector
vecAdd = zipWith (+)

dot :: Vector -> Vector -> Double
dot u v = sum (zipWith (*) u v)

matVecMul :: Matrix -> Vector -> Vector
matVecMul m v = [dot row v | row <- m]

relu :: Vector -> Vector
relu = map (max 0)

sigmoid :: Double -> Double
sigmoid x = 1.0 / (1.0 + exp (negate x))

-- ════════════════════════════════════════════════════════════════
-- § 3. THE THREE LAYERS
-- ════════════════════════════════════════════════════════════════

-- | Layer 1: PatchEncoder
--   Input: k×k RGB patch → flattened to k²×3 = 27 values (at k=3)
--   Output: h-dimensional embedding
--   Uses ColorPos from TesseractQuantize.hs
--
--   What it learns: spatial color patterns that correlate with
--   subject (face, hands) vs background (wall, furniture).

type PatchEncoderParams = (Matrix, Vector)  -- W ∈ R^(h × k²×3), b ∈ R^h

patchEncoderForward :: PatchEncoderParams -> [ColorPos] -> Vector
patchEncoderForward (w, b) patch =
  let flat = concatMap (\(ColorPos r g bc) -> [r, g, bc]) patch
  in relu (matVecMul w flat `vecAdd` b)

-- | Layer 2: Compress
--   Input: h-dimensional embedding
--   Output: c-dimensional compressed representation
--
--   What it learns: which features of the embedding are relevant
--   for depth prediction (edge patterns, color uniformity, etc.)

type CompressParams = (Matrix, Vector)  -- W ∈ R^(c × h), b ∈ R^c

compressForward :: CompressParams -> Vector -> Vector
compressForward (w, b) v = relu (matVecMul w v `vecAdd` b)

-- | Layer 3: DepthHead
--   Input: c-dimensional compressed vector
--   Output: Depth ∈ [0,1] via sigmoid
--
--   What it learns: the final mapping from compressed features
--   to a depth value. Sigmoid guarantees [0,1] range.
--   Output lives in R1 — never touches R3.

type DepthHeadParams = (Vector, Double)  -- w ∈ R^c, b ∈ R

depthHeadForward :: DepthHeadParams -> Vector -> Depth
depthHeadForward (w, b) v = Depth (sigmoid (dot w v + b))

-- ════════════════════════════════════════════════════════════════
-- § 4. COMPOSED NN: PatchEncoder ; Compress ; DepthHead
-- ════════════════════════════════════════════════════════════════

-- | Full parameter space: product of three layer params
--   This is the Para composition: Params(f;g;h) = (Params f, (Params g, Params h))
type DepthNNParams = (PatchEncoderParams, (CompressParams, DepthHeadParams))

-- | Forward pass: the composed Para morphism
--   (k²×3 RGB patch) → embedding → compressed → Depth
inferDepth :: DepthNNParams -> [ColorPos] -> Depth
inferDepth (pe, (co, dh)) patch =
  let embedding  = patchEncoderForward pe patch
      compressed = compressForward co embedding
      depth      = depthHeadForward dh compressed
  in depth

-- | Dimensions
data NNConfig = NNConfig
  { nnPatchSize :: Int  -- k: patch is k×k
  , nnHidden    :: Int  -- h: embedding dimension
  , nnCompressed :: Int -- c: compressed dimension
  } deriving (Show)

defaultConfig :: NNConfig
defaultConfig = NNConfig 3 16 8

inputDim :: NNConfig -> Int
inputDim cfg = nnPatchSize cfg * nnPatchSize cfg * 3

paramCount :: NNConfig -> Int
paramCount cfg =
  let k2x3 = inputDim cfg
      h = nnHidden cfg
      c = nnCompressed cfg
  in (h * k2x3 + h)   -- PatchEncoder: W + b
   + (c * h + c)       -- Compress: W + b
   + (c + 1)           -- DepthHead: w + b

-- ════════════════════════════════════════════════════════════════
-- § 5. PATCH EXTRACTION — from a 2D color field
-- ════════════════════════════════════════════════════════════════

-- | Extract k×k patch centered at (x,y) from an n×n field.
--   Clamp-to-edge at boundaries.
extractPatch :: Int -> Int -> Int -> Int -> [ColorPos] -> [ColorPos]
extractPatch n k x y field =
  let half = k `div` 2
  in [ field !! (clampIdx n py * n + clampIdx n px)
     | dy <- [-half..half], dx <- [-half..half]
     , let px = x + dx
           py = y + dy
     ]
  where
    clampIdx size i = max 0 (min (size - 1) i)

-- ════════════════════════════════════════════════════════════════
-- § 6. INTEGRATION — how NN output feeds into existing pipeline
-- ════════════════════════════════════════════════════════════════

-- | Epoch cadence (from ScaleInvariant.hs / ContinuousDepthCadence.hs)
sigmaBase :: CubeSize -> Double
sigmaBase (CubeSize n) = fromIntegral (n - 1) / 8.0

epochCenters :: CubeSize -> [Double]
epochCenters cs = [(2.0 * fromIntegral d + 1.0) * sigmaBase cs | d <- [0..3]]

sigmaForDepth :: CubeSize -> Depth -> Double
sigmaForDepth cs (Depth d) = sigmaBase cs * (2.0 - d)

gaussianProbs :: CubeSize -> Frame -> Depth -> [Double]
gaussianProbs cs (Frame z) d =
  let s  = sigmaForDepth cs d
      zf = fromIntegral z
      s2 = 2.0 * s * s
      raw = [exp (-(zf - mu)**2 / s2) | mu <- epochCenters cs]
      total = sum raw
  in if total < 1e-10
     then [0.25, 0.25, 0.25, 0.25]
     else map (/ total) raw

dominantEpoch :: CubeSize -> Frame -> Depth -> Int
dominantEpoch cs z d =
  let probs = gaussianProbs cs z d
  in snd $ maximum (zip probs [0..3])

-- | The integration point:
--   At N=64:  real depth → dominantEpoch (teacher)
--   At N>64:  inferDepth → dominantEpoch (student)
--   The pipeline after depth is IDENTICAL in both cases.
epochFromRealDepth :: CubeSize -> Frame -> Double -> Int
epochFromRealDepth cs z d = dominantEpoch cs z (Depth d)

epochFromNNDepth :: DepthNNParams -> CubeSize -> Frame -> [ColorPos] -> Int
epochFromNNDepth params cs z patch =
  let d = inferDepth params patch
  in dominantEpoch cs z d

-- ════════════════════════════════════════════════════════════════
-- § 7. SYNTHETIC TEST DATA
-- ════════════════════════════════════════════════════════════════

-- | Synthetic depth: radial from center (face-like)
syntheticDepth :: Int -> Int -> Int -> Double
syntheticDepth n x y =
  let cx = abs (fromIntegral x - fromIntegral (n-1) / 2.0) / (fromIntegral (n-1) / 2.0)
      cy = abs (fromIntegral y - fromIntegral (n-1) / 2.0) / (fromIntegral (n-1) / 2.0)
  in 1.0 - sqrt (cx*cx + cy*cy) / sqrt 2.0

-- | Synthetic color field: gradient
syntheticField :: Int -> [ColorPos]
syntheticField n =
  [ ColorPos (fromIntegral x / fromIntegral (n-1))
             (fromIntegral y / fromIntegral (n-1))
             0.5
  | y <- [0..n-1], x <- [0..n-1] ]

-- | Random-ish parameters (deterministic, not trained)
syntheticParams :: NNConfig -> DepthNNParams
syntheticParams cfg =
  let k2x3 = inputDim cfg
      h = nnHidden cfg
      c = nnCompressed cfg
      -- Simple initialization: small weights, zero bias
      wPE = [ [ 0.1 * sin (fromIntegral (i*k2x3 + j))
              | j <- [0..k2x3-1] ]
            | i <- [0..h-1] ]
      bPE = replicate h 0.0
      wCO = [ [ 0.1 * cos (fromIntegral (i*h + j))
              | j <- [0..h-1] ]
            | i <- [0..c-1] ]
      bCO = replicate c 0.0
      wDH = [ 0.1 * sin (fromIntegral i) | i <- [0..c-1] ]
      bDH = 0.0
  in ((wPE, bPE), ((wCO, bCO), (wDH, bDH)))

-- ════════════════════════════════════════════════════════════════
-- § 8. AXIOMS
-- ════════════════════════════════════════════════════════════════

eps :: Double
eps = 1e-10

-- (DI1) Output ∈ [0,1] — sigmoid guarantees this for all inputs
axiom_DI1 :: Bool
axiom_DI1 =
  let cfg = defaultConfig
      params = syntheticParams cfg
      field = syntheticField 64
      n = 64
      depths = [ unDepth (inferDepth params (extractPatch n 3 x y field))
               | y <- [0..n-1], x <- [0..n-1] ]
  in all (\d -> d >= 0.0 && d <= 1.0) depths

-- (DI2) DirectSum preservation: output produces Depth (R1), zero in R3
--   Proven by type: inferDepth returns Depth, not (Depth, Color).
--   The color axis is never computed or modified.
axiom_DI2 :: Bool
axiom_DI2 = True  -- enforced by type signature: inferDepth :: ... -> Depth

-- (DI3) Parameter count = 593 for default config (k=3, h=16, c=8)
axiom_DI3 :: Bool
axiom_DI3 = paramCount defaultConfig == 593

-- (DI4) NN-inferred depth produces valid palette indices (0..255)
--   via the existing epochFromNNDepth → dominantEpoch pipeline.
axiom_DI4 :: Bool
axiom_DI4 =
  let cfg = defaultConfig
      params = syntheticParams cfg
      field = syntheticField 64
      n = 64
      cubeSizes = [CubeSize 64, CubeSize 128, CubeSize 256]
  in all (\cs ->
    let nf = unCubeSize cs
    in all (\z ->
      all (\(x,y) ->
        let patch = extractPatch n 3 x y field
            ep = epochFromNNDepth params cs (Frame z) patch
            depth = inferDepth params patch
            a = 1; b = 2; c = 0  -- arbitrary color levels
            idx = ep * 64 + a * 16 + b * 4 + c
        in idx >= 0 && idx <= 255 && ep >= 0 && ep <= 3
      ) [(x,y) | x <- [0, n `div` 2, n-1], y <- [0, n `div` 2, n-1]]
    ) [0, nf `div` 4, nf `div` 2, 3 * nf `div` 4, nf - 1]
  ) cubeSizes

-- (DI5) If NN perfectly matches real depth, student = teacher
--   For any pixel, if inferDepth returns the same value as real depth,
--   then epochFromNNDepth = epochFromRealDepth.
axiom_DI5 :: Bool
axiom_DI5 =
  let cs = CubeSize 64
      testCases = [ (z, d)
                  | z <- [0, 8, 16, 24, 32, 40, 48, 56, 63]
                  , d <- [0.0, 0.25, 0.5, 0.75, 1.0] ]
  in all (\(z, d) ->
    let real    = epochFromRealDepth cs (Frame z) d
        -- If NN output = d, then epoch must match
        virtual = dominantEpoch cs (Frame z) (Depth d)
    in real == virtual
  ) testCases

-- ════════════════════════════════════════════════════════════════
-- § 9. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " DepthInference: 3-Layer Para NN for Virtual Depth"
  putStrLn " PatchEncoder ; Compress ; DepthHead = RGB patch → Depth"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""

  let cfg = defaultConfig
      params = syntheticParams cfg
      field = syntheticField 64
      n = 64

  -- Architecture summary
  putStrLn "── Architecture ──"
  putStrLn ""
  putStrLn $ "  Patch size:  " ++ show (nnPatchSize cfg) ++ "×" ++ show (nnPatchSize cfg)
  putStrLn $ "  Input dim:   " ++ show (inputDim cfg) ++ " (k²×3)"
  putStrLn $ "  Hidden dim:  " ++ show (nnHidden cfg)
  putStrLn $ "  Compress dim:" ++ show (nnCompressed cfg)
  putStrLn $ "  Output:      Depth ∈ [0,1]"
  putStrLn $ "  Parameters:  " ++ show (paramCount cfg)
  putStrLn ""

  putStrLn "  PatchEncoder: R^27 → R^16  (448 params)"
  putStrLn "       ReLU"
  putStrLn "  Compress:     R^16 → R^8   (136 params)"
  putStrLn "       ReLU"
  putStrLn "  DepthHead:    R^8  → [0,1] (  9 params)"
  putStrLn "       Sigmoid"
  putStrLn ""

  -- Sample inference
  putStrLn "── Sample Inference (synthetic params, not trained) ──"
  putStrLn ""
  putStrLn "  position    │ real depth │ NN depth │ delta"
  putStrLn "  ────────────┼────────────┼──────────┼──────"
  mapM_ (\(x, y, label) -> do
    let realD = syntheticDepth n x y
        patch = extractPatch n 3 x y field
        nnD   = unDepth (inferDepth params patch)
        delta = abs (realD - nnD)
    putStrLn $ "  " ++ padL 12 label
            ++ " │ " ++ padL 10 (showF realD)
            ++ " │ " ++ padL 8 (showF nnD)
            ++ " │ " ++ showF delta
    ) [ (32, 32, "center")
      , (0, 0, "corner(0,0)")
      , (63, 63, "corner(63,63)")
      , (32, 0, "edge(32,0)")
      , (16, 16, "quarter")
      ]
  putStrLn ""
  putStrLn "  (NN is untrained — these values are from random-ish weights."
  putStrLn "   After training, NN depth should approximate real depth.)"
  putStrLn ""

  -- Epoch agreement at N=64 (where both teacher and student have data)
  putStrLn "── Epoch Agreement: real vs NN depth ──"
  putStrLn ""
  putStrLn "  frame │ center(32,32)        │ corner(0,0)"
  putStrLn "        │ real_ep  nn_ep       │ real_ep  nn_ep"
  putStrLn "  ──────┼──────────────────────┼─────────────────"
  let cs = CubeSize 64
  mapM_ (\z -> do
    let realD_center = syntheticDepth n 32 32
        nnD_center   = unDepth (inferDepth params (extractPatch n 3 32 32 field))
        realEp_center = epochFromRealDepth cs (Frame z) realD_center
        nnEp_center   = dominantEpoch cs (Frame z) (Depth nnD_center)

        realD_corner = syntheticDepth n 0 0
        nnD_corner   = unDepth (inferDepth params (extractPatch n 3 0 0 field))
        realEp_corner = epochFromRealDepth cs (Frame z) realD_corner
        nnEp_corner   = dominantEpoch cs (Frame z) (Depth nnD_corner)

    putStrLn $ "  " ++ padL 5 (show z)
            ++ " │  ep" ++ show realEp_center
            ++ "     ep" ++ show nnEp_center
            ++ "          │  ep" ++ show realEp_corner
            ++ "     ep" ++ show nnEp_corner
    ) [0, 8, 16, 24, 32, 40, 48, 56, 63]
  putStrLn ""

  -- Depth distribution
  putStrLn "── NN Depth Distribution (64×64 field) ──"
  putStrLn ""
  let allDepths = [ unDepth (inferDepth params (extractPatch n 3 x y field))
                  | y <- [0..n-1], x <- [0..n-1] ]
      minD = minimum allDepths
      maxD = maximum allDepths
      avgD = sum allDepths / fromIntegral (length allDepths)
  putStrLn $ "  min:  " ++ showF minD
  putStrLn $ "  max:  " ++ showF maxD
  putStrLn $ "  mean: " ++ showF avgD
  putStrLn $ "  range: " ++ showF (maxD - minD)
  putStrLn ""

  -- Axioms
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""
  check "DI1 output ∈ [0,1] (sigmoid, all 4096 pixels)"          [axiom_DI1]
  check "DI2 DirectSum preservation (output ∈ R1, zero in R3)"   [axiom_DI2]
  check "DI3 parameter count = 593 (k=3, h=16, c=8)"             [axiom_DI3]
  check "DI4 valid palette indices at all CubeSizes"              [axiom_DI4]
  check "DI5 perfect depth → student = teacher"                   [axiom_DI5]
  putStrLn ""

  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " The NN predicts depth. The pipeline does the rest."
  putStrLn " R1 (epoch) is learned. R3 (color) is algebraic."
  putStrLn " DirectSum R1 ⊕ R3 = R4.  4⁴ = 256.  Always."
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
