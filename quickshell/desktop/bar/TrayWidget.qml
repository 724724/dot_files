import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts
import "../nc" as Nc

Rectangle {
    id: root
    required property var window

    // RunCat lives inside the pill, so the pill also shows when only RunCat is on.
    readonly property bool runcatOn: Nc.SysUsageService.runcatEnabled
    readonly property int systemIconLimit: Math.max(0, 4 - (runcatOn ? 1 : 0))
    readonly property bool hasOverflow:
        trayRepeater.count > systemIconLimit

    color: ThemeService.pillBg
    border.color: ThemeService.pillBorder
    border.width: 1
    radius: 999
    implicitHeight: 33
    // The Shazam button is always present, so the pill is always shown.
    implicitWidth: row.implicitWidth + 12
    Behavior on implicitWidth { AppleSpring { spring: 18; epsilon: 0.1 } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 3

        RunCatWidget { Layout.alignment: Qt.AlignVCenter }

        // Music Recognition (Shazam) — sits just right of RunCat.
        ShazamWidget {
            Layout.alignment: Qt.AlignVCenter
            screen: root.window ? root.window.screen : null
        }

        Repeater {
            id: trayRepeater
            model: SystemTray.items
            delegate: TrayItem {
                required property var modelData
                required property int index
                item: modelData
                window: root.window
                visible: index < root.systemIconLimit
                Layout.preferredWidth: visible ? implicitWidth : 0
                Layout.preferredHeight: visible ? implicitHeight : 0
            }
        }

        Item {
            id: overflowButton
            visible: root.hasOverflow
            Layout.preferredWidth: visible ? 22 : 0
            Layout.preferredHeight: 33

            Rectangle {
                anchors.centerIn: parent
                width: 22
                height: 22
                radius: 11
                color: overflowHover.hovered
                        || (TrayService.popupOpen
                            && TrayService.popupScreen === root.window.screen)
                    ? (ThemeService.isDark
                        ? Qt.rgba(1, 1, 1, 0.12)
                        : Qt.rgba(0, 0, 0, 0.10))
                    : "transparent"
                scale: overflowTap.pressed ? ThemeService.pressScale : 1
                Behavior on scale { AppleSpring { spring: 13 } }

                Text {
                    anchors.centerIn: parent
                    text: "󰅀"
                    color: ThemeService.fg
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.pixelSize: 13
                }
            }

            HoverHandler {
                id: overflowHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                id: overflowTap
                acceptedButtons: Qt.LeftButton
                onTapped: {
                    let w = root.window
                    if (!w) return
                    let p = w.contentItem.mapFromItem(
                        overflowButton,
                        overflowButton.width / 2,
                        overflowButton.height)
                    let sameScreen = TrayService.popupOpen
                        && TrayService.popupScreen === w.screen
                    TrayService.popupAnchorX = p.x + 10
                    TrayService.popupScreen = w.screen
                    TrayService.popupOpen = !sameScreen
                }
            }
        }
    }

    Connections {
        target: trayRepeater
        function onCountChanged() {
            if (!root.hasOverflow)
                TrayService.popupOpen = false
        }
    }

    onHasOverflowChanged: {
        if (!hasOverflow) TrayService.popupOpen = false
    }
}
