-- ════════════════════════════════════════════════════════════════
-- TriScaleLadder: the 64³ → 32³ → 16³ spacetime pyramid
--
-- PORTED from SixFour's color head (Spec.TriScaleTraining +
-- palette16.zig), adapted to Tesseract's export cube. The ladder is
-- ISOTROPIC: one 2×2×2 spacetime block (frame pair × 2×2 cells) per
-- coarse voxel, so side and frame count halve together:
--
--   rung │ cube      │ GIF delay │ rate   │ loop
--   ─────┼───────────┼───────────┼────────┼──────
--    64  │ 64×64×64  │   5 cs    │ 20 fps │ 3.2 s
--    32  │ 32×32×32  │  10 cs    │ 10 fps │ 3.2 s
--    16  │ 16×16×16  │  20 cs    │  5 fps │ 3.2 s
--
-- THE TIME LAW: side × delay = 320 cs at every rung — the loop's
-- wall-clock is rung-invariant, and the ladder CAPS at 64 because
-- 128 would need 2.5 cs, which GIF89a's integer centisecond field
-- cannot express (320 mod 128 ≠ 0).
--
-- THE CARRIER: exact integer block SUMS. Sums compose transitively
-- (pool₂ ∘ pool₂ = pool₄); rounded means do NOT (teeth-tested here,
-- as in SixFour: "u64 block-SUMS are the transitive pyramid
-- carrier"). The keystone is the microstate chain rule: W(fine)
-- telescopes into per-block conditional factors across rungs, so
-- the 16→32 and 32→64 transitions carry DISJOINT bits.
--
-- TESSERACT SCOPE (decree-bound): this ladder is MEASUREMENT ONLY.
-- It pools the realized sRGB8 colors of the exported 64³ index cube
-- into telemetry. No GIF byte depends on it, and it trains nothing
-- (★NO-CAPTURE-TRAINING). Distinct from quantization/
-- ResolutionLadder.hs, which gates per-cell resolution by subject
-- signal — that ladder spends pixels; this one accounts bits.
-- ════════════════════════════════════════════════════════════════

module TriScaleLadder where

import Data.List (nub, transpose)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE CUBE AND THE CARRIER (exact integer sums)
-- ════════════════════════════════════════════════════════════════

-- | A cube is frames × rows × cols of non-negative integer channel
-- values (in the app: one sRGB8 channel of the realized palette).
type Cube = [[[Integer]]]

chunk :: Int -> [a] -> [[a]]
chunk _ [] = []
chunk k xs = take k xs : chunk k (drop k xs)

add2 :: [[Integer]] -> [[Integer]] -> [[Integer]]
add2 = zipWith (zipWith (+))

-- | Sum-pool one frame over k×k spatial blocks.
poolFrame :: Int -> [[Integer]] -> [[Integer]]
poolFrame k rows =
  [ map sum (transpose (map (map sum . chunk k) rg)) | rg <- chunk k rows ]

-- | Sum-pool a cube over k×k×k spacetime blocks (frames too).
poolK :: Int -> Cube -> Cube
poolK k frames =
  [ foldr1 add2 (map (poolFrame k) fg) | fg <- chunk k frames ]

-- | One rung down: 2×2×2. The ladder is poolL . poolL.
poolL :: Cube -> Cube
poolL = poolK 2

total :: Cube -> Integer
total = sum . map (sum . map sum)

-- Rounded means (round-half-up), the carrier that DOESN'T compose.
meanR :: [Integer] -> Integer
meanR xs = (2 * sum xs + n) `div` (2 * n)
  where n = fromIntegral (length xs)

-- ════════════════════════════════════════════════════════════════
-- § 2. THE TIME LAW (GIF89a integer centiseconds)
-- ════════════════════════════════════════════════════════════════

-- | The loop's wall-clock, in centiseconds: 64 frames at 5 cs.
gifLoopCs :: Integer
gifLoopCs = 320

delayCs :: Integer -> Integer
delayCs s = gifLoopCs `div` s

rungs :: [Integer]
rungs = [64, 32, 16]

-- ════════════════════════════════════════════════════════════════
-- § 3. MICROSTATES (exact entropy: multinomial counts)
-- ════════════════════════════════════════════════════════════════

factorial :: Integer -> Integer
factorial n = product [1 .. n]

-- | W(counts): the number of microstates realizing the counts —
-- the multinomial coefficient. log W = the exact entropy in nats.
microstates :: [Integer] -> Integer
microstates cs = factorial (sum cs) `div` product (map factorial cs)

-- ════════════════════════════════════════════════════════════════
-- § 4. DENSITY ACCOUNTING (SixFour TriScaleTraining, verbatim)
--
-- Each 2×2×2 block has 8 children; the parent carries their sum,
-- leaving 7 residual degrees of freedom (the octant grading
-- 1+3+3+1 minus the total): 'detailBands' = 7.
-- ════════════════════════════════════════════════════════════════

detailBands :: Integer
detailBands = 7

blocksPerTransition :: Integer -> Integer
blocksPerTransition s = (s `div` 2) ^ (3 :: Int)

detailValuesPerTransition :: Integer -> Integer
detailValuesPerTransition s = detailBands * blocksPerTransition s

-- ════════════════════════════════════════════════════════════════
-- § 5. DETERMINISTIC PSEUDO-RANDOMNESS (no System.Random)
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

-- | Deterministic cube, side n, values in [0, 255].
cubeOf :: Int -> Int -> Cube
cubeOf seed n =
  chunk n (chunk n (take (n * n * n)
    [ fromIntegral (floor (u * 256) :: Int) | u <- uniforms seed ]))

seeds :: [Int]
seeds = [1 .. 6]

-- ════════════════════════════════════════════════════════════════
-- § 6. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (TL1) THE CARRIER COMPOSES: pool₂ ∘ pool₂ == pool₄ on the sum
--       carrier — the two-rung ladder equals the direct 4×4×4 pool,
--       exactly, for every cube.
axiom_TL1 :: Bool
axiom_TL1 = all ok seeds
  where ok seed = let c = cubeOf seed 16
                  in poolL (poolL c) == poolK 4 c

-- (TL2) ROUNDED MEANS DO NOT: there exist 4-tuples where the staged
--       rounded mean differs from the direct one (witness: 1,0,0,0
--       stages to 1 but directs to 0). Sums are the only lawful
--       carrier; means are a final realization, never a rung.
axiom_TL2 :: Bool
axiom_TL2 = not (null bad) && (1, 0, 0, 0) `elem` bad
  where
    bad = [ (a, b, c, d)
          | a <- [0 .. 3], b <- [0 .. 3], c <- [0 .. 3], d <- [0 .. 3]
          , meanR [meanR [a, b], meanR [c, d]] /= meanR [a, b, c, d] ]

-- (TL3) MASS CONSERVED: the cube's total is invariant down the
--       ladder — nothing dropped, nothing double-counted.
axiom_TL3 :: Bool
axiom_TL3 = all ok seeds
  where ok seed = let c = cubeOf seed 16
                  in total c == total (poolL c)
                  && total c == total (poolL (poolL c))

-- (TL4) THE TIME LAW: side × delay = 320 at every rung (the loop is
--       always 3.2 s), delays are the GIF-exact 5/10/20 cs, and the
--       ladder caps at 64 because 320 mod 128 ≠ 0 — a 128 rung has
--       no integer centisecond delay.
axiom_TL4 :: Bool
axiom_TL4 =
     map delayCs rungs == [5, 10, 20]
  && all (\s -> s * delayCs s == gifLoopCs && gifLoopCs `mod` s == 0) rungs
  && gifLoopCs `mod` 128 /= 0

-- (TL5) KEYSTONE — THE LADDER TELESCOPES: for 64 fine counts
--       grouped 8 → 8 → 1, the microstate chain rule factors
--       exactly: W(fine) == Π W(within mid blocks) × W(mid sums),
--       and W at the top is 1. The 16→32 and 32→64 transitions
--       consume disjoint bits; no bit is counted twice.
axiom_TL5 :: Bool
axiom_TL5 = all ok seeds
  where
    ok seed =
      let fine   = take 64 [ fromIntegral (floor (u * 4) :: Int)
                           | u <- uniforms (seed * 7919) ] :: [Integer]
          blocks = chunk 8 fine
          mids   = map sum blocks
      in microstates fine
           == product (map microstates blocks) * microstates mids
      && microstates [sum fine] == 1

-- (TL6) DENSITY: samples ×8 per rung; info-per-compute is
--       rung-invariant (7 values per block everywhere); both
--       transitions cost exactly 9/8 of the finest alone.
axiom_TL6 :: Bool
axiom_TL6 =
     and [ detailValuesPerTransition (2 * s) == 8 * detailValuesPerTransition s
         | s <- [16, 32, 64, 128] ]
  && and [ detailValuesPerTransition s == detailBands * blocksPerTransition s
         | s <- [16, 32, 64, 128, 256] ]
  && 8 * (detailValuesPerTransition 64 + detailValuesPerTransition 32)
       == 9 * detailValuesPerTransition 64

-- (TL7) CONCENTRATED IS FREE: a block's conditional factor is 1 —
--       zero bits — exactly when its mass sits on ≤1 child. The
--       meter that says which blocks carry information.
axiom_TL7 :: Bool
axiom_TL7 = all ok [ take 8 [ fromIntegral (floor (u * 4) :: Int)
                            | u <- uniforms s ] :: [Integer]
                   | s <- [11 .. 40] ]
         && ok [5, 0, 0, 0, 0, 0, 0, 0]
         && ok [0, 0, 0, 0, 0, 0, 0, 0]
  where ok cs = (microstates cs == 1)
                  == (length (filter (> 0) cs) <= 1)

-- ════════════════════════════════════════════════════════════════
-- § 6b. RUNG EQUIVALENCE AND THE RESOLUTION OF DEPTH (2026-08-10)
--
-- Daniel's theorem: 16³ == 32³ == 64³ IN THE INFORMATION PROCESS,
-- with COMPUTE TIME as the equivalence. Time and depth are related
-- through the ladder: depth's resolution is a RUNG, not a pixel
-- count.
-- ════════════════════════════════════════════════════════════════

-- | The base rung (RGB rides here, 20 fps) and depth's rung
-- (judgments ride here, 5 fps).
baseRung, depthRung :: Integer
baseRung  = 64
depthRung = 16

-- | One depth judgment aggregates (64/16)³ = 64 base samples —
-- exactly two rungs (8²) of the ×8 ladder.
samplesPerJudgment :: Integer
samplesPerJudgment = (baseRung `div` depthRung) ^ (3 :: Int)

-- (TL8) RUNG EQUIVALENCE — one process, three rates: on the poolL
--       orbit {c, pool c, pool² c} the invariants are (i) total
--       mass (TL3's conservation, checked on the orbit), (ii) loop
--       wall-clock 320 cs (TL4, all sides), (iii) information per
--       compute, 7 values per block (TL6, all sides). Only RATE
--       varies: samples per loop scale ×8 per rung. Equal compute
--       time is the equivalence class.
axiom_TL8 :: Bool
axiom_TL8 =
     all massConstant seeds
  && all (\s -> s * delayCs s == gifLoopCs) rungs
  && and [ (2 * s) ^ (3 :: Int) == 8 * s ^ (3 :: Int) | s <- rungs ]
  && and [ detailValuesPerTransition s == detailBands * blocksPerTransition s
         | s <- rungs ]
  where
    massConstant seed =
      let c0 = cubeOf seed 16
      in all (== total c0) [total (poolL c0), total (poolL (poolL c0))]

-- (TL9) THE RESOLUTION OF DEPTH: depth enters the process as the
--       per-pixel cadence-ensemble choice (σ vs 2σ); one reliable
--       readback of that choice needs the 64 draws a 16-rung voxel
--       aggregates. Depth's native rung is 16 —
--         · 64 samples per judgment, exactly two rungs down (8²)
--         · 16³ = 4096 judgments per 320 cs loop (the trit mask)
--         · judged at 5 Hz (the 20 cs slice) while RGB rides 20 Hz
--       Time and depth trade: ×4 space × ×4 time pooled per
--       decision. RGB : depth sample ratio == samplesPerJudgment.
axiom_TL9 :: Bool
axiom_TL9 =
     samplesPerJudgment == 64
  && samplesPerJudgment == 8 ^ (2 :: Int)
  && depthRung ^ (3 :: Int) == 4096
  && baseRung ^ (3 :: Int) == samplesPerJudgment * depthRung ^ (3 :: Int)
  && 100 `div` delayCs depthRung == 5
  && 100 `div` delayCs baseRung == 20

-- ════════════════════════════════════════════════════════════════
-- § 8. OFFSET LAWS (2026-08-11, Daniel: "several ways to get
-- 2×2×2 ↔ 1 — think of convolutions"; the scales are in time too)
--
-- A stride-2 2×2×2 sum pool is ONE POLYPHASE COMPONENT of the box
-- convolution: the offset group (ℤ/2)³ indexes 8 phases, and the
-- shipped ladder reads phase (0,0,0) only. On the loop's torus
-- (t wraps exactly — the 320 cs loop is periodic; spatial wrap is
-- the modeling choice made here) every phase is a partition, the 8
-- phases together are the full stride-1 sliding window, and the 8
-- windows covering any fine cell — one per phase — sum to the
-- trilinear tent [1,2,1]³: the anti-aliasing prefilter, realizable
-- one phase per tick at box cost (temporal dither of the reader).
--
-- CARRIER vs READS: only phase 0 serves the telescoping tower
-- (TL5's disjoint bits need nested partitions, and TL12 shows the
-- aligned tower reaches only even 4-offsets). The carrier stays
-- aligned — phases are a READ cadence. Phase-cycled TELEMETRY
-- (this ladder, the Dissonance tuning trace) needs no ruling;
-- offsetting DyadPreview's slow state moves GIF bytes and does.
-- ════════════════════════════════════════════════════════════════

type Offset = (Int, Int, Int)

-- | The corners of the 2×2×2 block == the phase group (ℤ/2)³.
offsets2 :: [Offset]
offsets2 = [ (f, r, c) | f <- [0, 1], r <- [0, 1], c <- [0, 1] ]

sideOf :: Cube -> Int
sideOf = length

-- | Torus lookup (t wraps by loop periodicity; space by choice).
at :: Cube -> Int -> Int -> Int -> Integer
at cu f r c = cu !! (f `mod` n) !! (r `mod` n) !! (c `mod` n)
  where n = sideOf cu

-- | Stride-2 sum pool at phase o: blocks {2v + o + {0,1}³} mod n.
poolAt :: Offset -> Cube -> Cube
poolAt (of_, or_, oc) cu =
  [ [ [ sum [ at cu (2 * f + of_ + df) (2 * r + or_ + dr)
                    (2 * c + oc + dc)
            | (df, dr, dc) <- offsets2 ]
      | c <- [0 .. h - 1] ] | r <- [0 .. h - 1] ] | f <- [0 .. h - 1] ]
  where h = sideOf cu `div` 2

-- | Stride-4 sum pool at a (mod 4) phase.
pool4At :: Offset -> Cube -> Cube
pool4At (of_, or_, oc) cu =
  [ [ [ sum [ at cu (4 * f + of_ + df) (4 * r + or_ + dr)
                    (4 * c + oc + dc)
            | df <- [0 .. 3], dr <- [0 .. 3], dc <- [0 .. 3] ]
      | c <- [0 .. h - 1] ] | r <- [0 .. h - 1] ] | f <- [0 .. h - 1] ]
  where h = sideOf cu `div` 4

-- | The stride-1 sliding-window sum: every anchor, every phase.
slide :: Cube -> Cube
slide cu =
  [ [ [ sum [ at cu (f + df) (r + dr) (c + dc)
            | (df, dr, dc) <- offsets2 ]
      | c <- [0 .. n - 1] ] | r <- [0 .. n - 1] ] | f <- [0 .. n - 1] ]
  where n = sideOf cu

-- | The trilinear tent [1,2,1]³ (total weight 64), directly.
tent :: Cube -> Cube
tent cu =
  [ [ [ sum [ w df * w dr * w dc * at cu (f + df) (r + dr) (c + dc)
            | df <- [-1, 0, 1], dr <- [-1, 0, 1], dc <- [-1, 0, 1] ]
      | c <- [0 .. n - 1] ] | r <- [0 .. n - 1] ] | f <- [0 .. n - 1] ]
  where n = sideOf cu
        w :: Int -> Integer
        w 0 = 2
        w _ = 1

-- (TL10) PHASES PARTITION THE TORUS: every one of the 8 offsets
--        conserves mass exactly, and phase (0,0,0) IS the aligned
--        carrier — the new machinery contains the old law.
axiom_TL10 :: Bool
axiom_TL10 = all ok seeds
  where ok seed = let cu = cubeOf seed 8
                  in all (\o -> total (poolAt o cu) == total cu) offsets2
                  && poolAt (0, 0, 0) cu == poolL cu

-- (TL11) THE TENT IS THE ORBIT: (a) every sliding anchor lives in
--        exactly one phase — S[p] == pool_{p mod 2} at p div 2;
--        (b) the 8 windows covering a cell sum to [1,2,1]³, so
--        cycling phases realizes the anti-aliasing tent at box
--        cost; (c) those 8 windows' anchors carry 8 DISTINCT
--        parities — one read per phase, none wasted.
axiom_TL11 :: Bool
axiom_TL11 = all ok seeds && paritiesDistinct
  where
    ok seed =
      let cu = cubeOf seed 8
          n  = sideOf cu
          s  = slide cu
          pools = [ (o, poolAt o cu) | o <- offsets2 ]
          phasePool o = maybe (error "phase") id (lookup o pools)
      in and [ s !! f !! r !! c ==
                 phasePool (f `mod` 2, r `mod` 2, c `mod` 2)
                   !! (f `div` 2) !! (r `div` 2) !! (c `div` 2)
             | f <- [0 .. n - 1], r <- [0 .. n - 1], c <- [0 .. n - 1] ]
      && tent cu ==
           [ [ [ sum [ at s (f - qf) (r - qr) (c - qc)
                     | (qf, qr, qc) <- offsets2 ]
               | c <- [0 .. n - 1] ] | r <- [0 .. n - 1] ]
             | f <- [0 .. n - 1] ]
    paritiesDistinct =
      length (nub [ ( (- qf) `mod` 2, (- qr) `mod` 2, (- qc) `mod` 2 )
                  | (qf, qr, qc) <- offsets2 ]) == 8

-- (TL12) PHASE REACHABILITY: staged offsets compose as o₁ + 2·o₂
--        (pool_{o₂} ∘ pool_{o₁} == pool4 at o₁ + 2o₂, all 64
--        pairs), so the aligned tower reaches ONLY the even
--        4-offsets — witness: an odd-phase 4-pool no even offset
--        reproduces. Odd phases need fresh fine reads:
--        phase-cycling is a READ cadence, never a tower rebuild.
axiom_TL12 :: Bool
axiom_TL12 = all ok seeds && witness
  where
    ok seed =
      let cu = cubeOf seed 8
      in and [ poolAt o2 (poolAt o1 cu)
                 == pool4At (add3 o1 (mul2 o2)) cu
             | o1 <- offsets2, o2 <- offsets2 ]
    witness =
      let cu   = cubeOf 3 8
          odd1 = pool4At (1, 0, 0) cu
      in all (\o2 -> pool4At (mul2 o2) cu /= odd1) offsets2
    add3 (a, b, c) (d, e, f) = (a + d, b + e, c + f)
    mul2 (a, b, c) = (2 * a, 2 * b, 2 * c)

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
  putStrLn " TriScaleLadder: 64³ → 32³ → 16³ (SixFour color-head port)"
  putStrLn " Sums are the carrier. The loop is 3.2 s at every rung."
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  rung │ cube     │ delay │ rate    │ side×delay"
  putStrLn "  ─────┼──────────┼───────┼─────────┼───────────"
  mapM_ (\s -> putStrLn $ "   " ++ show s ++ "  │ " ++ show s ++ "³      │ "
               ++ show (delayCs s) ++ " cs  │ "
               ++ show (100 `div` delayCs s) ++ " fps  │ "
               ++ show (s * delayCs s) ++ " cs")
        rungs
  putStrLn ""
  check "TL1 sums compose: pool₂ ∘ pool₂ == pool₄, exactly"          [axiom_TL1]
  check "TL2 rounded means do not compose (witness 1,0,0,0)"         [axiom_TL2]
  check "TL3 mass conserved down the ladder"                         [axiom_TL3]
  check "TL4 time law: side × delay = 320; ladder caps at 64"        [axiom_TL4]
  check "TL5 keystone: W(fine) telescopes; disjoint bits per rung"   [axiom_TL5]
  check "TL6 density: ×8 per rung; 7/block invariant; 9/8 overhead"  [axiom_TL6]
  check "TL7 concentrated block ⇔ W = 1 ⇔ zero bits (skip it)"       [axiom_TL7]
  check "TL8 rung equivalence: one process, three rates (orbit inv)" [axiom_TL8]
  check "TL9 depth resolves at rung 16: 64 draws/judgment, 5 Hz"     [axiom_TL9]
  check "TL10 phases partition the torus; phase 0 == the carrier"    [axiom_TL10]
  check "TL11 tent [1,2,1]³ == the 8-phase orbit (free anti-alias)"  [axiom_TL11]
  check "TL12 offsets compose o₁+2o₂; odd phases need fine reads"    [axiom_TL12]
  putStrLn ""
  putStrLn "  16³ == 32³ == 64³ in the information process; compute"
  putStrLn "  time is the equivalence. Depth's resolution is rung 16."
  putStrLn "  It trains nothing (★NO-CAPTURE-TRAINING)."
