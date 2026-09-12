"""Normalize only proven silent Basic Titles; preserve original snapshot for conflicts."""
from fractions import Fraction
import xml.etree.ElementTree as ET
from .title_fixture import EFFECT
from .readback import seconds


def prepare(data, generic=False):
    if len(data)>16*1024*1024 or b'<!ENTITY' in data.upper():raise ValueError('Unsafe snapshot size or entity declaration')
    root=ET.fromstring(data)
    projects=root.findall('.//project')
    if len(projects)!=1:raise ValueError('One project required')
    seq=projects[0].find('sequence');spine=seq.find('spine') if seq is not None else None
    if spine is None or not 1<=len(spine)<=(5000 if generic else 64) or any(c.tag not in ('asset-clip','gap') for c in spine):raise ValueError('Consecutive clips/gaps required')
    effects={e.get('id'):e.get('uid') for e in root.findall('resources/effect')}
    duration=seconds(seq.get('duration','0s'));existing=[]
    fmt=root.find(f"resources/format[@id='{seq.get('format')}']")
    fps=1/seconds(fmt.get('frameDuration','1/25s')) if generic and fmt is not None else Fraction(25)
    def clips(nodes, origin, parent_start):
        for clip in nodes:
            if clip.tag not in ('asset-clip','gap'):continue
            asset=root.find(f"resources/asset[@id='{clip.get('ref')}']")
            start=seconds(clip.get('start',asset.get('start','0s') if asset is not None else '0s'))
            position=origin+seconds(clip.get('offset','0s'))-parent_start
            yield clip,position-start
            if generic:yield from clips(list(clip),position,start)
    for clip,base in clips(spine,Fraction(0),seconds(seq.get('tcStart','0s'))):
        asset=root.find(f"resources/asset[@id='{clip.get('ref')}']")
        clip_start=seconds(clip.get('start',asset.get('start','0s') if asset is not None else '0s'))
        for title in list(clip):
            if title.tag!='title':continue
            if effects.get(title.get('ref'))!=EFFECT:raise ValueError('Unverified title template')
            if set(title.attrib)-{'ref','lane','offset','start','duration','name','enabled','role'}:raise ValueError('Unverified title attributes')
            if any(child.tag not in (('text','text-style-def','param','adjust-transform') if generic else ('text','text-style-def','param')) for child in title):raise ValueError('Title audio, effects or nested items unverified')
            for child in title:
                if generic and child.tag=='adjust-transform':
                    if len(child) or set(child.attrib)-{'position','scale','rotation','anchor','enabled'}:raise ValueError('Unsupported title transform')
                    continue
                if child.tag=='param':
                    if len(child) or set(child.attrib)-{'name','key','value'} or child.get('key') not in ('9999/999166631/999166633/2/351','9999/999166631/999166633/2/354/999169573/401'):
                        raise ValueError('Unverified Basic Title parameter')
                    continue
                if any(t.tag!='text-style' or len(t) for t in child):raise ValueError('Unsupported title text structure')
            start=base+seconds(title.get('offset','0s'));end=start+seconds(title.get('duration','0s'))
            if not 0<=start<end<=duration or (start*fps).denominator!=1 or (end*fps).denominator!=1:raise ValueError('Invalid title timing')
            existing.append({'text':''.join(''.join(t.itertext()) for t in title.findall('text')).strip(),
                             'start_frame':int(start*fps),'end_frame':int(end*fps),'enabled':title.get('enabled','1')!='0'})
            clip.remove(title)
    return ET.tostring(root,encoding='utf-8'),existing


def collision(rows,existing):
    exact=sum(any(e['enabled'] and all(e[k]==row[k] for k in ('text','start_frame','end_frame')) for e in existing) for row in rows)
    overlaps=sum(any(e['start_frame']<row['end_frame'] and row['start_frame']<e['end_frame'] for e in existing) for row in rows)
    # Never overwrite proofreading, duplicate an existing title, or infer ownership.
    return {'status':'duplicate' if rows and exact==len(rows) else ('conflict' if overlaps else 'clear'),
            'exactMatches':exact,'overlappingRows':overlaps,'existingTitles':len(existing)}
