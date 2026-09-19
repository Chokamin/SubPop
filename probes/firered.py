"""Pinned FireRedASR2-AED, local CPU inference with measured CTC timestamps."""
import argparse
import hashlib
from pathlib import Path


def load(path):
    import numpy as np
    import torch
    from .models import model_spec
    from .asr_backends import timed_row
    from .vendor.firered.data.asr_feat import ASRFeatExtractor
    from .vendor.firered.models.fireredasr_aed import FireRedAsrAed
    from .vendor.firered.tokenizer.aed_tokenizer import ChineseCharEnglishSpmTokenizer

    path = Path(path)
    spec = model_spec('firered-asr2-aed')
    # This checkpoint includes Namespace metadata: verify pinned bytes even when
    # a model was manually installed, then restrict unpickling to that type.
    for name, expected in spec['sha256'].items():
        h = hashlib.sha256()
        with (path/name).open('rb') as source:
            for block in iter(lambda: source.read(4*1024*1024), b''):
                h.update(block)
        if h.hexdigest() != expected:
            raise ValueError('FireRed 模型校验失败，请重新下载')
    with torch.serialization.safe_globals([argparse.Namespace]):
        checkpoint = torch.load(path/'model.pth.tar', map_location='cpu', weights_only=True)
    # Avoid allocating a second 4.7 GB copy of the parameters during loading.
    from accelerate import init_empty_weights
    with init_empty_weights():
        model = FireRedAsrAed.from_args(checkpoint['args'])
    model.load_state_dict(checkpoint['model_state_dict'], strict=True, assign=True)
    del checkpoint
    model.eval()
    extractor = ASRFeatExtractor(str(path/'cmvn.ark'))
    tokenizer = ChineseCharEnglishSpmTokenizer(str(path/'dict.txt'), str(path/'train_bpe1000.model'))

    @torch.inference_mode()
    def transcribe(samples):
        duration = len(samples)/16000
        # Kaldi features expect signed 16-bit PCM amplitude, not normalized float.
        pcm = np.clip(np.rint(np.asarray(samples)*32768), -32768, 32767).astype(np.int16)
        features, lengths, _, _, _ = extractor([(16000, pcm)], ['subpop'])
        if features is None:
            return []
        hypotheses = model.transcribe(features, lengths, beam_size=3, nbest=1,
            softmax_smoothing=1.25, length_penalty=0.6, eos_penalty=1.0,
            return_timestamp=True)
        if len(hypotheses) != 1 or not hypotheses[0]:
            raise ValueError('FireRed 未返回识别结果')
        hypothesis = hypotheses[0][0]
        ids = [int(i) for i in hypothesis['yseq'] if int(i) != 0]
        if not ids:
            return []
        times = hypothesis.get('timestamp')
        if not times or len(times[0]) != len(ids) or len(times[1]) != len(ids):
            raise ValueError('FireRed 未返回完整逐词时间')
        words = []
        for token, start, end in zip(ids, *times):
            text = tokenizer.detokenize([token], '', False).lower()
            if text in ('<blank>', '<sil>'):
                continue
            words.append((text, max(0, min(duration, start-0.06)), max(0, min(duration, end-0.06))))
        row = timed_row(tokenizer.merge_spm_timestamp(words), duration)
        return [row] if row else []
    return transcribe
