# Composition, clocks and interpretation

Kind: implementation plan and design record, begun 2026-10-21 against
`7730e6d`. This supersedes the signal note's extraction of velocity from
constant factors and its elapsed-seconds interpretation under tempo ramps.

The objective is to make musical meaning independent of incidental expression
structure. Keep integer steps, rational written time, numeric notation as the
default view, and ordinary prelude definitions over a small core.

## Plan and acceptance criteria

1. **Strength and expression.** Store attack strength separately from expression.
   `vel` changes strength; `level` changes expression. Equivalent signal
   expressions must produce the same strengths and audio. Preserve humanisation,
   source round trips, zero-onset fades and the crescendo reading view.
2. **Musical clocks.** Lower signals through the written-beat clock, including
   inside a sounding note. A phrase curve at a given written position must not
   depend on note segmentation. Test ramps, swing, gates, pitch and level, and
   agreement between MIDI and audio. Sound envelopes in `Mod` retain seconds.
3. **Tempo ownership.** Keep one ensemble clock, owned explicitly by a conductor
   track (user decision, 2026-10-21). Combining independent instrumental parts
   must not multiply their tempo instructions accidentally. Preserve nested
   tempo composition within the conductor and exact beat onsets. Migrate the
   examples and canonical source; reject ambiguous ownership with an actionable
   diagnostic. Numeric and staff views must describe the effective clock.
4. **Pitch identity.** Make pitched/unpitched interpretation an instrument
   property. Exporters must not classify a voice by examining an oscillator,
   filter or bend graph. A transposed pitched voice must export normally;
   unpitched instruments must fail explicitly until a percussion mapping exists.

Each stage adds regression tests, runs the existing suite, and records actual
results here. Haskell examples and `.neomusic` examples are part of migration.
No changes to recording assets or new synthesis algorithms are required.

## Strength and expression contract

`Event.strength` is an exact constant signal; `Event.level` is the independently
varying expression multiplier. Keeping the strength's expression (for example
`Start (Noise ...)`) lets reading views ignore humanisation without guessing
from its evaluated number. Validation requires a unitless constant in 0..1.
The audio and MIDI boundaries evaluate that explicit strength once per note.
They never extract it from `level`.

`strength s` multiplies attack strength by a constant. `strength across s`
samples a phrase signal at each note's written onset. `level s` and
`level across s` multiply expression only, even when `s` is constant.

`dynamics across s` is a coordinated gesture, used by `cresc` and `dim`:
sample its onset value `k` for strength, then multiply expression by `s/k`.
This works on the value of any supported signal expression, not just a
top-level `Points` constructor. At zero onset it takes strength from the
curve's peak within the note and normalizes expression by that peak, so a
fade-in sounds and attacks still rise through a crescendo from silence; a
note whose curve never rises above zero keeps neutral strength and is silent. This coordinated gesture
does not claim the same algebraic laws as the independent controls.

The prelude keeps `vel`, `swell`, `cresc`, `dim`, `vary` and `humanize`.
Migration: Haskell callers that used `scaleLevel (Const k)` for velocity should
use `scaleStrength (Const k)`. Direct `level` now consistently means expression;
use `vel` for attack changes. Direct `level across` now means expression only;
use `dynamics across` for the previous combined crescendo intent.

## Validation record

Baseline: 9 audio and 33 score/view checks passed on a fresh source build.
All four stages are implemented and locally validated:

- `cabal build all --offline --write-ghc-environment-files=never` passed for the
  library and all four executables.
- `cabal test --offline --write-ghc-environment-files=never --test-show-details=direct`
  passed: 9 audio and 37 score/view checks, including four new regression groups.
- All 16 example files passed the CLI `check` path, including the recorded
  orchestral score using the existing sibling `neomusic-samples` assets. This
  checks loading and timeline construction, not a full render of every score.
- The composition example exported numeric text/HTML, MIDI, WAV and MP3.
  WAV/MP3 encoding and stream metadata were checked; this is not a listening
  evaluation. Generated files are in ignored `output/`.
- Existing LilyPond golden outputs passed unchanged. `git diff --check` passed.

Remaining limitations: unpitched MIDI/staff mapping is still unsupported;
MIDI expression above 1 still clips to its controller range; phrase-spanning
oscillators are still rejected. These changes do not claim to solve those
separate backend/language extensions.


## Musical clock contract

All score signals now advance in written musical time. `Points` uses the
normalized written sounding span; oscillators use written beats. Audio lowers
this to `Warp` over normalized coordinates, with an analytic inverse of each
log-linear clock segment. Constant-clock notes retain the existing fast path.
MIDI samples in written beats and uses its conductor tempo track for playback.
Physical sound envelopes (`Mod`, including attack/release and fixed-Hz LFOs)
continue to use seconds.

This changes curves under nonconstant tempo intentionally. A phrase gesture
is now independent of subdivision into notes; cycle count and local cycle rate
both follow the beat. The regression checks ramps, swing, cyclic ramps, gates
that outlast a tempo scope, level and pitch, plus MIDI controller-track data.
MIDI's stepped tempo approximation still applies between its tempo events.

## Conductor contract

```
conductor: _:4 rit 2/3 [_:4] speed 2 [speed 2 [_:2]] _:2
lead:     0 2 4 7 7:4 [0 4 7 12]:1/2 (0 4 7):2
bass:     -12:4 -17:4 -12:2 -12:2
```

The conductor uses ordinary music expressions over rests. It contributes
written extent and tempo, but no instrumental events. It may not contain notes,
and a document has at most one conductor track. Instrumental parts alongside
an explicit conductor must contain no tempo nodes. Multi-part documents with
inline tempo must migrate it to a conductor; a single-part document retains
inline tempo as a convenient shorthand.

At the Haskell boundary, `arrange conductor parts` checks the same ownership.
Existing scores can migrate with `arrange (conductorOf s) [withoutTempo s]`.
`Tempo` remains available for whole-score and single-part construction. The
shared validator rejects overlapping tempo nodes from parallel siblings;
intentional nested nodes still multiply. This prevents accidental factor
multiplication without silently deduplicating legitimate nested composition.
Whole-score `scaleScore` and `reverseScore` now live in the core API.

For nonoverlapping tempo, reading views retain the familiar swing/hold/rit
marks. With overlapping nested factors, numeric and staff views describe the
combined log-linear clock segments. Numeric constant factors are exact where
available; irrational ramp endpoints carry `~` and six decimal places.

The tempo, forest and two orchestral examples have been migrated. The conductor
has no instrument declaration, no voice lane and no MIDI note/channel.

## Pitch identity contract

`Instrument.pitchIdentity` is `Pitched` (the default) or `Unpitched`. In source:

```
instrument lead = customSound pitch pitched
instrument drums = kick pitch unpitched
```

MIDI and staff exporters use this declaration, never the synthesis graph.
A pitched instrument with an octave bend remains pitched; a declared unpitched
instrument is rejected until an explicit percussion/staff mapping is supplied.
This does not attempt to transcribe a patch's internal oscillators or detuning:
MIDI and staff remain interpretations of score pitches. Audio is unaffected.
The old `Audio.percussive` helper remains a legacy heuristic, not export policy.
Custom noise/percussion instruments should declare `pitch unpitched` explicitly.

## Try the changes

`examples/neomusic/composition.neomusic` combines a phrase crescendo, a held
pitch curve under ritardando, an explicitly nested speed change and two parts.

```
cabal run neo-music -- check examples/neomusic/composition.neomusic
cabal run neo-music -- sheet examples/neomusic/composition.neomusic
cabal run neo-music -- play examples/neomusic/composition.neomusic -o output/composition.mp3
```

Create `output/` before exporting. That directory is ignored by Git.
