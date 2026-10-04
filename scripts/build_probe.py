"""Build the native integration probe against a locally extracted Apple SDK."""
from pathlib import Path
import plistlib
import os
import shutil
import subprocess
from sparkle_dependency import prepare, PUBLIC_KEY, FEED
from opencc_dependency import prepare as prepare_opencc
from extension_icon import prepare as prepare_extension_icon

ROOT=Path(__file__).resolve().parents[1]
SDK=ROOT/'.subloom/sdk-expanded/WorkflowExtensionsSDK.pkg/Payload/Library/Developer/SDKs/WorkflowExtensionSDK.sdk'
APP=ROOT/'.subloom/build/SubPop Probe.app'
EXT=APP/'Contents/PlugIns/SubPopProbe.appex'
TEAM_ID='925BTJVFFZ'
MACHO={bytes.fromhex(value) for value in ('feedface','feedfacf','cefaedfe','cffaedfe','cafebabe','bebafeca','cafebabf','bfbafeca')}

def plist(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(plistlib.dumps(value))

def run(*args):subprocess.run([str(a) for a in args],check=True)

def sign_development_runtime(runtime,launcher,identity):
    """Keep the private worker hardened while allowing its native wheels to load."""
    if identity=='-':return
    signed=0
    for path in runtime.rglob('*'):
        if path==launcher or path.is_symlink() or not path.is_file():continue
        with path.open('rb') as stream:
            if stream.read(4) not in MACHO:continue
        details=subprocess.run(['codesign','-d','--verbose=2',str(path)],capture_output=True,text=True)
        same_team=details.returncode==0 and f'TeamIdentifier={TEAM_ID}' in details.stderr
        if same_team and subprocess.run(['codesign','--verify','--strict',str(path)],capture_output=True).returncode==0:
            continue
        result=subprocess.run(['codesign','--force','--sign',identity,'--timestamp','--options','runtime',str(path)],capture_output=True,text=True)
        if result.returncode:raise RuntimeError(f'Cannot sign development runtime dependency: {path}')
        signed+=1
    print(f'Signed {signed} development runtime dependencies')

def build():
    if not (SDK/'usr/lib/libProExtension.a').exists():raise SystemExit(f'Extract the official Apple Workflow Extension SDK first; expected SDK: {SDK}')
    # The development venv links to an interpreter outside the project. Copy
    # and entitle a private launcher so the child can write the App Group bridge.
    python=(ROOT/'.venv/bin/python').resolve()
    launcher=ROOT/'.venv/bin/subpop-python3.12'
    shutil.copy2(python,launcher)
    dylib=python.parent.parent/'lib/libpython3.12.dylib'
    shutil.copy2(dylib,ROOT/'.venv/lib/libpython3.12.dylib')
    launcher_entitlements=ROOT/'.subloom/build/dev-python-entitlements.plist'
    launcher_entitlements.parent.mkdir(parents=True,exist_ok=True)
    plist(launcher_entitlements,{'com.apple.security.application-groups':['925BTJVFFZ.com.chokamin.SubPop'],'com.apple.security.cs.allow-jit':True,'com.apple.security.cs.allow-unsigned-executable-memory':True})
    identity=os.environ.get('SUBPOP_SIGNING_IDENTITY','-')
    signing_options=['--timestamp','--options','runtime'] if identity!='-' else []
    sign_development_runtime(ROOT/'.venv',launcher,identity)
    run('codesign','--force','--sign',identity,*signing_options,ROOT/'.venv/lib/libpython3.12.dylib')
    run('codesign','--force','--sign',identity,*signing_options,'--entitlements',launcher_entitlements,launcher)
    sparkle=prepare()
    opencc=prepare_opencc()
    frameworks=APP/'Contents/Frameworks'
    frameworks.mkdir(parents=True,exist_ok=True)
    destination=frameworks/'Sparkle.framework'
    if destination.exists():shutil.rmtree(destination)
    shutil.copytree(sparkle/'Sparkle.framework',destination,symlinks=True)
    for bundle in (APP,EXT):(bundle/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
    base=dict(CFBundleVersion='142',CFBundleShortVersionString='1.4.13',LSMinimumSystemVersion='13.0',SubPopUpdateRepository='Chokamin/SubPop')
    plist(APP/'Contents/Info.plist',dict(base,CFBundleDevelopmentRegion='zh_CN',CFBundleLocalizations=['zh_CN'],SUFeedURL=FEED,SUPublicEDKey=PUBLIC_KEY,SUEnableAutomaticChecks=False,SUAllowsAutomaticUpdates=False,SUVerifyUpdateBeforeExtraction=True,SURequireSignedFeed=True,SUSignedFeedFailureExpirationInterval=0,SUShowReleaseNotes=False,SUEnableSystemProfiling=False,LSUIElement=True,CFBundleURLTypes=[dict(CFBundleURLName='com.chokamin.SubPopProbe.start',CFBundleURLSchemes=['subpop-probe'])],SubPopWorkspace=str(ROOT),CFBundleIdentifier='com.chokamin.SubPopProbe',CFBundleName='SubPop',CFBundleIconFile='SubPop',CFBundleIconName='SubPop',CFBundleExecutable='SubPopProbe',CFBundlePackageType='APPL',NSPrincipalClass='NSApplication',NSAppleEventsUsageDescription='SubPop 需要读取 Final Cut Pro 的当前项目和时间线信息。'))
    plist(EXT/'Contents/Info.plist',dict(base,SubPopWorkspace=str(ROOT),CFBundleIdentifier='com.chokamin.SubPopProbe.Extension',CFBundleName='SubPop',CFBundleIconFile='ExtensionIcon',CFBundleIconName='ExtensionIcon',CFBundleDisplayName='SubPop',CFBundleExecutable='SubPopProbeExtension',CFBundlePackageType='XPC!',NSAppleEventsUsageDescription='SubPop 需要读取 Final Cut Pro 的当前项目和时间线信息。',NSExtension=dict(NSExtensionPointIdentifier='com.apple.FinalCut.WorkflowExtension',ProExtensionPrincipalViewControllerClass='SubPopProbeViewController',ProExtensionAttributes=dict(ContentViewMinimumWidth=580,ContentViewMinimumHeight=450))))
    mac_sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
    flags=['-isysroot',mac_sdk,'-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-arch','arm64','-mmacosx-version-min=13.0','-framework','Cocoa','-framework','QuartzCore','-framework','CoreText','-framework','CoreImage','-framework','ImageIO','-framework','Security','-framework','LocalAuthentication','-framework','UniformTypeIdentifiers']
    chinese=['-I'+str(opencc['include']),ROOT/'native/Probe/ChineseConversion.m',*opencc['libraries'],'-lc++']
    for destination in (EXT/'Contents/Resources/OpenCC',ROOT/'.subloom/build/OpenCC'):
        if destination.exists():shutil.rmtree(destination)
        shutil.copytree(opencc['data'],destination)
    run('xcrun','clang',*flags,ROOT/'native/Probe/CloudSettingsTests.m','-o',ROOT/'.subloom/build/SubPopCloudSettingsTests')
    run('xcrun','clang',*flags,ROOT/'native/Probe/ApplicationMenuTests.m','-o',ROOT/'.subloom/build/SubPopApplicationMenuTests')
    run('xcrun','clang',*flags,'-F'+str(frameworks),'-framework','Sparkle','-Wl,-rpath,@executable_path/../Frameworks',ROOT/'native/Probe/Container.m','-o',APP/'Contents/MacOS/SubPopProbe')
    run('xcrun','clang',*flags,*chinese,'-fapplication-extension','-I'+str(SDK/'usr/include'),'-F'+str(SDK/'Library/Frameworks'),'-L'+str(SDK/'usr/lib'),'-lProExtension','-framework','CoreMedia','-framework','AVFoundation','-Wl,-e,_ProExtensionMain',ROOT/'native/Probe/ProbeViewController.m',ROOT/'native/Probe/ProbePresentation.m',ROOT/'native/Probe/AudioProbe.m','-o',EXT/'Contents/MacOS/SubPopProbeExtension')
    run('xcrun','clang',*flags,'-framework','CoreMedia','-framework','AVFoundation',ROOT/'native/Probe/PreviewSourceTests.m','-o',ROOT/'.subloom/build/SubPopPreviewSourceTests')
    run('xcrun','clang',*flags,'-framework','CoreMedia','-framework','AVFoundation',ROOT/'native/Probe/AudioProbe.m',ROOT/'native/Probe/AudioProbeCLI.m','-o',ROOT/'.subloom/build/SubPopAudioProbeCLI')
    run('xcrun','clang',*flags,*chinese,'-I'+str(SDK/'usr/include'),'-F'+str(SDK/'Library/Frameworks'),'-L'+str(SDK/'usr/lib'),'-lProExtension','-framework','CoreMedia','-framework','AVFoundation',ROOT/'native/Probe/PresentationTests.m',ROOT/'native/Probe/ProbePresentation.m',ROOT/'native/Probe/AudioProbe.m','-o',ROOT/'.subloom/build/SubPopPresentationTests')
    run('xcrun','clang',*flags,*chinese,'-I'+str(SDK/'usr/include'),'-F'+str(SDK/'Library/Frameworks'),'-L'+str(SDK/'usr/lib'),'-lProExtension','-framework','CoreMedia','-framework','AVFoundation',ROOT/'native/Probe/StudioTests.m',ROOT/'native/Probe/ProbePresentation.m',ROOT/'native/Probe/AudioProbe.m','-o',ROOT/'.subloom/build/SubPopStudioTests')
    run('xcrun','clang',*flags,*chinese,'-I'+str(SDK/'usr/include'),'-F'+str(SDK/'Library/Frameworks'),'-L'+str(SDK/'usr/lib'),'-lProExtension','-framework','CoreMedia','-framework','AVFoundation',ROOT/'native/Probe/NativeStyleTests.m',ROOT/'native/Probe/ProbePresentation.m',ROOT/'native/Probe/AudioProbe.m','-o',ROOT/'.subloom/build/SubPopNativeStyleTests')
    run('xcrun','clang',*flags,*chinese,'-I'+str(SDK/'usr/include'),'-F'+str(SDK/'Library/Frameworks'),'-L'+str(SDK/'usr/lib'),'-lProExtension','-framework','CoreMedia','-framework','AVFoundation',ROOT/'native/Probe/ReferenceTests.m',ROOT/'native/Probe/ProbePresentation.m',ROOT/'native/Probe/AudioProbe.m','-o',ROOT/'.subloom/build/SubPopReferenceTests')
    run('xcrun','clang',*flags,*chinese,'-I'+str(SDK/'usr/include'),'-F'+str(SDK/'Library/Frameworks'),'-L'+str(SDK/'usr/lib'),'-lProExtension','-framework','CoreMedia','-framework','AVFoundation',ROOT/'native/Probe/ModelPreparationTests.m',ROOT/'native/Probe/ProbePresentation.m',ROOT/'native/Probe/AudioProbe.m','-o',ROOT/'.subloom/build/SubPopModelPreparationTests')
    run('xcrun','clang',*flags,*chinese,'-I'+str(SDK/'usr/include'),'-F'+str(SDK/'Library/Frameworks'),'-L'+str(SDK/'usr/lib'),'-lProExtension','-framework','CoreMedia','-framework','AVFoundation',ROOT/'native/Probe/FallbackAudioTests.m',ROOT/'native/Probe/ProbePresentation.m',ROOT/'native/Probe/AudioProbe.m','-o',ROOT/'.subloom/build/SubPopFallbackAudioTests')
    run('xcrun','clang',*flags,*chinese,'-I'+str(SDK/'usr/include'),'-F'+str(SDK/'Library/Frameworks'),'-L'+str(SDK/'usr/lib'),'-lProExtension','-framework','CoreMedia','-framework','AVFoundation',ROOT/'native/Probe/ChineseScriptTests.m',ROOT/'native/Probe/ProbePresentation.m',ROOT/'native/Probe/AudioProbe.m','-o',ROOT/'.subloom/build/SubPopChineseScriptTests')
    run('xcrun','clang',*flags,ROOT/'native/Probe/Tap5aInstallerTests.m','-o',ROOT/'.subloom/build/SubPopTap5aInstallerTests')
    run('xcrun','clang',*flags,ROOT/'native/Probe/RuntimePathsTests.m','-o',ROOT/'.subloom/build/SubPopRuntimePathsTests')
    run('xcrun','clang',*flags,ROOT/'native/Probe/UpdateTests.m','-o',ROOT/'.subloom/build/SubPopUpdateTests')
    run('xcrun','clang',*flags,ROOT/'native/Probe/FeedbackTests.m','-o',ROOT/'.subloom/build/SubPopFeedbackTests')
    resources=EXT/'Contents/Resources'
    resources.mkdir(parents=True,exist_ok=True)
    icon_output=ROOT/'.subloom/build/icon-assets'
    if icon_output.exists():shutil.rmtree(icon_output)
    icon_output.mkdir()
    run('xcrun','actool',ROOT/'native/Probe/Assets/SubPop.icon','--compile',icon_output,
        '--app-icon','SubPop','--platform','macosx','--minimum-deployment-target','15.0',
        '--output-partial-info-plist',icon_output/'icon-info.plist','--output-format','human-readable-text')
    (APP/'Contents/Resources').mkdir(parents=True,exist_ok=True)
    for name in ('SubPop.icns','Assets.car'):shutil.copy2(icon_output/name,APP/'Contents/Resources'/name)
    # The workflow extension supplies its own transparent glyph. Reusing the
    # application's opaque icon plate hides the logo in tinted host controls.
    extension_output=ROOT/'.subloom/build/extension-icon-assets'
    prepare_extension_icon(extension_output)
    (resources/'SubPop.icns').unlink(missing_ok=True)
    for name in ('ExtensionIcon.icns','Assets.car'):shutil.copy2(extension_output/name,resources/name)
    shutil.copy2(ROOT/'licenses/Sparkle.txt',APP/'Contents/Resources/Sparkle-LICENSE.txt')
    shutil.copy2(ROOT/'config/models.json',resources/'models.json')
    for fixture in (ROOT/'native/Probe/Fixtures').glob('*.fcpxml'):shutil.copy2(fixture,resources/fixture.name)
    ent=ROOT/'.subloom/build/probe.entitlements'
    # FCP injects its ProViewServiceSupport framework into the extension process.
    # Its signing team differs from ours. Scope this runtime exception to the
    # extension only; retain its sandbox and the container's library validation.
    plist(ent,{'com.apple.security.cs.disable-library-validation':True, 'com.apple.security.app-sandbox':True, 'com.apple.security.network.client':True, 'com.apple.security.application-groups':['925BTJVFFZ.com.chokamin.SubPop'], 'com.apple.security.files.user-selected.read-write':True, 'com.apple.security.automation.apple-events':True, 'com.apple.security.scripting-targets':{'com.apple.FinalCut':['com.apple.FinalCut.library.inspection'],'com.apple.FinalCutApp':['com.apple.FinalCut.library.inspection']}})
    run('codesign','--force','--sign','-','--entitlements',ent,EXT)
    run('codesign','--force','--sign','-','--entitlements',ROOT/'native/Probe/Container.entitlements',APP)
    run('codesign','--verify','--deep','--strict',APP)
    print(APP)

if __name__=='__main__':build()
