"""Fetch the pinned upstream Sparkle SDK; binaries remain outside Git."""
import hashlib
from pathlib import Path
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VERSION = '2.10.0'
SHA256 = 'c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c'
SDK = ROOT / f'.subloom/dependencies/Sparkle-{VERSION}'
PUBLIC_KEY = 'YQZEh9mQr0DpIHpB4wr+FSYIZBceBO+BoM18O+DaXGw='
KEY_ACCOUNT = 'com.chokamin.SubPop.updates'
FEED = 'https://github.com/Chokamin/SubPop/releases/latest/download/appcast.xml'


def prepare():
    archive = Path(str(SDK) + '.tar.xz')
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        partial = archive.with_suffix('.partial')
        try:
            urllib.request.urlretrieve(f'https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/Sparkle-{VERSION}.tar.xz', partial)
            if hashlib.file_digest(partial.open('rb'), 'sha256').hexdigest() != SHA256:
                raise ValueError('Sparkle SDK checksum mismatch')
            partial.replace(archive)
        finally:
            partial.unlink(missing_ok=True)
    with archive.open('rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != SHA256:
            raise ValueError('Sparkle SDK checksum mismatch')
    # Always restore the verified upstream copy; signing the app must not alter the SDK.
    SDK.mkdir(exist_ok=True)
    with tarfile.open(archive) as tar:
        tar.extractall(SDK, filter='data')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(SDK / 'Sparkle.framework')], check=True)
    return SDK


if __name__ == '__main__':
    print(prepare())
