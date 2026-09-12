from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
from probes.snapshot import prepare,collision

ROOT=Path(__file__).resolve().parents[1]

class SnapshotTests(unittest.TestCase):
    def test_verified_titles_removed_only_from_audio_copy(self):
        raw=(ROOT/'tests/fixtures/fcp-12.3-title-split.fcpxml').read_bytes()
        normalized,existing=prepare(raw)
        self.assertEqual(len(existing),3)
        self.assertEqual(len(ET.fromstring(normalized).findall('.//title')),0)
        self.assertEqual(len(ET.fromstring(normalized).findall('.//caption')),5)
        self.assertEqual(collision(existing,existing)['status'],'duplicate')
        self.assertEqual(len(ET.fromstring(raw).findall('.//title')),3)

    def test_proofread_or_timing_change_is_conflict_not_duplicate(self):
        _,old=prepare((ROOT/'tests/fixtures/fcp-12.3-title-split.fcpxml').read_bytes())
        _,edited=prepare((ROOT/'tests/fixtures/fcp-12.3-title-proofread.fcpxml').read_bytes())
        self.assertEqual(collision(old,edited)['status'],'conflict')
        edited[0]['text']=old[0]['text'];edited[0]['end_frame']-=1
        self.assertEqual(collision(old,edited)['status'],'conflict')
        self.assertEqual(collision(old,[])['status'],'clear')

    def test_unknown_template_or_nested_audio_refused(self):
        raw=(ROOT/'tests/fixtures/fcp-12.3-title-split.fcpxml').read_bytes()
        for mode in ('template','audio','filter'):
            root=ET.fromstring(raw)
            if mode=='template':root.find('.//effect').set('uid','unverified')
            else:ET.SubElement(root.find('.//title'),'audio' if mode=='audio' else 'filter-audio')
            with self.assertRaises(ValueError):prepare(ET.tostring(root))
