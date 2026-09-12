"""Bounded XML audio renderer: consecutive mono clips/gaps, static gain and mute.

This is XML-defined audio, not FCP's live solo/role monitoring mix. Effects,
retiming, J/L edits, layered audio and channel remapping remain unsupported.
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

RATE = 16000
MAX_SECONDS = 30


def flag(node, key, default='1'):
    value = node.get(key, default)
    if value not in ('0', '1'):
        raise ValueError(f'Invalid {key}')
    return value == '1'


def sample(time):
    count = time * RATE
    if count.denominator != 1:
        raise ValueError('Audio boundary must fall on a 16kHz sample')
    return int(count)


def inspect(path):
    data = path.read_bytes()
    if len(data) > 16*1024*1024 or b'<!ENTITY' in data.upper():
        raise ValueError('Unsafe XML')
    root = ET.fromstring(data)
    projects = root.findall('.//project')
    if len(projects) != 1:
        raise ValueError('One project required')
    project = projects[0]
    sequences = project.findall('sequence')
    if len(sequences) != 1:
        raise ValueError('One sequence required')
    seq = sequences[0]
    if len(seq) != 1 or seq[0].tag != 'spine':
        raise ValueError('One plain spine required')
    spine = seq[0]
    if not 1 <= len(spine) <= 64 or spine.attrib:
        raise ValueError('Unsupported spine')
    duration = seconds(seq.get('duration', '0s'))
    if not 0 < duration <= MAX_SECONDS:
        raise ValueError('Timeline limited to 30 seconds')
    fmt = root.find(f"resources/format[@id='{seq.get('format')}']")
    if fmt is None or seconds(fmt.get('frameDuration','0s')) != Fraction(1,25):
        raise ValueError('25fps timeline required')
    tc = seconds(seq.get('tcStart','0s'))
    segments = []
    cursor = Fraction(0)
    for clip in spine:
        if clip.tag not in ('asset-clip','gap'):
            raise ValueError('Only consecutive asset clips and gaps supported')
        allowed = {'ref','offset','name','start','duration','enabled','tcFormat','audioRole','videoRole','srcEnable','format','tcStart','modDate'} if clip.tag == 'asset-clip' else {'offset','name','start','duration','enabled'}
        if set(clip.attrib)-allowed:
            raise ValueError('Unsupported clip attributes (including J/L edits)')
        offset = seconds(clip.get('offset','0s'))-tc
        length = seconds(clip.get('duration','0s'))
        if offset != cursor or length <= 0 or offset+length > duration:
            raise ValueError('Clips must cover the timeline consecutively; use explicit gaps')
        start_sample, count = sample(offset), sample(length)
        if (offset*25).denominator != 1 or (length*25).denominator != 1:
            raise ValueError('Clip boundary must fall on a frame')
        cursor += length
        enabled = flag(clip,'enabled')
        segment = dict(kind=clip.tag, offset=str(offset), duration=str(length),
                       startSample=start_sample, sampleCount=count, gain=0.0, media=None)
        if clip.tag == 'gap':
            if any(c.tag != 'caption' for c in clip):
                raise ValueError('Nested media inside gaps unsupported')
            segments.append(segment)
            continue
        if clip.get('audioRole') != 'dialogue':
            raise ValueError('Only dialogue role supported')
        source_enable = clip.get('srcEnable','all')
        if source_enable not in ('all','audio','video'):
            raise ValueError('Invalid source enable')
        if any(c.tag not in ('caption','adjust-volume','audio-channel-source') for c in clip):
            raise ValueError('Effects, retiming and nested media unsupported')
        assets = root.findall(f"resources/asset[@id='{clip.get('ref')}']")
        if len(assets) != 1:
            raise ValueError('Unique asset required')
        asset = assets[0]
        if asset.get('hasAudio') != '1' or asset.get('audioChannels') != '1' or asset.get('audioSources','1') != '1':
            raise ValueError('Single mono audio source required')
        reps = asset.findall("media-rep[@kind='original-media']")
        if len(reps) != 1:
            raise ValueError('One original media reference required')
        url = urlparse(reps[0].get('src',''))
        if url.scheme != 'file' or url.netloc not in ('','localhost'):
            raise ValueError('Local media only')
        asset_start = seconds(asset.get('start','0s'))
        source = seconds(clip.get('start',asset.get('start','0s')))-asset_start
        if source < 0 or source+length > seconds(asset.get('duration','0s')):
            raise ValueError('Source range outside media')
        sample(source)
        gain = 1.0
        volumes = clip.findall('adjust-volume')
        if len(volumes) > 1:
            raise ValueError('One volume adjustment required')
        if volumes:
            volume = volumes[0]
            amount = volume.get('amount','0dB')
            if len(volume) or set(volume.attrib)-{'amount'} or not re.fullmatch(r'-?\d+(?:\.\d+)?dB',amount):
                raise ValueError('Only constant volume supported')
            db = float(amount[:-2])
            if not -96 <= db <= 0:
                raise ValueError('Only volume attenuation from -96 to 0dB supported')
            gain = 10 ** (db/20)
        channels = clip.findall('audio-channel-source')
        if len(channels) > 1:
            raise ValueError('Channel remapping unsupported')
        if channels:
            channel = channels[0]
            if len(channel) or set(channel.attrib)-{'srcCh','role','active','enabled'} or channel.get('srcCh') != '1' or channel.get('role','dialogue').split('.')[0] != 'dialogue':
                raise ValueError('Channel effects/remapping unsupported')
            enabled = enabled and flag(channel,'active') and flag(channel,'enabled')
        if not enabled or source_enable == 'video':
            gain = 0.0
        segment.update(media=str(Path(unquote(url.path))), source_start=str(source),
                       assetRef=clip.get('ref'), gain=gain)
        segments.append(segment)
    if cursor != duration:
        raise ValueError('Incomplete timeline coverage')
    return dict(project=project.get('name'),uid=project.get('uid'),duration=str(duration),
                relative_start='0',sampleCount=sample(duration),segments=segments,
                audibility='XML-defined mono timeline; live role/solo monitoring state not represented')


def render(xml, directory, binary, expected_uid):
    plan = inspect(xml)
    if plan['uid'] != expected_uid:
        raise ValueError('Active project mismatch')
    root = ET.fromstring(xml.read_bytes())
    pcm = array('f', [0.0]) * plan['sampleCount']
    reports = []
    for i, segment in enumerate(plan['segments']):
        if segment['gain'] == 0:
            continue
        # Native decoder receives a minimal bounded source segment, not effects
        # it would silently ignore. Original XML remains untouched in the job.
        doc = ET.Element('fcpxml',version='1.14')
        resources = ET.SubElement(doc,'resources')
        asset = deepcopy(root.find(f"resources/asset[@id='{segment['assetRef']}']"))
        for parent in asset.iter():
            for child in list(parent):
                if child.tag in ('bookmark','metadata'):parent.remove(child)
        resources.append(asset)
        project = ET.SubElement(doc,'project',name=plan['project'],uid=expected_uid)
        seq = ET.SubElement(project,'sequence',duration=segment['duration']+'s',tcStart='0s')
        spine = ET.SubElement(seq,'spine')
        start = seconds(asset.get('start','0s'))+Fraction(segment['source_start'])
        ET.SubElement(spine,'asset-clip',ref=segment['assetRef'],offset='0s',start=str(start)+'s',
                      duration=segment['duration']+'s',audioRole='dialogue')
        source_xml = directory/f'segment-{i:03}.fcpxml'
        source_xml.write_bytes(ET.tostring(doc,encoding='utf-8'))
        result = subprocess.run([str(binary),str(source_xml),expected_uid,str(directory)],
                                capture_output=True,text=True,check=True,timeout=60)
        decoded = json.loads(result.stdout)
        if decoded.get('status') != 'decoded':
            raise ValueError('Segment decode failed: '+decoded.get('stage','unknown'))
        name = decoded.get('pcmFile','')
        if Path(name).name != name or not name:
            raise ValueError('Invalid decoder output path')
        values = array('f')
        values.frombytes((directory/name).read_bytes())
        if sys.byteorder != 'little':values.byteswap()
        if len(values) != segment['sampleCount'] or not all(math.isfinite(v) for v in values):
            raise ValueError('Invalid decoded segment samples')
        offset = segment['startSample']
        gain = segment['gain']
        if gain != 1:
            values = array('f',(v*gain for v in values))
        pcm[offset:offset+len(values)] = values
        reports.append(dict(index=i,sourceStart=segment['source_start'],sampleCount=len(values),gain=gain))
    energy = sum(float(v)*v for v in pcm)
    if sys.byteorder != 'little':pcm.byteswap()
    data = pcm.tobytes()
    name = 'timeline.f32le'
    (directory/name).write_bytes(data)
    return dict(status='decoded',pcmFile=name,sampleCount=plan['sampleCount'],sampleRate=RATE,channels=1,
                pcmBytes=len(data),pcmSHA256=hashlib.sha256(data).hexdigest(),rms=math.sqrt(energy/plan['sampleCount']),
                silent=energy == 0,segments=reports,plan=plan)
