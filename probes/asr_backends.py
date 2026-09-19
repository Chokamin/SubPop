"""Local-only alternate engines, emitting measured word times for shared editorial rules."""
import math
import re
from .caption_fixture import spoken


def timed_row(words, duration):
    result=[]
    for text,start,end in words:
        text=re.sub(r'<\|[^|]+\|>', '', text).strip()
        if not text:continue
        start,end=float(start),float(end)
        if not all(math.isfinite(x) for x in (start,end)) or start<0 or end<start or start>duration:
            raise ValueError('识别模型返回了无效时间，请重试')
        if not spoken(text):
            if result:result[-1]['text']+=text
            continue
        if result and result[-1]['text'][-1:].isascii() and result[-1]['text'][-1:].isalnum() and text[:1].isascii() and text[:1].isalnum():text=' '+text
        result.append(dict(text=text,start=start,end=min(end,duration)))
    return dict(text=''.join(w['text'] for w in result),words=result) if result else None


def load_backend(engine,path,hints):
    if engine=='mlx-whisper':
        import mlx_whisper
        def transcribe(samples):
            output=mlx_whisper.transcribe(samples,path_or_hf_repo=str(path),language='zh',word_timestamps=True,
                initial_prompt=hints or None,condition_on_previous_text=False,verbose=False)
            rows=[]
            for segment in output['segments']:
                words=segment.get('words',[])
                if segment.get('text','').strip() and not words:raise ValueError('Whisper 未返回逐词时间')
                row=timed_row([(w['word'],w['start'],w['end']) for w in words],len(samples)/16000)
                if row:rows.append(row)
            return rows
        return transcribe
    if engine=='sensevoice':
        from funasr import AutoModel
        model=AutoModel(model=str(path),device='cpu',trust_remote_code=False,disable_update=True,disable_pbar=True)
        def transcribe(samples):
            output=model.generate(input=samples,fs=16000,language='zh',use_itn=True,output_timestamp=True,cache={})
            rows=[]
            for part in output:
                words,times=part.get('words',[]),part.get('timestamp',[])
                spoken=re.sub(r'<\|[^|]+\|>', '',part.get('text','')).strip()
                if spoken and (not words or len(words)!=len(times)):raise ValueError('SenseVoice 未返回完整逐词时间')
                row=timed_row([(w,t[0]/1000,t[1]/1000) for w,t in zip(words,times)],len(samples)/16000)
                if row:rows.append(row)
            return rows
        return transcribe
    raise ValueError('Unknown ASR engine')
