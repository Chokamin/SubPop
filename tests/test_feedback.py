"""Run the built feedback serializer and AppKit action regressions.

The native harness uses synthetic metadata, an isolated pasteboard, and a
stub browser action. It never submits an Issue or reads project state.
"""
from pathlib import Path
import json
import subprocess
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / '.subloom/build/SubPopFeedbackTests'


class FeedbackTests(unittest.TestCase):
    def run_native(self, *args):
        self.assertTrue(BINARY.is_file(), 'Run scripts/build_probe.py first')
        result = subprocess.run([str(BINARY), *args], capture_output=True,
                                text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('passed', result.stdout)

    def test_issue_form_encoding_validation_and_metadata_privacy(self):
        self.run_native()

    def test_panel_actions_shortcuts_and_browser_failure_recovery(self):
        self.run_native('--panel')

    def test_synthetic_screenshot_pixels_metadata_and_input_limits(self):
        self.run_native('--screenshots')

    def test_github_form_requires_only_the_problem_and_accepts_serializer_fields(self):
        form = yaml.safe_load((ROOT / '.github/ISSUE_TEMPLATE/bug_report.yml').read_text())
        fields = {item['id']: item for item in form['body'] if 'id' in item}
        self.assertEqual(set(fields), {'problem', 'screenshots', 'environment'})
        required = {key for key, item in fields.items()
                    if item.get('validations', {}).get('required', False)}
        self.assertEqual(required, {'problem'})
        self.assertEqual(fields['screenshots']['type'], 'textarea')
        self.assertNotIn('render', fields['screenshots'].get('attributes', {}),
                         'Screenshot Markdown needs a normal textarea for pasted image uploads')
        self.assertTrue(BINARY.is_file(), 'Run scripts/build_probe.py first')
        result = subprocess.run([str(BINARY), '--schema'], capture_output=True,
                                text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        schema = json.loads(result.stdout)
        self.assertEqual(set(schema['fullKeys']), {'template', 'title', 'problem', 'environment'})
        self.assertEqual(set(schema['shortKeys']), {'template', 'title', 'environment'})
        for keys in schema.values():
            self.assertLessEqual(set(keys) - {'template', 'title'}, set(fields))


if __name__ == '__main__':
    unittest.main()
