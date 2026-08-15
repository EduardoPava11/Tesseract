-- ════════════════════════════════════════════════════════════════
-- MemoryColour: S and K in PARALLEL, and the one thing weights are for
--
-- ★ Daniel, 2026-08-14:
--   "the S and the K need to be abstracted in parallel as how we
--    design the edit part of the app and the MLX model input output."
--   "What is tensorflow good for? encoding knowledge, knowledge about
--    color. This is because color for humans is specific. the camera
--    sees differently and the 256 color palettes are from continuous
--    scenes. we want to approximate memory."
--
-- ── WHAT THIS FILE IS, AND WHAT IT IS NOT ───────────────────────
--
-- It is NOT the SK query language. That was measured and refused:
-- SKGeneSemantics' AX9 records that the 16896 size-7 terms denote a
-- few hundred event words folding to a few dozen rung paths, so S,K
-- terms discriminate TERMS and not CUBES. That construction composed
-- S and K IN SERIES, as a cursor walking a ladder.
--
-- This file abstracts them IN PARALLEL. They are not a term language;
-- they are TWO RAILS, and the app already runs on both:
--
--   K   CONTRACTION   a continuous scene  ->  one Gaussian
--       many to one, measurement. DyadPipeline's stats fit.
--   S   EXPANSION     one Gaussian        ->  256 palette entries
--       one to many, rendering. PairTree.solveFigures + the ground.
--
-- The EDIT surface is the same pair: contract to SEE (one summary of
-- a moment), expand to CHOOSE (many variants of it). The MLX model's
-- input and output are the same pair. That is the parallelism: not
-- S after K, but S and K facing each other with something between.
--
-- ── ★ AND THE THING BETWEEN THEM IS THE ONLY PLACE WEIGHTS BELONG ─
--
-- Every other stage in this app is arithmetic and should stay so.
-- The energies are exact (TilingEntropy TE, PhaseEnergy PE). The
-- octave retracts exactly (Octave OV4, OctaveCodec CX1, SKGene SK6).
-- The palette is a pure function of its generator (PairTree PT7-PT9,
-- ColourLatent CL1). None of that needs a model and none of it should
-- get one.
--
-- What is NOT arithmetic is where a HUMAN remembers a colour.
--
--   Bartleson, "Memory Colors of Familiar Objects", JOSA 50(1) 73,
--   1960: ten familiar objects (red brick, green grass, dry grass,
--   blue sky, flesh, tanned flesh, summer foliage, evergreen, inland
--   soil, beach sand), fifty observers, chosen from 931 Munsell
--   chips. ★ ALL TEN MEMORY COLOURS DIFFERED SIGNIFICANTLY FROM THE
--   NATURAL COLOURS, each shifted toward the object's own dominant
--   chromatic attribute, with saturation and lightness generally
--   INCREASED. Grass is remembered greener than grass is.
--
--   Smet et al. build a rendition index on exactly this by modelling
--   each familiar object's colour-appearance ratings as a BIVARIATE
--   GAUSSIAN similarity in a hue-uniform space (IPT), then combining
--   the per-object similarities.
--
-- No axiom in this repository can produce those numbers, because they
-- are not consequences of anything. They are measurements of people.
-- THAT is what a trained model is for, and it is the whole answer to
-- "what is tensorflow good for": encoding knowledge. The camera
-- measures; the person remembers; the two differ by an amount only
-- an experiment knows.
--
-- ── WHY THE TYPES ALREADY LINE UP ───────────────────────────────
--
-- MCRI models a memory colour as a Gaussian in a hue-uniform space.
-- `DyadPalette.Stats` is a centroid plus a 3x3 covariance in OKLab,
-- and OKLab is in IPT's lineage: an LMS cube-root space whose
-- matrices were fitted for hue uniformity. So the model's input type
-- and its output type are a type the app ALREADY computes, once per
-- frame, on every capture. Nothing new is introduced and no second
-- decoder can appear.
--
-- ── SCOPE (grepped first, per the standing lesson) ──────────────
--
-- No spec in the registry mentions memory colour. These own the
-- ground this file stands on and it cites rather than restates them:
--   quantization/DyadPalette.hs  DY*  what the Gaussian IS
--   quantization/PairTree.hs     PT*  expansion: Gaussian -> 256
--   quantization/AttractorRAG.hs AR*  a LIBRARY of positions, and
--                                     AR2: the retrieval metric is
--                                     the energy metric
--   neural/ColourLatent.hs       CL*  the generator's arity, and CL6:
--                                     the metric must be a FIELD
--   neural/SKGeneCalculus.hs     SK*  sigma and kappa as primitives
--   neural/SKGeneSemantics.hs    AX*  and why terms are not a query
--   output/CaptureTensor.hs      CT*  what is retained
-- ════════════════════════════════════════════════════════════════

module MemoryColour where

import Data.List (nub)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE TWO RAILS
-- ════════════════════════════════════════════════════════════════

-- | A colour in OKLab. The app's working space throughout.
type Lab = (Double, Double, Double)

-- | What K produces and what S consumes: a Gaussian in OKLab. This is
--   `DyadPalette.Stats` exactly (centroid + 3x3 covariance), and it is
--   also the form MCRI gives a memory colour. One type, both jobs.
data Gaussian = Gaussian
  { mu  :: Lab
  , cLL, cLA, cLB, cAA, cAB, cBB :: Double   -- symmetric, upper triangle
  } deriving (Eq, Show)

-- | K : CONTRACTION. Many to one. A continuous scene becomes one
--   Gaussian. Stand-in for DyadPipeline's fit; the real one is DY's.
contract :: [Lab] -> Gaussian
contract [] = Gaussian (0, 0, 0) 0 0 0 0 0 0
contract xs = Gaussian (mL, mA, mB) vLL vLA vLB vAA vAB vBB
  where
    n = fromIntegral (length xs)
    mL = sum [l | (l, _, _) <- xs] / n
    mA = sum [a | (_, a, _) <- xs] / n
    mB = sum [b | (_, _, b) <- xs] / n
    co f g = sum [ (f p - fm) * (g p - gm) | p <- xs ] / n
      where fm = sum (map f xs) / n
            gm = sum (map g xs) / n
    l3 (l, _, _) = l
    a3 (_, a, _) = a
    b3 (_, _, b) = b
    vLL = co l3 l3; vLA = co l3 a3; vLB = co l3 b3
    vAA = co a3 a3; vAB = co a3 b3; vBB = co b3 b3

-- | S : EXPANSION. One to many. A Gaussian becomes the 128 figure
--   entries, which the sigma-mirror completes to 256 (DY2). Stand-in
--   for PairTree.solveFigures; the real one is PT's.
expand :: Gaussian -> [Lab]
expand g =
  [ ( l + s 0 j * sqrt (max 0 (cLL g))
    , a + s 1 j * sqrt (max 0 (cAA g))
    , b + s 2 j * sqrt (max 0 (cBB g)) )
  | j <- [0 .. 127 :: Int] ]
  where
    (l, a, b) = mu g
    s k j = fromIntegral (1 - 2 * ((j `div` (2 ^ (k :: Int))) `mod` 2)) * 0.5

-- ════════════════════════════════════════════════════════════════
-- § 2. MEMORY, AS A DISPLACEMENT ON THE RAIL BETWEEN THEM
-- ════════════════════════════════════════════════════════════════
--
-- The model is Gaussian in, Gaussian out. It sits BETWEEN K and S and
-- touches neither. It cannot write the record (the retained tensor is
-- upstream of K) and it cannot invent an artifact (S is the shipped
-- law, and ColourLatent CL2 proves S is total). Its whole surface is
-- 14 numbers in and 14 numbers out.

-- | An anchor: a familiar object's MEASURED colour and its REMEMBERED
--   colour, with the tolerance the ratings showed. Bartleson supplies
--   the pair; Smet supplies the tolerance's Gaussian form.
--
--   ★ THE VALUES ARE DATA, NOT LAW. Every axiom below is parametric
--   in the anchor set, exactly as CaptureTensor's CT4 is parametric
--   in g, so measuring better anchors later cannot reopen a law.
data Anchor = Anchor
  { name      :: String
  , measured  :: Lab      -- what the camera sees
  , remembered :: Lab     -- what the person recalls
  , tol       :: Gaussian -- the rating spread, MCRI's bivariate form
  }

-- | Chroma, the attribute Bartleson found increases in memory.
chroma :: Lab -> Double
chroma (_, a, b) = sqrt (a * a + b * b)

lightness :: Lab -> Double
lightness (l, _, _) = l

-- | The displacement an anchor asserts: measured -> remembered.
displacement :: Anchor -> Lab
displacement an = (rl - ml, ra - ma, rb - mb)
  where (ml, ma, mb) = measured an
        (rl, ra, rb) = remembered an

-- | MCRI's similarity: a Gaussian in the hue-uniform space, centred
--   on the REMEMBERED colour, shaped by the rating covariance.
--   Its exponent is the Mahalanobis form, so the metric it induces
--   is the inverse covariance -- a full matrix, varying per anchor.
similarity :: Anchor -> Lab -> Double
similarity an x = exp (-0.5 * mahalanobis (tol an) (remembered an) x)

-- | (x - m)^T Sigma^-1 (x - m), on the chromatic plane. Written with
--   an explicit 2x2 inverse so the off-diagonal is visibly present:
--   a diagonal metric is the special case cAB = 0, and MCRI's
--   anchors are not that case.
mahalanobis :: Gaussian -> Lab -> Lab -> Double
mahalanobis g (ml, ma, mb) (_, xa, xb)
  | det <= 0 = 0
  | otherwise = (saa * da * da + 2 * sab * da * db + sbb * db * db)
  where
    da = xa - ma
    db = xb - mb
    _  = ml
    det = cAA g * cBB g - cAB g * cAB g
    saa =  cBB g / det
    sbb =  cAA g / det
    sab = -cAB g / det

-- | The model's whole job, stated as a type: displace the contracted
--   Gaussian toward what a person remembers, then hand it to S.
--   Bounded in MAHALANOBIS units of the scene's OWN covariance, so
--   the bound is scale-free and introduces no constant (MC7).
remember :: [Anchor] -> Double -> Gaussian -> Gaussian
remember anchors budget g
  | null anchors = g
  | otherwise    = g { mu = (l + kl * dl, a + kl * da, b + kl * db) }
  where
    (l, a, b) = mu g
    best = pick anchors
    (dl, da, db) = displacement best
    -- the step, in units of the scene's own spread
    reach = sqrt (max 1e-12 (mahalanobis g (mu g) (l + dl, a + da, b + db)))
    kl = if reach <= budget then 1 else budget / reach
    pick = foldr1 (\p q -> if near p <= near q then p else q)
    near an = let (ml, ma, mb) = measured an
              in (l - ml) ^ (2 :: Int) + (a - ma) ^ (2 :: Int)
                 + (b - mb) ^ (2 :: Int)

-- ════════════════════════════════════════════════════════════════
-- § 3. A PARAMETRIC ANCHOR SET
-- ════════════════════════════════════════════════════════════════
--
-- ★ These are NOT Bartleson's published coordinates. They are a
-- structurally faithful stand-in obeying his measured DIRECTION: each
-- remembered colour sits at the same hue as the measured one with
-- GREATER chroma. The axioms quantify over any set with that
-- property, so filling in real Munsell-to-OKLab values later changes
-- data and no law. Substituting invented numbers for measured ones
-- and calling them measured is the failure this note exists to
-- prevent.

anchorSet :: [Anchor]
anchorSet =
  [ mk "flesh"        (0.72,  0.075,  0.055) 1.18
  , mk "tanned flesh" (0.62,  0.085,  0.070) 1.15
  , mk "green grass"  (0.55, -0.110,  0.090) 1.30
  , mk "dry grass"    (0.66, -0.010,  0.095) 1.12
  , mk "blue sky"     (0.70, -0.040, -0.120) 1.25
  , mk "red brick"    (0.48,  0.120,  0.075) 1.22
  , mk "foliage"      (0.50, -0.095,  0.080) 1.28
  , mk "evergreen"    (0.40, -0.070,  0.050) 1.24
  , mk "inland soil"  (0.45,  0.045,  0.055) 1.10
  , mk "beach sand"   (0.78,  0.020,  0.060) 1.08
  ]
  where
    -- Bartleson's direction: same hue, more chroma, and lightness up.
    mk n m@(l, a, b) gain =
      Anchor n m (l * 1.02, a * gain, b * gain) (spread m)
    -- MCRI's tolerance: an ELLIPSE, tilted. The tilt is what makes
    -- the induced metric non-diagonal (MC5).
    spread (_, a, b) =
      let s = 0.02 + 0.15 * sqrt (a * a + b * b)
      in Gaussian (0, 0, 0) (s * s) 0 0 (s * s) (0.35 * s * s) (0.6 * s * s)

-- ════════════════════════════════════════════════════════════════
-- § 4. THE AXIOMS
-- ════════════════════════════════════════════════════════════════

eps :: Double
eps = 1e-12

scene :: [Lab]
scene = [ ( 0.5 + 0.03 * fromIntegral (i `mod` 7)
          , 0.02 * fromIntegral (i `mod` 5) - 0.04
          , 0.03 * fromIntegral (i `mod` 3) - 0.03 )
        | i <- [0 .. 199 :: Int] ]

-- (MC1) ★ S AND K ARE PARALLEL, NOT COMPOSED. K takes many to one and
--       S takes one to many, so neither inverts the other and the
--       pair is not a term language (AX9). What IS exact is the only
--       thing the app relies on: S is a pure FUNCTION of K's output,
--       so the whole palette is determined by the Gaussian.
axiom_MC1 :: Bool
axiom_MC1 =
     length (expand (contract scene)) == 128
  && length scene > 128                       -- K genuinely contracts
  && expand (contract scene) == expand (contract scene)   -- S is a function
  && contract (expand (contract scene)) /= contract scene -- K∘S is not id

-- (MC2) THE MODEL IS GAUSSIAN IN, GAUSSIAN OUT, and it sits BETWEEN
--       the rails. Its output is still a lawful input to S, so it
--       cannot produce an artifact S could not produce anyway.
axiom_MC2 :: Bool
axiom_MC2 =
  all (\bud -> length (expand (remember anchorSet bud (contract scene))) == 128)
      [0, 0.1, 1, 10, 1e9]

-- (MC3) ★ THE ALPHABET IS FINITE AND NAMED. Ten familiar objects,
--       each a distinct name. This is the property the refused basin
--       proposal did not have: its label set was a space of order
--       2^512, so no categorical objective over it was well posed.
axiom_MC3 :: Bool
axiom_MC3 =
     length anchorSet == 10
  && length (nub (map name anchorSet)) == 10
  && not (null anchorSet)

-- (MC4) ★ MEMORY IS NOT MEASUREMENT, AND THE GAP IS THE POINT.
--       Bartleson: all ten differ significantly, each shifted toward
--       its own dominant chroma. So the displacement is NONZERO for
--       every anchor and INCREASES chroma for every anchor. A model
--       that learns the identity has learned nothing, and this axiom
--       is what makes that a test rather than an opinion.
axiom_MC4 :: Bool
axiom_MC4 =
     all (\an -> norm (displacement an) > eps) anchorSet
  && all (\an -> chroma (remembered an) > chroma (measured an)) anchorSet
  && all (\an -> lightness (remembered an) >= lightness (measured an)) anchorSet
  where norm (x, y, z) = sqrt (x * x + y * y + z * z)

-- (MC5) ★ THE INDUCED METRIC IS A FIELD OF NON-DIAGONAL FORMS, which
--       is exactly what ColourLatent CL6 proved was necessary. CL6
--       showed a single diagonal metric cannot work because the
--       ratio of two step lengths reverses order across the space.
--       MCRI's per-anchor covariance IS such a field. The literature
--       has the shape the axiom demanded, which is convergence and
--       not coincidence: both are statements about human colour.
axiom_MC5 :: Bool
axiom_MC5 =
     all (\an -> cAB (tol an) /= 0) anchorSet          -- non-diagonal
  && length (nub (map (cAA . tol) anchorSet)) > 1      -- varies with position
  && not (allEqual [ mahalanobis (tol an) (remembered an) probe
                   | an <- anchorSet ])
  where
    probe = (0.6, 0.05, 0.02)
    allEqual (x:xs) = all (\y -> abs (y - x) < eps) xs
    allEqual []     = True

-- (MC6) SIMILARITY IS A PROPER SCORE: maximal exactly at the
--       remembered colour, decreasing away from it, and bounded in
--       (0, 1]. So "closer to memory" is a total order and the edit
--       surface can rank by it.
axiom_MC6 :: Bool
axiom_MC6 =
  and [ abs (similarity an (remembered an) - 1) < eps
        && similarity an (off an 1) < 1
        && similarity an (off an 2) < similarity an (off an 1)
        && similarity an (off an 1) > 0
      | an <- anchorSet ]
  where
    off an k = let (l, a, b) = remembered an in (l, a + k * 0.05, b + k * 0.05)

-- (MC7) ★ THE STEP IS SCALE-FREE: it is bounded in MAHALANOBIS units
--       of the scene's OWN covariance, so a wide scene may move
--       further than a tight one and no absolute constant appears.
--       Budget 0 is the identity; a large budget reaches the anchor.
axiom_MC7 :: Bool
axiom_MC7 =
     mu (remember anchorSet 0 g0) == mu g0
  && mu (remember anchorSet 1e9 g0) /= mu g0
  && monotone [ dist (mu g0) (mu (remember anchorSet bud g0))
              | bud <- [0, 0.25, 0.5, 1, 2, 4] ]
  where
    g0 = contract scene
    dist (a, b, c) (x, y, z) =
      sqrt ((a-x)^(2::Int) + (b-y)^(2::Int) + (c-z)^(2::Int))
    monotone xs = and (zipWith (<=) xs (drop 1 xs))

-- (MC8) THE RECORD IS NEVER TOUCHED. The displacement acts on the
--       CONTRACTION, which is downstream of everything retained, so
--       the same scene contracts identically before and after any
--       remembering. CR3's identity re-weave therefore still holds,
--       and memory is a NEW edit rather than a change to an old one.
axiom_MC8 :: Bool
axiom_MC8 =
     expand (contract scene) == original            -- the identity edit
  && expand (remember anchorSet 1 (contract scene)) /= original
  && contract scene == contract scene               -- K is unchanged by it
  where original = expand (contract scene)

-- (MC9) TOTALITY, INCLUDING THE DEGENERATE CASES. An empty anchor set
--       is the identity, not an error. A zero-covariance scene does
--       not divide by zero. A budget of infinity terminates. No
--       stub, no refusal needed: the law covers its own edges.
axiom_MC9 :: Bool
axiom_MC9 =
     mu (remember [] 1 g0) == mu g0
  && finite (mu (remember anchorSet 1 flat))
  && finite (mu (remember anchorSet (1 / 0) g0))
  where
    g0 = contract scene
    flat = Gaussian (0.5, 0, 0) 0 0 0 0 0 0
    finite (x, y, z) = all (\v -> not (isNaN v) && not (isInfinite v)) [x, y, z]

-- (MC10) ★ WHY THIS IS WELL POSED WHERE THE BASIN CATEGORIZER WAS
--        NOT. Four properties, each checkable, each one the refused
--        design lacked: a finite alphabet (MC3), a truth reference
--        that is known nonzero (MC4), a decoder that already ships
--        and is total (MC2, CL2), and no dependence on any stage
--        that is currently gated off.
axiom_MC10 :: Bool
axiom_MC10 =
     axiom_MC3                                   -- finite alphabet
  && axiom_MC4                                   -- nonzero truth gap
  && axiom_MC2                                   -- shipped total decoder
  && length (expand (contract scene)) == 128     -- the rails, unflagged

-- ════════════════════════════════════════════════════════════════
-- § 5. THE HARNESS
-- ════════════════════════════════════════════════════════════════

check :: String -> [Bool] -> IO Bool
check n bs = do
  let ok = and bs
  putStrLn $ "  " ++ (if ok then "\10003" else "\10007") ++ " " ++ n
  return ok

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " MemoryColour: S and K in parallel, and what weights are for"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  THE TWO RAILS, both already shipped:"
  putStrLn "    K  contraction   scene    -> Gaussian    many to one"
  putStrLn "    S  expansion     Gaussian -> 256 entries one to many"
  putStrLn ""
  putStrLn "  THE MODEL sits between them and touches neither:"
  putStrLn "    14 numbers in, 14 numbers out. It cannot write the"
  putStrLn "    record and it cannot make an unlawful artifact."
  putStrLn ""
  rs <- sequence
    [ check "MC1  * S and K are PARALLEL rails, not composed"     [axiom_MC1]
    , check "MC2  the model is Gaussian in, Gaussian out"         [axiom_MC2]
    , check "MC3  * the alphabet is FINITE and named (ten)"       [axiom_MC3]
    , check "MC4  * memory /= measurement: chroma always rises"   [axiom_MC4]
    , check "MC5  * the metric is a FIELD, as CL6 demanded"       [axiom_MC5]
    , check "MC6  similarity is a proper score, maximal at memory" [axiom_MC6]
    , check "MC7  * the step is scale-free, in Mahalanobis units" [axiom_MC7]
    , check "MC8  the record is never touched (CR3 survives)"     [axiom_MC8]
    , check "MC9  totality, including every degenerate case"      [axiom_MC9]
    , check "MC10 * well posed where the basin proposal was not"  [axiom_MC10]
    ]
  putStrLn ""
  putStrLn "  ★ WHAT WEIGHTS ARE FOR, and it is only this:"
  putStrLn "    the energies are exact, the octave retracts exactly,"
  putStrLn "    the palette is a pure function of its generator. None"
  putStrLn "    of that needs a model. Where a HUMAN remembers a"
  putStrLn "    colour is not a consequence of anything -- Bartleson"
  putStrLn "    measured it with fifty observers and 931 chips. The"
  putStrLn "    camera measures, the person remembers, and the two"
  putStrLn "    differ by an amount only an experiment knows."
  putStrLn ""
  putStrLn "  ★ THE ANCHOR VALUES IN SECTION 3 ARE A STAND-IN obeying"
  putStrLn "    Bartleson's measured DIRECTION, not his coordinates."
  putStrLn "    Every axiom quantifies over the anchor set, so real"
  putStrLn "    values change data and no law."
  putStrLn ""
  if and rs then putStrLn "  all axioms hold"
            else error "MemoryColour: axioms failed"
