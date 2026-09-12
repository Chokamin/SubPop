"""Bounded clip-only Title drag fixture; no project replacement or media access."""
import argparse
import json
from fractions import Fraction
from pathlib import Path
import xml.etree.ElementTree as ET

UID='0D11EC79-ED11-4688-97A9-CB78621857DD'
EFFECT='.../Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti'

def payload(manifest, version='1.14'):
    if version not in ('1.12','1.13','1.14'):raise ValueError('Unsupported XML version')
    generic='frameDuration' in manifest
    if not generic and (manifest['projectUID']!=UID or manifest['fps']!=25):raise ValueError('Isolated 25fps project only')
    frame=Fraction(manifest.get('frameDuration','1/25'));total=manifest.get('totalFrames',217)
    if frame<=0 or type(total)!=int or not 0<total<=108000:raise ValueError('Invalid project timing')
    def t(n):return str(n*frame)+'s' if generic else f'{n}/25s'
    style_values=manifest.get('style',{})
    font=style_values.get('font','Helvetica');size=style_values.get('fontSize',72 if generic else 28)
    if font not in ('Helvetica','PingFang SC','Arial') or type(size) not in (int,float) or not 12<=size<=120:raise ValueError('Invalid title style')
    rows=manifest['captions']
    if not rows:raise ValueError('No titles')
    root=ET.Element('fcpxml',version=version)
    resources=ET.SubElement(root,'resources')
    ET.SubElement(resources,'format',id='r1',name='FFVideoFormatRateUndefined',frameDuration=str(frame)+'s',width=str(manifest.get('width','640')),height=str(manifest.get('height','360')),colorSpace=manifest.get('colorSpace','1-1-1 (Rec. 709)'))
    ET.SubElement(resources,'effect',id='r2',name='基本字幕',uid=EFFECT)
    clip=ET.SubElement(root,'clip',name='SubPop 中文字幕' if generic else 'SubPop ASR Titles Probe',format='r1',start='0s',duration=t(total),tcFormat='NDF')
    spine=ET.SubElement(clip,'spine');cursor=0
    for i,row in enumerate(rows,1):
        start,end=row['start_frame'],row['end_frame']
        if type(start)!=int or type(end)!=int or not cursor<=start<end<=total or not row['text'].strip():
            raise ValueError('Invalid or overlapping title timing')
        if start>cursor:ET.SubElement(spine,'gap',name='Gap',offset=t(cursor),start='0s',duration=t(start-cursor))
        title=ET.SubElement(spine,'title',ref='r2',offset=t(start),name=row['text'],start='0s',duration=t(end-start))
        ET.SubElement(ET.SubElement(title,'text'),'text-style',ref=f'ts{i}').text=row['text']
        style=ET.SubElement(title,'text-style-def',id=f'ts{i}')
        ET.SubElement(style,'text-style',font=font,fontSize=str(size),fontFace='Regular',fontColor='1 1 1 1',alignment='center')
        if generic:ET.SubElement(title,'adjust-transform',position='0 -40')
        cursor=end
    if cursor<total:ET.SubElement(spine,'gap',name='Gap',offset=t(cursor),start='0s',duration=t(total-cursor))
    ET.indent(root)
    return b'<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE fcpxml>\n'+ET.tostring(root,encoding='utf-8')+b'\n'

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--manifest',type=Path,required=True);p.add_argument('--output-dir',type=Path,required=True);a=p.parse_args()
    a.output_dir.mkdir(parents=True,exist_ok=True)
    for v in ('1.12','1.13','1.14'):(a.output_dir/f'TitleProbe-{v}.fcpxml').write_bytes(payload(json.loads(a.manifest.read_text()),v))
