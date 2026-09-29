from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
from probes.snapshot import prepare,collision,NATIVE_SUBTITLE_EFFECT

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

    def test_source_frame_title_does_not_block_project_audio(self):
        # FCP can place a title on a source clip's frame grid even when its
        # visible edges fall between project frames (e.g. 60 fps in 29.97).
        root=ET.parse(ROOT/'tests/fixtures/fcp-12.3-title-split.fcpxml').getroot()
        root.find('resources/format').set('frameDuration','1001/30000s')
        ET.SubElement(root.find('resources'),'format',id='source60',frameDuration='1/60s')
        root.find('.//spine/asset-clip').set('format','source60')
        first=root.find('.//title')
        first.set('offset','1/60s')
        normalized,existing=prepare(ET.tostring(root),generic=True)
        self.assertFalse(ET.fromstring(normalized).findall('.//title'))
        self.assertEqual((existing[0]['start_frame'],existing[0]['end_frame']),(0,97))
        self.assertFalse(existing[0]['exactTiming'])
        # Conservative rounding may overlap a new subtitle, but must never
        # declare an exact duplicate when the original edges are fractional.
        new=[{k:existing[0][k] for k in ('text','start_frame','end_frame')}]
        self.assertEqual(collision(new,existing)['status'],'conflict')

    def test_unknown_template_or_nested_audio_refused(self):
        raw=(ROOT/'tests/fixtures/fcp-12.3-title-split.fcpxml').read_bytes()
        for mode in ('template','audio','filter'):
            root=ET.fromstring(raw)
            if mode=='template':root.find('.//effect').set('uid','unverified')
            else:ET.SubElement(root.find('.//title'),'audio' if mode=='audio' else 'filter-audio')
            with self.assertRaises(ValueError):prepare(ET.tostring(root))

    def test_native_fcp_subtitles_are_removed_only_from_audio_copy(self):
        root=ET.parse(ROOT/'tests/fixtures/fcp-12.3-title-split.fcpxml').getroot()
        root.find('.//effect').set('uid',NATIVE_SUBTITLE_EFFECT)
        first=root.find('.//title')
        first.set('start','3600s')
        ET.SubElement(first,'param',name='Background Width',key='9999/3336678691/100/3336678692/2/100',value='0.6208')
        original=ET.tostring(root)
        normalized,existing=prepare(original,generic=True)
        self.assertEqual(len(existing),3)
        self.assertEqual(len(ET.fromstring(normalized).findall('.//title')),0)
        self.assertEqual(len(ET.fromstring(original).findall('.//title')),3)
        ET.SubElement(first,'audio')
        with self.assertRaisesRegex(ValueError,'标题包含可能有声音'):
            prepare(ET.tostring(root),generic=True)

    def test_tap5a_visual_title_is_counted_and_removed_from_audio_copy(self):
        root=ET.parse(ROOT/'tests/fixtures/fcp-12.3-title-split.fcpxml').getroot()
        root.find('.//effect').set('uid','custom-third-party-title-template')
        title=root.find('.//title')
        ET.SubElement(title,'param',name='Top',key='9999/10658/100/10661/2/100',value='0.1')
        text_style=title.find('text-style-def/text-style')
        ET.SubElement(text_style,'param',name='MotionSimpleValues',key='tracking',value='4')
        visual=ET.SubElement(title,'filter-video',ref='r4')
        ET.SubElement(visual,'param',name='Animation',key='nested/motion',value='1')
        original=ET.tostring(root)
        normalized,existing=prepare(original,generic=True)
        self.assertEqual(len(existing),3)
        self.assertEqual(len(ET.fromstring(normalized).findall('.//title')),0)
        self.assertEqual(len(ET.fromstring(original).findall('.//title')),3)
        self.assertEqual(collision(existing,existing)['status'],'duplicate')
        from tempfile import TemporaryDirectory
        from probes.project import inspect
        with TemporaryDirectory() as directory:
            audio_copy=Path(directory)/'input.fcpxml'
            audio_copy.write_bytes(normalized)
            self.assertEqual(inspect(audio_copy)['uid'],root.find('.//project').get('uid'))
        ET.SubElement(title,'audio',ref='r9')
        with self.assertRaisesRegex(ValueError,'可能有声音'):
            prepare(ET.tostring(root),generic=True)

    def test_nested_visual_media_is_allowed_but_audio_media_is_not_discarded(self):
        root=ET.parse(ROOT/'tests/fixtures/fcp-12.3-title-split.fcpxml').getroot()
        title=root.find('.//title')
        silent=ET.SubElement(root.find('resources'),'asset',id='r9',hasAudio='0')
        visual=ET.SubElement(title,'video',ref=silent.get('id'))
        ET.SubElement(visual,'filter-video').append(ET.Element('param',name='Blur',value='10'))
        normalized,_=prepare(ET.tostring(root),generic=True)
        self.assertFalse(ET.fromstring(normalized).findall('.//title'))
        ET.SubElement(title,'asset-clip',ref='r2')
        with self.assertRaisesRegex(ValueError,'可能有声音'):
            prepare(ET.tostring(root),generic=True)

    def test_fresh_host_drop_matches_actual_duplicate_decision(self):
        import json
        _,existing=prepare((ROOT/'tests/fixtures/fcp-12.3-fresh-title-drop.fcpxml').read_bytes())
        _,previous=prepare((ROOT/'tests/fixtures/fcp-12.3-title-split.fcpxml').read_bytes())
        evidence=json.loads((ROOT/'tests/fixtures/evidence/subpop-fresh-duplicate.json').read_text())
        self.assertEqual(collision(previous,existing),evidence['collision'])
        self.assertEqual(evidence['status'],'blocked-existing-titles')
        self.assertFalse(evidence['titlePayloadsGenerated'])

    def test_basic_title_nested_in_component_clip_preserves_source_clock(self):
        from copy import deepcopy
        source=ET.parse(ROOT/'tests/fixtures/fcp-12.3-title-split.fcpxml')
        effect=deepcopy(source.find('.//effect'))
        root=ET.parse(ROOT/'tests/fixtures/component-clips.fcpxml').getroot()
        root.find('resources').append(effect)
        parent=root.find('.//spine/gap/clip')
        title=deepcopy(source.find('.//title'));title.set('ref',effect.get('id'))
        title.set('offset','140s');title.set('duration','1s');parent.append(title)
        visual=ET.SubElement(title,'filter-video',ref=effect.get('id'))
        ET.SubElement(visual,'param',name='Nested visual effect',value='1')
        raw=ET.tostring(root);normalized,existing=prepare(raw,generic=True)
        self.assertEqual(len(existing),1)
        self.assertEqual((existing[0]['start_frame'],existing[0]['end_frame']),(100,125))
        self.assertFalse(ET.fromstring(normalized).findall('.//title'))
        self.assertEqual(len(ET.fromstring(raw).findall('.//title')),1)
        ET.SubElement(visual,'audio')
        with self.assertRaisesRegex(ValueError,'可能有声音'):prepare(ET.tostring(root),generic=True)
