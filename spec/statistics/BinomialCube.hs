{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════
-- BinomialCube: sRGB Cube Palette with Binomial Distribution
--
-- The sRGB cube is a unit cube [0,1]³.
--   Black = (0,0,0)  — one corner
--   White = (1,1,1)  — opposite corner
--   Distance from black to white = √3 ≈ 1.732 (the cube diagonal)
--
-- We tile this cube with 256 palette colors arranged as a
-- lattice: 8R × 8G × 4B = 256. Each color "owns" a Voronoi
-- cell of approximately equal volume (1/256 of the cube).
--
-- When source pixels are drawn uniformly from the cube,
-- each pixel falls into one of the 256 cells with probability
-- ≈ 1/256. The count per color follows:
--
--   count_c ~ Binomial(4096, 1/256)
--   E[count_c] = 16
--   Var[count_c] = 4096 × (1/256) × (255/256) ≈ 15.94
--   SD[count_c] ≈ 3.99
--
-- So most colors get 16 ± 4 pixels. This is the NATURAL
-- distribution. The 256×16 invariant is now a statistical
-- truth, not a forced lie.
-- ════════════════════════════════════════════════════════════

module BinomialCube where

import Data.List (sortBy, foldl', group, sort, minimumBy)
import Data.Ord (comparing, Down(..))
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)

-- ════════════════════════════════════════════════════════════
-- § 1. sRGB CUBE — Black and White as opposite corners
-- ════════════════════════════════════════════════════════════

-- | sRGB color in the unit cube [0,1]³
--   Black = origin = (0,0,0)
--   White = far corner = (1,1,1)
data SRGBColor = SRGBColor
  { sR :: {-# UNPACK #-} !Double
  , sG :: {-# UNPACK #-} !Double
  , sB :: {-# UNPACK #-} !Double
  } deriving (Eq, Ord, Show)

black :: SRGBColor
black = SRGBColor 0 0 0

white :: SRGBColor
white = SRGBColor 1 1 1

class Metric a where
  distance :: a -> a -> Double

instance Metric SRGBColor where
  distance (SRGBColor r1 g1 b1) (SRGBColor r2 g2 b2) =
    sqrt ((r1-r2)**2 + (g1-g2)**2 + (b1-b2)**2)

-- | The cube diagonal: max possible distance in sRGB
cubeDiagonal :: Double
cubeDiagonal = distance black white  -- √3 ≈ 1.732

-- ════════════════════════════════════════════════════════════
-- § 2. PALETTE as LATTICE in the sRGB cube
-- ════════════════════════════════════════════════════════════

-- | 8R × 8G × 4B = 256 colors, uniformly tiling the cube.
--
--   Why 8×8×4 and not 6×7×6?
--     - 8×8×4 = 256 exactly
--     - Human vision has less blue acuity (fewer S-cones)
--     - 4 blue levels matches perceptual resolution
--     - 8 red/green levels match higher R/G acuity
--
--   Black (0,0,0) is palette index 0.
--   White (1,1,1) is palette index 255.
--   They sit at opposite corners of the lattice.

type PaletteIdx = Int

data Palette = Palette
  { palColors :: !(Map PaletteIdx SRGBColor)
  , palNR     :: !Int  -- red levels
  , palNG     :: !Int  -- green levels
  , palNB     :: !Int  -- blue levels
  } deriving (Show)

makeCubePalette :: Palette
makeCubePalette =
  let nr = 8; ng = 8; nb = 4
      colors = Map.fromList
        [ (idx, SRGBColor r g b)
        | ir <- [0..nr-1]
        , ig <- [0..ng-1]
        , ib <- [0..nb-1]
        , let r = fromIntegral ir / fromIntegral (nr - 1)
              g = fromIntegral ig / fromIntegral (ng - 1)
              b = fromIntegral ib / fromIntegral (nb - 1)
              idx = ir * ng * nb + ig * nb + ib
        ]
  in Palette colors nr ng nb

-- | Verify black and white are in the palette
verifyCorners :: Palette -> IO ()
verifyCorners pal = do
  let colors = Map.elems (palColors pal)
      nearBlack = minimumBy (comparing (distance black)) colors
      nearWhite = minimumBy (comparing (distance white)) colors
  putStrLn $ "  Black (0,0,0): nearest palette = " ++ showRGB nearBlack
          ++ " dist=" ++ showF (distance black nearBlack)
  putStrLn $ "  White (1,1,1): nearest palette = " ++ showRGB nearWhite
          ++ " dist=" ++ showF (distance white nearWhite)
  putStrLn $ "  Cube diagonal: " ++ showF cubeDiagonal

-- | Find nearest palette index for a given sRGB color
--   For the lattice, we can compute this DIRECTLY (O(1))
--   instead of searching all 256 entries (O(256)).
nearestIndex :: Palette -> SRGBColor -> PaletteIdx
nearestIndex pal (SRGBColor r g b) =
  let nr = palNR pal; ng = palNG pal; nb = palNB pal
      ir = clampInt 0 (nr-1) (round (r * fromIntegral (nr - 1)))
      ig = clampInt 0 (ng-1) (round (g * fromIntegral (ng - 1)))
      ib = clampInt 0 (nb-1) (round (b * fromIntegral (nb - 1)))
  in ir * ng * nb + ig * nb + ib
  where
    clampInt lo hi x = max lo (min hi x)

-- | Look up palette color by index
lookupColor :: Palette -> PaletteIdx -> SRGBColor
lookupColor pal i = maybe black id (Map.lookup i (palColors pal))

-- ════════════════════════════════════════════════════════════
-- § 3. VORONOI CELL ANALYSIS
-- ════════════════════════════════════════════════════════════

-- | Each palette color owns a Voronoi cell in the cube.
--   For a uniform lattice, each cell has volume ≈ 1/256.
--   The probability that a uniform random point falls in cell c is:
--     p_c ≈ 1/256
--
--   Cell dimensions for 8×8×4 lattice:
--     ΔR = 1/7 ≈ 0.143
--     ΔG = 1/7 ≈ 0.143
--     ΔB = 1/3 ≈ 0.333
--   Cell volume = ΔR × ΔG × ΔB ≈ 0.00680
--   1/256 ≈ 0.00391
--
--   NOTE: Interior cells have full volume, edge/corner cells
--   have half/quarter volume. So the distribution is not
--   perfectly uniform — edge colors get fewer pixels.
--   This is the residual non-uniformity we'll measure.

-- ════════════════════════════════════════════════════════════
-- § 4. BINOMIAL DISTRIBUTION
-- ════════════════════════════════════════════════════════════

-- | The binomial distribution B(n, p):
--   P(X = k) = C(n,k) × p^k × (1-p)^(n-k)
--
--   For our case: n=4096, p=1/256
--   E[X] = np = 16
--   Var[X] = np(1-p) ≈ 15.94
--   SD[X] ≈ 3.99
--
--   The "16 pixels per color" is the EXPECTED VALUE.
--   The actual count fluctuates with SD ≈ 4.

binomialExpectedValue :: Int -> Double -> Double
binomialExpectedValue n p = fromIntegral n * p

binomialVariance :: Int -> Double -> Double
binomialVariance n p = fromIntegral n * p * (1 - p)

binomialSD :: Int -> Double -> Double
binomialSD n p = sqrt (binomialVariance n p)

-- | Compute binomial PMF for small k values
--   P(X=k) = C(n,k) * p^k * (1-p)^(n-k)
--   Using log-space to avoid overflow
binomialPMF :: Int -> Double -> Int -> Double
binomialPMF n p k =
  exp (logChoose n k + fromIntegral k * log p
       + fromIntegral (n - k) * log (1 - p))
  where
    logChoose nn kk =
      sum [log (fromIntegral i) | i <- [kk+1..nn]]
      - sum [log (fromIntegral i) | i <- [1..nn-kk]]

-- ════════════════════════════════════════════════════════════
-- § 5. SPATIAL TYPES
-- ════════════════════════════════════════════════════════════

data Spatial = Spatial {-# UNPACK #-} !Int {-# UNPACK #-} !Int
  deriving (Eq, Ord, Show)

instance Metric Spatial where
  distance (Spatial x1 y1) (Spatial x2 y2) =
    sqrt (fromIntegral ((x1-x2)^(2::Int) + (y1-y2)^(2::Int)))

data ColorGraph = ColorGraph
  { cgColor  :: !PaletteIdx
  , cgFrame  :: !Int
  , cgPixels :: ![Spatial]
  , cgSRGB   :: !SRGBColor
  } deriving (Show)

-- ════════════════════════════════════════════════════════════
-- § 6. FRAME GENERATION — Uniform source → Binomial counts
-- ════════════════════════════════════════════════════════════

type Seed = Int
nextSeed :: Seed -> Seed
nextSeed s = (s * 1103515245 + 12345) `mod` (2^(31::Int))
randDouble :: Seed -> (Double, Seed)
randDouble s = let s' = nextSeed s in (fromIntegral (abs s' `mod` 100000) / 100000.0, s')

-- | Generate a frame where source pixels are UNIFORM in the sRGB cube.
--   Quantization to nearest palette entry → Binomial counts.
generateBinomialFrame :: Palette -> Seed -> Int -> (Map PaletteIdx [Spatial], Seed)
generateBinomialFrame pal seed0 frameIdx =
  let positions = [(x, y) | y <- [0..63], x <- [0..63]]
      (buckets, seedFinal) = foldl' quantizePixel (Map.empty, seed0) positions
  in (buckets, seedFinal)
  where
    quantizePixel (buckets, s) (x, y) =
      let -- Draw uniform random sRGB color
          (r, s1) = randDouble s
          (g, s2) = randDouble s1
          (b, s3) = randDouble s2
          -- Quantize to nearest palette entry
          srcColor = SRGBColor r g b
          idx = nearestIndex pal srcColor
      in (Map.insertWith (++) idx [Spatial x y] buckets, s3)

-- | Generate a frame with SMOOTH spatial color field (like a real image)
--   but whose palette distribution is still approximately binomial
--   because the field covers the full sRGB cube uniformly.
generateSmoothFrame :: Palette -> Seed -> Int -> (Map PaletteIdx [Spatial], Seed)
generateSmoothFrame pal seed0 frameIdx =
  let positions = [(x, y) | y <- [0..63], x <- [0..63]]
      (buckets, seedFinal) = foldl' quantizePixel (Map.empty, seed0) positions
  in (buckets, seedFinal)
  where
    quantizePixel (buckets, s) (x, y) =
      let tx = fromIntegral x / 63.0
          ty = fromIntegral y / 63.0
          -- Smooth mapping that covers the ENTIRE cube
          -- (not just a small region — that was the old bug)
          --
          -- We use phase-shifted sinusoids that together
          -- span [0,1] on each channel across the 64×64 grid.
          baseR = 0.5 + 0.5 * sin (tx * pi * 2.0 + ty * pi * 0.7)
          baseG = 0.5 + 0.5 * cos (ty * pi * 2.0 + tx * pi * 1.3)
          baseB = 0.5 + 0.5 * sin ((tx + ty) * pi * 1.5 + 0.5)
          -- Small noise to break quantization ties
          (nr, s1) = randDouble s
          (ng, s2) = randDouble s1
          (nb, s3) = randDouble s2
          noise = 0.04
          r = clamp01 (baseR + noise * (nr - 0.5))
          g = clamp01 (baseG + noise * (ng - 0.5))
          b = clamp01 (baseB + noise * (nb - 0.5))
          idx = nearestIndex pal (SRGBColor r g b)
      in (Map.insertWith (++) idx [Spatial x y] buckets, s3)
    clamp01 v = max 0 (min 1 v)

-- ════════════════════════════════════════════════════════════
-- § 7. DISTRIBUTION ANALYSIS
-- ════════════════════════════════════════════════════════════

analyzeDistribution :: String -> Map PaletteIdx [Spatial] -> IO ()
analyzeDistribution label buckets = do
  let counts = [ length ps | ps <- Map.elems buckets ]
      allCounts = counts ++ replicate (256 - Map.size buckets) 0
      sortedCounts = sort allCounts
      n = 4096
      p = 1.0 / 256.0
      expectedMean = binomialExpectedValue n p
      expectedSD = binomialSD n p
      actualMean = fromIntegral (sum allCounts) / 256.0
      actualVar = sum [ (fromIntegral c - actualMean)^(2::Int)
                      | c <- allCounts ] / 256.0
      actualSD = sqrt actualVar
      -- Count how many are within 1 SD, 2 SD of mean
      within1 = length [c | c <- allCounts,
                  abs (fromIntegral c - actualMean) <= actualSD]
      within2 = length [c | c <- allCounts,
                  abs (fromIntegral c - actualMean) <= 2 * actualSD]
      colorsUsed = length [c | c <- allCounts, c > 0]
      maxCount = maximum allCounts
      minCount = minimum allCounts

  putStrLn $ "  ── " ++ label ++ " ──"
  putStrLn ""
  putStrLn $ "  Binomial prediction B(4096, 1/256):"
  putStrLn $ "    E[count]  = " ++ showF expectedMean
  putStrLn $ "    SD[count] = " ++ showF expectedSD
  putStrLn ""
  putStrLn $ "  Actual:"
  putStrLn $ "    Mean      = " ++ showF actualMean
  putStrLn $ "    SD        = " ++ showF actualSD
  putStrLn $ "    Min       = " ++ show minCount
  putStrLn $ "    Max       = " ++ show maxCount
  putStrLn $ "    Colors >0 = " ++ show colorsUsed ++ " / 256"
  putStrLn $ "    Within 1σ = " ++ show within1 ++ "/256 ("
          ++ showF (100 * fromIntegral within1 / 256.0) ++ "%)"
          ++ "  expected ≈ 68%"
  putStrLn $ "    Within 2σ = " ++ show within2 ++ "/256 ("
          ++ showF (100 * fromIntegral within2 / 256.0) ++ "%)"
          ++ "  expected ≈ 95%"
  putStrLn ""

  -- Histogram of counts
  let histogram = Map.fromListWith (+) [(c, 1::Int) | c <- allCounts]
      histList = Map.toAscList histogram
      maxHist = maximum (map snd histList)
  putStrLn "  Histogram (count → how many colors got that count):"
  putStrLn "  count │ freq"
  putStrLn "  ──────┼──────────────────────────────────────"
  mapM_ (\(cnt, freq) ->
    let barLen = max 0 (freq * 40 `div` max 1 maxHist)
    in putStrLn $ "  " ++ padL 5 (show cnt) ++ " │ "
               ++ replicate barLen '█' ++ " " ++ show freq
    ) histList
  putStrLn ""

-- ════════════════════════════════════════════════════════════
-- § 8. TRANSPORT (corrected: handles variable sizes)
-- ════════════════════════════════════════════════════════════

data Match = Match
  { matchFrom :: !Spatial
  , matchTo   :: !Spatial
  , matchCost :: !Double
  } deriving (Show)

data TransportPlan = TransportPlan
  { tpColorA   :: !PaletteIdx
  , tpColorB   :: !PaletteIdx
  , tpMatches  :: ![Match]
  , tpCost     :: !Double
  , tpColorDist :: !Double
  } deriving (Show)

-- | Compute transport between two graphs of the SAME palette color
--   across two frames. Uses cost-matrix assignment.
transportSameColor :: ColorGraph -> ColorGraph -> TransportPlan
transportSameColor ga gb =
  let ptsA = cgPixels ga
      ptsB = cgPixels gb
      nA = length ptsA
      nB = length ptsB
      n = max nA nB
  in if n == 0 then TransportPlan (cgColor ga) (cgColor gb) [] 0 0
     else
       let penalty = 91.0  -- ≈ 64√2, max possible distance in 64×64
           padA = ptsA ++ replicate (n - nA) (Spatial (-999) (-999))
           padB = ptsB ++ replicate (n - nB) (Spatial (-999) (-999))
           costMatrix = [ [ if isV a || isV b then penalty
                            else distance a b
                          | b <- padB ] | a <- padA ]
           matching = solveAssignment costMatrix n
           matches = [ Match (padA !! i) (padB !! j)
                             (costMatrix !! i !! j)
                     | (i, j) <- matching
                     , not (isV (padA !! i))
                     , not (isV (padB !! j)) ]
           totalCost = sum [matchCost m | m <- matches]
       in TransportPlan (cgColor ga) (cgColor gb) matches totalCost
                        (distance (cgSRGB ga) (cgSRGB gb))
  where isV (Spatial x _) = x == (-999)

-- | Assignment solver (row/col reduction + greedy)
solveAssignment :: [[Double]] -> Int -> [(Int, Int)]
solveAssignment costs n =
  let rowReduced = [ let m = minimum row in map (\x -> x - m) row | row <- costs ]
      colMins = [ minimum [rowReduced !! r !! c | r <- [0..n-1]] | c <- [0..n-1] ]
      reduced = [ [ rowReduced !! r !! c - colMins !! c
                   | c <- [0..n-1] ] | r <- [0..n-1] ]
      assign used result [] = result
      assign used result (r:rs) =
        let candidates = [ (c, reduced !! r !! c)
                         | c <- [0..n-1], not (c `elem` used) ]
        in case candidates of
             [] -> assign used result rs
             _  -> let (bestC, _) = minimumBy (comparing snd) candidates
                   in assign (bestC : used) ((r, bestC) : result) rs
  in assign [] [] [0..n-1]

-- | zip: given two frames' bucket maps, transport every shared color
transportZipFrames :: Palette -> Map PaletteIdx [Spatial]
                   -> Map PaletteIdx [Spatial]
                   -> [TransportPlan]
transportZipFrames pal bucketsA bucketsB =
  [ transportSameColor
      (ColorGraph c 0 psA (lookupColor pal c))
      (ColorGraph c 1 psB (lookupColor pal c))
  | c <- [0..255]
  , let psA = maybe [] id (Map.lookup c bucketsA)
        psB = maybe [] id (Map.lookup c bucketsB)
  , not (null psA) || not (null psB)
  ]

-- | unzip: extract the two marginal point-sets from all plans
transportUnzipAll :: [TransportPlan] -> (Int, Int, Int)
transportUnzipAll plans =
  let totalMatches = sum [length (tpMatches p) | p <- plans]
      totalA = sum [length (cgPixels ga)
                   | p <- plans
                   , let ga = undefined ] -- simplified
      colors = length plans
  in (colors, totalMatches, colors)

-- ════════════════════════════════════════════════════════════
-- § 9. MAIN
-- ════════════════════════════════════════════════════════════

main :: IO ()
main = do
  let pal = makeCubePalette

  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " sRGB CUBE: Black ↔ White with Binomial Color Distribution"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""

  -- § Show the cube geometry
  putStrLn "── sRGB Cube Geometry ──"
  putStrLn ""
  putStrLn "  Black = (0, 0, 0)  ← origin"
  putStrLn "  White = (1, 1, 1)  ← far corner"
  putStrLn $ "  Diagonal = √3 = " ++ showF cubeDiagonal
  putStrLn ""
  putStrLn "  Palette: 8R × 8G × 4B = 256 colors"
  putStrLn "  Lattice steps: ΔR=1/7≈0.143, ΔG=1/7≈0.143, ΔB=1/3≈0.333"
  putStrLn ""
  verifyCorners pal
  putStrLn ""

  -- § Show palette structure
  putStrLn "── Palette Corner Colors ──"
  putStrLn ""
  let showIdx i = "  [" ++ padL 3 (show i) ++ "] " ++ showRGB (lookupColor pal i)
  putStrLn $ showIdx 0   ++ "  ← BLACK  (R=0, G=0, B=0)"
  putStrLn $ showIdx 255 ++ "  ← WHITE  (R=7, G=7, B=3)"
  putStrLn $ showIdx 3   ++ "  ← pure BLUE  (R=0, G=0, B=3)"
  putStrLn $ showIdx 28  ++ "  ← pure GREEN (R=0, G=7, B=0)"
  putStrLn $ showIdx 224 ++ "  ← pure RED   (R=7, G=0, B=0)"
  putStrLn ""

  -- § Generate UNIFORM frame → should be binomial
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " TEST 1: Uniform Random Source → Binomial Distribution"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  let (uniformBuckets, seed1) = generateBinomialFrame pal 42 0
  analyzeDistribution "Uniform source pixels in sRGB cube" uniformBuckets

  -- § Generate SMOOTH frame → should also be approximately binomial
  --   if the field covers the full cube
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " TEST 2: Smooth Spatial Field → Approximately Binomial"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  let (smoothBuckets, seed2) = generateSmoothFrame pal seed1 0
  analyzeDistribution "Smooth field covering full sRGB cube" smoothBuckets

  -- § Generate a SECOND smooth frame for pairing
  let (smoothBuckets2, _) = generateSmoothFrame pal seed2 1

  -- § Transport between frames
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " TRANSPORT: Same-color spatial graphs across frames"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  let plans = transportZipFrames pal smoothBuckets smoothBuckets2
      nonEmpty = filter (\p -> not (null (tpMatches p))) plans
  putStrLn $ "  Colors with graphs in both frames: " ++ show (length nonEmpty)
  putStrLn ""
  putStrLn "  color │ sRGB value       │ #pxF1 │ #pxF2 │ EMD    │ #matched"
  putStrLn "  ──────┼──────────────────┼───────┼───────┼────────┼─────────"
  let showPlan p =
        let c = tpColorA p
            col = lookupColor pal c
            nA = maybe 0 length (Map.lookup c smoothBuckets)
            nB = maybe 0 length (Map.lookup c smoothBuckets2)
        in putStrLn $ "  " ++ padL 5 (show c)
                ++ " │ " ++ showRGB col
                ++ " │ " ++ padL 5 (show nA)
                ++ " │ " ++ padL 5 (show nB)
                ++ " │ " ++ padL 6 (showF (tpCost p))
                ++ " │ " ++ padL 7 (show (length (tpMatches p)))
  -- Show first 10 non-empty
  mapM_ showPlan (take 10 nonEmpty)
  putStrLn "  ..."
  -- Show total stats
  let totalEMD = sum [tpCost p | p <- nonEmpty]
      totalMatches = sum [length (tpMatches p) | p <- nonEmpty]
      meanEMD = totalEMD / fromIntegral (max 1 (length nonEmpty))
  putStrLn ""
  putStrLn $ "  Total matched pixels: " ++ show totalMatches
  putStrLn $ "  Mean EMD per color:   " ++ showF meanEMD
  putStrLn $ "  Total EMD:            " ++ showF totalEMD
  putStrLn ""

  -- § zip/unzip demonstration
  putStrLn "── zip / unzip ──"
  let firstPlan = head nonEmpty
      zippedMatches = tpMatches firstPlan
      unzippedA = map matchFrom zippedMatches
      unzippedB = map matchTo zippedMatches
  putStrLn $ "  Color " ++ show (tpColorA firstPlan)
          ++ ": " ++ show (length zippedMatches) ++ " matches (zipped)"
  putStrLn $ "  unzip → " ++ show (length unzippedA) ++ " points from frame 1"
  putStrLn $ "         + " ++ show (length unzippedB) ++ " points from frame 2"
  putStrLn ""

  -- § Binomial goodness-of-fit
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " BINOMIAL GOODNESS OF FIT"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  let counts = [ maybe 0 length (Map.lookup c uniformBuckets) | c <- [0..255] ]
      n = 4096; p = 1.0 / 256.0
  putStrLn "  Comparing observed counts to B(4096, 1/256):"
  putStrLn ""
  putStrLn "  count │ observed │ expected (binomial PMF × 256)"
  putStrLn "  ──────┼──────────┼─────────────────────────────"
  let observed = Map.fromListWith (+) [(c, 1::Int) | c <- counts]
  mapM_ (\k -> do
    let obs = maybe 0 id (Map.lookup k observed)
        expected = 256.0 * binomialPMF n p k
    putStrLn $ "  " ++ padL 5 (show k)
            ++ " │ " ++ padL 8 (show obs)
            ++ " │ " ++ padL 8 (showF expected)
            ++ "  " ++ replicate (max 0 obs) '▓'
            ++ replicate (max 0 (round expected - obs)) '░'
    ) [0..35]
  putStrLn ""

  -- § Chi-squared test
  let chiSq = sum [ (fromIntegral obs - expected)^(2::Int) / max 0.01 expected
                   | k <- [0..40]
                   , let obs = maybe 0 id (Map.lookup k observed)
                         expected = 256.0 * binomialPMF n p k ]
  putStrLn $ "  χ² statistic: " ++ showF chiSq
  putStrLn $ "  Degrees of freedom: ~35"
  putStrLn $ "  (χ² < 50 → good fit at p=0.05)"
  putStrLn ""

  -- § The incomparable lattice explained simply
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " WHAT 'INCOMPARABLE' MEANS — Simply"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  Imagine two color graphs:"
  putStrLn ""
  putStrLn "    Graph A: 16 pixels in a TALL THIN column"
  putStrLn "      ·█·      bounding box: 1×16 (tall)"
  putStrLn "      ·█·      mean pairwise dist: LARGE (spread vertically)"
  putStrLn "      ·█·"
  putStrLn "      ·█·"
  putStrLn ""
  putStrLn "    Graph B: 16 pixels in a SMALL SQUARE"
  putStrLn "      ████     bounding box: 4×4 (compact)"
  putStrLn "      ████     mean pairwise dist: SMALL (close together)"
  putStrLn "      ████"
  putStrLn "      ████"
  putStrLn ""
  putStrLn "  Which is 'more clustered'?"
  putStrLn ""
  putStrLn "    By mean pairwise distance: B wins (pixels closer)"
  putStrLn "    By bounding box diagonal:  B wins (smaller box)"
  putStrLn "    → B ≤ A.  COMPARABLE. B is tighter by all measures."
  putStrLn ""
  putStrLn "  Now consider:"
  putStrLn ""
  putStrLn "    Graph C: two tight clusters far apart"
  putStrLn "      ██····██   bbox: 8×2 (wide)"
  putStrLn "      ██····██   mean dist: MEDIUM (close within clusters,"
  putStrLn "                                     far between them)"
  putStrLn ""
  putStrLn "    Graph D: one loose cloud"
  putStrLn "      · ·· ·     bbox: 5×3 (smaller than C)"
  putStrLn "       · · ·     mean dist: MEDIUM (similar to C)"
  putStrLn "      · ·  ·"
  putStrLn ""
  putStrLn "  Which is 'more clustered'?"
  putStrLn ""
  putStrLn "    By mean pairwise distance: ≈ TIE"
  putStrLn "    By bounding box diagonal:  D wins (smaller box)"
  putStrLn "    By centroid variance:      C wins (tighter within clusters)"
  putStrLn ""
  putStrLn "  → C and D are INCOMPARABLE."
  putStrLn "    No single ordering captures the full picture."
  putStrLn "    A total order (sorting by one metric) THROWS AWAY"
  putStrLn "    this information. The product lattice KEEPS it."
  putStrLn ""
  putStrLn "  In practice: when pairing graphs, you may want to"
  putStrLn "  pair C with another two-cluster graph (shape-aware)"
  putStrLn "  rather than with a loose cloud that happens to have"
  putStrLn "  the same 'clustering score' on one metric."
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════
-- Helpers
-- ════════════════════════════════════════════════════════════

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 100) :: Int) / 100.0 :: Double)
          in take 7 (s ++ repeat '0')

showRGB :: SRGBColor -> String
showRGB (SRGBColor r g b) =
  "(" ++ showF r ++ "," ++ showF g ++ "," ++ showF b ++ ")"

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s
