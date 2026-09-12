"""Build a reviewable SRT from aligned text, for the isolated full-project experiment."""
import argparse
from fractions import Fraction
import json
from pathlib import Path
import re
import unicodedata


def spoken(text):
    return ''.join(c for c in text if not c.isspace() and not unicodedata.category(c).startswith('P'))


def captions(data, fps=25):
    if not isinstance(fps,int) or fps<=0:raise ValueError('Positive integer frame rate required')
    duration = Fraction(data['snapshot']['duration'])
    if data['snapshot']['project'] != 'Subloom-Original' or Fraction(data['snapshot']['relative_start']) != 0:
        raise ValueError('Only the complete isolated original project is supported')
    rows=[]
    for part in data['results']:
        words=part['words']
        if not words or ''.join(spoken(w['text']) for w in words) != spoken(part['text']):
            raise ValueError('Transcript and alignment differ; do not invent timestamps')
        previous=Fraction(0)
        for w in words:
            start,end=Fraction(str(w['start'])),Fraction(str(w['end']))
            if not spoken(w['text']) or start<previous or end<start or end>duration:
                raise ValueError('Invalid or overlapping alignment')
            previous=end
        segments=[]; pending=''
        for text in re.findall(r'[^，。！？；!?;]+[，。！？；!?;]*',part['text']):
            pending += text
            if len(spoken(pending))>=4 or pending.endswith(('。','！','？','!','?')):
                segments.append(pending);pending=''
        if pending:
            if segments:segments[-1]+=pending
            else:segments.append(pending)
        if ''.join(segments)!=part['text']:raise ValueError('Unsupported punctuation layout')
        cursor=0
        for text in segments:
            first=cursor;matched=''
            while cursor<len(words) and len(matched)<len(spoken(text)):
                matched+=spoken(words[cursor]['text']);cursor+=1
            if matched!=spoken(text):raise ValueError('A segment cuts an aligned token')
            start=Fraction(str(words[first]['start']));end=Fraction(str(words[cursor-1]['end']))
            start_frame=(start*fps).__floor__();end_frame=(end*fps).__ceil__()
            if end_frame<=start_frame or Fraction(end_frame,fps)>duration:raise ValueError('Invalid caption duration')
            if rows and start_frame<rows[-1]['end_frame']:raise ValueError('Quantized captions overlap')
            rows.append(dict(text=text,start_frame=start_frame,end_frame=end_frame))
        if cursor!=len(words):raise ValueError('Unconsumed alignment')
    return rows


def srt(rows,fps=25):
    def time(frame):
        value=Fraction(frame*1000,fps)
        if value.denominator!=1:raise ValueError('Fixture requires exact millisecond frame boundaries')
        ms=int(value);hours,ms=divmod(ms,3600000);minutes,ms=divmod(ms,60000);seconds,ms=divmod(ms,1000)
        return f'{hours:02}:{minutes:02}:{seconds:02},{ms:03}'
    return ''.join(f"{i}\n{time(row['start_frame'])} --> {time(row['end_frame'])}\n{row['text']}\n\n" for i,row in enumerate(rows,1))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--asr',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();data=json.loads(args.asr.read_text());rows=captions(data)
    args.output.write_text(srt(rows),encoding='utf-8')
    args.output.with_suffix('.json').write_text(json.dumps({'projectUID':data['snapshot']['uid'],'pcmSHA256':data['pcm_sha256'],'fps':25,'captions':rows},ensure_ascii=False,indent=2)+'\n')
    print(srt(rows))
