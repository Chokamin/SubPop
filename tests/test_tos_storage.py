import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

from probes import tos_storage as storage

CONFIG={'region':'cn-beijing','bucket':'test-bucket','tosAccessKey':'secret-ak','tosSecretKey':'secret-sk'}


class TOSStorageTests(unittest.TestCase):
    def factory(self):
        api=Mock();api.put_object.return_value=SimpleNamespace(version_id='version-test')
        api.head_object.return_value=SimpleNamespace(version_id='version-test')
        api.pre_signed_url.side_effect=lambda method,bucket,key,expires: SimpleNamespace(
            signed_url=f'https://{bucket}.tos-cn-beijing.volces.com/{key}?secret-signature')
        return api,Mock(return_value=api)

    def test_upload_private_presign_one_hour_delete_exact_version(self):
        import tos
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);api,factory=self.factory()
            with storage.TemporaryAudio(CONFIG,b'wav',root=root,factory=factory) as url:
                self.assertIn('?secret-signature',url)
                paths=list(storage.receipts(root).glob('*.json'));self.assertEqual(len(paths),1)
                raw=paths[0].read_text();self.assertNotIn('secret',raw)
                self.assertEqual(paths[0].stat().st_mode & 0o777,0o600)
                self.assertEqual(json.loads(raw)['versionID'],'version-test')
            self.assertEqual(storage.pending_count(root),0)
            args=api.put_object.call_args.kwargs
            self.assertEqual(args['acl'],tos.ACLType.ACL_Private);self.assertTrue(args['forbid_overwrite'])
            self.assertEqual(args['content'],b'wav');self.assertEqual(args['content_length'],3)
            self.assertEqual(api.pre_signed_url.call_args.kwargs['expires'],3600)
            self.assertEqual(api.delete_object.call_args.kwargs,{'version_id':'version-test','skip_trash':True})
            api.head_object.assert_not_called()

    def test_cleanup_on_cancel_and_processing_error(self):
        for failure in (SystemExit('cancelled'),ValueError('processing failure')):
            with tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);api,factory=self.factory()
                with self.assertRaises(type(failure)):
                    with storage.TemporaryAudio(CONFIG,b'wav',root=root,factory=factory):raise failure
                api.delete_object.assert_called_once();self.assertEqual(storage.pending_count(root),0)

    def test_failed_delete_journal_retried_and_no_new_upload_until_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);api,factory=self.factory();api.delete_object.side_effect=OSError('secret-network')
            with storage.TemporaryAudio(CONFIG,b'wav',root=root,factory=factory):pass
            self.assertEqual(storage.pending_count(root),1)
            with self.assertRaises(storage.StorageError) as caught:
                with storage.TemporaryAudio(CONFIG,b'wav',root=root,factory=factory):pass
            self.assertNotIn('secret',str(caught.exception));self.assertEqual(api.put_object.call_count,1)
            with self.assertRaises(storage.StorageError) as caught:
                storage.cleanup_pending(CONFIG,root,Mock(side_effect=ValueError('secret-config')))
            self.assertNotIn('secret',str(caught.exception))
            api.delete_object.side_effect=None
            storage.cleanup_pending(CONFIG,root,factory)
            self.assertEqual(storage.pending_count(root),0)

    def test_uncertain_upload_and_version_lookup(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);api,factory=self.factory();api.put_object.side_effect=TimeoutError('secret-upload')
            with self.assertRaises(storage.StorageError) as caught:
                with storage.TemporaryAudio(CONFIG,b'wav',root=root,factory=factory):pass
            self.assertNotIn('secret',str(caught.exception));self.assertTrue(caught.exception.__suppress_context__)
            self.assertEqual(storage.pending_count(root),1)
            with self.assertRaises(storage.StorageError):storage.cleanup_pending(CONFIG,root,factory)
            path=next(storage.receipts(root).glob('*.json'));value=json.loads(path.read_text());value['created']=time.time()-300
            path.write_text(json.dumps(value))
            storage.cleanup_pending(CONFIG,root,factory)
            api.head_object.assert_called();self.assertEqual(storage.pending_count(root),0)

    def test_never_deletes_foreign_keys_or_other_buckets(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);api,factory=self.factory();api.delete_object.side_effect=OSError()
            with storage.TemporaryAudio(CONFIG,b'wav',root=root,factory=factory):pass
            path=next(storage.receipts(root).glob('*.json'));value=json.loads(path.read_text())
            api.reset_mock();value['bucket']='another-bucket';path.write_text(json.dumps(value))
            storage.cleanup_pending(CONFIG,root,factory);api.delete_object.assert_not_called()
            value['bucket']=CONFIG['bucket'];value['key']='important-video.mov';path.write_text(json.dumps(value))
            with self.assertRaises(storage.StorageError):storage.cleanup_pending(CONFIG,root,factory)
            api.delete_object.assert_not_called()

    def test_validate_and_presign_host_restriction(self):
        for field,value in (('region','attacker.test'),('bucket','https://public'),('tosSecretKey','bad\nkey')):
            with self.assertRaises(storage.StorageError):storage.validate({**CONFIG,field:value})
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);api,factory=self.factory()
            api.pre_signed_url.side_effect=None;api.pre_signed_url.return_value=SimpleNamespace(signed_url='https://attacker.test/file')
            with self.assertRaises(storage.StorageError):
                with storage.TemporaryAudio(CONFIG,b'wav',root=root,factory=factory):pass
            api.delete_object.assert_called_once();self.assertEqual(storage.pending_count(root),0)

    def test_sdk_tls_fixed_endpoint_no_retries(self):
        import tos
        import certifi
        with patch.object(tos,'TosClientV2') as ctor:
            storage.client(CONFIG)
        args=ctor.call_args.kwargs
        self.assertEqual(args['endpoint'],'https://tos-cn-beijing.volces.com')
        self.assertTrue(args['enable_verify_ssl']);self.assertEqual(args['ca_crt'],certifi.where())
        self.assertEqual(args['max_retry_count'],0);self.assertEqual(args['follow_redirect_times'],0)

if __name__=='__main__':unittest.main()
