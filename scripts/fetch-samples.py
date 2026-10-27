#!/usr/bin/env python3
"""Fetch and verify the recorded libraries the example scores use.

    python3 scripts/fetch-samples.py --samples ~/neomusic-samples
    export NEOMUSIC_SAMPLES=~/neomusic-samples

Libraries (pick with --only; default all):
  vsco      VSCO 2 Community Edition (CC0), the files examples/neomusic/vsco/*.sfz
            name, extracted to SAMPLES/VSCO-2-CE/ (about 2.3 GB download)
  rooms     the OpenAIR Jack Lyons Concert Hall impulse response (CC BY 4.0),
            made stereo by examples/neomusic/rooms/make-room.py
  acoustic  Salamander piano and Meta guitars, through
            examples/neomusic/acoustic/prepare.py --fetch (about 1.8 GB)

Every download and every extracted file is checked against SHA-256 values in
examples/neomusic/samples.lock.json. Python 3 standard library only; the rooms
and acoustic steps also run their own scripts (acoustic needs ffmpeg).
Use --archive-dir to keep downloads somewhere reusable; without --fetch a
missing archive is an error and no network is used.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXAMPLES = ROOT / 'examples' / 'neomusic'
LOCK = EXAMPLES / 'samples.lock.json'


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def fail(message):
    sys.exit('fetch-samples: ' + message)


def obtain(entry, archives, fetch):
    """The verified archive for a lock entry, downloading it if allowed."""
    path = archives / entry['archive']
    if not path.exists():
        if not fetch:
            fail(f'{path} is missing; rerun with --fetch to download {entry["url"]}')
        archives.mkdir(parents=True, exist_ok=True)
        part = path.with_suffix(path.suffix + '.part')
        print(f'downloading {entry["url"]}', flush=True)
        with urllib.request.urlopen(entry['url']) as response, open(part, 'wb') as out:
            while True:
                block = response.read(1 << 20)
                if not block:
                    break
                out.write(block)
        part.replace(path)
    digest = sha256(path)
    if digest != entry['sha256']:
        if entry.get('archive_checksum_advisory'):
            # GitHub regenerates source tarballs occasionally; the files
            # inside are what matter, and each is checked after extraction.
            print(f'note: {path.name} checksum {digest} differs from the lock; '
                  'checking each extracted file instead', flush=True)
        else:
            fail(f'{path} has SHA-256 {digest}, expected {entry["sha256"]}; delete it and retry')
    return path


def vsco(lock, samples, archives, fetch):
    entry = lock['vsco']
    files = entry['files']
    target = samples / 'VSCO-2-CE'
    missing = [name for name, digest in files.items()
               if not (target / name).exists() or sha256(target / name) != digest]
    if missing:
        archive = obtain(entry, archives, fetch)
        prefix = entry['archive_prefix']
        wanted = set(missing)
        with tarfile.open(archive) as tar:
            for member in tar:
                name = member.name[len(prefix):] if member.name.startswith(prefix) else None
                if name in wanted and member.isfile():
                    out = target / name
                    out.parent.mkdir(parents=True, exist_ok=True)
                    with tar.extractfile(member) as src, open(out, 'wb') as dst:
                        while True:
                            block = src.read(1 << 20)
                            if not block:
                                break
                            dst.write(block)
                    wanted.discard(name)
        if wanted:
            fail(f'{len(wanted)} files not found in {archive.name}, e.g. {sorted(wanted)[0]}')
    bad = [name for name, digest in files.items() if sha256(target / name) != digest]
    if bad:
        fail(f'{len(bad)} VSCO files fail their checksum, e.g. {bad[0]}')
    print(f'VSCO 2 CE: {len(files)} files verified in {target}')


def rooms(lock, samples, archives, fetch):
    for entry in lock['rooms']:
        archive = obtain(entry, archives, fetch)
        directory = samples / 'rooms' / entry['id']
        directory.mkdir(parents=True, exist_ok=True)
        source = directory / entry['archive']
        if not source.exists() or sha256(source) != entry['sha256']:
            source.write_bytes(archive.read_bytes())
        made = directory / entry['made']
        if not made.exists() or sha256(made) != entry['made_sha256']:
            subprocess.run([sys.executable, str(EXAMPLES / 'rooms' / 'make-room.py'), str(source)], check=True)
        digest = sha256(made)
        if digest != entry['made_sha256']:
            fail(f'{made} has SHA-256 {digest}, expected {entry["made_sha256"]}')
        print(f'room {entry["id"]}: verified {made}')


def acoustic(samples, archives, fetch):
    command = [sys.executable, str(EXAMPLES / 'acoustic' / 'prepare.py'), '--samples', str(samples)]
    if archives is not None:
        command += ['--archive-dir', str(archives)]
    if fetch:
        command.append('--fetch')
    subprocess.run(command, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    default = os.environ.get('NEOMUSIC_SAMPLES')
    parser.add_argument('--samples', default=default, required=default is None,
                        help='directory to fill (default: $NEOMUSIC_SAMPLES)')
    parser.add_argument('--archive-dir', help='download cache (default: SAMPLES/downloads)')
    parser.add_argument('--only', action='append', choices=['vsco', 'rooms', 'acoustic'],
                        help='fetch just this library (repeatable)')
    parser.add_argument('--fetch', action='store_true', help='download missing archives')
    args = parser.parse_args()
    samples = Path(args.samples).expanduser().resolve()
    archives = Path(args.archive_dir).expanduser().resolve() if args.archive_dir else samples / 'downloads'
    lock = json.loads(LOCK.read_text())
    chosen = args.only or ['vsco', 'rooms', 'acoustic']
    if 'vsco' in chosen:
        vsco(lock, samples, archives, args.fetch)
    if 'rooms' in chosen:
        rooms(lock, samples, archives, args.fetch)
    if 'acoustic' in chosen:
        acoustic(samples, Path(args.archive_dir).expanduser().resolve() if args.archive_dir else None, args.fetch)
    print(f'Ready: export NEOMUSIC_SAMPLES={samples}')


if __name__ == '__main__':
    main()
