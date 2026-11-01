import importlib.util
import io
import json
from pathlib import Path
import plistlib
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import verify_release_assets as vra
import verify_ios_ipa as vii


def make_tar(path, names):
    with tarfile.open(path, 'w:gz') as t:
        for name, data in names.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            t.addfile(info, io.BytesIO(data))


class ReleaseAssetTests(unittest.TestCase):
    def test_missing_asset_fails(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ValueError, 'missing'):
                vra.verify(Path(d))

    def test_ios_ipa_version_policy(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'app.ipa'
            info = {'CFBundleName': 'CrispChess', 'CFBundleDisplayName': 'CrispChess',
                    'CFBundleIdentifier': 'com.crispstrobe.crispchess',
                    'CFBundleShortVersionString': '2.3.2', 'CFBundleVersion': '19',
                    'CFBundleExecutable': 'CrispChess'}
            with zipfile.ZipFile(p, 'w') as z:
                z.writestr('Payload/CrispChess.app/Info.plist', plistlib.dumps(info))
                z.writestr('Payload/CrispChess.app/CrispChess', b'exe')
            self.assertEqual(vii.verify_ipa(p, '2.3.2', '19')['CFBundleVersion'], '19')
            with self.assertRaisesRegex(ValueError, 'CFBundleVersion'):
                vii.verify_ipa(p, '2.3.2', '20')

    def test_windows_manifest_must_match_zip(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for rel in vra.ASSETS:
                p = root / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(b'x')
            with zipfile.ZipFile(root / 'android-apk/app-release.apk', 'w') as z:
                z.writestr('AndroidManifest.xml', b'<manifest/>')
                z.writestr('classes.dex', b'dex')
            info = {'CFBundleShortVersionString': '2.3.2', 'CFBundleVersion': '19'}
            with zipfile.ZipFile(root / 'ios-unsigned/CrispChess-ios-unsigned.ipa', 'w') as z:
                z.writestr('Payload/CrispChess.app/Info.plist', plistlib.dumps(info))
            make_tar(root / 'linux-x64/CrispChess-linux-x64.tar.gz',
                     {'./crispchess': b'x', './lib/libflutter_linux_gtk.so': b'x', './data/icudtl.dat': b'x'})
            make_tar(root / 'linux-x64-frozenight/CrispChess-linux-x64-frozenight.tar.gz',
                     {'./crispchess': b'x', './lib/libflutter_linux_gtk.so': b'x', './data/icudtl.dat': b'x', './lib/libfrozenight_ffi.so': b'x'})
            make_tar(root / 'frozenight-libs/frozenight-libs.tar.gz',
                     {'frozenight-libs/libfrozenight_ffi.dylib': b'x', 'frozenight-libs/libfrozenight_ffi.a': b'x'})
            make_tar(root / 'macos-app/CrispChess-macos.tar.gz',
                     {'CrispChess.app/Contents/Info.plist': plistlib.dumps(info), 'CrispChess.app/Contents/MacOS/CrispChess': b'x'})
            make_tar(root / 'web/CrispChess-web.tar.gz',
                     {'./index.html': b'x', './flutter_bootstrap.js': b'x', './main.dart.wasm': b'x'})
            with patch.object(vra, 'read_version', return_value=('2.3.2', '19')), \
                 patch.object(vra, 'verify_zip', return_value={'files': {'a': {'sha256': 'real'}}}):
                (root / 'windows-bundle-manifest/windows-bundle-manifest.json').write_text(json.dumps({'files': {'a': {'sha256': 'fake'}}}))
                with self.assertRaisesRegex(ValueError, 'manifest'):
                    vra.verify(root)
