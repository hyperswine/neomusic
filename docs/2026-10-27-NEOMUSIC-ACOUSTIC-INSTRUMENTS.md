# Recorded piano and guitars: first integration

Kind: implementation and local validation record, 2026-10-27. Applies to the
first acoustic-library integration on `tempo-hoisting`, based on `620f6d2`.
This implements the first milestone in the
[recordings intent](2026-10-24-NEOMUSIC-PIANO-AND-GUITARS.md): all three selected
instruments now render through NeoMusic. Listening judgments remain pending.

## What works

The integration uses the existing `Sampled` source and ordinary voice operations.
There are no Haskell engine or score-language changes. Five small SFZ maps,
a preparation script, pinned source/checksum metadata, and four example scores
live in [examples/neomusic/acoustic](../examples/neomusic/acoustic/README.md).
The sampler still rejects unsupported SFZ opcodes; these maps explicitly adapt
the original instruments to its supported subset.

| Instrument | Prepared recordings | Mapping |
|---|---:|---|
| Salamander Grand Piano V3 | 480 WAVs | 30 roots, 16 velocity layers, MIDI 21–108 |
| Meta nylon guitar | 348 WAVs | MIDI 40–83; automatic, finger-only and pick-only maps |
| Meta steel guitar | 375 WAVs | MIDI 40–84; three velocity layers |

Salamander is pinned to `3382bf9496bba2486f5ab0de55a264d1dfc38404`;
the Meta WAV archives are their respective `v1.0.0` releases. Exact download
URLs, SHA-256 checksums and credits are in
[sources.json](../examples/neomusic/acoustic/sources.json).
Salamander's FLAC attacks are decoded to PCM24 WAV without normalization,
retuning or trimming; Meta WAVs are copied unchanged. Prepared assets retain
upstream licenses/documents and per-file SHA-256 manifests.

The local installation is under
`/Users/jasonqin/Documents/GitHub/neomusic-samples/neo-acoustic/`, with the
verified archives cached in its `downloads/` directory. Recordings stay outside
Git. Another machine can reproduce the setup with:

```sh
python3 examples/neomusic/acoustic/prepare.py \
  --samples "$HOME/Documents/GitHub/neomusic-samples" --fetch
export NEOMUSIC_SAMPLES="$HOME/Documents/GitHub/neomusic-samples"
cabal run neo-music -- play examples/neomusic/acoustic-trio.neomusic -o trio.wav
cabal run neo-music -- play examples/neomusic/acoustic-trio.neomusic -o trio.mp3
cabal run neo-music -- sheet examples/neomusic/acoustic-trio.neomusic -o trio.html
```

Omit `--fetch` to prepare entirely offline from the cached archives. See the
[setup guide](../examples/neomusic/acoustic/README.md) for mapping details,
requirements and attribution.

## Local validation

- All executables build; the existing Cabal suite passes all 10 audio and
  40 score/view property groups.
- Five offline Python tests pass, covering complete unique key/velocity
  coverage, string boundaries, technique separation, piano layers,
  deterministic maps and rejection of missing/corrupt archives.
- The documented preparation command succeeds end to end with no network,
  using the cached archives. All five regenerated maps match the checked-in
  versions byte for byte. A Cabal source distribution includes the setup files,
  maps and four scores.
- NeoMusic's actual `readSampleSet` and `chooseRegions` load all five maps and
  select exactly one nonempty 48 kHz recording for every supported integer
  MIDI key and velocity 1–127.
- Solo piano, nylon guitar, steel guitar and trio scores each pass `check`,
  render to WAV and MP3, and produce numeric text and HTML views. Two WAV
  renders of each score have identical SHA-256 hashes. FFmpeg independently
  decodes the WAVs: samples are finite, nonzero, and peak at approximately 0.8.
  FFprobe confirms 44.1 kHz stereo MP3 output.
- Autocorrelation spot-checks of one A4 recording per instrument give about
  441.5 Hz (piano), 436.3 Hz (nylon) and 440.7 Hz (steel). These are coarse
  checks against mapping/octave mistakes, not full-library tuning certification.

Local audition files and measurements are in ignored
`output/acoustic-instruments/`, including `validation.json`:

| Example | Notes | MP3 duration including release/tail |
|---|---:|---:|
| `piano-recorded` | 17 | 6.80 s |
| `guitar-nylon-recorded` | 20 | 7.10 s |
| `guitar-steel-recorded` | 20 | 7.10 s |
| `acoustic-trio` | 36 | 9.50 s |

`piano-recorded-matched` and `piano-synthetic-reference-matched` provide the
same piano score and strengths through the new and existing piano voices.
Only constant gain was applied to the comparison WAVs; measured integrated
loudness is −20.00 and −19.99 LUFS, respectively. MP3 copies are also available.
The voices have different release behavior, so their total durations differ.
No subjective listening result or claim of improved realism is recorded yet.
These are local checks, not hosted CI evidence.

## Limits and next steps

This is an attack-sample baseline. Piano pedal/release triggers, hammer noise,
sympathetic resonance and the upstream advanced controls are not implemented.
Natural tuning is retained. Guitar maps choose a fixed string for each pitch;
there is no string selection, same-string choking, round robin or automatic
six-note limit. Nylon techniques switch rather than crossfade. Explicit voice
envelopes govern note-off and approximate the libraries' release behavior.
All differences are detailed in the setup guide.

Next, audition the individual examples and trio, especially repeated notes,
short releases, nylon technique changes and overlapping guitar notes. Adjust
voice definitions based on those results. Any later string or pedal behavior
should have an explicit performance contract and remain separate from the
numeric score notation.
