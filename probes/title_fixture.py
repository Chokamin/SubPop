"""Bounded clip-only Title drag fixture; no project replacement or media access."""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

UID='0D11EC79-ED11-4688-97A9-CB78621857DD'
EFFECT='.../Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti'

def payload(manifest, version='1.14'):
    if version not in ('1.12','1.13','1.14'):raise ValueError('Unsupported XML version')
    if manifest['projectUID']!=UID or manifest['fps']!=25:raise ValueError('Isolated 25fps project only')
    rows=manifest['captions']
    if not rows:raise ValueError('No titles')
    root=ET.Element('fcpxml',version=version)
    resources=ET.SubElement(root,'resources')
    ET.SubElement(resources,'format',id='r1',name='FFVideoFormatRateUndefined',frameDuration='1/25s',width='640',height='360',colorSpace='1-1-1 (Rec. 709)')
    ET.SubElement(resources,'effect',id='r2',name='基本字幕',uid=EFFECT)
    clip=ET.SubElement(root,'clip',name='SubPop ASR Titles Probe',format='r1',start='0s',duration='217/25s',tcFormat='NDF')
    spine=ET.SubElement(clip,'spine');cursor=0
    for i,row in enumerate(rows,1):
        start,end=row['start_frame'],row['end_frame']
        if type(start)!=int or type(end)!=int or not cursor<=start<end<=217 or not row['text'].strip():
            raise ValueError('Invalid or overlapping title timing')
        if start>cursor:ET.SubElement(spine,'gap',name='Gap',offset=f'{cursor}/25s',start='0s',duration=f'{start-cursor}/25s')
        title=ET.SubElement(spine,'title',ref='r2',offset=f'{start}/25s',name=row['text'],start='0s',duration=f'{end-start}/25s')
        ET.SubElement(ET.SubElement(title,'text'),'text-style',ref=f'ts{i}').text=row['text']
        style=ET.SubElement(title,'text-style-def',id=f'ts{i}')
        ET.SubElement(style,'text-style',font='Helvetica',fontSize='28',fontFace='Regular',fontColor='1 1 1 1',alignment='center')
        cursor=end
    if cursor<217:ET.SubElement(spine,'gap',name='Gap',offset=f'{cursor}/25s',start='0s',duration=f'{217-cursor}/25s')
    ET.indent(root)
    return b'<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE fcpxml>\n'+ET.tostring(root,encoding='utf-8')+b'\n'

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--manifest',type=Path,required=True);p.add_argument('--output-dir',type=Path,required=True);a=p.parse_args()
    a.output_dir.mkdir(parents=True,exist_ok=True)
    for v in ('1.12','1.13','1.14'):(a.output_dir/f'TitleProbe-{v}.fcpxml').write_bytes(payload(json.loads(a.manifest.read_text()),v))
