# Emberfall: a metal-orchestral minute

Kind: original composition and capability probe, 2026-10-29. A one-minute
piece in the vein of Bury the Light (Casey Edwards): heavy-metal drive with an
orchestral wall, written the day the [audition pass](2026-10-29-NEOMUSIC-AUDITION.md)
humanized the recorded instruments and the tempo-hoisting merge landed, to see
where the system stands. Score: [examples/neomusic/emberfall.neomusic](../examples/neomusic/emberfall.neomusic);
listen: [MP3](../examples/neomusic/audio/emberfall.mp3). Needs VSCO 2 CE, the
Meta steel guitar and the Jack Lyons room under `NEOMUSIC_SAMPLES`.

## The music

D minor, 168 bpm, 40 bars (160 written beats, 64.5 s rendered with the
ritard and the hall tail). The form:

| Bars | Section | What happens |
|---|---|---|
| 1-4 | intro | clean steel guitar arpeggios alone in the hall, strings and a timpani roll entering |
| 5-12 | drop | synth-chug sixteenths on D, kit, timpani slams, staccato violin ostinato |
| 13-20 | verse | gallop riff on Dm-Bb-C-A, violins carrying the riff |
| 21-28 | chorus | the melody over Dm-Bb-F-C / Dm-Bb-Gm-A: horns low, power chords, backbeat |
| 29-32 | bridge | neo-classical harp and violin runs down and up, drums building, an accel |
| 33-40 | final | the chorus again with double kick, ritard and a held Dm into the room |

Measured section levels (RMS): intro -33.6 dB, drop -19.1, verse -18.6,
chorus -16.6, bridge -17.9 (building), final -15.9, tail -19.8; peak -3.25
dBFS under the 0.8 limit. The arc reads on the meter the way it is meant to
read to an ear.

## How it uses the recent work

- **Tempo hoisting, no conductor.** All tempo lives in parts: `accel 1.05`
  rides the chug's last gallop into the final chorus, and the ending's
  `rit 0.8 [hold 2 [...]]` is written in the lead's own last bar. The one-clock
  rule bit exactly as designed during drafting: holding the final chord in
  six parts at once was rejected ("both set the tempo over the same beats"),
  so the fermata is written once, in the lead, and everyone else's final notes
  stretch with the slowing clock.
- **The auditioned steel guitar** is the intro's clean voice, humanized.
- **Humanize on players, not on machines:** guitar, harp, violins, timpani and
  the singing lead get seeds; the chug, bass and kit stay grid-tight, which is
  the aesthetic, not an oversight.
- **Sampled and synthesized voices mix freely:** the orchestra and clean
  guitar are recordings; the metal (chug, solo lead, crash) is saw/noise
  patches; the kit is the built-in kick/snare/hat, declared `pitch unpitched`.
- **The room:** the Jack Lyons concert hall at 45% wet carries the whole
  piece; the ending decays into it.

## Where things stand

What the piece surfaced, in the order it bit:

- **A part is one statement.** A second `name:` line overlays from beat 0
  rather than continuing the part; the first draft's section-by-section lines
  produced that tempo clash, not extra music. Long single lines (as in Blue
  Hour) are the idiom.
- **`hold` is a tempo shape**, so an ensemble fermata needs exactly one
  writer. Correct and enforceable, but a fermata over a bar line wants the
  tempo written somewhere all parts can see it; a conductor line remains the
  honest place for endings that belong to no one part.
- **No distortion.** The engine has no waveshaper, so there is no real metal
  guitar here: the chug is four detuned saws muted short and the lead a
  singing unison. It reads as synth-metal. A drive/distortion shaper (or a
  recorded high-gain guitar library) is the single biggest gap between this
  and the reference track.
- **The kit is synthesized presets**, which holds up at this scale; a sampled
  kit would deepen it. MIDI export refuses the piece (`unpitched instruments
  need an explicit MIDI percussion mapping`), so there is no MIDI of this
  arrangement until percussion mappings exist. The numeric view handles all
  thirteen parts fine.
- **`peak` normalizes down only.** The render peaked at -3.25 dBFS with the
  intro originally 22 dB under the drop; balance came from part gains, not
  the master. Loudness is a mix decision here, which is defensible, just
  manual.

Render cost: about 75 s for the minute, single pass, 1.5 GB of recordings
consulted through the header-lazy loader.

## 2026-11-06: recorded guitars and kit

The two gaps this page named are closed, at the owner's request: the score now
plays a recorded guitar through a drive and a recorded kit. What it says above
about saw patches and the built-in kit describes the piece as it was until
then. The design is in
[2026-11-06-NEOMUSIC-DRUMS-DRIVE-ORCHESTRA](2026-11-06-NEOMUSIC-DRUMS-DRIVE-ORCHESTRA.md).

- **Guitars.** The chug and the lead are the FreePats direct-recorded guitar
  (CC0) through `drive` on a `bus`, so a power chord is driven whole. The one
  chug part is played by two guitars, left and right: the recording's takes
  rotate, so they are two performances. Only the left one writes the accel,
  by the one-clock rule. The riff goes down to A1, so the guitar map was
  extended two semitones below the library's own lowest key.
- **Kit.** Kick, snare, closed hi-hat and crash are Big Rusty Drums (CC0).
  The kick ends with its note, so the last chorus's sixteenth double kicks do
  not pile up; the crash fades over five seconds. The drum lines are
  untouched: a fixed recording ignores the steps the synthesized kick needed.
- **Balance.** Each new part's gain was set from its level alone against the
  part it replaced, then the guitars and lead were adjusted until the section
  arc matched. Measured the same way before and after (mean level per
  section, whole bars):

  | Section | Before | After |
  |---|---|---|
  | intro (bars 1-4) | -32.5 dB | -31.9 dB |
  | drop (5-12) | -18.6 dB | -17.6 dB |
  | verse (13-20) | -18.3 dB | -17.5 dB |
  | chorus (21-28) | -16.0 dB | -15.4 dB |
  | bridge (29-32) | -17.6 dB | -16.8 dB |
  | final (33-40) | -15.3 dB | -15.1 dB |

  The peak is -1.9 dBFS both times. (These "before" figures differ a little
  from the ones above, which were taken over other spans.) The intro has no
  guitars or kit, so its 0.6 dB is the master's scaling alone; against that,
  every section is within 0.4 dB of where it sat. The chorus still lifts
  about 2 dB over the verse.
- **Length and cost.** 67.9 s where it was 64.5 s (the crash's tail), rendered
  in about 20 s.
- **MIDI.** The piece now exports to MIDI, since each drum declares its key
  (`pitch 36` and so on, from 2026-11-05).
- **Not judged by ear yet.** The levels are measurements. Whether the drive's
  voicing suits the piece, and whether short notes stand in well enough for
  palm mutes in the drop, needs listening. The audition MP3 is the new render.
