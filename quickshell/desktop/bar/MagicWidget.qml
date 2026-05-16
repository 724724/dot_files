import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

PillContainer {
    id: root
    implicitHeight: 33
    implicitWidth: row.implicitWidth + 24
    visible: hasMagic

    readonly property bool hasMagic: MagicService.hasMagic

    color: hovered
        ? Qt.rgba(180/255, 140/255, 255/255, 0.65)
        : hasMagic
            ? Qt.rgba(180/255, 140/255, 255/255, 0.45)
            : Qt.rgba(30/255, 40/255, 50/255, 0.25)
    border.color: hasMagic || hovered
        ? Qt.rgba(180/255, 140/255, 255/255, 0.6)
        : Qt.rgba(100/255, 210/255, 180/255, 0.3)

    TapHandler {
        onTapped: Hyprland.dispatch('hl.dsp.workspace.toggle_special("magic")')
    }

    RowLayout {
        id: row
        anchors.centerIn: parent

        Text {
            text: "󰘔"
            color: root.hasMagic ? "#ffffff" : "#d4f1e8"
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 12

            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }
}
