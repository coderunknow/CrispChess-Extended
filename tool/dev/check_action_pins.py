#!/usr/bin/env python3
"""Fail if critical release/validation workflows use mutable action refs."""
from pathlib import Path
import re
import sys

CRITICAL = [
    '.github/workflows/release.yml',
    '.github/workflows/frozenight-validation.yml',
]
SHA = re.compile(r'^[0-9a-f]{40}$')
errors = []
for name in CRITICAL:
    text = Path(name).read_text()
    for m in re.finditer(r'^\s*(?:-\s*)?uses:\s*([^\s#]+)', text, re.M):
        ref = m.group(1)
        if '@' not in ref or not SHA.fullmatch(ref.rsplit('@', 1)[1]):
            errors.append(f'{name}: mutable action ref {ref}')
if errors:
    print('\n'.join(errors))
    sys.exit(1)
print(f'Critical action pins verified in {len(CRITICAL)} workflows.')
