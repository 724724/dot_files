import pathlib
import unittest


ROOT = pathlib.Path(__file__).parents[2]


class ResourceGuardTests(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_battery_uses_upower_events_and_restores_saved_limit(self):
        source = self.read("desktop/nc/BatteryService.qml")
        self.assertIn("import Quickshell.Services.UPower", source)
        self.assertNotIn("\n        interval: 3000\n", source)
        self.assertIn("root._restorePending = true", source)
        self.assertIn("root.setChargeLimit(target)", source)

    def test_keyboard_backlight_poll_is_hardware_gated(self):
        source = self.read("desktop/osd/OsdService.qml")
        self.assertIn('property string _kbdPath: ""', source)
        self.assertIn('running: root._kbdPath !== ""', source)
        self.assertNotIn("interval: 250", source)

    def test_dock_keeps_render_headroom_separate_from_hit_band(self):
        source = self.read("desktop/dock/DockWindow.qml")
        self.assertIn("readonly property int dockIdleH: 120", source)
        self.assertIn("readonly property int dockTriggerH: 88", source)
        self.assertIn("? panelHeight : dockIdleH", source)

    def test_mission_control_keeps_dock_continuously_mapped(self):
        dock = self.read("desktop/dock/DockWindow.qml")
        overview = self.read("desktop/missioncontrol/MissionControlWindow.qml")
        self.assertNotIn("onOverviewHereChanged:", dock)
        self.assertIn("visible: true", overview)
        self.assertIn("mask: active ? null : closedRegion", overview)
        self.assertIn("WlrLayershell.layer: WlrLayer.Overlay", overview)
        self.assertNotIn("? WlrLayer.Top", overview)

    def test_long_lived_watchers_die_with_quickshell(self):
        for relative in (
            "desktop/bar/MediaService.qml",
            "desktop/bar/NetworkService.qml",
            "desktop/bar/PrivacyService.qml",
            "desktop/nc/AudioService.qml",
            "desktop/nc/ThemeService.qml",
            "desktop/missioncontrol/WallpaperService.qml",
        ):
            with self.subTest(relative=relative):
                self.assertIn("--pdeathsig", self.read(relative))


if __name__ == "__main__":
    unittest.main()
