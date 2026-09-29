"""Full-timeline audio fallback. Project XML supplies the clock, never source audio.

The exported file must cover the whole project from its first frame. A native
AVFoundation probe checks its duration and decodes bounded 30-second chunks.
"""
from array import array
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

from .project import RATE, sample
from .readback import seconds

SUPPORTED={'.wav','.aif','.aiff','.m4a','.caf'}
MAX_AUDIO_BYTES=4*1024*1024*1024
MAX_PROJECT_SECONDS=4*60*60


def project_context(xml):
    raw=xml.read_bytes()
    if not raw or len(raw)>16*1024*1024 or b'<!ENTITY' in raw.upper():
        raise ValueError('无效的项目快照')
    root=ET.fromstring(raw)
    projects=root.findall('.//project')
    if len(projects)!=1:raise ValueError('请先拖入一个完整的 FCP 项目')
    project=projects[0];sequence=project.find('sequence')
    if sequence is None or not project.get('uid') or sequence.find('spine') is None:
        raise ValueError('项目没有有效时间线')
    duration=seconds(sequence.get('duration','0s'))
    if duration<=0 or duration>MAX_PROJECT_SECONDS:raise ValueError('项目时长无效或超过四小时')
    fmt=next((f for f in root.findall('resources/format') if f.get('id')==sequence.get('format')),None)
    if fmt is None:raise ValueError('缺少项目格式')
    frame=seconds(fmt.get('frameDuration','0s'))
    if frame not in [Fraction(1,n) for n in (24,25,30,50,60)]+[Fraction(1001,n) for n in (24000,30000,60000)]:
        raise ValueError('暂不支持此项目帧率')
    return dict(project=project.get('name','未命名项目'),uid=project.get('uid'),duration=str(duration),
                relative_start='0',frameDuration=str(frame),totalFrames=math.ceil(duration/frame),
                width=fmt.get('width','1920'),height=fmt.get('height','1080'),
                colorSpace=fmt.get('colorSpace','1-1-1 (Rec. 709)'),sampleCount=sample(duration),
                segments=[],skippedAudio=[],bypassedAudioEffects=0,audioMode='exported',
                ignoredRoleClips=0,audibility='User-exported full FCP timeline mix')


def validate_file(path, expected_sha=None):
    if path.is_symlink() or not path.is_file() or path.suffix.lower() not in SUPPORTED:
        raise ValueError('请拖入 WAV、AIFF、M4A 或 CAF 音频文件')
    if not 0<path.stat().st_size<=MAX_AUDIO_BYTES:raise ValueError('音频文件为空或超过 4 GB')
    digest=hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda:source.read(1024*1024),b''):digest.update(block)
    if expected_sha and digest.hexdigest()!=expected_sha:raise ValueError('导出音频已改变，请重新拖入')
    return digest.hexdigest()


def file_duration(path,binary):
    result=subprocess.run([str(binary),'--inspect-file',str(path)],capture_output=True,text=True,check=True,timeout=30)
    info=json.loads(result.stdout)
    if info.get('status')!='ready':raise ValueError('无法读取导出音频：'+info.get('stage','unknown'))
    return Fraction(info['durationValue'],info['durationScale'])


def chunk_xml(path,uid,start,count):
    duration=Fraction(count,RATE)
    root=ET.Element('fcpxml',version='1.14');resources=ET.SubElement(root,'resources')
    asset=ET.SubElement(resources,'asset',id='exported',name='导出的整条时间线音频',start='0s',
                        duration=str(start+duration)+'s',hasAudio='1')
    ET.SubElement(asset,'media-rep',kind='original-media',src=path.as_uri())
    project=ET.SubElement(root,'project',uid=uid,name='导出音频')
    sequence=ET.SubElement(project,'sequence',duration=str(duration)+'s',tcStart='0s')
    spine=ET.SubElement(sequence,'spine')
    ET.SubElement(spine,'asset-clip',ref='exported',offset='0s',start=str(start)+'s',
                  duration=str(duration)+'s',audioRole='dialogue')
    return ET.tostring(root,encoding='utf-8')


def render(path,directory,binary,snapshot,expected_sha=None):
    validate_file(path,expected_sha)
    actual=file_duration(path,binary)
    expected=Fraction(snapshot['duration']);frame=Fraction(snapshot['frameDuration'])
    # Allow only a codec tail (up to 50 ms); never accept a partial export.
    tolerance=max(frame,Fraction(1,20))
    if abs(actual-expected)>tolerance:
        raise ValueError(f'导出音频时长 {float(actual):.2f} 秒与项目 {float(expected):.2f} 秒不符；请从项目起点导出整条时间线')
    total=snapshot['sampleCount'];available=min(total,sample(actual))
    if total-available>sample(tolerance):raise ValueError('导出音频未覆盖项目结尾')
    output=directory/'timeline.f32le';digest=hashlib.sha256();energy=0.0
    with output.open('wb') as dest:
        cursor=0
        while cursor<available:
            count=min(30*RATE,available-cursor)
            source_xml=directory/'decode-segment.fcpxml'
            source_xml.write_bytes(chunk_xml(path,snapshot['uid'],Fraction(cursor,RATE),count))
            response=subprocess.run([str(binary),str(source_xml),snapshot['uid'],str(directory)],
                                    capture_output=True,text=True,check=True,timeout=90)
            item=json.loads(response.stdout)
            if item.get('status')!='decoded':raise ValueError('无法解码导出音频：'+item.get('stage','unknown'))
            name=item.get('pcmFile','')
            if not name or Path(name).name!=name:raise ValueError('无效的解码结果')
            part=directory/name
            data=part.read_bytes();part.unlink()
            if len(data)!=count*4:raise ValueError('导出音频解码不完整')
            values=array('f');values.frombytes(data)
            if sys.byteorder!='little':values.byteswap()
            if not all(math.isfinite(value) for value in values):raise ValueError('导出音频包含无效采样')
            energy+=sum(float(value)*value for value in values)
            dest.write(data);digest.update(data);cursor+=count
        if cursor<total:
            zeros=b'\0'*((total-cursor)*4);dest.write(zeros);digest.update(zeros)
    return dict(status='decoded',pcmFile=output.name,sampleCount=total,sampleRate=RATE,channels=1,
                pcmBytes=total*4,pcmSHA256=digest.hexdigest(),rms=math.sqrt(energy/total),
                silent=energy==0,source='exported-full-timeline-audio',audioDuration=str(actual))
