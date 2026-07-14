module Main (main) where

import qualified Data.ByteString.Lazy as BL
import           Options.Applicative
import           System.Exit          (die)

import ISP.DNG
import ISP.Pipeline
import ISP.Pyramid
import ISP.Time

data CliOpts = CliOpts
  { cliDng1     :: !FilePath
  , cliDng2     :: !FilePath
  , cliOut      :: !FilePath
  , cliDelta    :: !Double
  , cliEstimator :: !EstimatorChoice
  , cliLevel    :: !Level
  , cliKIter    :: !Int
  }

data EstimatorChoice = Poisson | Effective !Double | Heisenberg
  deriving (Show)

estimatorOf :: EstimatorChoice -> TimeEstimator
estimatorOf Poisson       = PoissonInterarrival
estimatorOf (Effective p) = EffectiveIntegration p
estimatorOf Heisenberg    = HeisenbergPrecision

parser :: Parser CliOpts
parser = CliOpts
  <$> strArgument (metavar "DNG_A")
  <*> strArgument (metavar "DNG_B")
  <*> strOption   (short 'o' <> long "out" <> metavar "OUT.gif" <> value "/tmp/tesseract.gif")
  <*> option auto (long "delta" <> metavar "SECONDS" <> value 0.10 <> help "inter-capture delta t")
  <*> estimatorParser
  <*> levelParser
  <*> option auto (long "kmeans-iter" <> metavar "N" <> value 16)

estimatorParser :: Parser EstimatorChoice
estimatorParser =
      flag' Poisson      (long "estimator-poisson"    <> help "Poisson interarrival (default)")
  <|> (Effective <$> option auto (long "estimator-effective"  <> metavar "PHI_REF"))
  <|> flag' Heisenberg   (long "estimator-heisenberg" <> help "Heisenberg precision floor only")
  <|> pure Poisson

levelParser :: Parser Level
levelParser =
      flag' L1 (long "level-1")
  <|> flag' L2 (long "level-2")
  <|> flag' L3 (long "level-3")
  <|> flag' L4 (long "level-4")
  <|> flag' L5 (long "level-5")
  <|> flag' L6 (long "level-6")
  <|> flag' L7 (long "level-7")
  <|> flag' L8 (long "level-8")
  <|> pure L6

main :: IO ()
main = do
  opts <- execParser (info (parser <**> helper) fullDesc)
  ea <- readDNG (cliDng1 opts)
  eb <- readDNG (cliDng2 opts)
  dngA <- either die pure ea
  dngB <- either die pure eb
  let cfg = defaultConfig
              { cfgEstimator  = estimatorOf (cliEstimator opts)
              , cfgLevel      = cliLevel    opts
              , cfgKMeansIter = cliKIter    opts
              }
  case runPipeline cfg dngA dngB (cliDelta opts) of
    Left err   -> die err
    Right bs   -> do
      BL.writeFile (cliOut opts) bs
      putStrLn $ "Wrote " <> cliOut opts
