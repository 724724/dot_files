import Quickshell
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    property var screen: null
    spacing: 7
    implicitHeight: 33
    implicitWidth: micDot.implicitWidth + cameraPill.implicitWidth + (micDot.visible && cameraPill.visible ? spacing : 0)

    Item {
        id: micDot
        visible: PrivacyService.micActive
        implicitWidth: visible ? 10 : 0
        implicitHeight: 33
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight

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

    Rectangle {
        id: cameraPill
        visible: PrivacyService.cameraActive
        implicitWidth: visible ? 39 : 0
        implicitHeight: 25
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight
        Layout.alignment: Qt.AlignVCenter
        radius: 13
        color: cameraHover.hovered || PrivacyService.popupVisible ? "#30D158" : "#34C759"
        border.color: Qt.rgba(1, 1, 1, ThemeService.isDark ? 0.3 : 0.65)
        border.width: 1
        scale: cameraTap.pressed ? ThemeService.pressScale : 1
        transformOrigin: Item.Center

        Behavior on scale { AppleSpring { spring: 13 } }
        Behavior on implicitWidth { AppleSpring { spring: 14 } }

        Text {
            anchors.centerIn: parent
            text: "󰖠"
            color: "#ffffff"
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 13
        }

        HoverHandler {
            id: cameraHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            id: cameraTap
            onTapped: {
                let w = root.QsWindow.window
                if (!w) return
                let p = w.contentItem.mapFromItem(cameraPill, cameraPill.width / 2, 0)
                PrivacyService.anchorX = p.x + 10
                PrivacyService.targetScreen = root.screen
                PrivacyService.popupVisible = !PrivacyService.popupVisible
            }
        }
    }
}
