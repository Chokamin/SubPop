import json
import tempfile
from pathlib import Path
import unittest
from probes.vocabulary import parse,validate,context
from probes.worker import model_request

class VocabularyTests(unittest.TestCase):
    def test_hints_deduplicate_without_changing_numbers_or_technical_symbols(self):
        self.assertEqual(parse(' 小蚕，USB-C\n3.5%;小蚕、Qwen3-ASR'),['小蚕','USB-C','3.5%','Qwen3-ASR'])
        self.assertEqual(context(['USB-C','3.5%']),'USB-C，3.5%')
    def test_invalid_and_oversized_hints_refused(self):
        for value in ('x'*65,'a\tb',','.join(str(i) for i in range(101)),','.join(str(i)+'x'*60 for i in range(40))):
            with self.assertRaises(ValueError):parse(value)
        for value in ('string',[1],None):
            with self.assertRaises(ValueError):validate(value)
    def test_model_requests_only_accept_known_operations_and_models(self):
        with tempfile.TemporaryDirectory() as tmp:
            d=Path(tmp)/'d83c2ef0-8776-4679-afd2-3638fbd12e76';d.mkdir()
            value={'requestID':d.name,'kind':'model','operation':'install','modelID':'qwen3-asr-0.6b'}
            (d/'request.json').write_text(json.dumps(value));self.assertEqual(model_request(d),value)
            for key,bad in [('operation','shell'),('modelID','../../other')]:
                v={**value,key:bad};(d/'request.json').write_text(json.dumps(v))
                with self.assertRaises(ValueError):model_request(d)
