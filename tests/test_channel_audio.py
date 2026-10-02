"""Channel audibility planning and real PCM regressions using synthetic media."""
from array import array
import math
from pathlib import Path
import tempfile
import unittest
import wave
import xml.etree.ElementTree as ET
from probes import project
from probes.snapshot import prepare
from tests.test_project import basic


class ChannelAudioTests(unittest.TestCase):
    def inspect(self,root,mode='dialogue'):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'input.fcpxml';path.write_bytes(ET.tostring(root))
            return project.inspect(path,mode)

    def multichannel(self,channels=4,sources=1):
        root,_,seq,clip=basic();asset=root.find('resources/asset')
        asset.set('audioChannels',str(channels));asset.set('audioSources',str(sources))
        return root,seq,clip,asset

    def component(self,clip,channels,role='dialogue',**attrs):
        return ET.SubElement(clip,'audio-channel-source',srcCh=channels,role=role,**attrs)

    def test_multichannel_default_and_selected_components_keep_static_gains(self):
        root,_,clip,_=self.multichannel()
        default=self.inspect(root)['segments'][0]['channelMix']
        self.assertEqual(default,{'components':None,'sourceID':None,'expectedChannels':4,'expectedSources':1})
        first=self.component(clip,'1');ET.SubElement(first,'adjust-volume',amount='-6dB')
        self.component(clip,'2','music');self.component(clip,'3',enabled='0');self.component(clip,'4',active='0')
        selected=self.inspect(root)['segments'][0]
        self.assertEqual(selected['gain'],1)
        self.assertEqual(selected['channelMix']['components'][0]['channels'],[1])
        self.assertAlmostEqual(selected['channelMix']['components'][0]['gain'],10**(-6/20))
        self.assertEqual(len(self.inspect(root,'all')['segments'][0]['channelMix']['components']),2)

    def test_stereo_partial_selection_and_independent_volume_are_explicit(self):
        root,_,clip,_=self.multichannel(2)
        first=self.component(clip,'1');ET.SubElement(first,'adjust-volume',amount='-6dB')
        self.component(clip,'2')
        selected=self.inspect(root)['segments'][0]['channelMix']['components']
        self.assertEqual([component['channels'] for component in selected],[[1],[2]])
        self.assertAlmostEqual(selected[0]['gain'],10**(-6/20));self.assertEqual(selected[1]['gain'],1)
        clip[1].set('enabled','0')
        self.assertEqual(len(self.inspect(root)['segments'][0]['channelMix']['components']),1)

    def test_complete_explicit_stereo_layout_keeps_group_definition_at_top_level(self):
        root,_,clip,_=self.multichannel(2)
        self.assertNotIn('channelMix',self.inspect(root)['segments'][0])
        self.component(clip,'1,2')
        self.assertEqual(self.inspect(root)['segments'][0]['channelMix']['components'],[{'channels':[1,2],'gain':1.0}])
        clip.remove(clip[0]);self.component(clip,'1');self.component(clip,'2')
        self.assertEqual(self.inspect(root)['segments'][0]['channelMix']['components'],[{'channels':[1],'gain':1.0},{'channels':[2],'gain':1.0}])

    def test_missing_optional_metadata_is_deferred_to_real_media(self):
        root,_,clip,asset=self.multichannel()
        for key in ('audioChannels','audioSources'):asset.attrib.pop(key)
        selected=self.inspect(root)['segments'][0]['channelMix']
        self.assertIsNone(selected['components']);self.assertIsNone(selected['expectedChannels']);self.assertIsNone(selected['expectedSources'])
        self.component(clip,'3')
        self.assertEqual(self.inspect(root)['segments'][0]['channelMix']['components'],[{'channels':[3],'gain':1.0}])

    def test_muted_and_excluded_components_do_not_require_metadata_or_channels(self):
        for mode in ('muted','role'):
            root,_,clip,asset=self.multichannel()
            asset.set('audioChannels','invalid');asset.set('audioSources','invalid')
            if mode=='muted':self.component(clip,'bad',enabled='0')
            else:self.component(clip,'bad','music')
            self.assertEqual(self.inspect(root)['segments'],[])
        root,_,clip,asset=self.multichannel();asset.attrib.pop('audioChannels');clip.set('audioRole','music')
        self.assertEqual(self.inspect(root)['segments'],[])

    def test_disabled_component_does_not_contaminate_channel_range_or_effects(self):
        root,_,clip,_=self.multichannel(2)
        off=self.component(clip,'999',enabled='0');ET.SubElement(off,'filter-audio',ref='missing')
        self.component(clip,'1')
        selected=self.inspect(root)['segments'][0]
        self.assertEqual(selected['channelMix']['components'],[{'channels':[1],'gain':1.0}])
        self.assertEqual(self.inspect(root)['bypassedAudioEffects'],0)

    def test_actual_channel_metadata_is_required_only_for_audible_sources(self):
        for key,value in (('audioChannels','0'),('audioChannels','65'),('audioSources','33'),('audioSources','1.0')):
            root,_,clip,asset=self.multichannel();asset.set(key,value)
            with self.subTest(key=key,value=value):
                with self.assertRaisesRegex(ValueError,'通道信息无效'):self.inspect(root)
                clip.set('enabled','0');self.assertEqual(self.inspect(root)['segments'],[])

    def test_duplicate_and_out_of_range_active_channel_selection_is_rejected(self):
        for channels in ('1,1','0','5','1,','65'):
            root,_,clip,_=self.multichannel();self.component(clip,channels)
            with self.subTest(channels=channels):
                with self.assertRaisesRegex(ValueError,'通道'):self.inspect(root)
        root,_,clip,_=self.multichannel();self.component(clip,'1,2');self.component(clip,'2,3')
        with self.assertRaisesRegex(ValueError,'重复'):self.inspect(root)

    def test_multiple_sources_use_global_component_numbers_and_local_audio_numbers(self):
        root,_,clip,_=self.multichannel(2,2)
        self.assertEqual(self.inspect(root)['segments'][0]['channelMix']['expectedSources'],2)
        self.component(clip,'3')
        self.assertEqual(self.inspect(root)['segments'][0]['channelMix']['components'],[{'channels':[3],'gain':1.0}])
        clip[0].set('enabled','0');self.assertEqual(self.inspect(root)['segments'],[])
        clip.remove(clip[0]);clip.tag='audio';clip.set('srcCh','2');clip.set('srcID','2')
        selection=self.inspect(root)['segments'][0]['channelMix']
        self.assertEqual(selection['sourceID'],'2');self.assertEqual(selection['components'],[{'channels':[2],'gain':1.0}])
        clip.set('srcCh','3')
        with self.assertRaisesRegex(ValueError,'超出媒体范围'):self.inspect(root)

    def test_audio_default_source_is_first_source_instead_of_all_tracks(self):
        root,_,clip,_=self.multichannel(2,2);clip.tag='audio'
        selection=self.inspect(root)['segments'][0]['channelMix']
        self.assertEqual(selection['sourceID'],'1');self.assertIsNone(selection['components'])

    def test_role_source_mute_is_applied_before_channel_metadata(self):
        root,_,clip,asset=self.multichannel();asset.set('audioChannels','invalid')
        self.component(clip,'1','dialogue.voice')
        role=ET.Element('audio-role-source',role='dialogue',active='0')
        audible,_,_,selection=project.audio_selection(clip,asset,'dialogue',{},((role,),))
        self.assertFalse(audible);self.assertEqual(selection['components'],[])

    def wrapper(self,root,seq,clip,asset,channels='1'):
        spine=seq.find('spine');spine.remove(clip)
        wrapper=ET.SubElement(spine,'clip',offset=clip.get('offset'),start='0s',duration=clip.get('duration'))
        self.component(wrapper,channels)
        gap=ET.SubElement(wrapper,'gap',offset='0s',start='0s',duration=clip.get('duration'))
        audio=ET.SubElement(gap,'audio',ref=asset.get('id'),lane='-1',offset='0s',start='0s',duration=clip.get('duration'))
        return wrapper,gap,audio

    def test_container_selection_reaches_source_and_leaves_same_asset_connection_independent(self):
        root,seq,clip,asset=self.multichannel(2)
        wrapper,_,audio=self.wrapper(root,seq,clip,asset)
        audio.set('srcCh','1,2')
        connection=ET.SubElement(wrapper,'asset-clip',ref=asset.get('id'),lane='-2',offset='0s',start='0s',duration=clip.get('duration'),audioRole='dialogue')
        segments=self.inspect(root)['segments']
        self.assertEqual(segments[0]['channelMix']['components'],[{'channels':[1],'gain':1.0}])
        self.assertNotIn('channelMix',segments[1]);self.assertEqual(segments[1]['gain'],1)
        wrapper.find('audio-channel-source').set('enabled','0')
        segments=self.inspect(root)['segments']
        self.assertEqual(len(segments),1);self.assertNotIn('channelMix',segments[0])
        self.assertEqual(connection.get('enabled'),None)

    def test_direct_audio_connection_is_independent_from_primary_source_channels(self):
        root,seq,clip,asset=self.multichannel(2)
        wrapper,_,audio=self.wrapper(root,seq,clip,asset)
        audio.set('srcCh','1,2')
        ET.SubElement(wrapper,'audio',ref=asset.get('id'),lane='-2',offset='0s',start='0s',duration=clip.get('duration'),srcCh='2')
        segments=self.inspect(root)['segments']
        self.assertEqual([segment['channelMix']['components'] for segment in segments],
                         [[{'channels':[1],'gain':1.0}],[{'channels':[2],'gain':1.0}]])

    def test_container_stereo_group_retains_its_divisor_for_a_partial_leaf(self):
        for count in (2,4):
            root,seq,clip,asset=self.multichannel(count)
            _,_,audio=self.wrapper(root,seq,clip,asset,'1,2');audio.set('srcCh','1')
            selection=self.inspect(root)['segments'][0]['channelMix']['components']
            self.assertEqual(selection,[{'channels':[1],'gain':0.5}])

    def test_container_full_stereo_group_keeps_explicit_mean_for_full_leaf(self):
        root,seq,clip,asset=self.multichannel(2)
        _,_,audio=self.wrapper(root,seq,clip,asset,'1,2');audio.set('srcCh','1,2')
        segment=self.inspect(root)['segments'][0]
        self.assertEqual(segment['gain'],1)
        self.assertEqual(segment['channelMix']['components'],[{'channels':[1],'gain':0.5},{'channels':[2],'gain':0.5}])

    def test_global_container_channels_are_translated_to_chosen_source_local_channels(self):
        root,seq,clip,asset=self.multichannel(2,2)
        wrapper,_,audio=self.wrapper(root,seq,clip,asset,'3');audio.set('srcID','2');audio.set('srcCh','1')
        selection=self.inspect(root)['segments'][0]['channelMix']
        self.assertEqual(selection['sourceID'],'2');self.assertEqual(selection['components'],[{'channels':[1],'gain':1.0}])
        wrapper.find('audio-channel-source').set('srcCh','1')
        self.assertEqual(self.inspect(root)['segments'],[])

    def test_container_component_volume_and_leaf_volume_are_multiplied_once(self):
        root,seq,clip,asset=self.multichannel(4)
        wrapper,_,audio=self.wrapper(root,seq,clip,asset,'1,2')
        ET.SubElement(wrapper.find('audio-channel-source'),'adjust-volume',amount='-6dB')
        leaf=self.component(audio,'1,2');ET.SubElement(leaf,'adjust-volume',amount='-6dB')
        selection=self.inspect(root)['segments'][0]['channelMix']
        self.assertEqual([component['channels'] for component in selection['components']],[[1],[2]])
        for component in selection['components']:self.assertAlmostEqual(component['gain'],10**(-12/20)/2)
        self.assertTrue(all(not key.startswith('_') for key in selection))

    def test_muted_container_does_not_resolve_or_validate_its_source_layout(self):
        root,seq,clip,asset=self.multichannel(4)
        wrapper,gap,_=self.wrapper(root,seq,clip,asset)
        wrapper.find('audio-channel-source').set('enabled','0')
        asset.set('audioChannels','invalid')
        second=ET.SubElement(root.find('resources'),'asset',id='other',hasAudio='1',audioChannels='invalid',start='0s',duration=asset.get('duration'))
        ET.SubElement(gap,'audio',ref=second.get('id'),offset='0s',start='0s',duration=clip.get('duration'))
        self.assertEqual(self.inspect(root)['segments'],[])

    def test_nested_component_intersection_normalizes_the_group_only_once(self):
        outer={'components':[{'channels':[1,2],'gain':0.5}],'sourceID':None,'expectedChannels':4,'expectedSources':1}
        inner=dict(outer,components=[{'channels':[1,2],'gain':0.5}])
        leaf=dict(outer,components=[{'channels':[1,2],'gain':1.0}])
        selection=project.intersect_channels(outer,project.intersect_channels(inner,leaf))
        gain,mix=project.segment_channels(selection)
        self.assertEqual(gain,1)
        self.assertEqual(mix['components'],[{'channels':[1],'gain':0.125},{'channels':[2],'gain':0.125}])

    def test_fcp_roundtrip_nested_channel_fragments_keep_mute_gain_and_container_window(self):
        fixture=Path(__file__).parent/'fixtures/fcp-multichannel-roundtrip.fcpxml'
        normalized,_=prepare(fixture.read_bytes(),generic=True)
        segments=self.inspect(ET.fromstring(normalized))['segments']
        self.assertEqual(len(segments),4)
        self.assertEqual([(segment['offset'],segment['duration'],segment['source_start']) for segment in segments],
                         [('0','4','2'),('0','4','2'),('4','4','2'),('8','4','2')])
        self.assertEqual(segments[0]['channelMix']['components'],[{'channels':[1],'gain':1.0}])
        self.assertEqual(segments[1]['channelMix']['components'][0]['channels'],[3])
        self.assertAlmostEqual(segments[1]['channelMix']['components'][0]['gain'],10**(-6/20))
        self.assertEqual(segments[2]['channelMix']['expectedSources'],2)
        self.assertEqual([component['channels'] for component in segments[2]['channelMix']['components']],[[1],[3]])
        self.assertEqual(segments[3]['channelMix']['components'],[{'channels':[1,2],'gain':1.0}])

    def synced_wrapper(self,root,seq,wrapper):
        spine=seq.find('spine');spine.remove(wrapper);wrapper.set('offset','0s')
        sync=ET.SubElement(spine,'sync-clip',offset=seq.get('tcStart','0s'),start='0s',duration=wrapper.get('duration'))
        sync.append(wrapper)
        source=ET.SubElement(sync,'sync-source',sourceID='storyline')
        return source

    def test_sync_role_volume_is_consumed_once_at_channel_container_boundary(self):
        root,seq,clip,asset=self.multichannel(4)
        wrapper,_,_=self.wrapper(root,seq,clip,asset)
        source=self.synced_wrapper(root,seq,wrapper)
        role=ET.SubElement(source,'audio-role-source',role='dialogue');ET.SubElement(role,'adjust-volume',amount='-6dB')
        segment=self.inspect(root)['segments'][0]
        self.assertEqual(segment['gain'],1)
        self.assertAlmostEqual(segment['channelMix']['components'][0]['gain'],10**(-6/20))

    def test_parent_output_role_overrides_underlying_audio_role(self):
        root,seq,clip,asset=self.multichannel(4)
        wrapper,_,audio=self.wrapper(root,seq,clip,asset)
        audio.set('role','music')
        segments=self.inspect(root)['segments']
        self.assertEqual(len(segments),1);self.assertEqual(segments[0]['role'],'dialogue')
        self.assertEqual(segments[0]['channelMix']['components'],[{'channels':[1],'gain':1.0}])
        wrapper.find('audio-channel-source').set('role','music')
        self.assertEqual(self.inspect(root)['segments'],[])

    def test_unconsumed_role_controls_still_apply_to_independent_connections(self):
        root,seq,clip,asset=self.multichannel(4)
        wrapper,_,audio=self.wrapper(root,seq,clip,asset);audio.set('role','VO')
        ET.SubElement(wrapper,'asset-clip',ref=asset.get('id'),lane='-2',offset='0s',start='0s',duration=wrapper.get('duration'),audioRole='VO')
        source=self.synced_wrapper(root,seq,wrapper)
        for role,db in (('dialogue',-6),('VO',-12)):
            setting=ET.SubElement(source,'audio-role-source',role=role);ET.SubElement(setting,'adjust-volume',amount=f'{db}dB')
        segments=self.inspect(root)['segments']
        self.assertEqual(segments[0]['role'],'dialogue')
        self.assertAlmostEqual(segments[0]['channelMix']['components'][0]['gain'],10**(-6/20))
        self.assertEqual(segments[1]['role'],'VO');self.assertAlmostEqual(segments[1]['gain'],10**(-12/20))

    def write_wave(self,path,channels):
        with wave.open(str(path),'wb') as out:
            out.setparams((len(channels),2,16000,0,'NONE','not compressed'))
            out.writeframes(array('h',(value for frame in zip(*channels) for value in frame)).tobytes())

    def render_wave(self,directory,source,channels,components=(),missing=False):
        root,seq,clip,asset=self.multichannel(channels)
        asset.set('duration','1s');asset.find('media-rep').set('src',source.as_uri())
        seq.set('duration','1s');clip.set('duration','1s')
        for text,role,attrs,db in components:
            component=self.component(clip,text,role,**attrs)
            if db is not None:ET.SubElement(component,'adjust-volume',amount=f'{db}dB')
        if missing:
            for key in ('audioChannels','audioSources'):asset.attrib.pop(key)
        xml=directory/'input.fcpxml';xml.write_bytes(ET.tostring(root))
        binary=Path(__file__).resolve().parents[1]/'.subloom/build/SubPopAudioProbeCLI'
        result=project.render(xml,directory,binary,'DAILY-PROJECT')
        pcm=array('f');pcm.frombytes((directory/result['pcmFile']).read_bytes())
        self.assertEqual(len(pcm),16000)
        return pcm,result

    def test_native_selected_channel_excludes_music_and_disabled_channels(self):
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);source=directory/'four.wav'
            signals=[[int(2000*math.sin(2*math.pi*frequency*i/16000)) for i in range(16000)] for frequency in (440,880,1320,1760)]
            self.write_wave(source,signals)
            components=[('1','dialogue',{},-6),('2','music',{},None),('3','dialogue',{'enabled':'0'},None),('4','dialogue',{'active':'0'},None)]
            actual,_=self.render_wave(directory,source,4,components)
            reference=directory/'one.wav';self.write_wave(reference,[signals[0]])
            expected,_=self.render_wave(directory,reference,1,[('1','dialogue',{},-6)])
            self.assertLess(max(abs(a-b) for a,b in zip(actual,expected)),1e-5)

    def test_native_independent_channel_gains_and_groups_match_explicit_reference(self):
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);source=directory/'four.wav'
            signals=[[1000]*16000,[3000]*16000,[6000]*16000,[9000]*16000]
            self.write_wave(source,signals)
            components=[('1,2','dialogue',{},None),('3','dialogue',{},-6),('4','dialogue',{'enabled':'0'},None)]
            actual,_=self.render_wave(directory,source,4,components)
            expected_value=((1000+3000)/2+6000*10**(-6/20))/32768
            self.assertLess(max(abs(value-expected_value) for value in actual),1e-5)

    def test_native_explicit_stereo_group_and_two_mono_components_have_distinct_mixes(self):
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);source=directory/'two.wav'
            self.write_wave(source,[[1000]*16000,[3000]*16000])
            paired,_=self.render_wave(directory,source,2,[('1,2','dialogue',{},None)])
            separate,_=self.render_wave(directory,source,2,[('1','dialogue',{},None),('2','dialogue',{},None)])
            self.assertLess(max(abs(value-2000/32768) for value in paired),1e-5)
            self.assertLess(max(abs(value-4000/32768) for value in separate),1e-5)
            default,result=self.render_wave(directory,source,2)
            self.assertNotIn('channelMix',result['plan']['segments'][0])
            self.assertEqual(len(default),16000);self.assertFalse(result['silent'])

    def test_native_missing_metadata_reads_actual_selected_channel(self):
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);source=directory/'four.wav'
            self.write_wave(source,[[1000]*16000,[3000]*16000,[6000]*16000,[9000]*16000])
            actual,_=self.render_wave(directory,source,4,[('3','dialogue',{},None)],missing=True)
            self.assertLess(max(abs(value-6000/32768) for value in actual),1e-5)

    def test_native_container_stereo_group_is_averaged_once(self):
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);source=directory/'two.wav'
            self.write_wave(source,[[1000]*16000,[3000]*16000])
            root,seq,clip,asset=self.multichannel(2)
            asset.set('duration','1s');asset.find('media-rep').set('src',source.as_uri())
            seq.set('duration','1s');clip.set('duration','1s')
            _,_,audio=self.wrapper(root,seq,clip,asset,'1,2');audio.set('srcCh','1,2')
            xml=directory/'input.fcpxml';xml.write_bytes(ET.tostring(root))
            binary=Path(__file__).resolve().parents[1]/'.subloom/build/SubPopAudioProbeCLI'
            result=project.render(xml,directory,binary,'DAILY-PROJECT')
            actual=array('f');actual.frombytes((directory/result['pcmFile']).read_bytes())
            self.assertEqual(len(actual),16000)
            self.assertLess(max(abs(value-2000/32768) for value in actual),1e-5)

    def test_native_actual_layout_mismatch_is_reported_without_partial_pcm(self):
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);source=directory/'two.wav'
            self.write_wave(source,[[1000]*16000,[3000]*16000])
            with self.assertRaisesRegex(ValueError,'音频通道与项目配置'):
                self.render_wave(directory,source,4,[('3','dialogue',{},None)])
            source=directory/'four.wav'
            self.write_wave(source,[[1000]*16000,[3000]*16000,[6000]*16000,[9000]*16000])
            # A legacy whole-stereo plan must validate its declared layout too.
            with self.assertRaisesRegex(ValueError,'音频通道与项目配置'):
                self.render_wave(directory,source,2)
