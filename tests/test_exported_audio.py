from fractions import Fraction
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
import uuid
import wave
import xml.etree.ElementTree as ET
from unittest.mock import patch

from probes import exported_audio
from probes import run_job
from probes.snapshot import prepare
from probes.paths import AUDIO_BINARY
from probes.worker import request_input, job_command

FALLBACK_BINARY=Path(__file__).resolve().parents[1]/'.subloom/build/SubPopFallbackAudioTests'

def project_xml(duration='2s', node='unhandled-compound'):
    root=ET.Element('fcpxml',version='1.14')
    resources=ET.SubElement(root,'resources')
    ET.SubElement(resources,'format',id='r1',frameDuration='1/25s',width='1920',height='1080')
    project=ET.SubElement(root,'project',uid='FALLBACK-PROJECT',name='完整时间线')
    sequence=ET.SubElement(project,'sequence',format='r1',duration=duration,tcStart='3600s')
    spine=ET.SubElement(sequence,'spine')
    child=ET.SubElement(spine,node,offset='3600s',duration=duration)
    if node=='transition':ET.SubElement(child,'filter-audio')
    return ET.tostring(root)


def wav(path,seconds):
    with wave.open(str(path),'wb') as file:
        file.setnchannels(1);file.setsampwidth(2);file.setframerate(48000)
        file.writeframes(struct.pack('<h',1000)*round(seconds*48000))


class ExportedAudioTests(unittest.TestCase):
    @unittest.skipUnless(FALLBACK_BINARY.is_file(),'native fallback importer not built')
    def test_native_background_file_hash_does_not_overflow_worker_stack(self):
        subprocess.run([str(FALLBACK_BINARY),'hash'],check=True,capture_output=True,text=True,timeout=20)

    @unittest.skipUnless(FALLBACK_BINARY.is_file(),'native fallback importer not built')
    def test_native_import_copies_validates_and_resumes_without_crossing_projects(self):
        subprocess.run([str(FALLBACK_BINARY),'import'],check=True,capture_output=True,text=True,timeout=20)

    def test_unverified_audio_transition_uses_export_fallback(self):
        raw=project_xml(node='transition')
        with self.assertRaisesRegex(ValueError,'转场结构无法安全处理.*整条时间线音频'):
            prepare(raw,generic=True)
        with tempfile.TemporaryDirectory() as temp:
            xml=Path(temp)/'input.fcpxml';xml.write_bytes(raw)
            snapshot=exported_audio.project_context(xml)
            self.assertEqual(snapshot['sampleCount'],32000)
            self.assertEqual(snapshot['audioMode'],'exported')

    def test_external_source_keeps_original_project_clock_despite_unsupported_clip(self):
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);xml=directory/'input.fcpxml';xml.write_bytes(project_xml())
            snapshot=exported_audio.project_context(xml)
            self.assertEqual(snapshot['uid'],'FALLBACK-PROJECT')
            self.assertEqual(snapshot['sampleCount'],32000)
            self.assertEqual(snapshot['frameDuration'],'1/25')
            self.assertEqual(snapshot['audioMode'],'exported')

    def test_missing_or_changed_audio_refused_by_worker(self):
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp)/str(uuid.uuid4());directory.mkdir()
            xml=directory/'input.fcpxml';xml.write_bytes(project_xml())
            audio=directory/'exported-audio.wav';wav(audio,2)
            manifest={'requestID':directory.name,'projectUID':'FALLBACK-PROJECT',
                      'xmlSHA256':hashlib.sha256(xml.read_bytes()).hexdigest(),
                      'audioFile':audio.name,'audioSHA256':hashlib.sha256(audio.read_bytes()).hexdigest()}
            (directory/'request.json').write_text(json.dumps(manifest))
            self.assertEqual(request_input(directory),xml)
            with patch('probes.worker.resolve_model',return_value=(None,None)):
                self.assertIn('--audio-file',job_command(directory))
            with audio.open('ab') as file:file.write(b'changed')
            with self.assertRaisesRegex(ValueError,'已改变'):
                request_input(directory)

    @unittest.skipUnless(AUDIO_BINARY.is_file(),'native audio decoder not built')
    def test_native_decode_matches_full_project_and_rejects_partial_export(self):
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);xml=directory/'input.fcpxml';xml.write_bytes(project_xml())
            snapshot=exported_audio.project_context(xml)
            audio=directory/'complete.wav';wav(audio,2)
            decoded=exported_audio.render(audio,directory,AUDIO_BINARY,snapshot)
            self.assertEqual(decoded['sampleCount'],32000)
            self.assertEqual((directory/'timeline.f32le').stat().st_size,32000*4)
            self.assertGreater(decoded['rms'],0)
            padded=directory/'codec-tail.wav';wav(padded,1.98)
            adjusted=exported_audio.render(padded,directory,AUDIO_BINARY,snapshot)
            self.assertEqual(adjusted['sampleCount'],32000)
            self.assertEqual((directory/'timeline.f32le').stat().st_size,32000*4)
            short=directory/'partial.wav';wav(short,1)
            with self.assertRaisesRegex(ValueError,'时长'):
                exported_audio.render(short,directory,AUDIO_BINARY,snapshot)

    @unittest.skipUnless(AUDIO_BINARY.is_file(),'native audio decoder not built')
    def test_job_can_generate_timed_titles_from_export_when_xml_audio_is_unsupported(self):
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);xml=directory/'input.fcpxml';xml.write_bytes(project_xml(node='transition'))
            audio=directory/'complete.wav';wav(audio,2)
            jobs=directory/'jobs';jobs.mkdir()
            def recognized(input_xml,asr,aligner,output,pcm_path,**kwargs):
                snapshot=kwargs['snapshot_override']
                self.assertEqual(snapshot['audioMode'],'exported')
                return {'snapshot':snapshot,'pcm_sha256':hashlib.sha256(pcm_path.read_bytes()).hexdigest(),
                        'device':'test','results':[{'text':'你好','words':[
                            {'text':'你','start':0.2,'end':0.5},{'text':'好','start':0.5,'end':1.0}]}]}
            with patch.object(run_job,'WORK',jobs),patch.object(run_job,'check_models'),\
                 patch('probes.recognize_fixture.run',side_effect=recognized):
                output=run_job.run(xml,None,None,audio_file=audio,
                                   audio_sha=hashlib.sha256(audio.read_bytes()).hexdigest())
            manifest=json.loads((output/'captions.json').read_text())
            self.assertEqual(manifest['projectUID'],'FALLBACK-PROJECT')
            self.assertEqual(manifest['audioSource'],'exported-full-timeline')
            self.assertEqual(manifest['existingTitleReview'],'unavailable')
            self.assertEqual(manifest['captions'][0]['start_frame'],5)
            self.assertEqual(manifest['captions'][0]['end_frame'],25)
            self.assertTrue((output/'TitleProbe-1.14.fcpxml').is_file())


if __name__=='__main__':unittest.main()
