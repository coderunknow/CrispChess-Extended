"""Fail closed on an incomplete Windows x64 release (stdlib only).

Checks the actual ZIP/directory, PE architecture, Frozenight ABI exports and
non-system import closure. This is a packaging gate, not a claim of Windows 10
runtime verification. Usage: python tools/verify_windows_bundle.py PATH
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import zipfile

EXPORTS = {
    'frozenight_abi_version', 'frozenight_create', 'frozenight_destroy',
    'frozenight_set_position_v2', 'frozenight_search_bounded_v2',
    'frozenight_get_best_move_v2', 'frozenight_get_nodes_v2',
    'frozenight_get_score_v2', 'frozenight_get_depth_v2',
}
SYSTEM = {
    'kernel32.dll', 'kernelbase.dll', 'ntdll.dll', 'user32.dll', 'advapi32.dll',
    'bcrypt.dll', 'crypt32.dll', 'ws2_32.dll', 'userenv.dll', 'shell32.dll',
    'ole32.dll', 'oleaut32.dll', 'uuid.dll', 'secur32.dll', 'winmm.dll',
    'dbghelp.dll', 'dwmapi.dll', 'version.dll', 'gdi32.dll', 'comdlg32.dll',
    'comctl32.dll', 'shlwapi.dll', 'setupapi.dll', 'wintrust.dll', 'psapi.dll',
    'iphlpapi.dll', 'cryptbase.dll', 'sspcli.dll', 'normaliz.dll', 'powrprof.dll', 'bcryptprimitives.dll',
    'api-ms-win-crt-runtime-l1-1-0.dll', 'vcruntime140.dll', 'vcruntime140_1.dll',
    'msvcp140.dll', 'ucrtbase.dll', 'msvcrt.dll', 'winhttp.dll', 'wininet.dll',
}


def pe_info(data: bytes):
    """Parse with the maintained PE parser; never hand-roll import-table offsets."""
    try:
        import pefile
    except ImportError as e:
        raise ValueError('install tools/requirements-windows.txt before verification') from e
    try:
        pe = pefile.PE(data=data)
    except pefile.PEFormatError as e:
        raise ValueError(str(e)) from e
    try:
        if pe.FILE_HEADER.Machine != 0x8664 or pe.OPTIONAL_HEADER.Magic != 0x20b:
            raise ValueError('not an x64 PE32+ image')
        exports = {e.name.decode('ascii') for e in getattr(getattr(pe, 'DIRECTORY_ENTRY_EXPORT', None), 'symbols', []) if e.name}
        imports = [e.dll.decode('ascii').lower() for e in getattr(pe, 'DIRECTORY_ENTRY_IMPORT', [])]
        return exports, imports
    finally:
        pe.close()


def verify(root: Path):
    files = {p.relative_to(root).as_posix().lower(): p for p in root.rglob('*') if p.is_file()}
    for required in ('crispchess.exe', 'flutter_windows.dll', 'frozenight_ffi.dll'):
        if required not in files: raise ValueError(f'missing {required}')
    exports, imports = pe_info(files['frozenight_ffi.dll'].read_bytes())
    missing = EXPORTS-exports
    if missing: raise ValueError(f'missing Frozenight exports: {sorted(missing)}')
    # Flutter distributes its own UCRT/VC runtime beside the executable.
    system = SYSTEM | {n for n in imports if n.startswith('api-ms-win-') or n.startswith('ext-ms-win-')}
    unresolved = sorted(set(imports)-system-set(files))
    if unresolved: raise ValueError(f'unbundled non-system DLL imports: {unresolved}')
    return {
        'schema': 1, 'architecture': 'x64',
        'files': {name: {'bytes': p.stat().st_size,
                         'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                  for name,p in sorted(files.items())},
        'frozenightExports': sorted(exports), 'frozenightImports': sorted(imports),
        'runtimeVerification': 'not performed by this packaging check',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', type=Path)
    parser.add_argument('--manifest', type=Path)
    args = parser.parse_args()
    if args.path.is_dir(): result = verify(args.path)
    else:
        with zipfile.ZipFile(args.path) as z:
            names = z.namelist()
            if len(names) != len(set(names)): raise ValueError('duplicate ZIP entries')
            for n in names:
                p = Path(n)
                if p.is_absolute() or '..' in p.parts or '\\' in n:
                    raise ValueError(f'unsafe ZIP path: {n}')
            with tempfile.TemporaryDirectory() as d:
                z.extractall(d); result = verify(Path(d))
    text = json.dumps(result, indent=2)+'\n'
    if args.manifest: args.manifest.write_text(text)
    print(f'Windows bundle verified: {len(result["files"])} files; Frozenight ABI 2 exports present.')


if __name__ == '__main__':
    try: main()
    except (ValueError, KeyError, OSError, zipfile.BadZipFile) as e:
        raise SystemExit(f'Windows bundle verification FAILED: {e}')
