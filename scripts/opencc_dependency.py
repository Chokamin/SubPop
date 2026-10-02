"""Build pinned OpenCC for offline Chinese text conversion; cache stays outside Git.

The application statically links OpenCC/Marisa and bundles only the standard
s2t/t2s configs and their dictionaries. There is no runtime download or lookup
in Homebrew/system dictionary directories.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VERSION = '1.4.2'
SHA256 = 'a1862de88b38bb825ce73b4852be4159668b83a1a0821249c749769df79b5018'
SOURCE_URL = f'https://github.com/BYVoid/OpenCC/releases/download/ver.{VERSION}/opencc-{VERSION}-opencc-src.tar.xz'
CACHE = ROOT / '.subloom/dependencies'
SOURCE = CACHE / f'opencc-{VERSION}-opencc-src'
BUILD = CACHE / f'opencc-{VERSION}-build-arm64'
INSTALL = CACHE / f'opencc-{VERSION}-install-arm64'
DATA = CACHE / f'opencc-{VERSION}-resources/OpenCC'
CONFIGS = ('s2t.json', 't2s.json')
LICENSES = ('OpenCC.txt', 'OpenCC-Marisa.txt', 'OpenCC-Darts.txt', 'OpenCC-RapidJSON.txt', 'OpenCC-NOTICE.txt')


def checksum(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def dictionary_names(value):
    """Collect the fixed config's dictionary references without changing its rules."""
    if isinstance(value, dict):
        if value.get('type') == 'ocd2' and 'file' in value:
            name = value['file']
            if not isinstance(name, str) or Path(name).name != name or not name.endswith('.ocd2'):
                raise ValueError('Invalid upstream OpenCC dictionary reference')
            yield name
        for child in value.values():
            yield from dictionary_names(child)
    elif isinstance(value, list):
        for child in value:
            yield from dictionary_names(child)


def prepare():
    cmake = shutil.which('cmake')
    if not cmake:
        raise RuntimeError('CMake is required to build the pinned offline OpenCC dependency')
    CACHE.mkdir(parents=True, exist_ok=True)
    archive = CACHE / f'opencc-{VERSION}-opencc-src.tar.xz'
    if not archive.exists():
        partial = archive.with_suffix('.partial')
        try:
            urllib.request.urlretrieve(SOURCE_URL, partial)
            if checksum(partial) != SHA256:
                raise ValueError('OpenCC source checksum mismatch')
            partial.replace(archive)
        finally:
            partial.unlink(missing_ok=True)
    if checksum(archive) != SHA256:
        raise ValueError('OpenCC source checksum mismatch')
    # Re-extract the verified release on every build; local cache edits must not
    # silently become shipped dependency code. Tar's data filter rejects unsafe
    # paths, and the release may only write its one expected source directory.
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            if Path(member.name).parts[0] != SOURCE.name:
                raise ValueError('Unexpected OpenCC archive root')
        tar.extractall(CACHE, filter='data')
    subprocess.run([
        cmake, '-S', str(SOURCE), '-B', str(BUILD),
        '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_INSTALL_PREFIX=/SubPop-OpenCC',
        f'-DCMAKE_C_FLAGS=-ffile-prefix-map={ROOT}=.',
        f'-DCMAKE_CXX_FLAGS=-ffile-prefix-map={ROOT}=.',
        '-DCMAKE_OSX_ARCHITECTURES=arm64', '-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0',
        '-DCMAKE_DISABLE_FIND_PACKAGE_Git=TRUE',
        '-DBUILD_SHARED_LIBS=OFF', '-DOPENCC_ENABLE_INSTALL=ON',
        '-DENABLE_GTEST=OFF', '-DENABLE_BENCHMARK=OFF', '-DBUILD_PYTHON=OFF',
        '-DBUILD_OPENCC_JIEBA_PLUGIN=OFF', '-DUSE_SYSTEM_MARISA=OFF',
        '-DUSE_SYSTEM_DARTS=OFF', '-DUSE_SYSTEM_RAPIDJSON=OFF', '-DUSE_SYSTEM_TCLAP=OFF',
        '-DOPENCC_DICT_FORMAT=ocd2', f'-DPython3_EXECUTABLE={sys.executable}',
    ], check=True)
    # Disable Git discovery above: a release extracted inside SubPop's Git tree
    # otherwise inherits SubPop's version instead of OpenCC's release version.
    subprocess.run([cmake, '--build', str(BUILD), '--parallel', '4'], check=True)
    # A neutral compile-time prefix prevents private workstation paths from
    # entering the static library. Install into the cache via CMake's explicit
    # staging prefix; native callers require every dictionary in their bundle.
    subprocess.run([cmake, '--install', str(BUILD), '--prefix', str(INSTALL)], check=True)
    DATA.mkdir(parents=True, exist_ok=True)
    names = set()
    for config in CONFIGS:
        source = SOURCE / 'data/config' / config
        names.update(dictionary_names(json.loads(source.read_text(encoding='utf-8'))))
        shutil.copy2(source, DATA / config)
    for name in sorted(names):
        shutil.copy2(BUILD / 'data' / name, DATA / name)
    for name in LICENSES:
        shutil.copy2(ROOT / 'licenses' / name, DATA / name)
    expected = set(CONFIGS) | names | set(LICENSES) | {'provenance.json'}
    for path in DATA.iterdir():
        if path.name not in expected:
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink()
    manifest = {
        'name': 'OpenCC', 'version': VERSION, 'source_url': SOURCE_URL,
        'source_sha256': SHA256, 'architecture': 'arm64',
        'configuration': 'standard s2t/t2s; no regional vocabulary conversion',
        'files': {name: checksum(DATA / name) for name in sorted(expected - {'provenance.json'})},
    }
    (DATA / 'provenance.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    libraries = [INSTALL / 'lib/libopencc.a', INSTALL / 'lib/libmarisa.a']
    for path in libraries + [INSTALL / 'include/opencc/opencc.h']:
        if not path.is_file():
            raise RuntimeError(f'OpenCC build did not produce {path.name}')
    return {'include': INSTALL / 'include/opencc', 'libraries': libraries, 'data': DATA}


if __name__ == '__main__':
    result = prepare()
    print(json.dumps({key: [str(item) for item in value] if isinstance(value, list) else str(value) for key, value in result.items()}, indent=2))
