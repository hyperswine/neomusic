# Recorded piano and guitars

A baseline integration of Salamander Grand Piano V3 and Meta Open Sound's
nylon- and steel-string guitars. These are additional sound choices; existing
scores keep their existing sounds. The score language and sampler are unchanged.

## Prepare the recordings

Requirements: Python 3, FFmpeg, about 1.8 GB of downloads, and several GB of free
space for the archives and decoded recordings. From the repository root:

```sh
python3 examples/neomusic/acoustic/prepare.py \
  --samples "$HOME/Documents/GitHub/neomusic-samples" --fetch
export NEOMUSIC_SAMPLES="$HOME/Documents/GitHub/neomusic-samples"
cabal run neo-music -- play examples/neomusic/acoustic-trio.neomusic -o trio.wav
```

The script checks every archive against `sources.json` before reading it. It
uses the pinned Salamander commit and the two pinned Meta WAV releases. Each
instrument gets an `upstream/` directory with its source license and documents,
and a `prepared.json` with source information and SHA-256 fingerprints of every
prepared WAV. Large files live under `NEOMUSIC_SAMPLES/neo-acoustic/`, outside
Git. Only the maps, script and source lock belong in this repository.

For a previously downloaded archive cache, pass `--archive-dir /path/to/cache`.
Without `--fetch`, a missing archive is an error and no network is used.
Salamander FLAC is decoded to 24-bit PCM WAV at its original rate and channel
count; the audio is not normalized, retuned or trimmed. Meta WAVs are copied
unchanged. Generated SFZ files are deterministic and can be regenerated with
`--output /path/to/maps`.

## Sound choices

| Map | Written MIDI range | Selection |
|---|---|---|
| `salamander.sfz` | 21–108 (A0–C8) | 30 recorded roots, 16 attack layers; upstream natural tuning and key/velocity zones |
| `meta-nylon.sfz` | 40–83 (E2–B5) | Finger at velocity 1–42, light pick at 43–85, firm pick at 86–127 |
| `meta-nylon-finger.sfz` | 40–83 | Fingerstyle at every velocity; use voice gain for dynamics |
| `meta-nylon-pick.sfz` | 40–83 | Light pick at 1–64, firm pick at 65–127 |
| `meta-steel.sfz` | 40–84 (E2–C6) | Layers at 1–48, 49–96 and 97–127 |

Guitar maps select the string with the highest open pitch no higher than the
requested note: Low E for 40–44, A for 45–49, D for 50–54, G for 55–58, B for
59–63, High E above that. Thus every playable pitch/velocity selects exactly
one recording, without summing overlapping string recordings. All mapped
guitar pitches were recorded chromatically; normal integer notes do not need
transposition. The complete guitar archives are retained in prepared form for
future explicit string selection.

Example sound definition, in a score beside the `acoustic/` directory:

```text
sound grand = gain ((0.6 + 0.4 * velocity) * adsr 0.001 0 1 0.4) sampled "acoustic/salamander.sfz"
instrument piano = grand
```

The example envelope preserves the recorded attack and decay, then applies a
simple release at note-off. Guitar examples use a longer release. Velocity
selects the source layer and also controls a modest gain adjustment.

## Deliberate baseline differences from the supplied players

These maps are explicit adaptations, not imports that discard unknown SFZ
opcodes. NeoMusic's parser remains strict.

- **Piano:** attack samples only. No hammer/release triggers, pedal noises,
  sympathetic resonance, pedal controls, optional onset offsets, retuning
  switch, or special long releases for undamped high notes. The voice supplies
  one release envelope. `pedal` in a score extends gates; it does not reproduce
  the piano library's pedal/resonance system.
- **Guitars:** no channel-selected strings, keyswitches, same-string choking,
  automatic six-note limit, or randomized pitch/amplitude. Repeated notes use
  the same recording. Humanization can be applied explicitly in the score.
- **Nylon:** auto/pick modes switch layers instead of crossfading. Technique can
  be held constant with the finger or pick map. The upstream recommendation
  to let notes ring as one-shots is approximated by score gates and an explicit
  release; notes may be damped at note-off. There are no artificial sustain loops.
- **Steel:** upstream per-layer velocity curves are replaced by the example's
  simple voice gain. The samples themselves are unmodified.

These differences are audible, particularly on repeated notes, pedal piano
and guitar overlaps. The baseline is intended for auditioning the recordings,
not a claim of complete piano or guitar performance modeling.

## Sources and credits

- **Salamander Grand Piano V3:** recordings by **Alexander Holm**, Yamaha C5,
  licensed **CC BY 3.0 Unported**. Source distribution and key/velocity mapping:
  [sfzinstruments/SalamanderGrandPiano](https://github.com/sfzinstruments/SalamanderGrandPiano),
  SFZ reconstruction by **kinwie**; retuned-version work credited upstream to
  **Markus Fiedler**. This adaptation uses the natural-tuning samples and derives
  its key/velocity zones from that mapping. Changes: FLAC decoded to WAV; a
  smaller SFZ mapping and NeoMusic voice envelope replace the advanced player
  controls. Preserve this attribution when distributing the adaptation or music
  made from these samples, and retain the upstream license with the assets.
  Short form: Salamander Grand Piano V3 by Alexander Holm, licensed CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/), via sfzinstruments/SalamanderGrandPiano; samples decoded to WAV and remapped.
- **Meta nylon and steel guitars:** Meta Creative Audio team,
  [Meta Open Sound](https://github.com/facebookincubator/Meta-open-sound),
  **CC0 1.0** instrument recordings. The first-position string layout and velocity
  choices follow its published guidance, with the simplifications above.

## Checks and examples

```sh
python3 examples/neomusic/acoustic/test_prepare.py
cabal test --offline --write-ghc-environment-files=never --test-show-details=direct
```

The offline Python tests check every supported key/velocity pair for unique
coverage, string boundaries, technique separation, piano layers, deterministic
mapping output and rejection of corrupt archives. They need no audio assets.

The scores `piano-recorded.neomusic`, `guitar-nylon-recorded.neomusic`,
`guitar-steel-recorded.neomusic` and `acoustic-trio.neomusic` exercise attacks,
dynamics, repeated notes, chords and releases. They apply `humanize` with one
seed per part (see the [audition note](../../../docs/2026-10-29-NEOMUSIC-AUDITION.md)):
repeated notes then select different recordings on the piano and steel maps,
and on the nylon auto map the written velocities keep variation inside one
technique band. Automated render evidence and
remaining listening work are recorded in the dated integration note in `docs/`.

For a longer arrangement, try [Last Train, Blue Hour](../last-train-blue-hour.neomusic)
and its [MP3 audition](../audio/last-train-blue-hour.mp3): 72 bars of piano melody,
fingerstyle nylon, syncopated steel and a guitar-led bridge.
