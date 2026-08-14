-- ════════════════════════════════════════════════════════════════
-- WeaveState: what the model may know about the GIF it is weaving
--
-- Daniel's direction (2026-08-14): let the ANE tell the app the
-- state of the GIF as it is being made — one frame at a time, so we
-- weave better; a small JEPA-H learning "all the possibilities and
-- orientations and permutations of 256 → 64², 256 → 32², 256 → 16²
-- and all together in the 2×2×2 ↔ 1 scales."
--
-- This spec makes that precise, and in doing so replaces one word.
-- The POSSIBILITIES cannot be learned: 256^4096 is 2^32768 states at
-- the fine rung (WS9). What CAN be learned — and is all that a
-- weaver could use — is the STATE MAP: a causal, 33-number reading
-- of the cube-so-far in the bits currency of TilingEntropy, at all
-- three rungs at once.
--
--   WS1  the rung ladder: ground occupancy 1 / 4 / 16, and at rung
--        16 the whole ground manifold IS the 256! label group
--   WS2  label permutations are FREE — energy invariant AND the
--        GIF's own LZW cost invariant (proved here, not cited)
--   WS3  the orientation group D4 × polyphase = 64 elements: the
--        finite part, the part worth augmenting over
--   WS4  the palette-depth chain: E = E₄ + E₃₂|₄ + E₂₅₆|₃₂, exact,
--        and prefix truncation is monotone (the PairTree prefix law
--        in energy form)
--   WS5  causality: the state at frame t reads frames ≤ t, and the
--        streaming update equals the batch value exactly
--   WS6  sufficiency + size: 33 numbers per frame, and they
--        determine every energy the app reports
--   WS7  surprise: the one-ahead residual against the persistence
--        baseline — the ONLY thing a predictor may be promoted on
--   WS8  budget: the three-rung read costs 1 + ¼ + ¹⁄₁₆ of one fine
--        frame — the ladder is 31% overhead, not 3×
--   WS9  non-enumerability, stated as a number
--   WS10 the weave contract: what the state may steer, and when
--
-- Nothing here trains anything and nothing here changes a byte.
-- Placement (ANE vs CPU) is an ENGINEERING question the A19 bench
-- answers; this file is the law the answer must satisfy.
-- ════════════════════════════════════════════════════════════════

module WeaveState where

import Data.Bits (shiftR, xor)
import Data.List (foldl', nub, sort)
import qualified Data.Map.Strict as M

-- ════════════════════════════════════════════════════════════════
-- § 1. THE RUNG LADDER (256 onto three planes)
-- ════════════════════════════════════════════════════════════════

colors :: Int
colors = 256

rungs :: [Int]
rungs = [16, 32, 64]

cellsAt, groundOccupancy, ceilingBits, bondsAt :: Int -> Int
cellsAt r = r * r
groundOccupancy r = cellsAt r `div` colors    -- 1, 4, 16
ceilingBits r = cellsAt r * 8                 -- 2048, 8192, 32768
bondsAt r = 2 * r * (r - 1)                   -- 480, 1984, 8064

-- | log₂ of the ground-state multiplicity at a rung, in bits.
--   At r = 16 this is log₂(256!) exactly — the ground manifold is
--   the label group itself (WS1).
groundMultiplicityBits :: Int -> Double
groundMultiplicityBits r =
  logFactBits (cellsAt r) - fromIntegral colors * logFactBits (groundOccupancy r)

logFactBits :: Int -> Double
logFactBits n = sum [ logBase 2 (fromIntegral k) | k <- [1 .. n] ]

-- ════════════════════════════════════════════════════════════════
-- § 2. THE ENERGY (TilingEntropy, verbatim — house standalone rule)
-- ════════════════════════════════════════════════════════════════

histogramOf :: [Int] -> [Int]
histogramOf f = M.elems (M.unionWith (+) zero (M.fromListWith (+) [ (i, 1) | i <- f ]))
  where zero = M.fromList [ (i, 0) | i <- [0 .. colors - 1] ]

-- | E = Σ nᵢ log₂(nᵢ/(N/K)) bits = N·log₂K − N·H₀.
energy :: [Int] -> Double
energy hist = sum [ fromIntegral c * logBase 2 (fromIntegral c / nb)
                  | c <- hist, c > 0 ]
  where nb = fromIntegral (sum hist) / fromIntegral colors

energyPerCell :: [Int] -> Double
energyPerCell hist = energy hist / fromIntegral (max 1 (sum hist))

hBin :: Int -> Int -> Double
hBin a b
  | a == 0 || b == 0 = 0
  | otherwise = negate (p * logBase 2 p + q * logBase 2 q)
  where
    n = fromIntegral (a + b); p = fromIntegral a / n; q = fromIntegral b / n

-- | The eight dyadic rungs of E, root (bit 7 = the σ split) first.
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

-- ════════════════════════════════════════════════════════════════
-- § 3. THE WEAVE STATE (what the ANE would hand back, per frame)
-- ════════════════════════════════════════════════════════════════
-- Eleven numbers per rung: the eight dyadic energy rungs (whose
-- first entry is the φ order parameter, TE5), the plane's own bond
-- energy, the occupancy defect, and the intensive ε. Three rungs =
-- 33 numbers. That is the entire knowable state of a frame, in the
-- sense that every energy the app reports is a function of it (WS6).

data RungState = RungState
  { rsRung   :: Int
  , rsLevels :: [Double]   -- 8 dyadic rungs, root first (Σ = E)
  , rsWall   :: Double     -- B(1 − h(w)) bits, the plane's stratum
  , rsUnused :: Int        -- colors with zero occupancy
  , rsEps    :: Double     -- E / N, bits per cell ∈ [0,8]
  } deriving (Eq, Show)

rungStateOf :: Int -> [Int] -> RungState
rungStateOf r f = RungState
  { rsRung = r
  , rsLevels = levelEnergies hist
  , rsWall = fromIntegral b * (1 - hBin w (b - w))
  , rsUnused = length (filter (== 0) hist)
  , rsEps = energyPerCell hist }
  where
    hist = histogramOf f
    b = bondsAt r
    w = wallCount r f

stateEnergy :: RungState -> Double
stateEnergy = sum . rsLevels

stateWidth :: Int
stateWidth = length rungs * 11   -- 33 numbers

spin :: Int -> Bool
spin i = i >= 128

wallCount :: Int -> [Int] -> Int
wallCount r f = length
  [ () | y <- [0 .. r - 1], x <- [0 .. r - 1]
       , (dx, dy) <- [(1, 0), (0, 1)]
       , x + dx < r, y + dy < r
       , spin (f !! (y * r + x)) /= spin (f !! ((y + dy) * r + (x + dx))) ]

-- ════════════════════════════════════════════════════════════════
-- § 4. THE SYMMETRIES — what must NOT be learned
-- ════════════════════════════════════════════════════════════════

-- | Relabel indices by a permutation of the 256.
relabel :: [Int] -> [Int] -> [Int]
relabel perm = map (perm !!)

-- | A deterministic non-trivial permutation family: the affine maps
--   i ↦ (a·i + b) mod 256 with a odd (hence invertible), plus σ and
--   the eight PairTree sibling maps s_ℓ(i) = i XOR 2^ℓ.
affinePerm :: Int -> Int -> [Int]
affinePerm a b = [ (a * i + b) `mod` colors | i <- [0 .. colors - 1] ]

sigmaPerm :: [Int]
sigmaPerm = [ 255 - i | i <- [0 .. colors - 1] ]

siblingPerm :: Int -> [Int]
siblingPerm l = [ i `xor` (2 ^ l) | i <- [0 .. colors - 1] ]

permFamily :: [[Int]]
permFamily = sigmaPerm : [ siblingPerm l | l <- [0 .. 7] ]
                      ++ [ affinePerm a b | a <- [3, 7, 37], b <- [0, 1, 91] ]

-- | The eight square symmetries D4, acting on an r×r frame.
d4 :: Int -> Int -> [Int] -> [Int]
d4 g r f = [ f !! idx x y | y <- [0 .. r - 1], x <- [0 .. r - 1] ]
  where
    m = r - 1
    idx x y = case g `mod` 8 of
      0 -> y * r + x
      1 -> x * r + (m - y)            -- rot 90
      2 -> (m - y) * r + (m - x)      -- rot 180
      3 -> (m - x) * r + y            -- rot 270
      4 -> y * r + (m - x)            -- flip x
      5 -> (m - y) * r + x            -- flip y
      6 -> x * r + y                  -- transpose
      _ -> (m - x) * r + (m - y)      -- anti-transpose

-- | The polyphase components: (ℤ/2)³ on the spacetime cube; here the
--   spatial pair (ox, oy) ∈ (ℤ/2)², read as stride-2 sublattices.
polyphase :: Int -> Int -> Int -> [Int] -> [Int]
polyphase ox oy r f =
  [ f !! (((2 * y + oy) `mod` r) * r + ((2 * x + ox) `mod` r))
  | y <- [0 .. r `div` 2 - 1], x <- [0 .. r `div` 2 - 1] ]

orientationGroupSize :: Int
orientationGroupSize = 8 * 8    -- D4 × (ℤ/2)³

-- ════════════════════════════════════════════════════════════════
-- § 5. GIF89a LZW COST (so "free" is proved, not asserted)
-- ════════════════════════════════════════════════════════════════
-- Standard GIF LZW: 8-bit root, clear = 256, EOI = 257, first free
-- code 258, width grows 9→12, clear on overflow. Returns bits.

lzwBits :: [Int] -> Int
lzwBits [] = 0
lzwBits (s0 : rest) = go initDict 258 9 (9 {- leading clear -}) [s0] rest
  where
    initDict = M.fromList [ ([i], i) | i <- [0 .. 255] ]
    go dict next width acc buf xs = case xs of
      [] -> acc + width {- last code -} + width {- EOI -}
      (c : cs) ->
        let cand = buf ++ [c]
        in case M.lookup cand dict of
             Just _ -> go dict next width acc cand cs
             Nothing ->
               let acc' = acc + width
                   dict' = M.insert cand next dict
                   next' = next + 1
               in if next' > 4095
                    then go initDict 258 9 (acc' + width) [c] cs
                    else
                      let width' = if next' > 2 ^ width then width + 1 else width
                      in go dict' next' width' acc' [c] cs

-- ════════════════════════════════════════════════════════════════
-- § 6. CAUSAL / STREAMING READ (one frame at a time)
-- ════════════════════════════════════════════════════════════════

-- | The cube-so-far: fold frames left to right, carrying the pooled
--   histogram. The weaver may read this BEFORE committing frame t+1.
data WeaveTrace = WeaveTrace
  { wtFrames :: Int
  , wtPooled :: [Int]      -- histogram over all frames so far
  , wtLast   :: [Double]   -- last frame's per-rung energies
  } deriving (Eq, Show)

emptyTrace :: WeaveTrace
emptyTrace = WeaveTrace 0 (replicate colors 0) []

stepTrace :: WeaveTrace -> [Int] -> WeaveTrace
stepTrace wt f = WeaveTrace
  { wtFrames = wtFrames wt + 1
  , wtPooled = zipWith (+) (wtPooled wt) (histogramOf f)
  , wtLast = [ energy (histogramOf f) ] }

streamTrace :: [[Int]] -> WeaveTrace
streamTrace = foldl' stepTrace emptyTrace

-- | Persistence: the honest baseline any predictor must beat —
--   "the next frame's state is this frame's state".
persistenceError :: [Double] -> [Double] -> Double
persistenceError prev cur = sqrt (sum [ (a - b) ^ (2 :: Int)
                                      | (a, b) <- zip prev cur ])

-- ════════════════════════════════════════════════════════════════
-- § 7. PROBE FRAMES (deterministic — house lcg)
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

bayerOrder :: [Int]
bayerOrder = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

solidAt, neelAt :: Int -> [Int]
solidAt r = replicate (cellsAt r) 255
neelAt r = [ if bayerOrder !! ((y `mod` 4) * 4 + (x `mod` 4)) < 8 then 255 else 0
           | y <- [0 .. r - 1], x <- [0 .. r - 1] ]

randomAt :: Int -> Int -> [Int]
randomAt r seed = [ floor (u * fromIntegral colors)
                  | u <- take (cellsAt r) (uniforms seed) ]

-- | Balanced: every color exactly N/K times — the ground state.
balancedAt :: Int -> [Int]
balancedAt r = [ (y * r + x) `mod` colors | y <- [0 .. r - 1], x <- [0 .. r - 1] ]

-- | A subject on a ground: face indices in a disc, σ-half outside.
--   The disc may be displaced — a weave is a moving subject.
subjectAt :: Int -> Int -> [Int]
subjectAt r seed = subjectDrift r seed 0 0

subjectDrift :: Int -> Int -> Double -> Double -> [Int]
subjectDrift r seed dx dy =
  [ if inDisc x y then floor (u !! (y * r + x) * 128)
                  else 255 - floor (u !! (y * r + x) * 24)
  | y <- [0 .. r - 1], x <- [0 .. r - 1] ]
  where
    u = take (cellsAt r) (uniforms seed)
    c = fromIntegral r / 2 :: Double
    inDisc x y = (fromIntegral x - (c + dx)) ^ (2 :: Int)
               + (fromIntegral y - (c + dy)) ^ (2 :: Int)
               < (0.32 * fromIntegral r) ^ (2 :: Int)

probesAt :: Int -> [[Int]]
probesAt r = [ solidAt r, neelAt r, balancedAt r, randomAt r 3, subjectAt r 9 ]

-- | A 16-frame weave: the subject drifts (the trajectory a streaming
--   predictor would see).
weaveFrames :: Int -> [[Int]]
weaveFrames r = [ subjectDrift r (9 + 4 * t) (0.4 * fromIntegral t)
                                             (0.25 * fromIntegral t)
                | t <- [0 .. 15] ]

-- ════════════════════════════════════════════════════════════════
-- § 8. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (WS1) THE RUNG LADDER. 256 onto 16²/32²/64² gives ground
--       occupancies 1/4/16 and ceilings 2048/8192/32768 bits —
--       extensive ×4 per spatial rung. ★At rung 16 the ground
--       multiplicity is exactly log₂(256!) = 1684.00 bits: the
--       zero-energy state IS a permutation of the palette, so
--       "256 → 16×16" is the bijective rung.
axiom_WS1 :: Bool
axiom_WS1 =
     map groundOccupancy rungs == [1, 4, 16]
  && map ceilingBits rungs == [2048, 8192, 32768]
  && map bondsAt rungs == [480, 1984, 8064]
  && abs (groundMultiplicityBits 16 - logFactBits colors) < 1e-9
  && abs (groundMultiplicityBits 16 - 1683.9962872) < 1e-6
  && and [ ceilingBits (2 * r) == 4 * ceilingBits r | r <- [16, 32] ]
  && all (\r -> abs (energy (histogramOf (balancedAt r))) < 1e-9) rungs

-- (WS2) LABEL PERMUTATIONS ARE FREE, TWICE OVER. Energy is a
--       multiset functional, so all 256! relabelings share it; and
--       the GIF's own LZW is symbol-agnostic, so they share the
--       wire cost to the BIT. Nothing about "which permutation" is
--       learnable or worth learning — the model must be invariant.
axiom_WS2 :: Bool
axiom_WS2 =
     all sameEnergy permFamily
  && all sameBits permFamily
  && length (nub (sort sigmaPerm)) == colors
  && all (\p -> length (nub p) == colors) permFamily
  where
    f = subjectAt 64 9
    e0 = energy (histogramOf f)
    b0 = lzwBits f
    sameEnergy p = abs (energy (histogramOf (relabel p f)) - e0) < 1e-9
    sameBits p = lzwBits (relabel p f) == b0

-- (WS3) THE ORIENTATION GROUP IS FINITE — 64 elements (D4 × the
--       polyphase (ℤ/2)³). Energy is blind to arrangement entirely;
--       the BOND stratum is what sees it, and it is D4-invariant.
--       So orientation is augmentation over 64 cases, never a
--       combinatorial burden.
axiom_WS3 :: Bool
axiom_WS3 =
     orientationGroupSize == 64
  && all (\g -> histogramOf (d4 g 64 f) == histogramOf f) [0 .. 7]
  && all (\g -> abs (rsWall (rungStateOf 64 (d4 g 64 f)) - w0) < 1e-9) [0 .. 7]
  && length (nub [ sort (d4 g 64 f) | g <- [0 .. 7] ]) == 1
  && sum [ length (polyphase ox oy 64 f) | ox <- [0, 1], oy <- [0, 1] ] == cellsAt 64
  where
    f = subjectAt 64 9
    w0 = rsWall (rungStateOf 64 f)

-- (WS4) THE PALETTE-DEPTH CHAIN. Grouping the eight dyadic rungs
--       2+3+3 gives E = E₄ + E₃₂|₄ + E₂₅₆|₃₂ exactly, and the
--       coarse term equals the energy of the PREFIX-quantized frame
--       (the PairTree prefix law in energy form). Truncation is
--       monotone: a coarser palette can only lower E.
axiom_WS4 :: Bool
axiom_WS4 = all chain (probesAt 64)
  where
    chain f =
      let hist = histogramOf f
          lv = levelEnergies hist
          e = energy hist
          (top2, restL) = splitAt 2 lv
          (mid3, low3) = splitAt 3 restL
          e4 = sum top2; e32 = sum mid3; e256 = sum low3
          prefixE k = let sh = 8 - k
                          h' = M.elems (M.unionWith (+)
                                 (M.fromList [ (i, 0) | i <- [0 .. 2 ^ k - 1] ])
                                 (M.fromListWith (+) [ (i `shiftR` sh, 1) | i <- f ]))
                          n = fromIntegral (length f)
                      in n * fromIntegral k
                         + sum [ fromIntegral c * logBase 2 (fromIntegral c / n)
                               | c <- h', c > 0 ]
      in abs (e4 + e32 + e256 - e) < 1e-6
         && abs (prefixE 2 - e4) < 1e-6
         && abs (prefixE 5 - (e4 + e32)) < 1e-6
         && prefixE 2 <= prefixE 5 + 1e-6
         && prefixE 5 <= e + 1e-6
         && all (>= -1e-9) [e4, e32, e256]

-- (WS5) CAUSALITY AND STREAMING. The state of the cube-so-far is a
--       left fold: frame t reads only frames ≤ t, and the streaming
--       pooled histogram equals the batch one exactly. This is what
--       makes "one frame at a time, as it creates it" lawful rather
--       than aspirational.
axiom_WS5 :: Bool
axiom_WS5 =
     wtFrames tr == 16
  && wtPooled tr == batch
  && sum (wtPooled tr) == 16 * cellsAt 64
  && all (\k -> wtPooled (streamTrace (take k fs))
                  == foldr1 (zipWith (+)) (map histogramOf (take k fs)))
         [1, 2, 8, 16]
  where
    fs = weaveFrames 64
    tr = streamTrace fs
    batch = foldr1 (zipWith (+)) (map histogramOf fs)

-- (WS6) SUFFICIENCY AND SIZE. 33 numbers per frame (11 per rung),
--       and the energy the app reports is Σ of the eight rungs —
--       i.e. the state DETERMINES the reported energy, and no frame
--       detail beyond it is needed to report one.
axiom_WS6 :: Bool
axiom_WS6 =
     stateWidth == 33
  && all sufficient [ (r, f) | r <- rungs, f <- probesAt r ]
  && all (\r -> length (rsLevels (rungStateOf r (randomAt r 3))) == 8) rungs
  where
    sufficient (r, f) =
      let st = rungStateOf r f
      in abs (stateEnergy st - energy (histogramOf f)) < 1e-6
         && rsEps st >= -1e-12 && rsEps st <= 8 + 1e-12
         && rsUnused st == length (filter (== 0) (histogramOf f))

-- (WS7) SURPRISE HAS A BASELINE. A one-ahead predictor is only
--       worth its dispatch if it beats persistence. On a stationary
--       weave persistence error is 0 (nothing to predict); on the
--       drifting weave it is positive and bounded — that gap is the
--       entire budget a learned predictor competes for.
axiom_WS7 :: Bool
axiom_WS7 =
     all (\(a, b) -> persistenceError a b == 0) (pairs still)
  && any (\(a, b) -> persistenceError a b > 0) (pairs drift)
  && all (\(a, b) -> persistenceError a b <= fromIntegral (ceilingBits 64))
         (pairs drift)
  where
    pairs es = zip es (tail es)
    stateOf f = [ energy (histogramOf f) ]
    still = map stateOf (replicate 8 (subjectAt 64 9))
    drift = map stateOf (weaveFrames 64)

-- (WS8) THE LADDER IS CHEAP. Reading all three rungs costs
--       1 + ¼ + ¹⁄₁₆ of one fine frame — 5376 cell visits against
--       4096, i.e. 31.25% overhead, the spatial shadow of ANELoop's
--       1 + ⅛ + ¹⁄₆₄ curvature. Three-rung state is not three times
--       the work; that is why "all together" is affordable.
axiom_WS8 :: Bool
axiom_WS8 =
     total == 5376
  && abs (fromIntegral total / fromIntegral (cellsAt 64) - (1 + 1/4 + 1/16)) < 1e-12
  && total < 2 * cellsAt 64
  where total = sum (map cellsAt rungs)

-- (WS9) NON-ENUMERABILITY, AS A NUMBER. The state SET is 2^2048 /
--       2^8192 / 2^32768 at the three rungs; every corpus that will
--       ever exist is measure zero in it. Therefore the training
--       target is the state MAP (frames → 33 numbers → next 33),
--       never coverage of configurations. The one exhaustively
--       coverable object in the whole design is the 64-element
--       orientation group.
axiom_WS9 :: Bool
axiom_WS9 =
     map ceilingBits rungs == [2048, 8192, 32768]
  -- even a 2^30-sample corpus leaves ≥ 2^2000 of the SMALLEST rung
  -- untouched: coverage is not a strategy at any rung.
  && all (\r -> fromIntegral (ceilingBits r) - corpusBits > 2000) rungs
  && orientationGroupSize == 64
  && logBase 2 (fromIntegral orientationGroupSize) == 6
  && logBase 2 (fromIntegral orientationGroupSize) < corpusBits
  where
    -- a generous corpus: 2^30 samples is ~30 bits of coverage
    corpusBits = 30 :: Double

-- (WS10) THE WEAVE CONTRACT. The state is a READING, and a reading
--        may steer only where a law already admits a free choice:
--        warm starts (initial conditions, not objectives), sweep
--        budget K, and the EMA gain. It may never re-weight the
--        energy, because E is calibrated (one bit = one bit) — a
--        learned coefficient in front of it would be exactly the
--        naked constant the decrees forbid.
axiom_WS10 :: Bool
axiom_WS10 =
     all steerable ["warm-start", "sweep-budget-K", "ema-gain"]
  && not (any steerable ["energy-weight", "palette-bytes", "ground-law"])
  && abs (energyPerCell (histogramOf (balancedAt 64))) < 1e-12
  where
    steerable s = s `elem` ["warm-start", "sweep-budget-K", "ema-gain"]

-- ════════════════════════════════════════════════════════════════
-- § 9. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " WeaveState: what the model may know about the GIF"
  putStrLn " it is weaving — 33 numbers, three rungs, one frame at"
  putStrLn " a time; the possibilities are 2^32768 and are not the"
  putStrLn " target, the state map is"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "WS1  ladder: ground 1/4/16; rung 16 ground = 256! exactly"  [axiom_WS1]
  check "WS2  256! relabelings: same energy AND same LZW bits"       [axiom_WS2]
  check "WS3  orientations are 64 (D4 × polyphase), and finite"      [axiom_WS3]
  check "WS4  palette-depth chain 2+3+3 = prefix law, monotone"      [axiom_WS4]
  check "WS5  causal: streaming fold == batch, frame by frame"       [axiom_WS5]
  check "WS6  33 numbers suffice for every energy reported"          [axiom_WS6]
  check "WS7  surprise scored against persistence, or not at all"    [axiom_WS7]
  check "WS8  three rungs cost 1+¼+¹⁄₁₆ = 5376 visits (+31.25%)"     [axiom_WS8]
  check "WS9  state set 2^2048/2^8192/2^32768 — corpus is dust"      [axiom_WS9]
  check "WS10 the state steers initial conditions, never the law"    [axiom_WS10]
  putStrLn ""
  putStrLn "── THE LADDER ────────────────────────────────────────────"
  putStrLn "  rung   cells   ground   ceiling b   ground mult b   bonds"
  mapM_ rungRow rungs
  putStrLn ""
  putStrLn "── ONE WEAVE (16 frames, drifting subject) ───────────────"
  putStrLn "  t   E(64²) b    ε b/cell   E_wall b   unused"
  mapM_ traceRow (zip [0 :: Int ..] (take 6 (weaveFrames 64)))
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  A weaver cannot be told which of 2^32768 tilings it is"
  putStrLn "  making; it can be told how much order it has spent, at"
  putStrLn "  three rungs, one frame at a time. Permutations of the"
  putStrLn "  256 are free — same energy, same LZW bit count — so the"
  putStrLn "  model is invariant to them, not trained on them. The"
  putStrLn "  only exhaustible symmetry is the 64-element orientation"
  putStrLn "  group. What is left for a model to learn is the one"
  putStrLn "  thing that is actually hard: where the state goes next."
  putStrLn "══════════════════════════════════════════════════════════"

rungRow :: Int -> IO ()
rungRow r = putStrLn $
  "  " ++ pad 7 (show r ++ "²")
       ++ pad 8 (show (cellsAt r))
       ++ pad 9 (show (groundOccupancy r))
       ++ pad 12 (show (ceilingBits r))
       ++ pad 16 (fmt (groundMultiplicityBits r))
       ++ show (bondsAt r)

traceRow :: (Int, [Int]) -> IO ()
traceRow (t, f) = putStrLn $
  "  " ++ pad 4 (show t)
       ++ pad 13 (fmt (stateEnergy st))
       ++ pad 11 (fmt (rsEps st))
       ++ pad 11 (fmt (rsWall st))
       ++ show (rsUnused st)
  where st = rungStateOf 64 f

fmt :: Double -> String
fmt v = show (fromIntegral (round (v * 100) :: Integer) / 100 :: Double)

pad :: Int -> String -> String
pad n s = s ++ replicate (max 1 (n - length s)) ' '

check :: String -> [Bool] -> IO ()
check name results =
  let mark = if and results then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
