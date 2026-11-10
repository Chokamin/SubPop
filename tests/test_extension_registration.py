"""Container self-repair of the FCP extension record, with a fake PlugInKit."""
from pathlib import Path
import subprocess
import unittest

ROOT=Path(__file__).resolve().parents[1]


class ExtensionRegistrationTests(unittest.TestCase):
    def test_native_registration_checks(self):
        result=subprocess.run([str(ROOT/'.subloom/build/SubPopExtensionRegistrationTests')],capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('Extension registration checks passed',result.stderr)

    def test_container_checks_only_its_installed_copy_after_launch(self):
        source=(ROOT/'native/Probe/Container.m').read_text()
        self.assertIn('[self checkExtensionRegistrationShowingGuide:manual];',source)
        self.assertIn('installed ? SubPopEnsureExtensionRegistered(',source)
        self.assertIn('dispatch_get_global_queue(QOS_CLASS_UTILITY,0)',source)
        # A user's own open explains where the panel lives; FCP/URL launches, the
        # post-update relaunch and dev copies keep their silent behavior.
        self.assertIn('NSApplicationLaunchIsDefaultLaunchKey',source)
        self.assertIn('update-installing.json',source)
        self.assertIn('if (!flag) [self checkExtensionRegistrationShowingGuide:YES];',source)
        self.assertIn('if (!title && guide) title=SubPopLaunchGuideAlert(running,&detail);',source)
        self.assertIn('if (self.showingLaunchAlert) return;',source)
        header=(ROOT/'native/Probe/ExtensionRegistration.h').read_text()
        self.assertEqual(header.count('@"-a"'),1)
        self.assertNotIn('@"-e"',header)
        self.assertNotIn('@"-r"',header)


if __name__=='__main__':unittest.main()
