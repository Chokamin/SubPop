"""Submit a signed PKG using a Keychain profile, staple only after Apple accepts it."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)

def notarize(package, profile):
    package=Path(package).resolve()
    run('pkgutil','--check-signature',package)
    result=run('xcrun','notarytool','submit',package,'--keychain-profile',profile,'--wait','--output-format','json',capture_output=True,text=True)
    response=json.loads(result.stdout)
    report=package.with_suffix('.notary.json')
    report.write_text(json.dumps(response,indent=2)+'\n')
    if response.get('status') != 'Accepted':
        if response.get('id'):
            run('xcrun','notarytool','log',response['id'],'--keychain-profile',profile,package.with_suffix('.notary-log.json'))
        raise RuntimeError('Apple has not accepted this package; do not publish as notarized')
    run('xcrun','stapler','staple',package)
    run('xcrun','stapler','validate',package)
    run('spctl','--assess','--type','install','--verbose=2',package)
    with package.open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
    Path(str(package)+'.sha256').write_text(digest+'  '+package.name+'\n')
    print(json.dumps({'package':str(package),'sha256':digest,'notarized':True,'submissionID':response['id']}))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('package',type=Path);parser.add_argument('--keychain-profile',required=True)
    args=parser.parse_args();notarize(args.package,args.keychain_profile)
