import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property var window

    color: Qt.rgba(30/255, 40/255, 50/255, 0.25)
    border.color: Qt.rgba(100/255, 210/255, 180/255, 0.3)
    border.width: 1
    radius: 999
    implicitHeight: 33
    implicitWidth: trayRepeater.count > 0 ? row.implicitWidth + 12 : 0
    visible: trayRepeater.count > 0

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            id: trayRepeater
            model: SystemTray.items
            delegate: TrayItem {
                required property var modelData
                item: modelData
                window: root.window
            }
        }
    }
}
