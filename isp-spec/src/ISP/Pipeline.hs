-- | Top-level ISP pipeline: two DNGs + inter-capture Delta t -> animated GIF.
-- Every choice is explicit in 'ISPConfig'; there is no hidden defaulting,
-- no black box.
module ISP.Pipeline
  ( ISPConfig (..)
  , DebayerMethod (..)
  , defaultConfig
  , runPipeline
  , sampleDNG
  , interpolateFrames
  ) where

import qualified Data.ByteString.Lazy as BL
import qualified Data.Vector          as V
import qualified Data.Vector.Unboxed  as VU

import ISP.Bayer             (Quad (..))
import ISP.DNG
import ISP.GIF
import ISP.Palette
import ISP.Pyramid
import ISP.Sensor.Noise
import ISP.Sensor.Physics    (Channel (..))
import ISP.Sensor.Uncertainty
import ISP.Tesseract
import ISP.Time

data DebayerMethod = BinQuad | NearestNeighbor
  deriving (Eq, Show)

data ISPConfig = ISPConfig
  { cfgEstimator        :: !TimeEstimator
  , cfgLevel            :: !Level
  , cfgPalette          :: !PaletteMethod
  , cfgDebayer          :: !DebayerMethod
  , cfgKMeansIter       :: !Int
  , cfgWhiteLevelNorm   :: !Bool
  }
  deriving (Eq, Show)

defaultConfig :: ISPConfig
defaultConfig = ISPConfig
  { cfgEstimator      = PoissonInterarrival
  , cfgLevel          = L6
  , cfgPalette        = KMeans4D
  , cfgDebayer        = BinQuad
  , cfgKMeansIter     = 16
  , cfgWhiteLevelNorm = True
  }

runPipeline
  :: ISPConfig
  -> DNGFrame        -- capture A (at T = 0)
  -> DNGFrame        -- capture B (at T = deltaT)
  -> Double          -- deltaT in seconds
  -> Either String BL.ByteString
runPipeline cfg dngA dngB deltaT = do
  let lvl    = cfgLevel cfg
      s      = pyramidS lvl
      k      = pyramidK lvl
      ptsA   = sampleDNG cfg dngA 0
      ptsB   = sampleDNG cfg dngB deltaT
      frames = interpolateFrames k ptsA ptsB
      allPts = V.concat frames
      nPts   = V.length allPts
      kPal   = min 256 nPts
      seeds  = V.generate kPal $ \i ->
                 allPts V.! ((i * (max 1 nPts)) `div` kPal)
      (pal, _)    = kmeans (cfgKMeansIter cfg) allPts seeds
      indicesFr   = map (\pts -> assign pts (paletteCentroids pal)) frames
      imgs        = framesAsPixel8 s s indicesFr
      delays      = deriveDelaysCs deltaT k
  encodeAnimatedGif pal delays imgs

-- | Downsample a DNG to the target level's S x S grid of (R, G, B, T) points.
-- Uses nearest-quad sampling (no anti-alias) for v0 clarity.
sampleDNG :: ISPConfig -> DNGFrame -> Double -> V.Vector (T4D Double)
sampleDNG cfg dng tCapture =
  let s     = pyramidS (cfgLevel cfg)
      w     = dngWidth dng
      h     = dngHeight dng
      black = dngBlackLevel dng
      white = dngWhiteLevel dng
      gain  = dngAnalogGain dng
      tExp  = dngExposureSec dng
      pix   = dngPixels dng
      raw i j =
        let idx = j * w + i
        in fromIntegral (pix VU.! idx) :: Double
      -- Sample a 2x2 Bayer quad at the top-left (2*qi, 2*qj).
      quadAt qi qj =
        let i0 = 2 * qi
            j0 = 2 * qj
            r  = raw i0       j0
            gr = raw (i0 + 1) j0
            gb = raw i0       (j0 + 1)
            b  = raw (i0 + 1) (j0 + 1)
        in (r, gr, gb, b)
      -- Convert DN to photon count (electrons).
      elecs x = gain * max 0 (x - black)
      -- Poisson variance on the electron-domain count.
      varElec x = max 1 (elecs x)
      -- Estimate T for one pixel of a given channel.
      estT ch n =
        let vN = max 1 n
        in estimateT (cfgEstimator cfg) ch tExp n vN
      -- White-level normalization for the palette domain.
      norm x =
        if cfgWhiteLevelNorm cfg
          then max 0 (min 1 ((x - black) / max 1 (white - black)))
          else x
  in V.generate (s * s) $ \k ->
       let (si, sj) = k `divMod` s
           qi       = (si * (w `div` 2)) `div` s
           qj       = (sj * (h `div` 2)) `div` s
           (r, gr, gb, b) = quadAt qi qj
           rU   = Uncertain (norm r)  (sqrt (varElec r))
           grU  = Uncertain (norm gr) (sqrt (varElec gr))
           gbU  = Uncertain (norm gb) (sqrt (varElec gb))
           bU   = Uncertain (norm b)  (sqrt (varElec b))
           tR   = estT R  (elecs r)
           tGr  = estT Gr (elecs gr)
           tGb  = estT Gb (elecs gb)
           tB   = estT B  (elecs b)
           -- Combine per-channel T estimates by inverse-variance weight.
           tPix = weightedMeanU [tR, tGr, tGb, tB]
           -- Shift by capture time so A is at T=0, B is at T=deltaT in the
           -- output coordinate system.
           tShifted = Uncertain (uValue tPix + tCapture) (uSigma tPix)
           p4   = project5Dto4D (Quad rU grU gbU bU) tShifted
       in fmap uValue p4

-- | Linearly interpolate K frames between two S x S point grids.
interpolateFrames
  :: Int
  -> V.Vector (T4D Double)
  -> V.Vector (T4D Double)
  -> [V.Vector (T4D Double)]
interpolateFrames k ptsA ptsB
  | k <= 1    = [ptsA]
  | otherwise =
      [ V.zipWith (lerp4 alpha) ptsA ptsB
      | f <- [0 .. k - 1]
      , let alpha = fromIntegral f / fromIntegral (k - 1)
      ]
  where
    lerp4 a (T4D r1 g1 b1 t1) (T4D r2 g2 b2 t2) =
      T4D ((1 - a) * r1 + a * r2)
          ((1 - a) * g1 + a * g2)
          ((1 - a) * b1 + a * b2)
          ((1 - a) * t1 + a * t2)
