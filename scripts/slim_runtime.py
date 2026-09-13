"""Trim the staged inference runtime only; preserve development installs and licenses."""
from pathlib import Path
import json
import shutil
import subprocess

# Web demos are not part of the native FCP application. Never prune by import tracing alone.
UNUSED_DISTRIBUTIONS = ('gradio', 'gradio_client', 'pip')

def tree_bytes(root):
    return sum(p.stat().st_size for p in root.rglob('*') if p.is_file() and not p.is_symlink())

def slim(runtime):
    runtime=Path(runtime).resolve()
    if runtime.name != 'Runtime':raise ValueError('Refusing to trim outside a staged Runtime directory')
    site=runtime/'.venv/lib/python3.12/site-packages'
    if not site.is_dir():raise ValueError('Expected staged Python 3.12 runtime')
    before=tree_bytes(runtime);removed=[]
    def remove(path):
        if not path.exists() or path.is_symlink():return
        if not path.resolve().is_relative_to(runtime):raise ValueError('Path outside staged runtime')
        removed.append(str(path.relative_to(runtime)))
        if path.is_dir():shutil.rmtree(path)
        else:path.unlink()
    for name in UNUSED_DISTRIBUTIONS:
        remove(site/name)
        # Retain dist-info, including license notices and dependency provenance.
    for path in sorted(site.rglob('*'),key=lambda p:len(p.parts),reverse=True):
        if path.is_dir() and path.name in {'tests','test','__pycache__'}:
            remove(path)
    for relative in ('.venv/include','.venv/lib/python3.12/test','.venv/lib/python3.12/idlelib',
                     '.venv/lib/python3.12/ensurepip','.venv/share/man',
                     '.venv/lib/python3.12/site-packages/torch/include',
                     '.venv/lib/python3.12/site-packages/torch/share',
                     '.venv/lib/python3.12/site-packages/torch/bin/protoc',
                     '.venv/lib/python3.12/site-packages/torch/bin/protoc-3.21.12.0',
                     '.venv/lib/python3.12/site-packages/mlx/include',
                     '.venv/lib/python3.12/site-packages/mlx/share'):
        remove(runtime/relative)
    # Remove local/debug symbols only. Exported symbols required by Python/dlopen remain intact.
    stripped=[]
    for relative in ('torch/lib/libtorch_cpu.dylib','torch/lib/libtorch_python.dylib',
                     'llvmlite/binding/libllvmlite.dylib','mlx/lib/libmlx.dylib'):
        path=site/relative
        if path.is_file():
            old=path.stat().st_size
            subprocess.run(['strip','-x',str(path)],check=True,capture_output=True)
            # strip invalidates upstream signatures; keep unsigned validation builds loadable.
            subprocess.run(['codesign','--force','--sign','-',str(path)],check=True,capture_output=True)
            stripped.append({'path':relative,'before':old,'after':path.stat().st_size})
    report={'beforeBytes':before,'afterBytes':tree_bytes(runtime),'removed':removed,'stripped':stripped}
    (runtime/'runtime-trimming.json').write_text(json.dumps(report,indent=2)+'\n')
    return report

if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('runtime',type=Path)
    print(json.dumps(slim(parser.parse_args().runtime),indent=2))
