import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import uuid
from probes.worker import request_input,valid_id,publish_result,UID

class WorkerTests(unittest.TestCase):
    def test_only_canonical_request_ids(self):
        self.assertTrue(valid_id(str(uuid.uuid4())))
        for value in ('../outside','123',None,str(uuid.uuid4()).upper()):self.assertFalse(valid_id(value))

    def test_request_checksum_identity_and_symlink_guard(self):
        with tempfile.TemporaryDirectory() as temp:
            d=Path(temp)/str(uuid.uuid4());d.mkdir();xml=d/'input.fcpxml';xml.write_text('<fcpxml/>')
            manifest={'requestID':d.name,'projectUID':UID,'xmlSHA256':hashlib.sha256(xml.read_bytes()).hexdigest()}
            (d/'request.json').write_text(json.dumps(manifest))
            self.assertEqual(request_input(d),xml)
            xml.write_text('<changed/>')
            with self.assertRaises(ValueError):request_input(d)
            xml.unlink();xml.symlink_to(Path(temp)/'elsewhere')
            with self.assertRaises(ValueError):request_input(d)

    def test_result_cannot_read_arbitrary_directory(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ValueError):publish_result(Path(temp),Path(temp))
