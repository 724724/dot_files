import Quickshell
import QtQuick

Item {
    id: root
    readonly property bool micInUse: PrivacyService.micActive
    implicitHeight: 33
    implicitWidth: micInUse ? 10 : 0

    Item {
        id: micDot
        visible: root.micInUse
        x: 0
        y: 0
        width: 10
        height: 33

        Rectangle {
            anchors.centerIn: parent
            width: 8
            height: 8
            radius: 4
            color: "#FF9F0A"
            border.color: Qt.rgba(1, 1, 1, ThemeService.isDark ? 0.34 : 0.72)
            border.width: 1
        }
    }

}
