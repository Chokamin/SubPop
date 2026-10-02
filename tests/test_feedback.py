"""Run the built feedback serializer and AppKit action regressions.

The native harness uses synthetic metadata, an isolated pasteboard, and a
stub browser action. It never submits an Issue or reads project state.
"""
from pathlib import Path
import subprocess
import unittest

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


if __name__ == '__main__':
    unittest.main()
