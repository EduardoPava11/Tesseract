{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- TesseractDistances: Binomial Distribution of Distances
-- Between Repeating Color Palettes in the 4⁴ Tesseract
--
-- 64 sRGB colors × 4 epochs = 256 palette entries.
-- Each sRGB color repeats 4 times (once per epoch).
-- What is the distribution of distances between these copies?
-- Between different colors? Does it follow a binomial model?
-- ════════════════════════════════════════════════════════════════

module TesseractDistances where

import Data.List (sort, group, foldl', sortBy, intercalate)
import Data.Ord (comparing, Down(..))
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)

-- ════════════════════════════════════════════════════════════════
-- § 1. TESSERACT TYPES (from Tesseract.hs)
-- ════════════════════════════════════════════════════════════════

data TessCoord = TessCoord !Int !Int !Int !Int
  deriving (Show, Eq, Ord)

tessIndex :: TessCoord -> Int
tessIndex (TessCoord d a b c) = d * 64 + a * 16 + b * 4 + c

indexTess :: Int -> TessCoord
indexTess i = let (d,r1) = i `divMod` 64
                  (a,r2) = r1 `divMod` 16
                  (b,c) = r2 `divMod` 4
              in TessCoord d a b c

-- | The sRGB triplet (ignoring epoch) — identifies the "color family"
type SRGBTriple = (Int, Int, Int)

tessToSRGB :: TessCoord -> SRGBTriple
tessToSRGB (TessCoord _ a b c) = (a, b, c)

-- | All 256 lattice points
allCoords :: [TessCoord]
allCoords = [TessCoord d a b c | d <- [0..3], a <- [0..3], b <- [0..3], c <- [0..3]]

-- | Group by sRGB triplet: 64 groups of 4 epochs each
srgbGroups :: Map SRGBTriple [TessCoord]
srgbGroups = Map.fromListWith (++)
  [(tessToSRGB tc, [tc]) | tc <- allCoords]

-- | 4D Euclidean distance
dist4 :: TessCoord -> TessCoord -> Double
dist4 (TessCoord d1 a1 b1 c1) (TessCoord d2 a2 b2 c2) =
  sqrt (fromIntegral $ (d1-d2)^(2::Int) + (a1-a2)^(2::Int)
                      + (b1-b2)^(2::Int) + (c1-c2)^(2::Int))

-- | Squared distance (integer, avoids sqrt for exact arithmetic)
distSq :: TessCoord -> TessCoord -> Int
distSq (TessCoord d1 a1 b1 c1) (TessCoord d2 a2 b2 c2) =
  (d1-d2)^(2::Int) + (a1-a2)^(2::Int) + (b1-b2)^(2::Int) + (c1-c2)^(2::Int)

-- ════════════════════════════════════════════════════════════════
-- § 2. INTRA-COLOR DISTANCES
-- ════════════════════════════════════════════════════════════════

-- | For each sRGB color, compute all 6 pairwise distances
--   between its 4 epoch copies. Distance is PURELY temporal.
intraColorDistances :: Map SRGBTriple [Double]
intraColorDistances = Map.map pairwiseDists srgbGroups
  where
    pairwiseDists coords =
      [dist4 a b | a <- coords, b <- coords, tessIndex a < tessIndex b]

-- | Collect ALL intra-color distances (64 colors × 6 pairs = 384)
allIntraDistances :: [Double]
allIntraDistances = concat (Map.elems intraColorDistances)

-- | Theoretical: for fixed (a,b,c), the 4 copies differ only in d ∈ {0,1,2,3}
--   Pairwise |d1-d2| values: {1,1,1,2,2,3}
--   Distances = {1.0, 1.0, 1.0, 2.0, 2.0, 3.0}
theoreticalIntra :: [Double]
theoreticalIntra = [1, 1, 1, 2, 2, 3]

-- ════════════════════════════════════════════════════════════════
-- § 3. INTER-COLOR DISTANCES (between different sRGB families)
-- ════════════════════════════════════════════════════════════════

-- | For two different sRGB colors, compute all 16 pairwise distances
--   (4 epochs × 4 epochs).
interColorDistances :: SRGBTriple -> SRGBTriple -> [Double]
interColorDistances s1 s2 =
  let g1 = Map.findWithDefault [] s1 srgbGroups
      g2 = Map.findWithDefault [] s2 srgbGroups
  in [dist4 a b | a <- g1, b <- g2]

-- | Sample inter-color distances for adjacent sRGB colors
sampleInterDistances :: [(SRGBTriple, SRGBTriple, [Double])]
sampleInterDistances =
  [ ((0,0,0), (1,0,0), interColorDistances (0,0,0) (1,0,0))
  , ((0,0,0), (3,3,3), interColorDistances (0,0,0) (3,3,3))  -- black↔white
  , ((1,1,1), (2,2,2), interColorDistances (1,1,1) (2,2,2))
  , ((0,0,0), (0,0,1), interColorDistances (0,0,0) (0,0,1))
  ]

-- ════════════════════════════════════════════════════════════════
-- § 4. SQUARED DISTANCE DISTRIBUTION (exact combinatorics)
-- ════════════════════════════════════════════════════════════════

-- | Distribution of |x-y| for x, y ∈ {0,1,2,3} (uniform)
--   |x-y|=0: 4/16, |x-y|=1: 6/16, |x-y|=2: 4/16, |x-y|=3: 2/16
absDiffDist :: [(Int, Double)]
absDiffDist = [(0, 4/16), (1, 6/16), (2, 4/16), (3, 2/16)]

-- | Distribution of |x-y|² for one coordinate
sqDiffDist :: [(Int, Double)]
sqDiffDist = [(0, 4/16), (1, 6/16), (4, 4/16), (9, 2/16)]

-- | E[|x-y|²] for one coordinate
expectedSqDiff1D :: Double
expectedSqDiff1D = sum [fromIntegral k * p | (k, p) <- sqDiffDist]
-- = (0×4 + 1×6 + 4×4 + 9×2)/16 = 40/16 = 2.5

-- | For 4D: D² = sum of 4 independent |xi-yi|²
--   E[D²] = 4 × E[|x-y|²] = 4 × 2.5 = 10
--   E[D] ≈ √10 ≈ 3.162
expectedSqDist4D :: Double
expectedSqDist4D = 4 * expectedSqDiff1D  -- = 10

-- | Exact distribution of D² for all C(256,2) pairs
allPairSqDistances :: Map Int Int
allPairSqDistances =
  Map.fromListWith (+)
    [ (distSq a b, 1)
    | a <- allCoords, b <- allCoords
    , tessIndex a < tessIndex b ]

-- | Same but for INTRA-color pairs only (384 total)
intraSqDistances :: Map Int Int
intraSqDistances =
  Map.fromListWith (+)
    [ (distSq a b, 1)
    | group <- Map.elems srgbGroups
    , a <- group, b <- group
    , tessIndex a < tessIndex b ]

-- | Same but for INTER-color pairs (32640 - 384 = 32256 total)
interSqDistances :: Map Int Int
interSqDistances =
  Map.fromListWith (+)
    [ (distSq a b, 1)
    | a <- allCoords, b <- allCoords
    , tessIndex a < tessIndex b
    , tessToSRGB a /= tessToSRGB b ]

-- ════════════════════════════════════════════════════════════════
-- § 5. BINOMIAL MODEL FOR DISTANCE
-- ════════════════════════════════════════════════════════════════

-- | The squared distance D² = Σᵢ (xᵢ - yᵢ)² where each
--   (xᵢ - yᵢ)² takes values {0, 1, 4, 9}.
--
--   This is NOT a binomial distribution — it's a sum of 4
--   independent discrete random variables, each with support {0,1,4,9}.
--
--   However, the COUNT of how many coordinates differ IS binomial:
--     K = |{i : xᵢ ≠ yᵢ}| ~ Binomial(4, 12/16) = Binomial(4, 3/4)
--   because P(xᵢ = yᵢ) = 4/16 = 1/4.
--
--   E[K] = 4 × 3/4 = 3
--   Var[K] = 4 × 3/4 × 1/4 = 3/4
--   SD[K] ≈ 0.866

-- | Number of differing coordinates between two tesseract points
numDiffering :: TessCoord -> TessCoord -> Int
numDiffering (TessCoord d1 a1 b1 c1) (TessCoord d2 a2 b2 c2) =
  (if d1 /= d2 then 1 else 0) +
  (if a1 /= a2 then 1 else 0) +
  (if b1 /= b2 then 1 else 0) +
  (if c1 /= c2 then 1 else 0)

-- | Distribution of K (number of differing coordinates) over all pairs
kDistribution :: Map Int Int
kDistribution =
  Map.fromListWith (+)
    [ (numDiffering a b, 1)
    | a <- allCoords, b <- allCoords
    , tessIndex a < tessIndex b ]

-- | Binomial PMF: B(4, 3/4)
binomPMF_K :: Int -> Double
binomPMF_K k = fromIntegral (choose 4 k) * (3/4)^k * (1/4)^(4-k)
  where
    choose n r = product [n-r+1..n] `div` product [1..r]

-- | For INTRA-color pairs: K is always exactly 1
--   (only the epoch coordinate differs)
intraK :: Map Int Int
intraK = Map.fromListWith (+)
  [ (numDiffering a b, 1)
  | group <- Map.elems srgbGroups
  , a <- group, b <- group
  , tessIndex a < tessIndex b ]

-- ════════════════════════════════════════════════════════════════
-- § 6. THE KEY INSIGHT: Intra vs Inter distance separation
-- ════════════════════════════════════════════════════════════════

-- | Intra-color distances are ALWAYS ≤ 3 (purely temporal)
-- | Inter-color distances are ALWAYS ≥ 1 (at least one color axis differs)
-- | The OVERLAP region [1, 3] is where intra and inter coexist.
-- | The SEPARATION is characterized by the K distribution:
-- |   Intra: K = 1 always (only epoch differs)
-- |   Inter: K ∈ {1,2,3,4} with K ~ Binomial(3, 3/4) + 1
-- |          (at least 1 color axis differs, plus maybe epoch)

-- ════════════════════════════════════════════════════════════════
-- § 7. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " Tesseract Distances: Binomial Distribution of Palette Gaps"
  putStrLn " 64 sRGB colors × 4 epochs = 256 entries"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""

  -- Basic counts
  let nTotal = length allCoords
      nGroups = Map.size srgbGroups
      nIntra = sum (Map.elems intraSqDistances)
      nInter = sum (Map.elems interSqDistances)
      nAll = sum (Map.elems allPairSqDistances)
  putStrLn $ "  Palette entries:     " ++ show nTotal
  putStrLn $ "  sRGB families:       " ++ show nGroups
  putStrLn $ "  Total pairs C(256,2):" ++ show nAll
  putStrLn $ "  Intra-color pairs:   " ++ show nIntra ++ " (same sRGB, different epoch)"
  putStrLn $ "  Inter-color pairs:   " ++ show nInter ++ " (different sRGB)"
  putStrLn ""

  -- Intra-color distances
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " INTRA-COLOR: distances between 4 epoch-copies of same sRGB"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  For any sRGB (a,b,c), its 4 copies are:"
  putStrLn "    (0,a,b,c), (1,a,b,c), (2,a,b,c), (3,a,b,c)"
  putStrLn "  Distance is PURELY temporal: d = |epoch₁ - epoch₂|"
  putStrLn ""
  putStrLn "  d²  │ d     │ count │ fraction"
  putStrLn "  ────┼───────┼───────┼──────────"
  let intraDist = Map.toAscList intraSqDistances
  mapM_ (\(dsq, cnt) ->
    putStrLn $ "  " ++ padL 3 (show dsq)
            ++ " │ " ++ padL 5 (showF (sqrt (fromIntegral dsq)))
            ++ " │ " ++ padL 5 (show cnt)
            ++ " │ " ++ showF (fromIntegral cnt / fromIntegral nIntra)
    ) intraDist
  putStrLn ""
  putStrLn $ "  Total: " ++ show nIntra ++ " pairs"
  putStrLn $ "  E[d] = (3×1 + 2×2 + 1×3)/6 = " ++ showF ((3+4+3)/6)
  putStrLn $ "  All distances ≤ 3. Purely 1D (temporal axis only)."
  putStrLn ""

  -- Intra K distribution
  putStrLn "  Differing coordinates (K):"
  let intraKList = Map.toAscList intraK
  mapM_ (\(k, cnt) ->
    putStrLn $ "    K=" ++ show k ++ ": " ++ show cnt ++ " pairs"
    ) intraKList
  putStrLn "  → K=1 always. Only the epoch axis changes. ✓"
  putStrLn ""

  -- Inter-color distances
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " INTER-COLOR: distances between different sRGB families"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  d²  │ d     │ count  │ fraction"
  putStrLn "  ────┼───────┼────────┼──────────"
  let interDist = Map.toAscList interSqDistances
  mapM_ (\(dsq, cnt) ->
    putStrLn $ "  " ++ padL 3 (show dsq)
            ++ " │ " ++ padL 5 (showF (sqrt (fromIntegral dsq)))
            ++ " │ " ++ padL 6 (show cnt)
            ++ " │ " ++ showF (fromIntegral cnt / fromIntegral nInter)
    ) (take 20 interDist)
  if length interDist > 20
    then putStrLn $ "  ... (" ++ show (length interDist) ++ " distinct d² values)"
    else return ()
  putStrLn ""

  -- K distribution (THE binomial)
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " BINOMIAL: K = number of differing coordinates"
  putStrLn " K ~ Binomial(4, 3/4) for random pairs"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn $ "  K │ observed │ expected B(4,3/4)×" ++ show nAll ++ " │ ratio"
  putStrLn "  ──┼──────────┼─────────────────────────┼───────"
  let kList = Map.toAscList kDistribution
  mapM_ (\(k, cnt) -> do
    let expected = binomPMF_K k * fromIntegral nAll
    putStrLn $ "  " ++ show k
            ++ " │ " ++ padL 8 (show cnt)
            ++ " │ " ++ padL 23 (showF expected)
            ++ " │ " ++ showF (fromIntegral cnt / expected)
    ) kList
  putStrLn ""
  let chiSq = sum [ (fromIntegral cnt - expected)^(2::Int) / expected
                   | (k, cnt) <- kList
                   , let expected = binomPMF_K k * fromIntegral nAll
                   , expected > 0 ]
  putStrLn $ "  χ² = " ++ showF chiSq ++ "  (good fit if < 10, df=4)"
  putStrLn ""

  -- Specific example: black and white
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " EXAMPLE PAIRS"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  mapM_ (\(s1, s2, dists) -> do
    let sorted = sort dists
        meanD = sum dists / fromIntegral (length dists)
        minD = head sorted
        maxD = last sorted
    putStrLn $ "  " ++ showTriple s1 ++ " ↔ " ++ showTriple s2
    putStrLn $ "    16 pairwise distances (4 epochs × 4 epochs):"
    putStrLn $ "    min=" ++ showF minD ++ " max=" ++ showF maxD
            ++ " mean=" ++ showF meanD
    putStrLn $ "    values: " ++ intercalate ", " (map showF sorted)
    putStrLn ""
    ) sampleInterDistances

  -- The separation
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " INTRA vs INTER SEPARATION"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  let intraDists = sort allIntraDistances
      interDists = sort (concat [interColorDistances s1 s2
                                | s1 <- Map.keys srgbGroups
                                , s2 <- Map.keys srgbGroups
                                , s1 < s2])
      intraMax = maximum intraDists
      interMin = minimum interDists
  putStrLn $ "  Intra-color range: [" ++ showF (head intraDists)
          ++ ", " ++ showF intraMax ++ "]"
  putStrLn $ "  Inter-color range: [" ++ showF interMin
          ++ ", " ++ showF (last interDists) ++ "]"
  putStrLn $ "  Overlap region:    [" ++ showF interMin
          ++ ", " ++ showF intraMax ++ "]"
  putStrLn ""
  if interMin <= intraMax
    then putStrLn "  ★ There IS overlap: some inter-color pairs are as close"
      >> putStrLn "    as intra-color pairs. This happens when two sRGB colors"
      >> putStrLn "    are adjacent (differ by 1 on one axis) and share an epoch."
    else putStrLn "  ★ No overlap: inter and intra distances are fully separated."
  putStrLn ""

  -- Expected distance statistics
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " EXPECTED DISTANCE (theoretical)"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn $ "  E[|x-y|²] per coordinate = " ++ showF expectedSqDiff1D
  putStrLn $ "  E[D²] = 4 × " ++ showF expectedSqDiff1D
          ++ " = " ++ showF expectedSqDist4D
  putStrLn $ "  E[D] ≈ √" ++ showF expectedSqDist4D
          ++ " ≈ " ++ showF (sqrt expectedSqDist4D)
  putStrLn ""
  -- Actual mean
  let actualMeanSq = fromIntegral (sum [dsq * cnt | (dsq, cnt) <- Map.toList allPairSqDistances])
                   / fromIntegral nAll
  putStrLn $ "  Actual E[D²] = " ++ showF actualMeanSq
  putStrLn $ "  Actual E[D]  ≈ " ++ showF (sqrt actualMeanSq)
  putStrLn ""

  -- Summary
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn " SUMMARY"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  The distance distribution in the 4⁴ tesseract has two parts:"
  putStrLn ""
  putStrLn "  1. INTRA-COLOR (same sRGB, different epoch):"
  putStrLn "     K=1 always. Distance ∈ {1, 2, 3}."
  putStrLn "     Distribution: P(1)=1/2, P(2)=1/3, P(3)=1/6."
  putStrLn "     This is the discrete triangular distribution on {1,2,3}."
  putStrLn ""
  putStrLn "  2. INTER-COLOR (different sRGB):"
  putStrLn "     K ~ Binomial(4, 3/4). E[K]=3."
  putStrLn "     The number of differing coordinates IS the binomial."
  putStrLn "     The DISTANCE is a function of K and the magnitudes."
  putStrLn ""
  putStrLn "  The binomial is not on the distance itself —"
  putStrLn "  it's on the NUMBER OF AXES that differ."
  putStrLn "  This is the Hamming distance in the tesseract lattice."
  putStrLn ""
  putStrLn "  K=0: same point (impossible for distinct pairs)"
  putStrLn "  K=1: differ on 1 axis (neighbor in the lattice)"
  putStrLn "  K=2: differ on 2 axes (face diagonal)"
  putStrLn "  K=3: differ on 3 axes (space diagonal in 3D face)"
  putStrLn "  K=4: differ on all 4 axes (tesseract diagonal)"
  putStrLn "══════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 1000) :: Int) / 1000.0 :: Double)
          in take 7 (s ++ repeat '0')

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

showTriple :: SRGBTriple -> String
showTriple (a, b, c) = "(" ++ show a ++ "," ++ show b ++ "," ++ show c ++ ")"
