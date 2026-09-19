"""Bounded recognition hints and conservative dictionary spelling normalization."""
import re

def parse(text):
    if not isinstance(text,str):raise ValueError('词库必须为文本')
    terms=list(dict.fromkeys(t.strip() for t in re.split(r'[\n\r,，;；、]+',text) if t.strip()))
    if len(terms)>100 or sum(map(len,terms))>2000:raise ValueError('词库最多100个词、合计2000字')
    if any(len(t)>64 or any(ord(c)<32 or ord(c)==127 for c in t) for t in terms):raise ValueError('每个词最多64字，不支持控制字符')
    return terms

def validate(terms):
    if not isinstance(terms,list) or any(not isinstance(t,str) for t in terms):raise ValueError('Invalid vocabulary')
    return parse('\n'.join(terms))

def context(terms):return '，'.join(validate(terms))


def _chinese_integer(value):
    if not 0 <= value < 10000:
        return None
    digits='零一二三四五六七八九'
    if value == 0:return digits[0]
    result='';pending_zero=False
    for divisor,unit in ((1000,'千'),(100,'百'),(10,'十'),(1,'')):
        digit,value=divmod(value,divisor)
        if digit:
            if pending_zero:result+='零'
            result+=digits[digit]+unit;pending_zero=False
        elif result and value:pending_zero=True
    return result[1:] if result.startswith('一十') else result


def canonical_words(words, terms):
    """Unify complete dictionary spellings while keeping measured token spans.

    Only case/spacing and equivalent integer notation vary; no fuzzy homophones.
    Matching cannot cross sentence punctuation or a substantial audio pause.
    """
    from .editorial_rules import Word
    terms=validate(list(terms))
    if not terms:return words
    text=''.join(w.text for w in words)
    candidates=[]
    for term in terms:
        pieces=[]
        for token in re.findall(r'[0-9]+|[^\s]',term):
            variants=[token]
            if token.isascii() and token.isdigit() and len(token)<=4 and (token=='0' or not token.startswith('0')):
                variants += [_chinese_integer(int(token)), ''.join('零一二三四五六七八九'[int(c)] for c in token)]
            pieces.append('(?:'+'|'.join(re.escape(v) for v in dict.fromkeys(variants))+')')
        pattern=r'\s*'.join(pieces)
        # Do not replace part of a larger Latin name or numeric model identifier.
        if term[0].isascii() and term[0].isalnum():pattern=r'(?<![A-Za-z0-9])'+pattern
        if term[-1].isascii() and term[-1].isalnum():pattern+=r'(?![A-Za-z0-9])'
        candidates.extend((m.start(),m.end(),term) for m in re.finditer(pattern,text,re.IGNORECASE))
    # Prefer a longer term at the same starting position; never cascade rewrites.
    chosen=[];end=-1
    for start,stop,term in sorted(candidates,key=lambda x:(x[0],-(x[1]-x[0]),terms.index(x[2]))):
        if start>=end:chosen.append((start,stop,term));end=stop
    spans=[];offset=0
    for w in words:spans.append((offset,offset+len(w.text)));offset+=len(w.text)
    groups=[]
    for start,stop,term in chosen:
        indices=[i for i,(a,b) in enumerate(spans) if a<stop and b>start]
        if not indices:continue
        first,last=indices[0],indices[-1]
        if any(words[i+1].start-words[i].end>.5 for i in range(first,last)):continue
        if groups and first<=groups[-1][1]:
            groups[-1][1]=max(last,groups[-1][1]);groups[-1][2].append((start,stop,term))
        else:groups.append([first,last,[(start,stop,term)]])
    output=list(words)
    for first,last,matches in reversed(groups):
        origin=spans[first][0];replacement=text[origin:spans[last][1]]
        for start,stop,term in reversed(matches):replacement=replacement[:start-origin]+term+replacement[stop-origin:]
        output[first:last+1]=[Word(replacement,words[first].start,words[last].end)]
    return output
