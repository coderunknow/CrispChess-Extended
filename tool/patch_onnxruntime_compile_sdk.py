#!/usr/bin/env python3
"""Raise the onnxruntime pub package's Android compileSdk before a build.

The onnxruntime pub package (1.4.1, the latest release) pins
`compileSdkVersion 33` in its Android module and comments that bumping it is
a breaking change for older clients. AGP 9.1.1 — the minimum Flutter 3.44.2
enforces — checks AAR metadata strictly, and the module's transitive
androidx dependencies (fragment 1.7.1, window 1.2.0, activity 1.8.1, ...)
require compileSdk >= 34, so `:onnxruntime:checkReleaseAarMetadata` fails
with "15 issues were found when checking AAR metadata".

Overriding the module from the app's Gradle files does not work here: the
Flutter plugin loader evaluates the module during `:app`'s evaluation, so
root-level `afterEvaluate` runs too late ("Cannot run
Project.afterEvaluate when the project is already evaluated") and anything
registered earlier loses to the module's own script line. Patching the pub
cache copy is the deterministic, self-contained remedy; the package itself
is unmaintained at 1.4.1, so a future package update replaces this
workaround.

Usage: python3 tool/patch_onnxruntime_compile_sdk.py [version] [sdk]
Defaults: package 1.4.1, compileSdk 36 (Flutter 3.44.2's own value).
Exit codes: 0 patched or nothing to patch; 1 on an unexpected error.
"""

import os
import sys
from pathlib import Path

PACKAGE = "onnxruntime"
DEFAULT_VERSION = "1.4.1"
DEFAULT_SDK = "36"


def _pub_cache_roots() -> list[Path]:
    roots = []
    env = os.environ.get("PUB_CACHE")
    if env:
        roots.append(Path(env))
    home = Path.home() / ".pub-cache"
    if home.exists():
        roots.append(home)
    # Windows developer layouts keep the cache inside the Flutter checkout
    # or AppData; both are covered by the two roots above in CI.
    return roots


def main() -> int:
    version = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_VERSION
    sdk = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_SDK
    package_dir = f"{PACKAGE}-{version}"

    for root in _pub_cache_roots():
        build_gradle = root / "hosted" / "pub.dev" / package_dir / "android" / "build.gradle"
        if not build_gradle.exists():
            continue
        text = build_gradle.read_text(encoding="utf-8")
        if f"compileSdkVersion {sdk}" in text:
            print(f"[patch-onnxruntime] {build_gradle} already compiles against {sdk}")
            return 0
        needle = "compileSdkVersion 33"
        if needle not in text:
            print(f"[patch-onnxruntime] {build_gradle} has no 'compileSdkVersion 33' line; "
                  "the package layout changed — patch manually or update this tool.")
            return 1
        patched = text.replace(needle, f"compileSdkVersion {sdk}")
        build_gradle.write_text(patched, encoding="utf-8")
        print(f"[patch-onnxruntime] {build_gradle}: "
              f"'{needle}' -> 'compileSdkVersion {sdk}'")
        return 0

    print(f"[patch-onnxruntime] {PACKAGE}-{version} not found in the pub cache; "
          "nothing to patch (the Android module is not being built here).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
