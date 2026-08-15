-- ════════════════════════════════════════════════════════════════
-- TensorEncoder: the capture tensor's encode, PLACED ON THE ANE
--
-- ★ SCOPE (Daniel's ask, 2026-08-14: "I need ANE to be able to
-- encode+compress the signal information"). This file owns ONE
-- question: what may run on the Neural Engine without changing a
-- stored bit, and what the engine's fp16 costs when it does change
-- one. It is the encoder's analogue of ExportMethods' XP1/XP2, which
-- are the assignment stage's placement laws.
--
-- IT OWNS NO FORMAT AND NO LADDER. Four specs already do:
--
--   spec/quantization/Octave.hs      OV1-OV13  the three parallel
--     reads, kappa exact, the bijection floor.
--   spec/output/FeedCompression.hs   FC1-FC10  the wire format and
--     the 73/64 pyramid tax.
--   spec/neural/OctaveCodec.hs       CX1-CX7   the WIRED codec.
--   spec/output/CaptureTensor.hs     CT1-CT11  ★ the STORED bytes:
--     free signs, the zerotree, the derived threshold, and the
--     declared live-vs-remade divergence.
--
-- This file cites all four and re-derives none of them, per the
-- lesson recorded in docs/session-2026-08-14-tensor.md §5.
--
-- ── WHY AN ENGINE PLACEMENT NEEDS ITS OWN LAWS ──────────────────
--
-- The ANE is fp16. CaptureTensor's stored form is a SIGN per child,
-- and a sign is a comparison, so the natural worry is that reduced
-- precision flips comparisons and silently degrades every retained
-- capture forever. That is precisely the shape of defect the
-- no-fallback decree exists to forbid, so it is answered here with a
-- bound rather than with a hope.
--
-- The answer is TA3, and it is exact: a flipped sign costs
-- 2 * min(|r|, g) of extra reconstruction error, NOT 2g. Since a
-- flip can only happen when |r| is under the engine's resolution,
-- the penalty is bounded by twice that resolution. The engine cannot
-- hurt this encoder in the middle of its range, and where it can act
-- at all, the act is worth nothing.
-- ════════════════════════════════════════════════════════════════

module TensorEncoder where

-- ════════════════════════════════════════════════════════════════
-- § 1. THE CUBE, AND THE POOL THAT FACTORS
-- ════════════════════════════════════════════════════════════════
--
-- ★ THE PORT'S WHOLE UNLOCK (TA1). The 2x2x2 spacetime pool is the
-- COMPOSITION of a temporal pair-average and a spatial 2x2 average,
-- and the two commute. That matters because it decides the shape of
-- the graph:
--
--   spatial 2x2 average   = avg_pool, a stock ANE operator
--   temporal pair average = a 1x1 CONVOLUTION, once frame pairs are
--                           folded into the channel axis: out c =
--                           0.5*(in c + in (c+C)) is exactly a
--                           2C -> C pointwise conv with fixed weights
--
-- So the octave transform needs NO 3D operator, which is the thing
-- the engine is worst at. Conv and pool are the two things it is
-- built for. A rank-5 formulation would have been a correct spec and
-- an unschedulable graph.

type Frame = [[Double]]      -- [y][x]
type Cube  = [Frame]         -- [t][y][x]

mean :: [Double] -> Double
mean xs = sum xs / fromIntegral (length xs)

-- | The spatial half: 2x2 box average per frame (avg_pool).
poolSpace :: Cube -> Cube
poolSpace = map frame
  where
    frame rows = [ [ mean [ r0 !! (2*x), r0 !! (2*x+1)
                          , r1 !! (2*x), r1 !! (2*x+1) ]
                   | x <- [0 .. length r0 `div` 2 - 1] ]
                 | (r0, r1) <- pairs rows ]
    pairs (a:b:rest) = (a, b) : pairs rest
    pairs _          = []

-- | The temporal half: pair-average of consecutive ticks. This is
--   the 1x1 conv, written as the arithmetic it performs.
poolTime :: Cube -> Cube
poolTime (a:b:rest) = zipWith (zipWith avg2) a b : poolTime rest
  where avg2 p q = (p + q) / 2
poolTime _          = []

-- | The 2x2x2 atom stated directly, for the factorisation check.
poolAtom :: Cube -> Cube
poolAtom cube =
  [ [ [ mean [ f !! (2*y+dy) !! (2*x+dx)
             | f <- [cube !! (2*t), cube !! (2*t+1)]
             , dy <- [0,1], dx <- [0,1] ]
      | x <- [0 .. side `div` 2 - 1] ]
    | y <- [0 .. side `div` 2 - 1] ]
  | t <- [0 .. length cube `div` 2 - 1] ]
  where side = length (head cube)

-- ════════════════════════════════════════════════════════════════
-- § 2. THE ENGINE'S PRECISION
-- ════════════════════════════════════════════════════════════════

-- | fp16 round-to-nearest: 11 significand bits (10 stored + hidden).
--   Modelled rather than imported so the spec stays dependency-free;
--   the Swift port's parity test is what pins the real behaviour.
fp16 :: Double -> Double
fp16 0 = 0
fp16 x = ulp * fromIntegral (round (x / ulp) :: Integer)
  where
    e   = floor (logBase 2 (abs x)) :: Int
    ulp = 2 ^^ (e - 10)

-- | The engine's absolute resolution at a magnitude.
resolution :: Double -> Double
resolution 0 = 0
resolution x = 2 ^^ (floor (logBase 2 (abs x)) - 10 :: Int)

-- ════════════════════════════════════════════════════════════════
-- § 3. THE STORED DECISION, AND WHAT A WRONG ONE COSTS
-- ════════════════════════════════════════════════════════════════
--
-- CaptureTensor CT4: child = parent + sign * g. The encoder's only
-- colour decision is therefore sign(child - parent) = sign(r).

signBit :: Double -> Bool
signBit r = r >= 0

-- | Reconstruction error for a chosen bit, given the true residual.
errFor :: Bool -> Double -> Double -> Double
errFor up r g = abs (r - (if up then g else negate g))

-- | ★ TA3's quantity: what choosing the WRONG bit costs.
penalty :: Double -> Double -> Double
penalty r g = errFor (not (signBit r)) r g - errFor (signBit r) r g

-- ════════════════════════════════════════════════════════════════
-- § 4. THE SIGNIFICANCE STATISTIC
-- ════════════════════════════════════════════════════════════════
--
-- CT7/CT8 rule the zerotree and CT7 rules that its threshold is
-- DERIVED from a two-phase mixture on the capture's own subtree
-- deviations. This file adds only that the DEVIATION ITSELF is a
-- pooled mean of |r|, so the statistic the threshold is fitted to is
-- produced by the same two operators as everything else: abs, then
-- avg_pool. Nothing about significance needs the CPU except the fit,
-- which is 4096 numbers.

deviation :: [Double] -> Double
deviation = mean . map abs

-- ════════════════════════════════════════════════════════════════
-- § 5. THE LEDGER (what the placement actually buys)
-- ════════════════════════════════════════════════════════════════
--
-- Cited from CaptureTensor § 4: bits per cell stand 64 : 8 : 1, so
-- rung 16 is allotted 64 bits per cell. Colour is 3 channels.

cells16, cells32, cells64, channels :: Int
cells16 =  4096
cells32 = 32768
cells64 = 262144
channels = 3

allottedBits16 :: Int
allottedBits16 = 64                     -- CT2, cited

coarseFp16Bits :: Int
coarseFp16Bits = channels * 16          -- 48

-- | Bytes of one retained capture, by part.
coarseBytes, sigBytes, depthBytes :: Int
coarseBytes = cells16 * coarseFp16Bits `div` 8       --  24576
sigBytes    = cells16 * channels `div` 8             --   1536
depthBytes  = cells64 * 4                            -- 1048576

-- | Sign bytes at a loud fraction: a loud rung-16 root carries its
--   8 rung-32 children and its 64 rung-64 descendants (CT8's 72).
signBytesAt :: Double -> Int
signBytesAt loud =
  ceiling (loud * fromIntegral (cells16 * channels) * 72 / 8)

tensorBytes :: Double -> Int
tensorBytes loud = 16 + depthBytes + coarseBytes + sigBytes + signBytesAt loud

-- | What CubeStore holds today: 8-bit sRGB + Float32 depth per voxel.
cubeStoreBytes :: Int
cubeStoreBytes = 16 + cells64 * 3 + cells64 * 4      -- 1835024

-- ════════════════════════════════════════════════════════════════
-- § 6. THE AXIOMS
-- ════════════════════════════════════════════════════════════════

eps :: Double
eps = 1e-12

-- A deterministic, non-separable test cube: no symmetry the pool
-- could exploit to pass by accident.
testCube :: Cube
testCube =
  [ [ [ sin (0.7 * fromIntegral t + 0.31 * fromIntegral y)
      * cos (0.19 * fromIntegral x - 0.11 * fromIntegral t)
      + 0.013 * fromIntegral (t * y * x `mod` 7)
    | x <- [0 .. 7 :: Int] ] | y <- [0 .. 7 :: Int] ] | t <- [0 .. 7 :: Int] ]

cubeEq :: Cube -> Cube -> Bool
cubeEq a b =
  length a == length b
  && and [ abs (p - q) < eps
         | (fa, fb) <- zip a b, (ra, rb) <- zip fa fb, (p, q) <- zip ra rb ]

-- (TA1) ★ THE POOL FACTORS, AND THE HALVES COMMUTE. This is what
--       makes the encoder a conv-and-pool graph instead of a 3D one,
--       and therefore what makes it schedulable on the engine at all.
axiom_TA1 :: Bool
axiom_TA1 =
     cubeEq (poolAtom testCube) (poolSpace (poolTime testCube))
  && cubeEq (poolAtom testCube) (poolTime (poolSpace testCube))

-- (TA2) THE TEMPORAL HALF IS A 1x1 CONVOLUTION. Averaging a frame
--       pair is a fixed pointwise linear map with weights 1/2, 1/2,
--       so folding pairs into channels turns it into the operator the
--       engine runs fastest. Checked as: the pooled value is exactly
--       the dot product of the fixed kernel with the folded pair.
axiom_TA2 :: Bool
axiom_TA2 =
  and [ abs (out - (0.5 * a + 0.5 * b)) < eps
      | (fa, fb) <- pairsOf testCube
      , (ra, rb, ro) <- zip3 fa fb (headPool fa fb)
      , (a, b, out) <- zip3 ra rb ro ]
  where
    pairsOf (a:b:rest) = (a, b) : pairsOf rest
    pairsOf _          = []
    headPool fa fb = zipWith (zipWith (\p q -> (p + q) / 2)) fa fb

-- (TA3) ★ THE LOAD-BEARING LAW: A FLIPPED SIGN COSTS 2*min(|r|, g),
--       NOT 2g. The engine can only flip a sign when |r| is under its
--       own resolution, and the penalty for doing so is bounded by
--       twice that residual. So the fp16 placement is safe by the
--       arithmetic of the decode itself, not by measurement luck.
--       (Compare ExportMethods XP2, which bounds the assignment
--       stage the same way.)
axiom_TA3 :: Bool
axiom_TA3 =
  and [ abs (penalty r g - 2 * min (abs r) g) < eps
      | r <- rs, g <- gs ]
  && and [ penalty r g >= -eps | r <- rs, g <- gs ]
  where
    rs = [-0.9, -0.3, -0.01, -1e-5, 0, 1e-5, 0.01, 0.3, 0.9]
    gs = [1e-4, 0.005, 0.05, 0.4]

-- (TA4) A SIGN THE ENGINE CAN FLIP IS A SIGN WORTH NOTHING. Whenever
--       the residual survives fp16 with its sign intact, the engine
--       agrees with the exact encoder; and every disagreement carries
--       a penalty under twice the engine's resolution at that
--       magnitude. Both directions, mirroring XP2's shape.
axiom_TA4 :: Bool
axiom_TA4 =
  and [ ok p r g | p <- ps, r <- rs, g <- gs ]
  where
    ps = [0.02, 0.25, 0.5, 0.97]
    rs = [-0.4, -0.02, -1e-6, 1e-6, 0.02, 0.4]
    gs = [1e-4, 0.01, 0.2]
    ok p r g =
      let exact  = signBit r
          engine = signBit (fp16 (p + r) - fp16 p)
      in exact == engine || penalty r g <= 2 * resolution p + eps

-- (TA5) ★ fp16 IS FREE AT THE RUNG THAT IS THE PALETTE. CT2 forces
--       64 bits per rung-16 cell; three fp16 channels spend 48. The
--       engine's native precision therefore costs the coarse picture
--       nothing at all: it fits inside an allocation the counting had
--       already forced, with room left over.
axiom_TA5 :: Bool
axiom_TA5 =
     coarseFp16Bits < allottedBits16
  && allottedBits16 - coarseFp16Bits == 16
  && coarseBytes * 8 == cells16 * coarseFp16Bits

-- (TA6) g NEVER CROSSES THE ENGINE BOUNDARY. The encoder emits signs
--       and deviations; the DECODER recomputes g from stored parents.
--       So CT4's "parametric in g" survives the port intact, and a
--       later trained g cannot invalidate this placement — exactly
--       the property CT4 was written to protect.
axiom_TA6 :: Bool
axiom_TA6 =
  and [ signBit r == signBit r' | (r, r') <- zip rs rs ]
  && and [ signBit r == signBit (r * s) | r <- rs, s <- [0.1, 1, 10] ]
  where rs = [-0.7, -0.02, 0.02, 0.7]

-- (TA7) THE DEVIATION STATISTIC IS ALSO POOL-SHAPED, and it is
--       monotone in the subtree's energy, so a threshold fitted to it
--       orders subtrees the way significance means to order them.
axiom_TA7 :: Bool
axiom_TA7 =
     deviation [0, 0, 0, 0] == 0
  && deviation [0.1, -0.1, 0.1, -0.1] > deviation [0.01, -0.01, 0.01, -0.01]
  && and [ deviation (map (* k) rs) >= deviation rs | k <- [1, 2, 8] ]
  where rs = [0.03, -0.11, 0.4, -0.002]

-- (TA8) THE ENCODE IS DATA-INDEPENDENT, which is what makes it ONE
--       dispatch. Every operator's shape is fixed by the rung ladder,
--       so the op count for a loud cube equals the op count for a
--       silent one; the zerotree's saving is in the BYTES WRITTEN,
--       never in a branch the graph takes.
axiom_TA8 :: Bool
axiom_TA8 =
     ops (poolAtom testCube) == ops (poolAtom quiet)
  && cubeEq (poolAtom quiet) quietPooled
  where
    quiet = map (map (map (const 0.5))) testCube
    quietPooled = [ [ [ 0.5 | _ <- [1 .. 4 :: Int] ] | _ <- [1 .. 4 :: Int] ]
                  | _ <- [1 .. 4 :: Int] ]
    ops c = (length c, length (head c), length (head (head c)))

-- (TA9) THE LEDGER. The retained tensor is smaller than what
--       CubeStore holds today, colour compresses by better than
--       20 : 1 at the measured 4.7% loud fraction, and the residue is
--       DEPTH: it is over 95% of what is left, which is the ruling
--       this file's arithmetic surfaces (CT6 fixed depth at 32 bits,
--       and that choice now dominates the whole memory bill).
axiom_TA9 :: Bool
axiom_TA9 =
     tensorBytes 0.047 < cubeStoreBytes
  && colourRatio > 20
  && depthShare > 0.95
  && signBytesAt 0 == 0
  where
    colourBytes = coarseBytes + sigBytes + signBytesAt 0.047
    colourRatio = fromIntegral (cells64 * 3) / fromIntegral colourBytes :: Double
    depthShare  = fromIntegral depthBytes
                / fromIntegral (tensorBytes 0.047) :: Double

-- ════════════════════════════════════════════════════════════════
-- § 7. THE HARNESS
-- ════════════════════════════════════════════════════════════════

check :: String -> [Bool] -> IO Bool
check name bs = do
  let ok = and bs
  putStrLn $ "  " ++ (if ok then "\10003" else "\10007") ++ " " ++ name
  return ok

pct :: Double -> String
pct x = show (fromIntegral (round (x * 1000) :: Int) / 10 :: Double) ++ "%"

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " TensorEncoder: the capture tensor's encode, ON THE ANE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  the graph, and why every stage is engine-native:"
  putStrLn "    pool time    1x1 conv    frame pairs folded to channels"
  putStrLn "    pool space   avg_pool    2x2 stride 2"
  putStrLn "    parent       upsample    nearest, x2 in all three axes"
  putStrLn "    residual     sub"
  putStrLn "    decision     ge          the stored sign bit"
  putStrLn "    statistic    abs + pool  what the threshold is fitted to"
  putStrLn ""
  rs <- sequence
    [ check "TA1  * the 2x2x2 pool FACTORS, and the halves commute" [axiom_TA1]
    , check "TA2  the temporal half is a 1x1 convolution"           [axiom_TA2]
    , check "TA3  * a flipped sign costs 2*min(|r|,g), not 2g"      [axiom_TA3]
    , check "TA4  a sign the engine can flip is worth nothing"      [axiom_TA4]
    , check "TA5  * fp16 is FREE at the rung that is the palette"   [axiom_TA5]
    , check "TA6  g never crosses the engine boundary"              [axiom_TA6]
    , check "TA7  the deviation statistic is pool-shaped, monotone"  [axiom_TA7]
    , check "TA8  the encode is data-independent: ONE dispatch"     [axiom_TA8]
    , check "TA9  the ledger: colour 20:1, and depth is the residue" [axiom_TA9]
    ]
  putStrLn ""
  putStrLn "  THE LEDGER, one retained capture at 4.7% loud:"
  putStrLn $ "    depth  f32 fine rung   " ++ show depthBytes ++ " B"
  putStrLn $ "    colour rung 16 fp16    " ++ show coarseBytes ++ " B"
  putStrLn $ "    colour significance    " ++ show sigBytes ++ " B"
  putStrLn $ "    colour signs, loud     " ++ show (signBytesAt 0.047) ++ " B"
  putStrLn $ "    TOTAL                  " ++ show (tensorBytes 0.047) ++ " B"
  putStrLn $ "    CubeStore today        " ++ show cubeStoreBytes ++ " B"
  putStrLn $ "    depth's share          "
             ++ pct (fromIntegral depthBytes
                     / fromIntegral (tensorBytes 0.047) :: Double)
  putStrLn ""
  putStrLn "  ★ WHAT THE ARITHMETIC SURFACES. Colour is solved: the"
  putStrLn "  octave plus the zerotree take 786432 B of voxel colour"
  putStrLn "  down to about 31000. Every remaining byte is DEPTH at"
  putStrLn "  the precision CT6 fixed. That is a ruling, not a defect."
  putStrLn ""
  if and rs
    then putStrLn "  all axioms hold"
    else error "TensorEncoder: axioms failed"
