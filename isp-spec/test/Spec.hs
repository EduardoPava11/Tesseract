module Main (main) where

import Test.QuickCheck
import System.Exit (exitFailure, exitSuccess)
import Control.Monad (foldM)

import qualified ISP.Laws.Physics      as LPhys
import qualified ISP.Laws.Noise        as LNoise
import qualified ISP.Laws.Uncertainty  as LUnc
import qualified ISP.Laws.Bayer        as LBay
import qualified ISP.Laws.Tesseract    as LTes
import qualified ISP.Laws.Pyramid      as LPyr
import qualified ISP.Laws.Palette      as LPal
import qualified ISP.Laws.Pipeline     as LPip
import qualified ISP.Laws.Oklab        as LOk
import qualified ISP.Laws.BayerDither  as LBD
import qualified ISP.Laws.ColorDouble  as LCD
import qualified ISP.Laws.Fingerprint  as LFp
import qualified ISP.Laws.PaletteSpine as LPS
import qualified ISP.Laws.BinomialBeauty as LBB

allLaws :: [(String, [(String, Property)])]
allLaws =
  [ ("Physics",      LPhys.laws)
  , ("Noise",        LNoise.laws)
  , ("Uncertainty",  LUnc.laws)
  , ("Bayer",        LBay.laws)
  , ("Tesseract",    LTes.laws)
  , ("Pyramid",      LPyr.laws)
  , ("Palette",      LPal.laws)
  , ("Pipeline",     LPip.laws)
  , ("Oklab",        LOk.laws)
  , ("BayerDither",  LBD.laws)
  , ("ColorDouble",  LCD.laws)
  , ("Fingerprint",  LFp.laws)
  , ("PaletteSpine", LPS.laws)
  , ("BinomialBeauty", LBB.laws)
  ]

runOne :: String -> (String, Property) -> IO Bool
runOne group (name, p) = do
  putStr ("  " <> group <> " / " <> name <> " ... ")
  r <- quickCheckWithResult stdArgs { maxSuccess = 100, chatty = False } p
  case r of
    Success{} -> putStrLn "OK"  >> pure True
    _         -> putStrLn "FAIL" >> pure False

main :: IO ()
main = do
  putStrLn "tesseract-isp laws"
  oks <- foldM (\acc (g, ls) ->
                   foldM (\a l -> (&& a) <$> runOne g l) acc ls)
               True allLaws
  if oks then exitSuccess else exitFailure
