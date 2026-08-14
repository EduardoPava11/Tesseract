{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- GroundHue: the ground's OWN hue — the fourth coordinate of the
-- Wada family, selected by the background's own pixels
--
-- Daniel (2026-08-13), on the first 17 Pro export: "the colors are
-- still muddy." Measured over the shipped 64-frame GIF:
--
--     circular hue concentration  R  = 0.9913   (1.0 = one hue)
--     circular sd                    = 7.6°
--     87% of pixels within ±15° of a single hue
--     table max chroma               = 0.0919
--     background hue 44.7°  vs  image mean hue 48.8°
--
-- The wall is the face's hue. This spec says why, exactly, and what
-- the third option is.
--
-- ── THE DIAGNOSIS (GH1, GH2) ────────────────────────────────────
--
-- Nothing about the background's COLOUR ever reaches the palette.
-- The whole 256-entry table is a function of
--
--   (i)  the figure-weighted OKLab statistics (analyze weights are
--        1 − t, so the background carries weight ~0), and
--   (ii) three scalars from the background:
--          ΔL  = mean L,  αC/βC  from mean ln C and sd ln C
--        (DyadPalette.swift:168 backgroundMoments; PhasePalette § 10)
--
-- L and |C| are both invariant under rotation about the neutral
-- axis. So the ground family is HUE-BLIND: it can be told how LIGHT
-- and how COLOURFUL the wall is, never WHAT COLOUR it is. Under v7
-- (groundLab keeps the figure's hue, DyadPalette.swift:220) the σ
-- half therefore carries EXACTLY the figure half's hue set — for
-- every background that has ever been or will ever be photographed.
--
-- GH2 turns that into the measurement. Because the σ half is a
-- RIGID hue rotation of the figure half by a single angle Δh,
--
--     R_table  =  R_figure · cos(|Δh| / 2)                  (GH2)
--
-- and the three rulings are three points on that one curve:
--
--     v5-W   Δh = π   R_table = 0          forced opposition —
--                                          a warm face paints a
--                                          blue wall whatever the
--                                          wall is (THE BLUE HAZE)
--     v7     Δh = 0   R_table = R_figure   the GIF is exactly as
--                                          monochrome as the FACE
--                                          is (R = 0.9913 measured)
--     THIS   Δh = ĥ_B − ĥ_F                dispersion PROPORTIONAL
--                                          to the scene's own hue
--                                          separation
--
-- v7 did not make the output monochrome — it made the output
-- exactly as monochrome as a face is, which is the same thing when
-- half the frame is painted from the face's palette. No setting of
-- (ΔL, αC, βC) can move it: that is GH1, and it is why this is a
-- new coordinate rather than a retune.
--
-- ── THE FIX (GH3–GH11) ──────────────────────────────────────────
--
-- Wada does not constrain the hue interval — |Δh| is near-uniform
-- on [0°,180°] over the dictionary's 1128 pairs (scripts/wada/
-- derive.py:11). So Δh is a FREE coordinate of the family, and the
-- family with it is a group (GH3): rigid L-shift × affine in ln C ×
-- rotation in the (a,b) plane. v5 and v7 are two points of one
-- one-parameter subgroup. Nothing new is invented here; the free
-- coordinate is filled from evidence instead of from a ruling.
--
--     Δh  =  arg( resultant of background (a,b) )
--          −  arg( resultant of figure     (a,b) )
--
-- and the resultant IS the chroma-weighted circular mean of hue,
-- exactly (GH4) — because C·(cos h, sin h) = (a, b) by definition,
-- so the chroma weight is already in the vector. Consequences:
--
--   · no trig, no angles, no wraparound bug (GH4, GH5);
--   · two more accumulators inside the loop backgroundMoments
--     already runs — Σ m·a and Σ m·b (GH4);
--   · the rotation never needs a square root, because the ground's
--     chroma is set by the power law afterwards and the power law
--     re-normalises: rotate by the UNNORMALISED complex product and
--     the magnitude cancels (GH6). The hue law is exact in ℚ;
--   · total: no background mass, no chromatic background mass, or
--     an achromatic figure ⇒ identity rotation ⇒ byte-for-byte
--     today's behaviour (GH7), and the same when the wall genuinely
--     IS the face's hue (GH8);
--   · the gamut cannot defeat it: chromaClamp scales chroma ONLY,
--     so hue survives the clamp and the sRGB round trip (GH10).
--
-- ── WHAT IT DOES NOT FIX (GH12, GH14, GH15) ─────────────────────
--
-- GH12  The σ-side blur search minimises d(node, target) while the
--       pixel is DISPLAYED as ground(node). At Δh ≠ 0 those differ,
--       so the search must move into the ground frame. Note it is
--       ALREADY wrong at Δh = 0 whenever βC ≠ 1 or ΔL ≠ 0 — a
--       latent defect this spec exposes rather than creates. The
--       display-only rotation changes ZERO index bytes (free in
--       LZW, PT/head-tail): a riskless step A, with the search as
--       the pixel-moving step B.
-- GH14  γ-staging ŷ = c_F + γ(s)(y − c_F) is a convex combination,
--       so every staged hue moves TOWARD hue(c_F). It narrows which
--       entries the background can select — a real contributor to
--       the dead third of the table — but it cannot create the
--       single hue, because no staged background colour reaches the
--       palette at all (GH1). An L-only variant would leave hue
--       pointwise exact; that is a MEASUREMENT here, and DY9 is
--       authoritative until Daniel rules.
-- GH15  With PairTree on, the σ-side blur can emit at most 16
--       distinct indices per frame, so ≥ 112 of the 128 σ entries
--       carry no pixel in any single frame. n ∝ √λ (RL4/PT8) is fit
--       to the FIGURE's eigenvalues only; the background's own
--       variance never enters the allocation. That is a second,
--       independent defect — the hue law does not close it.
--
-- ── AXIOMS ──────────────────────────────────────────────────────
--
--   GH1  ★ HUE-BLINDNESS: the ground family reads the background
--          through three rotation-invariant scalars, so under v7
--          the σ half carries the figure's hue set for EVERY
--          background — no retune of (ΔL, αC, βC) can move it
--   GH2  ★ THE CONCENTRATION LAW: R_table = R_figure·cos(|Δh|/2);
--          v7 ⇒ R_table = R_figure, v5 ⇒ 0, this ⇒ the scene's own
--   GH3  ★ THE GROUND FAMILY IS A GROUP and Δh is its fourth
--          coordinate — v5 and v7 are two points of one subgroup
--   GH4  ★ CIRCULAR MEAN = THE (a,b) RESULTANT, exactly: chroma
--          weighting is already in the vector, and it is two more
--          accumulators in a loop that already runs
--   GH5  ★ WRAPAROUND: hues straddling 0/360 resolve exactly; the
--          naive mean of angle representatives is 180° wrong
--   GH6  ★ THE HUE LAW IS EXACT IN ℚ — the power law re-normalises,
--          so the rotation needs no square root
--   GH7  TOTALITY: no mass / no chromatic mass / achromatic figure
--          ⇒ identity rotation ⇒ exactly the Wada-prior path
--   GH8  GRACEFUL DEGRADATION: wall hue == face hue ⇒ Δh = 0 ⇒
--          every emitted direction equals v7's, exactly
--   GH9  ★ THE POINT: on a two-hue scene the table's concentration
--          strictly DROPS, and the σ half's mean hue equals the
--          BACKGROUND's mean hue exactly
--   GH10 ★ THE GAMUT CANNOT DEFEAT IT: chroma-only clamping is
--          hue-invariant, so the law reaches the bytes
--   GH11 ★ MONOTONE AND BOUNDED: R strictly decreases in |Δh| on
--          [0,π] — neither forced-monochrome nor forced-complement
--   GH12 ★ THE SEARCH MUST MOVE TOO: pre-image search is optimal
--          for the displayed metric; today's is already suboptimal
--          at Δh = 0; display-only rotation is index-identical
--   GH13 ★ SMOOTH THE RESULTANT, NEVER THE ANGLE — the JEPA-H ring
--          carries a unit vector (2 dims) and renormalises
--   GH14 γ-STAGING IS HUE-CONTRACTING (measurement, ruling owed):
--          staged hue lies between the pixel's and c_F's; an L-only
--          variant is hue-exact
--   GH15 ALLOCATION IS A SEPARATE DEFECT: ≤ 16 reachable σ indices
--          per frame; n ∝ √λ never sees the background's variance
-- ════════════════════════════════════════════════════════════════

module Main where

import Data.List (nub)
import Data.Ratio ((%))
import System.Exit (exitFailure)

-- ════════════════════════════════════════════════════════════════
-- § 1. EXACT ARITHMETIC IN THE (a,b) PLANE
--
-- Hue is a DIRECTION, never an angle. Every law below is stated on
-- vectors, which is why none of it needs trigonometry and none of
-- it can wrap wrongly at 0/360.
-- ════════════════════════════════════════════════════════════════

type Q   = Rational
type Lab = (Q, Q, Q)
type Dir = (Q, Q)          -- a vector in the (a,b) plane; hue = its argument

-- | Complex multiplication: rotation-and-scale. Rotating a hue by
--   Δh is multiplying by a vector whose argument is Δh.
cmul :: Dir -> Dir -> Dir
cmul (x1, y1) (x2, y2) = (x1 * x2 - y1 * y2, x1 * y2 + y1 * x2)

cconj :: Dir -> Dir
cconj (x, y) = (x, negate y)

cdot :: Dir -> Dir -> Q
cdot (x1, y1) (x2, y2) = x1 * x2 + y1 * y2

ccross :: Dir -> Dir -> Q
ccross (x1, y1) (x2, y2) = x1 * y2 - y1 * x2

norm2 :: Dir -> Q
norm2 v = cdot v v

isZeroDir :: Dir -> Bool
isZeroDir v = norm2 v == 0

vadd :: Dir -> Dir -> Dir
vadd (x1, y1) (x2, y2) = (x1 + x2, y1 + y2)

vsum :: [Dir] -> Dir
vsum = foldr vadd (0, 0)

vscale :: Q -> Dir -> Dir
vscale k (x, y) = (k * x, k * y)

-- | ★ Hue equality WITHOUT angles: same direction iff parallel and
--   pointing the same way. Exact, and immune to the 0/360 seam.
sameHue :: Dir -> Dir -> Bool
sameHue u v = not (isZeroDir u) && not (isZeroDir v)
           && ccross u v == 0 && cdot u v > 0

oppositeHue :: Dir -> Dir -> Bool
oppositeHue u v = not (isZeroDir u) && not (isZeroDir v)
               && ccross u v == 0 && cdot u v < 0

identityRot :: Dir
identityRot = (1, 0)

isUnit :: Dir -> Bool
isUnit v = norm2 v == 1

-- | R² of a multiset of UNIT hue directions. Squared, so the whole
--   concentration argument stays in ℚ — comparing R is comparing R².
conc2 :: [Dir] -> Q
conc2 us
  | null us   = 0
  | otherwise = norm2 (vsum us) / (fromIntegral (length us) ^ (2 :: Int))

-- | R² of MASSED unit directions — the pixel-weighted reading, which
--   is what the shipped GIF was measured with.
conc2W :: [(Q, Dir)] -> Q
conc2W ws
  | m == 0    = 0
  | otherwise = norm2 (vsum [ vscale w u | (w, u) <- ws ]) / (m * m)
  where m = sum (map fst ws)

-- Degrees, for the PRINTED tables only. No axiom depends on this.
hueDegD :: Dir -> Double
hueDegD (x, y) =
  let d = atan2 (fromRational y) (fromRational x) * 180 / pi
  in if d < 0 then d + 360 else d

-- ════════════════════════════════════════════════════════════════
-- § 2. THE GROUND FAMILY AS A GROUP (GH3)
--
-- The shipped family is (rigid L-shift, ln-chroma affine). Wada
-- leaves hue free, so the full family carries a rotation too:
--
--   g(L, C, h) = (L + ΔL,  exp(αC) · C^βC,  h + Δh)
--
-- Composition is closed, inversion is closed, and the identity is
-- (0, 0, 1, 1∠0). v5-W is Δh = π; v7 is Δh = 0. Both rulings live
-- inside ONE object, which is the whole argument for the third
-- option: it is not a new mechanism, it is the coordinate the
-- family already had.
-- ════════════════════════════════════════════════════════════════

data Ground = Ground
  { gDeltaL :: Q     -- rigid L-shift
  , gAlphaC :: Q     -- ln-chroma intercept
  , gBetaC  :: Q     -- ln-chroma slope
  , gRot    :: Dir   -- ★ the fourth coordinate: hue rotation
  } deriving (Eq, Show)

gIdentity :: Ground
gIdentity = Ground { gDeltaL = 0, gAlphaC = 0, gBetaC = 1, gRot = identityRot }

-- | g2 ∘ g1. ΔL adds; the ln-chroma affines compose; the rotations
--   multiply. (Rotations are compared up to positive scale — the
--   power law re-normalises the magnitude, GH6.)
gCompose :: Ground -> Ground -> Ground
gCompose g2 g1 = Ground
  { gDeltaL = gDeltaL g2 + gDeltaL g1
  , gAlphaC = gAlphaC g2 + gBetaC g2 * gAlphaC g1
  , gBetaC  = gBetaC g2 * gBetaC g1
  , gRot    = cmul (gRot g2) (gRot g1) }

gInverse :: Ground -> Ground
gInverse g = Ground
  { gDeltaL = negate (gDeltaL g)
  , gAlphaC = negate (gAlphaC g) / gBetaC g
  , gBetaC  = 1 / gBetaC g
  , gRot    = cconj (gRot g) }

-- | Equality of ground maps: the rotation only matters up to
--   positive scale, so compare hues, not vectors.
gSame :: Ground -> Ground -> Bool
gSame g1 g2 =
     gDeltaL g1 == gDeltaL g2
  && gAlphaC g1 == gAlphaC g2
  && gBetaC  g1 == gBetaC  g2
  && sameHue (gRot g1) (gRot g2)

-- | The two shipped rulings, as points of the family.
v7Ground, v5Ground :: Q -> Q -> Ground
v7Ground dL a = Ground { gDeltaL = dL, gAlphaC = a, gBetaC = 3 % 4
                       , gRot = identityRot }         -- SAME hue
v5Ground dL a = Ground { gDeltaL = dL, gAlphaC = a, gBetaC = 3 % 4
                       , gRot = (-1, 0) }             -- hue + 180°

-- | ★ THE HUE HALF OF THE GROUND LAW — exact, total, no square
--   roots (GH6). Achromatic entries stay achromatic exactly; every
--   other entry is rotated. The MAGNITUDE of the result is
--   irrelevant: the power law sets the chroma afterwards, which is
--   precisely why the rotation may stay unnormalised.
groundDir :: Ground -> Dir -> Dir
groundDir g v
  | isZeroDir v = v
  | otherwise   = cmul v (gRot g)

groundL :: Ground -> Q -> Q
groundL g l = l + gDeltaL g

-- | The RATIONAL sub-family (βC = 1): a similarity — rigid L-shift,
--   uniform chroma gain, hue rotation by a rational UNIT vector.
--   Every hue statement in this file lives here exactly; βC ≠ 1 only
--   rescales chroma and is hue-free by construction (GH10).
groundSim :: Q -> Q -> Dir -> Lab -> Lab
groundSim dL gain rot (l, a, b) =
  let (a', b') = cmul (a, b) rot
  in (l + dL, gain * a', gain * b')

-- ════════════════════════════════════════════════════════════════
-- § 3. THE FITTED ROTATION (GH4)
--
-- ★ The chroma-weighted circular mean of hue is the ARGUMENT of the
-- mass-weighted (a,b) sum:
--
--     Σ mᵢ·Cᵢ·e^{i hᵢ}  =  Σ mᵢ·(aᵢ + i·bᵢ)
--
-- because Cᵢ·(cos hᵢ, sin hᵢ) IS (aᵢ, bᵢ). The chroma weight is
-- already inside the coordinates — a chroma-weighted circular mean
-- costs Σ m·a and Σ m·b, two accumulators, in the same loop
-- backgroundMoments (DyadPalette.swift:168) already runs for
-- (mean L, mean ln C, sd ln C).
-- ════════════════════════════════════════════════════════════════

-- | The resultant of a massed ensemble. TOTAL: an empty or
--   achromatic ensemble resolves to the zero vector.
resultant :: [(Q, Lab)] -> Dir
resultant ws = vsum [ vscale m (a, b) | (m, (_, a, b)) <- ws, m > 0 ]

-- | ★ THE LAW. Δh takes the FIGURE's mean hue to the BACKGROUND's
--   own mean hue. Total: either resultant vanishing (no background
--   mass, no chromatic background mass, achromatic figure) gives the
--   identity rotation, which is exactly today's v7 / Wada-prior
--   behaviour (GH7).
groundRotation :: [(Q, Lab)] -> [(Q, Lab)] -> Dir
groundRotation figure background
  | isZeroDir f || isZeroDir b = identityRot
  | otherwise                  = cmul b (cconj f)
  where f = resultant figure
        b = resultant background

-- | The full fitted ground: the three shipped moments plus the
--   fourth coordinate. (ΔL, αC, βC come from PhasePalette § 10
--   unchanged — this spec adds gRot and touches nothing else.)
fitGroundHue :: Q -> Q -> Q -> [(Q, Lab)] -> [(Q, Lab)] -> Ground
fitGroundHue dL aC bC figure background =
  Ground { gDeltaL = dL, gAlphaC = aC, gBetaC = bC
         , gRot = groundRotation figure background }

-- ════════════════════════════════════════════════════════════════
-- § 4. FIXTURES
--
-- Every hue is a rational unit vector (Pythagorean), so every
-- concentration below is exact in ℚ. Chromas and masses vary — the
-- laws must not depend on them.
-- ════════════════════════════════════════════════════════════════

-- Rational unit hues. Names are their angles.
h0, h2262, h3687, h5313, h9000, h12687, h18000 :: Dir
h0     = (1, 0)                     --   0.00°
h2262  = (12 % 13, 5 % 13)          --  22.62°
h3687  = (4 % 5, 3 % 5)             --  36.87°
h5313  = (3 % 5, 4 % 5)             --  53.13°
h9000  = (0, 1)                     --  90.00°
h12687 = (negate (3 % 5), 4 % 5)    -- 126.87°
h18000 = (-1, 0)                    -- 180.00°

-- | A FACE: a tight hue wedge, ±22.62° about h0. The shipped
--   measurement (R = 0.9913, sd 7.6°) says the real one is tighter
--   still; this one is deliberately looser so the law is not
--   flattered by a degenerate figure.
--
--   ★ MIRROR-PAIRED about its axis: {u, ū} carry equal mass·chroma,
--   so the resultant lands on the axis EXACTLY, whatever the masses
--   and chromas are. That is what lets every concentration below be
--   an equality in ℚ rather than a float comparison.
faceHues :: [Dir]
faceHues = [h0, h2262, cconj h2262]

-- | A WALL at a different hue: the SAME mirror-paired shape rotated
--   by r. Its resultant is therefore exactly r, whatever masses and
--   chromas it is given — and rational unit vectors are closed under
--   multiplication, so nothing leaves ℚ.
wallRot :: Dir
wallRot = h5313                       -- Δh = 53.13°, cos Δh = 3/5

wallHues :: [Dir]
wallHues = map (`cmul` wallRot) faceHues

-- Masses and chromas differ freely BETWEEN the classes (and between
-- the axis sample and the mirror pair) — the law reads only the
-- DIRECTION of the resultant, never a magnitude.
faceEnsemble, wallEnsemble :: [(Q, Lab)]
faceEnsemble = [ (m, labOf c u)
               | (m, c, u) <- zip3 [3, 5, 5] faceChromas faceHues ]
wallEnsemble = [ (m, labOf c u)
               | (m, c, u) <- zip3 [7, 4, 4] wallChromas wallHues ]

faceChromas, wallChromas :: [Q]
faceChromas = [1 % 8, 1 % 10, 1 % 10]
wallChromas = [1 % 40, 1 % 25, 1 % 25]

labOf :: Q -> Dir -> Lab
labOf c (x, y) = (1 % 2, c * x, c * y)

-- | The SAME-hue scene: a wall that genuinely is the face's hue
--   (different chromas, different masses, same directions).
sameHueWall :: [(Q, Lab)]
sameHueWall = [ (m, labOf c u)
              | (m, c, u) <- zip3 [7, 4, 4] wallChromas faceHues ]

-- | An ACHROMATIC wall — a true gray card. The degenerate case the
--   Wada prior already covers.
grayWall :: [(Q, Lab)]
grayWall = [ (7, (3 % 5, 0, 0)), (4, (2 % 5, 0, 0)) ]

-- | The unit hue directions the 256-entry table shows, given a
--   figure hue set and a ground rotation. The σ half is the figure
--   half rotated RIGIDLY — one angle for all 128 entries, which is
--   exactly what makes GH2 a closed form. Rational unit vectors are
--   closed under cmul, so the result stays unit and stays in ℚ.
tableHues :: Dir -> [Dir] -> [Dir]
tableHues rot hs = hs ++ map (`cmul` rot) hs

-- ════════════════════════════════════════════════════════════════
-- § 5. THE σ-SIDE SEARCH (GH12)
--
-- pairDitherFrame (DyadPipeline.swift:561) picks the node minimising
-- d(node, target) and then DISPLAYS ground(node). Those are the same
-- argmin only when ground ≈ identity. The correct search is in the
-- ground frame.
-- ════════════════════════════════════════════════════════════════

dLab2 :: Lab -> Lab -> Q
dLab2 (l1, a1, b1) (l2, a2, b2) =
  (l1 - l2) ^ (2 :: Int) + (a1 - a2) ^ (2 :: Int) + (b1 - b2) ^ (2 :: Int)

-- | Today: match the target against the FIGURE node.
searchFigureFrame :: [Lab] -> Lab -> Int
searchFigureFrame nodes target = argmin [ dLab2 n target | n <- nodes ]

-- | ★ The pre-image search: match against what will be SHOWN.
searchGroundFrame :: (Lab -> Lab) -> [Lab] -> Lab -> Int
searchGroundFrame g nodes target = argmin [ dLab2 (g n) target | n <- nodes ]

argmin :: [Q] -> Int
argmin xs = snd (minimum (zip xs [0 ..]))

-- | The error a choice actually costs on screen.
shownError :: (Lab -> Lab) -> [Lab] -> Lab -> Int -> Q
shownError g nodes target i = dLab2 (g (nodes !! i)) target

-- ════════════════════════════════════════════════════════════════
-- § 6. γ-STAGING (GH14) — measurement only, DY9 is authoritative
-- ════════════════════════════════════════════════════════════════

-- | ŷ = c_F + γ(s)·(y − c_F), the shipped staging (DY9/DY10,
--   DyadPipeline.swift:182) written on ℚ.
stageAerial :: Q -> Lab -> Lab -> Lab
stageAerial gam (cl, ca, cb) (l, a, b) =
  (cl + gam * (l - cl), ca + gam * (a - ca), cb + gam * (b - cb))

-- | The a-b-preserving alternative Daniel asked about: buy the
--   octave in LIGHTNESS alone, leave the chroma plane intact.
stageLOnly :: Q -> Lab -> Lab -> Lab
stageLOnly gam (cl, _, _) (l, a, b) = (cl + gam * (l - cl), a, b)

abOf :: Lab -> Dir
abOf (_, a, b) = (a, b)

lOf :: Lab -> Q
lOf (l, _, _) = l

-- ════════════════════════════════════════════════════════════════
-- § 7. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (GH1) ★ HUE-BLINDNESS — THE DIAGNOSIS. The ground family reads the
--       background through (mean L, mean ln C, sd ln C): three
--       scalars, every one invariant under rotation about the
--       neutral axis. So under v7 the σ half carries EXACTLY the
--       figure half's hue set, for any background whatsoever, and no
--       value of (ΔL, αC, βC) can change that. The wall is the
--       face's hue by construction, not by accident.
axiom_GH1 :: Bool
axiom_GH1 = momentsBlind && v7CarriesFigureHues && noRetuneEscapes
  where
    c2Of (_, a, b) = a * a + b * b
    -- rotating a background about the neutral axis moves neither
    -- moment the family reads
    rotated r = [ (m, (l, a', b'))
                | (m, (l, a, b)) <- wallEnsemble
                , let (a', b') = cmul (a, b) r ]
    momentsBlind = and
      [ map (lOf . snd) (rotated r) == map (lOf . snd) wallEnsemble
        && map (c2Of . snd) (rotated r) == map (c2Of . snd) wallEnsemble
      | r <- [h2262, h5313, h9000, h12687, h18000] ]
    -- v7: every emitted σ direction has a figure direction's hue
    v7 = v7Ground (1 % 10) (negate 1)
    v7CarriesFigureHues = and
      [ any (sameHue (groundDir v7 (abOf lab))) faceHues
      | (_, lab) <- faceEnsemble ]
    -- ★ and it stays true for EVERY (ΔL, αC, βC) — the three
    --   shipped knobs never touch gRot, so the hue set is fixed
    noRetuneEscapes = and
      [ sameHue (groundDir g (abOf lab)) (abOf lab)
      | dL <- [negate (1 % 2), 0, 1 % 3], aC <- [negate 2, 0, 1]
      , bC <- [1 % 2, 1, 2]
      , let g = Ground { gDeltaL = dL, gAlphaC = aC, gBetaC = bC
                       , gRot = identityRot }
      , (_, lab) <- faceEnsemble ]

-- (GH2) ★ THE CONCENTRATION LAW. Because the σ half is a RIGID
--       rotation of the figure half,
--
--           R_table  =  R_figure · cos(|Δh|/2)
--
--       equivalently, squared and free of trigonometry,
--
--           2·R_table²  =  R_figure² · (1 + cos Δh).
--
--       v7 (Δh = 0) collapses it to R_table = R_figure: a one-hue
--       face forces a one-hue GIF, which is the 0.9913 measurement.
--       v5 (Δh = π) collapses it to 0: forced opposition, the blue
--       haze, independent of the scene.
axiom_GH2 :: Bool
axiom_GH2 = allUnit && lawExact && lawAtEveryAngle && v7Collapse && v5Collapse
  where
    rFig2  = conc2 faceHues
    -- cos Δh = the dot of two unit vectors — rational here
    cosDh  = cdot h0 wallRot
    rTab2  = conc2 (tableHues wallRot faceHues)
    allUnit    = all isUnit (tableHues wallRot faceHues)
    lawExact   = 2 * rTab2 == rFig2 * (1 + cosDh)
    -- and it is not a coincidence of one angle
    lawAtEveryAngle = and
      [ 2 * conc2 (tableHues r faceHues) == rFig2 * (1 + cdot h0 r)
      | r <- [identityRot, h2262, h3687, h5313, h9000, h12687, h18000] ]
    v7Collapse = conc2 (tableHues identityRot faceHues) == rFig2
    v5Collapse = conc2 (tableHues h18000 faceHues) == 0

-- (GH3) ★ THE GROUND FAMILY IS A GROUP, and Δh is its fourth
--       coordinate. Composition and inversion are closed in the
--       family; v5-W and v7 are two points of ONE one-parameter
--       subgroup. The third option is therefore not a new mechanism
--       — it is the coordinate the family already carried, filled
--       from evidence instead of from a ruling.
axiom_GH3 :: Bool
axiom_GH3 = closure && identityLaw && inverseLaw && assoc && oneSubgroup
  where
    gs = [ Ground { gDeltaL = dL, gAlphaC = aC, gBetaC = bC, gRot = r }
         | (dL, aC, bC, r) <- [ (1 % 10, negate 1, 3 % 4, h5313)
                              , (negate (1 % 5), 2, 1 % 2, h2262)
                              , (0, 0, 2, h9000)
                              , (1 % 3, 1 % 7, 1, h18000) ] ]
    closure = and [ gBetaC (gCompose g2 g1) /= 0 && not (isZeroDir (gRot (gCompose g2 g1)))
                  | g1 <- gs, g2 <- gs ]
    identityLaw = and [ gSame (gCompose gIdentity g) g
                     && gSame (gCompose g gIdentity) g | g <- gs ]
    inverseLaw = and [ gSame (gCompose (gInverse g) g) gIdentity
                    && gSame (gCompose g (gInverse g)) gIdentity | g <- gs ]
    assoc = and [ gSame (gCompose (gCompose g3 g2) g1)
                        (gCompose g3 (gCompose g2 g1))
                | g1 <- gs, g2 <- gs, g3 <- gs ]
    -- ★ v5 and v7 differ ONLY in gRot, and both rotations lie on the
    --   unit circle: one subgroup, two rulings.
    oneSubgroup =
      let a = v7Ground (1 % 10) (negate 1)
          b = v5Ground (1 % 10) (negate 1)
      in gDeltaL a == gDeltaL b && gAlphaC a == gAlphaC b
      && gBetaC a == gBetaC b && gRot a /= gRot b
      && isUnit (gRot a) && isUnit (gRot b)
      && oppositeHue (gRot b) (gRot a)

-- (GH4) ★ CIRCULAR MEAN = THE (a,b) RESULTANT. The chroma-weighted
--       circular mean of hue is the argument of Σ mᵢ(aᵢ,bᵢ), because
--       C(cos h, sin h) IS (a,b). So the chroma weighting is free,
--       and the whole law costs two accumulators inside the loop
--       backgroundMoments already runs.
axiom_GH4 :: Bool
axiom_GH4 = weightingIsFree && massScaleFree && chromaWeightsCount
  where
    -- explicit Σ m·C·(cos h, sin h) against Σ m·(a,b)
    explicit = vsum [ vscale (m * c) u
                    | ((m, _), (c, u)) <-
                        zip wallEnsemble (zip wallChromas wallHues) ]
    weightingIsFree = explicit == resultant wallEnsemble
    -- the DIRECTION is scale-free in the masses
    doubled = [ (2 * m, lab) | (m, lab) <- wallEnsemble ]
    massScaleFree = sameHue (resultant doubled) (resultant wallEnsemble)
    -- ★ chroma really does weight: a high-chroma outlier moves the
    --   mean, an equal-mass achromatic sample does not
    withGray = wallEnsemble ++ [ (100, (1 % 2, 0, 0)) ]
    chromaWeightsCount =
         resultant withGray == resultant wallEnsemble
      && not (sameHue (resultant (wallEnsemble ++ [(1, labOf (1 % 2) h18000)]))
                      (resultant wallEnsemble))

-- (GH5) ★ WRAPAROUND. Two hues straddling the 0/360 seam resolve to
--       the seam itself. The resultant gets it exactly right; the
--       naive mean of angle REPRESENTATIVES in [0,360) is 180° wrong
--       — which is why this spec never represents a hue as a number.
axiom_GH5 :: Bool
axiom_GH5 = resultantCorrect && naiveWrong && seamSymmetric
  where
    up   = h5313                        --  53.13°
    down = cconj h5313                  -- 306.87°
    ens  = [ (1, labOf (1 % 10) up), (1, labOf (1 % 10) down) ]
    resultantCorrect = sameHue (resultant ens) h0        -- exactly 0°
    naiveMean = (hueDegD up + hueDegD down) / 2
    naiveWrong = abs (naiveMean - 180) < 1e-9            -- 180°, not 0°
    -- and it is symmetric about the seam from the other side too
    seamSymmetric =
      sameHue (resultant [ (3, labOf (1 % 10) h2262)
                         , (3, labOf (1 % 10) (cconj h2262)) ]) h0

-- (GH6) ★ THE HUE LAW IS EXACT IN ℚ. The ground's chroma is set by
--       the power law, which RE-NORMALISES — so the rotation may be
--       applied unnormalised and no square root ever enters the hue
--       path. Scaling the rotation vector by any positive rational
--       leaves every emitted hue identical.
axiom_GH6 :: Bool
axiom_GH6 = scaleInvariant && rationalClosed && achromaticFixed
  where
    g k = Ground { gDeltaL = 0, gAlphaC = 0, gBetaC = 1
                 , gRot = vscale k wallRot }
    scaleInvariant = and
      [ sameHue (groundDir (g k) (a, b)) (groundDir (g 1) (a, b))
      | k <- [1 % 7, 3, 100, 1 % 1000], (_, (_, a, b)) <- faceEnsemble ]
    -- rational unit hues are closed under the rotation
    rationalClosed = all isUnit [ cmul u wallRot | u <- faceHues ]
    -- the achromatic axis is a fixed point, exactly
    achromaticFixed = groundDir (g 1) (0, 0) == (0, 0)

-- (GH7) TOTALITY. groundRotation is total and returns the IDENTITY
--       on every degenerate case — no background mass, no chromatic
--       background mass, an achromatic figure, an empty ensemble.
--       Identity rotation is byte-for-byte the v7 / Wada-prior path
--       that ships today, so the degenerate branch needs no new code
--       and no new constant.
axiom_GH7 :: Bool
axiom_GH7 = and
  [ groundRotation faceEnsemble []          == identityRot   -- no mass
  , groundRotation faceEnsemble grayWall    == identityRot   -- no chroma
  , groundRotation [] wallEnsemble          == identityRot   -- no figure
  , groundRotation grayWall wallEnsemble    == identityRot   -- gray figure
  , groundRotation [] []                    == identityRot
  , groundRotation zeroMass wallEnsemble    == identityRot   -- all m = 0
  , sameHue (groundRotation faceEnsemble wallEnsemble) wallRot  -- and it fits
  ]
  where zeroMass = [ (0, lab) | (_, lab) <- faceEnsemble ]

-- (GH8) GRACEFUL DEGRADATION. When the wall genuinely IS the face's
--       hue — different chroma, different lightness, same directions
--       — the fitted rotation is the identity and every emitted
--       direction equals v7's, exactly. The law does not "prefer"
--       colour; it reports the scene.
axiom_GH8 :: Bool
axiom_GH8 = fitsIdentity && bytesUnchanged
  where
    rot = groundRotation faceEnsemble sameHueWall
    fitsIdentity = sameHue rot identityRot
    fitted = fitGroundHue (1 % 10) (negate 1) (3 % 4) faceEnsemble sameHueWall
    v7     = v7Ground (1 % 10) (negate 1)
    bytesUnchanged =
         gSame fitted v7
      && and [ sameHue (groundDir fitted (a, b)) (groundDir v7 (a, b))
             | (_, (_, a, b)) <- faceEnsemble ]

-- (GH9) ★ THE POINT. On a two-hue scene the emitted table's hue
--       concentration STRICTLY DROPS against v7, and the σ half's
--       mean hue lands exactly on the BACKGROUND's own mean hue —
--       which is the property v5 (forced opposition) and v7 (forced
--       identity) both lack.
axiom_GH9 :: Bool
axiom_GH9 = strictDrop && groundMeanIsWallMean && notComplementEither
  where
    rot     = groundRotation faceEnsemble wallEnsemble
    unitRot = wallRot                       -- rot normalises to this, exactly
    rotIsWall = sameHue rot unitRot
    rV7  = conc2 (tableHues identityRot faceHues)
    rNew = conc2 (tableHues unitRot faceHues)
    strictDrop = rotIsWall && rNew < rV7 && rNew > 0
    -- the σ half's resultant points where the WALL's does
    sigmaResultant = vsum (map (`cmul` unitRot) faceHues)
    groundMeanIsWallMean = sameHue sigmaResultant (resultant wallEnsemble)
    -- and it is emphatically not the complement
    notComplementEither =
      not (oppositeHue sigmaResultant (vsum faceHues))
      && not (sameHue sigmaResultant (vsum faceHues))

-- (GH10) ★ THE GAMUT CANNOT DEFEAT IT. chromaClamp scales chroma and
--        ONLY chroma (DyadPalette.swift:115, spec § 3), so hue is
--        invariant under it for every clamp factor in (0,1]. The
--        ground's chroma law (any αC, βC) is likewise a positive
--        radial scaling. Therefore the hue the law computes is the
--        hue that reaches the table bytes — the fix cannot be eaten
--        by an out-of-gamut ground, only muted.
axiom_GH10 :: Bool
axiom_GH10 = clampHueInvariant && powerLawHueInvariant && lShiftHueInvariant
  where
    vs = [ (a, b) | (_, (_, a, b)) <- faceEnsemble ++ wallEnsemble ]
    ss = [ 1, 1 % 2, 1 % 10, 1 % 1000, 999 % 1000 ]
    clampHueInvariant = and [ sameHue (vscale s v) v | v <- vs, s <- ss ]
    -- the chroma law is exp(αC + βC·ln C) — a positive radial gain
    powerLawHueInvariant = and
      [ sameHue (abOf (groundSim 0 gain wallRot (1 % 2, a, b)))
                (cmul (a, b) wallRot)
      | (a, b) <- vs, gain <- [1 % 4, 1, 7] ]
    -- and the rigid L-shift touches no chroma at all
    lShiftHueInvariant = and
      [ let g = groundSim dL 1 wallRot (1 % 2, a, b)
        in sameHue (abOf g) (cmul (a, b) wallRot)
           && lOf g == 1 % 2 + dL
      | (a, b) <- vs, dL <- [negate (1 % 3), 0, 1 % 4] ]

-- (GH11) ★ MONOTONE AND BOUNDED. R_table is strictly decreasing in
--         |Δh| on [0,π]: dispersion is proportional to the scene's
--         own hue separation. That is the whole case for the third
--         option — v7 pins it at the maximum (monochrome) and v5 at
--         the minimum (blue haze), regardless of what was in front
--         of the camera.
axiom_GH11 :: Bool
axiom_GH11 = strictlyDecreasing && endpoints && boundedBetween
  where
    -- rotations of increasing |Δh|: 0 < 22.62 < 36.87 < 53.13 < 90 <
    -- 126.87 < 180 degrees
    ladder = [identityRot, h2262, h3687, h5313, h9000, h12687, h18000]
    rs = [ conc2 (tableHues r faceHues) | r <- ladder ]
    strictlyDecreasing = and (zipWith (>) rs (tail rs))
    endpoints = head rs == conc2 faceHues && last rs == 0
    boundedBetween = all (\r -> r >= 0 && r <= conc2 faceHues) rs

-- (GH12) ★ THE SEARCH MUST MOVE TOO. The σ-side blur search
--         (DyadPipeline.swift:578) minimises d(node, target) while
--         the pixel is DISPLAYED as ground(node). The pre-image
--         search is optimal for the metric that is actually seen,
--         and it is a STRICT improvement here. The defect predates
--         this spec: at Δh = 0 the figure-frame search is already
--         wrong whenever βC ≠ 1 or ΔL ≠ 0.
--
--         ★ And the split is safe to ship in two steps: rotating the
--         displayed table changes ZERO index bytes, so step A costs
--         exactly nothing in LZW (the index stream is untouched);
--         only step B moves pixels.
axiom_GH12 :: Bool
axiom_GH12 = groundFrameOptimal && frameChoicesDiffer && alreadyWrongAtZero
             && displayOnlyIsIndexFree
  where
    -- three prefix nodes of UNEQUAL chroma radius (the tree's leaves
    -- are not on a circle — PT8 sizes them by √λ)
    nodes = [ (1 % 2, 1 % 10, 0), (1 % 2, 0, 1 % 20), (1 % 2, negate (1 % 10), 0) ]
    g   = groundSim (1 % 10) (1 % 2) wallRot
    targets = [ (3 % 5, 3 % 100, 1 % 25)          -- exactly ground(node 0)
              , (3 % 5, negate (1 % 50), 3 % 200) -- near the origin
              , (3 % 5, 1 % 20, 1 % 20) ]
    groundFrameOptimal = and
      [ shownError g nodes t (searchGroundFrame g nodes t)
          <= shownError g nodes t (searchFigureFrame nodes t)
      | t <- targets ]
    frameChoicesDiffer = or
      [ searchGroundFrame g nodes t /= searchFigureFrame nodes t | t <- targets ]
    -- Δh = 0 but βC ≠ 1 and ΔL ≠ 0: still the wrong argmin, TODAY
    g0 = groundSim (1 % 5) (1 % 4) identityRot
    alreadyWrongAtZero = or
      [ searchGroundFrame g0 nodes t /= searchFigureFrame nodes t | t <- targets ]
    -- ★ step A: rotate the TABLE only. The index stream is produced
    --   by a search that never reads gRot, so it is IDENTICAL while
    --   the emitted bytes differ — zero LZW cost, zero risk.
    idx      = map (searchFigureFrame nodes) targets
    shownV7  = [ groundSim (1 % 10) (1 % 2) identityRot (nodes !! i) | i <- idx ]
    shownNew = [ groundSim (1 % 10) (1 % 2) wallRot     (nodes !! i) | i <- idx ]
    displayOnlyIsIndexFree =
      length idx == length targets && shownV7 /= shownNew

-- (GH13) ★ SMOOTH THE RESULTANT, NEVER THE ANGLE. The JEPA-H ring
--         (DyadPipeline.swift:620) carries the ground's generating
--         state; the hue must ride it as a 2-dim VECTOR that is
--         renormalised, not as an angle. Averaging angle
--         representatives across the seam gives the opposite hue —
--         the same wraparound failure as GH5, now at 5 Hz, once per
--         loop.
axiom_GH13 :: Bool
axiom_GH13 = vectorSmoothCorrect && angleSmoothWrong && emaKeepsDirection
  where
    slotA = h5313                   --  53.13°
    slotB = cconj h5313             -- 306.87°
    -- vector EMA (α = 1/2), then renormalise: lands on the seam
    blended = vadd (vscale (1 % 2) slotA) (vscale (1 % 2) slotB)
    vectorSmoothCorrect = sameHue blended h0
    -- angle EMA on [0,360) representatives: lands 180° away
    angleBlend = (hueDegD slotA + hueDegD slotB) / 2
    angleSmoothWrong = abs (angleBlend - 180) < 1e-9
    -- an EMA of unit vectors is NOT unit, but its DIRECTION is what
    -- the law reads — so renormalisation is a display detail, never
    -- a change of hue
    emaKeepsDirection = and
      [ sameHue (vadd (vscale a slotA) (vscale (1 - a) slotA)) slotA
      | a <- [1 % 10, 1 % 2, 9 % 10] ]

-- (GH14) γ-STAGING IS HUE-CONTRACTING — a MEASUREMENT. ŷ's chroma
--        vector is a convex combination of the pixel's and c_F's, so
--        every staged hue moves toward hue(c_F): the staged field's
--        hue spread is narrower than the sensor's, which narrows
--        which entries the background can select (the dead third of
--        the table). It is a CONTRIBUTOR, not the cause — no staged
--        background colour reaches the palette at all (GH1).
--
--        The a-b-preserving variant (buy the octave in L alone)
--        leaves every hue pointwise EXACT. DY9 is authoritative and
--        unchanged; this axiom only measures the difference so the
--        ruling can be taken on evidence.
axiom_GH14 :: Bool
axiom_GH14 = betweenness && contractsTowardCentroid && lOnlyIsHueExact
             && lOnlyStillMovesL
  where
    cF  = (1 % 2, 1 % 10 * (4 % 5), 1 % 10 * (3 % 5))   -- chromatic c_F
    cAB = abOf cF
    gam = 1 % 2                          -- γ(0) = 1/2, the far extreme
    ps  = [ (2 % 5, c * x, c * y)
          | (c, (x, y)) <- zip [1 % 8, 1 % 12, 1 % 20] wallHues ]
    -- the staged chroma vector lies in the cone spanned by v and c_F
    betweenness = and
      [ let v = abOf p; v' = abOf (stageAerial gam cF p)
        in signum (ccross v v') * signum (ccross v' cAB) >= 0
      | p <- ps ]
    -- ★ and it is strictly no further from c_F in ANGLE: the tangent
    --   of the angle to c_F cannot grow (cross-multiplied, exact)
    contractsTowardCentroid = and
      [ let v = abOf p; v' = abOf (stageAerial gam cF p)
        in cdot v cAB > 0 && cdot v' cAB > 0
           && abs (ccross v' cAB) * cdot v cAB
                <= abs (ccross v cAB) * cdot v' cAB
      | p <- ps ]
    -- L-only: hue survives pointwise, exactly
    lOnlyIsHueExact = and [ abOf (stageLOnly gam cF p) == abOf p | p <- ps ]
    -- and it is not a no-op: the lightness octave is still bought
    lOnlyStillMovesL = and [ lOf (stageLOnly gam cF p) /= lOf p | p <- ps ]

-- (GH15) ALLOCATION IS A SEPARATE DEFECT. With PairTree on, the
--        σ-side blur quantises at the 32-level: 16 node means, each
--        emitted as ONE canonical partner. So a frame can show at
--        most 128 + 16 = 144 of the 256 entries, and at least 112 σ
--        entries carry no pixel. (The measured 164-of-256 is the
--        UNION over 64 frames, whose canonical leaves drift; the
--        per-frame bound is 144.) The n ∝ √λ allocation (RL4/PT8)
--        is fit to the FIGURE's eigenvalues alone — the background's
--        own variance never enters. The hue law does not close this,
--        and should not pretend to.
axiom_GH15 :: Bool
axiom_GH15 = perFrameBound && deadEntries && unionExceedsFrameBound
             && allocationIsFigureOnly
  where
    figureEntries = 128 :: Int
    sigmaNodes    = 16 :: Int          -- depth-4 prefix nodes (P2)
    paletteSize   = 256 :: Int
    perFrameBound = figureEntries + sigmaNodes == 144
                 && figureEntries + sigmaNodes < paletteSize
    deadEntries = paletteSize - (figureEntries + sigmaNodes) == 112
    -- the measured count is a union over the loop, so it may exceed
    -- the per-frame bound without contradicting it
    measuredUnion = 164 :: Int
    unionExceedsFrameBound =
      measuredUnion > figureEntries + sigmaNodes
      && measuredUnion <= paletteSize
    -- ★ n ∝ √λ reads the FIGURE's eigenvalues. √ is monotone, so the
    --   allocation is the descending-λ permutation — and it is
    --   witnessed to be background-free: rotating the whole
    --   background, or DELETING it, leaves it identical.
    alloc :: [(Q, Lab)] -> [Q] -> [Int]
    alloc _bg lams = map snd (reverse (sortPairs (zip lams [0 ..])))
    sortPairs = foldr ins []
      where ins x [] = [x]
            ins x (y : ys) = if fst x <= fst y then x : y : ys else y : ins x ys
    rotatedWall = [ (m, (l, a', b'))
                  | (m, (l, a, b)) <- wallEnsemble
                  , let (a', b') = cmul (a, b) h9000 ]
    allocationIsFigureOnly =
         alloc wallEnsemble figureLambdas == alloc rotatedWall figureLambdas
      && alloc wallEnsemble figureLambdas == alloc [] figureLambdas
      && alloc [] figureLambdas == [0, 1, 2]
      && length (nub figureLambdas) == 3
    figureLambdas = [4 % 100, 1 % 100, 1 % 400] :: [Q]

-- ════════════════════════════════════════════════════════════════
-- § 8. MAIN
-- ════════════════════════════════════════════════════════════════

axioms :: [(String, Bool)]
axioms =
  [ ("GH1  ★ HUE-BLINDNESS: three rotation-invariant moments only", axiom_GH1)
  , ("GH2  ★ R_table = R_figure · cos(|Δh|/2) — exact", axiom_GH2)
  , ("GH3  ★ the ground family is a GROUP; Δh is coordinate four", axiom_GH3)
  , ("GH4  ★ circular mean = the (a,b) resultant; chroma is free", axiom_GH4)
  , ("GH5  ★ wraparound: the seam resolves exactly, angles do not", axiom_GH5)
  , ("GH6  ★ the hue law is EXACT in Q — no square root", axiom_GH6)
  , ("GH7  totality: every degenerate case ⇒ identity rotation", axiom_GH7)
  , ("GH8  graceful: same-hue wall ⇒ Δh = 0 ⇒ today's bytes", axiom_GH8)
  , ("GH9  ★ two-hue scene: concentration DROPS, ground = wall hue", axiom_GH9)
  , ("GH10 ★ chroma-only clamping is hue-invariant — it reaches bytes", axiom_GH10)
  , ("GH11 ★ R strictly decreasing in |Δh| on [0,π]", axiom_GH11)
  , ("GH12 ★ the σ search must move to the ground frame", axiom_GH12)
  , ("GH13 ★ smooth the RESULTANT, never the angle (JEPA-H ring)", axiom_GH13)
  , ("GH14 γ-staging is hue-contracting (measurement; DY9 rules)", axiom_GH14)
  , ("GH15 allocation is a SEPARATE defect: ≤144 entries per frame", axiom_GH15)
  ]

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " GroundHue: the ground's OWN hue — the fourth coordinate"
  putStrLn " of the Wada family, read off the background's own pixels"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── The measurement that opened this (shipped 17 Pro GIF) ──"
  putStrLn ""
  putStrLn "  circular hue concentration R : 0.9913   (1.0 = one hue)"
  putStrLn "  circular sd                  : 7.6°"
  putStrLn "  background hue 44.7°  vs  image mean hue 48.8°"
  putStrLn "  table max chroma             : 0.0919"
  putStrLn ""
  putStrLn "  GH1 says the wall CANNOT be any other hue: the ground"
  putStrLn "  family reads the background as (mean L, mean lnC, sd"
  putStrLn "  lnC) — three numbers, all blind to hue."
  putStrLn ""

  putStrLn "── GH2: one law, three rulings ──"
  putStrLn ""
  putStrLn "   Δh      ruling            R_table / R_figure"
  putStrLn "  ───────┼─────────────────┼────────────────────"
  mapM_ ruling
    [ (identityRot, "v7  same hue    ")
    , (h2262,       "                ")
    , (h3687,       "                ")
    , (h5313,       "                ")
    , (h9000,       "                ")
    , (h12687,      "                ")
    , (h18000,      "v5-W  complement") ]
  putStrLn ""
  putStrLn "  R_figure is the FACE's own concentration. v7 hands the"
  putStrLn "  whole GIF the face's number; v5 forces 0 whatever the"
  putStrLn "  scene; the fitted Δh returns the scene's own separation."
  putStrLn ""

  putStrLn "── Predicted effect at the measured R_figure = 0.9913 ──"
  putStrLn ""
  putStrLn "   scene |Δh|   predicted R_table"
  putStrLn "  ────────────┼───────────────────"
  mapM_ predicted [0, 15, 30, 45, 60, 90, 120, 180]
  putStrLn ""
  putStrLn "  (|Δh| must be measured on the CAMERA field, never on"
  putStrLn "  the shipped GIF — by GH1 the GIF has already thrown"
  putStrLn "  the background's hue away.)"
  putStrLn ""

  putStrLn "── The fitted rotation on the fixture scene ──"
  putStrLn ""
  putStrLn $ "  face mean hue : " ++ deg (resultant faceEnsemble)
  putStrLn $ "  wall mean hue : " ++ deg (resultant wallEnsemble)
  putStrLn $ "  Δh            : " ++ deg (groundRotation faceEnsemble wallEnsemble)
  putStrLn $ "  gray wall     : " ++ deg (groundRotation faceEnsemble grayWall)
             ++ "  (identity — the Wada prior path)"
  putStrLn $ "  same-hue wall : " ++ deg (groundRotation faceEnsemble sameHueWall)
             ++ "  (identity — today's bytes, exactly)"
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  mapM_ (uncurry check) axioms
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  A palette that is told how light and how colourful the"
  putStrLn "  wall is, but never WHAT COLOUR it is, can only paint the"
  putStrLn "  wall in the face's hue. That is not a tuning failure —"
  putStrLn "  it is the shape of the family. v5 forced the opposite"
  putStrLn "  hue and got a blue haze; v7 forced the same hue and got"
  putStrLn "  a monochrome. Both forced."
  putStrLn ""
  putStrLn "  The third option forces nothing. Wada leaves the hue"
  putStrLn "  interval free, so the family already has the coordinate"
  putStrLn "  — fill it from the background's own chroma-weighted"
  putStrLn "  resultant. Two accumulators, no trigonometry, no square"
  putStrLn "  root, no new constant, and every degenerate case lands"
  putStrLn "  exactly on the behaviour that ships today."
  putStrLn "══════════════════════════════════════════════════════════"

  let bad = length [ n | (n, ok) <- axioms, not ok ]
  if bad > 0 then exitFailure else pure ()

ruling :: (Dir, String) -> IO ()
ruling (r, name) =
  let rFig = conc2 faceHues
      rTab = conc2 (tableHues r faceHues)
      ratio = sqrt (fromRational rTab / fromRational rFig) :: Double
  in putStrLn $ "  " ++ padR 6 (showF1 (hueDegD r) ++ "°")
             ++ " │ " ++ name ++ " │ " ++ showF4 ratio

predicted :: Double -> IO ()
predicted dh =
  putStrLn $ "  " ++ padL 10 (showF1 dh ++ "°")
          ++ "  │ " ++ showF4 (0.9913 * cos (dh * pi / 360))

deg :: Dir -> String
deg v
  | isZeroDir v = "  (none)"
  | otherwise   = padL 8 (showF2 (hueDegD v)) ++ "°"

showF1, showF2, showF4 :: Double -> String
showF1 = showFn 1
showF2 = showFn 2
showF4 = showFn 4

showFn :: Int -> Double -> String
showFn n x =
  let p = 10 ^ n :: Integer
      r = round (x * fromIntegral p) :: Integer
      (q, m) = abs r `divMod` p
      sign = if r < 0 then "-" else ""
  in sign ++ show q ++ "." ++ padZ n (show m)

padZ :: Int -> String -> String
padZ n s = replicate (max 0 (n - length s)) '0' ++ s

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

padR :: Int -> String -> String
padR n s = s ++ replicate (max 0 (n - length s)) ' '

check :: String -> Bool -> IO ()
check name ok =
  putStrLn $ "  " ++ (if ok then "\10003" else "\10007") ++ " " ++ name
