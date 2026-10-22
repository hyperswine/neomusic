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

## Build and run

The project builds with cabal (GHC 9.8.2, which ghcup installs):
`cabal.project` pins the compiler and `cabal.project.freeze` every
dependency's version.

```bash
cabal build all
cabal test
cabal run neo-music -- check examples/neomusic/twinkle.neomusic
```

`cabal repl neomusic` loads the library in GHCi. Audio export needs FFmpeg
on the path; sheet music needs LilyPond.

## Layout

| path | what it is |
|---|---|
| `src/NeoMusic/` | the library: `Score`, `Signal`, `Language`, `Audio`, `Recording`, `Midi`, `Numeric`, `Sheet`, and the prelude |
| `app/neo-music` | the command-line renderer for `.neomusic` files |
| `app/screw-bgm`, `app/screw-anime`, `app/terra-bgm` | scores written against the library directly |
| `examples/neomusic/` | example scores, SFZ instrument maps for the VSCO 2 CE samples, and room impulse tooling |
| `test/` | Hedgehog properties and LilyPond golden files |
| `docs/` | the dated design record |

Recorded instruments and rooms are not in this repository: the SFZ maps
expect the VSCO 2 Community Edition samples (see
[the samples note](docs/2026-10-14-NEOMUSIC-SAMPLES.md) and
`examples/neomusic/vsco/make-sfz.py`).

## History

NeoMusic was split out of [HaskPlayground](https://github.com/hyperswine/HaskPlayground)
on 2026-10-21 with its history.
