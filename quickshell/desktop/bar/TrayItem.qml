import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import Qt5Compat.GraphicalEffects

Rectangle {
    id: trayItem
    required property SystemTrayItem item
    required property var window  // kept for API compat with TrayWidget caller

    implicitWidth: 22
    implicitHeight: 33
    scale: mouseArea.pressed ? ThemeService.pressScale : 1
    transformOrigin: Item.Center
    color: mouseArea.containsMouse
        ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10))
        : "transparent"
    radius: 4
    Behavior on scale { AppleSpring { spring: 13 } }

    readonly property string iconSource: {
        let icon = trayItem.item.icon
        if (!icon) return ""
        if (icon.includes("://")) return icon
        return "image://icon/" + icon
    }

    // Only the monochrome system glyphs (nm-applet's nm-*, fcitx5's fcitx-*/
    // keyboard) render near-white and disappear on the light-mode pill. Recolour
    // just those; coloured app icons (KakaoTalk, Notion, Bluetooth…) are left as-is.
    readonly property bool monochrome: {
        let s = iconSource.toLowerCase()
        return s.indexOf("nm-") !== -1 || s.indexOf("fcitx") !== -1 || s.indexOf("keyboard") !== -1
    }
    readonly property bool recolor: monochrome && !ThemeService.isDark

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
        visible: !trayItem.recolor   // hidden only while the recoloured copy shows
        source: trayItem.iconSource

        onStatusChanged: {
            if (status === Image.Error)
                source = "image://icon/application-x-executable"
        }
    }

    // Dark recolour of the monochrome glyphs, shown only in light mode.
    ColorOverlay {
        anchors.fill: iconImg
        source: iconImg
        color: "#1c1c1e"
        visible: trayItem.recolor
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
