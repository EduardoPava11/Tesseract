{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- Pipeline: Preview → Capture → Gene → Organism → User → Learn
--
-- THE LOOP:
--   1. PREVIEW  20fps continuous. User sees R, G, B, Depth.
--              No quantization. No palette. Just the raw channels.
--              The preview IS the data collection.
--
--   2. LEVEL    User picks CubeLevel → determines K (frames to save).
--              Level64:  K=64  (3.2s at 20fps)
--              Level128: K=32  (1.6s at 20fps)
--              Level256: K=16  (0.8s at 20fps)
--
--   3. CAPTURE  Save K consecutive frames from preview.
--              Each frame = S² blocks, each block = (histogram, depth).
--              Total data = S² × K × (3 histograms + 1 depth).
--
--   4. GENE     The gene maps blocks → TessCoords.
--              Gene = CORE (how to render) + ATTENTION (where to look).
--              CORE: histogram → (a,b,c) ∈ {0,1,2,3}³
--              ATTENTION: depth → modulation of epoch assignment
--              Together: block → (d,a,b,c) ∈ {0,1,2,3}⁴ → palette index
--
--   5. ORGANISM The GIF file: Phenotype + Engram + Capsule.
--              Phenotype = what standard viewers show (S²×K palette indices)
--              Engram = probability tensor (μ, σ² per cell)
--              Capsule = gene weights (what gets shared)
--
--   6. USER     The user IS the loss function.
--              They look at the GIF. They swipe/tap.
--              TAP = "this is beautiful" → positive reward.
--              LEFT = "explore more" → noise on ATTENTION.
--              RIGHT = "go back" → revert ATTENTION.
--              The user shapes the gene through selection pressure.
--
--   7. LEARN    ATTENTION weights update from user signal.
--              The gene learns which depth→epoch mappings the user prefers.
--              The gene learns which histogram interpretations look good.
--              Over time: the organism evolves to match the user's eye.
--
-- STATISTICAL FRAMEWORK:
--   Each block has a histogram — that's the DATA.
--   The gene decides how to interpret that histogram — that's the MODEL.
--   The deviation from B(S², 1/256) IS the signal.
--   The user's acceptance/rejection shapes which deviations
--   the gene amplifies vs suppresses.
--
--   The gene IS a statistical interpretation of the data.
--   Different genes see different things in the same scene.
--   Sharing genes = sharing ways of seeing.
-- ════════════════════════════════════════════════════════════════

module Pipeline where

import qualified Data.Map.Strict as Map
import Data.List (foldl', sortBy)
import Data.Ord (comparing, Down(..))

-- ════════════════════════════════════════════════════════════════
-- § 1. TYPES (from Block.hs, self-contained for clarity)
-- ════════════════════════════════════════════════════════════════

data CubeLevel = Level64 | Level128 | Level256
  deriving (Show, Eq, Ord, Enum, Bounded)

conservationProduct :: Int
conservationProduct = 4096

spatialSide :: CubeLevel -> Int
spatialSide Level64  = 64
spatialSide Level128 = 128
spatialSide Level256 = 256

frameCount :: CubeLevel -> Int
frameCount lv = conservationProduct `div` spatialSide lv

framesPerEpoch :: CubeLevel -> Int
framesPerEpoch lv = frameCount lv `div` 4

data RGB = RGB !Double !Double !Double deriving (Show, Eq, Ord)
newtype Depth = Depth Double deriving (Show, Eq, Ord)

data Pos = Pos !Int !Int deriving (Show, Eq, Ord)
newtype Frame = Frame Int deriving (Show, Eq, Ord)

-- ════════════════════════════════════════════════════════════════
-- § 2. PREVIEW — 20fps, 4 channels, no quantization
--
-- The preview is NOT a GIF. It's a live camera feed.
-- The user sees: R channel, G channel, B channel, Depth channel.
-- Each at the selected spatial resolution S×S.
--
-- The preview runs continuously at 20fps.
-- The depth channel tells the user what the camera sees as "near."
-- This is the ONLY place depth is visible — in the GIF it's invisible.
-- Depth modulates epoch assignment, but epochs are invisible too.
-- The user sees color. Depth works behind the scenes.
-- ════════════════════════════════════════════════════════════════

data PreviewFrame = PreviewFrame
  { pfRGB   :: !(Map.Map Pos RGB)    -- S² pixels, continuous [0,1]³
  , pfDepth :: !(Map.Map Pos Depth)  -- S² depths, continuous [0,1]
  } deriving (Show)

previewFPS :: Int
previewFPS = 20

-- | Capture duration in seconds for each level
captureDuration :: CubeLevel -> Double
captureDuration lv = fromIntegral (frameCount lv) / fromIntegral previewFPS

-- ════════════════════════════════════════════════════════════════
-- § 3. CAPTURE — save K consecutive frames
--
-- When the user triggers capture, we save K frames from the
-- preview stream. Each frame is S² blocks of (histogram, depth).
--
-- The capture is a WINDOW into the continuous preview.
-- The gene will process ALL K frames globally (not per-frame).
-- That's why we save first, then process.
-- ════════════════════════════════════════════════════════════════

-- | One block's data: the histogram IS the statistical summary
data BlockData = BlockData
  { bdHistR :: ![Int]    -- 14-bin histogram of R channel
  , bdHistG :: ![Int]    -- 14-bin histogram of G channel
  , bdHistB :: ![Int]    -- 14-bin histogram of B channel
  , bdDepth :: !Double   -- representative depth [0,1]
  , bdPos   :: !Pos      -- spatial position in S×S grid
  } deriving (Show)

-- | One captured frame: S² blocks
data CapturedFrame = CapturedFrame
  { cfIndex  :: !Int              -- 0..K-1
  , cfBlocks :: ![BlockData]      -- S² blocks
  } deriving (Show)

-- | The complete capture: K frames
data Capture = Capture
  { capLevel  :: !CubeLevel
  , capFrames :: ![CapturedFrame]  -- K frames
  } deriving (Show)

-- | Total data in a capture
captureBlockCount :: Capture -> Int
captureBlockCount cap = length (capFrames cap) * spatialSide (capLevel cap) ^ 2

-- ════════════════════════════════════════════════════════════════
-- § 4. THE GENE — statistical interpretation of the data
--
-- The gene has two parts:
--   CORE:      histogram → color level (a,b,c)
--   ATTENTION: depth → epoch modulation
--
-- CORE is the species identity. It defines HOW to read histograms.
--   Default: mode of histogram → binToLevel → {0,1,2,3}
--   Learned: weighted combination of bins, shaped by training.
--
-- ATTENTION is the individual's eye. It defines WHERE depth matters.
--   Default: σ(depth) = σ_base × (2 - depth), linear
--   Learned: non-linear σ(depth) curve, per-region weights.
--
-- The gene IS a function: BlockData × Frame → TessCoord
-- Different genes produce different GIFs from the same capture.
-- ════════════════════════════════════════════════════════════════

-- | A tesseract coordinate: (epoch, R, G, B) ∈ {0,1,2,3}⁴
data TessCoord = TessCoord !Int !Int !Int !Int
  deriving (Show, Eq, Ord)

paletteIndex :: TessCoord -> Int
paletteIndex (TessCoord d a b c) = d * 64 + a * 16 + b * 4 + c

-- | The CORE function: histogram → level
--   This is the species' way of reading color.
--
--   Default (no training): pick the bin with the most samples,
--   map it to a level via binToLevel. Purely statistical.
--
--   Trained: a small NN that weighs bins differently.
--   The gene carries these weights.
data CoreFn = CoreFn
  { coreName   :: !String
  , coreApply  :: [Int] -> Int   -- 14-bin histogram → level {0,1,2,3}
  }

instance Show CoreFn where show cf = "CoreFn<" ++ coreName cf ++ ">"

-- | Default CORE: mode → binToLevel (no learning needed)
defaultCore :: CoreFn
defaultCore = CoreFn "mode→binToLevel" $ \bins ->
  let bestBin = snd $ maximum (zip bins [0..13])
  in binToLevel bestBin

binToLevel :: Int -> Int
binToLevel b
  | b <  4    = 0
  | b <  7    = 1
  | b < 11    = 2
  | otherwise = 3

-- | The ATTENTION function: (frame, depth) → epoch
--   This is the individual's way of weighting time.
--
--   Default: Gaussian cadence, σ(depth) = σ_base × (2 - depth)
--   Trained: learned σ curve, potentially non-linear.
data AttnFn = AttnFn
  { attnName  :: !String
  , attnApply :: CubeLevel -> Int -> Double -> Int  -- level → frame → depth → epoch {0,1,2,3}
  }

instance Show AttnFn where show af = "AttnFn<" ++ attnName af ++ ">"

-- | Default ATTENTION: Gaussian cadence (the spec's formula)
defaultAttn :: AttnFn
defaultAttn = AttnFn "gaussian" $ \lv z depth ->
  let sb = fromIntegral (frameCount lv - 1) / 8.0
      s = sb * (2.0 - depth)
      zf = fromIntegral z
      s2 = 2.0 * s * s
      centers = [fromIntegral (2*d+1) * sb | d <- [0..3::Int]]
      raw = [exp (-(zf - mu)**2 / s2) | mu <- centers]
      total = sum raw
      probs = if total < 1e-10 then [0.25, 0.25, 0.25, 0.25]
              else map (/ total) raw
  in snd $ maximum (zip probs [0..3])

-- | The complete gene: CORE + ATTENTION
data Gene = Gene
  { geneCore :: !CoreFn
  , geneAttn :: !AttnFn
  } deriving (Show)

defaultGene :: Gene
defaultGene = Gene defaultCore defaultAttn

-- | The gene's core operation: map one block to a tesseract coordinate
applyGene :: Gene -> CubeLevel -> Int -> BlockData -> TessCoord
applyGene gene lv z bd =
  let a = coreApply (geneCore gene) (bdHistR bd)
      b = coreApply (geneCore gene) (bdHistG bd)
      c = coreApply (geneCore gene) (bdHistB bd)
      d = attnApply (geneAttn gene) lv z (bdDepth bd)
  in TessCoord d a b c

-- ════════════════════════════════════════════════════════════════
-- § 5. GENE APPLICATION — capture → palette indices
--
-- The gene processes ALL K frames globally.
-- For each block in each frame: gene(block, frame) → TessCoord
-- The result is S²×K palette indices.
--
-- This is the PHENOTYPE — what the GIF shows.
-- ════════════════════════════════════════════════════════════════

-- | Apply gene to entire capture → palette indices
applyToCapture :: Gene -> Capture -> Map.Map (Pos, Int) TessCoord
applyToCapture gene cap =
  let lv = capLevel cap
  in Map.fromList
    [ ((bdPos bd, cfIndex cf), applyGene gene lv (cfIndex cf) bd)
    | cf <- capFrames cap
    , bd <- cfBlocks cf
    ]

-- | Distribution: how palette entries are used
distribution :: Map.Map (Pos, Int) TessCoord -> Map.Map Int Int
distribution = Map.fromListWith (+) . map (\tc -> (paletteIndex tc, 1)) . Map.elems

-- | Epoch distribution across all voxels
epochDist :: Map.Map (Pos, Int) TessCoord -> [Int]
epochDist assignments =
  let counts = Map.fromListWith (+)
        [(d, 1) | TessCoord d _ _ _ <- Map.elems assignments]
  in [Map.findWithDefault 0 e counts | e <- [0..3]]

-- ════════════════════════════════════════════════════════════════
-- § 6. THE ORGANISM — Phenotype + Engram + Capsule
-- ════════════════════════════════════════════════════════════════

data Organism = Organism
  { orgLevel     :: !CubeLevel
  , orgPhenotype :: !(Map.Map (Pos, Int) Int)  -- S²×K palette indices
  , orgEngram    :: !(Map.Map Pos (Double, Double, Double, Double))
                    -- per-pixel: (μ_R, μ_G, μ_B, σ²) from histograms
  , orgGene      :: !Gene
  } deriving (Show)

-- | Build organism from capture + gene
buildOrganism :: Gene -> Capture -> Organism
buildOrganism gene cap =
  let lv = capLevel cap
      assignments = applyToCapture gene cap
      phenotype = Map.map paletteIndex assignments
      -- Engram: per-position mean color from histograms (across all K frames)
      engram = Map.fromList
        [ (pos, engramFromBlocks blocks)
        | (pos, blocks) <- Map.toList $ groupByPos cap
        ]
  in Organism lv phenotype engram gene

groupByPos :: Capture -> Map.Map Pos [BlockData]
groupByPos cap = Map.fromListWith (++)
  [ (bdPos bd, [bd]) | cf <- capFrames cap, bd <- cfBlocks cf ]

engramFromBlocks :: [BlockData] -> (Double, Double, Double, Double)
engramFromBlocks blocks =
  let n = fromIntegral (length blocks) :: Double
      -- Mean color from histogram modes
      meanCh bins = fromIntegral (snd (maximum (zip bins [0..13]))) / 13.0
      rs = map (meanCh . bdHistR) blocks
      gs = map (meanCh . bdHistG) blocks
      bs = map (meanCh . bdHistB) blocks
      muR = sum rs / n; muG = sum gs / n; muB = sum bs / n
      -- Variance across frames (temporal stability)
      var = sum [(r - muR)**2 + (g - muG)**2 + (b - muB)**2
                | (r, g, b) <- zip3 rs gs bs] / n
  in (muR, muG, muB, var)

-- ════════════════════════════════════════════════════════════════
-- § 7. USER SIGNAL — the loss function IS the human
--
-- The user sees the phenotype (the GIF playing in a loop).
-- They make a judgment: is this beautiful?
--
-- Gestures map to gene updates:
--   TAP   = "yes, this is good" → reinforce current ATTENTION
--   LEFT  = "show me different" → perturb ATTENTION (explore)
--   RIGHT = "go back"           → revert ATTENTION (retreat)
--
-- The user NEVER sees the gene. They see the phenotype.
-- Their aesthetic judgment IS the selection pressure.
-- Over time, the gene evolves to produce what they find beautiful.
--
-- This is NOT gradient descent. This is SELECTION.
-- The gene doesn't minimize a loss — it survives or dies.
-- ════════════════════════════════════════════════════════════════

data UserSignal = Tap | SwipeLeft | SwipeRight
  deriving (Show, Eq)

-- | Apply user signal to gene → new gene
--   TAP: reinforce (freeze attention, mark as "good")
--   LEFT: explore (noise on attention)
--   RIGHT: revert (restore previous attention)
applySignal :: UserSignal -> Gene -> Gene -> Gene
applySignal Tap        current _previous = current  -- keep current (it's good)
applySignal SwipeLeft  current _previous = current  -- would add noise (placeholder)
applySignal SwipeRight _current previous = previous -- revert to previous

-- ════════════════════════════════════════════════════════════════
-- § 8. THE FULL LOOP
--
-- preview(20fps) → user picks level → capture K frames
--   → gene(capture) → organism(phenotype + engram + capsule)
--   → user judges → signal → gene updates → repeat
--
-- The organism's GENE is the statistical interpretation.
-- The organism's PHENOTYPE is the visible result.
-- The organism's ENGRAM is the probability state.
-- The USER is the loss function.
-- The LOOP is evolution.
-- ════════════════════════════════════════════════════════════════

data AppState = AppState
  { asLevel     :: !CubeLevel
  , asGene      :: !Gene
  , asPrevGene  :: !Gene         -- for RIGHT revert
  , asOrganism  :: !(Maybe Organism)
  , asCapture   :: !(Maybe Capture)
  } deriving (Show)

initialState :: AppState
initialState = AppState Level64 defaultGene defaultGene Nothing Nothing

-- | The pipeline as a pure function
pipeline :: AppState -> Capture -> (AppState, Organism)
pipeline st cap =
  let gene = asGene st
      org = buildOrganism gene cap
  in (st { asCapture = Just cap, asOrganism = Just org }, org)

-- | User feedback as a pure function
feedback :: AppState -> UserSignal -> AppState
feedback st sig =
  let newGene = applySignal sig (asGene st) (asPrevGene st)
  in st { asPrevGene = asGene st, asGene = newGene }

-- ════════════════════════════════════════════════════════════════
-- § 9. STATISTICAL INVARIANTS
--
-- The gene's interpretation must satisfy:
--   (I1) Every block maps to exactly one TessCoord
--   (I2) TessCoord → palette index ∈ {0..255}
--   (I3) CoreFn output ∈ {0,1,2,3}
--   (I4) AttnFn output ∈ {0,1,2,3}
--   (I5) Epoch distribution follows Gaussian cadence (for default gene)
--   (I6) S × K = 4096
--   (I7) Total voxels = S² × K
--   (I8) Palette = 4⁴ = 256 regardless of gene
-- ════════════════════════════════════════════════════════════════

axiom_I1 :: Gene -> CubeLevel -> Bool
axiom_I1 gene lv =
  let bd = BlockData [0,0,0,100,0,0,0,0,0,0,0,0,0,0]
                     [0,0,0,0,0,0,0,100,0,0,0,0,0,0]
                     [0,0,0,0,0,0,0,0,0,0,0,100,0,0]
                     0.5 (Pos 0 0)
  in all (\z ->
    let TessCoord d a b c = applyGene gene lv z bd
    in d >= 0 && d <= 3 && a >= 0 && a <= 3
    && b >= 0 && b <= 3 && c >= 0 && c <= 3
    ) [0..frameCount lv - 1]

axiom_I2 :: Gene -> CubeLevel -> Bool
axiom_I2 gene lv =
  let bd = BlockData (replicate 14 10) (replicate 14 10) (replicate 14 10) 0.5 (Pos 0 0)
  in all (\z ->
    let i = paletteIndex (applyGene gene lv z bd)
    in i >= 0 && i <= 255
    ) [0..frameCount lv - 1]

axiom_I6 :: Bool
axiom_I6 = all (\lv -> spatialSide lv * frameCount lv == 4096)
  [Level64, Level128, Level256]

axiom_I8 :: Bool
axiom_I8 = 4^(4::Int) == (256::Int)

-- ════════════════════════════════════════════════════════════════
-- § 10. MAIN — demonstrate the full loop
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " Pipeline: Preview → Capture → Gene → Organism → User"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── The Loop ──"
  putStrLn ""
  putStrLn "  PREVIEW   20fps continuous. R, G, B, Depth channels."
  putStrLn "  LEVEL     User picks cube level → K frames to capture."
  putStrLn "  CAPTURE   Save K frames of S² blocks each."
  putStrLn "  GENE      Map blocks → TessCoords via CORE + ATTENTION."
  putStrLn "  ORGANISM  GIF = Phenotype + Engram + Capsule."
  putStrLn "  USER      TAP/LEFT/RIGHT = the loss function."
  putStrLn "  LEARN     ATTENTION updates. Gene evolves."
  putStrLn ""

  -- Show capture timing
  putStrLn "── Capture Timing at 20fps ──"
  putStrLn ""
  putStrLn "  level    │  S  │  K │ duration │ px/frame │ px/color"
  putStrLn "  ─────────┼─────┼────┼──────────┼──────────┼─────────"
  mapM_ (\lv ->
    putStrLn $ "  " ++ padL 8 (show lv)
            ++ " │" ++ padL 4 (show (spatialSide lv))
            ++ " │" ++ padL 3 (show (frameCount lv))
            ++ " │ " ++ padL 5 (showF (captureDuration lv)) ++ "s"
            ++ " │" ++ padL 9 (show (spatialSide lv ^ 2))
            ++ " │" ++ padL 8 (show (spatialSide lv ^ 2 `div` 256))
    ) [Level64, Level128, Level256]
  putStrLn ""

  -- Build a synthetic capture at Level64
  let lv = Level64
      gene = defaultGene
      synCap = Capture lv
        [ CapturedFrame z
          [ BlockData
              -- Histogram: center peak varies with position
              (mkHist (min 13 (x `div` 5)))
              (mkHist (min 13 (y `div` 5)))
              (mkHist (min 13 ((x+y) `div` 10)))
              -- Depth: face-like
              (let cx = abs (fromIntegral x - 31.5) / 31.5
                   cy = abs (fromIntegral y - 31.5) / 31.5
               in 1.0 - sqrt (cx*cx + cy*cy) / sqrt 2.0)
              (Pos x y)
          | y <- [0..spatialSide lv - 1]
          , x <- [0..spatialSide lv - 1]
          ]
        | z <- [0..frameCount lv - 1]
        ]

  putStrLn $ "── Synthetic Capture: " ++ show lv ++ " ──"
  putStrLn $ "  Frames: " ++ show (length (capFrames synCap))
  putStrLn $ "  Blocks/frame: " ++ show (length (cfBlocks (head (capFrames synCap))))
  putStrLn $ "  Total blocks: " ++ show (captureBlockCount synCap)
  putStrLn ""

  -- Apply gene
  putStrLn "── Gene Application (default gene) ──"
  let assignments = applyToCapture gene synCap
      dist = distribution assignments
      eps = epochDist assignments
  putStrLn $ "  Total assignments: " ++ show (Map.size assignments)
  putStrLn $ "  Palette used:      " ++ show (Map.size dist) ++ " / 256"
  putStrLn $ "  Epoch dist:        " ++ show eps
  putStrLn ""

  -- Build organism
  let org = buildOrganism gene synCap
  putStrLn $ "── Organism ──"
  putStrLn $ "  Level:     " ++ show (orgLevel org)
  putStrLn $ "  Phenotype: " ++ show (Map.size (orgPhenotype org)) ++ " palette indices"
  putStrLn $ "  Engram:    " ++ show (Map.size (orgEngram org)) ++ " position entries"
  putStrLn $ "  Gene:      " ++ show (orgGene org)
  putStrLn ""

  -- Axioms
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " INVARIANTS"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""
  check "I1 gene → valid TessCoord (all levels)"
    [axiom_I1 defaultGene lv' | lv' <- [Level64, Level128, Level256]]
  check "I2 TessCoord → index ∈ [0,255] (all levels)"
    [axiom_I2 defaultGene lv' | lv' <- [Level64, Level128, Level256]]
  check "I6 S × K = 4096"                        [axiom_I6]
  check "I8 4⁴ = 256"                            [axiom_I8]
  putStrLn ""

  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn "  The gene IS a statistical interpretation."
  putStrLn "  Different genes see different things in the same scene."
  putStrLn "  The user IS the loss function."
  putStrLn "  The GIF IS the organism."
  putStrLn "  Sharing a GIF = sharing a gene = sharing a way of seeing."
  putStrLn "════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

mkHist :: Int -> [Int]
mkHist peak = [if i == peak then 100 else 5 | i <- [0..13]]

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 100) :: Int) / 100.0 :: Double)
          in take 5 (s ++ repeat '0')

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      n = length results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name ++ " (" ++ show n ++ " cases)"

-- zip3 from Prelude
