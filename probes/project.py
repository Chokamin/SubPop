"""Timeline audio plan from FCPXML, including nested linear retimes.

Dialogue mode intentionally excludes music/effects roles. The XML-defined mix
does not include FCP's live solo monitoring or unmodelled audio effects.
"""
from array import array
from copy import deepcopy
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlparse
import xml.etree.ElementTree as ET
from .readback import seconds
from .timeline_audio import flag

RATE=16000

def sample(value):
    return (value*RATE + Fraction(1,2)).__floor__()

STORY_TAGS={'asset-clip','gap','clip','audio','video','ref-clip'}
CLIP_ATTRS={'ref','offset','name','start','duration','enabled','tcFormat','audioRole','videoRole','srcEnable','format','tcStart','modDate','lane'}

class UnsupportedAudioRetime(ValueError):
    """A valid edit whose audio clock cannot be reconstructed accurately."""
    def __init__(self, reason):
        self.reason=reason
        super().__init__(f'暂不支持{reason}；当前无法准确重建这段音频')


def linear_time_map(node, length):
    """Return (output start/end, source start/end) in the clip's local clock.

    Smooth interpolation and reverse/freeze require a different renderer, so
    accepting them as linear would make the transcript's clock unreliable.
    """
    maps=node.findall('timeMap')
    if not maps:return None
    if len(maps)!=1:raise ValueError('变速结构无效')
    mapping=maps[0]
    if set(mapping.attrib)-{'preservesPitch','frameSampling'} or mapping.get('preservesPitch','1') not in ('0','1'):
        raise ValueError('暂不支持此变速设置')
    points=[]
    for point in mapping:
        if point.tag!='timept' or len(point) or set(point.attrib)-{'time','value','interp','inTime','outTime'}:
            raise ValueError('变速关键点结构无效')
        interp=point.get('interp','smooth2')
        if interp not in ('linear','smooth','smooth2'):raise ValueError('未知变速插值类型')
        if interp!='linear' or 'inTime' in point.attrib or 'outTime' in point.attrib:
            raise UnsupportedAudioRetime('平滑变速')
        points.append((seconds(point.get('time','')),seconds(point.get('value',''))))
        if len(points)>5000:raise ValueError('变速关键点过多')
    # FCP's own speed-ramp XML may end a few audio samples beyond the clip's
    # visible duration. Trim its final affine segment to the actual endpoint.
    if len(points)<2 or points[0][0]!=0 or points[-1][0]<length:
        raise ValueError('变速时间范围不完整')
    intervals=[];stationary=False
    for begin,end in zip(points,points[1:]):
        if end[0]<=begin[0]:raise ValueError('变速关键点时间顺序无效')
        if end[1]<begin[1]:raise UnsupportedAudioRetime('倒放')
        if begin[0]>=length:break
        output_end=min(end[0],length)
        if end[1]==begin[1]:
            stationary=True
            # FCP's speed-ramp preset may insert a two-sample stationary lead.
            # A material freeze is still unsupported; this tiny lead is silent.
            if output_end-begin[0]>Fraction(1,1000):
                raise UnsupportedAudioRetime('停帧')
            continue
        source_end=begin[1]+(end[1]-begin[1])*(output_end-begin[0])/(end[0]-begin[0])
        intervals.append((begin[0],output_end,begin[1],source_end))
    if not intervals:
        if stationary:raise UnsupportedAudioRetime('停帧')
        raise ValueError('变速时间范围不完整')
    return intervals,mapping.get('preservesPitch','1')=='1'


def inverse_retime_segment(segment, intervals, preserve_pitch, origin, visible):
    """Map one compound-source audio interval into the retimed parent clock.

    Both the source clip and the compound can already be split at rate changes.
    Splitting their intersection again composes the two affine maps exactly.
    """
    inner_begin=Fraction(segment['offset'])
    inner_end=inner_begin+Fraction(segment['duration'])
    asset_begin=Fraction(segment['source_start'])
    asset_length=Fraction(segment.get('source_duration',segment['duration']))
    inner_pitch=segment.get('preservesPitch')
    if inner_pitch is not None and inner_pitch!=preserve_pitch:
        raise ValueError('暂不支持复合片段内外使用不同的保留音调设置')
    for source_at_begin,source_at_end,clipped_begin,clipped_end in inverse_retime_ranges(
            inner_begin,inner_end,intervals,origin,visible):
        asset_at_begin=asset_begin+(source_at_begin-inner_begin)*asset_length/(inner_end-inner_begin)
        asset_at_end=asset_begin+(source_at_end-inner_begin)*asset_length/(inner_end-inner_begin)
        mapped=dict(segment,offset=str(clipped_begin),duration=str(clipped_end-clipped_begin),
                    source_start=str(asset_at_begin),source_duration=str(asset_at_end-asset_at_begin),
                    startSample=sample(clipped_begin),sampleCount=sample(clipped_end)-sample(clipped_begin),
                    preservesPitch=preserve_pitch)
        if mapped['sampleCount']>0:yield mapped


def inverse_retime_ranges(inner_begin,inner_end,intervals,origin,visible):
    """Yield source and output intersections for a strictly forward linear map."""
    for out_begin,out_end,source_begin,source_end in intervals:
        begin=max(inner_begin,source_begin)
        end=min(inner_end,source_end)
        if end<=begin:continue
        slope=(out_end-out_begin)/(source_end-source_begin)
        mapped_begin=origin+out_begin+(begin-source_begin)*slope
        mapped_end=origin+out_begin+(end-source_begin)*slope
        clipped_begin=max(mapped_begin,visible[0])
        clipped_end=min(mapped_end,visible[1])
        if clipped_end<=clipped_begin:continue
        source_at_begin=begin+(clipped_begin-mapped_begin)/slope
        source_at_end=begin+(clipped_end-mapped_begin)/slope
        yield source_at_begin,source_at_end,clipped_begin,clipped_end


def excluded_role(role, audio_mode):
    # Custom audio roles (for example VO/旁白) are not music/effects. FCPXML
    # does not provide a built-in category for a user-created role.
    return audio_mode=='dialogue' and role.split('.')[0] in ('music','effects')


def audio_selection(node, asset, audio_mode):
    """Only downmix the full source when all its channels have equal audibility.

    Two mono components are a normal stereo layout, not two source tracks.
    Never mix an unselected/muted channel back in to accommodate that layout.
    """
    role=node.get('audioRole',node.get('role','dialogue')).split('.')[0]
    components=node.findall('audio-channel-source')
    if not components and excluded_role(role,audio_mode):return False,role
    if asset.get('audioChannels') not in ('1','2') or asset.get('audioSources','1')!='1':raise ValueError('暂不支持多通道媒体')
    expected=set(range(1,int(asset.get('audioChannels'))+1));seen=set();selected=set();roles=[]
    if not components:
        components=[ET.Element('audio-channel-source',srcCh=node.get('srcCh',', '.join(map(str,sorted(expected)))),role=role)]
    for component in components:
        component_role=component.get('role',role).split('.')[0]
        active=flag(component,'active') and flag(component,'enabled') and not excluded_role(component_role,audio_mode)
        if set(component.attrib)-{'srcCh','role','active','enabled'} or (active and len(component)):
            raise ValueError('暂不支持音频组件的通道重映射、裁剪或效果')
        text=component.get('srcCh','')
        if not re.fullmatch(r'\s*[1-9]\d*(?:\s*,\s*[1-9]\d*)*\s*',text):raise ValueError('音频通道配置无效')
        channels=[int(x) for x in text.split(',')]
        if len(set(channels))!=len(channels) or not set(channels)<=expected or seen.intersection(channels):raise ValueError('音频通道配置重复或超出媒体范围')
        seen.update(channels)
        if active:selected.update(channels);roles.append(component_role)
    if selected and selected!=expected:raise ValueError('暂不支持只启用部分音频通道；请将此片段设为完整单声道或立体声')
    return bool(selected),','.join(dict.fromkeys(roles)) or role


def inspect(path, audio_mode='dialogue'):
    if audio_mode not in ('dialogue','all'):raise ValueError('Unknown audio mode')
    data=path.read_bytes()
    if len(data)>16*1024*1024 or b'<!ENTITY' in data.upper():raise ValueError('Unsafe project XML')
    root=ET.fromstring(data);projects=root.findall('.//project')
    if len(projects)!=1:raise ValueError('请拖入一个完整项目')
    project=projects[0];seq=project.find('sequence')
    if seq is None or not project.get('uid'):raise ValueError('项目没有有效时间线')
    duration=seconds(seq.get('duration','0s'));tc=seconds(seq.get('tcStart','0s'))
    if duration<=0:raise ValueError('项目时长必须大于零')
    fmt=root.find(f"resources/format[@id='{seq.get('format')}']")
    if fmt is None:raise ValueError('缺少项目格式')
    frame=seconds(fmt.get('frameDuration','0s'))
    if frame not in [Fraction(1,n) for n in (24,25,30,50,60)]+[Fraction(1001,n) for n in (24000,30000,60000)]:raise ValueError('暂不支持此帧率')
    spine=seq.find('spine')
    if spine is None or len(seq.findall('spine'))!=1 or any(n.tag not in ('spine','note','metadata') for n in seq) or spine.attrib:raise ValueError('暂不支持此时间线结构')
    assets={a.get('id'):a for a in root.findall('resources/asset')}
    medias={m.get('id'):m for m in root.findall('resources/media')}
    segments=[];skipped=[];ignored=0;count=0;timeline_end=Fraction(0)

    def possible_media_audio(sequence,visited=()):
        for clip in sequence.iter():
            if clip.tag in ('asset-clip','audio') and flag(clip,'enabled') and clip.get('srcEnable')!='video':
                asset=assets.get(clip.get('ref'))
                if asset is not None and asset.get('hasAudio')=='1':return True
            if clip.tag=='ref-clip' and clip.get('ref') not in visited:
                nested=medias.get(clip.get('ref'))
                inner=nested.find('sequence') if nested is not None else None
                if inner is not None and possible_media_audio(inner,(*visited,clip.get('ref'))):return True
        return False

    def walk(node,parent_origin,parent_start,bounds,inherited=True,parent_gain=1.0,depth=0,media_stack=()):
        nonlocal ignored,count,timeline_end,segments,skipped
        count+=1
        if count>5000 or depth>128:raise ValueError('项目片段过多或嵌套过深')
        if node.tag not in STORY_TAGS:raise ValueError('暂不支持此多机位或同步片段结构')
        asset=assets.get(node.get('ref')) if node.tag in ('asset-clip','audio') else None
        media=medias.get(node.get('ref')) if node.tag=='ref-clip' else None
        media_seq=media.find('sequence') if media is not None else None
        if node.tag=='ref-clip' and (media_seq is None or node.get('ref') in media_stack):
            raise ValueError('复合片段引用缺失或形成循环')
        default_start=asset.get('start','0s') if asset is not None else media_seq.get('tcStart','0s') if media_seq is not None else '0s'
        start=seconds(node.get('start',default_start))
        origin=parent_origin+seconds(node.get('offset','0s'))-parent_start
        length=seconds(node.get('duration',asset.get('duration','0s') if asset is not None else '0s'))
        if length<=0:raise ValueError('片段时长必须大于零')
        visible=(max(bounds[0],origin),min(bounds[1],origin+length))
        if visible[1]>visible[0]:timeline_end=max(timeline_end,visible[1])
        allowed=CLIP_ATTRS | ({'role','srcCh','srcID','outCh'} if node.tag=='audio' else {'role','srcID'} if node.tag=='video' else {'useAudioSubroles'} if node.tag=='ref-clip' else set())
        if set(node.attrib)-allowed:raise ValueError('暂不支持分离的 J/L 音频或未知片段属性')
        if node.tag=='ref-clip':
            if node.get('useAudioSubroles','0') not in ('0','1'):raise ValueError('复合片段音频子角色设置无效')
            for component in node.findall('audio-role-source'):
                if set(component.attrib)-{'role','active','enabled'} or not component.get('role') or len(component) or not flag(component,'active') or not flag(component,'enabled'):
                    raise ValueError('暂不支持复合片段音频组件的单独静音、裁剪或效果')
        enabled=inherited and flag(node,'enabled')
        source_enable=node.get('srcEnable','all')
        if source_enable not in ('all','audio','video'):raise ValueError('无效的音频启用状态')
        audible=enabled and source_enable!='video' and visible[1]>visible[0]
        role=node.get('audioRole',node.get('role','dialogue')).split('.')[0]
        if node.tag in ('asset-clip','audio'):
            if asset is None:raise ValueError('媒体资源缺失')
            audible=audible and asset.get('hasAudio')=='1'
            if audible:
                selected,role=audio_selection(node,asset,audio_mode)
                if not selected:ignored+=1
                audible=selected
            if audible and (node.get('srcID','1')!='1' or 'outCh' in node.attrib):raise ValueError('暂不支持音频通道重映射')
        elif node.tag=='video':audible=False
        elif node.findall('audio-channel-source'):raise ValueError('暂不支持容器片段的音频通道重映射')
        if media_seq is not None and audible and not possible_media_audio(media_seq,(node.get('ref'),)):
            audible=False
        if media_seq is not None and excluded_role(role,audio_mode):audible=False
        gain=parent_gain
        volumes=node.findall('adjust-volume')
        if len(volumes)>1:raise ValueError('音量结构无效')
        if volumes and audible:
            v=volumes[0];amount=v.get('amount','0dB')
            if len(v) or set(v.attrib)-{'amount'} or not re.fullmatch(r'-?\d+(?:\.\d+)?dB',amount):raise ValueError('暂不支持音量关键帧或淡入淡出')
            db=float(amount[:-2])
            if not -96<=db<=12:raise ValueError('音量超出支持范围')
            gain*=10**(db/20)
        conform=node.findall('conform-rate')
        if len(conform)>1:raise ValueError('帧率适配结构无效')
        if conform:
            c=conform[0]
            # Only explicit 0 preserves real-time audio across frame rates.
            if c.get('scaleEnabled')!='0':raise ValueError('暂不支持启用速度缩放的帧率适配')
            if len(c) or set(c.attrib)-{'scaleEnabled','srcFrameRate','frameSampling'}:raise ValueError('帧率适配结构无效')
        # A video-only reverse or smooth retime does not change independently
        # scheduled dialogue. Its visual timing need not be reconstructed.
        has_time_map=node.find('timeMap') is not None
        unsupported_retime=None
        try:
            retime=linear_time_map(node,length) if has_time_map and audible else None
        except UnsupportedAudioRetime as error:
            retime=None;unsupported_retime=error.reason
        if retime and node.tag not in ('asset-clip','audio','ref-clip'):
            raise ValueError('暂不支持此容器音频变速')
        if media_seq is not None:
            media_start=seconds(media_seq.get('tcStart','0s'))
            media_duration=seconds(media_seq.get('duration','0s'))
            source_min=min((part[2] for part in retime[0]),default=start) if retime else start
            source_max=max((part[3] for part in retime[0]),default=start+length) if retime else start+length
            if not (has_time_map and (not audible or unsupported_retime)) and (source_min<media_start or source_max>media_start+media_duration):
                raise ValueError('复合片段引用范围超出内部时间线')
        harmless={'conform-rate','caption','adjust-volume','audio-channel-source','adjust-transform','adjust-crop','adjust-conform','adjust-blend','filter-video','filter-video-mask','metadata','marker','chapter-marker','keyword','rating','note'}
        if node.tag=='ref-clip':harmless.add('audio-role-source')
        if has_time_map:harmless.add('timeMap')
        if not audible:harmless.add('filter-audio')
        if node.tag=='video':harmless.update(('param','reserved'))
        children=[]
        for child in node:
            if child.tag in STORY_TAGS:children.append(child)
            elif child.tag not in harmless:raise ValueError('暂不支持音频效果、变速或嵌套模板：'+child.tag)
        if has_time_map and children:
            raise ValueError('变速片段带有连接素材，暂不能准确映射时间')
        if unsupported_retime:
            # This clip's audible output cannot be aligned. Keep the original
            # project clock and let independent clips elsewhere still run.
            skipped.append((visible[0],visible[1],unsupported_retime))
            return
        if node.tag in ('asset-clip','audio') and audible:
            reps=asset.findall("media-rep[@kind='original-media']")
            if len(reps)!=1:raise ValueError('缺少原始媒体引用')
            url=urlparse(reps[0].get('src',''))
            if url.scheme!='file' or url.netloc not in ('','localhost'):raise ValueError('需要本机原始媒体')
            asset_start=seconds(asset.get('start','0s'))
            asset_duration=seconds(asset.get('duration','0s'))
            def add_segment(out_begin,out_end,source_begin,source_end,preserve_pitch=None):
                source_begin-=asset_start;source_end-=asset_start
                if source_begin<0 or source_end>asset_duration or source_end<=source_begin:
                    raise ValueError('源音频范围无效')
                segment=dict(assetRef=node.get('ref'),media=str(Path(unquote(url.path))),offset=str(out_begin),duration=str(out_end-out_begin),source_start=str(source_begin),startSample=sample(out_begin),sampleCount=sample(out_end)-sample(out_begin),gain=gain,role=role)
                if preserve_pitch is not None:
                    segment.update(source_duration=str(source_end-source_begin),preservesPitch=preserve_pitch)
                segments.append(segment)
            if retime:
                intervals,preserve_pitch=retime
                for local_begin,local_end,source_begin,source_end in intervals:
                    out_begin=max(visible[0],origin+local_begin)
                    out_end=min(visible[1],origin+local_end)
                    if out_end<=out_begin:continue
                    slope=(source_end-source_begin)/(local_end-local_begin)
                    add_segment(out_begin,out_end,source_begin+(out_begin-origin-local_begin)*slope,
                                source_begin+(out_end-origin-local_begin)*slope,preserve_pitch)
            else:
                source=start+visible[0]-origin
                add_segment(visible[0],visible[1],source,source+visible[1]-visible[0])
        for child in children:
            # Contained media is trimmed/muted by its container. Connected items
            # share its enclosing timeline and can outlast or precede the anchor.
            contained=child.get('lane','0')=='0'
            walk(child,origin,start,visible if contained else bounds,
                 enabled and source_enable!='video' if contained else inherited,
                 gain if contained else parent_gain,depth+1,media_stack)
        if media_seq is not None:
            media_spine=media_seq.find('spine')
            if media_spine is None or len(media_seq.findall('spine'))!=1:
                raise ValueError('复合片段缺少完整内部时间线')
            next_stack=(*media_stack,node.get('ref'))
            if retime:
                intervals,preserve_pitch=retime
                source_bounds=(intervals[0][2],intervals[-1][3])
                outer_segments,outer_skipped,outer_end=segments,skipped,timeline_end
                segments=[];skipped=[]
                try:
                    for child in media_spine:
                        walk(child,Fraction(0),Fraction(0),source_bounds,
                             enabled and source_enable!='video' and not excluded_role(role,audio_mode),
                             gain,depth+1,next_stack)
                    inner_segments,inner_skipped=segments,skipped
                finally:
                    segments=outer_segments;skipped=outer_skipped
                    timeline_end=outer_end
                for segment in inner_segments:
                    segments.extend(inverse_retime_segment(segment,intervals,preserve_pitch,origin,visible))
                    if len(segments)>10000:raise ValueError('变速音频片段过多')
                for begin,end,reason in inner_skipped:
                    for _,_,out_begin,out_end in inverse_retime_ranges(begin,end,intervals,origin,visible):
                        skipped.append((out_begin,out_end,reason))
            else:
                for child in media_spine:
                    walk(child,origin,start,visible,enabled and source_enable!='video' and not excluded_role(role,audio_mode),
                         gain,depth+1,next_stack)

    cursor=Fraction(0)
    for node in spine:
        offset=seconds(node.get('offset','0s'))-tc;length=seconds(node.get('duration','0s'))
        if offset!=cursor:raise ValueError('主要故事情节必须连续；请保留空隙片段')
        if offset<0 or length<=0 or offset+length>duration:raise ValueError('片段范围超出项目')
        walk(node,Fraction(0),tc,(Fraction(0),duration));cursor+=length
    if timeline_end!=duration:raise ValueError('项目音频范围不完整')
    # FCP may finish a project at the sample boundary of connected audio, after
    # the last full video frame. PCM keeps that exact endpoint; titles use frames.
    skipped_audio=[{'offset':str(begin),'duration':str(end-begin),'startSample':sample(begin),'endSample':sample(end),'reason':reason}
                   for begin,end,reason in skipped if sample(end)>sample(begin)]
    return dict(project=project.get('name','未命名项目'),uid=project.get('uid'),duration=str(duration),relative_start='0',frameDuration=str(frame),totalFrames=(duration/frame).__ceil__(),width=fmt.get('width','1920'),height=fmt.get('height','1080'),colorSpace=fmt.get('colorSpace','1-1-1 (Rec. 709)'),sampleCount=sample(duration),segments=segments,skippedAudio=skipped_audio,audioMode=audio_mode,ignoredRoleClips=ignored,audibility='XML-defined audio excluding music/effects roles' if audio_mode=='dialogue' else 'XML-defined mix; FCP live role/solo monitoring not included')

def render(xml,directory,binary,expected_uid,audio_mode='dialogue'):
    plan=inspect(xml,audio_mode)
    if plan['uid']!=expected_uid:raise ValueError('项目身份不匹配')
    root=ET.fromstring(xml.read_bytes());pcm=array('f',[0])*plan['sampleCount'];reports=[]
    assets={asset.get('id'):asset for asset in root.findall('resources/asset')}
    def decode(segment,first,count):
        doc=ET.Element('fcpxml',version='1.14');res=ET.SubElement(doc,'resources')
        asset=deepcopy(assets[segment['assetRef']])
        for p in asset.iter():
            for c in list(p):
                if c.tag in ('bookmark','metadata'):p.remove(c)
        res.append(asset);pr=ET.SubElement(doc,'project',name=plan['project'],uid=expected_uid)
        length=Fraction(count,RATE);seq=ET.SubElement(pr,'sequence',duration=str(length)+'s',tcStart='0s');spine=ET.SubElement(seq,'spine')
        start=seconds(asset.get('start','0s'))+Fraction(first,RATE)
        ET.SubElement(spine,'asset-clip',ref=segment['assetRef'],offset='0s',start=str(start)+'s',duration=str(length)+'s',audioRole='dialogue')
        source_xml=directory/'decode-segment.fcpxml';source_xml.write_bytes(ET.tostring(doc,encoding='utf-8'))
        result=subprocess.run([str(binary),str(source_xml),expected_uid,str(directory)],capture_output=True,text=True,check=True,timeout=60)
        decoded=json.loads(result.stdout)
        if decoded.get('status')!='decoded':raise ValueError('无法读取媒体，请检查文件是否在线及目录访问权限：'+decoded.get('stage','unknown'))
        name=decoded.get('pcmFile','')
        if not name or Path(name).name!=name:raise ValueError('Invalid decoder output')
        values=array('f');values.frombytes((directory/name).read_bytes());(directory/name).unlink()
        if sys.byteorder!='little':values.byteswap()
        if len(values)!=count or not all(math.isfinite(v) for v in values):raise ValueError('音频解码不完整')
        return values

    for i,segment in enumerate(plan['segments']):
        output_total=segment['sampleCount'];source_first=sample(Fraction(segment['source_start']))
        source_total=(sample(Fraction(segment['source_start'])+Fraction(segment['source_duration']))-source_first
                      if 'source_duration' in segment else output_total)
        if not source_total or not output_total or not Fraction(1,20)<=Fraction(source_total,output_total)<=20:
            raise ValueError('音频变速超出可准确重建的范围')
        done=0
        while done<output_total:
            count=min(output_total-done,30*RATE,max(1,30*RATE*output_total//source_total))
            source_begin=(done*source_total+output_total//2)//output_total
            source_end=((done+count)*source_total+output_total//2)//output_total
            while source_end-source_begin>30*RATE:
                count-=1
                source_end=((done+count)*source_total+output_total//2)//output_total
            if count<=0 or source_end<=source_begin:raise ValueError('音频变速片段过短')
            values=decode(segment,source_first+source_begin,source_end-source_begin)
            if len(values)!=count:
                import numpy as np
                source=np.asarray(values,dtype=np.float32)
                if segment.get('preservesPitch',True):
                    import librosa
                    stretched=librosa.effects.time_stretch(source,rate=len(source)/count)
                else:
                    from scipy.signal import resample
                    stretched=resample(source,count)
                if abs(len(stretched)-count)>16:raise ValueError('音频变速长度不完整')
                values=array('f',stretched[:count])
                if len(values)<count:values.extend([0.0]*(count-len(values)))
            base=segment['startSample']+done;gain=segment['gain']
            # Sum overlapping dialogue, preserving the original project clock.
            pcm[base:base+count]=array('f',(pcm[base+k]+v*gain for k,v in enumerate(values)))
            done+=count
        reports.append(dict(index=i,sampleCount=output_total,gain=segment['gain']))
    energy=sum(float(v)*v for v in pcm)
    if sys.byteorder!='little':pcm.byteswap()
    data=pcm.tobytes();(directory/'timeline.f32le').write_bytes(data)
    return dict(status='decoded',pcmFile='timeline.f32le',sampleCount=plan['sampleCount'],sampleRate=RATE,channels=1,pcmBytes=len(data),pcmSHA256=hashlib.sha256(data).hexdigest(),rms=math.sqrt(energy/plan['sampleCount']),silent=energy==0,segments=reports,plan=plan)
