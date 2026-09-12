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

    def aligned(self, parts):
        return {'snapshot':{'duration':'10','relative_start':'0','project':'Test'},'results':parts}

    def test_rounding_shares_boundary_without_losing_text(self):
        data=self.aligned([{'text':'前一句。后一句。','words':[
            {'text':'前一句','start':0,'end':1.01},{'text':'后一句','start':1.02,'end':2}]}])
        from fractions import Fraction
        for fps in (25,30,Fraction(30000,1001)):
            rows=captions(data,fps,True)
            self.assertEqual(len(rows),2)
            self.assertEqual(rows[0]['end_frame'],rows[1]['start_frame'])
            self.assertEqual(''.join(r['text'] for r in rows),'前一句。后一句。')

    def test_subframe_captions_merge_instead_of_disappearing(self):
        data=self.aligned([{'text':'前。后。','words':[
            {'text':'前','start':0,'end':0.001},{'text':'后','start':0.002,'end':0.003}]}])
        self.assertEqual(captions(data,30,True),[{'text':'前。后。','start_frame':0,'end_frame':1}])

    def test_punctuation_inside_token_and_zero_length_text_preserved(self):
        data=self.aligned([{'text':'你好。世界。呜','words':[
            {'text':'你好世界','start':0,'end':1},{'text':'呜','start':2,'end':2}]}])
        rows=captions(data,30,True)
        self.assertEqual(rows,[{'text':'你好。世界。呜','start_frame':0,'end_frame':60}])

    def test_cross_chunk_overlap_merges_measured_intervals(self):
        data=self.aligned([{'text':'前一句。','words':[{'text':'前一句','start':0,'end':1.07}]},
                           {'text':'后一句。','words':[{'text':'后一句','start':1,'end':2}]}])
        self.assertEqual(captions(data,30,True),[{'text':'前一句。后一句。','start_frame':0,'end_frame':60}])
