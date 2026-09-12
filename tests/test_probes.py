import tempfile
import unittest
from pathlib import Path
from fractions import Fraction
import xml.etree.ElementTree as E
from probes.make_fixture import fixture
from probes.readback import inspect, seconds


class ProbeTests(unittest.TestCase):
    def check_xml(self, mutate=lambda r:None):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'fixture.fcpxml'
            root=E.fromstring(fixture(Path(d)/'audio.mp4'))
            mutate(root)
            E.ElementTree(root).write(p)
            return inspect(p)

    def test_time_is_rational(self):
        self.assertEqual(seconds('1001/30000s')*30000,1001)
        with self.assertRaises(ValueError):seconds('01:00:00:00')

    def test_nonzero_timeline_origin(self):
        data=self.check_xml()
        self.assertEqual(data['relative_start'],'0')
        self.assertEqual(Fraction(data['duration']),Fraction(217,25))
        self.assertIn('unknown',data['audibility'])

    def test_caption_offset_uses_parent_source_clock(self):
        def mutate(root):
            c=root.find('.//asset-clip');c.set('start','2s')
            caption=E.SubElement(c,'caption',offset='3s',duration='1s')
            E.SubElement(caption,'text').text='中文'
        self.assertEqual(self.check_xml(mutate)['captions'][0]['absolute_start'],'3601')

    def test_retime_rejected(self):
        with self.assertRaises(ValueError):
            self.check_xml(lambda r:E.SubElement(r.find('.//asset-clip'),'timeMap'))

    def test_disabled_rejected(self):
        with self.assertRaises(ValueError):
            self.check_xml(lambda r:r.find('.//asset-clip').set('enabled','0'))

    def test_source_audio_attributes_rejected(self):
        for key,value in (('srcEnable','video'),('srcEnable','invalid'),('audioStart','1s'),('audioDuration','2s')):
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):
                self.check_xml(lambda r:r.find('.//asset-clip').set(key,value))

    def test_real_audio_changes_rejected_and_original_restored(self):
        from probes.snapshot import prepare
        root=Path(__file__).parent/'fixtures'
        with tempfile.TemporaryDirectory() as d:
            for name in ('audio-minus6db','audio-component-disabled'):
                data,_=prepare((root/f'fcp-12.3-{name}.fcpxml').read_bytes())
                path=Path(d)/'audio.fcpxml';path.write_bytes(data)
                with self.subTest(name=name),self.assertRaises(ValueError):inspect(path)
        def shape(e):
            return e.tag,sorted(e.attrib.items()),(e.text or '').strip(),[shape(c) for c in e]
        before=E.parse(root/'fcp-12.3-fresh-title-drop.fcpxml').find('.//project/sequence')
        restored=E.parse(root/'fcp-12.3-audio-restored.fcpxml').find('.//project/sequence')
        self.assertEqual(shape(before),shape(restored))

    def test_multiple_clips_rejected(self):
        with self.assertRaises(ValueError):
            self.check_xml(lambda r:E.SubElement(r.find('.//spine'),'gap'))

    def test_components_rejected(self):
        with self.assertRaises(ValueError):
            self.check_xml(lambda r:E.SubElement(r.find('.//asset-clip'),'audio-channel-source',srcCh='1'))


class ActualReadbackRegression(unittest.TestCase):
    def test_fcp_12_3_export(self):
        # Parsing an archived real export is a regression, not a new FCP run.
        result=inspect(Path(__file__).parent/'fixtures/fcp-12.3-caption-readback.fcpxml')
        self.assertEqual(result['uid'],'0D11EC79-ED11-4688-97A9-CB78621857DD')
        self.assertEqual([(c['relative_start'],c['duration']) for c in result['captions']],[('1','1'),('4','6/5')])
        self.assertEqual(result['captions'][1]['text'],'保留 3.5% 和 USB-C')

if __name__=='__main__':unittest.main()


class ActualHostEvidenceTests(unittest.TestCase):
    def test_asr_writeback_preserves_original_project_and_captions(self):
        import json
        root=Path(__file__).resolve().parents[1]
        baseline=inspect(root/'tests/fixtures/fcp-12.3-native-drop.fcpxml')
        after=inspect(root/'tests/fixtures/fcp-12.3-asr-writeback.fcpxml')
        proofread=inspect(root/'tests/fixtures/fcp-12.3-asr-proofread.fcpxml')
        evidence=json.loads((root/'tests/fixtures/evidence/subpop-asr-writeback.json').read_text())
        self.assertEqual(baseline['uid'],after['uid'])
        self.assertEqual(after['uid'],proofread['uid'])
        self.assertEqual(len(after['captions']),5)
        for original in baseline['captions']:self.assertIn(original,after['captions'])
        for row in evidence['newCaptions']:
            caption=next(c for c in after['captions'] if c['text']==row['text'])
            self.assertEqual(Fraction(caption['relative_start']),Fraction(row['start_frame'],25))
            self.assertEqual(Fraction(caption['duration']),Fraction(row['end_frame']-row['start_frame'],25))
        a=E.parse(root/'tests/fixtures/fcp-12.3-native-drop.fcpxml')
        b=E.parse(root/'tests/fixtures/fcp-12.3-asr-writeback.fcpxml')
        for path in ('.//sequence','.//asset-clip'):self.assertEqual(a.find(path).attrib,b.find(path).attrib)
        edits=[(x,y) for x,y in zip(after['captions'],proofread['captions']) if x!=y]
        self.assertEqual(len(edits),1)
        self.assertEqual(edits[0][1]['text'],'大家好，欢迎使用中文字幕工具！')
        self.assertEqual(edits[0][0]['relative_start'],edits[0][1]['relative_start'])
        self.assertEqual(edits[0][0]['duration'],edits[0][1]['duration'])

    def test_native_audio_and_asr_share_the_complete_project_pcm(self):
        # Joins archived live evidence; does not run FCP or the ASR model.
        import json
        root = Path(__file__).resolve().parents[1]
        audio = json.loads((root/'tests/fixtures/evidence/subpop-native-audio-build8.json').read_text())
        asr = json.loads((root/'tests/fixtures/evidence/subpop-native-asr.json').read_text())
        dropped = inspect(root/'tests/fixtures/fcp-12.3-native-drop.fcpxml')
        self.assertEqual(audio['projectUID'], dropped['uid'])
        self.assertEqual(audio['projectUID'], asr['snapshot']['uid'])
        self.assertEqual(audio['pcmSHA256'], asr['pcm_sha256'])
        self.assertEqual(audio['sampleCount'], Fraction(dropped['duration'])*16000)
        self.assertEqual(audio['pcmBytes'], audio['sampleCount']*4)
        self.assertEqual(audio['status'], 'decoded')
        self.assertEqual(audio['sampleRate'], 16000)
        self.assertIn('unknown',audio['audibility'])

    def test_selection_comparison_preserves_ui_sdk_mismatch(self):
        # Archive consistency only: never reclassify this as live selection support.
        import json
        root = Path(__file__).resolve().parents[1]
        evidence = json.loads((root/'tests/fixtures/evidence/subpop-selection-comparison.json').read_text())
        records = {r['sourceFile']: r for r in evidence['records']}
        xml = E.parse(root/'tests/fixtures/fcp-12.3-caption-readback.fcpxml')
        project = xml.find('.//project')
        sequence = project.find('sequence')
        expected = (seconds(sequence.get('tcStart')), seconds(sequence.get('duration')))
        selected = cleared = 0
        for case in evidence['cases']:
            record = records[case['snapshotSourceFile']]
            self.assertEqual(record['recordedAt'], case['snapshotAt'])
            self.assertEqual(record['reason'], case['reason'])
            self.assertEqual(next(c['uid'] for c in record['containers'] if c['type']==3), project.get('uid'))
            times = [record['sequenceRange'][k] for k in ('start','duration')]
            self.assertTrue(all(t['flags'] & 1 for t in times))
            actual = tuple(Fraction(t['value'], t['timescale']) for t in times)
            self.assertEqual(actual, expected)
            ui = case['ui']['timelineRange']
            if ui:
                selected += 1
                self.assertNotEqual(actual, tuple(Fraction(ui[k]) for k in ('start','duration')))
            else:
                cleared += 1
        self.assertGreaterEqual(selected, 3)
        self.assertGreaterEqual(cleared, 1)
        self.assertEqual(evidence['conclusion'], 'selection_reading_not_validated')

    def test_host_uid_and_timing_match_independent_xml_export(self):
        # Recorded host evidence regression, not a new live FCP test.
        import json
        root = Path(__file__).resolve().parents[1]
        records = json.loads((root/'tests/fixtures/evidence/subpop-host-recovered.json').read_text())
        xml = E.parse(root/'tests/fixtures/fcp-12.3-caption-readback.fcpxml')
        project = xml.find('.//project')
        original = next(x for x in records if x['sequence']['name'] == project.get('name'))
        container = next(x for x in original['containers'] if x['type'] == 3)
        self.assertEqual(container['uid'], project.get('uid'))
        seq = original['sequence']
        for key, attr in [('start','tcStart'),('duration','duration'),('frameDuration',None)]:
            t = seq[key]
            self.assertTrue(t['flags'] & 1)
            actual = Fraction(t['value'],t['timescale'])
            expected = seconds(xml.find('.//project/sequence').get(attr)) if attr else Fraction(1,25)
            self.assertEqual(actual,expected)
        uids = {next(y['uid'] for y in x['containers'] if y['type']==3) for x in records}
        self.assertEqual(len(uids),2)
