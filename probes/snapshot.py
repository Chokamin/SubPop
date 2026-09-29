"""Remove silent timeline titles from the audio copy; preserve collision data."""
from fractions import Fraction
import xml.etree.ElementTree as ET
from .title_fixture import EFFECT
from .readback import seconds
from .project import inverse_retime_ranges,linear_time_map

NATIVE_SUBTITLE_EFFECT='.../Titles.localized/Subtitles.localized/Subtitle.localized/Subtitle.moti'
SILENT_TITLE_EFFECTS={EFFECT,NATIVE_SUBTITLE_EFFECT}


def title_has_audio(title, resources):
    """Inspect timeline content, not a title plug-in's visual parameter shape.

    A title may contain arbitrary Motion controls and video effects. A nested
    audio clip or compound media, however, cannot be removed from the audio
    copy without changing what the user hears.
    """
    audio_tags={'audio','audio-channel-source','filter-audio','adjust-volume',
                'audio-role-source','sync-clip','mc-clip','ref-clip','audition'}
    media_tags={'asset-clip','clip','video','gap'}
    for node in title.iter():
        if node is title:continue
        tag=node.tag.lower()
        if tag in audio_tags or 'audio' in tag or 'sound' in tag:return True
        ref=node.get('ref')
        resource=resources.get(ref) if ref else None
        if resource is not None and resource.tag=='media':return True
        if node.tag in media_tags:
            if node.tag in ('asset-clip','clip') and node.get('srcEnable')!='video':
                if resource is None or resource.tag!='asset' or resource.get('hasAudio')!='0':return True
            elif node.tag=='video' and ref and (resource is None or resource.tag not in ('asset','effect')):
                return True
        elif resource is not None and resource.tag=='asset' and resource.get('hasAudio')!='0':
            return True
    return False


def prepare(data, generic=False):
    if len(data)>16*1024*1024 or b'<!ENTITY' in data.upper():raise ValueError('Unsafe snapshot size or entity declaration')
    root=ET.fromstring(data)
    projects=root.findall('.//project')
    if len(projects)!=1:raise ValueError('One project required')
    seq=projects[0].find('sequence');spine=seq.find('spine') if seq is not None else None
    story_tags=('asset-clip','gap','clip','audio','video','ref-clip') if generic else ('asset-clip','gap')
    root_tags=(*story_tags,'title') if generic else story_tags
    if spine is None or not 1<=len(spine)<=(5000 if generic else 64) or any(c.tag not in root_tags for c in spine):raise ValueError('暂不支持此时间线结构；请展开多机位后重试' if generic else 'Consecutive clips/gaps required')
    effects={e.get('id'):e.get('uid') for e in root.findall('resources/effect')}
    resource_root=root.find('resources')
    resources={e.get('id'):e for e in resource_root if e.get('id')} if resource_root is not None else {}
    duration=seconds(seq.get('duration','0s'));existing=[]
    fmt=root.find(f"resources/format[@id='{seq.get('format')}']")
    fps=1/seconds(fmt.get('frameDuration','1/25s')) if generic and fmt is not None else Fraction(25)
    def titles(nodes,origin,parent_start,parent,bounds,media_stack=(),warps=()):
        for clip in nodes:
            if clip.tag=='title':
                begin=origin+seconds(clip.get('offset','0s'))-parent_start
                end=begin+seconds(clip.get('duration','0s'))
                intervals=[(max(begin,bounds[0]),min(end,bounds[1]))]
                for mapping,mapped_origin,mapped_bounds in warps:
                    intervals=[(out_begin,out_end) for left,right in intervals if right>left
                               for _,_,out_begin,out_end in inverse_retime_ranges(
                                   left,right,mapping,mapped_origin,mapped_bounds)]
                visible=(min((a for a,b in intervals),default=begin),max((b for a,b in intervals),default=begin))
                yield clip,visible,parent,bool(warps)
                continue
            if clip.tag not in story_tags:continue
            asset=resources.get(clip.get('ref')) if clip.tag in ('asset-clip','audio') else None
            media=resources.get(clip.get('ref')) if clip.tag=='ref-clip' else None
            media_seq=media.find('sequence') if media is not None and media.tag=='media' else None
            if clip.tag=='ref-clip' and (media_seq is None or clip.get('ref') in media_stack):
                raise ValueError('复合片段引用缺失或形成循环')
            default_start=asset.get('start','0s') if asset is not None else media_seq.get('tcStart','0s') if media_seq is not None else '0s'
            start=seconds(clip.get('start',default_start))
            position=origin+seconds(clip.get('offset','0s'))-parent_start
            length=seconds(clip.get('duration','0s'))
            # Audio-only validation runs later. A visual reverse with no titles
            # must not be rejected while stripping unrelated title layers.
            has_nested_titles=any(node.tag=='title' for node in clip.iter()) or (
                media_seq is not None and media_seq.find('.//title') is not None)
            retime=linear_time_map(clip,length) if clip.find('timeMap') is not None and has_nested_titles else None
            children=list(clip) if generic else [c for c in clip if c.tag=='title']
            if retime:
                mapping,_=retime
                local_bounds=(mapping[0][2],mapping[-1][3])
                output_bounds=(max(bounds[0],position),min(bounds[1],position+length))
                yield from titles(children,Fraction(0),Fraction(0),clip,local_bounds,media_stack,
                                  ((mapping,position,output_bounds),*warps))
            else:
                yield from titles(children,position,start,clip,bounds,media_stack,warps)
            if media_seq is not None:
                inner_spine=media_seq.find('spine')
                if inner_spine is None or len(media_seq.findall('spine'))!=1:
                    raise ValueError('复合片段缺少完整内部时间线')
                inner_bounds=max(bounds[0],position),min(bounds[1],position+length)
                if retime:
                    mapping,_=retime
                    yield from titles(list(inner_spine),Fraction(0),Fraction(0),inner_spine,
                                      (mapping[0][2],mapping[-1][3]),(*media_stack,clip.get('ref')),
                                      ((mapping,position,inner_bounds),*warps))
                else:
                    yield from titles(list(inner_spine),position,start,inner_spine,inner_bounds,
                                      (*media_stack,clip.get('ref')),warps)
    stripped={}
    for title,visible,parent,retimed in titles(spine,Fraction(0),seconds(seq.get('tcStart','0s')),spine,(Fraction(0),duration)):
        effect=effects.get(title.get('ref'))
        known=effect in SILENT_TITLE_EFFECTS
        if generic:
            if not effect:raise ValueError('标题模板引用缺失')
            if any('audio' in key.lower() or key in ('srcCh','outCh','srcID') for key in title.attrib):
                raise ValueError('标题包含可能有声音的属性，暂不能安全提取音频')
            if title_has_audio(title,resources):raise ValueError('标题包含可能有声音的内容，暂不能安全提取音频')
        elif not known:raise ValueError('Unverified title template')
        if not generic and set(title.attrib)-{'ref','lane','offset','start','duration','name','enabled','role'}:raise ValueError('Unverified title attributes')
        if not generic:
            if any(child.tag not in ('text','text-style-def','param') for child in title):raise ValueError('Title audio, effects or nested items unverified')
            for child in title:
                if child.tag=='param':
                    basic_keys=('9999/999166631/999166633/2/351','9999/999166631/999166633/2/354/999169573/401')
                    key=child.get('key','')
                    native_key=key.startswith('9999/') and all(part.isdecimal() for part in key.split('/'))
                    if len(child) or set(child.attrib)-{'name','key','value'} or 'value' not in child.attrib or not (key in basic_keys if effect==EFFECT else native_key):
                        raise ValueError('Unverified title parameter')
                    continue
                if any(t.tag!='text-style' or len(t) for t in child):raise ValueError('Unsupported title text structure')
        if seconds(title.get('duration','0s'))<=0:raise ValueError('Invalid title timing')
        visible_start,visible_end=visible
        if visible_end>visible_start:
            if not 0<=visible_start<visible_end<=duration or (not retimed and ((visible_start*fps).denominator!=1 or (visible_end*fps).denominator!=1)):
                raise ValueError('Invalid title timing')
            # FCP quantizes retimed titles to project frames. Widen the warning
            # interval by at most one frame; this never changes the original.
            first=(visible_start*fps).__floor__() if retimed else int(visible_start*fps)
            last=(visible_end*fps).__ceil__() if retimed else int(visible_end*fps)
            existing.append({'text':''.join(''.join(t.itertext()) for t in title.findall('text')).strip(),
                             'start_frame':first,'end_frame':last,'enabled':title.get('enabled','1')!='0'})
        stripped[id(title)]=(parent,title)
    for parent,title in stripped.values():
        if parent.tag=='spine':
            index=list(parent).index(title)
            gap=ET.Element('gap',offset=title.get('offset','0s'),start='0s',duration=title.get('duration','0s'))
            parent.remove(title);parent.insert(index,gap)
        else:parent.remove(title)
    return ET.tostring(root,encoding='utf-8'),existing


def collision(rows,existing):
    exact=sum(any(e['enabled'] and all(e[k]==row[k] for k in ('text','start_frame','end_frame')) for e in existing) for row in rows)
    overlaps=sum(any(e['start_frame']<row['end_frame'] and row['start_frame']<e['end_frame'] for e in existing) for row in rows)
    # Never overwrite proofreading, duplicate an existing title, or infer ownership.
    return {'status':'duplicate' if rows and exact==len(rows) else ('conflict' if overlaps else 'clear'),
            'exactMatches':exact,'overlappingRows':overlaps,'existingTitles':len(existing)}
