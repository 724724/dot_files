import pathlib
import unittest


ROOT = pathlib.Path(__file__).parents[2]


class DockTrashTests(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_files_is_a_permanent_dock_item(self):
        source = self.read("desktop/dock/DockService.qml")
        self.assertIn('fileManagerClass: "org.gnome.nautilus"', source)
        self.assertIn('execCmd: ["gtk-launch", "org.gnome.Nautilus"]', source)
        self.assertIn("if (root.isPermanent(cls)) return", source)
        self.assertIn("normalized.unshift(root.fileManagerApp)", source)

    def test_unpinned_running_apps_are_between_separator_and_trash(self):
        source = self.read("desktop/dock/DockWindow.qml")
        pinned_apps = source.index("model: win.pinnedApps")
        divider = source.index("id: utilitySeparator", pinned_apps)
        running_apps = source.index("model: win.extraApps", divider)
        trash = source.index("TrashItem {", divider)
        self.assertLess(pinned_apps, divider)
        self.assertLess(divider, running_apps)
        self.assertLess(running_apps, trash)
        self.assertNotIn("dockSeparatorVisible", source)

    def test_drag_unpins_at_the_rendered_separator_boundary(self):
        source = self.read("desktop/dock/DockWindow.qml")
        update = source[source.index("function updateDrag"):
                        source.index("function endDrag")]
        self.assertIn("utilitySeparator.mapToItem(dockRow,", update)
        self.assertIn("? separatorCenter.x : separatorCenter.y", update)
        self.assertIn("if (cursorAxis < separatorAxis)", update)
        self.assertIn("win.dropIndex = -1", update)
        self.assertNotIn("n * win.pitch + 7", update)
        end = source[source.index("function endDrag"):
                     source.index("// ── Right-click menu state")]
        self.assertIn("if (drop < 0) win.unpinApp", end)

    def test_trash_drop_accepts_only_local_file_urls(self):
        source = self.read("desktop/dock/TrashItem.qml")
        self.assertIn('value.startsWith("file://")', source)
        self.assertIn('["gio", "trash", "--force", "--"]', source)
        self.assertIn("drop.acceptProposedAction()", source)
        self.assertIn('["nautilus", "--new-window", "trash:///"]', source)

    def test_dock_geometry_is_persisted_as_portable_preferences(self):
        source = self.read("desktop/dock/DockService.qml")
        self.assertIn('property string dockEdge: "bottom"', source)
        self.assertIn('property real dockSizeLevel: 0.24', source)
        self.assertIn('path: Quickshell.stateDir + "/dock-edge.txt"', source)
        self.assertIn('path: Quickshell.stateDir + "/dock-size-level.txt"', source)
        self.assertIn('function setDockEdge(edge)', source)
        self.assertIn('function setDockSizeLevel(level)', source)

    def test_separator_drag_has_reduced_screen_aware_hard_limits(self):
        source = self.read("desktop/dock/DockWindow.qml")
        self.assertIn("readonly property real screenShortSide", source)
        self.assertIn("readonly property real minimumIconSize", source)
        self.assertIn("readonly property real maximumIconSize", source)
        self.assertIn("Math.max(24,", source)
        self.assertIn("Math.min(32, screenShortSide * 0.022)", source)
        self.assertIn("Math.max(48,", source)
        self.assertIn("Math.min(66, screenShortSide * 0.045)", source)
        self.assertNotIn("function _rubberband", source)
        self.assertNotIn("function _boundedIconSize", source)
        self.assertIn("function beginSizeDrag", source)
        self.assertIn("function updateSizeDrag", source)
        self.assertIn("function endSizeDrag", source)
        update = source[source.index("function updateSizeDrag"):
                        source.index("function endSizeDrag")]
        self.assertIn("Math.max(minimumIconSize,", update)
        self.assertIn("Math.min(maximumIconSize,", update)
        self.assertIn("DockService.setDockSizeLevel(level)", source)
        self.assertIn("sizeDragStartPoint.y - point.y", source)

    def test_separator_menu_can_place_dock_on_each_supported_edge(self):
        source = self.read("desktop/dock/DockWindow.qml")
        self.assertIn('{ id: "edge-bottom", label: "Position on Bottom"', source)
        self.assertIn('{ id: "edge-left", label: "Position on Left"', source)
        self.assertIn('{ id: "edge-right", label: "Position on Right"', source)
        self.assertIn('win.openUtilityMenu("position"', source)
        self.assertIn("DockService.setDockEdge(id.slice(5))", source)
        self.assertIn("flow: win.horizontalDock ? Grid.LeftToRight : Grid.TopToBottom", source)
        card = source[source.index("id: dockCard"):source.index("id: dockRow")]
        self.assertIn("width: win.horizontalDock", card)
        self.assertIn("height: win.horizontalDock", card)
        self.assertIn("x: win.horizontalDock", card)
        self.assertIn("y: win.horizontalDock", card)
        self.assertNotIn("implicitWidth: win.horizontalDock", card)
        self.assertNotIn("implicitHeight: win.horizontalDock", card)
        self.assertNotIn("anchors.horizontalCenter:", card)
        self.assertNotIn("anchors.verticalCenter:", card)

    def test_trash_empty_action_requires_confirmation(self):
        window = self.read("desktop/dock/DockWindow.qml")
        trash = self.read("desktop/dock/TrashItem.qml")
        self.assertIn('{ id: "trash-empty", label: "Empty Trash…"', window)
        self.assertIn('{ id: "confirm-empty", label: "Empty Trash", destructive: true }', window)
        self.assertIn("trashItem.emptyTrash()", window)
        self.assertIn('["gio", "trash", "--empty"]', trash)

    def test_all_dock_popups_dismiss_immediately_with_short_exit_motion(self):
        source = self.read("desktop/dock/DockWindow.qml")
        self.assertIn("readonly property int popupEnterDuration: 135", source)
        self.assertIn("readonly property int popupExitDuration: 90", source)
        self.assertIn("onPressed: win.closeUtilityMenu()", source)
        self.assertIn("onPressed: win.closeMenu()", source)
        self.assertIn("onPressed: win.previewOpen = false", source)
        for popup_id in (
            "id: utilityPopup",
            "id: previewPopup",
            "id: menuPopup",
            "id: submenuFlyout",
        ):
            start = source.index(popup_id)
            popup_header = source[start:start + 1000]
            self.assertIn("NumberAnimation", popup_header)
            self.assertIn("win.popupExitDuration", popup_header)
            self.assertNotIn("AppleSpring { spring: 11 }", popup_header)

    def test_trash_state_updates_immediately_and_watches_external_changes(self):
        source = self.read("desktop/dock/TrashItem.qml")
        empty = source[source.index("function emptyTrash()"):
                       source.index("function refreshTrashState()")]
        self.assertLess(empty.index("trashFull = false"),
                        empty.index('trashProc.command = ["gio", "trash", "--empty"]'))
        self.assertIn('["gio", "monitor", "--dir=" + item.trashFilesPath]', source)
        self.assertIn("stdout: SplitParser", source)
        self.assertIn("item.trashFull = !item.emptyOperation", source)

    def test_separator_has_a_centered_safe_hit_slot(self):
        window = self.read("desktop/dock/DockWindow.qml")
        item = self.read("desktop/dock/DockItem.qml")
        separator = window[window.index("id: utilitySeparator"):
                           window.index("TrashItem {", window.index("id: utilitySeparator"))]
        self.assertIn("? Math.max(28, 24 * win.dockScale) : 66 * win.dockScale", separator)
        self.assertIn("? 66 * win.dockScale : Math.max(28, 24 * win.dockScale)", separator)
        self.assertIn("anchors.centerIn: parent", separator)
        self.assertIn("onContainsMouseChanged:", separator)
        self.assertIn("win.separatorHoverActive = separatorMouse.containsMouse", separator)
        self.assertIn("dockWin.separatorInteractionActive", item)

    def test_pinned_to_unpinned_drag_animates_a_real_landing_gap(self):
        window = self.read("desktop/dock/DockWindow.qml")
        item = self.read("desktop/dock/DockItem.qml")
        self.assertIn("readonly property bool pinnedUnpinDropActive", window)
        self.assertIn("readonly property real unpinSeparatorShift:", window)
        self.assertIn("pinnedUnpinDropActive ? -pitch : 0", window)
        separator = window[window.index("id: utilitySeparator"):
                           window.index("Running applications that are not kept")]
        self.assertIn("win.pinSeparatorShift + win.unpinSeparatorShift", separator)
        self.assertIn("enabled: win.dragActive", separator)
        self.assertIn("pinnedIndex > src ? -dockWin.pitch : 0", item)

    def test_unpinned_to_pinned_drag_closes_source_gap_symmetrically(self):
        window = self.read("desktop/dock/DockWindow.qml")
        item = self.read("desktop/dock/DockItem.qml")
        self.assertIn("property int dragSourceTransientIndex: -1", window)
        self.assertIn("readonly property real pinSeparatorShift:", window)
        self.assertIn("nativePinDropActive ? pitch : 0", window)
        self.assertIn("property int transientIndex: -1", item)
        self.assertIn("readonly property real transientPinShift:", item)
        self.assertIn("transientIndex < dockWin.dragSourceTransientIndex", item)
        self.assertIn("item.pinnedIndex, item.transientIndex", item)
        self.assertNotIn("nativePinGap", window)
        self.assertNotIn("nativePinShift", item)

    def test_running_indicator_uses_explicit_small_geometry_on_side_docks(self):
        source = self.read("desktop/dock/DockItem.qml")
        indicator = source[source.index("id: runningIndicator"):
                           source.index("// Hyprland's new dispatcher API")]
        self.assertIn("x: item.horizontalDock", indicator)
        self.assertIn("y: item.horizontalDock", indicator)
        self.assertNotIn("anchors.left:", indicator)
        self.assertNotIn("anchors.right:", indicator)
        self.assertNotIn("anchors.bottom:", indicator)

    def test_icon_zoom_toggle_and_slider_are_persisted(self):
        service = self.read("desktop/dock/DockService.qml")
        window = self.read("desktop/dock/DockWindow.qml")
        self.assertIn("property bool iconZoomEnabled: true", service)
        self.assertIn("property real iconZoomScale: 1.75", service)
        self.assertIn('path: Quickshell.stateDir + "/dock-icon-zoom-enabled.txt"', service)
        self.assertIn('path: Quickshell.stateDir + "/dock-icon-zoom-scale.txt"', service)
        self.assertIn('{ id: "zoom-toggle", label: "Icon Zoom", toggle: true', window)
        self.assertIn('{ id: "zoom-slider", label: "Zoom Amount", slider: true }', window)
        self.assertIn("DockService.previewIconZoomScale", window)
        self.assertIn("DockService.commitIconZoomScale", window)

    def test_tooltips_follow_the_live_icon_edge_at_a_fixed_gap(self):
        for relative in (
            "desktop/dock/DockItem.qml",
            "desktop/dock/TrashItem.qml",
        ):
            source = self.read(relative)
            self.assertIn("readonly property real tooltipGap: 8", source)
            self.assertIn("item.iconInset", source)
            self.assertIn("item.baseIconSize * item.", source)
            self.assertNotIn("tooltipMargin", source)
        item = self.read("desktop/dock/DockItem.qml")
        tooltip = item[item.index("id: tooltip"):
                       item.index("id: runningIndicator")]
        self.assertNotIn("zoomInteractionAllowed && hover.hovered", tooltip)
        self.assertIn("tooltipInteractionAllowed && hover.hovered", tooltip)
        self.assertIn("item.baseIconSize * item.iconScale", tooltip)

    def test_icons_keep_square_geometry_and_preserve_source_aspect_ratio(self):
        icon = self.read("desktop/icons/AppIcon.qml")
        self.assertIn("fillMode: Image.PreserveAspectFit", icon)
        for relative, item_id in (
            ("desktop/dock/DockItem.qml", "id: iconImg"),
            ("desktop/dock/TrashItem.qml", "id: trashIcon"),
        ):
            source = self.read(relative)
            block = source[source.index(item_id):source.index("transform:", source.index(item_id))]
            self.assertIn("width: item.baseIconSize", block)
            self.assertIn("height: item.baseIconSize", block)
            self.assertIn("x: item.horizontalDock", block)
            self.assertIn("y: item.horizontalDock", block)
            self.assertNotIn("anchors.left:", block)
            self.assertNotIn("anchors.right:", block)

    def test_launchpad_and_overview_reserve_the_current_dock_thickness(self):
        for relative in (
            "desktop/launchpad/LaunchpadWindow.qml",
            "desktop/missioncontrol/MissionControlWindow.qml",
        ):
            source = self.read(relative)
            self.assertIn("Dock.DockService.dockSizeLevel", source)
            self.assertIn("readonly property int dockReserve: Math.ceil(", source)
            self.assertIn("Math.min(32, dockShortSide * 0.022)", source)
            self.assertIn("Math.min(66, dockShortSide * 0.045)", source)
            self.assertIn("Dock.DockService.dockEdge === \"left\"", source)
            self.assertIn("Dock.DockService.dockEdge === \"right\"", source)

    def test_launch_bounce_speed_is_independent_of_dock_size_and_zoom(self):
        source = self.read("desktop/dock/DockItem.qml")
        launch = source[source.index("property real launchProgress"):
                        source.index("// Safety: if this icon is torn down")]
        self.assertIn("16 * densityScale * launchProgress", launch)
        self.assertIn("SequentialAnimation on launchProgress", launch)
        self.assertIn("duration: 560", launch)
        self.assertIn("loops: Animation.Infinite", launch)
        self.assertNotIn("AppleSpring", launch)
        self.assertNotIn("iconZoomScale", launch)

        icon_transform = source[source.index("transform: [", source.index("id: iconImg")):
                                source.index("// App-name tooltip")]
        self.assertIn("x: item.horizontalDock ? 0", icon_transform)
        self.assertIn("y: item.horizontalDock ? -item.launchOffset : 0", icon_transform)
        launch_translate = icon_transform[:icon_transform.index("},", icon_transform.index("Translate {"))]
        self.assertNotIn("Behavior on x", launch_translate)
        self.assertNotIn("Behavior on y", launch_translate)


if __name__ == "__main__":
    unittest.main()
