module Main (main) where

import Control.Monad (unless)
import Hedgehog (checkParallel)
import System.Exit (exitFailure)
import qualified NeoMusicScoreTests
import qualified NeoMusicTests
import qualified CliTests

main :: IO ()
main = do
  neoMusicResult <- checkParallel NeoMusicTests.neoMusicGroup
  scoreResult <- checkParallel NeoMusicScoreTests.scoreGroup
  cliResult <- checkParallel CliTests.cliGroup
  unless (neoMusicResult && scoreResult && cliResult) exitFailure
