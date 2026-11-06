# A recorded kit and a direct guitar

Big Rusty Drums (Karoryfer Samples) and FreePats' Electric Guitar FSBS
(direct), both CC0. These are additional sound choices; existing scores keep
their sounds. The design is in
[the dated note](../../../docs/2026-11-06-NEOMUSIC-DRUMS-DRIVE-ORCHESTRA.md).

## Prepare the recordings

Requirements: Python 3, FFmpeg, bsdtar or 7z (for the guitar's `.7z`), about
0.7 GB of downloads and 1.3 GB for the decoded recordings. From the repository
root:

```sh
python3 examples/neomusic/rock/prepare.py --samples "$HOME/neomusic-samples" --fetch
export NEOMUSIC_SAMPLES="$HOME/neomusic-samples"
cabal run neo-music -- play examples/neomusic/rock-kit.neomusic -o kit.wav
```

`scripts/fetch-samples.py --only rock` does the same. The script checks each
archive against `sources.json`, decodes FLAC to WAV at its own depth and rate
(nothing is normalized, retuned or trimmed), keeps each library's license
under `upstream/`, and writes `prepared.json` with a SHA-256 fingerprint of
every decoded file. Recordings live under `NEOMUSIC_SAMPLES/big-rusty-drums/`
and `NEOMUSIC_SAMPLES/freepats-eguitar/`, outside Git; only the maps, the
script and the source lock belong here. Without `--fetch`, a missing archive
is an error and no network is used. Pass `--only big-rusty-drums` or `--only
freepats-eguitar` for one library.

## The kit

Each map is one drum. It plays as recorded on every key (`pitch_keytrack=0`)
and to the end of the recording (`loop_mode=one_shot`), so a drum line's steps
and lengths only say when. Velocity chooses among the recorded strengths (the
kick has 14, the snare and ride 10, the others 4 to 8); repeats rotate through
four takes. Every
microphone's recording of a hit plays together, at the library's default
levels: a snare is mostly its bottom microphone, a cymbal mostly the
overheads. Overheads are stereo and carry the kit's own left and right.

| Map | Drum | A General MIDI key for `pitch` |
|---|---|---|
| `kick.sfz`, `kick-open.sfz` | 24" kick, damped and undamped | 36, 35 |
| `snare.sfz`, `snare-edge.sfz`, `snare-rimshot.sfz`, `snare-brush.sfz` | 14" snare | 38, 38, 40, 38 |
| `sidestick.sfz` | stick across the rim | 37 |
| `hat-tight.sfz`, `hat-closed.sfz`, `hat-loose.sfz` | 14" hi-hat, closed three ways | 42 |
| `hat-quarter.sfz`, `hat-half.sfz`, `hat-open.sfz` | hi-hat, opening | 46 |
| `hat-pedal.sfz`, `hat-splash.sfz` | hi-hat by foot | 44, 46 |
| `tom-14.sfz`, `tom-15.sfz`, `tom-18.sfz`, `tom-22.sfz` | toms, high to low | 50, 47, 43, 41 |
| `ride.sfz`, `ride-bell.sfz`, `ride-edge.sfz` | 22" ride | 51, 53, 59 |
| `crash.sfz`, `china.sfz` | 17" crash, 18" china | 49, 52 |
| `sizzle-crash.sfz`, `sizzle-ride.sfz`, `stack.sfz` | cymbals with rivets, and a stack | 57, 59, 55 |

```text
sound kickS = sampled "rock/kick.sfz"
sound openS = gain (adsr 0.001 0 1 0.06) sampled "rock/hat-open.sfz"
instrument kick = kickS pitch 36
instrument ohat = openS gain 0.6 pitch 46
```

A release above a one-shot ends it with the note, so `openS` is an open
hi-hat that closes when its note ends: write it as long as it stays open.

## The guitar

`guitar-direct.sfz` covers keys 35 to 86 (B1 to D6) from 19 recorded pitches,
with a softer layer below velocity 93 in the lower range and four takes of
each. It follows the key and stops with the note. It is a raw instrument
signal: play it through a drive on a bus, so a chord's notes are driven
together, and filters for the cabinet.

```text
sound di     = gain ((0.55 + 0.45 * velocity) * adsr 0.002 0 1 0.04) sampled "rock/guitar-direct.sfz"
sound rhythm = gain 0.12 lowpass (hz 5200) 0.2 lowpass (hz 3600) 0.35 highpass (hz 100)
               drive 40 highpass (hz 220) bus di
instrument gtrL = rhythm pan -0.8
instrument gtrR = rhythm pan 0.8
```

Two instruments are two buses. Playing the same part on both gives two
players, since the takes rotate; `humanize` each with its own seed.

## Differences from the libraries' own players

- **Kit:** no per-microphone faders, tuning, deadening or "punch" controls,
  and no brush stirs or mechanical noises. Velocity switches layers; the
  library's player also scales each layer by velocity. There are no choke
  groups: an envelope on the voice chokes (above).
- **Guitar:** the upstream map picks a take at random; here takes rotate. Its
  0.2 s release is left to the voice.

## Sources and credits

- **Big Rusty Drums:** Karoryfer Samples, **CC0 1.0**,
  [sfzinstruments/karoryfer.big-rusty-drums](https://github.com/sfzinstruments/karoryfer.big-rusty-drums)
  at revision `f07ce00`. Velocity ranges and microphone levels are the
  library's own (its mappings and its Full kit program).
- **Electric Guitar FSBS (direct):** the FreePats project, **CC0 1.0**,
  [freepats/electric-guitar-FSBS-direct](https://github.com/freepats/electric-guitar-FSBS-direct),
  release 2022-09-11. Keys, layers and takes follow its map.

## Checks and examples

```sh
python3 examples/neomusic/rock/test_prepare.py
```

The offline tests check that every drum's microphones agree, that its layers
cover every velocity once and its takes are complete, and that the guitar
covers its range. They need no recordings. `rock-kit.neomusic` is the kit
alone; `high-gain.neomusic` is two guitars, a lead and the kit.
