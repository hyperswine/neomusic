{-# LANGUAGE OverloadedStrings #-}
-- | Command-line parsing and player selection for neo-music.
module CliTests (cliGroup) where

import Data.Either (isLeft)
import Hedgehog
import NeoMusic.Cli
import NeoMusic.Audio (encoderArgs)

cliGroup :: Group
cliGroup = Group "neo-music command line"
  [ ("render writes the named file", unit $
      parseArgs ["render", "a.neomusic", "-o", "a.wav"] === Right (Audio False "a.neomusic" (Just "a.wav") defaultAudioOpts))
  , ("render without -o is an error", unit $
      assert (isLeft (parseArgs ["render", "a.neomusic"])))
  , ("play -o keeps writing a file", unit $
      parseArgs ["play", "a.neomusic", "-o", "a.mp3"] === Right (Audio True "a.neomusic" (Just "a.mp3") defaultAudioOpts))
  , ("play without -o plays now", unit $
      parseArgs ["play", "a.neomusic"] === Right (Audio True "a.neomusic" Nothing defaultAudioOpts))
  , ("--no-dither turns dither off, anywhere after the input", unit $ do
      parseArgs ["render", "a.neomusic", "--no-dither", "-o", "a.wav"]
        === Right (Audio False "a.neomusic" (Just "a.wav") (defaultAudioOpts {optDither = False}))
      parseArgs ["play", "a.neomusic", "--no-dither"] === Right (Audio True "a.neomusic" Nothing (defaultAudioOpts {optDither = False})))
  , ("--rate, --bits and --mp3-quality", unit $ do
      parseArgs ["render", "a.neomusic", "-o", "a.mp3", "--rate", "48000", "--bits", "24", "--mp3-quality", "0"]
        === Right (Audio False "a.neomusic" (Just "a.mp3")
              defaultAudioOpts {optRate = Just 48000, optBits = Just 24, optMp3Quality = Just 0})
      parseArgs ["play", "a.neomusic", "--rate", "22050"]
        === Right (Audio True "a.neomusic" Nothing defaultAudioOpts {optRate = Just 22050}))
  , ("out-of-range or malformed numbers are rejected", unit $
      mapM_ (\flags -> assert (isLeft (parseArgs (["render", "a.neomusic", "-o", "a.wav"] ++ flags))))
        [ ["--rate", "4000"], ["--rate", "200000"], ["--rate", "fast"], ["--rate"]
        , ["--bits", "32"], ["--bits", "8"], ["--mp3-quality", "10"], ["--mp3-quality", "-1"]
        , ["--rate", "48000", "--rate", "44100"] ])
  , ("defaults are unchanged", unit $
      defaultAudioOpts === AudioOpts True Nothing Nothing Nothing)
  , ("encoder arguments per extension", unit $ do
      encoderArgs 2 ".mp3" === Just ["-codec:a", "libmp3lame", "-q:a", "2"]
      encoderArgs 0 ".mp3" === Just ["-codec:a", "libmp3lame", "-q:a", "0"]
      encoderArgs 2 ".flac" === Just []
      fmap (take 2) (encoderArgs 2 ".ogg") === Just ["-codec:a", "libvorbis"]
      fmap (take 2) (encoderArgs 2 ".opus") === Just ["-codec:a", "libopus"]
      fmap (take 2) (encoderArgs 2 ".m4a") === Just ["-codec:a", "aac"]
      encoderArgs 2 ".wav" === Nothing
      encoderArgs 2 ".aiff" === Nothing)
  , ("unknown audio options are rejected", unit $
      assert (isLeft (parseArgs ["render", "a.neomusic", "-o", "a.wav", "--dither"])))
  , ("other exports are unchanged", unit $ do
      parseArgs ["midi", "a.neomusic", "-o", "a.mid"] === Right (Export "midi" "a.neomusic" "a.mid" [])
      parseArgs ["staff", "a.neomusic", "-o", "a.ly", "--pdf"] === Right (Export "staff" "a.neomusic" "a.ly" ["--pdf"])
      parseArgs ["sheet", "a.neomusic", "--marks"] === Right (SheetStdout "a.neomusic" ["--marks"])
      parseArgs ["check", "a.neomusic"] === Right (Check "a.neomusic"))
  , ("unknown commands show usage", unit $
      parseArgs ["bogus", "a.neomusic", "-o", "x"] === Left usage)
  , ("macOS prefers afplay", unit $
      pickPlayer "darwin" (const True) "x.wav" === Just ("afplay", ["x.wav"]))
  , ("Linux uses ffplay, then aplay", unit $ do
      fmap fst (pickPlayer "linux" (const True) "x.wav") === Just "ffplay"
      pickPlayer "linux" (== "aplay") "x.wav" === Just ("aplay", ["-q", "x.wav"])
      pickPlayer "linux" (== "afplay") "x.wav" === Nothing)
  , ("no player available", unit $
      pickPlayer "darwin" (const False) "x.wav" === Nothing)
  ]
  where unit = withTests 1 . property
