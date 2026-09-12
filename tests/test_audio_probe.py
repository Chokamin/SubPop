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

    def test_actual_split_and_gap_refused_before_decode(self):
        for name in ('audio-split-4s','audio-leading-gap'):
            xml=ROOT/f'tests/fixtures/fcp-12.3-{name}.fcpxml'
            result=json.loads(subprocess.check_output([str(self.binary),str(xml),UID,str(self.directory)],text=True))
            self.assertEqual(result['stage'],'plain-clip-required')

    def test_derived_tail_trim_uses_source_offset(self):
        # Derived decoder experiment, not a host mix: isolate the real second
        # segment, enable it and remove attached titles/captions.
        def tail(tree):
            actual=ET.parse(ROOT/'tests/fixtures/fcp-12.3-audio-split-4s.fcpxml')
            segment=actual.findall('.//spine/asset-clip')[1]
            clip=tree.find('.//asset-clip')
            clip.attrib.clear();clip.attrib.update(segment.attrib)
            clip.attrib.pop('enabled',None);clip.set('offset','3600s')
            for child in list(clip):clip.remove(child)
            tree.find('.//sequence').set('duration',segment.get('duration'))
        whole=self.probe()
        whole_bytes=(self.directory/whole['pcmFile']).read_bytes()
        result=self.probe(tail)
        self.assertEqual(result['status'],'decoded',result)
        self.assertEqual(result['sourceStartSeconds'],4)
        self.assertEqual(result['sampleCount'],74880)
        # A sample-for-sample comparison catches silently decoding from zero.
        self.assertEqual((self.directory/result['pcmFile']).read_bytes(),whole_bytes[64000*4:])

    def test_aac_packet_boundaries_trim_to_requested_audio_range(self):
        media=self.directory/'packet-boundary.m4a'
        subprocess.run(['/opt/homebrew/bin/ffmpeg','-v','error','-nostdin','-y','-f','lavfi','-i',
                        'sine=frequency=440:sample_rate=48000:duration=31','-c:a','aac',str(media)],check=True)
        for start,duration in ((0,30),(30,1)):
            def mutate(tree):
                tree.find('.//media-rep').set('src',media.as_uri())
                tree.find('.//sequence').set('duration',f'{duration}s')
                clip=tree.find('.//asset-clip');clip.set('duration',f'{duration}s');clip.set('start',f'{start}s')
            result=self.probe(mutate)
            self.assertEqual(result['status'],'decoded',result)
            self.assertEqual(result['sampleCount'],duration*16000)
            self.assertGreater(result['rms'],0.01)

    def test_source_audio_attributes_refused(self):
        for key,value in (('srcEnable','video'),('srcEnable','invalid'),('audioStart','1s'),('audioDuration','2s')):
            with self.subTest(key=key,value=value):
                result=self.probe(lambda t:t.find('.//asset-clip').set(key,value))
                self.assertEqual(result['stage'],'unverified-source-audio')

    def test_real_host_audio_adjustments_refused(self):
        from probes.snapshot import prepare
        for name in ('audio-minus6db','audio-component-disabled'):
            with self.subTest(name=name):
                data,_=prepare((ROOT/f'tests/fixtures/fcp-12.3-{name}.fcpxml').read_bytes())
                xml=self.directory/'host.fcpxml';xml.write_bytes(data)
                result=json.loads(subprocess.check_output([str(self.binary),str(xml),UID,str(self.directory)],text=True))
                self.assertEqual(result['stage'],'unverified-clip-features')

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
