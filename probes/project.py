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
from .audio_gain import volume_gain, remap_gain, materialize_gain, evaluate_envelopes, curves
from .source_clips import (VIDEO_ONLY_CHILDREN,conform_audio_speed,multicam_sources,
                           primary_audio_sources,source_audio_child,synchronized_sources)

RATE=16000
# Retime intervals and independent components can repeat an owner's curves.
# Bound the serialized plan before duplicating their keyframe dictionaries.
MAX_PLAN_GAIN_CURVES=10000
MAX_PLAN_GAIN_KEYS=100000

def sample(value):
    return (value*RATE + Fraction(1,2)).__floor__()

STORY_TAGS={'asset-clip','gap','clip','audio','video','ref-clip','sync-clip','mc-clip','spine'}
CLIP_ATTRS={'ref','offset','name','start','duration','enabled','tcFormat','audioRole','videoRole','srcEnable','format','tcStart','modDate','lane'}
AUDIO_ENHANCEMENTS={
    'adjust-loudness':{'amount','uniformity'},
    'adjust-noiseReduction':{'amount'},
    'adjust-humReduction':{'frequency'},
    'adjust-EQ':{'mode'},
    'adjust-matchEQ':set(),
    'adjust-voiceIsolation':{'amount'},
}
AUDIO_PARAMETER_TAGS={'data','param','fadeIn','fadeOut','keyframeAnimation','keyframe'}

class UnsupportedAudioRetime(ValueError):
    """A valid edit whose audio clock cannot be reconstructed accurately."""
    def __init__(self, reason):
        self.reason=reason
        super().__init__(f'暂不支持{reason}；当前无法准确重建这段音频')


def linear_time_map(node, length, output_start=None):
    """Return (output start/end, source start/end) in the clip's local clock.

    Smooth interpolation and reverse/freeze require a different renderer, so
    accepting them as linear would make the transcript's clock unreliable.
    """
    if output_start is None:output_start=seconds(node.get('start','0s'))
    output_limit=output_start+length
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
    if len(points)<2 or points[0][0]>output_start or points[-1][0]<output_limit:
        raise ValueError('变速时间范围不完整')
    intervals=[];stationary=False
    for begin,end in zip(points,points[1:]):
        if end[0]<=begin[0]:raise ValueError('变速关键点时间顺序无效')
        if end[1]<begin[1]:raise UnsupportedAudioRetime('倒放')
        if begin[0]>=output_limit:break
        if end[0]<=output_start:continue
        output_begin=max(begin[0],output_start)
        output_end=min(end[0],output_limit)
        if end[1]==begin[1]:
            stationary=True
            # FCP's speed-ramp preset may insert a two-sample stationary lead.
            # A material freeze is still unsupported; this tiny lead is silent.
            if output_end-output_begin>Fraction(1,1000):
                raise UnsupportedAudioRetime('停帧')
            continue
        slope=(end[1]-begin[1])/(end[0]-begin[0])
        source_begin=begin[1]+slope*(output_begin-begin[0])
        source_end=begin[1]+slope*(output_end-begin[0])
        intervals.append((output_begin-output_start,output_end-output_start,source_begin,source_end))
    if not intervals:
        if stationary:raise UnsupportedAudioRetime('停帧')
        raise ValueError('变速时间范围不完整')
    return intervals,mapping.get('preservesPitch','1')=='1'


def inverse_retime_segment(segment, intervals, preserve_pitch, origin, visible, inner_clock=None, outer_clock=None):
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
        if inner_clock is not None:
            speed=(source_at_end-source_at_begin)/(clipped_end-clipped_begin)
            def transform(gain):
                return remap_gain(gain,inner_clock,outer_clock,source_at_begin,clipped_begin,speed)
            mapped['gain']=transform(segment['gain'])
            if segment.get('channelMix',{}).get('components'):
                mapped['channelMix']=dict(segment['channelMix'],components=[
                    dict(component,gain=transform(component['gain'])) for component in segment['channelMix']['components']])
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


def bypassed_audio_processors(children, effects):
    """Count audio effects intentionally omitted from source-media decoding."""
    count=0
    for processor in children:
        if processor.tag=='filter-audio':
            definition=effects.get(processor.get('ref'))
            if (set(processor.attrib)-{'ref','name','nameOverride','enabled','presetID'}
                    or definition is None or not definition.get('uid') or processor.get('enabled','1') not in ('0','1')):
                raise ValueError('音频效果引用或设置无效')
            if any(child.tag not in ('data','param') for child in processor):
                raise ValueError('音频效果结构无效')
            count+=processor.get('enabled','1')=='1'
        elif processor.tag in AUDIO_ENHANCEMENTS:
            if set(processor.attrib)-AUDIO_ENHANCEMENTS[processor.tag]:
                raise ValueError('音频增强设置无效')
            allowed={'param'} if processor.tag=='adjust-EQ' else {'data'} if processor.tag=='adjust-matchEQ' else set()
            if any(child.tag not in allowed for child in processor):
                raise ValueError('音频增强结构无效')
            count+=1
        else:raise ValueError('暂不支持音频组件的裁剪、静音或重映射：'+processor.tag)
        if any(child.tag not in AUDIO_PARAMETER_TAGS for child in processor.iter() if child is not processor):
            raise ValueError('音频效果参数结构无效')
    return count


def audio_selection(node, asset, audio_mode, effects, role_sources=(), volume=volume_gain):
    """Plan enabled source components before asking the decoder about media.

    Channel numbers describe a source's layout, not timeline audio layers.
    Missing optional asset metadata is checked against real media by the native
    decoder; excluded and disabled components never require that metadata.
    """
    role=node.get('audioRole',node.get('role','dialogue')).split('.')[0]
    components=node.findall('audio-channel-source')
    seen=set();roles=[];effect_count=0;selected=[];channel_roles={};consumed_groups=[]
    if not components:
        components=[ET.Element('audio-channel-source',role=node.get('audioRole',node.get('role','dialogue')))]
        if 'srcCh' in node.attrib:components[0].set('srcCh',node.get('srcCh'))
    for component in components:
        full_role=component.get('role',node.get('audioRole',node.get('role','dialogue')))
        component_role=full_role.split('.')[0]
        active=flag(component,'active') and flag(component,'enabled') and not excluded_role(component_role,audio_mode)
        matched=[]
        for group in role_sources:
            candidates=[source for source in group if full_role==source.get('role') or full_role.startswith(source.get('role','')+'.')]
            if candidates:
                if not any(group is previous for previous in consumed_groups):consumed_groups.append(group)
                source=max(candidates,key=lambda source:len(source.get('role')))
                active=active and flag(source,'active') and flag(source,'enabled')
                matched.append(source)
        if not active:continue
        if set(component.attrib)-{'srcCh','role','active','enabled'}:
            raise ValueError('暂不支持音频组件的通道重映射或裁剪')
        volumes=component.findall('adjust-volume')
        if len(volumes)>1:raise ValueError('音量结构无效')
        component_gain=volume(volumes[0]) if volumes else 1.0
        for source in matched:
            adjustments=source.findall('adjust-volume')
            if len(adjustments)>1:raise ValueError('音量结构无效')
            if adjustments:component_gain*=volume(adjustments[0])
            effect_count+=bypassed_audio_processors((child for child in source if child.tag!='adjust-volume'),effects)
        effect_count+=bypassed_audio_processors((child for child in component if child.tag!='adjust-volume'),effects)
        channels=None
        if 'srcCh' in component.attrib:
            text=component.get('srcCh','')
            if not re.fullmatch(r'\s*[1-9]\d*(?:\s*,\s*[1-9]\d*)*\s*',text):raise ValueError('音频通道配置无效')
            channels=[int(x) for x in text.split(',')]
            if len(channels)>64 or max(channels)>64 or len(set(channels))!=len(channels) or seen.intersection(channels):
                raise ValueError('音频通道配置重复或超出媒体范围')
            seen.update(channels)
            channel_roles.update({channel:full_role for channel in channels})
        elif node.findall('audio-channel-source'):
            raise ValueError('音频组件缺少通道选择；请检查片段的音频配置')
        selected.append({'channels':channels,'gain':component_gain});roles.append(component_role)
    # A silent or role-excluded source does not need to be opened or inspected.
    empty=dict(components=[],sourceID=None,expectedChannels=None,expectedSources=None,_roleSources=tuple(consumed_groups),_channelRoles={})
    if not selected:return False,role,effect_count,empty
    def metadata_count(key,limit):
        text=asset.get(key)
        if text is None:return None
        if not re.fullmatch(r'[1-9]\d*',text) or int(text)>limit:
            raise ValueError('媒体音频通道信息无效；请检查源媒体，或导入整条时间线音频')
        return int(text)
    channels=metadata_count('audioChannels',64);sources=metadata_count('audioSources',32)
    source_id=node.get('srcID','1') if node.tag=='audio' else None
    if source_id is not None and (not re.fullmatch(r'[1-9]\d*',source_id) or int(source_id)>32):
        raise ValueError('媒体音频源编号无效；请检查片段音频配置，或导入整条时间线音频')
    if 'outCh' in node.attrib:raise ValueError('暂不支持音频通道重映射')
    explicit=any(component['channels'] is not None for component in selected)
    if source_id is not None and sources is not None and int(source_id)>sources:
        raise ValueError('媒体音频源编号超出范围；请检查片段音频配置，或导入整条时间线音频')
    expected=channels if source_id is not None else channels*sources if channels is not None and sources is not None else None
    if channels is not None and sources is not None and channels*sources>64:
        raise ValueError('媒体音频通道信息无效；请检查源媒体，或导入整条时间线音频')
    if expected is not None and any(channel>expected for channel in seen):
        raise ValueError('音频通道配置重复或超出媒体范围')
    if not explicit:
        # Keep the ordinary clip gain outside native default downmixing.
        selection=dict(components=None,sourceID=source_id,expectedChannels=channels,expectedSources=sources,defaultGain=selected[0]['gain'])
    else:selection=dict(components=selected,sourceID=source_id,expectedChannels=channels,expectedSources=sources)
    selection.update(_roleSources=tuple(consumed_groups),_channelRoles=channel_roles)
    return True,','.join(dict.fromkeys(roles)) or role,effect_count,selection


def segment_channels(selection):
    """Keep implicit default downmixing; every explicit group uses its weights."""
    components=selection['components'];channels=selection['expectedChannels'];sources=selection['expectedSources']
    gain=selection.get('defaultGain',1.0) if components is None else 1.0
    if components is None:
        mix=None if channels in (1,2) and sources==1 else selection
    else:mix=selection
    if mix is not None:mix={key:value for key,value in mix.items() if key!='defaultGain' and not key.startswith('_')}
    return gain,mix


def intersect_channels(outer,inner):
    """Apply a container's layout once, intersecting child audibility/gains."""
    if outer['components']==[] or inner['components']==[]:
        return dict(inner,components=[])
    if outer['components'] is None:return inner
    outer_components=outer['components'];offset=0
    if outer['sourceID'] is None and inner['sourceID'] is not None:
        source=int(inner['sourceID']);channels=inner['expectedChannels']
        if channels is None and (source>1 or inner['expectedSources']!=1):
            raise ValueError('缺少音轨声道信息，无法准确映射容器的通道选择；可导入整条时间线音频')
        offset=(source-1)*(channels or 0)
        # A container numbers all sources together; an audio node numbers only
        # its chosen source. Preserve the outer group divisor across tracks.
        outer_components=[dict(component,channels=[channel-offset for channel in component['channels']
                          if channel>offset and (channels is None or channel<=offset+channels)],
                          divisor=component.get('divisor',len(component['channels']))) for component in outer_components]
        outer_components=[component for component in outer_components if component['channels']]
    roles={channel:outer.get('_channelRoles',{}).get(channel+offset,inner.get('_channelRoles',{}).get(channel,'dialogue'))
           for component in outer_components for channel in component['channels']}
    if inner['components'] is None:
        default_gain=inner.get('defaultGain',1.0)
        components=[];channel_gains={}
        for component in outer_components:
            channel_gains.update({channel:component['gain']*default_gain for channel in component['channels']})
            if component.get('divisor',len(component['channels']))==len(component['channels']):
                components.append({'channels':component['channels'],'gain':component['gain']*default_gain})
            else:
                components.extend({'channels':[channel],'gain':component['gain']*default_gain/component['divisor']}
                                  for channel in component['channels'])
        return dict(inner,components=components,_channelGains=channel_gains,_coefficients=True,_channelRoles=roles)
    gains=inner.get('_channelGains') or {channel:component['gain'] for component in inner['components'] for channel in component['channels']}
    components=[];channel_gains={}
    for component in outer_components:
        # Expand to scalar channel weights. Averaging the outer group happens
        # once, even when the leaf also declares a stereo component.
        for channel in component['channels']:
            if channel in gains:
                channel_gains[channel]=component['gain']*gains[channel]
                components.append({'channels':[channel],'gain':channel_gains[channel]/component.get('divisor',len(component['channels']))})
    return dict(inner,components=components,_coefficients=True,_channelGains=channel_gains,
                _channelRoles={channel:roles[channel] for channel in channel_gains})


def channel_role_sources(selection,groups,effects,volume=volume_gain):
    """Apply remaining role controls to the final component output roles."""
    if not groups or not selection['components']:return selection,0
    components=[];channel_gains={};roles={};effect_count=0
    for component in selection['components']:
        role_groups={}
        for channel in component['channels']:
            full_role=selection.get('_channelRoles',{}).get(channel,'dialogue')
            role_groups.setdefault(full_role,[]).append(channel)
        for full_role,channels in role_groups.items():
            active=True;gain=1.0
            for group in groups:
                matched=[source for source in group if full_role==source.get('role') or full_role.startswith(source.get('role','')+'.')]
                if not matched:continue
                source=max(matched,key=lambda source:len(source.get('role')))
                active=active and flag(source,'active') and flag(source,'enabled')
                if not active:break
                adjustments=source.findall('adjust-volume')
                if len(adjustments)>1:raise ValueError('音量结构无效')
                if adjustments:gain*=volume(adjustments[0])
                effect_count+=bypassed_audio_processors((child for child in source if child.tag!='adjust-volume'),effects)
            if active:
                for channel in channels:
                    weight=component['gain']*gain/len(component['channels'])
                    components.append({'channels':[channel],'gain':weight});roles[channel]=full_role
                    channel_gains[channel]=selection.get('_channelGains',{}).get(channel,component['gain'])*gain
    return dict(selection,components=components,_coefficients=True,_channelGains=channel_gains,_channelRoles=roles),effect_count


def validate_role_sources(sources):
    seen=set()
    for source in sources:
        role=source.get('role')
        if not role or role in seen or set(source.attrib)-{'role','active','enabled'}:
            raise ValueError('暂不支持音频角色组件裁剪或未知设置；可导入整条时间线音频')
        flag(source,'active');flag(source,'enabled');seen.add(role)
        if any(child.tag not in (*AUDIO_ENHANCEMENTS,'adjust-volume','filter-audio') for child in source):
            raise ValueError('暂不支持音频角色组件的静音区间或未知处理')


def split_audio_edit(node):
    """Separate a composite J/L edit's picture and source-clock audio window.

    Connected items stay with the original anchor; only contained media belongs
    to the separate audio window. No original project XML is modified.
    """
    if node.tag not in ('asset-clip','clip','ref-clip','sync-clip','mc-clip'):
        raise ValueError('此片段类型不能使用分离音频起止')
    start=seconds(node.get('start','0s'))
    length=seconds(node.get('duration','0s'))
    audio_start=seconds(node.get('audioStart',str(start)+'s'))
    audio_length=seconds(node.get('audioDuration',str(length)+'s'))
    if audio_length<0:raise ValueError('音频片段时长不能为负数')
    if node.get('srcEnable','all') not in ('all','audio','video'):
        raise ValueError('无效的音频启用状态')
    picture=deepcopy(node)
    for key in ('audioStart','audioDuration'):picture.attrib.pop(key,None)
    if audio_start==start and audio_length==length:return (picture,)
    audio=deepcopy(picture)
    picture.set('srcEnable','video')
    if not audio_length or node.get('srcEnable','all')=='video':return (picture,)
    if node.find('timeMap') is not None:
        raise ValueError('暂不支持分离音频起止与变速同时使用；可导入整条时间线音频')
    audio.set('srcEnable','audio')
    audio.set('start',str(audio_start)+'s');audio.set('duration',str(audio_length)+'s')
    audio.set('offset',str(seconds(node.get('offset','0s'))+audio_start-start)+'s')
    for child in list(audio):
        if child.tag in STORY_TAGS and child.get('lane','0')!='0' and node.tag!='sync-clip':audio.remove(child)
    return picture,audio


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
    effects={e.get('id'):e for e in root.findall('resources/effect')}
    segments=[];skipped=[];ignored=0;count=0;timeline_end=Fraction(0);bypassed_effects=0
    clock=0;next_clock=0;volume_contexts={}

    def contextual_volume(volume):
        return volume_gain(volume,volume_contexts.get(id(volume)))

    def possible_media_audio(sequence,visited=()):
        if len(visited)>128:raise ValueError('项目片段嵌套过深')
        for clip in sequence.iter():
            if clip.tag in ('asset-clip','audio') and flag(clip,'enabled') and clip.get('srcEnable')!='video':
                asset=assets.get(clip.get('ref'))
                if asset is not None and asset.get('hasAudio')=='1':return True
            if clip.tag=='ref-clip' and clip.get('ref') not in visited:
                nested=medias.get(clip.get('ref'))
                inner=nested.find('sequence') if nested is not None else None
                if inner is not None and possible_media_audio(inner,(*visited,clip.get('ref'))):return True
            if clip.tag=='mc-clip' and clip.get('ref') not in visited:
                _,sources=multicam_sources(clip,medias)
                if any(source.get('srcEnable','all') in ('all','audio') and possible_media_audio(angle,(*visited,clip.get('ref')))
                       for angle,source in sources):return True
        return False

    def walk(node,parent_origin,parent_start,bounds,inherited=True,parent_gain=1.0,depth=0,media_stack=(),role_sources=(),clock_frame=None,channel_layers=()):
        nonlocal ignored,count,timeline_end,segments,skipped,bypassed_effects,clock,next_clock
        count+=1
        if clock_frame is None:clock_frame=frame
        if count>5000 or depth>128:raise ValueError('项目片段过多或嵌套过深')
        if node.tag not in STORY_TAGS:raise ValueError('暂不支持此片段结构；可导入整条时间线音频')
        if node.tag=='spine':
            if set(node.attrib)-{'offset','lane','name','format'}:raise ValueError('嵌套故事情节属性无效')
            spine_origin=parent_origin+seconds(node.get('offset','0s'))-parent_start
            for child in node:
                walk(child,spine_origin,Fraction(0),bounds,inherited,parent_gain,depth+1,media_stack,role_sources,clock_frame,channel_layers)
            return
        if 'audioStart' in node.attrib or 'audioDuration' in node.attrib:
            # Resolve implied source starts/durations before splitting the edit.
            resolved=deepcopy(node)
            resource=assets.get(node.get('ref')) if node.tag=='asset-clip' else medias.get(node.get('ref')) if node.tag=='ref-clip' else None
            sequence=resource.find('sequence') if resource is not None and node.tag=='ref-clip' else None
            if 'start' not in resolved.attrib:
                resolved.set('start',sequence.get('tcStart','0s') if sequence is not None else resource.get('start','0s') if resource is not None else '0s')
            if 'duration' not in resolved.attrib and resource is not None:
                resolved.set('duration',resource.get('duration','0s'))
            for part in split_audio_edit(resolved):
                walk(part,parent_origin,parent_start,bounds,inherited,parent_gain,depth,media_stack,role_sources,clock_frame,channel_layers)
            return
        asset=assets.get(node.get('ref')) if node.tag in ('asset-clip','audio') else None
        media=medias.get(node.get('ref')) if node.tag in ('ref-clip','mc-clip') else None
        media_seq=media.find('sequence') if media is not None else None
        selected_angles=[]
        container_format=root.find(f"resources/format[@id='{node.get('format')}']")
        container_frame=seconds(container_format.get('frameDuration','0s')) if container_format is not None else clock_frame
        if node.tag=='mc-clip':media_seq,selected_angles=multicam_sources(node,medias)
        sync_settings=synchronized_sources(node) if node.tag=='sync-clip' else {}
        for sources in sync_settings.values():validate_role_sources(sources)
        for _,source in selected_angles:validate_role_sources(source.findall('audio-role-source'))
        if node.tag in ('ref-clip','mc-clip') and (media_seq is None or node.get('ref') in media_stack):
            raise ValueError('复合片段引用缺失或形成循环')
        default_start=asset.get('start','0s') if asset is not None else media_seq.get('tcStart','0s') if media_seq is not None else '0s'
        start=seconds(node.get('start',default_start))
        origin=parent_origin+seconds(node.get('offset','0s'))-parent_start
        length=seconds(node.get('duration',asset.get('duration','0s') if asset is not None else '0s'))
        if length<=0:raise ValueError('片段时长必须大于零')
        # Bind automation to the owner before role/channel settings propagate
        # to a leaf. The same media resource can be used at different offsets.
        context=dict(clock=clock,origin=origin,start=start,length=length)
        for path in ('adjust-volume','audio-channel-source/adjust-volume','audio-role-source/adjust-volume',
                     'sync-source/audio-role-source/adjust-volume','mc-source/audio-role-source/adjust-volume'):
            for volume in node.findall(path):volume_contexts[id(volume)]=context
        visible=(max(bounds[0],origin),min(bounds[1],origin+length))
        if visible[1]>visible[0]:timeline_end=max(timeline_end,visible[1])
        allowed=CLIP_ATTRS | ({'role','srcCh','srcID','outCh'} if node.tag=='audio' else {'role','srcID'} if node.tag=='video' else {'useAudioSubroles'} if node.tag=='ref-clip' else set())
        if set(node.attrib)-allowed:raise ValueError('暂不支持此片段的未知属性')
        if node.tag=='ref-clip' and node.get('useAudioSubroles','0') not in ('0','1'):
            raise ValueError('复合片段音频子角色设置无效')
        enabled=inherited and flag(node,'enabled')
        source_enable=node.get('srcEnable','all')
        if source_enable not in ('all','audio','video'):raise ValueError('无效的音频启用状态')
        audible=enabled and source_enable!='video' and visible[1]>visible[0]
        role=node.get('audioRole',node.get('role','dialogue')).split('.')[0]
        effect_count=0;component_gain=1.0;channel_mix=None;container_channels=None
        consumed={id(group) for _,selection in channel_layers for group in selection.get('_roleSources',())}
        remaining_roles=tuple(group for group in role_sources if id(group) not in consumed)
        if node.tag in ('asset-clip','audio'):
            if asset is None:raise ValueError('媒体资源缺失')
            audible=audible and asset.get('hasAudio')=='1'
            layers=[selection for ref,selection in channel_layers if ref is None or ref==node.get('ref')]
            if audible and any(selection['components']==[] for selection in layers):
                ignored+=1;audible=False
            if audible:
                selected,role,effect_count,selection=audio_selection(node,asset,'all' if layers else audio_mode,effects,
                                                                   () if layers else role_sources,contextual_volume)
                for layer in reversed(layers):selection=intersect_channels(layer,selection)
                if layers:
                    selection,role_effects=channel_role_sources(selection,remaining_roles,effects,contextual_volume)
                    effect_count+=role_effects
                    role=','.join(dict.fromkeys(full_role.split('.')[0] for full_role in selection.get('_channelRoles',{}).values())) or role
                selected=selected and selection['components']!=[]
                if not selected:ignored+=1
                audible=selected
                if audible:component_gain,channel_mix=segment_channels(selection)
        elif node.tag in ('video','gap'):audible=False
        elif node.tag=='clip' and not any(desc.tag in ('asset-clip','audio','ref-clip')
                for child in node if child.get('lane','0')=='0' or source_audio_child(node,child)
                for desc in child.iter()):
            # FCP also wraps visual-only material in a plain clip. Its own
            # conform/timeMap must not retime unrelated dialogue below it.
            audible=False
        elif node.findall('audio-channel-source') and audible:
            # A plain clip's components describe its primary source layout,
            # not independent connected clips, even if those reuse its asset.
            if node.tag!='clip':
                raise ValueError('暂不支持容器片段的音频通道重映射')
            selected,_,_,selection=audio_selection(node,ET.Element('asset'),'all' if channel_layers else audio_mode,effects,
                                                 () if channel_layers else role_sources,contextual_volume)
            if not selected:
                container_channels=(None,selection);audible=False
            else:
                refs={child.get('ref') for child in primary_audio_sources(node)}
                if len(refs)!=1 or next(iter(refs)) not in assets:
                    raise ValueError('暂不支持容器片段的音频通道重映射')
                ref=next(iter(refs))
                _,_,component_effects,selection=audio_selection(node,assets[ref],'all' if channel_layers else audio_mode,effects,
                                                             () if channel_layers else role_sources,contextual_volume)
                container_channels=(ref,selection)
                effect_count+=component_effects
        if media_seq is not None and audible and not possible_media_audio(media_seq,(node.get('ref'),)):
            audible=False
        if node.tag=='mc-clip' and audible and not any(source.get('srcEnable','all') in ('all','audio')
                and possible_media_audio(angle,(node.get('ref'),)) for angle,source in selected_angles):audible=False
        if media_seq is not None and excluded_role(role,audio_mode):audible=False
        if node.tag=='ref-clip':
            role_gains=set()
            for component in node.findall('audio-role-source'):
                if set(component.attrib)-{'role','active','enabled'} or not component.get('role') or not flag(component,'active') or not flag(component,'enabled'):
                    raise ValueError('暂不支持复合片段音频组件的单独静音或裁剪')
                if audible and not excluded_role(component.get('role'),audio_mode):
                    volumes=component.findall('adjust-volume')
                    if len(volumes)>1:raise ValueError('音量结构无效')
                    role_gains.add(contextual_volume(volumes[0]) if volumes else 1.0)
                    effect_count+=bypassed_audio_processors((child for child in component if child.tag!='adjust-volume'),effects)
            if len(role_gains)>1:raise ValueError('暂不支持复合片段内不同音频角色使用不同的音量')
            component_gain*=next(iter(role_gains),1.0)
        gain=parent_gain*component_gain
        volumes=node.findall('adjust-volume')
        if len(volumes)>1:raise ValueError('音量结构无效')
        if volumes and audible:
            gain*=contextual_volume(volumes[0])
        conform=node.findall('conform-rate')
        conform_speed=conform_audio_speed(node,root,assets,clock_frame,media_seq,audible,bool(media_stack))
        if node.tag=='clip' and not audible and conform and node.find('timeMap') is None and any(
                child.tag in STORY_TAGS and child.get('lane','0')!='0' and not source_audio_child(node,child)
                for child in node):
            # Muting source components does not move independent dialogue.
            # Recover a known source clock without requiring an unsupported
            # silent picture's audio conversion to become renderable.
            try:conform_speed=conform_audio_speed(node,root,assets,clock_frame,media_seq,True,bool(media_stack))
            except ValueError:pass
        # A video-only reverse or smooth retime does not change independently
        # scheduled dialogue. Its visual timing need not be reconstructed.
        has_time_map=node.find('timeMap') is not None
        if conform and conform[0].get('scaleEnabled','1')=='1' and has_time_map and audible:
            raise ValueError('暂不支持同时使用帧率适配与音频变速')
        unsupported_retime=None
        try:
            retime=linear_time_map(node,length,start) if has_time_map and audible else None
        except UnsupportedAudioRetime as error:
            retime=None;unsupported_retime=error.reason
        if retime and node.tag not in ('asset-clip','audio','ref-clip','mc-clip'):
            raise ValueError('暂不支持此容器音频变速')
        if media_seq is not None:
            media_start=seconds(media_seq.get('tcStart','0s'))
            media_duration=seconds(media_seq.get('duration','0s'))
            if node.tag=='mc-clip' and not media_seq.get('duration'):
                media_duration=max((seconds(child.get('offset','0s'))+seconds(child.get('duration','0s'))-media_start
                                    for angle,_ in selected_angles for child in angle),default=Fraction(0))
            source_min=min((part[2] for part in retime[0]),default=start) if retime else start
            source_max=max((part[3] for part in retime[0]),default=start+length*conform_speed) if retime else start+length*conform_speed
            if not (node.tag=='mc-clip' and not audible or has_time_map and (not audible or unsupported_retime)) and (source_min<media_start or source_max>media_start+media_duration):
                raise ValueError('复合片段引用范围超出内部时间线')
        harmless=set(VIDEO_ONLY_CHILDREN) | {'conform-rate','caption','adjust-volume','audio-channel-source','metadata','marker','chapter-marker','keyword','rating','note'}
        if node.tag=='ref-clip':harmless.add('audio-role-source')
        if node.tag=='sync-clip':harmless.add('sync-source')
        if node.tag=='mc-clip':harmless.add('mc-source')
        if has_time_map:harmless.add('timeMap')
        harmless.add('filter-audio')
        if node.tag=='video':harmless.update(('param','reserved'))
        children=[]
        for child in node:
            if child.tag in STORY_TAGS:children.append(child)
            elif child.tag not in harmless:raise ValueError('暂不支持此片段设置：'+child.tag+'；可导入整条时间线音频')
        def child_channels(child):
            primary=source_audio_child(node,child) or child.get('lane','0')=='0'
            if not primary:return ()
            return (*channel_layers,container_channels) if container_channels is not None else channel_layers
        if retime and any((child.get('lane','0')=='0' or source_audio_child(node,child))
                          and any(desc.tag in ('asset-clip','audio','ref-clip') for desc in child.iter())
                          for child in children):
            raise ValueError('暂不支持变速片段的内含音频结构；可导入整条时间线音频')
        if unsupported_retime:
            # Skip only the unrenderable source, not independent connections.
            skipped.append((visible[0],visible[1],unsupported_retime))
            audible=False
        if audible:
            effect_count+=bypassed_audio_processors(node.findall('filter-audio'),effects)
            bypassed_effects+=effect_count
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
                if channel_mix is not None:segment['channelMix']=channel_mix
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
                source=start+(visible[0]-origin)*conform_speed
                source_end=source+(visible[1]-visible[0])*conform_speed
                add_segment(visible[0],visible[1],source,source_end,
                            False if conform_speed!=1 else None)
        if conform_speed!=1 and node.tag in ('clip','sync-clip'):
            # A rate-conformed plain clip can wrap source audio in a gap. Plan
            # its children in source time, then invert the verified rate map.
            intervals=[(Fraction(0),length,start,start+length*conform_speed)]
            source_bounds=(start,start+length*conform_speed)
            outer_segments,outer_skipped,outer_end=segments,skipped,timeline_end
            outer_clock=clock;next_clock+=1;clock=next_clock;inner_clock=clock
            segments=[];skipped=[]
            try:
                for child in children:
                    if node.tag=='sync-clip' and child.get('lane','0')!='0':continue
                    if node.tag=='clip' and child.get('lane','0')!='0' and not source_audio_child(node,child):continue
                    groups=(*role_sources,sync_settings.get('storyline',())) if node.tag=='sync-clip' else role_sources
                    walk(child,Fraction(0),Fraction(0),source_bounds,
                         enabled and source_enable!='video',gain,depth+1,media_stack,groups,container_frame,child_channels(child))
                inner_segments,inner_skipped=segments,skipped
            finally:
                segments=outer_segments;skipped=outer_skipped;timeline_end=outer_end
                clock=outer_clock
            for segment in inner_segments:
                segments.extend(inverse_retime_segment(segment,intervals,False,origin,visible,inner_clock,outer_clock))
            for begin,end,reason in inner_skipped:
                for _,_,out_begin,out_end in inverse_retime_ranges(begin,end,intervals,origin,visible):
                    skipped.append((out_begin,out_end,reason))
            if node.tag=='sync-clip':
                for child in children:
                    if child.get('lane','0')!='0':
                        walk(child,origin,start/conform_speed,bounds,enabled and source_enable!='video',gain,depth+1,media_stack,
                             (*role_sources,sync_settings.get('connected',())),clock_frame,child_channels(child))
            else:
                for child in children:
                    if child.get('lane','0')=='0' or source_audio_child(node,child):continue
                    # FCP's plain-clip conform converts the connection point,
                    # but not the connected clip's own speed or duration. A
                    # six-second connection can continue beyond its anchor.
                    offset=seconds(child.get('offset','0s'))
                    connection_origin=origin+(offset-start)/conform_speed
                    walk(child,connection_origin-offset,Fraction(0),bounds,inherited,parent_gain,
                         depth+1,media_stack,role_sources,clock_frame,child_channels(child))
        else:
            for child in children:
                # Contained media is trimmed/muted by its container. Connected
                # items share its timeline and may outlast the anchor.
                contained=child.get('lane','0')=='0'
                if unsupported_retime and (contained or source_audio_child(node,child)):continue
                groups=(*role_sources,sync_settings.get('storyline' if contained else 'connected',())) if node.tag=='sync-clip' else role_sources
                # FCP serializes connected offsets in the adjusted local clock.
                # Their source and duration remain independent of this timeMap.
                walk(child,origin,start,visible if contained or source_audio_child(node,child) else bounds,
                     enabled and source_enable!='video' if contained or node.tag=='sync-clip' else inherited,
                     gain if contained or node.tag=='sync-clip' else parent_gain,depth+1,media_stack,groups,container_frame,child_channels(child))
        if unsupported_retime:return
        if media_seq is not None:
            media_format=root.find(f"resources/format[@id='{media_seq.get('format')}']")
            media_frame=seconds(media_format.get('frameDuration','0s')) if media_format is not None else container_frame
            media_spine=media_seq.find('spine')
            if node.tag!='mc-clip' and (media_spine is None or len(media_seq.findall('spine'))!=1):
                raise ValueError('复合片段缺少完整内部时间线')
            next_stack=(*media_stack,node.get('ref'))
            branches=[(media_spine,None)] if node.tag!='mc-clip' else selected_angles
            def walk_media(branch_origin,branch_start,branch_bounds):
                for branch,source in branches:
                    active=source is None or source.get('srcEnable','all') in ('all','audio')
                    groups=role_sources if source is None else (*role_sources,tuple(source.findall('audio-role-source')))
                    for child in branch:
                        walk(child,branch_origin,branch_start,branch_bounds,
                             enabled and source_enable!='video' and not excluded_role(role,audio_mode) and active,
                             gain,depth+1,next_stack,groups,media_frame,channel_layers)
            if retime or conform_speed!=1:
                intervals,preserve_pitch=retime if retime else ([(Fraction(0),length,start,start+length*conform_speed)],False)
                source_bounds=(intervals[0][2],intervals[-1][3])
                outer_segments,outer_skipped,outer_end=segments,skipped,timeline_end
                outer_clock=clock;next_clock+=1;clock=next_clock;inner_clock=clock
                segments=[];skipped=[]
                try:
                    walk_media(Fraction(0),Fraction(0),source_bounds)
                    inner_segments,inner_skipped=segments,skipped
                finally:
                    segments=outer_segments;skipped=outer_skipped
                    timeline_end=outer_end;clock=outer_clock
                for segment in inner_segments:
                    segments.extend(inverse_retime_segment(segment,intervals,preserve_pitch,origin,visible,inner_clock,outer_clock))
                    if len(segments)>10000:raise ValueError('变速音频片段过多')
                for begin,end,reason in inner_skipped:
                    for _,_,out_begin,out_end in inverse_retime_ranges(begin,end,intervals,origin,visible):
                        skipped.append((out_begin,out_end,reason))
            else:
                walk_media(origin,start,visible)

    cursor=Fraction(0)
    for node in spine:
        offset=seconds(node.get('offset','0s'))-tc;length=seconds(node.get('duration','0s'))
        if offset!=cursor:raise ValueError('主要故事情节必须连续；请保留空隙片段')
        if offset<0 or length<=0 or offset+length>duration:raise ValueError('片段范围超出项目')
        walk(node,Fraction(0),tc,(Fraction(0),duration));cursor+=length
    if timeline_end!=duration:raise ValueError('项目音频范围不完整')
    # Different component envelopes cannot be applied after their channels
    # have been summed. Decode those groups separately, preserving each
    # existing downmix divisor and applying its own output-time envelope.
    materialized=[];curve_count=0;key_count=0
    for segment in segments:
        components=segment.get('channelMix',{}).get('components')
        groups=components if components and any(curves(c['gain']) for c in components) else (None,)
        for component in groups:
            item=dict(segment);gain=segment['gain']
            if component is not None:
                gain*=component['gain']
                item['channelMix']=dict(segment['channelMix'],components=[dict(component,gain=1.0)])
            envelopes=curves(gain)
            curve_count+=len(envelopes)
            key_count+=sum(len(envelope.keyframes) for envelope in envelopes)
            if curve_count>MAX_PLAN_GAIN_CURVES or key_count>MAX_PLAN_GAIN_KEYS:
                raise ValueError('项目音量自动化过于复杂；请导入整条时间线音频')
            item['gain'],envelopes=materialize_gain(gain)
            if envelopes:item['gainEnvelopes']=envelopes
            materialized.append(item)
            if len(materialized)>10000:raise ValueError('音频片段或独立音量组件过多')
    segments=materialized
    # FCP may finish a project at the sample boundary of connected audio, after
    # the last full video frame. PCM keeps that exact endpoint; titles use frames.
    skipped_audio=[{'offset':str(begin),'duration':str(end-begin),'startSample':sample(begin),'endSample':sample(end),'reason':reason}
                   for begin,end,reason in skipped if sample(end)>sample(begin)]
    return dict(project=project.get('name','未命名项目'),uid=project.get('uid'),duration=str(duration),relative_start='0',frameDuration=str(frame),totalFrames=(duration/frame).__ceil__(),width=fmt.get('width','1920'),height=fmt.get('height','1080'),colorSpace=fmt.get('colorSpace','1-1-1 (Rec. 709)'),sampleCount=sample(duration),segments=segments,skippedAudio=skipped_audio,bypassedAudioEffects=bypassed_effects,audioMode=audio_mode,ignoredRoleClips=ignored,audibility='XML-defined audio excluding music/effects roles' if audio_mode=='dialogue' else 'XML-defined mix; FCP live role/solo monitoring not included')

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
        command=[str(binary),str(source_xml),expected_uid,str(directory)]
        if segment.get('channelMix') is not None:command.append(json.dumps(segment['channelMix'],separators=(',',':'),allow_nan=False))
        result=subprocess.run(command,capture_output=True,text=True,check=True,timeout=60)
        decoded=json.loads(result.stdout)
        if decoded.get('status')!='decoded':
            stage=decoded.get('stage','unknown')
            if stage in ('incomplete-project-audio','decode','resample'):
                raise ValueError('源媒体音轨未能完整读取；请检查媒体，或导入整条时间线音频：'+stage)
            if stage in ('audio-layout-mismatch','audio-channel-range','audio-source-selection','ambiguous-audio-channel-selection',
                         'audio-layout-conflict','invalid-channel-selection','unverified-audio-source-id',
                         'ambiguous-audio-tracks','unverified-multitrack-channel-selection',
                         'unsupported-channel-layout','audio-format-required'):
                raise ValueError('源媒体音频通道与项目配置不一致或无法准确映射；请检查片段音频配置，或导入整条时间线音频：'+stage)
            raise ValueError('无法读取媒体，请检查文件是否在线及目录访问权限：'+stage)
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
            if segment.get('gainEnvelopes'):
                envelope=evaluate_envelopes(segment['gainEnvelopes'],base,count,RATE)
                values=array('f',(v*float(envelope[k]) for k,v in enumerate(values)))
            # Sum overlapping dialogue, preserving the original project clock.
            pcm[base:base+count]=array('f',(pcm[base+k]+v*gain for k,v in enumerate(values)))
            done+=count
        reports.append(dict(index=i,sampleCount=output_total,gain=segment['gain']))
    energy=sum(float(v)*v for v in pcm)
    if sys.byteorder!='little':pcm.byteswap()
    data=pcm.tobytes();(directory/'timeline.f32le').write_bytes(data)
    return dict(status='decoded',pcmFile='timeline.f32le',sampleCount=plan['sampleCount'],sampleRate=RATE,channels=1,pcmBytes=len(data),pcmSHA256=hashlib.sha256(data).hexdigest(),rms=math.sqrt(energy/plan['sampleCount']),silent=energy==0,segments=reports,plan=plan)
