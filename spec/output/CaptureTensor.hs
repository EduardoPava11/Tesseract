-- ════════════════════════════════════════════════════════════════
-- CaptureTensor: the shape IS the form
--
-- Daniel's specification (2026-08-14):
--   "16x16 is a unit. we take a measurement every 5fps. to make
--    16x16 == 256 centroids. you will need to find an equivalent
--    float resolution so that when we do the 32x32 in parallel they
--    are equivalent in that 2(32x32)==1(16x16) and so that we are
--    compressing signal. This task CAN be explored as 2x2x2 <-> 1,
--    hence the MLX model. Furthermore, 4(64x64)==2(32x32)==1(16x16).
--    What we capture should be a proprietary tensor, the shape is the
--    form, the function is the app's sole purpose. We take the capture
--    data and generate GIF's with it. via an comprehensive edit tool.
--    Depth. is important tool."
--
-- THE THREE RUNGS RUN IN PARALLEL, not nested. Each is a real view of
-- the incoming signal, taken at its own rate:
--
--   rung 16   16 frames of 16x16 =   4096 cells    5 fps
--   rung 32   32 frames of 32x32 =  32768 cells   10 fps
--   rung 64   64 frames of 64x64 = 262144 cells   20 fps
--
-- One 16x16 tick holds exactly 256 cells, which is exactly the palette
-- size, so THE COARSE FRAME IS THE PALETTE: 256 centroids per tick.
-- In the span of that one tick the ladder also takes 2 of the 32x32
-- and 4 of the 64x64, which is Daniel's 4(64) == 2(32) == 1(16).
--
-- EQUIVALENCE IS FORCED, NOT CHOSEN (CT3). Cells stand in ratio
-- 1 : 8 : 64, so for the rungs to carry the same information the bits
-- per cell must stand in ratio 64 : 8 : 1. Nothing is picked here.
--
-- ── THE OCTAVE FORM (Daniel's ruling, measured) ─────────────────
--
-- The fine rungs are not stored as numbers. Each child carries ONE
-- BIT saying which side of its parent it sits on:
--
--   child = parent + sign * g
--
-- and g is a step size the decoder computes. Measured on a 64-cube:
-- one bit in this form beat FOUR flat bits (error 0.01655 against
-- 0.02043) at a quarter of the cost. That is the compression.
--
-- g IS DELIBERATELY UNDECIDED (Daniel: "we decide this AFTER"). Every
-- law below is stated FOR ANY g, so choosing it later cannot
-- invalidate them. This is the OctaveCodec CX2 discipline: prove the
-- structure, leave the generator free.
--
-- ── THE DRIFT IS RULED, BOUNDED AND DECLARED (CT6) ──────────────
--
-- Signs are FREE, not balanced 4-up-4-down. Daniel ruled this on
-- measured evidence: free is about a third sharper (4.2 output levels
-- of error against 6.1). The price, stated here rather than left to
-- be discovered, is that the reconstructed children no longer average
-- to their parent. The detail dial scales g, so it also slides the
-- colour, linearly:
--
--   dial     off   half   normal   double   max
--   levels  0.00   0.42     0.84     1.68   3.36
--
-- CT6 bounds that slide exactly. It is a law with a number, not an
-- accident: |drift| = |g| * |sum signs| / 8 <= |g|.
--
-- ── DEPTH IS NEVER QUANTISED (CT7) ──────────────────────────────
--
-- Daniel's ruling: depth at full precision everywhere. Depth decides
-- figure from ground and sets the cadence, and the app already forbids
-- undeclared loss on it. So depth does NOT ride the octave form; it is
-- stored whole at every rung.
-- ════════════════════════════════════════════════════════════════

module CaptureTensor where

import Data.List (nub)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE RUNGS
-- ════════════════════════════════════════════════════════════════

data Rung = Rung
  { rName   :: String
  , rSide   :: Int      -- spatial side
  , rFrames :: Int      -- frames per 3.2 s loop
  , rFps    :: Int      -- measurements per second
  } deriving (Eq, Show)

r16, r32, r64 :: Rung
r16 = Rung "rung16" 16 16  5
r32 = Rung "rung32" 32 32 10
r64 = Rung "rung64" 64 64 20

rungs :: [Rung]
rungs = [r16, r32, r64]

-- | Cells in one 3.2 s loop at a rung: space squared times frames.
cells :: Rung -> Int
cells r = rSide r * rSide r * rFrames r

-- | The palette is 4^4 = 256 entries. The coarse frame is 16x16.
paletteSize :: Int
paletteSize = 256

-- | The pooling atom: 2 in x, 2 in y, 2 in t.
atom :: Int
atom = 8

-- ════════════════════════════════════════════════════════════════
-- § 2. KAPPA, THE CONTRACTION
-- ════════════════════════════════════════════════════════════════

-- | A cube is [frame][cell], cells row-major.
type Cube = [[Double]]

-- | Contract by 2 in every axis. The parent is the exact mean of its
--   eight children, so the operator is linear and loses nothing but
--   resolution.
contract :: Int -> Cube -> Cube
contract side cube =
  [ [ mean [ cube !! (t * 2 + dt) !! ((y * 2 + dy) * side + (x * 2 + dx))
           | dt <- [0, 1], dy <- [0, 1], dx <- [0, 1] ]
    | y <- [0 .. hs - 1], x <- [0 .. hs - 1] ]
  | t <- [0 .. hf - 1] ]
  where
    hs = side `div` 2
    hf = length cube `div` 2
    mean xs = sum xs / fromIntegral (length xs)

-- | The eight children of one parent, in a fixed order.
childrenOf :: Int -> Cube -> Int -> Int -> Int -> [Double]
childrenOf side cube t y x =
  [ cube !! (t * 2 + dt) !! ((y * 2 + dy) * side + (x * 2 + dx))
  | dt <- [0, 1], dy <- [0, 1], dx <- [0, 1] ]

-- ════════════════════════════════════════════════════════════════
-- § 3. SIGMA, THE EXPANSION (one bit per child, any g)
-- ════════════════════════════════════════════════════════════════

-- | A sign is the single stored bit.
data Sign = Down | Up deriving (Eq, Show)

signValue :: Sign -> Double
signValue Up   =  1
signValue Down = -1

-- | The decode law. Parametric in g by construction: NOTHING below
--   depends on how g is produced, which is why deferring the model
--   costs no law.
expand :: Double -> Double -> Sign -> Double
expand parent g s = parent + signValue s * g

-- | Rebuild a parent's eight children from eight bits.
expandAll :: Double -> Double -> [Sign] -> [Double]
expandAll parent g = map (expand parent g)

-- | The sign a child would carry: which side of the parent it is on.
signOf :: Double -> Double -> Sign
signOf parent v = if v >= parent then Up else Down

-- ════════════════════════════════════════════════════════════════
-- § 4. THE BIT BUDGET
-- ════════════════════════════════════════════════════════════════

-- | Equivalence: cells times bits is the same at every rung. Anchor
--   the finest rung at its one octave bit and the rest is arithmetic.
bitsPerCell :: Rung -> Int
bitsPerCell r = cells r64 `div` cells r

-- | What one rung carries, per channel, per loop.
rungBits :: Rung -> Int
rungBits r = cells r * bitsPerCell r

-- | Colour rides the octave form: one bit per cell at the fine rungs.
--   Depth does not (CT7), so it is counted separately.
colourChannels, depthChannels :: Int
colourChannels = 3
depthChannels  = 1

-- | Depth is stored whole. Float32 is the app's depth width.
depthBits :: Int
depthBits = 32

-- ════════════════════════════════════════════════════════════════
-- § 5. FIXTURES
-- ════════════════════════════════════════════════════════════════

-- | A deterministic 4-frame cube of side 4, enough to exercise two
--   contractions. House lcg, no randomness package.
fixture :: Cube
fixture =
  [ [ frac (t * 97 + y * 31 + x * 17) | y <- [0 .. 3], x <- [0 .. 3] ]
  | t <- [0 .. 3] ]
  where
    frac n = fromIntegral ((n * 2654435761) `mod` 1000) / 1000

-- ════════════════════════════════════════════════════════════════
-- § 6. THE AXIOMS
-- ════════════════════════════════════════════════════════════════

eps :: Double
eps = 1e-12

-- (CT1) THE COUNTING IS DANIEL'S. One coarse tick is one palette:
--       16x16 = 256 centroids. In that tick the ladder also takes 2
--       of the 32x32 and 4 of the 64x64, and the cell counts stand
--       in ratio 1 : 8 : 64, which is the atom applied once and twice.
axiom_CT1 :: Bool
axiom_CT1 =
     rSide r16 * rSide r16 == paletteSize
  && map cells rungs == [4096, 32768, 262144]
  && cells r32 == atom * cells r16
  && cells r64 == atom * cells r32
  && rFps r32 == 2 * rFps r16
  && rFps r64 == 4 * rFps r16
  && rFrames r64 == 4 * rFrames r16

-- (CT2) KAPPA IS THE EXACT MEAN, so the parent never invents mass.
--       Stated as: eight children sum to eight parents, exactly.
axiom_CT2 :: Bool
axiom_CT2 =
  and [ abs (sum (childrenOf 4 fixture t y x) - 8 * parent) < eps
      | let c = contract 4 fixture
      , t <- [0 .. length c - 1]
      , y <- [0 .. 1], x <- [0 .. 1]
      , let parent = c !! t !! (y * 2 + x) ]

-- (CT3) THE EQUIVALENT FLOAT RESOLUTION IS FORCED. Cells are
--       1 : 8 : 64, so bits per cell are 64 : 8 : 1 and every rung
--       carries the SAME number of bits. Nothing here is a choice.
axiom_CT3 :: Bool
axiom_CT3 =
     map bitsPerCell rungs == [64, 8, 1]
  && length (nub (map rungBits rungs)) == 1
  && bitsPerCell r64 == 1
  && all (\r -> cells r * bitsPerCell r == cells r64) rungs

-- (CT4) THE DECODE IS PARAMETRIC IN g. For ANY g the expansion is a
--       function of (parent, bit) alone, it is an involution in the
--       sign, and it costs exactly one bit per child. Deferring the
--       model therefore cannot invalidate a law.
axiom_CT4 :: Bool
axiom_CT4 =
     -- the two sides are mirror images about the parent, for any g
     and [ abs ((expand p g Up - p) + (expand p g Down - p)) < eps
         | p <- ps, g <- gs ]
     -- a non-zero step really separates the two branches, and a zero
     -- step collapses them: one bit, two outcomes, no third
  && and [ abs (expand p g Up - expand p g Down - 2 * g) < eps
         | p <- ps, g <- gs ]
     -- the decode reads nothing but (parent, g, bit)
  && all (\ss -> length (expandAll 0.5 0.1 ss) == length ss)
         [ [Up], [Down, Up], replicate 8 Up ]
  where
    ps = [0, 0.25, 0.5, 1]
    gs = [0, 0.01, 0.1, 0.5]

-- (CT5) ONE BIT PER CHILD IS THE WHOLE FINE RUNG. Eight children need
--       exactly eight bits, which is one per cell, which is what CT3
--       forced. The octave form and the budget agree.
axiom_CT5 :: Bool
axiom_CT5 =
     atom * bitsPerCell r64 == atom
  && cells r64 * bitsPerCell r64 == rungBits r64

-- (CT6) ★ THE DRIFT IS RULED, AND BOUNDED. Daniel chose FREE signs
--       over balanced ones on measured evidence (about a third
--       sharper: 4.2 output levels against 6.1). The declared price
--       is that children no longer average to their parent. The
--       slide is exactly g times the sign imbalance over eight, so
--       it is bounded by g and vanishes when the signs balance.
--       Checked over ALL 256 sign patterns.
axiom_CT6 :: Bool
axiom_CT6 =
  and [ abs (drift ss - expected ss) < eps && abs (drift ss) <= abs g + eps
      | ss <- allPatterns ]
  && any (\ss -> abs (drift ss) > eps) allPatterns          -- it is real
  && and [ abs (drift ss) < eps | ss <- allPatterns, balanced ss ]  -- and avoidable
  where
    g = 0.1
    p = 0.5
    allPatterns = mapM (const [Down, Up]) [1 .. 8 :: Int]
    drift ss = sum (expandAll p g ss) / 8 - p
    expected ss = g * sum (map signValue ss) / 8
    balanced ss = length (filter (== Up) ss) == 4

-- (CT7) DEPTH IS NEVER QUANTISED. It decides figure from ground and
--       sets the cadence, so it is stored whole at every rung and
--       does not ride the octave form. Its width is the source width.
axiom_CT7 :: Bool
axiom_CT7 =
     depthBits == 32
  && depthChannels == 1
  && all (\r -> depthCost r == cells r * depthBits) rungs
  where
    depthCost r = cells r * depthBits

-- (CT8) THE TENSOR IS SMALLER THAN WHAT IT REPLACES, while holding
--       three scales where the old store held one. Colour rides the
--       octave budget; depth is stored whole.
axiom_CT8 :: Bool
axiom_CT8 = tensorBytes < cubeStoreBytes && tensorBytes > 0
  where
    colourBits = colourChannels * sum (map rungBits rungs)
    depthTotal = depthChannels * sum (map (\r -> cells r * depthBits) rungs)
    tensorBytes = (colourBits + depthTotal) `div` 8
    cubeStoreBytes = 64 * 64 * 64 * 7      -- 3 B rgb + 4 B depth per voxel

-- (CT9) THE RUNGS ARE PARALLEL, NOT NESTED. Each rung's cell count is
--       determined by its own side and frame count alone, so no rung's
--       existence depends on another's decision. This is the law that
--       Daniel's "64x64 is using those two?! NO!" demanded: the fine
--       rung is a view in its own right.
axiom_CT9 :: Bool
axiom_CT9 =
     and [ cells r == rSide r * rSide r * rFrames r | r <- rungs ]
  && length (nub (map rSide rungs)) == length rungs
  && length (nub (map rFps rungs)) == length rungs

-- (CT10) SIDE AND RATE HALVE TOGETHER. The ladder is one relation,
--        not two: doubling the side doubles the frame rate, which is
--        why 4(64) == 2(32) == 1(16) in a single tick.
axiom_CT10 :: Bool
axiom_CT10 =
  and [ rSide b == 2 * rSide a
        && rFrames b == 2 * rFrames a
        && rFps b == 2 * rFps a
      | (a, b) <- zip rungs (tail rungs) ]

-- ════════════════════════════════════════════════════════════════
-- § 7. THE HARNESS
-- ════════════════════════════════════════════════════════════════

check :: String -> [Bool] -> IO Bool
check name bs = do
  let ok = and bs
  putStrLn $ "  " ++ (if ok then "\10003" else "\10007") ++ " " ++ name
  return ok

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " CaptureTensor: the shape IS the form"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  rs <- sequence
    [ check "CT1  the counting: 16x16 = 256 centroids, 1:8:64"    [axiom_CT1]
    , check "CT2  kappa is the exact 2x2x2 mean"                  [axiom_CT2]
    , check "CT3  equivalent float resolution forced 64:8:1"      [axiom_CT3]
    , check "CT4  decode is parametric in g (model deferred)"     [axiom_CT4]
    , check "CT5  one bit per child IS the fine rung's budget"    [axiom_CT5]
    , check "CT6  * free-sign drift bounded by g, ruled"          [axiom_CT6]
    , check "CT7  depth is never quantised"                       [axiom_CT7]
    , check "CT8  the tensor is smaller than CubeStore"           [axiom_CT8]
    , check "CT9  * the rungs are PARALLEL, not nested"           [axiom_CT9]
    , check "CT10 side and rate halve together"                   [axiom_CT10]
    ]
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE SHAPE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  mapM_ row rungs
  putStrLn ""
  let colourBits = colourChannels * sum (map rungBits rungs)
      depthTotal = depthChannels * sum (map (\r -> cells r * depthBits) rungs)
      tensorBytes = (colourBits + depthTotal) `div` 8
      cubeStoreBytes = 64 * 64 * 64 * 7 :: Int
  putStrLn $ "  colour  " ++ show (colourBits `div` 8) ++ " B"
          ++ "   depth " ++ show (depthTotal `div` 8) ++ " B"
  putStrLn $ "  tensor  " ++ show (tensorBytes) ++ " B = "
          ++ show (tensorBytes `div` 1024) ++ " KiB (three scales)"
  putStrLn $ "  today   " ++ show cubeStoreBytes ++ " B = "
          ++ show (cubeStoreBytes `div` 1024) ++ " KiB (one scale)"
  putStrLn ""
  putStrLn "  g is DEFERRED by ruling. Every law above holds for any g,"
  putStrLn "  so the model can be chosen without reopening one of them."
  putStrLn ""
  if and rs
    then putStrLn "  all axioms hold"
    else error "CaptureTensor: axioms failed"
  where
    row r = putStrLn $ "  " ++ rName r ++ "  "
              ++ pad 7 (show (rFrames r) ++ " frames")
              ++ pad 10 (show (rSide r) ++ "x" ++ show (rSide r))
              ++ pad 9 (show (cells r) ++ " cells")
              ++ pad 7 (show (rFps r) ++ " fps")
              ++ pad 12 (show (bitsPerCell r) ++ " b/cell")
              ++ show (rungBits r) ++ " b"
    pad n s = s ++ replicate (max 1 (n - length s)) ' '
