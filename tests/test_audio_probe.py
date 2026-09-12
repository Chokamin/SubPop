"""Native parser/decode checks outside the extension, not proof of sandbox access."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
UID = '0D11EC79-ED11-4688-97A9-CB78621857DD'


class AudioProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory()
        cls.directory = Path(cls.scratch.name)
        cls.binary = cls.directory/'audio-probe'
        sdk = subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
        subprocess.run(['xcrun','clang','-isysroot',sdk,'-fobjc-arc','-Wall','-Wextra','-Werror',
                        '-framework','Foundation','-framework','AVFoundation','-framework','CoreMedia',
                        str(ROOT/'native/Probe/AudioProbe.m'),str(ROOT/'native/Probe/AudioProbeCLI.m'),
                        '-o',str(cls.binary)],check=True,capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def probe(self, mutate=lambda tree: None, uid=UID):
        tree = ET.parse(ROOT/'tests/fixtures/fcp-12.3-caption-readback.fcpxml')
        tree.find('.//media-rep').set('src',(ROOT/'.subloom/verification/mandarin.mp4').as_uri())
        mutate(tree)
        xml = self.directory/'test.fcpxml'
        tree.write(xml,encoding='utf-8')
        return json.loads(subprocess.check_output([str(self.binary),str(xml),uid,str(self.directory)],text=True))

    def test_wrong_active_project_refused(self):
        self.assertEqual(self.probe(uid='different')['stage'],'active-project-uid-mismatch')

    def test_partial_project_refused(self):
        result = self.probe(lambda t: t.find('.//asset-clip').set('duration','2s'))
        self.assertEqual(result['stage'],'full-project-coverage-required')

    def test_network_media_refused(self):
        result = self.probe(lambda t: t.find('.//media-rep').set('src','https://example.invalid/audio.mp4'))
        self.assertEqual(result['stage'],'local-media-required')

    def test_short_source_cannot_pass_as_whole_project(self):
        def longer_project(tree):
            tree.find('.//sequence').set('duration','9s')
            tree.find('.//asset-clip').set('duration','9s')
        self.assertEqual(self.probe(longer_project)['stage'],'incomplete-project-audio')

    def test_decode_whole_fixture(self):
        result = self.probe()
        self.assertEqual(result['status'],'decoded',result)
        self.assertEqual(result['sampleRate'],16000)
        self.assertEqual(result['channels'],1)
        self.assertEqual(result['sampleCount'],138880)
        self.assertEqual(result['pcmBytes'],138880*4)
        self.assertGreater(result['rms'],0)
        self.assertIn('unknown',result['audibility'])
