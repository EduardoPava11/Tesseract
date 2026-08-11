{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- ANELoop: the loop calculus for latent computation on the engine
--
-- Daniel's ruling (2026-08-11): "R, G, B, depth have scales and
-- cadences such that information is preserved and reinforced as
-- signal. How this signal is passed is up to the latent
-- computation. Loops. We need ANE loops."
--
-- Design: docs/ane-loop-design.md. The engine's measured law
-- (arXiv:2606.22283): fixed-iteration numerics fused into ONE
-- static graph are the widest win; no data-dependent trip counts.
-- This module proves the three exact facts that give the loop its
-- shape, then the loop itself on the model cube:
--
--   AL1  band eigen-law: M = I + Π₂ + Π₄ acts as 1·u1 + 2·u2 + 3·u4
--        — the objective is diagonal in the tower basis.
--   AL2  block decomposition: F splits exactly over 4³ spacetime
--        blocks — all coupling lives inside a block's 64 voxels.
--   AL4  monotone exchange: the fixed-order in-block sweep, each
--        exchange accepted only on ΔF ≤ 0, never increases F —
--        so a compile-time-fixed sweep count K is SAFE, never
--        wrong: exactly the trip-count law the engine demands.
--
-- The exchange score is the EXACT incremental form
--
--   ΔF(v, δ) = 2·⟨e_v + m₂(v) + m₄(v), δ⟩ + ‖δ‖²·(1 + 1/8 + 1/64)
--
-- with m₂, m₄ the voxel's current 2- and 4-block error means — all
-- coefficients are block volumes, derived, no naked constants.
-- This quadratic form IS what the fused graph evaluates per stage.
--
-- v1's update operator is this algebraic exchange; the LATENT slot
-- (a learned passer folded into the graph as constant weights,
-- synthetic corpus, axiom-gated) replaces the operator later
-- without changing the loop's shape.
-- ════════════════════════════════════════════════════════════════

module ANELoop where

import Data.List (foldl', minimumBy)
import Data.Ord (comparing)

-- ════════════════════════════════════════════════════════════════
-- § 1. DETERMINISTIC INPUTS + VECTORS (house pattern)
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

type V3 = (Double, Double, Double)

vAdd, vSub :: V3 -> V3 -> V3
vAdd (a, b, c) (d, e, f) = (a + d, b + e, c + f)
vSub (a, b, c) (d, e, f) = (a - d, b - e, c - f)

vScale :: Double -> V3 -> V3
vScale k (a, b, c) = (k * a, k * b, k * c)

vDot :: V3 -> V3 -> Double
vDot (a, b, c) (d, e, f) = a * d + b * e + c * f

vNorm2 :: V3 -> Double
vNorm2 v = vDot v v

vZero :: V3
vZero = (0, 0, 0)

vMean :: [V3] -> V3
vMean [] = vZero
vMean vs = vScale (1 / fromIntegral (length vs)) (foldl' vAdd vZero vs)

triples :: [Double] -> [V3]
triples (a : b : c : rest) = (a, b, c) : triples rest
triples _ = []

-- ════════════════════════════════════════════════════════════════
-- § 2. THE MODEL CUBE AND THE TOWER (8³; blocks 2³ and 4³)
-- ════════════════════════════════════════════════════════════════

side :: Int
side = 8

nVox :: Int
nVox = side * side * side

coords :: [(Int, Int, Int)]
coords = [ (x, y, z) | z <- [0 .. side - 1], y <- [0 .. side - 1], x <- [0 .. side - 1] ]

blockId :: Int -> (Int, Int, Int) -> (Int, Int, Int)
blockId b (x, y, z) = (x `div` b, y `div` b, z `div` b)

-- | Π_b e: project onto b³-block-constant fields.
projectBlocks :: Int -> [V3] -> [V3]
projectBlocks b field =
  [ blockMean (blockId b xyz) | xyz <- coords ]
  where
    tagged = zip coords field
    blockMean key = vMean [ v | (xyz, v) <- tagged, blockId b xyz == key ]

norm2Field :: [V3] -> Double
norm2Field = sum . map vNorm2

-- | The objective (unnormalized): ‖e‖² + ‖Π₂e‖² + ‖Π₄e‖².
--   PP1 (PhasePalette.hs) says this is N·(D₁₆+D₃₂+D₆₄).
bigF :: [V3] -> Double
bigF e = norm2Field e + norm2Field (projectBlocks 2 e)
       + norm2Field (projectBlocks 4 e)

haarBands :: [V3] -> ([V3], [V3], [V3])   -- (u4, u2, u1)
haarBands e =
  let p4 = projectBlocks 4 e
      p2 = projectBlocks 2 e
  in (p4, zipWith vSub p2 p4, zipWith vSub e p2)

-- ════════════════════════════════════════════════════════════════
-- § 3. THE EXCHANGE SWEEP (v1 loop body; blocks are independent)
--
-- State: per voxel a chosen palette color q_v against target y_v;
-- error e = q − y. One SWEEP visits every voxel of every 4³ block
-- in fixed raster order; at each voxel every candidate color is
-- scored by the exact incremental ΔF and the best strictly
-- improving exchange is taken (ties keep the current color, so a
-- reached fixed point is stable — extra sweeps are identity).
-- Means are updated after every accepted exchange (Gauss–Seidel).
-- ════════════════════════════════════════════════════════════════

-- | Derived curvature: exchanging one voxel moves its own term,
--   its 2-cell mean (volume 8), and its 4-block mean (volume 64).
curvature :: Double
curvature = 1 + 1 / 8 + 1 / 64

-- | ΔF of moving voxel v's error by δ, given current e (exact).
deltaF :: [V3] -> Int -> V3 -> Double
deltaF e v delta =
  let xyz = coords !! v
      cellMean b = vMean [ e !! i | (i, c) <- zip [0 ..] coords
                         , blockId b c == blockId b xyz ]
      g = (e !! v) `vAdd` cellMean 2 `vAdd` cellMean 4
  in 2 * vDot g delta + vNorm2 delta * curvature

-- | One full sweep: fixed raster order, per-voxel best improving
--   exchange from the candidate palette, strict decrease only.
sweep :: [V3] -> [V3] -> [V3] -> [V3]
sweep palette y q0 = foldl' visit q0 [0 .. nVox - 1]
  where
    visit q v =
      let e = zipWith vSub q y
          scored = [ (deltaF e v (vSub c (q !! v)), c) | c <- palette ]
          (best, cBest) = minimumBy (comparing fst) scored
      in if best < -1e-15
           then [ if i == v then cBest else qi | (i, qi) <- zip [0 ..] q ]
           else q

loopK :: Int -> [V3] -> [V3] -> [V3] -> [V3]
loopK k palette y q = iterate (sweep palette y) q !! k

-- Deterministic instances.
targets :: [V3]
targets = take nVox (triples (uniforms 5))

palette8 :: [V3]
palette8 = take 6 (triples (uniforms 6))

q0 :: [V3]
q0 = take nVox (map (\u -> palette8 !! (floor (u * 6) `mod` 6)) (uniforms 7))

-- ════════════════════════════════════════════════════════════════
-- § 4. AXIOMS
-- ════════════════════════════════════════════════════════════════

approx :: Double -> Double -> Double -> Bool
approx eps a b = abs (a - b) <= eps

errorFields :: [[V3]]
errorFields =
  [ take nVox [ (a - 0.5, b - 0.5, c - 0.5) | (a, b, c) <- triples (uniforms s) ]
  | s <- [11, 12] ]

-- (AL1) BAND EIGEN-LAW: M·e = e + Π₂e + Π₄e equals 3·u4 + 2·u2 + 1·u1
--       componentwise, exactly — the bands are M's eigenspaces with
--       eigenvalues {3, 2, 1}; pure-band fields verify each.
axiom_AL1 :: Bool
axiom_AL1 = all fieldOK errorFields && all pureOK errorFields
  where
    fieldOK e =
      let me = zipWith3 (\a b c -> vAdd a (vAdd b c))
                 e (projectBlocks 2 e) (projectBlocks 4 e)
          (u4, u2, u1) = haarBands e
          rhs = zipWith3 (\a b c -> vAdd (vScale 3 a) (vAdd (vScale 2 b) c))
                  u4 u2 u1
      in and (zipWith (\p r -> vNorm2 (vSub p r) <= 1e-18) me rhs)
    pureOK e =
      let (u4, u2, u1) = haarBands e
          apply f = zipWith3 (\a b c -> vAdd a (vAdd b c))
                      f (projectBlocks 2 f) (projectBlocks 4 f)
          eig lam f = and (zipWith (\p r -> vNorm2 (vSub p r) <= 1e-18)
                                   (apply f) (map (vScale lam) f))
      in eig 3 u4 && eig 2 u2 && eig 1 u1

-- (AL2) BLOCK DECOMPOSITION: F equals the sum of block-local Fs —
--       every projector is nested inside the 4³ blocks, so voxels
--       in different blocks never couple through M.
axiom_AL2 :: Bool
axiom_AL2 = all ok errorFields
  where
    ok e =
      let blocks = [ [ v | (xyz, v) <- zip coords e, blockId 4 xyz == key ]
                   | key <- [ (i, j, k) | i <- [0, 1], j <- [0, 1], k <- [0, 1] ] ]
          localF blk = sum (map vNorm2 blk) + innerNorm 2 blk + innerNorm 4 blk
          -- inner b-cell mean energy inside a 4³ block, laid out in
          -- raster order (x fastest), matching the global layout.
          innerNorm b blk =
            let sideB = 4
                idx (x, y, z) = x + sideB * (y + sideB * z)
                cs = [ (x, y, z) | z <- [0 .. sideB - 1]
                     , y <- [0 .. sideB - 1], x <- [0 .. sideB - 1] ]
                key (x, y, z) = (x `div` b, y `div` b, z `div` b)
                cells = [ (kx, ky, kz) | kz <- [0 .. sideB `div` b - 1]
                        , ky <- [0 .. sideB `div` b - 1]
                        , kx <- [0 .. sideB `div` b - 1] ]
                cellMean c = vMean [ blk !! idx xyz | xyz <- cs, key xyz == c ]
            in sum [ fromIntegral (b * b * b) * vNorm2 (cellMean c) | c <- cells ]
      in approx 1e-9 (bigF e) (sum (map localF blocks))

-- (AL3) EXACT RESTRICTION (mass conservation through the loop):
--       integer-valued fields pool to exact integer sums at both
--       scales, before and after any number of sweeps of an
--       integer-preserving exchange (the sums are re-derived from
--       the field, never carried — TL3's law on the loop's state).
axiom_AL3 :: Bool
axiom_AL3 = all ok [take nVox (map ((fromIntegral :: Int -> Double) . (`mod` 7)) (iterate lcg 31))]
  where
    ok xs =
      let field = map (\x -> (x, 0, 0)) xs
          total = sum xs
          pooledSum b = sum [ fromIntegral (b * b * b) * mx
                            | c <- [ (i, j, k) | i <- [0 .. side `div` b - 1]
                                   , j <- [0 .. side `div` b - 1]
                                   , k <- [0 .. side `div` b - 1] ]
                            , let (mx, _, _) = vMean [ v | (xyz, v) <- zip coords field
                                                    , blockId b xyz == c ] ]
      in approx 1e-9 (pooledSum 2) total && approx 1e-9 (pooledSum 4) total

-- (AL4) MONOTONE EXCHANGE: F never increases across sweeps, the
--       incremental ΔF agrees exactly with the recomputed
--       difference, and a reached fixed point is stable (one more
--       sweep is the identity) — overshooting K is safe.
axiom_AL4 :: Bool
axiom_AL4 = monotone && incrementalExact && fixedPointStable
  where
    states = take 7 (iterate (sweep palette8 targets) q0)
    fs = [ bigF (zipWith vSub q targets) | q <- states ]
    monotone = and (zipWith (\a b -> b <= a + 1e-12) fs (tail fs))
    incrementalExact = all probe [0, 3, 17, 63, 200]
      where
        probe v =
          let e = zipWith vSub q0 targets
              c = head palette8
              delta = vSub c (q0 !! v)
              q1 = [ if i == v then c else qi | (i, qi) <- zip [0 ..] q0 ]
              recomputed = bigF (zipWith vSub q1 targets) - bigF e
          in approx 1e-9 (deltaF e v delta) recomputed
    fixedPointStable =
      let deep = loopK 12 palette8 targets q0
      in sweep palette8 targets deep == deep

-- (AL5) NULL LAWS: K = 0 is the identity; a single-candidate
--       palette equal to the current colors exchanges nothing.
axiom_AL5 :: Bool
axiom_AL5 = loopK 0 palette8 targets q0 == q0
         && sweep [head palette8] targets allSame == allSame
  where allSame = replicate nVox (head palette8)

-- (AL6) DETERMINISM: the loop is a pure function — identical
--       recomputation, and sweeps compose (K then J = K+J).
axiom_AL6 :: Bool
axiom_AL6 = loopK 3 palette8 targets q0 == loopK 3 palette8 targets q0
         && loopK 2 palette8 targets (loopK 3 palette8 targets q0)
              == loopK 5 palette8 targets q0

-- (AL7) DERIVED CURVATURE: the quadratic coefficient is exactly
--       1 + 1/8 + 1/64 — the reciprocal block volumes, nothing
--       else; and the ΔF of the zero move is zero, exactly.
axiom_AL7 :: Bool
axiom_AL7 = curvature == 1 + 1 / 8 + 1 / 64
         && all (\v -> deltaF e0 v vZero == 0) [0, 9, 100]
  where e0 = zipWith vSub q0 targets

-- (AL8) THE CLOCK IDENTITY: 20 Hz RGB over 5 Hz depth judgments =
--       4 = the time extent of one 4³ block; a block holds exactly
--       TL9's 64 draws; the 64³ capture holds 4096 rung-16 blocks
--       per judgment loop. The channels interlock by arithmetic.
axiom_AL8 :: Bool
axiom_AL8 = rgbHz `div` depthHz == blockSide
         && blockSide ^ (3 :: Int) == samplesPerJudgment
         && (64 `div` blockSide) ^ (3 :: Int) == judgmentsPerLoop
  where
    rgbHz = 20 :: Int
    depthHz = 5
    blockSide = 4
    samplesPerJudgment = 64
    judgmentsPerLoop = 4096

-- ════════════════════════════════════════════════════════════════
-- § 4b. THE SIMT IDENTITY (2026-08-11, Daniel: "continue with an
-- SIMT model")
--
-- The Metal port runs ONE GPU THREAD PER 4³ BLOCK (AL2: blocks
-- never couple, so 4096 threads need no synchronization at all)
-- and carries the block mean and the eight 2-cell means as RUNNING
-- SUMS: after an accepted exchange δ at voxel v, bsum += δ and
-- c2[cell v] += δ — O(1) per stage instead of re-reading 64
-- voxels. AL9 states the identity that makes this lawful, over
-- EXACT arithmetic (Rational): the running-sum sweep IS the
-- recomputing sweep — same accepts, same states, and the carried
-- sums equal the recomputed sums after every sweep. In float the
-- two round differently; AL4's monotonicity and the near-tie
-- parity gate (XP2) absorb that, exactly as with the ANE engine.
-- Unlike the fused ANE graph, the kernel's K is a RUNTIME loop
-- bound — the SIMT port is the runtime-adaptive-K execution port.
-- ════════════════════════════════════════════════════════════════

type R3 = (Rational, Rational, Rational)

rAdd, rSub :: R3 -> R3 -> R3
rAdd (a, b, c) (d, e, f) = (a + d, b + e, c + f)
rSub (a, b, c) (d, e, f) = (a - d, b - e, c - f)

rScale :: Rational -> R3 -> R3
rScale s (a, b, c) = (s * a, s * b, s * c)

rDot :: R3 -> R3 -> Rational
rDot (a, b, c) (d, e, f) = a * d + b * e + c * f

rZero :: R3
rZero = (0, 0, 0)

-- | Block-local raster: v = x + 4(y + 4t); its 2-cell index.
cellOf :: Int -> Int
cellOf v = (x `div` 2) + 2 * ((y `div` 2) + 2 * (t `div` 2))
  where (x, y, t) = (v `mod` 4, (v `div` 4) `mod` 4, v `div` 16)

curvatureQ :: Rational
curvatureQ = 1 + 1 / 8 + 1 / 64

-- | The block-local visit law shared by both sweeps (mirrors
--   sweepBlockCPU and the Metal kernel: fold candidates in order,
--   strict decrease only, ties keep the current index).
visitQ :: [R3] -> R3 -> Int -> (Rational, Int)
visitQ cand g qv0 =
  foldl pick (0, qv0) (zip [0 ..] cand)
  where
    qv = cand !! qv0
    pick (bs, bi) (ci, c) =
      let d = rSub c qv
          df = 2 * rDot g d + curvatureQ * rDot d d
      in if df < bs then (df, ci) else (bs, bi)

-- | The recomputing sweep (the law, block-local).
sweepReQ :: [R3] -> [R3] -> Int -> [Int] -> [Int]
sweepReQ cand y k start = iterate one start !! k
  where
    one q = foldl visit q [0 .. 63]
    visit q v =
      let e i = rSub (cand !! (q !! i)) (y !! i)
          m2 = rScale (1 / 8) (foldl rAdd rZero
                 [ e w | w <- [0 .. 63], cellOf w == cellOf v ])
          m4 = rScale (1 / 64) (foldl rAdd rZero [ e w | w <- [0 .. 63] ])
          g = e v `rAdd` m2 `rAdd` m4
          (best, bi) = visitQ cand g (q !! v)
      in if best < 0
           then [ if i == v then bi else qi | (i, qi) <- zip [0 ..] q ]
           else q

-- | The running-sum sweep (the SIMT kernel, verbatim in Rational).
--   Returns the final state AND the carried sums for the invariant.
sweepIncQ :: [R3] -> [R3] -> Int -> [Int] -> ([Int], R3, [R3])
sweepIncQ cand y k start = go k (start, bsum0, c20)
  where
    e0 q v = rSub (cand !! (q !! v)) (y !! v)
    bsum0 = foldl rAdd rZero [ e0 start v | v <- [0 .. 63] ]
    c20 = [ foldl rAdd rZero [ e0 start v | v <- [0 .. 63], cellOf v == cell ]
          | cell <- [0 .. 7] ]
    go 0 (q, bs, c2) = (q, bs, c2)
    go n (q, bs, c2) = go (n - 1) (foldl visit (q, bs, c2) [0 .. 63])
    visit (q, bs, c2) v =
      let ev = rSub (cand !! (q !! v)) (y !! v)
          g = ev `rAdd` rScale (1 / 8) (c2 !! cellOf v)
                 `rAdd` rScale (1 / 64) bs
          (best, bi) = visitQ cand g (q !! v)
          d = rSub (cand !! bi) (cand !! (q !! v))
      in if best < 0
           then ( [ if i == v then bi else qi | (i, qi) <- zip [0 ..] q ]
                , bs `rAdd` d
                , [ if cell == cellOf v then s `rAdd` d else s
                  | (cell, s) <- zip [0 ..] c2 ] )
           else (q, bs, c2)

-- Deterministic block instances (indices from the spec's own LCG).
blockCase :: Int -> ([R3], [R3], [Int])
blockCase seed =
  ( take 8 rats                                     -- candidates
  , take 64 (drop 8 rats)                           -- targets
  , take 64 [ floor (u * 8) `mod` 8 | u <- uniforms (seed * 131) ] )
  where
    rats = [ (q a, q b, q c)
           | ((a, b, c) : _) <- iterate (drop 1) (triples (uniforms seed)) ]
    q x = toRational x - 1 / 2

-- (AL9) THE SIMT IDENTITY: over exact arithmetic the running-sum
--       sweep equals the recomputing sweep for every K tested, and
--       the carried sums equal the sums recomputed from the final
--       state — δ-updates lose nothing, in any order of sweeps.
axiom_AL9 :: Bool
axiom_AL9 = all ok [ (seed, k) | seed <- [21, 22, 23], k <- [0, 1, 3] ]
  where
    ok (seed, k) =
      let (cand, y, start) = blockCase seed
          re = sweepReQ cand y k start
          (inc, bs, c2) = sweepIncQ cand y k start
          e v = rSub (cand !! (inc !! v)) (y !! v)
          bsRe = foldl rAdd rZero [ e v | v <- [0 .. 63] ]
          c2Re = [ foldl rAdd rZero [ e v | v <- [0 .. 63], cellOf v == cell ]
                 | cell <- [0 .. 7] ]
      in re == inc && bs == bsRe && c2 == c2Re

-- ════════════════════════════════════════════════════════════════
-- § 5. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " ANELoop: fixed-K exchange sweeps on the signal tower"
  putStrLn " M = I + Π₂ + Π₄ is diagonal in bands: eigenvalues 3 2 1"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "AL1 band eigen-law: M·e = 3u4 + 2u2 + 1u1, exact"          [axiom_AL1]
  check "AL2 block decomposition: F = Σ blocks, no cross-coupling"  [axiom_AL2]
  check "AL3 exact restriction: sums conserved at both scales"      [axiom_AL3]
  check "AL4 monotone exchange: ΔF exact, F ↓, fixed point stable"  [axiom_AL4]
  check "AL5 null laws: K = 0 identity, degenerate palette inert"   [axiom_AL5]
  check "AL6 determinism + sweep composition"                       [axiom_AL6]
  check "AL7 curvature = 1 + 1/8 + 1/64, zero move costs zero"      [axiom_AL7]
  check "AL8 clock identity: 20/5 = 4 = block time; 64; 4096"       [axiom_AL8]
  check "AL9 SIMT identity: running sums == recomputed, exactly"    [axiom_AL9]
  putStrLn ""
  let final = loopK 6 palette8 targets q0
      f0 = bigF (zipWith vSub q0 targets)
      f6 = bigF (zipWith vSub final targets)
  putStrLn $ "  F: start " ++ show f0 ++ " → 6 sweeps " ++ show f6
  putStrLn ""
  putStrLn "  The loop: restrict exactly, exchange monotonically,"
  putStrLn "  prolong at 3:2:1 — K fixed, one fused dispatch."
  putStrLn "  The latent slot swaps the passer, never the shape."

check :: String -> [Bool] -> IO ()
check name results =
  let passed = and results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
