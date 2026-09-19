"""Verify an expanded PKG against its staging payload; never installs or edits FCP."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / '.subloom/package/payload/Applications/SubPop.app'
actual = ROOT / '.subloom/package-expanded/SubPop-component.pkg/Payload/Applications/SubPop.app'

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def manifest(base):
    result = {}
    for path in base.rglob('*'):
        relative = str(path.relative_to(base))
        if path.is_symlink():
            assert path.resolve().is_relative_to(base.resolve()), relative
            result[relative] = ['link', str(path.readlink())]
        elif path.is_file():
            result[relative] = [path.stat().st_mode & 0o777, digest(path)]
    return result

assert actual.is_dir(), 'Expand final PKG with pkgutil --expand-full first'
assert sorted(p.name for p in actual.parent.iterdir()) == ['SubPop.app'], 'Unexpected installer payload'
expected, packaged = manifest(source), manifest(actual)
assert expected == packaged, 'Expanded payload differs from staging'
for suffix in ('', 'Contents/PlugIns/SubPopProbe.appex'):
    info = plistlib.loads((actual / suffix / 'Contents/Info.plist').read_bytes())
    assert info.get('CFBundleIconName') == 'SubPop', 'Missing native icon identity'
    assert (actual / suffix / 'Contents/Resources/Assets.car').is_file(), 'Missing native icon catalog'
    assert info['SubPopPackagedRuntime'] and 'SubPopWorkspace' not in info
    assert info['CFBundleVersion'] == plistlib.loads((source / suffix / 'Contents/Info.plist').read_bytes())['CFBundleVersion']
assert not (actual / 'Contents/Resources/Runtime/.subloom/models').exists()
assert not (actual / 'Contents/Resources/Runtime/.subloom/verification').exists()
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(actual)], check=True)
signature = subprocess.run(['codesign', '-dvv', str(actual)], capture_output=True, text=True, check=True).stderr
print(json.dumps({'filesVerified': len(packaged), 'payloadMatches': True, 'externalSymlinks': False,
                  'bundledModels': False, 'bundledUserJobs': False, 'signature': 'Developer ID' if 'Authority=Developer ID Application:' in signature else 'ad-hoc'}))
