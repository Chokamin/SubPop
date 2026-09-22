"""Sign a staged SubPop app inside-out. Credentials stay in the macOS Keychain."""
import argparse
from pathlib import Path
import plistlib
import subprocess

MACHO = {bytes.fromhex(v) for v in ('feedface','feedfacf','cefaedfe','cffaedfe','cafebabe','bebafeca','cafebabf','bfbafeca')}
CONTAINER_ENTITLEMENTS = Path(__file__).resolve().parents[1]/'native/Probe/Container.entitlements'

def run(*args):
    subprocess.run([str(a) for a in args], check=True)

def sign(app, identity, extension_entitlements):
    app = Path(app).resolve()
    entitlements = plistlib.loads(Path(extension_entitlements).read_bytes())
    if entitlements.get('com.apple.security.cs.disable-library-validation') is not True or entitlements.get('com.apple.security.app-sandbox') is not True:
        raise ValueError('FCP extension requires its sandbox and the host-framework library-validation exception')
    runtime = app/'Contents/Resources/Runtime'
    python_entitlements = app.parent/'python-signing.plist'
    # Numba/LLVM generate machine code in the Python process. Scope exceptions to Python only.
    python_entitlements.write_bytes(plistlib.dumps({
        'com.apple.security.cs.allow-jit': True,
        'com.apple.security.cs.allow-unsigned-executable-memory': True,
    }))
    targets = []
    for path in app.rglob('*'):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open('rb') as stream:
            if stream.read(4) in MACHO:
                targets.append(path)
    sparkle=app/'Contents/Frameworks/Sparkle.framework'
    # Sign Sparkle bundles as units, preserving its helper entitlements.
    targets=[p for p in targets if not p.is_relative_to(sparkle)]
    if sparkle.exists():
        nested=sorted((p for p in sparkle.rglob('*') if not p.is_symlink() and p.suffix in ('.app','.xpc')),key=lambda p:len(p.parts),reverse=True)
        for bundle in [sparkle/'Versions/B/Autoupdate',*nested,sparkle]:
            run('codesign','--force','--sign',identity,'--timestamp','--options','runtime','--preserve-metadata=entitlements',bundle)
    for path in sorted(targets, key=lambda p: len(p.parts), reverse=True):
        command=['codesign','--force','--sign',identity,'--timestamp','--options','runtime']
        if path.parent == runtime/'.venv/bin' and path.name.startswith('python'):
            command += ['--entitlements', python_entitlements]
        run(*command,path)
    extension=app/'Contents/PlugIns/SubPopProbe.appex'
    run('codesign','--force','--sign',identity,'--timestamp','--options','runtime','--entitlements',extension_entitlements,extension)
    # TCC attributes extension Apple Events to its containing app. Both need the
    # hardened-runtime declaration; the extension sandbox still limits reads to FCP.
    run('codesign','--force','--sign',identity,'--timestamp','--options','runtime','--entitlements',CONTAINER_ENTITLEMENTS,app)
    run('codesign','--verify','--deep','--strict','--verbose=2',app)
    # Valid signatures alone cannot prove that FCP can load its host framework.
    for bundle, expected in ((extension, True), (app, False)):
        embedded = subprocess.run(['codesign','-d','--entitlements',':-',str(bundle)], capture_output=True, check=True).stdout
        values = plistlib.loads(embedded) if embedded.strip() else {}
        if (values.get('com.apple.security.cs.disable-library-validation') is True) != expected:
            raise ValueError('Library-validation exception must be scoped to the FCP extension')
        if values.get('com.apple.security.automation.apple-events') is not True:
            raise ValueError('Both app and extension must declare Apple Events for TCC attribution')
    python_entitlements.unlink()
    print(f'Signed {len(targets)} Mach-O files and app/extension bundles',flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('app',type=Path);p.add_argument('--identity',required=True);p.add_argument('--extension-entitlements',required=True,type=Path)
    a=p.parse_args();sign(a.app,a.identity,a.extension_entitlements)
