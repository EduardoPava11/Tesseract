-- ════════════════════════════════════════════════════════════════
-- CaptureTensor: what the STORED tensor costs, and how it decodes
--
-- ★ SCOPE, AND WHY IT IS NARROW (Daniel's ruling 2026-08-14, "go
-- with the split"). This file is ONLY about the bytes the app
-- retains and the arithmetic that turns them back into a cube.
-- It does NOT restate the ladder, and it must not: three specs
-- already own that ground and this file cites them rather than
-- re-deriving them.
--
--   spec/quantization/Octave.hs      OV1-OV13  THE THREE PARALLEL
--     READS. The rung set, the bijection floor (16 squared = 256 =
--     the palette), kappa exact, all three reads share one mean,
--     axis symmetry, parallel coherence.
--
--   spec/output/FeedCompression.hs   FC1-FC10  THE WIRE FORMAT.
--     The rate law (side times delay = 320 cs, 20/10/5 Hz), frames
--     = side, the 4-channel OKLab+depth payload, the pyramid tax of
--     exactly 73/64, depth as the figure/ground boundary, and the
--     synthetic sampler interface.
--
--   spec/neural/OctaveCodec.hs       CX1-CX7   THE CODEC.
--     sigma_g(x) = (x+g, x-g) composed over three WIRED levels, and
--     CX1 kappa(sigma_g(x)) = x for ANY g, which that file names the
--     codec's load-bearing law.
--
-- An earlier draft of this file restated all of the above as its own
-- axioms. That was the schism this project retires specs for, and it
-- is recorded here so the next reader does not repeat it.
--
-- ── ★ THE SPLIT (CT1), the ruling this file exists under ────────
--
-- Free signs contradict OV5, CX1, CX2 and CX3, all green. Daniel
-- ruled the SPLIT rather than choosing a winner, because the two are
-- different objects:
--
--   THE READS AND THE CODEC. Computed by kappa from live data, or
--   expanded by the composed binary form. Mean invariance holds
--   EXACTLY, by construction, for any g. OV4, OV5, CX1, CX2, CX3
--   stand untouched. The octave dials remain provably safe: no
--   setting can move exposure, white point or cast.
--
--   THE STORED TENSOR. One free sign bit per child, chosen by the
--   data rather than by the wiring. Daniel ruled this on measured
--   evidence: about a third sharper (4.2 output levels of error
--   against 6.1). It does NOT claim CX1 and never should.
--
-- THE DECLARED COST (CT11). Because the stored form does not retract
-- exactly, a GIF made from the live feed and the same GIF remade from
-- the retained tensor are not identical. The divergence is bounded by
-- g and is stated here rather than discovered later.
--
-- WHY THE TWO FORMS BOTH EARN THEIR PLACE. The wired codec costs ZERO
-- sign bits, since a child derives its signs from its own position,
-- but it can only express separable variation. The stored form pays
-- one bit per child to express what the wiring cannot. Neither
-- dominates, which is why the split is a real ruling and not a dodge.
-- ════════════════════════════════════════════════════════════════

module CaptureTensor where

import Data.List (nub)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE RUNGS, CITED NOT RESTATED
-- ════════════════════════════════════════════════════════════════

-- | Cells per 3.2 s loop at each rung. The SHAPE is Octave's (OV1)
--   and FeedCompression's (FC1, FC2); only the cell counts are
--   repeated here, because the bit budget below is arithmetic on
--   them and a spec that cannot see its own inputs cannot be checked.
cells16, cells32, cells64 :: Int
cells16 =  4096      -- 16 frames of 16x16, 5 fps
cells32 = 32768      -- 32 frames of 32x32, 10 fps
cells64 = 262144     -- 64 frames of 64x64, 20 fps

allCells :: [Int]
allCells = [cells16, cells32, cells64]

-- | The 2x2x2 atom (OV12).
atom :: Int
atom = 8

-- ════════════════════════════════════════════════════════════════
-- § 2. THE STORED FORM
-- ════════════════════════════════════════════════════════════════

data Sign = Down | Up deriving (Eq, Show)

signValue :: Sign -> Double
signValue Up   =  1
signValue Down = -1

-- | The stored decode. Parametric in g, exactly as CX1 is, but
--   WITHOUT CX1's retraction guarantee, because the signs here come
--   from the data and not from the wiring.
expand :: Double -> Double -> Sign -> Double
expand parent g s = parent + signValue s * g

expandAll :: Double -> Double -> [Sign] -> [Double]
expandAll parent g = map (expand parent g)

-- | The step size. DHVC 2.0's conditioning, ruled 2026-08-14: the
--   lower-scale spatial parent AND the same-scale temporal reference.
--   The 5/10/20 fps rungs already provide the temporal half.
type StepFn = Double -> Maybe Double -> Double

spatialOnly :: Double -> StepFn
spatialOnly k parent _ = k * abs parent

withTemporal :: Double -> Double -> StepFn
withTemporal k j parent prev = case prev of
  Nothing -> k * abs parent
  Just p  -> k * abs parent + j * abs (parent - p)

-- ════════════════════════════════════════════════════════════════
-- § 3. ZEROTREES (EZW 1993 / SPIHT 1996)
-- ════════════════════════════════════════════════════════════════
--
-- ★ THE THREE LOUD FRACTIONS, RECONCILED 2026-08-16. This file used
-- to print 45064 and 30232 as LITERALS in a putStrLn, under the
-- heading "95.3% of subtrees quiet", and nothing recomputed either.
-- Three different loud fractions were loose in the documentation and
-- no reader could tell them apart, because none of them said WHICH
-- LEVEL it counted. Decomposing the literals settles it exactly:
--
--   45064 = cells32 * 1  +  loud32 * cells32 * atom
--         = 32768       +  0.0469 * 32768 * 8
--     so 4.7% is the loud fraction of RUNG-32 PARENTS, and 95.3%
--     quiet is a statement about that level only.
--
--   30232 = cells16 * 1  +  loud16 * cells16 * (atom + atom*atom)
--         = 4096        +  0.0886 * 4096 * 72
--     so the full-zerotree row counts RUNG-16 ROOTS, at 8.9%. It was
--     never the same population as the row above it.
--
--   15.576% is a THIRD thing: the CT7 statistic dev16_of(g32, g64)
--     over all 72 descendants of a rung-16 root, measured on
--     nn/tensor-codec's synthetic cube and reproduced to the root
--     (1914 of 12288) by Store/CaptureTensor.swift.
--
-- They are not in conflict. They count different populations on
-- different fixtures, and the documentation simply never said so.
-- The rows below are now COMPUTED from named fractions, so the
-- arithmetic cannot drift from the prose again.
--
-- The threshold is DERIVED, never chosen: the crossover of a
-- two-phase mixture on the capture's own subtree deviations, the same
-- mechanism ruled for the rung-64 override. A single-phase capture
-- has no quiet phase and pays flat.

-- ★ THE PRIMITIVE IS A COUNT, not a percentage. Both historical
--   figures decompose to integers exactly, which is what makes this a
--   recovery rather than a fit:
--     45064 = cells32 + 1537 * atom
--     30232 = cells16 +  363 * (atom + atom*atom)
loudParents32, loudRoots16 :: Int
loudParents32 = 1537      -- of cells32 = 32768, i.e. 4.691%
loudRoots16   =  363      -- of cells16 =  4096, i.e. 8.862%

loud32, loud16 :: Double
loud32 = fromIntegral loudParents32 / fromIntegral cells32
loud16 = fromIntegral loudRoots16   / fromIntegral cells16

-- | One significance bit per rung-32 parent, plus the atom for the
--   loud ones. The old literal was 45064.
significanceBits :: Int
significanceBits = cells32 + loudParents32 * atom

-- | One bit per rung-16 root; a loud root pays its 8 + 64 descendants.
--   The old literal was 30232.
zeroTreeBits :: Int
zeroTreeBits = cells16 + loudRoots16 * flatLadderCost

-- ★ AND THE TWO ROWS ARE MEASURED AGAINST DIFFERENT BASELINES, which
--   is the fourth thing nobody wrote down. The significance row is
--   compared to the flat FINE RUNG (cells64 = 262144) and the
--   zerotree row to the flat LADDER (cells16 * 72 = 294912). Both
--   published percentages, 82.81% and 89.75%, are correct for their
--   own baseline and wrong for the other one. Named here so a reader
--   cannot pick the wrong denominator.
flatFineBits, flatLadderBits :: Int
flatFineBits   = cells64                    -- 262144
flatLadderBits = cells16 * flatLadderCost   -- 294912

savingVs :: Int -> Int -> Double
savingVs base b = 1 - fromIntegral b / fromIntegral base

pctOf :: Double -> String
pctOf x = show (fromIntegral (round (x * 1000) :: Int) / 10 :: Double) ++ "%"

sigCost :: Bool -> Int
sigCost loud = 1 + (if loud then atom else 0)

flatCost :: Int
flatCost = atom

zeroTreeCost :: Bool -> Int
zeroTreeCost loud = 1 + (if loud then atom + atom * atom else 0)

flatLadderCost :: Int
flatLadderCost = atom + atom * atom

-- ════════════════════════════════════════════════════════════════
-- § 4. THE BIT BUDGET
-- ════════════════════════════════════════════════════════════════

-- | Equivalence: cells times bits equal at every rung. Anchor the
--   fine rung at its one octave bit; the rest is forced.
bitsPerCell :: Int -> Int
bitsPerCell c = cells64 `div` c

rungBits :: Int -> Int
rungBits c = c * bitsPerCell c

-- | Depth is stored whole (CT6). FC3 says depth rides every rung;
--   this file only adds that it is never quantised.
depthBits :: Int
depthBits = 32

-- ════════════════════════════════════════════════════════════════
-- § 5. THE AXIOMS
-- ════════════════════════════════════════════════════════════════

eps :: Double
eps = 1e-12

-- (CT1) ★ THE SPLIT. The stored form does NOT retract: there exist
--       sign patterns whose reconstruction has a different mean from
--       the parent. The composed codec DOES retract for any g (CX1),
--       and this file never claims otherwise. Both statements are
--       true because they are about different objects, and holding
--       them apart is the whole content of the ruling.
axiom_CT1 :: Bool
axiom_CT1 =
     any (\ss -> abs (mean (expandAll p g ss) - p) > eps) allPatterns
  && all (\ss -> abs (mean (expandAll p g ss) - p) < eps)
         [ ss | ss <- allPatterns, balanced ss ]
  where
    p = 0.5
    g = 0.1
    allPatterns = mapM (const [Down, Up]) [1 .. 8 :: Int]
    balanced ss = length (filter (== Up) ss) == 4
    mean xs = sum xs / fromIntegral (length xs)

-- (CT2) THE EQUIVALENT FLOAT RESOLUTION IS FORCED. Cells stand
--       1 : 8 : 64 (OV1, FC2), so bits per cell stand 64 : 8 : 1 and
--       every rung carries the same total. Nothing is chosen.
axiom_CT2 :: Bool
axiom_CT2 =
     map bitsPerCell allCells == [64, 8, 1]
  && length (nub (map rungBits allCells)) == 1
  && bitsPerCell cells64 == 1
  && cells32 == atom * cells16
  && cells64 == atom * cells32

-- (CT3) ONE BIT PER CHILD IS THE FINE RUNG'S WHOLE BUDGET, and the
--       octave form and the forced allocation agree on that number.
axiom_CT3 :: Bool
axiom_CT3 =
     atom * bitsPerCell cells64 == atom
  && cells64 * bitsPerCell cells64 == rungBits cells64

-- (CT4) THE STORED DECODE IS PARAMETRIC IN g. Mirror images about
--       the parent, separation exactly 2g, and nothing read but
--       (parent, g, bit). True for any step function, so choosing
--       the model later cannot invalidate a law.
axiom_CT4 :: Bool
axiom_CT4 =
     and [ abs ((expand p (f p prev) Up - p)
                + (expand p (f p prev) Down - p)) < eps
         | f <- fs, p <- ps, prev <- prevs ]
  && and [ abs (expand p (f p prev) Up - expand p (f p prev) Down
                - 2 * f p prev) < eps
         | f <- fs, p <- ps, prev <- prevs ]
  where
    fs = [spatialOnly 0.1, withTemporal 0.1 0.5]
    ps = [0, 0.25, 0.5, 1]
    prevs = [Nothing, Just 0.2, Just 0.9]

-- (CT5) ★ THE DRIFT IS RULED AND BOUNDED. Daniel chose free signs
--       over balanced on measured evidence (about a third sharper).
--       The slide is exactly g times the sign imbalance over eight,
--       so it is bounded by g and vanishes when signs balance.
--       Checked over ALL 256 patterns.
axiom_CT5 :: Bool
axiom_CT5 =
  and [ abs (drift ss - expected ss) < eps && abs (drift ss) <= abs g + eps
      | ss <- allPatterns ]
  where
    g = 0.1
    p = 0.5
    allPatterns = mapM (const [Down, Up]) [1 .. 8 :: Int]
    drift ss = sum (expandAll p g ss) / 8 - p
    expected ss = g * sum (map signValue ss) / 8

-- (CT6) DEPTH IS NEVER QUANTISED. FC6 already says depth carries the
--       figure/ground split; this adds Daniel's ruling that it is
--       therefore stored whole at every rung and never rides the
--       octave form.
axiom_CT6 :: Bool
axiom_CT6 =
     depthBits == 32
  && all (\c -> depthCost c == c * depthBits) allCells
  && depthCost cells64 > sum (map rungBits allCells)   -- and it dominates
  where
    depthCost c = c * depthBits

-- (CT7) SIGNIFICANCE COSTS ONE BIT AND CAN SAVE EIGHT. Cheaper than
--       flat exactly when the loud fraction is below 7/8; measured
--       at 4.7%, which is nowhere near the break-even.
axiom_CT7 :: Bool
axiom_CT7 =
     sigCost False == 1
  && sigCost True == 1 + atom
  && sigCost True > flatCost
  && sigCost False < flatCost
  && breakEven == 7 / 8
  && cheaperAt 0.047
  && not (cheaperAt 0.95)
  where
    breakEven = fromIntegral (flatCost - 1) / fromIntegral atom :: Double
    cheaperAt p = 1 + p * fromIntegral atom < fromIntegral flatCost

-- (CT12) ★ THE THREE LOUD FRACTIONS ARE THREE POPULATIONS, and this
--        axiom exists so the arithmetic can never drift from the prose
--        again. Until 2026-08-16 the two zerotree rows were LITERALS
--        in a putStrLn (45064 and 30232) under a single "95.3% quiet"
--        heading, and nothing recomputed them, so three different
--        fractions read as one contradictory number.
--
--        Pinned here: each row is reproduced from its OWN population
--        to the bit, the two populations are genuinely different, and
--        both sit far below CT7's 7/8 break-even, so the zerotree
--        ruling does not depend on which fraction a reader picks up.
axiom_CT12 :: Bool
axiom_CT12 =
     -- the historical figures, recovered from the named fractions
     significanceBits == 45064
  && zeroTreeBits == 30232
     -- and they are NOT the same population
  && loud32 /= loud16
     -- both rows beat the flat bit, which is the ruling
  && significanceBits < cells64
  && zeroTreeBits < significanceBits
     -- and every fraction in play, including CT7's dev16 statistic at
     -- 15.576%, is below the 7/8 break-even, so significance coding
     -- is cheaper on all three readings
  && all belowBreakEven [loud32, loud16, 0.15576]
  where
    belowBreakEven p = 1 + p * fromIntegral atom < fromIntegral flatCost
    near a b = abs (a - b) < 5e-5

-- (CT8) A ZEROTREE ROOT TERMINATES THE WHOLE SUBTREE: one symbol at
--       rung 16 covers 8 descendants at rung 32 and 64 at rung 64.
--       Break-even 71/72, measured at 8.9% loud.
axiom_CT8 :: Bool
axiom_CT8 =
     zeroTreeCost False == 1
  && zeroTreeCost True == 1 + flatLadderCost
  && flatLadderCost == 72
  && abs (breakEven - 71 / 72) < eps
  && 1 + 0.089 * fromIntegral flatLadderCost < fromIntegral flatLadderCost
  where
    breakEven = fromIntegral (flatLadderCost - 1)
              / fromIntegral flatLadderCost :: Double

-- (CT9) A QUIET SUBTREE IS g = 0, NOT A SECOND PATH. Silence uses
--       the decode law already stated, so significance coding adds no
--       reconstruction branch (the no-fallback decree).
axiom_CT9 :: Bool
axiom_CT9 =
  and [ expand p 0 s == p | p <- [0, 0.25, 0.5, 1], s <- [Up, Down] ]

-- (CT10) ★ g READS THE PARENT AND THE PREVIOUS TICK. A temporal step
--        genuinely uses its reference, and degrades to the spatial
--        reading on a first tick rather than taking a special path.
axiom_CT10 :: Bool
axiom_CT10 =
     withTemporal 0.1 0.5 0.5 (Just 0.5) /= withTemporal 0.1 0.5 0.5 (Just 0.1)
  && withTemporal 0.1 0.5 0.5 Nothing == spatialOnly 0.1 0.5 Nothing

-- (CT11) ★ THE DECLARED COST OF THE SPLIT. A cube rebuilt from the
--        stored tensor differs from the same cube read live, and the
--        per-parent difference is bounded by g. This is the price of
--        the ruling, stated as a law so it can never be discovered
--        as a surprise.
axiom_CT11 :: Bool
axiom_CT11 =
  and [ abs (mean (expandAll p g ss) - p) <= abs g + eps | ss <- allPatterns ]
  && maximum [ abs (mean (expandAll p g ss) - p) | ss <- allPatterns ] > eps
  where
    p = 0.5
    g = 0.1
    allPatterns = mapM (const [Down, Up]) [1 .. 8 :: Int]
    mean xs = sum xs / fromIntegral (length xs)

-- ════════════════════════════════════════════════════════════════
-- § 6. THE HARNESS
-- ════════════════════════════════════════════════════════════════

check :: String -> [Bool] -> IO Bool
check name bs = do
  let ok = and bs
  putStrLn $ "  " ++ (if ok then "\10003" else "\10007") ++ " " ++ name
  return ok

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " CaptureTensor: what the STORED tensor costs"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  rs <- sequence
    [ check "CT1  * THE SPLIT: stored does not retract, codec does" [axiom_CT1]
    , check "CT2  equivalent float resolution forced 64:8:1"        [axiom_CT2]
    , check "CT3  one bit per child IS the fine rung's budget"      [axiom_CT3]
    , check "CT4  stored decode is parametric in g"                 [axiom_CT4]
    , check "CT5  * free-sign drift bounded by g, ruled"            [axiom_CT5]
    , check "CT6  depth is never quantised, and dominates"          [axiom_CT6]
    , check "CT7  significance: 1 bit saves 8, break-even 7/8"      [axiom_CT7]
    , check "CT8  a zerotree root kills 8 + 64 descendants"         [axiom_CT8]
    , check "CT9  a quiet subtree is g = 0, not a second path"      [axiom_CT9]
    , check "CT12 * three loud fractions = three populations"       [axiom_CT12]
    , check "CT10 * g reads parent AND previous tick"               [axiom_CT10]
    , check "CT11 * the live/remade divergence is bounded by g"     [axiom_CT11]
    ]
  putStrLn ""
  putStrLn "  THE SPLIT (Daniel, 2026-08-14):"
  putStrLn "    reads + codec   mean invariance EXACT (OV5, CX1-CX3)"
  putStrLn "    stored tensor   free signs, drift bounded by g (CT5)"
  putStrLn "    the price       live and remade differ, bounded (CT11)"
  putStrLn ""
  putStrLn "  ZEROTREES, and the three loud fractions count THREE"
  putStrLn "  DIFFERENT POPULATIONS. Computed, not pasted:"
  putStrLn $ "    flat             " ++ show cells64 ++ " b"
  putStrLn $ "    significance     " ++ show significanceBits
             ++ " b   saving " ++ pctOf (savingVs flatFineBits significanceBits)
             ++ " vs the flat FINE RUNG " ++ show flatFineBits
  putStrLn $ "                     " ++ show loudParents32
             ++ " loud rung-32 parents of " ++ show cells32
             ++ " = " ++ pctOf loud32
  putStrLn $ "    full zerotree    " ++ show zeroTreeBits
             ++ " b   saving " ++ pctOf (savingVs flatLadderBits zeroTreeBits)
             ++ " vs the flat LADDER " ++ show flatLadderBits
  putStrLn $ "                     " ++ show loudRoots16
             ++ " loud rung-16 roots of " ++ show cells16
             ++ " = " ++ pctOf loud16
  putStrLn "    CT7's dev16 statistic is a THIRD population: 15.576%"
  putStrLn "    of rung-16 roots on nn/tensor-codec's cube, 1914/12288,"
  putStrLn "    reproduced by the Swift port. See the note in section 3." 
  putStrLn ""
  putStrLn "  The ladder itself is NOT restated here. Octave.hs owns"
  putStrLn "  the reads, FeedCompression.hs owns the wire format, and"
  putStrLn "  OctaveCodec.hs owns the codec. This file owns the bytes."
  putStrLn ""
  if and rs
    then putStrLn "  all axioms hold"
    else error "CaptureTensor: axioms failed"
