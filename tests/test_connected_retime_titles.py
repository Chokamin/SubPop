"""Keep connected title clocks independent from their anchor's retiming."""
from fractions import Fraction
import unittest
import xml.etree.ElementTree as E

from probes.snapshot import prepare


def fixture(frame='1/30s'):
    root=E.Element('fcpxml',version='1.14')
    resources=E.SubElement(root,'resources')
    E.SubElement(resources,'format',id='f',frameDuration=frame,width='640',height='360')
    asset=E.SubElement(resources,'asset',id='a',start='0s',duration='32s',hasVideo='1',hasAudio='0',format='f')
    E.SubElement(asset,'media-rep',kind='original-media',src='file:///tmp/subpop-title-clock-test.mov')
    E.SubElement(resources,'effect',id='t',uid='third-party-silent-visual-title')
    project=E.SubElement(root,'project',name='Connected title clocks',uid='CONNECTED-TITLE-CLOCKS')
    sequence=E.SubElement(project,'sequence',format='f',duration='8s',tcStart='3600s')
    spine=E.SubElement(sequence,'spine')
    clip=E.SubElement(spine,'asset-clip',ref='a',offset='3600s',start='0s',duration='4s')
    E.SubElement(spine,'gap',offset='3604s',start='0s',duration='4s')
    return root,resources,sequence,spine,clip


def add_map(clip,points,interp='linear'):
    mapping=E.SubElement(clip,'timeMap',preservesPitch='0')
    for time,value in points:
        E.SubElement(mapping,'timept',time=time,value=value,interp=interp)
    return mapping


def add_title(parent,offset='2s',duration='2s',lane='1',text='Existing title'):
    title=E.SubElement(parent,'title',ref='t',offset=offset,duration=duration,lane=lane)
    E.SubElement(title,'text').text=text
    return title


class ConnectedRetimeTitleTests(unittest.TestCase):
    def normalized(self,root):
        before=E.tostring(root)
        normalized,existing=prepare(before,generic=True)
        self.assertEqual(E.tostring(root),before)
        self.assertEqual(E.fromstring(normalized).findall('.//title'),[])
        return E.fromstring(normalized),existing

    def ranges(self,root):
        _,existing=self.normalized(root)
        return [(title['text'],title['start_frame'],title['end_frame']) for title in existing]

    def test_fcp_roundtrip_anchor_offsets_keep_original_extent(self):
        # FCP 12.3 round-trip/host positions from the independent Build 145
        # audio project: these are adjusted local offsets, not source values.
        root,_,sequence,spine,_=fixture()
        spine.clear();sequence.set('duration','60s')
        cases=(
            ('2x','0s','2s',(('0s','0s'),('6s','12s')),'linear',4),
            ('Half','0s','1/2s',(('0s','0s'),('24s','12s')),'linear',Fraction(29,2)),
            ('Reverse','0s','6s',(('0s','8s'),('4s','0s')),'linear',32),
            ('Smooth','0s','2s',(('0s','0s'),('2s','1s'),('154/30s','12s')),'smooth2',40),
            ('Trimmed','2s','4s',(('-23999/24000s','0s'),('5s','12s')),'linear',52),
        )
        expected=[]
        for index,(name,start,offset,points,interp,begin) in enumerate(cases):
            base=3600+12*index
            E.SubElement(spine,'gap',offset=f'{base}s',duration='2s')
            clip=E.SubElement(spine,'asset-clip',ref='a',offset=f'{base+2}s',start=start,duration='4s')
            add_map(clip,points,interp)
            add_title(clip,offset,'6s',text=name)
            E.SubElement(spine,'gap',offset=f'{base+6}s',duration='6s')
            expected.append((name,int(begin*30),int((begin+6)*30)))
        self.assertEqual(self.ranges(root),expected)

    def test_connected_and_contained_titles_use_different_clocks(self):
        root,_,_,_,clip=fixture()
        add_map(clip,(('0s','0s'),('4s','8s')))
        add_title(clip,text='Connected')
        add_title(clip,lane='0',text='Contained')
        self.assertCountEqual(self.ranges(root),[('Connected',60,120),('Contained',30,60)])

    def test_parent_speed_changes_do_not_shorten_connection(self):
        root,_,_,_,clip=fixture()
        add_map(clip,(('0s','0s'),('2s','2s'),('4s','8s')))
        add_title(clip,'3s','3s')
        normalized,existing=self.normalized(root)
        self.assertEqual((existing[0]['start_frame'],existing[0]['end_frame']),(90,180))
        self.assertEqual(E.tostring(normalized.find('.//asset-clip/timeMap')),
                         E.tostring(clip.find('timeMap')))

    def test_connection_can_precede_or_outlast_anchor(self):
        root,_,_,spine,clip=fixture()
        clip.set('offset','3602s')
        spine[1].set('offset','3606s');spine[1].set('duration','2s')
        spine.insert(0,E.Element('gap',offset='3600s',duration='2s'))
        add_map(clip,(('0s','0s'),('4s','8s')))
        add_title(clip,'-1s','3s',text='Lead')
        add_title(clip,'3s','4s',text='Tail')
        self.assertCountEqual(self.ranges(root),[('Lead',30,120),('Tail',150,240)])

    def test_connected_title_ignores_unsupported_parent_source_curve(self):
        cases=(
            ((('0s','8s'),('4s','0s')),'linear'),
            ((('0s','0s'),('4s','8s')),'smooth2'),
            ((('0s','2s'),('4s','2s')),'linear'),
        )
        for points,interp in cases:
            with self.subTest(points=points,interp=interp):
                root,_,_,_,clip=fixture()
                add_map(clip,points,interp)
                add_title(clip,text='Connected')
                add_title(clip,lane='0',text='Unknown source timing')
                self.assertEqual(self.ranges(root),[('Connected',60,120)])

    def test_connected_container_keeps_its_own_start_and_title_duration(self):
        root,_,_,_,clip=fixture()
        add_map(clip,(('0s','0s'),('4s','8s')))
        connected=E.SubElement(clip,'asset-clip',ref='a',lane='1',offset='2s',start='5s',duration='5s')
        add_title(connected,'6s','3s')
        self.assertEqual(self.ranges(root),[('Existing title',90,180)])

    def test_connected_secondary_storyline_uses_its_output_offset(self):
        root,_,_,_,clip=fixture()
        add_map(clip,(('0s','0s'),('4s','8s')))
        connected=E.SubElement(clip,'spine',lane='1',offset='2s')
        add_title(connected,'1s','2s')
        self.assertEqual(self.ranges(root),[('Existing title',90,150)])

    def test_compound_source_title_still_follows_outer_retime(self):
        root,resources,_,spine,clip=fixture()
        media=E.SubElement(resources,'media',id='compound')
        inner=E.SubElement(media,'sequence',format='f',duration='8s',tcStart='0s')
        inner_clip=E.SubElement(E.SubElement(inner,'spine'),'asset-clip',ref='a',offset='0s',start='0s',duration='8s')
        add_title(inner_clip,text='Compound source')
        spine.remove(clip)
        outer=E.Element('ref-clip',ref='compound',offset='3600s',start='0s',duration='4s')
        spine.insert(0,outer)
        add_map(outer,(('0s','0s'),('4s','8s')))
        add_title(outer,text='Outer connection')
        self.assertCountEqual(self.ranges(root),[('Compound source',30,60),('Outer connection',60,120)])

    def test_inner_connection_keeps_ancestor_compound_warp(self):
        root,resources,_,spine,clip=fixture()
        media=E.SubElement(resources,'media',id='compound')
        inner=E.SubElement(media,'sequence',format='f',duration='4s',tcStart='0s')
        inner_clip=E.SubElement(E.SubElement(inner,'spine'),'asset-clip',ref='a',offset='0s',start='0s',duration='4s')
        add_map(inner_clip,(('0s','0s'),('4s','8s')))
        add_title(inner_clip,'1s','2s',text='Inner connection')
        spine.remove(clip)
        outer=E.Element('ref-clip',ref='compound',offset='3600s',start='0s',duration='2s')
        spine.insert(0,outer)
        spine[1].set('offset','3602s');spine[1].set('duration','6s')
        add_map(outer,(('0s','0s'),('2s','4s')))
        add_title(outer,'1s','1s',text='Outer connection')
        self.assertCountEqual(self.ranges(root),[('Inner connection',15,45),('Outer connection',30,60)])

    def test_fractional_frame_connection_remains_exact(self):
        root,_,_,_,clip=fixture('1001/30000s')
        add_map(clip,(('0s','0s'),('4s','8s')))
        add_title(clip,'1001/30000s','2002/30000s')
        _,existing=self.normalized(root)
        self.assertEqual((existing[0]['start_frame'],existing[0]['end_frame']),(1,3))
        self.assertTrue(existing[0]['exactTiming'])

    def test_missing_clip_start_uses_nonzero_asset_clock(self):
        root,resources,_,_,clip=fixture()
        resources.find('asset').set('start','10s')
        clip.attrib.pop('start')
        add_map(clip,(('10s','10s'),('14s','18s')))
        add_title(clip,'12s','2s',lane='0',text='Contained source')
        add_title(clip,'12s','1s',text='Connected output')
        self.assertCountEqual(self.ranges(root),[('Contained source',30,60),('Connected output',60,90)])

    def test_missing_reference_start_uses_nonzero_media_timecode(self):
        root,resources,_,spine,clip=fixture()
        media=E.SubElement(resources,'media',id='compound')
        inner=E.SubElement(media,'sequence',format='f',duration='8s',tcStart='10s')
        inner_clip=E.SubElement(E.SubElement(inner,'spine'),'asset-clip',ref='a',offset='10s',start='0s',duration='8s')
        add_title(inner_clip,'2s','2s',text='Compound source')
        spine.remove(clip)
        outer=E.Element('ref-clip',ref='compound',offset='3600s',duration='4s')
        spine.insert(0,outer)
        add_map(outer,(('10s','10s'),('14s','18s')))
        add_title(outer,'12s','1s',text='Connected output')
        self.assertCountEqual(self.ranges(root),[('Compound source',30,60),('Connected output',60,90)])


if __name__=='__main__':
    unittest.main()
