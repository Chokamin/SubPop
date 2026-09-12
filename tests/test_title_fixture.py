import copy
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
from fractions import Fraction
from probes.title_fixture import payload

ROOT=Path(__file__).resolve().parents[1]

class TitleFixtureTests(unittest.TestCase):
    def setUp(self):
        self.manifest={'projectUID':'0D11EC79-ED11-4688-97A9-CB78621857DD','fps':25,'captions':[
            {'text':'大家好，欢迎使用中文字幕工具。','start_frame':0,'end_frame':80},
            {'text':'今天我们测试语音识别，','start_frame':84,'end_frame':140},
            {'text':'并把生成的字幕导入达芬奇。','start_frame':146,'end_frame':214}]}

    def test_contiguous_wrapper_preserves_asr_offsets_and_gaps(self):
        root=ET.fromstring(payload(self.manifest))
        self.assertIsNone(root.find('.//project'))
        self.assertIsNone(root.find('.//asset'))
        spine=root.find('clip/spine');cursor=Fraction(0)
        for item in spine:
            self.assertEqual(Fraction(item.get('offset')[:-1]),cursor)
            cursor+=Fraction(item.get('duration')[:-1])
        self.assertEqual(cursor,Fraction(217,25))
        titles=spine.findall('title')
        for title,row in zip(titles,self.manifest['captions']):
            self.assertEqual(title.findtext('text/text-style'),row['text'])
            self.assertEqual(Fraction(title.get('offset')[:-1])*25,row['start_frame'])
            self.assertEqual(Fraction(title.get('duration')[:-1])*25,row['end_frame']-row['start_frame'])

    def test_rejects_wrong_target_and_overlapping_or_outside_timing(self):
        for change in ('uid','overlap','outside'):
            m=copy.deepcopy(self.manifest)
            if change=='uid':m['projectUID']='wrong'
            elif change=='overlap':m['captions'][1]['start_frame']=79
            else:m['captions'][-1]['end_frame']=218
            with self.assertRaises(ValueError):payload(m)

    def test_bundled_versions_match_generator(self):
        for version in ('1.12','1.13','1.14'):
            expected=payload(self.manifest,version)
            for folder in ('native/Probe/Fixtures','.subloom/build/SubPop Probe.app/Contents/PlugIns/SubPopProbe.appex/Contents/Resources'):
                self.assertEqual((ROOT/folder/f'TitleProbe-{version}.fcpxml').read_bytes(),expected)
