"""Explicit CLI model install, using the same verified downloader as the UI."""
import argparse
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from probes.models import CATALOG
from probes.model_download import install

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('model',choices=[m['id'] for m in CATALOG['models']]);args=parser.parse_args()
    install(args.model)
    print('Model and shared aligner verified and ready.')
