"""Independent connections use FCP's stored output clock, even on retimed anchors.

Offsets are grounded in the isolated FCP 12.3 import/export checks: 2x at
project2 + stored2 gives project4, while half-speed + stored1/2 gives 5/2.
These planner regressions do not themselves stand in for FCP verification.
"""
from fractions import Fraction
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as E

from probes.project import inspect
from probes.snapshot import prepare


def fixture(parent_tag='asset-clip', start='0s', duration='4s'):
    root=E.Element('fcpxml',version='1.14')
    resources=E.SubElement(root,'resources')
    E.SubElement(resources,'format',id='p30',frameDuration='1/30s',width='640',height='360',colorSpace='1-1-1 (Rec. 709)')
    for ref,has_video in (('camera',True),('external',False)):
        attrs=dict(id=ref,start='0s',duration='20s',hasAudio='1',audioSources='1',audioChannels='1',audioRate='48000')
        if has_video:attrs.update(hasVideo='1',format='p30',videoSources='1')
        asset=E.SubElement(resources,'asset',**attrs)
        E.SubElement(asset,'media-rep',kind='original-media',src=f'file:///TEST_MEDIA/{ref}.wav')
    project=E.SubElement(root,'project',name='Independent connected-retime clock regression',uid='CONNECTED-RETIME-TEST')
    sequence=E.SubElement(project,'sequence',format='p30',duration='12s',tcStart='3600s',audioLayout='stereo',audioRate='48k')
    spine=E.SubElement(sequence,'spine')
    E.SubElement(spine,'gap',offset='3600s',start='0s',duration='2s')
    attrs=dict(offset='3602s',start=start,duration=duration,audioRole='dialogue')
    if parent_tag=='asset-clip':attrs['ref']='camera'
    parent=E.SubElement(spine,parent_tag,**attrs)
    ending=Fraction(2)+Fraction(duration[:-1])
    E.SubElement(spine,'gap',offset=str(Fraction(3600)+ending)+'s',start='0s',duration=str(Fraction(12)-ending)+'s')
    return root,sequence,parent


def mapping(node,points,pitch='0'):
    time_map=E.SubElement(node,'timeMap',preservesPitch=pitch)
    for output,source,*interpolation in points:
        E.SubElement(time_map,'timept',time=str(output)+'s',value=str(source)+'s',interp=interpolation[0] if interpolation else 'linear')
    return time_map


def connected(parent,offset='2s',duration='6s',start='2s'):
    return E.SubElement(parent,'asset-clip',ref='external',lane='-1',offset=offset,start=start,duration=duration,audioRole='dialogue')


class ConnectedRetimeAudioTests(unittest.TestCase):
    def plan(self,root,mode='dialogue'):
        # The normal snapshot path must keep the same independent audio clock.
        with tempfile.TemporaryDirectory() as temp:
            direct=Path(temp)/'direct.fcpxml';direct.write_bytes(E.tostring(root))
            plan=inspect(direct,mode)
            normalized,existing=prepare(E.tostring(root),generic=True)
            self.assertEqual(existing,[])
            prepared=Path(temp)/'prepared.fcpxml';prepared.write_bytes(normalized)
            self.assertEqual(inspect(prepared,mode),plan)
            self.assertEqual((plan['duration'],plan['sampleCount']),('12',192000))
            return plan

    def segment(self,plan,ref):
        matches=[s for s in plan['segments'] if s['assetRef']==ref]
        self.assertEqual(len(matches),1)
        return matches[0]

    def assert_clock(self,segment,offset,source,duration,source_duration=None,pitch=None):
        offset=Fraction(offset);source=Fraction(source);duration=Fraction(duration)
        self.assertEqual((Fraction(segment['offset']),Fraction(segment['source_start']),Fraction(segment['duration'])),(offset,source,duration))
        self.assertEqual((segment['startSample'],segment['sampleCount']),(int(offset*16000),int(duration*16000)))
        if source_duration is None:
            self.assertNotIn('source_duration',segment)
            self.assertNotIn('preservesPitch',segment)
        else:
            self.assertEqual(Fraction(segment['source_duration']),Fraction(source_duration))
            self.assertIs(segment['preservesPitch'],pitch)

    def test_double_speed_source_and_connected_audio_have_separate_clocks(self):
        root,_,parent=fixture();mapping(parent,[(0,0),(6,12)])
        connected(parent,offset='2s')
        plan=self.plan(root)
        self.assert_clock(self.segment(plan,'camera'),2,0,4,8,False)
        # FCP actually starts this child at4, not3; its six source seconds
        # continue four seconds after the parent ends at6.
        self.assert_clock(self.segment(plan,'external'),4,2,6)
        self.assertEqual(plan['skippedAudio'],[])

    def test_half_speed_does_not_stretch_connection_or_inverse_its_offset(self):
        root,_,parent=fixture();mapping(parent,[(0,0),(24,12)])
        connected(parent,offset='1/2s')
        plan=self.plan(root)
        self.assert_clock(self.segment(plan,'camera'),2,0,4,2,False)
        self.assert_clock(self.segment(plan,'external'),Fraction(5,2),2,6)

    def test_silent_or_role_excluded_parent_does_not_mute_independent_dialogue(self):
        for silence in ('disabled','video','music','component'):
            with self.subTest(parent=silence):
                root,_,parent=fixture();mapping(parent,[(0,0),(4,8)])
                E.SubElement(parent,'adjust-volume',amount='-12dB')
                connected(parent)
                if silence=='disabled':parent.set('enabled','0')
                elif silence=='video':parent.set('srcEnable','video')
                elif silence=='music':parent.set('audioRole','music')
                else:E.SubElement(parent,'audio-channel-source',srcCh='1',enabled='0',role='dialogue')
                plan=self.plan(root)
                self.assertEqual([s['assetRef'] for s in plan['segments']],['external'])
                child=self.segment(plan,'external');self.assert_clock(child,4,2,6)
                self.assertEqual(child['gain'],1)
                self.assertEqual(plan['skippedAudio'],[])

    def test_unsupported_audible_parent_skips_only_its_own_interval(self):
        for points,reason in (([(0,8),(4,0)],'倒放'),
                              ([(0,0,'smooth2'),(2,1,'smooth2'),(4,8,'smooth2')],'平滑变速')):
            with self.subTest(reason=reason):
                root,_,parent=fixture();mapping(parent,points)
                connected(parent)
                plan=self.plan(root)
                self.assertEqual([s['assetRef'] for s in plan['segments']],['external'])
                self.assert_clock(self.segment(plan,'external'),4,2,6)
                self.assertEqual(plan['skippedAudio'],[{'offset':'2','duration':'4','startSample':32000,'endSample':96000,'reason':reason}])

    def test_video_only_reverse_and_smooth_parent_keep_connections_without_skips(self):
        for points in ([(0,8),(4,0)],[(0,0,'smooth2'),(2,1,'smooth2'),(4,8,'smooth2')]):
            with self.subTest(points=points):
                root,_,parent=fixture();parent.set('srcEnable','video');mapping(parent,points)
                connected(parent)
                plan=self.plan(root)
                self.assert_clock(self.segment(plan,'external'),4,2,6)
                self.assertEqual(plan['skippedAudio'],[])

    def test_plain_visual_wrapper_does_not_treat_connection_as_primary_audio(self):
        for points in ([(0,0),(4,8)],[(0,8),(4,0)],[(0,0,'smooth2'),(4,8,'smooth2')]):
            with self.subTest(points=points):
                root,_,parent=fixture(parent_tag='clip');mapping(parent,points)
                E.SubElement(parent,'video',ref='camera',offset='0s',start='0s',duration='12s')
                connected(parent)
                plan=self.plan(root)
                self.assertEqual([s['assetRef'] for s in plan['segments']],['external'])
                self.assert_clock(self.segment(plan,'external'),4,2,6)
                self.assertEqual(plan['skippedAudio'],[])

    def test_connection_uses_its_own_retime_and_pitch_choice(self):
        root,_,parent=fixture();mapping(parent,[(0,0),(6,12)],pitch='0')
        child=connected(parent,duration='3s',start='0s')
        mapping(child,[(0,2),(6,14)],pitch='1')
        plan=self.plan(root)
        self.assert_clock(self.segment(plan,'camera'),2,0,4,8,False)
        self.assert_clock(self.segment(plan,'external'),4,2,3,6,True)

    def test_compound_source_is_retimed_but_direct_connection_remains_independent(self):
        root,_,parent=fixture(parent_tag='ref-clip');parent.set('ref','compound')
        media=E.SubElement(root.find('resources'),'media',id='compound')
        sequence=E.SubElement(media,'sequence',format='p30',duration='12s',tcStart='0s')
        spine=E.SubElement(sequence,'spine')
        E.SubElement(spine,'asset-clip',ref='camera',offset='0s',start='1s',duration='12s',audioRole='dialogue')
        mapping(parent,[(0,0),(6,12)]);connected(parent)
        plan=self.plan(root)
        self.assert_clock(self.segment(plan,'camera'),2,1,4,8,False)
        self.assert_clock(self.segment(plan,'external'),4,2,6)

    def test_contained_primary_audio_on_retimed_asset_still_fails_explicitly(self):
        root,_,parent=fixture();mapping(parent,[(0,0),(6,12)])
        E.SubElement(parent,'audio',ref='camera',lane='0',offset='0s',start='0s',duration='8s',srcCh='1')
        connected(parent)
        with self.assertRaisesRegex(ValueError,'内含音频结构'):
            self.plan(root)

    def test_nonzero_adjusted_start_selects_source_window_and_preserves_child_clock(self):
        # Valid isolated FCP fixture: adjusted start1 maps to source2; the
        # three-second parent plays source2..8, while child2-start1 gives3.
        root,_,parent=fixture(start='1s',duration='3s')
        mapping(parent,[(0,0),(6,12)]);connected(parent,offset='2s')
        plan=self.plan(root)
        self.assert_clock(self.segment(plan,'camera'),2,2,3,6,False)
        self.assert_clock(self.segment(plan,'external'),3,2,6)

    def test_connection_is_clipped_by_project_end_with_its_source_window_intact(self):
        root,_,parent=fixture();mapping(parent,[(0,8),(4,0)])
        connected(parent,offset='6s')
        plan=self.plan(root)
        # The six-second child starts8, but this project ends12. Parent
        # visible duration ends6 and must not suppress the later connection.
        self.assert_clock(self.segment(plan,'external'),8,2,4)
        self.assertEqual(plan['skippedAudio'][0]['reason'],'倒放')

    def test_connection_before_project_zero_advances_only_its_own_source_start(self):
        root,_,parent=fixture();mapping(parent,[(0,0),(6,12)])
        connected(parent,offset='-3s')
        plan=self.plan(root)
        self.assert_clock(self.segment(plan,'external'),0,3,5)
        self.assert_clock(self.segment(plan,'camera'),2,0,4,8,False)
