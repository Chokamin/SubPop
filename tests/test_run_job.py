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

    def test_failed_decode_never_marks_job_ready(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);xml=root/'input.xml';xml.write_text('<fcpxml/>')
            with patch.object(run_job,'WORK',root/'jobs'),patch.object(run_job,'preflight',return_value={'uid':run_job.UID}),patch.object(run_job.subprocess,'run',side_effect=RuntimeError('decoder failed')):
                with self.assertRaises(RuntimeError):run_job.run(xml,root,root)
            state=json.loads(next((root/'jobs').glob('*/status.json')).read_text())
            self.assertEqual(state['status'],'failed');self.assertEqual(state['stage'],'decode')
            self.assertNotIn('outputs',state)
