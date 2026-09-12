"""Read-only verifier for the deliberately simple Subloom FCP fixture.

Not a general timeline reader. Rejects everything outside this probe's scope.
"""
from fractions import Fraction
from pathlib import Path
from urllib.parse import urlparse, unquote
import xml.etree.ElementTree as ET


def seconds(value):
    if not value.endswith('s'):
        raise ValueError('Expected FCPXML rational seconds')
    return Fraction(value[:-1])


def inspect(path):
    root = ET.parse(path).getroot()
    projects = root.findall('.//project')
    if len(projects) != 1:
        raise ValueError('Probe requires exactly one project')
    project = projects[0]
    seq = project.find('sequence')
    if seq is None:
        raise ValueError('Missing sequence')
    spine = seq.find('spine')
    if spine is None or len(spine) != 1 or spine[0].tag != 'asset-clip':
        raise ValueError('Probe supports one plain asset-clip only')
    clip = spine[0]
    if clip.get('srcEnable', 'all') not in ('all', 'audio') or any(k in clip.attrib for k in ('audioStart', 'audioDuration')):
        raise ValueError('Disabled source audio or split audio edits are unverified')
    if any(c.tag != 'caption' for c in clip):
        raise ValueError('Retime, components, effects and nested clips are unverified')
    if clip.get('enabled', '1') != '1' or clip.get('audioRole') != 'dialogue':
        raise ValueError('Probe requires enabled dialogue clip; audibility is NOT inferred')
    asset = root.find(f"resources/asset[@id='{clip.get('ref')}']")
    if asset is None or asset.get('hasAudio') != '1':
        raise ValueError('Missing audio asset')
    media = asset.find("media-rep[@kind='original-media']")
    if media is None:
        raise ValueError('Missing original media')
    url = urlparse(media.get('src', ''))
    if url.scheme != 'file' or url.netloc not in ('', 'localhost'):
        raise ValueError('Local media only')
    start = seconds(clip.get('start', asset.get('start', '0s')))
    offset = seconds(clip.get('offset', '0s'))
    tc_start = seconds(seq.get('tcStart', '0s'))
    duration = seconds(clip.get('duration', '0s'))
    if duration <= 0 or duration > 30:
        raise ValueError('Probe limited to 30 seconds')
    source_start = start - seconds(asset.get('start', '0s'))
    if source_start < 0:
        raise ValueError('Negative media trim')
    captions = []
    for caption in clip.findall('caption'):
        position = offset + seconds(caption.get('offset', '0s')) - start
        captions.append(dict(text=''.join(caption.find('text').itertext()).strip(),
                             absolute_start=str(position),
                             relative_start=str(position-tc_start),
                             duration=str(seconds(caption.get('duration', '0s')))))
    return dict(project=project.get('name'), uid=project.get('uid'),
                media=str(Path(unquote(url.path))), source_start=str(source_start),
                relative_start=str(offset-tc_start), duration=str(duration),
                captions=captions, audibility='unknown: XML clip enabled is not role/solo state')
