import QtQuick
import QtQuick.Layouts
import "../nc" as Nc

PillContainer {
    id: root
    clickable: true
    pressed: leftTap.pressed || rightTap.pressed
    implicitHeight: 33
    implicitWidth: row.implicitWidth + 24

    // Bar and notification center share one qs process, so the widget reads
    // and drives the NcServer singleton directly — instant, with none of the
    // `qs ipc` subprocess latency the old toggles paid on every click.
    readonly property bool isDnd: Nc.NcServer.dnd
    readonly property bool hasNotif: Nc.NcServer.count > 0

    TapHandler {
        id: leftTap
        acceptedButtons: Qt.LeftButton
        onTapped: Nc.NcServer.controlCenterVisible = !Nc.NcServer.controlCenterVisible
    }

    TapHandler {
        id: rightTap
        acceptedButtons: Qt.RightButton
        onTapped: Nc.NcServer.toggleDnd()
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
                color: ThemeService.fg
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
