from pathlib import Path
from fractions import Fraction
import unittest
import xml.etree.ElementTree as ET

ROOT=Path(__file__).parent/'fixtures'
def clock(value):return Fraction(value.rstrip('s'))

class MVPHostReadbackTests(unittest.TestCase):
    def test_actual_host_split_preserves_project_media_and_existing_captions(self):
        before=ET.parse(ROOT/'fcp-12.3-mvp-before.fcpxml').getroot()
        after=ET.parse(ROOT/'fcp-12.3-mvp-after.fcpxml').getroot()
        a=before.find('.//project');b=after.find('.//project')
        self.assertEqual(a.get('uid'),b.get('uid'))
        sa=a.find('sequence');sb=b.find('sequence')
        for key in ('duration','tcStart'):self.assertEqual(clock(sa.get(key)),clock(sb.get(key)))
        ca=sa.find('spine/asset-clip');cb=sb.find('spine/asset-clip')
        self.assertEqual(ca.attrib,cb.attrib)
        self.assertEqual(before.find('.//media-rep').get('src'),after.find('.//media-rep').get('src'))
        def captions(clip):
            return sorted((c.get('name'),clock(c.get('offset')),clock(c.get('start')),clock(c.get('duration')),c.get('role'),''.join(c.find('text').itertext()).strip()) for c in clip.findall('caption'))
        self.assertEqual(captions(ca),captions(cb));self.assertEqual(len(cb.findall('caption')),2)
        titles=cb.findall('title');self.assertEqual(len(titles),3)
        self.assertEqual([clock(t.get('offset'))*25 for t in titles],[0,84,146])
        self.assertEqual([clock(t.get('duration'))*25 for t in titles],[80,56,68])
        self.assertEqual(titles[0].find('text/text-style').text,'大家好，欢迎使用中文字幕工具！')
        for t in titles:
            style=t.find('text-style-def/text-style')
            self.assertEqual((style.get('font'),style.get('fontSize')),('PingFang SC','72'))
            self.assertEqual(t.find('adjust-transform').get('position'),'0 -40')
