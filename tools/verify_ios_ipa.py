#!/usr/bin/env python3
"""Verify an unsigned iOS IPA's bundle identity and numeric Darwin version."""
from __future__ import annotations
import argparse
from pathlib import Path
import plistlib
import zipfile

from release_version import read_version


def verify_ipa(path: Path, version: str, build: str) -> dict:
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        if len(names) != len(set(names)):
            raise ValueError('duplicate IPA entries')
        plists = [n for n in names if n.startswith('Payload/') and n.endswith('.app/Info.plist')
                  and n.count('/') == 2]
        if len(plists) != 1:
            raise ValueError('expected exactly one Payload/*.app/Info.plist')
        plist = plists[0]
        app = plist.rsplit('/', 1)[0]
        info = plistlib.loads(z.read(plist))
    expected = {
        'CFBundleName': 'CrispChess', 'CFBundleDisplayName': 'CrispChess',
        'CFBundleIdentifier': 'com.crispstrobe.crispchess',
        'CFBundleShortVersionString': version, 'CFBundleVersion': build,
    }
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f'{key}: expected {value!r}, got {info.get(key)!r}')
    exe = info.get('CFBundleExecutable')
    if not isinstance(exe, str) or not exe or '/' in exe:
        raise ValueError('CFBundleExecutable must name the app executable')
    if f'{app}/{exe}' not in names:
        raise ValueError(f'app executable missing: {exe}')
    return expected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    args = parser.parse_args()
    version, build = read_version()
    try:
        result = verify_ipa(args.ipa, version, build)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        parser.exit(1, f'iOS IPA validation failed: {error}\n')
    print(f'Verified unsigned CrispChess iOS IPA {result["CFBundleShortVersionString"]} '
          f'({result["CFBundleVersion"]})')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
