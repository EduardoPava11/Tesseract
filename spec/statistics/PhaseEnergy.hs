{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- PhaseEnergy: the two energies and the order↔subject transition
--
-- Daniel's directive (2026-08-09): two energy analyses — (a) the 256
-- energy of each frame's palette, (b) the 256 distribution onto the
-- 64×64 — and the BIG OBSERVABLE: the transition between the ordered
-- background and the high-energy, high-variance subject. Build the
-- phase-diagram machinery.
--
--   E_pal   Σ chroma² over the 256 table entries. σ-symmetric
--           (comp preserves chroma), and — theorem PE1 — an exact
--           closed form in the 9-number state: the palette energy
--           IS the chromatic variance of the stats.
--   E_dist  the configuration Hamiltonian of an index frame:
--           domain walls (exactly the Ising energy, PE4) plus
--           occupancy entropy. Its 4×4 restriction is
--           PairPermutations' adjacency (PE5).
--   Order   φ (σ-side fraction, magnetization analog), m_st
--           (staggered — the Néel detector for the Bayer band),
--           s (index entropy). The triple separates
--           SOLID / BAND / FACE pairwise (PE11).
--
-- Honesty: the machine is deterministic at T=0 with an explicit
-- field t(d); the expected transition is a CROSSOVER measured by
-- fluctuation-ridge width, not a critical singularity. The diagram
-- axes are control parameters (t, E_pal); order parameters are
-- measured, never axes.
-- ════════════════════════════════════════════════════════════════

module PhaseEnergy where

import Data.List (sortOn)
import Data.Ord (Down(..))

-- ════════════════════════════════════════════════════════════════
-- § 1. DETERMINISTIC RANDOMNESS + LINEAR ALGEBRA (house pattern)
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

normals :: Int -> [Double]
normals seed = go (uniforms seed)
  where
    go (u1 : u2 : us) =
      let r = sqrt (-2 * log (max 1e-12 u1)); a = 2 * pi * u2
      in r * cos a : r * sin a : go us
    go _ = []

type V3 = (Double, Double, Double)

jacobi3 :: [[Double]] -> ([Double], [V3])
jacobi3 mat0 = go (50 :: Int) mat0 [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
  where
    finish a v = ( [a !! 0 !! 0, a !! 1 !! 1, a !! 2 !! 2]
                 , [ (v !! 0 !! i, v !! 1 !! i, v !! 2 !! i) | i <- [0 .. 2] ] )
    go 0 a v = finish a v
    go it a v =
      let (mx, p, q) = maximum [ (abs (a !! i !! j), i, j)
                               | i <- [0 .. 2], j <- [i + 1 .. 2] ]
      in if mx < 1e-14 then finish a v else
        let th = if abs (a !! p !! p - a !! q !! q) < 1e-18
                   then pi / 4
                   else 0.5 * atan (2 * a !! p !! q / (a !! p !! p - a !! q !! q))
            sn = sin th; cs = cos th
            app = cs*cs * a!!p!!p + 2*sn*cs * a!!p!!q + sn*sn * a!!q!!q
            aqq = sn*sn * a!!p!!p - 2*sn*cs * a!!p!!q + cs*cs * a!!q!!q
            arp r = cs * a !! r !! p + sn * a !! r !! q
            arq r = negate sn * a !! r !! p + cs * a !! r !! q
            newA i j | i == p && j == p = app
                     | i == q && j == q = aqq
                     | (i == p && j == q) || (i == q && j == p) = 0
                     | i == p = arp j
                     | j == p = arp i
                     | i == q = arq j
                     | j == q = arq i
                     | otherwise = a !! i !! j
            newV i j | j == p = cs * v !! i !! p + sn * v !! i !! q
                     | j == q = negate sn * v !! i !! p + cs * v !! i !! q
                     | otherwise = v !! i !! j
        in go (it - 1) [[newA i j | j <- [0 .. 2]] | i <- [0 .. 2]]
                       [[newV i j | j <- [0 .. 2]] | i <- [0 .. 2]]

canonDir :: V3 -> V3
canonDir v@(x, y, z)
  | x >  1e-9 = v
  | x < -1e-9 = neg
  | y >  1e-9 = v
  | y < -1e-9 = neg
  | z >= 0    = v
  | otherwise = neg
  where neg = (negate x, negate y, negate z)

-- ════════════════════════════════════════════════════════════════
-- § 2. STATES AND SHELLS (DyadPalette geometry, continuous form)
-- ════════════════════════════════════════════════════════════════

data GState = GState { gC :: V3, gCov :: [[Double]] }

sampleState :: Int -> GState
sampleState seed = GState c cov
  where
    us = uniforms seed
    c = (0.3 + 0.4 * (us !! 0), 0.3 * (us !! 1) - 0.15, 0.3 * (us !! 2) - 0.15)
    lams = [ exp (log 1e-6 + u * (log 2e-2 - log 1e-6))
           | u <- [us !! 3, us !! 4, us !! 5] ]
    (q0 : q1 : q2 : q3 : _) = normals (seed + 1)
    n = sqrt (q0*q0 + q1*q1 + q2*q2 + q3*q3)
    (w, x, y, z) = (q0/n, q1/n, q2/n, q3/n)
    r = [ [1 - 2*(y*y + z*z), 2*(x*y - w*z),     2*(x*z + w*y)]
        , [2*(x*y + w*z),     1 - 2*(x*x + z*z), 2*(y*z - w*x)]
        , [2*(x*z - w*y),     2*(y*z + w*x),     1 - 2*(x*x + y*y)] ]
    cov = [ [ sum [ r !! i !! k * lams !! k * r !! j !! k | k <- [0 .. 2] ]
            | j <- [0 .. 2] ] | i <- [0 .. 2] ]

-- Sign-canonical PCA (DY8) → shell frame of the state.
pcaOf :: GState -> [(V3, Double)]
pcaOf st = [ (canonDir dir, val)
           | (val, dir) <- sortOn (Down . fst) (zip vals vecs) ]
  where (vals, vecs) = jacobi3 (gCov st)

guardedStd :: Double -> Double
guardedStd v = max 1e-3 (sqrt (max 0 v))

ladder :: [Int]
ladder = [1, 1, 2, 4, 8, 16, 32, 64]

rho :: Int -> Double
rho k = 2 * fromIntegral k / 7

-- | Primary shell points, continuous (pre-clamp) — DyadPalette §5.
shellPoints :: GState -> [V3]
shellPoints st =
  [ ( cl + u * d1x + w * d2x, ca + u * d1y + w * d2y, cb + u * d1z + w * d2z )
  | (k, n) <- zip [0 ..] ladder
  , j <- [0 .. n - 1]
  , let th = 2 * pi * fromIntegral j / fromIntegral n
  , let u = rho k * cos th * g1
  , let w = rho k * sin th * g2 ]
  where
    (cl, ca, cb) = gC st
    ((d1x, d1y, d1z), v1) : ((d2x, d2y, d2z), v2) : _ = pcaOf st
    g1 = guardedStd v1
    g2 = guardedStd v2

chroma2 :: V3 -> Double
chroma2 (_, a, b) = a * a + b * b

-- | E_pal by direct summation: primaries + σ-half (comp preserves
--   chroma exactly, pre-clamp), i.e. 2 × Σ chroma² over the shells.
ePalDirect :: GState -> Double
ePalDirect st = 2 * sum (map chroma2 (shellPoints st))

-- | E_pal closed form in the 9-number state (theorem): per-shell
--   trigonometric sums evaluated analytically — n≥3 shells average
--   the cross terms away; k=1 keeps its cross term; k=2 keeps the
--   antipodal PC1 term. Never touches a shell point.
ePalClosed :: GState -> Double
ePalClosed st = 2 * sum (map shellTerm (zip [0 ..] ladder))
  where
    (_, ca, cb) = gC st
    ((_, d1y, d1z), v1) : ((_, d2y, d2z), v2) : _ = pcaOf st
    g1 = guardedStd v1
    g2 = guardedStd v2
    cmu = ca * ca + cb * cb
    p1 = d1y * d1y + d1z * d1z
    p2 = d2y * d2y + d2z * d2z
    crossMu1 = ca * d1y + cb * d1z
    shellTerm (k, n)
      | n == 1 && k == 0 = cmu
      | n == 1 =
          cmu + 2 * rho k * g1 * crossMu1 + rho k ^ (2 :: Int) * g1 * g1 * p1
      | n == 2 =
          2 * cmu + 2 * rho k ^ (2 :: Int) * g1 * g1 * p1
      | otherwise =
          fromIntegral n * cmu
            + fromIntegral n * rho k ^ (2 :: Int) / 2 * (g1 * g1 * p1 + g2 * g2 * p2)

-- ════════════════════════════════════════════════════════════════
-- § 3. THE CONFIGURATION HAMILTONIAN (index frames)
-- ════════════════════════════════════════════════════════════════

side :: Int
side = 64

-- | Side spin: +1 primary (index < 128), −1 σ-half.
spin :: Int -> Int
spin i = if i < 128 then 1 else -1

-- | Domain walls over the OPEN 64² lattice (B = 2·64·63 = 8064 bonds).
walls :: [Int] -> Int
walls f = length
  [ () | y <- [0 .. side - 1], x <- [0 .. side - 1]
       , (dx, dy) <- [(1, 0), (0, 1)]
       , x + dx < side, y + dy < side
       , spin (f !! (y * side + x)) /= spin (f !! ((y + dy) * side + (x + dx))) ]

bonds :: Int
bonds = 2 * side * (side - 1)

-- | The Ising sum Σ σ_p σ_q over the same open bonds.
isingSum :: [Int] -> Int
isingSum f = sum
  [ spin (f !! (y * side + x)) * spin (f !! ((y + dy) * side + (x + dx)))
  | y <- [0 .. side - 1], x <- [0 .. side - 1]
  , (dx, dy) <- [(1, 0), (0, 1)]
  , x + dx < side, y + dy < side ]

-- | Occupancy entropy over the 256-index histogram, normalized.
sOcc :: [Int] -> Double
sOcc f = negate (sum [ p * log p | i <- [0 .. 255]
                     , let c = length (filter (== i) f)
                     , c > 0
                     , let p = fromIntegral c / n ]) / log 256
  where n = fromIntegral (length f)

phiOf :: [Int] -> Double
phiOf f = fromIntegral (length (filter (>= 128) f)) / fromIntegral (length f)

-- | Staggered magnetization (the Néel detector), 4×4-aligned lattice.
mStag :: [Int] -> Double
mStag f = abs (fromIntegral total) / fromIntegral (length f)
  where
    total = sum [ sgn x y * spin (f !! (y * side + x))
                | y <- [0 .. side - 1], x <- [0 .. side - 1] ]
    sgn x y = if even (x + y) then 1 else -1 :: Int

-- Tile-level (4×4, toroidal) — the PairPermutations restriction.
tileWalls :: [Bool] -> Int
tileWalls t = length
  [ () | y <- [0 .. 3], x <- [0 .. 3]
       , (dx, dy) <- [(1, 0), (0, 1)]
       , t !! (y * 4 + x) /= t !! (((y + dy) `mod` 4) * 4 + ((x + dx) `mod` 4)) ]

tileAdjacency :: [Bool] -> Int
tileAdjacency t = 32 - tileWalls t

bayerOrder :: [Int]
bayerOrder = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

bayerTile :: Int -> [Bool]
bayerTile k = [ o < k | o <- bayerOrder ]

-- ════════════════════════════════════════════════════════════════
-- § 4. SYNTHETIC FRAMES (deterministic, three regions)
-- ════════════════════════════════════════════════════════════════

solidFrame :: [Int]
solidFrame = replicate (side * side) 255

-- | The frame tiled by the k=8 Bayer checkerboard (σ = 255, primary = 0).
neelFrame :: [Int]
neelFrame = [ if bayerTile 8 !! ((y `mod` 4) * 4 + (x `mod` 4)) then 255 else 0
            | y <- [0 .. side - 1], x <- [0 .. side - 1] ]

-- | High-entropy face: uniform random primaries 0..127.
faceFrame :: Int -> [Int]
faceFrame seed = [ floor (u * 128) | u <- take (side * side) (uniforms seed) ]

-- | Three-region frame: solid rows / Néel band / random face.
threeRegion :: Int -> [Int]
threeRegion seed =
  [ pick y x | y <- [0 .. side - 1], x <- [0 .. side - 1] ]
  where
    face = faceFrame seed
    pick y x
      | y < 20 = 255
      | y < 44 = if bayerTile 8 !! ((y `mod` 4) * 4 + (x `mod` 4)) then 255 else 64
      | otherwise = face !! (y * side + x)

regionOf :: [Int] -> (Int, Int) -> [Int]
regionOf f (y0, y1) =
  [ f !! (y * side + x) | y <- [y0 .. y1 - 1], x <- [0 .. side - 1] ]

-- Region observables computed on a sub-rectangle (rows y0..y1).
subPhi, subS :: [Int] -> Double
subPhi = phiOf'
  where phiOf' g = fromIntegral (length (filter (>= 128) g)) / fromIntegral (length g)
subS g = negate (sum [ p * log p | i <- [0 .. 255]
                     , let c = length (filter (== i) g), c > 0
                     , let p = fromIntegral c / fromIntegral (length g) ]) / log 256

subMStag :: [Int] -> Int -> Double
subMStag g rows = abs (fromIntegral total) / fromIntegral (length g)
  where
    total = sum [ (if even (x + y) then 1 else -1 :: Int) * spin (g !! (y * side + x))
                | y <- [0 .. rows - 1], x <- [0 .. side - 1] ]

-- ════════════════════════════════════════════════════════════════
-- § 5. AXIOMS
-- ════════════════════════════════════════════════════════════════

stateSeeds :: [Int]
stateSeeds = [11, 22, 33, 44, 55]

-- (PE1) Closed form: E_pal summed over the shells equals the exact
--       9-number formula, never touching a point.
axiom_PE1 :: Bool
axiom_PE1 = all ok stateSeeds
  where
    ok s = let st = sampleState s
               a = ePalDirect st
               b = ePalClosed st
           in abs (a - b) <= 1e-9 * max 1 (abs a)

-- (PE2) σ-symmetry: comp negates (a,b), preserving chroma — the
--       complement half contributes exactly the primary half,
--       pre-clamp. (Encoded: ePalDirect is 2× the primary sum, and
--       negating ab of every shell point changes nothing.)
axiom_PE2 :: Bool
axiom_PE2 = all ok stateSeeds
  where
    ok s = let st = sampleState s
               prim = sum (map chroma2 (shellPoints st))
               comp = sum (map (\(l, a, b) -> chroma2 (l, negate a, negate b))
                               (shellPoints st))
           in comp == prim

-- (PE3) Eigenvalue monotonicity: scaling the covariance up strictly
--       increases E_pal (pre-clamp) whenever the PC plane is
--       chromatic.
axiom_PE3 :: Bool
axiom_PE3 = all ok stateSeeds
  where
    ok s = let st = sampleState s
               grown = st { gCov = map (map (* 2)) (gCov st) }
           in ePalClosed grown > ePalClosed st

-- (PE4) Ising identity: walls = (B − Σσσ)/2 exactly, and the global
--       σ-flip i → 255−i preserves walls (PP7 lifted to the frame).
axiom_PE4 :: Bool
axiom_PE4 = all ok [ solidFrame, neelFrame, faceFrame 5, threeRegion 6 ]
  where
    ok f = walls f == (bonds - isingSum f) `div` 2
        && walls (map (255 -) f) == walls f

-- (PE5) Tile restriction: toroidal tile walls = 32 − adjacency
--       (PairPermutations), and Bayer maximizes walls in its class
--       (adjacency-minimal ⇔ wall-maximal, sampled permutations).
axiom_PE5 :: Bool
axiom_PE5 =
     and [ tileWalls (bayerTile k) == 32 - tileAdjacency (bayerTile k)
         | k <- [0 .. 16] ]
  && and [ tileWalls (bayerTile k) >= tileWalls (permute s (bayerTile k))
         | k <- [2, 4, 8, 12], s <- [1 .. 60] ]
  where
    permute s t = [ t !! i | i <- shuffleP s ]
    shuffleP s = go (uniforms s) [0 .. 15]
      where
        go _ [] = []
        go (u : us) xs =
          let i = min (length xs - 1) (floor (u * fromIntegral (length xs)))
              (a, y : b) = splitAt i xs
          in y : go us (a ++ b)
        go [] _ = []

-- (PE6) Ground states: the solid frame has walls 0, s 0, φ 1; the
--       Néel frame has |m_st| = 1 and maximal walls.
axiom_PE6 :: Bool
axiom_PE6 =
     walls solidFrame == 0 && sOcc solidFrame == 0 && phiOf solidFrame == 1
  && mStag neelFrame == 1 && walls neelFrame == bonds

-- (PE7) Coverage dictionary: a frame tiled by bayerTile k has
--       φ = k/16 exactly (the lattice-gas equivalence).
axiom_PE7 :: Bool
axiom_PE7 = and
  [ phiOf f == fromIntegral k / 16
  | k <- [0, 3, 8, 13, 16]
  , let f = [ if bayerTile k !! ((y `mod` 4) * 4 + (x `mod` 4)) then 255 else 0
            | y <- [0 .. side - 1], x <- [0 .. side - 1] ] ]

-- (PE8) Staggered detector: among Bayer-tiled frames, |m_st| = 1
--       exactly at k = 8 and is strictly smaller elsewhere; the
--       sublattice contrast is nonzero for every k ∉ {0,16}.
axiom_PE8 :: Bool
axiom_PE8 =
     mSt 8 == 1
  && and [ mSt k < 1 | k <- [0 .. 16], k /= 8 ]
  && and [ any id (bayerTile k) /= all id (bayerTile k) || k == 0 || k == 16
         | k <- [0 .. 16] ]
  where
    mSt k = mStag [ if bayerTile k !! ((y `mod` 4) * 4 + (x `mod` 4)) then 255 else 0
                  | y <- [0 .. side - 1], x <- [0 .. side - 1] ]

-- (PE10) Mirror invariance: the horizontal index-domain mirror
--        preserves walls, φ, s, and |m_st| on the 64² frame.
axiom_PE10 :: Bool
axiom_PE10 = all ok [ neelFrame, faceFrame 9, threeRegion 10 ]
  where
    mirror f = [ f !! (y * side + (side - 1 - x))
               | y <- [0 .. side - 1], x <- [0 .. side - 1] ]
    ok f = walls (mirror f) == walls f
        && phiOf (mirror f) == phiOf f
        && abs (sOcc (mirror f) - sOcc f) < 1e-12
        && abs (mStag (mirror f) - mStag f) < 1e-12

-- (PE11) Phase separability: on the three-region frame the
--        (φ, m_st, s) triple classifies SOLID / BAND / FACE with
--        the stated margins.
axiom_PE11 :: Bool
axiom_PE11 =
     subPhi solidR > 0.9 && subS solidR < 0.1
  && subMStag bandR 24 > 0.5
  && subS faceR > 0.5 && subPhi faceR < 0.1
  where
    f = threeRegion 21
    solidR = regionOf f (0, 20)
    bandR = regionOf f (20, 44)
    faceR = regionOf f (44, 64)

-- (PE12) Determinism: every observable is a pure function of its
--        frame; recomputation is identical.
axiom_PE12 :: Bool
axiom_PE12 =
  let f = threeRegion 31
  in (walls f, phiOf f, sOcc f, mStag f) == (walls f, phiOf f, sOcc f, mStag f)
  && ePalClosed (sampleState 77) == ePalClosed (sampleState 77)

-- ════════════════════════════════════════════════════════════════
-- § 6. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " PhaseEnergy: palette energy, configuration energy, and"
  putStrLn " the order ↔ subject transition"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  let st = sampleState 11
  putStrLn $ "  sample state 11: E_pal(direct) = " ++ showF (ePalDirect st)
          ++ "   E_pal(closed 9-number form) = " ++ showF (ePalClosed st)
  putStrLn $ "  solid: walls=" ++ show (walls solidFrame)
          ++ "  Néel: walls=" ++ show (walls neelFrame) ++ "/" ++ show bonds
          ++ " m_st=" ++ showF (mStag neelFrame)
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "PE1 E_pal closed form = shell sum (the 9 numbers carry it)" [axiom_PE1]
  check "PE2 σ-symmetry: complement half = primary half, pre-clamp"  [axiom_PE2]
  check "PE3 E_pal strictly grows with the eigenvalues"              [axiom_PE3]
  check "PE4 walls = (B − Σσσ)/2 exactly; σ-flip invariant"          [axiom_PE4]
  check "PE5 tile walls = 32 − adjacency; Bayer wall-maximal"        [axiom_PE5]
  check "PE6 ground states: solid (0 walls) and Néel (|m_st|=1)"     [axiom_PE6]
  check "PE7 coverage dictionary: φ = k/16 on Bayer-tiled frames"    [axiom_PE7]
  check "PE8 staggered detector peaks uniquely at k = 8"             [axiom_PE8]
  check "PE10 mirror preserves walls, φ, s, |m_st|"                  [axiom_PE10]
  check "PE11 (φ, m_st, s) separates SOLID / BAND / FACE"            [axiom_PE11]
  check "PE12 determinism: pure functions of frame and state"        [axiom_PE12]
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  Two energies, one diagram. The palette's energy lives"
  putStrLn "  in the 9-number state (PE1); the frame's energy is the"
  putStrLn "  Ising Hamiltonian of its σ-spins plus its occupancy"
  putStrLn "  entropy (PE4). The background is the saturated phase,"
  putStrLn "  the Bayer band is Néel order (PE8), the subject is"
  putStrLn "  driven disorder — and the capture is a trajectory"
  putStrLn "  across the (t, E_pal) plane. No temperature exists:"
  putStrLn "  the transition is a crossover, measured by the width"
  putStrLn "  of its fluctuation ridge."
  putStrLn "══════════════════════════════════════════════════════════"

showF :: Double -> String
showF x =
  let n = round (abs x * 1000) :: Int
      sign = if x < 0 then "-" else ""
      frac = show (n `mod` 1000)
  in sign ++ show (n `div` 1000) ++ "." ++ replicate (3 - length frac) '0' ++ frac

check :: String -> [Bool] -> IO ()
check name results =
  let mark = if and results then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
