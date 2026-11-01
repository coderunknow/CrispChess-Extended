"""Fail closed on an incomplete Windows x64 release.

Checks the actual ZIP/directory, every required PE image, Frozenight ABI-2
exports, app-local Visual C++ runtime files and non-system import closure.
This is a packaging gate, not a claim of Windows 10 runtime verification.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import tempfile
import zipfile

EXPORTS = {
    'frozenight_abi_version', 'frozenight_create', 'frozenight_destroy',
    'frozenight_set_position_v2', 'frozenight_search_bounded_v2',
    'frozenight_get_best_move_v2', 'frozenight_get_nodes_v2',
    'frozenight_get_score_v2', 'frozenight_get_depth_v2',
}
REQUIRED = ('crispchess.exe', 'flutter_windows.dll', 'frozenight_ffi.dll')
VC_RUNTIME = ('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')
OPENMP_RUNTIME = ('vcomp140.dll',)
RUNTIME_IMAGES = VC_RUNTIME + OPENMP_RUNTIME
# Windows 10 ships the UCRT and these API sets. The VC++ 2015-2022 runtime is
# NOT assumed: CMake InstallRequiredSystemLibraries copies the redistributable
# DLLs beside the executable and this verifier requires them.
SYSTEM = {
    'kernel32.dll', 'kernelbase.dll', 'ntdll.dll', 'user32.dll', 'advapi32.dll',
    'bcrypt.dll', 'crypt32.dll', 'ws2_32.dll', 'userenv.dll', 'shell32.dll',
    'ole32.dll', 'oleaut32.dll', 'uuid.dll', 'secur32.dll', 'winmm.dll',
    'dbghelp.dll', 'dwmapi.dll', 'version.dll', 'gdi32.dll', 'comdlg32.dll',
    'comctl32.dll', 'shlwapi.dll', 'setupapi.dll', 'wintrust.dll', 'psapi.dll',
    'iphlpapi.dll', 'cryptbase.dll', 'sspcli.dll', 'normaliz.dll', 'powrprof.dll',
    'bcryptprimitives.dll', 'ucrtbase.dll', 'msvcrt.dll', 'winhttp.dll',
    'wininet.dll', 'oleacc.dll', 'uxtheme.dll', 'imm32.dll', 'msimg32.dll',
    'winspool.drv', 'combase.dll', 'rpcrt4.dll', 'sechost.dll', 'mswsock.dll',
    'nsi.dll', 'wtsapi32.dll', 'user32.dll', 'gdiplus.dll', 'd3d11.dll',
    'd3d9.dll', 'opengl32.dll', 'dxgi.dll', 'dcomp.dll', 'windowscodecs.dll',
    'propsys.dll', 'mf.dll', 'mfplat.dll', 'mfreadwrite.dll',
    'uiautomationcore.dll',
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
    for required in REQUIRED + RUNTIME_IMAGES:
        if required not in files:
            raise ValueError(f'missing {required}')
    images = {}
    all_imports = set()
    for name, path in sorted(files.items()):
        if not name.endswith(('.exe', '.dll')):
            continue
        exports, imports = pe_info(path.read_bytes())
        images[name] = {'exports': sorted(exports), 'imports': sorted(imports)}
        all_imports.update(imports)
    for required in REQUIRED:
        if required not in images:
            raise ValueError(f'{required} was not validated as an x64 PE image')
    missing = EXPORTS - set(images['frozenight_ffi.dll']['exports'])
    if missing:
        raise ValueError(f'missing Frozenight exports: {sorted(missing)}')
    system = SYSTEM | {n for n in all_imports if n.startswith('api-ms-win-') or n.startswith('ext-ms-win-')}
    unresolved = sorted(all_imports - system - set(files))
    if unresolved:
        raise ValueError(f'unbundled non-system DLL imports: {unresolved}')
    return {
        'schema': 2, 'architecture': 'x64',
        'files': {name: {'bytes': p.stat().st_size,
                         'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                  for name, p in sorted(files.items())},
        'peImages': images,
        'frozenightExports': images['frozenight_ffi.dll']['exports'],
        'frozenightImports': images['frozenight_ffi.dll']['imports'],
        'visualCppRuntime': list(VC_RUNTIME),
        'openMpRuntime': list(OPENMP_RUNTIME),
        'runtimeVerification': 'packaging/import-closure only; see workflow runtime probes',
    }


def verify_zip(path: Path):
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        normalized = [n.replace('\\', '/').lower() for n in names]
        if len(normalized) != len(set(normalized)):
            raise ValueError('duplicate ZIP entries')
        for n in names:
            p = PurePosixPath(n.replace('\\', '/'))
            if p.is_absolute() or '..' in p.parts or '\\' in n or (len(p.parts) and ':' in p.parts[0]):
                raise ValueError(f'unsafe ZIP path: {n}')
        with tempfile.TemporaryDirectory() as d:
            z.extractall(d)
            return verify(Path(d))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', type=Path)
    parser.add_argument('--manifest', type=Path)
    args = parser.parse_args()
    result = verify(args.path) if args.path.is_dir() else verify_zip(args.path)
    text = json.dumps(result, indent=2) + '\n'
    if args.manifest:
        args.manifest.write_text(text)
    print(f'Windows bundle verified: {len(result["files"])} files; '
          f'{len(result["peImages"])} x64 PE images; Frozenight ABI 2 and VC++ runtime present.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, zipfile.BadZipFile) as e:
        raise SystemExit(f'Windows bundle verification FAILED: {e}')
