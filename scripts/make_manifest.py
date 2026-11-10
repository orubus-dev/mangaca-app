#!/usr/bin/env python3
"""Builds the MANGACA self-update manifest (release/updates.json).

Latest release = the freshly built mangaca.apk (+ sha256/size). If the
previous release carries a downloadable mangaca.apk and its version code is
lower than this build's, a bsdiff delta (mangaca-delta.bsdiff) is produced so
devices on the previous code can update with a few MB instead of the full
APK. Everything is best-effort: no previous APK → manifest without deltas.
"""
import json
import os
import subprocess
import sys

REPO = os.environ.get('REPO', 'orubus-dev/mangaca-app')
TAG = os.environ.get('TAG', 'latest')
GH_TOKEN = os.environ.get('GH_TOKEN', '')

BASE_ASSET = f'https://github.com/{REPO}/releases/download/{TAG}'


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True)


def pubspec_version():
    for line in open('pubspec.yaml'):
        if line.startswith('version:'):
            v = line.split(':', 1)[1].strip()
            name, _, code = v.partition('+')
            return name, int(code or 1)
    return '0.0.0', 1


def apk_sha(path):
    out = sh('sha256sum', path).stdout.strip()
    return out.split(' ')[0] if out else ''


def main():
    version, code = pubspec_version()
    apk_sha_new = apk_sha('mangaca.apk')
    apk_size_new = os.path.getsize('mangaca.apk')

    manifest = {
        'latest': {
            'version': version,
            'code': code,
            'name': version,
            'url': f'{BASE_ASSET}/mangaca.apk',
            'sha256': apk_sha_new,
            'size': apk_size_new,
            'notes': f'MANGACA {version} — Read Beyond The Illusion',
        },
        'deltas': {},
    }

    # previous release APK (best effort)
    prev_apk = 'prev/mangaca.apk'
    env = {**os.environ, 'GH_TOKEN': GH_TOKEN}
    subprocess.run(
        ['gh', 'release', 'download', '--repo', REPO, '--pattern', 'mangaca.apk',
         '--dir', 'prev', '--clobber'],
        capture_output=True, text=True, env=env,
    )
    have_prev = os.path.exists(prev_apk)
    prev_code = 0
    if have_prev:
        # the committed manifest is the source of truth for the previous code
        try:
            j = json.load(open('release/updates.json'))
            prev_code = int(j.get('latest', {}).get('code', 0))
        except Exception:
            prev_code = 0

    if have_prev and 0 < prev_code < code:
        try:
            import bsdiff4
            bsdiff4.file_diff(prev_apk, 'mangaca.apk', 'mangaca-delta.bsdiff')
            manifest['deltas'][str(prev_code)] = {
                'from': prev_code,
                'to': code,
                'url': f'{BASE_ASSET}/mangaca-delta.bsdiff',
                'sha256': apk_sha('mangaca-delta.bsdiff'),
                'size': os.path.getsize('mangaca-delta.bsdiff'),
            }
            print(f'delta {prev_code} -> {code}: {manifest["deltas"][str(prev_code)]["size"]} bytes')
        except Exception as e:
            print(f'delta skipped: {e}')
    else:
        print('no previous APK / no lower code — manifest without deltas')

    os.makedirs('release', exist_ok=True)
    with open('release/updates.json', 'w') as f:
        json.dump(manifest, f, indent=2)
    print('manifest written')


if __name__ == '__main__':
    sys.exit(main())
