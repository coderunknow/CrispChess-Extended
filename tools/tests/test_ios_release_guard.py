"""The iOS App Store workflow must not upload development prerelease tags.

v2.3.2-dev1..dev3 each started an App Store build on their tag push (the
runs failed before the upload step, but only by luck). Dev tags are GitHub
prereleases; App Store Connect / TestFlight is reached only by a stable tag
or a deliberate manual dispatch.
"""
import fnmatch
import re
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / '.github/workflows/ios-release.yml'


def load():
    data = yaml.safe_load(WORKFLOW.read_text(encoding='utf-8'))
    # PyYAML reads the bare key `on` as boolean True.
    triggers = data.get('on', data.get(True))
    return data, triggers


def tag_triggers(patterns, tag):
    """GitHub's tag filter: later patterns win; `!` negates."""
    matched = False
    for pattern in patterns:
        negate = pattern.startswith('!')
        glob = pattern[1:] if negate else pattern
        # GitHub's `*` does not cross `/`; tags here contain none.
        if fnmatch.fnmatchcase(tag, glob):
            matched = not negate
    return matched


def evaluate(expression, event, ref_name, inputs):
    """Evaluates the small subset of GitHub expressions used in the guards."""
    expr = expression.strip()
    if expr.startswith('${{') and expr.endswith('}}'):
        expr = expr[3:-2].strip()
    expr = re.sub(r"contains\(github\.ref_name, '([^']*)'\)",
                  lambda m: repr(m.group(1) in ref_name), expr)
    expr = expr.replace("github.event_name", repr(event))
    expr = re.sub(r"inputs\.(\w+)", lambda m: repr(inputs.get(m.group(1))), expr)
    expr = expr.replace('&&', ' and ').replace('||', ' or ')
    expr = re.sub(r'!(?!=)', ' not ', expr)
    expr = expr.replace('false', 'False').replace('true', 'True')
    return bool(eval(expr, {'__builtins__': {}}, {}))  # noqa: S307 - fixed text


class IosReleaseGuardTests(unittest.TestCase):
    def setUp(self):
        self.data, self.triggers = load()
        self.job = self.data['jobs']['build-upload']
        self.steps = {s.get('name'): s for s in self.job['steps']}

    def test_dev_tags_do_not_trigger(self):
        patterns = self.triggers['push']['tags']
        for tag in ['v2.3.2-dev4', 'v2.3.2-dev10', 'v3.0.0-dev1']:
            self.assertFalse(tag_triggers(patterns, tag), tag)

    def test_stable_tags_still_trigger(self):
        patterns = self.triggers['push']['tags']
        for tag in ['v2.3.2', 'v2.4.0', 'v10.0.1']:
            self.assertTrue(tag_triggers(patterns, tag), tag)

    def test_manual_dispatch_is_kept(self):
        self.assertIn('workflow_dispatch', self.triggers)
        self.assertIn('dry_run', self.triggers['workflow_dispatch']['inputs'])

    def guarded(self, name, event, ref, inputs=None):
        inputs = inputs or {}
        job_if = self.job.get('if', 'true')
        step_if = self.steps[name].get('if', 'true')
        return (evaluate(job_if, event, ref, inputs)
                and evaluate(step_if, event, ref, inputs))

    def test_upload_and_submit_never_run_for_a_dev_tag_push(self):
        # Belt and braces: even if the tag filter were edited, a push of a
        # dev tag skips the job and both App Store steps.
        for name in ['Upload to App Store Connect', 'Submit to external TestFlight']:
            self.assertFalse(self.guarded(name, 'push', 'v2.3.2-dev4'), name)

    def test_upload_and_submit_run_for_a_stable_tag_push(self):
        for name in ['Upload to App Store Connect', 'Submit to external TestFlight']:
            self.assertTrue(self.guarded(name, 'push', 'v2.3.2'), name)

    def test_manual_dry_run_does_not_upload(self):
        inputs = {'dry_run': True, 'submit_only': False, 'status_only': False}
        self.assertFalse(self.guarded('Upload to App Store Connect',
                                      'workflow_dispatch', 'main', inputs))

    def test_manual_dispatch_can_still_upload(self):
        inputs = {'dry_run': False, 'submit_only': False, 'status_only': False}
        self.assertTrue(self.guarded('Upload to App Store Connect',
                                     'workflow_dispatch', 'main', inputs))


if __name__ == '__main__':
    unittest.main()
