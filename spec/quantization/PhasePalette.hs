{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- PhasePalette: the Phase-Diagram Palette Law (PP1–PP16)
--
-- Daniel's ruling (2026-08-10): the background goes to CHAOS, the
-- subject stays in ORDER, and there is a BOUNDARY LAYER; the 256
-- colors of each 64×64 frame must best represent the scene at the
-- 16×16, 32×32, and 64×64 reads. Information theory is the law.
--
-- Design: docs/phase-palette-design.md (defect ledger absorbed;
-- rulings R1–R5 confirmed 2026-08-11). This module is STEP 1:
-- spec only, no Swift. The objects:
--
--   F = D_16 + D_32 + D_64          (equal weights: TL8 ruling)
--
--   PP1 (keystone, exact for ALL fields): with e split into nested
--   orthogonal Haar bands u4 ⊥ u2 ⊥ u1,
--     F = (1/N)(3‖u4‖² + 2‖u2‖² + ‖u1‖²)
--       = (1/N)(‖e‖² + ‖Π₂e‖² + ‖Π₄e‖²)
--   — one derived kernel, exchange rate 3 : 2 : 1, zero knobs.
--
--   ORDER  (t < 1/32):  T = 0 quench — hard nearest assignment.
--   CHAOS  (t > 31/32): max-entropy occupancy per rung-16 block
--          (max log W(n), TL5's multinomial) subject to the pooled
--          read being correct — Jaynes, not aesthetics.
--   BAND   (else): posterior model averaging, realized by the
--          shipped Bayer coverage law (PE7's k/16 dictionary).
--
-- No naked constants: every parameter below is a mixture-fit
-- quantity (τ, s*), a measured moment (λ_max, background moments),
-- an exact combinatorial identity (1/32, ln 81, 16 tiles, 64 =
-- 4³ block, √(5/3) from Zador's 3/5), or the Wada dictionary
-- PRIOR used only on the single-phase fallback path (ruling R2).
--
-- The scale model: the axioms run on an 8³ cube (reads at 2³, 4³,
-- 8³ — the same 2×2×2 pooling tower as 16/32/64 over 64³). Every
-- law below is scale-free; the tower depth (two poolings) is what
-- is proved, and 8³ is the smallest cube carrying it.
-- ════════════════════════════════════════════════════════════════

module PhasePalette where

import Data.List (foldl', minimumBy, sortOn)
import Data.Ord (comparing)

-- ════════════════════════════════════════════════════════════════
-- § 1. DETERMINISTIC INPUTS (house pattern — no System.Random)
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

vAdd :: V3 -> V3 -> V3
vAdd (a, b, c) (d, e, f) = (a + d, b + e, c + f)

vSub :: V3 -> V3 -> V3
vSub (a, b, c) (d, e, f) = (a - d, b - e, c - f)

vScale :: Double -> V3 -> V3
vScale k (a, b, c) = (k * a, k * b, k * c)

vDot :: V3 -> V3 -> Double
vDot (a, b, c) (d, e, f) = a * d + b * e + c * f

vNorm2 :: V3 -> Double
vNorm2 v = vDot v v

vZero :: V3
vZero = (0, 0, 0)

vMean :: [V3] -> V3
vMean [] = vZero
vMean vs = vScale (1 / fromIntegral (length vs)) (foldl' vAdd vZero vs)

-- ════════════════════════════════════════════════════════════════
-- § 2. THE POOLING TOWER AND THE HAAR BANDS (side-8 model cube)
-- ════════════════════════════════════════════════════════════════

side :: Int
side = 8

nVox :: Int
nVox = side * side * side

coords :: [(Int, Int, Int)]
coords = [ (x, y, z) | z <- [0 .. side - 1], y <- [0 .. side - 1], x <- [0 .. side - 1] ]

-- | Π_b: project a field onto b³-block-constant fields (the exact
--   2×2×2 pooling tower composed: b = 2 is one rung, b = 4 is two).
projectBlocks :: Int -> [V3] -> [V3]
projectBlocks b field =
  [ blockMean (bx, by, bz) | (x, y, z) <- coords
  , let bx = x `div` b; by = y `div` b; bz = z `div` b ]
  where
    tagged = zip coords field
    blockMean key = vMean [ v | ((x, y, z), v) <- tagged
                          , (x `div` b, y `div` b, z `div` b) == key ]

-- | D_K of an error field: per-cell mean squared error of the read
--   pooled by factor (side/K). Read K = side is the raw field.
readDistortion :: Int -> [V3] -> Double
readDistortion k field =
  let b = side `div` k
      pooled = projectBlocks b field
  in sum (map vNorm2 pooled) / fromIntegral nVox

-- The three reads of the model cube (2 ↔ rung 16, 4 ↔ 32, 8 ↔ 64).
fTotal :: [V3] -> Double
fTotal e = readDistortion 2 e + readDistortion 4 e + readDistortion 8 e

haarBands :: [V3] -> ([V3], [V3], [V3])   -- (u4, u2, u1)
haarBands e =
  let p4 = projectBlocks 4 e
      p2 = projectBlocks 2 e
      u2 = zipWith vSub p2 p4
      u1 = zipWith vSub e p2
  in (p4, u2, u1)

norm2Field :: [V3] -> Double
norm2Field = sum . map vNorm2

-- Deterministic error fields: white, block-structured, and mixed.
errorFields :: [[V3]]
errorFields =
  [ take nVox (triples (normals s)) | s <- [11, 12, 13] ]
  ++ [ blocky ]
  ++ [ zipWith vAdd blocky (take nVox (triples (map (* 0.3) (normals 14)))) ]
  where
    triples (a : b : c : rest) = (a, b, c) : triples rest
    triples _ = []
    blocky = [ (fromIntegral (x `div` 4) - 0.5, fromIntegral (y `div` 2) * 0.2, 0.1)
             | (x, y, _) <- coords ]

-- ════════════════════════════════════════════════════════════════
-- § 3. THE MIXTURE CLOSED FORMS (DepthMixture's fit, restated)
-- ════════════════════════════════════════════════════════════════

data Mixture = Mixture
  { muF :: Double, muB :: Double, sigma :: Double
  , piF :: Double, piB :: Double }

tauOf :: Mixture -> Double
tauOf m = sigma m * sigma m / (muF m - muB m)

sStarOf :: Mixture -> Double
sStarOf m = (muF m + muB m) / 2 + tauOf m * log (piB m / piF m)

-- | The posterior t(s): σ-side (background) coverage.
posterior :: Mixture -> Double -> Double
posterior m s = 1 / (1 + exp (negate ((sStarOf m - s) / tauOf m)))

-- | 10–90 interface width: τ·ln 81 (exact identity: logistic
--   inversion at 0.1/0.9 gives s* ∓ τ·ln 9; ln 81 = 2·ln 9).
width1090 :: Mixture -> Double
width1090 m = abs (tauOf m) * log 81

-- | Affine reparametrization of the depth signal (a > 0): the fit
--   transforms covariantly, so the posterior is invariant.
affine :: Double -> Double -> Mixture -> Mixture
affine a b m = m { muF = a * muF m + b, muB = a * muB m + b, sigma = a * sigma m }

-- ════════════════════════════════════════════════════════════════
-- § 4. BAYER COVERAGE — the band's lever rule at 16 levels
-- ════════════════════════════════════════════════════════════════

bayer4R :: [[Rational]]
bayer4R = [ [ (fromIntegral v + 1 / 2) / 16 | v <- row ]
          | row <- [ [ 0,  8,  2, 10]
                   , [12,  4, 14,  6]
                   , [ 3, 11,  1,  9]
                   , [15,  7, 13,  5] :: [Int] ] ]

-- | σ-side tiles at coverage t (Rational — exactness is the law).
sigmaTiles :: Rational -> Int
sigmaTiles t = length [ () | row <- bayer4R, th <- row, th < t ]

-- ════════════════════════════════════════════════════════════════
-- § 5. THE QUENCH — Gibbs assignment and its T → 0 limit
-- ════════════════════════════════════════════════════════════════

-- | Soft assignment at temperature T (log-sum-exp shifted).
--   The Gibbs family is the DEFINITION of the soft ensemble; the
--   pooled objective is minimized by the count solver of § 6, not
--   by independent per-voxel sampling (ledger M1).
softAssign :: Double -> [V3] -> V3 -> [Double]
softAssign temp codebook x =
  let d2s = [ vNorm2 (vSub x c) | c <- codebook ]
      dmin = minimum d2s
      ws = [ exp (negate ((d - dmin) / temp)) | d <- d2s ]
      z = sum ws
  in map (/ z) ws

hardAssign :: [V3] -> V3 -> Int
hardAssign codebook x =
  snd (minimum [ (vNorm2 (vSub x c), j) | (j, c) <- zip [0 ..] codebook ])

argmax :: [Double] -> Int
argmax xs = snd (maximum (zip xs [0 ..]))

quenchCodebook :: [V3]
quenchCodebook = take 16 (triples (uniforms 21))
  where
    triples (a : b : c : rest) = (a, b, c) : triples rest
    triples _ = []

quenchProbes :: [V3]
quenchProbes = take 200 (triples (uniforms 22))
  where
    triples (a : b : c : rest) = (a, b, c) : triples rest
    triples _ = []

-- ════════════════════════════════════════════════════════════════
-- § 6. THE CHAOS COUNT SOLVER (rung-16 block law, denominator 64)
--
-- Per block: maximize log W(n) = log(64!/Π n_i!) subject to the
-- pooled mean hitting the target — solved v1-style as the best
-- denominator-64 approximation, ties broken by max log W then
-- lexicographic lowest counts (deterministic, PP14).
-- ════════════════════════════════════════════════════════════════

blockN :: Int
blockN = 64   -- 4³ voxels = TL9's samplesPerJudgment. Combinatorial, not tuned.

logFacts :: [Double]
logFacts = scanl (+) 0 (map (log . fromIntegral) [1 .. blockN])

logW :: [Int] -> Double
logW ns = logFacts !! blockN - sum [ logFacts !! n | n <- ns ]

-- | All count vectors of length k summing to blockN.
compositions :: Int -> Int -> [[Int]]
compositions 1 total = [[total]]
compositions k total =
  [ n : rest | n <- [0 .. total], rest <- compositions (k - 1) (total - n) ]

pooledMean :: [V3] -> [Int] -> V3
pooledMean colors ns =
  vScale (1 / fromIntegral blockN)
         (foldl' vAdd vZero (zipWith (\c n -> vScale (fromIntegral n) c) colors ns))

-- | The v1 solver. Error primary, then −log W, then lex order.
solveCounts :: [V3] -> V3 -> [Int]
solveCounts colors target =
  minimumBy (comparing key) (compositions (length colors) blockN)
  where
    key ns = ( vNorm2 (vSub (pooledMean colors ns) target)
             , negate (logW ns)
             , ns )

-- | The naive-rounding witness: round(64·w) repaired to sum 64.
--   The solver must never do worse (PP9b).
roundWitness :: [Double] -> [Int]
roundWitness ws =
  let raw = map (round . (* fromIntegral blockN)) ws
      deficit = blockN - sum raw
      order = map snd (sortOn (negate . fst) (zip ws [0 :: Int ..]))
      bump 0 ns _ = ns
      bump d ns (j : js) =
        bump (d - signum d) (adjust j (signum d) ns) js
      bump _ ns [] = ns
      adjust j delta ns = [ if i == j then max 0 (n + delta) else n
                          | (i, n) <- zip [0 ..] ns ]
  in bump deficit raw (cycle order)

-- ════════════════════════════════════════════════════════════════
-- § 7. TEMPERATURE PROVENANCE — T_bg = 2·λ_max(C_B), measured
-- ════════════════════════════════════════════════════════════════

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
                     | i == p || j == p = arp (if i == p then j else i)
                     | i == q || j == q = arq (if i == q then j else i)
                     | otherwise = a !! i !! j
            newV r c | c == p = cs * v !! r !! p + sn * v !! r !! q
                     | c == q = negate sn * v !! r !! p + cs * v !! r !! q
                     | otherwise = v !! r !! c
        in go (it - 1) [ [ newA i j | j <- [0 .. 2] ] | i <- [0 .. 2] ]
                       [ [ newV r c | c <- [0 .. 2] ] | r <- [0 .. 2] ]

weightedCov :: [(V3, Double)] -> [[Double]]
weightedCov samples =
  let wTot = sum (map snd samples)
      cen = vScale (1 / wTot) (foldl' vAdd vZero [ vScale w v | (v, w) <- samples ])
      comps (a, b, c) = [a, b, c]
      d v = comps (vSub v cen)
  in [ [ sum [ w * (d v !! i) * (d v !! j) | (v, w) <- samples ] / wTot
       | j <- [0 .. 2] ] | i <- [0 .. 2] ]

tBackground :: [(V3, Double)] -> Double
tBackground samples = 2 * maximum (fst (jacobi3 (weightedCov samples)))

-- ════════════════════════════════════════════════════════════════
-- § 8. ZADOR — the density identity and the class allocation
-- ════════════════════════════════════════════════════════════════

-- | 1-D Gaussian density (the 3-D diagonal case factorizes).
gauss :: Double -> Double -> Double -> Double
gauss mu var x = exp (negate ((x - mu) ^ (2 :: Int)) / (2 * var)) / sqrt (2 * pi * var)

-- | Class allocation share (w = 1; the band weight stays a bound,
--   ledger M9): a_i = (f_i · |C_i|^(1/3))^(3/5), share = normalized.
allocShare :: Double -> Double -> Double -> Double -> Double
allocShare fB detB fS detS =
  let a f det = (f * det ** (1 / 3)) ** (3 / 5)
  in a fB detB / (a fB detB + a fS detS)

-- ════════════════════════════════════════════════════════════════
-- § 9. AERIAL COMPOSITION (DY9 lift; chaos targets on staged labs)
-- ════════════════════════════════════════════════════════════════

gammaAerialR :: Rational -> Rational
gammaAerialR s = 1 / (2 - s)

sigmaCadenceR :: Int -> Rational -> Rational
sigmaCadenceR k s = (fromIntegral (k - 1) / 8) * (2 - s)

stageAerial :: V3 -> Double -> V3 -> V3
stageAerial cF s y = vAdd cF (vScale (1 / (2 - s)) (vSub y cF))

-- ════════════════════════════════════════════════════════════════
-- § 10. THE SCENE-FIT GROUND LAW (PP8) — byte level
--
-- Ruling R2: the partner half is generated by the Wada FAMILY
-- (hue mirror, chroma power law, rigid L-shift) with parameters
-- MOMENT-MATCHED to the capture's own background class — three
-- moments, zero hyperparameters:
--
--   ΔL  = mean L of background − L of centroid
--   βC  = sd(ln C_background) / sd(ln C_primaries)
--   αC  = mean(ln C_background) − βC · mean(ln C_primaries)
--
-- The Wada dictionary constants (scripts/wada/derive.py) demote to
-- the PRIOR used exactly on the single-phase (BIC) fallback path,
-- where the identity cap (ground ≤ figure chroma) also lives —
-- it is the dictionary's ROLE law, not the scene's.
-- ════════════════════════════════════════════════════════════════

type RGB8 = (Int, Int, Int)
type Lab  = (Double, Double, Double)

srgbToLinear :: Double -> Double
srgbToLinear c = if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ** 2.4

linearToSrgb :: Double -> Double
linearToSrgb c = if c <= 0.0031308 then 12.92 * c else 1.055 * c ** (1 / 2.4) - 0.055

cbrt' :: Double -> Double
cbrt' x = if x < 0 then negate (negate x ** (1 / 3)) else x ** (1 / 3)

srgb8ToOklab :: RGB8 -> Lab
srgb8ToOklab (r8, g8, b8) =
  let r = srgbToLinear (fromIntegral r8 / 255)
      g = srgbToLinear (fromIntegral g8 / 255)
      b = srgbToLinear (fromIntegral b8 / 255)
      l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
      m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
      s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
      l' = cbrt' l; m' = cbrt' m; s' = cbrt' s
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

chromaClamp :: Lab -> Lab
chromaClamp lab@(l, a, b)
  | inGamut lab = lab
  | otherwise   = let s = search 0 1 (40 :: Int) in (l, a * s, b * s)
  where
    search lo hi it
      | it == 0   = lo
      | inGamut (l, a * mid, b * mid) = search mid hi (it - 1)
      | otherwise = search lo mid (it - 1)
      where mid = (lo + hi) / 2

clampL :: Lab -> Lab
clampL (l, a, b) = (max 0 (min 1 l), a, b)

-- The Wada dictionary PRIOR (single-phase fallback only; provenance
-- scripts/wada/derive.py — moments of the 1933-34 dictionary).
wadaPriorL, wadaPriorAlphaC, wadaPriorBetaC :: Double
wadaPriorL      = 0.6170482164370319
wadaPriorAlphaC = -1.3176036044137163
wadaPriorBetaC  =  0.7469411483195036

data GroundMoments = GroundMoments
  { gmDeltaL :: Double     -- rigid L-shift (background mean L − centroid L)
  , gmAlphaC :: Double     -- ln-chroma intercept
  , gmBetaC  :: Double     -- ln-chroma slope
  , gmCapped :: Bool       -- identity cap engaged (prior path only)
  } deriving (Eq, Show)

-- | Moment matching — three moments, no hyperparameters. Chromatic
--   samples only enter the chroma fit (C = 0 is the measure-zero
--   achromatic axis, handled exactly in the law itself).
fitGround :: Double -> [Lab] -> [Lab] -> GroundMoments
fitGround centroidL prims bg =
  GroundMoments
    { gmDeltaL = meanOf lOf bg - centroidL
    , gmAlphaC = meanOf lnC bgC - beta * meanOf lnC prC
    , gmBetaC  = beta
    , gmCapped = False }
  where
    lOf (l, _, _) = l
    chroma (_, a, b) = sqrt (a * a + b * b)
    lnC = log . chroma
    prC = filter ((> 0) . chroma) prims
    bgC = filter ((> 0) . chroma) bg
    meanOf f xs = if null xs then 0 else sum (map f xs) / fromIntegral (length xs)
    sdOf f xs = let m = meanOf f xs
                in sqrt (max 0 (meanOf (\x -> (f x - m) ^ (2 :: Int)) xs))
    beta = if null bgC || null prC || sdOf lnC prC <= 0
             then wadaPriorBetaC
             else sdOf lnC bgC / sdOf lnC prC

-- | Single-phase (BIC) fallback: the dictionary prior, cap on.
priorMoments :: Double -> GroundMoments
priorMoments centroidL = GroundMoments
  { gmDeltaL = wadaPriorL - centroidL
  , gmAlphaC = wadaPriorAlphaC
  , gmBetaC  = wadaPriorBetaC
  , gmCapped = True }

groundLab :: GroundMoments -> Lab -> Lab
groundLab gm (l, a, b) =
  let c2 = a * a + b * b
      l' = l + gmDeltaL gm
  in if c2 <= 0 then (l', 0, 0)
     else let c  = sqrt c2
              cRaw = exp (gmAlphaC gm + gmBetaC gm * log c)
              c' = if gmCapped gm then min c cRaw else cRaw
              s  = c' / c
          in (l', negate (a * s), negate (b * s))

groundOf :: GroundMoments -> RGB8 -> RGB8
groundOf gm = oklabToSrgb8 . chromaClamp . clampL . groundLab gm . srgb8ToOklab

-- Deterministic sample ensembles for PP8.
skinColors :: Int -> Int -> [RGB8]
skinColors seed n = take n (go (uniforms seed))
  where
    go (u : v : w : us) = (mk 180 80 u, mk 140 60 v, mk 110 50 w) : go us
    go _ = []
    mk mu range u = max 0 (min 255 (round (mu + (u - 0.5) * range)))

coolColors :: Int -> Int -> [RGB8]
coolColors seed n = take n (go (uniforms seed))
  where
    go (u : v : w : us) = (mk 90 60 u, mk 110 60 v, mk 140 70 w) : go us
    go _ = []
    mk mu range u = max 0 (min 255 (round (mu + (u - 0.5) * range)))

-- ════════════════════════════════════════════════════════════════
-- § 11. AXIOMS PP1–PP16
-- ════════════════════════════════════════════════════════════════

approx :: Double -> Double -> Double -> Bool
approx eps x y = abs (x - y) <= eps

-- (PP1) THE KEYSTONE IDENTITY, exact for ALL fields (ledger M2):
--       D_16+D_32+D_64 = (1/N)(3‖u4‖²+2‖u2‖²+‖u1‖²)
--                      = (1/N)(‖e‖²+‖Π₂e‖²+‖Π₄e‖²),
--       with the Haar bands mutually orthogonal.
axiom_PP1 :: Bool
axiom_PP1 = all ok errorFields
  where
    ok e =
      let (u4, u2, u1) = haarBands e
          lhs = fTotal e
          byBands = (3 * norm2Field u4 + 2 * norm2Field u2 + norm2Field u1)
                      / fromIntegral nVox
          byProj = (norm2Field e + norm2Field (projectBlocks 2 e)
                     + norm2Field (projectBlocks 4 e)) / fromIntegral nVox
          dot f g = sum (zipWith vDot f g)
      in approx 1e-9 lhs byBands && approx 1e-9 lhs byProj
      && approx 1e-9 (dot u4 u2) 0 && approx 1e-9 (dot u4 u1) 0
      && approx 1e-9 (dot u2 u1) 0

-- (PP2) QUENCH LIMIT: the Gibbs assignment at vanishing temperature
--       equals the hard nearest search on every probe without a
--       near-tie (the near-tie clause is the only permitted
--       divergence — ANE fp16 note in the design).
axiom_PP2 :: Bool
axiom_PP2 = all ok (filter noTie quenchProbes)
  where
    noTie x = let ds = sortOn id [ vNorm2 (vSub x c) | c <- quenchCodebook ]
              in case ds of (d0 : d1 : _) -> d1 - d0 > 1e-9; _ -> True
    ok x = argmax (softAssign 1e-6 quenchCodebook x) == hardAssign quenchCodebook x

-- (PP3) CHAOS LIMIT: with only the mass constraint, the max-log-W
--       occupancy is the balanced one (counts differ by ≤ 1), and
--       any unit transfer strictly lowers log W.
axiom_PP3 :: Bool
axiom_PP3 = all ok [2, 3, 5, 7]
  where
    ok k =
      let base = blockN `div` k
          extra = blockN - base * k
          balanced = replicate extra (base + 1) ++ replicate (k - extra) base
          spread = maximum balanced - minimum balanced
          transfers = [ [ n + d i j | (i, n) <- zip [0 ..] balanced ]
                      | j <- [0 .. k - 1], jj <- [0 .. k - 1], j /= jj
                      , let d i _ = if i == j then 1 else if i == jj then -1 else 0
                      , balanced !! jj > 0 ]
          worse ns = all (>= 0) ns && logW ns < logW balanced - 1e-12
                       || maximum ns - minimum ns <= 1   -- transfer between equals: still balanced
      in spread <= 1 && all worse transfers

-- (PP4) TEMPERATURE PROVENANCE: T_bg = 2·λ_max(C_B) from the
--       background-weighted covariance; a pure function (identical
--       recomputation), strictly positive off degeneracy. No other
--       temperature literal exists in this module.
axiom_PP4 :: Bool
axiom_PP4 =
  let samples = [ ((u, v, w), 0.5 + u / 2)
                | (u, v, w) <- take 60 (triples (normals 31)) ]
      t1 = tBackground samples
      t2 = tBackground samples
      triples (a : b : c : rest) = (a, b, c) : triples rest
      triples _ = []
  in t1 == t2 && t1 > 0

-- (PP5) THE COVERAGE LAW (PE7 lift), exact in Rational: σ-side
--       tiles at coverage t = k/16 number exactly k, and the tile
--       expectation is the lever mixture t·c_σ + (1−t)·c_primary.
axiom_PP5 :: Bool
axiom_PP5 = all tileOK [0 .. 16] && all leverOK [0 .. 16]
  where
    tileOK k = sigmaTiles (fromIntegral k / 16) == k
    cSigma = (7, 11, 2) :: (Rational, Rational, Rational)
    cPrim  = (1, 3, 5)  :: (Rational, Rational, Rational)
    leverOK k =
      let t = fromIntegral k / 16 :: Rational
          n = fromIntegral (sigmaTiles t)
          mix3 (a1, a2, a3) (b1, b2, b3) =
            ( (n * a1 + (16 - n) * b1) / 16
            , (n * a2 + (16 - n) * b2) / 16
            , (n * a3 + (16 - n) * b3) / 16 )
          lever (a1, a2, a3) (b1, b2, b3) =
            ( t * a1 + (1 - t) * b1
            , t * a2 + (1 - t) * b2
            , t * a3 + (1 - t) * b3 )
      in mix3 cSigma cPrim == lever cSigma cPrim

-- (PP6) INTERFACE WIDTH: the 10–90 width of the posterior is
--       τ·ln 81 — verified against bisection inversion of the
--       logistic itself, across mixtures.
axiom_PP6 :: Bool
axiom_PP6 = all ok mixtures
  where
    mixtures = [ Mixture 0.8 0.2 s 0.5 0.5 | s <- [0.05, 0.15] ]
            ++ [ Mixture 0.7 0.3 0.1 0.3 0.7 ]
    ok m =
      let sAt p = bisect (\s -> posterior m s - p) (-10) 10 (200 :: Int)
          w = abs (sAt 0.1 - sAt 0.9)
      in approx 1e-9 w (width1090 m)
    bisect f lo hi it
      | it == 0 = (lo + hi) / 2
      | f lo * f mid <= 0 = bisect f lo mid (it - 1)
      | otherwise = bisect f mid hi (it - 1)
      where mid = (lo + hi) / 2

-- (PP7) AFFINE COVARIANCE: any increasing affine reparametrization
--       of the depth signal leaves the posterior — hence band
--       membership, coverage counts, and every emitted index —
--       unchanged; τ and the width transform covariantly.
axiom_PP7 :: Bool
axiom_PP7 = all ok [ (a, b) | a <- [0.5, 2, 17], b <- [-3, 0, 0.4] ]
  where
    m0 = Mixture 0.75 0.25 0.12 0.4 0.6
    grid = [ fromIntegral k / 20 | k <- [0 .. 20 :: Int] ]
    ok (a, b) =
      let m1 = affine a b m0
      in all (\s -> approx 1e-9 (posterior m1 (a * s + b)) (posterior m0 s)) grid
      && approx 1e-9 (tauOf m1) (a * tauOf m0)
      && approx 1e-9 (width1090 m1) (a * width1090 m0)

-- (PP8) TABLE FUNCTIONALITY (ruling R2): the partner half is a pure
--       function of (primaries, three background moments); the
--       single-phase path is a pure function of (primaries, the
--       Wada prior). Determinism byte-exact; achromatic figures map
--       to achromatic grounds at the shifted L, exactly; the
--       scene-fit matches the background's ln-chroma mean on
--       clamp-free ensembles; the prior path alone carries the
--       identity cap.
axiom_PP8 :: Bool
axiom_PP8 = determinism && achromatic && momentMatch && capLaw
  where
    prims = skinColors 1 128
    bg = coolColors 41 200
    primsLab = map srgb8ToOklab prims
    bgLab = map srgb8ToOklab bg
    cL = let (l, _, _) = head primsLab in l
    gm = fitGround cL primsLab bgLab
    gmP = priorMoments cL
    half m = map (groundOf m) prims
    determinism = half gm == half gm && half gmP == half gmP
    achromatic = all achOK [0.2, 0.5, 0.8]
      where achOK l = groundLab gm (l, 0, 0) == (l + gmDeltaL gm, 0, 0)
    chroma (_, a, b) = sqrt (a * a + b * b)
    lnC = log . chroma
    meanOf f xs = sum (map f xs) / fromIntegral (length xs)
    groundsLab = [ groundLab gm lab | lab <- primsLab, chroma lab > 0 ]
    momentMatch = approx 1e-6 (meanOf lnC groundsLab)
                              (meanOf lnC (filter ((> 0) . chroma) bgLab))
    capLaw = not (gmCapped gm) && gmCapped gmP
          && all (\lab -> chroma (groundLab gmP lab) <= chroma lab + 1e-12) primsLab

-- (PP9) CHAOS POOLED FIDELITY at the denominator-64 floor (ledger
--       M6): (a) denominator-64-constructible in-hull targets are
--       met EXACTLY; (b) the solver never does worse than the
--       naive-rounding witness; (c) out-of-hull error equals the
--       plane distance up to the witness floor.
axiom_PP9 :: Bool
axiom_PP9 = exactPart && witnessPart && hullPart
  where
    colors = [ (0.1, 0.2, 0.7), (0.8, 0.1, 0.1), (0.3, 0.9, 0.4) ] :: [V3]
    errAt target = vNorm2 (vSub (pooledMean colors (solveCounts colors target)) target)
    -- (a) constructible targets: counts (a, b, 64−a−b) chosen upfront.
    exactPart = all (\ns -> errAt (pooledMean colors ns) <= 1e-18)
                    [ [10, 20, 34], [0, 64, 0], [63, 1, 0], [21, 21, 22] ]
    -- (b) generic in-hull targets from normalized uniform weights.
    genWeights = [ let [u, v, w] = take 3 (drop (3 * i) (uniforms 51))
                       z = u + v + w
                   in [u / z, v / z, w / z] | i <- [0 .. 3] ]
    inHull ws = foldl' vAdd vZero (zipWith vScale ws colors)
    witnessPart = all
      (\ws -> errAt (inHull ws)
                <= vNorm2 (vSub (pooledMean colors (roundWitness ws)) (inHull ws)) + 1e-15)
      genWeights
    -- (c) offset along the triangle plane's normal from an interior point.
    normal = let (p0 : p1 : p2 : _) = colors
                 (x1, y1, z1) = vSub p1 p0
                 (x2, y2, z2) = vSub p2 p0
                 n = (y1 * z2 - z1 * y2, z1 * x2 - x1 * z2, x1 * y2 - y1 * x2)
             in vScale (1 / sqrt (vNorm2 n)) n
    interior = inHull [0.3, 0.4, 0.3]
    hullPart = all ok [0.05, 0.2]
      where
        ok delta =
          let target = vAdd interior (vScale delta normal)
              e2 = errAt target
              floorE = vNorm2 (vSub (pooledMean colors (roundWitness [0.3, 0.4, 0.3]))
                                    interior)
          in e2 >= delta * delta - 1e-12 && e2 <= delta * delta + floorE + 1e-12

-- (PP10) ANTI-CONCENTRATION (ledger M7, vertex exception explicit):
--        a chaos block whose target is farther from every vertex
--        than the witness floor gets W(n) > 1 (≥ 2 nonzero counts);
--        a vertex target may concentrate (W = 1). log W is the
--        traced entropy-bill ESTIMATE, not the LZW byte count.
axiom_PP10 :: Bool
axiom_PP10 = midEdge && vertexException
  where
    colors = [ (0.1, 0.2, 0.7), (0.8, 0.1, 0.1), (0.3, 0.9, 0.4) ] :: [V3]
    countsFor t = solveCounts colors t
    nonzero ns = length (filter (> 0) ns)
    midEdge = all (\t -> nonzero (countsFor t) >= 2 && logW (countsFor t) > 0)
      [ vScale 0.5 (vAdd (colors !! 0) (colors !! 1))
      , vScale 0.5 (vAdd (colors !! 1) (colors !! 2)) ]
    vertexException =
      let ns = countsFor (colors !! 1)
      in ns == [0, blockN, 0] && logW ns == 0

-- (PP11) SHELL INFLATION (density clause, exact): the Zador density
--        p^(3/5) of N(μ, σ²) is proportional to N(μ, (5/3)σ²) — the
--        ratio is constant over the grid. (The distortion-improvement
--        clause stays CONJ; measured on device at step 5.)
axiom_PP11 :: Bool
axiom_PP11 = all ok [ (0, 1), (0.3, 0.05), (-2, 7) ]
  where
    ok (mu, var) =
      let grid = [ mu + k * sqrt var / 4 | k <- [-8 .. 8] ]
          ratio x = gauss mu var x ** (3 / 5) / gauss mu (5 / 3 * var) x
          rs = map ratio grid
      in maximum rs - minimum rs <= 1e-9 * maximum rs

-- (PP12) ALLOCATION MONOTONICITY: the background's codeword share
--        rises strictly with its mass and covariance volume, and
--        vanishes in the all-subject limit.
axiom_PP12 :: Bool
axiom_PP12 = monoMass && monoVol && limitZero
  where
    grid = [ 0.1, 0.2 .. 0.9 ]
    monoMass = and [ allocShare f 1 (1 - f) 1 < allocShare f' 1 (1 - f') 1
                   | (f, f') <- zip grid (tail grid) ]
    monoVol = and [ allocShare 0.5 d 0.5 1 < allocShare 0.5 d' 0.5 1
                  | (d, d') <- zip grid (tail grid) ]
    limitZero = allocShare 1e-9 1 (1 - 1e-9) 1 < 1e-4

-- (PP13) MASS CONSERVATION (TL3 on the emitted cube): exact Integer
--        lattice sums are invariant under the 2×2×2 pooling tower.
axiom_PP13 :: Bool
axiom_PP13 = all ok [ take nVox (map (`mod` 256) (iterate lcg s)) | s <- [61, 62] ]
  where
    ok cube =
      let total = sum (map fromIntegral cube) :: Integer
          pooledTotal b =
            sum [ sum [ fromIntegral v :: Integer
                      | ((x, y, z), v) <- zip coords cube
                      , (x `div` b, y `div` b, z `div` b) == blk ]
                | blk <- [ (i, j, k) | i <- [0 .. side `div` b - 1]
                         , j <- [0 .. side `div` b - 1]
                         , k <- [0 .. side `div` b - 1] ] ]
      in pooledTotal 2 == total && pooledTotal 4 == total

-- (PP14) DETERMINISM (DY8 lift): solver, ground fit, and pooling
--        are pure — identical recomputation, byte for byte.
axiom_PP14 :: Bool
axiom_PP14 =
  let colors = [ (0.1, 0.2, 0.7), (0.8, 0.1, 0.1), (0.3, 0.9, 0.4) ] :: [V3]
      t = (0.4, 0.35, 0.35)
  in solveCounts colors t == solveCounts colors t
  && fTotal (head errorFields) == fTotal (head errorFields)

-- (PP15) SLOPE ORDERING, exact for ALL fields (projection
--        contraction — a theorem, not a measurement; ledger
--        M5/G12 removed all rate language): D_16 ≤ D_32 ≤ D_64.
axiom_PP15 :: Bool
axiom_PP15 = all ok errorFields
  where
    ok e = readDistortion 2 e <= readDistortion 4 e + 1e-12
        && readDistortion 4 e <= readDistortion 8 e + 1e-12

-- (PP16) AERIAL COMPOSITION: σ(s)·γ(s) = σ_base(K) exact in
--        Rational at every rung and depth (DY9 lift), and staging
--        commutes with pooling on blocks of uniform depth (the
--        chaos target's definition path, pool∘stage, is therefore
--        stage∘pool there — exactly).
axiom_PP16 :: Bool
axiom_PP16 = invariant && commutes
  where
    sGridR = [ fromIntegral n / 20 | n <- [0 .. 20 :: Int] ] :: [Rational]
    invariant = and [ sigmaCadenceR k s * gammaAerialR s == fromIntegral (k - 1) / 8
                    | k <- [64, 32, 16], s <- sGridR ]
    cF = (0.6, 0.05, 0.1) :: V3
    blocks = [ take 8 (drop (8 * i) (triples (uniforms 71))) | i <- [0 .. 2] ]
    triples (a : b : c : rest) = (a, b, c) : triples rest
    triples _ = []
    commutes = all ok [ (blk, s) | blk <- blocks, s <- [0, 0.4, 1] ]
      where
        ok (blk, s) =
          let poolThenStage = stageAerial cF s (vMean blk)
              stageThenPool = vMean (map (stageAerial cF s) blk)
          in vNorm2 (vSub poolThenStage stageThenPool) <= 1e-18

-- ════════════════════════════════════════════════════════════════
-- § 12. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " PhasePalette: order / chaos / boundary — the palette law"
  putStrLn " F = D_16 + D_32 + D_64  =  eᵀ(I + Π₂ + Π₄)e / N"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "PP1  keystone: three reads = 3:2:1 Haar bands, exact"      [axiom_PP1]
  check "PP2  quench: Gibbs T→0 = hard nearest search (no ties)"    [axiom_PP2]
  check "PP3  chaos limit: balanced occupancy maximizes log W"      [axiom_PP3]
  check "PP4  temperature provenance: T_bg = 2·λ_max(C_B), pure"    [axiom_PP4]
  check "PP5  coverage law: k/16 tiles, lever mixture exact (ℚ)"    [axiom_PP5]
  check "PP6  interface width: 10–90 = τ·ln 81, vs bisection"       [axiom_PP6]
  check "PP7  affine covariance: posterior invariant, τ covariant"  [axiom_PP7]
  check "PP8  table functionality: scene-fit / prior, pure, capped" [axiom_PP8]
  check "PP9  pooled fidelity at the denominator-64 floor"          [axiom_PP9]
  check "PP10 anti-concentration, vertex exception explicit"        [axiom_PP10]
  check "PP11 Zador density: p^(3/5) of N(μ,σ²) = N(μ,(5/3)σ²)"     [axiom_PP11]
  check "PP12 allocation monotone in mass and covariance volume"    [axiom_PP12]
  check "PP13 mass conservation: exact sums through the tower"      [axiom_PP13]
  check "PP14 determinism: solver, fit, pooling recompute equal"    [axiom_PP14]
  check "PP15 slope ordering: D_16 ≤ D_32 ≤ D_64, all fields"       [axiom_PP15]
  check "PP16 aerial composition: σ·γ exact; pool∘stage commutes"   [axiom_PP16]
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  ORDER is a crystal: the subject quenches to its nearest"
  putStrLn "  primary at zero temperature — the shipped one-search."
  putStrLn ""
  putStrLn "  CHAOS is an honest gas: the background carries maximal"
  putStrLn "  index entropy under one constraint — the pooled reads"
  putStrLn "  are right. Its colors are mixing vertices; the INDEX"
  putStrLn "  FIELD holds the information."
  putStrLn ""
  putStrLn "  The BOUNDARY is not a third phase: it is the posterior"
  putStrLn "  itself averaging the two, and the Bayer band has been"
  putStrLn "  computing that average all along."
  putStrLn ""
  putStrLn "  Three reads, one kernel: 16, 32, 64 weigh error 3:2:1"
  putStrLn "  by bands — dither is not noise, it is error moved to"
  putStrLn "  where the reads forgive it."

check :: String -> [Bool] -> IO ()
check name results =
  let passed = and results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
