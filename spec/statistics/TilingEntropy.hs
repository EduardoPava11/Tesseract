-- ════════════════════════════════════════════════════════════════
-- TilingEntropy: the energy of "256 colors on a 64×64 plane"
--
-- Daniel's ask (2026-08-14): formulate an ENERGY VALUE for the
-- entropy of the 256 colors distributed over the 64×64 plane.
--
-- The state space is exactly the tiling count: 256^4096 assignments,
-- of which the surjective ones (every color used ≥ once) are
-- 256!·S(4096,256) — a 9,865-digit number that is 0.99997208 of the
-- whole. So surjectivity costs 4.03e-5 BITS out of 32768: it is not
-- a constraint worth paying for, it is a PROPERTY OF THE GROUND
-- STATE (TE1, TE2).
--
--   E  =  (bits the wire would carry at maximal disorder)
--         −  (bits the wire must carry for this frame)
--
--      =  N·log₂K − N·H₀  =  Σᵢ nᵢ·log₂(nᵢ/16)   bits
--
-- with N = 4096 cells, K = 256 colors, N/K = 16 = the rung. It is
-- N·D(p‖uniform): a Kullback–Leibler divergence in the wire's own
-- units. Zero exactly at the balanced tiling; 32768 at a solid
-- frame; and — TE10 — already computable from the RATE LEDGER's
-- traced H₀, so it costs no new measurement.
--
-- The plane enters twice: once by fixing N (hence the ground count
-- 16), and once as a SECOND STRATUM in the same currency — the bond
-- field, E_wall = B(1 − h(w)) over B = 8064 open bonds (TE8). Note
-- what that fixes: in bits, the Néel checkerboard is maximally
-- ORDERED (w = 1), not maximally energetic. PhaseEnergy's linear
-- Ising w is the AF-asymmetric currency; this is the informational
-- one, and only this one telescopes with the rate ladder.
--
-- Honesty: E is negentropy measured from the balanced macrostate.
-- Its conjugate temperature is exactly 1 bit per bit (TE10) — there
-- is no fitted scale, no naked constant. The app's temperature-LIKE
-- axis (E_var, PhaseEnergy §2) stays CHROMATIC; it does not
-- multiply this quantity.
-- ════════════════════════════════════════════════════════════════

module TilingEntropy where

import Data.List (sort)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE PLANE AND ITS COUNTS
-- ════════════════════════════════════════════════════════════════

side, cells, colors, balanced, bonds :: Int
side     = 64
cells    = side * side          -- N = 4096
colors   = 256                  -- K
balanced = cells `div` colors   -- 16 — the ground occupancy, = the rung
bonds    = 2 * side * (side - 1) -- B = 8064 open-lattice bonds

-- | log₂ of the unconstrained tiling count |Ω| = K^N, in bits.
omegaBits :: Double
omegaBits = fromIntegral cells * logBase 2 (fromIntegral colors)

-- | Surjections from n labelled cells onto k labelled colors —
--   exact inclusion–exclusion, = k!·S(n,k).
surjections :: Int -> Int -> Integer
surjections k n = sum
  [ (if even j then 1 else -1) * binom k j * fromIntegral (k - j) ^ n
  | j <- [0 .. k] ]

binom :: Int -> Int -> Integer
binom n r = product [ fromIntegral (n - i) | i <- [0 .. r - 1] ]
            `div` product [ fromIntegral i | i <- [1 .. r] ]

-- | Stirling numbers of the second kind (recurrence) — the small-case
--   cross-check that `surjections` is the right count.
stirling2 :: Int -> Int -> Integer
stirling2 n k
  | n == 0 && k == 0 = 1
  | n == 0 || k == 0 = 0
  | otherwise = fromIntegral k * stirling2 (n - 1) k + stirling2 (n - 1) (k - 1)

factorial :: Int -> Integer
factorial n = product [ 1 .. fromIntegral n ]

-- | The fraction of tilings that MISS at least one color, to 20
--   decimal places (integer arithmetic — no Double ever sees the
--   9,865-digit numbers).
missingFraction :: Double
missingFraction =
  fromIntegral ((total - surj) * (10 ^ (20 :: Int)) `div` total) / 1e20
  where
    total = fromIntegral colors ^ cells :: Integer
    surj  = surjections colors cells

-- | The entropy PRICE of demanding every color appear, in bits.
surjectivityBits :: Double
surjectivityBits = negate (logBase 2 (1 - missingFraction))

-- ════════════════════════════════════════════════════════════════
-- § 2. THE ENERGY (index stratum)
-- ════════════════════════════════════════════════════════════════

-- | Occupancy histogram of an index frame.
histogram :: [Int] -> [Int]
histogram f = [ length (filter (== i) f) | i <- [0 .. colors - 1] ]

-- | Zeroth-order entropy of the frame, bits/cell ∈ [0, 8].
h0 :: [Int] -> Double
h0 hist = negate (sum [ p * logBase 2 p | c <- hist, c > 0
                      , let p = fromIntegral c / n ])
  where n = fromIntegral (sum hist)

-- | ★ THE ENERGY. E = Σ nᵢ log₂(nᵢ/16) bits = N·D(p‖u).
--   Ground state 0 (balanced, hence surjective); ceiling N·log₂K.
energy :: [Int] -> Double
energy hist = sum [ fromIntegral c * logBase 2 (fromIntegral c / nb)
                  | c <- hist, c > 0 ]
  where nb = fromIntegral (sum hist) / fromIntegral colors

-- | Intensive form: bits per cell ∈ [0, 8].
energyPerCell :: [Int] -> Double
energyPerCell hist = energy hist / fromIntegral (sum hist)

-- | The EXACT Boltzmann form: E_B = log₂ W_balanced − log₂ W(n),
--   W(n) = the multinomial N!/∏nᵢ! (how many frames wear this
--   histogram). Same zero, ceiling log₂W_balanced = 31922.01 bits.
logMultiplicityBits :: [Int] -> Double
logMultiplicityBits hist =
  logFactBits (sum hist) - sum (map logFactBits hist)

logFactBits :: Int -> Double
logFactBits n = sum [ logBase 2 (fromIntegral k) | k <- [1 .. n] ]

groundMultiplicityBits :: Double
groundMultiplicityBits = logMultiplicityBits (replicate colors balanced)

energyExact :: [Int] -> Double
energyExact hist = groundMultiplicityBits - logMultiplicityBits hist

-- ════════════════════════════════════════════════════════════════
-- § 3. THE PAIR-TREE DECOMPOSITION (the chain rule)
-- ════════════════════════════════════════════════════════════════
-- The 256 histogram is a depth-8 dyadic tree (PairTree). The energy
-- splits EXACTLY into eight rungs, one per bit — the root bit is the
-- σ split (index ≥ 128), so the first rung is the φ order parameter
-- itself (TE5), and the leaf bit is the sibling map s₀.

-- | Binary entropy from two counts, bits (0 when either side empty).
hBin :: Int -> Int -> Double
hBin a b
  | a == 0 || b == 0 = 0
  | otherwise = negate (p * logBase 2 p + q * logBase 2 q)
  where
    n = fromIntegral (a + b); p = fromIntegral a / n; q = fromIntegral b / n

-- | Energy of each tree level, root (bit 7 = σ) first.
levelEnergies :: [Int] -> [Double]
levelEnergies hist = go [hist]
  where
    go nodes
      | null nodes || length (head nodes) < 2 = []
      | otherwise =
          let halves = [ splitAt (length nd `div` 2) nd | nd <- nodes ]
              lvl = sum [ fromIntegral (sum l + sum r) * (1 - hBin (sum l) (sum r))
                        | (l, r) <- halves ]
              next = [ h | (l, r) <- halves, h <- [l, r], length h >= 2 ]
          in lvl : go next

phiOf :: [Int] -> Double
phiOf hist = fromIntegral (sum (drop 128 hist)) / fromIntegral (sum hist)

-- ════════════════════════════════════════════════════════════════
-- § 4. THE SPATIAL STRATUM (the plane, not just the palette)
-- ════════════════════════════════════════════════════════════════
-- Same currency, binary alphabet: the bond field over the open
-- lattice. w = wall fraction; maximal disorder is w = ½.

spin :: Int -> Bool
spin i = i >= 128

wallCount :: [Int] -> Int
wallCount f = length
  [ () | y <- [0 .. side - 1], x <- [0 .. side - 1]
       , (dx, dy) <- [(1, 0), (0, 1)]
       , x + dx < side, y + dy < side
       , spin (f !! (y * side + x)) /= spin (f !! ((y + dy) * side + (x + dx))) ]

wallEnergy :: [Int] -> Double
wallEnergy f = fromIntegral bonds * (1 - hBin w (bonds - w))
  where w = wallCount f

-- ════════════════════════════════════════════════════════════════
-- § 5. PROBE FRAMES (deterministic — house lcg)
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

bayerOrder :: [Int]
bayerOrder = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

solidFrame, neelFrame, balancedFrame :: [Int]
solidFrame = replicate cells 255
neelFrame  = [ if bayerOrder !! ((y `mod` 4) * 4 + (x `mod` 4)) < 8 then 255 else 0
             | y <- [0 .. side - 1], x <- [0 .. side - 1] ]
-- Every color exactly 16 times: the palette laid flat on the plane.
balancedFrame = [ (y * side + x) `mod` colors
                | y <- [0 .. side - 1], x <- [0 .. side - 1] ]

randomFrame :: Int -> [Int]
randomFrame seed = [ floor (u * fromIntegral colors)
                   | u <- take cells (uniforms seed) ]

faceFrame :: Int -> [Int]
faceFrame seed = [ floor (u * 128) | u <- take cells (uniforms seed) ]

probeHists :: [[Int]]
probeHists = map histogram
  [ solidFrame, neelFrame, balancedFrame, faceFrame 7
  , randomFrame 3, randomFrame 11, threeRegion 5 ]

-- Solid rows / Néel band / random face — PhaseEnergy's probe.
threeRegion :: Int -> [Int]
threeRegion seed =
  [ pick y x | y <- [0 .. side - 1], x <- [0 .. side - 1] ]
  where
    face = faceFrame seed
    pick y x
      | y < 20 = 255
      | y < 44 = if bayerOrder !! ((y `mod` 4) * 4 + (x `mod` 4)) < 8 then 255 else 64
      | otherwise = face !! (y * side + x)

-- ════════════════════════════════════════════════════════════════
-- § 6. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (TE1) THE STATE SPACE. |Ω| = 256^4096 ⇒ 32768 bits exactly. The
--       surjective subset is 256!·S(4096,256) (formula cross-checked
--       against the Stirling recurrence at small n,k), and demanding
--       it costs under 2⁻¹⁴ bits — surjectivity is FREE.
axiom_TE1 :: Bool
axiom_TE1 =
     omegaBits == 32768
  && and [ surjections k n == factorial k * stirling2 n k
         | (n, k) <- [(5, 3), (6, 4), (7, 2), (8, 5), (9, 9), (6, 6)] ]
  && surjectivityBits > 0
  && surjectivityBits < 2 ** (-14)
  && abs (missingFraction - 2.792000135e-5) < 1e-14

-- (TE2) THE GROUND STATE IS THE SURJECTION. E = 0 exactly at
--       nᵢ = N/K = 16 for all i — and that state uses every color,
--       so the "at least once" condition is implied, never imposed.
--       Any histogram with an unused color has E > 0.
axiom_TE2 :: Bool
axiom_TE2 =
     balanced * colors == cells
  && energy (replicate colors balanced) == 0
  && energyExact (replicate colors balanced) == 0
  && all (== balanced) (histogram balancedFrame)
  && all (> 0) [ energy h | h <- probeHists, any (== 0) h ]
  && all (\h -> energy h < 1e-9) [ histogram balancedFrame ]

-- (TE3) RANGE. 0 ≤ E ≤ N·log₂K, the ceiling attained exactly by a
--       solid frame; the intensive form lives in [0, 8] bits/cell.
axiom_TE3 :: Bool
axiom_TE3 =
     all (\h -> energy h >= -1e-9 && energy h <= omegaBits + 1e-9) probeHists
  && abs (energy (histogram solidFrame) - omegaBits) < 1e-9
  && abs (energyPerCell (histogram solidFrame) - 8) < 1e-12
  && abs (energyPerCell (histogram balancedFrame)) < 1e-12
  && all (\h -> let e = energyPerCell h in e >= -1e-12 && e <= 8 + 1e-12) probeHists

-- (TE4) THE PAIR-TREE CHAIN RULE. E = Σ over the eight dyadic
--       levels of n_v·(1 − h(θ_v)) — the energy is stratified by the
--       same tree the palette is (s_ℓ = i XOR 2^ℓ), exactly.
axiom_TE4 :: Bool
axiom_TE4 =
     all (\h -> length (levelEnergies h) == 8) probeHists
  && all (\h -> abs (sum (levelEnergies h) - energy h) < 1e-6) probeHists
  && all (\h -> all (>= -1e-9) (levelEnergies h)) probeHists

-- (TE5) THE FIRST RUNG IS φ. The root level (the σ split, index
--       ≥ 128) is exactly N·(1 − h(φ)) — PhaseEnergy's order
--       parameter re-read as energy. No new observable is needed for
--       the top of the ladder.
axiom_TE5 :: Bool
axiom_TE5 = all agree probeHists
  where
    agree h =
      let n = sum h
          e0 = fromIntegral n * (1 - hBin (sum (take 128 h)) (sum (drop 128 h)))
      in abs (head (levelEnergies h) - e0) < 1e-9
         && abs (phiOf h * fromIntegral n - fromIntegral (sum (drop 128 h))) < 1e-9

-- (TE6) LABEL INVARIANCE. E depends on the histogram as a MULTISET:
--       any permutation of the 256 labels — in particular σ(i)=255−i
--       and every sibling map s_ℓ — leaves it fixed. (The tree
--       decomposition does not: rungs are basis-dependent, which is
--       exactly why the tree is a choice and the total is not.)
axiom_TE6 :: Bool
axiom_TE6 =
     all (\h -> abs (energy (reverse h) - energy h) < 1e-9) probeHists
  && all (\h -> abs (energy (sort h) - energy h) < 1e-9) probeHists
  && all (\h -> abs (energy (sigmaPerm h) - energy h) < 1e-9) probeHists
  && all (\h -> abs (energyExact (sigmaPerm h) - energyExact h) < 1e-9) probeHists
  where sigmaPerm h = [ h !! (255 - i) | i <- [0 .. 255] ]

-- (TE7) THE EXACT BOLTZMANN TWIN. E_B = log₂W_bal − log₂W(n) shares
--       the zero, is non-negative, is bounded by E (Stirling's
--       correction is a debit), and its ceiling is the ground
--       multiplicity 31922.0109 bits — the honest microcanonical
--       number when the frame is small enough for it to matter.
axiom_TE7 :: Bool
axiom_TE7 =
     abs (groundMultiplicityBits - 31922.0109296453) < 1e-6
  && all (\h -> energyExact h >= -1e-6) probeHists
  && all (\h -> energyExact h <= energy h + 1e-6) probeHists
  && abs (energyExact (histogram solidFrame) - groundMultiplicityBits) < 1e-6
  && groundMultiplicityBits < omegaBits

-- (TE8) THE SPATIAL STRATUM. The plane's own energy in the same
--       currency: B(1 − h(w)) over the 8064 open bonds. ★ Order and
--       ANTI-order cost the same — solid (w=0) and Néel (w=1) both
--       sit at the ceiling B, while a random frame sits near zero.
--       PhaseEnergy's linear w does NOT have this symmetry; it is a
--       different (ferromagnetic) currency and must not be summed
--       with bits.
axiom_TE8 :: Bool
axiom_TE8 =
     abs (wallEnergy solidFrame - fromIntegral bonds) < 1e-9
  && abs (wallEnergy neelFrame  - fromIntegral bonds) < 1e-9
  && wallCount solidFrame == 0
  && wallCount neelFrame == bonds
  && wallEnergy (randomFrame 3) < 10
  && all (\f -> wallEnergy f >= -1e-9
             && wallEnergy f <= fromIntegral bonds + 1e-9)
         [solidFrame, neelFrame, randomFrame 3, threeRegion 5, balancedFrame]

-- (TE9) TELESCOPING TO THE CUBE. The 64-frame export is the same law
--       at N = 64·4096: ceiling 2,097,152 bits = 256 KiB — the width
--       of the wire the GIF is compressing. Frame energies add;
--       the cube's own energy is at least their mean (a frame-mixed
--       histogram cannot be more ordered than its parts on average —
--       concavity of H₀).
axiom_TE9 :: Bool
axiom_TE9 =
     cubeCeiling == 2097152
  && cubeCeiling `div` 8 `div` 1024 == 256
  && energy pooled + 1e-6 >= meanFrameEnergy - 1e-6
  && meanFrameEnergy >= 0
  where
    cubeCeiling = 64 * cells * 8 :: Int
    frames = [ randomFrame 3, faceFrame 7, threeRegion 5, solidFrame ]
    pooled = foldr1 (zipWith (+)) (map histogram frames)
    meanFrameEnergy = sum (map (energy . histogram) frames)
                        / fromIntegral (length frames)

-- (TE10) CALIBRATION — one bit of saving is one unit of energy, so
--        the quantity has NO free scale (no temperature to tune, no
--        naked constant): E = N·log₂K − N·H₀, i.e. exactly the bits
--        the ideal zeroth-order coder does not spend. The RATE
--        LEDGER already traces H₀, so E is readable off the wire.
axiom_TE10 :: Bool
axiom_TE10 = all ledgerIdentity probeHists
  where
    ledgerIdentity h =
      let n = fromIntegral (sum h)
      in abs (energy h - (n * 8 - n * h0 h)) < 1e-6

-- ════════════════════════════════════════════════════════════════
-- § 7. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " TilingEntropy: the energy of 256 colors on the 64×64"
  putStrLn " E = N·log₂K − N·H₀ = Σ nᵢ log₂(nᵢ/16) bits"
  putStrLn " ground = every color exactly 16× (hence surjective)"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "TE1  state space: 32768 b; surjectivity costs < 2⁻¹⁴ b"   [axiom_TE1]
  check "TE2  ground state E=0 ⟺ nᵢ=16 ∀i ⇒ surjective by law"     [axiom_TE2]
  check "TE3  range: E ∈ [0, 32768] b, ε ∈ [0,8] b/cell, tight"    [axiom_TE3]
  check "TE4  pair-tree chain rule: E = Σ 8 dyadic rungs, exact"   [axiom_TE4]
  check "TE5  first rung = N(1−h(φ)) — the order parameter is E₀"  [axiom_TE5]
  check "TE6  label invariance (σ, siblings, any permutation)"     [axiom_TE6]
  check "TE7  Boltzmann twin E_B ≤ E, ceiling = 31922.0109 b"      [axiom_TE7]
  check "TE8  spatial stratum B(1−h(w)): order ≡ anti-order"       [axiom_TE8]
  check "TE9  cube telescoping: 2,097,152 b = 256 KiB of wire"     [axiom_TE9]
  check "TE10 calibration: E = the bits H₀ already reports"        [axiom_TE10]
  putStrLn ""
  putStrLn "── THE NUMBERS ───────────────────────────────────────────"
  putStrLn $ "  |Ω| = 256^4096          : " ++ show omegaBits ++ " bits"
  putStrLn $ "  surjective fraction     : "
               ++ show (1 - missingFraction)
  putStrLn $ "  price of surjectivity   : " ++ show surjectivityBits ++ " bits"
  putStrLn $ "  ground multiplicity     : "
               ++ show groundMultiplicityBits ++ " bits"
  putStrLn ""
  putStrLn "  frame            E (bits)   E_B (bits)   ε (b/cell)  used"
  mapM_ row
    [ ("balanced", balancedFrame), ("random", randomFrame 3)
    , ("face 0..127", faceFrame 7), ("three-region", threeRegion 5)
    , ("néel k=8", neelFrame), ("solid", solidFrame) ]
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  Energy is negentropy in the wire's own units. The"
  putStrLn "  balanced tiling — every one of the 256 exactly 16 times,"
  putStrLn "  16 = the rung, the palette laid flat on the plane — is"
  putStrLn "  the zero, and it satisfies 'use all 256' for free. Every"
  putStrLn "  bit of structure the capture puts on the plane is a bit"
  putStrLn "  the GIF does not have to carry, so E is not a metaphor"
  putStrLn "  for compression: it IS the ledger, read from the other"
  putStrLn "  end. Strata add in bits (index rungs by the pair tree,"
  putStrLn "  bonds by the plane); currencies that are not bits do not."
  putStrLn "══════════════════════════════════════════════════════════"

row :: (String, [Int]) -> IO ()
row (name, f) = putStrLn $
  "  " ++ pad 17 name
       ++ pad 11 (fmt (energy h))
       ++ pad 13 (fmt (energyExact h))
       ++ pad 12 (fmt (energyPerCell h))
       ++ show (length (filter (> 0) h))
  where
    h = histogram f
    fmt v = show (fromIntegral (round (v * 100) :: Integer) / 100 :: Double)
    pad n s = s ++ replicate (max 1 (n - length s)) ' '

check :: String -> [Bool] -> IO ()
check name results =
  let mark = if and results then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
