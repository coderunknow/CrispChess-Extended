#!/usr/bin/env python3
"""Add Engine Lab strings to the ARB files and the tracked localisations.

This repository commits the output of `flutter gen-l10n`
(`lib/l10n/generated/*.dart`) instead of generating it during the build, and
no Flutter SDK is available in every environment that edits these strings. This
script is the alternative: it writes the same three things `gen-l10n` would —
the ARB entries and one getter in each of the three Dart files — so the tree
stays consistent without a toolchain.

What it deliberately does not do:

  * it never touches an existing key (a translated string is not overwritten);
  * it refuses to run if a generated file's class braces do not balance, rather
    than appending getters outside the class;
  * `--check` reports what is missing and exits non-zero instead of editing.

Usage:
    python3 tool/dev/l10n_add_keys.py KEY=English=Deutsch [...]
    python3 tool/dev/l10n_add_keys.py --from-file keys.json
    python3 tool/dev/l10n_add_keys.py --check KEY [KEY ...]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ARB_EN = ROOT / "lib/l10n/app_en.arb"
ARB_DE = ROOT / "lib/l10n/app_de.arb"
GEN_ABSTRACT = ROOT / "lib/l10n/generated/app_localizations.dart"
GEN_EN = ROOT / "lib/l10n/generated/app_localizations_en.dart"
GEN_DE = ROOT / "lib/l10n/generated/app_localizations_de.dart"

_GETTER = "String get {name} => {value};"


def _read_arb(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _write_arb(path: Path, data: dict) -> None:
    # Same shape gen-l10n and the existing file use: two-space indent, keys in
    # insertion order, trailing newline.
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def _dart_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")
    escaped = escaped.replace("\n", "\\n")
    return f"'{escaped}'"


def _class_span(source: str, header: str) -> tuple[int, int]:
    """Index of the body of `class X ... {` (start, end) using brace counting.

    Raises ValueError when the class is not found or its braces do not balance,
    which is the failure mode that put getters outside the class before.
    """
    match = re.search(header, source)
    if match is None:
        raise ValueError(f"class header not found: {header!r}")
    open_index = source.find("{", match.end() - 1)
    if open_index < 0:
        raise ValueError(f"no opening brace after {header!r}")
    depth = 0
    for index in range(open_index, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return open_index + 1, index
    raise ValueError(f"unbalanced braces in {header!r}")


def _insert_before_class_end(path: Path, header: str, chunk: str) -> None:
    source = path.read_text(encoding="utf-8")
    _, end = _class_span(source, header)
    path.write_text(source[:end] + chunk + source[end:], encoding="utf-8")


def _has_getter(path: Path, name: str) -> bool:
    source = path.read_text(encoding="utf-8")
    return re.search(rf"String get {re.escape(name)}\b", source) is not None


def add(entries: list[tuple[str, str, str]], check_only: bool = False) -> int:
    en = _read_arb(ARB_EN)
    de = _read_arb(ARB_DE)

    added_en: list[tuple[str, str]] = []
    added_de: list[tuple[str, str]] = []
    for name, english, german in entries:
        if name in en:
            continue
        if not check_only:
            en[name] = english
            de[name] = german
        added_en.append((name, english))
        added_de.append((name, german))

    missing_en = [n for n, _ in added_en if not _has_getter(GEN_EN, n)]
    missing_de = [n for n, _ in added_de if not _has_getter(GEN_DE, n)]
    missing_abstract = [
        n for n, _ in added_en if not _has_getter(GEN_ABSTRACT, n)
    ]

    if check_only:
        missing = []
        for name, _, _ in entries:
            if name not in en:
                print(f"missing from the ARB files: {name}")
                missing.append(name)
            elif not _has_getter(GEN_EN, name):
                print(f"missing from app_localizations_en.dart: {name}")
                missing.append(name)
            elif not _has_getter(GEN_DE, name):
                print(f"missing from app_localizations_de.dart: {name}")
                missing.append(name)
            elif not _has_getter(GEN_ABSTRACT, name):
                print(f"missing from app_localizations.dart: {name}")
                missing.append(name)
        if missing:
            print(f"{len(missing)} key(s) missing")
            return 1
        print(f"all {len(entries)} key(s) present")
        return 0

    _write_arb(ARB_EN, en)
    _write_arb(ARB_DE, de)

    abstract_chunk = "".join(
        "\n  /// `{name}`.\n  {getter}\n".format(
            name=name, getter=_GETTER.format(name=name, value="")
        ).replace(" => ;", ";")
        for name, _ in added_en
        if name in missing_abstract
    )
    if abstract_chunk:
        _insert_before_class_end(
            GEN_ABSTRACT, r"abstract class AppLocalizations \{", abstract_chunk
        )

    en_chunk = "".join(
        "\n  @override\n  "
        + _GETTER.format(name=name, value=_dart_string(value))
        + "\n"
        for name, value in added_en
        if name in missing_en
    )
    if en_chunk:
        _insert_before_class_end(
            GEN_EN, r"class AppLocalizationsEn extends AppLocalizations \{", en_chunk
        )

    de_chunk = "".join(
        "\n  @override\n  "
        + _GETTER.format(name=name, value=_dart_string(value))
        + "\n"
        for name, value in added_de
        if name in missing_de
    )
    if de_chunk:
        _insert_before_class_end(
            GEN_DE, r"class AppLocalizationsDe extends AppLocalizations \{", de_chunk
        )

    print(f"added {len(added_en)} key(s)")
    for name, _ in added_en:
        print(f"  {name}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "entries",
        nargs="*",
        help="KEY=English=Deutsch (the value may contain '='; split on the first two)",
    )
    parser.add_argument(
        "--from-file",
        type=Path,
        help="JSON object {key: [english, german]}",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="report missing keys instead of adding them",
    )
    args = parser.parse_args(argv)

    entries: list[tuple[str, str, str]] = []
    if args.from_file:
        raw = json.loads(args.from_file.read_text(encoding="utf-8"))
        for key, value in raw.items():
            if isinstance(value, dict):
                entries.append((key, value["en"], value["de"]))
            else:
                entries.append((key, value[0], value[1]))
    for raw in args.entries:
        parts = raw.split("=", 2)
        if len(parts) != 3:
            parser.error(f"expected KEY=English=Deutsch, got {raw!r}")
        entries.append((parts[0], parts[1], parts[2]))

    if not entries:
        parser.error("nothing to do: pass keys or --from-file")

    return add(entries, check_only=args.check)


if __name__ == "__main__":
    sys.exit(main())
