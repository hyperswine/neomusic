-- | Unitless music. Interpretation is supplied once, outside the score tree.
module NeoMusic.Score
  ( Event(..), Phrase, Name, Score(..), Shape(..), PitchIdentity(..), Instrument(..), Performance(..)
  , steady, swung, speedOf, swingOf, shapeSource
  , TimeMap, timeMap, timePieces, performed, tempoNodes, tempoSpans, exactSpeedAt, overlappingTempo, hold
  , module NeoMusic.Signal
  , addPitch, scaleStrength, strengthAcross, scaleLevel, levelAcross, dynamicsAcross, pitchAcross, addLag, lagAcross, glide, vel, pitchParts, bendMotion, swellMotion, vibrates
  , BeatEvent(..), n, chord, rest, hit, hush, transpose, invert, retro, stretch
  , withRhythm, withGate, scaleGate, staccato, pedal
  , mapPhrases, scaleScore, reverseScore, ensemble, conductorTrack, arrange, conductorOf, withoutTempo, tempoClash, scoreLength, flatten, validate, render, writeAudio, writeAudioWith
  , defaultInstrument, defaultPerformance
  ) where

import Control.Monad (unless, forM_)
import qualified Data.Map.Strict as M
import Data.List (nub, sort)
import GHC.Float (expm1)
import Data.Ratio (denominator, numerator)
import qualified NeoMusic.Audio as A
import NeoMusic.Pitch (Step(..), Tuning(..), freq)
import NeoMusic.Signal

type Name = String
-- | 'dur' is the time the event occupies; the next event starts after it.
-- 'gate' is how long it sounds, as a ratio of 'dur': 1 is as written, below 1
-- is detached (staccato), above 1 rings into what follows (legato, pedal).
-- Because the gate is a ratio, 'stretch' leaves articulation unchanged.
-- 'lag' is how many beats after its written onset the note sounds (before, if
-- negative): a performance nuance, like the gate, that the reading views
-- leave out. 'stretch' scales it with the durations.
--
-- Two signals shape a note while it sounds: 'pitchShift' is added to every
-- pitch, in steps ('Cents' parts in cents), and 'level' multiplies its
-- loudness. Pitch signals add and level signals multiply, so nesting composes
-- exactly. Attack strength is independent of expression; no signal syntax
-- determines velocity. Rests have strength 0 and ignore these transforms.
data Event = Event
  { dur :: Rational, gate :: Rational, lag :: Rational, pitches :: [Step]
  , strength :: Signal, pitchShift :: Signal, level :: Signal }
  deriving (Eq, Show)

type Phrase = [Event]
-- | 'Tempo' says how fast its music is performed relative to the written beats.
-- It acts on everything sounding during its written extent, in every voice:
-- the score has one shared clock (see "docs/2026-10-12-NEOMUSIC-TIMEMAP.md").
data Score = Line Name Phrase | Silence Rational | Score :>>: Score | Score :||: Score
  | Tempo Shape Score
  deriving (Eq, Show)

-- | A tempo factor over a node's written extent: 1 is as written, 1/2 half speed.
-- Every shape is piecewise log-linear (equal tempo ratio per beat), so nested
-- shapes multiply into the same family. See docs/2026-10-14-NEOMUSIC-CYCLE.md.
data Shape
  = Ramp Rational Rational        -- ^ from factor a at the start to b at the end (a == b: constant)
  | Cycle [(Rational, Shape)]     -- ^ these segments (written beats, shape), repeated from the start
  deriving (Eq, Show)

-- | A constant speed.
steady :: Rational -> Shape
steady r = Ramp r r

-- | Swing: in each period of @p@ beats, the first half takes share @s@ of the time.
swung :: Rational -> Rational -> Shape
swung p s = Cycle [(p / 2, steady (1 / (2 * s))), (p / 2, steady (1 / (2 * (1 - s))))]

-- | A shape as the argument of @speed@ in .neomusic source.
shapeSource :: Shape -> String
shapeSource (Ramp a b) = if a == b then fraction a else fraction a ++ " -> " ++ fraction b
shapeSource (Cycle segs) = "cycle {" ++ unwords [fraction l ++ ":" ++ segment sub | (l, sub) <- segs] ++ "}"
  where segment sub = if speedOf sub /= Nothing then shapeSource sub else "(" ++ shapeSource sub ++ ")"

fraction :: Rational -> String
fraction x = show (numerator x) ++ (if denominator x == 1 then "" else "/" ++ show (denominator x))

-- | The factor of a constant speed.
speedOf :: Shape -> Maybe Rational
speedOf (Ramp a b) | a == b = Just a
speedOf _ = Nothing

-- | Period and long share of a swing: two equal constant halves whose times
-- add up to the period.
swingOf :: Shape -> Maybe (Rational, Rational)
swingOf (Cycle [(h1, Ramp a a'), (h2, Ramp b b')])
  | h1 == h2 && a == a' && b == b' && a > 0 && b > 0 && 1 / a + 1 / b == 2
  = Just (2 * h1, 1 / (2 * a))
swingOf _ = Nothing
infixr 5 :>>:
infixr 4 :||:
instance Semigroup Score where (<>) = (:>>:)
instance Monoid Score where mempty = Silence 0

-- | How score pitches are interpreted by notation/MIDI. This is declared by
-- the instrument, never guessed from its synthesis graph.
data PitchIdentity = Pitched | Unpitched deriving (Eq, Show)

data Instrument = Instrument
  { tuning :: Tuning, timbre :: A.Voice, gain :: Double, pan :: Double, send :: Double
  , pitchIdentity :: PitchIdentity }
  deriving (Eq, Show)
data Performance = Performance
  { bpm :: Double, instruments :: M.Map Name Instrument, mix :: A.Mix }
  deriving (Eq, Show)
data BeatEvent = BeatEvent { onset :: Rational, instrument :: Name, event :: Event }
  deriving (Eq, Show)

defaultInstrument :: Instrument
defaultInstrument = Instrument (Tuning (440 * 2 ** (-9/12)) (2 ** (1/12))) (A.Classic A.pianoPatch) 1 0 0 Pitched
defaultPerformance :: Performance
defaultPerformance = Performance 120 M.empty (A.defaultMix 44100)

n :: Int -> Phrase
n x = chord [x]
chord :: [Int] -> Phrase
chord xs = hit xs 1 1
rest :: Phrase
rest = hush 1
hit :: [Int] -> Rational -> Double -> Phrase
hit xs d v = [Event d 1 0 (map Step xs) (Const (toRational v)) (Const 0) (Const 1)]
hush :: Rational -> Phrase
hush d = [Event d 1 0 [] (Const 0) (Const 0) (Const 1) | d /= 0]
transpose :: Int -> Phrase -> Phrase
transpose k = map (\e -> e {pitches = [Step (x+k) | Step x <- pitches e]})
invert :: Phrase -> Phrase
-- Mirroring a pitch around 0 mirrors its offset too.
invert = map (\e -> e {pitches = [Step (negate x) | Step x <- pitches e], pitchShift = negateSignal (pitchShift e)})
-- | Retrograde: the events in reverse order, and each note's own curves
-- played backwards too (a rising bend falls, a crescendo within a note
-- becomes a diminuendo), as 'reverseScore' mirrors tempo ramps. Waves and
-- noise keep to the beat and onset values stay with their notes.
retro :: Phrase -> Phrase
retro = reverse . map (\e -> e {pitchShift = mirror (pitchShift e), level = mirror (level e)})
  where
    mirror sig = case sig of
      Points ps -> Points (reverse [(1 - u, v) | (u, v) <- ps])
      a :+: b -> mirror a :+: mirror b
      a :*: b -> mirror a :*: mirror b
      Cents a -> Cents (mirror a)
      other -> other
stretch :: Rational -> Phrase -> Phrase
stretch k = map (\e -> e {dur = k * dur e, lag = k * lag e})
-- | Set every event's gate, replacing whatever was there.
withGate :: Rational -> Phrase -> Phrase
withGate g = map (\e -> e {gate = g})
-- | Multiply every event's gate: @scaleGate a . scaleGate b = scaleGate (a*b)@.
scaleGate :: Rational -> Phrase -> Phrase
scaleGate k = map (\e -> e {gate = k * gate e})
-- | Detached: each note sounds for half its written length.
staccato :: Phrase -> Phrase
staccato = scaleGate (1/2)

-- | Add a pitch signal to every note: @addPitch a . addPitch b = addPitch (a + b)@.
addPitch :: Signal -> Phrase -> Phrase
addPitch sig = map (\e -> if null (pitches e) then e else e {pitchShift = plus sig (pitchShift e)})

-- | Attack strength, independent of the expression signal. Multiplicative.
scaleStrength :: Signal -> Phrase -> Phrase
scaleStrength k = map (\e -> if null (pitches e) then e else e {strength = times k (strength e)})

-- | Multiply every note's level: @scaleLevel a . scaleLevel b = scaleLevel (a * b)@.
scaleLevel :: Signal -> Phrase -> Phrase
scaleLevel sig = map (\e -> if null (pitches e) then e else e {level = times sig (level e)})

-- | A pitch signal's constant steps, constant cents, and varying rest.
pitchParts :: Signal -> (Rational, Rational, Signal)
pitchParts sig = (sum steps, sum cs, foldr plus (Const 0) varying)
  where
    parts = terms sig
    steps = [k | t <- parts, Just k <- [constantValue t]]
    cs = [k | Cents t <- parts, Just k <- [constantValue t]]
    varying = [t | t <- parts, not (isConstantTerm t)]
    isConstantTerm t = case t of
      Cents a -> constantValue a /= Nothing
      _ -> constantValue t /= Nothing

-- | Attack strength: MIDI velocity and the sound's velocity input.
vel :: Event -> Double
vel e = maybe (valueAt 0 0 0 (strength e)) fromRational (constantValue (strength e))

-- | The pitch signal's shape: up, down, or away and back (oscillation ignored).
bendMotion :: Event -> Motion
bendMotion = motion . pitchShift

-- | The varying level's shape: growing, fading, or both.
swellMotion :: Event -> Motion
swellMotion = motion . level

-- | Whether the pitch oscillates (vibrato, trill).
vibrates :: Event -> Bool
vibrates = oscillates . pitchShift

-- | Portamento: each single-pitch note slides to the pitch of the note that
-- follows it directly (same instrument, single pitch, starting exactly when
-- its slot ends), over the last fraction @f@ of its sounding time. Notes with
-- no such successor, chords and rests are unchanged.
glide :: Rational -> Score -> Score
glide f score = fst (go 0 score)
  where
    starts = M.fromListWith (++) [((instrument e, onset e), [pitches (event e)]) | e <- either (const []) snd (flatten score)]
    target name t = case M.lookup (name, t) starts of
      Just [[Step y]] -> Just y
      _ -> Nothing
    slide name t e = case pitches e of
      [Step x] | Just y <- target name (t + dur e), y /= x ->
        e {pitchShift = plus (Points [(0, 0), (1 - f, 0), (1, fromIntegral (y - x))]) (pitchShift e)}
      _ -> e
    go at (Line name xs) =
      (Line name (zipWith (slide name) (scanl (+) at (map dur xs)) xs), at + sum (map dur xs))
    go at (Silence d) = (Silence d, at + d)
    go at (a :>>: b) = let (a', ta) = go at a; (b', tb) = go ta b in (a' :>>: b', tb)
    go at (a :||: b) = let (a', ta) = go at a; (b', tb) = go at b in (a' :||: b', max ta tb)
    go at (Tempo shape s) = let (s', t) = go at s in (Tempo shape s', t)

-- | A fermata: the music inside is held @k@ times as long ('steady' (1/k)).
-- The staff view prints a fermata when this covers a single onset.
hold :: Rational -> Score -> Score
hold k = Tempo (steady (1 / k))

-- | Sustain pedal held down for the whole score: every note rings until the
-- score's end. Onsets and lengths are unchanged; only gates grow. Rests stay rests.
pedal :: Score -> Score
pedal score = fst (go 0 score)
  where
    end = scoreLength score
    go at (Line name xs) =
      let onsets = scanl (+) at (map dur xs)
          held t e = if null (pitches e) then e else e {gate = max (gate e) ((end - t) / dur e)}
      in (Line name (zipWith held onsets xs), at + sum (map dur xs))
    go at (Silence d) = (Silence d, at + d)
    go at (a :>>: b) = let (a', ta) = go at a; (b', tb) = go ta b in (a' :>>: b', tb)
    go at (a :||: b) = let (a', ta) = go at a; (b', tb) = go at b in (a' :||: b', max ta tb)
    go at (Tempo shape s) = let (s', t) = go at s in (Tempo shape s', t)

-- | Expression over a group. It never changes attack strength.
levelAcross :: Signal -> Score -> Either String Score
levelAcross = across (\piece e -> Right e {level = times piece (level e)})

-- | Sample a group signal at each note's written onset for its attack strength.
strengthAcross :: Signal -> Score -> Either String Score
strengthAcross = across $ \piece e -> do
  _ <- onsetLevel piece
  pure e {strength = times (Start piece) (strength e)}

-- | A coordinated dynamic gesture: attack strength follows the onset value,
-- expression follows the remaining curve. Unlike 'levelAcross', this changes
-- both controls. A note starting from silence takes its strength from the
-- curve's peak within it instead, so the fade-in sounds and attacks still
-- rise through the gesture (a neutral strength of 1 would make the first
-- note of a crescendo from nothing its loudest attack). A note whose curve
-- never rises above zero keeps neutral strength and stays silent.
dynamicsAcross :: Signal -> Score -> Either String Score
dynamicsAcross = across $ \piece e -> do
  k <- onsetLevel piece
  let peak = snd (signalBounds piece)
      (attack, held) | k /= 0 = (k, Start piece)
                     | peak > 0 = (peak, Const peak)
                     | otherwise = (1, Const 1)
  pure e {strength = times held (strength e),
          level = times (normalize attack piece) (level e)}
  where
    normalize k (Points ps) = Points [(u, v / k) | (u, v) <- ps]
    normalize k sig = times (Const (1 / k)) sig

onsetLevel :: Signal -> Either String Rational
onsetLevel sig
  | hasCents sig = Left "cents only make sense in a pitch"
  | otherwise = maybe (Left "strength needs an exact value at the note's start") Right (exactAt 0 0 sig)

-- | A pitch signal spanning the whole score rather than each note.
pitchAcross :: Signal -> Score -> Either String Score
pitchAcross = across (\piece e -> Right e {pitchShift = plus piece (pitchShift e)})

-- | Every note sounds this many beats later (earlier, if negative).
addLag :: Rational -> Phrase -> Phrase
addLag k = map (\e -> if null (pitches e) then e else e {lag = lag e + k})

-- | Each note's lag grows by a score-long signal's value where the note starts.
lagAcross :: Signal -> Score -> Either String Score
lagAcross = across $ \piece e -> case exactAt 0 0 piece of
  Just k -> Right e {lag = lag e + k}
  Nothing -> Left "a lag must be a number at each note's start (no waves, no cents)"

-- | Apply a score-long signal note by note, each note getting its own span of it.
across :: (Signal -> Event -> Either String Event) -> Signal -> Score -> Either String Score
across apply sig score = fst <$> go 0 score
  where
    total = scoreLength score
    go at (Line name xs) = do
      let onsets = scanl (+) at (map dur xs)
          place t e
            | null (pitches e) || total <= 0 = Right e
            | otherwise = restrictTo total (t / total) ((t + dur e * gate e) / total) sig >>= (`apply` e)
      xs' <- sequence (zipWith place onsets xs)
      pure (Line name xs', at + sum (map dur xs))
    go at (Silence d) = Right (Silence d, at + d)
    go at (a :>>: b) = do (a', ta) <- go at a; (b', tb) <- go ta b; pure (a' :>>: b', tb)
    go at (a :||: b) = do (a', ta) <- go at a; (b', tb) <- go at b; pure (a' :||: b', max ta tb)
    go at (Tempo shape s) = do (s', t) <- go at s; pure (Tempo shape s', t)

-- | Length in beats, from durations (gates never change it).
scoreLength :: Score -> Rational
scoreLength (Line _ xs) = sum (map dur xs)
scoreLength (Silence d) = d
scoreLength (a :>>: b) = scoreLength a + scoreLength b
scoreLength (a :||: b) = max (scoreLength a) (scoreLength b)
scoreLength (Tempo _ s) = scoreLength s

withRhythm :: [Rational] -> Phrase -> Either String Phrase
withRhythm rs xs
  | null rs || any (<=0) rs = Left "rhythm pattern must be nonempty and positive"
  | otherwise = Right (zipWith (\d e -> e {dur = d}) (cycle rs) xs)
mapPhrases :: (Phrase -> Phrase) -> Score -> Score
mapPhrases f = go
  where
    go (Line name xs) = Line name (f xs)
    go (Silence d) = Silence d
    go (a :>>: b) = go a :>>: go b
    go (a :||: b) = go a :||: go b
    go (Tempo shape s) = Tempo shape (go s)

scaleScore :: Rational -> Score -> Score
scaleScore k (Silence d) = Silence (k*d)
scaleScore k (Line name xs) = Line name (stretch k xs)
scaleScore k (a :>>: b) = scaleScore k a :>>: scaleScore k b
scaleScore k (a :||: b) = scaleScore k a :||: scaleScore k b
scaleScore k (Tempo shape s) = Tempo (scaled shape) (scaleScore k s)
  where
    scaled (Cycle segs) = Cycle [(k * l, scaled sub) | (l, sub) <- segs]
    scaled other = other
reverseScore :: Score -> Score
reverseScore (Line name xs) = Line name (retro xs)
reverseScore (Silence d) = Silence d
reverseScore (a :>>: b) = reverseScore b :>>: reverseScore a
-- A ramp runs backwards; a cycle's segments run in reverse order, each mirrored,
-- so swing becomes short-long (exact when the extent is a whole number of
-- periods, since periods are counted from the node's start).
reverseScore (Tempo shape s) = Tempo (mirrored shape) (reverseScore s)
  where
    mirrored (Ramp a b) = Ramp b a
    mirrored (Cycle segs) = Cycle (reverse [(l, mirrored sub) | (l, sub) <- segs])
reverseScore (a :||: b) =
  let da = scoreLength a
      db = scoreLength b
      total = max da db
  in (Silence (total-da) :>>: reverseScore a) :||: (Silence (total-db) :>>: reverseScore b)


-- | Independent named parts as one ensemble with one clock.
--
-- Tempo is global: a change acts on everything sounding during its beats, in
-- every part. So any part may carry its own tempo; it is hoisted out of the
-- part into a single clock (@clock :||: music@), keeping its written
-- position, and so its effect, exactly. A conductor is just a part with no
-- notes. The one rule is 'tempoClash': no two parts may set the tempo over the
-- same written beats. Within one part, nested changes multiply as written.
ensemble :: [(Name, Score)] -> Either String Score
ensemble parts = do
  let owners = [(name, nodes) | (name, p) <- parts, let nodes = tempoNodes p, not (null nodes)]
  forM_ [(x, y) | (i, x) <- zip [0 :: Int ..] owners, y <- drop (i + 1) owners] $
    \((n1, t1), (n2, t2)) -> case tempoClash t1 t2 of
      Just (u, v) -> Left (n1 ++ " and " ++ n2 ++ " both set the tempo over beats " ++ beatText u ++ "-" ++ beatText v
                           ++ "; keep it in one of them, or in a conductor: track")
      Nothing -> pure ()
  let music = foldr (:||:) (Silence 0) [withoutTempo p | (_, p) <- parts]
      clock = foldr (:||:) (Silence 0) [conductorOf p | (_, p) <- parts, not (null (tempoNodes p))]
      result = if null owners then music else clock :||: music
  _ <- flatten result
  pure result

-- | A conductor: written time and tempo, no notes (its rests become silence,
-- so it names no instrument).
conductorTrack :: Score -> Either String Score
conductorTrack conductor = do
  (_, es) <- flatten conductor
  unless (all (null . pitches . event) es) (Left "a conductor track contains rests and tempo, not notes")
  pure (conductorOf conductor)

-- | One conductor and independent parts ('ensemble' with the conductor as a
-- part). Parts may keep their own tempo where the conductor sets none.
arrange :: Score -> [Score] -> Either String Score
arrange conductor parts = do
  c <- conductorTrack conductor
  ensemble (("conductor", c) : [("part " ++ show i, p) | (i, p) <- zip [1 :: Int ..] parts])

-- | The first written span where both lists set a tempo other than 1: two
-- owners of the same beats. (Nesting inside one owner is not a clash.)
tempoClash :: [(Rational, Rational, Shape)] -> [(Rational, Rational, Shape)] -> Maybe (Rational, Rational)
tempoClash xs ys = case [(max a b, min (a + da) (b + db)) | x@(a, da, _) <- xs, y@(b, db, _) <- ys, overlap x y] of
  clash : _ -> Just clash
  [] -> Nothing

beatText :: Rational -> String
beatText r = if denominator r == 1 then show (numerator r) else show (numerator r) ++ "/" ++ show (denominator r)

-- | Keep written structure and tempo, replacing all events with silence.
-- Useful for migrating an existing score to explicit conductor ownership.
conductorOf :: Score -> Score
conductorOf (Line _ xs) = Silence (sum (map dur xs))
conductorOf (Silence d) = Silence d
conductorOf (a :>>: b) = conductorOf a :>>: conductorOf b
conductorOf (a :||: b) = conductorOf a :||: conductorOf b
conductorOf (Tempo shape s) = Tempo shape (conductorOf s)

withoutTempo :: Score -> Score
withoutTempo (Tempo _ s) = withoutTempo s
withoutTempo (a :>>: b) = withoutTempo a :>>: withoutTempo b
withoutTempo (a :||: b) = withoutTempo a :||: withoutTempo b
withoutTempo s = s

-- | Exact beat onsets, shared by audio, MIDI and engraving. Rests remain events.
flatten :: Score -> Either String (Rational, [BeatEvent])
flatten = go 0
  where
    go at (Line name xs) = do
      unless (all ((> 0) . dur) xs) (Left "events need positive durations")
      unless (all ((> 0) . gate) xs) (Left "gates must be positive")
      unless (all (\e -> validPoints (pitchShift e) && validPoints (level e)) xs)
        (Left "signal points need u within 0..1, in nondecreasing order")
      unless (all (not . hasCents . level) xs) (Left "cents only make sense in a pitch")
      unless (all (\e -> not (hasCents (strength e)) && validPoints (strength e)
                          && maybe False (\k -> k >= 0 && k <= 1) (constantValue (strength e))) xs)
        (Left "a note's strength must be within 0..1")
      unless (all (\e -> fst (signalBounds (level e)) >= 0) xs)
        (Left "a level cannot go below 0")
      let onsets = scanl (+) at (map dur xs)
      unless (and [t + lag e >= 0 | (t, e) <- zip onsets xs, not (null (pitches e))])
        (Left "a note's lag cannot move it before the start of the piece")
      pure (sum (map dur xs), zipWith (\t e -> BeatEvent t name e) onsets xs)
    go _ (Silence d)
      | d < 0 = Left "silence cannot have negative duration"
      | otherwise = Right (d, [])
    go at (a :>>: b) = do
      (da, na) <- go at a
      (db, nb) <- go (at+da) b
      pure (da+db, na++nb)
    go at (a :||: b) = do
      case tempoClash (tempoNodes a) (tempoNodes b) of
        Just (u, v) -> Left ("parallel branches both set the tempo over beats " ++ beatText u ++ "-" ++ beatText v
                             ++ "; put the shared tempo around them, or in one of them")
        Nothing -> pure ()
      (da, na) <- go at a
      (db, nb) <- go at b
      pure (max da db, na++nb)
    go at (Tempo shape s) = validShape shape >> go at s
    validShape (Ramp a b) = unless (a > 0 && b > 0) (Left "tempo factors must be positive")
    validShape (Cycle segs) = do
      unless (not (null segs) && all ((> 0) . fst) segs)
        (Left "a tempo cycle needs segments of positive length")
      mapM_ (validShape . snd) segs

-- | Every tempo node with its written start and length, outermost first.
tempoNodes :: Score -> [(Rational, Rational, Shape)]
tempoNodes = snd . go 0
  where
    go _ (Line _ xs) = (sum (map dur xs), [])
    go _ (Silence d) = (d, [])
    go at (a :>>: b) = let (da, xa) = go at a; (db, xb) = go (at + da) b in (da + db, xa ++ xb)
    go at (a :||: b) = let (da, xa) = go at a; (db, xb) = go at b in (max da db, xa ++ xb)
    go at (Tempo shape s) = let (d, xs) = go at s in (d, (at, d, shape) : xs)

-- | The shared clock: written beats to performed beats. Pieces are keyed by
-- written start: end, log factor at the start, log slope per beat, and the
-- performed time at the start. Outside every piece the factor is 1.
newtype TimeMap = TimeMap (M.Map Rational (Rational, Double, Double, Double))
  deriving (Eq, Show)

timeMap :: Score -> TimeMap
timeMap score = TimeMap (M.fromList (scan 0 0 merged))
  where
    pieces = concatMap nodePieces (tempoNodes score)
    nodePieces (t0, len, shape) = filter (\(u, v, _, _) -> u < v) (shapePieces t0 len (t0 + len) shape)
    -- A shape spanning [start, start + len), cut off at @clip@. A cycle lays
    -- its segments end to end and repeats them; each segment's shape spans
    -- the segment.
    shapePieces start len clip shape = case shape of
      Ramp a b -> [(start, min (start + len) clip, ln a, ln (b / a) / fromRational len) | len > 0]
      Cycle segs ->
        let end = min (start + len) clip
            period = sum (map fst segs)
        in concat [ shapePieces (t + offset) l end sub
                  | period > 0, t <- takeWhile (< end) [start, start + period ..]
                  , (offset, (l, sub)) <- zip (scanl (+) 0 (map fst segs)) segs, t + offset < end ]
    ln = log . fromRational
    breaks = M.keys (M.fromList [(x, ()) | (u, v, _, _) <- pieces, x <- [u, v]])
    -- Factors multiply where nodes overlap, so log factors and slopes add.
    merged = [ (x0, x1, sum [la + k * fromRational (x0 - u) | (u, _, la, k) <- covering], sum [k | (_, _, _, k) <- covering])
             | (x0, x1) <- zip breaks (drop 1 breaks)
             , let covering = [p | p@(u, v, _, _) <- pieces, u <= x0, x1 <= v]
             , not (null covering) ]
    scan _ _ [] = []
    scan prevEnd prevPerf ((x0, x1, la, k) : more) =
      let start = prevPerf + fromRational (x0 - prevEnd)
      in (x0, (x1, la, k, start)) : scan x1 (start + logLinear la k (fromRational (x1 - x0))) more

-- | Performed beats taken by @x@ written beats of factor @exp (la + k t)@.
logLinear :: Double -> Double -> Double -> Double
logLinear la k x
  | k == 0 = x * exp (negate la)
  | otherwise = exp (negate la) * negate (expm1 (negate k * x)) / k

-- | The clock's pieces: written start, written end, log slope per beat (0 = constant).
timePieces :: TimeMap -> [(Rational, Rational, Double)]
timePieces (TimeMap m) = [(u, v, k) | (u, (v, _, k, _)) <- M.toList m]

performed :: TimeMap -> Rational -> Double
performed (TimeMap m) b = case M.lookupLE b m of
  Nothing -> fromRational b
  Just (u, (v, la, k, start))
    | b < v -> start + logLinear la k (fromRational (b - u))
    | otherwise -> start + logLinear la k (fromRational (v - u)) + fromRational (b - v)

-- | Effective tempo factors at both ends of each log-linear clock segment,
-- including straight gaps. These describe the combined clock, not its syntax.
tempoSpans :: Score -> [(Rational, Rational, Double, Double)]
tempoSpans score = [(a,b,rate a a,rate a b) | (a,b) <- zip bounds (drop 1 bounds)]
  where
    TimeMap m = timeMap score
    total = scoreLength score
    bounds = sort (nub (0 : total : [t | (a,(b,_,_,_)) <- M.toList m, t <- [a,b], t >= 0, t <= total]))
    rate at t = case M.lookupLE at m of
      Just (a,(b,la,k,_)) | at < b -> exp (la + k * fromRational (t-a))
      _ -> 1

-- | The exact combined speed factor at a written beat, when every tempo node
-- covering it is a constant speed (nested factors multiply exactly);
-- 'Nothing' inside a ramp or cycle. Reading views use this so exact tempos
-- never pass through floating point.
exactSpeedAt :: Score -> Rational -> Maybe Rational
exactSpeedAt score t = product <$> mapM speedOf [shape | (u, d, shape) <- tempoNodes score, u <= t, t < u + d]

-- | More than one tempo factor active at once (intentional nesting). Reading
-- views use the effective clock here instead of displaying conflicting marks.
overlappingTempo :: Score -> Bool
overlappingTempo score = or [overlap a b | (i,a) <- zip [0::Int ..] nodes, b <- drop (i+1) nodes]
  where nodes = tempoNodes score

overlap :: (Rational,Rational,Shape) -> (Rational,Rational,Shape) -> Bool
overlap (a,da,sa) (b,db,sb) = da > 0 && db > 0 && a < b+db && b < a+da
  && speedOf sa /= Just 1 && speedOf sb /= Just 1

-- | Check a performance against a score without rendering it: tempo, every
-- declared instrument, and that every line names a declared instrument.
validate :: Performance -> Score -> Either String ()
validate performance score = do
  _ <- flatten score
  unless (positive (bpm performance)) (Left "tempo must be finite and positive")
  forM_ (M.toList (instruments performance)) $ \(name, i) -> do
    let Tuning base r = tuning i
        context message = "instrument " ++ name ++ ": " ++ message
    unless (positive base && positive r) (Left (context "tuning must be finite and positive"))
    either (Left . context) Right (A.validVoice (timbre i))
    unless (finite (gain i) && gain i >= 0) (Left (context "gain must be finite and nonnegative"))
    unless (finite (pan i) && abs (pan i) <= 1) (Left (context "pan must be within -1..1"))
    unless (finite (send i) && send i >= 0 && send i <= 1) (Left (context "reverb send must be within 0..1"))
  forM_ (lineNames score) $ \name ->
    unless (M.member name (instruments performance)) (Left ("unknown instrument: " ++ name))
  where
    lineNames (Line name _) = [name]
    lineNames (Silence _) = []
    lineNames (a :>>: b) = lineNames a ++ lineNames b
    lineNames (a :||: b) = lineNames a ++ lineNames b
    lineNames (Tempo _ s) = lineNames s

-- | Beats become seconds here, once, for the whole score.
render :: Performance -> Score -> Either String A.Timeline
render performance score = do
  validate performance score
  (total,es) <- flatten score
  let clock = timeMap score
      seconds beats = performed clock beats * (60 / bpm performance)
  -- Constant pitch terms become frequency; strength is explicit. Only the
  -- varying parts reach the engine's per-sample path.
  ns <- sequence [ (\pitchMod -> A.Note (seconds (onset e + lag ev)) hz
               (seconds (onset e + lag ev + dur ev * gate ev) - seconds (onset e + lag ev))
               (timbre i) (vel ev) (gain i) (pan i) (send i) (musical pitchMod) loud)
                 <$> pitchContour octavesPerStep soundingBeats varyingPitch
           | e <- es, let ev = event e, let i = instruments performance M.! instrument e, step <- pitches ev
           , let octavesPerStep = logBase 2 (ratio (tuning i))
                 soundingBeats = fromRational (dur ev * gate ev)
                 (constSteps, constCents, varyingPitch) = pitchParts (pitchShift ev)
                 varyingLevel = level ev
                 base = freq (tuning i) step * 2 ** (fromRational constCents / 1200)
                 hz = if constSteps == 0 then base else base * ratio (tuning i) ** fromRational constSteps
                 loud = if varyingLevel == Const 1 then A.Flat 1 else musical (contour 0 soundingBeats varyingLevel)
                 musical = clockContour clock (onset e + lag ev) (dur ev * gate ev) ]
  unless (all (\v -> finite (A.start v) && positive (A.duration v) && positive (A.hz v)) ns
          && finite (seconds total)) (Left "score time or pitch cannot be represented in seconds and Hz")
  pure (A.Timeline (seconds total) ns)

-- | Lower pitch to octaves without first dividing cents by the step size.
-- A ratio of 1 has zero-sized steps, but cents still have their usual meaning.
-- Addition and unitless multiplication preserve that independent conversion.
pitchContour :: Double -> Double -> Signal -> Either String A.Contour
pitchContour octavesPerStep beats sig
  | not (hasCents sig) = pure (scaled octavesPerStep (contour 0 beats sig))
  | otherwise = case sig of
      Cents a | not (hasCents a) -> pure (scaled (1/1200) (contour 0 beats a))
      a :+: b -> (A.:+.) <$> lower a <*> lower b
      a :*: b | not (hasCents a) -> (contour 0 beats a A.:*.) <$> lower b
              | not (hasCents b) -> (A.:*. contour 0 beats b) <$> lower a
      Start a -> (\c -> A.Flat (A.contourAt c 0)) <$> lower a
      -- Preserve the existing step-based arithmetic for products/nesting of
      -- cents. Their reciprocal step size is undefined at ratio 1.
      _ | octavesPerStep == 0 -> Left "products or nesting of cents require a tuning ratio other than 1"
        | otherwise -> pure (scaled octavesPerStep (contour (1 / (1200 * octavesPerStep)) beats sig))
  where
    lower = pitchContour octavesPerStep beats
    scaled 0 _ = A.Flat 0
    scaled 1 c = c
    scaled k (A.Flat x) = A.Flat (k * x)
    scaled k c = A.Flat k A.:*. c

-- | Pull a musical contour through the shared clock. The engine receives
-- only dimensionless coordinates; it still knows nothing about score beats.
clockContour :: TimeMap -> Rational -> Rational -> A.Contour -> A.Contour
clockContour _ _ _ c@(A.Flat _) = c
clockContour clock start length' c
  | all (\seg -> A.clockCurve seg == 0 && A.timeFrom seg == A.positionFrom seg
               && A.timeTo seg == A.positionTo seg) segments = c
  | otherwise = A.Warp segments c
  where
    end = start + length'
    pieces = timePieces clock
    boundaries = sort (nub (start : end : [b | (x,y,_) <- pieces, b <- [x,y], b > start, b < end]))
    t0 = performed clock start
    elapsed = performed clock end - t0
    time b = (performed clock b - t0) / elapsed
    position b = fromRational ((b - start) / length')
    slope b = sum [k | (x,y,k) <- pieces, x <= b, b < y]
    segments = [A.ClockSegment (time a) (time b) (position a) (position b)
                  (slope a * fromRational (b-a)) | (a,b) <- zip boundaries (drop 1 boundaries)]

-- | A signal as the engine's contour: oscillator rates become cycles over the
-- note, and 'Cents' parts become steps.
contour :: Double -> Double -> Signal -> A.Contour
contour stepsPerCent beats sig
  | Just k <- constantValue sig = A.Flat (fromRational k)
  | otherwise = contourVarying stepsPerCent beats sig

contourVarying :: Double -> Double -> Signal -> A.Contour
contourVarying stepsPerCent beats sig = case sig of
  Const k -> A.Flat (fromRational k)
  Points ps -> A.Breaks [(fromRational u, fromRational y) | (u, y) <- ps]
  Osc w r -> A.Cycles (case w of Sine -> A.SineWave; Square -> A.SquareWave) (fromRational r * beats)
  a :+: b -> contour stepsPerCent beats a A.:+. contour stepsPerCent beats b
  a :*: b -> contour stepsPerCent beats a A.:*. contour stepsPerCent beats b
  Cents a -> A.Flat stepsPerCent A.:*. contour stepsPerCent beats a
  -- Noise is straight lines between its knots, so its knots are breakpoints.
  Noise seed rate offset ->
    let r = fromRational rate
        o = fromRational offset
        inner = [ ((fromIntegral k / r - o) / beats, fromRational (noiseKnot seed k))
                | beats > 0, k <- [floor (o * r) + 1 .. ceiling ((o + beats) * r) - 1 :: Integer] ]
    in A.Breaks ((0, valueAt 0 beats 0 sig) : inner ++ [(1, valueAt 0 beats 1 sig)])
  Start a -> A.Flat (valueAt stepsPerCent beats 0 a)

finite, positive :: Double -> Bool
finite x = not (isNaN x || isInfinite x)
positive x = finite x && x > 0

writeAudio :: FilePath -> Performance -> Score -> IO ()
writeAudio = writeAudioWith A.defaultDither

-- | 'writeAudio' with an explicit 16-bit dither ('A.NoDither' to truncate).
writeAudioWith :: A.Dither -> FilePath -> Performance -> Score -> IO ()
writeAudioWith dither path performance score = do
  timeline <- either (ioError . userError) pure (render performance score)
  A.writeTimelineMixWith dither path (mix performance) timeline
