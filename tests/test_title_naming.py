"""Native resource/name tests. These do not operate Final Cut Pro."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class TitleNamingTests(unittest.TestCase):
    def test_native_title_naming_bridge(self):
        result = subprocess.run(
            [str(ROOT / '.subloom/build/SubPopTitleNamingBridgeTests')],
            capture_output=True, text=True, check=True, timeout=30,
        )
        self.assertIn('checks passed', result.stdout)

    def test_native_title_naming(self):
        result = subprocess.run(
            [str(ROOT / '.subloom/build/SubPopTitleNamingTests')],
            capture_output=True, text=True, check=True, timeout=30,
        )
        self.assertIn('checks passed', result.stdout)
        self.assertIn('no FCP calls', result.stdout)


if __name__ == '__main__':
    unittest.main()
