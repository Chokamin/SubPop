import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from probes.run_job import cached_recognition

class RecoveryTests(unittest.TestCase):
    def test_only_matching_intact_failed_generation_is_reused(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);job=root/'old';job.mkdir()
            pcm=b'\0'*8;xml=b'<fcpxml/>'
            state=dict(jobID='new',snapshotSHA256=hashlib.sha256(xml).hexdigest(),projectUID='p',modelID='qwen3-asr-0.6b',audioMode='dialogue',vocabulary=[])
            old={**state,'jobID':'old','status':'failed','stage':'generate-titles','createdAt':'2026-09-12T00:00:00+00:00'}
            snapshot={'sampleCount':2}
            result=dict(snapshot=snapshot,modelID='qwen3-asr-0.6b',pcm_sha256=hashlib.sha256(pcm).hexdigest())
            (job/'status.json').write_text(json.dumps(old));(job/'input.fcpxml').write_bytes(xml)
            (job/'asr.json').write_text(json.dumps(result));(job/'timeline.f32le').write_bytes(pcm)
            with patch('probes.run_job.WORK',root):
                self.assertEqual(cached_recognition(state,snapshot),('old',result))
                for key,value in [('modelID','other'),('snapshotSHA256','wrong'),('audioMode','all'),('vocabulary',['x'])]:
                    self.assertIsNone(cached_recognition({**state,key:value},snapshot))
                # Migrating from the fast endpoint must never reuse its cloud result.
                state['modelID']=old['modelID']=result['modelID']='doubao-cloud'
                result['backendVersion']=1
                (job/'status.json').write_text(json.dumps(old));(job/'asr.json').write_text(json.dumps(result))
                self.assertIsNone(cached_recognition(state,snapshot))
                result['cloudProtocol']='seed-asr-2.0'
                (job/'asr.json').write_text(json.dumps(result))
                self.assertEqual(cached_recognition(state,snapshot),('old',result))
                (job/'timeline.f32le').write_bytes(b'x'*8)
                self.assertIsNone(cached_recognition(state,snapshot))
