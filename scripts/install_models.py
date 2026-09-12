"""Install a pinned official Qwen ASR model into SubPop's own model directory.

Run with .venv/bin/python. Recognition never downloads or sends audio online.
"""
import argparse
import os
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from probes.models import ROOT, CATALOG, model_spec, check_files

def install(model_id):
    spec=model_spec(model_id)
    os.environ['HF_HUB_DISABLE_TELEMETRY']='1'
    os.environ['HF_HUB_DISABLE_IMPLICIT_TOKEN']='1'
    from huggingface_hub import snapshot_download
    snapshot_download(spec['repository'],revision=spec['revision'],local_dir=ROOT/'.subloom/models'/spec['directory'],allow_patterns=list(spec['files']),token=False)
    check_files(spec)
    print(spec['name']+' installed and file sizes/configuration verified.')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('model',choices=[m['id'] for m in CATALOG['models']]);args=parser.parse_args();install(args.model)
