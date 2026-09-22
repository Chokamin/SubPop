import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from scripts import sign_release


class SigningPolicyTests(unittest.TestCase):
    def test_missing_extension_compatibility_or_sandbox_fails_before_signing(self):
        for values in ({}, {'com.apple.security.app-sandbox': True},
                       {'com.apple.security.cs.disable-library-validation': True}):
            with tempfile.TemporaryDirectory() as temp:
                ent = Path(temp) / 'extension.plist'
                ent.write_bytes(plistlib.dumps(values))
                with patch.object(sign_release.subprocess, 'run') as run:
                    with self.assertRaises(ValueError):
                        sign_release.sign(Path(temp) / 'Test.app', 'fake identity', ent)
                    run.assert_not_called()

    def test_signed_bundles_enforce_extension_only_scope(self):
        for extension_exception, host_exception in ((True, False), (False, False), (True, True)):
            with self.subTest(extension=extension_exception, host=host_exception), tempfile.TemporaryDirectory() as temp:
                app = Path(temp).resolve() / 'Test.app'
                extension = app / 'Contents/PlugIns/SubPopProbe.appex'
                extension.mkdir(parents=True)
                ent = Path(temp) / 'extension.plist'
                ent.write_bytes(plistlib.dumps({'com.apple.security.app-sandbox': True,
                    'com.apple.security.cs.disable-library-validation': True}))

                def execute(command, **kwargs):
                    if '-d' in command:
                        enabled = extension_exception if command[-1] == str(extension) else host_exception
                        return subprocess.CompletedProcess(command, 0, stdout=plistlib.dumps(
                            {'com.apple.security.cs.disable-library-validation': enabled,
                             'com.apple.security.automation.apple-events':True}))
                    return Mock(returncode=0)

                with patch.object(sign_release.subprocess, 'run', side_effect=execute):
                    if extension_exception and not host_exception:
                        sign_release.sign(app, 'fake identity', ent)
                    else:
                        with self.assertRaisesRegex(ValueError, 'scoped'):
                            sign_release.sign(app, 'fake identity', ent)

    def test_missing_container_apple_events_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp).resolve() / 'Test.app'
            extension = app / 'Contents/PlugIns/SubPopProbe.appex'
            extension.mkdir(parents=True)
            ent = Path(temp) / 'extension.plist'
            ent.write_bytes(plistlib.dumps({'com.apple.security.app-sandbox': True,
                'com.apple.security.cs.disable-library-validation': True}))

            def execute(command, **kwargs):
                if '-d' in command:
                    values = {'com.apple.security.cs.disable-library-validation': True,
                              'com.apple.security.automation.apple-events': True} if command[-1] == str(extension) else {}
                    return subprocess.CompletedProcess(command, 0, stdout=plistlib.dumps(values))
                return Mock(returncode=0)

            with patch.object(sign_release.subprocess, 'run', side_effect=execute):
                with self.assertRaisesRegex(ValueError, 'Both app and extension'):
                    sign_release.sign(app, 'fake identity', ent)
