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
                    let monitor = Hyprland.monitorFor(root.screen)
                    if (!monitor || !modelData.monitor) return true
                    return modelData.monitor.name === monitor.name
                }
            }
        }
    }
}
