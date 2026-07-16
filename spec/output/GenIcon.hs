{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- GenIcon: Isometric Tesseract Hexagon — 1024×1024 App Icon
--
-- An isometric cube along (1,1,1) → hexagon silhouette.
-- A tesseract → hexagon inside hexagon.
-- Outer = epoch 0, inner = epoch 3.
-- 3 visible faces per cube, each a 4×4 color grid.
-- ════════════════════════════════════════════════════════════════

module GenIcon where

import Data.Char (chr)
import System.IO (withFile, IOMode(..), hSetBinaryMode, hPutStr)

-- ════════════════════════════════════════════════════════════════
-- § 1. PALETTE (from Tesseract.hs)
-- ════════════════════════════════════════════════════════════════

lookupColor :: Int -> Int -> Int -> (Double, Double, Double)
lookupColor a b c =
  ( (fromIntegral a + 0.5) / 4.0
  , (fromIntegral b + 0.5) / 4.0
  , (fromIntegral c + 0.5) / 4.0 )

-- Slightly brighter version for inner cube (epoch 3)
lookupTinted :: Int -> Int -> Int -> (Double, Double, Double)
lookupTinted a b c =
  let (r, g, bl) = lookupColor a b c
      f = 1.15  -- brighten inner cube
  in (min 1 (r * f), min 1 (g * f), min 1 (bl * f))

-- ════════════════════════════════════════════════════════════════
-- § 2. ISOMETRIC PROJECTION
-- ════════════════════════════════════════════════════════════════

-- Isometric: (x, y, z) in [0,1]³ → (screen_x, screen_y)
-- x = right axis, y = up axis, z = left-back axis
isoProject :: Double -> Double -> Double -> Double -> (Double, Double)
                     -> (Double, Double)
isoProject x y z scale (cx, cy) =
  let cos30 = sqrt 3 / 2  -- ≈ 0.866
      sin30 = 0.5
      sx = (x - z) * cos30 * scale + cx
      -- y goes DOWN (looking from above, top face visible)
      sy = (x + z) * sin30 * scale - y * scale + cy
  in (sx, sy)

-- ════════════════════════════════════════════════════════════════
-- § 3. FACE GEOMETRY — 3 rhombus faces of isometric cube
-- ════════════════════════════════════════════════════════════════

-- Each face is defined by an origin and two edge vectors in 3D.
-- We project the 4×4 grid cells of each face.

data Face = Face
  { fOrigin :: (Double, Double, Double)
  , fU      :: (Double, Double, Double)  -- edge direction 1
  , fV      :: (Double, Double, Double)  -- edge direction 2
  , fColorFn :: Int -> Int -> (Double, Double, Double)  -- (iu, iv) → color
  }

-- | Top face: XZ plane at y=1. Shows R (x) × G (z). B = min (c=0) → warm tones.
topFace :: Face
topFace = Face
  { fOrigin = (0, 1, 0)
  , fU = (1, 0, 0)   -- x direction = R axis
  , fV = (0, 0, 1)   -- z direction = G axis (maps to b)
  , fColorFn = \iu iv -> lookupColor iu iv 0  -- a=iu, b=iv, c=0 (warm: no blue)
  }

-- | Left face: YZ plane at x=0. Shows G (z) × B (y inverted). R = min (a=0).
leftFace :: Face
leftFace = Face
  { fOrigin = (0, 0, 0)
  , fU = (0, 0, 1)   -- z direction = G axis (b)
  , fV = (0, 1, 0)   -- y direction = B axis (c) going up
  , fColorFn = \iu iv -> lookupColor 0 iu iv  -- a=0, b=iu, c=iv
  }

-- | Right face: XY plane at z=0. Shows R (x) × B (y inverted). G = min (b=0).
rightFace :: Face
rightFace = Face
  { fOrigin = (0, 0, 0)
  , fU = (1, 0, 0)   -- x direction = R axis (a)
  , fV = (0, 1, 0)   -- y direction = B axis (c) going up
  , fColorFn = \iu iv -> lookupColor iu 0 iv  -- a=iu, b=0, c=iv
  }

-- Inner cube faces (epoch 3, tinted)
topFaceInner :: Face
topFaceInner = topFace { fColorFn = \iu iv -> lookupTinted iu iv 0 }
leftFaceInner :: Face
leftFaceInner = leftFace { fColorFn = \iu iv -> lookupTinted 0 iu iv }
rightFaceInner :: Face
rightFaceInner = rightFace { fColorFn = \iu iv -> lookupTinted iu 0 iv }

-- ════════════════════════════════════════════════════════════════
-- § 4. POINT-IN-PARALLELOGRAM TEST
-- ════════════════════════════════════════════════════════════════

-- | Test if screen point (px, py) falls inside a projected parallelogram
--   defined by origin + u*t1 + v*t2 where t1, t2 ∈ [lo, hi).
--   Returns Just (t1, t2) if inside, Nothing otherwise.
pointInQuad :: Double -> (Double, Double)
            -> (Double, Double) -> (Double, Double)
            -> (Double, Double) -> (Double, Double)
            -> Maybe (Double, Double)
pointInQuad _scale (px, py) (ox, oy) (ux, uy) (vx, vy) _bounds =
  -- Solve: (px, py) = (ox, oy) + t1*(ux, uy) + t2*(vx, vy)
  let det = ux * vy - uy * vx
  in if abs det < 1e-10 then Nothing
     else let dx = px - ox
              dy = py - oy
              t1 = (dx * vy - dy * vx) / det
              t2 = (ux * dy - uy * dx) / det
          in if t1 >= 0 && t1 < 1 && t2 >= 0 && t2 < 1
             then Just (t1, t2)
             else Nothing

-- ════════════════════════════════════════════════════════════════
-- § 5. RENDER
-- ════════════════════════════════════════════════════════════════

-- | For a pixel (px, py), determine its color.
renderPixel :: Int -> Int -> (Int, Int, Int)
renderPixel px py =
  let fpx = fromIntegral px
      fpy = fromIntegral py
      -- Try outer cube faces first, then inner, then connecting edges
      result = tryFaces fpx fpy outerScale outerCenter outerFaces
           >>= \_ -> Nothing  -- fallback chain
      outerResult = tryFaces fpx fpy outerScale outerCenter outerFaces
      innerResult = tryFaces fpx fpy innerScale innerCenter innerFaces
      edgeResult = tryEdges fpx fpy
  in case outerResult of
       Just (r, g, b) -> toRGB8 r g b
       Nothing -> case innerResult of
         Just (r, g, b) -> toRGB8 r g b
         Nothing -> case edgeResult of
           Just (r, g, b) -> toRGB8 r g b
           Nothing -> (5, 5, 10)  -- dark background
  where
    outerScale = 420.0
    innerScale = 180.0
    outerCenter = (512, 540)
    innerCenter = (512, 540)
    outerFaces = [topFace, leftFace, rightFace]
    innerFaces = [topFaceInner, leftFaceInner, rightFaceInner]

-- | Try all 3 faces of a cube at given scale/center
tryFaces :: Double -> Double -> Double -> (Double, Double)
         -> [Face] -> Maybe (Double, Double, Double)
tryFaces px py scale center faces =
  let results = map (tryOneFace px py scale center) faces
  in case [r | Just r <- results] of
       (r:_) -> Just r
       [] -> Nothing

-- | Try one face: project its 4 corners, check if pixel is inside
tryOneFace :: Double -> Double -> Double -> (Double, Double)
           -> Face -> Maybe (Double, Double, Double)
tryOneFace px py scale (cx, cy) face =
  let -- Project face origin and edge endpoints
      (ox, oy, oz) = fOrigin face
      (ux, uy, uz) = fU face
      (vx, vy, vz) = fV face
      -- Screen coordinates of origin and edge vectors
      (sox, soy) = isoProject ox oy oz scale (cx, cy)
      (eux, euy) = isoProject (ox+ux) (oy+uy) (oz+uz) scale (cx, cy)
      (evx, evy) = isoProject (ox+vx) (oy+vy) (oz+vz) scale (cx, cy)
      -- Screen-space edge vectors
      sux = eux - sox
      suy = euy - soy
      svx = evx - sox
      svy = evy - soy
  in case pointInQuad scale (px, py) (sox, soy) (sux, suy) (svx, svy) (0, 1) of
       Just (t1, t2) ->
         let -- Which cell in the 4×4 grid?
             iu = min 3 (floor (t1 * 4))
             iv = min 3 (floor (t2 * 4))
             (r, g, b) = fColorFn face iu iv
             -- Subtle cell border darkening
             ft1 = t1 * 4 - fromIntegral iu
             ft2 = t2 * 4 - fromIntegral iv
             border = if ft1 < 0.04 || ft1 > 0.96 || ft2 < 0.04 || ft2 > 0.96
                      then 0.7 else 1.0
         in Just (r * border, g * border, b * border)
       Nothing -> Nothing

-- | Draw connecting edges between outer and inner cube vertices
tryEdges :: Double -> Double -> Maybe (Double, Double, Double)
tryEdges px py =
  let outerScale = 420.0
      innerScale = 180.0
      center = (512.0, 540.0)
      -- 8 vertices of a unit cube
      verts = [(x, y, z) | x <- [0, 1], y <- [0, 1], z <- [0, 1]]
      edges = [ (isoProject x y z outerScale center,
                 isoProject x y z innerScale center)
              | (x, y, z) <- verts ]
      -- Check if pixel is near any edge line
      nearEdge = any (\((x1,y1),(x2,y2)) ->
        distToSegment px py x1 y1 x2 y2 < 1.8) edges
  in if nearEdge
     then Just (0.85, 0.85, 0.92)  -- white-ish edge
     else Nothing

-- | Also draw cube wireframe edges
-- (included in the face rendering via border darkening)

-- | Distance from point to line segment
distToSegment :: Double -> Double -> Double -> Double -> Double -> Double -> Double
distToSegment px py x1 y1 x2 y2 =
  let dx = x2 - x1
      dy = y2 - y1
      lenSq = dx * dx + dy * dy
  in if lenSq < 1e-10 then sqrt ((px-x1)^(2::Int) + (py-y1)^(2::Int))
     else let t = max 0 (min 1 (((px-x1)*dx + (py-y1)*dy) / lenSq))
              projX = x1 + t * dx
              projY = y1 + t * dy
          in sqrt ((px - projX)^(2::Int) + (py - projY)^(2::Int))

-- | Also draw outer/inner cube wireframe
tryWireframe :: Double -> Double -> Maybe (Double, Double, Double)
tryWireframe px py =
  let outerScale = 420.0
      innerScale = 180.0
      center = (512.0, 540.0)
      -- Cube edges: 12 per cube
      cubeEdges = [ ((0,0,0),(1,0,0)), ((0,0,0),(0,1,0)), ((0,0,0),(0,0,1))
                  , ((1,1,1),(0,1,1)), ((1,1,1),(1,0,1)), ((1,1,1),(1,1,0))
                  , ((1,0,0),(1,1,0)), ((1,0,0),(1,0,1))
                  , ((0,1,0),(1,1,0)), ((0,1,0),(0,1,1))
                  , ((0,0,1),(1,0,1)), ((0,0,1),(0,1,1)) ]
      projectEdge s ((x1,y1,z1),(x2,y2,z2)) =
        (isoProject x1 y1 z1 s center, isoProject x2 y2 z2 s center)
      outerEdges = map (projectEdge outerScale) cubeEdges
      innerEdges = map (projectEdge innerScale) cubeEdges
      allEdges = outerEdges ++ innerEdges
      nearAny = any (\((x1,y1),(x2,y2)) ->
        distToSegment px py x1 y1 x2 y2 < 1.5) allEdges
  in if nearAny then Just (0.7, 0.7, 0.78) else Nothing

toRGB8 :: Double -> Double -> Double -> (Int, Int, Int)
toRGB8 r g b =
  ( max 0 (min 255 (round (r * 255)))
  , max 0 (min 255 (round (g * 255)))
  , max 0 (min 255 (round (b * 255))) )

-- ════════════════════════════════════════════════════════════════
-- § 6. FULL RENDER WITH LAYERED COMPOSITING
-- ════════════════════════════════════════════════════════════════

renderPixelFull :: Int -> Int -> (Int, Int, Int)
renderPixelFull px py =
  let fpx = fromIntegral px
      fpy = fromIntegral py
      outerScale = 420.0
      innerScale = 180.0
      center = (512.0, 540.0)
      -- Layer 1: outer cube faces (back faces first for correct occlusion)
      outerLeft = tryOneFace fpx fpy outerScale center leftFace
      outerRight = tryOneFace fpx fpy outerScale center rightFace
      outerTop = tryOneFace fpx fpy outerScale center topFace
      -- Layer 2: connecting edges
      edges = tryEdges fpx fpy
      -- Layer 3: inner cube faces
      innerLeft = tryOneFace fpx fpy innerScale center leftFaceInner
      innerRight = tryOneFace fpx fpy innerScale center rightFaceInner
      innerTop = tryOneFace fpx fpy innerScale center topFaceInner
      -- Layer 4: wireframe
      wire = tryWireframe fpx fpy
      -- Composite: painter's algorithm for isometric view
      -- Top face is the "lid" — drawn LAST (highest priority) for outer and inner
      -- Left and right are the "walls" — drawn first (behind the top)
      innerWalls = case (innerLeft, innerRight) of
                     (Just c, _) -> Just c
                     (_, Just c) -> Just c
                     _ -> Nothing
      outerWalls = case (outerLeft, outerRight) of
                     (Just c, _) -> Just c
                     (_, Just c) -> Just c
                     _ -> Nothing
  in -- Priority: innerTop > innerWalls > outerTop > outerWalls > wire > edges > bg
     -- Filled faces always beat wireframe lines
     case innerTop of
       Just (r, g, b) -> toRGB8 r g b
       Nothing -> case innerWalls of
         Just (r, g, b) -> toRGB8 r g b
         Nothing -> case outerTop of
           Just (r, g, b) -> toRGB8 r g b
           Nothing -> case outerWalls of
             Just (r, g, b) -> toRGB8 r g b
             Nothing -> case wire of
               Just (r, g, b) -> toRGB8 r g b
               Nothing -> case edges of
                 Just (r, g, b) -> toRGB8 r g b
                 Nothing -> (5, 5, 10)

-- ════════════════════════════════════════════════════════════════
-- § 7. MAIN — Write 1024×1024 PPM
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "Generating 1024×1024 isometric tesseract icon..."
  let size = 1024
  withFile "tesseract_icon.ppm" WriteMode $ \h -> do
    hSetBinaryMode h True
    hPutStr h $ "P6\n" ++ show size ++ " " ++ show size ++ "\n255\n"
    mapM_ (\py ->
      mapM_ (\px -> do
        let (r, g, b) = renderPixelFull px py
        hPutStr h [chr r, chr g, chr b]
        ) [0..size-1]
      ) [0..size-1]
  putStrLn "Written: tesseract_icon.ppm"
  putStrLn "Converting to PNG..."
