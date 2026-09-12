"""Keep packaged code read-only and store models/jobs in per-user application support."""
import os
from pathlib import Path
CODE_ROOT=Path(__file__).resolve().parents[1]
ROOT=Path(os.environ.get('SUBPOP_DATA_ROOT',str(CODE_ROOT))).expanduser().resolve()
AUDIO_BINARY=CODE_ROOT/'.subloom/build/SubPopAudioProbeCLI'
