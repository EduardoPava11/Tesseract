{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE FlexibleInstances #-}

-- ════════════════════════════════════════════════════════════════
-- TesseractSpec: Unified Specification
--
-- THESIS: 1D Time ⊕ 3D sRGB = 4D Tesseract (4^4 = 256)
--
-- PIPELINE:
--   19×19 block → { Histogram, GoBoard, KataGo } → ComposedColor → Epoch → Index
--
-- MEMORY BUDGET per block (19×19 = 361 pixels):
--   Source pixels:    361 × 3 doubles = 8,664 bytes (RGB)
--   Histogram:        3 × 14 ints    =   168 bytes
--   Go boards:        3 × 361 stones = 1,083 bytes
--   DitherGuide:      ~100 bytes (budget + candidate list)
--   TOTAL per block:  ~1.4 KB
--
-- For 4096 blocks:
--   All histograms:   688 KB (needed for global bin assignment)
--   Go evaluations:   ~5 MB (parallel, can stream)
--   Output indices:   4,096 bytes (one UInt8 per pixel)
--
-- TYPE SAFETY:
--   R, G, B, T are newtypes — compiler prevents mixing.
--   Histogram operates on channel VALUES (Quantizable).
--   Go operates on channel PAIRS (Comparable).
--   KataGo operates on POSITIONS (Evaluable).
--   Dithering operates on EITHER color OR time, never both.
-- ════════════════════════════════════════════════════════════════

module TesseractSpec where

import Data.List (foldl', sortBy)
import Data.Ord (comparing, Down(..))
import qualified Data.Map.Strict as Map
-- Data.Array removed: was only needed by deprecated KataGo types

-- ════════════════════════════════════════════════════════════════
-- § 1. AXES: Four orthogonal newtypes
-- ════════════════════════════════════════════════════════════════

-- | Color channel bins (0..13). 14 fine-grained levels per channel.
--   Newtypes prevent mixing: R cannot be used where G is expected.
newtype R = R { unR :: Int } deriving (Show, Eq, Ord)
newtype G = G { unG :: Int } deriving (Show, Eq, Ord)
newtype B = B { unB :: Int } deriving (Show, Eq, Ord)

-- | Temporal epoch (0..3). NOT a color bin. NOT ditherable on color.
newtype T = T { unT :: Int } deriving (Show, Eq, Ord)

-- | Coarse tesseract level (0..3). The quantization output.
newtype Lv = Lv { unLv :: Int } deriving (Show, Eq, Ord)

-- ════════════════════════════════════════════════════════════════
-- § 2. TYPE CLASSES: What each analysis can do
-- ════════════════════════════════════════════════════════════════

-- | Quantizable: continuous value → discrete level.
--   Memory: one Int per pixel per channel.
class Quantizable a where
  numBins  :: proxy a -> Int            -- 14 for color, 4 for time
  toBin    :: Double -> a               -- continuous → bin
  toLevel  :: a -> Lv                   -- bin → coarse level
  center   :: a -> Double               -- bin → continuous center

-- | Comparable: marker class for valid channel pairs.
--   The comparison function is stoneCompare (same for all pairs).
--   Memory: one Stone (1 byte) per pixel per pair.
class (Quantizable a, Quantizable b) => Comparable a b

-- | Ditherable: error diffusion can operate on this axis.
--   Memory: one Double error accumulator per pixel.
class Ditherable a where
  idealValue   :: a -> Double            -- the continuous ideal before quantization
  quantError   :: a -> a -> Double       -- ideal - quantized
  clampError   :: a -> Double -> Double  -- prevent runaway (±1.5 for epoch, ±0.2 for color)
  diffStrength :: a -> Double -> Double  -- depth → diffusion strength [0.3, 1.0]

-- ════════════════════════════════════════════════════════════════
-- § 3. INSTANCES: Which types satisfy which classes
-- ════════════════════════════════════════════════════════════════

-- Color channels are Quantizable (14 bins)
instance Quantizable R where
  numBins _ = 14
  toBin v = R (min 13 (max 0 (floor (v * 14))))
  toLevel (R b) = binToLv b
  center (R b) = (fromIntegral b + 0.5) / 14.0

instance Quantizable G where
  numBins _ = 14
  toBin v = G (min 13 (max 0 (floor (v * 14))))
  toLevel (G b) = binToLv b
  center (G b) = (fromIntegral b + 0.5) / 14.0

instance Quantizable B where
  numBins _ = 14
  toBin v = B (min 13 (max 0 (floor (v * 14))))
  toLevel (B b) = binToLv b
  center (B b) = (fromIntegral b + 0.5) / 14.0

-- Temporal epoch is Quantizable (4 bins, not 14)
instance Quantizable T where
  numBins _ = 4
  toBin v = T (min 3 (max 0 (round v)))
  toLevel (T d) = Lv d
  center (T d) = epochCenters !! d

-- Channel pairs are Comparable (→ Go stones)
instance Comparable R G
instance Comparable G B
instance Comparable B R

-- Color channels are Ditherable (Floyd-Steinberg on RGB)
instance Ditherable R where
  idealValue (R b) = center (R b)
  quantError (R ideal) (R actual) = center (R ideal) - center (R actual)
  clampError _ = max (-0.2) . min 0.2      -- ±0.2 for color channels
  diffStrength _ depth = 1.0 - depth * 0.7  -- near=0.3, far=1.0

instance Ditherable G where
  idealValue (G b) = center (G b)
  quantError (G ideal) (G actual) = center (G ideal) - center (G actual)
  clampError _ = max (-0.2) . min 0.2
  diffStrength _ depth = 1.0 - depth * 0.7

instance Ditherable B where
  idealValue (B b) = center (B b)
  quantError (B ideal) (B actual) = center (B ideal) - center (B actual)
  clampError _ = max (-0.2) . min 0.2
  diffStrength _ depth = 1.0 - depth * 0.7

-- Temporal is Ditherable (Floyd-Steinberg on T axis ONLY)
instance Ditherable T where
  idealValue (T d) = fromIntegral d
  quantError (T ideal) (T actual) = fromIntegral ideal - fromIntegral actual
  clampError _ = max (-1.5) . min 1.5       -- ±1.5 for temporal (wider than color)
  diffStrength _ depth = 1.0 - depth * 0.7   -- same depth-weighting as color

-- NOTE: T is Ditherable but NOT Comparable.
--       R,G,B are both Ditherable AND Comparable.
--       The type system ensures temporal dithering can't see color state.

-- ════════════════════════════════════════════════════════════════
-- § 4. COMPOSED TYPES: Products of orthogonal axes
-- ════════════════════════════════════════════════════════════════

-- | Color composition: one bin per independent channel.
--   Memory: 3 × Int = 24 bytes.
data CC = CC !R !G !B deriving (Show, Eq, Ord)

-- | Tesseract index: color × epoch.
--   Memory: 4 × Int = 32 bytes (or 1 × UInt8 = 1 byte as palette index).
data TI = TI !Lv !Lv !Lv !T deriving (Show, Eq, Ord)

palIdx :: TI -> Int
palIdx (TI (Lv a) (Lv b) (Lv c) (T d)) = d * 64 + a * 16 + b * 4 + c

-- | Addressed: color grounded in space and time.
--   Memory: CC (24) + 3 × Int (24) + Double (8) = 56 bytes.
data Addr = Addr
  { adCC    :: !CC
  , adX     :: !Int     -- 0..63 (grid column)
  , adY     :: !Int     -- 0..63 (grid row)
  , adFrame :: !Int     -- 0..63
  , adDepth :: !Double  -- [0,1], 1=near
  } deriving (Show)

-- ════════════════════════════════════════════════════════════════
-- § 5. GO BOARD: Pairwise channel comparison
-- ════════════════════════════════════════════════════════════════

data Stone = Blk | Wht | Emp deriving (Show, Eq, Ord)

type Board = Array (Int,Int) Stone

bsz :: Int
bsz = 19  -- Go board size = block side length

stoneCompare :: Double -> Double -> Stone
stoneCompare a b
  | a - b > 0.08 = Blk    -- channel A dominates
  | b - a > 0.08 = Wht    -- channel B dominates
  | otherwise     = Emp    -- boundary (dithering candidate)

-- | Three boards from one 19×19 block.
--   Memory: 3 × 361 × 1 byte = 1,083 bytes.
data GoBoards = GoBoards !Board !Board !Board deriving (Show)

-- | Territory analysis.
--   Memory: 4 × Int + 1 × Double = 40 bytes.
data Terr = Terr
  { tBlk :: !Int, tWht :: !Int, tEmp :: !Int
  , tScore :: !Double  -- (Blk - Wht) / total
  } deriving (Show)

-- | Board evaluation.
--   Memory: Terr (40) + 5 × Int/Double = 80 bytes.
data BdEv = BdEv
  { bdTerr  :: !Terr
  , bdLibB  :: !Int      -- Black liberties
  , bdLibW  :: !Int      -- White liberties
  , bdCmplx :: !Double   -- (liberties + empty) / 361
  } deriving (Show)

-- | Three board evaluations = Go analysis of one block.
--   Memory: 3 × 80 + 2 × 8 = 256 bytes.
data GoEv = GoEv
  { gRG :: !BdEv, gGB :: !BdEv, gBR :: !BdEv
  , gCmplx :: !Double    -- average complexity
  , gLibs  :: !Int       -- total liberties (= dither budget)
  } deriving (Show)

-- ════════════════════════════════════════════════════════════════
-- § 6. DITHER GUIDE: Go territory → dithering parameters
--
-- Liberties = boundary pixels = dithering candidates.
-- Complexity = (liberties + empty) / total = dithering budget fraction.
-- Territory score = channel balance = histogram skew.
--
-- This is everything we need. Territory analysis is transparent:
-- you can SEE the Go board, COUNT the liberties, VERIFY the logic.
-- No black-box NN needed.
-- ════════════════════════════════════════════════════════════════

-- | Dithering guidance for one block.
--   Memory: ~100 bytes (budget + small candidate list).
data DGuide = DGuide
  { dgBudget :: !Int             -- total ditherable pixels (= liberties)
  , dgCmplx  :: !Double          -- block complexity [0,1]
  } deriving (Show)

-- | Derive guide from Go evaluation.
--   Liberties ARE the dithering candidates.
--   Budget = total liberties. Complexity = game complexity.
deriveGuide :: GoEv -> DGuide
deriveGuide ev = DGuide (gLibs ev) (gCmplx ev)

-- ════════════════════════════════════════════════════════════════
-- § 8. HISTOGRAM: Per-channel bin counts
--
-- Memory: 14 × Int + 1 × Int = 60 bytes per channel.
--         3 channels = 180 bytes per block.
--         4096 blocks = 720 KB total (all needed for global matching).
-- ════════════════════════════════════════════════════════════════

data Hist = Hist { hCts :: ![Int], hN :: !Int } deriving (Show)
-- Memory: 14 × 8 + 8 = 120 bytes (Haskell Int = 8 bytes on 64-bit)

data BHist = BHist { bR :: !Hist, bG :: !Hist, bB :: !Hist } deriving (Show)
-- Memory: 3 × 120 = 360 bytes

-- | Target distribution scaled to n pixels.
--   Uses largest-remainder rounding for exact sum.
targetBins :: [Int]
targetBins = [1, 2, 4, 8, 16, 32, 64, 64, 32, 16, 8, 4, 2, 1]
-- Sum = 254

scaleTo :: Int -> [Int]
scaleTo n =
  let ideal = map (\t -> fromIntegral t * fromIntegral n / 254.0 :: Double) targetBins
      fl = map floor ideal
      rem_ = zipWith (-) ideal (map fromIntegral fl)
      deficit = n - sum fl
      winners = take deficit $ map fst $ sortBy (flip $ comparing snd) (zip [0..] rem_)
  in [fl !! i + (if i `elem` winners then 1 else 0) | i <- [0..13]]

-- ════════════════════════════════════════════════════════════════
-- § 8. THE PIPELINE: Two passes
--
-- PASS 1 (parallel, GPU):
--   For each of 4096 blocks:
--     a. Compute BHist (14-bin × 3 channels)      → 720 KB total
--     b. Compute GoBoards (3 × 19×19)              → streamed
--     c. Evaluate GoEv (territory, liberties)       → streamed
--     d. Derive DGuide (from GoEv)                  → ~400 KB total
--
-- PASS 2 (sequential, CPU):
--   a. Global bin assignment per channel (histogram matching)
--   b. Color dithering (F-S on R, G, B with DGuide)
--   c. Temporal dithering (F-S on T, depth-weighted)
--   d. Compose palette index = d×64 + a×16 + b×4 + c
--
-- Total memory: ~2 MB peak
-- ════════════════════════════════════════════════════════════════

-- | Full block analysis (output of Pass 1).
data BlkAn = BlkAn
  { baHist  :: !BHist
  , baGo    :: !GoEv
  , baGuide :: !DGuide
  , baPos   :: !(Int, Int)       -- position in 64×64 grid
  } deriving (Show)

-- | Full frame quantization (Pass 2).
quantizeFrame :: Int -> [BlkAn] -> [Double] -> [Int]
quantizeFrame z analyses depths =
  let n = length analyses
      -- Phase 2a: per-channel bin assignment (histogram matching)
      rBins = assignCh (map (bR . baHist) analyses)
      gBins = assignCh (map (bG . baHist) analyses)
      bBins = assignCh (map (bB . baHist) analyses)
      colors = zipWith3' (\r g b -> CC (R r) (G g) (B b)) rBins gBins bBins

      -- Phase 2b+c: color dithering + temporal dithering
      -- (using DGuide.strength to modulate F-S diffusion per pixel)
      indices = ditherAndCompose z colors depths analyses
  in indices

-- ════════════════════════════════════════════════════════════════
-- § 10. DITHERING: Color (R,G,B) then Temporal (T)
--
-- Phase 2b: Floyd-Steinberg on R, G, B independently.
--   Each channel diffuses its own error. Channels don't mix.
--   DGuide.strength modulates diffusion per pixel:
--     high strength (contested territory) → full diffusion
--     low strength (settled territory) → minimal diffusion
--
-- Phase 2c: Floyd-Steinberg on T.
--   idealEpoch = Σ d × P(d|z, σ(depth))
--   Error diffused spatially, depth-weighted.
--   Color is FROZEN. Only epoch changes.
-- ════════════════════════════════════════════════════════════════

ditherAndCompose :: Int -> [CC] -> [Double] -> [BlkAn] -> [Int]
ditherAndCompose z colors depths analyses =
  let n = length colors
      w = 64

      -- Phase 2b: color F-S per channel (with Go/KataGo guidance)
      -- For each pixel, the DGuide's strength map says how strongly to dither.
      -- Pixels on Go boundaries (high dgStr) → full diffusion.
      -- Pixels in settled territory (low dgStr) → minimal diffusion.
      -- [Simplified here — full implementation in Swift PerfectQuantizer]

      -- Phase 2c: temporal F-S
      epochErr = replicate n 0.0 :: [Double]

      go :: [Double] -> Int -> [Int]
      go _ i | i >= n = []
      go errs i =
        let depth = if i < length depths then depths !! i else 0.5
            sigma = sigmaBase * (2.0 - depth)
            probs = gaussProbs z sigma
            ideal = sum (zipWith (*) probs [0,1,2,3])
            adj = ideal + clampError (T 0) (errs !! i)
            q = min 3 (max 0 (round adj))
            err = adj - fromIntegral q
            s = diffStrength (T 0) depth
            d = err * s
            x = i `mod` w; y = i `div` w
            errs' = foldl' (\es (j, wt) ->
              if j >= 0 && j < n
              then setAt es j (es !! j + d * wt)
              else es) errs
              [ (i+1, 7/16), ((y+1)*w+(x-1), 3/16)
              , ((y+1)*w+x, 5/16), ((y+1)*w+(x+1), 1/16) ]
            CC (R r) (G g) (B b) = colors !! i
            ti = TI (toLevel (R r)) (toLevel (G g)) (toLevel (B b)) (T q)
        in palIdx ti : go errs' (i+1)

  in go epochErr 0

-- ════════════════════════════════════════════════════════════════
-- § 11. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- Structural
ax_S1 :: Bool
ax_S1 = 64 * 4096 == (262144 :: Int)   -- total samples

ax_S2 :: Bool
ax_S2 = 4^(4::Int) == (256 :: Int)     -- total buckets

ax_S3 :: Bool
ax_S3 = bsz * bsz == 361               -- block size = Go board

ax_S4 :: Bool
ax_S4 = sum targetBins == 254           -- target distribution sum

-- Memory
ax_M1 :: Bool
ax_M1 = 3 * 14 * 8 < 1024              -- BHist fits in 1 KB

ax_M2 :: Bool
ax_M2 = 3 * 361 < 2048                 -- GoBoards fits in 2 KB

-- Type separation (these are enforced by the compiler, not runtime)
-- ax_T1: R is not G (different newtypes)
-- ax_T2: T is not R (temporal ≠ color)
-- ax_T3: CC contains R, G, B but not T
-- ax_T4: TI contains T but T is only added in Phase 2c

-- ════════════════════════════════════════════════════════════════
-- § 12. CONSTANTS
-- ════════════════════════════════════════════════════════════════

sigmaBase :: Double
sigmaBase = 63.0 / 8.0

epochCenters :: [Double]
epochCenters = [7.875, 23.625, 39.375, 55.125]

gaussProbs :: Int -> Double -> [Double]
gaussProbs z sigma =
  let zf = fromIntegral z; s2 = 2.0 * sigma * sigma
      raw = [exp (-(zf - mu)^(2::Int) / s2) | mu <- epochCenters]
      total = sum raw
  in if total < 1e-10 then replicate 4 0.25 else map (/ total) raw

binToLv :: Int -> Lv
binToLv b
  | b < 4     = Lv 0
  | b < 7     = Lv 1
  | b < 11    = Lv 2
  | otherwise = Lv 3

-- ════════════════════════════════════════════════════════════════
-- § 13. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " TesseractSpec: Unified Specification"
  putStrLn " 1D Time ⊕ 3D sRGB = 4D Tesseract"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  ── Structural Axioms ──"
  putStrLn $ "  S1 (262,144 samples):    " ++ ck ax_S1
  putStrLn $ "  S2 (256 buckets):         " ++ ck ax_S2
  putStrLn $ "  S3 (361 = Go board):      " ++ ck ax_S3
  putStrLn $ "  S4 (target sum = 254):    " ++ ck ax_S4
  putStrLn ""
  putStrLn "  ── Memory Axioms ──"
  putStrLn $ "  M1 (BHist < 1 KB):        " ++ ck ax_M1
  putStrLn $ "  M2 (GoBoards < 2 KB):     " ++ ck ax_M2
  putStrLn ""
  putStrLn "  ── Type Classes ──"
  putStrLn "  Quantizable: R, G, B (14 bins), T (4 bins)"
  putStrLn "  Comparable:  (R,G), (G,B), (B,R) → Go Stone"
  putStrLn "  Ditherable:  R, G, B (±0.2 clamp), T (±1.5 clamp)"
  putStrLn "  NOT Comparable: T (time has no pairwise comparison)"
  putStrLn ""
  putStrLn "  ── Memory Budget (per frame) ──"
  let histMem = 4096 * 3 * 14 * 8          -- all histograms
      goMem = 4096 * 3 * 361               -- all Go boards (streamed)
      outMem = 4096                          -- output indices
  putStrLn $ "  Histograms:  " ++ showKB histMem ++ " (all 4096 blocks)"
  putStrLn $ "  Go boards:   " ++ showKB goMem ++ " (streamed, not all at once)"
  putStrLn $ "  Output:      " ++ showKB outMem ++ " (palette indices)"
  putStrLn $ "  Peak total:  " ++ showKB (histMem + outMem)
  putStrLn ""
  putStrLn "  ── Pipeline ──"
  putStrLn "  Pass 1 (GPU):  blocks → BHist + GoBoards + GoEv → DGuide"
  putStrLn "  Pass 2 (CPU):  bin assignment → color F-S → temporal F-S → index"
  putStrLn ""
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " Histogram: WHAT exists.  Go: WHERE boundaries are."
  putStrLn " Territory + liberties: transparent, verifiable, sufficient."
  putStrLn " Type classes enforce: R ≠ G ≠ B ≠ T. No mixing."
  putStrLn "════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

assignCh :: [Hist] -> [Int]
assignCh hists =
  let n = length hists
      demand = scaleTo n
  in snd $ foldl' (\(dem, acc) h ->
    let best = foldl' (\(bb, bs) b ->
          if dem !! b > 0 && hCts h !! b > 0
          then let s = fromIntegral (hCts h !! b) * fromIntegral (dem !! b) :: Double
               in if s > bs then (b, s) else (bb, bs)
          else (bb, bs)) (strongest h, 0) [0..13]
        chosen = fst best
        dem' = [if i == chosen then max 0 (dem !! i - 1) else dem !! i | i <- [0..13]]
    in (dem', acc ++ [chosen])
    ) (demand, []) hists

strongest :: Hist -> Int
strongest h = snd $ maximum (zip (hCts h) [0..])

setAt :: [a] -> Int -> a -> [a]
setAt xs i v | i >= 0 && i < length xs = take i xs ++ [v] ++ drop (i+1) xs
             | otherwise = xs

zipWith3' :: (a -> b -> c -> d) -> [a] -> [b] -> [c] -> [d]
zipWith3' f (a:as) (b:bs) (c:cs) = f a b c : zipWith3' f as bs cs
zipWith3' _ _ _ _ = []

ck :: Bool -> String
ck True  = "✓"
ck False = "✗"

showKB :: Int -> String
showKB n = show (n `div` 1024) ++ " KB"
