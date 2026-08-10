-- ════════════════════════════════════════════════════════════════
-- Dissonance: the Plomp–Levelt/Sethares kernel, once — the
-- domain-free object under SpectralPalette (quantization port),
-- the depth cadence (temporal port), and the set list (harmony
-- port). DISSONANCE WOVEN: octaves → color, depth → urgency, the
-- archive as a live set.
--
-- THEORY (Helmholtz 1875 → Fletcher 1940 → Plomp & Levelt 1965,
-- JASA 38, 548–560 → Sethares 1993, JASA 94(3)): roughness of two
-- weighted components p₁ = (pos₁,w₁), p₂ = (pos₂,w₂) on a
-- perceptual axis with local resolution field CB(·) is
--
--     x = x* · Δ(pos₁,pos₂) / CB(pos_min)
--     d(p₁,p₂) = w₁·w₂ · g(x),   g(x) = e^(−b1·x) − e^(−b2·x)
--
-- Helmholtz's fixed ~33 Hz max-roughness constant was WRONG; the
-- critical band (Fletcher) replaces it: max dissonance at roughly
-- a QUARTER of a critical bandwidth, frequency-dependent (P&L).
-- Unison is silent; widely-spaced components are never dissonant —
-- the dissonant region is a bump, not a wall. A timbre is a finite
-- weighted multiset; D(T) = Σ_{i<j} d(pᵢ,pⱼ); DESIGN = local
-- minimization of D over an interval action. Sethares is a
-- perceptually-weighted error metric — CIEDE2000 FOR THE EAR — and
-- scale design = minimization over the summed metric: the same
-- shape as palette optimization over a perceptual color distance.
--
-- KERNEL PROVENANCE (pinned, do not re-litigate): b1 = 3.51 (the
-- reference-implementation constant — NOT the brief's 3.5),
-- b2 = 5.75, x* = 0.24, s1 = 0.0207, s2 = 18.96 — verbatim from
-- Sethares' reference implementation (aatishb.com/dissonance,
-- dissonance-worker.js; constants verbatim — that implementation,
-- like the book, combines amplitudes by min(w₁,w₂)). This spec pins
-- PRODUCT w₁·w₂ (the 1993 JASA form; exact bilinearity) and notes
-- min as an accepted alternative (degree-1 homog., moves no minimum).
-- The true peak sits at x̂ = ln(b2/b1)/(b2−b1) = 0.220350, an
-- honest 8% below Sethares' nominal x* = 0.24 (DS3).
--
-- THE SIX-SLOT ARCHITECTURE: g never mentions time, color, or Hz.
-- A port fills three slots — POSITION, LOCAL RESOLUTION CB(·),
-- WEIGHT — and inherits every kernel law:
--
--   port          │ position   │ CB(·)              │ weight
--   ──────────────┼────────────┼────────────────────┼──────────
--   quantization  │ Hz (chart) │ s1·f + s2          │ occupancy
--   temporal      │ cadence ν  │ ν_min (σ shipped)  │ depth mass
--   harmony (ear) │ Hz (chart) │ s1·f + s2          │ occupancy
--   harmony (eye) │ CIELAB     │ 1 + 0.045·C_min    │ occupancy
--
-- THE MERGED URGENCY (the load-bearing amendment): the tuned
-- constant s_t of SpectralPalette SP11 is DELETED. The critical
-- band of the epoch axis is the shipped cadence width itself:
-- x_uv = x*·((2−d_min)/(2−d_max) − 1). Because σ spans exactly one
-- octave (BinomialCadence: σ(d) = (63/8)·(2−d)), full near/far
-- contrast lands at x = x* EXACTLY and g(x*)/g(x̂) = 0.9963 — the
-- quarter-critical-band roughness peak as a THEOREM of shipped
-- constants (DS12); companion: Δc = 2σ_base ⇒ the far pole's own
-- epoch spread rides x* exactly. Nothing is tuned. Sign is the
-- decreed reading: FAR = volatile = urgent halo, NEAR = stable
-- tonic subject (CD4/CD5).
--
-- DIP-SURVIVAL DISCIPLINE (DS7, enforced per port): every port
-- states WHICH consonances survive at its declared CB field — a
-- coarse-resolution port may lawfully hear only {3/2, 2/1} (the
-- bass-ear rule) and must say so. The reference field s1·f + s2
-- with all five constants is the pinned baseline.
--
-- F0-LOCK (DS15): the byte-locked container (64 frames × 5 cs =
-- 320 cs, NETSCAPE loop) forces every export onto the fundamental
-- F0 = 100/320 = 5/16 Hz exactly; the rung rates 5/10/20 Hz are
-- harmonics 16/32/64 of the loop. Every archive is intrinsically a
-- harmonic scale on one fundamental — the set-as-scale is lawful,
-- not imposed. Archive edges carry the dyad (X_ear, χ_eye): the
-- structural rhyme in one tuple. The dramaturgy peak P(n) = ⌈2n/3⌉
-- is a NAMED DESIGN PARAMETER (theater convention), retunable by
-- decree only — explicitly NOT psychophysics (DS16).
--
-- DECREE SCOPE (strict byte posture): closed-form MEASUREMENT +
-- TABLE/INDEX CHOICE + archive metadata + ordering only. No new
-- GIF byte until a decreed contract amendment (the SPECTRUM v1
-- STATS line is HELD). Trains nothing (★NO-CAPTURE-TRAINING), adds
-- no UI (SIMPLICITY), replaces nothing (DyadHarmony's Ou & Luo
-- keeps riding every export). PRE-PORT GATE: the chroma-gain law
-- (1 + κ·Ū) must be authored as a DS17 section and pass green
-- before any Swift touches tables; κ is Daniel's.
-- ════════════════════════════════════════════════════════════════

module Dissonance where

import Data.List (permutations, sort)
import Data.Ratio ((%))

-- ════════════════════════════════════════════════════════════════
-- § 1. THE KERNEL (all constants pinned; the domain-free core)
-- ════════════════════════════════════════════════════════════════

b1, b2, xStar, s1, s2 :: Double
b1    = 3.51                      -- reference impl; NOT the brief's 3.5
b2    = 5.75
xStar = 0.24
s1    = 0.0207
s2    = 18.96

-- | The dimensionless shape: zero at 0 and ∞, one interior peak.
gK :: Double -> Double
gK x = exp (-b1 * x) - exp (-b2 * x)

-- | Closed-form peak location and height.
xHat :: Double
xHat = log (b2 / b1) / (b2 - b1)

-- | Audio critical-band scaling: x = s(f_min)·Δf, CB = s1·f+s2 Hz.
sOf :: Double -> Double
sOf fMin = xStar / (s1 * fMin + s2)

-- | A partial on the audio axis: (frequency Hz, weight ≥ 0).
type Partial = (Double, Double)

-- | The pair kernel d(p,q) = w₁w₂·g(s(f_min)·Δf).
dK :: Partial -> Partial -> Double
dK (f1, a1) (f2, a2) = a1 * a2 * gK (sOf (min f1 f2) * abs (f2 - f1))

-- | Summed intrinsic dissonance: all unordered pairs.
dPairs :: [Partial] -> Double
dPairs ps = sum [ dK p q | (i, p) <- zip [0 :: Int ..] ps
                         , (j, q) <- zip [0 ..] ps, i < j ]

-- | Cross-term between two spectra (every p meets every q).
xTerm :: [Partial] -> [Partial] -> Double
xTerm ps qs = sum [ dK p q | p <- ps, q <- qs ]

-- ════════════════════════════════════════════════════════════════
-- § 2. DETERMINISTIC PSEUDO-RANDOMNESS (house LCG, no System.Random)
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

-- ════════════════════════════════════════════════════════════════
-- § 3. QUANTIZATION PORT — the 4:5:6 octave chart
-- ════════════════════════════════════════════════════════════════

harmonics :: [Integer]            -- (m_R, m_G, m_B): the just triad
harmonics = [4, 5, 6]

fFund :: Integer                  -- Hz; puts m_R·f0 at P&L's 500 Hz
fFund = 125

-- | Exact integer frequency of channel harmonic m, level ℓ.
freqI :: Integer -> Integer -> Integer
freqI m l = m * fFund * 2 ^ l

freqs12 :: [Double]
freqs12 = [ fromInteger (freqI m l) | m <- harmonics, l <- [0 .. 3] ]

-- | The constant kernel matrix G (zero diagonal, symmetric, ≥ 0) —
-- a compile-time constant in the Swift port (DissonanceKernel).
gMat :: [[Double]]
gMat = [ [ if fi == fj then 0
           else gK (sOf (min fi fj) * abs (fj - fi))
         | fj <- freqs12 ] | fi <- freqs12 ]

-- | D as a quadratic form in the occupancy 12-vector: ½·aᵀG·a.
quadD :: [Double] -> Double
quadD a = 0.5 * sum (zipWith (*) a (map (dot a) gMat))
  where dot u v = sum (zipWith (*) u v)

-- | Cross-dissonance as the bilinear pairing a₁ᵀG·a₂ — X_ear.
bilinX :: [Double] -> [Double] -> Double
bilinX a bb = sum (zipWith (*) a (map (dot bb) gMat))
  where dot u v = sum (zipWith (*) u v)

spectrum :: [Double] -> [Partial]
spectrum = zip freqs12

-- | Witness frame: 4096 chromatic triples, levels 0..3, from a warp
-- of the LCG stream (id = flat, (**3) = skewed dark).
witnessLevels :: (Double -> Double) -> Int -> ([Int], [Int], [Int])
witnessLevels warp seed = (as, bs, cs)
  where
    ls = take (3 * 4096)
           [ min 3 (floor (warp u * 4)) | u <- uniforms seed ]
    (as, rest) = splitAt 4096 ls
    (bs, cs)   = splitAt 4096 rest

-- | Exact integer level marginals per channel (the u64 carrier).
countsOf :: [Int] -> [Integer]
countsOf xs = [ fromIntegral (length (filter (== l) xs)) | l <- [0 .. 3] ]

-- | Occupancy 12-vector (channel-major) of a witness frame.
ampsOf :: (Double -> Double) -> Int -> [Double]
ampsOf warp seed =
  concat [ map ((/ 4096) . fromInteger) (countsOf ch)
         | ch <- [as, bs, cs] ]
  where (as, bs, cs) = witnessLevels warp seed

uniformAmps :: [Double]
uniformAmps = concat (replicate 3 (replicate 4 0.25))

-- ── Tuning: guarded sequential detune (scale design = table choice)

gridN :: Int                      -- 1/1200 octave = 0.3° of hue
gridN = 1200

betaOf :: Int -> Double
betaOf k = 2 ** (fromIntegral k / fromIntegral gridN)

combP :: Integer -> Double -> [Double] -> [Partial]
combP m beta amps =
  [ (fromInteger (m * fFund) * beta * 2 ^ l, a)
  | (l, a) <- zip [0 .. 3 :: Integer] amps ]

frac1 :: Double -> Double
frac1 x = x - fromIntegral (floor x :: Integer)

classAt :: Integer -> Int -> Double
classAt m k =
  frac1 (logBase 2 (fromInteger m) + fromIntegral k / fromIntegral gridN)

circDist :: Double -> Double -> Double
circDist p q = min dd (1 - dd) where dd = abs (frac1 (p - q))

curveOf :: [Partial] -> Integer -> [Double] -> [(Double, Int)]
curveOf placed m amps =
  [ (xTerm placed (combP m (betaOf k) amps), k) | k <- [0 .. gridN - 1] ]

localMins :: [(Double, Int)] -> [Int]
localMins pts =
  [ k1 | ((v0, _), (v1, k1), (v2, _)) <- zip3 pts (tail pts) (drop 2 pts)
       , v1 < v0, v1 < v2 ]

guardGamma :: Double              -- forbid hue collapse: ≥ 1 semitone
guardGamma = 1 / 12

guardedArgmin :: [Double] -> Integer -> [(Double, Int)] -> Int
guardedArgmin placedClasses m pts =
  snd (minimum [ (v, k) | (v, k) <- pts
               , k `elem` localMins pts
               , all (\q -> circDist (classAt m k) q >= guardGamma)
                     placedClasses ])

-- | The per-loop tuning: δ_G* then δ_B*, as 1/1200-octave indices.
designTuning :: [Double] -> (Int, Int)
designTuning amps12 = (kG, kB)
  where
    [aR, aG, aB] = [ take 4 (drop (4 * c) amps12) | c <- [0 .. 2] ]
    rComb  = combP 4 1 aR
    kG     = guardedArgmin [0] 5 (curveOf rComb 5 aG)
    placed = rComb ++ combP 5 (betaOf kG) aG
    kB     = guardedArgmin [0, classAt 5 kG] 6 (curveOf placed 6 aB)

-- ── Pitch class → hue (octave equivalence is the hue circle)

pitchClass :: Double -> Double
pitchClass f = frac1 (logBase 2 (f / fromInteger fFund))

tritone :: Double -> Double
tritone q = frac1 (q + 0.5)

chordVec :: (Int, Int, Int) -> (Double, Double)
chordVec (a, bl, c) =
  ( sum [ w * cos (th m) | (w, m) <- zip ws harmonics ]
  , sum [ w * sin (th m) | (w, m) <- zip ws harmonics ] )
  where
    ws   = map (2 ^^) [a, bl, c]
    th m = 2 * pi * frac1 (logBase 2 (fromInteger m))

chordHue :: (Int, Int, Int) -> Double
chordHue ch = let (vx, vy) = chordVec ch
                  h = atan2 vy vx * 180 / pi
              in if h < 0 then h + 360 else h

chordResultant :: (Int, Int, Int) -> Double
chordResultant ch@(a, bl, c) =
  let (vx, vy) = chordVec ch
  in sqrt (vx * vx + vy * vy) / sum (map (2 ^^) [a, bl, c])

hueDist :: Double -> Double -> Double
hueDist h1 h2 = min dd (360 - dd) where dd = abs (h1 - h2)

-- ════════════════════════════════════════════════════════════════
-- § 4. TEMPORAL PORT — depth → urgency, merged form (no s_t)
-- ════════════════════════════════════════════════════════════════

-- | BinomialCadence, shipped: σ_base = 63/8, σ(d) = σ_base·(2−d),
-- epoch centers c_e = (2e+1)·63/8, adjacent gap Δc = 2σ_base.
sigmaBase, centerGap :: Double
sigmaBase = 63 / 8
centerGap = 63 / 4

sigmaOf :: Double -> Double
sigmaOf d = sigmaBase * (2 - d)

-- | The bond coordinate: CB slot = the FARTHER voxel's own cadence
-- bandwidth (ν_min, mirroring f_min). ν ∝ 1/σ, so
-- x = x*·Δν/ν_min = x*·(σ_max/σ_min − 1) — unit-free, no s_t.
xBond :: Double -> Double -> Double
xBond dA dB = xStar * ((2 - dMin) / (2 - dMax) - 1)
  where dMin = min dA dB
        dMax = max dA dB

-- | Urgency of a rung-16 voxel bond: weights = exact depth-mass
-- block sums (cast), roughness of the cadence beat.
urgBond :: Double -> Double -> Double -> Double -> Double
urgBond w1 w2 dA dB = w1 * w2 * gK (xBond dA dB)

-- | Witness loop scalar Ū: full-field contrast against the near
-- tonic (d = 1). FAR = volatile = urgent (CD4/CD5 decreed sign).
uBar :: Double -> Double
uBar d = urgBond 1 1 d 1

-- | The urgency lattice at depth's native rung (TL9): 16×16×16,
-- 4-neighbor spatial bonds per slice + time-wrapped temporal bonds
-- (the NETSCAPE loop closes time into a torus).
urgencyBonds :: [((Int, Int, Int), (Int, Int, Int))]
urgencyBonds =
  [ ((t, y, x), (t, y, x + 1)) | t <- r, y <- r, x <- init r ]
    ++ [ ((t, y, x), (t, y + 1, x)) | t <- r, y <- init r, x <- r ]
    ++ [ ((t, y, x), ((t + 1) `mod` 16, y, x)) | t <- r, y <- r, x <- r ]
  where r = [0 .. 15]

-- ════════════════════════════════════════════════════════════════
-- § 5. HARMONY PORT — F0-lock, the eye kernel, the set list
-- ════════════════════════════════════════════════════════════════

-- | The loop fundamental, exact: 100 cs/s over 320 cs.
f0 :: Rational
f0 = 100 % 320

-- | Rung frame rate as a Rational: 100/(320/side) = side·F0.
rungRate :: Integer -> Rational
rungRate side = fromInteger side * f0

-- | A color partial: CIELAB position + occupancy weight.
type CPartial = ((Double, Double, Double), Double)

deltaE :: (Double, Double, Double) -> (Double, Double, Double) -> Double
deltaE (l1, a1, bb1) (l2, a2, bb2) =
  sqrt ((l1-l2)^(2::Int) + (a1-a2)^(2::Int) + (bb1-bb2)^(2::Int))

chromaOf :: (Double, Double, Double) -> Double
chromaOf (_, a, bb) = sqrt (a*a + bb*bb)

-- | The eye's resolution slot: CIEDE2000's S_C with C_min playing
-- f_min (the less-saturated member sets the local JND).
cbColor :: Double -> Double
cbColor cmin = 1 + 0.045 * cmin

dEye :: CPartial -> CPartial -> Double
dEye (p, w1) (q, w2) =
  w1 * w2 * gK (xStar * deltaE p q / cbColor (min (chromaOf p) (chromaOf q)))

-- | χ_eye: normalized cross-term — the eye-side dual on every
-- archive edge; the edge dyad is (X_ear, χ_eye).
chiEye :: [CPartial] -> [CPartial] -> Double
chiEye ls ms = sum [ dEye i j | i <- ls, j <- ms ] / (wTot ls * wTot ms)
  where wTot = sum . map snd

-- | Deterministic witness color timbre: 16 CIELAB partials.
cWitness :: Int -> [CPartial]
cWitness seed = take 16
  [ ((20 + 60 * u, 80 * v - 40, 80 * w - 40), 0.5 + t)
  | (u, v, w, t) <- quads (uniforms seed) ]
  where quads (a:bq:c:d:rest) = (a, bq, c, d) : quads rest
        quads _               = []

-- ── The set list (dramaturgy over the archive)

-- | Witness archive: 6 loops = (occupancy 12-vector, witness Ū).
archive :: [([Double], Double)]
archive = zip vecs (map uBar depths)
  where
    vecs   = [ ampsOf wf sd | (wf, sd) <- zip warps [1 ..] ]
    warps  = [ id, (** 3), sqrt, (** 2), (** 0.75), (** 1.5) ]
    depths = [ 0.9, 0.2, 0.5, 0.0, 0.7, 0.35 ]

-- | THE DRAMATURGY PEAK — DESIGN PARAMETER (theater convention),
-- retunable by decree only; explicitly NOT psychophysics.
peakPos :: Int -> Int             -- 1-based P(n) = ⌈2n/3⌉
peakPos n = ceiling (2 * fromIntegral n / 3 :: Double)

-- | Strictly unimodal with peak exactly at 0-based position p.
unimodalAt :: Int -> [Double] -> Bool
unimodalAt p us =
     and (zipWith (<) rise (tail rise))
  && and (zipWith (>) fall (tail fall))
  where rise = take (p + 1) us
        fall = drop p us

choose :: Integer -> Integer -> Integer
choose n k = product [n - k + 1 .. n] `div` product [1 .. k]

-- | Feasible orders and the transition-consonance argmin (Σ X_ear).
setList :: [([Double], Double)] -> ([[Int]], [Int], Double, Double)
setList loops = (feasible, best, bestCost, margin)
  where
    n        = length loops
    p0       = peakPos n - 1                       -- 0-based
    feasible = [ q | q <- permutations [0 .. n-1]
                   , unimodalAt p0 (map (snd . (loops !!)) q) ]
    cost q   = sum (zipWith xE q (tail q))
    xE i j   = bilinX (fst (loops !! i)) (fst (loops !! j))
    costs    = sort (map cost feasible)
    best     = snd (minimum [ (cost q, q) | q <- feasible ])
    bestCost = head costs
    margin   = costs !! 1 - head costs

-- ════════════════════════════════════════════════════════════════
-- § 6. AXIOMS  (verification: [E] exact, [P·tol] pinned numeric,
--               [G·step] grid with step-bound)
-- ════════════════════════════════════════════════════════════════

tol :: Double
tol = 1e-12

-- (DS1) UNISON ZERO, SILENT TAIL [E + P·1e-12]: g(0) = 0 exactly;
--       g strictly decreasing past x̂ (grid 10⁻³); g(8) < 10⁻¹².
--       Coincident and widely-spaced components are both consonant
--       — dissonance is a bump, not a wall.
axiom_DS1 :: Bool
axiom_DS1 =
     gK 0 == 0
  && gK 8 < tol
  && and [ gK x > gK (x + h) | let h = 1e-3
         , x <- [ xHat + h * fromIntegral k | k <- [0 .. 9779 :: Int] ] ]

-- (DS2) ONE INTERIOR PEAK, CLOSED FORM [P·1e-6 + G·1e-3]:
--       x̂ = ln(b2/b1)/(b2−b1) = 0.220350; g(x̂) = 0.179756;
--       exactly one sign change of g′ on [0,10]. Header states
--       b1 = 3.51 (the code constant), not the brief's 3.5.
axiom_DS2 :: Bool
axiom_DS2 =
     abs (xHat - 0.220350) < 1e-6
  && abs (gK xHat - 0.179756) < 1e-6
  && signChanges == 1
  where
    g' x = -b1 * exp (-b1 * x) + b2 * exp (-b2 * x)
    xs = [ 1e-3 * fromIntegral k | k <- [0 .. 10000 :: Int] ]
    signChanges = length [ () | (x0, x1) <- zip xs (tail xs)
                              , g' x0 > 0, g' x1 <= 0 ]

-- (DS3) QUARTER-CB HONESTY [P·1e-3]: x̂/x* = 0.918 — the true peak
--       sits 8% below Sethares' nominal x*; stated, not re-litigated.
axiom_DS3 :: Bool
axiom_DS3 = abs (xHat / xStar - 0.918) < 1e-3
         && xHat < xStar

-- (DS4) BILINEAR, SYMMETRIC [P·1e-12 + E]: d(λw₁, μw₂) = λμ·d;
--       d(p,q) = d(q,p) exactly. Product amplitude form pinned;
--       min-variant (degree-1 homogeneous) noted in the header.
axiom_DS4 :: Bool
axiom_DS4 =
     abs (dK (500, 2) (620, 3) - 6 * dK (500, 1) (620, 1)) < tol
  && dK (500, 0.7) (620, 0.4) == dK (620, 0.4) (500, 0.7)

-- (DS5) QUADRATIC FORM, POLARIZATION [P·1e-12]: pair-summed D
--       equals ½·aᵀG·a; D(a₁+a₂) = D(a₁) + D(a₂) + a₁ᵀG·a₂;
--       D(λa) = λ²·D(a). Merging loops decomposes exactly.
axiom_DS5 :: Bool
axiom_DS5 =
     abs (dPairs (spectrum a1) - quadD a1) < tol
  && abs (quadD (zipWith (+) a1 a2)
          - quadD a1 - quadD a2 - bilinX a1 a2) < tol
  && abs (quadD (map (* 3) a1) - 9 * quadD a1) < tol
  where
    a1 = ampsOf id 1
    a2 = ampsOf (** 3) 2

-- (DS6) THE HARMONIC-DIP LAW [G·5e-4]: witness 500 Hz, 7 partials,
--       amps 0.88^(k−1); D_T(α) on [1, 2.3] has a strict local
--       minimum within 0.01 of each of 6/5, 5/4, 4/3, 3/2, 5/3,
--       2/1, and depths recover the classical ranking
--       D(2/1) < D(3/2) < D(5/3) < D(4/3) < D(5/4) < D(6/5).
--       Extra 7-limit dips (7/6, 7/5, 7/4) permitted, not excluded.
axiom_DS6 :: Bool
axiom_DS6 =
     all (\r -> any (\al -> abs (al - r) < 0.01) (minsOf tim7)) ratios6
  && and (zipWith (<) rankVals (tail rankVals))
  where
    rankVals = map (valNear tim7) [ 2/1, 3/2, 5/3, 4/3, 5/4, 6/5 ]

-- shared dip machinery (DS6/DS7)
tim7, tim3 :: [Partial]
tim7 = [ (500 * fromIntegral k, 0.88 ^^ (k - 1)) | k <- [1 .. 7 :: Int] ]
tim3 = [ (500 * fromIntegral k, 0.88 ^^ (k - 1)) | k <- [1 .. 3 :: Int] ]

ratios6 :: [Double]
ratios6 = [ 6/5, 5/4, 4/3, 3/2, 5/3, 2/1 ]

dipPts :: [Partial] -> [(Double, Double)]
dipPts tim = [ (dCurve al, al) | al <- grid ]
  where
    dCurve al = dPairs (tim ++ [ (al * f, a) | (f, a) <- tim ])
    grid = [ 1 + 5e-4 * fromIntegral k | k <- [0 .. 2600 :: Int] ]

minsOf :: [Partial] -> [Double]
minsOf tim = [ al | ((v0, _), (v1, al), (v2, _))
                      <- zip3 pts (tail pts) (drop 2 pts)
                  , v1 < v0, v1 < v2 ]
  where pts = dipPts tim

valNear :: [Partial] -> Double -> Double
valNear tim r = minimum [ v | (v, al) <- dipPts tim, abs (al - r) < 0.01 ]

-- (DS7) DIP-SURVIVAL DISCIPLINE [rule + G·5e-4]: which dips survive
--       depends on the timbre and the CB field, and every port must
--       say which. The bass-ear witness: the 3-partial timbre hears
--       ONLY {3/2, 2/1} — no dip survives near 6/5, 5/4, 4/3, 5/3.
--       Baseline field constants pinned literally.
axiom_DS7 :: Bool
axiom_DS7 =
     all (\r -> any (\al -> abs (al - r) < 0.01) mins3) [ 3/2, 2/1 ]
  && all (\r -> not (any (\al -> abs (al - r) < 0.01) mins3))
         [ 6/5, 5/4, 4/3, 5/3 ]
  && (s1, s2, xStar, b1, b2) == (0.0207, 18.96, 0.24, 3.51, 5.75)
  where mins3 = minsOf tim3

-- (DS8) THE CHART IS EXACT [E]: 12 pinned integer frequencies;
--       intra-channel steps exact octaves; level-aligned cross-
--       channel ratios exactly 5:4, 6:5, 3:2 by integer cross-
--       multiplication; occupancy marginals are exact integer
--       counts, 4096/channel/frame, 262144/channel/loop.
axiom_DS8 :: Bool
axiom_DS8 =
     [ freqI m l | m <- harmonics, l <- [0 .. 3] ]
       == [ 500, 1000, 2000, 4000, 625, 1250, 2500, 5000
          , 750, 1500, 3000, 6000 ]
  && and [ freqI m (l + 1) == 2 * freqI m l
         | m <- harmonics, l <- [0 .. 2] ]
  && and [ 4 * freqI 5 l == 5 * freqI 4 l
        && 5 * freqI 6 l == 6 * freqI 5 l
        && 2 * freqI 6 l == 3 * freqI 4 l | l <- [0 .. 3] ]
  && all (\sd -> let (as, bs, cs) = witnessLevels id sd
                 in all ((== 4096) . sum . countsOf) [as, bs, cs])
         [1, 2, 3]
  && (64 * 4096 :: Integer) == 262144

-- (DS9) TUNING, PINNED AND TIMBRE-DEPENDENT [G·1/1200]: uniform
--       occupancy → (δG*, δB*) = (269, 836)/1200 under the 1/12
--       guard; δ = 0 (just 4:5:6) is NOT a resting point; the
--       dark-skew witness (u³, seed 2) moves δG* to 325 — 56 grid
--       steps ≈ 17° of hue. THE PUNCHLINE AS AXIOM: consonance
--       depends on the timbre; no fixed palette fits every image.
axiom_DS9 :: Bool
axiom_DS9 =
     designTuning uniformAmps == (269, 836)
  && fst (gCurveU !! 1) < fst (head gCurveU)
  && skewG == 325
  && skewG - 269 == 56
  && abs (56 / 1200 * 360 - 16.8) < 0.1
  where
    aU = replicate 4 0.25
    gCurveU = curveOf (combP 4 1 aU) 5 aU
    skew = ampsOf (** 3) 2
    [sR, sG] = [ take 4 (drop (4 * c) skew) | c <- [0, 1] ]
    skewG = guardedArgmin [0] 5 (curveOf (combP 4 1 sR) 5 sG)

-- (DS10) TRITONE = INVOLUTION [E + P·1e-9]: pitch class is level-
--        invariant across all four octaves; the σ-involution is
--        q ↦ q+½ (hue+180°), tritone² = id = σ∘σ; the chart colors
--        the 128 σ-representatives only — partners 255−i derive.
--        The byte contract as a theorem.
axiom_DS10 :: Bool
axiom_DS10 =
     and [ abs (pc m l - pc m 0) < 1e-9 | m <- harmonics, l <- [0 .. 3] ]
  && all (\q -> abs (tritone (tritone q) - q) < tol) [ 0, 0.1, 0.32, 0.9 ]
  && all (\q -> abs (hueDist (360 * tritone q) (360 * q) - 180) < 1e-9)
         [ 0, 0.2, 0.585 ]
  && length reps == 128
  && sort (reps ++ map (255 -) reps) == [0 .. 255 :: Int]
  where
    pc m l = pitchClass (fromInteger (freqI m l))
    reps   = [0 .. 127]

-- (DS11) CHORD HUE [P·4° + 1e-9]: a channel-dominant chord pulls
--        hue to that channel's class within 4° (2^ℓ weighting);
--        grays a=b=c keep circular resultant in (0.16, 0.17) —
--        low chroma, never zero — and all grays share one hue.
axiom_DS11 :: Bool
axiom_DS11 =
     hueDist (chordHue (3, 0, 0)) (360 * pitchClass 500) < 4
  && hueDist (chordHue (0, 3, 0)) (360 * pitchClass 625) < 4
  && hueDist (chordHue (0, 0, 3)) (360 * pitchClass 750) < 4
  && all (\l -> let r = chordResultant (l, l, l)
                in r > 0.16 && r < 0.17) [ 0, 1, 2, 3 ]
  && abs (chordHue (0, 0, 0) - chordHue (3, 3, 3)) < 1e-9

-- (DS12) DERIVED CALIBRATION [E + P·1e-3] — s_t DELETED: the CB of
--        the epoch axis is the shipped σ(d) itself. Full near/far
--        contrast lands at x = x* EXACTLY (σ ratio 2 is dyadic);
--        g(x*)/g(x̂) = 0.9963 — the quarter-CB roughness peak as a
--        theorem of BinomialCadence's constants. Companion (SD7):
--        Δc = 2σ_base ⇒ the far pole's own epoch spread rides
--        x*·Δc/σ(0) = x* exactly. No free constants.
axiom_DS12 :: Bool
axiom_DS12 =
     xBond 0 1 == xStar
  && abs (gK xStar / gK xHat - 0.9963) < 1e-4
  && sigmaOf 0 == 2 * sigmaOf 1
  && centerGap == 2 * sigmaBase
  && xStar * (centerGap / sigmaOf 0) == xStar

-- (DS13) URGENCY LAWS [E + G·1e-3 + P·1e-12]: U = 0 at equal depth
--        exactly; the bond coordinate x is strictly monotone in
--        depth contrast everywhere, and U is strictly monotone up
--        to the peak-crossing depth d̂ = 2 − 2/(1 + x̂/x*) = 0.9573
--        (HONESTY: full contrast x = x* overshoots the peak x̂ by
--        8% in x — DS3 — but the terminal dip is bounded by DS12's
--        theorem: U(full) ≥ 99.6% of the lattice maximum g(x̂));
--        bilinear in masses; near-field asymmetry — the same depth
--        GAP beats rougher in the near field (σ finer there).
axiom_DS13 :: Bool
axiom_DS13 =
     all (\d -> urgBond 1 1 d d == 0) [ 0, 0.25, 0.5, 0.75, 1 ]
  && and [ xBond 0 d < xBond 0 (d + h)
         | d <- [ h * fromIntegral k | k <- [0 .. 999 :: Int] ] ]
  && abs (dHat - 0.9573) < 1e-4
  && and [ urgBond 1 1 0 d < urgBond 1 1 0 (d + h)
         | d <- [ h * fromIntegral k | k <- [0 .. 956 :: Int] ] ]
  && urgBond 1 1 0 1 / gK xHat > 0.996
  && abs (urgBond 2 3 0 1 - 6 * urgBond 1 1 0 1) < tol
  && urgBond 1 1 0.5 1 > urgBond 1 1 0 0.5
  where
    h    = 1e-3
    dHat = 2 - 2 / (1 + xHat / xStar)

-- (DS14) THE URGENCY CLOCK [E] (TL9 restated): 16³ = 4096
--        judgments per 320 cs loop at 5 Hz; 64 draws per judgment
--        (= 64³); exactly 11776 bonds = 16 slices × 480 spatial
--        4-neighbor + 4096 time-wrapped temporal (NETSCAPE torus).
axiom_DS14 :: Bool
axiom_DS14 =
     (16 :: Integer) ^ (3 :: Int) == 4096
  && (100 :: Integer) `div` (320 `div` 16) == 5
  && ((64 :: Integer) `div` 16) ^ (3 :: Int) == 64
  && 64 ^ (3 :: Int) == 4096 * (64 :: Integer)
  && length urgencyBonds == 11776
  && length urgencyBonds == 16 * 480 + 4096

-- (DS15) F0-LOCK + CROSS-LOOP ALGEBRA [E + P·1e-12]: F0 = 5/16 Hz
--        exact; the rung rates 5/10/20 Hz are harmonics 16/32/64 of
--        the loop — every archive is a harmonic scale on one
--        fundamental. X_ear symmetric, bilinear, X(T,T) = 2·D(T);
--        χ_eye symmetric, bilinear in occupancy, zero at coincident
--        colors, bounded by g(x̂). The edge dyad is (X_ear, χ_eye).
axiom_DS15 :: Bool
axiom_DS15 =
     f0 == 5 % 16
  && map rungRate [16, 32, 64] == [5, 10, 20]
  && abs (xTerm (spectrum w1) (spectrum w2) - bilinX w1 w2) < tol
  && abs (bilinX w1 w2 - bilinX w2 w1) < tol
  && abs (bilinX w1 w1 - 2 * quadD w1) < tol
  && dEye cp cq == dEye cq cp
  && abs (dEye (fst cp, 2) (fst cq, 3) - 6 * dEye (fst cp, 1) (fst cq, 1))
       < tol
  && dEye cp (fst cp, 5) == 0
  && cSelf >= 0 && cSelf < gK xHat
  where
    w1 = ampsOf id 1
    w2 = ampsOf (** 3) 2
    cp = ((55, 30, -10), 1.5)
    cq = ((40, -20, 25), 0.7)
    cSelf = chiEye (cWitness 5) (cWitness 5)

-- (DS16) THE SETLIST EXISTS, IS DETERMINISTIC [E + P·1e-9]: the
--        6-loop witness archive has exactly C(n−1, P(n)−1) = 10
--        strictly urgency-unimodal orders peaking at P(6) = 4, and
--        a UNIQUE argmin of Σ X_ear with margin > 10⁻⁹.
--        P(n) = ⌈2n/3⌉ is a DESIGN PARAMETER (theater convention),
--        retunable by decree only — explicitly NOT psychophysics.
axiom_DS16 :: Bool
axiom_DS16 =
     peakPos 6 == 4
  && length feasible == 10
  && fromIntegral (length feasible) == choose 5 3
  && margin > 1e-9
  && unimodalAt 3 (map (snd . (archive !!)) best)
  where (feasible, best, _, margin) = setList archive

-- ════════════════════════════════════════════════════════════════
-- § 7. MAIN
-- ════════════════════════════════════════════════════════════════

check :: String -> [Bool] -> IO ()
check name results =
  let mark = if and results then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " Dissonance: the P&L/Sethares kernel, once — three ports"
  putStrLn " octaves → color · depth → urgency · archive = live set"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  port         │ position │ CB(·)           │ weight"
  putStrLn "  ─────────────┼──────────┼─────────────────┼───────────"
  putStrLn "  quantization │ Hz chart │ s1·f + s2       │ occupancy"
  putStrLn "  temporal     │ ν(depth) │ ν_min (σ shipped)│ depth mass"
  putStrLn "  harmony/ear  │ Hz chart │ s1·f + s2       │ occupancy"
  putStrLn "  harmony/eye  │ CIELAB   │ 1 + 0.045·C_min │ occupancy"
  putStrLn ""
  putStrLn $ "  kernel: b1 = " ++ show b1 ++ " (not 3.5), b2 = " ++ show b2
          ++ ", x* = " ++ show xStar
  putStrLn $ "  peak: x̂ = " ++ take 8 (show xHat)
          ++ ", g(x̂) = " ++ take 8 (show (gK xHat))
          ++ ", g(x*)/g(x̂) = " ++ take 6 (show (gK xStar / gK xHat))
  putStrLn $ "  uniform tuning (δG*, δB*) = "
          ++ show (designTuning uniformAmps) ++ " / 1200"
  putStrLn $ "  F0 = " ++ show f0 ++ " Hz; rungs at harmonics 16/32/64"
  let (feas, best, bc, mg) = setList archive
  putStrLn $ "  set list: " ++ show (length feas) ++ " feasible, best = "
          ++ show best ++ ", ΣX = " ++ take 8 (show bc)
          ++ ", margin = " ++ take 8 (show mg)
  putStrLn ""
  check "DS1  unison zero, silent tail (bump, not wall)"          [axiom_DS1]
  check "DS2  one interior peak: x̂ = 0.220350, g(x̂) = 0.179756"  [axiom_DS2]
  check "DS3  quarter-CB honesty: x̂/x* = 0.918"                  [axiom_DS3]
  check "DS4  bilinear in weights, symmetric in the pair"         [axiom_DS4]
  check "DS5  D = ½aᵀGa; polarization; λ² scaling"                [axiom_DS5]
  check "DS6  harmonic-dip law: six dips, classical ranking"      [axiom_DS6]
  check "DS7  dip survival: bass ear hears only {3/2, 2/1}"       [axiom_DS7]
  check "DS8  the chart is exact; occupancy = u64 marginals"      [axiom_DS8]
  check "DS9  tuning pinned (269,836); dark skew → 325 (+17°)"    [axiom_DS9]
  check "DS10 tritone = σ-involution; 128 reps color the chart"   [axiom_DS10]
  check "DS11 chord hue: dominance < 4°; grays low-chroma"        [axiom_DS11]
  check "DS12 derived calibration: full contrast at x*, no s_t"   [axiom_DS12]
  check "DS13 urgency: silent interiors, monotone, near-asym"     [axiom_DS13]
  check "DS14 urgency clock: 16³ @ 5 Hz, 11776 torus bonds"       [axiom_DS14]
  check "DS15 F0-lock 5/16 Hz; edge dyad (X_ear, χ_eye) lawful"   [axiom_DS15]
  check "DS16 setlist: C(5,3) = 10 feasible, unique argmin"       [axiom_DS16]
  putStrLn ""
  putStrLn "  One kernel, three ports. The palette is the timbre;"
  putStrLn "  depth boundaries beat; the archive is a scale on one"
  putStrLn "  fundamental. Strict byte posture: no new GIF byte —"
  putStrLn "  tables, indices, archive metadata, ordering only."
  putStrLn "  Trains nothing (★NO-CAPTURE-TRAINING). DS17 (chroma"
  putStrLn "  gain) is the gated pre-port section, not yet law."
