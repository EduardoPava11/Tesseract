{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- FaceCadence: The Face Mesh IS the Depth Signal
--
-- FACE mode (front camera, ARKit face mesh). No TrueDepth depth
-- map. The anatomical signal replaces it in the same pipeline slot:
--
--   nose = v_{argmax_i z_i}          (topology-independent)
--   R    = max_i ‖v_i − nose‖        (face radius)
--   s_i  = 1 − ‖v_i − nose‖ / R      ∈ [0,1]
--
-- Rasterized to S×S by barycentric interpolation, background = 0.
-- The grid feeds the existing depth slot unchanged:
--   σ(s) = σ_base × (2 − s)          (ContinuousDepthCadence)
-- Nose (s=1) locks crisply to its epoch. Background (s=0) diffuses.
--
-- The rasterizer here is the GOLDEN REFERENCE the Swift port must
-- match bit-for-bit in its decisions (edge rule, tie rules).
-- ════════════════════════════════════════════════════════════════

module FaceCadence where

import Data.List (foldl', maximumBy)
import Data.Ord  (comparing)

-- ════════════════════════════════════════════════════════════════
-- § 1. TYPES
-- ════════════════════════════════════════════════════════════════

-- Face-local meters. +z points OUT of the face (toward camera).
type V3   = (Double, Double, Double)
type Tri  = (Int, Int, Int)          -- indices into the vertex list
data Mesh = Mesh { mVerts :: [V3], mTris :: [Tri] }

type Signal = Double                 -- [0,1]: 1 = nose (near), 0 = background (far)
type Grid   = [[Signal]]             -- S rows × S cols, row-major

gridS :: Int
gridS = 16                            -- reference raster size for the spec

-- ════════════════════════════════════════════════════════════════
-- § 2. THE ANATOMICAL SIGNAL
-- ════════════════════════════════════════════════════════════════

epsR :: Double
epsR = 1e-12

dist :: V3 -> V3 -> Double
dist (ax,ay,az) (bx,by,bz) = sqrt ((ax-bx)^(2::Int) + (ay-by)^(2::Int) + (az-bz)^(2::Int))

-- | Nose tip = vertex with maximal z. Tie rule: FIRST index among
--   equal maxima (Swift port must use the same tie rule).
noseIndex :: Mesh -> Int
noseIndex (Mesh vs _) = snd $ foldl' pick (zHead, 0) (zip (map zOf vs) [0..])
  where
    zOf (_,_,z) = z
    zHead = zOf (head vs)
    pick (bz, bi) (z, i) = if z > bz then (z, i) else (bz, bi)

-- | Face radius R = max distance from nose to any vertex.
faceRadius :: Mesh -> Double
faceRadius m@(Mesh vs _) = maximum [dist v nose | v <- vs]
  where nose = mVerts m !! noseIndex m

-- | Per-vertex anatomical signal.
--   DEGENERATE GUARD: if R ≈ 0 (all vertices coincident) every
--   signal is defined as 1. No NaN ever leaves this function.
signals :: Mesh -> [Signal]
signals m@(Mesh vs _) =
  let nose = vs !! noseIndex m
      r    = faceRadius m
  in if r < epsR
       then map (const 1.0) vs
       else [1.0 - dist v nose / r | v <- vs]

-- ════════════════════════════════════════════════════════════════
-- § 3. THE REFERENCE RASTERIZER (golden for the Swift port)
--
-- Projection: orthographic, drop z. The xy bounding box of the
-- mesh maps to [0,S]×[0,S]. Pixel (row j, col i) samples at center
-- (i+0.5, j+0.5); col i = +x direction, row j = +y direction.
-- (Any screen-space flip in Swift must happen AFTER matching this.)
--
-- Coverage: closed triangle. Pixel center p is covered by (a,b,c)
-- iff all three normalized barycentric coords λ ≥ 0, where
-- λk = wk / area2 with signed edge functions — dividing by the
-- SIGNED doubled area makes the rule winding-independent.
-- Zero-area triangles (|area2| < 1e-12) cover nothing.
-- Overlap tie rule: FIRST triangle in index-list order wins.
-- Uncovered pixels are exactly 0.0.
-- ════════════════════════════════════════════════════════════════

edgeFn :: (Double,Double) -> (Double,Double) -> (Double,Double) -> Double
edgeFn (ax,ay) (bx,by) (px,py) = (bx-ax)*(py-ay) - (by-ay)*(px-ax)

-- | Barycentric coords of p in triangle (a,b,c), Nothing if degenerate.
bary :: (Double,Double) -> (Double,Double) -> (Double,Double)
     -> (Double,Double) -> Maybe (Double,Double,Double)
bary a b c p =
  let area2 = edgeFn a b c
  in if abs area2 < 1e-12
       then Nothing
       else let l0 = edgeFn b c p / area2
                l1 = edgeFn c a p / area2
                l2 = edgeFn a b p / area2
            in Just (l0, l1, l2)

covered :: (Double,Double,Double) -> Bool
covered (l0,l1,l2) = l0 >= 0 && l1 >= 0 && l2 >= 0

-- | xy bounding box → pixel space [0,S]. Degenerate extents guard.
toPixelSpace :: Int -> [V3] -> (V3 -> (Double,Double))
toPixelSpace s vs =
  let xs = [x | (x,_,_) <- vs]
      ys = [y | (_,y,_) <- vs]
      (x0, x1) = (minimum xs, maximum xs)
      (y0, y1) = (minimum ys, maximum ys)
      sf  = fromIntegral s
      spanOr1 lo hi = if hi - lo < epsR then 1.0 else hi - lo
  in \(x,y,_) -> ( (x - x0) / spanOr1 x0 x1 * sf
                 , (y - y0) / spanOr1 y0 y1 * sf )

-- | Rasterize the anatomical signal to an S×S grid.
--   Overlapping triangles combine via MAX — order-independent, and at
--   projection folds the surface nearer the nose wins (the natural
--   occlusion proxy for a selfie). On a genuinely shared edge both
--   triangles interpolate the same value, so max is harmless there.
--   Returns (grid, perPixelWitness) where the witness records the
--   triangle that PRODUCED the max (Nothing = background) — the pixel
--   value is exactly that triangle's interpolation, so the FC5
--   barycentric bound is checked against the witness triangle.
rasterize :: Int -> Mesh -> (Grid, [[Maybe Tri]])
rasterize s m@(Mesh vs tris) =
  let sig  = signals m
      proj = toPixelSpace s vs
      pvs  = map proj vs
      pixel j i =
        let p = (fromIntegral i + 0.5, fromIntegral j + 0.5)
            hits = allCovers p tris
        in case hits of
             [] -> (0.0, Nothing)
             _  -> let (v, t) = maximumBy (comparing fst)
                         [ ( l0 * (sig !! ia) + l1 * (sig !! ib) + l2 * (sig !! ic)
                           , t' )
                         | (t'@(ia,ib,ic), (l0,l1,l2)) <- hits ]
                   in (v, Just t)
      allCovers p ts =
        [ (t, ls)
        | t@(ia,ib,ic) <- ts
        , Just ls <- [bary (pvs !! ia) (pvs !! ib) (pvs !! ic) p]
        , covered ls ]
      rows = [ [ pixel j i | i <- [0 .. s-1] ] | j <- [0 .. s-1] ]
  in (map (map fst) rows, map (map snd) rows)

-- ════════════════════════════════════════════════════════════════
-- § 4. THE CADENCE SLOT (reused verbatim from ContinuousDepthCadence)
-- ════════════════════════════════════════════════════════════════

frameK :: Int
frameK = 64

sigmaBase :: Double
sigmaBase = fromIntegral (frameK - 1) / 8.0   -- 7.875

sigma :: Signal -> Double
sigma s = sigmaBase * (2.0 - s)

-- ════════════════════════════════════════════════════════════════
-- § 5. DETERMINISTIC PSEUDO-RANDOM MESHES (no System.Random)
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

-- | Infinite uniform [0,1) stream from a seed.
uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

-- | Random face-scale mesh: 4..12 vertices in an 16cm box,
--   z in [0, 5cm], with nV random triangles (distinct indices).
randomMesh :: Int -> Mesh
randomMesh seed =
  let us   = uniforms seed
      nV   = 4 + floor (head us * 9)
      coords = take (3 * nV) (tail us)
      vert k = let [ux,uy,uz] = take 3 (drop (3*k) coords)
               in (ux * 0.16 - 0.08, uy * 0.16 - 0.08, uz * 0.05)
      vs   = [vert k | k <- [0 .. nV-1]]
      tus  = drop (3 * nV + 1) us
      tri k = let [ta,tb,tc] = take 3 (drop (3*k) tus)
                  ia = floor (ta * fromIntegral nV)
                  ib = floor (tb * fromIntegral nV)
                  ic = floor (tc * fromIntegral nV)
              in (ia, ib, ic)
      distinct (a,b,c) = a /= b && b /= c && a /= c
      tris = take nV (filter distinct [tri k | k <- [0 .. 4*nV]])
  in Mesh vs tris

testSeeds :: [Int]
testSeeds = [1 .. 100]

rasterSeeds :: [Int]
rasterSeeds = [1 .. 20]

-- | Canonical demo mesh: a nose pyramid. Apex 3cm out of the face
--   plane, square base of 4 triangles fanning to the apex, plus a
--   rim of 4 vertices outside every triangle — they widen the xy
--   bounding box so the raster shows true background (= 0) pixels.
nosePyramid :: Mesh
nosePyramid = Mesh
  [ ( 0.00,  0.00, 0.030)   -- 0: nose tip
  , (-0.06, -0.06, 0.000)   -- 1
  , ( 0.06, -0.06, 0.000)   -- 2
  , ( 0.06,  0.06, 0.000)   -- 3
  , (-0.06,  0.06, 0.000)   -- 4
  , (-0.10, -0.10, 0.000)   -- 5: rim (uncovered)
  , ( 0.10, -0.10, 0.000)   -- 6: rim
  , ( 0.10,  0.10, 0.000)   -- 7: rim
  , (-0.10,  0.10, 0.000) ] -- 8: rim
  [ (0,1,2), (0,2,3), (0,3,4), (0,4,1) ]

-- | All-coincident mesh: the R = 0 degenerate case.
coincidentMesh :: Mesh
coincidentMesh = Mesh (replicate 5 (0.01, -0.02, 0.03)) [(0,1,2), (2,3,4)]

-- ════════════════════════════════════════════════════════════════
-- § 6. AXIOMS
-- ════════════════════════════════════════════════════════════════

eps :: Double
eps = 1e-9

allMeshes :: [Mesh]
allMeshes = nosePyramid : map randomMesh testSeeds

allRasters :: [(Mesh, Grid, [[Maybe Tri]])]
allRasters = [ let (g, w) = rasterize gridS m in (m, g, w)
             | m <- nosePyramid : map randomMesh rasterSeeds ]

-- (FC1) Nose anchor: s at the nose vertex = 1 exactly.
axiom_FC1 :: Bool
axiom_FC1 = all (\m -> abs (signals m !! noseIndex m - 1.0) < eps) allMeshes

-- (FC2) Boundedness: every vertex signal AND every rasterized pixel ∈ [0,1].
axiom_FC2 :: Bool
axiom_FC2 = all (\m -> all inUnit (signals m)) allMeshes
         && all (\(_, g, _) -> all (all inUnit) g) allRasters
  where inUnit s = s >= -eps && s <= 1.0 + eps

-- (FC3) Monotone: s strictly decreasing in ‖v − nose‖;
--       equal distances ⇒ equal signal.
axiom_FC3 :: Bool
axiom_FC3 = all check allMeshes
  where
    check m =
      let nose = mVerts m !! noseIndex m
          ds   = [dist v nose | v <- mVerts m]
          ss   = signals m
          pairs = [ (d1, s1, d2, s2)
                  | ((d1,s1), (d2,s2)) <- allPairs (zip ds ss) ]
      in all ordered pairs
    ordered (d1, s1, d2, s2)
      | abs (d1 - d2) < eps = abs (s1 - s2) < eps
      | d1 < d2             = s1 > s2
      | otherwise           = s1 < s2
    allPairs xs = [(a, b) | (i, a) <- zip [0::Int ..] xs
                          , (j, b) <- zip [0..] xs, i < j]

-- (FC4) Scale invariance: v ↦ o + λ(v − o), λ > 0, any origin o,
--       leaves every s_i unchanged.
axiom_FC4 :: Bool
axiom_FC4 = all check [ (m, l, o) | m <- allMeshes
                                  , l <- [0.5, 2.0, 17.3]
                                  , o <- [(0,0,0), (0.1,-0.2,0.05)] ]
  where
    check (m, l, (ox,oy,oz)) =
      let scaleV (x,y,z) = (ox + l*(x-ox), oy + l*(y-oy), oz + l*(z-oz))
          m' = m { mVerts = map scaleV (mVerts m) }
      in and (zipWith (\a b -> abs (a - b) < 1e-6) (signals m) (signals m'))

-- (FC5) Barycentric bound: a pixel covered by triangle (a,b,c)
--       lies in [min(s_a,s_b,s_c), max(s_a,s_b,s_c)].
axiom_FC5 :: Bool
axiom_FC5 = all check allRasters
  where
    check (m, g, w) =
      let sig = signals m
          ok val (ia,ib,ic) =
            let vs3 = [sig !! ia, sig !! ib, sig !! ic]
            in val >= minimum vs3 - eps && val <= maximum vs3 + eps
      in and [ maybe True (ok val) mt
             | (row, wrow) <- zip g w, (val, mt) <- zip row wrow ]

-- (FC6) Background: pixels covered by no triangle are exactly 0.
axiom_FC6 :: Bool
axiom_FC6 = all check allRasters
  where
    check (_, g, w) =
      and [ case mt of Nothing -> val == 0.0; Just _ -> True
          | (row, wrow) <- zip g w, (val, mt) <- zip row wrow ]

-- (FC7) Cadence reuse: σ(s) = σ_base × (2 − s) with σ_base = (K−1)/8,
--       K = 64, satisfies the ContinuousDepthCadence bounds on the
--       signal's domain: σ ∈ [σ_base, 2σ_base], monotone decreasing.
axiom_FC7 :: Bool
axiom_FC7 =
     abs (sigmaBase - 7.875) < eps
  && abs (sigma 1.0 - sigmaBase) < eps          -- nose: CD1
  && abs (sigma 0.0 - 2.0 * sigmaBase) < eps    -- background: CD2
  && all (\s -> sigma s >= sigmaBase - eps
             && sigma s <= 2.0 * sigmaBase + eps) samples
  && and [ sigma a > sigma b | (a, b) <- zip samples (tail samples) ]
  where samples = [0.0, 0.1 .. 1.0]

-- (FC8) Degenerate guard: R = 0 (all vertices coincident) ⇒
--       every s_i = 1 exactly, no NaN anywhere.
axiom_FC8 :: Bool
axiom_FC8 =
  let ss = signals coincidentMesh
  in all (\s -> not (isNaN s) && abs (s - 1.0) < eps) ss

-- ════════════════════════════════════════════════════════════════
-- § 7. VISUALIZATION
-- ════════════════════════════════════════════════════════════════

shade :: Signal -> Char
shade s
  | s <= 0.0  = '·'
  | s < 0.25  = '░'
  | s < 0.5   = '▒'
  | s < 0.75  = '▓'
  | otherwise = '█'

showGrid :: Grid -> IO ()
showGrid g = mapM_ (putStrLn . ("  " ++) . map shade) (reverse g)
  -- reverse: +y (row index) printed upward, matching face-local axes

-- ════════════════════════════════════════════════════════════════
-- § 8. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " FaceCadence: The Face Mesh IS the Depth Signal"
  putStrLn " s = 1 − ‖v − nose‖/R.  σ(s) = σ_base × (2 − s)."
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── The Signal on the Nose Pyramid ──"
  putStrLn ""
  let sig = signals nosePyramid
  putStrLn $ "  nose index   = " ++ show (noseIndex nosePyramid)
  putStrLn $ "  face radius  = " ++ showF (faceRadius nosePyramid) ++ " m"
  putStrLn $ "  s(nose)      = " ++ showF (sig !! 0)
  putStrLn $ "  s(base)      = " ++ showF (sig !! 1) ++ " (all four base corners equal)"
  putStrLn $ "  s(rim)       = " ++ showF (sig !! 5) ++ " (farthest vertices)"
  putStrLn ""

  putStrLn $ "── Rasterized " ++ show gridS ++ "×" ++ show gridS
          ++ " (█=nose-near, ·=background) ──"
  putStrLn ""
  let (g, _) = rasterize gridS nosePyramid
  showGrid g
  putStrLn ""

  putStrLn "── The Cadence Slot (unchanged from ContinuousDepthCadence) ──"
  putStrLn ""
  putStrLn $ "  σ_base = (K−1)/8 = " ++ showF sigmaBase ++ "  (K = " ++ show frameK ++ ")"
  putStrLn $ "  σ(s=1.0) = " ++ showF (sigma 1.0) ++ "  nose → crisp epoch lock"
  putStrLn $ "  σ(s=0.5) = " ++ showF (sigma 0.5) ++ "  mid-face"
  putStrLn $ "  σ(s=0.0) = " ++ showF (sigma 0.0) ++ "  background → diffuse"
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "FC1 nose anchor: s(nose) = 1 exactly"                    [axiom_FC1]
  check "FC2 boundedness: signals & pixels ∈ [0,1]"               [axiom_FC2]
  check "FC3 monotone: s strictly decreasing in ‖v−nose‖"         [axiom_FC3]
  check "FC4 scale invariance: λ·(mesh) leaves s unchanged"       [axiom_FC4]
  check "FC5 barycentric bound: pixel ∈ [min s, max s] of tri"    [axiom_FC5]
  check "FC6 background pixels are exactly 0"                     [axiom_FC6]
  check "FC7 cadence reuse: σ ∈ [σ_base, 2σ_base], decreasing"    [axiom_FC7]
  check "FC8 degenerate R=0 ⇒ all s = 1, no NaN"                  [axiom_FC8]
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  mesh → nose = argmax z → s = 1 − d/R → raster → depth slot"
  putStrLn ""
  putStrLn "  FACE mode needs no TrueDepth. The mesh IS the depth."
  putStrLn "  Nose = 1 locks its epoch. Background = 0 diffuses."
  putStrLn "  Scale-free: the same face at any distance, same signal."
  putStrLn "  σ(s) = σ_base × (2 − s), verbatim. The slot is unchanged."
  putStrLn ""
  putStrLn "  Swift port MUST match the reference rasterizer:"
  putStrLn "    · nose tie rule: first index among equal max z"
  putStrLn "    · closed-triangle rule: all normalized λ ≥ 0"
  putStrLn "    · winding-independent (divide by signed area)"
  putStrLn "    · zero-area triangles cover nothing"
  putStrLn "    · overlap: MAX of covering triangles (order-independent;"
  putStrLn "      near-nose wins at projection folds)"
  putStrLn "══════════════════════════════════════════════════════════"

-- Helpers (no-scientific-notation formatter: integer math, 3 dp)
showF :: Double -> String
showF x =
  let n    = round (abs x * 1000) :: Int
      sign = if x < 0 then "-" else ""
      frac = show (n `mod` 1000)
      pad3 = replicate (3 - length frac) '0' ++ frac
  in sign ++ show (n `div` 1000) ++ "." ++ pad3

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
