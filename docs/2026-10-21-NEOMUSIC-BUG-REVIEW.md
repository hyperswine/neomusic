# NeoMusic follow-up bug review

Kind: implementation and validation record. Applies to the working tree after
[the composition changes](2026-10-21-NEOMUSIC-COMPOSITION.md) and the subsequent
fixes to crescendo attacks, MIDI lag, curved chords and tempo labels.

## 2026-10-21: three reproduced bugs fixed

1. **Held expression bounds.** `level (start (0.5 -> -1)) [0]` was rejected
   because bounds included the negative end of the underlying curve. `start`
   holds only its onset value. Bounds now use that exact value when available;
   phase-zero sine and square values are also recognized exactly. Negative
   held expression remains invalid. This preserves the signal tree and its
   provenance for reading views.
2. **Effective MIDI tempo.** A base tempo of 1 BPM with conductor speed 120
   should export as 120 BPM. Export previously rejected the unused base tempo
   even though every emitted tempo was representable. MIDI now checks the
   effective tempo segments; an empty score still checks its base tempo.
   Uncovered spans, including trailing silence, still reject an out-of-range
   tempo. The regression compares the entire MIDI file with a plain 120 BPM
   score.
3. **Cents at tuning ratio 1.** When every integer step has the same frequency,
   varying cents previously divided by the zero step size and produced `NaN`.
   Cents now lower directly to octaves, independently of step size, through
   addition, unitless multiplication and held signals. Step-only offsets at
   ratio 1 remain neutral. Products of two cents-valued terms or nested cents
   still require a reciprocal step size and now return an explicit error at
   ratio 1. Their existing interpretation at other ratios is preserved.

## Validation

- Added three regression groups and observed all three fail against the
  pre-fix source, while the existing groups passed.
- `cabal test --offline --write-ghc-environment-files=never --test-show-details=direct`
  passes: 10 audio and 40 score/view groups. This includes ordinary, 24-EDO,
  descending and unit-ratio tuning checks, plus existing LilyPond goldens.
- `cabal build all --offline --write-ghc-environment-files=never` passes for
  the library and all four executables.
- All 16 `.neomusic` examples pass CLI `check`, including the recorded example
  with the sibling `neomusic-samples` assets.
- All three reproductions export numeric text and non-silent 44.1 kHz stereo
  WAV. The held-expression and effective-tempo cases also export MIDI.
  These are automated encoding checks, not a listening evaluation.
- `git diff --check` passes. Existing uncommitted changes were preserved.

This was a focused review of signal evaluation, tuning conversion and tempo
export, not an exhaustive proof that the system has no remaining bugs.
