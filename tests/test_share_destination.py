"""Local preset safety, packaging prerequisites; real FCP import is separate."""
from pathlib import Path
import importlib.util
import hashlib
import plistlib
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('subpop_package_release',ROOT/'scripts/package_release.py')
packaging=importlib.util.module_from_spec(spec)
spec.loader.exec_module(packaging)


class ShareDestinationTests(unittest.TestCase):
    def test_genuine_preset_is_portable_audio_only_and_targets_installed_app(self):
        path=ROOT/'native/Probe/Resources/Share Destinations/SubPop.fcpxdest'
        data=path.read_bytes()
        self.assertEqual(hashlib.sha256(data).hexdigest(),'3481e4d53c567e0d3fdc341bd7fd6eec2b822354dff8ee04446cfd7c1f16e475')
        archive=plistlib.loads(data)
        self.assertEqual(archive['$archiver'],'NSKeyedArchiver')
        objects=archive['$objects']
        def value(reference):
            self.assertIsInstance(reference,plistlib.UID)
            self.assertLess(reference.data,len(objects))
            return objects[reference.data]
        destination=value(archive['$top']['root'])
        self.assertEqual(value(destination['name']),'发送到 SubPop')
        self.assertEqual(value(destination['type']),'Export Media')
        self.assertIs(value(destination['jobActionUsesHelperApp']),True)
        self.assertEqual(value(destination['selectedAudioStompSettingName']),'WAV')
        self.assertEqual(destination['selectedRolePresetName'],plistlib.UID(0))
        self.assertEqual(destination['selectedVideoStompSettingName'],plistlib.UID(0))
        self.assertIs(value(destination['exportSelectedLayersOnly']),False)
        # Respect the original archive; complete-project duration is validated
        # at intake instead of guessing changes to undocumented FCP properties.
        self.assertIs(value(destination['exportInOutRangeOnly']),True)
        action_xml=[x for x in objects if isinstance(x,str) and '<jobAction ' in x]
        self.assertEqual(len(action_xml),1)
        action=ET.fromstring(action_xml[0])
        self.assertEqual(action.attrib['kind'],'open')
        self.assertEqual(action.attrib['appName'],'/Applications/SubPop.app')
        encoder_xml=[x for x in objects if isinstance(x,str) and '<setting name="WAV"' in x]
        self.assertEqual(len(encoder_xml),1)
        encoder=ET.fromstring(encoder_xml[0]).find('encoder')
        self.assertEqual(encoder.attrib['name'],'CoreAudio')
        self.assertEqual(encoder.find('file-extension').text,'wav')
        self.assertEqual(encoder.find('video-encode').attrib['isEnabled'],'no')
        self.assertEqual(encoder.find('audio-video-encode').attrib['isEnabled'],'no')
        self.assertEqual(encoder.find('audio-encode').attrib['isEnabled'],'yes')
        def inspect(item):
            self.assertNotIsInstance(item,bytes,'no opaque bookmarks or embedded media')
            if isinstance(item,str):
                for private in ('/Users/','/Volumes/','file://','bookmark','SubPop152','E48006F3'):
                    self.assertNotIn(private.lower(),item.lower())
            elif isinstance(item,dict):
                for key,child in item.items():inspect(key);inspect(child)
            elif isinstance(item,list):
                for child in item:inspect(child)
            elif isinstance(item,plistlib.UID):self.assertLess(item.data,len(objects))
        inspect(archive)

    def test_native_safe_preset_installation(self):
        result=subprocess.run([str(ROOT/'.subloom/build/SubPopShareDestinationTests')],capture_output=True,text=True,check=True,timeout=30)
        self.assertIn('checks passed',result.stdout)
        self.assertIn('no FCP settings or UI',result.stdout)

    def test_packaging_requires_a_real_resource_container(self):
        with tempfile.TemporaryDirectory() as directory:
            app=Path(directory)/'Test.app'
            with self.assertRaises(RuntimeError):packaging.validate_share_preset(app)
            path=app/packaging.SHARE_PRESET;path.parent.mkdir(parents=True)
            path.write_bytes(b'invalid')
            with self.assertRaises(RuntimeError):packaging.validate_share_preset(app)
            path.write_bytes(plistlib.dumps([]))
            with self.assertRaises(RuntimeError):packaging.validate_share_preset(app)
            # Synthetic container for filesystem validation, not an FCP preset.
            path.write_bytes(plistlib.dumps({'test':'isolated'}))
            self.assertEqual(packaging.validate_share_preset(app),path)
            path.unlink();other=Path(directory)/'other';other.write_bytes(plistlib.dumps({'test':'other'}));path.symlink_to(other)
            with self.assertRaises(RuntimeError):packaging.validate_share_preset(app)

    def test_postinstall_uses_narrow_host_command_and_boot_volume(self):
        with tempfile.TemporaryDirectory() as directory:
            script=packaging.prepare_installer_scripts(Path(directory)/'scripts')/'postinstall'
            subprocess.run(['/bin/sh','-n',str(script)],check=True)
            result=subprocess.run(['/bin/sh',str(script),'pkg','/Applications','/Volumes/Other'],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('startup volume',result.stderr)
            self.assertEqual(script.stat().st_mode&0o777,0o755)


if __name__=='__main__':unittest.main()
