import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PillContainer {
    id: root
    clickable: true
    implicitHeight: 33
    implicitWidth: row.implicitWidth + 24

    readonly property bool isDnd: SwayncService.dnd
    readonly property bool hasNotif: SwayncService.notifCount > 0

    Process {
        id: toggleProc
        command: ["qs", "ipc", "-c", "desktop", "call", "nc", "toggle"]
    }

    Process {
        id: dndProc
        command: ["qs", "ipc", "-c", "desktop", "call", "nc", "dnd"]
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: toggleProc.running = true
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: dndProc.running = true
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 0

        Item {
            implicitWidth: notifIcon.implicitWidth
            implicitHeight: notifIcon.implicitHeight

            Text {
                id: notifIcon
                text: root.isDnd ? "󰂛" : "󰂚"
                color: "#d4f1e8"
                font.family: "JetBrainsMono Nerd Font Propo"
                font.pixelSize: 14
            }

            Rectangle {
                visible: root.hasNotif
                width: 6
                height: 6
                radius: 3
                color: "#ff6b9d"
                anchors.top: notifIcon.top
                anchors.right: notifIcon.right
                anchors.rightMargin: -1
                anchors.topMargin: 1
            }
        }
    }
}
