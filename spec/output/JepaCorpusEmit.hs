{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- JepaCorpusEmit: emit the JEPA-H trajectory corpus (JH1)
--
-- ONE MODEL LINE (nn/jepa/README.md). Each sample is a CAPTURE: a
-- 16-slot latent ring under the local-level trajectory law
-- (spec/neural/JepaH.hs JH3) in the 6-dim latent (centroid l,a,b +
-- LOG-variances — positive by construction), with observations,
-- true states, AND the 768-byte DYAD table rendered per slot by
-- the single-source Haskell law (analytic tree + v7 prior ground).
-- The lab's python renderer must byte-match these tables before it
-- may render model outputs (the parity bridge).
--
-- Files (nn/jepa/corpus/): trajectories.jsonl + manifest.json.
-- Self-gating before any byte is written.
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


-- ── Trajectory sampler (mirrors JepaH.hs JH3) ────────────────────

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

normals :: Int -> [Double]
normals seed = go (uniforms seed)
  where go us = let (twelve, rest) = splitAt 12 us
                in (sum twelve - 6) : go rest

ringSlots, latentDim :: Int
ringSlots = 16
latentDim = 6

-- lawful base ranges per latent dim: centroid l,a,b then log-vars
dimLo, dimHi :: [Double]
dimLo = [0.35, -0.06, -0.06, log 0.002, log 0.001, log 0.0005]
dimHi = [0.75,  0.08,  0.08, log 0.030, log 0.019, log 0.0085]

-- | One capture: (sigq, sige, states[16][6], obs[16][6]).
-- v2 JUMP LAW: with probability 1/2 a capture carries ONE level
-- shift (a face moving, a crossover drifting -- the events the MS
-- law exists for): at a uniform slot, a uniform subset of dims
-- jumps by U[3,8] drift-sigmas. EMA smears jumps; a learned
-- smoother can snap -- the winnable gap the pure Gaussian lacks.
sampleCapture :: Int -> ([Double], [Double], [[Double]], [[Double]])
sampleCapture seed =
  let us = uniforms (7919 * seed + 101)
      (u0s, rest1) = splitAt latentDim us
      (uq, rest2) = splitAt latentDim rest1
      (ue, rest3) = splitAt latentDim rest2
      (uj : ujslot : rest4) = rest3
      (ujdims, ujmags) = splitAt latentDim (take (2 * latentDim) rest4)
      width d = dimHi !! d - dimLo !! d
      s0 d = dimLo !! d + (u0s !! d) * width d
      sigq d = (0.01 + 0.05 * (uq !! d)) * width d
      sige d = (0.01 + 0.05 * (ue !! d)) * width d
      hasJump = uj < 0.5
      jumpSlot = 1 + floor (ujslot * fromIntegral (ringSlots - 1))
      jumpAmt d = if hasJump && ujdims !! d < 0.5
                    then (3 + 5 * ujmags !! d) * sigq d
                         * (if ujmags !! d < 0.5 then 1 else -1)
                    else 0
      traj d = let es = normals (97 * seed + 3 * d + 1)
                   vs = normals (97 * seed + 3 * d + 2)
                   base = take ringSlots (scanl (\s e -> s + sigq d * e) (s0 d) es)
                   sts = [ x + (if t >= jumpSlot then jumpAmt d else 0)
                         | (t, x) <- zip [0 ..] base ]
                   ob = zipWith (\s v -> s + sige d * v) sts (take ringSlots vs)
               in (sts, ob)
      per = [ traj d | d <- [0 .. latentDim - 1] ]
      states = [ [ fst (per !! d) !! t | d <- [0 .. latentDim - 1] ]
               | t <- [0 .. ringSlots - 1] ]
      obs = [ [ snd (per !! d) !! t | d <- [0 .. latentDim - 1] ]
            | t <- [0 .. ringSlots - 1] ]
  in ( map sigq [0 .. latentDim - 1], map sige [0 .. latentDim - 1]
     , states, obs )

-- ── State → 768-byte table (the single-source law) ──────────────

tableOf :: [Double] -> [Int]
tableOf [l, a, b, lvl, lva, lvb] =
  let root = GNode [l, a, b] [exp lvl, exp lva, exp lvb]
      figs = figures8 root
      cL = let (ll, _, _) = srgb8ToOklab (head figs) in ll
      tbl = figs ++ map (groundPrior cL) (reverse figs)
  in concat [ [r, g, bb] | (r, g, bb) <- tbl ]
tableOf _ = error "6 dims"

-- ── Emission ─────────────────────────────────────────────────────

captureCount :: Int
captureCount = 1024

jNum :: Double -> String
jNum = show

emitCapture :: Int -> String
emitCapture seed =
  let (sq, se, states, obs) = sampleCapture seed
      jv xs = "[" ++ intercalate "," (map jNum xs) ++ "]"
      jvv xss = "[" ++ intercalate "," (map jv xss) ++ "]"
      jtbl st = "[" ++ intercalate "," (map show (tableOf st)) ++ "]"
  in "{\"seed\":" ++ show seed
  ++ ",\"sigq\":" ++ jv sq ++ ",\"sige\":" ++ jv se
  ++ ",\"states\":" ++ jvv states
  ++ ",\"obs\":" ++ jvv obs
  ++ ",\"tables\":[" ++ intercalate "," (map jtbl states) ++ "]}"

gates :: [(String, Bool)]
gates =
  [ ("determinism", emitCapture 1 == emitCapture 1)
  , ("positivity: log-space variances exponentiate positive",
      let (_, _, sts, _) = sampleCapture 2
      in all (\st -> all (> 0) [ exp v | v <- drop 3 st ]) sts)
  , ("ring shape 16 x 6",
      let (_, _, sts, ob) = sampleCapture 3
      in length sts == ringSlots && all ((== latentDim) . length) sts
      && length ob == ringSlots)
  , ("v7 involution inside every emitted slot-0 table",
      let (_, _, sts, _) = sampleCapture 4
          t = tableOf (head sts)
          entry i = (t !! (3 * i), t !! (3 * i + 1), t !! (3 * i + 2))
          cL = let (ll, _, _) = srgb8ToOklab (entry 0) in ll
      in length t == 768
      && all (\i -> entry (255 - i) == groundPrior cL (entry i)) [0 .. 127])
  , ("PT9 coherence on a trajectory tree",
      let (_, _, sts, _) = sampleCapture 5
          [l, a, b, lvl, lva, lvb] = head sts
          root = GNode [l, a, b] [exp lvl, exp lva, exp lvb]
          ls = leafMeans root
          close (x1,y1,z1) (x2,y2,z2) =
            abs (x1-x2) < 1e-9 && abs (y1-y2) < 1e-9 && abs (z1-z2) < 1e-9
          octet c = let ms = [ ls !! (c * 8 + r) | r <- [0 .. 7] ]
                        n = fromIntegral (length ms)
                        (as, bs, cs) = unzip3 ms
                    in (sum as / n, sum bs / n, sum cs / n)
          nodeMean c = toLab (gMean (nodeAt
            [ (c `shiftR` k) .&. 1 | k <- [3, 2, 1, 0] ] root))
      in all (\c -> close (octet c) (nodeMean c)) [0 .. 15])
  ]

main :: IO ()
main = do
  let failed = [ name | (name, ok) <- gates, not ok ]
  unless (null failed) $
    error ("JepaCorpusEmit: gates FAILED, no bytes written: " ++ show failed)
  putStrLn "  gates ✓ (determinism, positivity, ring, involution, PT9)"
  let dir = "../nn/jepa/corpus"
  createDirectoryIfMissing True dir
  writeFile (dir ++ "/trajectories.jsonl")
    (unlines (map emitCapture [1 .. captureCount]))
  writeFile (dir ++ "/manifest.json") $ unlines
    [ "{"
    , "  \"emitter\": \"spec/output/JepaCorpusEmit.hs\","
    , "  \"date\": \"2026-08-12\","
    , "  \"captures\": " ++ show captureCount ++ ","
    , "  \"ringSlots\": 16, \"latentDim\": 6,"
    , "  \"law\": \"local-level (JepaH.hs JH3) + v2 jump law (p=1/2 one level shift, U[3,8] drift-sigmas, uniform slot/dims) in centroid+log-variance space; tables per slot from the analytic tree + v7 prior ground (single-source)\","
    , "  \"decrees\": [\"NO-CAPTURE-TRAINING: synthetic only\", \"one model line\", \"beauty gates promote\"],"
    , "  \"spec\": [\"neural/JepaH.hs JH1-JH6\"]"
    , "}"
    ]
  putStrLn ("  wrote " ++ show captureCount ++ " capture rings -> " ++ dir)
