"""Native simulated FCP protocol and filesystem transactions; not a host test."""
from pathlib import Path
import plistlib
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / '.subloom/build/SubPop Probe.app'


class ShareReceiverTests(unittest.TestCase):
    def test_extension_intake_transactions(self):
        binary = ROOT / '.subloom/build/SubPopShareIntakeTests'
        result = subprocess.run([str(binary)], capture_output=True, text=True, check=True, timeout=30)
        self.assertIn('checks passed', result.stdout)
        self.assertIn('no FCP', result.stdout)

    def test_native_receive_transactions(self):
        binary = ROOT / '.subloom/build/SubPopShareReceiverTests'
        result = subprocess.run([str(binary)], capture_output=True, text=True, check=True, timeout=30)
        self.assertIn('checks passed', result.stdout)
        self.assertIn('simulated FCP events', result.stdout)

    def test_bundle_advertises_receive_only_official_protocol(self):
        info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
        self.assertEqual(info['com.apple.proapps.MediaAssetProtocol'], {})
        self.assertTrue(info['NSAppleScriptEnabled'])
        self.assertEqual(info['OSAScriptingDefinition'], 'ShareReceiver.sdef')
        source = ROOT / 'native/Probe/ShareReceiver.sdef'
        self.assertEqual((APP / 'Contents/Resources/ShareReceiver.sdef').read_bytes(), source.read_bytes())
        subprocess.run(['xmllint', '--noout', '--valid', str(source)], check=True, capture_output=True)


if __name__ == '__main__':
    unittest.main()
