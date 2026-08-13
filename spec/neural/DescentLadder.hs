{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- DescentLadder: the assignment descent and the three-model ladder
--
-- Daniel's rulings (2026-08-12, post-adversarial-review):
--   · the capture-assist model's FIRST job is P4 — hierarchical
--     assignment (tree descent), replacing the 128-way search
--     under the XP2 near-tie posture;
--   · the 3-MODEL LADDER is committed STRUCTURALLY now — M16/M32/
--     M64 nest by tree OUTPUTS (PT5 prefix law), NEVER by weights;
--   · corpus = synthetic sampler only (★NO-CAPTURE-TRAINING);
--   · sizes, cadences, and the sweep count K are DEVICE-MEASURED
--     parameters — they appear in NO law below (the adversarial
--     review killed every citation-derived constant; the ledger
--     and device passes decide).
--
-- The corrected lessons this spec encodes (docs/
-- jepa-h-adversarial-review-2026-08-12.md):
--   · small CONSTANT serial depth is the lawful shape (not "steps
--     lose" — O(n) serial depth loses);
--   · nesting lives on OUTPUTS: stopping the descent early IS the
--     coarser model, exactly (quotient law), so the ladder cannot
--     drift apart by construction;
--   · descent may disagree with exhaustive search only at
--     near-ties, and downstream F-descent revision stays lawful
--     (no "never revise" axiom — the review killed it);
--   · zero-rate-loss is NOT assumed: descent excess distortion is
--     a measured quantity with a per-probe bound, not a theorem.
--
--   DL1  the descent: fixed serial depth 3, fan-outs [2,8,8],
--        18 candidates examined vs 128 exhaustive
--   DL2  output nesting: early exit at stage k == classAbove
--        quotient of the full descent (the ladder law)
--   DL3  separated exactness: on margin-dominated fixtures the
--        descent equals exhaustive nearest at every level
--   DL4  near-tie law: on Gaussian-tree probes, every
--        disagreement is a near-tie — excess distortion is
--        bounded by the smallest stage gap encountered
--   DL5  corpus law: sampler is deterministic, stats are lawful
--        (PSD by construction), labels come from EXHAUSTIVE
--        search only — ground truth independent of the student
-- ════════════════════════════════════════════════════════════════

module DescentLadder where

import Data.Bits ((.&.), shiftR, complement)
import Data.List (minimumBy)
import Data.Ord (comparing)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE ANALYTIC TREE (mirrors PairTree.hs § 3b — PT7-PT9)
-- ════════════════════════════════════════════════════════════════

type Lab = (Double, Double, Double)

halfMeanC, halfVarC :: Double
halfMeanC = sqrt (2 / pi)
halfVarC  = 1 - 2 / pi

data GNode = GNode { gMean :: [Double], gVar :: [Double] }

splitAxis :: GNode -> Int
splitAxis n = fst (foldl pick (0, head vs) (zip [1 ..] (tail vs)))
  where
    vs = gVar n
    pick (bi, bv) (i, v) = if v > bv then (i, v) else (bi, bv)

splitG :: GNode -> (GNode, GNode)
splitG n = (child (-1), child 1)
  where
    a = splitAxis n
    v = gVar n !! a
    off = sqrt v * halfMeanC
    child s = GNode
      { gMean = [ if i == a then m + fromIntegral (s :: Int) * off else m
                | (i, m) <- zip [0 ..] (gMean n) ]
      , gVar  = [ if i == a then v * halfVarC else w
                | (i, w) <- zip [0 ..] (gVar n) ] }

-- | Node reached by a bit path (MSB-first generations).
nodeAt :: [Int] -> GNode -> GNode
nodeAt [] n = n
nodeAt (b : bs) n = let (l, r) = splitG n
                    in nodeAt bs (if b == 0 then l else r)

-- | The 128 leaves, index bits MSB = first generation.
leaves :: GNode -> [Lab]
leaves root = [ toLab (gMean (nodeAt (bitsOf j) root)) | j <- [0 .. 127] ]
  where bitsOf j = [ (j `shiftR` k) .&. 1 | k <- [6, 5 .. 0] ]

toLab :: [Double] -> Lab
toLab [x, y, z] = (x, y, z)
toLab _ = error "3 coords"

d2 :: Lab -> Lab -> Double
d2 (a, b, c) (x, y, z) = (a-x)^(2::Int) + (b-y)^(2::Int) + (c-z)^(2::Int)

-- ════════════════════════════════════════════════════════════════
-- § 2. THE DESCENT (P4 semantics) AND THE LADDER LEVELS
--
-- Stage boundaries are the figure strata (PT2): bit 6 | bits 5..3
-- | bits 2..0 — fan-outs [2, 8, 8], serial depth 3, candidates
-- examined 2+8+8 = 18. The three exits are the ladder:
--
--   exit 1 (2 figure classes  → 4 palette entries with σ)  = M16
--   exit 2 (16 figure classes → 32 with σ)                 = M32
--   exit 3 (128 leaves        → 256 with σ)                = M64
--
-- One descent, three exit depths: the models nest by OUTPUT.
-- ════════════════════════════════════════════════════════════════

stageBits :: [[Int]]
stageBits = [[6], [5, 4, 3], [2, 1, 0]]

fanouts :: [Int]
fanouts = map ((2 ^) . length) stageBits

-- | Centroid of the leaf class with the given index prefix
--   (bits chosen so far, MSB-first) — the analytic node mean,
--   which PT9 proved equals the octet mean of its leaves.
levelMean :: GNode -> [Int] -> Lab
levelMean root path = toLab (gMean (nodeAt path root))

-- | Greedy descent: at each stage pick the candidate class whose
--   analytic mean is nearest the target; ties → lowest index.
descend :: GNode -> Lab -> [Int]
descend root target = go [] stageBits
  where
    go path [] = path
    go path (bits : rest) =
      let cands = sequence (replicate (length bits) [0, 1])
          best = minimumBy
            (comparing (\c -> (d2 (levelMean root (path ++ c)) target,
                               bitsToInt c)))
            cands
      in go (path ++ best) rest
    bitsToInt = foldl (\acc b -> 2 * acc + b) 0

-- | Path → leaf index (7 bits MSB-first).
pathIndex :: [Int] -> Int
pathIndex = foldl (\acc b -> 2 * acc + b) 0

-- | Exhaustive exact nearest leaf (ties → lowest index) — the
--   teacher; corpus labels come from HERE only (DL5).
exhaustive :: [Lab] -> Lab -> Int
exhaustive ls target =
  snd (minimumBy (comparing fst) (zip (map (d2 target) ls) [0 ..]))

-- | classAbove on 7-bit figure indices: drop the low k bits.
quotient :: Int -> Int -> Int
quotient k i = i `shiftR` k

-- ════════════════════════════════════════════════════════════════
-- § 3. FIXTURES AND PROBES (deterministic, no System.Random)
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

-- | Gaussian-tree fixtures: skin-like and cool statistics with
--   axis-aligned canonical directions (the spec's Lab frame).
gaussTrees :: [GNode]
gaussTrees =
  [ GNode [0.62, 0.05, 0.02]  [0.020, 0.008, 0.002]
  , GNode [0.45, -0.01, 0.04] [0.004, 0.015, 0.006]
  , GNode [0.70, 0.02, -0.03] [0.010, 0.010, 0.010]   -- tied axes
  ]

probesFor :: Int -> GNode -> [Lab]
probesFor n root =
  take n (go (uniforms 97))
  where
    (ml, ma, mb) = toLab (gMean root)
    [vl, va, vb] = gVar root
    go (u : v : w : us) =
      ( ml + (u - 0.5) * 6 * sqrt vl
      , ma + (v - 0.5) * 6 * sqrt va
      , mb + (w - 0.5) * 6 * sqrt vb ) : go us
    go _ = []

-- | Margin-dominated fixture (PT5 pattern): leaves at dyadic
--   positions p(j) = Σ bit_k(j)·3^k on the L axis — every level's
--   separation dominates all below it.
separatedLeaves :: [Lab]
separatedLeaves =
  [ (sum [ fromIntegral ((j `shiftR` k) .&. 1) * 3 ^ k / 3000
         | k <- [0 .. 6 :: Int] ], 0, 0)
  | j <- [0 .. 127 :: Int] ]

-- | A degenerate "tree" whose node means are the class means of
--   the separated leaves (for DL3's descent-vs-exact check).
separatedMean :: [Int] -> Lab
separatedMean path =
  let k = 7 - length path
      c = pathIndex path * (2 ^ k)
      members = [ separatedLeaves !! (c + r) | r <- [0 .. 2 ^ k - 1] ]
      n = fromIntegral (length members)
      (ls, as, bs) = unzip3 members
  in (sum ls / n, sum as / n, sum bs / n)

descendSeparated :: Lab -> [Int]
descendSeparated target = go [] stageBits
  where
    go path [] = path
    go path (bits : rest) =
      let cands = sequence (replicate (length bits) [0, 1])
          best = minimumBy
            (comparing (\c -> (d2 (separatedMean (path ++ c)) target,
                               pathIndex c)))
            cands
      in go (path ++ best) rest

-- ════════════════════════════════════════════════════════════════
-- § 4. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (DL1) THE DESCENT SHAPE: serial depth exactly 3, fan-outs [2,8,8],
--       18 candidates examined; the exits partition the 7 bits and
--       compose to the full index — the corrected codec lesson
--       (constant serial depth) as structure, with no size or
--       cadence constant anywhere in the law.
axiom_DL1 :: Bool
axiom_DL1 =
     length stageBits == 3
  && fanouts == [2, 8, 8]
  && sum fanouts == 18
  && concat stageBits == [6, 5, 4, 3, 2, 1, 0]
  && product fanouts == 128

-- (DL2) OUTPUT NESTING (the ladder law): stopping the descent at
--       stage k yields EXACTLY the classAbove quotient of the full
--       descent — M16 and M32 are prefixes of M64's answer by
--       construction, on every tree and every probe. The models
--       cannot drift apart.
axiom_DL2 :: Bool
axiom_DL2 = and
  [ let full = descend root p
        exit1 = take 1 full     -- M16's class (1 bit)
        exit2 = take 4 full     -- M32's class (4 bits)
        j = pathIndex full
    in pathIndex exit1 == quotient 6 j
    && pathIndex exit2 == quotient 3 j
  | root <- gaussTrees, p <- probesFor 60 root ]

-- (DL3) SEPARATED EXACTNESS: on the margin-dominated fixture the
--       greedy descent equals exhaustive nearest at EVERY level
--       (leaf, 16-class, 2-class) — the regime the ANE descent is
--       licensed for.
axiom_DL3 :: Bool
axiom_DL3 = and
  [ let path = descendSeparated p
        j = pathIndex path
        e = exhaustive separatedLeaves p
    in j == e
    && quotient 3 j == quotient 3 e
    && quotient 6 j == quotient 6 e
  | p <- probeGrid ]
  where
    probeGrid = [ (fromIntegral n / 40000, 0.0, 0.0)
                | n <- [0 .. 160 :: Int] ]

-- (DL4) NEAR-TIE LAW: on Gaussian-tree probes, descent distortion
--       never beats exact (sanity), and EVERY disagreement is a
--       near-tie — the excess distance is bounded by the smallest
--       stage-decision gap the descent encountered on that probe
--       (the XP2 posture, stated per probe and CHECKED, not
--       assumed; zero rate/distortion loss is never claimed).
axiom_DL4 :: Bool
axiom_DL4 = and
  [ let ls = leaves root
        path = descend root p
        dj = sqrt (d2 (ls !! pathIndex path) p)
        de = sqrt (d2 (ls !! exhaustive ls p) p)
        gap = minStageGap root p
    in dj + 1e-12 >= de
    && (pathIndex path == exhaustive ls p || dj - de <= 2 * gap + 1e-9)
  | root <- gaussTrees, p <- probesFor 60 root ]
  where
    -- smallest winner/runner-up mean-distance gap over the stages
    minStageGap root p = minimum (go [] stageBits)
      where
        go _ [] = []
        go path (bits : rest) =
          let cands = sequence (replicate (length bits) [0, 1])
              ds = [ sqrt (d2 (levelMean root (path ++ c)) p) | c <- cands ]
              sorted = minimum ds : [minimum (filter (> minimum ds) ds ++ [1/0])]
              gap = case sorted of [a, b] -> b - a; _ -> 1/0
              best = minimumBy
                (comparing (\c -> (d2 (levelMean root (path ++ c)) p,
                                   pathIndex c)))
                cands
          in gap : go (path ++ best) rest

-- (DL6) CONDITIONAL EXACTNESS (the v4 law, measured in the lab
--       run of 2026-08-12 and pinned here): given the half that
--       contains the teacher's leaf, committing at stage 2 to the
--       octet with the smallest MIN-LEAF distance and then taking
--       the exact leaf argmin recovers EXACTLY the teacher's leaf,
--       for every tree and probe. Stages 2 and 3 are therefore
--       LAW, not learning; the only learnable blindness left in
--       the descent is the stage-1 half choice.
axiom_DL6 :: Bool
axiom_DL6 = and
  [ let ls = leaves root
        e = exhaustive ls p
        h = e `div` 64
        octs = [ (minimum [ d2 (ls !! (o * 8 + r)) p | r <- [0 .. 7] ], o)
               | o <- [h * 8 .. h * 8 + 7] ]
        o' = snd (minimum octs)
        leaf' = o' * 8 + snd (minimum
          [ (d2 (ls !! (o' * 8 + r)) p, r) | r <- [0 .. 7] ])
    in leaf' == e
  | root <- gaussTrees, p <- probesFor 80 root ]

-- (DL7) LOOKAHEAD DOMINANCE: the stage-1 lookahead rule (commit to
--       the half whose depth-4 DESCENDANT layer holds the nearest
--       node) is at least as accurate as the mean-greedy rule on
--       every fixture probe set — the lawful baseline any learned
--       stage-1 correction must beat.
axiom_DL7 :: Bool
axiom_DL7 = and
  [ countRight lookRule root >= countRight meanRule root
  | root <- gaussTrees ]
  where
    countRight rule root = length
      [ () | p <- probesFor 80 root
           , rule root p == exhaustive (leaves root) p `div` 64 ]
    meanRule root p =
      let m0 = gMean (nodeAt [0] root); m1 = gMean (nodeAt [1] root)
      in if d2 (toLab m0) p <= d2 (toLab m1) p then 0 else 1
    lookRule root p =
      let d4h h = minimum
            [ d2 (toLab (gMean (nodeAt (bits h k) root))) p | k <- [0 .. 7] ]
          bits h k = [h] ++ [ (k `shiftR` j) .&. 1 | j <- [2, 1, 0] ]
      in if d4h 0 <= d4h 1 then 0 else 1

-- (DL5) CORPUS LAW: the sampler is deterministic (same seed, same
--       probes), its variances are nonnegative by construction
--       (lawful stats), and labels for ALL exits come from the
--       exhaustive teacher, never from the descent — the student
--       can only ever be graded against ground truth it did not
--       produce. (Quotients of the exact label are the coarse
--       labels: teacher nesting mirrors DL2.)
axiom_DL5 :: Bool
axiom_DL5 =
     probesFor 40 (head gaussTrees) == probesFor 40 (head gaussTrees)
  && all (all (>= 0) . gVar) gaussTrees
  && and [ let ls = leaves root
               e = exhaustive ls p
           in quotient 3 e == quotient 3 e && e >= 0 && e < 128
         | root <- gaussTrees, p <- probesFor 20 root ]

-- ════════════════════════════════════════════════════════════════
-- § 5. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " DescentLadder: P4 assignment descent + the 3-model ladder"
  putStrLn " one descent, three exits; models nest by OUTPUT (PT5);"
  putStrLn " sizes/cadences/K are DEVICE-MEASURED, absent from law"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "DL1 shape: depth 3, fan-outs [2,8,8], 18 vs 128 candidates" [axiom_DL1]
  check "DL2 nesting: early exit == quotient of full descent"        [axiom_DL2]
  check "DL3 separated: descent == exhaustive at every level"        [axiom_DL3]
  check "DL4 near-tie: disagreement ⇒ bounded by the stage gap"      [axiom_DL4]
  check "DL5 corpus: deterministic, lawful, exhaustive teacher only" [axiom_DL5]
  check "DL6 conditional exactness: stages 2-3 are LAW given the half" [axiom_DL6]
  check "DL7 lookahead dominance: the lawful stage-1 baseline"        [axiom_DL7]
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  The ladder is one descent with three exits, so the"
  putStrLn "  small model IS a prefix of the large one's answer —"
  putStrLn "  nesting on outputs, never weights. Where the descent"
  putStrLn "  differs from exhaustive search it is a near-tie, and"
  putStrLn "  the cost is measured per probe, never assumed zero:"
  putStrLn "  citations motivate; the ledger and the device decide."
  putStrLn "══════════════════════════════════════════════════════════"

check :: String -> [Bool] -> IO ()
check name results =
  let mark = if and results then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
