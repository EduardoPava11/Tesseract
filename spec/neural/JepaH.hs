{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- JepaH: the ONE model line — laws before any training code
--
-- Daniel's decree (2026-08-12): ONE model — MLX-trained JEPA-H,
-- ported to iPhone; performance in service of BEAUTY, where beauty
-- is the meters already in every GIF (RATE LEDGER M, DYAD HARMONY,
-- palette churn, PHASE F). Charter: nn/jepa/README.md.
--
-- The model lives on the capture's LATENT RING: 16 slots at the
-- rung-16 cadence (the 3.2 s loop), each slot the generating state
-- the palette is a theorem of. It predicts masked slots in
-- embedding space; deployed, its state estimate STEADIES the slow
-- state — less palette churn, flatter LZW residue, more measured
-- order. Every constant below is derived (cube shape, Gaussian
-- moments, the local-level filter's own algebra) — none are tuned.
--
--   JH1  the ring: 16 = frames/epochs, exact; the 320 cs time law
--   JH2  masking partitions: arcs tile the ring; phases partition
--   JH3  the trajectory law: local-level dynamics in
--        (centroid, log-variances); the derived steady-state gain
--   JH4  whitening: shift-equivariant, self-normalizing
--   JH5  churn + the smoothing lemma (the beauty mechanism)
--   JH6  filter sanity at the limits
-- ════════════════════════════════════════════════════════════════

module JepaH where

import Data.List (nub, sort)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE RING
-- ════════════════════════════════════════════════════════════════

frameCount, epochs, ringSlots, frameDelayCs :: Int
frameCount = 64
epochs = 4
ringSlots = frameCount `div` epochs      -- 16, derived
frameDelayCs = 5

-- ════════════════════════════════════════════════════════════════
-- § 2. MASKING (lawful partitions of the 16-ring)
-- ════════════════════════════════════════════════════════════════

-- | Contiguous arc of length len starting at s, torus wrap.
arc :: Int -> Int -> [Int]
arc s len = [ (s + i) `mod` ringSlots | i <- [0 .. len - 1] ]

-- | Stride-2 phase classes (the time component of the polyphase
--   partition, RL3's shadow on the ring).
phase :: Int -> [Int]
phase p = [ i | i <- [0 .. ringSlots - 1], i `mod` 2 == p ]

-- ════════════════════════════════════════════════════════════════
-- § 3. THE TRAJECTORY LAW (the sampler's generative model)
--
-- The app's slow state is filtered by a derived local-level gain
-- (DepthMixture.localLevelAlpha — the MS law). The corpus therefore
-- samples from the local-level model itself:
--
--     s_{t+1} = s_t + sigma_q * eta_t        (level drift)
--     y_t     = s_t + sigma_e * nu_t         (observation)
--
-- per dimension of the 6-dim latent (centroid l,a,b + LOG-variances
-- — log-space keeps every sampled variance positive BY CONSTRUCTION,
-- no clamping law needed). The optimal steady-state gain for signal
-- ratio q = sigma_q^2/sigma_e^2 is the filter algebra's own number:
--
--     alpha*(q) = (-q + sqrt (q^2 + 4q)) / 2
-- ════════════════════════════════════════════════════════════════

latentDim :: Int
latentDim = 6

alphaStar :: Double -> Double
alphaStar q = (negate q + sqrt (q * q + 4 * q)) / 2

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

normals :: Int -> [Double]
normals seed = go (uniforms seed)
  where go us = let (twelve, rest) = splitAt 12 us
                in (sum twelve - 6) : go rest

-- | One latent dimension's trajectory: (states, observations).
trajectory1 :: Int -> Double -> Double -> Double -> ([Double], [Double])
trajectory1 seed s0 sigQ sigE =
  let es = normals (2 * seed + 1)
      vs = normals (2 * seed + 2)
      states = take ringSlots (scanl (\s e -> s + sigQ * e) s0 es)
      obs = zipWith (\s v -> s + sigE * v) states (take ringSlots vs)
  in (states, obs)

-- ════════════════════════════════════════════════════════════════
-- § 4. WHITENING (the embedding's zeroth layer)
-- ════════════════════════════════════════════════════════════════

whiten :: [Double] -> [Double]
whiten xs =
  let n = fromIntegral (length xs)
      mu = sum xs / n
      var = sum [ (x - mu) ^ (2 :: Int) | x <- xs ] / n
      sd = sqrt var + 1e-12
  in [ (x - mu) / sd | x <- xs ]

rot :: Int -> [a] -> [a]
rot k xs = let n = length xs in [ xs !! ((i + k) `mod` n) | i <- [0 .. n - 1] ]

-- ════════════════════════════════════════════════════════════════
-- § 5. CHURN AND THE SMOOTHING LEMMA
-- ════════════════════════════════════════════════════════════════

-- | Palette temporal churn: mean absolute step around the torus
--   (byte level in the lab; the law is stated on any real stream).
churn :: [Double] -> Double
churn xs =
  let n = length xs
  in sum [ abs (xs !! ((i + 1) `mod` n) - xs !! i)
         | i <- [0 .. n - 1] ] / fromIntegral n

ema :: Double -> [Double] -> [Double]
ema a (x : xs) = scanl (\s y -> s + a * (y - s)) x xs
ema _ [] = []

totalVar :: [Double] -> Double
totalVar xs = sum (map abs (zipWith (-) (tail xs) xs))

-- ════════════════════════════════════════════════════════════════
-- § 6. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (JH1) THE RING: 16 slots is the cube's own number (frames per
--       epoch), and the loop closes at 320 cs exactly — slot count
--       times frames-per-slot times the wire delay.
axiom_JH1 :: Bool
axiom_JH1 =
     ringSlots == 16
  && ringSlots * epochs == frameCount
  && ringSlots * (frameCount `div` ringSlots) * frameDelayCs == 320

-- (JH2) MASKING PARTITIONS: for every arc length dividing 16, the
--       translates tile the ring exactly (each slot masked once
--       per sweep); the two stride-2 phases partition it; and no
--       arc of lawful length ever covers the whole ring (context
--       is never empty).
axiom_JH2 :: Bool
axiom_JH2 =
     and [ sort (concat [ arc (k * len) len
                        | k <- [0 .. ringSlots `div` len - 1] ])
             == [0 .. ringSlots - 1]
         | len <- [1, 2, 4, 8] ]
  && sort (phase 0 ++ phase 1) == [0 .. ringSlots - 1]
  && length (phase 0) == 8
  && and [ len < ringSlots | len <- [1, 2, 4, 8] ]

-- (JH3) THE TRAJECTORY LAW: sampled trajectories are deterministic
--       under the seed; log-space variances exponentiate positive
--       ALWAYS; and the derived steady-state gain obeys the filter
--       algebra — alpha*(q) solves a^2 = q(1-a), lies in (0,1),
--       is monotone in q, and hits the lawful limits (0 as q->0:
--       constant level, trust the average; 1 as q->inf: pure
--       drift, trust the observation).
axiom_JH3 :: Bool
axiom_JH3 =
     trajectory1 7 0.5 0.02 0.05 == trajectory1 7 0.5 0.02 0.05
  && all (> 0) [ exp v | v <- fst (trajectory1 9 (log 0.01) 0.1 0.1) ]
  && all (\q -> let a = alphaStar q
                in abs (a * a - q * (1 - a)) < 1e-9 && a > 0 && a < 1)
         qGrid
  && and (zipWith (<) (map alphaStar qGrid) (map alphaStar (tail qGrid)))
  && alphaStar 1e-8 < 1e-3
  && alphaStar 1e8 > 0.999
  where qGrid = [0.01, 0.1, 0.5, 1, 2, 10, 100]

-- (JH4) WHITENING: mean 0 and variance 1 on nondegenerate streams,
--       and EXACT equivariance with the ring rotation — the
--       embedding respects the loop's own symmetry, so the model
--       cannot learn a spurious phase origin.
axiom_JH4 :: Bool
axiom_JH4 =
     all okStat fixtures
  && and [ maxAbsDiff (whiten (rot k xs)) (rot k (whiten xs)) < 1e-9
         | xs <- fixtures, k <- [1, 3, 7] ]
  where
    fixtures = [ take 16 (normals s) | s <- [11, 12] ]
            ++ [ take 16 (uniforms 13) ]
    okStat xs = let w = whiten xs
                    n = fromIntegral (length w)
                    mu = sum w / n
                    var = sum (map (^ (2 :: Int)) w) / n
                in abs mu < 1e-9 && abs (var - 1) < 1e-6
    maxAbsDiff a b = maximum (map abs (zipWith (-) a b))

-- (JH5) CHURN + THE SMOOTHING LEMMA: churn is nonnegative, zero
--       exactly on constants, rotation-invariant on the torus; and
--       the mechanism law — a smaller EMA gain never increases the
--       stream's total variation (checked across fixtures and gain
--       pairs): steadier latent ==> less churn. This is WHY a
--       better state estimate buys beauty.
axiom_JH5 :: Bool
axiom_JH5 =
     churn (replicate 16 0.7) == 0
  && all (\xs -> churn xs >= 0) fixtures
  && all (\xs -> abs (churn xs - churn (rot 5 xs)) < 1e-9) fixtures
  && and [ totalVar (ema a1 xs) <= totalVar (ema a2 xs) + 1e-9
         | xs <- fixtures
         , (a1, a2) <- [(0.1, 0.3), (0.3, 0.6), (0.6, 1.0), (0.1, 1.0)] ]
  where fixtures = [ take 16 (normals s) | s <- [21, 22, 23] ]

-- (JH6) FILTER SANITY AT THE LIMITS: with zero observation noise
--       the observations ARE the states (any gain-1 filter is
--       exact); with zero drift the state is constant and the
--       trajectory says so.
axiom_JH6 :: Bool
axiom_JH6 =
     let (s, y) = trajectory1 31 0.4 0.03 0.0 in y == s
  && let (s2, _) = trajectory1 32 0.4 0.0 0.05
     in all (== head s2) s2

-- ════════════════════════════════════════════════════════════════
-- § 7. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " JepaH: the one model line — ring, masks, trajectories,"
  putStrLn " whitening, and the churn mechanism, as law"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "JH1 ring: 16 = frames/epochs; the 320 cs loop law"          [axiom_JH1]
  check "JH2 masks: arcs tile, phases partition, context nonempty"   [axiom_JH2]
  check "JH3 trajectories: deterministic, positive, gain algebra"    [axiom_JH3]
  check "JH4 whitening: mean0/var1, EXACT ring equivariance"         [axiom_JH4]
  check "JH5 churn laws + smoothing lemma (the beauty mechanism)"    [axiom_JH5]
  check "JH6 filter limits: no-noise exactness, no-drift constancy"  [axiom_JH6]
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  One model, one ring, one mechanism: predict the latent"
  putStrLn "  the palette is a theorem of, steady it, and beauty is"
  putStrLn "  the measured consequence — M up, churn down, harmony"
  putStrLn "  held. The meters promote; the device decides."
  putStrLn "══════════════════════════════════════════════════════════"

check :: String -> [Bool] -> IO ()
check name results =
  let mark = if and results then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
