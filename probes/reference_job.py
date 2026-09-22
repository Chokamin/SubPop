"""Local text-only refinement. No ASR, media reads, credentials or network."""
import json
from pathlib import Path
from .reference_script import validate, digest, refine_rows
from .run_job import save
from .vocabulary import validate as validate_vocabulary


def read_request(directory):
    from .worker import valid_id, MAX_REQUEST
    path=directory/'request.json'
    if directory.is_symlink() or not valid_id(directory.name) or path.is_symlink() or path.stat().st_size>MAX_REQUEST:
        raise ValueError('无效的脚本整理请求')
    request=json.loads(path.read_text())
    if request.get('requestID')!=directory.name or request.get('kind')!='reference' or not isinstance(request.get('projectUID'),str) or not request['projectUID']:
        raise ValueError('脚本整理项目不匹配')
    if not validate(request.get('referenceScript','')):raise ValueError('请先填写参考脚本')
    if not isinstance(request.get('captions'),list):raise ValueError('缺少当前字幕')
    validate_vocabulary(request.get('vocabulary',[]))
    return request


def run(directory):
    request=read_request(directory)
    rows,report=refine_rows(request['captions'],request['referenceScript'],validate_vocabulary(request.get('vocabulary',[])))
    save(directory/'response.json',dict(requestID=directory.name,status='ready',kind='reference',
         projectUID=request['projectUID'],referenceSHA256=digest(request['referenceScript']),
         captions=rows,referenceReview=report))


if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--request',required=True,type=Path)
    run(parser.parse_args().request)
