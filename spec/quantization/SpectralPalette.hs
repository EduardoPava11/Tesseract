-- ════════════════════════════════════════════════════════════════
-- SpectralPalette: Sethares consonance for the 4⁴ lattice
--
-- THE SPECTRAL-PALETTE READING. The image's palette occupancy
-- spectrum IS a timbre. The 4⁴ index (d,a,b,c) — TesseractCoord —
-- splits into the CHROMATIC chord (a,b,c) and the CADENCE axis d:
--
--   · Each RGB channel is a 4-rung OCTAVE COMB: level ℓ ∈ 0..3 of
--     channel X sounds at  f(X,ℓ) = m_X · 125 Hz · 2^ℓ  with
--     harmonic numbers (m_R, m_G, m_B) = (4, 5, 6) — the just triad.
--     Levels ARE the color quanta; doubling of level value = octave.
--   · Amplitudes = occupancy: the per-channel level marginals of the
--     index histogram (exact integer counts / 4096 per frame — the
--     same u64 block-sum carrier as TriScaleLadder; frames at 20 Hz,
--     the loop spectrum = cube marginals / 262144, once per export).
--   · The whole loop is a 12-partial spectrum. Dissonance is the
--     Plomp–Levelt/Sethares kernel summed over all partial pairs —
--     a quadratic form  D = ½·aᵀG·a  in the occupancy 12-vector
--     with a CONSTANT 12×12 kernel matrix G (SP6), the eye's exact
--     sibling of E_pal's closed 9-number form (DyadEnergy.swift).
--
-- SCALE DESIGN = TABLE CHOICE (Sethares' punchline, for color):
-- the free knobs are the channel detunes δ_G, δ_B ∈ [0,1) octaves.
-- Per loop, sequential guarded minimization of the cross-dissonance
-- places the G and B combs at the dissonance minima OF THE LOOP'S
-- OWN OCCUPANCY SPECTRUM (SP8, SP9): consonant tuning depends on
-- the timbre — uniform occupancy tunes to the comb anti-node,
-- skewed occupancy jumps toward comb coincidence. The GUARD
-- (pitch-class distance ≥ 1/12 from every placed comb) is the
-- classical scale-design move: it forbids the trivial deepest
-- consonance, unison/coincidence, which in color is HUE COLLAPSE.
--
-- OCTAVES IN RGB PRODUCE COLOR (SP13, SP14): pitch class
-- q = frac(log₂ f) maps to the hue circle h = 360°·q — octave
-- equivalence IS hue identity. Integer octave number → lightness
-- shell (DyadPalette ladder ρ_k); circular resultant of the chord's
-- three class vectors (weighted 2^ℓ) → hue + chroma; occupancy →
-- shell mass. The tuned classes for uniform occupancy land at
-- {0, 0.546, 0.282} — hues 0°, 197°, 101°. The DYAD involution
-- T[255−i] = comp(T[i]) (hue+180°) is EXACTLY the tritone
-- q ↦ q+½: the σ-pair is the tritone transposition of the chord,
-- and σ∘σ = id ⇔ tritone² = id (SP13). The spectral chart colors
-- only the 128 σ-representatives; complements derive by involution
-- — the pair law of DyadPalette.hs stays the law.
--
-- DEPTH PRODUCES URGENCY (SP10–SP12): the cadence width
-- σ(d) = (63/8)·(2−d) frames (BinomialCadence.swift:57-61) gives
-- each depth a cadence frequency ν(d) = 20/(2π·σ(d)) Hz — near/far
-- is an EXACT OCTAVE (ν(1)/ν(0) = 2, SP10). Urgency between two
-- adjacent rung-16 voxels is the Sethares roughness of their
-- cadence beat:  U = w_u·w_v · g(s_t·|ν_u − ν_v|), weights = depth
-- mass block sums (DyadPipeline.swift:91-93 depths; TriScaleLadder
-- u64 sums). Calibration s_t = x̂/(ν(1)−ν(0)) puts FULL near/far
-- contrast exactly at the roughness peak (SP11): same depth beats
-- not at all, and urgency rises strictly with depth contrast —
-- near/far BOUNDARIES beat fastest. The field lives at depth's
-- native rung (TL9): 16×16×16 voxels per loop, judged at 5 Hz,
-- 11776 bonds (4-neighbor spatial + time-wrapped temporal, the
-- loop is a torus in time) — the same bond skeleton as
-- DyadEnergy's Ising walls.
--
-- A LIVE SET OF LOOPS (SP15): the cross-dissonance of two loops is
-- the bilinear pairing  X(T₁,T₂) = a₁ᵀG·a₂  of their occupancy
-- 12-vectors — computable from bytes alone (DYAD provenance
-- rebuilds tables and stats). D(T₁∪T₂) = D(T₁)+D(T₂)+X(T₁,T₂)
-- exactly (polarization). The archive (MapElites / the 𝔇 phase
-- archive) orders its live set by greedy consonant transitions:
-- next loop = argmin X against the current one; admission favors
-- local minima of ΣX against the set. Two loops "in the same key"
-- share their guarded tuning (δ_G*, δ_B*).
--
-- KERNEL PROVENANCE (pinned, do not re-litigate): b1 = 3.51,
-- b2 = 5.75, x* = 0.24, s1 = 0.0207, s2 = 18.96 — verbatim from
-- Sethares' reference implementation (aatishb.com/dissonance,
-- dissonance-worker.js). Amplitudes combine by PRODUCT a₁·a₂ (the
-- 1993 JASA form) — it gives exact bilinearity (SP3/SP6); the
-- book's min(a₁,a₂) variant would weaken SP6 to homogeneity, and
-- moves no minimum. The display factor C1 = 5 is omitted. The
-- actual peak sits at x̂ = ln(b2/b1)/(b2−b1) = 0.2203, an honest
-- 8% below Sethares' nominal x* = 0.24 (SP2) — a known quirk.
-- s1·f+s2 is the linear critical-band proxy: the JND field of the
-- axis, the CIEDE2000 move (S_L,S_C,S_H) for the ear.
--
-- TESSERACT SCOPE (decree-bound): closed-form MEASUREMENT + TABLE
-- CHOICE only. The container is untouched — 64×64×64 → 256×256 at
-- 5 cs stands byte-locked; only tables (free by contract), and one
-- provenance line change:  "SPECTRUM v1: 12×u32 loop counts,
-- δ_G*,δ_B* u16 grid indices, 16×u8 urgency slice means"  rides
-- the STATS comment so tables stay rebuildable from bytes (DY8).
-- It trains nothing (★NO-CAPTURE-TRAINING), adds no UI
-- (SIMPLICITY), and replaces nothing (iterative): DyadHarmony's
-- Ou & Luo score keeps riding exports; this is the second pair
-- metric on the same summation skeleton (DyadHarmony.swift:98-109).
-- Swift port slots (future, spec-first): hue source for the 128
-- σ-representatives in the DYAD table build; chroma gain
-- 1 + κ·Ū (κ = 1/4, shell-capped); urgency published beside
-- rungTelemetry.
-- ════════════════════════════════════════════════════════════════

module SpectralPalette where

-- ════════════════════════════════════════════════════════════════
-- § 1. THE KERNEL (all constants pinned)
-- ════════════════════════════════════════════════════════════════

b1, b2, xStar, s1, s2 :: Double
b1    = 3.51
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

-- | Critical-band scaling: x = s(f_min)·Δf, CB proxy s1·f+s2 Hz.
sOf :: Double -> Double
sOf fMin = xStar / (s1 * fMin + s2)

-- | A partial: (frequency Hz, amplitude ≥ 0).
type Partial = (Double, Double)

-- | The pair kernel d(p,q) = a₁a₂·g(s(f_min)·Δf).
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
-- § 2. THE 4:5:6 OCTAVE CHART (levels are the color quanta)
-- ════════════════════════════════════════════════════════════════

harmonics :: [Integer]           -- (m_R, m_G, m_B): the just triad
harmonics = [4, 5, 6]

fFund :: Integer                 -- Hz; puts m_R·f0 at P&L's 500 Hz
fFund = 125

-- | Exact integer frequency of channel harmonic m, level ℓ.
freqI :: Integer -> Integer -> Integer
freqI m l = m * fFund * 2 ^ l

-- | The 12 partial frequencies, channel-major, level-minor.
freqs12 :: [Double]
freqs12 = [ fromInteger (freqI m l) | m <- harmonics, l <- [0 .. 3] ]

-- | The constant kernel matrix G (zero diagonal, symmetric, ≥ 0).
gMat :: [[Double]]
gMat = [ [ if fi == fj then 0
           else gK (sOf (min fi fj) * abs (fj - fi))
         | fj <- freqs12 ] | fi <- freqs12 ]

-- | D as a quadratic form in the occupancy 12-vector: ½·aᵀG·a.
quadD :: [Double] -> Double
quadD a = 0.5 * sum (zipWith (*) a (map (dot a) gMat))
  where dot u v = sum (zipWith (*) u v)

-- | Cross-dissonance as the bilinear pairing a₁ᵀG·a₂.
bilinX :: [Double] -> [Double] -> Double
bilinX a bb = sum (zipWith (*) a (map (dot bb) gMat))
  where dot u v = sum (zipWith (*) u v)

-- | The 12 partials of an occupancy 12-vector.
spectrum :: [Double] -> [Partial]
spectrum = zip freqs12

-- ════════════════════════════════════════════════════════════════
-- § 3. OCCUPANCY FROM THE LATTICE (deterministic witnesses)
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

-- | A witness frame: 4096 chromatic triples (a,b,c), levels 0..3,
-- from a warp of the LCG stream (id = flat, (**3) = skewed dark).
witnessLevels :: (Double -> Double) -> Int -> ([Int], [Int], [Int])
witnessLevels warp seed = (as, bs, cs)
  where
    ls = take (3 * 4096)
           [ min 3 (floor (warp u * 4)) | u <- uniforms seed ]
    (as, rest) = splitAt 4096 ls
    (bs, cs)   = splitAt 4096 rest

-- | Exact integer level marginals per channel (the carrier).
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

-- ════════════════════════════════════════════════════════════════
-- § 4. SCALE DESIGN: GUARDED SEQUENTIAL DETUNE
-- ════════════════════════════════════════════════════════════════

gridN :: Int                      -- 1/1200 octave = 0.3° of hue
gridN = 1200

betaOf :: Int -> Double
betaOf k = 2 ** (fromIntegral k / fromIntegral gridN)

-- | One channel comb at detune β with its occupancy amplitudes.
combP :: Integer -> Double -> [Double] -> [Partial]
combP m beta amps =
  [ (fromInteger (m * fFund) * beta * 2 ^ l, a)
  | (l, a) <- zip [0 .. 3 :: Integer] amps ]

frac1 :: Double -> Double
frac1 x = x - fromIntegral (floor x :: Integer)

-- | Pitch class of channel harmonic m at grid detune k.
classAt :: Integer -> Int -> Double
classAt m k =
  frac1 (logBase 2 (fromInteger m) + fromIntegral k / fromIntegral gridN)

circDist :: Double -> Double -> Double
circDist p q = min dd (1 - dd) where dd = abs (frac1 (p - q))

-- | Cross-dissonance curve of comb m (amps) against placed partials.
curveOf :: [Partial] -> Integer -> [Double] -> [(Double, Int)]
curveOf placed m amps =
  [ (xTerm placed (combP m (betaOf k) amps), k) | k <- [0 .. gridN - 1] ]

-- | Strict interior local minima (grid indices).
localMins :: [(Double, Int)] -> [Int]
localMins pts =
  [ k1 | ((v0, _), (v1, k1), (v2, _)) <- zip3 pts (tail pts) (drop 2 pts)
       , v1 < v0, v1 < v2 ]

guardGamma :: Double              -- forbid hue collapse: ≥ 1 semitone
guardGamma = 1 / 12

-- | Deepest local minimum whose pitch class clears every placed
-- class by the guard — Sethares' local-minima scale step, with the
-- unison/coincidence (hue-collapse) branch excluded.
guardedArgmin :: [Double] -> Integer -> [(Double, Int)] -> Int
guardedArgmin placedClasses m pts =
  snd (minimum [ (v, k) | (v, k) <- pts
               , k `elem` localMins pts
               , all (\q -> circDist (classAt m k) q >= guardGamma)
                     placedClasses ])

-- | The per-loop tuning: δ_G* then δ_B*, as grid indices.
designTuning :: [Double] -> (Int, Int)
designTuning amps12 = (kG, kB)
  where
    [aR, aG, aB] = [ take 4 (drop (4 * c) amps12) | c <- [0 .. 2] ]
    rComb  = combP 4 1 aR
    kG     = guardedArgmin [0] 5 (curveOf rComb 5 aG)
    placed = rComb ++ combP 5 (betaOf kG) aG
    kB     = guardedArgmin [0, classAt 5 kG] 6 (curveOf placed 6 aB)

-- ════════════════════════════════════════════════════════════════
-- § 5. DEPTH → URGENCY (cadence roughness at rung 16)
-- ════════════════════════════════════════════════════════════════

-- | Cadence width in frames: σ(d) = (63/8)·(2−d), the
-- BinomialCadence law (σ_base = 63/8, near d=1 tight, far d=0 2×).
sigmaOf :: Double -> Double
sigmaOf d = 63 / 8 * (2 - d)

-- | Cadence frequency: spectral half-width of a σ-frame Gaussian
-- at 20 fps — ν(d) = 20/(2π·σ(d)) Hz.
nuOf :: Double -> Double
nuOf d = 20 / (2 * pi * sigmaOf d)

-- | Calibration: full near/far contrast lands AT the peak x̂.
sT :: Double
sT = xHat / (nuOf 1 - nuOf 0)

-- | Urgency of a voxel bond: Sethares roughness of the cadence
-- beat, weights = depth mass (u64 block sums cast, as in DYAD).
urg :: Double -> Double -> Double -> Double -> Double
urg w1 w2 d1 d2 = w1 * w2 * gK (sT * abs (nuOf d1 - nuOf d2))

-- | The urgency lattice at depth's native rung (TL9): 16×16×16
-- voxels, 4-neighbor spatial bonds per slice + time-wrapped
-- temporal bonds (the loop is a torus in time).
urgencyBonds :: [((Int, Int, Int), (Int, Int, Int))]
urgencyBonds =
  [ ((t, y, x), (t, y, x + 1)) | t <- r, y <- r, x <- init r ]
    ++ [ ((t, y, x), (t, y + 1, x)) | t <- r, y <- init r, x <- r ]
    ++ [ ((t, y, x), ((t + 1) `mod` 16, y, x)) | t <- r, y <- r, x <- r ]
  where r = [0 .. 15]

-- ════════════════════════════════════════════════════════════════
-- § 6. PITCH CLASS → HUE (octave equivalence is the hue circle)
-- ════════════════════════════════════════════════════════════════

-- | Pitch class of a frequency (f0-relative): q = frac(log₂ f/f0).
pitchClass :: Double -> Double
pitchClass f = frac1 (logBase 2 (f / fromInteger fFund))

-- | The tritone: the σ-involution in pitch space (hue + 180°).
tritone :: Double -> Double
tritone q = frac1 (q + 0.5)

-- | Chord hue and chroma-resultant: circular sum of the three
-- channel class vectors, weighted 2^ℓ (higher octave dominates).
-- Reference chart (δ = 0); tuning rotates the G/B classes.
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

-- | Resultant length / total weight ∈ [0,1] — the chroma factor.
chordResultant :: (Int, Int, Int) -> Double
chordResultant ch@(a, bl, c) =
  let (vx, vy) = chordVec ch
  in sqrt (vx * vx + vy * vy) / sum (map (2 ^^) [a, bl, c])

hueDist :: Double -> Double -> Double
hueDist h1 h2 = min dd (360 - dd) where dd = abs (h1 - h2)

-- ════════════════════════════════════════════════════════════════
-- § 7. AXIOMS
-- ════════════════════════════════════════════════════════════════

tol :: Double
tol = 1e-12

-- (SP1) UNISON ZERO, SILENT TAIL: g(0) = 0 exactly; g strictly
--       decreasing past x̂ (grid 10⁻³ to 10); g(8) < 10⁻¹² —
--       coincident partials and widely-spaced partials are both
--       consonant. The dissonant region is a bump, not a wall.
axiom_SP1 :: Bool
axiom_SP1 =
     gK 0 == 0
  && gK 8 < tol
  && and [ gK x > gK (x + h) | let h = 1e-3
         , x <- [ xHat + h * fromIntegral k | k <- [0 .. 9779 :: Int] ] ]

-- (SP2) ONE INTERIOR PEAK, CLOSED FORM: g′ changes sign exactly
--       once on [0,10] (grid 10⁻³), at x̂ = ln(b2/b1)/(b2−b1) =
--       0.220350 ± 10⁻⁶, height g(x̂) = 0.179756 ± 10⁻⁶ — an
--       honest 8% below Sethares' nominal x* = 0.24.
axiom_SP2 :: Bool
axiom_SP2 =
     signChanges == 1
  && abs (xHat - 0.220350) < 1e-6
  && abs (gK xHat - 0.179756) < 1e-6
  && xHat < xStar && xHat / xStar > 0.9
  where
    g' x = -b1 * exp (-b1 * x) + b2 * exp (-b2 * x)
    xs = [ 1e-3 * fromIntegral k | k <- [0 .. 10000 :: Int] ]
    signChanges = length [ () | (x0, x1) <- zip xs (tail xs)
                              , g' x0 > 0, g' x1 <= 0 ]

-- (SP3) BILINEAR AND SYMMETRIC: d(λa₁, μa₂) = λμ·d(a₁,a₂) to
--       10⁻¹² and d(p,q) = d(q,p) exactly — the product amplitude
--       form, pinned (the min-variant would only be homogeneous).
axiom_SP3 :: Bool
axiom_SP3 =
     abs (dK (500, 2) (620, 3) - 6 * dK (500, 1) (620, 1)) < tol
  && dK (500, 0.7) (620, 0.4) == dK (620, 0.4) (500, 0.7)

-- (SP4) THE CHART IS EXACT: 12 pinned frequencies; intra-channel
--       steps are exact octaves; level-aligned cross-channel pairs
--       are exactly 5:4, 6:5, 3:2 (integer cross-multiplication);
--       G is symmetric, zero-diagonal, non-negative.
axiom_SP4 :: Bool
axiom_SP4 =
     [ freqI m l | m <- harmonics, l <- [0 .. 3] ]
       == [ 500, 1000, 2000, 4000, 625, 1250, 2500, 5000
          , 750, 1500, 3000, 6000 ]
  && and [ freqI m (l + 1) == 2 * freqI m l
         | m <- harmonics, l <- [0 .. 2] ]
  && and [ 4 * freqI 5 l == 5 * freqI 4 l
        && 5 * freqI 6 l == 6 * freqI 5 l
        && 2 * freqI 6 l == 3 * freqI 4 l | l <- [0 .. 3] ]
  && and [ gMat !! i !! j == gMat !! j !! i
         | i <- [0 .. 11], j <- [0 .. 11] ]
  && and [ gMat !! i !! i == 0 | i <- [0 .. 11] ]
  && and [ gMat !! i !! j >= 0 | i <- [0 .. 11], j <- [0 .. 11] ]

-- (SP5) OCCUPANCY CONSERVED: witness level marginals are exact
--       integer counts summing to 4096 per channel — amplitudes
--       ride the same lawful sum carrier as the tri-scale ladder.
axiom_SP5 :: Bool
axiom_SP5 = all ok [1, 2, 3]
  where
    ok seed = let (as, bs, cs) = witnessLevels id seed
              in all ((== 4096) . sum . countsOf) [as, bs, cs]

-- (SP6) THE QUADRATIC FORM: pair-summed D equals ½·aᵀG·a to
--       10⁻¹²; POLARIZATION D(a₁+a₂) = D(a₁) + D(a₂) + a₁ᵀG·a₂;
--       scaling D(λa) = λ²·D(a). Merging two loops adds their
--       intrinsic dissonances plus exactly the bilinear cross-term.
axiom_SP6 :: Bool
axiom_SP6 =
     abs (dPairs (spectrum a1) - quadD a1) < tol
  && abs (quadD (zipWith (+) a1 a2)
          - quadD a1 - quadD a2 - bilinX a1 a2) < tol
  && abs (quadD (map (* 3) a1) - 9 * quadD a1) < tol
  where
    a1 = ampsOf id 1
    a2 = ampsOf (** 3) 2

-- (SP7) THE HARMONIC ANCHOR (P&L/Sethares, ported verbatim):
--       witness timbre 7 harmonics of 500 Hz, amps 0.88^(k−1);
--       D_T(α) on [1, 2.3] grid 5·10⁻⁴ has a local minimum within
--       0.01 of each of 6/5, 5/4, 4/3, 3/2, 5/3, 2/1, and their
--       depths recover the classical consonance ranking
--       2/1 < 3/2 < 5/3 < 4/3 < 5/4 < 6/5.
axiom_SP7 :: Bool
axiom_SP7 =
     all (\r -> any (\al -> abs (al - r) < 0.01) minAlphas) ratios
  && and (zipWith (<) rankVals (tail rankVals))
  where
    tim = [ (500 * fromIntegral k, 0.88 ^^ (k - 1)) | k <- [1 .. 7 :: Int] ]
    dCurve al = dPairs (tim ++ [ (al * f, a) | (f, a) <- tim ])
    grid = [ 1 + 5e-4 * fromIntegral k | k <- [0 .. 2600 :: Int] ]
    pts  = [ (dCurve al, al) | al <- grid ]
    minAlphas = [ al | ((v0, _), (v1, al), (v2, _))
                         <- zip3 pts (tail pts) (drop 2 pts)
                     , v1 < v0, v1 < v2 ]
    ratios   = [ 6/5, 5/4, 4/3, 3/2, 5/3, 2/1 ]
    valNear r = minimum [ v | (v, al) <- pts, abs (al - r) < 0.01 ]
    rankVals  = map valNear [ 2/1, 3/2, 5/3, 4/3, 5/4, 6/5 ]

-- (SP8) THE UNIFORM TUNING, PINNED: for flat occupancy the guarded
--       sequential design lands at (δ_G*, δ_B*) = (269, 836)/1200.
--       The excluded branches are the coincidence dips — the G
--       curve has a local min within one grid step of log₂(8/5)
--       (G comb aligns with R comb) and the B curve's GLOBAL min
--       sits within one step of log₂(4/3) (B aligns with R: hue
--       collapse, guarded away). δ = 0 is no minimum — the just
--       4:5:6 chart itself is not a resting point; the curve falls
--       through it. Tuned classes clear the guard pairwise.
axiom_SP8 :: Bool
axiom_SP8 =
     designTuning uniformAmps == (269, 836)
  && any (\k -> nearStep k (logBase 2 (8/5))) (localMins gCurve)
  && nearStep bGlobal (logBase 2 (4/3))
  && fst (gCurve !! 1) < fst (head gCurve)
  && all (>= guardGamma)
       [ circDist p q | (p, q) <- [ (qR, qG), (qR, qB), (qG, qB) ] ]
  where
    aU = replicate 4 0.25
    rComb = combP 4 1 aU
    gCurve = curveOf rComb 5 aU
    placed = rComb ++ combP 5 (betaOf 269) aU
    bGlobal = snd (minimum (curveOf placed 6 aU))
    nearStep k target =
      abs (fromIntegral k / 1200 - target) < 1 / 1200
    (qR, qG, qB) = (0, classAt 5 269, classAt 6 836)

-- (SP9) THE PUNCHLINE — CONSONANCE DEPENDS ON THE TIMBRE: a
--       dark-skewed witness occupancy (u³ warp) moves the UNGUARDED
--       global G minimum from the anti-node all the way to comb
--       coincidence (814/1200, within one step of log₂(8/5)) and
--       moves the GUARDED tuning from 269 to 325 — 56 grid steps
--       ≈ 17° of hue. The loop's own spectrum decides its tuning;
--       no fixed palette is consonant for every image.
axiom_SP9 :: Bool
axiom_SP9 =
     unguardedSkew == 814
  && abs (814 / 1200 - logBase 2 (8/5)) < 1 / 1200
  && guardedSkew == 325
  && abs (guardedSkew - 269) >= 10
  && designTuning uniformAmps /= (guardedSkew, snd (designTuning skew))
  where
    skew = ampsOf (** 3) 2
    [aR, aG] = [ take 4 (drop (4 * c) skew) | c <- [0, 1] ]
    sCurve = curveOf (combP 4 1 aR) 5 aG
    unguardedSkew = snd (minimum sCurve)
    guardedSkew   = guardedArgmin [0] 5 sCurve

-- (SP10) THE CADENCE OCTAVE: σ(0) = 2·σ(1) exactly (63/8 and 63/4
--        are dyadic rationals, exact in Double), so the near and
--        far cadence frequencies are one octave apart:
--        ν(1)/ν(0) = 2 — depth's two poles are the σ vs 2σ phases
--        of PHASE-16, heard as an octave.
axiom_SP10 :: Bool
axiom_SP10 =
     sigmaOf 0 == 2 * sigmaOf 1
  && sigmaOf 1 == 63 / 8
  && abs (nuOf 1 / nuOf 0 - 2) < tol
  && abs (sT - 1.090293) < 1e-6

-- (SP11) URGENCY CALIBRATION: zero at equal depth (exactly — flat
--        interiors are silent); FULL near/far contrast lands
--        exactly at the roughness peak g(x̂); strictly monotone in
--        depth contrast on [0,1] (grid 10⁻³) — the sharper the
--        depth boundary, the faster it beats, up to the peak and
--        never past it. Bilinear in the two voxel masses.
axiom_SP11 :: Bool
axiom_SP11 =
     all (\d -> urg 1 1 d d == 0) [ 0, 0.25, 0.5, 0.75, 1 ]
  && abs (urg 1 1 0 1 - gK xHat) < tol
  && and [ urg 1 1 0 d < urg 1 1 0 (d + h)
         | let h = 1e-3
         , d <- [ h * fromIntegral k | k <- [0 .. 998 :: Int] ] ]
  && abs (urg 2 3 0 1 - 6 * urg 1 1 0 1) < tol

-- (SP12) THE URGENCY CLOCK (TL9's rung): the field is 16³ = 4096
--        judgments per 3.2 s loop at 5 Hz (delay 20 cs), 64 draws
--        per judgment, on 11776 bonds — 16 slices × 480 spatial
--        4-neighbor bonds + 4096 time-wrapped temporal bonds (the
--        NETSCAPE loop closes time into a torus).
axiom_SP12 :: Bool
axiom_SP12 =
     16 ^ (3 :: Int) == (4096 :: Integer)
  && (100 :: Integer) `div` (320 `div` 16) == 5
  && ((64 :: Integer) `div` 16) ^ (3 :: Int) == 64
  && length urgencyBonds == 11776
  && length urgencyBonds == 16 * 480 + 4096

-- (SP13) OCTAVE EQUIVALENCE IS THE HUE CIRCLE: pitch class is
--        level-invariant (all four octaves of a channel share one
--        hue, to 10⁻⁹ in log arithmetic); the σ-involution is the
--        TRITONE q ↦ q+½ — hue+180°, and tritone² = id matching
--        σ∘σ = id; the reference classes are exactly log₂(5/4)
--        and log₂(3/2).
axiom_SP13 :: Bool
axiom_SP13 =
     and [ abs (pc m l - pc m 0) < 1e-9
         | m <- harmonics, l <- [0 .. 3] ]
  && all (\q -> abs (tritone (tritone q) - q) < tol) [ 0, 0.1, 0.32, 0.9 ]
  && all (\q -> abs (hueDist (360 * tritone q) (360 * q) - 180) < 1e-9)
         [ 0, 0.2, 0.585 ]
  && abs (pitchClass 625 - logBase 2 1.25) < tol
  && abs (pitchClass 750 - logBase 2 1.5) < tol
  where pc m l = pitchClass (fromInteger (freqI m l))

-- (SP14) CHORD HUE, PINNED (reference chart): a channel-dominant
--        chord pulls hue to that channel's class within 4° (the
--        2^ℓ weighting: level 3 vs 0 is 8:1); the neutral chords
--        a=b=c keep a resultant of 0.16–0.17 — the 4:5:6 classes
--        are deliberately non-equidistant (just ratios beat
--        perfect neutrality; grays stay LOW-chroma, not zero).
axiom_SP14 :: Bool
axiom_SP14 =
     hueDist (chordHue (3, 0, 0)) (360 * pitchClass 500) < 4
  && hueDist (chordHue (0, 3, 0)) (360 * pitchClass 625) < 4
  && hueDist (chordHue (0, 0, 3)) (360 * pitchClass 750) < 4
  && all (\l -> let r = chordResultant (l, l, l)
                in r > 0.16 && r < 0.17) [ 0, 1, 2, 3 ]
  && abs (chordHue (0, 0, 0) - chordHue (3, 3, 3)) < 1e-9

-- (SP15) THE LIVE SET PAIRS BY BILINEARITY: cross-dissonance of
--        two witness loops equals a₁ᵀG·a₂ to 10⁻¹², symmetric;
--        X(T,T) = 2·D(T); three witness loops give pairwise
--        distinct X (margin 10⁻⁹), so the greedy consonant
--        setlist order — next loop = argmin X against the current
--        one — is deterministic from bytes alone.
axiom_SP15 :: Bool
axiom_SP15 =
     abs (xTerm (spectrum w1) (spectrum w2) - bilinX w1 w2) < tol
  && abs (bilinX w1 w2 - bilinX w2 w1) < tol
  && abs (bilinX w1 w1 - 2 * quadD w1) < tol
  && minimum [ abs (x12 - x13), abs (x12 - x23), abs (x13 - x23) ]
       > 1e-9
  where
    w1 = ampsOf id 1
    w2 = ampsOf (** 3) 2
    w3 = ampsOf sqrt 3
    x12 = bilinX w1 w2
    x13 = bilinX w1 w3
    x23 = bilinX w2 w3

-- ════════════════════════════════════════════════════════════════
-- § 8. MAIN
-- ════════════════════════════════════════════════════════════════

check :: String -> [Bool] -> IO ()
check name results =
  let mark = if and results then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " SpectralPalette: the occupancy spectrum is a timbre"
  putStrLn " 12 partials = 3 channel combs × 4 octave levels (4:5:6)"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  ch │ levels 0..3 (Hz)          │ class  │ hue"
  putStrLn "  ───┼───────────────────────────┼────────┼──────"
  mapM_ (\(nm, m) ->
          putStrLn $ "   " ++ nm ++ " │ "
            ++ show [ freqI m l | l <- [0 .. 3] ]
            ++ " │ " ++ take 6 (show (frac1 (logBase 2 (fromInteger m))))
            ++ " │ " ++ take 5 (show (360 * frac1 (logBase 2 (fromInteger m))))
            ++ "°")
        (zip ["R", "G", "B"] harmonics)
  putStrLn ""
  putStrLn $ "  kernel peak x̂ = " ++ take 8 (show xHat)
          ++ ", g(x̂) = " ++ take 8 (show (gK xHat))
  putStrLn $ "  uniform guarded tuning (δG*, δB*) = "
          ++ show (designTuning uniformAmps) ++ " / 1200"
  putStrLn $ "  cadence: ν(near) = " ++ take 6 (show (nuOf 1))
          ++ " Hz, ν(far) = " ++ take 6 (show (nuOf 0))
          ++ " Hz (one octave), s_t = " ++ take 6 (show sT) ++ " s"
  putStrLn ""
  check "SP1  unison zero, silent tail (bump, not wall)"        [axiom_SP1]
  check "SP2  one interior peak at x̂ = 0.220350, closed form"   [axiom_SP2]
  check "SP3  bilinear in amplitudes, symmetric in the pair"    [axiom_SP3]
  check "SP4  the 4:5:6 octave chart is exact; G is a kernel"   [axiom_SP4]
  check "SP5  occupancy = integer marginals, 4096 per channel"  [axiom_SP5]
  check "SP6  D = ½aᵀGa; polarization; λ² scaling"              [axiom_SP6]
  check "SP7  harmonic anchor: six dips, classical ranking"     [axiom_SP7]
  check "SP8  uniform tuning pinned (269, 836); no hue collapse" [axiom_SP8]
  check "SP9  punchline: occupancy moves the tuning (56 steps)" [axiom_SP9]
  check "SP10 near/far cadence is an exact octave"              [axiom_SP10]
  check "SP11 urgency: 0 at flat, peak at full contrast, monotone" [axiom_SP11]
  check "SP12 urgency clock: 16³ at 5 Hz, 11776 torus bonds"    [axiom_SP12]
  check "SP13 octave equivalence = hue circle; σ-pair = tritone" [axiom_SP13]
  check "SP14 chord hue: dominance < 4°; grays stay low-chroma" [axiom_SP14]
  check "SP15 live set: X = a₁ᵀGa₂, distinct, greedy setlist"   [axiom_SP15]
  putStrLn ""
  putStrLn "  The palette is the timbre. Scale design = table choice"
  putStrLn "  at the dissonance minima of the loop's own spectrum."
  putStrLn "  Depth beats: boundaries are urgent, interiors silent."
  putStrLn "  It trains nothing (★NO-CAPTURE-TRAINING); the container"
  putStrLn "  is untouched — only tables and telemetry."
