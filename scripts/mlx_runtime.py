"""Bundle MLX built for the package's minimum macOS; cache stays outside Git.

pip on the release Mac picks the newest MLX wheels for that Mac. Those carry a
Metal 4.0 metallib and dylibs that need macOS 26.2, which fail on macOS 15 with
"Metal language version 4.0 incompatible with this OS". The packaged runtime
therefore swaps in the official macOS 15 wheels of the same locked version.
The macOS 26 wheels are also shipped, outside site-packages, in ALTERNATE; the
worker imports them only on a macOS that meets ALTERNATE/selection.json
(probes/mlx_select.py), so newer Macs keep MLX's Metal 4 kernels. The
development venv is left untouched.
"""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MINIMUM_MACOS = (15, 0)
VERSION = '0.32.2'
CACHE = ROOT / '.subloom/dependencies/mlx-wheels'
# Official PyPI files and digests for the locked version (requirements-asr.lock.txt).
WHEELS = (
    dict(distribution='mlx', file=f'mlx-{VERSION}-cp312-cp312-macosx_15_0_arm64.whl', size=619376,
         sha256='cf63fd5c32258ab07523b06401c20ee2280bf56e26e991d05bf6fd8a4d42d1f6',
         url='https://files.pythonhosted.org/packages/bc/be/c821eed5b7c13b42c114aec54c757545d6eeecce25d3212ea7d18dd79cfd/'
             f'mlx-{VERSION}-cp312-cp312-macosx_15_0_arm64.whl'),
    dict(distribution='mlx_metal', file=f'mlx_metal-{VERSION}-py3-none-macosx_15_0_arm64.whl', size=42512323,
         sha256='55a369250d220b2cf10213a87a2ac1b1a420608c5b35b1df4e7147ac8e32f121',
         url='https://files.pythonhosted.org/packages/79/ec/34f37376e26d537fadffb99af3a760d6545e37f5e1a30a552baadf237fc5/'
             f'mlx_metal-{VERSION}-py3-none-macosx_15_0_arm64.whl'),
)
ALTERNATE = 'mlx-macos26'
NEWER_WHEELS = (
    dict(distribution='mlx', file=f'mlx-{VERSION}-cp312-cp312-macosx_26_0_arm64.whl', size=619488,
         sha256='68560fd648c5bb900aa6f6765cd74c5a8abaf092d97d73584a57b7545966c227',
         url='https://files.pythonhosted.org/packages/0b/eb/af6b1a8b45f24d22e4735c52e0696c66233bd477e1b9e9dbbef225bdf88b/'
             f'mlx-{VERSION}-cp312-cp312-macosx_26_0_arm64.whl'),
    dict(distribution='mlx_metal', file=f'mlx_metal-{VERSION}-py3-none-macosx_26_0_arm64.whl', size=64367860,
         sha256='e6abeac9ac5265830c9c1541b6f96e9be37a85c2446763a46ad466c63a3837ab',
         url='https://files.pythonhosted.org/packages/dd/cd/4e50bf325100e7165e13d025f264362bf0009196269f9eaf87f2c6e738a2/'
             f'mlx_metal-{VERSION}-py3-none-macosx_26_0_arm64.whl'),
)
MACHO = {bytes.fromhex(v) for v in ('feedface', 'feedfacf', 'cefaedfe', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}
METAL_TARGET = re.compile(rb'apple-macosx(\d+)\.(\d+)')


def checksum(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def fetch(wheel, cache=CACHE):
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / wheel['file']
    if not path.exists():
        partial = path.with_suffix('.partial')
        try:
            urllib.request.urlretrieve(wheel['url'], partial)
            if partial.stat().st_size != wheel['size'] or checksum(partial) != wheel['sha256']:
                raise ValueError('MLX wheel checksum mismatch: ' + wheel['file'])
            partial.replace(path)
        finally:
            partial.unlink(missing_ok=True)
    # Verify on every build; a cached file must not silently change what ships.
    if path.stat().st_size != wheel['size'] or checksum(path) != wheel['sha256']:
        raise ValueError('MLX wheel checksum mismatch: ' + wheel['file'])
    return path


def validate(archive, distribution):
    """Allow only the mlx package and the wheel's own dist-info, without links."""
    allowed = {'mlx', f'{distribution}-{VERSION}.dist-info'}
    with zipfile.ZipFile(archive) as wheel:
        for member in wheel.infolist():
            parts = Path(member.filename).parts
            if (not parts or member.filename.startswith('/') or '..' in parts or parts[0] not in allowed
                    or (member.external_attr >> 16) & 0o170000 == 0o120000):
                raise ValueError('Unexpected MLX wheel member: ' + member.filename)


def extract(archive, site, distribution):
    validate(archive, distribution)
    with zipfile.ZipFile(archive) as wheel:
        for member in wheel.infolist():
            target = site / member.filename
            if member.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with wheel.open(member) as source, target.open('wb') as output:
                shutil.copyfileobj(source, output)
            mode = (member.external_attr >> 16) & 0o777
            target.chmod(mode or 0o644)


def install(site, wheels=WHEELS, cache=CACHE):
    """Replace the staged MLX with the minimum-macOS wheels of the same version."""
    site = Path(site)
    for wheel in wheels:
        if not (site / f"{wheel['distribution']}-{VERSION}.dist-info").is_dir():
            raise ValueError(f"Staged runtime does not use locked {wheel['distribution']} {VERSION}")
    archives = [fetch(wheel, cache) for wheel in wheels]
    # Check every archive before removing anything from the staged runtime.
    for wheel, archive in zip(wheels, archives):
        validate(archive, wheel['distribution'])
    shutil.rmtree(site / 'mlx')
    for wheel in wheels:
        shutil.rmtree(site / f"{wheel['distribution']}-{VERSION}.dist-info")
    for wheel, archive in zip(wheels, archives):
        extract(archive, site, wheel['distribution'])
    return [{'file': wheel['file'], 'sha256': wheel['sha256']} for wheel in wheels]


def install_alternate(runtime, wheels=NEWER_WHEELS, cache=CACHE):
    """Ship the newer-macOS MLX beside site-packages with the macOS it requires."""
    runtime = Path(runtime)
    target = runtime / ALTERNATE
    if target.exists():
        raise ValueError('Alternate MLX directory already exists')
    archives = [fetch(wheel, cache) for wheel in wheels]
    for wheel, archive in zip(wheels, archives):
        validate(archive, wheel['distribution'])
    target.mkdir()
    for wheel, archive in zip(wheels, archives):
        extract(archive, target, wheel['distribution'])
    # Headers and CMake files are build-time only, as in slim_runtime for site-packages.
    for name in ('include', 'share'):
        shutil.rmtree(target / 'mlx' / name, ignore_errors=True)
    required = max(filter(None, (file_requirement(path) for path in target.rglob('*')
                                 if path.is_file() and not path.is_symlink())), default=None)
    if not required or required <= MINIMUM_MACOS:
        raise ValueError('Alternate MLX does not need a newer macOS; nothing to select')
    manifest = {'minimumMacOS': list(required), 'version': VERSION,
                'wheels': [{'file': wheel['file'], 'sha256': wheel['sha256']} for wheel in wheels]}
    (target / 'selection.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def version_tuple(text):
    return tuple(int(part) for part in text.split('.')[:2])


def macho_minimum(path):
    """Highest minimum macOS among a Mach-O file's slices, or None if not Mach-O."""
    with Path(path).open('rb') as stream:
        if stream.read(4) not in MACHO:
            return None
    output = subprocess.run(['vtool', '-show-build', str(path)], capture_output=True, text=True, check=True).stdout
    versions = []
    # Read each load command on its own: LC_BUILD_VERSION also lists the linker's
    # "tool LD / version 1267.0", which is not an OS version.
    for block in output.split('Load command')[1:]:
        if 'LC_BUILD_VERSION' in block and re.search(r'platform\s+MACOS\b', block):
            match = re.search(r'minos\s+(\d+\.\d+)', block)
        elif 'LC_VERSION_MIN_MACOSX' in block:
            match = re.search(r'version\s+(\d+\.\d+)', block)
        else:
            match = None
        if match:
            versions.append(version_tuple(match.group(1)))
    return max(versions) if versions else None


def file_requirement(path):
    """macOS a file needs: a Metal library's compile target or a Mach-O minimum."""
    path = Path(path)
    if path.suffix == '.metallib':
        targets = {(int(a), int(b)) for a, b in METAL_TARGET.findall(path.read_bytes())}
        if not targets:
            raise ValueError('Metal library without a recorded macOS target: ' + str(path))
        return max(targets)
    return macho_minimum(path)


def alternate_limit(path, limits):
    for directory, limit in limits.items():
        if path.is_relative_to(directory):
            return limit
    return None


def check_minimum(root, minimum=MINIMUM_MACOS):
    """Refuse binaries or Metal libraries that need a newer macOS than the package allows.

    Only an ALTERNATE directory with selection.json may go higher, and never
    beyond the macOS recorded there, which the worker checks before use.
    """
    violations = []
    limits = {}
    for directory in Path(root).rglob(ALTERNATE):
        if directory.is_dir() and not directory.is_symlink():
            try:
                limits[directory] = tuple(json.loads((directory / 'selection.json').read_text())['minimumMacOS'])
            except (OSError, ValueError, KeyError, TypeError):
                violations.append({'path': str(directory), 'error': 'missing or invalid selection.json'})
    for path in sorted(Path(root).rglob('*')):
        if path.is_symlink() or not path.is_file():
            continue
        limit = alternate_limit(path, limits) or minimum
        try:
            found = file_requirement(path)
        except ValueError as error:
            violations.append({'path': str(path), 'error': str(error)})
            continue
        if found and found > limit:
            violations.append({'path': str(path), 'minimumMacOS': '.'.join(map(str, found))})
    if violations:
        raise RuntimeError('Packaged files require a newer macOS than '
                           + '.'.join(map(str, minimum)) + ': ' + json.dumps(violations[:10]))
    return True
