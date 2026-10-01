"""Audio clocks for split edits and fractional-rate source formats."""
from fractions import Fraction
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
from test_project import basic,compound
from probes import project
from probes.snapshot import prepare

class AudioEditTests(unittest.TestCase):
    def inspect(self,root):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'project.fcpxml';path.write_bytes(ET.tostring(root))
            return project.inspect(path)

    def fixture(self):
        root,p,seq,clip=basic();asset=root.find('resources/asset')
        asset.set('duration','20s');seq.set('duration','8s');clip.set('duration','8s');clip.set('start','0s')
        return root,p,seq,clip,asset

    def test_audio_shorter_than_picture_preserves_silence_clock(self):
        root,_,_,clip,_=self.fixture();clip.set('audioStart','2s');clip.set('audioDuration','3s')
        plan=self.inspect(root);s=plan['segments'][0]
        self.assertEqual((s['offset'],s['source_start'],s['duration']),('2','2','3'))
        self.assertEqual((plan['sampleCount'],s['startSample'],s['sampleCount']),(128000,32000,48000))

    def test_audio_tail_outlasts_last_picture(self):
        root,_,_,clip,_=self.fixture();clip.set('duration','4s');clip.set('audioDuration','8s')
        plan=self.inspect(root);self.assertEqual(plan['segments'][0]['duration'],'8')
        self.assertEqual(plan['sampleCount'],128000)

    def test_j_cut_before_picture_uses_source_time_not_zero(self):
        root,_,seq,clip,_=self.fixture();seq.set('duration','6s');clip.set('offset','3602s');clip.set('start','8s');clip.set('duration','4s')
        clip.set('audioStart','6s');clip.set('audioDuration','6s')
        seq.find('spine').insert(0,ET.Element('gap',offset='3600s',start='0s',duration='2s'))
        s=self.inspect(root)['segments'][0]
        self.assertEqual((s['offset'],s['source_start'],s['duration']),('0','6','6'))

    def test_audio_outside_project_is_clipped_without_shift(self):
        root,_,_,clip,_=self.fixture();clip.set('start','4s');clip.set('audioStart','2s');clip.set('audioDuration','12s')
        s=self.inspect(root)['segments'][0]
        self.assertEqual((s['offset'],s['source_start'],s['duration']),('0','4','8'))

    def test_connected_audio_is_not_duplicated_or_trimmed_by_jl(self):
        root,_,_,clip,asset=self.fixture();clip.set('audioDuration','2s')
        ET.SubElement(clip,'asset-clip',ref=asset.get('id'),lane='-1',offset='3s',start='10s',duration='4s',audioRole='dialogue')
        s=self.inspect(root)['segments'];self.assertEqual(len(s),2)
        self.assertCountEqual([(x['offset'],x['source_start'],x['duration']) for x in s],[('0','0','2'),('3','10','4')])

    def test_compound_and_plain_containers_use_independent_audio_bounds(self):
        root,_,seq,clip,_=self.fixture();_,ref=compound(root,seq,clip);ref.set('audioStart','2s');ref.set('audioDuration','3s')
        s=self.inspect(root)['segments'][0];self.assertEqual((s['offset'],s['source_start'],s['duration']),('2','2','3'))
        root,_,seq,clip,_=self.fixture();seq.find('spine').remove(clip)
        wrapper=ET.SubElement(seq.find('spine'),'clip',offset='3600s',start='0s',duration='8s',audioStart='2s',audioDuration='3s')
        clip.set('offset','0s');wrapper.append(clip)
        s=self.inspect(root)['segments'][0];self.assertEqual((s['offset'],s['source_start'],s['duration']),('2','2','3'))

    def test_empty_or_video_only_split_audio_stays_silent(self):
        for attrs in ({'audioDuration':'0s'},{'audioDuration':'2s','srcEnable':'video'},{'audioDuration':'2s','enabled':'0'}):
            root,_,_,clip,_=self.fixture();clip.attrib.update(attrs)
            self.assertEqual(self.inspect(root)['segments'],[])

    def test_invalid_split_audio_does_not_silently_pass(self):
        for attrs in ({'audioDuration':'-1s'},{'audioStart':'bad'},{'audioStart':'-1s'},
                      {'audioDuration':'2s','mystery':'1'},{'audioDuration':'2s','srcEnable':'bad'}):
            root,_,_,clip,_=self.fixture();clip.attrib.update(attrs)
            # A source before zero must actually be visible to be invalid.
            if attrs.get('audioStart')=='-1s':clip.set('start','-1s')
            with self.assertRaises(ValueError):self.inspect(root)

    def test_fractional_source_format_conform_does_not_double_audio(self):
        for frame in ('1/24s','1/25s','1001/30000s','1001/60000s'):
            root,_,_,clip,asset=self.fixture()
            root.find("resources/format[@id='r1']").set('frameDuration',frame)
            root.find("resources/format[@id='r3']").set('frameDuration','1001/60000s')
            clip.set('format',asset.get('format'));ET.SubElement(clip,'conform-rate',srcFrameRate='59.94')
            s=self.inspect(root)['segments'][0];self.assertEqual(s['duration'],'8');self.assertNotIn('source_duration',s)
            clip.set('audioStart','2s');clip.set('audioDuration','3s')
            s=self.inspect(root)['segments'][0];self.assertEqual((s['offset'],s['source_start'],s['duration']),('2','2','3'))

    def test_source_format_rate_mismatch_remains_rejected(self):
        root,_,_,clip,asset=self.fixture();clip.set('format',asset.get('format'))
        ET.SubElement(clip,'conform-rate',srcFrameRate='59.94')
        with self.assertRaises(ValueError):self.inspect(root)

    def test_fractional_conform_without_format_keeps_fcp_audio_clock(self):
        for frame in ('1/25s','1001/30000s','1001/60000s'):
            root,_,_,clip,_=self.fixture()
            root.find("resources/format[@id='r1']").set('frameDuration',frame)
            root.find("resources/format[@id='r3']").set('frameDuration','1001/60000s')
            for scale in (None,'1'):
                c=ET.SubElement(clip,'conform-rate',srcFrameRate='59.94')
                if scale:c.set('scaleEnabled',scale)
                s=self.inspect(root)['segments'][0]
                self.assertEqual(s['duration'],'8');self.assertNotIn('source_duration',s)
                clip.remove(c)

    def test_equal_rate_format_ids_do_not_change_audio_speed(self):
        root,_,_,clip,_=self.fixture()
        root.find("resources/format[@id='r3']").set('frameDuration','1001/60000s')
        ET.SubElement(root.find('resources'),'format',id='clipformat',frameDuration='1001/60000s')
        clip.set('format','clipformat');ET.SubElement(clip,'conform-rate',srcFrameRate='59.94')
        s=self.inspect(root)['segments'][0];self.assertNotIn('source_duration',s)
        root.find("resources/format[@id='clipformat']").set('frameDuration','1/25s')
        with self.assertRaisesRegex(ValueError,'帧率适配'):self.inspect(root)

    def test_fcp_roundtrip_5994_and_jl_audio_clocks(self):
        # Sanitized FCP 12.3 export; its WAV references all retain a 1x chirp,
        # and J/L begins at source second 1 for the entire six-second project.
        source=ET.parse(Path(__file__).parent/'fixtures/fcp-12.3-5994-jl-roundtrip.fcpxml').getroot()
        for p in source.findall('.//project'):
            root=ET.Element('fcpxml',version='1.14')
            root.append(ET.fromstring(ET.tostring(source.find('resources'))))
            root.append(ET.fromstring(ET.tostring(p)))
            plan=self.inspect(root);s=plan['segments'][0]
            normalized,existing=prepare(ET.tostring(root),generic=True)
            self.assertEqual(existing,[])
            self.assertEqual(self.inspect(ET.fromstring(normalized)),plan)
            self.assertNotIn('source_duration',s)
            is_jl=p.get('name')=='SubPop133-JL-enabled'
            self.assertEqual((s['offset'],s['source_start']),('0','1' if is_jl else '0'))
            self.assertEqual(plan['sampleCount'],96000 if is_jl else 64000 if '-25-' in p.get('name') else 64064)

    def test_jl_retime_is_explicitly_refused_without_losing_video_only_case(self):
        root,_,_,clip,_=self.fixture();clip.set('audioDuration','2s')
        mapping=ET.SubElement(clip,'timeMap');ET.SubElement(mapping,'timept',time='0s',value='0s',interp='linear')
        ET.SubElement(mapping,'timept',time='8s',value='16s',interp='linear')
        with self.assertRaisesRegex(ValueError,'分离音频起止与变速'):self.inspect(root)
        clip.set('srcEnable','video');self.assertEqual(self.inspect(root)['segments'],[])
