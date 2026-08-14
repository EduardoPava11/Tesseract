-- ════════════════════════════════════════════════════════════════
-- AdditiveLadder: every rung writes bits of every index
--
-- Daniel's ruling (2026-08-14): "all rungs require a meaningful
-- additive to the creation of GIFs." No rung may hold a
-- measurement-only job. The three views are not three resolutions of
-- one decision — they are THREE STRATA OF ONE INDEX, and the index
-- is their sum.
--
-- The law is not new machinery. It is two shipped laws read together
-- and pinned to the rung ladder:
--
--   PT5  (quantization/PairTree.hs) truncating ℓ bits of the
--        nearest-leaf index EQUALS the nearest level-ℓ centroid.
--        A prefix IS a coarse palette; the rest IS a refinement.
--   DL1  (neural/DescentLadder.hs) the descent has fixed serial
--        depth 3, fan-outs [2,8,8] — one bit, then two bit-triples.
--        The triples are the 2×2×2 atom.
--
-- THE STRATA (Daniel's σ ruling, same day: depth owns ALLOCATION,
-- the rungs own COLOUR — so the role bit sits above all three and is
-- written by neither):
--
--   bit 7    ROLE     figure/σ      — depth, via the Bayer coverage
--   bit 6    rung 16³ 4-level       — 4096 voxels write 1 bit
--   bits 5-3 rung 32³ 32-level      — 32768 voxels write 3 bits
--   bits 2-0 rung 64³ 256-level     — 262144 voxels write 3 bits
--
-- ★ THE INVARIANT (AD4). Voxels multiply by 8 per rung and classes
-- multiply by 8 per rung, so balanced occupancy is THE SAME NUMBER
-- at every rung: 1024 voxels per class. That is what 16³ ≡ 32³ ≡ 64³
-- means for colour — one constant, not a ladder with zero slack at
-- its coarsest end.
--
-- ★ THE ROLE BIT IS DERIVED, NOT WRITTEN (AD7). σ is a threshold of
-- the deterministic Bayer matrix against the rung-16 coverage field,
-- so a 4×4 tile has exactly 17 reachable σ patterns, not 2^16. Its
-- rate is RateLadder's 17-level coverage code — 2.04 KiB per cube,
-- not the 32 KiB a free bit plane would cost. The band mechanism
-- pays for itself.
--
-- Nothing here changes a byte. This is the law a port must satisfy.
-- ════════════════════════════════════════════════════════════════

module AdditiveLadder where

import Data.Bits (shiftL, shiftR, (.&.))
import Data.List (nub, sort)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE STRATA
-- ════════════════════════════════════════════════════════════════

-- | A stratum: which bits it owns, which rung writes it, and the
--   cumulative palette level it completes.
data Stratum = Stratum
  { stName   :: String
  , stLow    :: Int      -- lowest bit index owned
  , stWidth  :: Int      -- number of bits owned
  , stRung   :: Int      -- the cube side that writes it (0 = depth)
  , stLevel  :: Int      -- palette classes distinguishable once written
  } deriving (Eq, Show)

role, s16, s32, s64 :: Stratum
role = Stratum "role"    7 1  0   2      -- figure / σ, written by depth
s16  = Stratum "rung16"  6 1 16   4
s32  = Stratum "rung32"  3 3 32  32
s64  = Stratum "rung64"  0 3 64 256

strata :: [Stratum]
strata = [role, s16, s32, s64]

-- | The rung strata only — the three views Daniel's ruling is about.
rungStrata :: [Stratum]
rungStrata = [s16, s32, s64]

indexBits :: Int
indexBits = 8

-- | Voxels in the cube at a rung (the side cubed — space × time).
voxels :: Int -> Int
voxels r = r * r * r

-- | The field each stratum contributes, read off an index.
field :: Stratum -> Int -> Int
field st i = (i `shiftR` stLow st) .&. ((1 `shiftL` stWidth st) - 1)

-- | Recompose an index from its four contributions.
compose :: Int -> Int -> Int -> Int -> Int
compose r a b c =
  (r `shiftL` stLow role) + (a `shiftL` stLow s16)
    + (b `shiftL` stLow s32) + (c `shiftL` stLow s64)

decompose :: Int -> (Int, Int, Int, Int)
decompose i = (field role i, field s16 i, field s32 i, field s64 i)

allIndices :: [Int]
allIndices = [0 .. 255]

-- | Truncate an index to the palette level a stratum completes:
--   the prefix law's operator (PT5's classAbove, on the 8-bit index).
classAt :: Stratum -> Int -> Int
classAt st i = i `shiftR` stLow st

-- ════════════════════════════════════════════════════════════════
-- § 2. THE BIT BUDGET
-- ════════════════════════════════════════════════════════════════

-- | RateLadder RL6: the coverage code has exactly 17 representable
--   values (0..16 σ cells of the Bayer tile), so the role field's
--   rate is log₂17 per rung-16 voxel — NOT one bit per fine voxel.
coverageLevels :: Int
coverageLevels = 17

coverageRate :: Double
coverageRate = logBase 2 (fromIntegral coverageLevels)

-- | Bits a stratum spends over the whole cube.
stratumBits :: Stratum -> Double
stratumBits st
  | stRung st == 0 = fromIntegral (voxels 16) * coverageRate  -- AD7
  | otherwise = fromIntegral (voxels (stRung st) * stWidth st)

totalBits :: Double
totalBits = sum (map stratumBits strata)

-- | What the cube would cost if every fine voxel chose freely.
flatBits :: Double
flatBits = fromIntegral (voxels 64 * indexBits)

structuralRatio :: Double
structuralRatio = flatBits / totalBits

-- ════════════════════════════════════════════════════════════════
-- § 3. THE ROLE PLANE (derived, not written)
-- ════════════════════════════════════════════════════════════════

bayerOrder :: [Int]
bayerOrder = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

-- | The σ pattern of one 4×4 tile at coverage k: cell j is σ iff its
--   Bayer order is below k. Deterministic in (k, position).
tilePattern :: Int -> [Bool]
tilePattern k = [ o < k | o <- bayerOrder ]

-- | Every reachable tile pattern.
tilePatterns :: [[Bool]]
tilePatterns = map tilePattern [0 .. 16]

-- | The σ plane of a frame, reconstructed from a coverage field
--   alone — one coverage value per 4×4 tile (the rung-16 field).
rolePlane :: Int -> [Int] -> [Bool]
rolePlane side coverage =
  [ tilePattern (coverage !! (ty * tiles + tx)) !! ((y `mod` 4) * 4 + (x `mod` 4))
  | y <- [0 .. side - 1], x <- [0 .. side - 1]
  , let ty = y `div` 4, let tx = x `div` 4 ]
  where tiles = side `div` 4

-- ════════════════════════════════════════════════════════════════
-- § 4. ENERGY ALIGNMENT (TilingEntropy's chain rule, verbatim)
-- ════════════════════════════════════════════════════════════════

hBin :: Int -> Int -> Double
hBin a b
  | a == 0 || b == 0 = 0
  | otherwise = negate (p * logBase 2 p + q * logBase 2 q)
  where
    n = fromIntegral (a + b); p = fromIntegral a / n; q = fromIntegral b / n

-- | The eight dyadic rungs of E, root (bit 7 = role) first.
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

energy :: [Int] -> Double
energy hist = sum [ fromIntegral c * logBase 2 (fromIntegral c / nb)
                  | c <- hist, c > 0 ]
  where nb = fromIntegral (sum hist) / 256

-- | Group the eight dyadic levels by stratum: 1 + 1 + 3 + 3.
stratumEnergies :: [Int] -> [Double]
stratumEnergies hist = go (levelEnergies hist) (map stWidth strata)
  where
    go _ [] = []
    go ls (w : ws) = let (a, b) = splitAt w ls in sum a : go b ws

-- ════════════════════════════════════════════════════════════════
-- § 5. PROBE HISTOGRAMS (deterministic — house lcg)
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

-- | Balanced at the cube: 1024 of each of the 256.
balancedHist :: [Int]
balancedHist = replicate 256 1024

-- | A role-split histogram: mass m_g on the σ half, spread unevenly.
splitHist :: Double -> Int -> [Int]
splitHist mg seed =
  [ scale i (1 + floor (u * 40)) | (i, u) <- zip [0 :: Int ..] us ]
  where
    us = take 256 (uniforms seed)
    scale i v = if i >= 128 then round (fromIntegral v * mg * 2)
                            else round (fromIntegral v * (1 - mg) * 2)

probeHists :: [[Int]]
probeHists =
  [ balancedHist
  , splitHist 0.75 7
  , splitHist 0.5 11
  , replicate 128 2048 ++ replicate 128 0     -- figure only
  , replicate 255 0 ++ [262144]               -- solid σ
  ]

-- ════════════════════════════════════════════════════════════════
-- § 5b. THE CENSUS (what a shipped cube can be measured against)
-- ════════════════════════════════════════════════════════════════
-- The law says a stratum's bits are decided at its own rung, so they
-- are CONSTANT across that rung's block. A cube assigned freely at
-- the fine rung generally violates that. Conformance measures the
-- gap, on the emitted cube alone — no pipeline change, no device.
--
--   conformance st cube = (blocks where st's field is constant)
--                         / (blocks at st's rung)
--
-- 1.0 means the cube already obeys the additive law at that stratum.
-- This is the number S8's port is judged by, before and after.

-- | Block side at a stratum's rung, on a fine cube of side 64:
--   rung 16 blocks are 4×4×4, rung 32 are 2×2×2, rung 64 are 1×1×1.
--   The role stratum is not written at a rung at all (AD7 — it is a
--   Bayer expansion of the coverage field, varying per fine voxel),
--   so its block is a single voxel and its conformance is trivially
--   1: the law that constrains it is AD7's 17 patterns, not this.
blockSide :: Stratum -> Int
blockSide st
  | stRung st == 0 = 1
  | otherwise = 64 `div` stRung st

-- | A cube is [frame][cell] with cells in row-major order.
type Cube = [[Int]]

-- | Every block of a stratum's rung, as its list of member indices.
blocksOf :: Stratum -> Cube -> [[Int]]
blocksOf st cube =
  [ [ (cube !! (bt * k + dt)) !! ((by * k + dy) * side + (bx * k + dx))
    | dt <- [0 .. k - 1], dy <- [0 .. k - 1], dx <- [0 .. k - 1] ]
  | bt <- [0 .. nT - 1], by <- [0 .. n - 1], bx <- [0 .. n - 1] ]
  where
    k = blockSide st
    side = 64
    n = side `div` k
    nT = length cube `div` k        -- the cube's own depth, not 64

conformance :: Stratum -> Cube -> Double
conformance st cube
  | null bs = 1
  | otherwise = fromIntegral (length (filter constant bs)) / fromIntegral (length bs)
  where
    bs = blocksOf st cube
    constant b = length (nub (map (field st) b)) <= 1

-- | Classes actually used at a stratum's cumulative level.
classesUsed :: Stratum -> Cube -> Int
classesUsed st cube = length (nub [ classAt st i | f <- cube, i <- f ])

-- | A cube built BY the additive law: each stratum's field is drawn
--   once per block of its own rung. Deterministic (house lcg).
lawfulCube :: Int -> Cube
lawfulCube seed =
  [ [ compose (pick role t y x) (pick s16 t y x) (pick s32 t y x) (pick s64 t y x)
    | y <- [0 .. side - 1], x <- [0 .. side - 1] ]
  | t <- [0 .. frames - 1] ]
  where
    side = 64
    frames = 4                 -- one 4-frame group: the rung-16 block depth
    us = uniforms seed
    pick st t y x =
      let k = blockSide st
          n = side `div` k
          b = ((t `div` k) * n + (y `div` k)) * n + (x `div` k)
          w = stWidth st
      in floor (us !! ((stLow st * 9973 + b) `mod` 4096) * fromIntegral (2 ^ w :: Int))
           `mod` (2 ^ w)

-- | A cube assigned freely at the fine rung — today's shape.
freeCube :: Int -> Cube
freeCube seed =
  [ [ floor (us !! (((t * side + y) * side + x) `mod` 4096) * 256) `mod` 256
    | y <- [0 .. side - 1], x <- [0 .. side - 1] ]
  | t <- [0 .. frames - 1] ]
  where
    side = 64
    frames = 4
    us = uniforms seed

-- ════════════════════════════════════════════════════════════════
-- § 6. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (AD1) THE PARTITION. The four strata own disjoint bit ranges that
--       exhaust the 8-bit index, in descending order, with widths
--       1 + 1 + 3 + 3. Every rung of the ladder appears exactly once.
axiom_AD1 :: Bool
axiom_AD1 =
     sum (map stWidth strata) == indexBits
  && map stWidth strata == [1, 1, 3, 3]
  && map stLow strata == [7, 6, 3, 0]
  && and [ stLow a == stLow b + stWidth b | (a, b) <- zip strata (tail strata) ]
  && sort (map stRung rungStrata) == [16, 32, 64]
  && length (nub (concatMap ownedBits strata)) == indexBits
  where ownedBits st = [ stLow st .. stLow st + stWidth st - 1 ]

-- (AD2) THE COMPOSITION IDENTITY — the reason the law is called
--       ADDITIVE. Every index is the sum of its four strata's
--       contributions, and decompose/compose is a bijection on the
--       whole 256. No index exists that some rung did not help write.
axiom_AD2 :: Bool
axiom_AD2 =
     all (\i -> let (r, a, b, c) = decompose i in compose r a b c == i) allIndices
  && length (nub [ decompose i | i <- allIndices ]) == 256
  && all inRange allIndices
  where
    inRange i =
      let (r, a, b, c) = decompose i
      in r < 2 && a < 2 && b < 8 && c < 8

-- (AD3) THE RUNG ASSIGNMENT IS FORCED, NOT CHOSEN. Each step of the
--       ladder multiplies voxels by 8 (the 2×2×2 atom) and classes
--       by 8 (a bit-triple), so there is exactly one way to seat the
--       strata on the rungs. Rung 16 carries the odd bit because the
--       role bit was lifted out of its pair (Daniel's σ ruling).
axiom_AD3 :: Bool
axiom_AD3 =
     map (voxels . stRung) rungStrata == [4096, 32768, 262144]
  && and [ voxels (stRung b) == 8 * voxels (stRung a)
         | (a, b) <- zip rungStrata (tail rungStrata) ]
  && and [ stLevel b == 8 * stLevel a
         | (a, b) <- zip rungStrata (tail rungStrata) ]
  && stLevel s64 == 256
  && stLevel role * 2 == stLevel s16

-- (AD4) ★ THE 1024 INVARIANT. Balanced occupancy is the SAME number
--       at every rung — voxels ÷ classes = 1024 throughout. This is
--       what 16³ ≡ 32³ ≡ 64³ means for colour, and it is why the
--       coarsest rung no longer has zero slack: the ladder is stated
--       on the cube, not on a single frame.
axiom_AD4 :: Bool
axiom_AD4 =
     all (\st -> voxels (stRung st) `div` stLevel st == 1024) rungStrata
  && all (\st -> voxels (stRung st) `mod` stLevel st == 0) rungStrata
  -- and the per-FRAME ladder is the same statement divided by the
  -- rung's own frame count: 4096/256, 1024/256, 256/256.
  && [ (r * r) `div` 256 | r <- [64, 32, 16] ] == [16, 4, 1]

-- (AD5) PREFIX CONSISTENCY (PT5 on the 8-bit index). Truncating at a
--       stratum boundary yields exactly the class the coarser strata
--       already wrote — so a coarse rung's decision is never revised
--       by a finer one, only refined. PT5 owns the geometric half
--       (truncate ≡ nearest coarse centroid); this is the algebraic
--       half it is composed with.
axiom_AD5 :: Bool
axiom_AD5 =
     all (\i -> classAt s16 i == compose (field role i) (field s16 i) 0 0 `shiftR` 6)
         allIndices
  && all (\i -> classAt s64 i == i) allIndices
  && all (\i -> classAt s32 i == i `div` 8) allIndices
  && all (\i -> classAt role i == (if i >= 128 then 1 else 0)) allIndices
  -- refinement never revises: same prefix ⇒ same coarse class
  && and [ classAt s32 i == classAt s32 j
         | i <- allIndices, j <- allIndices, i `div` 8 == j `div` 8 ]
  && length (nub (map (classAt s16) allIndices)) == stLevel s16
  && length (nub (map (classAt s32) allIndices)) == stLevel s32

-- (AD6) DESCENT CORRESPONDENCE (DL1/DL2). The figure half's 128
--       leaves factor as 2×8×8 — exactly the strata's widths below
--       the role bit — so the additive strata ARE the descent's
--       three stages, and an early exit at stage k is the class
--       above (DL2's output nesting, read on the index).
axiom_AD6 :: Bool
axiom_AD6 =
     product fanouts == 128
  && fanouts == [2, 8, 8]
  && map (\w -> 2 ^ w) (map stWidth rungStrata) == fanouts
  && length fanouts == 3          -- DL1's fixed serial depth
  && all (\i -> exitAt 1 i == classAt s16 i) allIndices
  && all (\i -> exitAt 2 i == classAt s32 i) allIndices
  && all (\i -> exitAt 3 i == classAt s64 i) allIndices
  where
    fanouts = [ 2 ^ stWidth st | st <- rungStrata ]
    -- the descent's class after k stages = the index truncated to
    -- the strata written so far
    exitAt k i = i `shiftR` stLow (rungStrata !! (k - 1))

-- (AD7) ★ THE ROLE BIT IS DERIVED, NOT WRITTEN. σ is a threshold of
--       the fixed Bayer matrix against the rung-16 coverage field,
--       so a 4×4 tile has exactly 17 reachable patterns (RL6's
--       coverage code), the patterns are NESTED (monotone in k), and
--       the whole fine σ plane is reconstructible from the coarse
--       field alone. Its rate is 4096·log₂17 bits per cube, not one
--       bit per fine voxel — the band mechanism pays for itself.
axiom_AD7 :: Bool
axiom_AD7 =
     length (nub tilePatterns) == coverageLevels
  && coverageLevels == 17
  && map (length . filter id) tilePatterns == [0 .. 16]
  && and [ and (zipWith (\a b -> not a || b)
                        (tilePattern k) (tilePattern (k + 1)))
         | k <- [0 .. 15] ]                       -- nested
  && rolePlane 16 cov == rolePlane 16 cov         -- deterministic
  && length (rolePlane 16 cov) == 256
  -- the free-bit-plane alternative would cost 2^16 patterns/tile:
  && (2 :: Integer) ^ (16 :: Int) > fromIntegral coverageLevels
  && abs (stratumBits role - 4096 * coverageRate) < 1e-9
  && stratumBits role < fromIntegral (voxels 64)  -- cheaper than 1 b/voxel
  where cov = [ (7 * t + 3) `mod` 17 | t <- [0 .. 15] ]

-- (AD8) THE BUDGET. The four strata spend 905574.2 bits per cube
--       against 2097152 if every fine voxel chose freely — a
--       2.316:1 structural ratio, paid by the ladder's shape and not
--       by any coder. Every rung's share is strictly positive and
--       increases with the rung.
axiom_AD8 :: Bool
axiom_AD8 =
     abs (totalBits - 905574.2478) < 1e-3
  && abs (flatBits - 2097152) < 1e-9
  && abs (structuralRatio - 2.3158256) < 1e-6
  -- the budget is the sum of its parts, not a fitted number
  && abs (totalBits - (4096 * coverageRate + 4096 + 98304 + 786432)) < 1e-9
  && all (> 0) (map stratumBits strata)
  && and [ stratumBits b > stratumBits a
         | (a, b) <- zip rungStrata (tail rungStrata) ]
  && abs (stratumBits s64 - 786432) < 1e-9
  && abs (stratumBits s32 - 98304) < 1e-9
  && abs (stratumBits s16 - 4096) < 1e-9

-- (AD9) ENERGY ALIGNMENT. TilingEntropy's dyadic chain rule splits E
--       on exactly these boundaries, so each rung's BIT share has
--       its own ENERGY term and the terms sum to E. Per-rung colour
--       budget and per-rung energy budget are one object, not two.
axiom_AD9 :: Bool
axiom_AD9 =
     all (\h -> length (stratumEnergies h) == 4) probeHists
  && all (\h -> abs (sum (stratumEnergies h) - energy h) < 1e-6) probeHists
  && all (\h -> all (>= -1e-9) (stratumEnergies h)) probeHists
  && abs (sum (stratumEnergies balancedHist)) < 1e-9   -- ground state
  -- the role term is the φ order parameter's energy (TE5)
  && all roleTermIsPhi probeHists
  where
    roleTermIsPhi h =
      let n = sum h
          e = fromIntegral n * (1 - hBin (sum (take 128 h)) (sum (drop 128 h)))
      in abs (head (stratumEnergies h) - e) < 1e-9

-- (AD10) ★ NO RUNG IS SILENT — Daniel's ruling, made checkable.
--        Every rung writes at least one bit of every index, and for
--        each rung there exist indices differing ONLY in that rung's
--        bits. Deleting any rung's stratum changes what the GIF
--        emits, so no rung can be demoted to telemetry without
--        changing the artifact.
axiom_AD10 :: Bool
axiom_AD10 =
     all (\st -> stWidth st >= 1) strata
  && all distinguishes rungStrata
  && all (\st -> length (nub (map (field st) allIndices)) == 2 ^ stWidth st)
         rungStrata
  where
    distinguishes st =
      let m = (2 ^ stWidth st - 1) `shiftL` stLow st
          pairs = [ (i, i + (1 `shiftL` stLow st))
                  | i <- allIndices
                  , i + (1 `shiftL` stLow st) <= 255
                  , field st i + 1 == field st (i + (1 `shiftL` stLow st)) ]
      in not (null pairs)
         && all (\(i, j) -> i /= j && (i .&. complement8 m) == (j .&. complement8 m))
                pairs
    complement8 m = 255 - m

-- (AD11) CONFORMANCE IS DECIDABLE ON THE EMITTED CUBE. A cube built
--        by the law scores 1.0 at every stratum; a freely-assigned
--        cube does not, and the gap is the S8 port's price. The
--        finest stratum is conformant for free (its blocks are single
--        voxels), so only the coarser strata carry information —
--        which is exactly why a rung that writes nothing cannot be
--        measured, and a rung that writes bits can.
axiom_AD11 :: Bool
axiom_AD11 =
     all (\st -> abs (conformance st lawful - 1) < 1e-12) strata
  && abs (conformance s64 free - 1) < 1e-12       -- free at the fine rung
  && conformance s16 free < 0.01                  -- coarse strata are not
  && conformance s32 free < 0.01
  && blockSide s16 == 4 && blockSide s32 == 2 && blockSide s64 == 1
  && length (blocksOf s16 lawful) == 1 * 16 * 16      -- 4 frames / 4
  && length (blocksOf s32 lawful) == 2 * 32 * 32
  && length (blocksOf s64 lawful) == 4 * 64 * 64
  where
    lawful = lawfulCube 3
    free = freeCube 5

-- (AD12) THE CENSUS COUNTS WHAT THE LAW BOUNDS. Classes used at a
--        stratum never exceed that stratum's level, the counts are
--        monotone down the ladder (a finer stratum can only split
--        what a coarser one already separated), and a lawful cube
--        with enough blocks reaches every class.
axiom_AD12 :: Bool
axiom_AD12 =
     all (\st -> classesUsed st lawful <= stLevel st) strata
  && all (\st -> classesUsed st free <= stLevel st) strata
  && and [ classesUsed a lawful <= classesUsed b lawful
         | (a, b) <- zip strata (tail strata) ]
  && and [ classesUsed a free <= classesUsed b free
         | (a, b) <- zip strata (tail strata) ]
  && classesUsed role lawful == 2
  && classesUsed s64 free > 200          -- free assignment spreads wide
  where
    lawful = lawfulCube 3
    free = freeCube 5

-- ════════════════════════════════════════════════════════════════
-- § 7. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AdditiveLadder: every rung writes bits of every index"
  putStrLn " index = role·128 + r16·64 + r32·8 + r64"
  putStrLn " no rung is telemetry — Daniel's ruling 2026-08-14"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "AD1  partition: 1+1+3+3 disjoint, exhausts the 8 bits"     [axiom_AD1]
  check "AD2  composition: index = Σ strata, a bijection on 256"    [axiom_AD2]
  check "AD3  rung seating forced: voxels ×8 ⇔ classes ×8"          [axiom_AD3]
  check "AD4  ★ the 1024 invariant — same at every rung"            [axiom_AD4]
  check "AD5  prefix consistency: refine, never revise (PT5)"       [axiom_AD5]
  check "AD6  descent correspondence: [2,8,8] == the strata (DL1)"  [axiom_AD6]
  check "AD7  ★ role bit DERIVED: 17 tile patterns, not 2^16"       [axiom_AD7]
  check "AD8  budget 905574 b vs 2097152 flat = 2.316:1"            [axiom_AD8]
  check "AD9  energy aligns: Σ stratum energies == E (TE/WS4)"      [axiom_AD9]
  check "AD10 ★ no rung is silent — each changes the artifact"      [axiom_AD10]
  check "AD11 conformance decidable on the emitted cube (S1/S8)"    [axiom_AD11]
  check "AD12 census counts are bounded and monotone by stratum"    [axiom_AD12]
  putStrLn ""
  putStrLn "── CONFORMANCE OF A FREELY-ASSIGNED CUBE (today's shape) ─"
  putStrLn "  stratum   block    conformance   classes used / level"
  mapM_ censusRow strata
  putStrLn ""
  putStrLn "── THE STRATA ────────────────────────────────────────────"
  putStrLn "  stratum   bits    writer      voxels   classes      bits/cube"
  mapM_ row strata
  putStrLn $ "  " ++ pad 10 "Σ" ++ pad 8 "8"
               ++ pad 12 "" ++ pad 9 "" ++ pad 10 "256"
               ++ fmt totalBits ++ " b = " ++ fmt (totalBits / 8192) ++ " KiB"
  putStrLn $ "  flat 64³ × 8 bits = " ++ fmt flatBits ++ " b = 256 KiB"
               ++ "   ratio " ++ fmt structuralRatio ++ ":1"
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  A rung that only measures is not a view of the GIF, it"
  putStrLn "  is a view of the measurement. Here each rung writes its"
  putStrLn "  own bits of every index: 16³ says which quarter of the"
  putStrLn "  palette, 32³ which eighth of that, 64³ which leaf. The"
  putStrLn "  index is their sum, so nothing has to survive pooling —"
  putStrLn "  balance is authored at each rung natively, 1024 voxels"
  putStrLn "  per class, the same number all the way down. Depth"
  putStrLn "  keeps allocation and the rungs keep colour."
  putStrLn "══════════════════════════════════════════════════════════"

censusRow :: Stratum -> IO ()
censusRow st = putStrLn $
  "  " ++ pad 10 (stName st)
       ++ pad 9 (show (blockSide st) ++ "³")
       ++ pad 14 (fmt (conformance st free))
       ++ show (classesUsed st free) ++ " / " ++ show (stLevel st)
  where free = freeCube 5

row :: Stratum -> IO ()
row st = putStrLn $
  "  " ++ pad 10 (stName st)
       ++ pad 8 (show (stWidth st))
       ++ pad 12 (if stRung st == 0 then "depth" else show (stRung st) ++ "³")
       ++ pad 9 (if stRung st == 0 then show (voxels 16) else show (voxels (stRung st)))
       ++ pad 10 (show (stLevel st))
       ++ fmt (stratumBits st)

fmt :: Double -> String
fmt v = show (fromIntegral (round (v * 100) :: Integer) / 100 :: Double)

pad :: Int -> String -> String
pad n s = s ++ replicate (max 1 (n - length s)) ' '

check :: String -> [Bool] -> IO ()
check name results =
  let mark = if and results then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
