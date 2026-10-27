-- | Command-line parsing for @neo-music@, kept pure so it can be tested.
module NeoMusic.Cli
  ( Invocation (..), parseArgs, usage
  , playerCandidates, pickPlayer
  ) where

-- | What the command line asked for.
data Invocation
  = Audio Bool FilePath (Maybe FilePath)
    -- ^ play?, input, output: @render@ (always writes @-o@) or @play@ (writes @-o@ if given,
    -- otherwise renders to a temporary file and plays it)
  | Export String FilePath FilePath [String]
    -- ^ midi, sheet, hybrid or staff to a file, with flags
  | SheetStdout FilePath [String]
  | Check FilePath
  deriving (Eq, Show)

usage :: String
usage = unlines
  [ "usage: neo-music render song.neomusic -o out.{wav|mp3|flac}"
  , "       neo-music play song.neomusic [-o out.wav]   (no -o: render and play now)"
  , "       neo-music {midi|sheet|hybrid|staff} song.neomusic -o output [sheet/hybrid: --marks] [staff: --pdf --no-numbers]"
  , "       neo-music sheet song.neomusic [--marks]      (numeric sheet to stdout)"
  , "       neo-music check song.neomusic"
  , ""
  , "play uses afplay on macOS, or ffplay/aplay elsewhere, whichever is on PATH."
  ]

parseArgs :: [String] -> Either String Invocation
parseArgs args = case args of
  ["render", input, "-o", output] -> Right (Audio False input (Just output))
  ["render", _] -> Left "render needs an output file: neo-music render song.neomusic -o out.wav"
  ["play", input, "-o", output] -> Right (Audio True input (Just output))
  ["play", input] -> Right (Audio True input Nothing)
  [command, input, "-o", output] | command `elem` ["midi", "sheet", "hybrid", "staff"] ->
    Right (Export command input output [])
  "sheet" : input : "-o" : output : flags | flags == ["--marks"] -> Right (Export "sheet" input output flags)
  "hybrid" : input : "-o" : output : flags | flags == ["--marks"] -> Right (Export "hybrid" input output flags)
  "staff" : input : "-o" : output : flags | all (`elem` ["--pdf", "--no-numbers"]) flags ->
    Right (Export "staff" input output flags)
  "sheet" : input : flags | all (== "--marks") flags -> Right (SheetStdout input flags)
  ["check", input] -> Right (Check input)
  _ -> Left usage

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
