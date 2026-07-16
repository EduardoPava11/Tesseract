{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- WassersteinPalette: Wasserstein Barycentric Coordinates for
-- Per-Frame Palette Histograms
--
--   (after Bonneel, Peyré, Cuturi — "Wasserstein Barycentric
--    Coordinates", SIGGRAPH 2016 — adapted to the bell palette)
--
-- A frame's color content is a 256-bin histogram over the bell
-- palette (16 luminance strata of sizes
--   bell = [1,1,2,4,8,16,32,64,64,32,16,8,4,2,1,1],  Σ = 256).
-- Transport is STRATIFIED: the histogram projects onto the 16-bin
-- luminance-stratum axis, where 1-D optimal transport is EXACT —
--
--   EMD(A, B) = Σ_k |CDF_A(k) − CDF_B(k)|
--
-- the sorted-CDF machinery of BinomialCube's EMD. CDFs are
-- probability-normalized and stratum spacing is 1, so EMD lives
-- in [0, 15] strata.
--
-- BARYCENTER of histograms {H_i} with weights λ (Σλ = 1, λ ≥ 0):
-- in 1-D the Wasserstein barycenter is the QUANTILE AVERAGE — the
-- average of the inverse CDFs. Reference conventions (a Swift
-- port must match ALL of these):
--   · every histogram carries total mass T = 256 samples;
--   · quantiles are sampled at the T mid-levels q_j = (j+½)/T,
--     so the inverse-CDF table of a histogram is exactly its
--     multiset of strata, sorted — a vertex reconstructs EXACTLY;
--   · averaged positions land back on the stratum axis by FLOOR,
--     computed in INTEGER arithmetic: for rational weights
--     λ_i = n_i/g the bin is (Σ n_i·k_i) `div` g. No float ever
--     touches the floor.
--
-- Barycentric COORDINATES of a target H against a dictionary
-- {D_1..D_m}: the λ minimizing EMD(H, Bary(λ; D)). The reference
-- uses m = 3 and a coarse grid search over the simplex at
-- resolution 1/10 — this is a spec, not production.
--
-- WHY: coordinates against {first, middle, last} of a burst give
-- each frame a 3-number color address — the perceptual time axis.
-- ════════════════════════════════════════════════════════════════

module WassersteinPalette where

import Data.List (minimumBy, sort, transpose)
import Data.Ord (comparing)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE BELL LAYOUT (shared vocabulary with BellPalette)
-- ════════════════════════════════════════════════════════════════

bell :: [Int]
bell = [1,1,2,4,8,16,32,64,64,32,16,8,4,2,1,1]

nStrata :: Int
nStrata = 16

-- | offsets !! k = first palette index of stratum k.
offsets :: [Int]
offsets = scanl (+) 0 bell

-- | Palette index range owned by stratum k: [lo, lo + w).
stratumRange :: Int -> (Int, Int)
stratumRange k = (offsets !! k, bell !! k)

-- ════════════════════════════════════════════════════════════════
-- § 2. HISTOGRAMS AND THE STRATUM PROJECTION
--
-- A frame histogram has 256 bins (one per palette entry) and total
-- mass T = frameMass. For transport it projects to 16 stratum bins
-- by summing each stratum's index range.
-- ════════════════════════════════════════════════════════════════

type Hist256 = [Int]   -- 256 bins, counts, Σ = frameMass
type Hist16  = [Int]   --  16 bins, counts, Σ = frameMass

frameMass :: Int
frameMass = 256

-- | Bin counter for SORTED input (the ResolutionLadder span walk).
binCounts :: Int -> [Int] -> [Int]
binCounts nBins = go 0
  where
    go i ys | i == nBins = []
            | otherwise  = let (h, t) = span (== i) ys
                           in length h : go (i + 1) t

histogram256 :: [Int] -> Hist256
histogram256 = binCounts 256 . sort

-- | 256-bin palette histogram → 16-bin stratum histogram.
project :: Hist256 -> Hist16
project h = [ sum (take w (drop lo h))
            | k <- [0 .. nStrata - 1], let (lo, w) = stratumRange k ]

-- ════════════════════════════════════════════════════════════════
-- § 3. EXACT 1-D OPTIMAL TRANSPORT (EMD = Σ|ΔCDF|)
-- ════════════════════════════════════════════════════════════════

-- | EMD between two equal-mass stratum histograms. Integer CDF
--   differences, normalized ONCE by the mass — probability CDFs,
--   unit stratum spacing. Range [0, 15].
emd :: Hist16 -> Hist16 -> Double
emd a b = fromIntegral (sum (map abs (zipWith (-) (cdf a) (cdf b))))
        / fromIntegral frameMass
  where cdf = scanl1 (+)

-- ════════════════════════════════════════════════════════════════
-- § 4. THE QUANTILE-AVERAGE BARYCENTER
--
-- invTable h = the inverse CDF sampled at q_j = (j+½)/T — which
-- for integer counts is just the sorted multiset of strata:
--   concat [replicate c_k k]  (length exactly T).
-- Bary with rational weights n_i/g: position_j = Σ n_i·k_i div g,
-- an INTEGER floor. Each table is non-decreasing and weights are
-- non-negative, so positions come out sorted — binCounts applies.
-- ════════════════════════════════════════════════════════════════

invTable :: Hist16 -> [Int]
invTable h = concat [ replicate c k | (k, c) <- zip [0 ..] h ]

-- | Barycenter: numerators ns (Σ ns = g), denominator g, one
--   inverse-CDF table per dictionary atom. Total and exact.
bary :: [Int] -> Int -> [[Int]] -> Hist16
bary ns g tables =
  binCounts nStrata
    [ sum (zipWith (*) ns col) `div` g | col <- transpose tables ]

-- ════════════════════════════════════════════════════════════════
-- § 5. BARYCENTRIC COORDINATES (m = 3, simplex grid search)
-- ════════════════════════════════════════════════════════════════

gridG :: Int
gridG = 10

-- | All weight numerators [n1,n2,n3] with Σ = gridG: the simplex
--   at resolution 1/gridG, 66 points.
simplexGrid :: [[Int]]
simplexGrid = [ [i, j, gridG - i - j] | i <- [0 .. gridG], j <- [0 .. gridG - i] ]

-- | λ minimizing EMD(H, Bary(λ; D)). Ties break to the FIRST grid
--   point in (n1-major) enumeration order — deterministic.
coords :: Hist16 -> [Hist16] -> [Double]
coords h dict = map ((/ fromIntegral gridG) . fromIntegral) bestNs
  where
    tables = map invTable dict
    bestNs = snd (minimumBy (comparing fst)
                    [ (emd h (bary ns gridG tables), ns) | ns <- simplexGrid ])

-- ════════════════════════════════════════════════════════════════
-- § 6. DETERMINISTIC PSEUDO-RANDOMNESS AND FRAME GENERATION
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

-- | Infinite uniform [0,1) stream from a seed.
uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

clamp01 :: Double -> Double
clamp01 = max 0 . min 1

-- | A frame's 256-bin histogram: T samples with luminance
--   l = clamp01(mu + w·(u1+u2−1)) (triangular noise of half-width
--   w), stratum by band, palette index uniform inside the
--   stratum's range.
frameHist :: Int -> Double -> Double -> Hist256
frameHist seed mu w = histogram256 (take frameMass (go (uniforms seed)))
  where
    go (u1:u2:u3:us) =
      let l        = clamp01 (mu + w * (u1 + u2 - 1))
          k        = min (nStrata - 1) (floor (l * fromIntegral nStrata))
          (lo, wk) = stratumRange k
      in (lo + min (wk - 1) (floor (u3 * fromIntegral wk))) : go us
    go _ = []

-- | The 64-frame trajectory: mean luminance AND spread drift
--   smoothly (the spread drift breaks the pure-translation
--   degeneracy of quantile mixtures — coordinates stay unique).
muAt, spreadAt :: Int -> Double
muAt     t = 0.15 + 0.70 * fromIntegral t / 63
spreadAt t = 0.12 + 0.18 * fromIntegral t / 63

trajectory :: [Hist16]
trajectory = [ project (frameHist (9000 + 37 * t) (muAt t) (spreadAt t))
             | t <- [0 .. 63] ]

-- | Dictionary = {first, middle, last} of the trajectory.
dictionary :: [Hist16]
dictionary = [ trajectory !! 0, trajectory !! 31, trajectory !! 63 ]

-- | Shared coordinate trajectory (WB6 + visualization).
trajCoords :: [[Double]]
trajCoords = [ coords h dictionary | h <- trajectory ]

-- | All mass in one stratum.
pointMass :: Int -> Hist16
pointMass a = [ if k == a then frameMass else 0 | k <- [0 .. nStrata - 1] ]

-- ════════════════════════════════════════════════════════════════
-- § 7. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (WB1) Identity: the coordinates of D_k against the dictionary
--       are the k-th simplex vertex, within grid resolution. (At
--       the vertex the barycenter reconstructs D_k EXACTLY — the
--       mid-level quantile convention — so its EMD is 0.)
axiom_WB1 :: Bool
axiom_WB1 = all vertexOK [0 .. 2]
  where
    vertexOK k =
      let lam = coords (dictionary !! k) dictionary
          e i = if i == k then 1 else 0 :: Double
      in maximum [ abs (lam !! i - e i) | i <- [0 .. 2] ]
           <= 1 / fromIntegral gridG + 1e-12

-- (WB2) Partition: recovered λ sums to 1 and every component ≥ 0.
axiom_WB2 :: Bool
axiom_WB2 = all ok [5, 13, 21, 29, 37, 45, 53, 58]
  where
    ok t = let lam = coords (trajectory !! t) dictionary
           in abs (sum lam - 1) < 1e-9 && all (>= 0) lam

-- (WB3) Interpolation: Bary(λ) over a dictionary of two IDENTICAL
--       histograms is that histogram, EXACTLY (structural equality
--       for every grid λ) — integer floor of n·k + (g−n)·k over g.
axiom_WB3 :: Bool
axiom_WB3 = all ok [ (t, n) | t <- [0, 17, 44], n <- [0 .. gridG] ]
  where
    ok (t, n) =
      let h  = trajectory !! t
          ts = map invTable [h, h]
      in bary [n, gridG - n] gridG ts == h

-- (WB4) Metric sanity: EMD(H,H) = 0; EMD symmetric; triangle
--       inequality on random triples (all three rotations).
axiom_WB4 :: Bool
axiom_WB4 = all triple [1 .. 8]
  where
    hAt s m w = project (frameHist s m w)
    triple i =
      let a = hAt (300 + i) 0.25 0.15
          b = hAt (400 + i) 0.55 0.20
          c = hAt (500 + i) 0.80 0.12
      in emd a a == 0 && emd b b == 0 && emd c c == 0
      && emd a b == emd b a && emd a c == emd c a && emd b c == emd c b
      && emd a c <= emd a b + emd b c + 1e-12
      && emd a b <= emd a c + emd c b + 1e-12
      && emd b c <= emd b a + emd a c + 1e-12

-- (WB5) Quantile-average correctness: the (½,½) barycenter of two
--       point masses at strata a and b is the point mass at the
--       mid-quantile ⌊(a+b)/2⌋ — the FLOOR convention, exact.
axiom_WB5 :: Bool
axiom_WB5 = all ok [(3,6), (0,15), (2,3), (7,8), (5,5), (1,14), (6,13)]
  where
    ok (a, b) =
      bary [1, 1] 2 (map invTable [pointMass a, pointMass b])
        == pointMass ((a + b) `div` 2)

-- (WB6) Trajectory: for the smooth 64-frame drift, coordinates
--       against {first, middle, last} move monotonically IN
--       AGGREGATE. Precise statement: split λ(t) into 8 blocks of
--       8 frames; block means of λ_last are non-decreasing and of
--       λ_first non-increasing, each within slack 1/gridG (one
--       grid step); the total sweep is ≥ 0.6 on both. This is the
--       perceptual law behind using λ as the time axis.
axiom_WB6 :: Bool
axiom_WB6 =
     nonDecreasing bm3 && nonIncreasing bm1
  && last bm3 - head bm3 >= 0.6
  && head bm1 - last bm1 >= 0.6
  where
    blockMean xs   = [ sum (take 8 (drop (8 * b) xs)) / 8 | b <- [0 .. 7] ]
    bm1            = blockMean (map (!! 0) trajCoords)
    bm3            = blockMean (map (!! 2) trajCoords)
    slack          = 1 / fromIntegral gridG
    nonDecreasing xs = and (zipWith (\x y -> y >= x - slack) xs (tail xs))
    nonIncreasing xs = and (zipWith (\x y -> y <= x + slack) xs (tail xs))

-- ════════════════════════════════════════════════════════════════
-- § 8. VISUALIZATION
-- ════════════════════════════════════════════════════════════════

-- | One dictionary atom as a stratum bar row (1 char per 4 counts).
showAtomRow :: Int -> IO ()
showAtomRow k = putStrLn $
     "  " ++ padL 2 (show k) ++ " │ "
  ++ concat [ padL 4 (show (d !! k)) | d <- dictionary ]
  ++ "   " ++ replicate (max 0 ((dictionary !! 1 !! k) `div` 4)) '█'

showLambda :: [Double] -> String
showLambda lam = unwords (map showF lam)

-- ════════════════════════════════════════════════════════════════
-- § 9. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " WassersteinPalette: Barycentric Coordinates on the Bell"
  putStrLn " Stratified 1-D OT: EMD = Σ|ΔCDF| on 16 luminance strata."
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── The Dictionary {first, middle, last} (stratum counts) ──"
  putStrLn ""
  putStrLn "   k │  D₁  D₂  D₃    (bar = D₂)"
  putStrLn "  ───┼─────────────────────────────"
  mapM_ showAtomRow [0 .. nStrata - 1]
  putStrLn ""
  let [d1, d2, d3] = dictionary
  putStrLn $ "  EMD(D₁,D₂) = " ++ showF (emd d1 d2)
          ++ "   EMD(D₂,D₃) = " ++ showF (emd d2 d3)
          ++ "   EMD(D₁,D₃) = " ++ showF (emd d1 d3)
  putStrLn "  (probability CDFs, unit stratum spacing: EMD ∈ [0,15])"
  putStrLn ""

  putStrLn "── Coordinate Trajectory (64 frames, grid 1/10) ──"
  putStrLn ""
  putStrLn "   t  │  λ₁     λ₂     λ₃"
  putStrLn "  ────┼──────────────────────"
  mapM_ (\t -> putStrLn $ "  " ++ padL 3 (show t) ++ " │  "
                       ++ showLambda (trajCoords !! t))
        ([0, 8 .. 56] ++ [63])
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "WB1 identity: dictionary atoms recover their own vertex"    [axiom_WB1]
  check "WB2 partition: recovered λ sums to 1, all λ ≥ 0"            [axiom_WB2]
  check "WB3 interpolation: Bary over {H,H} = H, exactly"            [axiom_WB3]
  check "WB4 metric: EMD zero / symmetric / triangle on triples"     [axiom_WB4]
  check "WB5 quantile-average: ½,½ point masses meet at ⌊(a+b)/2⌋"   [axiom_WB5]
  check "WB6 trajectory: block-mean λ sweeps first→last, monotone"   [axiom_WB6]
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  histogram → strata → quantiles → coordinates"
  putStrLn ""
  putStrLn "  On the luminance axis, transport is EXACT and cheap:"
  putStrLn "  EMD is a sorted-CDF difference, the barycenter is a"
  putStrLn "  quantile average, and both are pure integer arithmetic"
  putStrLn "  under the reference conventions (mass 256, mid-level"
  putStrLn "  quantiles, floor by integer div)."
  putStrLn ""
  putStrLn "  A frame's λ against {first, middle, last} is its color"
  putStrLn "  ADDRESS in the burst: vertices are the anchors (WB1),"
  putStrLn "  the simplex is the map (WB2), and a smooth capture"
  putStrLn "  walks it monotonically (WB6) — λ IS the time axis."
  putStrLn "══════════════════════════════════════════════════════════"

-- Helpers (no-scientific-notation formatter: integer math, 3 dp)
showF :: Double -> String
showF x =
  let n    = round (abs x * 1000) :: Int
      sign = if x < 0 then "-" else ""
      frac = show (n `mod` 1000)
      pad3 = replicate (3 - length frac) '0' ++ frac
  in sign ++ show (n `div` 1000) ++ "." ++ pad3

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
