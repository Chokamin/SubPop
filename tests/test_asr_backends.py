import unittest
from unittest.mock import patch
from pathlib import Path
from probes.asr_backends import timed_row,load_backend
from probes import models

class AlternateTests(unittest.TestCase):
    def test_measured_times_and_event_tags(self):
        row=timed_row([('<|zh|>',0,0),('你好',.2,.8),('世界',1,2.2)],2)
        self.assertEqual(row['text'],'你好世界')
        self.assertEqual(row['words'][-1]['end'],2)
        self.assertEqual(row['words'][0]['start'],.2)
    def test_punctuation_attaches_without_inventing_speech_time(self):
        row=timed_row([('你好',.1,.5),('，',.6,.7),('世界',1,2)],3)
        self.assertEqual(row['text'],'你好，世界')
        self.assertEqual(row['words'][0],dict(text='你好，',start=.1,end=.5))
    def test_invalid_times_rejected(self):
        for start,end in [(float('nan'),1),(-1,1),(2,1),(4,5)]:
            with self.assertRaises(ValueError):timed_row([('字',start,end)],3)
    def test_alternate_models_do_not_require_qwen_aligner(self):
        for mid in ['whisper-large-v3-turbo','sensevoice-small']:
            with patch.object(models,'check_files',return_value=Path('/local')) as check:
                self.assertEqual(models.resolve_model(mid),(Path('/local'),None))
                self.assertEqual(check.call_count,1)
    def test_unknown_backend_rejected(self):
        with self.assertRaises(ValueError):load_backend('unknown',Path('/local'),'')
