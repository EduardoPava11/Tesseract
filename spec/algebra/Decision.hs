{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- Decision: How a Histogram Becomes a Pixel
--
-- THE GAP: we had histograms (data) and palette indices (output)
-- but the MIDDLE STEP — how statistical information becomes a
-- concrete pixel decision — was unspecified.
--
-- THE ANSWER: each 14-bin histogram defines a PROBABILITY
-- DISTRIBUTION over the 4 tesseract levels. The decision is
-- the level with highest mass. The confidence is that mass.
-- The dithering budget is 1 - confidence.
--
-- THIS IS WHY R, G, B are independent:
--   Each channel has its OWN confidence.
--   A block can be confident in R (skin is red)
--   but uncertain in B (blue varies with lighting).
--   Dithering should be STRONG on B and WEAK on R
--   for the SAME pixel.
--
-- THIS IS WHY g (global/local) EMERGES from the histogram:
--   g = average confidence across R, G, B channels.
--   Sharp histograms → high confidence → high g → global.
--   Spread histograms → low confidence → low g → local.
--   Depth CORRELATES with this but doesn't CAUSE it.
--   The data tells you what's stable. Depth confirms it.
-- ════════════════════════════════════════════════════════════════

module Decision where

import Data.List (foldl', maximumBy)
import Data.Ord (comparing)

-- ════════════════════════════════════════════════════════════════
-- § 1. HISTOGRAM → LEVEL PROBABILITIES
--
-- 14 bins → 4 levels. Not by mode, but by MASS.
--   Level 0: bins 0-3   (4 bins, dark)
--   Level 1: bins 4-6   (3 bins)
--   Level 2: bins 7-10  (4 bins)
--   Level 3: bins 11-13 (3 bins, bright)
--
-- The probability of each level is the sum of frequency mass
-- in its bin range. This is a PROJECTION from 14D → 4D.
-- ════════════════════════════════════════════════════════════════

numBins :: Int
numBins = 14

-- | 14-bin histogram: frequencies summing to 1, with sample count
data Hist = Hist { hBins :: ![Double], hN :: !Int }
  deriving (Show, Eq)

-- | The 4 level boundaries (which bins belong to which level)
levelBins :: [[Int]]
levelBins = [ [0,1,2,3]      -- Level 0: 4 bins
            , [4,5,6]         -- Level 1: 3 bins
            , [7,8,9,10]      -- Level 2: 4 bins
            , [11,12,13]      -- Level 3: 3 bins
            ]

-- | P(Level k | histogram) = sum of mass in level k's bins
levelProbs :: Hist -> [Double]
levelProbs (Hist bins _) =
  [ sum [bins !! b | b <- lBins] | lBins <- levelBins ]

-- ════════════════════════════════════════════════════════════════
-- § 2. THE DECISION: argmax, confidence, dithering budget
-- ════════════════════════════════════════════════════════════════

-- | Which level has the most mass?
decidedLevel :: Hist -> Int
decidedLevel h =
  let probs = levelProbs h
  in snd $ maximum (zip probs [0..3])

-- | Confidence: probability of the decided level ∈ [0,1]
--   1.0 = all mass in one level (sharp peak)
--   0.25 = uniform (maximum uncertainty for 4 levels)
confidence :: Hist -> Double
confidence h = maximum (levelProbs h)

-- | Dithering budget: 1 - confidence ∈ [0, 0.75]
--   How much of this channel's quantization error should be diffused.
--   0.0 = perfect confidence, no dithering needed.
--   0.75 = maximum uncertainty, strong dithering.
ditherBudget :: Hist -> Double
ditherBudget h = 1.0 - confidence h

-- | Statistical significance: does the sample count
--   support the confidence? Uses binomial standard error.
--   SE = sqrt(p(1-p)/n). Significant if confidence > 1/4 + 2×SE.
isSignificant :: Hist -> Bool
isSignificant h@(Hist _ n) =
  let p = confidence h
      se = if n > 1 then sqrt (p * (1 - p) / fromIntegral n) else 1.0
  in p > 0.25 + 2 * se  -- 2σ above uniform chance

-- ════════════════════════════════════════════════════════════════
-- § 3. THREE CHANNELS → GLOBAL/LOCAL WEIGHT
--
-- Each channel has its own confidence. The global weight g
-- is the AVERAGE confidence across R, G, B.
--
-- This is the STATISTICAL definition of "global":
--   A pixel is global when all three channels are confident.
--   A pixel is local when any channel is uncertain.
--
-- The NN learns to approximate this from the full pyramid.
-- The teacher computes it exactly from the histogram mass.
-- ════════════════════════════════════════════════════════════════

-- | Per-channel decision: level + confidence + dither budget
data ChannelDecision = ChannelDecision
  { cdLevel      :: !Int      -- {0,1,2,3}
  , cdConfidence :: !Double   -- P(decided level) ∈ [0.25, 1.0]
  , cdDither     :: !Double   -- 1 - confidence ∈ [0, 0.75]
  , cdSignificant :: !Bool    -- is confidence statistically significant?
  } deriving (Show, Eq)

decideChannel :: Hist -> ChannelDecision
decideChannel h = ChannelDecision
  { cdLevel      = decidedLevel h
  , cdConfidence = confidence h
  , cdDither     = ditherBudget h
  , cdSignificant = isSignificant h
  }

-- | Three-channel decision: all independent, then combined
data BlockDecision = BlockDecision
  { bdR      :: !ChannelDecision
  , bdG      :: !ChannelDecision
  , bdB      :: !ChannelDecision
  , bdGlobal :: !Double          -- g = mean confidence across R,G,B
  , bdEpoch  :: !Int             -- d ∈ {0,1,2,3} from temporal cadence
  } deriving (Show, Eq)

decideBlock :: Hist -> Hist -> Hist -> Int -> BlockDecision
decideBlock hR hG hB epoch =
  let dR = decideChannel hR
      dG = decideChannel hG
      dB = decideChannel hB
      g = (cdConfidence dR + cdConfidence dG + cdConfidence dB) / 3.0
  in BlockDecision dR dG dB g epoch

-- | The palette index from a block decision
blockPaletteIndex :: BlockDecision -> Int
blockPaletteIndex bd =
  bdEpoch bd * 64 + cdLevel (bdR bd) * 16 + cdLevel (bdG bd) * 4 + cdLevel (bdB bd)

-- ════════════════════════════════════════════════════════════════
-- § 4. DITHERING × CONFIDENCE
--
-- Floyd-Steinberg diffuses quantization error to neighbors.
-- The AMOUNT of diffusion depends on the channel's confidence:
--
--   error_diffused = quantization_error × dither_budget(channel)
--
-- High confidence → small budget → little diffusion → preserve detail.
-- Low confidence → large budget → strong diffusion → fill palette.
--
-- Each channel diffuses INDEPENDENTLY. R's error doesn't affect G.
-- This is the ALGEBRAIC reason R, G, B are separate axes.
-- ════════════════════════════════════════════════════════════════

-- | Quantization error for one channel: ideal value minus cell center
quantError :: Double -> Int -> Double
quantError idealValue level =
  let center = (fromIntegral level + 0.5) / 4.0
  in idealValue - center

-- | Diffused error: scaled by the channel's dither budget
diffusedError :: Double -> Double -> Double
diffusedError qError dBudget = qError * dBudget

-- | Floyd-Steinberg weights
fsWeights :: [(Int, Int, Double)]
fsWeights = [(1,0, 7/16), (-1,1, 3/16), (0,1, 5/16), (1,1, 1/16)]

-- ════════════════════════════════════════════════════════════════
-- § 5. DEPTH CONFIRMS, DOESN'T CAUSE
--
-- Depth correlates with confidence because:
--   Near (face) → uniform skin tone → sharp histogram → high conf
--   Far (wall) → varied colors → spread histogram → low conf
--
-- But depth ADDS information the histogram can't see:
--   Two blocks might have equal histograms (same confidence)
--   but different depths. The near block is the SUBJECT —
--   it should be temporally stable (same epoch across frames).
--   The far block is BACKGROUND — it can vary.
--
-- So the teacher's g is NOT just histogram confidence.
-- It's: g = α × histogram_confidence + (1-α) × depth
-- where α weights the two signals. Default α = 0.5.
--
-- The NN learns the optimal α (and potentially a non-linear
-- combination) through training.
-- ════════════════════════════════════════════════════════════════

teacherAlpha :: Double
teacherAlpha = 0.5

teacherGlobal :: Double -> Double -> Double
teacherGlobal histConfidence depth =
  teacherAlpha * histConfidence + (1 - teacherAlpha) * depth

-- ════════════════════════════════════════════════════════════════
-- § 6. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (D1) Level probabilities sum to 1
axiom_D1 :: Bool
axiom_D1 = all (\h -> abs (sum (levelProbs h) - 1.0) < 1e-10)
  [ mkHist [100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  , mkHist [10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10]
  , mkHist [0, 0, 0, 0, 0, 50, 50, 0, 0, 0, 0, 0, 0, 0]
  ]

-- (D2) Sharp histogram → high confidence
axiom_D2 :: Bool
axiom_D2 =
  let sharp = mkHist [0,0,0,0,0,0,100,0,0,0,0,0,0,0]   -- all in bin 6 → Level 1
      spread = mkHist [10,10,10,10,10,10,10,10,10,10,10,10,5,5]  -- uniform-ish
  in confidence sharp > 0.9 && confidence spread < 0.4

-- (D3) Dithering budget = 1 - confidence
axiom_D3 :: Bool
axiom_D3 =
  let h = mkHist [0, 0, 0, 0, 50, 50, 0, 0, 0, 0, 0, 0, 0, 0]
      c = confidence h
      d = ditherBudget h
  in abs (c + d - 1.0) < 1e-10

-- (D4) R, G, B are independent: changing R doesn't affect G's decision
axiom_D4 :: Bool
axiom_D4 =
  let hG = mkHist [0,0,0,0,0,0,50,50,0,0,0,0,0,0]
      hB = mkHist [0,0,0,0,0,0,0,0,0,0,0,50,50,0]
      hR1 = mkHist [100,0,0,0,0,0,0,0,0,0,0,0,0,0]  -- R = Level 0
      hR2 = mkHist [0,0,0,0,0,0,0,0,0,0,0,0,0,100]  -- R = Level 3
      bd1 = decideBlock hR1 hG hB 0
      bd2 = decideBlock hR2 hG hB 0
  in cdLevel (bdG bd1) == cdLevel (bdG bd2)  -- G's level unchanged
  && cdLevel (bdB bd1) == cdLevel (bdB bd2)  -- B's level unchanged

-- (D5) Global weight ∈ [0.25, 1.0]
axiom_D5 :: Bool
axiom_D5 =
  let low = decideBlock
              (mkHist [10,10,10,10,10,10,10,10,10,10,10,10,5,5])
              (mkHist [10,10,10,10,10,10,10,10,10,10,10,10,5,5])
              (mkHist [10,10,10,10,10,10,10,10,10,10,10,10,5,5]) 0
      high = decideBlock
              (mkHist [0,0,0,0,0,0,0,100,0,0,0,0,0,0])
              (mkHist [0,0,0,0,0,0,0,100,0,0,0,0,0,0])
              (mkHist [0,0,0,0,0,0,0,100,0,0,0,0,0,0]) 0
  in bdGlobal low >= 0.25 && bdGlobal high <= 1.0
  && bdGlobal high > bdGlobal low

-- (D6) Statistical significance: n=144 sharp → significant, n=9 spread → not
axiom_D6 :: Bool
axiom_D6 =
  let sharpBig = Hist ([0,0,0,0,0,0,0] ++ [fromIntegral (144-13) / 144] ++ [1/144,1/144,1/144,1/144,1/144,1/144]) 144
      spreadSmall = Hist (replicate 14 (1/14)) 9
  in isSignificant sharpBig && not (isSignificant spreadSmall)

-- (D7) Bimodal histogram: decision picks the LARGER mode
axiom_D7 :: Bool
axiom_D7 =
  let bimodal = mkHist [40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 60, 0, 0, 0]
      -- Mode at bin 10 (Level 2) > mode at bin 0 (Level 0)
  in decidedLevel bimodal == 2

-- (D8) Palette index composition: d×64 + a×16 + b×4 + c
axiom_D8 :: Bool
axiom_D8 =
  let bd = decideBlock
            (mkHist [0,0,0,0,0,0,0,100,0,0,0,0,0,0])   -- bin 7 → Level 2
            (mkHist [100,0,0,0,0,0,0,0,0,0,0,0,0,0])   -- bin 0 → Level 0
            (mkHist [0,0,0,0,0,0,0,0,0,0,0,0,0,100])   -- bin 13 → Level 3
            1                                              -- epoch 1
  in blockPaletteIndex bd == 1 * 64 + 2 * 16 + 0 * 4 + 3  -- = 99

-- (D9) teacherGlobal blends histogram confidence and depth
axiom_D9 :: Bool
axiom_D9 =
  let g1 = teacherGlobal 1.0 1.0  -- both high
      g2 = teacherGlobal 0.25 0.0  -- both low
      g3 = teacherGlobal 1.0 0.0  -- confident color, far depth
      g4 = teacherGlobal 0.25 1.0  -- uncertain color, near depth
  in g1 == 1.0 && g2 == 0.125
  && g3 == 0.5 && g4 == 0.625  -- depth wins when histogram is uncertain

-- ════════════════════════════════════════════════════════════════
-- § 7. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " Decision: How a Histogram Becomes a Pixel"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""

  -- Show the level → bin mapping
  putStrLn "── Level ← Bin Mapping ──"
  putStrLn ""
  mapM_ (\(lv, bins) ->
    putStrLn $ "  Level " ++ show lv ++ ": bins " ++ show bins
            ++ " (" ++ show (length bins) ++ " bins)"
    ) (zip [0..3::Int] levelBins)
  putStrLn ""

  -- Example: sharp vs spread
  let sharp = mkHist [0,0,0,0,0,0,100,0,0,0,0,0,0,0]
      spread = mkHist [10,10,10,10,10,10,10,10,10,10,10,10,5,5]
      bimodal = mkHist [40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 60, 0, 0, 0]

  putStrLn "── Decision Examples ──"
  putStrLn ""
  mapM_ (\(name, h) -> do
    let probs = levelProbs h
        d = decideChannel h
    putStrLn $ "  " ++ name ++ ":"
    putStrLn $ "    P(L0)=" ++ showF (probs!!0)
            ++ " P(L1)=" ++ showF (probs!!1)
            ++ " P(L2)=" ++ showF (probs!!2)
            ++ " P(L3)=" ++ showF (probs!!3)
    putStrLn $ "    level=" ++ show (cdLevel d)
            ++ " conf=" ++ showF (cdConfidence d)
            ++ " dither=" ++ showF (cdDither d)
            ++ " sig=" ++ show (cdSignificant d)
    putStrLn ""
    ) [ ("sharp (bin 6)",  sharp)
      , ("spread (uniform)", spread)
      , ("bimodal (0+10)", bimodal)
      ]

  -- Three-channel block
  let bd = decideBlock sharp spread bimodal 2
  putStrLn "── Block Decision (R=sharp, G=spread, B=bimodal, epoch=2) ──"
  putStrLn $ "  R: level=" ++ show (cdLevel (bdR bd)) ++ " conf=" ++ showF (cdConfidence (bdR bd))
  putStrLn $ "  G: level=" ++ show (cdLevel (bdG bd)) ++ " conf=" ++ showF (cdConfidence (bdG bd))
  putStrLn $ "  B: level=" ++ show (cdLevel (bdB bd)) ++ " conf=" ++ showF (cdConfidence (bdB bd))
  putStrLn $ "  g (global weight) = " ++ showF (bdGlobal bd)
  putStrLn $ "  palette index = " ++ show (blockPaletteIndex bd)
  putStrLn ""
  putStrLn "  R is confident → dither R weakly."
  putStrLn "  G is uncertain → dither G strongly."
  putStrLn "  B is bimodal → dither B at the boundary."
  putStrLn "  The SAME pixel gets different dithering per channel."
  putStrLn ""

  -- Axioms
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""
  check "D1 level probs sum to 1"                    [axiom_D1]
  check "D2 sharp → high conf, spread → low conf"    [axiom_D2]
  check "D3 dither budget = 1 - confidence"           [axiom_D3]
  check "D4 R,G,B independent (changing R ≠ G)"      [axiom_D4]
  check "D5 global weight ∈ [0.25, 1.0]"             [axiom_D5]
  check "D6 significance: big+sharp=yes, small+spread=no" [axiom_D6]
  check "D7 bimodal → picks larger mode"              [axiom_D7]
  check "D8 palette index = d×64 + a×16 + b×4 + c"  [axiom_D8]
  check "D9 teacherGlobal blends confidence + depth"  [axiom_D9]
  putStrLn ""

  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn "  The histogram IS the data."
  putStrLn "  The level mass IS the probability."
  putStrLn "  The confidence IS the global/local weight."
  putStrLn "  The dithering budget IS 1 - confidence."
  putStrLn "  R, G, B are independent — dithered independently."
  putStrLn "  Depth CONFIRMS what the histogram SHOWS."
  putStrLn "════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

mkHist :: [Int] -> Hist
mkHist counts =
  let n = sum counts
      nf = fromIntegral (max 1 n)
  in Hist (map (\c -> fromIntegral c / nf) counts) n

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 1000) :: Int) / 1000.0 :: Double)
          in take 6 (s ++ repeat '0')

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      n = length results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name ++ " (" ++ show n ++ " cases)"
