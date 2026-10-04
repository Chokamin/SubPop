"""Native resource checks; these do not replace Final Cut Pro visual acceptance."""
import hashlib
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / ".subloom/build/extension-brand-assets"


class ExtensionBrandIconTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = json.loads((OUTPUT / "conversion-report.json").read_text())

    def test_complete_canonical_artwork_is_the_only_source(self):
        source = ROOT / ".subloom/build/icon-assets/SubPop.icns"
        self.assertEqual(self.report["inputIcnsSHA256"],
                         hashlib.sha256(source.read_bytes()).hexdigest())
        self.assertFalse(self.report["artworkRedrawn"])
        self.assertTrue(self.report["uniformArtworkSource"])
        rasters = self.report["rasterRepresentations"]
        self.assertEqual({row["pixels"] for row in rasters},
                         {16, 32, 64, 128, 256, 512, 1024})
        masters = {(row["sourceIndex"], row["sourceWidth"], row["sourceHeight"])
                   for row in rasters}
        self.assertEqual(len(masters), 1)
        self.assertGreaterEqual(next(iter(masters))[1], 256)

    def test_square_base_and_three_dots_survive_the_bubble_cutout(self):
        # Both actual toolbar-sized and large brand representations must retain
        # the base. A bubble-only replacement would fail this check.
        for row in self.report["rasterRepresentations"]:
            if row["pixels"] < 32:
                continue
            with self.subTest(pixels=row["pixels"]):
                actual = row["landmarks"]
                self.assertGreaterEqual(actual["base"]["alpha"], 250)
                self.assertLessEqual(actual["bubble"]["alpha"], 10)
                self.assertEqual(len(actual["dots"]), 3)
                for dot in actual["dots"]:
                    self.assertGreaterEqual(dot["alpha"], 240)
                self.assertEqual(actual["exterior"]["alpha"], 0)
                self.assertGreater(row["partialAlphaPixels"], 0)
                self.assertEqual(actual["base"]["rgba"][:3], [247, 244, 235])

    def test_catalog_contains_all_ten_standard_representations(self):
        icon_set = OUTPUT / "SubPop.xcassets/SubPop.appiconset"
        definition = json.loads((icon_set / "Contents.json").read_text())
        images = definition["images"]
        self.assertEqual({(image["size"], image["scale"]) for image in images},
                         {(f"{size}x{size}", f"{scale}x")
                          for size in (16, 32, 128, 256, 512) for scale in (1, 2)})
        self.assertEqual(len(images), 10)
        for image in images:
            self.assertTrue((icon_set / image["filename"]).is_file())
        entries = json.loads(subprocess.check_output(
            ["xcrun", "assetutil", "--info", str(OUTPUT / "Assets.car")], text=True))
        self.assertIn("SubPop", {entry.get("Name") for entry in entries})
        self.assertTrue((OUTPUT / "SubPop.icns").is_file())


if __name__ == "__main__":
    unittest.main()
