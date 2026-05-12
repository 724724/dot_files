import Quickshell
import QtQuick
import QtQuick.Layouts

PillContainer {
    id: root
    implicitHeight: 33
    implicitWidth: row.implicitWidth + 24

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Text {
            text: "󰥔"
            color: "#d4f1e8"
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 12
        }

        Text {
            text: Time.time
            color: "#d4f1e8"
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }
}
