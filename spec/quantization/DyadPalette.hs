{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- DyadPalette: The DYAD-256 Paired Palette
--
-- 256 colors that are really 128 colors and a group action.
--
--   σ(i) = 255 − i            the index involution
--   T[σ(i)] = comp(T[i])      the table law
--   comp(L,a,b) = (L,−a,−b)   hue+180° in OKLab IS negation:
--                             L and chroma preserved, exactly.
--
-- The 128 primaries are allocated by a binomial ladder over
-- concentric shells of the face's OKLab distribution:
--
--   ladder = [1,1,2,4,8,16,32,64]   Σ = 128
--
-- Level k puts 2^(k−1) colors on the ellipse of radius ρ_k = 2k/7
-- standard deviations in the PC1×PC2 plane (level 0 = centroid).
-- Together the 8 rings tile the distribution's disk: a polar
-- binomial sampling. Complements are generated, never designed.
--
-- Roles: face pixels quantize to primaries 0..127 ONLY; the
-- background collapses to the single index 255 = comp(centroid).
--
-- Gamut law: when a complement (or shell sample) leaves sRGB, it
-- is clamped by scaling chroma alone — L and hue are never moved.
-- ════════════════════════════════════════════════════════════════

module DyadPalette where

import Data.List (sortOn)
import Data.Ord (Down(..))

-- ════════════════════════════════════════════════════════════════
-- § 1. THE LADDER AND THE INVOLUTION
-- ════════════════════════════════════════════════════════════════

dyadLadder :: [Int]
dyadLadder = [1, 1, 2, 4, 8, 16, 32, 64]

nLevels :: Int
nLevels = 8

primaryCount :: Int
primaryCount = 128

-- | offsets !! k = first primary index of level k (9 entries, last = 128).
offsets :: [Int]
offsets = scanl (+) 0 dyadLadder

-- | The index involution. Primaries 0..127 ↔ complements 255..128.
partner :: Int -> Int
partner i = 255 - i

-- ════════════════════════════════════════════════════════════════
-- § 2. OKLAB (Björn Ottosson's matrices, Double precision)
-- ════════════════════════════════════════════════════════════════

type RGB8 = (Int, Int, Int)              -- sRGB bytes, 0..255
type Lab  = (Double, Double, Double)     -- OKLab (L, a, b)

srgbToLinear :: Double -> Double
srgbToLinear c = if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ** 2.4

linearToSrgb :: Double -> Double
linearToSrgb c = if c <= 0.0031308 then 12.92 * c else 1.055 * c ** (1 / 2.4) - 0.055

cbrt :: Double -> Double
cbrt x = if x < 0 then negate (negate x ** (1 / 3)) else x ** (1 / 3)

srgb8ToOklab :: RGB8 -> Lab
srgb8ToOklab (r8, g8, b8) =
  let r = srgbToLinear (fromIntegral r8 / 255)
      g = srgbToLinear (fromIntegral g8 / 255)
      b = srgbToLinear (fromIntegral b8 / 255)
      l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
      m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
      s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
      l' = cbrt l; m' = cbrt m; s' = cbrt s
  in ( 0.2104542553 * l' + 0.7936177850 * m' - 0.0040720468 * s'
     , 1.9779984951 * l' - 2.4285922050 * m' + 0.4505937099 * s'
     , 0.0259040371 * l' + 0.7827717662 * m' - 0.8086757660 * s' )

oklabToLinear :: Lab -> (Double, Double, Double)
oklabToLinear (ll, aa, bb) =
  let l' = ll + 0.3963377774 * aa + 0.2158037573 * bb
      m' = ll - 0.1055613458 * aa - 0.0638541728 * bb
      s' = ll - 0.0894841775 * aa - 1.2914855480 * bb
      l = l' ^ (3 :: Int); m = m' ^ (3 :: Int); s = s' ^ (3 :: Int)
  in (  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
     , -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
     , -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s )

inGamut :: Lab -> Bool
inGamut lab =
  let (r, g, b) = oklabToLinear lab
  in all (\c -> c >= -1e-6 && c <= 1 + 1e-6) [r, g, b]

oklabToSrgb8 :: Lab -> RGB8
oklabToSrgb8 lab =
  let (r, g, b) = oklabToLinear lab
      to8 c = max 0 (min 255 (round (linearToSrgb (max 0 (min 1 c)) * 255)))
  in (to8 r, to8 g, to8 b)

-- ════════════════════════════════════════════════════════════════
-- § 3. COMP — hue+180° is negation; gamut clamp scales chroma only
-- ════════════════════════════════════════════════════════════════

comp :: Lab -> Lab
comp (l, a, b) = (l, negate a, negate b)

-- | Largest s ∈ [0,1] with (L, s·a, s·b) in gamut, by bisection.
--   s = 0 (the gray of the same L) is always in gamut for L ∈ [0,1],
--   so callers clamp L into [0,1] first (comp never changes L, and
--   the L of any real color is already in band).
chromaClamp :: Lab -> Lab
chromaClamp lab@(l, a, b)
  | inGamut lab = lab
  | otherwise   = let s = search 0 1 (40 :: Int)
                  in (l, a * s, b * s)
  where
    search lo hi it
      | it == 0   = lo
      | inGamut (l, a * mid, b * mid) = search mid hi (it - 1)
      | otherwise = search lo mid (it - 1)
      where mid = (lo + hi) / 2

clampL :: Lab -> Lab
clampL (l, a, b) = (max 0 (min 1 l), a, b)

-- | The generation law for complements, byte to byte.
complementOf :: RGB8 -> RGB8
complementOf = oklabToSrgb8 . chromaClamp . comp . srgb8ToOklab

-- ════════════════════════════════════════════════════════════════
-- § 4. STATISTICS — centroid, covariance, Jacobi PCA in OKLab
-- ════════════════════════════════════════════════════════════════

data Stats = Stats
  { stCentroid :: Lab
  , stCov      :: [[Double]]
  , stPCs      :: [(Lab, Double)]   -- (unit direction, eigenvalue), desc
  }

zero3 :: [[Double]]
zero3 = replicate 3 (replicate 3 0)

mkStats :: Lab -> [[Double]] -> Stats
mkStats c cov = Stats c cov pcs
  where
    (vals, vecs) = jacobi3 cov
    pcs = [ (canonDir vec, val) | (val, vec) <- sortOn (Down . fst) (zip vals vecs) ]

-- | Sign canonicalization (the deterministic flicker law,
--   DITHER-NN plan M1): an eigenvector's sign is arbitrary, and a
--   flip relocates the level-1 shell point and permutes ring
--   indices — palette churn with no visual cause. Canonical form:
--   the first component with magnitude above eps is POSITIVE, so
--   the PCA (and therefore the table) is a single-valued function
--   of (centroid, covariance).
canonDir :: Lab -> Lab
canonDir v@(x, y, z)
  | x >  eps  = v
  | x < -eps  = neg
  | y >  eps  = v
  | y < -eps  = neg
  | z >= 0    = v
  | otherwise = neg
  where eps = 1e-9
        neg = (negate x, negate y, negate z)

-- | TOTAL: no samples yields the mid-gray distribution.
analyze :: [RGB8] -> Stats
analyze []  = mkStats (0.5, 0, 0) zero3
analyze cs  = mkStats centroid cov
  where
    labs = map srgb8ToOklab cs
    n = fromIntegral (length labs)
    centroid = ( sum [l | (l, _, _) <- labs] / n
               , sum [a | (_, a, _) <- labs] / n
               , sum [b | (_, _, b) <- labs] / n )
    (cl, ca, cb) = centroid
    devs = [[l - cl, a - ca, b - cb] | (l, a, b) <- labs]
    cov = [[ sum [d !! i * d !! j | d <- devs] / n | j <- [0 .. 2]] | i <- [0 .. 2]]

-- | Warm start: EMA on the STATISTICS, not on colors. The blended
--   distribution re-derives its PCA, so the shell sampler stays a
--   deterministic function of (centroid, covariance).
emaStats :: Double -> Stats -> Stats -> Stats
emaStats alpha s1 s2 = mkStats cBlend covBlend
  where
    lerp x y = alpha * x + (1 - alpha) * y
    (l1, a1, b1) = stCentroid s1
    (l2, a2, b2) = stCentroid s2
    cBlend = (lerp l1 l2, lerp a1 a2, lerp b1 b2)
    covBlend = zipWith (zipWith lerp) (stCov s1) (stCov s2)

guardedStd :: Double -> Double
guardedStd v = max 1e-3 (sqrt (max 0 v))

-- Jacobi eigendecomposition for symmetric 3×3 (port of the
-- Tesseract64 Rust reference). Returns (eigenvalues, eigenvectors).
jacobi3 :: [[Double]] -> ([Double], [Lab])
jacobi3 mat0 = go (50 :: Int) mat0 [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
  where
    finish a v =
      ( [a !! 0 !! 0, a !! 1 !! 1, a !! 2 !! 2]
      , [ (v !! 0 !! i, v !! 1 !! i, v !! 2 !! i) | i <- [0 .. 2] ] )
    go 0 a v = finish a v
    go it a v =
      let (mx, p, q) = maximum [ (abs (a !! i !! j), i, j)
                               | i <- [0 .. 2], j <- [i + 1 .. 2] ]
      in if mx < 1e-12 then finish a v else
        let theta = if abs (a !! p !! p - a !! q !! q) < 1e-15
                      then pi / 4
                      else 0.5 * atan (2 * a !! p !! q / (a !! p !! p - a !! q !! q))
            sn = sin theta; cs = cos theta
            app = cs * cs * a !! p !! p + 2 * sn * cs * a !! p !! q + sn * sn * a !! q !! q
            aqq = sn * sn * a !! p !! p - 2 * sn * cs * a !! p !! q + cs * cs * a !! q !! q
            arp r = cs * a !! r !! p + sn * a !! r !! q
            arq r = negate sn * a !! r !! p + cs * a !! r !! q
            newA i j
              | i == p && j == p = app
              | i == q && j == q = aqq
              | (i == p && j == q) || (i == q && j == p) = 0
              | i == p = arp j
              | j == p = arp i
              | i == q = arq j
              | j == q = arq i
              | otherwise = a !! i !! j
            newV i j
              | j == p = cs * v !! i !! p + sn * v !! i !! q
              | j == q = negate sn * v !! i !! p + cs * v !! i !! q
              | otherwise = v !! i !! j
        in go (it - 1) [[newA i j | j <- [0 .. 2]] | i <- [0 .. 2]]
                       [[newV i j | j <- [0 .. 2]] | i <- [0 .. 2]]

-- ════════════════════════════════════════════════════════════════
-- § 5. THE SOLVER — polar binomial shells → 256-entry table
-- ════════════════════════════════════════════════════════════════

-- | Shell radius in standard deviations: 0, 2/7, 4/7, …, 2.
rho :: Int -> Double
rho k = 2 * fromIntegral k / fromIntegral (nLevels - 1)

-- | Level k, BEFORE clamping: ladder!!k points on the ellipse of
--   radius ρ_k in the PC1×PC2 plane, angles 2πj/n. One formula for
--   every level — ρ_0 = 0 makes level 0 the centroid.
shellRaw :: Stats -> Int -> [Lab]
shellRaw st k =
  [ point (2 * pi * fromIntegral j / fromIntegral n) | j <- [0 .. n - 1] ]
  where
    n = dyadLadder !! k
    (c1, c2, c3) = stCentroid st
    ((d1x, d1y, d1z), v1) = stPCs st !! 0
    ((d2x, d2y, d2z), v2) = stPCs st !! 1
    g1 = guardedStd v1; g2 = guardedStd v2
    r = rho k
    point th =
      ( c1 + r * (cos th * g1 * d1x + sin th * g2 * d2x)
      , c2 + r * (cos th * g1 * d1y + sin th * g2 * d2y)
      , c3 + r * (cos th * g1 * d1z + sin th * g2 * d2z) )

-- | 128 primaries in table order: level k occupies indices
--   [offsets!!k .. offsets!!k + ladder!!k − 1].
primaries :: Stats -> [RGB8]
primaries st =
  [ oklabToSrgb8 (chromaClamp (clampL p)) | k <- [0 .. nLevels - 1], p <- shellRaw st k ]

-- | The full DYAD table: primaries then generated complements,
--   laid out so that T[255−i] = complementOf T[i].
buildDyadFrom :: Stats -> [RGB8]
buildDyadFrom st = prims ++ map complementOf (reverse prims)
  where prims = primaries st

buildDyad :: [RGB8] -> [RGB8]
buildDyad = buildDyadFrom . analyze

-- ════════════════════════════════════════════════════════════════
-- § 6. ROLES — face → primaries; background → σ-mirror bleed to 255
--
-- v2 (the harsh bleed): the background is no longer one flat index.
-- Each background pixel is PULLED toward the centroid by t(d) — a
-- steep curve that saturates inside the bleed band — and assigned
-- the σ-MIRROR of its nearest primary. comp is an isometry of OKLab
-- (negation), so the nearest complement of comp(y) is exactly
-- partner(nearestPrimary(y)): one search serves both roles. A fully
-- pulled pixel IS the centroid, whose nearest primary is index 0,
-- whose partner is 255 — the bleed terminates at the solid by
-- construction, and t ≥ 1 forces it by exact select on any engine.
--
-- v3 (the pair-dither band): the v2 pull stays. In the band
-- (0 < t < 1) the pixel DITHERS between the two sides of its own
-- pair by a Bayer 4×4 ordered threshold on the grid position:
-- coverage t of each tile shows the σ side partner(q), the rest
-- shows the primary side q, where q = nearestPrimary(pulled) is
-- the v2 search unchanged. Endpoints are continuous BY
-- CONSTRUCTION: at t = 0 the whole tile is the primary side (the
-- face's own colors continue past the silhouette — no hue snap);
-- as t → 1 the pull has collapsed the pixel to the centroid, so
-- q → 0 and partner(q) → 255; t ≥ 1 stays the exact far select.
-- ════════════════════════════════════════════════════════════════

tau, bleedWidth, bleedGamma :: Double
tau        = 0.6    -- face threshold on the depth signal
bleedWidth = 0.15   -- depth band over which the background collapses
bleedGamma = 0.5    -- < 1 = harsher initial jump off the silhouette

-- | Pull toward the centroid: 0 at the silhouette, hard 1 at and
--   beyond tau − bleedWidth. Monotone nonincreasing in depth.
pull :: Double -> Double
pull d | d >= tau  = 0
       | otherwise = min 1 ((tau - d) / bleedWidth) ** bleedGamma

-- | The standard Bayer 4×4 thresholds, normalized to the midpoints
--   {0.5/16, 1.5/16, …, 15.5/16}. Fixed constants: the band's pair
--   dither is fully deterministic in the grid position.
bayer4 :: [[Double]]
bayer4 = [ [ (fromIntegral v + 0.5) / 16 | v <- row ]
         | row <- [ [ 0,  8,  2, 10]
                  , [12,  4, 14,  6]
                  , [ 3, 11,  1,  9]
                  , [15,  7, 13,  5] :: [Int] ] ]

dLab2 :: Lab -> Lab -> Double
dLab2 (l1, a1, b1) (l2, a2, b2) =
  (l1 - l2) ^ (2 :: Int) + (a1 - a2) ^ (2 :: Int) + (b1 - b2) ^ (2 :: Int)

-- | Nearest primary in OKLab; tie rule: LOWEST index wins.
nearestPrimaryLab :: [RGB8] -> Lab -> Int
nearestPrimaryLab tbl lc =
  snd (minimum [ (dLab2 (srgb8ToOklab p) lc, j)
               | (j, p) <- zip [0 :: Int ..] (take primaryCount tbl) ])

nearestPrimary :: [RGB8] -> RGB8 -> Int
nearestPrimary tbl = nearestPrimaryLab tbl . srgb8ToOklab

-- | v3 assignment at a grid position: face → nearest primary;
--   far (t ≥ 1) → exactly 255; band → pair dither between q and
--   partner(q) with coverage t under the Bayer threshold.
quantizeDyadAt :: [RGB8] -> Double -> (Int, Int) -> RGB8 -> Int
quantizeDyadAt tbl d (x, y) c
  | d > tau   = nearestPrimaryLab tbl lc
  | t >= 1    = 255
  | bayer4 !! (y `mod` 4) !! (x `mod` 4) < t = partner q
  | otherwise = q
  where
    t = pull d
    lc@(l, a, b) = srgb8ToOklab c
    (cl, ca, cb) = srgb8ToOklab (head tbl)
    pulled = (l + t * (cl - l), a + t * (ca - a), b + t * (cb - b))
    q = nearestPrimaryLab tbl pulled

-- | Position-free compatibility shim: the grid origin, whose Bayer
--   threshold 0.5/16 keeps the σ side for any t above it.
quantizeDyad :: [RGB8] -> Double -> RGB8 -> Int
quantizeDyad tbl d = quantizeDyadAt tbl d (0, 0)

-- ════════════════════════════════════════════════════════════════
-- § 7. DETERMINISTIC TEST INPUTS (no System.Random)
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

-- | Skin-tone-like samples: warm, reddish, moderate lightness
--   (the Tesseract64 synthetic face distribution).
skinColors :: Int -> Int -> [RGB8]
skinColors seed n = take n (go (uniforms seed))
  where
    go (u : v : w : us) = (mk 180 80 u, mk 140 60 v, mk 110 50 w) : go us
    go _ = []
    mk mu range u = max 0 (min 255 (round (mu + (u - 0.5) * range)))

randColors8 :: Int -> Int -> [RGB8]
randColors8 seed n = take n (go (uniforms seed))
  where
    go (u : v : w : us) = (to8 u, to8 v, to8 w) : go us
    go _ = []
    to8 u = min 255 (floor (u * 256))

-- | The constructor must be lawful on ALL of these: no data,
--   collapsed, anchor-extreme, faces, and wild color sets.
sampleSets :: [[RGB8]]
sampleSets =
  [ []                                  -- fully synthetic
  , replicate 40 (128, 128, 128)        -- collapsed mid gray
  , replicate 40 (0, 0, 0)              -- all black
  , replicate 40 (255, 255, 255)        -- all white (achromatic centroid)
  ]
  ++ [skinColors s 324 | s <- [1 .. 8]]
  ++ [randColors8 s 324 | s <- [20 .. 22]]

statsList :: [Stats]
statsList = map analyze sampleSets

allTables :: [[RGB8]]
allTables = map buildDyadFrom (statsList ++ emaBlends)
  where
    emaBlends = [ emaStats a (statsList !! 4) (statsList !! 5)
                | a <- [0, 0.25, 0.5, 0.9] ]

probeColors :: [RGB8]
probeColors = concat sampleSets ++ randColors8 30 200

-- ════════════════════════════════════════════════════════════════
-- § 8. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (DY1) The ladder: Σ = 128, powers of two, level sizes 1,1 then
--       doubling; σ is an involution mapping primaries onto
--       complements exactly.
axiom_DY1 :: Bool
axiom_DY1 =
     sum dyadLadder == primaryCount
  && length dyadLadder == nLevels
  && all (`elem` [1, 2, 4, 8, 16, 32, 64]) dyadLadder
  && take 2 dyadLadder == [1, 1]
  && and (zipWith (\x y -> y == 2 * x) (drop 1 dyadLadder) (drop 2 dyadLadder))
  && last offsets == primaryCount
  && all (\i -> partner (partner i) == i) [0 .. 255]
  && all (\i -> partner i >= 128 && partner i <= 255) [0 .. 127]

-- (DY2) The involution law: in EVERY generated table (including
--       degenerate inputs and EMA blends), T[255−i] is byte-exactly
--       the complement of T[i].
axiom_DY2 :: Bool
axiom_DY2 = all lawful allTables
  where
    lawful t = length t == 256
            && all (\i -> t !! partner i == complementOf (t !! i)) [0 .. 127]

-- (DY3) Comp preserves L exactly and flips hue exactly: the clamped
--       complement is (L, −s·a, −s·b) with s ∈ (0, 1] — colinear
--       with the negated chroma, never longer, never off-hue. Double
--       comp is the identity in continuous OKLab. Achromatic colors
--       are their own complement.
axiom_DY3 :: Bool
axiom_DY3 = all ok probeColors && all doubleComp probeColors
  where
    doubleComp c = let lab = srgb8ToOklab c in comp (comp lab) == lab
    ok c =
      let (l, a, b)    = srgb8ToOklab c
          (l', a', b') = chromaClamp (comp (l, a, b))
          chroma2  = a * a + b * b
          chroma2' = a' * a' + b' * b'
          crossZ   = a' * b - b' * a
          dotC     = a' * a + b' * b
      in l' == l
      && (chroma2 < 1e-12                    -- achromatic: comp = id
           || (dotC <= 0 && abs crossZ <= 1e-9 && chroma2' <= chroma2 + 1e-12))

-- (DY4) Shell law: level sizes equal the ladder, and every RAW
--       shell point sits at whitened radius ρ_k in the PC1×PC2
--       plane with no PC3 component.
axiom_DY4 :: Bool
axiom_DY4 = all sizes statsList && all residency statsList
  where
    sizes st = map (length . shellRaw st) [0 .. nLevels - 1] == dyadLadder
    residency st = and [ radiusOK st k p | k <- [0 .. nLevels - 1], p <- shellRaw st k ]
    radiusOK st k p =
      let (u, v, w) = whiten st p
      in abs (sqrt (u * u + v * v) - rho k) <= 1e-6 && abs w <= 1e-6
    whiten st (x, y, z) =
      let (c1, c2, c3) = stCentroid st
          dc = (x - c1, y - c2, z - c3)
          dot (e1, e2, e3) (f1, f2, f3) = e1 * f1 + e2 * f2 + e3 * f3
          [(dir1, v1), (dir2, v2), (dir3, v3)] = stPCs st
      in ( dot dir1 dc / guardedStd v1
         , dot dir2 dc / guardedStd v2
         , dot dir3 dc / guardedStd v3 )

-- (DY5) Totality and determinism: every sample set (including none)
--       yields a lawful 256-entry byte table, and the constructor is
--       a pure function — the same input builds the same table.
axiom_DY5 :: Bool
axiom_DY5 = all valid allTables && map buildDyad sampleSets == map buildDyad sampleSets
  where
    valid t = length t == 256 && all inRange t
    inRange (r, g, b) = all (\c -> c >= 0 && c <= 255) [r, g, b]

-- (DY6) Role law with the pair-dither band: face pixels land in
--       primaries 0..127; a band pixel is ALWAYS one of the two
--       sides {q, partner q} of its own pair; over a full 4×4 tile
--       the σ-side count equals the number of Bayer thresholds
--       below t — monotone in t, 0 at t = 0, 16 at t ≥ 1; fully
--       pulled background is exactly 255; the pull is monotone in
--       depth and saturates at tau − bleedWidth.
axiom_DY6 :: Bool
axiom_DY6 =
     all (< primaryCount) faceIdx
  && pairLaw
  && tileLaw
  && all (== 255) farIdx
  && monotonePull
  where
    tbl = buildDyad (skinColors 1 324)
    posGrid = [ (x, y) | x <- [0 .. 7], y <- [0 .. 7] ]
    faceIdx = [ quantizeDyadAt tbl 0.9 xy c
              | c <- skinColors 2 25, xy <- [(0, 0), (1, 2), (3, 3), (7, 5)] ]
    farIdx  = [ quantizeDyadAt tbl 0.2 xy c
              | c <- randColors8 33 25, xy <- [(0, 0), (1, 2), (3, 3), (7, 5)] ]
    -- (a) Band indices are the pair of the v2 search, nothing else.
    pairLaw = and
      [ idx == q || idx == partner q
      | c <- randColors8 31 25, xy <- posGrid
      , let idx = quantizeDyadAt tbl 0.55 xy c
      , let q = bandPrimary 0.55 c ]
    bandPrimary d c =
      let t = pull d
          (l, a, b) = srgb8ToOklab c
          (cl, ca, cb) = srgb8ToOklab (head tbl)
      in nearestPrimaryLab tbl (l + t * (cl - l), a + t * (ca - a), b + t * (cb - b))
    -- (b) Tile coverage: depthOf inverts the pull on the band, so
    --     each probe t is realized by an actual depth. σ side ⇔
    --     index ≥ 128 (q < 128, partner q ≥ 128, far = 255).
    depthOf t = tau - bleedWidth * t ** (1 / bleedGamma)
    sigmaCount t = length
      [ () | xy <- [ (x, y) | x <- [0 .. 3], y <- [0 .. 3] ]
           , quantizeDyadAt tbl (depthOf t) xy probe >= 128 ]
    probe = head (randColors8 31 1)
    ts = [fromIntegral k / 20 | k <- [0 .. 20 :: Int]]
    counts = map sigmaCount ts
    tileLaw =
         counts == [ length [ th | th <- concat bayer4, th < t ] | t <- ts ]
      && head counts == 0
      && last counts == 16
      && and (zipWith (<=) counts (tail counts))
    monotonePull =
         and (zipWith (>=) ps (tail ps))
      && pull (tau - bleedWidth) >= 1
      && pull tau == 0
      where ps = [pull (fromIntegral k / 100) | k <- [0 .. 100 :: Int]]

-- (DY7) EMA convexity: blending statistics keeps the centroid an
--       exact convex combination and the covariance positive
--       semidefinite — warm starts can never corrupt the solver.
axiom_DY7 :: Bool
axiom_DY7 = all ok [0, 0.25, 0.5, 0.9, 1]
  where
    s1 = statsList !! 4; s2 = statsList !! 5
    ok alpha =
      let b = emaStats alpha s1 s2
          (l1, a1, b1) = stCentroid s1
          (l2, a2, b2) = stCentroid s2
          lerp x y = alpha * x + (1 - alpha) * y
          (vals, _) = jacobi3 (stCov b)
      in stCentroid b == (lerp l1 l2, lerp a1 a2, lerp b1 b2)
      && all (>= -1e-9) vals

-- (DY8) Canonical signs (the deterministic flicker law): every
--       principal direction's first significant component is
--       positive, in every solved and every blended statistic —
--       the PCA is a single-valued function of (centroid,
--       covariance), so near-equal eigen-solutions cannot flip
--       shells between frames. canonDir itself is idempotent and
--       flip-invariant: v and −v canonicalize identically.
axiom_DY8 :: Bool
axiom_DY8 = all canonical (statsList ++ blends) && all flipFixed probes
  where
    blends = [ emaStats a (statsList !! 4) (statsList !! 5)
             | a <- [0.1, 0.5, 0.9] ]
    canonical st = all (ok . fst) (stPCs st)
    ok (x, y, z)
      | abs x > 1e-9 = x > 0
      | abs y > 1e-9 = y > 0
      | otherwise    = z >= 0
    flipFixed v = canonDir v == canonDir (negV v)
              && canonDir (canonDir v) == canonDir v
      where negV (x, y, z) = (negate x, negate y, negate z)
    probes = triples (map (subtract 0.5) (take 60 (uniforms 40)))
    triples (a : b : c : rest) = (a, b, c) : triples rest
    triples _ = []

-- ════════════════════════════════════════════════════════════════
-- § 9. VISUALIZATION
-- ════════════════════════════════════════════════════════════════

showLadder :: IO ()
showLadder = mapM_ row [0 .. nLevels - 1]
  where
    row k =
      let n  = dyadLadder !! k
          lo = offsets !! k
          hi = lo + n - 1
      in putStrLn $ "  " ++ padL 2 (show k)
                 ++ " │" ++ replicate (max 1 (n `div` 2)) '█'
                 ++ " " ++ padL 2 (show n) ++ ":" ++ show n
                 ++ "   ρ=" ++ showF (rho k)
                 ++ "σ   [" ++ show lo ++ ".." ++ show hi ++ "] : ["
                 ++ show (partner hi) ++ ".." ++ show (partner lo) ++ "]"

hueDeg :: Lab -> Double
hueDeg (_, a, b) = atan2 b a * 180 / pi

-- ════════════════════════════════════════════════════════════════
-- § 10. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " DyadPalette: DYAD-256 — 128 colors and a group action"
  putStrLn " σ(i) = 255−i, T[σ(i)] = comp(T[i]), comp = (L,−a,−b)"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── The Ladder (level │ pairs │ shell radius │ idx : partner idx) ──"
  putStrLn ""
  showLadder
  putStrLn ""
  putStrLn $ "  Σ ladder = " ++ show (sum dyadLadder)
          ++ " primaries; with complements = " ++ show (2 * sum dyadLadder)
  putStrLn ""

  putStrLn "── Reference Construction (324 skin samples, seed 1) ──"
  putStrLn ""
  let st  = analyze (skinColors 1 324)
      tbl = buildDyadFrom st
      showEntry i =
        let c = tbl !! i
            lab@(l, _, _) = srgb8ToOklab c
        in "  T[" ++ padL 3 (show i) ++ "] = " ++ showRGB8 c
        ++ "   L=" ++ showF l ++ "  hue=" ++ padL 8 (showF (hueDeg lab)) ++ "°"
  mapM_ (putStrLn . showEntry) [0, 1, 64, 127, 128, 191, 254, 255]
  putStrLn ""
  putStrLn $ "  face centroid → T[0];  background = T[255] = comp(T[0])"
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "DY1 ladder: Σ=128, doubling, σ involution onto [128..255]" [axiom_DY1]
  check "DY2 involution law: T[255−i] = comp(T[i]) byte-exact"      [axiom_DY2]
  check "DY3 comp: L exact, hue flipped exact, chroma-only clamp"   [axiom_DY3]
  check "DY4 shells: sizes = ladder, whitened radius = ρ_k, PC3=0"  [axiom_DY4]
  check "DY5 totality + determinism on all sample sets"             [axiom_DY5]
  check "DY6 roles: face → 0..127, band pair-dither, 255 far"       [axiom_DY6]
  check "DY7 EMA warm start: convex centroid, PSD covariance"       [axiom_DY7]
  check "DY8 canonical PCA signs: no shell flips between frames"    [axiom_DY8]
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  ladder = [1,1,2,4,8,16,32,64]  Σ = 128;  ×2 by σ = 256."
  putStrLn ""
  putStrLn "  Only 128 colors are ever DESIGNED. The involution"
  putStrLn "  σ(i) = 255−i generates the rest, because hue+180° in"
  putStrLn "  OKLab is linear: comp(L,a,b) = (L,−a,−b). L and chroma"
  putStrLn "  survive; only hue flips. Gamut escapes are clamped by"
  putStrLn "  scaling chroma alone — never L, never hue."
  putStrLn ""
  putStrLn "  The primaries tile the face's OKLab distribution as a"
  putStrLn "  polar binomial disk: 8 concentric PC1×PC2 shells with"
  putStrLn "  1,1,2,4,8,16,32,64 colors at radii 0..2σ. One formula,"
  putStrLn "  deterministic in (centroid, covariance) — warm starts"
  putStrLn "  EMA the statistics, so palettes cannot flicker by"
  putStrLn "  cluster permutation."
  putStrLn ""
  putStrLn "  Faces own the primaries. The background is the face's"
  putStrLn "  σ-mirror: each pixel pulled hard toward the centroid,"
  putStrLn "  assigned partner(nearestPrimary) — a harsh bleed that"
  putStrLn "  terminates, by construction, at 255 = comp(centroid)."
  putStrLn "══════════════════════════════════════════════════════════"

-- Helpers (no-scientific-notation formatter: integer math, 3 dp)
showF :: Double -> String
showF x =
  let n    = round (abs x * 1000) :: Int
      sign = if x < 0 then "-" else ""
      frac = show (n `mod` 1000)
      pad3 = replicate (3 - length frac) '0' ++ frac
  in sign ++ show (n `div` 1000) ++ "." ++ pad3

showRGB8 :: RGB8 -> String
showRGB8 (r, g, b) = "(" ++ padL 3 (show r) ++ "," ++ padL 3 (show g) ++ "," ++ padL 3 (show b) ++ ")"

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let passed = and results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
