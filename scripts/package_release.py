"""Build a relocatable, model-free PKG with optional Developer ID signing."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
STAGE=ROOT/'.subloom/package'
APP=STAGE/'payload/Applications/SubPop.app'
RUNTIME=APP/'Contents/Resources/Runtime'
DIST=ROOT/'dist'

def run(*args):subprocess.run([str(a) for a in args],check=True)

def build(application_identity=None, installer_identity=None):
    if bool(application_identity) != bool(installer_identity):
        raise ValueError("Both application and installer identities are required")
    if STAGE.exists():shutil.rmtree(STAGE)
    APP.parent.mkdir(parents=True);DIST.mkdir(exist_ok=True)
    shutil.copytree(ROOT/'.subloom/build/SubPop Probe.app',APP,symlinks=True)
    RUNTIME.mkdir()
    info=plistlib.loads((APP/'Contents/Info.plist').read_bytes())
    version=info['CFBundleShortVersionString']+'.'+info['CFBundleVersion']
    python=(ROOT/'.venv/bin/python').resolve().parent.parent
    shutil.copytree(python,RUNTIME/'.venv',symlinks=True,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
    source=ROOT/'.venv/lib/python3.12/site-packages'
    shutil.copytree(source,RUNTIME/'.venv/lib/python3.12/site-packages',dirs_exist_ok=True,symlinks=True,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
    for name in ('probes','config'):
        shutil.copytree(ROOT/name,RUNTIME/name,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
    (RUNTIME/'.subloom/build').mkdir(parents=True)
    shutil.copy2(ROOT/'.subloom/build/SubPopAudioProbeCLI',RUNTIME/'.subloom/build/SubPopAudioProbeCLI')
    shutil.copy2(ROOT/'requirements-asr.lock.txt',RUNTIME/'requirements-asr.lock.txt')
    # Bundled standalone Python uses @executable_path for libpython; never copy the development venv link.
    for path in RUNTIME.rglob('*'):
        if path.is_symlink() and not path.resolve().is_relative_to(RUNTIME.resolve()):
            raise RuntimeError('External runtime link: '+str(path))
    ext=APP/'Contents/PlugIns/SubPopProbe.appex'
    for bundle in (APP,ext):
        p=bundle/'Contents/Info.plist';info=plistlib.loads(p.read_bytes());info.pop('SubPopWorkspace',None)
        info.update(SubPopPackagedRuntime=True,LSMinimumSystemVersion='15.0')
        p.write_bytes(plistlib.dumps(info))
    if application_identity:
        from sign_release import sign
        sign(APP,application_identity,ROOT/'.subloom/build/probe.entitlements')
    else:
        run('codesign','--force','--sign','-','--entitlements',ROOT/'.subloom/build/probe.entitlements',ext)
        run('codesign','--force','--sign','-',APP)
    run('codesign','--verify','--deep','--strict',APP)
    component=STAGE/'SubPop-component.pkg'
    run('pkgbuild','--root',STAGE/'payload','--identifier','com.chokamin.SubPop.installer','--version',version,'--install-location','/','--ownership','recommended',component)
    resources=STAGE/'resources';resources.mkdir()
    welcome=resources/'Welcome.html'
    welcome.write_text('<html><meta charset="utf-8"><body><h1>SubPop 公开测试版</h1><p>安装 FCP 扩展和独立本机识别环境。适用于 Apple Silicon、macOS 15 或更高版本。FCP 集成当前实测版本为 12.3。</p><p>安装后打开应用程序中的 SubPop，再从 Final Cut Pro 扩展菜单打开。首次允许默认任务文件夹，进入模型管理下载所需模型。</p><p>此包尚未完成 Developer ID 签名及 Apple 公证，仅供测试使用。安装不包含模型、测试视频、词库或历史字幕。</p></body></html>')
    if application_identity:
        welcome.write_text(welcome.read_text().replace('此包尚未完成 Developer ID 签名及 Apple 公证，仅供测试使用。','此包使用 Developer ID 签名。Apple 公证结果请以对应 Release 说明为准，仅供测试使用。'))
    xml=STAGE/'distribution.xml'
    xml.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2"><title>SubPop</title><welcome file="Welcome.html"/><options customize="never" require-scripts="false" hostArchitectures="arm64"/><volume-check><allowed-os-versions><os-version min="15.0"/></allowed-os-versions></volume-check><choices-outline><line choice="default"/></choices-outline><choice id="default" visible="false"><pkg-ref id="com.chokamin.SubPop.installer"/></choice><pkg-ref id="com.chokamin.SubPop.installer" version="{version}">SubPop-component.pkg</pkg-ref></installer-gui-script>''')
    flavor='signed-candidate' if application_identity else 'test'
    output=DIST/f'SubPop-{version}-arm64-{flavor}.pkg'
    run('productbuild','--distribution',xml,'--resources',resources,'--package-path',STAGE,*(['--sign',installer_identity,'--timestamp'] if installer_identity else []),output)
    with output.open('rb') as stream:
        digest=hashlib.file_digest(stream,'sha256').hexdigest()
    (DIST/(output.name+'.sha256')).write_text(digest+'  '+output.name+'\n')
    print(json.dumps(dict(package=str(output),bytes=output.stat().st_size,sha256=digest,notarized=False)))

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--application-identity')
    parser.add_argument('--installer-identity')
    args=parser.parse_args()
    build(args.application_identity,args.installer_identity)
