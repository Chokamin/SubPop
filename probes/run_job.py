"""One bounded local job: native decode -> ASR -> aligned Title XML.

Explicit snapshot input, not a live host request. Never writes the FCP timeline.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import uuid

from .project import inspect, render
from fractions import Fraction
from .caption_fixture import captions, srt
from .title_fixture import payload, UID
from .snapshot import prepare, collision
from .models import DEFAULT_MODEL_ID, model_spec, resolve_model
from .vocabulary import validate as validate_vocabulary

ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'.subloom/verification/jobs'


def save(path,value):
    temp=path.with_suffix('.tmp')
    temp.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
    temp.replace(path)


def preflight(xml, asr, aligner):
    snapshot=inspect(xml)
    if not snapshot['uid']:raise ValueError('Project UID required')
    for model in (asr,aligner):
        if not model.resolve().is_relative_to(ROOT/'.subloom/models') or not (model/'config.json').is_file():
            raise ValueError('Use an independent SubPop model directory')
        if any(p.is_symlink() for p in model.rglob('*')):raise ValueError('Model files must not link to another project')
    return snapshot


def run(xml,asr,aligner,model_id=DEFAULT_MODEL_ID,audio_mode='dialogue',vocabulary=None):
    # Validate before starting costly work. Each invocation owns a new directory.
    vocabulary=validate_vocabulary(vocabulary or [])
    original=xml.read_bytes()
    directory=WORK/str(uuid.uuid4());directory.mkdir(parents=True)
    frozen=directory/'input.fcpxml';frozen.write_bytes(original)
    state={'vocabulary':vocabulary,'modelID':model_id,'audioMode':audio_mode,'jobID':directory.name,'status':'running','stage':'validate','projectUID':UID,
           'snapshotSHA256':hashlib.sha256(frozen.read_bytes()).hexdigest(),
           'createdAt':datetime.now(timezone.utc).isoformat(),'source':'explicit XML snapshot; freshness not established by active host'}
    def progress(stage):
        state['stage']=stage;save(directory/'status.json',state);print(json.dumps({'job':directory.name,'stage':stage}),flush=True)
    try:
        model_spec(model_id)
        progress('validate')
        normalized,existing=prepare(frozen.read_bytes(),generic=True)
        audioXML=directory/'audio-input.fcpxml';audioXML.write_bytes(normalized)
        snapshot=preflight(audioXML,asr,aligner)
        state['projectUID']=snapshot['uid']
        progress('decode')
        binary=ROOT/'.subloom/build/SubPopAudioProbeCLI'
        decoded=render(audioXML,directory,binary,snapshot['uid'],audio_mode);save(directory/'audio.json',decoded)
        if decoded['silent']:
            state.update(status='blocked-no-audio',stage='silent',pcmSHA256=decoded['pcmSHA256'])
            save(directory/'status.json',state)
            print(json.dumps({'ready':str(directory),'blocked':'silent'}),flush=True)
            return directory
        pcm=directory/decoded['pcmFile']
        if pcm.parent!=directory or not pcm.is_file():raise ValueError('Invalid PCM output')
        progress('recognize')
        from .recognize_fixture import run as recognize
        result=recognize(audioXML,asr,aligner,directory/'asr.json',pcm,device='cpu',verbose=False,audio_mode=audio_mode,vocabulary=vocabulary)
        result['modelID']=model_id;save(directory/'asr.json',result)
        progress('generate-titles')
        frame=Fraction(result['snapshot']['frameDuration']);fps=1/frame
        rows=captions(result,fps,generic=True)
        manifest={**result['snapshot'],'projectUID':snapshot['uid'],'pcmSHA256':result['pcm_sha256'],'fps':str(fps),'captions':rows,'modelID':model_id,'vocabulary':vocabulary}
        save(directory/'captions.json',manifest)
        check=collision(rows,existing);save(directory/'collision.json',check)
        if check['status']!='clear':
            state.update(status='blocked-existing-titles',stage=check['status'],collision=check,
                         pcmSHA256=result['pcm_sha256'],titleCount=len(rows),device=result['device'])
            save(directory/'status.json',state);print(json.dumps({'ready':str(directory),'blocked':check['status']}),flush=True)
            return directory
        (directory/'captions.srt').write_text(srt(rows,fps))
        for version in ('1.12','1.13','1.14'):(directory/f'TitleProbe-{version}.fcpxml').write_bytes(payload(manifest,version))
        outputs={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in directory.iterdir() if p.name.startswith('TitleProbe-') or p.name in ('captions.json','captions.srt')}
        state.update(status='ready',stage='ready',outputs=outputs,pcmSHA256=result['pcm_sha256'],titleCount=len(rows),device=result['device'])
        save(directory/'status.json',state);print(json.dumps({'ready':str(directory),'titleCount':len(rows)}),flush=True)
        return directory
    except BaseException as error:
        state.update(status='failed',error=f'{type(error).__name__}: {error}')
        save(directory/'status.json',state)
        print(json.dumps({'error':state['error']}),flush=True)
        raise


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--xml',type=Path,required=True)
    parser.add_argument('--model',default=DEFAULT_MODEL_ID)
    parser.add_argument('--audio-mode',choices=['dialogue','all'],default='dialogue')
    parser.add_argument('--vocabulary-file',type=Path)
    args=parser.parse_args();asr,aligner=resolve_model(args.model)
    vocabulary=json.loads(args.vocabulary_file.read_text()).get('vocabulary',[]) if args.vocabulary_file else []
    run(args.xml,asr,aligner,args.model,args.audio_mode,vocabulary)
