from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
from probes.snapshot import prepare,collision

ROOT=Path(__file__).resolve().parents[1]

class SnapshotTests(unittest.TestCase):
    def test_host_split_gap_boundaries_and_restoration(self):
        from probes.readback import inspect,seconds
        fixtures=ROOT/'tests/fixtures'
        split=ET.parse(fixtures/'fcp-12.3-audio-split-4s.fcpxml')
        clips=split.findall('.//spine/asset-clip')
        self.assertEqual([(seconds(c.get('offset'))-3600,seconds(c.get('start','0s')),seconds(c.get('duration'))) for c in clips],
                         [(0,0,4),(4,4,seconds('117/25s'))])
        # Both clips really were disabled in this captured host experiment.
        self.assertTrue(all(c.get('enabled')=='0' for c in clips))
        for name in ('audio-split-4s','audio-leading-gap'):
            path=fixtures/f'fcp-12.3-{name}.fcpxml'
            normalized,existing=prepare(path.read_bytes())
            self.assertEqual(len(existing),3)
            self.assertFalse(ET.fromstring(normalized).findall('.//title'))
            with self.assertRaises(ValueError):inspect(path)
        gap=ET.parse(fixtures/'fcp-12.3-audio-leading-gap.fcpxml').find('.//spine/gap')
        self.assertEqual(seconds(gap.get('duration')),4)
        def shape(e):return e.tag,sorted(e.attrib.items()),(e.text or '').strip(),[shape(c) for c in e]
        before=ET.parse(fixtures/'fcp-12.3-audio-restored.fcpxml').find('.//sequence')
        after=ET.parse(fixtures/'fcp-12.3-audio-edit-restored.fcpxml').find('.//sequence')
        self.assertEqual(shape(before),shape(after))

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

    def test_fresh_host_drop_matches_actual_duplicate_decision(self):
        import json
        _,existing=prepare((ROOT/'tests/fixtures/fcp-12.3-fresh-title-drop.fcpxml').read_bytes())
        _,previous=prepare((ROOT/'tests/fixtures/fcp-12.3-title-split.fcpxml').read_bytes())
        evidence=json.loads((ROOT/'docs/evidence/subpop-fresh-duplicate.json').read_text())
        self.assertEqual(collision(previous,existing),evidence['collision'])
        self.assertEqual(evidence['status'],'blocked-existing-titles')
        self.assertFalse(evidence['titlePayloadsGenerated'])
