from fractions import Fraction
from pathlib import Path
import tempfile
import subprocess
import unittest
import xml.etree.ElementTree as ET
from probes import project
from probes.snapshot import prepare
from probes.title_fixture import payload
from probes.caption_fixture import captions,srt

FIXTURE=Path(__file__).parent/'fixtures/fcp-12.3-native-drop.fcpxml'

def basic():
    root=ET.fromstring(FIXTURE.read_bytes());p=root.find('.//project');p.set('name','Daily tutorial');p.set('uid','DAILY-PROJECT')
    seq=p.find('sequence');clip=seq.find('spine/asset-clip')
    for child in list(clip):clip.remove(child)
    return root,p,seq,clip

class ProjectTests(unittest.TestCase):
    def inspect(self,root,mode='dialogue'):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'project.fcpxml';path.write_bytes(ET.tostring(root))
            return project.inspect(path,mode)

    def test_arbitrary_project_stereo_connected_music_excluded_or_mixed(self):
        root,p,seq,clip=basic();asset=root.find('resources/asset');asset.set('audioChannels','2')
        ET.SubElement(clip,'asset-clip',ref=asset.get('id'),name='BGM',lane='-1',offset=clip.get('start','0s'),start=clip.get('start','0s'),duration=clip.get('duration'),audioRole='music')
        plan=self.inspect(root)
        self.assertEqual(plan['project'],'Daily tutorial');self.assertEqual(plan['ignoredRoleClips'],1)
        self.assertEqual(len(plan['segments']),1)
        mixed=self.inspect(root,'all');self.assertEqual(len(mixed['segments']),2)
        self.assertEqual(mixed['segments'][0]['startSample'],mixed['segments'][1]['startSample'])

    def test_music_fade_is_ignored_only_in_dialogue_mode(self):
        root,p,seq,clip=basic();asset=root.find('resources/asset')
        music=ET.SubElement(clip,'asset-clip',ref=asset.get('id'),lane='-1',offset=clip.get('start','0s'),start=clip.get('start','0s'),duration=clip.get('duration'),audioRole='music')
        volume=ET.SubElement(music,'adjust-volume',amount='-12dB');ET.SubElement(volume,'param')
        self.assertEqual(len(self.inspect(root)['segments']),1)
        with self.assertRaises(ValueError):self.inspect(root,'all')

    def test_long_project_clock_and_fractional_frame_rate(self):
        root,p,seq,clip=basic();seq.set('duration','1800s');spine=seq.find('spine');spine.remove(clip)
        ET.SubElement(spine,'gap',offset=seq.get('tcStart','0s'),duration='1800s',start='0s')
        self.assertEqual(self.inspect(root)['sampleCount'],1800*16000)
        for duration in (1801,2700,7200):
            seq.set('duration',f'{duration}s');spine[0].set('duration',f'{duration}s')
            plan=self.inspect(root)
            self.assertEqual(plan['sampleCount'],duration*16000)
            manifest={**plan,'captions':[{'text':'片尾字幕','start_frame':plan['totalFrames']-25,'end_frame':plan['totalFrames']}]}
            for version in ('1.12','1.13','1.14'):
                result=ET.fromstring(payload(manifest,version))
                self.assertEqual(Fraction(result.find('clip').get('duration')[:-1]),duration)
                self.assertEqual(Fraction(result.find('clip/spine/title').get('offset')[:-1]),duration-1)
        seq.set('duration','0s')
        with self.assertRaises(ValueError):self.inspect(root)
        fmt=root.find(f"resources/format[@id='{seq.get('format')}']");fmt.set('frameDuration','1001/30000s')
        seq.set('duration','1001/10s');spine[0].set('duration','1001/10s')
        plan=self.inspect(root);self.assertEqual(plan['totalFrames'],3000)
        self.assertEqual(Fraction(plan['frameDuration']),Fraction(1001,30000))

    def test_disabled_rate_conform_preserves_audio_clock(self):
        root,p,seq,clip=basic();before=self.inspect(root)
        root.find('resources/format').set('frameDuration','1/25s')
        ET.SubElement(clip,'conform-rate',scaleEnabled='0',srcFrameRate='30',frameSampling='optical-flow')
        self.assertEqual(self.inspect(root),before)

    def test_rate_conform_scaling_and_malformed_nodes_refused(self):
        for attrs in ({},{'scaleEnabled':'1'},{'scaleEnabled':'false'},{'scaleEnabled':'0','unknown':'1'}):
            root,p,seq,clip=basic();ET.SubElement(clip,'conform-rate',**attrs)
            with self.assertRaises(ValueError):self.inspect(root)
        for extra in ('duplicate','child','timeMap'):
            root,p,seq,clip=basic();c=ET.SubElement(clip,'conform-rate',scaleEnabled='0')
            if extra=='duplicate':ET.SubElement(clip,'conform-rate',scaleEnabled='0')
            elif extra=='child':ET.SubElement(c,'timept')
            else:ET.SubElement(clip,'timeMap')
            with self.assertRaises(ValueError):self.inspect(root)

    def test_connected_dialogue_parent_source_offset_and_mute(self):
        root,p,seq,clip=basic();asset=root.find('resources/asset')
        ET.SubElement(clip,'asset-clip',ref=asset.get('id'),offset='2s',start='0s',duration='1s',audioRole='dialogue',lane='-1')
        self.assertEqual(self.inspect(root)['segments'][1]['startSample'],32000)
        clip.set('enabled','0');plan=self.inspect(root);self.assertEqual(len(plan['segments']),1);self.assertEqual(plan['segments'][0]['startSample'],32000)

    def test_audio_effect_retime_and_jl_are_rejected(self):
        for change in ('timeMap','filter-audio','audioDuration'):
            root,p,seq,clip=basic()
            if change=='audioDuration':clip.set(change,'1s')
            else:ET.SubElement(clip,change)
            with self.assertRaises(ValueError):self.inspect(root)

    def test_general_title_format_escapes_text_and_preserves_fractional_time(self):
        m={'projectUID':'DAILY','frameDuration':'1001/30000','totalFrames':3000,'width':'1920','height':'1080','captions':[{'text':'A & B <测试>','start_frame':100,'end_frame':130}]}
        root=ET.fromstring(payload(m));title=root.find('clip/spine/title')
        self.assertEqual(title.find('text/text-style').text,'A & B <测试>')
        self.assertEqual(Fraction(title.get('offset')[:-1]),Fraction(1001,300))
        self.assertEqual(root.find('resources/format').get('width'),'1920')
        self.assertIn('00:00:03,337',srt(m['captions'],Fraction(30000,1001)))

    def test_general_title_payload_passes_official_dtd(self):
        dtd=Path(__file__).resolve().parents[1]/'.subloom/verification/FCPXMLv1_14.dtd'
        m={'projectUID':'DAILY','frameDuration':'1001/30000','totalFrames':3000,'width':'1920','height':'1080','captions':[{'text':'校对 & <保留>','start_frame':0,'end_frame':100}]}
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)/'titles.fcpxml';p.write_bytes(payload(m))
            subprocess.run(['xmllint','--noout','--dtdvalid',str(dtd),str(p)],capture_output=True,check=True)

    def test_generic_snapshot_preserves_original_title_times(self):
        path=Path(__file__).parent/'fixtures/fcp-12.3-title-split.fcpxml'
        normalized,existing=prepare(path.read_bytes(),generic=True)
        self.assertEqual(len(existing),3)
        self.assertEqual(existing[1]['start_frame'],84)
        self.assertNotIn(b'<title ',normalized)
