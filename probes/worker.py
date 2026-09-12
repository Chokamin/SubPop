"""Local project worker. One fixed workspace, no network, no arbitrary commands."""
import fcntl
import hashlib
import json
import os
import signal
from pathlib import Path
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET

from .run_job import ROOT, save
from .title_fixture import UID
from .models import DEFAULT_MODEL_ID, model_spec, resolve_model, availability

BRIDGE=ROOT/'.subloom/verification/bridge'
MAX_XML=16*1024*1024


def valid_id(value):
    try:return str(uuid.UUID(value))==value
    except (ValueError,TypeError,AttributeError):return False


def request_input(directory):
    if directory.is_symlink() or not valid_id(directory.name):raise ValueError('Invalid request directory')
    request=directory/'request.json';xml=directory/'input.fcpxml'
    if request.is_symlink() or xml.is_symlink():raise ValueError('Linked input refused')
    if request.stat().st_size>4096 or not 0<xml.stat().st_size<=MAX_XML:raise ValueError('Invalid input size')
    data=json.loads(request.read_text())
    if data.get('requestID')!=directory.name or not isinstance(data.get('projectUID'),str) or not data.get('projectUID'):raise ValueError('Wrong request identity')
    raw=xml.read_bytes()
    if data.get('xmlSHA256')!=hashlib.sha256(raw).hexdigest():raise ValueError('Input checksum mismatch')
    if b'<!ENTITY' in raw.upper():raise ValueError('XML entities refused')
    projects=ET.fromstring(raw).findall('.//project')
    if len(projects)!=1 or projects[0].get('uid')!=data['projectUID']:raise ValueError('Snapshot project identity mismatch')
    model_spec(data.get('modelID', DEFAULT_MODEL_ID))
    if data.get('audioMode','dialogue') not in ('dialogue','all'):raise ValueError('Invalid audio mode')
    return xml


def job_command(directory):
    model_id = json.loads((directory/'request.json').read_text()).get('modelID', DEFAULT_MODEL_ID)
    resolve_model(model_id)
    return [sys.executable, '-B', '-m', 'probes.run_job', '--xml', str(directory/'input.fcpxml'), '--model', model_id, '--audio-mode', json.loads((directory/'request.json').read_text()).get('audioMode','dialogue')]


def publish_result(directory, job):
    # Only a run_job-owned output directory may be returned.
    job=Path(job).resolve()
    if job.parent!=ROOT/'.subloom/verification/jobs' or not valid_id(job.name):raise ValueError('Invalid result directory')
    status=json.loads((job/'status.json').read_text())
    model_id=status.get('modelID',DEFAULT_MODEL_ID)
    expected_model=json.loads((directory/'request.json').read_text()).get('modelID',DEFAULT_MODEL_ID) if (directory/'request.json').exists() else DEFAULT_MODEL_ID
    if model_id != expected_model:raise ValueError('Result model mismatch')
    request_data=json.loads((directory/'request.json').read_text()) if (directory/'request.json').exists() else {'projectUID':UID}
    if status['projectUID']!=request_data['projectUID']:raise ValueError('Wrong project')
    if status['status']=='blocked-no-audio':
        save(directory/'response.json',{'requestID':directory.name,'modelID':model_id,'status':'blocked-no-audio',
             'stage':'silent','projectUID':status['projectUID'],'jobID':job.name,'snapshotSHA256':status['snapshotSHA256']})
        return
    if status['status']=='blocked-existing-titles':
        save(directory/'response.json',{'requestID':directory.name,'modelID':model_id,'status':'blocked-existing-titles',
             'stage':status['stage'],'projectUID':status['projectUID'],'jobID':job.name,'collision':status['collision'],
             'snapshotSHA256':status['snapshotSHA256']})
        return
    if status['status']!='ready':raise ValueError('Result not ready')
    if hashlib.sha256((job/'captions.json').read_bytes()).hexdigest()!=status['outputs']['captions.json']:raise ValueError('Caption checksum mismatch')
    titles={}
    for version in ('1.12','1.13','1.14'):
        name=f'TitleProbe-{version}.fcpxml';data=(job/name).read_bytes()
        if hashlib.sha256(data).hexdigest()!=status['outputs'][name]:raise ValueError('Output checksum mismatch')
        titles[version]=data.decode('utf-8')
    save(directory/'response.json',{'requestID':directory.name,'modelID':model_id,'status':'ready','stage':'ready',
         'projectUID':status['projectUID'],'jobID':job.name,'titleCount':status['titleCount'],'payloads':titles,
         'outputs':status['outputs'],'snapshotSHA256':status['snapshotSHA256'],'pcmSHA256':status['pcmSHA256'],'manifest':json.loads((job/'captions.json').read_text())})


def serve():
    BRIDGE.mkdir(parents=True,exist_ok=True);os.chmod(BRIDGE,0o700)
    lock=(BRIDGE/'worker.lock').open('w')
    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    active=None;log=None;request=None;offset=0;buffer='';ready=None;started=0;job_error=None
    try:
        while True:
            save(BRIDGE/'service.json',{'protocol':2,'models':availability(),'pid':os.getpid(),'heartbeat':time.time(),
                                      'status':'busy' if active else 'idle'})
            if active:
                code=active.poll()
                log.flush()
                with (request/'worker.log').open() as reader:
                    reader.seek(offset);buffer+=reader.read();offset=reader.tell()
                lines=buffer.split('\n');buffer=lines.pop()
                for line in lines:
                    try:event=json.loads(line)
                    except json.JSONDecodeError:continue
                    if 'stage' in event:
                        save(request/'response.json',{'requestID':request.name,'status':'running','stage':event['stage'],'progress':event.get('progress')})
                    if 'ready' in event:ready=event['ready']
                    if isinstance(event.get('error'),str):job_error=event['error'][:1000]
                cancelled=(request/'cancel.json').is_file()
                if (cancelled or time.monotonic()-started>14400) and code is None:
                    os.killpg(active.pid,signal.SIGTERM)
                    try:active.wait(timeout=5)
                    except subprocess.TimeoutExpired:os.killpg(active.pid,signal.SIGKILL);active.wait()
                    code=-1
                if code is not None:
                    try:
                        if cancelled:raise InterruptedError('已取消识别')
                        if code!=0 or ready is None:raise ValueError(job_error or 'Recognition failed; see this request worker.log')
                        publish_result(request,ready)
                    except Exception as error:save(request/'response.json',{'requestID':request.name,'status':'cancelled' if isinstance(error,InterruptedError) else 'failed','stage':'worker','error':str(error)})
                    log.close();active=None
            else:
                for candidate in sorted(BRIDGE.iterdir()):
                    if not candidate.is_dir() or candidate.is_symlink() or not valid_id(candidate.name):continue
                    if not (candidate/'request.json').exists():continue
                    response=candidate/'response.json'
                    if response.exists():
                        # Recovery of an interrupted worker is explicit, never silently rerun.
                        previous=json.loads(response.read_text())
                        if previous.get('status') in ('running','queued'):
                            save(response,{'requestID':candidate.name,'status':'failed','stage':'worker-restarted','error':'Previous worker interrupted; start a new request'})
                        continue
                    try:
                        xml=request_input(candidate)
                        request=candidate;offset=0;buffer='';ready=None;job_error=None
                        save(response,{'requestID':candidate.name,'status':'running','stage':'starting'})
                        log=(candidate/'worker.log').open('w')
                        active=subprocess.Popen(job_command(candidate),cwd=ROOT,
                                                stdout=log,stderr=subprocess.STDOUT,start_new_session=True,env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1'})
                        started=time.monotonic()
                    except Exception as error:
                        save(response,{'requestID':candidate.name,'status':'failed','stage':'request-validation','error':str(error)})
                    break
            time.sleep(0.5)
    finally:
        if active and active.poll() is None:
            os.killpg(active.pid,signal.SIGTERM)
            try:active.wait(timeout=5)
            except subprocess.TimeoutExpired:os.killpg(active.pid,signal.SIGKILL);active.wait()
        if log:log.close()
        save(BRIDGE/'service.json',{'protocol':2,'status':'stopped','heartbeat':0})

if __name__=='__main__':
    def stop(signum,frame):raise SystemExit(0)
    signal.signal(signal.SIGTERM,stop)
    serve()
