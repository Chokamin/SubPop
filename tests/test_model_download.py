import hashlib
import io
from pathlib import Path
import tempfile
import unittest
from probes.model_download import transfer,Cancelled

class Response(io.BytesIO):
    def __init__(self,data,status=200,headers=None):super().__init__(data);self.status=status;self.headers=headers or {}

class DownloadTests(unittest.TestCase):
    def test_partial_download_resumes_and_publishes_only_verified_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'weights';p.with_suffix('.part').write_bytes(b'abc')
            seen=[]
            def open_(req,timeout):
                self.assertEqual(req.get_header('Range'),'bytes=3-');return Response(b'def',206,{'Content-Range':'bytes 3-5/6'})
            transfer('https://example.test/file',p,6,hashlib.sha256(b'abcdef').hexdigest(),lambda:False,lambda n,s:seen.append(n),open_)
            self.assertEqual(p.read_bytes(),b'abcdef');self.assertFalse(p.with_suffix('.part').exists());self.assertIn(6,seen)
    def test_server_ignoring_range_restarts_cleanly(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'weights';p.with_suffix('.part').write_bytes(b'abc')
            transfer('https://example.test/file',p,6,hashlib.sha256(b'abcdef').hexdigest(),lambda:False,lambda *a:None,lambda *a,**kw:Response(b'abcdef'))
            self.assertEqual(p.read_bytes(),b'abcdef')
    def test_bad_hash_cannot_publish_or_leave_corrupt_installed_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'weights';p.write_bytes(b'bad')
            with self.assertRaises(ValueError):transfer('https://example.test/file',p,3,hashlib.sha256(b'yes').hexdigest(),lambda:False,lambda *a:None,lambda *a,**kw:Response(b'bad'))
            self.assertFalse(p.exists());self.assertFalse(p.with_suffix('.part').exists())
    def test_cancel_keeps_partial_without_publishing(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'weights';p.with_suffix('.part').write_bytes(b'ab')
            with self.assertRaises(Cancelled):transfer('https://example.test/file',p,6,'unused',lambda:True,lambda *a:None)
            self.assertFalse(p.exists());self.assertEqual(p.with_suffix('.part').read_bytes(),b'ab')
    def test_linked_destination_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'weights';target=Path(tmp)/'other';target.write_bytes(b'keep');p.symlink_to(target)
            with self.assertRaises(ValueError):transfer('https://example.test/file',p,4,'unused',lambda:False,lambda *a:None)
            self.assertEqual(target.read_bytes(),b'keep')

    def test_first_install_includes_shared_aligner_and_pinned_hashes(self):
        from unittest.mock import patch
        from probes import model_download as download
        def spec(name,weight):
            files={'config.json':b'{}','model.safetensors':weight}
            return {'id':'test','directory':name,'repository':'test/'+name,'revision':'pinned','files':{k:len(v) for k,v in files.items()},'sha256':{k:hashlib.sha256(v).hexdigest() for k,v in files.items()}}
        a=spec('asr',b'ASR');b=spec('aligner',b'ALIGN');urls=[];states=[]
        def opener(request,timeout):
            urls.append(request.full_url)
            return Response(b'{}' if request.full_url.endswith('config.json') else (b'ALIGN' if '/aligner/' in request.full_url else b'ASR'))
        with tempfile.TemporaryDirectory() as tmp,patch.object(download,'model_spec',return_value=a),patch.object(download,'CATALOG',{'aligner':b}):
            root=Path(tmp);download.install('test',root,emit=states.append,opener=opener)
            self.assertEqual((root/'.subloom/models/asr/model.safetensors').read_bytes(),b'ASR')
            self.assertEqual((root/'.subloom/models/aligner/model.safetensors').read_bytes(),b'ALIGN')
            self.assertTrue(all('/resolve/pinned/' in u for u in urls));self.assertEqual(states[-1]['progress'],1)
    def test_removal_preserves_shared_aligner_and_unrelated_data(self):
        import json
        from probes.model_download import execute
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);base=root/'.subloom/models';(base/'asr').mkdir(parents=True);(base/'asr/weights').write_bytes(b'asr')
            (base/'aligner').mkdir();(base/'aligner/weights').write_bytes(b'aligner')
            d=root/'request';d.mkdir();(d/'request.json').write_text(json.dumps({'modelID':'qwen3-asr-0.6b','operation':'remove'}))
            execute(d,root);self.assertFalse((base/'asr').exists());self.assertEqual((base/'aligner/weights').read_bytes(),b'aligner')
            self.assertEqual(json.loads((d/'response.json').read_text())['status'],'ready')

    def test_mirror_failure_falls_back_without_changing_digest(self):
        from unittest.mock import patch
        from probes import model_download as download
        from probes.download_sources import sources
        spec={'id':'test','engine':'sensevoice','directory':'test','repository':'owner/model','revision':'pinned','files':{'config.json':2},'sha256':{'config.json':hashlib.sha256(b'{}').hexdigest()}}
        urls=[]
        def opener(req,timeout):
            urls.append(req.full_url)
            if 'hf-mirror.com' in req.full_url:raise OSError('unavailable')
            return Response(b'{}')
        with tempfile.TemporaryDirectory() as tmp,patch.object(download,'model_spec',return_value=spec):
            download.install('test',Path(tmp),opener=opener)
            self.assertEqual((Path(tmp)/'.subloom/models/test/config.json').read_bytes(),b'{}')
        self.assertEqual(len(urls),2)
        self.assertIn('hf-mirror.com',urls[0]);self.assertIn('huggingface.co',urls[1])
        self.assertEqual(len(sources('official')),1)
        with self.assertRaises(ValueError):sources('https://untrusted.example')
