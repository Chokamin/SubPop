"""Create an isolated FCP test project, never a production import path."""
from pathlib import Path
import xml.etree.ElementTree as ET


def fixture(media):
    root = ET.Element('fcpxml', version='1.14')
    resources = ET.SubElement(root, 'resources')
    ET.SubElement(resources, 'format', id='r1', frameDuration='1/25s', width='640', height='360', colorSpace='1-1-1 (Rec. 709)')
    asset = ET.SubElement(resources, 'asset', id='r2', name='mandarin', start='0s', duration='217/25s', hasVideo='1', format='r1', hasAudio='1', audioSources='1', audioChannels='1', audioRate='16000')
    ET.SubElement(asset, 'media-rep', kind='original-media', src=media.resolve().as_uri())
    event = ET.SubElement(root, 'event', name='Subloom-Probe')
    project = ET.SubElement(event, 'project', name='Subloom-Original')
    seq = ET.SubElement(project, 'sequence', format='r1', duration='217/25s', tcStart='3600s', tcFormat='NDF', audioLayout='stereo', audioRate='48k')
    spine = ET.SubElement(seq, 'spine')
    ET.SubElement(spine, 'asset-clip', ref='r2', name='mandarin', offset='3600s', start='0s', duration='217/25s', audioRole='dialogue')
    ET.indent(root)
    return ET.tostring(root, encoding='unicode', xml_declaration=True)


if __name__ == '__main__':
    folder = Path(__file__).resolve().parents[1] / '.subloom/verification'
    (folder / 'original.fcpxml').write_text(fixture(folder / 'mandarin.mp4'))
    (folder / 'position-probe.srt').write_text('1\n00:00:01,000 --> 00:00:02,000\nSubloom 简体字幕定位测试\n\n2\n00:00:04,000 --> 00:00:05,200\n保留 3.5% 和 USB-C\n', encoding='utf-8-sig')
