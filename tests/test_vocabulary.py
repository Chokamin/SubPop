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

class VocabularySpellingTests(unittest.TestCase):
    def normalize(self,text,terms):
        from probes.vocabulary import canonical_words
        from probes.editorial_rules import Word
        return canonical_words([Word(c,i*.1,(i+1)*.1) for i,c in enumerate(text)],terms)

    def test_equivalent_model_spelling_keeps_measured_span(self):
        rows=self.normalize('今年iPhone十八pro提升了',['iPhone 18 Pro'])
        self.assertEqual(''.join(w.text for w in rows),'今年iPhone 18 Pro提升了')
        term=next(w for w in rows if w.text=='iPhone 18 Pro')
        self.assertAlmostEqual(term.start,.2);self.assertAlmostEqual(term.end,1.3)

    def test_no_dictionary_no_fuzzy_numbers_or_partial_brand_replacement(self):
        for text,terms in [('iPhone十八pro',[]),('iPhone十七pro',['iPhone 18 Pro']),('miniPhone十八pro',['iPhone 18 Pro']),('普通的十八个',['iPhone 18 Pro'])]:
            self.assertEqual(''.join(w.text for w in self.normalize(text,terms)),text)

    def test_repeated_and_overlapping_terms(self):
        from probes.vocabulary import canonical_words
        from probes.editorial_rules import Word
        words=[Word('iPhone十八pro和IPHONE18PRO',1,3)]
        rows=canonical_words(words,['iPhone','iPhone 18 Pro'])
        self.assertEqual(rows,[Word('iPhone 18 Pro和iPhone 18 Pro',1,3)])

    def test_does_not_join_across_pause_or_punctuation(self):
        from probes.vocabulary import canonical_words
        from probes.editorial_rules import Word
        words=[Word('iPhone',0,1),Word('十八pro',2,3)]
        self.assertEqual(canonical_words(words,['iPhone 18 Pro']),words)
        self.assertEqual(''.join(w.text for w in self.normalize('iPhone，十八pro',['iPhone 18 Pro'])),'iPhone，十八pro')

    def test_final_subtitles_use_dictionary_spelling(self):
        from probes.editorial import optimized_captions
        text='今年iPhone十八pro提升了'
        data={'snapshot':{'duration':'4'},'results':[{'text':text,'words':[dict(text=c,start=i*.1,end=(i+1)*.1) for i,c in enumerate(text)]}]}
        rows=optimized_captions(data,30,['iPhone 18 Pro'])
        self.assertIn('iPhone 18 Pro',''.join(r['text'] for r in rows))
