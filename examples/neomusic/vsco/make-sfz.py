#!/usr/bin/env python3
"""Write SFZ mappings for the VSCO 2 Community Edition orchestra.

VSCO 2 CE (https://github.com/sgossner/VSCO-2-CE, CC0) ships its recordings
without mappings; it names each file by note, velocity layer and take. This
script reads those names and writes one .sfz per instrument here. Run it once
with the library's location:

    python3 make-sfz.py ~/neomusic-samples/VSCO-2-CE

The .sfz files name samples under "VSCO-2-CE/", so set NEOMUSIC_SAMPLES to the
directory that contains the library.

Pitches were measured, not assumed (see docs/2026-10-14-NEOMUSIC-SAMPLES.md
and docs/2026-11-06-NEOMUSIC-DRUMS-DRIVE-ORCHESTRA.md):
- Most folders name notes one octave low (their "A3" sounds at 440 Hz); the
  harp names them as sounding (its A4 is 440 Hz) and is 7 cents flat. So do
  the solo violin's bowed and plucked notes, the upright piano and the
  tubular bells.
- The timpani files name drums, not notes. Each drum's principal pitch comes
  from its spectrum (partials at about 1, 1.5 and 2 times it).
- The organ and the second upright number their files; the organ's keys were
  measured, and the upright's come from its own chart.
- The clarinet's "F#5" sustain sounds an F (one semitone lower than its name).

Pitched instruments follow the key and stop with the note (a release in the
voice lets them ring). Unpitched percussion plays as recorded on every key, to
the end of the recording.
"""
import os, re, sys
from collections import defaultdict

PITCH = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}

def midi(name, octave, shift):
    return 12 * (int(octave) + 1) + PITCH[name[0]] + (1 if name.endswith('#') else 0) + shift

# name: (folder, filename pattern with groups note, octave, layer, take; octave shift; tune cents)
FOLDERS = {
    'violins': ('Strings/Violin Section/susVib', r'_([A-G]#?)(-?\d)_v(\d)()\.wav$', 12, 0),
    'violas': ('Strings/Viola Section/susvib', r'_([A-G]#?)(-?\d)_v(\d)_(\d)\.wav$', 12, 0),
    'cellos': ('Strings/Cello Section/susvib', r'_([A-G]#?)(-?\d)_v(\d)_(\d)\.wav$', 12, 0),
    'bass': ('Strings/Solo Contrabass/SusVib', r'_([A-G]#?)(-?\d)_v(\d)_rr(\d)\.wav$', 12, 0),
    'violin-pizz': ('Strings/Violin Section/Pizz', r'_([A-G]#?)(-?\d)_v(\d)_rr(\d)\.wav$', 12, 0),
    'cello-pizz': ('Strings/Cello Section/pizzT', r'_([A-G]#?)(-?\d)_v(\d)_RR(\d)\.wav$', 12, 0),
    'flute': ('Woodwinds/Flute/susvib', r'_([A-G]#?)(-?\d)_v(\d)_(\d)\.wav$', 12, 0),
    'horn': ('Brass/F Horn/sus', r'_([A-G]#?)(-?\d)_v(\d)_(\d)\.wav$', 12, 0),
    'harp': ('Strings/Harp', r'_([A-G]#?)(-?\d)_(?:mp|mf|f)()()\.wav$', 0, 7),
}

# The rest of the orchestra, in the same form. A layer is a number or a
# dynamic mark (pp, mf, f...); a take is a number or absent.
NOTE = r'_([A-G]#?)(-?\d)'
MORE = {
    # Strings: the remaining articulations and the solo violin.
    'violin-spic': ('Strings/Violin Section/Spic', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'violin-trem': ('Strings/Violin Section/Trem', NOTE + r'_v(\d)()\.wav$', 12, 0),
    'viola-pizz': ('Strings/Viola Section/pizz', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'viola-spic': ('Strings/Viola Section/spic', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'viola-trem': ('Strings/Viola Section/trem', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'cello-spic': ('Strings/Cello Section/spic', NOTE + r'_v(\d)_RR(\d)\.wav$', 12, 0),
    'cello-trem': ('Strings/Cello Section/trem', NOTE + r'_v(\d)_(\d)\.wav$', 12, 0),
    'bass-nv': ('Strings/Solo Contrabass/SusNV', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'bass-pizz': ('Strings/Solo Contrabass/Pizz', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'bass-spic': ('Strings/Solo Contrabass/Spic', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'bass-trem': ('Strings/Solo Contrabass/Trem', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'solo-violin': ('Strings/Solo Violin/Arco Vib', NOTE + r'_(p|f)()\.wav$', 0, 0),
    'solo-violin-pizz': ('Strings/Solo Violin/Pizz', NOTE + r'_(p|f)(?:_RR(\d))?\.wav$', 0, 0),
    'solo-violin-spic': ('Strings/Solo Violin/spic', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'solo-violin-trem': ('Strings/Solo Violin/Trem', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    # Woodwinds.
    'flute-nv': ('Woodwinds/Flute/susNV', NOTE + r'_v(\d)_(\d)\.wav$', 12, 0),
    'flute-exp': ('Woodwinds/Flute/expvib', NOTE + r'_v(\d)_(\d)\.wav$', 12, 0),
    'flute-stac': ('Woodwinds/Flute/stac', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'piccolo': ('Woodwinds/Piccolo/Sus', NOTE + r'_()sustain(\d)\.wav$', 12, 0),
    'piccolo-stac': ('Woodwinds/Piccolo/Stac', NOTE + r'_()staccato(\d)\.wav$', 12, 0),
    'oboe': ('Woodwinds/Oboe/Sus', NOTE + r'_v(\d)()_Main\.wav$', 12, 0),
    'oboe-vib': ('Woodwinds/Oboe/Vib', NOTE + r'_v(\d)()_Main\.wav$', 12, 0),
    'oboe-stac': ('Woodwinds/Oboe/Stacc', NOTE + r'_v(\d)_rr(\d)_Main\.wav$', 12, 0),
    'clarinet': ('Woodwinds/Clarinet/susLong', NOTE + r'_v(\d)_rr(\d)_sum\.wav$', 12, 0),
    'clarinet-stac': ('Woodwinds/Clarinet/stac', NOTE + r'_v(\d)_rr(\d)_sum\.wav$', 12, 0),
    'bassoon': ('Woodwinds/Bassoon/sus', NOTE + r'_v(\d)_(\d)\.wav$', 12, 0),
    'bassoon-vib': ('Woodwinds/Bassoon/vib', NOTE + r'_v(\d)_(\d)\.wav$', 12, 0),
    'bassoon-stac': ('Woodwinds/Bassoon/stac', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    # Brass.
    'horn-stac': ('Brass/F Horn/stac', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'horn-mute': ('Brass/F Horn/mute', NOTE + r'_v(\d)_(\d)\.wav$', 12, 0),
    'trumpet': ('Brass/Trumpet/sus', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'trumpet-vib': ('Brass/Trumpet/susvib', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'trumpet-stac': ('Brass/Trumpet/stac', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'trumpet-harmon': ('Brass/Trumpet/harmonM-sus', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'trumpet-straight': ('Brass/Trumpet/straightM-sus', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'trombone': ('Brass/Tenor Trombone/sus', NOTE + r'_v(\d)_(\d)\.wav$', 12, 0),
    'trombone-vib': ('Brass/Tenor Trombone/vib', NOTE + r'_v(\d)_(\d)\.wav$', 12, 0),
    'trombone-stac': ('Brass/Tenor Trombone/stac', NOTE + r'_v(\d)_rr(\d)\.wav$', 12, 0),
    'old-trombone': ('Brass/OldTrombone/Sustain', NOTE + r'_v(\d)_(\d)\.wav$', 12, 0),
    'old-trombone-vib': ('Brass/OldTrombone/Vibrato', NOTE + r'_v(\d)_(\d)\.wav$', 12, 0),
    'old-trombone-stac': ('Brass/OldTrombone/Short', NOTE + r'_v(\d)_(\d)\.wav$', 12, 0),
    'tuba': ('Brass/Tuba/sus', NOTE + r'_v(\d)_rr(\d)_Mid\.wav$', 12, 0),
    'tuba-stac': ('Brass/Tuba/stac', NOTE + r'_v(\d)_rr(\d)_Sum\.wav$', 12, 0),
    # Keys and tuned percussion.
    'upright': ('Keys/Upright Nr1', NOTE + r'_(pp|mf|f)_RR(\d)\.wav$', 0, 0),
    'glockenspiel': ('Percussion/Glock', NOTE + r'()()\.wav$', 12, 0),
    'marimba': ('Percussion/Marimba', NOTE + r'_loud()_(\d+)\.wav$', 12, 0),
    'xylophone': ('Percussion/Xylo', NOTE + r'_ff()_(\d+)_far\.wav$', 12, 0),
    'tubular-bells': ('Percussion', r'^TB_hit_([A-G]#?)(\d)()_v\d_rr(\d)\.wav$', 0, 0),
}

# Files whose names are wrong: (instrument, named note) -> semitones to add.
MISNAMED = {('clarinet', 'F#5'): -1}

# Softest first.
DYNAMICS = ['ppp', 'pp', 'p', 'mp', 'mf', 'f', 'ff', 'fff']

# Numbered files: name -> (folder, filename pattern with the number, key of number 0, keys per number).
NUMBERED = {
    'organ': ('Keys/Organ/Loud', r'^Rode_Man3Open_(\d+)\.wav$', 35, 1),
    'organ-pedal': ('Keys/Organ/Loud', r'^Rode_Pedal_(\d+)\.wav$', 23, 1),
    'organ-quiet': ('Keys/Organ/Quiet', r'^NT5_Man3Quiet_(\d+)_rr1\.wav$', -86, 1),
    'organ-quiet-pedal': ('Keys/Organ/Quiet', r'^NT5_PedalQuiet_(\d+)_rr1\.wav$', -28, 1),
}

# Unpitched percussion: name -> filename pattern in Percussion/ with groups layer, take.
HITS = {
    'anvil': r'^Anvil_Hit1_v(\d)()_Sum',
    'bass-drum': r'^BDrumNewhit_v(\d)_rr(\d)_Sum',
    'bell-tree': r'^BellTree_Stroke()(\d)_v1_Sum',
    'brake-drum': r'^BrakeDrum1_Hammer_v(\d)()_Sum',
    'claves': r'^Claves1_Hit_v(\d)_rr(\d)_Sum',
    'conga': r'^Conga-HitN_v(\d)_rr(\d)_Sum',
    'conga-tap': r'^Conga-Tap1_v(\d)_rr(\d)_Sum',
    'quinto': r'^Quinto-HitN_v(\d)_rr(\d)_Sum',
    'quinto-tap': r'^Quinto-Tap1_v(\d)_rr(\d)_Sum',
    'tumba': r'^Tumba-HitN_v(\d)_rr(\d)_Sum',
    'tumba-tap': r'^Tumba-Tap1_v(\d)_rr(\d)_Sum',
    'cowbell': r'^Cowbell1_Hit_v(\d)_rr(\d)_Sum',
    'guiro': r'^Guiro-Hit_v(\d)_rr(\d)_Sum',
    'log-drum-high': r'^LogDrumHi_MedM_v(\d)_rr(\d)_Sum',
    'log-drum-low': r'^LogDrumLo_MedM_v(\d)_rr(\d)_Sum',
    'ratchet': r'^Ratchet1-Crank_v(\d)_rr(\d)_Sum',
    'sleighbells': r'^Sleighbells_Hit_v(\d)_rr(\d)_Mid',
    'concert-snare': r'^Snare2-HitSN_v(\d)_rr(\d)_Sum',
    'concert-snare-off': r'^Snare2-HitNS_v(\d)_rr(\d)_Sum',
    'concert-snare-roll': r'^Snare2-rollSN_v(\d)_rr(\d)_Sum',
    'concert-snare-tap': r'^Snare2-taps_v(\d)_rr(\d)_Sum',
    'tambourine': r'^Tamb1-Hit_v(\d)_rr(\d)_Sum',
    'tambourine-roll': r'^Tamb1-Roll_v(\d)_rr(\d)_Sum',
    'tambourine-shake': r'^Tamb1-Shake_v(\d)_rr(\d)_Sum',
    'triangle': r'^Triangle6-Hit_v(\d)_rr(\d)_Sum',
    'triangle-mute': r'^Triangle6-HitM_v(\d)_rr(\d)_Sum',
    'triangle-roll': r'^Triangle6-Roll_v(\d)_rr(\d)_Sum',
    'triangle-small': r'^Triangle3-Hit_v(\d)_rr(\d)_Sum',
    'triangle-small-mute': r'^Triangle3-HitM_v(\d)_rr(\d)_Sum',
    'triangle-small-roll': r'^Triangle3-Roll_v(\d)_rr(\d)_Sum',
    'cymbals': r'^cymbal-crash1_(pp|mp|mf|ff)_rr(\d)',
    'sus-cymbal': r'^susCymb1-hit_(pp|mp|f|fff)_rr(\d)',
    'sus-cymbal-stick': r'^susCymb1-hitstick_(pp|mp|f|fff)_rr(\d)',
    'sus-cymbal-bell': r'^susCymb1-hit-bell_(pp|mf|fff)()',
    'gong': r'^gongHit_(p|mf|f|fff)()',
}

# Timpani drum -> measured principal pitch (MIDI, fractional).
DRUMS = {1: 41.5, 2: 46.9, 3: 49.5, 4: 52.4, 5: 54.5}

def ranges(keys, margin=2):
    """Each key covers up to halfway to its neighbours; the ends reach `margin` further."""
    out = {}
    for i, k in enumerate(keys):
        lo = keys[i - 1] + (k - keys[i - 1]) // 2 + 1 if i > 0 else max(0, k - margin)
        hi = k + (keys[i + 1] - k) // 2 if i + 1 < len(keys) else min(127, k + margin)
        out[k] = (lo, hi)
    return out

def layers(n):
    """n velocity layers splitting 1..127 evenly, softest first."""
    edges = [round(1 + 127 * i / n) for i in range(n + 1)]
    return [(edges[i], edges[i + 1] - 1 if i + 1 < n else 127) for i in range(n)]

def write(name, sections, header):
    """sections: [(folder, regions)], each under its own default_path."""
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), name + '.sfz'), 'w') as f:
        f.write(f'// {header}\n// Generated by make-sfz.py from VSCO 2 CE (CC0); do not edit by hand.\n')
        for folder, regions in sections:
            f.write(f'<control> default_path=VSCO-2-CE/{folder}/\n')
            for r in regions:
                f.write('<region> ' + ' '.join(f'{k}={v}' for k, v in r) + '\n')

BUILT = {}

def rank(mark):
    """A layer's rank: its number, or its dynamic mark's place from soft to loud."""
    return DYNAMICS.index(mark) + 1 if mark in DYNAMICS else int(mark or 1)

def instrument(root, name, folder, pattern, shift, tune):
    files = sorted(os.listdir(os.path.join(root, folder)))
    notes = defaultdict(lambda: defaultdict(list))   # key -> layer -> [file]
    for fn in files:
        m = re.search(pattern, fn)
        if not m:
            continue
        key = midi(m.group(1), m.group(2), shift) + MISNAMED.get((name, m.group(1) + m.group(2)), 0)
        notes[key][rank(m.group(3))].append(fn)
    if not notes:
        sys.exit(f'{name}: no files in {folder} match')
    spans = ranges(sorted(notes))
    regions = []
    for key in sorted(notes):
        lo, hi = spans[key]
        bands = layers(len(notes[key]))
        for band, layer in zip(bands, sorted(notes[key])):
            takes = sorted(notes[key][layer])
            for t, fn in enumerate(takes):
                r = [('sample', fn), ('pitch_keycenter', key), ('lokey', lo), ('hikey', hi),
                     ('lovel', band[0]), ('hivel', band[1])]
                if tune:
                    r.append(('tune', tune))
                if len(takes) > 1:
                    r += [('seq_length', len(takes)), ('seq_position', t + 1)]
                regions.append(r)
    write(name, [(folder, regions)], f'{name}: {folder}, keys {min(notes)}..{max(notes)}')
    BUILT[name] = (folder, regions)
    return len(regions)

def section(name, lo, hi):
    """An instrument's regions limited to keys lo..hi."""
    folder, regions = BUILT[name]
    out = []
    for r in regions:
        d = dict(r)
        a, b = max(d['lokey'], lo), min(d['hikey'], hi)
        if a <= b:
            out.append([(k, a if k == 'lokey' else b if k == 'hikey' else v) for k, v in r])
    return (folder, out)

def timpani(root):
    folder = 'Percussion/Timpani'
    hits = defaultdict(lambda: defaultdict(list))
    for fn in sorted(os.listdir(os.path.join(root, folder))):
        m = re.match(r'Timpani(\d)_Hit_v(\d)_rr(\d)_Sum\.wav$', fn)
        if m:
            hits[int(m.group(1))][int(m.group(2))].append(fn)
    keys = {d: round(p) for d, p in DRUMS.items()}
    spans = ranges(sorted(keys.values()), margin=5)
    regions = []
    for drum in sorted(hits):
        key = keys[drum]
        lo, hi = spans[key]
        for band, layer in zip(layers(len(hits[drum])), sorted(hits[drum])):
            takes = sorted(hits[drum][layer])
            for t, fn in enumerate(takes):
                r = [('sample', fn), ('pitch_keycenter', key), ('tune', round((key - DRUMS[drum]) * 100)),
                     ('lokey', lo), ('hikey', hi), ('lovel', band[0]), ('hivel', band[1])]
                if len(takes) > 1:
                    r += [('seq_length', len(takes)), ('seq_position', t + 1)]
                regions.append(r)
    write('timpani', [(folder, regions)], 'timpani: five drums, measured pitches')
    return len(regions)

def numbered(root, name, folder, pattern, zero, per):
    """Files numbered along the keyboard: one layer, one take."""
    keys = {}
    for fn in sorted(os.listdir(os.path.join(root, folder))):
        m = re.search(pattern, fn)
        if m:
            keys[zero + per * int(m.group(1))] = fn
    spans = ranges(sorted(keys))
    regions = [[('sample', keys[k]), ('pitch_keycenter', k), ('lokey', spans[k][0]), ('hikey', spans[k][1]),
                ('lovel', 1), ('hivel', 127)] for k in sorted(keys)]
    write(name, [(folder, regions)], f'{name}: {folder}, keys {min(keys)}..{max(keys)}')
    return len(regions)

def player_piano(root):
    """The second upright: three dynamics, files numbered by its MappingChart.txt."""
    folder = 'Keys/Upright Piano'
    chart = {}
    for line in open(os.path.join(root, folder, 'MappingChart.txt')):
        m = re.match(r'(\d+)=(\d+)\s*$', line)
        if m:
            chart[int(m.group(1))] = int(m.group(2))
    notes = defaultdict(dict)
    for fn in sorted(os.listdir(os.path.join(root, folder))):
        m = re.match(r'Player_dyn(\d)_rr1_(\d+)\.wav$', fn)
        if m:
            notes[chart[int(m.group(2))]][int(m.group(1))] = fn
    spans = ranges(sorted(notes))
    regions = []
    for key in sorted(notes):
        for band, dyn in zip(layers(len(notes[key])), sorted(notes[key])):
            regions.append([('sample', notes[key][dyn]), ('pitch_keycenter', key), ('lokey', spans[key][0]),
                            ('hikey', spans[key][1]), ('lovel', band[0]), ('hivel', band[1])])
    write('upright-2', [(folder, regions)], f'upright-2: {folder}, keys {min(notes)}..{max(notes)}')
    return len(regions)

def timpani_rolls(root):
    folder = 'Percussion/Timpani/Rolls'
    rolls = defaultdict(dict)
    for fn in sorted(os.listdir(os.path.join(root, folder))):
        m = re.match(r'Timpani(\d)_Roll_v(\d)_rr1_Sum\.wav$', fn)
        if m:
            rolls[int(m.group(1))][int(m.group(2))] = fn
    keys = {d: round(p) for d, p in DRUMS.items()}
    spans = ranges(sorted(keys.values()), margin=5)
    regions = []
    for drum in sorted(rolls):
        key = keys[drum]
        for band, v in zip(layers(len(rolls[drum])), sorted(rolls[drum])):
            regions.append([('sample', rolls[drum][v]), ('pitch_keycenter', key), ('tune', round((key - DRUMS[drum]) * 100)),
                            ('lokey', spans[key][0]), ('hikey', spans[key][1]), ('lovel', band[0]), ('hivel', band[1])])
    write('timpani-roll', [(folder, regions)], 'timpani-roll: five drums, measured pitches')
    return len(regions)

def hit(root, name, pattern):
    """Unpitched percussion: the recording as it is on every key, to its end."""
    folder = 'Percussion'
    hits = defaultdict(list)
    for fn in sorted(os.listdir(os.path.join(root, folder))):
        m = re.search(pattern, fn)
        if m:
            hits[rank(m.group(1))].append(fn)
    if not hits:
        sys.exit(f'{name}: no files in {folder} match')
    regions = []
    for band, v in zip(layers(len(hits)), sorted(hits)):
        takes = sorted(hits[v])
        for t, fn in enumerate(takes):
            r = [('sample', fn), ('lokey', 0), ('hikey', 127), ('pitch_keytrack', 0), ('loop_mode', 'one_shot'),
                 ('lovel', band[0]), ('hivel', band[1])]
            if len(takes) > 1:
                r += [('seq_length', len(takes)), ('seq_position', t + 1)]
            regions.append(r)
    write(name, [(folder, regions)], f'{name}: unpitched, {len(hits)} layers')
    return len(regions)

if __name__ == '__main__':
    root = sys.argv[1]
    for name, spec in FOLDERS.items():
        print(name, instrument(root, name, *spec), 'regions')
    print('timpani', timpani(root), 'regions')
    for name, spec in MORE.items():
        print(name, instrument(root, name, *spec), 'regions')
    for name, spec in NUMBERED.items():
        print(name, numbered(root, name, *spec), 'regions')
    print('upright-2', player_piano(root), 'regions')
    print('timpani-roll', timpani_rolls(root), 'regions')
    for name, pattern in HITS.items():
        print(name, hit(root, name, pattern), 'regions')
    # A string section played from one staff: cellos to E3, violas F3..B3,
    # violins from C4, as a chord is usually spread across the sections.
    parts = [section('cellos', 0, 52), section('violas', 53, 59), section('violins', 60, 127)]
    write('strings', parts, 'strings: cellos to E3 (52), violas F3..B3, violins from C4 (60)')
    print('strings', sum(len(r) for _, r in parts), 'regions')
