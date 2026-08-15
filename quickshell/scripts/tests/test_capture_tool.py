#!/usr/bin/env python3

import os
import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class CaptureToolGuards(unittest.TestCase):
    def test_backend_is_executable_and_parses(self):
        backend = ROOT / "scripts" / "capture-tool.sh"
        self.assertTrue(os.access(backend, os.X_OK))
        subprocess.run(["bash", "-n", str(backend)], check=True)

    def test_backend_keeps_modes_and_arguments_bounded(self):
        text = (ROOT / "scripts" / "capture-tool.sh").read_text()
        self.assertIn("screen|window|portion", text)
        self.assertIn("valid_output", text)
        self.assertIn('recorder_args=("-w" "$record_region"', text)
        self.assertIn("printf -v record_region '%sx%s%+d%+d'", text)
        self.assertIn('"-w" "$OUTPUT_NAME"', text)
        self.assertNotIn('"-w" "region" "-region"', text)
        # Shell eval remains forbidden. Hyprland's typed Lua dispatcher is
        # invoked through `hyprctl eval` only after the address is hex-validated.
        self.assertNotIn("\neval ", text)
        self.assertIn("/usr/bin/hyprctl eval", text)
        self.assertNotIn("bash -c", text)

    def test_recorder_check_rejects_a_binary_with_missing_libraries(self):
        backend = ROOT / "scripts" / "capture-tool.sh"
        text = backend.read_text()
        result = subprocess.run(
            [str(backend), "check"], check=True, text=True, capture_output=True
        )
        state = json.loads(result.stdout)
        self.assertIn("recorder", state)
        self.assertIn("problem", state)
        self.assertIn('/usr/bin/ldd "$RECORDER_PATH"', text)
        self.assertIn('RECORDER_PROBLEM="missing-shared-library"', text)
        self.assertIn("sudo pacman -Syu", text)
        self.assertNotIn("libavcodec.so.63", text)

    def test_window_shadow_is_not_applied_to_regular_regions(self):
        text = (ROOT / "scripts" / "capture-tool.sh").read_text()
        shadow = text.index("-shadow 48x18+0+12")
        window_guard = text.rfind('if [[ "$MODE" == "window" ]]', 0, shadow)
        next_else = text.index("else", window_guard)
        self.assertLess(window_guard, shadow)
        self.assertLess(shadow, next_else)

    def test_toolbar_exposes_all_six_apple_style_modes(self):
        text = (ROOT / "desktop" / "capture" / "CaptureToolbarWindow.qml").read_text()
        for mode in (
            "screen",
            "window",
            "portion",
            "record-screen",
            "record-window",
            "record-portion",
        ):
            self.assertIn(f'modeValue: "{mode}"', text)

    def test_options_use_bounded_file_destinations_and_native_folder_picker(self):
        toolbar = (ROOT / "desktop" / "capture" / "CaptureToolbarWindow.qml").read_text()
        service = (ROOT / "desktop" / "capture" / "CaptureService.qml").read_text()
        backend = (ROOT / "scripts" / "capture-tool.sh").read_text()
        picker = (ROOT / "desktop" / "capture" / "CaptureFolderPicker.qml").read_text()

        for label in ("Desktop", "Documents", "Clipboard", "Other Locations…"):
            self.assertIn(f'label: "{label}"', toolbar)
        self.assertIn("CaptureFolderPicker", toolbar)
        self.assertIn("FolderListModel", picker)
        self.assertIn("Clock.ClockKineticList", picker)
        self.assertNotIn("FolderDialog", toolbar)
        self.assertNotIn("id: optionsShadow", toolbar)
        self.assertNotIn('["zenity"', toolbar + picker)
        self.assertNotIn("Process {", picker)
        self.assertIn("setCustomDirectory", service)
        self.assertIn("desktop|documents|clipboard|custom", backend)
        self.assertNotIn('{ value: "media"', toolbar)

    def test_every_screenshot_destination_copies_to_clipboard(self):
        text = (ROOT / "scripts" / "capture-tool.sh").read_text()
        clipboard_only = text.index('if [[ "$SAVE_MODE" == "clipboard" ]]')
        saved_copy = text.index("# Every file-backed screenshot is also copied")
        final_move = text.index('/usr/bin/mv -f -- "$final_temp" "$final_path"')
        self.assertLess(clipboard_only, saved_copy)
        self.assertLess(saved_copy, final_move)

    def test_portion_handles_and_window_hover_use_direct_manipulation(self):
        overlay = (ROOT / "desktop" / "capture" / "CaptureOverlayWindow.qml").read_text()
        self.assertIn("width: 36", overlay)
        self.assertIn("portionHandleRadius: 28", overlay)
        self.assertIn("function _beginPortionGesture", overlay)
        self.assertIn("function _updatePortionGesture", overlay)
        self.assertIn("function _finishPortionGesture", overlay)
        self.assertIn("z: 100", overlay)
        self.assertNotIn("id: cornerArea", overlay)
        self.assertNotIn("id: moveArea", overlay)
        self.assertIn("Qt.BlankCursor", overlay)
        self.assertIn("Qt.rgba(0.03, 0.49, 0.94, 0.24)", overlay)
        select_call = overlay.index("CaptureService.selectWindow(overlay.modelData, win)")
        trigger_call = overlay.index("CaptureService.trigger()", select_call)
        self.assertLess(select_call, trigger_call)

    def test_window_picker_has_a_dedicated_visible_workspace_snapshot(self):
        service = (ROOT / "desktop" / "capture" / "CaptureService.qml").read_text()
        overlay = (ROOT / "desktop" / "capture" / "CaptureOverlayWindow.qml").read_text()
        backend = ROOT / "scripts" / "capture-windows.sh"
        script = backend.read_text()

        self.assertTrue(os.access(backend, os.X_OK))
        subprocess.run(["bash", "-n", str(backend)], check=True)
        self.assertIn("windowClients", service)
        self.assertIn("CaptureService.windowClients", overlay)
        self.assertIn("activeWorkspace.id", script)
        self.assertIn("specialWorkspace.id", script)
        self.assertNotIn("Dock.DockService", overlay)

    def test_capture_overlay_stays_mapped_and_embeds_toolbar_in_one_surface(self):
        overlay = (ROOT / "desktop" / "capture" / "CaptureOverlayWindow.qml").read_text()
        toolbar = (ROOT / "desktop" / "capture" / "CaptureToolbarWindow.qml").read_text()
        controller = (ROOT / "desktop" / "capture" / "CaptureController.qml").read_text()
        self.assertIn("visible: true", overlay)
        self.assertIn("mask: active ? activeRegion : emptyRegion", overlay)
        self.assertIn("id: activeRegion", overlay)
        self.assertIn("width: overlay.width", overlay)
        self.assertIn("height: overlay.height", overlay)
        self.assertNotIn("item: targetArea", overlay)
        self.assertIn("WlrLayershell.layer: WlrLayer.Overlay", overlay)
        self.assertIn("CaptureToolbarWindow {", overlay)
        self.assertIn("selectedScreen: overlay.selectedScreen", overlay)
        self.assertIn("z: 1000", overlay)
        self.assertNotIn("CaptureToolbarWindow {}", controller)
        self.assertIn("Item {", toolbar)
        self.assertNotIn("PanelWindow {", toolbar)
        self.assertNotIn("WlrLayershell", toolbar)

    def test_selection_is_native_qml_and_recording_indicator_precedes_magic(self):
        overlay = (ROOT / "desktop" / "capture" / "CaptureOverlayWindow.qml").read_text()
        self.assertIn("localSelectionWidth", overlay)
        self.assertIn("CaptureService.windowClients", overlay)
        self.assertNotIn("slurp", overlay)

        bar = (ROOT / "desktop" / "bar" / "Bar.qml").read_text()
        self.assertLess(bar.index("RecordingIndicator"), bar.index("MagicWidget"))

    def test_all_screenshot_shortcuts_use_the_quickshell_capture_service(self):
        bindings = Path.home() / ".config" / "hypr" / "configs" / "keybindings.lua"
        if not bindings.exists():
            self.skipTest("Hyprland dotfiles are not present")
        text = bindings.read_text()
        expected = {
            "SHIFT + 3": 'hl.dsp.global("capture:screen")',
            "SHIFT + 4": 'hl.dsp.global("capture:portion")',
            "SHIFT + 5": 'hl.dsp.global("capture:toggle")',
        }
        for key, dispatcher in expected.items():
            line = next(line for line in text.splitlines() if key in line)
            self.assertIn(dispatcher, line)
            self.assertNotIn("shot.sh", line)

        service = (ROOT / "desktop" / "capture" / "CaptureService.qml").read_text()
        self.assertIn('name: "screen"', service)
        self.assertIn('name: "portion"', service)
        self.assertIn('root.pendingCaptureMode = "screen"', service)

    def test_toolbar_is_compact_draggable_and_persists_its_position(self):
        toolbar = (ROOT / "desktop" / "capture" / "CaptureToolbarWindow.qml").read_text()
        service = (ROOT / "desktop" / "capture" / "CaptureService.qml").read_text()

        self.assertIn("Math.min(660", toolbar)
        self.assertIn("id: toolbarDragHandler", toolbar)
        self.assertIn("property bool dragStarted: false", toolbar)
        self.assertIn("else if (dragStarted)", toolbar)
        self.assertIn("target: toolbarCard", toolbar)
        self.assertIn("&& !toolbarCard.controlHovered", toolbar)
        self.assertNotIn("preventStealing: true", toolbar)
        overlay = (ROOT / "desktop" / "capture" / "CaptureOverlayWindow.qml").read_text()
        self.assertIn("id: captureToolbar", overlay)
        self.assertNotIn("id: remapForInput", toolbar)
        self.assertNotIn("surfaceVisible", toolbar)
        self.assertNotIn("id: dragHandle", toolbar)
        self.assertNotIn("Soft, layered shadow", toolbar)
        self.assertIn("CaptureService.setToolbarPosition", toolbar)
        self.assertIn("toolbarPositionStored", service)
        self.assertIn("toolbarPosition:", service)

    def test_portion_history_is_independent_persistent_and_shared_by_4_and_5(self):
        service = (ROOT / "desktop" / "capture" / "CaptureService.qml").read_text()
        overlay = (ROOT / "desktop" / "capture" / "CaptureOverlayWindow.qml").read_text()
        self.assertIn("property var portionSelections", service)
        self.assertIn("function portionSelectionForScreen", service)
        self.assertIn("portionSelections: root.rememberSelection", service)
        self.assertIn("CaptureService.portionSelectionForScreen", overlay)
        self.assertIn("CaptureService.updateSelection", overlay)
        self.assertIn('name: "portion"', service)
        self.assertIn("function showPortion()", service)

    def test_dock_dims_and_releases_input_while_capture_is_active(self):
        dock = (ROOT / "desktop" / "dock" / "DockWindow.qml").read_text()
        self.assertIn('import "../capture" as Capture', dock)
        self.assertIn("Capture.CaptureService.overlayActive ? captureInputRegion", dock)
        self.assertIn("opacity: Capture.CaptureService.overlayActive ? 0.34 : 0", dock)

    def test_quick_portion_hides_toolbar_and_uses_camera_click_to_capture(self):
        service = (ROOT / "desktop" / "capture" / "CaptureService.qml").read_text()
        overlay = (ROOT / "desktop" / "capture" / "CaptureOverlayWindow.qml").read_text()

        self.assertIn("function showPortion()", service)
        self.assertIn("root.toolbarVisible = false", service)
        self.assertIn("quickPortionMode", overlay)
        self.assertIn('portionGesture = quickPortionMode ? "capture" : "move"', overlay)
        self.assertIn("return quickPortionMode ? Qt.BlankCursor", overlay)
        capture_gesture = overlay.index('if (portionGesture === "capture")')
        trigger = overlay.index("CaptureService.trigger()", capture_gesture)
        self.assertLess(capture_gesture, trigger)

    def test_window_capture_raises_only_the_selected_window_and_keeps_it_focused(self):
        service = (ROOT / "desktop" / "capture" / "CaptureService.qml").read_text()
        backend = (ROOT / "scripts" / "capture-tool.sh").read_text()
        overlay = (ROOT / "desktop" / "capture" / "CaptureOverlayWindow.qml").read_text()

        self.assertIn('resolvedMode === "window" ? root.selectedWindowAddress', service)
        self.assertIn('WINDOW_ADDRESS="${13:-}"', backend)
        self.assertIn("valid_window_address", backend)
        self.assertIn('hyprctl eval', backend)
        self.assertIn('hl.dsp.window.bring_to_top', backend)
        self.assertNotIn("restore_window_focus", backend)
        self.assertNotIn("id: windowTitle", overlay)

        rejected = subprocess.run(
            [
                str(ROOT / "scripts" / "capture-tool.sh"),
                "screenshot", "window", "eDP-1", "0", "0", "100", "100",
                "0", "clipboard", "0", "0", "", "not-an-address",
            ],
            text=True,
            capture_output=True,
        )
        self.assertEqual(rejected.returncode, 2)
        self.assertIn("invalid window address", rejected.stderr)

    def test_toolbar_mode_survives_quick_portion_and_reload(self):
        service = (ROOT / "desktop" / "capture" / "CaptureService.qml").read_text()
        self.assertIn('property string toolbarMode: "window"', service)
        self.assertIn("root.toolbarMode = nextMode", service)
        self.assertIn("root.mode = root.toolbarMode", service)
        self.assertIn("mode: root.toolbarMode", service)
        self.assertIn("root.toolbarMode = data.mode", service)

    def test_escape_is_owned_by_the_selected_capture_overlay(self):
        overlay = (ROOT / "desktop" / "capture" / "CaptureOverlayWindow.qml").read_text()
        self.assertIn("WlrKeyboardFocus.Exclusive", overlay)
        self.assertIn("HyprlandFocusGrab", overlay)
        self.assertIn('sequence: "Escape"', overlay)
        self.assertIn("onActivated: CaptureService.hide()", overlay)

    def test_capture_toolbar_and_menus_follow_the_shared_dark_theme(self):
        theme = (ROOT / "desktop" / "capture" / "ThemeService.qml").read_text()
        toolbar = (ROOT / "desktop" / "capture" / "CaptureToolbarWindow.qml").read_text()
        option_row = (ROOT / "desktop" / "capture" / "CaptureOptionRow.qml").read_text()
        picker = (ROOT / "desktop" / "capture" / "CaptureFolderPicker.qml").read_text()

        self.assertIn("Nc.ThemeService.isDark", theme)
        self.assertIn("ThemeService.toolbarBg", toolbar)
        self.assertIn("ThemeService.popupBg", toolbar)
        self.assertIn("ThemeService.textPrimary", option_row)
        self.assertIn("ThemeService.textPrimary", picker)

    def test_options_and_folder_popups_own_their_full_pointer_surface(self):
        toolbar = (ROOT / "desktop" / "capture" / "CaptureToolbarWindow.qml").read_text()
        hit_slop = (ROOT / "desktop" / "capture" / "CaptureHitSlop.qml").read_text()
        self.assertIn("id: optionsInput", toolbar)
        self.assertIn("id: folderInput", toolbar)
        self.assertGreaterEqual(toolbar.count("acceptedButtons: Qt.AllButtons"), 2)
        self.assertGreaterEqual(toolbar.count("cursorShape: Qt.ArrowCursor"), 2)
        self.assertIn("optionsInput.containsMouse", toolbar)
        self.assertIn("folderInput.containsMouse", toolbar)
        self.assertIn("enabled: CaptureService.optionsOpen && !CaptureService.recording", toolbar)
        self.assertIn("enabled: CaptureService.folderPickerOpen", toolbar)
        for target in ("toolbarCard", "optionsCard", "folderCard"):
            self.assertIn(f"targetItem: {target}", toolbar)
        self.assertEqual(toolbar.count("extent: 5"), 3)
        self.assertIn("property real extent: 5", hit_slop)
        self.assertIn("acceptedButtons: Qt.AllButtons", hit_slop)

    def test_camera_cursor_is_half_sized(self):
        overlay = (ROOT / "desktop" / "capture" / "CaptureOverlayWindow.qml").read_text()
        self.assertIn("width: 17", overlay)
        self.assertIn("height: 14", overlay)
        self.assertIn("width: 15.5; height: 10.5", overlay)
        self.assertNotIn("width: 34", overlay)
        self.assertNotIn("height: 28", overlay)


if __name__ == "__main__":
    unittest.main()
