#!/usr/bin/env python3
"""Fail if critical release/validation workflows use mutable action refs.

Parse the workflow YAML instead of grepping `uses:` so quoted keys/values and
unusual-but-valid YAML cannot hide a mutable ref from the gate.
"""
from pathlib import Path
import re
import sys

import yaml

CRITICAL = [
    '.github/workflows/release.yml',
    '.github/workflows/frozenight-validation.yml',
]
SHA = re.compile(r'^[0-9a-f]{40}$')


def iter_uses(node):
    if isinstance(node, dict):
        uses = node.get('uses')
        if isinstance(uses, str):
            yield uses
        for value in node.values():
            yield from iter_uses(value)
    elif isinstance(node, list):
        for item in node:
            yield from iter_uses(item)


def check_workflow(path: Path) -> list[str]:
    try:
        data = yaml.safe_load(path.read_text())
    except yaml.YAMLError as exc:
        return [f'{path}: invalid workflow YAML: {exc}']
    errors = []
    for ref in iter_uses(data):
        if '@' not in ref or not SHA.fullmatch(ref.rsplit('@', 1)[1]):
            errors.append(f'{path}: mutable action ref {ref}')
    return errors


def main() -> int:
    errors = []
    for name in CRITICAL:
        errors.extend(check_workflow(Path(name)))
    if errors:
        print('\n'.join(errors))
        return 1
    print(f'Critical action pins verified in {len(CRITICAL)} workflows.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
