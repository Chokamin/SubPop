"""Build the native integration probe against a locally extracted Apple SDK."""
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
SDK=ROOT/'.subloom/sdk-expanded/WorkflowExtensionsSDK.pkg/Payload/Library/Developer/SDKs/WorkflowExtensionSDK.sdk'
APP=ROOT/'.subloom/build/SubPop Probe.app'
EXT=APP/'Contents/PlugIns/SubPopProbe.appex'

def plist(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(plistlib.dumps(value))

def run(*args):subprocess.run([str(a) for a in args],check=True)

def build():
    if not (SDK/'usr/lib/libProExtension.a').exists():raise SystemExit(f'Extract the official Apple Workflow Extension SDK first; expected SDK: {SDK}')
    for bundle in (APP,EXT):(bundle/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
    base=dict(CFBundleVersion='61',CFBundleShortVersionString='1.1.0',LSMinimumSystemVersion='13.0',SubPopUpdateRepository='Chokamin/SubPop')
    plist(APP/'Contents/Info.plist',dict(base,LSUIElement=True,CFBundleURLTypes=[dict(CFBundleURLName='com.chokamin.SubPopProbe.start',CFBundleURLSchemes=['subpop-probe'])],SubPopWorkspace=str(ROOT),CFBundleIdentifier='com.chokamin.SubPopProbe',CFBundleName='SubPop',CFBundleIconFile='SubPop',CFBundleIconName='SubPop',CFBundleExecutable='SubPopProbe',CFBundlePackageType='APPL',NSPrincipalClass='NSApplication',NSAppleEventsUsageDescription='SubPop 需要读取 Final Cut Pro 的当前项目和时间线信息。'))
    plist(EXT/'Contents/Info.plist',dict(base,SubPopWorkspace=str(ROOT),CFBundleIdentifier='com.chokamin.SubPopProbe.Extension',CFBundleName='SubPop',CFBundleIconFile='SubPop',CFBundleIconName='SubPop',CFBundleDisplayName='SubPop',CFBundleExecutable='SubPopProbeExtension',CFBundlePackageType='XPC!',NSAppleEventsUsageDescription='SubPop 需要读取 Final Cut Pro 的当前项目和时间线信息。',NSExtension=dict(NSExtensionPointIdentifier='com.apple.FinalCut.WorkflowExtension',ProExtensionPrincipalViewControllerClass='SubPopProbeViewController'),ProExtensionAttributes=dict(ContentViewMinimumWidth=580,ContentViewMinimumHeight=680)))
    mac_sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
    flags=['-isysroot',mac_sdk,'-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-arch','arm64','-mmacosx-version-min=13.0','-framework','Cocoa','-framework','QuartzCore','-framework','CoreText','-framework','CoreImage','-framework','Security','-framework','LocalAuthentication']
    run('xcrun','clang',*flags,ROOT/'native/Probe/CloudSettingsTests.m','-o',ROOT/'.subloom/build/SubPopCloudSettingsTests')
    run('xcrun','clang',*flags,ROOT/'native/Probe/Container.m','-o',APP/'Contents/MacOS/SubPopProbe')
    run('xcrun','clang',*flags,'-fapplication-extension','-I'+str(SDK/'usr/include'),'-F'+str(SDK/'Library/Frameworks'),'-L'+str(SDK/'usr/lib'),'-lProExtension','-framework','CoreMedia','-framework','AVFoundation','-Wl,-e,_ProExtensionMain',ROOT/'native/Probe/ProbeViewController.m',ROOT/'native/Probe/ProbePresentation.m',ROOT/'native/Probe/AudioProbe.m','-o',EXT/'Contents/MacOS/SubPopProbeExtension')
    run('xcrun','clang',*flags,'-framework','CoreMedia','-framework','AVFoundation',ROOT/'native/Probe/AudioProbe.m',ROOT/'native/Probe/AudioProbeCLI.m','-o',ROOT/'.subloom/build/SubPopAudioProbeCLI')
    run('xcrun','clang',*flags,'-I'+str(SDK/'usr/include'),'-F'+str(SDK/'Library/Frameworks'),'-L'+str(SDK/'usr/lib'),'-lProExtension','-framework','CoreMedia','-framework','AVFoundation',ROOT/'native/Probe/PresentationTests.m',ROOT/'native/Probe/ProbePresentation.m',ROOT/'native/Probe/AudioProbe.m','-o',ROOT/'.subloom/build/SubPopPresentationTests')
    run('xcrun','clang',*flags,'-I'+str(SDK/'usr/include'),'-F'+str(SDK/'Library/Frameworks'),'-L'+str(SDK/'usr/lib'),'-lProExtension','-framework','CoreMedia','-framework','AVFoundation',ROOT/'native/Probe/StudioTests.m',ROOT/'native/Probe/ProbePresentation.m',ROOT/'native/Probe/AudioProbe.m','-o',ROOT/'.subloom/build/SubPopStudioTests')
    run('xcrun','clang',*flags,ROOT/'native/Probe/Tap5aInstallerTests.m','-o',ROOT/'.subloom/build/SubPopTap5aInstallerTests')
    resources=EXT/'Contents/Resources'
    resources.mkdir(parents=True,exist_ok=True)
    icon_output=ROOT/'.subloom/build/icon-assets'
    if icon_output.exists():shutil.rmtree(icon_output)
    icon_output.mkdir()
    run('xcrun','actool',ROOT/'native/Probe/Assets/SubPop.icon','--compile',icon_output,
        '--app-icon','SubPop','--platform','macosx','--minimum-deployment-target','15.0',
        '--output-partial-info-plist',icon_output/'icon-info.plist','--output-format','human-readable-text')
    for bundle in (APP,EXT):
        (bundle/'Contents/Resources').mkdir(parents=True,exist_ok=True)
        for name in ('SubPop.icns','Assets.car'):shutil.copy2(icon_output/name,bundle/'Contents/Resources'/name)
    shutil.copy2(ROOT/'config/models.json',resources/'models.json')
    for fixture in (ROOT/'native/Probe/Fixtures').glob('*.fcpxml'):shutil.copy2(fixture,resources/fixture.name)
    ent=ROOT/'.subloom/build/probe.entitlements'
    plist(ent,{'com.apple.security.app-sandbox':True, 'com.apple.security.network.client':True, 'com.apple.security.files.user-selected.read-write':True, 'com.apple.security.automation.apple-events':True, 'com.apple.security.scripting-targets':{'com.apple.FinalCut':['com.apple.FinalCut.library.inspection']}})
    run('codesign','--force','--sign','-','--entitlements',ent,EXT)
    run('codesign','--force','--sign','-',APP)
    run('codesign','--verify','--deep','--strict',APP)
    print(APP)

if __name__=='__main__':build()
