"""Rebuild and install this machine's SubPop extension; preserves its data."""
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
if __name__=='__main__':
    if not (ROOT/'.venv/bin/python').exists():raise SystemExit('Missing independent SubPop runtime; see README.md')
    subprocess.run([sys.executable,str(ROOT/'scripts/build_probe.py')],check=True,cwd=ROOT)
    subprocess.run(['ditto',str(ROOT/'.subloom/build/SubPop Probe.app'),'/Applications/SubPop.app'],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict','/Applications/SubPop.app'],check=True)
    print('Installed. Reopen the SubPop extension in Final Cut Pro. Existing models and permissions are preserved.')
