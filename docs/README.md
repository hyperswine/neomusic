# docs/: a chronological record

Kind: index. Every document in this directory is named
`YYYY-MM-DD-NAME.md`, dated by the day it was first written, so a listing of
the directory is the timeline of the project's thinking. Older and newer pages
are not reconciled with each other: a page says what was true or intended when
it was written, and a later page may supersede it without the earlier one
being rewritten. When two pages disagree, the later date wins.

The repository [README](../README.md) and the [terra-bgm note](../pieces/terra-bgm/README.md) stay beside the code they describe.

## Adding a page

Name it with today's date, add one line to the end of the list below, and say
near the top what kind of page it is and what state of the code it applies to.
Do not rename a page when it changes: its date is when it began, and the record
of what changed goes in dated sections inside it. Do not fold an older page
into a newer one to make them agree; write the newer one and point back.

Pages written before 2026-10-21 came from HaskPlayground, where they moved into docs/ on 2026-10-20; they keep the date already in their name, or else the date of their first commit.

## The record, oldest first

| date | page | what it is |
|---|---|---|
| 2026-09-12 | [NEOMUSIC-DESIGN](2026-09-12-NEOMUSIC-DESIGN.md) | Neo Music Notation and Neo Keyboard design document, draft v0.1 |
| 2026-09-12 | [NEOMUSIC-V1](2026-09-12-NEOMUSIC-V1.md) | the first playable NeoMusic implementation (`Seq`, `Part`, `Piece`); historical since 2026-10-12 |
| 2026-09-16 | [NEOMUSIC-V2](2026-09-16-NEOMUSIC-V2.md) | NeoMusic v2: velocity, synth voices, stereo mixing and reverb; historical since 2026-10-12 |
| 2026-09-22 | [NEOMUSIC-REVIEW](2026-09-22-NEOMUSIC-REVIEW.md) | review of v0.1, v1 and v2, and the proposal that led to `.neomusic` files and piano sheets |
| 2026-09-22 | [NEOMUSIC-LANGUAGE](2026-09-22-NEOMUSIC-LANGUAGE.md) | the current NeoMusic score language and `.neomusic` file guide: authoring, audio, MIDI, LilyPond |
| 2026-10-12 | [NEOMUSIC-CURVES](2026-10-12-NEOMUSIC-CURVES.md) | curves within a note; superseded 2026-10-13 by signals |
| 2026-10-12 | [NEOMUSIC-TIMEMAP](2026-10-12-NEOMUSIC-TIMEMAP.md) | time maps: one shared clock, tempo shapes and views |
| 2026-10-13 | [NEOMUSIC-PRELUDE](2026-10-13-NEOMUSIC-PRELUDE.md) | number parameters and a prelude: conveniences as definitions, not keywords |
| 2026-10-13 | [NEOMUSIC-SIGNALS](2026-10-13-NEOMUSIC-SIGNALS.md) | signals: one algebra for everything that varies over a note |
| 2026-10-14 | [NEOMUSIC-CYCLE](2026-10-14-NEOMUSIC-CYCLE.md) | tempo shapes as Ramp and Cycle |
| 2026-10-14 | [NEOMUSIC-HUMANIZE](2026-10-14-NEOMUSIC-HUMANIZE.md) | humanizing: timing and level variation per part |
| 2026-10-14 | [NEOMUSIC-PATCH](2026-10-14-NEOMUSIC-PATCH.md) | patches as modulation signals |
| 2026-10-14 | [NEOMUSIC-PHRASE](2026-10-14-NEOMUSIC-PHRASE.md) | phrase-level signals across notes |
| 2026-10-14 | [NEOMUSIC-SAMPLES](2026-10-14-NEOMUSIC-SAMPLES.md) | recorded sources (WAV, SFZ) and real rooms |
| 2026-10-14 | [NEOMUSIC-SOUNDS](2026-10-14-NEOMUSIC-SOUNDS.md) | sounds and mix defined in `.neomusic` files |
| 2026-10-14 | [NEOMUSIC-VOICE](2026-10-14-NEOMUSIC-VOICE.md) | voices as signal graphs: sources, shapers, mixing |
| 2026-10-21 | [NEOMUSIC-COMPOSITION](2026-10-21-NEOMUSIC-COMPOSITION.md) | plan and implementation record: strength, clocks, conductor ownership and pitch identity |
| 2026-10-21 | [NEOMUSIC-BUG-REVIEW](2026-10-21-NEOMUSIC-BUG-REVIEW.md) | follow-up fixes: held expression bounds, effective MIDI tempo and unit-ratio cents |
| 2026-10-22 | [NEOMUSIC-TEMPO-HOISTING](2026-10-22-NEOMUSIC-TEMPO-HOISTING.md) | prototype: tempo hoisted from any part, one ownership rule instead of three |
| 2026-10-24 | [NEOMUSIC-PIANO-AND-GUITARS](2026-10-24-NEOMUSIC-PIANO-AND-GUITARS.md) | intent: integrate Salamander piano and Meta nylon- and steel-string guitars |
| 2026-10-27 | [NEOMUSIC-ACOUSTIC-INSTRUMENTS](2026-10-27-NEOMUSIC-ACOUSTIC-INSTRUMENTS.md) | first Salamander and Meta guitar integration, setup, render evidence and remaining limits |
| 2026-10-27 | [LAST-TRAIN-BLUE-HOUR](2026-10-27-LAST-TRAIN-BLUE-HOUR.md) | original 72-bar J-pop/jazz acoustic trio, MP3 audition and score |
| 2026-10-29 | [NEOMUSIC-AUDITION](2026-10-29-NEOMUSIC-AUDITION.md) | audition pass on the recorded instruments: measurements, humanized examples, what still needs ears |
