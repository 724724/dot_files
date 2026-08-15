import Quickshell
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    property var screen: null
    property real windowOriginX: 0
    // 전체화면 오버레이에서는 알약+아이콘 대신 macOS식 작은 점으로 축소한다.
    property bool dotMode: false
    readonly property bool cameraInUse: PrivacyService.cameraActive
    readonly property bool micInUse: PrivacyService.micActive
    readonly property bool micOpenHere:
        PrivacyService.micModeOpen && PrivacyService.micModeScreen === root.screen
    readonly property bool cameraOpenHere:
        PrivacyService.cameraPopupOpen && PrivacyService.cameraPopupScreen === root.screen
    // Expose the two independently drawn controls to Bar's input mask. Masking
    // this whole RowLayout would make the transparent spacing between them eat
    // clicks intended for a window underneath the bar.
    readonly property Item micHitTarget: micButton.visible && !root.dotMode ? micButton : null
    readonly property Item cameraHitTarget: cameraButton.visible && !root.dotMode ? cameraButton : null
    readonly property string iconBase: {
        let x = Quickshell.env("XDG_CONFIG_HOME")
        let c = (x && x !== "") ? x : (Quickshell.env("HOME") + "/.config")
        return "file://" + c + "/quickshell/assets/sf-symbols/"
    }

    spacing: cameraInUse && micInUse ? (dotMode ? 5 : 7) : 0
    implicitHeight: 33

    Behavior on spacing { AppleSpring { spring: 18; epsilon: 0.1 } }

    function screenX(item) {
        let p = item.mapToItem(null, item.width / 2, item.height)
        return root.windowOriginX + p.x
    }

    component PrivacyButton: Item {
        id: button
        property bool inUse: false
        property bool dot: false
        property bool selected: false
        property color accent: "#34C759"
        property string glyph: ""
        property url iconSource: ""
        signal activated

        visible: opacity > 0.002
        opacity: inUse ? 1 : 0
        implicitWidth: inUse ? (dot ? 14 : 39) : 0
        implicitHeight: 33
        clip: true
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight

        Behavior on opacity { AppleSpring { spring: 18 } }
        Behavior on implicitWidth { AppleSpring { spring: 18; epsilon: 0.1 } }

        Rectangle {
            id: pill
            anchors.centerIn: parent
            width: button.dot ? 8 : 39
            height: button.dot ? 8 : 25
            radius: button.dot ? 4 : 13
            color: button.accent
            border.color: Qt.rgba(1, 1, 1, ThemeService.isDark ? 0.3 : 0.65)
            border.width: 1
            scale: buttonTap.pressed ? ThemeService.pressScale : 1
            transformOrigin: Item.Center

            Behavior on scale { AppleSpring { spring: 13 } }
            Behavior on width { AppleSpring { spring: 18; epsilon: 0.1 } }
            Behavior on height { AppleSpring { spring: 18; epsilon: 0.1 } }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 12
                color: "#ffffff"
                visible: !button.dot
                opacity: buttonHover.hovered || button.selected ? 0.10 : 0
                Behavior on opacity { AppleSpring { spring: 18 } }
            }

            Text {
                anchors.centerIn: parent
                visible: !button.dot && button.glyph !== ""
                text: button.glyph
                color: "#ffffff"
                font.family: "JetBrainsMono Nerd Font Propo"
                font.pixelSize: 13
            }

            Image {
                anchors.centerIn: parent
                visible: !button.dot && button.iconSource.toString() !== ""
                source: button.iconSource
                width: 11
                height: 13
                sourceSize.width: 34
                sourceSize.height: 40
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
        }

        // 점 모드는 macOS처럼 표시 전용이다 — 호버 커서도, 탭도 받지 않는다.
        HoverHandler {
            id: buttonHover
            enabled: button.inUse && !button.dot
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: buttonTap
            enabled: button.inUse && !button.dot
            acceptedButtons: Qt.LeftButton
            onTapped: button.activated()
        }
    }

    PrivacyButton {
        id: micButton
        inUse: root.micInUse
        dot: root.dotMode
        selected: root.micOpenHere
        accent: ThemeService.isDark ? "#FF9F0A" : "#FF9500"
        iconSource: root.iconBase + "mic.fill.png"
        onActivated: {
            let opening = !root.micOpenHere
            PrivacyService.cameraPopupOpen = false
            PrivacyService.micModeAnchorX = root.screenX(micButton)
            PrivacyService.micModeScreen = root.screen
            PrivacyService.micModeOpen = opening
        }
    }

    PrivacyButton {
        id: cameraButton
        inUse: root.cameraInUse
        dot: root.dotMode
        selected: root.cameraOpenHere
        accent: ThemeService.isDark ? "#30D158" : "#34C759"
        glyph: "󰕧"
        onActivated: {
            let opening = !root.cameraOpenHere
            PrivacyService.micModeOpen = false
            PrivacyService.cameraPopupAnchorX = root.screenX(cameraButton)
            PrivacyService.cameraPopupScreen = root.screen
            PrivacyService.cameraPopupOpen = opening
        }
    }
}
