import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import uuid
from fractions import Fraction

from probes.editorial_rules import Word
from probes.reference_script import ReferenceScript, validate, digest, refine_rows
from probes.editorial import optimized_captions
from probes.editorial import measured_words


def measured(text):
    return [Word(c, i*.1, (i+1)*.1) for i,c in enumerate(text)]


class ReferenceTests(unittest.TestCase):
    def apply(self, text, script):
        ref=ReferenceScript(script)
        result=ref.apply(measured(text))
        return ''.join(w.text for w in result),ref.report,result

    def test_anchored_homophone_and_equivalent_brand_spelling(self):
        text='今年iPhone十八pro在影响上的提升非常明显'
        result,report,words=self.apply(text,'今年 iPhone 18 Pro 在影像上的提升非常明显。')
        self.assertEqual(result,'今年iPhone 18 Pro在影像上的提升非常明显')
        self.assertEqual(report['correctionCount'],2)
        self.assertEqual(words[0].start,0);self.assertEqual(words[-1].end,len(text)*.1)
        self.assertTrue(all(a.end<=b.start for a,b in zip(words,words[1:])))

    def test_different_numbers_negation_and_adlibs_are_preserved(self):
        text='我觉得这次升级不值得而且价格是7999元顺便聊个题外话'
        result,report,_=self.apply(text,'我觉得这次升级值得，而且价格是8999元。脚本中另外还有一段没读。')
        self.assertEqual(result,text);self.assertEqual(report['correctionCount'],0)
        for a,b in [('没有','有'),('不','很'),('无','五'),('十七','十八'),('16.5','165'),('0018','18')]:
            text=f'我们今天实际使用的是{a}这个版本感觉相当不错'
            result,_,_=self.apply(text,f'我们今天实际使用的是{b}这个版本感觉相当不错')
            self.assertIn(a,result);self.assertEqual(result,text)

    def test_unrelated_and_too_short_context_remain_untouched(self):
        for text,script in [('今天我们出门拍摄手机视频','这是完全不同的汽车脚本'),('这个影响','这个影像'),('影响上提升','影像上提升')]:
            self.assertEqual(self.apply(text,script)[0],text)

    def test_script_only_passages_never_get_inserted(self):
        text='今天我先聊聊这款相机顺便说个题外话这个镜头表现非常清楚'
        result,_,_=self.apply(text,'脚本开头还有很多内容。今天我先聊聊这款相机。这个镜头表现非常清楚。后面还有其他内容。')
        self.assertEqual(result,text)

    def test_reordered_passages_and_repeated_takes(self):
        script='首先我们来谈谈影响上的变化非常明显。然后我们再看看续航实际使用感觉很好。'
        for text in ['然后我们再看看续航实际使用感觉很好','首先我们来谈谈影像上的变化非常明显']*2:
            result,_,_=self.apply(text,script)
            self.assertEqual(result,text.replace('影像','影响'))

    def test_equally_plausible_conflicting_passages_do_not_guess(self):
        text='我们今天讨论的是影象方面带来的改变非常明显'
        script='我们今天讨论的是影像方面带来的改变非常明显。中间还有一些其他的内容。我们今天讨论的是影响方面带来的改变非常明显。'
        result,_,_=self.apply(text,script)
        self.assertEqual(result,text)

    def test_script_boundaries_use_measured_words_only(self):
        text='这个效果我觉得还不错然后我们来看续航'
        script='这个效果我觉得还不错。然后我们来看续航。'
        result,report,words=self.apply(text,script)
        self.assertIn('不错。然后',result);self.assertEqual(report['boundaryCount'],1)
        self.assertEqual([(w.start,w.end) for w in words],[(w.start,w.end) for w in measured(text)])
        # A coarse token cannot be split into invented character times.
        self.assertEqual(ReferenceScript(script).apply([Word(text,4,9)]),[Word(text,4,9)])

    def test_spelling_never_joins_a_pause_or_sentence_separator(self):
        script='今年iPhone 18 Pro在影像上的提升非常明显'
        words=[Word('今年iPhone',0,1),Word('十八pro在影像上的提升非常明显',2,5)]
        self.assertEqual(''.join(w.text for w in ReferenceScript(script).apply(words)),'今年iPhone十八pro在影像上的提升非常明显')
        text='今年iPhone，十八pro在影像上的提升非常明显'
        self.assertEqual(self.apply(text,script)[0],text)

    def test_long_windows_do_not_apply_overlapping_edits_twice(self):
        text='我们现在开始讨论这款产品的实际使用情况以及生活当中的一些具体感受'*4+'今年iPhone十八pro在影响上的提升非常明显'+'然后再来一起看看续航表现到底如何'*8
        script=text.replace('iPhone十八pro','iPhone 18 Pro').replace('影响','影像')
        result,_,_=self.apply(text,script)
        self.assertEqual(result,script)
        self.assertEqual(self.apply(result,script)[0],script)

    def test_existing_cues_keep_all_timing_and_manual_text(self):
        rows=[dict(text='今年iPhone十八pro在影响上的提升非常明显',start_frame=12,end_frame=100,manual=True),dict(text='临时补充的内容都要保留',start_frame=120,end_frame=180)]
        output,report=refine_rows(rows,'今年 iPhone 18 Pro 在影像上的提升非常明显。')
        self.assertEqual(output[0]['text'],'今年iPhone 18 Pro在影像上的提升非常明显')
        self.assertEqual(output[1],rows[1]);self.assertEqual(report['changes'][0]['captionIndex'],0)
        self.assertEqual([{**r,'text':''} for r in rows],[{**r,'text':''} for r in output])
        self.assertIn('影响',rows[0]['text'])

    def test_empty_script_is_noop_and_input_is_bounded(self):
        words=measured('这是一句正常字幕')
        self.assertEqual(ReferenceScript('').apply(words),words)
        self.assertEqual(validate('  一行\n第二行\t '),'一行\n第二行')
        for text in (None,{},'x'*20001,'a\0b','😀'*10001):
            with self.assertRaises((ValueError,TypeError)):validate(text)
        self.assertEqual(digest(''), '')
        self.assertEqual(digest('脚本'),hashlib.sha256('脚本'.encode()).hexdigest())

    def test_explicit_dictionary_spelling_wins_over_script(self):
        text='我们今天来介绍这款芯片带来的变化非常明显'
        rows,report=refine_rows([dict(text=text,start_frame=0,end_frame=90)],text.replace('芯片','新片'),['芯片'])
        self.assertEqual(rows[0]['text'],text);self.assertEqual(report['correctionCount'],0)

    def test_vocabulary_remains_authoritative_and_new_cues_use_script_breaks(self):
        text='今年iPhone十八pro在影响上的提升非常明显然后我们来看续航'
        data={'snapshot':{'duration':'8'},'results':[{'text':text,'words':[dict(text=w.text,start=w.start,end=w.end) for w in measured(text)]}]}
        report={};rows=optimized_captions(data,30,['iPhone 18 PRO'],reference_script='今年 iPhone 18 Pro 在影像上的提升非常明显。然后我们来看续航。',reference_report=report)
        self.assertIn('iPhone 18 PRO',''.join(r['text'] for r in rows))
        self.assertNotIn('影响',''.join(r['text'] for r in rows))
        self.assertGreater(report['boundaryCount'],0)
        self.assertTrue(all(r['end_frame']>r['start_frame'] for r in rows))


class ReferenceIntegrationTests(unittest.TestCase):
    def test_final_pcm_sample_rounding_is_clipped_only_to_known_audio_extent(self):
        data={'snapshot':{'duration':'2683681/10000','sampleCount':4293890},'results':[dict(text='字幕',words=[dict(text='字幕',start=268,end=268.368125)])]}
        self.assertEqual(measured_words(data)[0].end,268.3681)
        data['results'][0]['words'][0]['end']=268.369
        with self.assertRaisesRegex(ValueError,'Invalid or overlapping'):measured_words(data)
        data['results'][0]['words'][0]['end']=268.368125;data['snapshot'].pop('sampleCount')
        with self.assertRaisesRegex(ValueError,'Invalid or overlapping'):measured_words(data)

    def test_finalize_produces_reference_result_and_verified_originals(self):
        from probes.run_job import finalize
        text='这个效果我觉得还不错然后我们来看续航'
        snapshot={'duration':'8','frameDuration':'1/30','name':'Test','uid':'TEST'}
        result={'snapshot':snapshot,'pcm_sha256':'pcm','device':'cpu','results':[dict(text=text,words=[dict(text=w.text,start=w.start,end=w.end) for w in measured(text)])]}
        state={'projectUID':'TEST','modelID':'qwen3-asr-0.6b','referenceScript':'这个效果我觉得还不错。然后我们来看续航。'}
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);finalize(root,state,result,[])
            manifest=json.loads((root/'captions.json').read_text());status=json.loads((root/'status.json').read_text())
            self.assertEqual(manifest['referenceSHA256'],digest(state['referenceScript']))
            self.assertEqual(manifest['unreferencedCaptions'],optimized_captions(result,30))
            for version in ('1.12','1.13','1.14'):
                name=f'TitleOriginal-{version}.fcpxml'
                self.assertEqual(hashlib.sha256((root/name).read_bytes()).hexdigest(),status['outputs'][name])

    def test_text_only_worker_never_requires_a_model_or_media(self):
        from probes.worker import job_command
        from probes.reference_job import read_request,run
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/str(uuid.uuid4());root.mkdir()
            rows=[dict(text='今年手机在影响上的提升非常明显',start_frame=10,end_frame=100)]
            request=dict(kind='reference',requestID=root.name,projectUID='TEST',referenceScript='今年手机在影像上的提升非常明显。',captions=rows)
            (root/'request.json').write_text(json.dumps(request))
            with patch('probes.worker.resolve_model',side_effect=AssertionError('must not resolve model')):
                self.assertIn('probes.reference_job',job_command(root))
                run(root)
            response=json.loads((root/'response.json').read_text())
            self.assertEqual(response['status'],'ready');self.assertEqual(response['captions'][0]['text'],'今年手机在影像上的提升非常明显')
            self.assertEqual(response['referenceSHA256'],digest(request['referenceScript']))
            request['requestID']='wrong';(root/'request.json').write_text(json.dumps(request))
            with self.assertRaises(ValueError):read_request(root)

    def test_recognition_request_accepts_long_script_and_rejects_bad_script(self):
        from probes.worker import request_input,UID
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/str(uuid.uuid4());root.mkdir();xml=root/'input.fcpxml'
            xml.write_text(f'<fcpxml><project uid="{UID}"/></fcpxml>')
            request=dict(requestID=root.name,projectUID=UID,xmlSHA256=hashlib.sha256(xml.read_bytes()).hexdigest(),referenceScript='中文脚本内容'*2000)
            (root/'request.json').write_text(json.dumps(request))
            self.assertEqual(request_input(root),xml)
            request['referenceScript']='x'*20001;(root/'request.json').write_text(json.dumps(request))
            with self.assertRaises(ValueError):request_input(root)
