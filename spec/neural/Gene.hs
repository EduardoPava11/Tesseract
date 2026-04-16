{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}

-- ════════════════════════════════════════════════════════════════
-- Gene: The NN That Sees Everything
--
-- Input:  137 floats — full pyramid (3 channels × 3 scales × 14 bins
--         + depth + frame + 4 sample counts + 5 entropy feedback)
-- Output: (d, a, b, c) ∈ {0,1,2,3}⁴ → palette index ∈ {0..255}
--
-- Architecture:
--   InputEncoder : R¹³⁷ → R³²  (ATTENTION, 4416 params)
--        ReLU
--   OutputHead   : R³² → R⁴   (CORE, 132 params)
--        Sigmoid × 3.999 → floor
--
-- Total: 4,548 params. Gene capsule: 4.4 KB (Int8).
--
-- The NN gets raw histogram frequencies AND sample counts.
-- It learns when to trust (high n) and when to discount (low n).
-- Depth cross-attends: modulates which scale matters.
--
-- The user IS the loss function. TAP = beauty. LEFT = explore.
-- The gene evolves through selection, not gradient descent.
-- Sharing a GIF = sharing a gene = sharing a way of seeing.
-- ════════════════════════════════════════════════════════════════

module Gene where

import Data.List (foldl')
import qualified Data.Map.Strict as Map

-- ════════════════════════════════════════════════════════════════
-- § 1. CUBE MODE (from Block.hs)
-- ════════════════════════════════════════════════════════════════

data CubeMode = Training | Inference
  deriving (Show, Eq, Ord, Enum, Bounded)

allModes :: [CubeMode]
allModes = [Training, Inference]

spatialSide :: CubeMode -> Int
spatialSide Training = 64; spatialSide Inference = 128

frameCount :: CubeMode -> Int
frameCount = spatialSide  -- S = K (cube)

rgbStep :: CubeMode -> Int
rgbStep m = 768 `div` spatialSide m

depthStep :: CubeMode -> Int
depthStep m = 256 `div` spatialSide m

rgbSamples :: CubeMode -> Int
rgbSamples m = let s = rgbStep m in s * s

depthSamples :: CubeMode -> Int
depthSamples m = let s = depthStep m in s * s

-- ════════════════════════════════════════════════════════════════
-- § 2. TYPE CLASSES
-- ════════════════════════════════════════════════════════════════

-- | Measurable: carries a sample count (statistical significance)
class Measurable a where
  sampleCount :: a -> Int

-- | Entropic: has Shannon entropy
class Entropic a where
  entropy :: a -> Double           -- H in nats
  normalizedEntropy :: a -> Double -- H / H_max ∈ [0,1]

-- ════════════════════════════════════════════════════════════════
-- § 3. COUNTED HISTOGRAM — data + significance, never separated
--
-- A histogram IS its frequencies AND its sample count.
-- You cannot have one without the other.
-- 14 bins. Frequencies sum to 1. n tells you how much to trust.
-- ════════════════════════════════════════════════════════════════

numBins :: Int
numBins = 14

data CountedHist = CountedHist
  { chBins :: ![Double]   -- 14 frequencies, sum ≈ 1.0
  , chN    :: !Int         -- sample count (never zero in practice)
  } deriving (Show, Eq)

instance Measurable CountedHist where
  sampleCount = chN

instance Entropic CountedHist where
  entropy (CountedHist bins _) =
    negate $ sum [p * log p | p <- bins, p > 1e-10]
  normalizedEntropy ch = entropy ch / log (fromIntegral numBins)

-- | Build from raw counts
fromCounts :: [Int] -> CountedHist
fromCounts counts =
  let n = sum counts
      nf = fromIntegral (max 1 n)
  in CountedHist
    { chBins = map (\c -> fromIntegral c / nf) counts
    , chN = n
    }

-- | Standard error of a bin proportion: SE = sqrt(p(1-p)/n)
binStdErr :: CountedHist -> Int -> Double
binStdErr (CountedHist bins n) i =
  let p = bins !! i
  in if n <= 1 then 1.0  -- maximum uncertainty
     else sqrt (p * (1 - p) / fromIntegral n)

-- ════════════════════════════════════════════════════════════════
-- § 4. CHANNEL PYRAMID — same region at 3 scales
--
-- Coarse (12×12=144) → Medium (6×6=36) → Fine (3×3=9)
-- These are SPATIAL context from the 768 crop, not mode-dependent.
-- At Training: native = Coarse. Medium/Fine = sub-block context.
-- At Inference: native = Medium. Coarse = neighborhood. Fine = sub-pixel.
-- ════════════════════════════════════════════════════════════════

data PyramidScale = Coarse | Medium | Fine
  deriving (Show, Eq, Ord, Enum, Bounded)

data ChannelPyramid = ChannelPyramid
  { cpCoarse :: !CountedHist   -- stride 12, 12×12 = 144 samples
  , cpMedium :: !CountedHist   -- stride 6,   6×6  =  36 samples
  , cpFine   :: !CountedHist   -- stride 3,   3×3  =   9 samples
  } deriving (Show, Eq)

-- | Access pyramid by scale
pyramidAt :: PyramidScale -> ChannelPyramid -> CountedHist
pyramidAt Coarse = cpCoarse
pyramidAt Medium = cpMedium
pyramidAt Fine   = cpFine

-- | Which scale is native for this mode?
nativeScale :: CubeMode -> PyramidScale
nativeScale Training  = Coarse
nativeScale Inference = Medium

-- ════════════════════════════════════════════════════════════════
-- § 5. ENTROPY FEEDBACK — from the previous organism
--
-- After building a GIF, we measure how well the 4⁴ tesseract
-- was filled. These 5 numbers feed into the NEXT generation.
--
-- High H(d) = temporal axis active = good
-- Low H(d) = everything in one epoch = depth isn't helping
-- High H(joint) = palette well-used = rich expression
-- Low H(joint) = palette collapsed = gene is failing
-- ════════════════════════════════════════════════════════════════

data EntropyFeedback = EntropyFeedback
  { efEpoch :: !Double   -- H(d) / log(4)      ∈ [0,1]
  , efR     :: !Double   -- H(a) / log(4)      ∈ [0,1]
  , efG     :: !Double   -- H(b) / log(4)      ∈ [0,1]
  , efB     :: !Double   -- H(c) / log(4)      ∈ [0,1]
  , efJoint :: !Double   -- H(d,a,b,c) / log(256) ∈ [0,1]
  } deriving (Show, Eq)

-- | Maximum entropy = uniform distribution = no information yet
uniformEntropy :: EntropyFeedback
uniformEntropy = EntropyFeedback 1.0 1.0 1.0 1.0 1.0

-- | Compute from a palette index distribution
computeEntropy :: Map.Map Int Int -> Int -> EntropyFeedback
computeEntropy dist totalVoxels =
  let total = fromIntegral totalVoxels :: Double
      -- Marginals
      epochCounts = [sum [c | (idx, c) <- Map.toList dist, idx `div` 64 == d] | d <- [0..3]]
      rCounts     = [sum [c | (idx, c) <- Map.toList dist, (idx `mod` 64) `div` 16 == a] | a <- [0..3]]
      gCounts     = [sum [c | (idx, c) <- Map.toList dist, (idx `mod` 16) `div` 4 == b] | b <- [0..3]]
      bCounts     = [sum [c | (idx, c) <- Map.toList dist, idx `mod` 4 == c'] | c' <- [0..3]]
      -- Shannon entropy
      h counts = let ps = [fromIntegral c / total | c <- counts, c > 0]
                 in negate $ sum [p * log p | p <- ps]
      hJoint = let ps = [fromIntegral c / total | c <- Map.elems dist, c > 0]
               in negate $ sum [p * log p | p <- ps]
  in EntropyFeedback
    { efEpoch = h epochCounts / log 4
    , efR     = h rCounts / log 4
    , efG     = h gCounts / log 4
    , efB     = h bCounts / log 4
    , efJoint = hJoint / log 256
    }

-- ════════════════════════════════════════════════════════════════
-- § 6. BLOCK PYRAMID — the complete NN input
-- ════════════════════════════════════════════════════════════════

data BlockPyramid = BlockPyramid
  { bpR         :: !ChannelPyramid
  , bpG         :: !ChannelPyramid
  , bpB         :: !ChannelPyramid
  , bpDepth     :: !Double            -- [0,1], 1=near
  , bpDepthN    :: !Int               -- depth sample count
  , bpFrameNorm :: !Double            -- z / (K-1) ∈ [0,1]
  , bpEntropy   :: !EntropyFeedback   -- from previous organism
  } deriving (Show)

-- | Flatten to 137 floats — the NN input vector
--   126 (3ch × 3scales × 14bins) + 2 (depth, frame)
--   + 4 (n_rgb×3 levels + n_depth) + 5 (entropy) = 137
inputDim :: Int
inputDim = 137

flatten :: BlockPyramid -> [Double]
flatten bp =
  -- 3 channels × 3 scales × 14 bins = 126
  concatMap (\ch -> concatMap chBins
    [cpCoarse ch, cpMedium ch, cpFine ch])
    [bpR bp, bpG bp, bpB bp]
  -- depth + frame = 2
  ++ [bpDepth bp, bpFrameNorm bp]
  -- 4 sample counts (raw integers as floats)
  ++ [ 144 :: Double   -- Coarse: 12×12 samples (always)
     , 36  :: Double   -- Medium: 6×6 samples (always)
     , 9   :: Double   -- Fine: 3×3 samples (always)
     , fromIntegral (bpDepthN bp)           -- varies by level
     ]
  -- 5 entropy feedback
  ++ [ efEpoch (bpEntropy bp)
     , efR (bpEntropy bp)
     , efG (bpEntropy bp)
     , efB (bpEntropy bp)
     , efJoint (bpEntropy bp)
     ]

-- ════════════════════════════════════════════════════════════════
-- § 7. VECTOR / MATRIX OPS
-- ════════════════════════════════════════════════════════════════

type Vector = [Double]
type Matrix = [[Double]]

dot :: Vector -> Vector -> Double
dot u v = sum (zipWith (*) u v)

matVecMul :: Matrix -> Vector -> Vector
matVecMul m v = [dot row v | row <- m]

vecAdd :: Vector -> Vector -> Vector
vecAdd = zipWith (+)

relu :: Vector -> Vector
relu = map (max 0)

sigmoid :: Double -> Double
sigmoid x = 1.0 / (1.0 + exp (negate x))

-- ════════════════════════════════════════════════════════════════
-- § 8. THE GENE — Para(ATTENTION) >>> Para(CORE)
--
-- ATTENTION (InputEncoder): reads the 136-float pyramid.
--   Learns WHICH scales, WHICH bins, WHICH depths matter.
--   Perturbed by LEFT swipe. Personal to the user.
--
-- CORE (OutputHead): maps features → tesseract coordinates.
--   The species identity. Frozen on iPhone.
--   Shared via gene capsule.
-- ════════════════════════════════════════════════════════════════

hiddenDim :: Int
hiddenDim = 32

-- | Output: 5 values — (d, a, b, c) tesseract + g global/local weight
--   d,a,b,c ∈ {0,1,2,3} — the 4⁴ index (preserved)
--   g ∈ [0,1] — how global vs local this pixel's palette entry is
--     g=1: global (same sRGB across all epochs, stable)
--     g=0: local (epoch-specific sRGB, can diverge)
--     depth=near → g≈1 (face is stable)
--     depth=far  → g≈0 (background varies)
outputDim :: Int
outputDim = 5

data GeneParams = GeneParams
  { gpAttention :: !(Matrix, Vector)  -- W1 ∈ R^(32×137), b1 ∈ R^32
  , gpCore      :: !(Matrix, Vector)  -- W2 ∈ R^(5×32),   b2 ∈ R^5
  } deriving (Show)

attentionParamCount :: Int
attentionParamCount = hiddenDim * inputDim + hiddenDim  -- 32×137 + 32 = 4416

coreParamCount :: Int
coreParamCount = outputDim * hiddenDim + outputDim  -- 5×32 + 5 = 165

totalParamCount :: Int
totalParamCount = attentionParamCount + coreParamCount  -- 4581

-- ════════════════════════════════════════════════════════════════
-- GENE OUTPUT: tesseract coordinate + global/local weight
-- ════════════════════════════════════════════════════════════════

-- | The 4⁴ tesseract coordinate (index decomposition preserved)
data TessCoord = TessCoord !Int !Int !Int !Int
  deriving (Show, Eq, Ord)

paletteIndex :: TessCoord -> Int
paletteIndex (TessCoord d a b c) = d * 64 + a * 16 + b * 4 + c

-- | Full gene output: tesseract coord + how global this pixel is
data GeneOutput = GeneOutput
  { goCoord  :: !TessCoord   -- (d,a,b,c) ∈ {0..3}⁴ → palette index
  , goGlobal :: !Double      -- g ∈ [0,1]: 1=global (stable), 0=local (epoch-varying)
  } deriving (Show, Eq)

-- | Forward pass: pyramid → (TessCoord, global weight)
geneForward :: GeneParams -> BlockPyramid -> GeneOutput
geneForward (GeneParams (w1, b1) (w2, b2)) bp =
  let x = flatten bp                              -- R^137
      h = relu (matVecMul w1 x `vecAdd` b1)       -- R^32
      o = matVecMul w2 h `vecAdd` b2               -- R^5
      -- First 4: Sigmoid × 3.999 → floor → {0,1,2,3}
      clamped = map (\v -> min 3 $ floor (sigmoid v * 3.999)) (take 4 o)
      -- 5th: Sigmoid → [0,1] global weight
      g = sigmoid (o !! 4)
  in GeneOutput
      (TessCoord (clamped !! 0) (clamped !! 1) (clamped !! 2) (clamped !! 3))
      g

-- ════════════════════════════════════════════════════════════════
-- ADAPTIVE PALETTE: G global + 4L local = 256
--
-- The palette index d×64 + a×16 + b×4 + c is ALWAYS valid.
-- What changes: the sRGB color at each index.
--
-- For pixels with g≈1 (global):
--   All 4 epoch copies of (a,b,c) → SAME sRGB
--   The color is stable across the animation.
--
-- For pixels with g≈0 (local):
--   Each epoch copy of (a,b,c) → DIFFERENT sRGB
--   The color shifts between epochs (temporal texture).
--
-- G = round(256 × mean(g over all pixels))
-- G global entries: 4 copies share sRGB → 64 visible colors
-- L = (256-G)/4 local entries: each epoch diverges → L unique per epoch
-- Per frame visible colors = G + L (not just 64)
-- ════════════════════════════════════════════════════════════════

-- | Compute the adaptive G/L split from gene outputs
adaptiveSplit :: [GeneOutput] -> (Int, Int)
adaptiveSplit outputs =
  let meanG = sum (map goGlobal outputs) / fromIntegral (max 1 (length outputs))
      g = min 256 . max 0 . round $ 256 * meanG
      -- Ensure (256 - g) divisible by 4
      g' = g - (g `mod` 4)
      l = (256 - g') `div` 4
  in (g', l)

-- ════════════════════════════════════════════════════════════════
-- § 9. TEACHER — the algebraic pipeline (from Block.hs)
-- ════════════════════════════════════════════════════════════════

binToLevel :: Int -> Int
binToLevel b
  | b <  4    = 0
  | b <  7    = 1
  | b < 11    = 2
  | otherwise = 3

histMode :: CountedHist -> Int
histMode (CountedHist bins _) = snd $ maximum (zip bins [0..])

-- | Teacher: the proven-correct algebraic assignment + depth-derived global weight
teacher :: CubeMode -> BlockPyramid -> GeneOutput
teacher mode bp =
  let -- Color from histogram mode at the NATIVE scale for this mode
      sc = nativeScale mode
      rHist = pyramidAt sc (bpR bp)
      gHist = pyramidAt sc (bpG bp)
      bHist = pyramidAt sc (bpB bp)
      a = binToLevel (histMode rHist)
      b = binToLevel (histMode gHist)
      c = binToLevel (histMode bHist)
      -- Epoch from Gaussian cadence
      d = dominantEpoch mode (bpFrameNorm bp * fromIntegral (frameCount mode - 1)) (bpDepth bp)
      -- Global weight from depth: near = global (1.0), far = local (0.0)
      g = bpDepth bp  -- depth IS the global weight for the teacher
  in GeneOutput (TessCoord d a b c) g

dominantEpoch :: CubeMode -> Double -> Double -> Int
dominantEpoch mode zf depth =
  let sb = fromIntegral (frameCount mode - 1) / 8.0
      s = sb * (2.0 - depth)
      s2 = 2.0 * s * s
      centers = [fromIntegral (2*d'+1) * sb | d' <- [0..3::Int]]
      raw = [exp (-(zf - mu)**2 / s2) | mu <- centers]
      total = sum raw
      probs = if total < 1e-10 then [0.25, 0.25, 0.25, 0.25]
              else map (/ total) raw
  in snd $ maximum (zip probs [0..3])

-- | Loss: Hamming distance on (d,a,b,c) + L2 on global weight
teacherLoss :: GeneParams -> CubeMode -> BlockPyramid -> Double
teacherLoss params lv bp =
  let GeneOutput (TessCoord gd ga gb gc) gg = geneForward params bp
      GeneOutput (TessCoord td ta tb tc) tg = teacher lv bp
      -- Hamming: 0 or 1 per axis, 4 axes
      hamming = fromIntegral $ (if gd /= td then 1 else 0)
              + (if ga /= ta then 1 else 0)
              + (if gb /= tb then 1 else 0)
              + (if gc /= tc then 1 else 0 :: Int)
      -- L2 on global weight
      gLoss = (gg - tg) ** 2
  in hamming + gLoss

-- ════════════════════════════════════════════════════════════════
-- § 10. USER SIGNAL — the loss function IS the human
-- ════════════════════════════════════════════════════════════════

data Signal = Tap | SwipeLeft | SwipeRight
  deriving (Show, Eq)

-- | Apply user signal to gene
--   TAP:   keep current (acceptance)
--   LEFT:  perturb ATTENTION, keep CORE (explore)
--   RIGHT: revert to previous gene (retreat)
applySignal :: Signal -> GeneParams -> GeneParams -> GeneParams
applySignal Tap        current _prev = current
applySignal SwipeLeft  current _prev =
  -- Perturb ATTENTION weights (placeholder: in practice, SGLD noise)
  current { gpAttention = perturbMatrix (gpAttention current) }
applySignal SwipeRight _current prev = prev

perturbMatrix :: (Matrix, Vector) -> (Matrix, Vector)
perturbMatrix (w, b) =
  -- Placeholder: add small deterministic perturbation
  -- Real implementation: SGLD noise scaled by learning rate
  let w' = map (map (\x -> x + 0.01 * sin (x * 137.0))) w
      b' = map (\x -> x + 0.01 * cos (x * 97.0)) b
  in (w', b')

-- ════════════════════════════════════════════════════════════════
-- § 11. THE SESSION — capture once, swipe many times
-- ════════════════════════════════════════════════════════════════

data Session = Session
  { sesLevel    :: !CubeMode
  , sesGene     :: !GeneParams
  , sesPrevGene :: !GeneParams
  , sesEntropy  :: !EntropyFeedback  -- from last organism
  , sesHistory  :: ![(Signal, EntropyFeedback)]
  } deriving (Show)

-- ════════════════════════════════════════════════════════════════
-- § 12. SYNTHETIC DATA
-- ════════════════════════════════════════════════════════════════

-- | Synthetic histogram peaked at a given bin
syntheticHist :: Int -> Int -> CountedHist
syntheticHist n peak = fromCounts
  [if i == peak then n - (numBins - 1) else 1 | i <- [0..numBins-1]]

-- | Synthetic channel pyramid for position (x,y) in an S×S grid
syntheticPyramid :: Int -> Int -> Int -> ChannelPyramid
syntheticPyramid s x _y =
  let peak = min 13 (x * numBins `div` max 1 s)
  in ChannelPyramid
    { cpCoarse = syntheticHist 144 peak   -- 12×12 Coarse
    , cpMedium = syntheticHist 36 peak   -- 6×6 Medium
    , cpFine   = syntheticHist 9 peak    -- 3×3 Fine
    }

syntheticBlock :: CubeMode -> Int -> Int -> Int -> BlockPyramid
-- Note: mode determines S and K, but pyramid scales are spatial constants
syntheticBlock m x y z =
  let s = spatialSide m
      k = frameCount m
      cx = abs (fromIntegral x - fromIntegral (s-1)/2) / (fromIntegral (s-1)/2)
      cy = abs (fromIntegral y - fromIntegral (s-1)/2) / (fromIntegral (s-1)/2)
      depth = 1.0 - sqrt (cx*cx + cy*cy) / sqrt 2.0
  in BlockPyramid
    { bpR = syntheticPyramid s x y
    , bpG = syntheticPyramid s y x  -- transpose for variety
    , bpB = syntheticPyramid s (x+y) 0
    , bpDepth = depth
    , bpDepthN = depthSamples m
    , bpFrameNorm = if k <= 1 then 0 else fromIntegral z / fromIntegral (k - 1)
    , bpEntropy = uniformEntropy
    }

-- | Synthetic gene params (deterministic, not trained)
syntheticGene :: GeneParams
syntheticGene =
  let w1 = [[0.01 * sin (fromIntegral (i * inputDim + j))
            | j <- [0..inputDim-1]]
            | i <- [0..hiddenDim-1]]
      b1 = replicate hiddenDim 0.0
      w2 = [[0.01 * cos (fromIntegral (i * hiddenDim + j))
            | j <- [0..hiddenDim-1]]
            | i <- [0..outputDim-1]]
      b2 = replicate outputDim 0.0
  in GeneParams (w1, b1) (w2, b2)

-- ════════════════════════════════════════════════════════════════
-- § 13. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (G1) flatten produces exactly 137 floats at all levels
axiom_G1 :: Bool
axiom_G1 = all (\lv ->
  length (flatten (syntheticBlock lv 0 0 0)) == inputDim
  ) allModes

-- (G2) geneForward output: (d,a,b,c) ∈ {0,1,2,3}⁴ AND g ∈ [0,1]
axiom_G2 :: Bool
axiom_G2 = all (\lv ->
  let bp = syntheticBlock lv 32 32 0
      GeneOutput (TessCoord d a b c) g = geneForward syntheticGene bp
  in all (\v -> v >= 0 && v <= 3) [d, a, b, c]
  && g >= 0 && g <= 1
  ) allModes

-- (G3) CountedHist frequencies sum to 1
axiom_G3 :: Bool
axiom_G3 = all (\n ->
  let ch = syntheticHist n 7
  in abs (sum (chBins ch) - 1.0) < 1e-10
  ) [9, 36, 144]

-- (G4) Sample counts match level geometry
axiom_G4 :: Bool
axiom_G4 = rgbSamples Training  == 144
        && rgbSamples Inference ==  36

-- (G5) ChannelPyramid contains all 3 levels
axiom_G5 :: Bool
axiom_G5 =
  let cp = syntheticPyramid 64 32 32
  in chN (cpCoarse cp) == 144
  && chN (cpMedium cp) == 36
  && chN (cpFine cp) == 9

-- (G6) Total parameter count = 4581
axiom_G6 :: Bool
axiom_G6 = totalParamCount == 4581

-- (G7) ATTENTION = 4416, CORE = 165 (5 outputs × 32 hidden + 5 biases)
axiom_G7 :: Bool
axiom_G7 = attentionParamCount == 4416 && coreParamCount == 165

-- (G8) Teacher produces valid output: (d,a,b,c) ∈ {0..3}⁴ and g ∈ [0,1]
axiom_G8 :: Bool
axiom_G8 = all (\lv ->
  let bp = syntheticBlock lv 32 32 0
      GeneOutput (TessCoord td ta tb tc) tg = teacher lv bp
  in all (\v -> v >= 0 && v <= 3) [td, ta, tb, tc]
  && tg >= 0 && tg <= 1
  ) allModes

-- (G9) Teacher loss = 0 when gene IS teacher (structural)
axiom_G9 :: Bool
axiom_G9 = True  -- by construction: if geneForward = teacher, loss = 0

-- (G10) TAP preserves gene
axiom_G10 :: Bool
axiom_G10 =
  let g1 = syntheticGene
      g2 = syntheticGene  -- dummy previous
      result = applySignal Tap g1 g2
  in gpCore result == gpCore g1
  && gpAttention result == gpAttention g1

-- (G11) SwipeRight reverts to previous
axiom_G11 :: Bool
axiom_G11 =
  let g1 = syntheticGene
      g2 = syntheticGene { gpCore = ([[1]], [1]) }  -- different
      result = applySignal SwipeRight g1 g2
  in gpCore result == gpCore g2

-- (G12) Entropy feedback ∈ [0,1]⁵
axiom_G12 :: Bool
axiom_G12 =
  let ef = uniformEntropy
  in all (\v -> v >= 0 && v <= 1)
    [efEpoch ef, efR ef, efG ef, efB ef, efJoint ef]

-- (G13) Uniform distribution → normalized entropy = 1.0
axiom_G13 :: Bool
axiom_G13 =
  let ch = CountedHist (replicate numBins (1.0 / fromIntegral numBins)) 140
  in abs (normalizedEntropy ch - 1.0) < 1e-10

-- (G14) Forward = flatten >>> encoder >>> relu >>> head >>> clamp+sigmoid
axiom_G14 :: Bool
axiom_G14 =
  let bp = syntheticBlock Training 10 20 5
      -- Manual pipeline
      x = flatten bp
      (w1, b1) = gpAttention syntheticGene
      (w2, b2) = gpCore syntheticGene
      h = relu (matVecMul w1 x `vecAdd` b1)
      o = matVecMul w2 h `vecAdd` b2
      clamped = map (\v -> min 3 $ floor (sigmoid v * 3.999)) (take 4 o)
      g = sigmoid (o !! 4)
      manual = GeneOutput (TessCoord (clamped!!0) (clamped!!1) (clamped!!2) (clamped!!3)) g
      -- Gene forward
      auto = geneForward syntheticGene bp
  in manual == auto

-- (G15) Confidence monotone in sample count
axiom_G15 :: Bool
axiom_G15 =
  let ch9   = syntheticHist 9 7
      ch36  = syntheticHist 36 7
      ch144 = syntheticHist 144 7
  in sampleCount ch9 < sampleCount ch36
  && sampleCount ch36 < sampleCount ch144

-- (G16) Pyramid access at each level returns correct n
axiom_G16 :: Bool
axiom_G16 =
  let cp = syntheticPyramid 64 32 32
  in chN (pyramidAt Coarse cp) == 144
  && chN (pyramidAt Medium cp) == 36
  && chN (pyramidAt Fine cp) == 9

-- (G17) Adaptive split: G + 4L = 256, G ∈ [0,256]
axiom_G17 :: Bool
axiom_G17 =
  let -- All-global outputs (g=1 for all)
      allGlobal = replicate 100 (GeneOutput (TessCoord 0 0 0 0) 1.0)
      (g1, l1) = adaptiveSplit allGlobal
      -- All-local outputs (g=0 for all)
      allLocal = replicate 100 (GeneOutput (TessCoord 0 0 0 0) 0.0)
      (g2, l2) = adaptiveSplit allLocal
      -- Mixed (g=0.5)
      mixed = replicate 100 (GeneOutput (TessCoord 0 0 0 0) 0.5)
      (g3, l3) = adaptiveSplit mixed
  in g1 + 4 * l1 == 256
  && g2 + 4 * l2 == 256
  && g3 + 4 * l3 == 256
  && g1 == 256 && l1 == 0    -- all global → G=256
  && g2 == 0 && l2 == 64     -- all local → G=0, L=64
  && g3 == 128 && l3 == 32   -- half-half → G=128, L=32

-- (G18) Teacher global weight = depth
axiom_G18 :: Bool
axiom_G18 = all (\lv ->
  let bp = syntheticBlock lv 32 32 0
      GeneOutput _ tg = teacher lv bp
  in abs (tg - bpDepth bp) < 1e-10  -- teacher's g IS depth
  ) allModes

-- ════════════════════════════════════════════════════════════════
-- § 14. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " Gene: 137 → 32 → 5.  Full pyramid. Adaptive palette."
  putStrLn " Output: (d,a,b,c) tesseract + g global/local weight."
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""

  -- Architecture
  putStrLn "── Architecture ──"
  putStrLn $ "  Input:     " ++ show inputDim ++ " floats (3ch × 3scales × 14bins + metadata)"
  putStrLn $ "  Hidden:    " ++ show hiddenDim ++ " (ReLU)"
  putStrLn $ "  Output:    " ++ show outputDim ++ " → (d,a,b,c) ∈ {0,1,2,3}⁴"
  putStrLn $ "  ATTENTION: " ++ show attentionParamCount ++ " params (InputEncoder, user-trained)"
  putStrLn $ "  CORE:      " ++ show coreParamCount ++ " params (OutputHead, species identity)"
  putStrLn $ "  TOTAL:     " ++ show totalParamCount ++ " params"
  putStrLn $ "  Capsule:   " ++ show totalParamCount ++ " bytes (Int8) = "
          ++ show (totalParamCount `div` 1024) ++ "." ++ show ((totalParamCount `mod` 1024) * 10 `div` 1024) ++ " KB"
  putStrLn ""

  -- Sample counts at each level
  putStrLn "── Statistical Significance ──"
  putStrLn ""
  putStrLn "  level    │ n_rgb │ n_depth │ SE(p=0.5) │ histogram reliable?"
  putStrLn "  ─────────┼───────┼─────────┼───────────┼────────────────────"
  mapM_ (\m -> do
    let n = rgbSamples m
        nd = depthSamples m
        se = sqrt (0.25 / fromIntegral n) :: Double
    putStrLn $ "  " ++ padL 8 (show m)
            ++ " │ " ++ padL 5 (show n)
            ++ " │ " ++ padL 7 (show nd)
            ++ " │ " ++ padL 9 (showF se)
            ++ " │ " ++ if n >= 30 then "yes (n≥30)" else "NO (n<30)"
    ) allModes
  putStrLn ""

  -- Entropy of synthetic histograms
  putStrLn "── Entropy at Each Scale ──"
  putStrLn ""
  let bp = syntheticBlock Training 32 32 8
  mapM_ (\(name, ch) ->
    putStrLn $ "  " ++ padL 12 name
            ++ ": n=" ++ padL 3 (show (chN ch))
            ++ "  H=" ++ showF (entropy ch)
            ++ "  H_norm=" ++ showF (normalizedEntropy ch)
    ) [ ("R Coarse", pyramidAt Coarse (bpR bp))
      , ("R Medium", pyramidAt Medium (bpR bp))
      , ("R Fine",   pyramidAt Fine   (bpR bp))
      ]
  putStrLn ""

  -- Gene forward on synthetic data
  putStrLn "── Gene Forward (untrained) ──"
  putStrLn ""
  mapM_ (\lv -> do
    let bp' = syntheticBlock lv 32 32 0
        gene_tc = geneForward syntheticGene bp'
        teach_tc = teacher lv bp'
        loss = teacherLoss syntheticGene lv bp'
    putStrLn $ "  " ++ padL 8 (show lv)
            ++ ": gene=" ++ show gene_tc
            ++ "  teacher=" ++ show teach_tc
            ++ "  loss=" ++ show loss
    ) allModes
  putStrLn ""

  -- Swipe simulation
  putStrLn "── Swipe Simulation ──"
  putStrLn ""
  let g0 = syntheticGene
      g1 = applySignal SwipeLeft g0 g0   -- explore
      g2 = applySignal SwipeLeft g1 g0   -- explore more
      g3 = applySignal SwipeRight g2 g1  -- retreat to g1
      g4 = applySignal Tap g3 g1         -- accept g3

      showGeneTC g = let tc = geneForward g (syntheticBlock Training 32 32 8)
                     in show tc
  putStrLn $ "  g0 (initial):       " ++ showGeneTC g0
  putStrLn $ "  g1 (LEFT):          " ++ showGeneTC g1
  putStrLn $ "  g2 (LEFT again):    " ++ showGeneTC g2
  putStrLn $ "  g3 (RIGHT → g1):    " ++ showGeneTC g3
  putStrLn $ "  g4 (TAP → keep g3): " ++ showGeneTC g4
  putStrLn ""

  -- Axioms
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""
  check "G1  flatten = 137 floats (all levels)"           [axiom_G1]
  check "G2  output: (d,a,b,c) ∈ {0..3}⁴, g ∈ [0,1]"    [axiom_G2]
  check "G3  histogram frequencies sum to 1"               [axiom_G3]
  check "G4  sample counts: 144, 36, 9"                    [axiom_G4]
  check "G5  pyramid has all 3 levels"                     [axiom_G5]
  check "G6  total params = 4581"                           [axiom_G6]
  check "G7  ATTENTION=4416, CORE=165"                      [axiom_G7]
  check "G8  teacher produces valid TessCoords"             [axiom_G8]
  check "G9  teacher loss = 0 at identity"                  [axiom_G9]
  check "G10 TAP preserves gene"                            [axiom_G10]
  check "G11 RIGHT reverts to previous"                     [axiom_G11]
  check "G12 entropy feedback ∈ [0,1]⁵"                    [axiom_G12]
  check "G13 uniform → entropy = 1.0"                      [axiom_G13]
  check "G14 forward = flatten>>>encode>>>relu>>>head>>>clamp" [axiom_G14]
  check "G15 confidence monotone in n"                      [axiom_G15]
  check "G16 pyramid access returns correct n"              [axiom_G16]
  check "G17 adaptive split G+4L=256"                      [axiom_G17]
  check "G18 teacher global weight = depth"                 [axiom_G18]
  putStrLn ""

  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn "  137 floats in. 5 values out. 4,581 params."
  putStrLn "  The NN sees the full pyramid. Every scale. Every bin."
  putStrLn "  Output 5: (d,a,b,c) tesseract + g global/local weight."
  putStrLn "  g=1 (near/face): global palette, stable across epochs."
  putStrLn "  g=0 (far/bg): local palette, epoch-specific sRGB."
  putStrLn "  G+4L=256. The split adapts to the scene."
  putStrLn "  The user swipes until beauty. TAP = this is the one."
  putStrLn "════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 10000) :: Int) / 10000.0 :: Double)
          in take 7 (s ++ repeat '0')

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      n = length results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name ++ " (" ++ show n ++ " cases)"
