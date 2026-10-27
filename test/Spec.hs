module Main (main) where

import Control.Monad (unless)
import Hedgehog (checkParallel)
import System.Exit (exitFailure)
import qualified CliTests
import qualified GoldenTests
import qualified NeoMusicScoreTests
import qualified NeoMusicTests

main :: IO ()
main = do
  neoMusicResult <- checkParallel NeoMusicTests.neoMusicGroup
  scoreResult <- checkParallel NeoMusicScoreTests.scoreGroup
  cliResult <- checkParallel CliTests.cliGroup
  goldenResult <- checkParallel GoldenTests.goldenGroup
  unless (neoMusicResult && scoreResult && cliResult && goldenResult) exitFailure
