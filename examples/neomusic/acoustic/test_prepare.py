"""Offline mapping and archive-integrity checks; no recordings or network required."""
import tempfile
import unittest
from pathlib import Path
import prepare


class MappingTests(unittest.TestCase):
    def test_complete_unique_key_velocity_coverage(self):
        for name, (_, regions) in prepare.mappings().items():
            lo, hi = (21,108) if name=='salamander' else (40,84 if name=='meta-steel' else 83)
            coverage = {}
            for r in regions:
                a,b = (r['key'],r['key']) if 'key' in r else (r['lokey'],r['hikey'])
                for key in range(a,b+1):
                    for velocity in range(r['lovel'],r['hivel']+1):
                        coverage[key,velocity] = coverage.get((key,velocity),0)+1
            expected={(key,velocity):1 for key in range(lo,hi+1) for velocity in range(1,128)}
            self.assertEqual(coverage,expected,name)

    def test_string_boundaries_and_techniques(self):
        nylon=prepare.guitar_regions('nylon')
        samples={r['key']:r['sample'] for r in nylon if r['lovel']==1}
        for key,string in [(44,'LowE'),(45,'A'),(49,'A'),(50,'D'),(55,'G'),(58,'G'),(59,'B'),(64,'HighE'),(83,'HighE')]:
            self.assertIn('_String'+string+'_',samples[key])
        self.assertTrue(all('Vel01Finger' in r['sample'] for r in prepare.guitar_regions('nylon','finger')))
        self.assertTrue(all('Finger' not in r['sample'] for r in prepare.guitar_regions('nylon','pick')))
        self.assertEqual(prepare.note_name(66,'s'),'Fs4')

    def test_piano_layers_and_roots(self):
        regions=prepare.piano_regions()
        self.assertEqual(len(regions),480)
        self.assertEqual({r['pitch_keycenter'] for r in regions},set(range(21,109,3)))
        self.assertEqual([(r['lovel'],r['hivel']) for r in regions if r['sample'].startswith('A0v')],prepare.PIANO_VELOCITIES)
        self.assertTrue(any(r['sample']=='D#4v16.wav' for r in regions))

    def test_archive_corruption_and_missing_download_fail_offline(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            source=dict(archive='test.zip',sha256='0'*64)
            with self.assertRaisesRegex(ValueError,'missing'): prepare.archive_for(source,root,False)
            (root/'test.zip').write_bytes(b'corrupt')
            with self.assertRaisesRegex(ValueError,'checksum mismatch'): prepare.archive_for(source,root,False)

    def test_maps_are_reproducible_and_paths_are_relative(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            prepare.write_maps(root)
            first={p.name:p.read_bytes() for p in root.glob('*.sfz')}
            prepare.write_maps(root)
            self.assertEqual(first,{p.name:p.read_bytes() for p in root.glob('*.sfz')})
            for body in first.values(): self.assertIn(b'default_path=neo-acoustic/',body)


if __name__=='__main__': unittest.main()
