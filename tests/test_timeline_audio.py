from array import array
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
from probes.snapshot import prepare,collision
from probes.timeline_audio import inspect,render
from probes.title_fixture import UID

ROOT=Path(__file__).resolve().parents[1]
FIX=ROOT/'tests/fixtures'

class TimelineAudioTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.directory=Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def source(self,name='mix-split-gain',mutate=None):
        data,existing=prepare((FIX/f'fcp-12.3-{name}.fcpxml').read_bytes())
        root=ET.fromstring(data)
        for m in root.findall('.//media-rep'):m.set('src',(ROOT/'.subloom/verification/mandarin.mp4').as_uri())
        if mutate:mutate(root)
        p=self.directory/'input.fcpxml';p.write_bytes(ET.tostring(root));return p,existing

    def decode(self,name,mutate=None):
        p,_=self.source(name,mutate)
        result=render(p,self.directory,ROOT/'.subloom/build/SubPopAudioProbeCLI',UID)
        data=(self.directory/result['pcmFile']).read_bytes()
        values=array('f');values.frombytes(data)
        return result,data,values

    def test_real_gain_and_cut_preserve_entire_source(self):
        _,whole,values=self.decode('mix-restored')
        result,data,mixed=self.decode('mix-split-gain')
        self.assertEqual(len(mixed),138880)
        self.assertEqual(data[64000*4:],whole[64000*4:])
        self.assertEqual(mixed[:64000],array('f',(v*10**(-6/20) for v in values[:64000])))
        self.assertEqual(len(result['segments']),2)

    def test_real_muted_segment_and_gap_keep_later_timing(self):
        _,whole,_=self.decode('mix-restored')
        for name in ('mix-split-muted','mix-leading-gap'):
            with self.subTest(name=name):
                result,data,_=self.decode(name)
                self.assertEqual(data[:64000*4],bytes(64000*4))
                self.assertEqual(data[64000*4:],whole[64000*4:])
                self.assertEqual(result['segments'][0]['sourceStart'],'4')

    def test_whole_disabled_or_component_disabled_skips_decoder(self):
        for name in ('audio-component-disabled','audio-split-4s'):
            p,_=self.source(name)
            with patch('probes.timeline_audio.subprocess.run',side_effect=AssertionError('Must not decode muted audio')):
                result=render(p,self.directory,Path('unused'),UID)
            self.assertTrue(result['silent'])
            self.assertEqual((self.directory/result['pcmFile']).read_bytes(),bytes(138880*4))

    def test_title_collision_uses_each_parent_source_clock(self):
        _,old=prepare((FIX/'fcp-12.3-mix-restored.fcpxml').read_bytes())
        for name in ('mix-split-gain','mix-split-muted','mix-leading-gap'):
            _,existing=prepare((FIX/f'fcp-12.3-{name}.fcpxml').read_bytes())
            self.assertEqual(collision(old,existing)['status'],'duplicate')

    def test_unhandled_audio_cannot_be_silently_ignored(self):
        mutations=[lambda r:r.find('.//asset-clip').set('audioStart','1s'),
                   lambda r:ET.SubElement(r.find('.//asset-clip'),'timeMap'),
                   lambda r:ET.SubElement(r.find('.//asset-clip'),'filter-audio'),
                   lambda r:ET.SubElement(r.find('.//adjust-volume'),'param'),
                   lambda r:r.find('.//asset').set('audioChannels','2'),
                   lambda r:r.find('.//asset-clip').set('srcEnable','bogus'),
                   lambda r:r.find('.//adjust-volume').set('amount','NaNdB'),
                   lambda r:r.find('.//asset-clip').set('offset','3601s'),
                   lambda r:r.find('.//sequence').set('duration','9s')]
        for i,mutate in enumerate(mutations):
            with self.subTest(case=i):
                p,_=self.source(mutate=mutate)
                with self.assertRaises(ValueError):inspect(p)

    def test_restoration_exact(self):
        def shape(e):return e.tag,sorted(e.attrib.items()),(e.text or '').strip(),[shape(c) for c in e]
        self.assertEqual(shape(ET.parse(FIX/'fcp-12.3-audio-restored.fcpxml').find('.//sequence')),
                         shape(ET.parse(FIX/'fcp-12.3-mix-restored.fcpxml').find('.//sequence')))
