# Recorded drums, high-gain guitar and the rest of the orchestra

**Status:** implemented 2026-11-06, with the design decided in the same sitting
(the owner asked for the three things to work, not for a proposal). This page
is the design note and the record of what was built and measured. It applies to
the code from the commit that adds it, the first after v0.2.0.0.

The Emberfall and Undertow notes named the two gaps: the kit was synthesized
presets, and there was no distortion ("the single biggest gap"). A third was
that VSCO 2 CE had only eleven maps (ten instruments and a combined string
section). This round closes all
three with three engine primitives and no new instrument system:

| Want | Primitive | Where |
|---|---|---|
| a drum plays as recorded, whatever the note | `pitch_keytrack=0` on a region | SFZ subset |
| a hit rings out, whatever the note's length | `loop_mode=one_shot` on a region | SFZ subset |
| a chord through one amplifier | `bus v` | voice algebra |

`drive` and `pitch KEY` (a drum's MIDI and staff key) were already in the
working tree from 2026-11-05 and are used as they were, with two changes noted
below.

## 1. Drums

A recorded kit needs nothing a recording did not already have, except two
things the sampler used to refuse or ignore.

- **A fixed region.** `pitch_keytrack=0` (0 and 100 are the values accepted)
  makes a region play at its recorded speed on every key. `tune` still applies,
  as a speed. The score's pitch signals still bend it, relative to the note.
  So a drum line's steps mean nothing, and a synthesized kick written at -27
  can be swapped for a recorded one without touching the line.
- **A one-shot.** `loop_mode=one_shot` was accepted before and treated as
  `no_loop`, so a crash written as a quarter note was cut after a quarter
  note. It now plays to the end of the recording. A note's tail is computed
  per note for this (`noteRinging`): what is left of the recording at the
  pitch the note plays it, longer if the pitch falls during the note.
- **A choke is a release.** A `gain` whose envelope releases still ends
  everything under it. So an open hi-hat is `gain (adsr 0.001 0 1 0.06)
  sampled "rock/hat-open.sfz"`, written as long as the hat stays open. No
  choke groups were added.
- **Microphones are regions.** Regions with the same key and velocity ranges
  all play, as before. A drum's map holds each microphone's recording of a hit
  at the library's default level, so one `sampled` is the mixed drum. Two
  channels remain the limit; overheads are stereo, close microphones mono.
- **One drum, one instrument,** as the synthesized kit already was, each with
  `pitch KEY` for MIDI and the staff.

Not done: per-microphone maps (to rebalance close and overhead in a score),
velocity crossfades within a layer (the library's own player scales each layer
by velocity; here layers switch, and the kick has fourteen), and the brush
stirs and mechanical noises.

**The kit: Big Rusty Drums** (Karoryfer Samples, CC0, 731 MB of FLAC): a 24"
kick, a 14" snare, four toms, a hi-hat and seven cymbals, up to fourteen
strengths and four takes of each hit. `examples/neomusic/rock/prepare.py`
decodes the 27 articulations mapped (1,428 files) and writes their maps from
the library's own velocity ranges. See `examples/neomusic/rock/README.md`.

## 2. High gain

`drive` was there, but a voice is one note. Three notes each driven and then
added are three clean-ish tones. A real amplifier distorts their sum, and the
difference tones between the notes are the sound of a power chord.

**`bus v`** is every note of the instrument playing `v`, summed. Shapers
outside it act on the sum:

```
sound di     = gain ((0.55 + 0.45 * velocity) * adsr 0.002 0 1 0.04) sampled "rock/guitar-direct.sfz"
sound rhythm = gain 0.12 lowpass (hz 5200) 0.2 lowpass (hz 3600) 0.35 highpass (hz 100)
               drive 40 highpass (hz 220) bus di
```

It is one constructor in the voice algebra (`Bus Voice`), not an effects
section: it says where the sum over notes happens. The rules follow from that.

- Outside a bus nothing can follow a note, so gains, filters, drive and pan
  there hold constants. A modulation that names velocity, the key or an
  envelope is an error.
- Every source is inside a bus, and a bus holds no other bus. `bend` and
  `unison` belong inside.
- `a + b` outside is allowed when both sides have a bus: two sums, each shaped.
- For shapers that are linear the bus changes nothing (a test holds a gain and
  two filters to 1e-9 against the per-note render while the notes sound).
  Only `drive` hears the difference.
- A bus belongs to an instrument. The engine's timeline has no instrument
  names, so notes share a bus when they have the same sound, gain, pan and
  send. Two guitars panned apart are two buses, which is two amplifiers.
- The instrument's `gain`, `pan` and `send` apply after the bus. How hard a
  note is played and its `level` curve apply before, so playing softer drives
  less, as it does on an amplifier.
- The bus runs to the end of the mix, so its filters ring out. A note's own
  filters still stop with the note (that was already so).

**The drive is antialiased.** A waveshaper makes harmonics without limit, and
those above half the sample rate fold back as tones that belong to no note. So
`drive` now outputs the curve's mean over each step of its input, from the
curve's antiderivative (`log (cosh (d x)) / (d tanh d)`), for half a sample of
delay. Measured on a 2,794 Hz sine at `drive 30`, 44.1 kHz:

| Harmonic | Folds to | Level against the fundamental | A plain waveshaper (computed, not measured) |
|---|---|---|---|
| 9 | 18,956 Hz | -24.7 dB | -19.1 dB |
| 11 | 13,368 Hz | -30.0 dB | -20.8 dB |
| 13 | 7,780 Hz | -37.1 dB | -22.3 dB |
| 15 | 2,193 Hz | -51.6 dB | -23.5 dB |
| 17 | 3,395 Hz | -47.6 dB | -24.6 dB |

The folds that land where a guitar is heard are 15 to 28 dB lower. Those near
the top of the band are reduced less, and a cabinet's low-pass removes them.

**The guitar: FreePats Electric Guitar FSBS (direct)** (CC0, 77 MB): a Fender
recorded straight into an instrument input, 19 pitches, two strengths in the
lower range and four takes of each, keys 33 to 86 (the library's map stops at
35; its lowest recording is played two semitones further down). It is a raw signal and is
meant for an amplifier. The amplifier here is a high-pass, the drive, and a
high-pass and two low-passes for the cabinet.

Not done: a recorded cabinet (a convolution inside a voice), palm mutes (the
library has none; the example uses short notes), and a recorded bass guitar
(the example keeps the synthesized `reeseBass`).

## 3. The rest of the orchestra

`examples/neomusic/vsco/make-sfz.py` now maps the whole library: 100 maps
where there were 11, naming 2,358 recordings where there were 290.

- **Strings:** spiccato and tremolo for every section, the remaining
  pizzicatos, the solo bass without vibrato, and the solo violin (bowed,
  plucked, spiccato, tremolo).
- **Woodwinds:** piccolo, oboe, clarinet and bassoon, sustained and staccato
  (and with vibrato where recorded), and the flute's other articulations.
- **Brass:** trumpet (five articulations), tenor trombone, an older trombone,
  tuba, and the horn's staccato and stopped notes.
- **Keys and tuned percussion:** two uprights, the organ (loud and quiet,
  manual and pedal), glockenspiel, marimba, xylophone, tubular bells, and
  timpani rolls.
- **Unpitched percussion,** 35 maps, each fixed and one-shot: bass drum,
  concert snare, cymbals, suspended cymbal, gong, tambourine, triangles,
  congas, cowbell, claves, anvil and others.

Pitched maps follow the key and stop with the note, as the earlier ones do,
so give them a release.

**Pitches were measured again.** Every pitched recording was measured (2,200
files, by the McLeod method on half a second after the attack) and compared with
its name.

- Every folder names notes an octave low, as the earlier ones did, except
  four that name them as they sound: the harp (known), the solo violin's bowed
  and plucked notes, the first upright, and the tubular bells.
- The clarinet's "F#5" sustain sounds an F, at all three strengths. The map
  places it there.
- The organ's files are numbered, not named. Its keys were measured: the loud
  manual's file n is key 35 + n, its pedal 23 + n; the quiet manual n - 86,
  its pedal n - 28. The detector reads an octave low on some loud pipes (they
  speak with octave ranks); the series is unbroken either way.
- The second upright's numbers follow its own `MappingChart.txt`.
- Bars and bells defeat a pitch detector, so those were read from spectra.
  The glockenspiel's bars sound an octave above their names, 11 to 26 cents
  sharp. Each tubular bell's fourth, fifth and sixth partials stand 2:3:4, and
  the strike note an octave under the fourth is the name.

Then each pitched map was played through the engine at five keys across its
range and the result measured: 320 notes. Of these, 284 read within 30 cents
of the key asked for (214 within 5 cents, 248 within 10). Eleven read exactly
an octave off, on low plucked and tremolo strings, loud organ pipes and a
timpano, where the detector takes a partial for the note. The other 25 are in
eight maps a pitch detector cannot read: bells and bars (above), timpani
(tuned from spectra in October), the highest plucked notes of the solo violin
and bass, and the second upright's lowest and highest keys.

Not mapped: the trombone's buzzes and falls, the guiro's scrapes, the
suspended cymbal's bowed and swelling strokes, the gong scrapes, and the
"alien", "zap" and rub effects.

## 4. What changed in the engine

- `Recording.hs`: `Region` gains `regionFixed` and `regionOneShot`;
  `pitch_keytrack` joins the subset.
- `Audio.hs`: `Bus`; `noteRinging` and `noteTail` beside `ringing` and
  `voiceTail`; `renderBus` and `busGroups`; an input node; `driveStep`.
  `compileVoice` takes what to build at a `Bus`.
- `Language.hs`: the word `bus`.
- From the 2026-11-05 tree: the sheet test expected a rest that the engraver
  does not write between two drums in one voice (the suite failed on it), an
  unused import and a shadowed name. All three are fixed.

**Unchanged output.** Every example was rendered in every view before and
after the engine changes (181 files: WAV, MIDI, LilyPond, numeric sheet) and
compared byte for byte. All are identical. `cabal test` passes (69
properties), as do the three Python suites.

## 5. Three scores

- `examples/neomusic/rock-kit.neomusic`: eight bars on the kit alone, with
  ghost notes, a choked open hi-hat and a fill around four toms.
- `examples/neomusic/high-gain.neomusic`: eighteen bars, two rhythm guitars
  left and right (the takes rotate and each side is humanized with its own
  seed), a lead, and the kit. It renders in 12 s.
- `examples/neomusic/orchestra-tutti.neomusic`: a twelve-bar chorale for the
  new instruments, woodwinds, then brass, then everyone with the percussion.

Their balances were set by measuring each part's level alone, not by ear. In
the high-gain piece the two guitars, the lead, the bass and the whole kit
each sit within 4 dB of one another in mean level. The owner has since
listened (same day): first to `rock-kit` and `orchestra-tutti`, found
acceptable, and then to the rest, accepting the quality and the synthesis.
That covers the recorded kit, the amplifier (`bus`, `drive` and the cabinet
filters) as heard in `high-gain` and Emberfall, and the orchestra maps.

## 6. Open

- Nothing is waiting on a listening verdict: the owner accepted the quality
  and the synthesis on 2026-11-06 (section 5).
- Done the same day, at the owner's request: Emberfall plays the recorded
  guitars and kit, and Undertow the recorded kit. Each piece's page has a
  dated section with the levels before and after. The guitar map reaches A1
  for Emberfall's riff (the library stops at B1).
- A recorded cabinet, a bass guitar (Karoryfer's are CC0), a brushed kit
  (Swirly Drums, CC0) and a choir remain as candidates.
- The takes counter is shared by every note at a pitch, across instruments.
  It was so before; a kit makes it more visible.

## Credits

- **Big Rusty Drums:** Karoryfer Samples, CC0 1.0, from
  [sfzinstruments/karoryfer.big-rusty-drums](https://github.com/sfzinstruments/karoryfer.big-rusty-drums).
- **Electric Guitar FSBS (direct):** the FreePats project, CC0 1.0, from
  [freepats/electric-guitar-FSBS-direct](https://github.com/freepats/electric-guitar-FSBS-direct).
- **VSCO 2 Community Edition:** Versilian Studios, CC0 1.0. Its organ and
  second upright were sampled by Simon Dalzell of Ivy Audio.
