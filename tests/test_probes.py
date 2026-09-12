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
    def test_host_uid_and_timing_match_independent_xml_export(self):
        # Recorded host evidence regression, not a new live FCP test.
        import json
        root = Path(__file__).resolve().parents[1]
        records = json.loads((root/'docs/evidence/subpop-host-recovered.json').read_text())
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
