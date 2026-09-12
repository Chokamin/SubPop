"""Offline ASR experiment on an FCP-exported test snapshot, NOT live integration."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import hashlib
from fractions import Fraction
try:
    from .readback import inspect
except ImportError:
    from readback import inspect


def run(xml, asr, aligner, output, pcm_path=None, device="cpu", verbose=True):
    snapshot = inspect(xml)
    expected = Path(__file__).resolve().parents[1] / '.subloom/verification/mandarin.mp4'
    if Path(snapshot['media']).resolve() != expected or snapshot['project'] != 'Subloom-Original':
        raise ValueError('Only the isolated fixture is allowed')
    for key in ('HF_HUB_OFFLINE', 'TRANSFORMERS_OFFLINE', 'HF_HUB_DISABLE_TELEMETRY'):
        os.environ[key] = '1'
    os.environ['PYTORCH_ENABLE_MPS_FALLBACK'] = '1'
    os.environ['HF_HOME'] = str(output.parent / 'hf')
    import numpy as np
    import torch
    from opencc import OpenCC
    from qwen_asr import Qwen3ASRModel
    if pcm_path is not None:
        if not pcm_path.resolve().is_relative_to(expected.parent):
            raise ValueError('PCM must be a copy in the isolated verification directory')
        pcm = pcm_path.read_bytes()
        if len(pcm) != Fraction(snapshot['duration'])*16000*4:
            raise ValueError('PCM length must cover the complete fixture at 16kHz float32 mono')
    else:
        pcm = subprocess.run(['ffmpeg', '-v', 'error', '-ss', str(float(Fraction(snapshot['source_start']))),
            '-i', snapshot['media'], '-t', str(float(Fraction(snapshot['duration']))),
            '-vn', '-ac', '1', '-ar', '16000', '-f', 'f32le', 'pipe:1'], check=True, capture_output=True).stdout
    samples = np.frombuffer(pcm, dtype='<f4').copy()
    if not np.isfinite(samples).all():
        raise ValueError('Non-finite PCM samples')
    if device not in ('cpu', 'mps'):raise ValueError('Unsupported device')
    if device == 'mps' and not torch.backends.mps.is_available():raise ValueError('MPS unavailable')
    model = Qwen3ASRModel.from_pretrained(str(asr), dtype=torch.float32, device_map=device,
        attn_implementation='eager', max_inference_batch_size=1, max_new_tokens=512,
        forced_aligner=str(aligner), forced_aligner_kwargs=dict(dtype=torch.float32, device_map=device, attn_implementation='eager'))
    result = model.transcribe(audio=(samples,16000), language='Chinese', return_time_stamps=True)
    converter = OpenCC('t2s')
    rows = []
    for part in result:
        rows.append(dict(text=converter.convert(part.text), words=[dict(text=converter.convert(w.text), start=w.start_time, end=w.end_time) for w in part.time_stamps]))
    evidence = 'ASR of native-extension PCM via external test process; not automatic plugin workflow' if pcm_path else 'offline ASR of FCP export; not live Workflow Extension'
    output.write_text(json.dumps(dict(evidence=evidence, snapshot=snapshot, pcm_sha256=hashlib.sha256(pcm).hexdigest(), device=device, results=rows), ensure_ascii=False, indent=2))
    if verbose:print(output.read_text())
    return json.loads(output.read_text())


if __name__ == '__main__':
    p=argparse.ArgumentParser()
    for name in ('xml','asr','aligner','output'):p.add_argument('--'+name,required=True,type=Path)
    p.add_argument('--pcm',type=Path)
    a=p.parse_args()
    run(a.xml,a.asr,a.aligner,a.output,a.pcm)
