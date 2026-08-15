import Quickshell
import Quickshell.Wayland
import QtQuick
import Qt5Compat.GraphicalEffects

PanelWindow {
    id: win

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "qs-camera-status"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property bool dark: ThemeService.isDark
    readonly property bool shown:
        PrivacyService.cameraPopupOpen && PrivacyService.cameraActive
    readonly property color cardBg: ThemeService.popupBg
    readonly property color cardBorder: ThemeService.stroke
    readonly property color primaryText: dark ? "#ffffff" : "#1a1a1a"
    readonly property color secondaryText:
        dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.55)
    readonly property color cameraGreen: dark ? "#30D158" : "#34C759"
    readonly property string cameraOwners: {
        let apps = PrivacyService.cameraApps || []
        let names = []
        for (let i = 0; i < apps.length; i++) {
            if (apps[i] && apps[i].name) names.push(String(apps[i].name))
        }
        return names.length > 0 ? names.join(", ") : "Camera in use"
    }

    property bool _surfaceVisible: false
    visible: _surfaceVisible

    Connections {
        target: PrivacyService
        function onCameraPopupOpenChanged() {
            if (PrivacyService.cameraPopupOpen) {
                if (PrivacyService.cameraPopupScreen)
                    win.screen = PrivacyService.cameraPopupScreen
                win._surfaceVisible = true
            }
        }
        function onCameraPopupScreenChanged() {
            if (PrivacyService.cameraPopupOpen && PrivacyService.cameraPopupScreen)
                win.screen = PrivacyService.cameraPopupScreen
        }
    }

    onVisibleChanged: if (visible) focusScope.forceActiveFocus()

    FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: PrivacyService.cameraPopupOpen = false

        MouseArea {
            anchors.fill: parent
            onClicked: PrivacyService.cameraPopupOpen = false
        }

        Rectangle {
            id: card
            width: 292
            height: content.implicitHeight + 32
            x: Math.max(10, Math.min(PrivacyService.cameraPopupAnchorX - width / 2,
                                     win.width - width - 10))
            y: win.shown ? BarState.contentTop : (BarState.contentTop - 8)
            radius: 18
            color: win.cardBg
            border.color: win.cardBorder
            border.width: 1
            z: 10
            opacity: win.shown ? 1 : 0
            scale: win.shown ? 1 : 0.97
            transformOrigin: Item.Top
            visible: opacity > 0.002

            Behavior on opacity { AppleSpring { spring: 18 } }
            Behavior on scale { AppleSpring { spring: 18 } }
            Behavior on y { AppleSpring { spring: 18 } }
            onOpacityChanged: if (!win.shown && opacity <= 0.002) win._surfaceVisible = false

            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                radius: 18
                samples: 37
                verticalOffset: 6
                color: Qt.rgba(0, 0, 0, win.dark ? 0.44 : 0.22)
            }

            MouseArea { anchors.fill: parent }

            Column {
                id: content
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 10

                Item {
                    width: parent.width
                    height: 42

                    Rectangle {
                        id: cameraBadge
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 38
                        height: 38
                        radius: 10
                        color: win.cameraGreen

                        Text {
                            anchors.centerIn: parent
                            text: "󰕧"
                            color: "#ffffff"
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 17
                        }
                    }

                    Column {
                        anchors.left: cameraBadge.right
                        anchors.leftMargin: 11
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            width: parent.width
                            text: win.cameraOwners
                            color: win.primaryText
                            elide: Text.ElideRight
                            font.family: "SF Pro Display"
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            font.letterSpacing: -0.15
                        }
                        Text {
                            text: PrivacyService.cameraApps.length > 0
                                ? "Using your camera" : "Camera access is active"
                            color: win.secondaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: win.cardBorder
                }

                Item {
                    width: parent.width
                    height: 40

                    Rectangle {
                        id: activeDot
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: win.cameraGreen
                    }

                    Column {
                        anchors.left: activeDot.right
                        anchors.leftMargin: 10
                        anchors.right: activeLabel.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            text: "Camera"
                            color: win.secondaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }
                        Text {
                            width: parent.width
                            text: PrivacyService.cameraName || "Camera"
                            color: win.primaryText
                            elide: Text.ElideRight
                            font.family: "SF Pro Display"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }

                    Text {
                        id: activeLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Active"
                        color: win.cameraGreen
                        font.family: "SF Pro Display"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }
}
