"""Native parser/decode checks outside the extension, not proof of sandbox access."""
import json
import math
from array import array
import struct
from pathlib import Path
import subprocess
import tempfile
import unittest
import wave
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
UID = '0D11EC79-ED11-4688-97A9-CB78621857DD'


class AudioProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory()
        cls.directory = Path(cls.scratch.name)
        cls.binary = cls.directory/'audio-probe'
        sdk = subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
        subprocess.run(['xcrun','clang','-isysroot',sdk,'-fobjc-arc','-Wall','-Wextra','-Werror',
                        '-framework','Foundation','-framework','AVFoundation','-framework','CoreMedia',
                        str(ROOT/'native/Probe/AudioProbe.m'),str(ROOT/'native/Probe/AudioProbeCLI.m'),
                        '-o',str(cls.binary)],check=True,capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def probe(self, mutate=lambda tree: None, uid=UID):
        tree = ET.parse(ROOT/'tests/fixtures/fcp-12.3-caption-readback.fcpxml')
        tree.find('.//media-rep').set('src',(ROOT/'.subloom/verification/mandarin.mp4').as_uri())
        mutate(tree)
        xml = self.directory/'test.fcpxml'
        tree.write(xml,encoding='utf-8')
        return json.loads(subprocess.check_output([str(self.binary),str(xml),uid,str(self.directory)],text=True))

    def test_wrong_active_project_refused(self):
        self.assertEqual(self.probe(uid='different')['stage'],'active-project-uid-mismatch')

    def test_actual_split_and_gap_refused_before_decode(self):
        for name in ('audio-split-4s','audio-leading-gap'):
            xml=ROOT/f'tests/fixtures/fcp-12.3-{name}.fcpxml'
            result=json.loads(subprocess.check_output([str(self.binary),str(xml),UID,str(self.directory)],text=True))
            self.assertEqual(result['stage'],'plain-clip-required')

    def test_derived_tail_trim_uses_source_offset(self):
        # Derived decoder experiment, not a host mix: isolate the real second
        # segment, enable it and remove attached titles/captions.
        def tail(tree):
            actual=ET.parse(ROOT/'tests/fixtures/fcp-12.3-audio-split-4s.fcpxml')
            segment=actual.findall('.//spine/asset-clip')[1]
            clip=tree.find('.//asset-clip')
            clip.attrib.clear();clip.attrib.update(segment.attrib)
            clip.attrib.pop('enabled',None);clip.set('offset','3600s')
            for child in list(clip):clip.remove(child)
            tree.find('.//sequence').set('duration',segment.get('duration'))
        whole=self.probe()
        whole_bytes=(self.directory/whole['pcmFile']).read_bytes()
        result=self.probe(tail)
        self.assertEqual(result['status'],'decoded',result)
        self.assertEqual(result['sourceStartSeconds'],4)
        self.assertEqual(result['sampleCount'],74880)
        # A sample-for-sample comparison catches silently decoding from zero.
        self.assertEqual((self.directory/result['pcmFile']).read_bytes(),whole_bytes[64000*4:])

    def test_aac_packet_boundaries_trim_to_requested_audio_range(self):
        media=self.directory/'packet-boundary.m4a'
        subprocess.run(['/opt/homebrew/bin/ffmpeg','-v','error','-nostdin','-y','-f','lavfi','-i',
                        'sine=frequency=440:sample_rate=48000:duration=31','-c:a','aac',str(media)],check=True)
        for start,duration in ((0,30),(30,1)):
            def mutate(tree):
                tree.find('.//media-rep').set('src',media.as_uri())
                tree.find('.//sequence').set('duration',f'{duration}s')
                clip=tree.find('.//asset-clip');clip.set('duration',f'{duration}s');clip.set('start',f'{start}s')
            result=self.probe(mutate)
            self.assertEqual(result['status'],'decoded',result)
            self.assertEqual(result['sampleCount'],duration*16000)
            self.assertGreater(result['rms'],0.01)

    def test_source_audio_attributes_refused(self):
        for key,value in (('srcEnable','video'),('srcEnable','invalid'),('audioStart','1s'),('audioDuration','2s')):
            with self.subTest(key=key,value=value):
                result=self.probe(lambda t:t.find('.//asset-clip').set(key,value))
                self.assertEqual(result['stage'],'unverified-source-audio')

    def test_real_host_audio_adjustments_refused(self):
        from probes.snapshot import prepare
        for name in ('audio-minus6db','audio-component-disabled'):
            with self.subTest(name=name):
                data,_=prepare((ROOT/f'tests/fixtures/fcp-12.3-{name}.fcpxml').read_bytes())
                xml=self.directory/'host.fcpxml';xml.write_bytes(data)
                result=json.loads(subprocess.check_output([str(self.binary),str(xml),UID,str(self.directory)],text=True))
                self.assertEqual(result['stage'],'unverified-clip-features')

    def test_partial_project_refused(self):
        result = self.probe(lambda t: t.find('.//asset-clip').set('duration','2s'))
        self.assertEqual(result['stage'],'full-project-coverage-required')

    def test_network_media_refused(self):
        result = self.probe(lambda t: t.find('.//media-rep').set('src','https://example.invalid/audio.mp4'))
        self.assertEqual(result['stage'],'local-media-required')

    def test_short_source_cannot_pass_as_whole_project(self):
        def longer_project(tree):
            tree.find('.//sequence').set('duration','9s')
            tree.find('.//asset-clip').set('duration','9s')
        self.assertEqual(self.probe(longer_project)['stage'],'incomplete-project-audio')

    def test_short_audio_track_uses_verified_silence_without_losing_position(self):
        from array import array
        media=self.directory/'short-audio-5994.mp4'
        subprocess.run(['/opt/homebrew/bin/ffmpeg','-v','error','-nostdin','-y',
            '-f','lavfi','-t','4.004','-i','color=c=black:size=160x90:rate=60000/1001',
            '-f','lavfi','-t','2','-i','sine=frequency=440:sample_rate=48000',
            '-c:v','mpeg4','-c:a','aac','-ac','1',str(media)],check=True)
        for start,duration,audible in ((0,4,2),(1,3,1),(3,1,0)):
            def mutate(tree):
                tree.find('.//media-rep').set('src',media.as_uri())
                tree.find('.//sequence').set('duration',f'{duration}s')
                clip=tree.find('.//asset-clip');clip.set('start',f'{start}s');clip.set('duration',f'{duration}s')
            result=self.probe(mutate)
            self.assertEqual(result['status'],'decoded',result)
            self.assertEqual(result['sampleCount'],duration*16000)
            pcm=array('f');pcm.frombytes((self.directory/result['pcmFile']).read_bytes())
            if audible:self.assertGreater(max(abs(v) for v in pcm[:audible*16000]),0.05)
            self.assertTrue(all(v==0 for v in pcm[audible*16000:]))
            self.assertEqual(result['verifiedSilenceSamples'],(duration-audible)*16000)

    def test_requested_range_after_container_end_still_fails(self):
        def mutate(tree):
            tree.find('.//sequence').set('duration','1s')
            clip=tree.find('.//asset-clip');clip.set('start','9s');clip.set('duration','1s')
        self.assertEqual(self.probe(mutate)['stage'],'incomplete-project-audio')

    def test_delayed_audio_track_keeps_leading_silence(self):
        from array import array
        media=self.directory/'delayed-audio.mp4'
        subprocess.run(['/opt/homebrew/bin/ffmpeg','-v','error','-nostdin','-y',
            '-f','lavfi','-t','4','-i','color=c=black:size=160x90:rate=25',
            '-itsoffset','1','-f','lavfi','-t','2','-i','sine=frequency=440:sample_rate=48000',
            '-c:v','mpeg4','-c:a','aac','-ac','1',str(media)],check=True)
        def mutate(tree):
            tree.find('.//media-rep').set('src',media.as_uri())
            tree.find('.//sequence').set('duration','4s');tree.find('.//asset-clip').set('duration','4s')
        result=self.probe(mutate);self.assertEqual(result['status'],'decoded',result)
        pcm=array('f');pcm.frombytes((self.directory/result['pcmFile']).read_bytes())
        self.assertEqual(len(pcm),64000)
        self.assertEqual(max(abs(v) for v in pcm[:15000]),0)
        self.assertGreater(max(abs(v) for v in pcm[18000:46000]),0.05)
        self.assertEqual(max(abs(v) for v in pcm[50000:]),0)

    def test_decode_whole_fixture(self):
        result = self.probe()
        self.assertEqual(result['status'],'decoded',result)
        self.assertEqual(result['sampleRate'],16000)
        self.assertEqual(result['channels'],1)
        self.assertEqual(result['sampleCount'],138880)
        self.assertEqual(result['pcmBytes'],138880*4)
        self.assertGreater(result['rms'],0)
        self.assertIn('unknown',result['audibility'])

    def channel_media(self, channels=4, rate=16000, seconds=1, name='channels.wav', frequency=170):
        """Independent physical channels; no ASR model or FCP session involved."""
        values=array('h')
        for frame in range(int(rate*seconds)):
            for channel in range(channels):
                values.append(round(5000*math.sin(2*math.pi*(frequency+channel*137)*frame/rate)))
        media=self.directory/name
        with wave.open(str(media),'wb') as output:
            output.setnchannels(channels);output.setsampwidth(2);output.setframerate(rate);output.writeframes(values.tobytes())
        return media,values

    def channel_probe(self, media, mix=None, duration=1, start=0, channels=None, sources=None):
        root=ET.Element('fcpxml',version='1.14');resources=ET.SubElement(root,'resources')
        asset=ET.SubElement(resources,'asset',id='audio',hasAudio='1',start='0s')
        if channels is not None:asset.set('audioChannels',str(channels))
        if sources is not None:asset.set('audioSources',str(sources))
        ET.SubElement(asset,'media-rep',kind='original-media',src=media.as_uri())
        project=ET.SubElement(root,'project',uid=UID,name='Physical-channel decoder fixture')
        sequence=ET.SubElement(project,'sequence',duration=f'{duration}s',tcStart='0s')
        spine=ET.SubElement(sequence,'spine')
        ET.SubElement(spine,'asset-clip',ref='audio',offset='0s',start=f'{start}s',duration=f'{duration}s',audioRole='dialogue')
        xml=self.directory/'channel-test.fcpxml';xml.write_bytes(ET.tostring(root))
        command=[str(self.binary),str(xml),UID,str(self.directory)]
        if mix is not None:command.append(json.dumps(mix))
        result=json.loads(subprocess.check_output(command,text=True))
        pcm=None
        if result.get('status')=='decoded':
            pcm=array('f');pcm.frombytes((self.directory/result['pcmFile']).read_bytes())
        return result,pcm

    def test_inspection_reports_actual_channel_layout_without_xml_claims(self):
        media,_=self.channel_media(6)
        result=json.loads(subprocess.check_output([str(self.binary),'--inspect-file',str(media)],text=True))
        self.assertEqual(result['status'],'ready',result)
        self.assertEqual(result['audioTracks'],1)
        self.assertEqual(result['audioChannels'],6)
        self.assertEqual(len(result['tracks']),1)
        self.assertEqual(result['tracks'][0]['channels'],6)
        self.assertEqual((result['tracks'][0]['firstChannel'],result['tracks'][0]['lastChannel']),(1,6))

    def test_four_channel_selection_excludes_unselected_audio_and_keeps_pcm(self):
        media,source=self.channel_media(4)
        result,pcm=self.channel_probe(media,{'components':[{'channels':[3],'gain':1.0}],
            'expectedChannels':4,'expectedSources':1,'sourceID':None})
        self.assertEqual(result['status'],'decoded',result)
        self.assertEqual(len(pcm),16000)
        self.assertLess(max(abs(value-source[index*4+2]/32768) for index,value in enumerate(pcm)),1e-7)

    def test_component_averaging_and_independent_channel_gain(self):
        media,source=self.channel_media(4)
        mix={'components':[{'channels':[1,2],'gain':0.5},{'channels':[3],'gain':0.25}],
            'expectedChannels':4,'expectedSources':1}
        result,pcm=self.channel_probe(media,mix)
        self.assertEqual(result['status'],'decoded',result)
        expected=[((source[i*4]+source[i*4+1])*0.25+source[i*4+2]*0.25)/32768 for i in range(16000)]
        self.assertLess(max(abs(actual-wanted) for actual,wanted in zip(pcm,expected)),1e-7)
        muted,zeros=self.channel_probe(media,{'components':[],'expectedChannels':4,'expectedSources':1})
        self.assertEqual(muted['status'],'decoded',muted)
        self.assertTrue(all(value==0 for value in zeros))

    def test_six_channels_resample_without_reordering_selected_channel(self):
        media,source=self.channel_media(6,rate=48000)
        mono=self.directory/'six-channel-reference.wav'
        with wave.open(str(mono),'wb') as output:
            output.setnchannels(1);output.setsampwidth(2);output.setframerate(48000)
            output.writeframes(array('h',(source[index] for index in range(5,len(source),6))).tobytes())
        result,pcm=self.channel_probe(media,{'components':[{'channels':[6],'gain':1}],
            'expectedChannels':6,'expectedSources':1})
        reference,wanted=self.channel_probe(mono,{'components':[{'channels':[1],'gain':1}]})
        self.assertEqual(result['status'],'decoded',result)
        self.assertEqual(reference['status'],'decoded',reference)
        self.assertEqual(len(pcm),16000)
        self.assertLess(max(abs(actual-expected) for actual,expected in zip(pcm,wanted)),1e-6)

    def test_partial_channels_use_actual_metadata_and_reject_conflicting_claims(self):
        media,_=self.channel_media(4)
        result,_=self.channel_probe(media,{'components':[{'channels':[4],'gain':1}],
            'expectedChannels':None,'expectedSources':None})
        self.assertEqual(result['status'],'decoded',result)
        for mix in ({'components':None,'expectedChannels':2},
                    {'components':None,'expectedSources':2},
                    {'components':[{'channels':[5],'gain':1}]},
                    {'components':[{'channels':[1,1],'gain':1}]},
                    {'components':[{'channels':[1],'gain':1},{'channels':[1],'gain':1}]},
                    {'components':[{'channels':[True],'gain':1}]},
                    {'components':[{'channels':[1],'gain':-1}]},
                    {'components':[{'channels':[1],'gain':float('nan')}]},
                    {'components':None,'sourceID':'2'}):
            with self.subTest(mix=mix):
                invalid,_=self.channel_probe(media,mix)
                self.assertEqual(invalid['status'],'failed',invalid)
                self.assertNotIn('pcmFile',invalid)
        conflict,_=self.channel_probe(media,channels=2,sources=1)
        self.assertEqual(conflict['stage'],'audio-layout-conflict',conflict)

    def test_default_stereo_retains_legacy_pcm_and_explicit_groups_do_not_double_normalize(self):
        media,_=self.channel_media(2,rate=48000)
        original,wanted=self.channel_probe(media,channels=2,sources=1)
        default,default_pcm=self.channel_probe(media,{'components':None,'expectedChannels':2,'expectedSources':1})
        self.assertEqual(default['status'],'decoded',default)
        self.assertEqual(default_pcm.tobytes(),wanted.tobytes())
        self.assertEqual(default['channelMixMode'],'legacy-mono-stereo-downmix')
        explicit,pcm=self.channel_probe(media,{'components':[{'channels':[1,2],'gain':1}],
            'expectedChannels':2,'expectedSources':1})
        self.assertEqual(original['status'],'decoded',original)
        self.assertEqual(explicit['status'],'decoded',explicit)
        self.assertEqual(explicit['channelMixMode'],'selected-source-components')
        scalar,scalar_pcm=self.channel_probe(media,{'components':[{'channels':[1],'gain':0.5},{'channels':[2],'gain':0.5}],
            'expectedChannels':2,'expectedSources':1})
        self.assertEqual(scalar['status'],'decoded',scalar)
        self.assertLess(max(abs(actual-expected) for actual,expected in zip(scalar_pcm,pcm)),1e-7)
        self.assertEqual(scalar['channelMixMode'],'selected-source-components')

    def test_selected_multichannel_short_delayed_track_preserves_pts_and_silence(self):
        media,source=self.channel_media(4,rate=48000,seconds=2,name='delayed-four-source.wav')
        delayed=self.directory/'delayed-four.mov'
        subprocess.run(['/opt/homebrew/bin/ffmpeg','-v','error','-nostdin','-y',
            '-f','lavfi','-t','4','-i','color=c=black:size=160x90:rate=25',
            '-itsoffset','1','-i',str(media),'-c:v','mpeg4','-c:a','pcm_s16le',str(delayed)],check=True)
        mix={'components':[{'channels':[2],'gain':1}],'expectedChannels':4,'expectedSources':1}
        result,pcm=self.channel_probe(delayed,mix,duration=4)
        self.assertEqual(result['status'],'decoded',result)
        self.assertEqual(len(pcm),64000)
        # The source has a one-second edit-list gap. Resampling may pre-ring a
        # few samples at the genuine onset; that is audio, not lost PTS padding.
        self.assertTrue(all(value==0 for value in pcm[:15900]))
        self.assertGreater(max(abs(value) for value in pcm[17000:47000]),0.1)
        self.assertTrue(all(value==0 for value in pcm[48000:]))
        trimmed,trimmed_pcm=self.channel_probe(delayed,mix,duration=1,start=2)
        self.assertEqual(trimmed['status'],'decoded',trimmed)
        # A restarted 48→16 kHz converter can change a few boundary samples;
        # enforce the real sound clock within the established 1ms allowance.
        best=min((sum((trimmed_pcm[index]-pcm[32000+index+lag])**2 for index in range(100,15000)),lag)
            for lag in range(-16,17))
        self.assertLess(best[0]/14900,1e-7,best)
        invalid,_=self.channel_probe(delayed,mix,duration=1,start=5)
        self.assertEqual(invalid['stage'],'incomplete-project-audio',invalid)

    def test_continuous_resampling_keeps_30_second_chunks_and_fractional_ranges_on_source_clock(self):
        media,_=self.channel_media(4,rate=48000,seconds=31,name='long-four.wav')
        mix={'components':[{'channels':[1],'gain':0.25},{'channels':[3],'gain':0.75}],
            'expectedChannels':4,'expectedSources':1}
        for start,duration in ((0,30),(30,1),(1,30)):
            with self.subTest(start=start,duration=duration):
                result,pcm=self.channel_probe(media,mix,start=start,duration=duration)
                self.assertEqual(result['status'],'decoded',result)
                self.assertEqual(len(pcm),duration*16000)
                # Check early and late physical sound, not just padded length.
                indices=list(range(100,1100))+list(range(len(pcm)-1100,len(pcm)-100))
                wanted=lambda i:(5000/32768)*(0.25*math.sin(2*math.pi*170*(start+i/16000))
                    +0.75*math.sin(2*math.pi*444*(start+i/16000)))
                self.assertLess(max(abs(pcm[i]-wanted(i)) for i in indices),1e-4)
        fractional,_=self.channel_media(4,rate=44100,seconds=2,name='fractional-four.wav')
        result,pcm=self.channel_probe(fractional,{'components':[{'channels':[2],'gain':1}]},
            start='1/25',duration='41/40')
        self.assertEqual(result['status'],'decoded',result)
        self.assertEqual(len(pcm),16400)
        self.assertLess(max(abs(pcm[i]-(5000/32768)*math.sin(2*math.pi*307*(0.04+i/16000)))
            for i in range(100,16300)),1e-4)

    def test_same_physical_pcm_in_wav_and_split_mov_tracks_keeps_identical_sound_clock(self):
        source,pcm=self.channel_media(4,rate=48000,seconds=3,name='same-four.wav')
        split=[]
        for index in (0,1):
            path=self.directory/f'same-stereo-{index}.wav';split.append(path)
            interleaved=array('h',(pcm[frame*4+index*2+channel] for frame in range(3*48000) for channel in (0,1)))
            with wave.open(str(path),'wb') as output:
                output.setnchannels(2);output.setsampwidth(2);output.setframerate(48000);output.writeframes(interleaved.tobytes())
        container=self.directory/'same-two-tracks.mov'
        subprocess.run(['/opt/homebrew/bin/ffmpeg','-v','error','-nostdin','-y',
            '-f','lavfi','-t','3','-i','color=c=black:size=160x90:rate=25',
            '-i',str(split[0]),'-i',str(split[1]),'-map','0:v','-map','1:a','-map','2:a',
            '-c:v','mpeg4','-c:a','pcm_s16le',str(container)],check=True)
        mix={'components':[{'channels':[1],'gain':0.5},{'channels':[4],'gain':0.25}]}
        wav_result,wav_pcm=self.channel_probe(source,mix,start=1,duration=2)
        mov_result,mov_pcm=self.channel_probe(container,mix,start=1,duration=2)
        self.assertEqual(wav_result['status'],'decoded',wav_result)
        self.assertEqual(mov_result['status'],'decoded',mov_result)
        self.assertEqual(len(wav_pcm),32000);self.assertEqual(len(mov_pcm),32000)
        self.assertLess(max(abs(actual-expected) for actual,expected in zip(mov_pcm,wav_pcm)),1e-7)

    @staticmethod
    def make_tracks_simultaneous(media):
        """Test fixture only: change MOV track flags/groups, never PCM or PTS.

        FFmpeg marks extra audio tracks as alternates by default. Set the
        generated tracks to independently enabled, non-alternate inputs to
        exercise the distinct safe-default-mix path.
        """
        data=bytearray(media.read_bytes())
        def atoms(begin,end):
            cursor=begin
            while cursor+8<=end:
                size,kind=struct.unpack_from('>I4s',data,cursor);header=8
                if size==1:size=struct.unpack_from('>Q',data,cursor+8)[0];header=16
                if size==0:size=end-cursor
                if size<header or cursor+size>end:raise AssertionError('Invalid generated MOV atom')
                yield kind,cursor+header,cursor+size
                cursor+=size
        for kind,begin,end in atoms(0,len(data)):
            if kind!=b'moov':continue
            for child,first,last in atoms(begin,end):
                if child!=b'trak':continue
                for atom,start,finish in atoms(first,last):
                    if atom!=b'tkhd':continue
                    flags=int.from_bytes(data[start+1:start+4],'big')|1
                    data[start+1:start+4]=flags.to_bytes(3,'big')
                    alternate=start+(46 if data[start]==1 else 34)
                    data[alternate:alternate+2]=b'\0\0'
        media.write_bytes(data)

    def multitrack_media(self, simultaneous=False, stereo_first=False):
        first,first_pcm=self.channel_media(2 if stereo_first else 1,seconds=2,name='multi-first.wav')
        second,second_pcm=self.channel_media(2,seconds=1,name='multi-second.wav',frequency=730)
        media=self.directory/('simultaneous.mov' if simultaneous else 'alternate.mov')
        subprocess.run(['/opt/homebrew/bin/ffmpeg','-v','error','-nostdin','-y',
            '-f','lavfi','-t','4','-i','color=c=black:size=160x90:rate=25',
            '-i',str(first),'-itsoffset','0.5','-i',str(second),
            '-map','0:v','-map','1:a','-map','2:a','-c:v','mpeg4','-c:a','pcm_s16le',str(media)],check=True)
        if simultaneous:self.make_tracks_simultaneous(media)
        return media,first_pcm,second_pcm

    def test_default_multiple_tracks_mix_only_unambiguous_simultaneous_sources(self):
        media,first,second=self.multitrack_media(simultaneous=True)
        info=json.loads(subprocess.check_output([str(self.binary),'--inspect-file',str(media)],text=True))
        self.assertEqual(info['audioTracks'],2,info)
        self.assertEqual([track['channels'] for track in info['tracks']],[1,2])
        self.assertFalse(info['hasAlternateAudio'],info)
        self.assertFalse(info['hasAudioAssociations'],info)
        self.assertTrue(info['allTracksEnabled'],info)
        result,pcm=self.channel_probe(media,{'components':None,'expectedChannels':None,'expectedSources':2},duration=4)
        self.assertEqual(result['status'],'decoded',result)
        # Default means each real track's AVFoundation downmix matrix, which
        # uses equal-power stereo coefficients rather than a group mean.
        first_result,first_mono=self.channel_probe(self.directory/'multi-first.wav',duration=2)
        second_result,second_mono=self.channel_probe(self.directory/'multi-second.wav',duration=1)
        self.assertEqual(first_result['status'],'decoded',first_result)
        self.assertEqual(second_result['status'],'decoded',second_result)
        wanted=[]
        for sample in range(64000):
            value=first_mono[sample] if sample<len(first_mono) else 0
            index=sample-8000
            if 0<=index<len(second_mono):value+=second_mono[index]
            wanted.append(value)
        self.assertLess(max(abs(actual-expected) for actual,expected in zip(pcm,wanted)),1e-7)
        self.assertTrue(all(value==0 for value in pcm[32000:]))

    def test_explicit_multitrack_global_channels_and_source_local_channels(self):
        media,first,second=self.multitrack_media(stereo_first=True)
        default,_=self.channel_probe(media,{'components':None,'expectedChannels':2,'expectedSources':2},duration=4)
        self.assertEqual(default['stage'],'ambiguous-audio-tracks',default)
        mixed,pcm=self.channel_probe(media,{'components':[{'channels':[1],'gain':1},{'channels':[4],'gain':0.5}],
            'expectedChannels':2,'expectedSources':2},duration=4)
        self.assertEqual(mixed['status'],'decoded',mixed)
        wanted=[]
        for sample in range(64000):
            value=first[sample*2]/32768 if sample<len(first)//2 else 0
            index=sample-8000
            if 0<=index<len(second)//2:value+=second[index*2+1]/65536
            wanted.append(value)
        self.assertLess(max(abs(actual-expected) for actual,expected in zip(pcm,wanted)),1e-7)
        local,second_only=self.channel_probe(media,{'components':[{'channels':[2],'gain':1}],
            'sourceID':'2','expectedChannels':2,'expectedSources':2},duration=4)
        self.assertEqual(local['status'],'decoded',local)
        second_expected=[second[(sample-8000)*2+1]/32768 if 8000<=sample<24000 else 0 for sample in range(64000)]
        self.assertLess(max(abs(actual-expected) for actual,expected in zip(second_only,second_expected)),1e-7)
        self.assertTrue(all(value==0 for value in second_only[:8000]))
        invalid,_=self.channel_probe(media,{'components':[{'channels':[3],'gain':1}],
            'sourceID':'2','expectedChannels':2,'expectedSources':2},duration=4)
        self.assertEqual(invalid['stage'],'invalid-channel-selection',invalid)
        invalid,_=self.channel_probe(media,{'components':None,'sourceID':'3'},duration=4)
        self.assertEqual(invalid['stage'],'unverified-audio-source-id',invalid)
