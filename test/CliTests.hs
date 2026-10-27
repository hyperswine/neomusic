{-# LANGUAGE OverloadedStrings #-}
-- | Command-line parsing and player selection for neo-music.
module CliTests (cliGroup) where

import Data.Either (isLeft)
import Hedgehog
import NeoMusic.Cli

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
        === Right (Audio False "a.neomusic" (Just "a.wav") (AudioOpts False))
      parseArgs ["play", "a.neomusic", "--no-dither"] === Right (Audio True "a.neomusic" Nothing (AudioOpts False)))
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
