import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch
from probes import run_job

class JobTests(unittest.TestCase):
    def test_direct_job_reports_crossfade_hard_cut_without_blocking_recognition(self):
        root=ET.parse(Path(__file__).parent/'fixtures/fcp-12.3-native-drop.fcpxml').getroot()
        seq=root.find('.//project/sequence');first=seq.find('spine/asset-clip')
        first.set('duration','4s')
        second=ET.fromstring(ET.tostring(first))
        second.set('offset','3604s');second.set('start','4s');second.set('duration','117/25s')
        spine=seq.find('spine')
        transition=ET.SubElement(spine,'transition',offset='18019/5s',duration='2/5s')
        ET.SubElement(root.find('resources'),'effect',id='crossfade',uid='FFAudioTransition')
        ET.SubElement(transition,'filter-audio',ref='crossfade')
        spine.append(second)
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);xml=directory/'input.fcpxml';xml.write_bytes(ET.tostring(root))
            def decoded(_,job,*args):
                (job/'timeline.f32le').write_bytes(b'\0\0\0\0')
                return {'silent':False,'pcmFile':'timeline.f32le','pcmSHA256':'pcm'}
            def recognized(*args,**kwargs):
                return {'snapshot':kwargs['snapshot_override'],'pcm_sha256':'pcm','device':'test','results':[]}
            with patch.object(run_job,'WORK',directory/'jobs'),patch.object(run_job,'render',side_effect=decoded),\
                 patch('probes.recognize_fixture.run',side_effect=recognized),\
                 patch.object(run_job,'finalize',side_effect=lambda job,state,result,existing:result['snapshot']):
                snapshot=run_job.run(xml,None,None)
        self.assertEqual(snapshot['bypassedAudioTransitions'],[{'offset':'19/5','duration':'2/5'}])
        self.assertEqual(len(snapshot['segments']),2)

    def test_preflight_uses_selected_audio_mode_for_component_roles(self):
        root=ET.parse(Path(__file__).parent/'fixtures/component-clips.fcpxml').getroot()
        root.findall('.//audio-channel-source')[1].set('role','music.music-1')
        with tempfile.TemporaryDirectory() as temp:
            xml=Path(temp)/'input.fcpxml';xml.write_bytes(ET.tostring(root))
            with self.assertRaises(ValueError):run_job.preflight(xml,None,None)
            snapshot=run_job.preflight(xml,None,None,'all')
            self.assertEqual(snapshot['audioMode'],'all')
            self.assertEqual(len(snapshot['segments']),3)

    def test_preflight_refuses_other_project_before_decode(self):
        with patch.object(run_job,'inspect',return_value={'uid':'other'}):
            with self.assertRaises(ValueError):run_job.preflight(Path('x'),Path('a'),Path('b'))

    def test_failed_decode_never_marks_job_ready(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);xml=root/'input.xml';xml.write_text('<fcpxml/>')
            with patch.object(run_job,'WORK',root/'jobs'),patch.object(run_job,'preflight',return_value={'uid':run_job.UID}),patch.object(run_job,'prepare',return_value=(b'<fcpxml/>',[])),patch.object(run_job,'render',side_effect=RuntimeError('decoder failed')):
                with self.assertRaises(RuntimeError):run_job.run(xml,root,root)
            state=json.loads(next((root/'jobs').glob('*/status.json')).read_text())
            self.assertEqual(state['status'],'failed');self.assertEqual(state['stage'],'decode')
            self.assertNotIn('outputs',state)

    def test_silent_job_finishes_without_importing_asr_or_generating_titles(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);xml=root/'input.xml';xml.write_text('<fcpxml/>')
            with patch.object(run_job,'WORK',root/'jobs'),patch.object(run_job,'preflight',return_value={'uid':run_job.UID}),patch.object(run_job,'prepare',return_value=(b'<fcpxml/>',[])),patch.object(run_job,'render',return_value={'silent':True,'pcmSHA256':'silent'}):
                job=run_job.run(xml,root,root)
            state=json.loads((job/'status.json').read_text())
            self.assertEqual(state['status'],'blocked-no-audio')
            self.assertFalse(list(job.glob('TitleProbe*')))
            self.assertFalse((job/'asr.json').exists())

    def test_invalid_snapshot_has_terminal_validation_error(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);xml=root/'input.xml';xml.write_text('<fcpxml/>')
            with patch.object(run_job,'WORK',root/'jobs'):
                with self.assertRaises(ValueError):run_job.run(xml,root,root)
            state=json.loads(next((root/'jobs').glob('*/status.json')).read_text())
            self.assertEqual(state['status'],'failed')
            self.assertEqual(state['stage'],'validate')

    def test_existing_titles_warn_but_still_generate_draggable_result(self):
        rows=[{'text':'重新识别','start_frame':0,'end_frame':25}]
        existing=[{'text':'旧字幕','start_frame':0,'end_frame':25,'enabled':True}]
        result={'snapshot':{'frameDuration':'1/25','totalFrames':25},'pcm_sha256':'pcm','device':'cpu'}
        state={'projectUID':'project','modelID':'test','vocabulary':[]}
        with tempfile.TemporaryDirectory() as temp:
            output=Path(temp)
            with patch.object(run_job,'optimized_captions',return_value=rows),patch.object(run_job,'payload',return_value=b'<fcpxml/>'):
                run_job.finalize(output,state,result,existing)
            manifest=json.loads((output/'captions.json').read_text())
            status=json.loads((output/'status.json').read_text())
            self.assertEqual(status['status'],'ready')
            self.assertEqual(manifest['existingTitleCollision']['status'],'conflict')
            self.assertEqual(manifest['existingTitleCollision']['overlappingRows'],1)
            self.assertTrue((output/'TitleProbe-1.14.fcpxml').is_file())
