import copy
import json
import unittest

import numpy as np

from probes.asr_diagnostics import RecognitionDiagnostics


class RecognitionDiagnosticsTests(unittest.TestCase):
    sample_rate = 1000

    def collector(self, **kwargs):
        return RecognitionDiagnostics(sample_rate=self.sample_rate, **kwargs)

    def signal(self, seconds, level=.1):
        return np.full(round(seconds * self.sample_rate), level, dtype=np.float32)

    def test_empty_signal_warns_without_claiming_speech_or_exposing_content(self):
        collector = self.collector()
        collector.record(0, 5000, self.signal(5), [])
        report = collector.report()
        self.assertEqual(report['warnings'][0]['reason'], 'signal-without-text')
        self.assertIn('音乐', report['warnings'][0]['message'])
        self.assertIn('音频能量不等于人声', report['limitation'])
        self.assertEqual(report['chunks'][0]['activeSeconds'], 5)
        self.assertEqual(report['chunks'][0]['textCharacters'], 0)
        self.assertAlmostEqual(report['chunks'][0]['rms'], .1, places=7)
        json.dumps(report, allow_nan=False)

    def test_silence_quiet_noise_short_signal_and_impulse_do_not_warn(self):
        for samples in (self.signal(5, 0), self.signal(5, .001), self.signal(1),
                        np.concatenate([self.signal(.001, 1), self.signal(4.999, 0)])):
            with self.subTest(length=len(samples), peak=max(samples)):
                collector = self.collector()
                collector.record(0, len(samples), samples, [])
                self.assertFalse(collector.report()['warnings'])

    def test_existing_text_suppresses_empty_hint_and_diagnostics_leave_rows_unchanged(self):
        rows = [dict(text='这是真实字幕，不能修改。', words=[
            dict(text='真实字幕', start=22, end=24),
            dict(text='不能修改', start=23, end=26)])]
        original = copy.deepcopy(rows)
        collector = self.collector()
        collector.record(20000, 25000, self.signal(5), rows)
        report = collector.report()
        self.assertEqual(rows, original)
        self.assertFalse(report['warnings'])
        self.assertEqual(report['chunks'][0]['alignedSeconds'], 3)
        self.assertEqual(report['chunks'][0]['start'], 20)
        serialized = json.dumps(report, ensure_ascii=False)
        self.assertNotIn('真实字幕', serialized)
        self.assertNotIn('digest', serialized)
        self.assertNotIn('sha', serialized)

    def test_repeated_phrase_is_only_a_review_hint_with_original_preserved(self):
        rows = [dict(text='今天我们一起看风景。' * 8, words=[])]
        original = copy.deepcopy(rows)
        collector = self.collector()
        collector.record(0, 20000, self.signal(20), rows)
        warnings = collector.report()['warnings']
        self.assertEqual(len(warnings), 1)
        self.assertEqual(warnings[0]['reason'], 'repetitive-text')
        self.assertEqual(warnings[0]['pattern'], 'within-chunk')
        self.assertIn('原结果已保留', warnings[0]['message'])
        self.assertEqual(rows, original)

    def test_a_few_intentional_repetitions_are_not_flagged(self):
        collector = self.collector()
        collector.record(0, 5000, self.signal(5), [dict(text='加油加油加油，欢迎大家。', words=[])])
        self.assertFalse(collector.report()['warnings'])

    def test_identical_three_chunks_warn_once_extend_range_and_reset_after_silence(self):
        collector = self.collector()
        rows = [dict(text='我们下次再见面。', words=[])]
        for index in range(4):
            collector.record(index * 5000, (index + 1) * 5000, self.signal(5), rows)
        warnings = collector.report()['warnings']
        self.assertEqual(len(warnings), 1)
        self.assertEqual(warnings[0]['pattern'], 'consecutive-chunks')
        self.assertEqual((warnings[0]['start'], warnings[0]['end']), (0, 20))
        collector.record(20000, 25000, self.signal(5, 0), [])
        collector.record(25000, 30000, self.signal(5), rows)
        self.assertEqual(len(collector.report()['warnings']), 1)

    def test_short_common_chunk_text_does_not_trigger_repeat_hint(self):
        collector = self.collector()
        for index in range(5):
            collector.record(index * 5000, (index + 1) * 5000,
                             self.signal(5), [dict(text='谢谢', words=[])])
        self.assertFalse(collector.report()['warnings'])

    def test_report_is_bounded_and_snapshot_cannot_mutate_collector(self):
        collector = self.collector(max_chunks=2, max_warnings=2)
        for index in range(5):
            collector.record(index * 5000, (index + 1) * 5000, self.signal(5), [])
        report = collector.report()
        self.assertEqual(report['chunkCount'], 5)
        self.assertEqual(report['warningCount'], 5)
        self.assertEqual(report['omittedChunks'], 3)
        self.assertEqual(report['omittedWarnings'], 3)
        self.assertEqual(len(report['chunks']), 2)
        self.assertEqual(len(report['warnings']), 2)
        report['chunks'][0]['start'] = -1
        report['warnings'][0]['end'] = -1
        self.assertEqual(collector.report()['chunks'][0]['start'], 0)
        self.assertEqual(collector.report()['warnings'][0]['end'], 5)

    def test_incomplete_prefix_is_not_used_for_repetition_diagnosis(self):
        collector = self.collector()
        rows = [dict(text='重复文本' * 3000, words=[])]
        for index in range(3):
            collector.record(index * 5000, (index + 1) * 5000, self.signal(5), rows)
        self.assertFalse(collector.report()['warnings'])
        self.assertEqual(collector.report()['chunks'][0]['textCharacters'], 12000)

    def test_invalid_alignment_not_counted_as_covered_or_hidden(self):
        collector = self.collector()
        rows = [dict(text='文字', words=[dict(start=float('nan'), end=1), dict(start=2, end=1)])]
        collector.record(0, 5000, self.signal(5), rows)
        chunk = collector.report()['chunks'][0]
        self.assertEqual(chunk['alignedSeconds'], 0)
        self.assertEqual(chunk['invalidWordTimes'], 2)
        json.dumps(collector.report(), allow_nan=False)

    def test_pcm_shape_finiteness_and_contiguous_intervals_are_checked(self):
        collector = self.collector()
        for start, end, samples in [(0, 0, np.array([])), (0, 2, np.zeros(1)),
                                    (0, 2, np.array([0, np.nan])), (0, 2, np.zeros((2, 1))),
                                    (True, 2, np.zeros(1))]:
            with self.subTest(start=start, end=end):
                with self.assertRaises(ValueError):
                    collector.record(start, end, samples, [])
        collector.record(0, 5000, self.signal(5), [])
        with self.assertRaises(ValueError):
            collector.record(4999, 9999, self.signal(5), [])
        with self.assertRaises(ValueError):
            collector.record(5001, 10001, self.signal(5), [])


if __name__ == '__main__':
    unittest.main()
