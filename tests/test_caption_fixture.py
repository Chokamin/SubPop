import json
from pathlib import Path
import unittest
from probes.caption_fixture import captions, srt

ROOT=Path(__file__).resolve().parents[1]

class CaptionFixtureTests(unittest.TestCase):
    def setUp(self):
        self.data=json.loads((ROOT/'docs/evidence/subpop-native-asr.json').read_text())

    def test_real_alignment_keeps_words_and_measured_times(self):
        rows=captions(self.data)
        self.assertEqual([(r['start_frame'],r['end_frame']) for r in rows],[(0,80),(84,140),(146,214)])
        self.assertEqual(''.join(r['text'] for r in rows),self.data['results'][0]['text'])
        self.assertIn('00:00:05,840 --> 00:00:08,560',srt(rows))
        # The measured zero-length 我 token is preserved within its sentence.
        self.assertIn('我们',rows[1]['text'])

    def test_text_mismatch_is_not_assigned_invented_timing(self):
        self.data['results'][0]['text']='不匹配的文本。'
        with self.assertRaises(ValueError):captions(self.data)

    def test_overlapping_words_refused(self):
        self.data['results'][0]['words'][1]['start']=0
        with self.assertRaises(ValueError):captions(self.data)

    def test_time_outside_project_refused(self):
        self.data['results'][0]['words'][-1]['end']=20
        with self.assertRaises(ValueError):captions(self.data)
