-- DepthMixture.hs
-- Tesseract spec — temporal layer
--
-- THE CONSTANT-FREE ROLE LAW: subject / background as the two phases
-- of the capture's own depth field. No naked thresholds.
--
-- Standing decree (Daniel, 2026-08-10): "we should never leave naked
-- constant like this" — the DyadPipeline trichotomy (faceThreshold
-- 0.6, bleedWidth 0.15, bleedGamma 0.5) hard-codes what MUST be
-- calculable from the data. This file derives the replacement.
--
-- MODEL. The scene is a two-state system: subject F, background B.
-- The pooled depth signals of a capture (64 × 4096 samples of s) are
-- a two-component Gaussian mixture with TIED variance:
--
--     P(s) = π_F·N(s; μ_F, σ²) + π_B·N(s; μ_B, σ²),   μ_F > μ_B
--
-- fit by EM (Dempster–Laird–Rubin 1977). Tied σ is load-bearing:
-- unequal variances make the log-odds QUADRATIC in s, so the
-- posterior is non-monotone (a far-enough wall flips back to
-- "face"). Tied σ forces the log-odds linear ⇒ monotone ⇒ a unique
-- crossover (DS2's spirit, lifted to a learned law).
--
-- THE LAW (closed form once fit):
--
--     pull       t(s) = P(B|s) = 1 / (1 + exp((s − s*)/τ))
--     crossover  s*   = (μ_F+μ_B)/2 + τ·ln(π_B/π_F)      (t(s*) = ½)
--     temper.    τ    = σ² / (μ_F − μ_B)                  (noise²/separation)
--
-- Boltzmann reading: with E_k(s) = (s−μ_k)²/2σ² − ln π_k,
-- t = e^(−E_B) / (e^(−E_F) + e^(−E_B)); the border is the
-- EQUAL-FREE-ENERGY CROSSOVER — the phase16 ruling ("BORDER = phase
-- crossover") made exact. The old constants become derived outputs:
--
--     faceThreshold 0.6   → s*             (per capture)
--     bleedGamma    0.5   → gone           (logistic shape is derived)
--     bleedWidth    0.15  → τ·ln 81        (10–90% width, emergent)
--     "~46 cm"            → m* = DepthSignal⁻¹(s*)  (a REPORT, not an input)
--
-- EQUATIONS OF MOTION. Two dynamics, both law-bound here:
--   (i) the EM iteration is the relaxation toward the free-energy
--       minimum — log-likelihood NON-DECREASING per step (DM7);
--  (ii) across the 64 frames the per-frame refit μ_F(t) is the
--       subject's literal motion (breathing, sway) — telemetry.
--
-- ROLE TRICHOTOMY WITHOUT NEW CONSTANTS. The Bayer 4×4 dither
-- (DyadPalette §6 v3, thresholds {0.5/16 … 15.5/16}) defines the
-- representable coverages; outside its range a solid side is forced:
--
--     solid face    ⇔  t < 1/32   (below finest coverage)
--     solid mirror  ⇔  t > 31/32  (above coarsest coverage)
--     band          ⇔  otherwise  (pair-dither at coverage t)
--
-- DEGENERATE SCENES (face fills the frame; no background phase):
-- model selection by BIC, penalty (k/2)·ln N — derived, not tuned.
-- One component winning ⇒ single-phase scene ⇒ no mirror side.
--
--   DM1  totality + range   t(s) ∈ [0,1] for all s
--   DM2  monotone           s₁ ≤ s₂ ⇒ t(s₁) ≥ t(s₂) (nearer never
--                           more background); crossover unique, t(s*)=½
--   DM3  planted recovery   EM on a planted bimodal field recovers
--                           (μ_F, μ_B, π_B, σ) and hence s*, τ
--   DM4  affine equivariance re-anchoring DepthSignal (s ↦ a·s+b, a>0)
--                           transports the fit; t is invariant at
--                           corresponding points — the anchors are NOT
--                           load-bearing for segmentation
--   DM5  posterior = responsibility   the closed-form logistic equals
--                           the EM responsibility at every sample
--   DM6  crossover report   m* from s* matches DepthSignal⁻¹ closed form
--   DM7  EM is a motion     log-likelihood non-decreasing per iteration
--   DM8  dither trichotomy  role boundaries are the Bayer extrema
--                           {1/32, 31/32}; band ⇔ representable coverage
--   DM9  degenerate scene   unimodal planted field ⇒ BIC prefers one
--                           component ⇒ single-phase (no mirror side)
--
-- Swift twin: Tesseract/Tesseract/DepthMixture.swift, consumed by
-- DyadPipeline (replaces faceThreshold/bleedWidth/bleedGamma/pull).
--
-- §R RULED (Daniel, 2026-08-10):
--   R1 RULED: DyadPalette.analyze weights = 1 − t (posterior subject
--      probability), replacing raw depth signal.
--   R2 RULED: EMA α is DERIVED — see §6 localLevelAlpha (DM10).
--      Muth 1960: the EMA is the optimal filter for a local-level
--      process (random-walk signal + white measurement noise); α is
--      the steady-state Kalman gain, estimated from the per-frame
--      stats sequence by method of moments on first differences:
--          Var(Δx) = q + 2r,   Cov₁(Δx) = −r
--          λ = q/r,  x = (λ+√(λ²+4λ))/2,  α = x/(x+1)
--      Pure flicker (ρ₁ = −1) ⇒ α = 0; zero-autocovariance drift ⇒
--      α = 1; constant stats ⇒ α = 1 (EMA byte-neutral). DY7's
--      pinned 0.3 is superseded.
--   R3 RULED: single-phase captures (DM9) ⇒ ALL-FACE (t ≡ 0, no
--      mirror side).
--
--   DM10 EMA gain derived   α ∈ [0,1]; alternating flicker ⇒ α = 0
--                           exactly; zero-lag-1 walk ⇒ α = 1 exactly;
--                           blends interior and monotone in the
--                           signal/noise amplitude ratio; constant
--                           sequence ⇒ α = 1 (identity EMA)
--   DM11 rung-16 τ-lift     the preview's pooled fit on rung-16
--                           judgments (64-sample exact means, TL9)
--                           collapses τ naively; lifting by the law
--                           of total variance (σ²_total = σ²_between
--                           + E[σ²_within], an identity) recovers the
--                           full-resolution (s*, τ). EXPORT keeps the
--                           full-res fit — measurement-only decree.
--   DM12 lift dominance     the naive gap grows with within-judgment
--                           variance; the lifted gap stays bounded
--
-- TRUTHFUL harness: every law asserted, main exits nonzero on failure.

module Main where

import Data.List (sort)
import System.Exit (exitFailure, exitSuccess)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE MIXTURE, EXACTLY
-- ════════════════════════════════════════════════════════════════

data Fit = Fit
  { muF   :: Double   -- subject mean   (μ_F > μ_B by relabeling)
  , muB   :: Double   -- background mean
  , piB   :: Double   -- background weight
  , sigma :: Double   -- tied std-dev
  } deriving Show

normalPdf :: Double -> Double -> Double -> Double
normalPdf mu sd x = exp (negate ((x-mu)^(2::Int)) / (2*sd*sd)) / (sd * sqrt (2*pi))

-- | Background responsibility of one sample under a fit (soft E-step).
responsibility :: Fit -> Double -> Double
responsibility (Fit mf mb pb sd) s =
  let pB = pb * normalPdf mb sd s
      pF = (1-pb) * normalPdf mf sd s
  in pB / (pB + pF)

-- | One EM step, tied variance.
emStep :: [Double] -> Fit -> Fit
emStep xs fit = Fit mf' mb' pb' sd'
  where
    rs  = map (responsibility fit) xs
    n   = fromIntegral (length xs)
    sB  = sum rs
    sF  = n - sB
    mb' = sum (zipWith (*) rs xs) / sB
    mf' = sum (zipWith (\r x -> (1-r)*x) rs xs) / sF
    pb' = sB / n
    var = sum (zipWith (\r x -> r*(x-mb')^(2::Int) + (1-r)*(x-mf')^(2::Int)) rs xs) / n
    sd' = max 1e-9 (sqrt var)

-- | Deterministic init: split at the median, class means either side.
--   (No randomness — CI-safe, reproducible.)
initFit :: [Double] -> Fit
initFit xs = Fit (mean hi) (mean lo) 0.5 (max 1e-9 (stdev xs))
  where
    ys       = sort xs
    (lo, hi) = splitAt (length ys `div` 2) ys
    mean zs  = sum zs / fromIntegral (length zs)
    stdev zs = let m = sum zs / fromIntegral (length zs)
               in sqrt (sum [ (z-m)^(2::Int) | z <- zs ] / fromIntegral (length zs))

-- | Full fit: fixed 64 EM steps from the deterministic init, then
--   relabel so μ_F ≥ μ_B (subject = nearer = larger signal).
fitMixture :: [Double] -> Fit
fitMixture xs = relabel (iterate (emStep xs) (initFit xs) !! 64)
  where relabel f | muF f >= muB f = f
                  | otherwise      = Fit (muB f) (muF f) (1 - piB f) (sigma f)

logLik :: [Double] -> Fit -> Double
logLik xs (Fit mf mb pb sd) =
  sum [ log (pb * normalPdf mb sd x + (1-pb) * normalPdf mf sd x) | x <- xs ]

-- ════════════════════════════════════════════════════════════════
-- § 2. THE LAW: pull, crossover, temperature — closed form
-- ════════════════════════════════════════════════════════════════

temperature :: Fit -> Double
temperature f = sigma f * sigma f / (muF f - muB f)

crossover :: Fit -> Double
crossover f = (muF f + muB f) / 2 + temperature f * log (piB f / (1 - piB f))

-- | THE PULL. Replaces DyadPipeline.pull and its three constants.
pull :: Fit -> Double -> Double
pull f s = 1 / (1 + exp ((s - crossover f) / temperature f))

-- | Emergent band width (10–90% of the logistic): τ·ln 81.
bandWidth :: Fit -> Double
bandWidth f = temperature f * log 81

-- Bayer 4×4 coverage extrema (DyadPalette §6 v3) — already law, not new.
bayerMin, bayerMax :: Double
bayerMin = 0.5 / 16    -- 1/32
bayerMax = 15.5 / 16   -- 31/32

data Role = SolidFace | Band | SolidMirror deriving (Eq, Show)

role :: Fit -> Double -> Role
role f s
  | t < bayerMin = SolidFace
  | t > bayerMax = SolidMirror
  | otherwise    = Band
  where t = pull f s

-- DepthSignal anchors — used ONLY to report s* in meters (DM4 proves
-- they are not load-bearing for the segmentation itself).
dNear, dFar :: Double
dNear = 0.25
dFar  = 1.5

metersOf :: Double -> Double
metersOf s = 1 / (1/dFar + s * (1/dNear - 1/dFar))

-- | BIC = k·ln N − 2·ln L. One component: k=2 (μ,σ). Two, tied: k=4.
bic1, bic2 :: [Double] -> Double
bic1 xs = 2 * log n - 2 * logLik xs (Fit m m 0.5 sd)   -- both means = m ⇒ single Gaussian
  where n  = fromIntegral (length xs)
        m  = sum xs / n
        sd = max 1e-9 (sqrt (sum [ (x-m)^(2::Int) | x <- xs ] / n))
bic2 xs = 4 * log n - 2 * logLik xs (fitMixture xs)
  where n = fromIntegral (length xs)

twoPhase :: [Double] -> Bool
twoPhase xs = bic2 xs < bic1 xs

-- ════════════════════════════════════════════════════════════════
-- § 3. THE DERIVED EMA GAIN (ruling R2) — localLevelAlpha
-- ════════════════════════════════════════════════════════════════

-- | Lag-1 autocorrelation of a series (population moments).
rho1 :: [Double] -> Maybe Double
rho1 ds
  | length ds < 2 = Nothing
  | v <= 0        = Nothing               -- constant component: uninformative
  | otherwise     = Just (c1 / v)
  where
    n    = fromIntegral (length ds)
    dbar = sum ds / n
    es   = map (subtract dbar) ds
    v    = sum (map (^(2::Int)) es) / n
    c1   = sum (zipWith (*) es (tail es)) / (n - 1)

-- | THE GAIN. Input: per-frame stat vectors (T × K). Output: the
--   steady-state Kalman gain of the pooled local-level model.
localLevelAlpha :: [[Double]] -> Double
localLevelAlpha xs
  | length xs < 3 = 1                     -- no moments estimable: identity EMA
  | null rhos     = 1                     -- constant stats: byte-neutral
  | bigR <= 0     = 1                     -- no measurement noise: follow
  | bigQ <= 0     = 0                     -- no signal: full smoothing
  | otherwise     = gain (bigQ / bigR)
  where
    comps  = [ [ x !! k | x <- xs ] | k <- [0 .. length (head xs) - 1] ]
    rhos   = [ r | Just r <- map (rho1 . diffs) comps ]
    diffs c = zipWith (-) (tail c) c
    -- standardized diffs: Var = 1, so r̂ = max 0 (−ρ), q̂ = 1 − 2r̂ (≥ 0)
    bigR   = sum [ max 0 (negate r) | r <- rhos ]
    bigQ   = sum [ max 0 (1 + 2 * min 0 r) | r <- rhos ]
    gain lam = let x = (lam + sqrt (lam*lam + 4*lam)) / 2 in x / (x + 1)

-- ════════════════════════════════════════════════════════════════
-- § 4. PLANTED FIELDS (deterministic — no System.Random in CI)
-- ════════════════════════════════════════════════════════════════

-- Binomial(8) atoms around a mean: near-Gaussian, exact weights.
-- Values μ + δ·(k−4)/2, k=0..8, weights C(8,k)/256; var = δ²/2.
cluster :: Double -> Double -> Int -> [Double]
cluster mu delta count =
  concat [ replicate (count * c8 k `div` 256) (mu + delta * fromIntegral (k-4) / 2)
         | k <- [0..8 :: Int] ]
  where c8 k = [1,8,28,56,70,56,28,8,1] !! k

-- The planted portrait: wall at s=0.05 (3072 px), face at s=0.75 (1024 px).
plantedBimodal :: [Double]
plantedBimodal = cluster 0.05 0.06 3072 ++ cluster 0.75 0.06 1024

plantedUnimodal :: [Double]
plantedUnimodal = cluster 0.5 0.06 4096

planted :: Fit
planted = fitMixture plantedBimodal

-- Signal sample grid for range/monotone laws.
sGrid :: [Double]
sGrid = [ fromIntegral k / 100 | k <- [0..100 :: Int] ]

approx :: Double -> Double -> Double -> Bool
approx tol a b = abs (a - b) < tol

-- ════════════════════════════════════════════════════════════════
-- § 4b. RUNG-16 JUDGMENTS + THE τ-LIFT (Aerial Mirror spec, step 2)
--
-- TL9: depth's native rung is 16 — one judgment = the exact mean of
-- 64 base samples (4×4 px × 4 frames). The live preview refits the
-- mixture on judgments; means alone shrink the tied σ to the
-- between-judgment component and would collapse τ = σ²/Δμ (a
-- near-hard band). The lift is the law of total variance — an
-- identity, not a tunable.
-- ════════════════════════════════════════════════════════════════

-- | One phase-pure judgment: binomial(6) atoms, EXACTLY 64 samples
--   (weights 1,6,15,20,15,6,1 sum to 64). var = 0.375·δ².
judgment64 :: Double -> Double -> [Double]
judgment64 mu delta =
  concat [ replicate w (mu + delta * fromIntegral (k - 3) / 2)
         | (k, w) <- zip [0 .. 6 :: Int] [1, 6, 15, 20, 15, 6, 1] ]

-- | The planted capture at rung 16: 48 background + 16 face
--   judgments (phase-pure — rung-16 spatial pooling is away from
--   the silhouette; the boundary band is the mixture's own job).
plantedCapture :: Double -> [[Double]]
plantedCapture delta =
  replicate 48 (judgment64 0.05 delta) ++ replicate 16 (judgment64 0.75 delta)

meanOf :: [Double] -> Double
meanOf xs = sum xs / fromIntegral (length xs)

varOf :: [Double] -> Double
varOf xs = let m = meanOf xs
           in sum [ (x - m) ^ (2 :: Int) | x <- xs ] / fromIntegral (length xs)

-- | (s*_full, τ_full, s*_lifted, τ_lifted) for a planted capture.
liftedFit :: Double -> (Double, Double, Double, Double)
liftedFit delta = (crossover full, temperature full, sLift, tLift)
  where
    blocks = plantedCapture delta
    full = fitMixture (concat blocks)
    pooled = fitMixture (map meanOf blocks)
    wWithin = meanOf (map varOf blocks)
    sigma2Lift = sigma pooled * sigma pooled + wWithin
    tLift = sigma2Lift / (muF pooled - muB pooled)
    sLift = (muF pooled + muB pooled) / 2
          + tLift * log (piB pooled / (1 - piB pooled))

-- ════════════════════════════════════════════════════════════════
-- § 5. THE LAWS
-- ════════════════════════════════════════════════════════════════

dm1_range :: Bool
dm1_range = all (\s -> let t = pull planted s in 0 <= t && t <= 1)
                (sGrid ++ [-10, 10])

dm2_monotone :: Bool
dm2_monotone = and [ pull planted s1 >= pull planted s2
                   | s1 <- sGrid, s2 <- sGrid, s1 <= s2 ]
            && approx 1e-9 (pull planted (crossover planted)) 0.5

dm3_recovery :: Bool
dm3_recovery = approx 0.01 (muF planted) 0.75
            && approx 0.01 (muB planted) 0.05
            && approx 0.01 (piB planted) 0.75
            && approx 0.01 (sigma planted) (0.06 / sqrt 2)

-- Affine recalibration s ↦ a·s + b: refit on transported data; the
-- pull at transported points must be unchanged (anchors not load-bearing).
dm4_equivariance :: Bool
dm4_equivariance = and
  [ approx 1e-6 (pull planted s) (pull planted' (a*s + b)) | s <- sGrid ]
  && approx 1e-6 (crossover planted') (a * crossover planted + b)
  where
    (a, b)   = (0.8, 0.1)   -- an arbitrary re-anchoring
    planted' = fitMixture (map (\s -> a*s + b) plantedBimodal)

dm5_posterior_is_responsibility :: Bool
dm5_posterior_is_responsibility =
  and [ approx 1e-9 (pull planted s) (responsibility planted s)
      | s <- take 500 plantedBimodal ]

dm6_meters_report :: Bool
dm6_meters_report =
  let s' = crossover planted
      m' = metersOf s'
      -- closed-form inverse of DepthSignal: s = ((1/m − 1/dFar)/(1/dNear − 1/dFar))
      sBack = (1/m' - 1/dFar) / (1/dNear - 1/dFar)
  in approx 1e-9 sBack s' && dNear < m' && m' < dFar

dm7_em_is_a_motion :: Bool
dm7_em_is_a_motion =
  let fits = take 65 (iterate (emStep plantedBimodal) (initFit plantedBimodal))
      lls  = map (logLik plantedBimodal) fits
  in and (zipWith (\l0 l1 -> l1 >= l0 - 1e-9) lls (tail lls))

dm8_dither_trichotomy :: Bool
dm8_dither_trichotomy =
  role planted (muF planted) == SolidFace          -- deep in the face phase
  && role planted (muB planted) == SolidMirror     -- deep in the background phase
  && role planted (crossover planted) == Band      -- the crossover dithers
  -- boundaries are exactly the Bayer extrema, nothing else:
  && bayerMin == 1/32 && bayerMax == 31/32

dm9_degenerate :: Bool
dm9_degenerate = twoPhase plantedBimodal && not (twoPhase plantedUnimodal)

-- Planted stat sequences for DM10 (T = 16 frames, K = 2 components).
-- flickerSeq: pure alternating measurement noise, ρ₁(Δx) = −1.
-- walkSeq: cumsum of the diff pattern (+1,+1,−1,−1) — zero lag-1
-- autocovariance of the diffs, i.e. no detectable measurement noise.
flickerSeq, walkSeq, constSeq :: [[Double]]
flickerSeq = [ [ s * 0.1,  s * 3 ] | k <- [0 .. 15 :: Int]
             , let s = if even k then 1 else -1 ]
walkSeq    = [ [ w, 2 * w ] | w <- scanl (+) 0 (take 16 (cycle [1, 1, -1, -1])) ]
constSeq   = replicate 16 [0.7, 0.2]

blend :: Double -> [[Double]]
blend amp = zipWith (zipWith (\w f -> amp * w + f)) walkSeq flickerSeq

dm10_derived_alpha :: Bool
dm10_derived_alpha =
     all (\s -> let a = localLevelAlpha s in 0 <= a && a <= 1)
         [flickerSeq, walkSeq, constSeq, blend 1, blend 4]
  && localLevelAlpha flickerSeq == 0          -- pure flicker: full smoothing
  && localLevelAlpha walkSeq    == 1          -- pure signal: follow
  && localLevelAlpha constSeq   == 1          -- constant stats: identity EMA
  && (let a1 = localLevelAlpha (blend 1)
          a4 = localLevelAlpha (blend 4)
      in 0 < a1 && a1 < a4 && a4 < 1)         -- interior, monotone in SNR

dm11_tau_lift :: Bool
dm11_tau_lift =
  let (sF, tF, sL, tL) = liftedFit 0.06
      naive = temperature (fitMixture (map meanOf (plantedCapture 0.06)))
  in abs (sL - sF) < 0.005            -- lifted crossover matches full-res
  && abs (tL - tF) / tF < 0.05        -- lifted temperature matches
  && naive < tF / 10                  -- the collapse DM11 exists to prevent

dm12_lift_dominance :: Bool
dm12_lift_dominance =
     naiveGap 0.12 > naiveGap 0.06        -- naive gap grows with within-var
  && liftGap 0.06 <= naiveGap 0.06
  && liftGap 0.12 <= naiveGap 0.12
  && liftGap 0.12 / tauFull 0.12 < 0.05   -- lifted gap stays bounded
  where
    tauFull d = let (_, t, _, _) = liftedFit d in t
    liftGap d = let (_, tF, _, tL) = liftedFit d in abs (tL - tF)
    naiveGap d =
      abs (temperature (fitMixture (map meanOf (plantedCapture d))) - tauFull d)

-- ════════════════════════════════════════════════════════════════
-- § 6. HARNESS
-- ════════════════════════════════════════════════════════════════

check :: String -> Bool -> IO Bool
check name ok = do
  putStrLn ((if ok then "  ✓ " else "  ✗ ") ++ name)
  return ok

main :: IO ()
main = do
  putStrLn "DepthMixture: the constant-free role law (two-phase depth field)"
  putStrLn ("  planted fit: " ++ show planted)
  putStrLn ("  s* = " ++ show (crossover planted)
         ++ "  τ = " ++ show (temperature planted)
         ++ "  band = " ++ show (bandWidth planted)
         ++ "  m* = " ++ show (metersOf (crossover planted)) ++ " m")
  results <- sequence
    [ check "DM1 range: t(s) ∈ [0,1] everywhere"                       dm1_range
    , check "DM2 monotone; unique crossover with t(s*) = 1/2"          dm2_monotone
    , check "DM3 planted recovery: (μ_F, μ_B, π_B, σ) from the field"  dm3_recovery
    , check "DM4 affine equivariance: anchors not load-bearing"        dm4_equivariance
    , check "DM5 closed-form pull == EM responsibility"                dm5_posterior_is_responsibility
    , check "DM6 crossover report m* inverts DepthSignal exactly"      dm6_meters_report
    , check "DM7 EM is a motion: log-likelihood never decreases"       dm7_em_is_a_motion
    , check "DM8 trichotomy from Bayer extrema {1/32, 31/32} only"     dm8_dither_trichotomy
    , check "DM9 BIC: bimodal ⇒ two phases, unimodal ⇒ one"            dm9_degenerate
    , check "DM10 derived EMA gain: flicker⇒0, walk⇒1, blends interior" dm10_derived_alpha
    , check "DM11 rung-16 τ-lift: total-variance identity recovers (s*, τ)" dm11_tau_lift
    , check "DM12 lift dominance: naive gap grows, lifted gap bounded"  dm12_lift_dominance
    ]
  if and results then exitSuccess else exitFailure
