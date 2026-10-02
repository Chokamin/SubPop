"""Actual built native decoder regressions; synthetic media, no FCP or ASR."""
from array import array
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import wave
import xml.etree.ElementTree as ET

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / '.subloom/build/SubPopAudioProbeCLI'
UID = 'SYNTHETIC-DECODER-REPEATABILITY'
RATE = 16000
START = Fraction(31498, RATE)
COUNT = 64597


def sha(data):
    return hashlib.sha256(data).hexdigest()


def signal(rate, seconds, kind=0):
    """Changing frequencies identify the source clock and expose bad tails."""
    values = array('h')
    for index in range(round(rate * seconds)):
        time = index / rate
        frequency = (kind + 1) * 137 + (int(time) % 5) * 47
        value = .18 * math.sin(2 * math.pi * frequency * time)
        value += .07 * math.sin(2 * math.pi * (frequency * 1.5 + 23) * time)
        value += .015 * math.sin(2 * math.pi * 29 * time)
        values.append(round(value * 32767))
    return values


def write_wave(path, rate, channels):
    interleaved = array('h')
    for frame in zip(*channels):
        interleaved.extend(frame)
    if sys.byteorder != 'little':
        interleaved.byteswap()
    with wave.open(str(path), 'wb') as output:
        output.setparams((len(channels), 2, rate, 0, 'NONE', 'not compressed'))
        output.writeframes(interleaved.tobytes())


class DecoderRepeatabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not BINARY.is_file():
            raise RuntimeError('Run scripts/build_probe.py before the native decoder tests')
        cls.scratch = tempfile.TemporaryDirectory(prefix='subpop-decoder-repeatability-')
        cls.directory = Path(cls.scratch.name)
        cls.binary = BINARY
        cls.binary_digest = sha(BINARY.read_bytes())
        cls.invocations = 0
        cls.mono48 = cls.directory / 'mono48.wav'
        cls.source48 = signal(48000, 12)
        write_wave(cls.mono48, 48000, [cls.source48])
        cls.mono44 = cls.directory / 'mono44.wav'
        cls.source44 = signal(44100, 12)
        write_wave(cls.mono44, 44100, [cls.source44])
        cls.stereo48 = cls.directory / 'stereo48.wav'
        left, right = signal(48000, 12, 0), signal(48000, 12, 1)
        write_wave(cls.stereo48, 48000, [left, right])
        # Independently create the AV default stereo downmix reference. The
        # 16-bit reference adds at most half one integer sample of quantization.
        cls.stereo_reference = cls.directory / 'stereo-mono-reference.wav'
        mixed = array('h', (round((a + b) / math.sqrt(2)) for a, b in zip(left, right)))
        write_wave(cls.stereo_reference, 48000, [mixed])
        cls.ffmpeg = shutil.which('ffmpeg')
        if cls.ffmpeg is None and Path('/opt/homebrew/bin/ffmpeg').is_file():
            cls.ffmpeg = '/opt/homebrew/bin/ffmpeg'

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def native(self, media, start=START, count=COUNT, channels=1, mix=None):
        start = Fraction(start)
        duration = Fraction(count, RATE)
        root = ET.Element('fcpxml', version='1.14')
        resources = ET.SubElement(root, 'resources')
        asset = ET.SubElement(resources, 'asset', id='source', hasAudio='1', start='0s',
                              audioChannels=str(channels), audioSources='1')
        ET.SubElement(asset, 'media-rep', kind='original-media', src=media.as_uri())
        p = ET.SubElement(root, 'project', uid=UID, name='Synthetic native decoder regression')
        sequence = ET.SubElement(p, 'sequence', duration=f'{duration}s', tcStart='0s')
        spine = ET.SubElement(sequence, 'spine')
        ET.SubElement(spine, 'asset-clip', ref='source', offset='0s', start=f'{start}s',
                      duration=f'{duration}s', audioRole='dialogue')
        data = ET.tostring(root, encoding='utf-8')
        xml = self.directory / 'input.fcpxml'
        xml.write_bytes(data)
        self.__class__.invocations += 1
        output = self.directory / f'decode-{self.__class__.invocations:03d}'
        output.mkdir()
        command = [str(self.binary), str(xml), UID, str(output)]
        if mix is not None:
            command.append(json.dumps(mix, allow_nan=False))
        result = subprocess.run(command, capture_output=True, text=True, check=True, timeout=60)
        decoded = json.loads(result.stdout)
        self.assertEqual(decoded.get('status'), 'decoded', decoded)
        pcm = (output / decoded['pcmFile']).read_bytes()
        self.assertEqual(decoded['sampleCount'], count, decoded)
        self.assertEqual(decoded['sampleRate'], RATE)
        self.assertEqual(decoded['channels'], 1)
        self.assertEqual(decoded['pcmBytes'], count * 4)
        self.assertEqual(len(pcm), count * 4)
        self.assertAlmostEqual(decoded['sourceStartSeconds'], float(start), places=9)
        values = np.frombuffer(pcm, dtype='<f4')
        self.assertTrue(np.isfinite(values).all())
        return decoded, pcm, data

    def repeated(self, media, repetitions, **kwargs):
        media_digest = sha(media.read_bytes())
        outputs = [self.native(media, **kwargs) for _ in range(repetitions)]
        self.assertEqual(sha(media.read_bytes()), media_digest)
        self.assertEqual(sha(self.binary.read_bytes()), self.binary_digest)
        self.assertEqual(len({sha(xml) for _, _, xml in outputs}), 1)
        hashes = [sha(pcm) for _, pcm, _ in outputs]
        self.assertEqual(len(set(hashes)), 1,
                         f'Identical native input decoded different PCM hashes: {hashes}')
        return outputs[0][0], np.frombuffer(outputs[0][1], dtype='<f4')

    def assert_source_clock(self, actual, source, source_rate, start=START):
        # Independently sample the known WAV at the requested source time.
        # Ignore abrupt synthetic frequency changes and SRC boundary ringing.
        times = float(start) + np.arange(len(actual)) / RATE
        source_values = np.asarray(source, dtype=np.float64) / 32768
        expected = np.interp(times * source_rate, np.arange(len(source_values)), source_values)
        phase = times % 1
        stable = (phase > .03) & (phase < .97)
        stable[:256] = False
        stable[-256:] = False
        self.assertGreater(int(stable.sum()), len(actual) * .8)
        error = actual[stable] - expected[stable]
        self.assertLess(float(np.abs(error).max()), .008)
        self.assertLess(float(np.sqrt(np.mean(error ** 2))), .002)
        correlation = np.corrcoef(actual[stable], expected[stable])[0, 1]
        self.assertGreater(float(correlation), .9995)
        self.assertGreater(float(np.max(np.abs(actual[-300:]))), .05)
        # Losing the source offset produces an unrelated frequency sequence.
        wrong = np.interp(np.arange(len(actual)) * source_rate / RATE,
                          np.arange(len(source_values)), source_values)
        self.assertGreater(float(np.sqrt(np.mean((actual[stable] - wrong[stable]) ** 2))), .05)

    def test_fractional_48k_mono_is_repeatable_and_keeps_source_clock(self):
        # The end crosses AVAssetReader's 64000-output-sample boundary. Build138
        # sometimes replaces its last 597 samples despite exactly identical XML.
        _, actual = self.repeated(self.mono48, 24)
        self.assert_source_clock(actual, self.source48, 48000)

    def test_fractional_44100_mono_is_repeatable_and_keeps_source_clock(self):
        _, actual = self.repeated(self.mono44, 8)
        self.assert_source_clock(actual, self.source44, 44100)

    def test_default_stereo_is_repeatable_and_preserves_downmix_gain(self):
        _, actual = self.repeated(self.stereo48, 8, channels=2)
        _, reference, _ = self.native(self.stereo_reference)
        expected = np.frombuffer(reference, dtype='<f4')
        self.assertLess(float(np.abs(actual[128:-128] - expected[128:-128]).max()), .00015)
        self.assertLess(abs(float(np.sqrt(np.mean(actual ** 2))) /
                            float(np.sqrt(np.mean(expected ** 2))) - 1), .001)
        # Explicit default selection and omitted selection have the same weights.
        _, explicit, _ = self.native(self.stereo48, channels=2,
                                     mix={'components': None, 'expectedChannels': 2, 'expectedSources': 1})
        self.assertEqual(actual.tobytes(), explicit)

    def test_aac_fractional_range_is_repeatable_and_matches_whole_source_clock(self):
        if self.ffmpeg is None:
            self.skipTest('ffmpeg is needed to create the synthetic AAC fixture')
        media = self.directory / 'packet-fraction.m4a'
        subprocess.run([self.ffmpeg, '-v', 'error', '-nostdin', '-y', '-i', str(self.mono48),
                        '-c:a', 'aac', '-b:a', '192k', str(media)], check=True, capture_output=True)
        _, actual = self.repeated(media, 8)
        _, whole, _ = self.native(media, start=0, count=8 * RATE)
        expected = np.frombuffer(whole, dtype='<f4')[31498:31498 + COUNT]
        # Compressed packet priming can differ at the edges; the interior must
        # retain the exact source clock rather than shift by a decoded packet.
        begin, end = 512, len(actual) - 512
        a, b = actual[begin:end].astype(np.float64), expected[begin:end].astype(np.float64)
        self.assertLess(float(np.sqrt(np.mean((a - b) ** 2))), .002)
        self.assertGreater(float(np.corrcoef(a, b)[0, 1]), .9995)
        lags = range(-4, 5)
        correlations = [float(np.dot(a[4:-4], expected[begin + 4 + lag:end - 4 + lag])) for lag in lags]
        self.assertEqual(list(lags)[int(np.argmax(correlations))], 0)
        self.assertGreater(float(np.max(np.abs(actual[-300:]))), .05)

    def test_delayed_short_track_preserves_known_silence_and_audible_position(self):
        if self.ffmpeg is None:
            self.skipTest('ffmpeg is needed to create the synthetic delayed track fixture')
        short = self.directory / 'short.wav'
        write_wave(short, 48000, [signal(48000, 2)])
        media = self.directory / 'delayed-short.mov'
        subprocess.run([self.ffmpeg, '-v', 'error', '-nostdin', '-y',
                        '-f', 'lavfi', '-t', '6', '-i', 'color=c=black:size=160x90:rate=25',
                        '-itsoffset', '1.25', '-i', str(short), '-map', '0:v:0', '-map', '1:a:0',
                        '-c:v', 'mpeg4', '-c:a', 'pcm_s16le', '-t', '6', str(media)],
                       check=True, capture_output=True)
        _, actual = self.repeated(media, 5, start=Fraction(1, 2), count=5 * RATE)
        # AVFoundation exposes the movie's leading empty edit as silence inside
        # a track starting at zero. SRC may ring near the content transition;
        # check the silence interior and the exact audible waveform separately.
        self.assertTrue(np.all(actual[:11500] == 0))
        self.assertTrue(np.all(actual[44000:] == 0))
        self.assertGreater(float(np.max(np.abs(actual[13000:43000]))), .05)
        _, direct, _ = self.native(short, start=0, count=2 * RATE)
        self.assertEqual(actual[12000:44000].tobytes(), direct)

    def test_16k_sample_aligned_trim_remains_exact(self):
        media = self.directory / 'mono16.wav'
        source = signal(RATE, 8)
        write_wave(media, RATE, [source])
        _, actual = self.repeated(media, 5)
        expected = np.asarray(source, dtype=np.float32)[31498:31498 + COUNT] / 32768
        self.assertEqual(actual.tobytes(), expected.tobytes())


if __name__ == '__main__':
    unittest.main()
