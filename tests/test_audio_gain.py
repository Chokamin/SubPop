"""Volume automation planning and PCM checks using synthetic constant media.

These regressions verify supported linear envelopes and clock composition;
they do not replace a comparison with Final Cut Pro's exported audio.
"""
from array import array
from fractions import Fraction
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import wave
import xml.etree.ElementTree as ET

from probes import audio_gain, project
from probes.snapshot import prepare


ROOT = Path(__file__).resolve().parents[1]
PYTHON = ROOT / '.venv/bin/python3.12'
BINARY = ROOT / '.subloom/build/SubPopAudioProbeCLI'
RATE = 16000
UID = 'AUDIO-GAIN-TEST'


def fixture(duration='8s', channels=1):
    root = ET.Element('fcpxml', version='1.14')
    resources = ET.SubElement(root, 'resources')
    ET.SubElement(resources, 'format', id='p25', frameDuration='1/25s',
                  width='640', height='360', colorSpace='1-1-1 (Rec. 709)')
    for ref in ('camera', 'external'):
        asset = ET.SubElement(resources, 'asset', id=ref, start='0s', duration='128s',
                              hasAudio='1', audioChannels=str(channels), audioSources='1',
                              audioRate=str(RATE), hasVideo='1', format='p25', videoSources='1')
        ET.SubElement(asset, 'media-rep', kind='original-media', src=f'file:///TEST_MEDIA/{ref}.wav')
    item = ET.SubElement(root, 'project', name='Volume automation regression', uid=UID)
    sequence = ET.SubElement(item, 'sequence', format='p25', duration=duration,
                             tcStart='3600s', audioLayout='stereo', audioRate='48k')
    spine = ET.SubElement(sequence, 'spine')
    clip = ET.SubElement(spine, 'asset-clip', ref='camera', offset='3600s',
                        start='0s', duration=duration, audioRole='dialogue')
    return root, sequence, clip


def volume(owner, amount='0dB', incoming=None, outgoing=None, keys=()):
    node = ET.SubElement(owner, 'adjust-volume', amount=amount)
    if incoming is None and outgoing is None and not keys:
        return node
    param = ET.SubElement(node, 'param', name='amount')
    for tag, duration in (('fadeIn', incoming), ('fadeOut', outgoing)):
        if duration is not None:
            ET.SubElement(param, tag, duration=duration, type='linear')
    if keys:
        animation = ET.SubElement(param, 'keyframeAnimation')
        for time, db in keys:
            ET.SubElement(animation, 'keyframe', time=time, value=db,
                          interp='linear', curve='linear')
    return node


def mapping(node, points):
    time_map = ET.SubElement(node, 'timeMap', preservesPitch='0')
    for output, source in points:
        ET.SubElement(time_map, 'timept', time=f'{output}s', value=f'{source}s', interp='linear')
    return time_map


def wrap(root, sequence, clip, duration=None, media_id='compound'):
    """Move a clip into a resource whose inner sequence starts at zero."""
    duration = duration or clip.get('duration')
    spine = sequence.find('spine')
    spine.remove(clip)
    media = ET.SubElement(root.find('resources'), 'media', id=media_id)
    inner = ET.SubElement(media, 'sequence', format='p25', duration=duration, tcStart='0s')
    ET.SubElement(inner, 'spine').append(clip)
    clip.set('offset', '0s')
    ref = ET.SubElement(spine, 'ref-clip', ref=media_id, offset=sequence.get('tcStart', '0s'),
                        start='0s', duration=duration)
    return inner, ref


def runtime(code, payload):
    # The discovery runner need not contain numpy. Use the project's existing
    # Python for envelope evaluation and the actual native render path.
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', PYTHONPATH=str(ROOT))
    result = subprocess.run([str(PYTHON), '-B', '-c', code], input=json.dumps(payload),
                            capture_output=True, text=True, check=True, timeout=180,
                            cwd=str(ROOT), env=environment)
    return json.loads(result.stdout)


class AudioGainTests(unittest.TestCase):
    def plan(self, root, mode='dialogue', prepared=True):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / 'direct.fcpxml'
            source.write_bytes(ET.tostring(root))
            result = project.inspect(source, mode)
            if prepared:
                normalized, titles = prepare(source.read_bytes(), generic=True)
                self.assertEqual(titles, [])
                source.write_bytes(normalized)
                self.assertEqual(project.inspect(source, mode), result)
            return result

    def values(self, segment, times):
        return runtime(
            'import json,sys\n'
            'from probes.audio_gain import evaluate_envelopes\n'
            'p=json.load(sys.stdin)\n'
            'print(json.dumps([float(evaluate_envelopes(p["envelopes"],s,1,16000)[0])*p["gain"] '
            'for s in p["samples"]]))\n',
            dict(envelopes=segment.get('gainEnvelopes', []), gain=segment['gain'],
                 samples=[int(Fraction(time) * RATE) for time in times]))

    def test_static_gain_keeps_float_and_no_automation_fields(self):
        root, _, clip = fixture()
        volume(clip, '-6dB')
        segment = self.plan(root)['segments'][0]
        self.assertIsInstance(segment['gain'], float)
        self.assertAlmostEqual(segment['gain'], 10 ** (-6 / 20))
        self.assertNotIn('gainEnvelopes', segment)

    def test_linear_fades_have_known_half_amplitude_and_original_sample_clock(self):
        root, _, clip = fixture()
        volume(clip, incoming='4s', outgoing='4s')
        plan = self.plan(root)
        self.assertEqual(plan['sampleCount'], 8 * RATE)
        self.assertEqual(self.values(plan['segments'][0], [0, 2, 4, 6]), [0.0, 0.5, 1.0, 0.5])
        self.assertEqual(plan['bypassedAudioEffects'], 0)

    def test_four_fcp_fade_curves_match_fixed_edge_progress_samples_in_both_directions(self):
        # Fixed reference values from the isolated FCP 12.3 WAV fit recorded
        # in .subloom/verification/audio-fade150/analysis-r2-curves.json.
        # Entries correspond to remaining/incoming progress 0,.25,.5,.75,1;
        # deliberately do not call the production easing function as oracle.
        references = {
            'linear': [0.0, 0.25, 0.5, 0.75, 1.0],
            'easeIn': [0.0, 0.382683432365, 0.707106781187, 0.923879532511, 1.0],
            'easeOut': [0.0, 0.076120467489, 0.292893218813, 0.617316567635, 1.0],
            'easeInOut': [0.0, 0.146446609407, 0.5, 0.853553390593, 1.0],
        }
        times = [0, Fraction(1, 2), 1, Fraction(3, 2), 2, 4,
                 6, Fraction(13, 2), 7, Fraction(15, 2), 8]
        for kind, reference in references.items():
            with self.subTest(kind=kind):
                root, _, clip = fixture()
                adjustment = volume(clip, incoming='2s', outgoing='2s')
                for fade in adjustment.find('param'):
                    fade.set('type', kind)
                segment = self.plan(root)['segments'][0]
                actual = self.values(segment, times)
                # Fade-out evaluates this same curve at remaining progress;
                # easeOut(.25) is .07612, not 1-easeOut(.75)=.38268.
                expected = reference + [1.0] + list(reversed(reference))
                for time, value, golden in zip(times, actual, expected):
                    with self.subTest(time=time):
                        self.assertAlmostEqual(value, golden, places=10)

    def test_nonzero_source_start_normalizes_keyframes_without_resetting_them(self):
        root, _, clip = fixture()
        clip.set('start', '10s')
        volume(clip, keys=[('10s', '-12'), ('14s', '0')])
        segment = self.plan(root)['segments'][0]
        self.assertEqual(segment['source_start'], '10')
        self.assertEqual([key['time'] for key in segment['gainEnvelopes'][0]['keyframes']], ['0', '4'])
        # Actual FCP output interpolates the two endpoint amplitudes rather
        # than interpolating their displayed dB values.
        self.assertAlmostEqual(self.values(segment, [2])[0], (10 ** (-12 / 20) + 1) / 2)

    def test_verified_double_speed_keys_use_adjusted_output_clock_and_absolute_volume(self):
        values = []
        for amount in (None, '-6dB'):
            with self.subTest(amount=amount):
                root, sequence, clip = fixture('6s')
                clip.set('start', '1s')
                mapping(clip, [(0, 0), (8, 16)])
                adjustment = volume(clip, amount or '0dB',
                                    keys=[('1s', '-6'), ('3s', '0'), ('5s', '-6'), ('7s', '0')])
                if amount is None:
                    # FCP's roundtrip removes adjust-volume.amount when these
                    # absolute keyframe values replace the initial -6 dB.
                    adjustment.attrib.pop('amount')
                    for key in adjustment.findall('param/keyframeAnimation/keyframe'):
                        key.attrib.pop('interp')
                        key.attrib.pop('curve')
                segment = self.plan(root)['segments'][0]
                self.assertEqual((segment['source_start'], segment['source_duration']), ('2', '12'))
                self.assertEqual([key['time'] for key in segment['gainEnvelopes'][0]['keyframes']],
                                 ['0', '2', '4', '6'])
                samples = self.values(segment, [0, 1, 2, 4, 5])
                expected = [10 ** (-6 / 20), (10 ** (-6 / 20) + 1) / 2,
                            1.0, 10 ** (-6 / 20), (10 ** (-6 / 20) + 1) / 2]
                for actual, reference in zip(samples, expected):
                    self.assertAlmostEqual(actual, reference)
                values.append(samples)
        for original, canonical in zip(*values):
            self.assertAlmostEqual(original, canonical)

    def test_trimmed_compound_keeps_inner_fade_age_and_nonzero_media_timecode(self):
        for media_tc in (0, 10):
            with self.subTest(media_tc=media_tc):
                root, sequence, clip = fixture()
                volume(clip, incoming='8s')
                inner, ref = wrap(root, sequence, clip)
                inner.set('tcStart', f'{media_tc}s')
                clip.set('offset', f'{media_tc}s')
                ref.set('start', f'{media_tc + 2}s')
                ref.set('duration', '4s')
                sequence.set('duration', '4s')
                segment = self.plan(root)['segments'][0]
                self.assertEqual((segment['offset'], segment['source_start'], segment['duration']), ('0', '2', '4'))
                self.assertEqual(self.values(segment, [0, 2]), [0.25, 0.5])

    def test_parent_and_independent_connected_clip_do_not_share_envelopes(self):
        root, _, clip = fixture()
        volume(clip, incoming='8s')
        child = ET.SubElement(clip, 'asset-clip', ref='external', lane='-1',
                              offset='2s', start='3s', duration='6s', audioRole='dialogue')
        segments = self.plan(root)['segments']
        self.assertEqual(len(segments), 2)
        self.assertEqual(self.values(segments[0], [4]), [0.5])
        self.assertNotIn('gainEnvelopes', segments[1])
        self.assertEqual((segments[1]['offset'], segments[1]['duration'], segments[1]['gain']), ('2', '6', 1.0))
        volume(child, incoming='4s')
        segments = self.plan(root)['segments']
        self.assertEqual(len(segments[1]['gainEnvelopes']), 1)
        self.assertEqual(self.values(segments[1], [2, 4, 6]), [0.0, 0.5, 1.0])

    def test_inaudible_parent_skips_invalid_automation_but_keeps_connection(self):
        for reason in ('disabled', 'video', 'music', 'component'):
            with self.subTest(reason=reason):
                root, _, clip = fixture()
                bad = ET.SubElement(clip, 'adjust-volume', amount='0dB')
                ET.SubElement(bad, 'param', name='unknown-volume-parameter')
                ET.SubElement(clip, 'asset-clip', ref='external', lane='-1', offset='2s',
                              start='0s', duration='6s', audioRole='VO')
                if reason == 'disabled':
                    clip.set('enabled', '0')
                elif reason == 'video':
                    clip.set('srcEnable', 'video')
                elif reason == 'music':
                    clip.set('audioRole', 'music')
                else:
                    ET.SubElement(clip, 'audio-channel-source', srcCh='1', role='dialogue', enabled='0')
                segments = self.plan(root)['segments']
                self.assertEqual([segment['assetRef'] for segment in segments], ['external'])
                self.assertNotIn('gainEnvelopes', segments[0])

    def test_excluded_and_disabled_component_fades_are_not_parsed(self):
        root, _, clip = fixture(channels=4)
        ET.SubElement(clip, 'audio-channel-source', srcCh='1', role='dialogue')
        for channel, attrs in (('2', dict(role='music')), ('3', dict(role='dialogue', active='0')),
                               ('4', dict(role='dialogue', enabled='0'))):
            component = ET.SubElement(clip, 'audio-channel-source', srcCh=channel, **attrs)
            bad = ET.SubElement(component, 'adjust-volume', amount='0dB')
            ET.SubElement(bad, 'param', name='unknown')
        plan = self.plan(root)
        self.assertEqual(plan['segments'][0]['channelMix']['components'], [{'channels': [1], 'gain': 1.0}])
        with self.assertRaises(ValueError):
            self.plan(root, 'all')

    def test_separate_component_envelopes_are_not_serialized_as_native_gains(self):
        root, _, clip = fixture(channels=4)
        first = ET.SubElement(clip, 'audio-channel-source', srcCh='1,2', role='dialogue')
        second = ET.SubElement(clip, 'audio-channel-source', srcCh='3,4', role='dialogue')
        volume(first, incoming='8s')
        volume(second, outgoing='8s')
        segments = self.plan(root)['segments']
        self.assertEqual(len(segments), 2)
        self.assertEqual([segment['channelMix']['components'] for segment in segments],
                         [[{'channels': [1, 2], 'gain': 1.0}], [{'channels': [3, 4], 'gain': 1.0}]])
        self.assertEqual(self.values(segments[0], [0, 4]), [0.0, 0.5])
        self.assertEqual(self.values(segments[1], [0, 4]), [1.0, 0.5])
        # Plans must remain JSON, including all independently decoded groups.
        json.dumps(segments, allow_nan=False)

    def test_container_channel_divisor_is_preserved_when_dynamic_groups_split(self):
        root, sequence, clip = fixture(channels=2)
        spine = sequence.find('spine')
        spine.remove(clip)
        wrapper = ET.SubElement(spine, 'clip', offset='3600s', start='0s', duration='8s')
        component = ET.SubElement(wrapper, 'audio-channel-source', srcCh='1,2', role='dialogue')
        volume(component, incoming='8s')
        gap = ET.SubElement(wrapper, 'gap', offset='0s', start='0s', duration='8s')
        ET.SubElement(gap, 'audio', ref='camera', lane='-1', offset='0s', start='0s', duration='8s', srcCh='1')
        segment = self.plan(root)['segments'][0]
        self.assertEqual(segment['channelMix']['components'], [{'channels': [1], 'gain': 1.0}])
        self.assertEqual(segment['gain'], 0.5)
        self.assertEqual(self.values(segment, [4]), [0.25])

    def test_sync_role_gain_uses_sync_owner_clock_and_is_applied_once(self):
        root, sequence, clip = fixture()
        spine = sequence.find('spine')
        spine.remove(clip)
        sync = ET.SubElement(spine, 'sync-clip', offset='3600s', start='0s', duration='8s')
        clip.set('offset', '0s')
        sync.append(clip)
        source = ET.SubElement(sync, 'sync-source', sourceID='storyline')
        role = ET.SubElement(source, 'audio-role-source', role='dialogue')
        volume(role, incoming='8s')
        volume(clip, '-6dB')
        segment = self.plan(root)['segments'][0]
        self.assertEqual(len(segment['gainEnvelopes']), 1)
        self.assertAlmostEqual(self.values(segment, [4])[0], 0.5 * 10 ** (-6 / 20))

    def test_compound_role_fade_uses_outer_edit_clock_after_source_trim(self):
        root, sequence, clip = fixture()
        _, ref = wrap(root, sequence, clip)
        sequence.set('duration', '4s')
        ref.set('start', '2s')
        ref.set('duration', '4s')
        role = ET.SubElement(ref, 'audio-role-source', role='dialogue')
        volume(role, incoming='4s')
        segment = self.plan(root)['segments'][0]
        self.assertEqual(segment['source_start'], '2')
        self.assertEqual(len(segment['gainEnvelopes']), 1)
        self.assertEqual(self.values(segment, [0, 2]), [0.0, 0.5])

    def test_verified_plain_conform_connection_retains_its_independent_fade_clock(self):
        root = ET.parse(ROOT / 'tests/fixtures/fcp-12.3-conformed-connected-audio.fcpxml').getroot()
        parent = root.find('project/sequence/spine/clip')
        child = parent.find('asset-clip')
        volume(parent, incoming='4s')
        volume(child, incoming='4s')
        plan = self.plan(root)
        primary = next(segment for segment in plan['segments']
                       if segment['assetRef'] == 'r3' and segment['offset'] == '2')
        connection = next(segment for segment in plan['segments'] if segment['assetRef'] == 'r5')
        self.assertEqual(connection['duration'], '6')
        self.assertNotIn('source_duration', connection)
        self.assertEqual(len(connection['gainEnvelopes']), 1)
        self.assertEqual(len(primary['gainEnvelopes']), 1)
        self.assertEqual(self.values(primary, [4]), [0.5])
        connection_middle = Fraction(connection['offset']) + 2
        self.assertAlmostEqual(self.values(connection, [connection_middle])[0], 0.5, places=4)

    def test_compound_outer_and_inner_fades_have_distinct_retimed_clocks(self):
        root, sequence, clip = fixture('16s')
        volume(clip, incoming='16s')
        _, ref = wrap(root, sequence, clip)
        ref.set('duration', '8s')
        sequence.set('duration', '8s')
        mapping(ref, [(0, 0), (8, 16)])
        volume(ref, incoming='8s')
        segment = self.plan(root)['segments'][0]
        self.assertEqual((segment['source_start'], segment['source_duration'], segment['duration']), ('0', '16', '8'))
        self.assertEqual(len(segment['gainEnvelopes']), 2)
        self.assertTrue(all(envelope['clock'] == 0 for envelope in segment['gainEnvelopes']))
        self.assertEqual(self.values(segment, [4]), [0.25])

    def test_multisegment_retime_does_not_reset_inner_fade_at_rate_boundary(self):
        root, sequence, clip = fixture('12s')
        volume(clip, incoming='8s')
        _, ref = wrap(root, sequence, clip)
        ref.set('duration', '8s')
        sequence.set('duration', '8s')
        mapping(ref, [(0, 0), (4, 4), (8, 12)])
        segments = self.plan(root)['segments']
        self.assertEqual([(segment['offset'], segment['source_start'], segment['source_duration']) for segment in segments],
                         [('0', '0', '4'), ('4', '4', '8')])
        self.assertEqual(self.values(segments[0], [2]), [0.25])
        self.assertEqual(self.values(segments[1], [4, 6]), [0.5, 1.0])

    def test_jl_audio_edges_and_project_trim_keep_fade_clock_without_duplicate_child(self):
        root, _, clip = fixture()
        clip.set('start', '4s')
        clip.set('audioStart', '2s')
        clip.set('audioDuration', '12s')
        volume(clip, incoming='8s')
        ET.SubElement(clip, 'asset-clip', ref='external', lane='-1', offset='7s',
                      start='10s', duration='4s', audioRole='dialogue')
        segments = self.plan(root)['segments']
        primary = [segment for segment in segments if segment['assetRef'] == 'camera']
        child = [segment for segment in segments if segment['assetRef'] == 'external']
        self.assertEqual((len(primary), len(child)), (1, 1))
        self.assertEqual((primary[0]['offset'], primary[0]['source_start'], primary[0]['duration']), ('0', '4', '8'))
        self.assertEqual(len(primary[0]['gainEnvelopes']), 1)
        self.assertEqual(self.values(primary[0], [0, 2, 6]), [0.25, 0.5, 1.0])
        self.assertEqual((child[0]['offset'], child[0]['duration']), ('3', '4'))
        self.assertNotIn('gainEnvelopes', child[0])

    def test_jl_and_time_map_guard_remains_explicit(self):
        root, _, clip = fixture()
        clip.set('audioDuration', '4s')
        volume(clip, incoming='2s')
        mapping(clip, [(0, 0), (8, 16)])
        with self.assertRaisesRegex(ValueError, '分离音频起止与变速'):
            self.plan(root)

    def test_scalar_and_schema_validation_do_not_accept_unknown_automation(self):
        context = dict(clock=0, origin=0, start=0, length=8)
        examples = [
            '<adjust-volume amount="NaNdB"/>',
            '<adjust-volume amount="13dB"/>',
            '<adjust-volume amount="-97dB"/>',
            '<adjust-volume amount="0dB" unknown="1"/>',
            '<adjust-volume><fadeIn duration="1s"/></adjust-volume>',
            '<adjust-volume><param name="unknown"/></adjust-volume>',
            '<adjust-volume><param name="amount" value="-6"/></adjust-volume>',
            '<adjust-volume><param name="amount"><param name="amount"/></param></adjust-volume>',
            '<adjust-volume><param name="amount"><fadeIn duration="1s"/><fadeIn duration="2s"/></param></adjust-volume>',
            '<adjust-volume><param name="amount"><fadeOut duration="1s"/><fadeIn duration="2s"/></param></adjust-volume>',
            '<adjust-volume><param name="amount"><fadeIn duration="1s" type="unknown"/></param></adjust-volume>',
            '<adjust-volume><param name="amount"><fadeIn duration="-1s"/></param></adjust-volume>',
            '<adjust-volume><param name="amount"><fadeIn duration="NaNs"/></param></adjust-volume>',
            '<adjust-volume><param name="amount"><fadeIn duration="1/0s"/></param></adjust-volume>',
            '<adjust-volume><param name="amount"><fadeIn duration="1s"><param name="amount"/></fadeIn></param></adjust-volume>',
            '<adjust-volume><param name="amount"><keyframeAnimation unknown="1"/></param></adjust-volume>',
            '<adjust-volume><param name="amount"><keyframeAnimation><keyframe time="1s" value="0"/><keyframe time="1s" value="0"/></keyframeAnimation></param></adjust-volume>',
            '<adjust-volume><param name="amount"><keyframeAnimation><keyframe time="2s" value="0"/><keyframe time="1s" value="0"/></keyframeAnimation></param></adjust-volume>',
            '<adjust-volume><param name="amount"><keyframeAnimation><keyframe time="0s" value="0" interp="unknown"/></keyframeAnimation></param></adjust-volume>',
            '<adjust-volume><param name="amount"><keyframeAnimation><keyframe time="0s" value="0" curve="unknown"/></keyframeAnimation></param></adjust-volume>',
            '<adjust-volume><param name="amount"><keyframeAnimation><keyframe time="0s" value="0" auxValue="1"/></keyframeAnimation></param></adjust-volume>',
        ]
        for text in examples:
            with self.subTest(xml=text):
                with self.assertRaises(ValueError):
                    audio_gain.volume_gain(ET.fromstring(text), context)

    def test_fade_defaults_and_zero_duration_are_valid_schema(self):
        context = dict(clock=0, origin=0, start=0, length=8)
        parsed = audio_gain.volume_gain(ET.fromstring(
            '<adjust-volume><param name="amount"><fadeIn duration="4s"/><fadeOut duration="4s"/></param></adjust-volume>'), context)
        _, envelopes = audio_gain.materialize_gain(parsed)
        self.assertEqual(envelopes[0]['fadeIn']['type'], 'easeIn')
        self.assertEqual(envelopes[0]['fadeOut']['type'], 'easeOut')
        self.assertEqual(envelopes[0]['length'], '8')
        for value in ('0s', '0/3s'):
            node = ET.fromstring(f'<adjust-volume amount="-6dB"><param name="amount"><fadeIn duration="{value}"/></param></adjust-volume>')
            self.assertAlmostEqual(audio_gain.volume_gain(node, context), 10 ** (-6 / 20))

    def test_unverified_fade_longer_than_owner_or_overlapping_edges_are_refused(self):
        context = dict(clock=0, origin=0, start=0, length=4)
        for children in ('<fadeIn duration="5s"/>', '<fadeOut duration="5s"/>',
                         '<fadeIn duration="3s"/><fadeOut duration="2s"/>'):
            with self.subTest(children=children):
                node = ET.fromstring(f'<adjust-volume><param name="amount">{children}</param></adjust-volume>')
                with self.assertRaises(ValueError):
                    audio_gain.volume_gain(node, context)
        # A containing edit can show less than the fade's full duration. The
        # source owner's full range, rather than its visible bounds, controls
        # validity; the existing trimmed-compound test checks its PCM gain age.
        node = ET.fromstring('<adjust-volume><param name="amount"><fadeIn duration="4s"/></param></adjust-volume>')
        self.assertEqual(len(audio_gain.curves(audio_gain.volume_gain(node, context))), 1)

    def test_automation_requires_valid_owner_and_unmapped_clock_cannot_escape_plan(self):
        node = ET.fromstring('<adjust-volume><param name="amount"><fadeIn duration="2s" type="linear"/></param></adjust-volume>')
        for context in (None, {}, dict(clock=0, origin=0, start=0, length=0),
                        dict(clock=True, origin=0, start=0, length=4),
                        dict(clock=0, origin='NaN', start=0, length=4)):
            with self.subTest(context=context):
                with self.assertRaises(ValueError):
                    audio_gain.volume_gain(node, context)
        gain = audio_gain.volume_gain(node, dict(clock=1, origin=2, start=0, length=4))
        with self.assertRaisesRegex(ValueError, '项目时钟'):
            audio_gain.materialize_gain(gain)
        remapped = audio_gain.remap_gain(gain, 1, 0, 2, 4, 2)
        static, envelopes = audio_gain.materialize_gain(remapped)
        self.assertEqual(static, 1.0)
        self.assertEqual(self.values(dict(gain=static, gainEnvelopes=envelopes), [4, Fraction(9, 2), 5]), [0.0, 0.5, 1.0])
        for speed in (0, -1):
            with self.assertRaises(ValueError):
                audio_gain.remap_gain(gain, 1, 0, 2, 4, speed)

    def test_curve_and_keyframe_budgets_are_enforced(self):
        envelope = audio_gain.Envelope(0, 1, 0, 8, 0, audio_gain.Fade(8, 'linear'))
        gain = audio_gain.Gain(1, (envelope,) * audio_gain.MAX_CURVES)
        with self.assertRaises(ValueError):
            _ = gain * audio_gain.Gain(1, (envelope,))
        keys = tuple(audio_gain.Keyframe(Fraction(index), 0) for index in range(audio_gain.MAX_KEYS + 1))
        with self.assertRaises(ValueError):
            audio_gain.Envelope(0, 1, 0, 8, 0, keyframes=keys)

    def split_gain_fixture(self, dynamic=True):
        root, _, clip = fixture()
        mapping(clip, [(0, 0), (4, 4), (8, 8)])
        if dynamic:
            volume(clip, incoming='8s', keys=[('0s', '0'), ('8s', '0')])
        return root

    def test_plan_curve_budget_is_checked_before_excess_materialization(self):
        root = self.split_gain_fixture()
        with patch.object(project, 'MAX_PLAN_GAIN_CURVES', 1), \
                patch.object(project, 'MAX_PLAN_GAIN_KEYS', 4), \
                patch.object(project, 'materialize_gain', wraps=audio_gain.materialize_gain) as materialize:
            with self.assertRaises(ValueError):
                self.plan(root, prepared=False)
            # The first segment uses exactly one curve; the second must be
            # rejected without allocating its duplicated keyframe dictionaries.
            self.assertEqual(materialize.call_count, 1)
        with patch.object(project, 'MAX_PLAN_GAIN_CURVES', 2), \
                patch.object(project, 'MAX_PLAN_GAIN_KEYS', 4):
            self.assertEqual(len(self.plan(root, prepared=False)['segments']), 2)

    def test_plan_key_budget_counts_keys_repeated_by_retime_segments_before_allocating(self):
        root = self.split_gain_fixture()
        with patch.object(project, 'MAX_PLAN_GAIN_CURVES', 2), \
                patch.object(project, 'MAX_PLAN_GAIN_KEYS', 3), \
                patch.object(project, 'materialize_gain', wraps=audio_gain.materialize_gain) as materialize:
            with self.assertRaises(ValueError):
                self.plan(root, prepared=False)
            self.assertEqual(materialize.call_count, 1)
        with patch.object(project, 'MAX_PLAN_GAIN_CURVES', 2), \
                patch.object(project, 'MAX_PLAN_GAIN_KEYS', 4):
            segments = self.plan(root, prepared=False)['segments']
            self.assertEqual(sum(len(envelope['keyframes']) for segment in segments
                                 for envelope in segment['gainEnvelopes']), 4)

    def test_zero_automation_plan_budgets_do_not_reject_static_segments(self):
        root = self.split_gain_fixture(dynamic=False)
        with patch.object(project, 'MAX_PLAN_GAIN_CURVES', 0), \
                patch.object(project, 'MAX_PLAN_GAIN_KEYS', 0), \
                patch.object(project, 'materialize_gain', wraps=audio_gain.materialize_gain) as materialize:
            segments = self.plan(root, prepared=False)['segments']
            self.assertEqual(len(segments), 2)
            self.assertEqual(materialize.call_count, 2)
            self.assertTrue(all('gainEnvelopes' not in segment for segment in segments))

    def test_whole_and_chunked_evaluation_use_absolute_sample_clock(self):
        root, _, clip = fixture('61s')
        volume(clip, incoming='60s')
        segment = self.plan(root)['segments'][0]
        result = runtime(
            'import json,sys,numpy as np\n'
            'from probes.audio_gain import evaluate_envelopes\n'
            'p=json.load(sys.stdin);n=61*16000;e=p["envelopes"]\n'
            'whole=evaluate_envelopes(e,0,n,16000)\n'
            'parts=np.concatenate([evaluate_envelopes(e,s,min(30*16000,n-s),16000) '
            'for s in range(0,n,30*16000)])\n'
            'print(json.dumps(dict(equal=bool(np.array_equal(whole,parts)), '
            'points=[float(whole[s]) for s in (0,30*16000,60*16000)])))\n',
            dict(envelopes=segment['gainEnvelopes']))
        self.assertTrue(result['equal'])
        self.assertEqual(result['points'], [0.0, 0.5, 1.0])

    def write_media(self, directory, channels, values, seconds=64):
        path = directory / 'constant.wav'
        with wave.open(str(path), 'wb') as output:
            output.setparams((channels, 2, RATE, 0, 'NONE', 'not compressed'))
            output.writeframes(array('h', values).tobytes() * (RATE * seconds))
        return path

    def native_render(self, root, directory, media):
        for node in root.findall('resources/asset/media-rep'):
            node.set('src', media.as_uri())
        xml = directory / 'input.fcpxml'
        xml.write_bytes(ET.tostring(root))
        report = runtime(
            'import json,sys\nfrom pathlib import Path\nfrom probes import project\n'
            'p=json.load(sys.stdin)\n'
            'print(json.dumps(project.render(Path(p["xml"]),Path(p["directory"]),Path(p["binary"]),p["uid"])))\n',
            dict(xml=str(xml), directory=str(directory), binary=str(BINARY), uid=UID))
        pcm = array('f')
        pcm.frombytes((directory / report['pcmFile']).read_bytes())
        return report, pcm

    def test_native_render_linear_fade_crosses_thirty_second_decode_boundary(self):
        root, _, clip = fixture('61s')
        volume(clip, incoming='60s')
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            media = self.write_media(directory, 1, [8192])
            report, pcm = self.native_render(root, directory, media)
            self.assertEqual((report['sampleCount'], len(pcm)), (61 * RATE, 61 * RATE))
            self.assertEqual(pcm[0], 0.0)
            self.assertAlmostEqual(pcm[30 * RATE], 0.125, places=6)
            self.assertAlmostEqual(pcm[60 * RATE], 0.25, places=6)
            self.assertLess(pcm[30 * RATE - 1], pcm[30 * RATE])
            self.assertLess(pcm[30 * RATE], pcm[30 * RATE + 1])
            self.assertFalse(report['silent'])

    def test_native_render_component_fades_preserve_each_stereo_group_mean(self):
        root, _, clip = fixture(channels=4)
        first = ET.SubElement(clip, 'audio-channel-source', srcCh='1,2', role='dialogue')
        second = ET.SubElement(clip, 'audio-channel-source', srcCh='3,4', role='dialogue')
        volume(first, incoming='8s')
        volume(second, outgoing='8s')
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            media = self.write_media(directory, 4, [8192, 8192, 16384, 16384])
            report, pcm = self.native_render(root, directory, media)
            self.assertEqual(report['sampleCount'], 8 * RATE)
            self.assertEqual(len(report['plan']['segments']), 2)
            self.assertAlmostEqual(pcm[0], 0.5, places=6)
            self.assertAlmostEqual(pcm[4 * RATE], 0.375, places=6)
            self.assertAlmostEqual(pcm[-1], 0.25, places=5)


if __name__ == '__main__':
    unittest.main()
