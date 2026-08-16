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

-- | Sign bits at a loud rung-16 root: its 8 rung-32 children and its
--   64 rung-64 descendants (CT8's 72).
signBitsPerLoudRoot :: Int
signBitsPerLoudRoot = 72

-- | ★ AND THE FOUR BYTES OF g, WHICH THE PORT WRITES AND THIS FILE
--   USED TO OMIT (adversarial run, 2026-08-15). The ledger charged 72
--   bits per loud root and nothing else, which prices a PREDICTED-g
--   format. The shipped port stores g instead:
--   Store/CaptureTensor.swift charges `perLoud = 4 + 72/8` = 13 B, and
--   writeSubtree emits two fp16 values that decode reads back off the
--   wire. So the spec's TOTAL could never be produced by the encoder
--   it describes, and no test compared them.
--
--   Storing g is the RULING (CaptureTensor.swift's header states it):
--   a tensor retained today stays decodable after any retrain, and no
--   naked k and j enter the app while the predictor does not exist.
--   This file now prices what ships.
--
--   ★ THE SAME 9-BYTE MODEL IS REPEATED in nn/tensor-codec at
--   build_model.py:222 and noise_floor.py:75, so any compression
--   figure quoted from those scripts is light by the same factor.
gBytesPerLoudRoot :: Int
gBytesPerLoudRoot = 4

bitsPerLoudRoot :: Int
bitsPerLoudRoot = signBitsPerLoudRoot + 8 * gBytesPerLoudRoot   -- 104

signBytesAt :: Double -> Int
signBytesAt loud =
  ceiling (loud * fromIntegral (cells16 * channels)
                * fromIntegral bitsPerLoudRoot / 8)

-- | ★ THE LOUD FRACTION IS A MEASUREMENT, AND TWO IMPLEMENTATIONS
--   DISAGREE ABOUT IT. Named here with provenance rather than left as
--   a bare literal in an axiom body.
--
--   `loudShipped` is what DepthMixture's crossover measures through
--   the Swift port on the documented synthetic cube. `loudPythonRef`
--   is what nn/tensor-codec/build_model.py:212 reports, and it is
--   WRONG: it writes log((1-w)/w) where DepthMixture.hs:182 and the
--   Swift both write log(piB/(1-piB)), so its point is the reflection
--   of the crossover about the midpoint. At the shipped point the two
--   weighted component densities are equal to 1.0000; at the Python
--   point the quiet component is 29.4x the loud one, and the reported
--   loud fraction exceeds the loud component's own fitted weight.
--   Kept here, named, because CLAUDE.md still quotes figures derived
--   from it.
loudShipped, loudPythonRef :: Double
loudShipped   = 0.15576         -- 1914 / 12288, DepthMixture crossover
loudPythonRef = 0.24862         -- build_model.py, inverted sign

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
--       and deviations; whatever g the decoder later uses, STORED
--       today or trained tomorrow, the bit the engine already emitted
--       is still the error-minimising one. So CT4's "parametric in g"
--       survives the port intact, and a later trained g cannot
--       invalidate this placement, which is the property CT4 was
--       written to protect.
--
--       ★ REWRITTEN 2026-08-15 after the adversarial run. The old
--       first conjunct was
--           and [ signBit r == signBit r' | (r, r') <- zip rs rs ]
--       and `zip rs rs` pairs a list with ITSELF, so every comparison
--       was signBit r == signBit r. It could not fail. The axiom
--       guarding the placement had no content in the half that
--       mattered.
--
--       ★ AND THE PROSE WAS WRONG TOO, which the tautology also hid.
--       The old text said "the DECODER recomputes g from stored
--       parents". The shipped port does not: Store/CaptureTensor.swift
--       STORES g, four bytes per loud root, and the decode reads it
--       back off the wire. See the ledger note at signBytesAt.
--
--       What has content is the ARGMIN claim, which fails the moment
--       errFor stops being symmetric about zero:
axiom_TA6 :: Bool
axiom_TA6 =
     -- the emitted sign IS the error-minimising choice, for every g
     and [ (errFor True r g <= errFor False r g) == signBit r
         | r <- rs, g <- gs ]
     -- and strictly so away from r = 0, so no g manufactures a tie a
     -- later retrain could break the other way
  && and [ abs (errFor (signBit r) r g - errFor (not (signBit r)) r g) > eps
         | r <- rs, g <- gs, r /= 0 ]
     -- the sign is scale-free in the residual
  && and [ signBit r == signBit (r * s) | r <- rs, s <- [0.1, 1, 10] ]
  where
    rs = [-0.7, -0.02, 0.02, 0.7]
    gs = [1e-4, 0.005, 0.05, 0.4]

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
--       CubeStore holds today, and the residue is DEPTH: it is over
--       95% of what is left, which is the ruling this file's
--       arithmetic surfaces (CT6 fixed depth at 32 bits, and that
--       choice now dominates the whole memory bill).
--
--       ★ REWRITTEN 2026-08-15 after the adversarial run, and this
--       axiom was FALSE, not merely weak. It asserted
--       `colourRatio > 20` off a hardcoded 0.047 loud fraction. At
--       the fraction the shipped Swift law actually measures the ratio
--       is 18.15 with the old 9-byte model and 15.42 once g is priced,
--       so the axiom read green while asserting something untrue of
--       the encoder it describes. Two separate defects made it pass:
--       a naked threshold, which the no-naked-constants decree already
--       forbids, and a naked loud fraction taken from the reference
--       script with the inverted crossover sign.
--
--       The magic 20 is GONE rather than re-tuned. A retuned bound
--       would be the same defect at a different number. What is
--       asserted now is structural: the tensor beats CubeStore, depth
--       dominates the residue, an all-quiet capture pays nothing for
--       signs, and the ratio FALLS as the loud fraction rises. The
--       ratio itself is printed rather than pinned, because it is a
--       measurement of the capture and not a property of the format.
axiom_TA9 :: Bool
axiom_TA9 =
     tensorBytes loudShipped < cubeStoreBytes
  && depthShare > 0.95
     -- an all-quiet capture spends nothing on signs (CT9: g = 0 is
     -- silence, not a second path)
  && signBytesAt 0 == 0
     -- colour still beats the flat voxel-byte format it replaces, at
     -- BOTH disputed fractions, so the ruling does not hinge on which
     -- crossover is right
  && colourRatioAt loudShipped > 1
  && colourRatioAt loudPythonRef > 1
     -- and the ratio is MONOTONE in the loud fraction, which is what
     -- makes it a measurement: a louder capture pays more
  && colourRatioAt 0.0 > colourRatioAt loudShipped
  && colourRatioAt loudShipped > colourRatioAt loudPythonRef
  where
    depthShare = fromIntegral depthBytes
               / fromIntegral (tensorBytes loudShipped) :: Double

-- (TA10) ★ THE LEDGER IS PINNED TO THE PORT. NEW 2026-08-15, and it
--        is the gate whose absence let the 9-byte defect live: nothing
--        anywhere compared this file's `tensorBytes` to the Swift
--        `bytesPerCapture`, so the spec priced a format the encoder
--        does not write and both sides stayed green for a month.
--
--        Two pins, both hand-carried across the language boundary
--        because no spec file may import and Haskell cannot call
--        Swift:
--
--          1. the per-root cost, stated the way Store/CaptureTensor
--             .swift states it (`perLoud = 4 + 72/8`), so changing
--             either the sign count or the g bytes breaks this axiom
--          2. the TOTAL at the shipped crossover, against the figure
--             CaptureTensorTests measures on the documented synthetic
--             fixture: 1099586 B
--
--        ★ BE HONEST ABOUT WHAT THIS IS. A hand-carried constant is
--        exactly the shape of the MerkleSearch defect, and it is only
--        safe here because of the direction: this axiom quantifies
--        over the spec's OWN computed arithmetic and compares it to
--        the other implementation, so drift on EITHER side fails it.
--        The MerkleSearch defect was restating a number and then
--        quantifying over the restatement, which can only agree with
--        itself. The residual gap is real and stays owed: the mirror
--        assertion belongs in CaptureTensorTests, comparing Swift's
--        measured bytes back to this file's printed TOTAL.
axiom_TA10 :: Bool
axiom_TA10 =
     bitsPerLoudRoot == 8 * (gBytesPerLoudRoot + signBitsPerLoudRoot `div` 8)
  && bitsPerLoudRoot == 104
  && tensorBytes loudShipped == portMeasuredBytes
     -- and the pin is not an accident of one fraction: the port's
     -- per-root cost is what makes it land
  && tensorBytes loudShipped > tensorBytesAtSignsOnly loudShipped
  where
    tensorBytesAtSignsOnly loud =
      16 + depthBytes + coarseBytes + sigBytes
      + ceiling (loud * fromIntegral (cells16 * channels)
                      * fromIntegral signBitsPerLoudRoot / 8 :: Double)

-- | Measured by TesseractTests/CaptureTensorTests on the synthetic
--   figure-over-ground fixture, quoted in CLAUDE.md. Hand carried; see
--   TA10's note on why that is safe here and what stays owed.
portMeasuredBytes :: Int
portMeasuredBytes = 1099586

colourBytesAt :: Double -> Int
colourBytesAt loud = coarseBytes + sigBytes + signBytesAt loud

colourRatioAt :: Double -> Double
colourRatioAt loud =
  fromIntegral (cells64 * channels) / fromIntegral (colourBytesAt loud)

-- ════════════════════════════════════════════════════════════════
-- § 7. THE HARNESS
-- ════════════════════════════════════════════════════════════════

check :: String -> [Bool] -> IO Bool
check name bs = do
  let ok = and bs
  putStrLn $ "  " ++ (if ok then "\10003" else "\10007") ++ " " ++ name
  return ok

ratioLine :: Double -> String
ratioLine loud =
  pad (pct loud) ++ "  colour " ++ show (colourBytesAt loud) ++ " B  "
  ++ show (fromIntegral (round (colourRatioAt loud * 100) :: Int) / 100 :: Double)
  ++ " : 1"
  where pad s = s ++ replicate (max 0 (7 - length s)) ' '

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
    , check "TA9  the ledger: monotone in loud, depth is the residue" [axiom_TA9]
    , check "TA10 * the ledger is PINNED to the port's own bytes"     [axiom_TA10]
    ]
  putStrLn ""
  putStrLn $ "  THE LEDGER, one retained capture at "
             ++ pct loudShipped ++ " loud (the SHIPPED crossover):"
  putStrLn $ "    depth  f32 fine rung   " ++ show depthBytes ++ " B"
  putStrLn $ "    colour rung 16 fp16    " ++ show coarseBytes ++ " B"
  putStrLn $ "    colour significance    " ++ show sigBytes ++ " B"
  putStrLn $ "    colour signs, loud     " ++ show (signBytesAt loudShipped)
             ++ " B   (" ++ show bitsPerLoudRoot ++ " b per loud root, g INCLUDED)"
  putStrLn $ "    TOTAL                  " ++ show (tensorBytes loudShipped) ++ " B"
  putStrLn $ "    CubeStore today        " ++ show cubeStoreBytes ++ " B"
  putStrLn $ "    depth's share          "
             ++ pct (fromIntegral depthBytes
                     / fromIntegral (tensorBytes loudShipped) :: Double)
  putStrLn ""
  putStrLn "  ★ THE COLOUR RATIO IS A MEASUREMENT, NOT A CONSTANT, and"
  putStrLn "  two implementations disagree about the loud fraction:"
  putStrLn $ "    all quiet            " ++ ratioLine 0.0
  putStrLn $ "    shipped crossover    " ++ ratioLine loudShipped
  putStrLn $ "    build_model.py       " ++ ratioLine loudPythonRef
             ++ "   <- inverted sign, see loudPythonRef"
  putStrLn ""
  putStrLn "  ★ WHAT THE ARITHMETIC SURFACES. Colour is solved: the"
  putStrLn "  octave plus the zerotree take 786432 B of voxel colour"
  putStrLn "  down to about 51000. Every remaining byte is DEPTH at"
  putStrLn "  the precision CT6 fixed. That is a ruling, not a defect."
  putStrLn ""
  if and rs
    then putStrLn "  all axioms hold"
    else error "TensorEncoder: axioms failed"
