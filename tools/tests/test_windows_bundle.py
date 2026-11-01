import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('wb', Path(__file__).parents[1] / 'verify_windows_bundle.py')
wb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wb)


class WindowsBundleTests(unittest.TestCase):
    def test_missing_runtime_fails(self):
        with tempfile.TemporaryDirectory() as d:
            for name in wb.REQUIRED:
                (Path(d) / name).touch()
            with self.assertRaisesRegex(ValueError, 'vcruntime140.dll'):
                wb.verify(Path(d))

    def test_not_pe_fails(self):
        with self.assertRaisesRegex(ValueError, 'DOS Header'):
            wb.pe_info(b'not a library')

    def test_missing_pefile_is_not_hidden_as_invalid_pe(self):
        with patch.dict('sys.modules', {'pefile': None}):
            with self.assertRaisesRegex(ValueError, 'requirements-windows'):
                wb.pe_info(b'MZ')

    def test_all_required_images_are_parsed_and_x64(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for name in wb.REQUIRED + wb.RUNTIME_IMAGES:
                (root / name).write_bytes(b'fake')
            calls = []
            def fake(data):
                calls.append(data)
                return (set(wb.EXPORTS) if len(calls) == 3 else set(), ['kernel32.dll'])
            with patch.object(wb, 'pe_info', side_effect=fake):
                result = wb.verify(root)
            self.assertEqual(len(calls), 7)
            self.assertEqual(result['architecture'], 'x64')
            self.assertEqual(set(result['peImages']), set(wb.REQUIRED + wb.RUNTIME_IMAGES))

    def test_wrong_architecture_fails(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for name in wb.REQUIRED + wb.RUNTIME_IMAGES:
                (root / name).write_bytes(b'fake')
            def fake(data):
                if data == b'crispchess.exe':
                    raise ValueError('not an x64 PE32+ image')
                return (set(wb.EXPORTS), [])
            (root / 'crispchess.exe').write_bytes(b'crispchess.exe')
            with patch.object(wb, 'pe_info', side_effect=fake):
                with self.assertRaisesRegex(ValueError, 'x64'):
                    wb.verify(root)

    def test_vc_runtime_is_not_a_system_import(self):
        self.assertFalse(set(wb.VC_RUNTIME) & wb.SYSTEM)
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for name in wb.REQUIRED + wb.RUNTIME_IMAGES:
                (root / name).write_bytes(b'fake')
            def fake(data):
                return (set(wb.EXPORTS), ['msvcp140.dll', 'vcruntime140.dll'])
            with patch.object(wb, 'pe_info', side_effect=fake):
                result = wb.verify(root)
            self.assertIn('msvcp140.dll', result['files'])

    def test_unbundled_non_system_import_fails(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for name in wb.REQUIRED + wb.RUNTIME_IMAGES:
                (root / name).write_bytes(b'fake')
            def fake(data):
                return (set(wb.EXPORTS), ['missing_dep.dll'])
            with patch.object(wb, 'pe_info', side_effect=fake):
                with self.assertRaisesRegex(ValueError, 'unbundled non-system DLL imports'):
                    wb.verify(root)

    def test_missing_frozenight_export_fails(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for name in wb.REQUIRED + wb.RUNTIME_IMAGES:
                (root / name).write_bytes(b'fake')
            def fake(data):
                return (set(), ['kernel32.dll'])
            with patch.object(wb, 'pe_info', side_effect=fake):
                with self.assertRaisesRegex(ValueError, 'missing Frozenight exports'):
                    wb.verify(root)

    def test_duplicate_zip_entries_fail(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'bad.zip'
            with zipfile.ZipFile(p, 'w') as z:
                z.writestr('a', 'a')
                z.writestr('a', 'b')
            with self.assertRaisesRegex(ValueError, 'duplicate'):
                wb.verify_zip(p)

    def test_unsafe_zip_paths_fail(self):
        for name in ('../evil', '/evil', 'a/../../evil', 'C:/evil', 'a\\..\\evil'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as d:
                p = Path(d) / 'bad.zip'
                with zipfile.ZipFile(p, 'w') as z:
                    z.writestr(name, 'x')
                with self.assertRaisesRegex(ValueError, 'unsafe'):
                    wb.verify_zip(p)

    def test_delay_imports_are_included_in_closure(self):
        import sys
        import types

        class Entry:
            def __init__(self, name):
                self.dll = name.encode('ascii')

        class FakePE:
            class FILE_HEADER:
                Machine = 0x8664
            class OPTIONAL_HEADER:
                Magic = 0x20B
            DIRECTORY_ENTRY_EXPORT = None
            DIRECTORY_ENTRY_IMPORT = [Entry('KERNEL32.dll')]
            DIRECTORY_ENTRY_DELAY_IMPORT = [Entry('missing_delay.dll')]
            def close(self):
                pass

        fake = types.SimpleNamespace(PE=lambda data: FakePE(), PEFormatError=Exception)
        with patch.dict(sys.modules, {'pefile': fake}):
            exports, imports = wb.pe_info(b'fake')
        self.assertIn('kernel32.dll', imports)
        self.assertIn('missing_delay.dll', imports)
