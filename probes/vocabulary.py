"""Bounded recognition hints. Audio remains authoritative; no text replacement."""
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
