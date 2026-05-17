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
            model: Hyprland.workspaces
            delegate: WorkspaceButton {
                required property var modelData
                workspace: modelData
                visible: {
                    if (modelData.name.startsWith("special:")) return false
                    if (!modelData.monitor) return false
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
