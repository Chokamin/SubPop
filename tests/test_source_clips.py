"""Selected audio, source clocks and titles in sync/multicam edits."""
from copy import deepcopy
from fractions import Fraction
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as E
from test_project import basic,compound
from probes.project import inspect
from probes.snapshot import prepare


def fixture():
    root,p,seq,clip=basic();res=root.find('resources');asset=res.find('asset')
    asset.set('duration','12s');asset.set('start','0s');asset.set('audioChannels','1')
    other=deepcopy(asset);other.set('id','external');other.find('media-rep').set('src','file:///TEST_MEDIA/external.wav');res.append(other)
    seq.set('duration','4s');clip.set('duration','12s');clip.set('start','0s');clip.set('offset','0s');clip.set('audioRole','dialogue.voice')
    seq.find('spine').remove(clip)
    return root,p,seq,clip,other


def synchronized():
    root,p,seq,clip,_=fixture();sync=E.SubElement(seq.find('spine'),'sync-clip',offset='3600s',start='2s',duration='4s')
    sync.append(clip);external=deepcopy(clip);external.set('ref','external');external.set('lane','-1');sync.append(external)
    source=E.SubElement(sync,'sync-source',sourceID='storyline');E.SubElement(source,'audio-role-source',role='dialogue',active='0')
    return root,p,seq,sync


def multicam():
    root,p,seq,clip,_=fixture();media=E.SubElement(root.find('resources'),'media',id='multi')
    multi=E.SubElement(media,'multicam',format=seq.get('format'),tcStart='0s')
    for key,ref in [('camera',clip.get('ref')),('recorder','external')]:
        angle=E.SubElement(multi,'mc-angle',angleID=key);child=deepcopy(clip);child.set('ref',ref);angle.append(child)
    mc=E.SubElement(seq.find('spine'),'mc-clip',ref='multi',offset='3600s',start='2s',duration='4s')
    E.SubElement(mc,'mc-source',angleID='camera',srcEnable='video');E.SubElement(mc,'mc-source',angleID='recorder',srcEnable='audio')
    return root,p,seq,mc,multi


class SourceClipTests(unittest.TestCase):
    def plan(self,root,mode='dialogue'):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'project.fcpxml';p.write_bytes(E.tostring(root));return inspect(p,mode)

    def test_sync_selected_external_audio_preserves_trim_and_project_clock(self):
        root,_,_,_=synchronized();s=self.plan(root)['segments']
        self.assertEqual([(n['assetRef'],n['offset'],n['source_start'],n['duration']) for n in s],[('external','0','2','4')])

    def test_sync_disabled_primary_channels_do_not_mute_external(self):
        root,_,_,sync=synchronized();sync.remove(sync.find('sync-source'))
        primary=sync.find('asset-clip');E.SubElement(primary,'audio-channel-source',srcCh='1',active='0')
        self.assertEqual([n['assetRef'] for n in self.plan(root)['segments']],['external'])

    def test_sync_muted_connected_source_and_role_gain(self):
        root,_,_,sync=synchronized();sync.find('sync-source/audio-role-source').set('active','1')
        source=E.SubElement(sync,'sync-source',sourceID='connected');role=E.SubElement(source,'audio-role-source',role='dialogue',enabled='0')
        self.assertNotIn('external',[s['assetRef'] for s in self.plan(root)['segments']])
        role.set('enabled','1');E.SubElement(role,'adjust-volume',amount='-6dB')
        s=self.plan(root)['segments'];self.assertAlmostEqual(next(n for n in s if n['assetRef']=='external')['gain'],10**(-6/20))
        self.assertEqual(next(n for n in s if n['assetRef']!='external')['gain'],1)

    def test_sync_music_role_follows_dialogue_filter(self):
        root,_,_,sync=synchronized();sync.findall('asset-clip')[1].set('audioRole','music')
        self.assertEqual(self.plan(root)['segments'],[]);self.assertEqual(len(self.plan(root,'all')['segments']),1)

    def test_sync_audio_container_disabled_mutes_all_internal_sources(self):
        for attrs in ({'enabled':'0'},{'srcEnable':'video'}):
            root,_,seq,sync=synchronized();sync.attrib.update(attrs)
            other=deepcopy(sync.find('asset-clip'));other.set('lane','-1');other.set('offset','3600s');other.set('duration','4s');seq.find('spine')[0].append(other)
            # Internal synchronized sources, including negative lanes, mute.
            self.assertEqual(self.plan(root)['segments'],[])

    def test_sync_internal_spine_and_offset_audio(self):
        root,_,_,sync=synchronized();primary=sync.find('asset-clip');sync.remove(primary);sp=E.SubElement(sync,'spine',offset='0s');sp.append(primary)
        s=self.plan(root)['segments'][0];self.assertEqual((s['source_start'],s['duration']),('2','4'))

    def test_sync_split_audio_bounds_do_not_double_external_source(self):
        root,_,_,sync=synchronized();sync.set('audioStart','3s');sync.set('audioDuration','2s')
        s=self.plan(root)['segments'];self.assertEqual(len(s),1)
        # Connected audio follows its own range, clipped only by the project.
        self.assertEqual(s[0]['duration'],'4')

    def test_mc_camera_switch_keeps_recorder_audio(self):
        root,_,_,mc,_=multicam();s=self.plan(root)['segments'][0];self.assertEqual((s['assetRef'],s['source_start'],s['duration']),('external','2','4'))
        mc.find('mc-source').set('srcEnable','none');self.assertEqual(self.plan(root)['segments'],[s])
        mc.find('mc-source').set('srcEnable','all');self.assertEqual(len(self.plan(root)['segments']),2)

    def test_mc_multiple_edits_switch_audio_at_original_time(self):
        root,_,seq,mc,_=multicam();seq.set('duration','8s');second=deepcopy(mc);second.set('offset','3604s');second.set('start','6s')
        for source in second.findall('mc-source'):source.set('srcEnable','all' if source.get('angleID')=='camera' else 'none')
        seq.find('spine').append(second)
        self.assertEqual([(s['assetRef'],s['offset'],s['source_start']) for s in self.plan(root)['segments']],[('external','0','2'),('r2','4','6')])

    def test_mc_muted_recorder_role_does_not_restore_camera_audio(self):
        root,_,_,mc,_=multicam();E.SubElement(mc.findall('mc-source')[1],'audio-role-source',role='dialogue',active='0')
        self.assertEqual(self.plan(root)['segments'],[])

    def test_mc_no_selection_invalid_angles_and_cycles_refused(self):
        for case in ('missing','unknown','duplicate','cycle'):
            root,_,_,mc,multi=multicam()
            if case=='missing':
                for n in list(mc):mc.remove(n)
            elif case=='unknown':mc.find('mc-source').set('angleID','unknown')
            elif case=='duplicate':mc.append(deepcopy(mc.find('mc-source')))
            else:
                angle=multi.findall('mc-angle')[1];angle.clear();angle.set('angleID','recorder');nested=deepcopy(mc);nested.set('offset','0s');angle.append(nested)
            with self.assertRaises(ValueError):self.plan(root)

    def test_source_component_trims_and_unknown_mutes_are_not_ignored(self):
        for key in ('start','duration','unknown'):
            root,_,_,sync=synchronized();sync.find('sync-source/audio-role-source').set(key,'1s')
            with self.assertRaisesRegex(ValueError,'组件'):self.plan(root)
        root,_,_,mc,_=multicam();source=E.SubElement(mc.findall('mc-source')[1],'audio-role-source',role='dialogue');E.SubElement(source,'mute',start='1s',duration='1s')
        with self.assertRaisesRegex(ValueError,'静音区间'):self.plan(root)

    def test_mc_in_compound_retains_source_clock(self):
        root,_,seq,mc,_=multicam();before=self.plan(root)['segments'];compound(root,seq,mc)
        self.assertEqual(self.plan(root)['segments'],before)

    def test_selected_visual_titles_are_stripped_and_unselected_ones_ignored(self):
        root,_,_,mc,multi=multicam();before=self.plan(root)['segments'];res=root.find('resources');E.SubElement(res,'effect',id='title',uid='TEST-SILENT-TITLE')
        for i,angle in enumerate(multi):
            parent=angle[0];title=E.SubElement(parent,'title',ref='title',lane='1',offset='3s',start='0s',duration='1s');E.SubElement(title,'text').text='selected' if i==0 else 'audio-only'
        original=E.tostring(root);normalized,existing=prepare(original,generic=True)
        self.assertEqual([e['text'] for e in existing],['selected']);self.assertEqual(existing[0]['start_frame'],25)
        self.assertEqual(len(E.fromstring(normalized).findall('.//title')),0);self.assertEqual(E.tostring(root),original)
        self.assertEqual(self.plan(E.fromstring(normalized))['segments'],before)

    def test_mc_all_angles_disabled_keeps_silent_project_duration(self):
        root,_,_,mc,_=multicam()
        for source in mc:source.set('srcEnable','none')
        plan=self.plan(root);self.assertEqual(plan['segments'],[]);self.assertEqual(plan['sampleCount'],64000)

    def test_nested_conform_uses_immediate_parent_frame_clock(self):
        root,_,seq,mc,multi=multicam()
        root.find("resources/format[@id='r1']").set('frameDuration','1/30s')
        fmt=E.SubElement(root.find('resources'),'format',id='source-format',frameDuration='1001/30000s',width='1920',height='1080')
        multi.set('format',fmt.get('id'));E.SubElement(mc,'conform-rate',srcFrameRate='29.97')
        self.assertEqual(Fraction(self.plan(root)['segments'][0]['source_duration']),Fraction(1001,250))
        compound(root,seq,mc)
        root.find('resources/media/sequence').set('format',fmt.get('id'))
        self.assertNotIn('source_duration',self.plan(root)['segments'][0])

    def test_multicam_conformed_title_collision_uses_output_frames(self):
        root,_,_,mc,multi=multicam();res=root.find('resources')
        res.find('format').set('frameDuration','1/30s')
        E.SubElement(res,'format',id='source-format',frameDuration='1001/30000s',width='1920',height='1080')
        multi.set('format','source-format');E.SubElement(mc,'conform-rate',srcFrameRate='29.97')
        E.SubElement(res,'effect',id='title',uid='TEST-SILENT-TITLE')
        title=E.SubElement(multi[0][0],'title',ref='title',lane='1',offset='3s',start='0s',duration='1s')
        E.SubElement(title,'text').text='one second in source clock'
        normalized,existing=prepare(E.tostring(root),generic=True)
        self.assertEqual((existing[0]['start_frame'],existing[0]['end_frame']),(29,60))
        self.assertFalse(existing[0]['exactTiming']);self.assertEqual(len(self.plan(E.fromstring(normalized))['segments']),1)

    def test_source_subrole_overrides_parent_role_without_muting_other_sources(self):
        root,_,_,sync=synchronized();source=sync.find('sync-source')
        E.SubElement(source,'audio-role-source',role='dialogue.voice',active='1')
        # The specific component's selection overrides this source group's
        # parent role. Connected recorder settings remain independent.
        self.assertEqual(len(self.plan(root)['segments']),2)
        source.find("audio-role-source[@role='dialogue.voice']").set('active','0')
        self.assertEqual([s['assetRef'] for s in self.plan(root)['segments']],['external'])

    def test_2997_to_30_source_format_scales_audio_exactly_and_disable_keeps_1x(self):
        root,_,seq,clip,_=fixture();seq.find('spine').append(clip);clip.set('offset','3600s');clip.set('start','2s');clip.set('duration','4s')
        root.find("resources/format[@id='r1']").set('frameDuration','1/30s');root.find("resources/format[@id='r3']").set('frameDuration','1001/30000s')
        clip.set('format','r3');c=E.SubElement(clip,'conform-rate',srcFrameRate='29.97')
        s=self.plan(root)['segments'][0];self.assertEqual(Fraction(s['source_duration']),Fraction(1001,250));self.assertFalse(s['preservesPitch'])
        c.set('scaleEnabled','0');self.assertNotIn('source_duration',self.plan(root)['segments'][0])
        c.set('scaleEnabled','1');clip.attrib.pop('format');self.assertNotIn('source_duration',self.plan(root)['segments'][0])

    def test_real_fcp_roundtrip_frame_conform_sync_and_selected_angles(self):
        root=E.parse(Path(__file__).parent/'fixtures/fcp-12.3-2997-sync-multicam.fcpxml').getroot();normalized,existing=prepare(E.tostring(root),generic=True)
        self.assertEqual(existing,[]);plan=self.plan(E.fromstring(normalized));s=plan['segments'];self.assertEqual(plan['sampleCount'],450667)
        self.assertNotIn('source_duration',s[0]);self.assertEqual(Fraction(s[1]['source_duration']),Fraction(1001,250));self.assertNotIn('source_duration',s[2])
        selected=[n for n in s if n['offset']=='16'];self.assertEqual(len(selected),1);self.assertEqual(selected[0]['assetRef'],'r5')
