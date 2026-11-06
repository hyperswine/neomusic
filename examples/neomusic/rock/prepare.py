#!/usr/bin/env python3
"""Prepare a recorded drum kit and a direct-recorded electric guitar, and write their SFZ maps.

    python3 examples/neomusic/rock/prepare.py --samples ~/neomusic-samples --fetch
    export NEOMUSIC_SAMPLES=~/neomusic-samples

Sources (both CC0, pinned in sources.json):
  big-rusty-drums   Karoryfer Samples' Big Rusty Drums: a 24" kick, 14" snare, four toms,
                    hi-hat and cymbals, each hit recorded by several microphones
  freepats-eguitar  FreePats' Electric Guitar FSBS (direct): a Fender recorded straight
                    into an instrument input, meant to be played through an amplifier

Recordings are decoded from FLAC to WAV at their own depth and rate, unchanged
otherwise, under SAMPLES/big-rusty-drums and SAMPLES/freepats-eguitar. The maps
are written next to this script. Run with --fetch to download missing archives;
otherwise preparation is offline. Requires Python 3, FFmpeg, and bsdtar or 7z
for the guitar's .7z archive.
"""
import argparse
import hashlib
import json
import math
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent

# The drums mapped: name -> (folder under Samples/, {microphone: level in dB}).
# Levels are the library's own defaults (its Full kit program), relative to
# each drum's loudest microphone: a snare is mostly its bottom microphone, a
# cymbal mostly the overheads. Overheads are stereo; the others are mono.
SNARE = {'btm': 0.0, 'top': -8.0, 'oh': -4.4}
HAT = {'cl': 0.0, 'oh': 0.0}
TOM = {'cl': 0.0, 'oh': -3.1}
CYMBAL = {'cl': -8.0, 'oh': 0.0}
DRUMS = {
    'kick': ('kick_24/kick', {'kick': 0.0}),
    'kick-open': ('kick_24_nodamp/kick', {'kick': 0.0}),
    'snare': ('snare_14/center', SNARE),
    'snare-edge': ('snare_14/edge', SNARE),
    'snare-rimshot': ('snare_14/rimshot', SNARE),
    'snare-brush': ('snare_14/brush', SNARE),
    'sidestick': ('snare_14/sidestick', SNARE),
    'hat-tight': ('hihat_14/tc', HAT),
    'hat-closed': ('hihat_14/cl', HAT),
    'hat-loose': ('hihat_14/lc', HAT),
    'hat-quarter': ('hihat_14/qo', HAT),
    'hat-half': ('hihat_14/ho', HAT),
    'hat-open': ('hihat_14/open', HAT),
    'hat-pedal': ('hihat_14/chik', HAT),
    'hat-splash': ('hihat_14/footspl', HAT),
    'tom-14': ('tom_14/center', TOM),
    'tom-15': ('tom_15/center', TOM),
    'tom-18': ('tom_18/center', TOM),
    'tom-22': ('tom_22/center', TOM),
    'ride': ('ride_22/rd', CYMBAL),
    'ride-bell': ('ride_22/bl', CYMBAL),
    'ride-edge': ('ride_22/ed', CYMBAL),
    'crash': ('crash_17/cr', CYMBAL),
    'china': ('china_18/cn', CYMBAL),
    'sizzle-crash': ('crash_sizzle_17/cr', CYMBAL),
    'sizzle-ride': ('ride_sizzle_19/rd', CYMBAL),
    'stack': ('stack_3_layer/mid', CYMBAL),
}
HIT = re.compile(r'_vl(\d+)_rr(\d+)\.flac$')

# The guitar's lowest key. Upstream plays its lowest recording (C2) down to B1
# (35); here it reaches A1, so a riff can go where low tunings go.
GUITAR_LOWEST = 33


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def archive_for(source, cache, fetch):
    path = cache / source['archive']
    if not path.exists():
        if not fetch:
            raise ValueError(f'{path} is missing; rerun with --fetch to download {source["url"]}')
        cache.mkdir(parents=True, exist_ok=True)
        part = path.with_name(path.name + '.part')
        print(f'downloading {source["url"]}', flush=True)
        with urllib.request.urlopen(source['url']) as response, part.open('wb') as out:
            shutil.copyfileobj(response, out, 1024 * 1024)
        part.replace(path)
    digest = sha256(path)
    if digest != source['sha256']:
        if not source.get('archive_checksum_advisory'):
            raise ValueError(f'{path} has SHA-256 {digest}, expected {source["sha256"]}; delete it and retry')
        # GitHub regenerates source tarballs now and then; prepared.json
        # fingerprints every decoded file instead.
        print(f'note: {path.name} checksum {digest} differs from sources.json', flush=True)
    return path


def flac_bits(path):
    """Bits per sample, from the STREAMINFO block every FLAC file starts with."""
    with path.open('rb') as f:
        head = f.read(26)
    if head[:4] != b'fLaC':
        raise ValueError(f'{path} is not a FLAC file')
    return ((head[20] & 1) << 4 | head[21] >> 4) + 1


def decode(ffmpeg, flac):
    """FLAC to WAV beside it, at the same depth; the FLAC is removed."""
    wav = flac.with_suffix('.wav')
    part = wav.with_name(wav.name + '.part')
    codec = 'pcm_s16le' if flac_bits(flac) <= 16 else 'pcm_s24le'
    subprocess.run([ffmpeg, '-nostdin', '-v', 'error', '-y', '-i', str(flac), '-c:a', codec, '-f', 'wav', str(part)], check=True)
    part.replace(wav)
    flac.unlink()
    return wav


def decode_all(flacs):
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        raise ValueError('FFmpeg is required to decode the FLAC recordings')
    with ThreadPoolExecutor(max_workers=8) as pool:
        return list(pool.map(lambda p: decode(ffmpeg, p), flacs))


def manifest(dest, source):
    files = [dict(file=str(p.relative_to(dest)), bytes=p.stat().st_size, sha256=sha256(p)) for p in sorted(dest.rglob('*.wav'))]
    (dest / 'prepared.json').write_text(json.dumps(dict(source=source, files=files), indent=2) + '\n')
    return len(files)


# Drums ------------------------------------------------------------------------

def velocity_ranges(text):
    """An upstream mapping's velocity range for each sample it names."""
    out, lo, hi = {}, 1, 127
    for token in re.findall(r'<\w+>|\w+=[^\s<]+', re.sub(r'//.*', '', text)):
        if token == '<group>':
            lo, hi = 1, 127
        elif token.startswith('lovel='):
            lo = int(token[6:])
        elif token.startswith('hivel='):
            hi = int(token[6:])
        elif token.startswith('sample='):
            out[token[7:].replace('\\', '/').split('Samples/', 1)[-1]] = (lo, hi)
    return out


def prepare_drums(source, archive, dest, output):
    wanted = {f'{folder}/{mic}': name for name, (folder, mics) in DRUMS.items() for mic in mics}
    ranges, flacs = {}, []
    (dest / 'upstream').mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, 'r:gz') as bundle:
        for member in bundle:
            if not member.isfile():
                continue
            path = member.name.split('/', 1)[1]
            if path.startswith('Programs/mappings/') and path.endswith('.sfz'):
                ranges.update(velocity_ranges(bundle.extractfile(member).read().decode('utf-8', 'replace')))
            elif path in ('LICENSE', 'Big_Rusty_Drums_user_guide_1.000.pdf'):
                (dest / 'upstream' / path).write_bytes(bundle.extractfile(member).read())
            elif path.startswith('Samples/') and path.endswith('.flac') and path[8:].rsplit('/', 1)[0] in wanted:
                target = dest / path[8:]
                if not target.with_suffix('.wav').exists():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(bundle.extractfile(member).read())
                    flacs.append(target)
    decode_all(flacs)
    if not (dest / 'upstream' / 'LICENSE').is_file():
        raise ValueError(f'missing upstream license in {archive}')
    for name, (folder, mics) in DRUMS.items():
        write_drum(output, name, folder, mics, dest, ranges)
    print(f'Prepared big-rusty-drums: {manifest(dest, source)} WAV files, {len(DRUMS)} maps', flush=True)


def write_drum(output, name, folder, mics, dest, ranges):
    """One drum: every microphone's recording of a hit plays together, on every key."""
    lines = [f'// {name}: Big Rusty Drums {folder}, microphones ' + ', '.join(f'{m} {db:+g} dB' for m, db in mics.items()),
             '// Generated by prepare.py from Karoryfer Samples\' Big Rusty Drums (CC0); do not edit by hand.',
             '// Every key plays the drum as recorded, to the end of the recording.',
             f'<control> default_path=big-rusty-drums/{folder}/']
    shapes = {}
    for mic, db in mics.items():
        hits = {}
        for wav in sorted((dest / folder / mic).glob('*.wav')):
            m = HIT.search(wav.with_suffix('.flac').name)
            if not m:
                raise ValueError(f'unexpected recording name: {wav}')
            hits.setdefault(int(m.group(1)), []).append((int(m.group(2)), wav.name))
        if not hits:
            raise ValueError(f'no recordings in {dest / folder / mic}')
        shapes[mic] = {layer: len(takes) for layer, takes in hits.items()}
        lines.append(f'<group> lokey=0 hikey=127 pitch_keytrack=0 loop_mode=one_shot' + (f' volume={db:g}' if db else ''))
        for layer in sorted(hits):
            takes = sorted(hits[layer])
            key = f'{folder}/{mic}/{takes[0][1]}'.replace('.wav', '.flac')
            if key not in ranges:
                raise ValueError(f'upstream maps give no velocity range for {key}')
            lo, hi = ranges[key]
            for position, (_, filename) in enumerate(takes, 1):
                lines.append(f'<region> sample={mic}/{filename} lovel={lo} hivel={hi} seq_length={len(takes)} seq_position={position}')
    if len({json.dumps(s, sort_keys=True) for s in shapes.values()}) != 1:
        raise ValueError(f'{name}: microphones disagree on layers and takes: {shapes}')
    (output / f'{name}.sfz').write_text('\n'.join(lines) + '\n')


# Guitar -----------------------------------------------------------------------

def prepare_guitar(source, archive, dest, output):
    tool = shutil.which('bsdtar') or shutil.which('7z') or shutil.which('7zz')
    if not tool:
        raise ValueError('bsdtar or 7z is required to unpack ' + archive.name)
    (dest / 'upstream').mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=dest) as scratch:
        command = [tool, '-xf', str(archive), '-C', scratch] if tool.endswith('bsdtar') else [tool, 'x', '-y', f'-o{scratch}', str(archive)]
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL)
        root = next(Path(scratch).iterdir())
        sfz = next(root.glob('*.sfz'))
        for name in ('LICENSE.txt', 'README.txt', sfz.name):
            shutil.copyfile(root / name, dest / 'upstream' / name)
        flacs = []
        for flac in sorted((root / 'samples' / 'bridge').glob('*.flac')):
            target = dest / 'bridge' / flac.name
            if not target.with_suffix('.wav').exists():
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(flac, target)
                flacs.append(target)
        decode_all(flacs)
        write_guitar(output, sfz.read_text())
    count = manifest(dest, source)
    if count != source['sample_count']:
        raise ValueError(f'freepats-eguitar: expected {source["sample_count"]} recordings, found {count}')
    print(f'Prepared freepats-eguitar: {count} WAV files', flush=True)


def write_guitar(output, upstream):
    """The upstream map's keys, layers and takes. Its takes are chosen at random; here they rotate."""
    lines = [f'// guitar-direct: FreePats Electric Guitar FSBS (direct), bridge pickups, keys {GUITAR_LOWEST}..86',
             '// Generated by prepare.py from the upstream map (CC0); do not edit by hand.',
             '// A raw instrument signal: play it through a drive and a cabinet (see README.md).',
             '<control> default_path=freepats-eguitar/bridge/']
    group, groups = None, []
    for token in re.findall(r'<\w+>|\w+=[^\s<]+', re.sub(r'//.*', '', upstream)):
        if token == '<group>':
            group = dict(samples=[])
            groups.append(group)
        elif token.startswith('<'):
            continue
        elif group is not None:
            k, v = token.split('=', 1)
            if k == 'sample':
                group['samples'].append(Path(v).with_suffix('.wav').name)
            elif k in ('lokey', 'hikey', 'lovel', 'hivel', 'pitch_keycenter'):
                group[k] = int(v)
            elif k == 'key':
                group.update(lokey=int(v), hikey=int(v), pitch_keycenter=int(v))
    lowest = min(g['lokey'] for g in groups)
    for g in groups:
        if g['lokey'] == lowest:
            g['lokey'] = min(lowest, GUITAR_LOWEST)
        takes = g['samples']
        for position, filename in enumerate(takes, 1):
            lines.append(f'<region> sample={filename} pitch_keycenter={g["pitch_keycenter"]} lokey={g["lokey"]} hikey={g["hikey"]}'
                         f' lovel={g.get("lovel", 1)} hivel={g.get("hivel", 127)} loop_mode=no_loop'
                         + (f' seq_length={len(takes)} seq_position={position}' if len(takes) > 1 else ''))
    (output / 'guitar-direct.sfz').write_text('\n'.join(lines) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--samples', type=Path, required=True, help='external NEOMUSIC_SAMPLES directory')
    parser.add_argument('--archive-dir', type=Path, help='verified archive cache (default: SAMPLES/downloads)')
    parser.add_argument('--output', type=Path, default=HERE, help='directory for generated SFZ maps')
    parser.add_argument('--only', action='append', choices=['big-rusty-drums', 'freepats-eguitar'], help='prepare just this library (repeatable)')
    parser.add_argument('--fetch', action='store_true', help='download missing archives')
    args = parser.parse_args()
    samples = args.samples.expanduser().resolve()
    cache = args.archive_dir or samples / 'downloads'
    args.output.mkdir(parents=True, exist_ok=True)
    for source in json.loads((HERE / 'sources.json').read_text()):
        if args.only and source['id'] not in args.only:
            continue
        archive = archive_for(source, cache, args.fetch)
        prepare = prepare_drums if source['id'] == 'big-rusty-drums' else prepare_guitar
        prepare(source, archive, samples / source['id'], args.output)
    print(f'Ready: set NEOMUSIC_SAMPLES={samples}', flush=True)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        raise SystemExit(str(exc))
