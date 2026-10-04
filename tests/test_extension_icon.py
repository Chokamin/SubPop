"""Verify the actual extension icon alpha and its compiled resource metadata."""
import importlib.util
import json
from pathlib import Path
import plistlib
import struct
import sys
import unittest
import zlib


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("extension_icon", ROOT / "scripts/extension_icon.py")
extension_icon = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extension_icon)


def read_rgba_png(path):
    """Decode native-rendered PNGs independently with the standard library."""
    data = path.read_bytes() if isinstance(path, Path) else path
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise AssertionError("Not a PNG")
    position, compressed = 8, bytearray()
    while position < len(data):
        length = struct.unpack_from(">I", data, position)[0]
        kind = data[position + 4:position + 8]
        payload = data[position + 8:position + 8 + length]
        position += length + 12
        if kind == b"IHDR":
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", payload)
            if (depth, color, compression, filtering, interlace) != (8, 6, 0, 0, 0):
                raise AssertionError("Expected a non-interlaced 8-bit RGBA PNG")
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break
    raw = zlib.decompress(compressed)
    stride, rows, previous = width * 4, [], bytearray(width * 4)
    for row_index in range(height):
        start = row_index * (stride + 1)
        method, row = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for index in range(stride):
            left = row[index - 4] if index >= 4 else 0
            above = previous[index]
            upper_left = previous[index - 4] if index >= 4 else 0
            if method == 1:
                predictor = left
            elif method == 2:
                predictor = above
            elif method == 3:
                predictor = (left + above) // 2
            elif method == 4:
                estimate = left + above - upper_left
                distances = (abs(estimate - left), abs(estimate - above), abs(estimate - upper_left))
                predictor = (left, above, upper_left)[distances.index(min(distances))]
            elif method == 0:
                predictor = 0
            else:
                raise AssertionError(f"Unsupported PNG filter {method}")
            row[index] = (row[index] + predictor) & 255
        rows.append(row)
        previous = row
    return width, height, rows


@unittest.skipUnless(sys.platform == "darwin", "Apple's actool and Cocoa are required")
class ExtensionIconTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # The native build produces these assets once. Inspect that exact output
        # instead of recompiling an unrelated catalog during the test run.
        cls.output = ROOT / ".subloom/build/extension-icon-assets"
        cls.info = plistlib.loads((cls.output / "icon-info.plist").read_bytes())
        cls.icon_set = cls.output / "ExtensionIcon.xcassets/ExtensionIcon.appiconset"

    def test_complete_mac_representations_and_compiled_resources(self):
        contents = json.loads((self.icon_set / "Contents.json").read_text())
        entries = contents["images"]
        self.assertEqual(len(entries), 10)
        self.assertEqual({(item["size"], item["scale"]) for item in entries},
                         {(f"{size}x{size}", f"{scale}x")
                          for size in (16, 32, 128, 256, 512) for scale in (1, 2)})
        for item in entries:
            with self.subTest(size=item["size"], scale=item["scale"]):
                pixels = int(item["size"].split("x")[0]) * int(item["scale"][:-1])
                width, height, _ = read_rgba_png(self.icon_set / item["filename"])
                self.assertEqual((width, height), (pixels, pixels))
                self.assertEqual(item["idiom"], "mac")
        self.assertEqual(self.info, {"CFBundleIconFile": "ExtensionIcon", "CFBundleIconName": "ExtensionIcon"})
        self.assertEqual(plistlib.loads((self.output / "icon-info.plist").read_bytes()), self.info)
        icon = (self.output / "ExtensionIcon.icns").read_bytes()
        self.assertEqual(icon[:4], b"icns")
        self.assertEqual(struct.unpack_from(">I", icon, 4)[0], len(icon))
        self.assertGreater((self.output / "Assets.car").stat().st_size, 0)

    def test_compiled_icns_keeps_alpha_and_three_holes(self):
        icon = (self.output / "ExtensionIcon.icns").read_bytes()
        position, checked = 8, 0
        while position < len(icon):
            length = struct.unpack_from(">I", icon, position + 4)[0]
            self.assertGreaterEqual(length, 8)
            self.assertLessEqual(position + length, len(icon))
            payload = icon[position + 8:position + length]
            position += length
            if payload[:8] != b"\x89PNG\r\n\x1a\n":
                continue  # Older small-icon ARGB encodings coexist with PNGs.
            width, height, rows = read_rgba_png(payload)
            checked += 1
            self.assertEqual(width, height)
            self.assertEqual(rows[0][3], 0)
            for center in (352, 512, 672):
                x, y = int(center * width / 1024), int(508 * height / 1024)
                self.assertEqual(rows[y][4 * x + 3], 0)
            self.assertEqual(rows[int(0.33 * height)][4 * int(0.50 * width) + 3], 255)
        self.assertGreater(checked, 0, "ICNS must include a readable PNG rendition")

    def test_transparent_outside_three_holes_and_opaque_bubble(self):
        for path in sorted(self.icon_set.glob("*.png")):
            with self.subTest(image=path.name):
                width, height, rows = read_rgba_png(path)
                alpha = lambda x, y: rows[y][4 * x + 3]
                sample = lambda x, y: alpha(int(x * width), int(y * height))
                # A full application tile would fill these margins and dots.
                self.assertTrue(all(alpha(x, 0) == alpha(x, height - 1) == 0
                                    for x in range(width)))
                self.assertTrue(all(alpha(0, y) == alpha(width - 1, y) == 0
                                    for y in range(height)))
                for center in (352, 512, 672):
                    # At 16 px, a subpixel circle shares edge coverage with its
                    # center pixel. It must still be at least 75% transparent.
                    self.assertLessEqual(sample(center / 1024, 508 / 1024), 64 if width == 16 else 0)
                # Preserve separate dots even in the smallest toolbar rendition.
                for x in (430, 594):
                    self.assertGreaterEqual(sample(x / 1024, 508 / 1024), 128 if width == 16 else 255)
                self.assertEqual(sample(0.50, 0.33), 255)
                # At least half the canvas remains transparent; alpha also keeps
                # vector antialiasing instead of a hard, jagged threshold.
                values = [row[4 * x + 3] for row in rows for x in range(width)]
                self.assertGreater(values.count(0), width * height // 2)
                self.assertTrue(any(0 < value < 255 for value in values))


if __name__ == "__main__":
    unittest.main()
