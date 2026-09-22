import base64
import fcntl
import importlib.util
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

from probes.update_lock import TaskLease

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from prepare_update_feed import feed_xml, SPARKLE


class OnlineUpdatesTests(unittest.TestCase):
    def test_job_and_installer_exclude_each_other_and_release_after_exit(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'update.lock'
            job = TaskLease(path)
            self.assertTrue(job.acquire())
            # A separate process, as in the application/worker boundary.
            script = '''import fcntl,os,sys
f=os.open(sys.argv[1],os.O_RDWR)
try: fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError: sys.exit(7)
'''
            self.assertEqual(subprocess.run([sys.executable, '-c', script, str(path)]).returncode, 7)
            job.release()
            self.assertEqual(subprocess.run([sys.executable, '-c', script, str(path)]).returncode, 0)
            updater = os.open(path, os.O_RDWR)
            fcntl.flock(updater, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertFalse(job.acquire())
            os.close(updater)  # also covers updater crash/cancel releasing kernel lease
            self.assertTrue(job.acquire())
            job.close()

    def test_lock_rejects_symlink(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder)/'target';target.write_text('preserve')
            link = Path(folder)/'update.lock';link.symlink_to(target)
            with self.assertRaises(OSError):TaskLease(link)
            self.assertEqual(target.read_text(), 'preserve')

    def test_feed_identifies_exact_signed_package_and_monotonic_build(self):
        signature = base64.b64encode(bytes(64)).decode()
        root = ET.fromstring(feed_xml('1.2.0', 82, 100, signature))
        item = root.find('channel/item')
        self.assertEqual(item.find(f'{{{SPARKLE}}}version').text, '82')
        self.assertEqual(item.find(f'{{{SPARKLE}}}shortVersionString').text, '1.2.0')
        self.assertEqual(item.find('enclosure').get(f'{{{SPARKLE}}}installationType'), 'package')
        self.assertEqual(item.find('enclosure').get('url'), 'https://github.com/Chokamin/SubPop/releases/download/v1.2.0/SubPop-1.2.0-arm64.pkg')
        for version, build, size, sig in [('1.2.0/other',82,100,signature),('1.2.0',0,100,signature),('1.2.0',83,0,signature),('1.2.0',83,100,'invalid')]:
            with self.assertRaises((ValueError, __import__('binascii').Error)):
                feed_xml(version, build, size, sig)
