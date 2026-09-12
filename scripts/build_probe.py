"""Build the native read-only probe against a locally extracted Apple SDK."""
from pathlib import Path
import plistlib
import subprocess

ROOT=Path(__file__).resolve().parents[1]
SDK=ROOT/'.subloom/sdk-expanded/WorkflowExtensionsSDK.pkg/Payload/Library/Developer/SDKs/WorkflowExtensionSDK.sdk'
APP=ROOT/'.subloom/build/Subloom Probe.app'
EXT=APP/'Contents/PlugIns/SubloomProbe.appex'

def plist(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(plistlib.dumps(value))

def run(*args):subprocess.run([str(a) for a in args],check=True)

def build():
    if not (SDK/'usr/lib/libProExtension.a').exists():raise SystemExit('Extract official SDK first; see HANDOFF.md')
    for bundle in (APP,EXT):(bundle/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
    base=dict(CFBundleVersion='1',CFBundleShortVersionString='0.0.1',LSMinimumSystemVersion='13.0')
    plist(APP/'Contents/Info.plist',dict(base,CFBundleIdentifier='com.chokamin.SubloomProbe',CFBundleName='Subloom Probe',CFBundleExecutable='SubloomProbe',CFBundlePackageType='APPL',NSPrincipalClass='NSApplication'))
    plist(EXT/'Contents/Info.plist',dict(base,CFBundleIdentifier='com.chokamin.SubloomProbe.Extension',CFBundleName='Subloom Probe',CFBundleDisplayName='Subloom Probe',CFBundleExecutable='SubloomProbeExtension',CFBundlePackageType='XPC!',NSExtension=dict(NSExtensionPointIdentifier='com.apple.FinalCut.WorkflowExtension',ProExtensionPrincipalViewControllerClass='SubloomProbeViewController'),ProExtensionAttributes=dict(ContentViewMinimumWidth=620,ContentViewMinimumHeight=430)))
    mac_sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
    flags=['-isysroot',mac_sdk,'-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-arch','arm64','-mmacosx-version-min=13.0','-framework','Cocoa']
    run('xcrun','clang',*flags,ROOT/'native/Probe/Container.m','-o',APP/'Contents/MacOS/SubloomProbe')
    run('xcrun','clang',*flags,'-fapplication-extension','-I'+str(SDK/'usr/include'),'-F'+str(SDK/'Library/Frameworks'),'-L'+str(SDK/'usr/lib'),'-lProExtension','-framework','CoreMedia','-Wl,-e,_ProExtensionMain',ROOT/'native/Probe/ProbeViewController.m','-o',EXT/'Contents/MacOS/SubloomProbeExtension')
    ent=ROOT/'.subloom/build/probe.entitlements'
    plist(ent,{'com.apple.security.app-sandbox':True})
    run('codesign','--force','--sign','-','--entitlements',ent,EXT)
    run('codesign','--force','--sign','-',APP)
    run('codesign','--verify','--deep','--strict',APP)
    print(APP)

if __name__=='__main__':build()
