FireRedASR2-AED inference subset, Copyright 2026 Xiaohongshu (Kaituo Xu).
Source: https://github.com/FireRedTeam/FireRedASR2S
Revision: 4e7d9aaf4482a47cec1724807026b9b151926eb5
License: Apache-2.0 (included).
SubPop changes: replace torchaudio forced alignment with local NumPy CTC Viterbi; raise on failed alignment, never fabricate timestamps. CPU-only wrapper lives in probes/firered.py. Other inference modules retain upstream implementation.
