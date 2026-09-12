"""Checks of the compiled bundle, not tests of FCP loading or behavior."""
import plistlib
from pathlib import Path
import subprocess
import unittest

ROOT=Path(__file__).resolve().parents[1]
APP=ROOT/'.subloom/build/Subloom Probe.app'
EXT=APP/'Contents/PlugIns/SubloomProbe.appex'

class NativeBundleTests(unittest.TestCase):
    def test_extension_registration_metadata(self):
        with (EXT/'Contents/Info.plist').open('rb') as f: info=plistlib.load(f)
        self.assertEqual(info['NSExtension']['NSExtensionPointIdentifier'],'com.apple.FinalCut.WorkflowExtension')
        self.assertEqual(info['NSExtension']['ProExtensionPrincipalViewControllerClass'],'SubloomProbeViewController')
        self.assertTrue((EXT/'Contents/MacOS'/info['CFBundleExecutable']).is_file())
        with (APP/'Contents/Info.plist').open('rb') as f: container=plistlib.load(f)
        self.assertTrue(info['CFBundleIdentifier'].startswith(container['CFBundleIdentifier']+'.'))

    def test_apple_silicon_and_sdk_entrypoint(self):
        binary=EXT/'Contents/MacOS/SubloomProbeExtension'
        arch=subprocess.check_output(['lipo','-archs',str(binary)],text=True).strip()
        self.assertEqual(arch,'arm64')
        symbols=subprocess.check_output(['nm',str(binary)],text=True)
        self.assertRegex(symbols,r'T _ProExtensionMain\b')
        self.assertRegex(symbols,r'T _ProExtensionHostSingleton\b')

    def test_signed_sandboxed_extension(self):
        subprocess.run(['codesign','--verify','--deep','--strict',str(APP)],check=True,capture_output=True)
        data=subprocess.check_output(['codesign','-d','--entitlements',':-',str(EXT)],stderr=subprocess.DEVNULL)
        ent=plistlib.loads(data)
        self.assertIs(ent['com.apple.security.app-sandbox'],True)
        self.assertNotIn('com.apple.security.automation.apple-events',ent)
        self.assertNotIn('com.apple.security.cs.disable-library-validation',ent)

if __name__=='__main__':unittest.main()
