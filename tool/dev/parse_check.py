#!/usr/bin/env python3
"""Syntax-check every Dart file with a real tree-sitter Dart grammar.

This is NOT a substitute for `dart analyze`: it catches syntax errors only
(missing brackets, unterminated strings, malformed declarations). Type errors,
unresolved symbols and lint violations are invisible to it. It exists because
the sandbox this repository was audited in has no Dart/Flutter SDK, and a
syntax regression introduced by a blind edit would otherwise reach CI unseen.

Usage:
    python3 tool/dev/parse_check.py [paths...]   # default: lib test integration_test bin
Exit code 0 when every file parses, 1 otherwise.
"""

import os
import sys

import tree_sitter_dart
from tree_sitter import Language, Parser

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_PATHS = ["lib", "test", "integration_test", "bin", "test_driver"]

LANGUAGE = Language(tree_sitter_dart.language())


def dart_files(paths):
    for path in paths:
        full = os.path.join(ROOT, path)
        if os.path.isfile(full):
            if full.endswith(".dart"):
                yield full
            continue
        for dirpath, _dirnames, filenames in os.walk(full):
            for name in sorted(filenames):
                if name.endswith(".dart"):
                    yield os.path.join(dirpath, name)


def first_error(node):
    """Deepest-first walk for the first node flagged as an error."""
    stack = [node]
    while stack:
        current = stack.pop()
        if current.type == "ERROR" or current.is_missing:
            return current
        stack.extend(current.children)
    return None


def main(argv):
    paths = argv[1:] or DEFAULT_PATHS
    parser = Parser(LANGUAGE)
    total = 0
    failures = []
    for path in dart_files(paths):
        total += 1
        source = open(path, "rb").read()
        tree = parser.parse(source)
        if tree.root_node.has_error:
            bad = first_error(tree.root_node) or tree.root_node
            row, col = bad.start_point
            line = source.split(b"\n")[row].decode("utf8", "replace")
            failures.append(
                f"{os.path.relpath(path, ROOT)}:{row + 1}:{col + 1}: {bad.type}\n    {line.strip()}"
            )

    print(f"parsed {total} Dart files")
    if failures:
        print(f"\n{len(failures)} file(s) with syntax errors:")
        for failure in failures:
            print("  " + failure)
        return 1
    print("no syntax errors")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
