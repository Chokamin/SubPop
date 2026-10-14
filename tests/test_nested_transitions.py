"""Synthetic nested-transition regressions at the snapshot/audio-plan boundary.

These tests compare source clocks and direct-audio plans. They do not assert
that omitted transition effects match FCP rendering or replace host testing.
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


def fixture(tc=3600, frame=Fraction(1, 25)):
    root = ET.Element('fcpxml', version='1.14')
    resources = ET.SubElement(root, 'resources')
    ET.SubElement(resources, 'format', id='format', frameDuration=time(frame),
                  width='1920', height='1080')
    asset = ET.SubElement(resources, 'asset', id='source', start='0s',
                          duration='60s', hasVideo='1', hasAudio='1',
                          format='format', audioSources='1', audioChannels='2',
                          audioRate='48000')
    ET.SubElement(asset, 'media-rep', kind='original-media',
                  src='file:///SYNTHETIC_TEST_MEDIA/source.mov')
    for identifier, uid in (('visual', 'FFCrossDissolve'),
                            ('crossfade', 'FFAudioTransition'),
                            ('unknown-audio', 'synthetic.unknown.audio'),
                            ('title', 'synthetic.silent.title')):
        ET.SubElement(resources, 'effect', id=identifier, uid=uid)
    project = ET.SubElement(root, 'project', name='Nested transitions',
                            uid='SYNTHETIC-NESTED-TRANSITIONS')
    sequence = ET.SubElement(project, 'sequence', format='format',
                             duration='12s', tcStart=time(tc))
    main = ET.SubElement(sequence, 'spine')
    anchor = ET.SubElement(main, 'asset-clip', ref='source', offset=time(tc),
                           start='10s', duration='12s', audioRole='dialogue')
    ET.SubElement(anchor, 'adjust-volume', amount='-6dB')
    return root, sequence, main, anchor


def add_transition(story, offset, duration=Fraction(2, 5), audio=False,
                   index=1):
    node = ET.Element('transition', offset=time(offset), duration=time(duration))
    ET.SubElement(node, 'filter-video', ref='visual')
    if audio:
        ET.SubElement(node, 'filter-audio', ref='crossfade')
    story.insert(index, node)
    return node


def connected_story(anchor, source_enable='video', origin=13):
    # Main clip starts at source time 10, so origin 13 is output time 3.
    story = ET.SubElement(anchor, 'spine', lane='1', offset=time(origin))
    for offset, source_start in ((0, 20), (4, 30)):
        clip = ET.SubElement(story, 'asset-clip', ref='source',
                              offset=time(offset), start=time(source_start),
                              duration='4s', srcEnable=source_enable,
                              audioRole='dialogue.voiceover')
        ET.SubElement(clip, 'adjust-volume', amount='-3dB')
    return story


def compound_story(root, main, anchor, inner_tc=100, trim=0):
    resources = root.find('resources')
    media = ET.SubElement(resources, 'media', id='compound')
    sequence = ET.SubElement(media, 'sequence', format='format',
                             duration='12s', tcStart=time(inner_tc))
    story = ET.SubElement(sequence, 'spine')
    for offset, source_start in ((inner_tc, 20), (inner_tc + 6, 30)):
        clip = ET.SubElement(story, 'asset-clip', ref='source',
                              offset=time(offset), start=time(source_start),
                              duration='6s', audioRole='dialogue')
        ET.SubElement(clip, 'adjust-volume', amount='-3dB')
    main.remove(anchor)
    ref = ET.SubElement(main, 'ref-clip', ref='compound',
                         offset=anchor.get('offset'), start=time(inner_tc + trim),
                         duration=time(12 - trim))
    if trim:
        tc = Fraction(anchor.get('offset')[:-1])
        ET.SubElement(main, 'gap', offset=time(tc + 12 - trim),
                      start='0s', duration=time(trim))
    return story, ref


def multicam_story(root, main, anchor):
    media = ET.SubElement(root.find('resources'), 'media', id='multicam')
    multi = ET.SubElement(media, 'multicam', format='format', tcStart='100s')
    selected = ET.SubElement(multi, 'mc-angle', angleID='selected')
    for offset, source_start in ((100, 20), (106, 30)):
        ET.SubElement(selected, 'asset-clip', ref='source', offset=time(offset),
                      start=time(source_start), duration='6s', audioRole='dialogue')
    unused = deepcopy(selected)
    unused.set('angleID', 'unused')
    multi.append(unused)
    main.remove(anchor)
    clip = ET.SubElement(main, 'mc-clip', ref='multicam', offset=anchor.get('offset'),
                          start='100s', duration='12s')
    ET.SubElement(clip, 'mc-source', angleID='selected', srcEnable='all')
    return selected, unused, clip


class NestedTransitionTests(unittest.TestCase):
    def normalize(self, root):
        raw = ET.tostring(root)
        normalized, existing = prepare(raw, generic=True)
        self.assertEqual(ET.tostring(root), raw)
        return normalized, existing

    def plan(self, data, mode='all'):
        raw = ET.tostring(data) if isinstance(data, ET.Element) else data
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'synthetic.fcpxml'
            path.write_bytes(raw)
            return inspect(path, mode)

    def assert_refused(self, root):
        with self.assertRaises(ValueError):
            normalized, _ = self.normalize(root)
            self.plan(normalized)

    def test_connected_visual_transition_preserves_original_audio(self):
        root, _, _, anchor = fixture()
        original_plan = self.plan(root)
        story = connected_story(anchor)
        # Picture clips contribute no audio but keep their original clocks.
        baseline = self.plan(root)
        add_transition(story, Fraction(19, 5))
        normalized, existing = self.normalize(root)
        self.assertEqual(existing, [])
        self.assertEqual(self.plan(normalized), baseline)
        self.assertEqual(baseline['segments'], original_plan['segments'])
        normalized_story = ET.fromstring(normalized).find('.//asset-clip/spine')
        self.assertEqual(normalized_story.attrib, story.attrib)
        self.assertEqual([clip.attrib for clip in normalized_story],
                         [clip.attrib for clip in story if clip.tag != 'transition'])
        self.assertFalse(ET.fromstring(normalized).findall('.//transition'))

    def test_connected_audio_transitions_keep_offsets_sources_roles_and_gain(self):
        for source_enable in ('all', 'audio'):
            for mode in ('dialogue', 'all'):
                for audio_transition in (False, True):
                    with self.subTest(source_enable=source_enable, mode=mode,
                                      audio_transition=audio_transition):
                        root, _, _, anchor = fixture()
                        story = connected_story(anchor, source_enable)
                        story[1].set('audioRole', 'music')
                        baseline = self.plan(root, mode)
                        add_transition(story, Fraction(19, 5), audio=audio_transition)
                        normalized, _ = self.normalize(root)
                        self.assertEqual(self.plan(normalized, mode), baseline)
                        voiceover = baseline['segments'][1]
                        self.assertEqual((voiceover['offset'], voiceover['source_start'],
                                          voiceover['duration']), ('3', '20', '4'))
                        self.assertEqual(voiceover['startSample'], 48000)

    def test_connected_edge_transitions_preserve_independent_audio_tail(self):
        root, sequence, _, anchor = fixture()
        anchor.set('duration', '6s')
        story = connected_story(anchor, 'audio', origin=14)
        baseline = self.plan(root)
        self.assertEqual(baseline['segments'][-1]['offset'], '8')
        self.assertEqual(baseline['segments'][-1]['duration'], '4')
        self.assertEqual(sequence.get('duration'), '12s')
        add_transition(story, 0, audio=True, index=0)
        add_transition(story, Fraction(38, 5), audio=True, index=len(story))
        normalized, _ = self.normalize(root)
        self.assertEqual(self.plan(normalized), baseline)

    def test_fractional_project_origin_does_not_change_local_story_clocks(self):
        root, _, _, anchor = fixture(tc=Fraction(108000001, 30000),
                                     frame=Fraction(1001, 30000))
        story = connected_story(anchor, 'audio', origin=Fraction(39001, 3000))
        baseline = self.plan(root)
        add_transition(story, Fraction(19, 5), audio=True)
        normalized, _ = self.normalize(root)
        self.assertEqual(self.plan(normalized), baseline)

    def test_compound_nonzero_source_clock_and_trim_preserve_full_plan(self):
        for trim in (0, 2):
            for mode in ('dialogue', 'all'):
                for audio_transition in (False, True):
                    with self.subTest(trim=trim, mode=mode,
                                      audio_transition=audio_transition):
                        root, _, main, anchor = fixture()
                        story, _ = compound_story(root, main, anchor, trim=trim)
                        baseline = self.plan(root, mode)
                        add_transition(story, Fraction(529, 5), audio=audio_transition)
                        normalized, _ = self.normalize(root)
                        self.assertEqual(self.plan(normalized, mode), baseline)
                        self.assertEqual(baseline['segments'][0]['source_start'], str(20 + trim))
                        self.assertEqual(baseline['segments'][1]['offset'], str(6 - trim))

    def test_shared_compound_resource_is_normalized_without_losing_second_use(self):
        root, sequence, main, anchor = fixture()
        sequence.set('duration', '24s')
        story, ref = compound_story(root, main, anchor)
        second = deepcopy(ref)
        second.set('offset', '3612s')
        main.append(second)
        baseline = self.plan(root)
        add_transition(story, Fraction(529, 5), audio=True)
        normalized, _ = self.normalize(root)
        self.assertEqual(self.plan(normalized), baseline)
        self.assertEqual([s['offset'] for s in baseline['segments']], ['0', '6', '12', '18'])

    def test_nested_crossfade_warning_uses_local_clock_not_project_time(self):
        root, _, _, anchor = fixture()
        story = connected_story(anchor, 'audio', origin=14)
        add_transition(story, Fraction(19, 5), audio=True)
        original = ET.tostring(root)
        warnings = []
        normalized, _ = prepare(original, generic=True, bypassed_transitions=warnings)
        expected = [{'scope': 'nested', 'sourceOffset': '19/5', 'sourceDuration': '2/5'}]
        self.assertEqual(warnings, expected)
        self.assertEqual(bypassed_audio_transitions(original), expected)
        self.assertEqual(bypassed_audio_transitions(normalized), [])
        self.assertNotIn('offset', warnings[0])
        self.assertEqual(ET.tostring(root), original)

    def test_compound_warning_preserves_nonzero_local_clock_for_every_reference(self):
        root, sequence, main, anchor = fixture()
        sequence.set('duration', '24s')
        story, ref = compound_story(root, main, anchor)
        second = deepcopy(ref)
        second.set('offset', '3612s')
        main.append(second)
        add_transition(story, Fraction(529, 5), audio=True)
        original = ET.tostring(root)
        warnings = []
        normalized, _ = prepare(original, generic=True, bypassed_transitions=warnings)
        expected = [{'scope': 'nested', 'sourceOffset': '529/5', 'sourceDuration': '2/5'}] * 2
        self.assertEqual(warnings, expected)
        self.assertEqual(bypassed_audio_transitions(original), expected)
        self.assertEqual(len(self.plan(normalized)['segments']), 4)
        self.assertFalse(ET.fromstring(normalized).findall('.//transition'))
        self.assertEqual(ET.tostring(root), original)

    def test_selected_multicam_angle_transition_keeps_selected_source_plan(self):
        for mode in ('dialogue', 'all'):
            with self.subTest(mode=mode):
                root, _, main, anchor = fixture()
                selected, _, _ = multicam_story(root, main, anchor)
                baseline = self.plan(root, mode)
                add_transition(selected, Fraction(529, 5), audio=True)
                original = ET.tostring(root)
                warnings = []
                normalized, _ = prepare(original, generic=True, bypassed_transitions=warnings)
                self.assertEqual(self.plan(normalized, mode), baseline)
                self.assertEqual(warnings, [
                    {'scope': 'nested', 'sourceOffset': '529/5', 'sourceDuration': '2/5'},
                ])
                self.assertFalse(ET.fromstring(normalized).findall('.//transition'))
                self.assertEqual(ET.tostring(root), original)

    def test_unselected_angles_and_unused_media_keep_unknown_transitions_untouched(self):
        for explicitly_disabled in (False, True):
            with self.subTest(explicitly_disabled=explicitly_disabled):
                root, _, main, anchor = fixture()
                _, unused, clip = multicam_story(root, main, anchor)
                if explicitly_disabled:
                    ET.SubElement(clip, 'mc-source', angleID='unused', srcEnable='none')
                node = add_transition(unused, Fraction(529, 5), audio=True)
                node.find('filter-audio').set('ref', 'unknown-audio')
                unused_media = ET.SubElement(root.find('resources'), 'media', id='unused-compound')
                inner = ET.SubElement(unused_media, 'sequence', format='format',
                                      duration='12s', tcStart='100s')
                story = ET.SubElement(inner, 'spine')
                story.extend(deepcopy(list(unused)))
                baseline = self.plan(root)
                original_unused = ET.tostring(unused)
                original_media = ET.tostring(unused_media)
                warnings = []
                normalized, _ = prepare(ET.tostring(root), generic=True,
                                        bypassed_transitions=warnings)
                self.assertEqual(self.plan(normalized), baseline)
                self.assertEqual(warnings, [])
                result = ET.fromstring(normalized)
                self.assertEqual(ET.tostring(result.find(".//mc-angle[@angleID='unused']")),
                                 original_unused)
                self.assertEqual(ET.tostring(result.find("resources/media[@id='unused-compound']")),
                                 original_media)
                # Changing selection makes the same unknown audio relevant.
                clip.find('mc-source').set('angleID', 'unused')
                if explicitly_disabled:
                    clip.remove(clip.findall('mc-source')[1])
                self.assert_refused(root)

    def test_compound_linear_retime_keeps_source_trim_and_output_samples(self):
        root, sequence, main, anchor = fixture()
        story, ref = compound_story(root, main, anchor)
        sequence.set('duration', '6s')
        ref.set('duration', '6s')
        mapping = ET.SubElement(ref, 'timeMap', preservesPitch='1')
        ET.SubElement(mapping, 'timept', time='100s', value='100s', interp='linear')
        ET.SubElement(mapping, 'timept', time='106s', value='112s', interp='linear')
        baseline = self.plan(root)
        self.assertEqual([(s['offset'], s['duration'], s['source_start'], s['source_duration'])
                          for s in baseline['segments']],
                         [('0', '3', '20', '6'), ('3', '3', '30', '6')])
        add_transition(story, Fraction(529, 5), audio=True)
        warnings = []
        normalized, _ = prepare(ET.tostring(root), generic=True,
                                bypassed_transitions=warnings)
        self.assertEqual(self.plan(normalized), baseline)
        self.assertEqual(warnings, [
            {'scope': 'nested', 'sourceOffset': '529/5', 'sourceDuration': '2/5'},
        ])

    def test_compound_reference_cycle_with_transition_still_refused(self):
        root, _, main, anchor = fixture()
        story, _ = compound_story(root, main, anchor)
        story.remove(story[0])
        story.insert(0, ET.Element('ref-clip', ref='compound', offset='100s',
                                   start='100s', duration='6s'))
        add_transition(story, Fraction(529, 5), audio=True)
        original = ET.tostring(root)
        with self.assertRaisesRegex(ValueError, '循环'):
            prepare(original, generic=True)
        self.assertEqual(ET.tostring(root), original)

    def test_nested_titles_are_stripped_without_losing_collision_intervals(self):
        root, _, _, anchor = fixture()
        story = connected_story(anchor, 'audio')
        title = ET.SubElement(story[0], 'title', ref='title', lane='2',
                              offset='21s', start='0s', duration='2s')
        ET.SubElement(title, 'text').text = 'Existing subtitle'
        baseline_raw, baseline_titles = self.normalize(root)
        baseline = self.plan(baseline_raw)
        add_transition(story, Fraction(19, 5))
        normalized, existing = self.normalize(root)
        self.assertEqual(self.plan(normalized), baseline)
        self.assertEqual(existing, baseline_titles)
        self.assertEqual(existing, [{'text': 'Existing subtitle', 'start_frame': 100,
                                     'end_frame': 150, 'enabled': True, 'exactTiming': True}])
        self.assertEqual(collision(existing, existing)['status'], 'duplicate')
        self.assertFalse(ET.fromstring(normalized).findall('.//title'))
        self.assertIsNotNone(root.find('.//title'))

    def test_repeated_source_bytes_and_reprepared_audio_copy_are_stable(self):
        root, _, main, anchor = fixture()
        story, _ = compound_story(root, main, anchor)
        add_transition(story, Fraction(529, 5), audio=True)
        source = ET.tostring(root)
        first, titles = prepare(source, generic=True)
        expected = self.plan(first)
        for _ in range(5):
            normalized, existing = prepare(source, generic=True)
            self.assertEqual(normalized, first)
            self.assertEqual(existing, titles)
            self.assertEqual(self.plan(normalized), expected)
        normalized_again, _ = prepare(first, generic=True)
        self.assertEqual(normalized_again, first)
        self.assertEqual(self.plan(normalized_again), expected)
        self.assertEqual(ET.tostring(root), source)

    def test_nested_transition_geometry_still_refuses_ambiguous_edits(self):
        for container in ('connected', 'compound'):
            for variant in ('discontinuous', 'misaligned', 'too-long', 'zero-length',
                            'negative-length', 'adjacent', 'missing-offset',
                            'missing-duration', 'unknown-attribute'):
                with self.subTest(container=container, variant=variant):
                    root, _, main, anchor = fixture()
                    if container == 'connected':
                        story = connected_story(anchor, 'audio')
                        cut = Fraction(4)
                    else:
                        story, _ = compound_story(root, main, anchor)
                        cut = Fraction(106)
                    node = add_transition(story, cut - Fraction(1, 5), audio=True)
                    if variant == 'discontinuous':
                        story[-1].set('offset', time(cut + 1))
                    elif variant == 'misaligned':
                        node.set('offset', time(cut + 1))
                    elif variant == 'too-long':
                        node.set('duration', '3s')
                    elif variant == 'zero-length':
                        node.set('duration', '0s')
                    elif variant == 'negative-length':
                        node.set('duration', '-1s')
                    elif variant == 'adjacent':
                        story.insert(1, deepcopy(node))
                    elif variant == 'missing-offset':
                        del node.attrib['offset']
                    elif variant == 'missing-duration':
                        del node.attrib['duration']
                    else:
                        node.set('audioStart', '0s')
                    self.assert_refused(root)

    def test_nested_unknown_or_hidden_audio_is_never_silently_removed(self):
        for container in ('connected', 'compound'):
            for variant in ('unknown-audio', 'missing-audio-ref', 'extra-audio-filter',
                            'audio-filter-parameter', 'visual-with-audio', 'unknown-child'):
                with self.subTest(container=container, variant=variant):
                    root, _, main, anchor = fixture()
                    if container == 'connected':
                        story = connected_story(anchor, 'video')
                        cut = Fraction(4)
                    else:
                        story, _ = compound_story(root, main, anchor)
                        cut = Fraction(106)
                    node = add_transition(story, cut - Fraction(1, 5), audio=True)
                    audio = node.find('filter-audio')
                    if variant == 'unknown-audio':
                        audio.set('ref', 'unknown-audio')
                    elif variant == 'missing-audio-ref':
                        audio.set('ref', 'missing')
                    elif variant == 'extra-audio-filter':
                        ET.SubElement(node, 'filter-audio', ref='crossfade')
                    elif variant == 'audio-filter-parameter':
                        ET.SubElement(audio, 'param', name='Unknown', value='1')
                    elif variant == 'visual-with-audio':
                        ET.SubElement(node.find('filter-video'), 'audio', ref='source')
                    else:
                        ET.SubElement(node, 'unknown')
                    self.assert_refused(root)


if __name__ == '__main__':
    unittest.main()
