import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile
spec = importlib.util.spec_from_file_location('wb', Path(__file__).parents[1] / 'verify_windows_bundle.py')
wb = importlib.util.module_from_spec(spec); spec.loader.exec_module(wb)
class WindowsBundleTests(unittest.TestCase):
    def test_missing_runtime_fails(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d)/'crispchess.exe').touch(); (Path(d)/'flutter_windows.dll').touch()
            with self.assertRaisesRegex(ValueError, 'frozenight_ffi.dll'): wb.verify(Path(d))
    def test_not_pe_fails(self):
        with self.assertRaises(ValueError): wb.pe_info(b'not a library')
    def test_duplicate_zip_entries_fail(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'bad.zip'
            with zipfile.ZipFile(p,'w') as z:
                z.writestr('a','a'); z.writestr('a','b')
            with zipfile.ZipFile(p) as z: self.assertNotEqual(len(z.namelist()),len(set(z.namelist())))
