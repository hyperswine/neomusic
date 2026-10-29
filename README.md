# NeoMusic

Algebraic music notation in Haskell. A `.neomusic` score is a small set of
uninterpreted primitives (pitch, duration, gate, signals over a note) plus
ordinary functions over them; bar lines, letter names and numeric notation
are views, not semantics. Scores render to WAV, MP3 or FLAC audio, to MIDI,
and optionally to LilyPond piano sheets.

Start with [the language and score guide](docs/2026-09-22-NEOMUSIC-LANGUAGE.md).
The [composition update](docs/2026-10-21-NEOMUSIC-COMPOSITION.md) records the
current strength/expression, conductor and pitch-identity contracts and migration.
The design notes, oldest first, are indexed in [docs/README.md](docs/README.md).

## Install with Homebrew

```sh
brew tap hyperswine/neomusic && brew trust hyperswine/neomusic
brew install neo-music
```

The [tap](https://github.com/hyperswine/homebrew-neomusic) builds the latest
release from source with `ghc@9.8` and `cabal-install`; no bottles are
published, so it takes a few minutes. It depends on `ffmpeg`. Use `--HEAD` for
`main`. The recorded-sample libraries are separate; see below.

## Build and run

The project builds with cabal 3.10+ and GHC 9.8 (tested with 9.8.2 and
9.8.4; install one with `ghcup install ghc 9.8.4`). `cabal.project` pins
the Hackage `index-state`, so dependency resolution is reproducible without
pinning an exact compiler. With several GHCs installed, pick one with
`cabal build all -w ghc-9.8.4`.

```bash
cabal build all
cabal test
cabal run neo-music -- check examples/neomusic/twinkle.neomusic
cabal run neo-music -- play examples/neomusic/twinkle.neomusic    # listen now
cabal run neo-music -- render examples/neomusic/twinkle.neomusic -o twinkle.flac
```

`cabal repl neomusic` loads the library in GHCi. Audio export needs FFmpeg
on the path; sheet music needs LilyPond.

## Layout

| path | what it is |
|---|---|
| `src/NeoMusic/` | the library: `Score`, `Signal`, `Language`, `Audio`, `Recording`, `Midi`, `Numeric`, `Sheet`, and the prelude |
| `app/neo-music` | the command-line renderer for `.neomusic` files |
| `pieces/` | personal pieces written against the library directly (`screw-bgm`, `screw-anime`, `terra-bgm`), a separate package not built by default: `cabal build all --project-file=cabal.project.pieces` |
| `examples/neomusic/` | example scores, SFZ instrument maps for VSCO 2 CE, Salamander and Meta guitars, and room impulse tooling |
| `test/` | Hedgehog properties and LilyPond golden files |
| `docs/` | the dated design record |

Recorded instruments and rooms are kept outside this repository. One script
fetches everything the example scores use and checks each download and file
against the SHA-256 values in `examples/neomusic/samples.lock.json`
(Python 3 standard library; the acoustic step also needs FFmpeg):

```sh
python3 scripts/fetch-samples.py --samples ~/neomusic-samples --fetch   # ~4 GB download
export NEOMUSIC_SAMPLES=~/neomusic-samples
cabal run neo-music -- check examples/neomusic/orchestral-recorded.neomusic
```

`--only vsco|rooms|acoustic` fetches one library: VSCO 2 Community Edition
(CC0; only the 290 files the maps use are extracted), the OpenAIR Jack Lyons
Concert Hall impulse response (CC BY 4.0, made stereo by
`examples/neomusic/rooms/make-room.py`), and Salamander piano plus Meta guitars
(via the [acoustic setup guide](examples/neomusic/acoustic/README.md)'s
`prepare.py`). `--archive-dir` keeps downloads in a reusable cache. A score that
names a missing recording fails with a message pointing here. Offline tests:
`python3 scripts/test_fetch_samples.py`. See also
[the samples note](docs/2026-10-14-NEOMUSIC-SAMPLES.md) and
`examples/neomusic/vsco/make-sfz.py`.

Listen to [Last Train, Blue Hour](examples/neomusic/audio/last-train-blue-hour.mp3),
a 2:40 J-pop/jazz piece for Salamander piano and both guitars. Its
[score and arrangement notes](docs/2026-10-27-LAST-TRAIN-BLUE-HOUR.md) describe the form and rendering.
Piano: Salamander Grand Piano V3 by Alexander Holm, licensed CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/), via sfzinstruments/SalamanderGrandPiano; samples decoded to WAV and remapped. Guitars: Meta Open Sound (CC0).
For a heavier wall, [Emberfall](examples/neomusic/audio/emberfall.mp3) is a
one-minute metal-orchestral piece for VSCO 2 CE, synthesized guitars and kit;
[its note](docs/2026-10-29-EMBERFALL.md) records what writing it surfaced.

## History

NeoMusic was split out of [HaskPlayground](https://github.com/hyperswine/HaskPlayground)
on 2026-10-21 with its history.
