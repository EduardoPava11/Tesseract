module Main (main) where

import qualified Data.Aeson           as A
import qualified Data.Aeson.Encode.Pretty as A
import qualified Data.ByteString.Lazy as BL
import           GHC.Generics         (Generic)
import           System.Directory     (createDirectoryIfMissing)

import ISP.Pyramid
import ISP.Sensor.Physics

-- Small golden payloads that the Swift side can load to verify that the
-- numeric constants and pyramid levels match the Haskell spec exactly.

data ChannelGolden = ChannelGolden
  { cgName             :: String
  , cgWavelengthNm     :: Double
  , cgFwhmNm           :: Double
  , cgPeakTransmission :: Double
  , cgPhotonEnergyJ    :: Double
  , cgHeisenberg_N1e4  :: Double
  , cgHeisenberg_N1e6  :: Double
  } deriving (Generic)
instance A.ToJSON ChannelGolden

data LevelGolden = LevelGolden
  { lgName :: String
  , lgS    :: Int
  , lgK    :: Int
  , lgSK   :: Int
  } deriving (Generic)
instance A.ToJSON LevelGolden

data Golden = Golden
  { goldenConstants :: ConstGolden
  , goldenChannels  :: [ChannelGolden]
  , goldenLevels    :: [LevelGolden]
  } deriving (Generic)
instance A.ToJSON Golden

data ConstGolden = ConstGolden
  { cstH        :: Double
  , cstC        :: Double
  , cstHbar     :: Double
  , cstHc       :: Double
  } deriving (Generic)
instance A.ToJSON ConstGolden

channelGolden :: Channel -> ChannelGolden
channelGolden c = ChannelGolden
  { cgName             = show c
  , cgWavelengthNm     = wavelengthNm c
  , cgFwhmNm           = fwhmNm c
  , cgPeakTransmission = peakTransmission c
  , cgPhotonEnergyJ    = photonEnergyJ c
  , cgHeisenberg_N1e4  = heisenbergFloorSec c 1e4
  , cgHeisenberg_N1e6  = heisenbergFloorSec c 1e6
  }

levelGolden :: Level -> LevelGolden
levelGolden l = LevelGolden (show l) (pyramidS l) (pyramidK l) (pyramidS l * pyramidK l)

main :: IO ()
main = do
  createDirectoryIfMissing True "golden/vectors"
  let payload = Golden
        { goldenConstants = ConstGolden planckH lightC planckHbar hcJm
        , goldenChannels  = map channelGolden allChannels
        , goldenLevels    = map levelGolden   allLevels
        }
  BL.writeFile "golden/vectors/constants.json" (A.encodePretty payload)
  putStrLn "Wrote golden/vectors/constants.json"
