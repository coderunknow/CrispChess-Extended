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
import struct
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
    'iphlpapi.dll', 'cryptbase.dll', 'sspcli.dll', 'normaliz.dll', 'powrprof.dll',
    'api-ms-win-crt-runtime-l1-1-0.dll', 'vcruntime140.dll', 'vcruntime140_1.dll',
    'msvcp140.dll', 'ucrtbase.dll', 'msvcrt.dll', 'winhttp.dll', 'wininet.dll',
}


def u16(b, p): return struct.unpack_from('<H', b, p)[0]
def u32(b, p): return struct.unpack_from('<I', b, p)[0]


def pe_info(data: bytes):
    if data[:2] != b'MZ': raise ValueError('not MZ')
    pe = u32(data, 0x3c)
    if data[pe:pe+4] != b'PE\0\0' or u16(data, pe+4) != 0x8664:
        raise ValueError('not an x64 PE image')
    optional = pe + 24
    magic = u16(data, optional)
    if magic != 0x20b: raise ValueError('not PE32+');
    section_count = u16(data, pe+6)
    optional_size = u16(data, pe+20)
    sections = optional + optional_size
    size = 40
    ranges = []
    for i in range(section_count):
        p = sections + (size+24)*i
        virtual, raw_size, raw = u32(data,p+12), u32(data,p+8), u32(data,p+20)
        ranges.append((virtual, virtual, raw))
    def offset(rva):
        for base, length, raw in ranges:
            if base <= rva < base+length: return raw+rva-base
        raise ValueError(f'RVA outside image: {rva}')
    def name(rva):
        p = offset(rva); end = data.index(b'\0',p)
        return data[p:end].decode('ascii')
    export_rva = u32(data, optional+112+8*0)
    imports = []
    import_rva = u32(data, optional+112+8*1)
    if import_rva:
        p = offset(import_rva)
        while u32(data,p+12):
            imports.append(name(u32(data,p+12)).lower()); p += 20
    exports = set()
    if export_rva:
        p = offset(export_rva); names = offset(u32(data,p+32))
        for i in range(u32(data,p+24)):
            exports.add(name(u32(data,names+4*i)))
    return exports, imports


def verify(root: Path):
    files = {p.relative_to(root).as_posix().lower(): p for p in root.rglob('*') if p.is_file()}
    for required in ('crispchess.exe', 'flutter_windows.dll', 'frozenight_ffi.dll'):
        if required not in files: raise ValueError(f'missing {required}')
    exports, imports = pe_info(files['frozenight_ffi.dll'].read_bytes())
    missing = EXPORTS-exports
    if missing: raise ValueError(f'missing Frozenight exports: {sorted(missing)}')
    # Flutter distributes its own UCRT/VC runtime beside the executable.
    unresolved = sorted(set(imports)-SYSTEM-set(files))
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
    except (ValueError, KeyError, OSError, struct.error, zipfile.BadZipFile) as e:
        raise SystemExit(f'Windows bundle verification FAILED: {e}')
