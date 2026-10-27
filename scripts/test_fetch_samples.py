#!/usr/bin/env python3
"""Offline tests for fetch-samples.py: checksums are enforced, no network."""
import hashlib
import importlib.util
import io
import tarfile
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('fetch', Path(__file__).with_name('fetch-samples.py'))
fetch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fetch)


def digest(data):
    return hashlib.sha256(data).hexdigest()


class FetchTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.archives = self.dir / 'cache'
        self.archives.mkdir()
        self.files = {'Strings/a.wav': b'RIFFa', 'Brass/b c.wav': b'RIFFbc'}
        tar_path = self.archives / 'lib.tar.gz'
        with tarfile.open(tar_path, 'w:gz') as tar:
            for name, data in list(self.files.items()) + [('Other/unused.wav', b'x')]:
                info = tarfile.TarInfo('VSCO-2-CE-abc/' + name)
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
        self.lock = {'vsco': {'archive': 'lib.tar.gz', 'url': 'file:///nonexistent', 'archive_prefix': 'VSCO-2-CE-abc/',
                              'sha256': fetch.sha256(tar_path),
                              'files': {n: digest(d) for n, d in self.files.items()}}}

    def test_extracts_only_listed_files_and_verifies(self):
        fetch.vsco(self.lock, self.dir / 's', self.archives, False)
        for name, data in self.files.items():
            self.assertEqual((self.dir / 's' / 'VSCO-2-CE' / name).read_bytes(), data)
        self.assertFalse((self.dir / 's' / 'VSCO-2-CE' / 'Other').exists())

    def test_corrupt_archive_is_rejected(self):
        self.lock['vsco']['sha256'] = '0' * 64
        with self.assertRaises(SystemExit):
            fetch.vsco(self.lock, self.dir / 's', self.archives, False)

    def test_advisory_archive_checksum_still_checks_files(self):
        self.lock['vsco']['sha256'] = '0' * 64
        self.lock['vsco']['archive_checksum_advisory'] = True
        fetch.vsco(self.lock, self.dir / 's', self.archives, False)
        self.lock['vsco']['files']['Strings/a.wav'] = '0' * 64
        with self.assertRaises(SystemExit):
            fetch.vsco(self.lock, self.dir / 't', self.archives, False)

    def test_missing_archive_without_fetch_is_an_error(self):
        (self.archives / 'lib.tar.gz').unlink()
        with self.assertRaises(SystemExit):
            fetch.vsco(self.lock, self.dir / 's', self.archives, False)

    def test_lock_covers_every_vsco_map(self):
        import json, re
        lock = json.loads(fetch.LOCK.read_text())
        for sfz in sorted((fetch.EXAMPLES / 'vsco').glob('*.sfz')):
            path = ''
            for line in sfz.read_text().splitlines():
                for key, value in re.findall(r'(default_path|sample)=(.+?)(?=\s+\w+=|$)', line.strip()):
                    if key == 'default_path':
                        path = value
                    else:
                        name = (path + value).replace('\\', '/')
                        self.assertTrue(name.startswith('VSCO-2-CE/'), name)
                        self.assertIn(name[len('VSCO-2-CE/'):], lock['vsco']['files'], sfz.name)


if __name__ == '__main__':
    unittest.main()
