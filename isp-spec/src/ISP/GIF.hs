-- | GIF89a encoding via JuicyPixels. Every frame shares one global palette
-- (the 4D palette projected to RGB by dropping T). Per-frame delays are
-- computed by the caller so that their sum equals the physical Delta t
-- between the two captures.
module ISP.GIF
  ( encodeAnimatedGif
  , paletteRGB
  , framesAsPixel8
  , deriveDelaysCs
  ) where

import qualified Data.ByteString.Lazy  as BL
import qualified Data.Vector           as V
import qualified Data.Vector.Storable  as VS
import           Data.Word             (Word8)
import           Codec.Picture         (Image (..), PixelRGB8)
import           Codec.Picture.Gif
                    ( GifDelay
                    , GifLooping (..)
                    , encodeGifImages
                    )

import ISP.Palette
import ISP.Tesseract

-- Build a 256-entry palette image (width 256, height 1) from our 4D palette.
paletteRGB :: Palette -> Image PixelRGB8
paletteRGB (Palette cents) =
  let n     = V.length cents
      bytes = VS.generate (n * 3) $ \i ->
        let (p, c) = i `divMod` 3
            T4D r g b _ = cents V.! p
        in case c of
             0 -> to8 r
             1 -> to8 g
             _ -> to8 b
  in Image n 1 bytes
  where
    to8 :: Double -> Word8
    to8 x =
      let y = round (max 0 (min 1 x) * 255) :: Int
      in fromIntegral y

-- Convert a list of per-frame index vectors into JuicyPixels Pixel8 images.
framesAsPixel8 :: Int -> Int -> [V.Vector Int] -> [Image Word8]
framesAsPixel8 w h = map (\idx ->
  Image w h (VS.generate (V.length idx) $ \i -> fromIntegral (idx V.! i)))

-- Split a total duration across K frames as integer centiseconds (GIF tick).
-- Guarantees each delay >= 1 cs and sum == round(totalSec * 100) when possible.
deriveDelaysCs :: Double -> Int -> [GifDelay]
deriveDelaysCs totalSec k
  | k <= 0 = []
  | otherwise =
      let totalCs = max k (round (totalSec * 100) :: Int)
          base    = totalCs `div` k
          extra   = totalCs - base * k
      in replicate extra (base + 1) ++ replicate (k - extra) base

-- Build an animated GIF from a shared palette + one Pixel8 image per frame.
encodeAnimatedGif
  :: Palette
  -> [GifDelay]
  -> [Image Word8]
  -> Either String BL.ByteString
encodeAnimatedGif pal delays imgs =
  let palImg = paletteRGB pal
      tuples = zipWith (\d img -> (palImg, d, img)) delays imgs
  in encodeGifImages LoopingForever tuples
