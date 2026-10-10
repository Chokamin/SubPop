import builtins
import contextlib
import hashlib
import io
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import numpy as np

from probes.local_pcm import PCMChunks
from probes.recognize_fixture import run


class LocalPCMTests(unittest.TestCase):
    def test_chunk_bytes_and_boundaries_match_prior_algorithm(self):
        # Quiet intervals deliberately move the split away from 25 seconds.
        samples = np.random.default_rng(4).uniform(-.2, .2, 96 * 16000).astype('<f4')
        samples[23 * 16000:24 * 16000] = 0
        samples[44 * 16000:45 * 16000] = 0
        expected = []
        cursor = 0
        while cursor < len(samples):
            end = min(cursor + 25 * 16000, len(samples))
            if end < len(samples):
                end = min(range(cursor + 20 * 16000, end - 1600 + 1, 1600),
                          key=lambda i: float(np.mean(samples[i:i + 1600] ** 2))) + 800
            expected.append((cursor, end))
            cursor = end
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'audio.f32'
            samples.tofile(path)
            # Prohibit the original unbounded file-read route.
            with patch.object(Path, 'read_bytes', side_effect=AssertionError('whole-file read')):
                with PCMChunks(path, len(samples)) as pcm:
                    actual = []
                    digest = hashlib.sha256()
                    for start, end, chunk in pcm:
                        self.assertLessEqual(chunk.nbytes, 25 * 16000 * 4)
                        self.assertTrue(chunk.flags.c_contiguous)
                        self.assertTrue(chunk.flags.writeable)
                        np.testing.assert_array_equal(chunk, samples[start:end])
                        actual.append((start, end))
                        digest.update(chunk)
                    self.assertEqual(actual, expected)
                    self.assertEqual(digest.hexdigest(), hashlib.sha256(samples).hexdigest())
                    self.assertEqual(pcm.sha256, digest.hexdigest())
                self.assertTrue(pcm.source.closed)

    def test_backend_mutation_cannot_change_file_or_later_chunks(self):
        samples = np.ones(51 * 16000, dtype='<f4')
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'audio.f32'
            samples.tofile(path)
            with PCMChunks(path, len(samples)) as pcm:
                for start, end, chunk in pcm:
                    np.testing.assert_array_equal(chunk, samples[start:end])
                    chunk.fill(0)
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), pcm.sha256)

    def test_length_and_late_nonfinite_sample_rejected(self):
        samples = np.ones(51 * 16000, dtype='<f4')
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'audio.f32'
            samples.tofile(path)
            with self.assertRaisesRegex(ValueError, 'PCM length'):
                with PCMChunks(path, len(samples) + 1):
                    self.fail('invalid length accepted')
            for value in (np.nan, np.inf, -np.inf):
                samples[-1] = value
                samples.tofile(path)
                reader = PCMChunks(path, len(samples))
                with self.assertRaisesRegex(ValueError, 'Non-finite'):
                    with reader:
                        self.fail('invalid final sample accepted')
                self.assertTrue(reader.source.closed)

    def test_change_during_model_reads_is_rejected(self):
        samples = np.ones(60 * 16000, dtype='<f4')
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'audio.f32'
            samples.tofile(path)
            with PCMChunks(path, len(samples)) as pcm:
                chunks = iter(pcm)
                next(chunks)
                with path.open('r+b') as changed:
                    changed.seek(50 * 16000 * 4)
                    changed.write(np.array([.5], dtype='<f4').tobytes())
                with self.assertRaisesRegex(ValueError, 'PCM changed'):
                    list(chunks)


class LocalRecognitionStreamingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.directory = self.root / '.subloom/verification/test'
        self.directory.mkdir(parents=True)
        self.path = self.directory / 'audio.f32'
        self.output = self.directory / 'asr.json'
        self.root_patch = patch('probes.paths.ROOT', self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)

    def recognize(self, samples, **options):
        samples.tofile(self.path)
        with contextlib.redirect_stdout(io.StringIO()):
            return run(self.directory / 'unused.fcpxml', Path('/model'), Path('/aligner'),
                       self.output, self.path, verbose=False,
                       snapshot_override={'sampleCount': len(samples)}, **options)

    def test_alternate_engine_does_not_import_qwen_or_torch(self):
        original_import = builtins.__import__
        def guarded_import(name, *args, **kwargs):
            if name in ('torch', 'qwen_asr'):
                raise AssertionError('unused Qwen dependency imported')
            return original_import(name, *args, **kwargs)
        received = []
        def transcribe(chunk):
            received.append(chunk.copy())
            return [{'text': '你好', 'words': [{'text': '你好', 'start': .1, 'end': .5}]}]
        samples = np.ones(52 * 16000, dtype='<f4') * .1
        with patch('probes.asr_backends.load_backend', return_value=transcribe), \
                patch('builtins.__import__', side_effect=guarded_import):
            result = self.recognize(samples, engine='mlx-whisper')
        self.assertEqual(result['device'], 'mlx')
        np.testing.assert_array_equal(np.concatenate(received), samples)
        self.assertEqual(result['pcm_sha256'], hashlib.sha256(samples).hexdigest())
        np.testing.assert_allclose([row['words'][0]['start'] for row in result['results']], [.1, 20.15, 40.2], rtol=0, atol=1e-12)
        self.assertEqual(result['recognitionDiagnostics']['chunks'][-1]['end'], 52)

    def test_invalid_audio_never_loads_backend(self):
        samples = np.ones(52 * 16000, dtype='<f4')
        samples[-1] = np.nan
        with patch('probes.asr_backends.load_backend') as load:
            with self.assertRaisesRegex(ValueError, 'Non-finite'):
                self.recognize(samples, engine='mlx-whisper')
        load.assert_not_called()
        self.assertFalse(self.output.exists())

    def test_signal_without_text_keeps_result_and_adds_review_intervals(self):
        samples = np.ones(52 * 16000, dtype='<f4') * .1
        with patch('probes.asr_backends.load_backend', return_value=lambda chunk: []):
            result = self.recognize(samples, engine='mlx-whisper')
        self.assertEqual(result['results'], [])
        warnings = result['recognitionDiagnostics']['warnings']
        self.assertEqual(len(warnings), 3)
        self.assertTrue(all(item['reason'] == 'signal-without-text' for item in warnings))
        self.assertEqual((warnings[0]['start'], warnings[-1]['end']), (0, 52))

    def test_backend_mutation_does_not_change_input_diagnostics(self):
        samples = np.full(8 * 16000, .1, dtype='<f4')
        def mutating_backend(chunk):
            chunk.fill(0)
            return []
        with patch('probes.asr_backends.load_backend', return_value=mutating_backend):
            result = self.recognize(samples, engine='mlx-whisper')
        review = result['recognitionDiagnostics']
        self.assertAlmostEqual(review['chunks'][0]['rms'], .1)
        self.assertEqual(review['warnings'][0]['reason'], 'signal-without-text')
        self.assertEqual(result['pcm_sha256'], hashlib.sha256(samples).hexdigest())

    def test_silence_keeps_diagnostic_clock_without_transcription(self):
        transcribe = Mock()
        with patch('probes.asr_backends.load_backend', return_value=transcribe):
            result = self.recognize(np.zeros(52 * 16000, dtype='<f4'), engine='mlx-whisper')
        transcribe.assert_not_called()
        self.assertEqual(result['results'], [])
        diagnostics = result['recognitionDiagnostics']
        self.assertEqual(diagnostics['warnings'], [])
        self.assertEqual((diagnostics['chunks'][0]['start'], diagnostics['chunks'][-1]['end']), (0, 52))

    def test_qwen_model_settings_and_global_times_preserved(self):
        model = Mock()
        model.transcribe.side_effect = lambda **args: [SimpleNamespace(text='你好', time_stamps=[
            SimpleNamespace(text='你好', start_time=.1, end_time=.5)])]
        qwen = SimpleNamespace(Qwen3ASRModel=SimpleNamespace(from_pretrained=Mock(return_value=model)))
        torch = SimpleNamespace(float32=object(), backends=SimpleNamespace(mps=SimpleNamespace(is_available=lambda: True)))
        samples = np.ones(52 * 16000, dtype='<f4') * .1
        with patch.dict('sys.modules', torch=torch, qwen_asr=qwen):
            result = self.recognize(samples)
        qwen.Qwen3ASRModel.from_pretrained.assert_called_once_with('/model', dtype=torch.float32, device_map='cpu',
            attn_implementation='eager', max_inference_batch_size=1, max_new_tokens=512,
            forced_aligner='/aligner', forced_aligner_kwargs={'dtype': torch.float32, 'device_map': 'cpu', 'attn_implementation': 'eager'})
        self.assertEqual(model.transcribe.call_count, 3)
        np.testing.assert_allclose([row['words'][0]['start'] for row in result['results']], [.1, 20.15, 40.2], rtol=0, atol=1e-12)
        self.assertEqual(result['pcm_sha256'], hashlib.sha256(samples).hexdigest())
        self.assertEqual(result['device'], 'cpu')


if __name__ == '__main__':
    unittest.main()
