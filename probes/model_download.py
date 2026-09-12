"""Explicit pinned model downloads, resumable bytes and atomic publication."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import time
import urllib.request
import urllib.error
from .models import ROOT, CATALOG, model_spec, check_files
from .run_job import save

class Cancelled(Exception):pass

def safe_directory(base,name):
    if base.is_symlink():raise ValueError("Linked model root refused")
    base.mkdir(parents=True,exist_ok=True)
    path=base/name
    if path.is_symlink() or not path.resolve().is_relative_to(base.resolve()):raise ValueError('Linked model directory refused')
    path.mkdir(exist_ok=True)
    return path

def transfer(url,path,size,digest,cancel,progress,opener=urllib.request.urlopen):
    """Only publish complete, verified bytes; failed/cancelled partials can resume."""
    partial=path.with_name(path.name+'.part')
    if path.is_symlink() or partial.is_symlink():raise ValueError('Linked model file refused')
    def verify(source):
        h=hashlib.sha256()
        with source.open('rb') as f:
            while block:=f.read(4*1024*1024):
                if cancel():raise Cancelled()
                h.update(block)
        return h.hexdigest()==digest
    if path.exists() and path.stat().st_size==size and verify(path):
        if partial.exists():partial.unlink()
        progress(size,'checking');return
    if path.exists():path.unlink()
    offset=partial.stat().st_size if partial.exists() else 0
    if offset>size:partial.unlink();offset=0
    if cancel():raise Cancelled()
    if offset<size:
        headers={'User-Agent':'SubPop/0.1','Accept-Encoding':'identity'}
        if offset:headers['Range']=f'bytes={offset}-'
        with opener(urllib.request.Request(url,headers=headers),timeout=20) as response:
            if offset and response.status!=206:offset=0
            if response.status==206 and not response.headers.get('Content-Range','').startswith(f'bytes {offset}-'):
                raise ValueError('下载服务器返回了错误的续传范围')
            with partial.open('ab' if offset else 'wb') as out:
                progress(offset,'resuming')
                while True:
                    if cancel():raise Cancelled()
                    block=response.read(256*1024)
                    if not block:break
                    offset+=len(block)
                    if offset>size:raise ValueError('下载文件大于预期大小')
                    out.write(block);progress(offset,'downloading')
    progress(offset,'checking')
    if offset!=size:raise ValueError('下载未完成，请重试以继续下载')
    if not verify(partial):
        partial.unlink();raise ValueError('文件校验失败，请重试下载')
    partial.replace(path)

def install(model_id,root=ROOT,cancel=lambda:False,emit=lambda value:None,opener=urllib.request.urlopen):
    specs=[model_spec(model_id),CATALOG['aligner']]
    total=sum(sum(s['files'].values()) for s in specs);done=0;started=time.monotonic();network=0;last_emit=0
    base=root/'.subloom/models'
    missing=sum(size for spec in specs for name,size in spec['files'].items() if not (base/spec['directory']/name).is_file())
    base.mkdir(parents=True,exist_ok=True)
    if shutil.disk_usage(base).free<missing+256*1024*1024:raise ValueError('磁盘空间不足，请腾出空间后重试')
    for spec in specs:
        directory=safe_directory(base,spec['directory'])
        for name,size in spec['files'].items():
            prior=0
            def progress(value,stage):
                nonlocal network,prior,last_emit
                if stage=='downloading':network+=max(0,value-prior)
                prior=value;now=time.monotonic()
                if now-last_emit>=0.15 or stage=='checking':
                    emit({'stage':stage,'completedBytes':done+value,'totalBytes':total,'progress':(done+value)/total,'bytesPerSecond':network/max(now-started,1),'file':name})
                    last_emit=now
            emit({'stage':'checking','completedBytes':done,'totalBytes':total,'progress':done/total,'file':name})
            url=f"https://huggingface.co/{spec['repository']}/resolve/{spec['revision']}/{name}"
            transfer(url,directory/name,size,spec['sha256'][name],cancel,progress,opener)
            done+=size
        check_files(spec,root)
    emit({'stage':'ready','completedBytes':total,'totalBytes':total,'progress':1})

def execute(directory,root=ROOT):
    request=json.loads((directory/'request.json').read_text());spec=model_spec(request['modelID'])
    state={'requestID':directory.name,'modelID':spec['id'],'operation':request['operation'],'status':'running','stage':'connecting'}
    def emit(value):state.update(value);save(directory/'response.json',state)
    try:
        emit({})
        if request['operation']=='install':install(spec['id'],root,lambda:(directory/'cancel.json').exists(),emit)
        elif request['operation']=='remove':
            # Shared aligner is retained for the other recognition model.
            base=root/'.subloom/models';path=base/spec['directory']
            if path.is_symlink() or not path.resolve().is_relative_to(base.resolve()):raise ValueError('Linked model refused')
            if path.exists():shutil.rmtree(path)
        else:raise ValueError('Unknown model operation')
        emit({'status':'ready','stage':'ready'})
    except Cancelled:emit({'status':'cancelled','stage':'cancelled','error':'已暂停下载，重试可继续'})
    except Exception as error:
        message=str(error)[:200]
        if isinstance(error,urllib.error.URLError):message='无法连接模型下载服务器，请检查网络后重试'
        elif isinstance(error,TimeoutError):message='下载连接超时，重试可继续下载'
        elif isinstance(error,OSError):message='模型文件读写失败，请检查磁盘空间和文件权限'
        emit({'status':'failed','stage':'failed','error':message,'detail':str(error)[:500]})

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--request',type=Path,required=True);a=p.parse_args();execute(a.request)
