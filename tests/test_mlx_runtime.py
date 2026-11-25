"""Packaged MLX must match the package's minimum macOS (Metal 4.0 failed on macOS 15)."""
import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

from scripts import mlx_runtime


def dylib(directory, name, minimum):
    source = Path(directory) / 'empty.c'
    source.write_text('int subpop_probe(void){return 0;}\n')
    output = Path(directory) / name
    subprocess.run(['xcrun', 'clang', '-dynamiclib', '-arch', 'arm64', f'-mmacosx-version-min={minimum}',
                    str(source), '-o', str(output)], check=True, capture_output=True)
    return output


def wheel(directory, name, members):
    path = Path(directory) / name
    with zipfile.ZipFile(path, 'w') as archive:
        for member, data in members.items():
            info = zipfile.ZipInfo(member)
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    data = path.read_bytes()
    return path, dict(file=name, size=len(data), sha256=hashlib.sha256(data).hexdigest(), url='https://invalid.test/')


class MinimumMacOSCheckTests(unittest.TestCase):
    def test_macho_minimum_reads_build_version_not_linker_version(self):
        with tempfile.TemporaryDirectory() as temp:
            self.assertEqual(mlx_runtime.macho_minimum(dylib(temp, 'old.dylib', '13.0')), (13, 0))
            self.assertEqual(mlx_runtime.macho_minimum(dylib(temp, 'new.dylib', '26.2')), (26, 2))
            text = Path(temp) / 'plain.txt'
            text.write_text('not a binary')
            self.assertIsNone(mlx_runtime.macho_minimum(text))

    def test_binary_newer_than_package_minimum_is_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            dylib(temp, 'ok.dylib', '15.0')
            self.assertTrue(mlx_runtime.check_minimum(temp))
            dylib(temp, 'too-new.dylib', '26.0')
            with self.assertRaisesRegex(RuntimeError, 'too-new.dylib'):
                mlx_runtime.check_minimum(temp)

    def test_metal_library_target_must_not_exceed_package_minimum(self):
        for payload, accepted in ((b'air64_v27-apple-macosx15.0.0', True),
                                  (b'air64_v28-apple-macosx26.2.0', False),
                                  (b'no target recorded', False)):
            with self.subTest(payload=payload), tempfile.TemporaryDirectory() as temp:
                (Path(temp) / 'mlx.metallib').write_bytes(b'MTLB' + payload)
                if accepted:
                    self.assertTrue(mlx_runtime.check_minimum(temp))
                else:
                    with self.assertRaisesRegex(RuntimeError, 'metallib'):
                        mlx_runtime.check_minimum(temp)


class WheelInstallTests(unittest.TestCase):
    def site(self, temp):
        site = Path(temp) / 'site-packages'
        (site / 'mlx/lib').mkdir(parents=True)
        (site / 'mlx/lib/mlx.metallib').write_bytes(b'apple-macosx26.2.0')
        (site / 'mlx/stale.py').write_text('old')
        for name in ('mlx', 'mlx_metal'):
            (site / f'{name}-{mlx_runtime.VERSION}.dist-info').mkdir()
            (site / f'{name}-{mlx_runtime.VERSION}.dist-info/WHEEL').write_text('Tag: macosx_26_0')
        (site / 'other').mkdir()
        return site

    def test_install_replaces_only_mlx_with_verified_wheels(self):
        with tempfile.TemporaryDirectory() as temp:
            site = self.site(temp)
            cache = Path(temp) / 'cache'
            cache.mkdir()
            version = mlx_runtime.VERSION
            _, core = wheel(cache, 'core.whl', {'mlx/core.py': 'new', f'mlx-{version}.dist-info/WHEEL': 'Tag: macosx_15_0'})
            _, metal = wheel(cache, 'metal.whl', {'mlx/lib/mlx.metallib': 'apple-macosx15.0.0',
                                                  f'mlx_metal-{version}.dist-info/WHEEL': 'Tag: macosx_15_0'})
            mlx_runtime.install(site, (dict(core, distribution='mlx'), dict(metal, distribution='mlx_metal')), cache)
            self.assertFalse((site / 'mlx/stale.py').exists())
            self.assertEqual((site / 'mlx/core.py').read_text(), 'new')
            self.assertEqual((site / 'mlx/lib/mlx.metallib').read_text(), 'apple-macosx15.0.0')
            self.assertIn('macosx_15_0', (site / f'mlx_metal-{version}.dist-info/WHEEL').read_text())
            self.assertTrue((site / 'other').is_dir())

    def test_checksum_mismatch_and_unsafe_members_are_refused_before_changes(self):
        version = mlx_runtime.VERSION
        for members in ({'mlx/core.py': 'x'}, {'../escape.py': 'x'}, {'other/file.py': 'x'}):
            with self.subTest(members=members), tempfile.TemporaryDirectory() as temp:
                site = self.site(temp)
                cache = Path(temp) / 'cache'
                cache.mkdir()
                _, entry = wheel(cache, 'core.whl', members)
                if members == {'mlx/core.py': 'x'}:
                    entry['sha256'] = '0' * 64
                with self.assertRaises(ValueError):
                    mlx_runtime.install(site, (dict(entry, distribution='mlx'),), cache)
                self.assertEqual((site / 'mlx/stale.py').read_text(), 'old')
                self.assertTrue((site / f'mlx-{version}.dist-info/WHEEL').is_file())
                self.assertFalse((Path(temp) / 'escape.py').exists())

    def test_unlocked_staged_version_is_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            site = Path(temp)
            with self.assertRaisesRegex(ValueError, 'locked'):
                mlx_runtime.install(site, mlx_runtime.WHEELS, Path(temp) / 'cache')

    def test_pinned_official_wheels_meet_minimum_when_cached(self):
        paths = [mlx_runtime.CACHE / item['file'] for item in mlx_runtime.WHEELS]
        if not all(path.is_file() for path in paths):
            self.skipTest('Pinned MLX wheels are fetched by package_release.py; none cached')
        with tempfile.TemporaryDirectory() as temp:
            site = self.site(temp)
            mlx_runtime.install(site)
            self.assertTrue(mlx_runtime.check_minimum(site))
