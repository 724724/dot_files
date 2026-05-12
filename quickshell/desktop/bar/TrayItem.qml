import Quickshell
import Quickshell.Services.SystemTray
import QtQuick

Rectangle {
    id: trayItem
    required property SystemTrayItem item
    required property var window  // kept for API compat with TrayWidget caller

    implicitWidth: 22
    implicitHeight: 33
    color: mouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
    radius: 4
    Behavior on color { ColorAnimation { duration: 150 } }

    Image {
        id: iconImg
        anchors.centerIn: parent
        width: 14
        height: 14
        sourceSize.width: 14
        sourceSize.height: 14
        smooth: true
        mipmap: true
        fillMode: Image.PreserveAspectFit
        source: {
            let icon = trayItem.item.icon
            if (!icon) return ""
            if (icon.includes("://")) return icon
            return "image://icon/" + icon
        }

        onStatusChanged: {
            if (status === Image.Error)
                source = "image://icon/application-x-executable"
        }
    }

    // Anchor needs anchor.window (the parent QsWindow) AND a screen-space rect
    // computed via mapFromItem — without those the platform menu has no valid
    // position and silently never opens.
    QsMenuAnchor {
        id: menuAnchor
        menu: trayItem.item.menu
        anchor.window: trayItem.QsWindow.window

        anchor.onAnchoring: {
            const win = trayItem.QsWindow.window
            if (!win) return
            menuAnchor.anchor.rect = win.contentItem.mapFromItem(
                trayItem,
                0, trayItem.height,
                trayItem.width, trayItem.height
            )
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: function (mouse) {
            if (trayItem.item.onlyMenu || mouse.button === Qt.RightButton) {
                menuAnchor.open()
            } else if (mouse.button === Qt.LeftButton) {
                trayItem.item.activate()
            } else {
                trayItem.item.secondaryActivate()
            }
        }

        // Forward scroll events for items that use them (volume mixers etc.)
        onWheel: function (wheel) {
            trayItem.item.scroll(wheel.angleDelta.y, false)
        }
    }
}
