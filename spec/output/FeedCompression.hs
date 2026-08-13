{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- FeedCompression: RGB+depth compressed into THREE SCALES AT THEIR
-- OWN RATES — the format the synthetic corpus must imitate
--
-- Daniel (2026-08-13): "we need to compress the feed into the 3
-- scales at the scale rates. so that when we train on synthetic
-- data they approximate the real data that is in the compressed
-- format. compression of the feed of RGB+depth. Where depth is
-- what gives us user and background boundary."
--
-- ── THE RATE LAW ────────────────────────────────────────────────
--
-- The 2×2×2 atom acts on TIME as well as space (Octave OV10), so a
-- rung is not merely a resolution — it is a RATE. One κ step halves
-- the side AND halves the frame count, leaving the LOOP DURATION
-- invariant:
--
--   rung 64 : 64 frames, delay  5 cs → 20 Hz
--   rung 32 : 32 frames, delay 10 cs → 10 Hz
--   rung 16 : 16 frames, delay 20 cs →  5 Hz
--
--   side × delay = 320 cs = 3.2 s AT EVERY RUNG (FC1)
--
-- ★ This table is not new. TriScaleLadder.swift:50 already ships
-- it, and DyadPreview's 5 Hz slow state (refreshStride = 4) is
-- ALREADY the rung-16 rate. The machine has been running the
-- coarsest scale at its correct rate all along, and calling it a
-- preview cadence.
--
-- ── WHY THIS IS CHEAPER THAN WHAT SHIPS TODAY (FC4, FC5) ────────
--
-- Each κ step costs 1/8 of the rung above (half in x, y and t), so
-- carrying ALL THREE rungs costs
--
--   1 + 1/8 + 1/64 = 73/64 = 1.140625
--
-- — a 14% tax over the fine rung alone. And because today's
-- CapturedFrame stores fp32 triples holding values that are exactly
-- k/255, the WHOLE THREE-RUNG PYRAMID at honest typing (8-bit OKLab
-- + fp16 depth) is 1.43 MiB against the 4.00 MiB single rung the
-- app retains now. The parallel read is not an extravagance. It is
-- 2.8× SMALLER than the status quo.
--
-- ── DEPTH IS THE BOUNDARY (FC6) ─────────────────────────────────
--
-- RGB says what colour; depth says WHOSE — user or background. It
-- is the only channel that carries the figure/ground split, which
-- is what RoleAllocation spends the entropy budget on. So depth is
-- compressed at every rung alongside colour, never derived from it.
--
-- The crossover must AGREE across rungs, or the three streams
-- disagree about where the user is. Pooling preserves the mean but
-- SHRINKS the variance, so a coarse-rung mixture fit must be
-- τ-lifted (the law of total variance, DepthMixture's existing
-- lift) before its crossover is comparable — FC6 states the
-- requirement and the direction of the bias.
--
-- ── THE ATTRACTORS (FC7) ────────────────────────────────────────
--
-- Daniel: "the pattern 1:1:2:4:8:16:32:64:64:32:16:8:4:2:1:1 are
-- attractors. color concentrations."
--
-- Sixteen basins, one per rung-16 row, holding 256 colours between
-- them. The profile is σ-symmetric and doubling: the two largest
-- basins hold 128 of the 256 — HALF the palette sits in an eighth
-- of the basins. That concentration is the point: colour does not
-- spread evenly over the table, it pools.
--
-- ── TILING AND TIGHTNESS (FC8, FC9) ─────────────────────────────
--
-- "I need tight phase diagram energy computation so that I can tile
-- the 64³." Tight = ADDITIVE. The configuration energy of the cube
-- decomposes EXACTLY into per-tile interiors plus the walls between
-- tiles, so a phase may be computed tile-local and composed — and
-- re-computed for one tile without touching the rest. That is what
-- makes a full 64³ re-solve per tick affordable.
--
-- ── AXIOMS ──────────────────────────────────────────────────────
--
--   FC1  ★ the rate law: side × delay = 320 cs at every rung; the
--        loop duration is the invariant, the rung sets the rate
--   FC2  frames = side: κ halves time exactly as it halves space
--   FC3  the payload is OKLab+depth, four channels, at every rung
--   FC4  ★ the pyramid tax is exactly 73/64 — all three rungs for
--        14% over the finest alone
--   FC5  ★ the three-rung pyramid is SMALLER than today's one rung
--   FC6  depth carries the boundary; pooling shrinks its variance,
--        so coarse fits need the τ-lift to agree
--   FC7  ★ the attractor ladder: 16 basins, 256 colours, σ-
--        symmetric, doubling, half the palette in two basins
--   FC8  the 64³ tiles EXACTLY by 4³ blocks — 4096 tiles, a true
--        partition, no remainder
--   FC9  ★ TIGHTNESS: the configuration energy is exactly additive
--        over tiles plus walls, so phase is tile-local
--   FC10 ★ the sampler interface: the compressed format is a TOTAL
--        function (rung, t, y, x) → (rgb, depth). Synthetic and
--        real data inhabit the same type by construction, which is
--        what NO-CAPTURE-TRAINING requires
-- ════════════════════════════════════════════════════════════════

module Main where

import Data.List (nub, sort)
import Data.Ratio ((%), numerator, denominator)

type Q = Rational

-- ════════════════════════════════════════════════════════════════
-- § 1. THE RUNGS, AS RATES
-- ════════════════════════════════════════════════════════════════

rungs :: [Int]
rungs = [64, 32, 16]

-- | The loop, in centiseconds. Invariant across rungs.
loopCs :: Int
loopCs = 320

-- | GIF inter-frame delay at a rung, in centiseconds.
delayCs :: Int -> Int
delayCs side = loopCs `div` side

-- | Frames at a rung. κ halves time with space, so a rung's frame
--   count IS its side.
frames :: Int -> Int
frames side = side

-- | Rate in Hz as an exact rational: frames per 3.2 s.
rateHz :: Int -> Q
rateHz side = fromIntegral (frames side * 100) % fromIntegral loopCs

-- ════════════════════════════════════════════════════════════════
-- § 2. THE PAYLOAD
-- ════════════════════════════════════════════════════════════════

-- | Four channels per cell: colour, and the boundary.
--
--   ★ THE COLOUR CHANNELS ARE OKLab, NOT sRGB. κ is a MEAN, and
--   averaging gamma-encoded sRGB averages a nonlinear code rather
--   than a colour — the pooled value would not be the perceptual
--   centre of what it pools. Every law in Octave.hs and
--   PhaseTiling.hs rests on the mean being meaningful and on
--   distance being Euclidean, and OKLab is the space where both
--   hold. (ISP.Oklab's downsampleMean2Oklab is the same primitive,
--   and DyadPalette already analyses in OKLab.)
data Channel = L | A | B | D deriving (Eq, Ord, Show, Enum, Bounded)

channels :: [Channel]
channels = [minBound .. maxBound]

-- | Cells at a rung: side² per frame × side frames = side³.
cells :: Int -> Int
cells side = side * side * side

-- | Values at a rung: one per channel per cell.
values :: Int -> Int
values side = cells side * length channels

-- | Honest bytes per cell: 8-bit OKLab + fp16 depth.
bytesPerCell :: Int
bytesPerCell = 3 + 2

bytesAt :: Int -> Int
bytesAt side = cells side * bytesPerCell

pyramidBytes :: Int
pyramidBytes = sum (map bytesAt rungs)

-- | What the app retains TODAY: one rung, fp32 triples + fp32
--   depth (CapturedFrame.swift — 12 B colour + 4 B depth).
todayBytesPerCell :: Int
todayBytesPerCell = 12 + 4

todayBytes :: Int
todayBytes = cells 64 * todayBytesPerCell

-- | The tax of carrying all three rungs, as a ratio to the finest.
pyramidTax :: Q
pyramidTax = fromIntegral (sum (map cells rungs)) % fromIntegral (cells 64)

-- ════════════════════════════════════════════════════════════════
-- § 3. THE ATTRACTOR LADDER
-- ════════════════════════════════════════════════════════════════

shellHalf :: [Int]
shellHalf = [1, 1, 2, 4, 8, 16, 32, 64]

-- | Daniel's concentrations: sixteen basins over the 256 colours.
attractors :: [Int]
attractors = shellHalf ++ reverse shellHalf

paletteSize :: Int
paletteSize = 256

-- ════════════════════════════════════════════════════════════════
-- § 4. TILING AND THE ENERGY
--
-- Proved on a side-8 scale model tiled by 2³ (64 tiles), standing
-- for 64³ tiled by 4³ (4096 tiles). The decomposition is
-- size-independent; only the counts change.
-- ════════════════════════════════════════════════════════════════

modelSide, modelTile :: Int
modelSide = 8
modelTile = 2

-- | An index cube: one palette index per cell, row-major (t,y,x).
type Cube = [Int]

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

cube :: Cube
cube = [ lcg (i * 7 + 3) `mod` 6 | i <- [0 .. modelSide ^ (3 :: Int) - 1] ]

idx :: Int -> (Int, Int, Int) -> Int
idx n (t, y, x) = t * n * n + y * n + x

cellAt :: Cube -> (Int, Int, Int) -> Int
cellAt c p = c !! idx modelSide p

coords :: Int -> [(Int, Int, Int)]
coords n = [ (t, y, x) | t <- [0 .. n-1], y <- [0 .. n-1], x <- [0 .. n-1] ]

-- | Every ordered adjacent pair in the cube (open boundary, three
--   axes — TIME included).
bonds :: [((Int, Int, Int), (Int, Int, Int))]
bonds =
  [ (p, q)
  | p@(t, y, x) <- coords modelSide
  , q <- [ (t+1, y, x), (t, y+1, x), (t, y, x+1) ]
  , inRange q ]
  where inRange (t, y, x) = all (\v -> v >= 0 && v < modelSide) [t, y, x]

-- | ★ Additivity is WEIGHT-INDEPENDENT. The tightness law holds for
--   ANY bond cost, so this file states it generically and leaves
--   the correct cost to PhaseTiling.hs, which computes it in OKLab
--   as ΔE² — and proves (PD2) that a colourblind index count is a
--   DIFFERENT answer, not an approximation of it.
type BondWeight = Int -> Int -> Q

energyWith :: BondWeight -> Cube -> [((Int, Int, Int), (Int, Int, Int))] -> Q
energyWith w c bs = sum [ w (cellAt c p) (cellAt c q) | (p, q) <- bs ]

-- | Two unrelated weights, used only to show the law does not
--   depend on which one is chosen.
wallCount, spread :: BondWeight
wallCount i j = if i == j then 0 else 1
spread    i j = fromIntegral ((i - j) * (i - j)) % 1

-- | Which tile a cell belongs to.
tileOf :: (Int, Int, Int) -> (Int, Int, Int)
tileOf (t, y, x) = (t `div` modelTile, y `div` modelTile, x `div` modelTile)

tiles :: [(Int, Int, Int)]
tiles = coords (modelSide `div` modelTile)

cellsOfTile :: (Int, Int, Int) -> [(Int, Int, Int)]
cellsOfTile (tb, yb, xb) =
  [ (tb * modelTile + dt, yb * modelTile + dy, xb * modelTile + dx)
  | dt <- [0 .. modelTile-1], dy <- [0 .. modelTile-1], dx <- [0 .. modelTile-1] ]

-- | Bonds wholly inside one tile, and bonds crossing between tiles.
interiorBonds, wallBonds :: [((Int, Int, Int), (Int, Int, Int))]
interiorBonds = [ b | b@(p, q) <- bonds, tileOf p == tileOf q ]
wallBonds     = [ b | b@(p, q) <- bonds, tileOf p /= tileOf q ]

-- | The per-tile interior energy — the tile-local quantity.
tileEnergy :: BondWeight -> Cube -> (Int, Int, Int) -> Q
tileEnergy w c tl =
  energyWith w c [ b | b@(p, q) <- interiorBonds
                 , tileOf p == tl, tileOf q == tl ]

-- ════════════════════════════════════════════════════════════════
-- § 5. THE SAMPLER INTERFACE
--
-- The corpus is a PROGRAM (NO-CAPTURE-TRAINING). What it must emit
-- is exactly this signature — so synthetic and real data are the
-- same type, not merely similar.
-- ════════════════════════════════════════════════════════════════

type Sample = (Q, Q, Q, Q)   -- (r, g, b, depth), all in [0,1]

type Feed = Int -> (Int, Int, Int) -> Sample   -- rung → cell → sample

-- | A deterministic synthetic feed: the shape a sampler must have.
syntheticFeed :: Feed
syntheticFeed side (t, y, x) =
  ( fromIntegral (h 1) % 256, fromIntegral (h 2) % 256
  , fromIntegral (h 3) % 256, fromIntegral (h 4) % 256 )
  where
    h k = lcg (side * 7919 + idx side (t, y, x) * 31 + k) `mod` 256

-- | Totality: a feed must answer for every cell of every rung.
feedTotal :: Feed -> Int -> Bool
feedTotal f side =
  all (\p -> inUnit (f side p)) (coords side)
  where inUnit (r, g, b, d) = all (\v -> v >= 0 && v <= 1) [r, g, b, d]

-- ════════════════════════════════════════════════════════════════
-- § 6. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (FC1) ★ THE RATE LAW. side × delay = 320 cs at every rung: the
--       loop duration is invariant and the rung sets the rate.
--       20 / 10 / 5 Hz — and 5 Hz is DyadPreview's existing slow
--       cadence, which was the rung-16 rate all along.
axiom_FC1 :: Bool
axiom_FC1 =
     all (\s -> s * delayCs s == loopCs) rungs
  && map delayCs rungs == [5, 10, 20]
  && map rateHz rungs == [20, 10, 5]
  && loopCs == 320
  && all (\s -> loopCs `mod` s == 0) rungs      -- integer delays

-- (FC2) κ halves time exactly as it halves space: the frame count
--       IS the side, so a rung is a rate, not just a resolution.
axiom_FC2 :: Bool
axiom_FC2 =
     all (\s -> frames s == s) rungs
  && and (zipWith (\a b -> frames a == 2 * frames b) rungs (tail rungs))
  && all (\s -> cells s == s * s * s) rungs
  && cells 64 == 262144 && cells 32 == 32768 && cells 16 == 4096

-- (FC3) The feed arrives as RGB+depth; the FORMAT is OKLab+depth,
--       converted once at compression. Depth is carried,
--       never derived — it is the only boundary evidence there is.
axiom_FC3 :: Bool
axiom_FC3 =
     channels == [L, A, B, D]
  && length channels == 4
  && D `elem` channels
  && all (\s -> values s == 4 * cells s) rungs
  && bytesPerCell == 5

-- (FC4) ★ THE PYRAMID TAX. Each κ step costs 1/8 of the rung above,
--       so all three rungs cost 73/64 of the finest — 14%.
axiom_FC4 :: Bool
axiom_FC4 =
     pyramidTax == 73 % 64
  && pyramidTax < 115 % 100
  && cells 32 * 8 == cells 64
  && cells 16 * 8 == cells 32
  && sum (map cells rungs) == 299008

-- (FC5) ★ CHEAPER THAN TODAY. The whole three-rung pyramid at
--       honest typing is smaller than the single rung the app
--       retains now in fp32 — because fp32 currently holds values
--       that are exactly k/255.
axiom_FC5 :: Bool
axiom_FC5 =
     pyramidBytes < todayBytes
  && todayBytes == 4194304                     -- 4.00 MiB
  && pyramidBytes == 1495040                   -- 1.43 MiB
  && todayBytes > 2 * pyramidBytes             -- more than 2× over
  && bytesAt 64 < todayBytes                   -- even the fine rung

-- (FC6) Depth carries the boundary, and pooling BIASES it: κ
--       preserves the mean exactly but shrinks the variance, so a
--       coarse-rung mixture fit is over-confident until τ-lifted.
--       The axiom pins the direction of the bias so the port
--       cannot get the sign wrong.
axiom_FC6 :: Bool
axiom_FC6 =
     meanPreserved
  && varianceShrinks
  && D `elem` channels
  where
    field   = [ fromIntegral (lcg (i * 13 + 1) `mod` 1000) % 1000
              | i <- [0 .. 63] ] :: [Q]
    pooled  = [ sum blk / 8 | blk <- chunk 8 field ]
    mean xs = sum xs / fromIntegral (length xs)
    var xs  = let m = mean xs
              in sum [ (v - m) * (v - m) | v <- xs ] / fromIntegral (length xs)
    meanPreserved   = mean pooled == mean field
    varianceShrinks = var pooled < var field
    chunk _ [] = []
    chunk n xs = take n xs : chunk n (drop n xs)

-- (FC7) ★ THE ATTRACTOR LADDER: sixteen basins over 256 colours,
--       σ-symmetric, doubling through the middle, and CONCENTRATED
--       — the two largest basins hold half the palette.
axiom_FC7 :: Bool
axiom_FC7 =
     attractors == [1,1,2,4,8,16,32,64,64,32,16,8,4,2,1,1]
  && sum attractors == paletteSize
  && length attractors == 16
  && attractors == reverse attractors
  && maximum attractors == 64
  && sum (take 2 (reverse (sort attractors))) == paletteSize `div` 2
  && and (zipWith (\a b -> b == 2 * a) (drop 1 shellHalf) (drop 2 shellHalf))
  && sum shellHalf == paletteSize `div` 2

-- (FC8) The 64³ tiles EXACTLY by 4³ — 4096 tiles, no remainder —
--       and the model tiles the same way at its own scale.
axiom_FC8 :: Bool
axiom_FC8 =
     64 `mod` 4 == 0
  && (64 `div` 4) ^ (3 :: Int) == 4096
  && cells 64 == 4096 * (4 ^ (3 :: Int))
  && length tiles == (modelSide `div` modelTile) ^ (3 :: Int)
  && sort (concatMap cellsOfTile tiles) == sort (coords modelSide)
  && length (nub (concatMap cellsOfTile tiles)) == cells modelSide

-- (FC9) ★ TIGHTNESS. The configuration energy decomposes EXACTLY
--       into per-tile interiors plus the walls between tiles. So a
--       phase can be computed tile-local, and ONE tile can be
--       re-solved without recomputing the cube — which is what
--       makes a full re-solve per tick affordable.
axiom_FC9 :: Bool
axiom_FC9 =
     all decomposes [wallCount, spread]
  && length interiorBonds + length wallBonds == length bonds
  && null [ b | b <- interiorBonds, b `elem` wallBonds ]
  where
    decomposes w =
         energyWith w cube bonds
           == sum (map (tileEnergy w cube) tiles) + energyWith w cube wallBonds
      && sum (map (tileEnergy w cube) tiles) == energyWith w cube interiorBonds

-- (FC10) ★ THE SAMPLER INTERFACE. The compressed format is a TOTAL
--        function (rung, cell) → (rgb, depth). A synthetic corpus
--        is exactly a term of that type — so synthetic and real
--        data are the SAME TYPE, not merely similar. That identity
--        is what NO-CAPTURE-TRAINING needs to be sound.
axiom_FC10 :: Bool
axiom_FC10 =
     all (feedTotal syntheticFeed) [4, 8]
  && syntheticFeed 8 (0, 0, 0) == syntheticFeed 8 (0, 0, 0)   -- pure
  && syntheticFeed 8 (0, 0, 0) /= syntheticFeed 16 (0, 0, 0)  -- rung
  && length (nub [ syntheticFeed 8 p | p <- take 32 (coords 8) ]) > 1
  && (let (r, g, b, d) = syntheticFeed 8 (1, 2, 3)
      in all (\v -> v >= 0 && v <= 1) [r, g, b, d])

-- ════════════════════════════════════════════════════════════════
-- § 7. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " FeedCompression: feed RGB+depth → OKLab+depth, 3 rates"
  putStrLn " the loop is the invariant; the rung sets the rate"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── The rungs ──"
  putStrLn ""
  putStrLn "  rung │ frames │ delay │  rate  │    cells │    bytes"
  putStrLn "  ─────┼────────┼───────┼────────┼──────────┼─────────"
  mapM_ row rungs
  putStrLn "  ─────┼────────┼───────┼────────┼──────────┼─────────"
  putStrLn $ "  all  │        │       │        │ "
           ++ padL 8 (show (sum (map cells rungs))) ++ " │ "
           ++ padL 8 (show pyramidBytes)
  putStrLn ""
  putStrLn $ "  pyramid tax   : " ++ show (numerator pyramidTax) ++ "/"
           ++ show (denominator pyramidTax)
           ++ "  (all three rungs for 14% over the finest)"
  putStrLn $ "  today retains : " ++ show todayBytes
           ++ " B in ONE rung (fp32 triples)"
  putStrLn $ "  ★ the pyramid is " ++ show (todayBytes `div` pyramidBytes)
           ++ "× SMALLER than what ships now"
  putStrLn ""

  putStrLn "── The attractors (colour concentrations) ──"
  putStrLn ""
  putStrLn $ "  " ++ unwords (map show attractors)
  putStrLn $ "  16 basins, " ++ show (sum attractors)
           ++ " colours, σ-symmetric; the two largest hold "
           ++ show (sum (take 2 (reverse (sort attractors))))
           ++ " — half the palette"
  putStrLn ""

  putStrLn "── Tiling ──"
  putStrLn ""
  putStrLn $ "  64³ by 4³ : " ++ show ((64 `div` 4) ^ (3 :: Int))
           ++ " tiles, exact partition"
  putStrLn $ "  energy    : Σ tile interiors + walls (additive, FC9)"
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "FC1  ★ rate law: side × delay = 320 cs; 20/10/5 Hz"       [axiom_FC1]
  check "FC2  frames = side: κ halves time as it halves space"     [axiom_FC2]
  check "FC3  payload is OKLab+depth at every rung, 4 channels"      [axiom_FC3]
  check "FC4  ★ pyramid tax is exactly 73/64 — three rungs for 14%"[axiom_FC4]
  check "FC5  ★ the pyramid is SMALLER than today's single rung"   [axiom_FC5]
  check "FC6  depth is the boundary; pooling shrinks its variance" [axiom_FC6]
  check "FC7  ★ attractors: 16 basins, 256 colours, σ-symmetric"   [axiom_FC7]
  check "FC8  64³ tiles exactly by 4³ — 4096 tiles, no remainder"  [axiom_FC8]
  check "FC9  ★ TIGHTNESS: energy = Σ tiles + walls, exactly"      [axiom_FC9]
  check "FC10 ★ sampler interface: synthetic ≡ real, same type"    [axiom_FC10]
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  A rung is a RATE, not a resolution. κ halves time with"
  putStrLn "  space, so 64³ is 64 frames at 20 Hz, 32³ is 32 at 10,"
  putStrLn "  16³ is 16 at 5 — and the loop stays 3.2 s throughout."
  putStrLn "  The app already runs its slow state at exactly the"
  putStrLn "  rung-16 rate and calls it a preview cadence."
  putStrLn ""
  putStrLn "  Carrying all three costs 73/64 of the finest alone,"
  putStrLn "  and the whole pyramid at honest typing is smaller than"
  putStrLn "  the single rung retained today. Compression here is"
  putStrLn "  not a cost. It is a refund."
  putStrLn ""
  putStrLn "  The format is a total function (rung, cell) → (rgb, d)."
  putStrLn "  A synthetic corpus is a TERM OF THAT TYPE — which is"
  putStrLn "  what makes training without captured data sound."
  putStrLn "══════════════════════════════════════════════════════════"

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

row :: Int -> IO ()
row s = putStrLn $
     "  " ++ padL 4 (show s)
  ++ " │ " ++ padL 6 (show (frames s))
  ++ " │ " ++ padL 5 (show (delayCs s))
  ++ " │ " ++ padL 5 (show (truncate (rateHz s) :: Integer)) ++ " Hz"
  ++ " │ " ++ padL 8 (show (cells s))
  ++ " │ " ++ padL 8 (show (bytesAt s))

check :: String -> [Bool] -> IO ()
check name results =
  let passed = and results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
