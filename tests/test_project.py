from fractions import Fraction
from pathlib import Path
import tempfile
import subprocess
import unittest
import xml.etree.ElementTree as ET
from probes import project
from probes.snapshot import prepare,bypassed_audio_transitions
from probes.title_fixture import payload
from probes.caption_fixture import captions,srt,quantize

FIXTURE=Path(__file__).parent/'fixtures/fcp-12.3-native-drop.fcpxml'

def basic():
    root=ET.fromstring(FIXTURE.read_bytes());p=root.find('.//project');p.set('name','Daily tutorial');p.set('uid','DAILY-PROJECT')
    seq=p.find('sequence');clip=seq.find('spine/asset-clip')
    for child in list(clip):clip.remove(child)
    return root,p,seq,clip

def compound(root,seq,clip,media_id='compound'):
    """Wrap one ordinary clip in a FCPXML compound media sequence."""
    duration=clip.get('duration')
    spine=seq.find('spine');spine.remove(clip)
    media=ET.SubElement(root.find('resources'),'media',id=media_id)
    inner=ET.SubElement(media,'sequence',format=seq.get('format'),duration=duration,tcStart='0s')
    ET.SubElement(inner,'spine').append(clip)
    clip.set('offset','0s')
    ref=ET.SubElement(spine,'ref-clip',ref=media_id,offset=seq.get('tcStart','0s'),start='0s',duration=duration)
    return media,ref

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

    def test_short_fcp_audio_crossfade_keeps_direct_audio_as_hard_cut(self):
        root,_,seq,first=basic()
        first.set('duration','4s')
        second=ET.fromstring(ET.tostring(first))
        second.set('offset','3604s');second.set('start','4s');second.set('duration','117/25s')
        spine=seq.find('spine')
        transition=ET.SubElement(spine,'transition',offset='18019/5s',duration='2/5s',name='Visual transition')
        effect=ET.SubElement(root.find('resources'),'effect',id='crossfade',uid='FFAudioTransition')
        ET.SubElement(transition,'filter-audio',ref=effect.get('id'),name='音频交叉淡入淡出')
        ET.SubElement(transition,'filter-video',ref='custom-visual')
        spine.append(second)
        original=ET.tostring(root)
        normalized,_=prepare(original,generic=True)
        self.assertEqual(len(ET.fromstring(normalized).findall('.//spine/transition')),0)
        self.assertEqual(bypassed_audio_transitions(original),[{'offset':'19/5','duration':'2/5'}])
        with tempfile.TemporaryDirectory() as temp:
            xml=Path(temp)/'input.fcpxml';xml.write_bytes(normalized)
            plan=project.inspect(xml)
        self.assertEqual([(s['offset'],s['duration']) for s in plan['segments']],[('0','4'),('4','117/25')])
        effect.set('uid','unknown-audio-effect')
        with self.assertRaisesRegex(ValueError,'转场音频无法安全处理'):
            prepare(ET.tostring(root),generic=True)
        effect.set('uid','FFAudioTransition');transition.set('duration','3s')
        with self.assertRaisesRegex(ValueError,'转场结构无法安全处理'):
            prepare(ET.tostring(root),generic=True)

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

    def test_fcp_verified_60_to_2997_rate_conform_maps_audio_at_double_speed(self):
        root,p,seq,clip=basic();asset=root.find('resources/asset')
        root.find("resources/format[@id='r1']").set('frameDuration','1001/30000s')
        root.find("resources/format[@id='r3']").set('frameDuration','1/60s')
        seq.set('duration','4s');clip.set('duration','4s');asset.set('duration','8s')
        ET.SubElement(clip,'conform-rate',srcFrameRate='60') # DTD defaults scaleEnabled to 1.
        segment=self.inspect(root)['segments'][0]
        self.assertEqual((segment['source_start'],segment['source_duration'],segment['duration']),('0','8','4'))
        self.assertFalse(segment['preservesPitch'])
        clip.find('conform-rate').set('scaleEnabled','0')
        segment=self.inspect(root)['segments'][0]
        self.assertNotIn('source_duration',segment)

    def test_rate_conform_maps_audio_nested_in_plain_clip(self):
        root,p,seq,clip=basic();asset=root.find('resources/asset')
        root.find("resources/format[@id='r1']").set('frameDuration','1001/30000s')
        root.find("resources/format[@id='r3']").set('frameDuration','1/60s')
        seq.set('duration','4s');asset.set('duration','8s');asset.set('audioChannels','2')
        spine=seq.find('spine');spine.remove(clip)
        wrapper=ET.SubElement(spine,'clip',offset='3600s',start='0s',duration='4s')
        ET.SubElement(wrapper,'audio-channel-source',srcCh='1',role='dialogue.dialogue-1')
        ET.SubElement(wrapper,'audio-channel-source',srcCh='2',role='dialogue.dialogue-2')
        ET.SubElement(wrapper,'conform-rate',srcFrameRate='60')
        gap=ET.SubElement(wrapper,'gap',offset='0s',duration='8s')
        ET.SubElement(gap,'audio',ref=asset.get('id'),lane='-1',offset='0s',start='0s',duration='8s',srcCh='1, 2')
        segment=self.inspect(root)['segments'][0]
        self.assertEqual((segment['source_start'],segment['source_duration'],segment['duration']),('0','8','4'))
        self.assertFalse(segment['preservesPitch'])
        wrapper.find('audio-channel-source').set('enabled','0')
        with self.assertRaises(ValueError):self.inspect(root)

    def test_compound_and_nested_compound_preserve_source_clock(self):
        root,p,seq,clip=basic();original=self.inspect(root)['segments']
        media,ref=compound(root,seq,clip)
        self.assertEqual(self.inspect(root)['segments'],original)
        outer=ET.SubElement(root.find('resources'),'media',id='outer')
        inner=ET.SubElement(outer,'sequence',format=seq.get('format'),duration=ref.get('duration'),tcStart='0s')
        spine=ET.SubElement(inner,'spine');seq.find('spine').remove(ref);ref.set('offset','0s');spine.append(ref)
        ET.SubElement(seq.find('spine'),'ref-clip',ref='outer',offset=seq.get('tcStart'),start='0s',duration=seq.get('duration'))
        self.assertEqual(self.inspect(root)['segments'],original)
        ref.set('ref','outer')
        with self.assertRaisesRegex(ValueError,'循环'):self.inspect(root)

    def test_compound_trim_music_role_and_connected_titles(self):
        root,p,seq,clip=basic();media,ref=compound(root,seq,clip)
        seq.set('duration','2s');ref.set('start','1s');ref.set('duration','2s')
        segment=self.inspect(root)['segments'][0]
        self.assertEqual((segment['source_start'],segment['startSample'],segment['sampleCount']),('1',0,32000))
        ref.set('audioRole','music')
        self.assertEqual(self.inspect(root)['segments'],[])
        self.assertEqual(len(self.inspect(root,'all')['segments']),1)
        ref.set('audioRole','dialogue')
        ref.set('useAudioSubroles','1')
        component=ET.SubElement(ref,'audio-role-source',role='dialogue.dialogue-1')
        self.assertEqual(self.inspect(root)['segments'][0]['source_start'],'1')
        component.set('active','0')
        with self.assertRaisesRegex(ValueError,'单独静音'):self.inspect(root)
        component.set('active','1')
        effect=ET.SubElement(root.find('resources'),'effect',id='titleEffect',uid='third-party-visual-title')
        title=ET.SubElement(clip,'title',ref=effect.get('id'),offset='1s',start='0s',duration='1s')
        ET.SubElement(title,'text').text='已有文字'
        normalized,existing=prepare(ET.tostring(root),generic=True)
        self.assertEqual(len(existing),1)
        self.assertEqual((existing[0]['start_frame'],existing[0]['end_frame']),(0,25))
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'audio.fcpxml';path.write_bytes(normalized)
            self.assertEqual(self.inspect(ET.fromstring(normalized))['segments'][0]['source_start'],'1')

    def test_visual_only_compound_reused_twice_does_not_block_audio(self):
        root,p,seq,clip=basic();original=self.inspect(root)['segments']
        effect=ET.SubElement(root.find('resources'),'effect',id='visualEffect',uid='third-party-title')
        media=ET.SubElement(root.find('resources'),'media',id='visualCompound')
        inner=ET.SubElement(media,'sequence',format=seq.get('format'),duration='1s',tcStart='0s')
        title=ET.SubElement(ET.SubElement(inner,'spine'),'title',ref=effect.get('id'),offset='0s',duration='1s')
        ET.SubElement(title,'text').text='视觉标题'
        for at in ('0s','2s'):
            ET.SubElement(clip,'ref-clip',ref=media.get('id'),lane='1',offset=at,start='0s',duration='1s')
        normalized,existing=prepare(ET.tostring(root),generic=True)
        self.assertEqual([(t['start_frame'],t['end_frame']) for t in existing],[(0,25),(50,75)])
        self.assertEqual(self.inspect(ET.fromstring(normalized))['segments'],original)
        self.assertEqual(len(ET.fromstring(normalized).findall('.//title')),0)
        self.assertEqual(len(ET.fromstring(normalized).findall('resources/media/sequence/spine/gap')),1)

    def test_linear_retime_segments_and_skipped_curves(self):
        root,p,seq,clip=basic();seq.set('duration','4s');clip.set('duration','4s')
        mapping=ET.SubElement(clip,'timeMap',preservesPitch='1')
        for out,source in ((0,0),(2,2),(4,8)):
            ET.SubElement(mapping,'timept',time=f'{out}s',value=f'{source}s',interp='linear')
        plan=self.inspect(root)
        self.assertEqual([(s['startSample'],s['sampleCount'],s['source_start'],s['source_duration']) for s in plan['segments']],
                         [(0,32000,'0','2'),(32000,32000,'2','6')])
        mapping[1].set('interp','smooth2')
        skipped=self.inspect(root)
        self.assertEqual(skipped['segments'],[])
        self.assertEqual(skipped['skippedAudio'][0]['reason'],'平滑变速')
        mapping[1].set('interp','linear');mapping[1].set('inTime','1/2s')
        self.assertEqual(self.inspect(root)['skippedAudio'][0]['reason'],'平滑变速')
        mapping[1].attrib.pop('inTime')
        mapping[1].set('interp','linear');mapping[-1].set('value','1s')
        self.assertEqual(self.inspect(root)['skippedAudio'][0]['reason'],'倒放')
        mapping[-1].set('value','8s');mapping[-1].set('time','3s')
        with self.assertRaisesRegex(ValueError,'范围不完整'):self.inspect(root)
        mapping[-1].set('time','4s')
        mapping[0].set('value','0s');mapping[1].set('value','0s');mapping[-1].set('value','0s')
        self.assertEqual(self.inspect(root)['skippedAudio'][0]['reason'],'停帧')
        mapping[1].set('value','2s');mapping[-1].set('value','8s')
        media,ref=compound(root,seq,clip)
        outer_map=ET.SubElement(ref,'timeMap')
        ET.SubElement(outer_map,'timept',time='0s',value='0s',interp='linear')
        ET.SubElement(outer_map,'timept',time='4s',value='4s',interp='linear')
        self.assertEqual([(s['startSample'],s['source_start']) for s in self.inspect(root)['segments']],
                         [(0,'0'),(32000,'2')])

    def test_fcp_speed_ramp_trims_time_map_tail_and_tiny_stationary_lead(self):
        # These points came from FCP 12.3's own "从 0%" speed-ramp XML export.
        root,p,seq,clip=basic()
        duration=Fraction(510720,48000)
        seq.set('duration',f'{duration}s');clip.set('duration',f'{duration}s')
        root.find('resources/asset').set('duration','8s')
        mapping=ET.SubElement(clip,'timeMap',preservesPitch='0')
        for output,source in (
            ('0s','0s'),('2/48000s','0s'),('128002/48000s','5/10s'),
            ('256000/48000s','2s'),('8s','45/10s'),('7680030/720000s','8s')):
            ET.SubElement(mapping,'timept',time=output,value=source,interp='linear')
        plan=self.inspect(root)
        self.assertEqual(len(plan['segments']),4)
        self.assertEqual(plan['segments'][0]['startSample'],1)
        self.assertEqual(sum(s['sampleCount'] for s in plan['segments']),plan['sampleCount']-1)
        self.assertLess(Fraction(plan['segments'][-1]['source_start'])+Fraction(plan['segments'][-1]['source_duration']),8)
        # A material freeze skips this clip and reports the missing interval.
        mapping[1].set('time','1/10s')
        self.assertEqual(self.inspect(root)['skippedAudio'][0]['reason'],'停帧')
        mapping[1].set('time','2/48000s')
        clip.remove(mapping);clip.set('duration','8s')
        media,ref=compound(root,seq,clip)
        ref.set('duration',f'{duration}s');ref.append(mapping)
        compound_plan=self.inspect(root)
        self.assertEqual([(s['offset'],s['duration'],s['source_start'],s['source_duration'])
                          for s in compound_plan['segments']],
                         [(s['offset'],s['duration'],s['source_start'],s['source_duration'])
                          for s in plan['segments']])
        for extra in ('duplicate','child','timeMap'):
            root,p,seq,clip=basic();c=ET.SubElement(clip,'conform-rate',scaleEnabled='0')
            if extra=='duplicate':ET.SubElement(clip,'conform-rate',scaleEnabled='0')
            elif extra=='child':ET.SubElement(c,'timept')
            else:ET.SubElement(clip,'timeMap')
            with self.assertRaises(ValueError):self.inspect(root)

    def test_unsupported_retime_skips_only_affected_audio(self):
        for mode in ('smooth2','reverse'):
            with self.subTest(mode=mode):
                root,p,seq,clip=basic();asset=root.find('resources/asset')
                asset.set('duration','8s');seq.set('duration','8s');clip.set('duration','4s')
                mapping=ET.SubElement(clip,'timeMap')
                ET.SubElement(mapping,'timept',time='0s',value='4s' if mode=='reverse' else '0s',interp='linear')
                ET.SubElement(mapping,'timept',time='4s',value='0s' if mode=='reverse' else '4s',interp='linear' if mode=='reverse' else 'smooth2')
                ET.SubElement(seq.find('spine'),'asset-clip',ref=asset.get('id'),offset='3604s',start='4s',duration='4s',audioRole='dialogue')
                plan=self.inspect(root)
                self.assertEqual([(s['startSample'],s['sampleCount']) for s in plan['segments']],[(64000,64000)])
                self.assertEqual([(s['startSample'],s['endSample']) for s in plan['skippedAudio']],[(0,64000)])
                ET.SubElement(clip,'asset-clip',ref=asset.get('id'),lane='1',offset='0s',start='0s',duration='1s')
                with self.assertRaisesRegex(ValueError,'连接素材'):self.inspect(root)

    def test_skip_inside_linear_compound_maps_to_project_clock(self):
        root,p,seq,clip=basic();asset=root.find('resources/asset')
        asset.set('duration','4s');seq.set('duration','4s');clip.set('duration','2s')
        media,ref=compound(root,seq,clip)
        inner=media.find('sequence');inner.set('duration','4s');ref.set('duration','4s')
        mapping=ET.SubElement(clip,'timeMap')
        ET.SubElement(mapping,'timept',time='0s',value='0s',interp='linear')
        ET.SubElement(mapping,'timept',time='2s',value='2s',interp='smooth2')
        ET.SubElement(inner.find('spine'),'asset-clip',ref=asset.get('id'),offset='2s',start='2s',duration='2s',audioRole='dialogue')
        outer=ET.SubElement(ref,'timeMap')
        ET.SubElement(outer,'timept',time='0s',value='0s',interp='linear')
        ET.SubElement(outer,'timept',time='4s',value='4s',interp='linear')
        plan=self.inspect(root)
        self.assertEqual([(s['startSample'],s['sampleCount']) for s in plan['segments']],[(32000,32000)])
        self.assertEqual([(s['startSample'],s['endSample']) for s in plan['skippedAudio']],[(0,32000)])

    def test_whole_compound_retime_maps_audio_and_source_trim(self):
        root,p,seq,clip=basic();asset=root.find('resources/asset')
        asset.set('duration','8s');seq.set('duration','4s');clip.set('duration','4s')
        media,ref=compound(root,seq,clip)
        media.find('sequence').set('duration','8s');clip.set('duration','8s')
        mapping=ET.SubElement(ref,'timeMap',preservesPitch='1')
        for output,source in ((0,0),(2,2),(4,8)):
            ET.SubElement(mapping,'timept',time=f'{output}s',value=f'{source}s',interp='linear')
        plan=self.inspect(root)
        self.assertEqual([(s['startSample'],s['sampleCount'],s['source_start'],s['source_duration']) for s in plan['segments']],
                         [(0,32000,'0','2'),(32000,32000,'2','6')])
        mapping.remove(mapping[1])
        mapping[0].set('value','1s');mapping[-1].set('value','5s')
        plan=self.inspect(root)
        self.assertEqual([(s['source_start'],s['source_duration']) for s in plan['segments']],[('1','4')])
        mapping[0].set('value','0s');mapping[-1].set('value','8s')
        # The same source compound used again must not inherit a prior warp.
        seq.set('duration','8s');ref.set('duration','4s')
        second_offset=Fraction(seq.get('tcStart','0s').removesuffix('s'))+4
        ET.SubElement(seq.find('spine'),'ref-clip',ref=media.get('id'),offset=f'{second_offset}s',start='0s',duration='4s')
        plan=self.inspect(root)
        self.assertEqual([(s['startSample'],s['source_start']) for s in plan['segments']],
                         [(0,'0'),(64000,'0')])

    def test_nested_compound_and_inner_linear_retime_compose(self):
        root,p,seq,clip=basic();asset=root.find('resources/asset')
        asset.set('duration','8s');seq.set('duration','2s');clip.set('duration','4s')
        media,ref=compound(root,seq,clip)
        media.find('sequence').set('duration','4s');ref.set('duration','2s')
        inner_map=ET.SubElement(clip,'timeMap',preservesPitch='1')
        ET.SubElement(inner_map,'timept',time='0s',value='0s',interp='linear')
        ET.SubElement(inner_map,'timept',time='4s',value='8s',interp='linear')
        outer_map=ET.SubElement(ref,'timeMap',preservesPitch='1')
        ET.SubElement(outer_map,'timept',time='0s',value='0s',interp='linear')
        ET.SubElement(outer_map,'timept',time='2s',value='4s',interp='linear')
        plan=self.inspect(root)
        self.assertEqual([(s['source_start'],s['source_duration'],s['sampleCount']) for s in plan['segments']],
                         [('0','8',32000)])
        outer_map.set('preservesPitch','0')
        with self.assertRaisesRegex(ValueError,'不同的保留音调'):self.inspect(root)

    def test_retimed_compound_with_nonzero_media_timecode(self):
        root,p,seq,clip=basic();asset=root.find('resources/asset')
        asset.set('duration','4s');seq.set('duration','2s');clip.set('duration','4s')
        media,ref=compound(root,seq,clip)
        media_seq=media.find('sequence');media_seq.set('duration','4s');media_seq.set('tcStart','10s')
        clip.set('offset','10s');ref.set('start','10s');ref.set('duration','2s')
        mapping=ET.SubElement(ref,'timeMap',preservesPitch='1')
        ET.SubElement(mapping,'timept',time='0s',value='10s',interp='linear')
        ET.SubElement(mapping,'timept',time='2s',value='14s',interp='linear')
        segments=self.inspect(root)['segments']
        self.assertEqual([(s['source_start'],s['source_duration'],s['startSample'],s['sampleCount']) for s in segments],
                         [('0','4',0,32000)])

    def test_title_inside_retimed_compound_uses_output_clock(self):
        root,p,seq,clip=basic();asset=root.find('resources/asset')
        asset.set('duration','4s');seq.set('duration','2s');clip.set('duration','4s')
        media,ref=compound(root,seq,clip)
        media.find('sequence').set('duration','4s');ref.set('duration','2s')
        effect=ET.SubElement(root.find('resources'),'effect',id='silentTitle',uid='third-party-visual-title')
        title=ET.SubElement(clip,'title',ref=effect.get('id'),lane='1',offset='2s',duration='1s')
        ET.SubElement(title,'text').text='已有标题'
        mapping=ET.SubElement(ref,'timeMap',preservesPitch='1')
        ET.SubElement(mapping,'timept',time='0s',value='0s',interp='linear')
        ET.SubElement(mapping,'timept',time='2s',value='4s',interp='linear')
        normalized,existing=prepare(ET.tostring(root),generic=True)
        self.assertEqual([(e['start_frame'],e['end_frame']) for e in existing],[(25,38)])
        self.assertEqual(len(self.inspect(ET.fromstring(normalized))['segments']),1)

    def test_title_inside_skipped_smooth_compound_is_stripped(self):
        root,p,seq,clip=basic();asset=root.find('resources/asset')
        asset.set('duration','4s');seq.set('duration','2s');clip.set('duration','4s')
        media,ref=compound(root,seq,clip)
        media.find('sequence').set('duration','4s');ref.set('duration','2s')
        effect=ET.SubElement(root.find('resources'),'effect',id='silentTitle',uid='third-party-visual-title')
        title=ET.SubElement(clip,'title',ref=effect.get('id'),lane='1',offset='2s',duration='1s')
        ET.SubElement(title,'text').text='已有标题'
        mapping=ET.SubElement(ref,'timeMap')
        ET.SubElement(mapping,'timept',time='0s',value='0s',interp='linear')
        ET.SubElement(mapping,'timept',time='2s',value='4s',interp='smooth2')
        normalized,existing=prepare(ET.tostring(root),generic=True)
        self.assertEqual(existing,[])
        self.assertEqual(ET.fromstring(normalized).findall('.//title'),[])
        self.assertEqual(self.inspect(ET.fromstring(normalized))['skippedAudio'][0]['reason'],'平滑变速')

    def test_reverse_video_only_does_not_block_separate_dialogue(self):
        root,p,seq,clip=basic();asset=root.find('resources/asset')
        clip.set('srcEnable','video')
        mapping=ET.SubElement(clip,'timeMap')
        ET.SubElement(mapping,'timept',time='0s',value='4s',interp='linear')
        ET.SubElement(mapping,'timept',time='4s',value='0s',interp='linear')
        audio=ET.SubElement(clip,'asset-clip',ref=asset.get('id'),lane='-1',offset='0s',start='0s',duration='4s',audioRole='dialogue')
        # Anchored audio on a retimed clip needs its own anchor mapping.
        with self.assertRaisesRegex(ValueError,'连接素材'):self.inspect(root)
        clip.remove(audio)
        seq.find('spine').remove(clip)
        gap=ET.SubElement(seq.find('spine'),'gap',offset=seq.get('tcStart','0s'),duration=clip.get('duration'),start='0s')
        gap.append(clip)
        # Independent connected audio under an unretimed parent is unaffected.
        ET.SubElement(gap,'asset-clip',ref=asset.get('id'),lane='-1',offset='0s',start='0s',duration='4s',audioRole='dialogue')
        plan=self.inspect(root)
        self.assertEqual(len(plan['segments']),1)
        self.assertEqual(plan['segments'][0]['source_start'],'0')
        normalized,existing=prepare(ET.tostring(root),generic=True)
        self.assertEqual(existing,[])
        self.assertEqual(len(self.inspect(ET.fromstring(normalized))['segments']),1)

    def test_reverse_visual_only_compound_does_not_block_separate_dialogue(self):
        root,p,seq,clip=basic();asset=root.find('resources/asset')
        seq.find('spine').remove(clip)
        gap=ET.SubElement(seq.find('spine'),'gap',offset=seq.get('tcStart','0s'),duration=clip.get('duration'),start='0s')
        ET.SubElement(gap,'asset-clip',ref=asset.get('id'),lane='-1',offset='0s',start='0s',duration='4s',audioRole='dialogue')
        media=ET.SubElement(root.find('resources'),'media',id='visual')
        inner=ET.SubElement(media,'sequence',format=seq.get('format'),duration='4s',tcStart='0s')
        ET.SubElement(ET.SubElement(inner,'spine'),'gap',offset='0s',duration='4s',start='0s')
        visual=ET.SubElement(gap,'ref-clip',ref='visual',lane='1',offset='0s',start='0s',duration='4s')
        mapping=ET.SubElement(visual,'timeMap')
        ET.SubElement(mapping,'timept',time='0s',value='4s',interp='linear')
        ET.SubElement(mapping,'timept',time='4s',value='0s',interp='linear')
        normalized,existing=prepare(ET.tostring(root),generic=True)
        self.assertEqual(existing,[])
        self.assertEqual(len(self.inspect(ET.fromstring(normalized))['segments']),1)

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

    def test_dialogue_filters_and_builtin_enhancements_use_source_audio(self):
        root,p,seq,clip=basic();asset=root.find('resources/asset')
        original=self.inspect(root)['segments']
        effect=ET.SubElement(root.find('resources'),'effect',id='compressor',name='Compressor',uid='example.compressor')
        component=ET.SubElement(clip,'audio-channel-source',srcCh='1',role='dialogue')
        ET.SubElement(component,'adjust-noiseReduction',amount='0.5')
        ET.SubElement(component,'adjust-voiceIsolation',amount='0.7')
        filter_node=ET.SubElement(clip,'filter-audio',ref=effect.get('id'))
        param=ET.SubElement(filter_node,'param',name='Threshold',value='-18')
        ET.SubElement(ET.SubElement(param,'keyframeAnimation'),'keyframe',time='0s',value='-18')
        processed=self.inspect(root)
        self.assertEqual(processed['segments'],original)
        self.assertEqual(processed['bypassedAudioEffects'],3)
        dtd=Path(__file__).resolve().parents[1]/'.subloom/verification/FCPXMLv1_14.dtd'
        with tempfile.TemporaryDirectory() as temp:
            xml=Path(temp)/'effects.fcpxml';xml.write_bytes(ET.tostring(root))
            subprocess.run(['xmllint','--noout','--dtdvalid',str(dtd),str(xml)],capture_output=True,check=True)
        filter_node.set('enabled','0')
        self.assertEqual(self.inspect(root)['bypassedAudioEffects'],2)
        filter_node.set('enabled','1');filter_node.set('ref','missing')
        with self.assertRaisesRegex(ValueError,'音频效果引用'):self.inspect(root)
        filter_node.set('ref',effect.get('id'))
        ET.SubElement(component,'adjust-volume',amount='-6dB')
        self.assertAlmostEqual(self.inspect(root)['segments'][0]['gain'],10**(-6/20))
        ET.SubElement(component,'mute',start='0s',duration='1s')
        with self.assertRaisesRegex(ValueError,'静音'):self.inspect(root)

    def test_compound_role_filter_and_excluded_music_effect(self):
        root,p,seq,clip=basic();media,ref=compound(root,seq,clip)
        effect=ET.SubElement(root.find('resources'),'effect',id='compressor',uid='example.compressor')
        role=ET.SubElement(ref,'audio-role-source',role='dialogue')
        ET.SubElement(role,'adjust-volume',amount='-6dB')
        ET.SubElement(role,'filter-audio',ref=effect.get('id'))
        self.assertEqual(self.inspect(root)['bypassedAudioEffects'],1)
        self.assertAlmostEqual(self.inspect(root)['segments'][0]['gain'],10**(-6/20))
        dtd=Path(__file__).resolve().parents[1]/'.subloom/verification/FCPXMLv1_14.dtd'
        with tempfile.TemporaryDirectory() as temp:
            xml=Path(temp)/'compound-effects.fcpxml';xml.write_bytes(ET.tostring(root))
            subprocess.run(['xmllint','--noout','--dtdvalid',str(dtd),str(xml)],capture_output=True,check=True)
        clip.set('audioRole','music')
        ET.SubElement(clip,'filter-audio',ref=effect.get('id'))
        self.assertEqual(self.inspect(root)['bypassedAudioEffects'],1)
        self.assertEqual(self.inspect(root,'all')['bypassedAudioEffects'],2)

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

    def components(self):
        data=(FIXTURE.parent/'component-clips.fcpxml').read_bytes()
        normalized,existing=prepare(data,generic=True)
        self.assertEqual(existing,[])
        return ET.fromstring(normalized)

    def test_component_clips_keep_vo_cuts_and_sample_accurate_tail(self):
        root=self.components();plan=self.inspect(root)
        self.assertEqual(plan['duration'],'1203/200')
        self.assertEqual(plan['sampleCount'],96240)
        self.assertEqual(plan['totalFrames'],151)
        self.assertEqual([(s['assetRef'],s['startSample'],s['sampleCount'],s['source_start'],s['role']) for s in plan['segments']],
                         [('voice',0,32000,'10','VO'),('voice',32000,32000,'18','VO'),('voice',64000,32240,'30','VO')])
        self.assertEqual(self.inspect(root,'all')['segments'],plan['segments'])
        # Enabling the detached camera audio includes only its visible 0..2s,
        # not its 60-second source or its -1s lead before the sequence.
        root.find('.//clip/clip').set('enabled','1')
        camera=self.inspect(root)['segments'][0]
        self.assertEqual((camera['assetRef'],camera['source_start'],camera['startSample'],camera['sampleCount']),('camera','2',0,32000))

    def test_contained_gain_and_mute_do_not_change_independent_connections(self):
        root=self.components();clip=root.find('.//spine/clip');clip.find('clip').set('enabled','1')
        ET.SubElement(clip.find('clip'),'adjust-volume',amount='-6dB')
        plan=self.inspect(root)
        self.assertAlmostEqual(plan['segments'][0]['gain'],10**(-6/20))
        self.assertEqual(plan['segments'][1]['gain'],1)
        clip.find('clip').set('enabled','0')
        self.assertTrue(all(s['assetRef']=='voice' for s in self.inspect(root)['segments']))

    def test_dual_mono_roles_mutes_and_incomplete_channel_selection(self):
        for role in ('dialogue.voice','VO.voice','旁白.旁白-1'):
            root=self.components()
            for c in root.findall('.//audio-channel-source'):c.set('role',role)
            self.assertEqual(len(self.inspect(root)['segments']),3)
        root=self.components()
        for c in root.findall('.//audio-channel-source'):c.set('role','music.music-1')
        self.assertEqual(self.inspect(root)['segments'],[])
        self.assertEqual(len(self.inspect(root,'all')['segments']),3)
        for key,value in (('enabled','0'),('active','0'),('role','music.music-1'),('srcCh','2'),('outCh','R')):
            root=self.components();root.find('.//audio-channel-source').set(key,value)
            with self.subTest(key=key):
                with self.assertRaises(ValueError):self.inspect(root)
        root=self.components()
        for c in root.findall('.//audio-channel-source'):c.set('enabled','0')
        self.assertEqual(self.inspect(root)['segments'],[])

    def test_contained_source_trim_and_unsupported_audio_not_silently_ignored(self):
        root=self.components();clip=root.find('.//spine/clip')
        audio=ET.SubElement(clip,'audio',ref='camera',offset='100s',start='100s',duration='60s',srcCh='1, 2')
        segment=self.inspect(root)['segments'][1]
        self.assertEqual((segment['source_start'],segment['startSample'],segment['sampleCount']),('2',0,32000))
        for tag in ('filter-audio','timeMap'):
            child=ET.SubElement(audio,tag)
            with self.assertRaises(ValueError):self.inspect(root)
            audio.remove(child)
        root.find('.//sequence').set('duration','7s')
        with self.assertRaisesRegex(ValueError,'范围不完整'):self.inspect(root)

    def test_subframe_project_endpoint_keeps_last_caption_and_frame_payload(self):
        plan=self.inspect(self.components());duration=Fraction(plan['duration'])
        rows=quantize([{'text':'最后一个字','start':Fraction(6),'end':duration}],duration,25)
        self.assertEqual(rows,[{'text':'最后一个字','start_frame':150,'end_frame':151}])
        for version in ('1.12','1.13','1.14'):
            xml=ET.fromstring(payload({**plan,'captions':rows},version))
            self.assertEqual(xml.find('clip').get('duration'),'151/25s')
        with self.assertRaises(ValueError):quantize([{'text':'越界','start':Fraction(6),'end':duration+1}],duration,25)

    def test_native_render_component_cuts_equal_explicit_source_slices(self):
        import wave
        from array import array
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);media=directory/'voice.wav'
            # A different constant per source second exposes wrong source
            # offsets; the two source channels differ to exercise the downmix.
            with wave.open(str(media),'wb') as out:
                out.setparams((2,2,16000,0,'NONE','not compressed'))
                for second in range(60):out.writeframes(array('h',[100+second*90,200+second*70]).tobytes()*16000)
            root=self.components();root.find("resources/asset[@id='voice']/media-rep").set('src',media.as_uri())
            xml=directory/'input.fcpxml';xml.write_bytes(ET.tostring(root))
            binary=FIXTURE.parents[2]/'.subloom/build/SubPopAudioProbeCLI'
            mixed=project.render(xml,directory,binary,'COMPONENT-PROJECT')
            actual=(directory/mixed['pcmFile']).read_bytes()
            seq=root.find('.//sequence');seq.set('duration','60s');spine=seq.find('spine');spine.clear()
            ET.SubElement(spine,'asset-clip',ref='voice',offset='0s',start='0s',duration='60s',audioRole='dialogue')
            xml.write_bytes(ET.tostring(root));whole=project.render(xml,directory,binary,'COMPONENT-PROJECT')
            source=(directory/whole['pcmFile']).read_bytes();unit=16000*4
            self.assertEqual(actual,source[10*unit:12*unit]+source[18*unit:20*unit]+source[30*unit:30*unit+32240*4])
            self.assertEqual(len(actual),96240*4)
            self.assertFalse(mixed['silent'])

    def test_native_render_with_audio_effect_uses_unprocessed_source_pcm(self):
        import wave
        from array import array
        root,p,seq,clip=basic()
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);media=directory/'voice.wav'
            with wave.open(str(media),'wb') as out:
                out.setparams((1,2,16000,0,'NONE','not compressed'))
                out.writeframes(array('h',[12000]).tobytes()*9*16000)
            root.find('resources/asset/media-rep').set('src',media.as_uri())
            xml=directory/'input.fcpxml';xml.write_bytes(ET.tostring(root))
            binary=FIXTURE.parents[2]/'.subloom/build/SubPopAudioProbeCLI'
            original=project.render(xml,directory,binary,'DAILY-PROJECT')
            original_pcm=(directory/original['pcmFile']).read_bytes()
            effect=ET.SubElement(root.find('resources'),'effect',id='compressor',uid='example.compressor')
            component=ET.SubElement(clip,'audio-channel-source',srcCh='1',role='dialogue')
            ET.SubElement(component,'adjust-noiseReduction',amount='0.5')
            ET.SubElement(clip,'filter-audio',ref=effect.get('id'))
            xml.write_bytes(ET.tostring(root))
            processed=project.render(xml,directory,binary,'DAILY-PROJECT')
            self.assertEqual((directory/processed['pcmFile']).read_bytes(),original_pcm)
            self.assertEqual(processed['plan']['bypassedAudioEffects'],2)

    def test_native_render_skips_smooth_audio_but_keeps_later_dialogue(self):
        import wave
        from array import array
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);media=directory/'voice.wav'
            with wave.open(str(media),'wb') as out:
                out.setparams((1,2,16000,0,'NONE','not compressed'))
                out.writeframes(array('h',[12000]).tobytes()*4*16000)
            root,p,seq,clip=basic();asset=root.find('resources/asset')
            asset.set('duration','4s');asset.find('media-rep').set('src',media.as_uri())
            seq.set('duration','4s');clip.set('duration','2s')
            mapping=ET.SubElement(clip,'timeMap')
            ET.SubElement(mapping,'timept',time='0s',value='0s',interp='linear')
            ET.SubElement(mapping,'timept',time='2s',value='2s',interp='smooth2')
            ET.SubElement(seq.find('spine'),'asset-clip',ref=asset.get('id'),offset='3602s',start='2s',duration='2s',audioRole='dialogue')
            xml=directory/'input.fcpxml';xml.write_bytes(ET.tostring(root))
            binary=FIXTURE.parents[2]/'.subloom/build/SubPopAudioProbeCLI'
            result=project.render(xml,directory,binary,'DAILY-PROJECT')
            pcm=array('f');pcm.frombytes((directory/result['pcmFile']).read_bytes())
            self.assertEqual(len(pcm),4*16000)
            self.assertEqual(max(abs(value) for value in pcm[:32000]),0)
            self.assertGreater(max(abs(value) for value in pcm[32000:]),0.1)
            self.assertEqual(result['plan']['skippedAudio'][0]['endSample'],32000)

    def test_native_render_linear_retime_keeps_pitch_and_project_duration(self):
        import math
        import wave
        from array import array
        import numpy as np
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);media=directory/'two-tones.wav'
            with wave.open(str(media),'wb') as out:
                out.setparams((1,2,16000,0,'NONE','not compressed'))
                for frequency in (440,880):
                    out.writeframes(array('h',(int(12000*math.sin(2*math.pi*frequency*i/16000)) for i in range(32000))).tobytes())
            root,p,seq,clip=basic();asset=root.find('resources/asset')
            asset.set('duration','4s');asset.find('media-rep').set('src',media.as_uri())
            seq.set('duration','2s');clip.set('duration','2s')
            mapping=ET.SubElement(clip,'timeMap',preservesPitch='1')
            ET.SubElement(mapping,'timept',time='0s',value='0s',interp='linear')
            ET.SubElement(mapping,'timept',time='2s',value='4s',interp='linear')
            xml=directory/'retimed.fcpxml';xml.write_bytes(ET.tostring(root))
            binary=FIXTURE.parents[2]/'.subloom/build/SubPopAudioProbeCLI'
            result=project.render(xml,directory,binary,'DAILY-PROJECT')
            samples=np.fromfile(directory/result['pcmFile'],dtype='<f4')
            self.assertEqual(len(samples),32000)
            self.assertFalse(result['silent'])
            for output_second,frequency in ((0,440),(1,880)):
                middle=samples[output_second*16000+4000:output_second*16000+12000]
                peak=np.fft.rfftfreq(len(middle),1/16000)[np.abs(np.fft.rfft(middle)).argmax()]
                self.assertLess(abs(peak-frequency),8)

    def test_native_render_trimmed_compound_matches_source_slice(self):
        import wave
        from array import array
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);media=directory/'source.wav'
            with wave.open(str(media),'wb') as out:
                out.setparams((1,2,16000,0,'NONE','not compressed'))
                for second in range(4):out.writeframes(array('h',[1000+second*2000]).tobytes()*16000)
            root,p,seq,clip=basic();asset=root.find('resources/asset')
            asset.set('duration','4s');asset.find('media-rep').set('src',media.as_uri())
            seq.set('duration','4s');clip.set('duration','4s')
            xml=directory/'source.fcpxml';xml.write_bytes(ET.tostring(root))
            binary=FIXTURE.parents[2]/'.subloom/build/SubPopAudioProbeCLI'
            whole=project.render(xml,directory,binary,'DAILY-PROJECT')
            source=(directory/whole['pcmFile']).read_bytes()
            media_resource,ref=compound(root,seq,clip)
            seq.set('duration','2s');ref.set('start','1s');ref.set('duration','2s')
            xml.write_bytes(ET.tostring(root))
            trimmed=project.render(xml,directory,binary,'DAILY-PROJECT')
            self.assertEqual((directory/trimmed['pcmFile']).read_bytes(),source[16000*4:48000*4])

    def test_native_render_whole_compound_retime_matches_leaf_retime(self):
        import wave
        from array import array
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);media_file=directory/'source.wav'
            with wave.open(str(media_file),'wb') as out:
                out.setparams((1,2,16000,0,'NONE','not compressed'))
                for second in range(4):out.writeframes(array('h',[1000+second*2000]).tobytes()*16000)
            root,p,seq,clip=basic();asset=root.find('resources/asset')
            asset.set('duration','4s');asset.find('media-rep').set('src',media_file.as_uri())
            seq.set('duration','2s');clip.set('duration','2s')
            mapping=ET.SubElement(clip,'timeMap',preservesPitch='1')
            ET.SubElement(mapping,'timept',time='0s',value='0s',interp='linear')
            ET.SubElement(mapping,'timept',time='2s',value='4s',interp='linear')
            xml=directory/'input.fcpxml';xml.write_bytes(ET.tostring(root))
            binary=FIXTURE.parents[2]/'.subloom/build/SubPopAudioProbeCLI'
            leaf=project.render(xml,directory,binary,'DAILY-PROJECT')
            leaf_pcm=(directory/leaf['pcmFile']).read_bytes()
            clip.remove(mapping);clip.set('duration','4s')
            media,ref=compound(root,seq,clip);media.find('sequence').set('duration','4s')
            ref.set('duration','2s');ref.append(mapping)
            xml.write_bytes(ET.tostring(root))
            dtd=Path(__file__).resolve().parents[1]/'.subloom/verification/FCPXMLv1_14.dtd'
            subprocess.run(['xmllint','--noout','--dtdvalid',str(dtd),str(xml)],capture_output=True,check=True)
            whole=project.render(xml,directory,binary,'DAILY-PROJECT')
            self.assertEqual((directory/whole['pcmFile']).read_bytes(),leaf_pcm)
