import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from probes import run_job

class JobTests(unittest.TestCase):
    def test_preflight_refuses_other_project_before_decode(self):
        with patch.object(run_job,'inspect',return_value={'uid':'other'}):
            with self.assertRaises(ValueError):run_job.preflight(Path('x'),Path('a'),Path('b'))

    def test_firered_checkpoint_preflight_retains_directory_guard(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();model=root/'.subloom/models/firered-asr2-aed'
            model.mkdir(parents=True);(model/'model.pth.tar').touch()
            with patch.object(run_job,'ROOT',root),patch.object(run_job,'inspect',return_value={'uid':'fixture'}):
                self.assertEqual(run_job.preflight(Path('input'),model,None)['uid'],'fixture')
                (model/'linked').symlink_to(root/'outside')
                with self.assertRaises(ValueError):run_job.preflight(Path('input'),model,None)

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
