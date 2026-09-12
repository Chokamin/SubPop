"""Build a reviewable SRT from aligned text, for the isolated full-project experiment."""
import argparse
from fractions import Fraction
import json
from pathlib import Path
import re
import unicodedata


def spoken(text):
    return ''.join(c for c in text if not c.isspace() and not unicodedata.category(c).startswith('P'))


def captions(data, fps=25, generic=False):
    fps=Fraction(fps)
    if fps<=0:raise ValueError('Positive frame rate required')
    duration = Fraction(data['snapshot']['duration'])
    if (not generic and data['snapshot']['project'] != 'Subloom-Original') or Fraction(data['snapshot']['relative_start']) != 0:
        raise ValueError('Only the complete isolated original project is supported')
    raw=[]
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
        # Punctuation can split one aligner token (e.g. a number or phrase).
        # Only emit a sentence boundary where a measured token actually ends.
        token_ends=set();count=0
        for word in words:
            count+=len(spoken(word['text']));token_ends.add(count)
        safe=[];pending='';count=0
        for text in segments:
            pending+=text;count+=len(spoken(text))
            if count in token_ends:safe.append(pending);pending=''
        if pending:raise ValueError('Unconsumed sentence text')
        segments=safe
        cursor=0
        for text in segments:
            first=cursor;matched=''
            while cursor<len(words) and len(matched)<len(spoken(text)):
                matched+=spoken(words[cursor]['text']);cursor+=1
            if matched!=spoken(text):raise ValueError('A segment cuts an aligned token')
            start=Fraction(str(words[first]['start']));end=Fraction(str(words[cursor-1]['end']))
            if raw and start<raw[-1]['start']:raise ValueError('Caption order is invalid')
            if raw and (start<raw[-1]['end'] or start==end or raw[-1]['start']==raw[-1]['end']):
                # Adjacent recognition chunks can have overlapping alignment.
                # Keep their text together over the measured union, never drop it.
                raw[-1]['text']+=text;raw[-1]['end']=max(raw[-1]['end'],end)
            else:raw.append(dict(text=text,start=start,end=end))
        if cursor!=len(words):raise ValueError('Unconsumed alignment')
    rows=[]
    for row in raw:
        start=(row['start']*fps).__floor__();end=(row['end']*fps).__ceil__()
        if end<=start or Fraction(end,fps)>duration:raise ValueError('Invalid caption duration')
        if rows and start<rows[-1]['end_frame']:
            # Outward rounding can make disjoint intervals share one frame.
            # Use a shared boundary nearest to the measured gap's midpoint.
            boundary=round((raw_end+row['start'])*fps/2)
            lower=rows[-1]['start_frame']+1;upper=end-1
            if lower<=upper:
                boundary=max(lower,min(upper,boundary))
                rows[-1]['end_frame']=boundary;start=boundary
            else:
                rows[-1]['text']+=row['text'];rows[-1]['end_frame']=end
                raw_end=row['end'];continue
        rows.append(dict(text=row['text'],start_frame=start,end_frame=end))
        raw_end=row['end']
    return rows


def srt(rows,fps=25):
    def time(frame):
        value=Fraction(frame*1000)/Fraction(fps)
        ms=round(value);hours,ms=divmod(ms,3600000);minutes,ms=divmod(ms,60000);seconds,ms=divmod(ms,1000)
        return f'{hours:02}:{minutes:02}:{seconds:02},{ms:03}'
    return ''.join(f"{i}\n{time(row['start_frame'])} --> {time(row['end_frame'])}\n{row['text']}\n\n" for i,row in enumerate(rows,1))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--asr',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();data=json.loads(args.asr.read_text());rows=captions(data)
    args.output.write_text(srt(rows),encoding='utf-8')
    args.output.with_suffix('.json').write_text(json.dumps({'projectUID':data['snapshot']['uid'],'pcmSHA256':data['pcm_sha256'],'fps':25,'captions':rows},ensure_ascii=False,indent=2)+'\n')
    print(srt(rows))
