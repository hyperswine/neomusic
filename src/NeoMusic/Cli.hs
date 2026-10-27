-- | Command-line parsing for @neo-music@, kept pure so it can be tested.
module NeoMusic.Cli
  ( Invocation (..), AudioOpts (..), defaultAudioOpts, parseArgs, usage
  , playerCandidates, pickPlayer
  ) where

import Text.Read (readMaybe)

-- | What the command line asked for.
data Invocation
  = Audio Bool FilePath (Maybe FilePath) AudioOpts
    -- ^ play?, input, output, options: @render@ (always writes @-o@) or @play@ (writes @-o@ if given,
    -- otherwise renders to a temporary file and plays it)
  | Export String FilePath FilePath [String]
    -- ^ midi, sheet, hybrid or staff to a file, with flags
  | SheetStdout FilePath [String]
  | Check FilePath
  deriving (Eq, Show)

-- | Options for @render@ and @play@.
data AudioOpts = AudioOpts
  { optDither :: Bool             -- ^ TPDF-dither 16-bit output (default on; @--no-dither@)
  , optRate :: Maybe Int          -- ^ @--rate@: override the score's sample rate
  , optBits :: Maybe Int          -- ^ @--bits@: override the score's export depth
  , optMp3Quality :: Maybe Int    -- ^ @--mp3-quality@: LAME VBR 0 (best) .. 9; default 2
  } deriving (Eq, Show)

defaultAudioOpts :: AudioOpts
defaultAudioOpts = AudioOpts { optDither = True, optRate = Nothing, optBits = Nothing, optMp3Quality = Nothing }

usage :: String
usage = unlines
  [ "usage: neo-music render song.neomusic -o out.{wav|mp3|flac|ogg|opus|m4a} [audio options]"
  , "       neo-music play song.neomusic [-o out.wav] [audio options]   (no -o: render and play now)"
  , "       neo-music {midi|sheet|hybrid|staff} song.neomusic -o output [sheet/hybrid: --marks] [staff: --pdf --no-numbers]"
  , "       neo-music sheet song.neomusic [--marks]      (numeric sheet to stdout)"
  , "       neo-music check song.neomusic"
  , ""
  , "audio options:"
  , "  --rate HZ          sample rate, 8000..192000 (default: the score's, usually 44100)"
  , "  --bits 16|24       export depth (default: the score's, usually 16)"
  , "  --mp3-quality 0-9  LAME VBR quality, 0 best (default 2)"
  , "  --no-dither        truncate to 16 bits instead of TPDF dither (24-bit is never dithered)"
  , "  mp3/flac/ogg/opus/m4a are encoded by ffmpeg, which must be on PATH"
  , ""
  , "play uses afplay on macOS, or ffplay/aplay elsewhere, whichever is on PATH."
  ]

parseArgs :: [String] -> Either String Invocation
parseArgs args = case args of
  "render" : input : rest -> parseAudio False input rest >>= \a -> case a of
    Audio _ _ Nothing _ -> Left "render needs an output file: neo-music render song.neomusic -o out.wav"
    _ -> Right a
  "play" : input : rest -> parseAudio True input rest
  [command, input, "-o", output] | command `elem` ["midi", "sheet", "hybrid", "staff"] ->
    Right (Export command input output [])
  "sheet" : input : "-o" : output : flags | flags == ["--marks"] -> Right (Export "sheet" input output flags)
  "hybrid" : input : "-o" : output : flags | flags == ["--marks"] -> Right (Export "hybrid" input output flags)
  "staff" : input : "-o" : output : flags | all (`elem` ["--pdf", "--no-numbers"]) flags ->
    Right (Export "staff" input output flags)
  "sheet" : input : flags | all (== "--marks") flags -> Right (SheetStdout input flags)
  ["check", input] -> Right (Check input)
  _ -> Left usage

parseAudio :: Bool -> FilePath -> [String] -> Either String Invocation
parseAudio play input = go Nothing defaultAudioOpts
  where
    go out opts args = case args of
      [] -> Right (Audio play input out opts)
      "-o" : file : rest | out == Nothing -> go (Just file) opts rest
      "--no-dither" : rest -> go out opts {optDither = False} rest
      "--rate" : v : rest | optRate opts == Nothing ->
        number "--rate" v (\r -> r >= 8000 && r <= 192000) "8000..192000" >>= \r -> go out opts {optRate = Just r} rest
      "--bits" : v : rest | optBits opts == Nothing ->
        number "--bits" v (`elem` [16, 24]) "16 or 24" >>= \b -> go out opts {optBits = Just b} rest
      "--mp3-quality" : v : rest | optMp3Quality opts == Nothing ->
        number "--mp3-quality" v (\q -> q >= 0 && q <= 9) "0..9" >>= \q -> go out opts {optMp3Quality = Just q} rest
      flag : _ -> Left ("unknown or repeated audio option: "++flag++"\n\n"++usage)

number :: String -> String -> (Int -> Bool) -> String -> Either String Int
number flag v ok range = case readMaybe v of
  Just x | ok x -> Right x
  _ -> Left (flag ++ " must be " ++ range ++ ", got " ++ show v)

-- | Audio players to try, in order, for an operating system name as in
-- 'System.Info.os', with the arguments that play a WAV file and exit.
playerCandidates :: String -> [(String, FilePath -> [String])]
playerCandidates os = (if os == "darwin" then (afplay :) else id) [ffplay, aplay]
  where
    afplay = ("afplay", \f -> [f])
    ffplay = ("ffplay", \f -> ["-nodisp", "-autoexit", "-loglevel", "error", f])
    aplay = ("aplay", \f -> ["-q", f])

-- | The first candidate player that is available, with its full argument list.
pickPlayer :: String -> (String -> Bool) -> FilePath -> Maybe (String, [String])
pickPlayer os available file =
  case [ (name, mk file) | (name, mk) <- playerCandidates os, available name ] of
    (p : _) -> Just p
    [] -> Nothing
