"""Independent dialogue survives a rate-conformed plain clip's source window.

The fixture's primary gap/audio shape and nonzero start are an isolated FCP
12.3 chirp export. Its WAV placed the connected six-second 1x source at
121001/30030; the zero-start control placed it at 4002/1001. These tests check
the planner and prepared snapshot, not ASR accuracy or a user project.
"""
from fractions import Fraction
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as E

from probes.project import inspect
from probes.snapshot import collision, prepare


FIXTURE = Path(__file__).parent / 'fixtures/fcp-12.3-conformed-connected-audio.fcpxml'
START2_OFFSET = Fraction(121001, 30030)
START0_OFFSET = Fraction(4002, 1001)


def fixture(start_zero=False):
    root = E.parse(FIXTURE).getroot()
    sequence = root.find('project/sequence')
    parent = sequence.find('spine/clip')
    child = parent.find('asset-clip')
    if start_zero:
        parent.attrib.pop('start')
        child.set('offset', '2s')
        sequence.find('spine').remove(sequence.findall('spine/clip')[1])
        sequence.set('duration', '12s')
    return root, sequence, parent, child


class ConformedConnectedAudioTests(unittest.TestCase):
    def plan(self, root, mode='dialogue', check_snapshot=False):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'input.fcpxml'
            path.write_bytes(E.tostring(root))
            result = inspect(path, mode)
            if check_snapshot:
                normalized, existing = prepare(path.read_bytes(), generic=True)
                self.assertEqual(existing, [])
                path.write_bytes(normalized)
                self.assertEqual(inspect(path, mode), result)
            return result

    def external(self, plan):
        matches = [segment for segment in plan['segments'] if segment['assetRef'] == 'r5']
        self.assertEqual(len(matches), 1)
        return matches[0]

    def assert_connection(self, plan, offset=START2_OFFSET):
        segment = self.external(plan)
        self.assertEqual((Fraction(segment['offset']), Fraction(segment['source_start']),
                          Fraction(segment['duration'])), (offset, Fraction(1), Fraction(6)))
        self.assertEqual(segment['sampleCount'], 96000)
        self.assertLessEqual(abs(Fraction(segment['startSample'], 16000) - offset), Fraction(1, 16000))
        self.assertNotIn('source_duration', segment)
        self.assertNotIn('preservesPitch', segment)
        self.assertEqual(plan['skippedAudio'], [])
        return segment

    def test_real_nonzero_start_roundtrip_keeps_entire_connection(self):
        root, _, _, _ = fixture()
        plan = self.plan(root, check_snapshot=True)
        self.assert_connection(plan)
        primary = next(segment for segment in plan['segments']
                       if segment['assetRef'] == 'r3' and segment['offset'] == '2')
        self.assertEqual((primary['source_start'], primary['duration'], primary['source_duration']),
                         ('59059/30000', '4', '1001/250'))
        self.assertFalse(primary['preservesPitch'])

    def test_zero_start_retains_verified_connection_clock(self):
        root, _, _, _ = fixture(start_zero=True)
        self.assert_connection(self.plan(root, check_snapshot=True), START0_OFFSET)

    def test_direct_audio_connection_keeps_its_own_source_and_duration(self):
        root, _, _, child = fixture()
        child.tag = 'audio'
        child.set('role', child.attrib.pop('audioRole'))
        child.set('srcCh', '1')
        self.assert_connection(self.plan(root))

    def test_connection_format_does_not_change_primary_conform_mapping(self):
        for format_id in (None, 'r2', 'r1'):
            with self.subTest(format=format_id):
                root, _, _, child = fixture()
                if format_id is not None:
                    child.set('format', format_id)
                    root.find("resources/asset[@id='r5']").set('format', format_id)
                self.assert_connection(self.plan(root))

    def test_connection_own_conform_uses_outer_project_frame_clock(self):
        root, _, _, child = fixture()
        root.find("resources/asset[@id='r5']").set('format', 'r2')
        child.set('format', 'r2')
        child.insert(0, E.Element('conform-rate', srcFrameRate='29.97'))
        segment = self.external(self.plan(root, check_snapshot=True))
        self.assertEqual((Fraction(segment['offset']), segment['source_start'], segment['duration']),
                         (START2_OFFSET, '1', '6'))
        # A conformed child is in the 30fps project, not the camera source's
        # 29.97fps internal clock, so six output seconds consume 6.006 source.
        self.assertEqual(segment['source_duration'], '3003/500')
        self.assertFalse(segment['preservesPitch'])

    def test_connection_only_trims_at_project_end(self):
        root, sequence, _, child = fixture()
        sequence.set('duration', '9s')
        sequence.find('spine').remove(sequence.findall('spine/clip')[1])
        sequence.find("spine/gap[@name='Tail']").set('duration', '3s')
        before = E.tostring(root)
        plan = self.plan(root, check_snapshot=True)
        segment = self.external(plan)
        self.assertEqual(E.tostring(root), before)
        self.assertEqual(child.get('duration'), '6s')
        self.assertEqual((Fraction(segment['offset']), segment['source_start'], Fraction(segment['duration'])),
                         (START2_OFFSET, '1', Fraction(149269, 30030)))
        self.assertEqual(segment['startSample'] + segment['sampleCount'], plan['sampleCount'])
        self.assertNotIn('source_duration', segment)
        self.assertEqual(plan['sampleCount'], 144000)
        self.assertEqual(plan['skippedAudio'], [])

    def test_parent_gain_mute_and_channel_selection_do_not_affect_connection(self):
        for control in ('gain', 'disabled', 'primary-muted', 'component-disabled'):
            with self.subTest(parent_control=control):
                root, _, parent, _ = fixture()
                parent.insert(1, E.Element('adjust-volume', amount='-12dB'))
                if control == 'disabled':
                    parent.set('enabled', '0')
                elif control == 'primary-muted':
                    parent.find('spine/gap/audio').set('enabled', '0')
                else:
                    component = E.SubElement(parent, 'audio-channel-source', srcCh='1', role='dialogue')
                    if control == 'component-disabled':
                        component.set('enabled', '0')
                    else:
                        E.SubElement(component, 'adjust-volume', amount='-6dB')
                plan = self.plan(root)
                segment = self.assert_connection(plan)
                self.assertEqual(segment['gain'], 1)
                self.assertNotIn('channelMix', segment)
                if control == 'gain':
                    primary = next(segment for segment in plan['segments']
                                   if segment['assetRef'] == 'r3' and segment['offset'] == '2')
                    effective_gain = primary['gain'] * primary['channelMix']['components'][0]['gain']
                    self.assertAlmostEqual(effective_gain, 10 ** (-18 / 20))

    def test_muted_conform_and_time_map_preserves_existing_output_connection_clock(self):
        # The conform-only verified clock must not be imposed on an existing
        # timeMap output offset when the unsupported combination is silent.
        root, _, parent, _ = fixture()
        parent.set('enabled', '0')
        time_map = E.Element('timeMap', preservesPitch='0')
        E.SubElement(time_map, 'timept', time='0s', value='0s', interp='linear')
        E.SubElement(time_map, 'timept', time='12s', value='24s', interp='linear')
        parent.insert(1, time_map)
        segment = self.assert_connection(self.plan(root, check_snapshot=True), Fraction(120941, 30000))
        self.assertEqual(segment['gain'], 1)

    def test_connection_uses_own_component_gain_and_mute(self):
        root, _, _, child = fixture()
        component = E.SubElement(child, 'audio-channel-source', srcCh='1', role='dialogue')
        E.SubElement(component, 'adjust-volume', amount='-6dB')
        segment = self.assert_connection(self.plan(root))
        self.assertEqual(segment['channelMix']['components'][0]['channels'], [1])
        self.assertAlmostEqual(segment['channelMix']['components'][0]['gain'], 10 ** (-6 / 20))
        component.set('active', '0')
        self.assertFalse(any(segment['assetRef'] == 'r5' for segment in self.plan(root)['segments']))

    def test_connection_role_filter_is_independent_of_primary(self):
        root, _, _, child = fixture()
        child.set('audioRole', 'music')
        self.assertFalse(any(segment['assetRef'] == 'r5' for segment in self.plan(root)['segments']))
        self.assert_connection(self.plan(root, 'all'))

    def test_nested_primary_spine_retains_conformed_gap_audio(self):
        root, _, parent, _ = fixture()
        primary_spine = parent.find('spine')
        parent.remove(primary_spine)
        nested = E.Element('clip', offset='0s', duration='12s', format='r2')
        nested.append(primary_spine)
        parent.insert(1, nested)
        plan = self.plan(root)
        self.assert_connection(plan)
        primary = next(segment for segment in plan['segments']
                       if segment['assetRef'] == 'r3' and segment['offset'] == '2')
        self.assertEqual(primary['source_duration'], '1001/250')

    def test_connected_spine_is_not_part_of_primary_audio_layout(self):
        root, _, parent, child = fixture()
        parent.remove(child)
        connected_spine = E.SubElement(parent, 'spine', lane='-1', offset='4s', format='r1')
        child.set('lane', '0')
        child.set('offset', '0s')
        connected_spine.append(child)
        E.SubElement(parent, 'audio-channel-source', srcCh='1', role='dialogue', enabled='0')
        self.assert_connection(self.plan(root))

    def test_lane_zero_sync_wrapper_is_still_primary_source_layout(self):
        root, _, parent, _ = fixture()
        primary_spine = parent.find('spine')
        parent.remove(primary_spine)
        sync = E.Element('sync-clip', offset='0s', duration='12s', format='r2')
        sync.append(primary_spine)
        parent.insert(1, sync)
        plan = self.plan(root, check_snapshot=True)
        self.assert_connection(plan)
        primary = next(segment for segment in plan['segments']
                       if segment['assetRef'] == 'r3' and segment['offset'] == '2')
        self.assertEqual((primary['source_start'], primary['source_duration']),
                         ('59059/30000', '1001/250'))

    def test_constructed_connected_title_collision_keeps_entire_verified_clock(self):
        # Title placement is a constructed snapshot regression using the
        # verified audio anchor clock, not an FCP title export in this round.
        for start_zero, expected_frames in ((False, (120, 301)), (True, (119, 300))):
            with self.subTest(start_zero=start_zero):
                root, _, parent, child = fixture(start_zero=start_zero)
                E.SubElement(root.find('resources'), 'effect', id='t', uid='TEST-SILENT-TITLE')
                title = E.SubElement(parent, 'title', ref='t', lane='1',
                                     offset=child.get('offset'), duration='6s')
                E.SubElement(title, 'text').text = 'Constructed title clock'
                before = E.tostring(root)
                normalized, existing = prepare(before, generic=True)
                self.assertEqual(E.tostring(root), before)
                self.assertEqual(E.fromstring(normalized).findall('.//title'), [])
                self.assertEqual(existing, [{'text': 'Constructed title clock',
                                            'start_frame': expected_frames[0],
                                            'end_frame': expected_frames[1],
                                            'enabled': True, 'exactTiming': False}])
                # The anchor ends at frame180; its title still occupies these
                # later frames, and must retain the ordinary collision warning.
                result = collision([{'text': 'New caption', 'start_frame': 230, 'end_frame': 260}], existing)
                self.assertEqual((result['status'], result['overlappingRows']), ('conflict', 1))
                self.assert_connection(self.plan(E.fromstring(normalized)),
                                       START0_OFFSET if start_zero else START2_OFFSET)
