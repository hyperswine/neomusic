# Last Train, Blue Hour

Kind: composition and audition record, 2026-10-27. An original 72-bar acoustic
piece for Salamander Grand Piano and Meta nylon- and steel-string guitars,
using the [first recorded-instrument integration](2026-10-27-NEOMUSIC-ACOUSTIC-INSTRUMENTS.md).

[Listen to the MP3](../examples/neomusic/audio/last-train-blue-hour.mp3) ·
[Read the score](../examples/neomusic/last-train-blue-hour.neomusic)

## Musical intent

A nostalgic J-pop melody with jazz harmony: 112 BPM, C major and A minor,
major/minor ninths, secondary dominants and a borrowed F minor chord. The
chorus starts with F–G–Em–Am, then uses a ii–V turnaround. This is an original
composition, with no melody borrowed from an existing song.

The piano takes the melody and lower accompaniment as two score parts sharing
one recorded instrument. Fingerstyle nylon plays flowing eighth-note patterns
on the left; steel plays offbeat, lightly staggered chords on the right. The
bridge passes the melody from nylon to steel. A higher final chorus gives way
to a quieter ending with a gradual ritardando. Only these three sampled
instruments are used, with a light shared algorithmic room.

| Bars | Section | Approximate start |
|---|---|---|
| 1–4 | Introduction | 0:00 |
| 5–20 | Two verses | 0:09 |
| 21–28 | Pre-chorus | 0:43 |
| 29–44 | Chorus | 1:00 |
| 45–52 | Guitar bridge | 1:34 |
| 53–68 | Final chorus | 1:52 |
| 69–72 | Outro | 2:26 |

The score contains 288 written beats and 2,069 notes, about 157 seconds of
performed music. The export is about **2:40**, including releases and the room
tail. Humanization uses fixed seeds, so the performance is repeatable.

## Reproduce and inspect

Prepare the recordings using the
[acoustic setup guide](../examples/neomusic/acoustic/README.md), then:

```sh
export NEOMUSIC_SAMPLES="$HOME/Documents/GitHub/neomusic-samples"
cabal run neo-music -- check examples/neomusic/last-train-blue-hour.neomusic
cabal run neo-music -- play examples/neomusic/last-train-blue-hour.neomusic -o blue-hour.wav
cabal run neo-music -- play examples/neomusic/last-train-blue-hour.neomusic -o blue-hour.mp3
cabal run neo-music -- sheet examples/neomusic/last-train-blue-hour.neomusic -o blue-hour.html
```

The committed MP3 is encoded from the native 44.1 kHz stereo PCM24 WAV using
FFmpeg's LAME encoder at VBR quality 2, with no added compression, limiting or
loudness normalization. The score's master peak is 0.86. Its melodic contour,
chord voicings, arpeggio/strum functions and section form remain visible in the
numeric source; no changes to the Haskell engine or language were needed.

Local WAV, numeric HTML/text and technical measurements are kept in ignored
`output/last-train-blue-hour/`. Large library recordings remain in the external
sample directory. The small MP3 audition is versioned with the source.

## Local checks

- All four score parts end at exactly 288 beats; every pitch fits the selected
  instrument's mapped range. The common conductor owns the tempo changes.
- Repeated final WAV renders are byte-identical. Independent FFmpeg decoding
  verifies finite samples, no clipping and no empty one-second musical spans.
- WAV and MP3 are 44.1 kHz stereo and 160.400 seconds long. Decoded peaks are
  approximately 0.860 and 0.837, respectively. The WAV uses 24-bit PCM.
- A dry chorus excerpt measures the accompaniment parts within about 1 dB of
  one another in RMS, with the piano melody about 5 dB above them. This guides
  the balance but does not replace listening.
- All 50 existing Haskell property groups and five offline acoustic mapping
  tests pass. Numeric HTML and text exports also succeed.

## Credits

Composition and arrangement: generated for this NeoMusic project at the user's
request. Piano recordings: **Salamander Grand Piano V3 by Alexander Holm**,
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/), with SFZ reconstruction
by **kinwie**, from
[sfzinstruments/SalamanderGrandPiano](https://github.com/sfzinstruments/SalamanderGrandPiano).
Natural-tuning attacks were decoded from FLAC to WAV and used with adapted
mappings and voice envelopes. Guitars: **Meta Creative Audio team**, CC0,
[Meta Open Sound](https://github.com/facebookincubator/Meta-open-sound).
See the setup guide and source lock for pinned versions and full adaptation
notes. The MP3 metadata also retains these credits.

This audition uses the baseline sampler behavior: no piano sympathetic
resonance or sampled pedal/release system, and no guitar same-string choking
or round robin. The balance was checked numerically; aesthetic and realism
judgments are left to listening.
