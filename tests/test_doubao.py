import base64
import copy
import hashlib
import http.client
import io
import json
from pathlib import Path
import tempfile
import unittest
import uuid
import wave
from unittest.mock import Mock, patch

import numpy as np
from probes import doubao, models, worker, run_job, model_download


def response(text='你好'):
    return {'result': {'text': text, 'utterances': [{'text': text, 'words': [
        {'text': '你', 'start_time': 100, 'end_time': 300},
        {'text': '好', 'start_time': 300, 'end_time': 500}]}]}}


class DoubaoTests(unittest.TestCase):
    def test_wav_encoding_and_chunk_coverage(self):
        with wave.open(io.BytesIO(doubao.wav_bytes(np.array([-2, -.5, 0, .5, 2])))) as wav:
            self.assertEqual((wav.getnchannels(), wav.getsampwidth(), wav.getframerate()), (1, 2, 16000))
            self.assertEqual(np.frombuffer(wav.readframes(5), dtype='<i2').tolist(), [-32767,-16384,0,16384,32767])
        audio=np.ones(19 * 16000, dtype=np.float32);audio[8*16000:9*16000]=0
        with patch.object(doubao, 'CHUNK_SAMPLES', 10 * 16000):
            spans=list(doubao.chunk_ranges(audio))
        self.assertEqual(spans[0][0], 0);self.assertEqual(spans[-1][1], len(audio))
        self.assertTrue(all(a[1]==b[0] for a,b in zip(spans,spans[1:])))
        self.assertTrue(all(0 < end-start <= 10*16000 for start,end in spans))
        self.assertTrue(8*16000 <= spans[0][1] <= 9*16000)

    def test_timing_simplification_and_conservation(self):
        value=response('你好。');value['result']['utterances'][0]['text']='你好。'
        rows=doubao.parse_result(value,1,300)
        self.assertEqual(rows[0]['text'],'你好。')
        self.assertEqual(rows[0]['words'][0]['start'],300.1)
        self.assertEqual(rows[0]['words'][-1]['end'],300.5)
        for invalid in (-1, float('nan'), 1500, '100', True):
            broken=copy.deepcopy(value);broken['result']['utterances'][0]['words'][0]['start_time']=invalid
            with self.assertRaises(doubao.CloudError):doubao.parse_result(broken,1)
        for broken in ({}, {'result':{'text':'你好'}}, {'result':{'text':'有漏字','utterances':[]}}, response('不匹配')):
            with self.assertRaises(doubao.CloudError):doubao.parse_result(broken,1)
        self.assertEqual(doubao.parse_result({'result':{'text':'','utterances':[]}},1),[])
        value['result']['utterances'][0]['words'].insert(0,{'text':' ','start_time':-1,'end_time':-1})
        self.assertEqual(doubao.parse_result(value,1,300),rows)

    def test_network_headers_payload_and_no_secret_in_body(self):
        connection=Mock();reply=connection.getresponse.return_value
        reply.status=200;reply.getheader.return_value='20000000';reply.read.return_value=b''
        body={'audio':{'data':base64.b64encode(b'wav').decode()}}
        with patch.object(doubao.http.client,'HTTPSConnection',return_value=connection):
            self.assertEqual(doubao.post(doubao.SUBMIT,body,'fake-test-key','request-test'),('20000000',None))
        args,kwargs=connection.request.call_args
        self.assertEqual(args,('POST',doubao.SUBMIT))
        self.assertEqual(kwargs['headers']['X-Api-Key'],'fake-test-key')
        self.assertEqual(kwargs['headers']['X-Api-Resource-Id'],'volc.seedasr.auc')
        self.assertEqual(kwargs['headers']['X-Api-Sequence'],'-1')
        self.assertEqual(json.loads(kwargs['body']),body)
        self.assertNotIn('fake-test-key',kwargs['body'].decode())
        reply.read.assert_not_called();connection.close.assert_called_once()

    def test_failure_never_retries_or_logs_server_content(self):
        for status, code in ((302,'20000000'),(401,''),(429,''),(500,''),(200,'bad'),(200,'20000000')):
            connection=Mock();reply=connection.getresponse.return_value
            reply.status=status;reply.getheader.return_value=code;reply.read.return_value=b'secret-echo'
            with patch.object(doubao.http.client,'HTTPSConnection',return_value=connection):
                with self.assertRaises(doubao.CloudError) as caught:doubao.post(doubao.QUERY,{},'private-secret','request')
            self.assertNotIn('secret',str(caught.exception))
            self.assertEqual(connection.request.call_count,1);connection.close.assert_called_once()
        connection=Mock();connection.request.side_effect=TimeoutError('private-secret')
        with patch.object(doubao.http.client,'HTTPSConnection',return_value=connection):
            with self.assertRaises(doubao.CloudError) as caught:doubao.post(doubao.SUBMIT,{},'private-secret','request')
        self.assertIn('未自动重试',str(caught.exception));self.assertNotIn('secret',str(caught.exception))
        self.assertTrue(caught.exception.__suppress_context__)

    def test_direct_submit_then_poll_same_id(self):
        send=Mock(side_effect=[('20000000',None),('20000002',None),('20000001',None),('20000000',response())])
        phases=[];sleep=Mock()
        result=doubao.request_chunk(b'wav',{'apiKey':'fake'},send=send,sleep=sleep,emit=phases.append)
        self.assertEqual(result,response())
        self.assertEqual(phases,['uploading','queued','processing']);self.assertEqual(sleep.call_count,2)
        calls=[c.args for c in send.call_args_list]
        self.assertEqual([c[0] for c in calls],[doubao.SUBMIT]+[doubao.QUERY]*3)
        self.assertEqual(len({c[3] for c in calls}),1)
        self.assertEqual(calls[0][1]['audio']['format'],'wav')
        self.assertEqual(base64.b64decode(calls[0][1]['audio']['data']),b'wav')
        self.assertNotIn('url',calls[0][1]['audio'])
        self.assertNotIn('fake',json.dumps(calls[0][1]))
        self.assertTrue(calls[0][1]['request']['show_utterances'])
        self.assertTrue(all(c[1]=={} for c in calls[1:]))
        for fail in (doubao.CloudError('failed'),SystemExit('cancelled')):
            send=Mock(side_effect=[('20000000',None),fail])
            with self.assertRaises(type(fail)):doubao.request_chunk(b'wav',{'apiKey':'fake'},send=send)
            self.assertEqual(send.call_count,2)
        clock=Mock(side_effect=[0,1801]);send=Mock(return_value=('20000000',None))
        with self.assertRaisesRegex(doubao.CloudError,'等待超时'):
            doubao.request_chunk(b'wav',{'apiKey':'fake'},send=send,clock=clock)
        send.assert_called_once()

    def test_direct_upload_bounds_silence_and_submission_failure(self):
        for wav in (b'',b'x'*(doubao.CHUNK_SAMPLES*2+45)):
            send=Mock()
            with self.assertRaises(doubao.CloudError):doubao.request_chunk(wav,{'apiKey':'fake'},send=send)
            send.assert_not_called()
        wav=doubao.wav_bytes(np.zeros(doubao.CHUNK_SAMPLES,dtype=np.float32))
        send=Mock(side_effect=[('20000000',None),('20000003',None)])
        self.assertEqual(doubao.request_chunk(wav,{'apiKey':'fake'},send=send),{'result':{'text':'','utterances':[]}})
        self.assertLess(len(json.dumps(send.call_args_list[0].args[1])),2600000)
        send=Mock(side_effect=doubao.CloudError('failed'))
        with self.assertRaises(doubao.CloudError):doubao.request_chunk(b'wav',{'apiKey':'fake'},send=send)
        send.assert_called_once()

    def test_cloud_gates_and_absence_of_local_download(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            self.assertFalse(doubao.configured(root))
            cloud=next(m for m in models.availability(root) if m['id']==doubao.MODEL_ID)
            self.assertFalse(cloud['installed']);self.assertFalse(cloud['hasFiles'])
            with self.assertRaises(ValueError):models.resolve_model(doubao.MODEL_ID,root)
            with self.assertRaises(ValueError):model_download.install(doubao.MODEL_ID,root)
            status=root/'.subloom/cloud/doubao.json';status.parent.mkdir(parents=True);status.write_text('{"configured":true}')
            self.assertFalse(doubao.configured(root))  # Old metadata must be refreshed by the signed host.
            status.write_text('{"version":2,"configured":true}')
            self.assertFalse(doubao.configured(root))
            status.write_text('{"version":3,"configured":true}')
            self.assertEqual(models.resolve_model(doubao.MODEL_ID,root),(None,None))
            with patch.object(doubao,'credential') as key:
                with self.assertRaises(doubao.CloudError):doubao.recognize(root/'missing',{},consent=False)
                key.assert_not_called()
            with patch.object(run_job,'WORK',root/'jobs'):
                with self.assertRaises(ValueError):run_job.run(root/'missing',None,None,doubao.MODEL_ID)
                self.assertFalse((root/'jobs').exists())

    def test_worker_requires_actual_boolean_consent(self):
        with tempfile.TemporaryDirectory() as tmp:
            d=Path(tmp)/str(uuid.uuid4());d.mkdir()
            xml=d/'input.fcpxml';xml.write_text('<fcpxml><project uid="test"/></fcpxml>')
            value={'requestID':d.name,'projectUID':'test','xmlSHA256':hashlib.sha256(xml.read_bytes()).hexdigest(),'modelID':doubao.MODEL_ID}
            for consent in (None,False,'true',1):
                value['cloudConsent']=consent;(d/'request.json').write_text(json.dumps(value))
                with self.assertRaisesRegex(ValueError,'云端识别'):worker.request_input(d)
                with patch.object(worker,'resolve_model'):
                    with self.assertRaisesRegex(ValueError,'云端识别'):worker.job_command(d)
            value['cloudConsent']=True;(d/'request.json').write_text(json.dumps(value))
            self.assertEqual(worker.request_input(d),xml)
            with patch.object(worker,'resolve_model'):command=worker.job_command(d)
            self.assertIn('--allow-cloud',command)
            self.assertNotIn('api-key',' '.join(command))

    def test_recognizer_preserves_global_time_and_progress(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp).resolve();pcm=root/'.subloom/verification/audio.f32le';pcm.parent.mkdir(parents=True)
            np.full(32000,.25,dtype='<f4').tofile(pcm)
            send=Mock(return_value=response());events=[]
            with patch.object(doubao,'ROOT',root),patch.object(doubao,'CHUNK_SAMPLES',16000):
                result=doubao.recognize(pcm,{'sampleCount':32000},consent=True,key='fake',send=send,emit=events.append)
            self.assertEqual(send.call_count,2)
            self.assertEqual(result['results'][1]['words'][0]['start'],1.1)
            self.assertEqual([v['progress'] for v in events],[.5,1])
            self.assertEqual(result['pcm_sha256'],hashlib.sha256(pcm.read_bytes()).hexdigest())
            self.assertNotIn('fake',json.dumps(result))

    def test_cloud_job_reuses_editorial_vocabulary_and_exports_titles(self):
        # Real snapshot parsing, cloud adapter and finalization; fake audio + HTTP only.
        import xml.etree.ElementTree as ET
        from contextlib import redirect_stdout
        from tests.test_project import basic
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp).resolve();xml=root/'input.fcpxml'
            tree,_,_,_=basic();xml.write_bytes(ET.tostring(tree))
            def render(xml,directory,*args):
                count=run_job.inspect(xml)['sampleCount'];pcm=directory/'timeline.f32le'
                np.full(count,.25,dtype='<f4').tofile(pcm)
                return {'silent':False,'pcmFile':pcm.name}
            words=[{'text':'iPhone','start_time':100,'end_time':400},
                   {'text':'十八','start_time':400,'end_time':700},
                   {'text':'pro','start_time':700,'end_time':1000}]
            result={'result':{'text':'iPhone十八pro','utterances':[{'text':'iPhone十八pro','words':words}]}}
            with patch.object(run_job,'WORK',root/'.subloom/verification/jobs'),patch.object(doubao,'ROOT',root),patch.object(run_job,'render',side_effect=render),patch.object(doubao,'credential',return_value='fake'),patch.object(doubao,'request_chunk',return_value=result) as send,redirect_stdout(io.StringIO()):
                job=run_job.run(xml,None,None,doubao.MODEL_ID,vocabulary=['iPhone 18 Pro'],allow_cloud=True)
            state=json.loads((job/'status.json').read_text());manifest=json.loads((job/'captions.json').read_text())
            self.assertEqual(state['status'],'ready');self.assertEqual(state['device'],'cloud')
            self.assertEqual(''.join(c['text'] for c in manifest['captions']),'iPhone 18 Pro')
            self.assertEqual(len(list(job.glob('TitleProbe-*.fcpxml'))),3)
            send.assert_called_once()
            for title in job.glob('TitleProbe-*.fcpxml'):ET.fromstring(title.read_bytes())

    def test_key_helper_uses_only_private_pipe_and_sanitizes_errors(self):
        with patch.dict('os.environ',{'SUBPOP_CONTAINER_EXECUTABLE':'/usr/bin/true'}):
            with patch.object(doubao.subprocess,'run',return_value=Mock(returncode=0,stdout=json.dumps({'apiKey':'fake-test-key'}).encode())) as run:
                self.assertEqual(doubao.credential()['apiKey'],'fake-test-key')
            self.assertEqual(run.call_args.args[0],['/usr/bin/true','--doubao-credentials'])
            self.assertNotIn('env',run.call_args.kwargs)
            with patch.object(doubao.subprocess,'run',side_effect=OSError('do-not-log')):
                with self.assertRaises(doubao.CloudError) as caught:doubao.credential()
            self.assertNotIn('do-not-log',str(caught.exception))


if __name__=='__main__':unittest.main()
