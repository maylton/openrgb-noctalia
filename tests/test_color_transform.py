from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "openrgb-noctalia" / "apply_color.py"
SPEC = importlib.util.spec_from_file_location("apply_color", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ColorTransformTests(unittest.TestCase):
    def transform(self, color: str, enabled: bool = True):
        return MODULE.transform_color(
            color,
            pastel_correction=enabled,
            saturation_threshold=0.45,
            brightness_threshold=0.85,
            target_saturation=0.65,
            target_brightness=0.85,
        )

    def test_known_pastel_blue_is_corrected(self):
        output, corrected, *_ = self.transform("99B6F2")
        self.assertTrue(corrected)
        self.assertEqual(output, "4C7AD9")

    def test_saturated_blue_is_preserved(self):
        output, corrected, *_ = self.transform("39BAE6")
        self.assertFalse(corrected)
        self.assertEqual(output, "39BAE6")

    def test_dark_color_is_preserved(self):
        output, corrected, *_ = self.transform("334155")
        self.assertFalse(corrected)
        self.assertEqual(output, "334155")

    def test_white_is_not_hue_shifted(self):
        output, corrected, *_ = self.transform("FFFFFF")
        self.assertFalse(corrected)
        self.assertEqual(output, "FFFFFF")

    def test_correction_can_be_disabled(self):
        output, corrected, *_ = self.transform("99B6F2", enabled=False)
        self.assertFalse(corrected)
        self.assertEqual(output, "99B6F2")

    def test_invalid_color_is_rejected(self):
        with self.assertRaises(ValueError):
            self.transform("XYZ")


if __name__ == "__main__":
    unittest.main()
