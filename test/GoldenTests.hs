{-# LANGUAGE OverloadedStrings #-}
-- | Golden regression snapshots for the parser, MIDI export and audio.
--
-- Each fixture is parsed, exported to MIDI and rendered. The parse
-- (@show@ of the score), the MIDI bytes and a per-block audio summary
-- (peak and RMS of each 50 ms block, both channels, before 16/24-bit
-- quantisation) are compared with files in test/golden/regression/.
-- MIDI and the parse must match exactly; audio within 1e-9, which allows
-- for libm differences between platforms but catches any real DSP change.
--
-- After an intended change, regenerate with
--   NEOMUSIC_GOLDEN_UPDATE=1 cabal test
-- and review the diff of test/golden/regression/.
module GoldenTests (goldenGroup) where

import Control.Monad (forM, when)
import qualified Data.ByteString.Lazy as BL
import qualified Data.Vector.Unboxed as VU
import Hedgehog
import NeoMusic.Audio (Mix (..), renderTimelineMix)
import NeoMusic.Language (Document (..), loadDocument)
import NeoMusic.Midi (midi)
import qualified NeoMusic.Score as S
import System.Environment (lookupEnv)
import System.FilePath (takeBaseName, (</>))
import Text.Read (readMaybe)

fixtures :: [FilePath]
fixtures =
  [ "examples/neomusic/scale.neomusic", "examples/neomusic/voices.neomusic"
  , "examples/neomusic/ties.neomusic", "examples/neomusic/cents.neomusic"
  , "examples/neomusic/composition.neomusic", "examples/neomusic/signals.neomusic"
  , "test/golden/regression/hall.neomusic" ]

goldenDir :: FilePath
goldenDir = "test/golden/regression"

-- | Peak and RMS of each 50 ms block of a channel.
summary :: Int -> VU.Vector Double -> [(Double, Double)]
summary rate xs =
  [ (VU.maximum (VU.map abs b), sqrt (VU.sum (VU.map (^ (2 :: Int)) b) / fromIntegral (VU.length b)))
  | from <- [0, block .. VU.length xs - 1]
  , let b = VU.slice from (min block (VU.length xs - from)) xs ]
  where block = max 1 (rate `div` 20)

goldenGroup :: Group
goldenGroup = Group "golden regressions: parser, MIDI, audio"
  [ ("fixtures match their snapshots", withTests 1 $ property $ do
      update <- evalIO (maybe False (not . null) <$> lookupEnv "NEOMUSIC_GOLDEN_UPDATE")
      results <- evalIO $ forM fixtures $ \path -> do
        doc <- loadDocument [] path >>= either fail pure
        let name = takeBaseName path
            perf = performance doc
            parsed = show (score doc) ++ "\n"
        bytes <- either fail pure (midi perf (score doc))
        timeline <- either fail pure (S.render perf (score doc))
        (l, r) <- either fail pure (renderTimelineMix (S.mix perf) timeline)
        let rate = mixRate (S.mix perf)
            audio = (VU.length l, summary rate l, summary rate r)
            parseFile = goldenDir </> (name ++ ".parse")
            midiFile = goldenDir </> (name ++ ".mid")
            audioFile = goldenDir </> (name ++ ".audio")
        when update $ do
          writeFile parseFile parsed
          BL.writeFile midiFile bytes
          writeFile audioFile (show audio ++ "\n")
        parsed' <- readFile parseFile
        bytes' <- BL.readFile midiFile
        audio' <- readMaybe <$> readFile audioFile
        pure (name, parsed' == parsed, bytes' == bytes, fmap (close audio) audio')
      mapM_ (\(name, p, m, a) -> do
        annotate name
        (name, p, m, a) === (name, True, True, Just True)) results)
  ]
  where
    close (n, l, r) (n', l', r') = n == n' && length l == length l' && length r == length r'
      && and (zipWith near (concatPairs l) (concatPairs l')) && and (zipWith near (concatPairs r) (concatPairs r'))
    concatPairs = concatMap (\(a, b) -> [a, b])
    near a b = abs (a - b) <= 1e-9
