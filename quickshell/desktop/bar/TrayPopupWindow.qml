import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import QtQuick
import Qt5Compat.GraphicalEffects

PanelWindow {
    id: win

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "qs-tray-popup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property bool shown: TrayService.popupOpen
    readonly property bool dark: ThemeService.isDark
    property bool _surfaceVisible: false
    visible: _surfaceVisible

    Connections {
        target: TrayService
        function onPopupOpenChanged() {
            if (TrayService.popupOpen) {
                if (TrayService.popupScreen)
                    win.screen = TrayService.popupScreen
                win._surfaceVisible = true
            }
        }
        function onPopupScreenChanged() {
            if (TrayService.popupOpen && TrayService.popupScreen)
                win.screen = TrayService.popupScreen
        }
    }

    onVisibleChanged: if (visible) focusScope.forceActiveFocus()

    FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: TrayService.popupOpen = false

        MouseArea {
            anchors.fill: parent
            onClicked: TrayService.popupOpen = false
        }

        Rectangle {
            id: card
            readonly property real naturalHeight: iconGrid.implicitHeight + 24

            width: 204
            height: Math.min(naturalHeight,
                win.height - BarState.contentTop - 10)
            x: Math.max(10, Math.min(
                TrayService.popupAnchorX - width + 20,
                win.width - width - 10))
            y: win.shown ? BarState.contentTop : BarState.contentTop - 8
            radius: 16
            color: ThemeService.popupBg
            border.width: 1
            border.color: ThemeService.stroke
            transformOrigin: Item.TopRight
            opacity: win.shown ? 1 : 0
            scale: win.shown ? 1 : 0.965
            visible: opacity > 0.002
            z: 10

            Behavior on opacity { AppleSpring { spring: 18 } }
            Behavior on scale { AppleSpring { spring: 18 } }
            Behavior on y { AppleSpring { spring: 18 } }
            onOpacityChanged: {
                if (!win.shown && opacity <= 0.002)
                    win._surfaceVisible = false
            }

            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                radius: 16
                samples: 33
                verticalOffset: 6
                color: Qt.rgba(0, 0, 0, win.dark ? 0.46 : 0.24)
            }

            MouseArea { anchors.fill: parent }

            Flickable {
                anchors.fill: parent
                anchors.margins: 12
                contentWidth: width
                contentHeight: iconGrid.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Grid {
                    id: iconGrid
                    width: parent.width
                    columns: 5
                    spacing: 5

                    Repeater {
                        model: SystemTray.items

                        delegate: Item {
                            required property var modelData
                            width: 32
                            height: 32

                            TrayItem {
                                anchors.fill: parent
                                item: modelData
                                window: win
                                iconSize: 16
                                cornerRadius: 8
                            }
                        }
                    }
                }
            }
        }
    }
}
