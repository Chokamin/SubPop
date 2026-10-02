"""Explicit FCP synchronized-source and multicam angle selection.

No angle is guessed and inactive sources are never mixed back in.
"""

from fractions import Fraction
from .readback import seconds


# FCPXML 1.14 intrinsic-params-video plus video filters. These only affect
# pictures; audio planning must keep the clip's original timing and routing.
# Share this explicit set across clips and multicam sources so new visual
# settings cannot be mistaken for unsupported audio or time-map operations.
VIDEO_ONLY_CHILDREN=frozenset({
    'object-tracker','adjust-crop','adjust-corners','adjust-conform',
    'adjust-transform','adjust-blend','adjust-stabilization',
    'adjust-rollingShutter','adjust-360-transform','adjust-reorient',
    'adjust-orientation','adjust-cinematic','adjust-colorConform',
    'adjust-stereo-3D','filter-video','filter-video-mask',
})


def synchronized_sources(node):
    sources={}
    for source in node.findall('sync-source'):
        key=source.get('sourceID')
        if key not in ('storyline','connected') or key in sources or set(source.attrib)!={'sourceID'}:
            raise ValueError('同步片段音频来源设置无效')
        if any(child.tag!='audio-role-source' for child in source):
            raise ValueError('同步片段音频组件结构无效')
        sources[key]=tuple(source)
    return sources


def multicam_sources(node, medias):
    media=medias.get(node.get('ref'))
    multicam=media.find('multicam') if media is not None else None
    if multicam is None:raise ValueError('多机位媒体引用缺失')
    angles={}
    for angle in multicam.findall('mc-angle'):
        key=angle.get('angleID')
        if not key or key in angles or set(angle.attrib)-{'angleID','name'}:
            raise ValueError('多机位角度设置无效')
        angles[key]=angle
    sources=[];seen=set()
    for source in node.findall('mc-source'):
        key=source.get('angleID');mode=source.get('srcEnable','all')
        if key not in angles or key in seen or mode not in ('all','audio','video','none') or set(source.attrib)-{'angleID','srcEnable'}:
            raise ValueError('多机位选中来源无效')
        if any(child.tag not in VIDEO_ONLY_CHILDREN and child.tag!='audio-role-source' for child in source):
            raise ValueError('多机位来源包含未知设置')
        seen.add(key)
        if mode!='none':sources.append((angles[key],source))
    if not seen:raise ValueError('多机位未提供选中的音频／画面角度；可导入整条时间线音频')
    return multicam,sources


def conform_audio_speed(node,root,assets,frame,media_seq=None,audible=True,nested=False):
    conform=node.findall('conform-rate')
    if len(conform)>1:raise ValueError('帧率适配结构无效')
    conform_speed=Fraction(1)
    if conform:
        c=conform[0]
        if len(c) or set(c.attrib)-{'scaleEnabled','srcFrameRate','frameSampling'}:raise ValueError('帧率适配结构无效')
        scale=c.get('scaleEnabled','1') # FCPXML DTD default.
        if scale not in ('0','1'):raise ValueError('帧率适配结构无效')
        if scale=='1' and audible:
            asset=assets.get(node.get('ref')) if node.tag in ('asset-clip','audio') else None
            audio_assets=[asset] if asset is not None else [assets.get(child.get('ref')) for child in node.iter() if child.tag in ('asset-clip','audio')]
            source_frames=[]
            for audio_asset in audio_assets:
                source_format=root.find(f"resources/format[@id='{audio_asset.get('format')}']") if audio_asset is not None else None
                source_frames.append(seconds(source_format.get('frameDuration','0s')) if source_format is not None else None)
            source_rate=c.get('srcFrameRate')
            known_frame={'60':Fraction(1,60),'59.94':Fraction(1001,60000),'29.97':Fraction(1001,30000)}.get(source_rate)
            clip_format=root.find(f"resources/format[@id='{node.get('format')}']")
            clip_frame=seconds(clip_format.get('frameDuration','0s')) if clip_format is not None else None
            explicit_source=(node.tag in ('asset-clip','clip') and known_frame is not None
                and source_frames and all(rate==known_frame for rate in source_frames)
                and clip_frame==known_frame)
            # Read the effective clip format, not merely its resource ID.
            multicam_format=root.find(f"resources/format[@id='{media_seq.get('format')}']") if node.tag=='mc-clip' else None
            if source_rate=='29.97' and frame==Fraction(1,30) and (
                    explicit_source or node.tag=='sync-clip' and clip_frame==known_frame
                    or multicam_format is not None and seconds(multicam_format.get('frameDuration','0s'))==known_frame):
                # Verified FCP 12.3 export: a source-format 29.97 clip is
                # played 1001/1000 as fast in a 30 fps parent clock.
                conform_speed=Fraction(1001,1000)
            elif (known_frame is not None and frame==known_frame and (
                    explicit_source or node.tag=='sync-clip' and clip_frame==known_frame
                    or multicam_format is not None and seconds(multicam_format.get('frameDuration','0s'))==known_frame)):
                # A redundant marker in a nested source-format sequence does
                # not inherit the outer project's rate conversion.
                conform_speed=Fraction(1)
            elif explicit_source:
                conform_speed=Fraction(1)
            elif (node.tag in ('asset-clip','clip') and source_rate in ('59.94','29.97')
                  and source_frames and all(rate==known_frame for rate in source_frames)
                  and clip_frame is None and not node.get('format')):
                # FCP 12.3 round-trips these 59.94 sources at 1x in
                # 25/29.97/59.94 projects, dropping redundant conform-rate.
                conform_speed=Fraction(1)
            elif (node.tag in ('asset-clip','clip') and not nested and source_rate=='60'
                  and source_frames and all(rate==known_frame for rate in source_frames)
                  and frame==Fraction(1001,30000)):
                conform_speed=Fraction(2)
            else:
                raise ValueError('暂不支持此有声片段的速度缩放帧率适配')
    return conform_speed
