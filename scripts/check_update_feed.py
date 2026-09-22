"""Build an isolated Sparkle verifier; it cannot reach an installation callback.

Pass a feed URL and optional --download or --cancel. Intended for the pinned
1.2.0 / Build82 fixture, not for installing updates or controlling FCP.
"""
from pathlib import Path
import plistlib,shutil,subprocess,sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from sparkle_dependency import PUBLIC_KEY
root=Path(__file__).resolve().parents[1];app=root/'.subloom/verification/update83/FeedProbe.app';mac=app/'Contents/MacOS';mac.mkdir(parents=True,exist_ok=True)
frameworks=app/'Contents/Frameworks';frameworks.mkdir(exist_ok=True)
f=frameworks/'Sparkle.framework'
if not f.exists():shutil.copytree(root/'.subloom/build/SubPop Probe.app/Contents/Frameworks/Sparkle.framework',f,symlinks=True)
info={'CFBundleIdentifier':'com.chokamin.SubPop.UpdateFeedProbe'+('Cancel' if '--cancel' in sys.argv else ''),'CFBundleExecutable':'FeedProbe','CFBundleName':'SubPop Feed Verification','CFBundlePackageType':'APPL','CFBundleVersion':'81','CFBundleShortVersionString':'1.1.0','SUFeedURL':'https://github.com/Chokamin/SubPop/releases/latest/download/appcast.xml','SUPublicEDKey':PUBLIC_KEY,'SUVerifyUpdateBeforeExtraction':True,'SURequireSignedFeed':True,'SUSignedFeedFailureExpirationInterval':0,'SUEnableAutomaticChecks':False,'SUAllowsAutomaticUpdates':False,'LSUIElement':True}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-arch','arm64','-mmacosx-version-min=13.0','-framework','Cocoa','-F'+str(frameworks),'-framework','Sparkle','-Wl,-rpath,@executable_path/../Frameworks',str(root/'native/Probe/OnlineUpdateTests.m'),'-o',str(mac/'FeedProbe')],check=True)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)

if len(sys.argv)>1:
    subprocess.run([str(mac/'FeedProbe'),*sys.argv[1:]],check=True,timeout=310)
