{-# LANGUAGE OverloadedStrings #-}
-- | The synthesis engine and tuning laws, driven through the score API.
module NeoMusicTests (neoMusicGroup) where

import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Data.Either (isLeft)
import qualified Data.Map.Strict as M
import qualified Data.ByteString.Lazy as BL
import qualified Data.Vector.Unboxed as VU
import System.IO.Temp (withSystemTempFile)
import System.IO (hClose)
import NeoMusic.Audio
  ( Contour(..), Mix(..), Mod(..), Osc(..), Patch(..), Note(..), Timeline(..), Voice(..), Wave(..)
  , adsr, basicPatch, cutoffHz, defaultMix, expandClassic, hall, hat, kick, modAt, noReverb, noiseSweep, note
  , Dither(..), defaultDither, pcmWavWith, tpdfNoise
  , pcmWav, pcmWavBits, percussive, pianoPatch, pluck, reeseBass, renderTimelineMix, sawPatch, sinePatch, snare
  , squarePatch, subBass, supersaw, validPatch, validVoice, Room(..), Reverb(..), writeTimelineMix )
import qualified Data.Map.Strict as Map
import NeoMusic.Recording (Recording(..), Region(..), SampleSet(..), parseSfz, readRecording, readSampleSet)
import Control.Exception (evaluate)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import NeoMusic.Pitch (Step(..), Tuning(..), equalTemperament, freq)
import NeoMusic.Score
  ( Performance(..), Score(..), defaultInstrument, defaultPerformance, hit, n, render, rest )
import qualified NeoMusic.Score as S

-- | One instrument "v" with the given tuning and patch, at the given tempo.
perfWith :: Tuning -> Patch -> Double -> Performance
perfWith t p speed = defaultPerformance
  { bpm = speed, instruments = M.singleton "v" defaultInstrument {S.tuning = t, S.timbre = Classic p} }

-- | A dry, unnormalised render of single notes of a voice, straight from the engine.
voiceRender :: Int -> Double -> [Note] -> Either String (VU.Vector Double, VU.Vector Double)
voiceRender rate total = renderTimelineMix (Mix rate noReverb 0 0.8 0 False Nothing 16) . Timeline total

-- | One note of a voice: start, Hz, seconds, velocity.
voiceNote :: Voice -> Double -> Double -> Double -> Double -> Note
voiceNote v t f d vel = Note t f d v vel 1 0 0 (Flat 0) (Flat 1)

-- | A recording's audio is read on first use; these tests read it before
-- their temporary files go.
used :: Either String Recording -> IO (Either String Recording)
used r = do
  either (const (pure ())) (mapM_ (evaluate . VU.length) . recordingAudio) r
  pure r

-- | Mean square over a span of samples.
meanSquare :: VU.Vector Double -> Int -> Int -> Double
meanSquare xs from count = VU.sum (VU.map (^ (2 :: Int)) (VU.slice from count xs)) / fromIntegral count

-- | The lag between @lo@ and @hi@ samples where a signal best matches itself.
period :: VU.Vector Double -> Int -> Int -> Int -> Int -> Int
period xs from count lo hi = snd (maximum [(sum [VU.unsafeIndex xs (from + i) * VU.unsafeIndex xs (from + i + lag) | i <- [0 .. count - 1]], lag) | lag <- [lo .. hi]])

stereo :: Mix -> Performance -> Score -> Either String (VU.Vector Double, VU.Vector Double)
stereo m perf music = render perf music >>= renderTimelineMix m

mono :: Int -> Performance -> Score -> Either String (VU.Vector Double)
mono rate perf music = do
  (l, r) <- stereo (defaultMix rate) perf music
  pure (VU.zipWith (\a b -> (a + b) / 2) l r)

neoMusicGroup :: Group
neoMusicGroup = Group "NeoMusic audio engine"
  [ ("transposition under arbitrary tuning", property $ do
      divisions <- forAll (Gen.int (Range.linear 1 1200))
      x <- forAll (Gen.int (Range.linear (-20) 20))
      k <- forAll (Gen.int (Range.linear (-20) 20))
      t <- evalEither (equalTemperament 220 divisions)
      let expected = freq t (Step x) * ratio t ** fromIntegral k
      assert (abs (freq t (Step (x+k)) / expected - 1) < 1e-10))
  , ("invalid inputs are rejected", withTests 1 $ property $ do
      let perf = perfWith (Tuning 220 2) sinePatch 60
          note = Line "v" (n 0)
      mapM_ (assert . isLeft)
        [ render perf (Line "v" (hit [0] 0 1))
        , render perf (Line "v" (hit [0] 1 1.5))
        , render perf (Line "v" (hit [0] 1 (0/0)))
        , render perf {bpm = 0} note
        , render (perfWith (Tuning (0/0) 2) sinePatch 60) note
        , render (perfWith (Tuning 220 2) sinePatch {resonance = 1} 60) note ]
      assert (isLeft (mono 8000 (perfWith (Tuning 4000 2) sinePatch 60) note)))
  , ("PCM duration, pitch, silence and WAV framing", withTests 1 $ property $ do
      let perf = perfWith (Tuning 440 2) sinePatch 60
      xs <- evalEither (mono 8000 perf (Line "v" (n 0 <> rest)))
      VU.length xs === 16000
      -- The trailing rest is kept, and silent once the 15 ms release has passed.
      assert (VU.all (== 0) (VU.drop 8120 xs))
      assert (VU.maximum (VU.map abs xs) <= 0.8)
      let crossings = length [() | i <- [0 .. 7998], xs VU.! i <= 0, xs VU.! (i + 1) > 0]
      assert (abs (crossings - 440) <= 1)
      bytes <- evalIO $ withSystemTempFile "neo-test.wav" $ \path handle -> do
        hClose handle
        pcmWav path 8000 [xs]
        content <- BL.readFile path
        BL.length content `seq` pure content
      BL.length bytes === 32044
      BL.take 4 bytes === "RIFF"
      BL.take 4 (BL.drop 8 bytes) === "WAVE"
      BL.take 4 (BL.drop 40 bytes) === BL.pack [0,125,0,0])
  , ("velocity, gain, pan and send", withTests 1 $ property $ do
      let base = perfWith (Tuning 440 2) sinePatch 60
          mixed = base {instruments = M.map (\i -> i {S.gain = 0.5, S.pan = -1, S.send = 0.3}) (instruments base)}
          quietSecond = Line "v" (hit [0] 1 1 <> hit [0] 1 0.5)
      Timeline _ ns <- evalEither (render mixed quietSecond)
      map velocity ns === [1, 0.5]
      map gain ns === [0.5, 0.5]
      map pan ns === [-1, -1]
      map send ns === [0.3, 0.3]
      xs <- evalEither (mono 8000 base quietSecond)
      let peakIn a b = VU.maximum (VU.map abs (VU.slice a (b - a) xs))
      -- Skip the first note's 15 ms release, which overlaps the second note.
      assert (abs (peakIn 8400 16000 / peakIn 0 8000 - 0.5) < 1e-3)
      (l, r) <- evalEither (stereo (defaultMix 8000) mixed quietSecond)
      assert (VU.all (== 0) r && VU.any (/= 0) l))
  , ("reverb tails and synth releases", withTests 1 $ property $ do
      let t = Tuning 220 2
          dry = perfWith t sinePatch 60
          wet = dry {instruments = M.map (\i -> i {S.send = 1}) (instruments dry)}
          blip = Line "v" (n 0)
          m = (defaultMix 8000) {mixReverb = hall, mixTail = 1}
      (dryL, _) <- evalEither (stereo m dry blip)
      (wetL, wetR) <- evalEither (stereo m wet blip)
      -- One beat, the sine preset's 15 ms release, then the 1 s reverb tail.
      VU.length wetL === 16120
      assert (VU.all (== 0) (VU.drop 8120 dryL))
      assert (VU.any ((> 1e-3) . abs) (VU.drop 8400 wetL) && VU.any (/= 0) (VU.drop 8400 wetR))
      assert (VU.all (\x -> abs x <= 0.8) wetL)
      let ringing = perfWith t pluck {amp = Velocity :* adsr 0.01 0 1 0.5} 60
      (sl, sr) <- evalEither (stereo (defaultMix 8000) ringing blip)
      VU.length sl === 12000
      assert (VU.any ((> 1e-3) . abs) (VU.drop 8000 sl) && VU.all (not . isNaN) sr)
      noise <- evalEither (mono 8000 (perfWith t hat 60) blip)
      assert (VU.any (/= 0) noise && VU.all (\x -> abs x <= 0.8) noise))
  , ("adsr is exactly the classic envelope", property $ do
      a <- forAll (Gen.element [0, 0.0005, 0.002, 0.01, 0.3])
      d <- forAll (Gen.element [0, 0.05, 0.4, 1.5])
      sus <- forAll (Gen.element [0, 0.15, 0.8, 1])
      r <- forAll (Gen.element [0, 0.001, 0.05, 1.2])
      gate <- forAll (Gen.element [0.0001, 0.003, 0.2, 1, 2.5])
      ts <- forAll (Gen.list (Range.linear 1 40) (Gen.double (Range.linearFrac 0 5)))
      -- The envelope the engine used before patches became signals, verbatim.
      let classic t
            | t < 0 = 0
            | t < gate = held t
            | t < gate + r' = let u = (t - gate) / r' in held gate * (1 - u) * (1 - u)
            | otherwise = 0
            where
              a' = max 0.001 a
              r' = max 0.002 r
              held x
                | x < a' = x / a'
                | d <= 0 = sus
                | otherwise = sus + (1 - sus) * exp (-4.6 * (x - a') / d)
      -- Bit for bit, not approximately.
      [modAt (adsr a d sus r) gate 1 0 t | t <- ts] === map classic ts)
  , ("patch modulations: release, LFO, velocity, bounds, pitched or not", withTests 1 $ property $ do
      -- Release starts from wherever the sound has got to at note-off.
      let swellUp = Release 0.5 (Linear 0 1 2)
      modAt swellUp 1 1 0 1 === 0.5
      modAt swellUp 1 1 0 1.25 === 0.5 * 0.5 * 0.5
      modAt swellUp 1 1 0 1.6 === 0
      -- Then restarts the second part's clock; Approach is 99% of the way after its time.
      modAt (Then 1 (K 3) (Linear 0 10 2)) 9 1 0 1.5 === 2.5
      assert (abs (modAt (Approach 1 0 2) 9 1 0 2 - 0.01) < 0.0001)
      -- A fixed-Hz LFO, a velocity input, and the key.
      assert (abs (modAt (Lfo SineWave 5) 9 1 0 0.05 - 1) < 1e-12)
      modAt (Velocity :* K 2) 9 0.25 0 0 === 0.5
      modAt (K 0.5 :* Key) 9 1 2 0 === 1
      -- Velocity is the patch's to apply: without it, soft and hard notes match.
      let flat = (perfWith (Tuning 440 2) sinePatch {amp = adsr 0.005 0 1 0.015} 60)
      xs <- evalEither (mono 8000 flat (Line "v" (hit [0] 1 1 <> hit [0] 1 0.5)))
      let peakIn a' b' = VU.maximum (VU.map abs (VU.slice a' (b' - a') xs))
      assert (abs (peakIn 8400 16000 / peakIn 0 8000 - 1) < 1e-3)
      -- An amplitude that could go negative is rejected.
      assert (isLeft (validPatch sinePatch {amp = Lfo SineWave 3}))
      assert (isLeft (validPatch sinePatch {amp = Linear 0 1 0}))
      -- A vibrato patch is pitched; a pitch that falls into the note isn't.
      let vibrato = sinePatch {pitch = K 0.2 :* Lfo SineWave 5.5}
      assert (not (percussive (Classic vibrato)) && percussive (Classic kick) && percussive (Classic hat)
              && not (percussive (Classic sinePatch)))
      plain <- evalEither (mono 8000 (perfWith (Tuning 440 2) sinePatch 60) (Line "v" (n 0)))
      wobbly <- evalEither (mono 8000 (perfWith (Tuning 440 2) vibrato 60) (Line "v" (n 0)))
      assert (plain /= wobbly)
      -- A modulated cutoff is never bypassed, even when its base is open.
      let opened = sinePatch {oscillators = oscillators pluck, cutoff = cutoffHz 20000}
          closing = opened {cutoff = cutoffHz 20000 :+ K (-6) :* Velocity}
      bright <- evalEither (mono 8000 (perfWith (Tuning 220 2) opened 60) (Line "v" (n 0)))
      dark <- evalEither (mono 8000 (perfWith (Tuning 220 2) closing 60) (Line "v" (n 0)))
      assert (bright /= dark))
    , ("voices: classic expansion, strings, filters, pan, pitched or not", withTests 1 $ property $ do
      -- Every preset sounds the same played by the fast path and by the
      -- general interpreter on its expansion, a curved note included.
      let presets = [basicPatch, pianoPatch, sinePatch, sawPatch, squarePatch, pluck, supersaw
                    , reeseBass, subBass, kick, snare, hat, noiseSweep]
          curved v = (voiceNote v 0.3 330 0.4 0.6) {pitchMod = Breaks [(0, 0), (1, 0.25)], loudness = Breaks [(0, 0.5), (1, 1)]}
          notes v = [voiceNote v 0 220 0.25 0.8, curved v]
      differences <- evalEither (mapM (\p -> do
          (l1, r1) <- voiceRender 22050 1 (notes (Classic p))
          (l2, r2) <- voiceRender 22050 1 (notes (expandClassic p))
          let biggest = VU.maximum (VU.map abs (l1 VU.++ r1))
          pure (VU.maximum (VU.map abs (VU.zipWith (-) (l1 VU.++ r1) (l2 VU.++ r2))) / biggest)) presets)
      annotateShow differences
      assert (all (< 1e-9) differences)
      -- A plucked string sounds at its pitch, and its fundamental falls 60 dB
      -- over the decay: 30 dB in half of it.
      let string = Gain (adsr 0.001 0 1 0.05) (Plucked 1 0)
      (s, _) <- evalEither (voiceRender 44100 2 [voiceNote string 0 220 1.9 1])
      let lag = period s 8820 2000 170 240
      annotateShow lag
      assert (abs (44100 / fromIntegral lag / 220 - 1) < 0.005)
      let fall = meanSquare s 8820 4410 / meanSquare s 30870 4410
      annotateShow (10 * logBase 10 fall)
      assert (abs (10 * logBase 10 fall - 30) < 1.5)
      -- It follows a bend: an octave up sounds an octave up.
      (up, _) <- evalEither (voiceRender 44100 1 [voiceNote (Bend (K 12) string) 0 220 0.9 1])
      assert (abs (44100 / fromIntegral (period up 8820 2000 85 120) / 440 - 1) < 0.01)
      -- A band passes its centre at unity and cuts two octaves away.
      let band = Bandpass (cutoffHz 1000) 1 (Tone SineWave)
      (centre, _) <- evalEither (voiceRender 44100 0.5 [voiceNote band 0 1000 0.45 1])
      (away, _) <- evalEither (voiceRender 44100 0.5 [voiceNote band 0 4000 0.45 1])
      let steady xs = sqrt (2 * meanSquare xs 11025 4410)
      annotateShow (steady centre, steady away)
      assert (abs (steady centre - 1) < 0.01 && steady away < 0.3)
      -- Pan and unison spread a voice across the stereo field.
      (hardL, hardR) <- evalEither (voiceRender 8000 0.5 [voiceNote (Pan (K (-1)) (Tone SineWave)) 0 220 0.4 1])
      assert (VU.any ((> 0.5) . abs) hardL && VU.all ((< 1e-12) . abs) hardR)
      (wideL, wideR) <- evalEither (voiceRender 8000 0.5 [voiceNote (Unison 3 20 1 (Tone SawWave)) 0 220 0.4 1])
      assert (wideL /= wideR)
      -- A voice sounds until note-off plus its longest release.
      (cut, _) <- evalEither (voiceRender 8000 1 [voiceNote (Gain (adsr 0.001 0 1 0.2) (Tone SineWave)) 0 220 0.5 1])
      assert (VU.any ((> 1e-3) . abs) (VU.slice 4400 400 cut) && VU.all (== 0) (VU.drop 5700 cut))
      -- Drive: 0 leaves the signal unchanged; > 0 saturates within +-1 and boosts a sub-unity tone.
      let quietSine = Gain (K 0.5) (Tone SineWave)
      (plainSine, _) <- evalEither (voiceRender 8000 0.5 [voiceNote quietSine 0 220 0.4 1])
      (zeroDrive, _) <- evalEither (voiceRender 8000 0.5 [voiceNote (Drive (K 0) quietSine) 0 220 0.4 1])
      (hardDrive, _) <- evalEither (voiceRender 8000 0.5 [voiceNote (Drive (K 2.5) quietSine) 0 220 0.4 1])
      zeroDrive === plainSine
      assert (meanSquare hardDrive 0 3200 > meanSquare plainSine 0 3200 && VU.all ((<= 1) . abs) hardDrive)
      -- Unpitched: every part is. Noise is; a bend into the note makes it so.
      let flute = sinePatch {oscillators = [Osc TriangleWave 0 1 1 0, Osc NoiseWave 0 0.04 1 0]}
      [percussive v | v <- [Noise, Tone SawWave :& Gain (K 0.1) Noise, Bend (Approach 12 0 0.1) (Tone SineWave)
                           , Plucked 1 0.5, Classic kick, Classic snare, Classic flute, Gain (K 2) (Highpass (K 3) Noise)
                           , Drive (K 2) Noise]]
        === [True, False, True, False, True, True, False, True, True]
      mapM_ (assert . isLeft . validVoice)
        [ Tone NoiseWave, Plucked 0 0.5, Plucked 1 2, Bandpass (K 1) 0 (Tone SineWave), Drive (K (-1)) Noise
        , Pan (K 2) Noise, Lowpass (K 1) 1 Noise, Unison 0 0 0 Noise, Gain (Linear 0 1 0) Noise, Classic sinePatch {resonance = 1} ])
    , ("recordings: WAV, SFZ, layers, takes, rooms", withTests 1 $ property $ do
      -- WAV at 16 and 24 bits reads back to within its step.
      let tone amp f = VU.generate 11025 (\i -> amp * sin (2 * pi * f * fromIntegral i / 22050))
          original = tone 0.8 220
      back <- evalIO $ withSystemTempDirectory "neomusic" $ \dir -> do
        pcmWavBits 16 (dir </> "a.wav") 22050 [original, VU.map negate original]
        pcmWavBits 24 (dir </> "b.wav") 22050 [original]
        a <- readRecording (dir </> "a.wav") >>= used
        b <- readRecording (dir </> "b.wav") >>= used
        pure (a, b)
      (r16, r24) <- evalEither (either Left (\a -> (,) a <$> snd back) (fst back))
      (recordingRate r16, recordingFrames r16, length (recordingAudio r16), recordingFrames r24) === (22050, 11025, 2, 11025)
      let worst xs = VU.maximum (VU.zipWith (\x y -> abs (realToFrac x - y)) xs original)
      case recordingAudio r16 of
        (l : _) -> assert (worst l < 2 / 32767)   -- written at 32767 per unit, read at 32768
        [] -> failure
      case recordingAudio r24 of
        (m : _) -> assert (worst m < 2 / 8388607)
        [] -> failure
      -- SFZ: values with spaces, headers inline, group opcodes inherited,
      -- note names; anything outside the subset is an error naming it.
      regions <- evalEither (parseSfz (unlines
        [ "// a comment", "<control> default_path=My Folder/"
        , "<group> lovel=1 hivel=64 <region> sample=a b.wav key=c4"
        , "<region> sample=c.wav lokey=c#4 hikey=72 // trailing" ]))
      regions === [ Map.fromList [("default_path", "My Folder/"), ("lovel", "1"), ("hivel", "64"), ("sample", "a b.wav"), ("key", "c4")]
                  , Map.fromList [("default_path", "My Folder/"), ("lovel", "1"), ("hivel", "64"), ("sample", "c.wav"), ("lokey", "c#4"), ("hikey", "72")] ]
      assert (either (elem "amp_veltrack" . words) (const False) (parseSfz "<region> sample=a.wav amp_veltrack=0"))
      assert (isLeft (parseSfz "<curve> v=1"))
      -- An instrument: a 220 Hz recording as A3, two velocity layers (soft and
      -- loud), and two takes of the loud one.
      set <- evalIO $ withSystemTempDirectory "neomusic" $ \dir -> do
        pcmWavBits 16 (dir </> "soft.wav") 22050 [tone 0.1 220]
        pcmWavBits 16 (dir </> "loud1.wav") 22050 [tone 0.6 220]
        pcmWavBits 16 (dir </> "loud2.wav") 22050 [tone 0.9 220, tone 0.9 220]
        writeFile (dir </> "inst.sfz") $ unlines
          [ "<group> pitch_keycenter=57 lokey=50 hikey=64"
          , "<region> sample=soft.wav lovel=1 hivel=63"
          , "<region> sample=loud1.wav lovel=64 seq_length=2 seq_position=1"
          , "<region> sample=loud2.wav lovel=64 seq_length=2 seq_position=2" ]
        loaded <- readSampleSet [] (dir </> "inst.sfz")
        mapM_ (mapM_ (used . Right . regionRecording) . setRegions) loaded
        pure loaded
      instrument <- evalEither set
      length (setRegions instrument) === 3
      let at t f v = voiceNote (Sampled instrument) t f 0.4 v
          peak xs from = VU.maximum (VU.map abs (VU.slice from 4000 xs))
      -- Retuned by resampling: B3 from the A3 recording.
      (b3, _) <- evalEither (voiceRender 44100 0.5 [at 0 246.94 1])
      assert (abs (44100 / fromIntegral (period b3 2000 4000 150 210) / 246.94 - 1) < 0.005)
      -- Velocity picks the layer; repeats of a pitch rotate its takes.
      (played, _) <- evalEither (voiceRender 22050 2 [at 0 220 0.2, at 0.5 220 0.9, at 1 220 0.9, at 1.5 220 0.9])
      let peaks = [peak played (round (t * 22050) + 500) | t <- [0, 0.5, 1, 1.5 :: Double]]
      annotateShow peaks
      assert (and (zipWith (\x y -> abs (x - y) < 0.01) peaks [0.1, 0.9, 0.6, 0.9]))
      -- A note no recording covers is an error, not silence.
      assert (isLeft (voiceRender 22050 1 [at 0 1000 0.5]))
      -- A recorded room: a delta (with a quieter echo 100 samples later)
      -- normalised to unit energy, convolved with the send bus exactly.
      impulse <- evalIO $ withSystemTempDirectory "neomusic" $ \dir -> do
        pcmWavBits 16 (dir </> "room.wav") 8000 [VU.generate 200 (\i -> if i == 0 then 0.8 else if i == 100 then 0.4 else 0)]
        readRecording (dir </> "room.wav") >>= used
      room <- evalEither impulse
      let sent = (voiceNote (Tone SineWave) 0 220 0.3 1) {send = 1}
          mixWith r = Mix 8000 noReverb 0 0.8 0 False r 16
      (dry, _) <- evalEither (renderTimelineMix (mixWith Nothing) (Timeline 0.5 [sent]))
      (wet, _) <- evalEither (renderTimelineMix (mixWith (Just (Room room 1 0))) (Timeline 0.5 [sent]))
      -- The taps are 2:1 after 16-bit rounding (26214 and 13107), so at unit energy 2/sqrt 5 and 1/sqrt 5.
      let expected = VU.imap (\i x -> x + 2 / sqrt 5 * x + (if i >= 100 then VU.unsafeIndex dry (i - 100) / sqrt 5 else 0)) dry
      annotateShow (VU.maximum (VU.map abs (VU.zipWith (-) wet expected)))
      assert (VU.maximum (VU.map abs (VU.zipWith (-) wet expected)) < 1e-9)
      assert (isLeft (renderTimelineMix (Mix 8000 hall 0 0.8 0 False (Just (Room room 1 0)) 16) (Timeline 0.5 [sent])))
      -- A room recorded at twice the rate is resampled without folding: a delta
      -- at its frame 200 lands exactly at frame 100. Four channels are refused.
      others <- evalIO $ withSystemTempDirectory "neomusic" $ \dir -> do
        pcmWavBits 16 (dir </> "fast.wav") 16000 [VU.generate 400 (\i -> if i == 200 then 0.5 else 0)]
        pcmWavBits 16 (dir </> "four.wav") 8000 (replicate 4 (VU.generate 100 (\i -> if i == 0 then 0.5 else 0)))
        (,) <$> (readRecording (dir </> "fast.wav") >>= used) <*> (readRecording (dir </> "four.wav") >>= used)
      fast <- evalEither (fst others)
      four <- evalEither (snd others)
      (shifted, _) <- evalEither (renderTimelineMix (mixWith (Just (Room fast 1 0))) (Timeline 0.5 [sent]))
      let echo = VU.imap (\i x -> x + (if i >= 100 then VU.unsafeIndex dry (i - 100) else 0)) dry
      annotateShow (VU.maximum (VU.map abs (VU.zipWith (-) shifted echo)))
      assert (VU.maximum (VU.map abs (VU.zipWith (-) shifted echo)) < 1e-9)
      assert (isLeft (renderTimelineMix (mixWith (Just (Room four 1 0))) (Timeline 0.5 [sent]))))
  , ("engine edges: loops, releases after then, note-on pitch, ringing and declicking", withTests 1 $ property $ do
      let rate = 44100 :: Int
          fr = fromIntegral rate :: Double
          mix0 = (defaultMix rate) {mixNormalize = False}
          energy v a b = VU.sum (VU.map (^ (2 :: Int)) (VU.slice a (b - a) v))
          frames = 4410                                   -- a 0.1 s recording of C4
          c4 = VU.generate frames (\i -> realToFrac (sin (2 * pi * 261.63 * fromIntegral i / fr)) :: Float)
          recording = Recording "memory.wav" fr frames Nothing [c4]
          setAt key lp = SampleSet "memory.sfz" [Region recording 60 (key, key) (1, 127) 1 (1, 1) lp False Nothing False]
          sampled key lp = Gain (adsr 0.001 0 1 0.05) (Sampled (setAt key lp))
          half = round (0.5 * fr) :: Int
      -- A loop may end on the recording's last frame and keeps playing.
      (looped, _) <- evalEither (renderTimelineMix mix0 (Timeline 1 [note 0 261.63 0.5 (sampled 60 (Just (0, frames - 1))) 1 1 0 0]))
      let first = energy looped 0 frames
      assert (energy looped (3 * frames) half > 0.5 * first)
      -- A release inside then's second part starts at note-off, not d later.
      let thenRelease = Then 1 (K 1) (Release 0.5 (K 1))
      assert (abs (modAt thenRelease 2 1 0 2.25 - 0.25) < 1e-12)
      modAt thenRelease 2 1 0 2.6 === 0
      -- Recordings are checked at the pitch a note starts on, as they're played:
      -- a C4 note starting an octave up needs the region at C5, not C4.
      let glideDown voice = (note 0 261.63 0.5 voice 1 1 0 0) {pitchMod = Breaks [(0, 1), (1, 0)]}
      (fromAbove, _) <- evalEither (renderTimelineMix mix0 (Timeline 1 [glideDown (sampled 72 Nothing)]))
      assert (energy fromAbove 0 half > 0)
      assert (isLeft (renderTimelineMix mix0 (Timeline 1 [glideDown (sampled 60 Nothing)])))
      -- A plucked string with no envelope rings out past note-off...
      (plucked, _) <- evalEither (renderTimelineMix mix0 (Timeline 1 [note 0 220 0.5 (Gain Velocity (Plucked 2.5 0.6)) 1 1 0 0]))
      assert (energy plucked (half + 2205) (half + 8820) > 0)
      -- ...and a tone with no release fades over 2 ms instead of clicking off.
      (cut, _) <- evalEither (renderTimelineMix mix0 (Timeline 1 [note 0 220 0.5 (Tone SineWave) 1 1 0 0]))
      let peak = VU.maximum (VU.map abs (VU.take half cut))
          lastWindow = VU.slice (half + 66) 22 cut              -- the final half millisecond
      assert (VU.maximum (VU.map abs lastWindow) < 0.3 * peak))
  , ("one-shots, fixed pitch and buses", withTests 1 $ property $ do
      let rate = 44100 :: Int
          fr = fromIntegral rate :: Double
          frames = 4410                                   -- a 0.1 s recording of C4
          c4 = VU.generate frames (\i -> realToFrac (sin (2 * pi * 261.63 * fromIntegral i / fr)) :: Float)
          recording = Recording "memory.wav" fr frames Nothing [c4]
          region fixed oneShot = Region recording 60 (0, 127) (1, 127) 1 (1, 1) Nothing False fixed oneShot
          sampled fixed oneShot = Sampled (SampleSet "memory.sfz" [region fixed oneShot])
          short voice f = voiceNote voice 0 f 0.02 1                  -- note-off at 882 frames
          energy v from to = VU.sum (VU.map (^ (2 :: Int)) (VU.slice from (to - from) v))
          worst a b = VU.maximum (VU.map abs (VU.zipWith (-) a b))
      -- The opcodes: pitch_keytrack is 0 or 100, and a fixed region's tune is a speed.
      loaded <- evalIO $ withSystemTempDirectory "neomusic" $ \dir -> do
        pcmWavBits 16 (dir </> "hit.wav") 22050 [VU.generate 2205 (\i -> 0.5 * sin (2 * pi * 220 * fromIntegral i / 22050))]
        writeFile (dir </> "drum.sfz") "<region> sample=hit.wav lokey=0 hikey=127 pitch_keytrack=0 tune=1200 loop_mode=one_shot\n<region> sample=hit.wav key=60\n"
        writeFile (dir </> "half.sfz") "<region> sample=hit.wav pitch_keytrack=50\n"
        (,) <$> readSampleSet [] (dir </> "drum.sfz") <*> readSampleSet [] (dir </> "half.sfz")
      drum <- evalEither (fst loaded)
      map (\r -> (regionFixed r, regionOneShot r)) (setRegions drum) === [(Just 2, True), (Nothing, False)]
      assert (isLeft (snd loaded))
      -- A one-shot plays to its end whenever the note ends; any other recording stops with the note.
      (cut, _) <- evalEither (voiceRender rate 0.5 [short (sampled Nothing False) 261.63])
      (whole, _) <- evalEither (voiceRender rate 0.5 [short (sampled Nothing True) 261.63])
      (held, _) <- evalEither (voiceRender rate 0.5 [voiceNote (sampled Nothing False) 0 261.63 0.2 1])
      energy cut 1000 4410 === 0
      assert (energy whole 1000 4400 > 100 && worst (VU.take 4400 whole) (VU.take 4400 held) < 1e-12)
      -- Played an octave lower it lasts twice as long, and all of it sounds.
      (low, _) <- evalEither (voiceRender rate 0.5 [short (sampled Nothing True) 130.815])
      assert (energy low 4500 8700 > 100 && energy low 8830 9000 == 0)
      -- A release above it still ends it: that is a choke.
      (choked, _) <- evalEither (voiceRender rate 0.5 [short (Gain (adsr 0.001 0 1 0.01) (sampled Nothing True)) 261.63])
      energy choked 1400 4410 === 0
      -- A fixed region plays as recorded on every key; one that follows the key does not.
      (onC, _) <- evalEither (voiceRender rate 0.5 [short (sampled (Just 1) True) 261.63])
      (onA, _) <- evalEither (voiceRender rate 0.5 [short (sampled (Just 1) True) 880])
      (movedA, _) <- evalEither (voiceRender rate 0.5 [short (sampled Nothing True) 880])
      annotateShow (worst onC onA)
      assert (worst onC onA < 1e-9 && worst onC movedA > 0.1)
      -- A bus sums an instrument's notes. Shapers that are linear give the
      -- same sound outside it as inside; a drive does not, since the notes
      -- of a chord then pass through it together.
      let inner = Gain (Velocity :* adsr 0.001 0 1 0.05) (Tone SawWave)
          chord voice = [voiceNote voice 0 110 0.3 0.4, voiceNote voice 0.05 164.81 0.25 0.4]
          render' ns = fst <$> voiceRender rate 0.5 ns
          cabinet v = Gain (K 0.5) (Lowpass (cutoffHz 2000) 0.2 (Highpass (cutoffHz 100) v))
      perNote <- evalEither (render' (chord (cabinet inner)))
      onBus <- evalEither (render' (chord (cabinet (Bus inner))))
      -- (While the notes sound: a note's filters stop with it, a bus's ring on.)
      let sounding = VU.take 13000
      annotateShow (worst (sounding perNote) (sounding onBus))
      assert (worst (sounding perNote) (sounding onBus) < 1e-9)
      drivenNotes <- evalEither (render' (chord (Drive (K 8) inner)))
      drivenBus <- evalEither (render' (chord (Drive (K 8) (Bus inner))))
      assert (worst drivenNotes drivenBus > 0.1 && VU.all ((<= 1) . abs) drivenBus)
      -- One note alone is the same either way.
      alone <- evalEither (render' (take 1 (chord (Drive (K 8) inner))))
      aloneBus <- evalEither (render' (take 1 (chord (Drive (K 8) (Bus inner)))))
      assert (worst (sounding alone) (sounding aloneBus) < 1e-9)
      -- A bus belongs to an instrument: the same sound at another pan is another bus.
      let driven = Drive (K 8) (Bus inner)
          left = (voiceNote driven 0 110 0.3 0.4) {pan = -1}
          right = (voiceNote driven 0.05 164.81 0.25 0.4) {pan = 1}
      both <- evalEither (render' [left, right])
      onlyLeft <- evalEither (render' [left])
      assert (worst both onlyLeft < 1e-9 && VU.maximum (VU.map abs onlyLeft) > 0.1)
      -- What may stand outside a bus.
      mapM_ (assert . isLeft . validVoice)
        [ Bus (Bus inner), Gain Velocity (Bus inner), Lowpass Key 0 (Bus inner), Bend (K 12) (Bus inner)
        , Unison 2 10 0 (Bus inner), inner :& Bus inner, Drive (adsr 0.1 0 1 0.1) (Bus inner) ]
      mapM_ (\v -> validVoice v === Right ())
        [ Bus inner, Drive (K 8) (Bus inner) :& Gain (K 0.2) (Bus (Tone SineWave)), Pan (K 0.5) (cabinet (Bus inner)) ])
  , ("16-bit TPDF dither: seeded, within one step, 24-bit untouched", withTests 1 $ property $ do
      let lsb = 1 / 32767
          quiet = VU.generate 4000 (\i -> 0.4 * lsb * sin (2 * pi * 440 * fromIntegral i / 8000))
          tone = VU.generate 4000 (\i -> 0.5 * sin (2 * pi * 220 * fromIntegral i / 8000))
          samples16 bytes = [ fromIntegral (BL.index bytes k) + 256 * fromIntegral (BL.index bytes (k + 1))
                              - (if BL.index bytes (k + 1) >= 128 then 65536 else 0) :: Int
                            | k <- [44, 46 .. BL.length bytes - 2] ]
          write dither bits chans = withSystemTempDirectory "neomusic" $ \dir -> do
            pcmWavWith dither bits (dir </> "x.wav") 8000 chans
            bytes <- BL.readFile (dir </> "x.wav")
            BL.length bytes `seq` pure bytes
      (a, b, c, plainTone, ditherTone, quietPlain, quietDither, p24, d24) <- evalIO $ (,,,,,,,,)
        <$> write (Tpdf 1) 16 [tone, tone] <*> write (Tpdf 1) 16 [tone, tone] <*> write (Tpdf 2) 16 [tone, tone]
        <*> write NoDither 16 [tone] <*> write (Tpdf 7) 16 [tone]
        <*> write NoDither 16 [quiet] <*> write (Tpdf 7) 16 [quiet]
        <*> write NoDither 24 [tone] <*> write (Tpdf 7) 24 [tone]
      a === b
      assert (a /= c)
      assert (all ((<= 1) . abs) (zipWith (-) (samples16 plainTone) (samples16 ditherTone)))
      assert (samples16 plainTone /= samples16 ditherTone)
      assert (all (== 0) (samples16 quietPlain))
      assert (any (/= 0) (samples16 quietDither))
      p24 === d24
      let noise = map (tpdfNoise 42) [0 .. 19999]
      assert (all (\x -> x > -1 && x < 1) noise)
      assert (abs (sum noise / 20000) < 0.02))
  , ("streamed export equals mastering then writing whole vectors", withTests 1 $ property $ do
      let notes = [ note (0.1 * fromIntegral k) (220 * (1 + 0.1 * fromIntegral k)) 0.3 (Classic sawPatch) 0.7 1 0 0.5
                  | k <- [0 .. 9 :: Int] ]
          timeline = Timeline 1.5 notes
          mixes = [ (defaultMix 22050) {mixReverb = hall, mixTail = 0.5}
                  , (defaultMix 22050) {mixReverb = hall {width = 0.4, preDelay = 0.01}, mixBits = 24, mixDrive = 1.5}
                  , (defaultMix 16000) {mixNormalize = False, mixPeak = 1} ]
      results <- evalIO $ withSystemTempDirectory "neomusic" $ \dir -> mapM (\(k, m) -> do
        let a = dir </> ("stream" ++ show k ++ ".wav"); b = dir </> ("whole" ++ show k ++ ".wav")
        writeTimelineMix a m timeline
        (l, r) <- either fail pure (renderTimelineMix m timeline)
        pcmWavWith defaultDither (mixBits m) b (mixRate m) [l, r]
        x <- BL.readFile a; y <- BL.readFile b
        pure (BL.length x > 44, x == y)) (zip [0 :: Int ..] mixes)
      results === replicate 3 (True, True))
  ]
