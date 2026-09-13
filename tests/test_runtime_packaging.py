import tempfile
import unittest
from pathlib import Path
from scripts.slim_runtime import slim

class RuntimePackagingTests(unittest.TestCase):
    def test_pruning_keeps_runtime_helpers_and_licenses(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)/'Runtime'
            site=root/'.venv/lib/python3.12/site-packages'
            for name in ('torch/testing/__init__.py','torch/bin/torch_shm_manager','torch/bin/protoc','torch/include/header.h','joblib/test/data/fixture.gz',
                         'gradio/demo.py','gradio-1.dist-info/licenses/LICENSE','numpy/testing/__init__.py'):
                path=site/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('fixture')
            report=slim(root)
            self.assertTrue((site/'torch/testing/__init__.py').exists())
            self.assertTrue((site/'torch/bin/torch_shm_manager').exists())
            self.assertFalse((site/'torch/bin/protoc').exists())
            self.assertTrue((site/'numpy/testing/__init__.py').exists())
            self.assertTrue((site/'gradio-1.dist-info/licenses/LICENSE').exists())
            self.assertFalse((site/'joblib/test').exists())
            self.assertFalse((site/'gradio').exists())
            self.assertFalse((site/'torch/include').exists())
            self.assertLess(report['afterBytes'],report['beforeBytes'])

    def test_refuses_development_workspace(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)/'SubPop'
            (root/'.venv/lib/python3.12/site-packages').mkdir(parents=True)
            with self.assertRaises(ValueError):slim(root)
