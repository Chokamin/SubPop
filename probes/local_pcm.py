"""Bounded, validated access to the private float32 PCM used by local ASR."""
import hashlib
import os

import numpy as np


RATE = 16000
MAX_CHUNK_SAMPLES = 25 * RATE
VALIDATION_SAMPLES = 256 * 1024


class PCMChunks:
    """Read one model window at a time, keeping the original project sample clock."""

    def __init__(self, path, sample_count):
        self.path = path
        self.sample_count = sample_count
        self.source = None

    def __enter__(self):
        if isinstance(self.sample_count, bool) or not isinstance(self.sample_count, int) or self.sample_count<=0:
            raise ValueError('Positive integer PCM sample count required')
        self.source = self.path.open('rb')
        try:
            if os.fstat(self.source.fileno()).st_size != self.sample_count * 4:
                raise ValueError('PCM length must cover the complete fixture at 16kHz float32 mono')
            # Reject corrupt samples before loading a model or doing any inference.
            digest = hashlib.sha256()
            remaining = self.sample_count
            while remaining:
                block = self._read(min(remaining, VALIDATION_SAMPLES))
                if not np.isfinite(block).all():
                    raise ValueError('Non-finite PCM samples')
                digest.update(memoryview(block).cast('B'))
                remaining -= len(block)
            self.sha256 = digest.hexdigest()
            return self
        except BaseException:
            self.source.close()
            raise

    def __exit__(self, *error):
        self.source.close()

    def _read(self, sample_count):
        # readinto avoids an additional bytes copy, and gives backends their own
        # writable, contiguous window rather than access to a file mapping.
        samples = np.empty(sample_count, dtype='<f4')
        target = memoryview(samples).cast('B')
        received = 0
        while received < len(target):
            count = self.source.readinto(target[received:])
            if not count:
                raise ValueError('PCM changed while recognition was running')
            received += count
        return samples

    def __iter__(self):
        cursor = 0
        consumed = hashlib.sha256()
        while cursor < self.sample_count:
            self.source.seek(cursor * 4)
            samples = self._read(min(MAX_CHUNK_SAMPLES, self.sample_count - cursor))
            if not np.isfinite(samples).all():
                raise ValueError('Non-finite PCM samples')
            count = len(samples)
            if cursor + count < self.sample_count:
                # Preserve the existing low-energy 20–25 second split exactly.
                candidates = range(20 * RATE, count - 1600 + 1, 1600)
                count = min(candidates, key=lambda i: float(np.mean(samples[i:i + 1600] ** 2))) + 800
            chunk = samples[:count]
            consumed.update(memoryview(chunk).cast('B'))
            yield cursor, cursor + count, chunk
            cursor += count
        # The source is private, but still reject an in-place change between the
        # validation pass and model reads instead of reporting a misleading hash.
        if (os.fstat(self.source.fileno()).st_size != self.sample_count * 4
                or consumed.hexdigest() != self.sha256):
            raise ValueError('PCM changed while recognition was running')
