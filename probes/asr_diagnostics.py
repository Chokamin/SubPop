"""Bounded local ASR review hints, never a speech detector or text filter.

Only numerical input/output coverage and generic review messages leave this
collector. Audio, transcription text and text fingerprints are not included in
the diagnostic report. An energetic input may be music or noise; a repetition
may be intentional. Neither condition changes the recognized result.
"""
import hashlib
import math
import re


_SIGNAL_RMS = 10 ** (-45 / 20)
_MAX_TEXT_CHECK = 8192
_REPETITION = re.compile(r'(.{4,64}?)\1{3,}')
_LIMITATION = '音频能量不等于人声；这些提示不能证明漏字或识别错误，请试听核对。'


def _text_summary(rows):
    count = 0
    checked = []
    for row in rows:
        for character in row.get('text', ''):
            if character.isalnum():
                count += 1
                if len(checked) < _MAX_TEXT_CHECK:
                    checked.append(character.casefold())
    return count, ''.join(checked)


def _alignment_summary(rows, start, end):
    spans = []
    count = 0
    invalid = 0
    for row in rows:
        for word in row.get('words', []):
            count += 1
            try:
                begin, finish = float(word['start']), float(word['end'])
                if not math.isfinite(begin) or not math.isfinite(finish) or finish < begin:
                    raise ValueError('Invalid diagnostic word interval')
            except (KeyError, TypeError, ValueError, OverflowError):
                invalid += 1
                continue
            begin, finish = max(start, begin), min(end, finish)
            if finish > begin:
                spans.append((begin, finish))
    covered = 0.0
    cursor = start
    for begin, finish in sorted(spans):
        covered += max(0.0, finish - max(begin, cursor))
        cursor = max(cursor, finish)
    return count, round(covered, 6), invalid


class RecognitionDiagnostics:
    """Collect one record per sequential PCM chunk with global word times.

    Storage is capped independently of project length. Repeated chunk text is
    compared with an ephemeral digest; the digest never appears in report().
    """

    def __init__(self, sample_rate=16000, max_chunks=4096, max_warnings=512):
        for value in (sample_rate, max_chunks, max_warnings):
            if isinstance(value, bool) or not isinstance(value, int) or value < 1:
                raise ValueError('Positive integer diagnostic limits required')
        self.sample_rate = sample_rate
        self.max_chunks = max_chunks
        self.max_warnings = max_warnings
        self._chunks = []
        self._warnings = []
        self._chunk_count = 0
        self._warning_count = 0
        self._previous_end = None
        self._repeat_digest = None
        self._repeat_count = 0
        self._repeat_start = 0.0
        self._repeat_chunk = 0
        self._repeat_warning = None

    def _warn(self, reason, start, end, chunk, **extra):
        self._warning_count += 1
        if len(self._warnings) >= self.max_warnings:
            return None
        message = ('该时段有较明显的音频信号，但未生成文字；音乐、环境声或无人声也可能出现此情况，请试听核对。'
                   if reason == 'signal-without-text' else
                   '该时段的识别文字重复较多，请试听核对；原结果已保留。')
        warning = dict(reason=reason, start=round(start, 6), end=round(end, 6),
                       chunk=chunk, message=message, **extra)
        self._warnings.append(warning)
        return warning

    def record(self, start_sample, end_sample, samples, rows):
        """Record current input plus *only* rows produced by this chunk.

        Word times must already be on the full project's zero-based clock.
        Samples are read, not copied or retained after this call.
        """
        import numpy as np

        if (any(isinstance(v, bool) or not isinstance(v, int) for v in (start_sample, end_sample))
                or start_sample < 0 or end_sample <= start_sample
                or (self._previous_end is not None and start_sample != self._previous_end)):
            raise ValueError('Sequential non-empty diagnostic chunks required')
        data = np.asarray(samples)
        if data.ndim != 1 or data.size != end_sample - start_sample or not np.isfinite(data).all():
            raise ValueError('Finite mono PCM matching the diagnostic interval required')
        # Small windows distinguish a sustained signal from one brief impulse.
        # This is deliberately called energy, not voice activity or speech.
        frame_size = max(1, self.sample_rate // 10)
        total_energy = 0.0
        active_samples = 0
        peak = 0.0
        for offset in range(0, len(data), frame_size):
            block = data[offset:offset + frame_size]
            energy = float(np.sum(np.square(block, dtype=np.float64)))
            total_energy += energy
            peak = max(peak, float(np.max(np.abs(block), initial=0)))
            if energy / len(block) >= _SIGNAL_RMS ** 2:
                active_samples += len(block)
        rms = math.sqrt(total_energy / len(data))
        start, end = start_sample / self.sample_rate, end_sample / self.sample_rate
        text_count, text = _text_summary(rows)
        words, aligned, invalid_times = _alignment_summary(rows, start, end)
        self._chunk_count += 1
        self._previous_end = end_sample
        record = dict(index=self._chunk_count, start=round(start, 6), end=round(end, 6),
                      rms=round(rms, 8), peak=round(peak, 8),
                      activeSeconds=round(active_samples / self.sample_rate, 6),
                      textCharacters=text_count, wordCount=words, alignedSeconds=aligned)
        if invalid_times:
            record['invalidWordTimes'] = invalid_times
        if len(self._chunks) < self.max_chunks:
            self._chunks.append(record)
        if text_count == 0 and active_samples >= 2 * self.sample_rate and rms >= _SIGNAL_RMS:
            self._warn('signal-without-text', start, end, self._chunk_count)

        # At least four repetitions, >= 32 characters and half the whole chunk
        # output. Long unchecked output cannot be diagnosed from a prefix.
        if text_count <= _MAX_TEXT_CHECK and any(
                len(match.group()) >= 32 and len(match.group()) >= len(text) / 2
                for match in _REPETITION.finditer(text)):
            self._warn('repetitive-text', start, end, self._chunk_count, pattern='within-chunk')

        eligible = 6 <= text_count <= _MAX_TEXT_CHECK and end - start >= 5
        digest = hashlib.sha256(text.encode('utf-8')).digest() if eligible else None
        if digest is not None and digest == self._repeat_digest:
            self._repeat_count += 1
            if self._repeat_count == 3:
                self._repeat_warning = self._warn('repetitive-text', self._repeat_start,
                                                 end, self._repeat_chunk, pattern='consecutive-chunks')
            elif self._repeat_count > 3 and self._repeat_warning is not None:
                self._repeat_warning['end'] = round(end, 6)
        else:
            self._repeat_digest = digest
            self._repeat_count = 1 if eligible else 0
            self._repeat_start = start
            self._repeat_chunk = self._chunk_count
            self._repeat_warning = None

    def report(self):
        """Return a JSON-safe snapshot without live mutable collector state."""
        return dict(schemaVersion=1, sampleRate=self.sample_rate,
                    chunkCount=self._chunk_count, warningCount=self._warning_count,
                    omittedChunks=self._chunk_count - len(self._chunks),
                    omittedWarnings=self._warning_count - len(self._warnings),
                    chunks=[dict(item) for item in self._chunks],
                    warnings=[dict(item) for item in self._warnings], limitation=_LIMITATION)
