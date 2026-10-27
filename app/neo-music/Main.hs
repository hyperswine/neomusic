module Main (main) where

import qualified Data.ByteString.Lazy as BL
import qualified NeoMusic.Audio as A
import NeoMusic.Language
import NeoMusic.Midi (midi)
import NeoMusic.Numeric (NumericView (..), numericHtml, numericPage, plain)
import NeoMusic.Sheet (engrave)
import qualified NeoMusic.Score as S
import System.Environment (getArgs, lookupEnv)
import System.Directory (findExecutable)
import System.FilePath (dropExtension, takeExtension, (</>))
import System.Info (os)
import System.IO.Temp (withSystemTempDirectory)
import Data.List (intercalate)
import Data.Maybe (isJust)
import NeoMusic.Cli
import System.Process (callProcess)
import System.Exit (die)

main :: IO ()
main = do
  args <- getArgs
  invocation <- either die pure (parseArgs args)
  case invocation of
    Audio _ input (Just output) opts -> renderTo opts input output
    Audio _ input Nothing opts -> playNow opts input
    Export command input output flags -> run command input output flags
    SheetStdout input flags -> readDocument input >>= \doc ->
      orDie (numericPage (plain {showMarks = not (null flags)}) (performance doc) (score doc)) >>= putStr
    Check input -> do
      doc <- readDocument input
      timeline <- orDie (S.render (performance doc) (score doc))
      putStrLn (show (length (A.notes timeline))++" notes, "++show (A.seconds timeline)++" seconds")

renderTo :: AudioOpts -> FilePath -> FilePath -> IO ()
renderTo opts input output = do
  doc <- readDocument input
  let dither = if optDither opts then A.defaultDither else A.NoDither
  S.writeAudioWith dither output (performance doc) (score doc)

-- | Render to a temporary WAV and play it with the first available player.
playNow :: AudioOpts -> FilePath -> IO ()
playNow opts input = do
  found <- mapM (\(name, _) -> (,) name . isJust <$> findExecutable name) (playerCandidates os)
  let available name = maybe False id (lookup name found)
  case pickPlayer os available "" of
    Nothing -> die ("play: no audio player found on PATH (tried "
      ++ intercalate ", " (map fst (playerCandidates os))
      ++ "). Install one, or write a file with: neo-music render "++input++" -o out.wav")
    Just _ -> withSystemTempDirectory "neo-music" $ \dir -> do
      let wav = dir </> "play.wav"
      renderTo opts input wav
      case pickPlayer os available wav of
        Just (player, playerArgs) -> callProcess player playerArgs
        Nothing -> pure ()

-- | A document with the recordings it names, found next to it or under each
-- directory in NEOMUSIC_SAMPLES (separated by colons).
readDocument :: FilePath -> IO Document
readDocument path = do
  dirs <- maybe [] (splitOn ':') <$> lookupEnv "NEOMUSIC_SAMPLES"
  loadDocument dirs path >>= orDie
  where
    splitOn c xs = case break (== c) xs of
      (a, []) -> [a | not (null a)]
      (a, _ : rest) -> [a | not (null a)] ++ splitOn c rest
orDie :: Either String a -> IO a
orDie = either die pure
run :: String -> FilePath -> FilePath -> [String] -> IO ()
run command input output flags = do
  doc <- readDocument input
  let perf = performance doc
      music = score doc
      reading = plain {showMarks = "--marks" `elem` flags}
  case command of
    "midi" -> orDie (midi perf music) >>= BL.writeFile output
    "sheet" -> case takeExtension output of
      ".txt" -> orDie (numericPage reading perf music) >>= writeFile output
      ".html" -> orDie (numericHtml reading perf music) >>= writeFile output
      _ -> die "numeric sheet output must be .txt or .html; use staff for LilyPond/PDF"
    "hybrid" -> if takeExtension output == ".html"
      then orDie (numericHtml reading {flatBars = True} perf music) >>= writeFile output
      else die "hybrid preview output must be .html"
    "staff" -> do
      if takeExtension output /= ".ly" then die "staff output must have .ly extension" else pure ()
      let view = (sheetView doc) {numbers = "--no-numbers" `notElem` flags}
      text <- orDie (engrave perf view music)
      writeFile output text
      if "--pdf" `elem` flags then do
        executable <- findExecutable "lilypond"
        program <- maybe (die "LilyPond source was written; PDF requires lilypond on PATH") pure executable
        callProcess program ["--pdf","-o",dropExtension output,output]
      else pure ()
    _ -> die ("unknown command: "++command)
