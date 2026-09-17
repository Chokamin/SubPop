import importlib.util
import unittest
import json
from pathlib import Path
from fractions import Fraction
from probes.text_units import clean_generated_text, display_length
from probes.editorial import optimized_captions
from probes.editorial_rules import Word, make_captions, bridge_brief_gaps

class CleanupTests(unittest.TestCase):
    def test_sentence_punctuation_removed_but_values_survive(self):
        self.assertEqual(clean_generated_text('尺寸1/1.1英寸，延迟0.1毫秒；范围12-13档，时间6:44，亮度50%，温度-5度。'),
                         '尺寸1/1.1英寸延迟0.1毫秒范围12-13档时间6:44亮度50%温度-5度')
        self.assertEqual(clean_generated_text('售价2,000元。'), '售价2,000元')
        self.assertEqual(clean_generated_text('“USB-C、C++、C#、v1.2。”'), 'USB-C C++ C# v1.2')
        self.assertEqual(clean_generated_text("Ready,go! Don't stop."), "Ready go Don't stop")
        self.assertEqual(clean_generated_text('……'), '')

    def test_mixed_display_width(self):
        self.assertEqual(display_length('字幕ABC123'),5)

@unittest.skipUnless(importlib.util.find_spec('jieba'),'Run with SubPop .venv for lexical integration')
class EditorialTests(unittest.TestCase):
    def test_number_units_and_vocabulary_survive_length_boundary(self):
        words=[Word('我们测得',0,.8),Word('0.1',.8,1),Word('毫秒',1.1,1.3),Word('延迟',1.3,1.6)]
        self.assertEqual([r.text for r in make_captions(words,max_chars=6)],['我们测得','0.1毫秒延迟'])
        name='星河映像实验室';text='欢迎来到'+name+'参观'
        words=[Word(c,i*.1,(i+1)*.1) for i,c in enumerate(text)]
        protected=make_captions(words,max_chars=6,protected_terms=[name])
        self.assertTrue(any(name in r.text for r in protected))
        self.assertFalse(any(name in r.text for r in make_captions(words,max_chars=6)))

    def test_short_gaps_bridge_long_pauses_remain(self):
        rows=bridge_brief_gaps(make_captions([Word('你好。',0,1),Word('世界。',1.15,2),Word('再见。',3,4)]))
        self.assertEqual(rows[0].end,1.15);self.assertEqual(rows[1].end,2);self.assertEqual(rows[-1].end,4)

    def test_adapter_punctuation_internal_token_and_frames(self):
        data={'snapshot':{'duration':'5','relative_start':'0','project':'P'},'results':[{'text':'你好。世界。USB-C，3.5%。','words':[
            {'text':'你好世界','start':0,'end':1.01},{'text':'USB-C','start':1.02,'end':2},{'text':'3.5%','start':2.1,'end':3}]}]}
        for fps in (30,Fraction(30000,1001)):
            rows=optimized_captions(data,fps)
            self.assertEqual(''.join(r['text'] for r in rows).replace(' ',''),'你好世界USB-C3.5%')
            self.assertTrue(all(a['end_frame']<=b['start_frame'] for a,b in zip(rows,rows[1:])))

    def test_uncertain_zero_word_preserves_text_and_requests_review(self):
        data={'snapshot':{'duration':'5','relative_start':'0','project':'P'},'results':[{'text':'这是结果。','words':[
            {'text':'这是结','start':0,'end':1},{'text':'果','start':3,'end':3}]}]}
        review=[];rows=optimized_captions(data,30,warnings=review)
        self.assertEqual(''.join(r['text'] for r in rows),'这是结果');self.assertEqual(len(review),1)

    def test_invalid_alignment_is_not_silently_cleaned(self):
        data={'snapshot':{'duration':'5','relative_start':'0','project':'P'},'results':[{'text':'不相符。','words':[{'text':'错字','start':0,'end':1}]}]}
        with self.assertRaises(ValueError):optimized_captions(data,30)

    def test_short_video_semantic_regressions_at_measured_frames(self):
        data=json.loads((Path(__file__).parent/'fixtures/editorial-short-video.json').read_text())
        for fps in (30,Fraction(30000,1001)):
            rows=optimized_captions(data,fps)
            self.assertEqual([r['text'] for r in rows],[
                '今年iPhone十八Pro系列在影像上的提升','其实有很多',
                '但不知道为什么','发布会上只讲了一点点',
                '那这支视频我将结合','最近这段时间的使用体验和研究成果'])
            self.assertEqual(rows[1]['start_frame'],round(Fraction('2.32')*fps))
            self.assertEqual(rows[3]['start_frame'],round(Fraction('4.16')*fps))
            self.assertTrue(all(a['end_frame']<=b['start_frame'] for a,b in zip(rows,rows[1:])))

    def test_short_questions_stay_intact_and_long_silence_wins(self):
        text='你知道为什么吗'
        words=[Word(c,i*.2,(i+1)*.2) for i,c in enumerate(text)]
        self.assertEqual([r.text for r in make_captions(words)],[text])
        words=[Word('使用体验',0,1),Word('和',2,2.2),Word('研究成果',2.2,3)]
        self.assertEqual([r.text for r in make_captions(words)],['使用体验','和研究成果'])

    def test_other_lead_ins_and_parallel_terms(self):
        text='我们测量了它的续航能力不过结果还不错'
        words=[Word(c,i*.15,(i+1)*.15) for i,c in enumerate(text)]
        rows=make_captions(words,max_chars=14)
        self.assertFalse(any(r.text.endswith('不过') for r in rows))
        self.assertTrue(any(r.text.startswith('不过') for r in rows))
        text='接下来我们一起看看拍摄效果和使用感受'
        words=[Word(c,i*.15,(i+1)*.15) for i,c in enumerate(text)]
        rows=make_captions(words,max_chars=14)
        self.assertEqual(''.join(r.text for r in rows),text)
        self.assertFalse(any(r.text.startswith('和') for r in rows))
