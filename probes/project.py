"""MVP timeline plan: plain cuts/gaps and connected audio/video.

Dialogue mode intentionally excludes music/effects roles. Never interpret live
FCP solo monitoring, retimes, compounds or audio effects as supported mixing.
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
    if (duration/frame).denominator!=1:raise ValueError('项目时长不在帧边界')
    spine=seq.find('spine')
    if spine is None or len(seq)!=1 or spine.attrib:raise ValueError('暂不支持此时间线结构')
    assets={a.get('id'):a for a in root.findall('resources/asset')};segments=[];ignored=0;count=0
    def walk(node,parent_origin,parent_start,inherited=True,parent_gain=1.0):
        nonlocal ignored,count
        count+=1
        if count>5000:raise ValueError('项目片段过多')
        if node.tag not in ('asset-clip','gap'):raise ValueError('暂不支持复合片段、多机位或变速；请先展开为普通片段')
        asset=assets.get(node.get('ref')) if node.tag=='asset-clip' else None
        start=seconds(node.get('start',asset.get('start','0s') if asset is not None else '0s'))
        origin=parent_origin+seconds(node.get('offset','0s'))-parent_start
        length=seconds(node.get('duration','0s'))
        if length<=0 or origin<0 or origin+length>duration:raise ValueError('片段范围超出项目')
        if set(node.attrib)-{'ref','offset','name','start','duration','enabled','tcFormat','audioRole','videoRole','srcEnable','format','tcStart','modDate','lane'}:raise ValueError('暂不支持分离的 J/L 音频或未知片段属性')
        enabled=flag(node,'enabled')
        role=node.get('audioRole','dialogue').split('.')[0]
        role_nodes=node.findall('audio-channel-source')
        if len(role_nodes)==1:role=role_nodes[0].get('role',role).split('.')[0]
        excluded=audio_mode=='dialogue' and role in ('music','effects')
        gain=1.0
        volumes=node.findall('adjust-volume')
        if len(volumes)>1:raise ValueError('音量结构无效')
        if volumes and not excluded:
            v=volumes[0];amount=v.get('amount','0dB')
            if len(v) or set(v.attrib)-{'amount'} or not re.fullmatch(r'-?\d+(?:\.\d+)?dB',amount):raise ValueError('暂不支持音量关键帧或淡入淡出')
            db=float(amount[:-2])
            if not -96<=db<=12:raise ValueError('音量超出支持范围')
            gain*=10**(db/20)
        harmless={'caption','adjust-volume','audio-channel-source','adjust-transform','adjust-crop','adjust-conform','adjust-blend','filter-video','metadata','marker','keyword','rating'}
        if excluded:harmless.add('filter-audio')
        children=[]
        for child in node:
            if child.tag in ('asset-clip','gap'):children.append(child)
            elif child.tag not in harmless:raise ValueError('暂不支持音频效果、变速或嵌套模板：'+child.tag)
        if node.tag=='asset-clip':
            if asset is None:raise ValueError('媒体资源缺失')
            source_enable=node.get('srcEnable','all')
            if source_enable not in ('all','audio','video'):raise ValueError('无效的音频启用状态')
            channels=node.findall('audio-channel-source')
            if len(channels)>1 and not excluded:raise ValueError('暂不支持多音频组件；请使用单声道或立体声片段')
            if channels and not excluded:
                c=channels[0]
                if len(c) or set(c.attrib)-{'srcCh','role','active','enabled'} or c.get('srcCh') not in ('1','1, 2','1,2'):raise ValueError('暂不支持音频通道重映射或效果')
                role=c.get('role',role).split('.')[0];enabled=enabled and flag(c,'active') and flag(c,'enabled')
            if role not in ('dialogue','music','effects'):raise ValueError('未知音频角色，请在 FCP 中设置对白、音乐或效果角色')
            if asset.get('hasAudio')=='1' and enabled and source_enable!='video' and (audio_mode=='all' or role=='dialogue'):
                if asset.get('audioChannels') not in ('1','2') or asset.get('audioSources','1')!='1':raise ValueError('暂不支持多通道媒体')
                reps=asset.findall("media-rep[@kind='original-media']")
                if len(reps)!=1:raise ValueError('缺少原始媒体引用')
                url=urlparse(reps[0].get('src',''))
                if url.scheme!='file' or url.netloc not in ('','localhost'):raise ValueError('需要本机原始媒体')
                source=start-seconds(asset.get('start','0s'))
                if source<0 or source+length>seconds(asset.get('duration','0s')):raise ValueError('源音频范围无效')
                segments.append(dict(assetRef=node.get('ref'),media=str(Path(unquote(url.path))),offset=str(origin),duration=str(length),source_start=str(source),startSample=sample(origin),sampleCount=sample(origin+length)-sample(origin),gain=gain,role=role))
            elif asset.get('hasAudio')=='1' and role!='dialogue' and audio_mode=='dialogue':ignored+=1
        for child in children:walk(child,origin,start)
    cursor=Fraction(0)
    for node in spine:
        offset=seconds(node.get('offset','0s'))-tc;length=seconds(node.get('duration','0s'))
        if offset!=cursor:raise ValueError('主要故事情节必须连续；请保留空隙片段')
        walk(node,Fraction(0),tc);cursor+=length
    if cursor!=duration:raise ValueError('项目音频范围不完整')
    return dict(project=project.get('name','未命名项目'),uid=project.get('uid'),duration=str(duration),relative_start='0',frameDuration=str(frame),totalFrames=int(duration/frame),width=fmt.get('width','1920'),height=fmt.get('height','1080'),colorSpace=fmt.get('colorSpace','1-1-1 (Rec. 709)'),sampleCount=sample(duration),segments=segments,audioMode=audio_mode,ignoredRoleClips=ignored,audibility='XML-defined dialogue roles' if audio_mode=='dialogue' else 'XML-defined mix; FCP live role/solo monitoring not included')

def render(xml,directory,binary,expected_uid,audio_mode='dialogue'):
    plan=inspect(xml,audio_mode)
    if plan['uid']!=expected_uid:raise ValueError('项目身份不匹配')
    root=ET.fromstring(xml.read_bytes());pcm=array('f',[0])*plan['sampleCount'];reports=[]
    for i,segment in enumerate(plan['segments']):
        remaining=segment['sampleCount'];done=0
        while remaining:
            count=min(remaining,30*RATE)
            doc=ET.Element('fcpxml',version='1.14');res=ET.SubElement(doc,'resources')
            asset=deepcopy(root.find(f"resources/asset[@id='{segment['assetRef']}']"))
            for p in asset.iter():
                for c in list(p):
                    if c.tag in ('bookmark','metadata'):p.remove(c)
            res.append(asset);pr=ET.SubElement(doc,'project',name=plan['project'],uid=expected_uid)
            length=Fraction(count,RATE);seq=ET.SubElement(pr,'sequence',duration=str(length)+'s',tcStart='0s');spine=ET.SubElement(seq,'spine')
            start=seconds(asset.get('start','0s'))+Fraction(sample(Fraction(segment['source_start']))+done,RATE)
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
            base=segment['startSample']+done;gain=segment['gain']
            # Sum overlapping dialogue, preserving the original project clock.
            pcm[base:base+count]=array('f',(pcm[base+k]+v*gain for k,v in enumerate(values)))
            done+=count;remaining-=count
        reports.append(dict(index=i,sampleCount=segment['sampleCount'],gain=segment['gain']))
    energy=sum(float(v)*v for v in pcm)
    if sys.byteorder!='little':pcm.byteswap()
    data=pcm.tobytes();(directory/'timeline.f32le').write_bytes(data)
    return dict(status='decoded',pcmFile='timeline.f32le',sampleCount=plan['sampleCount'],sampleRate=RATE,channels=1,pcmBytes=len(data),pcmSHA256=hashlib.sha256(data).hexdigest(),rms=math.sqrt(energy/plan['sampleCount']),silent=energy==0,segments=reports,plan=plan)
