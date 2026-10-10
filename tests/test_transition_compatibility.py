"""Short edge transitions and silent title storylines retain the audio edit.

These fixtures describe synthetic XML only. They do not stand in for FCP
rendered crossfades, host acceptance, or speech recognition verification.
"""
from copy import deepcopy
from fractions import Fraction
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

from probes.project import inspect
from probes.snapshot import bypassed_audio_transitions, collision, prepare


def time(value):
    return str(Fraction(value)) + 's'


def fixture(tc=Fraction(3600), frame=Fraction(1, 25), duration=8):
    root = ET.Element('fcpxml', version='1.14')
    resources = ET.SubElement(root, 'resources')
    ET.SubElement(resources, 'format', id='format', frameDuration=time(frame),
                  width='1920', height='1080')
    asset = ET.SubElement(resources, 'asset', id='source', start='0s',
                          duration='30s', hasVideo='1', format='format',
                          hasAudio='1', audioSources='1', audioChannels='1',
                          audioRate='48000')
    ET.SubElement(asset, 'media-rep', kind='original-media',
                  src='file:///SYNTHETIC_TEST_MEDIA/source.mov')
    for identifier, uid in (('crossfade', 'FFAudioTransition'),
                            ('visual', 'synthetic.visual.transition'),
                            ('title', 'synthetic.silent.title')):
        ET.SubElement(resources, 'effect', id=identifier, uid=uid)
    project = ET.SubElement(root, 'project', name='Transition compatibility',
                            uid='TRANSITION-COMPATIBILITY')
    sequence = ET.SubElement(project, 'sequence', format='format',
                             duration=time(duration), tcStart=time(tc))
    spine = ET.SubElement(sequence, 'spine')
    clip = ET.SubElement(spine, 'asset-clip', ref='source', offset=time(tc),
                         start='2s', duration=time(duration), audioRole='dialogue')
    ET.SubElement(clip, 'adjust-volume', amount='-6dB')
    return root, sequence, spine, clip


def transition(offset, duration=Fraction(1, 2), audio=True):
    node = ET.Element('transition', name='Synthetic transition',
                      offset=time(offset), duration=time(duration))
    ET.SubElement(node, 'filter-video', ref='visual')
    if audio:
        ET.SubElement(node, 'filter-audio', ref='crossfade')
    return node


def silent_title_spine(clip):
    nested = ET.SubElement(clip, 'spine', lane='1', offset='3s')
    nested.append(transition(0, audio=False))
    title = ET.SubElement(nested, 'title', ref='title', offset='0s',
                          start='0s', duration='4s')
    ET.SubElement(title, 'text').text = 'Synthetic heading'
    nested.append(transition(Fraction(7, 2), audio=False))
    return nested, title


class TransitionCompatibilityTests(unittest.TestCase):
    def plan(self, root, mode='all'):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'synthetic.fcpxml'
            path.write_bytes(ET.tostring(root))
            return inspect(path, mode)

    def prepared(self, root):
        raw, existing = prepare(ET.tostring(root), generic=True)
        return ET.fromstring(raw), existing

    def assert_refused(self, root):
        # Unknown nested structures may be preserved by snapshot.prepare and
        # then rejected by the authoritative audio-plan validation.
        with self.assertRaises(ValueError):
            normalized, _ = self.prepared(root)
            self.plan(normalized)

    def test_leading_and_trailing_crossfades_leave_audio_plan_unchanged(self):
        for leading, trailing in ((True, False), (False, True), (True, True)):
            with self.subTest(leading=leading, trailing=trailing):
                root, _, spine, _ = fixture()
                baseline = self.plan(root)
                if leading:
                    spine.insert(0, transition(3600))
                if trailing:
                    spine.append(transition(Fraction(7215, 2)))
                original = ET.tostring(root)
                normalized, existing = self.prepared(root)
                self.assertEqual(self.plan(normalized), baseline)
                self.assertEqual(existing, [])
                self.assertFalse(normalized.findall('.//transition'))
                self.assertEqual(ET.tostring(root), original)
                expected = []
                if leading:
                    expected.append({'offset': '0', 'duration': '1/2'})
                if trailing:
                    expected.append({'offset': '15/2', 'duration': '1/2'})
                self.assertEqual(bypassed_audio_transitions(original), expected)

    def test_fractional_5994_project_clock_keeps_exact_sources_and_samples(self):
        frame = Fraction(1001, 60000)
        tc = Fraction(216000001, 60000)
        length = 360 * frame
        fade = 30 * frame
        root, _, spine, _ = fixture(tc, frame, length)
        baseline = self.plan(root)
        spine.insert(0, transition(tc, fade))
        spine.append(transition(tc + length - fade, fade))
        original = ET.tostring(root)
        normalized, _ = self.prepared(root)
        self.assertEqual(self.plan(normalized), baseline)
        self.assertEqual(bypassed_audio_transitions(original), [
            {'offset': '0', 'duration': str(fade)},
            {'offset': str(length - fade), 'duration': str(fade)},
        ])

    def test_terminal_transition_does_not_clip_independent_audio_past_main_end(self):
        root, sequence, spine, clip = fixture()
        sequence.set('duration', '10s')
        narration = ET.SubElement(clip, 'asset-clip', ref='source', lane='-1',
                                   offset='6s', start='10s', duration='6s',
                                   audioRole='dialogue.voiceover')
        ET.SubElement(narration, 'adjust-volume', amount='-3dB')
        baseline = self.plan(root)
        self.assertEqual(baseline['segments'][1]['offset'], '4')
        self.assertEqual(baseline['segments'][1]['duration'], '6')
        spine.append(transition(Fraction(7215, 2)))
        normalized, _ = self.prepared(root)
        self.assertEqual(self.plan(normalized), baseline)
        self.assertEqual(self.plan(normalized)['sampleCount'], 160000)

    def test_interior_crossfade_retains_existing_hard_cut_behavior(self):
        root, _, spine, clip = fixture()
        clip.set('duration', '4s')
        second = deepcopy(clip)
        second.set('offset', '3604s')
        second.set('start', '6s')
        spine.append(second)
        baseline = self.plan(root)
        spine.insert(1, transition(Fraction(14415, 4)))
        normalized, _ = self.prepared(root)
        self.assertEqual(self.plan(normalized), baseline)

    def test_edge_geometry_rejects_orphan_misaligned_and_out_of_clip_ranges(self):
        cases = (
            ('leading-not-at-start', True, Fraction(3601, 1), Fraction(1, 2), 8),
            ('leading-before-start', True, Fraction(7199, 2), Fraction(1, 2), 8),
            ('leading-past-clip', True, Fraction(3600), Fraction(1), Fraction(1, 2)),
            ('trailing-not-at-end', False, Fraction(3607), Fraction(1, 2), 8),
            ('trailing-past-end', False, Fraction(3608), Fraction(1, 2), 8),
            ('trailing-before-clip', False, Fraction(7199, 2), Fraction(1), Fraction(1, 2)),
            ('long', False, Fraction(3605), Fraction(3), 8),
            ('zero', False, Fraction(3608), Fraction(0), 8),
            ('negative', False, Fraction(7217, 2), Fraction(-1, 2), 8),
        )
        for name, leading, offset, length, clip_length in cases:
            with self.subTest(name=name):
                root, _, spine, clip = fixture(duration=clip_length)
                node = transition(offset, length)
                spine.insert(0, node) if leading else spine.append(node)
                self.assert_refused(root)
        root, _, spine, clip = fixture()
        spine.remove(clip)
        spine.append(transition(3600))
        self.assert_refused(root)

    def test_adjacent_transition_chain_cannot_become_valid_by_removal_order(self):
        for leading in (False, True):
            with self.subTest(leading=leading):
                root, _, spine, _ = fixture()
                if leading:
                    spine.insert(0, transition(3600))
                    spine.insert(0, transition(3600))
                else:
                    spine.append(transition(Fraction(7215, 2)))
                    spine.append(transition(Fraction(7215, 2)))
                self.assert_refused(root)

    def test_edge_missing_timing_and_unknown_transition_attributes_are_refused(self):
        for target, attribute in (('transition', 'offset'), ('transition', 'duration'),
                                  ('clip', 'offset'), ('clip', 'duration')):
            with self.subTest(target=target, attribute=attribute):
                root, _, spine, clip = fixture()
                node = transition(Fraction(7215, 2))
                spine.append(node)
                del (node if target == 'transition' else clip).attrib[attribute]
                self.assert_refused(root)
        root, _, spine, _ = fixture()
        node = transition(Fraction(7215, 2))
        node.set('audioStart', '0s')
        spine.append(node)
        self.assert_refused(root)

    def test_edge_unknown_audio_filters_and_hidden_audio_are_refused(self):
        for variant in ('missing-ref', 'nonstandard-effect', 'extra-filter',
                        'filter-attribute', 'filter-child', 'visual-audio', 'unknown-child'):
            with self.subTest(variant=variant):
                root, _, spine, _ = fixture()
                node = transition(Fraction(7215, 2))
                spine.append(node)
                audio = node.find('filter-audio')
                if variant == 'missing-ref':
                    audio.set('ref', 'missing')
                elif variant == 'nonstandard-effect':
                    audio.set('ref', 'visual')
                elif variant == 'extra-filter':
                    ET.SubElement(node, 'filter-audio', ref='crossfade')
                elif variant == 'filter-attribute':
                    audio.set('unknown', '1')
                elif variant == 'filter-child':
                    ET.SubElement(audio, 'param', value='0')
                elif variant == 'visual-audio':
                    ET.SubElement(node.find('filter-video'), 'audio', ref='source')
                else:
                    ET.SubElement(node, 'unknown')
                self.assert_refused(root)

    def test_silent_title_transitions_keep_gap_collision_and_connected_audio(self):
        root, _, _, clip = fixture()
        nested, title = silent_title_spine(clip)
        narration = ET.SubElement(clip, 'asset-clip', ref='source', lane='-1',
                                   offset='4s', start='10s', duration='3s',
                                   audioRole='dialogue.voiceover')
        ET.SubElement(narration, 'adjust-volume', amount='-3dB')
        original = ET.tostring(root)
        baseline_root = deepcopy(root)
        baseline_root.find('.//asset-clip').remove(baseline_root.find('.//asset-clip/spine'))
        baseline = self.plan(baseline_root)
        normalized, existing = self.prepared(root)
        self.assertFalse(normalized.findall('.//title'))
        self.assertFalse(normalized.findall('.//transition'))
        normalized_spine = normalized.find('.//asset-clip/spine')
        self.assertIsNotNone(normalized_spine)
        self.assertEqual(normalized_spine.attrib, nested.attrib)
        self.assertEqual([n.tag for n in normalized_spine], ['gap'])
        self.assertEqual(normalized_spine[0].attrib,
                         {'offset': '0s', 'start': '0s', 'duration': '4s'})
        self.assertEqual(self.plan(normalized), baseline)
        self.assertEqual(existing, [{'text': 'Synthetic heading', 'start_frame': 25,
                                     'end_frame': 125, 'enabled': True, 'exactTiming': True}])
        self.assertEqual(collision(existing, existing)['status'], 'duplicate')
        self.assertEqual(ET.tostring(root), original)
        self.assertEqual(bypassed_audio_transitions(original), [])

    def test_title_storyline_past_main_end_still_sets_project_extent(self):
        root, sequence, _, clip = fixture()
        sequence.set('duration', '10s')
        nested, title = silent_title_spine(clip)
        nested.set('offset', '8s')
        normalized, existing = self.prepared(root)
        plan = self.plan(normalized)
        self.assertEqual(plan['sampleCount'], 160000)
        self.assertEqual(len(plan['segments']), 1)
        self.assertEqual(plan['segments'][0]['duration'], '8')
        self.assertEqual((existing[0]['start_frame'], existing[0]['end_frame']), (150, 250))

    def test_silent_title_storyline_does_not_discard_audio_or_unknown_media(self):
        for variant in ('title-audio', 'title-audio-filter', 'transition-audio',
                        'hidden-visual-audio', 'spine-audio', 'spine-unknown',
                        'missing-visual-ref', 'visual-media-ref'):
            with self.subTest(variant=variant):
                root, _, _, clip = fixture()
                nested, title = silent_title_spine(clip)
                if variant == 'title-audio':
                    ET.SubElement(title, 'asset-clip', ref='source', offset='0s', duration='1s')
                elif variant == 'title-audio-filter':
                    ET.SubElement(title, 'filter-audio', ref='crossfade')
                elif variant == 'transition-audio':
                    ET.SubElement(nested[0], 'filter-audio', ref='crossfade')
                elif variant == 'hidden-visual-audio':
                    ET.SubElement(nested[0].find('filter-video'), 'audio', ref='source')
                elif variant == 'spine-audio':
                    ET.SubElement(nested, 'asset-clip', ref='source', offset='4s',
                                  start='10s', duration='1s', audioRole='dialogue')
                elif variant == 'spine-unknown':
                    ET.SubElement(nested, 'unknown', offset='4s', duration='1s')
                elif variant == 'missing-visual-ref':
                    nested[0].find('filter-video').set('ref', 'missing')
                else:
                    nested[0].find('filter-video').set('ref', 'source')
                self.assert_refused(root)

    def test_silent_title_storyline_requires_valid_timing_and_transition_geometry(self):
        for variant in ('misaligned-leading', 'misaligned-trailing', 'too-long',
                        'missing-duration', 'adjacent-transitions', 'unknown-attribute'):
            with self.subTest(variant=variant):
                root, _, _, clip = fixture()
                nested, _ = silent_title_spine(clip)
                if variant == 'misaligned-leading':
                    nested[0].set('offset', '1s')
                elif variant == 'misaligned-trailing':
                    nested[-1].set('offset', '3s')
                elif variant == 'too-long':
                    nested[0].set('duration', '3s')
                elif variant == 'missing-duration':
                    del nested[0].attrib['duration']
                elif variant == 'adjacent-transitions':
                    nested.insert(0, transition(0, audio=False))
                else:
                    nested[0].set('unknown', '1')
                self.assert_refused(root)

    def test_unrelated_gap_storyline_is_not_assumed_to_be_stripped_titles(self):
        root, _, _, clip = fixture()
        nested = ET.SubElement(clip, 'spine', lane='1', offset='3s')
        nested.append(transition(0, audio=False))
        ET.SubElement(nested, 'gap', offset='0s', start='0s', duration='4s')
        nested.append(transition(Fraction(7, 2), audio=False))
        self.assert_refused(root)


if __name__ == '__main__':
    unittest.main()
