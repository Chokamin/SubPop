"""Choose the packaged MLX build for this macOS before mlx is first imported.

site-packages carries MLX built for macOS 15, which runs everywhere the package
installs. A newer build (Metal 4 kernels) sits in mlx-macos26 next to it and is
put first on sys.path only when this Mac meets the macOS its selection.json
records. Development checkouts have no such directory and keep their venv MLX.
"""
import json
import platform
import subprocess
import sys
from .paths import CODE_ROOT

ALTERNATE = CODE_ROOT / 'mlx-macos26'


def macos_version():
    text = platform.mac_ver()[0]
    if not text:
        try:
            text = subprocess.run(['/usr/bin/sw_vers', '-productVersion'], capture_output=True,
                                  text=True, timeout=5).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return None
    try:
        return tuple(int(part) for part in text.split('.')[:2])
    except ValueError:
        return None


def select(alternate=ALTERNATE, current=None):
    """Return which MLX build this process uses: 'newer', 'macos15' or 'environment'."""
    if not (alternate / 'selection.json').is_file():
        return 'environment'
    if 'mlx' in sys.modules:
        # Already imported; a second build cannot be swapped in safely.
        module = sys.modules['mlx']
        locations = [*getattr(module, '__path__', []), getattr(module, '__file__', None) or '']
        return 'newer' if any(str(location).startswith(str(alternate)) for location in locations) else 'macos15'
    try:
        required = tuple(json.loads((alternate / 'selection.json').read_text())['minimumMacOS'])
    except (OSError, ValueError, KeyError, TypeError):
        return 'macos15'
    version = current if current is not None else macos_version()
    if version is None or version < required:
        return 'macos15'
    if str(alternate) not in sys.path:
        sys.path.insert(0, str(alternate))
    return 'newer'
