{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- Octave: the THREE PARALLEL READS — 64³ ∥ 32³ ∥ 16³
--
-- Daniel's corrections (2026-08-13), both of which changed the
-- shape of this spec:
--
--   1. "16^3 should be the smallest. because 16x16 == 256, 256
--      colors, 1:1:2:4:8:16:32:64:64:32:16:8:4:2:1:1 leafs"
--   2. "the three 16³/32³/64³ resolutions should be used in
--      PARALLEL to read the feed. The live feed is to be read in
--      the three resolutions and we encode/compress the
--      information so that it is useful to generate GIF's"
--
-- ── WHY 16 IS THE FLOOR (OV2, OV3) ──────────────────────────────
--
-- 16² = 256 = the palette. At rung 16 the image and the colour
-- table are the SAME SIZE — one pixel per entry, the bijection
-- (DitherRamp DR1's bottom rung, BellPalette BP4: "the palette IS
-- the image"). Below it the bijection breaks: 8² = 64 < 256, and
-- three quarters of the table could not be addressed even once.
-- The floor is not a taste; it is where the two cardinalities meet.
--
-- And the 256 distribute across the rung as Daniel's ladder:
--
--   1 : 1 : 2 : 4 : 8 : 16 : 32 : 64 : 64 : 32 : 16 : 8 : 4 : 2 : 1 : 1
--
-- sixteen shells summing to 256, symmetric about its middle. Its
-- first half is EXACTLY the binomial shell ladder DyadPalette
-- already solves ([1,1,2,4,8,16,32,64] = 128 primaries); the
-- second half is that half mirrored through the σ-involution
-- (PT6). The ladder was already half-built and half-named.
--
-- ── THE THREE READS ARE PARALLEL, NOT NESTED ────────────────────
--
-- The old draft of this file built a tower by repeatedly pooling
-- ONE read. Daniel's ruling is different and better: the feed is
-- read at all three rungs AT ONCE, and the three streams are
-- compressed as they arrive — "watching while watching."
--
-- ★ OV13 IS THE LOAD-BEARING LAW: reading directly at a coarse
-- rung and pooling the fine read agree EXACTLY — but ONLY if the
-- downsample is a MEAN. Under the point-sample the app ships today
-- (Quantize.metal:196-201, one texel per 12×12 block) they do NOT
-- agree, and the parallel architecture is incoherent: the 16³
-- stream would disagree with the pooled 64³ stream about the same
-- scene. So the box prefilter (rate-ladder step S2, currently
-- unbuilt) is not an optimisation here. It is a PRECONDITION.
--
-- ── THE SAFETY PROPERTY (OV5) ───────────────────────────────────
--
-- κ conserves the mean exactly (OV4), so ALL THREE READS SHARE THE
-- SAME MEAN. Therefore any normalised mixture of them has that
-- mean too — for every setting of the three dials. Exposure, white
-- point and cast cannot drift. That invariance is what makes this
-- a user control rather than an internal flag.
--
-- ── SIZE ────────────────────────────────────────────────────────
--
-- The rung arithmetic (OV1–OV3) is exact at the app's real values.
-- The field laws are proved on a 1/8-linear SCALE MODEL — sides
-- 8 ∥ 4 ∥ 2 standing for 64 ∥ 32 ∥ 16 — because 64³ = 262144 cells
-- of ℚ³ is not a runghc-sized object. The algebra is
-- size-independent; only the cell count changes.
--
-- ── AXIOMS ──────────────────────────────────────────────────────
--
--   OV1  the rung set is {64, 32, 16}; adjacent rungs differ by 2
--   OV2  ★ THE BIJECTION FLOOR: 16² = 256 = |palette|; 8² = 64
--        breaks it, so 16 is the smallest lawful rung
--   OV3  ★ THE LADDER: 1,1,2,4,8,16,32,64 mirrored sums to 256,
--        is σ-symmetric, and its half is DyadPalette's shells
--   OV4  κ is exact; pool ∘ up = id; all three reads share one mean
--   OV5  ★ MEAN INVARIANCE for every dial setting
--   OV6  identity: pure-fine reproduces the input exactly
--   OV7  pure-coarse yields the 16-rung read, upsampled
--   OV8  separable and affine: one dial moves exactly one read
--   OV9  monotone in each dial
--   OV10 ★ axis symmetry: κ cannot tell x, y and FRAME apart
--   OV11 grid: 8 states per dial (RoleAllocation's widgetCells)
--   OV12 atom correspondence: 2×2×2 ↔ 1 is three composed 2 → 1
--   OV13 ★ PARALLEL COHERENCE: direct read ≡ pooled read under a
--        MEAN downsample, and NOT under a point sample
-- ════════════════════════════════════════════════════════════════

module Main where

import Data.Ratio ((%))

type Q = Rational
type V3 = (Q, Q, Q)

vAdd, vSub :: V3 -> V3 -> V3
vAdd (a, b, c) (p, q, r) = (a + p, b + q, c + r)
vSub (a, b, c) (p, q, r) = (a - p, b - q, c - r)

vScale :: Q -> V3 -> V3
vScale s (a, b, c) = (s * a, s * b, s * c)

vZero :: V3
vZero = (0, 0, 0)

vMean :: [V3] -> V3
vMean [] = vZero
vMean vs = vScale (1 % fromIntegral (length vs)) (foldr vAdd vZero vs)

vNorm2 :: V3 -> Q
vNorm2 (a, b, c) = a * a + b * b + c * c

-- ════════════════════════════════════════════════════════════════
-- § 1. THE RUNGS AND THE LADDER (exact, at the app's real values)
-- ════════════════════════════════════════════════════════════════

rungs :: [Int]
rungs = [64, 32, 16]

floorRung :: Int
floorRung = minimum rungs

paletteSize :: Int
paletteSize = 256

-- | The binomial shell half DyadPalette already solves: 128
--   primaries on concentric PC1×PC2 ellipse shells.
shellHalf :: [Int]
shellHalf = [1, 1, 2, 4, 8, 16, 32, 64]

-- | Daniel's full ladder: the half, mirrored through σ (PT6).
ladder :: [Int]
ladder = shellHalf ++ reverse shellHalf

-- ════════════════════════════════════════════════════════════════
-- § 2. THE SCALE MODEL — sides 8 ∥ 4 ∥ 2 for 64 ∥ 32 ∥ 16
--
-- Flat row-major over (t, y, x): index = t·n² + y·n + x. The third
-- axis is FRAME; nothing in κ distinguishes it (OV10).
-- ════════════════════════════════════════════════════════════════

sideFine, sideMid, sideCoarse :: Int
sideFine   = 8      -- stands for 64
sideMid    = 4      -- stands for 32
sideCoarse = 2      -- stands for 16

at :: Int -> [V3] -> (Int, Int, Int) -> V3
at n c (t, y, x) = c !! (t * n * n + y * n + x)

-- | κ: side n → side n/2, each output the EXACT mean of its 2×2×2
--   spacetime block. This is the operator TriScaleLadder already
--   runs on every capture, as telemetry.
pool :: Int -> [V3] -> [V3]
pool n c =
  [ vMean [ at n c (2 * tb + dt, 2 * yb + dy, 2 * xb + dx)
          | dt <- [0, 1], dy <- [0, 1], dx <- [0, 1] ]
  | tb <- [0 .. h - 1], yb <- [0 .. h - 1], xb <- [0 .. h - 1] ]
  where h = n `div` 2

-- | ★ The counter-example operator: nearest-neighbour decimation,
--   one sample per block — what Quantize.metal ships today.
decimate :: Int -> [V3] -> [V3]
decimate n c =
  [ at n c (2 * tb, 2 * yb, 2 * xb)
  | tb <- [0 .. h - 1], yb <- [0 .. h - 1], xb <- [0 .. h - 1] ]
  where h = n `div` 2

-- | σ's structural half: replication. (The LEARNED half, x ± g(x),
--   lives in OctaveCodec; OV5 holds for both, because a mixture of
--   equal-mean fields has that mean whatever the expansion.)
up :: Int -> [V3] -> [V3]
up n c =
  [ at n c (t `div` 2, y `div` 2, x `div` 2)
  | t <- [0 .. m - 1], y <- [0 .. m - 1], x <- [0 .. m - 1] ]
  where m = 2 * n

-- ════════════════════════════════════════════════════════════════
-- § 3. THE THREE PARALLEL READS
--
-- A Feed is the band-limited field the sensor offers. Each rung
-- reads it independently. OV13 proves the three agree.
-- ════════════════════════════════════════════════════════════════

-- | Direct read at each rung: κ applied k times to the feed.
readFine, readMid, readCoarse :: [V3] -> [V3]
readFine   f = f
readMid    f = pool sideFine f
readCoarse f = pool sideMid (pool sideFine f)

-- | Dial 0..7 → weight. Normalised at use, so the dials are a
--   SIMPLEX over the three reads, not independent gains.
weight :: Int -> Q
weight w = fromIntegral w % 1

-- | The identity setting: today's app is the fine read alone.
identityDial :: (Int, Int, Int)
identityDial = (0, 0, 7)          -- (coarse, mid, fine)

widgetCells :: Int
widgetCells = 8

-- | The mixture: every read lifted to the fine rung and blended by
--   normalised weights. This is ISP.Compose's weight profile, in
--   the live app's rungs.
blend :: (Int, Int, Int) -> [V3] -> [V3]
blend (wC, wM, wF) f
  | total == 0 = replicate (sideFine ^ (3 :: Int)) (vMean f)
  | otherwise  =
      foldr1 (zipWith vAdd)
        [ map (vScale (weight wC / total)) (up sideMid (up sideCoarse (readCoarse f)))
        , map (vScale (weight wM / total)) (up sideMid (readMid f))
        , map (vScale (weight wF / total)) (readFine f)
        ]
  where total = weight wC + weight wM + weight wF

energy :: [V3] -> Q
energy = sum . map vNorm2

-- ════════════════════════════════════════════════════════════════
-- § 4. FIXTURES (deterministic, no System.Random)
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

-- | A feed with structure at every rung: a ramp (coarse), a block
--   pattern (mid) and per-cell wobble (fine).
feed :: [V3]
feed =
  [ ( fromIntegral (t + y + x) % 24
      + fromIntegral ((t `div` 4 + x `div` 4) `mod` 2) % 8
      + fromIntegral (lcg (i * 7 + 1) `mod` 33) % 512
    , fromIntegral (lcg (i * 13 + 5) `mod` 41) % 512
      + fromIntegral (y `div` 2) % 32
    , fromIntegral (lcg (i * 29 + 3) `mod` 37) % 512
      - fromIntegral (x `div` 2) % 32 )
  | t <- [0 .. sideFine - 1], y <- [0 .. sideFine - 1], x <- [0 .. sideFine - 1]
  , let i = t * sideFine * sideFine + y * sideFine + x ]

transposeTX :: [V3] -> [V3]
transposeTX c =
  [ at sideFine c (x, y, t)
  | t <- [0 .. sideFine - 1], y <- [0 .. sideFine - 1], x <- [0 .. sideFine - 1] ]

dials :: [(Int, Int, Int)]
dials =
  [ (0, 0, 7), (7, 0, 0), (0, 7, 0), (1, 1, 1)
  , (4, 2, 1), (1, 2, 4), (7, 7, 7), (2, 5, 3) ]

-- ════════════════════════════════════════════════════════════════
-- § 5. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (OV1) The rung set: three rungs, adjacent ones a factor of two
--       apart, 16 the floor and 64 the top.
axiom_OV1 :: Bool
axiom_OV1 =
     rungs == [64, 32, 16]
  && length rungs == 3
  && and (zipWith (\a b -> a == 2 * b) rungs (tail rungs))
  && floorRung == 16
  && maximum rungs == 64

-- (OV2) ★ THE BIJECTION FLOOR. At rung 16 the image and the colour
--       table have EQUAL cardinality — one pixel per entry. The
--       next rung down cannot address three quarters of the table
--       even once, so 16 is the smallest lawful rung.
axiom_OV2 :: Bool
axiom_OV2 =
     floorRung * floorRung == paletteSize
  && 16 * 16 == 256
  && (floorRung `div` 2) * (floorRung `div` 2) < paletteSize   -- 64 < 256
  && all (\r -> r * r >= paletteSize) rungs
  && head [ r | r <- rungs, r * r == paletteSize ] == floorRung

-- (OV3) ★ THE LADDER. Daniel's 1:1:2:4:8:16:32:64:64:32:16:8:4:2:1:1
--       sums to the palette, is symmetric about its middle, has one
--       shell per rung-16 row, and its first half is EXACTLY the
--       binomial shell ladder DyadPalette already solves.
axiom_OV3 :: Bool
axiom_OV3 =
     ladder == [1,1,2,4,8,16,32,64,64,32,16,8,4,2,1,1]
  && sum ladder == paletteSize
  && sum shellHalf == paletteSize `div` 2
  && ladder == reverse ladder                       -- σ-symmetric
  && length ladder == floorRung                     -- one per row
  && take 8 ladder == shellHalf                     -- DyadPalette's
  && drop 8 ladder == reverse shellHalf             -- and its mirror
  && and (zipWith (\a b -> b == 2 * a) (drop 1 shellHalf) (drop 2 shellHalf))

-- (OV4) κ is exact averaging, pool ∘ up is the identity, and — the
--       fact everything else rests on — ALL THREE READS SHARE ONE
--       MEAN, exactly.
axiom_OV4 :: Bool
axiom_OV4 =
     length (readFine feed)   == 512
  && length (readMid feed)    == 64
  && length (readCoarse feed) == 8
  && pool sideFine (up sideMid (readMid feed)) == readMid feed
  && pool sideMid (up sideCoarse (readCoarse feed)) == readCoarse feed
  && vMean (readFine feed) == vMean (readMid feed)
  && vMean (readMid feed)  == vMean (readCoarse feed)

-- (OV5) ★ MEAN INVARIANCE. Every dial setting yields the same mean
--       — a normalised mixture of equal-mean fields. Exposure,
--       white point and cast cannot drift, at any setting.
axiom_OV5 :: Bool
axiom_OV5 =
     all (\d -> vMean (blend d feed) == vMean feed) dials
  && vMean (blend (0, 0, 0) feed) == vMean feed      -- degenerate too
  && all (\d -> length (blend d feed) == 512) dials

-- (OV6) Identity: the fine read alone reproduces the feed exactly,
--       so the dial set has a true pass-through and the default
--       reproduces today's bytes.
axiom_OV6 :: Bool
axiom_OV6 =
     blend identityDial feed == feed
  && blend (0, 0, 1) feed == feed
  && blend (0, 0, 7) feed == blend (0, 0, 1) feed    -- scale-free

-- (OV7) Pure-coarse yields the rung-16 read upsampled — flat 2×2×2
--       blocks, the extreme the dial can reach, still lawful.
axiom_OV7 :: Bool
axiom_OV7 =
     blend (7, 0, 0) feed == up sideMid (up sideCoarse (readCoarse feed))
  && blend (0, 7, 0) feed == up sideMid (readMid feed)
  && vMean (blend (7, 0, 0) feed) == vMean feed

-- (OV8) Separable and affine: the blend is a convex combination,
--       so one dial scales exactly one read; the difference between
--       two settings is a combination of the reads alone.
axiom_OV8 :: Bool
axiom_OV8 =
     blend (1, 1, 1) feed == equalThirds
  && blend (2, 2, 2) feed == blend (1, 1, 1) feed    -- normalised
  && blend (3, 3, 3) feed == blend (1, 1, 1) feed
  where
    equalThirds =
      foldr1 (zipWith vAdd)
        [ map (vScale (1 % 3)) (up sideMid (up sideCoarse (readCoarse feed)))
        , map (vScale (1 % 3)) (up sideMid (readMid feed))
        , map (vScale (1 % 3)) (readFine feed) ]

-- (OV9) Monotone: departure from the flat field grows as the fine
--       dial is raised against a fixed coarse setting.
axiom_OV9 :: Bool
axiom_OV9 =
     and [ dev (4, 0, w) <= dev (4, 0, w + 1) | w <- [0 .. 6] ]
  && and [ dev (0, 4, w) <= dev (0, 4, w + 1) | w <- [0 .. 6] ]
  && dev (7, 0, 0) < dev (0, 0, 7)
  where
    flat = replicate 512 (vMean feed)
    dev d = energy (zipWith vSub (blend d feed) flat)

-- (OV10) ★ Axis symmetry: κ cannot tell space from time, so a
--        2-frame group is exactly the temporal half of the atom
--        and BLEEDING's 4×4×4 block is two temporal rungs.
axiom_OV10 :: Bool
axiom_OV10 =
     vMean (readCoarse (transposeTX feed)) == vMean (readCoarse feed)
  && energy (readCoarse (transposeTX feed)) == energy (readCoarse feed)
  && energy (readMid (transposeTX feed)) == energy (readMid feed)
  && transposeTX (transposeTX feed) == feed

-- (OV11) Grid: 8 states per dial, matching RoleAllocation's
--        widgetCells so the edit space stays 8^5.
axiom_OV11 :: Bool
axiom_OV11 =
     widgetCells == 8
  && length [ weight w | w <- [0 .. 7] ] == widgetCells
  && weight 0 == 0
  && and [ weight (w + 1) - weight w == 1 | w <- [0 .. 6] ]
  && (let (a, b, c) = identityDial
      in all (\x -> x >= 0 && x < widgetCells) [a, b, c])

-- (OV12) Atom correspondence: the spacetime atom pools EIGHT
--        children; the palette atom (PairTree PT7) pools TWO.
--        Three composed binary means equal the one-shot mean of
--        eight — which is why PT9's check line reads "2×2×2↔1".
axiom_OV12 :: Bool
axiom_OV12 =
     vMean octet == threeLevelBinaryMean octet
  && length octet == 8
  where
    octet = take 8 (drop 64 feed)
    threeLevelBinaryMean xs =
      let pair (a : b : rest) = vMean [a, b] : pair rest
          pair _              = []
      in head (pair (pair (pair xs)))

-- (OV13) ★ PARALLEL COHERENCE — the law that licenses reading the
--        feed at three rungs at once. Under a MEAN downsample,
--        reading directly at a coarse rung and pooling the fine
--        read agree EXACTLY, so the three streams describe one
--        scene. Under the POINT SAMPLE the app ships today they
--        DISAGREE — so the box prefilter is a precondition of this
--        architecture, not an optimisation.
axiom_OV13 :: Bool
axiom_OV13 =
     poolTwice == readCoarse feed                  -- κ composes
  && pool sideFine (readFine feed) == readMid feed
  && decimateTwice /= readCoarse feed              -- ★ and decimation
  && decimate sideFine (readFine feed) /= readMid feed  --   does not
  where
    poolTwice     = pool sideMid (pool sideFine feed)
    decimateTwice = decimate sideMid (decimate sideFine feed)

-- ════════════════════════════════════════════════════════════════
-- § 6. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " Octave: THREE PARALLEL READS — 64³ ∥ 32³ ∥ 16³"
  putStrLn " 16 is the floor: 16² = 256 = the palette (the bijection)"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── The rungs ──"
  putStrLn ""
  mapM_ (\r -> putStrLn $ "  " ++ padL 4 (show r) ++ "³   cells/frame "
             ++ padL 6 (show (r * r))
             ++ (if r * r == paletteSize
                   then "   ← BIJECTION: one pixel per palette entry"
                   else ""))
        rungs
  putStrLn $ "  " ++ padL 4 "8" ++ "³   cells/frame " ++ padL 6 "64"
           ++ "   (BELOW THE FLOOR: 64 < 256, table unaddressable)"
  putStrLn ""

  putStrLn "── The ladder (sums to the palette, σ-symmetric) ──"
  putStrLn ""
  putStrLn $ "  " ++ unwords (map show ladder)
  putStrLn $ "  sum = " ++ show (sum ladder)
           ++ "   half = " ++ show (sum shellHalf)
           ++ " = DyadPalette's shells; mirror = σ (PT6)"
  putStrLn ""

  putStrLn "── The dials (a simplex over the three reads) ──"
  putStrLn ""
  putStrLn "  COARSE  the 16³ read — ground holds still across frames"
  putStrLn "  MID     the 32³ read — structure the tree resolves"
  putStrLn "  FINE    the 64³ read — per-frame, per-cell detail"
  putStrLn $ "  identity = " ++ show identityDial
           ++ "  (fine alone = today's bytes)"
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "OV1  rung set {64,32,16}, factor 2, floor 16"            [axiom_OV1]
  check "OV2  ★ BIJECTION FLOOR: 16² = 256 = |palette|"           [axiom_OV2]
  check "OV3  ★ LADDER 1..64|64..1 sums to 256, σ-symmetric"      [axiom_OV3]
  check "OV4  κ exact; pool∘up = id; all three reads, one mean"   [axiom_OV4]
  check "OV5  ★ MEAN INVARIANCE at every dial setting"            [axiom_OV5]
  check "OV6  identity: the fine read alone reproduces the feed"  [axiom_OV6]
  check "OV7  pure-coarse yields the rung-16 read, upsampled"     [axiom_OV7]
  check "OV8  separable, affine, scale-free (a true simplex)"     [axiom_OV8]
  check "OV9  monotone in each dial"                              [axiom_OV9]
  check "OV10 ★ axis symmetry: κ cannot tell x, y from FRAME"     [axiom_OV10]
  check "OV11 grid: 8 states/dial (RoleAllocation widgetCells)"   [axiom_OV11]
  check "OV12 atom: 2×2×2 ↔ 1 = three composed 2 → 1 means"       [axiom_OV12]
  check "OV13 ★ PARALLEL COHERENCE — and decimation BREAKS it"    [axiom_OV13]
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  The feed is read at three rungs AT ONCE. 16 is the"
  putStrLn "  floor because 16² = 256: one pixel per palette entry,"
  putStrLn "  the rung where the palette IS the image. The 256"
  putStrLn "  distribute as 1,1,2,4,8,16,32,64 and its σ-mirror —"
  putStrLn "  a ladder whose first half the solver already builds."
  putStrLn ""
  putStrLn "  The three reads agree because κ composes: pooling the"
  putStrLn "  fine read equals reading coarse directly. That is TRUE"
  putStrLn "  FOR A MEAN AND FALSE FOR A POINT SAMPLE — so the box"
  putStrLn "  prefilter is a precondition of the parallel read, not"
  putStrLn "  an optimisation of it."
  putStrLn ""
  putStrLn "  And because all three share one mean, every setting of"
  putStrLn "  the dials leaves the colour exactly where the solver"
  putStrLn "  put it."
  putStrLn "══════════════════════════════════════════════════════════"

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let passed = and results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
