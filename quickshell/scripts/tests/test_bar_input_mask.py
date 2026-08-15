import pathlib
import unittest


ROOT = pathlib.Path(__file__).parents[2]


class BarInputMaskTests(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_only_visible_center_pills_enter_the_input_region(self):
        source = self.read("desktop/bar/Bar.qml")
        for target in ("ddayW", "mediaW", "clockStatusW", "magicW"):
            self.assertIn(f"item: {target}.visible ? {target} : null", source)

    def test_privacy_buttons_do_not_mask_the_gap_between_them(self):
        bar = self.read("desktop/bar/Bar.qml")
        privacy = self.read("desktop/bar/PrivacyIndicatorsWidget.qml")
        self.assertNotIn("Region { item: privacyW }", bar)
        self.assertIn("item: privacyW.micHitTarget", bar)
        self.assertIn("item: privacyW.cameraHitTarget", bar)
        self.assertIn("readonly property Item micHitTarget", privacy)
        self.assertIn("readonly property Item cameraHitTarget", privacy)

    def test_pill_regions_follow_their_rounded_visual_shape(self):
        source = self.read("desktop/bar/Bar.qml")
        self.assertGreaterEqual(source.count("radius: 17"), 13)


if __name__ == "__main__":
    unittest.main()
