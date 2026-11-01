#!/usr/bin/env python3
"""Fail closed unless every mandatory release asset is present and structurally valid."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import tarfile
import zipfile

from release_version import read_version
from verify_windows_bundle import verify_zip

ASSETS = {
    'android-apk/app-release.apk': 'app-release.apk',
    'ios-unsigned/CrispChess-ios-unsigned.ipa': 'CrispChess-ios-unsigned.ipa',
    'linux-x64/CrispChess-linux-x64.tar.gz': 'CrispChess-linux-x64.tar.gz',
    'linux-x64-frozenight/CrispChess-linux-x64-frozenight.tar.gz': 'CrispChess-linux-x64-frozenight.tar.gz',
    'frozenight-libs/frozenight-libs.tar.gz': 'frozenight-libs.tar.gz',
    'macos-app/CrispChess-macos.tar.gz': 'CrispChess-macos.tar.gz',
    'windows-x64/CrispChess-windows-x64.zip': 'CrispChess-windows-x64.zip',
    'web/CrispChess-web.tar.gz': 'CrispChess-web.tar.gz',
    'windows-bundle-manifest/windows-bundle-manifest.json': 'windows-bundle-manifest.json',
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def tar_names(path: Path) -> list[str]:
    with tarfile.open(path, 'r:gz') as t:
        members = t.getmembers()
        for m in members:
            p = Path(m.name)
            if p.is_absolute() or '..' in p.parts:
                raise ValueError(f'unsafe tar path: {m.name}')
        return [m.name for m in members]


def require(names, expected, archive):
    missing = [n for n in expected if n not in names]
    if missing:
        raise ValueError(f'{archive}: missing {missing}')


def verify(root: Path) -> dict:
    version, build = read_version()
    result = {'version': version, 'build': build, 'assets': {}}
    paths = {}
    for rel, name in ASSETS.items():
        path = root / rel
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f'missing or empty release asset: {rel}')
        paths[name] = path
        result['assets'][name] = {'bytes': path.stat().st_size, 'sha256': sha256(path)}
    with zipfile.ZipFile(paths['app-release.apk']) as z:
        require(z.namelist(), ['AndroidManifest.xml', 'classes.dex'], 'APK')
    with zipfile.ZipFile(paths['CrispChess-ios-unsigned.ipa']) as z:
        names = z.namelist()
        plists = [n for n in names if n.startswith('Payload/') and n.endswith('.app/Info.plist') and n.count('/') == 2]
        if len(plists) != 1:
            raise ValueError('IPA must contain one app Info.plist')
        info = plistlib.loads(z.read(plists[0]))
        if info.get('CFBundleShortVersionString') != version or info.get('CFBundleVersion') != build:
            raise ValueError('IPA Darwin version does not match pubspec policy')
    for name, frozen in [('CrispChess-linux-x64.tar.gz', False), ('CrispChess-linux-x64-frozenight.tar.gz', True)]:
        names = tar_names(paths[name])
        require(names, ['./crispchess', './lib/libflutter_linux_gtk.so', './data/icudtl.dat'], name)
        if frozen:
            require(names, ['./lib/libfrozenight_ffi.so'], name)
    names = tar_names(paths['frozenight-libs.tar.gz'])
    require(names, ['frozenight-libs/libfrozenight_ffi.dylib', 'frozenight-libs/libfrozenight_ffi.a'], 'native libs')
    names = tar_names(paths['CrispChess-macos.tar.gz'])
    plist = 'CrispChess.app/Contents/Info.plist'
    require(names, [plist, 'CrispChess.app/Contents/MacOS/CrispChess'], 'macOS app')
    with tarfile.open(paths['CrispChess-macos.tar.gz'], 'r:gz') as t:
        info = plistlib.load(t.extractfile(plist))
    if info.get('CFBundleShortVersionString') != version or info.get('CFBundleVersion') != build:
        raise ValueError('macOS Darwin version does not match pubspec policy')
    names = tar_names(paths['CrispChess-web.tar.gz'])
    require(names, ['./index.html', './flutter_bootstrap.js'], 'web')
    if './main.dart.wasm' not in names and './main.dart.js' not in names:
        raise ValueError('web archive has neither WASM nor JavaScript entrypoint')
    windows = verify_zip(paths['CrispChess-windows-x64.zip'])
    manifest = json.loads(paths['windows-bundle-manifest.json'].read_text())
    if manifest.get('files') != windows['files']:
        raise ValueError('Windows manifest does not match the delivered ZIP file hashes')
    result['windowsZipSha256'] = result['assets']['CrispChess-windows-x64.zip']['sha256']
    result['windowsFiles'] = len(windows['files'])
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifacts', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    try:
        result = verify(args.artifacts)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, tarfile.TarError) as error:
        parser.exit(1, f'Release asset verification FAILED: {error}\n')
    text = json.dumps(result, indent=2) + '\n'
    if args.report:
        args.report.write_text(text)
    print(f'Verified {len(result["assets"])} mandatory release assets; Windows ZIP {result["windowsZipSha256"]}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
