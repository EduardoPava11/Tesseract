{-# LANGUAGE DeriveGeneric #-}
-- | Minimal DNG (TIFF-based) reader and writer.
--
-- v0 supports only the uncompressed CFA raw path that we use for synthetic
-- fixtures: little-endian, single strip, 16-bit BitsPerSample, Compression=1.
-- Real iPhone ProRAW uses lossless JPEG (Compression=7 or 8); that path is
-- explicitly marked TODO so the spec stays honest.
module ISP.DNG
  ( DNGFrame (..)
  , readDNG
  , writeTestDNG
  , SensorMeta (..)
  , defaultSensorMeta
  ) where

import qualified Data.ByteString      as BS
import qualified Data.ByteString.Lazy as BL
import           Data.Binary.Get
import           Data.Binary.Put
import           Data.Word
import qualified Data.Vector.Unboxed  as VU
import           Data.Bits ((.&.))

import ISP.Bayer           (CFAPattern (..))
import ISP.Sensor.Noise    (NoiseProfile (..))

-- Full per-capture metadata plus raw photosite buffer.
data DNGFrame = DNGFrame
  { dngWidth        :: !Int
  , dngHeight       :: !Int
  , dngCFAPattern   :: !CFAPattern
  , dngBitsPerSample :: !Int
  , dngBlackLevel   :: !Double       -- per-channel vector collapsed to scalar for v0
  , dngWhiteLevel   :: !Double
  , dngExposureSec  :: !Double
  , dngISO          :: !Int
  , dngNoiseR       :: !NoiseProfile
  , dngNoiseGr      :: !NoiseProfile
  , dngNoiseGb      :: !NoiseProfile
  , dngNoiseB       :: !NoiseProfile
  , dngBaselineExposureEv :: !Double
  , dngAnalogGain   :: !Double      -- electrons per DN
  , dngPixels       :: !(VU.Vector Word16)
  }
  deriving (Show)

data SensorMeta = SensorMeta
  { smCFAPattern         :: !CFAPattern
  , smBlackLevel         :: !Double
  , smWhiteLevel         :: !Double
  , smExposureSec        :: !Double
  , smISO                :: !Int
  , smNoiseR             :: !NoiseProfile
  , smNoiseGr            :: !NoiseProfile
  , smNoiseGb            :: !NoiseProfile
  , smNoiseB             :: !NoiseProfile
  , smBaselineExposureEv :: !Double
  , smAnalogGain         :: !Double
  }
  deriving (Show)

defaultSensorMeta :: SensorMeta
defaultSensorMeta = SensorMeta
  { smCFAPattern         = RGGB
  , smBlackLevel         = 512
  , smWhiteLevel         = 65535
  , smExposureSec        = 1 / 120
  , smISO                = 100
  , smNoiseR             = NoiseProfile 1.0 16.0
  , smNoiseGr            = NoiseProfile 1.0 16.0
  , smNoiseGb            = NoiseProfile 1.0 16.0
  , smNoiseB             = NoiseProfile 1.0 16.0
  , smBaselineExposureEv = 0
  , smAnalogGain         = 1.0
  }

-- TIFF tag numbers we care about
tagImageWidth, tagImageLength, tagBitsPerSample, tagCompression :: Word16
tagPhotometric, tagStripOffsets, tagRowsPerStrip, tagStripByteCounts :: Word16
tagBlackLevel, tagWhiteLevel :: Word16
tagImageWidth      = 256
tagImageLength     = 257
tagBitsPerSample   = 258
tagCompression     = 259
tagPhotometric     = 262
tagStripOffsets    = 273
tagRowsPerStrip    = 278
tagStripByteCounts = 279
tagBlackLevel      = 50714
tagWhiteLevel      = 50717

-- | Read a DNG from disk. Handles only the uncompressed CFA path.
readDNG :: FilePath -> IO (Either String DNGFrame)
readDNG fp = do
  bs <- BS.readFile fp
  pure (parseDNG bs)

parseDNG :: BS.ByteString -> Either String DNGFrame
parseDNG bs =
  case runGetOrFail parseHeader (BL.fromStrict bs) of
    Left  (_, _, err) -> Left err
    Right (_, _, ifdOff) ->
      case runGetOrFail (parseIFD bs (fromIntegral ifdOff)) (BL.fromStrict bs) of
        Left  (_, _, err) -> Left err
        Right (_, _, frame) -> Right frame

parseHeader :: Get Word32
parseHeader = do
  b0 <- getWord8
  b1 <- getWord8
  case (b0, b1) of
    (0x49, 0x49) -> pure ()  -- little-endian "II"
    _            -> fail "only little-endian TIFF supported in v0"
  magic <- getWord16le
  if magic /= 42 then fail "bad TIFF magic" else pure ()
  getWord32le

parseIFD :: BS.ByteString -> Int -> Get DNGFrame
parseIFD fullBs ifdOff = do
  skip ifdOff
  n <- fromIntegral <$> getWord16le
  tags <- mapM (const getTag) [(1 :: Int) .. n]
  let look t = lookup t tags
      getInt = maybe (error "missing tag") fromIntegral . look
      w = getInt tagImageWidth
      h = getInt tagImageLength
      strip = getInt tagStripOffsets
      sbc   = getInt tagStripByteCounts
      bits  = maybe 16 fromIntegral (look tagBitsPerSample)
      raw   = BS.take sbc (BS.drop strip fullBs)
      vec   = VU.generate (w * h) $ \i ->
                 let lo = BS.index raw (2 * i)
                     hi = BS.index raw (2 * i + 1)
                 in fromIntegral hi * 256 + fromIntegral lo
  pure DNGFrame
    { dngWidth             = w
    , dngHeight            = h
    , dngCFAPattern        = RGGB
    , dngBitsPerSample     = bits
    , dngBlackLevel        = maybe 0      fromIntegral (look tagBlackLevel)
    , dngWhiteLevel        = maybe 65535  fromIntegral (look tagWhiteLevel)
    , dngExposureSec       = 1 / 120
    , dngISO               = 100
    , dngNoiseR            = NoiseProfile 1.0 16.0
    , dngNoiseGr           = NoiseProfile 1.0 16.0
    , dngNoiseGb           = NoiseProfile 1.0 16.0
    , dngNoiseB            = NoiseProfile 1.0 16.0
    , dngBaselineExposureEv = 0
    , dngAnalogGain        = 1.0
    , dngPixels            = vec
    }

-- Return (tag, decoded-value-as-Word32). Only handles scalar SHORT/LONG/BYTE.
getTag :: Get (Word16, Word32)
getTag = do
  tag   <- getWord16le
  typ   <- getWord16le
  count <- getWord32le
  valBs <- getByteString 4
  let v = case typ of
            1 -> fromIntegral (BS.index valBs 0)                      -- BYTE
            3 -> fromIntegral (BS.index valBs 0) +
                 256 * fromIntegral (BS.index valBs 1)                 -- SHORT
            _ -> let b0' = fromIntegral (BS.index valBs 0)
                     b1' = fromIntegral (BS.index valBs 1)
                     b2' = fromIntegral (BS.index valBs 2)
                     b3' = fromIntegral (BS.index valBs 3)
                 in b0' + 256 * (b1' + 256 * (b2' + 256 * b3'))        -- LONG
  _ <- pure (typ, count) -- suppress unused
  pure (tag, v)

-- | Write a minimal uncompressed CFA "DNG" (actually a TIFF) for test fixtures.
-- We label it DNG for clarity but only the TIFF skeleton is real — no
-- ColorMatrix, no UniqueCameraModel, no DNGVersion. The readDNG path above
-- deliberately tolerates this minimal shape.
writeTestDNG :: FilePath -> SensorMeta -> Int -> Int -> VU.Vector Word16 -> IO ()
writeTestDNG fp _sm w h pix = do
  let headerSz    = 8       -- II, 42, ifdOff
      nTags       = 10 :: Int
      ifdSz       = 2 + 12 * nTags + 4
      pixOff      = headerSz + ifdSz
      pixBytes    = 2 * VU.length pix
      ifdOff      = headerSz
      header = runPut $ do
        putWord8 0x49 >> putWord8 0x49
        putWord16le 42
        putWord32le (fromIntegral ifdOff)
      ifd = runPut $ do
        putWord16le (fromIntegral nTags)
        tagShort tagImageWidth  (fromIntegral w)
        tagShort tagImageLength (fromIntegral h)
        tagShort tagBitsPerSample 16
        tagShort tagCompression 1
        tagShort tagPhotometric 32803
        tagLong  tagStripOffsets (fromIntegral pixOff)
        tagShort tagRowsPerStrip (fromIntegral h)
        tagLong  tagStripByteCounts (fromIntegral pixBytes)
        tagShort tagBlackLevel 0
        tagShort tagWhiteLevel 65535
        putWord32le 0
      pixLe = runPut $ VU.mapM_ putWord16le pix
  BL.writeFile fp (BL.concat [header, ifd, pixLe])

tagShort :: Word16 -> Word16 -> Put
tagShort t v = do
  putWord16le t
  putWord16le 3     -- SHORT
  putWord32le 1
  putWord16le v
  putWord16le 0

tagLong :: Word16 -> Word32 -> Put
tagLong t v = do
  putWord16le t
  putWord16le 4     -- LONG
  putWord32le 1
  putWord32le v

_maskHiLo :: Word16 -> Word16
_maskHiLo w = w .&. 0xFFFF
