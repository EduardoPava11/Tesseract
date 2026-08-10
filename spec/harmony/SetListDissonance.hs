-- ════════════════════════════════════════════════════════════════
-- SetListDissonance: the Sethares roughness kernel woven into the
-- 4⁴ lattice, the depth cadence, and the archive — THE SET-LIST
-- READING.
--
-- THEORY (Plomp & Levelt 1965, JASA 38; Sethares 1993, JASA 94(3)):
-- roughness of two partials (f₁,a₁),(f₂,a₂) is
--
--     d = a₁·a₂ · g(x),   g(x) = e^(−b1·x) − e^(−b2·x),
--     x = x* · Δf / CB(f_min)
--
-- with b1 = 3.51, b2 = 5.75, x* = 0.24 (Sethares' reference
-- implementation, aatishb.com/dissonance). g is domain-free: zero at
-- unison, single peak at x̂ = ln(b2/b1)/(b2−b1) ≈ 0.2203 (≈ quarter
-- critical band — P&L's frequency-dependent replacement for
-- Helmholtz's wrong fixed 33 Hz), exponential tail (wide pairs never
-- rough). Everything audio lives in three slots: POSITION (Hz),
-- LOCAL RESOLUTION (critical bandwidth CB(f_min) = s1·f + s2), and
-- WEIGHT (amplitude). Sethares is CIEDE2000-for-the-ear; scale
-- design = local minimization of the pair-summed metric — the same
-- shape as palette optimization over a perceptual color distance.
--
-- THE WEAVE (three ports of the one kernel):
--
--   I.  OCTAVES IN RGB PRODUCE COLOR. RGB lattice level ℓ ∈ 0..3 is
--       a temporal OCTAVE REGISTER: f(ℓ) = 1.25·2^(ℓ+1) Hz, so
--       levels 1,2,3 land exactly on the tri-scale rung rates
--       5/10/20 Hz (TriScaleLadder TL4/TL8) and every register is a
--       power-of-two multiple of the 3.2 s loop fundamental
--       0.3125 Hz. A palette entry (d,a,b,c) is a 3-partial CHORD;
--       its roughness D_chord (constant-Q temporal CB, Q = 2)
--       depends only on the register gaps {|a−b|,|b−c|,|a−c|} — it
--       is EXACTLY σ-invariant, so the involution i ↔ 255−i
--       (digit complement) preserves it, and the 128 σ-classes get a
--       lawful roughness rank. COLOR OUT: rank fills the DYAD
--       shells (counts 1,1,2,4,8,16,32,64; radii ρ_k = 2k/7
--       UNCHANGED — only the free assignment moves): grays
--       (a=b=c, D=0, unison chords) at the neutral core, register
--       runs {ℓ,ℓ+1,ℓ+2} (max roughness) at the saturated rim,
--       σ-partner = hue+180° (DyadPalette canon). Chroma IS chord
--       roughness.
--
--   II. DEPTH PRODUCES URGENCY. The epoch process has positions =
--       the 4 cadence centers c_e = (2e+1)·63/8 (Δc = 15.75·|Δe|)
--       and local resolution = the cadence width σ(depth) =
--       (63/8)·(2−depth) (BinomialCadence). Then
--       x_k(d) = x*·Δc_k/σ(d) = 2x*·k/(2−d): the FAR pole (d=0,
--       σ = Δc) sits exactly at x = x*, within 0.4 % of the g-peak
--       — far content rides the Plomp–Levelt roughness maximum —
--       and the NEAR pole (d=1) sits one octave up the tail.
--       U(d) = Σ_{e<e'} P_e·P_{e'}·g(x_{|Δe|}(d)) is strictly
--       decreasing in depth: far = rough = URGENT, near = calm —
--       the closed-form law under CD5's "near = stable / far =
--       volatile". Clock: rung 16 (TL9), 4096 judgments per loop at
--       5 Hz; 16-sample envelope Û per loop; scalar Ū per loop.
--
--   III. A LIVE SET OF LOOPS. A loop's TIMBRE is its palette as a
--       weighted spectrum {(CIELAB position, occupancy)} — the
--       palette IS the timbre, rebuildable from STATS bytes (DY8).
--       Inter-loop dissonance is the pure Sethares cross-term with
--       the CIEDE2000 resolution slot:
--           χ(L,M) = Σ_{i∈L,j∈M} wᵢwⱼ·g(x*·ΔE/(1+0.045·C_min))
--                    / (W_L·W_M)
--       The color OCTAVE is the σ-involution's hue action R₁₈₀:
--       σ-balanced loops transpose by it for FREE (χ-invariant,
--       exact). THE SET LIST: order the archive (EliteMap 3×3 / the
--       𝔇 phase archive) so the urgency sequence Ū is unimodal
--       peaking at position ⌈2n/3⌉ (dramaturgy) and, among such
--       orderings, total transition dissonance Σχ is minimal —
--       scale design over loops: consecutive loops sit at consonant
--       intervals of each other's timbres. Exhaustive for n ≤ 9.
--
-- DECREE SCOPE: measurement + ordering + table CHOICE only. No GIF
-- byte of the locked container changes (table/index choice is free);
-- all closed form, trains nothing (★NO-CAPTURE-TRAINING); rides
-- BESIDE Ou & Luo CH (DyadHarmony), never replaces it; no UI.
-- ════════════════════════════════════════════════════════════════

module SetListDissonance where

import Data.List (sort, sortBy, permutations, minimumBy)
import Data.Ord (comparing)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE KERNEL (pinned constants; the domain-free core)
-- ════════════════════════════════════════════════════════════════

b1, b2, xStar :: Double
b1    = 3.51
b2    = 5.75
xStar = 0.24

g :: Double -> Double
g x = exp (-b1 * x) - exp (-b2 * x)

-- | The single interior peak, closed form.
xHat :: Double
xHat = log (b2 / b1) / (b2 - b1)

-- ════════════════════════════════════════════════════════════════
-- § 2. PORT I — OCTAVE REGISTERS AND CHORD ROUGHNESS (4⁴ lattice)
-- ════════════════════════════════════════════════════════════════

-- | Register frequency in centihertz, exact integers:
-- f(ℓ) = 1.25·2^(ℓ+1) Hz = 125·2^(ℓ+1) cHz.
fRegCentiHz :: Integer -> Integer
fRegCentiHz l = 125 * 2 ^ (l + 1)

-- | Rung rates in cHz from the time law (TriScaleLadder):
-- rate = 100/delay Hz, delay = 320/side cs.
rungRateCentiHz :: Integer -> Integer
rungRateCentiHz side = 10000 * side `div` 320

-- | Loop fundamental: 1/3.2 s = 0.3125 Hz = 125/4 cHz (×4 = 125).
loopFundamentalQuarterCentiHz :: Integer
loopFundamentalQuarterCentiHz = 125

-- | Constant-Q temporal critical band: CB(f) = f/Q, Q = 2 (pinned
-- design constant, a retune slot). Then for a register pair with gap
-- dl, x = x*·(f_max−f_min)/(f_min/2) = 2x*·(2^dl − 1) — a function
-- of the GAP alone, the exactness that makes σ-invariance exact.
qTime :: Double
qTime = 2

xGap :: Integer -> Double
xGap dl = xStar * qTime * (2 ^^ dl - 1)

-- | A lattice entry (d,a,b,c), digits 0..3; index = base-4.
type Entry = (Integer, Integer, Integer, Integer)

entries :: [Entry]
entries = [ (d, a, b, c) | d <- [0..3], a <- [0..3], b <- [0..3], c <- [0..3] ]

entryIndex :: Entry -> Integer
entryIndex (d, a, b, c) = 64 * d + 16 * a + 4 * b + c

-- | The σ involution: index complement 255−i == digit complement.
sigmaE :: Entry -> Entry
sigmaE (d, a, b, c) = (3 - d, 3 - a, 3 - b, 3 - c)

-- | Chord roughness of the RGB triple: sum of g over the three
-- register gaps, evaluated on the SORTED gap list so equal multisets
-- give bit-identical Doubles.
dChord :: Entry -> Double
dChord (_, a, b, c) =
  sum [ g (xGap dl) | dl <- sort [abs (a - b), abs (b - c), abs (a - c)] ]

-- ════════════════════════════════════════════════════════════════
-- § 3. PORT II — DEPTH → URGENCY (epoch roughness)
-- ════════════════════════════════════════════════════════════════

-- | BinomialCadence, 64 frames: σ_base = 63/8; centers (2e+1)·63/8;
-- adjacent center gap Δc = 2·σ_base = 63/4; σ(d) = σ_base·(2−d).
sigmaBase, centerGap :: Double
sigmaBase = 63 / 8
centerGap = 63 / 4

sigmaOf :: Double -> Double
sigmaOf d = sigmaBase * (2 - d)

-- | The dimensionless epoch-pair coordinate: x_k(d) = 2x*k/(2−d).
xDepth :: Integer -> Double -> Double
xDepth k d = xStar * centerGap * fromIntegral k / sigmaOf d

-- | Uniform-weight urgency (the axiom form; runtime weights are the
-- BinomialCadence epoch probabilities P_e·P_e'). Pair multiplicity
-- over 4 epochs: gap 1 ×3, gap 2 ×2, gap 3 ×1.
urgency :: Double -> Double
urgency d = (1 / 16) * sum [ m * g (xDepth k d)
                           | (m, k) <- [(3, 1), (2, 2), (1, 3)] ]

-- ════════════════════════════════════════════════════════════════
-- § 4. PORT III — THE EYE KERNEL AND LOOP TIMBRES
-- ════════════════════════════════════════════════════════════════

-- | A color partial: CIELAB position + occupancy weight.
type Partial = ((Double, Double, Double), Double)

deltaE :: (Double, Double, Double) -> (Double, Double, Double) -> Double
deltaE (l1, a1, b1') (l2, a2, b2') =
  sqrt ((l1-l2)^(2::Int) + (a1-a2)^(2::Int) + (b1'-b2')^(2::Int))

chroma :: (Double, Double, Double) -> Double
chroma (_, a, b') = sqrt (a*a + b'*b')

-- | The resolution slot, CIEDE2000's S_C with C̄ → C_min (mirror of
-- f_min: the less-saturated member sets the local JND).
cbColor :: Double -> Double
cbColor cmin = 1 + 0.045 * cmin

-- | Sethares-for-the-eye pair roughness.
dEye :: Partial -> Partial -> Double
dEye (p, w1) (q, w2) =
  w1 * w2 * g (xStar * deltaE p q / cbColor (min (chroma p) (chroma q)))

-- | Pure cross-term between two timbres, normalized to [0, g(x̂)).
chi :: [Partial] -> [Partial] -> Double
chi ls ms = sum [ dEye i j | i <- ls, j <- ms ] / (wTot ls * wTot ms)
  where wTot = sum . map snd

-- | Hue rotation (degrees) — the interval action; R₁₈₀ = the color
-- octave (the σ-involution's hue component, DyadPalette canon).
rotP :: Double -> Partial -> Partial
rotP thDeg ((l, a, b'), w) = ((l, a * co - b' * si, a * si + b' * co), w)
  where th = thDeg * pi / 180; co = cos th; si = sin th

-- ════════════════════════════════════════════════════════════════
-- § 5. THE WITNESS TABLE (octaves → color, concretely)
--
-- 128 σ-classes ranked by dChord fill the DYAD shell counts
-- [1,1,2,4,8,16,32,64] (radii/counts canon-fixed; the ASSIGNMENT is
-- the free choice this design pins). Witness partials: the d=0
-- epoch slice + σ-partners (128 partials); rep hue = golden-angle
-- spread within [0,180), partner = +180°; shell sets chroma
-- C_k = 25·ρ_k, ρ_k = 2(k+1)/7, and lightness L_k = 74 − 4k.
-- ════════════════════════════════════════════════════════════════

ladderCounts :: [Int]
ladderCounts = [1, 1, 2, 4, 8, 16, 32, 64]

-- | σ-class reps: indices 0..127 (partner = 255−i). Sorted by
-- (dChord, index): rank → shell.
classShell :: Integer -> Int
classShell i = shellOfRank (rankOf i)
  where
    reps = sortBy (comparing (\j -> (dChord (entryOf j), j))) [0 .. 127]
    rankOf j = length (takeWhile (/= j) reps)
    shellOfRank r = length (takeWhile (<= r) (tail (scanl (+) 0 ladderCounts)))
      -- shells filled in ladder counts: ranks [0], [1], [2,3], ...

entryOf :: Integer -> Entry
entryOf i = (i `div` 64, (i `div` 16) `mod` 4, (i `div` 4) `mod` 4, i `mod` 4)

shellChroma, shellL :: Int -> Double
shellChroma k = 25 * 2 * fromIntegral (k + 1) / 7
shellL k = 74 - 4 * fromIntegral k

-- | Witness timbre: reps i ∈ 0..63 (epoch 0) and partners 255−i.
-- Weight field: 1 for the σ-balanced witness; pseudo-occupancy
-- (deterministic, σ-UNBALANCED) for the dip witness.
witness :: (Integer -> Double) -> [Partial]
witness wf = concat
  [ [ ((lk, ck * cos h, ck * sin h), wf i)
    , ((lk, ck * cos (h + pi), ck * sin (h + pi)), wf (255 - i)) ]
  | i <- [0 .. 63]
  , let k  = classShell i
        ck = shellChroma k
        lk = shellL k
        h  = 2 * pi * frac (fromIntegral i * phiG) / 2   -- [0, π)
  ]
  where frac x = x - fromIntegral (floor x :: Integer)
        phiG   = 0.618033988749895

wBalanced, wOcc :: Integer -> Double
wBalanced _ = 1
wOcc i = 1 + fromIntegral ((i * 7) `mod` 5) / 5

-- ════════════════════════════════════════════════════════════════
-- § 6. THE SET LIST (dramaturgy over the archive)
-- ════════════════════════════════════════════════════════════════

-- | Witness archive: 5 loops = hue-rotated variants of the witness
-- timbre, each with a representative depth giving Ū = urgency d.
setLoops :: [([Partial], Double)]
setLoops = [ (rotP th `map` witness wOcc, urgency d)
           | (th, d) <- zip [0, 30, 75, 120, 150] [0.9, 0.2, 0.5, 0.0, 0.7] ]

-- | Unimodal with peak exactly at position p (0-based), strict.
unimodalAt :: Int -> [Double] -> Bool
unimodalAt p us =
     and (zipWith (<) rise (tail rise))
  && and (zipWith (>) fall (tail fall))
  where rise = take (p + 1) us
        fall = drop p us

-- | The set list: among urgency-unimodal orderings peaking at
-- ⌈2n/3⌉ (1-based), minimize total transition dissonance Σχ.
setList :: [([Partial], Double)] -> ([Int], Double, Int)
setList loops = (best, cost best, length feasible)
  where
    n        = length loops
    peakPos  = ceiling (2 * fromIntegral n / 3 :: Double) - 1  -- 0-based
    chiM i j = chiTable !! i !! j
    chiTable = [ [ chi (fst (loops !! i)) (fst (loops !! j))
                 | j <- [0 .. n-1] ] | i <- [0 .. n-1] ]
    feasible = [ p | p <- permutations [0 .. n-1]
                   , unimodalAt peakPos (map (snd . (loops !!)) p) ]
    cost p   = sum (zipWith chiM p (tail p))
    best     = minimumBy (comparing cost) feasible

-- ════════════════════════════════════════════════════════════════
-- § 7. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (SD1) UNISON IS SILENT, DISTANCE IS FREE: g(0) = 0 exactly and
--       the tail vanishes — coincident partials and widely separated
--       partials are both consonant (P&L's two ends).
axiom_SD1 :: Bool
axiom_SD1 = g 0 == 0 && g 20 < 1e-8 && g 20 > 0

-- (SD2) ONE PEAK, CLOSED FORM: g′ has exactly one zero, at
--       x̂ = ln(b2/b1)/(b2−b1) ≈ 0.220353 — the quarter-critical-
--       band roughness maximum, frequency-dependent via the CB slot
--       (what replaced Helmholtz's fixed 33 Hz).
axiom_SD2 :: Bool
axiom_SD2 = abs (xHat - 0.220350) < 1e-6
         && signChanges == (1 :: Int)
  where
    g' x = -b1 * exp (-b1 * x) + b2 * exp (-b2 * x)
    grid = [ fromIntegral i * 1e-3 | i <- [0 .. 10000 :: Int] ]
    signChanges = length . filter id
      $ zipWith (\x y -> g' x > 0 && g' y <= 0) grid (tail grid)

-- (SD3) REGISTERS ARE THE LADDER'S OCTAVES (exact integers): RGB
--       levels 1,2,3 at f(ℓ) = 1.25·2^(ℓ+1) Hz land exactly on the
--       rung rates of sides 16/32/64 (5/10/20 Hz), level 0 one
--       octave below, and every register is a power-of-two multiple
--       of the 0.3125 Hz loop fundamental: f(ℓ) = 2^(ℓ+3)·(1/3.2 s).
axiom_SD3 :: Bool
axiom_SD3 =
     map fRegCentiHz [1, 2, 3] == map rungRateCentiHz [16, 32, 64]
  && fRegCentiHz 0 * 2 == rungRateCentiHz 16
  && and [ 4 * fRegCentiHz l == 2 ^ (l + 3) * loopFundamentalQuarterCentiHz
         | l <- [0 .. 3] ]

-- (SD4) σ PRESERVES ROUGHNESS (exact, bit-identical): chord
--       roughness depends only on register gaps, and the involution
--       complements digits, preserving every gap — so the 128
--       σ-classes have well-defined roughness and σ-partners always
--       share a shell (the DYAD same-radius law inherited for free).
axiom_SD4 :: Bool
axiom_SD4 = all (\e -> dChord (sigmaE e) == dChord e) entries

-- (SD5) GRAYS ARE UNISON: D_chord = 0 exactly on a=b=c and only
--       there — 16 of 256 entries; the neutral core is the silent
--       chord class.
axiom_SD5 :: Bool
axiom_SD5 = all ok entries && length zeros == 16
  where ok e@(_, a, b, c) = (dChord e == 0) == (a == b && b == c)
        zeros = filter ((== 0) . dChord) entries

-- (SD6) ROUGHNESS RANKS THE LATTICE: maximum chord roughness is
--       attained exactly by the register RUNS {ℓ,ℓ+1,ℓ+2} (value
--       2g(2x*) + g(6x*) ≈ 0.2506) and the minimum NONZERO exactly
--       by the wide splits {ℓ,ℓ,ℓ±3} (2g(14x*) ≈ 1.5e−5): clusters
--       of adjacent octave registers are the vivid rim, wide spacing
--       is nearly neutral. Chroma = roughness rank is well-founded.
axiom_SD6 :: Bool
axiom_SD6 =
     all (\t -> isRun t == (dChordT t == dMax)) triples
  && all (\t -> isWide t == (dChordT t == dMinNZ)) triples
  && dMax == 2 * g (xGap 1) + g (xGap 2)
  && dMinNZ == 2 * g (xGap 3)
  where
    triples  = [ (a, b, c) | a <- [0..3], b <- [0..3], c <- [0..3] ]
    dChordT (a, b, c) = dChord (0, a, b, c)
    dMax   = maximum (map dChordT triples)
    dMinNZ = minimum (filter (> 0) (map dChordT triples))
    isRun t  = sortT t `elem` [[0,1,2],[1,2,3]]
    isWide t = let s = sortT t in s == [0,0,3] || s == [0,3,3]
    sortT (a, b, c) = sort [a, b, c]

-- (SD7) FAR RIDES THE ROUGHNESS PEAK: the epoch-pair coordinate is
--       x_k(d) = 2x*k/(2−d) — algebra from Δc = 2σ_base — so at the
--       far pole the adjacent-epoch pair sits exactly at x* and
--       within 0.4 % of the peak height g(x̂); the near pole sits at
--       2x*, one octave up the decaying tail.
axiom_SD7 :: Bool
axiom_SD7 =
     xDepth 1 0 == xStar
  && xDepth 1 1 == 2 * xStar
  && all (\k -> abs (xDepth k 0 - xStar * fromIntegral k) < 1e-12) [1, 2, 3]
  && g xStar / g xHat > 0.995
  && abs (xStar - xHat) / xHat < 0.09

-- (SD8) URGENCY IS MONOTONE IN DEPTH: U strictly decreasing on
--       d ∈ [0,1] (grid 0.01) — far = volatile = urgent (CD5's
--       banner made closed-form), with U(0)/U(1) ∈ [1.9, 2.0].
axiom_SD8 :: Bool
axiom_SD8 =
     and (zipWith (>) us (tail us))
  && ratio > 1.9 && ratio < 2.0
  where us    = [ urgency (fromIntegral i / 100) | i <- [0 .. 100 :: Int] ]
        ratio = urgency 0 / urgency 1

-- (SD9) THE URGENCY CLOCK (exact integers, TL9's rung): 16 envelope
--       samples per 320 cs loop at the 20 cs judgment slice; 4096
--       judgments per loop at rung 16; 5 Hz readback.
axiom_SD9 :: Bool
axiom_SD9 =
     (320 :: Integer) `div` 20 == 16
  && (16 :: Integer) ^ (3 :: Int) == 4096
  && (100 :: Integer) `div` 20 == 5

-- (SD10) THE EYE KERNEL IS LAWFUL: symmetric (exact), bilinear in
--       occupancy (< 1e−12), zero at coincident colors, and χ is
--       bounded by the peak: 0 ≤ χ < g(x̂).
axiom_SD10 :: Bool
axiom_SD10 =
     dEye p q == dEye q p
  && abs (dEye (fst p, 2) (fst q, 3) - 6 * dEye (fst p, 1) (fst q, 1)) < 1e-12
  && dEye p (fst p, 5) == 0
  && cSelf >= 0 && cSelf < g xHat
  where
    p = ((55, 30, -10), 1.5)
    q = ((40, -20, 25), 0.7)
    cSelf = chi (witness wOcc) (witness wOcc)

-- (SD11) THE COLOR OCTAVE: (a) for σ-BALANCED occupancy the timbre
--       is R₁₈₀-invariant as a weighted set, so transposing by the
--       color octave is free — χ(L, R₁₈₀L) = χ(L, L) to 1e−12;
--       (b) for σ-UNBALANCED occupancy, θ = 180° is a strict local
--       minimum of the transition curve X(θ): the deepest point of
--       the ±10° neighborhood (1° grid), with ≥ 15 % prominence
--       against its immediate neighbors, and within 2 % of the
--       unison dip X(0). Sethares' minima are LOCAL — scale steps
--       are argmin_local, and the wide-θ baseline plays the role of
--       his consonant far tail — so the lawful claim is the dip,
--       not a global minimum. This is the 2/1 dip ported to hue.
axiom_SD11 :: Bool
axiom_SD11 = partA && partB
  where
    bal   = witness wBalanced
    partA = abs (chi bal (map (rotP 180) bal) - chi bal bal) < 1e-12
    occ   = witness wOcc
    xAt t = chi occ (map (rotP t) occ)
    x180  = xAt 180
    partB = all (\t -> x180 < xAt t) ([170 .. 179] ++ [181 .. 190])
         && xAt 179 - x180 > 0.15 * x180
         && xAt 181 - x180 > 0.15 * x180
         && abs (x180 - xAt 0) < 0.02 * xAt 0

-- (SD12) THE SET LIST EXISTS AND IS UNIQUE: for the 5-loop witness
--       archive, the urgency-unimodal orderings peaking at position
--       ⌈2n/3⌉ = 4 number exactly C(4,3) = 4, and exactly one of
--       them minimizes total transition dissonance Σχ.
axiom_SD12 :: Bool
axiom_SD12 =
     nFeasible == 4
  && length bests == 1
  && unimodalAt 3 (map (snd . (setLoops !!)) best)
  where
    (best, bestCost, nFeasible) = setList setLoops
    n        = length setLoops
    feasible = [ p | p <- permutations [0 .. n-1]
                   , unimodalAt 3 (map (snd . (setLoops !!)) p) ]
    chiOf i j = chi (fst (setLoops !! i)) (fst (setLoops !! j))
    cost p    = sum (zipWith chiOf p (tail p))
    bests     = [ p | p <- feasible, abs (cost p - bestCost) < 1e-15 ]

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
  putStrLn " SetListDissonance: Sethares woven into the 4⁴ lattice,"
  putStrLn " the depth cadence, and the archive (THE SET-LIST READING)"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  register │ f(ℓ) Hz │ rung │ rate    │ cycles/loop"
  putStrLn "  ─────────┼─────────┼──────┼─────────┼────────────"
  putStrLn "     0     │   2.5   │  —   │  —      │   8"
  putStrLn "     1     │   5.0   │  16  │  5 fps  │  16"
  putStrLn "     2     │  10.0   │  32  │ 10 fps  │  32"
  putStrLn "     3     │  20.0   │  64  │ 20 fps  │  64"
  putStrLn ""
  putStrLn $ "  x̂ = " ++ show xHat ++ ", g(x̂) = " ++ show (g xHat)
  putStrLn $ "  U(far=0) = " ++ show (urgency 0)
          ++ ", U(near=1) = " ++ show (urgency 1)
          ++ ", ratio = " ++ show (urgency 0 / urgency 1)
  let (best, bc, nf) = setList setLoops
  putStrLn $ "  set list = " ++ show best ++ ", Σχ = " ++ show bc
          ++ ", feasible = " ++ show nf
  putStrLn ""
  check "SD1  unison silent; wide pairs never rough"             [axiom_SD1]
  check "SD2  one peak at x̂ = ln(b2/b1)/(b2−b1) ≈ 0.2203"        [axiom_SD2]
  check "SD3  RGB levels = temporal octaves = the rung rates"    [axiom_SD3]
  check "SD4  σ preserves chord roughness, bit-exactly"          [axiom_SD4]
  check "SD5  grays are the unison class (16 zeros, iff a=b=c)"  [axiom_SD5]
  check "SD6  runs are the rim, wide splits the near-neutral"    [axiom_SD6]
  check "SD7  far pole sits at x*, 0.4% off the g-peak"          [axiom_SD7]
  check "SD8  urgency strictly decreasing in depth (~2× span)"   [axiom_SD8]
  check "SD9  urgency clock: 16 samples/loop, 4096 @ 5 Hz"       [axiom_SD9]
  check "SD10 eye kernel: symmetric, bilinear, bounded χ"        [axiom_SD10]
  check "SD11 the color octave: R₁₈₀ free for σ-balance; 180° dip" [axiom_SD11]
  check "SD12 the set list: 4 feasible, unique argmin"           [axiom_SD12]
  putStrLn ""
  putStrLn "  Chroma is chord roughness. Far rides the P&L peak."
  putStrLn "  The archive is a scale; the set list tunes it."
  putStrLn "  Measurement + choice only; trains nothing"
  putStrLn "  (★NO-CAPTURE-TRAINING); no locked byte moves."
