"""Local phrase-aware subtitle boundaries; never rewrite words or invent timings."""
import re
from .text_units import clean_generated_text, display_length

LEAD_INS = ('其实', '但是', '不过', '所以', '因此', '而且', '并且', '另外', '然后', '比如', '例如')


def coordinated_ranges(text):
    """Keep short noun/verb+noun pairs together, e.g. 使用体验和研究成果."""
    if not re.search(r"[\u3400-\u9fff]",text):return []
    import jieba.posseg
    tokens=[];cursor=0
    for token in jieba.posseg.cut(text, HMM=False):
        tokens.append((token.word, token.flag, cursor, cursor+len(token.word)))
        cursor+=len(token.word)
    spans=[m.span() for m in re.finditer(r"(?:最近|过去|未来|接下来)?(?:这|那|一|几)(?:段时间|个月|星期|周|年|天)",text)]
    for i in range(len(tokens)-2):
        if tokens[i][0] in ('这','那','一','几') and tokens[i+1][1].startswith('q') and tokens[i+2][1].startswith('n'):
            left=i-1 if i and tokens[i-1][1].startswith('t') else i
            if tokens[i+2][3]-tokens[left][2]<=10:spans.append((tokens[left][2],tokens[i+2][3]))
    for i,(word,_,_,_) in enumerate(tokens):
        if word not in ('和','与','及') or i==0 or i+1==len(tokens):continue
        left,right=i-1,i+1
        if not all(tokens[n][1].startswith(('n','v')) for n in (left,right)):continue
        if left>0 and tokens[left][1].startswith('n') and tokens[left-1][1].startswith('v') and len(tokens[left-1][0]+tokens[left][0])<=6:left-=1
        if right+1<len(tokens) and tokens[right][1].startswith('v') and tokens[right+1][1].startswith('n') and len(tokens[right][0]+tokens[right+1][0])<=6:right+=1
        start,end=tokens[left][2],tokens[right][3]
        if end-start<=12:spans.append((start,end))
    return spans


def phrase_partition(words, max_chars, max_duration, punctuation_boundary):
    """Choose measured lexical boundaries for one uninterrupted spoken block."""
    count=len(words)
    if not count:return []
    clean=[clean_generated_text(w.text) for w in words]
    # Prefer readable short-video clauses without chopping every sentence to a
    # fixed length. Semantic cues can outweigh a modestly shorter line.
    costs=[float('inf')]*(count+1);paths=[None]*(count+1);costs[0]=0
    for end in range(1,count+1):
        for start in range(end-1,-1,-1):
            text=''.join(clean[start:end]);length=display_length(text)
            duration=words[end-1].end-words[start].start
            if end-start>1 and (length>max_chars or duration>max_duration):break
            cost=3.5 + max(0,length-14)**2*.22 + max(0,5-length)**2*.65
            if text.endswith(LEAD_INS):cost+=15
            if text.endswith(('的','把','被','和','与','及','在','将','这','那','对','给','从')):cost+=7
            if text.startswith(('和','与','及','的','了','着','过')):cost+=8
            if end<count:
                left=''.join(clean[start:end]);right=''.join(clean[end:])
                pause=words[end].start-words[end-1].end
                cost-=min(1.5,max(0,pause)*5)
                if punctuation_boundary(words[end-1].text,words[end].text):cost-=2
                if right.startswith(LEAD_INS) and length>=5:cost-=3
                # An introductory question clause has a useful short-video cut.
                # Avoid treating every occurrence of 为什么 as a mandatory cut.
                if re.search(r'(?:不知道|知道|想知道|解释|告诉你)为什么$',left) and display_length(right)>=5:cost-=3
            candidate=costs[start]+cost
            if candidate<costs[end]:costs[end]=candidate;paths[end]=start
    chunks=[];end=count
    while end:
        start=paths[end]
        if start is None:raise ValueError('无法在已测量的词边界断句')
        chunks.append(words[start:end]);end=start
    return list(reversed(chunks))
