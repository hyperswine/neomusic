# Recorded instruments: audition pass

Kind: audition measurements and score adjustments, 2026-10-29. Applies to
`main` at `2814192` (the tempo-hoisting branch as merged by PR #1, plus the
later streaming-export work). This does the listening work asked for by
[the integration note](2026-10-27-NEOMUSIC-ACOUSTIC-INSTRUMENTS.md): repeated
notes, short releases, nylon technique changes and overlapping guitar notes.

Everything here is objective signal analysis of local renders (44.1 kHz, peak
normalized to 0.8): envelopes, rest-separated attack correlations and spectral
centroids. No subjective listening judgment is recorded; the sections below
say what measurements support and what still needs ears. Probe scores, WAV
renders, the analysis script and `audition.json` are in ignored
`output/audition/`; the four example renders for listening are in
`output/audition/final/`.

## Repeated notes: confirmed identical replay, fixed in the examples

Eight C4 quarters on Salamander, attacks separated by rests so no release
contaminates the comparison:

| Score | Consecutive-attack correlation | Peak spread |
|---|---|---|
| `vel 0.8` alone | 1.0000, 1.0000, 1.0000 | 0.00 dB |
| `humanize 7` | 0.8093, 0.4547, 0.1053 | 0.79 dB |

Correlation exactly 1 is the same recording replayed at the same gain: the
machine-gun effect, now measured. Humanizing de-clones it by the intended
mechanism: a note's velocity is its strength at onset, strength varied by
`vary` 0.15 moves `round (vel * 127)` across Salamander's narrow upper
velocity bands (0.8 gives 102; 0.68..0.8 gives 86..102, crossing the 81/88,
89/96 and 97/104 layer boundaries), so repeats select *different recordings*,
not one replay at a different gain. On the finger-only nylon map (one
recording per key) humanize varies gain and timing only; on steel at
`vel 0.85` it crosses the 97 layer boundary, alternating the two firm layers.

Blue Hour already wrapped every part in `loose 1/80 [vary 0.1 ...]`; the four
acoustic examples did not. All four now apply `humanize` with one seed per
part (piano 3, nylon 5, steel 9, in the trio too). The numeric and staff views
of all four scores are byte-identical before and after: humanizing is
performance, engraving is unchanged, as the contract requires.

## Short releases: no clicks; the voice release replaces the natural ring

Single C4 on Salamander (release 0.4 s) and low E on nylon finger (0.7 s) at
gates 1/8 to 3:

| Gate | Piano: natural decay before note-off | 20 dB down after note-off | Total sound |
|---|---|---|---|
| 1/8 | attack still rising at 75 ms | 0.23 s | 0.48 s |
| 1/4 | attack still developing | 0.24 s | 0.54 s |
| 1 | partial beating (no net slope) | 0.23 s | 0.98 s |
| 3 | -12.8 dB/s | 0.29 s | 2.18 s |

- **No clicks.** The largest inter-sample step within +-5 ms of note-off is
  never an outlier against the surrounding 100 ms, at any gate: the ADSR
  release and the 2 ms declick guard start smoothly.
- **The release envelope governs, not the recording.** After note-off the
  level falls 20 dB in ~0.23 s (piano) while the recording's own decay is
  12.8 dB/s, so a released note dies about five times faster than the same
  string rings undamped. Nylon behaves the same with a longer tail (0.61 s to
  -40 dB).
- **Very short gates truncate the attack.** At gate 1/8 (75 ms at 100 bpm) the
  recorded hammer attack is still developing when the release starts, so
  staccato below about a sixteenth cuts the attack mid-rise.

These are the documented baseline limits, now with numbers. Whether 0.4/0.7 s
sounds like a damper or like a fade is an ear judgment; nothing was changed
here.

## Nylon technique: hard switches measured; band-safe velocities documented

Low E through the auto map, one note per render (spectral centroid of the
20-140 ms window):

| Velocity | Selected layer | Centroid |
|---|---|---|
| 0.30 (v38) | finger | 620 Hz |
| 0.34 (v43) | light pick | 968 Hz |
| 0.50 (v64) | light pick (same recording as v43) | 968 Hz |
| 0.85 (v108) | firm pick | 1168 Hz |

The finger-to-pick switch at velocity 43 is a +56% centroid jump between
adjacent dynamics, and `tech-flicker` (eight low Es at `vel 0.34` under
`humanize`) flickers technique note-to-note: centroids 506-1505 Hz across one
passage. So `vary` must not cross 43 or 86 on the auto map. The example's
written velocities keep `vary` 0.15 inside one band each:

| Written vel | v under vary 0.15 | Band |
|---|---|---|
| 0.25 | 27-32 | finger (1-42) |
| 0.55 | 59-70 | light pick (43-85) |
| 0.6 | 65-76 | light pick (43-85) |
| 0.85 | 92-108 | firm pick (86-127) |

The score now carries this as a comment: written velocities near 0.33 or 0.67
(the band edges as velocity fractions) should use the finger or pick map
instead of the auto map. The trio already uses the finger map, so its
dynamics cannot change technique.

## Overlapping guitar notes: no buildup, no clipping; muddiness is for ears

Em arpeggio at gate 1 versus gate 3/2, and four re-plucked low Es at gate 3/2,
all on the finger map:

| Probe | Peak RMS | Total sound |
|---|---|---|
| arpeggio, gate 1 | -4.48 dB | 2.40 s |
| arpeggio, gate 3/2 | -4.44 dB | 2.54 s |
| re-pluck, gate 3/2 | -4.34 dB | 2.04 s |

Ringing into the next note (gate 3/2) sustains between onsets by about 3 dB
but does not raise the peak; re-plucks sum linearly without runaway, and the
master `peak 0.8` normalization holds at exactly -1.94 dBFS on every render.
With no same-string choking (a stated baseline limit) overlapping notes simply
add; whether that is muddy in longer arrangements is a listening question,
already flagged for Blue Hour-scale pieces.

## What changed

- `piano-recorded`, `guitar-nylon-recorded`, `guitar-steel-recorded`,
  `acoustic-trio`: `humanize` with one seed per part (3/5/9), with comments
  saying why (layer crossing on piano and steel; band safety on the nylon auto
  map; finger map in the trio).
- No engine, sampler, map or documentation-contract changes.

Verification: the four scores pass `check`; their numeric and staff views are
byte-identical to before the change; WAV and MP3 renders peak at exactly
-1.94 dBFS with the same durations as before; the full Cabal suite passes
(score properties, CLI and golden regressions).

## Still for ears

- Whether layer-crossing repeats (piano, firm steel) sound like a player or
  like a sampler glitch.
- Whether the 0.4 s piano / 0.7 s guitar release reads as a damper at
  staccato, and whether the 1/8-gate attack truncation is audible at tempo.
- Whether six-string overlaps and gate 3/2 arpeggios stay clear in longer
  arrangements.
