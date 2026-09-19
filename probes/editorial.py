"""SubPop adapter for the subtitle presentation rules ported from VinciSub."""
from fractions import Fraction
from .caption_fixture import spoken, quantize, captions
from .editorial_rules import Word, make_captions, bridge_brief_gaps
from .text_units import clean_generated_text
from .vocabulary import canonical_words

RULES_VERSION='semantic-phrases-v3-vocabulary'


def measured_words(data):
    result=[]
    duration=Fraction(data['snapshot']['duration'])
    for part in data['results']:
        text=part['text'];words=part['words']
        if ''.join(spoken(w['text']) for w in words)!=spoken(text):
            raise ValueError('Transcript and alignment differ; do not invent timestamps')
        cursor=0;previous=Fraction(0)
        for word in words:
            start,end=Fraction(str(word['start'])),Fraction(str(word['end']))
            target=spoken(word['text'])
            if not target or start<previous or end<start or end>duration:
                raise ValueError('Invalid or overlapping alignment')
            previous=end
            first=cursor;matched=''
            while cursor<len(text) and len(matched)<len(target):
                matched+=spoken(text[cursor]);cursor+=1
            while cursor<len(text) and not spoken(text[cursor]):cursor+=1
            if matched!=target:raise ValueError('Aligned token does not match transcript')
            result.append(Word(text[first:cursor],float(start),float(end)))
        if cursor!=len(text):raise ValueError('Unconsumed transcript')
    return result


def optimized_captions(data, fps, vocabulary=(), max_chars=20, warnings=None):
    raw=[];fps=Fraction(fps)
    for index,part in enumerate(data['results']):
        scoped={**data,'results':[part]}
        words=canonical_words(measured_words(scoped),vocabulary)
        # The timing fallback must use the same canonical transcript as the normal path.
        scoped={**scoped,'results':[{'text':''.join(w.text for w in words),
            'words':[dict(text=w.text,start=w.start,end=w.end) for w in words]}]}
        try:
            arranged=make_captions(words,max_chars=max_chars,protected_terms=vocabulary)
            current=[dict(text=c.text,start=Fraction(str(c.start)),end=Fraction(str(c.end))) for c in arranged]
        except ValueError:
            # Preserve the proven SubPop sentence spans when the stricter
            # reference rules cannot place instantaneous words reliably.
            if warnings is not None:warnings.append({'part':index,'reason':'alignment-review'})
            try:
                current=[dict(text=c['text'],start=Fraction(c['start_frame'],fps),end=Fraction(c['end_frame'],fps))
                         for c in captions(scoped,fps,True)]
            except ValueError:
                if not words or any(w.start!=w.end for w in words):raise
                if not raw:raise ValueError('首段词语缺少有效时长，需要重新对齐')
                raw[-1]['text']+=scoped['results'][0]['text'];raw[-1]['end']=max(raw[-1]['end'],Fraction(str(words[-1].end)))
                continue
        for row in current:
            if raw and row['start']<raw[-1]['end']:
                raw[-1]['text']+=row['text'];raw[-1]['end']=max(raw[-1]['end'],row['end'])
            else:raw.append(row)
    for i,row in enumerate(raw):
        row['text']=clean_generated_text(row['text'])
        if i+1<len(raw) and 0<raw[i+1]['start']-row['end']<=Fraction(1,5):row['end']=raw[i+1]['start']
    return quantize([r for r in raw if r['text']],Fraction(data['snapshot']['duration']),fps)
