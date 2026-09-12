"""Offline ASR experiment on an FCP-exported test snapshot, NOT live integration."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import hashlib
from fractions import Fraction
try:
    from .project import inspect
except ImportError:
    from project import inspect


def run(xml, asr, aligner, output, pcm_path=None, device="cpu", verbose=True, audio_mode="dialogue", vocabulary=None, engine=None):
    from .vocabulary import context
    hints=context(vocabulary or [])
    snapshot = inspect(xml,audio_mode)
    from .paths import ROOT
    expected = ROOT / '.subloom/verification'
    for key in ('HF_HUB_OFFLINE', 'TRANSFORMERS_OFFLINE', 'HF_HUB_DISABLE_TELEMETRY'):
        os.environ[key] = '1'
    os.environ['PYTORCH_ENABLE_MPS_FALLBACK'] = '1'
    os.environ['HF_HOME'] = str(output.parent / 'hf')
    import numpy as np
    import torch
    from opencc import OpenCC
    from qwen_asr import Qwen3ASRModel
    if pcm_path is not None:
        if not pcm_path.resolve().is_relative_to(expected):
            raise ValueError('PCM must be a copy in the isolated verification directory')
        pcm = pcm_path.read_bytes()
        if len(pcm) != snapshot['sampleCount']*4:
            raise ValueError('PCM length must cover the complete fixture at 16kHz float32 mono')
    else:
        raise ValueError('Timeline recognition requires rendered PCM; source-file fallback removed')
    samples = np.frombuffer(pcm, dtype='<f4').copy()
    if not np.isfinite(samples).all():
        raise ValueError('Non-finite PCM samples')
    if device not in ('cpu', 'mps'):raise ValueError('Unsupported device')
    if device == 'mps' and not torch.backends.mps.is_available():raise ValueError('MPS unavailable')
    if engine:
        from .asr_backends import load_backend
        transcribe=load_backend(engine,asr,hints)
        device='mlx' if engine=='mlx-whisper' else 'cpu'
    else:
        model = Qwen3ASRModel.from_pretrained(str(asr), dtype=torch.float32, device_map=device,
            attn_implementation='eager', max_inference_batch_size=1, max_new_tokens=512,
            forced_aligner=str(aligner), forced_aligner_kwargs=dict(dtype=torch.float32, device_map=device, attn_implementation='eager'))
    converter = OpenCC('t2s')
    rows = []
    cursor=0;chunk_index=0
    while cursor<len(samples):
        end=min(cursor+25*16000,len(samples))
        if end<len(samples):
            # Prefer a low-energy boundary in the last five seconds; no speech
            # is dropped, and alignment is offset back to the project clock.
            search=cursor+20*16000
            candidates=range(search,end-1600+1,1600)
            end=min(candidates,key=lambda i:float(np.mean(samples[i:i+1600]**2)))+800
        chunk=samples[cursor:end]
        chunk_index+=1
        print(json.dumps({'stage':'recognize','progress':round(end/len(samples),4),'chunk':chunk_index}),flush=True)
        if np.max(np.abs(chunk),initial=0)>1e-7:
            if engine:
                for row in transcribe(chunk):
                    row['text']=converter.convert(row['text'])
                    for word in row['words']:
                        word['text']=converter.convert(word['text'])
                        word['start']+=cursor/16000
                        word['end']=min(word['end']+cursor/16000,end/16000)
                    rows.append(row)
            else:
                parts=model.transcribe(audio=(chunk,16000),language='Chinese',return_time_stamps=True,context=hints)
                for part in parts:
                    if not part.text.strip():continue
                    rows.append(dict(text=converter.convert(part.text),words=[dict(text=converter.convert(w.text),start=w.start_time+cursor/16000,end=min(w.end_time+cursor/16000,len(samples)/16000)) for w in part.time_stamps]))
        cursor=end
    evidence = 'Offline recognition of rendered project PCM; chunk timestamps mapped to full project'
    output.write_text(json.dumps(dict(backendVersion=1, evidence=evidence, snapshot=snapshot, pcm_sha256=hashlib.sha256(pcm).hexdigest(), device=device, results=rows), ensure_ascii=False, indent=2))
    if verbose:print(output.read_text())
    return json.loads(output.read_text())


if __name__ == '__main__':
    p=argparse.ArgumentParser()
    for name in ('xml','asr','aligner','output'):p.add_argument('--'+name,required=True,type=Path)
    p.add_argument('--pcm',type=Path)
    a=p.parse_args()
    run(a.xml,a.asr,a.aligner,a.output,a.pcm)
