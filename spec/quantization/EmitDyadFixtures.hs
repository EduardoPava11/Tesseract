{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- EmitDyadFixtures: golden fixtures for the Python solver port
--
-- Prints JSON to stdout: named sample sets and the 768-byte DYAD
-- table each produces (hex). The Python port (nn/phase/dyad_solver.py)
-- must reproduce every table BYTE-EXACTLY before any phase sweep may
-- trust it (DITHER-NN plan: "gated byte-exact against spec fixtures").
--
-- Run:  cd spec && runghc -W -package-env=- quantization/EmitDyadFixtures.hs \
--         > ../nn/phase/fixtures.json
--
-- The solver code below is a verbatim copy of DyadPalette.hs §§2–5
-- (house pattern: spec files are standalone). If the two ever drift,
-- the fixtures drift with THIS file — regenerate after any solver
-- change and re-run the Python gate.
-- ════════════════════════════════════════════════════════════════

module EmitDyadFixtures where

import Data.List (sortOn, intercalate)
import Data.Ord (Down(..))

-- ── §2 OKLab (copy) ─────────────────────────────────────────────

type RGB8 = (Int, Int, Int)
type Lab  = (Double, Double, Double)

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

-- ── §3 comp + clamp (copy) ──────────────────────────────────────

comp :: Lab -> Lab
comp (l, a, b) = (l, negate a, negate b)

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

complementOf :: RGB8 -> RGB8
complementOf = oklabToSrgb8 . chromaClamp . comp . srgb8ToOklab

-- ── §4 statistics (copy, incl. DY8 canonDir) ────────────────────

data Stats = Stats { stCentroid :: Lab, stCov :: [[Double]], stPCs :: [(Lab, Double)] }

zero3 :: [[Double]]
zero3 = replicate 3 (replicate 3 0)

canonDir :: Lab -> Lab
canonDir v@(x, y, z)
  | x >  1e-9 = v
  | x < -1e-9 = neg
  | y >  1e-9 = v
  | y < -1e-9 = neg
  | z >= 0    = v
  | otherwise = neg
  where neg = (negate x, negate y, negate z)

mkStats :: Lab -> [[Double]] -> Stats
mkStats c cov = Stats c cov pcs
  where
    (vals, vecs) = jacobi3 cov
    pcs = [ (canonDir vec, val) | (val, vec) <- sortOn (Down . fst) (zip vals vecs) ]

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

guardedStd :: Double -> Double
guardedStd v = max 1e-3 (sqrt (max 0 v))

jacobi3 :: [[Double]] -> ([Double], [Lab])
jacobi3 mat0 = go (50 :: Int) mat0 [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
  where
    finish a v = ( [a !! 0 !! 0, a !! 1 !! 1, a !! 2 !! 2]
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

-- ── §5 solver (copy) ────────────────────────────────────────────

nLevels, primaryCount :: Int
nLevels = 8
primaryCount = 128

dyadLadder :: [Int]
dyadLadder = [1, 1, 2, 4, 8, 16, 32, 64]

rho :: Int -> Double
rho k = 2 * fromIntegral k / fromIntegral (nLevels - 1)

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

primaries :: Stats -> [RGB8]
primaries st =
  [ oklabToSrgb8 (chromaClamp (clampL p)) | k <- [0 .. nLevels - 1], p <- shellRaw st k ]

buildDyadFrom :: Stats -> [RGB8]
buildDyadFrom st = prims ++ map complementOf (reverse prims)
  where prims = primaries st

-- ── deterministic sample sets (copy of the spec's LCG inputs) ───

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

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

fixtureSets :: [(String, [RGB8])]
fixtureSets =
  [ ("empty", [])
  , ("gray", replicate 40 (128, 128, 128))
  , ("black", replicate 40 (0, 0, 0))
  , ("white", replicate 40 (255, 255, 255))
  , ("skin1", skinColors 1 324)
  , ("skin2", skinColors 2 324)
  , ("skin5", skinColors 5 324)
  , ("wild20", randColors8 20 324)
  ]

-- ── JSON emission ───────────────────────────────────────────────

hexByte :: Int -> String
hexByte b = [d (b `div` 16), d (b `mod` 16)]
  where d k = "0123456789abcdef" !! k

tableHex :: [RGB8] -> String
tableHex = concatMap (\(r, g, b) -> hexByte r ++ hexByte g ++ hexByte b)

jsonFixture :: (String, [RGB8]) -> String
jsonFixture (name, samples) =
  "  {\"name\": \"" ++ name ++ "\", \"samples\": ["
    ++ intercalate "," [ "[" ++ show r ++ "," ++ show g ++ "," ++ show b ++ "]"
                       | (r, g, b) <- samples ]
    ++ "], \"table_hex\": \"" ++ tableHex (buildDyadFrom (analyze samples)) ++ "\"}"

main :: IO ()
main = do
  putStrLn "{\"dyad_fixtures_v\": 1, \"fixtures\": ["
  putStrLn (intercalate ",\n" (map jsonFixture fixtureSets))
  putStrLn "]}"
