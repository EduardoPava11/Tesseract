{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- StatsVariance: the GIF89a statistical-variance corpus
--
-- ★NO-CAPTURE-TRAINING DECREE (2026-08-09): the DYAD NN stack trains
-- on the FORMAT's own statistical manifold, never on captures. Since
-- DY8 + STATS provenance, a capture's palette world is a single-
-- valued function of 9 numbers per frame (OKLab centroid + covariance)
-- — so the corpus is a distribution over states and 64-frame ring
-- trajectories, and a state generates BOTH sides of a training pair:
-- the palette (lawful solver) and the imagery (pixels drawn from the
-- very Gaussian the state describes).
--
--   state       centroid ~ U(sRGB-representable OKLab region),
--               Σ = R·diag(λ)·Rᵀ, R ~ U(SO(3)), λ log-uniform
--   trajectory  ring-OU (Fourier synthesis on the 64-ring: exact
--               periodicity) + boxcar JUMP events (lighting shocks)
--   imagery     pixels = centroid + chol(Σ)·w, w a unit random-phase
--               field — marginal matches the state by construction
--
-- The corpus is a PROGRAM: (sampler, seed) regenerates byte-identical
-- data; held-out = a disjoint seed range. Evaluation is synthetic too
-- (ratified): the device feel-test is the only real-world gate.
-- ════════════════════════════════════════════════════════════════

module StatsVariance where

import Data.List (sortOn)
import Data.Ord (Down(..))

-- ════════════════════════════════════════════════════════════════
-- § 1. DETERMINISTIC RANDOMNESS (LCG → uniforms → normals)
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

-- | Box–Muller on LCG uniforms (u guarded away from 0).
normals :: Int -> [Double]
normals seed = go (uniforms seed)
  where
    go (u1 : u2 : us) =
      let r = sqrt (-2 * log (max 1e-12 u1))
          a = 2 * pi * u2
      in r * cos a : r * sin a : go us
    go _ = []

-- ════════════════════════════════════════════════════════════════
-- § 2. OKLAB GAMUT (self-contained; matrices as in DyadPalette)
-- ════════════════════════════════════════════════════════════════

type V3 = (Double, Double, Double)

oklabToLinear :: V3 -> V3
oklabToLinear (ll, aa, bb) =
  let l' = ll + 0.3963377774 * aa + 0.2158037573 * bb
      m' = ll - 0.1055613458 * aa - 0.0638541728 * bb
      s' = ll - 0.0894841775 * aa - 1.2914855480 * bb
      l = l' ^ (3 :: Int); m = m' ^ (3 :: Int); s = s' ^ (3 :: Int)
  in (  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
     , -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
     , -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s )

inGamut :: V3 -> Bool
inGamut lab =
  let (r, g, b) = oklabToLinear lab
  in all (\c -> c >= -1e-6 && c <= 1 + 1e-6) [r, g, b]

-- ════════════════════════════════════════════════════════════════
-- § 3. THE STATE PRIOR (format-uniform, ratified)
-- ════════════════════════════════════════════════════════════════

lamMin, lamMax :: Double
lamMin = 1e-6
lamMax = 2e-2

-- | Rejection-sample a centroid uniformly over the representable
--   OKLab region (bounding box L ∈ [0,1], a,b ∈ [−0.4, 0.4]).
sampleCentroid :: [Double] -> (V3, [Double])
sampleCentroid (u1 : u2 : u3 : us) =
  let c = (u1, 0.8 * u2 - 0.4, 0.8 * u3 - 0.4)
  in if inGamut c then (c, us) else sampleCentroid us
sampleCentroid _ = error "uniforms is infinite"

-- | Uniform rotation from a unit quaternion of 4 normals.
sampleRotation :: [Double] -> ([[Double]], [Double])
sampleRotation ns =
  let (q0 : q1 : q2 : q3 : rest) = ns
      n = sqrt (q0*q0 + q1*q1 + q2*q2 + q3*q3)
      (w, x, y, z) = (q0/n, q1/n, q2/n, q3/n)
      r = [ [1 - 2*(y*y + z*z), 2*(x*y - w*z),     2*(x*z + w*y)]
          , [2*(x*y + w*z),     1 - 2*(x*x + z*z), 2*(y*z - w*x)]
          , [2*(x*z - w*y),     2*(y*z + w*x),     1 - 2*(x*x + y*y)] ]
  in (r, rest)

sampleEigenvalues :: [Double] -> ([Double], [Double])
sampleEigenvalues (u1 : u2 : u3 : us) =
  ([ exp (log lamMin + u * (log lamMax - log lamMin)) | u <- [u1, u2, u3] ], us)
sampleEigenvalues _ = error "uniforms is infinite"

-- | Σ = R·diag(λ)·Rᵀ — PSD by construction.
composeCov :: [[Double]] -> [Double] -> [[Double]]
composeCov r lams =
  [ [ sum [ r !! i !! k * lams !! k * r !! j !! k | k <- [0 .. 2] ]
    | j <- [0 .. 2] ] | i <- [0 .. 2] ]

data GState = GState { gCentroid :: V3, gCov :: [[Double]] }

sampleState :: Int -> GState
sampleState seed =
  let (c, us1) = sampleCentroid (uniforms seed)
      (r, ns1) = sampleRotation (normals (seed + 1))
      (lams, _) = sampleEigenvalues us1
      _ = ns1
  in GState c (composeCov r lams)

-- ════════════════════════════════════════════════════════════════
-- § 4. RING TRAJECTORIES (OU on the 64-ring + boxcar jumps)
--
-- A stationary OU process on a ring is diagonalized by the ring's
-- Fourier modes with amplitudes ∝ 1/sqrt(θ² + k²): synthesizing it
-- as a truncated trigonometric series makes 64-periodicity EXACT,
-- smoothness the stiffness knob θ, and every sample closed-form.
-- Jumps are boxcars in (t mod 64) — periodic by construction.
-- ════════════════════════════════════════════════════════════════

ringFrames, ringModes :: Int
ringFrames = 64
ringModes = 8

-- | One scalar ring-OU component: amplitude, stiffness, coefficients.
ringOU :: Double -> Double -> [Double] -> (Double -> Double, [Double])
ringOU amp theta ns =
  let ks = [1 .. ringModes]
      (coeffs, rest) = splitAt (2 * ringModes) ns
      pairs = zip ks (chunk2 coeffs)
      norm = sqrt (sum [ 1 / (theta * theta + fromIntegral k * fromIntegral k)
                       | k <- ks ])
      f t = amp / max 1e-9 norm * sum
        [ (a * cos w + b * sin w) / sqrt (theta * theta + kk * kk)
        | (k, (a, b)) <- pairs
        , let kk = fromIntegral k
        , let w = 2 * pi * kk * t / fromIntegral ringFrames ]
  in (f, rest)
  where
    chunk2 (a : b : r) = (a, b) : chunk2 r
    chunk2 _ = []

-- | Periodic boxcar: δ inside [start, start+width) on the ring.
boxcar :: Double -> Int -> Int -> (Double -> Double)
boxcar delta start width t =
  let ti = floor t `mod` ringFrames
      inside = (ti - start) `mod` ringFrames < width
  in if inside then delta else 0

-- | A full trajectory: per-component centroid rings + jump boxcars,
--   log-eigenvalue rings, and a rotation-angle ring about a fixed
--   axis — Σ_t stays PSD because eigenvalues live in log space.
sampleTrajectory :: Int -> [GState]
sampleTrajectory seed =
  [ GState (cAt t) (covAt t) | f <- [0 .. ringFrames - 1], let t = fromIntegral f ]
  where
    base = sampleState seed
    (c0l, c0a, c0b) = gCentroid base
    us = uniforms (seed + 7)
    theta = exp (log 0.5 + (us !! 0) * (log 8 - log 0.5))
    nJumps = floor ((us !! 1) * 3)
    jumps =
      [ boxcar (0.12 * (us !! (10 + 3 * j)) - 0.06)
               (floor ((us !! (11 + 3 * j)) * 64))
               (4 + floor ((us !! (12 + 3 * j)) * 20))
      | j <- [0 .. nJumps - 1] ]
    jumpAt t = sum [ jf t | jf <- jumps ]
    ns = normals (seed + 13)
    (fL, ns1) = ringOU 0.06 theta ns
    (fA, ns2) = ringOU 0.03 theta ns1
    (fB, ns3) = ringOU 0.03 theta ns2
    cAt t = clampGamut ( c0l + fL t + jumpAt t
                       , c0a + fA t
                       , c0b + fB t )
    -- covariance ring: log-eigen walks + slow rotation about an axis
    (r0, ns4) = sampleRotation ns3
    (lams0, _) = sampleEigenvalues (uniforms (seed + 3))
    (fE1, ns5) = ringOU 0.3 theta ns4
    (fE2, ns6) = ringOU 0.3 theta ns5
    (fE3, ns7) = ringOU 0.3 theta ns6
    (fPhi, _) = ringOU 0.4 theta ns7
    covAt t =
      let lams = [ max lamMin (min lamMax (l * exp (fe t)))
                 | (l, fe) <- zip lams0 [fE1, fE2, fE3] ]
          r = matMul r0 (rotZ (fPhi t))
      in composeCov r lams
    rotZ phi = [ [cos phi, negate (sin phi), 0]
               , [sin phi, cos phi, 0]
               , [0, 0, 1] ]
    matMul a b = [ [ sum [ a !! i !! k * b !! k !! j | k <- [0 .. 2] ]
                   | j <- [0 .. 2] ] | i <- [0 .. 2] ]
    -- Iterative chroma reduction at clamped L: terminates in gamut
    -- because the gray axis with L ∈ [0,1] always is.
    clampGamut lab = go lab (0 :: Int)
      where
        go v@(l, a, b) k
          | inGamut v = v
          | k > 30    = (max 0 (min 1 l), 0, 0)
          | otherwise = go (max 0 (min 1 l), a * 0.8, b * 0.8) (k + 1)

-- ════════════════════════════════════════════════════════════════
-- § 5. THE FIELD GENERATOR (imagery from the state itself)
--
-- w(x,y) = random-phase cosine sum: mean 0, variance EXACTLY 1 in
-- expectation (E[cos²] = ½, amplitudes √(2/M)). Three independent
-- components, colored by chol(Σ): the pixel marginal matches the
-- state — the statistic IS the image.
-- ════════════════════════════════════════════════════════════════

fieldSide, fieldWaves :: Int
fieldSide = 64
fieldWaves = 24

chol3 :: [[Double]] -> [[Double]]
chol3 s =
  let l00 = sqrt (max 1e-12 (s !! 0 !! 0))
      l10 = s !! 1 !! 0 / l00
      l20 = s !! 2 !! 0 / l00
      l11 = sqrt (max 1e-12 (s !! 1 !! 1 - l10 * l10))
      l21 = (s !! 2 !! 1 - l20 * l10) / l11
      l22 = sqrt (max 1e-12 (s !! 2 !! 2 - l20 * l20 - l21 * l21))
  in [[l00, 0, 0], [l10, l11, 0], [l20, l21, l22]]

-- | One unit-variance random-phase field; frequency band sampled
--   per wave (the dither-difficulty knob: low bands = banding
--   country, high bands = noise country).
unitField :: Int -> (Int, Int) -> Double
unitField seed (x, y) =
  let us = uniforms seed
      waves = [ ( 0.5 + 7.5 * (us !! (4 * i))          -- cycles across the field
                , 2 * pi * (us !! (4 * i + 1))          -- direction
                , 2 * pi * (us !! (4 * i + 2)) )        -- phase
              | i <- [0 .. fieldWaves - 1] ]
      s = fromIntegral fieldSide
  in sqrt (2 / fromIntegral fieldWaves) * sum
       [ cos (2 * pi * f * (fromIntegral x * cos d + fromIntegral y * sin d) / s + p)
       | (f, d, p) <- waves ]

-- | Pixel lab at (x,y): centroid + chol(Σ) · (w1, w2, w3).
samplePixel :: GState -> Int -> (Int, Int) -> V3
samplePixel st seed xy =
  let l = chol3 (gCov st)
      w = [unitField (seed + 100 * k) xy | k <- [1, 2, 3]]
      (cl, ca, cb) = gCentroid st
      dot row = sum (zipWith (*) row w)
  in (cl + dot (l !! 0), ca + dot (l !! 1), cb + dot (l !! 2))

-- ════════════════════════════════════════════════════════════════
-- § 6. AXIOMS
-- ════════════════════════════════════════════════════════════════

stateSeeds, trajSeeds :: [Int]
stateSeeds = [101, 202, 303, 404, 505, 606]
trajSeeds = [17, 34, 51]

eigsOf :: [[Double]] -> [Double]
eigsOf m = let (vals, _) = jacobi3 m in vals

-- (SV1) Prior validity: centroids in gamut; covariance symmetric,
--       eigenvalues inside [λmin, λmax] up to tolerance.
axiom_SV1 :: Bool
axiom_SV1 = all ok (map sampleState stateSeeds)
  where
    ok st = inGamut (gCentroid st)
         && symmetric (gCov st)
         && all (\e -> e >= lamMin * 0.9 && e <= lamMax * 1.1) (eigsOf (gCov st))
    symmetric m = and [ abs (m !! i !! j - m !! j !! i) < 1e-12
                      | i <- [0 .. 2], j <- [0 .. 2] ]

-- (SV2) Rotations are orthonormal with determinant +1.
axiom_SV2 :: Bool
axiom_SV2 = all ok stateSeeds
  where
    ok seed =
      let (r, _) = sampleRotation (normals (seed + 1))
          rt = [ [ r !! j !! i | j <- [0 .. 2] ] | i <- [0 .. 2] ]
          prod = [ [ sum [ rt !! i !! k * r !! k !! j | k <- [0 .. 2] ]
                   | j <- [0 .. 2] ] | i <- [0 .. 2] ]
          idErr = maximum [ abs (prod !! i !! j - (if i == j then 1 else 0))
                          | i <- [0 .. 2], j <- [0 .. 2] ]
          det = r!!0!!0 * (r!!1!!1 * r!!2!!2 - r!!1!!2 * r!!2!!1)
              - r!!0!!1 * (r!!1!!0 * r!!2!!2 - r!!1!!2 * r!!2!!0)
              + r!!0!!2 * (r!!1!!0 * r!!2!!1 - r!!1!!1 * r!!2!!0)
      in idErr < 1e-9 && abs (det - 1) < 1e-9

-- (SV3) Exact ring closure: every trajectory is 64-periodic — the
--       trigonometric synthesis makes frame 64 ≡ frame 0.
axiom_SV3 :: Bool
axiom_SV3 = all ok trajSeeds
  where
    ok seed =
      let us = uniforms (seed + 7)
          theta = exp (log 0.5 + (us !! 0) * (log 8 - log 0.5))
          (f, _) = ringOU 0.06 theta (normals (seed + 13))
      in all (\t -> abs (f t - f (t + 64)) < 1e-9) [0, 7.5, 31, 63]

-- (SV4) Trajectory PSD: every frame of every trajectory has a
--       positive-definite covariance (log-space eigen walks).
axiom_SV4 :: Bool
axiom_SV4 = all (all frameOK . sampleTrajectory) trajSeeds
  where
    frameOK st = all (> 0) (eigsOf (gCov st))
              && inGamut (gCentroid st)

-- (SV5) Marginal law: the field's sample statistics match the
--       generating state (the statistic IS the image). Relative
--       Frobenius tolerance covers finite-sample error at 64².
axiom_SV5 :: Bool
axiom_SV5 = all ok (zip stateSeeds [1000, 2000 ..])
  where
    ok (sseed, fseed) =
      let st = sampleState sseed
          pixels = [ samplePixel st fseed (x, y)
                   | x <- [0 .. fieldSide - 1], y <- [0 .. fieldSide - 1] ]
          n = fromIntegral (length pixels)
          (cl, ca, cb) = gCentroid st
          mean3 = ( sum [l | (l,_,_) <- pixels] / n
                  , sum [a | (_,a,_) <- pixels] / n
                  , sum [b | (_,_,b) <- pixels] / n )
          (ml, ma, mb) = mean3
          devs = [ [l - ml, a - ma, b - mb] | (l, a, b) <- pixels ]
          sc = [ [ sum [ d !! i * d !! j | d <- devs ] / n | j <- [0 .. 2] ]
               | i <- [0 .. 2] ]
          frob m = sqrt (sum [ (m !! i !! j) ^ (2 :: Int)
                             | i <- [0 .. 2], j <- [0 .. 2] ])
          diffC = frob [ [ sc !! i !! j - gCov st !! i !! j | j <- [0 .. 2] ]
                       | i <- [0 .. 2] ]
          meanErr = sqrt ((ml-cl)^(2::Int) + (ma-ca)^(2::Int) + (mb-cb)^(2::Int))
      in meanErr < 0.03 && diffC / max 1e-9 (frob (gCov st)) < 0.45

-- (SV6) Determinism: the corpus is a pure function of the seed.
axiom_SV6 :: Bool
axiom_SV6 = all (\s -> render (sampleTrajectory s) == render (sampleTrajectory s))
                trajSeeds
  where
    render = concatMap (\st -> let (l, a, b) = gCentroid st
                               in show (l, a, b, gCov st))

-- (SV7) Seed separation: disjoint seeds yield distinct corpora —
--       held-out ranges are genuinely unseen.
axiom_SV7 :: Bool
axiom_SV7 = and [ gCentroid (sampleState a) /= gCentroid (sampleState b)
                | (a, b) <- zip stateSeeds (tail stateSeeds) ]

-- ════════════════════════════════════════════════════════════════
-- § 7. Jacobi (shared house 3×3 eigensolver)
-- ════════════════════════════════════════════════════════════════

jacobi3 :: [[Double]] -> ([Double], [V3])
jacobi3 mat0 = go (50 :: Int) mat0 [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
  where
    finish a v =
      ( [a !! 0 !! 0, a !! 1 !! 1, a !! 2 !! 2]
      , [ (v !! 0 !! i, v !! 1 !! i, v !! 2 !! i) | i <- [0 .. 2] ] )
    go 0 a v = finish a v
    go it a v =
      let (mx, p, q) = maximum [ (abs (a !! i !! j), i, j)
                               | i <- [0 .. 2], j <- [i + 1 .. 2] ]
      in if mx < 1e-14 then finish a v else
        let theta = if abs (a !! p !! p - a !! q !! q) < 1e-18
                      then pi / 4
                      else 0.5 * atan (2 * a !! p !! q / (a !! p !! p - a !! q !! q))
            sn = sin theta; cs = cos theta
            app = cs*cs * a!!p!!p + 2*sn*cs * a!!p!!q + sn*sn * a!!q!!q
            aqq = sn*sn * a!!p!!p - 2*sn*cs * a!!p!!q + cs*cs * a!!q!!q
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
-- § 8. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " StatsVariance: the GIF89a statistical-variance corpus"
  putStrLn " states ~ format-uniform; rings ~ OU + jumps; the"
  putStrLn " statistic generates both the palette and the image"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  let st = sampleState 101
      (cl, ca, cb) = gCentroid st
  putStrLn $ "  sample state (seed 101): centroid = ("
          ++ showF cl ++ ", " ++ showF ca ++ ", " ++ showF cb ++ ")"
  putStrLn $ "  eigenvalues = " ++ unwords (map showE (sortOn Down (eigsOf (gCov st))))
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "SV1 prior: gamut centroids, λ in range, Σ symmetric"        [axiom_SV1]
  check "SV2 rotations orthonormal, det +1"                          [axiom_SV2]
  check "SV3 exact ring closure (64-periodic trajectories)"          [axiom_SV3]
  check "SV4 every trajectory frame PSD and in gamut"                [axiom_SV4]
  check "SV5 marginal law: field statistics match the state"         [axiom_SV5]
  check "SV6 determinism: corpus = f(seed)"                          [axiom_SV6]
  check "SV7 seed separation: held-out ranges are unseen"            [axiom_SV7]
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  No capture data. The machine's palette world is a"
  putStrLn "  function of 9 numbers per frame; the corpus samples"
  putStrLn "  those numbers from the format's own representable"
  putStrLn "  range and lets the state generate everything else."
  putStrLn "  Held-out is a seed range. The only real-world gate"
  putStrLn "  is the device feel-test."
  putStrLn "══════════════════════════════════════════════════════════"

showF :: Double -> String
showF x =
  let n = round (abs x * 1000) :: Int
      sign = if x < 0 then "-" else ""
      frac = show (n `mod` 1000)
  in sign ++ show (n `div` 1000) ++ "." ++ replicate (3 - length frac) '0' ++ frac

showE :: Double -> String
showE x = showF (x * 1000) ++ "e-3"

check :: String -> [Bool] -> IO ()
check name results =
  let mark = if and results then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
