# Recorded piano and guitars: intent

Kind: intent and implementation plan, 2026-10-24. The user has chosen
Salamander Grand Piano and Meta's nylon- and steel-string guitars as the next
recorded instruments to integrate into NeoMusic. Integration and listening
comparisons are pending; this note does not claim they already work in the
renderer or have been demonstrated to sound better.

This builds on [recorded sources and real rooms](2026-10-14-NEOMUSIC-SAMPLES.md).

## Selected libraries

| Instrument | Source | Reason for choosing it |
|---|---|---|
| Piano | [Salamander Grand Piano](https://github.com/sfzinstruments/SalamanderGrandPiano) by Alexander Holm | A dedicated sampled grand piano with 16 velocity layers, for more detailed piano dynamics. |
| Nylon-string guitar | [Meta Open Sound](https://github.com/facebookincubator/Meta-open-sound) | Real classical-guitar recordings with documented note mapping and dynamic layers. |
| Steel-string guitar | [Meta Open Sound](https://github.com/facebookincubator/Meta-open-sound) | Real acoustic-guitar recordings with documented string coverage and velocity layers. |

Use the full-quality recordings for rendering. Meta publishes WAV bundles on
its [releases page](https://github.com/facebookincubator/Meta-open-sound/releases).
For Salamander, identify and pin a specific distribution: the linked SFZ remap
uses FLAC and advanced SFZ/ARIA features, so it is not a drop-in instrument for
NeoMusic's current WAV reader and SFZ subset.

Salamander is published under CC BY 3.0; retain the license and attribution to
Alexander Holm, and credit any reused mapping work. Meta's instrument
collections are published under CC0. Record the exact source, version,
license, credits and checksums with the chosen assets and mappings.

## Integration direction

Keep the existing separation: the score describes music, while the performance
chooses its instruments. Each library should become a `Sampled` source through
an explicit mapping, composable with the existing envelopes, gain, pan and
other voice operations. No piano- or guitar-specific score syntax is needed
for this first integration.

Store the large recordings outside Git, using the existing `NEOMUSIC_SAMPLES`
lookup. Keep small mappings, reproducible preparation scripts, acquisition
instructions and attribution in the repository. Add these as explicit sound
choices so existing scores retain their current instruments.

## Planned steps and acceptance

1. Obtain and pin the selected recordings; inspect their ranges, root pitches,
   dynamic layers, release behavior and licenses. Prepare losslessly decoded
   WAV files where the selected distribution requires it.
2. Audit the supplied mappings against the supported SFZ subset. Adapt them
   without silently dropping behavior. Document any simplifications, especially
   Salamander's release/resonance behavior and guitar string selection; extend
   the sampler only where the chosen musical behavior requires it.
3. Add examples for solo piano, each guitar, and a small mixed arrangement.
   Exercise soft and loud attacks, repeated notes, chords, short notes and
   sustained notes across the supported ranges.
4. Check deterministic rendering, pitch and velocity-region selection, and WAV
   and MP3 export. Make listening comparisons at matched loudness using the
   same score and performance settings where comparable; retain the original
   renders as references.

The first milestone is all three instruments rendering through NeoMusic's own
engine with documented mappings and audible examples. Claims of improved
realism follow the listening comparison. Advanced piano pedal/resonance and
guitar performance techniques can be considered after that baseline works.

## 2026-10-27: first milestone

All three instruments now render locally through the existing sampler. See the
[integration record](2026-10-27-NEOMUSIC-ACOUSTIC-INSTRUMENTS.md) for setup,
validation, audition files and remaining performance-model limitations.
Subjective listening comparisons are still pending.
