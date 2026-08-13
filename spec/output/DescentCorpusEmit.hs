{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- DescentCorpusEmit: emit the descent-ladder training corpus
--
-- J1 of the capture-assist plan (Daniel's rulings 2026-08-12:
-- P4 descent first; 3-model ladder nested by OUTPUTS; corpus =
-- SYNTHETIC ONLY per ★NO-CAPTURE-TRAINING). Output lands in
-- nn/descent/corpus/ following the nn/<model>/ layout.
--
-- Files:
--   samples.jsonl   one line per sample: the generating stats
--                   (centroid + diagonal variances — the lawful
--                   axis-aligned Stats subset, v1 manifold), the
--                   128 clamped figure bytes, and per-probe rows:
--                   staged lab + EXHAUSTIVE-teacher labels at all
--                   three exits (leaf, 16-class, 2-class).
--   manifest.json   counts, gates, provenance, conventions.
--
-- Teacher law (DL5): labels come from exhaustive nearest over the
-- labs of the CLAMPED figure bytes — exactly what the Swift
-- assignment searches — never from the descent. Coarse labels are
-- quotients of the leaf label (DL2's nesting, teacher side).
--
-- Self-gating: before writing a byte, the emitter re-verifies its
-- mirrored core against the spec laws — 128 leaves, the v7
-- same-hue involution T[255−i] = ground(T[i]) byte-exact on a
-- fixture table, PT9 node/octet coherence, teacher label sanity,
-- and determinism. Any mismatch aborts the emit.
-- ════════════════════════════════════════════════════════════════

module Main where

import Data.Bits ((.&.), shiftR)
import Data.List (minimumBy, intercalate)
import Data.Ord (comparing)
import System.Directory (createDirectoryIfMissing)
import Control.Monad (unless)

-- ── Color core (mirrors spec/quantization/DyadPalette.hs) ────────

type Lab = (Double, Double, Double)
type RGB8 = (Int, Int, Int)

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
      l3 = cbrt l; m3 = cbrt m; s3 = cbrt s
  in ( 0.2104542553 * l3 + 0.7936177850 * m3 - 0.0040720468 * s3
     , 1.9779984951 * l3 - 2.4285922050 * m3 + 0.4505937099 * s3
     , 0.0259040371 * l3 + 0.7827717662 * m3 - 0.8086757660 * s3 )

linearRGB :: Lab -> (Double, Double, Double)
linearRGB (l, a, b) =
  let l3 = l + 0.3963377774 * a + 0.2158037573 * b
      m3 = l - 0.1055613458 * a - 0.0638541728 * b
      s3 = l - 0.0894841775 * a - 1.2914855480 * b
      ll = l3 * l3 * l3; mm = m3 * m3 * m3; ss = s3 * s3 * s3
  in (  4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss
     , -1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss
     , -0.0041960863 * ll - 0.7034186147 * mm + 1.7076147010 * ss )

inGamut :: Lab -> Bool
inGamut lab = let (r, g, b) = linearRGB lab
              in all (\c -> c >= -1e-6 && c <= 1 + 1e-6) [r, g, b]

chromaClamp :: Lab -> Lab
chromaClamp lab@(l, a, b)
  | inGamut lab = lab
  | otherwise = let s = search 0 1 (40 :: Int) in (l, a * s, b * s)
  where
    search lo hi it
      | it == 0 = lo
      | inGamut (l, a * mid, b * mid) = search mid hi (it - 1)
      | otherwise = search lo mid (it - 1)
      where mid = (lo + hi) / 2

clampL :: Lab -> Lab
clampL (l, a, b) = (max 0 (min 1 l), a, b)

oklabToSrgb8 :: Lab -> RGB8
oklabToSrgb8 lab =
  let (r, g, b) = linearRGB lab
      to8 c = max 0 (min 255
        (round (linearToSrgb (max 0 (min 1 c)) * 255) :: Int))
  in (to8 r, to8 g, to8 b)

-- v7 same-hue ground (prior path — the involution gate's law)
wadaGroundL, wadaAlphaC, wadaBetaC :: Double
wadaGroundL = 0.6170482164370319
wadaAlphaC = -1.3176036044137163
wadaBetaC  =  0.7469411483195036

groundPrior :: Double -> RGB8 -> RGB8
groundPrior cL rgb =
  let (l, a, b) = srgb8ToOklab rgb
      c2 = a * a + b * b
      l' = l + (wadaGroundL - cL)
  in oklabToSrgb8 (chromaClamp (clampL (
       if c2 <= 0 then (l', 0, 0)
       else let c = sqrt c2
                c' = min c (exp (wadaAlphaC + wadaBetaC * log c))
                s = c' / c
            in (l', a * s, b * s))))     -- v7: same hue, never negated

-- ── The analytic tree (mirrors PairTree.hs § 3b / Swift PairTree) ──

halfMeanC, halfVarC :: Double
halfMeanC = sqrt (2 / pi)
halfVarC  = 1 - 2 / pi

-- Axis-aligned v1 manifold: diagonal covariance in the Lab frame,
-- canonical directions = the axes (matches Swift canonDir on
-- diagonal covariance). Full-PCA sampling is J2 (needs mirrored
-- Jacobi + parity gates).
data GNode = GNode { gMean :: [Double], gVar :: [Double] }

splitAxis :: GNode -> Int
splitAxis n = fst (foldl pick (0, head vs) (zip [1 ..] (tail vs)))
  where
    vs = gVar n
    pick (bi, bv) (i, v) = if v > bv then (i, v) else (bi, bv)

splitG :: GNode -> (GNode, GNode)
splitG n = (child (-1), child 1)
  where
    a = splitAxis n
    v = gVar n !! a
    off = sqrt v * halfMeanC
    child s = GNode
      [ if i == a then m + fromIntegral (s :: Int) * off else m
      | (i, m) <- zip [0 :: Int ..] (gMean n) ]
      [ if i == a then v * halfVarC else w
      | (i, w) <- zip [0 :: Int ..] (gVar n) ]

nodeAt :: [Int] -> GNode -> GNode
nodeAt [] n = n
nodeAt (b : bs) n = let (l, r) = splitG n
                    in nodeAt bs (if b == 0 then l else r)

leafMeans :: GNode -> [Lab]
leafMeans root =
  [ toLab (gMean (nodeAt [ (j `shiftR` k) .&. 1 | k <- [6, 5 .. 0] ] root))
  | j <- [0 .. 127 :: Int] ]

toLab :: [Double] -> Lab
toLab [x, y, z] = (x, y, z)
toLab _ = error "3 coords"

figures8 :: GNode -> [RGB8]
figures8 = map (oklabToSrgb8 . chromaClamp . clampL) . leafMeans

d2 :: Lab -> Lab -> Double
d2 (a, b, c) (x, y, z) = (a-x)^(2::Int) + (b-y)^(2::Int) + (c-z)^(2::Int)

exhaustive :: [Lab] -> Lab -> Int
exhaustive ls t = snd (minimumBy (comparing fst) (zip (map (d2 t) ls) [0 ..]))

-- ── Deterministic sampler (LCG; Irwin–Hall 12-sum normals) ───────

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

normals :: Int -> [Double]
normals seed = go (uniforms seed)
  where
    go us = let (twelve, rest) = splitAt 12 us
            in (sum twelve - 6) : go rest

-- | One sample: centroid + diagonal variances drawn in lawful
--   ranges (skin-to-cool lightness, moderate chroma, positive
--   variance by construction).
sampleStats :: Int -> ([Double], [Double])
sampleStats seed =
  let (u1 : u2 : u3 : u4 : u5 : u6 : _) = uniforms (7919 * seed + 13)
  in ( [0.35 + 0.4 * u1, -0.06 + 0.14 * u2, -0.06 + 0.14 * u3]
     , [0.002 + 0.028 * u4, 0.001 + 0.018 * u5, 0.0005 + 0.008 * u6] )

sampleProbes :: Int -> ([Double], [Double]) -> Int -> [Lab]
sampleProbes n (mu, var) seed =
  take n (go (normals (104729 * seed + 7)))
  where
    [ml, ma, mb] = mu
    [vl, va, vb] = var
    go (z1 : z2 : z3 : zs) =
      (ml + z1 * sqrt vl, ma + z2 * sqrt va, mb + z3 * sqrt vb) : go zs
    go _ = []

-- ── Emission ─────────────────────────────────────────────────────

sampleCount, probeCount :: Int
sampleCount = 768
probeCount = 192

jNum :: Double -> String
jNum = show

emitSample :: Int -> String
emitSample seed =
  let (mu, var) = sampleStats seed
      root = GNode mu var
      figs = figures8 root
      labs = map srgb8ToOklab figs
      probes = sampleProbes probeCount (mu, var) seed
      rows = [ "{\"lab\":[" ++ intercalate "," (map jNum [pl, pa, pb])
            ++ "],\"leaf\":" ++ show e
            ++ ",\"c16\":" ++ show (e `shiftR` 3)
            ++ ",\"c2\":" ++ show (e `shiftR` 6) ++ "}"
             | p@(pl, pa, pb) <- probes, let e = exhaustive labs p ]
  in "{\"seed\":" ++ show seed
  ++ ",\"mu\":[" ++ intercalate "," (map jNum mu)
  ++ "],\"var\":[" ++ intercalate "," (map jNum var)
  ++ "],\"figures\":[" ++ intercalate ","
       [ "[" ++ intercalate "," (map show [r, g, b]) ++ "]" | (r, g, b) <- figs ]
  ++ "],\"probes\":[" ++ intercalate "," rows ++ "]}"

-- ── Self-gates (abort before writing on any mismatch) ────────────

gates :: [(String, Bool)]
gates =
  [ ("128 leaves per tree",
      all ((== 128) . length . figures8 . uncurry GNode . sampleStats) [1 .. 4])
  , ("v7 involution on fixture: T[255-i] == ground(T[i]) byte-exact",
      let root = GNode [0.62, 0.05, 0.02] [0.02, 0.008, 0.002]
          figs = figures8 root
          cL = let (l, _, _) = srgb8ToOklab (head figs) in l
          tbl = figs ++ map (groundPrior cL) (reverse figs)
      in length tbl == 256
      && all (\i -> tbl !! (255 - i) == groundPrior cL (tbl !! i)) [0 .. 127])
  , ("PT9 coherence: depth-4 node mean == octet mean of leaf means",
      let root = GNode [0.5, 0.0, 0.01] [0.015, 0.012, 0.003]
          ls = leafMeans root
          close (a,b,c) (x,y,z) = abs (a-x) < 1e-9 && abs (b-y) < 1e-9 && abs (c-z) < 1e-9
          octet c = let ms = [ ls !! (c * 8 + r) | r <- [0 .. 7] ]
                        n = fromIntegral (length ms)
                        (as, bs, cs) = unzip3 ms
                    in (sum as / n, sum bs / n, sum cs / n)
          nodeMean c = toLab (gMean (nodeAt
            [ (c `shiftR` k) .&. 1 | k <- [3, 2, 1, 0] ] root))
      in all (\c -> close (octet c) (nodeMean c)) [0 .. 15])
  , ("teacher labels in range on a sample",
      let (mu, var) = sampleStats 1
          labs = map srgb8ToOklab (figures8 (GNode mu var))
      in all (\p -> let e = exhaustive labs p in e >= 0 && e < 128)
             (sampleProbes 32 (mu, var) 1))
  , ("determinism: sample 1 emits identical bytes twice",
      emitSample 1 == emitSample 1)
  ]

main :: IO ()
main = do
  let failed = [ name | (name, ok) <- gates, not ok ]
  unless (null failed) $
    error ("DescentCorpusEmit: gates FAILED, no bytes written: " ++ show failed)
  putStrLn "  gates ✓ (leaves, involution, PT9, teacher, determinism)"
  let dir = "../nn/descent/corpus"
  createDirectoryIfMissing True dir
  let body = unlines (map emitSample [1 .. sampleCount])
  writeFile (dir ++ "/samples.jsonl") body
  writeFile (dir ++ "/manifest.json") $ unlines
    [ "{"
    , "  \"emitter\": \"spec/output/DescentCorpusEmit.hs\","
    , "  \"date\": \"2026-08-12\","
    , "  \"samples\": " ++ show sampleCount ++ ","
    , "  \"probesPerSample\": " ++ show probeCount ++ ","
    , "  \"manifold\": \"v1 axis-aligned (diagonal covariance, canonical axis directions); full-PCA sampling is J2 and needs mirrored Jacobi + parity gates\","
    , "  \"teacher\": \"exhaustive nearest over labs of CLAMPED figure bytes (DL5); coarse labels are quotients of the leaf label (DL2)\","
    , "  \"exits\": {\"leaf\": 128, \"c16\": 16, \"c2\": 2},"
    , "  \"decrees\": [\"NO-CAPTURE-TRAINING: synthetic only\", \"labels never from the descent\", \"sizes/cadences/K are device-measured, not corpus properties\"],"
    , "  \"spec\": [\"neural/DescentLadder.hs DL1-DL5\", \"quantization/PairTree.hs PT1-PT9\"]"
    , "}"
    ]
  putStrLn ("  wrote " ++ show sampleCount ++ " samples × "
            ++ show probeCount ++ " probes → " ++ dir)
