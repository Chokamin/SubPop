"""One bounded local job: native decode -> ASR -> aligned Title XML.

Explicit snapshot input, not a live host request. Never writes the FCP timeline.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import uuid

from .readback import inspect
from .caption_fixture import captions, srt
from .title_fixture import payload, UID

ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'.subloom/verification/jobs'


def save(path,value):
    temp=path.with_suffix('.tmp')
    temp.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
    temp.replace(path)


def preflight(xml, asr, aligner):
    snapshot=inspect(xml)
    if snapshot['uid']!=UID or snapshot['project']!='Subloom-Original' or snapshot['duration']!='217/25' or snapshot['relative_start']!='0':
        raise ValueError('Only complete isolated 8.68s project supported')
    if Path(snapshot['media']).resolve()!=ROOT/'.subloom/verification/mandarin.mp4':
        raise ValueError('Isolated test media only')
    for model in (asr,aligner):
        if not model.resolve().is_relative_to(ROOT/'.subloom/models') or not (model/'config.json').is_file():
            raise ValueError('Use an independent SubPop model directory')
        if any(p.is_symlink() for p in model.rglob('*')):raise ValueError('Model files must not link to another project')
    return snapshot


def run(xml,asr,aligner):
    # Validate before starting costly work. Each invocation owns a new directory.
    snapshot=preflight(xml,asr,aligner)
    directory=WORK/str(uuid.uuid4());directory.mkdir(parents=True)
    frozen=directory/'input.fcpxml';frozen.write_bytes(xml.read_bytes())
    # Re-validate the actual frozen input to prevent an input-file race.
    snapshot=preflight(frozen,asr,aligner)
    state={'jobID':directory.name,'status':'running','stage':'decode','projectUID':snapshot['uid'],
           'snapshotSHA256':hashlib.sha256(frozen.read_bytes()).hexdigest(),
           'createdAt':datetime.now(timezone.utc).isoformat(),'source':'explicit XML snapshot; freshness not established by active host'}
    def progress(stage):
        state['stage']=stage;save(directory/'status.json',state);print(json.dumps({'job':directory.name,'stage':stage}),flush=True)
    try:
        progress('decode')
        binary=ROOT/'.subloom/build/SubPopAudioProbeCLI'
        completed=subprocess.run([str(binary),str(frozen),UID,str(directory)],capture_output=True,text=True,check=True,timeout=60)
        decoded=json.loads(completed.stdout);save(directory/'audio.json',decoded)
        if decoded.get('status')!='decoded':raise ValueError('Audio decode failed: '+decoded.get('stage','unknown'))
        pcm=directory/decoded['pcmFile']
        if pcm.parent!=directory or not pcm.is_file():raise ValueError('Invalid PCM output')
        progress('recognize')
        from .recognize_fixture import run as recognize
        result=recognize(frozen,asr,aligner,directory/'asr.json',pcm,device='cpu',verbose=False)
        progress('generate-titles')
        rows=captions(result)
        manifest={'projectUID':UID,'pcmSHA256':result['pcm_sha256'],'fps':25,'captions':rows}
        save(directory/'captions.json',manifest)
        (directory/'captions.srt').write_text(srt(rows))
        for version in ('1.12','1.13','1.14'):(directory/f'TitleProbe-{version}.fcpxml').write_bytes(payload(manifest,version))
        outputs={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in directory.iterdir() if p.name.startswith('TitleProbe-') or p.name in ('captions.json','captions.srt')}
        state.update(status='ready',stage='ready',outputs=outputs,pcmSHA256=result['pcm_sha256'],titleCount=len(rows),device=result['device'])
        save(directory/'status.json',state);print(json.dumps({'ready':str(directory),'titleCount':len(rows)}),flush=True)
        return directory
    except BaseException as error:
        state.update(status='failed',error=f'{type(error).__name__}: {error}')
        save(directory/'status.json',state)
        raise


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--xml',type=Path,required=True)
    args=parser.parse_args();run(args.xml,ROOT/'.subloom/models/asr',ROOT/'.subloom/models/aligner')
