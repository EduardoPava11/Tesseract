{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- MixtureStability: the mixture local-level law (MS)
--
-- Ruling (Daniel, 2026-08-11, on the first 17 Pro export): build
-- the mixture stability law. The device evidence (GIF
-- tesseract_1786472964, DYAD ENERGY trace): φ — the σ-class order
-- parameter — collapsed 0.34 → 0.00 by frame ~45, walls 429 → 0,
-- E_pal 0.39 → 0.93: the background family died mid-loop.
--
-- DIAGNOSIS. The export law fits ONE pooled mixture per capture
-- (DyadPipeline stage 0) and freezes s*. The per-frame depth
-- SIGNAL drifts (anchors, exposure, micro-motion), so late frames'
-- background samples crossed the frozen crossover and the σ class
-- went extinct — a failure of the ESTIMATOR's temporal model, not
-- of the mixture law itself.
--
-- THE LAW (constant-free, the DepthMixture pattern):
--
--   1. Fit the mixture PER FRAME on the frame's own samples
--      (per-frame refit follows any drift by construction).
--   2. Filter the per-frame state sequence
--          θ_f = (μF, μB, logit πB, log σ)
--      with the SAME derived local-level gain as ruling R2:
--          α = localLevelAlpha {θ_f}     (Muth/Kalman, DM10)
--      — pure flicker ⇒ α = 0 (frozen), true drift ⇒ α = 1
--      (tracked), blends in between. The pull field of frame f
--      uses the FILTERED state θ̂_f.
--   3. The capture-level two-phase decision (R3, BIC on pooled
--      samples) is unchanged; extinction within a two-phase
--      capture happens only through the standing Bayer floor
--      (t < 1/32 nowhere ⇒ no σ pixels), never by a hard flip.
--
-- The state transform is domain-respecting (logit / log), so the
-- filtered state is always a valid mixture; order μF > μB survives
-- filtering by convexity (EMA of the positive gap is positive).
--
--   MS1  identity          constant per-frame fits ⇒ α = 1 and
--                          filtered ≡ raw, exactly
--   MS2  flicker-kill      alternating fits ⇒ α = 0 ⇒ filtered
--                          frozen at θ_0; the σ-class mass never
--                          collapses while the raw sequence
--                          alternates into extinction
--   MS3  drift-tracking    zero-lag-1-autocov drift ⇒ α = 1 ⇒
--                          filtered ≡ raw (a true lean-in is
--                          followed exactly)
--   MS4  the device replay a drifting-anchor capture: (a) the
--                          pooled-fit law loses the σ class in
--                          late frames (φ → 0 — the bug, replayed);
--                          (b) the MS law keeps φ above the Bayer
--                          floor on every frame; (c) under anchor
--                          FLICKER the MS crossover moves less
--                          than the raw per-frame crossover
--   MS5  contraction       total variation of every filtered
--                          component ≤ raw total variation
--   MS6  order preserved   filtered μF > μB on every frame
--   MS7  gain parity       the copied localLevelAlpha reproduces
--                          DM10's witnesses (alternating ⇒ 0,
--                          zero-autocov walk ⇒ 1, constant ⇒ 1)
--
-- Verbatim copies from DepthMixture.hs (house pattern: spec files
-- standalone; if the twins drift, MS7 catches the gain).
-- ════════════════════════════════════════════════════════════════

module Main where

-- ── § 1. Mixture machinery (copy of DepthMixture.hs §§1–3) ──────

data Fit = Fit
  { muF   :: Double
  , muB   :: Double
  , piB   :: Double
  , sigma :: Double
  } deriving (Show, Eq)

initFit :: [Double] -> Fit
initFit xs = Fit hi lo 0.5 (max 1e-6 (std xs))
  where
    m  = mean xs
    hi = mean (filter (>= m) xs `orElse` [m + 1e-3])
    lo = mean (filter (<  m) xs `orElse` [m - 1e-3])
    orElse a b = if null a then b else a

emStep :: [Double] -> Fit -> Fit
emStep xs (Fit mf mb pb sd) = Fit mf' mb' pb' sd'
  where
    resp x = let pF = (1 - pb) * gauss x mf sd
                 pB = pb * gauss x mb sd
             in if pF + pB <= 0 then 0.5 else pB / (pF + pB)
    rs  = map resp xs
    n   = fromIntegral (length xs)
    nB  = sum rs
    nF  = n - nB
    mb' = if nB <= 0 then mb else sum (zipWith (*) rs xs) / nB
    mf' = if nF <= 0 then mf else sum (zipWith (\r x -> (1 - r) * x) rs xs) / nF
    pb' = min 0.999 (max 0.001 (nB / n))
    var = sum (zipWith (\r x -> r * (x - mb') ^ (2 :: Int)
                              + (1 - r) * (x - mf') ^ (2 :: Int)) rs xs) / n
    sd' = max 1e-6 (sqrt var)

gauss :: Double -> Double -> Double -> Double
gauss x mu sd = exp (negate ((x - mu) ^ (2 :: Int)) / (2 * sd * sd)) / sd

fitMixture :: [Double] -> Fit
fitMixture xs = relabel (iterate (emStep xs) (initFit xs) !! 64)
  where relabel f@(Fit a b p s)
          | a >= b    = f
          | otherwise = Fit b a (1 - p) s

crossover, temperature :: Fit -> Double
temperature f = sigma f * sigma f / max 1e-9 (muF f - muB f)
crossover f = (muF f + muB f) / 2 + temperature f * log (piB f / (1 - piB f))

pull :: Fit -> Double -> Double
pull f s = 1 / (1 + exp ((s - crossover f) / max 1e-9 (temperature f)))

mean :: [Double] -> Double
mean xs = sum xs / fromIntegral (length xs)

std :: [Double] -> Double
std xs = sqrt (mean (map (\x -> (x - m) ^ (2 :: Int)) xs))
  where m = mean xs

rho1 :: [Double] -> Maybe Double
rho1 ds
  | length ds < 2 = Nothing
  | v <= 0        = Nothing
  | otherwise     = Just (c1 / v)
  where
    n    = fromIntegral (length ds)
    dbar = sum ds / n
    cs   = map (subtract dbar) ds
    v    = sum (map (^ (2 :: Int)) cs) / n
    c1   = sum (zipWith (*) cs (tail cs)) / n

localLevelAlpha :: [[Double]] -> Double
localLevelAlpha xs
  | length xs < 3 = 1
  | null rhos     = 1
  | bigR <= 0     = 1
  | bigQ <= 0     = 0
  | otherwise     = gain (bigQ / bigR)
  where
    comps  = [ [ x !! k | x <- xs ] | k <- [0 .. length (head xs) - 1] ]
    rhos   = [ r | Just r <- map (rho1 . diffs) comps ]
    diffs c = zipWith (-) (tail c) c
    bigR   = sum [ max 0 (negate r) | r <- rhos ]
    bigQ   = sum [ max 0 (1 + 2 * min 0 r) | r <- rhos ]
    gain lam = let x = (lam + sqrt (lam * lam + 4 * lam)) / 2 in x / (x + 1)

-- ── § 2. The MS filter ──────────────────────────────────────────

toState :: Fit -> [Double]
toState f = [ muF f, muB f
            , log (piB f / (1 - piB f))
            , log (sigma f) ]

fromState :: [Double] -> Fit
fromState [a, b, lp, ls] = Fit a b (1 / (1 + exp (negate lp))) (exp ls)
fromState _ = error "state arity"

-- | The mixture local-level law: derived gain over the per-frame
--   state sequence, EMA in the transformed domain.
filterFits :: [Fit] -> [Fit]
filterFits fits = map fromState (scanl1 step states)
  where
    states = map toState fits
    a = localLevelAlpha states
    step prev cur = zipWith (\p c -> p + a * (c - p)) prev cur

-- ── § 3. Synthetic captures (LCG, deterministic) ────────────────

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

-- CLT normal: sum of 12 uniforms − 6
normals :: Int -> [Double]
normals seed = go (uniforms seed)
  where go us = let (a, rest) = splitAt 12 us in (sum a - 6) : go rest

-- | One frame of depth samples: face at μF, background at μB,
--   background fraction w, noise σ, plus a global anchor offset d.
frameSamples :: Int -> Double -> Double -> Double -> Double -> Double
             -> [Double]
frameSamples seed mF mB w sd d =
  [ clamp01 (base + sd * g + d)
  | (u, g) <- take 512 (zip (uniforms (seed * 7 + 1)) (normals (seed * 13 + 5)))
  , let base = if u < w then mB else mF ]
  where clamp01 = max 0 . min 1

bayerFloor :: Double
bayerFloor = 1 / 32          -- the standing Bayer extremum (derived)

-- | σ-class mass of a frame under a fit: the fraction of samples
--   whose coverage clears the Bayer floor (extinction criterion).
phi :: Fit -> [Double] -> Double
phi f xs = fromIntegral (length (filter ((> bayerFloor) . pull f) xs))
         / fromIntegral (length xs)

tv :: [Double] -> Double
tv c = sum (map abs (zipWith (-) (tail c) c))

gate :: String -> Bool -> IO Bool
gate name ok = do
  putStrLn $ "  " ++ (if ok then "✓" else "✗") ++ " " ++ name
  pure ok

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " MixtureStability: per-frame fits, derived-gain filtering"
  putStrLn " drift is followed, flicker is frozen, collapse needs truth"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  -- MS1: constant sequence ⇒ identity
  let cFit = Fit 0.9 0.25 0.25 0.0625
      constSeq = replicate 64 cFit
      close a b = abs (a - b) < 1e-9
      fitClose x y = close (muF x) (muF y) && close (muB x) (muB y)
                     && close (piB x) (piB y) && close (sigma x) (sigma y)
  g1 <- gate "MS1  constant fits ⇒ α = 1, filtered ≡ raw (round-trip exact)"
      $ and (zipWith fitClose (filterFits constSeq) constSeq)

  -- MS2: alternating fits ⇒ frozen at θ_0; σ class never collapses
  let hiF = Fit 0.9 0.25 0.30 0.05
      -- the collapse shape: a transient-chasing fit whose crossover
      -- falls BELOW the background probes, so t < the Bayer floor
      loF = Fit 0.35 0.05 0.02 0.03
      flickerSeq = take 64 (cycle [hiF, loF])
      filtFlick = filterFits flickerSeq
      probeBg = [ 0.2 + 0.1 * u | u <- take 128 (uniforms 99) ]
  g2 <- gate "MS2  alternating fits ⇒ α = 0, frozen; min φ stays positive"
      $ and (zipWith fitClose filtFlick (replicate 64 hiF))
        && minimum (map (`phi` probeBg) filtFlick) > 0
        && minimum (map (`phi` probeBg) flickerSeq) == 0

  -- MS3: zero-lag-1-autocov drift ⇒ tracked exactly
  let driftSeq = [ Fit (fromIntegral (461 - k) / 512)
                       (fromIntegral (128 + 2 * k) / 1024) 0.25 0.0625
                 | k <- [0 .. 63 :: Int] ]
      filtDrift = filterFits driftSeq
  g3 <- gate "MS3  linear drift ⇒ α = 1, filtered ≡ raw (lean-in followed)"
      $ and (zipWith fitClose filtDrift driftSeq)

  -- MS4: THE DEVICE REPLAY — drifting anchor over 64 frames
  let anchors = [ 0.010 * fromIntegral k | k <- [0 .. 63 :: Int] ]
      framesD = [ frameSamples (100 + k) 0.9 0.25 0.3 0.05 d
                | (k, d) <- zip [0 ..] anchors ]
      pooledFit = fitMixture (concat framesD)
      perFrame  = map fitMixture framesD
      filtered  = filterFits perFrame
      phiPooled = [ phi pooledFit xs | xs <- framesD ]
      phiMS     = [ phi f xs | (f, xs) <- zip filtered framesD ]
      -- anchor FLICKER: alternating ±offset, no true motion
      flickA    = [ if even k then 0 else 0.05 | k <- [0 .. 63 :: Int] ]
      framesF   = [ frameSamples (300 + k) 0.9 0.25 0.3 0.05 d
                  | (k, d) <- zip [0 ..] flickA ]
      perFrameF = map fitMixture framesF
      filteredF = filterFits perFrameF
  g4 <- gate ("MS4  device replay: pooled law loses the σ class "
              ++ "(min φ = " ++ show (round2 (minimum phiPooled))
              ++ "); MS law keeps it (min φ = "
              ++ show (round2 (minimum phiMS))
              ++ "); flicker crossover TV contracts")
      $ minimum phiPooled < bayerFloor          -- the bug, replayed
        && minimum phiMS > 4 * bayerFloor       -- the law holds the class
        && tv (map crossover filteredF)
             < tv (map crossover perFrameF) / 4 -- flicker smoothed ≥4×

  -- MS5: contraction on every suite and component
  let suites = [flickerSeq, driftSeq, perFrame, perFrameF]
      contracts fs = and
        [ tv (map (!! k) (map toState (filterFits fs)))
            <= tv (map (!! k) (map toState fs)) + 1e-12
        | k <- [0 .. 3] ]
  g5 <- gate "MS5  total variation of filtered ≤ raw, every component"
      $ all contracts suites

  -- MS6: order μF > μB preserved through filtering
  g6 <- gate "MS6  filtered μF > μB on every frame of every suite"
      $ all (all (\f -> muF f > muB f) . filterFits) suites

  -- MS7: gain-copy parity with DM10's witnesses
  let alt  = [ [fromIntegral (k `mod` 2)] | k <- [0 .. 15 :: Int] ]
      walk = [ [fromIntegral k] | k <- [0 .. 15 :: Int] ]
      cst  = replicate 16 [7]
  g7 <- gate "MS7  gain parity: alternating ⇒ 0, walk ⇒ 1, constant ⇒ 1"
      $ localLevelAlpha alt == 0
        && localLevelAlpha walk == 1
        && localLevelAlpha cst == 1

  putStrLn ""
  let results = [g1, g2, g3, g4, g5, g6, g7]
  putStrLn $ "  " ++ show (length (filter id results)) ++ "/"
           ++ show (length results) ++ " gates green"
  putStrLn ""
  putStrLn "  Drift is followed, flicker is frozen, extinction is"
  putStrLn "  earned at the Bayer floor — never granted by a flip."
  if and results then pure () else error "MixtureStability: gate failure"
  where
    round2 x = fromIntegral (round (x * 100) :: Int) / 100 :: Double
