#!/usr/bin/env python3
"""Repeat failed Dart tests as GitHub check annotations.

Reads the JSON file written by `flutter test --file-reporter json:<path>` and
prints one `::error::` workflow command per failed test (name, error, start of
the stack). Job logs are not always readable from where a fix is made; the
annotations are. Informational only: the exit status is always 0, so this can
neither fail nor rescue a job — the test step's own status decides.
"""
import json
import sys
from pathlib import Path


def escape(text: str) -> str:
    return text.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')


def main(argv):
    if len(argv) < 2:
        return 0
    title = argv[2] if len(argv) > 2 else 'Test failure'
    path = Path(argv[1])
    if not path.exists():
        print(f'::warning title={title}::no test report at {path}')
        return 0
    names, files, errors, failed = {}, {}, {}, []
    suites = {}
    for line in path.read_text(errors='replace').splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        kind = event.get('type')
        if kind == 'suite':
            suites[event['suite']['id']] = event['suite'].get('path')
        elif kind == 'testStart':
            test = event['test']
            names[test['id']] = test.get('name', '?')
            files[test['id']] = suites.get(test.get('suiteID'))
        elif kind == 'error':
            errors.setdefault(event['testID'], []).append(
                (event.get('error', ''), event.get('stackTrace', '')))
        elif kind == 'testDone' and event.get('result') in ('failure', 'error'):
            failed.append(event['testID'])
    for test_id in failed[:30]:
        parts = []
        for error, stack in errors.get(test_id, []):
            parts.append(error.strip())
            parts.append('\n'.join(stack.strip().splitlines()[:8]))
        body = f"{files.get(test_id) or ''}: {names.get(test_id, test_id)}\n" + '\n'.join(parts)
        print(f'::error title={title}::' + escape(body[:8000]))
    if not failed:
        print(f'::notice title={title}::no failed tests in {path}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
