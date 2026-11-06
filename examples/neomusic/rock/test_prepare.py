#!/usr/bin/env python3
"""Offline checks of the committed drum and guitar maps and of prepare.py's parsing. No recordings needed."""
import re
import sys
import tempfile
import unittest
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import prepare  # noqa: E402


def regions(path):
    """Each region's opcodes, with its group's."""
    out, group = [], {}
    for line in path.read_text().splitlines():
        line = line.split('//')[0].strip()
        if line.startswith('<group>'):
            group = dict(t.split('=', 1) for t in line.split()[1:])
        elif line.startswith('<region>'):
            out.append({**group, **dict(t.split('=', 1) for t in line.split()[1:])})
    return out


def tiles(spans, lo, hi):
    """Whether inclusive spans cover lo..hi exactly once."""
    at = lo
    for a, b in sorted(set(spans)):
        if a != at:
            return False
        at = b + 1
    return at == hi + 1


class Maps(unittest.TestCase):
    def test_every_drum_is_mapped(self):
        self.assertEqual({p.stem for p in HERE.glob('*.sfz')}, set(prepare.DRUMS) | {'guitar-direct'})

    def test_drums_play_as_recorded_at_every_velocity_and_take(self):
        for name, (folder, mics) in prepare.DRUMS.items():
            rs = regions(HERE / f'{name}.sfz')
            by_mic = defaultdict(list)
            for r in rs:
                self.assertEqual((r['lokey'], r['hikey'], r['pitch_keytrack'], r['loop_mode']), ('0', '127', '0', 'one_shot'), name)
                by_mic[r['sample'].split('/')[0]].append(r)
            self.assertEqual(set(by_mic), set(mics), name)
            shapes = set()
            for mic, group in by_mic.items():
                self.assertEqual({float(r.get('volume', 0)) for r in group}, {mics[mic]}, name)
                layers = defaultdict(list)
                for r in group:
                    layers[(int(r['lovel']), int(r['hivel']))].append((int(r['seq_position']), int(r['seq_length'])))
                self.assertTrue(tiles(layers, 1, 127), f'{name} {mic}: velocity layers leave a gap or overlap')
                for takes in layers.values():
                    self.assertEqual(sorted(p for p, _ in takes), list(range(1, len(takes) + 1)), name)
                    self.assertEqual({n for _, n in takes}, {len(takes)}, name)
                shapes.add(tuple(sorted((k, len(v)) for k, v in layers.items())))
            self.assertEqual(len(shapes), 1, f'{name}: microphones disagree')

    def test_guitar_covers_its_range_at_every_velocity(self):
        rs = regions(HERE / 'guitar-direct.sfz')
        self.assertEqual(len(rs), 120)
        for key in range(35, 87):
            here = [r for r in rs if int(r['lokey']) <= key <= int(r['hikey'])]
            self.assertTrue(tiles([(int(r['lovel']), int(r['hivel'])) for r in here], 1, 127), f'key {key}')
            for span in {(r['lovel'], r['hivel']) for r in here}:
                takes = sorted(int(r['seq_position']) for r in here if (r['lovel'], r['hivel']) == span)
                self.assertEqual(takes, [1, 2, 3, 4], f'key {key}')


class Parsing(unittest.TestCase):
    def test_velocity_ranges_follow_groups(self):
        text = '<group>\nhivel=9\namp_velcurve_9=1\n<region>\nsample=../Samples/a/kick/k_vl1_rr1.flac\n' \
               '//====\n<group>\nlovel=10\nhivel=18\n<region> sample=..\\Samples\\a\\kick\\k_vl2_rr1.flac seq_position=2\n'
        self.assertEqual(prepare.velocity_ranges(text), {'a/kick/k_vl1_rr1.flac': (1, 9), 'a/kick/k_vl2_rr1.flac': (10, 18)})

    def test_flac_depth_is_read_from_the_header(self):
        for bits in (16, 24):
            info = (44100 << 44) | (1 << 41) | ((bits - 1) << 36) | 1000      # rate, channels - 1, bits - 1, samples
            head = b'fLaC' + bytes([0x80, 0, 0, 34]) + bytes(10) + info.to_bytes(8, 'big') + bytes(16)
            with tempfile.NamedTemporaryFile(suffix='.flac') as f:
                f.write(head)
                f.flush()
                self.assertEqual(prepare.flac_bits(Path(f.name)), bits)

    def test_a_wrong_archive_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            archive = Path(d) / 'x.7z'
            archive.write_bytes(b'not the archive')
            source = dict(archive='x.7z', url='file:///nowhere', sha256='0' * 64)
            with self.assertRaises(ValueError):
                prepare.archive_for(source, Path(d), False)
            with self.assertRaises(ValueError):
                prepare.archive_for(dict(source, archive='missing.7z'), Path(d), False)


if __name__ == '__main__':
    unittest.main()
