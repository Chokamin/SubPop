"""Pure video settings must not alter the snapshot's source-audio plan."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as E

from probes.project import inspect
from probes.snapshot import prepare
from test_project import basic, compound
from test_source_clips import multicam, synchronized


DTD = Path(__file__).resolve().parents[1] / '.subloom/verification/FCPXMLv1_14.dtd'
COLOR_REQUIRED = {'peakNitsOfPQSource': '1000', 'peakNitsOfSDRToPQSource': '100'}
COLOR_VARIANTS = (
    {},  # The official DTD defaults to automatic, enabled, conformNone.
    {'autoOrManual': 'automatic', 'conformType': 'conformAuto'},
    {'autoOrManual': 'manual', 'conformType': 'conformNone'},
    *({'autoOrManual': 'manual', 'conformType': conversion} for conversion in (
        'conformHLGtoSDR', 'conformPQtoSDR', 'conformHLGtoPQ', 'conformPQtoHLG',
        'conformSDRtoHLG75', 'conformSDRtoHLG100', 'conformSDRtoPQ')),
    {'enabled': '0', 'autoOrManual': 'manual', 'conformType': 'conformPQtoSDR'},
)
CONTAINERS = ('asset-clip', 'clip', 'video', 'sync-clip', 'ref-clip',
              'mc-video-source', 'mc-audio-source', 'compound-mc-source')

# FCPXML 1.14 intrinsic-params-video, plus its two video filter types.
# Keep real required attributes/children here so the regression exercises
# valid FCP structures rather than merely matching a product whitelist.
VIDEO_SETTINGS = (
    ('object-tracker', {}),
    ('adjust-crop', {'mode': 'trim'}),
    ('adjust-corners', {}),
    ('adjust-conform', {'type': 'fit'}),
    ('adjust-transform', {'position': '0 0', 'scale': '1 1'}),
    ('adjust-blend', {'amount': '0.8'}),
    ('adjust-stabilization', {'type': 'automatic'}),
    ('adjust-rollingShutter', {'amount': 'medium'}),
    ('adjust-360-transform', {'coordinates': 'spherical', 'latitude': '10'}),
    ('adjust-reorient', {'tilt': '5'}),
    ('adjust-orientation', {'mapping': 'tinyPlanet'}),
    ('adjust-cinematic', {'aperture': '2.8'}),
    ('adjust-colorConform', {**COLOR_REQUIRED, 'conformType': 'conformHLGtoSDR'}),
    ('adjust-stereo-3D', {'depth': '0.5', 'swapEyes': '1'}),
    ('filter-video', {'ref': 'visual-effect'}),
    ('filter-video-mask', {'inverted': '1'}),
)


def channel_settings(node):
    voice = E.SubElement(node, 'audio-channel-source', srcCh='1', role='dialogue.voice')
    E.SubElement(voice, 'adjust-volume', amount='-6dB')
    E.SubElement(node, 'audio-channel-source', srcCh='2', role='music.music-1')


def asset_case():
    root, _, seq, clip = basic()
    asset = root.find('resources/asset')
    asset.set('start', '0s'); asset.set('duration', '12s'); asset.set('audioChannels', '2')
    seq.set('duration', '4s')
    clip.set('start', '2s'); clip.set('duration', '4s')
    channel_settings(clip)
    return root, seq, clip


def container_case(kind):
    if kind in ('mc-video-source', 'mc-audio-source', 'compound-mc-source'):
        root, _, seq, mc, _ = multicam()
        recorder = mc.findall('mc-source')[1]
        role = E.SubElement(recorder, 'audio-role-source', role='dialogue.voice')
        E.SubElement(role, 'adjust-volume', amount='-6dB')
        target = mc.find('mc-source') if kind == 'mc-video-source' else recorder
        if kind == 'compound-mc-source':
            # The media contains a trimmed four-second edit, still referencing
            # the original recorder clock through both container levels.
            compound(root, seq, mc)
        return root, target
    if kind == 'sync-clip':
        root, _, _, sync = synchronized()
        E.SubElement(sync.findall('asset-clip')[1], 'adjust-volume', amount='-6dB')
        return root, sync
    root, seq, clip = asset_case()
    if kind == 'asset-clip':
        return root, clip
    if kind == 'ref-clip':
        seq.set('duration', '8s'); clip.set('start', '0s'); clip.set('duration', '8s')
        _, ref = compound(root, seq, clip)
        seq.set('duration', '4s'); ref.set('start', '2s'); ref.set('duration', '4s')
        return root, ref
    seq.find('spine').remove(clip)
    wrapper = E.SubElement(seq.find('spine'), 'clip', offset='3600s', start='2s', duration='4s')
    if kind == 'clip':
        for component in list(clip.findall('audio-channel-source')):
            clip.remove(component)
        clip.set('offset', '0s'); clip.set('start', '0s'); clip.set('duration', '12s')
        wrapper.append(clip)
        channel_settings(wrapper)
        return root, wrapper
    if kind == 'video':
        video = E.SubElement(wrapper, 'video', ref=clip.get('ref'), offset='0s', start='0s', duration='12s')
        audio = E.SubElement(wrapper, 'audio', ref=clip.get('ref'), lane='-1', offset='0s',
                             start='0s', duration='12s', srcCh='1', role='dialogue.voice')
        E.SubElement(audio, 'adjust-volume', amount='-6dB')
        return root, video
    raise AssertionError(kind)


def insert_visual(target, setting):
    if setting.tag.startswith('filter-video'):
        target.append(setting)
        return
    # Intrinsic video parameters precede intrinsic audio and contained clips.
    # mc-source puts role selection before its intrinsic video parameters.
    preceding = {'note', 'conform-rate', 'timeMap'}
    if target.tag == 'mc-source':
        preceding.add('audio-role-source')
    index = 0
    while index < len(target) and target[index].tag in preceding:
        index += 1
    target.insert(index, setting)


def add_color(target, attrs=None):
    node = E.Element('adjust-colorConform', {**COLOR_REQUIRED, **(attrs or {})})
    insert_visual(target, node)
    return node


def add_setting(root, target, tag, attrs):
    node = E.Element(tag, attrs)
    if tag == 'object-tracker':
        E.SubElement(node, 'tracking-shape', id='visual-tracker', name='Subject')
    elif tag in ('filter-video', 'filter-video-mask'):
        E.SubElement(root.find('resources'), 'effect', id='visual-effect', uid='TEST-VIDEO-EFFECT')
        if tag == 'filter-video-mask':
            E.SubElement(node, 'mask-shape', name='Face')
            E.SubElement(node, 'filter-video', ref='visual-effect')
    elif tag in ('adjust-transform', 'adjust-stabilization', 'adjust-reorient'):
        # Visual keyframes are valid and must not be mistaken for audio gain
        # animation, which the planner still refuses.
        param = E.SubElement(node, 'param', name='Video parameter', value='0')
        animation = E.SubElement(param, 'keyframeAnimation')
        E.SubElement(animation, 'keyframe', time='0s', value='0')
        E.SubElement(animation, 'keyframe', time='4s', value='1')
    insert_visual(target, node)
    return node


class VisualAdjustmentTests(unittest.TestCase):
    def pipeline(self, root, mode='dialogue'):
        # Use the same prepare -> inspect handoff as a generic dragged project.
        # No decoder, ASR, FCP UI, or real media path is needed for this stage.
        original = E.tostring(root, encoding='utf-8', xml_declaration=True)
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'source.fcpxml'
            source.write_bytes(original)
            try:
                normalized, existing = prepare(source.read_bytes(), generic=True)
                self.assertEqual(existing, [])
                prepared = Path(temp) / 'prepared.fcpxml'
                prepared.write_bytes(normalized)
                result = inspect(prepared, mode)
                # Preparing an audio snapshot retains the video's settings;
                # it does not rewrite the user's source project to remove them.
                parsed = E.fromstring(normalized)
                for tag, _ in VIDEO_SETTINGS:
                    self.assertEqual([E.tostring(n) for n in parsed.iter(tag)],
                                     [E.tostring(n) for n in root.iter(tag)])
                return result
            finally:
                self.assertEqual(source.read_bytes(), original)
                self.assertEqual(E.tostring(root, encoding='utf-8', xml_declaration=True), original)

    def assert_unchanged(self, root, target, setting):
        before = {mode: self.pipeline(root, mode) for mode in ('dialogue', 'all')}
        setting(target)
        for mode in before:
            self.assertEqual(self.pipeline(root, mode), before[mode])
        return before

    def test_color_conform_automatic_manual_disabled_and_hdr_variants_keep_audio(self):
        for attrs in COLOR_VARIANTS:
            with self.subTest(attrs=attrs):
                root, target = container_case('asset-clip')
                plans = self.assert_unchanged(root, target, lambda node: add_color(node, attrs))
                segment = plans['dialogue']['segments'][0]
                self.assertEqual((segment['source_start'], segment['startSample'], segment['sampleCount']),
                                 ('2', 0, 64000))
                self.assertEqual(segment['channelMix']['components'], [{'channels': [1], 'gain': 10**(-6/20)}])
                self.assertEqual(len(plans['all']['segments'][0]['channelMix']['components']), 2)

    def test_color_conform_in_legal_containers_preserves_trim_gain_and_source_selection(self):
        for kind in CONTAINERS:
            with self.subTest(container=kind):
                root, target = container_case(kind)
                plans = self.assert_unchanged(root, target, lambda node: add_color(node, {
                    'autoOrManual': 'manual', 'conformType': 'conformPQtoSDR'}))
                self.assertEqual(plans['dialogue']['sampleCount'], 64000)
                self.assertEqual(len(plans['dialogue']['segments']), 1)
                segment = plans['dialogue']['segments'][0]
                self.assertEqual((segment['source_start'], segment['duration']), ('2', '4'))
                if kind in ('sync-clip', 'mc-video-source', 'mc-audio-source', 'compound-mc-source'):
                    self.assertEqual(segment['assetRef'], 'external')
                    self.assertAlmostEqual(segment['gain'], 10**(-6/20))

    def test_all_official_video_settings_are_ignored_by_asset_and_multicam_audio_plans(self):
        for kind in ('asset-clip', 'mc-audio-source'):
            for tag, attrs in VIDEO_SETTINGS:
                with self.subTest(container=kind, setting=tag):
                    root, target = container_case(kind)
                    plans = self.assert_unchanged(root, target,
                        lambda node: add_setting(root, node, tag, attrs))
                    self.assertEqual(plans['dialogue']['bypassedAudioEffects'], 0)

    def test_color_conform_keeps_disabled_channels_containers_and_roles_muted(self):
        for case in ('channel', 'container', 'music', 'multicam-role', 'sync-source'):
            with self.subTest(case=case):
                kind = 'mc-audio-source' if case == 'multicam-role' else 'sync-clip' if case == 'sync-source' else 'asset-clip'
                root, target = container_case(kind)
                if case == 'channel':
                    target.find('audio-channel-source').set('enabled', '0')
                elif case == 'container':
                    target.set('enabled', '0')
                elif case == 'music':
                    target.find('audio-channel-source').set('role', 'music.music-2')
                elif case == 'multicam-role':
                    target.find('audio-role-source').set('active', '0')
                else:
                    target.findall('asset-clip')[1].set('enabled', '0')
                plans = self.assert_unchanged(root, target, add_color)
                self.assertEqual(plans['dialogue']['segments'], [])
                self.assertEqual(plans['dialogue']['sampleCount'], 64000)
                if case in ('channel', 'music'):
                    self.assertEqual(len(plans['all']['segments']), 1)

    def test_unknown_video_like_settings_are_still_refused(self):
        for kind in CONTAINERS:
            with self.subTest(container=kind):
                root, target = container_case(kind)
                add_color(target)
                insert_visual(target, E.Element('adjust-unverifiedVideo'))
                with self.assertRaisesRegex(ValueError, '未知|暂不支持'):
                    self.pipeline(root)

    def test_unknown_volume_parameter_is_refused_next_to_color_conform(self):
        for kind in ('asset-clip', 'clip', 'sync-clip', 'ref-clip', 'mc-audio-source'):
            with self.subTest(container=kind):
                root, target = container_case(kind)
                add_color(target)
                volume = next(root.iter('adjust-volume'))
                parameter = E.SubElement(volume, 'param', name='Volume', value='-6')
                E.SubElement(E.SubElement(parameter, 'keyframeAnimation'), 'keyframe', time='0s', value='-6')
                with self.assertRaisesRegex(ValueError, '音量参数'):
                    self.pipeline(root)

    def test_unsupported_audio_retimes_keep_the_existing_skip_rule(self):
        for interpolation, begin, end, reason in (
                ('smooth2', '2s', '6s', '平滑变速'),
                ('linear', '6s', '2s', '倒放'),
                ('linear', '2s', '2s', '停帧')):
            with self.subTest(reason=reason):
                root, target = container_case('asset-clip')
                mapping = E.Element('timeMap', preservesPitch='1')
                E.SubElement(mapping, 'timept', time='2s', value=begin, interp=interpolation)
                E.SubElement(mapping, 'timept', time='6s', value=end, interp=interpolation)
                target.insert(0, mapping)
                plans = self.assert_unchanged(root, target, add_color)
                self.assertEqual(plans['dialogue']['segments'], [])
                self.assertEqual(plans['dialogue']['skippedAudio'], [{
                    'offset': '0', 'duration': '4', 'startSample': 0, 'endSample': 64000, 'reason': reason}])

    def test_invalid_time_map_and_unverified_rate_conform_are_still_refused(self):
        for case in ('unknown-interpolation', 'unsupported-frame-rate', 'container-retime'):
            with self.subTest(case=case):
                root, target = container_case('clip' if case == 'container-retime' else 'asset-clip')
                add_color(target)
                if case == 'unsupported-frame-rate':
                    target.insert(0, E.Element('conform-rate', srcFrameRate='24'))
                    message = '速度缩放帧率适配'
                else:
                    mapping = E.Element('timeMap')
                    interpolation = 'unverified' if case == 'unknown-interpolation' else 'linear'
                    E.SubElement(mapping, 'timept', time='2s', value='2s', interp=interpolation)
                    E.SubElement(mapping, 'timept', time='6s', value='6s', interp=interpolation)
                    target.insert(0, mapping)
                    message = '未知变速插值|容器音频变速'
                with self.assertRaisesRegex(ValueError, message):
                    self.pipeline(root)

    @unittest.skipUnless(DTD.is_file() and shutil.which('xmllint'), 'Official FCPXML 1.14 DTD and xmllint required')
    def test_visual_regressions_use_official_dtd_valid_settings_and_positions(self):
        documents = []
        for kind in CONTAINERS:
            for attrs in COLOR_VARIANTS:
                root, target = container_case(kind)
                add_color(target, attrs)
                documents.append((kind, 'adjust-colorConform', attrs, root))
        for kind in ('asset-clip', 'mc-audio-source'):
            for tag, attrs in VIDEO_SETTINGS:
                root, target = container_case(kind)
                add_setting(root, target, tag, attrs)
                documents.append((kind, tag, attrs, root))
        with tempfile.TemporaryDirectory() as temp:
            xml = Path(temp) / 'visual-settings.fcpxml'
            for kind, tag, attrs, root in documents:
                with self.subTest(container=kind, setting=tag, attrs=attrs):
                    xml.write_bytes(E.tostring(root))
                    result = subprocess.run(['xmllint', '--noout', '--dtdvalid', str(DTD), str(xml)],
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
