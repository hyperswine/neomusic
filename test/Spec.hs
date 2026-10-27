module Main (main) where

import Control.Monad (unless)
import Hedgehog (checkParallel)
import System.Exit (exitFailure)
import qualified NeoMusicScoreTests
import qualified NeoMusicTests
import qualified GoldenTests

main :: IO ()
main = do
  neoMusicResult <- checkParallel NeoMusicTests.neoMusicGroup
  scoreResult <- checkParallel NeoMusicScoreTests.scoreGroup
  goldenResult <- checkParallel GoldenTests.goldenGroup
  unless (neoMusicResult && scoreResult && goldenResult) exitFailure
