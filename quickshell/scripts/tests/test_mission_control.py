import json
import pathlib
import shutil
import subprocess
import textwrap
import unittest


ROOT = pathlib.Path(__file__).parents[2]
HYPR_WINDOWRULES = ROOT.parent / "hypr" / "configs" / "windowrules.lua"


class MissionControlTests(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_workspace_and_window_focus_commit_before_close(self):
        source = self.read("desktop/missioncontrol/MissionControlController.qml")
        workspace = source[source.index("function requestWorkspace"):
                           source.index("function _onMotionSettled")]
        window = source[source.index("function requestWindow"):
                        source.index("function requestWorkspace")]
        settled = source[source.index("function _onMotionSettled"):
                         source.index("function _gestureStart")]
        self.assertLess(workspace.index("MCService.focusWorkspace(wsId)"),
                        workspace.index('requestHide("workspace")'))
        self.assertLess(window.index("MCService.focusWindow(address)"),
                        window.index('requestHide("window")'))
        self.assertNotIn("focusWorkspace", settled)
        self.assertNotIn("focusWindow", settled)

    def test_dock_stays_above_the_ordered_overlay_regardless_of_pin(self):
        overview = self.read("desktop/missioncontrol/MissionControlWindow.qml")
        dock = self.read("desktop/dock/DockWindow.qml")
        rules = HYPR_WINDOWRULES.read_text(encoding="utf-8")
        rule_start = rules.index('match = { namespace = "qs-missioncontrol" }')
        rule_end = rules.index("\n\n", rule_start)
        mission_control_rule = rules[rule_start:rule_end]
        self.assertIn("visible: true", overview)
        self.assertIn("mask: active ? null : closedRegion", overview)
        self.assertIn("WlrLayershell.layer: WlrLayer.Overlay", overview)
        self.assertNotIn("? WlrLayer.Top", overview)
        self.assertIn("WlrLayershell.layer: WlrLayer.Overlay", dock)
        self.assertIn("order = 10", mission_control_rule)
        self.assertNotIn("onOverviewHereChanged:", dock)

    def test_unpinned_dock_tracks_overview_progress_without_a_tail(self):
        controller = self.read(
            "desktop/missioncontrol/MissionControlController.qml")
        service = self.read("desktop/dock/DockService.qml")
        dock = self.read("desktop/dock/DockWindow.qml")
        self.assertIn("property real overviewProgress: 0", service)
        self.assertIn('property: "overviewProgress"', controller)
        self.assertIn(
            "scope._surfaceVisible ? scope.overviewProgress : 0", controller)
        self.assertIn("property real autoHideMargin:", dock)
        self.assertIn("readonly property real overviewMargin:", dock)
        self.assertIn(
            "(dockVisibleMargin - dockHiddenMargin) * overviewRevealProgress",
            dock)
        self.assertIn(
            "Math.max(autoHideMargin, overviewMargin)", dock)
        self.assertNotIn("Behavior on margins.bottom", dock)
        self.assertNotIn("Behavior on margins.left", dock)
        self.assertNotIn("Behavior on margins.right", dock)

        hidden, visible = -84, 10
        for progress, expected in (
                (0, -84), (0.25, -60.5), (0.5, -37),
                (0.75, -13.5), (1, 10)):
            with self.subTest(progress=progress):
                margin = hidden + (visible - hidden) * progress
                self.assertAlmostEqual(margin, expected)

    def test_exit_keeps_window_previews_fully_opaque(self):
        source = self.read("desktop/missioncontrol/MissionControlWindow.qml")
        content = source[source.index("id: content"):
                         source.index("// Escape to close")]
        self.assertIn("visible: win.active", content)
        self.assertIn("opacity: 1", content)
        self.assertNotIn("overviewProgress", content)
        self.assertNotIn("presentationOpacity", source)
        self.assertIn("property var entryStack", source)
        self.assertGreaterEqual(source.count("Number(win.entryStack[modelData])"), 2)

    def test_exit_hides_real_windows_until_the_exact_endpoint(self):
        controller = self.read("desktop/missioncontrol/MissionControlController.qml")
        window = self.read("desktop/missioncontrol/MissionControlWindow.qml")
        hide = controller[controller.index("function requestHide"):
                          controller.index("function requestToggle")]
        settled = controller[controller.index("function _onMotionSettled"):
                             controller.index("function _gestureStart")]
        gesture = controller[controller.index("function _gestureUpdate"):
                             controller.index("function _project")]
        wallpaper = window[window.index("id: wallpaper"):
                           window.index("id: content")]
        self.assertIn("scope._holdBackdrop = true", hide)
        self.assertIn("scope._holdBackdrop = false", settled)
        self.assertIn("progressDelta < 0", gesture)
        self.assertIn("scope._holdBackdrop = true", gesture)
        self.assertIn("win.holdBackdrop ? 1 : win.overviewProgress", wallpaper)
        self.assertIn("win.holdBackdrop && !wallpaper.imageReady", wallpaper)
        self.assertIn("opacity: 0.12 * win.overviewProgress", wallpaper)

    def test_workspace_strip_is_structurally_opaque(self):
        window = self.read("desktop/missioncontrol/MissionControlWindow.qml")
        theme = self.read("desktop/missioncontrol/ThemeService.qml")
        self.assertIn("color: ThemeService.surfaceOpaque", window)
        self.assertIn("readonly property color surfaceOpaque", theme)

    def test_workspace_strip_edge_is_physical_pixel_aligned(self):
        window = self.read("desktop/missioncontrol/MissionControlWindow.qml")
        self.assertIn("Math.round(stripExtent * deviceScale) / deviceScale", window)
        self.assertIn("Math.round(win.stripSlide * deviceScale) / deviceScale", window)
        self.assertIn("topBand.renderedStripExtent + topBand.renderedStripSlide", window)
        self.assertIn("border.width: 0", window)
        self.assertIn("* topBand.physicalPixel", window)
        self.assertIn("antialiasing: false", window)
        for scale in (1, 1.25, 1.5, 1.75, 2):
            extent = round(157 * scale) / scale
            self.assertAlmostEqual(extent * scale, round(extent * scale))
            self.assertAlmostEqual((1 / scale) * scale, 1)

    def test_first_frame_is_transparent_and_strip_endpoint_is_fixed(self):
        window = self.read("desktop/missioncontrol/MissionControlWindow.qml")
        thumb = self.read("desktop/missioncontrol/WindowThumb.qml")
        self.assertIn("readonly property real stripHiddenY: -win.stripHeight", window)
        self.assertIn("placeholderVisible: false", window)
        self.assertIn("!capture.hasContent", thumb)
        self.assertIn("capture.captureFrame()", thumb)

    def test_motion_is_interruptible_bounded_and_velocity_aware(self):
        controller = self.read("desktop/missioncontrol/MissionControlController.qml")
        motion = self.read("desktop/missioncontrol/MotionProgress.qml")
        self.assertIn("MotionProgress {", controller)
        self.assertIn("motion.track", controller)
        self.assertIn("motion.settleTo", controller)
        self.assertIn("finishTime", controller)
        self.assertIn("position <= 0", motion)
        self.assertIn("position >= 1", motion)

    @unittest.skipUnless(shutil.which("node"), "node is needed to execute the QML JS layout")
    def test_spatial_layout_is_bounded_and_non_overlapping(self):
        layout_path = ROOT / "desktop/missioncontrol/SpatialLayout.js"
        script = textwrap.dedent(
            f"""
            const fs = require('fs');
            const vm = require('vm');
            let source = fs.readFileSync({json.dumps(str(layout_path))}, 'utf8')
                .replace(/^\\.pragma library\\s*/, '');
            const context = {{}};
            vm.createContext(context);
            vm.runInContext(source, context);
            const monitor = {{x: 0, y: 0, width: 1920, height: 1200, scale: 1}};
            const windows = [
                {{address:'a', at:[80,80], size:[920,680]}},
                {{address:'b', at:[610,150], size:[1050,760]}},
                {{address:'c', at:[120,650], size:[760,440]}},
                {{address:'d', at:[1050,610], size:[720,500]}},
                {{address:'e', at:[780,420], size:[560,720]}}
            ];
            process.stdout.write(JSON.stringify(
                context.pack(windows.map(w => w.address), windows, monitor,
                    1680, 870, 22)));
            """
        )
        result = subprocess.run(
            ["node", "-e", script], check=True, capture_output=True, text=True
        )
        boxes = json.loads(result.stdout)
        self.assertEqual(set(boxes), {"a", "b", "c", "d", "e"})
        for address, box in boxes.items():
            with self.subTest(address=address):
                self.assertGreaterEqual(box["x"], 0)
                self.assertGreaterEqual(box["y"], 0)
                self.assertLessEqual(box["x"] + box["width"], 1680.5)
                self.assertLessEqual(box["y"] + box["height"], 870.5)
        values = list(boxes.values())
        for i, first in enumerate(values):
            for second in values[i + 1:]:
                separated = (
                    first["x"] + first["width"] + 21 <= second["x"]
                    or second["x"] + second["width"] + 21 <= first["x"]
                    or first["y"] + first["height"] + 21 <= second["y"]
                    or second["y"] + second["height"] + 21 <= first["y"]
                )
                self.assertTrue(separated, (first, second))


if __name__ == "__main__":
    unittest.main()
