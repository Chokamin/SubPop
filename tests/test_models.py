import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from probes import models, worker

class ModelTests(unittest.TestCase):
    def test_catalog_has_distinct_models_and_default(self):
        ids=[m['id'] for m in models.CATALOG['models']]
        self.assertEqual(len(set(ids)),5)
        self.assertIn(models.DEFAULT_MODEL_ID,ids)
        self.assertEqual(len({m['directory'] for m in models.CATALOG['models']}),len(ids))
        for value in ('../../other',None,'qwen3-forced-aligner-0.6b'):
            with self.assertRaises(ValueError):models.model_spec(value)

    def test_missing_truncated_and_wrong_configuration_not_installed(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);d=root/'.subloom/models/asr';d.mkdir(parents=True)
            spec={'directory':'asr','hiddenSize':1024,'files':{'config.json':2,'model.safetensors':10}}
            (d/'config.json').write_text('{}')
            with self.assertRaises(ValueError):models.check_files(spec,root)
            (d/'model.safetensors').write_bytes(b'0'*9)
            with self.assertRaises(ValueError):models.check_files(spec,root)
            (d/'model.safetensors').write_bytes(b'0'*10)
            with self.assertRaises(ValueError):models.check_files(spec,root)
            (d/'config.json').write_text(json.dumps({'model_type':'qwen3_asr','thinker_config':{'text_config':{'hidden_size':1024}}}))
            spec['files']['config.json']=(d/'config.json').stat().st_size
            self.assertEqual(models.check_files(spec,root),d)
            (d/'model.safetensors').unlink();(d/'model.safetensors').symlink_to(d/'config.json')
            with self.assertRaises(ValueError):models.check_files(spec,root)

    def test_worker_routes_each_model_to_its_actual_job_argument(self):
        with tempfile.TemporaryDirectory() as temp:
            d=Path(temp)
            for spec in models.CATALOG['models']:
                (d/'request.json').write_text(json.dumps({'modelID':spec['id'],'audioMode':'dialogue','cloudConsent':spec.get('engine')=='doubao'}))
                with patch.object(worker,'resolve_model') as resolve:
                    command=worker.job_command(d)
                resolve.assert_called_once_with(spec['id'])
                self.assertEqual(command[command.index('--model')+1],spec['id'])
                self.assertEqual(command[command.index('--audio-mode')+1],'dialogue')

    def test_bundle_and_worker_share_catalog(self):
        bundle=models.ROOT/'.subloom/build/SubPop Probe.app/Contents/PlugIns/SubPopProbe.appex/Contents/Resources/models.json'
        self.assertEqual(json.loads(bundle.read_text()),models.CATALOG)
