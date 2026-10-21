module Main (main) where

import Control.Monad (unless)
import Hedgehog (checkParallel)
import System.Exit (exitFailure)
import qualified NeoMusicScoreTests
import qualified NeoMusicTests

main :: IO ()
main = do
  neoMusicResult <- checkParallel NeoMusicTests.neoMusicGroup
  scoreResult <- checkParallel NeoMusicScoreTests.scoreGroup
  unless (neoMusicResult && scoreResult) exitFailure
