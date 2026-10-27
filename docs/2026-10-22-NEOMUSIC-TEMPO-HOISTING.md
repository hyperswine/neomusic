# Tempo hoisting: one ownership rule instead of three

Kind: prototype and decision record, 2026-10-22, on branch `tempo-hoisting`
against `6eecc11`. It revisits the conductor contract in
[the composition update](2026-10-21-NEOMUSIC-COMPOSITION.md), which made an
explicit conductor mandatory for multi-part tempo (a user decision). Merging
this relaxes that decision, so it is the user's call.

## The problem

Tempo is written in a scope (`speed 2 [x]`) but acts globally: `timeMap` reads
every tempo node in the score, whatever branch it sits in, so a change acts on
everything sounding during its beats. Three rules guarded that one fact:

1. `flatten`: parallel branches may not set overlapping tempo.
2. `arrange`: instrumental parts may contain no tempo at all.
3. The language: a multi-part document with any inline tempo needs a
   `conductor:` line, except that a single-part document may keep it inline.

Rule 1 is the real constraint: two owners of the same beats would multiply by
accident. Rules 2 and 3 are stricter versions of it, and they made validity
depend on how many parts a document has:
- a single part with `rit` was valid, and adding a tempo-free second part made
  the document an error;
- `a: speed 1 [...]` beside another part was rejected by rule 3, although
  rule 1 says a steady 1 owns nothing.

## The prototype

`ensemble :: [(Name, Score)] -> Either String Score` combines named parts:

- Each part's tempo is hoisted out of it, `conductorOf` for the clock and
  `withoutTempo` for the music, into one clock beside tempo-free music:
  `clock :||: music`. Every tempo node keeps its written position, so the clock
  is unchanged.
- The one rule, `tempoClash`, is rule 1, now one function shared by `flatten`
  and `ensemble`: no two parts set a tempo other than 1 over the same written
  beats. Nesting inside one part multiplies, as before. The error names both
  parts and the beats: `right and left both set the tempo over beats 1-3; keep
  it in one of them, or in a conductor: track`.
- A conductor is a part without notes (`conductorTrack` checks that and turns
  its rests into silence). It is optional and may sit beside parts that own
  other spans.
- `arrange conductor parts` is now `ensemble` with the conductor as a part.
  `arrange (conductorOf s) [withoutTempo s]` still migrates a score.

In the language, every voice line is a part and `parseDocument` calls
`ensemble`. The conductor-required check, the single-part exception and the
duplicate-conductor error are gone. The diff is 3 files, +86/-23: most of it
is the new tests and doc comments.

## Evidence

- `cabal test`: 10 audio and 40 score/view groups pass, including the LilyPond
  goldens and source round-trips. The ownership test now checks:
  - inline part tempo renders, numbers and sheets exactly as the same tempo in
    a conductor;
  - parts owning different spans, beside a conductor, are accepted, and so is
    `speed 1` beside another part's tempo;
  - real clashes are still rejected: two parts, a part and the conductor, or
    two branches of one part, with the named error;
  - the hoisted form is one clock with no notes beside music with no tempo.
- **Byte-identical outputs.** `main` was built in a separate worktree and every
  example (all 16, including the two recorded-orchestra scores) was exported by
  both. WAV, MIDI and numeric text are identical, so every score valid before
  behaves exactly as before.

## What it changes for authors

| Document | Before | With hoisting |
|---|---|---|
| one part with `rit`, plus a tempo-free part | error | valid |
| `a: speed 1 [...]` beside a part with tempo | error | valid |
| two parts' tempo over different spans | error | valid |
| a conductor plus a part's tempo over another span | error | valid |
| two parts' tempo over the same beats | error | error, naming both |
| two `conductor:` lines | error | valid (two owners, still clash-checked) |

## Trade-offs and the decision

- **For:** one rule, stated once and checked in one place; validity no longer
  depends on the number of parts; tempo can live next to the music it shapes
  (a part's own `rit` or fermata); errors say where the clash is.
- **Against:** the explicit-conductor discipline from the 2026-10-21 decision
  becomes optional. A long score can scatter tempo across parts, which is
  harder to read than one conductor line. Canonical source (`prettyScore`)
  still emits a single `conductor:`, and the numeric and staff views already
  show one combined tempo lane, so readers of generated output always see one
  owner. A lint could recommend a conductor for multi-part scores without
  making it an error.
- **Not changed:** the reviewer's other observations (a conductor longer than
  the parts extends the piece; equal effective factors from different owners
  still clash) are out of scope and behave as before.

If accepted, `docs/2026-09-22-NEOMUSIC-LANGUAGE.md` changes as on this branch,
and the composition note's conductor contract gains a pointer here.
