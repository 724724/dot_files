import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts
import "../nc" as Nc

Rectangle {
    id: root
    required property var window

    // RunCat lives inside the pill, so the pill also shows when only RunCat is on.
    readonly property bool runcatOn: Nc.SysUsageService.runcatEnabled

    color: ThemeService.pillBg
    border.color: ThemeService.pillBorder
    border.width: 1
    radius: 999
    implicitHeight: 33
    implicitWidth: (trayRepeater.count > 0 || runcatOn) ? row.implicitWidth + 12 : 0
    visible: trayRepeater.count > 0 || runcatOn

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 3

        RunCatWidget { Layout.alignment: Qt.AlignVCenter }

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
