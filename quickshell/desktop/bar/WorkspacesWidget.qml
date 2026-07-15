import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

PillContainer {
    id: root
    required property var screen

    implicitHeight: 33
    implicitWidth: Math.max(row.implicitWidth, 10)

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            // Hyprland.workspaces has no ordering guarantee — it reflects the
            // order Hyprland reported workspaces in, so a freshly-created ws can
            // land out of sequence (e.g. 1,4,2,3). Sort a copy by id so the row
            // is always ascending.
            model: [...Hyprland.workspaces.values].sort((a, b) => a.id - b.id)
            delegate: WorkspaceButton {
                required property var modelData
                workspace: modelData
                visible: {
                    if (modelData.name.startsWith("special:")) return false
                    // Both can be transiently null during monitor/config reloads.
                    if (!modelData.monitor || !root.screen) return false
                    // Compare monitor names directly. Hyprland.monitorFor()
                    // can return null for the external screen in some setups,
                    // which previously caused the widget to fall through to
                    // "show all workspaces" on that bar.
                    return modelData.monitor.name === root.screen.name
                }
            }
        }
    }
}
