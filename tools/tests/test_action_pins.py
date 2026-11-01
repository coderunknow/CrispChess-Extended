import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('check_action_pins', ROOT / 'tool/dev/check_action_pins.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class ActionPinTests(unittest.TestCase):
    def check(self, text):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'wf.yml'
            p.write_text(text)
            return mod.check_workflow(p)

    def test_pinned_step_passes(self):
        self.assertEqual(self.check('''jobs:
  build:
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
'''), [])

    def test_quoted_key_mutable_ref_fails(self):
        errs = self.check('''jobs:
  build:
    steps:
      - "uses": actions/checkout@v4
''')
        self.assertEqual(len(errs), 1)
        self.assertIn('mutable action ref', errs[0])

    def test_quoted_value_mutable_ref_fails(self):
        errs = self.check('''jobs:
  build:
    steps:
      - uses: "actions/checkout@v4"
''')
        self.assertEqual(len(errs), 1)

    def test_invalid_yaml_fails_closed(self):
        errs = self.check('jobs: [')
        self.assertEqual(len(errs), 1)
        self.assertIn('invalid workflow YAML', errs[0])


if __name__ == '__main__':
    unittest.main()
