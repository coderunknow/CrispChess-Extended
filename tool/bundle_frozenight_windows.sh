#!/usr/bin/env bash
# Copy the locked-source build into a Flutter Windows output, then fail closed.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
runtime="${1:?Usage: bundle_frozenight_windows.sh WINDOWS_RELEASE_DIRECTORY}"
dll="$root/native/frozenight/target/release/frozenight_ffi.dll"
[[ -f "$dll" ]] || { echo 'Build native/frozenight with cargo build --locked --release first.' >&2; exit 1; }
cp "$dll" "$runtime/frozenight_ffi.dll"
python "$root/tools/verify_windows_bundle.py" "$runtime"
