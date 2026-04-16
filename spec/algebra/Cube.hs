{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- Cube: The GIF as a 64³ Voxel Object
--
-- A GIF is 64 frames of 64×64 pixels. That's 64³ = 262,144 voxels.
-- Each voxel has a palette index ∈ {0..255}.
--
-- Normally, you VIEW the cube from the front:
--   The xy-plane is one frame. The z-axis is time.
--   Playing the GIF = slicing the cube along z at 20fps.
--
-- But the cube has THREE natural projections:
--   FRONT:  slice along z → (x, y) frames, z = time → normal GIF
--   SIDE:   slice along x → (y, z) frames, x = column → spatiotemporal Y×T
--   TOP:    slice along y → (x, z) frames, y = row → spatiotemporal X×T
--
-- Each projection is a different GIF:
--   Front GIF: 64 frames of 64×64 → how the scene looks over time
--   Side GIF:  64 frames of 64×64 → how each row evolves (time is VISIBLE)
--   Top GIF:   64 frames of 64×64 → how each column evolves
--
-- The user ROTATES the cube. As it rotates past 45°, the side
-- becomes the dominant view. The NN re-computes the voxels so
-- the side view is ALSO beautiful. The rotation IS the animation.
--
-- The SPECTRUM of global vs per-frame palettes:
--   g=1 (global): voxels coherent in ALL projections
--   g=0 (local):  voxels optimized for FRONT only
--   The adaptive g per pixel: face is global (survives rotation),
--   background is local (looks like noise from the side).
--
-- Category theory:
--   The cube is a functor: {0..63}³ → {0..255}
--   A projection is a natural transformation: Cube → Frame sequence
--   The NN is an endofunctor: Cube → Cube (improves for current view)
-- ════════════════════════════════════════════════════════════════

module Cube where

import Data.List (foldl')
import qualified Data.Map.Strict as Map

-- ════════════════════════════════════════════════════════════════
-- § 1. THE VOXEL CUBE
-- ════════════════════════════════════════════════════════════════

type Voxel = (Int, Int, Int)         -- (x, y, z) ∈ {0..63}³
type PaletteIndex = Int              -- {0..255}
type VoxelCube = Map.Map Voxel PaletteIndex

cubeSize :: Int
cubeSize = 64

allVoxels :: [Voxel]
allVoxels = [(x, y, z) | x <- [0..cubeSize-1]
                        , y <- [0..cubeSize-1]
                        , z <- [0..cubeSize-1]]

totalVoxels :: Int
totalVoxels = cubeSize ^ (3 :: Int)  -- 262,144

-- ════════════════════════════════════════════════════════════════
-- § 2. PROJECTIONS — three natural views of the cube
--
-- Each projection picks 2 axes for the frame (spatial)
-- and 1 axis for the sequence (temporal / playback).
-- ════════════════════════════════════════════════════════════════

data Axis = AxisX | AxisY | AxisZ
  deriving (Show, Eq, Ord)

data Projection = Projection
  { projFrameA :: !Axis    -- first spatial axis of the frame
  , projFrameB :: !Axis    -- second spatial axis of the frame
  , projSlice  :: !Axis    -- the "time" axis (slice through this)
  } deriving (Show, Eq)

-- | The three canonical projections
front :: Projection
front = Projection AxisX AxisY AxisZ   -- normal GIF: (x,y) frame, z = time

side :: Projection
side = Projection AxisY AxisZ AxisX    -- side view: (y,z) frame, x = column

top :: Projection
top = Projection AxisX AxisZ AxisY     -- top view: (x,z) frame, y = row

allProjections :: [Projection]
allProjections = [front, side, top]

-- ════════════════════════════════════════════════════════════════
-- § 3. SLICING — extract a 2D frame from the cube
-- ════════════════════════════════════════════════════════════════

-- | A 2D frame: 64×64 palette indices
type Frame2D = Map.Map (Int, Int) PaletteIndex

-- | Extract one frame from the cube at a given depth along the slice axis
sliceCube :: VoxelCube -> Projection -> Int -> Frame2D
sliceCube cube proj depth = Map.fromList
  [ ((a, b), idx)
  | a <- [0..cubeSize-1]
  , b <- [0..cubeSize-1]
  , let voxel = makeVoxel proj a b depth
  , Just idx <- [Map.lookup voxel cube]
  ]

-- | Build a voxel coordinate from projection + frame position + depth
makeVoxel :: Projection -> Int -> Int -> Int -> Voxel
makeVoxel proj a b depth =
  let vals = [(projFrameA proj, a), (projFrameB proj, b), (projSlice proj, depth)]
      get ax = maybe 0 id (lookup ax vals)
  in (get AxisX, get AxisY, get AxisZ)

-- | Extract ALL frames for a projection → a full GIF sequence
sliceAll :: VoxelCube -> Projection -> [Frame2D]
sliceAll cube proj = [sliceCube cube proj d | d <- [0..cubeSize-1]]

-- ════════════════════════════════════════════════════════════════
-- § 4. ROTATION — interpolate between projections
--
-- At 0°: viewing from front (normal GIF).
-- At 90°: viewing from side (spatiotemporal cross-section).
-- Between 0° and 90°: a 3D perspective blend.
--
-- For the NN update: at each rotation angle θ, the "current"
-- projection shifts. When θ > 45°, the side becomes dominant.
-- The NN should then optimize for the side view.
-- ════════════════════════════════════════════════════════════════

-- | Rotation state: angle around one axis
data Rotation = Rotation
  { rotAxis  :: !Axis     -- which axis we rotate around
  , rotAngle :: !Double   -- angle in radians [0, 2π)
  } deriving (Show, Eq)

-- | Which projection is dominant at this rotation?
--   [0, π/4):    front
--   [π/4, 3π/4): side (or top, depending on rotation axis)
--   [3π/4, 5π/4): back (= front reversed)
--   etc.
dominantProjection :: Rotation -> Projection
dominantProjection (Rotation axis angle) =
  let normalized = angle `mod'` (2 * pi)
      quadrant = floor (normalized / (pi / 2)) :: Int
  in case (axis, quadrant `mod` 4) of
      (AxisY, 0) -> front     -- looking at front face
      (AxisY, 1) -> side      -- rotated right → side face
      (AxisY, 2) -> front     -- back face (front reversed)
      (AxisY, 3) -> side      -- rotated left → other side
      (AxisX, 0) -> front
      (AxisX, 1) -> top       -- rotated up → top face
      (AxisX, 2) -> front
      (AxisX, 3) -> top
      _          -> front

mod' :: Double -> Double -> Double
mod' a b = a - b * fromIntegral (floor (a / b) :: Int)

-- | Blend factor: how much of the "next" projection to show
--   0.0 = fully current projection
--   1.0 = fully next projection
blendFactor :: Rotation -> Double
blendFactor (Rotation _ angle) =
  let within = (angle `mod'` (pi / 2)) / (pi / 2)
  in if within < 0.5
     then within * 2          -- 0→1 as we approach the next face
     else (1 - within) * 2   -- 1→0 as we settle into the face

-- ════════════════════════════════════════════════════════════════
-- § 5. THE PALETTE SPECTRUM
--
-- Each voxel has a palette index and a global weight g.
-- g=1: this voxel's color is COHERENT across all projections.
--      It looks the same whether viewed from front, side, or top.
-- g=0: this voxel's color is optimized for the FRONT projection only.
--      From the side, it might look like noise.
--
-- The spectrum:
--   All g=1: uniform palette, all views coherent (like a solid die)
--   All g=0: each frame independent (like a flipbook)
--   Adaptive g: face is global (survives rotation), BG is local
-- ════════════════════════════════════════════════════════════════

type GlobalMap = Map.Map Voxel Double  -- g ∈ [0,1] per voxel

-- | Coherence of a projection: mean global weight of visible voxels
projectionCoherence :: GlobalMap -> Projection -> Int -> Double
projectionCoherence gmap proj depth =
  let voxels = [makeVoxel proj a b depth | a <- [0..cubeSize-1], b <- [0..cubeSize-1]]
      gs = [Map.findWithDefault 0.5 v gmap | v <- voxels]
  in sum gs / fromIntegral (length gs)

-- | A voxel that is GLOBAL (g ≈ 1) looks good from any angle.
--   A voxel that is LOCAL (g ≈ 0) only looks good from front.
--   When the user rotates to the side, local voxels degrade.
--   The NN should increase g for voxels that the user views from the side.

-- ════════════════════════════════════════════════════════════════
-- § 6. THE UPDATE: NN re-processes for the current view
--
-- When the cube rotates to show a new face:
--   1. The current face's frames are extracted (sliceCube)
--   2. The NN processes them (residual on teacher)
--   3. The voxels are UPDATED with new palette indices
--   4. The cube re-renders showing the updated view
--
-- This is an ENDOFUNCTOR: Cube → Cube
-- The NN maps one cube to a better cube (for the current view).
-- Each rotation triggers an update. The cube improves iteratively.
-- ════════════════════════════════════════════════════════════════

-- | Update the cube for a given projection view.
--   Replaces voxels visible in this projection with NN-assigned values.
updateCubeForView :: VoxelCube -> Projection
                  -> (Frame2D -> Int -> Frame2D)   -- NN: old frame → depth → new frame
                  -> VoxelCube
updateCubeForView cube proj nnUpdate =
  let updated = [ (makeVoxel proj a b d, idx)
                | d <- [0..cubeSize-1]
                , let oldFrame = sliceCube cube proj d
                      newFrame = nnUpdate oldFrame d
                , ((a, b), idx) <- Map.toList newFrame
                ]
  in foldl' (\c (v, i) -> Map.insert v i c) cube updated

-- ════════════════════════════════════════════════════════════════
-- § 7. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (V1) Cube has 64³ = 262,144 voxels
axiom_V1 :: Bool
axiom_V1 = totalVoxels == 262144

-- (V2) Three canonical projections exist and are distinct
axiom_V2 :: Bool
axiom_V2 = front /= side && side /= top && front /= top
        && length allProjections == 3

-- (V3) Each projection produces 64 frames of 64×64
axiom_V3 :: Bool
axiom_V3 =
  let cube = Map.fromList [(v, 0) | v <- allVoxels]
      frames = sliceAll cube front
  in length frames == 64
  && all (\f -> Map.size f == 64 * 64) frames

-- (V4) Slicing from front at z=0 gives the first frame
axiom_V4 :: Bool
axiom_V4 =
  let cube = Map.fromList [((x,y,z), x + y * 64 + z * 4096) | (x,y,z) <- allVoxels]
      frame0 = sliceCube cube front 0
      -- At z=0, voxel (x,y,0) should have index x + y*64
  in all (\(x,y) ->
      Map.lookup (x, y) frame0 == Just (x + y * 64)
    ) [(x,y) | x <- [0..5], y <- [0..5]]

-- (V5) Slicing from side at x=0 gives a y×z frame
axiom_V5 :: Bool
axiom_V5 =
  let cube = Map.fromList [((x,y,z), x * 100 + y * 10 + z) | (x,y,z) <- allVoxels, x < 5, y < 5, z < 5]
      frame0 = sliceCube cube side 0  -- x=0 slice → (y,z) frame
      -- At x=0, voxel (0,y,z) has index 0 + y*10 + z
  in Map.lookup (0, 0) frame0 == Just 0    -- (y=0, z=0)
  && Map.lookup (1, 2) frame0 == Just 12   -- (y=1, z=2) → 0 + 10 + 2 = 12

-- (V6) Dominant projection at angle 0 = front
axiom_V6 :: Bool
axiom_V6 = dominantProjection (Rotation AxisY 0) == front

-- (V7) Dominant projection at angle π/2 = side (for Y-axis rotation)
axiom_V7 :: Bool
axiom_V7 = dominantProjection (Rotation AxisY (pi / 2)) == side

-- (V8) Update preserves cube size
axiom_V8 :: Bool
axiom_V8 =
  let cube = Map.fromList [(v, 0) | v <- allVoxels]
      idUpdate frame _depth = frame  -- identity: no change
      updated = updateCubeForView cube front idUpdate
  in Map.size updated == Map.size cube

-- (V9) Identity update preserves all values
axiom_V9 :: Bool
axiom_V9 =
  let cube = Map.fromList [(v, v_idx v) | v <- take 1000 allVoxels]
      idUpdate frame _depth = frame
      updated = updateCubeForView cube front idUpdate
  in all (\v -> Map.lookup v updated == Map.lookup v cube) (take 1000 allVoxels)
  where v_idx (x,y,z) = (x + y * 64 + z * 4096) `mod` 256

-- (V10) Palette always valid: all indices ∈ {0..255}
axiom_V10 :: Bool
axiom_V10 =
  let cube = Map.fromList [(v, (x + y + z) `mod` 256) | v@(x,y,z) <- allVoxels]
  in all (\i -> i >= 0 && i <= 255) (Map.elems cube)

-- ════════════════════════════════════════════════════════════════
-- § 8. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " Cube: The GIF as a 64³ Voxel Object"
  putStrLn " Three projections. Rotate to explore. NN updates the view."
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── The Cube ──"
  putStrLn $ "  Size: " ++ show cubeSize ++ "³ = " ++ show totalVoxels ++ " voxels"
  putStrLn $ "  Palette: 256 entries (4⁴ tesseract)"
  putStrLn ""

  putStrLn "── Three Projections ──"
  putStrLn ""
  putStrLn "  FRONT: (x, y) frames, z = time → normal GIF playback"
  putStrLn "  SIDE:  (y, z) frames, x = column → spatiotemporal Y×T"
  putStrLn "  TOP:   (x, z) frames, y = row → spatiotemporal X×T"
  putStrLn ""

  -- Demonstrate slicing
  let cube = Map.fromList [((x,y,z), (x + y + z) `mod` 256) | (x,y,z) <- allVoxels]
  putStrLn "── Slicing ──"
  mapM_ (\(name, proj) -> do
    let frames = sliceAll cube proj
        f0 = head frames
        f63 = last frames
        uniqueF0 = length $ Map.elems f0
    putStrLn $ "  " ++ name ++ ": " ++ show (length frames) ++ " frames"
            ++ ", frame 0 has " ++ show (Map.size f0) ++ " pixels"
    ) [("Front", front), ("Side", side), ("Top", top)]
  putStrLn ""

  -- Demonstrate rotation
  putStrLn "── Rotation (around Y-axis) ──"
  putStrLn ""
  putStrLn "  angle  │ dominant    │ blend"
  putStrLn "  ───────┼─────────────┼──────"
  mapM_ (\deg -> do
    let rad = deg * pi / 180
        rot = Rotation AxisY rad
        dom = dominantProjection rot
        blend = blendFactor rot
    putStrLn $ "  " ++ padL 5 (show (round deg :: Int)) ++ "° │ "
            ++ padL 11 (showProj dom)
            ++ " │ " ++ showF blend
    ) [0, 30, 45, 60, 90, 120, 135, 150, 180]
  putStrLn ""

  -- The animation concept
  putStrLn "── The Animation ──"
  putStrLn ""
  putStrLn "  1. User sees the GIF from the front (normal playback)"
  putStrLn "  2. User rotates the cube (drag gesture)"
  putStrLn "  3. As rotation passes 45°, the SIDE face becomes dominant"
  putStrLn "  4. The NN re-computes voxels for the side view"
  putStrLn "  5. The side GIF plays: spatiotemporal cross-section"
  putStrLn "  6. Each row's evolution over time is VISIBLE"
  putStrLn "  7. Rotate back: front is updated too"
  putStrLn ""
  putStrLn "  The cube IS the memory."
  putStrLn "  Rotation reveals how the memory was encoded."
  putStrLn "  The NN improves the encoding for each view."
  putStrLn ""

  -- Axioms
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""
  check "V1  64³ = 262,144 voxels"              [axiom_V1]
  check "V2  3 distinct projections"             [axiom_V2]
  check "V3  each projection → 64 frames of 64²" [axiom_V3]
  check "V4  front slice at z=0 = first frame"   [axiom_V4]
  check "V5  side slice at x=0 = Y×Z frame"     [axiom_V5]
  check "V6  angle 0 → front"                    [axiom_V6]
  check "V7  angle π/2 → side"                   [axiom_V7]
  check "V8  update preserves cube size"          [axiom_V8]
  check "V9  identity update = no change"         [axiom_V9]
  check "V10 all palette indices ∈ {0..255}"     [axiom_V10]
  putStrLn ""

  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn "  The GIF is a cube. 64³ voxels. 256 colors."
  putStrLn "  Front = normal GIF. Side = time made visible."
  putStrLn "  Rotate to explore. NN updates for each view."
  putStrLn "  Global voxels survive rotation. Local voxels don't."
  putStrLn "  The rotation IS the animation. The cube IS the memory."
  putStrLn "════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

showProj :: Projection -> String
showProj p | p == front = "Front"
           | p == side  = "Side"
           | p == top   = "Top"
           | otherwise  = "Other"

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 100) :: Int) / 100.0 :: Double)
          in take 5 (s ++ repeat '0')

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      n = length results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name ++ " (" ++ show n ++ " cases)"
